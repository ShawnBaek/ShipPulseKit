import Foundation
import ShipPulseKitCore
#if canImport(UIKit)
import UIKit
#endif
#if canImport(MetricKit) && !os(watchOS) && !os(tvOS)
import MetricKit
#endif

/// Connects the collection sources to sampling, ``UploadQueue`` and the uploader.
///
/// ``ShipPulseKit`` owns exactly one engine, created by ``ShipPulseKit/start(_:)``.
@MainActor
final class Engine {
    private let configuration: Configuration
    private let queue: UploadQueue
    private let uploader: any RecordUploading
    private let retention: RetentionTracker
    private let context: RecordContext
    private let defaults: UserDefaults
    private var isFlushing = false
    private var flushRequested = false

    private enum Key {
        static let sampleRate = "ShipPulseKit.sampleRate"
        static let diagnosticSampleRate = "ShipPulseKit.diagnosticSampleRate"
        static let configFetchedAt = "ShipPulseKit.configFetchedAt"
    }

    /// Creates an engine.
    ///
    /// - Parameters:
    ///   - configuration: The options passed to ``ShipPulseKit/start(_:)``.
    ///   - queue: The outbox. `nil` uses the default directory; tests pass a temporary one.
    ///   - uploader: The transport. `nil` uses ``CloudKitUploader``.
    ///   - defaults: Storage for the install ID and sampling rates.
    ///   - context: Device and app fields stamped on every record.
    /// - Throws: ``ShipPulseKitError/iCloudContainerUnavailable(containerIdentifier:reason:)``
    ///   when ``CloudKitUploader`` can't open the container.
    init(
        configuration: Configuration,
        queue: UploadQueue? = nil,
        uploader: (any RecordUploading)? = nil,
        defaults: UserDefaults = .standard,
        context: RecordContext = DeviceContext.current()
    ) throws(ShipPulseKitError) {
        self.configuration = configuration
        self.queue = queue ?? UploadQueue(directory: UploadQueue.defaultDirectory(), maxAge: configuration.maxQueueAge, maxCount: configuration.maxQueuedRecords)
        if let uploader {
            self.uploader = uploader
        } else {
            self.uploader = try CloudKitUploader(configuration: configuration)
        }
        self.defaults = defaults
        self.retention = RetentionTracker(defaults: defaults)
        self.context = context
    }

    #if canImport(MetricKit) && !os(watchOS) && !os(tvOS)
    private var collector: MetricKitCollector?
    var metricManager: MetricManager? { collector?.manager }
    #endif

    /// Starts MetricKit collection, screen tracking and retention, then uploads.
    func start() {
        #if canImport(MetricKit) && !os(watchOS) && !os(tvOS)
        let collector = MetricKitCollector(stateReportingDomains: configuration.additionalStateDomains.union([Schema.screenDomain]))
        let fallback = context
        #if !os(visionOS)
        if configuration.collectsMetrics {
            let installID = retention.installID()
            collector.startMetrics { [weak self] report in
                let record = PayloadMapper.summaryRecord(
                    report: ReportMapper.dailyReport(from: report),
                    rawJSON: try? JSONEncoder().encode(report),
                    begin: report.timeRange.start,
                    end: report.timeRange.end,
                    installID: installID,
                    context: Self.context(fallback, report.environment.map { ($0.deviceType, $0.osVersion.number, $0.applicationBuildVersion, $0.latestApplicationVersion) }),
                    now: Date()
                )
                await self?.enqueue([record])
            }
        }
        #endif
        if configuration.collectsDiagnostics {
            collector.startDiagnostics { [weak self] report in
                let fields = ReportMapper.diagnosticFields(report)
                let env = report.environment
                guard let encoded = try? JSONEncoder().encode(report),
                      let json = PayloadMapper.redactedDiagnosticJSON(encoded) else { return }
                let record = PayloadMapper.diagnosticRecord(
                    json: json,
                    kind: fields.kind,
                    durationMs: fields.durationMs,
                    extraFields: fields.extra,
                    isTestFlight: env.isTestFlightApp,
                    begin: report.timeRange.start,
                    end: report.timeRange.end,
                    context: Self.context(fallback, (env.deviceType, env.osVersion.number, env.applicationBuildVersion, env.applicationVersion)),
                    now: Date()
                )
                await self?.enqueue([record])
            }
        }
        self.collector = collector
        #endif
        #if canImport(UIKit) && !os(watchOS)
        if configuration.automaticScreenTracking { AutomaticScreenTracking.install() }
        #endif
        recordActivity()
        observeForeground()
        Task {
            await refreshSamplingConfig()
            await flush()
        }
    }

    /// The record context for a report.
    ///
    /// A report can describe an earlier build or OS than the running one, so its own
    /// environment wins over the current device context.
    ///
    /// - Parameters:
    ///   - current: The running app's context.
    ///   - env: The report's environment, if it has one.
    /// - Returns: The context to stamp on the report's record.
    nonisolated static func context(_ current: RecordContext, _ env: (device: String, os: String, build: String, version: String)?) -> RecordContext {
        guard let env else { return current }
        return RecordContext(bundleIdentifier: current.bundleIdentifier, appVersion: env.version, buildVersion: env.build, osVersion: env.os, deviceModel: env.device)
    }

    /// Queues the install and daily-open records for this launch or foreground.
    func recordActivity() {
        guard configuration.tracksRetention else { return }
        let records = retention.records(at: Date(), context: context)
        Task { await enqueue(records) }
    }

    /// Samples records, stamps the rate, writes them to the queue and uploads.
    ///
    /// - Parameter records: New records from any collection source.
    func enqueue(_ records: [PendingRecord]) async {
        let admitted = records.filter(isSampledIn).map(stampingRate)
        guard !admitted.isEmpty else { return }
        try? await queue.enqueue(admitted)
        await flush()
    }

    /// Uploads queued records in batches of 100 until the queue is empty or CloudKit
    /// rejects a batch.
    ///
    /// A call made while a flush is running asks it for one more pass, so a record queued
    /// just after the running pass read the queue still goes out now.
    func flush() async {
        guard !isFlushing else {
            flushRequested = true
            return
        }
        isFlushing = true
        defer { isFlushing = false }
        repeat {
            flushRequested = false
            await drainQueue()
        } while flushRequested
    }

    private func drainQueue() async {
        guard await uploader.isAvailable() else { return }
        while let batch = try? await queue.pending(limit: 100), !batch.isEmpty {
            guard let accepted = try? await uploader.upload(batch), !accepted.isEmpty else { return }
            await queue.remove(accepted)
            if accepted.count < batch.count { return }
        }
    }

    // MARK: Sampling

    /// The current sampling rate.
    ///
    /// A ``SamplingMode/fixed(_:)`` configuration wins; otherwise it is the last `SPConfig`
    /// rate seen, or `1`.
    var sampleRate: Double { rate(for: configuration.sampling, key: Key.sampleRate) }
    /// The current diagnostic sampling rate, resolved like ``sampleRate``.
    var diagnosticSampleRate: Double { rate(for: configuration.diagnosticSampling, key: Key.diagnosticSampleRate) }

    private func rate(for mode: SamplingMode, key: String) -> Double {
        switch mode {
        case .fixed(let value): return max(0, min(1, value))
        case .automatic: return defaults.object(forKey: key) as? Double ?? 1
        }
    }

    private func isSampledIn(_ record: PendingRecord) -> Bool {
        let rate = record.kind == .diagnosticPayload ? diagnosticSampleRate : sampleRate
        return Sampling.includes(installID: retention.installID(), rate: rate)
    }

    /// Stamps the record's sampling rate. Readers divide counts by it to estimate the full
    /// population.
    private func stampingRate(_ record: PendingRecord) -> PendingRecord {
        var record = record
        let rate = record.kind == .diagnosticPayload ? diagnosticSampleRate : sampleRate
        record.fields[Schema.Field.sampleRate] = .double(rate)
        return record
    }

    /// Refreshes the rates the ShipPulse app publishes, at most once a day.
    ///
    /// - Parameter now: The current date.
    func refreshSamplingConfig(now: Date = Date()) async {
        let fetchedAt = defaults.object(forKey: Key.configFetchedAt) as? Date ?? .distantPast
        guard now.timeIntervalSince(fetchedAt) > 24 * 60 * 60 else { return }
        guard let config = await uploader.fetchSamplingConfig(bundleID: context.bundleIdentifier) else { return }
        defaults.set(config.sampleRate, forKey: Key.sampleRate)
        defaults.set(config.diagnosticSampleRate, forKey: Key.diagnosticSampleRate)
        defaults.set(now, forKey: Key.configFetchedAt)
    }

    private func observeForeground() {
        #if canImport(UIKit) && !os(watchOS)
        NotificationCenter.default.addObserver(forName: UIApplication.willEnterForegroundNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.recordActivity()
                Task { await self.flush() }
            }
        }
        #endif
    }
}

/// Reads the running app's and device's ``RecordContext``.
enum DeviceContext {
    /// The context of the running app on this device.
    static func current() -> RecordContext {
        let info = Bundle.main.infoDictionary ?? [:]
        let os = ProcessInfo.processInfo.operatingSystemVersion
        return RecordContext(
            bundleIdentifier: Bundle.main.bundleIdentifier ?? "unknown",
            appVersion: info["CFBundleShortVersionString"] as? String ?? "0",
            buildVersion: info["CFBundleVersion"] as? String ?? "0",
            osVersion: "\(os.majorVersion).\(os.minorVersion).\(os.patchVersion)",
            deviceModel: modelIdentifier()
        )
    }

    private static func modelIdentifier() -> String {
        // On the Simulator, hw.machine is the host CPU; the simulated model is in the environment.
        if let simulated = ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] { return simulated }
        var size = 0
        sysctlbyname("hw.machine", nil, &size, nil, 0)
        var machine = [UInt8](repeating: 0, count: max(size, 1))
        sysctlbyname("hw.machine", &machine, &size, nil, 0)
        return String(decoding: machine.prefix { $0 != 0 }, as: UTF8.self)
    }
}


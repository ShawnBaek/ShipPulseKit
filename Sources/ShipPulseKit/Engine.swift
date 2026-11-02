import Foundation
import ShipPulseKitCore
#if canImport(UIKit)
import UIKit
#endif
#if canImport(MetricKit) && !os(watchOS) && !os(tvOS)
import MetricKit
#endif

/// Connects the collection sources to sampling, ``DataContainer`` and the uploader.
///
/// ``ShipPulseKit`` owns exactly one engine, created by ``ShipPulseKit/start(_:)``. The
/// engine keeps no state on the device itself: it talks only to ``DataContainer`` and
/// ``RecordUploading``.
@MainActor
final class Engine {
    private let configuration: Configuration
    private let container: DataContainer
    private let uploader: any RecordUploading
    private let context: RecordContext
    private var isFlushing = false
    private var flushRequested = false

    /// Creates an engine.
    ///
    /// - Parameters:
    ///   - configuration: The options passed to ``ShipPulseKit/start(_:)``.
    ///   - container: The on-device state. `nil` uses the default directory and
    ///     `UserDefaults.standard`; tests pass a temporary one.
    ///   - uploader: The transport. `nil` uses ``CloudKitUploader``.
    ///   - context: Device and app fields stamped on every record.
    /// - Throws: ``ShipPulseKitError`` with code ``ShipPulseKitError/Code/iCloudContainerUnavailable``
    ///   when ``CloudKitUploader`` can't open the container.
    init(
        configuration: Configuration,
        container: DataContainer? = nil,
        uploader: (any RecordUploading)? = nil,
        context: RecordContext = DeviceContext.current()
    ) throws(ShipPulseKitError) {
        self.configuration = configuration
        self.container = container ?? DataContainer(maxAge: configuration.maxQueueAge, maxCount: configuration.maxQueuedRecords)
        if let uploader {
            self.uploader = uploader
        } else {
            self.uploader = try CloudKitUploader(configuration: configuration)
        }
        self.context = context
    }

    #if canImport(MetricKit) && !os(watchOS) && !os(tvOS)
    private var collector: MetricKitCollector?
    /// The MetricKit manager, once ``start()`` has run.
    ///
    /// ``ShipPulseKit/trackLaunchTask(_:_:)`` needs the same manager that collects reports,
    /// so launch tasks count toward this app's extended launch metric.
    var metricManager: MetricManager? { collector?.manager }
    #endif

    /// Starts MetricKit collection, screen tracking and retention, then uploads.
    func start() {
        #if canImport(MetricKit) && !os(watchOS) && !os(tvOS)
        let collector = MetricKitCollector(stateReportingDomains: configuration.additionalStateDomains.union([Schema.screenDomain]))
        let fallback = context
        #if !os(visionOS)
        if configuration.collectsMetrics {
            let container = container
            collector.startMetrics { [weak self] report in
                let installID = await container.installID()
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
        let now = Date(), context = context
        Task {
            let records = await container.updateRetention { RetentionTracker.records(for: $0, at: now, context: context) }
            await enqueue(records)
        }
    }

    /// Samples records, stamps the rate, writes them to ``DataContainer`` and uploads.
    ///
    /// - Parameter records: New records from any collection source.
    func enqueue(_ records: [PendingRecord]) async {
        let installID = await container.installID()
        let rates = await sampleRates()
        let admitted = records.compactMap { record -> PendingRecord? in
            let rate = record.kind == .diagnosticPayload ? rates.diagnostic : rates.metric
            guard Sampling.includes(installID: installID, rate: rate) else { return nil }
            // Readers divide counts by the rate to estimate the full population.
            var record = record
            record.fields[Schema.Field.sampleRate] = .double(rate)
            return record
        }
        guard !admitted.isEmpty else { return }
        try? await container.enqueue(admitted)
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
        while let batch = try? await container.pending(limit: 100), !batch.isEmpty {
            guard let accepted = try? await uploader.upload(batch), !accepted.isEmpty else { return }
            await container.remove(accepted)
            if accepted.count < batch.count { return }
        }
    }

    // MARK: Sampling

    /// The current sampling rates.
    ///
    /// A ``SamplingMode/fixed(_:)`` configuration wins; otherwise each is the last `SPConfig`
    /// rate seen, or `1`.
    ///
    /// - Returns: The rate for metric and retention records, and the rate for diagnostics.
    func sampleRates() async -> (metric: Double, diagnostic: Double) {
        let stored = await container.sampling()
        return (
            Self.rate(for: configuration.sampling, stored: stored.sampleRate),
            Self.rate(for: configuration.diagnosticSampling, stored: stored.diagnosticSampleRate)
        )
    }

    private nonisolated static func rate(for mode: SamplingMode, stored: Double?) -> Double {
        switch mode {
        case .fixed(let value): return max(0, min(1, value))
        case .automatic: return stored ?? 1
        }
    }

    /// Refreshes the rates the ShipPulse app publishes, at most once a day.
    ///
    /// - Parameter now: The current date.
    func refreshSamplingConfig(now: Date = Date()) async {
        let fetchedAt = await container.sampling().fetchedAt ?? .distantPast
        guard now.timeIntervalSince(fetchedAt) > 24 * 60 * 60 else { return }
        guard let config = await uploader.fetchSamplingConfig(bundleID: context.bundleIdentifier) else { return }
        await container.saveSampling(config, fetchedAt: now)
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


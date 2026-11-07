#if canImport(MetricKit) && !os(watchOS) && !os(tvOS)
import Foundation
@_weakLinked import MetricKit
import ShipPulseKitCore

/// Collects iOS 27 MetricKit reports through `MetricManager`'s async streams.
///
/// Metric reports arrive about once a day per device. Diagnostic reports arrive as they
/// occur, delivered on a later launch. visionOS has no metric reports, only diagnostics.
///
/// Main-actor isolated because ``Engine``, which creates and owns it, lives there. The
/// listening tasks run off the main actor and capture only the report stream and the
/// `@Sendable` callback, never the collector.
@MainActor
final class MetricKitCollector {
    /// The manager whose report streams this collector reads.
    ///
    /// It is shared with ``Engine/metricManager`` because launch-task tracking must use the
    /// manager that collects the reports.
    let manager: MetricManager
    /// The stream listeners, cancelled when the collector goes away.
    private var tasks: [Task<Void, Never>] = []

    /// Creates a collector.
    ///
    /// - Parameter stateReportingDomains: Domains MetricKit breaks metrics down by,
    ///   including the screen domain.
    init(stateReportingDomains: Set<String>) {
        #if os(visionOS)
        manager = MetricManager()
        #else
        manager = MetricManager(enabledStateReportingDomains: Set(stateReportingDomains.map(StateReportingDomain.init(rawValue:))))
        #endif
    }

    #if !os(visionOS)
    /// Starts listening for daily metric reports.
    ///
    /// - Parameter onReport: Called for each metric report.
    func startMetrics(onReport: @escaping @Sendable (MetricReport) async -> Void) {
        let reports = manager.metricReports
        let task = Task.detached(priority: .utility) {
            for await report in reports { await onReport(report) }
        }
        tasks.append(task)
    }
    #endif

    /// Starts listening for diagnostic reports.
    ///
    /// - Parameter onReport: Called for each diagnostic report.
    func startDiagnostics(onReport: @escaping @Sendable (DiagnosticReport) async -> Void) {
        let diagnostics = manager.diagnosticReports
        let task = Task.detached(priority: .utility) {
            for await report in diagnostics { await onReport(report) }
        }
        tasks.append(task)
    }

    /// Cancels the stream listeners, so no report is handled after the engine is gone.
    isolated deinit {
        tasks.forEach { $0.cancel() }
    }
}

/// Flattens MetricKit's typed results into the stable `MetricSummary` schema.
enum ReportMapper {
    #if !os(visionOS)
    /// Flattens a metric report, including its per-state entries.
    ///
    /// - Parameter report: The MetricKit report.
    /// - Returns: The report in ShipPulse's schema.
    static func dailyReport(from report: MetricReport) -> DailyReport {
        let env = report.environment
        return DailyReport(
            overall: summary(report.intervalEntries.fullDayEntry.values),
            states: report.stateEntries.map {
                StateSummary(domain: $0.state.domain, label: $0.state.label, durationSeconds: seconds($0.state.duration), metrics: summary($0.values))
            },
            isLowPowerModeEnabled: env?.lowPowerModeEnabled ?? false,
            isTestFlight: env?.isTestFlightApp ?? false,
            includesMultipleAppVersions: env?.includesMultipleApplicationVersions ?? false,
            hasExceededStateLimit: env?.hasExceededStateLimit ?? false
        )
    }

    /// Maps every MetricKit result to `MetricKey` entries, normalizing units.
    ///
    /// Histograms are in milliseconds, totals in seconds and sizes in megabytes.
    ///
    /// - Parameter results: The results of one interval or state entry.
    /// - Returns: The flattened summary.
    static func summary(_ results: [MetricResult]) -> MetricSummary { // swiftlint:disable:this cyclomatic_complexity function_body_length
        var s = MetricSummary()
        for result in results {
            switch result {
            case .timeToFirstDraw(let m): s.histograms[.timeToFirstDraw] = histogram(m.histogram)
            case .optimizedTimeToFirstDraw(let m): s.histograms[.optimizedTimeToFirstDraw] = histogram(m.histogram)
            case .extendedLaunch(let m): s.histograms[.extendedLaunch] = histogram(m.histogram)
            case .applicationResumeTime(let m): s.histograms[.applicationResumeTime] = histogram(m.histogram)
            case .hangTime(let m): s.histograms[.hangTime] = histogram(m.histogram)
            case .hitchTime(let m):
                s.values[.hitchRatio] = m.ratio.value
                s.values[.hitchSeconds] = seconds(m.totalHitchTime)
                s.values[.animationSeconds] = seconds(m.totalAnimationTime)
            case .foregroundTermination(let m):
                s.counts[.foregroundTermination(.normal)] = m.normalTerminationCount
                s.counts[.foregroundTermination(.memoryLimit)] = m.memoryLimitTerminationCount
                s.counts[.foregroundTermination(.badAccess)] = m.badAccessTerminationCount
                s.counts[.foregroundTermination(.abnormal)] = m.abnormalTerminationCount
                s.counts[.foregroundTermination(.illegalInstruction)] = m.illegalInstructionTerminationCount
                s.counts[.foregroundTermination(.watchdog)] = m.watchdogTerminationCount
            case .backgroundTermination(let m):
                s.counts[.backgroundTermination(.normal)] = m.normalTerminationCount
                s.counts[.backgroundTermination(.memoryLimit)] = m.memoryLimitTerminationCount
                s.counts[.backgroundTermination(.highCPU)] = m.highCPUTerminationCount
                s.counts[.backgroundTermination(.systemPressure)] = m.systemPressureTerminationCount
                s.counts[.backgroundTermination(.badAccess)] = m.badAccessTerminationCount
                s.counts[.backgroundTermination(.abnormal)] = m.abnormalTerminationCount
                s.counts[.backgroundTermination(.illegalInstruction)] = m.illegalInstructionTerminationCount
                s.counts[.backgroundTermination(.watchdog)] = m.watchdogTerminationCount
                s.counts[.backgroundTermination(.fileLock)] = m.fileLockTerminationCount
                s.counts[.backgroundTermination(.taskTimeout)] = m.taskTimeoutTerminationCount
            case .signpostInterval(let m):
                s.signposts.append(SignpostSummary(
                    name: m.signpostName,
                    category: m.signpostCategory,
                    count: m.totalCount,
                    duration: histogram(m.signpostDuration),
                    averageMemoryMB: m.averageMemory.map { megabytes($0.average) },
                    cpuSeconds: m.cpuTime.map(seconds),
                    logicalWritesMB: m.logicalWrites.map(megabytes),
                    hitchRatio: m.hitchTimeRatio?.value,
                    hitchSeconds: m.totalHitchTime.map(seconds),
                    animationSeconds: m.totalAnimationTime.map(seconds)
                ))
            case .locationActivityTime(let m):
                s.values[.locationSeconds(.bestAccuracyForNavigation)] = seconds(m.bestAccuracyForNavigation)
                s.values[.locationSeconds(.bestAccuracy)] = seconds(m.bestAccuracy)
                s.values[.locationSeconds(.tenMeters)] = seconds(m.tenMeters)
                s.values[.locationSeconds(.oneHundredMeters)] = seconds(m.oneHundredMeter)
                s.values[.locationSeconds(.oneKilometer)] = seconds(m.oneKilometer)
                s.values[.locationSeconds(.threeKilometers)] = seconds(m.threeKilometers)
                s.values[.locationSeconds(.reducedAccuracy)] = seconds(m.reducedAccuracy)
            case .totalForegroundTime(let m): s.values[.foregroundSeconds] = seconds(m.value)
            case .totalBackgroundTime(let m): s.values[.backgroundSeconds] = seconds(m.value)
            case .totalBackgroundAudioTime(let m): s.values[.backgroundAudioSeconds] = seconds(m.value)
            case .totalBackgroundLocationTime(let m): s.values[.backgroundLocationSeconds] = seconds(m.value)
            case .cpuTime(let m): s.values[.cpuSeconds] = seconds(m.value)
            case .cpuInstructionsCount(let m): s.counts[.cpuInstructions] = m.value
            case .gpuTime(let m): s.values[.gpuSeconds] = seconds(m.value)
            case .peakMemory(let m): s.values[.peakMemoryMB] = megabytes(m.value)
            case .suspendedMemory(let m): s.values[.suspendedMemoryMB] = megabytes(m.value.average)
            case .totalWiFiUpload(let m): s.values[.wifiUploadMB] = megabytes(m.value)
            case .totalWiFiDownload(let m): s.values[.wifiDownloadMB] = megabytes(m.value)
            case .totalCellularUpload(let m): s.values[.cellularUploadMB] = megabytes(m.value)
            case .totalCellularDownload(let m): s.values[.cellularDownloadMB] = megabytes(m.value)
            case .logicalDiskWrites(let m): s.values[.logicalDiskWritesMB] = megabytes(m.value)
            case .pixelLuminance(let m): s.values[.pixelLuminance] = m.value.average.value
            case .cellularConditionTime(let m): s.histograms[.cellularConditionBars] = histogram(m.histogram)
            case .totalFileCount(let m):
                s.counts[.binaryFileCount] = m.binaryFileCount
                s.counts[.dataFileCount] = m.dataFileCount
            case .totalFileSize(let m):
                s.values[.binaryFileSizeMB] = megabytes(m.binaryFileSize)
                s.values[.dataFileSizeMB] = megabytes(m.dataFileSize)
                s.values[.cacheFolderSizeMB] = megabytes(m.cacheFolderSize)
                s.values[.cloneSizeMB] = megabytes(m.cloneSize)
            case .totalDiskSpaceCapacity(let m):
                s.values[.diskCapacityMB] = megabytes(m.capacity)
                s.values[.diskUsedMB] = megabytes(m.spaceUsed)
            case .metalFrameRate(let m):
                s.values[.metalFPS(layer: m.layerName)] = m.framesPerSecond.converted(to: .hertz).value
                s.counts[.metalFrames(layer: m.layerName)] = m.frameCount
                s.values[.metalActiveSeconds(layer: m.layerName)] = seconds(m.activeDrawingDuration)
            @unknown default:
                // A metric added after this SDK version. It is still in the raw report JSON.
                break
            }
        }
        return s
    }

    #endif

    /// The fields that make a diagnostic queryable without decoding its call stacks.
    ///
    /// - Parameter report: The MetricKit diagnostic.
    /// - Returns: The kind, the duration in milliseconds when the kind has one, and
    ///   kind-specific fields.
    static func diagnosticFields(_ report: DiagnosticReport) -> (kind: String, durationMs: Double?, extra: [Schema.Field: FieldValue]) {
        switch report.result {
        case .crash(let d):
            var extra: [Schema.Field: FieldValue] = [:]
            if let category = d.terminationCategory { extra[.terminationCategory] = .string(category.rawValue) }
            if let signal = d.signal { extra[.signal] = .int(Int64(signal)) }
            if let type = d.exceptionType { extra[.exceptionType] = .int(Int64(type)) }
            return ("crash", nil, extra)
        case .hang(let d): return ("hang", milliseconds(d.hangDuration), [:])
        case .appLaunch(let d): return ("appLaunch", milliseconds(d.launchDuration), [:])
        case .cpuException(let d): return ("cpuException", milliseconds(d.totalCPUTime), [:])
        case .diskWriteException(let d): return ("diskWriteException", nil, [.writesMB: .double(megabytes(d.totalBytesWritten))])
        case .memoryException: return ("memoryException", nil, [:])
        @unknown default: return ("unknown", nil, [:])
        }
    }

    #if !os(visionOS)
    private static func histogram<D: Dimension>(_ source: MetricKit.Histogram<D>) -> ShipPulseKitCore.Histogram {
        ShipPulseKitCore.Histogram(buckets: source.buckets.map {
            .init(start: normalized($0.lowerBound), end: normalized($0.upperBound), count: $0.count)
        })
    }

    /// Durations become milliseconds; other units (signal bars) keep their base value.
    private static func normalized<D: Dimension>(_ measurement: Measurement<D>) -> Double {
        if let duration = measurement as? Measurement<UnitDuration> { return milliseconds(duration) }
        return measurement.value
    }

    #endif

    private static func seconds(_ m: Measurement<UnitDuration>) -> Double { m.converted(to: .seconds).value }
    private static func milliseconds(_ m: Measurement<UnitDuration>) -> Double { m.converted(to: .milliseconds).value }
    private static func megabytes(_ m: Measurement<UnitInformationStorage>) -> Double { m.converted(to: .megabytes).value }
}
#endif

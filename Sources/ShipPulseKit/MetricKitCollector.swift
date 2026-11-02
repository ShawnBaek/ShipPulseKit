#if canImport(MetricKit) && !os(watchOS) && !os(tvOS)
import Foundation
import MetricKit
import ShipPulseKitCore
import Synchronization

/// Collects iOS 27 MetricKit reports through `MetricManager`'s async streams.
///
/// Metric reports arrive about once a day per device. Diagnostic reports arrive as they
/// occur, delivered on a later launch. visionOS has no metric reports, only diagnostics.
final class MetricKitCollector: Sendable {
    /// The manager whose report streams this collector reads.
    ///
    /// It is shared with ``Engine/metricManager`` because launch-task tracking must use the
    /// manager that collects the reports.
    let manager: MetricManager
    /// The stream listeners, cancelled when the collector goes away.
    private let tasks = Mutex<[Task<Void, Never>]>([])

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
        tasks.withLock { $0.append(task) }
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
        tasks.withLock { $0.append(task) }
    }

    /// Cancels the stream listeners, so no report is handled after the engine is gone.
    deinit {
        tasks.withLock { $0.forEach { $0.cancel() } }
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
            lowPowerMode: env?.lowPowerModeEnabled ?? false,
            isTestFlight: env?.isTestFlightApp ?? false,
            includesMultipleAppVersions: env?.includesMultipleApplicationVersions ?? false,
            exceededStateLimit: env?.hasExceededStateLimit ?? false
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
            case .timeToFirstDraw(let m): s.histograms[MetricKey.timeToFirstDraw] = histogram(m.histogram)
            case .optimizedTimeToFirstDraw(let m): s.histograms[MetricKey.optimizedTimeToFirstDraw] = histogram(m.histogram)
            case .extendedLaunch(let m): s.histograms[MetricKey.extendedLaunch] = histogram(m.histogram)
            case .applicationResumeTime(let m): s.histograms[MetricKey.applicationResumeTime] = histogram(m.histogram)
            case .hangTime(let m): s.histograms[MetricKey.hangTime] = histogram(m.histogram)
            case .hitchTime(let m):
                s.values[MetricKey.hitchRatio] = m.ratio.value
                s.values[MetricKey.hitchSeconds] = seconds(m.totalHitchTime)
                s.values[MetricKey.animationSeconds] = seconds(m.totalAnimationTime)
            case .foregroundTermination(let m):
                s.counts[MetricKey.foregroundTermination("normal")] = m.normalTerminationCount
                s.counts[MetricKey.foregroundTermination("memoryLimit")] = m.memoryLimitTerminationCount
                s.counts[MetricKey.foregroundTermination("badAccess")] = m.badAccessTerminationCount
                s.counts[MetricKey.foregroundTermination("abnormal")] = m.abnormalTerminationCount
                s.counts[MetricKey.foregroundTermination("illegalInstruction")] = m.illegalInstructionTerminationCount
                s.counts[MetricKey.foregroundTermination("watchdog")] = m.watchdogTerminationCount
            case .backgroundTermination(let m):
                s.counts[MetricKey.backgroundTermination("normal")] = m.normalTerminationCount
                s.counts[MetricKey.backgroundTermination("memoryLimit")] = m.memoryLimitTerminationCount
                s.counts[MetricKey.backgroundTermination("highCPU")] = m.highCPUTerminationCount
                s.counts[MetricKey.backgroundTermination("systemPressure")] = m.systemPressureTerminationCount
                s.counts[MetricKey.backgroundTermination("badAccess")] = m.badAccessTerminationCount
                s.counts[MetricKey.backgroundTermination("abnormal")] = m.abnormalTerminationCount
                s.counts[MetricKey.backgroundTermination("illegalInstruction")] = m.illegalInstructionTerminationCount
                s.counts[MetricKey.backgroundTermination("watchdog")] = m.watchdogTerminationCount
                s.counts[MetricKey.backgroundTermination("fileLock")] = m.fileLockTerminationCount
                s.counts[MetricKey.backgroundTermination("taskTimeout")] = m.taskTimeoutTerminationCount
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
                s.values[MetricKey.locationSeconds("bestAccuracyForNavigation")] = seconds(m.bestAccuracyForNavigation)
                s.values[MetricKey.locationSeconds("bestAccuracy")] = seconds(m.bestAccuracy)
                s.values[MetricKey.locationSeconds("tenMeters")] = seconds(m.tenMeters)
                s.values[MetricKey.locationSeconds("oneHundredMeters")] = seconds(m.oneHundredMeter)
                s.values[MetricKey.locationSeconds("oneKilometer")] = seconds(m.oneKilometer)
                s.values[MetricKey.locationSeconds("threeKilometers")] = seconds(m.threeKilometers)
                s.values[MetricKey.locationSeconds("reducedAccuracy")] = seconds(m.reducedAccuracy)
            case .totalForegroundTime(let m): s.values[MetricKey.foregroundSeconds] = seconds(m.value)
            case .totalBackgroundTime(let m): s.values[MetricKey.backgroundSeconds] = seconds(m.value)
            case .totalBackgroundAudioTime(let m): s.values[MetricKey.backgroundAudioSeconds] = seconds(m.value)
            case .totalBackgroundLocationTime(let m): s.values[MetricKey.backgroundLocationSeconds] = seconds(m.value)
            case .cpuTime(let m): s.values[MetricKey.cpuSeconds] = seconds(m.value)
            case .cpuInstructionsCount(let m): s.counts[MetricKey.cpuInstructions] = m.value
            case .gpuTime(let m): s.values[MetricKey.gpuSeconds] = seconds(m.value)
            case .peakMemory(let m): s.values[MetricKey.peakMemoryMB] = megabytes(m.value)
            case .suspendedMemory(let m): s.values[MetricKey.suspendedMemoryMB] = megabytes(m.value.average)
            case .totalWiFiUpload(let m): s.values[MetricKey.wifiUploadMB] = megabytes(m.value)
            case .totalWiFiDownload(let m): s.values[MetricKey.wifiDownloadMB] = megabytes(m.value)
            case .totalCellularUpload(let m): s.values[MetricKey.cellularUploadMB] = megabytes(m.value)
            case .totalCellularDownload(let m): s.values[MetricKey.cellularDownloadMB] = megabytes(m.value)
            case .logicalDiskWrites(let m): s.values[MetricKey.logicalDiskWritesMB] = megabytes(m.value)
            case .pixelLuminance(let m): s.values[MetricKey.pixelLuminance] = m.value.average.value
            case .cellularConditionTime(let m): s.histograms[MetricKey.cellularConditionBars] = histogram(m.histogram)
            case .totalFileCount(let m):
                s.counts[MetricKey.binaryFileCount] = m.binaryFileCount
                s.counts[MetricKey.dataFileCount] = m.dataFileCount
            case .totalFileSize(let m):
                s.values[MetricKey.binaryFileSizeMB] = megabytes(m.binaryFileSize)
                s.values[MetricKey.dataFileSizeMB] = megabytes(m.dataFileSize)
                s.values[MetricKey.cacheFolderSizeMB] = megabytes(m.cacheFolderSize)
                s.values[MetricKey.cloneSizeMB] = megabytes(m.cloneSize)
            case .totalDiskSpaceCapacity(let m):
                s.values[MetricKey.diskCapacityMB] = megabytes(m.capacity)
                s.values[MetricKey.diskUsedMB] = megabytes(m.spaceUsed)
            case .metalFrameRate(let m):
                s.values[MetricKey.metalFPS(layer: m.layerName)] = m.framesPerSecond.converted(to: .hertz).value
                s.counts[MetricKey.metalFrames(layer: m.layerName)] = m.frameCount
                s.values[MetricKey.metalActiveSeconds(layer: m.layerName)] = seconds(m.activeDrawingDuration)
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
    static func diagnosticFields(_ report: DiagnosticReport) -> (kind: String, durationMs: Double?, extra: [String: FieldValue]) {
        switch report.result {
        case .crash(let d):
            var extra: [String: FieldValue] = [:]
            if let category = d.terminationCategory { extra[Schema.Field.terminationCategory] = .string(category.rawValue) }
            if let signal = d.signal { extra[Schema.Field.signal] = .int(Int64(signal)) }
            if let type = d.exceptionType { extra[Schema.Field.exceptionType] = .int(Int64(type)) }
            return ("crash", nil, extra)
        case .hang(let d): return ("hang", milliseconds(d.hangDuration), [:])
        case .appLaunch(let d): return ("appLaunch", milliseconds(d.launchDuration), [:])
        case .cpuException(let d): return ("cpuException", milliseconds(d.totalCPUTime), [:])
        case .diskWriteException(let d): return ("diskWriteException", nil, [Schema.Field.writesMB: .double(megabytes(d.totalBytesWritten))])
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

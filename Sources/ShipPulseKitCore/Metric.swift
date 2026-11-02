import Foundation

/// Every MetricKit metric ShipPulseKit records, one case per iOS 27 `MetricResult` case.
///
/// The raw value is the stable identifier stored in ``DailyReport``. ``storageKeys`` lists
/// the keys a metric writes into ``MetricSummary``.
public enum Metric: String, CaseIterable, Codable, Sendable {
    // Launch
    case timeToFirstDraw
    case optimizedTimeToFirstDraw
    case extendedLaunch
    case applicationResumeTime
    // Responsiveness and animation
    case hangTime
    case hitchTime
    // Terminations
    case foregroundTermination
    case backgroundTermination
    // Run time
    case totalForegroundTime
    case totalBackgroundTime
    case totalBackgroundAudioTime
    case totalBackgroundLocationTime
    // CPU / GPU
    case cpuTime
    case cpuInstructionsCount
    case gpuTime
    // Memory
    case peakMemory
    case suspendedMemory
    // Network
    case totalWiFiUpload
    case totalWiFiDownload
    case totalCellularUpload
    case totalCellularDownload
    case cellularConditionTime
    // Disk
    case logicalDiskWrites
    case totalFileCount
    case totalFileSize
    case totalDiskSpaceCapacity
    // Location
    case locationActivityTime
    // Display and graphics
    case pixelLuminance
    case metalFrameRate
    // Custom
    case signpostInterval

    /// The area a metric belongs to, used to section the ShipPulse UI.
    public enum Group: String, CaseIterable, Codable, Sendable {
        case launch, responsiveness, termination, runTime, cpuGPU, memory, network, disk, location, display, custom
    }

    /// How a metric is stored in ``MetricSummary``.
    public enum Kind: String, Codable, Sendable {
        /// One histogram in ``MetricSummary/histograms``.
        case histogram
        /// One number in ``MetricSummary/values``.
        case value
        /// One integer in ``MetricSummary/counts``.
        case count
        /// Several sub-values under a common key prefix (terminations, file sizes, Metal layers…).
        case breakdown
        /// Entries in ``MetricSummary/signposts``.
        case signposts
    }

    /// The unit a metric's stored values use.
    public enum Unit: String, Codable, Sendable {
        case milliseconds, seconds, megabytes, ratio, count, signalBars, luminance, framesPerSecond, mixed
    }

    /// The area this metric belongs to.
    public var group: Group {
        switch self {
        case .timeToFirstDraw, .optimizedTimeToFirstDraw, .extendedLaunch, .applicationResumeTime: .launch
        case .hangTime, .hitchTime: .responsiveness
        case .foregroundTermination, .backgroundTermination: .termination
        case .totalForegroundTime, .totalBackgroundTime, .totalBackgroundAudioTime, .totalBackgroundLocationTime: .runTime
        case .cpuTime, .cpuInstructionsCount, .gpuTime: .cpuGPU
        case .peakMemory, .suspendedMemory: .memory
        case .totalWiFiUpload, .totalWiFiDownload, .totalCellularUpload, .totalCellularDownload, .cellularConditionTime: .network
        case .logicalDiskWrites, .totalFileCount, .totalFileSize, .totalDiskSpaceCapacity: .disk
        case .locationActivityTime: .location
        case .pixelLuminance, .metalFrameRate: .display
        case .signpostInterval: .custom
        }
    }

    /// How this metric is stored.
    public var kind: Kind {
        switch self {
        case .timeToFirstDraw, .optimizedTimeToFirstDraw, .extendedLaunch, .applicationResumeTime, .hangTime, .cellularConditionTime: .histogram
        case .cpuInstructionsCount: .count
        case .hitchTime, .foregroundTermination, .backgroundTermination, .totalFileCount, .totalFileSize,
             .totalDiskSpaceCapacity, .locationActivityTime, .metalFrameRate: .breakdown
        case .signpostInterval: .signposts
        default: .value
        }
    }

    /// The unit of this metric's stored values.
    public var unit: Unit {
        switch self {
        case .timeToFirstDraw, .optimizedTimeToFirstDraw, .extendedLaunch, .applicationResumeTime, .hangTime: .milliseconds
        case .totalForegroundTime, .totalBackgroundTime, .totalBackgroundAudioTime, .totalBackgroundLocationTime,
             .cpuTime, .gpuTime, .locationActivityTime: .seconds
        case .peakMemory, .suspendedMemory, .totalWiFiUpload, .totalWiFiDownload, .totalCellularUpload,
             .totalCellularDownload, .logicalDiskWrites, .totalFileSize, .totalDiskSpaceCapacity: .megabytes
        case .cpuInstructionsCount, .foregroundTermination, .backgroundTermination, .totalFileCount: .count
        case .cellularConditionTime: .signalBars
        case .pixelLuminance: .luminance
        case .metalFrameRate: .framesPerSecond
        case .hitchTime, .signpostInterval: .mixed
        }
    }

    /// A title for the metric, in English.
    public var displayName: String {
        switch self {
        case .timeToFirstDraw: "Time to First Draw"
        case .optimizedTimeToFirstDraw: "Optimized Time to First Draw"
        case .extendedLaunch: "Extended Launch"
        case .applicationResumeTime: "Resume Time"
        case .hangTime: "Hang Time"
        case .hitchTime: "Hitch Time"
        case .foregroundTermination: "Foreground Terminations"
        case .backgroundTermination: "Background Terminations"
        case .totalForegroundTime: "Foreground Time"
        case .totalBackgroundTime: "Background Time"
        case .totalBackgroundAudioTime: "Background Audio Time"
        case .totalBackgroundLocationTime: "Background Location Time"
        case .cpuTime: "CPU Time"
        case .cpuInstructionsCount: "CPU Instructions"
        case .gpuTime: "GPU Time"
        case .peakMemory: "Peak Memory"
        case .suspendedMemory: "Suspended Memory"
        case .totalWiFiUpload: "Wi-Fi Upload"
        case .totalWiFiDownload: "Wi-Fi Download"
        case .totalCellularUpload: "Cellular Upload"
        case .totalCellularDownload: "Cellular Download"
        case .cellularConditionTime: "Cellular Signal"
        case .logicalDiskWrites: "Disk Writes"
        case .totalFileCount: "File Count"
        case .totalFileSize: "File Size"
        case .totalDiskSpaceCapacity: "Disk Space"
        case .locationActivityTime: "Location Activity"
        case .pixelLuminance: "Pixel Luminance"
        case .metalFrameRate: "Metal Frame Rate"
        case .signpostInterval: "Signpost Intervals"
        }
    }

    /// The 0.1.0 list of foreground termination reasons.
    @available(*, deprecated, message: "Use ForegroundTerminationReason.allCases.")
    public static var foregroundTerminationReasons: [String] { ForegroundTerminationReason.allCases.map(\.rawValue) }
    /// The 0.1.0 list of background termination reasons.
    @available(*, deprecated, message: "Use BackgroundTerminationReason.allCases.")
    public static var backgroundTerminationReasons: [String] { BackgroundTerminationReason.allCases.map(\.rawValue) }
    /// The 0.1.0 list of location accuracies.
    @available(*, deprecated, message: "Use LocationAccuracy.allCases.")
    public static var locationAccuracies: [String] { LocationAccuracy.allCases.map(\.rawValue) }

    /// The keys this metric writes into ``MetricSummary``.
    ///
    /// ``metalFrameRate`` keys depend on layer names and ``signpostInterval`` lives in
    /// ``MetricSummary/signposts``, so both return an empty list.
    public var storageKeys: [MetricKey] {
        switch self {
        case .timeToFirstDraw: [.timeToFirstDraw]
        case .optimizedTimeToFirstDraw: [.optimizedTimeToFirstDraw]
        case .extendedLaunch: [.extendedLaunch]
        case .applicationResumeTime: [.applicationResumeTime]
        case .hangTime: [.hangTime]
        case .hitchTime: [.hitchRatio, .hitchSeconds, .animationSeconds]
        case .foregroundTermination: ForegroundTerminationReason.allCases.map(MetricKey.foregroundTermination)
        case .backgroundTermination: BackgroundTerminationReason.allCases.map(MetricKey.backgroundTermination)
        case .totalForegroundTime: [.foregroundSeconds]
        case .totalBackgroundTime: [.backgroundSeconds]
        case .totalBackgroundAudioTime: [.backgroundAudioSeconds]
        case .totalBackgroundLocationTime: [.backgroundLocationSeconds]
        case .cpuTime: [.cpuSeconds]
        case .cpuInstructionsCount: [.cpuInstructions]
        case .gpuTime: [.gpuSeconds]
        case .peakMemory: [.peakMemoryMB]
        case .suspendedMemory: [.suspendedMemoryMB]
        case .totalWiFiUpload: [.wifiUploadMB]
        case .totalWiFiDownload: [.wifiDownloadMB]
        case .totalCellularUpload: [.cellularUploadMB]
        case .totalCellularDownload: [.cellularDownloadMB]
        case .cellularConditionTime: [.cellularConditionBars]
        case .logicalDiskWrites: [.logicalDiskWritesMB]
        case .totalFileCount: [.binaryFileCount, .dataFileCount]
        case .totalFileSize: [.binaryFileSizeMB, .dataFileSizeMB, .cacheFolderSizeMB, .cloneSizeMB]
        case .totalDiskSpaceCapacity: [.diskCapacityMB, .diskUsedMB]
        case .locationActivityTime: LocationAccuracy.allCases.map(MetricKey.locationSeconds)
        case .pixelLuminance: [.pixelLuminance]
        case .metalFrameRate, .signpostInterval: []
        }
    }

    /// The metrics in one group.
    ///
    /// - Parameter group: The group.
    /// - Returns: The group's metrics, in declaration order.
    public static func cases(in group: Group) -> [Metric] {
        allCases.filter { $0.group == group }
    }
}

extension MetricSummary {
    /// The metrics present in this summary, for example to list what a device reported.
    public var reportedMetrics: [Metric] {
        Metric.allCases.filter { metric in
            switch metric {
            case .signpostInterval: return !signposts.isEmpty
            case .metalFrameRate:
                return values.keys.contains {
                    switch $0 {
                    case .metalFPS, .metalFrames, .metalActiveSeconds: true
                    default: false
                    }
                } || counts.keys.contains { if case .metalFrames = $0 { true } else { false } }
            default:
                return metric.storageKeys.contains { histograms[$0] != nil || values[$0] != nil || counts[$0] != nil }
            }
        }
    }
}

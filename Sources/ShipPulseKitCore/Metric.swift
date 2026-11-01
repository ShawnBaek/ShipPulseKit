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

    /// Reasons a ``foregroundTermination`` is broken down by.
    public static let foregroundTerminationReasons = ["normal", "memoryLimit", "badAccess", "abnormal", "illegalInstruction", "watchdog"]
    /// Reasons a ``backgroundTermination`` is broken down by.
    public static let backgroundTerminationReasons = ["normal", "memoryLimit", "highCPU", "systemPressure", "badAccess", "abnormal", "illegalInstruction", "watchdog", "fileLock", "taskTimeout"]
    /// Accuracy levels ``locationActivityTime`` is broken down by.
    public static let locationAccuracies = ["bestAccuracyForNavigation", "bestAccuracy", "tenMeters", "oneHundredMeters", "oneKilometer", "threeKilometers", "reducedAccuracy"]

    /// The keys this metric writes into ``MetricSummary``.
    ///
    /// ``metalFrameRate`` keys depend on layer names and ``signpostInterval`` lives in
    /// ``MetricSummary/signposts``, so both return an empty list.
    public var storageKeys: [String] {
        switch self {
        case .timeToFirstDraw: [MetricKey.timeToFirstDraw]
        case .optimizedTimeToFirstDraw: [MetricKey.optimizedTimeToFirstDraw]
        case .extendedLaunch: [MetricKey.extendedLaunch]
        case .applicationResumeTime: [MetricKey.applicationResumeTime]
        case .hangTime: [MetricKey.hangTime]
        case .hitchTime: [MetricKey.hitchRatio, MetricKey.hitchSeconds, MetricKey.animationSeconds]
        case .foregroundTermination: Self.foregroundTerminationReasons.map(MetricKey.foregroundTermination)
        case .backgroundTermination: Self.backgroundTerminationReasons.map(MetricKey.backgroundTermination)
        case .totalForegroundTime: [MetricKey.foregroundSeconds]
        case .totalBackgroundTime: [MetricKey.backgroundSeconds]
        case .totalBackgroundAudioTime: [MetricKey.backgroundAudioSeconds]
        case .totalBackgroundLocationTime: [MetricKey.backgroundLocationSeconds]
        case .cpuTime: [MetricKey.cpuSeconds]
        case .cpuInstructionsCount: [MetricKey.cpuInstructions]
        case .gpuTime: [MetricKey.gpuSeconds]
        case .peakMemory: [MetricKey.peakMemoryMB]
        case .suspendedMemory: [MetricKey.suspendedMemoryMB]
        case .totalWiFiUpload: [MetricKey.wifiUploadMB]
        case .totalWiFiDownload: [MetricKey.wifiDownloadMB]
        case .totalCellularUpload: [MetricKey.cellularUploadMB]
        case .totalCellularDownload: [MetricKey.cellularDownloadMB]
        case .cellularConditionTime: [MetricKey.cellularConditionBars]
        case .logicalDiskWrites: [MetricKey.logicalDiskWritesMB]
        case .totalFileCount: [MetricKey.binaryFileCount, MetricKey.dataFileCount]
        case .totalFileSize: [MetricKey.binaryFileSizeMB, MetricKey.dataFileSizeMB, MetricKey.cacheFolderSizeMB, MetricKey.cloneSizeMB]
        case .totalDiskSpaceCapacity: [MetricKey.diskCapacityMB, MetricKey.diskUsedMB]
        case .locationActivityTime: Self.locationAccuracies.map(MetricKey.locationSeconds)
        case .pixelLuminance: [MetricKey.pixelLuminance]
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
            case .metalFrameRate: return values.keys.contains { $0.hasPrefix("metalFrameRate[") }
            default:
                return metric.storageKeys.contains { histograms[$0] != nil || values[$0] != nil || counts[$0] != nil }
            }
        }
    }
}

import Foundation

/// Every MetricKit metric from one report, flattened into a stable ShipPulse schema.
///
/// MetricKit's own Codable types can change shape between OS releases. This keyed form is
/// what ShipPulse aggregates. The SDK also uploads the raw report JSON next to it, so nothing
/// is lost when Apple adds metrics.
///
/// Units are normalized: histograms in milliseconds, totals in seconds, sizes in megabytes.
/// Keys come from ``MetricKey``.
///
/// Readers see it read-only; only ShipPulseKit, which fills it one metric at a time, can
/// change it.
public struct MetricSummary: Codable, Sendable, Equatable {
    /// Duration distributions, such as launch and hang times.
    public package(set) var histograms: [String: Histogram]
    /// Single numbers, such as foreground seconds or peak memory.
    public package(set) var values: [String: Double]
    /// Whole counts, such as terminations.
    public package(set) var counts: [String: Int]
    /// Developer-defined signpost intervals, including hitch regions.
    public package(set) var signposts: [SignpostSummary]

    /// Creates a summary.
    public init(histograms: [String: Histogram] = [:], values: [String: Double] = [:], counts: [String: Int] = [:], signposts: [SignpostSummary] = []) {
        self.histograms = histograms
        self.values = values
        self.counts = counts
        self.signposts = signposts
    }

    /// Whether the summary holds no metrics.
    public var isEmpty: Bool { histograms.isEmpty && values.isEmpty && counts.isEmpty && signposts.isEmpty }
}

/// Metrics for one developer-defined interval, signposted on
/// `MetricManager.logHandle(category:)`.
public struct SignpostSummary: Codable, Sendable, Equatable {
    /// The signpost name.
    public let name: String
    /// The signpost category.
    public let category: String
    /// How many times the interval ran.
    public let count: Int
    /// The interval's durations.
    public let duration: Histogram
    /// Average memory during the interval, in megabytes.
    public let averageMemoryMB: Double?
    /// CPU time spent in the interval, in seconds.
    public let cpuSeconds: Double?
    /// Logical disk writes during the interval, in megabytes.
    public let logicalWritesMB: Double?
    /// Hitch time divided by animation time, for animation intervals.
    public let hitchRatio: Double?
    /// Total hitch time, in seconds, for animation intervals.
    public let hitchSeconds: Double?
    /// Total animation time, in seconds, for animation intervals.
    public let animationSeconds: Double?

    /// Creates a signpost summary.
    public init(name: String, category: String, count: Int, duration: Histogram, averageMemoryMB: Double? = nil, cpuSeconds: Double? = nil, logicalWritesMB: Double? = nil, hitchRatio: Double? = nil, hitchSeconds: Double? = nil, animationSeconds: Double? = nil) {
        self.name = name
        self.category = category
        self.count = count
        self.duration = duration
        self.averageMemoryMB = averageMemoryMB
        self.cpuSeconds = cpuSeconds
        self.logicalWritesMB = logicalWritesMB
        self.hitchRatio = hitchRatio
        self.hitchSeconds = hitchSeconds
        self.animationSeconds = animationSeconds
    }
}

/// Metrics measured while the app was in one reported state, for example the screen "Feed".
///
/// This is how ShipPulse attributes hitches, hangs and memory to a screen.
public struct StateSummary: Codable, Sendable, Equatable {
    /// The state-reporting domain, such as ``Schema/screenDomain``.
    public let domain: String
    /// The state's label, such as a screen name.
    public let label: String
    /// Time spent in the state, in seconds.
    public let durationSeconds: Double
    /// Metrics measured while in the state.
    public let metrics: MetricSummary

    /// Creates a state summary.
    public init(domain: String, label: String, durationSeconds: Double, metrics: MetricSummary) {
        self.domain = domain
        self.label = label
        self.durationSeconds = durationSeconds
        self.metrics = metrics
    }
}

/// One device's daily report, as stored in the `summary` field of `SPMetricSummary`.
public struct DailyReport: Codable, Sendable, Equatable {
    /// The schema version new reports are written with.
    public static let currentSchemaVersion = 1

    /// The schema version the report was written with.
    public let schemaVersion: Int
    /// Metrics for the whole day.
    public let overall: MetricSummary
    /// Metrics per reported state, such as per screen.
    public let states: [StateSummary]
    /// Whether Low Power Mode was on during the report.
    public let lowPowerMode: Bool
    /// Whether the report came from a TestFlight build.
    public let isTestFlight: Bool
    /// Whether the day spans an app update, mixing two versions.
    public let includesMultipleAppVersions: Bool
    /// Whether MetricKit dropped states because the app reported too many.
    public let exceededStateLimit: Bool

    /// Creates a report with the current schema version.
    public init(overall: MetricSummary, states: [StateSummary] = [], lowPowerMode: Bool = false, isTestFlight: Bool = false, includesMultipleAppVersions: Bool = false, exceededStateLimit: Bool = false) {
        self.schemaVersion = Self.currentSchemaVersion
        self.overall = overall
        self.states = states
        self.lowPowerMode = lowPowerMode
        self.isTestFlight = isTestFlight
        self.includesMultipleAppVersions = includesMultipleAppVersions
        self.exceededStateLimit = exceededStateLimit
    }
}

/// Storage keys for every MetricKit metric in ``MetricSummary``.
///
/// Group aggregation sums cumulative values and takes percentiles over the per-device
/// snapshots in ``distribution``.
public enum MetricKey {
    // Launch: histograms in milliseconds.
    public static let timeToFirstDraw = "timeToFirstDraw"
    public static let optimizedTimeToFirstDraw = "optimizedTimeToFirstDraw"
    public static let extendedLaunch = "extendedLaunch"
    public static let applicationResumeTime = "applicationResumeTime"
    // Responsiveness and animation.
    public static let hangTime = "hangTime"
    public static let hitchRatio = "hitchTime.ratio"
    public static let hitchSeconds = "hitchTime.totalSeconds"
    public static let animationSeconds = "hitchTime.animationSeconds"
    // Run time (seconds).
    public static let foregroundSeconds = "totalForegroundTime.seconds"
    public static let backgroundSeconds = "totalBackgroundTime.seconds"
    public static let backgroundAudioSeconds = "totalBackgroundAudioTime.seconds"
    public static let backgroundLocationSeconds = "totalBackgroundLocationTime.seconds"
    // CPU / GPU.
    public static let cpuSeconds = "cpuTime.seconds"
    public static let cpuInstructions = "cpuInstructionsCount"
    public static let gpuSeconds = "gpuTime.seconds"
    // Memory (MB).
    public static let peakMemoryMB = "peakMemory.mb"
    public static let suspendedMemoryMB = "suspendedMemory.averageMB"
    // Network (MB).
    public static let wifiUploadMB = "totalWiFiUpload.mb"
    public static let wifiDownloadMB = "totalWiFiDownload.mb"
    public static let cellularUploadMB = "totalCellularUpload.mb"
    public static let cellularDownloadMB = "totalCellularDownload.mb"
    public static let cellularConditionBars = "cellularConditionTime"
    // Disk (MB unless noted).
    public static let logicalDiskWritesMB = "logicalDiskWrites.mb"
    public static let binaryFileCount = "totalFileCount.binary"
    public static let dataFileCount = "totalFileCount.data"
    public static let binaryFileSizeMB = "totalFileSize.binaryMB"
    public static let dataFileSizeMB = "totalFileSize.dataMB"
    public static let cacheFolderSizeMB = "totalFileSize.cacheMB"
    public static let cloneSizeMB = "totalFileSize.cloneMB"
    public static let diskCapacityMB = "totalDiskSpace.capacityMB"
    public static let diskUsedMB = "totalDiskSpace.usedMB"
    // Display.
    public static let pixelLuminance = "pixelLuminance.average"
    // Location accuracy time (seconds).
    public static func locationSeconds(_ accuracy: String) -> String { "locationActivityTime.\(accuracy)" }
    // Terminations (counts).
    public static func foregroundTermination(_ reason: String) -> String { "foregroundTermination.\(reason)" }
    public static func backgroundTermination(_ reason: String) -> String { "backgroundTermination.\(reason)" }
    // Metal, one set per layer.
    public static func metalFPS(layer: String) -> String { "metalFrameRate[\(layer)].fps" }
    public static func metalFrames(layer: String) -> String { "metalFrameRate[\(layer)].frames" }
    public static func metalActiveSeconds(layer: String) -> String { "metalFrameRate[\(layer)].activeSeconds" }

    /// Per-device snapshot keys. Groups report their spread, not their sum.
    public static let distribution: Set<String> = [
        peakMemoryMB, suspendedMemoryMB, pixelLuminance, hitchRatio,
        binaryFileSizeMB, dataFileSizeMB, cacheFolderSizeMB, cloneSizeMB, diskCapacityMB, diskUsedMB,
    ]

    /// Whether a key holds a per-device snapshot, including per-layer Metal frame rates.
    ///
    /// - Parameter key: A storage key.
    /// - Returns: `true` for snapshot keys.
    public static func isDistribution(_ key: String) -> Bool {
        distribution.contains(key) || key.hasSuffix("].fps")
    }
}

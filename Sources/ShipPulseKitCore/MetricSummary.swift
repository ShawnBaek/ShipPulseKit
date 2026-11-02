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
    public package(set) var histograms: [MetricKey: Histogram]
    /// Single numbers, such as foreground seconds or peak memory.
    public package(set) var values: [MetricKey: Double]
    /// Whole counts, such as terminations.
    public package(set) var counts: [MetricKey: Int]
    /// Developer-defined signpost intervals, including hitch regions.
    public package(set) var signposts: [SignpostSummary]

    /// Creates a summary.
    public init(histograms: [MetricKey: Histogram] = [:], values: [MetricKey: Double] = [:], counts: [MetricKey: Int] = [:], signposts: [SignpostSummary] = []) {
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
    public let isLowPowerModeEnabled: Bool
    /// Whether the report came from a TestFlight build.
    public let isTestFlight: Bool
    /// Whether the day spans an app update, mixing two versions.
    public let includesMultipleAppVersions: Bool
    /// Whether MetricKit dropped states because the app reported too many.
    public let hasExceededStateLimit: Bool

    // The JSON keys are the 0.1.0 property names; renaming a property must not change them.
    private enum CodingKeys: String, CodingKey {
        case schemaVersion, overall, states, isTestFlight, includesMultipleAppVersions
        case isLowPowerModeEnabled = "lowPowerMode"
        case hasExceededStateLimit = "exceededStateLimit"
    }

    /// Creates a report with the current schema version.
    ///
    /// - Parameters:
    ///   - overall: Metrics for the whole day.
    ///   - states: Metrics per reported state, such as per screen.
    ///   - isLowPowerModeEnabled: Whether Low Power Mode was on.
    ///   - isTestFlight: Whether the report came from a TestFlight build.
    ///   - includesMultipleAppVersions: Whether the day spans an app update.
    ///   - hasExceededStateLimit: Whether MetricKit dropped states.
    public init(overall: MetricSummary, states: [StateSummary] = [], isLowPowerModeEnabled: Bool = false, isTestFlight: Bool = false, includesMultipleAppVersions: Bool = false, hasExceededStateLimit: Bool = false) {
        self.schemaVersion = Self.currentSchemaVersion
        self.overall = overall
        self.states = states
        self.isLowPowerModeEnabled = isLowPowerModeEnabled
        self.isTestFlight = isTestFlight
        self.includesMultipleAppVersions = includesMultipleAppVersions
        self.hasExceededStateLimit = hasExceededStateLimit
    }
}

// 0.1.0 names, kept so the ShipPulse app gets a rename fix-it instead of an error.
extension DailyReport {
    /// Creates a report with the 0.1.0 parameter names.
    ///
    /// `@_disfavoredOverload` keeps calls that use none of the old names on the current
    /// initializer instead of making them ambiguous.
    @available(*, deprecated, message: "Use lowPowerMode → isLowPowerModeEnabled, exceededStateLimit → hasExceededStateLimit.")
    @_disfavoredOverload
    public init(overall: MetricSummary, states: [StateSummary] = [], lowPowerMode: Bool = false, isTestFlight: Bool = false, includesMultipleAppVersions: Bool = false, exceededStateLimit: Bool = false) {
        self.init(overall: overall, states: states, isLowPowerModeEnabled: lowPowerMode, isTestFlight: isTestFlight, includesMultipleAppVersions: includesMultipleAppVersions, hasExceededStateLimit: exceededStateLimit)
    }

    /// The 0.1.0 name of ``isLowPowerModeEnabled``.
    @available(*, deprecated, renamed: "isLowPowerModeEnabled")
    public var lowPowerMode: Bool { isLowPowerModeEnabled }

    /// The 0.1.0 name of ``hasExceededStateLimit``.
    @available(*, deprecated, renamed: "hasExceededStateLimit")
    public var exceededStateLimit: Bool { hasExceededStateLimit }
}

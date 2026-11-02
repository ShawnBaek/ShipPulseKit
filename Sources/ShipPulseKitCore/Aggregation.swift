import Foundation

/// Metrics from a group of devices merged together, for example one device model on one
/// build.
///
/// Histograms are added bucket by bucket, cumulative values and counts are summed, and
/// per-device snapshots keep their spread for percentiles.
///
/// The stored properties are read-only outside the type, so the counts always match what
/// ``add(_:)`` merged.
public struct GroupAggregate: Sendable, Equatable {
    /// The group's key, for example a device model or screen label.
    public private(set) var key: String
    /// How many device reports were added.
    public private(set) var deviceCount: Int
    /// Merged histograms, keyed by ``MetricKey``.
    public private(set) var histograms: [MetricKey: Histogram]
    /// Summed cumulative values, such as foreground seconds.
    public private(set) var totals: [MetricKey: Double]
    /// Summed counts, such as terminations.
    public private(set) var counts: [MetricKey: Int]
    /// One value per device for snapshot metrics, where ``MetricKey/isDistribution`` is `true`.
    public private(set) var samples: [MetricKey: [Double]]

    /// Creates an empty group.
    ///
    /// - Parameter key: The group's key.
    public init(key: String) {
        self.key = key
        self.deviceCount = 0
        self.histograms = [:]
        self.totals = [:]
        self.counts = [:]
        self.samples = [:]
    }

    /// Adds one device's metrics to the group.
    ///
    /// - Parameter summary: The device's metrics.
    public mutating func add(_ summary: MetricSummary) {
        deviceCount += 1
        for (k, h) in summary.histograms { histograms[k] = (histograms[k] ?? Histogram()).merged(with: h) }
        for (k, c) in summary.counts { counts[k, default: 0] += c }
        for (k, v) in summary.values {
            if k.isDistribution { samples[k, default: []].append(v) } else { totals[k, default: 0] += v }
        }
    }

    /// A percentile of a merged histogram.
    ///
    /// ```swift
    /// let p90 = group.percentile(0.9, of: .hangTime)
    /// ```
    ///
    /// - Parameters:
    ///   - p: The percentile, from `0` to `1`.
    ///   - histogramKey: A histogram key, such as ``MetricKey/hangTime``.
    /// - Returns: The value in milliseconds, or `nil` if the group has no such histogram.
    public func percentile(_ p: Double, of histogramKey: MetricKey) -> Double? {
        histograms[histogramKey]?.percentile(p)
    }

    /// A percentile across devices of a snapshot value, such as peak memory.
    ///
    /// - Parameters:
    ///   - p: The percentile, from `0` to `1`.
    ///   - key: A key where ``MetricKey/isDistribution`` is `true`.
    /// - Returns: The nearest device's value, or `nil` if no device reported it.
    public func samplePercentile(_ p: Double, of key: MetricKey) -> Double? {
        guard let values = samples[key], !values.isEmpty else { return nil }
        let sorted = values.sorted()
        return sorted[min(sorted.count - 1, Int(Double(sorted.count - 1) * p + 0.5))]
    }

    /// Hang time per hour of foreground use, in seconds, as Xcode Organizer reports it.
    public var hangSecondsPerHour: Double? {
        guard let foreground = totals[.foregroundSeconds], foreground > 0,
              let hang = histograms[.hangTime] else { return nil }
        let hangMs = hang.buckets.reduce(0.0) { $0 + ($1.start + $1.end) / 2 * Double($1.count) }
        return (hangMs / 1000) / (foreground / 3600)
    }

    /// The group's hitch ratio.
    ///
    /// It divides summed hitch time by summed animation time instead of averaging
    /// per-device ratios, so devices that animate more weigh more.
    public var hitchRatio: Double? {
        guard let animation = totals[.animationSeconds], animation > 0 else { return nil }
        return (totals[.hitchSeconds] ?? 0) / animation
    }

    /// Foreground and background terminations for any reason other than normal.
    public var abnormalTerminations: Int {
        counts.filter {
            switch $0.key {
            case .foregroundTermination(let reason): reason != .normal
            case .backgroundTermination(let reason): reason != .normal
            // A reason added by a newer SDK still counts.
            case .unknown(let raw): (raw.hasPrefix("foregroundTermination.") || raw.hasPrefix("backgroundTermination.")) && !raw.hasSuffix(".normal")
            default: false
            }
        }
            .reduce(0) { $0 + $1.value }
    }
}

// 0.1.0 spellings, kept so the ShipPulse app gets a fix-it instead of an error.
extension GroupAggregate {
    /// The 0.1.0 spelling of ``percentile(_:of:)``.
    ///
    /// - Parameters:
    ///   - histogramKey: The stored histogram key.
    ///   - p: The percentile, from `0` to `1`.
    /// - Returns: The value in milliseconds, or `nil` if the group has no such histogram.
    @available(*, deprecated, renamed: "percentile(_:of:)")
    public func percentile(_ histogramKey: String, _ p: Double) -> Double? {
        percentile(p, of: MetricKey(rawValue: histogramKey))
    }

    /// The 0.1.0 spelling of ``samplePercentile(_:of:)``.
    ///
    /// - Parameters:
    ///   - key: The stored snapshot key.
    ///   - p: The percentile, from `0` to `1`.
    /// - Returns: The nearest device's value, or `nil` if no device reported it.
    @available(*, deprecated, renamed: "samplePercentile(_:of:)")
    public func samplePercentile(_ key: String, _ p: Double) -> Double? {
        samplePercentile(p, of: MetricKey(rawValue: key))
    }

    /// The 0.1.0 argument order of ``percentile(_:of:)``, for calls like
    /// `percentile(MetricKey.hangTime, 0.9)`.
    ///
    /// - Parameters:
    ///   - histogramKey: A histogram key.
    ///   - p: The percentile, from `0` to `1`.
    /// - Returns: The value in milliseconds, or `nil` if the group has no such histogram.
    @available(*, deprecated, renamed: "percentile(_:of:)")
    public func percentile(_ histogramKey: MetricKey, _ p: Double) -> Double? {
        percentile(p, of: histogramKey)
    }

    /// The 0.1.0 argument order of ``samplePercentile(_:of:)``.
    ///
    /// - Parameters:
    ///   - key: A snapshot key.
    ///   - p: The percentile, from `0` to `1`.
    /// - Returns: The nearest device's value, or `nil` if no device reported it.
    @available(*, deprecated, renamed: "samplePercentile(_:of:)")
    public func samplePercentile(_ key: MetricKey, _ p: Double) -> Double? {
        samplePercentile(p, of: key)
    }
}

/// Groups device summaries into ``GroupAggregate`` values.
public enum Aggregation {
    /// Groups summaries by any key, for example device model or screen label.
    ///
    /// - Parameter items: Each device's key and summary.
    /// - Returns: One aggregate per key, largest group first.
    public static func group(_ items: [(key: String, summary: MetricSummary)]) -> [GroupAggregate] {
        var groups: [String: GroupAggregate] = [:]
        for item in items {
            groups[item.key, default: GroupAggregate(key: item.key)].add(item.summary)
        }
        return groups.values.sorted { $0.deviceCount > $1.deviceCount }
    }

    /// Groups summaries by device model.
    ///
    /// - Parameter items: Each device's model identifier and summary.
    /// - Returns: One aggregate per model, largest group first.
    public static func byDeviceModel(_ items: [(deviceModel: String, summary: MetricSummary)]) -> [GroupAggregate] {
        group(items.map { (key: $0.deviceModel, summary: $0.summary) })
    }

    /// Groups per-state metrics across devices, for example per screen.
    ///
    /// - Parameters:
    ///   - reports: Daily reports from many devices.
    ///   - domain: The state domain, such as ``Schema/screenDomain``.
    /// - Returns: One aggregate per state label, largest group first.
    public static func byState(_ reports: [DailyReport], domain: String) -> [GroupAggregate] {
        group(reports.flatMap { report in
            report.states.filter { $0.domain == domain }.map { (key: $0.label, summary: $0.metrics) }
        })
    }
}

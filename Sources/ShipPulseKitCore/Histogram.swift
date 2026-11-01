import Foundation

/// A mergeable histogram.
///
/// MetricKit reports launch and hang times as histograms. Merging them lets the ShipPulse
/// app add histograms from many devices and still read accurate p50 and p90; averaging
/// would hide the slow tail that matters most.
public struct Histogram: Codable, Sendable, Equatable {
    /// One range of a histogram and how many samples fell in it.
    public struct Bucket: Codable, Sendable, Equatable {
        /// The lower bound, in milliseconds.
        public var start: Double
        /// The upper bound, in milliseconds.
        public var end: Double
        /// The number of samples in the range.
        public var count: Int

        /// Creates a bucket.
        public init(start: Double, end: Double, count: Int) {
            self.start = start
            self.end = end
            self.count = count
        }
    }

    /// The buckets, sorted by lower bound.
    public var buckets: [Bucket]

    /// Creates a histogram, sorting the buckets by lower bound.
    public init(buckets: [Bucket] = []) {
        self.buckets = buckets.sorted { $0.start < $1.start }
    }

    /// The number of samples across all buckets.
    public var totalCount: Int { buckets.reduce(0) { $0 + $1.count } }

    /// Adds another histogram's counts, bucket by bucket.
    ///
    /// Buckets with identical bounds are combined.
    ///
    /// - Parameter other: The histogram to add.
    /// - Returns: The merged histogram.
    public func merged(with other: Histogram) -> Histogram {
        var byBounds: [String: Bucket] = [:]
        for bucket in buckets + other.buckets {
            let key = "\(bucket.start)-\(bucket.end)"
            if var existing = byBounds[key] {
                existing.count += bucket.count
                byBounds[key] = existing
            } else {
                byBounds[key] = bucket
            }
        }
        return Histogram(buckets: Array(byBounds.values))
    }

    /// A percentile, interpolated linearly inside the bucket that crosses it.
    ///
    /// - Parameter p: The percentile, from `0` to `1`.
    /// - Returns: The value in milliseconds, or `nil` for an empty histogram.
    public func percentile(_ p: Double) -> Double? {
        let total = totalCount
        guard total > 0 else { return nil }
        let target = max(0, min(1, p)) * Double(total)
        var seen = 0.0
        for bucket in buckets where bucket.count > 0 {
            let next = seen + Double(bucket.count)
            if next >= target {
                let fraction = (target - seen) / Double(bucket.count)
                return bucket.start + (bucket.end - bucket.start) * fraction
            }
            seen = next
        }
        return buckets.last?.end
    }
}

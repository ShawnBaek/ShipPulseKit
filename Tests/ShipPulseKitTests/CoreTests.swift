import Foundation
import Testing
import ShipPulseKitCore

@Suite struct HistogramTests {
    @Test func decodingSortsBuckets() throws {
        let json = Data(#"{"buckets":[{"start":100,"end":200,"count":1},{"start":0,"end":100,"count":1}]}"#.utf8)
        let histogram = try JSONDecoder().decode(Histogram.self, from: json)
        #expect(histogram.buckets.map(\.start) == [0, 100])
        #expect(histogram.percentile(0.25) == 50)
        #expect(try JSONDecoder().decode(Histogram.self, from: JSONEncoder().encode(histogram)) == histogram)
    }

    @Test func percentileInterpolatesInsideBucket() {
        let h = Histogram(buckets: [.init(start: 0, end: 100, count: 50), .init(start: 100, end: 200, count: 50)])
        #expect(h.percentile(0.5) == 100)
        #expect(h.percentile(0.9) == 180)
    }

    @Test func mergeAddsMatchingBuckets() {
        let a = Histogram(buckets: [.init(start: 0, end: 100, count: 2)])
        let b = Histogram(buckets: [.init(start: 0, end: 100, count: 3), .init(start: 100, end: 200, count: 1)])
        let merged = a.merged(with: b)
        #expect(merged.totalCount == 6)
        #expect(merged.buckets.first == .init(start: 0, end: 100, count: 5))
    }

    @Test func emptyHistogramHasNoPercentile() {
        #expect(Histogram().percentile(0.5) == nil)
    }
}

@Suite struct AggregationTests {
    private func summary(launch: [Histogram.Bucket], foreground: Double, hitch: Double = 0, animation: Double = 0, memory: Double? = nil) -> MetricSummary {
        var values: [String: Double] = [MetricKey.foregroundSeconds: foreground, MetricKey.hitchSeconds: hitch, MetricKey.animationSeconds: animation]
        if let memory { values[MetricKey.peakMemoryMB] = memory }
        return MetricSummary(histograms: [MetricKey.timeToFirstDraw: Histogram(buckets: launch)], values: values, counts: [MetricKey.foregroundTermination("watchdog"): 1])
    }

    @Test func groupsByDeviceModelAndKeepsTail() {
        let fast = summary(launch: [.init(start: 0, end: 500, count: 9)], foreground: 3600, memory: 150)
        let slow = summary(launch: [.init(start: 2000, end: 3000, count: 1)], foreground: 3600, memory: 400)
        let groups = Aggregation.byDeviceModel([("iPhone13,1", fast), ("iPhone13,1", slow), ("iPhone17,1", fast)])
        let mini = groups.first { $0.key == "iPhone13,1" }!
        #expect(mini.deviceCount == 2)
        #expect((mini.percentile(MetricKey.timeToFirstDraw, 0.95) ?? 0) >= 2000)
        #expect((mini.percentile(MetricKey.timeToFirstDraw, 0.5) ?? .infinity) < 500)
        #expect(mini.totals[MetricKey.foregroundSeconds] == 7200)
        #expect(mini.samplePercentile(MetricKey.peakMemoryMB, 1) == 400)
        #expect(mini.abnormalTerminations == 2)
    }

    @Test func hitchRatioUsesSummedTimes() {
        let a = summary(launch: [], foreground: 60, hitch: 1, animation: 10)
        let b = summary(launch: [], foreground: 60, hitch: 9, animation: 90)
        let group = Aggregation.group([("x", a), ("x", b)])[0]
        #expect(group.hitchRatio == 0.1)
    }

    @Test func groupsByScreenState() {
        let feed = StateSummary(domain: Schema.screenDomain, label: "Feed", durationSeconds: 60, metrics: MetricSummary(values: [MetricKey.hitchSeconds: 2, MetricKey.animationSeconds: 20]))
        let settings = StateSummary(domain: Schema.screenDomain, label: "Settings", durationSeconds: 30, metrics: MetricSummary(values: [MetricKey.hitchSeconds: 0, MetricKey.animationSeconds: 10]))
        let reports = [DailyReport(overall: MetricSummary(), states: [feed, settings]), DailyReport(overall: MetricSummary(), states: [feed])]
        let screens = Aggregation.byState(reports, domain: Schema.screenDomain)
        #expect(screens.first?.key == "Feed")
        #expect(screens.first?.deviceCount == 2)
        #expect(screens.first?.hitchRatio == 0.1)
    }
}

@Suite struct SamplingTests {
    @Test func samplingIsDeterministicPerInstall() {
        let id = "8D1B6C2E-1111-4E0A-9C8B-000000000001"
        #expect(Sampling.includes(installID: id, rate: 0.3) == Sampling.includes(installID: id, rate: 0.3))
        #expect(Sampling.includes(installID: id, rate: 1))
        #expect(!Sampling.includes(installID: id, rate: 0))
    }

    @Test func samplingRateApproximatesShare() {
        let included = (0..<10_000).filter { Sampling.includes(installID: "install-\($0)", rate: 0.25) }.count
        #expect((2_200...2_800).contains(included))
    }

    @Test func recommendedRateKeepsSmallAppsAtFullRate() {
        #expect(Sampling.recommendedRate(largestGroupDevices: 120) == 1)
        #expect(Sampling.recommendedRate(largestGroupDevices: 3_000) == 0.1)
        #expect(Sampling.recommendedRate(largestGroupDevices: 1_000_000) == 0.01)
    }
}

@Suite struct MetricEnumTests {
    @Test func coversAllThirtyMetricResultCases() {
        #expect(Metric.allCases.count == 30)
    }

    @Test func everyGroupHasMetrics() {
        #expect(Metric.Group.allCases.allSatisfy { !Metric.cases(in: $0).isEmpty })
    }

    @Test func storageKeysAreUnique() {
        let keys = Metric.allCases.flatMap(\.storageKeys)
        #expect(Set(keys).count == keys.count)
    }

    @Test func reportedMetricsReadsSummary() {
        let summary = MetricSummary(histograms: [MetricKey.hangTime: Histogram()], values: [MetricKey.peakMemoryMB: 120], counts: [MetricKey.foregroundTermination("watchdog"): 1])
        #expect(summary.reportedMetrics == [.hangTime, .foregroundTermination, .peakMemory])
    }
}

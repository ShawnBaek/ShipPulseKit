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
        var values: [MetricKey: Double] = [MetricKey.foregroundSeconds: foreground, MetricKey.hitchSeconds: hitch, MetricKey.animationSeconds: animation]
        if let memory { values[MetricKey.peakMemoryMB] = memory }
        return MetricSummary(histograms: [MetricKey.timeToFirstDraw: Histogram(buckets: launch)], values: values, counts: [MetricKey.foregroundTermination(.watchdog): 1])
    }

    @Test func groupsByDeviceModelAndKeepsTail() {
        let fast = summary(launch: [.init(start: 0, end: 500, count: 9)], foreground: 3600, memory: 150)
        let slow = summary(launch: [.init(start: 2000, end: 3000, count: 1)], foreground: 3600, memory: 400)
        let groups = Aggregation.byDeviceModel([("iPhone13,1", fast), ("iPhone13,1", slow), ("iPhone17,1", fast)])
        let mini = groups.first { $0.key == "iPhone13,1" }!
        #expect(mini.deviceCount == 2)
        #expect((mini.percentile(0.95, of: .timeToFirstDraw) ?? 0) >= 2000)
        #expect((mini.percentile(0.5, of: .timeToFirstDraw) ?? .infinity) < 500)
        #expect(mini.totals[MetricKey.foregroundSeconds] == 7200)
        #expect(mini.samplePercentile(1, of: .peakMemoryMB) == 400)
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
        #expect(Sampling.recommendedRate(largestGroupDeviceCount: 120) == 1)
        #expect(Sampling.recommendedRate(largestGroupDeviceCount: 3_000) == 0.1)
        #expect(Sampling.recommendedRate(largestGroupDeviceCount: 1_000_000) == 0.01)
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
        let summary = MetricSummary(histograms: [MetricKey.hangTime: Histogram()], values: [MetricKey.peakMemoryMB: 120], counts: [MetricKey.foregroundTermination(.watchdog): 1])
        #expect(summary.reportedMetrics == [.hangTime, .foregroundTermination, .peakMemory])
    }
}

@Suite struct MetricKeyTests {
    /// A `DailyReport` exactly as 0.1.0 encodes it with `.sortedKeys`.
    private let golden = #"{"exceededStateLimit":false,"includesMultipleAppVersions":false,"isTestFlight":true,"lowPowerMode":false,"overall":{"counts":{"backgroundTermination.taskTimeout":2,"foregroundTermination.watchdog":1},"histograms":{"hangTime":{"buckets":[{"count":3,"end":250,"start":0}]}},"signposts":[{"category":"ShipPulse","count":4,"duration":{"buckets":[]},"hitchRatio":0.01,"name":"PhotoGrid"}],"values":{"hitchTime.ratio":0.02,"locationActivityTime.tenMeters":12,"metalFrameRate[Game].fps":59.5,"peakMemory.mb":182.5,"someFutureMetric":7}},"schemaVersion":1,"states":[{"domain":"shippulse.screen","durationSeconds":120,"label":"Feed","metrics":{"counts":{},"histograms":{},"signposts":[],"values":{"hitchTime.ratio":0.03}}}]}"#

    @Test func goldenReportRoundTripsByteForByte() throws {
        let report = try JSONDecoder().decode(DailyReport.self, from: Data(golden.utf8))
        #expect(report.overall.values[.hitchRatio] == 0.02)
        #expect(report.overall.values[.locationSeconds(.tenMeters)] == 12)
        #expect(report.overall.values[.metalFPS(layer: "Game")] == 59.5)
        #expect(report.overall.counts[.foregroundTermination(.watchdog)] == 1)
        #expect(report.overall.counts[.backgroundTermination(.taskTimeout)] == 2)
        #expect(report.overall.histograms[.hangTime]?.totalCount == 3)
        #expect(report.overall.values[.unknown("someFutureMetric")] == 7)
        #expect(report.isTestFlight && !report.isLowPowerModeEnabled)

        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        #expect(String(decoding: try encoder.encode(report), as: UTF8.self) == golden)
    }

    /// Every key string 0.1.0 wrote, from its `MetricKey` string constants.
    private let shipped: [String: MetricKey] = [
        "timeToFirstDraw": .timeToFirstDraw, "optimizedTimeToFirstDraw": .optimizedTimeToFirstDraw,
        "extendedLaunch": .extendedLaunch, "applicationResumeTime": .applicationResumeTime,
        "hangTime": .hangTime, "hitchTime.ratio": .hitchRatio, "hitchTime.totalSeconds": .hitchSeconds,
        "hitchTime.animationSeconds": .animationSeconds, "totalForegroundTime.seconds": .foregroundSeconds,
        "totalBackgroundTime.seconds": .backgroundSeconds, "totalBackgroundAudioTime.seconds": .backgroundAudioSeconds,
        "totalBackgroundLocationTime.seconds": .backgroundLocationSeconds, "cpuTime.seconds": .cpuSeconds,
        "cpuInstructionsCount": .cpuInstructions, "gpuTime.seconds": .gpuSeconds, "peakMemory.mb": .peakMemoryMB,
        "suspendedMemory.averageMB": .suspendedMemoryMB, "totalWiFiUpload.mb": .wifiUploadMB,
        "totalWiFiDownload.mb": .wifiDownloadMB, "totalCellularUpload.mb": .cellularUploadMB,
        "totalCellularDownload.mb": .cellularDownloadMB, "cellularConditionTime": .cellularConditionBars,
        "logicalDiskWrites.mb": .logicalDiskWritesMB, "totalFileCount.binary": .binaryFileCount,
        "totalFileCount.data": .dataFileCount, "totalFileSize.binaryMB": .binaryFileSizeMB,
        "totalFileSize.dataMB": .dataFileSizeMB, "totalFileSize.cacheMB": .cacheFolderSizeMB,
        "totalFileSize.cloneMB": .cloneSizeMB, "totalDiskSpace.capacityMB": .diskCapacityMB,
        "totalDiskSpace.usedMB": .diskUsedMB, "pixelLuminance.average": .pixelLuminance,
        "foregroundTermination.memoryLimit": .foregroundTermination(.memoryLimit),
        "backgroundTermination.fileLock": .backgroundTermination(.fileLock),
        "locationActivityTime.reducedAccuracy": .locationSeconds(.reducedAccuracy),
        "metalFrameRate[Layer].frames": .metalFrames(layer: "Layer"),
        "metalFrameRate[Layer].activeSeconds": .metalActiveSeconds(layer: "Layer"),
    ]

    private func isUnknown(_ key: MetricKey) -> Bool {
        if case .unknown = key { true } else { false }
    }

    @Test func everyShippedStringMapsToItsCase() {
        for (string, key) in shipped {
            let parsed = MetricKey(rawValue: string)
            #expect(!isUnknown(parsed), "\(string) parsed as unknown")
            #expect(parsed.rawValue == string)
            #expect(key.rawValue == string)
        }
    }

    @Test func everyKnownKeyRoundTrips() {
        for key in MetricKey.allKnown {
            #expect(!isUnknown(MetricKey(rawValue: key.rawValue)), "\(key.rawValue)")
        }
        #expect(Set(MetricKey.allKnown.map(\.rawValue)).count == MetricKey.allKnown.count)
    }

    @Test func unknownKeyRoundTrips() throws {
        let key = MetricKey(rawValue: "foregroundTermination.someNewReason")
        #expect(isUnknown(key))
        #expect(key.rawValue == "foregroundTermination.someNewReason")
        let data = try JSONEncoder().encode([key: 1.0])
        #expect(String(decoding: data, as: UTF8.self) == #"{"foregroundTermination.someNewReason":1}"#)
        #expect(try JSONDecoder().decode([MetricKey: Double].self, from: data) == [key: 1])
    }

    @Test func snapshotKeysAreDistributions() {
        #expect(MetricKey.peakMemoryMB.isDistribution)
        #expect(MetricKey.metalFPS(layer: "Game").isDistribution)
        #expect(!MetricKey.foregroundSeconds.isDistribution)
    }
}

@Suite struct SchemaTests {
    @Test func recordTypeAndFieldNamesAreUnchanged() {
        #expect(Schema.RecordType.allCases.map(\.rawValue) == ["SPMetricSummary", "SPDiagnosticPayload", "SPInstall", "SPActiveDay", "SPConfig"])
        #expect(Schema.Field.sampleRate.rawValue == "sampleRate")
        #expect(Schema.Field.lowPowerMode.rawValue == "lowPowerMode")
        #expect(Schema.Field.allCases.count == 26)
    }
}

import Foundation
import Testing
import ShipPulseKitCore
@testable import ShipPulseKit

private let context = RecordContext(bundleIdentifier: "com.example.app", appVersion: "2.4", buildVersion: "120", osVersion: "26.1.0", deviceModel: "iPhone18,1")

private func freshDefaults() -> UserDefaults {
    let name = "ShipPulseKitTests-\(UUID().uuidString)"
    return UserDefaults(suiteName: name)!
}

private func day(_ iso: String) -> Date {
    ISO8601DateFormatter().date(from: iso)!
}

@Suite struct RetentionTrackerTests {
    @Test func firstLaunchEmitsInstallAndActiveDay() {
        let tracker = RetentionTracker(defaults: freshDefaults())
        let records = tracker.records(at: day("2026-11-01T09:00:00Z"), context: context)
        #expect(records.map(\.kind) == [.install, .activeDay])
        #expect(records[1].fields["daysSinceInstall"] == .int(0))
    }

    @Test func sameDayEmitsNothing() {
        let tracker = RetentionTracker(defaults: freshDefaults())
        _ = tracker.records(at: day("2026-11-01T09:00:00Z"), context: context)
        #expect(tracker.records(at: day("2026-11-01T22:00:00Z"), context: context).isEmpty)
    }

    @Test func laterDayEmitsActiveDayWithDayIndex() {
        let tracker = RetentionTracker(defaults: freshDefaults())
        let first = tracker.records(at: day("2026-11-01T09:00:00Z"), context: context)
        let later = tracker.records(at: day("2026-11-08T09:00:00Z"), context: context)
        #expect(later.map(\.kind) == [.activeDay])
        #expect(later[0].fields["daysSinceInstall"] == .int(7))
        #expect(later[0].fields["installID"] == first[0].fields["installID"])
    }
}

@Suite struct PayloadMapperTests {
    @Test func summaryRecordCarriesDecodableReport() throws {
        let report = DailyReport(
            overall: MetricSummary(histograms: [MetricKey.timeToFirstDraw: Histogram(buckets: [.init(start: 0, end: 100, count: 3)])], values: [MetricKey.peakMemoryMB: 182]),
            states: [StateSummary(domain: Schema.screenDomain, label: "Feed", durationSeconds: 120, metrics: MetricSummary(values: [MetricKey.hitchRatio: 0.02]))],
            isTestFlight: true
        )
        let begin = day("2026-10-31T00:00:00Z")
        let record = PayloadMapper.summaryRecord(report: report, rawJSON: Data("{}".utf8), begin: begin, end: day("2026-11-01T00:00:00Z"), installID: "abc", context: context, now: Date())
        #expect(record.kind.recordType == "SPMetricSummary")
        #expect(record.recordName == "summary-abc-\(Int64(begin.timeIntervalSince1970))")
        #expect(record.fields["isTestFlight"] == .int(1))
        guard case .bytes(let body) = record.fields["summary"] else { Issue.record("missing summary"); return }
        let decoded = try JSONDecoder().decode(DailyReport.self, from: try (body as NSData).decompressed(using: .zlib) as Data)
        #expect(decoded == report)
    }

    @Test func diagnosticRecordNameIsStableAndQueryable() {
        let json = Data(#"{"result":"hang"}"#.utf8)
        let a = PayloadMapper.diagnosticRecord(json: json, kind: "hang", durationMs: 2400, extraFields: [:], isTestFlight: false, begin: Date(), end: Date(), context: context, now: Date())
        let b = PayloadMapper.diagnosticRecord(json: json, kind: "hang", durationMs: 2400, extraFields: [:], isTestFlight: false, begin: Date(), end: Date(), context: context, now: Date())
        #expect(a.recordName == b.recordName)
        #expect(a.fields["kind"] == .string("hang"))
        #expect(a.fields["durationMs"] == .double(2400))
    }

    @Test func compressedPayloadRoundTrips() throws {
        let json = Data(String(repeating: #"{"histogram":[1,2,3]},"#, count: 200).utf8)
        let record = PayloadMapper.diagnosticRecord(json: json, kind: "crash", durationMs: nil, extraFields: [:], isTestFlight: false, begin: Date(), end: Date(), context: context, now: Date())
        guard case .bytes(let body) = record.fields["payload"] else { Issue.record("missing payload"); return }
        #expect(try (body as NSData).decompressed(using: .zlib) as Data == json)
    }
}

@Suite struct UploadQueueTests {
    private func makeQueue(maxCount: Int = 500, maxAge: TimeInterval = 3600) -> UploadQueue {
        let dir = FileManager.default.temporaryDirectory.appending(path: "ShipPulseKitTests-\(UUID().uuidString)")
        return UploadQueue(directory: dir, maxAge: maxAge, maxCount: maxCount)
    }

    private func record(_ name: String, at date: Date = Date()) -> PendingRecord {
        PendingRecord(kind: .activeDay, recordName: name, fields: ["day": .string("2026-11-01")], createdAt: date)
    }

    @Test func persistsUntilRemoved() async throws {
        let queue = makeQueue()
        try await queue.enqueue([record("a"), record("b")])
        #expect(try await queue.count() == 2)
        await queue.remove(["a"])
        #expect(try await queue.pending(limit: 10).map(\.recordName) == ["b"])
    }

    @Test func dropsOverflowOldestFirst() async throws {
        let queue = makeQueue(maxCount: 2)
        let now = Date()
        try await queue.enqueue([record("old", at: now - 30), record("mid", at: now - 20), record("new", at: now - 10)])
        #expect(try await queue.pending(limit: 10).map(\.recordName) == ["mid", "new"])
    }

    @Test func dropsExpired() async throws {
        let queue = makeQueue(maxAge: 60)
        try await queue.enqueue([record("stale", at: Date() - 3600), record("fresh")])
        #expect(try await queue.pending(limit: 10).map(\.recordName) == ["fresh"])
    }
}

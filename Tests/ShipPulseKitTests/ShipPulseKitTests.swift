import CloudKit
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

@Suite struct DiagnosticRedactionTests {
    @Test func removesExceptionStringsAtAnyDepth() throws {
        let json = Data(#"{"result":{"crash":{"exceptionReason":{"composedMessage":"user@example.com","arguments":["secret"],"className":"NSInvalidArgumentException"}}}}"#.utf8)
        let redacted = try #require(PayloadMapper.redactedDiagnosticJSON(json))
        let text = String(decoding: redacted, as: UTF8.self)
        #expect(!text.contains("user@example.com"))
        #expect(!text.contains("secret"))
        #expect(text.contains("NSInvalidArgumentException"))
    }

    @Test func keyOrderDoesNotChangeTheRecordName() throws {
        let a = try #require(PayloadMapper.redactedDiagnosticJSON(Data(#"{"b":1,"a":{"y":2,"x":3}}"#.utf8)))
        let b = try #require(PayloadMapper.redactedDiagnosticJSON(Data(#"{"a":{"x":3,"y":2},"b":1}"#.utf8)))
        #expect(a == b)
    }

    @Test func rejectsNonJSON() {
        #expect(PayloadMapper.redactedDiagnosticJSON(Data()) == nil)
    }
}

@Suite struct UploadSplittingTests {
    private func records(_ count: Int) -> [PendingRecord] {
        (0..<count).map { PendingRecord(kind: .activeDay, recordName: "r\($0)", fields: [:], createdAt: Date()) }
    }

    @Test func splitsBatchesOverTheLimit() async throws {
        var requests: [Int] = []
        let accepted = try await CloudKitUploader.uploadSplitting(records(10)) { batch in
            requests.append(batch.count)
            if batch.count > 3 { throw CKError(.limitExceeded) }
            return batch.map(\.recordName)
        }
        #expect(Set(accepted) == Set(records(10).map(\.recordName)))
        #expect(requests.first == 10)
    }

    @Test func dropsASingleRecordThatIsTooLarge() async throws {
        let accepted = try await CloudKitUploader.uploadSplitting(records(1)) { _ in throw CKError(.limitExceeded) }
        #expect(accepted == ["r0"])
    }

    @Test func rethrowsOtherErrors() async {
        await #expect(throws: CKError.self) {
            _ = try await CloudKitUploader.uploadSplitting(records(4)) { _ in throw CKError(.networkUnavailable) }
        }
    }
}

private actor RecordingUploader: RecordUploading {
    private(set) var batches: [[String]] = []

    func isAvailable() async -> Bool { true }

    func upload(_ records: [PendingRecord]) async throws -> [String] {
        let names = records.map(\.recordName)
        batches.append(names)
        return names
    }

    func fetchSamplingConfig(bundleID: String) async -> RemoteSamplingConfig? { nil }
}

@Suite struct EngineFlushTests {
    @MainActor @Test func uploadsTheWholeQueueInBatches() async throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: "ShipPulseKitTests-\(UUID().uuidString)")
        let queue = UploadQueue(directory: dir, maxAge: 3600, maxCount: 500)
        let uploader = RecordingUploader()
        let engine = try Engine(
            configuration: Configuration(sampling: .fixed(1), diagnosticSampling: .fixed(1)),
            queue: queue,
            uploader: uploader,
            defaults: freshDefaults(),
            context: context
        )
        let now = Date()
        let records = (0..<150).map {
            PendingRecord(kind: .activeDay, recordName: "r\($0)", fields: [:], createdAt: now + Double($0))
        }
        await engine.enqueue(records)
        #expect(await uploader.batches.map(\.count) == [100, 50])
        #expect(try await queue.count() == 0)
    }
}

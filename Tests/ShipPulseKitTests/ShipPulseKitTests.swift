import CloudKit
import Foundation
import Testing
import ShipPulseKitCore
@testable import ShipPulseKit

private let context = RecordContext(bundleIdentifier: "com.example.app", appVersion: "2.4", buildVersion: "120", osVersion: "26.1.0", deviceModel: "iPhone18,1")

private func freshSuite() -> String {
    "ShipPulseKitTests-\(UUID().uuidString)"
}

private func day(_ iso: String) -> Date {
    ISO8601DateFormatter().date(from: iso)!
}

@Suite struct RetentionTrackerTests {
    private let fresh = RetentionTracker.State(installID: "abc")

    @Test func firstLaunchEmitsInstallAndActiveDay() {
        let (records, state) = RetentionTracker.records(for: fresh, at: day("2026-11-01T09:00:00Z"), context: context)
        #expect(records.map(\.kind) == [.install, .activeDay])
        #expect(records[1].fields[.daysSinceInstall] == .int(0))
        #expect(state == RetentionTracker.State(installID: "abc", firstLaunch: day("2026-11-01T09:00:00Z"), lastActiveDay: "2026-11-01"))
    }

    @Test func sameDayEmitsNothing() {
        let (_, state) = RetentionTracker.records(for: fresh, at: day("2026-11-01T09:00:00Z"), context: context)
        let (records, unchanged) = RetentionTracker.records(for: state, at: day("2026-11-01T22:00:00Z"), context: context)
        #expect(records.isEmpty)
        #expect(unchanged == state)
    }

    @Test func laterDayEmitsActiveDayWithDayIndex() {
        let (first, state) = RetentionTracker.records(for: fresh, at: day("2026-11-01T09:00:00Z"), context: context)
        let (later, _) = RetentionTracker.records(for: state, at: day("2026-11-08T09:00:00Z"), context: context)
        #expect(later.map(\.kind) == [.activeDay])
        #expect(later[0].fields[.daysSinceInstall] == .int(7))
        #expect(later[0].fields[.installID] == first[0].fields[.installID])
        #expect(later[0].recordName == "active-abc-2026-11-08")
    }

    @Test func daysAreUTC() {
        #expect(RetentionTracker.dayString(day("2026-11-01T23:59:59Z")) == "2026-11-01")
        #expect(RetentionTracker.daysBetween(day("2026-11-01T23:00:00Z"), day("2026-11-02T01:00:00Z")) == 1)
    }
}

@Suite struct PendingRecordFormatTests {
    @Test func fieldsStayAJSONObjectKeyedByName() throws {
        let record = PendingRecord(kind: .activeDay, recordName: "a", fields: [.day: .string("2026-11-01")], createdAt: Date())
        let json = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(record)) as? [String: Any])
        let fields = try #require(json["fields"] as? [String: Any])
        #expect(Array(fields.keys) == ["day"])
        #expect(try JSONDecoder().decode(PendingRecord.self, from: JSONEncoder().encode(record)) == record)
    }

    @Test func decodesARecordQueuedBy010() throws {
        let json = #"{"kind":"activeDay","recordName":"active-x-2026-11-01","fields":{"day":{"string":{"_0":"2026-11-01"}},"daysSinceInstall":{"int":{"_0":3}}},"createdAt":800000000}"#
        let record = try JSONDecoder().decode(PendingRecord.self, from: Data(json.utf8))
        #expect(record.fields[.day] == .string("2026-11-01"))
        #expect(record.fields[.daysSinceInstall] == .int(3))
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
        #expect(record.fields[.isTestFlight] == .int(1))
        guard case .bytes(let body) = record.fields[.summary] else { Issue.record("missing summary"); return }
        let decoded = try JSONDecoder().decode(DailyReport.self, from: try (body as NSData).decompressed(using: .zlib) as Data)
        #expect(decoded == report)
    }

    @Test func diagnosticRecordNameIsStableAndQueryable() {
        let json = Data(#"{"result":"hang"}"#.utf8)
        let a = PayloadMapper.diagnosticRecord(json: json, kind: "hang", durationMs: 2400, extraFields: [:], isTestFlight: false, begin: Date(), end: Date(), context: context, now: Date())
        let b = PayloadMapper.diagnosticRecord(json: json, kind: "hang", durationMs: 2400, extraFields: [:], isTestFlight: false, begin: Date(), end: Date(), context: context, now: Date())
        #expect(a.recordName == b.recordName)
        #expect(a.fields[.kind] == .string("hang"))
        #expect(a.fields[.durationMs] == .double(2400))
    }

    @Test func compressedPayloadRoundTrips() throws {
        let json = Data(String(repeating: #"{"histogram":[1,2,3]},"#, count: 200).utf8)
        let record = PayloadMapper.diagnosticRecord(json: json, kind: "crash", durationMs: nil, extraFields: [:], isTestFlight: false, begin: Date(), end: Date(), context: context, now: Date())
        guard case .bytes(let body) = record.fields[.payload] else { Issue.record("missing payload"); return }
        #expect(try (body as NSData).decompressed(using: .zlib) as Data == json)
    }
}

private func temporaryDirectory() -> URL {
    FileManager.default.temporaryDirectory.appending(path: "ShipPulseKitTests-\(UUID().uuidString)")
}

@Suite struct DataContainerTests {
    private func makeContainer(directory: URL = temporaryDirectory(), suite: String = freshSuite(), maxCount: Int = 500, maxAge: TimeInterval = 3600) -> DataContainer {
        DataContainer(directory: directory, maxAge: maxAge, maxCount: maxCount, defaultsSuite: suite)
    }

    private func record(_ name: String, at date: Date = Date()) -> PendingRecord {
        PendingRecord(kind: .activeDay, recordName: name, fields: [.day: .string("2026-11-01")], createdAt: date)
    }

    @Test func persistsUntilRemoved() async throws {
        let container = makeContainer()
        try await container.enqueue([record("a"), record("b")])
        #expect(try await container.pendingCount() == 2)
        await container.remove(["a"])
        #expect(try await container.pending(limit: 10).map(\.recordName) == ["b"])
    }

    @Test func pendingRecordsSurviveANewContainer() async throws {
        let directory = temporaryDirectory()
        let written = record("a")
        try await makeContainer(directory: directory).enqueue([written])
        #expect(try await makeContainer(directory: directory).pending(limit: 10) == [written])
    }

    @Test func reenqueueOverwrites() async throws {
        let container = makeContainer()
        try await container.enqueue([record("a")])
        try await container.enqueue([record("a")])
        #expect(try await container.pendingCount() == 1)
    }

    @Test func dropsOverflowOldestFirst() async throws {
        let container = makeContainer(maxCount: 2)
        let now = Date()
        try await container.enqueue([record("old", at: now - 30), record("mid", at: now - 20), record("new", at: now - 10)])
        #expect(try await container.pending(limit: 10).map(\.recordName) == ["mid", "new"])
    }

    @Test func dropsExpired() async throws {
        let container = makeContainer(maxAge: 60)
        try await container.enqueue([record("stale", at: Date() - 3600), record("fresh")])
        #expect(try await container.pending(limit: 10).map(\.recordName) == ["fresh"])
    }

    @Test func installIDIsStableAcrossContainers() async throws {
        let suite = freshSuite()
        let defaults = try #require(UserDefaults(suiteName: suite))
        let id = await makeContainer(suite: suite).installID()
        #expect(await makeContainer(suite: suite).installID() == id)
        #expect(defaults.string(forKey: "ShipPulseKit.installID") == id)
    }

    @Test func retentionStatePersistsUnderTheShippedKeys() async throws {
        let suite = freshSuite()
        let defaults = try #require(UserDefaults(suiteName: suite))
        let launch = day("2026-11-01T09:00:00Z")
        let first = await makeContainer(suite: suite).updateRetention { RetentionTracker.records(for: $0, at: launch, context: context) }
        #expect(first.count == 2)
        #expect(defaults.object(forKey: "ShipPulseKit.firstLaunch") as? Date == launch)
        #expect(defaults.string(forKey: "ShipPulseKit.lastActiveDay") == "2026-11-01")
        let again = await makeContainer(suite: suite).updateRetention { RetentionTracker.records(for: $0, at: launch + 3600, context: context) }
        #expect(again.isEmpty)
    }

    @Test func readsStateWrittenBy010() async throws {
        let suite = freshSuite()
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.set("legacy-id", forKey: "ShipPulseKit.installID")
        defaults.set(day("2026-10-01T00:00:00Z"), forKey: "ShipPulseKit.firstLaunch")
        defaults.set("2026-10-31", forKey: "ShipPulseKit.lastActiveDay")
        defaults.set(0.25, forKey: "ShipPulseKit.sampleRate")
        let container = makeContainer(suite: suite)
        let records = await container.updateRetention { RetentionTracker.records(for: $0, at: day("2026-11-01T09:00:00Z"), context: context) }
        #expect(records.map(\.recordName) == ["active-legacy-id-2026-11-01"])
        #expect(records[0].fields[.daysSinceInstall] == .int(31))
        #expect(await container.sampling().sampleRate == 0.25)
    }

    @Test func samplingRoundTrips() async {
        let suite = freshSuite()
        let fetchedAt = day("2026-11-01T09:00:00Z")
        await makeContainer(suite: suite).saveSampling(RemoteSamplingConfig(sampleRate: 0.5, diagnosticSampleRate: 0.1), fetchedAt: fetchedAt)
        let stored = await makeContainer(suite: suite).sampling()
        #expect(stored == DataContainer.StoredSampling(sampleRate: 0.5, diagnosticSampleRate: 0.1, fetchedAt: fetchedAt))
    }

    @Test func undecodableFilesExpireByModificationDate() async throws {
        let directory = temporaryDirectory()
        let container = makeContainer(directory: directory, maxAge: 60)
        try await container.enqueue([record("fresh")])
        let stale = directory.appending(path: "from-newer-sdk.json")
        try Data(#"{"kind":"someFutureKind"}"#.utf8).write(to: stale)
        try FileManager.default.setAttributes([.modificationDate: Date() - 3600], ofItemAtPath: stale.path(percentEncoded: false))
        let recent = directory.appending(path: "recent-unknown.json")
        try Data("not json".utf8).write(to: recent)
        try await container.prune(now: Date())
        #expect(!FileManager.default.fileExists(atPath: stale.path(percentEncoded: false)))
        #expect(FileManager.default.fileExists(atPath: recent.path(percentEncoded: false)))
        #expect(try await container.pending(limit: 10).map(\.recordName) == ["fresh"])
    }

    @Test func defaultDirectoryIsThe010Queue() {
        #expect(DataContainer.defaultDirectory().path(percentEncoded: false).hasSuffix("Application Support/ShipPulseKit/Queue/"))
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
    private let rejecting: Set<String>
    private let config: RemoteSamplingConfig?

    init(rejecting: Set<String> = [], config: RemoteSamplingConfig? = nil) {
        self.rejecting = rejecting
        self.config = config
    }

    func isAvailable() async -> Bool { true }

    func upload(_ records: [PendingRecord]) async throws -> [String] {
        let names = records.map(\.recordName)
        batches.append(names)
        return names.filter { !rejecting.contains($0) }
    }

    func fetchSamplingConfig(bundleID: String) async -> RemoteSamplingConfig? { config }
}

@Suite struct EngineTests {
    @MainActor private func makeEngine(_ uploader: RecordingUploader, configuration: Configuration = Configuration(sampling: .fixed(rate: 1), diagnosticSampling: .fixed(rate: 1))) throws -> (Engine, DataContainer) {
        let container = DataContainer(directory: temporaryDirectory(), maxAge: 3600, maxCount: 500, defaultsSuite: freshSuite())
        let engine = try Engine(configuration: configuration, container: container, uploader: uploader, context: context)
        return (engine, container)
    }

    @MainActor @Test func uploadsTheWholeQueueInBatches() async throws {
        let uploader = RecordingUploader()
        let (engine, container) = try makeEngine(uploader)
        let now = Date()
        let records = (0..<150).map {
            PendingRecord(kind: .activeDay, recordName: "r\($0)", fields: [:], createdAt: now + Double($0))
        }
        await engine.enqueue(records)
        #expect(await uploader.batches.map(\.count) == [100, 50])
        #expect(try await container.pendingCount() == 0)
    }

    @MainActor @Test func keepsRecordsCloudKitDidNotAccept() async throws {
        let uploader = RecordingUploader(rejecting: ["b"])
        let (engine, container) = try makeEngine(uploader)
        await engine.enqueue(["a", "b", "c"].map { PendingRecord(kind: .activeDay, recordName: $0, fields: [:], createdAt: Date()) })
        #expect(try await container.pending(limit: 10).map(\.recordName) == ["b"])
    }

    @MainActor @Test func stampsTheSampleRate() async throws {
        let uploader = RecordingUploader(rejecting: ["a"])
        let (engine, container) = try makeEngine(uploader)
        await engine.enqueue([PendingRecord(kind: .activeDay, recordName: "a", fields: [:], createdAt: Date())])
        #expect(try await container.pending(limit: 1).first?.fields[.sampleRate] == .double(1))
    }

    @MainActor @Test func zeroRateQueuesNothing() async throws {
        let uploader = RecordingUploader()
        let (engine, container) = try makeEngine(uploader, configuration: Configuration(sampling: .fixed(rate: 0)))
        await engine.enqueue([PendingRecord(kind: .activeDay, recordName: "a", fields: [:], createdAt: Date())])
        #expect(try await container.pendingCount() == 0)
        #expect(await uploader.batches.isEmpty)
    }

    @MainActor @Test func storesPublishedRatesOncePerDay() async throws {
        let uploader = RecordingUploader(config: RemoteSamplingConfig(sampleRate: 0.5, diagnosticSampleRate: 0.2))
        let (engine, container) = try makeEngine(uploader, configuration: Configuration())
        let now = day("2026-11-01T09:00:00Z")
        await engine.refreshSamplingConfig(now: now)
        #expect(await container.sampling() == DataContainer.StoredSampling(sampleRate: 0.5, diagnosticSampleRate: 0.2, fetchedAt: now))
        #expect(await engine.sampleRates() == (metric: 0.5, diagnostic: 0.2))
        await engine.refreshSamplingConfig(now: now + 3600)
        #expect(await container.sampling().fetchedAt == now)
    }
}

@Suite struct CloudKitEntitlementsTests {
    private let usable = CloudKitEntitlements(services: ["CloudKit"], containers: ["iCloud.com.example.a", "iCloud.com.example.b"])

    @Test func allowsTheDefaultAndAnyListedContainer() {
        #expect(usable.problem(opening: nil) == nil)
        #expect(usable.problem(opening: "iCloud.com.example.b") == nil)
        #expect(CloudKitEntitlements(services: ["*"], containers: ["iCloud.x"]).problem(opening: nil) == nil)
    }

    @Test func rejectsMissingEntitlements() {
        #expect(CloudKitEntitlements(services: [], containers: ["iCloud.x"]).problem(opening: nil) != nil)
        #expect(CloudKitEntitlements(services: ["CloudDocuments"], containers: ["iCloud.x"]).problem(opening: nil) != nil)
        #expect(CloudKitEntitlements(services: ["CloudKit"], containers: []).problem(opening: nil) != nil)
        #expect(usable.problem(opening: "iCloud.com.other") != nil)
    }

    @Test func readsAPropertyList() throws {
        let services = try #require(CloudKitEntitlements(propertyList: MachOFixture.plist(services: ["CloudKit"], containers: ["iCloud.x"])))
        #expect(services == CloudKitEntitlements(services: ["CloudKit"], containers: ["iCloud.x"]))

        let wildcard = try PropertyListSerialization.data(fromPropertyList: ["com.apple.developer.icloud-services": "*"], format: .xml, options: 0)
        #expect(CloudKitEntitlements(propertyList: wildcard)?.services == ["*"])
        #expect(CloudKitEntitlements(propertyList: Data("not a plist".utf8)) == nil)
    }

    /// Everything reaching `CKContainer` is gated here: with nothing granted it must not be called.
    @Test func uploaderThrowsWithoutTouchingCloudKit() {
        let cases: [(CloudKitEntitlements?, String?)] = [
            (nil, nil),
            (nil, "iCloud.com.example.a"),
            (CloudKitEntitlements(services: [], containers: []), nil),
            (usable, "iCloud.com.other"),
        ]
        for (entitlements, identifier) in cases {
            #expect(throws: ShipPulseKitError.self) {
                _ = try CloudKitUploader(configuration: Configuration(containerIdentifier: identifier), entitlements: entitlements)
            }
        }
    }

    /// This test process has no iCloud entitlement, which used to crash in CloudKit.
    @MainActor
    @Test func startThrowsInAProcessWithoutEntitlements() throws {
        do {
            try ShipPulseKit.start(Configuration(), isMetricKitAvailable: true)
            Issue.record("start() should have thrown")
        } catch {
            #expect(error.code == .iCloudContainerUnavailable)
        }
    }
}

@Suite struct MachOEntitlementsTests {
    private let plist = MachOFixture.plist(services: ["CloudKit"], containers: ["iCloud.x"])
    private let arm64 = MachOEntitlements.cpuARM64

    @Test func readsTheCodeSignatureOfAThinBinary() {
        #expect(MachOEntitlements.propertyList(in: MachOFixture.thin(signature: plist), cpuType: arm64) == plist)
    }

    /// arm64_32 watches run 32-bit Mach-O files.
    @Test func readsA32BitBinary() {
        let file = MachOFixture.thin(signature: plist, is64Bit: false)
        #expect(MachOEntitlements.propertyList(in: file, cpuType: MachOEntitlements.cpuARM64_32) == plist)
    }

    @Test func picksTheMatchingSliceOfAUniversalBinary() {
        let other = MachOFixture.plist(services: [], containers: [])
        for is64 in [false, true] {
            let file = MachOFixture.universal(
                [(MachOEntitlements.cpuX86_64, MachOFixture.thin(signature: other)), (arm64, MachOFixture.thin(signature: plist))],
                is64: is64
            )
            #expect(MachOEntitlements.propertyList(in: file, cpuType: arm64) == plist)
            #expect(MachOEntitlements.propertyList(in: file, cpuType: MachOEntitlements.cpuX86_64) == other)
            #expect(MachOEntitlements.propertyList(in: file, cpuType: MachOEntitlements.cpuARM64_32) == nil)
        }
    }

    /// Simulator signatures hold unrelated entitlements, so the section must win.
    @Test func prefersTheSimulatorSectionOverTheSignature() {
        let signed = MachOFixture.plist(services: [], containers: [])
        let file = MachOFixture.thin(signature: signed, section: plist)
        #expect(MachOEntitlements.propertyList(in: file, cpuType: arm64) == plist)
    }

    @Test func aBinaryWithoutEntitlementsHasNone() {
        #expect(MachOEntitlements.propertyList(in: MachOFixture.thin(), cpuType: arm64) == nil)
    }

    /// A malformed file must never trap, wherever it stops.
    @Test func truncatedFilesNeverTrap() {
        let file = MachOFixture.thin(signature: plist, section: plist)
        for length in 0..<file.count {
            _ = MachOEntitlements.propertyList(in: file.prefix(length), cpuType: arm64)
        }
        let universal = MachOFixture.universal([(arm64, file)], is64: true)
        for length in 0..<universal.count {
            _ = MachOEntitlements.propertyList(in: universal.prefix(length), cpuType: arm64)
        }
    }

    @Test func corruptFilesNeverTrap() {
        let file = MachOFixture.universal([(arm64, MachOFixture.thin(signature: plist, section: plist))], is64: false)
        for offset in stride(from: 0, to: file.count, by: 1) {
            for value: UInt8 in [0x00, 0x7F, 0xFF] {
                var corrupt = file
                corrupt[offset] = value
                _ = MachOEntitlements.propertyList(in: corrupt, cpuType: arm64)
            }
        }
        // Every 4-byte field at once pointing past the end, with no valid sum.
        var huge = MachOFixture.thin(signature: plist)
        for offset in stride(from: 16, to: huge.count - 3, by: 4) {
            huge.replaceSubrange(offset..<(offset + 4), with: [0xFF, 0xFF, 0xFF, 0xFF])
        }
        #expect(MachOEntitlements.propertyList(in: huge, cpuType: arm64) == nil)
    }

    #if os(macOS)
    /// Guards the fixture's format against what `codesign` really writes, and the path from
    /// file to entitlements: if it broke, every host app would silently lose its metrics.
    @Test func readsARealCodeSignature() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let binary = directory.appending(path: "signed"), entitlements = directory.appending(path: "e.plist")
        try FileManager.default.copyItem(at: URL(filePath: "/usr/bin/true"), to: binary)
        try plist.write(to: entitlements)

        let codesign = Process()
        codesign.executableURL = URL(filePath: "/usr/bin/codesign")
        codesign.arguments = ["-f", "-s", "-", "--entitlements", entitlements.path, binary.path]
        codesign.standardError = FileHandle.nullDevice
        try codesign.run()
        codesign.waitUntilExit()
        try #require(codesign.terminationStatus == 0)

        #expect(CloudKitEntitlements.of(executable: binary) == CloudKitEntitlements(services: ["CloudKit"], containers: ["iCloud.x"]))
    }

    @Test func aMissingExecutableHasNoEntitlements() {
        #expect(CloudKitEntitlements.of(executable: URL(filePath: "/no/such/executable")) == nil)
    }

    /// `ofRunningApp()` only supplies the URL; this proves it reaches the executable that runs.
    @Test func runningAppReadsItsOwnExecutable() throws {
        let url = try #require(Bundle.main.executableURL)
        #expect(FileManager.default.isExecutableFile(atPath: url.path))
        #expect(CloudKitEntitlements.ofRunningApp() == CloudKitEntitlements.of(executable: url))
    }
    #endif
}

/// Builds minimal Mach-O files, so the parser's tests need no signed binaries.
private enum MachOFixture {
    static func plist(services: [String], containers: [String]) -> Data {
        let values: [String: [String]] = [
            "com.apple.developer.icloud-services": services,
            "com.apple.developer.icloud-container-identifiers": containers,
        ]
        return (try? PropertyListSerialization.data(fromPropertyList: values, format: .xml, options: 0)) ?? Data()
    }

    static func thin(signature: Data? = nil, section: Data? = nil, is64Bit: Bool = true) -> Data {
        let headerSize = is64Bit ? 32 : 28
        let segmentSize = 72 + 80
        let commandsSize = (signature == nil ? 0 : 16) + (section == nil ? 0 : segmentSize)
        var payload = Data()
        var commands = Data()
        let dataStart = headerSize + commandsSize

        if let section {
            let offset = dataStart + payload.count
            payload.append(section)
            commands.append(le(UInt32(0x19)))
            commands.append(le(UInt32(segmentSize)))
            commands.append(fixedName("__TEXT"))
            commands.append(Data(count: 40)) // vmaddr ... initprot, before nsects.
            commands.append(le(UInt32(1)))
            commands.append(le(UInt32(0)))
            commands.append(fixedName("__entitlements"))
            commands.append(fixedName("__TEXT"))
            commands.append(Data(count: 8))
            commands.append(le64(UInt64(section.count)))
            commands.append(le(UInt32(offset)))
            commands.append(Data(count: 28))
        }
        if let signature {
            let blob = superblob(entitlements: signature)
            commands.append(le(UInt32(0x1D)))
            commands.append(le(UInt32(16)))
            commands.append(le(UInt32(dataStart + payload.count)))
            commands.append(le(UInt32(blob.count)))
            payload.append(blob)
        }

        var file = Data()
        file.append(le(is64Bit ? 0xFEED_FACF : 0xFEED_FACE))
        file.append(Data(count: 12))
        file.append(le(UInt32((signature == nil ? 0 : 1) + (section == nil ? 0 : 1))))
        file.append(le(UInt32(commandsSize)))
        file.append(Data(count: headerSize - file.count))
        file.append(commands)
        file.append(payload)
        return file
    }

    static func universal(_ slices: [(cpu: UInt32, file: Data)], is64: Bool) -> Data {
        let entrySize = is64 ? 32 : 20
        var offset = 8 + entrySize * slices.count
        var header = be(is64 ? 0xCAFE_BABF : 0xCAFE_BABE) + be(UInt32(slices.count))
        var body = Data()
        for slice in slices {
            header += be(slice.cpu) + be(UInt32(0))
            if is64 {
                header += be(UInt32(0)) + be(UInt32(offset)) + be(UInt32(0)) + be(UInt32(slice.file.count)) + be(UInt32(0)) + be(UInt32(0))
            } else {
                header += be(UInt32(offset)) + be(UInt32(slice.file.count)) + be(UInt32(0))
            }
            body.append(slice.file)
            offset += slice.file.count
        }
        return header + body
    }

    private static func superblob(entitlements: Data) -> Data {
        // A leading slot proves the entitlements slot is found by type, not position.
        let other = be(0xFADE_0C02) + be(UInt32(8))
        let headerSize = 12 + 8 * 2
        let blob = be(0xFADE_7171) + be(UInt32(entitlements.count + 8)) + entitlements
        var data = be(0xFADE_0CC0) + be(UInt32(headerSize + other.count + blob.count)) + be(UInt32(2))
        data += be(UInt32(0)) + be(UInt32(headerSize))
        data += be(UInt32(5)) + be(UInt32(headerSize + other.count))
        return data + other + blob
    }

    private static func fixedName(_ name: String) -> Data {
        var data = Data(name.utf8)
        data.append(Data(count: 16 - data.count))
        return data
    }

    private static func le(_ value: UInt32) -> Data { withUnsafeBytes(of: value.littleEndian) { Data($0) } }
    private static func le64(_ value: UInt64) -> Data { withUnsafeBytes(of: value.littleEndian) { Data($0) } }
    private static func be(_ value: UInt32) -> Data { withUnsafeBytes(of: value.bigEndian) { Data($0) } }
}

@Suite struct ShipPulseKitErrorTests {
    @Test func containerErrorCarriesDetails() {
        let error = ShipPulseKitError.iCloudContainerUnavailable(containerIdentifier: "iCloud.com.example", reason: "no entitlement")
        #expect(error.code == .iCloudContainerUnavailable)
        #expect(error.containerIdentifier == "iCloud.com.example")
        #expect(error.errorDescription?.contains("iCloud.com.example") == true)
        #expect(error.errorDescription?.contains("no entitlement") == true)
    }

    @Test func codesMatchInASwitchWithDefault() {
        let label: String = switch ShipPulseKitError.alreadyStarted.code {
        case .iCloudContainerUnavailable: "container"
        case .alreadyStarted: "started"
        default: "other"
        }
        #expect(label == "started")
        #expect(ShipPulseKitError.alreadyStarted.errorDescription == "ShipPulseKit is already running.")
    }
}

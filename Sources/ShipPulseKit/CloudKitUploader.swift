import CloudKit
import Foundation
import ShipPulseKitCore
import ShipPulseKitObjC

/// Sampling rates the ShipPulse app publishes for an app in its `SPConfig` record.
struct RemoteSamplingConfig: Sendable, Equatable {
    var sampleRate: Double
    var diagnosticSampleRate: Double
}

/// The transport that delivers queued records.
///
/// ``Engine`` talks only to this protocol, so tests and future transports don't need
/// CloudKit. ``CloudKitUploader`` is the production implementation.
protocol RecordUploading: Sendable {
    /// Whether uploads can be attempted right now.
    ///
    /// - Returns: `true` when the transport is reachable.
    func isAvailable() async -> Bool
    /// Uploads records.
    ///
    /// - Parameter records: The records to save.
    /// - Returns: Names of the records that were accepted. Only these leave the queue.
    /// - Throws: A transport error when the whole batch failed.
    func upload(_ records: [PendingRecord]) async throws -> [String]
    /// Reads the app's `SPConfig` record.
    ///
    /// - Parameter bundleID: The app's bundle identifier.
    /// - Returns: The published rates, or `nil` if the ShipPulse app hasn't written any.
    func fetchSamplingConfig(bundleID: String) async -> RemoteSamplingConfig?
}

/// Saves records to the public or private database of the app's CloudKit container.
struct CloudKitUploader: RecordUploading {
    private let container: CKContainer
    private let database: CKDatabase

    /// Opens the configured container.
    ///
    /// CloudKit raises an Objective-C exception when the app has no usable container. This
    /// catches it and throws instead, so the host app never crashes.
    ///
    /// - Parameter configuration: Supplies the container identifier and database.
    /// - Throws: ``ShipPulseKitError`` with code ``ShipPulseKitError/Code/iCloudContainerUnavailable``.
    init(configuration: Configuration) throws(ShipPulseKitError) {
        var resolved: CKContainer?
        let exception = SPKCatchException {
            resolved = configuration.containerIdentifier.map(CKContainer.init(identifier:)) ?? CKContainer.default()
        }
        guard exception == nil, let container = resolved else {
            throw .iCloudContainerUnavailable(
                containerIdentifier: configuration.containerIdentifier,
                reason: exception?.reason ?? "no iCloud container entitlement"
            )
        }
        self.container = container
        self.database = configuration.database == .public ? container.publicCloudDatabase : container.privateCloudDatabase
    }

    /// Whether the device is signed in to iCloud.
    ///
    /// Writing to a public database still requires an iCloud account, so records stay
    /// queued until there is one.
    func isAvailable() async -> Bool {
        (try? await container.accountStatus()) == .available
    }

    /// Saves records, overwriting any with the same name.
    ///
    /// A `serverRecordChanged` conflict counts as accepted: the record already exists.
    /// Batches over CloudKit's request limits are split, see ``uploadSplitting(_:send:)``.
    func upload(_ records: [PendingRecord]) async throws -> [String] {
        try await Self.uploadSplitting(records, send: save)
    }

    /// Sends records, halving any batch CloudKit rejects with `limitExceeded`.
    ///
    /// CloudKit limits a request to 400 records and 2 MB and asks callers to split and
    /// retry. Without this, one oversized oldest batch would block the queue for good. A
    /// single record that is still too large can never upload, so it is reported as
    /// accepted and leaves the queue.
    ///
    /// - Parameters:
    ///   - records: The records to send.
    ///   - send: Sends one batch and returns the accepted names.
    /// - Returns: Names of the records that were accepted or dropped as too large.
    /// - Throws: Any error other than `limitExceeded`.
    static func uploadSplitting(
        _ records: [PendingRecord],
        send: ([PendingRecord]) async throws -> [String]
    ) async throws -> [String] {
        guard !records.isEmpty else { return [] }
        do {
            return try await send(records)
        } catch let error as CKError where error.code == .limitExceeded {
            guard records.count > 1 else { return records.map(\.recordName) }
            let middle = records.count / 2
            let first = try await uploadSplitting(Array(records[..<middle]), send: send)
            let second = try await uploadSplitting(Array(records[middle...]), send: send)
            return first + second
        }
    }

    private func save(_ records: [PendingRecord]) async throws -> [String] {
        let ckRecords = records.map(Self.makeRecord)
        let (saveResults, _) = try await database.modifyRecords(saving: ckRecords, deleting: [], savePolicy: .allKeys, atomically: false)
        return saveResults.compactMap { id, result in
            switch result {
            case .success: return id.recordName
            case .failure(let error as CKError) where error.code == .serverRecordChanged: return id.recordName
            // A single record over CloudKit's size limit can never upload; drop it.
            case .failure(let error as CKError) where error.code == .limitExceeded: return id.recordName
            case .failure: return nil
            }
        }
    }

    func fetchSamplingConfig(bundleID: String) async -> RemoteSamplingConfig? {
        let id = CKRecord.ID(recordName: Schema.configRecordName(bundleID: bundleID))
        guard let record = try? await database.record(for: id) else { return nil }
        let rate = record[Schema.Field.sampleRate.rawValue] as? Double ?? 1
        let diagnosticRate = record[Schema.Field.diagnosticSampleRate.rawValue] as? Double ?? rate
        return RemoteSamplingConfig(sampleRate: rate, diagnosticSampleRate: diagnosticRate)
    }

    /// Converts a queued record to a `CKRecord`.
    ///
    /// - Parameter pending: The queued record.
    /// - Returns: A record with the same type, name and fields.
    static func makeRecord(_ pending: PendingRecord) -> CKRecord {
        let record = CKRecord(recordType: pending.kind.recordType, recordID: CKRecord.ID(recordName: pending.recordName))
        for (field, value) in pending.fields {
            let key = field.rawValue
            switch value {
            case .string(let v): record[key] = v as CKRecordValue
            case .int(let v): record[key] = v as CKRecordValue
            case .double(let v): record[key] = v as CKRecordValue
            case .date(let v): record[key] = v as CKRecordValue
            case .bytes(let v): record[key] = v as CKRecordValue
            }
        }
        return record
    }
}

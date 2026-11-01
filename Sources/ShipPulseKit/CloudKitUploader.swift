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
    /// - Throws: ``ShipPulseKitError/iCloudContainerUnavailable(containerIdentifier:reason:)``.
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
    func upload(_ records: [PendingRecord]) async throws -> [String] {
        guard !records.isEmpty else { return [] }
        let ckRecords = records.map(Self.makeRecord)
        let (saveResults, _) = try await database.modifyRecords(saving: ckRecords, deleting: [], savePolicy: .allKeys, atomically: false)
        return saveResults.compactMap { id, result in
            switch result {
            case .success: return id.recordName
            case .failure(let error as CKError) where error.code == .serverRecordChanged: return id.recordName
            case .failure: return nil
            }
        }
    }

    func fetchSamplingConfig(bundleID: String) async -> RemoteSamplingConfig? {
        let id = CKRecord.ID(recordName: Schema.configRecordName(bundleID: bundleID))
        guard let record = try? await database.record(for: id) else { return nil }
        let rate = record[Schema.Field.sampleRate] as? Double ?? 1
        let diagnosticRate = record[Schema.Field.diagnosticSampleRate] as? Double ?? rate
        return RemoteSamplingConfig(sampleRate: rate, diagnosticSampleRate: diagnosticRate)
    }

    /// Converts a queued record to a `CKRecord`.
    ///
    /// - Parameter pending: The queued record.
    /// - Returns: A record with the same type, name and fields.
    static func makeRecord(_ pending: PendingRecord) -> CKRecord {
        let record = CKRecord(recordType: pending.kind.recordType, recordID: CKRecord.ID(recordName: pending.recordName))
        for (key, value) in pending.fields {
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

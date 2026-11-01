import Foundation
import ShipPulseKitCore

/// A CloudKit record waiting to be uploaded. Kept as plain Codable data so it can sit in
/// the on-disk queue while the device is offline or signed out of iCloud.
struct PendingRecord: Codable, Sendable, Equatable {
    /// The CloudKit record type a pending record becomes.
    enum Kind: String, Codable, Sendable, CaseIterable {
        case metricSummary
        case diagnosticPayload
        case install
        case activeDay

        /// The CloudKit record type name.
        var recordType: String {
            switch self {
            case .metricSummary: Schema.RecordType.metricSummary
            case .diagnosticPayload: Schema.RecordType.diagnosticPayload
            case .install: Schema.RecordType.install
            case .activeDay: Schema.RecordType.activeDay
            }
        }
    }

    /// The record type.
    var kind: Kind
    /// A deterministic name, so a retried upload overwrites instead of duplicating.
    var recordName: String
    /// The record's fields, keyed by `Schema.Field` names.
    var fields: [String: FieldValue]
    /// When the record was queued. Drives upload order and expiry in ``UploadQueue``.
    var createdAt: Date
}

/// A CloudKit field value that can be stored as JSON.
enum FieldValue: Codable, Sendable, Equatable {
    case string(String)
    case int(Int64)
    case double(Double)
    case date(Date)
    case bytes(Data)
}

/// Common fields every record carries so the ShipPulse app can filter without decoding
/// payload bodies.
struct RecordContext: Sendable, Equatable {
    var bundleIdentifier: String
    var appVersion: String
    var buildVersion: String
    var osVersion: String
    var deviceModel: String

    /// The context as record fields.
    var fields: [String: FieldValue] {
        [
            "bundleID": .string(bundleIdentifier),
            "appVersion": .string(appVersion),
            "build": .string(buildVersion),
            "osVersion": .string(osVersion),
            "device": .string(deviceModel),
        ]
    }
}

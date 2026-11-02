import Foundation
import ShipPulseKitCore

/// A CloudKit record waiting to be uploaded. Kept as plain Codable data so it can sit in
/// the on-disk queue while the device is offline or signed out of iCloud.
struct PendingRecord: Codable, Sendable, Equatable {
    /// The CloudKit record type a pending record becomes.
    enum Kind: String, Codable, Sendable, CaseIterable {
        /// A daily MetricKit report, uploaded as `SPMetricSummary`.
        case metricSummary
        /// A MetricKit diagnostic (crash, hang and so on), uploaded as `SPDiagnosticPayload`.
        case diagnosticPayload
        /// The first launch of an install, uploaded as `SPInstall`.
        case install
        /// A UTC day the app was opened, uploaded as `SPActiveDay`.
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
    /// When the record was queued. Drives upload order and expiry in ``DataContainer``.
    var createdAt: Date
}

/// A CloudKit field value that can be stored as JSON.
enum FieldValue: Codable, Sendable, Equatable {
    /// A CloudKit `String` field.
    case string(String)
    /// A CloudKit `Int64` field, also used for booleans (`0` or `1`).
    case int(Int64)
    /// A CloudKit `Double` field.
    case double(Double)
    /// A CloudKit `Date/Time` field.
    case date(Date)
    /// A CloudKit `Bytes` field, used for compressed payloads.
    case bytes(Data)
}

/// Common fields every record carries so the ShipPulse app can filter without decoding
/// payload bodies.
struct RecordContext: Sendable, Equatable {
    /// The app's bundle identifier, so one container can hold several apps.
    var bundleIdentifier: String
    /// The marketing version (`CFBundleShortVersionString`).
    var appVersion: String
    /// The build number (`CFBundleVersion`).
    var buildVersion: String
    /// The OS version, such as `27.1.0`.
    var osVersion: String
    /// The hardware model identifier, such as `iPhone18,1`.
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

import Foundation

/// CloudKit record types and field names shared by ShipPulseKit, which writes them, and the
/// ShipPulse app, which reads them.
///
/// Changing a name here is a schema change for every integrating app. Keep it in sync with
/// `CloudKit/ShipPulseKit.ckdb`.
public enum Schema {
    /// CloudKit record type names.
    ///
    /// Pass ``rawValue`` to CloudKit.
    public enum RecordType: String, CaseIterable, Codable, Sendable {
        /// Per-device daily metrics: a ``DailyReport`` in `summary`, raw MetricKit JSON in
        /// `report`.
        case metricSummary = "SPMetricSummary"
        /// One MetricKit diagnostic (crash, hang, launch, CPU, disk, memory) with call stacks.
        case diagnosticPayload = "SPDiagnosticPayload"
        /// One per install, written on first launch.
        case install = "SPInstall"
        /// One per install per UTC day the app is opened.
        case activeDay = "SPActiveDay"
        /// Written by the ShipPulse app; read by ShipPulseKit for sampling rates.
        case config = "SPConfig"
    }

    /// CloudKit field names. `docs/CloudKitSchema.md` lists which record types use each.
    ///
    /// Pass ``rawValue`` to CloudKit. `CodingKeyRepresentable` keeps a `[Field: …]`
    /// dictionary encoded as a JSON object keyed by these names.
    public enum Field: String, CaseIterable, Codable, CodingKeyRepresentable, Sendable {
        /// The app's bundle identifier. On every record.
        case bundleID
        /// The app's marketing version. On every record.
        case appVersion
        /// The app's build number. On every record.
        case build
        /// The OS version, such as `27.1.0`. On every record.
        case osVersion
        /// The hardware model identifier, such as `iPhone18,1`. On every record.
        case device
        /// The install's random ID.
        case installID
        /// The UTC day, formatted `yyyy-MM-dd`, of an ``RecordType/activeDay`` record.
        case day
        /// Whole UTC days from the first launch to ``day``.
        case daysSinceInstall
        /// When the install first launched.
        case firstLaunch
        /// The start of the period a report covers.
        case timeBegin
        /// The end of the period a report covers.
        case timeEnd
        /// A zlib-compressed ``DailyReport`` as JSON.
        case summary
        /// The zlib-compressed raw MetricKit report JSON.
        case report
        /// The ``DailyReport/schemaVersion`` the summary was written with.
        case schemaVersion
        /// `1` for a TestFlight build, else `0`.
        case isTestFlight
        /// `1` when Low Power Mode was on, else `0`.
        case lowPowerMode
        /// The diagnostic kind, such as `crash` or `hang`.
        case kind
        /// The diagnostic's duration in milliseconds, when its kind has one.
        case durationMs
        /// The zlib-compressed, redacted diagnostic JSON.
        case payload
        /// How ``payload`` is encoded; currently `json+zlib`.
        case payloadEncoding
        /// The sampling rate a record was admitted at, or the rate `SPConfig` publishes.
        case sampleRate
        /// The diagnostic sampling rate `SPConfig` publishes.
        case diagnosticSampleRate
        /// A crash's termination category.
        case terminationCategory
        /// A crash's signal number.
        case signal
        /// A crash's Mach exception type.
        case exceptionType
        /// Bytes a disk-write exception wrote, in megabytes.
        case writesMB
    }

    /// The custom security role defined in `CloudKit/ShipPulseKit.ckdb`.
    ///
    /// Assign it to your own iCloud user in CloudKit Console so ShipPulse can write
    /// `SPConfig` and prune old records.
    public static let adminRole = "ShipPulseAdmin"

    /// The state-reporting domain ShipPulseKit uses for screens.
    public static let screenDomain = "shippulse.screen"

    /// The `SPConfig` record name for an app.
    ///
    /// - Parameter bundleID: The app's bundle identifier.
    /// - Returns: One record name per bundle identifier.
    public static func configRecordName(bundleID: String) -> String {
        "config-\(bundleID)"
    }
}

import Foundation

/// CloudKit record types and field names shared by ShipPulseKit, which writes them, and the
/// ShipPulse app, which reads them.
///
/// Changing a name here is a schema change for every integrating app. Keep it in sync with
/// `CloudKit/ShipPulseKit.ckdb`.
public enum Schema {
    /// CloudKit record type names.
    public enum RecordType {
        /// Per-device daily metrics: a ``DailyReport`` in `summary`, raw MetricKit JSON in
        /// `report`.
        public static let metricSummary = "SPMetricSummary"
        /// One MetricKit diagnostic (crash, hang, launch, CPU, disk, memory) with call stacks.
        public static let diagnosticPayload = "SPDiagnosticPayload"
        /// One per install, written on first launch.
        public static let install = "SPInstall"
        /// One per install per UTC day the app is opened.
        public static let activeDay = "SPActiveDay"
        /// Written by the ShipPulse app; read by ShipPulseKit for sampling rates.
        public static let config = "SPConfig"
    }

    /// CloudKit field names. `docs/CloudKitSchema.md` lists which record types use each.
    public enum Field {
        public static let bundleID = "bundleID"
        public static let appVersion = "appVersion"
        public static let build = "build"
        public static let osVersion = "osVersion"
        public static let device = "device"
        public static let installID = "installID"
        public static let day = "day"
        public static let daysSinceInstall = "daysSinceInstall"
        public static let firstLaunch = "firstLaunch"
        public static let timeBegin = "timeBegin"
        public static let timeEnd = "timeEnd"
        public static let summary = "summary"
        public static let report = "report"
        public static let schemaVersion = "schemaVersion"
        public static let isTestFlight = "isTestFlight"
        public static let lowPowerMode = "lowPowerMode"
        public static let kind = "kind"
        public static let durationMs = "durationMs"
        public static let payload = "payload"
        public static let payloadEncoding = "payloadEncoding"
        public static let sampleRate = "sampleRate"
        public static let diagnosticSampleRate = "diagnosticSampleRate"
        public static let terminationCategory = "terminationCategory"
        public static let signal = "signal"
        public static let exceptionType = "exceptionType"
        public static let writesMB = "writesMB"
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

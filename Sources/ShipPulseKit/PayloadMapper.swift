import Foundation
import ShipPulseKitCore

/// Builds ``PendingRecord`` values from mapped reports.
///
/// It is free of MetricKit types, so it can be tested on any platform.
enum PayloadMapper {
    /// The record for one device's daily metrics.
    ///
    /// It holds the flattened `DailyReport` that ShipPulse aggregates, plus the raw MetricKit
    /// report JSON, so metrics added in later OS releases are kept too. Both are
    /// zlib-compressed.
    ///
    /// - Parameters:
    ///   - report: The flattened report.
    ///   - rawJSON: MetricKit's own encoding of the report, if it encoded.
    ///   - begin: Start of the report's time range.
    ///   - end: End of the report's time range.
    ///   - installID: The reporting install.
    ///   - context: Device and app fields.
    ///   - now: The queueing time.
    /// - Returns: An `SPMetricSummary` record named per install and time range.
    static func summaryRecord(
        report: DailyReport,
        rawJSON: Data?,
        begin: Date,
        end: Date,
        installID: String,
        context: RecordContext,
        now: Date
    ) -> PendingRecord {
        var fields = context.fields
        fields[.installID] = .string(installID)
        fields[.timeBegin] = .date(begin)
        fields[.timeEnd] = .date(end)
        fields[.schemaVersion] = .int(Int64(report.schemaVersion))
        fields[.isTestFlight] = .int(report.isTestFlight ? 1 : 0)
        fields[.lowPowerMode] = .int(report.isLowPowerModeEnabled ? 1 : 0)
        fields[.summary] = .bytes(compressed((try? JSONEncoder().encode(report)) ?? Data()))
        if let rawJSON { fields[.report] = .bytes(compressed(rawJSON)) }
        // One record per install and window, so a redelivered report overwrites.
        let name = "summary-\(installID)-\(Int64(begin.timeIntervalSince1970))"
        return PendingRecord(kind: .metricSummary, recordName: name, fields: fields, createdAt: now)
    }

    /// The record for one diagnostic (crash, hang, launch, CPU, disk or memory).
    ///
    /// - Parameters:
    ///   - json: The diagnostic's JSON, including call stacks.
    ///   - kind: The diagnostic kind, for example `"crash"`.
    ///   - durationMs: The hang or launch duration, when the kind has one.
    ///   - extraFields: Kind-specific queryable fields.
    ///   - isTestFlight: Whether the report came from a TestFlight build.
    ///   - begin: Start of the report's time range.
    ///   - end: End of the report's time range.
    ///   - context: Device and app fields.
    ///   - now: The queueing time.
    /// - Returns: An `SPDiagnosticPayload` record named after a hash of its content, so the
    ///   same diagnostic is stored once.
    static func diagnosticRecord(
        json: Data,
        kind: String,
        durationMs: Double?,
        extraFields: [Schema.Field: FieldValue],
        isTestFlight: Bool,
        begin: Date,
        end: Date,
        context: RecordContext,
        now: Date
    ) -> PendingRecord {
        var fields = context.fields.merging(extraFields) { _, new in new }
        fields[.kind] = .string(kind)
        if let durationMs { fields[.durationMs] = .double(durationMs) }
        fields[.isTestFlight] = .int(isTestFlight ? 1 : 0)
        fields[.timeBegin] = .date(begin)
        fields[.timeEnd] = .date(end)
        fields[.payload] = .bytes(compressed(json))
        fields[.payloadEncoding] = .string("json+zlib")
        let hash = String(Sampling.stableHash(json), radix: 16)
        let name = "diagnostic-\(context.bundleIdentifier)-\(context.buildVersion)-\(kind)-\(hash)"
        return PendingRecord(kind: .diagnosticPayload, recordName: name, fields: fields, createdAt: now)
    }

    /// Diagnostic JSON with free-form runtime strings removed, in a stable key order.
    ///
    /// Objective-C exception `composedMessage` and `arguments` can carry user data, and the
    /// public database is world-readable, so both are dropped wherever they appear. Sorted
    /// keys make the content hash in the record name the same in every process, so a
    /// redelivered diagnostic overwrites instead of duplicating.
    ///
    /// - Parameter json: MetricKit's encoding of a `DiagnosticReport`.
    /// - Returns: The redacted JSON, or `nil` if it isn't a JSON object.
    static func redactedDiagnosticJSON(_ json: Data) -> Data? {
        guard let object = try? JSONSerialization.jsonObject(with: json) else { return nil }
        let redacted = removingKeys(redactedKeys, from: object)
        return try? JSONSerialization.data(withJSONObject: redacted, options: [.sortedKeys])
    }

    static let redactedKeys: Set<String> = ["composedMessage", "arguments"]

    private static func removingKeys(_ keys: Set<String>, from value: Any) -> Any {
        if let dictionary = value as? [String: Any] {
            var result: [String: Any] = [:]
            for (key, child) in dictionary where !keys.contains(key) {
                result[key] = removingKeys(keys, from: child)
            }
            return result
        }
        if let array = value as? [Any] {
            return array.map { removingKeys(keys, from: $0) }
        }
        return value
    }

    /// zlib-compresses data, or returns it unchanged if compression fails.
    static func compressed(_ data: Data) -> Data {
        (try? (data as NSData).compressed(using: .zlib) as Data) ?? data
    }
}

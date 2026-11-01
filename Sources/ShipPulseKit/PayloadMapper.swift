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
        fields[Schema.Field.installID] = .string(installID)
        fields[Schema.Field.timeBegin] = .date(begin)
        fields[Schema.Field.timeEnd] = .date(end)
        fields[Schema.Field.schemaVersion] = .int(Int64(report.schemaVersion))
        fields[Schema.Field.isTestFlight] = .int(report.isTestFlight ? 1 : 0)
        fields[Schema.Field.lowPowerMode] = .int(report.lowPowerMode ? 1 : 0)
        fields[Schema.Field.summary] = .bytes(compressed((try? JSONEncoder().encode(report)) ?? Data()))
        if let rawJSON { fields[Schema.Field.report] = .bytes(compressed(rawJSON)) }
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
        extraFields: [String: FieldValue],
        isTestFlight: Bool,
        begin: Date,
        end: Date,
        context: RecordContext,
        now: Date
    ) -> PendingRecord {
        var fields = context.fields.merging(extraFields) { _, new in new }
        fields[Schema.Field.kind] = .string(kind)
        if let durationMs { fields[Schema.Field.durationMs] = .double(durationMs) }
        fields[Schema.Field.isTestFlight] = .int(isTestFlight ? 1 : 0)
        fields[Schema.Field.timeBegin] = .date(begin)
        fields[Schema.Field.timeEnd] = .date(end)
        fields[Schema.Field.payload] = .bytes(compressed(json))
        fields[Schema.Field.payloadEncoding] = .string("json+zlib")
        let hash = String(Sampling.stableHash(json), radix: 16)
        let name = "diagnostic-\(context.bundleIdentifier)-\(context.buildVersion)-\(kind)-\(hash)"
        return PendingRecord(kind: .diagnosticPayload, recordName: name, fields: fields, createdAt: now)
    }

    /// zlib-compresses data, or returns it unchanged if compression fails.
    static func compressed(_ data: Data) -> Data {
        (try? (data as NSData).compressed(using: .zlib) as Data) ?? data
    }
}

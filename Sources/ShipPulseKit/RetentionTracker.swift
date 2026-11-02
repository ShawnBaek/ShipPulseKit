import Foundation

/// Produces the anonymous signals ShipPulse uses for retention.
///
/// It emits one `SPInstall` record per install and one `SPActiveDay` record per UTC
/// calendar day the app is opened.
///
/// It is pure: the stored ``State`` and the time go in, records and the new state come out.
/// ``DataContainer`` loads and saves the state. The install ID is a random UUID kept per
/// app, never shared across apps, and reset when the app is deleted. Retention therefore
/// counts devices, and a reinstall counts as a new device.
enum RetentionTracker {
    /// What the tracker remembers between launches.
    struct State: Sendable, Equatable {
        /// The install's random ID.
        var installID: String
        /// The first launch, or `nil` before it is recorded.
        var firstLaunch: Date?
        /// The last UTC day recorded, formatted `yyyy-MM-dd`.
        var lastActiveDay: String?
    }

    private static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        return calendar
    }()

    /// The records to upload for an app launch or foreground.
    ///
    /// - Parameters:
    ///   - state: The stored state.
    ///   - now: The time of the launch or foreground.
    ///   - context: Device and app fields to stamp on each record.
    /// - Returns: An install record on first launch, plus an active-day record unless today
    ///   was already recorded, and the state to store.
    static func records(for state: State, at now: Date, context: RecordContext) -> ([PendingRecord], State) {
        var state = state
        var records: [PendingRecord] = []
        let installID = state.installID
        let firstLaunch: Date
        if let first = state.firstLaunch {
            firstLaunch = first
        } else {
            firstLaunch = now
            state.firstLaunch = now
            var fields = context.fields
            fields[.installID] = .string(installID)
            fields[.firstLaunch] = .date(firstLaunch)
            records.append(PendingRecord(kind: .install, recordName: "install-\(installID)", fields: fields, createdAt: now))
        }

        let day = dayString(now)
        guard state.lastActiveDay != day else { return (records, state) }
        state.lastActiveDay = day
        var fields = context.fields
        fields[.installID] = .string(installID)
        fields[.day] = .string(day)
        fields[.daysSinceInstall] = .int(Int64(daysBetween(firstLaunch, now)))
        records.append(PendingRecord(kind: .activeDay, recordName: "active-\(installID)-\(day)", fields: fields, createdAt: now))
        return (records, state)
    }

    /// The UTC day of a date, formatted `yyyy-MM-dd`.
    static func dayString(_ date: Date) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    /// Whole UTC calendar days from `start` to `end`.
    static func daysBetween(_ start: Date, _ end: Date) -> Int {
        calendar.dateComponents([.day], from: calendar.startOfDay(for: start), to: calendar.startOfDay(for: end)).day ?? 0
    }
}

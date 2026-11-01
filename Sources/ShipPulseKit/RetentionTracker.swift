import Foundation

/// Produces the anonymous signals ShipPulse uses for retention.
///
/// It emits one `SPInstall` record per install and one `SPActiveDay` record per UTC
/// calendar day the app is opened.
///
/// The install ID is a random UUID kept in UserDefaults, so it is per app, never shared
/// across apps, and reset when the app is deleted. Retention therefore counts devices,
/// and a reinstall counts as a new device.
struct RetentionTracker {
    private let defaults: UserDefaults
    private let calendar: Calendar

    private enum Key {
        static let installID = "ShipPulseKit.installID"
        static let firstLaunch = "ShipPulseKit.firstLaunch"
        static let lastActiveDay = "ShipPulseKit.lastActiveDay"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        self.calendar = calendar
    }

    /// The install's random ID, created on first use.
    ///
    /// It also drives per-install sampling, so it exists even when retention tracking is
    /// off.
    ///
    /// - Returns: A UUID string, stable until the app is deleted.
    func installID() -> String {
        if let existing = defaults.string(forKey: Key.installID) { return existing }
        let id = UUID().uuidString
        defaults.set(id, forKey: Key.installID)
        return id
    }

    /// The records to upload for an app launch or foreground.
    ///
    /// - Parameters:
    ///   - now: The time of the launch or foreground.
    ///   - context: Device and app fields to stamp on each record.
    /// - Returns: An install record on first launch, plus an active-day record unless today
    ///   was already recorded. Empty otherwise.
    func records(at now: Date, context: RecordContext) -> [PendingRecord] {
        var records: [PendingRecord] = []
        let installID = installID()
        let firstLaunch: Date
        if let first = defaults.object(forKey: Key.firstLaunch) as? Date {
            firstLaunch = first
        } else {
            firstLaunch = now
            defaults.set(firstLaunch, forKey: Key.firstLaunch)
            var fields = context.fields
            fields["installID"] = .string(installID)
            fields["firstLaunch"] = .date(firstLaunch)
            records.append(PendingRecord(kind: .install, recordName: "install-\(installID)", fields: fields, createdAt: now))
        }

        let day = dayString(now)
        guard defaults.string(forKey: Key.lastActiveDay) != day else { return records }
        defaults.set(day, forKey: Key.lastActiveDay)
        var fields = context.fields
        fields["installID"] = .string(installID)
        fields["day"] = .string(day)
        fields["daysSinceInstall"] = .int(Int64(daysBetween(firstLaunch, now)))
        records.append(PendingRecord(kind: .activeDay, recordName: "active-\(installID)-\(day)", fields: fields, createdAt: now))
        return records
    }

    /// The UTC day of a date, formatted `yyyy-MM-dd`.
    func dayString(_ date: Date) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    /// Whole UTC calendar days from `start` to `end`.
    func daysBetween(_ start: Date, _ end: Date) -> Int {
        calendar.dateComponents([.day], from: calendar.startOfDay(for: start), to: calendar.startOfDay(for: end)).day ?? 0
    }
}

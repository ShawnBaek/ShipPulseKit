import Foundation

/// The single owner of everything ShipPulseKit keeps on the device.
///
/// That is the pending records, one JSON file each, and a few UserDefaults keys: the
/// install ID, the retention state and the last sampling rates the ShipPulse app published.
/// No other type touches the file system or UserDefaults, so every read and write is
/// serialized by this actor.
///
/// Pending records work as an outbox. Every record is written here before any upload is
/// attempted, and removed only after CloudKit accepts it, so nothing is lost while the
/// device is offline or signed out of iCloud. Each file is named after
/// ``PendingRecord/recordName``, so a record enqueued twice overwrites itself.
///
/// Plain files and UserDefaults are deliberate: a Core Data or SwiftData store could clash
/// with the host app's own and would need migrations.
actor DataContainer {
    private let directory: URL
    private let maxAge: TimeInterval
    private let maxCount: Int
    private let defaults: UserDefaults
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    /// UserDefaults keys. The names are shipped in 0.1.0, so they never change.
    private enum Key {
        static let installID = "ShipPulseKit.installID"
        static let firstLaunch = "ShipPulseKit.firstLaunch"
        static let lastActiveDay = "ShipPulseKit.lastActiveDay"
        static let sampleRate = "ShipPulseKit.sampleRate"
        static let diagnosticSampleRate = "ShipPulseKit.diagnosticSampleRate"
        static let configFetchedAt = "ShipPulseKit.configFetchedAt"
    }

    /// Creates a container.
    ///
    /// - Parameters:
    ///   - directory: Where pending records are stored. Production uses
    ///     ``defaultDirectory()``; tests pass a temporary one.
    ///   - maxAge: Pending records older than this are dropped.
    ///   - maxCount: The most pending records kept; the oldest go first.
    ///   - defaultsSuite: The UserDefaults suite for the install ID, retention state and
    ///     sampling rates. `nil` is `UserDefaults.standard`; tests pass a unique suite.
    ///     `UserDefaults` isn't `Sendable`, so the container creates its own instance
    ///     rather than sharing one with its caller.
    init(directory: URL = DataContainer.defaultDirectory(), maxAge: TimeInterval, maxCount: Int, defaultsSuite: String? = nil) {
        self.directory = directory
        self.maxAge = maxAge
        self.maxCount = maxCount
        self.defaults = defaultsSuite.flatMap(UserDefaults.init(suiteName:)) ?? .standard
    }

    /// `Application Support/ShipPulseKit/Queue`, the directory 0.1.0 already writes to, so
    /// records queued before an update still upload.
    static func defaultDirectory() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appending(path: "ShipPulseKit/Queue", directoryHint: .isDirectory)
    }

    // MARK: Install and retention state

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

    /// Reads the retention state, applies `update` and saves the state it returns, with no
    /// other access in between.
    ///
    /// A launch and a foreground can record activity at the same moment; doing the read and
    /// the write in one actor call keeps them from both seeing the old day.
    ///
    /// - Parameter update: Takes the stored state and returns a result and the new state.
    /// - Returns: The result of `update`.
    func updateRetention<Result: Sendable>(_ update: @Sendable (RetentionTracker.State) -> (Result, RetentionTracker.State)) -> Result {
        let stored = RetentionTracker.State(
            installID: installID(),
            firstLaunch: defaults.object(forKey: Key.firstLaunch) as? Date,
            lastActiveDay: defaults.string(forKey: Key.lastActiveDay)
        )
        let (result, state) = update(stored)
        if state.firstLaunch != stored.firstLaunch { defaults.set(state.firstLaunch, forKey: Key.firstLaunch) }
        if state.lastActiveDay != stored.lastActiveDay { defaults.set(state.lastActiveDay, forKey: Key.lastActiveDay) }
        return result
    }

    // MARK: Sampling

    /// The rates last read from the app's `SPConfig` record.
    struct StoredSampling: Sendable, Equatable {
        /// The sampling rate, or `nil` before the first fetch.
        var sampleRate: Double?
        /// The diagnostic sampling rate, or `nil` before the first fetch.
        var diagnosticSampleRate: Double?
        /// When `SPConfig` was last read, or `nil` if never.
        var fetchedAt: Date?
    }

    /// The stored sampling rates.
    func sampling() -> StoredSampling {
        StoredSampling(
            sampleRate: defaults.object(forKey: Key.sampleRate) as? Double,
            diagnosticSampleRate: defaults.object(forKey: Key.diagnosticSampleRate) as? Double,
            fetchedAt: defaults.object(forKey: Key.configFetchedAt) as? Date
        )
    }

    /// Saves rates read from `SPConfig`.
    ///
    /// - Parameters:
    ///   - config: The published rates.
    ///   - fetchedAt: When they were read.
    func saveSampling(_ config: RemoteSamplingConfig, fetchedAt: Date) {
        defaults.set(config.sampleRate, forKey: Key.sampleRate)
        defaults.set(config.diagnosticSampleRate, forKey: Key.diagnosticSampleRate)
        defaults.set(fetchedAt, forKey: Key.configFetchedAt)
    }

    // MARK: Pending records

    /// Writes records to disk, then prunes.
    ///
    /// - Parameter records: The records to keep until upload.
    /// - Throws: A file-system error if the directory or a file can't be written.
    func enqueue(_ records: [PendingRecord]) throws {
        guard !records.isEmpty else { return }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for record in records {
            let data = try encoder.encode(record)
            try data.write(to: fileURL(for: record.recordName), options: .atomic)
        }
        try prune(now: Date())
    }

    /// The oldest pending records, so a long offline period uploads in the order events
    /// happened.
    ///
    /// - Parameter limit: The most records to return.
    /// - Returns: Up to `limit` records, oldest first.
    /// - Throws: A file-system error if the directory can't be read.
    func pending(limit: Int) throws -> [PendingRecord] {
        try load().sorted { $0.createdAt < $1.createdAt }.prefix(limit).map { $0 }
    }

    /// Deletes records CloudKit accepted.
    ///
    /// - Parameter recordNames: Names of the records to delete.
    func remove(_ recordNames: [String]) {
        for name in recordNames {
            try? FileManager.default.removeItem(at: fileURL(for: name))
        }
    }

    /// The number of records waiting for upload.
    ///
    /// - Returns: How many pending records are on disk.
    /// - Throws: A file-system error if the directory can't be read.
    func pendingCount() throws -> Int {
        try load().count
    }

    /// Drops records older than the maximum age, then the oldest beyond the maximum count.
    ///
    /// - Parameter now: The current date.
    func prune(now: Date) throws {
        let all = try load().sorted { $0.createdAt < $1.createdAt }
        let expired = all.filter { now.timeIntervalSince($0.createdAt) > maxAge }
        let fresh = all.filter { now.timeIntervalSince($0.createdAt) <= maxAge }
        let overflow = fresh.count > maxCount ? Array(fresh.prefix(fresh.count - maxCount)) : []
        remove((expired + overflow).map(\.recordName))
    }

    private func load() throws -> [PendingRecord] {
        guard FileManager.default.fileExists(atPath: directory.path()) else { return [] }
        let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        return files.filter { $0.pathExtension == "json" }.compactMap { url in
            guard let data = try? Data(contentsOf: url) else { return nil }
            return try? decoder.decode(PendingRecord.self, from: data)
        }
    }

    private func fileURL(for recordName: String) -> URL {
        let safe = recordName.replacingOccurrences(of: "/", with: "_")
        return directory.appending(path: safe + ".json")
    }
}

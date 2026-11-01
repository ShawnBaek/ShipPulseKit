import Foundation

/// The on-disk repository of records waiting for upload, used as an outbox.
///
/// Every record is written here before any upload is attempted, and removed only after
/// CloudKit accepts it, so nothing is lost while the device is offline or signed out of
/// iCloud. Each record is one JSON file named after ``PendingRecord/recordName``, so a
/// record enqueued twice overwrites itself.
actor UploadQueue {
    private let directory: URL
    private let maxAge: TimeInterval
    private let maxCount: Int
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(directory: URL, maxAge: TimeInterval, maxCount: Int) {
        self.directory = directory
        self.maxAge = maxAge
        self.maxCount = maxCount
    }

    static func defaultDirectory() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appending(path: "ShipPulseKit/Queue", directoryHint: .isDirectory)
    }

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

    /// The oldest queued records, so a long offline period uploads in the order events
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

    func count() throws -> Int {
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

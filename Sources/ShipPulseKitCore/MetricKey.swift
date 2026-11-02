import Foundation

/// The key of one stored value in ``MetricSummary``.
///
/// Each key's ``rawValue`` is the string written to CloudKit, unchanged since 0.1.0, so
/// records from every SDK version decode the same way. A key written by a newer SDK decodes
/// as ``unknown(_:)`` instead of failing.
///
/// Units are normalized: histograms in milliseconds, totals in seconds, sizes in megabytes.
/// Group aggregation sums cumulative values and takes percentiles over per-device snapshots
/// (``isDistribution``).
public enum MetricKey: Hashable, Sendable {
    // MARK: Launch

    /// Time from launch to the first frame, as a histogram in milliseconds.
    ///
    /// From MetricKit's `timeToFirstDraw`.
    case timeToFirstDraw
    /// Time to first draw for launches the system prewarmed, as a histogram in milliseconds.
    ///
    /// From MetricKit's `optimizedTimeToFirstDraw`.
    case optimizedTimeToFirstDraw
    /// Time until the app is usable, including tracked launch tasks, as a histogram in
    /// milliseconds.
    ///
    /// From MetricKit's `extendedLaunch`.
    case extendedLaunch
    /// Time to resume from the background, as a histogram in milliseconds.
    ///
    /// From MetricKit's `applicationResumeTime`.
    case applicationResumeTime

    // MARK: Responsiveness and animation

    /// Main-thread hangs, as a histogram of durations in milliseconds.
    ///
    /// From MetricKit's `hangTime`.
    case hangTime
    /// Hitch time divided by animation time, a per-device ratio.
    ///
    /// From MetricKit's `hitchTime` ratio.
    case hitchRatio
    /// Total hitch time, in seconds.
    ///
    /// From MetricKit's `hitchTime` total hitch time.
    case hitchSeconds
    /// Total time spent animating or scrolling, in seconds.
    ///
    /// From MetricKit's `hitchTime` total animation time.
    case animationSeconds

    // MARK: Run time

    /// Time in the foreground, in seconds.
    ///
    /// From MetricKit's `totalForegroundTime`.
    case foregroundSeconds
    /// Time running in the background, in seconds.
    ///
    /// From MetricKit's `totalBackgroundTime`.
    case backgroundSeconds
    /// Time playing audio in the background, in seconds.
    ///
    /// From MetricKit's `totalBackgroundAudioTime`.
    case backgroundAudioSeconds
    /// Time using location in the background, in seconds.
    ///
    /// From MetricKit's `totalBackgroundLocationTime`.
    case backgroundLocationSeconds

    // MARK: CPU and GPU

    /// CPU time, in seconds.
    ///
    /// From MetricKit's `cpuTime`.
    case cpuSeconds
    /// Instructions retired, as a count.
    ///
    /// From MetricKit's `cpuInstructionsCount`.
    case cpuInstructions
    /// GPU time, in seconds.
    ///
    /// From MetricKit's `gpuTime`.
    case gpuSeconds

    // MARK: Memory

    /// Peak memory, in megabytes. A per-device snapshot.
    ///
    /// From MetricKit's `peakMemory`.
    case peakMemoryMB
    /// Average memory while suspended, in megabytes. A per-device snapshot.
    ///
    /// From MetricKit's `suspendedMemory`.
    case suspendedMemoryMB

    // MARK: Network

    /// Data uploaded over Wi-Fi, in megabytes.
    ///
    /// From MetricKit's `totalWiFiUpload`.
    case wifiUploadMB
    /// Data downloaded over Wi-Fi, in megabytes.
    ///
    /// From MetricKit's `totalWiFiDownload`.
    case wifiDownloadMB
    /// Data uploaded over cellular, in megabytes.
    ///
    /// From MetricKit's `totalCellularUpload`.
    case cellularUploadMB
    /// Data downloaded over cellular, in megabytes.
    ///
    /// From MetricKit's `totalCellularDownload`.
    case cellularDownloadMB
    /// Time spent at each cellular signal strength, as a histogram over signal bars.
    ///
    /// From MetricKit's `cellularConditionTime`.
    case cellularConditionBars

    // MARK: Disk

    /// Logical disk writes, in megabytes.
    ///
    /// From MetricKit's `logicalDiskWrites`.
    case logicalDiskWritesMB
    /// Files in the app bundle, as a count.
    ///
    /// From MetricKit's `totalFileCount` binary file count.
    case binaryFileCount
    /// Files in the app's data container, as a count.
    ///
    /// From MetricKit's `totalFileCount` data file count.
    case dataFileCount
    /// Size of the app bundle, in megabytes. A per-device snapshot.
    ///
    /// From MetricKit's `totalFileSize` binary file size.
    case binaryFileSizeMB
    /// Size of the app's data container, in megabytes. A per-device snapshot.
    ///
    /// From MetricKit's `totalFileSize` data file size.
    case dataFileSizeMB
    /// Size of the app's caches folder, in megabytes. A per-device snapshot.
    ///
    /// From MetricKit's `totalFileSize` cache folder size.
    case cacheFolderSizeMB
    /// Space shared with clones of other files, in megabytes. A per-device snapshot.
    ///
    /// From MetricKit's `totalFileSize` clone size.
    case cloneSizeMB
    /// The device's disk capacity, in megabytes. A per-device snapshot.
    ///
    /// From MetricKit's `totalDiskSpaceCapacity` capacity.
    case diskCapacityMB
    /// Disk space used on the device, in megabytes. A per-device snapshot.
    ///
    /// From MetricKit's `totalDiskSpaceCapacity` space used.
    case diskUsedMB

    // MARK: Display and graphics

    /// Average pixel luminance, in MetricKit's luminance unit. A per-device snapshot.
    ///
    /// From MetricKit's `pixelLuminance`.
    case pixelLuminance
    /// Frames per second for one Metal layer. A per-device snapshot.
    ///
    /// From MetricKit's `metalFrameRate` frames per second.
    ///
    /// - Parameter layer: The `CAMetalLayer` name MetricKit reports.
    case metalFPS(layer: String)
    /// Frames drawn for one Metal layer, as a count.
    ///
    /// From MetricKit's `metalFrameRate` frame count.
    ///
    /// - Parameter layer: The `CAMetalLayer` name MetricKit reports.
    case metalFrames(layer: String)
    /// Time one Metal layer spent drawing, in seconds.
    ///
    /// From MetricKit's `metalFrameRate` active drawing duration.
    ///
    /// - Parameter layer: The `CAMetalLayer` name MetricKit reports.
    case metalActiveSeconds(layer: String)

    // MARK: Breakdowns

    /// Foreground terminations for one reason, as a count.
    ///
    /// From MetricKit's `foregroundTermination`.
    ///
    /// - Parameter reason: Why the app was terminated.
    case foregroundTermination(ForegroundTerminationReason)
    /// Background terminations for one reason, as a count.
    ///
    /// From MetricKit's `backgroundTermination`.
    ///
    /// - Parameter reason: Why the app was terminated.
    case backgroundTermination(BackgroundTerminationReason)
    /// Time using location at one accuracy, in seconds.
    ///
    /// From MetricKit's `locationActivityTime`.
    ///
    /// - Parameter accuracy: The requested location accuracy.
    case locationSeconds(LocationAccuracy)

    // MARK: Forward compatibility

    /// A key this version doesn't know, written by a newer SDK.
    ///
    /// The ShipPulse app keeps and shows it rather than dropping the value. This version
    /// never writes it.
    ///
    /// - Parameter rawValue: The stored key.
    case unknown(String)

    /// Every key this version writes that doesn't depend on a Metal layer name.
    ///
    /// `CaseIterable` can't be synthesized for cases with associated values, so this lists
    /// them, including every termination reason and location accuracy.
    public static var allKnown: [MetricKey] {
        fixedKeys
            + ForegroundTerminationReason.allCases.map(MetricKey.foregroundTermination)
            + BackgroundTerminationReason.allCases.map(MetricKey.backgroundTermination)
            + LocationAccuracy.allCases.map(MetricKey.locationSeconds)
    }

    private static let fixedKeys: [MetricKey] = [
        .timeToFirstDraw, .optimizedTimeToFirstDraw, .extendedLaunch, .applicationResumeTime,
        .hangTime, .hitchRatio, .hitchSeconds, .animationSeconds,
        .foregroundSeconds, .backgroundSeconds, .backgroundAudioSeconds, .backgroundLocationSeconds,
        .cpuSeconds, .cpuInstructions, .gpuSeconds,
        .peakMemoryMB, .suspendedMemoryMB,
        .wifiUploadMB, .wifiDownloadMB, .cellularUploadMB, .cellularDownloadMB, .cellularConditionBars,
        .logicalDiskWritesMB, .binaryFileCount, .dataFileCount, .binaryFileSizeMB, .dataFileSizeMB,
        .cacheFolderSizeMB, .cloneSizeMB, .diskCapacityMB, .diskUsedMB,
        .pixelLuminance,
    ]

    private static let fixedByRawValue: [String: MetricKey] = Dictionary(uniqueKeysWithValues: fixedKeys.map { ($0.rawValue, $0) })

    private static let distributionKeys: Set<MetricKey> = [
        .peakMemoryMB, .suspendedMemoryMB, .pixelLuminance, .hitchRatio,
        .binaryFileSizeMB, .dataFileSizeMB, .cacheFolderSizeMB, .cloneSizeMB, .diskCapacityMB, .diskUsedMB,
    ]

    /// Whether the key holds a per-device snapshot, such as peak memory or a Metal layer's
    /// frame rate.
    ///
    /// Groups report the spread of snapshot values across devices instead of summing them.
    public var isDistribution: Bool {
        if case .metalFPS = self { return true }
        return Self.distributionKeys.contains(self)
    }
}

extension MetricKey {
    /// Two keys are equal when they store under the same string, so ``unknown(_:)`` holding
    /// a known key's string equals that key.
    public static func == (lhs: MetricKey, rhs: MetricKey) -> Bool {
        lhs.rawValue == rhs.rawValue
    }

    /// Hashes the stored string, matching ``==(_:_:)``.
    ///
    /// - Parameter hasher: The hasher to feed.
    public func hash(into hasher: inout Hasher) {
        hasher.combine(rawValue)
    }
}

extension MetricKey: RawRepresentable {
    /// Reads a stored key.
    ///
    /// It never fails: a key this version doesn't know becomes ``unknown(_:)``.
    ///
    /// - Parameter rawValue: The stored key, such as `"hitchTime.ratio"`.
    public init(rawValue: String) {
        if let fixed = Self.fixedByRawValue[rawValue] {
            self = fixed
        } else if let reason = Self.suffix(of: rawValue, after: "foregroundTermination.").flatMap(ForegroundTerminationReason.init(rawValue:)) {
            self = .foregroundTermination(reason)
        } else if let reason = Self.suffix(of: rawValue, after: "backgroundTermination.").flatMap(BackgroundTerminationReason.init(rawValue:)) {
            self = .backgroundTermination(reason)
        } else if let accuracy = Self.suffix(of: rawValue, after: "locationActivityTime.").flatMap(LocationAccuracy.init(rawValue:)) {
            self = .locationSeconds(accuracy)
        } else if let layer = Self.metalLayer(in: rawValue, measure: "fps") {
            self = .metalFPS(layer: layer)
        } else if let layer = Self.metalLayer(in: rawValue, measure: "frames") {
            self = .metalFrames(layer: layer)
        } else if let layer = Self.metalLayer(in: rawValue, measure: "activeSeconds") {
            self = .metalActiveSeconds(layer: layer)
        } else {
            self = .unknown(rawValue)
        }
    }

    /// The stored key, such as `"hitchTime.ratio"` for ``hitchRatio``.
    public var rawValue: String {
        switch self {
        case .timeToFirstDraw: "timeToFirstDraw"
        case .optimizedTimeToFirstDraw: "optimizedTimeToFirstDraw"
        case .extendedLaunch: "extendedLaunch"
        case .applicationResumeTime: "applicationResumeTime"
        case .hangTime: "hangTime"
        case .hitchRatio: "hitchTime.ratio"
        case .hitchSeconds: "hitchTime.totalSeconds"
        case .animationSeconds: "hitchTime.animationSeconds"
        case .foregroundSeconds: "totalForegroundTime.seconds"
        case .backgroundSeconds: "totalBackgroundTime.seconds"
        case .backgroundAudioSeconds: "totalBackgroundAudioTime.seconds"
        case .backgroundLocationSeconds: "totalBackgroundLocationTime.seconds"
        case .cpuSeconds: "cpuTime.seconds"
        case .cpuInstructions: "cpuInstructionsCount"
        case .gpuSeconds: "gpuTime.seconds"
        case .peakMemoryMB: "peakMemory.mb"
        case .suspendedMemoryMB: "suspendedMemory.averageMB"
        case .wifiUploadMB: "totalWiFiUpload.mb"
        case .wifiDownloadMB: "totalWiFiDownload.mb"
        case .cellularUploadMB: "totalCellularUpload.mb"
        case .cellularDownloadMB: "totalCellularDownload.mb"
        case .cellularConditionBars: "cellularConditionTime"
        case .logicalDiskWritesMB: "logicalDiskWrites.mb"
        case .binaryFileCount: "totalFileCount.binary"
        case .dataFileCount: "totalFileCount.data"
        case .binaryFileSizeMB: "totalFileSize.binaryMB"
        case .dataFileSizeMB: "totalFileSize.dataMB"
        case .cacheFolderSizeMB: "totalFileSize.cacheMB"
        case .cloneSizeMB: "totalFileSize.cloneMB"
        case .diskCapacityMB: "totalDiskSpace.capacityMB"
        case .diskUsedMB: "totalDiskSpace.usedMB"
        case .pixelLuminance: "pixelLuminance.average"
        case .metalFPS(let layer): "metalFrameRate[\(layer)].fps"
        case .metalFrames(let layer): "metalFrameRate[\(layer)].frames"
        case .metalActiveSeconds(let layer): "metalFrameRate[\(layer)].activeSeconds"
        case .foregroundTermination(let reason): "foregroundTermination.\(reason.rawValue)"
        case .backgroundTermination(let reason): "backgroundTermination.\(reason.rawValue)"
        case .locationSeconds(let accuracy): "locationActivityTime.\(accuracy.rawValue)"
        case .unknown(let rawValue): rawValue
        }
    }

    private static func suffix(of rawValue: String, after prefix: String) -> String? {
        rawValue.hasPrefix(prefix) ? String(rawValue.dropFirst(prefix.count)) : nil
    }

    private static func metalLayer(in rawValue: String, measure: String) -> String? {
        let prefix = "metalFrameRate[", suffix = "].\(measure)"
        guard rawValue.hasPrefix(prefix), rawValue.hasSuffix(suffix), rawValue.count >= prefix.count + suffix.count else { return nil }
        return String(rawValue.dropFirst(prefix.count).dropLast(suffix.count))
    }
}

extension MetricKey: Codable {
    /// Decodes a key from its stored string.
    ///
    /// - Parameter decoder: The decoder to read from.
    /// - Throws: `DecodingError` if the value isn't a string.
    public init(from decoder: any Decoder) throws {
        self.init(rawValue: try decoder.singleValueContainer().decode(String.self))
    }

    /// Encodes the key as its stored string.
    ///
    /// - Parameter encoder: The encoder to write to.
    /// - Throws: An encoding error from `encoder`.
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

// Without this, a `[MetricKey: Double]` encodes as an array of alternating keys and values
// instead of a JSON object, which would change the stored format.
extension MetricKey: CodingKeyRepresentable {
    private struct Key: CodingKey {
        let stringValue: String
        var intValue: Int? { nil }
        init(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { nil }
    }

    /// The key as a JSON object key.
    public var codingKey: any CodingKey { Key(stringValue: rawValue) }

    /// Reads a key from a JSON object key.
    ///
    /// - Parameter codingKey: The object key.
    public init?<T: CodingKey>(codingKey: T) {
        self.init(rawValue: codingKey.stringValue)
    }
}

/// Why the system ended the app in the foreground, as MetricKit's `foregroundTermination`
/// breaks it down.
public enum ForegroundTerminationReason: String, CaseIterable, Codable, Sendable {
    /// The app exited normally.
    case normal
    /// The app exceeded its memory limit.
    case memoryLimit
    /// The app accessed invalid memory.
    case badAccess
    /// The app ended abnormally for another reason.
    case abnormal
    /// The app ran an illegal instruction.
    case illegalInstruction
    /// The watchdog ended the app for being unresponsive.
    case watchdog
}

/// Why the system ended the app in the background, as MetricKit's `backgroundTermination`
/// breaks it down.
public enum BackgroundTerminationReason: String, CaseIterable, Codable, Sendable {
    /// The app exited normally.
    case normal
    /// The app exceeded its memory limit.
    case memoryLimit
    /// The app used too much CPU in the background.
    case highCPU
    /// The system reclaimed resources under pressure.
    case systemPressure
    /// The app accessed invalid memory.
    case badAccess
    /// The app ended abnormally for another reason.
    case abnormal
    /// The app ran an illegal instruction.
    case illegalInstruction
    /// The watchdog ended the app for being unresponsive.
    case watchdog
    /// The app held a file lock while suspended.
    case fileLock
    /// A background task ran past its time limit.
    case taskTimeout
}

/// A location accuracy level, as MetricKit's `locationActivityTime` breaks it down.
public enum LocationAccuracy: String, CaseIterable, Codable, Sendable {
    /// `kCLLocationAccuracyBestForNavigation`.
    case bestAccuracyForNavigation
    /// `kCLLocationAccuracyBest`.
    case bestAccuracy
    /// `kCLLocationAccuracyNearestTenMeters`.
    case tenMeters
    /// `kCLLocationAccuracyHundredMeters`.
    case oneHundredMeters
    /// `kCLLocationAccuracyKilometer`.
    case oneKilometer
    /// `kCLLocationAccuracyThreeKilometers`.
    case threeKilometers
    /// `kCLLocationAccuracyReduced`.
    case reducedAccuracy
}

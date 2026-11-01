import Foundation

/// Deterministic per-install sampling.
///
/// The same install is either always in or always out for a given rate, so trends and
/// retention cohorts stay consistent, and counts can be scaled back up by `1 / rate`.
public enum Sampling {
    /// Whether an install reports at a given rate.
    ///
    /// - Parameters:
    ///   - installID: The install's ID.
    ///   - rate: The share of installs that report, from `0` to `1`.
    /// - Returns: The same answer every time for the same install and rate.
    public static func includes(installID: String, rate: Double) -> Bool {
        guard rate < 1 else { return true }
        guard rate > 0 else { return false }
        let bucket = stableHash(Data(installID.utf8)) % 10_000
        return Double(bucket) < rate * 10_000
    }

    /// A rate that keeps roughly `targetPerGroup` reporting devices in the largest
    /// device-model group.
    ///
    /// The ShipPulse app writes the result to the `SPConfig` record.
    ///
    /// - Parameters:
    ///   - largestGroupDevices: Devices in the largest device-model group.
    ///   - targetPerGroup: Reporting devices to keep in that group.
    /// - Returns: A rate from a few fixed steps, so the sample rarely changes.
    public static func recommendedRate(largestGroupDevices: Int, targetPerGroup: Int = 300) -> Double {
        guard largestGroupDevices > targetPerGroup else { return 1 }
        let raw = Double(targetPerGroup) / Double(largestGroupDevices)
        // Round to a few stable steps so the rate (and therefore the sample) rarely changes.
        let steps: [Double] = [1, 0.5, 0.25, 0.1, 0.05, 0.02, 0.01]
        return steps.first { $0 <= raw } ?? 0.01
    }

    /// The FNV-1a hash of some data.
    ///
    /// Unlike `Hashable.hashValue`, it is stable across processes.
    ///
    /// - Parameter data: The bytes to hash.
    /// - Returns: A 64-bit hash.
    public static func stableHash(_ data: Data) -> UInt64 {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in data {
            hash ^= UInt64(byte)
            hash = hash &* 0x100000001b3
        }
        return hash
    }
}

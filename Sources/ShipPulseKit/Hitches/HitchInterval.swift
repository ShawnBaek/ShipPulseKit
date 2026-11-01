#if canImport(MetricKit) && !os(watchOS) && !os(tvOS) && !os(visionOS)
import Foundation
import MetricKit
import os
import ShipPulseKitCore

/// A measured region of animation or scrolling.
///
/// Create one with ``ShipPulseKit/beginHitchInterval(_:category:)``. It emits a MetricKit
/// animation signpost (`mxSignpostAnimationIntervalBegin`), so Apple reports hitch time,
/// hitch ratio and run count for this name in the daily `SignpostIntervalMetric`. The
/// measurement is MetricKit's own, at no runtime cost to the app.
///
/// Names are `StaticString` because MetricKit signposts require compile-time names.
///
/// `@unchecked Sendable`: `isOpen` is mutated only on the main actor; `deinit` reads it
/// after the last reference is gone.
public final class HitchInterval: @unchecked Sendable {
    private let name: StaticString
    private let log: OSLog
    private let signpostID: OSSignpostID
    private var isOpen = true

    @MainActor
    init(name: StaticString, category: String) {
        self.name = name
        self.log = SignpostLogs.handle(category: category)
        self.signpostID = OSSignpostID(log: log)
        mxSignpostAnimationIntervalBegin(log: log, name: name, signpostID: signpostID)
    }

    /// Ends the interval.
    ///
    /// Calling it more than once is harmless. An interval released without `end()` is
    /// closed automatically.
    @MainActor
    public func end() {
        guard isOpen else { return }
        isOpen = false
        mxSignpost(.end, log: log, name: name, signpostID: signpostID)
    }

    deinit {
        // An interval dropped without `end()` is closed so the signpost doesn't leak.
        guard isOpen else { return }
        let log = log, name = name, id = signpostID
        mxSignpost(.end, log: log, name: name, signpostID: id)
    }
}

/// Caches one `OSLog` per category, as `MetricManager.logHandle(category:)` requires.
enum SignpostLogs {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var handles: [String: OSLog] = [:]

    static func handle(category: String) -> OSLog {
        lock.lock()
        defer { lock.unlock() }
        if let existing = handles[category] { return existing }
        let handle = MetricManager.logHandle(category: category)
        handles[category] = handle
        return handle
    }
}
#endif

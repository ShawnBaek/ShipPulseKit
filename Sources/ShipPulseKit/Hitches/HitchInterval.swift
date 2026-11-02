#if canImport(MetricKit) && !os(watchOS) && !os(tvOS) && !os(visionOS)
import Foundation
import MetricKit
import os
import ShipPulseKitCore

/// A measured region of animation or scrolling.
///
/// Available on iOS and macOS, not on watchOS or visionOS, where MetricKit has no
/// animation signposts.
///
/// Create one with ``ShipPulseKit/beginHitchInterval(_:category:)``. It emits a MetricKit
/// animation signpost (`mxSignpostAnimationIntervalBegin`), so Apple reports hitch time,
/// hitch ratio and run count for this name in the daily `SignpostIntervalMetric`. The
/// measurement is MetricKit's own, at no runtime cost to the app.
///
/// Names are `StaticString` because MetricKit signposts require compile-time names.
///
/// An interval belongs to the main actor, like the animations and scrolling it measures:
/// every API that opens one is a main-actor UI API, so the compiler checks every use and no
/// lock is needed. It ends exactly once, and an interval released without ``end()`` is
/// closed automatically.
@MainActor
public final class HitchInterval {
    private let name: StaticString
    private let log: OSLog
    private let signpostID: OSSignpostID
    private var isOpen = true

    /// Begins the animation signpost.
    ///
    /// - Parameters:
    ///   - name: The region's name, shown in ShipPulse.
    ///   - category: The signpost category; one `OSLog` is cached per category.
    init(name: StaticString, category: String) {
        self.name = name
        self.log = SignpostLogs.handle(category: category)
        self.signpostID = OSSignpostID(log: log)
        mxSignpostAnimationIntervalBegin(log: log, name: name, signpostID: signpostID)
    }

    /// Ends the interval.
    ///
    /// Call it on the main actor. Calling it again is harmless: the signpost ends once. An
    /// interval released without `end()` is closed automatically.
    public func end() {
        guard isOpen else { return }
        isOpen = false
        mxSignpost(.end, log: log, name: name, signpostID: signpostID)
    }

    /// Closes an interval dropped without ``end()``, so its signpost doesn't leak.
    ///
    /// `isolated` (SE-0371) runs it on the main actor, so it reads `isOpen` without a lock.
    isolated deinit {
        end()
    }
}

/// Caches one `OSLog` per category, as `MetricManager.logHandle(category:)` requires.
///
/// Main-actor isolated because only ``HitchInterval``, which lives there, reads it.
@MainActor
enum SignpostLogs {
    private static var handles: [String: OSLog] = [:]

    /// The log handle for a signpost category, created on first use.
    ///
    /// - Parameter category: The signpost category.
    /// - Returns: The cached `OSLog` from `MetricManager.logHandle(category:)`.
    static func handle(category: String) -> OSLog {
        if let existing = handles[category] { return existing }
        let handle = MetricManager.logHandle(category: category)
        handles[category] = handle
        return handle
    }
}
#endif

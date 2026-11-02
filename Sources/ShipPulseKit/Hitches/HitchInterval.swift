#if canImport(MetricKit) && !os(watchOS) && !os(tvOS) && !os(visionOS)
import Foundation
import MetricKit
import os
import ShipPulseKitCore
import Synchronization

/// A measured region of animation or scrolling.
///
/// Create one with ``ShipPulseKit/beginHitchInterval(_:category:)``. It emits a MetricKit
/// animation signpost (`mxSignpostAnimationIntervalBegin`), so Apple reports hitch time,
/// hitch ratio and run count for this name in the daily `SignpostIntervalMetric`. The
/// measurement is MetricKit's own, at no runtime cost to the app.
///
/// Names are `StaticString` because MetricKit signposts require compile-time names.
///
/// An interval is `Sendable`: you can end it from any thread or task, and it ends exactly
/// once.
public final class HitchInterval: Sendable {
    private let name: StaticString
    private let log: OSLog
    private let signpostID: OSSignpostID
    private let isOpen = Mutex(true)

    /// Begins the animation signpost.
    ///
    /// Main-actor isolated because every entry point that opens an interval is a main-actor
    /// UI API: ``ShipPulseKit/beginHitchInterval(_:category:)``, the animation helpers and
    /// the scroll trackers.
    ///
    /// - Parameters:
    ///   - name: The region's name, shown in ShipPulse.
    ///   - category: The signpost category; one `OSLog` is cached per category.
    @MainActor
    init(name: StaticString, category: String) {
        self.name = name
        self.log = SignpostLogs.handle(category: category)
        self.signpostID = OSSignpostID(log: log)
        mxSignpostAnimationIntervalBegin(log: log, name: name, signpostID: signpostID)
    }

    /// Ends the interval.
    ///
    /// Calling it more than once, from any thread, is harmless. An interval released
    /// without `end()` is closed automatically.
    public func end() {
        guard isOpen.withLock({ open in
            defer { open = false }
            return open
        }) else { return }
        mxSignpost(.end, log: log, name: name, signpostID: signpostID)
    }

    /// Closes an interval dropped without ``end()``, so its signpost doesn't leak.
    deinit {
        end()
    }
}

/// Caches one `OSLog` per category, as `MetricManager.logHandle(category:)` requires.
enum SignpostLogs {
    private static let handles = Mutex<[String: OSLog]>([:])

    /// The log handle for a signpost category, created on first use.
    ///
    /// - Parameter category: The signpost category.
    /// - Returns: The cached `OSLog` from `MetricManager.logHandle(category:)`.
    static func handle(category: String) -> OSLog {
        handles.withLock { handles in
            if let existing = handles[category] { return existing }
            let handle = MetricManager.logHandle(category: category)
            handles[category] = handle
            return handle
        }
    }
}
#endif

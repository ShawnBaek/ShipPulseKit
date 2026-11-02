#if canImport(MetricKit) && !os(watchOS) && !os(tvOS) && !os(visionOS)
import Foundation
import ShipPulseKitCore

// Opt-in hitch measurement for specific regions, through MetricKit animation signposts.
// Without any of this, `start(_:)` already records app-wide hitch time and ratio, broken
// down by screen.
extension ShipPulseKit {
    /// Opens a measured hitch interval.
    ///
    /// Available on iOS and macOS, not on watchOS or visionOS, where MetricKit has no
    /// animation signposts.
    ///
    /// Keep the returned value and call ``HitchInterval/end()`` when the region ends:
    ///
    /// ```swift
    /// let interval = ShipPulseKit.beginHitchInterval("PhotoGrid")
    /// // ...
    /// interval.end()
    /// ```
    ///
    /// - Parameters:
    ///   - name: The region's name, shown in ShipPulse.
    ///   - category: The signpost category. Defaults to `"ShipPulse"`.
    /// - Returns: The open interval.
    @MainActor
    public static func beginHitchInterval(_ name: StaticString, category: String = "ShipPulse") -> HitchInterval {
        HitchInterval(name: name, category: category)
    }

    /// Measures hitches while `body` runs, including work that spans an `await`.
    ///
    /// Available on iOS and macOS, not on watchOS or visionOS, where MetricKit has no
    /// animation signposts.
    ///
    /// - Parameters:
    ///   - name: The region's name, shown in ShipPulse.
    ///   - category: The signpost category. Defaults to `"ShipPulse"`.
    ///   - operation: The work to measure.
    /// - Returns: The result of `operation`.
    @MainActor
    public static func measureHitches<Result>(_ name: StaticString, category: String = "ShipPulse", _ operation: () async throws -> Result) async rethrows -> Result {
        let interval = HitchInterval(name: name, category: category)
        defer { interval.end() }
        return try await operation()
    }
}

#if canImport(SwiftUI)
import SwiftUI

extension ShipPulseKit {
    /// Runs SwiftUI's `withAnimation` and measures hitches until the animation logically
    ///
    /// Available on iOS and macOS, not on watchOS or visionOS, where MetricKit has no
    /// animation signposts.
    /// completes.
    ///
    /// ```swift
    /// ShipPulseKit.withAnimation("CardFlip", .spring) { isFlipped.toggle() }
    /// ```
    ///
    /// - Parameters:
    ///   - name: The region's name, shown in ShipPulse.
    ///   - animation: The animation to apply.
    ///   - category: The signpost category. Defaults to `"ShipPulse"`.
    ///   - body: The state change to animate.
    /// - Returns: The result of `body`.
    @MainActor
    public static func withAnimation<Result>(_ name: StaticString, _ animation: Animation? = .default, category: String = "ShipPulse", _ body: () throws -> Result) rethrows -> Result {
        let interval = HitchInterval(name: name, category: category)
        return try SwiftUI.withAnimation(animation, completionCriteria: .logicallyComplete, body) {
            interval.end()
        }
    }
}

private struct HitchWhileVisible: ViewModifier {
    let name: StaticString
    let category: String
    @State private var interval: HitchInterval?

    func body(content: Content) -> some View {
        content
            .onAppear { interval = HitchInterval(name: name, category: category) }
            .onDisappear { interval?.end(); interval = nil }
    }
}

private struct HitchWhileScrolling: ViewModifier {
    let name: StaticString
    let category: String
    @State private var interval: HitchInterval?

    func body(content: Content) -> some View {
        content.onScrollPhaseChange { _, phase in
            if phase.isScrolling {
                if interval == nil { interval = HitchInterval(name: name, category: category) }
            } else {
                interval?.end()
                interval = nil
            }
        }
    }
}

extension View {
    /// Measures hitches for as long as this view is on screen.
    ///
    /// Available on iOS and macOS, not on watchOS or visionOS, where MetricKit has no
    /// animation signposts.
    ///
    /// - Parameters:
    ///   - name: The region's name, shown in ShipPulse.
    ///   - category: The signpost category. Defaults to `"ShipPulse"`.
    /// - Returns: A view that measures hitches while visible.
    @MainActor
    public func shipPulseHitches(_ name: StaticString, category: String = "ShipPulse") -> some View {
        modifier(HitchWhileVisible(name: name, category: category))
    }

    /// Measures hitches only while the scroll view moves.
    ///
    /// The SwiftUI counterpart of UIKit's `shipPulseTrackScrollHitches(_:category:)`.
    ///
    /// Available on iOS and macOS, not on watchOS or visionOS, where MetricKit has no
    /// animation signposts.
    ///
    /// Attach it to a `ScrollView`, `List` or `Form`. The interval covers dragging,
    /// decelerating and programmatic scrolling:
    ///
    /// ```swift
    /// List(items) { ItemRow(item: $0) }
    ///     .shipPulseScrollHitches("FeedScroll")
    /// ```
    ///
    /// - Parameters:
    ///   - name: The region's name, shown in ShipPulse.
    ///   - category: The signpost category. Defaults to `"ShipPulse"`.
    /// - Returns: A view that measures hitches while scrolling.
    @MainActor
    public func shipPulseScrollHitches(_ name: StaticString, category: String = "ShipPulse") -> some View {
        modifier(HitchWhileScrolling(name: name, category: category))
    }
}
#endif

#if canImport(UIKit)
import UIKit

extension UIView {
    /// Runs `UIView.animate` and measures hitches until the animation completes.
    ///
    /// The UIKit counterpart of SwiftUI's ``ShipPulseKit/ShipPulseKit/withAnimation(_:_:category:_:)``.
    ///
    /// Available on iOS, not on watchOS or visionOS, where MetricKit has no animation
    /// signposts.
    ///
    /// - Parameters:
    ///   - name: The region's name, shown in ShipPulse.
    ///   - duration: The animation's duration, in seconds.
    ///   - delay: Seconds to wait before the animation starts.
    ///   - options: The animation options.
    ///   - category: The signpost category. Defaults to `"ShipPulse"`.
    ///   - animations: The changes to animate.
    ///   - completion: Called when the animation ends, after the interval closes.
    @MainActor
    public static func shipPulseAnimate(
        _ name: StaticString,
        withDuration duration: TimeInterval,
        delay: TimeInterval = 0,
        options: UIView.AnimationOptions = [],
        category: String = "ShipPulse",
        animations: @escaping () -> Void,
        completion: ((Bool) -> Void)? = nil
    ) {
        let interval = HitchInterval(name: name, category: category)
        UIView.animate(withDuration: duration, delay: delay, options: options, animations: animations) { finished in
            interval.end()
            completion?(finished)
        }
    }
}

extension UIViewPropertyAnimator {
    /// Measures hitches from now until the animator finishes.
    ///
    /// The UIKit counterpart of SwiftUI's ``ShipPulseKit/ShipPulseKit/withAnimation(_:_:category:_:)``,
    /// for property animators.
    ///
    /// Available on iOS, not on watchOS or visionOS, where MetricKit has no animation
    /// signposts.
    ///
    /// Call it before `startAnimation()`.
    ///
    /// - Parameters:
    ///   - name: The region's name, shown in ShipPulse.
    ///   - category: The signpost category. Defaults to `"ShipPulse"`.
    @MainActor
    public func shipPulseTrackHitches(_ name: StaticString, category: String = "ShipPulse") {
        let interval = HitchInterval(name: name, category: category)
        addCompletion { _ in interval.end() }
    }
}

extension UIScrollView {
    /// Measures hitches whenever this scroll view is dragged or decelerating.
    ///
    /// The UIKit counterpart of SwiftUI's `shipPulseScrollHitches(_:category:)`.
    ///
    /// Available on iOS, not on watchOS or visionOS, where MetricKit has no animation
    /// signposts.
    ///
    /// It doesn't touch the delegate, so it works alongside your own
    /// `UIScrollViewDelegate`:
    ///
    /// ```swift
    /// collectionView.shipPulseTrackScrollHitches("PhotoGridScroll")
    /// ```
    ///
    /// - Parameters:
    ///   - name: The region's name, shown in ShipPulse.
    ///   - category: The signpost category. Defaults to `"ShipPulse"`.
    @MainActor
    public func shipPulseTrackScrollHitches(_ name: StaticString, category: String = "ShipPulse") {
        let tracker = ScrollHitchTracker(name: name, category: category, scrollView: self)
        objc_setAssociatedObject(self, &ScrollHitchTracker.associationKey, tracker, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
    }
}

/// Opens an interval when the pan gesture begins and closes it once deceleration settles,
/// observed through `contentOffset` KVO, with no per-frame callback of its own.
@MainActor
final class ScrollHitchTracker: NSObject {
    /// Only its address is used, as the associated-object key. Main-actor isolated like the
    /// rest of the class, so the compiler checks every access.
    static var associationKey: UInt8 = 0
    private let name: StaticString
    private let category: String
    private weak var scrollView: UIScrollView?
    private var interval: HitchInterval?
    private var offsetObservation: NSKeyValueObservation?
    private var settleCheck: DispatchWorkItem?

    /// Starts watching a scroll view's pan gesture.
    ///
    /// It adds itself as a gesture target instead of becoming the delegate, so the app's own
    /// `UIScrollViewDelegate` keeps working.
    ///
    /// - Parameters:
    ///   - name: The region's name, shown in ShipPulse.
    ///   - category: The signpost category.
    ///   - scrollView: The scroll view to watch. Held weakly; it retains the tracker.
    init(name: StaticString, category: String, scrollView: UIScrollView) {
        self.name = name
        self.category = category
        self.scrollView = scrollView
        super.init()
        scrollView.panGestureRecognizer.addTarget(self, action: #selector(pan(_:)))
    }

    @objc private func pan(_ gesture: UIPanGestureRecognizer) {
        switch gesture.state {
        case .began:
            if interval == nil { interval = HitchInterval(name: name, category: category) }
            offsetObservation = nil
        case .ended, .cancelled, .failed:
            closeWhenSettled()
        default:
            break
        }
    }

    private func closeWhenSettled() {
        guard let scrollView, scrollView.isDecelerating else { return finish() }
        offsetObservation = scrollView.observe(\.contentOffset, options: [.new]) { [weak self] _, _ in
            MainActor.assumeIsolated { self?.scheduleSettleCheck() }
        }
        scheduleSettleCheck()
    }

    /// The last offset change can arrive while `isDecelerating` is still true, so re-check
    /// shortly after motion pauses instead of trusting the final callback.
    private func scheduleSettleCheck() {
        settleCheck?.cancel()
        let check = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                guard let self, let view = self.scrollView else { return }
                if !view.isDecelerating && !view.isTracking { self.finish() }
            }
        }
        settleCheck = check
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12, execute: check)
    }

    private func finish() {
        settleCheck?.cancel()
        settleCheck = nil
        offsetObservation = nil
        interval?.end()
        interval = nil
    }
}
#endif
#endif

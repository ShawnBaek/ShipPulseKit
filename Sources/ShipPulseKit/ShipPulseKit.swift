import Foundation
import ShipPulseKitCore
#if canImport(MetricKit) && !os(watchOS) && !os(tvOS)
import MetricKit
#endif

/// The entry point to ShipPulseKit.
///
/// Call ``start(_:)`` once, early in app launch. ShipPulseKit then records every MetricKit
/// metric and diagnostic plus an anonymous first-launch and daily-open signal, queues them
/// on disk, and uploads them to a CloudKit container you own.
///
/// There is no ShipPulse server. The ShipPulse app reads the same container to show vitals
/// and retention, even for apps too small for App Store Connect analytics.
public enum ShipPulseKit {
    @MainActor private static var engine: Engine?

    /// Starts collecting metrics, diagnostics and retention signals.
    ///
    /// Call it once from `application(_:didFinishLaunchingWithOptions:)` or your SwiftUI
    /// `App` initializer. If it throws, the app keeps running without metrics:
    ///
    /// ```swift
    /// do {
    ///     try ShipPulseKit.start()
    /// } catch {
    ///     print(error.localizedDescription)
    /// }
    /// ```
    ///
    /// - Parameter configuration: Where records go and what is collected. The default
    ///   writes everything to the public database of the first container in the app's
    ///   entitlements.
    /// - Throws: ``ShipPulseKitError`` with code ``ShipPulseKitError/Code/iCloudContainerUnavailable``
    ///   when the app has no usable iCloud container, or
    ///   ``ShipPulseKitError/Code/alreadyStarted`` on a second call.
    @MainActor
    public static func start(_ configuration: Configuration = Configuration()) throws(ShipPulseKitError) {
        guard engine == nil else { throw .alreadyStarted }
        let engine = try Engine(configuration: configuration)
        self.engine = engine
        engine.start()
    }

    /// Uploads every record still queued on disk.
    ///
    /// ShipPulseKit already uploads on launch, on each new report and on returning to the
    /// foreground. Call this only for extra delivery points, such as a background task.
    @MainActor
    public static func flush() async {
        await engine?.flush()
    }

    /// Marks the screen the user is on.
    ///
    /// MetricKit then breaks hitches, hangs, memory and every other metric down by screen,
    /// so ShipPulse can show which screen hitches. In SwiftUI, prefer
    /// `shipPulseScreen(_:fileID:)`. In UIKit,
    /// ``Configuration/automaticScreenTracking`` reports view controllers for you.
    ///
    /// Main-actor isolated because screens change on the main thread, so transitions are
    /// reported in the order the user saw them.
    ///
    /// - Parameter name: The screen's name, or `nil` when no screen is showing.
    @MainActor
    public static func reportScreen(_ name: String?) {
        ScreenReporter.shared.report(name)
    }

    #if canImport(MetricKit) && !os(watchOS) && !os(tvOS) && !os(visionOS)
    /// Runs work that is part of launch so MetricKit counts it in extended launch time.
    ///
    /// Available on iOS and macOS, not on watchOS or visionOS, where MetricKit has no
    /// launch tasks.
    ///
    /// Use it for work the user waits on before the app is usable, such as loading the
    /// first feed:
    ///
    /// ```swift
    /// let feed = await ShipPulseKit.trackLaunchTask("LoadFeed") {
    ///     await store.loadFeed()
    /// }
    /// ```
    ///
    /// Before ``start(_:)`` succeeds, the operation simply runs untracked.
    ///
    /// - Parameters:
    ///   - id: A stable name for the task, shown in ShipPulse.
    ///   - operation: The launch work.
    /// - Returns: The operation's result.
    /// - Throws: Whatever `operation` throws.
    @MainActor
    public static func trackLaunchTask<Result, Failure: Error>(
        _ id: String,
        _ operation: () async throws(Failure) -> Result
    ) async throws(Failure) -> Result {
        guard let manager = engine?.metricManager else { return try await operation() }
        return try await manager.trackLaunchTask(id: LaunchTaskID(rawValue: id), operation)
    }
    #endif
}

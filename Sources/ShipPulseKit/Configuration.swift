import Foundation

/// Options for ``ShipPulseKit/start(_:)``.
///
/// The defaults suit most apps; pass a configuration only to change the container or turn
/// something off:
///
/// ```swift
/// try ShipPulseKit.start(.init(containerIdentifier: "iCloud.com.example.metrics"))
/// ```
public struct Configuration: Sendable, Equatable {
    /// Where records are written inside your container.
    public enum Database: Sendable, Equatable {
        /// Records from every user's device land in your container.
        ///
        /// This is what the ShipPulse app reads; use it in production.
        case `public`
        /// Records land in each user's own iCloud private database, which you cannot read.
        ///
        /// Useful only while developing, to see payloads from devices signed in to your
        /// own Apple Account.
        case `private`
    }

    /// The iCloud container identifier, for example `iCloud.com.example.app`.
    ///
    /// `nil` uses the first container in the app's entitlements.
    public var containerIdentifier: String?
    /// The database records are written to. The default is ``Configuration/Database/public``.
    public var database: Database
    /// Whether daily MetricKit metric reports are recorded.
    public var collectsMetrics: Bool
    /// Whether MetricKit diagnostics (crashes, hangs, exceptions) are recorded.
    public var collectsDiagnostics: Bool
    /// Whether the anonymous first-launch and daily-open records used for retention are sent.
    public var tracksRetention: Bool
    /// The share of installs that report.
    ///
    /// Sampling is per install, so the same devices keep reporting and the ShipPulse app
    /// scales counts back up.
    public var sampling: SamplingMode
    /// The share of installs that report diagnostics.
    ///
    /// Diagnostics carry call stacks and are larger, so they can be sampled separately.
    public var diagnosticSampling: SamplingMode
    /// Extra MetricKit state-reporting domains to break metrics down by.
    ///
    /// The screen domain used by `shipPulseScreen(_:fileID:)` is always enabled.
    public var additionalStateDomains: Set<String>
    /// Whether UIKit view controllers are reported as screens automatically.
    ///
    /// When `true`, each content view controller's class name becomes the screen when it
    /// appears, so per-screen metrics work with no code beyond ``ShipPulseKit/start(_:)``.
    public var tracksScreensAutomatically: Bool
    /// How long a pending record waits for upload before it is dropped. The default is 30
    /// days.
    public var maxPendingRecordAge: TimeInterval
    /// The most pending records kept on the device while uploads can't happen. The oldest
    /// are dropped first. The default is 500.
    public var maxPendingRecords: Int

    /// Creates a configuration. Every parameter matches the property of the same name.
    public init(
        containerIdentifier: String? = nil,
        database: Database = .public,
        collectsMetrics: Bool = true,
        collectsDiagnostics: Bool = true,
        tracksRetention: Bool = true,
        sampling: SamplingMode = .automatic,
        diagnosticSampling: SamplingMode = .automatic,
        additionalStateDomains: Set<String> = [],
        tracksScreensAutomatically: Bool = true,
        maxPendingRecordAge: TimeInterval = 30 * 24 * 60 * 60,
        maxPendingRecords: Int = 500
    ) {
        self.containerIdentifier = containerIdentifier
        self.database = database
        self.collectsMetrics = collectsMetrics
        self.collectsDiagnostics = collectsDiagnostics
        self.tracksRetention = tracksRetention
        self.sampling = sampling
        self.diagnosticSampling = diagnosticSampling
        self.additionalStateDomains = additionalStateDomains
        self.tracksScreensAutomatically = tracksScreensAutomatically
        self.maxPendingRecordAge = maxPendingRecordAge
        self.maxPendingRecords = maxPendingRecords
    }
}

// 0.1.0 names, kept so host apps get a rename fix-it instead of an error.
extension Configuration {
    /// Creates a configuration with the 0.1.0 parameter names.
    ///
    /// `@_disfavoredOverload` keeps calls that use none of the old names on the current
    /// initializer instead of making them ambiguous.
    @available(*, deprecated, message: "Use automaticScreenTracking → tracksScreensAutomatically, maxQueueAge → maxPendingRecordAge, maxQueuedRecords → maxPendingRecords.")
    @_disfavoredOverload
    public init(
        containerIdentifier: String? = nil,
        database: Database = .public,
        collectsMetrics: Bool = true,
        collectsDiagnostics: Bool = true,
        tracksRetention: Bool = true,
        sampling: SamplingMode = .automatic,
        diagnosticSampling: SamplingMode = .automatic,
        additionalStateDomains: Set<String> = [],
        automaticScreenTracking: Bool = true,
        maxQueueAge: TimeInterval = 30 * 24 * 60 * 60,
        maxQueuedRecords: Int = 500
    ) {
        self.init(
            containerIdentifier: containerIdentifier,
            database: database,
            collectsMetrics: collectsMetrics,
            collectsDiagnostics: collectsDiagnostics,
            tracksRetention: tracksRetention,
            sampling: sampling,
            diagnosticSampling: diagnosticSampling,
            additionalStateDomains: additionalStateDomains,
            tracksScreensAutomatically: automaticScreenTracking,
            maxPendingRecordAge: maxQueueAge,
            maxPendingRecords: maxQueuedRecords
        )
    }

    /// The 0.1.0 name of ``tracksScreensAutomatically``.
    @available(*, deprecated, renamed: "tracksScreensAutomatically")
    public var automaticScreenTracking: Bool {
        get { tracksScreensAutomatically }
        set { tracksScreensAutomatically = newValue }
    }

    /// The 0.1.0 name of ``maxPendingRecordAge``.
    @available(*, deprecated, renamed: "maxPendingRecordAge")
    public var maxQueueAge: TimeInterval {
        get { maxPendingRecordAge }
        set { maxPendingRecordAge = newValue }
    }

    /// The 0.1.0 name of ``maxPendingRecords``.
    @available(*, deprecated, renamed: "maxPendingRecords")
    public var maxQueuedRecords: Int {
        get { maxPendingRecords }
        set { maxPendingRecords = newValue }
    }
}

/// How ShipPulseKit decides what share of installs report.
public enum SamplingMode: Sendable, Equatable {
    /// Follows the rate the ShipPulse app publishes in your container's `SPConfig` record.
    ///
    /// Every install reports while the app is small, and fewer do as it grows.
    case automatic
    /// A fixed share of installs.
    ///
    /// - Parameter rate: The share of installs that report, from `0` to `1`. Values
    ///   outside that range are clamped.
    case fixed(rate: Double)

    /// The 0.1.0 spelling of ``fixed(rate:)``.
    ///
    /// - Parameter rate: The share of installs that report, from `0` to `1`.
    /// - Returns: ``fixed(rate:)``.
    @available(*, deprecated, renamed: "fixed(rate:)")
    public static func fixed(_ rate: Double) -> SamplingMode {
        .fixed(rate: rate)
    }
}

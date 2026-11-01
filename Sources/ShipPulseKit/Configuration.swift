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
    public var automaticScreenTracking: Bool
    /// How long a queued record waits before it is dropped instead of uploaded.
    public var maxQueueAge: TimeInterval
    /// The most records kept on disk while offline. The oldest are dropped first.
    public var maxQueuedRecords: Int

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
        automaticScreenTracking: Bool = true,
        maxQueueAge: TimeInterval = 30 * 24 * 60 * 60,
        maxQueuedRecords: Int = 500
    ) {
        self.containerIdentifier = containerIdentifier
        self.database = database
        self.collectsMetrics = collectsMetrics
        self.collectsDiagnostics = collectsDiagnostics
        self.tracksRetention = tracksRetention
        self.sampling = sampling
        self.diagnosticSampling = diagnosticSampling
        self.additionalStateDomains = additionalStateDomains
        self.automaticScreenTracking = automaticScreenTracking
        self.maxQueueAge = maxQueueAge
        self.maxQueuedRecords = maxQueuedRecords
    }
}

/// How ShipPulseKit decides what share of installs report.
public enum SamplingMode: Sendable, Equatable {
    /// Follows the rate the ShipPulse app publishes in your container's `SPConfig` record.
    ///
    /// Every install reports while the app is small, and fewer do as it grows.
    case automatic
    /// A fixed share of installs, from `0` to `1`.
    case fixed(Double)
}

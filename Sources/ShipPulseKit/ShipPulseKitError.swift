import Foundation

/// Errors that ``ShipPulseKit/start(_:)`` throws.
///
/// ShipPulseKit never crashes the host app. It throws instead, so you decide what to do;
/// usually you log the error and keep going without metrics.
public enum ShipPulseKitError: Error, Equatable, Sendable {
    /// The app has no usable iCloud container.
    ///
    /// Add **Signing & Capabilities → iCloud → CloudKit** with a container, or set
    /// ``Configuration/containerIdentifier`` to a container the app is entitled to.
    ///
    /// - Parameters:
    ///   - containerIdentifier: The container that was requested, or `nil` for the default.
    ///   - reason: Why CloudKit rejected it.
    case iCloudContainerUnavailable(containerIdentifier: String?, reason: String)
    /// ``ShipPulseKit/start(_:)`` was already called.
    ///
    /// Collection keeps running with the first configuration.
    case alreadyStarted
}

extension ShipPulseKitError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .iCloudContainerUnavailable(let identifier, let reason):
            let target = identifier.map { "container \($0)" } ?? "the default iCloud container"
            return "ShipPulseKit can't use \(target): \(reason). Enable iCloud with CloudKit in Signing & Capabilities, or pass a containerIdentifier the app is entitled to."
        case .alreadyStarted:
            return "ShipPulseKit is already running."
        }
    }
}

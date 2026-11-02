import Foundation

/// An error that ``ShipPulseKit/start(_:)`` throws.
///
/// ShipPulseKit never crashes the host app. It throws instead, so you decide what to do;
/// usually you log the error and keep going without metrics.
///
/// Match on ``code``. It is a struct rather than an enum, like `CKError.Code`, so a later
/// release can add codes without breaking your `switch`:
///
/// ```swift
/// do {
///     try ShipPulseKit.start()
/// } catch {
///     switch error.code {
///     case .iCloudContainerUnavailable: print(error.localizedDescription)
///     case .alreadyStarted: break
///     default: print(error.localizedDescription)
///     }
/// }
/// ```
public struct ShipPulseKitError: Error, Equatable, Sendable {
    /// What went wrong.
    public struct Code: RawRepresentable, Hashable, Sendable {
        /// The code's stable name.
        public let rawValue: String

        /// Creates a code from its name.
        ///
        /// - Parameter rawValue: The code's stable name.
        public init(rawValue: String) {
            self.rawValue = rawValue
        }

        /// The app has no usable iCloud container.
        ///
        /// Add **Signing & Capabilities → iCloud → CloudKit** with a container, or set
        /// ``Configuration/containerIdentifier`` to a container the app is entitled to.
        /// ``ShipPulseKitError/containerIdentifier`` and ``ShipPulseKitError/reason`` say
        /// which container and why.
        public static let iCloudContainerUnavailable = Code(rawValue: "iCloudContainerUnavailable")

        /// ``ShipPulseKit/start(_:)`` was already called.
        ///
        /// Collection keeps running with the first configuration.
        public static let alreadyStarted = Code(rawValue: "alreadyStarted")
    }

    /// What went wrong.
    public let code: Code
    /// The container that was requested, or `nil` for the default container or when the
    /// error isn't about a container.
    public let containerIdentifier: String?
    /// Why CloudKit rejected the container, or `nil` when the error isn't about a
    /// container.
    public let reason: String?

    /// The error ``ShipPulseKit/start(_:)`` throws when CloudKit can't open the container.
    ///
    /// - Parameters:
    ///   - containerIdentifier: The container that was requested, or `nil` for the default.
    ///   - reason: Why CloudKit rejected it.
    /// - Returns: An error with code ``Code/iCloudContainerUnavailable``.
    static func iCloudContainerUnavailable(containerIdentifier: String?, reason: String) -> ShipPulseKitError {
        ShipPulseKitError(code: .iCloudContainerUnavailable, containerIdentifier: containerIdentifier, reason: reason)
    }

    /// The error a second ``ShipPulseKit/start(_:)`` throws.
    static let alreadyStarted = ShipPulseKitError(code: .alreadyStarted, containerIdentifier: nil, reason: nil)
}

extension ShipPulseKitError: LocalizedError {
    /// A message for your log that says how to fix the problem.
    public var errorDescription: String? {
        switch code {
        case .iCloudContainerUnavailable:
            let target = containerIdentifier.map { "container \($0)" } ?? "the default iCloud container"
            return "ShipPulseKit can't use \(target): \(reason ?? "unknown reason"). Enable iCloud with CloudKit in Signing & Capabilities, or pass a containerIdentifier the app is entitled to."
        case .alreadyStarted:
            return "ShipPulseKit is already running."
        default:
            return "ShipPulseKit error \(code.rawValue)."
        }
    }
}

import Foundation
import ShipPulseKitCore
import StateReporting
#if canImport(SwiftUI)
import SwiftUI
#endif
#if canImport(UIKit) && !os(watchOS)
import UIKit
#endif

/// Reports the current screen through StateReporting, so MetricKit attributes every metric
/// (hitches, hangs, memory and so on) to it.
final class ScreenReporter: Sendable {
    static let shared = ScreenReporter()

    private let reporter = StateReporter<Never, Never>.reporter(for: Schema.screenDomain)

    func report(_ screen: String?) {
        reporter.reportTransition(to: screen)
    }

    /// Shortens a `#fileID` to its last two path components.
    ///
    /// `"NativeMobile/Feed/FeedView.swift"` becomes `"Feed/FeedView.swift"`: short, but
    /// still identifies the file.
    ///
    /// - Parameter fileID: A `#fileID` value.
    /// - Returns: The screen name.
    static func screenName(fromFileID fileID: String) -> String {
        let parts = fileID.split(separator: "/")
        return parts.count > 2 ? parts.suffix(2).joined(separator: "/") : parts.joined(separator: "/")
    }
}

#if canImport(SwiftUI)
private struct ShipPulseScreenModifier: ViewModifier {
    let name: String

    func body(content: Content) -> some View {
        content.onAppear { ShipPulseKit.reportScreen(name) }
    }
}

extension View {
    /// Attributes MetricKit metrics to this screen while it is visible.
    ///
    /// With no argument, the screen is named after the source file that applies the
    /// modifier, so ShipPulse shows hitches per file, for example `Feed/FeedView.swift`:
    ///
    /// ```swift
    /// FeedView()
    ///     .shipPulseScreen()          // "Feed/FeedView.swift"
    /// SettingsView()
    ///     .shipPulseScreen("Settings")
    /// ```
    ///
    /// - Parameters:
    ///   - name: The screen's name, or `nil` to use the source file.
    ///   - fileID: The caller's file. Leave the default.
    /// - Returns: A view that reports itself as the current screen when it appears.
    public func shipPulseScreen(_ name: String? = nil, fileID: String = #fileID) -> some View {
        modifier(ShipPulseScreenModifier(name: name ?? ScreenReporter.screenName(fromFileID: fileID)))
    }
}
#endif

#if canImport(UIKit) && !os(watchOS)
/// Automatic screen reporting for UIKit.
///
/// Every `viewDidAppear(_:)` of a content view controller reports its class name. Enabled
/// by ``Configuration/automaticScreenTracking``.
enum AutomaticScreenTracking {
    @MainActor private static var installed = false

    @MainActor
    static func install() {
        guard !installed else { return }
        installed = true
        let original = #selector(UIViewController.viewDidAppear(_:))
        let replacement = #selector(UIViewController.shipPulse_viewDidAppear(_:))
        guard let a = class_getInstanceMethod(UIViewController.self, original),
              let b = class_getInstanceMethod(UIViewController.self, replacement) else { return }
        method_exchangeImplementations(a, b)
    }

    /// The screen name for a view controller, or `nil` when it isn't a screen.
    ///
    /// Containers and system controllers aren't screens. Hosting controllers are named after
    /// their root SwiftUI view.
    ///
    /// - Parameter controller: The view controller that appeared.
    /// - Returns: The screen name, or `nil`.
    static func screenName(for controller: UIViewController) -> String? {
        if controller is UINavigationController || controller is UITabBarController
            || controller is UISplitViewController || controller is UIPageViewController {
            return nil
        }
        let name = String(describing: type(of: controller))
        if name.hasPrefix("UI") && !name.hasPrefix("UIHostingController") { return nil }
        if name.hasPrefix("_") { return nil }
        if let open = name.firstIndex(of: "<"), name.hasPrefix("UIHostingController") {
            let inner = name[name.index(after: open)...].dropLast()
            return inner.hasPrefix("AnyView") || inner.hasPrefix("ModifiedContent") ? nil : String(inner)
        }
        return name
    }
}

extension UIViewController {
    @objc fileprivate func shipPulse_viewDidAppear(_ animated: Bool) {
        shipPulse_viewDidAppear(animated) // Calls the original after the exchange.
        if let name = AutomaticScreenTracking.screenName(for: self) {
            ShipPulseKit.reportScreen(name)
        }
    }
}
#endif

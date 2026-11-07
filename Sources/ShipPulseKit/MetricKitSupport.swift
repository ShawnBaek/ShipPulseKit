import Foundation

/// Decides whether the Swift MetricKit API this SDK needs exists on the running system.
///
/// Some OS seeds ship without parts of it while reporting the same version as the release,
/// so `#available` can't tell them apart. iPadOS 27.0 seed 24A5390f, for example, has no
/// `SignpostIntervalMetric.hitchTimeRatio`. A strong reference to such a symbol makes dyld
/// abort the host app before `main`, so every MetricKit and StateReporting import in this
/// module is `@_weakLinked`. A missing symbol then binds to null instead, and this gate keeps
/// the SDK from ever calling through it.
enum MetricKitSupport {
    /// Whether every symbol in ``MetricKitSymbols`` exists. Computed once per process.
    ///
    /// Safe from any thread.
    static let isAvailable = frameworkExports(MetricKitSymbols.metricKit, path: "/System/Library/Frameworks/MetricKit.framework/MetricKit")
        && frameworkExports(MetricKitSymbols.stateReporting, path: "/System/Library/Frameworks/StateReporting.framework/StateReporting")

    /// Whether a framework exports all of the given symbols.
    ///
    /// Searching only the framework's own image rather than `RTLD_DEFAULT` keeps this
    /// well under a millisecond on the main thread, however many images the app has loaded.
    ///
    /// - Parameters:
    ///   - symbols: C symbol names. With none, the framework isn't opened at all, because
    ///     watchOS has no MetricKit.
    ///   - path: The framework's binary.
    /// - Returns: `false` if the framework can't be opened or any symbol is missing.
    static func frameworkExports(_ symbols: [String], path: String) -> Bool {
        guard !symbols.isEmpty else { return true }
        guard let handle = dlopen(path, RTLD_LAZY) else { return false }
        defer { dlclose(handle) }
        return symbols.allSatisfy { dlsym(handle, $0) != nil }
    }
}

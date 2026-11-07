import Foundation
import Testing
@testable import ShipPulseKit

private let metricKitPath = "/System/Library/Frameworks/MetricKit.framework/MetricKit"

@Suite struct MetricKitSupportTests {
    /// A wrong gate would silently turn the SDK off for every user, so a released OS must pass.
    @Test func everySymbolExistsOnThisOS() {
        #expect(MetricKitSupport.isAvailable)
    }

    @Test func listsTheSymbolThatCrashedSeed24A5390f() {
        #if !os(watchOS) && !os(visionOS)
        #expect(MetricKitSymbols.metricKit.contains("$s9MetricKit016SignpostIntervalA0V14hitchTimeRatio10Foundation11MeasurementVyAA05HitchfG0CGSgvg"))
        #endif
    }

    @Test func oneMissingSymbolFailsTheCheck() throws {
        let real = try #require(MetricKitSymbols.stateReporting.first)
        let path = "/System/Library/Frameworks/StateReporting.framework/StateReporting"
        #expect(MetricKitSupport.frameworkExports([real], path: path))
        #expect(!MetricKitSupport.frameworkExports([real, "$sShipPulseKitNoSuchSymbol"], path: path))
    }

    @Test func unopenableFrameworkFailsTheCheck() {
        #expect(!MetricKitSupport.frameworkExports(["anything"], path: "/System/Library/Frameworks/NoSuch.framework/NoSuch"))
    }

    @Test func noSymbolsNeedsNoFramework() {
        #expect(MetricKitSupport.frameworkExports([], path: "/System/Library/Frameworks/NoSuch.framework/NoSuch"))
    }
}

/// What apps reach when ``MetricKitSupport`` finds the OS incomplete: each must take its no-op
/// path. Every symbol exists on the test host, so a stray call wouldn't crash here; these prove
/// the gate picks the path, not that the path avoids every symbol.
@MainActor
@Suite struct MissingMetricKitTests {
    /// A real start would throw here: the test process has no iCloud container.
    @Test func startDoesNothing() async throws {
        try ShipPulseKit.start(Configuration(), isMetricKitAvailable: false)
        try ShipPulseKit.start(Configuration(), isMetricKitAvailable: false)
        await ShipPulseKit.flush()
    }

    @Test func screenReportsAreDropped() {
        let reporter = ScreenReporter(isMetricKitAvailable: false)
        #expect(!reporter.isReporting)
        reporter.report("Feed")
        reporter.report(nil)
    }

    #if canImport(MetricKit) && !os(watchOS) && !os(tvOS) && !os(visionOS)
    @Test func hitchIntervalNeverOpens() {
        let interval = HitchInterval(name: "Test", category: "Test", isMetricKitAvailable: false)
        #expect(!interval.isOpen)
        interval.end()
        interval.end()
    }

    @Test func hitchIntervalDroppedWithoutEndIsHarmless() {
        _ = HitchInterval(name: "Test", category: "Test", isMetricKitAvailable: false)
    }

    /// `start` left the engine nil, so the operation must run without a `MetricManager`.
    @Test func launchTaskRunsUntracked() async throws {
        try ShipPulseKit.start(Configuration(), isMetricKitAvailable: false)
        let result = await ShipPulseKit.trackLaunchTask("Test") { 42 }
        #expect(result == 42)
    }
    #endif
}

@MainActor
@Suite struct AvailableMetricKitTests {
    @Test func screenReporterReports() {
        #expect(ScreenReporter(isMetricKitAvailable: true).isReporting)
    }

    #if canImport(MetricKit) && !os(watchOS) && !os(tvOS) && !os(visionOS)
    @Test func hitchIntervalOpensAndEndsOnce() {
        let interval = HitchInterval(name: "Test", category: "Test", isMetricKitAvailable: true)
        #expect(interval.isOpen)
        interval.end()
        #expect(!interval.isOpen)
        interval.end()
    }
    #endif
}

#if os(macOS)
/// Reads the test binary, which links the SDK statically, the way dyld will see an app.
@Suite struct LinkedBinaryTests {
    private func imports() throws -> [(name: String, isWeak: Bool)] {
        var info = Dl_info()
        #expect(dladdr(#dsohandle, &info) != 0)
        let binary = String(cString: try #require(info.dli_fname))

        let nm = Process()
        nm.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        nm.arguments = ["nm", "-m", "-u", binary]
        let pipe = Pipe()
        nm.standardOutput = pipe
        try nm.run()
        let output = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        nm.waitUntilExit()
        #expect(nm.terminationStatus == 0)

        return output.split(separator: "\n").compactMap { line in
            guard line.hasSuffix("(from MetricKit)") || line.hasSuffix("(from StateReporting)") else { return nil }
            let words = line.split(separator: " ")
            guard words.count >= 3 else { return nil }
            return (String(words[words.count - 3].dropFirst()), line.contains(" weak "))
        }
    }

    /// One strong reference from any file makes the linker bind the symbol strongly, which
    /// brings back the launch crash on a system without it.
    @Test func everyMetricKitImportIsWeak() throws {
        let imports = try imports()
        #expect(!imports.isEmpty)
        #expect(imports.filter { !$0.isWeak }.map(\.name) == [])
    }

    /// An unlisted symbol would crash on null, because the gate wouldn't know to check it.
    /// `scripts/update-metrickit-symbols.sh` regenerates the list.
    @Test func gateChecksEveryImport() throws {
        let listed = Set(MetricKitSymbols.metricKit + MetricKitSymbols.stateReporting)
        #expect(try imports().map(\.name).filter { !listed.contains($0) } == [])
    }
}
#endif

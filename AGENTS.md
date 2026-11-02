# AGENTS.md

Guidance for coding agents (Claude Code, Codex and others) working in this repository.

## What this is

ShipPulseKit is a Swift package that third-party apps embed. It collects MetricKit metrics
and diagnostics plus anonymous retention signals, queues them on
disk, and uploads them to the **host app's own CloudKit container**. There is no server.

The [ShipPulse](https://github.com/ShawnBaek/ShipPulse) app reads those records.
`ShipPulseKitCore` is shared by both sides.

## Layout

```
Package.swift                 iOS / macOS / watchOS / visionOS 27+
Sources/ShipPulseKitCore/     Pure Swift, no Apple-UI or CloudKit: Schema, MetricSummary /
                              DailyReport, Histogram, Aggregation, Sampling.
                              Also imported by the ShipPulse app.
Sources/ShipPulseKit/         The SDK: Engine, MetricKitCollector, ReportMapper,
                              UploadQueue (offline-first), CloudKitUploader,
                              RetentionTracker, ScreenReporter, Hitches/*
Sources/ShipPulseKitObjC/     One function: catches the NSException CloudKit raises when the
                              host app has no iCloud entitlement.
CloudKit/ShipPulseKit.ckdb    Schema fragment, merged into each host container
docs/                         CloudKitSchema.md, HitchTracking.md
Sources/*/*.docc/             DocC landing pages (Product → Build Documentation in Xcode)
Tests/ShipPulseKitTests/      Swift Testing
```

## Commands

```bash
swift build
```

```bash
swift test
```

Validate the schema fragment against a real container. This is read-only, and requires
`xcrun cktool save-token` once:

```bash
xcrun cktool export-schema --team-id TEAMID --container-id CONTAINER --environment development --output-file current.ckdb && { cat current.ckdb; echo; sed '1d' CloudKit/ShipPulseKit.ckdb; } > merged.ckdb && xcrun cktool validate-schema --team-id TEAMID --container-id CONTAINER --environment development --file merged.ckdb
```

Never run `cktool import-schema` or `reset-schema` without explicit approval from the user.
Import replaces the whole schema of the target environment.

## Rules

1. **Never crash or block the host app.**
   - No `fatalError`, force unwraps on external data, or `try!` in `Sources/ShipPulseKit`.
   - Keep main-thread work tiny.
   - A missing iCloud container makes `start()` throw `ShipPulseKitError`; nothing else
     fails.
2. **Schema changes go in three places in one change:**
   - `CloudKit/ShipPulseKit.ckdb`
   - `Sources/ShipPulseKitCore/Schema.swift`
   - `docs/CloudKitSchema.md`

   Then revalidate with `cktool validate-schema`. Adding fields and types is safe. Renaming
   or removing them breaks every integrated app, so don't, unless the user asks and the
   `schemaVersion` is bumped.
3. **Record names stay deterministic.** Retries and redelivered reports must overwrite, not
   duplicate. Use `Sampling.stableHash` (FNV-1a), never `hashValue`, which is seeded per
   process.
4. **Offline first.** Write every record to `UploadQueue` before uploading, and remove it
   only after CloudKit accepts it.
5. **Record every MetricKit metric.**
   - When Apple adds a `MetricResult` case, map it in `ReportMapper.summary` with a
     `MetricKey`.
   - Normalize units: histograms in ms, totals in seconds, sizes in MB.
   - The raw report JSON is uploaded too, so unmapped metrics are never lost.
6. **Privacy is a feature.**
   - No app user data, IDFA, IDFV or network calls outside CloudKit.
   - Strip free-form runtime strings (exception messages and arguments) from diagnostics
     before upload; see `PayloadMapper.redactedDiagnosticJSON`.
   - CloudKit's `___createdBy` links records to an iCloud account; keep the docs honest
     about it.
   - `installID` stays a per-install random UUID in UserDefaults.
7. **Public API is a contract.**
   - Hitch region names are `StaticString`, because MetricKit requires it.
   - Keep entry points small: `start`, `flush`, `reportScreen`, `trackLaunchTask`, the hitch
     APIs, and the SwiftUI and UIKit extensions.
   - Update `README.md` when the API changes.
8. **Swift 6 strict concurrency.**
   - The compiler must prove every concurrency boundary. Don't use `@unchecked Sendable`,
     `nonisolated(unsafe)` or `@preconcurrency` to silence a diagnostic.
   - Prefer actors and `@MainActor`; use checked `Sendable` value types, `sending`
     parameters and results, and `@Sendable` closures to move values across isolation.
   - When a framework type isn't `Sendable` (for example `MetricManager`), keep it inside
     one actor or the main actor and pass only `Sendable` values out. For shared mutable
     state that can't live in an actor, use `Mutex` from `Synchronization`.
9. **Platform guards:** MetricKit is unavailable on watchOS and tvOS. On visionOS,
   `metricReports`, `MetricReport` and `logHandle(category:)` are unavailable, so metric
   mapping and `Hitches/*` also need `!os(visionOS)`. Build every platform before
   publishing: `xcodebuild build -scheme ShipPulseKit -destination generic/platform=visionOS`
   (and `iOS`, `watchOS`).
10. **Keep Core portable.** `ShipPulseKitCore` must not import MetricKit, CloudKit, UIKit or
    SwiftUI.

## Testing notes

- **Unit tests cover:** Core math (histogram merge and percentiles, aggregation, sampling),
  record mapping, the queue and retention. Add a test with every behavior change.
- **MetricKit needs a physical device.**
  - Reports arrive about daily; diagnostics arrive on the next launch.
  - Use Xcode's **Debug → Simulate MetricKit Payloads** on a device to exercise the pipeline.
- **CloudKit environments:** debug builds write to the Development environment.
  TestFlight and App Store builds need the schema deployed to Production.

## Style

- Match the surrounding code.
- Doc comments use DocC markup: a one-line summary, then discussion, then
  `- Parameters:`, `- Returns:` and `- Throws:`. Link symbols in the same module with
  ``` ``Symbol`` ```; use single backticks for other modules and Apple APIs. Put examples in
  fenced `swift` code blocks.
- Every `public` declaration has a doc comment. New public API also goes under
  **Topics** in the module's `.docc` landing page.
- Doc comments explain *why*. No narration comments.
- No new dependencies. The package depends only on Apple frameworks.

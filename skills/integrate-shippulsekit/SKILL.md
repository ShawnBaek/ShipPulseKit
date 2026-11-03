---
name: integrate-shippulsekit
description: Add ShipPulseKit to an iOS, macOS, watchOS or visionOS app, install its CloudKit schema, and check that records arrive. Use when someone asks to integrate ShipPulseKit, send MetricKit metrics or hitches to CloudKit with it, set up its CloudKit container or schema, or find out why ShipPulse shows no data.
---

# Integrate ShipPulseKit

ShipPulseKit collects MetricKit metrics, diagnostics and anonymous retention records and
uploads them to the **host app's own CloudKit container**. There is no server. Work through
the steps in order and stop at each **Ask** until the person answers.

Source of truth: the package's `README.md`, `docs/CloudKitSchema.md` and
`docs/HitchTracking.md`. When this skill and those files disagree, follow the files.

## 1. Read the app before changing anything

Collect these facts and show them to the person:

- **Targets:** every app target that should run the SDK (iOS, macOS, watchOS, visionOS),
  and its build configurations.
- **Bundle IDs per configuration:** a configuration with its own bundle ID (Beta, Staging)
  is a separate app to CloudKit.
- **Entitlements:** the `com.apple.developer.icloud-container-identifiers` array of each
  target. Resolve variables: `iCloud.$(CFBundleIdentifier)` becomes a different container
  for each bundle ID.
- **Existing CloudKit use:** Core Data or SwiftData sync, `CKContainer` calls, and which
  database each uses.
- **Launch entry point:** SwiftUI `App.init`, `application(_:didFinishLaunchingWithOptions:)`,
  or both (for example a UIKit iOS app plus a SwiftUI Mac app).
- **Test and preview guards:** how the app already detects UI tests, unit tests and SwiftUI
  previews.

## 2. Choose the container

**The app's existing container is fine and is the usual choice.** ShipPulseKit only adds
`SP`-prefixed record types to the public database (the default). It doesn't touch the app's
record types, records or private database, so Core Data and SwiftData sync keep working.

- **The app already has iCloud with CloudKit:** configure nothing. `ShipPulseKit.start()`
  without arguments uses the **first** container in the entitlements. Confirm that the first
  entry is the container you mean.
- **A separate container:** only when the person wants metrics kept apart, or the first
  entitlement entry is the wrong one. Add the container under **Signing & Capabilities →
  iCloud → CloudKit** on every target that runs the SDK, and pass it explicitly:
  `ShipPulseKit.start(Configuration(containerIdentifier: "iCloud.…"))`.
- **No iCloud yet:** add the iCloud capability with CloudKit and a container. This changes
  signing and the App ID. **Ask** first.

Keep the default `database: .public`. With `.private`, neither the developer nor the
ShipPulse app can read other users' records.

List every container that release builds will actually write to, one per bundle ID. Ask
which ones are in use; unused configurations can be skipped.

## 3. Add the package and start it

1. Add the package, then add the `ShipPulseKit` product to each target:

   ```swift
   .package(url: "https://github.com/ShawnBaek/ShipPulseKit.git", from: "0.2.0")
   ```

   Check the latest release tag first; tags are plain `major.minor.patch`.

2. Call `start()` **once**, early, behind the app's test and preview guards. A second call
   throws `alreadyStarted`. `start()` throws `ShipPulseKitError` only when there is no
   usable iCloud container; log the error and let the app keep running.

   ```swift
   // UIKit: application(_:didFinishLaunchingWithOptions:)
   if !isRunningTestsOrPreviews {
       do {
           try ShipPulseKit.start()
       } catch {
           logger.error("ShipPulseKit disabled: \(error.localizedDescription, privacy: .public)")
       }
   }
   ```

   ```swift
   // SwiftUI
   @main
   struct MyApp: App {
       init() {
           do { try ShipPulseKit.start() } catch { /* log; the app runs on without metrics */ }
       }
       var body: some Scene { WindowGroup { ContentView() } }
   }
   ```

   Don't use `try!`, force unwraps, or `fatalError` around the SDK.

## 4. Optional: screens, regions and launch work

Nothing here is required. Add it where the person cares about a specific screen or interaction.

- **Screens:**
  - UIKit view controllers are reported automatically
    (`tracksScreensAutomatically`, on by default).
  - In SwiftUI, add `.shipPulseScreen()` or `.shipPulseScreen("Name")` to top-level screens.
- **Hitch regions:**
  - Use the APIs in `docs/HitchTracking.md`, for example
    `.shipPulseScrollHitches("Feed")`, `collectionView.shipPulseTrackScrollHitches("Feed")`
    or `ShipPulseKit.withAnimation("CardFlip", .spring) { … }`.
  - Names are `StaticString`. Use one stable name per region, never per item.
- **Launch work:** wrap work the user waits on at launch in
  `await ShipPulseKit.trackLaunchTask("LoadFeed") { … }`. This API exists on iOS and
  macOS only.
  - Start the task early, at scene connection or in the first view's task, not after an
    intro animation. MetricKit ignores launch tasks that begin after the first scene is
    active.

## 5. Privacy declarations

Add these to the app's `PrivacyInfo.xcprivacy` and App Store privacy label:

- **Data types:** Performance Data and Crash Data.
- **Purposes:** App Functionality and Analytics.
- **Tracking:** not tracking.

CloudKit stamps each record with a container-scoped iCloud user record ID (`___createdBy`).
Whether to declare the data as linked to identity is the developer's policy decision. Point
them to the README's Privacy section, and **Ask** them to decide.

## 6. Install the CloudKit schema in Development

Records arrive only after the schema exists. Do this for each container from step 2.
`cktool import-schema` **replaces the whole environment schema**, so never import the
fragment by itself.

Prerequisites:
- Ask once for the team ID.
- `xcrun cktool save-token` must already be done by the person.

If the exported schema already has `SPMetricSummary` or `CREATE ROLE ShipPulseAdmin`, the
schema is already installed. Don't merge again, because that would duplicate it; compare the
existing `SP*` types with the package's `ShipPulseKit.ckdb` and report any differences to the
person instead.

1. **Back up and merge** (read-only):

   ```bash
   xcrun cktool export-schema --team-id TEAM --container-id CONTAINER --environment development --output-file backup.ckdb
   ```

   ```bash
   { cat backup.ckdb; echo; sed '1d' ShipPulseKit.ckdb; } > merged.ckdb
   ```

   Get `ShipPulseKit.ckdb` from the package's `CloudKit/` folder at the version the app uses.

2. **Validate** (read-only):

   ```bash
   xcrun cktool validate-schema --team-id TEAM --container-id CONTAINER --environment development --file merged.ckdb
   ```

3. **Check that the merge only adds.** `merged.ckdb` must start with every line of
   `backup.ckdb` unchanged. The additions must be exactly `CREATE ROLE ShipPulseAdmin` and
   the five `SP*` record types: `SPMetricSummary`, `SPDiagnosticPayload`, `SPInstall`,
   `SPActiveDay` and `SPConfig`.

4. **Ask** for approval to import. Name each container and environment, and state that the
   import replaces the Development schema with the merged file.

5. **Re-export right before importing.** If the result differs from `backup.ckdb`, someone
   changed the schema meanwhile: merge again rather than importing a stale file. Then import:

   ```bash
   xcrun cktool import-schema --team-id TEAM --container-id CONTAINER --environment development --file merged.ckdb
   ```

6. **Verify.** Export again and confirm:
   - the `SP*` types and the role are present;
   - no line from `backup.ckdb` is missing.

   Keep the backups and tell the person where they are.

Never run `cktool reset-schema`. Never import into Production.

## 7. Production deploy is the person's job

TestFlight and App Store builds write to **Production**. CloudKit never creates record types
there on its own, so a release build without the deployed schema uploads nothing. Records
wait on the device for up to 30 days (500 at most), then the oldest are dropped.

The person deploys in CloudKit Console: **container → Deploy Schema Changes**. Deploy ships
**every** pending Development change, not just ShipPulseKit's.

When the person pastes the Console diff, review it:
- It may contain only `+` lines: `CREATE ROLE ShipPulseAdmin`, the five `SP*` types, and the
  `Users` index from step 8 if it was added.
- Any `-` line, or a change to one of the app's own types, is a reason to stop and investigate.

Afterwards, confirm with a read-only export of the `production` environment.

## 8. Optional: the ShipPulseAdmin role

Collecting and reading work without this role. The developer needs it only to change
sampling rates (`SPConfig`) or delete old records. If they want it:

- **Not the Security Roles page:** that page only *defines* what the role may do. Its
  permissions already come from the schema; don't edit or save it.
- **Assign on the user record:** in each environment, open **Data → Records**, query `Users`
  in the public database, and add the role to the developer's own user record.
- **If the query fails:** `Users` lacks a queryable `recordName` index. Add it in
  Development and deploy it.
- **If the record is missing:** a user record exists only after that iCloud account has used
  the container in that environment.

## 9. Verify records arrive

- **Retention:** run a debug build on a device or simulator signed in to iCloud. Records go
  to **Development**. Check Console → Records → public database for `SPInstall` and
  `SPActiveDay` records.
- **Metrics and diagnostics:** these need a physical device.
  - MetricKit delivers reports about once a day, and diagnostics on the next launch.
  - To test sooner, use Xcode's **Debug → Simulate MetricKit Payloads**.
- **Nothing arrives:**
  - Check that the build writes to the environment where the schema is.
  - Check the container (step 2).
  - Check that the device is signed in to iCloud.
  - Check the app's log for the `start()` error.

## Report back

Finish with a short table, one row per container:

| Container | Bundle IDs | Development schema | Production schema |
| --- | --- | --- | --- |

Add the release builds that depend on the Production deploy, and anything not verified.

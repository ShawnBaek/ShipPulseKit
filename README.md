# ShipPulseKit

Drop-in Swift package that sends your app's MetricKit vitals, hitches, diagnostics and
anonymous retention to **your own CloudKit container**. There is no server.
[ShipPulse](https://github.com/ShawnBaek/ShipPulse) reads them, even for apps too small for
App Store Connect analytics.

**Pure MetricKit approach.** Every vital, including hitches, launch time, hangs and memory,
is measured by Apple's MetricKit, not by the SDK. ShipPulseKit adds no frame timers or
sampling of its own, so it costs nothing at runtime and its numbers match Xcode Organizer.
The SDK only forwards MetricKit reports, marks screens and regions for MetricKit to
attribute, and records anonymous retention.

Requires iOS, macOS, watchOS or visionOS 27+. Test on a physical device; MetricKit doesn't
report in the Simulator. visionOS has no daily metric reports, so it sends diagnostics and
retention only.

## Architecture

![ShipPulseKit architecture](docs/design/architecture.png)

- **Collectors** turn MetricKit reports and app launches into records.
- **Engine** samples the records and hands them to **DataContainer**, the only owner of
  on-device state: pending records and a few UserDefaults keys.
- **CloudKitUploader** saves pending records to your CloudKit container. A record leaves the
  device only after CloudKit accepts it.

Source: [docs/design/ShipPulseKit-Architecture.sketch](docs/design/ShipPulseKit-Architecture.sketch).
The `DataContainer` split shown here lands in the next release.

## 1. Enable CloudKit

1. In Xcode, open **Signing & Capabilities → + iCloud** and check **CloudKit**. Pick a
   container.
2. Add the ShipPulseKit record types to that container. See
   [docs/CloudKitSchema.md](docs/CloudKitSchema.md#installing-the-schema).
3. In CloudKit Console, assign the `ShipPulseAdmin` role to your iCloud user.
4. Before your first TestFlight or App Store build, deploy the schema to **Production**:
   CloudKit Console → your container → **Deploy Schema Changes**. Debug builds write to the
   Development environment; TestFlight and App Store builds write to Production. Until the
   schema is in Production, release builds keep records queued on the device and nothing
   arrives.

Without a container, `start()` throws `ShipPulseKitError.iCloudContainerUnavailable`. It never crashes your app.

## 2. Install

```swift
.package(url: "https://github.com/ShawnBaek/ShipPulseKit.git", from: "0.1.0")
```

## 3. Start

**SwiftUI**

```swift
@main
struct MyApp: App {
    init() {
        do { try ShipPulseKit.start() }
        catch { print(error.localizedDescription) }   // app runs on without metrics
    }
    var body: some Scene { WindowGroup { ContentView() } }
}
```

**UIKit**

```swift
func application(_ application: UIApplication,
                 didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
    do { try ShipPulseKit.start() } catch { print(error.localizedDescription) }
    return true
}
```

That's all you need. Every MetricKit metric and diagnostic is collected, along with
retention. UIKit screens are tracked automatically.

## Optional: screens and regions

```swift
FeedView().shipPulseScreen()                       // per-screen metrics, named after the file

List(photos) { PhotoRow($0) }
    .shipPulseScrollHitches("PhotoFeed")           // SwiftUI: hitch time while scrolling

collectionView.shipPulseTrackScrollHitches("PhotoFeed")   // UIKit

ShipPulseKit.withAnimation("CardFlip", .spring) { flipped.toggle() }
```

More APIs: [docs/HitchTracking.md](docs/HitchTracking.md).

## Custom CloudKit

```swift
try ShipPulseKit.start(Configuration(
    containerIdentifier: "iCloud.com.example.metrics", // default: first container in entitlements
    database: .public                                  // .private = your own devices only
))
```

With `.private`, records stay in each user's own iCloud, so neither you nor the ShipPulse
app can read other users' data; dashboards and benchmarks need `.public`.

Other options: `sampling`, `collectsDiagnostics`, `tracksRetention`,
`automaticScreenTracking`.

## Data format

Each device sends one `SPMetricSummary` per day. Its `summary` field is zlib-compressed JSON:

```json
{
  "schemaVersion": 1,
  "overall": {
    "histograms": { "timeToFirstDraw": { "buckets": [{ "start": 0, "end": 500, "count": 41 }] } },
    "values": { "hitchTime.ratio": 0.0041, "peakMemory.mb": 182.4 },
    "counts": { "foregroundTermination.watchdog": 0 }
  },
  "states": [
    { "domain": "shippulse.screen", "label": "Feed/FeedView.swift",
      "metrics": { "values": { "hitchTime.ratio": 0.0072 } } }
  ]
}
```

Other record types: `SPDiagnosticPayload` (crash, hang and launch call stacks),
`SPInstall` and `SPActiveDay` (retention). Full field
list: [docs/CloudKitSchema.md](docs/CloudKitSchema.md).

## Samples

`Examples/SwiftUISample` and `Examples/UIKitSample` show the same flow: launch tracking, a
home list, a photo grid (collection view) and a photo list (table view), each with screen and
hitch measurement. Open the sample's `.xcodeproj`, set your team, and run it on a device.

## Privacy

The SDK sends no IDFA, IDFV or app user data, and makes no network calls outside CloudKit.
Diagnostics are sent without Objective-C exception messages or arguments, which could
contain user data.

Records go to your container's public database, readable by any client of that container.
CloudKit stamps each record with the creator's container-scoped user record ID
(`___createdBy`), which links records from one iCloud account. For the privacy label,
declare *Diagnostics → Performance Data* and *Crash Data*, used for app functionality and
analytics, not for tracking. Whether you also mark them linked to identity depends on your
own policy; see [docs/CloudKitSchema.md](docs/CloudKitSchema.md#privacy).

## License

Apache-2.0

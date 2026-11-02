# Measuring hitches

There are three levels. Most apps only need the first.

## Level 1: one line at app entry (default)

```swift
// SwiftUI
@main struct MyApp: App {
    init() { try? ShipPulseKit.start() }
    var body: some Scene { WindowGroup { ContentView() } }
}

// UIKit: AppDelegate
func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
    try? ShipPulseKit.start()
    return true
}
```

You get, with no other code:

- **App-wide hitches from MetricKit:** hitch ratio, hitch time and animation time for
  everything Apple tracks by default (scrolling and system animations).
- **Per-screen hitches in UIKit:** every content view controller is reported as a screen
  when it appears (`tracksScreensAutomatically`, on by default). A `UIHostingController` is
  named after its root SwiftUI view.

## Level 2: name your SwiftUI screens (one modifier each)

```swift
FeedView().shipPulseScreen()            // named after the file: "Feed/FeedView.swift"
CheckoutView().shipPulseScreen("Checkout")
```

MetricKit then breaks every metric down by screen, including hitches, hangs and memory.
This is as close as MetricKit gets to "which file hitched". Apple reports no call stack or
source location for hitches.

## Level 3: measure a specific region

| Where | API |
| --- | --- |
| Any code | `let i = ShipPulseKit.beginHitchInterval("PhotoGrid")` … `i.end()` |
| Async work | `try await ShipPulseKit.measureHitches("LoadFeed") { … }` |
| SwiftUI animation | `ShipPulseKit.withAnimation("CardFlip", .spring) { flipped.toggle() }` |
| SwiftUI while visible | `.shipPulseHitches("MapOverlay")` |
| SwiftUI while scrolling | `List { … }.shipPulseScrollHitches("FeedScroll")` |
| UIKit animation | `UIView.shipPulseAnimate("Expand", withDuration: 0.3) { … }` |
| UIKit property animator | `animator.shipPulseTrackHitches("Sheet")` |
| UIKit scroll view | `collectionView.shipPulseTrackScrollHitches("Feed")` (delegate untouched) |

Each region is a MetricKit animation signpost. MetricKit then reports hitch time, hitch
ratio and the number of times the region ran for that name, in the daily
`SignpostIntervalMetric`. All measurement is MetricKit's own, so a region adds no runtime
cost.

Names are `StaticString` because MetricKit signposts require compile-time names. Use a
stable name per region, not per item.

MetricKit reports hitch time and ratio, not a count of individual hitches. Apple's
recommended hitch metric is the time ratio (ms of hitch per second of animation), because
one 200 ms hitch and ten 20 ms hitches have the same total but feel different.

# ``ShipPulseKit``

Record every MetricKit metric and diagnostic in your own CloudKit container, with one line.

## Overview

ShipPulseKit measures nothing itself: no frame timers or sampling of the render loop.
Hitches, hangs, launch time, memory and every other metric come from Apple's daily MetricKit
reports, broken down by screen. Records are written to disk first and uploaded to your app's
CloudKit container, where the ShipPulse app reads them. There is no server.

visionOS has no daily metric reports, so it sends diagnostics and retention only. watchOS
has no MetricKit, so it sends retention only.

```swift
do {
    try ShipPulseKit.start()
} catch {
    print(error.localizedDescription)
}
```

Enable **Signing & Capabilities → iCloud → CloudKit** with a container before calling
``ShipPulseKit/ShipPulseKit/start(_:)``. Without a usable container it throws
``ShipPulseKitError`` with code ``ShipPulseKitError/Code/iCloudContainerUnavailable`` instead of
crashing, and the app runs on without metrics.

### Screens

UIKit screens are tracked automatically: ShipPulseKit swizzles
`UIViewController.viewDidAppear(_:)` to report each content view controller's class name to
StateReporting. Set ``Configuration/automaticScreenTracking`` to `false` to turn it off.
SwiftUI screens use `shipPulseScreen(_:fileID:)`.

### Records and privacy

By default records go to the container's public database. With
``Configuration/Database/private`` they go to each user's own private database, which you
can't read. Records the device can't upload yet stay on disk for
``Configuration/maxQueueAge`` (30 days by default), up to ``Configuration/maxQueuedRecords``
(500).

## Topics

### Starting

- ``ShipPulseKit/ShipPulseKit/start(_:)``
- ``Configuration``
- ``SamplingMode``
- ``ShipPulseKitError``

### Screens and launch

- ``ShipPulseKit/ShipPulseKit/reportScreen(_:)``
- ``ShipPulseKit/ShipPulseKit/trackLaunchTask(_:_:)``

### Hitch regions

The hitch APIs exist on iOS and macOS only; the UIKit ones on iOS only. watchOS and
visionOS have no MetricKit animation signposts, so these symbols aren't compiled there.

- ``ShipPulseKit/ShipPulseKit/beginHitchInterval(_:category:)``
- ``ShipPulseKit/ShipPulseKit/measureHitches(_:category:_:)``
- ``ShipPulseKit/ShipPulseKit/withAnimation(_:_:category:_:)``
- ``HitchInterval``

### Delivery

- ``ShipPulseKit/ShipPulseKit/flush()``

# ``ShipPulseKit``

Record every MetricKit metric and diagnostic in your own CloudKit container, with one line.

## Overview

ShipPulseKit uses MetricKit only: no frame timers, no swizzled render loops. Hitches,
hangs, launch time, memory and every other metric come from Apple's daily reports, broken
down by screen. Records are written to disk first and uploaded to your app's CloudKit
container, where the ShipPulse app reads them. There is no server.

```swift
do {
    try ShipPulseKit.start()
} catch {
    print(error.localizedDescription)
}
```

Enable **Signing & Capabilities → iCloud → CloudKit** with a container before calling
``ShipPulseKit/ShipPulseKit/start(_:)``.

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

- ``ShipPulseKit/ShipPulseKit/beginHitchInterval(_:category:)``
- ``ShipPulseKit/ShipPulseKit/measureHitches(_:category:_:)``
- ``ShipPulseKit/ShipPulseKit/withAnimation(_:_:category:_:)``
- ``HitchInterval``

### Delivery

- ``ShipPulseKit/ShipPulseKit/flush()``

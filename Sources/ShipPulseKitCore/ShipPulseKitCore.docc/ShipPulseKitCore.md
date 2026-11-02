# ``ShipPulseKitCore``

The record schema and aggregation math shared by ShipPulseKit and the ShipPulse app.

## Overview

ShipPulseKit writes ``DailyReport`` values into CloudKit, and the ShipPulse app reads them
back and merges many devices with ``Aggregation``. This module imports only Foundation, so
both sides compile the same definitions.

## Topics

### Records

- ``Schema``
- ``DailyReport``
- ``MetricSummary``
- ``StateSummary``
- ``SignpostSummary``

### Metrics

- ``Metric``
- ``MetricKey``
- ``ForegroundTerminationReason``
- ``BackgroundTerminationReason``
- ``LocationAccuracy``
- ``Histogram``

### Aggregation and sampling

- ``Aggregation``
- ``GroupAggregate``
- ``Sampling``

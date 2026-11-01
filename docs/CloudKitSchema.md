# CloudKit schema

ShipPulseKit writes to the **public database of a container you own**. The ShipPulse app
reads the same records. There is no ShipPulse server.

The schema source is [`CloudKit/ShipPulseKit.ckdb`](../CloudKit/ShipPulseKit.ckdb).

## Record types

All types carry the same context fields: `bundleID`, `appVersion`, `build`, `osVersion` and
`device` (model identifier, for example `iPhone17,1`). Every uploaded record also carries
`sampleRate`.

| Type | One record per | Written by | Purpose |
| --- | --- | --- | --- |
| `SPMetricSummary` | install × MetricKit report (about a day) | SDK | **Every** MetricKit metric: `summary` holds a `DailyReport` (all 30 iOS 27 metric types flattened into histograms, values, counts and signposts, plus a per-screen breakdown); `report` holds the raw MetricKit JSON (zlib). Both are compressed; together they are a few KB |
| `SPDiagnosticPayload` | diagnostic | SDK | One crash, hang, app-launch, CPU, disk-write or memory diagnostic with call stacks (`payload`, zlib JSON). `kind`, `durationMs`, `terminationCategory`, `signal` and `exceptionType` are queryable |
| `SPInstall` | install | SDK | `installID`, `firstLaunch`; denominator for retention cohorts |
| `SPActiveDay` | install × UTC day opened | SDK | `day`, `daysSinceInstall`; numerator for Dn retention |
| `SPConfig` | app (`config-<bundleID>`) | ShipPulse app | `sampleRate`, `diagnosticSampleRate` the SDK reads once a day |

### Record names are deterministic

Retries and redelivered payloads overwrite the existing record instead of duplicating it.

- `summary-<installID>-<windowStart>`
- `diagnostic-<bundleID>-<build>-<kind>-<hash>`, where `<hash>` is the FNV-1a hash of the
  redacted, key-sorted diagnostic JSON
- `install-<installID>`
- `active-<installID>-<yyyy-MM-dd>`

## How ShipPulse reads it

| Question | Query |
| --- | --- |
| Vitals by device model for a build | `SPMetricSummary` where `bundleID == X AND build == B AND timeBegin >= D`, then merge histograms per `device` (`Aggregation.byDeviceModel` in ShipPulseKitCore) |
| New records since last sync | any type where `bundleID == X AND ___modTime > lastSync`, sorted by `___modTime` |
| Dn retention | cohort = `SPInstall.firstLaunch` day; retained = `SPActiveDay` with `daysSinceInstall == n`; each count scaled by `1 / sampleRate` |
| Crash and hang trends | `SPDiagnosticPayload` where `bundleID == X AND kind == "crash" AND timeBegin >= D`; decode `payload` only for stacks |
| Hitches, hangs and memory by screen | decode `summary.states` where `domain == "shippulse.screen"`, then `Aggregation.byState` |
| Exclude TestFlight devices | add `isTestFlight == 0` to any query |

Fields used in filters are `QUERYABLE`, and fields used for ordering are `SORTABLE`.
`___recordID` is `QUERYABLE` because CloudKit refuses queries on a type without that index.

## Volume and sampling

Each install sends about one `SPMetricSummary` (a few KB compressed) and one `SPActiveDay`
per day.

For large apps, ShipPulse writes `SPConfig.sampleRate` so that the largest device-model
group keeps about 300 reporting installs (`Sampling.recommendedRate`). Sampling is
deterministic per install, so the same devices keep reporting and cohorts stay intact.
Small apps keep `sampleRate = 1`, which means every install reports.

## Permissions

| Role | Grant | Why |
| --- | --- | --- |
| `_icloud` | CREATE on SDK types | Any device signed in to iCloud can add its own records. Devices without iCloud keep records queued until they sign in |
| `_creator` | WRITE on SDK types | A device can overwrite only its own records (retries) |
| `_world` | READ | Lets ShipPulse read with a CloudKit Web Services API token from your container. Only your apps and holders of your token can read |
| `ShipPulseAdmin` | CREATE and WRITE on `SPConfig`; WRITE on SDK types | Your own iCloud user: publishes sampling rates and deletes old records. Nobody else can change `SPConfig` |

## Requirements

ShipPulseKit targets iOS, macOS, watchOS and visionOS 27 or later. It uses MetricKit's
Swift `MetricManager` (async report streams) and StateReporting for per-screen attribution.
watchOS has no MetricKit, so it sends only retention records.

## Installing the schema

`cktool import-schema` **replaces** the environment's whole schema, so merge first:

```bash
xcrun cktool export-schema --team-id TEAM --container-id iCloud.com.you.app --environment development --output-file current.ckdb
```

```bash
{ cat current.ckdb; echo; sed '1d' ShipPulseKit.ckdb; } > merged.ckdb
```

```bash
xcrun cktool validate-schema --team-id TEAM --container-id iCloud.com.you.app --environment development --file merged.ckdb
```

```bash
xcrun cktool import-schema --team-id TEAM --container-id iCloud.com.you.app --environment development --file merged.ckdb
```

Then:

1. In CloudKit Console, open **Security Roles** and assign `ShipPulseAdmin` to your iCloud user.
2. Before your first TestFlight or App Store build, deploy the schema to **Production** in
   CloudKit Console (**Deploy Schema Changes**). Release builds write to Production; until
   the schema is there, their records stay queued on the device.

## Privacy

- **What the SDK sends:** no IDFV, IDFA or app user data. `installID` is a random UUID per
  app install, stored in UserDefaults. It is never shared across apps and is reset when the
  app is deleted. Diagnostic JSON has Objective-C exception `composedMessage` and
  `arguments` removed, because they can hold runtime strings with user data.
- **What CloudKit adds:** every record carries `___createdBy`, the creator's
  container-scoped user record ID. It is stable across reinstalls, so it links all records
  from one iCloud account, including diagnostics. Public-database records are readable by
  any client of the container (`_world` READ).
- **Privacy label:** declare *Diagnostics → Performance Data* and *Crash Data*, not used for
  tracking. Because of `___createdBy`, decide with your own policy whether they count as
  linked to identity.
- **No deletion by default:** CloudKit has no automatic expiry. ShipPulse prunes records
  older than the retention window you choose, which is why the admin role has WRITE.

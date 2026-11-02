# Schema evolution

How ShipPulseKit changes its data format without breaking apps that already ship it.

Three facts shape every decision here:

1. **The schema lives in every host app's container.** Each developer deploys
   `CloudKit/ShipPulseKit.ckdb` into their own container, on their own schedule.
2. **Production schema is add-only.** Once a record type or field is deployed to Production,
   it can't be renamed, removed or retyped.
3. **Old SDK versions keep writing for years.** Users who never update an app keep sending
   records in the format of the SDK version it shipped with.

So there is no "migration" in place. The format only ever grows, and readers understand every
version that was ever written.

## 1. Prefer changes inside the summary JSON

Most data lives in the zlib-compressed JSON of `SPMetricSummary.summary` (a `DailyReport`),
versioned by `DailyReport.schemaVersion`. A new metric or a new structure goes inside that
JSON, so CloudKit sees no schema change and nobody has to deploy anything.

- New metric keys are new `MetricKey` cases. Readers built before the key existed decode it
  as `MetricKey.unknown(_:)` instead of failing.
- New optional properties on `DailyReport` and its parts decode as `nil` from older records.
- Bump `DailyReport.currentSchemaVersion` only when the meaning of existing data changes, not
  when something is added.

Add a CloudKit field only when the ShipPulse app has to **query** on it (filter or sort).

## 2. When a CloudKit change is unavoidable, only add

- Add the new field or record type. Never delete, rename or retype a deployed one.
- To "rename" a field, add the new one, write **both** for at least one minor release, and
  have readers prefer the new field and fall back to the old one.
- Mark retired fields as deprecated in `docs/CloudKitSchema.md`; they stay in the schema.
- Every change still goes into the three files of AGENTS.md rule 2 in one commit, and is
  validated with `cktool validate-schema` against the Development environment.

## 3. Don't write a field before the container has it

Saving a record with a field that isn't in the Production schema fails, so an app that updates
the SDK before deploying the new schema would queue records that can never upload until they
are pruned.

Planned guard (not built yet): the ShipPulse app writes the deployed schema version into the
app's `SPConfig` record (for example `deployedSchemaVersion`). The SDK writes fields newer than
that version only when the container reports it, and otherwise writes the previous format.

Until the guard exists, release notes for a schema-changing version must say **"deploy the
schema to Production before shipping this version."**

## 4. Readers accept every version (migrate on read)

- The ShipPulse app should decode each schema version it may find and convert it into one
  current model in its data layer, so aggregation and UI only see that model.
- If a metric's definition changes, the app can re-derive it from the raw MetricKit report
  JSON, which is uploaded with a summary whenever MetricKit could encode it.
- Keep one golden JSON fixture per schema version in `Tests/ShipPulseKitTests` (today the
  version 1 fixture is in `CoreTests.swift`), and require that each keeps decoding.

## 5. On-device data

- **Pending records** (the JSON files `DataContainer` keeps until upload) may have been written
  by an older SDK version. `PendingRecord` decoding must tolerate older shapes: new properties
  are optional or have defaults. Add a test with an old fixture when the shape changes.
- **UserDefaults keys** never change name; see `DataContainer`.
- **The pending-record directory** stays `Application Support/ShipPulseKit/Queue`, so records
  queued before an update still upload.

## 6. Release checklist for a schema change

1. Update `CloudKit/ShipPulseKit.ckdb`, `Sources/ShipPulseKitCore/Schema.swift` and
   `docs/CloudKitSchema.md` together.
2. `cktool validate-schema` against Development (AGENTS.md has the command). Never run
   `import-schema` or `reset-schema` without the user's approval.
3. Bump the minor version before 1.0, the major version after. Tags stay plain
   `major.minor.patch` (AGENTS.md rule 11).
4. Release notes give the deploy steps and the "deploy before shipping" warning.
5. Deploy to Production in the maintainers' own apps before tagging.

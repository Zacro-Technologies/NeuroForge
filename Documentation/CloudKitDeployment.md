# CloudKit deployment checklist

NeuroForge uses the private CloudKit database in
`iCloud.com.zacrotech.NeuroForge`. The structured SwiftData store synchronizes
durable learning data; derived caches stay in a separate local-only store. The
custom `NeuroForgePrivateDocumentsV1` zone synchronizes imported document
originals with the record types `NFDocumentOriginalAsset`,
`NFDocumentOriginalLink`, and `NFDocumentOriginalTombstone`.

The following Apple Developer configuration is required before a signed build
can use this code:

1. Under team `34NS8XN5F9`, register the iCloud container
   `iCloud.com.zacrotech.NeuroForge` if it does not exist.
2. Edit explicit App ID `com.zacrotech.NeuroForge` (`K2BVT78TQ7`). Enable
   iCloud with CloudKit support and associate only that container.
3. Enable Push Notifications for the App ID. Give the iOS and macOS products
   their platform-appropriate APS entitlement (`aps-environment` on iOS and
   `com.apple.developer.aps-environment` on macOS), using `development` for
   development profiles and `production` for distribution profiles.
4. Regenerate and install every affected Development and App Store Connect
   provisioning profile after changing capabilities. Confirm the embedded
   profile grants the CloudKit container, CloudKit service, and APS environment
   requested by the signed app.
5. Run the development-signed, nonshipping schema bootstrap described below.
   First use Core Data's supported CloudKit schema initializer for exactly the
   nine durable SwiftData models, then save and delete saturated representative
   records for the three custom document types through the production codec.
6. Inspect every pending Development type, field, encryption setting, index,
   and role in CloudKit Console. Deploy the reviewed whole-container schema to
   Production before TestFlight/App Store testing. Promotion is a separate,
   additive and irreversible Apple-console operation; compiling or uploading
   the app does not perform it and does not copy Development records.

## Development schema bootstrap

Use a one-off Debug launch argument or a dedicated development utility that is
excluded from Archive. It must run before NeuroForge opens any normal
`ModelContainer`, print an unambiguous success/failure marker, and be removed
from the source after the successful bootstrap.

For the SwiftData-managed portion, build an `NSManagedObjectModel` with
`NSManagedObjectModel.makeManagedObjectModel(for:)` from only
`NFPersistentStoreLocation.durableModels`, attach a scratch store to an
`NSPersistentCloudKitContainer` configured for
`iCloud.com.zacrotech.NeuroForge`, and run
`initializeCloudKitSchema(options: [.dryRun, .printSchema])` before the actual
`initializeCloudKitSchema(options: [.printSchema])`. Remove the persistent
store from its coordinator before deleting the scratch store. Never let this
Core Data bridge and SwiftData own the same store URL at the same time.

The nine required managed models are:

- `UserProfileRecord`
- `ProgressAnnotationRecord`
- `AttemptRecord`
- `AttemptReflectionRecord`
- `WeeklyTransferStateRecord`
- `ReassessmentStateRecord`
- `SessionCheckpointRecord`
- `DailyPlanRecord`
- `ItemReportRecord`

Do not initialize `InputCalibrationRecord`, `SourceDocumentRecord`,
`SourceChunkRecord`, or `AIGenerationRecord`; they are intentionally local-only.
Their `CD_` record types must be absent from the Development and Production
schemas.

For the custom zone, use `NFPrivateDocumentCloudRecordCodec` rather than
manually duplicating its keys. In Development, create the
`NeuroForgePrivateDocumentsV1` zone, save one fully populated
`NFDocumentOriginalAsset`, then its `NFDocumentOriginalLink`, then a fully
populated `NFDocumentOriginalTombstone`. Assert each record's keys exactly match
the codec manifest, then delete only those three representative records in
link/tombstone/asset order; retain the zone. This saturates optional fields such
as `pccConsentedAt` and tombstone `contentHash` without shipping dummy data.

Before promotion, verify all 12 required record types and the encrypted fields
covered by `PrivateCloudTransportTests`. CloudKit cannot convert an existing
unencrypted field to encrypted. If Development contains accidental types or
wrong fields, reset it only when Production is still empty and only after an
explicit destructive confirmation; a Development reset deletes Development
data and schema. Never reset or attempt destructive schema edits after those
fields exist in Production.

Before release, test two signed devices on the same iCloud account: edits in
both directions, offline queue/retry, an unavailable or signed-out iCloud
account, private-original upload/download/delete, and an iCloud account switch.
An unavailable service must leave the existing local store and imported files
intact. Before a CloudKit-backed SwiftData store opens, NeuroForge must resolve
the current private-database user and select that account's isolated durable
store namespace. The raw CloudKit user record name must never be persisted or
logged. An account switch must quarantine the prior mirror, disable both sync
paths, and require an explicit user choice before any local records or originals
can be copied into the new account. Never attach one account's SQLite store,
persistent history, or CloudKit metadata to another account.

The app's effective entitlement files are platform-specific:

- iOS/iPadOS: `Sources/Resources/NeuroForgeTestFlight.entitlements`
- macOS: `Sources/Resources/NeuroForgeMac.entitlements`

Debug signing substitutes the Development CloudKit/APS environments. Release
signing substitutes Production. NeuroForge does not request a native Private
Cloud Compute entitlement; AI authoring uses the separately installed Apple
Intelligence Shortcut.

The macOS entitlement file also enables App Sandbox, outbound network access,
and read access to files the person selects in the system importer. App Sandbox
is required for Mac App Store distribution; verify both security-scoped import
and sharing of app-owned exports in the signed macOS build.

Useful verification commands for an archived product are:

```sh
codesign -d --entitlements :- Payload/NeuroForge.app
security cms -D -i Payload/NeuroForge.app/embedded.mobileprovision
```

The signed app and embedded profile must agree on the CloudKit container and
APS environment. Also verify the CloudKit environment in the signed
entitlements, not only the source plist. TestFlight uses the Production
CloudKit environment.

Do not describe complete private-iCloud deletion as verified from a generic
SwiftData export event. `NSPersistentCloudKitContainer` events don't identify
the records in the exported transaction. NeuroForge uses an automatic
two-launch transaction instead. The first launch durably binds the request and
the non-destructive local-purge intent to the current one-way account
fingerprint, the entitled container, and the active store identity; it then
freezes both private-sync paths and asks the person to reopen the app. The
second launch runs before any ModelContainer exists. It targets only the
allowlisted `com.apple.coredata.cloudkit.zone` and
`NeuroForgePrivateDocumentsV1` private zones, persists each result, reads back
both exact zone IDs, and accepts only `zoneNotFound` or confirmed omission as
absence. Network, authentication, account-change, and partial-failure results
remain unfinished on a blocking retry screen with the existing local data
untouched at the remote boundary.

Only after both remote zones are verified absent does that same second launch
remove and verify the app's local stores and sidecars, imported copies,
account-scoped document queue/cache, AI caches, prepared exports and protected
store-recovery packages, widget snapshot, Spotlight domain, managed
notifications, background requests, shortcut handoff, onboarding draft, and
other explicitly allowlisted preferences. A durable cleanup ledger makes every
step idempotent across crashes. The cloud request and deletion lock are cleared
only after all local surfaces are verified; the app then opens a fresh
local-only store and shows one success acknowledgement. There is no Settings
"finish deletion" step and no generic SwiftData event is accepted as proof.

Apple references:

- https://developer.apple.com/documentation/xcode/configuring-icloud-services
- https://developer.apple.com/documentation/cloudkit/enabling-cloudkit-in-your-app
- https://developer.apple.com/documentation/swiftdata/syncing-model-data-across-a-persons-devices
- https://developer.apple.com/documentation/coredata/nspersistentcloudkitcontainer/initializecloudkitschema(options:)
- https://developer.apple.com/documentation/cloudkit/deploying-an-icloud-container-s-schema
- https://developer.apple.com/documentation/cloudkit/integrating-a-text-based-schema-into-your-workflow
- https://developer.apple.com/documentation/technotes/tn3163-understanding-the-synchronization-of-nspersistentcloudkitcontainer
- https://developer.apple.com/documentation/cloudkit/cksyncengineaccountchangetype/switchaccounts
- https://developer.apple.com/documentation/cloudkit/responding-to-requests-to-delete-data

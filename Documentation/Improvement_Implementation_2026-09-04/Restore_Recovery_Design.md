# Durable multi-store restore recovery design

Date: 2026-09-05. Status: **live integration design; journal/startup building blocks implemented, execution pending**.

Current implementation and its limits are recorded in [Restore_Journal_Status.md](Restore_Journal_Status.md). The remaining live flow below is a design, not a claim of delivered crash recovery.

This document specifies the remaining engineering work for MIG-007. The current immutable `NFPreparedDataArchive` and asynchronous bounded decoder prevent file substitution after preview and keep decoding off the UI actor. They do not establish crash atomicity across the application's stores. The new journal/startup building blocks do not yet replace that live restore path or complete MIG-007.

## Requirement and current boundaries

[MIG-007](../Improvement_Spec_2026-09-04/04_Runtime_Data_and_Migration.md#mig-007) requires validated staging, explicit deterministic merge policy, preservation of originals, idempotent application, file/reference verification, and a retained recoverable transaction when materialization fails. Imported runs initially remain suspended or read-only; decoding is not writer authority.

The current restore touches these distinct persistence domains:

| Domain | Current implementation | Consequence |
| --- | --- | --- |
| Durable structured database | `NFPersistentStoreLocation.durableModels` / `NeuroForgeDurable` configuration | May also have CloudKit transport. |
| Local-derived structured database | `localOnlyModels` / `NeuroForgeLocalOnly` configuration | A second database, even when both are used through one `ModelContext`. |
| Local learning | `NFLocalSessionRepository` | Account-scoped archive, publication lock and revision checks; contains private snapshots, runs, dispositions and corrections. |
| Adaptive history | `NFAdaptivePlanHistoryRepository` | Independent atomic file; default path is currently shared rather than account-namespaced. |
| Source and recovery files | Managed document paths, private diagnostic/recovery artifacts | Original PDF/image formatting is not embedded in the JSON archive. Shared paths require a shared-surface fence. |

`NFDataArchiveRestoreService.restore` currently writes adaptive history first, changes models, imports local learning, then saves the model context. Its predecessors exist only in memory. A process exit can leave these domains at different revisions. A successful save followed by a thrown error or interrupted phase publication cannot be repaired by `context.rollback()`.

There are two important startup constraints:

- `NFAppStartupController.startIfNeeded` currently opens the container and then constructs `AppStore` before publishing the runtime.
- `AppStore.init` calls `reload()` and `refreshReassessmentSchedule()`. `reload()` itself can migrate records, save redacted diagnostics, merge state and write historical corrections. Recovery gating after that initializer is too late.

`deleteAllModelRecords` currently uses AppStore's selected/deduplicated arrays. A restore plan must inspect complete raw database records; a selected winner is not a complete census of stored identities.

Current-source follow-up: raw destination census and crossed-identity protection are now implemented, with integrated verification pending; see [Raw_Restore_Census_Status.md](Raw_Restore_Census_Status.md). These checks do not implement the transaction described below.

## Transaction model

Use a durable **forward-recovery transaction**. Once live mutation may have started, retain the accepted plan and reconcile it to completion. Do not attempt an unverified reverse restore, and do not announce that a saved database was rolled back.

Illustrative interfaces, not declarations already present in the app:

```swift
struct NFRestoreAcceptedPlan: Codable, Sendable {
    let transactionID: UUID
    let journalVersion: Int
    let namespace: String
    let installationOwnerID: UUID
    let sourceDigest: String
    let stagedPayloadDigest: String
    let acceptedPolicy: NFDataArchiveRestorePolicy
    let affectedRecords: [NFRestoreRecordOperation]
    let fileOperations: [NFRestoreFileOperation]
    let previewCounts: NFDataArchiveRecordCounts
}

@MainActor
func accept(
    prepared: NFPreparedDataArchive,
    previewRevision: String,
    policy: NFDataArchiveRestorePolicy
) async throws -> NFRestoreTransactionID

@MainActor
func resume(
    transactionID: NFRestoreTransactionID,
    context: ModelContext
) async -> NFRestoreRecoveryOutcome

func inspectPendingRestore(namespace: String) throws -> NFRestoreStartupGate
```

Each record operation stores:

- Database domain, entity type and stable logical identity.
- The complete accepted before-state, its digest and its multiplicity. Where the database has duplicate logical identities, record the entire raw group; do not silently choose a winner. An ambiguity that cannot be represented safely blocks acceptance.
- The exact desired after-state payload/digest, or an explicit absence for deletion.
- The fixed action: insert, replace, delete or leave unchanged.
- Referenced identities used during validation.

Canonical field encoding must be versioned and preserve raw original payload fields. A portable archive is **not** a sufficient predecessor backup: it deliberately redacts protected/private content. Temporary database identifiers must not be mistaken for stable cross-launch identities.

The source file digest and staged payload digest are different concepts. `NFPreparedDataArchive` already retains a validated value, not the original file bytes. Stage a canonical, permitted encoding of that exact value and record its own digest. Retain the original source digest as provenance. Do not reread the external URL after acceptance or claim that normalization preserves its original byte digest.

## Fixed merge decisions

The accepted policy is stored with the transaction. Replay never asks the current store what the original policy would do now.

| Policy | Accepted operation set |
| --- | --- |
| Abort on conflict | Abort before acceptance if the reviewed state has a conflict; otherwise freeze inserts. |
| Keep existing | Freeze exact insert/skip decisions and the identities/digests that caused each skip. |
| Replace matching | Freeze matching identity groups and their specific replacements. |
| Replace all | Freeze the identities present at acceptance and their replacements/deletions. Never repeat an unbounded delete-all query during replay. |

A record arriving after acceptance, outside the affected identity set, survives. If it creates a reference to a record the plan would delete, recovery stops with a conflict instead of expanding the deletion set. A changed value under an already affected identity is a third state that also stops recovery. The stored count/result receipt is based on accepted operations, so retries do not increase the reported restored count or create repeated correction notices.

## Execution and startup order

1. **Prepare without live mutation.** Decode, bound and hash immutable values off the main actor. Populate an isolated staging container and sandboxed local repository without constructing an ordinary AppStore. Validate the prospective merged state, schemas, hashes, references, privacy scope, imported-run recovery classification and size limits. Use disposable roots and no integrations.
2. **Acquire the write fence.** End active session ownership safely, settle dirty editors and queued attempt writes, stop authoring and integrations, and exclude other writers. Ordinary mutation paths need the same gate; disabling a screen alone is insufficient. Recheck the preview revision against fresh raw records. If the reviewed conflict set changed, produce an updated preview rather than silently accepting new destructive work.
3. **Stage durable intent.** Write a bounded private transaction directory with payload, raw predecessor values/files, checksums and manifest. Verify every necessary artifact before atomically publishing an `accepted` marker. Before that marker, cancellation or failure leaves live data unchanged. Use restrictive directory/file permissions and platform data protection. A durable file writer should flush the file, publish by atomic rename and flush the containing directory where supported; document the actual crash/power-loss guarantee rather than assuming `.atomic` establishes it.
4. **Apply under the owning actor.** Use a dedicated `ModelContext` on the main actor with autosave disabled. Do not pass model objects into detached tasks. Apply the two database domains as independently reconcilable operations, then local learning, adaptive history and permitted source materialization. Before-images are already durable. No plan-building query is rerun during replay.
5. **Reconcile every boundary.** An exact after-state means the operation already succeeded; acknowledge it without rewriting. An exact accepted before-state means the frozen operation may be applied. Any other state is retained and reported as recovery conflict. This includes a database save that succeeded but whose next journal write did not. A phase label is a progress hint, not proof of database state.
6. **Handle failures honestly.** Roll back only unsaved changes in the current context. Re-fetch persistent values through a fresh context. Retain the transaction after any possible live write. Do not reinstall predecessor files merely because a save callback threw. Do not display the current unconditional “restore was rolled back” message when a domain may have committed.
7. **Verify before success.** Verify postimages, counts, references and materialized file hashes. Save a completed receipt before releasing the fence or publishing widgets/derived state. An interruption after that receipt reuses it without repeating application. Runs remain suspended/read-only until the existing ownership coordinator independently authorizes continuation.

For a cold launch, the order is:

1. Run the already authorized complete-deletion and pending-local-purge gates. These cleanup paths must include restore artifacts so old intent cannot resurrect deleted data.
2. Inspect a small bounded restore-journal index before opening any container. An unreadable/future journal is a recovery block, not equivalent to no journal.
3. Resolve the account namespace without replaying work into a different account. Pending work touching shared local-derived/history/source paths also blocks access from a different namespace until reconciled or explicitly cleaned up.
4. If recovery is required, open only the necessary local configuration with transport disabled and keep normal runtime initialization gated. Do not start `AppStore.init` side effects, background registration, shortcuts, Spotlight or widget publication.
5. Present a recovery route. Only the recovery coordinator may write. After verified completion, reopen/activate the ordinary runtime and transport through the normal startup path.

An active CloudKit-enabled container cannot be made reliably quiescent merely by stopping the application's custom document transport. Destructive application should happen after releasing/reopening the runtime locally, then rechecking the accepted preconditions. The design does not claim a distributed transaction with remote peers. Unexpected peer changes cause recovery conflict rather than deletion or overwriting beyond the accepted plan.

## Privacy, preservation and cleanup

- Bind the transaction to the existing durable-store namespace and installation owner. Do not infer account ownership from imported profile data.
- Journal payloads and predecessors are local private recovery material. They must not enter CloudKit, caches shared with another account, ordinary JSON/CSV exports, accessibility content or diagnostics.
- A normal recovery-status export contains only appropriate IDs, version information and digests. A separate explicit private recovery-artifact export follows the existing protected-artifact policy; it is not a normal portable learning archive.
- Do not reuse `NFStoreRecoveryService.preparePackage` as a transactional backup of open stores. It is a failed-open artifact copier that rotates a temporary directory and copies SQLite sidecars. A live consistent database backup needs a closed/quiescent store or a supported coordinated backup mechanism.
- Never copy the main SQLite file alone while WAL writes remain possible. Preserve both database domains and the required sidecars/files as a coherent recovery package.
- Source/attempt deletion must invalidate replay authority before removing data, then remove linked staged payloads/predecessors. If a recovery artifact cannot be classified safely, remove the whole artifact conservatively. A pending transaction must not silently restore deleted source text later.
- Whole-device and account cleanup include journal roots, staging directories, predecessors and completion receipts. Failed cleanup remains a visible block.
- Imported JSON restores source text/citations and explicit unavailable source-file state. It does not recreate omitted original PDFs, images or formatting.
- Retain bounded original recovery material until the chosen retention/cleanup policy permits deletion. Completion does not justify silently dropping the only recoverable originals.

## Failure-injection acceptance tests

All tests use isolated temporary roots and real supported archive/prepared/restore interfaces. No real user store, app-group widget surface or network transport is used. Reopen a fresh persistent container/repository when testing restart behavior; keeping one in-memory object alive is insufficient.

Inject a failure immediately before and after each write below. For every case, assert the accepted identity set, original raw payload preservation, honest user-visible state and absence of duplicate attempts/sets/notices.

| Boundary | Required assertion after restart |
| --- | --- |
| Staged permitted payload write | No live mutation; partial staging cannot become accepted. |
| Each predecessor/backup write | Failed preservation prevents live writes. |
| Accepted manifest/marker publication | Complete durable intent or no accepted transaction; no writable half-accepted state. |
| Durable database save | Reconcile exact before/after state, including save-success followed by a thrown callback. |
| Local-derived database save | A separate domain can be incomplete without claiming both databases committed. |
| Journal phase write after either database save | Exact postimages are acknowledged without duplicate insertion or rollback. |
| Local-learning atomic publication and subsequent readback | Original or valid postimage; malformed/third state blocks recovery. |
| Adaptive-history publication and subsequent readback | Preserve the fixed accepted merge and avoid repeated notices. |
| Each source materialization/rename | Retain recoverable intent and source identity; no successful completion with broken references. |
| Final reference/hash verification | Failure leaves recovery active and does not publish success. |
| Completed receipt publication | A durable completed receipt can be acknowledged idempotently after relaunch. |
| Artifact cleanup | Failed cleanup cannot silently permit replay or claim verified deletion. |

Additional regressions:

1. `replaceAll`, interruption, then a peer record with a new identity: recovery retains that record and does not broaden deletion membership.
2. A peer modifies an affected identity, or creates a dependent reference: recovery preserves it and reports conflict.
3. Duplicate raw records hidden by normal winner projections: plan construction either represents the exact group or refuses it; it never silently drops originals.
4. Retry each recoverable transaction twice: stable result counts, no repeated attempt, set, correction notice or XP award.
5. Unknown schema, corrupt manifest, digest mismatch, wrong account/installation or oversized artifact: no ordinary startup writes and no guessed replay.
6. Same-account and different-account startup with a shared-surface transaction: neither opens mixed private content before the gate.
7. Protected canaries in predecessors/snapshots: retained locally where permitted, absent from normal exports and recovery UI/accessibility.
8. Deleting a linked source/attempt and full local cleanup: staged intent cannot resurrect it on next launch.
9. A finished transaction followed by missing cleanup or success UI: completion reuses the durable receipt, without reapplying records.
10. Cancel before acceptance: byte-identical live stores/files. After acceptance, dismissing UI does not cancel or erase durable intent.

## Bounded first implementation slice

**Deliver a durable interruption fence and retained accepted plan, without automatic replay.** This is useful independently: an interrupted restore becomes explicitly recoverable and cannot silently enter ordinary practice against mixed stores. It does not make the current application sequence crash-atomic and does not close MIG-007.

The first slice should wrap the existing one-shot restore with durable intent and a conservative recovery state. It must not expose a “Retry restore” button that simply reruns today's `replaceAll` implementation.

Proposed interfaces for this slice:

```swift
struct NFRestoreInterruptionDescriptor: Codable, Sendable {
    let transactionID: UUID
    let schemaVersion: Int
    let namespace: String
    let installationOwnerID: UUID
    let acceptedPolicy: NFDataArchiveRestorePolicy
    let sourceDigest: String
    let permittedPayloadDigest: String
    let acceptedIdentityPlanDigest: String
}

enum NFRestoreInterruptionState: Codable, Sendable {
    case accepted
    case mutationMayHaveStarted
    case recoveryRequired
    case verifiedComplete
}

// The file boundary owns bounded read/write, hashes and atomic publication.
func persistAcceptedRestore(...) async throws -> NFRestoreInterruptionDescriptor
func markMutationMayHaveStarted(transactionID: UUID) async throws
func inspectRestoreInterruption(...) throws -> NFRestoreStartupGate
func markVerifiedComplete(transactionID: UUID, verification: ...) async throws
```

Exact scope and files:

| File | First-slice responsibility |
| --- | --- |
| `Sources/Privacy/NFDataArchiveRestoreService.swift` | Capture the accepted policy and fixed raw identity/before/after plan from the exact prepared value; stage permitted payload plus bounded predecessor values before mutation; durably mark possible mutation before the first current adaptive/core/local write. On any ambiguous failure retain recovery, never rerun or claim rollback. Verify persisted desired state before completion. |
| `Sources/Privacy/NFDataArchiveRestoreJournal.swift` (new, subject to root approval/project generation) | Small private file store for immutable accepted artifacts and versioned state; bounded discovery; checksums; restrictive permissions; injected file-write failures. Keep the state/payload format capable of later deterministic replay without inventing it now. Alternatively place this type in the existing restore-service file if no project change is desired. |
| `Sources/App/NeuroForgeApp.swift` | Add a startup interruption state to `NFAppStartupController`. After deletion gates and before container/AppStore creation, inspect pending journals. In this first slice, an incomplete/unknown journal shows a recovery route **without opening the durable runtime at all**. This avoids needing a partial read-only AppStore mode yet. |
| `Sources/App/AppRootView.swift` and the startup host view | Provide a live-session recovery route once the one-shot restore enters an ambiguous state. Disable normal actions and integrations; show retained transaction status and safe recovery-artifact handling. No automatic replay or reset action. |
| `Sources/Persistence/PersistenceModels.swift` | Add a shared mutation gate for the current AppStore, set before accepted intent; guard mutation entry points while restore/recovery owns the store. Avoid calling mutating `reload()` after an ambiguous failure. This is a semantic gate, not just UI state. |
| `Sources/Integrations/System/NFSystemIntegrationCoordinator.swift` | Suspend app-owned authoring/background/document jobs and prevent reactivation/publication while the gate is active. Do not claim this stops an already-open CloudKit container. |
| `Sources/Features/Settings/SettingsView.swift` | Preserve the accepted transaction ID; show completion only after verification. After ambiguous failure, route to recovery rather than a fresh restore attempt. “Cancel” remains valid before acceptance, not as deletion of accepted intent. |
| `Sources/Persistence/NFSchemaMigration.swift` and local repository cleanup paths | Include interruption artifacts in existing whole-device/account/source cleanup so intent cannot recreate deleted data. |
| `Tests/DataExportRoundTripTests.swift` plus existing startup/persistence tests | Test normal one-shot completion, failed durable intent/no mutation, interrupted mutation/cold-start fence, saved-core/lost-marker recovery, immutable accepted policy/identity set, and protected export/cleanup. |

For the first slice's live acceptance, preserve currently supported successful restore behavior only when it can be verified. If transport/writers cannot be quiesced sufficiently to capture a reliable plan and predecessors, route the accepted operation through a controlled local restart before application rather than weakening the guarantee. That integration is a prerequisite for destructive execution, not an optional test omission.

The first slice can recognize an already verified complete receipt at startup and clear its UI fence. It must otherwise retain incomplete work for the later replay implementation or a compatible recovery tool. A read-only recovery state is useful, but it is not the specified automatic idempotent replay. Future work still includes per-domain operation reconciliation, authenticated postimage receipts, safe container/CloudKit quiescence, source materialization and the full failure matrix.

This slice is larger than “write one phase JSON”: a durable marker without startup gating, private preservation and immutable accepted membership would produce a misleading recovery claim. It also cannot be reduced to a RAM backup or a catch block around `context.save()`.

## Remaining risks and evidence status

The highest implementation risks are comprehensive write-fence coverage, safely releasing the active CloudKit container, shared local storage/account scope, and complete raw predecessor capture across both database configurations. A same-process lock alone does not exclude cross-process or CloudKit writes. A state label alone does not prove a save failed or succeeded.

No production files, tests, project configuration or build outputs were changed for this design. All failure-boundary cases above are proposed tests, not executed evidence. Existing async preparation tests do not substitute for these cases.

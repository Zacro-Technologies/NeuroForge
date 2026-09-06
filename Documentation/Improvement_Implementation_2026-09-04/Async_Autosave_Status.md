# Async archive autosave — frozen integration package

`async-session-writes.patch` changes 9 existing Swift files. `catalog-entries.json` supplies four EN/JA entries; insert them entrywise without reformatting the existing catalog. No project/model-schema changes are needed. `prepare.py` reads current main and generates `base/`, `work/`, and the patch without editing the repository.

## What is connected

Ordinary/source/protected and modern/legacy generated **actual debounced view tasks** now call the storage actor. MainActor captures an immutable operation and one exclusive ticket. Shared pure builders retain the existing slot/owner/revision/pending-response/accepted-prefix checks. Candidate construction, whole-archive validation/encoding/hashing, bounded file checks, staging, flushing and atomic replacement execute on the actor. Live AppStore, ModelContext, models and repository objects never cross that boundary.

The worker uses the existing publication NSLock and the existing `.lock` flock namespace. Synchronous lock acquisition is now nonblocking. Both sync and async writes validate the cached digest of the original bytes, as well as the durable revision. A synchronous retry cannot overwrite bytes that an async save refused as stale. The ordinary builder also refuses replacing an existing foreign-owned run even when a caller holds an authentic local writer generation.

Cancellation before the commit boundary leaves the predecessor intact. After rename, the repository adopts the accepted archive regardless of cancellation or released view ownership. The runtime separately rechecks its captured command before acknowledgement/mirroring; it cannot publish another owner's feedback. A directory-verification failure after rename returns a committed-but-unverified acknowledgement, retains the draft/recovery surface, blocks a normal saved close, and permits a real async retry. Granular recovery originals and unrelated opaque private payloads are retained.

Raw repository writes/adoption, takeover and context-first session/delete/restore entry points are fenced. Independently invoked `AppStore.reload()` retains read projections while pending but defers its legacy taxonomy/diagnostic/weekly model mutations and archive reconciliation; repeated deferred reloads coalesce per store and run after ticket finalization. No core mutation is justified by a future archive acknowledgement.

Typing remains available during autosave. An explicit response/help/stage/Skip/Next/End/Replace/reviewed action waits once behind it and locks further UI edits. On completion, the captured writer and response identity are checked again. A late native input is retained with an explicit retry message instead of being silently scored or discarded. Solving time excludes the explicit-action wait. The current editor is never marked saved merely because an older snapshot succeeded. Staged estimate focus follows its actual acknowledgement. The progress indicator appears only after 200 ms.

In-app Close and native Close/Quit wait for pending saves, then run the existing exact current-draft/delegate checks. Quit still prepares every registration before dismissing any. A new/withdrawn registration during its wait cancels the stale native command. Native window handling preserves child-sheet and original-delegate authority.

## Verification at handoff

- All nine complete candidate files pass frontend parse.
- Current-tree `git apply --check` passes; exact patch/base hashes are recorded in `verification.json` and `base-sha256.txt`.
- Before the final section13 rebase, all six Swift 6 strict-concurrency, warnings-as-errors isolated typechecks passed. After the rebase, native registries/modifier/callbacks and native tests pass again. The other four refreshed checks currently stop on the older built module lacking `permitsSolidSection` / `solidSectionPolicyVersion`; their exact diagnostics are retained in the typecheck logs. They must be repeated against the new module or covered by the full integration build. No source guard was removed to satisfy an older module.
- `typecheck.py` documents the compile-only declarations used against the current built module: existing private file helpers for the isolated worker; a repository property/method shell for the real async API body; new async API signatures for runtime/tests. This is **not** a full-project compile. Existing private file implementations remain intact in the parsed full repository candidate.
- No Xcode build, XCTest execution, simulator/native application control, or installed visual acceptance was performed by this agent. Parent owns those checks.

The 15 new methods are appended to existing `ExactSessionContinuityTests` and `GeneratedLifecycleParityTests`, plus `NativePendingArchiveCloseTests`. They hold the **actual worker** through a DEBUG event-only hook at encoding/staging/rename/commit. Coverage includes a 6 MiB retained opaque payload, MainActor responsiveness, the actual shared lock, pre-context refusal, pre/post-commit cancellation, generation release, exact digest mismatch, wrong-owner refusal, after-rename directory verification failure/retry, late edits, queued Submit/Skip/End/reference reveal, local-save/legacy-mirror failure, cold modern/legacy recovery, deferred reload mutation, and native pending-close registration/delegate checks. Observer hooks carry event names and a thread-location Bool only.

## Still requires engineering after this slice

The initial acknowledgement, presentation/exposure, explicit prepared/receipt/feedback, adaptive/fixed launch and Next/Replace acceptance, and administrative writers retain their synchronous durable implementations. They are correctly fenced/queued against this autosave actor; their own large writes can still occupy MainActor. Move these commands to typed async preparation/acceptance individually, retaining the same ticket, captured generation, immutable receipt and persist-before-publish boundaries. Do not claim the entire archive architecture requirement complete from this vertical slice.

Full restored-store journaling, broader off-main derived projections, physical-device/VoiceOver certification and the remaining installed module matrix are separate outstanding work. Current parent UI/native evidence predates this async package.

## Root execution on a5a0a069

The full-project macOS build succeeds. Focused XCTest:183/184 methods pass; six assertions fail in one generated self-check fixture because it writes the wrong declared response field. All ordinary continuity, granular recovery backup, native pending-close, catalog and historical-target methods pass. The test-only self-check correction is pending execution. Native pending-close tests exercise actual NSWindow coordination with a manual pending gate; they do not run the storage actor. Installed application evidence for this async slice is still pending.

## Subsequent execution and iOS stack repair

All async autosave tests pass in the c01 and c0c4 full Mac runs. A real installed c01 source cold-read and coordinate autosave crash exposed excessive cooperative-worker stack use in archive validation. The 09b build splits the same ordered checks into non-inlined phases and unwinds normalized decoding before validation; the installed source, coordinate, section and cube journeys now pass. Ordinary/source/protected explicit Submit has since been migrated as a separate slice and still requires execution.

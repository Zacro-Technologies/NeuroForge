# Generated explicit Submit: asynchronous archive transactions

This delta uses the ordinary `NFSessionLifecycleCoordinator.commitAsync` and its MainActor immutable receipt builder. It migrates the generated scored Submit and self-check reveal/rating production buttons, keyboard submission, pending-commit cold replay, explicit retry and takeover replay. It also waits for Submit before processing End. No model columns or serialized generated draft fields change.

## Actual transaction order

1. Capture the current generation-bearing writer command and raw response; await at most the already queued draft boundary. Stop the solving clock before waiting. Freeze score, attempt ID and response with the existing coordinator.
2. Persist the exact prepared private draft through the existing storage actor, transaction ticket, same file lock and byte/revision CAS. Adopt accepted revision even when cancellation follows rename.
3. The worker authenticates the exact retained private payload digest, run owner and prepared stage. It independently compares the immutable proposed record against the frozen response/result/exercise/attempt/provenance/sidecars, then retains the immutable history snapshot.
4. After verified snapshot acknowledgement, the MainActor inserts the original SwiftData receipt. No ModelContext or live model enters an actor.
5. Persist the feedback draft through the actor. Publish feedback and aggregate counts only after verified acknowledgement. A post-rename directory-verification failure retains the exact accepted draft and its typed publication intent while the visible UI stays pending. Retry repairs those exact bytes at the next revision, then publishes once.

Modern run identity stays `draft.id`; legacy nil-runState drafts retain their authenticated original `draft.id` writer and generation-derived historical attempt.sessionID. Legacy data gains no invented slot ledger. Replay matches authentic immutable receipts without rescoring. Conflicting originals stay unchanged; a separate typed actor operation journals the proposed immutable record against its authenticated prepared draft.

Late native answer changes cannot overwrite the frozen prepared response; recovery export retains the actual changed field. Answer controls and confidence are disabled during pending work. A pause delivered while Submit awaits storage preserves its interruption count and queued checkpoint; accepted phase changes do not falsely count as answer edits. Source self-check reference remains behind verified acknowledgement and produces self-reported, zero-objective evidence.

## Validation authored

Twelve async test methods run the actual injected storage executor on its normal cooperative worker stack. They hold prepared/snapshot/feedback/conflict stages, cover pre-rename and post-commit cancellation, modern plus legacy cold continuation, ownership release, exact attempted-response refusal, conflicting original retention, unverified reference/feedback repair, late native fields, and queued Pause/End. They reuse `NFAsyncSubmitProbe` already present in ExactSessionContinuityTests. No tests or Xcode build were executed by this agent.

All four changed files pass Swift frontend parsing and the patch passes current-main apply check. Four isolated strict Swift 6 typechecks cover the actual runtime, immutable worker candidate, MainActor receipt adapter and all twelve test bodies. Unchanged private helpers use compile-only signatures in those checks; this is not a full application build or execution. Root must run the real suite and installed journey.

## Deliberately remaining engineering slices

Generated Skip/worked-solution commits, initial launch/first presentation, intermediate teaching/support locks, ordinary/generated Next/Replace and terminal persistence, reviewed override/admin/deletion/restore writes still use their existing synchronous durable protocols. `retryCommitAsync` dispatches a pending unscored intent to that existing implementation. End waits for scored Submit, then uses the existing terminal transform. Core SwiftData receipt insertion and legacy projections remain MainActor work. These are separately scoped migration work, not external acceptance items.

The package rebases from current main and preserves net-folding14/solid-section/coordinate policy guards, split non-inlined archive validators, current 44-point controls, data focus reset, generic encoder, and recent generated pause policy. No source, catalog, simulator or DerivedData mutation outside this scratch package.

Actual iOS execution on sourcef9541cc4: all33 selected regressions pass (14 ordinary Submit,12 generated Submit,7 typed archive methods including advanced coordinate families). This is real simulator worker execution, not the installed interface journey. Concurrent Mac full suite was stopped after fingerprint worker stack overflows; no full-source acceptance claim.

Complete Mac execution on sourcef4c27814: all1343 tests pass281.085s, including this implementation. Root repaired the NFChoiceOption full accessibility label and split fingerprint validator frames without changing fingerprints or checks. Per-slot timing-change repair and new installed advanced-coordinate journeys are separate pending verification.

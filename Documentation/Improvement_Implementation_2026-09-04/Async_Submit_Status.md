# Ordinary explicit Submit async migration

Delta against the current main sources, including the integrated autosave actor, recovery-backup guard, split archive validators and net-folding policy. The exact four base-file hashes are in `base-sha256.txt`. No main-tree writes or Xcode builds were performed for this package.

1. Capture the current writer generation, exact response/sidecars, stable slot/attempt and solving duration on MainActor. The existing scorer creates one frozen intent; protected scoring retains its existing minimal receipt. Lock explicit submission while storage is pending.
2. Publish only the locked prepared-answer phase. Persist its exact local checkpoint through the archive actor. Adopt the acknowledged revision even when cancellation arrives after rename. Mirror the captured legacy checkpoint on MainActor after verified local acknowledgement. Failed preparation cannot insert an AttemptRecord or show a reference/feedback.
3. Construct a transient AttemptRecord and evaluate immutable retry matching on MainActor. This uninserted model never crosses executors. Retain the exact ordinary/source snapshot, sidecars and editorial capture using an immutable actor command tied to the prepared checkpoint, slot and attempt. Protected items never gain a generic exercise/solution snapshot. The two new operation payloads are immutable reference boxes, with snapshot validation in a separate non-inlined function, to avoid increasing the existing operation enum's worker-stack footprint.
4. After verified snapshot retention, revalidate the captured generation and insert/save the core AttemptRecord on MainActor through the existing immutable retry queue. This small SwiftData receipt insertion remains synchronous in this bounded archive migration. Core failure leaves the prepared intent and snapshot durable, with no feedback publication. Conflict journals use the actor before any conflicting core insertion.
5. Construct a complete feedback checkpoint as a value, including exactly-once aggregates and the captured reflection invitation. Save it through the actor before publishing feedback or aggregates. Failed feedback persistence leaves the prepared UI and authentic receipt available for retry without rescoring or duplicating the original row.
6. A rename followed by failed directory verification adopts the accepted revision but does **not** reveal the reference or feedback. A typed pending value retains that exact checkpoint, its publication intent and the original command generation. Autosave, close and End cannot replace it with the older visible phase. Retry rewrites/verifies that exact value, then publishes once. A cold reader independently validates whichever exact file was retained. Legacy mirror failure after successful local verification does not retract an already accepted phase.
7. The actual ordinary/source/protected Submit controls, self-check controls, keyboard routes, cold prepared-resume and Retry call awaited entry points. End requested during Submit waits for its acknowledgement. Existing synchronous runtime methods remain compatibility seams for direct fixtures/shared generated callers; no production test flag selects the new path.

Cancellation before worker commit preserves the old bytes; cancellation after rename adopts the accepted receipt before returning. A cancelled command does not proceed to another transaction. A newer writer generation prevents old-command insertion or UI acknowledgement. Late raw native answer changes remain available for recovery, cannot replace the frozen prepared answer and cannot inherit its score.

## Remaining migration slices

- Generated explicit prepared answer, attempt and feedback writes still use their synchronous adapter.
- Launch, initial/presentation acknowledgement, intermediate teaching locks, Skip, Next, Replace, reviewed overrides and administrative/archive writes still need separate awaited caller migration.
- Core SwiftData receipt insertion and legacy projections remain MainActor operations; no ModelContext or live models cross actors in this package.
- Full restore journaling and broader background projections remain separate engineering work.

## Validation

Four modified Swift files parse. Four isolated Swift 6 strict-concurrency/warnings-as-errors typechecks pass: actual runtime/coordinator, pure operation candidates, MainActor receipt construction/insertion adapter and 14 new test methods. These checks use signatures for unchanged/private dependencies and do not replace a complete app build.

The 14 new tests are authored against the actual injected archive executor on its normal cooperative worker stack. They cover held-feedback publication, solving-time exclusion, precommit cancellation, cancellation after snapshot/feedback rename, writer takeover, legacy mirror failure, private source reference/self-report, protected cold receipt replay, real filesystem failure, late native input, queued End, unprepared snapshot refusal and directory-verification failures for feedback and source reference. No XCTest execution or installed-device pass is claimed for this delta.

## Root execution

All14 new regressions pass in the complete1315/1315 Mac run on6485e708. Source reference, protected minimal receipts, post-rename directory verification, exact retry and cancellation paths are executed. Actual installed UI Submit remains a separate next run.

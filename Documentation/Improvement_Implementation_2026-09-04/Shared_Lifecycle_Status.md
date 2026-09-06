# Shared lifecycle implementation — 5 September 2026

Current verification (5 September, 14:41): the generated-run parity package adds a durable presentation gate, per-run/per-slot identities, skip/solution receipts, staged help, explicit terminal states and separate new runs. All 11 `GeneratedLifecycleParityTests` and 25 live editorial controller tests passed in the full 1,116-test run on `c041286d`; that full run failed one older command-capability method (two assertions). The corrected full run on `5bb6de34` then passed all 1,116 tests, including the updated pause capability and inactive terminal/prepared phase guard. The terminal draft still retains unneeded future set inventory; compacting that terminal receipt, protecting all specialized transitions and completing writer-generation/background-write integration remain engineering work. Older sections below record earlier checkpoints.

CORE-001 now has a shared command boundary for ordinary and generated practice. This is a bounded implementation, not a claim that the complete improvement specification is accepted. The first completed integrated run exercised the new runtime paths; one generated test fixture required correction and full rerun remains required.

`NFSessionLifecycleCoordinator`, in the existing UniversalSessionView file, owns typed phases, allowed Next/skip-completion/end commands, frozen typed response/result/confidence/attempt identity, scoring-versus-clarification branching, prepared checkpoint before attempt creation, attempt acknowledgement before feedback persistence, and next snapshot persistence before visible publication. Both runtimes now use these operations; they no longer each implement the full commit or ordinary Next sequence. Generated integer phase values survive only at its legacy UI/private-envelope boundary.

The adapters retain their different exact envelopes. Ordinary practice uses NFLocalItemCheckpoint, the local reservation journal and AppStore.saveExerciseAttempt; the existing SwiftData checkpoint is a compatibility projection updated after the exact local snapshot is durable. Generated practice uses NFGeneratedPracticeDraft and saveAuthoredExerciseAttempt; private authoring payloads are not copied into sync-eligible SessionRequest fields. No SwiftData model fields, archive schema versions, scorer identifiers, signatures or evidence classes changed. The generated envelope adds one backward-decodable optional clarificationMessage, which is bound to its exact editable response and disappears when that response changes.

Generated receipt recovery probes the full existing receipt before quarantine or a fresh attempt write. A conflicting receipt carries its frozen CommitIntent to the append-only DATA-012 journal; both payloads must be durably captured before read-only conflict recovery is acknowledged. A failed conflict-journal write leaves the prepared phase and response retryable. The existing generated conflict regression now asserts both raw proposals, both exact exercise references and unchanged original attempt. Ordinary receipt recovery deliberately delegates the complete immutable comparison to AppStore's idempotent attempt-save operation: its coordinator receipt port reports absent, but an existing attempt ID bypasses only current interaction quarantine, then AppStore checks the typed response, exact key/result/scorer, session and provenance. It does not accept an ID match as proof of an equivalent commit. Recovered prepared intents use the retained scorer result, never a newly evaluated result. A new uncommitted invalid contract remains unavailable. Eager restore checks protect editable malformed interaction/response snapshots; committed historical receipts are not rewritten.

Next creates an exact candidate snapshot while the previous feedback is still visible. A failed proposal write leaves that feedback, response and index intact. Once the exact journal accepts a snapshot, a later compatibility-mirror failure may display a recoverable save error; the accepted exact snapshot remains available for resume. The coordinator does not roll back an accepted reservation or fabricate a second identity.

Installed UI evidence identified exhausted focused pools for logic.conditions, logic.proof-builder, science.confound and transfer.conditions. The adapter now retains first-item feedback and exposes nextUnavailableReason with no unavailable exercise publication or false save-error alert. The UI offers an explicit early end. This is an honest capacity boundary; additional semantic content remains an editorial/generator requirement.

## New regression methods and execution

Existing SessionIntegrityReviewTests file:

- testFiniteFocusedFamiliesRetainSavedFeedbackWithoutActivatingAnUnavailableQuestion — four actual runtime/factory/ledger probes, no new snapshot or fake result, explicit early end.
- testSharedLifecycleRetriesTheFrozenIntentOnlyAfterPreparedSnapshotSaves — failed preparation, changed incoming draft, stable ID and original typed response, exact durability order.
- testSharedNextProposalWriteFailureCannotPublishOrChangePhase — failure after proposal preparation cannot publish the candidate.
- testSharedReferenceExposureRollsBackOnFailedDurableWrite — reference remains hidden on failed save.
- testOrdinarySharedSelfCheckPreservesRevealedReferenceAndFrozenRating — actual private exact self-check, neutral result and no objective score count.
- testMalformedOrdinaryTypedCheckpointCannotReachATrappingRestore — duplicate/mismatched structured payload stays unavailable, original repository response survives.
- testOrdinaryNextPublishesExactlyTheDurableNextSnapshot — actual adapter accepted snapshot, blank typed next response and exact resume.

Existing AIAndSourceTests file:

- testGeneratedNextWriteFailureRetainsFeedbackThenPublishesExactSavedQuestion — real filesystem write obstruction, intact prior feedback, retry and exact private resume.
- testGeneratedSharedLifecycleReferenceIsNotExposedWhenSaveFails — actual authored self-check adapter, no premature reference disclosure or attempt.
- testGeneratedClarificationIsDurableInlineGuidanceWithoutAnAttemptOrSaveAlert — actual symbolic authority, unsupported notation, saved/restored guidance, edit clears guidance, valid resubmission.

The existing future-nested-exercise test now first asserts rejection of an unauthorized reserved snapshot replacement and original sorted JSON preservation, then constructs a future checkpoint directly to verify unavailable recovery without overwriting the original journal.

## Remaining boundary and acceptance work

Protected assessment item selection, assessment stopping rules and the skip/reveal evidence operation remain specialized ordinary adapters. Their lifecycle/checkpoint behavior and protected output policy require the full integrated regression suite; this extraction does not claim they were converted into one generic content selector. Source-review migration uses the same Universal runtime; its adapter tests passed within ExperienceImprovementTests (18 tests, zero failures). Installed current-run UI acceptance remains separate. No archived private payload is converted into ordinary cloud content. Physical accessibility checks, representative human learning sessions, all 58 family expansions, independent band review and signed-release admission remain outside the evidence established by these automated tests.

The completed `/tmp/neuroforge-coordinated-recovery-unit-tests.log` run at 01:40:36 on 5 September executed 784 tests with 16 failed assertions across four methods. SessionIntegrityReviewTests passed all 28 methods, including all ten new ordinary/shared methods and the corrected future-snapshot fixture. Generated reference exposure and clarification methods passed. The generated Next method accounted for ten assertions because its fault fixture deleted the original journal and then retried against a missing revision; the fixture now moves the directory aside and restores it exactly before retry. Production revision checks were preserved. The remaining failures were old focused-family availability expectations and a presentation-pin fixture. No full-pass claim is made; the corrected test requires rerun.

## Skip acceptance correction and attempted integration

Read-only review found that clearing pendingSkip before the new current-checkpoint write could erase the reservation bridge's skip intent. The corrected adapter retains pendingOutcome through the post-commit checkpoint until the next/summary snapshot accepts it. Membership in the acknowledged skipped/revealed event set prevents duplicate cumulative duration after retry or close/relaunch. Failed transitions keep the saved-skip state, disable response edits and expose retry/end actions. A finite exhausted pool accepts an early summary with its actual presented count; it does not publish empty feedback.

Three more SessionIntegrityReviewTests cover fresh/final skip and solution-reveal ledger outcomes; finite-pool repeated actions; and a real immutable skip plus reachable pending checkpoint, failed transition write, retry/reopen with one attempt, one outcome and seven seconds. The failure fixture moves the prior directory aside rather than deleting the journal, so restoration retains the real transaction revision.

The first integrated attempt after extraction (`/tmp/neuroforge-session-recovery-unit-tests.log` and `...-installed-ui.log`) stopped before tests because Swift6.3.3 crashed during IR generation for an optional ConfidenceLevel setter reabstraction in AIStudioView. This was a compiler failure, not a completed test run. The explicit-closure correction subsequently compiled in the 784-test run, and all three skip tests passed. That completed run and its remaining failures are recorded above.

## Latest verification update

The subsequent root-owned `/tmp/neuroforge-final-recovery-unit-tests.log` run completed at 01:49:57 on 5 September 2026 with **784 tests, zero failures**. It includes the corrected generated Next write-obstruction fixture and all content, historical, golden, shared lifecycle and granular protection tests described here. This supersedes the earlier 784/16 result above. The later scratchpad byte/geometry recovery changes are authored after that green run and await their own integrated execution; see [Scratchpad_Recovery_Status.md](Scratchpad_Recovery_Status.md). The successful Mac run is not certification of all editorial, physical-device, installed UI or performance release gates.

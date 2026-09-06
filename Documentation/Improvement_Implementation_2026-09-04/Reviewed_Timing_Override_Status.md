# Effective timing after a saved display override

Follow-up to the integrated per-receipt timing patch8bb5. The original accepted timed request remains immutable, but its original B1 fluency scope must not block a later untimed B2 question after the user has durably removed the timing target.

Three existing files only:
- `NFLocalSessionRepository`: derive one effective condition from exact predecessor override or original request; use it both for candidate feasibility and criterion condition groups. Pass the same explicit override into checkpoint creation at prepare and atomic acceptance.
- `UniversalSessionView`: add optional final `timingConditionOverride` argument to `NFLocalItemCheckpoint.initial`; require supported non-timed overrides and validate the exercise against the effective condition. Runtime timing authority and checkpoint persistence continue to require the exact accepted slot/admission/profile/scorer/manifest for any originally timed run, while using its actual saved non-timed condition to permit the new untimed demand. An override cannot grant a timed scope or bypass a changed/missing manifest. Existing nil initialization and requests retain their exact metadata.
- `LocalLearningLifecycleTests`: `testTimedRunCanRemoveTimingTargetAdvanceToB2AndResumeWithExactUntimedAdmission`. Uses actual synthetic admitted bank entries, eight real prerequisite commits, six-item public timed launch, persisted untimed switch, four full responses, actual automatic B2 selection, exact cold draft/commit/Next, preserved first timed receipt/original request, and manifest-drift refusal even after the untimed override. The enlarged B1 fixture supply avoids confusing an actual scope defect with finite inventory exhaustion; source keys/digests remain real bank materializations.

Full patched-file syntax checks and `git apply --check` pass. Actual module compilation/XCTest remain root-owned and pending. No main files changed here. Patch SHA256: 5d204299f2a91991b73f2b40684d8bcc4df569d9724da057d31e2cd43d9d4a27.

Actual Mac verification on2ba96fe3: complete1359-test suite passes284.558s. Includes all13generatedNext/End and3timingreceipt/target-change tests. Actual iOS new transition workers and new installed Next/End implementation remain pending.

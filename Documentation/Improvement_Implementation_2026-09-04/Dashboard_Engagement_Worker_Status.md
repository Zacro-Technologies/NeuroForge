# Dashboard engagement worker migration

This package preserves the existing raw engagement policy while moving Forge, consistency and mental-math adaptation/reduction into the existing immutable dashboard worker. The live view now reads one revision-controlled snapshot. Model capture remains on MainActor. The successful checkpoint upsert advances the existing ephemeral progress revision so completion-only changes can invalidate pending dashboard work without a reload or archive mutation.

No history-list, priority-card, whole-dashboard background migration, performance percentile, reviewed admission or evidence widening is claimed. Raw engagement remains separate from effective reviewed learning evidence. Forge counts every existing eligible non-skipped activity, including source and protected participation, under its unchanged policy; consistency uses the unchanged standardized raw subset; mental-math inputs use the selected filters, effective dispositions and protected-first adapter.

## Files

- `Sources/Adaptive/NFProgressInsightEngine.swift`: Sendable immutable engagement/completion/result values, immutable compatibility reducers, expanded cancellable worker.
- `Sources/Adaptive/NFMentalMathProgressAdapter.swift`: model-to-value capture, with existing synchronous wrapper retained.
- `Sources/Features/Progress/ProgressDashboardView.swift`: capture all-time engagement beside filtered math, render worker results.
- `Sources/Persistence/PersistenceModels.swift`: successful checkpoint save invalidates ephemeral progress revision.
- `Tests/ProfileProgressContractsTests.swift`: three actual-store held-worker regressions, one existing compatibility test actor annotation.
- `Tests/ProgressEvidenceTests.swift`: actor annotations on two existing legacy-model compatibility tests.

The two model compatibility reducer entry points are explicitly MainActor because `NFImmutableAttemptRecordSnapshot.init(_:)` reads SwiftData models. Their immutable overloads remain nonisolated. Strict checking caught and corrected this missing isolation in the initial candidate; there is no unsafe actor bypass.

## New regression methods

1. `testDashboardCompletionOnlyUpsertInvalidatesHeldEngagementWithoutReload`: real saved answer and incomplete checkpoint; completed old worker held; actual `upsertCheckpoint(isComplete:true)` changes revision without reloading, changing attempt bytes, or changing the private archive; current snapshot earns completion XP; late old result cannot erase it. Captured completion remains a value after the model changes.
2. `testDashboardEngagementStaysAllTimeWhileMathUsesFilteredEffectiveHistory`: actual saved recent/older math, quantitative, source, protected, skipped and separately withdrawn rows. All-time Forge/consistency remain equal through math/week filtering; math sample counts/accuracy obey filters and effective exclusion. Raw rows remain unchanged and no reviewed conditions are invented.
3. `testDashboardTenThousandActualRowsCaptureImmutableEngagementAndMathOffMain`: generates 10,000 real in-memory persisted rows on demand, then captures the actual store boundary; holds the actual detached reducer while MainActor changes and rolls back a model field; exact immutable input, count, membership, accuracy and completion XP remain coherent. No large fixture JSON is committed and no latency target is asserted.

All fixtures use existing in-memory AppStore setup and explicitly assert shared widget publishing is disabled. Containers are retained for each entire asynchronous fixture. They do not access real user stores.

## Verification and integration

`prepare.py` regenerates the six-file patch from the current repository without writing any repository file. `typecheck.py` checks the exact reducer/adapter/capture bodies and both complete test files against the actual compiled macOS NeuroForge module; it renames only the probe's capture method/test calls to avoid importing two same-signature methods from different modules. This is a real-module typecheck, with no persistence or authority stubs. See `Typecheck_Manifest.txt` for exact module hash and command.

Syntax parse and current-tree `git apply --check` pass. Strict Swift 6 complete-concurrency typecheck passes with no diagnostics. No xcodebuild, linked tests, native UI run, whole UI file typecheck or measured performance result is claimed. Root must integrate and execute the three new tests plus the existing progress/engagement suites.

## Actual execution

All three new actual-store worker methods pass on source `54cd410a`, within a 223/225 partial Mac run. The 10,000 persisted-row fixture passed13.496s including preparation/capture/reduction; this is not a latency benchmark. All48 ProfileProgressContractsTests and20 ProgressEvidenceTests pass. Both failures are in separate new goal fixtures. An installed weekly-chart/history replay of the compiled engagement implementation is pending.

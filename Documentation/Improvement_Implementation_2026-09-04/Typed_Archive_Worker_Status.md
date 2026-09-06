# Typed archive worker regression supplement

This is a scratch-only, append-only test patch. It adds no production source, model, project, or test target changes. The only destination is `Tests/LocalLearningLifecycleTests.swift`, already included in the macOS unit suite and the iOS native-input target. The base includes the current adaptive quarantine-proof test tail.

## What the six methods exercise

`TypedGeometryArchiveWorkerTests` uses a real file-backed `NFLocalSessionRepository` with disposable in-memory SwiftData records, then the actual `NFUniversalSessionRuntime.checkpointDraftAsync` transaction and `NFLocalSessionRepository.prepareStartup`/`adoptPreparedStartup` worker boundary:

1. `testSourceExactDraftColdStartupAndAutosaveUseRealBackgroundWorkers`
2. `testCoordinateDraftColdStartupAndAutosaveUseRealBackgroundWorkers`
3. `testLabeledCubeDraftColdStartupAndAutosaveUseRealBackgroundWorkers`
4. `testSolidSectionDraftColdStartupAndAutosaveUseRealBackgroundWorkers`
5. `testCubeNetDraftColdStartupAndAutosaveUseRealBackgroundWorkers`
6. `testMixedTypedArchiveColdStartupAndAutosaveKeepEveryExactDraft`

Spatial fixtures use the real public catalog launch for coordinate rotation, object rotation, cross-section, and cube net; they assert the current retained schema and valid typed contract. Source uses the actual exact-source adapter, including its cold resume validation. These are ordinary editable drafts: the tests do not grant reviewed content or derive correctness from the wrong draft values.

Each method saves a first typed edit through the real asynchronous actor, releases the writer, prepares/adopts the authentic file off-main, attaches the cold runtime, saves a different typed edit through the actor, and independently decodes the newly written file again. Exact exercise/response/scratchpad, slot and attempt IDs, digest, original item position, response flags and saved revision are checked. Read/adopt must leave original file bytes unchanged. No attempts, scores, or credits may be created. The saved source reference stays unrevealed. The observer records stage names and execution location only; there are no mock workers, blocking semaphores, sleeps, or fault callbacks.

All caches, documents, local archive, history, temporary artifacts, and rotation state are explicitly fixture-scoped. Widget publishing is disabled and asserted; model containers remain alive through every async use.

## Validation status

- `swiftc -frontend -parse` on the full patched test file: PASS.
- `git apply --check` against the root working tree: PASS.
- No xcodebuild, app compilation, XCTest execution, simulator launch, or performance measurement was run by this agent.
- Root must compile and execute all six on both macOS and the existing iOS native-input target. Passing macOS alone is insufficient evidence for the iOS cooperative-worker stack budget that triggered this regression work.
- This checks exact active-draft persistence and cold recovery. It does not claim full archived-history throughput, native geometry interaction coverage, protected evaluator continuation, or percentile latency.

## Validation-frame source review

The previously reviewed root refactor preserved sequential validation, all error and cancellation checks, local Archive-copy mutation, and publish-after-validation behavior. `normalizedArchive` completes before the nine ordered validation helpers; no helper publishes a partially classified archive on a subsequent error. Root incorporated explicit non-inlining on the entry/helper boundaries. This source review found no concrete semantics/exclusivity defect. Native execution of the resulting call stack remains root-owned evidence.

## Root execution

All six tests pass on the actual iOS simulator unit host at source6485e708, on the normal cooperative executor. See Typed_Archive_iOS_6_Passing_Summary.json.

Actual iOS execution on sourcef9541cc4: all33 selected regressions pass (14 ordinary Submit,12 generated Submit,7 typed archive methods including advanced coordinate families). This is real simulator worker execution, not the installed interface journey. Concurrent Mac full suite was stopped after fingerprint worker stack overflows; no full-source acceptance claim.

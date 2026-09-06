# Detached retrieval validation stack fix

Patch SHA256: 94fb4f58f028897783baf9f49d16fff5e03163f53a318021d14efd788cf9a622

The actual macOS debug crash `/Users/takamimarsh/Library/Logs/DiagnosticReports/NeuroForge-2026-09-05-155148.ips` is a cooperative worker stack overflow, with twelve frames and no recursion. Read-only disassembly of the compiled debug dylib shows approximately160448 bytes retained by `NFFallbackExerciseGenerator.generate` before validation, plus15968 bytes in `NFRetrievalAssetCatalog.asset` at the failing leaf. Other factory/preview frames remain in the chain.

The public generator is now a small construction→mandatory schema validation→mandatory taxonomy validation→return wrapper. The private non-inlined construction helper returns all temporary construction frames before validators descend through retained authority. This preserves the generated value, validation order, errors, actor boundary, and version/recipe bytes. It introduces no cache, thread or stack configuration, release-optimization requirement, or main-actor fallback.

Two actual XCTest methods are appended to existing ContentImprovementRegressionTests.swift under RetrievalWorkerStackTests:

- `testActualDetachedPrelaunchValidatesEveryRetrievalAssetFormWithoutChangingAuthorityOrStore`: real memory-only AppStore→reviewedStartingPreview→Task.detached path with synthetic exact admissions for each cloze/equation/figure form in EN/JA; proves preview feasibility, no archive/attempt/launch publication, and byte-identical second detached factory materialization.
- `testDetachedGenerationStillRejectsInvalidRequestsThroughMandatoryValidation`: actual detached negative-index/future-policy refusal with exact invalidIndex/unsupportedRetrievalAsset errors.

The first method uses synthetic admission authority solely as a test fixture; it grants no shipped review or band. The existing actual failing DefaultContentCatalogTests.testTypedRetrievalAssetPreviewAndNextRemainInEquationActivity is retained and should be included in the root rerun.

PASS: two changed Swift files parsed; current-tree git apply --check. No app build/test execution by this agent. Root owns actual worker regression and final stack-frame inspection. No working-tree edits. Both fixture stores explicitly use one disposable per-fixture directory for cache/documents/history/temporary artifacts, memory-only local repositories and per-fixture memory rotation; cleanup removes the directory.


## Root execution update

Root execution: both retrieval worker-stack tests pass in the full 1,211-test run and the 134-test follow-up. A later coordinate fingerprint implementation introduced a distinct nested stack problem; it is separately recorded and being corrected.


## Current structural fix and execution

Full source8d4c09e6 passed1,235/1,237; both failures were actual retrieval worker previews. Factory unavailable-fallback unwind alone did not remove all large nested frames. Root split draft generation from exercise assembly, and ordinary fallback search from fixed/retention selection. All three worker regressions and all20catalog tests pass on dd374256 in the216-test focused run; that run fails six separate initial-target methods. BuildCandidate now has a4,640-byte debug frame, draft49,024 and assembly100,128; disassembly is retained in Generation_Frame_Disassembly_dd374256.txt. No stack-size override or main-actor fallback was used. A subsequent section13 integration requires a fresh full run.

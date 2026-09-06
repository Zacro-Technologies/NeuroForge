# Authored goal relevance — SCH-003

This patch adds an actual preference input to the existing reviewed selector's goal tier. It never treats a goal as evidence of proficiency, inferred weakness, prerequisite completion, or band readiness. The released admission registry remains empty.

## Policy and authority

- `NFEditorialDemandRecord.goalAlignment` is optional. A declared alignment names the exact objective and a sorted, unique, nonempty set of supported raw `TrainingGoal` identifiers. Every admission for that objective in the same manifest must carry the same declaration. All-nil objectives remain supported and receive zero goal relevance.
- New `EditorialLiveControllerV5` / `EditorialMixedControllerV5` pins are created only when relevant admitted declarations and the actual stored profile preferences exist. The profile UUID and sorted raw goals are frozen in the request. Empty known preferences are valid and receive zero relevance; unknown IDs, duplicates, unknown policy/schema versions, or conflicting objective declarations fail closed.
- The goal trace binds the admitted bank ID, exact exercise digest, objective, authored mapping, frozen preferences, and exact goal intersection. The rank is binary, so multiple selected goals cannot manufacture extra weight. Family coverage, explicit due/repair slots, family/structure variety and the existing hard band/prerequisite filters retain precedence.
- All live V5 candidate traces are reconstructed from admissions before selection. Acceptance replays the full selection under the existing transaction/evidence/writer/rotation checks. Cold validation binds every stored goal trace to its request preferences and delivery profile. Current profile edits affect future launches only.

## Compatibility

V1–V4 controller constants and their behavior are unchanged. New optional keys encode as absent for old values. Old requests explicitly keep zero goal relevance even when run against a trusted catalog that contains a mapping. Unknown future goal pins remain decodable/read-only, preserving the original exact checkpoint and receipts. No exercise, generator, scorer, bank, or SwiftData schema changes are made.

## Exact source ownership

Six existing files only:

- `Sources/Adaptive/EditorialBandEvidenceV1.swift`: optional authored alignment and identity guard.
- `Sources/Adaptive/NFEditorialPracticePolicy.swift`: optional preference/trace types, V5 support, consistency checks and controller trace publication.
- `Sources/Persistence/NFLocalSessionRepository.swift`: reviewedSelection inputs and narrow cold goal validator. No acceptAdaptiveItem, actor publication, lock or generic checkpoint changes.
- `Sources/Persistence/PersistenceModels.swift`: narrow new beginSession pin capture from actual profile goals. No dashboard/attempt/restore mutations.
- `Tests/EditorialBandEvidenceTests.swift`: 2 pure methods.
- `Tests/LocalLearningLifecycleTests.swift`: 6 real-store methods in the existing controller test class.

The draft base includes the integrated V4 scope fingerprint and exportArchive-property fixture correction. Apply only the generated narrow hunks; preserve concurrent generator frame, dashboard, and async acceptance changes. No catalog strings, new source files, project generation, or startup changes are required.

## Added test methods

1. `testAuthoredGoalRankingUsesKnownExplicitIntersectionWithoutProficiencyOrDuplicateWeights`
2. `testAuthoredGoalManifestRejectsConflictingOrPartialObjectiveMappingsAndKeepsLegacyNilBytes`
3. `testActualAuthoredGoalPreferenceRanksOnlyAfterMixedCoverageAndNeverRaisesInitialBand`
4. `testActualGoalPreferenceIsFrozenAcrossProfileEditReplaceNextAndPersistentColdReplay`
5. `testActualGoalSelectionRejectsStalePublicationAndForgedTraceBeforeConsumingAnotherSlot`
6. `testActualEmptyKnownGoalsAreZeroPreferenceAndLegacyPinsDoNotAcquireGoals`
7. `testFutureGoalPreferencePinIsRetainedReadOnlyWithoutRewritingExactQuestion`
8. `testChangedAuthoredGoalManifestCannotContinueAnAcceptedRunAndUnknownProfileGoalsCannotLaunch`

These fixtures use synthetic trusted mappings over actual exact-bank exercises, actual AppStore profile APIs and native answer/Next/Replace paths, disk reopen, stale-revision refusal, valid-but-forged preference trace refusal, and exact retry. They confer no review authority on shipped items.

## Verification status and limits

`swiftc -frontend -parse` for all six files and `git apply --check` are the only checks performed by this agent. No builds or test execution have been performed. Root must compile and execute the eight new methods, existing pure/controller suites, and applicable native checks against a recorded source input.

Goal mappings require actual authored admissions before the released application can rank using them. This is a concrete remaining external content gate; the implementation does not supply unsigned mappings. Preference ranking does not close unrelated adaptive/evidence obligations or make a new calibration claim.

For the separate async Next package, the current sync acceptance replay is reused, but external core-only quarantine/history mutations need an epoch/ticket fence during the worker await. That independent review finding was sent to Experience and root; this patch does not alter their publication regions.

## Executed verification

On source `54cd410a`, five of six new actual-store goal methods and one pure method passed within223/225 focused tests. The two remaining fixture assumptions were corrected without changing production: JSON Set arrays are compared by exact canonical semantics, and the valid Next path calls the runtime to carry prior outcome history. Both corrected methods pass in an actual2/2 Mac run on `cbb90bfc` (8.411s). Full-suite execution covering the final combination remains required. The older due/legacy fixture now freezes local routing identity before acceptance and passes on54cd.

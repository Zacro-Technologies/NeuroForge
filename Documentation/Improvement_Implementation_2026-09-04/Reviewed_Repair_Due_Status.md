# Declared reviewed repair and due slots — scratch handoff

This package connects existing retention scheduling to actual one-item reviewed selection, capture and runtime calls. It adds no production admission or reviewed-content approval. The released registry remains empty.

## Compatibility and authority

- A new optional `NFEditorialDemandRecord.reviewContract` declares an exact reviewed scope, all actual scorer component IDs, compatible sibling structures and allowed probe/repair/delayed roles. It is authenticated by the existing external admission manifest and exact exercise digest. Generic response IDs never imply compatibility across undeclared structures.
- Only newly accepted requests whose authenticated inventory contains this contract use `EditorialLiveControllerV4` / `EditorialMixedControllerV4`. Missing contracts retain V3; V1–V3 receipts are never upgraded or backfilled. Default legacy bank recipes and generator versions do not change.
- V4 freezes one `reviewAssignment` with the candidate, compatible condition group, effective origin identity/digest, exact entry/rung/due day and displayed-explanation fact. Existing evidence/CAS, writer-generation, receipt replay, timing receipt and full materialization validation remain authoritative.
- `reviewFeedbackDigest` is captured at the immutable prepared-result boundary. A writer-fenced visible committed-feedback acknowledgement records a bounded, idempotent local presentation fact. This proves displayed explanation only, never understanding.
- Actual role-bearing commits project a practice probe, independent immediate repair, or delayed-check observation only if their captured conditions still match the selected role. A display-timing change preserves the typed practice answer but does not claim it satisfied the earlier review conditions.

## Selection and runtime behavior

Normal eligible Next can choose a fresh same-scope repair after an actual failed original and displayed feedback, or a genuinely due fresh sibling after a past independent origin. Scalar corrections, unknown help/tool/locale conditions, protected/source/self-report history, invalid or quarantined origins cannot supply role authority. Freshness is checked against both scoped semantic exposure and the accepted ledger.

Normal review allocations are bounded by 30% of the session estimate and five accepted review slots; consumed replacements also count. For an explicit count session, the conservative estimate uses the fixed request count and minimum duration across exact authenticated catalog contracts, including unavailable inventory so depletion cannot expand the allowance. Mixed required coverage still precedes review priority. A count-one explicit repair may use the full selected review budget.

`beginEditorialRepair(from:commandID:command:)` uses the current owner generation, acknowledged exact original and canonical launch. The runtime’s existing similar-question action takes this path for a failed declared V4 task, preserving a retry command ID and releasing the original writer only after acceptance. There is no fallback into unrelated practice when the declared repair is unavailable. Current task labels distinguish practice, immediate repair, delayed check and changed review conditions. Timing remains independent.

Immediate repair success cannot advance a retention rung. It clears the repaired criteria and schedules a later check using the existing 1/3/7/14/30-day ladder. Only a due independent delayed sibling can advance one rung.

## Persistence and deletion

The new local explanation table is bounded to 4096 and validated with cancellation checks and explicit non-inlined boundaries. It is stripped from portable archives; portable adaptive receipts are already stripped. A historical capture may retain its immutable nested role witness and hashes, but those cannot regain local authority without the accepted local receipt graph.

Linked deletion removes origin facts. If deletion of an origin or any other answer removes the originating run’s authority, dependent review sessions become recovery-only while retaining their exact current checkpoint and retired drafts. Dependency propagation also invalidates later descendants. Deleted-run tombstones and anonymous consumed positions remain. No original AttemptRecord is edited and no duplicate score/XP is created.

## Changes and verification

Eight existing source/test files; no new source file or project generation. Seven new tests: two pure scheduling/condition tests and five actual AppStore tests covering explanation acknowledgement, repair commit, delayed commit, cold receipt replay, stale effective-origin refusal, V3 non-backfill, explicit repair writer fencing, and direct/indirect linked deletion. Parser and patch-application checks only; parent must compile and execute. Content independent review is pending and must not be described as completed.

The patch preserves the integrated per-receipt timing condition and effective timing override changes, async Submit machinery, coordinate15 request copying and background validator cancellation/isolation.

## Remaining scope

This closes declared-slot ranking and live capture/publication for supported authored contracts; it is not full SCH-008 queue completion. Existing compatibility reminder queues remain explicitly legacy. A dedicated reviewed queue/history UI, explicit reviewed deferral controls, richer criterion-specific explanation presentation and the transient repaired-in-session status display remain separate work. Production reviewed inventory still requires genuine external admission; no unsigned catalog is enabled.

## Pre-execution review correction

Independent source review found that reusing a scope ID with changed criterion or sibling declarations could carry over an old retention rung. Supplement `bdb808a2` adds the exact length-delimited authored compatibility digest to declared retention keys in both reducer and selection. Legacy nil-contract keys remain unchanged. A new regression asserts the old entry stays exact while the changed contract starts at rung zero. Full app tests remain pending.

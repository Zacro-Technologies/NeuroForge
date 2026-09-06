# Activity examples, demand and duration preview

UX-013 requires an example or miniature preview, estimated duration and understandable challenge setup. This package adds an authored, unscored task-structure example for every one of the 58 current catalog activities. It also projects the actual admitted demand and duration ranges for reviewed choices. The released registry remains empty; the original practice path gets an example and an explicit unknown-duration message, never an inferred reviewed band.

## Scope and application

Apply `task-structure-preview.patch` to four existing files and add the 70 EN/JA entries in `catalog-entries.json` entrywise, preserving existing translations. No new source files, build/project generation, saved schema, exercise metadata or recipe version changes. This is independent presentation content; retained questions and scoring contracts are unchanged.

The patch is freshly rebased on root's integrated unavailable-choice scope/quarantine repairs plus net14. It preserves the new validated net scope mapping, launch defaults and catalog summary. The net example now covers face relationships, orientation and validity rather than claiming every new question asks for an opposite face.

## Important boundaries

- Miniatures contain roles, placeholders and response actions. They never display an unused question's actual prompt, numeric values, answer choices, reference, evaluator or solution. Ordered-task examples avoid giving the correct order. Merely viewing a preview does not create a session, consume a bank position, change exposure, or produce evidence.
- Reviewed preview aggregates come only after existing exact-digest admission. They contain relevant-given, extra-detail and missing-given count ranges, plus bounded authored response-duration ranges. They do not forward raw quantity-domain prose, misconceptions, keys, prerequisite IDs or unrelated source text.
- When candidates are eligible, the displayed range uses that eligible set. Automatic demonstrated/recent targets further restrict the preview to their exact initial comparability group. The actual selected questions still come from prepare/accept with fresh eligibility and evidence checks.
- Planning estimates use the common ordinary transition/feedback allowance and the actual effective timing preference. Untimed and elapsed-only give identical demand and duration projections. The estimate is labeled editorial planning, not a deadline, calibration result or promise about learner speed. Notes/pauses may take longer.
- Missing or unsafe ranges stay unavailable, including finite huge values that cannot be safely converted. Zero/over-limit question counts cannot manufacture a duration. Existing original activity five-minute defaults are not rebranded as accurate forecasts for arbitrary counts.
- A mixed run shows one clearly labeled example format. Explicit graph construction has its own brief structural description. No extra controls or selection mutations are added.

## Tests supplied (not executed by this agent)

Four new DefaultContentCatalogTests methods:
1. Every catalog ID has an explicit distinct EN/JA placeholder example; unknown IDs have no fallback claim.
2. Actual admitted preview returns expected givens and 10–40 second response range, yields a 54–144 second planning range for three ordinary items, and preserves the complete 13-model raw census plus local archive. Untimed/elapsed ranges are equal; no prompt or digest is copied into example text.
3. Evaluator-like canaries in demand prose do not enter the projection; missing, huge and out-of-conversion-range durations stay unavailable, with no clamping claim.
4. Released-empty catalog still has readable original activity examples but cannot gain reviewed demand/duration/evidence.

Parser validation and current `git apply --check` pass. Actual Mac/iOS compilation and execution remain root-owned. Native example and duration labels have `train-task-structure-example` and `train-task-duration-estimate` identifiers.

## Remaining gates

The examples are product-authored task structures, not reviewed low/high calibration examples or empirical timing studies. Real reviewed admission and QA acceptance still require the specification's external content evidence. No claim is made that the unsigned catalog now has measured bands or a validated completion-time distribution.

## Root execution

All four new preview regressions pass in the complete1315/1315 Mac run on6485e708. This includes all58 EN/JA examples, admitted demand/duration bounds, read-only raw census and unsafe-range refusal. Native layout acceptance remains.

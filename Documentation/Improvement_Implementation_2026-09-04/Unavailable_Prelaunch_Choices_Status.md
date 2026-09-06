# Reviewed prelaunch unavailable-choice retention

This package changes new-launch preview and UI only. It does not modify admission, saved requests, selection/override receipts, scoring, V1/V2 initial-target proof, timers or the empty released registry.

## Behavior

- A selected objective/family/band is pinned to its activity, field, content locale, profile and reviewed catalog identity. It remains selected through count increases, exhausted inventory, quarantine, changed prerequisites or settings, scope/locale changes, and failed/unavailable registry refresh. A recovered matching choice regains its current availability; no automatic fallback is selected for the person.
- All actual authenticated family/band contracts remain informative choices even when hard filters leave zero candidates. Reasons distinguish used inventory, exposure, quarantine, prerequisites, timing, unknown verification and unsupported scope. Unsupported bands are listed without inventing demand or review approval.
- Automatic continues to use the shared demonstrated initial-target policy and exact compatibility group. Its target remains unavailable when exhausted; it never silently becomes B1. If no reviewed B1 exists, the cold B1 preference is an explicitly unsupported Automatic placeholder, with no reasoning-step or eligible-band claim.
- Smaller-count alternatives only start a positive verified count. Start0 is impossible. A general mixed run is still one-item admission; per-family full-count shortages do not falsely promise or deny its later response-dependent path.
- A concrete activity may explicitly return to its original difficulty settings. The action clearly leaves reviewed-band selection and discloses Untimed when leaving timed fluency. Timing otherwise remains unchanged. Legacy difficulty copy explicitly says the setting is not a reviewed B1–B4 level.
- New menus put the 44pt minimum inside their native label; rows and reasons remain readable/accessibility-labeled. Existing public graph construction route remains intact.

## Integration

Apply `unavailable-choices.patch` (three existing files). Add missing keys from `catalog-entries.json` entrywise to EN/JA; preserve existing translations. No project regeneration or schema migration.

The patch is based on current source after ADP-006 event-order/future-pin fixes and solidSection13 mapping. The merge retains those source changes and root's canonical raw capture/read-only fixture fixes. No other owner hunks are reverted.

## Verification supplied

Parser validation and `git apply --check` only; root owns actual compilation/execution.

Five new methods in DefaultContentCatalogTests:
1. Exact B2 persists through larger count, current quarantine, rejected launch without file mutation, and resolved quarantine.
2. Selection persists through registry loss, failed preview and changed field; explicit nil is the only clearing action.
3. No inferred reviewed B1/B4 when only actual B2 contracts exist; explicit B2 still launches.
4. Consumed B2 remains visible at zero after actual commits; Automatic keeps recent B2 rather than lowering, and no zero-question launch is allowed.

5. Two real populated activity catalogs deliberately share the same band ID; activity/profile/catalog identity, and isolated field/locale changes cannot reattach the old selection. Explicitly selecting the new valid choice restores Start.

The existing prerequisite test now expects an explanatory disabled B3 row while retaining its failed-launch and unchanged-cursor assertions. Actual metadata fixtures are trusted synthetic tests, not signoff of released questions.

## Remaining follow-up

Substantive structural examples and expected-duration/demand preview are the next separate package. No current/unused prompt, evaluator or answer is disclosed by this package. Released reviewed admission remains an external content gate.

## Independent review

Content found a same-ID context collision in the initial candidate; this final patch fixes it with NFEditorialPrelaunchScope and the fifth regression. Count and timing are intentionally excluded from the scope identity because the learner can adjust them explicitly; refreshed feasibility still checks the exact timing contract, and untimed/elapsed do not change demand. No independent execution is claimed.

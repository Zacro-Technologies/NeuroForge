# Mixed initial targets and truthful next-item availability

This scratch patch depends on the substantive task-preview package (final aae1969e). It changes three existing files only: editorial policy, Train detail, and LocalLearningLifecycleTests. No working-tree edits, build or project generation were performed.

## Concrete corrected behavior

ADP-006 requires same-objective/compatible-family initial targets and matching reasons; ADP-010 keeps per-family controls; SCH-002/003/004 preserve hard constraints, mixed-family variety and explicit shortages. The old new-launch `sessionPin` filtered every automatic family through the existence of a B1 admission before asking V2 for its actual target. That omitted a legitimate higher-only family even after authentic recent or demonstrated success. New automatic pin construction includes every admitted band; the existing V2 reducer still selects each family's target. A cold family with no B1 remains explicitly unavailable, and other families may supply the next mixed item. Explicit user bands retain their exact band filter. Nothing rewrites an already frozen schema1/2/3 pin or its receipts; no controller/evidence thresholds changed.

The new read-only `NFEditorialMixedStartingPreview` shows each family's automatic target, exact initial reason, actual reasoning-step range when reviewed, and next-item availability. It is capped by the existing 32-family authority limit. Train initially shows four rows with an explicit 44-point Show all button. It promises neither question order nor a full requested count. It never displays a shared mixed B-level. A chosen explicit family still uses the existing full-count eligibility/shortage UI.

The mixed preview's overall feasibility now uses the next eligible item, not a requirement that any one family fill the whole count. Consumed or quarantined targets are not lowered. The production registry stays empty, so this card never invents reviewed bands in released practice.

## Source tests added (not yet executed)

Three `EditorialLiveControllerPersistenceTests` methods:

1. New automatic scopes include an actual bank-bound B2-only family; explicit B2 still narrows to the chosen family; a saved legacy pin decodes/re-encodes unchanged rather than acquiring new scopes.
2. A real native B2 commit produces effective admitted history. Read-only mixed preview shows that family's B2/recent reason and another family's B1/cold reason; both have less supply than the full requested count. Raw 13-model census and local archive bytes remain unchanged. Actual mixed first decisions match those per-family targets, then genuine repository/core reopen retains the exact pins/decisions and no new attempts.
3. A cold B2-only family retains unavailable B1, while another family with one B1 can begin a ten-question mixed run. After that real answer, finite shortage retains the exact feedback/question/count with one consumed slot and no invented continuation. A new preview reports no next supply and keeps both B1 targets.

Nine EN/JA keys are in `catalog-entries.json`. Parser and patch checks are reported separately from actual execution; root owns Mac/iOS compilation and native validation.

## Remaining concrete engineering seams from this audit

- Live selection candidates currently leave `dueRepairPriority`, `goalRelevance`, and `observedWeakCriterionMatch` at their zero defaults (`NFLocalSessionRepository.reviewedSelection`). The lexicographic reducer fields exist, but priority inputs need an authenticated, criterion/structure-compatible live projection and receipt/CAS coverage. No claim is made that the priority projection is complete.
- Accessibility compatibility is still represented by default-true candidate flags in this native admission subset; any new accessibility-specific content selection needs an explicit capability/request contract rather than a guessed inference.
- Protected initial suggestions remain gated on a real admitted protected protocol; creating a suggestion from legacy holdout metadata would fabricate authority.
- Historical/emergent content review, paired-band editorial review and empirical duration/pilot evidence remain external gates. Static preview examples do not close them.

## Root execution

All three mixed starting-target regressions pass in the complete1315/1315 Mac run on6485e708. Actual higher-only history, cold unavailableB1, single-next shortage and retained receipts/pins are verified.

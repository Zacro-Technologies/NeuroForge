# 03 — Adaptive learning, evidence and scheduling

This chapter specifies the behavior that replaces nominal difficulty labels with real question demands, keeps learning records faithful, and turns practice into a coherent sequence of challenge, help, correction and later review. It is an implementation specification, not a claim that the proposed thresholds are scientifically validated.

The numerical thresholds, band boundaries, scheduling intervals and decision rules below are **proposed product defaults pending editorial validation and learner pilots**. They must be versioned together. They are not normative scores, clinically meaningful cutoffs, an established forgetting curve, or proof of generalized cognitive improvement. Ship one authoritative policy implementation, `EditorialBandEvidenceV1`, rather than retaining separate incompatible online and history reducers.

Related audit findings: [QA-06, QA-07, QA-09, QA-10, QA-15 and QA-16](../QA_2026-09-04/README.md). QA-06 demonstrated that difficulty 0.2 and 0.9 currently produce the same scientific-notation problem; QA-07 demonstrated concentration in a few mechanics; QA-09 concerns resumed timing and assistance; QA-10 concerns answer leakage; QA-15 concerns timing and challenge being coupled; QA-16 concerns durable estimates ignoring difficulty.

## 1. Outcomes, boundaries and vocabulary

<a id="adp-001"></a>

### ADP-001 — Make the delivered question, the explanation and the record agree

A difficulty change must alter reviewed demands in the actual delivered exercise. Setting a floating-point property, changing the item ID, shuffling options, changing color, or replacing a field noun does not satisfy this requirement. A learner who chooses Harder must encounter a concretely different task demand, such as an additional dependent reasoning step, a less familiar representation, closer but still distinct distractors, or a more demanding quantity range.

Separate these five concepts in models and UI:

| Concept | Meaning | Must not be presented as |
|---|---|---|
| Current practice target | Band the next selected question is intended to exercise | Demonstrated proficiency or a promise of success |
| Demonstrated practice band | Highest band with the specified recent independent evidence for a defined objective and activity | Mastery of an entire lab or general intelligence |
| Protected check result | Performance and coverage on reviewed protected content under recorded conditions | A percentile, IQ score, diagnosis or direct comparison with other learners |
| Evidence coverage | Quantity, breadth, recency and conditions of usable observations | Precision of a psychometrically calibrated latent ability estimate |
| Practice XP and participation | Participation rewards and completed activity | Ability, learning improvement or extra weight in any skill reducer |

The word “standard” in an internal evidence eligibility flag means eligible for the app's built-in skill records. It does not mean that an assessment has been standardized against a representative population. Normal UI should prefer “skill evidence,” “practice result,” “starting check” and specific descriptions of the demonstrated task.

<a id="adp-002"></a>

### ADP-002 — Use a shared, explicit item contract

Every generated or authored item admitted to adaptive built-in practice must carry the following immutable fields or equivalent typed fields. The content chapter owns authoring and validation; this chapter owns selection and evidence use.

| Field | Required meaning |
|---|---|
| `objectiveID` | Specific intended learning objective, more precise than the lab |
| `familyID` | Reviewed activity family or mechanic |
| `structureID` | Underlying problem structure; renaming entities or shuffling options preserves it |
| `semanticFingerprint` | Canonical identity of the substantive problem and authoritative answer contract, ignoring presentation-only changes |
| `editorialBand` | B1, B2, B3 or B4, assigned using the reviewed demand contract |
| `demandVector` | Explicit demands described in ADP-003, including task-specific parameter values |
| `bandContractVersion` | Version of the editorial rules and permitted parameter domain |
| `calibrationStatus` | `editorial`, `pilotObserved`, or `empiricallyCalibrated`; never inferred from the old difficulty float |
| `calibrationVersion` | Optional independent calibration dataset/model version; absent for editorial-only content |
| `independentEligible` | Reviewed as capable of producing independently scored skill evidence in its unassisted presentation |
| `protectedEligible` | Additionally approved for the protected pool, including leakage, exposure and form checks |
| `assistancePolicy` | Which tools are permitted, which presentations count as assistance, and what changes evidence eligibility |
| `answerContractVersion` | Authoritative grading/rubric version, separate from presentation version |
| `expectedDurationRange` | Reviewed starting duration estimate, with documented scope and sample basis |
| `representationIDs` | Actual stimulus and response representations, not only a renderer name |
| `prerequisiteObjectiveIDs` | Prerequisites needed for the item to be meaningful |

An item must not acquire a different band merely because the session requested one. A request selects a permitted band-specific contract; the generator returns the band it actually fulfilled. If it cannot fulfill it, selection handles an unavailable band explicitly. The final record preserves both `requestedBand` and `deliveredBand` plus a reason for any approved fallback.

Legacy `difficulty.overall` values are uncalibrated descriptive metadata. They must not be converted into IRT difficulty parameters, treated as observed item success probabilities, or used to bridge old and new proficiency estimates. Existing evidence may remain visible as legacy practice history subject to the correction policy; it does not automatically establish a band under this specification.

<a id="adp-003"></a>

### ADP-003 — Represent difficulty on multiple axes

The global band is an editorial ordering within a declared objective/family, not an arithmetic average that makes unrelated activities comparable. Use this minimum demand vector:

| Axis | Required representation | Examples of real changes |
|---|---|---|
| Reasoning dependency | Integer dependent transformations or decisions, with an authored solution graph | One proportion versus choosing the relevant proportion and using it in a second calculation |
| Quantity demand | Family-specific typed ranges and arithmetic constraints | Integer versus fractional ratios; scientific-notation exponents; exact versus approximate quantity |
| Representation demand | Number/type of mappings and familiarity prerequisites | Table to claim; diagram to coordinates; prose to state invariant |
| Distractor discrimination | Authored misconception classes and verified distance/distinctness | Obvious wrong operation versus two plausible methods differing in one assumption |
| Abstraction | Concrete, schematic or abstract contract with declared prerequisites | Observed cases versus a general conditional claim |
| Context/information selection | Count and role of relevant, irrelevant and missing givens | All givens stated versus selecting relevant evidence or stating a bounded assumption |
| Tool/scaffold condition | Essential givens, optional hints, worked steps, permitted scratchpad/manipulation | An unassisted item with available optional help remains the same independent contract; using help changes evidence |
| Domain prerequisites | Named prerequisite concepts, not the learner's degree or age | Fractions, conditional probability, loop semantics, confidence-interval interpretation |

Time pressure is a **separate condition**, never an axis used to inflate a content band's difficulty. Language verbosity, poor formatting, tiny targets and confusing controls must never be counted as legitimate difficulty. Reading demand is recorded for accessibility and duration planning; unnecessary reading is removed.

Changing a scaffold on an already presented item creates an assistance event, not a silent transformation into a lower-band independent item. A separate simpler problem is a new item with its own identity.

<a id="adp-004"></a>

### ADP-004 — Define B1–B4 as reviewed task bands

Use the shared names below. The band labels describe the questions; do not label the person “Developing” or “Advanced” solely because an item at that band was selected.

| Band | User-facing name | Default editorial contract |
|---|---|---|
| B1 | Foundation | One core relationship or operation, explicit relevant givens, familiar representation, distinct misconception-based alternatives, minimal prerequisite load |
| B2 | Developing | Two dependent steps or one nontrivial representation mapping, familiar prerequisites, some selection of relevant givens, plausible distinct alternatives |
| B3 | Challenging | Several dependent decisions, an unfamiliar but taught representation or assumption choice, closely competing defensible-looking alternatives, explicit checking of constraints |
| B4 | Advanced | Interacting constraints or competing models, multiple representations or boundary cases, justification/verification of a solution, reduced incidental scaffolding while preserving all essential givens |

These are starting authoring rules. A family may use a reviewed band mapping that differs in exact step counts, provided its contract states why and shows representative items. It may support only a subset of bands. An activity with no defensible B4 must report that limit; it must not manufacture B4 by using larger numbers, hiding instructions, or imposing a deadline.

#### Family-level editorial examples

These examples define meaningful band transitions for implementers and reviewers. They are proposed question contracts, not claims that the examples have already been added or validated.

| Family/objective | B1 Foundation | B2 Developing | B3 Challenging | B4 Advanced |
|---|---|---|---|---|
| Mental multiplication by decomposition | Two-digit integer times a one-digit factor with one useful split | Two-digit factors where compensation or distributivity saves work | Select between two valid strategies, then calculate with a carry/sign/decimal constraint | Plan and verify a chain where intermediate magnitude and representation choices matter; still permit exact mental strategies |
| Scientific notation | Normalize a positive integer coefficient and preserve magnitude | Multiply/divide normalized quantities with exponent bookkeeping | Compare magnitudes or repair a multi-step calculation with unit/exponent constraints | Combine quantities from different representations and diagnose which transformation violates magnitude or units |
| Estimation | Choose a plausible range from explicit scale information | Produce an estimate using one stated decomposition | Choose reasonable assumptions, combine two factors and state a defensible range | Compare sensitivity to alternative assumptions, identify the dominant uncertainty and revise the range |
| Probability | Natural-frequency counts with one relevant denominator | Convert between representations or compare base-rate and conditional information | Combine evidence with base rates and distinguish competing conditionals | Analyze decision consequences under multiple stated scenarios without assuming a single unsupported probability |
| Spatial transformation | One labeled 2D rotation/reflection with explicit axes | Compose two transformations or map between view and coordinates | Distinguish non-equivalent 3D orientations or projections using labeled faces/axes | Solve a constrained multi-view or cross-section problem and reject a plausible impossible interpretation |
| Scientific evidence | Match a directly observed pattern to a limited descriptive claim | Distinguish description from causal explanation using design information | Compare competing explanations and choose a discriminating intervention | Integrate a figure, method constraint and uncertainty statement; identify what a follow-up result would and would not resolve |
| Logic/debugging | Trace a short straight-line state update | Trace a conditional/loop boundary or diagnose a stale derived value | Choose a minimal repair that passes meaningful boundary cases | Distinguish multiple plausible repairs, preserve an invariant and supply a counterexample to an invalid alternative |
| Built-in retrieval | Recall a specific reviewed fact/relation with an unambiguous response contract | Reconstruct meaningful slots or discriminate a near misconception | Recall the relevant principle from an unfamiliar cue and apply one consequence | Integrate several reviewed facts to explain or reconstruct a relationship without receiving the answer in the prompt |
| Transfer | Change one representation while holding the learned relation fixed | Apply the relation to a new surface context and explain the mapping | Check whether the relation's assumptions still hold in an unfamiliar context | Coordinate multiple relations/representations and identify a boundary where direct transfer would fail |

B4 is not “university-level” by default, and B1 is not “for children.” Formal prerequisites and observed activity-specific evidence determine suitability. Domain framing alone does not raise a band. A new field name on rate × time is not advanced transfer.

<a id="adp-005"></a>

### ADP-005 — Test difficulty through its actual demands

For every admitted band transition, the content validation layer must supply:

1. A paired low/high example with the same objective and a reviewer explanation of which demand changes.
2. Executable constraints checking the parameter domain, answer validity, required steps, unique alternatives and necessary representations.
3. A semantic comparison showing that changing the band changes the substantive task where the family supports multiple bands.
4. A counter-check that timing-only changes preserve band, objective, answer contract and demand vector.
5. Pilot observations by band when available, without relabeling an item as calibrated from a very small convenience sample.

Some randomly selected examples at adjacent bands may look similar. The generator must still satisfy their different authored contracts; “not identical” alone is not a sufficient test. For instance, replacing 36 with 37 while leaving the required reasoning identical does not establish a B1-to-B4 transition.

## 2. Cold start and user control

<a id="adp-006"></a>

### ADP-006 — Start from low-stakes evidence without demanding a long baseline

A new learner can start useful practice immediately. The starting check is optional and resumable. Education stage, interests and goals choose framing, prerequisites to offer, and the first activities; they never establish proficiency or assign a low score.

Cold-start behavior for a selected family:

- If no relevant independent observations exist, default to B1 Foundation, untimed, with optional help visible.
- Offer “Start with more challenge” as a single optional control. Choosing it starts at B2; an explicit band selection may start higher where prerequisites and content are available. This is a user preference, not evidence.
- The first two independent answers are exploratory. No demonstrated band is awarded and no automatic upward shift occurs before four eligible current-band observations.
- If a valid recent protected check or a demonstrated practice band exists for the **same objective and compatible family**, use that band as the initial target. Do not transfer a strong arithmetic result to scientific reasoning, or a strong coordinate-rotation result to all spatial activities.
- If there are observations but insufficient coverage, resume the most recent successfully practiced target band; show “Finding a comfortable challenge” rather than a numeric ability estimate.
- After 30 local days without relevant practice, start with one review probe at the prior band or one below if the learner chooses Easier. Inactivity does not automatically lower the historical demonstrated band. It changes recency and the recommendation to check again.

Store why the initial target was chosen: `coldStartDefault`, `userRequested`, `protectedCheckSuggestion`, `recentPracticeTarget`, or `refreshProbe`. The displayed explanation must match this reason.

<a id="adp-007"></a>

### ADP-007 — Keep challenge, timing and assistance independent

The session configuration has three independent fields:

```
ChallengeMode = adaptive | fixedBand(B1...B4)
TimingMode = untimed | elapsedOnly | timedFluency
AssistanceMode = available | protectedRestricted
```

“Easier” and “Harder” are actions on the current target band, not timing modes. “Keep this level” selects `fixedBand(currentDeliveredBand)` for the remainder of the activity session. The default scope of an override is the current session; a separately labelled preference may persist it for that activity.

A timing-only setting change does not regenerate or replace the current question and does not change the requested band, selected family, underlying quantities, rubric, or answer. Hiding a timer changes presentation only. Untimed disables timing-based evidence and pressure without reducing academic demand.

Timed fluency is appropriate only for reviewed fluency families with a clear accuracy-first prerequisite. A first proposed gate is at least eight recent independent, untimed, fully correct attempts at the same family/band across two sessions, no unresolved repeated conceptual error, and explicit learner choice. This gate is a product safeguard, not a clinical rule. Failing the gate leaves untimed or elapsed-only available; it does not lower band or XP. Other reasoning families may display elapsed time for orientation but should not silently become speed drills.

<a id="adp-008"></a>

### ADP-008 — Apply overrides at a safe boundary

When the learner chooses Easier/Harder on an unanswered item, present two direct actions: “Apply to next question” (default) and “Replace this question.” Replacing records an exposure and an `itemReplacedByUser` event; it does not score the abandoned answer as wrong or allow the same protected item to be rerolled. The current draft remains in the original attempt/session record where applicable.

An override changes the target by one supported band. If the adjacent band is unavailable, show the highest/lower available band and a concrete reason; do not silently jump several bands. A direct band picker can explicitly select any available band. Neither action creates skill evidence, promotes demonstrated proficiency, changes XP, or changes timing.

Protected checks do not offer Easier/Harder, reroll or answer-revealing hints. They offer pause/save, an accessibility route, or exit with progress retained. The check's selector chooses its next item from its fixed protected policy.

<a id="adp-009"></a>

### ADP-009 — Explain the change in learner language

A one-line optional explanation accompanies an automatic change, without a modal interruption:

- “You solved the last four independently. The next problem adds one reasoning step.”
- “Let's practice the underlying step before combining it with another.”
- “You chose a harder question. Your recorded level has not changed yet.”
- “This activity has no reviewed Advanced questions yet. Continue at Challenging or choose another activity.”

The explanation must identify the actual delivered change. A generic “AI personalized this” message is forbidden for deterministic policy decisions. Expose the underlying event and policy version in technical details, not the primary learning flow.

## 3. Authoritative practice state and update policy

<a id="evd-001"></a>

### EVD-001 — Reduce durable events into separate evidence channels

The shared reducer returns typed views of one append-only event stream. It never mutates old answers or mixes incompatible channels.

```
LearnerEvidenceState
  practice[objectiveID, familyID, band, compatibleConditionGroup]
  protectedCheck[dimensionID, formProtocolVersion, band]
  transfer[sourceObjectiveID, transferContractID, band]
  retention[objectiveID, familyID, band, delayClass]
  personalStudy[sourceOrSetID, objectiveID]
  confidenceCalibration[scope, conditionGroup]
  speed[familyID, band, inputConditionGroup]
  coverage[scope]
```

A correct transfer attempt can support its declared source objective only according to the reviewed transfer contract. It cannot mint a second full-weight independent observation in a broad Transfer score and in each source skill. Maintain one observation ID with explicit attribution; all derived views must reveal that shared origin. There is no combined cognition score.

The minimum reducer input includes the frozen item contract, original response, deterministic score and rubric parts, validity disposition, assistance/exposure events, response lock and confidence timing, attempt/session identity, event sequence, active time chunks, conditions, and semantic identity. See the persistence chapter for physical storage and correction records. This chapter requires those inputs; it does not prescribe competing migration records.

<a id="evd-002"></a>

### EVD-002 — Use `EditorialBandEvidenceV1` for both live and replayed results

The first implementation uses finite recent evidence grouped by the actual editorial band. It does **not** use a latent IRT theta or turn editorial bands into interval-scale numbers. Live session decisions and Progress read the same reducer output and policy version.

For a specified objective/family/band/channel, form the independent evidence window by applying eligibility, deduplication and condition rules, then selecting the last 20 eligible observations in the preceding 60 local days. Use durable decision time, not the machine's current time when replaying a historic decision.

Let `q_i` be criterion-based credit in [0, 1] for each retained eligible observation. Store:

```
n = number of retained independent observations
creditSum = sum(q_i)
recentMeanCredit = creditSum / n                  // absent if n == 0
fullCorrectCount = count(observation.isFullCredit)
semanticCount = number of distinct semanticFingerprint values
structureCount = number of distinct structureID values
sessionCount = number of distinct sessionID values
activeDayCount = number of distinct configured local training days
```

For ranking only, use the smoothed descriptive score:

```
planningScore = (1 + creditSum) / (2 + n)
```

The added 1 and 2 are explicit conservative starting constants for planning. This score is not a calibrated probability of future success, a posterior ability estimate, or a published confidence interval. It must not be shown as “your ability is 83%.” Promotion/demotion use the explicit rules below, not an unstated interpretation of this score.

Prefer exact rational criterion weights/credits and exact threshold comparisons. The evaluator supplies authoritative `isFullCredit` and `isZeroCredit` flags from satisfied criteria; the reducer never invents them by rounding a display percentage. In the pseudocode above, `fullCorrectCount` means the count of `isFullCredit`, replacing any approximate numeric shorthand. If floating-point arithmetic is unavoidable for a policy mean, `policyComparisonEpsilon = 1e-12` is permitted only to compare a computed mean with a documented threshold; it does not alter earned credit, convert partial criteria into full credit, create a zero-credit response, or excuse a scorer contradiction. Inputs must be finite and in [0,1]; invalid score payloads are ineligible pending recovery rather than silently clamped into a valid academic outcome. Stable accumulation order is mandatory.

#### Exact V1 window and condition defaults

The 60-day window consists of the decision's canonical local day and the previous 59 local days, inclusive. Future-dated observations do not enter that decision's window. All boundary calculations use the versioned stored day context and the canonical day policy; never reinterpret old active-day labels using a new time zone. A repeat-spacing threshold of 30 days is met when canonical day ordinals differ by at least 30. That spacing is only a necessary repeat control, not proof of independent novelty: an exact familiar item intentionally revisited remains a labelled review and cannot fill an unseen-probe or distinct-semantic demonstration requirement.

A compatible independent-accuracy group is an explicit tuple:

```
(evidenceLane,
 objectiveID, familyID, deliveredBand, bandContractVersion,
 scoringComparabilityID, stimulusComparabilityID,
 toolConditionID, localeComparabilityID, pacingConditionID)
```

The catalog supplies reviewed comparability IDs. If absent, use exact answer-contract version, exact stimulus/response format, exact assistance/tool policy, exact content locale and exact timing mode as separate groups; do not assume equivalence. A reviewed stimulus comparability group may contain the different substantive formats required by a family without claiming that arbitrary renderers are equivalent. Equivalent accessibility presentations use that reviewed group with their accommodation facts retained. Input modality is not, by itself, an ability penalty; it becomes an additional grouping key for clean speed. Changes to a comparability mapping require a versioned content/evidence disposition, never an unlogged merge of old buckets.

The clean-speed grouping extends this tuple with input modality, device class, input-editor version, latency-calibration version, timer visibility and timed-fluency target policy. Confidence grouping extends it with confidence-mapping version, binary-outcome definition and collection policy (`requiredProtected`, `requiredCalibration`, or `optionalPractice`). Required and optional confidence samples are not silently pooled. Missing compatibility metadata yields a separate unknown group with no cross-condition improvement claim.

<a id="evd-003"></a>

### EVD-003 — Define an independent observation before counting it

A response may enter the independent practice window only when all conditions hold:

1. Its built-in content and answer contract are valid and approved for independent use at the time of the effective validity projection.
2. A scorable response was committed once, with a stable observation identity and an authoritative rubric result.
3. No answer, worked step, or hint was used before that response lock. Essential givens and accessibility-equivalent presentations do not count as hints.
4. The response was not a retry of the same semantic problem after seeing its answer or feedback.
5. It was not skipped, abandoned, replaced, self-rated, or merely marked understood.
6. It is not a personal-source or arbitrary generated/self-check item being promoted into standard skill evidence.
7. Its condition group is compatible with the view being reduced.
8. It passes the repeat controls below.

A learner may use a scratchpad where the item contract permits it without invalidating untimed reasoning accuracy. Calculator, external search, revealing manipulators and worked examples must follow the item's explicit tool contract. When a tool condition is not known, preserve the result as practice history and exclude it from claims requiring independent conditions. Do not infer cheating from a fast response or a user-selected aid.

Repeat controls:

- The same `semanticFingerprint` contributes at most one independent practice observation to an objective/family/band window in 30 local days. Additional attempts remain history and may help a personal study queue.
- An exact same semantic item never establishes a fresh protected observation after exposure, regardless of elapsed time.
- Renamed contexts and shuffled options retain the same semantic identity.
- For band demonstration, at most four observations from any one `structureID` count toward the first eight. If a narrow family has only one reviewed structure, it may show independent practice accuracy but cannot claim broad structural coverage. Its UI scope must remain explicit.
- One attempt can supply multiple rubric criteria, but it counts as one exposure and at most one observation for promotion. Four graded fields on one problem are not four independent questions.
- Replayed duplicate commits and two-device copies share one observation ID and never count twice.

A changed mathematical quantity may create a new semantic item while retaining the same structure. This supports parameter practice but does not by itself establish transfer or breadth.

<a id="evd-004"></a>

### EVD-004 — Assistance produces a learning outcome, not an unassisted success

Assisted work remains valuable and visible. Store `assistedCredit`, the furthest hint/worked step revealed, the timing of each reveal and the final response. Do not replace it with zero, and do not treat it as an independent failure merely because assistance was used.

| Event | Independent proficiency | Next-question support | Review queue | Participation reward |
|---|---|---|---|---|
| Correct without help | Eligible under EVD-003 | Supports upward exploration | May schedule delayed review | Normal policy |
| Incorrect without help | Eligible credit, including zero | Supports repair/lower target under ADP-011 | Add misconception/repair entry | Normal policy |
| Correct after a hint | Excluded from independent window | Indicates useful scaffold; offer fresh repair item | Keep objective pending until independent check | Normal participation, never bonus ability |
| Worked solution revealed before response | Excluded | Offer a smaller worked step or fresh sibling | Schedule an independent follow-up | Reveal alone earns no answer XP; retain DATA-013 participation rules for separately completed eligible work |
| Self-rating “understood” | Excluded | Preference only | Personal reminder only | Never changes skill evidence |
| Accessibility-equivalent representation | Eligible if reviewed equivalent | No automatic easier band | Same objective; condition recorded | Same participation policy |
| Non-equivalent aid | Separate condition; no independent claim | Recommend compatible practice | Keep independent check pending | No penalty language |

If two of the last three presented items require help or are explicitly replaced as too difficult, offer a Foundation/underlying-step path. This is a support recommendation, not a score-based demotion. The learner can keep the current challenge. Do not translate hint use into an ability failure or silently lower the recorded band.

<a id="adp-010"></a>

### ADP-010 — Maintain a practice control state distinct from evidence

Per active objective/family session, maintain:

```
PracticeControlState
  initialTargetBand
  currentTargetBand
  challengeMode
  upwardChangesThisSession
  totalAutomaticChangesThisSession
  eligibleResponsesSinceLastAutomaticChange
  currentBandDecisionResponses[]   // independent observations since entry/change
  recentPresentedSupportEvents[]   // last 3 presentations, separate from evidence
  overrideScope
  decisionOrdinal
  selectedExercisePath[]
```

This is selection state. A change in `currentTargetBand` does not alter a demonstrated band or a protected result. It is safe to explore a harder question before enough evidence exists to certify sustained performance there. Entering a different band, whether automatically or by a learner action, clears `currentBandDecisionResponses` for subsequent decisions; historic evidence remains in its band bucket. Easier/Harder changes the starting target for the remaining session while preserving Adaptive mode; Keep this level explicitly changes to fixed-band mode. Manual changes do not reset automatic-change limits or presentation ordinals. A resumed session restores the control state and counters rather than treating resume as a new session with a new allowance.

<a id="adp-011"></a>

### ADP-011 — Apply a bounded practice staircase

Initial defaults for ordinary Adaptive practice:

- At most one automatic upward move per activity session.
- At most two automatic band changes of any direction per activity session.
- After an automatic change, require two additional independent current-band observations before considering another change. After that cooldown, evaluate the normal window thresholds; the cooldown does not reduce the three/four-answer requirements.
- An automatic change moves one supported adjacent band, never skips an unavailable intermediate band.
- No automatic change modifies the currently visible item, a committed response, or a user's fixed-band choice.

Upward exploration requires the last four eligible observations at the current band since that band was entered to have mean credit at least 0.875, at least three full-credit responses, and no individual credit below 0.5. The next band must have enough reviewed unseen compatible content for at least three independent probes. Success on one repeated structure does not establish demonstrated mastery even if these short-term rules allow a harder exploratory question.

Downward support requires the last three eligible observations at the current band since that band was entered to have mean credit no greater than one third, with at least two responses whose authoritative `isZeroCredit` flag is true. Move one band lower if available. At B1, remain at B1 and offer a worked example/prerequisite practice instead of inventing B0 or repeatedly failing the learner.

A one-off mistake, one skip, one slow response, low confidence or a pause never changes the target automatically. A repeated specific error may choose the next **same-band** repair structure before a threshold is reached. Learning from errors is not equivalent to raising question volume.

```
function decideNextPractice(state, committedEvent, evidence, pool, decisionContext):
    effective = evidence.apply(committedEvent)       // shared versioned reducer
    control = state.applyPresentationAndCommit(committedEvent)

    if control.challengeMode is fixedBand:
        requestedBand = control.fixedBand
        reason = "userFixedBand"
    else:
        requestedBand = control.currentTargetBand
        reason = "continueCurrentChallenge"

        if eligibleForPracticeDecision(committedEvent, effective):
            control.appendCurrentBandDecisionResponse(committedEvent)
            if changeLimitsPermit(control):
                if downwardRuleSatisfied(control.currentBandDecisionResponses):
                    requestedBand = adjacentLowerSupportedBandOrCurrent(pool)
                    reason = requestedBand changed ? "independentDifficultyPattern" : "foundationSupport"
                else if upwardRuleSatisfied(control.currentBandDecisionResponses)
                        and control.upwardChangesThisSession == 0
                        and pool.hasThreeUnseenIndependentProbesAtNextBand:
                    requestedBand = nextBand
                    reason = "independentSuccessPattern"

    constraints = hardConstraints(effective, control, decisionContext)
    candidates = pool.filter(constraints).filter(deliveredBand == requestedBand)
    selection = chooseByCoverageThenPriorityThenStableTieBreak(candidates)
    if selection is absent:
        return handlePoolShortageWithoutFalsifyingBand(control, requestedBand)

    return SelectionDecision(
        selection, requestedBand, selection.editorialBand,
        reason, evidenceDigest, policyVersion, poolVersion,
        deterministicTieBreak, control.afterDecision
    )
```

The upward rule is evaluated after the downward rule only for explicit determinism; the numeric conditions cannot both hold on the same relevant window. Store the rule inputs in the decision receipt so a support engineer can explain the action without rerunning mutable catalog state.

<a id="adp-012"></a>

### ADP-012 — Demonstrate a band using broader evidence than a short streak

For an objective/family/band, `demonstratedRecentPracticeBand` is awarded only when the last 20-observation/60-day window contains:

- At least eight eligible independent semantic items.
- At least two sessions on at least two active local days.
- At least two reviewed problem structures; at most four of the first qualifying eight may come from one structure.
- Mean criterion credit at least 0.8 and at least six full-credit responses among the qualifying eight or more.
- No unresolved validity issue that affects qualifying observations.
- The response-format coverage specified by the family contract. If two independent response formats exist and are part of the intended objective, include both. Do not invent a cosmetic format switch to satisfy this condition.

Use a deterministic qualifying set: traverse the recent window newest to oldest, respecting the per-structure cap until eight are selected; reverse it to chronological order for display. Evaluate all eight-observation demonstration conditions, including session/day/format coverage and credit, on this same qualifying set. Do not independently cherry-pick a favorable score set and a different breadth set. If more than eight are used in the displayed window, the band decision still uses this specified qualifying set and exposes both counts. This prevents implementation-dependent selection of a convenient favorable subset.

Do not infer demonstration of every lower band from a harder success. Prerequisite links may suggest appropriate practice, but unobserved bands remain unobserved. Do not average band numbers across unrelated objectives into a lab level.

A historical demonstrated band is not erased by one later error or by inactivity. Maintain `lastDemonstratedAt`, `recentSupportStatus` and `recommendedTargetBand` separately. Set recent support to `needsRefresh` after 30 days without qualifying evidence. If two later sessions on separate days produce a qualifying recent set below mean 0.6, mark it `notCurrentlySupported` and recommend a lower target; preserve the historical demonstration and its date. Use neutral wording such as “Your recent answers suggest reviewing the underlying steps.”

The 0.8 and 0.6 thresholds provide initial hysteresis. Pilot work must examine whether they cause repeated oscillation or inappropriate level retention. Changing them requires a policy version and replay/correction plan; do not silently reinterpret previous achievements.

## 4. Confidence, partial credit and truthful evidence

<a id="evd-005"></a>

### EVD-005 — Collect confidence only under a defined purpose

Confidence does not increase credit, promote ability, accelerate retention intervals, reduce question difficulty, or earn extra XP. It is optional context for ordinary practice and a separate metacognitive observation when collected before feedback under a specified protocol.

| Mode | Confidence behavior |
|---|---|
| Protected baseline/reassessment | Required inline before committing the answer; no preselected default; exact outcome/key remains undisclosed |
| Explicit calibration activity | Required inline before commit; protocol defines whether the later outcome is binary or graded |
| Ordinary scored practice | Optional inline; a deterministic one-in-five invitation expands the control; declining/ignoring never blocks submission |
| Timed Rapid Recall/fluency | Suppressed; neither pre-answer nor retrospective confidence is collected by default |
| Personal source/self-check | Optional study reflection; never standard calibration or proficiency evidence |

Choose exactly one invitation slot in each consecutive group of five ordinary-practice presentations, rather than using five independent random trials. With zero-based presentation ordinal `i`, let `g = floor(i / 5)` and `slot = H(sessionID, policyVersion, g, "confidence-invitation") mod 5`; expand the invitation when `i mod 5 == slot`. Use an independently salted stable hash. Determine the schedule before observing responses. Do not invite confidence only after difficult-looking questions or mistakes, because that would bias the recorded sample. Persist the invitation decision across pause/relaunch; repeatedly reopening must not reroll it. A short final group may contain no invitation. Ineligible timed-fluency/personal-study presentations do not consume ordinary-practice invitation ordinals.

Only a confidence value locked before any outcome/answer reveal enters calibration. The initial compatibility mapping is versioned as `confidenceCategoricalV1`: Guessing = 0.25, Uncertain = 0.45, Fairly confident = 0.72 and Certain = 0.92, matching current stored semantics. These are approximate categorical proxies, not measurements of an exact subjective probability. Numeric calibration diagnostics must disclose the mapping; ordinary copy must not imply certainty or precision from those numeric values. A later UI vocabulary/probability change receives a new mapping version and cannot be silently pooled with old samples. Post-outcome confidence, edited retrospective confidence and self-ratings remain reflections. In ordinary practice, display the current problem and answer while choosing confidence; do not replace the whole problem with a new screen.

For a binary scored outcome `y ∈ {0,1}` and a chosen probability mapping `c ∈ [0,1]`, descriptive calibration can report mean `(c - y)` and mean `(c - y)^2` over a defined compatible sample. Preserve the mapping version of named confidence options. Use the last 50 eligible pre-feedback observations within the current and previous 59 canonical local days for one compatible confidence group. Require at least 12 observations spanning at least two sessions before a user-facing descriptive calibration summary. The V1 summary is not a time-trend or improvement badge; stronger longitudinal comparison remains subject to EVD-011. Preserve the unselected/declined invitation count separately so an optional-practice sample is not presented as representative of every answered item. These are descriptive task-specific measures, not personality traits or a diagnosis of overconfidence.

For partial-credit tasks, confidence wording must match what is predicted. Default to “How confident are you that this whole answer is correct?” and use the rubric's full-credit indicator as `y`. Do not silently compare that confidence with fractional credit and call the result calibrated. A distinct graded-confidence protocol is a future separately reviewed contract.

<a id="evd-006"></a>

### EVD-006 — Treat partial credit according to the rubric, not the renderer

Every partial-credit schema must expose scored criteria with stable IDs, maximum credit and the deterministically earned amount. The aggregate `q` is the normalized weighted rubric result; absence of a required field is validation/incomplete state until the learner intentionally submits a permitted partial answer.

The reducer uses `q` for the same-band descriptive mean and staircase thresholds. It uses the full-credit indicator for full-correct counts. A 0.5 response contributes 0.5 once, not one full success, not an automatic zero, and not two observations because two criteria were scored.

A rubric can use criterion-level errors to choose a repair item. It must not infer an unobserved strategy from an answer's correctness. If strategy choice was never asked or logged, the state says `strategyUnknown`. The existing practice of inferring valid strategy use from a template name or any positive credit must not support a strategy-flexibility claim.

If the answer contract recognizes multiple mathematically or logically equivalent valid responses, those responses must receive the same criterion credit and lead to the same adaptive action. Content corrections that change credit enter through EVD-008; they never rewrite the raw response.

<a id="evd-007"></a>

### EVD-007 — Give uncertainty an honest, implementable meaning

Editorial-only content supports evidence coverage, not a psychometric standard error. Replace count-only “stable” interpretations with explicit coverage flags:

| State | Exact default condition | Example copy |
|---|---|---|
| No observations | No eligible independent observations | “Try a few questions to establish a starting point.” |
| Early observations | 1–7 qualifying observations, or only one session/day | “Based on 5 independent answers; more examples will help.” |
| Limited breadth | Enough answers but missing required structures/formats | “Your answers cover one problem structure so far.” |
| Recently supported | ADP-012 conditions met in the defined window | “Foundation questions demonstrated across two sessions.” |
| Needs refresh | Previously supported but no qualifying evidence in 30 days | “Last checked on 4 August; a short review is available.” |
| Not currently supported | Later two-session qualifying set falls below support threshold | “Recent answers suggest reviewing these steps.” |
| Evidence affected | Relevant observations are quarantined or under correction | “Some questions were excluded while their content is reviewed.” |

Coverage must expose counts by family, structure, format and condition. Twenty repeats of one easy pattern cannot narrow a displayed uncertainty band as if they sampled an entire skill. A figure labelled confidence interval or a numeric latent skill estimate remains unavailable until a separately validated model and calibration dataset exist.

<a id="evd-008"></a>

### EVD-008 — Make invalid content exclusions affect every derived view

A validity projection supplied by the correction subsystem identifies whether an item/semantic contract/version is valid, quarantined, superseded, retired, or invalid for a specified evidence use. The reducer and selector consume the same projection.

Required hooks:

- `canSelect(item, mode, validityRevision)` excludes known-invalid and quarantined content from new delivery, including semantic siblings affected by a shared faulty rule.
- `effectiveObservation(attempt, validityRevision)` returns eligible evidence, revised derived credit authorized by a correction record, or an explicit exclusion with reason.
- `rebuildDerivedState(affectedObservationIDs, policyVersion, validityRevision)` deterministically rebuilds practice targets, supported-band summaries, review queues, confidence summaries and speed/claim views that depended on those observations.
- `explainChangedResult(originalAttemptID)` points to the original answer and the correction/exclusion explanation. The UI does not blame the learner for a defective question.

If a quarantined item was the sole trigger for an upward shift, do not interrupt the current valid question or silently overwrite the historical decision. Mark that decision as based on evidence later excluded; at the next safe boundary choose using the corrected state. A current item affected by the quarantine becomes non-scoring practice or is withdrawn with its draft preserved according to the content-correction chapter.

A learner report alone is an event and a review signal. The content policy determines provisional quarantine; one unverified report must not arbitrarily erase unrelated skill history. Once quarantined, the item contributes no standard evidence until a valid disposition exists. If later reinstated, replay uses that disposition and stable identity without duplication.

<a id="evd-009"></a>

### EVD-009 — Preserve active time and exclude interrupted items from clean speed evidence

Active duration begins when the complete usable stimulus and response controls are ready. Record monotonic active chunks while the answer is available, stop them at response lock, and exclude paused/background intervals, post-answer feedback, optional reflection and explicitly observed confidence-editing UI intervals from response speed. Define a confidence-editing interval from focus/interaction beginning in the confidence control until the choice/dismissal, return to response editing, or submit; overlapping intervals are unioned and subtracted once. The app cannot infer private deliberation time before that focus, so it must not claim to have measured pure thinking time. Timed fluency suppresses confidence and therefore has no such ambiguity. Full sitting-active time still includes interaction/feedback time for honest budget planning, while answer-duration evidence uses the narrower interval convention. A visible timer may show whole-session elapsed time separately; label it accordingly.

A checkpoint must preserve current-item accumulated active chunks, response-lock state and duration, hint/worked-step events, interruptions, revisions, input mode and tool conditions. After app relaunch, continue accumulating chunks without resetting prior duration. Never derive cross-launch active time by subtracting wall-clock timestamps; device clock changes and time-zone changes do not measure work.

Clean speed evidence requires all of the following:

- Explicit timed-fluency mode for a reviewed eligible family.
- Fully correct independent response under the family's permitted tools.
- No pause, background interruption, relaunch resume, answer reveal, help, or response revision after lock.
- Known-complete active duration and a compatible input/device/calibration condition.
- The same family and actual demand band when compared over time.

Set `resumedAfterRelaunch = true` durably even if the restored interrupt counter was absent in an old record. Such an attempt can still contribute independent untimed accuracy if other conditions hold, but not uninterrupted speed evidence. If a crash loses the final unsaved time fragment, retain the known duration, flag it incomplete and exclude it from clean speed claims. Do not pretend the persisted duration is exact.

The acceptance fixture is 20 active seconds before save plus 5 after resume: record approximately 25 known active seconds, preserve any prior help/revision counts, mark interrupted and exclude from clean speed. The original active clock may have finite precision; tolerance must reflect the test clock and checkpoint policy, not a permissive percentage that conceals losing 20 seconds.

<a id="evd-010"></a>

### EVD-010 — Keep personal study separate from built-in skill evidence

Imported sources, user-authored sets, arbitrary external-model questions and self-check ratings always enter `personalStudy`. They can have deterministic task credit and useful spaced reminders without affecting built-in proficiency, protected checks, calibration norms, promotion gates or generalized claims.

A source-backed answer is not automatically academically reliable merely because it has a citation. A future reviewed content-promotion process may admit a new contract into the built-in catalog, but old personal-source attempts do not retroactively become standard observations. The promoted contract receives explicit review, new eligibility metadata and a defined version boundary.

Personal study may adapt local reminders from the learner's self-rating. The UI must call that “your review rating” rather than measured recall or skill improvement. No reducer should treat `.matched` self-check as the equivalent of an independently graded correct answer.

<a id="evd-011"></a>

### EVD-011 — Limit improvement statements to comparable observed tasks

The first release of this policy may show descriptive changes in independent accuracy at the same objective/family/band and compatible conditions. It must show sample sizes and dates. A change of band, format difficulty, assistance, timing, input condition, grading contract, semantic exposure or validity projection makes simple before/after percentages potentially incomparable.

Do not generate “your reasoning improved” from a higher practice accuracy percentage on an easier set. Do not generate “faster” from hinted, interrupted, resumed or differently demanding tasks. Do not generate protected improvement from overlapping exposed forms.

A formal improvement badge requires a separately specified comparison protocol with equivalent reviewed forms, sufficient samples and predeclared claim rules. Existing historical theta/difficulty labels do not meet that requirement. Until that protocol is validated, use factual wording such as “7 of your last 8 independent Foundation questions were fully correct.” Nothing in this chapter authorizes a generalized cognition score, percentile or IQ claim.

## 5. Protected starting checks and reassessment

<a id="adp-013"></a>

### ADP-013 — Protect an assessment contract rather than a nominal seed namespace

A protected item must pass independent correctness, ambiguity, accessibility-equivalence and answer-leakage review. Pool separation uses semantic/structural exposure rules, not only different IDs or seeds. A practice problem that reveals the exact protected solution renders its protected sibling exposed under the content contract even if its namespace differs.

Essential givens must remain visible. Solution-bearing context, decisive-step labels, answer-revealing alternative text, highlighted correct diagrams, prefilled correct order, and worked examples do not belong in the protected stimulus. Audit visible text, accessibility text, image labels, option IDs surfaced through accessibility, diagram legends and all representations. QA-10 is a release gate, not a cosmetic cleanup.

Protected presentation permits save/pause and reviewed accessibility equivalents. Hints, revealing manipulation, worked solutions, Easier/Harder and reroll are unavailable. Accommodations are recorded; they are not automatically called misconduct or lower ability. If an equivalent accessible form is unavailable, explain the limitation and leave that dimension unassessed rather than substituting an unrelated task.

<a id="adp-014"></a>

### ADP-014 — Use the same band evidence model with a separate protected channel

Protected baseline and reassessment use the same eligibility, band grouping, scoring and coverage reducer as ordinary independent work, with a separate evidence channel and a fixed assessment protocol. Practice does not update a protected result; protected results may suggest an initial practice target for the same objective.

For the initial protocol, retain eight scored eligible observations per performance dimension and at least two substantive response formats where the dimension's reviewed protocol requires them. The seven performance dimensions are mental arithmetic, quantitative estimation, probability, spatial transformations, data interpretation, experimental reasoning and logic. This is a coverage requirement, not proof of psychometric precision. Format diversity cannot be satisfied by a cosmetic renderer switch.

The eighth reported dimension, confidence calibration, is different: derive it from pre-feedback confidence predictions paired with outcomes on those reviewed tasks under EVD-005, with at least 12 eligible predictions across two sessions before a descriptive summary. It is not established by answering eight knowledge questions about what confidence or calibration means. Such knowledge questions can be useful explicit metacognition practice but do not measure calibrated behavior. Keep calibration separate from correctness/proficiency, describe the task mix, and avoid comparisons across materially different dimension/band mixtures. This is an explicit protocol change; migration must preserve the old dimension history as legacy evidence rather than relabeling it.

The selector begins at B1 by default or at a declared optional starting-band preference. That preference is not evidence. After each durable independent response, it may choose another reviewed band under a fixed protected staircase that is recorded in the protocol:

- Two consecutive full-credit responses at the same band permit one adjacent-band probe, provided coverage slots remain and the next band has reviewed candidates.
- Two zero-credit responses at the same band permit one adjacent lower-band probe.
- Partial responses leave the band unchanged while the selector changes structure to resolve the missing criterion.
- Reset the two-answer selection streak after each band change or partial response; a skip breaks this selection streak without becoming zero credit. Pause/resume alone does not break it. Band observations remain in the evidence reducer even when the short selection streak resets.
- At least two observations at a visited band are required before using it to suggest a practice start; one successful high-band question never establishes a level.
- Coverage constraints take precedence over escalation. Before choosing a third item of one required format, prioritize an unrepresented required format compatible with the current band when available.
- A starting recommendation is the highest visited band whose complete effective observation set in the linked current protocol form chain has at least two independent full-credit responses on distinct semantic items and `2 * zeroCreditCount <= observationCount`. Partial outcomes contribute to observationCount but are neither full nor zero unless the authoritative rubric says so. Do not choose a favorable subset from that band. Label it a starting recommendation, not the ADP-012 demonstrated practice band.

The same-band descriptive data remain inspectable; do not compress this adaptive path into an uncalibrated theta. If an empirically calibrated assessment is developed later, it requires a new protocol/model version and validated bridging rules. That future work does not reinterpret the old random difficulty jitter as calibration.

<a id="sch-001"></a>

### SCH-001 — Change the old eight-minute cap into a sitting budget

The current baseline's hard block time cap can force a slower learner to retry a fresh set without completing coverage. Replace that behavior with a distinction between **form coverage** and **time available in this sitting**.

- A protected form has a fixed form identity, protocol version, candidate catalog snapshot and committed selection/exposure path.
- A sitting has an active-work budget, initially offer 3, 5 or 8 minutes with an honest estimated question count.
- At a safe boundary, when no appropriate question fits the remaining estimated time, offer “Save and continue later” and an explicit optional extension. Preserve the same form and coverage.
- If a current item runs past the planned sitting budget, do not mark it wrong, auto-submit it, reveal the answer or discard it. Let the learner finish, save or skip under the protocol. An absolute operational timeout for resource recovery must save state and end the sitting without academic penalty.
- Pauses, time away, confidence entry and result/reflection reading do not consume response-time evidence. Sitting duration and response duration may differ; show which is being measured.
- V1 presentation cap is 16 distinct presented slots per performance dimension per form, with a target of eight eligible scored observations and the required format coverage. Skips and displayed-but-later-invalidated items count toward the operational presentation cap, but neither contributes fabricated academic credit. A pause or new sitting does not reset this cap. Unpresented form capacity is not exposure.
- At cap or feasible-pool exhaustion without sufficient coverage, stop with `coverageIncomplete`, preserve all valid evidence, and offer practice or a separately accepted **linked supplemental check**. Starting a supplement is an explicit learner action, not an automatic reroll. Its deterministic identity uses root form ID, protocol version and supplement ordinal; it has another 16-presentation cap and selects only unexposed preauthorized content. Reuse valid same-protocol observations toward the missing coverage, so the learner need not redo already established answers. No automatic loop starts another supplement.
- Only supplements sharing the exact new protocol, reviewed band/answer/comparability contracts and validity/exposure policy can contribute to this coverage chain. Old protected forms and calibration-knowledge MCQs remain in their legacy protocol bucket and never fill new performance/calibration coverage by relabeling. If no valid supplemental inventory exists, the dimension stays incompletely assessed with an honest explanation.
- A skipped protected item is an exposure without scored credit. It does not count toward eight scored observations. Resume selects a fresh eligible replacement while preserving the already answered path.

This is an explicit product behavior change from “finish enough answers before the maximum active duration or retry a new form.” Coverage can now accumulate across resumptions of the same undisclosed form. No seed reset, reroll, or repeat exposure is used to make a form look fresh.

<a id="evd-012"></a>

### EVD-012 — Disclose results without leaking reusable protected keys

Normal protected completion shows dimension-level results, observed bands, coverage, condition notes and concept guidance. It does **not** reveal exact reusable protected answer keys. Use wording such as “Your results appear after this block,” not a promise to show every exact answer.

For teaching after a check, launch a distinct reviewed practice variant that does not expose the reusable protected contract. A retired/disclosed protected form may reveal its exact key only after an explicit exposure/retirement transaction and confirmation that related reusable forms remain valid. That is an exceptional content operation, not the default completion path.

An unfinished form that remains undisclosed can resume. A form whose answers were disclosed, whose contracts became invalid, or whose selected path cannot be faithfully reconstructed requires an explicit replacement protocol preserving prior history. The app explains why a replacement is needed instead of silently generating a new seed.

## 6. Selection, variety and sparse pools

<a id="sch-002"></a>

### SCH-002 — Filter hard constraints before ranking candidates

The selector must apply constraints in this order:

1. Valid content/version and appropriate independent/protected/personal evidence channel.
2. Accessibility and supported language/representation equivalence.
3. Objective, prerequisites, requested activity scope and supported delivered band.
4. Semantic exposure and protected-family separation.
5. Session deduplication, frozen current-item identity and reservation ownership.
6. Required review/transfer contract, if this is a review or transfer slot.
7. Remaining sitting budget and safe expected duration.

Mixed-session family/structure quotas are not hard filters. Evaluate them only after the hard filters as feasible soft preferences under SCH-003. No popularity score, goal weight, content quantity or tie-break value can bypass the hard filters. If the constraints produce no item, use SCH-004. Do not use a force-unwrapped fallback that returns any lab item and preserves the requested activity label.

<a id="sch-003"></a>

### SCH-003 — Balance at the experience level, not only at bank construction

Mixed ordinary practice initially targets at least four applicable families in a ten-item session, no more than two consecutive items in one family, and no family above 35% in a rolling 100-item balanced mixed-practice window when the catalog supports those quotas. Apply these as soft preferences after SCH-002 has established the feasible pool. If satisfying a preference would require invalid content, an unsupported band, a repeated protected item or another hard-constraint violation, keep the hard constraint and record the unmet variety preference. These are pilot defaults consistent with the QA plan. Intentional focused drills are exempt and explicitly labelled.

Maintain separate counts for semantic items, structures, families and representation types. Parameter variation is useful practice, but it does not satisfy family variety. With fewer than four compatible families, use all supported families and show the reduced scope rather than filling unavailable families with mislabeled clones. The selector must report infeasible quota constraints in diagnostics and content coverage reports.

Within feasible hard constraints, rank lexicographically:

1. Required coverage deficit for the current session/assessment/review protocol.
2. Due review/repair priority for the declared slot.
3. Smaller recent family/structure share relative to its quota.
4. Match to the current actual demand band and appropriate prerequisites.
5. Goal relevance and recent observed weak criterion for that objective.
6. Stable tie-break key.

Lexicographic ranking prevents a large numerical parameter pool from drowning out a smaller scientifically meaningful family. If weighted ranking is later introduced, its exact weights and feasibility tests must be versioned; the initial implementation must not rely on arbitrary raw pool order.

<a id="sch-004"></a>

### SCH-004 — Handle content shortage visibly and safely

When the requested band or mechanic has no eligible novel content, use this ordered response:

1. Try another reviewed structure in the same family, objective and band with compatible conditions.
2. For a mixed session only, try another eligible family serving the same intended slot and explain the actual activity.
3. Offer a same-band reviewed repeat explicitly labelled “Review a familiar problem”; it receives the repeat evidence treatment and cannot be presented as an unseen independent probe.
4. Offer the adjacent lower supported band as an explicit learner choice, with delivered-band metadata preserved.
5. End the block early with “You've completed the available reviewed questions for this activity,” retain earned work and offer another activity.

Do not silently broaden a selected confound-identification drill into interval interpretation while retaining the original activity title. Do not count a repeated item as fresh merely because a new seed creates a new ID. Do not fabricate a harder band or generate unreviewed protected content to meet a session length target.

If three unseen candidates are unavailable for upward exploration, remain at the current target and state that the next band is not available yet. This is a catalog limitation, not evidence of learner failure. Report shortage counts by objective/family/band to the content team through local QA diagnostics; no external analytics is implied.

<a id="sch-005"></a>

### SCH-005 — Use deterministic tie-breaking and persist the actual path

All selected candidates have stable IDs. Sort the feasible candidate list by the ranking above, then break exact ties using a stable hash:

```
tieKey = H(
    policyVersion,
    catalogVersion,
    profilePseudonymousID,
    sessionID,
    decisionOrdinal,
    candidateID,
    "question-selection"
)
```

Use a specified stable algorithm, such as the existing versioned stable hash implementation; do not use Swift's randomized `Hasher`, dictionary iteration order, wall-clock milliseconds or global random state. Confidence invitation selection uses a different salt. A stable secondary comparison by `candidateID` resolves hash collisions.

#### Reservation granularity agreed with CON-017/CON-019

The [content chapter](02_Content_and_Scoring.md) owns the whole-epoch candidate recipe. For adaptive practice, that order is an inventory priority recipe, **not an immutable full-session question list**. Use `adaptiveItem` delivery by default, independently of whether challenge is Adaptive or fixed-band:

- On accepted launch, transactionally reserve and consume exactly **one** concrete first item. Before each later presentation, reserve and consume exactly one next item chosen from the current durable evidence, override and feasible inventory.
- Eligibility-aware seeking may pass ineligible positions without consuming them. Track reserved/consumed positions as a set or equivalent durable ledger; a single advancing cursor cannot express this behavior safely. The state chapter owns migration and transaction atomicity.
- A committed ordinary reservation remains consumed for novelty rotation even if the learner abandons it before answering or before its first display. Consumption and exposure are separate facts: only actual presentation records exposure; a never-displayed reserved item produces no academic observation. At most one exact unpresented committed slot exists per adaptive session.
- Prewarm at most **two** speculative candidates for latency. They are advisory only: no reservation, ownership, consumption, exposure or fixed selection decision. A band/field/override change can discard both freely. Recheck eligibility against current inventory at the actual reservation transaction.
- Once an exact slot is committed, its question identity and demands are frozen. Easier/Harder applies to the next slot; an explicit Replace consumes the already committed item and reserves a new identity. It never changes the existing item's band/key in place.
- Feasible inventory excludes invalid content, already-consumed positions, session semantic exclusions and positions committed by another owner. Advisory prewarm does not reduce available inventory. The upward rule checks for three feasible next-band probes; it does not reserve all three in advance.
- A deliberately predetermined fixed quiz may retain `fixedBlock` delivery with a full block reserved/consumed at launch. This is a distinct delivery policy, not the meaning of “Keep this level.” Later selection changes require an explicit remaining-work amendment or a new session; previously committed unused positions remain consumed. It cannot claim to adapt its frozen items invisibly.
- In either mode, the session exclusion set forbids repeating a semantic identity across an epoch boundary or replacing content under an old identity. Completing an epoch is not a way to reroll already answered questions within the same quiz.

For protected checks, the approved form/candidate capacity is not an exposure. Select and freeze the exact next item from that form after each response; retain the protected exposure ledger and safe resume rules. Never treat all candidates in a reserved form as already displayed.

Reservation tests must assert: adaptive launch consumes one exact item; two prewarm candidates consume none; an abandoned committed slot stays consumed; an override discards advisory candidates without consumption; seeking past an ineligible B4 position does not consume it; and concurrent reservation cannot allocate the same exact position to two owners.

Persist the chosen item identity, band/demand contract, presentation snapshot or reconstructable catalog identity, exposure state, ranking reason and exact selection ordinal as part of the reservation before presentation. A presentation acknowledgement records when the usable surface was actually shown. Resume restores that item, not “generate(index)” with an empty fingerprint history. Catalog updates must not replace a frozen in-progress question with a newly generated sibling.

The full selected path, including skipped, replaced and assisted exposures, is available to deduplication after relaunch. Same-device windows cannot commit different items for one session ordinal; the device-local ownership and persistence conflict protocol owns that arbitration. This release guarantees exact mid-question resume only on the saving device under RUN-006. Independent offline devices cannot guarantee global no-repeat or shared live-session ownership through asynchronous sync. If later merged historical records conflict or duplicate an observation, apply the history conflict/deduplication protocol without double scoring; do not imply a supported cross-device draft handoff.

## 7. Retention and mistake review

<a id="sch-006"></a>

### SCH-006 — Keep review objectives separate from literal question repetition

A built-in retention entry is keyed by objective, family, band and reviewed relation/structure scope, not only a template's ever-changing item ID. It records the last independent observation, delay since previous exposure, assistance, exact/sibling exposure history, current interval rung and validity projection.

A retention check normally uses an unseen reviewed sibling that tests the same objective at a compatible band. An exact repeated question can be useful recall practice but is labelled familiar-item recall and does not establish unseen transfer. A change from numeric entry to multiple choice may reduce retrieval demand; record that change and do not compare it as equivalent retention without a reviewed contract.

Do not infer retention growth from confidence, streak length, XP, source self-rating or simply opening the review. Do not infer a validated forgetting probability from the existing `exp(-elapsed/stability)` formula. For the first implementation, use explicit scheduling intervals with honest labels such as “Due for review,” not “You remember 85%.”

<a id="sch-007"></a>

### SCH-007 — Use a bounded, explainable initial interval ladder

Initial built-in interval ladder: 1, 3, 7, 14 and 30 local days. These are scheduling defaults pending pilot data, not scientifically optimal intervals.

| Effective review outcome | Queue action |
|---|---|
| First independent full success on a new objective/structure | Schedule first delayed sibling check in 1 day |
| Due delayed check, independent full success | Advance one interval rung, at most to 30 days |
| Independent partial credit at least 0.5 but not full | Keep current rung; schedule a repair sibling first, then another delayed check no later than the smaller of 3 days/current rung |
| Independent credit below 0.5 | Add targeted repair; reset interval to 1 day after an independent repair success |
| Hint/worked solution used | Do not advance rung; add a fresh independent check when appropriate; maintain assisted completion history |
| Skip/no response | Keep interval and last independent result; allow defer to tomorrow without calling it failure |
| Self-rating in personal study | Update only personal reminder timing under its labelled self-rating policy |
| Content quarantined | Suspend affected queue entry; do not schedule another instance of the faulty contract |

An early voluntary repeat before the due date can provide practice but does not advance the retention rung. A due success after a long absence advances one rung, not several, because elapsed time alone does not demonstrate repeated retention. Date calculations use the configured local day boundary; a time-zone change does not create several due events or erase a queued review.

An interval restart is tied to the next independent repair success, not the moment a solution was shown. Multiple wrong attempts on the same semantic item in one session create one unresolved repair need, not an exploding list of future reminders.

<a id="sch-008"></a>

### SCH-008 — Make the mistake queue actionable and criterion-specific

A mistake entry links to the immutable original attempt and a reviewed error category. It includes the objective, family, band, actual missing criterion, available explanation, valid fresh sibling candidates and the current status:

```
needsExplanation -> readyForRepair -> repairedInSession -> dueForDelayedCheck -> retained
                                  \-> stillNeedsSupport
```

- `needsExplanation`: the learner has not yet opened a useful explanation; opening it does not prove understanding.
- `readyForRepair`: a fresh related task is available. The interface explains which step it exercises.
- `repairedInSession`: a distinct semantic sibling at a compatible demand band was independently solved in the same session.
- `dueForDelayedCheck`: the immediate repair succeeded and a later independent check is scheduled.
- `retained`: a delayed unseen sibling was independently solved after at least the first one-day interval.
- `stillNeedsSupport`: the repair remained incorrect or assisted; offer a prerequisite/worked example without repeatedly forcing the same question.

An immediate repair is evidence of current task performance, not delayed retention. Marking an explanation helpful, choosing an error reflection, or correcting the original answer after viewing the solution does not close the learning loop by itself.

Rank pending mistake entries by unresolved conceptual criterion, due date, objective relevance and recent repetition, with stable ties. Do not put every arithmetic slip ahead of a major conceptual misunderstanding simply because it occurred more recently. The error taxonomy must come from observed scored criteria; where the system cannot distinguish misconception from typo, use neutral “Check this step” copy and allow the learner to annotate it.

<a id="sch-009"></a>

### SCH-009 — Limit review backlog pressure

Default daily review budget is at most 30% of the selected session minutes and at most five review items, subject to actual expected duration. An explicit review session can exceed that limit by learner choice. A backlog never blocks starting normal practice and does not create guilt-based streak penalties.

When there are more due items than fit, select the highest-priority compatible entries and retain the rest. Show “3 reviews ready” or “More reviews available,” not a red overdue debt counter. Deferral does not alter historical performance or demonstrated bands. Review scheduling must not silently turn a 5-minute session into a 20-minute obligation.

## 8. Daily plans, duration and safe changes

<a id="sch-010"></a>

### SCH-010 — Preserve the canonical daily plan while allowing real adaptation inside it

A committed daily plan freezes its day identity, profile/configuration snapshot, ordered blocks, declared objectives/evidence modes, minute budget, block identity, content/policy versions and replacement history. New answers must not silently rewrite completed or in-progress block identities.

Within an uncompleted practice block, the selector may choose a different actual band or structure according to ADP-011. That is a **question selection decision inside the block**, not a new daily plan. Persist the decision and a short reason. Completion counts continue to reference the original block identity.

Changes that alter block scope, add/remove a block, replace a lab, switch evidence mode, change a protected protocol or materially change the remaining time allocation require an explicit plan amendment/override event under the existing canonical-plan history model. The original plan remains inspectable. Do not invent a second “current plan” with the same identity but different block contents.

If the learner lowers energy before a block begins, offer untimed work, a shorter remaining block, or a different valid activity. Lower energy alone does not lower demonstrated proficiency or rewrite previously recorded challenge. If the plan is already underway, apply changes to future unstarted work with an explanation; current drafts and completed blocks remain intact.

<a id="sch-011"></a>

### SCH-011 — Derive workload from item durations and interaction overhead

Remove the blanket `max(3, minutes / 2)` behavior. A one-minute block must not require three substantial questions plus several confidence/feedback screens.

Each candidate has a reviewed expected response duration range and expected interaction overhead by mode. Use the learner's recent same-family/same-band compatible median duration after at least eight usable observations as an optional pacing estimate, bounded to the reviewed range; do not use it as an ability estimate. Use at most the last 20 complete durations in the same 60-day window. Exclude paused/background intervals and incomplete/corrupted durations; do not infer idleness from a learner thinking without touching the screen.

V1 initial overhead defaults, in seconds per item, are: ordinary practice/repair/retention 8; protected check 6; timed fluency 1; personal reference/self-check 15; explicit calibration 10; and dedicated reflection 3 beyond its authored reflection task duration. These are proposed planning allowances, not measured cognitive or interaction norms. Store them in the same versioned policy configuration. Replace an allowance only with a reviewed policy change or a compatible measured phase-duration median after at least eight complete observations (last 20/60 days); do not modify an in-progress promised budget retroactively. If a required authored duration range is missing, the item is unavailable for an automatic time-budgeted selection until its contract is completed; an explicitly chosen count-based study item may retain an honest unavailable-time estimate.

Initial planning estimate:

```
responseEstimate = personalizedCompatibleMedian if enough data else authoredMedian
itemEstimate = responseEstimate + modeOverheadEstimate
remainingBudget = sittingBudget - consumedSittingActiveTime
canStartNext = itemEstimate <= remainingBudget + explicitOverrunAllowance
```

The initial `explicitOverrunAllowance` is zero unless the learner has chosen “One more question.” If the remaining budget is insufficient, finish the current item and show a saved summary or offer an explicit extension. Do not start a long problem just to reach a minimum count.

A dedicated one-minute reflection block is one brief session-level reflection or calibration observation, not a disguised three-item near-transfer quiz. Its evidence channel and purpose must match its label. It can be skipped/deferred without invalidating already completed learning work.

For ordinary practice, time is an approximate session budget, not an academic deadline. Never auto-submit an answer as wrong when it expires. For timed fluency, distinguish a voluntary speed condition from assessment of conceptual correctness; retain the answer's correctness even when its duration exceeds the displayed target.

<a id="sch-012"></a>

### SCH-012 — Handle stopping and completion without falsifying achievement

A practice block can end because its planned workload is finished, the learner chose to stop, the time budget is used, suitable content is unavailable, or a persistence/content issue prevents safe continuation. Record the actual reason.

- At least one answered valid practice item is needed for “practice completed” under the participation policy; skip-only work is “session ended,” not a completed learning block.
- Ending early preserves all committed answers and drafts. The UI distinguishes “2 questions completed” from “daily plan complete.”
- A content-shortage stop may fulfill an amended available-work block only through the explicit plan policy; it cannot silently mark unattempted protected coverage complete.
- A save failure leaves the stage open and retryable. Do not award a durable completion or advance to a dependent block before the necessary checkpoint commits.
- A required protected confidence input or explicit metacognition response can remain incomplete and saved. No stage may trap the learner by requiring a reflection before a safe save/exit.

<a id="sch-013"></a>

### SCH-013 — Respect travel, offline use and changes in available content

Use the existing canonical local-day/travel policy as the source of day identity. Active-day counts for coverage and interval rungs use recorded local-day keys with policy versions, not a reinterpretation of old timestamps using today's time zone.

Offline selection must use verified locally available pools and the same deterministic policy. Network/model availability does not change the standard evidence boundary. A temporary absence of a model must not demote the learner or convert a protected check into unreviewed generated content.

If a catalog update invalidates an in-progress item, the correction protocol decides whether to withdraw it or preserve it as non-scoring history. If it merely adds new valid items, the current frozen item remains unchanged; future selections can use the new catalog only at a recorded boundary. A form bound to an older protected catalog continues only if that catalog remains valid and available.

## 9. Replay, correction and implementation integration

<a id="evd-013"></a>

### EVD-013 — Guarantee deterministic equivalence

The system must satisfy:

```
reduce(initialState, committedEvents, itemSnapshotVersions, validityRevision, policyVersion)
    == liveStateAfterThoseSameEvents
```

Compare the complete state: eligibility, per-band counts/credit, demonstrated-band support, practice targets where reconstructed from decision events, queue statuses/due days, calibration samples and speed eligibility. A superficial equality of one percentage is insufficient.

Use a stable total ordering from the persistence model. Within a session, committed session ordinal governs academic sequence. Cross-session order uses the canonical effective event order and stable identity tie-breaks defined by the persistence chapter. Duplicate events are idempotent. Invalid transitions fail closed with recoverable diagnostics, not a silently regenerated new path.

Decision receipts freeze their historical inputs and rationale. A later validity correction yields a new effective projection and corrected future recommendations; it does not rewrite the fact that an earlier decision was made with the then-available evidence. Progress can show the current corrected summary with a link to what changed.

<a id="evd-014"></a>

### EVD-014 — Make policy versions deployable without silent reinterpretation

Version together the eligibility predicates, independence controls, band demonstration thresholds, staircase, intervals, ranking/tie-break algorithm and confidence invitation schedule. The item band/answer contracts remain separately versioned. Record the combination used for every decision.

The migration/correction chapter owns how old records are retained, superseded or excluded. Required integration behavior is:

- Legacy records with unknown band remain in an explicitly legacy bucket.
- Unknown assistance/timing must not become “clean” by default.
- Unsupported policy/item versions prevent a new standard claim, while preserving readable history.
- A content change that only improves presentation does not retroactively change semantic difficulty unless the reviewed contract changed.
- Rebuilding after a correction must complete before publishing affected proficiency/claim summaries, or show the previous summary as pending revision with no new claims.

<a id="sch-014"></a>

### SCH-014 — Map the implementation to current components

| Current component | Required responsibility after the change |
|---|---|
| `NFFallbackExerciseGenerator` | Generate actual permitted band/demand contracts; fail explicitly when unsupported; stop overwriting only the difficulty number |
| `NFDeterministicSessionExerciseFactory` | Select/restore concrete frozen items; preserve semantic exposure and no-repeat path; return explicit shortage outcomes |
| `NFUniversalSessionRuntime` | Continuous question interaction; durable assistance/timing; apply selection decisions at safe boundaries; no independent shadow proficiency reducer |
| `AdaptiveEngine.reduce` | Delegate to the shared evidence projection or become a compatibility view; do not maintain a different difficulty-blind theta |
| `NFAssessmentEngine` | Protected protocol and coverage selection using valid band contracts; separate sitting budgets; shared evidence model |
| `NFDailyScheduler` | Canonical block prescription, scope/variety/time constraints and explicit amendment history |
| `NFRetentionScheduler` | Versioned due-date/rung policy based on valid delayed outcomes; no unsupported memory-probability presentation |
| `NFMentalMathProgressAdapter` | Consume explicitly observed strategy/unit/estimate/timing criteria; stop manufacturing strategy evidence from positive credit/template names |
| `NFSpeedEvidenceEngine` | Clean speed predicate including relaunch/assistance/compatible band and complete active time |
| `NFImprovementClaimEngine` | Suppress unsupported comparisons; consume comparable condition/band/form contracts and correction projections |
| Progress and history views | Show actual band, independent/assisted status, sample coverage and readable explanations; separate XP and personal study |

This is a responsibility map, not permission to duplicate the model across these files. Prefer small pure policy modules with explicit inputs, and keep UI selection controls from mutating evidence fields directly.

## 10. Executable simulation specification

These fixtures are mandatory policy tests in addition to UI QA. Use a virtual monotonic clock, fixed local calendar/day boundary, fixed profile/session IDs, a small explicit catalog and stable event IDs. No fixture may depend on wall-clock sleeps or random UUID iteration order. Fixtures should assert the chosen item's actual demand vector and semantic identity, not only `requestedBand`.

### Shared fixture catalog and conventions

Create `QA.Catalog.v1` with an arithmetic objective `O.mul`, a reasoning objective `O.evidence`, four reviewed families for mixed practice, two substantive structures per family/band, and at least six semantic items per structure/band. All have valid independent eligibility; a disjoint protected subset uses distinct semantic/solution contracts and required formats. Each band's paired fixture changes a declared demand: B1 one operation; B2 a two-step composition; B3 a representation/assumption decision plus calculation; B4 interacting constraints and a verification step.

`F` means full credit 1, `Z` means 0, `H` means an answer after a hint, `P(x)` means criterion credit x, and `S` means skip. Unless stated otherwise, items have distinct semantic fingerprints, correct required conditions, no help, two compatible structures, and no prior exposure. The fixture's semantic identities and exact scored criteria must be authored explicitly, not generated by the policy under test.

### Selection and band fixtures

| Fixture | Input sequence/state | Required result |
|---|---|---|
| ADP-F01 — Real demand change | Same objective, base seed/context; explicitly request B1 and B4 | Different reviewed demand contracts and substantive problems; actual delivered bands B1/B4; independently correct keys; timing identical |
| ADP-F02 — Timing isolation | Freeze an unanswered B2 question, switch untimed → elapsed-only → untimed | Same item/answer/demand/semantic ID and draft; only timing/display condition changes; no promotion event |
| ADP-F03 — Cold start | No observations, no explicit override | B1 untimed; no demonstrated band; reason `coldStartDefault` |
| ADP-F04 — Explicit harder start | No observations, learner explicitly selects B3 | B3 if valid/available; no proficiency evidence; reason `userRequested`; no automatic timing enablement |
| ADP-F05 — Strong trajectory | Adaptive B1, distinct F,F,F,F at B1 | Next item B2 with real extra demand; one upward event; demonstrated band still absent until broader criteria met |
| ADP-F06 — Weak trajectory | Adaptive B3, Z,Z,Z at B3 | Next item B2; preserve earlier history; no claim learner lost general ability |
| ADP-F07 — Mixed trajectory | B2, F,Z,F,P(0.5),F | Stay B2: latest qualifying windows do not satisfy either threshold; choose missing criterion/structure where appropriate |
| ADP-F08 — Partial upward boundary | B2, F,F,F,P(0.5) | Mean 0.875 and three full successes: one B3 probe permitted if pool/cooldown limits allow; no full-credit rounding of P(0.5) |
| ADP-F09 — Partial lower boundary | B3, Z,Z,P(0.5) | Mean 1/6, at least two zeros: next B2; the partial result remains 0.5 in history |
| ADP-F10 — Not enough failure evidence | B2, Z,F,Z | Mean 1/3 with two zeros satisfies default down rule; next B1. B2,Z,P(0.5),P(0.5) has mean 1/3 but fewer than two zeros, so stays B2 |
| ADP-F11 — Fixed band | Fixed B2 with eight F or eight Z | Keep B2; offer optional support/challenge suggestion; no automatic band change |
| ADP-F12 — Upward throttle | B1 F×4 → B2, then B2 F×4 in same activity session | Stay B2 because one automatic upward change already used; no hidden second promotion |
| ADP-F13 — Foundation floor | B1 Z,Z,Z | Stay B1; offer prerequisite/worked example; no B0, negative level or forced restart |
| ADP-F14 — Assisted sequence | B2 H,H,F | H results excluded from independent decision window; no evidence-based demotion; offer help/easier choice from support pattern |
| ADP-F15 — Skip sequence | B2 S,S,F | No zeros manufactured; no band change from skips; exposures recorded and replacement items remain distinct |
| ADP-F16 — Sparse next band | B1 F×4, B2 has only two unseen valid candidates | Stay B1; no unsupported upward move; show limited available challenge and record shortage |
| ADP-F17 — Empty selected activity | Explicit family has no fresh compatible items; other families exist | No silent relabelled substitution; offer familiar review/other activity/stop with accurate scope |
| ADP-F18 — Tie order | Two exact-ranked candidates supplied in reversed array/dictionary order | Same selected candidate and tie receipt with fixed IDs/policy/catalog/session/ordinal |
| ADP-F19 — Resume path | Second question required a dedup fallback; save/relaunch | Restore exact selected second item and subsequent path; first item never reappears as an unseen replacement |
| ADP-F20 — User override | Adaptive B2, user Harder then changes timer visibility | Next eligible question B3; timer visibility has no additional band effect; no demonstrated-band change |

### Evidence, validity and timing fixtures

| Fixture | Input sequence/state | Required result |
|---|---|---|
| EVD-F01 — Supported band | Eight eligible items, two structures with four each, two sessions/two days, seven F and one P(0.5) | Banded practice support established: mean 0.9375, seven full; counts and exact qualifying IDs exposed |
| EVD-F02 — One-structure gaming | Twenty F from different numbers in one structure | High narrow practice accuracy, limited breadth; no broad demonstrated-band claim |
| EVD-F03 — Same-item gaming | Same semantic item F repeated twenty times in 30 days with new option orders/IDs | At most one eligible observation; no promotion from the repeated sequence; history retains all attempts |
| EVD-F04 — One-session streak | Eight valid F in one session/day across two structures | No demonstrated band yet; reason missing second session/day, not a fabricated uncertainty interval |
| EVD-F05 — Confidence invariance | Identical answers/events except all optional confidence guessing versus certain | Identical ability, staircase, XP and retention schedule; only valid pre-feedback calibration/reflection channel differs |
| EVD-F06 — Invitation replay | Same session/ordinal reopened five times | Identical one-in-five invitation decision; absent practice confidence never blocks submission |
| EVD-F07 — Retrospective confidence | Confidence supplied after answer outcome reveal; separate 11-versus-12 eligible pre-feedback observations across two sessions | Post-outcome value is reflection only. Eleven eligible predictions show sample count without a calibration summary; twelve show the compatible-group descriptive summary. Required and optional samples remain separate; only the last 50 in 60 days qualify |
| EVD-F08 — Partial confidence | Whole-answer confidence 0.72 under confidenceCategoricalV1, rubric q=0.5 | Ability descriptive q=0.5 once; calibration binary full-correct outcome y=0, not 0.5 |
| EVD-F09 — Equivalent answer | Two accepted algebraic/logical equivalents to one contract | Same criterion credit, independence and adaptive action |
| EVD-F10 — Resume timing | 20 active seconds, hint/pause, save/relaunch, 5 active seconds then answer | Approximately 25 known active seconds; prior hint/interrupt retained; resumed flag true; independent/clean-speed exclusion consistent with aid use |
| EVD-F11 — Resume without help | 20 seconds, save/relaunch, 5 seconds, correct unassisted response | Accuracy may be independent; clean speed excluded solely because interrupted/resumed; no zero duration reset |
| EVD-F12 — Clock change | Wall clock moves back 2 hours between monotonic chunks | Nonnegative correct active chunk sum; no 2-hour speed artifact; local-day policy handles day identity separately |
| EVD-F13 — Duplicate commit | Same observation received twice locally and once via sync | One scored observation, one queue transition, no duplicate XP or exposure count |
| EVD-F14 — Quarantine trigger | Four F cause B1→B2; validity projection later excludes one triggering item | Current valid item preserved; effective evidence becomes three F; next decision uses corrected state; historical decision marked affected, not erased |
| EVD-F15 — Faulty sibling family | One answer-generation rule invalidates multiple semantic siblings | All affected eligible observations excluded and new candidates filtered; unrelated families unchanged |
| EVD-F16 — Reinstatement | Quarantined item receives valid reinstatement disposition | Replay restores its single effective observation exactly once; original answer/history unchanged |
| EVD-F17 — Personal source | Twenty deterministic source answers or self-rated matched responses | Personal-study state/reminders update; zero standard practice/protected/promotion/calibration observations |
| EVD-F18 — Legacy metadata | Old attempt has difficulty 0.9 but no valid band contract | Legacy history only; no automatic B4 or IRT calibration; unknown assistance remains unknown |
| EVD-F19 — Online/replay | Execute a mixed event script, destroy derived cache, rebuild | Complete state equality including eligibility, chosen-path receipts, support, queues, calibration and speed exclusions |
| EVD-F20 — Unobserved strategy | Correct numeric response with no strategy interaction | Strategy evidence remains unknown; no flexibility/strategy-success claim |

### Protected, retention and plan fixtures

| Fixture | Input sequence/state | Required result |
|---|---|---|
| SCH-F01 — Protected leakage | Candidate has solution-bearing context, accessible label or supplied counterexample | Admission/selection rejects protected eligibility; no protected observation is created |
| SCH-F02 — Protected time slice | Five-minute sitting ends after three scored observations | Form remains incomplete/resumable with same identity, remaining coverage and exposure path; no forced fresh-seed restart |
| SCH-F03 — Slow current item | Current item exceeds sitting budget while draft remains | No auto-wrong/auto-submit; finish/save/skip choices; complete draft preserved |
| SCH-F04 — Protected skip | S then valid scored answers; separate case with seven scored and nine skipped presentations | Skipped item exposed, no credit/coverage; next replacement fresh. At 16 presented slots with only seven eligible answers, stop coverageIncomplete; no automatic new form. Explicit linked supplement preserves seven valid same-protocol observations and needs the missing coverage, not eight replacement answers |
| SCH-F05 — Protected key reuse | Complete reusable protected form | Dimension results/concept guidance only; exact key still unavailable; teaching launches a distinct practice contract |
| SCH-F06 — Protected accessible form | Equivalent reviewed accessible form exists | Use it with recorded conditions and preserved objective; no ability penalty from accessibility setting alone |
| SCH-F07 — Missing accessible form | No equivalent reviewed form | Dimension stays unassessed; explain limitation; do not substitute an easier unrelated task |
| SCH-F08 — Interval advance | New independent F; due day-1 sibling F | First due day +1, then next interval +3 local days; one-rung advance only |
| SCH-F09 — Early repeat | Day-1 review scheduled, learner repeats the original same day | Practice history retained; no retention-rung advance and no fresh independent semantic observation |
| SCH-F10 — Failed retention | Due independent Z, then assisted correction | Add repair; rung does not advance; next delayed check anchored to later independent repair success |
| SCH-F11 — Successful repair | Incorrect item → explanation → independent fresh sibling F → next-day independent sibling F | needsExplanation → readyForRepair → repairedInSession/dueForDelayedCheck → retained; immediate repair not labelled delayed retention |
| SCH-F12 — Backlog | 40 due entries, five-minute session | Select only items fitting at most 30%/five-item cap; remaining queue preserved; normal practice available |
| SCH-F13 — One-minute reflection | Dedicated reflection block with budget 60 seconds | One brief reflection/calibration task; never three ordinary near-transfer questions |
| SCH-F14 — Mixed family balance | Feasible 10-item mixed pool with four+ families | At least four families, no run above two, correct actual item scope; stable choices under input-order permutation |
| SCH-F15 — Dominant bank family | One family has 990 items, eight others have reviewed candidates | Mixed quota/ranking still distributes selected families; raw pool size does not dictate concentration |
| SCH-F16 — Canonical plan | New performance evidence arrives after one daily block completes | Original block IDs/order/completion remain; next-item band may adapt within the current practice block with a decision receipt |
| SCH-F17 — Lower energy mid-plan | Two blocks complete, learner shortens remaining session | Explicit future-work amendment/override; completed work preserved; no retroactive band/difficulty downgrade |
| SCH-F18 — Save failure | Attempt saved, dependent completion checkpoint fails | No false durable block completion/automatic next block; retryable stage and stable attempt ID |
| SCH-F19 — Time zone change | Travel changes local wall date during incomplete form/session | Same in-progress identity/draft; no duplicate due rung or automatic fresh daily plan that discards work |
| SCH-F20 — Catalog update | Valid new catalog arrives during unanswered question | Frozen question remains identical; future catalog change only at recorded boundary; invalidation uses correction path |

## 11. Pilot validation and release gates

<a id="adp-015"></a>

### ADP-015 — Validate the proposed bands with representative learners

Before calling bands empirically calibrated, run a consented pilot with novice, intermediate and experienced learners who match the intended subject prerequisites. Use an explicit research plan and data minimization; this specification does not authorize external telemetry or contact with participants.

The pilot must inspect actual delivered questions and record observed independent success, partial-credit distribution, assistance use, completion time, skip reasons, disputed grading, explanation usefulness and perceived challenge by objective/family/band. A small observed success-rate table can support `pilotObserved`; it cannot by itself establish a calibrated item-response scale.

Initial product targets for review are roughly 70–85% independent full success in sustained ordinary practice, enough recoverable errors to make explanation useful, and few repeated failures without support. These are design targets to test, not guarantees for every learner or every band. Do not force the algorithm to achieve the target by relabeling questions or excluding legitimate errors. If a family shows no meaningful separation between bands, repair its demand contracts before changing scoring rhetoric.

Analyze whether upward/downward rules converge without oscillation, whether novices receive useful repair paths, whether experienced learners exhaust available bands, whether assisted learners can demonstrate fresh independent success later, and whether actual time fits displayed session budgets. Inspect subgroups by relevant accessibility/input conditions without interpreting differences as inherent ability.

<a id="evd-015"></a>

### EVD-015 — Require evidence integrity before stronger product claims

Release gates for this chapter:

1. QA-06 paired-demand regression passes for every admitted multi-band family, not only a metadata assertion.
2. QA-15 timing-isolation tests pass at configuration, runtime and resume boundaries.
3. QA-09 active-time/help/interruption preservation passes across every save stage, relaunch and checkpoint-recovery path.
4. QA-10 protected leakage review covers visible, visual and accessibility representations, and reusable protected keys stay undisclosed.
5. QA-16 live/replay equivalence and repeat-gaming fixtures pass using the single versioned reducer.
6. QA-07 catalog and runtime distributions pass under feasible mixed quotas; shortages produce explicit outcomes.
7. All source/self-rating fixtures prove zero standard skill contribution.
8. Quarantine/correction fixtures rebuild every affected derived channel without changing raw historical answers.
9. Novice/experienced trajectory simulations select different actual demands and remain finite under sparse pools.
10. Human pilot feedback supports the intended challenge and clarity; stronger calibration or improvement claims remain disabled until separately justified.

A green deterministic test suite establishes that the policy implements the specified rules. It does not establish educational validity, appropriate difficulty for every person, long-term retention, broad transfer, or generalized cognitive improvement. Those conclusions require the corresponding learner and outcome evidence, reported at its actual scope.

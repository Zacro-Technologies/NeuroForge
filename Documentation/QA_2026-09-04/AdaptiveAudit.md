# NeuroForge adaptive learning and session reliability audit

Audit date: 2026-09-04. This is an independent source audit; the parent audit owns app execution and the full test-suite results. No app source was changed. Findings labelled source-confirmed follow the actual production entry points. Runtime reproduction is still needed where explicitly stated.

## Executive assessment

The app has real adaptation of **what to practice** and a real response-dependent baseline selector, but it does not yet have convincing adaptation of **how hard the practice questions are**. The generator's requested difficulty changes metadata without changing the question. Progress levels also primarily summarize success and evidence counts without adjusting for item difficulty. Those gaps undermine a promise of personalized challenge even when deterministic scoring and the scheduler work correctly.

Session mechanics contain tangible reliability and pacing issues: ordinary Practice saves cannot be resumed through the production launcher, restored attempts lose important per-item timing/context, and only the first authored hint is accessible. The interface asks for confidence on every response, frequently followed by a separate required reflection, which makes a simple quiz feel procedural.

## Prioritized findings

### P1 A-01 — Difficulty selection changes the label, not the generated problem (source-confirmed)

- `Sources/TrainingEngine/NFFallbackExerciseGenerator.swift:69` validates targetDifficulty; `:155` assigns the result of adjustedDifficulty; `:3153–3175` only overwrites `difficulty.overall` with the requested value. A file-wide search shows no other content-producing use of targetDifficulty.
- `:3232–3257` chooses a variant from the preferred mechanic/format or randomness. `:3260–3271` derives the content seed without targetDifficulty. Thus the same seed/index/lab/purpose at targetDifficulty 0.2 and 0.9 produces the same prompt, answer schema, quantities, and representations, with different difficulty metadata.
- `Sources/AI/NFNextDayPlanPreparationService.swift:90–102` forwards the assessment descriptor's difficulty or the fixed session target to that generator.
- `Sources/Features/Training/UniversalSessionView.swift:652–662` advances normal practice using the same immutable request. It never changes target difficulty based on previous answers.
- `Sources/Assessment/NFAssessmentEngine.swift:1019–1022` assigns candidate difficulty using base values plus seed jitter and a variant offset, while the referenced mechanic can remain the same. Assessment selection reacts to those nominal values, so descriptor-level adaptivity does not establish empirically calibrated challenge.

Impact: an advanced learner can receive the same task as a beginner; difficulty-dependent UI and analytics can imply a distinction the question does not deliver. A baseline's response-driven item ordering exists, but difficulty validity remains weak.

Fix: define reviewed easy/medium/hard parameter bands per mechanic (number magnitude, reasoning steps, distractor closeness, representation changes and scaffold availability). Select actual item bands from a learner state. Add a bounded staircase/target-success policy for practice and preserve protected assessment policy separately. Do not increase difficulty by simply increasing time pressure.

Acceptance: compare identical seed/context at low and high difficulty and assert the problem's real demand differs; simulate consistently correct, consistently incorrect, and mixed learners and verify actual question bands diverge while staying within reviewed bounds. Evaluate observed success rates with representative learners before calling item difficulty calibrated.

### P1 A-02 — “Save & close” strands generic Practice sessions (source-confirmed)

- `Sources/Features/Training/UniversalSessionView.swift:2113–2118` offers Save & close for ordinary practice. `:2165–2172` saves a checkpoint and dismisses the session.
- `Sources/Persistence/PersistenceModels.swift:2585–2601` only selects a resumable checkpoint when the launch has a planBlockID, a baseline block, or a reassessment block/cycle; every other launch returns false from the matcher.
- The generic Practice catalog launches source `.focused` without plan IDs. There is no other checkpoint restoration entry point in the source inventory.

Impact: the answer draft and scratchpad may be durable in storage but are inaccessible on reopening ordinary Practice; the next launch reserves another question set. The save wording suggests a continuity feature that does not work for this path.

Fix: create a first-class resumable session identity and a “Continue practice” entry, persist the full launch contract and reserved offline question identities, and let the learner explicitly resume or start fresh.

Acceptance: start any ordinary activity, type a draft and scratchpad, save/close, relaunch the app and resume; exact question, answer draft, position, counts, selected field/mode, and question reservation must survive.

### P1/P2 A-03 — Resume discards per-item timing, hints and interruption state (source-confirmed)

- Runtime initializes `shownAt = Date()` and counters at zero (`Sources/Features/Training/UniversalSessionView.swift:106–112`). Restored time is assigned only to `cumulativeActiveDuration` (`:156–161`).
- `SessionCheckpointRecord` (`Sources/Persistence/PersistenceModels.swift:873–907`) stores aggregate active duration but no current item's accumulated duration, hint count, interruption count, revision count, or locked-response timing.
- Attempt commit measures only the new `shownAt` interval (`UniversalSessionView.swift:504`, `:917–923`) and persists fresh counters (`:522–529`).
- `Sources/Adaptive/NFSpeedEvidenceEngine.swift:53–60` accepts timed, correct attempts with interruptionCount == 0 and their saved per-attempt duration.

Impact: after resuming a timed daily-plan item, the per-attempt speed can be artificially short and an interrupted/hinted item can appear uninterrupted/unhinted. Aggregate session time is retained, but per-attempt evidence is no longer faithful.

Fix: store an explicit current-item checkpoint including accumulated active duration, response lock, counters, and input state. Mark any relaunch-resumed item as interrupted for speed-evidence eligibility.

Acceptance: checkpoint after 20 seconds, relaunch, answer 5 seconds later; persisted item active time must be approximately 25 seconds and the item must not enter uninterrupted speed evidence. Preserve hint/revision counts across the same test.

### P2 A-04 — Durable ability summaries ignore question difficulty (source-confirmed)

- `Sources/Domain/DomainModels.swift:642–660` exposes no general item difficulty in AttemptDTO.
- `Sources/Adaptive/AdaptiveEngine.swift:102–110` updates theta from credit minus sigmoid(theta), without an item-difficulty term. `:122–126` labels status based on evidence count; `:141` narrows uncertainty by count alone.
- The protected dimension reducer repeats a difficulty-independent theta update (`Sources/Assessment/NFAssessmentEngine.swift:1154–1158`) even though the live assessment state used difficulty (`:404–410`).

Impact: two learners with equal answer outcomes on materially different difficulty paths receive the same durable theta; live adaptive estimates and later progress summaries are different models. “Stable” indicates enough observations, not demonstrated mastery over increasingly hard skills.

Fix: persist calibrated item difficulty/version and replay the same measurement model; clearly separate evidence sufficiency, current proficiency, practice accuracy, and engagement levels. Continue avoiding unsupported percentile/IQ/improvement claims.

Acceptance: equal correctness on easy and hard known-calibrated forms must yield appropriately different estimates; replay after relaunch must reproduce the online estimate; repeating one easy family should not establish broad mastery.

### P2 A-05 — Only the first hint in each ladder can be used (source-confirmed)

- Generator supplies two hints, e.g. `Sources/TrainingEngine/NFFallbackExerciseGenerator.swift:614`, `:878`, `:1316`, `:1678`.
- `Sources/Features/Training/UniversalSessionView.swift:314–316` always returns `hintLadder.first`.
- `:473–478` prevents any new request once showHint is true.

Impact: learners stuck after a generic initial hint have no progressive help despite authored supporting content. The only options are guessing or skipping.

Fix: progressive hint disclosure with one hint per tap, optional worked step after a failed attempt, and a similar follow-up question to verify learning; persist assistance use separately from independent success.

Acceptance: all authored hints are reachable in order, no answer is disclosed before the intended step, and assistance counts remain accurate after resume.

### P2 A-06 — Per-question workflow imposes avoidable friction (source-confirmed design issue)

- Every normal answer transitions to a separate confidence screen (`Sources/Features/Training/UniversalSessionView.swift:1765–1786`). This is followed by feedback and an explicit Next challenge action.
- `Sources/Persistence/PersistenceModels.swift:3150–3175` can require another reflection for high-confidence mistakes, repeated errors, strategy errors, or every weekly mission item.
- The pause overlay suppresses Save & close during the required reflection (`UniversalSessionView.swift:2108–2118`).
- A 1-minute reflection plan block is mapped to an ordinary near-transfer session (`Sources/Assessment/NFDailyScheduler.swift:629`, `:850–859`); normal duration-to-item mapping always produces at least 3 questions (`UniversalSessionView.swift:220–222`). The block label and minimum interaction workload are poorly matched.

Impact: drill pacing is broken into several full-screen steps. Learners cannot simply save and leave when a mandatory reflection is pending, even though reflection restoration code exists. A very short block still has the overhead of multiple questions/confidence/feedback screens.

Fix: place confidence in the answer area when useful, sample it in ordinary practice, retain mandatory calibration on protected checks where needed, show concise inline feedback, and offer optional deeper explanation. Allow saving a pending reflection. Make reflection blocks actual short session-level reflections; derive question counts from expected item duration and the learner's pace.

Acceptance: a standard choice item should require selection, answer/confidence submission, and onward action with no unnecessary intermediate screen; a one-minute reflection block should be completable near its displayed duration; every stage must save safely.

### P2 A-07 — Restored normal sessions do not reconstruct their deduplication path (source-confirmed risk; needs runtime example)

- Ordinary next-question selection excludes `seenQuestionFingerprints` (`Sources/Features/Training/UniversalSessionView.swift:652–662`) and can trigger alternate seed/mechanic fallbacks (`Sources/AI/NFNextDayPlanPreparationService.swift:135–196`).
- Initialization regenerates the current index with no exclusion history (`UniversalSessionView.swift:231`) and starts the seen set with only the regenerated exercise (`:235`). Neither the checkpoint nor SessionRequest carries the concrete selected question path.

Impact: where original generation required a no-repeat fallback, a resumed item can be regenerated differently and the saved draft restored onto it; subsequent items can repeat questions answered before closing. Narrow fixed mechanics make this especially plausible. This must be reproduced for a real resumable daily block before assigning release-blocker severity.

Fix/acceptance: persist selected exercise identity/payload or deterministically replay the full selection path. Resume every index of a known fallback-triggering session and compare fingerprints, answer schema, and subsequent sequence byte-for-byte.

## What does work in the implementation

- Daily scheduling genuinely uses selected goals, lab weakness, estimate uncertainty, review urgency, transfer gap, variety and recent workload (`NFDailyScheduler.swift:324–394`), with a 14-active-day breadth policy (`:673–734`). This is more than a fixed random list.
- Low readiness and untimed preferences alter pacing; mental-math timing has a learned eligibility gate, and protected checks suppress speed scoring (`NFDailyScheduler.swift:555–573`; `PersistenceModels.swift:2741–2747`; `UniversalSessionView.swift:305–310`).
- Protected baseline selection updates a per-dimension state after durable responses, enforces dimension/format coverage, has bounded item/time budgets, and replays durable descriptor paths (`NFAssessmentEngine.swift:395–465`, `:848–900`, `:939–975`).
- Baseline practice previews have zero assessment weight; document practice remains outside standardized evidence. Skips do not count as scored answers. The app labels incomplete checks as requiring more answers rather than assigning a low score (`UniversalSessionView.swift:1997–2015`).
- Attempt insertion uses stable IDs and safe retry semantics; failed checkpoints roll back and retain the open session (`PersistenceModels.swift:4755–4768`, `:4780+`). These are useful reliability foundations.
- Scoring is deterministic and typed; hints/answers are withheld for protected assessments. The defect findings do not imply every scoring mechanic is broken.

## Suggested implementation sequence

1. Fix save/resume identity and per-item evidence fidelity first; add interruption and checkpoint-path regression tests.
2. Make difficulty a real content-generation input; keep baseline and practice policies distinct; add simulated learner trajectories and real learner calibration.
3. Unify durable and live measurement models, and revise proficiency/uncertainty copy to match the evidence.
4. Streamline the answer/confidence/feedback loop, expose progressive hints, and make reflection blocks fit their stated duration.
5. Test novice, intermediate and advanced users across the same activities. Measure completion time, skip rate, assistance rate, error repetition, and observed success rate by actual difficulty band. Use those outcomes to judge challenge and usefulness.

## Validation limits

This sub-audit inspected production source and existing contract tests, including `SessionFlowContractTests.swift`, but did not execute its own runtime test suite or modify the app. Existing tests exercise scratchpad round trips, checkpoint failure retry, summary counts and today-plan chaining. They do not, in that file, establish generic focused-session resume or preservation of per-item hint/timing/deduplication state. The parent QA report should attach its current build/test and hands-on results separately. A source audit cannot establish that training improves real-world cognition; that requires learning-outcome evidence.

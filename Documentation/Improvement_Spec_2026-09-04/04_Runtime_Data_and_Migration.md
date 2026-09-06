# Runtime, persistence, navigation and migration

Status: proposed implementation contract, version 1.1, revised 5 September 2026. This chapter defines the target behavior; it does not claim the implementation already exists. Read the [master specification](README.md) for scope and precedence and the [audit](../QA_2026-09-04/README.md) for observed evidence.

## 1. Architectural boundary

<a id="core-001"></a>

**CORE-001 — One learning runtime.** Every built-in practice launch, daily-plan block, protected check, review task, AI-authored activity and source-based activity shall pass through one session coordinator. Deterministic grading, rubric-based AI grading, composite/hybrid evaluation and reference/self-check use shared lifecycle primitives with explicitly declared evaluation authority and evidence eligibility. AI is a central teaching and assessment capability; local processing provides practical offline use and responsive operations when suitable. A feature must not implement its own Submit→save→Next sequence. The existing `NFUniversalSessionRuntime` is the migration starting point, not a requirement to keep all logic in its current large view file.

<a id="core-002"></a>

**CORE-002 — Separate responsibilities.** Introduce the following logical components. Names below are proposed Swift-facing contracts, not instructions to copy an entire architecture before delivering a vertical slice.

| Component | Owns | Must not own |
|---|---|---|
| `SessionCoordinator` | Typed run state; commands; lifecycle; ownership; transition validation | Question truth, SwiftUI geometry, direct cloud API calls |
| `QuestionSelector` | Feasible candidate selection, protected exposure rules, versioned deterministic ordering | Score mutation, prose authoring at scoring time |
| `ExerciseFactory` | A reviewed concrete item from a descriptor/demand vector | Relabeling fixed tasks as harder, evidence reduction |
| `ResponseValidator` | Structural validity and actionable entry errors | Inferring semantic correctness from formatting alone |
| `ExerciseEvaluator` | Execute pinned deterministic, rubric-AI or composite component protocols; validate results and apply the declared aggregate rubric | Silently changing authority, rubric or model for an accepted response; publishing an unvalidated grade |
| `AICapabilityRouter` / provider adapters | Match task, language, context size, connectivity, service configuration, cost and latency budget to an available local or cloud capability | Reinterpreting saved grades, bypassing spend limits, treating source/answer instructions as application commands |
| `EvaluationJobRepository` | Durable AI request identity, dispatch/retry state, result receipt and reconciliation | Claiming a remote request was cancelled or never charged without provider evidence |
| `AttemptRepository` | Append/idempotent commit, immutable original records, conflict detection | Silently replacing old responses or scoring versions |
| `SessionRepository` | Run envelope, reservation, checkpoint, commit journal | Regenerating a different question into an old draft |
| `EvidenceProjector` | Deterministic reduction of eligible records and corrections | Writing a new answer score, awarding XP by side effect |
| `LearningPresentation` | Readable response/explanation/diagram view models | Treating raw serialized payloads as display text |
| `NavigationCoordinator` | Validated routes, destination paths, dirty-work policy | Guessing a destination from stale view state |
| Existing system adapters | Notifications, widgets, Spotlight, optional sync | Defining authoritative learner/session state |

<a id="core-003"></a>

**CORE-003 — Explicit inputs and replay boundaries.** Deterministic generation, structural validation, result validation, evidence reduction and next-item selection accept explicit value inputs and policy versions. The coordinator supplies clock, saved locale, seed and configuration. AI generation, teaching and grading run through explicit asynchronous provider adapters supplied with immutable request context and a pinned protocol. Network/model output is an external result to validate and persist, not hidden global state in a pure function. A seed or temperature setting does not make a model reproducible: replay a saved accepted result without calling the provider again. Contract tests may substitute an adapter; live-provider quality and latency require separate evidence.

<a id="core-004"></a>

**CORE-004 — Concurrency.** UI state stays on MainActor. Bounded expensive catalog construction, content decoding and bulk evidence projection execute away from the UI actor using immutable snapshots. Persistent models are accessed through their owning context/actor, not sent between actors. Returned view projections are immutable `Sendable` values. Provider calls, encoding, validation and durable file operations run away from the UI actor; no live persistence model crosses actors. Cancellation cancels disposable computation; it does not interrupt a transaction halfway through an acknowledged save. Every returned result is checked against the captured run, slot, response revision, writer generation and job identity before publication. Once committed, adopt its receipt even if the waiting UI task was cancelled; a later UI owner can render it safely.

<a id="core-005"></a>

**CORE-005 — Versioned interfaces.** Codable runtime payloads declare their own schema version. Store schema version, content version, evaluator protocol/scorer version, rubric version, provider/model identity, selection policy version and presentation version are separate fields. Increasing one must not silently imply the others changed. Unsupported future payloads produce a recoverable unavailable state, never a best-guess decoder.

## 2. Session identity and launch contract

<a id="run-001"></a>

**RUN-001 — A run has a durable identity before interaction.** Allocate `sessionID`, `runRevision`, initial reservation and the first `itemSlotID` before enabling the answer controls. An `itemSlotID` identifies a particular position/purpose within a run and is not the exercise's semantic fingerprint. Reusing a question in a deliberate review creates a new slot, not an overwrite of the original attempt.

<a id="run-002"></a>

**RUN-002 — Launch is not resume.** Expose separate commands `start(configuration)` and `resume(sessionID)`. Resume shall never call the launch reservation function first. Clicking Continue uses the exact stored session ID. Clicking New practice creates a new run after a clear decision when other work is active. The current `beginSession` pattern that reserves an offline slice before looking for resumable work must be removed.

<a id="run-003"></a>

**RUN-003 — Persist the complete launch contract.** The run envelope contains:

| Field | Type / rule |
|---|---|
| `sessionID` | UUID allocated once |
| `origin` | today, focused, baseline, reassessment, weeklyMission, review, authoredSet, sourceRecall |
| `ownerDeviceID` | Installation/device identifier; never used as an external tracking ID |
| `ownershipGeneration` | Monotone local generation for same-device window takeover |
| `labID`, `objectiveIDs`, `familyFilter` | Canonical IDs; display names resolved separately |
| `purpose` | instructional, practice, retention, nearTransfer, appliedTransfer, protectedAssessment, selfCheck |
| `fieldIDs`, `topicSnapshot` | Chosen context; topic can be absent, never empty filler |
| `localeIdentifier` | Exact content locale used for the active item |
| `challengePolicy` | adaptive or explicit editorial band plus override scope |
| `timingPolicy` | untimed, elapsedOnly or eligible timedFluency target; independent of challenge |
| `confidencePolicy` | requiredInline, optionalInline, suppressed |
| `assistancePolicy` | permitted authored/AI hint stages, solution reveal policy and effect on eligibility |
| `evaluationPolicy` | deterministic, rubricAI, composite or selfCheck; contract/rubric versions, evidence eligibility and protected protocol. Composite pins component IDs/authorities, dependencies, weights, required resolution and aggregate rule |
| `capabilityPolicy` | configured service/local capabilities, permitted fallback protocols, bounded latency/retry/spend policy; exact executed route retained per job |
| `requestedBudget` | Time estimate or explicit count, plus actual stop policy |
| `planID`, `blockID`, `missionID`, `assessmentFormID` | Optional stable links; only valid combinations allowed |
| `sourceSetID`, `sourceVersionRefs` | Optional local references; not copied into ordinary analytics |
| `catalogVersion`, `generatorVersion`, `selectionPolicyVersion` | Pinned at reservation; controlled changes recorded explicitly |
| `seed`, `reservationID`, `epochID` | Persisted determinism inputs; no random fresh seed on resume |
| `reservationStrategy` | `fixedBlock` or `adaptiveItem`; independent of fixed/adaptive challenge preference |
| `selectionDecisionOrdinal`, `selectionDecisionID` | Stable ordered selection command identity; each decision resolves once |
| `consumedPositionSetRef`, `runSemanticExclusions` | Versioned novelty ledger and all IDs already committed within this run; not a cursor alone |
| `createdAt`, `updatedAt`, `checkpointRevision` | Wall-clock metadata plus monotone local revision |
| `status` | active, suspended, completed, endedEarly, unavailable, migrationRecovery |
| `completedSlotIDs`, `currentSlotID` | Exact committed path; ordered slot records provide positions |
| `stopReason` | completedCount, budgetBoundary, learnerEnded, poolExhausted, itemInvalidated, failure; absent while active |
| `learningPolicySnapshot` | Policy versions and relevant override decisions; not a giant mutable profile reference |

<a id="run-004"></a>

**RUN-004 — Multiple suspended sessions.** Permit more than one suspended run. Today shows the most recently active resumable run, plus a count/link when more exist; Practice shows all focused/review runs. There is one writable active run per device. Starting another suspends the first through an acknowledged checkpoint. Suspended runs are not silently expired because they are old or exceed the visible list size. Paginate the list; allow explicit End session with clear preservation of submitted answers.

<a id="run-005"></a>

**RUN-005 — Same-device window ownership.** An app-level actor assigns one window the writable ownership generation. A second window may inspect a read-only summary or request Take over. Takeover first checkpoints the existing writer, then increments generation and invalidates old controls. A stale command is rejected with “This session is open in another window.” If the old window is gone, recover its last acknowledged checkpoint and mark interruption.

<a id="run-006"></a>

**RUN-006 — Cross-device limit.** This release guarantees exact resume on the device that saved the run. Existing progress sync is retained, but mid-question cross-device editing is not added. A remote session marker, if shown, says “Saved on another device”; it must not imply a safe handoff. Independent offline devices cannot guarantee global no-repeat or a single active writer through asynchronous CloudKit. Do not implement a fictitious global lease using timestamps.

## 3. Normative state machine

<a id="run-007"></a>

**RUN-007 — Lifecycle states.** Use explicit states rather than unrelated booleans that allow impossible combinations. `paused` and `saveFailed` wrap a resumable underlying state; they are not reasons to discard it.

| State | Visible surface | Valid principal commands | Persistence obligation |
|---|---|---|---|
| `preparing` | Short progress indication; cancel available | Cancel disposable work, queue safe close | No item may be answered until its identity is committed; retain any previous acknowledged checkpoint |
| `answering` | Problem, givens, response editor, allowed hints, inline confidence | Edit, requestHint, submit, skip, revealForLearning, pause | Debounced draft + immediate lifecycle checkpoints |
| `submitting` | Same problem; response locked; short saving indication | Queue safe close; no second submit/Next | Freeze response and evaluation intent durably before dispatch or attempt write |
| `evaluating` | Original response plus “Evaluating your answer…”; component status where useful | Cancel pending evaluation, pause/saveAndClose; no duplicate dispatch | Component jobs identify exact input, contract/provider/model/rubric; accepted subresults retained while others wait; no final aggregate/evidence yet; waiting excluded from solving time |
| `awaitingEvaluation(reason)` | Saved answer with unresolved components identified; no invented final score | Retry unresolved components, use approved fallback, saveAndClose; choose self-check only where allowed | Preserve exact accepted subresults, pending jobs and remote identities; unknown outcome is explicit; no regrading completed components on retry |
| `feedback` | Original question/answer plus concise correction/explanation | Next, deeperExplanation, reflect, retrySimilar, bookmark, pause | Attempt already durable; ancillary actions save independently |
| `protectedAcknowledgement` | Original response plus “Answer saved”; no correctness | Next, report, pause | Protected attempt durable; exact key remains unavailable |
| `referenceComparison` | Original response locked; reference revealed; self-rating controls | Rate, saveSelfCheck, pause | Reveal persisted; independent status cannot be restored by closing |
| `savingSelfCheck` | Comparison retained while committing | Queue safe close | Separate rating record; no evaluated correctness synthesized |
| `optionalReflection` | Inline editable reflection below feedback | Save, dismiss, edit reason, pause | Independent supplemental record; score immutable |
| `explicitReflection` | Metacognition task with purpose and original answer context | Save, “Not sure yet”, pause, saveAndClose | Allowed only under explicit task policy; never blocks safe exit |
| `paused(previous)` | Resume, Save & close, optional End session | Resume, saveAndClose, end | Clock stopped; interruption reasons recorded |
| `saveFailed(previous,intent)` | Content intact plus retry action and concise error | Retry, export draft, keep editing where safe, explicit draft discard or durable-pending close under RUN-022 | No false success; never discard a prepared/committed answer journal |
| `summary` | Completed/ended-early scope, results, next useful action | Review, done, start separate practice | Completion/stop status committed once |
| `unavailable(reason)` | Specific missing/invalid item explanation | Preserve work, choose safe replacement where allowed, end | Existing draft and original slot remain inspectable |

<a id="run-008"></a>

**RUN-008 — Answer evaluation.** Submit validates structural requirements and confidence, freezes the exact response, then executes its declared deterministic, rubric-based AI or composite contract. Use deterministic evaluation for suitable exact tasks and semantic AI grading for short responses, explanations and source-grounded answers with a validated rubric. Correct paraphrases need not appear in a fixed alias list. A reference answer alone is not a complete rubric: the protocol specifies criteria, acceptable alternatives, partial credit, contradictions, evidence requirements and when judgment is insufficient. Only a validated result becomes a committed grade and inline feedback; the problem and original answer remain visible.

A composite/hybrid item can combine an exact numeric/interpreter/selection component with an AI-graded explanation. Before response, pin each component’s ID, evaluator/contract, input dependencies, weight, required/optional status and outcome policy, plus an explicit versioned aggregate rule for credit, correctness and evidence eligibility. Do not force exact components through AI merely because another component needs semantic grading. Persist exact subresults independently while prose evaluation is pending. Ordinary UI may show an acknowledged component result with “Explanation evaluation pending” only when the item’s display policy allows it; it must not label the whole answer fully correct, zero-credit or complete. Protected component results remain hidden.

No final aggregate grade, graded completion or proficiency/evidence contribution is published until every component required by the aggregate rule has a validated terminal result. A timeout/uncertain judgment is unresolved, not a zero or omitted denominator. Optional or self-reported components follow their declared role and cannot silently become evaluated credit. Once ready, compute the aggregate from the exact referenced component receipts and pinned rule, then commit it once through DATA-010.

Empty or structurally malformed input stays editable with actionable guidance. A well-formed wrong answer, including a semantic unit error or reversed explanation, is graded under the rubric rather than granted unlimited free validation retries. Clarification means insufficient input to apply the rubric, not provider failure or low confidence in a difficult judgment. Provider timeout, unsupported language/context or invalid output preserves the locked answer in awaiting evaluation without a zero score. Offer an approved equivalent local/cloud evaluator, later retry, or an explicit self-check choice where appropriate. A second Submit is deduplicated by command/job identity, not only button disabling. A learner may request a grade review after feedback; the review appends a disposition and never edits the original answer or grade.

<a id="run-009"></a>

**RUN-009 — Confidence.** Protected baseline/reassessment and explicit calibration require an unselected-by-default inline confidence choice. Ordinary practice makes confidence optional and expands a deterministic one-in-five invitation; declining does not block Submit. All timed Rapid Recall/fluency tasks suppress confidence collection. Apply the exact invitation ordinal/hash policy in the adaptive chapter; repeated rendering does not count as another presentation. Confidence never changes answer correctness or XP. A response can be edited before submit after choosing confidence; editing invalidates that confidence selection when it materially changes the answer. Formatting-only edits normalized to the identical semantic response do not require recollection. Confidence is frozen atomically with the submitted response.

<a id="run-010"></a>

**RUN-010 — Reflection.** In ordinary practice, show the correction before optional reflection. A suggested error reason is displayed as a suggestion, not a selected learner diagnosis. “Not sure yet” is valid for explicit reflection tasks. Suggested, confirmed and later revised reasons are distinct fields. Reflection notes cannot alter the original response, score or correctness. Saving/closing must work during every reflection stage, including an explicit pre-feedback task.

<a id="run-011"></a>

**RUN-011 — Protected evaluation and feedback.** Protected checks may use deterministic evaluation or a validated consistent AI evaluator protocol. Pin its rubric, model/provider configuration, language, scoring scale and uncertainty/review policy for the form; use only benchmarked compatible fallbacks. Provider/model drift or loss of capability pauses evaluation or records an ungraded outcome under the form policy, rather than silently changing measurement mid-form. AI evaluation can receive the relevant response, givens and restricted rubric through the configured service. Keep learner-facing feedback separate from evaluator context. During protected checks, show no per-item correctness, score, decisive hint, key, solution-bearing chart summary or error diagnosis. On completion, show dimension summaries and concept guidance. Reusable protected exact keys remain hidden in ordinary history. Practice this skill launches a separate instructional variant. Exact feedback may be exposed only for a separately designated retired/disclosed form, with a durable exposure event that permanently excludes that form from future protected selection; this is not the default release flow.

<a id="run-012"></a>

**RUN-012 — Reference/self-check.** Submit locks the recalled answer and persists the reveal state before showing a reference. The learner chooses Matched, Partly or Not yet. Display neither “Correct” nor “100%” for that self-rating. A supplied model reference does not by itself become a grading authority. Rubric-based AI grading is a separate supported route, clearly labeled as AI evaluated and validated under RUN-008; do not force source recall or explanatory answers into self-check merely because they are prose. A learner may pause after reveal and resume the same revealed state; reopening must never restore independent eligibility. Unrated revealed responses remain incomplete self-checks, not wrong answers.

<a id="run-013"></a>

**RUN-013 — Hint progression.** Authored and AI tutoring hints share the same durable assistance/exposure ledger. Save the exact accepted AI hint, its grounding references and provider/model/protocol receipt before showing it; retries/relaunch replay that hint rather than generating a different stage. Failed or cancelled requests do not count as help, while any revealed substantive hint does. `nextHintIndex` starts at zero. Requesting a hint reveals that stage once and appends an assistance event with stage, clock offset and content version. Repeated taps while the disclosure is in flight do not reveal multiple stages accidentally. The next button says Next hint while stages remain. The final action is See worked solution, never a disabled dead end. Solution reveal creates a revealed/not-independently-scored outcome; it must not submit a fabricated answer. A fresh repair question is a new slot with its own evidence eligibility.

<a id="run-014"></a>

**RUN-014 — Skip.** Skip creates a durable skipped outcome with reason optional. It has no graded credit denominator or proficiency weight, whether the available evaluator is deterministic or AI. The selection/exposure ledger still records the displayed item. Three skips are not automatically three incorrect answers. Repeated skipping may offer an easier or different activity, but never imposes a hidden skill penalty.

<a id="run-015"></a>

**RUN-015 — Next and repair.** Next reserves/activates exactly one next slot. The UI must not call the generator twice as view state changes. Retry similar preserves the original attempt, creates an explicit repair slot, selects a different semantic instance, and marks any repeated structure/context so the evidence reducer can limit independence. Repair work is shown as additional optional practice; it does not silently grow a promised fixed-count quiz or change a canonical daily block's completion contract.

<a id="run-016"></a>

**RUN-016 — Ending.** End session is distinct from completing all planned work. Completed attempts stay; unanswered slots have no score. The summary says “Ended after 3 of 10 questions,” not Completed. Unused already committed mixed-bank reservations remain consumed under the no-replacement policy. End is not Delete. Ending an unfinished protected check saves its accumulated evidence and exposure; it never rerolls unseen difficulty simply because the learner closes it. Submitted answers awaiting AI evaluation are listed separately from graded/completed work and retain their jobs/context. A later accepted grade attaches to the original ended run without silently changing its stop reason or planned count.

## 4. Item checkpoint contract

<a id="data-001"></a>

**DATA-001 — Exact item snapshot.** Before presenting an item, persist the descriptor plus a versioned `ExerciseSnapshot` sufficient to reconstruct the exact learner-visible question: prompt, essential givens, table/diagram parameters, option IDs and original displayed labels/order, input schema, source citations when permitted, locale, units, assistance stages, feedback reference, display-policy flags, content hash, semantic fingerprint, structure ID and real demand vector. Images use app-managed content-addressed assets; no transient file URL is a permanent reference. Protected snapshots contain only learner-visible givens and a verified evaluator reference, never an exportable hidden answer key.

<a id="data-002"></a>

**DATA-002 — Evaluation identity.** Pin `evaluationContractID`, contract digest, authority and scorer/protocol version. AI evaluation additionally pins rubric ID/version/digest, provider and model identifier/revision when exposed, request-template version, output schema, relevant generation settings, locale and source-context digests. Record unavailable model revision information honestly; never invent reproducibility from a marketing name. Retain the permitted exact context/rubric needed to explain the saved decision and the accepted structured criterion results, evidence references and learner-facing rationale. Do not require hidden model reasoning.

For composite evaluation, retain a parent evaluation-plan digest and stable component IDs, each component’s authority/contract/input-dependency digests, accepted receipt or explicit pending state, and the aggregation rule/version. The aggregate receipt names the exact component result IDs/digests it used; a provider cannot replace an exact subresult or silently change the component weights.

An already accepted result replays from its immutable receipt even if the provider is offline or retired. An unevaluated saved response uses its still-valid pinned protocol or an explicitly compatible, recorded fallback. A service configuration/model change cannot silently regrade history. Invalidated contracts preserve the original work and use a recorded correction, replacement or recovery policy. If no suitable evaluator is available, save the ungraded answer and explain the available next action.

<a id="data-003"></a>

**DATA-003 — Current-item fields.** Persist the following together with the run revision:

| Field group | Required values |
|---|---|
| Identity | sessionID, slotID, stable attemptID, snapshotID/digest, reservation path index |
| Phase | answering/evaluating/awaitingEvaluation/feedback/comparison/reflection state, exact reveal flags, committedAttemptID |
| Response | typed draft, original text, selected IDs, ordering/evidence map/trace state; response schema version |
| Confidence | selection or absent, invitation policy, response semantic hash at selection, lock status |
| Assistance | each revealed hint ID, solution/reference reveal, assistance stage index, interrupted assistance UI state |
| Timing | accumulated active milliseconds for this item and session, durable active-segment chunks, observed confidence-interaction intervals, timer eligibility, current foreground segment token, segment sequence, stop-at-submit offset |
| Input | modality and calibration version, accessibility/accommodation flags, material response revision count |
| Interruption | pause/background/relaunch/ownership-change reasons and counts; unknown gap flag |
| Scratchpad | text, drawing bytes, format version, viewport/tool metadata if needed; asset digest |
| Feedback | immutable result/reference and policy-permitted explanation snapshot, expansion state optional; protected checkpoints omit keys, decisive explanation and exportable per-item evaluator internals |
| Reflection | trigger/inferred suggestion/learner reason/note/confirmation status/version |
| Selection | consumed candidate IDs, semantic fingerprints, actual descriptor path, policy decisions and any fallback reason |
| Evaluation | parent evaluation/job/command ID, frozen response/context digest; component IDs with input/contract digests, accepted receipts or queued/dispatch/pending state, remote request IDs, retry/deadline/spend state; aggregate-rule digest, required-component readiness and pending review scope |
| Save | checkpoint revision, last acknowledged wall-clock date, commit-intent phase |

<a id="data-004"></a>

**DATA-004 — Time accounting.** Use a monotonic clock within a process. Add each active segment once; do not infer active duration from wall-clock time across a relaunch. Accumulated duration survives pause/close. Background, manual pause and ownership transfer stop active measurement. Returning to foreground starts a new answer-time segment only after explicit run resumption into an eligible visible answering state. Paused, AI/provider evaluation wait, feedback, comparison, reflection, loading and summary phases never accrue answer-solving time; separately labeled session-use time may include other active learning phases. Foregrounding does not reset earlier time. An unknown interval caused by termination is marked interrupted/unknown and excluded from clean speed evidence. The learning UI may show a measured lower bound if the last segment could not be recovered, with no false precision.

Persist confidence-control interaction intervals under EVD-009, union overlapping intervals and subtract them once from answer duration. Keep them in active sitting time for budget accounting. Do not claim that UI events measure private deliberation or pure thinking time. Timed fluency suppresses confidence; other conditions retain their explicit measurement scope.

<a id="data-005"></a>

**DATA-005 — Clock edge cases.** Timezone, daylight-saving and manual system-clock changes must not alter active duration or replay ordering. Wall-clock timestamps support display/scheduling; transaction sequence and explicit event relationships support ordering. Tests inject a fake monotonic clock and independent wall clock. No item can have negative time, nonfinite time or duplicate segment accounting.

<a id="data-006"></a>

**DATA-006 — Save guarantees.** Autosave drafts after a proposed 500 ms idle debounce and immediately on explicit pause, background transition, save/close, navigation away or ownership transfer where the OS permits. “Saved” means an acknowledged durable write. A sudden crash can lose unacknowledged keystrokes; the interface must not claim otherwise. Explicit Save & close flushes the current draft and local commit/job state before dismissal. It need not wait for an external AI result: a durably saved pending job uses the truthful waiting state in RUN-022. If that fails, keep the screen and input intact.

<a id="data-007"></a>

**DATA-007 — Scratchpad portability.** Notes and drawing bytes are preserved independently of whether the current platform can render/edit both. Opening an iPad drawing on Mac and closing the editor must retain identical drawing bytes. Unsupported drawings show a retained-preview or “Drawing saved; editing is available on iPad” message, with text notes still editable. Clear operates only on the selected layer and has Undo during the session; it is never implemented by replacing the entire payload with empty drawing data.

<a id="data-008"></a>

**DATA-008 — Resume algorithm.** Resolve the stored run, verify its schema and ownership, reconcile pending commits and evaluation jobs without blindly redispatching a remotely uncertain request, verify the current snapshot digest, apply content invalidation records, restore exact slot/phase/draft/assistance/time, then enable controls. Do not regenerate the current item from only seed+index. A committed slot resumes its exact policy-permitted phase: ordinary feedback, protected acknowledgement, reference comparison, reflection or summary, unless the previously acknowledged transition activated the next slot. Apply the display/exposure policy before constructing any visible or accessibility output. An unanswered draft can never be attached to a different item because of a deduplication fallback.

<a id="data-009"></a>

**DATA-009 — Language changes.** App chrome can follow a changed language immediately. A current saved question stays in its recorded content locale until the learner completes or explicitly restarts that item unscored. New items may use a supported new locale after recording the policy transition. Option identity, answer interpretation and decimal parsing follow the active item’s explicit response contract; they do not drift when Settings changes. Expose a plain-language explanation if question and chrome language differ.

## 5. Commit, crash and conflict behavior

<a id="data-010"></a>

**DATA-010 — Idempotent evaluation and commit protocol.** Deterministic, AI and composite grading share the durable response→component results→aggregate attempt→feedback contract. A single-evaluator item is a one-component plan. Reference/self-check keeps its separately declared unscored lifecycle; self-rating is never synthesized into an evaluated component grade.

```text
submit(commandID, ownershipGeneration):
  reject stale ownership or incompatible phase
  validate structural response requirements and required confidence
  freeze response + timing + assistance + snapshot/context digests
  persist evaluation intent(stableAttemptID, planDigest, componentBindings, aggregateRule)
  for each unresolved graded component in declared dependency order:
      preserve any previously accepted matching component receipt
      if required dependency is unresolved: retain component pending; continue
      if component.authority == rubricAI:
          persist job/dispatch identity bound to component, input and pinned protocol
          await eligible configured provider within component and parent budgets
          on unavailable/timeout/unknown outcome: persist pending state; continue
          validate output, criterion bounds, grounding and protocol binding
          on insufficient judgment: preserve unresolved component; continue
      else if component.authority == deterministic:
          evaluate exact component input against its pinned contract
          on clarification/invalid item: retain subresults; apply declared policy; continue
      persist validated component receipt with input/contract/result digests
  if any aggregate-required component lacks a validated terminal result:
      persist awaitingEvaluation with accepted subresults + unresolved jobs
      publish no final aggregate grade or graded evidence; return
  aggregate = applyPinnedRule(exactComponentReceiptSet)
  validate aggregate bounds, correctness and eligibility against declared rule
  persist aggregate receipt + prepared CommitIntent(stableAttemptID, digest)
  appendOrFindIdenticalAttempt(stableAttemptID, digest)
  persist checkpoint(phase = feedback or protectedAcknowledgement,
                     committedAttemptID = stableAttemptID)
  acknowledge intent
  publish rebuilt evidence/reward projections
  render the saved phase through its protected/self-check/practice display policy
```

Independent components may execute concurrently within the plan’s declared dependency and spend limits. Component durability is not final-attempt acknowledgement. A failed prose request does not discard, recompute or overwrite a valid exact subresult; retry only unresolved components and reuse the accepted receipts whose dependency digests still match. Aggregate computation is deterministic over accepted receipts and the pinned rule, even when some receipts came from AI. No partial-result renormalization, assumed missing-component zero or guessed full credit is allowed.

Each asynchronous stage uses immutable values and rechecks job identity, byte/revision CAS and writer generation at durable acceptance. A valid late result may be retained for its original frozen job after navigation/cancellation, but cannot overwrite a changed response or another slot. Cancellation applies to the selected pending jobs/components and leaves already accepted component receipts intact. Cancellation that wins before local result acceptance records a cancelled job; a later remote receipt stays unapplied unless that frozen job is explicitly resumed. If durable acceptance wins first, adopt its result despite cancellation. Switching to an allowed self-check path durably supersedes the grading job so a late callback cannot turn a revealed self-rating into independent evaluated evidence. No partial streamed output is a final grade. A rename accepted but not yet verified is retained for recovery; learner feedback waits for the required durable acknowledgement.

Use provider idempotency keys and status/result lookup where supported. Persist request identity before dispatch. A timeout or process death can leave the remote outcome unknown: reconcile first; do not promise exactly-once external billing when the provider cannot guarantee it. Record every bounded retry under the same logical job, with backoff and a maximum attempt/spend budget. One locally accepted result wins per component job, and one aggregate commit wins per attempt; duplicate or conflicting callbacks are retained/rejected by those identities and cannot award again. A user-requested reevaluation is a separate linked review job, not a transport retry that hunts for a higher score.

Clarification/invalid-input outcomes close the evaluation revision without an attempt or score. Further edits create a new response revision and job binding; stale callbacks remain attached to the old input. In a composite, preserve old receipts as history and reuse one for the new plan only when its full declared input/contract dependency digests are identical. Reevaluate changed components and their declared dependents, never silently rebind an accepted result to different input. When response/context is sufficient but judgment is uncertain, preserve it for compatible review rather than inviting answer changes under the same submitted identity.

The job policy declares supported languages/context sizes, timeout, bounded retry count and cost/latency limits. Show the chosen service and useful waiting/retry state; enforce configured spend limits without an approval prompt for every normal request. If a limit or capability is unavailable, offer a suitable approved local/less costly route, save for later, or change the configured limit explicitly. Local processing enables reasonable offline practice; it does not imply every cloud model can run offline. Cancel stops queued work and attempts cancellation of in-flight requests. Explain any known request already sent or possible charge; retain the answer and any committed receipt. Never equate a UI cancellation with deletion of remote work.

Requested AI grading/tutoring may send the relevant answer, source passages and rubric through the normally configured service. Credentials stay in the platform credential store; request logs omit secrets and unnecessary source/answer copies. Treat learner/source text and model output as data: delimit roles, constrain output schemas and lengths, reject unsupported references/actions, and never execute an instruction embedded in an answer or retrieved source. This protects grading integrity without forbidding useful source-grounded AI.

The journal and evidence records may be in different configured stores. Do not assume SwiftData offers an atomic transaction across disjoint stores. Durable intents, stable IDs and reconciliation provide recoverability. Where records share one store, one transaction may replace the two-phase persistence without changing the observable contract.

A protected receipt retains the response, evaluator/rubric/provider reference, eligibility and minimum versioned internal outcome inputs needed for recovery. Solution-bearing expected answers and worked explanations stay out of generic checkpoints, history and user-facing exports. Restricted evaluator context may be processed by the configured AI service under the form protocol; learner exports use an opaque receipt/reference plus permitted aggregate results. Apply protection before text, accessibility or export construction. This is a disclosure policy, not a claim of cryptographic secrecy against an owner inspecting a local executable.

A protected response that cannot be judged under its validated authority remains authentic and ungraded; it does not switch to answer-revealing self-check mid-form. Clarification may request supported input without exposing a correct answer. Apply the form's compatible fallback, delayed evaluation, replacement/cap or unavailable policy without inventing a zero score.

<a id="data-011"></a>

**DATA-011 — Crash boundaries.** Before intent persistence, resume the last acknowledged draft. After an AI job is durable but before dispatch, resume or cancel that job; after dispatch with unknown remote outcome, reconcile it before retrying. After a component result is saved, replay it without another evaluator call and resume only unresolved components. After all required components and the aggregate receipt are saved, finish committing that exact aggregate without regrading. Provider result receipt and local attempt acknowledgement are distinct boundaries. After intent but before attempt write, retry the same attempt ID. After attempt write but before checkpoint update, find the identical attempt and advance the checkpoint without evaluating/awarding again. After checkpoint update but before UI feedback, render the saved phase through its display policy: a protected commit produces acknowledgement, never ordinary answer feedback; self-check restores reveal/comparison/rating state. At no boundary may Next create a duplicate attempt or the same response appear as both scored and unscored without an explicit correction record.

<a id="data-012"></a>

**DATA-012 — Payload conflict.** An existing identical attempt ID with a different response/result digest is a conflict, not a normal overwrite. Retain both raw records in recovery diagnostics, exclude the conflict from derived proficiency until resolved, show a recoverable save problem, and prevent duplicate XP. Local actor ownership and stable identities should make this exceptional. CloudKit object IDs are not sufficient for domain uniqueness; preserve the repository’s deterministic domain deduplication without deleting unseen peer objects during ordinary reads.

<a id="data-013"></a>

**DATA-013 — Derived state.** XP, completion, progress, review scheduling and proficiency update from committed authoritative records and versioned correction/exclusion events. They must be rebuildable. An interrupted replay cannot add XP twice. Optional confidence, reflection length, retrying a failed save, view appearance and navigating back never award points. Retain existing reward values during the reliability release; this specification changes correctness/idempotency, not the reward economy.

<a id="data-014"></a>

**DATA-014 — Save failure UI.** Show “Your answer is still here. NeuroForge couldn’t save it.” with Retry save and Keep working where safe. Provide Copy answer/Export draft for prolonged local failure; do not automatically send diagnostic data. An already scored-but-not-acknowledged response stays locked while retrying that commit; the learner cannot edit it into a new payload with the same attempt ID. A failed draft-only checkpoint may remain editable and produce a later revision.

<a id="data-015"></a>

**DATA-015 — Reservation atomicity and adaptive delivery.** Use two explicit reservation strategies. `fixedBlock` reserves the exact predetermined block when launch is durably accepted. `adaptiveItem` reserves and consumes one exact first item at accepted launch, then one exact next item per committed selection decision before presentation. A fixed challenge band may still use adaptive item selection for family/spacing; fixed-band does not imply fixed-block. The whole-epoch permutation is a candidate-priority recipe, not a promise to deliver contiguous positions despite changed eligibility. Seeking past an ineligible candidate leaves it unconsumed; use a consumed-position set plus stable decision IDs rather than a scalar cursor alone.

Commit the consumed position, chosen descriptor/snapshot, slot and decision record atomically within the local reservation store. The same decision ID must return the same chosen item after retries. Cancelling before durable acceptance consumes nothing; cancelling afterwards leaves the accepted identity consumed even if never displayed. Consumption and actual exposure are separate records. Advisory prewarming may prepare at most two unreserved candidates; it confers no lease and consumes nothing. An override may invalidate that advisory work. A presented or committed slot is immutable; an explicit Replace marks it replaced/consumed and reserves a distinct linked next slot. Already reserved unused fixed-block items remain consumed if replaced or abandoned. Protected adaptation follows a versioned preauthorized form policy, never an ad hoc easier item.

Maintain run-wide semantic exclusions across epoch boundaries so a quiz cannot repeat itself. Check capacity and finite termination before accepting a fixed requested block; for adaptive delivery, validate current feasibility and disclose later eligibility/exhaustion limits without inventing a completed count. The selector returns explicit failures; the coordinator cannot relax truth, protected exposure, source access permissions or exact no-repeat to make the screen continue. Failure to build a candidate never returns an already accepted identity to the front.

## 6. Storage scopes and record additions

<a id="data-016"></a>

**DATA-016 — Proposed schema additions.** V2 needs the following logical records. A Codable envelope can combine physically small records, but the invariants and storage scopes remain mandatory.

| Record | Key | Purpose / retention |
|---|---|---|
| `SessionRunEnvelope` | sessionID | Complete launch and lifecycle state; local resume ownership |
| `SessionSlotRecord` | sessionID+slotID | Ordered exact item path, snapshot reference, selection decision |
| `SelectionDecisionRecord` / `ConsumedPositionLedger` | decisionID / profile+lab+edition+lane+epoch | Idempotent fixed/adaptive reservations, exact consumed positions and separate exposure; transactional with local run/slot acceptance |
| `ExerciseSnapshotRecord` | snapshotID/content digest | Original learner-visible content and feedback; retained while referenced |
| `ItemCheckpointEnvelope` | sessionID+slotID+revision | Current draft and timing/assistance state; latest acknowledged revision plus recovery predecessor |
| `CommitIntentRecord` | stableAttemptID | Recoverable prepared/acknowledged write; compact acknowledged entries after reconciliation |
| `EvaluationJobRecord` | parentEvaluationID + componentID + jobID/dispatch ordinal | Frozen component input/protocol/dependencies, pending state, remote identity and bounded retry/cost; retain accepted sibling receipts and compact redundant transport data after reconciliation |
| `EvaluationResultReceipt` | resultID + parentEvaluationID/componentID | Accepted component grade, criterion rationale/evidence and evaluator/input/result digests; aggregate receipt references exact component results plus rule/version; retained with its attempt |
| `GradeReviewRecord` | reviewID + originalAttemptID | Disputed component IDs/aggregate rule and concern, affected dependencies, linked reviewer/evaluator receipt and append-only resolution; no duplicate attempt or reward |
| `AttemptEvidenceEnvelope` | attemptID+schemaVersion | Extends immutable attempt with band/demand/eligibility/context and evaluator-authority flags |
| `EvidenceDispositionRecord` | dispositionID | Append-only include/exclude/correct/supersede event with a reason and version |
| `ContentInvalidationRecord` | ruleID+contentVersion | Signed known-invalid item/family predicates; active until superseded |
| `LearnerBandProjection` | objectiveID+modelVersion | Disposable reducer output; source evidence references and freshness |
| `ReviewTaskRecord` | taskID | Due target, origin attempt, scheduling policy and task state |
| `SavedStudySetRecord` | setID | Explicitly saved question collection in its declared storage scope; no cache TTL |
| `SavedStudySetItemRecord` | setID+itemID | Pinned local question/reference snapshot and practice history link |
| `LearnerBookmarkRecord` | bookmarkID | User’s private saved activity/question pointer and optional note |
| `LocalNavigationState` | windowID | Valid per-destination paths for this app run; disposable |

<a id="data-017"></a>

**DATA-017 — Storage and AI processing scopes.** Separate local persistence, optional history/source sync, requested AI processing and diagnostic/research collection. They are different operations. A cloud AI feature may process relevant answers, source excerpts and rubric context using the learner’s configured service; no additional per-answer or per-run privacy approval is required for that ordinary requested operation. Offer clear service settings and an offline/local-only mode for availability or preference, with honest capability limits. Local processing exists to keep suitable learning tasks useful offline and responsive, not as a blanket prohibition on cloud intelligence.

Keep resume ownership, transaction journals and credentials device-local. Persist instructional content/results in the declared collection/history scope; sync them only through the configured supported sync feature, never by accidentally adding a relationship to a cloud store. Cloud processing does not itself mean a collection is synced, and local storage does not mean its selected passages cannot be used by a requested AI feature. Use stable ID references across stores and recoverable commits; enforce account separation and platform file/credential protections.

<a id="data-018"></a>

**DATA-018 — Legacy scope and service use.** Preserve existing durable records, original bytes and established sync behavior during migration. Inventory legacy source-associated fields and keep them readable; do not copy an entire source index to cloud storage as an implementation shortcut. Preserve existing explicit per-source Offline only/local-only restrictions during migration; generic service configuration does not erase them. Automatic applies to new or previously unset source policies. Ordinary use of a configured AI feature can transmit relevant retained context, including selected legacy answers/sources whose recorded policy permits that route. Recheck explicit source restrictions before dispatch. A restricted source can use a suitable local capability or remain pending until its source setting is explicitly changed; this is not a new per-run consent step. Explain this once in service configuration and accurately describe local, cloud and offline capabilities. Changing a sync setting is distinct from requesting AI processing; do not require a second consent ceremony for each supported feature action.

<a id="data-019"></a>

**DATA-019 — Content storage.** Public built-in snapshots may deduplicate by content digest. Source snapshots deduplicate only within the appropriate account/collection storage scope; do not leak equality across users/accounts or source-policy boundaries. Retain blobs while an attempt, unfinished run or saved collection references them. Cache eviction may remove only unreferenced disposable objects. Garbage collection uses a transactional reference scan and retryable tombstones, not file age alone.

Temporary generated-set inventory expires for new launches after seven days. Explicit Save set creates a durable collection in its declared storage scope, retained until the learner deletes it. Expiry of temporary inventory does not delete a submitted attempt's permitted instructional snapshot or break an already accepted suspended run: that run pins the exact set members/assets required to finish its original contract. Continue remains available for that run, while New practice from the expired temporary set is unavailable unless it was explicitly saved. This pin does not make the set a permanent reusable collection. Once the run is ended/completed, retain only attempted-history, saved-collection and other genuine references; release unneeded unattempted inventory through garbage collection. Copy must distinguish “Temporary sets are available for new practice for 7 days” from retention of already saved answers/unfinished work. Explicit deletion still follows the linked-history/unfinished-work impact preview and user choice.

<a id="data-020"></a>

**DATA-020 — Size and corrupt input.** Check sizes before decoding images, drawings, archives or generated payloads; bound AI request context, response bytes, nesting, criterion count and string lengths before parsing or rendering. Oversized or adversarial source/answer text must not change the grader’s instructions, execute code, expose credentials or silently truncate away decisive answer context. Use an explicit bounded context selection/chunking policy and retain its references; report insufficient context when faithful evaluation is impossible. Preserve existing source-import limits unless a separately tested change replaces them. A malformed snapshot reports one unavailable history item; it must not crash or block all history. Corrupt private media can be exported as original bytes for user recovery but is never executed. No arbitrary code from imported sources is run.

## 7. Readable history and correction policy

<a id="data-021"></a>

**DATA-021 — Presentation is typed.** A `ResponsePresentation` renderer supports all eight response schemas. Numeric: value plus unit; choice: original selected label; multiple choice: selected labels; ordering: numbered original step labels; short text: original response; self-check: recalled text plus separate self-rating; claim/evidence: readable associations; trace: variable/value rows and selected rule label. Raw JSON remains an archive/debug representation. `normalizedResponse` is not a sufficient display substitute when it contains opaque IDs.

<a id="data-022"></a>

**DATA-022 — Complete review context.** Standard practice history shows original prompt, essential diagram/table/options, Your answer, Correct approach, Why, assistance used, and a fresh-practice action. AI feedback clearly identifies AI evaluation and shows the rubric criteria, score and concise evidence-based explanation. Model/provider/rubric/version details live behind Technical details alongside version/seed/scorer fields. Replay the accepted result without a network call, and offer Request grade review with the original answer/context attached. If original labels/representations are unavailable for a legacy record, explain the missing context and show whatever authentic content remains. Never hallucinate a diagram or label from an ID. Protected display restrictions apply before presentation and before accessibility text generation.

<a id="data-023"></a>

**DATA-023 — Historical evidence correction.** Never update an original `AttemptRecord` response, timestamp, score, confidence or key in place as a content repair. Add `EvidenceDispositionRecord` with originalAttemptID, applicable defect rule/version, disposition, old result digest, optional corrected deterministic or validated AI result, corrected evaluator/rubric/provider receipt, rationale, createdAt and stable idempotency key. A learner-requested review freezes the original response and available question/source context, records the stated concern and uses an appropriate validated reviewer protocol. Show pending, confirmed, revised or unresolved status; no silent automatic replacement or repeated grading until a preferred score appears. For a composite review, identify the disputed components or aggregate rule. Reevaluate only affected components and declared dependents against the original frozen input; reuse unchanged accepted receipts without evaluator calls. Append revised component receipts and a disposition naming the new aggregate receipt, recomputed under the applicable recorded rule. A pending review does not partially overwrite the accepted aggregate; retain it or explicitly exclude it under the disposition policy until the replacement is complete. The effective view presents original and correction when relevant; aggregate calculations consume the effective projection. Corrections are not new learner attempts and earn no XP.

<a id="data-024"></a>

**DATA-024 — Rules for each audited defect.**

| Defect | Safe historical treatment |
|---|---|
| Duplicate equivalent spatial choices | If exact snapshot/descriptor and response identify an equivalent valid choice, append deterministic full-credit correction. Otherwise exclude affected score with explanation. |
| Contradictory science interval prompt/key | Mark affected item invalid and exclude it from proficiency, accuracy denominators, speed and improvement claims. Do not infer what the learner would have answered to a corrected prompt. Preserve effort/participation history. |
| Accepted equivalent state got partial credit | If the exact old accepted-equivalence contract confirms validity, append full-credit correction; preserve original raw response. |
| `f`/`F` mathematical false acceptance | Correct only if exact original response and question roles are available under reviewed rules; mark prior result revised. No negative XP. |
| Rigid prose matching rejected a reasonable answer | Reevaluate authentic retained responses with a validated semantic rubric and suitable AI or deterministic evaluator. Preserve the original result, attach model/rubric/provider provenance and append the justified correction. For batch repair, first validate representative disputed/unchanged controls and review uncertainty; missing question/source context produces unresolved/excluded evidence rather than an invented grade. |
| Learner disputes an AI grade or a provider/rubric defect is discovered | Preserve the original accepted grade and request receipt; append a bounded review job and resolution. Use exact original input, disclose changed evaluator/rubric, and rebuild effective evidence once. Self-rating alone does not override evaluated correctness. |
| Self-check was stored as objective correct/100% | Preserve original bytes and append a `selfReported` disposition when source/type provenance identifies the record; remove it from verified accuracy, proficiency and calibration. Retain effort, the original recall and the authentic learner rating. Unknown provenance remains unknown, not guessed from the displayed percentage. |
| Difficulty was metadata-only | Preserve historical practice accuracy as historical where content is valid; mark demand provenance `legacyUncalibrated`. Exclude it from new band/proficiency claims that require actual reviewed demand. |
| Resumed item lost timing/assistance | Mark timing provenance incomplete; exclude from clean speed and affected independent-evidence claims. Never reconstruct missing seconds or hints from guesses. |
| Report awaiting adjudication | Locally quarantine future presentation immediately; unresolved report is not automatically proof that every old response was wrong. Separate user report from verified invalidation. |

<a id="data-025"></a>

**DATA-025 — Communicating corrections.** After a correction changes a visible aggregate, show a one-time, dismissible “We corrected some question results” notice linking to affected items and the specific reason. State whether questions were excluded or scores corrected. Do not imply the learner regressed when only the measurement changed. Retain dismiss state separately; do not force repeated alerts on every sync/relaunch. No product claim or chart may silently compare incompatible old/new scoring regimes.

## 8. Navigation contract

<a id="run-017"></a>

**RUN-017 — Five destinations.** Use Today, Practice, Progress, Sources, Settings. Review and History are explicit destinations inside Progress, with Today shortcuts. Use one typed route family per top-level destination. Do not add a sixth tab for review and do not let a pushed Document or Answer review remain attached to a newly selected root.

<a id="run-018"></a>

**RUN-018 — Path ownership.** While the app is open, each destination owns its own validated path. Switching destinations displays that destination and its own path. Tapping the already selected tab/sidebar item returns that destination to its root after any dirty-work guard. Back pops only the current destination. Selection highlight, navigation title, visible content and accessibility destination identifier update as one transition.

<a id="run-019"></a>

**RUN-019 — Cold launch and recovery.** Ordinary cold launch opens Today root with Continue when a valid unfinished local session exists. Explicit validated deep links override that start location. Avoid automatically restoring a problematic deep path after a hang. Disposable navigation state includes a schema version and is pruned when referenced records no longer exist. No route string can force decoding arbitrary code, access another account’s sources or invoke an unconfigured service.

<a id="run-020"></a>

**RUN-020 — Transactional route intents.** A route intent contains destination, typed path, optional source import/review continuation, and a unique intent ID. Dirty-work Save/Discard/Cancel applies to the whole intent. Cancel drops all its payloads; Save completes before navigation; Discard affects the draft only after an explicit choice. An external route arriving while answering offers safe pause/save and continuation; it never replaces the active item behind the learner’s back. Replayed callbacks with the same intent ID are idempotent.

<a id="run-021"></a>

**RUN-021 — Implementation constraint.** Use stable, state-driven navigation paths rather than resetting an entire nested view subtree with changing `.id` as the primary routing mechanism. This is the target architecture for the observed stale-detail defect; it is not a claim that the beta-OS hang's exact cause is proved. Apple documents state-driven paths and Codable restoration; choose typed enum routes whose decode/validation is under app control. [Apple: NavigationPath](https://developer.apple.com/documentation/swiftui/navigationpath)

<a id="run-022"></a>

**RUN-022 — Safe exit during work and failure.** Every visible phase accepts an exit intent. While disposable generation is running, cancel it and retain the previous acknowledged state; an accepted reservation remains consumed. During submit/self-check commit, queue close and reconcile the write. During an AI evaluation wait, Save & close preserves the frozen answer/job and shows “Answer saved; evaluation pending.” Closing need not wait for a network response. Request cancellation is explicit and respects DATA-010’s possible remote completion/charge; a later result cannot navigate or replace the current screen. If a durable recovery intent exists but the destination store remains unavailable, permit close with a truthful “Answer waiting to finish saving” state and recover that exact intent on resume; do not show ordinary saved-success or erase the journal. Before any durable intent/checkpoint exists, retain the UI and offer Retry, Keep editing, Copy/Export recovery or explicitly Discard unsaved changes to the last acknowledged checkpoint. Discard never deletes committed attempts or a prepared intent. Explain exactly which unacknowledged text would be lost. These policies also govern dirty-work navigation and window closure; a convenience dismissal cannot bypass them.

## 9. Store and archive migration

<a id="mig-001"></a>

**MIG-001 — Freeze the shipped schema.** Before modifying any persistent model, capture the actual shipped V1 metadata and create a genuinely frozen versioned schema definition. Current `NFSchemaV1` lists live model types; simply editing those types and adding a new enum is not proof that V1 metadata stayed compatible. Preserve entity names, property renaming identifiers, defaults, encryption flags and durable/local partition membership. Add `NFSchemaV2` with an explicit migration plan and test every distributed prerelease metadata variant that must remain supported. Apple’s schema migration APIs provide the framework; compatibility still needs actual store fixtures. [Apple: SchemaMigrationPlan](https://developer.apple.com/documentation/SwiftData/SchemaMigrationPlan)

<a id="mig-002"></a>

**MIG-002 — Additive first.** Introduce new optional/additive envelopes and local stores before requiring them. Keep old raw attempts readable. A deterministic background backfill may add display/evidence envelopes, but each record carries its backfill status and original digest. Progress can show a bounded Updating history state while projections rebuild; it must not show a false zero. Preserve the previous known-good projection until a replacement is complete and consistent.

<a id="mig-003"></a>

**MIG-003 — Legacy sessions.** For each unfinished checkpoint, classify recoverability: exact snapshot/request/path available; reconstructable with a verified historical generator and full selection history; or incomplete. The first two can migrate with an interruption flag and retained evidence provenance. The last shows “This older session can’t be resumed exactly” and offers its saved answer/notes plus Start new practice. Do not attach the old draft to a newly generated problem. Already committed answers remain in history. Do not count an unavailable unfinished run as completed.

<a id="mig-004"></a>

**MIG-004 — Content epoch transition.** New corrected/balanced catalogs use a new signed content version. Preserve consumed semantic identities where stable mappings exist. A catalog migration must not claim 1,000 newly unseen questions by resetting all IDs or shuffling labels. Preserve old consumed identities in a versioned ledger, document equivalent-identity mappings, and start a new epoch only according to the published epoch policy. Remove invalid items without silently weakening reviewed content floors; replenish and sign before enabling affected mixed-bank launches.

<a id="mig-005"></a>

**MIG-005 — Archive version.** The 4 September audit recorded full archive version 17 and oldest restorable version 14; verify the actual supported versions at implementation time. Add a new archive version for the new records; do not reuse 17 with an incompatible payload. The provisional next value is 18, verified against the repository at implementation time. Round-trip tests must cover 14–17 into the new reader and new→empty-new installation. Do not promise new archives can be restored by an old app. Unknown future archives fail with a readable update-required message before mutating stores.

<a id="mig-006"></a>

**MIG-006 — Export completeness and protection.** The full archive includes original attempts, disposition/grade-review history, accepted AI result receipts, recoverable pending jobs, authentic review snapshots permitted by protection policy, saved sets, notes/drawings, unfinished runs and source links needed for honest reconstruction. Credentials are excluded. User-facing exports never introduce reusable protected exact keys. A protected run retains its evaluator reference and policy-safe accepted receipt. Already accepted permitted summaries replay without contacting the provider; unevaluated protected work without a compatible evaluator stays unavailable/recoverable rather than disclosing an answer. Original source files follow the explicit export selection already supported; exports explain when only references/text are included. Record counts, stable identities and content hashes are independently validated.

Apply protected per-field allowlists before export, migration fallback decoding and accessibility presentation, not just by hiding a final view. Import never relaxes a protection/exposure flag because a newer evaluator or presentation adapter is missing.

<a id="mig-007"></a>

**MIG-007 — Restore transaction.** Validate version, schema, sizes, hashes, references, account/storage scope, evaluation receipt bindings and conflicts into a temporary staging store. Present a preview with counts and conflicts. On commit, apply idempotent inserts/merges, preserve originals, then materialize files and verify references. If materialization fails, retain a recoverable transaction and do not announce complete restoration. A retry must not duplicate attempts, sets or correction notices. Restore into a nonempty store requires explicit, deterministic merge policy; no silent destructive replacement.

Restored AI grades render their saved permitted receipts offline. Pending remote jobs require verified provider/account/request identity before lookup or redispatch; importing a backup cannot silently incur new model charges or regrade completed history. Imported run envelopes enter suspended/read-only recovery first; they never acquire a writer merely by decoding. Exact writable continuation is permitted only when the original local owner identity can be verified and the installed ownership coordinator reconciles it with any existing run. A different-device or unverifiable-owner restore preserves original run/slot/provenance and draft for readable recovery, but offers a separate fresh practice run rather than mid-question continuation. It does not rebind a protected form into a second writable incarnation. Existing identical committed attempts deduplicate by identity/digest; conflicting run revisions are shown separately for recovery and never field-merged. The restore preview explicitly lists resumable versus read-only unfinished runs. This release deliberately does not add archive-based cross-device live handoff.

<a id="mig-008"></a>

**MIG-008 — Rollback.** Before migration, retain a protected recoverable store package using the app's existing recovery mechanism. A failed migration opens recovery/read-only mode, not an empty app. Rollback means restoring a compatible prior package with a compatible binary, not opening a V2 store with an old binary. Retain logs with redacted reason codes. Do not delete old models or migration code in the same release that first adopts V2.

<a id="mig-009"></a>

**MIG-009 — Cloud deployment.** Validate new durable metadata against a development container and then the production-equivalent schema before distributed sync testing. Additive local-only records must never appear in the durable configuration. Preserve required platform entitlements, account controls and the configured sync choice. Do not advertise cross-device feature readiness because an unsigned simulator build passes. Source excerpts or generated content enter sync only through their declared supported storage scope. This sync rule does not prohibit transmission to the configured AI provider for a requested learning operation. Validate direct cloud and available on-device adapters independently of CloudKit; a Shortcut integration can supplement them but is not the sole AI architecture.

<a id="mig-010"></a>

**MIG-010 — Deletion and account lifecycle.** Update the existing deletion/export/privacy inventory for every new record, blob, journal, saved set, bookmark, projection and cache. Device-local deletion stays local; private-cloud deletion follows the established separate action and retryable tombstones. Account changes cannot attach one account’s private source snapshots to another account’s history. A cancelled/failed cleanup names unfinished components and remains retryable; no early success state.

## 10. Required runtime acceptance examples

| Scenario | Expected invariant |
|---|---|
| Save focused Q3/5 with `17` and drawing | Continue shows Q3/5, same question/option order, `17`, same drawing and counters. No new reservation. |
| Save after committed Q3 but before Next | Same committed response and policy-permitted phase returns; no extra score. Next activates Q4 once. |
| Crash after attempt insert but before checkpoint | Reconcile same attempt ID, render saved phase without protected leakage, preserve one reward/evidence contribution. |
| Hint 1 then close/relaunch | Hint 1 stays revealed; Next hint reaches stage 2; hint count remains 1 before the next request. |
| 20 active seconds, pause, 5 after resume | Approximately 25 active seconds; interruption recorded; excluded from clean speed. |
| Reference revealed, rating unsaved, relaunch | Reference remains revealed and response locked; no independent grade; rating may be completed later. |
| Required reflection then Save & close | Saves phase and text; exits safely; resume returns to that phase without rescoring. |
| Locale changed with numeric draft | Original item parser/locale remains pinned; no changed answer or silent new item. |
| Deep Document then Settings | Settings content/title/highlight agree immediately; Back never reveals a foreign destination. |
| Deep answer review then Sources, repeated 100 times | No stale views, sustained CPU loop, crash, unexpected prompt or lost record. |
| Same run opened in second Mac window | One writer; explicit safe takeover; old window cannot submit stale commands. |
| Unknown old snapshot version | One recoverable unavailable run/item; other app features still work. |
| Corrected invalid interval item in history | Original response retained, invalid result excluded with reason, no negative XP or fake learner decline. |
| iPad drawing opened/closed on Mac | Drawing payload hash unchanged. |
| Export→empty restore→resume | Exact run/slot identity, phase and draft retained; writable resume requires verified original local ownership and content. Other-device/unverifiable-owner work is read-only recovery with separate fresh practice. |
| Temporary set expires while its run is suspended | Continue retains the accepted run's exact content; New practice unavailable; attempted history remains readable in its declared scope. |
| Adaptive learner changes band after an answer | One next eligible identity reserved once, bypassed ineligible inventory unconsumed, prewarm discarded safely, no change to current/past items. |
| AI short response uses a correct paraphrase absent from aliases; a composite variant adds an exact quantity | Rubric awards justified prose credit. Exact component receipt survives prose timeout/cold retry; no final full/zero grade or evidence while required prose is pending. Final aggregate follows pinned weights/rule once. History replays both receipts; reviewing prose preserves unchanged exact credit without another evaluator call. |
| Cloud grade times out after dispatch, then app closes | Answer/job retained; remote outcome reconciled before bounded retry; no duplicate local attempt or claim of guaranteed no charge. |
| Cancel after result receipt is durably accepted | Receipt survives, no duplicate score or forced navigation; the original slot can later show its saved result. |
| Offline launch or network loss during source grading | Eligible local practice/grading remains usable; unsupported cloud evaluation stays pending with exact response/context and truthful options. |
| Provider/model retires after a grade was accepted | History replays the accepted result without a model call; unresolved jobs use a validated compatible route or remain recoverable. |
| Learner requests review of an AI grade | Original answer/result immutable; one linked review and append-only resolution; no second learner attempt or XP. |

These examples become automated regression tests plus selected installed-app checks in the [QA and delivery chapter](05_QA_and_Delivery.md). Tests that only search for a source string or submit the canonical key to its own scorer do not satisfy the behavioral contracts above.

# QA, validation, implementation sequence and release gates

Status: proposed implementation contract, version 1.0, 4 September 2026. This is a test and delivery specification, not a report of these future tests passing. The [original QA report](../QA_2026-09-04/README.md) is the authority for what was actually executed. Read the [master specification](README.md) for product decisions and the other chapters for feature requirements.

## 1. What a release must establish

<a id="qa-req-001"></a>

**QA-REQ-001 — Separate the claims.** A passing build, a content signature, a unit test, a successful simulator journey, and a learning study establish different things. The release record shall report each separately. It must not describe the product as fully tested because the existing 541 unit tests and four smoke tests passed. The seven investigative probes in the audit deliberately assert observed defects; they are reproduction evidence. Convert their expectations into regression assertions before adding them to the release suite.

<a id="qa-req-002"></a>

**QA-REQ-002 — Five independent gates.** A release containing the improvements requires all applicable gates below. A staged internal build may meet only an explicit subset, but the enabled feature and its claims must remain within that subset.

| Gate | Question answered | Required evidence | Blocking failures |
|---|---|---|---|
| G1 Content and grading integrity | Are the delivered tasks true, fair and meaningfully different? | Independent oracle tests; reviewed contracts; full manifest census; known grading regressions; protected leakage audit | Contradictory facts, false correct/incorrect grading, duplicate semantic choices, unreviewed protected item, fabricated novelty |
| G2 Runtime and data integrity | Does an action preserve the right question, response and evidence? | Installed-app save/resume; crash injection; idempotent commits; supported archive migrations; same-device ownership | Lost acknowledged work, duplicate attempts/XP, substituted draft question, irrecoverable supported archive |
| G3 Experience and accessibility | Can users understand and operate the complete flow? | Device screenshots; manual VoiceOver and keyboard results; task observations; empty/error/large-text states | Unreachable primary action, unlabeled essential controls, stale selected destination, recurring unbounded UI hang |
| G4 Learning policy and variety | Does the learner receive appropriate actual demands and interpretable feedback? | Deterministic learner simulations; delivered-content inspection; inventory feasibility; evidence replay; pilot observations | Difficulty changes only metadata, helped answers inflate independent evidence, confidence changes ability, unannounced repetition |
| G5 Distribution and integrations | Does the signed app work with its supported environment? | Physical device installation; production-equivalent CloudKit checks; Shortcut/provider contract; notifications/widgets/import/export lifecycle | Enabled integration loses/corrupts data, publishes private content outside consent, or fails without a recovery path |

<a id="qa-req-003"></a>

**QA-REQ-003 — Test the shipped configuration.** Record commit, dirty-tree status, app/build version, catalog/scorer/policy versions, OS/device, locale, text size, appearance, cloud/account state and relevant flags in every release run. A test against a development content bank does not certify a different signed release bank. Produce a machine-readable manifest beside human notes. Never store personal source text, secrets or account tokens in that manifest.

<a id="qa-req-004"></a>

**QA-REQ-004 — Independent oracle rule.** The expected answer must not be obtained by calling the production scorer or copying its stored key. For bounded mathematics and program execution, derive an independent small oracle or enumerate the domain. For prose, causal reasoning, diagrams and transfer, reviewers must work the item without first seeing its answer and document disagreements. Production generation and evaluation may share typed contracts, but the validation authority must be capable of disagreeing with them.

<a id="qa-req-005"></a>

**QA-REQ-005 — Test the failure path as a product.** A test is incomplete when it checks only an error enum. Verify the visible explanation, retained work, available next action, keyboard/focus behavior and absence of false success. The intended failure response is part of the feature's acceptance criteria.

## 2. Required test layers and fixtures

<a id="qa-req-006"></a>

**QA-REQ-006 — Layer responsibilities.** Keep fast deterministic tests close to engine boundaries and reserve expensive UI tests for integrated behavior that cannot be established below the UI. Do not create hundreds of screenshot tests that repeat the same state transition with different numbers.

| Layer | Responsibility | Suitable existing starting points |
|---|---|---|
| Pure unit/property | Numeric/symbolic interpretation, option uniqueness, graph ordering, policy transitions, timing accounting | `GeneralExerciseEngineTests`, `MathContentContractTests`, `RetrievalRuntimeScoringTests`, `AdaptiveEngineTests` |
| Content release validation | Actual 1,000-per-lab admission, family/structure counts, artifacts, fingerprints, feasible quotas, protected givens | `ReleaseContentIntegrityTests`, `OfflineQuestionBankTests`, `BundledRetrievalCatalogTests`, `UserFacingContentLintTests` |
| Repository/component integration | Reservation + journal + attempt + projection + migration against real stores | `PersistenceRuntimeTests`, `RecoveryMigrationTests`, `FocusedQuizRotationIntegrationTests`, `DataExportRoundTripTests` |
| Policy replay/simulation | Full event sequences, independent/assisted exclusions, actual selected demands, repeat constraints | `AssessmentSchedulerTests`, `AdaptivePlanHistoryTests`, `ProgressEvidenceTests`, `AdaptiveQuestionPopulationPolicyTests` |
| Installed UI | Input, feedback, navigation, save/close/relaunch, restored history, keyboard and accessible state | Extend `NavigationSmokeUITests`; add focused journey suites with stable semantic identifiers |
| Manual device/research | VoiceOver speech, Pencil, visual clarity, physical performance, provider/cloud behavior, learning usefulness | Versioned run sheets and recorded observations with informed participant consent |

Names above locate current test areas; they are not a requirement to overload every existing file. New modules should have narrowly named suites. New state-machine tests assert public effects and durable records, not the view's private Boolean arrangement.

<a id="qa-req-007"></a>

**QA-REQ-007 — Golden fixture package.** Commit small synthetic fixtures for: a fresh learner; existing legacy learner with committed history; three suspended session phases; an interrupted timed item; a disputed legacy science item; an external self-check; a 10,000-attempt history; a source library with duplicates/deleted references; each supported prior archive version; and malformed/future payloads. Fixtures must contain no real personal source data. Include a manifest explaining which invariants each fixture exercises and a deterministic creation script when binary stores are unsuitable for review.

<a id="qa-req-008"></a>

**QA-REQ-008 — Reproduction identity.** A content failure record includes family/objective, concrete parameters, seed when relevant, content and scorer versions, semantic fingerprint, response, expected and observed result, and representation assets. A UI failure includes exact path, underlying session/phase and a redacted screenshot or accessibility transcript. A random fuzz failure must shrink to a retained minimal case before closure.

<a id="qa-req-009"></a>

**QA-REQ-009 — Bounded exhaustive versus sampled checks.** Exhaust all finite coordinate symmetry cases, enumerated response aliases, supported migration versions and state-machine transitions where practicable. For a large generator domain, sample boundary values, degenerate cases and fixed reproducible seeds in addition to a broader deterministic sweep. A sweep count is a coverage statement, not proof that every generated item is valid. The release manifest itself receives a complete census because those are the exact shipped items.

## 3. Content and grading regression cases

The following are minimum acceptance cases. Exact successor IDs may change after the generator is corrected; the underlying mathematical and behavioral counterexamples must remain testable. Trace primarily to CON-001–034 and SCO-001–019 in the [content chapter](02_Content_and_Scoring.md).

| Test | Given / action | Required outcome |
|---|---|---|
| T-C01 | Recreate audit spatial seed 11, point `(10,10)`, 90° counterclockwise | Correct answer is `(-10,10)`; rendered alternatives are semantically distinct. Construction fails safely if unique valid distractors cannot be produced. |
| T-C02 | Enumerate admitted boundary/symmetry coordinates and transformations, including axes and equal coordinates | Independent transform oracle agrees; no two options normalize to the same object/point. Visual and spoken descriptions agree. |
| T-C03 | Science seed `8424208090942894707`, A `[18,26]`, B `[27,35]` | Geometry states disjoint; no “overlap” prompt/key/caption. Statistical claims stay within the explicitly supplied interval/design contract. |
| T-C04 | Intervals with shared endpoint, nesting, equal bounds, reversed author input, and disjoint ranges | Closed/open endpoint policy is explicit; invalid author input rejected; no universal significance conclusion inferred from overlap. |
| T-C05 | Derivative of `x²`: submit `2x`, `2*x`, `x+x` under permitted grammar | All mathematically valid in-domain forms earn identical full credit. Original notation survives history. |
| T-C06 | Derivative of `2x²`: submit `4x`, `4*x`, `4x^1`, then `2x` | First three fully accepted; last rejected with useful correction. Parser limits and supported variable declarations honored. |
| T-C07 | Definite-integral task explicitly defines antiderivative `F` of `f`; submit `F(b)-F(a)` and `f(b)-f(a)` | First accepted; second is not accepted by case folding. Unicode/prose normalization does not erase symbol roles. |
| T-C08 | Mean prompt: correct paraphrases, “count divided by sum,” negated rule and incomplete fragments | Supported correct concepts accepted; reversed/negated rule rejected. Unjudgeable prose follows the declared self-check/clarification policy, never hidden substring scoring. |
| T-C09 | Estimate contract accepts canonical plausibility label and alias `yes` | Both receive identical component credit, total credit and correctness. All accepted-state combinations enumerated. |
| T-C10 | Exact quantity with rational, decimal, scientific notation and convertible units; requested metres with well-formed `1.25 cm` | Declared equivalents accepted; wrong known unit/quantity or required representation scored under the rubric. Empty/unparseable/unsupported notation and zero denominator receive clarification without an objective attempt. No unlimited free retries for semantic unit mistakes. |
| T-C11 | Multiple-choice task with correct, omitted and extra options, including select-all | Full credit only for the declared complete valid selection; explicit partial rule obeyed; extra false options cannot improve credit. |
| T-C12 | Partial-order task with two independent steps | Both valid topological orders accepted; every violated required dependency rejected with the relevant constraint identified. |
| T-C13 | Claim/evidence task with one valid and one unsupported edge | Output identifies the unsupported relationship; broad overlap of keywords cannot substitute for the support graph. |
| T-C14 | Logic-state task with typed fields and declared Boolean/value aliases | Equivalent states receive identical full credit; wrong independent field earns the authored component result. No alias penalty. |
| T-C15 | Open reference recall, then Matched/Partly/Not yet; migrate an old self-check stored as correct/1 | New UI/history show self-report; no deterministic “Correct,” 100%, or independent ability update. Revealed-but-unrated remains incomplete. Legacy original preserved with provenance-based selfReported disposition and exclusion from verified outcomes. |
| T-C16 | Blank, overlong, malformed Unicode, parser-limit input and uncovered prose in every relevant schema | Bounded completion, clear actionable result, no crash, no accidental submitted wrong answer for structural invalidity. Protected uncertainty never switches to answer-revealing self-check; apply preauthorized recovery without scored coverage. |
| T-C17 | Every protected manifest item rendered in text, diagram, alternative description, hint and history; recursively inspect checkpoint/journal/archive payload fixtures | Only essential givens visible; no decisive solution scaffold, per-item correctness or reusable exact key exposed through ordinary surfaces or nested exportable records. Internal evaluator inputs remain in the restricted repository; export uses protected-safe receipts. |
| T-C18 | Regenerate the actual admitted editions, not a simplified mirror | Counts, IDs, assets and fingerprints match signed manifests. Family/structure quotas and feasible assignment requirements pass. |
| T-C19 | Requested low/high demand for the same family and controlled seed, including audit seed `20260904` | Delivered objective-compatible demand changes as specified: steps, representation, uncertainty, constraints or scaffolding. Metadata-only differences fail. |
| T-C20 | A “figure,” “3D,” “paper” or “equation” activity | Its promised figure/object/abstract/target equation is actually present and necessary to answer; accessible equivalent asks the same substantive task. |
| T-C21 | Correct answer and every authored hint/explanation/repair | Truth stays consistent across phases; next hint is reachable; final explanation shows a useful operation; repair is a distinct linked item. |
| T-C22 | Retired/replaced bad item in a suspended session and in completed history | New use quarantined; historical original retained with correction/exclusion status; no silent new question inserted into the old draft. |

<a id="qa-req-010"></a>

**QA-REQ-010 — Editorial inspection.** Each of the 58 current activity families must have an approved objective, real demand progression, one fully worked representative at every supported band, common-error distractors, valid answer alternatives, accessibility text and explanation/repair. Every admitted protected form requires independent content and leakage review. For parameterized families, reviewers sign the generator domain and boundary rationale as well as representative items. Machine correctness checks still run over every admitted concrete item.

<a id="qa-req-011"></a>

**QA-REQ-011 — Variety report.** Emit inventory and delivered-session distributions by lab, family, structure, objective, target identity, band, field and response form. Report both numerical uniqueness and substantive structure coverage. Separate mixed, focused, review, protected and user-authored lanes. Do not average a repetitive mixed bank with a diverse catalog to hide the issue. Show unmet soft preferences with capacity/prerequisite reasons; fail hard integrity/no-replacement violations.

## 4. Runtime, navigation and recovery cases

Trace to RUN-001–022, DATA-001–025, MIG-001–010 and UX-004–005/016–025. Run the core cases against real local stores, then a representative set through the installed UI. Fault injection is a test harness capability disabled in distributed builds.

| Test | Given / action | Required outcome |
|---|---|---|
| T-R01 | Five-question focused practice; complete two, enter draft `17` on item three, Save & close, Continue | Same run, position 3/5, prompt/options/representation and draft `17`; no new launch reservation. |
| T-R02 | Repeat T-R01 across process termination and app relaunch | Last acknowledged checkpoint restored; interruption recorded; no false uninterrupted speed evidence. |
| T-R03 | Save at answering, feedback, protected acknowledgement, reference comparison, optional reflection and explicit reflection | Every stage has a safe exit and restores that exact phase without duplicate score, second reference reveal or required reflection trap. |
| T-R04 | Spend 20 active seconds, pause/relaunch, spend 5 active seconds, submit using controllable clock | Approximately 25 active seconds within explicit harness tolerance; background gap excluded; clean-speed eligibility false. |
| T-R05 | Use two hint stages with repeated rapid taps; close after second | Both authored stages reachable, no double disclosure from one command; count and exposure survive; assistance evidence retained. |
| T-R06 | Reveal solution without answer, then close/reopen | Revealed learning outcome, no fabricated wrong/correct response, independent status remains false. |
| T-R07 | Submit then double-tap, keyboard-submit and background concurrently | One attempt and one XP derivation; controls settle to the saved result. |
| T-R08 | Fail before commit-intent persistence | No success acknowledgement; draft retained; retry produces exactly one eventual attempt. |
| T-R09 | Crash after durable intent but before attempt write | Recovery retries the same attempt ID and payload; one result. |
| T-R10 | Crash after attempt write but before slot/journal acknowledgement | Recovery detects identical committed payload, advances bookkeeping once and displays original result. |
| T-R11 | Crash after acknowledgement before UI feedback | Relaunch displays saved feedback/acknowledgement; cannot re-answer the committed slot. |
| T-R12 | Same attempt ID with a different payload due to stale writer | Conflict surfaced and retained for diagnosis; neither payload silently overwrites another. |
| T-R13 | Disk/write failure during Save & close | No false Saved success. Before durable intent, retain editor and offer retry/recovery or explicit unsaved-draft discard. After durable intent, safe pending close preserves journal and truthful waiting state under RUN-022. |
| T-R14 | Two same-device windows submit or reserve concurrently; then Take over | One writer generation; disjoint accepted reservations; old window becomes read-only; stale commands rejected. |
| T-R15 | Start another session while current draft exists | First acknowledged as suspended before second writable run; Today/Practice provide exact continuation for both. |
| T-R16 | Content update changes prompt/key/assets while old run is suspended | Old snapshot/scorer used if valid and supported, or explicit recovery state if invalidated. Never blend old answer with new prompt. |
| T-R17 | Source deleted, asset missing, unsupported future checkpoint or malformed data | Specific unavailable state with preserved inspectable work; no crash or invented history. |
| T-R18 | Skip, End session, count completion and time-budget boundary | Distinct stop/outcome semantics; skip is not a zero-score answer; ended early is not completed; accepted fixedBlock reservations stay consumed, adaptiveItem consumes only each committed item decision, advisory prewarm consumes nothing. |
| T-R19 | Retry similar from feedback/history and repeat the command | Explicit separate repair run/slot with one creation per command; old score immutable; original plan target count unchanged. |
| T-R20 | Navigate each top-level root → depth 1/2/3 → every other destination | Selection and visible destination agree; returning restores that destination's own path; reselect active destination pops its root after dirty-work guard. |
| T-R21 | Reproduce Progress → skill → history → answer → Sources, and Document → Settings | No stale detail or persistent high CPU; original evidence and log attached. Repeat on supported stable macOS as well as the audited beta if available. |
| T-R22 | Open same deep link twice, invalid link, deleted object link, link while draft is active | One intended route, truthful unavailable state where needed, checkpoint before destination change; no duplicate run/attempt. |
| T-R23 | Edit answer after selecting confidence | Material semantic edit clears confidence; formatting-only equivalent retains it; required policy validates inline; optional omission never blocks. |
| T-R24 | Eight submitted response types viewed immediately, after relaunch, after content update and export/restore | Human-readable value/choices/order/relationships, exact original question context and honest available explanation; no serialized JSON in ordinary history. |
| T-R25 | Scratchpad has drawing + text; open on platform unable to edit that drawing | Original bytes preserved; view/export where supported; no empty overwrite; edited text saves independently. |

<a id="qa-req-012"></a>

**QA-REQ-012 — Navigation coverage algorithm.** Parameterize five destinations × representative path depths × switch/reselect/back/deep-link actions, with dirty and clean sessions. Assert visible root ownership and route IDs rather than only whether a sidebar label is selected. A route smoke test that clicks only roots cannot close QA-11.

<a id="qa-req-013"></a>

**QA-REQ-013 — Timing robustness.** Use injected monotonic time for deterministic tests of zero/negative/nonfinite intervals, wall-clock adjustment, daylight-saving changes, time-zone travel and background interruption. An unknown interval contributes no invented speed measurement. Include locked screen, incoming system interruption and app termination on physical devices; simulated lifecycle callbacks alone do not certify these cases.

## 5. Adaptation, review and evidence validation

The [adaptive chapter](03_Adaptive_Learning_and_Evidence.md) contains the normative numeric defaults and 60 simulation fixtures. Reuse those exact defaults from a versioned configuration. Do not independently hard-code a second staircase or review schedule into tests/UI. Assertions below inspect observable decisions and evidence eligibility.

| Test | Scenario | Required evidence |
|---|---|---|
| T-A01 | Cold learner with no baseline; novice, developing and advanced profile inputs | Conservative explicit start; profile input is a starting preference, not earned mastery; actual delivered demands recorded. |
| T-A02 | Repeated eligible success versus repeated eligible errors | Bounded band progression/support under ADP rules; selected tasks change substantively; no unsupported leap from a single result. |
| T-A03 | Same correctness sequence, high versus low confidence | Same ability/band evidence; different calibration interpretation only where enough evidence exists. |
| T-A04 | Same answers, helped versus independent, timed versus untimed, paused versus uninterrupted | Only eligible records enter each projection; timing choice does not silently change challenge; interrupted/helped records excluded from clean speed. |
| T-A05 | Easier/Harder/Keep this level, then resume and complete | Override scope/persistence matches contract; infeasible request explained; no mutation of already presented item or past answer. |
| T-A06 | Strong arithmetic, weak spatial, mixed topic/representation performance | No global promotion from unrelated success; objective/family evidence and prerequisites govern delivery. |
| T-A07 | Many easy successes, few difficult attempts, self-checks and deliberate repeats | History remains visible; projection does not claim broad advanced mastery; confidence/XP/self-report do not substitute for eligible challenge. |
| T-A08 | Replay identical append-only records in random arrival order, with duplicate transport records | Same final projection with deterministic ordering/deduplication; stable tie-breaks; no repeated XP. |
| T-A09 | Apply content invalidation/correction to old evidence | Original preserved; projection changes through disposition; correction message attributes data-quality change accurately. |
| T-A10 | Protected block budget ends midway; resume next sitting | Same form and unexposed items; no reroll; completion based on required coverage; exact reusable solutions remain protected. |
| T-A11 | Immediate repair success followed by delayed recall and unseen application | Separate purposes/exposure eligibility; immediate success alone does not establish delayed retention or transfer. |
| T-A12 | Overdue queue, snooze, deletion of source, already-active review task | Stable task identities; bounded queue; no duplicated review, pressure copy or impossible link. |
| T-A13 | Midnight/time-zone/profile/readiness changes while canonical plan exists | Plan identity and completion denominators follow SCH rules; extra practice remains explicit and separate. |
| T-A14 | Skewed finite inventory, narrow activity, cross-epoch request, learner improves near exhaustion | Finite feasible selection, hard no-repeat preserved, actual unavailable challenge disclosed, no fabricated advanced label. |
| T-A15 | Equal seed, policy, learner state and candidate manifest replayed | Same eligible item identities, declared demand vectors and reasons; incidental UI timing does not perturb selection. |

<a id="qa-req-014"></a>

**QA-REQ-014 — Human demand audit.** For each supported family, hide band labels and ask at least two independent subject reviewers to order representative items by expected demand and identify the added reasoning requirement. Disagreement triggers revision or a documented different-demand interpretation; changing a timer or arithmetic magnitude alone is insufficient for a general reasoning progression. This is editorial validation, not psychometric calibration.

<a id="qa-req-015"></a>

**QA-REQ-015 — Simulation is a policy check.** Synthetic learners validate internal rules and edge cases. They cannot establish that humans find B3 harder than B2, that the model accurately estimates ability, or that users retain knowledge. Reports shall label simulated outcomes and keep them separate from participant observations.

## 6. Device, accessibility and interaction matrix

<a id="qa-req-016"></a>

**QA-REQ-016 — Required configurations.** Run on the minimum supported OS and current supported stable release when different, plus the designated beta compatibility lane if supported. Confirm actual supported versions from the release's `project.yml` and distribution metadata at test time; the audit's Xcode/OS versions are historical evidence, not perpetual requirements.

| Configuration | Minimum exercised scope |
|---|---|
| Smallest supported iPhone + compact-width simulator | All eight response types; full keyboard-visible loop; Today/Practice/Progress/Sources/Settings; every exit phase; default and AX5 text |
| Large iPhone physical device | Touch accuracy, haptics, VoiceOver, notification deep link, interruption/relaunch and normal/large text |
| iPad physical or simulator, portrait/landscape | Split view at narrow and wide widths; scratchpad beside problem; hardware keyboard; source beside notes |
| Pencil-capable iPad physical device | Draw, undo/redo, save, resume, history/export persistence; only required if drawing feature is enabled |
| Mac supported stable OS | Minimum supported window, resizable split pane, hardware keyboard, VoiceOver, multiple windows, all navigation-depth transitions and performance |
| English and Japanese | Every primary screen and schema, validation, long labels, number/unit formats, correct answer interpretation and VoiceOver output |
| Light/dark, Reduce Motion, increased contrast settings | All semantic selected/error/correctness states; no color/motion-only information; useful static replacements |

<a id="qa-req-017"></a>

**QA-REQ-017 — Journey coverage.** Complete at least one genuine session in all seven labs and every enabled new interaction slice. Complete the full Today circuit, a protected assessment across multiple sittings, focused practice, mistake review, a source self-check and a saved question set. Exercise skip, hint, solution, report, pause, save/close, resume, early ending and natural completion where each policy permits them. “Not applicable” needs the mode rule, not a blank cell.

<a id="qa-req-018"></a>

**QA-REQ-018 — Manual accessibility protocol.** A qualified tester shall navigate without sight using VoiceOver on phone and Mac; use keyboard-only on Mac/iPad; use the supported switch/voice interaction paths for primary actions; and inspect maximum Dynamic Type. Record actual spoken names/values for equations, transformed objects, plots, order positions, selection and feedback. Automated accessibility-tree checks are supplemental. A chart alt description cannot disclose the answer in a protected task. Drag interactions require equivalent buttons/list actions with the same scoring and time-assistance policy.

<a id="qa-req-019"></a>

**QA-REQ-019 — Visual artifact review.** Capture tab roots, onboarding, every schema, validation, feedback, pause, history, import progress/error and question-set save states. For each, review default and maximum text, keyboard visible where relevant, and the smallest applicable width. Maintain one contact sheet per journey with the build/configuration caption. Screenshot changes need human semantic review: a pixel difference may be benign, while a perfectly matching broken layout is still wrong.

<a id="qa-req-020"></a>

**QA-REQ-020 — Contrast and target targets.** Adopt the native product targets in A11Y-002: touch regions at least 44×44pt, normal text contrast 4.5:1 and large text 3:1, visible focus/meaningful controls with appropriate contrast. Measure actual rendered colors/materials in both appearances. These are specified product QA targets, not a claim of legal or platform-wide compliance. The contrast values follow the [W3C contrast guidance](https://www.w3.org/WAI/WCAG22/Understanding/contrast-minimum.html); native sizing/interaction still needs device review.

## 7. Performance and large-data behavior

<a id="qa-req-021"></a>

**QA-REQ-021 — Proposed performance budgets.** The values below are initial acceptance targets, not current measured performance. Establish a recorded baseline on named reference hardware in Release configuration with a stable OS, no debugger, and controlled background workload. Use 30 measured runs after explicitly documenting warm-up/cache conditions for latency distributions. Report p50/p95 and worst observed run; do not discard outliers without a reason. If a budget proves inappropriate, revise it through the decision register before release rather than silently failing it.

| Operation | Initial target | Conditions and failure interpretation |
|---|---|---|
| Warm destination switch | p95 ≤200ms to useful content | Cached root/detail; no stale content; UI feedback begins within 100ms |
| Resume saved ordinary item | p95 ≤500ms | Local checkpoint/assets available, excludes process cold launch |
| Prepare next local item | p95 ≤500ms | Approved bank/ordinary asset; heavy first construction must be precomputed or show progress |
| Cold launch to usable Today | p95 ≤2s | Reference supported physical devices, ordinary store; migrations measured separately |
| Visible answer acknowledgement | p95 ≤500ms | Local valid deterministic item and healthy store; durable save precedes success; immediate command feedback ≤100ms |
| Open/filter history with 10,000 attempts | p95 ≤500ms first useful page | Paginated queries; no synchronous full-history decode on main actor |
| Search 1,000 indexed synthetic sources | p95 ≤500ms useful first results | Local index ready; query results paginated; no original-document decode per keystroke |
| Interactive scrolling/manipulation | Target frame cadence of reference display; investigate any main-thread stall >100ms | Capture an Instruments trace, identify work and fix reproducible stalls; do not invent a universal memory ceiling |
| Session endurance | No continuing retained growth after five repeated 20-item runs and cleanup | Record resident-memory trend, allocations and thermal state; investigate monotonic growth and leaked controllers/assets |

Content-bank construction, large import/OCR and schema migration are separate background operations. They need progress, cancellation where safe and explicit recovery; they must not hold the UI hostage to an unrealistically small latency target. Use a 50MB import boundary where that remains the documented supported limit, with different test cases for invalid input, many-page documents and image-heavy content. Never infer import success merely from a nonempty temporary file.

<a id="qa-req-022"></a>

**QA-REQ-022 — Hang closure.** QA-11 remains unresolved until the two observed routes are checked after the navigation repair on stable supported macOS, with repeated navigation and large history. A beta-only hang may be classified as platform-dependent with supporting traces, but the independently observed stale-stack issue still requires a passing repair test. Capture an Instruments trace and sample if a stall recurs; do not attribute it solely to SwiftUI from stack-frame names.

## 8. Migration, privacy and real integrations

<a id="qa-req-023"></a>

**QA-REQ-023 — Migration/restore run sheet.** For every supported archive/store version: import a known populated fixture into an empty install; verify counts and identities; view old responses; continue recoverable sessions; inspect unrecoverable states; export; restore again; compare authoritative records and privacy scope. Add interruption at each migration/journal stage, corrupt checksum, unsupported future schema, missing blob and repeated restore. A failed restore must leave the previous usable store intact. Test signed physical installs with sandbox file access, not only decoded model arrays.

<a id="qa-req-024"></a>

**QA-REQ-024 — Correction validation.** For every known defect class in DATA-024, apply the proposed disposition to fixtures with/without enough reconstruction data. Verify: original history preserved; affected evidence excluded or corrected only as justified; replay deterministic; user copy attributes the change to corrected content; XP policy follows its own explicit contract; old scorer output is not silently replaced. Identical response text alone is insufficient to infer which old question was seen.

<a id="qa-req-025"></a>

**QA-REQ-025 — Local data and diagnostics boundaries.** Test generated temporary content expiry at seven days, explicit Save set persistence, deletion, associated snapshot retention references, archive inclusion and iCloud partition. Local saved collections do not authorize uploading source excerpts, drawings or model prompts. Instrumentation proposed here stays local by default. Allowlisted aggregate research fields are event kind, build/policy version, relative duration bucket, lab/family/band and anonymous study participant code. Exclude raw answers, source names/text, question payloads, personal profile notes and device-wide identifiers unless a separately consented study specifically requires them. No new analytics SDK or network endpoint is implied by this specification.

<a id="qa-req-026"></a>

**QA-REQ-026 — Signed integration matrix.** The release owner records actual results for:

| Integration | Required cases |
|---|---|
| Question Writer/Shortcut/provider | Installed signed flow; success; no provider; unavailable Shortcut; cancellation; offline; malformed/oversized output; callback after relaunch; duplicate callback; correct source consent; reference quality/self-check labels |
| CloudKit/progress | Two signed devices; offline divergent records; convergence and deduplication; account change/sign-out; schema compatibility; deletion; existing document policy; local-only new payloads absent from cloud |
| Notifications | Denied/allowed/provisional where used; timezone change; overdue schedule; disabled reminders; meaningful deep link; no repeated stale notification |
| Widgets/App Group | Snapshot refresh; empty/completed/paused states; deep link; stale data handling; extension process lifecycle |
| Spotlight | Index/update/delete and deleted-object deep link; private/source policy respected |
| Import/OCR | Small text, PDF, scanned PDF, malformed file, access denied, size boundary, cancellation, duplicate import, source deletion during indexing |
| Export/delete | Fresh and upgraded archive; private-content inclusion choices; rollback; full deletion/purge lifecycle and failed deletion retry using disposable fixtures |

An unavailable external integration test is “not verified,” not “passed with mocks.” If the feature cannot be certified, disable the affected new capability or withhold the release claim; record that product decision explicitly. Existing working capabilities cannot simply disappear as collateral damage without a reviewed scope decision.

## 9. Human usability and learning validation

<a id="qa-req-027"></a>

**QA-REQ-027 — Formative usability rounds.** Initial proposal: two iterative rounds of six participants each, selected across novice, intermediate and experienced STEM learners, with accessibility users included through recruitment or a dedicated complementary accessibility session. This small sample is for finding usability failures and content misunderstandings; it is not a statistically representative efficacy study. Avoid assigning one person to stand in for an entire ability or disability group.

Provide realistic goals without naming UI controls: begin a suitable short practice; make/use a mistake explanation; ask for appropriate help; change challenge without changing timing; leave halfway and continue; find the original answer; practice a related mistake; import a synthetic source and save a study set; explain what progress and self-check mean. Observe unaided first. Record wrong turns, facilitator intervention, lost-work concern, disputed grading and comments in the participant's own words. End with comprehension questions: “What was saved?”, “What caused this level?”, “What does Matched tell the app?”, and “What will happen when you return?”

Proposed formative exit criteria: no unresolved critical lost-work/grading/navigation failure; at least five of six in the second round complete each core task without facilitator rescue; all can locate Continue after a interruption; no repeated misconception that XP/self-rating proves assessed mastery. Report numerator/denominator and task context rather than claiming population success from these small counts. Any repeated critical misunderstanding blocks the affected copy/flow even if a numerical target is met.

<a id="qa-req-028"></a>

**QA-REQ-028 — Question usefulness review.** Reviewers and participants assess objective relevance, clarity, reasoning demand, distractor plausibility, explanation usefulness and whether a new variant actually requires transfer. Record per-family issues; do not merge all scores into one attractive “quality” number. Ask whether a learner can explain why the answer works after feedback and solve a fresh related task without the same scaffold. Immediate practice improvement is reported as such.

<a id="qa-req-029"></a>

**QA-REQ-029 — Learning evaluation is a separate study.** Before efficacy claims, define a study protocol with representative recruitment, consent/data handling, pre-specified outcomes, a comparison condition appropriate to the claim, counterbalanced or randomized assignment where feasible, delayed retention and held-out application items. Determine sample size from the intended effect/uncertainty and design; this specification does not invent a universal number. Keep training items and evaluation forms separated by target/structure exposure policy. Report uncertainty, attrition, prior knowledge and accommodation differences. Do not claim general intelligence improvement from better performance on repeated in-app items.

<a id="qa-req-030"></a>

**QA-REQ-030 — Product metrics with honest denominators.** In opt-in research/local QA, measure first meaningful answer time; decision/tap count; abandonments by phase; exact resume success among attempted resumes; disputed grades among graded answers; hint→fresh independent success; family/structure concentration; response success by actual band; delayed recall; and held-out application. Exclude validation errors from answer accuracy; separate skips, revealed items, self-checks and ended-early sessions. Preserve context rather than optimizing a single completion-rate metric that rewards easier questions.

## 10. Implementation work packages

<a id="del-001"></a>

**DEL-001 — Deliver slices with dependent gates.** The sequence below is dependency-driven. It is not a calendar estimate. Implementation owners should size each package after inspecting affected modules and the actual content deficit. Engineering work and editorial authoring run in parallel where independent. A designer or QA reviewer is an accountable role, not a requirement to hire a separate person for each row.

| Package | Deliverable / owner disciplines | Depends on | Merge/release gate |
|---|---|---|---|
| WP-00 Contract foundation | Freeze legacy schema fixtures; authoritative record/ID/version contracts; reproduction tests; correction inventory — runtime + content + QA | None | Existing behavior reproducible; legacy preservation fixtures available; shared decisions accepted in code review |
| WP-01 Grading and truth | Unique spatial choices; interval truth; typed equivalence; accepted-state credit; protected scaffold separation — engine + subject review | WP-00 | T-C01–17; zero known critical grading/content defect in enabled edition |
| WP-02 Durable session spine | Stable run IDs, exact snapshots/checkpoints, journal/idempotency, ownership and timing — runtime + persistence | WP-00 | T-R01–19/23/25; migration fault cases; acknowledged work never lost |
| WP-03 Navigation and readable replay | Five independent paths, deep links, readable all-schema history, correction notices — UI + persistence | WP-02; history contract from WP-01 | T-R20–24, QA-11 stable-OS investigation, no JSON in normal history |
| WP-04 Continuous practice loop | Inline response/confidence/feedback, progressive hints, optional reflection, safe exit, repair link — design + UI + engine | WP-01/02 | All phase journeys on phone/Mac, protected/self-check distinctions intact |
| WP-05 Real demand and balanced inventory | 58-family matrix, authored bands/structures, feasible 1,000-item-per-lab editions, selector/reservation reconciliation — learning + content + engine | WP-01; reservation interface WP-02 | Full manifest census, editorial sign-off, no fake novelty, exact capacity/exhaustion tests |
| WP-06 Adaptive evidence and review | Versioned policy reducer, challenge overrides, protected continuation, correction replay, retention queue, canonical plan stability — learning + engine + persistence | WP-02/05 | Adaptive chapter fixtures + T-A01–15; actual delivered-demand inspection |
| WP-07 Discoverability and polish | Today/Practice/Progress/Sources/Settings composition, saved-set clarity, tokens, copy, EN/JA/a11y — design + UI + localization | WP-03/04; learner-state interfaces WP-06 | Device/keyboard/VoiceOver matrix; formative round; all missing/loading/error states |
| WP-08 Interactive depth | One complete approved interaction slice per lab with accessible alternative and linked evidence — domain/UI pairs | WP-04/05/06 | INT-001–008 acceptance; no visualization-only task substitutes for learning objective |
| WP-09 Lifecycle and distribution | Versioned archive migration, signed integrations, scale/performance, final usability rerun, release evidence — persistence + QA + release owner | Relevant enabled packages | G1–G5 complete for distribution scope; no unresolved blocking failures |
| WP-10 Outcome calibration | Representative human demand validation and separate retention/application study — learning/research | Stable WP-05/06/08 content and exposure rules | Claims limited to actual measured results; thresholds revised only through versioned policy |

<a id="del-002"></a>

**DEL-002 — First reviewable vertical slice.** Before rolling the architecture across all labs, deliver Mental Mathematics focused practice end to end: reviewed B1/B2 item, equivalent numeric answer, progressive hints, inline optional confidence, durable save on item three, exact resume, correction feedback, readable history and a distinct repair item. Include a protected numeric fixture and self-check fixture to prove authority differences through the same lifecycle. The slice is complete only when its migrated old-history case and crash-after-attempt case pass. This exposes shared design errors early without requiring a decorative redesign first.

<a id="del-003"></a>

**DEL-003 — Preserve source-of-truth build configuration.** Current project generation uses `project.yml`; keep it authoritative and regenerate the Xcode project through the established workflow when target/source settings change. Retain Swift 6 concurrency and current warnings-as-errors expectations. Do not make tests pass by weakening warnings, removing required suites, silently excluding damaged content without an edition decision, or bumping a fixture checksum without independently examining the changed content.

<a id="del-004"></a>

**DEL-004 — Capability gating.** New code can be integrated behind deterministic local build/configuration capabilities while dependent editorial or distribution gates remain incomplete. A flag controls a coherent feature, not half of a save transaction. Persist the runtime/content policy used by an active run so a flag change cannot reinterpret an in-progress response. No remote experiment infrastructure, analytics transmission or backend service is required. The distribution manifest records enabled capabilities and applicable gates.

<a id="del-005"></a>

**DEL-005 — Definition of done per package.** Required: final behavior matches linked requirements; relevant public-effect tests pass; changed screens inspected in their applicable compact/large-text states; migration/privacy effects documented; copy reviewed; no unrelated user edits overwritten; known limitations stated; diagnostics sufficient to reproduce remaining nonblocking issues. Update a feature's requirement status only with an evidence path/build, not “implemented” alone.

## 11. Triage, rollout and closure

<a id="del-006"></a>

**DEL-006 — Severity and release decisions.** Classify P0 as widespread data loss/corruption or disclosure; P1 as wrong grading, misleading independent evidence, loss of acknowledged draft, blocked core flow, repeated hang or essential accessibility failure; P2 as material friction/clarity/learning-quality deficit with a viable path; P3 as minor cosmetic or low-impact polish. An observed defect can move severity with documented scope, never merely because a deadline is near. P0/P1 block the affected enabled release capability. P2 closure or explicit scoped deferral is required before claiming that area polished.

<a id="del-007"></a>

**DEL-007 — Rollout order.** Use developer fixtures → internal installed builds → controlled volunteer usability/beta build → ordinary distribution after G1–G5. Each transition records content and schema versions, enabled capabilities, observed issues and recovery plan. Never test destructive restoration/deletion against the user's primary library. Use disposable test data and separate test accounts when external behavior is required.

<a id="del-008"></a>

**DEL-008 — Rollback means compatible recovery.** Before distribution, prove a recovery build can read the newly written store or restore the supported backup safely. “Install the old binary” is not a valid plan after an incompatible migration. Keep the last approved content edition available for safe new launches; retain pinned snapshots/scorers or explicit recovery for suspended runs. A content rollback cannot reuse an already exposed protected item as if unseen.

<a id="del-009"></a>

**DEL-009 — Release evidence bundle.** Store: configuration manifest; requirement/test traceability; automated summaries and failures; editorial manifest/reviewer records; device screenshots; accessibility notes; performance measurements; migration/restore results; signed integration run sheets; remaining issues; scope/claim statement. Redact personal material. Link raw result bundles where practical and give enough summary for a reviewer to assess coverage without opening gigabytes of logs.

<a id="del-010"></a>

**DEL-010 — Final closure questions.** The release reviewer must be able to answer, with evidence: Are known incorrect scores fixed? Can a learner save and continue the identical work? Does challenge change the task itself? Is every enabled activity honest about its operation? Can independent, assisted and self-reported results be distinguished? Is mixed practice actually varied within feasible inventory? Can all users reach the required controls? Are migrations and enabled external services verified? If any answer is unknown, state the exact uncovered capability; do not replace it with “all tests pass.”

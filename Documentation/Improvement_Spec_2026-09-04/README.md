# NeuroForge improvement specification

**Version 1.0 · 4 September 2026 · Proposed implementation baseline**

NeuroForge should become a dependable practice app in which a learner can understand the task, answer fairly, get useful help, continue saved work, and see why the next question suits them. The first priority is to repair grading, continuity and evidence integrity. The next is to make practice genuinely varied and adaptive, simplify the answer loop, and add interactions that teach something specific.

This specification turns the [4 September QA findings](../QA_2026-09-04/README.md) into implementation requirements, data contracts, screen behavior, content standards, concrete examples, failure handling and release tests. It covers the existing seven labs, all 58 current activity families, all eight response schemas, the daily plan, protected checks, source study, question creation, review/history, persistence, accessibility and supported integrations.

**This is a specification, not a claim that these improvements are already implemented.** No production app changes are included in this documentation package. The audit's executed tests establish the starting state; future acceptance cases below remain work to perform during implementation.

For one searchable document, open the [complete specification](Complete_Specification.md). Use the [requirement index](Requirement_Index.md) to jump directly to an implementation contract. The package contains 256 normative requirements; the [validation record](Specification_Validation.md) documents structural checks and coverage.

## 1. How to use this package

| Document | Intended readers / purpose | What it specifies |
|---|---|---|
| **This master specification** | Product, engineering, content and QA | Product outcomes, scope, shared decisions, priority, audit traceability and change control |
| [01 — Experience and interaction](01_Experience_and_Interaction.md) | Product design, SwiftUI, accessibility, localization | Every principal screen; continuous answering; hints/repair; source study; history; seven interactive slices; responsive tokens; copy and focus behavior |
| [02 — Content and scoring](02_Content_and_Scoring.md) | Content engineering, subject reviewers, learning design | Typed item contracts; all eight scoring domains; fairness/equivalence; protected scaffolds; finite inventory; worked examples; all 58 family progressions |
| [03 — Adaptive learning and evidence](03_Adaptive_Learning_and_Evidence.md) | Learning design, engine, persistence, research | B1–B4 demands; cold start; exact policy transitions; overrides; evidence eligibility; confidence; protected checks; review schedules; 60 simulation fixtures |
| [04 — Runtime, data and migration](04_Runtime_Data_and_Migration.md) | App/runtime, persistence, integrations | Run/slot identity; state machine; snapshots; timing; commit recovery; navigation; privacy partition; legacy evidence corrections; schema/archive migration |
| [05 — QA and delivery](05_QA_and_Delivery.md) | QA, release owner, all implementers | Known-defect regressions; failure injection; devices/accessibility; performance budgets; signed integrations; usability protocol; work packages; release gates |
| [Requirement index](Requirement_Index.md) | Implementers and reviewers | Searchable links to every normative requirement definition, grouped by owner chapter |

Read the master first. Then read the owning feature chapter and its dependencies before coding. A UI change that affects scoring, exposure or saving is incomplete until the corresponding content/evidence/runtime rules are included. The chapters are deliberately specific enough to become implementation tickets; the work-package boundaries in chapter 05 provide the initial grouping.

### Normative language and precedence

“Must,” “shall,” and requirement statements are the proposed acceptance contract. “Should” describes a preferred design that can be changed with a recorded reason. “May” is optional within the stated constraints. Numerical values called **proposed defaults** are concrete V1 implementation choices subject to validation; they are not merely placeholders and must not vary independently between modules.

Use this precedence when a conflict appears: this master decision register → the chapter that owns the contract → illustrative examples and tests. Content owns truth/score semantics; adaptive learning owns selection/evidence policy; runtime owns persistence/ownership/recovery; experience owns presentation within those constraints; QA owns how fulfillment is demonstrated. Resolve contradictions in the documents before using precedence to implement a surprising behavior. Do not silently weaken a requirement because its fixture is inconvenient.

This package replaces the earlier audit's suggested UX and learning defaults where it makes a more precise decision. The audit remains the record of observed evidence. Existing project privacy, content-integrity and release requirements remain in force unless a specific replacement is documented here. In particular, there is no implied permission to widen source transmission, erase history, weaken signed content admission, or call an unverified integration certified.

## 2. The product problems being solved

| User concern | Verified starting problem | Target behavior |
|---|---|---|
| “It feels clunky” | Separate confidence/reflection/feedback pages, disappearing problem context, long card stacks, weak continuation | One continuous learning surface; appropriate inline confidence; correction before optional reflection; exact Continue; one obvious next action |
| “It feels unprofessional” | Raw serialized answers in history, technical scorer copy, broken section switching, wrapped controls, unfair scores | Readable authentic history, stable navigation, consistent terms, accessible layouts and trustworthy feedback |
| “Do the features work?” | Concrete grading defects, lost focused-session continuation, inaccessible later hints; integrations incompletely certified | Known defects closed with behavioral tests; all enabled journeys and external boundaries receive explicit release evidence |
| “Are the questions clear and useful?” | Some misleading activity names, solution cues, thin explanations and rigid paraphrase matching | Specific learning objectives, honest task names, essential givens, reviewed scoring contracts and useful explanation/repair |
| “Does it adjust to the user?” | Requested difficulty sometimes changes only metadata; focused modes use defaults coupled to timing | Actual demand bands selected from independent evidence, explicit user overrides, timing controlled separately |
| “Is it challenging enough?” | Numerical variants and shallow tasks do not establish sustained advanced challenge | Reviewed multi-step, representation, assumption and boundary-case progressions, with explicit unsupported-band limits |
| “Is there enough variety?” | Transfer 98.6% one family; Logic 99%; Science 99.3% two families in audited default banks | Stratified admission, substantive structures, feasible runtime balance and honest exhaustion/review boundaries |
| “What interactions are missing?” | Existing tools are not connected into a mistake→understanding→fresh practice→retention loop | Progressive help, repair, review/bookmarks, step-through code, experimental choices, data prediction, meaningful reconstruction and spatial controls |

The app already contains useful foundations: deterministic exercises, multiple response schemas, some spatial views, scratchpads, source import, offline question sets, plan/history records and system integrations. Preserve those capabilities while making the underlying contracts dependable.

### Evidence baseline

The QA build was based on `f9b846015676e6b3bed7a4f7037e59475dda1b49`, version 1.0.0 (5). It passed **541 existing unit tests** and **four compact-iPhone smoke tests**. **Seven investigative probes reproduced suspected defects**, and 4,000 actual default bank contracts were regenerated and inspected. Live Mac testing found a stale destination stack and one sustained navigation/layout hang; the exact cause of the hang remains unproved on the audited beta OS. Source import and offline self-check worked in the sampled flow. These observations establish neither universal failure nor complete certification.

## 3. Product outcomes and scope requirements

<a id="prd-001"></a>

### PRD-001 — Trustworthy attempts

Every new authoritative score must refer to the exact displayed item, its reviewed evaluation contract and the learner's actual response. Declared equivalents earn identical credit. A malformed input, ambiguous interpretation, invalid item, self-rating, skipped item and objectively wrong answer are distinguishable outcomes. No UI convenience may collapse them into a misleading percentage.

<a id="prd-002"></a>

### PRD-002 — Dependable continuity

An acknowledged same-device save must preserve run identity, position, exact content, draft, assistance, phase and active-time provenance. Continue is visible and uses that identity. Every phase has a safe exit, including reflection and a pending write. Recovery explains any limitation and preserves authentic work instead of attaching an old answer to a new question.

<a id="prd-003"></a>

### PRD-003 — A complete learning loop

Ordinary practice supports attempt → accurate feedback → useful explanation/help → optional fresh repair → later review. The original problem remains available while learning from it. Immediate repair success is distinguishable from delayed retention and unfamiliar application. Repeated help does not inflate independent skill evidence.

<a id="prd-004"></a>

### PRD-004 — Meaningful personalization

Adaptation shall change the delivered task demands within a reviewed objective/family. Learner goals, starting preferences, prerequisite evidence, recent independent performance and available content guide selection. Confidence, time pressure, XP and self-report do not manufacture ability. Explain a consequential band change with the actual reason and allow explicit ordinary-practice control.

<a id="prd-005"></a>

### PRD-005 — Useful breadth

All enabled activities have accurate names, objectives, prerequisites, meaningful content and supported difficulty bands. Mixed practice balances substantive families and structures subject to hard validity/exposure/eligibility constraints. Numerical variants count as numerical variants. A missing band or exhausted pool has a truthful visible state; it is not filled with mislabeled substitutes.

<a id="prd-006"></a>

### PRD-006 — Clear interface hierarchy

After setup, the learner can identify the recommended next activity, start practice with at most two clear setup decisions, and resume saved work with one visible action. Today, Practice, Progress, Sources and Settings remain stable destinations. Learning text, response and primary action outrank decorative status cards, internal metadata and reward summaries.

<a id="prd-007"></a>

### PRD-007 — Inclusive operation

Every enabled learning operation works with applicable touch, keyboard and accessibility controls, including an equivalent alternative to drag/manipulation. Small layouts, software keyboards and large text cannot hide necessary controls. English and Japanese receive behavioral and editorial review. Accommodations are recorded honestly where they affect timing interpretation; they are not treated as proof of lower ability.

<a id="prd-008"></a>

### PRD-008 — Historical honesty and privacy

Preserve original attempts, content/scorer identities and authentic available context. Corrections are append-only dispositions. New source/AI snapshots and saved collections stay local under the specified scope. Protected keys do not leak through history, accessibility or nested exported records. A personal-study rating is never presented as independently verified standardized mastery.

<a id="prd-009"></a>

### PRD-009 — Release evidence matches claims

Enabled capabilities need their applicable content, runtime, experience, learning-policy and distribution gates. “All tests pass” is not a substitute for known-defect closure or signed integration checks. Editorial bands remain editorial until empirically validated. General intelligence, broad STEM transfer and clinical interpretations are outside the claims supported by this work.

<a id="prd-010"></a>

### PRD-010 — Scope stays coherent

Implement the dependent work packages as complete vertical slices. Preserve existing useful features and source policies. Prioritize correctness, continuity and the learning loop before additional reward systems or social features. This scope does not add a social feed, leaderboard, new currency, remote analytics service, unrestricted code execution, or live cross-device mid-question handoff. Those would need their own product and data contracts.

## 4. Shared decision register

These decisions are binding across the chapters. Their purpose is to prevent separate engineers from making individually reasonable but incompatible choices.

| Decision | V1 contract | Owning detail |
|---|---|---|
| D-01 Navigation | Five destinations: **Today** (rename Forge), **Practice**, **Progress**, **Sources**, **Settings**. Review/History inside Progress with Today shortcuts. | UX-001, RUN-017–021 |
| D-02 Route state | Each destination owns its path during the app run. Switch shows its path; reselect active destination returns to root after dirty-work handling. Ordinary cold launch starts Today + Continue. | UX-004–005, RUN-018–020 |
| D-03 Challenge labels | B1 Foundation, B2 Developing, B3 Challenging, B4 Advanced describe reviewed task demands within an objective/family. Never map old difficulty floats directly into them. | CON-011–013, ADP-002–007 |
| D-04 Timing | Untimed, elapsed-only and timed fluency are separate conditions. Changing timing cannot change current question, band, rubric or underlying quantities. | ADP-007, RUN-003 |
| D-05 Confidence | Required inline before submit for protected checks/explicit calibration, with no default. Optional in ordinary scored practice, expanded for one deterministic slot in each five presentation ordinals. Suppressed in timed fluency. Never changes correctness, XP or ability. | UX-017, EVD-005, RUN-009 |
| D-06 Reflection | Ordinary correction comes first; reflection is optional. No preselected learner diagnosis. Explicit metacognition tasks may ask first with a clear purpose and “Not sure yet”; every stage saves/exits safely. | UX-020, RUN-010/022 |
| D-07 Protected feedback | Per-item “Answer saved”; completed-block dimension/concept guidance. Reusable exact keys remain hidden. Practice this skill uses a fresh instructional variant. Disclosure requires a separately retired form and durable exposure transaction; it is not the default. | EVD-012, RUN-011, DATA-010 |
| D-08 Self-check authority | Matched / Partly / Not yet are self-report. No deterministic Correct/100% or independent built-in ability credit. Legacy records receive provenance-based dispositions, not silent overwrites. | SCO-014, EVD-010, DATA-024 |
| D-09 Reservation strategy | `fixedBlock` consumes accepted exact block reservations at launch. `adaptiveItem` consumes one exact first item at launch, then one item per accepted selection decision. Max two advisory prewarm candidates consume nothing. | CON-017/019, SCH-005, DATA-015 |
| D-10 Novelty and exposure | Consumed identity and displayed exposure are separate. Abandoned accepted reservations remain consumed. Skipped ineligible inventory stays available. No same-run semantic repeat across epochs; intentional review is a separately labeled lane. | CON-016–019, SCH-002–005 |
| D-11 Resume scope | Exact resume guaranteed on the saving device. Multiple suspended runs, one writable run per device; coordinated same-device window takeover. No new mid-question cross-device sync. | RUN-001–006 |
| D-12 Archive ownership | Restore preserves original identities/drafts. Writable continuation requires verified original local ownership and valid content. Different-device/unverifiable-owner unfinished runs are read-only recovery with separate fresh practice. | MIG-006–007 |
| D-13 Temporary versus saved | Temporary generated inventory allows new launches for seven days. Save set retains a local collection until deletion. An accepted unfinished run pins what it needs to finish; attempted-history snapshots survive inventory expiry. | UX-015, DATA-017–019 |
| D-14 Source and AI scope | New private source/AI study snapshots, drafts and saved collections are local-only. Existing explicit progress/source policies preserved; no new source-upload or analytics consent inferred. | EVD-010, DATA-017–018, QA-REQ-025 |
| D-15 Evidence | One versioned `EditorialBandEvidenceV1` reducer for live/history. Separate current target, demonstrated band, protected evidence, retention/application, confidence, speed, personal study and XP. | EVD-001–015 |
| D-16 Protected assessment dimensions | Seven performance dimensions plus separately derived confidence calibration. Knowledge of calibration is not calibrated behavior. Coverage determines completion; sitting time budget supports exact continuation. | ADP-013–014, SCH-001 |
| D-17 Canonical daily plan | Preserve plan/block identity and original completion contract. Adapt within a block; readiness/profile changes and repair do not silently expand or replace completed obligations. | SCH-010–013, RUN-015–016 |
| D-18 Corrections | Original records immutable. Verified corrections/exclusions are versioned, idempotent dispositions, with truthful history and no fabricated learner regression. Retain existing reward economy; no duplicate/negative XP from repairs. | EVD-008/014, DATA-013/023–025 |
| D-19 Grading boundary | Syntax/ambiguity clarification differs from a scoreable semantic mistake. Known wrong units or assertions follow the rubric; unsupported prose can become explicit self-check, never fake objective grading. | SCO-001–017, RUN-008, DATA-010 |
| D-20 Delivery floor and feasibility | Planned new offline edition retains at least 1,000 valid semantic contracts per lab with exact editorial quotas. Deficits block the claimed edition; do not fill them by relabeling repeats or weakening truth checks. | CON-014–019/029, QA-REQ-010–011 |

These choices are not all empirically validated design truths. They are a coherent starting contract based on observed failures and the app's existing architecture. Changeable thresholds and research-dependent claims are called out below.

## 5. Learner scenarios the product must support

| Learner situation | Desired path | Failure to prevent |
|---|---|---|
| New or returning novice | Try an approachable sample, choose a modest goal, start B1 or a clear recommendation, get a helpful worked step | Long unexplained baseline as the only route; failure interpreted as a fixed personal trait |
| Developing learner | Practice a target, understand an error, solve a fresh repair, return to a scheduled check | Repetition of one number template; explanations that merely restate the stored key |
| Experienced STEM learner | Select harder reviewed tasks with interacting constraints, unfamiliar representation or justified assumptions | Larger numbers or tighter timer passed off as advanced reasoning |
| Short or interrupted session | Enter an answer, leave during any phase, continue exactly later | New quiz after Save & close; missing hint/timing history; compulsory reflection trap |
| Learner studying personal material | Import a source, recall a meaningful target, inspect reference, self-rate honestly, save reusable local set | Generated reference treated as authoritative truth; silent expiry of unfinished work; accidental source transmission |
| Learner with accessibility needs | Read/hear equivalent givens, manipulate through accessible controls, use untimed mode, reach feedback and Continue | Answer-leaking alt text, drag-only task, clipped primary action, timed evidence compared across incompatible conditions |
| Learner disputing a grade | Report exact context, retain authentic response, inspect correction/disposition later, practice a valid replacement | Silent record rewrite, report counted as wrong, unresolved bad item served again locally |

These are usage contexts, not claims about demographics or fixed personas. Difficulty is grounded in observed task performance and prerequisites, not inferred from identity, degree, age or a marketing segment.

## 6. Audit-to-specification traceability

| Audit finding | Required design response | Minimum closure evidence |
|---|---|---|
| QA-01 Duplicate spatial answer | CON-006, SCO-006; unique semantic alternatives | T-C01–02 plus bounded-domain oracle |
| QA-02 Contradictory intervals | CON-002/007; separate geometry, estimand and inference | T-C03–04; independent science review; legacy disposition |
| QA-03 Valid answers rejected | SCO-005/009–013; typed equivalence and honest prose coverage | T-C05–06/08/10/16; adversarial accepted/rejected corpus |
| QA-04 f/F wrongly equated | SCO-003/010–011; case-sensitive symbolic roles | T-C07 and symbol-preserving variants |
| QA-05 Equivalent state partial credit | SCO-001/015–016; criterion equivalence | T-C09/14; all accepted aliases agree |
| QA-06 Metadata-only difficulty | CON-011–013; ADP-001–012; demand-bearing selection | T-C19; T-A01–07; human demand review |
| QA-07 Concentrated mixed banks | CON-014–019; SCH-002–005; exact family matrix | T-C18/20; T-A14; manifest/delivery distribution |
| QA-08 Focused resume broken | RUN-001–008, DATA-001–015; visible Continue | T-R01–03/15/16; exact UI relaunch journey |
| QA-09 Resumed timing/help lost | DATA-003–008, EVD-003/009 | T-R04–06; timing/interruption replay |
| QA-10 Protected solution cues | CON-004/008, RUN-011, EVD-012 | T-C17; visual/accessibility/nested-data inspection |
| QA-11 Stale navigation and hang | UX-004–005, RUN-017–022 | T-R20–22; stable-OS regression/performance trace |
| QA-12 JSON and poor history | UX-025, DATA-001/021–025 | T-R24; all eight schemas after update/restore |
| QA-13 Fragmented answer flow | UX-016–021, RUN-007–012/022 | Every phase journey; keyboard/VoiceOver; observed comprehension |
| QA-14 Later hints unreachable | UX-019, CON-025, RUN-013 | T-C21; T-R05–06; fresh repair linked without score rewrite |
| QA-15 Timing changes challenge | ADP-007–009; separate controls | T-A04–05; current item unchanged by timing toggle |
| QA-16 Durable evidence ignores demands | EVD-001–015; legacy boundaries and exact replay | T-A07–09/15; reducer equality and correction fixtures |
| QA-17 Compact control wrapping | A11Y-001–006, COPY-003 | Compact default/AX5 screenshots with keyboard and EN/JA labels |

The broad audit also left incomplete certification work: physical integrations, all-schema journeys, full accessibility, migrations/restore, performance at scale and human usefulness/learning evaluation. Chapter 05 makes that work explicit rather than assuming that repairing the 17 listed defects certifies everything else.

## 7. Priority, sequencing and scope of releases

| Priority | Contents | Why it comes here |
|---|---|---|
| P0/P1 trust foundation | Correct grading/content; protected boundaries; stable run identity, commit recovery and exact resume; navigation reliability | Later progress and interaction improvements cannot be trusted on defective attempts or lost state |
| Core learning release | Real bands, viable varied inventory, authoritative evidence, continuous answer loop, progressive help, readable history/review | Establishes the behavior that makes the app useful across repeated sessions |
| Experience completion | Today/Practice discovery, source-set clarity, typography/layout/copy, full accessibility/localization and all states | Makes that reliable behavior comprehensible and operable on supported devices |
| Interactive depth | Complete domain-specific interactions with meaningful scoring, assistance policy and accessible alternatives | Adds useful learning depth once truth, state and evidence can support it |
| Outcome validation | Representative demand pilots and separately designed retention/application research | Supports stronger claims only after the product and content are stable enough to study |

Chapter 05 defines WP-00 through WP-10 and five release gates. Some work can run in parallel: content authors can fill family/band deficits while runtime engineers repair saving; design can validate a continuous numeric practice slice while evidence replay is implemented. Dependence remains explicit. A polished screen alone does not complete a package if its history, exit or grading behavior is still wrong.

The first vertical slice is a complete Mental Mathematics focused session with a reviewed demand pair, fair numeric interpretation, staged help, inline feedback, save on question three, exact relaunch continuation, readable history and a separate repair item. Include protected and self-check fixtures through the same lifecycle. Use this to validate shared contracts before scaling across the catalog.

This specification does not promise a calendar date or person-week estimate. The main effort uncertainty is substantive authoring and independent review for every admitted family/band/structure, followed by migration and physical integration validation. Size those packages against actual capacity deficits and existing module boundaries; do not substitute generic “add 7,000 questions” tickets for the detailed family contracts.

## 8. Success measures and validation-dependent defaults

| Outcome | Measurement | Proposed completion criterion / limit |
|---|---|---|
| Fair grading | Known counterexamples, bounded truth oracles, adversarial equivalent/invalid response sets | Zero known critical grading/contradiction defect in enabled content; not a claim of universal mathematical coverage |
| Reliable continuation | Exact-state equality and observed Continue journeys | Every supported saved phase restores correctly on the saving device; no loss of acknowledged work |
| Less friction | Decisions/taps, wrong turns, abandonments, unaided task observation | No mandatory ordinary confidence/reflection page detour; core task criteria from QA-REQ-027 |
| Real challenge | Demand-vector differences, band transitions, reviewer ordering, participant task performance | Delivered question changes meaningfully; unsupported bands disclosed; quantitative policy remains a proposed V1 model |
| Genuine variety | Admission and delivered distributions, structure/target identities, capacity reports | Exact proposed edition quotas; runtime preference targets met where feasible without violating eligibility/no-repeat |
| Useful feedback | Explanation comprehension, fresh repair and delayed task outcomes | Learners can identify the relevant correction and attempt a fresh task; delayed learning reported separately |
| Accessible operation | Manual VoiceOver/keyboard, actual target/contrast/layout checks | No essential unreachable/unlabeled/clipped operation in supported scope |
| Honest progress | Event replay, provenance and participant explanation | Independent/assisted/personal study/XP remain distinguishable; unknown evidence does not become false certainty |

Specific band staircase thresholds, evidence windows, interval ladders, confidence proxies, timing gates, visual token values and performance budgets are defined in their chapters. They are **versioned proposed defaults**, not empirical universal constants. Product/learning owners may revise them after measured evidence, with a documented reason and compatibility/replay plan. Until then, implement them consistently so they can actually be evaluated.

A human pilot is required to judge whether questions feel appropriately challenging and useful. A separate properly designed study is required for claims of durable learning or unfamiliar application. No proposed scoring rule or simulator makes those research outcomes automatic.

## 9. Risks, dependencies and resolved boundaries

| Risk/dependency | Required response |
|---|---|
| Insufficient authored content for balanced bands/forms | Admission emits exact deficits; continue a valid accurately described scope or hold the new edition. Do not invent suitable equations/figures or weaken the published floor. |
| Unsupported symbolic/prose equivalence | Bounded grammar and explicit rubric; clarification/self-check where authority is insufficient; preserved original response. No hidden model judgment in protected scoring. |
| Old records lack snapshots or true difficulty | Preserve authentic history, mark unknown/legacy provenance, offer recovery; no fabricated reconstruction or retroactive B4. |
| Store partition and cross-store writes | Durable local journal plus idempotent domain attempt identity; explicit local/cloud record inventory; actual migration fixtures. |
| Protected content is bundled offline | Prevent accidental UI/export leakage and track exposure; do not advertise cryptographic exam security against local binary inspection. |
| Navigation hang was observed on beta macOS | Repair known stale-path behavior, investigate stable supported OS with traces, record remaining platform-specific evidence honestly. |
| New local retention interacts with expiry | Expire temporary new-launch inventory; pin accepted unfinished runs/history; explicit saved-set deletion preview. |
| Signed systems cannot be verified by mocks | Use physical devices/accounts and run sheets before certifying enabled distribution capabilities. |
| New study data or telemetry would expand privacy scope | Local QA/research defaults only; separate explicit consent and protocol for transmission; no analytics service implied. |

These are implementation constraints with defined handling, not permission questions awaiting the user. The remaining empirical work is scheduled in the delivery gates; it does not prevent implementing the specified first slice.

## 10. Requirement tracking and change control

Requirement prefixes are PRD (product), UX/INT/A11Y/COPY (experience), CON/SCO (content/scoring), ADP/EVD/SCH (adaptation/evidence/scheduling), CORE/RUN/DATA/MIG (runtime/persistence), and QA-REQ/DEL (validation/delivery). Audit QA-01–17, content QA-F/QA-S/QA-B identifiers, simulation fixtures and T-C/T-R/T-A cases are evidence/test references, not duplicate product requirements.

Use the following implementation status values per requirement: **specified**, **in progress**, **implemented**, **verified**, or **deferred with scope decision**. This package initially marks behavior as specified. A status of verified requires a build/catalog/policy and an evidence link. Shared requirements can have multiple implementation packages but one authoritative definition.

Every substantive change records decision ID or requirement IDs, old/new behavior, reason, affected data/content/policy versions, required migration/replay, tests and user-visible copy. A threshold change is not merely a constant edit when it alters demonstrated bands or review dates. A corrected answer is not merely a fixture update when it affects saved evidence. A renderer change is not merely visual when it exposes a solution.

Before implementation review, confirm that the feature ticket includes its screen/phase states, inputs/outputs, content authority, persistence/ownership behavior, accessibility, failure/recovery path, metrics boundaries and acceptance cases. The relevant chapters already provide those contracts; tickets should link them rather than create inconsistent abbreviated rules.

## 11. Supporting evidence and technical foundations

The primary evidence is repository-local: [QA report](../QA_2026-09-04/README.md), [content audit](../QA_2026-09-04/ContentAudit.md), [adaptive audit](../QA_2026-09-04/AdaptiveAudit.md), [UX audit](../QA_2026-09-04/UXAudit.md), and [executed probes](../QA_2026-09-04/ExecutedProbeResults.txt). Exact code references and current behavioral limitations are preserved there.

Platform guidance informs implementation details: state-driven routing and restoration in [Apple NavigationPath](https://developer.apple.com/documentation/swiftui/navigationpath), versioned migration through [Apple SchemaMigrationPlan](https://developer.apple.com/documentation/SwiftData/SchemaMigrationPlan), and contextual proportional [Apple feedback guidance](https://developer.apple.com/design/human-interface-guidelines/feedback). These sources support platform techniques; they do not validate NeuroForge's content, numerical learning policies or future release quality.

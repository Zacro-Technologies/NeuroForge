# NeuroForge — Complete improvement specification

**4 September 2026 · Version 1.0 · Proposed implementation baseline**

This generated reading copy combines the master and five chapters. Edit the source chapters, then run `validate_spec.py` to rebuild it. It specifies future behavior; it does not certify that the app implements it.

[Reading guide](README.md) · [Requirement index](Requirement_Index.md)

---

<!-- Source: README.md -->

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

---

<!-- Source: 01_Experience_and_Interaction.md -->

# NeuroForge improvement specification: experience, interaction and accessibility

Date: 2026-09-04. Status: proposed implementation requirements, not a description of completed work. Owner: experience implementation, coordinated with the core learning, content, navigation, persistence and release specifications in this directory.

This appendix defines how the application should behave for a learner. Requirement identifiers are stable: `UX-###` covers journeys and screens, `INT-###` covers learning interactions, `A11Y-###` covers accessible operation, and `COPY-###` covers language. A requirement is complete only when its behavior, state handling and acceptance criteria work in the running application. A passing source-contract test is supporting evidence, not a substitute for a usable screen.

The intended product is a practical STEM learning companion. The main experience should answer three questions quickly: what should I practice, why is it useful, and what did I learn? The application must preserve the existing strengths—offline practice, durable progress, protected skill checks, local sources, 3D representations and scratchpad—while removing unnecessary administrative work around them.

## 1. Decisions and boundaries

<a id="ux-001"></a>

### UX-001 — Five stable destinations

Keep exactly five primary destinations, in this order: **Today, Practice, Progress, Sources, Settings**. Rename the current Forge destination to Today. The NeuroForge brand and earned milestones can remain, but users should not have to learn a brand metaphor to identify their daily task.

Review and History are explicit sections within Progress, not a sixth destination. Today includes a shortcut to due reviews. Question creation belongs to Practice and is also available contextually from a source. A generated question set is a learning resource, not a separate primary navigation mode.

| Destination | User's reason for visiting | First visible action | Supporting routes |
|---|---|---|---|
| Today | Know what to do now and continue interrupted work | Continue session, or Start today's practice | Due review, adjust plan, completed daily review |
| Practice | Choose a particular skill, activity or topic | Search or recommended practice | Recent activities, exact catalog, custom question sets |
| Progress | Understand results and revisit learning | Overview with Review and History visible | Skill detail, filtered history, answer detail, annotations |
| Sources | Study material the learner supplied | Import source or open a recent source | Source detail, reading, review, question creation, collections |
| Settings | Change a preference or manage data | Search settings | Practice, accessibility, notifications, Question Writer, data and sync, about |

Acceptance: labels, commands, deep links, empty states and onboarding all name these same five destinations. No user-facing control says “Open Library” when the destination is named Sources. No standalone AI Studio or Review tab is added.

<a id="ux-002"></a>

### UX-002 — Primary-action hierarchy

Each screen has one visually dominant next action for its current state. Supporting actions use secondary or plain treatments. A screen may show several useful actions, but two unrelated actions must not have equal prominent styling in the same immediate group.

The order of importance is: resume meaningful unfinished work; perform the selected learning task; understand feedback; choose an alternative; inspect metadata. Rewards and technical information come after learning content. Use **Practice XP** for the participation reward and **Participation** for the related activity summary; neither is a skill grade. Do not reintroduce Forge as the label of a primary progress metric after renaming the destination Today. Do not display content template, scorer or validator versions in the main visual hierarchy of an answer review.

Acceptance: when a reviewer sees a grayscale screenshot without reading every paragraph, the current task and primary action remain apparent. The first viewport is not filled by several competing hero cards.

<a id="ux-003"></a>

### UX-003 — Learning and evidence policies belong to the core model

The UI must consume an explicit session policy rather than infer evidence status from a color, title or destination. At minimum it needs to know whether the task is ordinary practice, a protected skill check, calibration, delayed review or personal-source practice; whether hints are allowed; whether confidence is required before commit; whether feedback is immediate or delayed; and which edits are allowed before and after commit.

The shared confidence policy is normative: protected baseline/reassessment and explicit calibration require inline confidence before submit, with no default. Ordinary scored practice offers optional inline confidence, with one deterministic invitation expanded in each group of five presentation ordinals under EVD-005; skipping the invitation never blocks submission. Timed Rapid Recall/fluency suppresses confidence collection entirely so it does not contaminate timing. Missing confidence is absent evidence, never a carried-forward or fabricated level. Ordinary correction is immediate, with optional reflection afterward and no preselected error diagnosis. See the core learning specification for authoritative sampling, evidence and adaptation rules.

Challenge bands are B1 Foundation, B2 Developing, B3 Challenging and B4 Advanced. These labels describe editorial challenge, not a measured grade, age, intelligence level or validated population percentile. Do not show an Expert label that overstates the content's depth.

## 2. Navigation that cannot leave stale content on screen

<a id="ux-004"></a>

### UX-004 — Destination and visible content must agree

The selected sidebar row or tab must always correspond to the visible root and any child screens belonging to it. A Sources document must never remain visible while Settings is selected. A Back button must only navigate within the selected destination's path. Changing destination is not a back action.

This is a verified current failure to repair: on Mac, after Sources → document detail → source review → close review, selecting Settings highlighted Settings while the document detail remained visible; Back then revealed Settings. A separate deep Progress → answer-review route became unresponsive during a sidebar switch. The latter's root cause remains unproven; its sample was dominated by AppKit/SwiftUI layout and rendering. Do not assume a navigation refactor alone fixes the responsiveness incident without reproducing it.

The root navigation specification owns route data and implementation. Required visible behavior is:

1. Selecting a different destination immediately presents that destination's own root or deliberately retained path, consistently across platforms.
2. Retain each destination's typed browsing path within the current app run. Switching presents the selected destination's own retained path. If a validated deep link requests the root or a target child, it overrides that path predictably.
3. Selecting the currently selected tab or sidebar destination again pops that destination to its root, after dirty-editor/session guards. Do not reset it merely because a body re-renders.
4. A root replacement must finish before an unrelated child sheet or full-screen session is presented.
5. Closing a source review returns to its source context. Closing a generated practice set returns to that set, not the top of Practice unless that was its origin.
6. A completed session returns to its launch context with a visible saved result. A daily multi-section session can offer Continue next section before returning.
7. Cold launch starts at Today root with a visible Continue entry for suspended work, unless a validated deep link defines another route.
8. Multiple suspended sessions are allowed. Only one writable active run exists per device; other windows open it read-only or offer Take over on this device after checkpointing the current writer.
9. Exact same-device resume is required. Mid-question cross-device resume is outside this release until a coordinated handoff exists; CloudKit availability must not be presented as evidence that such resume works.
10. An archive restore does not transfer live ownership. The preview separates resumable runs from read-only recovered work. Writable continuation requires verified original local ownership and valid content. On a different device or with unverifiable ownership, preserve the original question, response, notes and provenance for readable recovery; offer **Start new practice**, not Continue. Do not rebind a protected form into a second writable copy.

Acceptance: repeat the two verified failure routes, then switch between every destination from root, first-level detail and deepest supported detail. Test pointer, keyboard commands and accessibility activation. No stale child, stranded sheet, mismatched highlight, navigation warning or sustained CPU/render loop is acceptable. Repeat with an active filter, Japanese text, reduced motion and a narrow window.

<a id="ux-005"></a>

### UX-005 — Unsaved work and reversible navigation

Autosave reversible drafts locally where existing persistence contracts permit. Distinguish saved draft, pending write and failed write. Ordinary navigation from a successfully saved draft should not require a discard dialog.

Follow the safe-exit transaction rules in RUN-022. If a draft has no prepared durable commit, offer Retry saving, Keep editing, Copy/Export recovery and explicit Discard unsaved changes. Discard returns to the last acknowledged checkpoint and explains exactly which unacknowledged input would be lost. It never deletes an existing attempt or prepared commit intent. Never label destructive discard as Done.

Every stage accepts an exit request. Cancel disposable next-item generation while keeping the prior acknowledged state; accepted reservations remain consumed. During answer or self-check commit, queue the close and reconcile the write. If the recovery intent is already durable but the destination store remains unavailable, allow close with **Answer waiting to finish saving** and restore that exact pending intent later. Do not show the ordinary Saved state, erase the journal, or let the learner edit a prepared commit into a different response using the same attempt identity. This policy applies to navigation and window closure as well as Save and close. Failed save must not silently convert a complete session into an empty draft.

Protected assessment and any explicitly required reflection do not justify trapping the learner. Save the exact pending state, leave safely and resume at the same stage. The current reflection checkpoint already records a pending attempt, trigger, reason and note; expose that capability instead of removing Save and close.

Acceptance: force a save failure at answer, confidence, reflection, source note and question-set configuration stages; retry succeeds without duplicate attempts. A normal leave/resume does not reveal a protected key or reset confidence order. The learner can stop without force-quitting.

## 3. First use and calibration

<a id="ux-006"></a>

### UX-006 — Sample-first onboarding

The first screen should offer a concrete example of the product within one primary action: **Try a sample**. Secondary actions are **Set up my practice** and a clearly placed **Restore a backup**. The sample is optional and low stakes. Do not require account setup, a full questionnaire, a source import, notification permission or external model setup before a learner can try the product.

The first sample should take roughly 30–60 seconds for a typical learner, but its interface is untimed. Use one approachable authored item with meaningful feedback. For example, choose a useful mental-math strategy or identify what a simple data comparison can support. It must show the pattern of prompt, response, helpful explanation and next step. It must not present a trivial interaction as an intelligence assessment.

Sample results do not become protected skill evidence. If retained as activity, identify them as sample practice and keep that rule explicit. At sample completion, show **Make this fit me** and **Try another skill**. Back returns safely; leaving the app preserves setup progress.

Acceptance: a fresh installation reaches a scorable sample without entering personal information. Sample completion demonstrates feedback, not just a welcome animation. A keyboard or VoiceOver user can finish the sample independently.

<a id="ux-007"></a>

### UX-007 — Short, purposeful setup

After the sample, collect only decisions that immediately change experience: preferred STEM contexts; optional emphasis; preferred daily duration; timing comfort. Explain each choice in one sentence. Default broad STEM coverage, five minutes and an untimed or accuracy-first start for a new learner, subject to the core plan policy. Do not infer advanced ability from career stage alone.

Display context and emphasis as choices with clear selected state. Explain that choosing Computing changes examples and emphasis, while broad skill coverage can remain. Allow later changes in Settings. Avoid a forced “choose all abilities” form that gives the impression of personalization without changing anything.

The final setup screen says what will happen: “Start with a short session. Your next practice will adjust as you answer.” Offer **Start practice** as primary and **Take a short skill check** as secondary. Notification permission appears only after the learner chooses to add a reminder.

Acceptance: setup fits three short stages at most, excluding the sample. Back preserves every choice. The selected duration, language and timing preference are reflected in the first session. No accessibility option is required to disclose disability or diagnosis.

<a id="ux-008"></a>

### UX-008 — Optional short calibration with honest scope

Offer a short starting check from onboarding and Today. Show estimated range, skill coverage, untimed status and **You can stop and continue later** before starting. Let the learner choose a relevant block; do not require completing the full battery before useful practice appears.

Use a preview item when the response mechanic is unfamiliar. Explain whether it is a preview or a scored check. The check may adapt its length; therefore show “Question 3” plus a bounded progress explanation rather than a precise total that changes unexpectedly. The core engine determines item selection, stopping and whether evidence is sufficient.

At completion, describe an actionable starting point: “Start with proportional reasoning. We'll begin with familiar numbers and add more complex comparisons.” If evidence is insufficient, say what was saved and offer Continue later. Avoid labeling a learner weak or unassessed as the dominant motivational message.

Acceptance: stopping and resuming retains exact protected ordering and evidence; a preview does not inflate the estimate; an excluded visual modality receives an honest alternative or omission; the UI does not promise a validated score after too little evidence.

## 4. Today

<a id="ux-009"></a>

### UX-009 — Today screen composition and defaults

Order Today as follows:

1. Compact date/greeting and optional profile context.
2. One current-task surface: interrupted session if present, otherwise today's next section.
3. Due reviews, when applicable, with a clear count and estimated duration.
4. A compact preview of remaining daily sections.
5. One optional recommendation, such as a starting check or a different skill.
6. Small completion/consistency summary with milestones behind a disclosure or dedicated detail.

The current-task surface shows title, skill, estimated time, number or range of questions where meaningful, and one ordinary-language reason. For example: “Practice ratios · about 5 min. Your last two sets suggest another round will help.” Do not require reading a priority formula.

Primary CTA is **Continue session**, **Start today's practice**, or **Review today's results**, depending on state. Secondary actions are **Adjust** and **Choose another activity**. After completing today, congratulate briefly, show what was practiced, and offer due review or optional practice without replacing the completed plan with a fresh zero-percent plan.

<a id="ux-010"></a>

### UX-010 — Readiness and adjustment

Keep readiness optional and lightweight. A control such as “How much energy do you have?” may offer Low, Usual, High with short explanations. Show the concrete effect before applying a change: “Shorter session, untimed, with familiar topics.” Do not suggest readiness measures cognition or mental health.

Adjust opens a focused sheet containing duration, timing and remaining sections. Already completed work is visibly fixed. Section replacement offers a small reason list—Too easy, Too hard, Already familiar, Want variety, Accessibility issue—and previews the replacement's title and time. The core engine decides valid replacements and evidence consequences.

Acceptance: adjust never discards completed sections, silently re-awards daily rewards or strands a checkpoint. A replacement acknowledgement is concise and actionable. Undo appears only when the core model verifies it is safe; otherwise explain why without exposing internal dependency language.

<a id="ux-011"></a>

### UX-011 — Today states

| State | Required presentation | Action |
|---|---|---|
| First day, no check | Approachable short practice and optional starting check | Start practice |
| Incomplete session | Exact activity and progress; saved-draft indicator | Continue session |
| Daily plan complete | Completion remains stable; what was learned | Review results |
| Reviews due | Count and estimate without guilt | Review now |
| Nothing due | “You're up to date” with next review date if reliable | Optional practice |
| Plan preparing | Stable layout and text “Preparing today's practice…” | Existing safe practice remains reachable where valid |
| No valid content | Explain the specific missing content and safe recovery | Retry or choose supported activity |
| Persistence failure | Current work remains visible; no success badge | Retry saving |

A loading state must not show fake progress. A transient failure should not fill the whole app with a technical error when another safe activity remains available.

## 5. Practice and custom question sets

<a id="ux-012"></a>

### UX-012 — Exact activity discovery

Practice opens with search, one recommendation, recent/resumable activities, and a compact skill browser. Search returns matching **activities** as well as parent skills. A result should show the activity name, skill, expected interaction, approximate time and level. Selecting “Estimate then calculate” must open that activity, not force the learner to find it again in Mental Math.

Use filters only where they help: Skill, Context, Duration, Level. Search and filters are visible together; active chips show constraints; Clear all is available. Preserve them when returning from an activity. No-results copy names the active constraints and offers a reset. Do not search only internal keywords while ignoring translated display text.

Favorite and recently used activities provide fast return. Favorites are optional, local resources with clear remove behavior. A user can start mixed practice without selecting a subskill. Browsing the entire catalog should not push the Start action several screens below the selected activity.

Acceptance: exact activity is reachable from a matching query in one selection; all supported catalog entries are discoverable; search handles English/Japanese titles and useful synonyms; 100 catalog entries remain responsive.

<a id="ux-013"></a>

### UX-013 — Activity detail and setup

Show the activity's name, one sentence about its use, one example or miniature preview, estimated duration, and current recommended challenge. Display setup in a compact area with a persistent primary **Start practice** action.

Difficulty and timing are separate controls. Difficulty defaults to **Matched to you** when the core model has a defensible estimate, otherwise **Starting level**. The learner can choose Easier or Harder; explain the effective content band using a concrete example. Timing choices are Untimed, Elapsed time only and a core-supported Timed fluency mode. Elapsed time only is an orientation aid and does not introduce a response deadline or speed-evidence claim. Changing timing must not change difficulty unless explicitly explained and confirmed as a different activity.

Question count may be selected separately from duration only if both have meaningful behavior. Avoid simultaneous precise “5 minutes” and “10 questions” promises when neither constrains the other. Use “About 5 minutes · 6 questions” where it is an estimate. Locked speed or transfer modes show the relevant readiness requirement and a practice route to it.

Acceptance: novice and established profiles receive intentionally different defaults where content supports it; timing-only change leaves requested difficulty unchanged; a manual override remains visible. Starting a catalog activity never silently replaces a daily checkpoint.

<a id="ux-014"></a>

### UX-014 — Question creation as a guided task

Use the screen title **Create a question set**. Primary input is “What do you want to practice?” with optional source selection. Offer a few useful starter sets that explain what they teach. Suggest skill, form and level; keep detailed form count/objective configuration under **More options**.

Source selection opens a searchable chooser showing filename, preparation status and allowed question route. A disabled source must explain why and expose the relevant recovery. Do not list an unbounded document library inline above Create. Selecting multiple sources summarizes the selection and permits review.

Show the current route in ordinary terms: “Created on this device” or “Uses Question Writer.” Before an external run, present exactly the excerpts and destination choice required by the core privacy flow. Preserve existing explicit source-sharing authorization; simplifying the UI must not weaken it. External setup can use a short guided checklist, but never pretend a Shortcut is native in-app generation.

States: ready, preparing, awaiting external app, cancelling, saved, failed with retry, failed with supported offline fallback. On completion, move focus to the result and show **Start set**, **Review questions**, and the retention choice. A failed run retains the configuration. Closing an external app returns to a recoverable in-app state.

<a id="ux-015"></a>

### UX-015 — Saved versus temporary sets and collections

Make content retention explicit before the learner relies on a set. A temporary generated set says “Temporary · new practice available for 7 days.” Seven days is the default new-launch eligibility of its inventory, not a promise to delete every saved answer or stop unfinished work at that boundary. A deliberately saved set says “Saved on this device.” New private study snapshots and saved collections are local-only in this release; this work does not extend iCloud excerpt scope. Do not call a seven-day cache a permanent library.

Provide **Save set** to opt into durable local retention until the learner deletes the set. Saving captures the question/feedback/context version needed to study later. Do not claim synced availability for these saved sets or collections. Retaining personal material must be user-controlled and reversible.

Collections are optional organization: title, description, included sources and saved sets, last practiced, next review. Defaults are Recent and Saved; creating a collection is not required to start. Actions are Rename, Add/remove item, Practice, Export where supported, and Delete. Removing from a collection is not deleting the underlying source or attempt history; the menu must distinguish them.

An accepted unfinished run pins the exact set members and assets needed to finish its original contract. After the temporary inventory expires, that run still offers **Continue session**, while **Start new practice** from the expired unsaved set is unavailable. Attempted-history snapshots survive expiry and remain readable. The pin does not make the set a permanent reusable collection: after the run is ended or completed, release unneeded unattempted inventory according to DATA-019. Explicit **Save set** creates the durable local collection. Explicit deletion presents its impact on unfinished work, attempts and source links before changing those references.

Acceptance: advance the clock through day seven with an untouched temporary set, a partially completed set and an explicitly saved set. New launch from the expired unsaved inventory is unavailable; the accepted unfinished run resumes exactly; existing answer history remains readable; the saved collection remains reusable. Ending a pinned run releases only unneeded inventory. No retained run or collection bypasses quarantine of a reported defective question.

## 6. The continuous session surface

<a id="ux-016"></a>

### UX-016 — Keep the problem present through the answer loop

Use one continuous problem surface with a stable header, stimulus, response area and action footer. Submitting must not replace the entire screen with confidence or feedback for ordinary practice. Preserve the prompt and the learner's response as feedback appears. A collapsed prompt may be available after a long explanation, but the learner can expand it without losing scroll position.

Header: Back/Save and close action, activity name, current position, optional timer. Utility actions: scratchpad, report, and pause; secondary utilities can live in a menu. Do not repeat the lab name in multiple pills and headers unless the current activity changed skills and that distinction matters.

Footer has one primary action appropriate to stage: Check answer, Confirm answer, Continue, Finish set, or Continue next section. It reserves safe-area and keyboard space. Skip is separate and says its evidence consequence concisely. Do not align Hint, Skip and a long Submit label in an unconditional horizontal row on compact screens.

The session presentation reducer must expose explicit states so controls cannot infer behavior from a view's incidental position. The core state model may use different identifiers, but the user-visible transitions must satisfy this table:

| Presentation state | Visible content | Primary action | Exit and failure behavior |
|---|---|---|---|
| Loading next item | Stable header; progress text; no stale previous input | Disabled until valid item arrives | Save and close remains available; generation failure exposes retry/alternate supported activity |
| Answering, incomplete | Prompt, stimulus and editable response; concise requirement | Disabled Check answer/Confirm answer | Save the incomplete draft; do not mark it incorrect |
| Answering, valid ordinary | Same surface; optional confidence according to policy | Check answer | Save exact input and any chosen confidence; ignore duplicate activation while commit is pending |
| Answering, protected/calibration | Same surface; required confidence with no default | Confirm answer only after response and confidence are valid | Save exact draft without revealing any correctness |
| Commit pending | Response remains visible; progress state on action | Disabled with Saving… | Exit request is queued; reconcile commit. A durable pending intent may close as Answer waiting to finish saving under RUN-022. Never claim normal saved success or discard the journal |
| Ordinary feedback | Prompt, submitted response, result and explanation together | Continue | Optional reflection and repair can be deferred; Save and close preserves completed attempt |
| Protected answer saved | Prompt/response summary and neutral Answer saved | Continue | No key, correctness, grading color, result sound or leaked accessible value; save exact protected stage |
| Self-check reference | Original recall response plus source reference and match choices | Save self-check after rating | Recall input remains historically fixed; Save and close resumes comparison without pretending an independent score |
| Reflection draft | Prompt/feedback context where allowed; optional or explicitly required reflection | Save reflection or Continue as policy permits | Save and close always works; no preselected diagnosis or unexplained required note |
| Section summary | Saved counts, takeaway and remaining section estimate | Continue next section or Finish set | Closing returns to launch context; retry unfinished save before showing success |
| Paused | Brief paused overlay over inaccessible background content | Resume | Save and close at every resumable stage; elapsed pause excluded from active timing |

Resume restores the exact recorded phase, including protected acknowledgement and revealed-but-unrated self-check comparison. A completed protected answer never resumes through the ordinary correctness-feedback renderer. A retry uses the same pending attempt identity. A repair uses a new identity. A new question clears answer, validation, optional confidence, hint state and transient feedback only after the prior stage has been checkpointed. This separation is required to avoid the common “next item shows previous answer” and “retry duplicates score” failures.

<a id="ux-017"></a>

### UX-017 — Confidence before commit, inline

Display the existing V1 confidence labels inline with the entered response: **Guessing, Uncertain, Fairly confident, Certain**, mapped respectively to the existing descriptive proxies **0.25, 0.45, 0.72, 0.92** under EVD-005. Preserve the current localized semantic labels; a future wording/proxy change requires an explicit versioned policy decision. No choice is selected by default. For protected baseline/reassessment and explicit calibration, the learner chooses confidence before the same Submit action commits the response. The original response remains visible; there is no dedicated confidence screen.

For protected/calibration tasks, answer entry → inline explicit confidence → Submit preserves the necessary order. No correctness cue, answer highlighting, reference or hint that leaks the answer may appear before confidence is committed. If response editing is allowed, Edit answer returns to entry and clears or re-confirms confidence according to core policy. If editing is forbidden, explain it before initial submission.

For ordinary scored practice, confidence is optional inline. Exactly one deterministic slot in each group of five presentation ordinals expands the invitation under EVD-005; repeated rendering or resume is not another presentation. The remaining items may expose the optional control without expanding it. Skipping never blocks the answer. Timed Rapid Recall/fluency does not collect confidence. An omitted confidence value is absent evidence, not the previous question's value. A correct answer never requires navigating to a confidence page and then another feedback page.

Acceptance: automation proves ordering of response, confidence and key reveal. VoiceOver focus remains in the relevant group. No double click or Enter repetition creates two attempts. Every answer can be understood while choosing confidence because the original response remains visible.

<a id="ux-018"></a>

### UX-018 — Feedback that teaches

Ordinary-practice feedback appears immediately after successful commit and has this order:

1. Result: Correct, Partly correct, or Let's review this.
2. The learner's answer and the expected answer, using readable typed presentation.
3. One decisive explanation of why or how.
4. Optional worked steps, source evidence or a diagram.
5. Continue and, when useful, Try a similar question.

Avoid generic “The durable scorer recorded…” as teaching copy. Do not repeat the entire question in an explanation without adding reasoning. Partial credit must identify which part worked and which part needs repair. For personal self-checks, use Matched, Partly, or Not yet, never a Correct banner, “100%,” or deterministic ability-evidence framing. Say “Your self-check: partly matched” when the learner rated the match; the app has not independently proved the open response.

Protected responses show neutral “Answer saved” with no per-item correctness or solution. Say “Your results appear after this block.” At block completion show dimensional summaries and concept guidance; **Practice this skill** launches a fresh instructional variant. Reusable protected items never expose exact keys or solutions in ordinary history or exports intended for learner review. Only explicitly retired/disclosed forms may reveal exact item feedback, with the core exposure/invalidation transaction; that is not default shipping behavior. Do not render hidden keys inside accessibility labels, source previews, diagnostic details or a repair button.

<a id="ux-019"></a>

### UX-019 — Graduated help and repair

Hints are an ordered ladder: a directional cue, a more concrete step, then a worked step or solution if permitted. Each tap reveals the next available help. Label the remaining state honestly: Hint 1 of 3, Next hint, Show worked step. Do not disable help after the first hint while later authored hints exist.

Record actual help used. A correct assisted answer must not be displayed as independent mastery. A solution reveal can end scoring or convert the attempt's evidence according to core policy; the interface explains that before reveal where it materially changes the outcome.

After a mistake or substantial help, offer a fresh related item that practices the same subskill with different surface content. It must not be the identical keyed question with a different title. The repair uses a new attempt and preserves the original result. The learner can defer it to Review rather than elongating a short session unexpectedly.

Acceptance: all authored hint levels are reachable; first clue is useful for the specific item; help counts are accurate; protected questions cannot expose hints; repair content is valid, distinct and matched to the intended subskill.

<a id="ux-020"></a>

### UX-020 — Reflection is useful and never a trap

For ordinary practice, show the explanation first, then an optional concise reflection: “What will you check next time?” Offer a few relevant reasons and an explicit “Not sure yet,” with no error diagnosis preselected. An inferred reason is visibly a suggestion, not a user-confirmed diagnosis. Pre-feedback reflection is allowed only for an explicitly designated metacognition task, with its purpose explained and Save and close available. A generic transfer label, wrong answer, repeated error or high confidence alone does not make reflection mandatory or move it ahead of ordinary correction.

Do not preselect a reason and then count a quick Save as independent learner reflection. Persist user confirmation separately from deterministic error classification. An optional note remains optional; empty notes should not be an unexplained blocker. Character limits show remaining space only when relevant rather than dominating an empty screen.

Acceptance: the learner can view normal correction without completing a survey, edit a reflection without changing the original score, and safely resume a pending required reflection. Error-pattern reporting distinguishes inferred and self-reported reasons.

<a id="ux-021"></a>

### UX-021 — Session exit, pause and completion

Pause freezes active timing according to core policy and clearly offers Resume and Save and close in every resumable stage, including confidence and reflection. Backgrounding checkpoints the current stage and stops answer timing. Returning to the foreground starts a new answer-time segment only after explicit run resumption into an eligible visible answering state. Paused, loading, feedback, self-check comparison, reflection and summary never accrue answer-solving time. Previously accumulated time remains; an unknown interruption is marked honestly and excluded from clean speed evidence. Separately labeled session-use time may include other active learning phases. Closing the scratchpad must not accidentally commit an answer.

Completion summarizes work: questions attempted, correct/partial outcomes where appropriate, help used, one learning takeaway, and an optional next action. XP can appear as a small acknowledgement. Do not show a celebratory complete state before writes succeed. If a section is incomplete because the learner skipped everything or evidence was insufficient, say what happened without pretending a valid assessment result exists.

For daily sections, **Continue next section** is primary when the learner chose a multi-section session; **Finish for now** remains available. The summary identifies the remaining time estimate before continuing. Completing the last section returns to stable Today completion.

Acceptance: pause/resume, quit/relaunch, skip, error reflection, last-question completion and multi-section continuation produce no duplicate attempts, repeated XP or reset daily completion. Save failure remains recoverable.

<a id="ux-022"></a>

### UX-022 — Scratchpad with visible context

Preserve typed notes and PencilKit drawing. On iPad and sufficiently wide Mac windows, provide a split pane with the problem on one side and scratchpad on the other. At compact widths use an expandable panel or sheet with a pinned problem preview that can expand to include the relevant table/diagram.

Include Draw/Notes where supported, Undo, Redo and Clear. Clear should offer immediate Undo; do not require a frightening confirmation for every reversible stroke reset. Keep scratchpad outside scoring unless a particular future interaction explicitly uses structured working as a response. Preserve unsupported drawing bytes when opening a note on a platform that cannot edit them.

Acceptance: a learner can refer to the original question while writing; drawing survives close/reopen and supported export/restore; Mac opening an iPad drawing does not erase it; keyboard and screen-reader users receive a fully usable notes path.

## 7. Progress, Review and readable History

<a id="ux-023"></a>

### UX-023 — Progress overview leads with useful interpretation

Progress has three explicit, visible sections or a segmented control: **Overview, Review, History**. Default to Overview and retain the last selection during same-session navigation. Overview shows recent learning, one next-practice recommendation, consistency and skill summaries. Put details of uncertainty, evidence channels and methods under clearly labeled disclosures.

Do not lead with an empty ring and “unassessed.” A first-use state says what practice will reveal and provides Start practice or a starting check. A filtered-empty state states that history still exists and offers Clear filters. Explain personal-source practice separately without suggesting it was wasted because it does not affect protected skill estimates.

Charts support point inspection: date, activity type, sample count and displayed value, plus a route to the relevant history. Preserve an accessible table/summary. A chart is not a replacement for an understandable sentence about what changed, and a tiny sample must not be presented as robust improvement.

<a id="ux-024"></a>

### UX-024 — Review is a learning queue

Review groups Due now, Saved for later and Recently repaired. Queue entries show skill/topic, why it appears, source where appropriate, expected length and whether it uses a fresh similar item or source recall. Primary action is **Start review**. A learner can defer a review, remove a self-added bookmark, or report unsuitable content without deleting prior attempts.

A due review should not expose its answer in the queue preview. Review suggestions follow core scheduling and question quarantine rules. Completing a repair updates the schedule and records new evidence; it does not rewrite the original error. Today due-review shortcut opens this exact queue or a bounded review session with clear context.

Acceptance: due count matches the core schedule; not-due items are not silently included in a time estimate; completion removes or reschedules an item correctly; no closed-loop repetition of a revealed protected question.

<a id="ux-025"></a>

### UX-025 — History is directly readable, searchable and replayable

History lists all relevant saved attempts, with filters for date, skill, result, support and source. Reusable protected items use safe dimensional/concept guidance and never reveal exact keys or solutions; exports intended for learner review preserve that rule. Keep advanced timing/confidence/version filters under More filters. Rows show a readable prompt excerpt, readable answer and result. Search uses visible text, not only serialized payloads or internal IDs.

Answer detail must reconstruct enough original context to understand the work: prompt, options or structured input labels, table/diagram, learner response, expected result where allowed, original teaching explanation, hints used and source citations. The original attempt remains immutable. A learner may add a note, bookmark, report, or start a similar question, all as separate actions/data.

Fix the verified raw JSON leak at its presentation boundary. Current `saveExerciseAttempt` encodes `NFExerciseResponse` into `AttemptRecord.response` (`PersistenceModels.swift:3041–3050`); snapshot/history/detail render it directly (`ProgressDashboardView.swift:1888`, `:2270`, `:2333`). Preserve the raw payload for compatibility, but render a typed display representation:

| Response kind | Main display |
|---|---|
| Numeric | Original entered value and unit, e.g. `1000` or `12.5 cm` |
| Single choice | Saved visible option label, not option ID |
| Multiple choice | Selected visible labels in original option order |
| Ordered steps | Numbered saved step labels |
| Short text | Exact entered prose with readable line breaks |
| Self-check | Learner's answer, then their match rating |
| Claim/evidence | Named claim with selected evidence labels and relation |
| Logic state | Named fields and values; named rule if selected |

Do not replace raw JSON with `normalizedResponse` blindly: choice/order/evidence normalizations also contain IDs. Persist labels and original context at attempt time. For older records without sufficient context, show what can be decoded honestly and mark unavailable labels; do not silently invent a historical answer. Technical payload and versions may be available under **Technical details**, outside the default learner view.

Acceptance: all eight schema families remain readable after relaunch, content updates and export/restore in standard history, completed daily review and generated-set history. No `_0`, Codable envelope, property key or internal option/claim/rule ID appears in primary copy or VoiceOver. Protected keys remain inaccessible.

## 8. Sources and Settings

<a id="ux-026"></a>

### UX-026 — Sources root and import states

Sources shows search, Import source, recent sources and optional collections. Rows identify title/filename, supported content type, preparation state, and available learning actions. A source with no readable text is not marked Ready merely because its original file exists.

Import supports existing format, size, local extraction and OCR contracts. Show meaningful phases: copying, extracting text, recognizing text, preparing review. Display current file and batch completion. Cancel stops future work and explains which completed imports remain. Retry unfinished operates on unfinished items rather than duplicating ready sources.

Duplicate handling should show the existing source and offered outcomes in ordinary language: Use existing, Keep both, Replace, Skip. Replacement must explain linked history consequences and confirm only the actual destructive boundary. A processing failure offers Open details, Retry extraction or Run local OCR where supported. Imported code is displayed as text, never executed.

Acceptance: fresh, empty, processing, partial batch, cancelled, duplicate, unreadable, unsupported and recovery states are visually and functionally distinct. Each actionable state has a clear next step. Importing a synthetic source cannot leave stale navigation over Settings.

<a id="ux-027"></a>

### UX-027 — Source detail and studying

Source detail leads with **Read source**, **Review from memory**, and **Create question set**, enabled according to readiness and permissions. Show a short content preview and where the original is stored. File metadata, detailed extraction diagnostics and sync mechanics are optional details.

A reading view provides search, clear excerpt location, readable text/math/tables and links back to original context. A review prompt requires recall before revealing reference. A self-check makes the learner's role explicit and uses Matched, Partly, or Not yet without a numeric correctness percentage. The question-creation route carries the source selection and returns to the source when closed.

Question privacy and sync are separate controls with plain explanations. Disabling question generation does not imply deleting the original. Syncing an original does not imply extracted text/index sync. User-facing copy must describe actual capability, not aspirations.

Acceptance: a source can be read, reviewed and used for permitted generation with predictable returns. Missing/changed/deleted source chunks offer recovery instead of an empty modal. Reference excerpts preserve citations and do not overstate factual authority.

<a id="ux-028"></a>

### UX-028 — Searchable Settings categories

Replace the broad card dashboard with searchable categories: Practice; Accessibility; Notifications; Question Writer; Data and sync; About. Search matches labels and common synonyms such as language, dark, sound, export, reminders and timer. Each result deep-links to the control and highlights it briefly without disruptive animation.

Practice contains duration, timing, contexts, emphasis and day boundary. Accessibility contains language, timer visibility, motion, supported visual alternatives and input preferences/calibration. Notifications describes permission and schedule state. Question Writer shows configuration and a test/recovery action. Data and sync contains export/restore, local storage, sync status, reports and deletion. About contains version and methodology.

Use live values where changes are immediately saved. Editors with multiple related changes have explicit Save/Cancel and dirty-state behavior. Data deletion remains a separate destructive flow with concrete scope and progress. Never convert a failure to “Done” simply because local cleanup started.

Acceptance: a learner can find language, hide timer, sound, duration, export and restore by both browsing and search. Changing unrelated preferences preserves active session and daily completion. Deletion/export behaviors match the privacy specification.

## 9. Rich interaction slices that teach a specific skill

Each slice below is an implementation candidate with a bounded first release. Build one polished interaction per family before multiplying variants. The content specification owns item validity, difficulty bands and supported claims. The response emitted by every visual interaction must also be producible through an accessible control path.

<a id="int-001"></a>

### INT-001 — Mental math: estimate, decompose, solve, repair

Use a problem such as 57 × 19 to teach the strategy `57 × (20 − 1)`. Stage one requests a rough estimate or range only when that is the chosen mechanic. Stage two requests the exact value. A learner can expand optional working without affecting scoring unless the mechanic explicitly scores steps. Feedback shows the chosen decomposition—57 × 20 = 1140, then 1140 − 57 = 1083—and highlights the first divergence if structured working was entered. This exact worked example is instructional content, not a claim that the app currently stores these teaching steps.

Hints progress from “Use a nearby multiple of ten” to “Calculate 57 × 20, then subtract one group of 57” to a worked intermediate value. Do not present a generic operation-naming clue as the only help. The repair changes operands and keeps the same strategy before expanding to a different strategy.

Accessible equivalent: labeled estimate and exact-value fields, explicit units, ordered text working steps, keyboard-operable step reveal. Numeric input must permit signs, decimal separator and fractions when the content contract accepts them; do not use a keypad that makes accepted answers impossible. Preserve a standard hardware keyboard path.

Acceptance: exact and estimate stages cannot overwrite one another; support use is recorded; the repair is distinct; large text shows operands and answer simultaneously; history replays both stages.

<a id="int-002"></a>

### INT-002 — Spatial reasoning: controlled transformations with reset

Preserve native 3D orbit and static 2D equivalents. Add Reset view, Front, Side, Top and a clearly labeled target orientation. For a transformation activity, let the learner apply a discrete rotate/reflect operation to a copy of the object rather than unconstrained camera orbit being mistaken for the answer. Camera manipulation and object transformation must be separate concepts.

For cube-net learning, provide a controlled fold/unfold demonstration only in permitted practice/feedback. A protected mental-rotation assessment must not offer a manipulation that performs the reasoning being assessed. State the available tools before the answer begins.

Accessible equivalent: keyboard/stepper actions naming axis and angle; a structured description of faces/relationships; a validated nonvisual task when it measures an appropriate construct. If no equivalent exists, provide an exclusion/alternative with an honest scope statement rather than pretending a different task measures the same visual ability.

Acceptance: Reset returns exactly to the authored state; camera orbit never changes scored response; reduced motion uses discrete transitions; operations and object state are announced; visual descriptions do not reveal the key.

<a id="int-003"></a>

### INT-003 — Quantitative reasoning: predict, inspect and compare data

Show a small chart/table with a concrete decision: identify a trend, estimate a value, compare rates, or select the justified conclusion. Before revealing an explanatory overlay, ask for a prediction. Let the learner inspect points to see exact values and units when the activity allows it. For graph construction, allow selecting or dragging a point with keyboard adjustment as an equivalent.

Feedback connects the answer to the relevant data, denominator, uncertainty or scale. Highlight only the decisive evidence, not every bar. Avoid cosmetic charts whose labels already state the answer. Difficulty can vary data noise, relationships and reasoning steps according to validated content bands, not simply add more rows.

Accessible equivalent: a real labeled data table, select-value controls and text descriptions of axes/scales; point inspection via keyboard and VoiceOver. Visual color cannot be the sole series identifier.

Acceptance: displayed chart and table derive from the same source; units are present; pointer and non-pointer answers serialize identically; no interpolation or visual scaling changes the correct result unexpectedly.

<a id="int-004"></a>

### INT-004 — Scientific reasoning: claim, evidence and experimental choice

Use a concrete miniature study. Ask the learner to connect a claim to supporting or limiting evidence, then choose an experimental change that distinguishes explanations. Render claims and evidence as manageable lists with a selected-claim panel; do not repeat a long evidence list under every claim.

Pointer users may drag a piece of evidence to a claim. Every relationship must also be creatable by choosing a claim and checking evidence options. Show current connections in text. Undo and Clear current claim are available. Validation states exactly what is incomplete without implying which evidence is correct.

Feedback identifies what the evidence supports, what it does not establish, and one relevant confound or control. Repair changes the study context while keeping the inference structure. Open-ended explanations can be optional reflection unless a validated scoring scheme exists.

Acceptance: all required claims can be mapped, incomplete structure cannot be committed, relationships remain readable in history, accessible controls produce the same mapping, and no raw claim/evidence ID is displayed.

<a id="int-005"></a>

### INT-005 — Logic and debugging: visible state trace

Display short pseudocode alongside a variable-state table and current line. For instructional practice, Step executes one permitted line and highlights changed variables; Reset restarts from the original input. The learner can predict the next state before revealing execution. For an assessment of independent tracing, step reveal is disabled or scored as support according to policy.

A bug-finding slice lets the learner select a line, choose a violated invariant, or enter a corrected expression supported by the deterministic engine. Avoid pretending arbitrary code edits are safely evaluated when the interpreter only supports a restricted grammar. Show accepted syntax in examples, not an internal parser error.

Accessible equivalent: numbered text lines, Next step and Previous revealed step controls, labeled variable table, explicit changed-value announcements, and a line-selection picker. Do not require dragging tiny line markers.

Acceptance: UI state matches interpreter state; prediction is captured before reveal; reset never erases an already committed attempt; unsupported syntax gets useful validation; history preserves code and original input.

<a id="int-006"></a>

### INT-006 — Retrieval: recall, reference and honest self-check

Present a focused question from a known source and let the learner answer before seeing the excerpt. After confidence where required, show the relevant reference with a precise location and a short criteria list. Ask Matched, Partly, or Not yet only when the response is genuinely self-checked; label the result accordingly.

Offer an option to mark the question ambiguous or the excerpt insufficient. A repair may rephrase the same idea or ask a related retrieval question, but must not claim source-grounded quality if the source only contains fragments. Scheduling follows the core retention model and keeps early re-exposure distinct from a valid delayed check.

Accessible equivalent: labeled text entry, standard dictation support where available, expandable source text, keyboard-operable match choices. Read reference only after the user chooses to reveal it.

Acceptance: no key before recall; the source citation opens useful context; matched status is not misrepresented as independently verified correctness; source deletion or reprocessing yields recovery without a blank screen.

<a id="int-007"></a>

### INT-007 — Transfer: choose the useful structure in a new context

Use a task that genuinely requires carrying a familiar relationship into a different context. For example, after proportional reasoning, compare resource allocation in a different domain with changed surface details. The learner selects or constructs the useful relationship and solves. A debrief may invite an optional explanation of what carried over. Pre-feedback reflection is permitted only when the task is separately and explicitly designated as a metacognition task; transfer alone is not a mandatory-reflection policy.

Keep the first release constrained: two skills, a bounded problem and a deterministic response schema. Optional scaffolding can identify the relevant relationship, but that changes evidence status according to core rules. A debrief explicitly connects the old and new contexts, including what differs. Do not relabel ordinary multiple choice as transfer because its story mentions another discipline.

Accessible equivalent: text/table representation, labeled relationship selection and numeric/structured response. Reflection can be typed and resumed. Time pressure is not added merely to make transfer feel harder.

Acceptance: content review verifies the intended transfer distance; cues are controlled; explanation names the shared structure; using help is recorded; no requirement prevents Save and close.

<a id="int-008"></a>

### INT-008 — Ordering, touch and keyboard conventions

Where ordering is used, support drag with clear insertion position, plus Move up/Move down and keyboard commands. Announce the resulting position. Keep the selected item stable during reorder. A disabled move at the first/last position is understandable and does not remove the item's accessible identity.

For selectable choices, show a checkbox for multiple selection and a radio-style selection for single choice. Do not use the same circle/check treatment for both without instructions. Selected state must be visible beyond color. All manipulations offer undo before commit where allowed.

Acceptance: pointer, touch, keyboard and VoiceOver produce identical ordering/selection responses; reordering never loses text; accidental drag cancellation restores the previous state; history shows labels in the submitted order.

## 10. Responsive design and measured visual tokens

These are proposed implementation targets. They must be checked against actual supported devices and the final content, not treated as current measured app values.

<a id="a11y-001"></a>

### A11Y-001 — Layout matrix and breakpoints

Support the smallest device/window allowed by the product. Required QA widths: 320, 375, 390/393, 430, 600, 768, 1024 and 1440 points where the platform permits them. Test landscape phone, narrow Mac, iPad split view, software keyboard, English/Japanese and accessibility text sizes.

Use available container width, not device model, to choose composition. Below 600pt use a single content column; 600–899pt can use selected two-column supporting layouts while keeping the question primary; at 900pt and wider, permit problem/scratchpad and source/notes split panes. Accessibility sizes can force a single column regardless of width. A control label that no longer fits should wrap or reflow, never shrink below the chosen readable text style.

<a id="a11y-002"></a>

### A11Y-002 — Token proposal

| Token | Proposed value/behavior | Validation |
|---|---|---|
| Spacing scale | 4, 8, 12, 16, 24, 32, 48pt | One spacing system across all screens |
| Compact horizontal margin | 16pt; 12pt only at the minimum 320pt width if necessary | No clipped control or text |
| Regular margin | 24pt, increasing to 32pt for wide reading surfaces | Content does not stretch indefinitely |
| Learning-text line width | Approximately 60–75 Latin characters; practical width cap around 680–760pt | Check prose, equations and Japanese wrapping |
| Ordinary section gap | 24pt | Grouping visible without excessive scrolling |
| Card radius | 16pt ordinary, 20pt primary surface | Avoid multiple competing radius systems |
| Control radius | 10–12pt | Clear distinction from content surfaces |
| Minimum touch target | 44 × 44pt; primary action usually 48–52pt high at default size | Verify actual hittable rectangle |
| Primary action | One semantic accent fill and tested foreground | Contrast checked in both appearances |
| Text styles | Platform Dynamic Type styles: title, title2, headline, body, subheadline, footnote | No fixed-size body text |
| Essential body copy | Body or subheadline, not caption2 | Large text still fits |
| Secondary metadata | Footnote; no essential instruction below body-equivalent readability | Contrast at least 4.5:1 for normal text |
| Borders | 1pt semantic separator where needed | Not relied on as the only focus/selection indicator |
| Focus indicator | Visible platform focus ring or 2pt-equivalent semantic ring | 3:1 against adjacent colors |
| Standard motion | 120–180ms small state change, 200–250ms navigation where native | Reduced motion removes spatial displacement |
| Loading feedback | Immediate disabled/action state; show progress text if operation persists | No unresponsive interval without feedback |

Actual palette colors should be derived from existing semantic theme tokens where they pass rendered contrast. Do not copy a bright accent onto white text indiscriminately. Measure final light/dark combinations, selected/unselected/disabled states and material backgrounds. Avoid large blurred or glowing backgrounds behind instructional text; use a restrained surface and accent hierarchy.

<a id="a11y-003"></a>

### A11Y-003 — Dynamic Type and safe areas

At accessibility text sizes, reflow numeric value/unit controls, confidence choices, metadata rows and chart summaries vertically. Decorative progress rings may shrink or disappear; their information remains text. A three-metric row must become a stack when it stops fitting.

Action footers reserve their full height and keyboard/safe-area insets. The last control can scroll fully above the footer and tab bar. Long instructions, error text and Japanese labels must never be constrained to one or two lines just to preserve a card height.

Acceptance: capture and manually inspect all tab roots, onboarding, each response family, feedback, pause, history and source detail at default and largest supported accessibility size. No hidden essential text, overlapping action, horizontal clipping or unreachable field passes review.

<a id="a11y-004"></a>

### A11Y-004 — Focus and keyboard sequence

Default session focus order is: screen/activity heading; position/timing summary; prompt and required representation; response fields/options; confidence if present; validation; primary action; hint/skip utilities; remaining details. Visual and accessibility order must agree. Utility controls remain reachable without being repeated before every text fragment.

On a new question, move keyboard focus to the first appropriate answer field; move VoiceOver focus to the new prompt heading or a brief question announcement, then let the user navigate. After submission, announce the result and move to feedback without losing the ability to inspect the answer. After error, focus the offending field or an error summary with a direct route to it.

Hardware keyboard: Tab/Shift-Tab follow logical order; Enter submits only when the current stage and control type allow it; multiline prose uses a deliberate modified submit shortcut; Escape pauses or closes a reversible sheet, never silently discards work. Arrow keys navigate choice groups only when that group owns focus. Visible shortcut hints should not crowd the phone layout.

Acceptance: complete each response family, pause, resume, report and finish using only keyboard. No hidden default action bypasses confidence, commits twice or advances through a disabled state.

<a id="a11y-005"></a>

### A11Y-005 — VoiceOver names, values and announcements

Every editor and slider has an explicit accessible name. Required names include Your answer, Your answer from memory, Unit, Difficulty, Confidence, Reflection note and Scratchpad notes. A neighboring visible Text is not sufficient for an unlabeled TextEditor or Slider.

Selection announces selected/not selected and the number selected where useful. Reorder announces position. Chart inspection announces series, date, value and unit. Tables expose headers and cell coordinates without reading the whole table as one giant inaccessible blob. A source location is a meaningful label, not an internal chunk ID.

Use live announcements sparingly: result, completed save, failed save, next question, import completion and changed state relevant to the task. Do not announce a countdown every second. Move focus after asynchronous generation to a result heading only if it will not interrupt active typing elsewhere.

Acceptance: a VoiceOver user can complete the first-session journey independently. Inspect the actual accessibility tree and operate the controls; identifier presence alone does not prove usability.

<a id="a11y-006"></a>

### A11Y-006 — Motion, audio, haptics and sensory alternatives

Respect system Reduce Motion and the app preference. Use fade or immediate state replacement rather than spinning, bouncing, orbiting or sliding instructional content. No model rotates automatically. A static equivalent remains available when 3D is not usable.

Haptics and sound are optional reinforcement, never the only indication of correctness, timeout, selection or failure. Match feedback to user preferences and system capabilities. Do not play celebration sound for an incorrect or insufficient-evidence result merely because the session ended.

Acceptance: with motion, audio and haptics disabled, every state transition remains understandable. No protected answer is leaked by a sound or haptic before required confidence commit.

## 11. Standard copy and localization

<a id="copy-001"></a>

### COPY-001 — Vocabulary contract

| Use | Avoid in default learner copy |
|---|---|
| Today | Forge as an unexplained navigation label |
| Practice | Train, Lab, Module as interchangeable navigation terms |
| Skill | Ability core, dimension, attribution |
| Activity | Mechanic, template family, protocol |
| Section | Chapter/block/circuit phase used inconsistently |
| Try a new context | Crossover/transfer jargon without explanation |
| Your saved answer | Immutable response |
| Practice XP / Participation | Forge XP / engagement as learner-facing metric names |
| Explanation | Durable scoring explanation |
| Checked answer | Deterministically validated payload |
| Source | Library item/chunk when naming navigation |
| Question Writer | Internal Shortcut implementation name except setup details |
| Saved on this device | Persisted locally |

Technical terminology may be necessary in advanced methodology or developer exports. Keep those surfaces explicitly secondary. A statement such as “This task does not change your skill estimate” can be useful; “Immutable score preserving seeded diagnostic” is not.

<a id="copy-002"></a>

### COPY-002 — Standard action and state catalog

| Situation | Preferred copy |
|---|---|
| New daily session | Start today's practice |
| Interrupted work | Continue session |
| Main response action | Check answer |
| Required confidence commit | Confirm answer |
| Between questions | Continue |
| Final question complete | Finish set |
| Daily continuation | Continue next section |
| Safe leave | Save and close |
| Pause | Session paused |
| Saved draft | Saved on this device |
| Failed save | We couldn't save this yet. Your answer is still here. |
| Required field | Enter your answer to continue. |
| Incomplete mapping | Choose evidence for each required claim. |
| Hint | Get a hint / Next hint / Show worked step |
| Correct result | Correct |
| Partial result | Partly correct |
| Incorrect result | Let's review this |
| Self-check outcome | Your self-check: partly matched |
| Due review | Ready to review |
| No reviews due | You're up to date. |
| Empty history | Your completed answers will appear here. |
| Filtered empty | No answers match these filters. |
| Source preparing | Preparing this source… |
| Unreadable source | We couldn't find readable text. |
| Temporary set | Temporary · new practice available for 7 days |
| Expired temporary set | New practice from this temporary set has expired. Saved answers remain in History. |
| Expired set with an unfinished accepted run | You can still continue your saved session. |
| Durable pending save | Answer waiting to finish saving |
| Recovered run without local ownership | Recovered work · read-only. You can review your answer and notes, or start new practice. |
| Report saved | Report saved. This question will be handled according to your report settings. |

The report confirmation must describe the actual quarantine behavior. Do not promise human review, a server submission or a fix when reports remain local. Error copy should offer the next usable action and omit raw exception text unless the learner explicitly opens technical details.

<a id="copy-003"></a>

### COPY-003 — English and Japanese parity

Every user-facing string uses the localization system, including runtime enum labels, validation, empty states, context explanations, chart announcements, date/count plurals, action labels, reported-item states and external setup instructions. Do not build English sentences by concatenating localized fragments where Japanese order differs.

Use locale-aware dates, times, plural/count formatting, numeric input and units according to the content contract. Japanese must wrap naturally without horizontal scrolling for ordinary prose. Math and code preserve semantic tokens; translating a display label must not change a canonical answer or scoring key. English source content may remain English when that is what the learner imported, but app chrome must not switch languages unpredictably.

Provide a manual Japanese review pass for clarity and educational tone, not just a catalog completeness check. Avoid excessive katakana technical jargon where a familiar Japanese explanation is clearer. A language change preserves the active route and saved draft; if changing a live question's language could alter validity, apply it to the next question/session and explain that.

Acceptance: run the same first-use, incorrect-answer, confidence, source import, history and export journeys in English and Japanese. No raw localization key, untranslated enum case, truncated button or mixed-language error passes. Screen-reader output uses the appropriate language for app text.

## 12. Implementation packages and definition of done

<a id="ux-029"></a>

### UX-029 — Package order

**Package A: repair visible defects and navigation.** Fix raw JSON presentation for all response families, reflection safe exit, stale nested content, and any reproduced navigation hang. Correct mismatched destination names. Add direct History and Review entry points. Preserve all existing scoring and persistence contracts.

**Package B: rebuild the answer loop.** Create the continuous problem/response/feedback surface, inline confidence policy, graduated hints, readable original feedback and targeted repair. Include smallest-width, keyboard and VoiceOver operation before adding more activity types.

**Package C: simplify discovery and first use.** Implement Today hierarchy, sample-first onboarding, optional starting check, exact activity search, explicit adaptive difficulty versus timing, and categorized Settings. Connect all routes to the core navigation model.

**Package D: durable study resources.** Implement saved/temporary distinction, collection organization, original-context answer snapshots and useful source reading/review returns. Align retention and deletion with the privacy/persistence specification.

**Package E: polished interaction slices.** Implement one bounded slice per family with deterministic/accessible response equivalence, then broaden content only after usability and question-quality review.

<a id="ux-030"></a>

### UX-030 — Release evidence required for this appendix

For every package, provide a traceable list of implemented requirement IDs, automated checks that validate actual behavior, screenshots where layout matters, and a concise manual journey ledger. Record platform, OS, device/window size, language, text size, input method and whether the data fixture is fresh or established.

The minimum manual suite covers fresh sample/setup; optional check pause/resume; correct/wrong/partial answer; hints through their final level; required confidence; optional and required reflection; save failure/retry; all eight response representations in history; daily completion and preference edit; deep destination switching; empty/processing/failed source; generated-set expiry versus saved retention; keyboard and VoiceOver; minimum-width and largest-text presentation.

Use representative usability sessions to evaluate clarity and perceived professionalism. Ask learners to perform tasks without coaching, then explain what they believe happened. Log wrong turns, hesitation, misunderstood labels, unintended difficulty, skipped explanations and reports of repetitive questions. Measure first-practice access, time spent on administrative controls versus solving, successful error recovery, and ability to find a prior explanation. Proposed targets include a first practice within two clear setup decisions, one obvious resume action, no mandatory full-page confidence detour in ordinary practice, and all critical tasks independently completable with keyboard and VoiceOver.

Do not declare the app professional because the UI tests pass or the cards look consistent. Completion requires the actual learner journeys to be understandable, responsive, recoverable and educationally useful, with the evidence limitations documented by the wider QA plan.

---

<!-- Source: 02_Content_and_Scoring.md -->

# 02 — Content, question quality, and scoring specification

**Status:** proposed implementation specification, based on QA executed on 4 September 2026. Requirements using **must** describe the intended replacement behavior. They do not describe capabilities already delivered. No application implementation is included in this chapter.

**Scope:** deterministic exercise contracts, editorial production, the eight existing response types, answer equivalence, feedback authority, item identity, the mixed offline banks, all 58 existing catalog activities, and seven complete worked examples. The adaptation chapter owns learner estimation and scheduling policy. The application/state chapter owns persistence transactions and migrations. The interaction chapter owns controls, layouts, and accessibility implementation. Those implementations must preserve the content and scoring invariants defined here.

## 1. Evidence and the outcomes this chapter must deliver

The executable evidence is recorded in [ExecutedProbeResults.txt](../QA_2026-09-04/ExecutedProbeResults.txt). Six content probes executed the application generators and scorer; the bank probe checked 4,000 actual identities. Their passing assertions confirmed defects in the current application. Passing those investigative probes is **not** a release acceptance criterion: the eventual regression tests must assert the corrected behavior.

| Evidence ID | Confirmed current behavior | User consequence | Requirements that replace it |
|---|---|---|---|
| QA-C01 | Spatial seed 11 produces two `(-10, 10)` choices; one receives full credit and one receives none. | A correct answer can be penalized arbitrarily. | CON-006; SCO-006; QA-S01 |
| QA-C02 | Science seed 8424208090942894707 calls intervals 18–26 and 27–35 overlapping; 266 of the 1,000 science bank items have this contradiction. | The lesson contradicts its own evidence and teaches an unreliable inference. | CON-007; EX-C104; QA-S02 |
| QA-C03 | The canonical arithmetic-mean wording passes, while “Sum all observations then divide by their count” fails; `2*x` and `4x` fail equivalent derivative questions. | The app rewards guessing its wording over understanding. | SCO-003; SCO-009 through SCO-013; QA-S03 |
| QA-C04 | `f(b)-f(a)` receives full credit when the question defines `F′=f` and requires `F(b)-F(a)`. | The app accepts a substantively wrong mathematical answer. | SCO-010; SCO-011; QA-S04 |
| QA-C05 | An explicitly accepted `yes` instead of `plausible` yields `isCorrect=true` and credit 2/3. | Feedback and recorded achievement disagree. | SCO-001; SCO-015; QA-S05 |
| QA-C06 | Transfer contains 986 rate-product questions; Logic contains 990 stale-state traces; Science contains 557 mean mappings and 436 interval questions. | Distinct numbers feel like the same question repeatedly. | CON-014 through CON-019; QA-B01 through QA-B06 |
| QA-C07 | Retrieval has 101 different targets delivered as the same fixed retrieve/compare/locate/retry sequence. | Completing a generic workflow is counted as exposure to a knowledge target without eliciting that knowledge. | CON-010; CON-016; CON-026; QA-F48 |
| QA-C08 | Source inspection shows solution cues in context and representations rendered before answers, including protected checks. | Baseline and independent practice can be answered from a supplied solution cue. | CON-004; CON-008; QA-S06 |
| QA-C09 | The same seed at target difficulty 0.2 and 0.9 produces identical problem, response contract, representations, and ID; metadata alone changes. | The requested challenge level does not necessarily change the task. | CON-011 through CON-013; family matrix |

The implementation outcome is a question system in which a learner can understand the task, give an ordinary correct response, trust the result, learn from an error, encounter genuinely different problems, and recognize why a later task is harder. The chapter does not claim any resulting change in general intelligence or externally validated psychometric performance.

## 2. The authoritative exercise contract

<a id="con-001"></a>

### CON-001 — One contract must drive generation, rendering, validation, and explanation

Replace the implicit relationship between strings, answer keys, and metadata with an explicit authoritative contract. Retain adapters to `NFExercise` and `NFExerciseInteraction` during migration; do not require a simultaneous rewrite of every screen. The new contract must be able to serialize and round-trip the following fields without losing meaning.

| Field group | Required content | Consumer and invariant |
|---|---|---|
| Identity | `semanticProblemID`, `semanticFingerprint`, `contractRevision`, `familyID`, `objectiveID`, `structureID`, `generatorVersion`, canonical parameters, content-edition ID | Novelty is tied to the problem, not a display UUID, option order, language, or difficulty label. |
| Task | Plain-language question, requested deliverable, essential givens, assumptions, domain restrictions, answer format, units | The question is answerable from the intended prerequisites plus these givens. |
| Objective | One primary operation; optional explicitly weighted subordinate operations; prerequisite concept IDs | A workflow or confidence exercise cannot silently become evidence that an unrelated fact was recalled. |
| Representations | Structured table/chart/geometry/code/equation data; role of each representation; accessible equivalent | All visible claims, summaries, and accessible descriptions derive from the same underlying data. |
| Answer authority | One of the eight response contracts, semantic alternatives, forbidden assertions, partial-credit policy, independently verified reference | Rendering does not invent an answer; scoring does not infer authority from display text. |
| Assistance | Essential givens, optional hint stages, worked solution, reference material, allowed teaching modes | Solution-bearing material is unavailable before an independent response. |
| Difficulty intent | `editorialBand` B1–B4, `demandVector`, prerequisite demands, named parameter bounds, reason for each demand | A level describes actual task demands and is separately identified from empirical difficulty estimates. |
| Feedback | Correct reasoning, shortest decisive step, misconception-specific explanation, next attempt recommendation | Explanations must be true for the actual parameters and learner response. |
| Provenance | Author/reviewer IDs, review date, source references when needed, generator/oracle versions, verification record | A future content audit can reproduce what was approved and why. |
| Delivery | Eligible modes, `independentEligible`, `protectedEligible`, compatible response forms, time eligibility, novelty relationship, required assets, locale support | Unsupported forms and missing assets are excluded before reservation. |

A suggested implementation shape is a versioned `NFExerciseContract` containing a discriminated `NFAuthoritativeResponseContract`, an `NFStimulusModel`, and `NFContentReviewRecord`. These names are proposed types, not assertions about existing APIs. Prefer typed values and enums to adding more magic strings to tags. `NFExercise` may initially remain the rendered/session object produced from that contract.

<a id="con-002"></a>

### CON-002 — Parameters must be generated before prose

Generation must follow this order: select an eligible family and demand specification; draw bounded substantive parameters; derive the stimulus model; derive the answer with an independent or independently checked method; construct and validate alternatives; select compatible representations; render localized task text; validate the complete item. A rejected candidate must never reach a session. The seed and generator version must reproduce the rejection as well as valid outputs.

For finite small domains, release tooling must enumerate the whole domain. For larger domains, it must enumerate all boundary partitions and run a deterministic property sweep. “The canonical answer scored as correct” is necessary but cannot replace independent truth checks. Calculation chains must have an independent arithmetic oracle; cube nets must be checked by geometric folding rather than a hand-maintained opposite-face list; logical patches must be executed by the restricted interpreter against the contract's test inputs.

<a id="con-003"></a>

### CON-003 — Generation failure must remain a content failure

A runtime content error must produce a replacement reservation or a clear inability to continue, never an incorrect score for the learner. Keep a reason such as `duplicateAnswer`, `noValidInterpretation`, `missingAsset`, `unsupportedLocale`, `oracleMismatch`, or `ungradableResponseContract`. Record the content edition, family, seed, and contract revision. Do not include imported private document text in a general diagnostics log. A repeated failing family is quarantined for the current session; the reservation rules in section 6 determine what can replace it.

<a id="con-004"></a>

### CON-004 — Every representation needs a declared instructional role

Use four roles: `essentialGiven`, `optionalPracticeHint`, `postResponseReference`, and `workedExample`. An independent item may initially render only essential givens. An assisted-practice item may expose an explicit requested hint, which records assistance without changing the original submitted response. A teaching example may show all roles and must not record an unaided performance result. A picture or equation cannot evade this rule by being stored in a different field.

The counterexample `2×3=6`, the conclusion “the divisor is zero,” and a fully stated best experiment are post-response reasoning or teaching scaffolds when the question asks the learner to derive them. They are not essential givens merely because they are useful to read. A domain restriction such as `a=b≠0`, by contrast, is an essential given.

<a id="con-005"></a>

### CON-005 — An item must state what is being judged

The contract must identify whether it judges a final value, exact representation, method, explanation, uncertainty interpretation, minimal counterexample, or a set of simultaneous criteria. Instructions must not request three deliverables when the scorer grades one. Do not ask “estimate” while silently requiring one exact string. Do not ask “which experiment?” while grading the order of generic study steps. If more than one answer is valid, encode the alternatives or change the task.

## 3. Correctness, ambiguity, and content quality

<a id="con-006"></a>

### CON-006 — Every selectable alternative must be semantically distinct

Before shuffling, canonicalize every option under the response domain. Coordinate choices use typed tuples, numerical choices use exact quantities, formulas use the restricted symbolic equivalence checker, and prose choices use editorial equivalence annotations plus a duplicate-text check. Reject any distractor equivalent to an accepted answer or another distractor. Unique IDs are insufficient.

For coordinate rotation, the generator may keep a valid symmetric input such as `(10,10)` and generate a different misconception-based distractor; it need not exclude symmetric points. Candidate distractor transforms include clockwise rotation, origin reflection, or unchanged input, but each actual result must be rechecked because transformations can coincide on axes or the origin. If the number of distinct meaningful alternatives falls below the required count, reduce the declared choice count where allowed or reject that parameter set. Never keep an indistinguishable option and score by its hidden ID.

<a id="con-007"></a>

### CON-007 — Statistical interpretations must follow the estimand and procedure

Replace the current generic “overlapping uncertainty prevents a definitive effect claim” rule. An interval-bearing task must declare the quantity being estimated, interval type, level if applicable, sampling/design assumptions, and whether the question is descriptive, inferential, or causal. If that information is intentionally missing, “the interval type/procedure is unspecified” must be a supported limitation; do not infer its meaning.

The interval object must store endpoints numerically. `overlap` is a derived geometric fact: closed intervals overlap when the maximum lower endpoint is no greater than the minimum upper endpoint. Touching at an endpoint is recorded separately from positive-length overlap for explanatory precision. This flag must not itself determine statistical significance, causal identification, or equivalence. Comparing two individual confidence intervals is not a substitute for analyzing the difference of interest. [Altman and Bland, *Interaction revisited: the difference between two estimates*](https://www.bmj.com/content/326/7382/219) explicitly discusses the mistake of interpreting overlap as proof of a nonsignificant difference.

For an inference about a mean difference, either provide a reviewed interval for that difference or provide the data and a fully specified supported calculation. Its interpretation depends on that procedure. Failure to exclude zero does not establish equality; exclusion of zero does not establish practical importance or causation. A causal conclusion additionally needs a defensible assignment/design argument. A randomized study can still have a limited target population. A plot of observational group means cannot answer every one of these questions.

A generated raw dataset, displayed mean, interval, narrative, answer key, and accessible description must agree. If intervals are deliberately supplied independently of the raw dataset for an elementary reading task, explicitly identify them as supplied model summaries and do not imply that the displayed observations generated those intervals. Prefer computing all summaries from the same reviewed dataset and method.

<a id="con-008"></a>

### CON-008 — No pre-answer solution leakage in independent modes

A release test must generate every family in each protected purpose and inspect both visual and accessible content roles. It must fail if a hidden answer is repeated in a pre-answer caption, graph summary, equation, hint, alt text, source citation excerpt, table heading, or placeholder. Accessibility needs equivalent information, not a more revealing solution. Removing a necessary graph description is also unacceptable: accessible stimuli must preserve the task while describing essential data.

<a id="con-009"></a>

### CON-009 — Distractors must express plausible errors

Each distractor must have an authored misconception ID and a one-sentence explanation of why that error produces this specific alternative. Generic “always,” “ignore the evidence,” or obviously unrelated text is insufficient for a mature question bank. For a time-unit question, distractors should be comparable units such as minute, hour, or day under a clearly stated SI-base-unit question, not three paragraphs about reversed relationships. For an experimental design item, rival options should each fix some limitations while failing the decisive one.

Correct options must not be identifiable by consistently being longer, more qualified, grammatically compatible, more technical, or the only option containing numbers. These properties are lint warnings for editorial review, not a reason to distort naturally necessary wording. The release record must document any exception.

<a id="con-010"></a>

### CON-010 — A response form must perform the operation its name promises

Cloze requires a real omitted element with enough context to make the omission resolvable. Equation reconstruction requires a specific equation with a meaningful slot. Figure interpretation requires a figure or structured data whose content matters to the answer. Code tracing requires inputs and control flow that determine an output. Paper Sprint requires an actual bounded abstract. A repair-cycle task must involve an actual response discrepancy and a target-specific retry, or be explicitly classified as learning-method practice with no credit for the knowledge target.

A target must declare `compatibleRenderings`; unsupported renderings are unavailable rather than synthesized as generic `E_source+C_stated→□` text. Generating a new rendering does not create a new knowledge target.

<a id="con-011"></a>

### CON-011 — Editorial difficulty must be based on real demands

Define four initial editorial bands: **B1 Foundation**, **B2 Developing**, **B3 Challenging**, and **B4 Advanced within this family**. These are intended demand categories, not percent-correct predictions or psychometric thresholds. Each family must specify actual changes in at least one of: number of dependent steps, number of relevant variables, prerequisite concepts, representation conversion, distractor similarity, uncertainty to resolve, size of the search space, or amount of scaffolding. The family matrix in section 9 supplies the required starting definitions.

Do not increase difficulty solely by adding a long story, awkward numbers, tiny controls, unfamiliar vocabulary unrelated to the target, or time pressure. Larger arithmetic may be a legitimate demand in an arithmetic family, but must not be used as the primary difficulty control in a causal-reasoning question. All levels retain readable language and accessible representations.

<a id="con-012"></a>

### CON-012 — Difficulty requests must select valid demand specifications

The adaptation layer supplies an intended level/demand request and relevant prerequisites. The content layer must return the selected actual demand vector and a reason if the request cannot be met. It must never label an unchanged exercise “advanced” simply by replacing `difficulty.overall`. Same seed plus different demand specifications should produce a predictably different contract where substantive content differs; if the request maps to the same supported demand bin, report the same level honestly.

Protected difficulty equivalence across alternate forms requires explicit review. A short recognition item is not automatically equivalent to free recall of the same relationship. Maintain empirical statistics separately by format, assistance, context, and level until evidence supports aggregation.

<a id="con-013"></a>

### CON-013 — Editorial and empirical difficulty must remain separate

Store `editorialBand` and `demandVector` independently from `empiricalDifficultyEstimate`, `calibrationStatus`, calibration version, sample size, eligibility rules, uncertainty, and model version. No value in this chapter is an externally validated item parameter. The proposed quotas, level labels, score weights, and parser limits are engineering or editorial decisions that require evaluation. Low observed success can indicate a bad question, input friction, or missing prerequisites as well as genuine challenge. Item difficulty updates must not silently rewrite historical contracts.

## 4. Scoring authority and result semantics

<a id="sco-001"></a>

### SCO-001 — Correctness and credit must be consistent

A fully accepted authoritative response must have `isCorrect=true` and `credit=1`. An accepted equivalent is not partial knowledge. A partial response must have `isCorrect=false`, a declared partial-credit basis, and component results explaining the missing or contradictory parts. An incorrect response has `isCorrect=false` and credit zero unless the declared rubric deliberately awards component credit. A skipped, unsubmitted, invalid-item, ungradable, or self-reported response must not be encoded as an objective incorrect/correct binary.

Introduce a versioned outcome distinction equivalent to `correct`, `partial`, `incorrect`, `needsClarification`, `selfReported`, `skipped`, and `invalidItem`. The state chapter owns the persistence representation. Existing boolean/credit fields may be adapter outputs, but they cannot erase the distinction from new records. `needsClarification` means the submitted notation cannot be interpreted safely; it is not a euphemism for a confidently wrong answer.

<a id="sco-002"></a>

### SCO-002 — Scoring must produce an inspectable component result

For each component store the submitted value, parsed value when applicable, applicable rule version, outcome, awarded/max credit, misconception code if supported, and a learner-safe explanation. Preserve the original response alongside normalized interpretation. Feedback must not claim a specific misconception solely because an arbitrary wrong number matches no known case; use “Recheck the conversion” unless there is diagnostic evidence for a direction or scale error.

Scoring must be deterministic and side-effect free for a given contract revision and response. It must not change with device locale, network/model availability, option order, app theme, or elapsed time. A time-based statistic is separately derived from a valid timing contract. A post-answer diagnostic retry never overwrites the original attempt.

<a id="sco-003"></a>

### SCO-003 — Parsing policy must follow the answer domain

Replace a single universal text normalizer with explicit domains: natural-language phrases, exact numbers, fixed-unit quantities, unrestricted-unit quantities within an allowed dimensional family, identifiers, symbolic expressions, coordinate tuples, ordered labels, and booleans. Case folding is acceptable for ordinary English prose and some reviewed textual aliases. It is not generally safe for variables, named functions, units, chemical symbols, or source-code identifiers.

Parsing stages are lexical normalization, syntactic parsing, domain validation, semantic equivalence, and rubric evaluation. Reject unsupported syntax before equivalence. Do not execute user text. Do not silently drop operators, exponents, grouping, signs, decimal points, primes, or unit prefixes. Preserve the complete parse and interpretation for feedback when notation could be surprising.

<a id="sco-004"></a>

### SCO-004 — The eight response types remain the stable surface contract

The following rules cover the existing `numeric`, `singleChoice`, `multipleChoice`, `orderedSteps`, `shortText`, `selfCheck`, `claimEvidence`, and `logicState` enum cases. More specialized typed contracts may be carried inside these cases or introduced by a versioned adapter; this chapter does not require proliferating interaction types merely to fix grading.

| Existing type | Accepted example | Rejected or non-objective example | Required interpretation |
|---|---|---|---|
| Numeric | EX-C01: for 1,250 mm in a field labeled metres, `1.25`, `1.250`, `5/4`, or `1.25e0` | `1250`, `1.25 cm`, `1/0`; uninterpretable `1,25` under an ambiguous locale policy requests clarification | Exact numeric value plus declared unit/representation policy. |
| Single choice | EX-C02: select the unique option representing a 90° counterclockwise rotation of `(10,10)`, namely `(-10,10)` | An equivalent duplicate option is a content error, never a learner error | Options validated semantically before ID-based selection scoring. |
| Multiple choice | EX-C03: when A and C are the two safeguards, select exactly A and C | Selecting A, C, and “remove inconvenient outcomes” is not fully correct | Exact set for full credit; explicit optional partial rule. |
| Ordered steps | EX-C04: a proof follows all declared dependency edges; two independent preparation steps may be swapped | A conclusion preceding a required derivation violates its edge | All valid topological orders accepted when order is partial. |
| Short text | EX-C05: “Sum all observations then divide by their count” for arithmetic mean; `4x` for derivative of `2x²` | “Divide the count by the sum”; `f(b)-f(a)` when F is the required antiderivative | Prose and symbolic subcontracts use separate authority. |
| Self-check | EX-C06: learner recalls, reveals, then records “partly matched” with a specific omitted condition | Clicking “matched” is not independently verified objective correctness | Self-reported reflection and exposure only. |
| Claim/evidence | EX-C07: attach group means to an observed-difference claim and assignment information to a causal-limit claim | A larger observed mean alone supporting “treatment caused every increase” | Satisfy declared support constraints without unsupported edges. |
| Logic/state | EX-C08: final typed state `count=9`, `ready=true`, violated invariant `readyMatchesCount` | `count=9`, `ready=false`; an accepted alias yielding partial credit | Per-field domain parsing and full credit for accepted equivalent states. |

<a id="sco-005"></a>

### SCO-005 — Numeric responses require exact and approximate contracts

Use the existing exact-rational machinery as the preferred authority for integers, terminating decimals, rational arithmetic, proportions, and exact unit conversions. A displayed decimal approximation must not silently replace an exact rational key. For a task explicitly requiring a rounded answer, define the rounding rule and precision, then judge that deliverable. For an approximation task, define the accepted interval numerically, including boundary inclusivity, instead of a handful of strings.

EX-C01 asks: “Convert 1,250 millimetres to metres.” The response control visibly supplies `m`. Accept `1.25`, `1.250`, `5/4`, and `1.25e0`; preserve the learner's original notation. Reject `1250` as a value error. If the learner explicitly submits `125 cm`, the quantity is equivalent but the requested representation is not metres: return a representation component error if that is an assessed objective, otherwise convert and explain according to the contract's predeclared mode. Do not decide after seeing the answer.

Reject NaN, infinity unless explicitly meaningful in a separately reviewed domain, denominator zero, overflow, impossible unit combinations, and expressions outside the allowed grammar. Percentages distinguish a probability from a percentage: `0.25` in a probability field and `25` in a percent field can denote the same ratio, but `0.25%` does not equal `25%`. Negative zero normalizes to zero unless signed zero is explicitly part of an advanced computing objective.

<a id="sco-006"></a>

### SCO-006 — Single-choice scoring requires a unique semantic answer

After CON-006 validates the options, selected option ID may identify the selected semantic value. Unknown/stale option IDs are invalid responses and must not crash or select a default. Duplicate display text, equivalent formula answers, and multiple defensible prose choices invalidate the item before presentation. If a previously shipped duplicate is discovered during a session, suppress objective scoring and replace the item; do not force the learner to guess an internal ID.

<a id="sco-007"></a>

### SCO-007 — Multiple-choice credit must be explicit and resistant to selecting everything

Full credit requires exactly the accepted set, or one of the explicitly accepted alternative sets. The default for independent assessment is exact-set grading. If a practice task declares equal-weight component credit, use `max(0, (correctSelections − incorrectSelections) / requiredSelections)` with a maximum of 1; this is a proposed transparent instructional rule, not a validated ability model. The rule must not be used when the number or cost of wrong actions makes equal weights inappropriate.

For EX-C03 with two correct and two incorrect options: A+C earns 1; A earns 0.5 only in a partial-credit practice contract; A+C+one incorrect earns 0.5; selecting all four earns 0. Exact-set mode awards zero for all but A+C. Feedback identifies every missed safeguard and every harmful selected action. Do not show “correct” for a partially completed set.

<a id="sco-008"></a>

### SCO-008 — Ordered steps must represent dependency rather than stylistic preference

Add an ordering authority capable of a single order or a dependency DAG. Full credit requires all required nodes exactly once and every required edge satisfied. For a graph with independent A and B both preceding C, A-B-C and B-A-C are accepted. Repeated/missing/unknown steps cannot receive full credit. Detect cycles in authored graphs as a release error.

If partial credit is permitted, score the fraction of required dependency edges satisfied, with separate mandatory completeness validation. When the graph has no edges, every complete permutation is correct; do not divide by zero or invent positional penalties. Do not award a nearly full score to a response that omits the decisive step merely because remaining nodes are conveniently positioned. For a strict algebraic proof, the dependency graph may legitimately reduce to one chain. A generic preferred reading order is a learning strategy exercise; it must not be presented as a uniquely valid theorem about how all experts read papers.

<a id="sco-009"></a>

### SCO-009 — Short text must declare its supported interpretation

Use exact normalized aliases for constrained labels such as “independent variable,” explicit identifier parsing for code names, typed mathematical parsing for formulas, and reviewed concept criteria for short explanations. A 280-character limit may remain for concise responses, but it is a UI limit and cannot justify truncating input silently. Validate the length before commitment; preserve the complete original until the learner edits it.

For ordinary explanatory prose, explicitly approved paraphrases receive objective credit. A response outside the deterministic coverage must either be evaluated by a reviewed constrained rubric whose limitations are known or be marked “needs review/self-check,” without a false objective wrong score. Unbounded model-generated judgments may offer coaching, but cannot silently become authoritative scoring for protected evidence. The product must clearly separate a model suggestion from the local verified result.

<a id="sco-010"></a>

### SCO-010 — Restricted symbolic equivalence must preserve symbol roles

Initially support rational coefficients, declared variables, addition, subtraction, multiplication, division, parentheses, and bounded integer powers for families whose mathematics falls inside that grammar. Treat implicit multiplication (`2x`), explicit multiplication (`2*x`), and the multiplication glyph (`2×x`) as equivalent when the tokenization is unambiguous. Normalize `x^1` to `x` and multiply exact rational coefficients. Accept `4x`, `4*x`, and `2x+2x` for the derivative of `2x²` on its stated real domain.

The contract must provide a symbol table. For EX-C05b, `F` is a named antiderivative function and `f` is the integrand; they are distinct. Function application `F(b)` is not multiplication `F*b`. Prime notation must refer to a declared derivative relation and cannot be stripped as punctuation. Coordinate labels and dummy variables may be renamed only when the contract declares an alpha-equivalence rule; never infer that all letters differing only in case are synonyms.

Use canonical exact polynomial normalization when applicable. For rational functions, compare only within declared domain restrictions and preserve exclusions: `(x²−1)/(x−1)` is not an unrestricted replacement for `x+1` when the original domain excludes x=1. Cross-multiplication alone must not accept an expression where denominators introduce or erase forbidden values. If the parser cannot prove equivalence within the supported domain, request clarification or self-check rather than guessing from a few sampled numerical points.

<a id="sco-011"></a>

### SCO-011 — Symbolic processing must have bounded complexity

Proposed initial implementation limits: 256 lexical tokens, nesting depth 32, at most 16 declared symbols, integer exponents from −12 through 12, and a maximum of 2,048 expanded polynomial terms. These are resource limits for a local parser and must be configurable/versioned; they are not learner difficulty parameters. Stop safely at a limit and explain the supported notation without recording an incorrect conceptual answer. Never evaluate arbitrary Swift, JavaScript, Python, shell commands, or imported code.

Trigonometric identities, arbitrary derivatives, matrix algebra, chemical formulas, and proof equivalence require separate reviewed domain modules. Do not advertise universal algebra equivalence based on the initial polynomial parser. Unit symbols have their own registry and case rules: metre `m` and a prefix/unit symbol `M` cannot be case-folded into the same token.

<a id="sco-012"></a>

### SCO-012 — Prose grading must preserve direction, conditions, and negation

For the arithmetic-mean objective, accepted concept coverage requires an additive total of the relevant observations and division by their count. “Sum observations / number of observations” passes. “Divide the count by the total” fails because direction is reversed. “Do not divide by the count” fails despite containing every keyword. “Add all values and divide by how many values there are; this works because each observation contributes once” passes. A response that includes the correct method and then asserts its negation cannot receive full credit.

A constrained rubric must define required concepts, accepted relation paraphrases, mandatory qualifiers, explicit contradictions, and examples just outside its coverage. Keyword presence alone is insufficient. When robust deterministic relation interpretation is unavailable for an objective, use constrained structured answers or honest self-check rather than pretending a small synonym list covers unrestricted language. Allow the learner to report a grading issue without forcing them to label their valid answer wrong.

<a id="sco-013"></a>

### SCO-013 — Retrieval computations must use computational response contracts

The 800 computed retrieval instances should stop using exact prose strings as their primary arithmetic authority. Attach a typed quantity, formula, coordinate, sequence, or discrete result contract. The knowledge target remains the learned relationship being retrieved; a correct computed answer may provide evidence for applying that relationship, while a recognition answer must retain its weaker response-form identity. A binary numeral may include leading zeroes unless a fixed-width/minimal-width instruction says otherwise. A unit already fixed by the response control need not be retyped.

<a id="sco-014"></a>

### SCO-014 — Self-check must be honest about its authority

The learner must attempt recall before revealing the reference. The app then shows a checklist tied to that target, not generic criteria such as “names the central idea” for every question. EX-C06 on the median must distinguish ordering, odd count, and averaging the two central observations for an even count. “Matched,” “partly matched,” and “not yet” are self-reports; do not encode “matched” as an objectively correct response or include it in verified accuracy.

Store reveal time, whether a pre-reveal attempt occurred, checklist selections, the self-rating, and optional reflection. Do not require lengthy reflection on every successful recall. A closed-reference retry can be offered as a new linked attempt. It cannot overwrite the first response or convert an assisted attempt into unaided success. A rating made without attempting recall is a review exposure, not recall evidence.

<a id="sco-015"></a>

### SCO-015 — Composite and state answers must grade typed components

Stop grading estimate/plausibility/exact tasks as opaque dictionaries of literal strings. Each response field has its own domain, accepted equivalents, mandatory/optional status, and weight. A whole accepted equivalent state receives full credit regardless of whether it matches the canonical spelling. A state task can use integer, rational, Boolean, enum, and declared identifier fields. Boolean text aliases such as `true` and `True` may be accepted under an explicit Boolean parser; source-code identifiers remain case-sensitive.

For EX-C08, starting at count 10 and ready false, execute `count -= 3`, set ready from `count <= 7`, then `count += 2` without recomputation. The final state is count 9, ready true; the invariant “ready equals count<=7” is violated. In a practice rubric assigning state 0.8 and invariant 0.2, both state fields correct plus the right invariant earns 1; both fields correct plus a wrong invariant earns 0.8. If state component weights differ, declare them. An accepted Boolean alias must not lower credit.

<a id="sco-016"></a>

### SCO-016 — Estimates and units require explicit semantic policies

Define `estimateMode` as one of nearest specified unit, nearest specified significant digit count, nearest power of ten, bounded practical estimate, or assumption-derived range. State the chosen task in learner language. For “nearest power of ten” of 198×48, 10,000 is the target. For “give a useful approximate product,” a reasonable declared range such as 9,000–11,000 may be chosen editorially for that task; it is not a scientifically universal tolerance and must be reviewed against the objective. Exact product 9,504 is not conceptually wrong merely because it is precise; the task may separately assess whether a preliminary estimate was recorded before exact work.

The plausibility control should represent a typed judgment such as plausible / too small / too large with an optional reason. It must compare the learner's own estimate and exact result under a defined rule, not always key “yes” independently of what they entered. If the estimate is 100 and the exact answer 9,504, “plausible” is not correct even though it is the canonical word in another generated item.

A quantity contract declares whether the unit is supplied by the control, must be chosen, may be freely equivalent, or must match a requested representation. Prefixes, dimensional conversions, and significant-figure requirements are separate objectives. Locale parsing must be deterministic and explained when separators are ambiguous; do not silently interpret `1,250` differently between the displayed problem and submission. A locked metres suffix and an accessible “answer in metres” label eliminate avoidable unit-entry friction for simple conversions.

<a id="sco-017"></a>

### SCO-017 — Claim/evidence tasks must encode support constraints

A claim may require one evidence item, all items in a necessary bundle, or any one of several sufficient bundles. Encode these explicitly rather than insisting on one arbitrary map. EX-C07: observed group means support the descriptive contrast; convenience assignment supports a warning about baseline comparability; neither supports “every individual benefits.” A statement that restates the claim is not independent evidence merely because it has a different ID.

Full credit requires every claim's support condition and no prohibited unsupported edge. Partial practice credit uses declared claim/component weights and deducts unsupported attachments, with floor zero; “attach everything everywhere” must never be fully correct. Contradictory evidence should be an available category where the task requires it, not forced into “supports” or “ignore.” Feedback must identify the actual missing relationship or scope violation. Unknown/deleted evidence IDs are invalid submissions, not evidence of reasoning failure.

<a id="sco-018"></a>

### SCO-018 — Feedback and replay must preserve the original result

The first feedback sentence must say what happened in ordinary language: “Correct — 46×19 is 874,” “Your estimate is reasonable; recheck the exact multiplication,” or “I could not interpret that formula; use `*` for multiplication.” It must not call every correct answer “Supported” or every mistake “Revisit the decisive step.” The next sentence explains the shortest useful reason. Expandable detail may show alternatives and a worked solution.

A diagnostic trace, second attempt, or appeal can add a linked result. It cannot mutate the original answer or scoring version. Correcting a bad question at release time requires a separately governed historical correction decision; the UI must not silently revise yesterday's evidence. The application/state chapter specifies the migration and correction records.

## 5. Content identity, versioning, and editorial governance

<a id="con-020"></a>

### CON-020 — Separate identity layers and exposure relationships

Use `objectiveID` for the thing being learned, `familyID` for the generating activity, and `structureID` for its substantive reasoning pattern. A `semanticProblemID` identifies one substantive problem with specific givens and an authoritative response relation. `semanticFingerprint` is a reproducible digest of its canonical semantic contract. `contractRevision` identifies a change to that authority. Display-instance IDs identify presentations and reservations, not new questions.

A translation, font, option order, animation, surface noun substitution, pseudocode display skin, newly generated UUID, or changed difficulty label does not create semantic novelty. A changed substantive given and answer can create a new problem instance, but it still shares its structure and objective. Rewording `46×19` as 46 sensors with 19 readings each does not create an unseen mathematical structure. The adaptation layer can distinguish instance exposure from structure exposure using these fields.

For retrieval, the knowledge target identity survives different response forms. A single fact seen in recognition and then recalled is one knowledge target with two differently qualified attempts. A new computed instance can have a distinct problem identity when its essential givens and required answer genuinely change; it still belongs to the same knowledge relationship and calculation structure. The bank must not count nine renderings as nine additional knowledge contracts.

<a id="con-021"></a>

### CON-021 — Version the smallest changed authority and the containing edition

A copy correction that preserves meaning and grading increments a presentation revision. A changed correct answer, accepted-equivalence set, domain restriction, substantive givens, or score rule increments contract revision and the edition's manifest. Changes to generator behavior or candidate admission increment the appropriate generator/bank version. A scoring-policy update increments scoring version even if item wording is unchanged. Historic attempts retain their original references.

A corrected typo must not erase exposure history or present a familiar item as new. A genuinely changed contract must record `supersedes` and its relationship to the old problem: copy-only, answer-authority correction, altered givens, or new structure. A quarantined item must not reappear under a fresh UUID. The state/migration chapter owns how these relationships project into installed ledgers; the content release must supply the mapping.

<a id="con-022"></a>

### CON-022 — The release manifest must cover the actual delivered bank

The current offline bank explicitly leaves signed inventory coverage unset. The replacement release must include the admitted item identities/fingerprints, knowledge-target records, family/structure quotas, response-contract versions, generator version, and content assets in the signed inventory or a reviewed signed exception with an explicit expiry/next-release obligation. A code-signed application alone does not satisfy a separately required content-manifest audit.

Validation must verify that every reserved item resolves inside the installed approved edition and that no changed bank mapping reuses the same edition identity. Missing signature coverage cannot be “fixed” by setting a Boolean or bypassing a gate. The content release process must follow the repository's [ContentSigning.md](../ContentSigning.md), with signing authority outside ordinary runtime generation. Deployment and signing are separate authorized release actions, not part of writing this specification.

<a id="con-023"></a>

### CON-023 — Every family needs an editorial record and an independent reviewer

The record must include the primary objective, prerequisites, approved domains/fields, four band definitions, generator parameter partitions, invalid regions, independent oracle, alternate forms, assistance policy, misconception taxonomy, accepted and rejected examples, sources where factual support matters, and locale/asset support. The reviewer must inspect sampled rendered items as a learner would see them and inspect all critical boundary cases. A reviewer cannot approve a family solely by reading the generator comments or running self-consistency tests.

Factual source records must support the particular claim made, not merely share the topic. Elementary mathematical identities may be independently proved in the review record. Domain-specific facts need an appropriate textbook, primary source, standard, or official reference. Record limitations and assumptions. Avoid questions whose correctness depends on unannounced jurisdiction, rapidly changing product behavior, or personal medical/financial advice in the default general bank.

<a id="con-024"></a>

### CON-024 — Editorial review must evaluate language as part of correctness

Every task must have one short primary question, a clearly labeled deliverable, necessary assumptions, and consistent terminology. Use “observed difference” when that is all the data support; “causal effect” only when the task actually addresses identification. Do not use “source-backed” for a generic bundled statement with no displayed source. Remove implementation language such as “the bounded internal AST is interpreted” from ordinary learner instructions.

English and Japanese releases require equivalent task demands and accepted response support. Translating a question but leaving only English prose answers is incomplete localization. Language difficulty must not unintentionally become a prerequisite for a numeric skill. Content reviewers must inspect line wraps, notation, units, accessible reading order, and whether symbols preserve meaning under localization. The interaction chapter specifies presentation details; the contract must provide accurate localized inputs.

<a id="con-025"></a>

### CON-025 — Feedback must be authored as a learning sequence

For each misconception, provide an immediate explanation, one smallest corrective action, and an optional worked solution. Follow-up practice should vary the essential feature that caused the error while keeping unrelated demands manageable. After correcting a unit-direction error, a second item may reverse the conversion direction rather than merely replace 1,250 with 2,500. After a counterexample error, ask the learner to check premise and conclusion independently, then provide a different universal statement.

A replay or explanation must be optional when the learner was confidently correct and the objective is fluency. Do not require repeated generic “what went wrong?” reflections for correct answers. A wrong response should not trigger a long conceptual lecture unrelated to the actual mistake. Explanations must not claim evidence of a misconception when the response is ambiguous or the parser could not interpret it.

<a id="con-026"></a>

### CON-026 — Metacognitive tasks must not masquerade as subject knowledge

Retrieval Cycle Builder and Confidence Calibration teach learning procedures and judgment. Their success is evidence for those objectives only. A cycle task associated with a chemistry target must include a chemistry retrieval/reconstruction component before it can supply target-specific knowledge evidence. Merely ordering “attempt, compare, locate, retry” is a distinct procedural task. Source-Filter Trace must require the actual supplied source, candidate claims, and filter behavior; a fixed pseudocode return of an obviously correct label is insufficient.

<a id="con-027"></a>

### CON-027 — Content incidents need a reproducible correction path

A learner can report “my answer should be accepted,” “more than one option is correct,” “question unclear,” “fact seems wrong,” or “something else.” Attach edition, semantic ID, contract revision, response/scoring version, locale, and seed. Include private source material only through a separate explicit inclusion choice in the UI. Triage must distinguish input parsing, answer equivalence, key error, ambiguity, missing prerequisite, and feature mismatch.

Confirmed wrong-key or duplicate-answer incidents quarantine the affected contract or parameter region. Review the learner impact and corrected evidence through the state chapter's correction policy. The chapter does not authorize silently deleting past attempts or automatically awarding learning mastery. A quality dashboard must show incident rate with exposure denominator and item revision; raw report count alone overweights popular questions.

## 6. Genuine variety with feasible inventory and no replacement

<a id="con-014"></a>

### CON-014 — Balanced admission must precede balanced delivery

The current first-1,000-unique scan must be replaced by release-time inventory admission with explicit family/structure quotas. At least 1,000 eligible semantic contracts per lab remains the planned offline floor. The system must prove that the inventory can meet the quotas before advertising balanced mixed practice. Reserving many unique numeric variants of one family cannot substitute for creating missing families.

The following are proposed **editorial targets for a new 1,000-item edition**, not statements about current inventory and not psychometrically validated optimal proportions. The exact values are chosen to prevent the observed 98–99% concentration while retaining every catalog family. The quotas must be versioned and inspectable.

| Lab | Proposed admission quotas, in current catalog order | Total | Additional constraint |
|---|---|---:|---|
| Mental Mathematics | 100 for each of its 10 families | 1,000 | At least four substantive structures per family; a structure's number-only variants cannot exceed half that family's quota. |
| Spatial Reasoning | 167 coordinate rotation, 167 object rotation, 167 cross-section, 167 top-view, 166 cube-net, 166 reflection | 1,000 | Different transformations/objects/sections must carry the quota; changing coordinates alone cannot fill object or projection families. |
| Quantitative Intuition | 125 for each of its 8 families | 1,000 | Different probability structures, assumptions, and interval targets required; no more than half of a family's quota from one structure. |
| Scientific Reasoning | 112 Claim–Evidence Bounds; 111 for each of the other 8 families | 1,000 | Every family needs genuine scenarios with substantive design/evidence differences. |
| Logic & Debugging | 112 State Trace; 111 for each of the other 8 families | 1,000 | State Trace cannot dominate by variable substitution; other families need independent claim/program structures. |
| Retrieval Practice | 100 Free Recall, 160 Precision Recall, 140 Cloze, 100 Teach It Back, 120 Recognition Audit, 20 Cycle Builder, 140 Equation Reconstruction, 100 Figure Interpretation, 20 Source-Filter Trace | 1,000 | These are delivery assignments to 1,000 unique target/problem contracts, not 1,000 additional formats; maintain 125 target contracts in each field. |
| Transfer Lab | 143 for its first 6 families; 142 Saturation Check | 1,000 | Each includes both successful transfer and informative limits where appropriate; no more than half a family from one source/target structure pair. |

“Four substantive structures” is a proposed editorial breadth target. It does not mean four renamed settings. For rapid recall, separate multiplication-table facts, division inverses, decimal place-value facts, and signed-number facts only if the activity's objective and prerequisites explicitly support them. If broadening would make an existing activity misleading, create a reviewed successor subfamily or rename the activity with migration mapping rather than expanding it silently.

<a id="con-015"></a>

### CON-015 — Quota feasibility must be checked as a finite assignment problem

A candidate supplies semantic ID, family eligibility, structure, field, band, and compatible renderings. Admit a set satisfying hard uniqueness, content validity, required assets/locales, and declared quotas. For retrieval, the same target may support more than one rendering but may occupy only one slot in the edition's target count. Use a deterministic bipartite matching/min-cost-flow step to assign targets to compatible rendering slots while respecting field totals. Store the resulting assignment in the manifest. Do not assume every field/format/band cross-product exists.

If capacity is insufficient, fail the new edition's admission with an exact deficit report: available valid unique items, required count, and missing compatible assets/structures. The shipping product may continue the last valid approved edition with its limitations described accurately, or release a smaller specifically named practice activity outside the 1,000-item mixed guarantee if the product specification explicitly permits that lane. It must not fabricate novelty, bypass a minimum count, or silently relax a advertised balanced-bank guarantee to make a release pass.

<a id="con-016"></a>

### CON-016 — Per-target novelty and per-rendering variety must be distinguished

A no-replacement retrieval epoch consumes a target/problem identity once, whichever compatible rendering is delivered. It cannot later count the same target as fresh because it changed from free recall to cloze. A deliberate spaced review is permitted in a separate review schedule and is labeled review; it does not reset the mixed bank's novelty cursor. An imported personal fact is not a new standardized item and cannot fill an offline release deficit.

Where a target has only one meaningful form, deliver that form. Where several exist, choose among the approved forms under the mode, assistance, and prerequisite rules, and record the actual form. If the release's rendering quota cannot be realized because only 40 targets contain meaningful equations, it cannot promise 140 Equation Reconstruction assignments until another 100 suitable contracts/assets are authored.

<a id="con-017"></a>

### CON-017 — Separate candidate order from the reservation of an adaptive item

Within each profile/lab/edition/lane, deterministically shuffle admitted unique IDs within family queues and build a balanced whole-epoch **candidate priority order** using nonempty queues, proportional deficit, and seeded tie-breaking. The order is a reproducible inventory recipe, not an immutable list of all questions in an adaptive session. Persist its version/hash and the positions that have actually been reserved/consumed. Eligibility-aware search may bypass ineligible positions without consuming them; a single monotonically advancing cursor is insufficient when bypassed items remain available.

Use two explicit reservation strategies. **Fixed block** quizzes reserve their exact complete form/sequence at accepted launch and retain the existing consumed-on-abandonment behavior. **Adaptive item** sessions reserve and consume exactly one concrete first item in the accepted-launch transaction, before it can be presented. After an answer, permitted override, or explicit replacement, the adaptation layer supplies the next demand request; the content layer selects one eligible unconsumed contract from the remaining inventory, and an atomic transaction reserves/consumes that exact identity before presentation. Each decision has a stable ordinal, reason, selected contract revision, requested/realized band and demand, and reservation ID. Repeated execution of the same decision cannot allocate a second item.

A committed reservation remains consumed even if the learner closes the session before seeing or answering it. Consumption is an inventory event, **not** proof of exposure or performance: record presentation separately when the item is actually displayed. Optional prewarming of at most two possible next candidates is advisory only; it creates no reservation, consumption, exposure, or evidence. Recheck eligibility and identity during the actual transaction. A band override discards advisory candidates and affects the next item. It never regenerates different content or changes difficulty under an already committed semantic identity. Explicitly replacing the current item leaves that reservation consumed, then commits a new exact contract and links the reason; it cannot resurrect the old slot.

Both strategies preserve hard no replacement: concurrent windows cannot commit the same available position; a committed abandoned item is not issued again in that epoch; a session-level exclusion set forbids repeats within the session even across an epoch boundary. The state chapter owns the consumed-position set, decision idempotency, and migration from cursor-only ledgers. The adaptation chapter owns permitted live band changes. A protected form may select only from its approved fixed form or preauthorized adaptive branches; reserving its capacity is not exposure, and the next committed branch/item remains frozen once issued.

Short-block balance is a **soft** target subject to prerequisites, requested band, protected-form rules, invalidations, and remaining unique capacity. A 10-item block cannot include all nine families equally; some eligible families may run out. The hard invariants are truth, eligibility, exact identity, and no replacement. Report the realized mix and any unmet demand so the UI can name the session accurately. A failed content item is consumed/quarantined, never scored against the learner, and replaced only through a new valid reservation.

<a id="con-018"></a>

### CON-018 — Exhaustion fallback must preserve the guarantee it actually has

When a selected narrow activity runs out of unseen valid items, provide an explicit continuation: end the activity, continue with a named related activity, or deliberately review previous items. Do not silently broaden “Cube-Net Puzzle” into coordinate rotation while keeping the original activity title. A review continuation starts a clearly labeled review lane and does not claim unseen items. Its exposure relationship stays linked to the original identities.

For mixed practice, if a preferred family is exhausted but other eligible unseen items remain, select those and record the reason. If all remaining items fail prerequisites, offer the prerequisite route or a review; do not label advanced ineligible material as suitable. If the whole eligible bank is exhausted, show that the set is complete before beginning a new epoch. A new epoch may repeat identities after the boundary policy, but never within a single reserved quiz.

<a id="con-019"></a>

### CON-019 — Epoch boundaries must solve capacity before reserving

For a fixed quiz or adaptive session crossing an epoch, exclude every ID already committed within that session from the next epoch portion. Place the previous epoch's configured tail after other candidate IDs where feasible. For a fixed block, check that enough unique eligible IDs remain to fill the requested block before committing it. For adaptive mode, check capacity for the one requested next item after each demand change. If the requested unique eligible capacity is unavailable, state the unmet demand and offer an eligible next route, a shorter session, or a separate review; never silently lower the band or reuse an identity. Do not enter an unbounded retry loop, reuse a question under a fresh ID, or incorrectly promise a requested count.

Tests must cover a bank whose family queues have sharply unequal capacity, a narrow selected activity, a final partial epoch, a quiz longer than remaining eligible capacity, two simultaneous windows, abandonment before the first answer, invalidated items after reservation, a version upgrade, and a target with multiple renderings. Properties checked are set uniqueness, no duplicate within the quiz, stable reservation identity, truthful realized mix, and finite termination. Runtime family balance cannot be an unconditional assertion when eligibility makes it impossible.

## 7. Seven complete worked examples

These are proposed editorial fixtures with independent arithmetic/logic checks. They are not claims that the current app contains the interactions described. Fixture IDs must remain stable in tests even if learner-facing wording is refined.

### EX-C101 — Mental Mathematics: compensation with a diagnostic retry

**Family:** `mental.compensation`. **Objective:** compute an exact product using a nearby round multiplier and signed compensation. **Band:** B2 Developing. **Prerequisites:** distributivity, multiplication by 10/20, addition/subtraction. **Independent prompt:** “Compute 46×19. Enter the exact result.” Essential representation: `46×19` only. **Key:** 874, independently verified by long multiplication and `46×(20−1)=920−46`.

Accept `874`, `0874`, and an exact expression only if the numeric parser explicitly supports arithmetic expressions for this task; otherwise explain that the field expects the final number before commitment. `874.0` is equal. Reject 920 as omitted compensation, 966 as compensation in the wrong direction, and 864 as an arithmetic error without inventing a misconception unless the work reveals it. Use numeric exact full-credit grading. An optional practice scratchpad can collect “nearby product” and “compensation” but cannot be mandatory in a final-answer fluency mode.

After 920, feedback reads: “46×20 is 920. Because 19 is one less than 20, subtract one group of 46: 874.” A requested hint before answering says “19 is one away from a round number,” records assistance, and does not expose the result. A follow-up `37×21` tests the opposite compensation direction. B1 uses one-digit facts with an explicit decomposition; B3 requires choosing among nearby multipliers; B4 combines two compensations with a reasonableness check. Larger arbitrary integers alone do not establish a new strategy.

**Verification:** exact arithmetic oracle over parameter partitions; sign-of-compensation tests; equivalent numeric spellings; no solution in independent context; submitted error remains unchanged after replay. This fixture maps to SCO-005, CON-004, CON-011, and QA-F02.

### EX-C102 — Spatial Reasoning: a genuine three-dimensional rotation

**Family:** `spatial.object-rotation`. **Objective:** track face identity through a specified object rotation. **Band:** B2 Developing. **Prerequisites:** named axes, quarter-turns, face adjacency. Define a cube centered at the origin with A on +x, B on −x, C on +y, D on −y, E on +z, and F on −z. Essential figure: cube with these face labels, a +z axis arrow, and a 90° counterclockwise arrow **as viewed from +z looking toward the origin**. Prompt: “After this rotation, which labeled face points in the +y direction?”

**Key:** A. A +90° active rotation about +z maps the +x normal to +y. Options A, C, D, E are distinct face identities. D is a direction error, C is failure to rotate, and E confuses the fixed axis. Face identity and normals, not a pre-rendered answer image, supply the oracle. The accessible alternative describes initial face normals and the viewpoint without naming the rotated result.

In teaching mode, the user can drag the cube, reset to the canonical viewpoint, and step through the rotation. In independent mode, the allowed interaction must not reveal the target orientation by performing the exact requested transform automatically. A post-response replay animates the transform and highlights the source face. B3 composes rotations about different axes; B4 compares unfamiliar asymmetric solids with explicit orientation constraints. Every transformation must preserve lengths, adjacency, and proper-rotation handedness; a mirror image is not a rotation.

**Verification:** rotation matrix/orientation oracle; full set of cube orientations; reversal/viewpoint cases; equivalent options rejected; hidden labels do not leak via accessibility; visual depiction matches stated active rotation. Maps to CON-006, CON-010, SCO-006, QA-F12.

### EX-C103 — Quantitative Intuition: Bayes through counts

**Family:** `quantitative.bayes`. **Objective:** condition on all positive results rather than all cases. **Band:** B2 Developing. **Prerequisites:** proportions, percentages, two-way tables. Use a synthetic manufacturing setting, not individualized diagnostic advice. Prompt: “Among 1,000 components, 100 have a defect. A screen flags 80 of those 100 and also flags 90 of the 900 components without a defect. Of the flagged components, what percentage have a defect? Give one decimal place.”

**Key:** `100×80/(80+90)=800/17≈47.0588%`, rounded to 47.1%. Essential table: defective flagged 80, defective unflagged 20, nondefective flagged 90, nondefective unflagged 810. The answer field supplies `%`. Accept `47.1`; if the specified response is one decimal place, `47.0588` can trigger a pre-commit rounding clarification or a separately declared representation component, not an arbitrary wrong-value verdict. Do not accept 80%, 8%, or 10% as numerically equivalent.

After 80%, explain that 80/100 is the screen's hit rate among defective components, whereas the question asks about the flagged group of 170. A practice interaction highlights the conditioning group only after a hint request or answer. B1 uses a fully assembled count table; B3 derives counts from rates and a rare base rate; B4 compares two screening policies with explicit costs and uncertainty while preserving the same conditional-probability target.

**Verification:** all table cells nonnegative, totals reconcile, denominators nonzero, numeric rational key and rounding agree, no medical framing, and accessible table totals do not substitute the answer for the task. Maps to SCO-005, SCO-016, QA-F21.

### EX-C104 — Scientific Reasoning: separate interval geometry, inference, and causality

**Family:** `science.figure-uncertainty`. **Objective:** choose a conclusion matching the measured contrast, its stated analysis, and study design. **Band:** B3 Challenging. Prompt: “In an observational comparison, group A has mean 21 and group B mean 32. The separate 95% confidence intervals for the means are [16,26] and [25,39]. The report supplies a 95% confidence interval of [2,20] for the mean difference B−A, calculated under its stated comparison model. Participants chose their group. Which conclusion is supported?”

**Key:** “B has the higher observed mean. The supplied interval for B−A excludes zero under the reported analysis, but self-selection prevents this result alone from establishing a causal treatment effect.” Distinguish three components: observed difference 11; difference-interval interpretation; assignment limitation. The individual mean intervals overlap, yet the supplied difference interval excludes zero. The task explicitly avoids the shortcut that overlap means nonsignificance.

Distractors: “The means must be equal because their intervals overlap”; “The result proves every participant benefits from B”; “The interval for B−A means 95% of individual outcomes fall between 2 and 20.” Each has one documented inferential error. Do not assert the supplied intervals were calculated from an accompanying raw dataset unless a consistent dataset and method are actually supplied. A simpler B1 fixture asks only whether two stated intervals overlap, with no significance inference. A B2 fixture interprets a difference interval crossing zero without calling that proof of equality. A B4 fixture compares randomized and observational designs with missingness or model sensitivity supplied explicitly.

**Verification:** numerical contrast; overlap predicate independent of inferential key; interval type and estimand shown; one correct choice; causal qualifiers preserved in feedback and accessible summaries. Regression seed 8424208090942894707 must either be regenerated with coherent claims or removed with an identity correction record. Maps to CON-007, CON-008, SCO-006, QA-S02, QA-F28.

### EX-C105 — Logic & Debugging: inspect a real stale-state defect

**Family:** `logic.state-trace`. **Objective:** distinguish stored state from a recomputed predicate. **Band:** B2 Developing. Initial state: count=10, ready=false. Rule: ready must equal `(count<=7)` at the end of each completed update operation. Program: decrement count by 3; set ready to `(count<=7)`; increment count by 2 without updating ready. Prompt: “After the final operation, enter count and ready, then identify the violated end-state rule.”

**Key:** count=9, ready=true; readiness rule violated. The nonnegative-count rule is not violated. The program is run by the existing restricted interpreter using typed AST values. The visible code is rendered from that AST so Python-like, Swift-like, or neutral displays cannot disagree with the oracle. Clarify that the rule is checked after completed update operations; do not ambiguously claim it was first violated at a transient internal expression step.

Accept reviewed Boolean aliases without changing score. After a wrong `ready=false`, the trace replay shows that no assignment changed ready after it was set true; it does not rewrite the original response. A repair follow-up asks the learner to choose or construct a bounded patch and run it against empty/edge/typical states. B3 adds a branch where the stale state appears only for some inputs; B4 asks for the smallest counterexample or invariant-preserving patch across an explicitly finite domain.

**Verification:** independent interpreter execution; typed per-field grading; invariant timing; alternate display skins share semantics; solution absent before submission; correct equivalent states receive 1. Maps to SCO-015, CON-025, QA-S05, QA-F34.

### EX-C106 — Retrieval Practice: recall the median without wording traps

**Family:** `retrieval.precision-recall` or `retrieval.teach-back`, depending on the explicit response mode. **Objective:** retrieve the ordered-data median rule including the even-count case. **Band:** B2 Developing. Prompt: “How do you find the median of an ordered list when the number of values is odd, and when it is even?” Reference: “For an odd count, take the middle value. For an even count, average the two middle values.”

For a constrained structured precision response, use two fields with reviewed concepts: odd-count rule and even-count rule. Accept “middle observation” and “mean of the two central observations.” Reject “take the middle value in both cases.” For unrestricted teach-back prose, collect an attempted explanation and then self-check against the two explicit criteria; do not award objective accuracy from a keyword matcher. If a deterministic grader cannot safely recognize “For odd n take the central observation; for even n average the middle pair,” it should route to honest comparison rather than mark it wrong.

The same target can later be revisited using a concrete ordered list such as `[2,4,7,9]`, whose median is 5.5, but that item records its relationship to the same rule. Recognition options, if used, contain plausible competing methods: central pair mean, lower central value, higher central value, mean of all observations. A new rendering alone is not a new target. B3 mixes ordering and parity decisions; B4 asks which transformation preserves or changes a median with a counterexample. Those are different demand contracts tied to the relationship, not mere rephrasing.

**Verification:** odd/even finite datasets; correct paraphrases and negations; self-check authority; recall before reference reveal; target identity retained across forms. Maps to SCO-009, SCO-012, SCO-014, CON-016, QA-F44.

### EX-C107 — Transfer Lab: identify where a familiar rate rule stops working

**Family:** `transfer.saturation` with a linked `transfer.rate` foundation. **Objective:** map accumulation structure and recheck a capacity constraint. **Band:** B3 Challenging. Source example: a printer produces 12 labels per minute for 5 minutes, giving 60 labels. Target: a reservoir begins empty, water enters at 12 litres per minute for 5 minutes, the reservoir holds 40 litres, and overflow is not retained. Prompt: “How much water is retained after 5 minutes, and which source assumption must change?”

**Key:** 40 litres retained; unconstrained accumulation/absence of a capacity limit does not hold. The inflow total is 60 litres and overflow is 20 litres. The deliverable is retained volume, not delivered volume. A two-component practice rubric can award the quantity and constraint explanation separately; full credit requires both. Accept equivalent unit quantities only under the declared representation policy. Reject 60 litres retained and the explanation “the rate is different” because the supplied rate is unchanged.

The source and target are shown as paired structures with quantities and units. A practice slider can vary duration and capacity after the first answer, illustrating `retained=min(rate×time,capacity)` for this explicitly constant-rate, initially empty, overflow-discarded model. B1 maps rate and time with no capacity; B2 changes units; B3 introduces capacity; B4 includes a nonzero initial amount or piecewise rate with all assumptions stated. Successful practice is not automatically near-transfer evidence; the adaptation/assessment chapter decides eligibility from prior exposure and origin metadata.

**Verification:** zero duration, zero/positive capacity, exact-fill boundary, below/above capacity, unit cancellation, alternative expression equivalence, and familiarity/structure metadata. Maps to CON-020, SCO-015, SCO-017, QA-F58.

## 8. Family inventory interpretation and implementation boundary

<a id="con-028"></a>

### CON-028 — The matrix is the migration inventory, not a new count claim

The following 58 rows are the activities in the current [NFDefaultContentCatalog.swift](../../Sources/TrainingEngine/NFDefaultContentCatalog.swift), in catalog order. Activity IDs are stable migration keys. `v0` etc. identify the **current fallback variant selector**, not a count of unique questions, a difficulty level, or a newly specified generator. Current mechanism descriptions refer to [NFFallbackExerciseGenerator.swift](../../Sources/TrainingEngine/NFFallbackExerciseGenerator.swift). Proposed B1–B4 demands describe work that must be authored and implemented.

Every row is governed by CON-001 through CON-027 and the relevant response rules. `QA-Fnn` is a mandatory family acceptance suite. The tests listed are minimum substantive cases, in addition to schema, localization, accessibility, identity, assistance, and general scoring tests. A catalog activity must remain unavailable at a band until its contract, assets, oracle, and review record exist. The UI must not advertise B4 content by relabeling a B1 seed.

<a id="con-029"></a>

### CON-029 — Family expansion must preserve a coherent operation

A matrix's advanced demand may require new substructures and a versioned generator; it cannot simply be stamped onto the old variant. If the expansion materially changes the activity promise, review its name/summary and provide an identity migration. Keep previously learned simpler forms in the appropriate band. Do not require every learner to complete every band of every activity; adaptation owns that selection.

The new quota for a narrow family must not be filled using semantic aliases. For cube nets, there are only 11 free cube-net shapes; rotations and relabelings of an otherwise identical query cannot manufacture hundreds of independent structures. Broaden reviewed tasks to queries that genuinely change the information or required relation, such as face adjacency, multiple fold constraints, specified intermediate folds, or validating a proposed fold. Count exact finite capacity after canonicalizing symmetries and query roles. If the resulting family cannot supply its proposed quota, CON-015's deficit path applies: author more coherent task types, revise the future edition's declared quota through review, or postpone that balanced edition. The implementation must never claim the capacity exists merely because parameter strings differ.

## 9. All 58 existing families: mechanism, prerequisites, demand changes, tests

### Mental Mathematics — 10 activities

| QA / current activity ID and title | Current mechanism | Prerequisites | Proposed real B1 → B2 → B3 → B4 demands | Required family tests |
|---|---|---|---|---|
| QA-F01 — `mental.rapid-recall`, Rapid Recall (v0) | Numeric products with left 6–12 and right 7–12. | Integer multiplication; inverse division for later forms. | B1: one-digit facts with optional reconstruction. B2: mixed multiplication/division facts without method cues. B3: signed and decimal-place facts with explicit prerequisites. B4: select/justify a fast reconstruction for unfamiliar related facts; do not turn this into an endurance timer. | Exact fact oracle; inverse consistency; zero/sign/decimal boundaries; timing separated from accuracy; declared new substructures and same-fact exposure deduplication. |
| QA-F02 — `mental.compensation`, Compensation Lab (v1) | Two-digit number times 9, 11, 19, or 21. | Distributivity; round multiples. | B1: supplied nearby product. B2: choose add/subtract one group. B3: compare two useful nearby multipliers. B4: two-factor compensation with a bound check and independently checked intermediate steps. | Both compensation directions; near-round boundaries; no cue in independent context; EX-C101; exact answers and valid alternative strategies. |
| QA-F03 — `mental.representation-relay`, Representation Relay (v2) | Fraction to percent; mixed generator sometimes uses mg to g. | Fractions; decimal place value; percent meaning. | B1: halves/quarters/decimals. B2: nonunit fractions and percentages above 100. B3: recurring rational forms under stated exact/rounded policy. B4: identify inconsistent linked representations in a table. Keep unit conversion a separately declared substructure. | Exact rational equivalence; percent scale; units do not leak across substructures; equivalent fraction/decimal inputs; precision instruction matches scoring. |
| QA-F04 — `mental.scientific-notation`, Scientific Notation Repair (v3) | Normalize a two-digit coefficient by one decimal shift. | Powers of ten; coefficient interval. | B1: one shift with shown place value. B2: positive/negative exponents and several shifts. B3: repair calculations combining coefficients and exponents. B4: compare magnitudes and detect cancellation/rounding issues under stated precision. | Value-preserving normalization; coefficient bounds; zero policy; negative exponents; equivalent valid notation; difficulty request changes actual shifts/operations. |
| QA-F05 — `mental.missing-factor`, Missing Factor (v4) | Solve integer box×multiplier=product. | Multiplication/division. | B1: one inverse with fact-table numbers. B2: signed or decimal factors. B3: one unknown in a two-operation relation. B4: select the only solution satisfying a stated domain after inverse transformations. | Unique solution/domain; zero multiplier rejected or deliberately classified; rational answers; forward substitution independent oracle; no invalid divide step. |
| QA-F06 — `mental.error-detective`, Percent Error Detective (v5) | Select the valid trace for one percentage of a base. | Percent multiplier; meaning of whole. | B1: identify percent-to-decimal scale. B2: locate first error in an actual trace. B3: distinguish changed base in sequential discounts/increases. B4: audit a table with multiple plausible errors and repair only the first decisive one. | Every trace step evaluated; first-error location; percentage-base changes; correct trace may use a different valid method; partial explanations do not pass contradictions. |
| QA-F07 — `mental.calculation-chain`, Calculation Chain (v6) | Add, multiply, subtract with small integers. | Operation order; intermediate values. | B1: two visible steps. B2: three/four steps with optional scratchpad. B3: branches or inverse checks with rational values. B4: locate a wrong intermediate step in two competing traces while preserving dependency order. | Interpreter/exact oracle; negative/rational states; diagnostic retry leaves original score; visible versus recalled intermediate demand declared; no memory-span efficacy claim. |
| QA-F08 — `mental.estimate-first`, Estimate First (v7) | Fixed nearest-power estimate around 200×50 plus literal plausibility/exact fields. | Rounding; multiplication; scale comparison. | B1: nearest stated power of ten. B2: useful one/two-significant-digit estimate before exact product. B3: compare bounds for a multistep expression. B4: choose an estimation strategy appropriate to error tolerance and explain whether a result can be ruled out. | Estimate-mode tolerance; actual learner estimate/result plausibility relation; exact component separate; accepted aliases full credit; ambiguous “estimate” wording forbidden. |
| QA-F09 — `mental.tool-judgment`, Mental or Machine? (v8) | One repeated-conversion/audit-trail scenario with an obvious tool choice. | Precision, repetition, consequence, auditability. | B1: one salient constraint. B2: trade precision against repetition. B3: choose among mental estimate, calculator, spreadsheet, or code for a concrete workflow. B4: propose a verification plan for a consequential calculation with conflicting constraints. | Multiple defensible tools encoded or question narrowed; no blanket “code always wins”; actual costs/constraints stated; comparable distractor wording. |
| QA-F10 — `mental.strategy-duel`, Strategy Duel (v9) | Prefer round compensation or ×100÷4 over costly/incorrect options. | Distributivity; factors; equivalent methods. | B1: compare valid and invalid methods. B2: compare two valid methods for a stated mental-work criterion. B3: choose under different exactness/working-memory constraints. B4: construct and verify an alternative method, then compare explicit operation counts or burdens. | Do not mark a mathematically valid method numerically wrong; criterion for “efficient” stated; strategy and result scored separately; tie cases accepted. |

### Spatial Reasoning — 6 activities

| QA / current activity ID and title | Current mechanism | Prerequisites | Proposed real B1 → B2 → B3 → B4 demands | Required family tests |
|---|---|---|---|---|
| QA-F11 — `spatial.coordinate-rotation`, Coordinate Rotation (v0) | Always a 90° counterclockwise point rotation in the positive quadrant. | Coordinates; direction; origin. | B1: one quarter-turn with axes. B2: clockwise/counterclockwise across all quadrants. B3: 180°/270° and non-origin centers. B4: compose translations and rotations or infer an unknown transform from enough correspondences. | Seed-11 duplicate regression; axes/origin/symmetry points; distance preservation about center; active/passive convention; every option semantically unique. |
| QA-F12 — `spatial.object-rotation`, 3D Object Rotation (v1) | Rotate a single coordinate triple about z; no labeled-face object task. | 3D axes; face normals; viewpoint. | B1: one labeled cube quarter-turn with teaching replay. B2: EX-C102 active rotation from an explicit viewpoint. B3: sequential rotations about different axes. B4: unfamiliar asymmetric object orientations with occlusion and no mirror substitution. | Proper rotation oracle; handedness; fixed-axis normals; order noncommutativity; visual/accessible agreement; matched face labels rather than coordinate-only substitution. |
| QA-F13 — `spatial.cross-section`, Cross-Section Puzzle (v2) | Three elementary solid/parallel-or-central slice cases. | Solid geometry; plane intersection. | B1: axis-aligned cube/cylinder/sphere slices. B2: translated planes and noncentral sphere radius changes. B3: oblique planes with permitted shapes derived geometrically. B4: infer or reject a proposed slice under multiple position/orientation constraints. | Plane actually intersects solid; degeneracy/tangency distinguished; no “circle versus ellipse” ambiguity from inclusive definitions; independent geometry oracle; symmetry deduplication. |
| QA-F14 — `spatial.top-view`, Top-View Decoder (v3) | Select length and width of a rectangular block. | Orthographic projection; occupied positions. | B1: footprint of a block. B2: stepped assemblies with hidden height. B3: choose between assemblies sharing one projection using a second view. B4: reconstruct all feasible arrangements or identify underdetermination from supplied projections. | Real occupied-cell model; height does not incorrectly affect top footprint; occlusion; multiple valid reconstructions encoded; view orientation specified. |
| QA-F15 — `spatial.cube-net`, Cube-Net Puzzle (v4) | Opposite-to-A query on a validated net. | Face adjacency; folding; opposite normals. | B1: marked fold hints. B2: opposite-face query without hints. B3: adjacency/orientation relations after partial folds. B4: evaluate multiple face constraints or find an impossible proposed net/fold under explicit rules. | All 11 free net shapes; fold collision/normal oracle; query-role/symmetry canonicalization; actual finite capacity audit; invalid nets never shown as valid; no label-only novelty. |
| QA-F16 — `spatial.vector-reflection`, Vector Reflection (v5) | Reflect a positive coordinate pair across the y-axis. | Coordinates; components; mirror line. | B1: reflection across a coordinate axis. B2: arbitrary quadrants and translated axis-aligned lines. B3: reflect across y=x or y=−x with clear geometry. B4: distinguish rotation/reflection compositions using orientation and fixed points. | Axis/line fixed points; distance-to-line preservation; involution property; unique choices at symmetric coordinates; direction and units consistent. |

### Quantitative Intuition — 8 activities

| QA / current activity ID and title | Current mechanism | Prerequisites | Proposed real B1 → B2 → B3 → B4 demands | Required family tests |
|---|---|---|---|---|
| QA-F17 — `quantitative.proportion`, Observed Proportion (v0) | Part/whole percentage with one-decimal tolerance. | Part/whole; percent. | B1: explicit full denominator. B2: derive total from complementary counts. B3: distinguish conditional from overall denominators. B4: compare rates across differently sized groups without confusing counts with rates. | Totals/denominators; zero-total case excluded or declared undefined; rounding boundaries; fraction/percent distinction; denominator misconception feedback. |
| QA-F18 — `quantitative.fermi`, Fermi Estimate (v1) | All four factors and multiplication formula are supplied. | Multiplicative decomposition; units; plausible ranges. | B1: select correct factors from a list. B2: supply one justified missing factor range. B3: construct an explicit decomposition and range. B4: compare sensitivity and decide which additional measurement most reduces uncertainty. | Dimension cancellation; factor independence assumptions stated; equivalent decompositions accepted; interval propagation; plausible assumptions reviewed, not exact-word graded; no false single “true” estimate. |
| QA-F19 — `quantitative.unit-bridge`, Unit Bridge (v2) | mm→m, sometimes in estimate/plausibility/exact fields. | Metric prefixes; dimension preservation. | B1: one prefix conversion with fixed destination unit. B2: choose factor orientation. B3: squared/cubed units or compound rates. B4: reconcile mixed units in a multistep calculation and identify a dimensionally invalid model. | Exponent applies to conversion factor; affine temperature conversions handled separately; quantity versus representation policy; exact rational values; unit omission according to control mode. |
| QA-F20 — `quantitative.scaling`, Scaling Law (v3) | Direct/inverse/square relation with factor 2 or 3. | Proportionality; exponents. | B1: direct scaling. B2: distinguish direct/inverse. B3: power-law transformation from a stated exponent. B4: combine scale changes or identify insufficient data when proportionality is not given. | Law-specific oracle; nonzero domains; negative/fractional factor policy; no multiplication shortcut for inverse cases; unchanged metadata cannot represent harder content. |
| QA-F21 — `quantitative.bayes`, Base-Rate Bayes (v4) | Natural-frequency conditional probability in a narrow rate range. | Two-way tables; conditional denominators. | B1: supplied positive-result counts. B2: EX-C103 complete table. B3: reconstruct counts from base rate and screen rates. B4: compare policies or posterior conclusions with explicit loss/uncertainty constraints. | Reconciled cells; no zero conditional denominator; complements; rare-base-rate cases; exact-rational/rounding check; prior and conditional probabilities never conflated. |
| QA-F22 — `quantitative.expected-value`, Expected Value (v5) | Probability-weighted signed outcomes. | Probability totals; weighted sums. | B1: two gains. B2: gains/losses and stated costs. B3: several outcomes with conditional branches. B4: compare expected value against a stated risk or resource constraint without claiming expected value uniquely determines preference. | Probabilities sum to 1; costs not double-counted; signs; unreachable branches; alternate valid utility/risk choices when not specified; independent exact oracle. |
| QA-F23 — `quantitative.regression`, Regression Detective (v6) | Extreme first score and lower second score; fixed cautious interpretation. | Sampling variability; selection; causal limits. | B1: identify extreme-based selection. B2: distinguish noise from evidence of permanent change. B3: compare repeated measurements with/without extreme selection. B4: assess intervention claims with a control group and explicitly modeled variation. | Do not assert regression as the only cause; include improvements/declines and no-change cases; observed data support keyed claim; uncertainty and causal design kept separate. |
| QA-F24 — `quantitative.interval`, Interval Inspector (v7) | Generic “95% uncertainty interval” scope selection. | Estimates; interval endpoints; procedure. | B1: read endpoints for a named quantity. B2: distinguish population observation intervals from mean-estimate intervals. B3: interpret confidence versus credible intervals under supplied definitions. B4: compare decision thresholds using an interval for the actual contrast and stated model. | Interval type always explicit unless omission is the task; no overlap-significance shortcut; zero inclusion not equality; confidence not automatically parameter probability; source-backed wording review. |

### Scientific Reasoning — 9 activities

| QA / current activity ID and title | Current mechanism | Prerequisites | Proposed real B1 → B2 → B3 → B4 demands | Required family tests |
|---|---|---|---|---|
| QA-F25 — `science.claim-evidence`, Claim–Evidence Bounds (v0) | Changing means with the same descriptive/causal-limit evidence mapping. | Observation versus inference; study design. | B1: support one descriptive claim. B2: distinguish descriptive and causal evidence. B3: match multiple claims to sufficient evidence bundles. B4: identify conflicts and revise scope across a bounded report with alternative explanations. | Evidence is not a tautological restatement; alternative support bundles; treatment direction varies; no universal causal claim from means; actual design differences create variety. |
| QA-F26 — `science.confound`, Confound Hunter (v1) | Baseline ability explicitly causes exposure and outcome. | Directed causal graphs; temporal order. | B1: one clearly described common cause. B2: infer graph from a scenario. B3: distinguish confounder, mediator, and collider with supplied graph. B4: compare adjustment plans under a declared causal model. | Graph paths and node roles oracle; no association-only definition of confounder; temporal/domain assumptions supplied; do not imply indiscriminate adjustment is safe. |
| QA-F27 — `science.next-experiment`, Next Discriminating Experiment (v2) | One intervention-versus-drift scenario; context supplies the best experiment. | Hypotheses; predictions; controls. | B1: choose an observation with contrasting predictions. B2: choose independent manipulation/measurement. B3: compare realistic designs with partial strengths and costs. B4: choose a sequential experiment plan under explicit resource and identifiability constraints. | No pre-answer key in context; prediction matrix validated; rival options genuinely discriminate some cases; impossibility/insufficient-control case; no universal uniquely “best” without criterion. |
| QA-F28 — `science.figure-uncertainty`, Figure Uncertainty Audit (v3) | Variable means/raw values with sometimes contradictory overlap claims. | Means; interval types; design scope. | B1: verify displayed geometry. B2: identify what an interval estimates. B3: EX-C104 contrast interval plus design. B4: audit model assumptions, paired/independent comparison, and practical threshold separately. | All 266 current bad cases replaced/quarantined; data-summary agreement; touching/disjoint/overlap partitions; significance from specified analysis; no causal inference from interval geometry. |
| QA-F29 — `science.bias-repair`, Bias Repair (v4) | Select randomization, blinding, and replication over post-hoc exclusion. | Assignment/measurement/selection bias. | B1: match a safeguard to one threat. B2: repair a two-threat design. B3: choose feasible safeguards with explicit ethical/practical constraints. B4: identify residual limitations after a partial repair and avoid overclaiming identification. | Each safeguard targets the named threat; infeasible options not universally keyed; replication does not remove every bias; selecting all cannot earn full credit. |
| QA-F30 — `science.competing-predictions`, Competing Predictions (v5) | Generic preference for evidence expected by one rival. | Hypotheses; conditional predictions. | B1: match each model to a prediction. B2: select discriminating evidence from a table. B3: update relative support with a supplied likelihood model. B4: identify an observation that both models fail and propose a testable revision. | Explicit hypotheses/data; predictions computed; evidence compatible with both does not settle comparison; numeric update if used independently verified; no hindsight-only model rewrite. |
| QA-F31 — `science.reviewer`, Reviewer Mode (v6) | Fixed convenience-assignment and truncated-axis concerns. | Design, visualization, reproducibility. | B1: find one documented flaw in a short report. B2: separate strengths from flaws. B3: rank threats to a stated conclusion. B4: propose a minimal revision and explain what remains unresolved. | Real bounded report/figure; axis baseline context matters; transparency not marked as a flaw; severity criterion explicit; multiple defensible rankings accepted or avoided. |
| QA-F32 — `science.experiment-sequence`, Experiment Sequence (v7) | Order generic hypothesis/prediction/control/contrast steps under an experiment question. | Experimental dependencies; measurement timing. | B1: order one concrete protocol chain. B2: parallel preparation steps and control checks. B3: insert a missing safeguard at a valid dependency point. B4: repair a branching protocol that cannot identify its target effect. | Prompt asks the deliverable actually scored; DAG alternate orders; stateful timing dependencies; dangerous/unsupported real-world procedure content excluded from generic tasks. |
| QA-F33 — `science.paper-sprint`, Paper Sprint (v8) | A preferred reading order without an abstract. | Question/method/result/limitation distinction. | B1: identify fields in a short synthetic abstract. B2: extract numerical result and limitation. B3: separate authors' conclusion from supported claims. B4: compare two conflicting bounded abstracts and identify the missing methodological detail. | Actual abstract included; every keyed extraction supported by text; no source hallucination; alternative accurate wording; reading strategy not misgraded as the only valid order. |

### Logic & Debugging — 9 activities

| QA / current activity ID and title | Current mechanism | Prerequisites | Proposed real B1 → B2 → B3 → B4 demands | Required family tests |
|---|---|---|---|---|
| QA-F34 — `logic.state-trace`, State Trace (v0) | Many numbers in one stale-derived-state program. | Assignment; Boolean conditions; invariants. | B1: two assignments. B2: EX-C105 stale state. B3: conditional updates with different branch outcomes. B4: find a smallest counterexample or compare invariant-preserving updates across a finite state space. | Independent AST execution; invariant timing; branches cover both paths; typed aliases full credit; display skins no new semantics; actual program structures required for quota. |
| QA-F35 — `logic.conditions`, Necessary or Sufficient? (v1) | Divisibility by 4 versus evenness, with explanation before answer. | Implication; converse; counterexample. | B1: supplied small truth/set examples. B2: classify necessary/sufficient/both/neither. B3: compound predicates with explicit domains. B4: construct a minimal counterexample to one direction or derive a weakest sufficient condition in a bounded domain. | All four relation categories represented; vacuous truth/domain restrictions reviewed; no answer in context; truth-table/set oracle; alternative valid counterexamples. |
| QA-F36 — `logic.counterexample`, Counterexample Quest (v2) | Fixed even-product claim and visible 2×3=6 solution. | Premise; conclusion; universal quantifier. | B1: select a premise-true/conclusion-false case. B2: construct one in a bounded domain. B3: distinguish counterexample from a case outside domain. B4: find a minimal counterexample under an explicit order or repair the quantifier/condition. | Premise true and conclusion false independently checked; zero/negative domain cases; minimality oracle; no visible keyed example; multiple correct constructions accepted. |
| QA-F37 — `logic.proof-builder`, Proof Builder (v3) | One four-step parity proof. | Definitions; algebra; dependency. | B1: strict short proof chain. B2: alternate independent derivation branches. B3: supply a missing justified step. B4: choose sufficient lemmas and assemble a dependency-valid proof with an explicit target and domain. | DAG all topological orders; no cyclic proof; each inference locally valid; irrelevant lemma penalties declared; prose proof outside supported verifier becomes self-check. |
| QA-F38 — `logic.invalid-step`, First Invalid Step (v4) | Division-by-zero fallacy with divisor-zero cue. | Algebra operation preconditions. | B1: explicit single invalid operation. B2: locate first invalid line in a trace. B3: distinguish valid cancellation from domain loss. B4: compare two purported proofs with conditional validity and repair the earliest unsupported step. | Nonzero and zero branches; prior lines verified; first versus any invalid step differentiated; domain preservation; solution removed from independent preamble. |
| QA-F39 — `logic.boundary-bug`, Boundary Bug Hunt (v5) | One loop always misses last element. | Index ranges; empty/singleton cases. | B1: trace singleton boundary. B2: choose minimal failing input. B3: bugs dependent on value as well as size. B4: shrink a counterexample across a finite structured input domain under a declared minimization order. | Empty/singleton/typical input execution; expected output defined, including zero-valued elements; minimality criterion; no test input outside declared domain; interpreter bounds. |
| QA-F40 — `logic.complexity`, Complexity Duel (v6) | Linear scan versus ordered pair enumeration. | Input size; operation counts. | B1: count concrete loop iterations. B2: infer linear/quadratic growth. B3: triangular, logarithmic, or composed loops with stated primitive costs. B4: compare asymptotic growth with finite-size constants and an explicit workload. | Correct dominant term; loop bounds inclusive/exclusive; early exits and input assumptions; output-size misconception; do not equate asymptotic class with fastest at every n. |
| QA-F41 — `logic.loop-repair`, Loop Repair (v7) | Choose index<count instead of count−1. | Loop invariant; bounds; exact-once visitation. | B1: choose a safe bound. B2: repair start/bound/increment combinations. B3: preserve a data-dependent invariant across branches. B4: choose a minimal patch satisfying a reviewed test domain and explain a remaining limitation. | Empty/singleton/multi-element tests; no duplicate/omitted visits; patch authority from interpreter; hidden tests meaningful rather than mirrored implementation; unsafe text never executed. |
| QA-F42 — `logic.calibration`, Confidence Calibration (v8) | Pick 70/80/90% with small-sample caution. | Frequencies; probability; uncertainty. | B1: compare stated confidence to an observed rate. B2: identify over/underconfidence in a supplied table. B3: compare groups with different sample sizes/uncertainty. B4: diagnose confidence changes under selection or shifting task mix using explicit data. | No individual certainty inferred from 10 answers; comparable population stated; proper separation of evidence and preference; no always-50% strategy; adaptation calibration model remains separate. |

### Retrieval Practice — 9 activities

| QA / current activity ID and title | Current mechanism | Prerequisites | Proposed real B1 → B2 → B3 → B4 demands | Required family tests |
|---|---|---|---|---|
| QA-F43 — `retrieval.free-recall`, Free Recall (v0) | Self-check with three generic criteria. | Prior exposure to a specific target. | B1: recall a short fact after learning. B2: recall a relationship and condition. B3: recall several linked elements without source cues. B4: reconstruct a bounded explanation including a limitation; still self-reported unless objectively constrained. | Attempt-before-reveal; target-specific checklist; no 100% accuracy from “matched”; source/target identity; assistance/exposure provenance; unsupported prose never asserted objectively wrong. |
| QA-F44 — `retrieval.precision-recall`, Precision Recall (v1) | Exact-string short answer for any fact/computation. | Relevant target knowledge; supported answer notation. | B1: constrained name/value. B2: EX-C106 odd/even relationship fields. B3: a formula/application with conditions. B4: distinguish closely related definitions using a required qualifier and a reviewed constrained response. | Arithmetic-mean paraphrase; `2*x`/`4x`; case-sensitive F/f; label versus formula domain; unit-fixed numeric answers; unknown prose coverage routes honestly. |
| QA-F45 — `retrieval.cloze`, Relationship Cloze (v2) | Full question prefixed “Cloze reconstruction.” | Learned relationship; context comprehension. | B1: one meaningful blank. B2: choose the omitted relation or condition. B3: multiple linked slots with unambiguous scope. B4: reconstruct a omitted causal/mathematical dependency from a bounded source excerpt. | Actual omission; no multiple unconstrained completions; slot grammar/units; answer not elsewhere in excerpt; changed rendering retains target identity. |
| QA-F46 — `retrieval.teach-back`, Teach It Back (v3) | Self-check explanation with generic criteria. | Learned entities, relationship, conditions. | B1: explain one relation simply. B2: include a necessary condition. B3: use a concrete example and counterexample. B4: explain the boundary of applicability to a peer in a bounded scenario. | Unconstrained prose self-check only; explicit checklist; unsupported added scope flagged in reference; no enforced essay length; original attempt preserved after reveal. |
| QA-F47 — `retrieval.recognition`, Recognition Audit (v4) | One canonical answer versus generic relationship statements. | Target familiarity or source reading. | B1: distinguish plausible neighboring concepts. B2: choose correct direction/condition. B3: discriminate near-miss statements differing in one qualifier. B4: select a supported reconstruction from a bounded source with misleading but plausible alternatives. | Comparable option grammar/length; target-specific misconception distractors; unique supported interpretation; no recognition-as-free-recall claim; source shown only when mode permits. |
| QA-F48 — `retrieval.repair-cycle`, Retrieval Cycle Builder (v5) | Fixed workflow order unrelated to each target. | Attempt/review distinction; target knowledge if assessed. | B1: learn the explicit recall-review cycle as metacognitive practice. B2: locate a specific mismatch in a supplied attempt. B3: choose a targeted repair and make a closed-reference retry. B4: distinguish incomplete recall from an invalid source claim and plan the relevant follow-up. | Generic workflow cannot count as target knowledge; actual discrepancy exists; retry is new linked attempt; valid workflow orders encoded; reference hidden again before retry. |
| QA-F49 — `retrieval.equation`, Equation Reconstruction (v6) | Generic E_source+C_stated→blank plus exact prose answer. | Specific formula and symbol meanings. | B1: fill one term/coefficient. B2: reconstruct one side with units. B3: restore missing dependency/condition. B4: rebuild a reviewed derivation fragment while preserving domain and variable roles. | Real target equation; F/f and function/multiplication distinction; restricted equivalence; domain exclusions; missing required asset disables form rather than generating generic equation. |
| QA-F50 — `retrieval.figure`, Figure Interpretation (v7) | Two-row table repeats the question. | Reading the actual figure type. | B1: read a plotted value/label. B2: recover a supported trend. B3: relate a figure to the target equation or condition. B4: distinguish two plausible interpretations using uncertainty/design information explicitly supplied. | Actual chart/table data required; axes/units/legend; accessible equivalent; claim bounded by data; no statistical shortcuts; paraphrase or structured response appropriate to task. |
| QA-F51 — `retrieval.source-filter`, Source-Filter Trace (v8) | Fixed pseudocode returns an obvious supported candidate. | Source claims; Boolean filters; bounded trace. | B1: evaluate one claim against explicit source evidence. B2: trace changing candidate order and support states. B3: handle multiple supported/unsupported qualifiers. B4: repair a filter whose logic accepts an unsupported scope expansion. | Actual source support relation; varied return position/no-result case; interpreter oracle; content evidence distinct from code-trace evidence; no opaque generic “supported” label answer cue. |

### Transfer Lab — 7 activities

| QA / current activity ID and title | Current mechanism | Prerequisites | Proposed real B1 → B2 → B3 → B4 demands | Required family tests |
|---|---|---|---|---|
| QA-F52 — `transfer.sequence`, Transfer Sequence (v0) | Generic identify/represent/solve/check order. | Familiar source method; target comprehension. | B1: map named source quantities. B2: order actual target-specific steps. B3: insert a needed assumption check before a risky transfer. B4: revise a partially valid plan where source and target dependencies differ. | Real source/target pair; dependency-valid alternatives; transfer process distinct from target solution; no generic order counted as quantitative mastery. |
| QA-F53 — `transfer.conditions`, Preserve Transfer Conditions (v1) | Fixed select structure preservation and constraint recheck. | Assumptions; units; mathematical roles. | B1: identify same/different units. B2: classify preserved versus changed assumptions. B3: determine whether a method remains applicable after one constraint changes. B4: identify the minimal additional information required to justify transfer. | Every condition explicit; alternative sufficient bundles; cannot copy coefficients across units; insufficient-information answer where appropriate; no always-choose-cautious pattern. |
| QA-F54 — `transfer.rate`, Rate in a New Field (v2) | Rate×time with only number/context changes; 986 bank slots. | Constant rates; accumulation; units. | B1: identify rate/time in a new setting. B2: convert units before accumulation. B3: piecewise constant rates or nonzero initial quantity. B4: distinguish input flow, retained amount, and outflow under a supplied conservation model. | Quantity target explicit; constant-rate assumption checked; piecewise exact integration; zero/time/unit boundaries; source/target structure metadata; strict bank family quota. |
| QA-F55 — `transfer.representation`, Table-to-Equation (v3) | Four simple y=kx tables. | Ratios; linear relations. | B1: direct proportionality table. B2: affine relation with intercept. B3: discriminate inverse/quadratic/linear forms from sufficient data. B4: identify underdetermination or select among a stated finite model class with noise/measurement assumptions. | Enough data for uniqueness within declared model class; do not imply finite points identify a universal function; every row verified; equivalent equations accepted; ratio versus difference errors. |
| QA-F56 — `transfer.causal-map`, Causal Structure Map (v4) | Fixed controller/regulation feedback evidence mapping. | Directed graphs; feedback; delays. | B1: map node roles. B2: map direction and sign of edges. B3: compare delayed feedback structures across unfamiliar labels. B4: identify why an apparent analogy fails when an edge, delay, or external input differs. | Graph isomorphism under permitted role mapping; direction/sign/delay preserved; surface labels insufficient; multiple valid maps encoded; no metaphor-only claim of causal identity. |
| QA-F57 — `transfer.interacting-variables`, Interacting-Variable Ratio (v5) | Double numerator and halve denominator, six baseline values. | Ratios; multiplicative changes. | B1: change one quantity. B2: simultaneous opposing changes. B3: map ratio roles across concentration/density/rate contexts with units. B4: infer a missing factor or identify when a denominator change violates a constant-quantity assumption. | Nonzero denominator/domain; independent factor transformation; exact rational oracle; realistic conservation assumptions explicit; alternative units; varied transformations beyond always ×4. |
| QA-F58 — `transfer.saturation`, Saturation Check (v6) | One generic “check linearity” answer. | Linear accumulation; capacity/limits. | B1: identify a stated cap. B2: decide whether source linear rule applies within range. B3: EX-C107 retained versus delivered amount. B4: piecewise behavior with initial state, threshold, or multiple constraints explicitly supplied. | Exact threshold equality; below/above cap; no unsupported universal linearity; retained/delivered distinction; boundary assumptions; transfer evidence only with eligible origin/exposure metadata. |

## 10. Verification, implementation order, and completion gates

<a id="sco-019"></a>

### SCO-019 — The score test corpus must contain both meaning-preserving and meaning-changing edits

Every authoritative answer needs tests that mutate one meaningful feature at a time: reverse a relation, negate it, alter a quantifier, remove a condition, change a sign, change an exponent, change a unit prefix, swap F/f, insert redundant parentheses, add insignificant zeroes, or use a declared synonym. The correct acceptance boundary must be decided editorially before implementation. Tests must include invalid combinations that contain all expected keywords. A catalog audit that submits only each stored canonical key back to the same scorer is not adequate.

| Acceptance suite | Inputs / execution | Required corrected result | Evidence mapping |
|---|---|---|---|
| QA-S01 | Spatial seed 11; enumerate all generated option semantic values; symmetry/axis/origin partitions | Exactly one semantic correct choice and no equivalent distractor; any shipped invalid old contract is handled as an item error | QA-C01; CON-006; SCO-006 |
| QA-S02 | Entire bounded uncertainty parameter domain; original science seed; touching/disjoint/overlap fixtures; individual versus difference intervals | Stimulus/narrative agree; every key follows the declared estimand and procedure; overlap flag does not determine inferential significance | QA-C02; CON-007; EX-C104 |
| QA-S03 | Arithmetic-mean paraphrase; `2*x` for x² derivative; `4x` for 2x² derivative; relation reversal and negation | Equivalent answers receive 1; reversed/contradictory answers do not; uncovered prose routes to self-check without false objective rejection | QA-C03; SCO-009–SCO-013 |
| QA-S04 | F(b)−F(a), f(b)−f(a), F*b−F*a, swapped endpoint order, valid grouping variants under F′=f | Only domain-valid antiderivative expression/equivalents receive full credit; roles/case retained | QA-C04; SCO-010–SCO-011 |
| QA-S05 | Canonical estimate/state; every declared equivalent spelling; combinations of field alternatives; one wrong field | Every fully accepted equivalent yields correct/1; partial states have declared component scores and false correctness | QA-C05; SCO-001; SCO-015 |
| QA-S06 | Every family and protected purpose; inspect visual/accessibility pre-answer role graph | Only essential givens are exposed; no keyed counterexample, zero-divisor conclusion, or best-experiment solution before response | QA-C08; CON-004; CON-008 |
| QA-S07 | Numeric exact/rounded/estimate policies, fraction/decimal/scientific notation, locale separators, fixed/free units, zero denominator | Meaning-preserving notation accepted under declared mode; ambiguity clarified; invalid mathematical values rejected safely | SCO-003; SCO-005; SCO-016 |
| QA-S08 | Multiple-choice and claim/evidence correct sets, missing edge, extraneous edge, select-all, alternate sufficient bundles | Full correctness only for complete valid support/set; selecting everything cannot exploit partial credit | SCO-007; SCO-017 |
| QA-S09 | Ordering DAG with independent steps; missing/repeated node; reversed edge; authored cycle | All valid complete topological orders accepted; invalid order rejected; cyclic authored contract blocked | SCO-008 |
| QA-S10 | Free recall with/without pre-reveal attempt; all three self-ratings; closed-reference retry | Self-reported outcome distinct from verified accuracy; retry linked and original intact | SCO-014; CON-026 |
| QA-S11 | Same contract/response across option order, display skin, theme, offline/online state, supported locale representations | Same authoritative outcome and credit; localized parser policy explicit; no model-dependent score | SCO-002; SCO-003 |
| QA-S12 | Unsupported symbolic grammar, resource limits, overflow, malformed tuple, stale option/evidence ID | Finite safe response with explanatory invalid/clarification outcome; no crash, code execution, or false conceptual score | SCO-003; SCO-011 |

<a id="con-030"></a>

### CON-030 — Bank and identity tests must validate capacity, not only counts

| Acceptance suite | Required scenario | Invariant |
|---|---|---|
| QA-B01 | Full new edition admission for every lab | At least required unique semantic capacity; approved quotas and all mandatory assets; deficits fail before release. |
| QA-B02 | Whole epoch from heavily unequal family queues; all permutations audited | Every admitted semantic ID appears exactly once; deterministic order; realized mix matches finite admitted inventory. |
| QA-B03 | Two concurrent windows, abandon-before-answer, relaunch | No reservation collision or reuse; quit does not reset novelty. |
| QA-B04 | Quiz crosses epoch with prior-tail and within-quiz exclusions | No duplicate inside the quiz; finite fallback when requested unique eligible capacity is unavailable. |
| QA-B05 | One target supports free recall, cloze, recognition; translations and option shuffles | Rendering/locale changes do not add target novelty or erase exposure. |
| QA-B06 | Selected family exhausted; remaining lab items fail prerequisites; review chosen | No silent activity substitution, fake novel ID, or forced ineligible item; truthful named continuation. |
| QA-B07 | Copy-only revision, answer correction, generator change, quarantined item | Correct identity/supersession relation; required edition/scoring versions; installed historical attempts retain references. |
| QA-B08 | Retrieval field totals plus compatible rendering slots deliberately infeasible | Assignment algorithm returns exact deficit; it does not count one target twice or attach meaningless assets. |
| QA-B09 | Current-bank comparison audit | Report concentration by family **and structure**, distinct targets, rendering mix, band capacity, and duplicate/invalid counts; raw 1,000 count alone cannot pass. |

<a id="con-031"></a>

### CON-031 — Release review must inspect representative learner sessions

For the complete proposed four-band release, after automated contract checks reviewers must complete at least one Foundation, Developing, Challenging, and Advanced session in each lab using the actual renderer and response controls. This is 28 editorial sample sessions, chosen for band and family coverage rather than a claim of statistical validation. An interim corrective release reviews every advertised lab/band combination; it must not advertise unimplemented bands merely to satisfy a 28-session count. Include a keyboard-only and accessible reading pass for every response/representation type. The interaction chapter defines device sizes and assistive-technology coverage.

For each sample, reviewers answer: can a learner identify the deliverable; are prerequisites and assumptions sufficient; is the task materially different at its band; can ordinary valid notation be entered; does a correct answer receive full credit; do wrong alternatives expose real misconceptions; can the explanation be followed; does the session feel varied without becoming incoherent? Record any content wording that requires reading implementation terminology. A nontechnical/editorial reviewer must inspect at least the instructions and feedback, not only an engineer familiar with internal schemas.

<a id="con-032"></a>

### CON-032 — Instrument quality without inventing a psychometric model

Collect, subject to the app's existing privacy choices, counts of presented/answered/skipped items, parse clarifications, disagreement reports, selected distractors, hints, objective outcomes, self-check outcomes, and qualified timing. Aggregate by edition/revision, objective, family, structure, response form, band, assistance, and language. The adaptation chapter determines which events are eligible for learner estimation. This chapter requires the underlying distinctions so an easy recognition item is not merged blindly with an uncued explanation.

Use low participation in a distractor, unusually high abandonment, or repeated parser clarification as review signals, not automatic proof of bad content. Compare rates only with denominators and relevant uncertainty; do not set unsupported universal pass-rate targets. The release should retain enough raw structured provenance to reproduce a questionable score without collecting more personal text than necessary.

<a id="con-033"></a>

### CON-033 — Implement in a dependency order that cannot hide unresolved defects

| Work package | Concrete deliverable | Depends on | Completion condition |
|---|---|---|---|
| C-A: trust repairs | Duplicate-option guard; coherent interval authority; accepted-state full-credit fix; independent-mode scaffold roles | Existing generator/scorer adapters | QA-S01, S02, S05, S06 pass on corrected behavior; known defective regions quarantined or replaced with version mapping. |
| C-B: response authority | Domain-specific parsing; numeric/unit policies; bounded symbolic parser; constrained prose/self-check routing; explicit outcome types | Shared state/outcome contract from application chapter | QA-S03, S04, S07–S12 pass; UI displays the actual authority and clarification states. |
| C-C: editorial schema | Objective/family/structure identities; four-band demand records; reviewer/oracle records; compatible-rendering assets | C-A and shared adaptation fields | All 58 matrix rows have reviewed B1/B2 coverage; unsupported B3/B4 availability remains explicit, never relabeled. |
| C-D: genuine family expansion | New scenario/program/geometry/target structures needed by quota deficit reports | C-C | Finite candidate pools satisfy approved edition quotas after semantic canonicalization; all QA-F01–F58 suites for admitted bands pass. |
| C-E: bank admission and rotation | Deterministic capacity assignment; approved balanced inventory; whole-epoch permutation; exhaustion fallback | C-C, C-D, atomic reservation integration | QA-B01–B09 pass; current first-unique concentration cannot recur unnoticed. |
| C-F: release and evaluation | Signed edition inventory, incident workflow, 28 editorial sample sessions, quality metrics | C-A through C-E, external release authority | Manifest covers delivered content; all admitted contracts reproducible; outcomes match rendering; unresolved content limitations documented. |

C-A can ship as a corrective edition before the entire expanded bank is ready, provided its identity corrections and honest inventory limitations are preserved. It must not claim all planned bands or balanced quotas have been delivered. C-D cannot be replaced by widening integer ranges to hit a count. C-F is not complete when a checklist exists; it requires execution evidence.

<a id="con-034"></a>

### CON-034 — The chapter is complete only when quality and honesty agree

The intended content release is accepted when every delivered item has a valid authoritative contract, every fully accepted equivalent receives full credit, no protected item reveals its solution beforehand, all advertised forms and bands have real assets/demands, the declared bank quotas are feasible and satisfied, no-replacement behavior is preserved across realistic failures, and ordinary learner feedback is accurate about the type of evidence obtained. Release notes must distinguish repaired grading from new content and new content from demonstrated learning outcomes.

Unresolved expert review, unavailable advanced families, parser scope limits, and source-specific ungraded prose are legitimate product boundaries when stated clearly and routed appropriately. They are not reasons to invent correct answers, fake variety, conceal a scorer limitation, or label the same basic task harder.

## 11. Source and implementation reference map

| Repository source | Role in current implementation | Specification responsibility |
|---|---|---|
| [NFDefaultContentCatalog.swift](../../Sources/TrainingEngine/NFDefaultContentCatalog.swift) | 58 activities, stable IDs, fallback selectors, summaries, initial difficulty metadata | CON-028/029 and QA-F01–F58 inventory. |
| [NFFallbackExerciseGenerator.swift](../../Sources/TrainingEngine/NFFallbackExerciseGenerator.swift) | Actual seven-lab question drafts, parameters, strategies, renderings, answer schemas | CON-001–013 and the worked fixtures. |
| [NFExerciseModels.swift](../../Sources/TrainingEngine/NFExerciseModels.swift) | Eight interaction cases and current exercise/scoring-related metadata | CON-001, SCO-001–018 migration adapters. |
| [NFExerciseScoringEngine.swift](../../Sources/TrainingEngine/NFExerciseScoringEngine.swift) | Schema validation, input validation, response grading, feedback | SCO-001–019 and QA-S01–S12. |
| [NFBundledRetrievalCatalog.swift](../../Sources/TrainingEngine/NFBundledRetrievalCatalog.swift) | 200 editorial targets, 800 computed instances, exact-string aliases/normalizer | SCO-009–014, CON-010/016/026, QA-F43–F51. |
| [NFEstimateExactContract.swift](../../Sources/TrainingEngine/NFEstimateExactContract.swift) | Estimate/plausibility/exact fields encoded as logic state | SCO-015/016 and QA-S05/S07. |
| [NFQuestionFingerprint.swift](../../Sources/TrainingEngine/NFQuestionFingerprint.swift) | Existing novelty canonicalization, retrieval target identity | CON-020/021, QA-B05/B07. |
| [NFOfflineQuestionBank.swift](../../Sources/TrainingEngine/NFOfflineQuestionBank.swift) | First-unique admission, 1,000-per-lab floor, signed coverage gate | CON-014–022 and QA-B01/B08/B09. |
| [NFOfflineQuestionRotation.swift](../../Sources/TrainingEngine/NFOfflineQuestionRotation.swift) | Versioned IDs, reservation ledgers, epoch/cursor and boundary exclusions | CON-017–019; state chapter owns transaction implementation. |
| [UniversalSessionView.swift](../../Sources/Features/Training/UniversalSessionView.swift) | Renders context/representations and current response controls | CON-004/008 and SCO-014/016; interaction chapter owns screens. |
| [OfflineQuestionBankTests.swift](../../Tests/OfflineQuestionBankTests.swift) | Canonical-key, uniqueness, and at-least-one-family tests | Extend with semantic truth, family capacity, and distribution gates rather than relying on current coverage alone. |
| [ExecutedProbeResults.txt](../QA_2026-09-04/ExecutedProbeResults.txt) | Actual application evidence for bad items, grading, distributions, and metadata-only difficulty | Baseline comparison for corrective acceptance tests. |

The one external statistical reference in section 3 supports the specific warning about comparing separate confidence intervals. The quotas, four editorial bands, parser resource limits, suggested practice partial-credit formula, and 28-session editorial review set are proposed product/engineering policies. None is represented as an externally validated psychometric standard.

---

<!-- Source: 03_Adaptive_Learning_and_Evidence.md -->

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

---

<!-- Source: 04_Runtime_Data_and_Migration.md -->

# Runtime, persistence, navigation and migration

Status: proposed implementation contract, version 1.0, 4 September 2026. This chapter defines the target behavior; it does not claim the implementation already exists. Read the [master specification](README.md) for scope and precedence and the [audit](../QA_2026-09-04/README.md) for observed evidence.

## 1. Architectural boundary

<a id="core-001"></a>

**CORE-001 — One learning runtime.** Every built-in practice launch, daily-plan block, protected check, review task and deterministic authored activity shall pass through one session coordinator. Source recall and reference/self-check use the same lifecycle primitives but a different scoring authority and evidence eligibility. A feature must not implement its own Submit→save→Next sequence. The existing `NFUniversalSessionRuntime` is the migration starting point, not a requirement to keep all logic in its current large view file.

<a id="core-002"></a>

**CORE-002 — Separate responsibilities.** Introduce the following logical components. Names below are proposed Swift-facing contracts, not instructions to copy an entire architecture before delivering a vertical slice.

| Component | Owns | Must not own |
|---|---|---|
| `SessionCoordinator` | Typed run state; commands; lifecycle; ownership; transition validation | Question truth, SwiftUI geometry, direct cloud API calls |
| `QuestionSelector` | Feasible candidate selection, protected exposure rules, versioned deterministic ordering | Score mutation, prose authoring at scoring time |
| `ExerciseFactory` | A reviewed concrete item from a descriptor/demand vector | Relabeling fixed tasks as harder, evidence reduction |
| `ResponseValidator` | Structural validity and actionable entry errors | Inferring semantic correctness from formatting alone |
| `ExerciseEvaluator` | Versioned deterministic scoring contract | Network/model evaluation of protected/scored answers |
| `AttemptRepository` | Append/idempotent commit, immutable original records, conflict detection | Silently replacing old responses or scoring versions |
| `SessionRepository` | Run envelope, reservation, checkpoint, commit journal | Regenerating a different question into an old draft |
| `EvidenceProjector` | Deterministic reduction of eligible records and corrections | Writing a new answer score, awarding XP by side effect |
| `LearningPresentation` | Readable response/explanation/diagram view models | Treating raw serialized payloads as display text |
| `NavigationCoordinator` | Validated routes, destination paths, dirty-work policy | Guessing a destination from stale view state |
| Existing system adapters | Notifications, widgets, Spotlight, optional sync | Defining authoritative learner/session state |

<a id="core-003"></a>

**CORE-003 — Pure boundaries.** Question generation, response validation, scoring, evidence reduction and next-item selection shall accept explicit value inputs and policy versions. They shall not read `Date()`, the global locale, `UserDefaults`, a network response or random state internally. The coordinator supplies the clock, saved locale, seed and policy. This is necessary for replay and independent tests.

<a id="core-004"></a>

**CORE-004 — Concurrency.** UI state stays on MainActor. Bounded expensive catalog construction, content decoding and bulk evidence projection execute away from the UI actor using immutable snapshots. Persistent models are accessed through their owning context/actor, not sent between actors. Returned view projections are immutable `Sendable` values. Cancellation cancels disposable computation; it does not interrupt a transaction halfway through an acknowledged save.

<a id="core-005"></a>

**CORE-005 — Versioned interfaces.** Codable runtime payloads declare their own schema version. Store schema version, content version, scorer version, selection policy version and presentation version are separate fields. Increasing one must not silently imply the others changed. Unsupported future payloads produce a recoverable unavailable state, never a best-guess decoder.

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
| `assistancePolicy` | permitted hint stages, solution reveal policy and effect on eligibility |
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
| `submitting` | Same problem; response locked; “Saving answer…” only if perceptible delay | Queue safe close; no second submit/Next | Durable commit intent and idempotent attempt write; close reconciles or retains a durable recoverable intent |
| `feedback` | Original question/answer plus concise correction/explanation | Next, deeperExplanation, reflect, retrySimilar, bookmark, pause | Attempt already durable; ancillary actions save independently |
| `protectedAcknowledgement` | Original response plus “Answer saved”; no correctness | Next, report, pause | Protected attempt durable; exact key remains unavailable |
| `referenceComparison` | Original response locked; reference revealed; self-rating controls | Rate, saveSelfCheck, pause | Reveal persisted; independent status cannot be restored by closing |
| `savingSelfCheck` | Comparison retained while committing | Queue safe close | Separate rating record; no deterministic correctness synthesized |
| `optionalReflection` | Inline editable reflection below feedback | Save, dismiss, edit reason, pause | Independent supplemental record; score immutable |
| `explicitReflection` | Metacognition task with purpose and original answer context | Save, “Not sure yet”, pause, saveAndClose | Allowed only under explicit task policy; never blocks safe exit |
| `paused(previous)` | Resume, Save & close, optional End session | Resume, saveAndClose, end | Clock stopped; interruption reasons recorded |
| `saveFailed(previous,intent)` | Content intact plus retry action and concise error | Retry, export draft, keep editing where safe, explicit draft discard or durable-pending close under RUN-022 | No false success; never discard a prepared/committed answer journal |
| `summary` | Completed/ended-early scope, results, next useful action | Review, done, start separate practice | Completion/stop status committed once |
| `unavailable(reason)` | Specific missing/invalid item explanation | Preserve work, choose safe replacement where allowed, end | Existing draft and original slot remain inspectable |

<a id="run-008"></a>

**RUN-008 — Ordinary deterministic answer.** Submit validates supported syntax, required fields and required confidence; freezes the exact response; evaluates against the pinned contract; writes an authoritative attempt only for a scoreable result; then reveals inline feedback. The problem does not disappear. Empty, unparseable or unsupported notation stays editable with clarification and creates no objective attempt. A well-formed wrong quantity/unit or requested-representation error is judged by the declared semantic rubric; it is not automatically a free validation retry. A zero-credit valid answer is a legitimate committed attempt. An evaluator's `needsClarification` stays in the answer phase without a score; uncovered explanatory prose may enter a clearly labeled self-check path under its declared authority, never an invented objective zero. A second click while submitting is ignored by command identity, not merely button disabling.

<a id="run-009"></a>

**RUN-009 — Confidence.** Protected baseline/reassessment and explicit calibration require an unselected-by-default inline confidence choice. Ordinary practice makes confidence optional and expands a deterministic one-in-five invitation; declining does not block Submit. All timed Rapid Recall/fluency tasks suppress confidence collection. Apply the exact invitation ordinal/hash policy in the adaptive chapter; repeated rendering does not count as another presentation. Confidence never changes answer correctness or XP. A response can be edited before submit after choosing confidence; editing invalidates that confidence selection when it materially changes the answer. Formatting-only edits normalized to the identical semantic response do not require recollection. Confidence is frozen atomically with the submitted response.

<a id="run-010"></a>

**RUN-010 — Reflection.** In ordinary practice, show the correction before optional reflection. A suggested error reason is displayed as a suggestion, not a selected learner diagnosis. “Not sure yet” is valid for explicit reflection tasks. Suggested, confirmed and later revised reasons are distinct fields. Reflection notes cannot alter the original response, score or correctness. Saving/closing must work during every reflection stage, including an explicit pre-feedback task.

<a id="run-011"></a>

**RUN-011 — Protected feedback.** During protected checks, show no per-item correctness, score, decisive hint, key, solution-bearing chart summary or error diagnosis. On completion, show dimension summaries and concept guidance. Reusable protected exact keys remain hidden in ordinary history. Practice this skill launches a separate instructional variant. Exact feedback may be exposed only for a separately designated retired/disclosed form, with a durable exposure event that permanently excludes that form from future protected selection; this is not the default release flow.

<a id="run-012"></a>

**RUN-012 — Reference/self-check.** Submit locks the recalled answer and persists the reveal state before showing a reference. The learner chooses Matched, Partly or Not yet. Display neither “Correct” nor “100%” for that self-rating. A supplied model reference does not become a factual scoring authority. A learner may pause after reveal and resume the same revealed state; reopening must never restore independent eligibility. Unrated revealed responses remain incomplete self-checks, not wrong answers.

<a id="run-013"></a>

**RUN-013 — Hint progression.** `nextHintIndex` starts at zero. Requesting a hint reveals that stage once and appends an assistance event with stage, clock offset and content version. Repeated taps while the disclosure is in flight do not reveal multiple stages accidentally. The next button says Next hint while stages remain. The final action is See worked solution, never a disabled dead end. Solution reveal creates a revealed/not-independently-scored outcome; it must not submit a fabricated answer. A fresh repair question is a new slot with its own evidence eligibility.

<a id="run-014"></a>

**RUN-014 — Skip.** Skip creates a durable skipped outcome with reason optional. It has no deterministic credit denominator or proficiency weight. The selection/exposure ledger still records the displayed item. Three skips are not automatically three incorrect answers. Repeated skipping may offer an easier or different activity, but never imposes a hidden skill penalty.

<a id="run-015"></a>

**RUN-015 — Next and repair.** Next reserves/activates exactly one next slot. The UI must not call the generator twice as view state changes. Retry similar preserves the original attempt, creates an explicit repair slot, selects a different semantic instance, and marks any repeated structure/context so the evidence reducer can limit independence. Repair work is shown as additional optional practice; it does not silently grow a promised fixed-count quiz or change a canonical daily block's completion contract.

<a id="run-016"></a>

**RUN-016 — Ending.** End session is distinct from completing all planned work. Completed attempts stay; unanswered slots have no score. The summary says “Ended after 3 of 10 questions,” not Completed. Unused already committed mixed-bank reservations remain consumed under the no-replacement policy. End is not Delete. Ending an unfinished protected check saves its accumulated evidence and exposure; it never rerolls unseen difficulty simply because the learner closes it.

## 4. Item checkpoint contract

<a id="data-001"></a>

**DATA-001 — Exact item snapshot.** Before presenting an item, persist the descriptor plus a versioned `ExerciseSnapshot` sufficient to reconstruct the exact learner-visible question: prompt, essential givens, table/diagram parameters, option IDs and original displayed labels/order, input schema, source citations when permitted, locale, units, assistance stages, feedback reference, display-policy flags, content hash, semantic fingerprint, structure ID and real demand vector. Images use app-managed content-addressed assets; no transient file URL is a permanent reference. Protected snapshots contain only learner-visible givens and a verified evaluator reference, never an exportable hidden answer key.

<a id="data-002"></a>

**DATA-002 — Evaluation identity.** Pin `evaluationContractID`, its digest and scorer version. A saved item is evaluated with that contract while valid. Updating the app must not silently score a displayed old question with a new key. If the old contract is known invalid, place the slot in unavailable/invalidated and preserve the draft; offer an unscored explanation and replacement according to mode. If the old valid evaluator cannot run, do not guess a score.

<a id="data-003"></a>

**DATA-003 — Current-item fields.** Persist the following together with the run revision:

| Field group | Required values |
|---|---|
| Identity | sessionID, slotID, stable attemptID, snapshotID/digest, reservation path index |
| Phase | answering/feedback/comparison/reflection state, exact reveal flags, committedAttemptID |
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
| Save | checkpoint revision, last acknowledged wall-clock date, commit-intent phase |

<a id="data-004"></a>

**DATA-004 — Time accounting.** Use a monotonic clock within a process. Add each active segment once; do not infer active duration from wall-clock time across a relaunch. Accumulated duration survives pause/close. Background, manual pause and ownership transfer stop active measurement. Returning to foreground starts a new answer-time segment only after explicit run resumption into an eligible visible answering state. Paused, feedback, comparison, reflection, loading and summary phases never accrue answer-solving time; separately labeled session-use time may include other active learning phases. Foregrounding does not reset earlier time. An unknown interval caused by termination is marked interrupted/unknown and excluded from clean speed evidence. The learning UI may show a measured lower bound if the last segment could not be recovered, with no false precision.

Persist confidence-control interaction intervals under EVD-009, union overlapping intervals and subtract them once from answer duration. Keep them in active sitting time for budget accounting. Do not claim that UI events measure private deliberation or pure thinking time. Timed fluency suppresses confidence; other conditions retain their explicit measurement scope.

<a id="data-005"></a>

**DATA-005 — Clock edge cases.** Timezone, daylight-saving and manual system-clock changes must not alter active duration or replay ordering. Wall-clock timestamps support display/scheduling; transaction sequence and explicit event relationships support ordering. Tests inject a fake monotonic clock and independent wall clock. No item can have negative time, nonfinite time or duplicate segment accounting.

<a id="data-006"></a>

**DATA-006 — Save guarantees.** Autosave drafts after a proposed 500 ms idle debounce and immediately on explicit pause, background transition, save/close, navigation away or ownership transfer where the OS permits. “Saved” means an acknowledged durable write. A sudden crash can lose unacknowledged keystrokes; the interface must not claim otherwise. Explicit Save & close flushes the current draft and all pending commit work before dismissal. If that fails, keep the screen and input intact.

<a id="data-007"></a>

**DATA-007 — Scratchpad portability.** Notes and drawing bytes are preserved independently of whether the current platform can render/edit both. Opening an iPad drawing on Mac and closing the editor must retain identical drawing bytes. Unsupported drawings show a retained-preview or “Drawing saved; editing is available on iPad” message, with text notes still editable. Clear operates only on the selected layer and has Undo during the session; it is never implemented by replacing the entire payload with empty drawing data.

<a id="data-008"></a>

**DATA-008 — Resume algorithm.** Resolve the stored run, verify its schema and ownership, reconcile pending commits, verify the current snapshot digest, apply content invalidation records, restore exact slot/phase/draft/assistance/time, then enable controls. Do not regenerate the current item from only seed+index. A committed slot resumes its exact policy-permitted phase: ordinary feedback, protected acknowledgement, reference comparison, reflection or summary, unless the previously acknowledged transition activated the next slot. Apply the display/exposure policy before constructing any visible or accessibility output. An unanswered draft can never be attached to a different item because of a deduplication fallback.

<a id="data-009"></a>

**DATA-009 — Language changes.** App chrome can follow a changed language immediately. A current saved question stays in its recorded content locale until the learner completes or explicitly restarts that item unscored. New items may use a supported new locale after recording the policy transition. Option identity, answer interpretation and decimal parsing follow the active item’s explicit response contract; they do not drift when Settings changes. Expose a plain-language explanation if question and chrome language differ.

## 5. Commit, crash and conflict behavior

<a id="data-010"></a>

**DATA-010 — Idempotent commit protocol.** The coordinator executes this sequence for deterministic attempts:

```text
submit(commandID, ownershipGeneration):
  reject stale ownership or incompatible phase
  validate response and required confidence
  freeze response + timing + assistance + snapshot digest
  result = evaluate(frozenResponse, pinnedContract)
  if needsClarification: retain editable draft, show entry guidance, return
  if invalidItem: retain original work, quarantine, enter unavailable, return
  if selfReported/unsupportedProse:
      if protected: preserve ungraded response, apply protected recovery policy, return
      else: enter declared self-check path, return
  receipt = makePolicySafeCommitPayload(result, assessmentProtection)
  persist prepared CommitIntent(stableAttemptID, payloadDigest, receipt)
  appendOrFindIdenticalAttempt(stableAttemptID, payloadDigest)
  persist checkpoint(phase = feedback or protectedAcknowledgement,
                     committedAttemptID = stableAttemptID)
  acknowledge intent
  publish rebuilt evidence/reward projections
  render the saved phase through its protected/self-check/practice display policy
```

The journal and evidence records may be in different configured stores. Do not assume SwiftData offers an atomic transaction across disjoint stores. The durable intent, stable attempt ID and reconciliation procedure provide recoverability. Where all records share one store, one transaction may replace the two-phase persistence without changing the observable contract.

The protected receipt stores the response, evaluator/contract reference, eligibility and the minimum versioned internal aggregate inputs needed for recovery. Solution-bearing `expectedAnswerSummary`, hidden canonical answers and worked explanations cannot be copied into generic checkpoint/journal/history payloads. Keep internal per-item outcome inputs behind the protected repository's access policy; user-facing exports use an opaque receipt/reference plus permitted aggregate results, not that internal object. Export/restore may require the verified local evaluator to rebuild restricted aggregates. This prevents accidental disclosure through nested Codable records; it does not claim cryptographic secrecy against an owner inspecting a fully offline executable.

A protected task whose response cannot be judged under its approved authority does not switch to reference/self-check in the middle of the form. Clarification may request supported notation without exposing a correct answer. If authority remains insufficient, preserve the authentic ungraded response, record no scored coverage, and use the form's preauthorized replacement/cap policy or an honest unavailable state. Do not create a zero score or reveal a reusable key to resolve evaluator uncertainty.

<a id="data-011"></a>

**DATA-011 — Crash boundaries.** Before intent persistence, resume the last acknowledged draft. After intent but before attempt write, retry the same attempt ID. After attempt write but before checkpoint update, find the identical attempt and advance the checkpoint without evaluating/awarding again. After checkpoint update but before UI feedback, render the saved phase through its display policy: a protected commit produces acknowledgement, never ordinary answer feedback; self-check restores reveal/comparison/rating state. At no boundary may Next create a duplicate attempt or the same response appear as both scored and unscored without an explicit correction record.

<a id="data-012"></a>

**DATA-012 — Payload conflict.** An existing identical attempt ID with a different response/result digest is a conflict, not a normal overwrite. Retain both raw records in recovery diagnostics, exclude the conflict from derived proficiency until resolved, show a recoverable save problem, and prevent duplicate XP. Local actor ownership and stable identities should make this exceptional. CloudKit object IDs are not sufficient for domain uniqueness; preserve the repository’s deterministic domain deduplication without deleting unseen peer objects during ordinary reads.

<a id="data-013"></a>

**DATA-013 — Derived state.** XP, completion, progress, review scheduling and proficiency update from committed authoritative records and versioned correction/exclusion events. They must be rebuildable. An interrupted replay cannot add XP twice. Optional confidence, reflection length, retrying a failed save, view appearance and navigating back never award points. Retain existing reward values during the reliability release; this specification changes correctness/idempotency, not the reward economy.

<a id="data-014"></a>

**DATA-014 — Save failure UI.** Show “Your answer is still here. NeuroForge couldn’t save it.” with Retry save and Keep working where safe. Provide Copy answer/Export draft for prolonged local failure; do not automatically send diagnostic data. An already scored-but-not-acknowledged response stays locked while retrying that commit; the learner cannot edit it into a new payload with the same attempt ID. A failed draft-only checkpoint may remain editable and produce a later revision.

<a id="data-015"></a>

**DATA-015 — Reservation atomicity and adaptive delivery.** Use two explicit reservation strategies. `fixedBlock` reserves the exact predetermined block when launch is durably accepted. `adaptiveItem` reserves and consumes one exact first item at accepted launch, then one exact next item per committed selection decision before presentation. A fixed challenge band may still use adaptive item selection for family/spacing; fixed-band does not imply fixed-block. The whole-epoch permutation is a candidate-priority recipe, not a promise to deliver contiguous positions despite changed eligibility. Seeking past an ineligible candidate leaves it unconsumed; use a consumed-position set plus stable decision IDs rather than a scalar cursor alone.

Commit the consumed position, chosen descriptor/snapshot, slot and decision record atomically within the local reservation store. The same decision ID must return the same chosen item after retries. Cancelling before durable acceptance consumes nothing; cancelling afterwards leaves the accepted identity consumed even if never displayed. Consumption and actual exposure are separate records. Advisory prewarming may prepare at most two unreserved candidates; it confers no lease and consumes nothing. An override may invalidate that advisory work. A presented or committed slot is immutable; an explicit Replace marks it replaced/consumed and reserves a distinct linked next slot. Already reserved unused fixed-block items remain consumed if replaced or abandoned. Protected adaptation follows a versioned preauthorized form policy, never an ad hoc easier item.

Maintain run-wide semantic exclusions across epoch boundaries so a quiz cannot repeat itself. Check capacity and finite termination before accepting a fixed requested block; for adaptive delivery, validate current feasibility and disclose later eligibility/exhaustion limits without inventing a completed count. The selector returns explicit failures; the coordinator cannot relax truth, protected exposure, source privacy or exact no-repeat to make the screen continue. Failure to build a candidate never returns an already accepted identity to the front.

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
| `AttemptEvidenceEnvelope` | attemptID+schemaVersion | Extends immutable attempt with band/demand/eligibility/context flags |
| `EvidenceDispositionRecord` | dispositionID | Append-only include/exclude/correct/supersede event with a reason and version |
| `ContentInvalidationRecord` | ruleID+contentVersion | Signed known-invalid item/family predicates; active until superseded |
| `LearnerBandProjection` | objectiveID+modelVersion | Disposable reducer output; source evidence references and freshness |
| `ReviewTaskRecord` | taskID | Due target, origin attempt, scheduling policy and task state |
| `SavedStudySetRecord` | setID | Explicitly saved local question collection; no cache TTL |
| `SavedStudySetItemRecord` | setID+itemID | Pinned local question/reference snapshot and practice history link |
| `LearnerBookmarkRecord` | bookmarkID | User’s private saved activity/question pointer and optional note |
| `LocalNavigationState` | windowID | Valid per-destination paths for this app run; disposable |

<a id="data-017"></a>

**DATA-017 — Privacy partition.** Built-in attempt evidence retains the app’s existing explicit private-sync policy. New source/AI study snapshots, private reference answers, local citations, source excerpts, source-review drafts and saved study collections remain device-local in this release. Introduce local envelopes where necessary rather than inserting private blobs into a cloud-configured model by convenience. Session resume envelopes and ownership journals are device-local; shared durable history is committed via the recoverable protocol. Use stable ID references across stores, never an unsupported cross-store object relationship.

<a id="data-018"></a>

**DATA-018 — Legacy scope.** Existing durable records keep their established policy and original bytes; this specification does not silently delete remote history or retroactively change cloud permissions. New model fields must not widen the content being uploaded. Migration inventories which legacy fields contain source-associated text and preserves their prior privacy treatment, with no new copying of local source indexes to durable/cloud records. New explicit local retention is not consent to sync or send a source to Question Writer.

<a id="data-019"></a>

**DATA-019 — Content storage.** Public built-in snapshots may deduplicate by content digest. Source snapshots deduplicate only within the appropriate local privacy scope; do not leak equality across users/accounts or source-policy boundaries. Retain blobs while an attempt, unfinished run or saved collection references them. Cache eviction may remove only unreferenced disposable objects. Garbage collection uses a transactional reference scan and retryable tombstones, not file age alone.

Temporary generated-set inventory expires for new launches after seven days. Explicit Save set creates a local durable collection retained until the learner deletes it. Expiry of temporary inventory does not delete a submitted attempt's permitted instructional snapshot or break an already accepted suspended run: that run pins the exact set members/assets required to finish its original contract. Continue remains available for that run, while New practice from the expired temporary set is unavailable unless it was explicitly saved. This pin does not make the set a permanent reusable collection. Once the run is ended/completed, retain only attempted-history, saved-collection and other genuine references; release unneeded unattempted inventory through garbage collection. Copy must distinguish “Temporary sets are available for new practice for 7 days” from retention of already saved answers/unfinished work. Explicit deletion still follows the linked-history/unfinished-work impact preview and user choice.

<a id="data-020"></a>

**DATA-020 — Size and corrupt input.** Check sizes before decoding images, drawings, archives or generated payloads. Preserve existing source-import limits unless a separately tested change replaces them. A malformed snapshot reports one unavailable history item; it must not crash or block all history. Corrupt private media can be exported as original bytes for user recovery but is never executed. No arbitrary code from imported sources is run.

## 7. Readable history and correction policy

<a id="data-021"></a>

**DATA-021 — Presentation is typed.** A `ResponsePresentation` renderer supports all eight response schemas. Numeric: value plus unit; choice: original selected label; multiple choice: selected labels; ordering: numbered original step labels; short text: original response; self-check: recalled text plus separate self-rating; claim/evidence: readable associations; trace: variable/value rows and selected rule label. Raw JSON remains an archive/debug representation. `normalizedResponse` is not a sufficient display substitute when it contains opaque IDs.

<a id="data-022"></a>

**DATA-022 — Complete review context.** Standard practice history shows original prompt, essential diagram/table/options, Your answer, Correct approach, Why, assistance used, and a fresh-practice action. Version/seed/scorer fields live behind Technical details. If original labels/representations are unavailable for a legacy record, explain the missing context and show whatever authentic content remains. Never hallucinate a diagram or label from an ID. Protected display restrictions apply before presentation and before accessibility text generation.

<a id="data-023"></a>

**DATA-023 — Historical evidence correction.** Never update an original `AttemptRecord` response, timestamp, score, confidence or key in place as a content repair. Add `EvidenceDispositionRecord` with originalAttemptID, applicable defect rule/version, disposition, old result digest, optional corrected deterministic result, corrected scorer/contract version, rationale, createdAt and stable idempotency key. The effective view presents original and correction when relevant; aggregate calculations consume the effective projection. Corrections are not new learner attempts and earn no XP.

<a id="data-024"></a>

**DATA-024 — Rules for each audited defect.**

| Defect | Safe historical treatment |
|---|---|
| Duplicate equivalent spatial choices | If exact snapshot/descriptor and response identify an equivalent valid choice, append deterministic full-credit correction. Otherwise exclude affected score with explanation. |
| Contradictory science interval prompt/key | Mark affected item invalid and exclude it from proficiency, accuracy denominators, speed and improvement claims. Do not infer what the learner would have answered to a corrected prompt. Preserve effort/participation history. |
| Accepted equivalent state got partial credit | If the exact old accepted-equivalence contract confirms validity, append full-credit correction; preserve original raw response. |
| `f`/`F` mathematical false acceptance | Correct only if exact original response and question roles are available under reviewed rules; mark prior result revised. No negative XP. |
| Rigid prose matching rejected a reasonable answer | Do not bulk use a language model to invent authoritative corrected grades. Use reviewed explicit equivalence where decidable; otherwise withdraw disputed grading and offer self-check/new practice. |
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

**RUN-019 — Cold launch and recovery.** Ordinary cold launch opens Today root with Continue when a valid unfinished local session exists. Explicit validated deep links override that start location. Avoid automatically restoring a problematic deep path after a hang. Disposable navigation state includes a schema version and is pruned when referenced records no longer exist. No route string can force decoding arbitrary code or bypass source/privacy checks.

<a id="run-020"></a>

**RUN-020 — Transactional route intents.** A route intent contains destination, typed path, optional source import/review continuation, and a unique intent ID. Dirty-work Save/Discard/Cancel applies to the whole intent. Cancel drops all its payloads; Save completes before navigation; Discard affects the draft only after an explicit choice. An external route arriving while answering offers safe pause/save and continuation; it never replaces the active item behind the learner’s back. Replayed callbacks with the same intent ID are idempotent.

<a id="run-021"></a>

**RUN-021 — Implementation constraint.** Use stable, state-driven navigation paths rather than resetting an entire nested view subtree with changing `.id` as the primary routing mechanism. This is the target architecture for the observed stale-detail defect; it is not a claim that the beta-OS hang's exact cause is proved. Apple documents state-driven paths and Codable restoration; choose typed enum routes whose decode/validation is under app control. [Apple: NavigationPath](https://developer.apple.com/documentation/swiftui/navigationpath)

<a id="run-022"></a>

**RUN-022 — Safe exit during work and failure.** Every visible phase accepts an exit intent. While disposable generation is running, cancel it and retain the previous acknowledged state; an accepted reservation remains consumed. During submit/self-check commit, queue close and reconcile the write. If a durable recovery intent exists but the destination store remains unavailable, permit close with a truthful “Answer waiting to finish saving” state and recover that exact intent on resume; do not show ordinary saved-success or erase the journal. Before any durable intent/checkpoint exists, retain the UI and offer Retry, Keep editing, Copy/Export recovery or explicitly Discard unsaved changes to the last acknowledged checkpoint. Discard never deletes committed attempts or a prepared intent. Explain exactly which unacknowledged text would be lost. These policies also govern dirty-work navigation and window closure; a convenience dismissal cannot bypass them.

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

**MIG-005 — Archive version.** Current full archive version is 17 and current oldest restorable version is 14. Add a new archive version for the new records; do not reuse 17 with an incompatible payload. The provisional next value is 18, verified against the repository at implementation time. Round-trip tests must cover 14–17 into the new reader and new→empty-new installation. Do not promise new archives can be restored by an old app. Unknown future archives fail with a readable update-required message before mutating stores.

<a id="mig-006"></a>

**MIG-006 — Export completeness and protection.** The full archive includes original attempts, disposition history, authentic review snapshots permitted by protection policy, saved local sets, notes/drawings, unfinished run envelopes and source links needed for honest reconstruction. User-facing exports never introduce reusable protected exact keys. A protected run can retain a verified evaluator reference; restoring without that evaluator yields unavailable/recovery rather than answer disclosure. Original source files follow the explicit export selection already supported; exports explain when only references/text are included. Record counts, stable identities and content hashes are independently validated.

Apply protected per-field allowlists before export, migration fallback decoding and accessibility presentation, not just by hiding a final view. Import never relaxes a protection/exposure flag because a newer evaluator or presentation adapter is missing.

<a id="mig-007"></a>

**MIG-007 — Restore transaction.** Validate version, schema, sizes, hashes, references, privacy scope and conflicts into a temporary staging store. Present a preview with counts and conflicts. On commit, apply idempotent inserts/merges, preserve originals, then materialize files and verify references. If materialization fails, retain a recoverable transaction and do not announce complete restoration. A retry must not duplicate attempts, sets or correction notices. Restore into a nonempty store requires explicit, deterministic merge policy; no silent destructive replacement.

Imported run envelopes enter suspended/read-only recovery first; they never acquire a writer merely by decoding. Exact writable continuation is permitted only when the original local owner identity can be verified and the installed ownership coordinator reconciles it with any existing run. A different-device or unverifiable-owner restore preserves original run/slot/provenance and draft for readable recovery, but offers a separate fresh practice run rather than mid-question continuation. It does not rebind a protected form into a second writable incarnation. Existing identical committed attempts deduplicate by identity/digest; conflicting run revisions are shown separately for recovery and never field-merged. The restore preview explicitly lists resumable versus read-only unfinished runs. This release deliberately does not add archive-based cross-device live handoff.

<a id="mig-008"></a>

**MIG-008 — Rollback.** Before migration, retain a protected recoverable store package using the app's existing recovery mechanism. A failed migration opens recovery/read-only mode, not an empty app. Rollback means restoring a compatible prior package with a compatible binary, not opening a V2 store with an old binary. Retain logs with redacted reason codes. Do not delete old models or migration code in the same release that first adopts V2.

<a id="mig-009"></a>

**MIG-009 — Cloud deployment.** Validate new durable metadata against a development container and then the production-equivalent schema before distributed sync testing. Additive local-only records must never appear in the durable configuration. Preserve existing entitlement/capability gates and explicit opt-in. Do not advertise cross-device feature readiness because an unsigned simulator build passes. No source excerpt or generated private payload enters CloudKit as an incidental consequence of a new relationship.

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
| Temporary set expires while its run is suspended | Continue retains the accepted run's exact content; New practice unavailable; attempted history remains readable and local. |
| Adaptive learner changes band after an answer | One next eligible identity reserved once, bypassed ineligible inventory unconsumed, prewarm discarded safely, no change to current/past items. |

These examples become automated regression tests plus selected installed-app checks in the [QA and delivery chapter](05_QA_and_Delivery.md). Tests that only search for a source string or submit the canonical key to its own scorer do not satisfy the behavioral contracts above.

---

<!-- Source: 05_QA_and_Delivery.md -->

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


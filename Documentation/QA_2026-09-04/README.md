# NeuroForge QA and improvement plan — 4 September 2026

**Decision: the app is not ready to be called polished, reliably adaptive, or fully quality-assured.** Its core architecture supports substantial useful functionality, and its existing automated tests pass. However, this audit reproduced incorrect grading, contradictory questions, extreme repetition, broken focused-session continuity, and confusing navigation. Fixing those issues will improve the experience more than adding more rewards, decorative motion, or nominal question volume.

This is a broad current-build QA pass combining live Mac and compact-iPhone use, all existing unit tests, the existing iPhone UI suite, seven additional investigative probes, and three independent source reviews. It is not a certification that every device, external integration, or question has passed independent human review.

**Direct answers to the product questions**

| Question | Assessment |
|---|---|
| Why does it feel clunky? | A correct answer requires submission, a separate confidence screen, then a separate feedback screen and Next. Some mistakes add a compulsory reflection before the explanation. The question disappears during these stages. Useful actions are spread across long card stacks and nested screens. |
| Why does it feel unprofessional? | Learner-facing history displays serialized JSON; feedback uses terms such as “Supported,” “immutable score,” and “durable scorer”; navigation can leave the wrong page visible; some answers are unfairly graded. Visual hierarchy gives decorative cards and metadata too much space. |
| Are all features working as intended? | No. Focused Save & close does not provide a usable resume path; later hints are unreachable; declared equivalent answers can receive partial credit; some questions contradict their own data. External services are not comprehensively certified by this pass. |
| Is it clear to a new user? | Partly. Three-step setup and a prominent daily start action are helpful. But Forge, cores, labs, paths, chapters, crossover, transfer and side quests create unnecessary vocabulary. The difference between XP, self-rating, scored accuracy and measured proficiency requires too much explanation. |
| Are the questions high quality? | Uneven. There are useful deterministic exercises, but this pass found objectively bad items, weak distractors, rigid answer matching, answer cues, and mislabeled activities. Quality checks need to establish truth and fairness, not just that the stored key passes its own scorer. |
| Are they useful? | Many target useful foundational skills: arithmetic, proportions, units, code state, causal reasoning and recall. Their usefulness is reduced by excessive scaffolding, shallow application and a weak mistake-to-repair loop. This audit does not establish improvement in general intelligence or real-world STEM performance. |
| Do levels adjust to the learner? | The scheduler adapts what to practice, and baseline selection responds to answers. Actual problem difficulty is not reliably adapted: the same seeded question at requested difficulty 0.2 and 0.9 was identical except for its difficulty metadata. Focused launches also use fixed default values. |
| Is it challenging enough? | It can provide novice drills. Sustained challenge for experienced STEM learners is not supported by the sampled content or difficulty implementation. Harder levels need more demanding reasoning, not merely different labels or tighter timers. This judgement needs validation with real novice/intermediate/advanced learners. |
| Is there enough variety? | There is broad advertised coverage, but severe imbalance inside several default mixed banks. Transfer is 98.6% one multiplication mechanic; Logic is 99% one trace mechanic. Different numbers are not enough to make repeated sessions feel varied. |

**What was actually tested**

Build: current working tree based on commit `f9b846015676e6b3bed7a4f7037e59475dda1b49`, version **1.0.0 (5)**, Debug, Xcode **26.6 (17F113)**. Mac: **macOS 27.0 beta (26A5425a)**. Phone: **iPhone SE (3rd generation), iOS 26.5 Simulator**. The pre-existing changes in `project.yml`, the Xcode project and two release documents were retained.

| Validation | Result | What the result establishes |
|---|---|---|
| Full existing Mac unit suite | **541 passed, 0 failed** | Existing scoring, content, scheduler, persistence, import, export, localization and integration-contract checks pass. |
| Existing compact iPhone UI suite | **4 passed, 0 failed** | Primary destination reachability; maximum-accessibility-size onboarding actions; quick-practice entry; declined Question Writer recovery. |
| New investigative probes | **7 reproduced the suspected defects** | Actual generator/scorer execution confirmed the findings below. These tests assert current defective behavior; their passing is evidence of reproduction, not release success. |
| Live Mac session | Correct numeric answer; wrong confident answer; hint; reflection; pause; focused save/reopen; progress/history | Correct/incorrect feedback, confidence, recorded attempts and progress worked in sampled paths. Focused resume, hints, history presentation and navigation failed or created serious friction. |
| Live offline question set | Created six-question starter; submitted explanatory answer; compared reference; saved self-rating | Offline creation and reference/self-check flow worked. This does not certify a live external model provider. |
| Live source workflow | Imported a synthetic Markdown file; indexing completed; opened detail and source review | Small local text import and recall entry worked; source remained Offline only. |
| Live compact iPhone | Fresh onboarding; baseline block entry; unscored preview; numeric/unit response; confidence; protected feedback; save/close | Sampled controls were usable; preview and protected-feedback distinctions were visible. Full baseline completion and every question layout were not manually tested. |
| Persistence after Mac recovery | Relaunch retained recorded progress, generated set and source | No loss of the sampled committed data was observed. This does not validate all failure/migration cases. |
| Content execution | Generated/scored representative defects and regenerated **4,000** default bank contracts | Exact bank identities matched their stored semantic fingerprints; counts below come from actual app code, not just a reconstruction. |

Evidence: [unit results](UnitTestResults.txt), [iPhone UI results](iPhoneSmokeResults.txt), [probe output](ExecutedProbeResults.txt), [content probes](ContentQAProbes.swift), [difficulty probe](AdaptiveQAProbes.swift), and [Mac hang sample](MacNavigationHang.sample.txt). Full Xcode result bundles remain at `/private/tmp/neuroforge-qa-20260904-unit-retry.xcresult`, `/private/tmp/neuroforge-qa-20260904-ios.xcresult`, and `/private/tmp/neuroforge-qa-20260904-probes.xcresult`.

The probes were temporarily compiled into the existing test target. The original test source was restored byte-for-byte and checked with `cmp`. No production application code was changed. The retained probe files live in this documentation directory and are not part of the normal test target.

**Highest-priority defects**

P1 means repair before trusting the affected feature or publishing a polished/adaptive product claim. P2 means material learning or usability improvement. “Executed” is a code-level reproduction; “live” is a user-interface observation; “source” follows the current implementation but was not fully reproduced in the UI.

| ID | Priority / evidence | Finding and user impact | Required fix / acceptance condition |
|---|---|---|---|
| QA-01 | P1 · executed | A spatial rotation question offers two identical correct coordinates, but one gets 0% credit. Seed 11: rotate `(10,10)` by 90° counterclockwise; two answers say `(-10,10)`. | Reject semantically duplicate options before publication. Exhaustively check symmetry/boundary coordinates; equivalent correct choices must never be marked wrong. |
| QA-02 | P1 · executed | Science questions claim uncertainty intervals overlap when they are disjoint. Example: A `[18,26]`, B `[27,35]`; the keyed answer still asserts overlap. **266/1,000** default science contracts have this contradiction. | Derive prompt, key and accessible description from the actual data. Specify the interval type and verify the inference separately; overlap alone is not a universal significance rule. Review and replace affected contracts. |
| QA-03 | P1 · executed | Valid retrieval answers get zero: `2*x` for derivative of x²; `4x` for derivative of 2x²; an ordinary correct explanation of the arithmetic mean. | Use typed numeric/unit or restricted symbolic answer contracts. For explanatory prose, use defensible concept rubrics or explicit ungraded self-check. Test plausible valid and invalid responses, including negation. |
| QA-04 | P1 · executed | Mathematical case-folding accepts `f(b)-f(a)` where the question requires antiderivative `F(b)-F(a)`. | Keep mathematical identifiers case-sensitive. Separate prose normalization from mathematical equivalence. |
| QA-05 | P1 · executed | A declared equivalent estimate response is marked correct but earns only **66.7%**, whereas the canonical wording earns 100%. | Give full credit for every declared accepted state. Calculate partial credit using accepted field equivalents. Stored correctness, score and progress must agree. |
| QA-06 | P1 · executed + source | Difficulty 0.2 and 0.9 produce identical prompt, answer schema, representation and identity: “Normalize 36 × 10^4 into scientific notation.” Only metadata changes. | Make difficulty control reviewed reasoning demands and parameter bands. Simulate improving/struggling learners and inspect the actual delivered tasks; do not validate only the requested number. |
| QA-07 | P1 · executed | Default mixed banks are overwhelmingly one mechanic in Transfer and Logic; science is 99.3% two mechanics. | Build balanced banks and enforce runtime family quotas. Test distributions and consecutive runs, not only uniqueness and one occurrence per family. |
| QA-08 | P1 · live + source | Quick Practice: save at question 3/5 with draft `17`; reopen the same entry; app starts a different question 1/5 with an empty response. | Persist a resumable focused-session identity, question path and draft. Show Continue practice. Verify exact continuation after close, relaunch and content updates. |
| QA-09 | P1 · source | Resumed items reset per-item elapsed time, hint and interruption counters. Aggregate session time alone survives; speed evidence can look faster and uninterrupted. | Persist current-item state. An item resumed after relaunch must be marked interrupted for speed evidence and retain previous active time/help. Test 20 seconds before save + 5 after = roughly 25 active seconds, with speed ineligible. |
| QA-10 | P1 · source | Some pre-answer context/representations explain the decisive answer even on protected checks. Invalid-proof context identifies division by zero; counterexample representation supplies the answer. | Separate essential givens from solution scaffolds; keep scaffolds in teaching/assisted modes. Independently audit every protected item for answer leakage. |
| QA-11 | P1 · live | Mac section switching from nested pages is unreliable. Document detail stayed visible with Settings selected; Back then revealed Settings. Leaving deeply nested answer review also produced a sustained layout hang requiring app termination. | Make each top-level destination own a stable navigation path and clear/pop the appropriate path on switching. Test every depth-to-section combination. Reproduce the hang on stable macOS before assigning its exact platform/root cause. |
| QA-12 | P2 · live + source | History shows `{"numeric":{"_0":{"value":"1000"}}}` as the learner’s answer, followed by scorer/template versions and a generic saved-key statement. | Render each response type in ordinary language and reconstruct choices, units, diagrams and explanation. Put diagnostics in an optional technical detail view. |
| QA-13 | P2 · live + source | Each answer replaces the problem with confidence, sometimes required reflection, then feedback. A paused required reflection offers only Resume. | Keep problem and response visible; collect required confidence inline; show immediate teaching feedback in ordinary practice. Save safely at every stage. |
| QA-14 | P2 · live + source | “Use a hint” becomes disabled “Hint shown” after the first clue, even though two-step hint ladders exist. A multiplication hint merely says “Name the operation before calculating.” | Reveal hints progressively, ending with a worked step/solution and a fresh repair question. Preserve assistance evidence. |
| QA-15 | P2 · source | Focused practice uses fixed difficulty, and switching timing mode also changes requested difficulty (0.4 for Accuracy first versus 0.58 otherwise). | Separate timing from challenge; offer Adaptive/Easier/Harder with honest current-band descriptions. A timing-only change must preserve challenge. |
| QA-16 | P2 · source | Durable proficiency updates ignore general item difficulty, unlike the live assessment model. Repeated easy successes can look like broad stable evidence. | Persist calibrated item difficulty/version and replay a consistent measurement model. Distinguish sufficient evidence, accuracy, proficiency and XP. |
| QA-17 | P2 · live + source | At default text on iPhone SE, the Energy selection breaks “Normal” across multiple lines; large status headers reduce question space. | Reflow the energy control and session headers, reserve usable action space, and inspect actual screenshots with keyboards and large text. |

Implementation references for QA-01–07/10 are in [ContentAudit.md](ContentAudit.md); QA-06/08/09/15/16 in [AdaptiveAudit.md](AdaptiveAudit.md); QA-11–14/17 in [UXAudit.md](UXAudit.md). Those reviewer reports preserve detailed file/line evidence and remaining hypotheses. Where they describe preliminary reconstruction or source-only work, the executed/live evidence in this main report supersedes that narrower status.

**Question quality and variety**

The default mixed bank is built by accepting the first 1,000 semantically distinct contracts. Large numerical parameter spaces therefore overwhelm fixed questions. A uniqueness test passes while the learner repeats the same operation.

| Default bank, General STEM | Actual composition | Implication |
|---|---|---|
| Transfer | 986 rate×time; the other six families share 14 items | A mixed transfer quiz will usually feel like repeated multiplication. |
| Logic & Debugging | 990 stale-derived-state traces; eight other families share 10 | Most apparent novelty is new numbers in one trace. |
| Scientific Reasoning | 557 mean/evidence mappings; 436 interval questions; seven other families have one each | Causal design, bias, hypotheses and scientific reading receive very little mixed-bank exposure. |
| Retrieval | 1,000 target contracts distributed across nine renderers; 101 use the same retrieve→compare→locate→retry ordering | Renderer counts look balanced, but some tasks do not actually test knowledge of their named target. |

These counts describe the current default mixed bank, not every selected-activity launch, every authored set, or the daily scheduler. Those routes have separate selection rules. No audited count establishes that all 7,000 questions are wrong, or that all activities lack variety.

| Lab | Useful foundation | Content improvements needed |
|---|---|---|
| Mental mathematics | Exact arithmetic, operation order, units and mental strategies | Real difficulty bands; meaningful estimation ranges; strategy choice; staged hints; correct equivalence credit. |
| Spatial | Coordinate transformations, cube-net validation, existing 3D/static views | Unique distractors; genuine labeled-object transformations and projection puzzles; reset/view controls; novel orientations. |
| Quantitative intuition | Proportions, natural frequencies, magnitudes and uncertainty | Ask learners to form assumptions and compare ranges; avoid doing every Fermi decomposition for them; improve units/estimate contracts. |
| Scientific reasoning | Causal claims, confounds, evidence and experimental design | Repair interval facts; balance families; real figures/short synthetic abstracts; competing-hypothesis predictions and experiment consequences. |
| Logic & debugging | Deterministic program execution, invariants, boundaries and counterexamples | Many program structures and bug types; boundary-test exploration; remove solution cues from independent checks; avoid one dominant trace. |
| Retrieval | Recall, source grounding and reference comparison | Accept defensible answers; target-specific cloze and equations; genuine figure questions; misconception-based distractors; more useful recall prompts. |
| Transfer | Applying familiar structure in different contexts | Multi-step unfamiliar scenarios with a genuine representation/assumption change; more than renamed rate products; explicit transfer objectives. |

Some activity names overstate their depth. A “3D Object Rotation” can reduce to a coordinate rotation with z unchanged; “Paper Sprint” can ask for a fixed reading order without an abstract; “equation reconstruction” can display a generic formula unrelated to the concept. Either rename these accurately or implement the promised task.

Set an editorial standard for each family: objective, prerequisites, real difficulty dimensions, independently verified answer, plausible distractors, accepted-equivalence rules, assistance policy, useful worked explanation, and an unseen application item. Review the parameter domain, not only one attractive sample. Content integrity/signatures establish that a payload is unchanged; they do not establish that its answer is true.

**Interactive capabilities to prioritize**

The app already has 3D orbit/static views, scratchpads, pause/checkpoints, reporting, history, progress filters and several response schemas. Preserve these foundations. The missing depth is the connection between an error, understanding, practice and later retention.

| Priority | Interaction | Specific behavior and purpose |
|---|---|---|
| First | Progressive help and repair | Hint → smaller worked step → explanation → fresh similar item. This makes a difficult question teachable without abandoning the session. |
| First | Visible resume and review | One-tap Continue; mistake queue; retry-similar; bookmarks; comprehensible original question/answer/diagram. Review creates a new attempt, never rewrites old evidence. |
| First | In-session challenge adjustment | Easier/Harder/Keep this level, separate from timing. Explain the change briefly and choose genuinely different content demands. |
| First | A continuous answer surface | Retain the problem while answering, rating confidence and reading feedback. Keep primary actions reachable; support keyboard submission and accessible validation. |
| Next | Step-through debugging | Predict next state, advance execution, inspect variables, choose a minimal fix, then run visible boundary cases in the existing restricted interpreter. |
| Next | Experiment and evidence interaction | Assign control/confound/outcome roles, predict competing explanations, choose an experiment, and inspect a synthetic result. Keep a tap/keyboard alternative to dragging. |
| Next | Data prediction and interpretation | Read real plotted data, mark a predicted range, reveal a result, inspect points/units, and explain which claim is supported. |
| Next | Spatial manipulation | Reset/view presets, explicit axes, constrained rotations and labeled faces. Restrict assistance appropriately during independent checks. |
| Next | Real reconstruction | Reorder actual reasoning steps, fill meaningful equation slots, map claims to relevant evidence; retain accessible list/button equivalents. |
| Next | Problem beside scratchpad | Split pane on iPad/Mac and expandable panel on phone so working does not hide the question. Preserve drawings on platforms that cannot edit them. |
| Later | Durable saved study collections | Explicit local Save set, folders/favorites and spaced review. Distinguish saved content from the current seven-day temporary generated payload. |

Do not prioritize leaderboards, more currencies, more top-level screens, or more decoration until the learning loop and grading are reliable. Motion should communicate selection, progress and cause/effect, with Reduce Motion support. Apple’s feedback guidance likewise favors feedback integrated into the interface and proportionate interruption. [Apple Human Interface Guidelines: Feedback](https://developer.apple.com/design/human-interface-guidelines/feedback)

**Improvement plan with completion gates**

The sequence below is ordered by dependencies. Effort should be estimated after each work package is scoped; adding calendar promises before the content redesign is understood would be unreliable.

| Stage | Work package / responsible disciplines | Concrete deliverables | Gate before proceeding |
|---|---|---|---|
| 1 — Restore trust | Training engine + subject reviewer + QA | Repair/quarantine bad items; symbolic/prose grading contracts; equivalent-state scoring; protected-content review. Version changes and preserve old attempt identities. Identify previously affected evidence for a transparent correction policy. | Zero duplicate correct options or stimulus/key contradictions in bounded domains; accepted equivalents earn identical credit; known false positives/negatives regressions pass; protected checks contain no solution cues. |
| 1 — Restore continuity | App/state engineer + QA | Focused session IDs and resume entry; full item checkpoint; navigation path repair; preservation of old drawing data. Investigate Mac layout hang. | Drafts, question identity, position and counters survive close/relaunch; interrupted items cannot enter clean speed evidence; every nested destination can switch sections without stale content or hangs. |
| 2 — Make adaptation real | Learning design + engine engineer | Reviewed difficulty bands per mechanic; separate timing; bounded practice staircase; consistent durable assessment model; visible overrides. | Simulated weak/strong/mixed learners receive different actual demands; same input replays consistently; timing changes do not silently change difficulty. Human pilot verifies that intended bands differ in challenge. |
| 2 — Rebalance content | Content engineer + editors | Stratified bank admission; mixed-session quotas; real scenario/mechanic expansion; target-specific distractors and reconstruction. | Proposed initial mixed-quiz rule: at least four applicable families in a 10-item general quiz, no more than two consecutive items from one family, and no family above 35% over a rolling 100-item balanced mix. Intentional focused drills are exempt and labeled. Tune these proposals for educational coverage. |
| 3 — Repair the learning flow | Product designer + SwiftUI engineer | Persistent question/response/feedback surface; inline confidence where required; useful staged hints; explanation-first ordinary error feedback; save at every phase; contextual repair questions. | Routine answering has no unnecessary full-screen interruption; learners can access a useful explanation immediately in practice, then demonstrate understanding on a fresh item; every stage exits safely. |
| 3 — Make history useful | Persistence + UI engineer | Versioned exercise/feedback snapshots; readable responses; original diagrams/options; mistake review and retry-similar. | Each response schema is understandable after relaunch/content update; no JSON or raw option IDs in normal UI; re-practice creates separate evidence. |
| 4 — Simplify and polish | Product/content design + accessibility QA | Compact Today with one next action and a short reason; searchable activities/recent practice; consistent names; categorized Settings; reduced card density; proper empty/loading/error states; labeled editors/sliders. | First practice requires at most two clear decisions after setup; resume is one visible action; no broken labels/covered controls at supported compact widths and accessibility sizes; keyboard and VoiceOver paths verified. |
| 5 — Add depth and validate learning | Learning designer + engineers + representative learners | One polished interactive activity per major domain; novice/intermediate/advanced pilots; delayed-recall and unseen-application evaluation. | Each new interaction has a scorable purpose and accessible equivalent; user testing shows fewer wrong turns and clearer explanations; learning claims match measured outcomes. |

Keep existing answer records immutable. When correcting bad historical scoring or difficulty metadata, retain original content/scorer versions and create an explicit correction/supersession record or exclude invalid evidence with an explanation. Do not silently recompute history against new keys.

**Release and QA matrix still required**

| Area | Remaining work / current boundary |
|---|---|
| Every interaction, every platform | Complete full sessions for all eight response schemas and all seven labs on phone, iPad and Mac; exercise skip, report, hint, reflection, completion and resume at each stage. The current UI suite is only four smoke tests. |
| Accessibility | Live VoiceOver, Full Keyboard Access, Switch Control, Voice Control, touch targets, focus after feedback/errors, Reduce Motion, contrast and all large-text screens. AX-tree inspection and an onboarding geometry test are not auditory accessibility certification. |
| Layout | Small/large phones; iPad portrait/landscape/split view; Mac minimum window; English/Japanese; software keyboard visible. Current source still has rigid session action/number rows and a fixed-width Progress hero. |
| Performance and scale | Measure cold/warm launch, time to first problem, navigation latency, large libraries/history, import cancellation, memory, energy and long sessions on reference physical hardware. Isolate the observed Mac nested-navigation hang on stable OS builds. |
| Complete lifecycle | Full daily circuit, baseline, reassessment, weekly mission, day rollover, timezone change, profile mutation after completion, exact relaunch continuation. Existing model tests cover many contracts; a complete installed-app pass remains necessary. |
| Real Question Writer | Installed signed Shortcut and actual provider: success, cancellation, missing setup, no network, malformed output, callback/relaunch and source-consent bounds. This pass verified offline creation and simulated declined-URL recovery only. |
| CloudKit | Signed devices/accounts, production-equivalent schema, two-device convergence, offline resume, account switch, conflicts, document originals and deletion. Source and mocked tests cannot certify the service. |
| Other system integrations | Physical notification delivery/denial, widgets/App Group refresh and deep links, Spotlight indexing/purge, background behavior, sound/haptics and Pencil. |
| Import/export/recovery | Live corrupt/large/scanned sources, sandbox permissions and OCR, disk-full rollback, export→empty-install restore, supported prior versions, destructive deletion/retry with disposable data. Small Markdown import and the automated contracts passed here. |
| Editorial/localization | Independent expert review of every family and protected item; native Japanese review; task instructions, units, formula equivalence and plausible distractors. Do not equate catalog counts/lint success with educational correctness. |
| Human usability and learning | Recruit representative novice/intermediate/advanced STEM learners. Observe hesitations, abandonments, mistaken taps, disputed grading, perceived challenge and explanation usefulness; then measure delayed retention and unfamiliar application separately. |

Proposed product measures: first meaningful answer time; taps/screens per item; abandonments after confidence/reflection; successful resume rate; contested grading by family; hint-to-independent-success rate; family concentration; success rate by actual difficulty band; delayed retention and unseen transfer. Prefer local opt-in research or test instrumentation; do not add analytics/data transmission implicitly.

**Observed visual and navigation evidence**

[iPhone SE Forge screenshot](iPhoneSE-Forge.png) shows the current Energy picker splitting its selected label and the amount of space devoted to headers/cards. This is a default-text live screenshot, not the automated maximum-text onboarding test.

Mac hang reproduction: Progress → Explore details → Mental Mathematics → Answer history → saved answer → Sources sidebar. The interface became unavailable, the process stayed around 99% CPU for several minutes, and the sample repeatedly captured AppKit/SwiftUI layout and `SkillDetailView` rendering. Terminating the QA process and relaunching recovered the app. Direct Forge → Sources then worked. A separate Document-detail → Settings transition retained the old detail until Back. The exact cause of the high-CPU hang remains unproven, especially on the beta Mac OS; the stale-detail behavior was directly visible.

Audit-created local state remains available for inspection: two Mac mental-math attempts and their checkpoints, one new six-question offline starter set with one saved self-check, the [synthetic source](SyntheticSource.md), and a partially completed iPhone numerical baseline after its practice preview. Existing sources and histories were retained. No real external model run, cloud sync change, or destructive data deletion was performed.

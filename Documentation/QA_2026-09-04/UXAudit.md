# NeuroForge UX, clarity, interaction and accessibility source audit — 2026-09-04

Scope: independent source inspection of current Onboarding, Forge/Today, Practice, sessions, Progress, Sources, AI Studio, Settings, navigation and design system. No application edits, build, tests or UI operation were performed by this auditor. Parent auditor owns live UI/testing. A later parent update directly confirmed the Mac answer/confidence/reflection flow, one-use first hint, reflection pause/close restriction, and raw JSON answer history; these observations are attributed below. “Confirmed source behavior” means the behavior follows directly from reachable UI/state code; layout/accessibility outcomes still need device or assistive-technology verification. Prior August 30 audit was read only as a checklist, not accepted as current proof.

## Main conclusion

The app has far more functionality than the interface helps a learner understand. It feels like a collection of administrative forms and evidence dashboards wrapped in game styling. The biggest friction is in the core answer loop: answer → separate confidence page → sometimes mandatory reflection → separate feedback page → next answer. Repeated context changes, large card stacks, inconsistent terms, and weak post-error teaching create more effort around each question than necessary. More decorative animation would not address this.

Current implementation already has useful interaction: native 3D orbit and static equivalents, PencilKit/typed scratchpad, progress filters and accessible chart data, response validation, pause/checkpoint/resume, source import recovery and deduplication, source review, reports, generated-set history, answer history, plan replacement/undo history, and baseline previews. These should be preserved and made easier to reach. Claims that the app has no history, no 3D, no search reset, no draft guard, or no compact-layout remediation would be inaccurate against current source.

## Prioritized findings

### UX-01 — High — The ordinary answer loop interrupts the learner repeatedly

Evidence: parent live Mac QA confirmed the separate confidence page. `Sources/Features/Training/UniversalSessionView.swift:424` always moves submitted answers to `.confidence`; `:1765` renders a whole separate confidence screen; `:557` can route to reflection; `:1857` requires Save and view explanation; `:1964` then requires Next challenge. The confidence screen contains no prompt or response recap (`:1765–1789`).

Impact: even a quick correct answer needs Submit, confidence choice, then Next; a triggered error adds another screen and another required decision. The learner must hold the question/answer in memory while the UI replaces it with metacognitive controls. This is a direct source-backed explanation for “clunky.”

Recommendation: keep question and submitted answer in place. Place confidence choices inline before commit when needed, show feedback in the same surface, and use a persistent Next action. For low-stakes fluency sets, sample confidence where product/evidence policy permits; preserve required confidence in calibration/assessment. Do not turn confidence into a meaningless default just to reduce taps.

Acceptance: routine correct item requires no full-screen context change; original prompt/response remain available in feedback; full keyboard journey works; intentional confidence evidence is retained.

### UX-02 — High — Reflection gates the explanation and preselects a diagnosis

Evidence: `UniversalSessionView.swift:563–569` sets a suggested error code as the selected reason and enters reflection; `:1807` says “Choose what may have happened before viewing the explanation”; `:1857–1865` offers only Save and view explanation. `:583–604` cannot move to feedback until the reflection is saved.

Impact: users may not yet know why they were wrong. A preselected reason can be saved without real reflection, producing a form-completion ritual that also weakens the usefulness of error-pattern data. The user can pause but cannot save and close from this stage: `UniversalSessionView.swift:2108–2117` replaces Save & close with “Complete the required reflection before closing this item.” Parent live Mac QA confirmed this restriction. There is no direct “Show explanation first” in this screen. This restriction is especially unnecessary because checkpoint code already supports a pending reflection attempt, trigger, selected reason and note (`:815–839`), and runtime initialization restores reflection (`:244–262`).

Recommendation: for ordinary practice, show a concise correction first, then offer one suggested repair strategy and optional reflection. Preserve explicit pre-feedback reflection only for a clearly explained transfer/calibration exercise; include “I’m not sure yet” where valid. Persist a distinction between inferred and user-confirmed error reasons.

Acceptance: ordinary mistakes can reach teaching feedback immediately; only explicit user confirmation enters the self-reported error dataset; the selected reason can be revised after seeing the explanation without changing the original score.

### UX-03 — High — Progressive hints exist in the model but are unreachable in the session UI

Evidence: parent live Mac QA confirmed the generic first hint “Name operation before calculating” and no next-hint action. `UniversalSessionView.swift:314–315` returns only `exercise.feedback.hintLadder.first`; `:471–475` allows a single `showHint` transition; `:1404–1405` disables the hint button permanently after use.

Impact: a learner who does not understand the first clue has no second step, worked example, or graduated help. The obvious escape is skip/report/guess. This is a real capability gap, not merely cosmetic polish.

Recommendation: implement Hint 1 → Hint 2 → Worked step → Solution with explicit support use recorded. Keep protected assessment restrictions intact. Follow a helped answer with a fresh similar question at an appropriate difficulty.

Acceptance: every authored hint-ladder element is reachable in order; no hint leaks into protected scoring; support count reflects actual help used; after error, a fresh repair item is available without recreating the entire session.

### UX-04 — High — Focused practice is not consistently learner-adjusted, and timing controls silently change difficulty

Evidence: `Sources/Features/Train/TrainCatalogView.swift:694–721` passes `targetDifficulty: mode == "Accuracy first" ? 0.4 : 0.58`. Thus changing the label from Accuracy first to Untimed changes the requested difficulty as well as mode. Catalog-specific start passes `activity.defaultDifficulty` (`:50–61`), and the default selected focus can launch ten items (`:36`, `:547`). `AIStudioView.swift:175` starts difficulty at 0.5, while choosing a starter overrides it with `starter.defaultDifficulty` (`:1083–1091`). These observations concern the request boundary; the separate adaptive audit should establish downstream difficulty handling.

Impact: learners cannot predict challenge from the UI, and repeated focused practice may stay too easy or too hard despite improving performance. The user sees no “matched to your level” explanation or easier/harder correction in this flow.

Recommendation: separate Difficulty (Adaptive, Easier, Harder) from Timing (Untimed, Optional target). Use the current skill estimate as the default for focused/catalog practice, subject to validated content-band availability. Explain the current band with a concrete example and permit a quick correction after a few answers.

Acceptance: a timing-only change preserves requested content difficulty; different learner estimates create appropriately different default practice requests; manual overrides are visible and reversible; unsupported difficulty bands are not relabeled “Expert.”

### UX-05 — High — Completed-answer history is present but does not preserve the teaching experience

Evidence: `ProgressDashboardView.swift:2026–2040` constructs “Scoring explanation” from generic durable-scorer/result/key boilerplate. The read-only detail at `:2306–2366` presents metadata, exact prompt, exact response, this generic key, and an integrity note. The snapshot at `:1861–1881` does not carry original feedback explanation, decisive step, diagrams/tables/options or citations. There is no retry-similar, bookmark, or add-to-review action in this view.

Impact: the learner can inspect a ledger but cannot conveniently relearn a mistake. Some prompts depend on representations/options that are not restored by this detail. The phrase “Scoring explanation” overpromises compared with a result plus key.

Recommendation: persist a versioned, learner-facing exercise/feedback snapshot sufficient to replay the original educational context. Present My answer, Correct approach, Why, and Try a similar question. Keep original attempts immutable; create a new practice attempt for remediation. Add an optional mistake review queue and bookmarks.

Acceptance: a history item involving a table, choice options or spatial diagram remains understandable after relaunch and content updates; original teaching explanation is available; re-practice creates new evidence without altering the old record.

### UX-06 — Medium/high — Valuable routes are buried below many competing sections

Evidence: Today renders header, prescription, plan, quick practice, ability cores, weekly mission, milestones, then side quests (`TodayView.swift:43–51`). Starting skill check lives in the final side-quests section (`:888–896`). Practice renders recommendation, foundation paths, crossover, then the catalog/AI creation section (`TrainCatalogView.swift:151–165`, `:227–243`). Each lab renders all focus cards before setup and Start (`:572–642`). Progress puts skill map behind Explore details (`ProgressDashboardView.swift:127–147`); answer history is then reached through a skill detail (`:1420–1443`).

Impact: high feature count is experienced as scrolling and discovery cost. A new learner can miss the most useful calibration step; a returning learner needs multiple decisions to reach their previous work or an exact activity.

Recommendation: Forge should prioritize one next action, its reason, and a compact “What else” section. Elevate incomplete starting check contextually. Give Practice a direct search with exact-activity results plus recent/resume/favorites. Put History/Review beside Progress overview. Use progressive disclosure for the focus catalog and a sticky Start footer.

Acceptance: first practice starts within two explicit decisions after setup; any recent activity can resume from one visible action; the starting check is discoverable without scrolling through milestones; exact activity search lands on that activity rather than only its parent lab.

### UX-07 — Medium — Information architecture uses too many names and exposes internal terminology

Evidence: top-level destinations are Forge, Practice, Progress, Sources (`PersistenceModels.swift:4857–4863`), but generated-source handoff says “Import in Library” (`AIStudioView.swift:675`) and source privacy copy refers to Library (`:727`). Session feedback says “saved separately from the immutable score” (`UniversalSessionView.swift:1925`) and chain replay says “score-preserving”/“seeded steps” (`:1936`). Skill detail uses “cross-module skill attribution” and “Protected assessment” (`ProgressDashboardView.swift:1408–1415`). The product simultaneously uses abilities, labs, modules, paths, cores, chapters, crossover, transfer and side quests.

Impact: brand/game vocabulary does not consistently map to actions; implementation language crowds out learning guidance. This contributes to the impression of an internal prototype.

Recommendation: use a consistent user vocabulary: Today, Practice, Review, Progress, Sources; “skill” for an ability; “activity” for a practice type; “round” or “section” consistently within sessions. Keep playful Forge branding if desired, but pair it with Today. Move scoring/integrity mechanics into optional details. Fix “Library” navigation copy to match Sources.

Acceptance: a copy inventory contains no mismatched destination names; five representative learners can explain what they will do next and whether it affects their skill estimate without reading methodology.

### UX-08 — Medium — Card styling and gamification compete with the task hierarchy

Evidence: `Theme.swift:285–304` applies material, rounded border and shadow for each ordinary card; `:307–349` adds another gradient/glow card treatment. Today renders eight major stacked sections (`TodayView.swift:43–51`), including four milestone tiles (`:851–883`) and ability cores. Progress repeats Forge journey/XP near the top (`ProgressDashboardView.swift:114–118`, `:236`).

Impact: most surfaces carry equal weight, large rounded containers, icon tiles, eyebrow labels and explanatory subtitles. This is a design diagnosis from composition, not a measured contrast or performance failure. Users must visually parse containers instead of quickly identifying the next action.

Recommendation: establish three levels of hierarchy: primary task surface, plain supporting rows, optional detail. Reduce shadows/gradients and redundant headings, reserve accent color for selection and action, and make XP/milestones a compact optional layer. Review spacing/density separately for phone and Mac.

Acceptance: in grayscale, primary action and current task remain obvious; one accent action per section; no more than one hero surface per screen; screen captures at minimum width and large text are reviewed, not just source layout tests.

### UX-09 — Medium — Current compact/Dynamic Type risks remain in main-session and Progress layouts

Evidence: session action controls use unconditional HStack for Hint + Skip + Spacer + large Submit (`UniversalSessionView.swift:1402–1421`); numeric value/unit row also uses unconditional HStack (`:1462–1489`). Progress overview uses HStack with a fixed 120pt ring, 24pt gap and body text (`ProgressDashboardView.swift:173–233`); skill-detail metrics use three simultaneous columns (`:1389–1393`).

Impact: source-backed layout risk at small width, translated strings, software keyboard and accessibility sizes. This auditor has not reproduced clipping. Prior onboarding geometry and tab-bar overlap were addressed in current code and must not simply be repeated as verified current bugs.

Recommendation: use ViewThatFits or size-aware vertical arrangements; persistent submit footer with reserved safe area; hide decorative ring or shrink/reflow it at accessibility sizes. Verify content with keyboard visible and scrolling.

Acceptance: iPhone SE/320–375pt, landscape, split-view iPad/Mac, English/Japanese and AX5 remain usable; no horizontal clipping, covered primary actions, inaccessible focus or tiny controls.

### UX-10 — Medium/high — Important form controls still lack explicit accessible identity

Evidence: main session short-answer TextEditor (`UniversalSessionView.swift:1544–1551`) and recall TextEditor (`:1570–1578`) have no `.accessibilityLabel`, unlike the scratchpad editor which explicitly has one (`ScratchpadView.swift:127–131`). AI Studio difficulty slider is unlabeled (`AIStudioView.swift:649–652`). Reflection reason buttons have no minimum tap height (`UniversalSessionView.swift:1887–1901`), unlike choice controls which specify >=54pt (`:1684`).

Impact: concrete source accessibility omissions; the exact VoiceOver announcement and rendered hit targets require live verification. An adjacent Text label is not a reliable substitute for explicit labeling of a custom editor or unlabeled Slider.

Recommendation: explicit names, values, hints, 44pt target areas, error announcement/focus handling, and completion focus. Ensure source text/diagram descriptions preserve equivalent task information without revealing answers.

Acceptance: VoiceOver user can locate answer editor, identify difficulty and adjust it, submit, receive feedback and advance without sight; all reason controls meet target area requirement; verify with live VoiceOver, keyboard-only, and Switch Control as available.

### UX-11 — Medium — Interactions are largely form entry; rich learning manipulation is shallow

Evidence: response renderer switches among number/text/choice, arrow-up/down ordering, nested checklists and logic fields (`UniversalSessionView.swift:1459–1665`). Ordering only exposes stepwise arrows (`:1497–1540`); claim/evidence repeats the entire evidence set per claim (`:1609–1632`). Spatial interaction supports orbit and static 2D (`SpatialDiagramView.swift:56–85`, `:279–296`) but no explicit reset/viewpoint/axis controls. Progress chart defines marks/axes and an accessible data disclosure but no selection/inspection (`ProgressDashboardView.swift:378–425`).

Recommendation, in useful order: (1) progressively revealed hints/repair; (2) drag ordering with existing keyboard arrows retained; (3) claim/evidence mapping with tap equivalents; (4) code trace stepper and editable trace state; (5) chart inspection and prediction before reveal; (6) spatial reset/view presets and constrained transform manipulation. Use manipulation to teach/test a specific skill, not animation for its own sake.

Acceptance: new interaction has equal keyboard/assistive path, produces deterministic scorable responses, and improves time-on-task/comprehension in usability testing. Preserve existing 3D orbit and PencilKit capabilities.

### UX-12 — Medium — AI creation looks like a form-builder setup, not a guided learner task

Evidence: AI Studio lists recent sets, starter sets, Customize, all material, Create, then result (`AIStudioView.swift:213–224`). Customize asks lab, field, question form, count, topic, objective and difficulty (`:621–660`). Material iterates every imported document with no search/pagination (`:678–704`). External setup copy asks the user to edit a Shortcut's Use Model action (`SettingsView.swift:391`).

Impact: creating a tailored set requires too much expertise about the app's model and question taxonomy. The AI source list grows linearly with library size. External Shortcuts are a legitimate platform constraint but add obvious context switching and setup friction.

Recommendation: start with “What do you want to practice?” plus optional source; infer suggested lab/form/level, expose Advanced options on demand. Search/select source in a sheet. Provide a setup walkthrough and reliable offline fallback for Question Writer; current missing/failed Shortcut recovery code should be tested, not assumed broken.

Acceptance: create a useful starter/topic set with two decisions; all implied source permissions remain explicit; 100-source library remains fast/findable; failed/cancelled/missing external flow returns to a usable state.

### UX-13 — Medium — Reusable generated study sets expire after seven days

Evidence: AI Studio says “Continue a set you created in the last seven days” (`AIStudioView.swift:422`); `AIGenerationRecord.defaultPayloadTTL` is seven days (`PersistenceModels.swift:700`); result recovery requires nonexpired payload (`:751`) and AI Studio purges expired payloads on open (`AIStudioView.swift:267`). Metadata/attempt history remain, but question content may not (`:477`). No pin/favorite/save-permanently control was found in current feature source.

Impact: sensible cache/privacy policy can conflict with learner expectation of “my saved question sets,” reusable course material, and longer spaced review. This is current intended behavior, not a data-loss defect claim.

Recommendation: distinguish Temporary set from Saved study set. Show retention before creation and permit explicit local retention/save-to-collection if product privacy policy supports it. Keep per-set delete and export behavior clear.

Acceptance: user can predict which content will remain after a week; a deliberately saved collection remains reviewable on schedule; temporary content expires without misleading “Practice” actions.

### UX-14 — Medium — Settings are a long mixed control dashboard with no search

Evidence: `SettingsView.swift:107–128` lays out profile/training, AI, sync, system controls, export, reports, methodology then deletion in adaptive cards. Accessibility/language profile settings require “More practice & accessibility settings” (`:312–317`). There is no searchable modifier or settings query in the Settings view.

Impact: routine preferences, system setup, data management, methodology, and destructive actions occupy the same information level. A setting may be technically reachable but difficult to discover.

Recommendation: a searchable categorized list: Practice, Accessibility, Notifications, Question Writer, Data & sync, About. Surface only current actionable integration issues. Use a separate details screen for technical state.

Acceptance: find change-language, hide timer, adjust pace, export, and import recovery quickly by navigation and search; current state is visible; saving a preference preserves current plan/session contracts.

### UX-15 — Medium — Scratchpad occupies a separate sheet and hides the problem

Evidence: main session opens scratchpad as a sheet (`UniversalSessionView.swift:1127`); `ScratchpadView` receives only a text binding, renders Notes/Draw, and contains no question context (`ScratchpadView.swift:36–125`).

Impact: solving a table/equation problem requires remembering or repeatedly returning to the stimulus. This wastes the benefit of iPad/Mac screen space.

Recommendation: split problem/scratchpad pane on large screens, expandable inline panel on phone; preserve question/diagram preview. Add explicit clear undo or recoverable clear.

Acceptance: user can see original problem while writing on iPad/Mac; sheet/pane closing preserves drawing; clear is reversible without losing a session.

### UX-16 — Functional risk to hand off — Mac scratchpad may discard imported/synced iPad drawing payloads

Evidence: payload supports `drawingData` (`ScratchpadView.swift:8–26`) and decoding runs on all platforms; drawing is retained in view state only for iOS (`:64–67`); macOS `persist()` always encodes `drawingData: Data()` (`:155–160`), and persistence runs onDisappear (`:124`).

Boundary: this auditor has not confirmed a supported cross-platform sync/restore path that places an iPad drawing into a Mac editable checkpoint. If such a path exists, opening and closing the Mac scratchpad destroys the drawing bytes. Do not mark as reproduced until transport is confirmed.

Recommendation: preserve unrendered drawing payload on Mac and explicitly describe unsupported editing. Test iPad export → Mac restore → open/close → re-export round trip.


### UX-17 — High — Answer history exposes serialized enum JSON instead of the learner's answer (UI confirmed)

Observed: parent live Mac QA answered 57 × 19 incorrectly with 1000. Both Answer history and saved-answer detail displayed `{"numeric":{"_0":{"value":"1000"}}}` as the learner's answer. The detail foregrounded template/scorer/validator versions, then offered a generic durable-scorer/key statement rather than the original teaching explanation. Numeric leakage and both rendered surfaces are directly UI-confirmed; other schema coverage below follows the shared source path.

Root cause chain:

1. `Sources/Persistence/PersistenceModels.swift:3041–3044` serializes the entire `NFExerciseResponse` enum with `JSONEncoder`. JSON encoding normally succeeds, so `result.normalizedResponse` is only an error fallback, not the presented answer.
2. `:3045–3050` stores that JSON in `AttemptRecord.response`, a field also treated as learner-facing text.
3. `Sources/Features/Progress/ProgressDashboardView.swift:1888` copies the string unchanged into `NFReadOnlyAttemptSnapshot.response`.
4. History row `:2270` interpolates it into “Answer: …”. Detail `:2333` passes it directly to a plain Text card. Completed-circuit review shares these snapshot/detail components and inherits the issue.
5. Generated practice shares the same persistence path (`PersistenceModels.swift:3136–3146`) and AI generation history also directly renders `attempt.response` (`AIStudioView.swift:1961–1963`). Thus both main and generated practice are affected by design, not just the tested math activity.

Schema breadth: `Sources/TrainingEngine/NFExerciseModels.swift:749–757` declares all eight response cases as synthesized Codable; `UniversalSessionView.swift:953–972` constructs each. Every successfully saved case reaches this JSON-as-answer path: numeric (value/unit), single choice (optionID), multiple choice (optionIDs), ordered steps (stepIDs), short text, self-check (rating/reflection), claim/evidence (claim/evidence identifiers), logic state (field values/violatedRuleID). For choices, ordering and evidence mapping, stripping JSON braces alone is insufficient because stored values are internal IDs rather than the visible labels. `NFExerciseScoringEngine.swift:938–996` and `:1131` also use IDs in normalized responses, so blindly replacing the field with `normalizedResponse` would still leak identifiers for these schemas.

Impact: strongest concrete explanation for “unprofessional.” History cannot reliably be used for learning, raw IDs are unintelligible, and VoiceOver speaks serialization syntax. Exact-data provenance was prioritized over understandable presentation.

Recommendation: retain machine-readable response payloads for replay/export/scoring compatibility, but add a typed learner-facing response renderer. Numeric shows original entered value and unit; choice shows saved visible option text; multiple choice shows selected option labels; ordering shows numbered step labels; text shows exact entered prose; self-check separates answer and match rating; claim/evidence renders named relationships; state trace shows named fields/values and rule description. Persist the display labels and exercise context with the original attempt so future template changes cannot alter history. Put content-version diagnostics in an optional Details disclosure. Keep raw payload only in explicitly requested technical export/details.

Acceptance: submit one response in every interaction family, relaunch, and review in main history, completed review and generated-set history. No visible `_0`, JSON property names or option/claim/rule identifiers. Display must preserve original user input and meaning, and export/restore must retain existing raw payload compatibility. Protected answer keys remain protected. Include an older record without a context snapshot and provide a readable, honest fallback rather than silently inventing labels.

### UX-18 — High — Mac navigation became unresponsive from a deep answer-review route (observed; cause unproven)

Parent observed on macOS 27.0 beta (26A5425a), build 1.0.0 (5): Progress → Explore details → Mental Math → Answer history → saved answer review, then click Sources sidebar. UI automation first reported no windows available and subsequent app acquisition timed out, while the app process remained alive. Parent owns reproduction/relaunch confirmation. A three-second process sample is retained at `/private/tmp/neuroforge-qa-source-navigation-hang.txt`; its 1,266 main-thread samples are under AppKit/SwiftUI layout/render work and include repeated `SkillDetailView.body` evaluation. This is an observed responsiveness failure, not a proven crash or data-loss event, and tool timeout alone is not sufficient to assign a root cause.

Source investigation: the Mac outer NavigationSplitView directly replaces its detail when sidebar selection changes and changes detail `.id` (`AppRootView.swift:281–310`). The Progress detail itself owns a NavigationStack plus item-driven skill destination (`ProgressDashboardView.swift:104`, `:163–165`), then nested destination-based NavigationLinks for answer history (`:1420–1443`) and saved review (`:2183–2189`). A deep stack teardown/replacement interacting with SwiftUI layout is a plausible surface to isolate, but not a demonstrated implementation fault. The selectedDestination didSet's dirty-editor reset is guarded (`PersistenceModels.swift:1057–1068`), and read-only review does not register a dirty editor. There is no explicit state-mutating onAppear/onChange/task loop in SkillDetailView. Chart points use stable attempt IDs (`ProgressDashboardView.swift:1733`), so the common fresh-UUID identity bug is not present.

Performance contributor, not established root cause: SkillDetailView computes filtered attempts, attribution, reduced estimates, charts, and speed projections through repeatedly accessed computed properties (`ProgressDashboardView.swift:1315–1351`, `:1653–1666`). Attribution repeatedly decodes persisted skill-weights JSON (`PersistenceModels.swift:232–234`). The sample includes those calculations and localization bundle work as well as framework layout, but does not prove they initiate or sustain a loop.

Next isolation steps: repeat sidebar switches from Progress root, skill detail, history, and saved-review depth; compare direct switch with pop-to-root first; test stable macOS and iOS; instrument navigation path changes/body invalidations and capture Instruments hangs/time profiler. If teardown is implicated, use explicit stable per-destination navigation paths rather than destructive identity replacement; if recomputation dominates, create immutable cached view projections keyed by evidence/filter revision. Do not prescribe either as a verified fix until reproduced. Acceptance requires repeated deep navigation with responsive controls and intact history, plus no sustained layout/render cycling.

## Current improvements visible since the old audit

- Onboarding now constrains page width to viewport and uses safeAreaInset for action bar (`OnboardingView.swift:53–96`), restores draft and focus, and uses responsive header layouts. Needs live current regression testing.
- Main navigation reserves 68pt under compact tab content (`AppRootView.swift:256–269`). This is not proof every screen fits, but contradicts blindly repeating the old unreserved-overlay implementation.
- Main session uses a response validator (`UniversalSessionView.swift:383–408`) and can show explicit requirements (`:1422–1430`). Old “one claim enables Submit” requires current retest.
- Pause modal hides underlying accessibility elements (`UniversalSessionView.swift:1112–1116`).
- Source import now models progress, cancellation, retry, duplicates and explicit recovery states (`LibraryView.swift:59–75`, `:93–129`, `:574–631`, `:1090–1120`).
- AI Studio includes persisted drafts, global unsaved guards, cancellation, retry/offline/reinstall recovery and result focus (`AIStudioView.swift:254–282`, `:349–410`, `:717–800`).
- Full answer history and completed chapter review now exist (`ProgressDashboardView.swift:2045`, `:2306`, `:2370`). Their learning value and discoverability need improvement; absence is no longer the correct diagnosis.
- Theme uses explicit adaptive foreground/control pairs and semantic contrast specifications (`Theme.swift:63–198`). Do not assert blanket low contrast without measuring rendered combinations.

## Improvement sequencing

1. **Reliability/clarity gate:** validate current tests and live critical paths, eliminate actual crashes/data-loss/mis-scoring; repair small-screen/AX problems; separate timing/difficulty controls and fix mismatched destination copy. Keep the learner's current data untouched during audit.
2. **Core learning loop:** single persistent problem surface, confidence inline where required, fast feedback, optional ordinary-practice reflection, graduated hints, fresh repair question, persistent explanation snapshots. These yield more value than new top-level tabs or more rewards.
3. **Navigation and personalization:** compact Today, searchable exact activity browser, visible resume/review, learner-adjusted focused/catalog defaults, saved collections, settings categories. Explain recommendation in ordinary language with one reason and an override.
4. **Useful interactive depth:** test one polished activity per major skill family—ordering, trace stepping, evidence mapping, data prediction, spatial transform—before broadening. Maintain score integrity and accessible equivalents.
5. **Professional finish:** unified vocabulary/design density, typography, empty/loading/error states, content retention copy, platform-specific input behavior; follow with first-session and repeat-use usability testing.

## Suggested measurement and QA acceptance targets

Targets below are proposed product criteria, not claims about current measured performance.

- New learner can describe what the app trains, whether the current task is assessed, and what to do next after five seconds on the relevant screen.
- First practice starts within two clear decisions after setup; repeat/resume is one obvious action.
- Routine answer requires no mandatory full-page interruption after response entry; essential confidence collection remains valid.
- 100% of supported question interaction families have verified keyboard, VoiceOver and 44pt-equivalent touch paths.
- Current question, validation, submit, feedback and next action remain usable on smallest supported phone with keyboard and AX5 text.
- Post-error user can reach a useful explanation and a fresh repair question; original attempt remains immutable.
- Difficulty-only and timing-only choices are independently testable; known novice/intermediate/advanced fixture profiles get intentionally different recommended challenges.
- History question remains understandable with original diagram/table/options/feedback across app updates and export/restore.
- 100-source import library and large attempt history have responsive search, bounded rendering and comprehensible empty/filtered states.
- Conduct moderated sessions with at least five representative learners at different STEM levels; log hesitations, wrong turns, requests for explanation, perceived challenge and usefulness. Source/tests cannot establish educational usefulness or perceived professionalism alone.

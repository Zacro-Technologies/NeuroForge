# NeuroForge Whole-App UX, Accessibility, and Feature Audit

Post-audit remediation and certification companion: [Audit Remediation and Release Certification — 2026-08-31](Audit_Remediation_and_Release_Certification_2026-08-31.md)

Audit date: 2026-08-30  
Build tested: 1.0.0 (4), Debug  
Platforms exercised: native macOS and iOS Simulator  
Primary method: direct user-perspective interaction through Computer Use  
Repository: NeuroForge  
Auditor disposition: not ready for release without the release-gate fixes below

## 1. Executive summary

NeuroForge has a substantial working product surface: onboarding, a four-part baseline, seven practice labs, a 58-activity catalog, generated question sets, source import and review, progress analytics, profile controls, exports, localization controls, and Apple-platform integration settings are all present. Core offline practice is usable, data persists across relaunches, and the app gives unusually clear privacy context in several important workflows.

However, the tested build has three immediate release gates:

1. AI Studio can crash the whole app when Settings says Question Writer is ready but the corresponding Shortcut has been removed.
2. A completed daily circuit can be replaced by a new zero-percent circuit on the same day after preferences are saved, while XP and history remain. This breaks the daily-plan contract and may permit repeated rewards.
3. The compact iPhone layout is not usable at iPhone SE dimensions: onboarding and Forge content are clipped horizontally, persistent controls cover content, and the tab bar covers primary actions.

The audit tracks 69 items:

- 30 behaviors directly observed through the app UI.
- 24 additional implementation-backed correctness, accessibility, and integration risks.
- 15 missing, unreachable, or incomplete product capabilities.

Some implementation-backed items explain or broaden an observed item; those overlaps are called out rather than counted as separate user symptoms.

### Release recommendation

Do not ship build 1.0.0 (4) as the production release. Fix O-001 through O-012, add regression coverage for each, and complete a signed physical-device pass for CloudKit, notifications, widgets, Shortcuts, Spotlight, and iPad before release approval.

### Severity model

| Severity | Meaning in this audit |
|---|---|
| Blocker | Reproducible process-wide crash, persisted core-data corruption/loss, or a core path that cannot safely ship |
| High | Materially wrong scoring/data/state, a blocked supported-device or assistive-technology path, silent authored-work loss, or a major trust failure |
| Medium | Meaningful task friction, misleading behavior, incomplete integration/recovery, or a defect with a practical workaround |
| Low | Localized clarity, consistency, or polish issue that should be bundled with nearby work |

## 2. How this audit was performed

This was not a coded-test-only review. The running app was operated from the user's perspective using Computer Use:

- Clicked, typed, scrolled, selected, paused, resumed, closed, reopened, filtered, searched, imported, exported, changed preferences, and navigated with menus and keyboard commands.
- Exercised fresh onboarding on iPhone and the established Mac profile.
- Completed a full daily circuit and representative sessions across the major interaction families.
- Inspected all top-level destinations and every Settings section.
- Inspected the complete practice catalog and all seven labs.
- Tested narrow Mac presentation and compact iPhone presentation.
- Read the app's accessibility representation while interacting, including labels, values, headings, focusable actions, chart summaries, and table output.
- Relaunched the app to distinguish transient UI state from persisted behavior.

After the UI pass, source inspection was used only to:

- Locate the implementation responsible for an observed issue.
- Identify silent failure paths that are difficult to force safely.
- Find integration paths blocked by unsigned builds or unavailable physical-device services.
- Inventory features that are implemented but unreachable.

Observed issues and source-backed risks are deliberately separated below.

## 3. Environment and coverage boundary

### Tested builds

| Target | Result |
|---|---|
| macOS 27.0, Apple Silicon | Build succeeded and the app was exercised extensively |
| iPhone SE (3rd generation), iOS 26.5 Simulator | Build/install succeeded; onboarding, Forge, compact layout, and session entry exercised |
| iPhone 17 Pro Max, iOS 26.5 Simulator | Onboarding exercised through the third step; simulator later shut down unexpectedly |
| iPad A16 Simulator | CoreSimulator service repeatedly died before a stable test pass |
| Connected physical iPad | Detected by Xcode but not deployed to, avoiding an unapproved mutation of the user's personal device |

Toolchain:

- macOS 27.0 (26A5421a)
- Xcode 26.6 (17F113)
- XcodeGen 2.46.0
- Swift 6.3.3

The Mac Debug build was unsigned/linker-signed and the iOS target was an unsigned Simulator build. Neither provided effective production entitlements. That means successful CloudKit, push notification, App Group, widget data-sharing, and signed Shortcuts paths could not be validated. Their unavailable/local-only states were inspected instead.

### Persisted test state after the pass

The Mac profile contained one local learner, nine attempts, one reflection, one current plan, five checkpoints, one progress annotation, one imported document with 256 chunks, five AI generations, and one calibration record. The iPhone SE profile was separate and contained onboarding data plus one started/checkpointed session. No user data was deleted.

### Evidence strength used in this report

| Label | Meaning |
|---|---|
| Observed | Reproduced through the running UI with Computer Use |
| Observed + located | Reproduced in UI and tied to a specific implementation location |
| Source-backed risk | A concrete reachable code path found after UI testing; not necessarily forced in this unsigned environment |
| Coverage gap | Requires signing, hardware, service state, destructive data, or a stable target not available in this run |

## 4. Coverage ledger

| Area | User journeys exercised | Result |
|---|---|---|
| First launch and onboarding | All three setup steps, Back navigation, goals, context, duration, pace, baseline choice | Working flow; compact layout and accessibility issues |
| Baseline | All four blocks, start, answer, confidence, pause, save/close, resume | Functional; misleading counts/copy and narrow presentation |
| Today / Forge | Readiness, Adjust Circuit, replacement, three-chapter daily circuit, scratchpad, structured response, reflection, summary, completion, relaunch | Functional core; serious plan-state, validation, copy, and completion-state defects |
| Practice | All seven labs, recommendation, all 58 catalog rows, search, lab/type filters, empty results, details, start/resume | Broadly working; recommendation/history and reachability gaps |
| Interaction engines | Numeric, multiple choice, state trace, spatial 3D/2D, claim/evidence, source-backed review, generated practice | Multiple validation, keyboard, and accessibility defects |
| AI Studio | Starter catalog, no-results reset, configuration, offline generation, six-question run, hint, answer, feedback, leave/resume | Offline path works; external Question Writer path crashes |
| Progress | Overview, filters, ability detail, chart, coverage, common errors, annotation create/edit/export flag, exports | Data and accessibility inconsistencies; no real answer-history UI |
| Sources | Search, no results, import picker, source detail, privacy policy choices, browse, exact search, source review, question handoff | Core works; table accessibility, stale status, draft-loss, and handoff gaps |
| Settings | Profile, accessibility, notifications, quiet hours, language, Spotlight/privacy toggles, exports, privacy policy, reset/delete confirmations | Most controls work; localization, reachability, and integration-state defects |
| macOS integration | Command shortcuts, Training menu, Import, Open Export, Open Methodology, destinations, active-session commands | Several commands are context-insensitive or land at the wrong place |
| Compact iPhone | Fresh onboarding, setup completion, Forge, daily-circuit launch, first session item | Major clipping/overlap; no stable iPad pass |
| Accessibility | Accessible names/values, headings, focus order, keyboard behavior, tables, charts, editor labels, contrast review | Multiple high-impact VoiceOver, keyboard, and low-vision issues |
| Localization | Live English/Japanese switching, Settings, profile editor, Forge, relaunch | Mixed-language states and incomplete coverage |
| Data safety | Pause/save/close, relaunch persistence, non-destructive confirmations, exports | Core persistence works; silent loss/truncation paths remain |

## 5. Release gates and high-priority observed defects

### O-001 — Blocker — AI Studio crashes when a previously verified Shortcut is missing

Evidence: Observed + located  
Platform: macOS  
Area: AI Studio / Question Writer / Shortcuts

Reproduction:

1. Have NeuroForge's preferences record Question Writer setup as verified.
2. Remove or otherwise make the NeuroForge Private Authoring Shortcut unavailable.
3. Open AI Studio. The UI still presents Question Writer as ready.
4. Ask it to create six questions.

Actual result:

- NeuroForge terminates with EXC_BREAKPOINT / SIGTRAP.
- The crash report shows a main-actor isolation violation in the URL-open completion callback:
  - _dispatch_assert_queue_fail
  - _swift_task_checkIsolatedSwift
  - AIStudioView.openExternalURL
- Crash report: /Users/takamimarsh/Library/Logs/DiagnosticReports/NeuroForge-2026-08-30-162132.ips
- Relevant implementation: Sources/Features/AI/AIStudioView.swift:1069-1075.

Expected result:

- Recheck whether the Shortcut exists before labeling the integration ready.
- If it is missing, show a nonfatal recovery state with Reinstall Shortcut, Retry, and Use offline generation.
- Completion callbacks that update actor-isolated state must return to MainActor.

User impact:

- Complete data-loss risk for any unsaved work in the process.
- A stale readiness badge actively guides the user into the crash.

Recommended fix and regression:

- Make URL-open completion explicitly MainActor-safe.
- Invalidate stored readiness when the external workflow disappears or fails.
- Add a UI regression that verifies missing/deleted/cancelled/denied Shortcut outcomes never crash and always offer offline fallback.

### O-002 — High — Saving preferences can replace an already completed daily circuit

Evidence: Observed  
Platform: macOS  
Area: Today / plan persistence / rewards

Reproduction:

1. Complete all chapters in the current daily circuit.
2. Confirm the circuit shows completion and XP/history were recorded.
3. Open Settings and save profile/language/accessibility preference changes.
4. Return to Today and relaunch the app.

Actual result:

- The completed plan was replaced on the same calendar day by a new Logic + Crossover plan at 0 percent.
- Previously awarded XP and answer history remained.
- Relaunch preserved the replacement rather than restoring the completed circuit.

Expected result:

- Non-plan preferences must not rebuild an already materialized plan for the same learner day.
- A deliberate plan reset should be explicit, explain consequences, and have well-defined reward behavior.

User impact:

- Completion becomes untrustworthy.
- The user may repeat daily rewards or lose the visual record of today's completed work.
- Any streak or adaptive-plan logic based on one plan per day can diverge from attempt history.

Recommended fix and regression:

- Separate preference persistence from plan invalidation.
- Give daily plans stable day/profile identity and preserve completed state.
- Add tests for each preference field before and after partial and full completion, including relaunch and timezone-day boundaries.

### O-003 — High — iPhone SE layout clips content and covers primary actions

Evidence: Observed  
Platform: iPhone SE (3rd generation), iOS 26.5 Simulator  
Area: Onboarding, Forge, tab bar, session presentation

Reproduction:

1. Launch a fresh profile on an iPhone SE-sized display.
2. Move through all onboarding steps.
3. Finish setup and open Forge.
4. Start the daily circuit.

Actual result:

- Onboarding content uses a width larger than the viewport; headings, the YOUR RHYTHM label, Back, and Step text are cut off on the left and right.
- The persistent bottom call-to-action overlaps options and explanatory content.
- On Forge, the tab bar covers Adjust Circuit and the circuit chapter region.
- XP/status content at the right edge is clipped.
- The first-session view exposed raw target text. Its overall geometry was not scored because the Simulator unexpectedly changed orientation.
- Onboarding's gray Get started treatment looked disabled even when it was the intended action, and small secondary copy had weak visual emphasis.

Expected result:

- All controls and text remain within safe-area bounds at the minimum supported iPhone width.
- Persistent bottom elements reserve content inset and never cover the focused choice or primary action.
- Dynamic Type must be accommodated without horizontal cropping.

User impact:

- A supported device class cannot reliably complete setup or understand/tap core actions.
- This is an accessibility failure for larger text users even on wider phones.

Recommended fix and regression:

- Remove fixed-width assumptions; use container-relative layout and ViewThatFits/adaptive stacks.
- Add measured bottom content margins matching overlay/tab-bar height.
- Add snapshot and interactive tests at iPhone SE width for every onboarding page, every tab root, and all session interaction families at default and accessibility text sizes.

### O-004 — High — Structured-response questions accept incomplete answers

Evidence: Observed + located  
Platform: macOS  
Area: Today session / claim and evidence

Reproduction:

1. Open a claim/evidence mapping question with multiple claims or required relationships.
2. Map only one claim.
3. Observe the Submit action.

Actual result:

- Submit becomes enabled after only one mapping.
- Feedback can contain raw relationship identifiers instead of a human-readable explanation.

Expected result:

- Submit should remain disabled until the schema's required number of mappings and relationships is satisfied.
- The feedback layer should always translate identifiers to localized user-facing labels.

User impact:

- Users can submit structurally incomplete work and receive scoring that does not match the prompt.
- The result can contaminate mastery estimates and adaptive recommendations.

Relevant implementation:

- Sources/Features/Training/UniversalSessionView.swift:286-303 and 1368-1420.
- Related generation/scoring: Sources/TrainingEngine/NFExerciseModels.swift and the structured-response scorer.

Recommended fix:

- Validate each interaction against its schema, not merely non-emptiness.
- Add tests for zero, partial, exact, duplicate, and excessive mappings.

### O-005 — High — The accessibility tree duplicates table content and omits table structure

Evidence: Observed  
Platform: macOS and iPhone session accessibility representation  
Area: Today tables, source viewer tables

Actual result:

- A Today table exposed the same sentence repeatedly for individual cells/columns without meaningful row, column, or header relationships.
- The source viewer repeated each logical row once for every column: two times in a two-column table, three times in a three-column table, and four times in a four-column table.
- Cell navigation did not communicate position or header context.

Expected result:

- Each table should expose a concise table summary, header cells, unique data cells, row/column position, and predictable traversal.
- Visible sentences must not be duplicated in the accessibility tree.

Likely user impact:

- The inspected accessibility tree indicates that VoiceOver users will hear redundant content and be unable to reliably associate a value with its header.
- This is likely to block source review and multiple exercise types rather than merely inconvenience them.
- A complete auditory VoiceOver pass was not performed, so release testing must confirm the exact spoken order and rotor behavior on physical devices.

Recommended fix:

- Build a semantic accessibility representation separate from the visual Grid.
- Test with VoiceOver rotor/table navigation on Mac, iPhone, and iPad.

### O-006 — High — Japanese mode produces mixed-language screens and stale localization

Evidence: Observed  
Platform: macOS  
Area: Settings, profile editing, Today

Reproduction:

1. Change app language from English to Japanese.
2. Inspect Settings, profile editing, and Forge.
3. Switch back to English without quitting.

Actual result:

- Forge mixed Japanese with English strings such as Choose free practice, CHAPTER, Crossover, and active this week.
- Settings retained English system/integration labels.
- The profile editor's shell headings remained English while option values changed to Japanese.
- Switching back to English left parts of the sidebar and options in Japanese until the app was quit and relaunched.

Expected result:

- The selected app language should update all owned strings consistently and atomically.
- Switching language should never create a mixed stale navigation tree.
- Startup, deletion, and date formatting should honor the selected app language.

User impact:

- Users cannot depend on the language preference and may misunderstand destructive or privacy-related controls.

Recommended fix:

- Audit all owned strings and remove hard-coded English.
- Give the app's language state one invalidation boundary instead of selectively rebuilding views.
- Add cold-launch and bidirectional switching tests for every root screen and confirmation dialog.

### O-007 — High — Closing Source review silently discards the draft

Evidence: Observed + located  
Platform: macOS  
Area: Sources / source review

Reproduction:

1. Open a source and start a Source review.
2. Type a response.
3. Choose Close.
4. Reopen Source review.

Actual result:

- The editor closes immediately with no warning.
- The typed draft is gone on reopen.

Expected result:

- Close should present Save draft, Discard, and Cancel when the response has changed, or autosave a checkpoint.

User impact:

- Silent loss of user-authored study work.

Relevant implementation:

- Sources/Features/Library/LibraryView.swift:1358-1405 and 1586-1604.

Recommended fix:

- Apply the same dirty-state guard used by the safer generated-practice flow.
- Add close-button, Escape, navigation, window-close, and app-termination recovery tests.

### O-008 — High — Progress annotations silently truncate and expose inaccessible actions

Evidence: Observed + located  
Platform: macOS  
Area: Progress / annotations

Reproduction:

1. Create an annotation and enter more than 500 characters.
2. Observe the counter and Save state.
3. Save and reopen the annotation.
4. Try to discover Edit/Delete through the accessibility tree.

Actual result:

- The remaining counter clamps at 0.
- Save stays enabled.
- The saved note is silently truncated to the first 500 characters.
- The row action menu was absent from the accessibility representation and only discoverable through pointer context-click.
- The editor's text area did not have a useful accessible label.

Expected result:

- Prevent additional input or clearly report over-limit content and disable Save.
- Never silently alter submitted text.
- Expose Edit and Delete as explicit, keyboard- and VoiceOver-reachable actions.

User impact:

- Loss of note content.
- VoiceOver and keyboard users cannot manage notes independently.

Relevant implementation:

- Sources/Features/Progress/ProgressAnnotationsView.swift:25-99 and 179-205.

Recommended fix:

- Validate before mutation; show an inline error.
- Preserve the editor on save failure.
- Add named buttons or accessibility actions and announce destructive consequences.

### O-009 — High — Ability detail numbers contradict their own coverage breakdown

Evidence: Observed  
Platform: macOS  
Area: Progress / quantitative ability detail

Actual result:

- The Quantitative ability header reported 4 answers and 89 percent.
- Its coverage section attributed only 1 answer to Protected assessment and showed no answers in the other channels.

Expected result:

- The headline and coverage components should reconcile to the same attempts and clearly label any intentionally excluded channels.

User impact:

- Users cannot understand what evidence drives mastery.
- The adaptive system appears unreliable, particularly in an education product where evidence provenance is central.

Recommended fix:

- Use one normalized query/result model for headline metrics and channel coverage.
- Add invariant checks that displayed channel totals reconcile with the displayed total.

### O-010 — High — Internal identifiers and placeholders leak into user-facing UI

Evidence: Observed  
Platform: macOS and iPhone  
Area: Today, Progress, feedback, crossover

Observed examples:

- target.scientificReasoning
- target.logicDebugging
- causal_overreach
- claim.difference:evidence.means;claim.limits:evidence.assignment+evidence.universal
- literal target skill
- the the target skill representation

Expected result:

- Every enum/raw identifier must pass through a complete localized presentation layer.
- Placeholder strings must be resolved before an exercise is added to the catalog or plan.

User impact:

- Prompts and feedback become difficult or impossible to understand.
- The leakage makes the app appear unfinished and weakens trust in generated/adaptive content.

Recommended fix:

- Add catalog validation that rejects raw-key patterns, unresolved tokens, duplicated words, and nonlocalized enum descriptions.
- Run it against all bundled and generated content in every supported locale.

### O-011 — High — The weekly mission changed during the same day's session

Evidence: Observed  
Platform: macOS  
Area: Today / adaptive plan

Actual result:

- The mission changed from Science & Data + Quantitative to Science & Data + Logic during the audit day without an explicit user-requested mission change.

Expected result:

- A weekly mission should have a stable identity and visible change reason.
- If adaptive evidence legitimately changes it, the app should explain when and why, and avoid changing it mid-session.

User impact:

- Goals appear arbitrary and progress continuity is lost.
- This compounds O-002 by making plan selection difficult to audit.

Recommended fix:

- Persist mission identity/version and an explanation event.
- Only roll a weekly mission at a documented boundary or through explicit confirmation.

### O-012 — High — Completed sessions remain interactive and can enter a false paused state

Evidence: Observed  
Platform: macOS  
Area: Session summary

Reproduction:

1. Finish the chapter and reach its summary.
2. Use Pause or Scratchpad.

Actual result:

- Pause remains active and reports Session paused even though no question remains.
- Scratchpad remains editable after the result is committed.
- Completed Today chapter cards remain visually tappable but do not provide a useful action.

Expected result:

- A committed session should enter a final, immutable state with only meaningful next actions: Done, review answers, view explanation, or practice again.

User impact:

- State and persistence semantics are ambiguous.
- Users may believe they paused work that is already complete or expect a completed card to open a review.

Recommended fix:

- Replace the active-session toolbar on summary with completion-specific actions.
- Make completed chapter cards open a real review, or remove their button affordance.

## 6. Medium-priority observed defects

### O-013 — Numeric validation accepts text that cannot be scored

Evidence: Observed  
Area: AI Studio numeric practice

Typing abc into a numeric answer left Submit enabled. Submission then falls into a generic/internal-sounding error path. Numeric fields should parse and validate continuously, explain the accepted form, support signed/scientific/localized values where the schema allows them, and disable Submit for invalid input.

### O-014 — Session summary hides skipped work

Evidence: Observed  
Area: Today summary

After two correct answers and one skip, the summary said 2 of 2 fully correct. That wording suppresses the skipped item and presents a perfect-looking denominator. Show attempted, correct, incorrect, and skipped counts explicitly, for example 2 correct, 0 incorrect, 1 skipped, 3 presented.

### O-015 — Crossover content is repetitive and contains template artifacts

Evidence: Observed  
Area: Today crossover

All three crossover questions used the same table-to-equation structure with only numbers changed. Copy also included target skill, the the target skill representation, and punctuation such as sample.; and feasible.;. Crossover should vary reasoning transfer, representation, and context, and catalog linting should reject placeholder/grammar artifacts.

### O-016 — The Mac session sheet becomes too narrow for its content

Evidence: Observed  
Area: Baseline and active sessions

At the app's narrow supported window size, the session sheet compressed headings such as Numerical control into three lines and produced a dense, awkward interaction column. Define a meaningful minimum session width, adapt the header/action layout, or present sessions as a full-window route at compact widths.

### O-017 — Hardware keyboard behavior is incomplete

Evidence: Observed  
Area: Mental Math session on macOS

The numeric answer field autofocuses, but Return did not submit and Tab did not move focus predictably. During onboarding, Tab also failed to move focus to the first primary call-to-action. Users need discoverable shortcuts, reliable focus order, Escape behavior, and Return/Command-Return submission where safe. See also R-001 and R-002 for data-entry consequences.

### O-018 — Filtered-empty Progress uses the wrong explanation

Evidence: Observed  
Area: Progress filters

The timed-only filter produced an empty state claiming the ability was new or unassessed, even though history existed and was merely excluded by the filter. Empty-state copy must distinguish no history, no matches, and insufficient evidence, and should include Clear filters.

### O-019 — Progress recommendations and answer-history promises are not actionable

Evidence: Observed  
Area: Progress

Practice next cards look like controls but are plain, noninteractive content. Ability detail refers to answer history but does not show individual answers. Either make the cards deep-link into the recommended practice and add a real attempt list, or restyle/reword them as informational text.

### O-020 — Charts have no useful nonvisual summary

Evidence: Observed  
Area: Progress charts

The accessibility representation exposed generic ranges such as 1 to 1.1 and 1 to 1, 2 series without naming the measure, dates, trend, or comparison. Provide a concise chart summary, current value, change over time, and a data-table alternative.

### O-021 — Error labels and icon semantics leak implementation state

Evidence: Observed  
Area: Progress

The common-error label displayed causal_overreach, and decorative/status icons were announced as Syncing. Related source inspection found that the Today streak can be exposed as a bare number without context, while a reusable status-pill symbol is hidden without guaranteeing that equivalent meaning remains in its text. Map error taxonomies to localized language, give streak values complete labels, and hide only genuinely decorative symbols. Status icons need labels that match the actual state.

Related references:

- Sources/Features/Today/TodayView.swift:362-374.
- Sources/DesignSystem/Theme.swift:621-639.

### O-022 — Baseline progress and scoring language are misleading

Evidence: Observed  
Area: Baseline

Block badges initially say 0 items, a zero-progress track still draws a nonzero-looking dot, and singular copy later says 1 items. One block says Practice · no score while feedback says Supported 100% credit. Align product terminology and use correct pluralization and zero states.

### O-023 — Circuit replacement feedback is late and its reasoning is inconsistent

Evidence: Observed  
Area: Adjust Circuit / Today

After replacing a chapter and launching the session, a Block replaced alert appeared over the already-running session. Why next also described Logic and Chosen by you after Data reasoning had been selected. Commit and acknowledge the replacement before launch, then generate explanation text from the persisted selection.

### O-024 — Scratchpad labeling and empty-state behavior are misleading

Evidence: Observed  
Area: Session toolbar

The action Accessibility and scratchpad only opened the scratchpad, and Clear was enabled while the pad was empty. Split or rename the action to reflect what it does, place accessibility settings where they can actually be changed, and disable Clear until content exists.

### O-025 — macOS menu commands are enabled in the wrong context or navigate incompletely

Evidence: Observed  
Area: Training menu and keyboard commands

- Submit / Next was enabled outside a session and did nothing without feedback.
- Open Data Export and Open Methodology only selected Settings rather than scrolling/opening the requested section.
- Show Train and Show Library conflict with the visible destination names Practice and Sources.
- Import Study Material correctly opened the file picker.
- Command-1 navigation worked.

Commands should validate active context, be disabled when inapplicable, and land on the exact destination promised by the label.

## 7. Low-priority observed polish and comprehension issues

### O-026 — Readiness changes without explaining their effect

Evidence: Observed  
Area: Today

Readiness changed from Normal to Low, but the app did not state which chapter length, pacing, or recommendation changed. Add a short Why this changed explanation and make the consequence visible.

### O-027 — Relative-time formatting is overprecise and inconsistent

Evidence: Observed  
Area: AI Studio recent sets

Recent items used 0 sec, 1 min, 0 sec, and 10 min,29 sec. Use stable localized thresholds such as Just now, 1 min ago, and 10 min ago, with correct spacing and pluralization.

### O-028 — Small grammar defects are widespread

Evidence: Observed  
Area: Today, baseline, progress

Examples include 1 chapters, 1 items, 1 answers, sample.;, and feasible.;. Centralize pluralization through localized format strings and run catalog text linting.

### O-029 — Long content and instructional regions lack navigable semantic structure

Evidence: Observed  
Area: AI review disclosure and privacy policy

Long, structured policy/disclosure content appeared as one huge accessibility text element without headings or navigable sections. The AI prompt/self-check regions and Methodology content also lacked consistent heading semantics. Break these into semantic headings, paragraphs, lists, and links so assistive-technology users can skim and navigate them.

Related references:

- Sources/Features/AI/AIStudioView.swift:1531-1566.
- Better prompt-heading comparison: Sources/Features/Training/UniversalSessionView.swift:1179-1185.
- Sources/Features/Methodology/MethodologyLibraryView.swift:151-185.
- Sources/Features/Settings/SettingsView.swift:872-881.

### O-030 — Count-choice selection uses opaque accessibility values

Evidence: Observed  
Area: Practice configuration

Count choices announced values such as 0 and 1 rather than Selected/Not selected or a radio-button role. Use selected traits and a group label that communicates the current set size.

## 8. Additional implementation-backed risks

These paths were found after the UI pass. They are concrete, reachable implementation risks, but some require unusual input, failure injection, signing, or service state that was not safe or available in this run.

### R-001 — High — Save and close can dismiss even when checkpoint persistence fails

Condition:

- UniversalSessionView invokes checkpoint persistence and then dismisses the session.
- The persistence layer can throw, but the view's close path does not require confirmed success before dismissal.

Impact:

- A user can explicitly choose Save and close, receive no failure message, and later discover that recent answers or self-check state were lost.
- This broadens the manually observed unsaved-editor problem into an active-session data-safety risk.

References:

- Sources/Features/Training/UniversalSessionView.swift:712-729 and 1753-1757.
- Sources/Persistence/PersistenceModels.swift:3909-3997.

Recommendation:

- Make dismissal conditional on a successful committed checkpoint.
- On failure, keep the session open, preserve the draft in memory, show Retry, and offer an explicit Discard path.
- Inject persistence failures in tests at every session stage.

### R-002 — High — Numeric keyboards exclude valid negative input and schema-permitted notation

Condition:

- Active numeric fields use decimalPad.
- The fallback generator demonstrably creates potentially negative expected-value answers.
- The shared numeric schema also permits scientific notation.
- decimalPad does not provide minus or exponent keys.

Impact:

- A generated negative answer may be impossible to enter on iPhone/iPad without an external keyboard or paste.
- If scientific notation is intentionally supported by the schema, the native touch entry UI does not expose it.

References:

- Sources/Features/Training/UniversalSessionView.swift:1247-1249.
- Sources/Features/AI/AIStudioView.swift:1815-1819.
- Sources/Features/Training/SessionView.swift:663-670.
- Sources/TrainingEngine/NFFallbackExerciseGenerator.swift:1175-1213 and 3097-3126.

Recommendation:

- Select the keyboard and accessory controls from the answer schema.
- Provide explicit minus, decimal, fraction, and exponent support where applicable.
- Ensure every generated answer is enterable on every supported input method.

### R-003 — High — Localized decimal input can be mis-scored by two orders of magnitude

Condition:

- Numeric normalization removes commas rather than interpreting the active locale's decimal separator.

Example:

- In a comma-decimal locale, 1,25 can normalize to 125 rather than 1.25.

Impact:

- Correct answers become incorrect and mastery data is corrupted for affected locales.

Reference:

- Sources/TrainingEngine/NFExerciseScoringEngine.swift:407-428.

Recommendation:

- Parse with locale-aware NumberFormatter/FormatStyle, preserve signs and exponents, and reject ambiguous separators with a clear message.
- Add tests for English and Japanese plus comma-decimal locales even if the UI is not yet translated for all of them.

### R-004 — High — AI Studio logic responses do not validate the violated rule

Condition:

- The logic interaction captures a violated-rule choice, but the validation/scoring path does not consistently require and compare it.

Impact:

- An incomplete or logically wrong response can receive credit based on only the other fields.

References:

- Sources/Features/AI/AIStudioView.swift:1280-1307 and 1752-1774.

Recommendation:

- Make all schema-required fields part of both Submit enablement and scoring.
- Add adversarial tests in which each individual field is wrong or omitted.

### R-005 — High — Multiple-choice validation ignores schema minimum and maximum selections

Condition:

- Universal validation treats a nonempty selection as complete without enforcing minSelections/maxSelections.

Impact:

- Multi-select items can be submitted with too few or too many choices, producing inconsistent scoring and feedback.

References:

- Sources/TrainingEngine/NFExerciseModels.swift:559-564.
- Sources/Features/Training/UniversalSessionView.swift:286-303.

Recommendation:

- Validate selection count against the schema and state the requirement near the control.

### R-006 — Medium — Overlong short text can be submitted and scored as zero without guidance

Condition:

- The model specifies a maximum length, but active Universal and AI Studio validation only check non-emptiness.
- Scoring later rejects the oversized answer.

Impact:

- A user is allowed to submit an answer the app already knows is invalid and receives an unexplained zero.

References:

- Sources/TrainingEngine/NFExerciseModels.swift:591-595.
- Sources/Features/Training/UniversalSessionView.swift:286-303 and 1313-1320.
- Sources/Features/AI/AIStudioView.swift:1280-1307 and 1665-1672.
- Sources/TrainingEngine/NFExerciseScoringEngine.swift:543-553.

Recommendation:

- Show a live count, constrain or validate before submission, and never convert a format error into academic feedback.

### R-007 — High — iCloud policy controls can show a state that failed to persist

Condition:

- The Library UI updates document sync/policy state optimistically.
- The persistence operation can fail and roll back without the visible selection being reliably reconciled.

Impact:

- The user may believe a private source is local-only or cloud-synced when the committed policy differs.

References:

- Sources/Features/Library/LibraryView.swift:665-692 and 767-785.
- Sources/Persistence/PersistenceModels.swift:3414-3437.

Recommendation:

- Show an in-progress state, commit first, then update the durable selection.
- On failure, restore the previous state and present a clear privacy-specific error.

### R-008 — High — Rapid cloud-policy changes can launch competing persistence tasks

Condition:

- Consecutive selection changes create independent asynchronous operations without serialization or cancellation.

Impact:

- Slow operations can complete out of order, leaving policy, original-document state, and UI inconsistent.

References:

- Sources/Features/Library/LibraryView.swift:767-799.
- Sources/Persistence/PersistenceModels.swift:1137-1207.

Recommendation:

- Serialize changes per document, disable the control during a transaction, or use a latest-intent version token.

### R-009 — Medium — Destructive and cloud-privacy copy can understate or blur scope

Condition:

- The source deletion confirmation focuses on the document, while the persistence cascade also removes associated chunks, exercises, and derived data.
- Settings privacy copy can blur the difference between removing the app/local device data and deleting private iCloud data.

Impact:

- A destructive action can remove more study material than the user reasonably understood.

References:

- Sources/Features/Library/LibraryView.swift:950-952.
- Sources/Persistence/PersistenceModels.swift:3440-3479.
- Sources/Features/Settings/SettingsView.swift:52-101 and 849-851.

Recommendation:

- Enumerate all deleted dependent data and whether attempts/history remain.
- State app removal, local-device deletion, and private-iCloud deletion as three separate consequences.

### R-010 — High — Transfer practice is classified and weighted as retrieval

Condition:

- Transfer items and plan requests flow through retrieval-related classifications/fallback generation.
- Improvement claims and adaptive weights can therefore attribute the evidence to the wrong ability.

Impact:

- Training content, recommendations, mastery, and scientific claims can disagree about what was practiced.

References:

- Sources/Features/Train/TrainCatalogView.swift:600-609 and 684-710.
- Sources/AI/NFNextDayPlanPreparationService.swift:29-56 and 92-101.
- Sources/TrainingEngine/NFFallbackExerciseGenerator.swift:78-93, 3142-3156, and 3209-3218.
- Sources/Persistence/PersistenceModels.swift:2381-2412.
- Sources/Adaptive/NFImprovementClaimEngine.swift:50-87 and 132-139.

Recommendation:

- Give transfer its own end-to-end taxonomy and migration.
- Add invariants that request skill, generated skill, scored skill, mastery update, and displayed claim all match.

### R-011 — High — Annotation save failures still dismiss the editor

Condition:

- The save path dismisses after invoking persistence even if persistence reports failure.

Impact:

- An annotation can appear saved but disappear, with no recovery path.

References:

- Sources/Features/Progress/ProgressAnnotationsView.swift:83-99 and 200-205.

Recommendation:

- Keep the editor presented until save succeeds and make the error accessible as a live status message.

### R-012 — High — Direct accent foregrounds can fail contrast on light surfaces

Evidence:

- Calculated approximate contrast ratios against white/light surfaces:
  - cyan: 2.13:1
  - mint: 1.92:1
  - amber: 2.08:1
  - gold: 1.61:1
  - rose: 3.14:1

Impact:

- The bright accents contrast strongly against NeuroForge's dark ink/midnight colors, but several are below normal-text and non-text contrast targets when used directly on white or light system surfaces.
- Because the app uses system/window backgrounds that can vary with appearance, direct foreground use is not safe without pairing it to the actual background.
- When color carries text, a small symbol, a boundary, or state without a stronger redundant cue, low-vision and color-vision users may not perceive it.

References:

- Sources/DesignSystem/Theme.swift:7-14.
- Examples of use: Sources/Features/Today/TodayView.swift:422-425 and 447-450; Sources/Features/Library/LibraryView.swift:1416-1419, 1538-1540, and 2305-2308.

Recommendation:

- Define appearance-aware semantic foreground/on-accent pairs and test each actual foreground/background combination.
- Do not use hue alone for mastery, readiness, correctness, sync, or selection.

### R-013 — Medium — History screens silently expose only short prefixes

Condition:

- Progress annotations show six, reports show four, generated sets show five, while persistence may retain up to 64.

Impact:

- Older data exists but is undiscoverable, and users may assume it was deleted.

References:

- Sources/Features/Progress/ProgressAnnotationsView.swift:25-70.
- Sources/Features/Settings/SettingsView.swift:407-439.
- Sources/Features/AI/AIStudioView.swift:250-310.
- Sources/Persistence/PersistenceModels.swift:667 and 2692-2712.

Recommendation:

- Add See all, pagination, date search, and transparent retention wording.

### R-014 — Medium — Local cleanup retry availability does not cover every failed cleanup entity

Condition:

- Settings derives Retry cleanup visibility from a narrower set of flags than the cleanup coordinator can leave pending.

Impact:

- A failed cleanup can remain unresolved without presenting the recovery action.

References:

- Sources/Features/Settings/SettingsView.swift:474-488.
- Sources/Persistence/PersistenceModels.swift:3518-3557.

Recommendation:

- Drive the UI from one cleanup transaction state that enumerates each pending entity and failure.

### R-015 — High — Other editors also lack consistent unsaved-work protection

Condition:

- Source review was manually confirmed to lose a draft.
- AI Studio's outer close/navigation path is not consistently guarded, even though the in-practice leave flow has a confirmation.

References:

- Sources/Features/Library/LibraryView.swift:1358-1405 and 1586-1604.
- Sources/Features/AI/AIStudioView.swift:145-183, 607-622, and 1038-1065.
- Safer comparison: Sources/Features/AI/AIStudioView.swift:1490-1523.

Recommendation:

- Adopt one reusable dirty-editor/checkpoint protocol for every authored response.

### R-016 — Medium — Notification denial has no direct Open Settings recovery

Condition:

- A denied authorization state is reported, but the control does not offer the standard system-settings route.

Impact:

- The user cannot recover from denial without leaving the app and manually locating its notification settings.

References:

- Sources/Features/Settings/NotificationSettingsControls.swift:19-23 and 60-68.
- Sources/Integrations/System/NFSystemIntegrationCoordinator.swift:1486-1489 and 1504-1506.

Recommendation:

- Add Open System Settings and explain which NeuroForge toggles remain disabled until authorization changes.

### R-017 — Medium — Reaction calibration uses a double-click-style interaction unsuited to touch

Condition:

- The calibration measurement depends on sequential taps/double-click-like timing in a way that is vulnerable to gesture recognition and accidental activation.

Impact:

- The measured result may reflect UI gesture handling rather than learner reaction time.

References:

- Sources/Features/Onboarding/OnboardingView.swift:453-455 and 516-541.

Recommendation:

- Use a clear start/stimulus/tap sequence, discard anticipatory taps, repeat enough trials, and report confidence/variance.

### R-018 — Low — Calibration references Apple Pencil where it is not relevant

Condition:

- Input calibration copy/options can mention Pencil in contexts that are not Pencil-capable or where the tested task is generic reaction input.

References:

- Sources/Features/Onboarding/OnboardingView.swift:457-474.

Recommendation:

- Detect capabilities and only surface Pencil-specific setup on supported iPads, with a task that measures Pencil behavior.

### R-019 — Medium — App language is not applied to every lifecycle and date boundary

Condition:

- Language setup covers the main view hierarchy but not all startup/deletion flows.
- Multiple DateFormatter usages rely on process/system locale instead of the selected app language.

Impact:

- Mixed-language states can recur on cold launch and in sensitive confirmations/history dates.

References:

- Sources/App/NeuroForgeApp.swift:434-557.
- Sources/Resources/NFAppLocalization.swift:8-29.
- Date examples: Sources/Features/Onboarding/OnboardingView.swift:197-201; Sources/Features/Library/LibraryView.swift:593 and 710; Sources/Features/Progress/ProgressAnnotationsView.swift:66 and 125-127; Sources/Features/Progress/ProgressDashboardView.swift:401, 681, and 1010.

Recommendation:

- Inject the selected locale into every scene, formatter, confirmation, and integration payload.

### R-020 — Medium — XP source formatting contains a malformed interpolation path

Condition:

- A Today source string contains malformed interpolation/formatting, currently masked by catalog content in the tested route.

Impact:

- A fallback path can expose raw formatting or an incorrect XP source.

References:

- Sources/Features/Today/TodayView.swift:926.
- Award source comparison: Sources/Adaptive/NFProgressInsightEngine.swift:324.

Recommendation:

- Replace string-built identifiers with typed, localized presentation models and test fallback catalog absence.

### R-021 — High — Medium widget can show the wrong action after completion

Condition:

- Widget action selection and completion presentation do not consistently agree.

Impact:

- A completed user may be offered a start/continue action that opens the wrong app state.

References:

- Widgets/NeuroForgeWidgets.swift:74-78, 85-102, and 147-151.

Recommendation:

- Derive visual state, accessibility label, and deep link from one widget snapshot enum.

### R-022 — Medium — Empty widget state is contradictory and weakly accessible

Condition:

- An empty snapshot can display 0m in a way that looks like a completed/real plan.
- Rings, raw symbols, and abbreviated time lack robust accessible/localized alternatives.

References:

- Widgets/NeuroForgeWidgets.swift:24-34, 95-108, and 135-156.

Recommendation:

- Use an explicit No plan yet state and a localized Open NeuroForge action.
- Provide one concise accessibility label with plan duration, completion, and next action.

### R-023 — Medium — Spotlight results lack content URLs and continuation handling

Condition:

- Indexed items do not carry sufficiently specific contentURL/user activity routing, and the app has no complete continuation handler for a selected result.

Impact:

- Spotlight can index content but cannot reliably take the user back to the exact source, activity, or review.

References:

- Sources/Integrations/System/NFSpotlightIntegration.swift:189-230.
- App routing in Sources/App/AppRootView.swift.

Recommendation:

- Define stable typed deep links for each indexable entity and test cold-launch, warm-launch, deleted-item, and privacy-off behavior.

### R-024 — Medium — Notifications are informational only and do not route to a concrete task

Condition:

- Requests lack categories/actions and enough typed userInfo to open the relevant plan, source, or review.

Impact:

- A reminder tap can only open the app generically, increasing friction and making notification copy overpromise.

References:

- Sources/Integrations/System/NFNotificationIntegration.swift:432-463.

Recommendation:

- Add stable identifiers, action categories, and deterministic deep-link handling with privacy-safe lock-screen copy.

## 9. Missing, unreachable, or incomplete product capabilities

These are not all release blockers. They are product gaps discovered while comparing what the UI promises, what the code contains, and what a user can actually reach.

### G-001 — Quick Practice exists in code but has no reachable Today entry

Priority: Medium

Today defines quick-practice state and a view path, but the main body does not expose it. Either surface a clearly labeled short-session action or remove the dormant implementation to avoid maintaining an untested branch.

Reference: Sources/Features/Today/TodayView.swift:37-45 and 667-689.

### G-002 — Input calibration settings are implemented but unreachable

Priority: High

Onboarding contains calibration and Settings has an InputCalibrationSettings implementation/draft entry, but no user-facing route allows recalibration later. Input characteristics change with device, keyboard, Pencil, and accessibility settings; add an accessible recalibration route with reset/compare semantics.

References:

- Sources/Features/Onboarding/OnboardingView.swift:439-543.
- Sources/Features/Settings/InputCalibrationSettingsView.swift:3-72.
- Sources/Features/Settings/SettingsView.swift:627-635.

### G-003 — Retrieval's Import study material action is not context-aware

Priority: Medium

The retrieval catalog card sends the user to Sources rather than opening import or returning them to a retrieval workflow after import. Preserve intent: open the importer, index the source, then offer Start retrieval practice from this source.

References:

- Sources/Features/Train/TrainCatalogView.swift:659-669.
- Import request handling: Sources/Persistence/PersistenceModels.swift:2232-2239.

### G-004 — Mac Open Export and Open Methodology commands do not open their promised content

Priority: Medium

Both commands select the Settings destination only. Add destination subroutes/scroll anchors so menu commands and deep links land on the exact panel.

Reference: Sources/App/NeuroForgeApp.swift:705-712.

### G-005 — Duplicate scanned-document recovery is incomplete

Priority: Medium

The Library has a duplicate/scanned-PDF recovery branch, but the user-facing flow does not provide a complete compare/replace/retry path. Present filename, fingerprint, existing source, OCR/index status, and safe choices without silently creating duplicate study evidence.

Reference: Sources/Features/Library/LibraryView.swift:843-873.

### G-006 — Empty source-review handoff has no useful explanation

Priority: Medium

When a source cannot produce a review, the handoff can stop without explaining whether there is no text, indexing is incomplete, privacy policy forbids generation, or the source has insufficient chunks. Provide a reason and direct recovery action.

Reference: Sources/Features/Library/LibraryView.swift:549-564.

### G-007 — Reviews deep links only select Sources

Priority: Medium

The neuroforge://reviews route does not open a specific review, queue, or source; it merely selects Sources. Define review identifiers and an actual review destination.

Reference: Sources/App/AppRootView.swift:119-120.

### G-008 — Completed chapters have no answer review

Priority: High

Completed chapter cards remain present but do not open the user's questions, answers, explanations, confidence, or scratchpad. Add a read-only review that preserves the exact content version used for scoring.

References:

- Sources/Features/Today/TodayView.swift:548-565 and 1169-1177.
- Plan sequence/fallback paths in the Today planning implementation.

### G-009 — Practice next is not a launch point

Priority: Medium

Progress makes a recommendation but cannot carry the user into a configured activity. Add a deep link that preserves the recommended skill, mode, duration, source, and rationale.

References:

- Sources/Features/Progress/ProgressDashboardView.swift:365-380 and 858-880.

### G-010 — There is no individual answer-history UI

Priority: High

Ability detail promises answer history but offers only aggregates. Users need a filterable list of date, activity, prompt/version, answer, result, timing, support level, confidence, and explanation, with appropriate source/privacy controls.

References:

- Sources/Features/Progress/ProgressDashboardView.swift:12-41 and 126-132.

### G-011 — Generated sets lack personal attempt history

Priority: Medium

AI Studio can resume a current draft and list recent generated sets, but it does not show previous attempts, per-question outcomes, retries, or improvement across a set.

References:

- Sources/Features/AI/AIStudioView.swift:1513-1523 and 1928-1935.

### G-012 — Export is one-way; there is no restore/import workflow

Priority: High

Settings can export a full archive, CSV, questions, and review data, but the app has no corresponding verified restore or migration path. Export alone is not a backup story. Add versioned archive validation, preview, conflict handling, and rollback-safe import.

References:

- Sources/Features/Settings/SettingsView.swift:314-360.
- Documentation promise/context: README.md:77.

### G-013 — Older retained reports, annotations, and generated sets are undiscoverable

Priority: Medium

This is the product manifestation of R-013. Add See all/history, search, pagination, retention explanation, and explicit deletion/export for each user-authored data type.

### G-014 — Source readiness does not reflect the selected AI/privacy policy

Priority: Medium

Source rows can say Ready for questions regardless of whether the current policy permits question creation or only source review. Show separate Index ready and Question generation availability states.

References:

- Sources/Features/Library/LibraryView.swift:580-637 and 1039-1071.

### G-015 — Adaptive changes have no audit trail or undo

Priority: High

The user sees readiness, weekly mission, Why next, circuit replacement, and regenerated plans, but there is no durable explanation log showing which evidence or preference caused a change. Add an adaptive-plan history with timestamp, old/new state, reason, and Undo where safe. This would make O-002, O-010, O-011, and O-023 diagnosable to users and support staff.

## 10. Accessibility audit

This is an engineering accessibility review, not a formal WCAG or platform certification. The WCAG mappings below identify the most relevant success criteria even though NeuroForge is a native app.

| Finding | User effect | Relevant guidance | Required remediation |
|---|---|---|---|
| Compact iPhone content clips and overlays | Content and controls become unavailable; larger text will worsen it | WCAG 1.4.4, 1.4.10; Apple Dynamic Type and safe-area guidance | Reflow at compact width and every supported text size; reserve overlay insets |
| Table rows/cells repeat without header relationships | The accessibility tree gives VoiceOver no reliable way to associate evidence with claims, labels, or values | WCAG 1.3.1, 4.1.2 | Expose semantic headers, unique cells, position, and table summary; confirm with an auditory pass |
| Progress charts expose only generic ranges | Trend/evidence is unavailable nonvisually | WCAG 1.1.1, 1.3.1 | Provide a named summary and equivalent data table |
| Annotation TextEditor lacks a useful name | The purpose of the editable control is unclear | WCAG 3.3.2, 4.1.2 | Add a visible label linked to the field and a concise accessibility label/hint |
| Annotation Edit/Delete exists only in a pointer context menu | Keyboard and VoiceOver users cannot manage notes | WCAG 2.1.1, 2.4.3, 4.1.2 | Add explicit buttons or discoverable accessibility actions |
| Count selection announces 0/1 | Selection state and control role are opaque | WCAG 1.3.1, 4.1.2 | Use selected traits/radio semantics and announce the group/value |
| Return does not submit and Tab focus is unreliable | Full keyboard users cannot efficiently operate sessions | WCAG 2.1.1, 2.4.3, 2.4.7 | Define focus order, shortcuts, visible focus, and submission behavior |
| Long policy/disclosure content is one text node | Screen-reader users cannot skim by headings or sections | WCAG 1.3.1, 2.4.6 | Use semantic headings, paragraphs, lists, and link labels |
| Direct accent foregrounds can be about 1.61:1 to 3.14:1 on white/light surfaces | Low-vision users may not perceive text/state/boundaries in light appearance | WCAG 1.4.3, 1.4.11 | Test each actual color pair; use appearance-aware semantic colors and redundant cues |
| Raw identifiers are spoken | Prompts and feedback are unintelligible | WCAG 3.1.2, 3.3.2 | Localize all identifiers and validate the content catalog |
| Decorative/error icons are labeled Syncing | Assistive output communicates a false state | WCAG 4.1.2, 4.1.3 | Hide decorative icons; label status symbols from real state |
| Delayed Block replaced alert interrupts a live session | Context changes after focus has moved | WCAG 3.2.2, 4.1.3 | Confirm before navigation and announce completion in context |
| Zero progress uses a nonzero-looking dot and color-heavy status | Progress meaning depends on appearance | WCAG 1.4.1, 1.4.11 | Use accurate geometry plus text percentage/state |
| Scratchpad action is labeled Accessibility and scratchpad | Name does not match behavior | WCAG 2.5.3, 3.2.4 | Rename it or open a real combined menu |
| Practice next cards look interactive but are not | Visual affordance misleads all users, especially magnification/keyboard users | WCAG 1.3.1, 3.2.4 | Make them buttons/links or remove control styling |
| Fixed-height/width dashboard and source regions | Dynamic Type may truncate or overlap beyond the SE issue | WCAG 1.4.4, 1.4.10 | Test all accessibility sizes and replace fixed layout constraints |
| Gray primary CTA and weak secondary onboarding copy | The intended next action can appear disabled and explanatory text may be hard to perceive | WCAG 1.4.3, 1.4.11, 3.2.4 | Give enabled actions a consistent affordance and measure every actual text/background pair |

### Accessibility settings behavior that did work

- Exclude visual-spatial content removed Spatial and Visual paths from the six-path selection, then restored correctly when turned off.
- The 3D Object Rotation activity offered both native 3D and Static 2D modes with understandable descriptive copy.
- Important destructive confirmations were reachable and could be cancelled.
- The main navigation was exposed and Command-1 navigation worked on Mac.

### Required hands-on accessibility follow-up

Before release, perform a complete auditory and input-method pass on physical hardware:

- VoiceOver on iPhone and iPad, including rotor headings, tables, actions, and adjustable controls.
- VoiceOver on macOS with full keyboard navigation.
- Dynamic Type at every accessibility category, Bold Text, Increase Contrast, Differentiate Without Color, Reduce Motion, and Reduce Transparency.
- Switch Control, Voice Control, Full Keyboard Access, and external hardware keyboard.
- Apple Pencil only where the device and activity support it.
- Right-to-left layout if an RTL locale is added; this build currently offers English and Japanese.

## 11. UI/UX simplification and removal candidates

The app would benefit from subtractive work as well as new features:

1. Remove button/card styling from Practice next and completed chapters unless they gain real actions.
2. Remove or disable Submit / Next menu commands when no active session can consume them.
3. Rename Show Train and Show Library to match the visible Practice and Sources destinations.
4. Remove Accessibility from the scratchpad action unless it opens actual accessibility controls.
5. Replace the 20-option generic reflection picker with a smaller context-specific set plus Other. Many options were irrelevant to the activity just completed.
6. Collapse repeated privacy prose into a short summary with progressive disclosure, while preserving a structured full policy.
7. Remove stale Question Writer ready state; readiness should be live, not a permanent historical badge.
8. Remove the false affordance from zero-progress dots and completed-card buttons.
9. Consolidate legacy SessionView/deterministic session implementations or formally retire them. Multiple partially active renderers increase the chance of divergent validation, keyboard, and checkpoint behavior.
10. Decide whether Quick Practice is a real supported feature. Surface and test it, or delete the dormant path.
11. Replace raw-duration microcopy such as 0 sec and bare m abbreviations with one localized time-formatting system.
12. Reduce repeated crossover templates; variety should be a content-quality requirement, not an incidental generator outcome.

## 12. System integrations and Apple-platform coverage

| Integration | What was tested | Result | What remains |
|---|---|---|---|
| Question Writer / Shortcuts | Stale verified state with missing Shortcut; launch from AI Studio | Reproducible app crash, O-001 | Successful physical-device generation, cancellation, provider refusal, timeout, no-network, account/model unavailable |
| Offline AI generation | Six-question quantitative set, hints, answers, feedback, leave/resume | Working | Broader content-quality sampling and every interaction schema |
| CloudKit structured sync | Local-only/unavailable UI state | UI explains local state, but unsigned build has no entitlement | Account switching, multi-device convergence, conflicts, offline queue, quota, schema, deletion |
| iCloud original documents | Privacy/sync selectors in unsigned state | Unavailable path inspected | Upload/download/delete original, partial failures, account isolation |
| Notifications | Settings controls, quiet hours, source inspection | Controls respond; authorization not requested | Permission grant/deny/recovery, delivery, quiet hours, tap routing, background behavior |
| Widgets | Extension embedded in simulator build; source and snapshot path inspected | Cannot validate shared data without App Group entitlement | Every family, Home/Lock Screen, timeline refresh, deep links, accessibility, empty/completed state |
| Spotlight | Master/dependent privacy toggles inspected | Dependency gating works | Real indexing, search result relevance, cold/warm deep link, deletion and privacy purge |
| macOS commands | Navigation, import, submit/next, pause/resume, scratchpad, export/methodology commands | Mixed; see O-017 and O-025 | Full menu validation for every session phase and window state |
| File import | Native macOS picker opened and was cancelled; existing document browsed | Picker and local indexed source work | Signed sandbox/security-scoped behavior, scanned PDF/OCR, corrupt/huge/encrypted/duplicate files |
| Export | Full archive, progress CSV, generated questions JSON, document AI-review CSV | Export preparation succeeded | Round-trip restore, schema migration, share-sheet cancellation, disk-full/permission errors |
| 3D spatial content | Native 3D and Static 2D modes on Mac | Both modes opened | Physical-device RealityKit performance, motion sensitivity, thermal and memory behavior |
| Haptics and audio | Controls/configuration inspected | Not meaningfully testable in simulator/Mac pass | Physical-device timing, silence/quiet-hours interaction, accessibility alternatives |

Production provisioning and integration requirements are also described in:

- Documentation/CloudKitDeployment.md
- Documentation/ShortcutAuthoringDeployment.md
- Documentation/TestFlightAppReviewNotes.md

## 13. What worked well

The audit found meaningful strengths that should be protected with regression tests:

- The Mac and iOS Simulator targets build successfully.
- Onboarding preserves selections when moving backward and clearly separates learning context, rhythm, and baseline choice.
- The baseline can be paused, saved, closed, and resumed.
- A full daily circuit can be completed, including structured responses, scratchpad, reflection, skip, feedback, and summary.
- Core XP and answer attempts persisted across relaunch, even though the daily plan did not.
- All seven practice labs are represented, and the catalog exposes 58 activity entries with working search and filters.
- The catalog's no-results state offers a Reset filters action.
- Logic details and State Trace open correctly.
- 3D Object Rotation offers native and static alternatives.
- Offline AI Studio generation produced a six-question set without network or external model dependency.
- AI Studio hint, feedback, leave confirmation, checkpoint, and resume behavior worked in the tested path.
- Source search, no-results clearing, exact search, browsing, privacy-policy selection, and source-grounded question handoff are present.
- The existing imported product-spec document was indexed into 256 searchable chunks.
- Profile accessibility exclusion, quiet hours, and Spotlight dependent privacy toggles update as configured.
- Local-device deletion and setup-reset confirmations accurately distinguished important data categories in the tested dialogs, and both could be cancelled.
- Full archive, progress CSV, generated-question JSON, and document-review CSV export preparation succeeded.
- Mac Import Study Material opened the native file picker.
- Command-1 navigation worked.
- Relaunch restored the selected English language after the transient mixed-language state was cleared.

## 14. Performance, responsiveness, and resilience observations

### Responsiveness

- The Mac root screen remains usable near its apparent minimum window width, but the session sheet does not adapt well.
- The iPhone SE root and onboarding layouts fail at compact width.
- The iPhone 17 Pro Max onboarding layout appeared visually healthy before simulator instability interrupted the pass.
- A complete iPad layout pass was not possible because the A16 simulator's CoreSimulator service repeatedly terminated.

### Startup

- The iPhone Simulator displayed a blank white launch surface for roughly three seconds in a Debug build. This was not filed as a product defect because Debug/simulator startup is not representative enough. Measure signed Release cold and warm launches on physical devices and provide a branded launch screen that matches the first rendered surface.

### Resilience

- Local offline functionality continued without a server or credentials.
- Pause/resume generally preserved work.
- The app recovered after the AI Studio crash on relaunch, but any unsaved process state was at risk.
- CoreSimulator shutdowns affected both iPhone Pro Max and iPad A16 test targets. There was not enough evidence to attribute those host-service failures to NeuroForge, so they are recorded as test-environment limitations rather than app defects.

## 15. Test limitations and explicitly unverified paths

The following were not skipped casually; they require capabilities unavailable or unsafe in this environment:

- Signed CloudKit private database sync, account switching, conflict resolution, quota/error states, and multi-device convergence.
- Production/development CloudKit schema validation.
- Remote-original document upload/download/delete and two-launch iCloud deletion verification.
- Real push-notification permission, delivery, quiet-hours scheduling, background execution, and tap routing.
- App Group widget snapshot sharing and live Home/Lock Screen timelines.
- Successful Question Writer round trip on a physical iPhone/iPad with an installed Shortcut and supported model provider.
- Spotlight search result selection under real indexing.
- Signed Mac sandbox and security-scoped import behavior.
- Physical-device Apple Pencil, haptics, audio timing, RealityKit performance, thermal behavior, battery impact, and touch latency.
- Full auditory VoiceOver, Switch Control, Voice Control, Full Keyboard Access, and large Dynamic Type matrix.
- Stable iPad split-view, rotation, Stage Manager, and multitasking because the simulator service failed.
- Destructive Delete this device and Delete iCloud & this device completion. The confirmations were inspected and cancelled to preserve user data.
- OCR quality for photographs/scanned PDFs, encrypted/corrupt/very large imports, disk-full conditions, and cloud/network fault injection.
- Japanese through every cold-start, deletion, widget, notification, export, and date boundary.
- Long-duration adaptive validity, spaced-repetition scheduling over multiple real days, timezone travel, daylight-saving transitions, and clock changes.
- App Store/TestFlight installation, receipts, review environment, and production entitlements.
- A populated assessment-report detail view was not available because the test stores contained zero durable report records; the reports entry/empty state and implementation were inspected.
- The entire 58-activity catalog was inspected and representative major interaction families were exercised, but the app's 7,000 bundled question permutations were not individually answered. Content-quality sampling should be automated and supplemented with human review.

These paths should be covered in a signed release-candidate test plan rather than inferred from the unsigned build.

## 16. Recommended remediation sequence

### Gate 0 — Stop-crash and stop-corruption

1. Fix O-001 and test every missing/cancelled/failed Shortcut outcome.
2. Fix O-002 so profile/preferences cannot replace today's committed plan.
3. Make Save and close conditional on durable persistence success, R-001.
4. Fix annotation save/truncation behavior, O-008 and R-011.
5. Add dirty-state protection to every editor, O-007 and R-015.

Exit criteria:

- No external-integration state can crash the process.
- No control labeled Save can dismiss before confirmed persistence.
- Repeated preference edits cannot change the identity/completion of today's plan or duplicate rewards.

### Gate 1 — Restore content and scoring trust

1. Enforce all structured-response schema constraints, O-004 and R-004 through R-006.
2. Make numeric entry fully enterable and locale-correct, O-013 and R-002/R-003.
3. Reconcile Progress totals and coverage, O-009.
4. Separate Transfer from Retrieval end to end, R-010.
5. Remove raw identifiers and run catalog linting, O-010/O-015/O-028.
6. Make mission/circuit changes stable and explainable, O-011/O-023/G-015.

Exit criteria:

- Every generated answer is enterable.
- UI validation and scorer validation use the same schema.
- Displayed evidence totals reconcile.
- No bundled/generated content contains raw keys, unresolved placeholders, malformed punctuation, or wrong skill taxonomy.

### Gate 2 — Compact layout and accessibility

1. Rebuild compact layouts and test iPhone SE plus accessibility text sizes, O-003.
2. Replace repeated table accessibility output with real semantics, O-005.
3. Add chart summaries and data tables, O-020.
4. Label editors, controls, selection state, and context actions.
5. Fix keyboard focus/submission behavior, O-017.
6. Replace low-contrast semantic colors, R-012.
7. Structure disclosure and policy text with headings, O-029.

Exit criteria:

- All content/actions are visible and operable at the narrowest supported width and largest supported text size.
- Core onboarding, daily circuit, AI practice, source review, and Progress can be completed with VoiceOver and with keyboard-only input.
- Text/state/boundary contrast meets the chosen WCAG-equivalent target.

### Gate 3 — Product continuity and recovery

1. Add completed-session and answer history, G-008 through G-011.
2. Make Practice next and import handoffs actionable, G-003/G-009.
3. Add versioned archive restore, G-012.
4. Expose recalibration and decide Quick Practice's fate, G-001/G-002.
5. Add full-history browsing and transparent retention, R-013/G-013.

### Gate 4 — Signed physical-device certification

1. Run the system-integration matrix in section 12 with production-equivalent entitlements.
2. Complete iPad layouts, multitasking, Pencil, and physical input.
3. Complete notifications, widgets, Spotlight, Shortcuts, CloudKit, document sync, and deletion.
4. Repeat accessibility and localization passes on the signed candidate.

## 17. Suggested regression suite derived from this audit

Automated tests are not a substitute for the Computer-driven pass, but they should prevent known regressions:

1. Daily-plan identity remains stable across every preference mutation, partial completion, full completion, relaunch, and day rollover.
2. Missing external Shortcut never crashes and always exposes offline recovery.
3. Every interaction schema has zero/partial/exact/excessive-input tests in UniversalSession and AI Studio.
4. Every generated numeric answer is typeable and parses identically in supported locales.
5. Headline ability counts equal the sum of displayed evidence channels.
6. Transfer attempts never update Retrieval unless explicitly dual-tagged and disclosed.
7. Persistence failure keeps editors/sessions open and preserves in-memory content.
8. Annotation limits never silently truncate and all note actions are keyboard/VoiceOver reachable.
9. Catalog lint rejects raw identifiers, unresolved target placeholders, duplicate words, punctuation collisions, and pluralization templates.
10. Snapshot/reflow tests cover iPhone SE, large iPhone, iPad portrait/landscape/split view, and Mac minimum width at all Dynamic Type categories.
11. Accessibility snapshots verify unique table cells, labeled editors, selected traits, headings, chart summaries, and status announcements.
12. Bidirectional English/Japanese switching updates every visible string without relaunch and persists through cold launch.
13. Widget snapshot state, label, and deep link derive from one enum and agree in empty, active, paused, and completed states.
14. Notification and Spotlight payloads cold-launch into the exact promised destination.
15. Exported archives can be validated and restored into an empty store and upgraded from prior schema versions.

Each release candidate should still receive a shorter direct-manipulation smoke pass across all root destinations, one complete daily circuit, one session per interaction family, one source workflow, one generated set, all integration entry points, and the compact-device layout.

## 18. Test artifacts and state left behind

- Crash report:
  - /Users/takamimarsh/Library/Logs/DiagnosticReports/NeuroForge-2026-08-30-162132.ips
- Mac build:
  - /Users/takamimarsh/Library/Developer/Xcode/DerivedData/NeuroForge-alnciohhyuwzyxbtbabgoeiucyaa/Build/Products/Debug/NeuroForge.app
- iOS Simulator build:
  - /Users/takamimarsh/Library/Developer/Xcode/DerivedData/NeuroForge-alnciohhyuwzyxbtbabgoeiucyaa/Build/Products/Debug-iphonesimulator/NeuroForge.app

In-app test state:

- One local Mac profile with attempts, a reflection, checkpoints, an annotation, generated sets, and the existing imported product-spec source.
- One separate iPhone SE profile with onboarding completed and a started/checkpointed session.
- A saved paused Mental Math draft from keyboard testing may remain on Mac.
- The local annotation was left as: QA note: verified the 500-character limit silently truncates over-limit text.
- Language was restored to English.
- Visual-spatial exclusion, quiet hours, and Spotlight indexing were restored to off/default test state where applicable.
- Destructive delete/reset operations were cancelled.
- Notification authorization was not requested.

This audit itself is the only repository file created by the testing/reporting task. No source fixes were made, because the request was to test and report rather than modify the product.

## 19. Final assessment

NeuroForge's breadth is real and much of the offline learning loop works, but the current build does not yet protect three things a learning product must make dependable: process stability, durable user work, and trustworthy evidence. The crash, same-day plan replacement, compact-device failure, incomplete-answer scoring, inconsistent progress totals, and inaccessible evidence tables are therefore release concerns, not polish.

Once the release gates are corrected, the strongest next investment is continuity: let users review exactly what they answered, understand why the adaptive plan changed, move directly from recommendations into practice, and restore their exported data. Those improvements would make the product feel coherent rather than merely feature-rich.

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

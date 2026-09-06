# Installed-app visual evidence

These are unedited screenshots or extracted failure-movie frames from the installed iPhone SE (3rd generation), iOS 26.5 tests. They certify only their recorded state. See [the experience ledger](../Experience_Status.md) for executed journeys and remaining acceptance requirements.

| Capture | Recorded evidence |
|---|---|
| [Visible sample feedback](SE-sample-visible-feedback.png) | Correct, worked explanation, strategy and setup action visibly coexist. Full sample-to-setup journey passed in the current 01:48:51 bundle. |
| [Verified AX5 onboarding](SE-onboarding-verified-AX5.png) | Actual UIKit accessibilityExtraExtraExtraLarge scaling, active larger-control assertion and contained final actions. Passed in the current 01:48:51 bundle. |
| [Japanese Q3 continuation](SE-Q3-exact-feedback-cold-relaunch-ja.png) | Exact answer 17, original 8 × 7 question at 3/5, saved feedback and persistent Next in the current 01:48:51 run. Passed in 72.806 s. |
| [English Q3 continuation](SE-Q3-exact-feedback-cold-relaunch-en.png) | Exact answer 17, original 8 × 7 question at 3/5, saved feedback and persistent Next in the current 01:48:51 run. Passed in 67.521 s. |
| [Responsive Sources](SE-sources-responsive.png) | Narrow stacked hero and whole-word metadata pills, from the 22:57:34 run. |
| [Nested history return](SE-nested-history-source-settings-return.png) | Saved attempt detail retained after repeated document/Settings/root changes, from the passing 22:44:44 retry. |

Earlier evidence is preserved deliberately:

- `SE-onboarding-accessibility-first-run.png` used an invalid category raw value. **It is not AX5 evidence.**
- `SE-sources-width-failure-first-run.png` records the word-breaking failure before the responsive hero fix.
- `SE-external-interruption-paused-first-input.png` records another app taking the foreground during the 23:10:37 English test. The corresponding NeuroForge hierarchy showed a correctly paused session.
- `SE-numeric-input-focus-failure-before-44pt-fix.png` records the distinct fresh-simulator failure: a visible 35pt numeric field did not gain focus from the standard center tap. The 44pt target and explicit focus fix awaits the final installed rerun.
- The Japanese `-before-sticky-next` and `-dark` captures retain earlier versions. First-run Practice/Progress captures are representative states, not a whole-app acceptance certificate.

Result bundles live under `/tmp/NeuroForge-improvement-ios/Logs/Test/` with the recorded 4–5 September dates and times. They were exported with `xcresulttool`; no screenshot was synthesized from a design or reconstructed from a log.


The following failure frames were extracted from the finalized 19-journey run `Test-NeuroForgeUISmoke-2026.09.05_00-09-16--0400.xcresult` and visually reviewed. They preserve the observed failure, not a pass:

- `SE-expanded-EN-resume-short-touch-failure.png`: Q3 remains paused after one50ms center touch on Resume; no unavailable or error state appears.
- `SE-expanded-JA-next-short-touch-failure.png`: original Japanese Q1 answer and feedback remain after one50ms center touch on the visible Next action.
- `SE-expanded-history-short-touch-failure.png`: the saved-answer card remains in the History section after its50ms center touch.
- `SE-expanded-logic-choice-obscured-by-footer.png`: the desired choice lies under the fixed Submit footer; the old test incorrectly trusted its hittable flag without revealing the entire control.

Synthesized touch records and full accessibility trees accompany the original result. The first three demonstrate intermittent50ms-touch behavior on this simulator/host; they do not establish a framework defect or certify physical-device/stable-OS behavior. A bounded one150ms press at these exact interactions, without retries or relaxed state assertions, is queued for verification.


Current Q3 EN/JA images now come from the finalized00:39:37 run: English passed68.002s and Japanese75.857s. Both visibly retain answer17, the original8×7 question at3/5, feedback and the persistent Next action. The earlier English capture is preserved with `-before-sticky-next`. `SE-logic-state-visible-feedback.png`, `SE-quantitative-unit-visible-feedback.png`, `SE-retrieval-neutral-self-check-feedback.png` and `SE-spatial-visible-feedback.png` are visually reviewed captures from passing native response journeys in that same run; they establish those depicted response schemas, not all catalog families. `SE-clarification-before-visible-guidance-fix.png` is retained evidence of guidance hidden below the keyboard before the focus/visibility fix; it is not a visibility pass.


## Current correctly installed 20-journey run

All 20 native installed journeys passed in `Test-NeuroForgeUISmoke-2026.09.05_01-48-51--0400.xcresult`, ending 02:03:04 on 5 September. Parent verified the installed runner and its live container before execution after diagnosing the prior stale-runner mismatch. Attachments were exported only after finalization to `/tmp/nf-ui-current20-attachments`; the copied originals are mapped in `current20-capture-manifest.json`.

| Current capture | Visually inspected evidence |
|---|---|
| [Claim mapping](SE-claim-mapping-visible-feedback.png) | Named evidence relationships and the actual Correct heading/explanation remain readable above Next. |
| [Visible clarification](SE-clarification-visible-guidance.png) | Original 35-character draft at 1/5 and complete reviewed-answer-coverage guidance appear above Submit with the keyboard dismissed. There is no score or fabricated result. |
| [Exact source cold recall](SE-source-exact-cold-recall-neutral-feedback.png) | Original recall and “not yet” rating at 1/1, neutral Self-check saved title, personal-study scope and View summary. The test also cold-reopened this same saved feedback and verified reference hiding before reveal. |
| [Finite logic](SE-finite-logic-conditions-retained-feedback.png) | Original 1/5 answer/result retained with honest no-fresh-question reason and reachable End session. |
| [Finite ordered proof](SE-finite-ordered-proof-retained-answer.png) | Exact submitted sequence retained at 1/5 and explicit End session; this particular viewport shows the sequence rather than the below-fold result title. The prior visible-result assertion and subsequent ended-summary assertion both passed. |
| [Finite science](SE-finite-science-confound-retained-feedback.png) | Original 1/5 response and feedback retained with shortage reason and End session. |
| [Finite transfer](SE-finite-transfer-retained-feedback.png) | Both submitted choices and original 1/5 result retained with shortage reason and End session. |

The four finite tests each subsequently activated End session and asserted “Ended after 1 of 5 questions”; these screenshots capture the pre-end retained state, not the summary. EN/JA Q3, sample and verified AX5 images in the table above were replaced with this run's actual captures. Earlier failures remain separately named and are not represented as passes.

This binary predates the subsequent accessibility-heading-focus, typed timing-separation and scratchpad recovery patches. It provides no manual VoiceOver/hardware-keyboard, all 58-family, protected-mode, physical-device or full responsive-matrix certification.


Expanded 22-journey run: 21 passed, one test-selector failure. The live injected runner hash was verified against `Expanded_UI_Installed_Binary_Manifest.json`; this run did not use a Dead container. [Source chooser](SE-source-chooser-selection-search.png) was visually reviewed: the selected synthetic source remains checked after search/clear, with its preparation status, local route and source-detail action visible. The complete select/search/clear/close/reopen/remove journey passed in 41.583 seconds. [Energy preview](SE-energy-preview-before-apply-prior-title.png) shows the proposed Normal → Low change, concrete remaining plan and reachable Apply action. The test then failed before a tap because a generic query matched both the Cancel wrapper and the single actionable Cancel button. Its corrected typed Button query and subsequent cold-relaunch assertions await the next run. The captured long title truncates on SE; source now uses the concise localized “Energy preview,” also awaiting a replacement capture. These screenshots predate the new safe-exit, contextual scratchpad and chart inspection changes. See `expanded22-capture-manifest.json` for exact attachment/hash mapping.

The 05:28:09 five-journey retry passed logic-state locking, quantitative response/inspection, exact source cold resume, and finite transfer (4/5; 352.576 seconds). The weekly chart journey failed because its query used “1 answer” while the actual row says “1 scored answer”; the corrected query retains the complete matching-history/original-detail assertions, still pending execution. Latest logic/source/transfer captures above now come from this retry. [Quantitative visual omission](SE-quantitative-table-values-not-visible.png) records missing drawn count values despite their AX presence; the subsequent explicit numeric Text fix is awaiting installed visual verification. See `native-five-capture-manifest.json` for exact input and attachment hashes.


## Latest finalized23-journey captures — 06:17:04

The correctly injected23-test runner completed21 passes and2 failures in1052.634s. The [manifest](journal-ordered23-capture-manifest.json) records exact input/binary references and source attachments. [Original data counts](SE-quantitative-original-counts-visible.png) now visibly show43 and21, resolving the earlier numeric-drawing omission. [Energy preview](SE-energy-preview-before-apply-en.png) and [source chooser](SE-source-chooser-selection-search.png) were refreshed from passing journeys. [English Q3](SE-english-q3-latest-cold-feedback.png) shows the original8×7 prompt, saved feedback and Next after cold relaunch.

[Weekly data](SE-weekly-chart-date-activity-count-credit.png) establishes the actual Aug31/MentalMath/0%/1 scored answer row. The final AX tree contains correct scoped History and the original10×9 attempt, but a stale index-bound ScrollView query failed during navigation before detail opened. [Japanese Continue](SE-japanese-continue-unacknowledged-0617.png) remains a failed standard tap with Today visible and no recovery error. Neither failed journey is counted as a pass. [Ordered feedback](SE-ordered-feedback-empty-footer-label-observation.png) preserves an empty-looking Next pill at the captured instant despite the later passing forward action; its cause remains unverified.

These captures predate the subsequently integrated math stages, live trace and denominator-overlay interactions. Earlier failure images are retained separately and are not replaced with invented pass evidence.

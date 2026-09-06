# Independent review of local session integrity

Reviewed `NFLocalSessionRepository`, `NFUniversalSessionRuntime`, and the `AppStore` attempt/checkpoint write boundaries on 4 September 2026. Findings were sent directly to the coordinating runtime implementer; this review did not edit their production files.

| Finding | Concrete consequence | Required fix / observed response |
|---|---|---|
| Advancing after failed commit-tail checkpoint | The attempt saves but the dependent checkpoint fails; `Next` can activate another item and skip the retry stage | Coordinator added checkpoint success gating before next selection. Regression: `testFailedFeedbackCheckpointCannotActivateNextQuestion` |
| Protected export redacts only top-level results | Legacy `request.resumedResults`, credits, response payload, and reflection clues remain nested in a portable archive | Coordinator added canonical `launchOnly()` request and protected reflection clearing. Regression: `testProtectedExportRemovesNestedLegacyOutcomesAndReflectionSuggestions` |
| Personal draft copied into sync-eligible checkpoint | A new source draft/scratchpad enters the old SwiftData checkpoint despite local envelope storage | Coordinator gated the legacy mirror for personal/source content. Regression: `testPersonalDraftDoesNotEnterSyncEligibleCheckpointModel` |
| Skip has no prepared outcome journal | Termination after skip attempt save but before the next slot checkpoint restores an editable prior item with an already-skipped attempt ID | Coordinator added a pending skip transition. Prepared-skip reconciliation regression added; subsequent follow-up identified the need to freeze edits and reconcile from the Retry action while skip persistence is pending |
| Pending attempt branch lacks payload conflict check | Editing/retrying a prepared attempt can flush the old pending response while displaying the newly computed score | Coordinator added immutable payload comparison in the pending branch and protects a prepared answer from reopening |
| Decoded duplicate disposition identities | `Dictionary(uniqueKeysWithValues:)` can trap during reconciliation on a malformed existing archive | Coordinator added identity validation on load; malformed archives retain their original bytes |
| Whole archive re-encoded during each autosave | Every 500 ms draft update serializes all saved sets, snapshots and sessions up to the 64 MiB cap | Scale/performance gate remains; per-run/per-snapshot storage or measured partitioning is needed before claiming the full large-store budget |
| Clock starts during constructor rather than readiness acknowledgement | Generation and initial loading can enter answer duration | Runtime now exposes `acknowledgePresented()` and its visible content surface calls it only after durable preparation; answer/sitting clocks remain stopped during construction and initial preparation |
| Sitting budget uses answer durations only | Feedback and confidence interaction do not consume the advertised sitting budget | Separate persisted sitting-active chunks now include confidence/feedback; narrower answer chunks freeze at lock and during explicitly observed confidence interaction; known pause/relaunch gaps are excluded |
| Interruption count carries into later items | One interrupted item can mark subsequent clean items interrupted | Per-item reset implemented; restored answer-duration completeness stays false until the next item |

`Tests/SessionIntegrityReviewTests.swift` contains nine actual runtime/store regressions. All nine passed in the full app run at 22:20 EDT on 4 September 2026. The coordinating app test run is the execution authority; these tests were not included in the isolated adaptive policy test harness. Tests inspect digest tampering, atomic import rejection, conflicting draft preservation, foreign-owner identity across re-export, and coordinated window takeover. No migration or device certification is implied by this review.

## Runtime sitting-budget integration

`SessionWorkloadBudgetTests` adds five actual-runtime tests covering: clocks begin at durable presentation; observed confidence/feedback remain in sitting time but not answer duration; pause/relaunch retain known chunks without the inactive gap; missing reviewed duration offers an explicit five-question request without persisting an exposure; fixed-count practice continues after an advisory time target; and a protected sitting resumes the same session, frozen candidate pool, coverage and exclusions. All five passed in the coordinator's app run at 22:20 EDT on 4 September 2026.

Compatibility changes are deliberate:

- A supplied question count remains the promised workload even if an advisory minute target is present.
- Minute-only ordinary practice requires reviewed duration ranges. Unreviewed content presents an explicit count-based alternative instead of silently inventing a range or forcing three questions.
- Protected legacy duration estimates remain advisory and do not establish reviewed band evidence. At a time boundary the local envelope is suspended with the same form/catalog snapshot; the next sitting resets sitting time only. Coverage, prior responses and selected IDs persist. Cap/pool exhaustion remains an incomplete stop.
- Constructor elapsed time is no longer learner work. Injected-time tests must durably prepare and call `acknowledgePresented()` before advancing their clock, and prepare the restored runtime before resuming it.
- Protected portable export must redact both the cached assessment state and candidate snapshot; the coordinator owns that export boundary.

The runtime and checkpoint structs compiled in the full app run. All 14 tests in the two runtime review/budget classes passed. The complete 652-test run still had 12 assertion failures outside these classes, so this report does not claim a passing full suite. Device readiness/focus coverage and large-archive performance remain separate gates.

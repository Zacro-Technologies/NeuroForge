# Review queue and durable deferral implementation

## Verification boundary

The full Mac run on `8bb54c57610b8c265876c2e60176872b03f82e9dee54f5a258abacbd85bf597e` passed all 1,092 tests, including all 11 `ReviewDeferralTests` and the scheduler fixtures below. The retained log is `Retrieval_Authority_1092_Passing_Run.log`. Installed deferral interactions, notification delivery and manual accessibility remain unverified; this does not establish reviewed retention proficiency.

## Implemented behavior

- The review queue, Today shortcut, new retention requests, Today sequence, disposable Today time estimate, and notification due date derive from the same effective reminder origins and supported deferral records. Quarantined origins and marker-only protected history are excluded before queue presentation or launch.
- A deferral stores its profile, memory item, originating independent attempt, source family, request time, configured local day boundary, time zone, and absolute return instant in the existing private organization archive. It neither edits an attempt nor changes credit, confidence, bands, evidence, or the compatibility interval. The stored return instant remains fixed when the learner travels. A new qualifying independent result invalidates the old anchor-specific preference.
- The UI returns deferred entries to Due now at the configured next local-day boundary. It lists them under Saved for later beforehand. Unknown, duplicate, malformed, unbounded, or unsupported metadata is retained as unavailable, displays recovery guidance, cannot be overwritten, and cannot silently suppress ordinary reminders.
- Metadata publishes through the existing revision-checked atomic local repository write. Failed writes leave the queue, observable revision, original attempt bytes, and prior private payload unchanged. A peer revision conflict never overwrites a peer bookmark; retry requires loading that current repository state rather than merging stale preferences by guesswork.
- New standalone reviews use a separate `.focused`/`.retention` run with at most five due targets from one activity and explicit question count. All due entries remain visible in the queue even if the current frozen Today plan contains a smaller subset. Empty or stale target lists fail explicitly; not-due and deferred targets do not fill remaining time with unrelated practice.
- Today execution projects only eligible targets from its frozen target list. Original target order and seeds survive. The canonical plan record and already accepted exact session drafts remain unchanged. An accepted review must be continued or ended before its remaining targets can be deferred.
- New review generation recognizes the two explicit shipped template editions, v3 and v4. Known non-shift mechanics cannot fall back to a different broad lab mechanic when their finite candidate set is exhausted. Unknown families return explicit content unavailability. This new selection does not regenerate an existing saved question.
- Review completion saves against the original scheduled memory identity and appends a new attempt. Existing compatibility rules require due, fresh, full, unassisted success to refresh their one-day reminder; the original failure/result is never rewritten.
- Due cards show activity, reason, and bounded estimated length without original answers. Saved and recently repaired rows apply the same protected-first history projection before constructing titles or results. Removing a bookmark preserves notes, reflection history, original attempts, and source provenance.
- The existing deletion cleanup removes deferrals anchored to deleted attempts. Supported private metadata travels through the existing local archive export/import route and account partition. AppRoot refreshes already-permitted notification schedules when the deferral signature changes, through its existing isolation/permission guards.

## Regression fixtures executed in the full 1,092-test run

`ReviewDeferralTests` in `Tests/LocalLearningLifecycleTests.swift` includes these regression cases:

1. Exact next boundary across spring daylight-saving change and no repeated-tap extension.
2. Travel preserves the accepted instant; a fresh anchor does not inherit a stale deferral.
3. Unknown/duplicate records cannot hide normal reminders; old metadata still decodes.
4. Real directory write failure preserves bytes; retry, cold read, supported private export/import, and deletion cleanup.
5. Stale peer metadata write cannot erase a peer bookmark or acknowledge a deferral.
6. Future/unbounded metadata stays retained and does not suppress the natural schedule.
7. Authentic canonical Today projection, pinned target/seed preservation, stale sequence revalidation, accepted-target rejection, and exact checkpoint decode/restoration.
8. Authentic standalone launch, explicit count, fresh semantic selection, scheduled memory identity on append, and refreshed due date without rewriting original history.
9. All-due deferral yields no launch, a consistent next reminder date, and exact expiry eligibility.
10. Quarantine plus marker-only protection prevents stale launch and private queue disclosure; bookmark removal preserves original history and notes.

Two tests in `Tests/AssessmentSchedulerTests.swift` cover explicit v3/v4/full-memory family selection, unknown-family refusal, and authentic finite `conditions.divisibility` exhaustion. The prior matching test now requires a non-nil oracle token and a usable result, instead of allowing `nil == nil` to hide an unrecognized shipped edition.

## Remaining boundaries and gaps

This is the effective **legacy practice reminder** path. It does not manufacture reviewed B1–B4 contracts, certify retention mastery, or claim the reviewed 1/3/7/14/30 progression is supplied by the current legacy catalog. Those content/review gates remain in the adaptive/content ledgers. Personal source self-checks remain personal records and are not promoted into objective due evidence.

No cross-process metadata auto-merge is introduced. A stale writer fails safely and needs a fresh repository view before a successful retry. Actual OS notification rescheduling/delivery, installed deferral interactions, assistive technology behavior, and multi-window queue refresh still require execution evidence. Queue reduction continues to use the existing store projection; this change does not close the broader background architecture or percentile performance requirements. Durable multi-store restore journaling remains tracked separately in `Restore_Recovery_Design.md`.

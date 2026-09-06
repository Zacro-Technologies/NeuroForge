# Protected and ending transitions — immutable checkpoint publication

All eight new authentic protected transition tests passed inside 36 exact continuity methods; the complete scope passed 146/146 on 65f7773d. Source is integrated. The full regression and current installed journeys remain separate evidence.

Scratch-only package. Apply `protected-transitions.patch` against `base-sha256.txt`; two existing files change, no new project files/model columns/localized keys. Parent owns app builds and test execution.

The ordinary shared coordinator now accepts protected progression too: practice preview → protected item, protected answer → next item, acknowledged protected skip → next item, automatic stop → summary, and saved sitting → next sitting. Complete proposals are prepared from the acknowledged checkpoint and its retained assessment catalog/state. The next descriptor is verified against that exact catalog; protected question/score material stays out of generic snapshot fields. Slot, attempt, index, phase, sitting counter and reset clock are published only after the proposed local checkpoint saves.

The skip receipt remains the immutable no-score activity. Its acknowledged event can update derived selection exposure, idempotently; pendingSkip remains set while a next/summary write fails. Exact cold recovery therefore retains the same skipped item/intent and does not select it again or add the duration twice. Known acknowledged current activity is also excluded from in-progress duration and legacy committed-position duplication.

Manual End follows the same saved-boundary protocol for ordinary, source and protected sessions. Unfinished response/scratchpad/phase context remains in the terminal checkpoint; ending creates no fake score or skip. If a skip is already waiting to advance, End acknowledges that same receipt and saves its terminal state directly without selecting another question. A prepared answer must reconcile its frozen commit first. A narrow `allowsUnpreparedEnding` flag permits a confidence-stage draft with no prepared intent; it does not permit abandonment of a prepared outcome. `continueSitting` is a distinct coordinator command whose only source phase is summary.

The local archive remains authoritative when a later legacy projection fails. An accepted next item is not retracted after that secondary failure. Failed next/summary writes leave the prior visible state intact; the clocks exclude transition storage time. The full synchronous persistence API is retained; this is not the asynchronous storage migration.

## Verification performed

- Complete modified Swift source and test files passed frontend parse.
- `git apply --check` passed against recorded main.
- The exact new coordinator, whole ordinary runtime, current same-file typed sidecar extensions and all eight new tests passed strict Swift 6 typecheck against the compiled app's real model/repository/AppStore types. No stubbed persistence implementation was needed for this package.
- No app build, unit test execution or installed UI test was run by this subagent.

## Eight new ExactSessionContinuityTests methods

1. Real next-file obstruction after the current feedback save retains original exercise/response/slot and byte-identical receipt; retry and actual local-file reopen recover the exact accepted protected descriptor.
2. Practice preview feedback stays visible after failed first protected publication.
3. Protected skip failure retains one no-score receipt/exposure, exact duration and pending intent; cold local reopen reconciles once.
4. Automatic sitting stop and continuation preserve summary/time/ordinal/current question through failed publication and reset only after acceptance.
5. Unscored confidence-stage End preserves response and scratchpad, does not publish a failed summary or create an attempt, and is terminal-idempotent.
6. End after a saved protected skip consumes no next question and retains one immutable activity.
7. Accepted protected Next remains published when only the later legacy projection fails.
8. Prepared protected answer cannot be abandoned by End; retry commits its original attempt ID once before terminal acknowledgement.

Suggested execution: new eight methods plus all ExactSessionContinuityTests and SessionIntegrityReviewTests, followed by the ordinary/generated shared-coordinator and full regression suites. The first test uses a real filesystem obstruction; the other failure seams are DEBUG-only closures immediately before the real local write or after it before the existing legacy projection.

## Still separate engineering work

Generated terminal compaction must release unused unsaved future inventory without losing actual run scope/current work. The reviewed initial-band catalog UI/forwarding remains separate. Writer-generation fencing for every remaining command and off-main durable transaction APIs are still required. Neither this package nor the existing native/simulator journeys certify all physical keyboard, VoiceOver, multi-window or release acceptance paths.

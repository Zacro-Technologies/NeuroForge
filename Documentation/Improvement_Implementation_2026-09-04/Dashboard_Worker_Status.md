# Dashboard background reductions

Root-authored implementation, actual full Mac/iOS compilation and execution pending. Initial source008fa7 failed compile because errorPatternsCard still referenced diagnosticProjection.isLoading; sourceaaae840 supplies dashboardProjection.isLoading. No earlier passing run covers this worker implementation.

The visible Overview now captures filtered immutable effective/public/diagnostic observations once for a request. Its key contains a fresh nonserialized AppStore UUID after every physical reload (including same-ID replacements and conflicts), current local archive transaction revision (corrections/deletions), filter values, local day, and selected progress section. The old full-observation array is no longer rebuilt solely to compare diagnostic change keys on every SwiftUI render.

A cancellable detached worker derives reviewed summaries, evidence counts, existing confidence calibration, weekly chart points, and error patterns. The existing domain reducers and protected/public observation boundary are reused. New requests immediately withdraw the old derived snapshot; the UI shows a localized EN/JA loading state while keeping filter and section controls available. Publication requires the exact ephemeral generation; older success after cancellation cannot replace a newer corrected result. Cancelling the projection cancels its active worker and has no durable repository command.

Authored tests: real AppStore correction while an old successful result is held, followed by proof that late success cannot restore withdrawn chart/count authority and original records are unchanged; cancellation/empty filter with exact archive bytes unchanged;10,000 immutable observations on a held real worker with MainActor responsiveness and exact public chart membership/counts. No elapsed-time performance target is claimed from the latter fixture.

Remaining engineering: live-model capture/DTO decoding is still MainActor work. Consistency, mental-math metrics, Forge/priorities, legacy historical projections, reload/migration reconciliation, and ability-detail aggregation are not migrated by this bounded slice. Full generation sensitivity includes calendar settings in the next small follow-up; the current key has local-day but not calendar configuration itself. Native Progress filter/chart/loading journeys, meaningful representative performance measurements and the full device/accessibility matrix remain pending.

## Executed verification

The full Mac suite passed 1,362/1,362 tests on source `aaae840e`, including all three real worker tests. A subsequent source review found missing invalidation for incremental core saves, quarantine changes, failed conflict journaling, and clock/calendar changes. Those follow-ups remain required; installed dashboard verification is pending.

## Refresh follow-up execution

Source `8dd5232a` passed all four added actual-store refresh tests within a 154/155 partial Mac run; source `b7fe7284` passed them again within the 1396/1397 partial full run. Incremental saved attempts, quarantines, conflicts including failed journal writes, complete calendar settings and active date/foreground changes now invalidate the worker snapshot. The late-result generation and exact current-request render guard remain in force. A verified installed `8dd5232a` binary passed the weekly-chart-to-exact-history journey (55.134s). This does not establish the full filter/device/performance matrix. The subsequent engagement/math worker package is integrated and execution is pending.

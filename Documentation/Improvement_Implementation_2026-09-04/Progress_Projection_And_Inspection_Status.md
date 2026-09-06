# Progress projections and point inspection

All six projection/inspection tests passed in the later complete 852-test run with zero failures. The subsequent installed 23-journey run passed 22 checks; the new chart-history journey failed at Submit before reaching the chart. Installed chart inspection is still pending. It addresses remaining UX-023 and effective-evidence presentation gaps; it does not establish reviewed editorial demand, empirical improvement or complete accessibility acceptance.

## Implemented behavior

- Weekly and cumulative charts consume effective immutable AttemptDTO values, including correction and conflict exclusions. Identity duplicates count once; conflicting copies, self-reports, future dates and nonfinite or out-of-range numeric values do not choose a displayed result. Weight scaling avoids overflow on large retained legacy values.
- Ability headlines, eligible counts and per-channel credit share those same effective observations, including cross-activity skill attribution. Original SwiftData attempts remain unchanged and available in history.
- Each chart point retains the exact contributing attempt IDs. Cumulative points share one immutable series buffer and prefix ranges instead of copying quadratic ID arrays. Running-prefix weight normalization preserves early valid points when later weights are much larger. History membership is hashed once and materialized only on an explicit navigation action; accessible tables page 50 rows at a time.
- Public performance charts exclude reusable protected per-answer results. Baseline/reassessment source markers receive the same protected history classification as explicit evidence markers. Safe category totals are separate from scored point rendering.
- Each chart point provides a scoped inspection. Native date/index selection displays date, activity or practice type, sample count, earned-credit value and a history route. Weekly selection displays every activity represented at that week; cumulative selection routes to the preceding answers within that series. Accessible table rows also open the matching history.
- The former three-answer transfer-gap message asserted unfamiliarity and restricted learning gains without comparable-task evidence. The view now describes separate practice-type averages and explains their unestablished comparability. An impossible legacy speed-unlock invitation is replaced by the missing-context reason.
- Mental-math details use the AppStore effective adapter and authenticated retained contracts; the legacy aggregate is labeled Practice accuracy. Unknown reviewed independence, strategy, timing and transfer relations are not invented.

## Verification

Six ProfileProgressContracts tests exercise actual AppStore corrections/withdrawal with original-history preservation; identity conflicts, future/invalid inputs and extreme weight arithmetic; exact weekly/cumulative history membership; protected per-answer exclusion including baseline/reassessment-only source markers; consistent cross-activity attribution; and a 10,000-point shared-buffer/prefix-scaling regression. Existing weekly and cross-activity attribution tests remain applicable. Installed chart inspection and current-surface screenshots are pending. Accessibility table links provide an alternate route, but actual VoiceOver, hardware keyboard and the complete responsive matrix still require execution.

## Quantitative question data inspection

A later INT-003 slice adds NFInspectableDataProjection and NFDataInspectionView to the actual ordinary representation renderer. Only the retained, current observed-proportion practice contract authorizes the conversion: its two exhaustive outcomes are observation counts. Bars, native category selection, keyboard-accessible picker and real data table use the same original labels and integer count strings. The vertical scale begins at zero, count units remain explicit, and the learner's percentage response is a separate untouched control. No explanatory overlay or inferred result is introduced.

Protected, nonpractice, future, unrelated, worked-example and malformed table contracts stay outside this renderer. Three new content regressions cover actual English/Japanese generation, source/count/percentage agreement, identical pointer/picker selection identity, and malformed/protected/future exclusion with unchanged original bytes. The installed quantitative journey is extended to inspect the second category and table while preserving its entered answer. These later source/tests await the new integrated build and installed run.

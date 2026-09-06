# Background preparation and defensive rendering

The initial784-test baseline below has been superseded by full1,021-test and later scoped results in Run_Manifest.json. Keep initial design descriptions separate from actual acceptance.

## Archive preparation

Settings reads, normalizes, redacts protected portable fields and decodes the selected JSON in a detached disposable worker. An immutable Sendable prepared archive crosses back to MainActor. Preview and commit use this same value; changing or deleting the selected external file cannot substitute a different archive after preview. Semantic conflict checks against the live destination run again before commit. Cancellation invalidates the UI request generation and cannot start a restore.

The reader checks file size and also limits actual chunked reads to64MiB plus the one byte needed to detect growth beyond the limit. Security-scoped access lasts through preparation. The selected file is never rewritten by preparation. New fixtures cover exact preview/commit bytes after external substitution, cancellation without accepted work and oversized input before decoding.

The compensation-only restore path is superseded by the durable accepted journal, startup process lease and cold two-store/exact-file coordinator documented in Restore_Runtime_And_Linked_Deletion_Status.md. Actual cold and cleanup tests pass; installed/physical acceptance remains. Production startup archive reads now use the verified background preparation below. Whole-archive writes and other bulk projections still require asynchronous/paginated work and measured performance.

## Public diagnostic projection

A MainActor adapter captures immutable effective attempt values and current interpretations. Protected classification runs before carrying an error code into the worker; holdout and near-transfer evidence are also excluded at the pure boundary. Corrections and conflict dispositions can withdraw a pattern without rewriting original answers. Duplicate identities cannot manufacture repeated errors, conflicting duplicates are excluded, and future/nonfinite inputs are omitted.

Grouping and sorting run in a detached worker. A generation ticket prevents late work from publishing after a new correction/filter or cancellation. Prior authoritative results disappear immediately when invalidated. Invalid floating-point inputs have reflexive change detection so they cannot trigger an endless view update loop. Unsupported empty strengths/confidence/due arrays no longer produce false zero-result claims in the dashboard.

Three added tests cover actual AppStore dispositions and marker-only protection, off-actor immutable reduction, and late-publication rejection. Their integrated execution is pending.

## Spatial rendering

The diagram boundary refuses invalid difficulty vectors, nonfinite/out-of-Float-range coordinates and more than128 points before Canvas or RealityKit work. Original descriptions and snapshots remain retained with an explicit unavailable message. Large numeric labels use scientific formatting instead of trapping Double-to-Int conversion. The same representability guard rejects new unrenderable scored stimuli; it does not alter historical response bytes or results.

Two added tests cover extreme/nonfinite geometry, bounded point counts and huge numeric labels. Pencil drawing bounds and history recovery are documented separately in Scratchpad_Recovery_Status.md.

## 5 September: production local-session startup integrated and executed

`NFAppStartupController` now awaits a detached, bounded local-session reader after account classification and cold restore, before constructing AppStore or publishing integrations. The worker runs the actual granular decoder and full archive validator. A private immutable packet carries the original digest, revision, owner and a held shared lease on the same file lock used by writers. MainActor adoption checks the launch generation, cache publication and source/lock identity without reading or decoding the full archive again. Cancellation and stale publication preserve the predecessor. Symlinks/FIFOs and oversized sources are rejected. Granular recovery preserves the exact private original backup before adoption; failed backup leaves readable recovery data with writes blocked.

All nine actual-file startup tests passed in the 85-test run on `ac4285803927eaa85dcc426630c9afccf6d27d0d4617b2432315e940800f1311`, including 2,000 real snapshots, off-main responsiveness, cancellation, competing writes, source substitution, stale launch, unsupported schemas and recovery backup failures. The same-source installed cold restore test passed in 53.239 seconds and exercised this production loader. This establishes those paths only; it does not establish Release p50/p95 budgets, physical devices, asynchronous whole-archive transactions or complete bulk projection work.

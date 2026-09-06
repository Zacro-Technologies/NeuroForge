# Granular history snapshot recovery — 5 September 2026

This implements the bounded local-history portion of DATA-020. All six granular recovery tests passed in the root-owned integrated Mac run at 01:39:36 on 5 September 2026. It does not claim completion of media decoding, asynchronous rendering, every malformed portable import, or all specification acceptance tests.

Previously, a single undecodable NFLocalAttemptSnapshot exercise caused the whole local Archive decode to fail. Independent SwiftData attempt rows survived, but all otherwise valid local snapshots and private drafts became unavailable. The repository now decodes only the independent history-snapshot array element by element. A supported valid exercise remains readable. An identifiable malformed, oversized, unsupported-version or protected exercise becomes an NFUnavailableHistorySnapshot marker containing only its attempt ID, canonical-element SHA-256 digest and fixed reason. No replacement exercise, key, correctness or model answer is invented.

The 64 MiB file bound is checked before JSON decoding. Each history snapshot has the existing 8 MiB snapshot bound before typed exercise decoding. Unidentifiable entries, global duplicate identities, unsupported archive versions, malformed sessions and invalid ledgers/receipt references still fail closed as a whole. Sessions and reservation members are never silently discarded. Unknown saved presentation versions mark affected sessions as migrationRecovery rather than admitting them to the resumable list.

Before any recovered projection can overwrite its source file, the entire bounded original file is saved byte for byte in a repository-specific local recovery directory. The directory is0700, files are0600, and iOS uses protected atomic writes. Recovery storage has an aggregate64 MiB bound. A failed backup leaves the source file unchanged, permits the recovered valid history to be read, and blocks repository mutation through loadError. A successful later journal write can serialize the valid snapshots plus unavailable markers while the original remains recoverable locally. The opaque backup is not part of Codable Archive and never enters automatic portable exports.

Raw assessmentProtected is checked before an exercise is decoded. A protectedContent marker preserves protected-first history and accessibility restrictions even when an inconsistent AttemptRecord claims ordinary practice. Full portable JSON and both CSV projections use the same marker restriction, including marker-only withheldProtectedConflictAttemptIDs imports; no key or per-item result is revived by removing the corrupt snapshot. The local backup may contain unknown private/protected bytes, so it is deliberately excluded from portable content. The export contains the unavailable marker, not raw JSON or base64 backup data.

Linked attempt/source/generated-content cleanup conservatively removes unclassifiable recovery backups; whole-device/account directory removal includes these files. A retained unavailable marker cannot be silently replaced by a newly attached snapshot under the same attempt ID. Marker import and conflict/evidence integration are coordinated with the adaptive agent's repository changes.

The history detail uses historySnapshotUnavailableReason to explain this specific unavailable item and retains the learner's authentic AttemptRecord. It does not describe a corrupt snapshot as merely an older question version.

## Tests authored in the existing ContentImprovementRegressionTests file

The separate GranularHistorySnapshotRecoveryTests class contains:

- testOneMalformedHistorySnapshotRetainsValidContextAndOriginalPrivateBytes
- testProtectedMalformedMarkerOverridesInconsistentHistoryAndPortableResults
- testFutureGlobalVersionDuplicateIdentityAndMalformedSessionStayFailClosed
- testFailedRecoveryBackupPreservesSourceAndRefusesAllMutation
- testOversizedArchiveIsRejectedBeforeGranularDecodingOrBackup
- testLinkedHistoryDeletionPurgesUnclassifiableRecoveryBackups

These use actual bounded files, repository load/reload/mutation, a memory AppStore, history projection and actual four-file portable export. All six passed in `/tmp/neuroforge-coordinated-recovery-unit-tests.log`; the enclosing run executed 784 tests with 16 failures outside this suite. This suite result is not an all-project pass. No new production source file, SwiftData model or project regeneration was required.

## Explicit limits

This recovery is limited to independent local attempted-history snapshots. A portable archive whose typed top-level decode is already malformed still follows the strict import rejection path; an exported recovered marker is a supported safe reference. Sessions/ledgers with corruption remain unavailable rather than becoming lossy reconstructed authority. The private recovery files are retained locally; a separate user-facing recovery-file export workflow for unclassifiable protected/private originals is not implemented. General corrupt image recovery and off-main-thread decode/rendering remain separately tracked work. A bounded scratchpad byte/geometry follow-up is now authored in Scratchpad_Recovery_Status.md, after this suite passed.

The inconsistent-record canary regression now also removes the original local diagnostic marker/snapshot, imports only the withheld protected conflict identity, and verifies that history plus actual reexports remain protected. The first integrated build attempt ended in the unrelated AIStudio Swift IRGen compiler crash before any tests ran; the subsequent completed integrated run passed all six granular tests, including this marker-only case.

## Latest verification update

The subsequent root-owned `/tmp/neuroforge-final-recovery-unit-tests.log` run completed at 01:49:57 on 5 September 2026 with **784 tests, zero failures**. It includes the corrected generated Next write-obstruction fixture and all content, historical, golden, shared lifecycle and granular protection tests described here. This supersedes the earlier 784/16 result above. The later scratchpad byte/geometry recovery changes are authored after that green run and await their own integrated execution; see [Scratchpad_Recovery_Status.md](Scratchpad_Recovery_Status.md). The successful Mac run is not certification of all editorial, physical-device, installed UI or performance release gates.

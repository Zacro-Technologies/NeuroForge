# Synthetic golden fixture package v1

This package implements the reproducible fixture portion of QA-REQ-007. It contains no real learner data, source material, account identifiers, or exported user store. The JSON files are generated from the declared archive schema. They are **synthetic compatibility fixtures**, not files claimed to have been exported by historical shipped builds, signed content, or frozen binary SwiftData/CloudKit stores.

The committed package is in `Tests/Fixtures/ImprovementGolden_v1/`. Its `manifest.json` lists each file's byte count, SHA-256 digest, expected record counts, accepted/rejected status, invariants, and limits. The fixed synthetic timestamp is `2026-09-04T12:00:00Z`; the seed is `347811`; UUIDs come from explicit category/ordinal strings in the generator. Hashes provide reproducibility evidence, not an external signature or editorial approval.

## Reproduction

From the repository root:

```sh
python3 Tests/Fixtures/ImprovementGolden_v1/regenerate.py --check
python3 Tests/Fixtures/ImprovementGolden_v1/regenerate.py
python3 Tests/Fixtures/ImprovementGolden_v1/regenerate.py --output-dir /tmp/neuroforge-golden-review --large-count 10000
python3 Tests/Fixtures/ImprovementGolden_v1/regenerate.py --output-dir /tmp/neuroforge-golden-review --large-count 10000 --check
```

The generator uses only Python's standard library, never opens an app store or user document, and never accesses the network. It refuses to expand the large history into the committed fixture directory. Small artifacts and the manifest are sorted, stable UTF-8 JSON; the intentionally malformed file is stable truncated JSON. Running `--check` performs a byte-for-byte comparison without rewriting files.

## Coverage

| Fixture | Records | Invariant and limit |
|---|---:|---|
| `fresh-v18.json` | One synthetic profile, no attempts | Fresh learner history has no invented previous work. Profile values exercise the actual declared schema and semantic decoder. |
| `legacy-v14.json` … `legacy-v18.json` | Three fixed attempts each | Numeric committed history, disputed science, external self-check. Earlier versions omit fields introduced later: v14 reflection collection and pre-v16 adaptive history. The production migration, identity decoder and restore service must agree on identities, counts, exact original response strings, keys, correctness and credits. These are synthetic schema variants, not evidence that every old binary store migrates. |
| `disputed-science-v18.json` | One legacy science attempt | The family and edition are known but its original table is unavailable. The correct historical disposition is precautionary `unverifiable-interval`, with original answer/grade retained. No geometry or counterfactual answer is invented. Exact disjoint/touching/overlap geometry has separate independent policy fixtures in `HistoricalContentCorrectionPolicyTests`. |
| `external-self-check-v18.json` | One external self-check | Retains exact JSON spacing, a newline escape, Japanese recall text, the authentic matched rating, original false objective authority, and source identifiers for deleted synthetic material. Effective authority is personal study. No missing source passage is recreated. |
| `source-duplicates-deleted-reference-v18.json` | Two documents, two chunks, one historical answer | Distinct document/chunk IDs with identical content hashes remain distinct. A historical answer may retain its authentic deleted source references; no new active generated set relies on those absent sources. Original file formatting is not claimed. |
| `invalid-source-reference-v18.json` | A deliberately dangling chunk | The identity-only decoder is insufficient to establish validity. Semantic preview/restore must reject the missing document reference without mutating an existing destination. |
| `invalid-duplicate-attempt-v18.json` | Repeated attempt identity | Identity decoder and restore reject duplicate attempt IDs. |
| `malformed-truncated.json` and `future-v99.json` | Invalid structure / unsupported version | The decoder rejects each, and restore leaves an existing synthetic sentinel untouched. |
| `history-10000.recipe.json` | On-demand 10,000-row archive | The generator creates stable, unique attempt and session UUIDs and fixed raw payloads. The actual decoder, preview and restore assert 10,000 records and exact response preservation. This is a history-scale correctness fixture, not a question-variety, performance percentile, or learning-effect claim. |
| `runtime-phases.recipe.json` | Four runtime capture recipes | Actual public runtime operations create item, feedback, self-check-comparison, and interrupted timed-item checkpoints. These are exported and restored through production interfaces, comparing exact captured phase, question, digest, response, notes, duration and committed identity. |

The runtime recipes fix owner/session IDs, seed, and monotonic clock progression. Production-owned slot/attempt UUIDs and wall-clock capture timestamps are intentionally left authentic. They are compared against the same captured record after restoration, never replaced with fabricated fixed identities. Consequently these test-generated runtime archives are not claimed to be byte-identical to a historical saved store and are not committed as such.

## Actual interfaces and isolation

`GoldenArchiveFixtureTests` lives in the existing `Tests/DataExportRoundTripTests.swift` file. It calls `NFDataExportRoundTripValidator.decodeArchive`, `NFDataArchiveRestoreService.preview/restore`, and, for runtime captures, `NFUniversalSessionRuntime` and `NFDataExportService.makeExports`.

Every restoring fixture injects an in-memory SwiftData container and local session repository, an in-memory rotation ledger, and temporary source/cache/adaptive-history roots. It asserts `AppStore.allowsSharedWidgetPublishing == false` and refuses to continue if that invariant is false. This closes the otherwise shared widget app-group side effect of the actual restore service. No manual environment flag is treated as isolation. No real user store is opened, inspected, modified, or copied by the fixture generator or fixture setup.

The generator/10,000-row test uses `/usr/bin/python3` only on macOS. Other tests use Foundation/SwiftData and the app's interfaces; their test bundle must have access to the checkout fixtures through the established `#filePath` repository-root pattern. Device installation and asset packaging are separate acceptance work.

## Tests and observed execution

The six methods are:

- `testGoldenCommittedPackageHashesAndActualDecoderCounts`
- `testGoldenFreshAndLegacyVersions14Through18RestoreExactOriginalPayloads`
- `testGoldenInvalidPayloadsCannotChangeAnExistingSyntheticStore`
- `testGoldenSourceDuplicatesAndDeletedHistoricalReferencesRemainDistinct`
- `testGoldenRegeneratorReproducesCommittedFilesAnd10000AttemptHistory`
- `testGoldenRuntimeCapturesPreserveThreePhasesAndInterruptedTiming`

Observed execution: the latest completed root-owned Mac run (`/tmp/neuroforge-coordinated-recovery-unit-tests.log`, 5 September 2026, suite completed 01:39:36) passed all six methods. This includes byte-identical regeneration, actual supported-version restore, invalid-payload nonmutation, actual 10,000-attempt restore, captured runtime-phase restoration, and duplicate/deleted source identity preservation. The earlier lowercase UUID substring failure is resolved by strict parsing of every reference, exact UUID count/set equality, and checks that deleted document/chunk references are neither recreated nor relinked; raw response preservation remains asserted. The enclosing run executed 784 tests with 16 failed assertions outside this suite and requires rerun. These results make no performance-percentile, manual-device or authentic prior-binary-store migration claim.

Remaining external acceptance includes actual prior binary stores, CloudKit/device ownership integration, hardware timing, VoiceOver speech, Pencil drawing interaction, source-format fidelity on representative imported originals, and any learning-effect evaluation. The complete editorial content/band/signature obligations remain separate and are not satisfied by these synthetic fixtures.

## Latest verification update

The subsequent root-owned `/tmp/neuroforge-final-recovery-unit-tests.log` run completed at 01:49:57 on 5 September 2026 with **784 tests, zero failures**. It includes the corrected generated Next write-obstruction fixture and all content, historical, golden, shared lifecycle and granular protection tests described here. This supersedes the earlier 784/16 result above. The later scratchpad byte/geometry recovery changes are authored after that green run and await their own integrated execution; see [Scratchpad_Recovery_Status.md](../Scratchpad_Recovery_Status.md). The successful Mac run is not certification of all editorial, physical-device, installed UI or performance release gates.

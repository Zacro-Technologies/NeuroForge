# Captured session writer commands — scratch handoff

Frozen patch: `writer-commands.patch` (1,944 lines, 10 existing files).
SHA-256: `97ee8e714fe6d4c202bfe9e3f06d9159e41cb4cf6e8c33d5b386058648abe973`.
No working-tree changes, builds, simulator actions, @Model columns, portable schema changes, or new catalog entries.

## Behavior

- `NFSessionWriterCommand` retains one opaque in-process repository/writer/session/generation capability. A runtime captures authority only on initial claim or explicit takeover. Nested synchronous lifecycle work retains its original token through callbacks, including A → B → A ownership changes.
- Actual ordinary/source/protected checkpoint storage now calls `saveSession(command:expectedRevision:)`. The runtime advances its own acknowledged envelope revision after successful local persistence or accepted adaptive Next/Replace; it no longer reads the latest archive revision and overwrites under it.
- Ordinary presentation acknowledgement, scored/skipped receipt writes, legacy checkpoint mirrors, reflection writes, and generated scored/unscored/conflict writes use mandatory session command gates. Validation after a receipt write prevents stale feedback publication without erasing that durable receipt.
- The shared coordinator rechecks authority after receipt lookup and after successful receipt storage, before acknowledging feedback. Ownership loss is not an answer conflict.
- Actual generated checkpoint storage uses captured authority plus its modern revision. Known legacy generated continuation keeps its existing run/pending-attempt identities and uses an exact predecessor-payload digest instead of inventing a new slot ledger. Restore checks the supplied draft against the current authentic retained payload before claiming/writing.
- Adaptive nonlaunch prepare requires a command, carries it in preparation, and revalidates it under the publication lock before idempotent replay or mutation. Initial `predecessor == nil` is still the separate synchronous launch protocol.
- Checked revision advancement refuses negative/exhausted counters without overflow, reset, truncation, or replacing the original archive. This covers ordinary construction/storage and generated construction/storage.

## Tests and validation

12 new tests are appended to existing ExactSessionContinuityTests and GeneratedLifecycleParityTests: runtime ABA, same-owner stale revision, actual prewrite token loss, receipt-write/ABA/retry with one immutable attempt, source self-check neutral evidence, protected minimal-receipt replay, matching-receipt callback ownership loss, generated durable receipt/cold replay, generated prewrite loss, legacy exact-payload/ABA, and ordinary/generated exhausted counters preserving saved bytes.

The patch **already includes** Adaptive's direct nonlaunch fixture changes from `/tmp/nf-session-writer-fixtures-20260905/writer-fixtures.patch` and `/tmp/nf-editorial-prelaunch-20260905/writer-fixture-followup.patch`. Do not apply them twice. It also adapts two low-level LocalReservationBridge fixtures with one explicitly registered writer/retained command. No fixture silently takes ownership or refreshes a token on retry. Existing schema, cursor, same-revision takeover, and immutable history assertions remain.

All 10 complete Swift files pass frontend parse; current-main `git apply --check` passes. Swift 6 strict typecheck passes for the complete actual ordinary and generated runtimes, the new storage wrappers, the shared coordinator, existing fixture classes, and all 12 new tests. `TypecheckTests.swift` uses only two compile-only AppStore adaptive-preparation signature declarations against the last built module; full repository adaptive implementation and fixture adaptations are parsed but await the parent build. Tests have **not** been executed by this agent.

`prepare.py` freshly reads main, preserves other owners' changes, copies into `base/` and `work/`, and emits the combined patch plus `base-sha256.txt`. `typecheck.py` explains the compile-only declarations. `storage.swift`, `ordinary-tests.swift`, and `generated-tests.swift` are readable component sources.

Adaptive independently reviewed nonlaunch validation-before-replay, under-lock acceptance, accepted revision publication, and nested ABA retention. The concrete overflow issue found in that review is fixed and has two adversarial tests. This was source review, not execution.

## Remaining architecture scope

Synchronous durable commit APIs remain synchronous in this package. Raw archival/import/maintenance and historical-annotation APIs remain separate from live session entry points. A new async transaction migration must carry immutable proposals, exact expected archive/run revision and digest, and writer generation through the same actual disk lock, then publish only an acknowledged result under the same generation. Cancellation after durable replacement must preserve its receipt for cold reconciliation.

New/fixed launch retains the existing synchronous launch protocol. Before making it asynchronous, capture and validate the predecessor writer boundary too; `predecessor == nil` must not become delayed authorization. This package does not claim that every delayed native editor closure has a captured generation, nor that every historical/admin caller has migrated to an actor API.


## Root execution update

Root execution: all 12 original writer tests pass in the 188/189 scope; the two additional checked-revision tests pass in the full 1,211-test run. The existing stale-window test exposed a real retained-run identity bug, fixed and passing in the 134-test follow-up. Exact manifests and failed overall results remain in Run_Manifest.json.

import Foundation
import SwiftData
import XCTest
@testable import NeuroForge

@MainActor
final class LocalReservationBridgeTests: XCTestCase {
    private func fixture(index: Int = 0) throws -> NFLocalSessionEnvelope {
        let container = try ModelContainer(for: Schema(NFSchemaV1.models), configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let store = AppStore(context: container.mainContext, localSessionRepository: NFLocalSessionRepository())
        let runtime = NFUniversalSessionRuntime(request: .init(lab: .mentalMath, source: .focused, seed: 347811,
            localeIdentifier: "en", requestedItemCount: 5, mechanicID: "mentalMath.mentalCalculation"))
        XCTAssertTrue(runtime.checkpointDraft(store: store))
        var envelope = try XCTUnwrap(store.localSessions.archive.sessions.first)
        envelope.checkpoint.index = index
        runtime.releaseWriter()
        return envelope
    }
    private func next(_ prior: NFLocalSessionEnvelope) throws -> NFLocalSessionEnvelope {
        var envelope = prior
        envelope.revision += 1; envelope.checkpoint.index += 1
        envelope.checkpoint.slotID = UUID(); envelope.checkpoint.attemptID = UUID()
        envelope.checkpoint.exercise = NFDeterministicSessionExerciseFactory.makeExercise(request: envelope.request,
            index: envelope.index, assessmentDescriptor: nil,
            excludingContentFingerprints: [NFQuestionFingerprint.fingerprint(for: try XCTUnwrap(prior.checkpoint.exercise))])
        envelope.checkpoint.exerciseDigest = try NFLocalItemCheckpoint.digest(XCTUnwrap(envelope.checkpoint.exercise))
        envelope.checkpoint.committedAttemptID = nil; envelope.checkpoint.pendingOutcome = nil
        envelope.checkpoint.phase = .item; envelope.checkpoint.solutionRevealed = false
        return envelope
    }
    func testInitialSaveReservesExactIDsWithoutExposureAndVisibleCallbackIsIdempotent() throws {
        let envelope = try fixture()
        let accepted = try NFLocalReservationBridge.accepting(envelope: envelope, ledger: .init())
        let slot = try XCTUnwrap(accepted.slots[envelope.checkpoint.slotID.uuidString])
        XCTAssertEqual(slot.attemptID, envelope.checkpoint.attemptID.uuidString)
        XCTAssertEqual(slot.snapshotDigest, envelope.checkpoint.exerciseDigest)
        XCTAssertEqual(accepted.runs[envelope.id.uuidString]?.scope.positionRecipeID, "snapshot-slot.v1")
        XCTAssertEqual(accepted.runs[envelope.id.uuidString]?.versions.presentationVersion, NFSessionPresentationPolicy.version)
        XCTAssertNotEqual(accepted.runs[envelope.id.uuidString]?.versions.presentationVersion,
            String(try XCTUnwrap(envelope.checkpoint.exercise).schemaVersion))
        XCTAssertTrue(accepted.exposures.isEmpty); XCTAssertTrue(accepted.outcomes.isEmpty)
        XCTAssertEqual(try NFLocalReservationBridge.accepting(envelope: envelope, previous: envelope, ledger: accepted), accepted)
        let presented = try NFLocalReservationBridge.acknowledge(envelope: envelope, ledger: accepted, at: Date(timeIntervalSince1970: 100))
        let replay = try NFLocalReservationBridge.acknowledge(envelope: envelope, ledger: presented, at: Date(timeIntervalSince1970: 900))
        XCTAssertEqual(replay, presented); XCTAssertEqual(presented.exposures.count, 1)
        XCTAssertEqual(presented.exposures.values.first?.occurredAt, Date(timeIntervalSince1970: 100))
    }
    func testOldResumedQ3CapturesOnlyCurrentSlotWithoutFabricatingEarlierHistory() throws {
        let envelope = try fixture(index: 2)
        let accepted = try NFLocalReservationBridge.accepting(envelope: envelope, ledger: .init())
        let slot = try XCTUnwrap(accepted.slots.values.first)
        XCTAssertEqual(slot.plannedQuestionOrdinal, 2); XCTAssertEqual(slot.pathOrdinal, 0)
        XCTAssertEqual(accepted.slots.count, 1); XCTAssertEqual(accepted.snapshots.count, 1)
        XCTAssertTrue(accepted.exposures.isEmpty)
        XCTAssertNil(accepted.scopes.values.first?.legacyConsumption)
        XCTAssertEqual(accepted.scopes.values.first?.consumedPositions, [.init(epoch: 0, ordinal: 2)])
    }
    func testPresentationPinsHaveExplicitLegacyCompatibilityAndRejectUnknownFutureBeforeNext() throws {
        var envelope = try fixture()
        // Next follows an acknowledged outcome; version compatibility must not
        // bypass the reservation policy's independent sequencing requirement.
        envelope.checkpoint.phase = .feedback
        envelope.checkpoint.committedAttemptID = envelope.checkpoint.attemptID
        let initial = try NFLocalReservationBridge.accepting(envelope: envelope, ledger: .init())
        let encoded = String(decoding: try JSONEncoder().encode(initial), as: UTF8.self)
        let advanced = try next(envelope)
        for legacy in ["1", "2"] {
            let bytes = Data(encoded.replacingOccurrences(of: NFSessionPresentationPolicy.version, with: legacy).utf8)
            let retained = try JSONDecoder().decode(NFSelectionReservationLedger.self, from: bytes)
            let result = try NFLocalReservationBridge.accepting(envelope: advanced, previous: envelope, ledger: retained)
            XCTAssertEqual(result.runs[envelope.id.uuidString]?.versions.presentationVersion, legacy)
            XCTAssertEqual(result.slots.count, 2)
            for (id, decision) in retained.decisions { XCTAssertEqual(result.decisions[id], decision) }
        }
        let future = try JSONDecoder().decode(NFSelectionReservationLedger.self,
            from: Data(encoded.replacingOccurrences(of: NFSessionPresentationPolicy.version, with: "UniversalPresentationV999").utf8))
        XCTAssertThrowsError(try NFLocalReservationBridge.accepting(envelope: advanced, previous: envelope, ledger: future)) { error in
            guard case NFLocalSessionRepository.RepositoryError.unsupportedVersion = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        }
        XCTAssertEqual(future.slots.count, 1)
        XCTAssertEqual(future.runs[envelope.id.uuidString]?.versions.presentationVersion, "UniversalPresentationV999")
    }
    func testPreparedSkipDoesNotCommitUntilAdvanceAndRevealRetainsDistinctDisposition() throws {
        for pending in ["skip", "reveal"] {
            let envelope = try fixture()
            let initial = try NFLocalReservationBridge.accepting(envelope: envelope, ledger: .init())
            var prepared = envelope
            prepared.checkpoint.pendingOutcome = pending
            prepared.checkpoint.solutionRevealed = pending == "reveal"
            let pendingState = try NFLocalReservationBridge.accepting(envelope: prepared, previous: envelope, ledger: initial)
            XCTAssertTrue(pendingState.outcomes.isEmpty)
            let advanced = try next(prepared)
            let committed = try NFLocalReservationBridge.accepting(envelope: advanced, previous: prepared, ledger: pendingState)
            XCTAssertEqual(committed.slots[prepared.checkpoint.slotID.uuidString]?.status, pending == "reveal" ? .revealed : .skipped)
            XCTAssertEqual(committed.slots.count, 2); XCTAssertEqual(committed.outcomes.count, 1)
            XCTAssertTrue(committed.exposures.isEmpty, "A committed imported response cannot establish old exposure timing")
        }
    }
    func testFeedbackCommitsOnceAndNextPreservesOriginalSnapshot() throws {
        let envelope = try fixture()
        var state = try NFLocalReservationBridge.accepting(envelope: envelope, ledger: .init())
        var feedback = envelope
        feedback.checkpoint.phase = .feedback; feedback.checkpoint.committedAttemptID = feedback.checkpoint.attemptID
        state = try NFLocalReservationBridge.accepting(envelope: feedback, previous: envelope, ledger: state)
        XCTAssertEqual(state.outcomes.count, 1)
        XCTAssertEqual(try NFLocalReservationBridge.acknowledge(envelope: feedback, ledger: state, at: Date()), state)
        let advanced = try next(feedback)
        state = try NFLocalReservationBridge.accepting(envelope: advanced, previous: feedback, ledger: state)
        XCTAssertEqual(state.outcomes.count, 1); XCTAssertEqual(state.slots.count, 2)
        let slot = try XCTUnwrap(state.slots[envelope.checkpoint.slotID.uuidString])
        let snapshot = try XCTUnwrap(NFSelectionReservationPolicy.snapshot(for: slot, in: state))
        XCTAssertEqual(try JSONDecoder().decode(NFExercise.self, from: snapshot.payload), envelope.checkpoint.exercise)
    }
    func testTamperedSnapshotOrForeignOwnerCannotRewriteDecision() throws {
        let envelope = try fixture()
        let state = try NFLocalReservationBridge.accepting(envelope: envelope, ledger: .init())
        var tampered = envelope; tampered.checkpoint.exerciseDigest = "not-the-acknowledged-bytes"
        XCTAssertThrowsError(try NFLocalReservationBridge.accepting(envelope: tampered, previous: envelope, ledger: state))
        let foreign = NFLocalSessionEnvelope(id: envelope.id, ownerDeviceID: UUID(), revision: 2, request: envelope.request,
            checkpoint: envelope.checkpoint, status: envelope.status, updatedAt: Date())
        XCTAssertThrowsError(try NFLocalReservationBridge.accepting(envelope: foreign, previous: envelope, ledger: state))
        XCTAssertEqual(state.slots.count, 1); XCTAssertTrue(state.outcomes.isEmpty)
    }
    func testPersonalAndProtectedSnapshotsNeverEnterOrdinaryLedger() throws {
        var personal = try fixture()
        personal.request = .init(lab: .mentalMath, source: .focused, seed: 1, evidenceClass: .documentPractice, requestedItemCount: 5)
        XCTAssertEqual(try NFLocalReservationBridge.accepting(envelope: personal, ledger: .init()), .init())
        var protected = personal
        protected.request = .init(lab: .mentalMath, source: .baseline, seed: 1, evidenceClass: .assessmentHoldout,
            requestedItemCount: 5, assessmentBlock: .numericalFluency)
        protected.checkpoint.exercise = nil
        XCTAssertEqual(try NFLocalReservationBridge.accepting(envelope: protected, ledger: .init()), .init())
    }
    func testAdaptiveNextCannotAppendCurrentContractUnderDifferentGeneratorOrScorerPins() throws {
        let source = NFMemoryOfflineQuestionRotationStateStore()
        let rotation = NFOfflineQuestionRotation(store: source), repository = NFLocalSessionRepository()
        var request = SessionRequest(lab: .mentalMath, source: .focused, seed: 863,
            localeIdentifier: "en", requestedItemCount: 2)
        request.localSessionID = request.id
        request.ordinaryDelivery = .init(strategy: .adaptiveItem, profileID: UUID(), bank: NFOfflineQuestionBank.rotationBank)
        let first = try repository.prepareAdaptiveItem(request: request, predecessor: nil, rotation: rotation,
            bank: NFOfflineQuestionBank.rotationBank, quarantinedItemIDs: [], at: Date())
        var feedback = try repository.acceptAdaptiveItem(first, checkpoint: first.checkpoint, rotation: rotation, quarantinedItemIDs: [])
        feedback.checkpoint.phase = .feedback
        feedback.checkpoint.committedAttemptID = feedback.checkpoint.attemptID
        try repository.save(feedback)
        let writer = UUID()
        XCTAssertTrue(repository.claimWriter(writer, sessionID: request.id, checkpoint: { true }))
        defer { repository.releaseWriter(writer) }
        let command = try repository.sessionCommand(authority: repository.writerAuthority(for: writer, sessionID: request.id), sessionID: request.id)
        let candidate = try repository.prepareAdaptiveItem(request: request, predecessor: feedback.checkpoint,
            rotation: rotation, bank: NFOfflineQuestionBank.rotationBank, quarantinedItemIDs: [], at: Date(), command: command)
        let next = NFLocalSessionEnvelope(id: request.id, ownerDeviceID: repository.ownerDeviceID,
            revision: feedback.revision + 1, request: request, checkpoint: candidate.checkpoint,
            status: .suspended, updatedAt: candidate.checkpoint.shownAt)
        let original = try XCTUnwrap(repository.archive.selectionLedger)
        var alteredBody = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(candidate.checkpoint.exercise)) as? [String: Any])
        alteredBody["prompt"] = "Different contract under the same materialized seed"
        let alteredExercise = try JSONDecoder().decode(NFExercise.self, from: JSONSerialization.data(withJSONObject: alteredBody))
        var alteredNext = next
        alteredNext.checkpoint.exercise = alteredExercise
        alteredNext.checkpoint.exerciseDigest = try NFLocalItemCheckpoint.digest(alteredExercise)
        var receiptBody = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(candidate.receipt)) as? [String: Any])
        receiptBody["exerciseDigest"] = alteredNext.checkpoint.exerciseDigest
        let alteredReceipt = try JSONDecoder().decode(NFLocalAdaptiveItemReceipt.self, from: JSONSerialization.data(withJSONObject: receiptBody))
        XCTAssertEqual(alteredExercise.seed, candidate.checkpoint.exercise?.seed)
        XCTAssertThrowsError(try NFLocalReservationBridge.accepting(envelope: alteredNext, previous: feedback,
            ledger: original, adaptiveReceipt: alteredReceipt), "The pure bridge must authenticate more than the materialized seed")
        XCTAssertEqual(try NFLocalReservationBridge.accepting(envelope: next, previous: feedback,
            ledger: original, adaptiveReceipt: candidate.receipt).slots.count, 2)
        for key in ["generatorVersion", "scorerVersion"] {
            var body = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(original)) as? [String: Any])
            var runs = try XCTUnwrap(body["runs"] as? [String: Any])
            var run = try XCTUnwrap(runs[request.id.uuidString] as? [String: Any])
            var pins = try XCTUnwrap(run["versions"] as? [String: Any])
            pins[key] = "999"
            run["versions"] = pins; runs[request.id.uuidString] = run; body["runs"] = runs
            let unsupported = try JSONDecoder().decode(NFSelectionReservationLedger.self,
                from: JSONSerialization.data(withJSONObject: body))
            XCTAssertThrowsError(try NFLocalReservationBridge.accepting(envelope: next, previous: feedback,
                ledger: unsupported, adaptiveReceipt: candidate.receipt)) { error in
                guard case NFLocalSessionRepository.RepositoryError.unsupportedVersion = error else {
                    return XCTFail("Expected a version boundary, received \(error)")
                }
            }
            XCTAssertEqual(unsupported.slots, original.slots)
            XCTAssertEqual(unsupported.snapshots, original.snapshots)
        }
        XCTAssertEqual(repository.archive.selectionLedger, original)
        XCTAssertEqual(repository.archive.offlineRotationLedger?.scopes.values.first?.cursor, 1)
    }

    func testAdaptiveReplacementAuthenticatesOriginalDraftAndCannotReplaceCommittedAnswer() throws {
        let repository = NFLocalSessionRepository()
        let rotation = NFOfflineQuestionRotation(store: NFMemoryOfflineQuestionRotationStateStore())
        var request = SessionRequest(lab: .mentalMath, source: .focused, seed: 887,
            localeIdentifier: "en", requestedItemCount: 2)
        request.localSessionID = request.id
        request.ordinaryDelivery = .init(strategy: .adaptiveItem, profileID: UUID(), bank: NFOfflineQuestionBank.rotationBank)
        let launch = try repository.prepareAdaptiveItem(request: request, predecessor: nil, rotation: rotation,
            bank: NFOfflineQuestionBank.rotationBank, quarantinedItemIDs: [], at: Date())
        let previous = try repository.acceptAdaptiveItem(launch, checkpoint: launch.checkpoint, rotation: rotation, quarantinedItemIDs: [])
        let writer = UUID()
        XCTAssertTrue(repository.claimWriter(writer, sessionID: request.id, checkpoint: { true }))
        defer { repository.releaseWriter(writer) }
        let command = try repository.sessionCommand(authority: repository.writerAuthority(for: writer, sessionID: request.id), sessionID: request.id)
        let replacement = try repository.prepareAdaptiveReplacement(request: request, predecessor: previous.checkpoint,
            rotation: rotation, bank: NFOfflineQuestionBank.rotationBank, quarantinedItemIDs: [], at: Date(), command: command)
        let original = try XCTUnwrap(repository.archive.selectionLedger)
        let next = NFLocalSessionEnvelope(id: request.id, ownerDeviceID: repository.ownerDeviceID,
            revision: previous.revision + 1, request: request, checkpoint: replacement.checkpoint,
            status: .suspended, updatedAt: replacement.checkpoint.shownAt)
        var changedDraft = previous
        changedDraft.checkpoint.scratchpad = "Different predecessor under the same IDs"
        XCTAssertThrowsError(try NFLocalReservationBridge.accepting(envelope: next, previous: changedDraft,
            ledger: original, adaptiveReceipt: replacement.receipt))
        var committed = previous
        committed.checkpoint.phase = .feedback; committed.checkpoint.committedAttemptID = committed.checkpoint.attemptID
        XCTAssertThrowsError(try NFLocalReservationBridge.accepting(envelope: next, previous: committed,
            ledger: original, adaptiveReceipt: replacement.receipt))
        let accepted = try NFLocalReservationBridge.accepting(envelope: next, previous: previous,
            ledger: original, adaptiveReceipt: replacement.receipt)
        XCTAssertEqual(accepted.slots[previous.checkpoint.slotID.uuidString]?.status, .replaced)
        XCTAssertEqual(accepted.slots[next.checkpoint.slotID.uuidString]?.replacesSlotID, previous.checkpoint.slotID.uuidString)
        XCTAssertEqual(accepted.slots[next.checkpoint.slotID.uuidString]?.plannedQuestionOrdinal, 0)
        XCTAssertEqual(accepted.runs[request.id.uuidString]?.nextDecisionOrdinal, 2)
        XCTAssertTrue(accepted.outcomes.isEmpty, "Replacement is not an answered/skipped attempt")
        XCTAssertEqual(original.slots[previous.checkpoint.slotID.uuidString]?.status, .reserved)
        XCTAssertEqual(repository.archive.selectionLedger, original)
    }

}

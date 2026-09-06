import Foundation
import XCTest
@testable import NeuroForge

final class SelectionReservationLedgerTests: XCTestCase {
    private let scope = NFReservationScope(profileID: "p", labID: "math", contentEditionID: "edition1", laneID: "ordinary", privacyScopeID: "builtin", positionRecipeID: "epoch-permutation.v1")
    private let versions = NFReservationVersionPin(catalogFingerprint: "bank1", generatorVersion: "1", selectionPolicyVersion: NFSelectionReservationPolicy.policyVersion, presentationVersion: "1", scorerVersion: "1")
    private func initial() throws -> NFSelectionReservationLedger {
        try NFSelectionReservationPolicy.registerFreshScope(scope, catalogFingerprint: "bank1", verifiedEmptySourceID: "verified-no-old-scope", in: .init())
    }
    private func candidate(_ ordinal: Int, semantic: String? = nil, eligible: Bool = true, protected: Bool = false) -> NFReservationCandidate {
        let payload = Data("verified snapshot \(ordinal)".utf8)
        return .init(candidateID: "candidate\(ordinal)", semanticID: semantic ?? "semantic\(ordinal)", position: .init(epoch: 0, ordinal: ordinal),
            snapshot: .init(id: "snapshot\(ordinal)", digest: NFReservationSnapshot.digest(payload), payload: payload, evaluationContractID: "eval1", evaluationContractDigest: NFReservationSnapshot.digest(payload)),
            rank: [ordinal], tieKey: UInt64(ordinal), selectionReason: "eligible deterministic rank", eligibilityRevision: "1", eligible: eligible, protectedContent: protected)
    }
    private func command(runID: String = "run", ordinal: UInt64 = 0, operation: NFReservationOperation = .launch,
                         predecessor: String? = nil, fixed: [NFReservationPosition] = []) -> NFReservationCommand {
        .init(decisionID: NFSelectionReservationPolicy.decisionID(runID: runID, ordinal: ordinal), runID: runID,
            ownerDeviceID: "device", scope: scope, versions: versions, configurationDigest: "config1",
            strategy: fixed.isEmpty ? .adaptiveItem : .fixedBlock, operation: operation,
            decisionOrdinal: ordinal, intendedPathOrdinal: Int(ordinal), plannedQuestionOrdinal: Int(ordinal),
            predecessorSlotID: predecessor, fixedPlannedPositions: fixed)
    }
    private func accept(_ command: NFReservationCommand, _ candidates: [NFReservationCandidate], _ state: NFSelectionReservationLedger) throws -> NFSelectionReservationLedger {
        try NFSelectionReservationPolicy.prepareAcceptance(command: command, candidates: candidates, state: state, expectedRevision: state.revision).state
    }
    private func presented(_ state: NFSelectionReservationLedger, slot: NFReservationSlot) throws -> NFSelectionReservationLedger {
        try NFSelectionReservationPolicy.acknowledgePresentation(eventID: "exposure." + slot.id, runID: slot.runID, slotID: slot.id, ownerDeviceID: "device", presentationOrdinal: 0, occurredAt: Date(timeIntervalSince1970: 100), in: state)
    }

    func testProbesDoNotConsumeAndAdaptiveAcceptanceConsumesOnlySelectedPosition() throws {
        let initial = try initial()
        XCTAssertEqual(NFSelectionReservationPolicy.advisoryPrewarm([candidate(0), candidate(1), candidate(2)]).count, 2)
        XCTAssertTrue(initial.scopes[scope.key]!.consumedPositions.isEmpty)
        let result = try accept(command(), [candidate(0, eligible: false), candidate(1, protected: true), candidate(2)], initial)
        XCTAssertEqual(result.scopes[scope.key]?.consumedPositions, [candidate(2).position])
        XCTAssertEqual(result.slots.count, 1)
        XCTAssertTrue(result.exposures.isEmpty)
        XCTAssertTrue(result.outcomes.isEmpty)
    }
    func testFixedBlockReservationIsAtomicAndRetainsExactPlannedOrder() throws {
        let initial = try initial()
        let launch = command(fixed: [candidate(2).position, candidate(0).position])
        XCTAssertThrowsError(try accept(launch, [candidate(0)], initial))
        XCTAssertTrue(initial.slots.isEmpty)
        let result = try accept(launch, [candidate(0), candidate(2)], initial)
        XCTAssertEqual(result.runs["run"]?.slotIDs.compactMap { result.slots[$0]?.candidateID }, ["candidate2", "candidate0"])
        XCTAssertEqual(result.scopes[scope.key]?.consumedPositions.count, 2)
        XCTAssertTrue(result.exposures.isEmpty)
    }
    func testAcceptedDecisionReplaysOriginalSnapshotDespiteChangedPoolAndStaleRead() throws {
        let launch = command(), initial = try initial()
        let result = try accept(launch, [candidate(0)], initial)
        let replay = try NFSelectionReservationPolicy.prepareAcceptance(command: launch, candidates: [], state: result, expectedRevision: initial.revision)
        XCTAssertTrue(replay.isReplay)
        XCTAssertEqual(replay.state, result)
        XCTAssertEqual(replay.slots.first?.snapshotDigest, candidate(0).snapshot.digest)
        XCTAssertNotNil(UUID(uuidString: try XCTUnwrap(replay.slots.first?.id)))
        XCTAssertNotNil(UUID(uuidString: try XCTUnwrap(replay.slots.first?.attemptID)))
    }
    func testConflictingDecisionAndStalePublicationRejectWithoutMutation() throws {
        let initial = try initial()
        let receipt = try NFSelectionReservationPolicy.prepareAcceptance(command: command(), candidates: [candidate(0)], state: initial, expectedRevision: initial.revision)
        let concurrent = try accept(command(runID: "other"), [candidate(1)], initial)
        XCTAssertThrowsError(try NFSelectionReservationPolicy.applying(receipt, to: concurrent))
        var conflicting = command(); conflicting.intendedSlotIDs = [UUID().uuidString]
        XCTAssertThrowsError(try accept(conflicting, [candidate(0)], receipt.state))
        XCTAssertEqual(concurrent.slots.count, 1)
    }
    func testExposureIsIdempotentAndNoLaterSlotCanAppearBeforePredecessorOutcome() throws {
        let launch = command(fixed: [candidate(0).position, candidate(1).position])
        var state = try accept(launch, [candidate(0), candidate(1)], initial())
        let slots = try XCTUnwrap(state.runs["run"]?.slotIDs).compactMap { state.slots[$0] }
        XCTAssertThrowsError(try presented(state, slot: slots[1]))
        state = try presented(state, slot: slots[0])
        let replay = try NFSelectionReservationPolicy.acknowledgePresentation(eventID: "exposure." + slots[0].id, runID: "run", slotID: slots[0].id,
            ownerDeviceID: "device", presentationOrdinal: 0, occurredAt: Date(timeIntervalSince1970: 999), in: state)
        XCTAssertEqual(replay, state)
        XCTAssertEqual(replay.exposures.values.first?.occurredAt, Date(timeIntervalSince1970: 100))
        XCTAssertEqual(replay.scopes[scope.key]?.consumedPositions.count, 2)
    }
    func testAbandonmentPreservesConsumedPositionsWithoutInventingExposureOrAnswer() throws {
        let reserved = try accept(command(), [candidate(0)], initial())
        let ended = try NFSelectionReservationPolicy.endRun("run", ownerDeviceID: "device", in: reserved)
        XCTAssertEqual(ended.slots.values.first?.status, .abandoned)
        XCTAssertEqual(ended.scopes[scope.key]?.consumedPositions, reserved.scopes[scope.key]?.consumedPositions)
        XCTAssertTrue(ended.exposures.isEmpty); XCTAssertTrue(ended.outcomes.isEmpty)
        XCTAssertEqual(try NFSelectionReservationPolicy.endRun("run", ownerDeviceID: "device", in: ended), ended)
    }
    func testExplicitReplacementKeepsLogicalQuestionAndConsumesOldAndNewPositions() throws {
        var state = try accept(command(), [candidate(0)], initial())
        let old = try XCTUnwrap(state.slots.values.first)
        var replacement = command(ordinal: 1, operation: .replace, predecessor: old.id)
        replacement = NFReservationCommand(decisionID: replacement.decisionID, runID: "run", ownerDeviceID: "device", scope: scope, versions: versions,
            configurationDigest: "config1", strategy: .adaptiveItem, operation: .replace, decisionOrdinal: 1, intendedPathOrdinal: 1,
            plannedQuestionOrdinal: 0, predecessorSlotID: old.id, fixedPlannedPositions: [])
        state = try accept(replacement, [candidate(1)], state)
        XCTAssertEqual(state.slots[old.id]?.status, .replaced)
        let new = try XCTUnwrap(state.slots.values.first { $0.id != old.id })
        XCTAssertEqual(new.plannedQuestionOrdinal, 0); XCTAssertEqual(new.pathOrdinal, 1)
        XCTAssertEqual(new.replacesSlotID, old.id)
        XCTAssertEqual(state.scopes[scope.key]?.consumedPositions.count, 2)
    }
    func testSemanticRepeatIsExcludedEvenAtUnconsumedPosition() throws {
        var state = try accept(command(), [candidate(0)], initial())
        let first = try XCTUnwrap(state.slots.values.first)
        state = try presented(state, slot: first)
        state = try NFSelectionReservationPolicy.recordOutcome(.init(eventID: "answer", runID: "run", slotID: first.id, status: .answered), ownerDeviceID: "device", in: state)
        let next = command(ordinal: 1, operation: .next, predecessor: first.id)
        XCTAssertThrowsError(try accept(next, [candidate(1, semantic: "semantic0")], state))
        let accepted = try accept(next, [candidate(1, semantic: "semantic0"), candidate(2)], state)
        XCTAssertEqual(accepted.slots.count, 2)
        XCTAssertEqual(accepted.runs["run"]?.semanticExclusions, ["semantic0", "semantic2"])
    }
    func testActualLegacyCursorSeedProtectsAllPriorEpochsAndCurrentPrefix() throws {
        let state = try NFSelectionReservationPolicy.seedLegacyScope(scope, catalogFingerprint: "bank1", sourcePositionRecipeID: scope.positionRecipeID,
            migrationID: "real-old-ledger", sourceDigest: "verified-source", epoch: 50, cursor: 3, bankQuestionCount: 1000, in: .init())
        let consumption = try XCTUnwrap(state.scopes[scope.key])
        XCTAssertTrue(consumption.contains(.init(epoch: 49, ordinal: 999)))
        XCTAssertTrue(consumption.contains(.init(epoch: 50, ordinal: 2)))
        XCTAssertFalse(consumption.contains(.init(epoch: 50, ordinal: 3)))
        XCTAssertFalse(consumption.contains(.init(epoch: 51, ordinal: 0)))
        XCTAssertTrue(consumption.consumedPositions.isEmpty, "Compact migration must not allocate 50,003 records")
        XCTAssertThrowsError(try NFSelectionReservationPolicy.registerFreshScope(scope, catalogFingerprint: "bank1", verifiedEmptySourceID: "assume-empty", in: state))
        XCTAssertThrowsError(try NFSelectionReservationPolicy.seedLegacyScope(scope, catalogFingerprint: "bank1", sourcePositionRecipeID: "catalog-ordinal-is-not-epoch", migrationID: "bad", sourceDigest: "x", epoch: 0, cursor: 0, bankQuestionCount: 1000, in: .init()))
    }
    func testUnseededLegacyScopeCannotBeMistakenForFreshAndWrongOwnerCannotPresent() throws {
        XCTAssertThrowsError(try accept(command(), [candidate(0)], .init()))
        let state = try accept(command(), [candidate(0)], initial())
        let first = try XCTUnwrap(state.slots.values.first)
        XCTAssertThrowsError(try NFSelectionReservationPolicy.acknowledgePresentation(eventID: "x", runID: "run", slotID: first.id, ownerDeviceID: "foreign", presentationOrdinal: 0, occurredAt: Date(), in: state))
    }
    func testAcknowledgedLegacyAnswerDoesNotInventPresentationAndRoundTripsExactly() throws {
        let state = try accept(command(), [candidate(0)], initial())
        let slot = try XCTUnwrap(state.slots.values.first)
        let outcome = NFReservationOutcome(eventID: "answer", runID: "run", slotID: slot.id, status: .answered)
        XCTAssertThrowsError(try NFSelectionReservationPolicy.recordOutcome(outcome, ownerDeviceID: "device", in: state))
        let answered = try NFSelectionReservationPolicy.recordOutcome(outcome, ownerDeviceID: "device", acknowledgedAttemptID: slot.attemptID, in: state)
        XCTAssertTrue(answered.exposures.isEmpty)
        XCTAssertEqual(answered.slots[slot.id]?.status, .answered)
        XCTAssertEqual(try JSONDecoder().decode(NFSelectionReservationLedger.self, from: JSONEncoder().encode(answered)), answered)
    }
}

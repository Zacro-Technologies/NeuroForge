import Foundation
import SwiftData
import XCTest
@testable import NeuroForge

/// Adversarial review of the new local durability boundary. These are separate
/// from policy simulations: they use the actual runtime, repository and store.
@MainActor
final class SessionIntegrityReviewTests: XCTestCase {
    private func store(repository: NFLocalSessionRepository? = nil) throws -> (AppStore, ModelContainer) {
        let container = try ModelContainer(for: Schema(NFSchemaV1.models), configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        return (AppStore(context: container.mainContext, localSessionRepository: repository ?? NFLocalSessionRepository()), container)
    }
    private func request(personal: Bool = false) -> SessionRequest {
        .init(lab: .mentalMath, source: .focused, seed: 20260904, localeIdentifier: "en",
              preferredMentalMathKind: .multiplication, evidenceClass: personal ? .documentPractice : .practice,
              requestedItemCount: 3, isTimed: false, mechanicID: "mentalMath.mentalCalculation")
    }

    func testFutureNestedExerciseCannotReplaceOrGradeAnAcknowledgedDraft() throws {
        let (source, container) = try store(); defer { _ = container }
        let first = NFUniversalSessionRuntime(request: request())
        first.numericValue = "17"
        XCTAssertTrue(first.checkpointDraft(store: source))
        let original = try XCTUnwrap(source.localSessions.archive.sessions.first)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let originalBytes = try encoder.encode(original)
        var saved = original
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(first.exercise)) as? [String: Any])
        object["schemaVersion"] = 999
        let future = try JSONDecoder().decode(NFExercise.self, from: JSONSerialization.data(withJSONObject: object))
        saved.checkpoint.exercise = future
        saved.checkpoint.exerciseDigest = try NFLocalItemCheckpoint.digest(future)
        XCTAssertThrowsError(try source.localSessions.save(saved))
        XCTAssertEqual(try encoder.encode(XCTUnwrap(source.localSessions.archive.sessions.first)), originalBytes)
        first.releaseWriter()
        var launch = saved.request
        launch.localSessionID = saved.id
        launch.localCheckpoint = saved.checkpoint
        let restored = NFUniversalSessionRuntime(request: launch)
        XCTAssertNotNil(restored.unavailableReason)
        XCTAssertFalse(restored.canEditDraft)
        XCTAssertFalse(restored.checkpointDraft(store: source))
        restored.submitInline(store: source)
        XCTAssertTrue(source.attempts.isEmpty)
        XCTAssertEqual(source.localSessions.archive.sessions.first?.checkpoint.exercise, original.checkpoint.exercise)
        XCTAssertEqual(source.localSessions.archive.sessions.first?.checkpoint.response, original.checkpoint.response)
        XCTAssertEqual(source.localSessions.archive.sessions.first?.checkpoint.exerciseDigest, original.checkpoint.exerciseDigest)
        XCTAssertEqual(try encoder.encode(XCTUnwrap(source.localSessions.archive.sessions.first)), originalBytes)
    }

    func testTamperedImportedSnapshotRejectsWholeArchiveWithoutPartialMutation() throws {
        let (source, sourceContainer) = try store(); defer { _ = sourceContainer }
        let runtime = NFUniversalSessionRuntime(request: request())
        runtime.numericValue = "authentic draft"
        XCTAssertTrue(runtime.checkpointDraft(store: source))
        var exported = source.localSessions.exportArchive
        exported.sessions[0].checkpoint.exerciseDigest = "tampered"
        let destination = NFLocalSessionRepository()
        XCTAssertThrowsError(try destination.importArchive(exported))
        XCTAssertTrue(destination.archive.sessions.isEmpty)
        XCTAssertTrue(destination.archive.snapshots.isEmpty)
        XCTAssertEqual(source.localSessions.archive.sessions[0].checkpoint.response,
                       .numeric(NFNumericSubmission(value: "authentic draft", unit: nil)))
    }

    func testForeignImportRetainsOriginalOwnerAndCannotBecomeWritableByReexport() throws {
        let sourceOwner = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
        let destinationOwner = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
        let (source, container) = try store(repository: NFLocalSessionRepository(ownerDeviceID: sourceOwner)); defer { _ = container }
        let runtime = NFUniversalSessionRuntime(request: request())
        runtime.numericValue = "17"
        XCTAssertTrue(runtime.checkpointDraft(store: source))
        let destination = NFLocalSessionRepository(ownerDeviceID: destinationOwner)
        try destination.importArchive(source.localSessions.exportArchive)
        let recovered = try XCTUnwrap(destination.archive.sessions.first)
        XCTAssertEqual(recovered.ownerDeviceID, sourceOwner)
        XCTAssertEqual(recovered.status, .migrationRecovery)
        var unauthorized = recovered; unauthorized.status = .suspended
        XCTAssertThrowsError(try destination.save(unauthorized))
        let finalOwner = NFLocalSessionRepository(ownerDeviceID: destinationOwner)
        try finalOwner.importArchive(destination.exportArchive)
        XCTAssertEqual(finalOwner.archive.sessions.first?.status, .migrationRecovery)
        XCTAssertEqual(finalOwner.archive.sessions.first?.checkpoint.response, recovered.checkpoint.response)
    }

    func testConflictingImportedResponseDoesNotRewriteAcknowledgedDraft() throws {
        let repository = NFLocalSessionRepository()
        let (source, container) = try store(repository: repository); defer { _ = container }
        let runtime = NFUniversalSessionRuntime(request: request())
        runtime.numericValue = "17"
        XCTAssertTrue(runtime.checkpointDraft(store: source))
        var conflict = repository.exportArchive
        conflict.sessions[0].checkpoint.response = .numeric(NFNumericSubmission(value: "99", unit: nil))
        XCTAssertThrowsError(try repository.importArchive(conflict))
        XCTAssertEqual(repository.archive.sessions[0].checkpoint.response, .numeric(NFNumericSubmission(value: "17", unit: nil)))
    }

    func testProtectedExportRemovesNestedLegacyOutcomesAndReflectionSuggestions() throws {
        let (source, container) = try store(); defer { _ = container }
        let runtime = NFUniversalSessionRuntime(request: request())
        XCTAssertTrue(runtime.checkpointDraft(store: source))
        var run = try XCTUnwrap(source.localSessions.archive.sessions.first)
        run.checkpoint.exercise = nil // Protected snapshots are deliberately held outside the portable envelope.
        run.checkpoint.correctness = [false, true]
        run.checkpoint.credits = [0, 1]
        run.checkpoint.reflectionNote = "SECRET PROTECTED ERROR DIAGNOSIS"
        run.request = .init(lab: .mentalMath, source: .baseline, seed: 20260904,
            evidenceClass: .assessmentHoldout, assessmentBlock: .numericalFluency,
            resumedResults: [true], resumedCredits: [1], resumedResponsePayload: "SECRET NESTED OUTCOME",
            resumedReflectionNote: "SECRET NESTED REFLECTION")
        try source.localSessions.save(run)
        let exported = source.localSessions.exportArchive
        let protected = try XCTUnwrap(exported.sessions.first)
        XCTAssertTrue(protected.checkpoint.correctness.isEmpty)
        XCTAssertTrue(protected.checkpoint.credits.isEmpty)
        XCTAssertNil(protected.checkpoint.result)
        XCTAssertNil(protected.checkpoint.suggestedReflectionCode)
        XCTAssertTrue(protected.checkpoint.reflectionNote.isEmpty)
        XCTAssertTrue(protected.request.resumedResults.isEmpty)
        XCTAssertTrue(protected.request.resumedCredits.isEmpty)
        XCTAssertNil(protected.request.resumedResponsePayload)
        XCTAssertTrue(protected.request.resumedReflectionNote.isEmpty)
        let bytes = String(decoding: try JSONEncoder().encode(exported), as: UTF8.self)
        XCTAssertFalse(bytes.contains("SECRET"))
    }

    func testFailedFeedbackCheckpointCannotActivateNextQuestion() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "NFCommitTail-\(UUID())")
        defer { try? FileManager.default.removeItem(at: folder) }
        let repository = NFLocalSessionRepository(url: folder.appending(path: "sessions.json"))
        let (source, container) = try store(repository: repository); defer { _ = container }
        let runtime = NFUniversalSessionRuntime(request: request())
        XCTAssertTrue(runtime.checkpointDraft(store: source))
        runtime.numericValue = "0"; runtime.submitInline(store: source)
        XCTAssertEqual(runtime.stage, .feedback); XCTAssertEqual(source.attempts.count, 1)
        let frozen = runtime.exercise
        try FileManager.default.removeItem(at: folder)
        try Data("blocked write target".utf8).write(to: folder)
        runtime.next(store: source)
        XCTAssertEqual(runtime.index, 0)
        XCTAssertEqual(runtime.stage, .feedback)
        XCTAssertEqual(runtime.exercise, frozen)
        XCTAssertNotNil(runtime.saveError)
    }

    func testFiniteFocusedFamiliesRetainSavedFeedbackWithoutActivatingAnUnavailableQuestion() throws {
        for family in ["logic.conditions", "logic.proof-builder", "science.confound", "transfer.conditions"] {
            let (source, container) = try store(); defer { _ = container }
            let activity = try XCTUnwrap(NFDefaultContentCatalog.activity(id: "nf.default." + family))
            let runtime = NFUniversalSessionRuntime(request: .init(lab: activity.lab, source: .focused,
                seed: 20260904, localeIdentifier: "en", requestedItemCount: 5, isTimed: false,
                mechanicID: activity.mechanicID))
            XCTAssertNil(runtime.exercise.availabilityReason, family)
            XCTAssertTrue(runtime.checkpointDraft(store: source), family)
            switch runtime.exercise.interaction {
            case let .singleChoice(schema): runtime.singleChoiceID = schema.correctOptionID
            case let .multipleChoice(schema): runtime.multipleChoiceIDs = Set(schema.correctOptionIDs)
            case let .orderedSteps(schema): runtime.orderedStepIDs = schema.correctOrder
            default: XCTFail("Unexpected finite-family response contract: " + family); continue
            }
            runtime.submitInline(store: source)
            XCTAssertEqual(runtime.stage, .feedback, family)
            XCTAssertEqual(source.attempts.count, 1, family)
            let original = runtime.exercise
            let result = runtime.lastResult
            let responseBytes = source.attempts.first?.response
            let snapshotCount = source.localSessions.archive.selectionLedger?.snapshots.count
            runtime.next(store: source)
            XCTAssertEqual(runtime.index, 0, family)
            XCTAssertEqual(runtime.stage, .feedback, family)
            XCTAssertEqual(runtime.exercise, original, family)
            XCTAssertEqual(runtime.lastResult, result, family)
            XCTAssertNotNil(runtime.nextUnavailableReason, family)
            XCTAssertNil(runtime.unavailableReason, family)
            XCTAssertNil(runtime.saveError, family)
            XCTAssertEqual(source.attempts.first?.response, responseBytes, family)
            XCTAssertEqual(source.localSessions.archive.selectionLedger?.snapshots.count, snapshotCount, family)
            XCTAssertEqual(source.localSessions.archive.sessions.first?.checkpoint.phase, .feedback, family)
            runtime.next(store: source)
            XCTAssertEqual(source.attempts.count, 1, family)
            runtime.endSession(store: source)
            XCTAssertEqual(runtime.stage, .summary, family)
            XCTAssertTrue(runtime.endedEarly, family)
            XCTAssertEqual(runtime.presentedCount, 1, family)
        }
    }

    func testSharedLifecycleRetriesTheFrozenIntentOnlyAfterPreparedSnapshotSaves() throws {
        let exercise = NFUniversalSessionRuntime(request: request()).exercise
        let lifecycle = NFSessionLifecycleCoordinator()
        var allowPrepared = false
        var saved: [NFSessionLifecycleCoordinator.CommitIntent] = []
        var events: [String] = []
        func submit(_ response: NFExerciseResponse) {
            lifecycle.commit(exercise: exercise, response: response, attemptID: nil, confidence: .certain,
                recoveredIntent: nil, canMutate: { true }, receipt: { _ in .absent }, allowsNewCommit: { true },
                publishPrepared: { _ in events.append("freeze") },
                persistPrepared: { events.append("prepare"); return allowPrepared },
                saveAttempt: { saved.append($0); events.append("attempt") },
                acknowledge: { _ in events.append("feedback") }, persistFeedback: { events.append("ack"); return true },
                nonScorable: { _ in XCTFail("Expected a valid numeric response") },
                conflictingReceipt: { _ in XCTFail("No conflicting receipt") }, failedSave: { XCTFail("No failed attempt write") })
        }
        let original = NFExerciseResponse.numeric(.init(value: "0", unit: nil))
        submit(original)
        let frozenID = try XCTUnwrap(lifecycle.preparedIntent?.attemptID)
        XCTAssertEqual(lifecycle.phase, .confidence)
        XCTAssertEqual(events, ["freeze", "prepare"])
        XCTAssertTrue(saved.isEmpty)
        allowPrepared = true
        submit(.numeric(.init(value: "999", unit: nil)))
        XCTAssertEqual(saved.count, 1)
        XCTAssertEqual(saved.first?.attemptID, frozenID)
        XCTAssertEqual(saved.first?.response, original)
        XCTAssertEqual(events, ["freeze", "prepare", "freeze", "prepare", "attempt", "feedback", "ack"])
        XCTAssertEqual(lifecycle.phase, .feedback)
    }

    func testSharedNextProposalWriteFailureCannotPublishOrChangePhase() {
        let lifecycle = NFSessionLifecycleCoordinator()
        lifecycle.phase = .feedback
        var events: [String] = []
        lifecycle.advance(canMutate: { true }, persistCurrent: { events.append("current"); return true },
            prepare: { () -> NFSessionLifecycleCoordinator.Advance<String> in events.append("prepare"); return .item("candidate") },
            persist: { _ in events.append("persist"); return false },
            publish: { _ in XCTFail("An unsaved candidate cannot be published") },
            unavailable: { _ in XCTFail("This is a write failure, not inventory shortage") },
            failedPreparation: { XCTFail("Preparation succeeded") })
        XCTAssertEqual(events, ["current", "prepare", "persist"])
        XCTAssertEqual(lifecycle.phase, .feedback)
    }

    func testSharedReferenceExposureRollsBackOnFailedDurableWrite() {
        let lifecycle = NFSessionLifecycleCoordinator()
        var exposed = false
        XCTAssertFalse(lifecycle.revealReference(canMutate: { true }, expose: { exposed = $0 }, persist: { false }))
        XCTAssertFalse(exposed)
        XCTAssertEqual(lifecycle.phase, .item)
        XCTAssertTrue(lifecycle.revealReference(canMutate: { true }, expose: { exposed = $0 }, persist: { true }))
        XCTAssertTrue(exposed)
        XCTAssertEqual(lifecycle.phase, .selfCheckComparison)
    }

    func testOrdinarySharedSelfCheckPreservesRevealedReferenceAndFrozenRating() throws {
        let (source, container) = try store(); defer { _ = container }
        let question = NFAuthoredQuestion(id: "synthetic.shared.ordinary-reference", lab: .quantitative,
            style: .shortAnswer, prompt: "Explain why two equal groups double one group.", context: "Synthetic comparison",
            choices: [], correctAnswer: "Two equal groups contain twice the quantity of one group.", acceptedAnswers: [],
            explanation: "Count equal groups.", hint: "Compare one and two groups.", decisiveStep: "Count groups.",
            difficulty: 0.3, citationChunkIDs: [], evidenceClass: .documentPractice)
        guard case .selfCheck = question.authoritativeExercise.interaction else { return XCTFail("Expected self-check authority") }
        var launch = SessionRequest(lab: .quantitative, source: .focused, seed: 20260904,
            localeIdentifier: "en", evidenceClass: .documentPractice, requestedItemCount: 1, isTimed: false)
        launch.localCheckpoint = try .initial(request: launch, exercise: question.authoritativeExercise,
            slotID: UUID(), attemptID: UUID(), at: Date(timeIntervalSince1970: 1_788_523_200))
        launch.freshlyAcceptedLaunch = true
        let runtime = NFUniversalSessionRuntime(request: launch)
        XCTAssertTrue(runtime.checkpointDraft(store: source))
        runtime.selfCheckReflection = "There are two equal groups, each containing the same number of units."
        runtime.submitInline(store: source)
        XCTAssertEqual(runtime.stage, .selfCheckComparison)
        XCTAssertTrue(runtime.selfCheckReferenceRevealed)
        runtime.selfCheckRating = .matched
        runtime.saveSelfCheck(store: source)
        XCTAssertEqual(runtime.stage, .feedback)
        XCTAssertEqual(runtime.lastResult?.outcome, .selfReported)
        XCTAssertTrue(runtime.selfCheckReferenceRevealed)
        XCTAssertEqual(runtime.selfCheckRating, .matched)
        XCTAssertTrue(runtime.correctness.isEmpty)
        XCTAssertTrue(runtime.credits.isEmpty)
        let saved = try XCTUnwrap(source.localSessions.archive.sessions.first?.checkpoint)
        XCTAssertTrue(saved.referenceRevealed)
        XCTAssertEqual(saved.selfCheckRating, .matched)
        XCTAssertEqual(saved.response, .selfCheck(.init(rating: .matched, reflection: runtime.selfCheckReflection)))
        XCTAssertEqual(source.attempts.count, 1)
        XCTAssertEqual(NFResponsePresentation.decode(try XCTUnwrap(source.attempts.first?.response)), saved.response)
    }

    func testMalformedOrdinaryTypedCheckpointCannotReachATrappingRestore() throws {
        let (source, container) = try store(); defer { _ = container }
        let runtime = NFUniversalSessionRuntime(request: request())
        XCTAssertTrue(runtime.checkpointDraft(store: source))
        let original = try XCTUnwrap(source.localSessions.archive.sessions.first)
        var corrupted = original.checkpoint
        corrupted.response = .claimEvidence(.init(pairs: [
            .init(claimID: "duplicate", evidenceIDs: []), .init(claimID: "duplicate", evidenceIDs: [])
        ]))
        var launch = original.request
        launch.localSessionID = original.id
        launch.localCheckpoint = corrupted
        let recovered = NFUniversalSessionRuntime(request: launch)
        XCTAssertNotNil(recovered.unavailableReason)
        XCTAssertFalse(recovered.canSubmit)
        XCTAssertFalse(recovered.checkpointDraft(store: source))
        XCTAssertEqual(source.localSessions.archive.sessions.first?.checkpoint.response, original.checkpoint.response)
        XCTAssertTrue(source.attempts.isEmpty)
    }

    func testOrdinaryNextPublishesExactlyTheDurableNextSnapshot() throws {
        let (source, container) = try store(); defer { _ = container }
        let runtime = NFUniversalSessionRuntime(request: request())
        XCTAssertTrue(runtime.checkpointDraft(store: source))
        runtime.numericValue = "0"
        runtime.submitInline(store: source)
        XCTAssertEqual(runtime.stage, .feedback)
        let first = runtime.exercise
        runtime.next(store: source)
        XCTAssertEqual(runtime.stage, .item)
        XCTAssertEqual(runtime.index, 1)
        XCTAssertNil(runtime.saveError)
        let saved = try XCTUnwrap(source.localSessions.archive.sessions.first)
        XCTAssertEqual(saved.checkpoint.exercise, runtime.exercise)
        XCTAssertEqual(saved.checkpoint.phase, .item)
        XCTAssertEqual(saved.checkpoint.index, 1)
        XCTAssertNotEqual(saved.checkpoint.exercise, first)
        XCTAssertEqual(saved.checkpoint.response, .initialDraft(for: runtime.exercise))
        runtime.releaseWriter()
        var launch = saved.request
        launch.localSessionID = saved.id
        launch.localCheckpoint = saved.checkpoint
        let resumed = NFUniversalSessionRuntime(request: launch)
        XCTAssertEqual(resumed.exercise, runtime.exercise)
        XCTAssertEqual(resumed.index, 1)
        XCTAssertEqual(resumed.stage, .item)
        XCTAssertEqual(resumed.correctness, runtime.correctness)
    }

    func testSkipAndRevealKeepOneReservationOutcomeForFreshAndFinalSlots() throws {
        for count in [1, 3] {
            for revealed in [false, true] {
                let (source, container) = try store(); defer { _ = container }
                var now: TimeInterval = 100
                let launch = SessionRequest(lab: .mentalMath, source: .focused, seed: 20260904,
                    localeIdentifier: "en", preferredMentalMathKind: .multiplication,
                    requestedItemCount: count, isTimed: false, mechanicID: "mentalMath.mentalCalculation")
                let runtime = NFUniversalSessionRuntime(request: launch, monotonicNow: { now })
                XCTAssertTrue(runtime.checkpointDraft(store: source))
                runtime.acknowledgePresented()
                now += 7
                if revealed { runtime.numericValue = "original draft"; runtime.revealSolution(store: source) }
                runtime.skip(store: source)
                XCTAssertEqual(source.attempts.count, 1)
                XCTAssertEqual(runtime.stage, count == 1 ? .summary : .item)
                XCTAssertEqual(runtime.index, count == 1 ? 0 : 1)
                XCTAssertFalse(runtime.hasSavedSkipAwaitingAdvance)
                XCTAssertEqual(runtime.presentedCount, 1)
                XCTAssertEqual(runtime.skippedCount, revealed ? 0 : 1)
                XCTAssertEqual(runtime.revealedCount, revealed ? 1 : 0)
                XCTAssertNil(runtime.saveError)
                let saved = try XCTUnwrap(source.localSessions.archive.sessions.first?.checkpoint)
                XCTAssertEqual(saved.cumulativeActiveDuration, 7, accuracy: 0.001)
                XCTAssertNil(saved.pendingOutcome)
                let outcomes = source.localSessions.archive.selectionLedger?.outcomes.values.filter { $0.runID == runtime.sessionID.uuidString } ?? []
                XCTAssertEqual(outcomes.count, 1)
                XCTAssertEqual(outcomes.first?.status, revealed ? .revealed : .skipped)
            }
        }
    }

    func testFinitePoolSkipEndsWithItsRealSavedCountAndCannotBeRepeated() throws {
        let (source, container) = try store(); defer { _ = container }
        let activity = try XCTUnwrap(NFDefaultContentCatalog.activity(id: "nf.default.logic.conditions"))
        var now: TimeInterval = 100
        let runtime = NFUniversalSessionRuntime(request: .init(lab: activity.lab, source: .focused,
            seed: 20260904, localeIdentifier: "en", requestedItemCount: 5, isTimed: false,
            mechanicID: activity.mechanicID), monotonicNow: { now })
        XCTAssertTrue(runtime.checkpointDraft(store: source))
        runtime.acknowledgePresented()
        now += 7
        runtime.skip(store: source)
        XCTAssertEqual(runtime.stage, .summary)
        XCTAssertTrue(runtime.endedEarly)
        XCTAssertEqual(runtime.index, 0)
        XCTAssertEqual(runtime.presentedCount, 1)
        XCTAssertEqual(runtime.skippedCount, 1)
        XCTAssertTrue(runtime.correctness.isEmpty)
        XCTAssertNil(runtime.lastResult)
        XCTAssertNotNil(runtime.nextUnavailableReason)
        XCTAssertNil(runtime.saveError)
        XCTAssertFalse(runtime.hasSavedSkipAwaitingAdvance)
        runtime.next(store: source)
        runtime.skip(store: source)
        runtime.retrySaving(store: source)
        XCTAssertEqual(source.attempts.count, 1)
        XCTAssertEqual(runtime.presentedCount, 1)
        let saved = try XCTUnwrap(source.localSessions.archive.sessions.first?.checkpoint)
        XCTAssertEqual(saved.cumulativeActiveDuration, 7, accuracy: 0.001)
        XCTAssertNil(saved.pendingOutcome)
        XCTAssertEqual(source.localSessions.archive.selectionLedger?.outcomes.count, 1)
        XCTAssertEqual(source.localSessions.archive.selectionLedger?.outcomes.values.first?.status, .skipped)
    }

    func testCommittedSkipPendingTransitionSurvivesFailedWriteAndRetriesWithoutDoubleDuration() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "NFPendingSkip-\(UUID())")
        let live = folder.appending(path: "live")
        let held = folder.appending(path: "held")
        try FileManager.default.createDirectory(at: live, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = live.appending(path: "sessions.json")
        let repository = NFLocalSessionRepository(url: url)
        let (source, container) = try store(repository: repository); defer { _ = container }
        let first = NFUniversalSessionRuntime(request: request())
        XCTAssertTrue(first.checkpointDraft(store: source))
        var pending = try XCTUnwrap(repository.archive.sessions.first)
        let originalExercise = first.exercise
        // This is the reachable boundary after the real immutable skip has
        // saved and before its next snapshot has been accepted.
        try source.saveSkippedExercise(attemptID: pending.checkpoint.attemptID, sessionID: pending.id,
            exercise: originalExercise, shownAt: pending.checkpoint.shownAt, activeDuration: 7, source: .focused)
        pending.checkpoint.pendingOutcome = "skip"
        pending.checkpoint.assessmentEvents = ["skipped:\(originalExercise.id)"]
        pending.checkpoint.cumulativeActiveDuration = 7
        pending.checkpoint.itemActiveDuration = 7
        try repository.save(pending)
        first.releaseWriter()
        var launch = pending.request
        launch.localSessionID = pending.id
        launch.localCheckpoint = pending.checkpoint
        let resumed = NFUniversalSessionRuntime(request: launch)
        XCTAssertTrue(resumed.checkpointDraft(store: source))
        XCTAssertTrue(resumed.hasSavedSkipAwaitingAdvance)
        XCTAssertFalse(resumed.canEditDraft)
        let originalAttempt = try XCTUnwrap(source.attempts.first)
        let originalDate = originalAttempt.submittedAt
        try FileManager.default.moveItem(at: live, to: held)
        try Data("blocked transition write".utf8).write(to: live)
        resumed.retrySaving(store: source)
        XCTAssertEqual(resumed.stage, .item)
        XCTAssertEqual(resumed.index, 0)
        XCTAssertTrue(resumed.hasSavedSkipAwaitingAdvance)
        XCTAssertNotNil(resumed.saveError)
        XCTAssertEqual(source.attempts.count, 1)
        XCTAssertEqual(repository.archive.sessions.first?.checkpoint.pendingOutcome, "skip")
        XCTAssertEqual(repository.archive.sessions.first?.checkpoint.cumulativeActiveDuration, 7)
        try FileManager.default.removeItem(at: live)
        try FileManager.default.moveItem(at: held, to: live)
        resumed.retrySaving(store: source)
        XCTAssertEqual(resumed.stage, .item)
        XCTAssertEqual(resumed.index, 1)
        XCTAssertFalse(resumed.hasSavedSkipAwaitingAdvance)
        XCTAssertNil(resumed.saveError)
        XCTAssertEqual(source.attempts.count, 1)
        XCTAssertEqual(source.attempts.first?.id, originalAttempt.id)
        XCTAssertEqual(source.attempts.first?.submittedAt, originalDate)
        XCTAssertEqual(repository.archive.sessions.first?.checkpoint.cumulativeActiveDuration, 7)
        XCTAssertEqual(repository.archive.selectionLedger?.outcomes.count, 1)
        XCTAssertEqual(repository.archive.selectionLedger?.outcomes.values.first?.status, .skipped)
        let reopened = NFLocalSessionRepository(url: url, ownerDeviceID: repository.ownerDeviceID)
        XCTAssertNil(reopened.loadError)
        XCTAssertEqual(reopened.archive.sessions.first?.checkpoint.index, 1)
        XCTAssertEqual(reopened.archive.sessions.first?.checkpoint.cumulativeActiveDuration, 7)
        XCTAssertEqual(reopened.archive.selectionLedger?.outcomes.count, 1)
        resumed.releaseWriter()
    }

    func testSolutionRevealRetainsDraftAndAssistanceWithoutAnIncorrectAnswerOrSkip() throws {
        let (source, container) = try store(); defer { _ = container }
        var now: TimeInterval = 100
        let runtime = NFUniversalSessionRuntime(request: request(), monotonicNow: { now })
        XCTAssertTrue(runtime.checkpointDraft(store: source))
        runtime.acknowledgePresented()
        now += 7
        runtime.numericValue = "my original draft"
        runtime.requestHint()
        runtime.revealSolution(store: source)
        let count = runtime.assistanceEvents.count
        runtime.revealSolution(store: source)
        XCTAssertEqual(runtime.assistanceEvents.count, count, "Repeated reveal must not append another event")
        XCTAssertEqual(runtime.assistanceEvents.last?.kind, .workedSolution)
        XCTAssertEqual(runtime.assistanceEvents.last?.activeOffset, 7)
        XCTAssertFalse(runtime.canSubmit)
        let saved = try XCTUnwrap(source.localSessions.archive.sessions.first)
        XCTAssertTrue(saved.checkpoint.solutionRevealed)
        XCTAssertEqual(saved.checkpoint.assistanceEvents, runtime.assistanceEvents)
        runtime.skip(store: source)
        let attempt = try XCTUnwrap(source.attempts.first)
        XCTAssertEqual(attempt.responseFormatRaw, "revealed")
        XCTAssertEqual(attempt.errorCode, "solution_revealed")
        XCTAssertEqual(NFResponsePresentation.decode(attempt.response), .numeric(.init(value: "my original draft", unit: nil)))
        XCTAssertEqual(attempt.evidenceWeight, 0)
        XCTAssertEqual(runtime.revealedCount, 1)
        XCTAssertEqual(runtime.skippedCount, 0)
        XCTAssertEqual(runtime.incorrectCount, 0)
        XCTAssertEqual(runtime.presentedCount, 1)
        XCTAssertEqual(source.localSessions.archive.snapshots.first?.attemptID, attempt.id)
    }

    func testFailedRevealCheckpointDoesNotDiscloseSolutionOrInventAssistance() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "NFReveal-\(UUID())")
        defer { try? FileManager.default.removeItem(at: folder) }
        let repository = NFLocalSessionRepository(url: folder.appending(path: "sessions.json"))
        let (source, container) = try store(repository: repository); defer { _ = container }
        let runtime = NFUniversalSessionRuntime(request: request())
        XCTAssertTrue(runtime.checkpointDraft(store: source))
        runtime.numericValue = "17"
        try FileManager.default.removeItem(at: folder)
        try Data("blocked write target".utf8).write(to: folder)
        runtime.requestHint(store: source)
        XCTAssertEqual(runtime.hintCount, 0, "An unacknowledged hint must not be disclosed and later counted as unaided work")
        XCTAssertTrue(runtime.assistanceEvents.isEmpty)
        runtime.revealSolution(store: source)
        XCTAssertFalse(runtime.solutionRevealed)
        XCTAssertTrue(runtime.assistanceEvents.isEmpty)
        XCTAssertTrue(runtime.canSubmit)
        XCTAssertNotNil(runtime.saveError)
        XCTAssertTrue(source.attempts.isEmpty)
    }

    func testFixedCountUnscoredPracticeEndsWithoutInventingObjectiveAnswers() throws {
        let (source, container) = try store(); defer { _ = container }
        let runtime = NFUniversalSessionRuntime(request: request())
        XCTAssertTrue(runtime.checkpointDraft(store: source))
        for _ in 0..<3 { runtime.skip(store: source) }
        XCTAssertEqual(runtime.stage, .summary)
        XCTAssertEqual(runtime.presentedCount, 3)
        XCTAssertEqual(runtime.skippedCount, 3)
        XCTAssertTrue(runtime.correctness.isEmpty)
        XCTAssertEqual(source.localSessions.archive.sessions.first?.status, .completed)
        XCTAssertTrue(source.attempts.allSatisfy { $0.evidenceWeight == 0 && $0.wasSkipped })
    }

    func testHistoricalCorrectionReplaysOnceWithoutRewritingOriginalAnswerAndScore() throws {
        let (source, container) = try store(); defer { _ = container }
        let record = AttemptRecord(sessionID: UUID(), lab: .retrieval, itemID: "retained-old-item",
            prompt: "How is the arithmetic mean of a finite set of numbers calculated?",
            response: "Sum all observations then divide by their count",
            correctAnswer: "Add the values and divide by the number of values",
            isCorrect: false, confidence: .guessing, evidenceClass: .practice, source: .focused)
        record.templateID = "nf.fallback.retrieval.practice.v3.short-answer"
        record.scoringVersion = 7
        record.responseFormatRaw = "shortText"
        record.deterministicCredit = 0
        container.mainContext.insert(record)
        try container.mainContext.save()
        source.reload()
        try source.reconcileHistoricalAuthority()
        let correctionCount = source.localSessions.archive.contentCorrections?.count
        let dispositions = source.evidenceDispositions
        try source.reconcileHistoricalAuthority()
        XCTAssertEqual(source.localSessions.archive.contentCorrections?.count, correctionCount)
        XCTAssertEqual(source.evidenceDispositions, dispositions)
        XCTAssertEqual(source.effectiveAttemptDTO(record).credit, 1)
        XCTAssertEqual(source.effectiveAttemptDTO(record).correct, true)
        XCTAssertEqual(record.deterministicCredit, 0)
        XCTAssertFalse(record.isCorrect)
        XCTAssertEqual(record.response, "Sum all observations then divide by their count")
        XCTAssertEqual(record.scoringVersion, 7)
        XCTAssertTrue(source.localSessions.archive.contentCorrections?.allSatisfy { $0.originalResultDigest.count == 64 } == true)
        try source.localSessions.removeReferences(attemptIDs: [record.id], generationIDs: [])
        XCTAssertTrue(source.localSessions.archive.contentCorrections?.isEmpty == true)
    }

    func testUnchangedStructuredResponseKeepsConfidenceAcrossRepeatedEncoding() throws {
        let (source, container) = try store(); defer { _ = container }
        let activity = try XCTUnwrap(NFDefaultContentCatalog.activity(id: "nf.default.logic.state-trace"))
        let request = SessionRequest(lab: .logicDebugging, source: .focused, seed: 20260904,
            localeIdentifier: "en", requestedItemCount: 1, isTimed: false, mechanicID: activity.mechanicID)
        let runtime = NFUniversalSessionRuntime(request: request)
        guard case let .logicState(schema) = runtime.exercise.interaction else { return XCTFail("Fixture must exercise dictionary-valued structured answers") }
        XCTAssertTrue(runtime.checkpointDraft(store: source))
        runtime.logicState = schema.expectedFinalState
        runtime.violatedRuleID = schema.expectedViolatedRuleID
        runtime.chooseConfidence(.fairlyConfident)
        let originalIdentity = runtime.responseDraftIdentity
        for _ in 0..<100 {
            // Rebuilding the same state in another insertion order is not an edit.
            runtime.logicState = Dictionary(uniqueKeysWithValues: schema.expectedFinalState.keys.sorted().reversed().map { ($0, schema.expectedFinalState[$0]!) })
            runtime.invalidateConfidenceAfterEdit()
            XCTAssertEqual(runtime.selectedConfidence, .fairlyConfident)
            XCTAssertEqual(runtime.responseDraftIdentity, originalIdentity)
        }
        runtime.logicState[try XCTUnwrap(schema.expectedFinalState.keys.first)] = "a genuinely changed response"
        runtime.invalidateConfidenceAfterEdit()
        XCTAssertNil(runtime.selectedConfidence, "An actual answer change still requires a new confidence choice")
    }

    func testStructuredCommitRetryKeepsOriginalBytesAndRejectsChangedKeyResultOrSession() throws {
        let (source, container) = try store(); defer { _ = container }
        let activity = try XCTUnwrap(NFDefaultContentCatalog.activity(id: "nf.default.logic.state-trace"))
        let runtime = NFUniversalSessionRuntime(request: .init(lab: .logicDebugging, source: .focused,
            seed: 20260904, localeIdentifier: "en", requestedItemCount: 1, isTimed: false, mechanicID: activity.mechanicID))
        guard case let .logicState(schema) = runtime.exercise.interaction else { return XCTFail("Expected structured state fixture") }
        let response = NFExerciseResponse.logicState(.init(finalState: schema.expectedFinalState,
            violatedRuleID: schema.expectedViolatedRuleID))
        let result = NFExerciseScoringEngine.score(response, for: runtime.exercise)
        let attemptID = UUID(), sessionID = UUID(), shownAt = Date(timeIntervalSince1970: 1_800_000_000)
        func save(_ submitted: NFExerciseResponse, result: NFExerciseScoringResult, session: UUID) throws {
            try source.saveExerciseAttempt(attemptID: attemptID, sessionID: session, exercise: runtime.exercise,
                response: submitted, result: result, confidence: .certain, shownAt: shownAt,
                activeDuration: 7, source: .focused)
        }
        try save(response, result: result, session: sessionID)
        let original = try XCTUnwrap(source.attempts.first)
        // A legacy writer's harmless JSON whitespace must not invalidate retry.
        let legacyBytes = "\n" + original.response + "\n"
        original.response = legacyBytes
        try container.mainContext.save()
        let originalDate = original.submittedAt
        for _ in 0..<30 {
            let reordered = Dictionary(uniqueKeysWithValues: schema.expectedFinalState.keys.sorted().reversed().map { ($0, schema.expectedFinalState[$0]!) })
            try save(.logicState(.init(finalState: reordered, violatedRuleID: schema.expectedViolatedRuleID)), result: result, session: sessionID)
        }
        XCTAssertEqual(source.attempts.count, 1)
        XCTAssertEqual(original.response, legacyBytes)
        XCTAssertEqual(original.submittedAt, originalDate)

        let changedKey = NFExerciseScoringResult(exerciseID: result.exerciseID, scoringVersion: result.scoringVersion,
            isCorrect: result.isCorrect, credit: result.credit, normalizedResponse: result.normalizedResponse,
            errorCode: result.errorCode, expectedAnswerSummary: "a different key", feedback: result.feedback)
        let changedResult = NFExerciseScoringResult(exerciseID: result.exerciseID, scoringVersion: result.scoringVersion,
            isCorrect: !result.isCorrect, credit: result.credit, normalizedResponse: result.normalizedResponse,
            errorCode: result.errorCode, expectedAnswerSummary: result.expectedAnswerSummary, feedback: result.feedback)
        XCTAssertThrowsError(try save(response, result: changedKey, session: sessionID))
        XCTAssertThrowsError(try save(response, result: changedResult, session: sessionID))
        XCTAssertThrowsError(try save(response, result: result, session: UUID()))
        XCTAssertEqual(source.attempts.count, 1)
        XCTAssertEqual(original.response, legacyBytes)
        XCTAssertEqual(original.correctAnswerText, result.expectedAnswerSummary)
        XCTAssertEqual(original.isCorrect, result.isCorrect)
    }

    func testRemovingOneRunKeepsPublicSnapshotReferencedByAnotherRun() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "NFSharedSnapshot-\(UUID())")
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appending(path: "sessions.json")
        let repository = NFLocalSessionRepository(url: url)
        let (source, container) = try store(repository: repository); defer { _ = container }
        let launch = request()
        let first = NFUniversalSessionRuntime(request: launch)
        XCTAssertTrue(first.checkpointDraft(store: source))
        let firstAttempt = try XCTUnwrap(repository.archive.sessions.first?.checkpoint.attemptID)
        first.releaseWriter()
        let second = NFUniversalSessionRuntime(request: launch)
        XCTAssertTrue(second.checkpointDraft(store: source))
        let secondAttempt = try XCTUnwrap(repository.archive.sessions.first(where: { $0.id == second.sessionID })?.checkpoint.attemptID)
        XCTAssertEqual(repository.archive.selectionLedger?.slots.count, 2)
        XCTAssertEqual(repository.archive.selectionLedger?.snapshots.count, 1, "Exact public snapshot deduplicates within the same device privacy scope")
        try repository.removeReferences(attemptIDs: [firstAttempt])
        XCTAssertEqual(repository.archive.selectionLedger?.slots.count, 1)
        XCTAssertEqual(repository.archive.selectionLedger?.snapshots.count, 1)
        XCTAssertTrue(second.ownsWriter, "Deleting a different run must not revoke the retained writer")
        let reopened = NFLocalSessionRepository(url: url, ownerDeviceID: repository.ownerDeviceID)
        XCTAssertNil(reopened.loadError, "Deleting one reference must not corrupt another retained run")
        XCTAssertEqual(reopened.archive.sessions.map(\.id), [second.sessionID])
        try repository.removeReferences(attemptIDs: [secondAttempt])
        XCTAssertFalse(second.ownsWriter, "A deleted run cannot be resurrected by its stale writer")
        XCTAssertEqual(repository.archive.selectionLedger?.snapshots.count, 0)
    }

    func testPersonalDraftDoesNotEnterSyncEligibleCheckpointModel() throws {
        let (source, container) = try store(); defer { _ = container }
        let runtime = NFUniversalSessionRuntime(request: request(personal: true))
        runtime.numericValue = "PRIVATE DRAFT"; runtime.scratchpad = "PRIVATE NOTES"
        XCTAssertTrue(runtime.checkpointDraft(store: source))
        XCTAssertEqual(source.localSessions.archive.sessions.count, 1)
        XCTAssertTrue(source.sessionCheckpoints.isEmpty,
                      "Private draft payloads belong only to the local session archive.")
    }

    func testSecondWindowCannotWriteUntilFirstCheckpointsAndTransfersOwnership() throws {
        let (source, container) = try store(); defer { _ = container }
        let first = NFUniversalSessionRuntime(request: request())
        first.numericValue = "17"
        XCTAssertTrue(first.checkpointDraft(store: source))
        var launch = request(); launch.localSessionID = first.sessionID
        launch.localCheckpoint = source.localSessions.archive.sessions.first?.checkpoint
        let second = NFUniversalSessionRuntime(request: launch)
        XCTAssertFalse(second.checkpointDraft(store: source))
        second.takeOver(store: source)
        XCTAssertFalse(first.ownsWriter); XCTAssertTrue(second.ownsWriter)
        XCTAssertEqual(second.numericValue, "17")
        first.numericValue = "stale write"
        XCTAssertFalse(first.checkpointDraft(store: source))
        XCTAssertEqual(source.localSessions.archive.sessions.first?.checkpoint.response,
                       .numeric(NFNumericSubmission(value: "17", unit: nil)))
    }

    func testStaleReflectionWriterCannotSaveAfterWindowTakeover() throws {
        let (source, container) = try store(); defer { _ = container }
        let first = NFUniversalSessionRuntime(request: request())
        XCTAssertTrue(first.checkpointDraft(store: source))
        first.numericValue = "0"
        first.chooseConfidence(.certain)
        first.submitInline(store: source)
        XCTAssertEqual(first.stage, .feedback)
        first.reflect()
        XCTAssertEqual(first.stage, .reflection)
        first.reflectionNote = "Checkpointed before takeover."
        XCTAssertTrue(first.checkpointDraft(store: source))
        let saved = try XCTUnwrap(source.localSessions.archive.sessions.first)
        var launch = saved.request
        launch.localCheckpoint = saved.checkpoint
        launch.localSessionID = saved.id
        let second = NFUniversalSessionRuntime(request: launch)
        XCTAssertFalse(second.checkpointDraft(store: source))
        second.takeOver(store: source)
        XCTAssertTrue(second.ownsWriter)
        XCTAssertFalse(first.canSaveReflection)
        first.reflectionNote = "Stale window must not save this."
        first.saveReflection(store: source)
        XCTAssertTrue(source.attemptReflections.isEmpty)
        second.reflectionNote = "Current window interpretation."
        second.saveReflection(store: source)
        XCTAssertEqual(source.attemptReflections.count, 1)
        XCTAssertEqual(source.attemptReflections.first?.note, "Current window interpretation.")
        XCTAssertEqual(source.attempts.count, 1)
    }

    func testPreparedSkipReconcilesAfterAttemptSavedWithoutCreatingAnotherAttempt() throws {
        let (source, container) = try store(); defer { _ = container }
        let first = NFUniversalSessionRuntime(request: request())
        XCTAssertTrue(first.checkpointDraft(store: source))
        var prepared = try XCTUnwrap(source.localSessions.archive.sessions.first)
        prepared.checkpoint.pendingOutcome = "skip"
        try source.localSessions.save(prepared)
        try source.saveSkippedExercise(attemptID: prepared.checkpoint.attemptID, sessionID: first.sessionID,
            exercise: first.exercise, shownAt: prepared.checkpoint.shownAt, activeDuration: 3, source: .focused)
        first.releaseWriter()

        var launch = prepared.request
        launch.localCheckpoint = prepared.checkpoint
        launch.localSessionID = first.sessionID
        let restored = NFUniversalSessionRuntime(request: launch)
        XCTAssertTrue(restored.checkpointDraft(store: source))
        restored.reconcilePendingSkip(store: source)
        XCTAssertEqual(source.attempts.count, 1)
        XCTAssertEqual(source.attempts.first?.id, prepared.checkpoint.attemptID)
        XCTAssertTrue(source.attempts.first?.wasSkipped == true)
        XCTAssertEqual(restored.index, 1)
        XCTAssertNil(source.localSessions.archive.sessions.first?.checkpoint.pendingOutcome)
    }

    func testMalformedStoredCheckpointRetainsOriginalBytesAndBecomesRecoveryOnly() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "NFStoredIntegrity-\(UUID())")
        defer { try? FileManager.default.removeItem(at: folder) }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appending(path: "sessions.json")
        let (source, container) = try store(); defer { _ = container }
        let runtime = NFUniversalSessionRuntime(request: request())
        XCTAssertTrue(runtime.checkpointDraft(store: source))
        var malformed = source.localSessions.archive
        malformed.sessions[0].checkpoint.exerciseDigest = "changed-on-disk"
        let originalBytes = try JSONEncoder().encode(malformed)
        try originalBytes.write(to: url)
        let restored = NFLocalSessionRepository(url: url, ownerDeviceID: source.localSessions.ownerDeviceID)
        XCTAssertNil(restored.loadError)
        XCTAssertEqual(restored.archive.sessions.first?.status, .migrationRecovery)
        XCTAssertEqual(try Data(contentsOf: url), originalBytes)
    }
}

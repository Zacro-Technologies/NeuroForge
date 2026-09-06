import Foundation
import SwiftData
import XCTest
#if os(macOS)
import AppKit
#endif
@testable import NeuroForge

@MainActor
final class ExactSessionContinuityTests: XCTestCase {
    private func makeStore(repository: NFLocalSessionRepository? = nil) throws -> (AppStore, ModelContainer) {
        let container = try ModelContainer(for: Schema(NFSchemaV1.models), configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        return (AppStore(context: container.mainContext, localSessionRepository: repository), container)
    }

    private func request() -> SessionRequest {
        SessionRequest(lab: .mentalMath, source: .focused, seed: 20260904,
            localeIdentifier: "en", preferredMentalMathKind: .multiplication,
            requestedItemCount: 5, isTimed: false,
            mechanicID: NFDefaultContentCatalog.activities.first { $0.id == "nf.default.mental.rapid-recall" }!.mechanicID)
    }

    private func answer(_ runtime: NFUniversalSessionRuntime, store: AppStore, value: String = "0") {
        runtime.numericValue = value
        runtime.submitInline(store: store)
    }

    private func numericProtectedRuntime() throws -> NFUniversalSessionRuntime {
        // The adaptive catalog can select several valid response formats for
        // numerical fluency. Select an actual supported numeric descriptor;
        // never replace its protected contract or seed a scoring result.
        for seed in UInt64(20260904)..<UInt64(20261032) {
            let request = SessionRequest(lab: .mentalMath, source: .reassessment, seed: seed,
                localeIdentifier: "en", evidenceClass: .assessmentHoldout,
                assessmentBlock: .numericalFluency, reassessmentCycle: 1, isTimed: false)
            let runtime = NFUniversalSessionRuntime(request: request)
            if case .numeric = runtime.exercise.interaction,
               runtime.exercise.assessmentProtected,
               runtime.exercise.availabilityReason == nil,
               runtime.assessmentDescriptor != nil {
                return runtime
            }
        }
        throw XCTUnwrapFailure.noNumericProtectedDescriptor
    }

    private enum XCTUnwrapFailure: Error { case noNumericProtectedDescriptor }

    func testQuestionThreeDraftRestoresExactIdentitySnapshotHintsAndPositionAfterRepositoryReload() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "NFExact-\(UUID())")
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appending(path: "sessions.json")
        let owner = UUID()
        let repo = NFLocalSessionRepository(url: url, ownerDeviceID: owner)
        let (store, container) = try makeStore(repository: repo)
        defer { _ = container }
        let runtime = NFUniversalSessionRuntime(request: request())
        XCTAssertTrue(runtime.checkpointDraft(store: store))
        answer(runtime, store: store)
        XCTAssertEqual(runtime.stage, .feedback)
        runtime.next(store: store)
        answer(runtime, store: store)
        runtime.next(store: store)
        XCTAssertEqual(runtime.index, 2)
        runtime.numericValue = "17"
        runtime.scratchpad = NFScratchpadPayload(notes: "Carry the one", drawingData: Data([1, 2, 3])).storedValue
        runtime.requestHint()
        XCTAssertTrue(runtime.checkpointDraft(store: store))
        let exact = runtime.exercise
        let reopened = NFLocalSessionRepository(url: url, ownerDeviceID: owner)
        XCTAssertNil(reopened.loadError)
        let (restoredStore, restoredContainer) = try makeStore(repository: reopened)
        defer { _ = restoredContainer }
        XCTAssertTrue(restoredStore.resumeSession(runtime.sessionID))
        let restored = NFUniversalSessionRuntime(request: try XCTUnwrap(restoredStore.activeSessionRequest))
        XCTAssertEqual(restored.sessionID, runtime.sessionID)
        XCTAssertEqual(restored.index, 2)
        XCTAssertEqual(restored.itemCount, 5)
        XCTAssertEqual(restored.numericValue, "17")
        XCTAssertEqual(restored.exercise, exact)
        XCTAssertEqual(restored.scratchpad, runtime.scratchpad)
        XCTAssertEqual(restored.hintCount, runtime.hintCount)
        XCTAssertTrue(restored.isPaused)
        XCTAssertGreaterThan(restored.interruptionCount, runtime.interruptionCount)
    }

    func testSavedFeedbackDoesNotAdvanceOrRescoreUntilNext() throws {
        let (store, container) = try makeStore()
        defer { _ = container }
        let runtime = NFUniversalSessionRuntime(request: request())
        answer(runtime, store: store)
        XCTAssertEqual(store.attempts.count, 1)
        let question = runtime.exercise
        XCTAssertTrue(runtime.checkpointDraft(store: store))
        runtime.releaseWriter()
        XCTAssertTrue(store.resumeSession(runtime.sessionID))
        let restored = NFUniversalSessionRuntime(request: try XCTUnwrap(store.activeSessionRequest))
        XCTAssertEqual(restored.stage, .feedback)
        XCTAssertEqual(restored.exercise, question)
        XCTAssertEqual(restored.index, 0)
        XCTAssertEqual(restored.numericValue, "0")
        restored.resume()
        restored.commit(confidence: .certain, store: store)
        XCTAssertEqual(store.attempts.count, 1)
        restored.next(store: store)
        XCTAssertEqual(restored.index, 1)
        restored.next(store: store)
        XCTAssertEqual(restored.index, 1, "Repeated Next cannot reserve a second item")
    }

    func testMonotonicTimePreservesSegmentsAcrossSuspensionAndWallClockJump() throws {
        let (store, container) = try makeStore()
        defer { _ = container }
        var clock: TimeInterval = 100
        let runtime = NFUniversalSessionRuntime(request: request(), monotonicNow: { clock })
        XCTAssertTrue(runtime.checkpointDraft(store: store))
        runtime.acknowledgePresented()
        clock = 120
        runtime.pause(at: Date(timeIntervalSince1970: 500))
        XCTAssertTrue(runtime.checkpointDraft(store: store))
        runtime.releaseWriter()
        XCTAssertTrue(store.resumeSession(runtime.sessionID))
        let restored = NFUniversalSessionRuntime(request: try XCTUnwrap(store.activeSessionRequest), monotonicNow: { clock })
        XCTAssertTrue(restored.checkpointDraft(store: store))
        clock = 50_000
        restored.resume(at: Date(timeIntervalSince1970: -50_000))
        clock += 5
        answer(restored, store: store)
        XCTAssertEqual(try XCTUnwrap(store.attempts.first).activeDurationSeconds, 25, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(store.attempts.first).confidenceRaw, nil)
        XCTAssertGreaterThan(try XCTUnwrap(store.attempts.first).interruptionCount, 0)
    }

    func testBlankInputDoesNotCreateAttemptAndOptionalConfidenceRemainsAbsent() throws {
        let (store, container) = try makeStore()
        defer { _ = container }
        let runtime = NFUniversalSessionRuntime(request: request())
        runtime.submitInline(store: store)
        XCTAssertTrue(store.attempts.isEmpty)
        answer(runtime, store: store)
        XCTAssertEqual(runtime.stage, .feedback)
        XCTAssertNil(store.attempts.first?.confidenceRaw)
        XCTAssertEqual(store.attempts.count, 1)
    }

    func testSubmittedResponseLocksUntilAnAcknowledgedNextQuestion() throws {
        let (store, container) = try makeStore()
        defer { _ = container }
        let runtime = NFUniversalSessionRuntime(request: request())
        XCTAssertTrue(runtime.checkpointDraft(store: store))
        XCTAssertTrue(runtime.canEditDraft)
        XCTAssertFalse(runtime.canRateSelfCheck)
        runtime.numericValue = "17"
        runtime.pause()
        XCTAssertFalse(runtime.canEditDraft)
        runtime.resume()
        XCTAssertTrue(runtime.canEditDraft)
        runtime.submitInline(store: store)
        XCTAssertEqual(runtime.stage, .feedback)
        XCTAssertFalse(runtime.canEditDraft)
        XCTAssertFalse(runtime.canRateSelfCheck)
        let original = try XCTUnwrap(store.attempts.first)
        let response = original.response
        XCTAssertEqual(runtime.numericValue, "17")
        XCTAssertEqual(try JSONDecoder().decode(NFExerciseResponse.self, from: Data(response.utf8)),
            .numeric(.init(value: "17", unit: nil)))
        runtime.next(store: store)
        XCTAssertEqual(runtime.stage, .item)
        XCTAssertEqual(runtime.index, 1)
        XCTAssertTrue(runtime.canEditDraft)
        XCTAssertFalse(runtime.canRateSelfCheck)
        runtime.numericValue = "29"
        XCTAssertTrue(runtime.checkpointDraft(store: store))
        XCTAssertEqual(original.response, response)
        XCTAssertEqual(store.attempts.count, 1)
    }

    func testSelfCheckLocksRecallAtComparisonButAllowsRatingUntilCommit() throws {
        let (store, container) = try makeStore()
        defer { _ = container }
        let chunk = NFSourceChunk(id: "locked-source-recall", documentID: UUID(), documentVersion: 1,
            sourceName: "Synthetic comparison.txt", locator: .init(page: nil, lineStart: 1, lineEnd: 1, section: nil),
            text: "An exact reference retained for comparison.", contentHash: "locked-source-recall", ordinal: 0, language: "en")
        let request = try NFSourceReviewExactAdapter.makeRequest(chunk: chunk, localeIdentifier: "en")
        let runtime = NFUniversalSessionRuntime(request: request)
        XCTAssertTrue(runtime.checkpointDraft(store: store))
        XCTAssertTrue(runtime.canEditDraft)
        XCTAssertFalse(runtime.canRateSelfCheck)
        runtime.selfCheckReflection = "My original unaided recall."
        runtime.submitInline(store: store)
        XCTAssertEqual(runtime.stage, .selfCheckComparison)
        XCTAssertFalse(runtime.canEditDraft)
        XCTAssertTrue(runtime.canRateSelfCheck)
        runtime.pause()
        XCTAssertFalse(runtime.canRateSelfCheck)
        runtime.resume()
        XCTAssertTrue(runtime.canRateSelfCheck)
        runtime.selfCheckRating = .partiallyMatched
        runtime.saveSelfCheck(store: store)
        XCTAssertEqual(runtime.stage, .feedback)
        XCTAssertFalse(runtime.canEditDraft)
        XCTAssertFalse(runtime.canRateSelfCheck)
        let record = try XCTUnwrap(store.attempts.first)
        XCTAssertEqual(try JSONDecoder().decode(NFExerciseResponse.self, from: Data(record.response.utf8)),
            .selfCheck(.init(rating: .partiallyMatched, reflection: "My original unaided recall.")))
        XCTAssertEqual(record.evidenceWeight, 0)
        runtime.next(store: store)
        XCTAssertEqual(runtime.stage, .summary)
        XCTAssertFalse(runtime.canEditDraft)
        XCTAssertFalse(runtime.canRateSelfCheck)
        XCTAssertEqual(store.attempts.count, 1)
    }

    func testRepeatedSubmitCommitsOnceWithNoMandatoryReflection() throws {
        let (store, container) = try makeStore()
        defer { _ = container }
        let runtime = NFUniversalSessionRuntime(request: request())
        runtime.numericValue = "-9999999"
        runtime.chooseConfidence(.certain)
        runtime.submitInline(store: store)
        runtime.submitInline(store: store)
        runtime.commit(confidence: .certain, store: store)
        XCTAssertEqual(store.attempts.count, 1)
        XCTAssertEqual(runtime.stage, .feedback)
        XCTAssertNil(runtime.selectedReflectionCode)
        runtime.reflect()
        XCTAssertEqual(runtime.stage, .reflection)
        XCTAssertTrue(runtime.checkpointDraft(store: store), "Every reflection stage can save and close")
    }

    func testRepositoryFailureKeepsPreviousAcknowledgementAndDraft() throws {
        let parent = FileManager.default.temporaryDirectory.appending(path: "NFBlocked-\(UUID())")
        try Data("not a directory".utf8).write(to: parent)
        defer { try? FileManager.default.removeItem(at: parent) }
        let repo = NFLocalSessionRepository(url: parent.appending(path: "session.json"))
        let (store, container) = try makeStore(repository: repo)
        defer { _ = container }
        let runtime = NFUniversalSessionRuntime(request: request())
        runtime.numericValue = "17"
        XCTAssertFalse(runtime.checkpointDraft(store: store))
        XCTAssertEqual(runtime.numericValue, "17")
        XCTAssertTrue(store.resumableSessions.isEmpty)
        XCTAssertNotNil(runtime.saveError)
    }

    func testUnknownVersionDoesNotOverwriteOriginalFile() throws {
        let file = FileManager.default.temporaryDirectory.appending(path: "NFFuture-\(UUID()).json")
        defer { try? FileManager.default.removeItem(at: file) }
        let bytes = Data(#"{"schemaVersion":999,"sessions":[],"snapshots":[]}"#.utf8)
        try bytes.write(to: file)
        let repo = NFLocalSessionRepository(url: file)
        XCTAssertNotNil(repo.loadError)
        XCTAssertThrowsError(try repo.removeAll())
        XCTAssertEqual(try Data(contentsOf: file), bytes)
    }

    func testCrossDeviceImportPreservesDraftWithoutWritableContinuation() throws {
        let (source, container) = try makeStore()
        defer { _ = container }
        let runtime = NFUniversalSessionRuntime(request: request())
        runtime.numericValue = "17"
        XCTAssertTrue(runtime.checkpointDraft(store: source))
        let (target, otherContainer) = try makeStore()
        defer { _ = otherContainer }
        try target.localSessions.importArchive(source.localSessions.exportArchive)
        XCTAssertFalse(target.resumeSession(runtime.sessionID))
        XCTAssertEqual(target.localSessions.archive.sessions.first?.status, .migrationRecovery)
        XCTAssertEqual(target.localSessions.archive.sessions.first?.checkpoint.response, .numeric(NFNumericSubmission(value: "17", unit: nil)))
    }

    func testExactSnapshotIsAvailableForTypedHistoryAndLocalDeletionIncludesIt() throws {
        let (store, container) = try makeStore()
        defer { _ = container }
        let runtime = NFUniversalSessionRuntime(request: request())
        answer(runtime, store: store, value: "17")
        let attempt = try XCTUnwrap(store.attempts.first)
        XCTAssertEqual(store.exerciseSnapshot(for: attempt.id), runtime.exercise)
        XCTAssertEqual(NFResponsePresentation.text(attempt.response, exercise: store.exerciseSnapshot(for: attempt.id)), "17")
        try store.localSessions.removeAll()
        XCTAssertNil(store.exerciseSnapshot(for: attempt.id))
    }
    func testPreparedAnswerRecoversAfterAttemptWriteWithoutDuplicateResult() throws {
        let (store, container) = try makeStore()
        defer { _ = container }
        let runtime = NFUniversalSessionRuntime(request: request())
        runtime.numericValue = "17"
        XCTAssertTrue(runtime.checkpointDraft(store: store))
        var run = try XCTUnwrap(store.resumableSessions.first)
        let response = NFExerciseResponse.numeric(NFNumericSubmission(value: "17", unit: nil))
        let result = NFExerciseScoringEngine.score(response, for: runtime.exercise)
        run.checkpoint.phase = .confidence
        run.checkpoint.result = result
        try store.localSessions.save(run)
        try store.saveExerciseAttempt(attemptID: run.checkpoint.attemptID, sessionID: run.id,
            exercise: runtime.exercise, response: response, result: result, confidence: nil,
            shownAt: run.checkpoint.shownAt, activeDuration: 0, source: .focused)
        runtime.releaseWriter()
        XCTAssertTrue(store.resumeSession(run.id))
        let recovered = NFUniversalSessionRuntime(request: try XCTUnwrap(store.activeSessionRequest))
        XCTAssertTrue(recovered.checkpointDraft(store: store))
        recovered.commit(confidence: nil, store: store)
        recovered.commit(confidence: nil, store: store)
        XCTAssertEqual(store.attempts.count, 1)
        XCTAssertEqual(recovered.correctness.count, 1)
        XCTAssertEqual(recovered.stage, .feedback)
        XCTAssertEqual(store.resumableSessions.first?.checkpoint.committedAttemptID, run.checkpoint.attemptID)
    }

    func testPreparedSkipRecoversAfterAttemptWriteWithoutReansweringSlot() throws {
        let (store, container) = try makeStore()
        defer { _ = container }
        let runtime = NFUniversalSessionRuntime(request: request())
        XCTAssertTrue(runtime.checkpointDraft(store: store))
        var run = try XCTUnwrap(store.resumableSessions.first)
        run.checkpoint.pendingOutcome = "skip"
        try store.localSessions.save(run)
        try store.saveSkippedExercise(attemptID: run.checkpoint.attemptID, sessionID: run.id,
            exercise: runtime.exercise, shownAt: run.checkpoint.shownAt, activeDuration: 0,
            source: .focused)
        runtime.releaseWriter()
        XCTAssertTrue(store.resumeSession(run.id))
        let recovered = NFUniversalSessionRuntime(request: try XCTUnwrap(store.activeSessionRequest))
        XCTAssertTrue(recovered.checkpointDraft(store: store))
        recovered.reconcilePendingSkip(store: store)
        XCTAssertEqual(store.attempts.count, 1)
        XCTAssertEqual(store.attempts.first?.wasSkipped, true)
        XCTAssertEqual(recovered.index, 1)
        XCTAssertTrue(recovered.correctness.isEmpty)
    }

    func testWindowTakeoverRequiresPriorCheckpointAndRevokesStaleWriter() {
        let repo = NFLocalSessionRepository()
        let first = UUID(), second = UUID(), session = UUID()
        var acceptsSave = false
        XCTAssertTrue(repo.claimWriter(first, sessionID: session, checkpoint: { acceptsSave }))
        XCTAssertFalse(repo.claimWriter(second, sessionID: session, checkpoint: { true }))
        XCTAssertFalse(repo.takeOver(second, sessionID: session, checkpoint: { true }))
        XCTAssertTrue(repo.isWriter(first, sessionID: session))
        acceptsSave = true
        XCTAssertTrue(repo.takeOver(second, sessionID: session, checkpoint: { true }))
        XCTAssertFalse(repo.isWriter(first, sessionID: session))
        XCTAssertTrue(repo.isWriter(second, sessionID: session))
    }

    func testNumericEquivalentEditsRetainConfidenceAndMeaningfulEditsClearIt() throws {
        let (store, container) = try makeStore()
        defer { _ = container }
        let runtime = NFUniversalSessionRuntime(request: request())
        runtime.numericValue = "12"
        runtime.chooseConfidence(.certain)
        runtime.numericValue = "12.0"
        runtime.invalidateConfidenceAfterEdit()
        XCTAssertEqual(runtime.selectedConfidence, .certain)
        runtime.numericValue = "13"
        runtime.invalidateConfidenceAfterEdit()
        XCTAssertNil(runtime.selectedConfidence)
        runtime.submitInline(store: store)
        XCTAssertNil(store.attempts.first?.confidenceRaw)
    }

    func testClosePolicyRequiresExactAcknowledgementAndQuitRechecksEveryWindow() {
        XCTAssertEqual(NFSessionExitDisposition.resolve(saveSucceeded: false, exactAcknowledgement: false, pendingCommit: true), .unacknowledged)
        XCTAssertEqual(NFSessionExitDisposition.resolve(saveSucceeded: false, exactAcknowledgement: true, pendingCommit: true), .pendingCommit)
        let registry = NFSessionCloseRegistry()
        let first = UUID(), second = UUID()
        var calls = 0
        var saved = false
        registry.register(first) { calls += 1; return saved }
        registry.register(second) { calls += 1; return true }
        XCTAssertFalse(registry.prepareToClose())
        XCTAssertEqual(calls, 2)
        saved = true
        XCTAssertTrue(registry.prepareToClose())
        saved = false
        XCTAssertFalse(registry.prepareToClose(), "A cancelled quit must never cache an earlier successful check")
        // Two views of the same logical run use distinct registration tokens.
        // Removing the saved secondary view must retain the blocked writer.
        registry.remove(second)
        XCTAssertFalse(registry.prepareToClose())
        registry.remove(first)
        XCTAssertTrue(registry.prepareToClose())
    }

    func testFailedCloseDiscardsOnlyUnsavedMemoryAndCannotAutosaveAfterDiscard() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "NFExit-\(UUID())")
        let backup = folder.appendingPathExtension("backup")
        defer { try? FileManager.default.removeItem(at: folder); try? FileManager.default.removeItem(at: backup) }
        let repository = NFLocalSessionRepository(url: folder.appending(path: "session.json"))
        let (store, container) = try makeStore(repository: repository); defer { _ = container }
        let runtime = NFUniversalSessionRuntime(request: request())
        runtime.numericValue = "17"
        XCTAssertTrue(runtime.checkpointDraft(store: store))
        let saved = try XCTUnwrap(repository.archive.sessions.first)
        try FileManager.default.moveItem(at: folder, to: backup)
        try Data("not a directory".utf8).write(to: folder)
        runtime.numericValue = "29"
        runtime.scratchpad = NFScratchpadPayload(notes: "My unsaved calculation", drawingData: Data()).storedValue
        XCTAssertEqual(runtime.prepareToClose(store: store), .unacknowledged)
        XCTAssertTrue(runtime.recoveryText.contains("29")); XCTAssertTrue(runtime.recoveryText.contains("My unsaved calculation"))
        runtime.finishClosing()
        try FileManager.default.removeItem(at: folder)
        try FileManager.default.moveItem(at: backup, to: folder)
        XCTAssertFalse(runtime.checkpointDraft(store: store), "Scene/debounce callbacks must not resurrect discarded edits")
        XCTAssertEqual(repository.archive.sessions.first?.checkpoint.response, saved.checkpoint.response)
        XCTAssertEqual(repository.archive.sessions.first?.checkpoint.scratchpad, saved.checkpoint.scratchpad)
    }

    func testLocalAcknowledgementSurvivesSecondaryAdapterFailureAndChangedDraftDoesNot() throws {
        enum SecondaryFailure: Error { case unavailable }
        let (store, container) = try makeStore(); defer { _ = container }
        let runtime = NFUniversalSessionRuntime(request: request())
        runtime.numericValue = "17"
        runtime.pause()
        // Exercise the real local write inside the same throwing adapter used
        // by the legacy second write. A false outer result is not a lost draft.
        XCTAssertFalse(runtime.checkpointDraft(using: {
            XCTAssertTrue(runtime.checkpointDraft(store: store))
            throw SecondaryFailure.unavailable
        }))
        XCTAssertEqual(runtime.exitDisposition(store: store), .saved)
        runtime.numericValue = "29"
        XCTAssertEqual(runtime.exitDisposition(store: store), .unacknowledged)
        XCTAssertEqual(store.localSessions.archive.sessions.first?.checkpoint.response,
            .numeric(.init(value: "17", unit: nil)))
    }

    func testPreparedSourceSelfCheckColdRetryCommitsWithoutRepeatingReveal() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "NFSourceExit-\(UUID())")
        let backup = folder.appendingPathExtension("backup")
        defer { try? FileManager.default.removeItem(at: folder); try? FileManager.default.removeItem(at: backup) }
        let owner = UUID(), url = folder.appending(path: "sessions.json")
        let repository = NFLocalSessionRepository(url: url, ownerDeviceID: owner)
        let (store, container) = try makeStore(repository: repository); defer { _ = container }
        let chunk = NFSourceChunk(id: "exit-source", documentID: UUID(), documentVersion: 1,
            sourceName: "Synthetic source.txt", locator: .init(page: nil, lineStart: 1, lineEnd: 1, section: nil),
            text: "The retained private reference.", contentHash: "exit-source", ordinal: 0, language: "en")
        let sourceRequest = try NFSourceReviewExactAdapter.makeRequest(chunk: chunk, localeIdentifier: "en")
        let runtime = NFUniversalSessionRuntime(request: sourceRequest)
        runtime.selfCheckReflection = "My original recall."
        XCTAssertTrue(runtime.checkpointDraft(store: store))
        runtime.submitInline(store: store)
        XCTAssertEqual(runtime.stage, .selfCheckComparison)
        runtime.selfCheckRating = .notYet
        try FileManager.default.moveItem(at: folder, to: backup)
        try Data("blocked".utf8).write(to: folder)
        runtime.saveSelfCheck(store: store)
        XCTAssertTrue(runtime.hasPreparedCommit)
        XCTAssertTrue(store.attempts.isEmpty)
        XCTAssertEqual(runtime.exitDisposition(store: store), .unacknowledged)
        try FileManager.default.removeItem(at: folder)
        try FileManager.default.moveItem(at: backup, to: folder)
        XCTAssertEqual(runtime.prepareToClose(store: store), .pendingCommit)
        runtime.finishClosing()
        let reopened = NFLocalSessionRepository(url: url, ownerDeviceID: owner)
        let (restoredStore, restoredContainer) = try makeStore(repository: reopened); defer { _ = restoredContainer }
        let run = try XCTUnwrap(reopened.archive.sessions.first)
        let restored = NFUniversalSessionRuntime(request: try NFSourceReviewExactAdapter.resumeRequest(run, ownerDeviceID: owner))
        XCTAssertTrue(restored.checkpointDraft(store: restoredStore))
        restored.retrySaving(store: restoredStore)
        XCTAssertEqual(restored.stage, .feedback, "A prepared self-check is a commit, not another reference reveal")
        XCTAssertEqual(restored.selfCheckReflection, "My original recall.")
        XCTAssertEqual(restoredStore.attempts.count, 1)
        XCTAssertEqual(restoredStore.attempts.first?.id, run.checkpoint.attemptID)
        XCTAssertEqual(restoredStore.attempts.first?.evidenceWeight, 0)
        restored.retrySaving(store: restoredStore)
        XCTAssertEqual(restoredStore.attempts.count, 1)
    }

    func testProtectedMinimalReceiptAndOldCommittedReceiptResumeWithoutRegrading() throws {
        let (store, container) = try makeStore(); defer { _ = container }
        let runtime = try numericProtectedRuntime()
        XCTAssertTrue(runtime.exercise.assessmentProtected)
        guard case let .numeric(schema) = runtime.exercise.interaction else { return XCTFail("Expected numerical assessment fixture") }
        runtime.numericValue = "17"
        if schema.answer.unitRequired {
            runtime.numericUnit = try XCTUnwrap(schema.answer.canonicalUnit)
        }
        runtime.chooseConfidence(.certain)
        XCTAssertTrue(runtime.checkpointDraft(store: store))
        XCTAssertTrue(runtime.canSubmit, runtime.responseValidationMessage ?? "Complete numeric fixture must be submittable")
        let before = try XCTUnwrap(store.localSessions.archive.sessions.first)
        runtime.submitInline(store: store)
        XCTAssertEqual(runtime.stage, .feedback)
        let committed = try XCTUnwrap(store.attempts.first)
        let original = try NFImmutableAttemptRecordSnapshot.encoded(NFImmutableAttemptRecordSnapshot(committed))
        let feedback = try XCTUnwrap(store.localSessions.archive.sessions.first)
        let receipt = try XCTUnwrap(feedback.checkpoint.protectedCommitReceipt)
        XCTAssertNil(feedback.checkpoint.result)
        XCTAssertNil(store.localSessions.exportArchive.sessions.first?.checkpoint.protectedCommitReceipt)
        let canary = NFExerciseScoringResult(exerciseID: runtime.exercise.id,
            scoringVersion: NFExerciseScoringEngine.scoringVersion, isCorrect: true, credit: 1,
            normalizedResponse: "SECRET_CANONICAL", errorCode: "SECRET_DIAGNOSIS", expectedAnswerSummary: "SECRET_KEY",
            feedback: .init(title: "SECRET_TITLE", explanation: "SECRET_EXPLANATION", decisiveStep: "SECRET_STEP",
                strategy: "SECRET_STRATEGY", errorCode: "SECRET_ERROR", isDelayed: false))
        let safe = try XCTUnwrap(NFProtectedCommitReceipt(attemptID: receipt.attemptID,
            exercise: runtime.exercise, descriptor: runtime.assessmentDescriptor, score: canary))
        XCTAssertFalse(String(decoding: try JSONEncoder().encode(safe), as: UTF8.self).contains("SECRET"))
        var invalid = safe; invalid.schemaVersion = 999
        XCTAssertNil(invalid.verifiedScore(for: feedback.checkpoint, exercise: runtime.exercise))
        runtime.releaseWriter()
        for pending in [false, true] {
            var legacy = pending ? before : feedback
            legacy.checkpoint.protectedCommitReceipt = nil
            if pending { legacy.checkpoint.phase = .confidence; legacy.checkpoint.pendingOutcome = "answer" }
            try store.localSessions.save(legacy)
            XCTAssertTrue(store.resumeSession(legacy.id))
            let restored = NFUniversalSessionRuntime(request: try XCTUnwrap(store.activeSessionRequest))
            XCTAssertNotNil(restored.unavailableReason)
            restored.reconcileProtectedReceipt(store: store)
            XCTAssertNil(restored.unavailableReason)
            XCTAssertTrue(restored.checkpointDraft(store: store))
            restored.retrySaving(store: store)
            XCTAssertEqual(restored.stage, .feedback)
            XCTAssertEqual(store.attempts.count, 1)
            XCTAssertEqual(try NFImmutableAttemptRecordSnapshot.encoded(NFImmutableAttemptRecordSnapshot(committed)), original)
            // Match Save & close: release this presentation and clear its
            // active route before opening another saved-session boundary.
            restored.finishClosing()
            store.activeSessionRequest = nil
        }
        // A portable opaque receipt has placeholder false/zero values. Even
        // with a retained old local catalog, those are not evaluator authority.
        var opaqueCheckpoint = before
        opaqueCheckpoint.checkpoint.phase = .confidence
        opaqueCheckpoint.checkpoint.pendingOutcome = "answer"
        try store.localSessions.save(opaqueCheckpoint)
        committed.errorCode = "protected_evaluator_unavailable"
        committed.isCorrect = false; committed.deterministicCredit = 0; committed.evidenceWeight = 0
        try container.mainContext.save()
        XCTAssertTrue(store.resumeSession(opaqueCheckpoint.id))
        let unavailable = NFUniversalSessionRuntime(request: try XCTUnwrap(store.activeSessionRequest))
        unavailable.reconcileProtectedReceipt(store: store)
        XCTAssertNotNil(unavailable.unavailableReason)
        XCTAssertFalse(unavailable.checkpointDraft(store: store))
        XCTAssertNil(store.localSessions.archive.sessions.first?.checkpoint.protectedCommitReceipt)
        XCTAssertEqual(committed.errorCode, "protected_evaluator_unavailable")
    }

    func testGeneratedDiscardCannotBeResavedByDisappearanceAndPendingCommitResumesOnce() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "NFGeneratedExit-\(UUID())")
        let backup = folder.appendingPathExtension("backup")
        defer { try? FileManager.default.removeItem(at: folder); try? FileManager.default.removeItem(at: backup) }
        let repository = NFLocalSessionRepository(url: folder.appending(path: "session.json"))
        let (store, container) = try makeStore(repository: repository); defer { _ = container }
        let id = UUID()
        let request = NFAuthoringRequest(id: id, capability: .contextualize, lab: .quantitative,
            field: .general, customTopic: "Synthetic addition", learningObjective: "Add two integers",
            style: .numerical, difficulty: 0.3, count: 1, localeIdentifier: "en", seed: 347811, aiMode: .disabled)
        let question = NFAuthoredQuestion(id: "synthetic.exit.addition", lab: .quantitative, style: .numerical,
            prompt: "What is 1 + 1?", context: "Synthetic addition", choices: [], correctAnswer: "2",
            acceptedAnswers: [], explanation: "One plus one is two.", hint: "Count the two units.",
            decisiveStep: "Add the two units.", difficulty: 0.3, citationChunkIDs: [], evidenceClass: .documentPractice)
        let result = NFAuthoringResult(questions: [question], provenance: .init(requestID: id,
            generatedAt: Date(timeIntervalSince1970: 1_788_523_200), route: .deterministicFallback,
            routeReason: "Synthetic exit fixture", promptVersion: 1, modelIdentifier: "synthetic.fixture",
            sourceChunkIDs: [], sourceDocumentIDs: [], validationVersion: 1, repairCount: 0,
            cacheKey: "synthetic.exit", isFallback: true), routeCandidates: [],
            validationStatus: .init(level: .deterministicKey, sourceSupport: .notApplicable), validationNotes: [])
        let first = AIGeneratedPracticeRuntime(result: result, request: request)
        first.numericValue = "17"
        XCTAssertTrue(first.checkpoint(store: store))
        let original = try XCTUnwrap(store.generatedPracticeDraft(for: id))
        try FileManager.default.moveItem(at: folder, to: backup)
        try Data("blocked".utf8).write(to: folder)
        first.numericValue = "29"
        XCTAssertEqual(first.prepareToClose(store: store), .unacknowledged)
        XCTAssertTrue(first.recoveryText.contains("29"))
        first.finishClosing()
        try FileManager.default.removeItem(at: folder)
        try FileManager.default.moveItem(at: backup, to: folder)
        first.pause(store: store) // Same callback used by disappearance/background.
        XCTAssertEqual(store.generatedPracticeDraft(for: id)?.response, original.response)
        let pending = AIGeneratedPracticeRuntime(result: result, request: request, draft: original)
        XCTAssertTrue(pending.restoreCheckpoint(store: store)); pending.resume()
        pending.numericValue = "2"
        try FileManager.default.moveItem(at: folder, to: backup)
        try Data("blocked".utf8).write(to: folder)
        pending.submit(store: store)
        XCTAssertEqual(pending.stage, 1)
        XCTAssertTrue(store.attempts.isEmpty)
        XCTAssertEqual(pending.exitDisposition(store: store), .unacknowledged)
        try FileManager.default.removeItem(at: folder)
        try FileManager.default.moveItem(at: backup, to: folder)
        XCTAssertEqual(pending.prepareToClose(store: store), .pendingCommit)
        pending.finishClosing()
        let saved = try XCTUnwrap(store.generatedPracticeDraft(for: id))
        let restored = AIGeneratedPracticeRuntime(result: result, request: request, draft: saved)
        XCTAssertTrue(restored.restoreCheckpoint(store: store)); restored.resume()
        XCTAssertEqual(restored.stage, 2)
        XCTAssertEqual(store.attempts.count, 1)
        XCTAssertEqual(store.attempts.first?.id, saved.pendingAttemptID)
        restored.retryCommit(store: store)
        XCTAssertEqual(store.attempts.count, 1)
        XCTAssertEqual(restored.prepareToClose(store: store), .saved)
    }

    func testProtectedPreparedCommitColdReplayUsesMinimalFrozenReceiptWithoutAttempt() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "NFProtectedExit-\(UUID())")
        let backup = folder.appendingPathExtension("backup")
        defer { try? FileManager.default.removeItem(at: folder); try? FileManager.default.removeItem(at: backup) }
        let owner = UUID(), url = folder.appending(path: "session.json")
        let repository = NFLocalSessionRepository(url: url, ownerDeviceID: owner)
        let (store, container) = try makeStore(repository: repository); defer { _ = container }
        let runtime = try numericProtectedRuntime()
        guard case let .numeric(schema) = runtime.exercise.interaction else { return XCTFail("Expected numeric protected fixture") }
        runtime.numericValue = "17"
        if schema.answer.unitRequired {
            runtime.numericUnit = try XCTUnwrap(schema.answer.canonicalUnit)
        }
        runtime.chooseConfidence(.certain)
        XCTAssertTrue(runtime.checkpointDraft(store: store))
        XCTAssertTrue(runtime.canSubmit, runtime.responseValidationMessage ?? "Complete numeric fixture must be submittable")
        try FileManager.default.moveItem(at: folder, to: backup)
        try Data("blocked".utf8).write(to: folder)
        runtime.submitInline(store: store)
        XCTAssertTrue(runtime.hasPreparedCommit)
        XCTAssertEqual(runtime.exitDisposition(store: store), .unacknowledged)
        XCTAssertTrue(store.attempts.isEmpty)
        try FileManager.default.removeItem(at: folder)
        try FileManager.default.moveItem(at: backup, to: folder)
        XCTAssertEqual(runtime.prepareToClose(store: store), .pendingCommit)
        let run = try XCTUnwrap(repository.archive.sessions.first)
        let receipt = try XCTUnwrap(run.checkpoint.protectedCommitReceipt)
        XCTAssertEqual(run.checkpoint.pendingOutcome, "answer")
        XCTAssertNil(run.checkpoint.result)
        runtime.finishClosing()
        let reopened = NFLocalSessionRepository(url: url, ownerDeviceID: owner)
        let (restoredStore, restoredContainer) = try makeStore(repository: reopened); defer { _ = restoredContainer }
        XCTAssertTrue(restoredStore.resumeSession(run.id))
        let restored = NFUniversalSessionRuntime(request: try XCTUnwrap(restoredStore.activeSessionRequest))
        XCTAssertNil(restored.unavailableReason)
        XCTAssertEqual(restored.lastResult?.credit, receipt.credit)
        XCTAssertNil(restored.lastResult?.expectedAnswerSummary)
        XCTAssertNil(restored.lastResult?.normalizedResponse)
        XCTAssertTrue(restored.checkpointDraft(store: restoredStore))
        restored.retrySaving(store: restoredStore)
        XCTAssertEqual(restored.stage, .feedback)
        XCTAssertEqual(restoredStore.attempts.count, 1)
        XCTAssertEqual(restoredStore.attempts.first?.id, receipt.attemptID)
        restored.retrySaving(store: restoredStore)
        XCTAssertEqual(restoredStore.attempts.count, 1)
        restored.finishClosing()
        restoredStore.activeSessionRequest = nil
        // Recreate the durable boundary where the original attempt exists but
        // its prepared journal has not yet acknowledged feedback.
        try reopened.save(run)
        XCTAssertTrue(restoredStore.resumeSession(run.id))
        let lagged = NFUniversalSessionRuntime(request: try XCTUnwrap(restoredStore.activeSessionRequest))
        XCTAssertTrue(lagged.checkpointDraft(store: restoredStore))
        try FileManager.default.moveItem(at: folder, to: backup)
        try Data("blocked feedback write".utf8).write(to: folder)
        lagged.retrySaving(store: restoredStore)
        XCTAssertEqual(lagged.stage, .feedback)
        XCTAssertNotNil(lagged.saveError)
        XCTAssertEqual(lagged.prepareToClose(store: restoredStore), .pendingCommit,
            "A verified original receipt and exact prepared answer can safely reconcile later")
        lagged.reflectionNote = "New unsaved reflection"
        XCTAssertEqual(lagged.prepareToClose(store: restoredStore), .unacknowledged,
            "The committed answer must not hide a later unsaved learner note")
        XCTAssertTrue(lagged.recoveryText.contains("New unsaved reflection"))
        XCTAssertEqual(restoredStore.attempts.count, 1)
    }

    func testTestScopedPreferencesDoNotMutateLearnerPersistentDefaults() throws {
        let suite = try XCTUnwrap(NFAppPreferenceScope.testSuiteName)
        let scoped = NFAppPreferenceScope.defaults
        let domain = Bundle.main.bundleIdentifier ?? "com.zacrotech.NeuroForge"
        let keys = ["nf.onboarding.step", "nf.onboarding.draft", "nf.progress.section",
            NFAppLocalization.preferredLanguageDefaultsKey,
            NFShortcutAuthoringConfiguration.setupVerifiedDefaultsKey,
            NFShortcutAuthoringConfiguration.setupVersionDefaultsKey,
            NFShortcutAuthoringConfiguration.installPageVisitedDefaultsKey,
            NFShortcutAuthoringConfiguration.installPageVisitedVersionDefaultsKey]
        let original = UserDefaults.standard.persistentDomain(forName: domain) ?? [:]
        let originalScoped = scoped.persistentDomain(forName: suite)
        defer {
            if let originalScoped { scoped.setPersistentDomain(originalScoped, forName: suite) }
            else { scoped.removePersistentDomain(forName: suite) }
        }
        scoped.set(3, forKey: "nf.onboarding.step")
        scoped.set("Synthetic draft", forKey: "nf.onboarding.draft")
        scoped.set("Review", forKey: "nf.progress.section")
        NFAppLocalization.setPreferredLanguageCode("ja")
        NFShortcutAuthoringConfiguration.markSetupVerified()
        XCTAssertTrue(NFShortcutAuthoringConfiguration.isSetupVerified())
        XCTAssertEqual(scoped.string(forKey: NFAppLocalization.preferredLanguageDefaultsKey), "ja")
        NFShortcutAuthoringConfiguration.clearSetupVerification()
        let after = UserDefaults.standard.persistentDomain(forName: domain) ?? [:]
        XCTAssertEqual(NSDictionary(dictionary: original.filter { keys.contains($0.key) }),
            NSDictionary(dictionary: after.filter { keys.contains($0.key) }))
    }

    #if os(macOS)
    private final class OriginalWindowDelegate: NSObject, NSWindowDelegate {
        var closes = 0
        var resizes = 0
        var closeObserved: (() -> Void)?
        func windowShouldClose(_ sender: NSWindow) -> Bool {
            closes += 1; closeObserved?(); return false
        }
        func windowDidResize(_ notification: Notification) { resizes += 1 }
    }

    func testOverlappingWindowRegistrationsKeepOneProxyAndRestoreOriginalDelegateInEitherOrder() {
        for removeFirstToken in [true, false] {
            let window = NSWindow(contentRect: .init(x: 0, y: 0, width: 400, height: 300),
                styleMask: [.titled, .closable], backing: .buffered, defer: true)
            window.isReleasedWhenClosed = false
            let original = OriginalWindowDelegate(); window.delegate = original
            let registry = NFSessionWindowCloseRegistry()
            let first = UUID(), second = UUID()
            var prepares = 0
            registry.register(first, window: window, prepare: { prepares += 1; return false }, close: {})
            let proxy = window.delegate
            registry.register(second, window: window, prepare: { prepares += 1; return false }, close: {})
            XCTAssertTrue(window.delegate === proxy)
            window.delegate?.windowDidResize?(Notification(name: NSWindow.didResizeNotification, object: window))
            XCTAssertEqual(original.resizes, 1, "Unrelated original delegate callbacks remain forwarded.")
            registry.remove(removeFirstToken ? first : second, window: window)
            XCTAssertTrue(window.delegate === proxy)
            XCTAssertEqual(window.delegate?.windowShouldClose?(window), false)
            XCTAssertEqual(prepares, 1, "Only the still-registered presentation checks its own draft.")
            XCTAssertEqual(original.closes, 0)
            registry.remove(removeFirstToken ? second : first, window: window)
            XCTAssertTrue(window.delegate === original)
            XCTAssertEqual(window.delegate?.windowShouldClose?(window), false)
            XCTAssertEqual(original.closes, 1)
            window.delegate = nil
        }
    }

    func testNativeCloseCommandDismissesOwnedPresentationThenAsksOriginalWindowDelegate() async {
        let window = NSWindow(contentRect: .init(x: 0, y: 0, width: 400, height: 300),
            styleMask: [.titled, .closable], backing: .buffered, defer: true)
        window.isReleasedWhenClosed = false
        let original = OriginalWindowDelegate(); window.delegate = original
        let registry = NFSessionWindowCloseRegistry(), token = UUID()
        let forwarded = expectation(description: "Original delegate receives the deferred native close")
        original.closeObserved = { forwarded.fulfill() }
        var closedPresentation = false
        registry.register(token, window: window, prepare: { true }, close: {
            closedPresentation = true
            registry.remove(token, window: window)
        })
        NFSessionNativeCloseActions().closeWindow(window, registry: registry)
        XCTAssertTrue(closedPresentation)
        let result = await XCTWaiter.fulfillment(of: [forwarded], timeout: 2)
        XCTAssertEqual(result, .completed)
        XCTAssertTrue(window.delegate === original)
        XCTAssertEqual(original.closes, 1)
        window.delegate = nil
    }

    func testNativeQuitCommandKeepsEveryPresentationIfAnySaveFailsThenClosesBeforeTerminating() async {
        let registry = NFSessionCloseRegistry(), actions = NFSessionNativeCloseActions()
        let first = UUID(), second = UUID()
        var writable = false, closes = 0, terminated = false
        registry.register(first, check: { true }, close: { closes += 1; registry.remove(first) })
        registry.register(second, check: { writable }, close: { closes += 1; registry.remove(second) })
        actions.quit(registry: registry, windows: [], terminate: { terminated = true })
        XCTAssertEqual(closes, 0)
        XCTAssertFalse(terminated)
        XCTAssertTrue(registry.hasPresentations)
        writable = true
        let completed = expectation(description: "Terminate after all presentations withdraw")
        actions.quit(registry: registry, windows: [], terminate: {
            XCTAssertEqual(closes, 2)
            XCTAssertFalse(registry.hasPresentations)
            terminated = true; completed.fulfill()
        })
        let result = await XCTWaiter.fulfillment(of: [completed], timeout: 2)
        XCTAssertEqual(result, .completed)
        XCTAssertTrue(terminated)
    }

    func testNativeQuitAcknowledgesWriterAndWindowTeardownWithoutSwiftUIDisappearance() async throws {
        let (store, container) = try makeStore()
        defer { _ = container }
        let runtime = NFUniversalSessionRuntime(request: request())
        runtime.numericValue = "17"
        XCTAssertTrue(runtime.checkpointDraft(store: store))
        let window = NSWindow(contentRect: .init(x: 0, y: 0, width: 400, height: 300),
            styleMask: [.titled, .closable], backing: .buffered, defer: true)
        window.isReleasedWhenClosed = false
        let original = OriginalWindowDelegate(); window.delegate = original
        defer { window.delegate = nil }
        let registry = NFSessionCloseRegistry(), windows = NFSessionWindowCloseRegistry()
        let actions = NFSessionNativeCloseActions(), token = UUID()
        let close = {
            registry.closePresentation(token, close: { runtime.finishClosing() }) {
                windows.remove(token)
            }
        }
        registry.register(token, check: { runtime.prepareToClose(store: store).permitsClose }, close: close)
        windows.register(token, window: window, prepare: { runtime.prepareToClose(store: store).permitsClose }, close: close)
        let completed = expectation(description: "Explicit teardown completes Quit without onDisappear")
        actions.quit(registry: registry, windows: [window]) {
            XCTAssertFalse(registry.hasPresentations)
            XCTAssertTrue(windows.registeredWindows.isEmpty)
            XCTAssertTrue(window.delegate === original)
            XCTAssertFalse(runtime.ownsWriter)
            completed.fulfill()
        }
        let result = await XCTWaiter.fulfillment(of: [completed], timeout: 2)
        XCTAssertEqual(result, .completed)
        XCTAssertEqual(store.localSessions.archive.sessions.first?.checkpoint.response,
            .numeric(.init(value: "17", unit: nil)))
        XCTAssertTrue(store.attempts.isEmpty)
    }

    func testNewUnpreparedPresentationCancelsQuitAndGetsItsOwnFreshSaveDecision() async {
        let registry = NFSessionCloseRegistry(), actions = NFSessionNativeCloseActions()
        let original = UUID(), replacement = UUID()
        var replacementWritable = false, originalCloses = 0, replacementCloses = 0, terminations = 0
        registry.register(original, check: { true }, close: {
            registry.closePresentation(original, close: {
                originalCloses += 1
                registry.register(replacement, check: { replacementWritable }, close: {
                    registry.closePresentation(replacement, close: { replacementCloses += 1 })
                })
            })
        })
        actions.quit(registry: registry, windows: [], terminate: { terminations += 1 })
        XCTAssertEqual(originalCloses, 1)
        XCTAssertEqual(replacementCloses, 0)
        XCTAssertTrue(registry.hasPresentations)
        XCTAssertEqual(terminations, 0)
        actions.quit(registry: registry, windows: [], terminate: { terminations += 1 })
        XCTAssertEqual(replacementCloses, 0, "A newly opened unsaved presentation still blocks Quit.")
        XCTAssertTrue(registry.hasPresentations)
        replacementWritable = true
        let completed = expectation(description: "A fresh Quit can save the new presentation")
        actions.quit(registry: registry, windows: []) {
            terminations += 1
            completed.fulfill()
        }
        let result = await XCTWaiter.fulfillment(of: [completed], timeout: 2)
        XCTAssertEqual(result, .completed)
        XCTAssertEqual(originalCloses, 1)
        XCTAssertEqual(replacementCloses, 1)
        XCTAssertEqual(terminations, 1)
        XCTAssertFalse(registry.hasPresentations)
    }
    #endif

}

#if os(macOS)

@MainActor
final class NativeCloseKeyboardRoutingTests: XCTestCase {
    private func window() -> NSWindow {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 320, height: 240),
            styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        return window
    }
    private func key(_ text: String = "w", modifiers: NSEvent.ModifierFlags = .command,
                     window: NSWindow, repeated: Bool = false) throws -> NSEvent {
        try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: modifiers,
            timestamp: 0, windowNumber: window.windowNumber, context: nil,
            characters: text, charactersIgnoringModifiers: text, isARepeat: repeated, keyCode: 13))
    }

    func testExactCommandWUsesCurrentRegisteredSaveGuardAndRetainsFailedSave() throws {
        let target = window(), registry = NFSessionWindowCloseRegistry(), token = UUID()
        var saveCalls = 0, closeCalls = 0
        registry.register(token, window: target, prepare: { saveCalls += 1; return false }, close: { closeCalls += 1 })
        defer { registry.remove(token, window: target); target.close() }
        XCTAssertTrue(registry.routeCloseKey(try key(window: target), keyWindow: target))
        XCTAssertEqual(saveCalls, 1)
        XCTAssertEqual(closeCalls, 0)
        XCTAssertEqual(registry.registeredWindows.count, 1)
        XCTAssertTrue(registry.routeCloseKey(try key(window: target), keyWindow: target))
        XCTAssertEqual(saveCalls, 2, "A failed save never grants cached permission to close.")
    }

    func testOtherWindowsOtherModifiersAndUnregisteredPresentationKeepNativeRouting() throws {
        let root = window(), session = window(), unrelated = window()
        let registry = NFSessionWindowCloseRegistry(), token = UUID()
        var saveCalls = 0
        registry.register(token, window: root, presentationWindow: session,
            prepare: { saveCalls += 1; return false }, close: {})
        defer { registry.remove(token, window: root); session.close(); root.close(); unrelated.close() }
        XCTAssertFalse(registry.routeCloseKey(try key(window: root), keyWindow: root))
        XCTAssertFalse(registry.routeCloseKey(try key(window: unrelated), keyWindow: unrelated))
        for flags: NSEvent.ModifierFlags in [[], [.command, .shift], [.command, .option], [.command, .control]] {
            XCTAssertFalse(registry.routeCloseKey(try key(modifiers: flags, window: session), keyWindow: session))
        }
        XCTAssertFalse(registry.routeCloseKey(try key("q", window: session), keyWindow: session))
        XCTAssertFalse(registry.routeCloseKey(try key(window: session, repeated: true), keyWindow: session))
        XCTAssertEqual(saveCalls, 0)
        registry.remove(token, window: root)
        XCTAssertFalse(registry.routeCloseKey(try key(window: session), keyWindow: session))
    }

    func testAttachedCitationOrScratchpadSheetKeepsItsOwnNativeClosePath() throws {
        let session = window(), child = window(), registry = NFSessionWindowCloseRegistry(), token = UUID()
        var saveCalls = 0
        registry.register(token, window: session, prepare: { saveCalls += 1; return false }, close: {})
        session.beginSheet(child)
        defer {
            session.endSheet(child); child.orderOut(nil)
            registry.remove(token, window: session); child.close(); session.close()
        }
        XCTAssertTrue(session.attachedSheet === child)
        XCTAssertFalse(registry.routeCloseKey(try key(window: session), keyWindow: session))
        XCTAssertFalse(registry.routeCloseKey(try key(window: child), keyWindow: child))
        XCTAssertEqual(saveCalls, 0)
    }
}
#endif

@MainActor
extension ExactSessionContinuityTests {
    private enum TransitionFault: Error { case unavailable }
    private func submitProtectedNumeric(_ runtime: NFUniversalSessionRuntime, store: AppStore) throws {
        guard case let .numeric(schema) = runtime.exercise.interaction else { throw TransitionFault.unavailable }
        runtime.numericValue = "17"
        runtime.numericUnit = schema.answer.unitRequired ? try XCTUnwrap(schema.answer.canonicalUnit) : ""
        runtime.chooseConfidence(.uncertain)
        XCTAssertTrue(runtime.canSubmit, runtime.responseValidationMessage ?? "")
        runtime.submitInline(store: store)
        XCTAssertEqual(runtime.stage, .feedback); XCTAssertNil(runtime.saveError)
    }

    func testProtectedNextRealFailedWriteRetainsPriorQuestionAndReceiptUntilExactAcceptance() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "NFProtectedNext-\(UUID())")
        let live = root.appending(path: "live"), held = root.appending(path: "held")
        defer { try? FileManager.default.removeItem(at: root) }
        let url = live.appending(path: "sessions.json"), owner = UUID()
        let repo = NFLocalSessionRepository(url: url, ownerDeviceID: owner)
        let (store, container) = try makeStore(repository: repo); defer { _ = container }
        let runtime = try numericProtectedRuntime()
        XCTAssertTrue(runtime.checkpointDraft(store: store)); runtime.acknowledgePresented()
        try submitProtectedNumeric(runtime, store: store)
        let current = try XCTUnwrap(repo.archive.sessions.first?.checkpoint)
        let originalExercise = runtime.exercise
        let originalAttempt = try XCTUnwrap(store.attempts.first)
        let originalBytes = try NFImmutableAttemptRecordSnapshot.encoded(NFImmutableAttemptRecordSnapshot(originalAttempt))
        var proposed: NFLocalItemCheckpoint?
        runtime.localCheckpointWriteFailure = { checkpoint in
            guard checkpoint.slotID != current.slotID, proposed == nil else { return }
            proposed = checkpoint
            try FileManager.default.moveItem(at: live, to: held)
            try Data("blocked next publication".utf8).write(to: live)
        }
        runtime.next(store: store)
        let candidate = try XCTUnwrap(proposed)
        XCTAssertEqual(runtime.stage, .feedback); XCTAssertEqual(runtime.exercise, originalExercise)
        XCTAssertEqual(runtime.index, current.index); XCTAssertEqual(runtime.numericValue, "17")
        XCTAssertEqual(repo.archive.sessions.first?.checkpoint.slotID, current.slotID)
        XCTAssertNotNil(runtime.saveError)
        XCTAssertNil(candidate.exercise, "Protected material stays out of generic snapshots")
        XCTAssertNil(candidate.result); XCTAssertNil(candidate.protectedCommitReceipt)
        XCTAssertNotEqual(candidate.attemptID, current.attemptID)
        XCTAssertEqual(store.attempts.count, 1)
        try FileManager.default.removeItem(at: live); try FileManager.default.moveItem(at: held, to: live)
        runtime.localCheckpointWriteFailure = nil
        runtime.next(store: store)
        XCTAssertEqual(runtime.stage, .item); XCTAssertNil(runtime.saveError)
        let accepted = try XCTUnwrap(repo.archive.sessions.first?.checkpoint)
        XCTAssertEqual(accepted.descriptor, candidate.descriptor)
        XCTAssertNotEqual(accepted.slotID, current.slotID)
        XCTAssertEqual(runtime.assessmentDescriptor, accepted.descriptor)
        XCTAssertEqual(try NFImmutableAttemptRecordSnapshot.encoded(NFImmutableAttemptRecordSnapshot(originalAttempt)), originalBytes)
        runtime.finishClosing()
        let reopened = NFLocalSessionRepository(url: url, ownerDeviceID: owner)
        let coldStore = AppStore(context: container.mainContext, localSessionRepository: reopened)
        XCTAssertTrue(coldStore.resumeSession(runtime.sessionID))
        let cold = NFUniversalSessionRuntime(request: try XCTUnwrap(coldStore.activeSessionRequest))
        XCTAssertNil(cold.unavailableReason); XCTAssertEqual(cold.assessmentDescriptor, accepted.descriptor)
        XCTAssertEqual(cold.exercise, runtime.exercise); XCTAssertTrue(cold.isPaused)
        XCTAssertEqual(coldStore.attempts.count, 1)
    }

    func testAssessmentPreviewDoesNotPublishProtectedQuestionWhenNextSnapshotFails() throws {
        let (store, container) = try makeStore(); defer { _ = container }
        let request = try XCTUnwrap((UInt64(300)..<UInt64(500)).lazy.map { seed in
            SessionRequest(lab: .mentalMath, source: .baseline, seed: seed, localeIdentifier: "en",
                evidenceClass: .assessmentHoldout, assessmentBlock: .numericalFluency, isTimed: false)
        }.first { request in
            let candidate = NFUniversalSessionRuntime(request: request)
            if case .numeric = candidate.exercise.interaction { return candidate.isAssessmentPractice }
            return false
        })
        let runtime = NFUniversalSessionRuntime(request: request)
        XCTAssertTrue(runtime.checkpointDraft(store: store)); runtime.acknowledgePresented()
        try submitProtectedNumeric(runtime, store: store)
        let original = runtime.exercise, slot = try XCTUnwrap(store.localSessions.archive.sessions.first?.checkpoint.slotID)
        runtime.localCheckpointWriteFailure = { if $0.slotID != slot { throw TransitionFault.unavailable } }
        runtime.next(store: store)
        XCTAssertTrue(runtime.isAssessmentPractice); XCTAssertEqual(runtime.stage, .feedback)
        XCTAssertEqual(runtime.exercise, original); XCTAssertTrue(runtime.correctness.isEmpty)
        XCTAssertEqual(store.attempts.count, 1); XCTAssertEqual(store.attempts.first?.evidenceWeight, 0)
        runtime.localCheckpointWriteFailure = nil; runtime.next(store: store)
        XCTAssertEqual(runtime.stage, .item); XCTAssertTrue(runtime.exercise.assessmentProtected)
        XCTAssertFalse(runtime.isAssessmentPractice); XCTAssertTrue(runtime.correctness.isEmpty)
        XCTAssertNil(store.localSessions.archive.sessions.first?.checkpoint.exercise)
    }

    func testProtectedSkipFailureColdReplayKeepsOneUnscoredReceiptAndSelectionExposure() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "NFProtectedSkip-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appending(path: "sessions.json"), owner = UUID()
        let repo = NFLocalSessionRepository(url: url, ownerDeviceID: owner)
        let (store, container) = try makeStore(repository: repo); defer { _ = container }
        var clock: TimeInterval = 0
        let runtime = NFUniversalSessionRuntime(request: try numericProtectedRuntime().request, monotonicNow: { clock })
        XCTAssertTrue(runtime.checkpointDraft(store: store)); runtime.acknowledgePresented()
        let original = try XCTUnwrap(repo.archive.sessions.first?.checkpoint)
        clock = 17
        runtime.localCheckpointWriteFailure = { if $0.slotID != original.slotID { throw TransitionFault.unavailable } }
        runtime.skip(store: store)
        XCTAssertEqual(runtime.stage, .item); XCTAssertEqual(runtime.assessmentDescriptor, original.descriptor)
        XCTAssertTrue(runtime.hasSavedSkipAwaitingAdvance); XCTAssertFalse(runtime.canEditDraft)
        XCTAssertEqual(runtime.activeElapsed(), 17, accuracy: 0.001)
        let pending = try XCTUnwrap(repo.archive.sessions.first?.checkpoint)
        XCTAssertEqual(pending.pendingOutcome, "skip"); XCTAssertEqual(pending.slotID, original.slotID)
        XCTAssertEqual(pending.assessmentState?.selectedItemIDs, Set([try XCTUnwrap(original.descriptor?.id)]))
        XCTAssertTrue(pending.credits.isEmpty); XCTAssertEqual(pending.cumulativeActiveDuration, 17)
        let savedAttempt = try XCTUnwrap(store.attempts.first)
        let immutable = try NFImmutableAttemptRecordSnapshot.encoded(NFImmutableAttemptRecordSnapshot(savedAttempt))
        XCTAssertEqual(savedAttempt.id, original.attemptID); XCTAssertEqual(savedAttempt.evidenceWeight, 0)
        runtime.finishClosing()
        let reopened = NFLocalSessionRepository(url: url, ownerDeviceID: owner)
        let coldStore = AppStore(context: container.mainContext, localSessionRepository: reopened)
        XCTAssertTrue(coldStore.resumeSession(runtime.sessionID))
        let cold = NFUniversalSessionRuntime(request: try XCTUnwrap(coldStore.activeSessionRequest))
        XCTAssertNil(cold.unavailableReason); XCTAssertTrue(cold.hasSavedSkipAwaitingAdvance)
        XCTAssertTrue(cold.checkpointDraft(store: coldStore)); cold.reconcilePendingSkip(store: coldStore)
        XCTAssertNil(cold.saveError); XCTAssertFalse(cold.hasSavedSkipAwaitingAdvance)
        XCTAssertNotEqual(cold.assessmentDescriptor, original.descriptor); XCTAssertEqual(cold.stage, .item)
        XCTAssertTrue(cold.correctness.isEmpty); XCTAssertEqual(coldStore.attempts.count, 1)
        XCTAssertEqual(try NFImmutableAttemptRecordSnapshot.encoded(NFImmutableAttemptRecordSnapshot(savedAttempt)), immutable)
        XCTAssertEqual(reopened.archive.sessions.first?.checkpoint.cumulativeActiveDuration, 17)
    }

    func testProtectedSittingStopAndRestartPersistBeforeSummaryResetOrNextQuestion() throws {
        let (store, container) = try makeStore(); defer { _ = container }
        var clock: TimeInterval = 0
        let runtime = NFUniversalSessionRuntime(request: try numericProtectedRuntime().request, monotonicNow: { clock })
        XCTAssertTrue(runtime.checkpointDraft(store: store)); runtime.acknowledgePresented()
        clock = 10; try submitProtectedNumeric(runtime, store: store)
        let original = runtime.exercise
        clock = 400
        runtime.localCheckpointWriteFailure = { if $0.phase == .summary { throw TransitionFault.unavailable } }
        runtime.next(store: store)
        XCTAssertEqual(runtime.stage, .feedback); XCTAssertFalse(runtime.awaitingNextSitting)
        XCTAssertEqual(runtime.exercise, original); XCTAssertEqual(runtime.sittingOrdinal, 0)
        runtime.localCheckpointWriteFailure = nil; runtime.next(store: store)
        XCTAssertEqual(runtime.stage, .summary); XCTAssertTrue(runtime.awaitingNextSitting)
        let summary = try XCTUnwrap(store.localSessions.archive.sessions.first?.checkpoint)
        XCTAssertEqual(summary.assessmentStopReason, .maximumActiveDurationReached)
        XCTAssertEqual(store.localSessions.archive.sessions.first?.status, .suspended)
        runtime.localCheckpointWriteFailure = { if $0.slotID != summary.slotID { throw TransitionFault.unavailable } }
        runtime.continueProtectedSitting(store: store)
        XCTAssertEqual(runtime.stage, .summary); XCTAssertTrue(runtime.awaitingNextSitting)
        XCTAssertEqual(runtime.sittingOrdinal, 0); XCTAssertEqual(runtime.exercise, original)
        XCTAssertEqual(store.localSessions.archive.sessions.first?.checkpoint.sittingActiveDuration, summary.sittingActiveDuration)
        runtime.localCheckpointWriteFailure = nil; runtime.continueProtectedSitting(store: store)
        XCTAssertEqual(runtime.stage, .item); XCTAssertFalse(runtime.awaitingNextSitting)
        XCTAssertEqual(runtime.sittingOrdinal, 1); XCTAssertNotEqual(runtime.exercise, original)
        XCTAssertEqual(store.localSessions.archive.sessions.first?.checkpoint.sittingActiveDuration, 0)
        XCTAssertEqual(store.attempts.count, 1)
    }

    func testEndFromUnscoredConfidenceRetainsDraftAndDoesNotPublishFailedSummary() throws {
        let (store, container) = try makeStore(); defer { _ = container }
        let runtime = NFUniversalSessionRuntime(request: request())
        XCTAssertTrue(runtime.checkpointDraft(store: store)); runtime.acknowledgePresented()
        runtime.numericValue = "29"; runtime.scratchpad = "My unfinished calculation"
        runtime.submitResponse()
        XCTAssertEqual(runtime.stage, .confidence); XCTAssertFalse(runtime.hasPreparedCommit)
        runtime.localCheckpointWriteFailure = { if $0.phase == .summary { throw TransitionFault.unavailable } }
        runtime.endSession(store: store)
        XCTAssertEqual(runtime.stage, .confidence); XCTAssertFalse(runtime.endedEarly)
        XCTAssertEqual(runtime.numericValue, "29"); XCTAssertTrue(store.attempts.isEmpty)
        runtime.localCheckpointWriteFailure = nil; runtime.endSession(store: store)
        XCTAssertEqual(runtime.stage, .summary); XCTAssertTrue(runtime.endedEarly)
        XCTAssertTrue(store.attempts.isEmpty)
        let terminal = try XCTUnwrap(store.localSessions.archive.sessions.first)
        XCTAssertEqual(terminal.status, .endedEarly); XCTAssertNil(terminal.checkpoint.committedAttemptID)
        XCTAssertEqual(terminal.checkpoint.response, .numeric(.init(value: "29", unit: nil)))
        XCTAssertEqual(terminal.checkpoint.scratchpad, "My unfinished calculation")
        runtime.endSession(store: store)
        XCTAssertEqual(try NFImmutableAttemptRecordSnapshot.encoded(store.localSessions.archive.sessions.first), try NFImmutableAttemptRecordSnapshot.encoded(terminal))
    }

    func testEndingAnAcknowledgedProtectedSkipDoesNotSelectOrConsumeAnotherQuestion() throws {
        let (store, container) = try makeStore(); defer { _ = container }
        let runtime = try numericProtectedRuntime()
        XCTAssertTrue(runtime.checkpointDraft(store: store)); runtime.acknowledgePresented()
        let slot = try XCTUnwrap(store.localSessions.archive.sessions.first?.checkpoint.slotID)
        runtime.localCheckpointWriteFailure = { if $0.slotID != slot { throw TransitionFault.unavailable } }
        runtime.skip(store: store)
        XCTAssertTrue(runtime.hasSavedSkipAwaitingAdvance)
        let attempt = try XCTUnwrap(store.attempts.first)
        let immutable = try NFImmutableAttemptRecordSnapshot.encoded(NFImmutableAttemptRecordSnapshot(attempt))
        runtime.endSession(store: store)
        XCTAssertEqual(runtime.stage, .summary); XCTAssertTrue(runtime.endedEarly)
        XCTAssertFalse(runtime.hasSavedSkipAwaitingAdvance)
        let terminal = try XCTUnwrap(store.localSessions.archive.sessions.first?.checkpoint)
        XCTAssertEqual(terminal.slotID, slot); XCTAssertEqual(terminal.assessmentState?.selectedItemIDs.count, 1)
        XCTAssertEqual(terminal.assessmentEvents.count, 1); XCTAssertTrue(terminal.credits.isEmpty)
        XCTAssertEqual(store.attempts.count, 1)
        XCTAssertEqual(try NFImmutableAttemptRecordSnapshot.encoded(NFImmutableAttemptRecordSnapshot(attempt)), immutable)
    }

    func testAcceptedProtectedNextRemainsPublishedWhenOnlyLegacyProjectionFails() throws {
        let (store, container) = try makeStore(); defer { _ = container }
        let runtime = try numericProtectedRuntime()
        XCTAssertTrue(runtime.checkpointDraft(store: store)); runtime.acknowledgePresented()
        try submitProtectedNumeric(runtime, store: store)
        let old = runtime.exercise
        var projections = 0
        runtime.legacyCheckpointWriteFailure = {
            projections += 1
            if projections > 1 { throw TransitionFault.unavailable }
        }
        runtime.next(store: store)
        XCTAssertEqual(runtime.stage, .item); XCTAssertNotEqual(runtime.exercise, old)
        XCTAssertNotNil(runtime.saveError)
        let accepted = try XCTUnwrap(store.localSessions.archive.sessions.first?.checkpoint)
        XCTAssertEqual(accepted.descriptor, runtime.assessmentDescriptor)
        XCTAssertNil(accepted.exercise); XCTAssertNil(accepted.result)
        XCTAssertEqual(store.attempts.count, 1)
        runtime.legacyCheckpointWriteFailure = nil; runtime.retrySaving(store: store)
        XCTAssertNil(runtime.saveError); XCTAssertEqual(runtime.assessmentDescriptor, accepted.descriptor)
        XCTAssertEqual(store.attempts.count, 1)
    }
    func testEndingPreparedProtectedAnswerCannotAbandonIntentAndCommitsOnceBeforeSummary() throws {
        let (store, container) = try makeStore(); defer { _ = container }
        let runtime = try numericProtectedRuntime()
        XCTAssertTrue(runtime.checkpointDraft(store: store)); runtime.acknowledgePresented()
        guard case let .numeric(schema) = runtime.exercise.interaction else { return XCTFail("Numeric fixture") }
        runtime.numericValue = "17"; runtime.numericUnit = schema.answer.unitRequired ? try XCTUnwrap(schema.answer.canonicalUnit) : ""
        runtime.chooseConfidence(.uncertain)
        runtime.legacyCheckpointWriteFailure = { throw TransitionFault.unavailable }
        runtime.submitInline(store: store)
        XCTAssertTrue(runtime.hasPreparedCommit); XCTAssertTrue(store.attempts.isEmpty)
        let intent = try XCTUnwrap(store.localSessions.archive.sessions.first?.checkpoint)
        XCTAssertEqual(intent.pendingOutcome, "answer"); XCTAssertNotNil(intent.protectedCommitReceipt)
        runtime.endSession(store: store)
        XCTAssertEqual(runtime.stage, .confidence); XCTAssertFalse(runtime.endedEarly)
        XCTAssertTrue(runtime.hasPreparedCommit); XCTAssertTrue(store.attempts.isEmpty)
        runtime.legacyCheckpointWriteFailure = nil; runtime.endSession(store: store)
        XCTAssertEqual(runtime.stage, .summary); XCTAssertTrue(runtime.endedEarly)
        XCTAssertFalse(runtime.hasPreparedCommit); XCTAssertEqual(store.attempts.count, 1)
        XCTAssertEqual(store.attempts.first?.id, intent.attemptID)
        let terminal = try XCTUnwrap(store.localSessions.archive.sessions.first?.checkpoint)
        XCTAssertEqual(terminal.protectedCommitReceipt, intent.protectedCommitReceipt)
        XCTAssertNil(terminal.exercise); XCTAssertNil(terminal.result)
    }

}

extension ExactSessionContinuityTests {
    func testSessionCommandCannotBeRevivedByReacquiringTheSameRuntimeWriter() throws {
        let (store, container) = try makeStore(); _ = container
        let runtime = NFUniversalSessionRuntime(request: request())
        XCTAssertTrue(runtime.checkpointDraft(store: store))
        let old = try runtime.sessionWriterCommand(), other = UUID()
        runtime.releaseWriter()
        XCTAssertTrue(store.localSessions.claimWriter(other, sessionID: runtime.sessionID, checkpoint: { true }))
        runtime.takeOver(store: store)
        XCTAssertTrue(runtime.ownsWriter)
        XCTAssertNotEqual(old, try runtime.sessionWriterCommand())
        let original = try XCTUnwrap(store.localSessions.archive.sessions.first)
        var stale = original; stale.revision += 1; stale.checkpoint.scratchpad = "stale old generation"
        XCTAssertThrowsError(try store.localSessions.saveSession(stale, command: old, expectedRevision: original.revision))
        XCTAssertEqual(try NFImmutableAttemptRecordSnapshot.encoded(XCTUnwrap(store.localSessions.archive.sessions.first)),
            try NFImmutableAttemptRecordSnapshot.encoded(original))
        runtime.scratchpad = "explicitly reacquired writer"
        XCTAssertTrue(runtime.checkpointDraft(store: store))
        XCTAssertEqual(store.localSessions.archive.sessions.first?.checkpoint.scratchpad, runtime.scratchpad)
    }

    func testSameWriterCannotOverwriteAnUnacknowledgedNewerEnvelopeRevision() throws {
        let (store, container) = try makeStore(); _ = container
        let runtime = NFUniversalSessionRuntime(request: request())
        XCTAssertTrue(runtime.checkpointDraft(store: store))
        let old = try XCTUnwrap(store.localSessions.archive.sessions.first)
        var newer = old; newer.revision += 1; newer.checkpoint.scratchpad = "newer accepted state"
        try store.localSessions.saveSession(newer, command: runtime.sessionWriterCommand(), expectedRevision: old.revision)
        runtime.scratchpad = "old editor draft"
        XCTAssertFalse(runtime.checkpointDraft(store: store))
        XCTAssertEqual(try NFImmutableAttemptRecordSnapshot.encoded(XCTUnwrap(store.localSessions.archive.sessions.first)),
            try NFImmutableAttemptRecordSnapshot.encoded(newer))
        XCTAssertEqual(runtime.scratchpad, "old editor draft")
        runtime.takeOver(store: store)
        XCTAssertEqual(runtime.scratchpad, "newer accepted state")
        XCTAssertTrue(runtime.checkpointDraft(store: store))
    }

    func testCheckpointCommandKeepsItsGenerationAcrossTheRealPrewriteBoundary() throws {
        let (store, container) = try makeStore(); _ = container
        let runtime = NFUniversalSessionRuntime(request: request())
        XCTAssertTrue(runtime.checkpointDraft(store: store))
        let original = try XCTUnwrap(store.localSessions.archive.sessions.first), other = UUID()
        runtime.numericValue = "91"
        runtime.localCheckpointWriteFailure = { _ in
            runtime.localCheckpointWriteFailure = nil
            runtime.releaseWriter()
            XCTAssertTrue(store.localSessions.claimWriter(other, sessionID: runtime.sessionID, checkpoint: { true }))
        }
        XCTAssertFalse(runtime.checkpointDraft(store: store))
        XCTAssertEqual(try NFImmutableAttemptRecordSnapshot.encoded(XCTUnwrap(store.localSessions.archive.sessions.first)),
            try NFImmutableAttemptRecordSnapshot.encoded(original))
        XCTAssertEqual(runtime.numericValue, "91")
        XCTAssertFalse(runtime.ownsWriter)
        store.localSessions.releaseWriter(other)
    }

    func testReceiptWriteThenWriterABADoesNotPublishOldFeedbackAndRetryUsesOneReceipt() throws {
        let (store, container) = try makeStore(); _ = container
        let runtime = NFUniversalSessionRuntime(request: request())
        XCTAssertTrue(runtime.checkpointDraft(store: store)); runtime.numericValue = "0"
        let other = UUID(), old = try runtime.sessionWriterCommand()
        runtime.receiptWriteAcknowledged = {
            runtime.receiptWriteAcknowledged = nil
            XCTAssertEqual(store.attempts.count, 1, "The actual immutable attempt must already be durable")
            runtime.releaseWriter()
            XCTAssertTrue(store.localSessions.claimWriter(other, sessionID: runtime.sessionID, checkpoint: { true }))
            runtime.takeOver(store: store)
        }
        runtime.submitInline(store: store)
        XCTAssertEqual(store.attempts.count, 1)
        XCTAssertNotEqual(runtime.stage, .feedback)
        XCTAssertTrue(runtime.hasPreparedCommit)
        XCTAssertNotEqual(old, try runtime.sessionWriterCommand())
        XCTAssertEqual(store.localSessions.archive.sessions.first?.checkpoint.phase, .confidence)
        let record = try XCTUnwrap(store.attempts.first)
        let original = try NFImmutableAttemptRecordSnapshot.encoded(NFImmutableAttemptRecordSnapshot(record))
        runtime.retrySaving(store: store)
        XCTAssertEqual(runtime.stage, .feedback)
        XCTAssertEqual(store.attempts.count, 1)
        XCTAssertEqual(try NFImmutableAttemptRecordSnapshot.encoded(NFImmutableAttemptRecordSnapshot(record)), original)
        XCTAssertNil(runtime.unavailableReason, "Ownership loss must not be recorded as a conflicting answer")
    }

    func testSourceSelfCheckReceiptKeepsOriginalReferenceAndNeutralEvidenceAfterWriterLoss() throws {
        let (store, container) = try makeStore(); _ = container
        let chunk = NFSourceChunk(id: "writer-source", documentID: UUID(), documentVersion: 1,
            sourceName: "Private writer fixture.txt", locator: .init(page: nil, lineStart: 1, lineEnd: 1, section: nil),
            text: "The exact private reference.", contentHash: "writer-source", ordinal: 0, language: "en")
        let source = try NFSourceReviewExactAdapter.makeRequest(chunk: chunk, localeIdentifier: "en")
        let runtime = NFUniversalSessionRuntime(request: source)
        XCTAssertTrue(runtime.checkpointDraft(store: store)); runtime.selfCheckReflection = "My original recall."
        runtime.submitInline(store: store); XCTAssertEqual(runtime.stage, .selfCheckComparison)
        runtime.selfCheckRating = .partiallyMatched
        let other = UUID()
        runtime.receiptWriteAcknowledged = {
            runtime.receiptWriteAcknowledged = nil
            runtime.releaseWriter()
            XCTAssertTrue(store.localSessions.claimWriter(other, sessionID: runtime.sessionID, checkpoint: { true }))
        }
        runtime.saveSelfCheck(store: store)
        XCTAssertEqual(store.attempts.count, 1); XCTAssertNotEqual(runtime.stage, .feedback)
        XCTAssertEqual(store.attempts.first?.evidenceWeight, 0)
        XCTAssertEqual(store.localSessions.archive.sessions.first?.checkpoint.phase, .confidence)
        runtime.takeOver(store: store); runtime.retrySaving(store: store)
        XCTAssertEqual(runtime.stage, .feedback); XCTAssertEqual(store.attempts.count, 1)
        XCTAssertEqual(runtime.selfCheckReflection, "My original recall.")
        XCTAssertEqual(runtime.exercise, source.localCheckpoint?.exercise)
    }

    func testProtectedReceiptBeforeOwnershipLossRemainsMinimalAndReplaysWithoutAnotherScore() throws {
        let (store, container) = try makeStore(); _ = container
        let runtime = try numericProtectedRuntime()
        XCTAssertTrue(runtime.checkpointDraft(store: store))
        guard case let .numeric(schema) = runtime.exercise.interaction else { return XCTFail("Expected authentic numeric schema") }
        runtime.numericValue = "17"; runtime.numericUnit = schema.answer.unitRequired ? try XCTUnwrap(schema.answer.canonicalUnit) : ""
        runtime.chooseConfidence(.certain)
        XCTAssertTrue(runtime.canSubmit, runtime.responseValidationMessage ?? "Complete authentic response")
        runtime.submitResponse()
        let other = UUID()
        runtime.receiptWriteAcknowledged = {
            runtime.receiptWriteAcknowledged = nil
            runtime.releaseWriter()
            XCTAssertTrue(store.localSessions.claimWriter(other, sessionID: runtime.sessionID, checkpoint: { true }))
        }
        runtime.commit(confidence: .certain, store: store)
        XCTAssertEqual(store.attempts.count, 1); XCTAssertNotEqual(runtime.stage, .feedback)
        let checkpoint = try XCTUnwrap(store.localSessions.archive.sessions.first?.checkpoint)
        XCTAssertNil(checkpoint.exercise); XCTAssertNil(checkpoint.result); XCTAssertNotNil(checkpoint.protectedCommitReceipt)
        let id = try XCTUnwrap(store.attempts.first?.id)
        runtime.takeOver(store: store); runtime.retrySaving(store: store)
        XCTAssertEqual(runtime.stage, .feedback); XCTAssertEqual(store.attempts.map(\.id), [id])
        XCTAssertNil(store.localSessions.archive.sessions.first?.checkpoint.result)
    }

    func testMatchingReceiptCallbackLosingAuthorityCannotPublishScoredOrUnscoredFeedback() {
        let exercise = NFUniversalSessionRuntime(request: request()).exercise
        let response = NFExerciseResponse.numeric(.init(value: "0", unit: nil))
        let coordinator = NFSessionLifecycleCoordinator()
        var owns = true, acknowledged = false
        coordinator.commit(exercise: exercise, response: response, attemptID: UUID(), confidence: nil,
            recoveredIntent: nil, canMutate: { owns }, receipt: { _ in owns = false; return .matching },
            allowsNewCommit: { true }, publishPrepared: { _ in XCTFail("Stale receipt cannot prepare") },
            persistPrepared: { XCTFail("Stale receipt cannot write"); return false }, saveAttempt: { _ in XCTFail("No second attempt") },
            acknowledge: { _ in acknowledged = true }, persistFeedback: { XCTFail("No stale feedback checkpoint"); return false },
            nonScorable: { _ in XCTFail("Expected supported numeric fixture") }, conflictingReceipt: { _ in XCTFail("Ownership is not conflict") }, failedSave: {})
        XCTAssertFalse(acknowledged); XCTAssertEqual(coordinator.phase, .item)
        owns = true
        coordinator.commitUnscored(canMutate: { owns }, receipt: { owns = false; return .matching },
            prepare: { XCTFail("No stale prepare") }, persistPrepared: { false }, save: { XCTFail("No duplicate activity") },
            acknowledge: { acknowledged = true }, persistFeedback: { false }, failed: {})
        XCTAssertFalse(acknowledged); XCTAssertEqual(coordinator.phase, .item)
    }
}

extension ExactSessionContinuityTests {
    func testColdMaximumRevisionRetainsOriginalArchiveAndRefusesCheckpointWithoutWrapping() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "NFRevision-\(UUID())")
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appending(path: "sessions.json"), owner = UUID()
        let repository = NFLocalSessionRepository(url: url, ownerDeviceID: owner)
        let (store, container) = try makeStore(repository: repository); _ = container
        let runtime = NFUniversalSessionRuntime(request: request())
        XCTAssertTrue(runtime.checkpointDraft(store: store)); runtime.releaseWriter()
        var maximal = try XCTUnwrap(repository.archive.sessions.first)
        maximal.revision = Int.max
        try repository.save(maximal) // Authenticated imported/maintenance envelope, outside live writer API.
        let originalBytes = try Data(contentsOf: url)
        let reloaded = NFLocalSessionRepository(url: url, ownerDeviceID: owner)
        XCTAssertNil(reloaded.loadError)
        let (coldStore, coldContainer) = try makeStore(repository: reloaded); _ = coldContainer
        XCTAssertTrue(coldStore.resumeSession(maximal.id))
        let cold = NFUniversalSessionRuntime(request: try XCTUnwrap(coldStore.activeSessionRequest))
        XCTAssertFalse(cold.checkpointDraft(store: coldStore))
        XCTAssertNotNil(cold.saveError)
        XCTAssertEqual(reloaded.archive.sessions.first?.revision, Int.max)
        XCTAssertEqual(try Data(contentsOf: url), originalBytes)
        XCTAssertThrowsError(try NFSessionWriterRevision.next(after: -1))
        XCTAssertThrowsError(try NFSessionWriterRevision.next(after: Int.max))
    }
}

/// Fixtures hold the real worker at a named boundary. No learner data is sent
/// through the hook and the MainActor never waits on the fixture semaphore.
final class NFAsyncArchiveWriteProbe: @unchecked Sendable {
    private let lock = NSLock()
    private let releaseSignal = DispatchSemaphore(value: 0)
    private let heldStage: NFLocalArchiveWriteStage
    private var isHeld = false
    private var timedOut = false
    private var observations: [Bool] = []
    init(_ stage: NFLocalArchiveWriteStage) { heldStage = stage }
    func observe(_ stage: NFLocalArchiveWriteStage, _ main: Bool) {
        let hold = lock.withLock {
            observations.append(main)
            if stage == heldStage, !isHeld { isHeld = true; return true }
            return false
        }
        if hold, releaseSignal.wait(timeout: .now() + 15) != .success { lock.withLock { timedOut = true } }
    }
    func release() { releaseSignal.signal() }
    func waitUntilHeld() async -> Bool {
        for _ in 0..<500 {
            if lock.withLock({ isHeld }) { return true }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return false
    }
    var stayedOffMain: Bool { lock.withLock { !observations.isEmpty && !observations.contains(true) && !timedOut } }
}

extension ExactSessionContinuityTests {
    func testAsyncLargeArchiveKeepsMainResponsiveAndFencesRawAndContextFirstWrites() async throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "NFAsync-Large-\(UUID())")
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appending(path: "sessions.json")
        let repository = NFLocalSessionRepository(url: url)
        // A retained unknown private payload remains opaque and byte-identical.
        let opaque = Data(repeating: 0x20, count: 6 * 1_024 * 1_024)
        let opaqueID = UUID()
        try repository.savePrivateStudyRun(id: opaqueID, generationID: opaqueID, payload: opaque)
        let (store, container) = try makeStore(repository: repository); _ = container
        let runtime = NFUniversalSessionRuntime(request: request())
        XCTAssertTrue(runtime.checkpointDraft(store: store)); runtime.acknowledgePresented()
        runtime.numericValue = "12"
        let probe = NFAsyncArchiveWriteProbe(.encoding); defer { probe.release() }
        repository.archiveWriteObserver = { probe.observe($0, $1) }
        let saving = Task { await runtime.checkpointDraftAsync(store: store) }
        let held = await probe.waitUntilHeld(); XCTAssertTrue(held)
        XCTAssertTrue(repository.hasPendingArchiveWrite)
        XCTAssertTrue(runtime.canEditDraft, "Typing stays available until an explicit action is queued")
        var callbackInvoked = false
        XCTAssertFalse(repository.takeOver(UUID(), sessionID: runtime.sessionID, checkpoint: { callbackInvoked = true; return true }))
        XCTAssertFalse(callbackInvoked)
        let command = try runtime.sessionWriterCommand()
        XCTAssertThrowsError(try store.withSessionCommand(command, sessionID: runtime.sessionID) { callbackInvoked = true })
        XCTAssertFalse(callbackInvoked, "The busy check precedes any core model mutation")
        XCTAssertThrowsError(try store.deleteAllLocalData())
        XCTAssertThrowsError(try repository.removePrivateStudyRun(id: opaqueID))
        runtime.numericValue = "123"
        XCTAssertEqual(runtime.numericValue, "123", "MainActor edits run while the actor is held")
        probe.release()
        let saved = await saving.value; XCTAssertTrue(saved)
        XCTAssertTrue(probe.stayedOffMain)
        XCTAssertEqual(repository.archive.sessions.first?.checkpoint.response, .numeric(.init(value: "12", unit: nil)))
        XCTAssertEqual(repository.archive.privateStudyRuns?.first(where: { $0.id == opaqueID })?.payload, opaque)
        XCTAssertEqual(runtime.numericValue, "123")
        XCTAssertEqual(runtime.exitDisposition(store: store), .unacknowledged)
        repository.archiveWriteObserver = nil
        XCTAssertTrue(runtime.prepareToClose(store: store).permitsClose)
        let cold = NFLocalSessionRepository(url: url, ownerDeviceID: repository.ownerDeviceID)
        XCTAssertNil(cold.loadError)
        XCTAssertEqual(cold.archive.sessions.first?.checkpoint.response, .numeric(.init(value: "123", unit: nil)))
    }

    func testAsyncQueuedSubmitCapturesOneAnswerAndExcludesStorageWaitFromAnswerTime() async throws {
        let repository = NFLocalSessionRepository()
        let (store, container) = try makeStore(repository: repository); _ = container
        var now: TimeInterval = 100
        let runtime = NFUniversalSessionRuntime(request: request(), monotonicNow: { now })
        XCTAssertTrue(runtime.checkpointDraft(store: store)); runtime.acknowledgePresented()
        now = 107; runtime.numericValue = "12"
        let probe = NFAsyncArchiveWriteProbe(.encoding); defer { probe.release() }
        repository.archiveWriteObserver = { probe.observe($0, $1) }
        let saving = Task { await runtime.checkpointDraftAsync(store: store) }
        let held = await probe.waitUntilHeld(); XCTAssertTrue(held)
        runtime.submitInline(store: store)
        XCTAssertTrue(runtime.draftSaveGate.hasQueuedAction)
        XCTAssertFalse(runtime.canEditDraft); XCTAssertTrue(store.attempts.isEmpty)
        XCTAssertEqual(runtime.stage, .item)
        now = 150
        probe.release()
        _ = await saving.value
        XCTAssertEqual(runtime.stage, .feedback)
        let attempt = try XCTUnwrap(store.attempts.first)
        XCTAssertEqual(store.attempts.count, 1)
        XCTAssertEqual(attempt.activeDurationSeconds, 7, accuracy: 0.001)
        let response = try JSONDecoder().decode(NFExerciseResponse.self, from: Data(attempt.response.utf8))
        XCTAssertEqual(response, .numeric(.init(value: "12", unit: nil)))
        runtime.retrySaving(store: store)
        XCTAssertEqual(store.attempts.count, 1)
    }

    func testAsyncLateResponseAfterQueuedSubmitIsRetainedAndRequiresAnotherExplicitAction() async throws {
        let repository = NFLocalSessionRepository()
        let (store, container) = try makeStore(repository: repository); _ = container
        let runtime = NFUniversalSessionRuntime(request: request())
        XCTAssertTrue(runtime.checkpointDraft(store: store)); runtime.acknowledgePresented()
        runtime.numericValue = "12"
        let probe = NFAsyncArchiveWriteProbe(.encoding); defer { probe.release() }
        repository.archiveWriteObserver = { probe.observe($0, $1) }
        let saving = Task { await runtime.checkpointDraftAsync(store: store) }
        let held = await probe.waitUntilHeld(); XCTAssertTrue(held)
        runtime.submitInline(store: store)
        // Model one already-delivered native edit callback arriving before the
        // disabled view update. Its value must not be silently discarded/scored.
        runtime.numericValue = "123"
        probe.release(); _ = await saving.value
        XCTAssertEqual(runtime.numericValue, "123")
        XCTAssertEqual(runtime.stage, .item); XCTAssertTrue(store.attempts.isEmpty)
        XCTAssertNotNil(runtime.saveError)
        repository.archiveWriteObserver = nil
        runtime.saveError = nil; runtime.submitInline(store: store)
        XCTAssertEqual(runtime.stage, .feedback); XCTAssertEqual(store.attempts.count, 1)
    }

    func testAsyncCancellationBeforeCommitPreservesExactOriginalBytes() async throws {
        for stage in [NFLocalArchiveWriteStage.encoding, .staged] {
            let folder = FileManager.default.temporaryDirectory.appending(path: "NFAsync-Cancel-\(UUID())")
            defer { try? FileManager.default.removeItem(at: folder) }
            let url = folder.appending(path: "sessions.json")
            let repository = NFLocalSessionRepository(url: url)
            let (store, container) = try makeStore(repository: repository); _ = container
            let runtime = NFUniversalSessionRuntime(request: request())
            XCTAssertTrue(runtime.checkpointDraft(store: store)); runtime.acknowledgePresented()
            let bytes = try Data(contentsOf: url), revision = repository.archive.transactionRevision
            runtime.numericValue = "12"
            let probe = NFAsyncArchiveWriteProbe(stage); defer { probe.release() }
            repository.archiveWriteObserver = { probe.observe($0, $1) }
            let saving = Task { await runtime.checkpointDraftAsync(store: store) }
            let held = await probe.waitUntilHeld(); XCTAssertTrue(held)
            if stage == .staged {
                let competitor = NFLocalSessionRepository(url: url, ownerDeviceID: repository.ownerDeviceID)
                XCTAssertThrowsError(try competitor.removePrivateStudyRun(id: UUID())) { error in
                    guard case NFLocalSessionRepository.RepositoryError.busy = error else { return XCTFail("Expected the actual shared publication lock") }
                }
            }
            saving.cancel(); probe.release()
            let saved = await saving.value; XCTAssertFalse(saved)
            XCTAssertEqual(try Data(contentsOf: url), bytes)
            XCTAssertEqual(repository.archive.transactionRevision, revision)
            XCTAssertEqual(runtime.numericValue, "12"); XCTAssertNil(runtime.saveError)
            XCTAssertFalse(repository.hasPendingArchiveWrite)
            let leftovers = try FileManager.default.contentsOfDirectory(atPath: folder.path).filter { $0.hasPrefix(".local-transaction-") }
            XCTAssertTrue(leftovers.isEmpty)
        }
    }

    func testAsyncCancellationAndWriterReleaseAfterRenameStillAdoptCommittedReceipt() async throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "NFAsync-Committed-\(UUID())")
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appending(path: "sessions.json")
        let repository = NFLocalSessionRepository(url: url)
        let (store, container) = try makeStore(repository: repository); _ = container
        let runtime = NFUniversalSessionRuntime(request: request())
        XCTAssertTrue(runtime.checkpointDraft(store: store)); runtime.acknowledgePresented()
        runtime.numericValue = "12"
        let revision = repository.archive.transactionRevision ?? 0
        let probe = NFAsyncArchiveWriteProbe(.committed); defer { probe.release() }
        repository.archiveWriteObserver = { probe.observe($0, $1) }
        let saving = Task { await runtime.checkpointDraftAsync(store: store) }
        let held = await probe.waitUntilHeld(); XCTAssertTrue(held)
        saving.cancel(); runtime.releaseWriter()
        XCTAssertFalse(repository.claimWriter(UUID(), sessionID: runtime.sessionID, checkpoint: { true }))
        probe.release(); _ = await saving.value
        XCTAssertEqual(repository.archive.transactionRevision, revision + 1)
        XCTAssertEqual(repository.archive.sessions.first?.checkpoint.response, .numeric(.init(value: "12", unit: nil)))
        XCTAssertFalse(repository.hasPendingArchiveWrite); XCTAssertFalse(runtime.ownsWriter)
        XCTAssertEqual(runtime.stage, .item); XCTAssertTrue(store.attempts.isEmpty)
        let cold = NFLocalSessionRepository(url: url, ownerDeviceID: repository.ownerDeviceID)
        XCTAssertNil(cold.loadError)
        XCTAssertEqual(cold.archive.sessions.first?.checkpoint.response, .numeric(.init(value: "12", unit: nil)))
    }

    func testAsyncUnchangedRevisionWithDifferentOriginalBytesRefusesPublication() async throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "NFAsync-Digest-\(UUID())")
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appending(path: "sessions.json")
        let repository = NFLocalSessionRepository(url: url)
        let (store, container) = try makeStore(repository: repository); _ = container
        let runtime = NFUniversalSessionRuntime(request: request())
        XCTAssertTrue(runtime.checkpointDraft(store: store)); runtime.acknowledgePresented()
        let original = try Data(contentsOf: url)
        runtime.numericValue = "12"
        let probe = NFAsyncArchiveWriteProbe(.encoding); defer { probe.release() }
        repository.archiveWriteObserver = { probe.observe($0, $1) }
        let saving = Task { await runtime.checkpointDraftAsync(store: store) }
        let held = await probe.waitUntilHeld(); XCTAssertTrue(held)
        let external = Data(" \n".utf8) + original
        try external.write(to: url, options: .atomic)
        probe.release()
        let saved = await saving.value; XCTAssertFalse(saved)
        XCTAssertEqual(try Data(contentsOf: url), external)
        runtime.retrySaving(store: store)
        XCTAssertEqual(try Data(contentsOf: url), external, "A synchronous retry cannot overwrite unadopted bytes either")
        XCTAssertNotNil(runtime.saveError); XCTAssertEqual(runtime.numericValue, "12")
        XCTAssertFalse(repository.hasPendingArchiveWrite)
    }

    func testAsyncLocalAcknowledgementSurvivesLegacyMirrorFailureAndColdResume() async throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "NFAsync-Mirror-\(UUID())")
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appending(path: "sessions.json")
        let repository = NFLocalSessionRepository(url: url)
        let (store, container) = try makeStore(repository: repository); _ = container
        let runtime = NFUniversalSessionRuntime(request: request())
        XCTAssertTrue(runtime.checkpointDraft(store: store)); runtime.acknowledgePresented()
        runtime.numericValue = "12"
        runtime.legacyCheckpointWriteFailure = { throw CocoaError(.fileWriteNoPermission) }
        let saved = await runtime.checkpointDraftAsync(store: store); XCTAssertFalse(saved)
        XCTAssertNotNil(runtime.saveError)
        XCTAssertEqual(repository.archive.sessions.first?.checkpoint.response, .numeric(.init(value: "12", unit: nil)))
        let cold = NFLocalSessionRepository(url: url, ownerDeviceID: repository.ownerDeviceID)
        XCTAssertEqual(cold.archive.sessions.first?.checkpoint.response, .numeric(.init(value: "12", unit: nil)))
        runtime.legacyCheckpointWriteFailure = nil
        runtime.retrySaving(store: store)
        XCTAssertNil(runtime.saveError); XCTAssertTrue(store.attempts.isEmpty)
    }
}

extension ExactSessionContinuityTests {
    func testAsyncPostRenameVerificationFailureRetainsReceiptAndRequiresVerifiedRetry() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "NFAsync-Verify-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let folder = root.appending(path: "active"), moved = root.appending(path: "retained")
        let url = folder.appending(path: "sessions.json")
        let repository = NFLocalSessionRepository(url: url)
        let (store, container) = try makeStore(repository: repository); _ = container
        let runtime = NFUniversalSessionRuntime(request: request())
        XCTAssertTrue(runtime.checkpointDraft(store: store)); runtime.acknowledgePresented()
        runtime.numericValue = "123"
        let probe = NFAsyncArchiveWriteProbe(.renamed); defer { probe.release() }
        repository.archiveWriteObserver = { probe.observe($0, $1) }
        let saving = Task { await runtime.checkpointDraftAsync(store: store) }
        let held = await probe.waitUntilHeld(); XCTAssertTrue(held)
        // Rename already succeeded. Removing its directory name makes the real
        // directory-flush verification fail without deleting the accepted bytes.
        try FileManager.default.moveItem(at: folder, to: moved)
        probe.release()
        let saved = await saving.value; XCTAssertFalse(saved)
        XCTAssertTrue(repository.archiveWriteVerificationNeeded)
        XCTAssertEqual(repository.archive.sessions.first?.checkpoint.response, .numeric(.init(value: "123", unit: nil)))
        XCTAssertEqual(runtime.exitDisposition(store: store), .unacknowledged)
        XCTAssertNotNil(runtime.saveError)
        XCTAssertThrowsError(try repository.removePrivateStudyRun(id: UUID()))
        let retained = NFLocalSessionRepository(url: moved.appending(path: "sessions.json"), ownerDeviceID: repository.ownerDeviceID)
        XCTAssertEqual(retained.archive.sessions.first?.checkpoint.response, .numeric(.init(value: "123", unit: nil)))
        try FileManager.default.moveItem(at: moved, to: folder)
        repository.archiveWriteObserver = nil
        let retried = await runtime.checkpointDraftAsync(store: store); XCTAssertTrue(retried)
        XCTAssertFalse(repository.archiveWriteVerificationNeeded); XCTAssertNil(runtime.saveError)
        XCTAssertTrue(runtime.prepareToClose(store: store).permitsClose)
    }
}

extension ExactSessionContinuityTests {
    func testReloadDuringAsyncWriteKeepsProjectionsReadableAndDefersLegacyModelMutation() async throws {
        let repository = NFLocalSessionRepository()
        let (store, container) = try makeStore(repository: repository); _ = container
        let runtime = NFUniversalSessionRuntime(request: request())
        XCTAssertTrue(runtime.checkpointDraft(store: store)); runtime.acknowledgePresented()
        runtime.numericValue = "12"
        let probe = NFAsyncArchiveWriteProbe(.encoding); defer { probe.release() }
        repository.archiveWriteObserver = { probe.observe($0, $1) }
        let saving = Task { await runtime.checkpointDraftAsync(store: store) }
        let held = await probe.waitUntilHeld(); XCTAssertTrue(held)
        let document = SourceDocumentRecord(filename: "fixture.txt", typeIdentifier: "public.plain-text", sizeBytes: 1, localPath: "")
        let original = "Extractor error at /Users/private/fixture-secret.txt"
        document.indexError = original
        store.context.insert(document); try store.context.save()
        store.reload(); store.reload()
        XCTAssertTrue(store.documents.contains { $0.id == document.id })
        XCTAssertEqual(document.indexError, original, "reload cannot mutate a model before a later archive busy refusal")
        XCTAssertFalse(store.context.hasChanges)
        probe.release(); _ = await saving.value
        XCTAssertEqual(document.indexError, NFDiagnosticRedactor.sanitizedPersistedMessage(original, context: .documentExtraction))
        XCTAssertNotEqual(document.indexError, original)
        XCTAssertFalse(store.context.hasChanges)
    }
}

extension ExactSessionContinuityTests {
    func testAsyncValidLocalWriterCannotReplaceAnotherOwnersRetainedRun() async throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "NFAsync-Owner-\(UUID())")
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appending(path: "sessions.json")
        let originalRepository = NFLocalSessionRepository(url: url)
        let (store, container) = try makeStore(repository: originalRepository); _ = container
        let runtime = NFUniversalSessionRuntime(request: request())
        XCTAssertTrue(runtime.checkpointDraft(store: store)); runtime.finishClosing()
        let bytes = try Data(contentsOf: url)
        let repository = NFLocalSessionRepository(url: url, ownerDeviceID: UUID())
        let original = try XCTUnwrap(repository.archive.sessions.first)
        let writer = UUID()
        XCTAssertTrue(repository.claimWriter(writer, sessionID: original.id, checkpoint: { true }))
        defer { repository.releaseWriter(writer) }
        let command = try repository.sessionCommand(authority: repository.writerAuthority(for: writer, sessionID: original.id), sessionID: original.id)
        let proposed = NFLocalSessionEnvelope(id: original.id, ownerDeviceID: repository.ownerDeviceID,
            revision: original.revision + 1, request: original.request, checkpoint: original.checkpoint,
            status: original.status, updatedAt: Date())
        do {
            _ = try await repository.saveSessionAsync(proposed, command: command, expectedRevision: original.revision)
            XCTFail("Current process authority cannot replace a foreign owner's retained payload")
        } catch NFLocalSessionRepository.RepositoryError.wrongOwner { }
        XCTAssertEqual(try Data(contentsOf: url), bytes)
        XCTAssertEqual(repository.archive.sessions.first?.ownerDeviceID, original.ownerDeviceID)
        XCTAssertFalse(repository.hasPendingArchiveWrite)
    }
}

#if os(macOS)
@MainActor final class NativePendingArchiveCloseTests: XCTestCase {
    func testQuitWaitsForPendingWriteAndRechecksEveryWindowBeforeDismissingAny() async throws {
        let registry = NFSessionCloseRegistry()
        let actions = NFSessionNativeCloseActions()
        let gate = NFSessionDraftSaveGate()
        XCTAssertTrue(gate.begin())
        let first = UUID(), second = UUID()
        var firstClosed = false, secondClosed = false, terminated = false
        registry.register(first, check: { true }, close: { firstClosed = true; registry.remove(first) }, saveGate: gate)
        actions.quit(registry: registry, windows: [], terminate: { terminated = true })
        XCTAssertFalse(firstClosed); XCTAssertFalse(terminated)
        for _ in 0..<5 { await Task.yield() }
        registry.register(second, check: { false }, close: { secondClosed = true; registry.remove(second) })
        gate.finish()
        for _ in 0..<10 { await Task.yield() }
        XCTAssertFalse(firstClosed); XCTAssertFalse(secondClosed); XCTAssertFalse(terminated)
        registry.remove(second)
        actions.quit(registry: registry, windows: [], terminate: { terminated = true })
        for _ in 0..<10 { await Task.yield() }
        XCTAssertTrue(firstClosed); XCTAssertTrue(terminated)
    }

    func testWindowCloseWaitsForSaveBeforeCallingOriginalDelegateAndClosesExactlyOnce() async throws {
        final class Original: NSObject, NSWindowDelegate {
            var calls = 0
            func windowShouldClose(_ sender: NSWindow) -> Bool { calls += 1; return false }
        }
        let window = NSWindow(contentRect: .init(x: 0, y: 0, width: 500, height: 600),
            styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.delegate = nil; window.close() }
        let original = Original(); window.delegate = original
        let registry = NFSessionWindowCloseRegistry()
        let token = UUID(), gate = NFSessionDraftSaveGate()
        XCTAssertTrue(gate.begin())
        var closes = 0
        registry.register(token, window: window, prepare: { true }, close: {
            closes += 1; registry.remove(token, window: window)
        }, saveGate: gate)
        XCTAssertTrue(registry.requestClose(window))
        XCTAssertEqual(closes, 0); XCTAssertEqual(original.calls, 0)
        gate.finish()
        for _ in 0..<20 { await Task.yield() }
        XCTAssertEqual(closes, 1)
        XCTAssertTrue(window.delegate === original)
        XCTAssertEqual(original.calls, 1)
    }
}
#endif


extension ExactSessionContinuityTests {
    func testPendingAsyncWriteRefusesRecoveryBackupPurgeBeforeAnyDeletion() async throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "NFAsync-Recovery-Purge-\(UUID())")
        defer { try? FileManager.default.removeItem(at: folder) }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appending(path: "sessions.json")
        var raw = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(NFLocalSessionRepository.Archive())) as? [String: Any])
        let malformedID = UUID()
        raw["snapshots"] = [["attemptID": malformedID.uuidString, "exercise": "retained malformed original"]]
        let original = try JSONSerialization.data(withJSONObject: raw, options: [.sortedKeys])
        try original.write(to: url)
        let repository = NFLocalSessionRepository(url: url)
        XCTAssertNil(repository.loadError)
        XCTAssertEqual(repository.archive.unavailableHistorySnapshots?.map(\.attemptID), [malformedID])
        let recoveryDirectory = try XCTUnwrap(repository.historyRecoveryDirectoryURL)
        let backup = try XCTUnwrap(FileManager.default.contentsOfDirectory(at: recoveryDirectory, includingPropertiesForKeys: nil).first)
        XCTAssertEqual(try Data(contentsOf: backup), original)
        let (store, container) = try makeStore(repository: repository); _ = container
        let runtime = NFUniversalSessionRuntime(request: request())
        XCTAssertTrue(runtime.checkpointDraft(store: store)); runtime.acknowledgePresented()
        runtime.numericValue = "123"
        let predecessor = try Data(contentsOf: url)
        let probe = NFAsyncArchiveWriteProbe(.encoding); defer { probe.release() }
        repository.archiveWriteObserver = { probe.observe($0, $1) }
        let saving = Task { await runtime.checkpointDraftAsync(store: store) }
        let held = await probe.waitUntilHeld(); XCTAssertTrue(held)
        XCTAssertThrowsError(try repository.purgeHistoryRecoveryBackups()) { error in
            guard case NFLocalSessionRepository.RepositoryError.busy = error else { return XCTFail("Expected busy, got \(error)") }
        }
        XCTAssertThrowsError(try repository.removeReferences(attemptIDs: [malformedID])) { error in
            guard case NFLocalSessionRepository.RepositoryError.busy = error else { return XCTFail("Expected busy, got \(error)") }
        }
        XCTAssertEqual(try Data(contentsOf: backup), original)
        XCTAssertEqual(try Data(contentsOf: url), predecessor)
        XCTAssertEqual(repository.archive.unavailableHistorySnapshots?.map(\.attemptID), [malformedID])
        probe.release()
        let saved = await saving.value; XCTAssertTrue(saved)
        XCTAssertTrue(probe.stayedOffMain)
        XCTAssertEqual(try Data(contentsOf: backup), original)
        repository.archiveWriteObserver = nil
        try repository.purgeHistoryRecoveryBackups()
        XCTAssertFalse(FileManager.default.fileExists(atPath: recoveryDirectory.path))
    }
}


/// Counts real archive transactions; holds the selected worker boundary on its
/// normal cooperative executor. No model, response, score or receipt is injected.
final class NFAsyncSubmitProbe: @unchecked Sendable {
    private let lock = NSLock()
    private let signal = DispatchSemaphore(value: 0)
    private let transaction: Int
    private let stage: NFLocalArchiveWriteStage
    private var currentTransaction = 0
    private var held = false
    private var observations: [Bool] = []
    private var timedOut = false
    init(transaction: Int, stage: NFLocalArchiveWriteStage) { self.transaction = transaction; self.stage = stage }
    func observe(_ stage: NFLocalArchiveWriteStage, _ onMain: Bool) {
        let shouldHold = lock.withLock {
            observations.append(onMain)
            if stage == .encoding { currentTransaction += 1 }
            guard !held, currentTransaction == transaction, stage == self.stage else { return false }
            held = true; return true
        }
        if shouldHold, signal.wait(timeout: .now() + 15) != .success { lock.withLock { timedOut = true } }
    }
    func release() { signal.signal() }
    func waitUntilHeld() async -> Bool {
        for _ in 0..<500 {
            if lock.withLock({ held }) { return true }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return false
    }
    var stayedOffMain: Bool { lock.withLock { !observations.isEmpty && !observations.contains(true) && !timedOut } }
}

extension ExactSessionContinuityTests {
    func testAsyncSubmitPublishesFeedbackOnlyAfterThirdAcceptedArchiveAndExcludesWait() async throws {
        let repository = NFLocalSessionRepository()
        let (store, container) = try makeStore(repository: repository); _ = container
        var now: TimeInterval = 100
        let runtime = NFUniversalSessionRuntime(request: request(), monotonicNow: { now })
        XCTAssertTrue(runtime.checkpointDraft(store: store)); runtime.acknowledgePresented()
        now = 107; runtime.numericValue = "12"
        XCTAssertTrue(runtime.canSubmit, runtime.responseValidationMessage ?? "Complete numeric fixture")
        let probe = NFAsyncSubmitProbe(transaction: 3, stage: .encoding); defer { probe.release() }
        repository.archiveWriteObserver = { probe.observe($0, $1) }
        let submit = Task { await runtime.submitInlineAsync(store: store) }
        let held = await probe.waitUntilHeld(); XCTAssertTrue(held)
        XCTAssertEqual(store.attempts.count, 1)
        XCTAssertEqual(runtime.stage, .confidence)
        XCTAssertTrue(runtime.hasPreparedCommit); XCTAssertTrue(runtime.correctness.isEmpty)
        XCTAssertFalse(runtime.canEditDraft); XCTAssertFalse(runtime.canSubmit)
        XCTAssertEqual(repository.archive.sessions.first?.checkpoint.phase, .confidence)
        XCTAssertEqual(repository.archive.snapshots.count, 1)
        now = 180
        probe.release(); await submit.value
        XCTAssertTrue(probe.stayedOffMain)
        XCTAssertEqual(runtime.stage, .feedback); XCTAssertEqual(runtime.correctness.count, 1)
        XCTAssertEqual(repository.archive.sessions.first?.checkpoint.phase, .feedback)
        XCTAssertEqual(store.attempts[0].activeDurationSeconds, 7, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(repository.archive.sessions.first?.checkpoint.cumulativeActiveDuration), 7, accuracy: 0.001)
        repository.archiveWriteObserver = nil
        let original = try NFImmutableAttemptRecordSnapshot.encoded(NFImmutableAttemptRecordSnapshot(store.attempts[0]))
        await runtime.retrySavingAsync(store: store)
        XCTAssertEqual(store.attempts.count, 1)
        XCTAssertEqual(try NFImmutableAttemptRecordSnapshot.encoded(NFImmutableAttemptRecordSnapshot(store.attempts[0])), original)
    }

    func testAsyncSubmitCancellationBeforePreparedRenameRetainsOriginalBytesAndRetriesSameAttempt() async throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "NFSubmit-Cancel-\(UUID())")
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appending(path: "sessions.json"), repository = NFLocalSessionRepository(url: folder.appending(path: "sessions.json"))
        let (store, container) = try makeStore(repository: repository); _ = container
        let runtime = NFUniversalSessionRuntime(request: request())
        XCTAssertTrue(runtime.checkpointDraft(store: store)); runtime.acknowledgePresented(); runtime.numericValue = "12"
        let original = try Data(contentsOf: url)
        let attemptID = try XCTUnwrap(repository.archive.sessions.first?.checkpoint.attemptID)
        let probe = NFAsyncSubmitProbe(transaction: 1, stage: .staged); defer { probe.release() }
        repository.archiveWriteObserver = { probe.observe($0, $1) }
        let submit = Task { await runtime.submitInlineAsync(store: store) }
        let held = await probe.waitUntilHeld(); XCTAssertTrue(held)
        submit.cancel(); probe.release(); await submit.value
        XCTAssertEqual(try Data(contentsOf: url), original)
        XCTAssertTrue(store.attempts.isEmpty); XCTAssertTrue(repository.archive.snapshots.isEmpty)
        XCTAssertEqual(runtime.stage, .confidence); XCTAssertTrue(runtime.hasPreparedCommit)
        XCTAssertEqual(runtime.numericValue, "12"); XCTAssertNotNil(runtime.saveError)
        repository.archiveWriteObserver = nil
        await runtime.retrySavingAsync(store: store)
        XCTAssertEqual(runtime.stage, .feedback); XCTAssertEqual(store.attempts.map(\.id), [attemptID])
        XCTAssertTrue(probe.stayedOffMain)
    }

    func testAsyncSubmitCancellationAfterHistoryRenameColdRetriesExactPreparedAnswer() async throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "NFSubmit-Snapshot-Cold-\(UUID())")
        defer { try? FileManager.default.removeItem(at: folder) }
        let owner = UUID(), url = folder.appending(path: "sessions.json")
        let repository = NFLocalSessionRepository(url: url, ownerDeviceID: owner)
        let (store, container) = try makeStore(repository: repository); _ = container
        let runtime = NFUniversalSessionRuntime(request: request())
        XCTAssertTrue(runtime.checkpointDraft(store: store)); runtime.acknowledgePresented(); runtime.numericValue = "12"
        let exact = runtime.exercise
        let probe = NFAsyncSubmitProbe(transaction: 2, stage: .committed); defer { probe.release() }
        repository.archiveWriteObserver = { probe.observe($0, $1) }
        let submit = Task { await runtime.submitInlineAsync(store: store) }
        let held = await probe.waitUntilHeld(); XCTAssertTrue(held)
        submit.cancel(); probe.release(); await submit.value
        XCTAssertEqual(runtime.stage, .confidence); XCTAssertTrue(store.attempts.isEmpty)
        let prepared = try XCTUnwrap(repository.archive.sessions.first)
        XCTAssertEqual(prepared.checkpoint.pendingOutcome, "answer")
        XCTAssertEqual(repository.archive.snapshots.first?.exercise, exact)
        runtime.finishClosing()
        let reopened = NFLocalSessionRepository(url: url, ownerDeviceID: owner)
        XCTAssertNil(reopened.loadError)
        let (coldStore, coldContainer) = try makeStore(repository: reopened); _ = coldContainer
        XCTAssertTrue(coldStore.resumeSession(prepared.id))
        let cold = NFUniversalSessionRuntime(request: try XCTUnwrap(coldStore.activeSessionRequest))
        XCTAssertTrue(cold.checkpointDraft(store: coldStore))
        let frozen = cold.lastResult
        await cold.retrySavingAsync(store: coldStore)
        XCTAssertEqual(cold.stage, .feedback); XCTAssertEqual(cold.lastResult, frozen)
        XCTAssertEqual(coldStore.attempts.map(\.id), [prepared.checkpoint.attemptID])
        XCTAssertEqual(coldStore.exerciseSnapshot(for: prepared.checkpoint.attemptID), exact)
    }

    func testAsyncSubmitCancellationAfterFeedbackRenameAdoptsFeedbackAndColdReceiptOnce() async throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "NFSubmit-Feedback-Cold-\(UUID())")
        defer { try? FileManager.default.removeItem(at: folder) }
        let owner = UUID(), url = folder.appending(path: "sessions.json")
        let repository = NFLocalSessionRepository(url: url, ownerDeviceID: owner)
        let (store, container) = try makeStore(repository: repository)
        let runtime = NFUniversalSessionRuntime(request: request())
        XCTAssertTrue(runtime.checkpointDraft(store: store)); runtime.acknowledgePresented(); runtime.numericValue = "12"
        let probe = NFAsyncSubmitProbe(transaction: 3, stage: .committed); defer { probe.release() }
        repository.archiveWriteObserver = { probe.observe($0, $1) }
        let submit = Task { await runtime.submitInlineAsync(store: store) }
        let held = await probe.waitUntilHeld(); XCTAssertTrue(held)
        XCTAssertEqual(runtime.stage, .confidence)
        submit.cancel(); probe.release(); await submit.value
        XCTAssertEqual(runtime.stage, .feedback); XCTAssertEqual(runtime.correctness.count, 1)
        let attempt = try XCTUnwrap(store.attempts.first)
        let original = try NFImmutableAttemptRecordSnapshot.encoded(NFImmutableAttemptRecordSnapshot(attempt))
        runtime.finishClosing()
        let reopened = NFLocalSessionRepository(url: url, ownerDeviceID: owner)
        let coldStore = AppStore(context: container.mainContext, localSessionRepository: reopened)
        XCTAssertTrue(coldStore.resumeSession(runtime.sessionID))
        let cold = NFUniversalSessionRuntime(request: try XCTUnwrap(coldStore.activeSessionRequest))
        XCTAssertTrue(cold.checkpointDraft(store: coldStore)); await cold.retrySavingAsync(store: coldStore)
        XCTAssertEqual(cold.stage, .feedback); XCTAssertEqual(cold.correctness.count, 1)
        XCTAssertEqual(coldStore.attempts.count, 1)
        XCTAssertEqual(try NFImmutableAttemptRecordSnapshot.encoded(NFImmutableAttemptRecordSnapshot(coldStore.attempts[0])), original)
    }

    func testAsyncSubmitReleasedGenerationCannotInsertAfterAcceptedPreparation() async throws {
        let repository = NFLocalSessionRepository()
        let (store, container) = try makeStore(repository: repository); _ = container
        let old = NFUniversalSessionRuntime(request: request())
        XCTAssertTrue(old.checkpointDraft(store: store)); old.acknowledgePresented(); old.numericValue = "12"
        let probe = NFAsyncSubmitProbe(transaction: 1, stage: .committed); defer { probe.release() }
        repository.archiveWriteObserver = { probe.observe($0, $1) }
        let submit = Task { await old.submitInlineAsync(store: store) }
        let held = await probe.waitUntilHeld(); XCTAssertTrue(held)
        old.releaseWriter()
        probe.release(); await submit.value
        XCTAssertTrue(store.attempts.isEmpty); XCTAssertEqual(old.stage, .confidence)
        let saved = try XCTUnwrap(repository.archive.sessions.first)
        repository.archiveWriteObserver = nil
        var fresh = saved.request; fresh.localCheckpoint = saved.checkpoint; fresh.localSessionID = saved.id
        let current = NFUniversalSessionRuntime(request: fresh)
        XCTAssertTrue(current.checkpointDraft(store: store))
        await current.retrySavingAsync(store: store)
        XCTAssertEqual(current.stage, .feedback); XCTAssertEqual(store.attempts.map(\.id), [saved.checkpoint.attemptID])
        let original = try NFImmutableAttemptRecordSnapshot.encoded(NFImmutableAttemptRecordSnapshot(store.attempts[0]))
        await old.retrySavingAsync(store: store)
        XCTAssertEqual(try NFImmutableAttemptRecordSnapshot.encoded(NFImmutableAttemptRecordSnapshot(store.attempts[0])), original)
        XCTAssertEqual(old.stage, .confidence)
    }

    func testAsyncSubmitPreparedLocalWriteSurvivesLegacyMirrorFailure() async throws {
        enum Fault: Error { case mirror }
        let repository = NFLocalSessionRepository()
        let (store, container) = try makeStore(repository: repository); _ = container
        let runtime = NFUniversalSessionRuntime(request: request())
        XCTAssertTrue(runtime.checkpointDraft(store: store)); runtime.acknowledgePresented(); runtime.numericValue = "12"
        runtime.legacyCheckpointWriteFailure = { throw Fault.mirror }
        await runtime.submitInlineAsync(store: store)
        let saved = try XCTUnwrap(repository.archive.sessions.first)
        XCTAssertEqual(saved.checkpoint.phase, .confidence); XCTAssertEqual(saved.checkpoint.pendingOutcome, "answer")
        XCTAssertTrue(store.attempts.isEmpty); XCTAssertEqual(runtime.stage, .confidence)
        runtime.legacyCheckpointWriteFailure = nil
        await runtime.retrySavingAsync(store: store)
        XCTAssertEqual(runtime.stage, .feedback); XCTAssertEqual(store.attempts.map(\.id), [saved.checkpoint.attemptID])
    }

    func testAsyncSourceReferenceAndSelfRatingUseAcceptedSnapshotsAndZeroObjectiveEvidence() async throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "NFSubmit-Source-Acknowledgement-\(UUID())")
        defer { try? FileManager.default.removeItem(at: folder) }
        let repository = NFLocalSessionRepository(url: folder.appending(path: "sessions.json"))
        let (store, container) = try makeStore(repository: repository); _ = container
        let chunk = NFSourceChunk(id: "async-source", documentID: UUID(), documentVersion: 1,
            sourceName: "Private async source.txt", locator: .init(page: nil, lineStart: 1, lineEnd: 1, section: nil),
            text: "The exact private reference stays local.", contentHash: "async-source", ordinal: 0, language: "en")
        let source = try NFSourceReviewExactAdapter.makeRequest(chunk: chunk, localeIdentifier: "en")
        let runtime = NFUniversalSessionRuntime(request: source)
        XCTAssertTrue(runtime.checkpointDraft(store: store)); runtime.acknowledgePresented()
        runtime.selfCheckReflection = "My independently recalled answer."
        let revealProbe = NFAsyncSubmitProbe(transaction: 1, stage: .staged); defer { revealProbe.release() }
        repository.archiveWriteObserver = { revealProbe.observe($0, $1) }
        let reveal = Task { await runtime.submitInlineAsync(store: store) }
        let held = await revealProbe.waitUntilHeld(); XCTAssertTrue(held)
        XCTAssertFalse(runtime.selfCheckReferenceRevealed); XCTAssertTrue(store.attempts.isEmpty)
        revealProbe.release(); await reveal.value
        XCTAssertEqual(runtime.stage, .selfCheckComparison); XCTAssertTrue(runtime.selfCheckReferenceRevealed)
        runtime.selfCheckRating = .partiallyMatched
        let commitProbe = NFAsyncSubmitProbe(transaction: 3, stage: .encoding); defer { commitProbe.release() }
        repository.archiveWriteObserver = { commitProbe.observe($0, $1) }
        let commit = Task { await runtime.saveSelfCheckAsync(store: store) }
        let commitHeld = await commitProbe.waitUntilHeld(); XCTAssertTrue(commitHeld)
        XCTAssertEqual(runtime.stage, .confidence); XCTAssertEqual(store.attempts.count, 1)
        XCTAssertTrue(runtime.correctness.isEmpty)
        commitProbe.release(); await commit.value
        XCTAssertEqual(runtime.stage, .feedback); XCTAssertTrue(runtime.correctness.isEmpty)
        XCTAssertEqual(store.attempts[0].evidenceWeight, 0); XCTAssertEqual(store.attempts[0].deterministicCredit, 0)
        XCTAssertEqual(store.attempts[0].correctAnswerText, "")
        XCTAssertEqual(store.exerciseSnapshot(for: store.attempts[0].id), source.localCheckpoint?.exercise)
        XCTAssertEqual(repository.archive.snapshots[0].exercise.provenance.sourceDocumentIDs, [chunk.documentID.uuidString])
    }

    func testAsyncProtectedPreparedCancellationColdRetryKeepsOnlyMinimalReceipt() async throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "NFSubmit-Protected-\(UUID())")
        defer { try? FileManager.default.removeItem(at: folder) }
        let owner = UUID(), url = folder.appending(path: "sessions.json")
        let repository = NFLocalSessionRepository(url: url, ownerDeviceID: owner)
        let (store, container) = try makeStore(repository: repository); _ = container
        let runtime = try numericProtectedRuntime()
        XCTAssertTrue(runtime.checkpointDraft(store: store)); runtime.acknowledgePresented()
        guard case let .numeric(schema) = runtime.exercise.interaction else { return XCTFail("Expected authentic protected numeric descriptor") }
        runtime.numericValue = "17"
        if schema.answer.unitRequired { runtime.numericUnit = try XCTUnwrap(schema.answer.canonicalUnit) }
        runtime.chooseConfidence(.certain)
        XCTAssertTrue(runtime.canSubmit, runtime.responseValidationMessage ?? "Complete protected numeric fixture")
        let probe = NFAsyncSubmitProbe(transaction: 1, stage: .committed); defer { probe.release() }
        repository.archiveWriteObserver = { probe.observe($0, $1) }
        let submit = Task { await runtime.submitInlineAsync(store: store) }
        let held = await probe.waitUntilHeld(); XCTAssertTrue(held)
        submit.cancel(); probe.release(); await submit.value
        let prepared = try XCTUnwrap(repository.archive.sessions.first)
        let receipt = try XCTUnwrap(prepared.checkpoint.protectedCommitReceipt)
        XCTAssertNil(prepared.checkpoint.exercise); XCTAssertNil(prepared.checkpoint.result)
        XCTAssertTrue(repository.archive.snapshots.isEmpty); XCTAssertTrue(store.attempts.isEmpty)
        XCTAssertNil(repository.exportArchive.sessions.first?.checkpoint.protectedCommitReceipt)
        runtime.finishClosing()
        let coldRepository = NFLocalSessionRepository(url: url, ownerDeviceID: owner)
        let (coldStore, coldContainer) = try makeStore(repository: coldRepository); _ = coldContainer
        XCTAssertTrue(coldStore.resumeSession(prepared.id))
        let cold = NFUniversalSessionRuntime(request: try XCTUnwrap(coldStore.activeSessionRequest))
        XCTAssertNil(cold.unavailableReason); XCTAssertTrue(cold.checkpointDraft(store: coldStore))
        await cold.retrySavingAsync(store: coldStore)
        XCTAssertEqual(cold.stage, .feedback); XCTAssertEqual(coldStore.attempts.map(\.id), [receipt.attemptID])
        XCTAssertEqual(cold.lastResult?.credit, receipt.credit); XCTAssertNil(cold.lastResult?.expectedAnswerSummary)
        XCTAssertTrue(coldRepository.archive.snapshots.isEmpty)
    }

    func testAsyncSubmitRealFeedbackFilesystemFailurePreservesCoreReceiptAndRetryDoesNotRewriteIt() async throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "NFSubmit-Feedback-Failure-\(UUID())")
        let backup = folder.appendingPathExtension("held")
        defer { try? FileManager.default.removeItem(at: folder); try? FileManager.default.removeItem(at: backup) }
        let repository = NFLocalSessionRepository(url: folder.appending(path: "sessions.json"))
        let (store, container) = try makeStore(repository: repository); _ = container
        let runtime = NFUniversalSessionRuntime(request: request())
        XCTAssertTrue(runtime.checkpointDraft(store: store)); runtime.acknowledgePresented(); runtime.numericValue = "12"
        let probe = NFAsyncSubmitProbe(transaction: 3, stage: .staged); defer { probe.release() }
        repository.archiveWriteObserver = { probe.observe($0, $1) }
        let submit = Task { await runtime.submitInlineAsync(store: store) }
        let held = await probe.waitUntilHeld(); XCTAssertTrue(held)
        let original = try NFImmutableAttemptRecordSnapshot.encoded(NFImmutableAttemptRecordSnapshot(XCTUnwrap(store.attempts.first)))
        try FileManager.default.moveItem(at: folder, to: backup)
        try Data("blocked parent".utf8).write(to: folder)
        probe.release(); await submit.value
        XCTAssertEqual(runtime.stage, .confidence); XCTAssertTrue(runtime.correctness.isEmpty)
        XCTAssertEqual(store.attempts.count, 1); XCTAssertNotNil(runtime.saveError)
        try FileManager.default.removeItem(at: folder); try FileManager.default.moveItem(at: backup, to: folder)
        repository.archiveWriteObserver = nil
        await runtime.retrySavingAsync(store: store)
        XCTAssertEqual(runtime.stage, .feedback); XCTAssertEqual(runtime.correctness.count, 1)
        XCTAssertEqual(store.attempts.count, 1)
        XCTAssertEqual(try NFImmutableAttemptRecordSnapshot.encoded(NFImmutableAttemptRecordSnapshot(store.attempts[0])), original)
    }
}

extension ExactSessionContinuityTests {
    func testAsyncSubmitLateNativeResponseIsRetainedWithoutReplacingFrozenAnswerOnRetry() async throws {
        let repository = NFLocalSessionRepository()
        let (store, container) = try makeStore(repository: repository); _ = container
        let runtime = NFUniversalSessionRuntime(request: request())
        XCTAssertTrue(runtime.checkpointDraft(store: store)); runtime.acknowledgePresented(); runtime.numericValue = "12"
        let probe = NFAsyncSubmitProbe(transaction: 1, stage: .encoding); defer { probe.release() }
        repository.archiveWriteObserver = { probe.observe($0, $1) }
        let submit = Task { await runtime.submitInlineAsync(store: store) }
        let held = await probe.waitUntilHeld(); XCTAssertTrue(held)
        XCTAssertFalse(runtime.canEditDraft)
        runtime.numericValue = "13" // A native callback already delivered before disabled state propagated.
        probe.release(); await submit.value
        XCTAssertEqual(runtime.numericValue, "13"); XCTAssertTrue(store.attempts.isEmpty)
        XCTAssertEqual(repository.archive.sessions.first?.checkpoint.response, .numeric(.init(value: "12", unit: nil)))
        repository.archiveWriteObserver = nil
        await runtime.retrySavingAsync(store: store)
        XCTAssertEqual(runtime.numericValue, "13"); XCTAssertTrue(store.attempts.isEmpty)
        XCTAssertEqual(runtime.prepareToClose(store: store), .unacknowledged)
        XCTAssertTrue(runtime.recoveryText.contains("13"))
        XCTAssertEqual(repository.archive.sessions.first?.checkpoint.response, .numeric(.init(value: "12", unit: nil)))
    }
}

extension ExactSessionContinuityTests {
    func testAsyncEndRequestedDuringSubmitWaitsForAcceptedFeedbackAndKeepsOneReceipt() async throws {
        let repository = NFLocalSessionRepository()
        let (store, container) = try makeStore(repository: repository); _ = container
        let runtime = NFUniversalSessionRuntime(request: request())
        XCTAssertTrue(runtime.checkpointDraft(store: store)); runtime.acknowledgePresented(); runtime.numericValue = "12"
        let probe = NFAsyncSubmitProbe(transaction: 3, stage: .encoding); defer { probe.release() }
        repository.archiveWriteObserver = { probe.observe($0, $1) }
        let submit = Task { await runtime.submitInlineAsync(store: store) }
        let held = await probe.waitUntilHeld(); XCTAssertTrue(held)
        let ending = Task { await runtime.endSessionAsync(store: store) }
        for _ in 0..<20 where !runtime.draftSaveGate.hasQueuedAction { await Task.yield() }
        XCTAssertTrue(runtime.draftSaveGate.hasQueuedAction)
        XCTAssertEqual(runtime.stage, .confidence)
        let attemptID = try XCTUnwrap(store.attempts.first?.id)
        probe.release(); await submit.value; await ending.value
        XCTAssertEqual(runtime.stage, .summary); XCTAssertTrue(runtime.endedEarly)
        XCTAssertEqual(store.attempts.map(\.id), [attemptID])
        XCTAssertEqual(repository.archive.sessions.first?.status, .endedEarly)
        XCTAssertEqual(repository.archive.sessions.first?.checkpoint.correctness.count, 1)
    }
}

extension ExactSessionContinuityTests {
    func testAsyncAttemptRetentionRejectsUnpreparedAndWrongAttemptUnderCurrentWriter() async throws {
        let repository = NFLocalSessionRepository()
        let (store, container) = try makeStore(repository: repository); _ = container
        let runtime = NFUniversalSessionRuntime(request: request())
        XCTAssertTrue(runtime.checkpointDraft(store: store)); runtime.acknowledgePresented()
        let initial = try XCTUnwrap(repository.archive.sessions.first)
        let command = try runtime.sessionWriterCommand()
        let premature = NFLocalAttemptSnapshot(attemptID: initial.checkpoint.attemptID, exercise: runtime.exercise)
        do {
            _ = try await repository.retainAttemptSnapshotAsync(premature, sessionID: runtime.sessionID, command: command)
            XCTFail("A writer token does not authorize history before a prepared answer")
        } catch { guard case NFLocalSessionRepository.RepositoryError.staleRevision = error else { return XCTFail("Expected exact-state refusal") } }
        XCTAssertEqual(repository.archive.sessions.first?.checkpoint, initial.checkpoint); XCTAssertEqual(repository.archive.sessions.first?.revision, initial.revision); XCTAssertTrue(repository.archive.snapshots.isEmpty)
        runtime.numericValue = "12"
        let probe = NFAsyncSubmitProbe(transaction: 1, stage: .committed); defer { probe.release() }
        repository.archiveWriteObserver = { probe.observe($0, $1) }
        let submit = Task { await runtime.submitInlineAsync(store: store) }
        let held = await probe.waitUntilHeld(); XCTAssertTrue(held)
        submit.cancel(); probe.release(); await submit.value
        repository.archiveWriteObserver = nil
        let accepted = try XCTUnwrap(repository.archive.sessions.first)
        let unrelated = NFLocalAttemptSnapshot(attemptID: UUID(), exercise: runtime.exercise)
        do {
            _ = try await repository.retainAttemptSnapshotAsync(unrelated, sessionID: runtime.sessionID, command: command)
            XCTFail("An unrelated attempt cannot inherit this prepared slot")
        } catch { guard case NFLocalSessionRepository.RepositoryError.staleRevision = error else { return XCTFail("Expected exact-attempt refusal") } }
        XCTAssertEqual(repository.archive.sessions.first?.checkpoint, accepted.checkpoint); XCTAssertEqual(repository.archive.sessions.first?.revision, accepted.revision); XCTAssertTrue(repository.archive.snapshots.isEmpty)
        await runtime.retrySavingAsync(store: store)
        XCTAssertEqual(runtime.stage, .feedback); XCTAssertEqual(store.attempts.map(\.id), [initial.checkpoint.attemptID])
    }
}

extension ExactSessionContinuityTests {
    func testAsyncFeedbackDirectoryVerificationFailureRetainsPendingPresentationUntilExactRepair() async throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "NFSubmit-Feedback-Verification-\(UUID())")
        let backup = folder.appendingPathExtension("held")
        defer { try? FileManager.default.removeItem(at: folder); try? FileManager.default.removeItem(at: backup) }
        let owner = UUID(), url = folder.appending(path: "sessions.json")
        let repository = NFLocalSessionRepository(url: url, ownerDeviceID: owner)
        let (store, container) = try makeStore(repository: repository); _ = container
        let runtime = NFUniversalSessionRuntime(request: request())
        XCTAssertTrue(runtime.checkpointDraft(store: store)); runtime.acknowledgePresented(); runtime.numericValue = "12"
        let probe = NFAsyncSubmitProbe(transaction: 3, stage: .renamed); defer { probe.release() }
        repository.archiveWriteObserver = { probe.observe($0, $1) }
        let submit = Task { await runtime.submitInlineAsync(store: store) }
        let held = await probe.waitUntilHeld(); XCTAssertTrue(held)
        let original = try NFImmutableAttemptRecordSnapshot.encoded(NFImmutableAttemptRecordSnapshot(XCTUnwrap(store.attempts.first)))
        // The real file was renamed, but its containing directory now cannot be
        // opened for verification. No acknowledgement or candidate is fabricated.
        try FileManager.default.moveItem(at: folder, to: backup)
        probe.release(); await submit.value
        XCTAssertTrue(probe.stayedOffMain); XCTAssertTrue(repository.archiveWriteVerificationNeeded)
        let accepted = try XCTUnwrap(repository.archive.sessions.first)
        XCTAssertEqual(accepted.checkpoint.phase, .feedback)
        XCTAssertEqual(accepted.checkpoint.committedAttemptID, store.attempts.first?.id)
        XCTAssertEqual(runtime.stage, .confidence); XCTAssertTrue(runtime.correctness.isEmpty)
        XCTAssertTrue(runtime.hasPreparedCommit); XCTAssertFalse(runtime.canSubmit); XCTAssertFalse(runtime.canEditDraft)
        XCTAssertEqual(runtime.exitDisposition(store: store), .unacknowledged)
        runtime.next(store: store); runtime.endSession(store: store)
        let autosave = await runtime.checkpointDraftAsync(store: store); XCTAssertFalse(autosave)
        XCTAssertEqual(repository.archive.sessions.first?.checkpoint, accepted.checkpoint)
        XCTAssertEqual(repository.archive.sessions.first?.revision, accepted.revision)
        XCTAssertEqual(runtime.stage, .confidence); XCTAssertNotNil(runtime.saveError)
        try FileManager.default.moveItem(at: backup, to: folder)
        let cold = NFLocalSessionRepository(url: url, ownerDeviceID: owner)
        XCTAssertNil(cold.loadError); XCTAssertEqual(cold.archive.sessions.first?.checkpoint, accepted.checkpoint)
        repository.archiveWriteObserver = nil
        await runtime.retrySavingAsync(store: store)
        XCTAssertFalse(repository.archiveWriteVerificationNeeded)
        XCTAssertEqual(runtime.stage, .feedback); XCTAssertEqual(runtime.correctness.count, 1)
        XCTAssertEqual(repository.archive.sessions.first?.checkpoint, accepted.checkpoint)
        XCTAssertEqual(store.attempts.count, 1)
        XCTAssertEqual(try NFImmutableAttemptRecordSnapshot.encoded(NFImmutableAttemptRecordSnapshot(store.attempts[0])), original)
        await runtime.retrySavingAsync(store: store)
        XCTAssertEqual(runtime.correctness.count, 1); XCTAssertEqual(store.attempts.count, 1)
    }

    func testAsyncSourceReferenceDirectoryVerificationFailureNeverRevealsBeforeRepair() async throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "NFSubmit-Source-Verification-\(UUID())")
        let backup = folder.appendingPathExtension("held")
        defer { try? FileManager.default.removeItem(at: folder); try? FileManager.default.removeItem(at: backup) }
        let repository = NFLocalSessionRepository(url: folder.appending(path: "sessions.json"))
        let (store, container) = try makeStore(repository: repository); _ = container
        let chunk = NFSourceChunk(id: "verify-source", documentID: UUID(), documentVersion: 1,
            sourceName: "Private verified source.txt", locator: .init(page: nil, lineStart: 1, lineEnd: 1, section: nil),
            text: "The exact comparison remains behind verified acknowledgement.", contentHash: "verify-source", ordinal: 0, language: "en")
        let source = try NFSourceReviewExactAdapter.makeRequest(chunk: chunk, localeIdentifier: "en")
        let runtime = NFUniversalSessionRuntime(request: source)
        XCTAssertTrue(runtime.checkpointDraft(store: store)); runtime.acknowledgePresented()
        runtime.selfCheckReflection = "My independent recall before seeing the comparison."
        let probe = NFAsyncSubmitProbe(transaction: 1, stage: .renamed); defer { probe.release() }
        repository.archiveWriteObserver = { probe.observe($0, $1) }
        let reveal = Task { await runtime.submitInlineAsync(store: store) }
        let held = await probe.waitUntilHeld(); XCTAssertTrue(held)
        try FileManager.default.moveItem(at: folder, to: backup)
        probe.release(); await reveal.value
        XCTAssertTrue(probe.stayedOffMain); XCTAssertTrue(repository.archiveWriteVerificationNeeded)
        let accepted = try XCTUnwrap(repository.archive.sessions.first)
        XCTAssertEqual(accepted.checkpoint.phase, .selfCheckComparison)
        XCTAssertTrue(accepted.checkpoint.referenceRevealed)
        XCTAssertEqual(runtime.stage, .confidence); XCTAssertFalse(runtime.selfCheckReferenceRevealed)
        XCTAssertFalse(runtime.canRateSelfCheck); XCTAssertFalse(runtime.canSubmit); XCTAssertTrue(store.attempts.isEmpty)
        runtime.next(store: store); runtime.endSession(store: store)
        let autosave = await runtime.checkpointDraftAsync(store: store); XCTAssertFalse(autosave)
        XCTAssertEqual(runtime.prepareToClose(store: store), .unacknowledged)
        XCTAssertEqual(repository.archive.sessions.first?.checkpoint, accepted.checkpoint)
        XCTAssertEqual(repository.archive.sessions.first?.revision, accepted.revision)
        try FileManager.default.moveItem(at: backup, to: folder)
        repository.archiveWriteObserver = nil
        await runtime.retrySavingAsync(store: store)
        XCTAssertFalse(repository.archiveWriteVerificationNeeded)
        XCTAssertEqual(runtime.stage, .selfCheckComparison); XCTAssertTrue(runtime.selfCheckReferenceRevealed)
        XCTAssertTrue(store.attempts.isEmpty)
        XCTAssertEqual(repository.archive.sessions.first?.checkpoint, accepted.checkpoint)
        XCTAssertEqual(runtime.selfCheckReflection, "My independent recall before seeing the comparison.")
    }
}

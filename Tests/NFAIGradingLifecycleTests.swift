import Foundation
import SwiftData
import XCTest
@testable import NeuroForge

private actor NFAIGradeProviderProbe {
    private var continuation: CheckedContinuation<Void, Never>?
    private(set) var calls = 0
    private(set) var request: NFAIGradeRequest?
    func grade(_ request: NFAIGradeRequest) async -> NFAIGradeReceipt {
        calls += 1; self.request = request
        await withCheckedContinuation { continuation = $0 }
        return NFAIGradingLifecycleTests.receipt(request)
    }
    func release() { continuation?.resume(); continuation = nil }
    func waitUntilHeld() async -> Bool {
        for _ in 0..<300 {
            if continuation != nil { return true }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return false
    }
}

private final class NFAIJobWriteProbe: @unchecked Sendable {
    private let lock = NSLock()
    private let gate = DispatchSemaphore(value: 0)
    private var held = false
    private let stage: NFAIGradingJobStore.WriteStage
    init(_ stage: NFAIGradingJobStore.WriteStage) { self.stage = stage }
    func observe(_ stage: NFAIGradingJobStore.WriteStage) {
        guard stage == self.stage else { return }
        lock.lock(); held = true; lock.unlock()
        _ = gate.wait(timeout: .now() + 10)
    }
    func release() { gate.signal() }
    private var isHeld: Bool { lock.lock(); defer { lock.unlock() }; return held }
    func waitUntilHeld() async -> Bool {
        for _ in 0..<300 {
            if isHeld { return true }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return false
    }
}

@MainActor final class NFAIGradingLifecycleTests: XCTestCase {
    private enum Fault: Error { case unavailable }
    nonisolated static func receipt(_ request: NFAIGradeRequest, credit: Double = 1) -> NFAIGradeReceipt {
        NFAIGradeReceipt(id: UUID(), requestID: request.id, requestDigest: request.contentDigest, request: request,
            decision: .graded, criteria: request.exercise.aiRubric!.criteria.map {
                .init(criterionID: $0.id, credit: credit, explanation: "The stated mechanism addresses this criterion.",
                    responseEvidence: [request.answerText!], sourceChunkIDs: [])
            }, explanation: "The explanation preserves the required causal relationship.", nextStep: "Apply the same mechanism to another example.",
            providerIdentifier: "test-provider", modelIdentifier: "semantic-test-v1", routeIdentifier: "local",
            acceptedAt: Date(), reviewOf: request.reviewOf)
    }
    private func fixture() -> (NFAuthoringRequest, NFAuthoringResult) {
        let id = UUID()
        let request = NFAuthoringRequest(id: id, capability: .contextualize, lab: .scientificReasoning,
            field: .general, customTopic: "Heat transfer", learningObjective: "Explain a mechanism",
            style: .shortAnswer, difficulty: 0.3, count: 1, localeIdentifier: "en", seed: 29, aiMode: .automatic)
        let question = NFAuthoredQuestion(id: "semantic-answer-\(id)", lab: .scientificReasoning,
            style: .shortAnswer, prompt: "Why does an ice cube melt in a warm room?",
            context: "Consider energy transfer.", choices: [], correctAnswer: "Heat flows from the warmer room into the ice.",
            acceptedAnswers: [], explanation: "Energy transfer changes the phase of the ice.",
            hint: "Compare temperatures.", decisiveStep: "Identify the direction of heat flow.",
            difficulty: 0.3, citationChunkIDs: [], evidenceClass: .documentPractice)
        let result = NFAuthoringResult(questions: [question], provenance: .init(requestID: id,
            generatedAt: Date(), route: .deterministicFallback, routeReason: "Synthetic semantic fixture",
            promptVersion: NFAuthoringRequest.promptVersion, modelIdentifier: "synthetic.fixture",
            sourceChunkIDs: [], sourceDocumentIDs: [], validationVersion: NFAuthoringEngine.validationVersion,
            repairCount: 0, cacheKey: id.uuidString, isFallback: true), routeCandidates: [],
            validationStatus: .init(level: .schemaCheckedModelOutput, sourceSupport: .notApplicable), validationNotes: [])
        return (request, result)
    }
    private func store(_ repository: NFLocalSessionRepository) throws -> (AppStore, ModelContainer) {
        let container = try ModelContainer(for: Schema(NFSchemaV1.models), configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        return (AppStore(context: container.mainContext, localSessionRepository: repository, allowsSharedWidgetPublishing: false), container)
    }
    private func runtime(_ store: AppStore) throws -> AIGeneratedPracticeRuntime {
        let (request, result) = fixture()
        let runtime = AIGeneratedPracticeRuntime(result: result, request: request)
        runtime.configureFreshAIGrading(mode: .automatic)
        XCTAssertNotNil(runtime.exercise.aiRubric)
        XCTAssertTrue(runtime.checkpoint(store: store))
        runtime.acknowledgePresented(store: store)
        runtime.shortText = "The warmer air transfers energy into the ice."
        XCTAssertTrue(runtime.canSubmit)
        return runtime
    }
    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("NF-AI-Grade-\(UUID())")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }
    private func gradingRequest() throws -> NFAIGradeRequest {
        let (_, result) = fixture()
        let exercise = try NFAIExerciseFactory.shortResponse(from: result.questions[0].authoritativeExercise,
            reference: result.questions[0].correctAnswer)
        return .init(attemptID: UUID(), runID: UUID(), exercise: exercise,
            response: .shortText("The room supplies thermal energy to the ice."))
    }

    func testFreshSemanticContractDoesNotUpgradeAnAcceptedLegacyDraft() throws {
        let repository = NFLocalSessionRepository(), (store, container) = try store(repository); _ = container
        let (request, result) = fixture()
        let old = AIGeneratedPracticeRuntime(result: result, request: request)
        XCTAssertTrue(old.checkpoint(store: store))
        let saved = try XCTUnwrap(store.generatedPracticeDraft(for: request.id))
        old.configureFreshAIGrading(mode: .automatic)
        XCTAssertNil(old.exercise.aiRubric)
        old.finishClosing()
        let resumed = AIGeneratedPracticeRuntime(result: result, request: request, draft: saved)
        resumed.configureFreshAIGrading(mode: .automatic)
        XCTAssertEqual(resumed.exercise, saved.result.questions[0].authoritativeExercise)
        XCTAssertEqual(saved.schemaVersion, 1)
    }

    func testHeldProviderHasDurableExactPendingAnswerAndNoAttemptOrReference() async throws {
        let repository = NFLocalSessionRepository(), (store, container) = try store(repository); _ = container
        let runtime = try runtime(store), probe = NFAIGradeProviderProbe()
        runtime.gradeAnswer = { request, _ in await probe.grade(request) }
        let submitting = Task { await runtime.submitAsync(store: store) }
        let held = await probe.waitUntilHeld(); XCTAssertTrue(held)
        let saved = try XCTUnwrap(store.generatedPracticeDraft(for: runtime.result.provenance.requestID))
        XCTAssertEqual(saved.schemaVersion, 2); XCTAssertTrue(saved.valid)
        XCTAssertEqual(saved.aiGradingRequest?.response, .shortText("The warmer air transfers energy into the ice."))
        XCTAssertEqual(saved.aiGradingRequest?.attemptID, runtime.acceptedAttemptID)
        XCTAssertEqual(saved.aiGradingRequest?.slotID, runtime.acceptedSlotID?.uuidString)
        XCTAssertFalse(runtime.canEditDraft); XCTAssertFalse(runtime.canSubmit)
        XCTAssertEqual(runtime.stage, 0); XCTAssertNil(runtime.lastScore)
        XCTAssertFalse(runtime.selfCheckReferenceRevealed); XCTAssertTrue(store.attempts.isEmpty)
        XCTAssertFalse(runtime.draftSaveGate.isSaving)
        let checkpointed = await runtime.checkpointAsync(store: store); XCTAssertTrue(checkpointed)
        await probe.release(); await submitting.value
        XCTAssertEqual(runtime.stage, 2); XCTAssertEqual(store.attempts.count, 1)
    }

    func testAcceptedGradeUsesOneImmutableAttemptAndReplaysWithoutProvider() async throws {
        let repository = NFLocalSessionRepository(), (store, container) = try store(repository); _ = container
        let runtime = try runtime(store)
        runtime.gradeAnswer = { request, _ in Self.receipt(request) }
        await runtime.submitAsync(store: store)
        XCTAssertEqual(runtime.stage, 2); XCTAssertEqual(store.attempts.count, 1)
        let receipt = try XCTUnwrap(runtime.lastScore?.aiGrade)
        XCTAssertEqual(repository.archive.snapshots.first?.aiGrade, receipt)
        XCTAssertEqual(runtime.lastScore?.normalizedResponse, "The warmer air transfers energy into the ice.")
        let saved = try XCTUnwrap(store.generatedPracticeDraft(for: runtime.result.provenance.requestID))
        runtime.finishClosing()
        let resumed = AIGeneratedPracticeRuntime(result: saved.result, request: saved.request, draft: saved)
        resumed.gradeAnswer = { _, _ in XCTFail("Saved feedback must not call a provider"); throw Fault.unavailable }
        XCTAssertTrue(resumed.restoreCheckpoint(store: store, automaticallyRetryPrepared: false))
        await resumed.restoreAIGrading(store: store)
        XCTAssertEqual(resumed.lastScore?.aiGrade, receipt); XCTAssertEqual(store.attempts.count, 1)
    }

    func testNetworkFailureRetainsRequestForExplicitRetry() async throws {
        let repository = NFLocalSessionRepository(), (store, container) = try store(repository); _ = container
        let runtime = try runtime(store)
        runtime.gradeAnswer = { _, _ in throw Fault.unavailable }
        await runtime.submitAsync(store: store)
        let request = try XCTUnwrap(runtime.aiGradingRequest)
        XCTAssertEqual(runtime.aiGradingJob?.status, .pending)
        XCTAssertEqual(runtime.stage, 0); XCTAssertTrue(store.attempts.isEmpty)
        runtime.gradeAnswer = { next, _ in XCTAssertEqual(next, request); return Self.receipt(next) }
        await runtime.gradeAIAnswerAsync(store: store)
        XCTAssertEqual(runtime.stage, 2); XCTAssertEqual(runtime.lastScore?.aiGrade?.requestID, request.id)
        XCTAssertEqual(runtime.aiGradingJob?.dispatchCount, 2)
    }

    func testAcceptedSidecarSurvivesFailedPreparedCheckpointAndColdReplay() async throws {
        let directory = try temporaryDirectory(), owner = UUID()
        let repository = NFLocalSessionRepository(url: directory.appendingPathComponent("sessions.json"), ownerDeviceID: owner)
        let (store, container) = try store(repository)
        let runtime = try runtime(store)
        runtime.gradeAnswer = { request, _ in Self.receipt(request) }
        runtime.privateCheckpointWriteFailure = { if $0.stage == 1 { throw Fault.unavailable } }
        await runtime.submitAsync(store: store)
        XCTAssertTrue(store.attempts.isEmpty)
        let receipt = try XCTUnwrap(runtime.aiGradingJob?.receipt)
        let saved = try XCTUnwrap(store.generatedPracticeDraft(for: runtime.result.provenance.requestID))
        XCTAssertEqual(saved.stage, 0); XCTAssertEqual(saved.aiGradingRequest, receipt.request)
        runtime.finishClosing()
        let reopened = NFLocalSessionRepository(url: directory.appendingPathComponent("sessions.json"), ownerDeviceID: owner)
        let coldStore = AppStore(context: container.mainContext, localSessionRepository: reopened, allowsSharedWidgetPublishing: false)
        let resumed = AIGeneratedPracticeRuntime(result: saved.result, request: saved.request, draft: saved)
        resumed.gradeAnswer = { _, _ in XCTFail("An accepted sidecar must replay"); throw Fault.unavailable }
        XCTAssertTrue(resumed.restoreCheckpoint(store: coldStore, automaticallyRetryPrepared: false))
        await resumed.restoreAIGrading(store: coldStore)
        XCTAssertEqual(resumed.stage, 2); XCTAssertEqual(resumed.lastScore?.aiGrade, receipt)
        XCTAssertEqual(coldStore.attempts.count, 1)
    }

    func testCancelThenLateProviderResultCannotPublishGrade() async throws {
        let repository = NFLocalSessionRepository(), (store, container) = try store(repository); _ = container
        let runtime = try runtime(store), probe = NFAIGradeProviderProbe()
        runtime.gradeAnswer = { request, _ in await probe.grade(request) }
        let submitting = Task { await runtime.submitAsync(store: store) }
        let held = await probe.waitUntilHeld(); XCTAssertTrue(held)
        await runtime.cancelAIGrading(store: store)
        XCTAssertEqual(runtime.aiGradingJob?.status, .cancelled)
        await probe.release(); await submitting.value
        XCTAssertEqual(runtime.stage, 0); XCTAssertNil(runtime.lastScore)
        XCTAssertTrue(store.attempts.isEmpty); XCTAssertFalse(runtime.canEditDraft)
    }

    func testWriterTakeoverRejectsDelayedGradePublication() async throws {
        let repository = NFLocalSessionRepository(), (store, container) = try store(repository); _ = container
        let runtime = try runtime(store), probe = NFAIGradeProviderProbe()
        runtime.gradeAnswer = { request, _ in await probe.grade(request) }
        let submitting = Task { await runtime.submitAsync(store: store) }
        let held = await probe.waitUntilHeld(); XCTAssertTrue(held)
        let saved = try XCTUnwrap(store.generatedPracticeDraft(for: runtime.result.provenance.requestID))
        let next = AIGeneratedPracticeRuntime(result: saved.result, request: saved.request, draft: saved)
        next.takeOver(store: store, automaticallyRetryPrepared: false)
        XCTAssertTrue(next.ownsWriter); XCTAssertFalse(runtime.ownsWriter)
        await probe.release(); await submitting.value
        XCTAssertNil(runtime.lastScore); XCTAssertEqual(next.stage, 0); XCTAssertTrue(store.attempts.isEmpty)
    }

    func testReviewAppendsWithoutReplacingOriginalAttemptOrGrade() async throws {
        let repository = NFLocalSessionRepository(), (store, container) = try store(repository); _ = container
        let runtime = try runtime(store)
        runtime.gradeAnswer = { request, _ in Self.receipt(request, credit: 0) }
        await runtime.submitAsync(store: store)
        let original = try XCTUnwrap(runtime.savedAIGrade)
        let before = try JSONEncoder().encode(NFImmutableAttemptRecordSnapshot(XCTUnwrap(store.attempts.first)))
        runtime.gradeAnswer = { request, _ in Self.receipt(request, credit: 1) }
        await runtime.reviewAIGrade(reason: "My wording states the same direction of energy transfer.", store: store)
        XCTAssertEqual(runtime.savedAIGrade, original)
        XCTAssertEqual(runtime.aiGradeReview?.reviewOf, original.id)
        XCTAssertEqual(runtime.aiGradeReview?.criteria.first?.credit, 1)
        XCTAssertEqual(store.attempts.count, 1)
        XCTAssertEqual(try JSONEncoder().encode(NFImmutableAttemptRecordSnapshot(XCTUnwrap(store.attempts.first))), before)
        let saved = try XCTUnwrap(store.generatedPracticeDraft(for: runtime.result.provenance.requestID))
        XCTAssertEqual(saved.aiGradeReviews?.last?.receipt, runtime.aiGradeReview)
        XCTAssertEqual(saved.lastScore?.aiGrade, original)
    }

    func testUnavailableGradeCanUseDurableUnscoredReferenceFallback() async throws {
        let repository = NFLocalSessionRepository(), (store, container) = try store(repository); _ = container
        let runtime = try runtime(store)
        runtime.gradeAnswer = { _, _ in throw Fault.unavailable }
        await runtime.submitAsync(store: store)
        await runtime.comparePendingAIAnswer(store: store)
        XCTAssertTrue(runtime.isSolutionViewed); XCTAssertEqual(runtime.stage, 2)
        XCTAssertNil(runtime.lastScore); XCTAssertEqual(runtime.answeredActivityCount, 0)
        XCTAssertEqual(runtime.revealedActivityCount, 1)
        XCTAssertEqual(store.attempts.first?.evidenceWeight, 0)
    }

    func testJobOwnerRequestAndRevisionCASPreserveOriginalBytes() async throws {
        let directory = try temporaryDirectory(), jobs = NFAIGradingJobStore(directoryURL: directory)
        let request = try gradingRequest(), owner = UUID()
        let queued = try await jobs.create(request, ownerDeviceID: owner)
        let file = directory.appendingPathComponent("Grading/grade-\(request.id.uuidString.lowercased()).json")
        let original = try Data(contentsOf: file)
        do { _ = try await jobs.beginDispatch(request, ownerDeviceID: UUID(), expectedRevision: queued.revision); XCTFail() } catch {}
        do { _ = try await jobs.beginDispatch(request, ownerDeviceID: owner, expectedRevision: Int.max); XCTFail() } catch {}
        let changed = NFAIGradeRequest(id: request.id, attemptID: request.attemptID, runID: request.runID,
            exercise: request.exercise, response: .shortText("The opposite direction."), createdAt: request.createdAt)
        do { _ = try await jobs.create(changed, ownerDeviceID: owner); XCTFail() } catch {}
        XCTAssertEqual(try Data(contentsOf: file), original)
    }

    func testActualJobWorkerCancellationBeforeRenameKeepsOriginal() async throws {
        let directory = try temporaryDirectory(), jobs = NFAIGradingJobStore(directoryURL: directory)
        let request = try gradingRequest(), owner = UUID()
        let queued = try await jobs.create(request, ownerDeviceID: owner)
        let file = directory.appendingPathComponent("Grading/grade-\(request.id.uuidString.lowercased()).json")
        let original = try Data(contentsOf: file), probe = NFAIJobWriteProbe(.beforeCommit)
        defer { probe.release() }
        await jobs.setWriteObserver { probe.observe($0) }
        let write = Task { try await jobs.beginDispatch(request, ownerDeviceID: owner, expectedRevision: queued.revision) }
        let held = await probe.waitUntilHeld(); XCTAssertTrue(held)
        write.cancel(); probe.release()
        do { _ = try await write.value; XCTFail() } catch is CancellationError {} catch { XCTFail("\(error)") }
        XCTAssertEqual(try Data(contentsOf: file), original)
    }

    func testActualJobWorkerCancellationAfterRenameAdoptsReceipt() async throws {
        let directory = try temporaryDirectory(), jobs = NFAIGradingJobStore(directoryURL: directory)
        let request = try gradingRequest(), owner = UUID()
        let queued = try await jobs.create(request, ownerDeviceID: owner)
        let dispatch = try await jobs.beginDispatch(request, ownerDeviceID: owner, expectedRevision: queued.revision)
        let receipt = Self.receipt(request), probe = NFAIJobWriteProbe(.committed)
        defer { probe.release() }
        await jobs.setWriteObserver { probe.observe($0) }
        let write = Task { try await jobs.accept(receipt, for: request, ownerDeviceID: owner, expectedRevision: dispatch.revision) }
        let held = await probe.waitUntilHeld(); XCTAssertTrue(held)
        write.cancel(); probe.release()
        let accepted = try await write.value
        XCTAssertEqual(accepted.receipt, receipt)
        let reopened = NFAIGradingJobStore(directoryURL: directory)
        let saved = try await reopened.load(id: request.id, ownerDeviceID: owner)
        XCTAssertEqual(saved?.receipt, receipt)
        do { _ = try await reopened.cancel(request, ownerDeviceID: owner, expectedRevision: accepted.revision); XCTFail() } catch {}
    }
}

extension NFAIGradingLifecycleTests {
    func testUncertainEvaluationRemainsSavedWithoutZeroCreditOrFailedAttempt() async throws {
        let repository = NFLocalSessionRepository(), (store, container) = try store(repository); _ = container
        let runtime = try runtime(store)
        runtime.gradeAnswer = { request, _ in
            NFAIGradeReceipt(id: UUID(), requestID: request.id, requestDigest: request.contentDigest, request: request,
                decision: .needsClarification, criteria: [], explanation: "The explanation needs the direction of energy transfer.",
                nextStep: nil, providerIdentifier: "test-provider", modelIdentifier: "semantic-test-v1",
                routeIdentifier: "local", acceptedAt: Date(), reviewOf: nil)
        }
        await runtime.submitAsync(store: store)
        XCTAssertEqual(runtime.aiGradingJob?.status, .accepted)
        XCTAssertEqual(runtime.aiGradingJob?.receipt?.decision, .needsClarification)
        XCTAssertNil(runtime.lastScore); XCTAssertTrue(runtime.hasPendingAIGrade)
        XCTAssertTrue(store.attempts.isEmpty); XCTAssertTrue(runtime.correctness.isEmpty)
    }

    func testEndWhileProviderWaitsRetainsPendingRequestWithoutPublishingLateGrade() async throws {
        let repository = NFLocalSessionRepository(), (store, container) = try store(repository); _ = container
        let runtime = try runtime(store), probe = NFAIGradeProviderProbe()
        runtime.gradeAnswer = { request, _ in await probe.grade(request) }
        let submitting = Task { await runtime.submitAsync(store: store) }
        let held = await probe.waitUntilHeld(); XCTAssertTrue(held)
        let request = try XCTUnwrap(runtime.aiGradingRequest)
        await runtime.endSessionAsync(store: store)
        XCTAssertEqual(runtime.stage, 3); XCTAssertEqual(runtime.completedActivityCount, 0)
        let saved = try XCTUnwrap(store.generatedPracticeDrafts.first(where: { $0.id == runtime.runID })
            ?? store.localSessions.archive.privateStudyRuns?.first(where: { $0.id == runtime.runID })
                .flatMap { try? JSONDecoder().decode(NFGeneratedPracticeDraft.self, from: $0.payload) })
        XCTAssertEqual(saved.aiGradingRequest, request); XCTAssertTrue(saved.valid)
        await probe.release(); await submitting.value
        XCTAssertEqual(runtime.stage, 3); XCTAssertTrue(store.attempts.isEmpty)
    }

    func testReviewJournalSurvivesCompletionAndCannotRebindOriginalAnswer() async throws {
        let repository = NFLocalSessionRepository(), (store, container) = try store(repository); _ = container
        let runtime = try runtime(store)
        runtime.gradeAnswer = { request, _ in Self.receipt(request, credit: 0) }
        await runtime.submitAsync(store: store)
        let original = try XCTUnwrap(runtime.savedAIGrade)
        runtime.gradeAnswer = { request, _ in Self.receipt(request, credit: 1) }
        await runtime.reviewAIGrade(reason: "The energy direction is stated in different words.", store: store)
        let reviews = runtime.aiGradeReviews
        XCTAssertEqual(NFAIGradeReviewProjection.latestAcceptedReview(of: original, jobs: reviews)?.criteria.first?.credit, 1)
        await runtime.nextAsync(store: store)
        XCTAssertEqual(runtime.stage, 3)
        let record = try XCTUnwrap(repository.archive.privateStudyRuns?.first(where: { $0.id == runtime.runID }))
        let terminal = try JSONDecoder().decode(NFGeneratedPracticeDraft.self, from: record.payload)
        XCTAssertEqual(terminal.aiGradeReviews, reviews); XCTAssertTrue(terminal.valid)
        var forged = terminal
        forged.aiGradingRequest = NFAIGradeRequest(attemptID: original.request.attemptID, runID: original.request.runID,
            slotID: original.request.slotID, exercise: original.request.exercise,
            response: .shortText("The opposite claim."))
        XCTAssertFalse(forged.valid)
        XCTAssertEqual(repository.archive.snapshots.first?.aiGrade, original)
    }
}

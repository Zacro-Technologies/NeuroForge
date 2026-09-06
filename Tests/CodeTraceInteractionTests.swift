import XCTest
import SwiftData
@testable import NeuroForge

@MainActor final class CodeTraceInteractionTests: XCTestCase {
    private func exercise(policy: Int? = 1, purpose: NFExercisePurpose = .practice) throws -> NFExercise {
        try NFFallbackExerciseGenerator.generate(.init(seed: 604, index: 0, lab: .logicDebugging,
            purpose: purpose, localeIdentifier: "en", preferredAssessmentFormat: .stateTrace, tracePolicyVersion: policy))
    }
    private func makeStore(_ repository: NFLocalSessionRepository = NFLocalSessionRepository()) throws -> (AppStore, ModelContainer) {
        let container = try ModelContainer(for: Schema(NFSchemaV1.models), configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        return (AppStore(context: container.mainContext, localSessionRepository: repository), container)
    }
    private func runtime(exercise: NFExercise) throws -> NFUniversalSessionRuntime {
        var request = SessionRequest(lab: .logicDebugging, source: .focused, seed: 604,
            localeIdentifier: "en", requestedItemCount: 1, isTimed: false)
        request.tracePolicyVersion = 1
        request.localSessionID = UUID()
        request.localCheckpoint = try NFLocalItemCheckpoint.initial(request: request, exercise: exercise,
            slotID: UUID(), attemptID: UUID(), at: Date())
        request.freshlyAcceptedLaunch = true
        return NFUniversalSessionRuntime(request: request)
    }
    private func enterPrediction(_ runtime: NFUniversalSessionRuntime, correct: Bool = false) throws -> NFExerciseResponse {
        guard case let .logicState(schema) = runtime.exercise.interaction else { throw FixtureError.notTrace }
        runtime.logicState = correct ? schema.expectedFinalState : schema.initialState
        runtime.violatedRuleID = schema.expectedViolatedRuleID
        XCTAssertTrue(runtime.canSubmit, runtime.responseValidationMessage ?? "Trace prediction should be structurally valid")
        return .logicState(.init(finalState: runtime.logicState, violatedRuleID: runtime.violatedRuleID))
    }
    private enum FixtureError: Error { case notTrace }

    func testTraceUsesTheSameInterpreterAndExactNumberedSourceAcrossEverySkin() throws {
        let program: [NFPseudocodeStatement] = [
            .assign(name: "count", expression: .subtract(.variable("count"), .value(.integer(3)))),
            .ifThen(condition: .lessThanOrEqual(.variable("count"), .value(.integer(7))),
                body: [.assign(name: "ready", expression: .value(.boolean(true)))]),
            .assign(name: "count", expression: .add(.variable("count"), .value(.integer(2))))]
        let input: [String: NFPseudocodeValue] = ["count": .integer(10), "ready": .boolean(false)]
        for skin in NFPseudocodeDisplaySkin.allCases {
            let contract = try NFCodeTraceContract.make(program: program, initialVariables: input, skin: skin)
            let restored = try JSONDecoder().decode(NFCodeTraceContract.self, from: JSONEncoder().encode(contract))
            let steps = try restored.steps()
            XCTAssertEqual(steps.map(\.lineNumber), skin == .pythonLike ? [1, 2, 3, 4] : [1, 2, 3, 5])
            XCTAssertEqual(steps[0].variables, ["count": .integer(7), "ready": .boolean(false)])
            XCTAssertEqual(steps[2].variables, ["count": .integer(7), "ready": .boolean(true)])
            XCTAssertEqual(steps.last?.variables, try NFRestrictedPseudocodeInterpreter.execute(program, initialVariables: input).variables)
            XCTAssertEqual(restored.source, NFPseudocodeRenderer.render(program, skin: skin))
        }
    }

    func testFalseBranchLoopAndArithmeticBoundsRemainInterpreterTruthful() throws {
        let program: [NFPseudocodeStatement] = [
            .ifThen(condition: .value(.boolean(false)), body: [.assign(name: "x", expression: .value(.integer(99)))]),
            .whileLoop(condition: .lessThan(.variable("x"), .value(.integer(2))), iterationLimit: 3,
                body: [.assign(name: "x", expression: .add(.variable("x"), .value(.integer(1))))])]
        let trace = try NFCodeTraceContract.make(program: program, initialVariables: ["x": .integer(0)], skin: .swiftLike)
        XCTAssertEqual(try trace.steps().last?.variables["x"], .integer(2))
        XCTAssertFalse(try trace.steps().contains { $0.variables["x"] == .integer(99) })
        XCTAssertThrowsError(try NFRestrictedPseudocodeInterpreter.execute([
            .assign(name: "x", expression: .add(.value(.integer(Int.max)), .value(.integer(1))))])) {
                XCTAssertEqual($0 as? NFPseudocodeRuntimeError, .integerOverflow)
            }
        XCTAssertFalse(NFCodeTraceContract.hasBoundedJSONDepth(Data((String(repeating: "[", count: 33) + String(repeating: "]", count: 33)).utf8)))
        var future = trace; future.schemaVersion = 99
        XCTAssertThrowsError(try future.steps())
    }

    func testOnlyExplicitNewRecipeAddsTraceAndLegacyRecipeRemainsStatic() throws {
        let legacy = try exercise(policy: nil), current = try exercise()
        XCTAssertEqual(legacy.generatorVersion, 4)
        XCTAssertNil(NFCodeTraceProjection.make(exercise: legacy))
        XCTAssertEqual(current.generatorVersion, 5)
        XCTAssertNotEqual(current.id, legacy.id, "Opted-in trace and legacy recipes retain distinct identities")
        XCTAssertNotNil(NFCodeTraceProjection.make(exercise: current))
        XCTAssertEqual(legacy.interaction, current.interaction)
        XCTAssertEqual(legacy.prompt, current.prompt)
        XCTAssertEqual(NFQuestionFingerprint.fingerprint(for: legacy), NFQuestionFingerprint.fingerprint(for: current),
            "An inspection control does not make repeated question content fresh")
        XCTAssertThrowsError(try exercise(policy: 99))
        var request = SessionRequest(lab: .logicDebugging, source: .focused, seed: 604)
        XCTAssertNil(request.launchOnly().tracePolicyVersion)
        request.tracePolicyVersion = 1
        XCTAssertEqual(request.launchOnly().tracePolicyVersion, 1)
        let restored = try JSONDecoder().decode(SessionRequest.self, from: JSONEncoder().encode(request))
        XCTAssertEqual(restored.tracePolicyVersion, 1)
    }

    func testPredictionMustExistAndFailedFirstRevealCannotShowOrRecordExecution() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "NFTrace-\(UUID())")
        let backup = folder.appendingPathExtension("retained")
        defer { try? FileManager.default.removeItem(at: folder); try? FileManager.default.removeItem(at: backup) }
        let repo = NFLocalSessionRepository(url: folder.appending(path: "Sessions.json"))
        let (store, container) = try makeStore(repo); defer { _ = container }
        let runtime = try runtime(exercise: exercise())
        XCTAssertTrue(runtime.checkpointDraft(store: store)); runtime.acknowledgePresented()
        runtime.inspectCode(.next, store: store)
        XCTAssertNil(runtime.traceInspection)
        let prediction = try enterPrediction(runtime)
        XCTAssertTrue(runtime.checkpointDraft(store: store))
        try FileManager.default.moveItem(at: folder, to: backup)
        try Data("blocked".utf8).write(to: folder)
        runtime.inspectCode(.next, store: store)
        XCTAssertNil(runtime.traceInspection)
        XCTAssertFalse(runtime.assistanceEvents.contains { $0.kind == .codeTrace })
        XCTAssertNotNil(runtime.saveError)
        XCTAssertTrue(store.attempts.isEmpty)
        try FileManager.default.removeItem(at: folder)
        try FileManager.default.moveItem(at: backup, to: folder)
        runtime.inspectCode(.next, store: store)
        XCTAssertNil(runtime.saveError)
        XCTAssertEqual(runtime.traceInspection?.prediction, prediction)
        XCTAssertEqual(runtime.traceInspection?.cursor, 1)
        XCTAssertEqual(repo.archive.sessions.first?.checkpoint.traceInspection, runtime.traceInspection)
        XCTAssertEqual(runtime.capturedSupportCount, 1)
        XCTAssertEqual(runtime.hintCount, 0, "Trace support must not skip the first ordinary hint ladder rung")
    }

    func testExactColdResumeResetAndLaterCommitKeepFirstPredictionAndImmutableHistory() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "NFTraceResume-\(UUID())")
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appending(path: "Sessions.json"), owner = UUID()
        let (store, container) = try makeStore(NFLocalSessionRepository(url: url, ownerDeviceID: owner)); defer { _ = container }
        let runtime = try runtime(exercise: exercise())
        XCTAssertTrue(runtime.checkpointDraft(store: store)); runtime.acknowledgePresented()
        let original = try enterPrediction(runtime)
        runtime.inspectCode(.next, store: store); runtime.inspectCode(.next, store: store)
        let saved = try XCTUnwrap(runtime.traceInspection), exact = runtime.exercise
        runtime.finishClosing()
        let reopened = NFLocalSessionRepository(url: url, ownerDeviceID: owner)
        let (restoredStore, restoredContainer) = try makeStore(reopened); defer { _ = restoredContainer }
        XCTAssertTrue(restoredStore.resumeSession(runtime.sessionID))
        let resumed = NFUniversalSessionRuntime(request: try XCTUnwrap(restoredStore.activeSessionRequest))
        XCTAssertEqual(resumed.exercise, exact); XCTAssertEqual(resumed.traceInspection, saved)
        resumed.resume(); XCTAssertTrue(resumed.checkpointDraft(store: restoredStore)); resumed.acknowledgePresented()
        resumed.inspectCode(.previous, store: restoredStore)
        XCTAssertEqual(resumed.traceInspection?.cursor, 1)
        resumed.inspectCode(.reset, store: restoredStore)
        XCTAssertEqual(resumed.traceInspection?.cursor, 0)
        XCTAssertEqual(resumed.traceInspection?.revealedStepCount, 2)
        XCTAssertEqual(resumed.traceInspection?.prediction, original)
        _ = try enterPrediction(resumed, correct: true)
        resumed.submitInline(store: restoredStore)
        XCTAssertEqual(resumed.stage, .feedback)
        let attempt = try XCTUnwrap(restoredStore.attempts.first)
        let history = try XCTUnwrap(reopened.archive.snapshots.first { $0.attemptID == attempt.id })
        XCTAssertEqual(history.exercise, exact)
        XCTAssertEqual(history.traceInspection?.prediction, original)
        XCTAssertEqual(attempt.hintCount, 1)
        let committed = history.traceInspection
        resumed.inspectCode(.next, store: restoredStore); resumed.inspectCode(.reset, store: restoredStore)
        XCTAssertEqual(resumed.traceInspection, committed)
        XCTAssertEqual(restoredStore.attempts.count, 1)
        XCTAssertEqual(reopened.archive.snapshots.first?.traceInspection, committed)
    }

    func testProtectedAndFutureInspectionCannotExposeAStateOrBecomeEditable() throws {
        let protected = try exercise(purpose: .assessmentHoldout)
        XCTAssertTrue(protected.assessmentProtected)
        XCTAssertNil(NFCodeTraceProjection.make(exercise: protected))
        let exact = try exercise()
        let runtime = try runtime(exercise: exact)
        let (store, container) = try makeStore(); defer { _ = container }
        XCTAssertTrue(runtime.checkpointDraft(store: store))
        _ = try enterPrediction(runtime)
        runtime.inspectCode(.next, store: store)
        var checkpoint = try XCTUnwrap(store.localSessions.archive.sessions.first?.checkpoint)
        checkpoint.traceInspection?.schemaVersion = 99
        var request = runtime.request
        request.localCheckpoint = checkpoint
        let future = NFUniversalSessionRuntime(request: request)
        XCTAssertNotNil(future.unavailableReason)
        XCTAssertFalse(future.canEditDraft)
        XCTAssertNil(future.traceInspection)
        XCTAssertEqual(checkpoint.response, store.localSessions.archive.sessions.first?.checkpoint.response)
    }

    func testGeneratedTypedTraceUsesTheSamePredictionCheckpointAndHistoryPolicy() async throws {
        let exact = try exercise(purpose: .documentPractice)
        guard case let .logicState(schema) = exact.interaction else { return XCTFail("Expected trace schema") }
        let request = NFAuthoringRequest(capability: .contextualize, lab: .logicDebugging, field: .computing,
            customTopic: "trace", learningObjective: "trace state", style: .shortAnswer, difficulty: 0.5,
            count: 1, seed: 604, aiMode: .disabled)
        let template = try await NFAuthoringEngine.shared.author(request)
        let question = NFAuthoredQuestion(id: exact.id, lab: exact.lab, style: .shortAnswer,
            prompt: exact.prompt, context: exact.contextText ?? "", choices: [],
            correctAnswer: schema.expectedFinalState.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: ","),
            acceptedAnswers: [], explanation: exact.feedback.correctExplanation,
            hint: exact.feedback.hintLadder.first ?? "", decisiveStep: exact.feedback.decisiveStep,
            difficulty: 0.5, citationChunkIDs: [], evidenceClass: .documentPractice, authoritativeExercise: exact)
        XCTAssertTrue(NFAuthoredExerciseAuthority.validatesBinding(question))
        let result = NFAuthoringResult(questions: [question], provenance: template.provenance,
            routeCandidates: template.routeCandidates, validationStatus: template.validationStatus, validationNotes: [])
        let (store, container) = try makeStore(); defer { _ = container }
        let runtime = AIGeneratedPracticeRuntime(result: result, request: request)
        XCTAssertTrue(runtime.checkpoint(store: store))
        runtime.logicState = schema.initialState; runtime.violatedRuleID = schema.expectedViolatedRuleID
        XCTAssertTrue(runtime.canSubmit)
        runtime.inspectCode(.next, store: store)
        let saved = try XCTUnwrap(store.generatedPracticeDraft(for: result.provenance.requestID))
        XCTAssertEqual(saved.traceInspection, runtime.traceInspection)
        runtime.finishClosing()
        let resumed = AIGeneratedPracticeRuntime(result: result, request: request, draft: saved)
        XCTAssertTrue(resumed.restoreCheckpoint(store: store)); resumed.resume()
        XCTAssertEqual(resumed.traceInspection, saved.traceInspection)
        resumed.logicState = schema.expectedFinalState
        resumed.submit(store: store)
        XCTAssertEqual(resumed.stage, 2)
        let attempt = try XCTUnwrap(store.attempts.first)
        XCTAssertEqual(attempt.evidenceWeight, 0)
        XCTAssertEqual(attempt.hintCount, 1)
        XCTAssertEqual(store.localSessions.archive.snapshots.first?.traceInspection?.prediction, saved.traceInspection?.prediction)
        let committed = resumed.traceInspection
        resumed.inspectCode(.reset, store: store)
        XCTAssertEqual(resumed.traceInspection, committed)
    }
    func testNextStatePredictionIsRetainedBeforeRevealAndInvalidSyntaxNeverAdvances() throws {
        let (store, container) = try makeStore(); defer { _ = container }
        let runtime = try runtime(exercise: exercise())
        XCTAssertTrue(runtime.checkpointDraft(store: store))
        _ = try enterPrediction(runtime)
        runtime.inspectCode(.next, store: store)
        runtime.inspectCode(.predict("count", "nine"), store: store)
        runtime.inspectCode(.predict("ready", "true"), store: store)
        let before = runtime.traceInspection
        XCTAssertEqual(store.localSessions.archive.sessions.first?.checkpoint.traceInspection?.nextStatePrediction?["count"], "nine")
        runtime.inspectCode(.next, store: store)
        XCTAssertEqual(runtime.traceInspection, before)
        XCTAssertTrue(store.attempts.isEmpty)
        XCTAssertTrue(runtime.recoveryText.contains("nine"))
        runtime.inspectCode(.predict("count", "42"), store: store)
        runtime.inspectCode(.next, store: store)
        XCTAssertEqual(runtime.traceInspection?.cursor, 2)
        XCTAssertEqual(runtime.traceInspection?.statePredictions?.last?.values, ["count": "42", "ready": "true"])
        XCTAssertEqual(runtime.traceInspection?.statePredictions?.last?.step, 2)
        runtime.inspectCode(.reset, store: store)
        XCTAssertEqual(runtime.traceInspection?.statePredictions?.count, 1, "Reset cannot erase a recorded prediction")
    }

    func testImmutableTraceSnapshotRejectsAnotherPredictionUnderTheSameAttemptID() throws {
        let exact = try exercise()
        guard case let .logicState(schema) = exact.interaction else { return XCTFail("Expected state") }
        let original = try NFTraceInspectionDraft.begin(exercise: exact, prediction: .logicState(.init(finalState: schema.initialState, violatedRuleID: schema.expectedViolatedRuleID)))
        let different = try NFTraceInspectionDraft.begin(exercise: exact, prediction: .logicState(.init(finalState: schema.expectedFinalState, violatedRuleID: schema.expectedViolatedRuleID)))
        let repository = NFLocalSessionRepository(), id = UUID()
        try repository.retainSnapshot(attemptID: id, exercise: exact, traceInspection: original)
        XCTAssertThrowsError(try repository.retainSnapshot(attemptID: id, exercise: exact, traceInspection: different))
        XCTAssertEqual(repository.archive.snapshots.first?.traceInspection, original)
        XCTAssertEqual(repository.archive.snapshots.count, 1)
    }

    func testUnacknowledgedTypedNextPredictionStaysVisibleAndExportable() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "NFTraceEdit-\(UUID())")
        let backup = folder.appendingPathExtension("retained")
        defer { try? FileManager.default.removeItem(at: folder); try? FileManager.default.removeItem(at: backup) }
        let repo = NFLocalSessionRepository(url: folder.appending(path: "Sessions.json"))
        let (store, container) = try makeStore(repo); defer { _ = container }
        let runtime = try runtime(exercise: exercise())
        XCTAssertTrue(runtime.checkpointDraft(store: store))
        _ = try enterPrediction(runtime)
        runtime.inspectCode(.next, store: store)
        let acknowledged = runtime.traceInspection
        try FileManager.default.moveItem(at: folder, to: backup)
        try Data("blocked".utf8).write(to: folder)
        runtime.inspectCode(.predict("count", "my unsaved next-state prediction"), store: store)
        XCTAssertEqual(runtime.traceInspection?.nextStatePrediction?["count"], "my unsaved next-state prediction")
        XCTAssertEqual(repo.archive.sessions.first?.checkpoint.traceInspection, acknowledged)
        XCTAssertTrue(runtime.recoveryText.contains("my unsaved next-state prediction"))
        XCTAssertEqual(runtime.prepareToClose(store: store), .unacknowledged)
        XCTAssertEqual(runtime.traceInspection?.cursor, 1)
        XCTAssertTrue(store.attempts.isEmpty)
    }

    func testOversizedPendingAndRecordedStatePredictionsAreRejectedWithoutTruncation() throws {
        let exact = try exercise()
        let projection = try XCTUnwrap(NFCodeTraceProjection.make(exercise: exact))
        guard case let .logicState(schema) = exact.interaction else { throw FixtureError.notTrace }
        let prediction = NFExerciseResponse.logicState(.init(finalState: schema.initialState, violatedRuleID: schema.expectedViolatedRuleID))
        var draft = try NFTraceInspectionDraft.begin(exercise: exact, prediction: prediction)
        let oversized = String(repeating: " ", count: 501)
        draft.predict(variable: "count", value: oversized, in: projection)
        XCTAssertFalse(draft.isValid(for: exact))
        XCTAssertFalse(draft.canAdvance(in: projection), "Even whitespace cannot bypass the retained-text bound.")
        draft.next(in: projection)
        XCTAssertEqual(draft.cursor, 1)
        XCTAssertEqual(draft.nextStatePrediction?["count"], oversized)
        XCTAssertEqual(try JSONDecoder().decode(NFTraceInspectionDraft.self, from: JSONEncoder().encode(draft)).nextStatePrediction?["count"], oversized)
        draft.nextStatePrediction = nil
        draft.statePredictions = [.init(step: 2, values: ["count": String(repeating: " ", count: 500) + "1", "ready": "true"])]
        XCTAssertFalse(draft.isValid(for: exact), "A trimmed parseable integer cannot smuggle oversized saved prediction text.")
    }

    func testOversizedTraceEditStaysExportableAndCannotClaimSavedUntilCorrected() throws {
        let repo = NFLocalSessionRepository()
        let (store, container) = try makeStore(repo); defer { _ = container }
        let runtime = try runtime(exercise: exercise())
        XCTAssertTrue(runtime.checkpointDraft(store: store)); runtime.acknowledgePresented()
        _ = try enterPrediction(runtime)
        runtime.inspectCode(.next, store: store)
        let acknowledged = runtime.traceInspection
        let oversized = String(repeating: "9", count: 501)
        runtime.inspectCode(.predict("count", oversized), store: store)
        XCTAssertEqual(runtime.traceInspection?.nextStatePrediction?["count"], oversized)
        XCTAssertEqual(repo.archive.sessions.first?.checkpoint.traceInspection, acknowledged)
        XCTAssertEqual(runtime.saveError, NFTraceInspectionDraft.oversizedPredictionMessage)
        XCTAssertFalse(runtime.canSubmit)
        XCTAssertTrue(runtime.recoveryText.contains(oversized))
        XCTAssertEqual(runtime.prepareToClose(store: store), .unacknowledged)
        XCTAssertTrue(store.attempts.isEmpty)
        runtime.resume()
        runtime.inspectCode(.predict("count", "2"), store: store)
        XCTAssertNil(runtime.saveError)
        XCTAssertEqual(repo.archive.sessions.first?.checkpoint.traceInspection?.nextStatePrediction?["count"], "2")
        XCTAssertEqual(runtime.traceInspection?.cursor, 1)
    }

}

import Foundation
import SwiftData
import XCTest
@testable import NeuroForge

@MainActor
final class SessionWorkloadBudgetTests: XCTestCase {
    private func store(repository: NFLocalSessionRepository? = nil) throws -> (AppStore, ModelContainer) {
        let container = try ModelContainer(for: Schema(NFSchemaV1.models), configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        return (AppStore(context: container.mainContext, localSessionRepository: repository ?? NFLocalSessionRepository()), container)
    }
    private func request(count: Int? = 5, minutes: Int? = nil, timing: NFSessionTimingCondition? = nil) -> SessionRequest {
        .init(lab: .mentalMath, source: .focused, seed: 20260904, localeIdentifier: "en",
            requestedMinutes: minutes, preferredMentalMathKind: .multiplication,
            requestedItemCount: count, isTimed: timing?.mode != .untimed && timing != nil, timingCondition: timing, mechanicID: "mentalMath.mentalCalculation")
    }
    private func fill(_ runtime: NFUniversalSessionRuntime) {
        switch runtime.exercise.interaction {
        case let .numeric(s): runtime.numericValue = String(s.answer.value); runtime.numericUnit = s.answer.canonicalUnit ?? ""
        case let .singleChoice(s): runtime.singleChoiceID = s.correctOptionID
        case let .multipleChoice(s): runtime.multipleChoiceIDs = Set(s.correctOptionIDs)
        case let .orderedSteps(s): runtime.orderedStepIDs = s.correctOrder
        case let .shortText(s): runtime.shortText = s.expectedAnswer
        case let .selfCheck(s): runtime.selfCheckReflection = s.referenceAnswer
        case let .claimEvidence(s): runtime.claimSelections = Dictionary(uniqueKeysWithValues: s.correctPairs.map { ($0.claimID, Set($0.evidenceIDs)) })
        case let .logicState(s): runtime.logicState = s.expectedFinalState; runtime.violatedRuleID = s.expectedViolatedRuleID
        }
    }

    func testElapsedOnlyAndUntimedSwitchPreserveExactDraftReceiptAndConfidenceThenResume() throws {
        let (store, container) = try store(); defer { _ = container }
        var now = 0.0
        let runtime = NFUniversalSessionRuntime(request: request(count: 2, minutes: 1, timing: .init(.untimed)), monotonicNow: { now })
        XCTAssertTrue(runtime.checkpointDraft(store: store)); runtime.acknowledgePresented()
        fill(runtime); runtime.scratchpad = "Retained exact scratchpad"
        runtime.chooseConfidence(.fairlyConfident)
        let originalExercise = runtime.exercise, response = runtime.readableAnswer
        let confidence = runtime.selectedConfidence, invitation = runtime.confidenceInvitation
        let originalConfig = try NFLocalReservationBridge.configurationDigest(runtime.request)
        let originalSlots = store.localSessions.archive.selectionLedger?.slots
        now = 75
        runtime.setDisplayTiming(.elapsedOnly, store: store)
        XCTAssertTrue(runtime.showsTimer); XCTAssertFalse(runtime.usesTimedMode)
        XCTAssertEqual(runtime.workloadMode, .practice)
        XCTAssertNotEqual(runtime.timerLabel(), "Time target reached", "Elapsed time has no academic countdown")
        XCTAssertEqual(runtime.exercise, originalExercise); XCTAssertEqual(runtime.readableAnswer, response)
        XCTAssertEqual(runtime.selectedConfidence, confidence); XCTAssertEqual(runtime.confidenceInvitation, invitation)
        runtime.setDisplayTiming(.untimed, store: store)
        XCTAssertFalse(runtime.showsTimer); XCTAssertEqual(runtime.timerLabel(), "Untimed")
        runtime.setDisplayTiming(.elapsedOnly, store: store)
        XCTAssertEqual(try NFLocalReservationBridge.configurationDigest(runtime.request), originalConfig)
        XCTAssertEqual(store.localSessions.archive.selectionLedger?.slots, originalSlots)
        let saved = try XCTUnwrap(store.localSessions.archive.sessions.first)
        XCTAssertEqual(saved.request.timingCondition?.mode, .untimed)
        XCTAssertEqual(saved.checkpoint.timingConditionOverride?.mode, .elapsedOnly)
        let bytes = try JSONEncoder().encode(saved)
        let decoded = try JSONDecoder().decode(NFLocalSessionEnvelope.self, from: bytes)
        var resumed = decoded.request; resumed.localSessionID = decoded.id; resumed.localCheckpoint = decoded.checkpoint
        runtime.releaseWriter(); now = 100_000
        let restored = NFUniversalSessionRuntime(request: resumed, monotonicNow: { now })
        XCTAssertTrue(restored.checkpointDraft(store: store)); restored.resume()
        XCTAssertEqual(restored.exercise, originalExercise); XCTAssertEqual(restored.readableAnswer, response)
        XCTAssertEqual(restored.scratchpad, "Retained exact scratchpad")
        XCTAssertTrue(restored.usesElapsedOnly); XCTAssertFalse(restored.usesTimedMode)
        now += 5; restored.submitInline(store: store)
        let answer = try XCTUnwrap(store.attempts.first)
        XCTAssertEqual(answer.deterministicCredit, 1); XCTAssertFalse(answer.wasTimed)
        XCTAssertEqual(answer.activeDurationSeconds, 80, accuracy: 0.001)
    }

    func testLegacyBooleanTimingRequestKeepsItsSavedSemanticsWhileNewElapsedIsDisplayOnly() throws {
        let legacy = SessionRequest(lab: .mentalMath, source: .focused, seed: 20260904,
            localeIdentifier: "en", requestedItemCount: 1, isTimed: true, mechanicID: "mentalMath.mentalCalculation")
        let bytes = try JSONEncoder().encode(legacy)
        let restored = try JSONDecoder().decode(SessionRequest.self, from: bytes)
        XCTAssertNil(restored.timingCondition)
        let runtime = NFUniversalSessionRuntime(request: restored)
        XCTAssertEqual(runtime.usesTimedMode, runtime.exercise.timingEligible)
        let elapsed = NFUniversalSessionRuntime(request: request(timing: .init(.elapsedOnly)))
        XCTAssertTrue(elapsed.showsTimer); XCTAssertFalse(elapsed.usesTimedMode)
        XCTAssertEqual(elapsed.request.launchOnly().timingCondition, .init(.elapsedOnly))
    }

    func testFutureTimingAndHugeOrNegativeDurationsRetainRecoveryPayloadWithoutNumericTraps() throws {
        let (store, container) = try store(); defer { _ = container }
        let runtime = NFUniversalSessionRuntime(request: request(timing: .init(.untimed)))
        XCTAssertTrue(runtime.checkpointDraft(store: store))
        let original = try XCTUnwrap(store.localSessions.archive.sessions.first)
        runtime.releaseWriter()
        var cases: [NFLocalSessionEnvelope] = []
        var future = original
        future.checkpoint.timingConditionOverride = .init(.elapsedOnly)
        future.checkpoint.timingConditionOverride?.schemaVersion = 999
        cases.append(future)
        for value in [-1.0, 1e300] {
            for field in 0..<4 {
                var bad = original
                switch field {
                case 0: bad.checkpoint.cumulativeActiveDuration = value
                case 1: bad.checkpoint.itemActiveDuration = value
                case 2: bad.checkpoint.assessmentPracticeDuration = value
                default: bad.checkpoint.sittingActiveDuration = value
                }
                cases.append(bad)
            }
        }
        for bad in cases {
            var archive = store.localSessions.archive; archive.sessions = [bad]
            let destination = NFLocalSessionRepository(ownerDeviceID: store.localSessions.ownerDeviceID)
            let encoded = try JSONEncoder().encode(archive)
            let decoded = try JSONDecoder().decode(NFLocalSessionRepository.Archive.self, from: encoded)
            try destination.importArchive(decoded)
            let preserved = try XCTUnwrap(destination.archive.sessions.first)
            XCTAssertEqual(preserved.status, .migrationRecovery)
            XCTAssertEqual(preserved.checkpoint.cumulativeActiveDuration, bad.checkpoint.cumulativeActiveDuration)
            var request = preserved.request; request.localSessionID = preserved.id; request.localCheckpoint = preserved.checkpoint
            let recovered = NFUniversalSessionRuntime(request: request)
            XCTAssertNotNil(recovered.unavailableReason)
            XCTAssertFalse(recovered.checkpointDraft(store: store))
        }
        let corruptLegacy = SessionRequest(lab: .mentalMath, source: .focused, seed: 1,
            requestedItemCount: 1, resumedActiveDurationSeconds: 1e300)
        XCTAssertEqual(corruptLegacy.resumedActiveDurationSeconds, 1e300)
        XCTAssertNotNil(NFUniversalSessionRuntime(request: corruptLegacy).unavailableReason)
    }

    func testClocksBeginOnlyAtDurablePresentationAndSeparateConfidenceAndFeedback() throws {
        let (store, container) = try store(); defer { _ = container }
        var now = 100.0
        let runtime = NFUniversalSessionRuntime(request: request(), monotonicNow: { now })
        now = 150
        runtime.acknowledgePresented()
        XCTAssertEqual(runtime.sittingActiveElapsed(), 0)
        XCTAssertTrue(runtime.checkpointDraft(store: store))
        now = 200
        runtime.acknowledgePresented()
        now = 220
        runtime.beginConfidenceInteraction()
        now = 227
        runtime.chooseConfidence(.uncertain)
        now = 232
        fill(runtime); runtime.submitInline(store: store)
        XCTAssertEqual(runtime.stage, .feedback)
        XCTAssertEqual(try XCTUnwrap(store.attempts.first).activeDurationSeconds, 25, accuracy: 0.001)
        now = 245
        XCTAssertEqual(runtime.sittingActiveElapsed(), 45, accuracy: 0.001)
        XCTAssertTrue(runtime.checkpointDraft(store: store))
        XCTAssertEqual(try XCTUnwrap(store.localSessions.archive.sessions.first?.checkpoint.sittingActiveDuration), 45, accuracy: 0.001)
    }

    func testPauseAndRelaunchPreserveKnownAnswerAndSittingChunksWithoutClockGap() throws {
        let (store, container) = try store(); defer { _ = container }
        var now = 100.0
        let runtime = NFUniversalSessionRuntime(request: request(), monotonicNow: { now })
        XCTAssertTrue(runtime.checkpointDraft(store: store)); runtime.acknowledgePresented()
        now += 20; runtime.pause()
        XCTAssertTrue(runtime.checkpointDraft(store: store)); runtime.releaseWriter()
        XCTAssertTrue(store.resumeSession(runtime.sessionID))
        now = 100_000
        let restored = NFUniversalSessionRuntime(request: try XCTUnwrap(store.activeSessionRequest), monotonicNow: { now })
        XCTAssertTrue(restored.checkpointDraft(store: store)); restored.resume()
        now += 5; fill(restored); restored.submitInline(store: store)
        XCTAssertEqual(try XCTUnwrap(store.attempts.first).activeDurationSeconds, 25, accuracy: 0.001)
        XCTAssertEqual(restored.sittingActiveElapsed(), 25, accuracy: 0.001)
        XCTAssertFalse(restored.answerDurationComplete)
    }

    func testUnknownDurationLaunchOffersExplicitCountAlternativeWithoutSavingAnExposure() throws {
        let (store, container) = try store(); defer { _ = container }
        let runtime = NFUniversalSessionRuntime(request: request(count: nil, minutes: 3))
        XCTAssertTrue(runtime.durationChoiceRequired)
        XCTAssertFalse(runtime.checkpointDraft(store: store))
        XCTAssertTrue(store.localSessions.archive.sessions.isEmpty)
        runtime.startCountBasedAlternative(store: store)
        let alternate = try XCTUnwrap(store.activeSessionRequest)
        XCTAssertEqual(alternate.requestedItemCount, 5)
        XCTAssertNil(alternate.requestedMinutes)
        XCTAssertNotEqual(alternate.id, runtime.request.id)
        XCTAssertNotNil(alternate.localSessionID)
        XCTAssertEqual(alternate.localCheckpoint?.itemCount, 5)
        XCTAssertEqual(alternate.localCheckpoint?.phase, .item)
        XCTAssertTrue(alternate.freshlyAcceptedLaunch == true)
        XCTAssertFalse(NFUniversalSessionRuntime(request: alternate).durationChoiceRequired)
    }

    func testExplicitFixedCountSurvivesAdvisoryTimeTargetWithoutAutoSubmitting() throws {
        let (store, container) = try store(); defer { _ = container }
        var now = 0.0
        let runtime = NFUniversalSessionRuntime(request: request(count: 2, minutes: 1), monotonicNow: { now })
        XCTAssertTrue(runtime.checkpointDraft(store: store)); runtime.acknowledgePresented()
        fill(runtime); now = 180
        XCTAssertEqual(runtime.stage, .item)
        XCTAssertTrue(store.attempts.isEmpty)
        runtime.submitInline(store: store); runtime.next(store: store)
        XCTAssertEqual(runtime.index, 1)
        XCTAssertEqual(runtime.stage, .item)
        XCTAssertTrue(runtime.isDurablyPrepared)
    }

    func testProtectedTimeSliceResumesSameCoverageAndSelectsUnseenNextItem() throws {
        let (store, container) = try store(); defer { _ = container }
        var now = 0.0
        let launch = SessionRequest(lab: .logicDebugging, source: .reassessment, seed: 918273,
            localeIdentifier: "en", requestedMinutes: 3, evidenceClass: .assessmentHoldout,
            assessmentBlock: .logicMetacognition, reassessmentCycle: 1, isTimed: false)
        let runtime = NFUniversalSessionRuntime(request: launch, monotonicNow: { now })
        XCTAssertTrue(runtime.checkpointDraft(store: store)); runtime.acknowledgePresented()
        let firstDescriptor = try XCTUnwrap(runtime.assessmentDescriptor?.id)
        fill(runtime); runtime.chooseConfidence(.fairlyConfident)
        now = 190
        XCTAssertEqual(runtime.stage, .item)
        runtime.submitInline(store: store)
        XCTAssertEqual(runtime.stage, .feedback)
        runtime.next(store: store)
        XCTAssertEqual(runtime.stage, .summary)
        XCTAssertTrue(runtime.awaitingNextSitting)
        XCTAssertFalse(runtime.endedEarly)
        let saved = try XCTUnwrap(store.resumableSessions.first)
        XCTAssertEqual(saved.checkpoint.assessmentStopReason, .maximumActiveDurationReached)
        XCTAssertEqual(saved.checkpoint.assessmentState?.completedScorableItems, 1)
        runtime.releaseWriter(); XCTAssertTrue(store.resumeSession(runtime.sessionID))
        now = 50_000
        let restored = NFUniversalSessionRuntime(request: try XCTUnwrap(store.activeSessionRequest), monotonicNow: { now })
        XCTAssertTrue(restored.checkpointDraft(store: store))
        XCTAssertEqual(restored.sessionID, runtime.sessionID)
        XCTAssertEqual(restored.request.seed, launch.seed)
        restored.continueProtectedSitting(store: store)
        XCTAssertEqual(restored.stage, .item)
        XCTAssertEqual(restored.assessmentState.completedScorableItems, 1)
        XCTAssertNotEqual(restored.assessmentDescriptor?.id, firstDescriptor)
        XCTAssertEqual(restored.sittingOrdinal, 1)
        XCTAssertEqual(restored.sittingActiveElapsed(), 0)
        XCTAssertTrue(restored.isDurablyPrepared)
        XCTAssertEqual(store.attempts.count, 1)
    }
}

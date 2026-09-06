import SwiftData
import XCTest
@testable import NeuroForge

final class AttemptReflectionContractTests: XCTestCase {
    func testPublishedTaxonomyMatchesReleaseContract() {
        XCTAssertEqual(
            Set(NFErrorReflectionCode.allCases.map(\.rawValue)),
            [
                "knowledge_missing", "misconception", "misread_constraint", "unit_mismatch",
                "sign_direction", "place_value", "operation_selection", "exponent",
                "percentage_base", "rounding", "invalid_implication", "confound",
                "causal_overreach", "edge_case_omitted", "state_tracking", "syntax_familiarity",
                "time_pressure", "input_error", "unfamiliar_context", "other"
            ]
        )
    }

    @MainActor
    func testReflectionPersistsAsSupplementWithoutMutatingAttempt() throws {
        let (store, container) = try makeStore()
        defer { _ = container }
        try store.saveLabAttempt(
            lab: .mentalMath,
            itemID: "reflection-immutable",
            prompt: "12 × 8",
            response: "84",
            correctAnswer: "96",
            isCorrect: false,
            confidence: .certain
        )
        let attempt = try XCTUnwrap(store.attempts.first)
        let original = (
            response: attempt.response,
            credit: attempt.deterministicCredit,
            errorCode: attempt.errorCode,
            submittedAt: attempt.submittedAt
        )

        try store.saveAttemptReflection(
            attemptID: attempt.id,
            deterministicErrorCode: attempt.errorCode,
            selectedErrorCode: .placeValue,
            trigger: .highConfidenceError,
            note: "I transposed the product."
        )

        XCTAssertEqual(attempt.response, original.response)
        XCTAssertEqual(attempt.deterministicCredit, original.credit)
        XCTAssertEqual(attempt.errorCode, original.errorCode)
        XCTAssertEqual(attempt.submittedAt, original.submittedAt)
        XCTAssertEqual(store.effectiveErrorCode(for: attempt), NFErrorReflectionCode.placeValue.rawValue)

        let restored = AppStore(context: container.mainContext)
        let reflection = try XCTUnwrap(restored.attemptReflections.first)
        XCTAssertEqual(reflection.attemptID, attempt.id)
        XCTAssertEqual(reflection.deterministicErrorCode, original.errorCode)
        XCTAssertEqual(reflection.selectedErrorCode, .placeValue)
        XCTAssertEqual(reflection.note, "I transposed the product.")
    }

    @MainActor
    func testReflectionNoteLengthBoundaryRejectsWithoutInsertionOrTruncation() throws {
        let (store, container) = try makeStore()
        defer { _ = container }
        for itemID in ["reflection-exact-limit", "reflection-over-limit"] {
            try store.saveLabAttempt(
                lab: .mentalMath,
                itemID: itemID,
                prompt: "12 × 8",
                response: "84",
                correctAnswer: "96",
                isCorrect: false,
                confidence: .certain
            )
        }
        let exactAttempt = try XCTUnwrap(store.attempts.first { $0.itemID == "reflection-exact-limit" })
        let overAttempt = try XCTUnwrap(store.attempts.first { $0.itemID == "reflection-over-limit" })
        let exact = String(repeating: "a", count: AttemptReflectionRecord.maximumNoteCharacters)
        let over = exact + "b"

        try store.saveAttemptReflection(
            attemptID: exactAttempt.id,
            deterministicErrorCode: exactAttempt.errorCode,
            selectedErrorCode: .inputError,
            trigger: .highConfidenceError,
            note: exact
        )
        XCTAssertEqual(store.attemptReflections.first?.note, exact)

        XCTAssertThrowsError(try store.saveAttemptReflection(
            attemptID: overAttempt.id,
            deterministicErrorCode: overAttempt.errorCode,
            selectedErrorCode: .inputError,
            trigger: .highConfidenceError,
            note: over
        )) { error in
            XCTAssertEqual(
                error as? NFAttemptReflectionPersistenceError,
                .noteTooLong(maximum: AttemptReflectionRecord.maximumNoteCharacters)
            )
        }
        XCTAssertEqual(store.attemptReflections.count, 1)
        XCTAssertFalse(store.attemptReflections.contains { $0.attemptID == overAttempt.id })
    }

    @MainActor
    func testDiagnosticTriggerPrecedesFeedbackButProtectedAssessmentNeverReflects() throws {
        let (store, container) = try makeStore()
        defer { _ = container }
        let exercise = try NFFallbackExerciseGenerator.generate(NFExerciseGenerationRequest(
            seed: 81,
            index: 0,
            lab: .logicDebugging,
            purpose: .practice,
            sourceContext: NFExerciseSourceContext(topic: "state transition"),
            targetDifficulty: 0.55
        ))
        let feedback = NFExerciseFeedback(
            title: "Review",
            explanation: "Deterministic explanation",
            decisiveStep: nil,
            strategy: nil,
            errorCode: "logic_state",
            isDelayed: false
        )
        let incorrect = NFExerciseScoringResult(
            exerciseID: exercise.id,
            scoringVersion: 1,
            isCorrect: false,
            credit: 0,
            normalizedResponse: nil,
            errorCode: "logic_state",
            expectedAnswerSummary: "expected",
            feedback: feedback
        )

        XCTAssertEqual(
            store.reflectionTrigger(
                for: incorrect,
                confidence: .fairlyConfident,
                exercise: exercise,
                source: .focused
            ),
            .highConfidenceError
        )

        let delayed = NFExerciseScoringResult(
            exerciseID: exercise.id,
            scoringVersion: 1,
            isCorrect: false,
            credit: 0,
            normalizedResponse: nil,
            errorCode: "logic_state",
            expectedAnswerSummary: nil,
            feedback: NFExerciseFeedback(
                title: "Recorded",
                explanation: "Protected",
                decisiveStep: nil,
                strategy: nil,
                errorCode: nil,
                isDelayed: true
            )
        )
        XCTAssertNil(store.reflectionTrigger(
            for: delayed,
            confidence: .certain,
            exercise: exercise,
            source: .baseline
        ))
    }

    @MainActor
    func testLaterReflectionRevisionIsAppendOnlyIdempotentAndRestoresWithoutChangingScore() throws {
        let (store, container) = try makeStore()
        defer { _ = container }
        try store.saveLabAttempt(lab: .mentalMath, itemID: "revision-original", prompt: "12 × 8",
            response: "84", correctAnswer: "96", isCorrect: false, confidence: .certain)
        let attempt = try XCTUnwrap(store.attempts.first)
        let originalResponse = attempt.response
        let originalTime = attempt.submittedAt
        let originalCredit = attempt.deterministicCredit
        try store.saveAttemptReflection(attemptID: attempt.id, deterministicErrorCode: attempt.errorCode,
            selectedErrorCode: .placeValue, trigger: .highConfidenceError, note: "My first interpretation.")
        let original = try XCTUnwrap(store.attemptReflections.first)
        let originalReflectionTime = original.createdAt
        for _ in 0..<3 {
            try store.saveAttemptReflection(attemptID: attempt.id, deterministicErrorCode: "must not replace original",
                selectedErrorCode: .inputError, trigger: .strategyMismatch, note: "  I mistyped it.  ")
        }
        XCTAssertEqual(store.attemptReflections.count, 1)
        XCTAssertEqual(original.selectedErrorCode, .placeValue)
        XCTAssertEqual(original.note, "My first interpretation.")
        XCTAssertEqual(original.createdAt, originalReflectionTime)
        XCTAssertEqual(original.trigger, .highConfidenceError)
        XCTAssertEqual(original.deterministicErrorCode, attempt.errorCode)
        XCTAssertEqual(store.currentReflection(for: attempt.id)?.revision, 1)
        XCTAssertEqual(store.effectiveErrorCode(for: attempt), NFErrorReflectionCode.inputError.rawValue)
        let first = try XCTUnwrap(store.privateStudyMetadata.annotations.first?.reflectionRevisions?.first)
        try store.saveAttemptReflection(attemptID: attempt.id, deterministicErrorCode: attempt.errorCode,
            selectedErrorCode: nil, trigger: .highConfidenceError, note: "I am not sure yet.")
        let history = try XCTUnwrap(store.privateStudyMetadata.annotations.first?.reflectionRevisions)
        XCTAssertEqual(history.count, 2)
        XCTAssertEqual(history[0], first)
        XCTAssertEqual(history[1].predecessorID, first.id)
        XCTAssertEqual(history[1].originalReflectionID, original.id)
        XCTAssertNil(store.currentReflection(for: attempt.id)?.selectedErrorCodeRaw)
        XCTAssertEqual(store.effectiveErrorCode(for: attempt), attempt.errorCode)
        XCTAssertEqual(attempt.response, originalResponse)
        XCTAssertEqual(attempt.submittedAt, originalTime)
        XCTAssertEqual(attempt.deterministicCredit, originalCredit)

        let portable = try JSONDecoder().decode(NFLocalSessionRepository.Archive.self,
            from: JSONEncoder().encode(store.localSessions.exportArchive))
        let repository = NFLocalSessionRepository()
        try repository.importArchive(portable)
        let restored = AppStore(context: container.mainContext, localSessionRepository: repository)
        XCTAssertEqual(restored.currentReflection(for: attempt.id)?.note, "I am not sure yet.")
        XCTAssertEqual(restored.privateStudyMetadata.annotations.first?.reflectionRevisions, history)
        var attemptedRewrite = restored.privateStudyMetadata
        attemptedRewrite.annotations[0].reflectionRevisions = [first]
        XCTAssertThrowsError(try restored.savePrivateStudyMetadata(attemptedRewrite))
        XCTAssertEqual(restored.privateStudyMetadata.annotations.first?.reflectionRevisions, history)
        try repository.removeReferences(attemptIDs: [attempt.id])
        XCTAssertTrue(restored.privateStudyMetadata.annotations.isEmpty)
    }

    @MainActor
    func testFailedReflectionRevisionKeepsPreviousInterpretationAndOriginalRecord() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "NFReflectionRevision-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = NFLocalSessionRepository(url: root.appending(path: "archive.json"))
        let container = try ModelContainer(for: Schema(NFSchemaV1.models),
            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let store = AppStore(context: container.mainContext, localSessionRepository: repository)
        try store.saveLabAttempt(lab: .mentalMath, itemID: "revision-failure", prompt: "12 × 8",
            response: "84", correctAnswer: "96", isCorrect: false, confidence: .certain)
        let attempt = try XCTUnwrap(store.attempts.first)
        try store.saveAttemptReflection(attemptID: attempt.id, deterministicErrorCode: attempt.errorCode,
            selectedErrorCode: .placeValue, trigger: .highConfidenceError, note: "Original.")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try FileManager.default.removeItem(at: root)
        try Data("blocked path".utf8).write(to: root)
        XCTAssertThrowsError(try store.saveAttemptReflection(attemptID: attempt.id,
            deterministicErrorCode: attempt.errorCode, selectedErrorCode: .inputError,
            trigger: .highConfidenceError, note: "Unsaved revision."))
        XCTAssertEqual(store.currentReflection(for: attempt.id)?.note, "Original.")
        XCTAssertEqual(store.effectiveErrorCode(for: attempt), NFErrorReflectionCode.placeValue.rawValue)
        XCTAssertEqual(store.attemptReflections.count, 1)
        XCTAssertTrue(store.privateStudyMetadata.annotations.isEmpty)
        XCTAssertFalse(attempt.isCorrect)
    }

    @MainActor
    func testUnknownReflectionMetadataDoesNotReviveAnOlderConfirmedDiagnosis() throws {
        let (store, container) = try makeStore(); defer { _ = container }
        try store.saveLabAttempt(lab: .mentalMath, itemID: "future-reflection", prompt: "12 × 8",
            response: "84", correctAnswer: "96", isCorrect: false, confidence: .certain)
        let attempt = try XCTUnwrap(store.attempts.first)
        try store.saveAttemptReflection(attemptID: attempt.id, deterministicErrorCode: attempt.errorCode,
            selectedErrorCode: .placeValue, trigger: .highConfidenceError, note: "First interpretation.")
        XCTAssertEqual(store.currentReflection(for: attempt.id)?.selectedErrorCodeRaw, NFErrorReflectionCode.placeValue.rawValue)
        var future = NFPrivateStudyMetadata()
        future.schemaVersion = 999
        let bytes = try JSONEncoder().encode(future)
        try store.localSessions.savePrivateStudyRun(id: NFPrivateStudyMetadata.recordID,
            generationID: NFPrivateStudyMetadata.recordID, payload: bytes)
        XCTAssertNotNil(store.privateStudyMetadataUnavailableReason)
        XCTAssertNil(store.currentReflection(for: attempt.id))
        XCTAssertEqual(store.effectiveErrorCode(for: attempt), attempt.errorCode)
        XCTAssertEqual(store.attemptReflections.first?.selectedErrorCode, .placeValue)
        XCTAssertEqual(store.attemptReflections.first?.note, "First interpretation.")
        XCTAssertEqual(store.localSessions.archive.privateStudyRuns?.first?.payload, bytes)
    }

    @MainActor
    func testReflectionRevisionWithMissingOriginalAnchorIsRecoveryOnlyWithoutRevivingDiagnosis() throws {
        let (store, container) = try makeStore(); defer { _ = container }
        try store.saveLabAttempt(lab: .mentalMath, itemID: "mismatched-reflection", prompt: "12 × 8",
            response: "84", correctAnswer: "96", isCorrect: false, confidence: .certain)
        let attempt = try XCTUnwrap(store.attempts.first)
        try store.saveAttemptReflection(attemptID: attempt.id, deterministicErrorCode: attempt.errorCode,
            selectedErrorCode: .placeValue, trigger: .highConfidenceError, note: "First interpretation.")
        let original = try XCTUnwrap(store.attemptReflections.first)
        let revision = NFStudyReflectionRevision(id: UUID(), attemptID: attempt.id,
            originalReflectionID: UUID(), revision: 1, predecessorID: nil,
            selectedErrorCodeRaw: NFErrorReflectionCode.inputError.rawValue,
            note: "A revision from an unavailable original.", createdAt: Date())
        var metadata = NFPrivateStudyMetadata()
        metadata.annotations = [NFStudyAnnotation(id: attempt.id, reflectionRevisions: [revision])]
        // A structurally valid portable supplement can arrive before its original
        // SwiftData record. It must remain readable and must not guess an anchor.
        XCTAssertTrue(metadata.isSupported)
        try store.savePrivateStudyMetadata(metadata)
        XCTAssertNotNil(store.reflectionUnavailableReason(for: attempt.id))
        XCTAssertNil(store.currentReflection(for: attempt.id))
        XCTAssertEqual(store.effectiveErrorCode(for: attempt), attempt.errorCode)
        XCTAssertThrowsError(try store.saveAttemptReflection(attemptID: attempt.id,
            deterministicErrorCode: attempt.errorCode, selectedErrorCode: .unitMismatch,
            trigger: .highConfidenceError, note: "Must not reattach to a different original."))
        XCTAssertEqual(store.privateStudyMetadata.annotations.first?.reflectionRevisions, [revision])
        XCTAssertEqual(store.attemptReflections.first?.id, original.id)
        XCTAssertEqual(original.selectedErrorCode, .placeValue)
        XCTAssertEqual(original.note, "First interpretation.")
    }

    @MainActor
    private func makeStore() throws -> (AppStore, ModelContainer) {
        let container = try ModelContainer(
            for: Schema(NFSchemaV1.models),
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        return (AppStore(context: container.mainContext), container)
    }
}

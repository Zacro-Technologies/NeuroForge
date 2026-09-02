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
    private func makeStore() throws -> (AppStore, ModelContainer) {
        let container = try ModelContainer(
            for: Schema(NFSchemaV1.models),
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        return (AppStore(context: container.mainContext), container)
    }
}

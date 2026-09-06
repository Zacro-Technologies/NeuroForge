import Foundation
import XCTest
@testable import NeuroForge

final class NFAIGradingContractTests: XCTestCase {
    func testAcceptedReceiptReplaysWeightedPartialCreditWithoutModel() throws {
        let request = try makeRequest(answer: "Add the observations; divide by a number.")
        let receipt = makeReceipt(request, credits: [1, 0.5])
        let score = try NFAIGradeValidator.score(receipt, for: request)
        XCTAssertEqual(score.credit, 0.75)
        XCTAssertEqual(score.outcome, .partial)
        XCTAssertFalse(score.isCorrect)
        XCTAssertEqual(score.components.map(\.awardedCredit), [0.5, 0.25])
        let restored = try JSONDecoder().decode(NFExerciseScoringResult.self, from: JSONEncoder().encode(score))
        XCTAssertEqual(restored, score)
        XCTAssertTrue(NFAIGradeValidator.validatesScore(restored, exercise: request.exercise,
            response: request.response, attemptID: request.attemptID))
    }

    func testExactScorerCannotTurnMissingAIGradeIntoIncorrectAnswer() throws {
        let request = try makeRequest()
        let score = NFExerciseScoringEngine.score(request.response, for: request.exercise)
        XCTAssertEqual(score.outcome, .needsClarification)
        XCTAssertNil(score.objectiveCorrectness)
        XCTAssertNil(score.expectedAnswerSummary)
        XCTAssertNil(score.aiGrade)
    }

    func testChangedResponseOrRubricRejectsPreviouslyAcceptedReceipt() throws {
        let request = try makeRequest()
        let receipt = makeReceipt(request)
        let edited = NFAIGradeRequest(id: request.id, attemptID: request.attemptID, runID: request.runID,
            exercise: request.exercise, response: .shortText("Divide the count by the sum."), createdAt: request.createdAt)
        XCTAssertThrowsError(try NFAIGradeValidator.validate(receipt, for: edited))
        XCTAssertNotEqual(edited.contentDigest, request.contentDigest)
        let score = try NFAIGradeValidator.score(receipt, for: request)
        XCTAssertFalse(NFAIGradeValidator.validatesScore(score, exercise: request.exercise,
            response: request.response, attemptID: UUID()))
    }

    func testInventedLearnerEvidenceAndUnknownSourcesAreRejected() throws {
        let request = try makeRequest()
        XCTAssertThrowsError(try NFAIGradeValidator.validate(makeReceipt(request, quote: "I used an unbiased estimator"), for: request))
        XCTAssertThrowsError(try NFAIGradeValidator.validate(makeReceipt(request, sourceIDs: ["invented-source"]), for: request))
    }

    func testDuplicateMissingAndOutOfRangeCriteriaAreRejected() throws {
        let request = try makeRequest()
        XCTAssertThrowsError(try NFAIGradeValidator.validate(makeReceipt(request, credits: [1]), for: request))
        XCTAssertThrowsError(try NFAIGradeValidator.validate(makeReceipt(request, credits: [1, 1.1]), for: request))
        XCTAssertThrowsError(try NFAIGradeValidator.validate(makeReceipt(request, credits: [1, .nan]), for: request))
        XCTAssertThrowsError(try NFAIGradeValidator.validate(makeReceipt(request, duplicateIDs: true), for: request))
    }

    func testUncertainEvaluationNeverProducesAZeroScore() throws {
        let request = try makeRequest()
        let receipt = makeReceipt(request, decision: .needsClarification, credits: [])
        XCTAssertNoThrow(try NFAIGradeValidator.validate(receipt, for: request))
        XCTAssertThrowsError(try NFAIGradeValidator.score(receipt, for: request)) { error in
            XCTAssertEqual(error as? NFAIGradeValidationError, .needsClarification)
        }
    }

    func testFullyCreditedParaphraseRetainsTheActualAnswer() throws {
        let request = try makeRequest(answer: "Total the observations, then divide by how many there are.")
        let score = try NFAIGradeValidator.score(makeReceipt(request), for: request)
        XCTAssertTrue(score.isCorrect)
        XCTAssertEqual(score.credit, 1)
        XCTAssertEqual(score.normalizedResponse, request.answerText)
        XCTAssertNotEqual(score.normalizedResponse, score.expectedAnswerSummary)
    }

    func testSavedExactScoreDecodesWithoutAIReceipt() throws {
        let original = try makeRequest().exercise
        let legacy = NFAuthoredExerciseAuthority.make(id: "legacy", lab: .mentalMath, style: .numerical,
            prompt: "What is 2 + 3?", context: "Addition", choices: [], correctAnswer: "5", acceptedAnswers: ["5"],
            explanation: "Two plus three is five.", hint: "Count three more.", decisiveStep: "Add the two values.",
            difficulty: 0.2, citationChunkIDs: [], evidenceClass: .documentPractice)
        let score = NFExerciseScoringEngine.score(.numeric(.init(value: "5", unit: nil)), for: legacy)
        let data = try JSONEncoder().encode(score)
        let decoded = try JSONDecoder().decode(NFExerciseScoringResult.self, from: data)
        XCTAssertNil(decoded.aiGrade)
        XCTAssertTrue(decoded.isCorrect)
        XCTAssertNil(legacy.aiRubric)
        XCTAssertEqual(original.schemaVersion, 14)
    }

    func testServiceUsesFrozenInputAndRejectsWrongResponseIdentity() async throws {
        let request = try makeRequest()
        let service = NFAIGradingService(complete: { completion, mode in
            XCTAssertEqual(mode, .automatic)
            XCTAssertEqual(completion.id, request.id)
            XCTAssertEqual(completion.task, .grading)
            XCTAssertNotNil(completion.jsonSchema)
            XCTAssertTrue(completion.input.contains(request.answerText!))
            return NFAICompletionResult(requestID: UUID(), text: "{}", providerIdentifier: "fixture",
                modelIdentifier: "fixture-model", route: .cloud, generatedAt: Date())
        })
        do {
            _ = try await service.grade(request, mode: .automatic)
            XCTFail("A response from another request must not be accepted")
        } catch {
            XCTAssertEqual(error as? NFAIGradeValidationError, .mismatchedRequest)
        }
    }

    private func makeRequest(answer: String = "Add the observations, then divide by their count.") throws -> NFAIGradeRequest {
        let base = NFAuthoredExerciseAuthority.make(id: "mean-explanation", lab: .mentalMath, style: .shortAnswer,
            prompt: "How do you calculate the arithmetic mean?", context: "Arithmetic mean", choices: [],
            correctAnswer: "Divide the sum of all observations by the number of observations.", acceptedAnswers: [],
            explanation: "The sum divided by the count gives the mean.", hint: "Start with the total.",
            decisiveStep: "Explain the calculation.", difficulty: 0.4, citationChunkIDs: [], evidenceClass: .documentPractice)
        let exercise = try NFAIExerciseFactory.shortResponse(from: base,
            reference: "Divide the sum of all observations by the number of observations.",
            criteria: ["Add all observations.", "Divide the sum by the count, not the reverse."])
        return NFAIGradeRequest(attemptID: UUID(), runID: UUID(), exercise: exercise, response: .shortText(answer))
    }

    private func makeReceipt(_ request: NFAIGradeRequest, decision: NFAIGradeDecision = .graded,
                             credits: [Double] = [1, 1], quote: String? = nil,
                             sourceIDs: [String] = [], duplicateIDs: Bool = false) -> NFAIGradeReceipt {
        let criteria = credits.enumerated().map { index, credit in
            NFAICriterionGrade(criterionID: "criterion-\(duplicateIDs ? 1 : index + 1)", credit: credit,
                explanation: credit == 1 ? "This criterion is supported by your answer." : "Specify which number is the divisor.",
                responseEvidence: [quote ?? request.answerText!], sourceChunkIDs: sourceIDs)
        }
        return NFAIGradeReceipt(id: UUID(), requestID: request.id, requestDigest: request.contentDigest,
            request: request, decision: decision, criteria: criteria,
            explanation: decision == .graded ? "You identified the total; check the divisor." : "The source context is incomplete.",
            nextStep: nil, providerIdentifier: "fixture", modelIdentifier: "fixture-model",
            routeIdentifier: "cloud", acceptedAt: Date(), reviewOf: request.reviewOf)
    }
}

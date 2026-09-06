import Foundation
import XCTest
@testable import NeuroForge

@MainActor final class NFAILearningProgressTests: XCTestCase {
    private func example(topic: String = "Heat transfer", sourceID: String? = nil,
                         credit: Double = 0.5, date: TimeInterval = 100) throws -> (AttemptRecord, NFAIGradeReceipt) {
        let question = NFAuthoredQuestion(id: "learning-\(UUID())", lab: .scientificReasoning,
            style: .shortAnswer, prompt: "Explain why the ice melts.", context: "A warmer room surrounds the ice.",
            choices: [], correctAnswer: "Energy flows from the warmer room into the ice.", acceptedAnswers: [],
            explanation: "Energy transfer changes the state of the ice.", hint: "Compare temperatures.",
            decisiveStep: "Explain the direction of energy transfer.", difficulty: 0.3,
            citationChunkIDs: [], evidenceClass: .documentPractice)
        let initial = try NFAIExerciseFactory.shortResponse(from: question.authoritativeExercise, reference: question.correctAnswer)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(initial)) as? [String: Any])
        var context = try XCTUnwrap(object["sourceContext"] as? [String: Any])
        context["topic"] = topic
        if let sourceID { context["sourceDocumentIDs"] = [sourceID]; context["materialTitle"] = "Saved thermodynamics notes" }
        object["sourceContext"] = context
        let exercise = try JSONDecoder().decode(NFExercise.self, from: JSONSerialization.data(withJSONObject: object))
        let request = NFAIGradeRequest(attemptID: UUID(), runID: UUID(), slotID: UUID().uuidString,
            exercise: exercise, response: .shortText("Energy enters the ice from the warmer air."))
        let receipt = grade(request, credit: credit)
        let score = try NFAIGradeValidator.score(receipt, for: request)
        let record = AttemptRecord(sessionID: request.runID, lab: exercise.lab, itemID: exercise.id,
            prompt: exercise.prompt, response: String(decoding: try JSONEncoder().encode(request.response), as: UTF8.self),
            correctAnswer: question.correctAnswer, isCorrect: score.isCorrect, confidence: .fairlyConfident,
            evidenceClass: .documentPractice, source: .focused, responseFormat: "shortText")
        record.id = request.attemptID; record.templateID = exercise.templateID
        record.scoringVersion = score.scoringVersion; record.deterministicCredit = credit
        record.submittedAt = Date(timeIntervalSince1970: date); record.errorCode = nil
        return (record, receipt)
    }
    private func grade(_ request: NFAIGradeRequest, credit: Double) -> NFAIGradeReceipt {
        .init(id: UUID(), requestID: request.id, requestDigest: request.contentDigest, request: request,
            decision: .graded, criteria: request.exercise.aiRubric!.criteria.map {
                .init(criterionID: $0.id, credit: credit, explanation: "Identify which object supplies energy.",
                    responseEvidence: [request.answerText!], sourceChunkIDs: [])
            }, explanation: "Saved semantic feedback.", nextStep: "Compare the temperatures of the two objects.",
            providerIdentifier: "test-provider", modelIdentifier: "test-model", routeIdentifier: "local",
            acceptedAt: Date(timeIntervalSince1970: 1_000), reviewOf: request.reviewOf)
    }
    private func reviewed(_ original: NFAIGradeReceipt, credit: Double, response: NFExerciseResponse? = nil) -> NFAIGradingJob {
        let request = NFAIGradeRequest(attemptID: original.request.attemptID, runID: original.request.runID,
            slotID: original.request.slotID, exercise: original.request.exercise,
            response: response ?? original.request.response, sourceChunks: original.request.sourceChunks,
            reviewOf: original.id, reviewReason: "Consider the meaning of my wording.")
        return NFAIGradingJob(ownerDeviceID: UUID(), request: request, revision: 2, status: .accepted,
            dispatchCount: 1, receipt: grade(request, credit: credit), events: [
                .init(revision: 0, status: .queued, occurredAt: request.createdAt, reason: nil),
                .init(revision: 1, status: .dispatching, occurredAt: request.createdAt, reason: nil),
                .init(revision: 2, status: .accepted, occurredAt: request.createdAt, reason: nil)
            ])
    }

    func testDocumentPracticeCountsAsScopedLearningWithoutAbilityEvidence() throws {
        let (first, firstGrade) = try example(credit: 0.25)
        let (second, secondGrade) = try example(credit: 0.75, date: 200)
        second.hintCount = 1
        XCTAssertEqual(first.evidenceWeight, 0)
        let scopes = NFAILearningProgress.make(attempts: [NFReadOnlyAttemptSnapshot(attempt: first), NFReadOnlyAttemptSnapshot(attempt: second)],
            originalReceipts: [first.id: firstGrade, second.id: secondGrade], reviewJobs: [])
        let scope = try XCTUnwrap(scopes.first)
        XCTAssertEqual(scopes.count, 1); XCTAssertEqual(scope.kind, .topic)
        XCTAssertEqual(scope.title, "Heat transfer")
        XCTAssertEqual(scope.attemptCount, 2); XCTAssertEqual(scope.earnedCredit, 1)
        XCTAssertEqual(scope.possibleCredit, 2); XCTAssertTrue(scope.answers[0].wasAssisted)
        XCTAssertEqual(Set(scope.attemptIDs), [first.id, second.id])
        XCTAssertEqual(first.evidenceWeight, 0)
    }

    func testAcceptedReviewReplacesCreditOnceAndPreservesOriginalFeedback() throws {
        let (record, original) = try example(credit: 0)
        let review = reviewed(original, credit: 1)
        let row = NFReadOnlyAttemptSnapshot(attempt: record)
        let scopes = NFAILearningProgress.make(attempts: [row, row], originalReceipts: [record.id: original], reviewJobs: [review, review])
        let answer = try XCTUnwrap(scopes.first?.answers.first)
        XCTAssertEqual(scopes.first?.attemptCount, 1); XCTAssertEqual(scopes.first?.earnedCredit, 1)
        XCTAssertEqual(answer.originalCredit, 0); XCTAssertEqual(answer.originalReceiptID, original.id)
        XCTAssertEqual(answer.effectiveReceiptID, review.receipt?.id); XCTAssertTrue(answer.wasReviewed)
        XCTAssertEqual(answer.originalFeedback, original.explanation)
        XCTAssertEqual(record.deterministicCredit, 0); XCTAssertFalse(record.isCorrect)
        XCTAssertNil(scopes.first?.latestCriterionNeedingWork)
    }

    func testPendingUnscoredProtectedAndDisputedWorkAreExcluded() throws {
        var rows: [NFReadOnlyAttemptSnapshot] = [], originals: [UUID: NFAIGradeReceipt] = [:]
        for flag in ["pending", "skip", "reveal", "protected", "baseline", "disputed"] {
            let (record, grade) = try example()
            switch flag {
            case "skip": record.wasSkipped = true
            case "reveal": record.errorCode = "solution_revealed"; record.responseFormatRaw = "revealed"
            case "protected": record.evidenceClassRaw = EvidenceClass.assessmentHoldout.rawValue
            case "baseline": record.sessionSourceRaw = SessionSource.baseline.rawValue
            default: break
            }
            var row = NFReadOnlyAttemptSnapshot(attempt: record)
            if flag == "disputed" {
                row = row.applyingHistoricalCorrections(dispositions: [.init(id: "dispute", attemptID: record.id.uuidString,
                    revision: 1, policyVersion: NFHistoricalPracticeProjection.policyVersion, occurredAt: Date(),
                    disposition: .excludedInvalidScore, reason: "The source key is disputed.", correctedDerivedCredit: nil,
                    supersedesDispositionID: nil)], corrections: [], activeIDs: nil)
            }
            rows.append(row)
            if flag != "pending" { originals[record.id] = grade }
        }
        XCTAssertTrue(NFAILearningProgress.make(attempts: rows, originalReceipts: originals, reviewJobs: []).isEmpty)
    }

    func testStableSourceAndTopicScopesDoNotMergeUnrelatedMaterial() throws {
        let source = UUID().uuidString
        let pairs = try [example(sourceID: source), example(sourceID: source.lowercased(), date: 200),
            example(sourceID: UUID().uuidString), example(topic: "Phase equilibrium", sourceID: source)]
        let scopes = NFAILearningProgress.make(attempts: pairs.map { NFReadOnlyAttemptSnapshot(attempt: $0.0) },
            originalReceipts: Dictionary(uniqueKeysWithValues: pairs.map { ($0.0.id, $0.1) }), reviewJobs: [])
        XCTAssertEqual(scopes.count, 3)
        XCTAssertEqual(scopes.map(\.attemptCount).sorted(), [1, 1, 2])
        XCTAssertTrue(scopes.allSatisfy { $0.kind == .source && $0.title == "Saved thermodynamics notes" })
        XCTAssertEqual(Set(scopes.map(\.id)).count, 3)
    }

    func testLatestActionableCriterionKeepsItsExactAnswerAndDate() throws {
        let (old, oldGrade) = try example(credit: 0, date: 100)
        let (recent, recentGrade) = try example(credit: 0.5, date: 300)
        let scopes = NFAILearningProgress.make(attempts: [NFReadOnlyAttemptSnapshot(attempt: old), NFReadOnlyAttemptSnapshot(attempt: recent)],
            originalReceipts: [old.id: oldGrade, recent.id: recentGrade], reviewJobs: [])
        let focus = try XCTUnwrap(scopes.first?.latestCriterionNeedingWork)
        XCTAssertEqual(focus.attemptID, recent.id); XCTAssertEqual(focus.submittedAt, recent.submittedAt)
        XCTAssertEqual(focus.criterion, recentGrade.request.exercise.aiRubric?.criteria.first?.description)
        XCTAssertEqual(focus.explanation, recentGrade.criteria.first?.explanation)
        XCTAssertEqual(focus.nextStep, recentGrade.nextStep)
    }

    func testHistoryAndProgressRejectReceiptForAnotherSavedContext() throws {
        let (record, original) = try example(credit: 0)
        record.sessionID = UUID()
        let row = NFReadOnlyAttemptSnapshot(attempt: record)
        XCTAssertNil(row.applyingAIGrade(original, reviews: []).aiGrade)
        XCTAssertTrue(NFAILearningProgress.make(attempts: [row], originalReceipts: [record.id: original], reviewJobs: []).isEmpty)
    }

    func testWrongAnswerReviewCannotChangeEffectiveCredit() throws {
        let (record, original) = try example(credit: 0)
        let foreign = reviewed(original, credit: 1, response: .shortText("An entirely different answer."))
        let row = NFReadOnlyAttemptSnapshot(attempt: record)
        let updated = row.applyingAIGrade(original, reviews: [foreign])
        XCTAssertNil(updated.reviewedAIGrade); XCTAssertEqual(updated.effectiveCredit, 0)
        let scopes = NFAILearningProgress.make(attempts: [row], originalReceipts: [record.id: original], reviewJobs: [foreign])
        XCTAssertEqual(scopes.first?.earnedCredit, 0)
    }

    func testConflictingDuplicateHistoryIdentityIsNotCounted() throws {
        let (record, original) = try example(credit: 0.5)
        let first = NFReadOnlyAttemptSnapshot(attempt: record)
        record.prompt = "A different retained question."
        let conflicting = NFReadOnlyAttemptSnapshot(attempt: record)
        XCTAssertTrue(NFAILearningProgress.make(attempts: [first, conflicting], originalReceipts: [record.id: original], reviewJobs: []).isEmpty)
    }

    func testProtectedHistoryNeverAttachesAIGradeOrReview() throws {
        let (record, original) = try example(credit: 0)
        record.sessionSourceRaw = SessionSource.reassessment.rawValue
        let protected = NFReadOnlyAttemptSnapshot(attempt: record).applyingAIGrade(original, reviews: [reviewed(original, credit: 1)])
        XCTAssertNil(protected.aiGrade); XCTAssertNil(protected.reviewedAIGrade)
        XCTAssertEqual(protected.effectiveResult, .all); XCTAssertEqual(protected.correctAnswer, "")
    }
}

import Foundation
import XCTest
@testable import NeuroForge

/// Temporary investigative QA probes. These intentionally assert the observed
/// defects, so a passing run confirms reproduction; they are not release gates.
@MainActor
final class NFContentQAProbeTests: XCTestCase {
    func testDuplicateCorrectSpatialOptionsAreScoredDifferently() async throws {
        let exercise = try NFFallbackExerciseGenerator.generate(NFExerciseGenerationRequest(
            seed: 11, index: 0, lab: .spatial, purpose: .practice
        ))
        guard case let .singleChoice(schema) = exercise.interaction else {
            return XCTFail("Expected a single-choice spatial exercise")
        }
        let keyed = try XCTUnwrap(schema.options.first { $0.id == schema.correctOptionID })
        let identical = schema.options.filter { $0.text == keyed.text }
        print("NF_CONTENT_QA spatial prompt=\(exercise.prompt) duplicatedAnswer=\(keyed.text) ids=\(identical.map(\.id))")
        XCTAssertEqual(keyed.text, "(-10, 10)")
        XCTAssertEqual(identical.count, 2, "The same valid coordinate appears twice")
        let keyedResult = NFExerciseScoringEngine.score(.singleChoice(optionID: keyed.id), for: exercise)
        let other = try XCTUnwrap(identical.first { $0.id != keyed.id })
        let otherResult = NFExerciseScoringEngine.score(.singleChoice(optionID: other.id), for: exercise)
        XCTAssertTrue(keyedResult.isCorrect)
        XCTAssertFalse(otherResult.isCorrect)
        print("NF_CONTENT_QA identical spatial answers keyedCredit=\(keyedResult.credit) otherCredit=\(otherResult.credit)")
    }

    func testScienceIntervalNarrativeContradictsActualStimulus() async throws {
        let exercise = try NFFallbackExerciseGenerator.generate(NFExerciseGenerationRequest(
            seed: 8_424_208_090_942_894_707, index: 0,
            lab: .scientificReasoning, purpose: .practice
        ))
        let intervals = try intervalsInScienceExercise(exercise)
        XCTAssertEqual(intervals.a, [18, 26])
        XCTAssertEqual(intervals.b, [27, 35])
        XCTAssertLessThan(intervals.a[1], intervals.b[0], "The displayed intervals are disjoint")
        XCTAssertTrue(exercise.prompt.contains("overlapping uncertainty intervals"))
        guard case let .singleChoice(schema) = exercise.interaction else {
            return XCTFail("Expected a single-choice science exercise")
        }
        let keyed = try XCTUnwrap(schema.options.first { $0.id == schema.correctOptionID })
        XCTAssertTrue(keyed.text.contains("overlapping uncertainty"))
        let result = NFExerciseScoringEngine.score(.singleChoice(optionID: keyed.id), for: exercise)
        XCTAssertTrue(result.isCorrect)
        print("NF_CONTENT_QA science prompt=\(exercise.prompt) A=\(intervals.a) B=\(intervals.b) keyed=\(keyed.text) credit=\(result.credit)")
    }

    func testAcceptedEquivalentResponseGetsCorrectButPartialCredit() async throws {
        let exercise = try NFFallbackExerciseGenerator.generate(NFExerciseGenerationRequest(
            seed: 100, index: 0, lab: .mentalMath, purpose: .practice,
            preferredAssessmentMechanicID: "mentalMath.fallback-variant-7"
        ))
        guard case let .logicState(schema) = exercise.interaction else {
            return XCTFail("Expected the estimate/plausibility/exact composite")
        }
        XCTAssertTrue(NFEstimateExactContract.isComposite(schema))
        var answer = schema.expectedFinalState
        answer[NFEstimateExactContract.plausibilityKey] = "yes"
        XCTAssertTrue(schema.acceptedEquivalentStates.contains(answer))
        let canonical = NFExerciseScoringEngine.score(
            .logicState(NFLogicStateSubmission(finalState: schema.expectedFinalState, violatedRuleID: nil)),
            for: exercise
        )
        let equivalent = NFExerciseScoringEngine.score(
            .logicState(NFLogicStateSubmission(finalState: answer, violatedRuleID: nil)),
            for: exercise
        )
        XCTAssertTrue(canonical.isCorrect)
        XCTAssertEqual(canonical.credit, 1, accuracy: 0.000_001)
        XCTAssertTrue(equivalent.isCorrect)
        XCTAssertEqual(equivalent.credit, 2.0 / 3.0, accuracy: 0.000_001)
        print("NF_CONTENT_QA equivalent response=\(answer) isCorrect=\(equivalent.isCorrect) credit=\(equivalent.credit) canonicalCredit=\(canonical.credit)")
    }

    func testValidRetrievalParaphrasesAndFormulaEquivalentsAreRejected() async throws {
        let probes: [(UInt64, String, String)] = [
            (1053, "general.arithmetic-mean", "Sum all observations then divide by their count"),
            (3532, "mathematics.square-derivative", "2*x"),
            (361, "mathematics.monomial-derivative-2-2", "4x")
        ]
        for (seed, target, response) in probes {
            let exercise = try shortTextRetrievalExercise(seed: seed, expectedTarget: target)
            guard case let .shortText(schema) = exercise.interaction else {
                return XCTFail("Expected short text")
            }
            let canonical = NFExerciseScoringEngine.score(.shortText(schema.expectedAnswer), for: exercise)
            let result = NFExerciseScoringEngine.score(.shortText(response), for: exercise)
            XCTAssertTrue(canonical.isCorrect)
            XCTAssertFalse(result.isCorrect)
            XCTAssertEqual(result.credit, 0, accuracy: 0.000_001)
            print("NF_CONTENT_QA retrieval target=\(target) prompt=\(exercise.prompt) input=\(response) expected=\(schema.expectedAnswer) isCorrect=\(result.isCorrect) credit=\(result.credit)")
        }
    }

    func testIncorrectCalculusAnswerAcceptedAfterCaseFolding() async throws {
        let exercise = try shortTextRetrievalExercise(
            seed: 1353, expectedTarget: "mathematics.integral-derivative-link"
        )
        guard case let .shortText(schema) = exercise.interaction else {
            return XCTFail("Expected short text")
        }
        let result = NFExerciseScoringEngine.score(.shortText("f(b) - f(a)"), for: exercise)
        XCTAssertEqual(schema.expectedAnswer, "F(b) minus F(a)")
        XCTAssertTrue(result.isCorrect)
        XCTAssertEqual(result.credit, 1, accuracy: 0.000_001)
        print("NF_CONTENT_QA calculus prompt=\(exercise.prompt) expected=\(schema.expectedAnswer) incorrectInput=f(b)-f(a) accepted=\(result.isCorrect)")
    }

    func testActualOfflineBankMechanicDistributionsAndInvalidIntervals() async throws {
        let labs: [TrainingLab] = [.transfer, .logicDebugging, .scientificReasoning, .retrieval]
        for lab in labs {
            let descriptors = NFOfflineQuestionBank.descriptors(for: lab)
            XCTAssertEqual(descriptors.count, 1000)
            var counts: [String: Int] = [:]
            var invalidIntervalCount = 0
            for descriptor in descriptors {
                let exercise = try NFFallbackExerciseGenerator.generate(NFExerciseGenerationRequest(
                    seed: descriptor.seed, index: 0, lab: lab, purpose: .practice,
                    localeIdentifier: "en", sourceContext: NFExerciseSourceContext(primaryField: .general)
                ))
                XCTAssertEqual(NFQuestionFingerprint.fingerprint(for: exercise), descriptor.semanticFingerprint)
                let prefix = exercise.templateFamily + "."
                let slug = exercise.templateID.hasPrefix(prefix)
                    ? String(exercise.templateID.dropFirst(prefix.count)) : exercise.templateID
                counts[slug, default: 0] += 1
                if lab == .scientificReasoning && slug == "data-forensics.uncertainty" {
                    let intervals = try intervalsInScienceExercise(exercise)
                    if intervals.a[1] < intervals.b[0] {
                        invalidIntervalCount += 1
                        XCTAssertTrue(exercise.prompt.contains("overlapping uncertainty intervals"))
                    }
                }
            }
            let sortedCounts = counts.keys.sorted().map { "\($0)=\(counts[$0]!)" }.joined(separator: "; ")
            print("NF_CONTENT_QA actualBank lab=\(lab.rawValue) count=\(descriptors.count) lastCandidate=\(descriptors.last?.candidateIndex ?? -1) families=\(sortedCounts) invalidIntervals=\(invalidIntervalCount)")
            switch lab {
            case .transfer:
                XCTAssertEqual(counts["field-shift.rate-product"], 986)
            case .logicDebugging:
                XCTAssertEqual(counts["trace.stale-derived-state"], 990)
            case .scientificReasoning:
                XCTAssertEqual(counts["claim.evidence.bounds"], 557)
                XCTAssertEqual(counts["data-forensics.uncertainty"], 436)
                XCTAssertEqual(invalidIntervalCount, 266)
            case .retrieval:
                XCTAssertEqual(counts["reconstruction.ordered-cycle"], 101)
            default:
                break
            }
        }
    }

    private func shortTextRetrievalExercise(seed: UInt64, expectedTarget: String) throws -> NFExercise {
        let exercise = try NFFallbackExerciseGenerator.generate(NFExerciseGenerationRequest(
            seed: seed, index: 0, lab: .retrieval, purpose: .practice,
            preferredAssessmentMechanicID: "retrieval.fallback-variant-1"
        ))
        XCTAssertTrue(exercise.tags.contains("knowledge-target.nf.retrieval.v1." + expectedTarget))
        return exercise
    }

    private func intervalsInScienceExercise(_ exercise: NFExercise) throws -> (a: [Int], b: [Int]) {
        let tables: [[[String]]] = exercise.representations.compactMap { representation in
            guard case let .table(headers, rows, _) = representation,
                  headers == ["Group", "Mean", "Interval"] else { return nil }
            return rows
        }
        let rows = try XCTUnwrap(tables.first)
        XCTAssertEqual(rows.count, 2)
        let a = rows[0][2].split(separator: "–").compactMap { Int($0) }
        let b = rows[1][2].split(separator: "–").compactMap { Int($0) }
        XCTAssertEqual(a.count, 2)
        XCTAssertEqual(b.count, 2)
        guard a.count == 2 && b.count == 2 else {
            throw NSError(domain: "NFContentQA", code: 1, userInfo: [NSLocalizedDescriptionKey: "Unexpected interval format: \(rows)"])
        }
        return (a, b)
    }
}

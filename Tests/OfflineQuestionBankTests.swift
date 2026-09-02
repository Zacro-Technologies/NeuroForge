import XCTest

@testable import NeuroForge

final class OfflineQuestionBankTests: XCTestCase {
    func testEveryLabShipsOneThousandCanonicalUniqueScorableQuestions() throws {
        XCTAssertEqual(NFOfflineQuestionBank.version, 2)
        XCTAssertEqual(NFOfflineQuestionBank.questionsPerLab, 1_000)
        XCTAssertEqual(NFOfflineQuestionBank.audit(), [])

        for lab in TrainingLab.allCases {
            let descriptors = NFOfflineQuestionBank.descriptors(for: lab)
            XCTAssertEqual(descriptors.count, 1_000, lab.rawValue)
            XCTAssertEqual(Set(descriptors.map(\.semanticFingerprint)).count, 1_000, lab.rawValue)

            var contracts: Set<String> = []
            var templateSlugs: Set<String> = []
            for descriptor in descriptors {
                let exercise = try NFFallbackExerciseGenerator.generate(
                    NFExerciseGenerationRequest(
                        seed: descriptor.seed,
                        index: 0,
                        lab: lab,
                        purpose: .practice,
                        localeIdentifier: "en",
                        sourceContext: NFExerciseSourceContext(primaryField: .general)
                    )
                )
                XCTAssertNoThrow(try NFExerciseSchemaValidator.validate(exercise), descriptor.id)
                XCTAssertEqual(
                    NFQuestionFingerprint.fingerprint(for: exercise),
                    descriptor.semanticFingerprint,
                    descriptor.id
                )
                XCTAssertTrue(
                    contracts.insert(NFQuestionFingerprint.canonicalContract(for: exercise)).inserted,
                    descriptor.id
                )
                templateSlugs.insert(exercise.templateID)

                let result = NFExerciseScoringEngine.score(correctResponse(for: exercise.interaction), for: exercise)
                XCTAssertTrue(result.isCorrect, descriptor.id)
                XCTAssertEqual(result.credit, 1, accuracy: 0.000_001, descriptor.id)
            }

            XCTAssertGreaterThanOrEqual(
                templateSlugs.count,
                NFFallbackExerciseGenerator.variantCount(for: lab),
                "\(lab.rawValue) bank collapsed one or more reviewed activity families"
            )
        }
    }

    func testAdaptivePopulationRemainsBlockedUntilTheNewBankIsSigned() {
        let evidence = NFOfflineQuestionBank.adaptivePopulationFloorEvidence

        XCTAssertTrue(evidence.deficits.isEmpty)
        XCTAssertFalse(evidence.catalogIntegrityVerified)
        XCTAssertFalse(evidence.satisfiesReleaseFloor)
    }

    private func correctResponse(for interaction: NFExerciseInteraction) -> NFExerciseResponse {
        switch interaction {
        case let .numeric(schema):
            .numeric(NFNumericSubmission(value: String(schema.answer.value), unit: schema.answer.canonicalUnit))
        case let .singleChoice(schema):
            .singleChoice(optionID: schema.correctOptionID)
        case let .multipleChoice(schema):
            .multipleChoice(optionIDs: schema.correctOptionIDs)
        case let .orderedSteps(schema):
            .orderedSteps(stepIDs: schema.correctOrder)
        case let .shortText(schema):
            .shortText(schema.expectedAnswer)
        case let .selfCheck(schema):
            .selfCheck(NFSelfCheckSubmission(
                rating: .matched,
                reflection: schema.asksForReflection ? "Matched the reference." : nil
            ))
        case let .claimEvidence(schema):
            .claimEvidence(NFClaimEvidenceSubmission(pairs: schema.correctPairs))
        case let .logicState(schema):
            .logicState(NFLogicStateSubmission(
                finalState: schema.expectedFinalState,
                violatedRuleID: schema.expectedViolatedRuleID
            ))
        }
    }
}

import XCTest

@testable import NeuroForge

final class UserFacingContentLintTests: XCTestCase {
    func testAuditExamplesFailWithTheirSpecificRule() throws {
        let examples: [(String, NFUserFacingContentLinter.Violation.Rule)] = [
            ("target.scientificReasoning", .rawIdentifier),
            ("causal_overreach", .rawIdentifier),
            ("claim.difference:evidence.means", .rawIdentifier),
            ("Use the target skill here.", .unresolvedPlaceholder),
            ("Compare the the representations.", .repeatedWord),
            ("Review the sample.; then answer.", .punctuationCollision),
            ("You completed 1 chapters.", .incorrectSingularGrammar),
            ("Resolve {{topic}} before publishing.", .unresolvedPlaceholder),
            ("A value of %@ is still unresolved.", .unresolvedPlaceholder)
        ]

        for (text, expectedRule) in examples {
            XCTAssertEqual(
                NFUserFacingContentLinter.lint(text)?.rule,
                expectedRule,
                text
            )
        }
    }

    func testNormalTechnicalCopyDoesNotTriggerFalsePositive() {
        let examples = [
            "Use x_1 and x_2 in the displayed equation.",
            "A had had B as its prior state before the transition.",
            "Choose 1 item, then compare 2 items.",
            "Estimate the input-output relationship; explain your limit.",
            "状態を比較し、根拠を1つ選んでください。"
        ]

        for text in examples {
            XCTAssertNil(NFUserFacingContentLinter.lint(text), text)
        }
    }

    func testEveryDeterministicFamilyPassesInEverySupportedLocale() throws {
        for localeIdentifier in ["en", "ja"] {
            for lab in TrainingLab.allCases {
                for variant in 0..<NFFallbackExerciseGenerator.variantCount(for: lab) {
                    let exercise = try NFFallbackExerciseGenerator.generate(
                        NFExerciseGenerationRequest(
                            seed: UInt64(90_000 + variant),
                            index: variant,
                            lab: lab,
                            purpose: .practice,
                            localeIdentifier: localeIdentifier,
                            sourceContext: NFExerciseSourceContext(primaryField: .engineering),
                            preferredAssessmentMechanicID: "\(lab.rawValue).fallback-variant-\(variant)"
                        )
                    )
                    XCTAssertEqual(NFUserFacingContentLinter.lint(exercise), [], "\(localeIdentifier):\(lab.rawValue):\(variant)")
                }
            }
        }
    }

    func testInternalMechanicIdentifierNeverBecomesLearnerFacingContext() throws {
        let exercise = try NFFallbackExerciseGenerator.generate(
            NFExerciseGenerationRequest(
                seed: 90_500,
                index: 0,
                lab: .logicDebugging,
                purpose: .practice,
                localeIdentifier: "en",
                sourceContext: NFExerciseSourceContext(
                    primaryField: .engineering,
                    topic: "target.logicDebugging",
                    targetSkills: [TrainingLab.logicDebugging.skillID]
                ),
                preferredAssessmentMechanicID: "target.logicDebugging"
            )
        )

        XCTAssertFalse(exercise.contextText?.contains("target.logicDebugging") == true)
        XCTAssertEqual(NFUserFacingContentLinter.lint(exercise), [])
    }

    func testEveryStructuredTransferMissionKindHasDistinctLintCleanContent() throws {
        var templateIDs = Set<String>()
        var prompts = Set<String>()

        for (index, kind) in NFTransferChallengeKind.allCases.enumerated() {
            let brief = NFExerciseTransferBrief(
                missionID: "mission-\(index)",
                seed: UInt64(index + 1),
                kind: kind,
                labs: [.scientificReasoning, .quantitative],
                skillIDs: [TrainingLab.transfer.skillID],
                requiredDimensions: ["representation", "field"]
            )
            let exercise = try NFFallbackExerciseGenerator.generate(
                NFExerciseGenerationRequest(
                    seed: UInt64(91_000 + index),
                    index: 0,
                    lab: .transfer,
                    purpose: .appliedTransfer,
                    localeIdentifier: "en",
                    sourceContext: NFExerciseSourceContext(
                        primaryField: .physics,
                        transferBrief: brief
                    )
                )
            )

            XCTAssertEqual(NFUserFacingContentLinter.lint(exercise), [], kind.rawValue)
            templateIDs.insert(exercise.templateID)
            prompts.insert(exercise.prompt)
        }

        XCTAssertEqual(templateIDs.count, NFTransferChallengeKind.allCases.count)
        XCTAssertEqual(prompts.count, NFTransferChallengeKind.allCases.count)
    }

    func testOneWeeklyMissionRotatesReviewedMechanicsInsteadOfRepeatingANumericTemplate() throws {
        let brief = NFExerciseTransferBrief(
            missionID: "mission-variety",
            seed: 92_000,
            kind: .multiRepresentationTransform,
            labs: [.scientificReasoning, .logicDebugging],
            skillIDs: [TrainingLab.transfer.skillID],
            requiredDimensions: ["representation", "response_type", "field"]
        )
        let exercises = try (0..<NFTransferChallengeKind.allCases.count).map { index in
            try NFFallbackExerciseGenerator.generate(
                NFExerciseGenerationRequest(
                    seed: brief.seed,
                    index: index,
                    lab: .transfer,
                    purpose: .appliedTransfer,
                    localeIdentifier: "en",
                    sourceContext: NFExerciseSourceContext(primaryField: .general, transferBrief: brief)
                )
            )
        }

        XCTAssertEqual(Set(exercises.map(\.templateID)).count, NFTransferChallengeKind.allCases.count)
        XCTAssertEqual(Set(exercises.map(\.prompt)).count, NFTransferChallengeKind.allCases.count)
        XCTAssertEqual(Set(exercises.flatMap(\.tags).filter { $0.hasPrefix("challenge.") }).count, NFTransferChallengeKind.allCases.count)
        XCTAssertTrue(exercises.allSatisfy { NFUserFacingContentLinter.lint($0).isEmpty })
    }

    func testSignedReleaseCatalogCopyPassesContentLint() {
        XCTAssertFalse(NFReleaseContentCatalog.audit().contains { $0.hasPrefix("content-lint:") })
    }
}

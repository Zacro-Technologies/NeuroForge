import Foundation
import RealityKit
import XCTest

@testable import NeuroForge

final class GeneralExerciseEngineTests: XCTestCase {
    func testReflectionReasonsDefaultToAConciseRelevantSetWhileGroupsPreserveEveryChoice() {
        let grouped = NFErrorReflectionGroup.allCases.flatMap(\.choices)
        XCTAssertEqual(grouped.count, Set(grouped).count)
        XCTAssertEqual(Set(grouped), Set(NFErrorReflectionCode.allCases))

        for lab in TrainingLab.allCases {
            let candidate = NFErrorReflectionCode.candidate(for: "input_notation", lab: lab)
            let choices = NFErrorReflectionCode.conciseChoices(candidate: candidate, lab: lab)
            XCTAssertLessThanOrEqual(choices.count, 5)
            XCTAssertEqual(choices.count, Set(choices).count)
            XCTAssertTrue(choices.contains(candidate))
            XCTAssertEqual(choices.last, .other)
        }
    }

    func testRestrictedPseudocodeInterpreterValidatesTracesWithoutParsingCode() throws {
        let program: [NFPseudocodeStatement] = [
            .assign(name: "index", expression: .value(.integer(0))),
            .whileLoop(
                condition: .lessThan(.variable("index"), .inputCount),
                iterationLimit: 8,
                body: [
                    .visitInput(index: .variable("index")),
                    .assign(name: "index", expression: .add(.variable("index"), .value(.integer(1))))
                ]
            )
        ]

        let result = try NFRestrictedPseudocodeInterpreter.execute(program, inputCount: 3)
        XCTAssertEqual(result.integer(named: "index"), 3)
        XCTAssertEqual(result.visitedInputIndices, [0, 1, 2])
    }

    func testRestrictedPseudocodeInterpreterFailsClosedOnBoundsAndInfiniteLoops() {
        XCTAssertThrowsError(try NFRestrictedPseudocodeInterpreter.execute(
            [.visitInput(index: .value(.integer(1)))],
            inputCount: 1
        )) { error in
            XCTAssertEqual(error as? NFPseudocodeRuntimeError, .inputIndexOutOfBounds(1))
        }

        XCTAssertThrowsError(try NFRestrictedPseudocodeInterpreter.execute([
            .whileLoop(
                condition: .value(.boolean(true)),
                iterationLimit: 2,
                body: []
            )
        ])) { error in
            XCTAssertEqual(error as? NFPseudocodeRuntimeError, .iterationLimitExceeded)
        }
    }

    func testPseudocodeDisplaySkinsRenderDistinctSyntaxOverOneExecutableAST() throws {
        let program: [NFPseudocodeStatement] = [
            .assign(name: "index", expression: .value(.integer(0))),
            .whileLoop(
                condition: .lessThan(.variable("index"), .inputCount),
                iterationLimit: 8,
                body: [
                    .visitInput(index: .variable("index")),
                    .assign(
                        name: "index",
                        expression: .add(.variable("index"), .value(.integer(1)))
                    )
                ]
            )
        ]

        let rendered = Dictionary(uniqueKeysWithValues: NFPseudocodeDisplaySkin.allCases.map {
            ($0, NFPseudocodeRenderer.render(program, skin: $0))
        })
        XCTAssertEqual(Set(rendered.values).count, NFPseudocodeDisplaySkin.allCases.count)
        XCTAssertTrue(rendered[.languageNeutral]?.contains("END WHILE") == true)
        XCTAssertTrue(rendered[.pythonLike]?.contains("while index < len(input):") == true)
        XCTAssertTrue(rendered[.javaScriptLike]?.contains("input.length") == true)
        XCTAssertTrue(rendered[.javaScriptLike]?.contains(";") == true)
        XCTAssertTrue(rendered[.swiftLike]?.contains("input.count") == true)

        // Rendering is presentation-only. All four views share this exact
        // interpreter result and therefore cannot change scoring semantics.
        let execution = try NFRestrictedPseudocodeInterpreter.execute(program, inputCount: 3)
        XCTAssertEqual(execution.integer(named: "index"), 3)
        XCTAssertEqual(execution.visitedInputIndices, [0, 1, 2])
    }

    func testScientificFigureForensicsIncludesInspectableSeededRawDataset() throws {
        var exercise: NFExercise?
        for seed in 0..<512 where exercise == nil {
            let candidate = try NFFallbackExerciseGenerator.generate(NFExerciseGenerationRequest(
                seed: UInt64(seed),
                index: 0,
                lab: .scientificReasoning,
                purpose: .practice
            ))
            if candidate.tags.contains("seeded-dataset") { exercise = candidate }
        }
        let resolved = try XCTUnwrap(exercise)
        let tables: [([String], [[String]])] = resolved.representations.compactMap { representation in
            guard case let .table(headers, rows, _) = representation else { return nil }
            return (headers, rows)
        }
        let raw = try XCTUnwrap(tables.first { $0.0.contains("Observation") })
        XCTAssertEqual(raw.0, ["Group", "Observation", "Value"])
        XCTAssertEqual(raw.1.count, 16)
        XCTAssertEqual(Set(raw.1.compactMap(\.first)), Set(["A", "B"]))
        XCTAssertTrue(raw.1.allSatisfy { $0.count == 3 && Int($0[1]) != nil && Int($0[2]) != nil })
        XCTAssertNoThrow(try NFExerciseSchemaValidator.validate(resolved))
    }

    func testGeneratorIsDeterministicForEveryLabAndPurpose() throws {
        var IDs = Set<String>()

        for lab in TrainingLab.allCases {
            for purpose in NFExercisePurpose.allCases {
                let request = NFExerciseGenerationRequest(
                    seed: 0xC0FFEE,
                    index: 7,
                    lab: lab,
                    purpose: purpose,
                    sourceContext: NFExerciseSourceContext(
                        primaryField: .physics,
                        topic: "orbital dynamics",
                        domainVocabulary: ["momentum", "orbit"]
                    )
                )
                let first = try NFFallbackExerciseGenerator.generate(request)
                let second = try NFFallbackExerciseGenerator.generate(request)

                XCTAssertEqual(first, second)
                XCTAssertEqual(first.lab, lab)
                XCTAssertEqual(first.purpose, purpose)
                XCTAssertEqual(first.evidenceClass, purpose.evidenceClass)
                XCTAssertEqual(first.assessmentProtected, purpose.isProtectedAssessment)
                XCTAssertEqual(first.generatorVersion, NFFallbackExerciseGenerator.generatorVersion)
                XCTAssertEqual(first.schemaVersion, NFFallbackExerciseGenerator.schemaVersion)
                XCTAssertFalse(first.provenance.contentDigest.isEmpty)
                XCTAssertNoThrow(try NFExerciseSchemaValidator.validate(first))
                IDs.insert(first.id)
            }
        }

        XCTAssertEqual(IDs.count, TrainingLab.allCases.count * NFExercisePurpose.allCases.count)
    }

    func testDifferentSeedsAndIndicesProduceStableUniqueItemIdentity() throws {
        var IDs = Set<String>()
        let count = 128

        for index in 0..<count {
            let request = NFExerciseGenerationRequest(
                seed: UInt64(index % 11),
                index: index,
                lab: TrainingLab.allCases[index % TrainingLab.allCases.count],
                purpose: .practice
            )
            let exercise = try NFFallbackExerciseGenerator.generate(request)
            XCTAssertTrue(IDs.insert(exercise.id).inserted)
        }

        XCTAssertEqual(IDs.count, count)
    }

    func testStructuredTransferBriefControlsContentSkillsDimensionsAndScoring() throws {
        let seed: UInt64 = 0x7A_A5_F3_12
        var templateIDs = Set<String>()

        for kind in NFTransferChallengeKind.allCases {
            let brief = NFExerciseTransferBrief(
                missionID: "mission.\(kind.rawValue)",
                seed: seed,
                kind: kind,
                labs: [.quantitative, .logicDebugging],
                skillIDs: [TrainingLab.quantitative.skillID, TrainingLab.logicDebugging.skillID],
                requiredDimensions: ["representation", "field", "response_type"]
            )
            let request = NFExerciseGenerationRequest(
                seed: seed,
                index: 0,
                lab: .transfer,
                purpose: .appliedTransfer,
                sourceContext: NFExerciseSourceContext(
                    primaryField: .dataScience,
                    targetSkills: brief.skillIDs,
                    transferBrief: brief
                ),
                targetDifficulty: 0.7
            )

            let first = try NFFallbackExerciseGenerator.generate(request)
            let duplicate = try NFFallbackExerciseGenerator.generate(request)
            XCTAssertEqual(first, duplicate)
            XCTAssertEqual(first.sourceContext.transferBrief, brief)
            XCTAssertEqual(first.title, kind.title)
            XCTAssertTrue(first.prompt.contains(TrainingLab.quantitative.shortTitle))
            XCTAssertTrue(first.prompt.contains(TrainingLab.logicDebugging.shortTitle))
            XCTAssertTrue(first.contextText?.contains("representation, field, response type") == true)
            XCTAssertTrue(first.tags.contains("mission.\(kind.rawValue)"))
            XCTAssertTrue(first.tags.contains("transfer-lab.quantitative"))
            XCTAssertTrue(first.tags.contains("transfer-lab.logicDebugging"))
            XCTAssertEqual(first.skillWeights[TrainingLab.transfer.skillID] ?? -1, 0.4, accuracy: 1e-12)
            XCTAssertEqual(first.skillWeights[TrainingLab.quantitative.skillID] ?? -1, 0.3, accuracy: 1e-12)
            XCTAssertEqual(first.skillWeights[TrainingLab.logicDebugging.skillID] ?? -1, 0.3, accuracy: 1e-12)
            XCTAssertEqual(first.skillWeights.values.reduce(0, +), 1, accuracy: 1e-12)
            XCTAssertNoThrow(try NFExerciseSchemaValidator.validate(first))

            let result = NFExerciseScoringEngine.score(
                correctResponse(for: first.interaction),
                for: first
            )
            XCTAssertTrue(result.isCorrect)
            XCTAssertEqual(result.credit, 1, accuracy: 1e-12)
            templateIDs.insert(first.templateID)
        }

        XCTAssertEqual(templateIDs.count, NFTransferChallengeKind.allCases.count)

        let rotationBrief = NFExerciseTransferBrief(
            missionID: "mission.rotates-reviewed-mechanics",
            seed: seed,
            kind: .abstractReconstruction,
            labs: [.quantitative, .logicDebugging],
            skillIDs: [TrainingLab.quantitative.skillID, TrainingLab.logicDebugging.skillID],
            requiredDimensions: ["representation", "field"]
        )
        let rotatedChallengeTags = try Set((0..<NFTransferChallengeKind.allCases.count).map { index in
            let exercise = try NFFallbackExerciseGenerator.generate(NFExerciseGenerationRequest(
                seed: seed,
                index: index,
                lab: .transfer,
                purpose: .appliedTransfer,
                sourceContext: NFExerciseSourceContext(
                    targetSkills: rotationBrief.skillIDs,
                    transferBrief: rotationBrief
                )
            ))
            return try XCTUnwrap(exercise.tags.first { $0.hasPrefix("challenge.") })
        })
        XCTAssertEqual(
            rotatedChallengeTags,
            Set(NFTransferChallengeKind.allCases.map { "challenge.\($0.rawValue)" })
        )

        let firstBrief = NFExerciseTransferBrief(
            missionID: "mission.dimension-control",
            seed: seed,
            kind: .abstractReconstruction,
            labs: [.quantitative, .logicDebugging],
            skillIDs: [TrainingLab.quantitative.skillID, TrainingLab.logicDebugging.skillID],
            requiredDimensions: ["representation", "field"]
        )
        let changedBrief = NFExerciseTransferBrief(
            missionID: firstBrief.missionID,
            seed: seed,
            kind: firstBrief.kind,
            labs: [.scientificReasoning, .spatial],
            skillIDs: [TrainingLab.scientificReasoning.skillID, TrainingLab.spatial.skillID],
            requiredDimensions: ["delay", "stimulus_category"]
        )
        func generated(with brief: NFExerciseTransferBrief) throws -> NFExercise {
            try NFFallbackExerciseGenerator.generate(NFExerciseGenerationRequest(
                seed: seed,
                index: 0,
                lab: .transfer,
                purpose: .appliedTransfer,
                sourceContext: NFExerciseSourceContext(targetSkills: brief.skillIDs, transferBrief: brief)
            ))
        }
        let original = try generated(with: firstBrief)
        let changed = try generated(with: changedBrief)
        XCTAssertNotEqual(original.id, changed.id)
        XCTAssertNotEqual(original.prompt, changed.prompt)
        XCTAssertNotEqual(original.skillWeights, changed.skillWeights)
        XCTAssertTrue(changed.contextText?.contains("delay, stimulus category") == true)
    }

    func testAllSupportedInteractionSchemasAreGeneratedAndCorrectResponsesScoreExactly() throws {
        var interactionKinds = Set<String>()

        for lab in TrainingLab.allCases {
            for seed in 0..<128 {
                let exercise = try NFFallbackExerciseGenerator.generate(
                    NFExerciseGenerationRequest(
                        seed: UInt64(seed),
                        index: seed,
                        lab: lab,
                        purpose: .practice
                    )
                )
                interactionKinds.insert(interactionKind(exercise.interaction))
                let response = correctResponse(for: exercise.interaction)
                let result = NFExerciseScoringEngine.score(response, for: exercise)

                XCTAssertTrue(result.isCorrect, "Expected correct score for \(lab.rawValue), \(interactionKind(exercise.interaction))")
                XCTAssertEqual(result.credit, 1, accuracy: 1e-12)
                XCTAssertNil(result.errorCode)
                XCTAssertFalse(result.feedback.isDelayed)
                XCTAssertNotNil(result.expectedAnswerSummary)
            }
        }

        XCTAssertEqual(
            interactionKinds,
            Set(["numeric", "singleChoice", "multipleChoice", "orderedSteps", "shortText", "selfCheck", "claimEvidence", "logicState"])
        )
    }

    func testResponseRevisionPolicyIsExplicitAndProtectedItemsAlwaysLock() throws {
        for lab in TrainingLab.allCases {
            for seed in 0..<48 {
                let practice = try NFFallbackExerciseGenerator.generate(NFExerciseGenerationRequest(
                    seed: UInt64(seed),
                    index: seed,
                    lab: lab,
                    purpose: .practice
                ))
                let expected: NFResponseEditPolicy = switch practice.interaction {
                case .orderedSteps, .shortText, .claimEvidence, .logicState: .editableBeforeCommit
                case .numeric, .singleChoice, .multipleChoice, .selfCheck: .lockedAfterSubmit
                }
                XCTAssertEqual(practice.responseEditPolicy, expected)

                let protected = try NFFallbackExerciseGenerator.generate(NFExerciseGenerationRequest(
                    seed: UInt64(seed),
                    index: seed,
                    lab: lab,
                    purpose: .assessmentHoldout
                ))
                XCTAssertEqual(protected.responseEditPolicy, .lockedAfterSubmit)
            }
        }
    }

    func testDeterministicInventoryCoversNamedP0MechanicsAcrossAllSevenLabs() throws {
        let requiredTags: [TrainingLab: Set<String>] = [
            .mentalMath: [
                "rapid-recall", "decompose", "strategy-duel", "estimate-first",
                "representation-relay", "scientific-notation-shift", "missing-number",
                "error-detective", "calculation-chain", "mental-or-machine"
            ],
            .spatial: [
                "2d-rotation", "3d-rotation", "cross-section", "orthographic-projection",
                "folding-net", "vector-transformation"
            ],
            .quantitative: [
                "fermi-estimation", "dimensional-analysis", "scaling-law", "conditional-probability",
                "bayesian-updating", "expected-value", "sampling-variability", "uncertainty-interval"
            ],
            .scientificReasoning: [
                "experimental-design", "confound", "next-experiment", "data-forensics",
                "figure-to-claim", "reviewer-mode", "competing-hypotheses", "paper-sprint"
            ],
            .logicDebugging: [
                "state-tracing", "necessary-sufficient", "counterexample", "proof-step-ordering",
                "first-invalid-step", "boundary-case", "complexity-comparison", "repair-pseudocode"
            ],
            .retrieval: [
                "free-recall", "short-answer", "cloze", "explain-a-concept",
                "source-supported", "derivation-ordering"
            ],
            .transfer: [
                "surface-context", "field-transfer", "representation-shift", "causal-structure",
                "interacting-variables", "constraint-shift", "response-shift"
            ]
        ]
        let minimumTemplateCounts: [TrainingLab: Int] = [
            .mentalMath: 10,
            .spatial: 6,
            .quantitative: 8,
            .scientificReasoning: 8,
            .logicDebugging: 8,
            .retrieval: 6,
            .transfer: 7
        ]

        for lab in TrainingLab.allCases {
            var templates = Set<String>()
            var tags = Set<String>()

            for seed in 0..<512 {
                let exercise = try NFFallbackExerciseGenerator.generate(
                    NFExerciseGenerationRequest(
                        seed: UInt64(seed),
                        index: seed,
                        lab: lab,
                        purpose: .practice,
                        sourceContext: NFExerciseSourceContext(
                            primaryField: STEMField.allCases[seed % STEMField.allCases.count],
                            topic: "inventory coverage",
                            transferOriginField: .engineering
                        )
                    )
                )
                templates.insert(exercise.templateID)
                tags.formUnion(exercise.tags)
                XCTAssertNoThrow(try NFExerciseSchemaValidator.validate(exercise))

                let result = NFExerciseScoringEngine.score(correctResponse(for: exercise.interaction), for: exercise)
                XCTAssertTrue(result.isCorrect, "Authoritative key failed for \(exercise.templateID)")
                XCTAssertEqual(result.credit, 1, accuracy: 1e-12)
            }

            XCTAssertGreaterThanOrEqual(templates.count, minimumTemplateCounts[lab] ?? 0, "Insufficient deterministic breadth for \(lab.rawValue)")
            let missingTags = (requiredTags[lab] ?? []).subtracting(tags)
            XCTAssertTrue(missingTags.isEmpty, "Missing \(lab.rawValue) mechanics: \(missingTags.sorted())")
        }
    }

    func testPreferredAssessmentFormatsSelectCompatibleDeterministicInteractions() throws {
        let cases: [(TrainingLab, NFAssessmentItemFormat, String)] = [
            (.mentalMath, .numericEntry, "numeric"),
            (.mentalMath, .singleChoice, "singleChoice"),
            (.spatial, .diagramMatch, "singleChoice"),
            (.spatial, .singleChoice, "singleChoice"),
            (.quantitative, .numericEntry, "numeric"),
            (.quantitative, .singleChoice, "singleChoice"),
            (.scientificReasoning, .claimEvidence, "claimEvidence"),
            (.scientificReasoning, .singleChoice, "singleChoice"),
            (.logicDebugging, .stateTrace, "logicState"),
            (.logicDebugging, .singleChoice, "singleChoice"),
            (.logicDebugging, .orderedSteps, "orderedSteps"),
            (.retrieval, .orderedSteps, "orderedSteps"),
            (.transfer, .numericEntry, "numeric"),
            (.transfer, .claimEvidence, "claimEvidence")
        ]

        for (offset, entry) in cases.enumerated() {
            let request = NFExerciseGenerationRequest(
                seed: UInt64(9_000 + offset),
                index: offset,
                lab: entry.0,
                purpose: .baseline,
                targetDifficulty: 0.55,
                preferredAssessmentFormat: entry.1
            )
            let first = try NFFallbackExerciseGenerator.generate(request)
            let second = try NFFallbackExerciseGenerator.generate(request)

            XCTAssertEqual(first, second)
            XCTAssertEqual(interactionKind(first.interaction), entry.2, "Format \(entry.1.rawValue) was ignored for \(entry.0.rawValue)")
            XCTAssertNoThrow(try NFExerciseSchemaValidator.validate(first))
            XCTAssertTrue(NFExerciseScoringEngine.score(correctResponse(for: first.interaction), for: first).isCorrect)

            if entry.1 == .diagramMatch {
                XCTAssertTrue(first.representations.contains { representation in
                    if case .spatial = representation { return true }
                    return false
                })
            }
        }
    }

    @MainActor
    func testSpatialDifficultyVectorAndNativeThreeDimensionalSceneAreDeterministic() throws {
        let expectedRotations: [Int: Double] = [
            0: 90, 1: 90, 2: 0, 3: 0, 4: 90, 5: 0
        ]

        for variant in 0..<6 {
            let format: NFAssessmentItemFormat = variant.isMultiple(of: 2) ? .diagramMatch : .singleChoice
            let exercise = try NFFallbackExerciseGenerator.generate(NFExerciseGenerationRequest(
                seed: 80_000 + UInt64(variant),
                index: variant,
                lab: .spatial,
                purpose: .practice,
                preferredAssessmentFormat: format,
                preferredAssessmentMechanicID: "spatial.fallback-variant-\(variant)"
            ))
            let spatialMetadata: [NFSpatialRepresentationMetadata] = exercise.representations.compactMap { representation in
                guard case let .spatial(metadata) = representation else { return nil }
                return metadata
            }
            let metadata = try XCTUnwrap(spatialMetadata.first)
            let parameters = try XCTUnwrap(exercise.spatialDifficultyParameters)

            XCTAssertEqual(parameters.viewpoint, metadata.viewpoint)
            XCTAssertEqual(parameters.rotationMagnitudeDegrees, expectedRotations[variant])
            XCTAssertTrue((0...1).contains(parameters.objectComplexity))
            XCTAssertTrue((0...1).contains(parameters.distractorSimilarity))
            XCTAssertEqual(
                parameters.responseMode,
                format == .diagramMatch ? .diagramMatch : .singleChoice
            )
            XCTAssertNoThrow(try NFExerciseSchemaValidator.validate(exercise))

            let encoded = try JSONEncoder().encode(metadata)
            XCTAssertEqual(try JSONDecoder().decode(NFSpatialRepresentationMetadata.self, from: encoded), metadata)

            if metadata.dimension == .threeDimensional {
                let scene = NFSpatialRealitySceneFactory.makeScene(for: metadata)
                XCTAssertEqual(scene.name, NFSpatialRealitySceneFactory.rootEntityName)
                XCTAssertFalse(scene.children.isEmpty)
                XCTAssertNotNil(
                    scene.findEntity(named: NFSpatialRealitySceneFactory.stimulusEntityName)
                        ?? scene.findEntity(named: "point.A")
                )
            }
        }
    }

    func testLegacySpatialMetadataDecodesWithExplicitSafeDifficultyDefaults() throws {
        let exercise = try NFFallbackExerciseGenerator.generate(NFExerciseGenerationRequest(
            seed: 900,
            index: 1,
            lab: .spatial,
            purpose: .practice,
            preferredAssessmentMechanicID: "spatial.fallback-variant-1"
        ))
        let spatialMetadata: [NFSpatialRepresentationMetadata] = exercise.representations.compactMap { representation in
            guard case let .spatial(metadata) = representation else { return nil }
            return metadata
        }
        let metadata = try XCTUnwrap(spatialMetadata.first)
        let encoded = try JSONEncoder().encode(metadata)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        object.removeValue(forKey: "difficultyParameters")
        let legacyData = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        let decoded = try JSONDecoder().decode(NFSpatialRepresentationMetadata.self, from: legacyData)

        XCTAssertEqual(
            decoded.difficultyParameters,
            NFSpatialDifficultyParameters.legacy(viewpoint: metadata.viewpoint)
        )
    }

    func testAssessmentDescriptorsSelectTheirDeclaredFallbackMechanic() throws {
        let expectedSlugs: [TrainingLab: [Int: String]] = [
            .mentalMath: [
                0: "rapid-recall", 1: "decompose.compensation", 2: "representation-relay",
                3: "scientific-notation", 5: "error-detective", 6: "calculation-chain",
                7: "estimate-first", 9: "strategy-duel"
            ],
            .spatial: [
                0: "coordinate.rotate-ccw", 1: "rotation.3d-z-axis", 2: "cross-section.",
                3: "orthographic.top-view", 5: "vector.reflect-y-axis"
            ],
            .quantitative: [
                1: "fermi.decomposition", 4: "probability.bayes-natural-frequency",
                5: "probability.expected-value", 6: "sampling.regression-to-mean",
                7: "uncertainty.interval-interpretation"
            ],
            .scientificReasoning: [
                0: "claim.evidence.bounds", 1: "design.identify-confound",
                2: "design.next-discriminating-experiment", 3: "data-forensics.uncertainty",
                7: "design.discriminating-sequence"
            ],
            .logicDebugging: [
                0: "trace.stale-derived-state", 1: "conditions.divisibility",
                2: "counterexample.even-product", 3: "proof.order-odd-sum",
                4: "proof.first-invalid-division",
                5: "debug.boundary-last-element", 7: "debug.repair-loop-bound",
                8: "calibration.observed-frequency"
            ]
        ]

        for block in NFAssessmentBlockKind.allCases {
            let descriptors = NFAssessmentEngine.makePracticeCandidates(block: block, seed: 7_311)
            let uniqueMechanics = Dictionary(descriptors.map { ($0.mechanicID, $0) }, uniquingKeysWith: { first, _ in first })
            for descriptor in uniqueMechanics.values {
                let marker = ".fallback-variant-"
                let variantText = try XCTUnwrap(descriptor.mechanicID.components(separatedBy: marker).last)
                let variant = try XCTUnwrap(Int(variantText))
                let expectedSlug = try XCTUnwrap(expectedSlugs[descriptor.lab]?[variant])
                let exercise = try NFFallbackExerciseGenerator.generate(NFExerciseGenerationRequest(
                    seed: descriptor.seed,
                    index: 0,
                    lab: descriptor.lab,
                    purpose: .baseline,
                    targetDifficulty: descriptor.difficulty,
                    preferredAssessmentFormat: descriptor.format,
                    preferredAssessmentMechanicID: descriptor.mechanicID
                ))

                XCTAssertTrue(
                    exercise.templateID.contains(expectedSlug),
                    "\(descriptor.mechanicID) generated \(exercise.templateID)"
                )
                XCTAssertTrue(NFExerciseScoringEngine.score(correctResponse(for: exercise.interaction), for: exercise).isCorrect)
            }
        }
    }

    func testSpatialInventoryIncludesMultipleStimulusCategoriesAndThreeDimensionalMechanics() throws {
        var categories = Set<String>()
        var operations = Set<NFSpatialOperation>()
        var foundThreeDimensional = false

        for seed in 0..<256 {
            let exercise = try generate(lab: .spatial, purpose: .practice, seed: UInt64(seed))
            for representation in exercise.representations {
                guard case let .spatial(metadata) = representation else { continue }
                categories.insert(metadata.stimulusCategory)
                operations.formUnion(metadata.operations)
                foundThreeDimensional = foundThreeDimensional || metadata.dimension == .threeDimensional
                XCTAssertFalse(metadata.accessibilityDescription.isEmpty)
            }
        }

        XCTAssertGreaterThanOrEqual(categories.count, 6)
        XCTAssertTrue(foundThreeDimensional)
        XCTAssertTrue(operations.isSuperset(of: [.rotate, .project, .crossSection, .coordinateTransform, .diagramEquationMatch]))
    }

    func testEveryDocumentRetrievalVariantStaysChunkGroundedAndProtectedPoolsStayBundled() throws {
        let sourceContext = NFExerciseSourceContext(
            primaryField: .computing,
            topic: "loop invariants",
            materialTitle: "Private algorithm notes",
            sourceDocumentIDs: ["document.private"],
            sourceChunkIDs: ["chunk.private"],
            groundingFacts: [
                NFExerciseGroundingFact(
                    id: "fact.private.inventory",
                    statement: "What invariant do the notes require?",
                    expectedAnswer: "The processed prefix remains sorted",
                    acceptedAlternatives: ["the processed prefix is sorted"],
                    citationIDs: ["chunk.private"]
                )
            ]
        )
        var documentTemplates = Set<String>()

        for seed in 0..<256 {
            let personal = try NFFallbackExerciseGenerator.generate(
                NFExerciseGenerationRequest(
                    seed: UInt64(seed),
                    index: seed,
                    lab: .retrieval,
                    purpose: .documentPractice,
                    sourceContext: sourceContext
                )
            )
            documentTemplates.insert(personal.templateID)
            XCTAssertTrue(personal.provenance.isSourceGrounded)
            XCTAssertEqual(personal.citations.count, 1)
            XCTAssertEqual(personal.citations.first?.sourceChunkID, "chunk.private")
            XCTAssertEqual(personal.provenance.sourceChunkIDs, ["chunk.private"])
            XCTAssertTrue(personal.prompt.contains("What invariant do the notes require?"))

            let protected = try NFFallbackExerciseGenerator.generate(
                NFExerciseGenerationRequest(
                    seed: UInt64(seed),
                    index: seed,
                    lab: .retrieval,
                    purpose: .assessmentHoldout,
                    sourceContext: sourceContext
                )
            )
            XCTAssertTrue(protected.citations.isEmpty)
            XCTAssertFalse(protected.provenance.isSourceGrounded)
            if case .selfCheck = protected.interaction {
                XCTFail("Protected retrieval must retain an objective deterministic key")
            }
        }

        XCTAssertGreaterThanOrEqual(documentTemplates.count, 6)
    }

    func testExerciseAndResponseCodableRoundTripPreservesSchema() throws {
        let context = NFExerciseSourceContext(
            primaryField: .chemistry,
            secondaryFields: [.dataScience],
            topic: "reaction kinetics",
            materialTitle: "Kinetics notes",
            sourceDocumentIDs: ["document.1"],
            sourceChunkIDs: ["chunk.1"],
            domainVocabulary: ["activation energy"],
            targetSkills: ["claim evaluation"],
            audienceDescription: "Undergraduate chemistry",
            transferOriginField: .mathematics,
            groundingFacts: [
                NFExerciseGroundingFact(
                    id: "fact.1",
                    statement: "How does a catalyst affect activation energy?",
                    expectedAnswer: "It lowers activation energy",
                    acceptedAlternatives: ["lowers the activation barrier"],
                    citationIDs: ["chunk.1"]
                )
            ]
        )
        let exercise = try NFFallbackExerciseGenerator.generate(
            NFExerciseGenerationRequest(
                seed: 42,
                index: 3,
                lab: .retrieval,
                purpose: .documentPractice,
                localeIdentifier: "en-US",
                sourceContext: context
            )
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let decoder = JSONDecoder()

        let exerciseData = try encoder.encode(exercise)
        let decodedExercise = try decoder.decode(NFExercise.self, from: exerciseData)
        XCTAssertEqual(decodedExercise, exercise)
        XCTAssertEqual(decodedExercise.citations.count, 1)
        XCTAssertTrue(decodedExercise.provenance.isSourceGrounded)
        XCTAssertEqual(decodedExercise.provenance.sourceChunkIDs, ["chunk.1"])

        let response = correctResponse(for: exercise.interaction)
        let responseData = try encoder.encode(response)
        XCTAssertEqual(try decoder.decode(NFExerciseResponse.self, from: responseData), response)
    }

    func testProtectedBaselineAndHoldoutPoolsNeverSharePracticeNamespace() throws {
        for lab in TrainingLab.allCases {
            let baseline = try generate(lab: lab, purpose: .baseline, seed: 1)
            let practice = try generate(lab: lab, purpose: .practice, seed: 1)
            let holdout = try generate(lab: lab, purpose: .assessmentHoldout, seed: 1)

            XCTAssertTrue(baseline.templateFamily.contains(".baseline."))
            XCTAssertTrue(holdout.templateFamily.contains(".holdout."))
            XCTAssertTrue(practice.templateFamily.contains(".practice."))
            XCTAssertNotEqual(baseline.templateFamily, practice.templateFamily)
            XCTAssertNotEqual(holdout.templateFamily, practice.templateFamily)
            XCTAssertNotEqual(baseline.templateFamily, holdout.templateFamily)
            XCTAssertTrue(baseline.assessmentProtected)
            XCTAssertTrue(holdout.assessmentProtected)
            XCTAssertFalse(practice.assessmentProtected)
            XCTAssertTrue(baseline.feedback.hintLadder.isEmpty)
            XCTAssertTrue(holdout.feedback.hintLadder.isEmpty)
        }
    }

    func testUserMaterialCanOnlyAuthorDocumentPractice() throws {
        let sourceContext = NFExerciseSourceContext(
            primaryField: .chemistry,
            topic: "kinetics",
            materialTitle: "Private kinetics notes",
            sourceDocumentIDs: ["document.private", "document.unused"],
            sourceChunkIDs: ["chunk.private", "chunk.unused"],
            groundingFacts: [
                NFExerciseGroundingFact(
                    id: "fact.private",
                    statement: "What relationship do the notes define?",
                    expectedAnswer: "A private material answer",
                    acceptedAlternatives: [],
                    citationIDs: ["chunk.private"]
                )
            ]
        )

        let baseline = try NFFallbackExerciseGenerator.generate(
            NFExerciseGenerationRequest(
                seed: 8,
                index: 0,
                lab: .retrieval,
                purpose: .baseline,
                sourceContext: sourceContext
            )
        )
        XCTAssertTrue(baseline.citations.isEmpty)
        XCTAssertFalse(baseline.provenance.isSourceGrounded)
        XCTAssertFalse(baseline.prompt.contains("private material answer"))
        if case .selfCheck = baseline.interaction {
            return XCTFail("Protected assessment retrieval must have an objective key")
        }

        let personalPractice = try NFFallbackExerciseGenerator.generate(
            NFExerciseGenerationRequest(
                seed: 8,
                index: 0,
                lab: .retrieval,
                purpose: .documentPractice,
                sourceContext: sourceContext
            )
        )
        XCTAssertEqual(personalPractice.evidenceClass, .documentPractice)
        XCTAssertEqual(personalPractice.citations.map(\.documentID), ["document.private"])
        XCTAssertEqual(personalPractice.provenance.sourceDocumentIDs, ["document.private"])
        XCTAssertEqual(personalPractice.provenance.sourceChunkIDs, ["chunk.private"])
        XCTAssertTrue(personalPractice.provenance.isSourceGrounded)
        XCTAssertTrue(personalPractice.prompt.contains("What relationship do the notes define?"))
        XCTAssertNoThrow(try NFExerciseSchemaValidator.validate(personalPractice))
    }

    func testAssessmentFeedbackIsDelayedUntilExplicitReveal() throws {
        let exercise = try generate(lab: .logicDebugging, purpose: .baseline, seed: 9)
        let response = correctResponse(for: exercise.interaction)

        let hidden = NFExerciseScoringEngine.score(response, for: exercise)
        XCTAssertTrue(hidden.isCorrect)
        XCTAssertTrue(hidden.feedback.isDelayed)
        XCTAssertNil(hidden.expectedAnswerSummary)
        XCTAssertNil(hidden.feedback.decisiveStep)
        XCTAssertNil(hidden.feedback.strategy)

        let revealed = NFExerciseScoringEngine.score(
            response,
            for: exercise,
            revealDelayedFeedback: true
        )
        XCTAssertTrue(revealed.isCorrect)
        XCTAssertFalse(revealed.feedback.isDelayed)
        XCTAssertNotNil(revealed.expectedAnswerSummary)
        XCTAssertNotNil(revealed.feedback.decisiveStep)
    }

    func testNumericScoringEnforcesUnitsAndToleranceBoundaries() throws {
        let exercise = try firstExercise(lab: .quantitative) {
            guard case let .numeric(schema) = $0,
                  schema.answer.canonicalUnit == "%",
                  case .absolute = schema.answer.tolerance else { return false }
            return true
        }
        guard case let .numeric(schema) = exercise.interaction else {
            return XCTFail("Expected numeric interaction")
        }
        let expected = schema.answer.value
        guard case let .absolute(tolerance) = schema.answer.tolerance else {
            return XCTFail("Expected absolute tolerance")
        }

        let accepted = NFExerciseScoringEngine.score(
            .numeric(NFNumericSubmission(value: String(expected + tolerance), unit: "percent")),
            for: exercise
        )
        XCTAssertTrue(accepted.isCorrect)

        let outside = NFExerciseScoringEngine.score(
            .numeric(NFNumericSubmission(value: String(expected + tolerance + 0.001), unit: "%")),
            for: exercise
        )
        XCTAssertFalse(outside.isCorrect)
        XCTAssertEqual(outside.errorCode, "numeric_value")

        let missingUnit = NFExerciseScoringEngine.score(
            .numeric(NFNumericSubmission(value: String(expected), unit: nil)),
            for: exercise
        )
        XCTAssertFalse(missingUnit.isCorrect)
        XCTAssertEqual(missingUnit.errorCode, "unit_missing")

        let wrongUnit = NFExerciseScoringEngine.score(
            .numeric(NFNumericSubmission(value: String(expected), unit: "kg")),
            for: exercise
        )
        XCTAssertFalse(wrongUnit.isCorrect)
        XCTAssertEqual(wrongUnit.errorCode, "unit_mismatch")
    }

    func testPartialCreditIsDeterministicForCompositeResponses() throws {
        let multipleChoice = try firstExercise(lab: .transfer) {
            if case .multipleChoice = $0 { return true }
            return false
        }
        guard case let .multipleChoice(multipleSchema) = multipleChoice.interaction else {
            return XCTFail("Expected multiple choice")
        }
        let partialMultiple = NFExerciseScoringEngine.score(
            .multipleChoice(optionIDs: [multipleSchema.correctOptionIDs[0]]),
            for: multipleChoice
        )
        XCTAssertFalse(partialMultiple.isCorrect)
        XCTAssertGreaterThan(partialMultiple.credit, 0)
        XCTAssertLessThan(partialMultiple.credit, 1)

        let ordered = try firstExercise(lab: .transfer) {
            if case .orderedSteps = $0 { return true }
            return false
        }
        guard case let .orderedSteps(orderedSchema) = ordered.interaction else {
            return XCTFail("Expected ordered steps")
        }
        var reordered = orderedSchema.correctOrder
        reordered.swapAt(0, 1)
        let partialOrder = NFExerciseScoringEngine.score(
            .orderedSteps(stepIDs: reordered),
            for: ordered
        )
        XCTAssertFalse(partialOrder.isCorrect)
        XCTAssertGreaterThan(partialOrder.credit, 0)
        XCTAssertLessThan(partialOrder.credit, 1)

        let claimExercise = try firstExercise(lab: .scientificReasoning) {
            if case .claimEvidence = $0 { return true }
            return false
        }
        guard case let .claimEvidence(claimSchema) = claimExercise.interaction else {
            return XCTFail("Expected claim-evidence")
        }
        var structurallyCompleteButWrong = claimSchema.correctPairs
        let pairIndex = try XCTUnwrap(structurallyCompleteButWrong.indices.last)
        let replacement = try XCTUnwrap(claimSchema.evidence.first(where: {
            !structurallyCompleteButWrong[pairIndex].evidenceIDs.contains($0.id)
        }))
        var evidenceIDs = structurallyCompleteButWrong[pairIndex].evidenceIDs
        guard !evidenceIDs.isEmpty else {
            return XCTFail("Expected every authored claim to require at least one evidence relationship")
        }
        evidenceIDs[evidenceIDs.index(before: evidenceIDs.endIndex)] = replacement.id
        structurallyCompleteButWrong[pairIndex] = NFClaimEvidencePair(
            claimID: structurallyCompleteButWrong[pairIndex].claimID,
            evidenceIDs: evidenceIDs
        )
        let partialClaim = NFExerciseScoringEngine.score(
            .claimEvidence(NFClaimEvidenceSubmission(pairs: structurallyCompleteButWrong)),
            for: claimExercise
        )
        XCTAssertFalse(partialClaim.isCorrect)
        XCTAssertGreaterThan(partialClaim.credit, 0)
        XCTAssertLessThan(partialClaim.credit, 1)
    }

    func testSharedResponseValidatorRejectsZeroPartialDuplicateAndExcessiveMappings() throws {
        let exercise = try firstExercise(lab: .scientificReasoning) {
            if case .claimEvidence = $0 { return true }
            return false
        }
        guard case let .claimEvidence(schema) = exercise.interaction else {
            return XCTFail("Expected claim-evidence")
        }
        let emptyPairs = schema.claims.map {
            NFClaimEvidencePair(claimID: $0.id, evidenceIDs: [])
        }
        let zero = NFExerciseResponseValidator.validate(
            .claimEvidence(NFClaimEvidenceSubmission(pairs: emptyPairs)),
            for: exercise.interaction,
            localeIdentifier: exercise.localeIdentifier
        )
        XCTAssertEqual(zero.issue?.errorCode, "claim_evidence_relationships")

        var partialPairs = emptyPairs
        partialPairs[0] = schema.correctPairs[0]
        let partial = NFExerciseResponseValidator.validate(
            .claimEvidence(NFClaimEvidenceSubmission(pairs: partialPairs)),
            for: exercise.interaction,
            localeIdentifier: exercise.localeIdentifier
        )
        XCTAssertEqual(partial.issue?.errorCode, "claim_evidence_relationships")

        let exact = NFExerciseResponseValidator.validate(
            .claimEvidence(NFClaimEvidenceSubmission(pairs: schema.correctPairs)),
            for: exercise.interaction,
            localeIdentifier: exercise.localeIdentifier
        )
        XCTAssertTrue(exact.isValid)

        var excessivePairs = schema.correctPairs
        let first = excessivePairs[0]
        if let extra = schema.evidence.first(where: { !first.evidenceIDs.contains($0.id) }) {
            excessivePairs[0] = NFClaimEvidencePair(
                claimID: first.claimID,
                evidenceIDs: first.evidenceIDs + [extra.id]
            )
            let excessive = NFExerciseResponseValidator.validate(
                .claimEvidence(NFClaimEvidenceSubmission(pairs: excessivePairs)),
                for: exercise.interaction,
                localeIdentifier: exercise.localeIdentifier
            )
            XCTAssertEqual(excessive.issue?.errorCode, "claim_evidence_relationships")
        }

        let duplicate = NFExerciseResponseValidator.validate(
            .claimEvidence(NFClaimEvidenceSubmission(pairs: schema.correctPairs + [schema.correctPairs[0]])),
            for: exercise.interaction,
            localeIdentifier: exercise.localeIdentifier
        )
        XCTAssertEqual(duplicate.issue?.errorCode, "claim_evidence_unknown")
    }

    func testSharedResponseValidatorEnforcesEveryStructuredSchemaConstraint() {
        let options = [
            NFChoiceOption(id: "a", text: "A", accessibilityLabel: nil, distractorCode: nil),
            NFChoiceOption(id: "b", text: "B", accessibilityLabel: nil, distractorCode: nil),
            NFChoiceOption(id: "c", text: "C", accessibilityLabel: nil, distractorCode: nil)
        ]
        let multiple = NFExerciseInteraction.multipleChoice(NFMultipleChoiceResponseSchema(
            options: options,
            correctOptionIDs: ["a", "b"],
            minimumSelections: 2,
            maximumSelections: 2
        ))
        XCTAssertEqual(
            NFExerciseResponseValidator.validate(.multipleChoice(optionIDs: []), for: multiple).issue?.errorCode,
            "selection_bounds"
        )
        XCTAssertTrue(NFExerciseResponseValidator.validate(.multipleChoice(optionIDs: ["a", "c"]), for: multiple).isValid)
        XCTAssertEqual(
            NFExerciseResponseValidator.validate(.multipleChoice(optionIDs: ["a", "b", "c"]), for: multiple).issue?.errorCode,
            "selection_bounds"
        )

        let ordered = NFExerciseInteraction.orderedSteps(NFOrderedStepsResponseSchema(
            steps: [NFOrderedStep(id: "1", text: "First"), NFOrderedStep(id: "2", text: "Second")],
            correctOrder: ["1", "2"]
        ))
        XCTAssertEqual(
            NFExerciseResponseValidator.validate(.orderedSteps(stepIDs: ["1", "1"]), for: ordered).issue?.errorCode,
            "ordered_steps_membership"
        )
        XCTAssertTrue(NFExerciseResponseValidator.validate(.orderedSteps(stepIDs: ["2", "1"]), for: ordered).isValid)

        let shortText = NFExerciseInteraction.shortText(NFShortTextResponseSchema(
            expectedAnswer: "abc",
            scoringRule: .normalizedExact(acceptedAnswers: ["abc"]),
            maximumCharacters: 3
        ))
        XCTAssertEqual(NFExerciseResponseValidator.validate(.shortText(""), for: shortText).issue?.errorCode, "text_missing")
        XCTAssertTrue(NFExerciseResponseValidator.validate(.shortText("abc"), for: shortText).isValid)
        XCTAssertEqual(NFExerciseResponseValidator.validate(.shortText("abcd"), for: shortText).issue?.errorCode, "text_too_long")

        let logic = NFExerciseInteraction.logicState(NFLogicStateResponseSchema(
            initialState: ["x": "0"],
            expectedFinalState: ["x": "1"],
            acceptedEquivalentStates: [],
            ruleOptions: options,
            expectedViolatedRuleID: "a"
        ))
        XCTAssertEqual(
            NFExerciseResponseValidator.validate(
                .logicState(NFLogicStateSubmission(finalState: ["x": "1"], violatedRuleID: nil)),
                for: logic
            ).issue?.errorCode,
            "logic_rule_missing"
        )
        XCTAssertTrue(NFExerciseResponseValidator.validate(
            .logicState(NFLogicStateSubmission(finalState: ["x": "wrong"], violatedRuleID: "b")),
            for: logic
        ).isValid)
    }

    func testLocalizedNumericParsingIsExactAndNeverDropsAnAmbiguousComma() {
        let schema = NFNumericResponseSchema(
            answer: NFNumericAnswer(
                value: 1.25,
                tolerance: .absolute(0),
                canonicalUnit: nil,
                acceptedUnits: [],
                unitRequired: false,
                displayPrecision: 2
            ),
            placeholder: "1,25",
            permitsScientificNotation: true,
            permitsThousandsSeparators: true
        )
        let german = NFExerciseScoringEngine.validateNumeric(
            NFNumericSubmission(value: "1,25", unit: nil),
            schema: schema,
            localeIdentifier: "de_DE"
        )
        XCTAssertTrue(german.isCorrect)
        XCTAssertEqual(german.normalizedResponse, "5/4")

        let englishAmbiguous = NFExerciseScoringEngine.validateNumeric(
            NFNumericSubmission(value: "1,25", unit: nil),
            schema: schema,
            localeIdentifier: "en_US"
        )
        XCTAssertFalse(englishAmbiguous.isCorrect)
        XCTAssertEqual(englishAmbiguous.errorCode, "numeric_ambiguous")
        XCTAssertNotEqual(englishAmbiguous.normalizedResponse, "125")

        XCTAssertTrue(NFExerciseScoringEngine.validateNumeric(
            NFNumericSubmission(value: "5/4", unit: nil),
            schema: schema,
            localeIdentifier: "en_US"
        ).isCorrect)
        XCTAssertTrue(NFExerciseScoringEngine.validateNumeric(
            NFNumericSubmission(value: "1.25e0", unit: nil),
            schema: schema,
            localeIdentifier: "en_US"
        ).isCorrect)
    }

    func testClaimEvidenceExpectedSummaryUsesVisibleLabelsInsteadOfIdentifiers() throws {
        let exercise = try firstExercise(lab: .scientificReasoning) {
            if case .claimEvidence = $0 { return true }
            return false
        }
        guard case let .claimEvidence(schema) = exercise.interaction else {
            return XCTFail("Expected claim-evidence")
        }
        let result = NFExerciseScoringEngine.score(
            .claimEvidence(NFClaimEvidenceSubmission(pairs: schema.correctPairs)),
            for: exercise
        )
        let summary = try XCTUnwrap(result.expectedAnswerSummary)
        for claim in schema.claims { XCTAssertTrue(summary.contains(claim.text)) }
        for pair in schema.correctPairs {
            XCTAssertFalse(summary.contains("\(pair.claimID):"))
        }
    }

    func testLogicStateSeparatesStateAndInvariantErrors() throws {
        let exercise = try firstExercise(lab: .logicDebugging) {
            if case .logicState = $0 { return true }
            return false
        }
        guard case let .logicState(schema) = exercise.interaction else {
            return XCTFail("Expected logic-state interaction")
        }

        let wrongRule = schema.ruleOptions.first { $0.id != schema.expectedViolatedRuleID }?.id
        let result = NFExerciseScoringEngine.score(
            .logicState(
                NFLogicStateSubmission(
                    finalState: schema.expectedFinalState,
                    violatedRuleID: wrongRule
                )
            ),
            for: exercise
        )
        XCTAssertFalse(result.isCorrect)
        XCTAssertEqual(result.errorCode, "logic_rule")
        XCTAssertEqual(result.credit, 0.8, accuracy: 1e-12)
    }

    func testSelfCheckUsesExplicitLearnerRatingWithoutPretendingSemanticScoring() throws {
        let exercise = try firstExercise(lab: .retrieval) {
            if case .selfCheck = $0 { return true }
            return false
        }

        let partial = NFExerciseScoringEngine.score(
            .selfCheck(NFSelfCheckSubmission(rating: .partiallyMatched, reflection: "Missed one condition")),
            for: exercise
        )
        XCTAssertFalse(partial.isCorrect)
        XCTAssertEqual(partial.credit, 0.5, accuracy: 1e-12)
        XCTAssertEqual(partial.errorCode, "self_check_partial")

        let matched = NFExerciseScoringEngine.score(
            .selfCheck(NFSelfCheckSubmission(rating: .matched, reflection: "Matched the reference.")),
            for: exercise
        )
        XCTAssertTrue(matched.isCorrect)
        XCTAssertEqual(matched.credit, 1, accuracy: 1e-12)

        let missingRequiredComparison = NFExerciseScoringEngine.score(
            .selfCheck(NFSelfCheckSubmission(rating: .matched, reflection: nil)),
            for: exercise
        )
        XCTAssertFalse(missingRequiredComparison.isCorrect)
        XCTAssertEqual(missingRequiredComparison.errorCode, "self_check_reflection_missing")
    }

    func testWrongResponseTypeFailsClosed() throws {
        let exercise = try generate(lab: .spatial, purpose: .practice, seed: 1)
        let result = NFExerciseScoringEngine.score(.shortText("correct"), for: exercise)

        XCTAssertFalse(result.isCorrect)
        XCTAssertEqual(result.credit, 0)
        XCTAssertEqual(result.errorCode, "response_type_mismatch")
    }

    func testInvalidGenerationRequestIsRejected() {
        XCTAssertThrowsError(
            try NFFallbackExerciseGenerator.generate(
                NFExerciseGenerationRequest(seed: 1, index: -1, lab: .mentalMath, purpose: .practice)
            )
        ) { error in
            XCTAssertEqual(error as? NFExerciseGenerationError, .invalidIndex)
        }

        XCTAssertThrowsError(
            try NFFallbackExerciseGenerator.generate(
                NFExerciseGenerationRequest(
                    seed: 1,
                    index: 0,
                    lab: .mentalMath,
                    purpose: .practice,
                    targetDifficulty: 1.2
                )
            )
        ) { error in
            XCTAssertEqual(error as? NFExerciseGenerationError, .invalidTargetDifficulty)
        }
    }

    // MARK: - Helpers

    private func generate(
        lab: TrainingLab,
        purpose: NFExercisePurpose,
        seed: UInt64
    ) throws -> NFExercise {
        try NFFallbackExerciseGenerator.generate(
            NFExerciseGenerationRequest(seed: seed, index: 0, lab: lab, purpose: purpose)
        )
    }

    private func firstExercise(
        lab: TrainingLab,
        matching predicate: (NFExerciseInteraction) -> Bool
    ) throws -> NFExercise {
        for seed in 0..<256 {
            let exercise = try generate(lab: lab, purpose: .practice, seed: UInt64(seed))
            if predicate(exercise.interaction) { return exercise }
        }
        throw SearchError.notFound
    }

    private func correctResponse(for interaction: NFExerciseInteraction) -> NFExerciseResponse {
        switch interaction {
        case let .numeric(schema):
            .numeric(
                NFNumericSubmission(
                    value: String(schema.answer.value),
                    unit: schema.answer.canonicalUnit
                )
            )
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
            .logicState(
                NFLogicStateSubmission(
                    finalState: schema.expectedFinalState,
                    violatedRuleID: schema.expectedViolatedRuleID
                )
            )
        }
    }

    private func interactionKind(_ interaction: NFExerciseInteraction) -> String {
        switch interaction {
        case .numeric: "numeric"
        case .singleChoice: "singleChoice"
        case .multipleChoice: "multipleChoice"
        case .orderedSteps: "orderedSteps"
        case .shortText: "shortText"
        case .selfCheck: "selfCheck"
        case .claimEvidence: "claimEvidence"
        case .logicState: "logicState"
        }
    }

    private enum SearchError: Error {
        case notFound
    }
}

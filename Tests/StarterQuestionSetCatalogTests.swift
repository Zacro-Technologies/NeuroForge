import XCTest

@testable import NeuroForge

final class StarterQuestionSetCatalogTests: XCTestCase {
    private struct SemanticStarterDump: Codable {
        let index: Int
        let id: String
        let title: String
        let field: STEMField
        let lab: TrainingLab
        let topic: String
        let learningObjective: String
        let style: NFQuestionStyle
        let difficulty: Double
        let result: NFAuthoringResult
    }

    private var sourceStudyAuditChunks: [NFSourceChunk] {
        let documentID = UUID(uuidString: "7A9C35A5-2D81-46A4-BF5F-6A7E13AE90B8")!
        return [
            NFSourceChunk(
                id: "semantic-source.methods",
                documentID: documentID,
                documentVersion: 1,
                sourceName: "Methods and Results",
                locator: NFSourceLocator(page: 1, lineStart: 1, lineEnd: 3, section: "Methods"),
                text: "The trial found a 12 percent reduction in recovery time for the treated sample. The authors state that the association may not generalize beyond the sampled clinics. The methods section reports random assignment before outcome measurement.",
                contentHash: "semantic-source-methods-v1",
                ordinal: 0,
                language: "en",
                contentTypeTags: ["prose"]
            ),
            NFSourceChunk(
                id: "semantic-source.constraints",
                documentID: documentID,
                documentVersion: 1,
                sourceName: "Table and Constraints",
                locator: NFSourceLocator(page: 2, lineStart: 1, lineEnd: 3, section: "Evidence"),
                text: "The table compares mean growth under 20 and 30 degrees Celsius. The theorem applies only when every edge weight is nonnegative. The code visits an array index only while the index is less than count.",
                contentHash: "semantic-source-constraints-v1",
                ordinal: 1,
                language: "en",
                contentTypeTags: ["prose"]
            )
        ]
    }

    private func starterDefaultRequest(
        _ descriptor: NFStarterQuestionSetDescriptor,
        seed: UInt64
    ) -> NFAuthoringRequest {
        descriptor.makeAuthoringRequest(
            seed: seed,
            localeIdentifier: "en_US",
            sourceChunks: descriptor.id == "nf.starter.general.source-study"
                ? sourceStudyAuditChunks
                : [],
            aiMode: .disabled
        )
    }

    func testLearnFromMyMaterialRequiresAnImportedSource() {
        XCTAssertTrue(
            NFAIStudioStarterSourcePolicy.requiresImportedSource(
                starterSetID: "nf.starter.general.source-study"
            )
        )
        XCTAssertFalse(
            NFAIStudioStarterSourcePolicy.requiresImportedSource(
                starterSetID: "nf.starter.general.transfer"
            )
        )
        XCTAssertFalse(
            NFAIStudioStarterSourcePolicy.requiresImportedSource(starterSetID: nil)
        )
        XCTAssertEqual(
            NFAIStudioStarterSourcePolicy.supportedStyles(
                starterSetID: "nf.starter.general.source-study"
            ),
            [.shortAnswer]
        )
        XCTAssertEqual(
            NFAIStudioSourceAuthoringPolicy.offlineSupportedStyles,
            [.shortAnswer]
        )
        XCTAssertTrue(
            NFAIStudioDocumentAuthoringPolicy.allowsQuestionWriter(.privateCloudAllowed)
        )
        XCTAssertFalse(
            NFAIStudioDocumentAuthoringPolicy.allowsQuestionWriter(.onDeviceOnly)
        )
        XCTAssertFalse(
            NFAIStudioDocumentAuthoringPolicy.allowsQuestionWriter(.noAI)
        )
        XCTAssertTrue(
            NFAIStudioDocumentAuthoringPolicy.allowsOfflineQuestions(.privateCloudAllowed)
        )
        XCTAssertTrue(
            NFAIStudioDocumentAuthoringPolicy.allowsOfflineQuestions(.onDeviceOnly)
        )
        XCTAssertFalse(
            NFAIStudioDocumentAuthoringPolicy.allowsOfflineQuestions(.noAI)
        )
        let allowedDocumentID = UUID()
        let localDocumentID = UUID()
        XCTAssertEqual(
            NFAIStudioDocumentAuthoringPolicy.requestPolicies(
                for: [allowedDocumentID, localDocumentID],
                policiesByDocumentID: [
                    allowedDocumentID: .privateCloudAllowed,
                    localDocumentID: .onDeviceOnly
                ]
            ),
            [allowedDocumentID, localDocumentID]
                .sorted { $0.uuidString < $1.uuidString }
                .map { $0 == allowedDocumentID ? .privateCloudAllowed : .onDeviceOnly }
        )
        for lab in TrainingLab.allCases {
            let shortcutStyles = NFAIStudioSourceAuthoringPolicy.shortcutSupportedStyles(
                for: lab
            )
            XCTAssertEqual(
                shortcutStyles,
                NFAIStudioQuestionStylePolicy.suggestedStyles(for: lab)
                    .filter(NFQuestionWriterAuthoringPolicy.supports)
            )
            XCTAssertFalse(shortcutStyles.contains(.multipleChoice))
        }
        XCTAssertNil(
            NFAIStudioStarterSourcePolicy.supportedStyles(
                starterSetID: "nf.starter.general.transfer"
            )
        )
    }

    func testStudioStyleReconciliationPreservesACompatibleStarterDefault() throws {
        let starter = try XCTUnwrap(
            NFStarterQuestionSetCatalog.descriptor(id: "nf.starter.mathematics.calculus")
        )
        let available = NFAIStudioQuestionStylePolicy.suggestedStyles(for: starter.lab)

        XCTAssertTrue(available.contains(starter.defaultStyle))
        XCTAssertEqual(
            NFAIStudioQuestionStylePolicy.reconciledStyle(
                current: starter.defaultStyle,
                available: available
            ),
            starter.defaultStyle
        )
        XCTAssertEqual(
            NFAIStudioQuestionStylePolicy.reconciledStyle(
                current: .spatialTransformation,
                available: available
            ),
            available.first
        )
    }

    func testStarterCatalogPassesBreadthAndQualityAudit() {
        XCTAssertEqual(NFStarterQuestionSetCatalog.audit(), [])
        XCTAssertGreaterThanOrEqual(NFStarterQuestionSetCatalog.sets.count, 40)

        for field in STEMField.allCases {
            let fieldSets = NFStarterQuestionSetCatalog.sets(for: field)
            XCTAssertGreaterThanOrEqual(fieldSets.count, 5, field.rawValue)
            XCTAssertEqual(Set(fieldSets.map(\.topic)).count, fieldSets.count, field.rawValue)
            XCTAssertGreaterThanOrEqual(
                Set(fieldSets.flatMap(\.supportedStyles)).count,
                3,
                field.rawValue
            )
        }
    }

    func testRecommendationsAreDeterministicBalancedAndGoalAware() throws {
        let fields: Set<STEMField> = [.physics, .computing, .chemistry]
        let goals: Set<TrainingGoal> = [.programming, .experimentalDesign]
        let first = NFStarterQuestionSetCatalog.recommendations(
            fields: fields,
            goals: goals,
            seed: 0xCAFE_BABE,
            limit: 7
        )
        let second = NFStarterQuestionSetCatalog.recommendations(
            fields: fields,
            goals: goals,
            seed: 0xCAFE_BABE,
            limit: 7
        )

        XCTAssertEqual(first, second)
        XCTAssertEqual(first.count, 7)
        XCTAssertEqual(Set(first.map(\.id)).count, first.count)
        for field in fields {
            XCTAssertTrue(first.contains(where: { $0.field == field }), field.rawValue)
        }
        XCTAssertTrue(first.contains(where: { $0.lab == .logicDebugging }))
        XCTAssertTrue(first.contains(where: { $0.lab == .scientificReasoning }))

        let next = NFStarterQuestionSetCatalog.recommendations(
            fields: fields,
            goals: goals,
            seed: 0xCAFE_BABE,
            excluding: Set(first.map(\.id)),
            limit: 7
        )
        XCTAssertTrue(Set(first.map(\.id)).isDisjoint(with: Set(next.map(\.id))))
    }

    func testSearchFindsFieldNativeContentInsteadOfGenericKeywordFiller() throws {
        let graph = NFStarterQuestionSetCatalog.search("shortest path graph", field: .computing)
        XCTAssertEqual(try XCTUnwrap(graph.first).id, "nf.starter.computing.graphs")

        let stoichiometry = NFStarterQuestionSetCatalog.search("limiting reagent", field: .chemistry)
        XCTAssertEqual(
            try XCTUnwrap(stoichiometry.first).id,
            "nf.starter.chemistry.stoichiometry"
        )

        let leakage = NFStarterQuestionSetCatalog.search("test set leakage", field: .dataScience)
        XCTAssertEqual(try XCTUnwrap(leakage.first).id, "nf.starter.data-science.validation")
    }

    func testSearchMatchesLocalizedStarterDisplayCopy() throws {
        let japanese = Locale(identifier: "ja")
        let graph = NFStarterQuestionSetCatalog.search(
            "グラフアルゴリズム",
            field: .computing,
            locale: japanese
        )
        XCTAssertEqual(try XCTUnwrap(graph.first).id, "nf.starter.computing.graphs")

        let localizedSummary = try XCTUnwrap(
            NFStarterQuestionSetCatalog.descriptor(id: "nf.starter.computing.graphs")
        ).localizedSummary(locale: japanese)
        let summaryPhrase = localizedSummary
            .split(whereSeparator: { $0 == "、" || $0 == "。" })
            .first
            .map(String.init) ?? localizedSummary
        XCTAssertTrue(
            NFStarterQuestionSetCatalog.search(
                summaryPhrase,
                field: .computing,
                locale: japanese
            ).contains(where: { $0.id == "nf.starter.computing.graphs" })
        )
    }

    func testStarterDescriptorBuildsAStableBoundedAuthoringRequest() throws {
        let descriptor = try XCTUnwrap(
            NFStarterQuestionSetCatalog.descriptor(id: "nf.starter.mathematics.calculus")
        )
        let first = descriptor.makeAuthoringRequest(
            seed: 42,
            style: .proofOrDerivation,
            difficulty: 0.72,
            count: 9,
            localeIdentifier: "en_US",
            aiMode: .automatic
        )
        let second = descriptor.makeAuthoringRequest(
            seed: 42,
            style: .proofOrDerivation,
            difficulty: 0.72,
            count: 9,
            localeIdentifier: "en_US",
            aiMode: .automatic
        )

        XCTAssertEqual(first.seed, second.seed)
        XCTAssertEqual(first.field, .mathematics)
        XCTAssertEqual(first.lab, .logicDebugging)
        XCTAssertEqual(first.style, .proofOrDerivation)
        XCTAssertEqual(first.count, 9)
        XCTAssertEqual(first.difficulty, 0.72, accuracy: 0.000_001)
        XCTAssertEqual(first.capability, .contextualize)

        let unsupportedStyle = descriptor.makeAuthoringRequest(
            seed: 42,
            style: .experimentalDesign
        )
        XCTAssertEqual(unsupportedStyle.style, descriptor.defaultStyle)
    }

    func testEveryStarterSetHasJapaneseDisplayCopy() {
        let japanese = Locale(identifier: "ja")
        for descriptor in NFStarterQuestionSetCatalog.sets {
            let title = descriptor.localizedTitle(locale: japanese)
            let summary = descriptor.localizedSummary(locale: japanese)
            XCTAssertNotEqual(title, descriptor.title, descriptor.id)
            XCTAssertNotEqual(summary, descriptor.summary, descriptor.id)
            XCTAssertTrue(containsJapaneseScript(title), descriptor.id)
            XCTAssertTrue(containsJapaneseScript(summary), descriptor.id)
        }
    }

    func testSourceStudyStarterLocalizesVisibleObjectiveWithoutChangingSemanticRoutingKey() throws {
        let japanese = Locale(identifier: "ja")
        let descriptor = try XCTUnwrap(
            NFStarterQuestionSetCatalog.sets.first { $0.id == "nf.starter.general.source-study" }
        )

        XCTAssertTrue(containsJapaneseScript(descriptor.localizedLearningObjective(locale: japanese)))
        XCTAssertNotEqual(descriptor.localizedLearningObjective(locale: japanese), descriptor.learningObjective)

        let request = descriptor.makeAuthoringRequest(seed: 42, localeIdentifier: "ja")
        XCTAssertEqual(request.customTopic, descriptor.topic)
        XCTAssertEqual(request.learningObjective, descriptor.learningObjective)
    }

    func testFallbackGeneratorProvidesBroadNonRepeatingQuestionFamilies() throws {
        for field in STEMField.allCases {
            for lab in TrainingLab.allCases {
                let expectedFamilyCount = switch lab {
                case .mentalMath: 10
                case .spatial: 6
                case .quantitative: 8
                case .scientificReasoning, .logicDebugging, .retrieval: 9
                case .transfer: 7
                }
                var prompts = Set<String>()
                var templateIDs = Set<String>()
                for index in 0..<expectedFamilyCount {
                    let exercise = try NFFallbackExerciseGenerator.generate(
                        NFExerciseGenerationRequest(
                            seed: 0x5EED,
                            index: index,
                            lab: lab,
                            purpose: .practice,
                            sourceContext: NFExerciseSourceContext(
                                primaryField: field,
                                topic: "starter breadth audit"
                            ),
                            preferredAssessmentMechanicID: "\(lab.rawValue).fallback-variant-\(index)"
                        )
                    )
                    prompts.insert(exercise.prompt)
                    templateIDs.insert(exercise.templateID)
                    XCTAssertNoThrow(try NFExerciseSchemaValidator.validate(exercise))
                }

                XCTAssertGreaterThanOrEqual(
                    prompts.count,
                    max(5, expectedFamilyCount - 2),
                    "Too much prompt repetition for \(field.rawValue) / \(lab.rawValue)"
                )
                XCTAssertGreaterThanOrEqual(
                    templateIDs.count,
                    expectedFamilyCount,
                    "Too little mechanic breadth for \(field.rawValue) / \(lab.rawValue)"
                )
            }
        }
    }

    func testMentalMathFeedbackExplainsTheActualMechanic() throws {
        let expectedVocabulary = [
            "product", "compensation", "percentage", "exponent", "division",
            "percentage base", "operation", "magnitude", "audit trail", "factor structure"
        ]
        var explanations = Set<String>()

        for variant in 0..<10 {
            let exercise = try NFFallbackExerciseGenerator.generate(
                NFExerciseGenerationRequest(
                    seed: 0xF33D,
                    index: variant,
                    lab: .mentalMath,
                    purpose: .practice,
                    sourceContext: NFExerciseSourceContext(primaryField: .general),
                    preferredAssessmentMechanicID: "mentalMath.fallback-variant-\(variant)"
                )
            )
            let explanation = exercise.feedback.correctExplanation
            explanations.insert(explanation)
            XCTAssertTrue(
                explanation.localizedCaseInsensitiveContains(expectedVocabulary[variant]),
                "Variant \(variant) has irrelevant feedback: \(explanation)"
            )
        }

        XCTAssertEqual(explanations.count, 10)
        let toolChoice = try NFFallbackExerciseGenerator.generate(
            NFExerciseGenerationRequest(
                seed: 0xA11D,
                index: 0,
                lab: .mentalMath,
                purpose: .practice,
                sourceContext: NFExerciseSourceContext(primaryField: .engineering),
                preferredAssessmentMechanicID: "mentalMath.fallback-variant-8"
            )
        )
        XCTAssertTrue(toolChoice.feedback.correctExplanation.localizedCaseInsensitiveContains("reproducible"))
        XCTAssertTrue(toolChoice.feedback.correctExplanation.localizedCaseInsensitiveContains("audit trail"))
        XCTAssertFalse(toolChoice.feedback.correctExplanation.localizedCaseInsensitiveContains("changing scale or units"))
    }

    func testDeterministicAuthoringMatrixHasDistinctValidMechanics() async throws {
        func lab(for style: NFQuestionStyle) -> TrainingLab {
            switch style {
            case .multipleChoice, .shortAnswer: .retrieval
            case .numerical, .dataInterpretation: .quantitative
            case .proofOrDerivation, .debugging: .logicDebugging
            case .experimentalDesign: .scientificReasoning
            case .spatialTransformation: .spatial
            }
        }

        var auditedCells = 0
        for (fieldIndex, field) in STEMField.allCases.enumerated() {
            let descriptors = NFStarterQuestionSetCatalog.sets(for: field)
            for (styleIndex, style) in NFQuestionStyle.allCases.enumerated() {
                let compatible = descriptors.filter { $0.supportedStyles.contains(style) }
                let descriptor = compatible.isEmpty
                    ? descriptors[styleIndex % descriptors.count]
                    : compatible[styleIndex % compatible.count]
                let request = NFAuthoringRequest(
                    capability: .contextualize,
                    lab: lab(for: style),
                    field: field,
                    customTopic: descriptor.topic,
                    learningObjective: descriptor.learningObjective,
                    style: style,
                    difficulty: descriptor.defaultDifficulty,
                    count: 3,
                    localeIdentifier: "en_US",
                    seed: UInt64(70_000 + fieldIndex * 1_000 + styleIndex * 100),
                    aiMode: .disabled
                )
                let result = try await NFAuthoringEngine.shared.author(request)
                XCTAssertEqual(result.questions.count, 3, "\(field.rawValue) / \(style.rawValue)")
                XCTAssertEqual(
                    Set(result.questions.map(\.prompt)).count,
                    3,
                    "Exact prompt repetition in \(field.rawValue) / \(style.rawValue)"
                )
                XCTAssertEqual(
                    Set(result.questions.map(\.decisiveStep)).count,
                    3,
                    "Mechanic repetition in \(field.rawValue) / \(style.rawValue)"
                )
                for question in result.questions {
                    XCTAssertEqual(
                        NFUserFacingContentLinter.lint(question.authoritativeExercise),
                        [],
                        "\(field.rawValue) / \(style.rawValue): \(question.prompt)"
                    )
                    XCTAssertNoThrow(
                        try NFExerciseSchemaValidator.validate(question.authoritativeExercise),
                        "\(field.rawValue) / \(style.rawValue): \(question.prompt)"
                    )
                    XCTAssertTrue(
                        acceptsAuthoredResponseWithHonestAuthority(question.authoritativeExercise),
                        "\(field.rawValue) / \(style.rawValue): \(question.prompt)"
                    )
                    XCTAssertTrue(
                        displayMathIsBalanced(in: question.prompt),
                        "\(field.rawValue) / \(style.rawValue): \(question.prompt)"
                    )
                }
                auditedCells += 1
            }
        }
        XCTAssertEqual(auditedCells, STEMField.allCases.count * NFQuestionStyle.allCases.count)
    }

    func testEveryStarterDefaultRotatesAllSixReasoningSlots() async throws {
        for (index, descriptor) in NFStarterQuestionSetCatalog.sets.enumerated() {
            let request = starterDefaultRequest(
                descriptor,
                seed: UInt64(900_000 + index * 10_000)
            )
            let result = try await NFAuthoringEngine.shared.author(request)
            XCTAssertEqual(result.questions.count, descriptor.defaultItemCount, descriptor.id)
            XCTAssertEqual(Set(result.questions.map(\.prompt)).count, result.questions.count, descriptor.id)
            XCTAssertEqual(
                Set(result.questions.map(\.decisiveStep)).count,
                result.questions.count,
                descriptor.id
            )
            for question in result.questions {
                XCTAssertEqual(
                    NFUserFacingContentLinter.lint(question.authoritativeExercise),
                    [],
                    "\(descriptor.id): \(question.prompt)"
                )
                XCTAssertNoThrow(try NFExerciseSchemaValidator.validate(question.authoritativeExercise))
                XCTAssertTrue(acceptsAuthoredResponseWithHonestAuthority(question.authoritativeExercise), descriptor.id)
                XCTAssertTrue(displayMathIsBalanced(in: question.prompt), descriptor.id)
            }
        }
    }

    func testSourceStudyUsesDistinctCitedPropositionsAndSelfCheck() async throws {
        let descriptor = try XCTUnwrap(
            NFStarterQuestionSetCatalog.descriptor(id: "nf.starter.general.source-study")
        )
        XCTAssertEqual(descriptor.supportedStyles, [.shortAnswer])
        let single = NFSourceChunk(
            id: "single-proposition",
            documentID: UUID(uuidString: "7A9C35A5-2D81-46A4-BF5F-6A7E13AE90B8")!,
            documentVersion: 1,
            sourceName: "One claim",
            locator: NFSourceLocator(page: 1, lineStart: 1, lineEnd: 1, section: "Claim"),
            text: "The treatment may reduce recovery time only for adults in the sampled clinics.",
            contentHash: "single-proposition-v1",
            ordinal: 0,
            language: "en",
            contentTypeTags: ["prose"]
        )
        let oneChunkResult = try await NFAuthoringEngine.shared.author(
            descriptor.makeAuthoringRequest(
                seed: 2_100_000,
                localeIdentifier: "en_US",
                sourceChunks: [single],
                aiMode: .disabled
            )
        )
        XCTAssertEqual(oneChunkResult.questions.count, 1)
        XCTAssertEqual(Set(oneChunkResult.questions.map(\.prompt)).count, 1)
        XCTAssertEqual(Set(oneChunkResult.questions.map(\.decisiveStep)).count, 1)
        XCTAssertEqual(Set(oneChunkResult.questions.map(\.correctAnswer)), [single.text])
        for question in oneChunkResult.questions {
            XCTAssertEqual(question.citationChunkIDs, [single.id])
            if case let .selfCheck(schema) = question.authoritativeExercise.interaction {
                XCTAssertEqual(schema.referenceAnswer, single.text)
                XCTAssertFalse(schema.criteria.isEmpty)
                XCTAssertTrue(schema.asksForReflection)
            } else {
                XCTFail("Reconstructive source recall must permit faithful paraphrase via self-check")
            }
        }

        let twoChunkResult = try await NFAuthoringEngine.shared.author(
            descriptor.makeAuthoringRequest(
                seed: 2_200_000,
                localeIdentifier: "en_US",
                sourceChunks: sourceStudyAuditChunks,
                aiMode: .disabled
            )
        )
        XCTAssertEqual(Set(twoChunkResult.questions.map(\.correctAnswer)).count, 6)
        XCTAssertEqual(Set(twoChunkResult.questions.flatMap(\.citationChunkIDs)).count, 2)
        XCTAssertEqual(twoChunkResult.validationStatus.level, .exactSourceRestatement)
        XCTAssertEqual(twoChunkResult.validationStatus.sourceSupport, .exactAnswerText)
        for question in twoChunkResult.questions {
            let cited = try XCTUnwrap(
                sourceStudyAuditChunks.first { question.citationChunkIDs.contains($0.id) }
            )
            XCTAssertTrue(cited.text.contains(question.correctAnswer))
            XCTAssertTrue(acceptsAuthoredResponseWithHonestAuthority(question.authoritativeExercise))
        }
    }

    func testSourceStudyDeduplicatesOverlapsRejectsFragmentsAndInterleavesChunks() async throws {
        let descriptor = try XCTUnwrap(
            NFStarterQuestionSetCatalog.descriptor(id: "nf.starter.general.source-study")
        )
        let documentID = UUID(uuidString: "7D21A194-6618-4A3C-AC1B-AE6AA639EC53")!
        let dense = NFSourceChunk(
            id: "dense-prose",
            documentID: documentID,
            documentVersion: 1,
            sourceName: "Dense methods",
            locator: NFSourceLocator(page: 1, lineStart: 1, lineEnd: 8, section: "Methods"),
            text: "The control group was evaluated by Dr. Smith before treatment. The U.S. trial enrolled adults from two clinics. Random allocation occurred before baseline measurement. Assessors remained masked until every outcome was recorded. The protocol excluded participants younger than eighteen years. Temperature stayed between 20 and 22 degrees Celsius. Missing outcomes were reported separately by group. The analysis preserved the original assignment groups.",
            contentHash: "dense-prose-v1",
            ordinal: 0,
            characterStart: 0,
            characterEnd: 430,
            language: "en",
            contentTypeTags: ["prose"]
        )
        let overlapping = NFSourceChunk(
            id: "overlapping-prose",
            documentID: documentID,
            documentVersion: 1,
            sourceName: "Overlapping methods",
            locator: NFSourceLocator(page: 1, lineStart: 6, lineEnd: 10, section: "Methods"),
            text: "fragment that began inside an earlier sentence and cannot stand alone. The analysis preserved the original assignment groups. Follow-up ended after twelve complete weeks.",
            contentHash: "overlapping-prose-v1",
            ordinal: 1,
            characterStart: 360,
            characterEnd: 590,
            language: "en",
            contentTypeTags: ["prose"]
        )
        let laterPage = NFSourceChunk(
            id: "later-page-prose",
            documentID: documentID,
            documentVersion: 1,
            sourceName: "Later results",
            locator: NFSourceLocator(page: 2, lineStart: 1, lineEnd: 2, section: "Results"),
            text: "Every confidence interval was reported with its prespecified endpoint. No unplanned subgroup result was labeled confirmatory.",
            contentHash: "later-page-prose-v1",
            ordinal: 2,
            characterStart: 1_000,
            characterEnd: 1_150,
            language: "en",
            contentTypeTags: ["prose"]
        )
        let request = descriptor.makeAuthoringRequest(
            seed: 2_250_000,
            count: 6,
            localeIdentifier: "en_US",
            sourceChunks: [dense, overlapping, laterPage],
            aiMode: .disabled
        )
        let result = try await NFAuthoringEngine.shared.author(request)
        let answers = result.questions.map(\.correctAnswer)

        XCTAssertEqual(result.questions.count, 6)
        XCTAssertEqual(Set(answers).count, answers.count)
        XCTAssertTrue(Set(result.questions.flatMap(\.citationChunkIDs)).isSuperset(of: [dense.id, laterPage.id]))
        XCTAssertFalse(answers.contains { $0.hasSuffix("Dr.") })
        XCTAssertTrue(answers.contains("The U.S. trial enrolled adults from two clinics."))
        XCTAssertFalse(answers.contains("trial enrolled adults from two clinics."))
        XCTAssertFalse(answers.contains { $0.localizedCaseInsensitiveContains("fragment that began") })
        XCTAssertLessThanOrEqual(
            answers.filter { $0 == "The analysis preserved the original assignment groups." }.count,
            1
        )
        XCTAssertTrue(
            answers.contains("Every confidence interval was reported with its prespecified endpoint."),
            "A nonoverlapping later-page first proposition must remain eligible"
        )
        XCTAssertEqual(result.validationStatus.sourceSupport, .exactAnswerText)
    }

    func testSourceStudyRoundRobinPreventsOneDenseChunkFromStarvingAnother() async throws {
        let descriptor = try XCTUnwrap(
            NFStarterQuestionSetCatalog.descriptor(id: "nf.starter.general.source-study")
        )
        let firstDocument = UUID(uuidString: "D18DB9F0-A2E9-4E70-AD99-455930E5D136")!
        let secondDocument = UUID(uuidString: "55722386-738C-463A-82F3-4305F46D5FA9")!
        let dense = NFSourceChunk(
            id: "dense-six",
            documentID: firstDocument,
            documentVersion: 1,
            sourceName: "Long chapter",
            locator: NFSourceLocator(page: 1, lineStart: 1, lineEnd: 6, section: "Chapter"),
            text: "The first mechanism requires a closed boundary. The second mechanism conserves total signed flow. The third mechanism applies only above zero temperature. The fourth mechanism assumes independent measurement errors. The fifth mechanism fails at an empty input. The sixth mechanism preserves units through conversion.",
            contentHash: "dense-six-v1",
            ordinal: 0,
            language: "en",
            contentTypeTags: ["prose"]
        )
        let secondary = NFSourceChunk(
            id: "secondary-two",
            documentID: secondDocument,
            documentVersion: 1,
            sourceName: "Supplement",
            locator: NFSourceLocator(page: 2, lineStart: 1, lineEnd: 2, section: "Supplement"),
            text: "The supplement reports calibration before every trial. The sensitivity analysis changes one assumption at a time.",
            contentHash: "secondary-two-v1",
            ordinal: 1,
            language: "en",
            contentTypeTags: ["prose"]
        )
        let engine = NFAuthoringEngine(cacheCapacity: 4, cacheTTL: 600)
        let request = descriptor.makeAuthoringRequest(
            seed: 2_260_000,
            count: 6,
            localeIdentifier: "en_US",
            sourceChunks: [dense, secondary],
            aiMode: .disabled
        )
        let first = try await engine.author(request)
        let second = try await engine.author(request)

        XCTAssertEqual(first.questions.count, 6)
        XCTAssertEqual(Set(first.questions.flatMap(\.citationChunkIDs)), Set([dense.id, secondary.id]))
        XCTAssertEqual(Set(first.questions.map(\.correctAnswer)).count, 6)
        XCTAssertEqual(first.provenance.generatedAt, second.provenance.generatedAt)
        XCTAssertEqual(first.questions, second.questions)
        let cachedCount = await engine.cachedResultCount()
        XCTAssertEqual(cachedCount, 1)
    }

    func testSourceStudyFailsClosedForNonProseWithoutClaimAuthority() async throws {
        let descriptor = try XCTUnwrap(
            NFStarterQuestionSetCatalog.descriptor(id: "nf.starter.general.source-study")
        )
        let documentID = UUID(uuidString: "F864A829-A9C4-424F-8D62-42612F7DCDBA")!
        let unsupported = [
            NFSourceChunk(
                id: "code-only", documentID: documentID, documentVersion: 1,
                sourceName: "Code", locator: NFSourceLocator(page: 1, lineStart: 1, lineEnd: 2, section: "Code"),
                text: "for item in values { total += item }", contentHash: "code-only-v1", ordinal: 0,
                language: "swift", contentTypeTags: ["source-code", "code"]
            ),
            NFSourceChunk(
                id: "table-only", documentID: documentID, documentVersion: 1,
                sourceName: "Table", locator: NFSourceLocator(page: 2, lineStart: 1, lineEnd: 2, section: "Table"),
                text: "phase,value\nbaseline,12", contentHash: "table-only-v1", ordinal: 1,
                language: "csv", contentTypeTags: ["table", "csv"]
            ),
            NFSourceChunk(
                id: "formula-only", documentID: documentID, documentVersion: 1,
                sourceName: "Formula", locator: NFSourceLocator(page: 3, lineStart: 1, lineEnd: 1, section: "Formula"),
                text: "E = mc^2", contentHash: "formula-only-v1", ordinal: 2,
                language: "latex", contentTypeTags: ["equation", "math"]
            )
        ]

        let request = descriptor.makeAuthoringRequest(
            seed: 2_270_000,
            count: 6,
            localeIdentifier: "en_US",
            sourceChunks: unsupported,
            aiMode: .disabled
        )
        do {
            _ = try await NFAuthoringEngine.shared.author(request)
            XCTFail("Short-answer recall must not manufacture a cited prose answer from code/table/formula-only material")
        } catch let error as NFAIError {
            guard case let .invalidOutput(notes) = error else {
                return XCTFail("Expected invalidOutput, got \(error)")
            }
            XCTAssertTrue(notes.joined(separator: " ").localizedCaseInsensitiveContains("complete, distinct proposition"))
        }
    }

    func testSelectedSourceMultipleChoiceFailsClosedInsteadOfRepeatingGenericDistractors() async throws {
        let chunk = sourceStudyAuditChunks[0]
        let unsupported = NFQuestionStyle.allCases.filter { $0 != .shortAnswer }
        XCTAssertEqual(unsupported.count, 7)
        for (index, style) in unsupported.enumerated() {
            let lab: TrainingLab = switch style {
            case .multipleChoice, .shortAnswer: .retrieval
            case .numerical, .dataInterpretation: .quantitative
            case .proofOrDerivation, .debugging: .logicDebugging
            case .experimentalDesign: .scientificReasoning
            case .spatialTransformation: .spatial
            }
            let request = NFAuthoringRequest(
                capability: .sourceGroundedPractice,
                lab: lab,
                field: .general,
                customTopic: "prose statements from selected material",
                learningObjective: "preserve every cited qualifier",
                style: style,
                difficulty: 0.55,
                count: 6,
                localeIdentifier: "en_US",
                seed: UInt64(2_280_000 + index),
                sourceChunks: [chunk],
                aiMode: .disabled
            )
            do {
                _ = try await NFAuthoringEngine.shared.author(request)
                XCTFail("Selected-source \(style.rawValue) must fail closed")
            } catch let error as NFAIError {
                guard case let .invalidOutput(notes) = error else {
                    return XCTFail("Expected invalidOutput for \(style.rawValue), got \(error)")
                }
                XCTAssertTrue(
                    notes.joined(separator: " ").localizedCaseInsensitiveContains("prose short-answer recall"),
                    style.rawValue
                )
            }
        }
    }

    func testSourceStudyStripsMarkdownHeadingsAndPreservesAbbreviatedPropositions() async throws {
        let descriptor = try XCTUnwrap(
            NFStarterQuestionSetCatalog.descriptor(id: "nf.starter.general.source-study")
        )
        let documentID = UUID(uuidString: "8581DF6B-0C86-4920-9683-3FDF92320C90")!
        let first = "In Jan. 2025, each 5 mg. dose was infused for approx. 10 min. and observed for 30 sec. by Dr. Smith."
        let second = "The U.S. cohort was compared with the U.K. cohort by A. Chen, Ph.D. before publication."
        let third = "The comparison in Vol. 4, pp. 12–18 (cf. Fig. 2) contrasts site No. 3 on St. James Road vs. site No. 4."
        let fourth = "The investigator consulted “Dr. Smith” before reporting the final result."
        let fifth = "The protocol cites “e.g. repeated trials” as one illustrative design."
        let sixth = "The report states “The treatment may help.”"
        let seventh = "Another complete claim follows under the same protocol."
        let chunk = NFSourceChunk(
            id: "scholarly-abbreviations",
            documentID: documentID,
            documentVersion: 1,
            sourceName: "Methods.md",
            locator: NFSourceLocator(page: 4, lineStart: 1, lineEnd: 8, section: "Methods"),
            text: "# Methods\n\(first)\nResults\n=======\n\(second)\n## Cross-reference\n\(third)\n\(fourth)\n\(fifth)\n\(sixth) \(seventh)",
            contentHash: "scholarly-abbreviations-v1",
            ordinal: 0,
            characterStart: 0,
            language: "en",
            contentTypeTags: ["prose", "markdown"]
        )
        let result = try await NFAuthoringEngine.shared.author(
            descriptor.makeAuthoringRequest(
                seed: 2_285_000,
                count: 7,
                localeIdentifier: "en_US",
                sourceChunks: [chunk],
                aiMode: .disabled
            )
        )

        XCTAssertEqual(
            Set(result.questions.map(\.correctAnswer)),
            Set([first, second, third, fourth, fifth, sixth, seventh])
        )
        XCTAssertTrue(result.questions.allSatisfy { $0.citationChunkIDs == [chunk.id] })
        XCTAssertTrue(result.questions.allSatisfy { chunk.text.contains($0.correctAnswer) })
        XCTAssertFalse(result.questions.contains { $0.correctAnswer.contains("#") || $0.correctAnswer.contains("Results") })
    }

    func testStarterOpenResponsesUseSemanticOrSelfCheckScoring() async throws {
        let openStyles: Set<NFQuestionStyle> = [
            .shortAnswer, .proofOrDerivation, .debugging,
            .experimentalDesign, .dataInterpretation
        ]
        var auditedOpenResponses = 0
        for (index, descriptor) in NFStarterQuestionSetCatalog.sets.enumerated() {
            let result = try await NFAuthoringEngine.shared.author(
                starterDefaultRequest(descriptor, seed: UInt64(2_300_000 + index * 10_000))
            )
            for question in result.questions where openStyles.contains(question.style) {
                auditedOpenResponses += 1
                switch question.authoritativeExercise.interaction {
                case let .shortText(schema):
                    if case .constrainedConcepts = schema.scoringRule {
                        break
                    }
                    XCTFail("\(descriptor.id) uses brittle or unbounded short-text scoring")
                case let .selfCheck(schema):
                    XCTAssertFalse(schema.referenceAnswer.isEmpty, descriptor.id)
                    XCTAssertFalse(schema.criteria.isEmpty, descriptor.id)
                default:
                    XCTFail("\(descriptor.id) open response has the wrong interaction")
                }
            }
            for question in result.questions where question.style != .spatialTransformation {
                if case let .shortText(schema) = question.authoritativeExercise.interaction,
                   case .normalizedExact = schema.scoringRule {
                    XCTFail("\(descriptor.id) hard-fails natural paraphrases with normalizedExact")
                }
            }
        }
        XCTAssertGreaterThan(auditedOpenResponses, 150)
    }

    func testMixedStarterQuestionsExposeTruthfulSupportedStylesAndInteractions() async throws {
        let expectedMixedStyles: [String: NFQuestionStyle] = [
            "nf.starter.general.spatial-models": .shortAnswer,
            "nf.starter.mathematics.modeling": .shortAnswer,
            "nf.starter.physics.mechanics": .proofOrDerivation,
            "nf.starter.physics.electricity": .debugging,
            "nf.starter.physics.thermodynamics": .proofOrDerivation,
            "nf.starter.engineering.statics": .proofOrDerivation,
            "nf.starter.engineering.units": .debugging,
            "nf.starter.chemistry.stoichiometry": .debugging,
            "nf.starter.chemistry.solutions": .debugging
        ]
        for (index, descriptor) in NFStarterQuestionSetCatalog.sets.enumerated() {
            let result = try await NFAuthoringEngine.shared.author(
                starterDefaultRequest(descriptor, seed: UInt64(2_450_000 + index * 10_000))
            )
            for question in result.questions {
                XCTAssertTrue(
                    descriptor.supportedStyles.contains(question.style),
                    "\(descriptor.id) emitted unsupported style \(question.style.rawValue)"
                )
                if question.style == .numerical {
                    guard case .numeric = question.authoritativeExercise.interaction else {
                        return XCTFail("\(descriptor.id) labels a nonnumeric interaction as numerical")
                    }
                } else if question.style == .spatialTransformation {
                    guard case .shortText = question.authoritativeExercise.interaction else {
                        return XCTFail("\(descriptor.id) spatial item lost its coordinate-response contract")
                    }
                } else if question.style != .multipleChoice {
                    guard case .selfCheck = question.authoritativeExercise.interaction else {
                        return XCTFail("\(descriptor.id) reasoning item must use reveal-and-self-check")
                    }
                }
            }
            if let expected = expectedMixedStyles[descriptor.id] {
                XCTAssertTrue(
                    result.questions.contains { $0.style == expected },
                    "\(descriptor.id) never captures its promised reasoning in a truthful \(expected.rawValue) item"
                )
            }
        }
    }

    func testNumericalStarterToleranceMatchesAuthoredPrecision() async throws {
        let cases: [(id: String, correct: String, nearMiss: String)] = [
            ("nf.starter.engineering.units", "2750", "2748"),
            ("nf.starter.physics.thermodynamics", "25200", "25225"),
            ("nf.starter.physics.electricity", "540", "539.5")
        ]
        for (index, item) in cases.enumerated() {
            let descriptor = try XCTUnwrap(NFStarterQuestionSetCatalog.descriptor(id: item.id))
            let result = try await NFAuthoringEngine.shared.author(
                starterDefaultRequest(descriptor, seed: UInt64(2_500_000 + index * 10_000))
            )
            let question = try XCTUnwrap(result.questions.first { $0.correctAnswer == item.correct })
            guard case let .numeric(schema) = question.authoritativeExercise.interaction else {
                return XCTFail("Expected a numeric schema for \(item.id)")
            }
            XCTAssertEqual(schema.answer.displayPrecision, 0)
            XCTAssertEqual(schema.answer.tolerance, .absolute(1e-9))
            XCTAssertTrue(NFExerciseScoringEngine.score(
                .numeric(NFNumericSubmission(value: item.correct, unit: nil)),
                for: question.authoritativeExercise
            ).isCorrect)
            XCTAssertFalse(NFExerciseScoringEngine.score(
                .numeric(NFNumericSubmission(value: item.nearMiss, unit: nil)),
                for: question.authoritativeExercise
            ).isCorrect, "\(item.id) accepted a wrong exact-arithmetic near miss")
        }

        let probability = try XCTUnwrap(
            NFStarterQuestionSetCatalog.descriptor(id: "nf.starter.mathematics.probability")
        )
        let result = try await NFAuthoringEngine.shared.author(
            starterDefaultRequest(probability, seed: 2_540_000)
        )
        let rounded = try XCTUnwrap(result.questions.first {
            $0.prompt.localizedCaseInsensitiveContains("round to four decimal places")
        })
        guard case let .numeric(schema) = rounded.authoritativeExercise.interaction else {
            return XCTFail("Rounded probability must remain numeric")
        }
        XCTAssertEqual(schema.answer.displayPrecision, 4)
        XCTAssertEqual(schema.answer.tolerance, .absolute(0.00005))
        XCTAssertTrue(NFExerciseScoringEngine.score(
            .numeric(NFNumericSubmission(value: String(schema.answer.value + 0.00004), unit: nil)),
            for: rounded.authoritativeExercise
        ).isCorrect)
        XCTAssertFalse(NFExerciseScoringEngine.score(
            .numeric(NFNumericSubmission(value: String(schema.answer.value + 0.00006), unit: nil)),
            for: rounded.authoritativeExercise
        ).isCorrect)
    }

    func testNumericalPromptsDoNotRequireReasoningTheResponseCannotCapture() async throws {
        let unscoredCommands = [
            "explain", "diagnose", "draw a ", "draw an ", "draw the ", "formulate", "justify",
            "state why", "identify", "choose the", "check that"
        ]
        for (index, descriptor) in NFStarterQuestionSetCatalog.sets.enumerated()
            where descriptor.defaultStyle == .numerical {
            let result = try await NFAuthoringEngine.shared.author(
                starterDefaultRequest(descriptor, seed: UInt64(2_600_000 + index * 10_000))
            )
            for question in result.questions where question.style == .numerical {
                let prompt = question.prompt.lowercased()
                let violations = unscoredCommands.filter(prompt.contains)
                XCTAssertTrue(
                    violations.isEmpty,
                    "\(descriptor.id) numeric field cannot capture required reasoning verbs \(violations): \(question.prompt)"
                )
            }
        }
    }

    func testMultipleChoiceStarterKeysUseDistinctBalancedPatterns() async throws {
        let descriptors = NFStarterQuestionSetCatalog.sets.filter {
            $0.defaultStyle == .multipleChoice
        }
        XCTAssertEqual(descriptors.count, 4)
        var patterns = Set<[Int]>()
        var totals = Array(repeating: 0, count: 4)
        for (index, descriptor) in descriptors.enumerated() {
            let result = try await NFAuthoringEngine.shared.author(
                starterDefaultRequest(descriptor, seed: UInt64(2_700_000 + index * 10_000))
            )
            let pattern = try result.questions.map { question in
                try XCTUnwrap(question.choices.firstIndex(of: question.correctAnswer))
            }
            XCTAssertEqual(Set(pattern), Set(0..<4), descriptor.id)
            patterns.insert(pattern)
            for position in pattern { totals[position] += 1 }
        }
        XCTAssertEqual(patterns.count, descriptors.count)
        XCTAssertEqual(totals, [6, 6, 6, 6])
    }

    func testStarterObjectivesAreVisibleInConcreteQuestionFamilies() async throws {
        let requiredSignals: [String: [[String]]] = [
            "nf.starter.general.estimation": [["assumption"], ["bound", "range"], ["sanity", "implausible"], ["order of magnitude", "normalized exponent"]],
            "nf.starter.mathematics.calculus": [["limit definition"], ["product rule"], ["accumulation"], ["a′(2)=4", "a'(2)=4"], ["a(2)=∫₀²", "a(2)=8/3"], ["1 l/s³", "1 l/s^3", "\\mathrm{l}/\\mathrm{s}^3"], ["4 l/s"], ["8/3 l"], ["mean value theorem"], ["definite integral"]],
            "nf.starter.mathematics.linear-algebra": [["dimension error", "inner dimensions"], ["geometric", "invariant direction"]],
            "nf.starter.mathematics.discrete-proof": [["induction"], ["invariant"], ["contradiction"], ["parity"], ["pigeonhole"]],
            "nf.starter.mathematics.probability": [["natural frequencies", "10,000 people"], ["base rate"]],
            "nf.starter.mathematics.modeling": [["constraint"], ["unit"], ["boundary", "feasible"], ["sensitivity"]],
            "nf.starter.general.spatial-models": [["orientation"], ["adjacency"], ["preserv"], ["orthographic projection"], ["fold"]],
            "nf.starter.physics.mechanics": [["momentum conservation"], ["energy conservation"], ["limiting check", "t=0 limit"], ["dimension"], ["newton’s second law", "newton's second law"]],
            "nf.starter.physics.electricity": [["kirchhoff", "current conservation"], ["unit inconsistency", "dimensionally inconsistent"], ["potential change"]],
            "nf.starter.physics.waves": [["wave is"], ["graph"], ["phase"], ["invariant", "remain unchanged"]],
            "nf.starter.physics.thermodynamics": [["state function"], ["path quantities"], ["physical range", "boundary check"]],
            "nf.starter.engineering.statics": [["free-body"], ["equilibrium"], ["safety factor"], ["assumption"]],
            "nf.starter.engineering.controls": [["block diagram"], ["negative feedback"], ["positive feedback"], ["steady-state", "transient"]],
            "nf.starter.engineering.signals": [["sampling"], ["alias"], ["filter"], ["noise"]],
            "nf.starter.engineering.materials": [["stress"], ["fatigue"], ["discriminat"], ["fractograph"]],
            "nf.starter.engineering.units": [["dimensionally consistent"], ["tolerance"], ["worst-case"]],
            "nf.starter.chemistry.stoichiometry": [["limiting"], ["mole ratio"], ["inverted"], ["yield"]],
            "nf.starter.chemistry.kinetics": [["rate law"], ["mechanism"], ["controlled"]],
            "nf.starter.chemistry.equilibrium": [["0–14", "0-14"], ["dilute aqueous classroom"], ["kakb=kw"]],
            "nf.starter.chemistry.thermochemistry": [["exothermic"], ["spontaneity"], ["gibbs"]],
            "nf.starter.chemistry.solutions": [["conserv"], ["inverted"], ["dilution"], ["v₂=c₁v₁/c₂", "v2=c1v1/c2"], ["200 ml"]],
            "nf.starter.computing.graphs": [["cycle-handling invariant"], ["visited before recursing", "mark u visited before recursing"]],
            "nf.starter.life-sciences.genetics": [["linkage", "linked"], ["independent-assortment", "independent assortment"], ["no-selection assumption", "selection"]],
            "nf.starter.life-sciences.experiments": [["known-active positive control"], ["procedural control"], ["vehicle control"]],
            "nf.starter.life-sciences.epidemiology": [["true positives"], ["selection bias"], ["denominator"]],
            "nf.starter.life-sciences.ecology": [["environmental forcing"], ["competitor interaction", "drought-by-competitor"], ["factorial"], ["discrete logistic"], ["one-month lag"], ["carrying capacity"]],
            "nf.starter.data-science.inference": [["effect size", "practically important"], ["independence assumption"], ["paired method"]]
        ]
        for (index, descriptor) in NFStarterQuestionSetCatalog.sets.enumerated()
            where requiredSignals[descriptor.id] != nil {
            let result = try await NFAuthoringEngine.shared.author(
                starterDefaultRequest(descriptor, seed: UInt64(3_100_000 + index * 10_000))
            )
            let corpus = result.questions.map {
                [$0.prompt, $0.correctAnswer, $0.explanation, $0.decisiveStep]
                    .joined(separator: " ")
            }.joined(separator: " ").lowercased()
            for alternatives in requiredSignals[descriptor.id] ?? [] {
                XCTAssertTrue(
                    alternatives.contains(where: corpus.contains),
                    "\(descriptor.id) does not teach promised objective signal: \(alternatives)"
                )
            }
        }
    }

    func testReviewedCorrectnessPremisesRemainExplicit() async throws {
        let requiredSignals: [String: [[String]]] = [
            "nf.starter.general.causal-claims": [["assigned and delivered at classroom level"], ["independent assignment unit"]],
            "nf.starter.general.data-literacy": [["vertical axis spans 90 to 99"], ["3/9 of the display", "one third of the full plotted height"]],
            "nf.starter.mathematics.modeling": [["all four listed corners are feasible"], ["maximum profit of 320"]],
            "nf.starter.computing.algorithms": [["0 <= low <= high <= int.max"], ["nonnegative-index invariant"]],
            "nf.starter.computing.graphs": [["current smaller key pops before an older stale one"], ["candidate distance", "candidatedistance"], ["never finalize on discovery"]],
            "nf.starter.computing.concurrency": [["provider idempotency key"], ["durable outbox"], ["actor isolation alone"]],
            "nf.starter.chemistry.thermochemistry": [["−0.100 kj/k", "-0.100 kj/k"], ["−10 kj", "-10 kj"]],
            "nf.starter.chemistry.equilibrium": [["in water at the same temperature"], ["kakb=kw"]],
            "nf.starter.engineering.materials": [["stress amplitudes differ"], ["same stress", "s–n curves"]],
            "nf.starter.data-science.inference": [["corresponding two-sided 5% test"], ["same model and method"], ["all 20 null hypotheses are true"]],
            "nf.starter.data-science.classifiers": [["same labeled dataset"], ["actual-positive count is fixed"]],
            "nf.starter.physics.electricity": [["δv=+5 v", "Δv=+5 v"]],
            "nf.starter.physics.waves": [["smaller phase separation"], ["consecutive nodes"], ["no other nodes"]],
            "nf.starter.engineering.signals": [["ideal lower-bound rule"], ["practical reconstruction may require margin"]]
        ]
        for (index, descriptor) in NFStarterQuestionSetCatalog.sets.enumerated()
            where requiredSignals[descriptor.id] != nil {
            let result = try await NFAuthoringEngine.shared.author(
                starterDefaultRequest(descriptor, seed: UInt64(3_500_000 + index * 10_000))
            )
            let corpus = result.questions.map {
                [$0.prompt, $0.correctAnswer, $0.explanation, $0.decisiveStep]
                    .joined(separator: " ")
            }.joined(separator: " ").lowercased()
            for alternatives in requiredSignals[descriptor.id] ?? [] {
                XCTAssertTrue(
                    alternatives.contains(where: corpus.contains),
                    "\(descriptor.id) lost reviewed premise: \(alternatives)"
                )
            }
        }
    }

    func testSpatialCoordinateAnswersAcceptNaturalMinusAndSpacing() async throws {
        let descriptor = try XCTUnwrap(
            NFStarterQuestionSetCatalog.descriptor(id: "nf.starter.general.spatial-models")
        )
        let result = try await NFAuthoringEngine.shared.author(
            starterDefaultRequest(descriptor, seed: 3_800_000)
        )
        let question = try XCTUnwrap(result.questions.first {
            $0.correctAnswer.contains("−") && $0.correctAnswer.contains(",")
        })
        let natural = question.correctAnswer
            .replacingOccurrences(of: "−", with: "-")
            .replacingOccurrences(of: ",", with: ", ")
            .replacingOccurrences(of: "  ", with: " ")
        XCTAssertTrue(
            NFExerciseScoringEngine.score(
                .shortText(natural),
                for: question.authoritativeExercise
            ).isCorrect
        )
    }

    func testEveryStarterDefaultIsConcreteTopicNativeAndWorked() async throws {
        let bannedMetaPromptFragments = [
            "which option states the governing relation",
            "before applying the main method",
            "most informative boundary or falsification test",
            "which option identifies the characteristic diagnostic",
            "which interpretation of",
            "best demonstrates transfer of",
            "state the governing relation or invariant",
            "state one prerequisite that must be checked",
            "name a boundary or falsification test",
            "name the characteristic diagnostic",
            "give the strongest interpretation warranted",
            "state the mapping check required",
            "build a correctness argument for the governing invariant",
            "give a necessity argument for a key prerequisite",
            "construct a decisive boundary case or counterexample for",
            "solution reaches a plausible result after an invalid step",
            "derive the strongest conclusion warranted in",
            "justify transferring a"
        ]
        let bannedRubricAnswerFragments = [
            "use initialization, preservation, and termination",
            "show how removing the prerequisite permits",
            "use one admissible boundary case",
            "locate the first invariant, unit, direction, or scope violation",
            "separate the supported conclusion from its converse",
            "map objects, relations, constraints, and checks",
            "answer only the requested reasoning role",
            "state the topic-native"
        ]
        let bannedUndefinedPromptFragments = [
            "meet the stated criterion", "the main method", "topic-valid repair",
            "the topic’s characteristic", "in a new setting by renaming",
            "which option states", "requested reasoning role"
        ]

        var auditedQuestions = 0
        var violations: [String] = []
        var topicStrippedSignatures: [String: Set<String>] = [:]
        var exactPromptAnswerOwners: [String: String] = [:]
        for (index, descriptor) in NFStarterQuestionSetCatalog.sets.enumerated() {
            let request = starterDefaultRequest(
                descriptor,
                seed: UInt64(1_400_000 + index * 10_000)
            )
            let result = try await NFAuthoringEngine.shared.author(request)
            let nativeSignals = try XCTUnwrap(
                starterNativeSignals[descriptor.id],
                "Missing semantic contract for \(descriptor.id)"
            )
            var nativeQuestionCount = 0
            var reasoningExplanationCount = 0

            for (questionIndex, question) in result.questions.enumerated() {
                auditedQuestions += 1
                let label = "\(descriptor.id) Q\(questionIndex + 1)"
                let normalizedPrompt = normalizedSemanticText(question.prompt)
                let exactContract = normalizedPrompt + "|" + normalizedSemanticText(question.correctAnswer)
                if let owner = exactPromptAnswerOwners[exactContract], owner != descriptor.id {
                    violations.append("\(label): duplicates the exact prompt/answer contract from \(owner)")
                } else {
                    exactPromptAnswerOwners[exactContract] = descriptor.id
                }
                let promptWithoutCatalogTopic = normalizedPrompt.replacingOccurrences(
                    of: normalizedSemanticText(descriptor.topic),
                    with: " "
                )
                if bannedMetaPromptFragments.contains(where: normalizedPrompt.contains) {
                    violations.append("\(label): meta prompt: \(question.prompt)")
                }
                if bannedUndefinedPromptFragments.contains(where: normalizedPrompt.contains) {
                    violations.append("\(label): unresolved generic input: \(question.prompt)")
                }
                if normalizedPrompt.hasPrefix("debug the following "),
                   normalizedPrompt.contains(" case") {
                    violations.append("\(label): awkward generic debug framing: \(question.prompt)")
                }
                if nativeSignals.contains(where: promptWithoutCatalogTopic.contains) {
                    nativeQuestionCount += 1
                }
                let signature = promptWithoutCatalogTopic
                    .replacingOccurrences(of: "[0-9]+(?: [0-9]+)*", with: "#", options: .regularExpression)
                    .replacingOccurrences(of: " +", with: " ", options: .regularExpression)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                topicStrippedSignatures[signature, default: []].insert(descriptor.id)

                let normalizedAnswer = normalizedSemanticText(question.correctAnswer)
                if bannedRubricAnswerFragments.contains(where: normalizedAnswer.contains) {
                    violations.append("\(label): rubric prose used as answer: \(question.correctAnswer)")
                }
                if normalizedSemanticText(question.explanation) == normalizedAnswer {
                    violations.append("\(label): explanation merely repeats the answer")
                }
                if explanationAddsReasoning(question.explanation, beyond: question.correctAnswer) {
                    reasoningExplanationCount += 1
                }
                if descriptor.defaultStyle == .multipleChoice,
                   !question.choices.dropFirst().isEmpty,
                   !explainsWhyAConcreteDistractorFails(question) {
                    violations.append("\(label): MC explanation does not identify its nearest distractor")
                }
                if descriptor.defaultStyle == .multipleChoice {
                    let normalizedExplanation = normalizedSemanticText(question.explanation)
                    let nearestDistractorMentions = normalizedExplanation
                        .components(separatedBy: "nearest distractor")
                        .count - 1
                    if nearestDistractorMentions > 1 {
                        violations.append("\(label): MC explanation repeats its nearest-distractor contrast")
                    }
                    if normalizedExplanation.contains("it fails the specific relation or case stated in the prompt") {
                        violations.append("\(label): MC explanation appends generic distractor boilerplate")
                    }
                }
            }
            if nativeQuestionCount < 5 {
                violations.append("\(descriptor.id): only \(nativeQuestionCount)/6 prompts contain topic-native entities or operands")
            }
            if reasoningExplanationCount < 5 {
                violations.append("\(descriptor.id): only \(reasoningExplanationCount)/6 explanations add calculation or causal reasoning")
            }
            if Set(result.questions.map(\.decisiveStep)).count < 4 {
                violations.append("\(descriptor.id): fewer than four distinct objective mechanics")
            }
            if descriptor.id == "nf.starter.general.source-study" {
                for (questionIndex, question) in result.questions.enumerated() {
                    let cited = request.sourceChunks.first {
                        question.citationChunkIDs.contains($0.id)
                    }
                    if cited == nil || !(cited?.text.contains(question.correctAnswer) ?? false) {
                        violations.append(
                            "\(descriptor.id) Q\(questionIndex + 1): answer is not entailed verbatim by its cited source"
                        )
                    }
                    if case .selfCheck = question.authoritativeExercise.interaction {
                        // Source recall permits faithful paraphrase and punctuation differences.
                    } else {
                        violations.append(
                            "\(descriptor.id) Q\(questionIndex + 1): reconstructive recall is not self-check"
                        )
                    }
                }
            }
            if let expectedAnswers = numericStarterAnswerMultisets[descriptor.id] {
                XCTAssertEqual(
                    result.questions.filter { question in
                        if case .numeric = question.authoritativeExercise.interaction { return true }
                        return false
                    }.map(\.correctAnswer).sorted(),
                    expectedAnswers.sorted(),
                    "Independent numeric key audit failed for \(descriptor.id)"
                )
            }
        }

        for (signature, descriptorIDs) in topicStrippedSignatures where descriptorIDs.count > 2 {
            violations.append(
                "Topic-stripped prompt signature is shared by \(descriptorIDs.count) starters: \(signature)"
            )
        }

        XCTAssertEqual(auditedQuestions, 42 * 6)
        XCTAssertTrue(violations.isEmpty, violations.joined(separator: "\n\n"))
    }

    func testDumpEveryStarterDefaultForSemanticAudit() async throws {
        var dumps: [SemanticStarterDump] = []
        for (index, descriptor) in NFStarterQuestionSetCatalog.sets.enumerated() {
            let request = starterDefaultRequest(
                descriptor,
                seed: UInt64(900_000 + index * 10_000)
            )
            let result = try await NFAuthoringEngine.shared.author(request)
            dumps.append(SemanticStarterDump(
                index: index,
                id: descriptor.id,
                title: descriptor.title,
                field: descriptor.field,
                lab: descriptor.lab,
                topic: descriptor.topic,
                learningObjective: descriptor.learningObjective,
                style: descriptor.defaultStyle,
                difficulty: descriptor.defaultDifficulty,
                result: result
            ))
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(dumps)
        try data.write(
            to: URL(fileURLWithPath: "/tmp/nf-all-starters-semantic-audit.json"),
            options: .atomic
        )
        XCTAssertEqual(dumps.count, 42)
        XCTAssertEqual(dumps.flatMap(\.result.questions).count, 252)
    }

    private func displayMathIsBalanced(in value: String) -> Bool {
        value.components(separatedBy: "$$").count % 2 == 1
    }

    private var starterNativeSignals: [String: [String]] {
        [
            "nf.starter.general.causal-claims": ["treatment", "outcome", "random", "confound", "exposure", "control", "school", "volunteer", "classroom", "patient", "assessor", "group"],
            "nf.starter.general.estimation": ["estimate", "people", "minutes", "distance", "volume", "magnitude"],
            "nf.starter.general.logic": ["premise", "conclusion", "implies", "counterexample", " if ", " both ", "boolean", "policy", "siren", "integer"],
            "nf.starter.general.data-literacy": ["table", "chart", "sample", "interval", "mean", "rate"],
            "nf.starter.general.transfer": ["source", "target", "constraint", "recipe", "route", "schedule", "calibration", "formula", "inflow", "balance", "bridge", "scale", "server"],
            "nf.starter.general.source-study": ["source", "claim", "evidence", "qualifier", "passage", "result", "paper", "sentence", "excerpt", "chapter", "prose"],
            "nf.starter.general.spatial-models": ["coordinate", "point", "origin", "axis", "vector", "rotation"],
            "nf.starter.mathematics.calculus": ["f(", "f′", "derivative", "integral", "limit", "continuous", "differentiable", "\\lim"],
            "nf.starter.mathematics.linear-algebra": ["matrix", "vector", "rank", "determinant", "eigen", "null", "ax"],
            "nf.starter.mathematics.discrete-proof": ["integer", "induction", "parity", "divisible", "sum", " k ", " n "],
            "nf.starter.mathematics.probability": ["probability", "event", "outcome", "bayes", "conditional", "independent"],
            "nf.starter.mathematics.modeling": ["objective", "constraint", "feasible", "optimum", "cost", "decision variable", "profit", "model", "batch", "subscription", "resource", "quadratic"],
            "nf.starter.physics.mechanics": ["force", "mass", "velocity", "acceleration", "momentum", "energy", "speed", "work", "impulse", "cart", "object"],
            "nf.starter.physics.electricity": ["voltage", "current", "resistance", "charge", "circuit", "potential", "resistor", "power", "ampere", "coulomb"],
            "nf.starter.physics.waves": ["frequency", "period", "wavelength", "amplitude", "phase", "wave"],
            "nf.starter.physics.thermodynamics": ["heat", "work", "temperature", "pressure", "volume", "entropy"],
            "nf.starter.physics.measurement": ["measurement", "uncertainty", "instrument", "trial", "dimension", "error", "length", "result", "standard", "speed"],
            "nf.starter.computing.algorithms": ["algorithm", "input", "loop", "complexity", "comparison", "index", "runtime", "recursion", "midpoint", "while", "for ", "func"],
            "nf.starter.computing.graphs": ["graph", "vertex", "edge", "queue", "distance", "path"],
            "nf.starter.computing.boundaries": ["array", "index", "loop", "empty", "length", "element", "values", "count", "clamp", "collection"],
            "nf.starter.computing.concurrency": ["thread", "lock", "race", "transaction", "message", "shared", "task", "parallel", "retry", "producer", "consumer", "processed"],
            "nf.starter.computing.data-structures": ["tree", "heap", "hash", "queue", "node", "key", "scheduler", "undo", "frontier", "load factor", "stack"],
            "nf.starter.engineering.statics": ["load", "force", "moment", "support", "beam", "safety factor"],
            "nf.starter.engineering.controls": ["setpoint", "error", "gain", "feedback", "overshoot", "response"],
            "nf.starter.engineering.signals": ["sample", "frequency", "hertz", "signal", "filter", "alias"],
            "nf.starter.engineering.materials": ["stress", "strain", "load", "fatigue", "crack", "specimen"],
            "nf.starter.engineering.units": [" mm", " m ", "metre", "millimetre", "newton", "pascal", "tolerance", "dimension", "capacity", "error", "margin"],
            "nf.starter.chemistry.stoichiometry": ["mol", "reaction", "reagent", "yield", "coefficient", "product"],
            "nf.starter.chemistry.kinetics": ["rate", "concentration", "reaction", "order", "temperature", "activation"],
            "nf.starter.chemistry.equilibrium": ["equilibrium", " q ", " k ", "acid", "base", "ph", "buffer", "ha ", "exothermic", "reaction"],
            "nf.starter.chemistry.thermochemistry": ["enthalpy", "entropy", "gibbs", "joule", "temperature", "reaction", "deltah", "deltag", "heatcapacity", "hess"],
            "nf.starter.chemistry.solutions": ["molar", "solution", "solute", "volume", "dilution", "concentration"],
            "nf.starter.life-sciences.genetics": ["allele", "genotype", "offspring", "cross", "dominant", "recombinant", "mother", "parent", "son", "trait", "disease"],
            "nf.starter.life-sciences.experiments": ["treatment", "control", "replicate", "batch", "organism", "outcome", "cell", "sample", "mouse", "dose", "microscopist", "growth"],
            "nf.starter.life-sciences.cell-systems": ["receptor", "signal", "gene", "protein", "pathway", "feedback", "mrna", "dose", "ec50", "repressor", "ligand"],
            "nf.starter.life-sciences.epidemiology": ["risk", "disease", "test", "sensitivity", "specificity", "prevalence"],
            "nf.starter.life-sciences.ecology": ["population", "species", "site", "sample", "habitat", "abundance"],
            "nf.starter.data-science.classifiers": ["true positive", "false positive", "precision", "recall", "threshold", "class"],
            "nf.starter.data-science.inference": ["sample", "confidence interval", "null", "p-value", " p ", "alpha", "effect", "standard error", "mean", "hypotheses"],
            "nf.starter.data-science.validation": ["train", "test", "validation", "leakage", "feature", "split"],
            "nf.starter.data-science.regression": ["coefficient", "residual", "predictor", "outcome", "interaction", "confound", "model", "umbrella", "heteroskedastic", "slope"],
            "nf.starter.data-science.algorithms": ["pipeline", "row", "feature", "transform", "schema", "reproduc", "join", "timezone", "seed", "encoder", "parse"]
        ]
    }

    private var numericStarterAnswerMultisets: [String: [String]] {
        [
            "nf.starter.mathematics.probability": ["0.5", "0.3571", "0.12", "0.1538", "1.5", "70"],
            "nf.starter.mathematics.modeling": ["320", "40", "7", "6", "3"],
            "nf.starter.physics.mechanics": ["3", "4", "10", "4.899", "5"],
            "nf.starter.physics.electricity": ["3", "7", "4", "540", "15"],
            "nf.starter.physics.thermodynamics": ["25200", "2000", "320", "330", "2"],
            "nf.starter.engineering.statics": ["24", "3", "11", "20", "10"],
            "nf.starter.engineering.units": ["2750", "6000", "0.1", "1", "50"],
            "nf.starter.chemistry.stoichiometry": ["5", "6", "75", "2", "0.8"],
            "nf.starter.chemistry.solutions": ["0.25", "0.6", "10", "2", "0.6"]
        ]
    }

    private func normalizedSemanticText(_ value: String) -> String {
        " " + value
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US"))
            .lowercased()
            .replacingOccurrences(of: "[^a-z0-9′\\\\()]+", with: " ", options: .regularExpression)
            .replacingOccurrences(of: " +", with: " ", options: .regularExpression) + " "
    }

    private func explanationAddsReasoning(_ explanation: String, beyond answer: String) -> Bool {
        let normalized = normalizedSemanticText(explanation)
        guard normalized != normalizedSemanticText(answer) else { return false }
        if explanation.range(of: #"[=×÷/−+]|\b(because|therefore|so|gives|means|while|but|rather|indicat|requires|cannot|instead|before|after|when)\b"#, options: [.regularExpression, .caseInsensitive]) != nil {
            return true
        }
        return explanation.count >= 56
    }

    private func explainsWhyAConcreteDistractorFails(_ question: NFAuthoredQuestion) -> Bool {
        let normalized = normalizedSemanticText(question.explanation)
        let contrastTerms = [
            " distractor ", " nearest ", " tempting ", " instead ", " not ",
            " cannot ", " incorrectly ", " invalid ", " confus ", " revers ",
            " omit ", " violates ", " unsupported ", " rather "
        ]
        return contrastTerms.contains(where: normalized.contains)
    }

    private func acceptsAuthoredResponseWithHonestAuthority(_ exercise: NFExercise) -> Bool {
        let response: NFExerciseResponse = switch exercise.interaction {
        case let .numeric(schema):
            .numeric(NFNumericSubmission(
                value: schema.answer.authoritativeValue.canonicalString,
                unit: schema.answer.canonicalUnit
            ))
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
        let result = NFExerciseScoringEngine.score(response, for: exercise)
        if case .selfCheck = exercise.interaction {
            return result.outcome == .selfReported && result.objectiveCorrectness == nil && result.credit == 0
        }
        return result.isCorrect
    }


    private func containsJapaneseScript(_ value: String) -> Bool {
        value.unicodeScalars.contains { scalar in
            (0x3040...0x30FF).contains(scalar.value)
                || (0x3400...0x9FFF).contains(scalar.value)
        }
    }
}

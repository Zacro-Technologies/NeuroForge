import Foundation

/// Builds immutable exercise contracts. Exact evaluators and saved AI rubrics
/// retain their own scoring authority when a question is presented or restored.
enum NFAuthoredExerciseAuthority {
    static let generatorVersion = 12

    static func make(
        id: String,
        lab: TrainingLab,
        style: NFQuestionStyle,
        prompt: String,
        context: String,
        choices: [String],
        correctAnswer: String,
        acceptedAnswers: [String],
        explanation: String,
        hint: String,
        decisiveStep: String,
        difficulty: Double,
        citationChunkIDs: [String],
        evidenceClass: EvidenceClass,
        requiredTermGroups: [String] = [],
        minimumRequiredTermMatches: Int? = nil,
        rejectedAssertionGroups: [String] = [],
        numericDisplayPrecision: Int? = nil,
        numericAbsoluteTolerance: Double? = nil,
        contentTier: NFExerciseContentTier = .deterministicGenerated,
        modelIdentifier: String? = nil,
        promptVersion: Int? = nil,
        request: NFAuthoringRequest? = nil
    ) -> NFExercise {
        let boundedDifficulty = difficulty.isFinite ? min(1, max(0, difficulty)) : 0.5
        let matchingChunks = request?.sourceChunks.filter { citationChunkIDs.contains($0.id) } ?? []
        let sourceDocumentIDs: [String]
        let citations: [NFExerciseCitation]

        if !matchingChunks.isEmpty {
            sourceDocumentIDs = Array(Set(matchingChunks.map { $0.documentID.uuidString })).sorted()
            citations = matchingChunks.map { chunk in
                NFExerciseCitation(
                    id: "ai-studio.\(chunk.id)",
                    documentID: chunk.documentID.uuidString,
                    sourceChunkID: chunk.id,
                    title: chunk.sourceName,
                    locator: locator(for: chunk),
                    supportDescription: decisiveStep,
                    excerptDigest: chunk.contentHash
                )
            }
        } else if !citationChunkIDs.isEmpty {
            // Compatibility for manually constructed or pre-release fixtures
            // that did not retain the request beside the question. New
            // production authoring always supplies the exact request above.
            let compatibilityDocumentID = "legacy-personal-document"
            sourceDocumentIDs = [compatibilityDocumentID]
            citations = citationChunkIDs.map { chunkID in
                NFExerciseCitation(
                    id: "ai-studio.\(chunkID)",
                    documentID: compatibilityDocumentID,
                    sourceChunkID: chunkID,
                    title: context,
                    locator: .chunk(chunkID),
                    supportDescription: decisiveStep,
                    excerptDigest: nil
                )
            }
        } else {
            sourceDocumentIDs = []
            citations = []
        }

        let interaction = interaction(
            style: style,
            choices: choices,
            correctAnswer: correctAnswer,
            acceptedAnswers: acceptedAnswers,
            decisiveStep: decisiveStep,
            requiredTermGroups: requiredTermGroups,
            minimumRequiredTermMatches: minimumRequiredTermMatches,
            rejectedAssertionGroups: rejectedAssertionGroups,
            numericDisplayPrecision: numericDisplayPrecision,
            numericAbsoluteTolerance: numericAbsoluteTolerance,
            usesReferenceSelfCheck: modelIdentifier != nil
        )
        let digestSurface = ([
            id,
            lab.rawValue,
            style.rawValue,
            prompt,
            context,
            correctAnswer,
            decisiveStep,
            String(boundedDifficulty),
            numericDisplayPrecision.map { String($0) } ?? "derived-precision",
            numericAbsoluteTolerance.map { String($0) } ?? "derived-tolerance"
        ] + choices + acceptedAnswers + requiredTermGroups + rejectedAssertionGroups + citationChunkIDs)
            .joined(separator: "\u{241F}")
        let isSourceGrounded = !citations.isEmpty
        let locale = NFAppLocalization.locale(identifier: request?.localeIdentifier ?? "en")

        return NFExercise(
            id: id,
            schemaVersion: 1,
            generatorVersion: generatorVersion,
            templateID: "ai-studio.\(style.rawValue)",
            templateFamily: "ai.studio.document-practice.\(style.rawValue)",
            templateVersion: 1,
            seed: request?.seed ?? AdaptiveEngine.fnv1a64(digestSurface),
            lab: lab,
            purpose: .documentPractice,
            evidenceClass: evidenceClass,
            localeIdentifier: request?.localeIdentifier ?? "en",
            title: style.localizedTitle(locale: locale),
            prompt: prompt,
            contextText: context.isEmpty ? nil : context,
            instructions: decisiveStep,
            sourceContext: NFExerciseSourceContext(
                primaryField: request?.field ?? .general,
                topic: request?.customTopic,
                materialTitle: matchingChunks.first?.sourceName,
                sourceDocumentIDs: sourceDocumentIDs,
                sourceChunkIDs: citationChunkIDs,
                domainVocabulary: [],
                targetSkills: [lab.skillID],
                audienceDescription: request?.learningObjective,
                groundingFacts: []
            ),
            interaction: interaction,
            difficulty: NFExerciseDifficulty(
                overall: boundedDifficulty,
                reasoningSteps: reasoningSteps(for: style),
                abstraction: boundedDifficulty,
                representationShift: representationShift(for: style, difficulty: boundedDifficulty),
                priorKnowledge: boundedDifficulty,
                timePressure: 0
            ),
            skillWeights: [lab.skillID: 1],
            strategies: [
                NFExerciseStrategy(
                    id: "ai-studio.\(style.rawValue).strategy",
                    title: style.title,
                    summary: decisiveStep,
                    orderedSteps: [decisiveStep],
                    whenToUse: context.isEmpty ? prompt : context
                )
            ],
            representations: [.prose],
            citations: citations,
            provenance: NFExerciseProvenance(
                contentTier: contentTier,
                generatorID: modelIdentifier == nil
                    ? "neuroforge.ai-studio.authority"
                    : "neuroforge.ai-studio.validated-model-reference",
                generatorVersion: generatorVersion,
                modelIdentifier: modelIdentifier,
                promptVersion: promptVersion,
                sourceDocumentIDs: sourceDocumentIDs,
                sourceChunkIDs: citationChunkIDs,
                contentDigest: "fnv1a64:\(String(AdaptiveEngine.fnv1a64(digestSurface), radix: 16))",
                validatorVersion: NFExerciseSchemaValidator.validatorVersion,
                isSourceGrounded: isSourceGrounded
            ),
            rubric: NFExerciseRubric(
                criteria: [
                    NFExerciseRubricCriterion(
                        id: "authored-response",
                        description: decisiveStep,
                        weight: 1
                    )
                ],
                fullCreditThreshold: 1,
                permitsPartialCredit: false
            ),
            feedback: NFExerciseFeedbackSpec(
                timing: .immediate,
                correctTitle: NFAppLocalization.localized(
                    "Matched",
                    locale: locale,
                    comment: "Correct-answer feedback title for a typed AI Practice Studio exercise."
                ),
                correctExplanation: explanation,
                retryTitle: NFAppLocalization.localized(
                    "Review the reference answer",
                    locale: locale,
                    comment: "Neutral retry feedback title for an authored AI Practice Studio exercise."
                ),
                retryExplanation: explanation,
                decisiveStep: decisiveStep,
                hintLadder: hint.isEmpty ? [] : [hint],
                errorExplanations: [:]
            ),
            accessibility: NFExerciseAccessibility(
                promptAccessibilityLabel: prompt,
                visualAlternative: style == .spatialTransformation ? prompt : nil,
                requiresVisualSpatialProcessing: false,
                supportsVoiceOver: true,
                supportsKeyboardOnly: true,
                usesMotion: false
            ),
            assessmentProtected: false,
            expectedDurationSeconds: expectedDuration(for: style),
            timingEligible: false,
            responseEditPolicy: responseEditPolicy(for: style),
            tags: [
                "ai-practice-studio",
                modelIdentifier == nil ? "typed-authority" : "validated-model-practice",
                style.rawValue
            ]
        )
    }

    static func validatesBinding(_ question: NFAuthoredQuestion) -> Bool {
        let exercise = question.authoritativeExercise
        guard exercise.id == question.id,
              exercise.lab == question.lab,
              exercise.prompt == question.prompt,
              exercise.contextText == (question.context.isEmpty ? nil : question.context),
              question.evidenceClass == .documentPractice,
              exercise.evidenceClass == .documentPractice,
              exercise.purpose == .documentPractice,
              !exercise.assessmentProtected,
              (exercise.provenance.contentTier != .freeFormAI || exercise.aiRubric != nil),
              exercise.provenance.sourceChunkIDs == question.citationChunkIDs,
              choices(in: exercise.interaction) == question.choices,
              expectedAnswers(in: exercise.interaction).contains(question.correctAnswer) else {
            return false
        }
        if let rubric = exercise.aiRubric {
            guard question.style == .shortAnswer,
                  rubric.referenceAnswer == question.correctAnswer,
                  rubric.criteria == exercise.rubric.criteria else { return false }
        }
        return (try? NFExerciseSchemaValidator.validate(exercise)) != nil
    }

    static func responseFormat(for interaction: NFExerciseInteraction) -> String {
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

    private static func interaction(
        style: NFQuestionStyle,
        choices: [String],
        correctAnswer: String,
        acceptedAnswers: [String],
        decisiveStep: String,
        requiredTermGroups: [String],
        minimumRequiredTermMatches: Int?,
        rejectedAssertionGroups: [String],
        numericDisplayPrecision: Int?,
        numericAbsoluteTolerance: Double?,
        usesReferenceSelfCheck: Bool
    ) -> NFExerciseInteraction {
        if usesReferenceSelfCheck {
            return .selfCheck(NFSelfCheckResponseSchema(
                referenceAnswer: correctAnswer,
                criteria: [decisiveStep],
                asksForReflection: true
            ))
        }
        switch style {
        case .multipleChoice:
            let options = choices.enumerated().map { index, text in
                NFChoiceOption(
                    id: "choice-\(index)",
                    text: text,
                    accessibilityLabel: text,
                    distractorCode: text == correctAnswer ? nil : "authored_distractor"
                )
            }
            let correctIndex = choices.firstIndex(of: correctAnswer) ?? 0
            return .singleChoice(NFSingleChoiceResponseSchema(
                options: options,
                correctOptionID: "choice-\(correctIndex)"
            ))

        case .numerical:
            let normalized = correctAnswer.replacingOccurrences(of: ",", with: "")
            let answer = Double(normalized) ?? 0
            let derivedPrecision = numericDisplayPrecision ?? decimalPlaces(in: normalized)
            let derivedTolerance = numericAbsoluteTolerance
                ?? (derivedPrecision == 0 ? 1e-9 : 0.5 * pow(10, -Double(derivedPrecision)))
            return .numeric(NFNumericResponseSchema(
                answer: NFNumericAnswer(
                    value: answer,
                    tolerance: .absolute(derivedTolerance),
                    canonicalUnit: nil,
                    acceptedUnits: [],
                    unitRequired: false,
                    displayPrecision: derivedPrecision
                ),
                placeholder: "Enter a number, then submit",
                permitsScientificNotation: true,
                permitsThousandsSeparators: true
            ))

        case .spatialTransformation:
            let accepted = ([correctAnswer] + acceptedAnswers)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            return .shortText(NFShortTextResponseSchema(
                expectedAnswer: correctAnswer,
                scoringRule: .normalizedExact(acceptedAnswers: Array(NSOrderedSet(array: accepted))
                    .compactMap { $0 as? String }),
                maximumCharacters: 2_000
            ))

        case .shortAnswer, .proofOrDerivation, .debugging, .experimentalDesign, .dataInterpretation:
            let accepted = ([correctAnswer] + acceptedAnswers)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            let boundedGroups = requiredTermGroups
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            let boundedRejections = rejectedAssertionGroups
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            let scoringRule: NFShortTextScoringRule
            if boundedGroups.isEmpty {
                // Open reasoning rarely has one canonical sentence. Requiring
                // byte-normalized prose made ordinary correct paraphrases fail.
                // The learner now recalls an answer, reveals the deterministic
                // reference, and rates the comparison explicitly.
                return .selfCheck(NFSelfCheckResponseSchema(
                    referenceAnswer: correctAnswer,
                    criteria: [decisiveStep],
                    asksForReflection: true
                ))
            } else {
                scoringRule = .constrainedConcepts(
                    acceptedAnswers: Array(NSOrderedSet(array: accepted))
                        .compactMap { $0 as? String },
                    requiredTerms: boundedGroups,
                    minimumMatches: min(
                        boundedGroups.count,
                        max(1, minimumRequiredTermMatches ?? boundedGroups.count)
                    ),
                    rejectedAssertions: boundedRejections
                )
            }
            return .shortText(NFShortTextResponseSchema(
                expectedAnswer: correctAnswer,
                scoringRule: scoringRule,
                maximumCharacters: 2_000
            ))
        }
    }

    private static func decimalPlaces(in value: String) -> Int {
        let mantissa = value.lowercased().split(separator: "e", maxSplits: 1).first.map(String.init) ?? value
        guard let point = mantissa.firstIndex(of: ".") else { return 0 }
        return min(12, mantissa.distance(from: mantissa.index(after: point), to: mantissa.endIndex))
    }

    private static func choices(in interaction: NFExerciseInteraction) -> [String] {
        guard case let .singleChoice(schema) = interaction else { return [] }
        return schema.options.map(\.text)
    }

    private static func expectedAnswers(in interaction: NFExerciseInteraction) -> [String] {
        switch interaction {
        case let .numeric(schema):
            [schema.answer.authoritativeValue.canonicalString, String(schema.answer.value)]
        case let .singleChoice(schema):
            schema.options.filter { $0.id == schema.correctOptionID }.map(\.text)
        case let .multipleChoice(schema):
            schema.options.filter { schema.correctOptionIDs.contains($0.id) }.map(\.text)
        case let .orderedSteps(schema):
            [schema.correctOrder.joined(separator: ",")]
        case let .shortText(schema):
            [schema.expectedAnswer]
        case let .selfCheck(schema):
            [schema.referenceAnswer]
        case let .claimEvidence(schema):
            schema.correctPairs.map(\.claimID)
        case let .logicState(schema):
            [schema.expectedFinalState.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: ",")]
        }
    }

    private static func locator(for chunk: NFSourceChunk) -> NFExerciseCitationLocator {
        if let page = chunk.locator.page { return .page(page) }
        if let start = chunk.locator.lineStart, let end = chunk.locator.lineEnd {
            return .lines(start: start, end: end)
        }
        if let section = chunk.locator.section { return .section(section) }
        return .chunk(chunk.id)
    }

    private static func reasoningSteps(for style: NFQuestionStyle) -> Int {
        switch style {
        case .multipleChoice, .shortAnswer: 2
        case .numerical, .spatialTransformation: 3
        case .proofOrDerivation, .debugging, .experimentalDesign, .dataInterpretation: 4
        }
    }

    private static func representationShift(for style: NFQuestionStyle, difficulty: Double) -> Double {
        switch style {
        case .dataInterpretation, .spatialTransformation, .debugging:
            min(1, difficulty + 0.1)
        default:
            difficulty
        }
    }

    private static func expectedDuration(for style: NFQuestionStyle) -> Int {
        switch style {
        case .multipleChoice, .shortAnswer: 90
        case .numerical, .spatialTransformation: 150
        case .proofOrDerivation, .debugging, .experimentalDesign, .dataInterpretation: 240
        }
    }

    private static func responseEditPolicy(for style: NFQuestionStyle) -> NFResponseEditPolicy {
        switch style {
        case .proofOrDerivation, .debugging, .experimentalDesign, .dataInterpretation,
             .spatialTransformation:
            .editableBeforeCommit
        case .multipleChoice, .shortAnswer, .numerical:
            .lockedAfterSubmit
        }
    }
}

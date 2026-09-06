import Foundation

// MARK: - Exercise identity and evidence

/// The instructional or assessment role of an exercise. Baseline and periodic
/// holdout items share the protected assessment evidence stratum, while retaining
/// distinct purposes so selection and UI code can keep their pools separate.
enum NFExercisePurpose: String, Codable, CaseIterable, Sendable {
    case baseline
    case practice
    case nearTransfer
    case appliedTransfer
    case retention
    case assessmentHoldout
    case documentPractice

    var title: String {
        switch self {
        case .baseline: NFAppLocalization.localized("Starting skill check", locale: NFAppLocalization.preferredLocale, comment: "Session purpose shown above a starting assessment question.")
        case .practice: NFAppLocalization.localized("Practice", locale: NFAppLocalization.preferredLocale, comment: "Session purpose shown above a practice question.")
        case .nearTransfer: NFAppLocalization.localized("Near transfer", locale: NFAppLocalization.preferredLocale, comment: "Session purpose for applying a skill in a closely related setting.")
        case .appliedTransfer: NFAppLocalization.localized("Applied transfer", locale: NFAppLocalization.preferredLocale, comment: "Session purpose for applying a skill in a new setting.")
        case .retention: NFAppLocalization.localized("Retention review", locale: NFAppLocalization.preferredLocale, comment: "Session purpose for a spaced review question.")
        case .assessmentHoldout: NFAppLocalization.localized("Skill check", locale: NFAppLocalization.preferredLocale, comment: "Session purpose shown above a reassessment question.")
        case .documentPractice: NFAppLocalization.localized("Source practice", locale: NFAppLocalization.preferredLocale, comment: "Session purpose for a question made from imported material.")
        }
    }

    var evidenceClass: EvidenceClass {
        switch self {
        case .baseline, .assessmentHoldout: .assessmentHoldout
        case .practice: .practice
        case .nearTransfer: .nearTransfer
        case .appliedTransfer: .appliedTransfer
        case .retention: .retention
        case .documentPractice: .documentPractice
        }
    }

    var delaysFeedback: Bool {
        self == .baseline || self == .assessmentHoldout
    }

    var isProtectedAssessment: Bool {
        self == .baseline || self == .assessmentHoldout
    }
}

enum NFExerciseContentTier: String, Codable, CaseIterable, Sendable {
    case bundledAuthored
    case deterministicGenerated
    case aiContextualized
    case sourceGroundedAI
    case freeFormAI
}

enum NFExerciseFeedbackTiming: String, Codable, Sendable {
    case immediate
    case afterAssessmentBlock
}

// MARK: - Context, provenance, and citations

struct NFExerciseGroundingFact: Codable, Equatable, Sendable {
    let id: String
    let statement: String
    let expectedAnswer: String
    let acceptedAlternatives: [String]
    let citationIDs: [String]
}

/// A typed transfer contract shared by scheduling, exercise generation, and
/// telemetry. Keeping this structured prevents a selected mission from being
/// reduced to an unvalidated topic string before it reaches the generator.
enum NFTransferChallengeKind: String, Codable, CaseIterable, Sendable {
    case figureAndClaimAudit
    case numericalSimulationDebug
    case causalStructureComparison
    case abstractReconstruction
    case multiRepresentationTransform

    var title: String { localizedTitle(locale: NFAppLocalization.preferredLocale) }

    func localizedTitle(locale: Locale) -> String {
        switch self {
        case .figureAndClaimAudit: NFAppLocalization.localized("Figure and claim audit", locale: locale, comment: "Weekly transfer-challenge type.")
        case .numericalSimulationDebug: NFAppLocalization.localized("Numerical simulation debug", locale: locale, comment: "Weekly transfer-challenge type.")
        case .causalStructureComparison: NFAppLocalization.localized("Causal structure comparison", locale: locale, comment: "Weekly transfer-challenge type.")
        case .abstractReconstruction: NFAppLocalization.localized("Abstract reconstruction", locale: locale, comment: "Weekly transfer-challenge type.")
        case .multiRepresentationTransform: NFAppLocalization.localized("Multi-representation transform", locale: locale, comment: "Weekly transfer-challenge type.")
        }
    }
}

struct NFExerciseTransferBrief: Codable, Equatable, Sendable {
    let missionID: String
    let seed: UInt64
    let kind: NFTransferChallengeKind
    let labs: [TrainingLab]
    let skillIDs: [String]
    let requiredDimensions: [String]

    var labSummary: String {
        labs.map(\.shortTitle).joined(separator: " + ")
    }

    var dimensionSummary: String {
        NFTransferDimensionLocalization.list(requiredDimensions)
    }
}

/// Structured, policy-safe context supplied to authored, deterministic, or AI
/// generators. Source text itself is deliberately not stored here; only bounded
/// identifiers and reviewed facts may become scoring authority.
struct NFExerciseSourceContext: Codable, Equatable, Sendable {
    let primaryField: STEMField
    let secondaryFields: [STEMField]
    let topic: String?
    let materialTitle: String?
    let sourceDocumentIDs: [String]
    let sourceChunkIDs: [String]
    let domainVocabulary: [String]
    let targetSkills: [String]
    let audienceDescription: String?
    let transferOriginField: STEMField?
    let transferBrief: NFExerciseTransferBrief?
    let groundingFacts: [NFExerciseGroundingFact]

    init(
        primaryField: STEMField = .general,
        secondaryFields: [STEMField] = [],
        topic: String? = nil,
        materialTitle: String? = nil,
        sourceDocumentIDs: [String] = [],
        sourceChunkIDs: [String] = [],
        domainVocabulary: [String] = [],
        targetSkills: [String] = [],
        audienceDescription: String? = nil,
        transferOriginField: STEMField? = nil,
        transferBrief: NFExerciseTransferBrief? = nil,
        groundingFacts: [NFExerciseGroundingFact] = []
    ) {
        self.primaryField = primaryField
        self.secondaryFields = secondaryFields
        self.topic = topic
        self.materialTitle = materialTitle
        self.sourceDocumentIDs = sourceDocumentIDs
        self.sourceChunkIDs = sourceChunkIDs
        self.domainVocabulary = domainVocabulary
        self.targetSkills = targetSkills
        self.audienceDescription = audienceDescription
        self.transferOriginField = transferOriginField
        self.transferBrief = transferBrief
        self.groundingFacts = groundingFacts
    }
}

enum NFExerciseCitationLocator: Codable, Equatable, Sendable {
    case page(Int)
    case pages(start: Int, end: Int)
    case section(String)
    case lines(start: Int, end: Int)
    case chunk(String)
    case equation(String)
    case figure(String)
}

struct NFExerciseCitation: Codable, Equatable, Sendable, Identifiable {
    let id: String
    let documentID: String
    let sourceChunkID: String?
    let title: String
    let locator: NFExerciseCitationLocator
    let supportDescription: String
    let excerptDigest: String?
}

struct NFExerciseProvenance: Codable, Equatable, Sendable {
    let contentTier: NFExerciseContentTier
    let generatorID: String
    let generatorVersion: Int
    let modelIdentifier: String?
    let promptVersion: Int?
    let sourceDocumentIDs: [String]
    let sourceChunkIDs: [String]
    let contentDigest: String
    let validatorVersion: Int
    let isSourceGrounded: Bool
}

// MARK: - Difficulty, strategies, and representations

struct NFExerciseDifficulty: Codable, Equatable, Sendable {
    let overall: Double
    let reasoningSteps: Int
    let abstraction: Double
    let representationShift: Double
    let priorKnowledge: Double
    let timePressure: Double

    init(
        overall: Double,
        reasoningSteps: Int,
        abstraction: Double,
        representationShift: Double,
        priorKnowledge: Double,
        timePressure: Double
    ) {
        self.overall = overall
        self.reasoningSteps = reasoningSteps
        self.abstraction = abstraction
        self.representationShift = representationShift
        self.priorKnowledge = priorKnowledge
        self.timePressure = timePressure
    }
}

struct NFExerciseStrategy: Codable, Equatable, Sendable, Identifiable {
    let id: String
    let title: String
    let summary: String
    let orderedSteps: [String]
    let whenToUse: String
}

enum NFSpatialDimension: String, Codable, Sendable {
    case twoDimensional
    case threeDimensional
}

enum NFSpatialOperation: String, Codable, CaseIterable, Sendable {
    case rotate
    case reflect
    case translate
    case project
    case crossSection
    case coordinateTransform
    case diagramEquationMatch

    var title: String {
        switch self {
        case .rotate: NFAppLocalization.localized("Rotate", locale: NFAppLocalization.preferredLocale, comment: "Spatial-question operation.")
        case .reflect: NFAppLocalization.localized("Reflect shape", locale: NFAppLocalization.preferredLocale, comment: "Spatial-question operation for mirroring a geometric shape across a line or plane.")
        case .translate: NFAppLocalization.localized("Translate", locale: NFAppLocalization.preferredLocale, comment: "Spatial-question operation.")
        case .project: NFAppLocalization.localized("Project", locale: NFAppLocalization.preferredLocale, comment: "Spatial-question operation.")
        case .crossSection: NFAppLocalization.localized("Cross-section", locale: NFAppLocalization.preferredLocale, comment: "Spatial-question operation.")
        case .coordinateTransform: NFAppLocalization.localized("Coordinate transform", locale: NFAppLocalization.preferredLocale, comment: "Spatial-question operation.")
        case .diagramEquationMatch: NFAppLocalization.localized("Match diagram and equation", locale: NFAppLocalization.preferredLocale, comment: "Spatial-question operation.")
        }
    }
}

enum NFTransferDimensionLocalization {
    static func title(for identifier: String, locale: Locale = NFAppLocalization.preferredLocale) -> String {
        switch identifier {
        case "representation": NFAppLocalization.localized("representation", locale: locale, comment: "Transfer-mission dimension varied between questions.")
        case "response_type": NFAppLocalization.localized("answer format", locale: locale, comment: "Transfer-mission dimension varied between questions.")
        case "field": NFAppLocalization.localized("subject", locale: locale, comment: "Transfer-mission dimension varied between questions.")
        case "surface_context": NFAppLocalization.localized("scenario", locale: locale, comment: "Transfer-mission dimension varied between questions.")
        case "interacting_variables": NFAppLocalization.localized("interacting variables", locale: locale, comment: "Transfer-mission dimension varied between questions.")
        case "delay": NFAppLocalization.localized("time delay", locale: locale, comment: "Transfer-mission dimension varied between questions.")
        case "stimulus_category": NFAppLocalization.localized("question type", locale: locale, comment: "Transfer-mission dimension varied between questions.")
        default: NFAppLocalization.localized("another feature", locale: locale, comment: "Fallback transfer-mission dimension when an older saved identifier is no longer recognized.")
        }
    }

    static func list(_ identifiers: [String], locale: Locale = NFAppLocalization.preferredLocale) -> String {
        identifiers.map { title(for: $0, locale: locale) }.joined(separator: ", ")
    }
}

struct NFSpatialPoint: Codable, Equatable, Sendable {
    let label: String
    let x: Double
    let y: Double
    let z: Double?
}

/// Display-only resource limits also gate newly scored stimuli. Original
/// snapshots remain intact when a history diagram cannot be represented.
enum NFSpatialRenderingSafety {
    static let maximumPointCount = 128
    static let maximumCoordinateMagnitude = Double(Float.greatestFiniteMagnitude) / 4

    static func permits(_ metadata: NFSpatialRepresentationMetadata) -> Bool {
        let p = metadata.difficultyParameters
        guard metadata.points.count <= maximumPointCount,
              p.rotationMagnitudeDegrees.isFinite, (0...360).contains(p.rotationMagnitudeDegrees),
              p.objectComplexity.isFinite, (0...1).contains(p.objectComplexity),
              p.distractorSimilarity.isFinite, (0...1).contains(p.distractorSimilarity) else { return false }
        return metadata.points.allSatisfy { point in
            [point.x, point.y, point.z ?? 0].allSatisfy {
                $0.isFinite && abs($0) <= maximumCoordinateMagnitude
            }
        }
    }

    static func coordinateLabel(_ value: Double, locale: Locale) -> String {
        guard value.isFinite else { return "—" }
        if abs(value) >= 1_000_000_000_000 {
            return value.formatted(.number.locale(locale).notation(.scientific).precision(.significantDigits(1...12)))
        }
        return value.formatted(.number.locale(locale).precision(.fractionLength(0...1)))
    }
}

enum NFSpatialResponseMode: String, Codable, CaseIterable, Sendable {
    case singleChoice
    case diagramMatch
    case coordinateEntry
    case numericEntry
    case multipleChoice
    case directManipulation
}

/// The independently tunable spatial-demand vector recorded with every
/// spatial stimulus. Values expressed as proportions are bounded to `0...1`
/// by the exercise schema validator; rotation is an absolute magnitude in
/// degrees so direction remains part of the operation rather than difficulty.
struct NFSpatialDifficultyParameters: Codable, Equatable, Sendable {
    let stimulusCategory: String
    let viewpoint: String
    let rotationMagnitudeDegrees: Double
    let objectComplexity: Double
    let distractorSimilarity: Double
    let responseMode: NFSpatialResponseMode

    init(
        stimulusCategory: String,
        viewpoint: String,
        rotationMagnitudeDegrees: Double,
        objectComplexity: Double,
        distractorSimilarity: Double,
        responseMode: NFSpatialResponseMode
    ) {
        self.stimulusCategory = stimulusCategory
        self.viewpoint = viewpoint
        self.rotationMagnitudeDegrees = rotationMagnitudeDegrees
        self.objectComplexity = objectComplexity
        self.distractorSimilarity = distractorSimilarity
        self.responseMode = responseMode
    }

    private enum CodingKeys: String, CodingKey {
        case stimulusCategory
        case viewpoint
        case rotationMagnitudeDegrees
        case objectComplexity
        case distractorSimilarity
        case responseMode
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        stimulusCategory = try container.decodeIfPresent(String.self, forKey: .stimulusCategory)
            ?? "legacy-unspecified"
        viewpoint = try container.decode(String.self, forKey: .viewpoint)
        rotationMagnitudeDegrees = try container.decode(Double.self, forKey: .rotationMagnitudeDegrees)
        objectComplexity = try container.decode(Double.self, forKey: .objectComplexity)
        distractorSimilarity = try container.decode(Double.self, forKey: .distractorSimilarity)
        responseMode = try container.decode(NFSpatialResponseMode.self, forKey: .responseMode)
    }

    static func legacy(viewpoint: String) -> NFSpatialDifficultyParameters {
        NFSpatialDifficultyParameters(
            stimulusCategory: "legacy-unspecified",
            viewpoint: viewpoint,
            rotationMagnitudeDegrees: 0,
            objectComplexity: 0.5,
            distractorSimilarity: 0.5,
            responseMode: .singleChoice
        )
    }
}

struct NFSpatialRepresentationMetadata: Codable, Equatable, Sendable {
    let stimulusCategory: String
    let dimension: NFSpatialDimension
    let objectDescription: String
    let viewpoint: String
    let operations: [NFSpatialOperation]
    let points: [NFSpatialPoint]
    let axisLabels: [String]
    let accessibilityDescription: String
    let assetName: String?
    let protectedGrammarID: String?
    let difficultyParameters: NFSpatialDifficultyParameters

    init(
        stimulusCategory: String,
        dimension: NFSpatialDimension,
        objectDescription: String,
        viewpoint: String,
        operations: [NFSpatialOperation],
        points: [NFSpatialPoint],
        axisLabels: [String],
        accessibilityDescription: String,
        assetName: String?,
        protectedGrammarID: String?,
        difficultyParameters: NFSpatialDifficultyParameters
    ) {
        self.stimulusCategory = stimulusCategory
        self.dimension = dimension
        self.objectDescription = objectDescription
        self.viewpoint = viewpoint
        self.operations = operations
        self.points = points
        self.axisLabels = axisLabels
        self.accessibilityDescription = accessibilityDescription
        self.assetName = assetName
        self.protectedGrammarID = protectedGrammarID
        self.difficultyParameters = difficultyParameters
    }

    private enum CodingKeys: String, CodingKey {
        case stimulusCategory
        case dimension
        case objectDescription
        case viewpoint
        case operations
        case points
        case axisLabels
        case accessibilityDescription
        case assetName
        case protectedGrammarID
        case difficultyParameters
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        stimulusCategory = try container.decode(String.self, forKey: .stimulusCategory)
        dimension = try container.decode(NFSpatialDimension.self, forKey: .dimension)
        objectDescription = try container.decode(String.self, forKey: .objectDescription)
        viewpoint = try container.decode(String.self, forKey: .viewpoint)
        operations = try container.decode([NFSpatialOperation].self, forKey: .operations)
        points = try container.decode([NFSpatialPoint].self, forKey: .points)
        axisLabels = try container.decode([String].self, forKey: .axisLabels)
        accessibilityDescription = try container.decode(String.self, forKey: .accessibilityDescription)
        assetName = try container.decodeIfPresent(String.self, forKey: .assetName)
        protectedGrammarID = try container.decodeIfPresent(String.self, forKey: .protectedGrammarID)
        difficultyParameters = try container.decodeIfPresent(
            NFSpatialDifficultyParameters.self,
            forKey: .difficultyParameters
        ) ?? .legacy(viewpoint: viewpoint)
    }
}

struct NFLogicTransition: Codable, Equatable, Sendable, Identifiable {
    let id: String
    let condition: String
    let mutation: String
}

struct NFLogicRepresentationMetadata: Codable, Equatable, Sendable {
    let variables: [String: String]
    let transitions: [NFLogicTransition]
    let invariants: [String: String]
    let traceLanguage: String
    var traceContract: NFCodeTraceContract? = nil
}

enum NFExerciseRepresentation: Codable, Equatable, Sendable {
    case spatial(NFSpatialRepresentationMetadata)
    case logicState(NFLogicRepresentationMetadata)
    case equation(latex: String, spokenDescription: String)
    case table(headers: [String], rows: [[String]], accessibilitySummary: String)
    case code(language: String, source: String, accessibilitySummary: String)
    case prose
}

struct NFExerciseAccessibility: Codable, Equatable, Sendable {
    let promptAccessibilityLabel: String
    let visualAlternative: String?
    let requiresVisualSpatialProcessing: Bool
    let supportsVoiceOver: Bool
    let supportsKeyboardOnly: Bool
    let usesMotion: Bool
}

// MARK: - Response schemas

enum NFNumericTolerance: Codable, Equatable, Sendable {
    case absolute(Double)
    case relative(Double)
    case absoluteOrRelative(absolute: Double, relative: Double)
}

struct NFNumericAnswer: Codable, Equatable, Sendable {
    let value: Double
    let tolerance: NFNumericTolerance
    let canonicalUnit: String?
    let acceptedUnits: [String]
    let unitRequired: Bool
    let displayPrecision: Int
    let authoritativeValue: NFExactNumber
    let authoritativeTolerance: NFExactNumericTolerance

    init(
        value: Double,
        tolerance: NFNumericTolerance,
        canonicalUnit: String?,
        acceptedUnits: [String],
        unitRequired: Bool,
        displayPrecision: Int,
        authoritativeValue: NFExactNumber? = nil,
        authoritativeTolerance: NFExactNumericTolerance? = nil
    ) {
        self.value = value
        self.tolerance = tolerance
        self.canonicalUnit = canonicalUnit
        self.acceptedUnits = acceptedUnits
        self.unitRequired = unitRequired
        self.displayPrecision = displayPrecision
        self.authoritativeValue = authoritativeValue
            ?? NFExactNumber(legacyDouble: value)
            ?? (try! NFExactNumber(numerator: 0))
        self.authoritativeTolerance = authoritativeTolerance
            ?? NFExactNumericTolerance(legacy: tolerance)
            ?? .absolute(try! NFExactNumber(numerator: 0))
    }

    init(
        authoritativeValue: NFExactNumber,
        authoritativeTolerance: NFExactNumericTolerance,
        legacyTolerance: NFNumericTolerance,
        canonicalUnit: String?,
        acceptedUnits: [String] = [],
        unitRequired: Bool? = nil,
        displayPrecision: Int = 2
    ) {
        value = authoritativeValue.doubleValue
        tolerance = legacyTolerance
        self.canonicalUnit = canonicalUnit
        self.acceptedUnits = acceptedUnits
        self.unitRequired = unitRequired ?? (canonicalUnit != nil)
        self.displayPrecision = displayPrecision
        self.authoritativeValue = authoritativeValue
        self.authoritativeTolerance = authoritativeTolerance
    }

    private enum CodingKeys: String, CodingKey {
        case value
        case tolerance
        case canonicalUnit
        case acceptedUnits
        case unitRequired
        case displayPrecision
        case authoritativeValue
        case authoritativeTolerance
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        value = try container.decode(Double.self, forKey: .value)
        tolerance = try container.decode(NFNumericTolerance.self, forKey: .tolerance)
        canonicalUnit = try container.decodeIfPresent(String.self, forKey: .canonicalUnit)
        acceptedUnits = try container.decode([String].self, forKey: .acceptedUnits)
        unitRequired = try container.decode(Bool.self, forKey: .unitRequired)
        displayPrecision = try container.decode(Int.self, forKey: .displayPrecision)
        authoritativeValue = try container.decodeIfPresent(
            NFExactNumber.self,
            forKey: .authoritativeValue
        ) ?? NFExactNumber(legacyDouble: value) ?? (try NFExactNumber(numerator: 0))
        authoritativeTolerance = try container.decodeIfPresent(
            NFExactNumericTolerance.self,
            forKey: .authoritativeTolerance
        ) ?? NFExactNumericTolerance(legacy: tolerance) ?? .absolute(try NFExactNumber(numerator: 0))
    }
}

struct NFNumericResponseSchema: Codable, Equatable, Sendable {
    let answer: NFNumericAnswer
    let placeholder: String
    let permitsScientificNotation: Bool
    let permitsThousandsSeparators: Bool
}

struct NFChoiceOption: Codable, Equatable, Sendable, Identifiable {
    let id: String
    let text: String
    let accessibilityLabel: String?
    let distractorCode: String?
}

struct NFSingleChoiceResponseSchema: Codable, Equatable, Sendable {
    let options: [NFChoiceOption]
    let correctOptionID: String
}

struct NFMultipleChoiceResponseSchema: Codable, Equatable, Sendable {
    let options: [NFChoiceOption]
    let correctOptionIDs: [String]
    let minimumSelections: Int
    let maximumSelections: Int
    var acceptedAlternativeSets: [[String]]? = nil
}

struct NFOrderedStep: Codable, Equatable, Sendable, Identifiable {
    let id: String
    let text: String
}

struct NFOrderingDependency: Codable, Equatable, Sendable {
    let before: String
    let after: String
}

struct NFOrderedStepsResponseSchema: Codable, Equatable, Sendable {
    let steps: [NFOrderedStep]
    let correctOrder: [String]
    /// nil preserves a legacy strict chain; [] deliberately accepts every complete order.
    var dependencies: [NFOrderingDependency]? = nil
}

enum NFShortTextScoringRule: Codable, Equatable, Sendable {
    case normalizedExact(acceptedAnswers: [String])
    case requiredTerms(terms: [String], minimumMatches: Int)
    /// Deterministic concept scoring for open responses where a bag of words
    /// is not sufficient authority. Accepted answers remain exact safe paths,
    /// required groups describe the correct semantic direction, and rejected
    /// assertion groups stop an otherwise keyword-complete contradiction.
    case constrainedConcepts(
        acceptedAnswers: [String],
        requiredTerms: [String],
        minimumMatches: Int,
        rejectedAssertions: [String]
    )
}

enum NFShortTextAuthority: Codable, Equatable, Sendable {
    case symbolic(NFSymbolicAnswerContract)
    case exactQuantity(NFNumericResponseSchema)
    case reviewedProse(acceptedAnswers: [String], rejectedAssertions: [String])
    case identifier(acceptedAnswers: [String])
    case unsignedBinaryNumeral(NFUnsignedBinaryNumeralContract)
}

struct NFShortTextResponseSchema: Codable, Equatable, Sendable {
    let expectedAnswer: String
    let scoringRule: NFShortTextScoringRule
    let maximumCharacters: Int
    var authority: NFShortTextAuthority? = nil
}

struct NFSelfCheckResponseSchema: Codable, Equatable, Sendable {
    let referenceAnswer: String
    let criteria: [String]
    let asksForReflection: Bool
}

struct NFClaimOption: Codable, Equatable, Sendable, Identifiable {
    let id: String
    let text: String
}

struct NFEvidenceOption: Codable, Equatable, Sendable, Identifiable {
    let id: String
    let text: String
    let citationID: String?
}

struct NFClaimEvidencePair: Codable, Equatable, Sendable {
    let claimID: String
    let evidenceIDs: [String]
}

struct NFClaimSupportContract: Codable, Equatable, Sendable {
    let claimID: String
    /// Each inner set is independently sufficient; no unlisted attachment is supported.
    let sufficientBundles: [[String]]
}

struct NFClaimEvidenceSelectionScope: Codable, Equatable, Sendable {
    var schemaVersion = 1
    let claimID: String
    let evidenceIDs: [String]
    let minimumSelections: Int
    let maximumSelections: Int
}

struct NFClaimEvidenceResponseSchema: Codable, Equatable, Sendable {
    let claims: [NFClaimOption]
    let evidence: [NFEvidenceOption]
    let correctPairs: [NFClaimEvidencePair]
    var supportContracts: [NFClaimSupportContract]? = nil
    var selectionScopes: [NFClaimEvidenceSelectionScope]? = nil
}

struct NFLogicStateResponseSchema: Codable, Equatable, Sendable {
    let initialState: [String: String]
    let expectedFinalState: [String: String]
    let acceptedEquivalentStates: [[String: String]]
    let ruleOptions: [NFChoiceOption]
    let expectedViolatedRuleID: String?
    var fieldDomains: [String: NFStateFieldDomain]? = nil
    var plausibilityPolicy: NFEstimatePlausibilityPolicy? = nil
}

enum NFExerciseInteraction: Codable, Equatable, Sendable {
    case numeric(NFNumericResponseSchema)
    case singleChoice(NFSingleChoiceResponseSchema)
    case multipleChoice(NFMultipleChoiceResponseSchema)
    case orderedSteps(NFOrderedStepsResponseSchema)
    case shortText(NFShortTextResponseSchema)
    case selfCheck(NFSelfCheckResponseSchema)
    case claimEvidence(NFClaimEvidenceResponseSchema)
    case logicState(NFLogicStateResponseSchema)
}

// MARK: - Rubric and feedback

struct NFExerciseRubricCriterion: Codable, Equatable, Sendable, Identifiable {
    let id: String
    let description: String
    let weight: Double
}

struct NFExerciseRubric: Codable, Equatable, Sendable {
    let criteria: [NFExerciseRubricCriterion]
    let fullCreditThreshold: Double
    let permitsPartialCredit: Bool
}

struct NFExerciseFeedbackSpec: Codable, Equatable, Sendable {
    let timing: NFExerciseFeedbackTiming
    let correctTitle: String
    let correctExplanation: String
    let retryTitle: String
    let retryExplanation: String
    let decisiveStep: String
    let hintLadder: [String]
    let errorExplanations: [String: String]
}

// MARK: - Complete authored exercise

enum NFResponseEditPolicy: String, Codable, Equatable, Sendable {
    /// The submitted response is locked while confidence is captured. This is
    /// the default for recognition, numeric, self-check, and all protected work.
    case lockedAfterSubmit

    /// Deliberative construction tasks may explicitly return to the response
    /// before confidence is committed; each return increments revision telemetry.
    case editableBeforeCommit
}

struct NFExercise: Codable, Equatable, Sendable, Identifiable {
    let id: String
    let schemaVersion: Int
    let generatorVersion: Int
    let templateID: String
    let templateFamily: String
    let templateVersion: Int
    let seed: UInt64
    let lab: TrainingLab
    let purpose: NFExercisePurpose
    let evidenceClass: EvidenceClass
    let localeIdentifier: String
    let title: String
    let prompt: String
    let contextText: String?
    let instructions: String
    let sourceContext: NFExerciseSourceContext
    let interaction: NFExerciseInteraction
    let difficulty: NFExerciseDifficulty
    let skillWeights: [String: Double]
    let strategies: [NFExerciseStrategy]
    let representations: [NFExerciseRepresentation]
    let citations: [NFExerciseCitation]
    let provenance: NFExerciseProvenance
    let rubric: NFExerciseRubric
    let feedback: NFExerciseFeedbackSpec
    let accessibility: NFExerciseAccessibility
    let assessmentProtected: Bool
    let expectedDurationSeconds: Int
    let timingEligible: Bool
    let responseEditPolicy: NFResponseEditPolicy
    let tags: [String]
    var contractMetadata: NFExerciseContractMetadata? = nil
    var availabilityReason: String? = nil
    /// Present only on a new, explicitly pinned semantic evaluation contract.
    /// Legacy self-check and exact-answer records retain their original authority.
    var aiRubric: NFAIGradingRubric? = nil

    var spatialDifficultyParameters: NFSpatialDifficultyParameters? {
        representations.lazy.compactMap { representation in
            guard case let .spatial(metadata) = representation else { return nil }
            return metadata.difficultyParameters
        }.first
    }
}

// MARK: - Learner submissions and deterministic results

struct NFNumericSubmission: Codable, Equatable, Sendable {
    let value: String
    let unit: String?
}

enum NFSelfCheckRating: String, Codable, CaseIterable, Sendable {
    case matched
    case partiallyMatched
    case notYet
}

struct NFSelfCheckSubmission: Codable, Equatable, Sendable {
    let rating: NFSelfCheckRating
    let reflection: String?
}

struct NFClaimEvidenceSubmission: Codable, Equatable, Sendable {
    let pairs: [NFClaimEvidencePair]
}

struct NFLogicStateSubmission: Codable, Equatable, Sendable {
    let finalState: [String: String]
    let violatedRuleID: String?
}

enum NFExerciseResponse: Codable, Equatable, Sendable {
    case numeric(NFNumericSubmission)
    case singleChoice(optionID: String)
    case multipleChoice(optionIDs: [String])
    case orderedSteps(stepIDs: [String])
    case shortText(String)
    case selfCheck(NFSelfCheckSubmission)
    case claimEvidence(NFClaimEvidenceSubmission)
    case logicState(NFLogicStateSubmission)

    /// The typed response schema is deterministic telemetry; it is not the
    /// learner's physical input modality.
    var responseFormatRaw: String {
        switch self {
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
}

struct NFExerciseFeedback: Codable, Equatable, Sendable {
    let title: String
    let explanation: String
    let decisiveStep: String?
    let strategy: String?
    let errorCode: String?
    let isDelayed: Bool
}

enum NFScoringOutcome: String, Codable, Equatable, Sendable {
    case correct, partial, incorrect, needsClarification, selfReported, skipped, invalidItem

    var objectiveCorrectness: Bool? {
        switch self {
        case .correct: true
        case .partial, .incorrect: false
        case .needsClarification, .selfReported, .skipped, .invalidItem: nil
        }
    }
}

struct NFScoringComponentResult: Codable, Equatable, Sendable {
    let id: String
    let submittedValue: String
    let parsedValue: String?
    let ruleVersion: Int
    let outcome: NFScoringOutcome
    let awardedCredit: Double
    let maximumCredit: Double
    let misconceptionCode: String?
    let explanation: String
}

struct NFExerciseScoringResult: Codable, Equatable, Sendable {
    let exerciseID: String
    let scoringVersion: Int
    let isCorrect: Bool
    let credit: Double
    let normalizedResponse: String?
    let errorCode: String?
    let expectedAnswerSummary: String?
    let feedback: NFExerciseFeedback
    let outcome: NFScoringOutcome
    let components: [NFScoringComponentResult]
    var aiGrade: NFAIGradeReceipt?

    var objectiveCorrectness: Bool? { outcome.objectiveCorrectness }

    init(exerciseID: String, scoringVersion: Int, isCorrect: Bool, credit: Double,
         normalizedResponse: String?, errorCode: String?, expectedAnswerSummary: String?,
         feedback: NFExerciseFeedback, outcome: NFScoringOutcome? = nil,
         components: [NFScoringComponentResult] = [], aiGrade: NFAIGradeReceipt? = nil) {
        self.exerciseID = exerciseID
        self.scoringVersion = scoringVersion
        self.isCorrect = isCorrect
        self.credit = credit
        self.normalizedResponse = normalizedResponse
        self.errorCode = errorCode
        self.expectedAnswerSummary = expectedAnswerSummary
        self.feedback = feedback
        self.outcome = outcome ?? (isCorrect ? .correct : (credit > 0 ? .partial : .incorrect))
        self.components = components
        self.aiGrade = aiGrade
    }

    private enum CodingKeys: String, CodingKey {
        case exerciseID, scoringVersion, isCorrect, credit, normalizedResponse, errorCode
        case expectedAnswerSummary, feedback, outcome, components, aiGrade
    }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(exerciseID: try c.decode(String.self, forKey: .exerciseID),
                  scoringVersion: try c.decode(Int.self, forKey: .scoringVersion),
                  isCorrect: try c.decode(Bool.self, forKey: .isCorrect),
                  credit: try c.decode(Double.self, forKey: .credit),
                  normalizedResponse: try c.decodeIfPresent(String.self, forKey: .normalizedResponse),
                  errorCode: try c.decodeIfPresent(String.self, forKey: .errorCode),
                  expectedAnswerSummary: try c.decodeIfPresent(String.self, forKey: .expectedAnswerSummary),
                  feedback: try c.decode(NFExerciseFeedback.self, forKey: .feedback),
                  outcome: try c.decodeIfPresent(NFScoringOutcome.self, forKey: .outcome),
                  components: try c.decodeIfPresent([NFScoringComponentResult].self, forKey: .components) ?? [],
                  aiGrade: try c.decodeIfPresent(NFAIGradeReceipt.self, forKey: .aiGrade))
    }
}

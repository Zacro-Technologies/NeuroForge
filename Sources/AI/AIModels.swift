import Foundation

enum NFAICapability: String, Codable, CaseIterable, Identifiable, Sendable {
    case contextualize = "contextualize_exercise"
    case sourceGroundedPractice = "source_grounded_practice"
    case transferVariant = "transfer_variant"
    case progressiveHint = "progressive_hint"
    case conciseExplanation = "concise_explanation"
    case errorDiagnosis = "error_diagnosis"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .contextualize: NFAppLocalization.localized("Field-specific practice", locale: NFAppLocalization.preferredLocale, comment: "AI Practice Studio capability.")
        case .sourceGroundedPractice: NFAppLocalization.localized("Practice from my material", locale: NFAppLocalization.preferredLocale, comment: "AI Practice Studio capability using a selected local source.")
        case .transferVariant: NFAppLocalization.localized("Transfer challenge", locale: NFAppLocalization.preferredLocale, comment: "AI Practice Studio capability for applying a skill in another context.")
        case .progressiveHint: NFAppLocalization.localized("Progressive hint", locale: NFAppLocalization.preferredLocale, comment: "AI Practice Studio capability.")
        case .conciseExplanation: NFAppLocalization.localized("Tailored explanation", locale: NFAppLocalization.preferredLocale, comment: "AI Practice Studio capability.")
        case .errorDiagnosis: NFAppLocalization.localized("Error-pattern coaching", locale: NFAppLocalization.preferredLocale, comment: "AI Practice Studio capability.")
        }
    }
}

enum NFAIRoute: String, Codable, Sendable {
    /// Retained only so previously saved provenance can still decode. New
    /// authoring never selects this route.
    case privateCloudCompute = "private_cloud_compute"
    /// Retained for decoding results from the earlier Apple Intelligence-named
    /// Shortcut route. New results use `externalShortcut`.
    case shortcutsAppleIntelligence = "shortcuts_apple_intelligence"
    /// New provider-neutral provenance for the user-owned Question Writer
    /// Shortcut. The template may recommend ChatGPT, but the app cannot attest
    /// which model a learner selected after installing or editing it.
    case externalShortcut = "external_shortcut"
    case onDevice = "on_device"
    case directCloud = "direct_cloud"
    case deterministicFallback = "deterministic_fallback"
}

enum NFAIRouteState: String, Codable, Sendable {
    case ready
    case unavailable
    case forbidden
    case fallback

    var title: String {
        switch self {
        case .ready:
            NFAppLocalization.localized("Ready", locale: NFAppLocalization.preferredLocale, comment: "AI processing-route status.")
        case .unavailable:
            NFAppLocalization.localized("Unavailable", locale: NFAppLocalization.preferredLocale, comment: "AI processing-route status.")
        case .forbidden:
            NFAppLocalization.localized("Not allowed", locale: NFAppLocalization.preferredLocale, comment: "AI processing-route status when the learner's privacy choice forbids a route.")
        case .fallback:
            NFAppLocalization.localized("Using fallback", locale: NFAppLocalization.preferredLocale, comment: "AI processing-route status when a safe local fallback is active.")
        }
    }
}

struct NFAIRouteSnapshot: Codable, Equatable, Sendable {
    let route: NFAIRoute
    let state: NFAIRouteState
    let reason: String
}

enum NFSourceSupportLevel: String, Codable, Equatable, Sendable {
    case notApplicable = "not_applicable"
    case citationIdentifiersOnly = "citation_identifiers_only"
    case lexicalOverlap = "lexical_overlap"
    case deterministicSourceTransformation = "deterministic_source_transformation"
    case exactAnswerText = "exact_answer_text"
}

enum NFAuthoringValidationLevel: String, Codable, Equatable, Sendable {
    case deterministicKey = "deterministic_key"
    case deterministicKeyWithModelContext = "deterministic_key_with_model_context"
    case exactSourceRestatement = "exact_source_restatement"
    case independentlyCheckedModelKey = "independently_checked_model_key"
    case sourceLinkedModelOutput = "source_linked_model_output"
    case schemaCheckedModelOutput = "schema_checked_model_output"
    case rubricModelOutput = "rubric_model_output"
}

struct NFAuthoringValidationStatus: Codable, Equatable, Sendable {
    let level: NFAuthoringValidationLevel
    let sourceSupport: NFSourceSupportLevel

    var title: String {
        switch level {
        case .deterministicKey: NFAppLocalization.localized("Deterministic answer key", locale: NFAppLocalization.preferredLocale, comment: "Authoring-validation status; the app computed the key using fixed rules.")
        case .deterministicKeyWithModelContext: NFAppLocalization.localized("Deterministic key + AI context", locale: NFAppLocalization.preferredLocale, comment: "Authoring-validation status for a fixed app-computed answer key with optional model-generated presentation context.")
        case .exactSourceRestatement: NFAppLocalization.localized("Exact source restatement", locale: NFAppLocalization.preferredLocale, comment: "Authoring-validation status; the key is copied exactly from one cited excerpt.")
        case .independentlyCheckedModelKey: NFAppLocalization.localized("Independently checked model key", locale: NFAppLocalization.preferredLocale, comment: "Authoring-validation status; model output passed a separate exact-restatement check.")
        case .sourceLinkedModelOutput: NFAppLocalization.localized("Source-linked model output", locale: NFAppLocalization.preferredLocale, comment: "Authoring-validation status; linkage does not establish factual truth.")
        case .schemaCheckedModelOutput: NFAppLocalization.localized("Schema-checked model output", locale: NFAppLocalization.preferredLocale, comment: "Authoring-validation status; schema validation does not establish factual truth.")
        case .rubricModelOutput: NFAppLocalization.localized("AI practice with a saved rubric", locale: NFAppLocalization.preferredLocale, comment: "AI-authored practice has a fixed rubric for later semantic grading.")
        }
    }

    var summary: String {
        switch level {
        case .deterministicKey:
            if sourceSupport == .deterministicSourceTransformation {
                NFAppLocalization.localized("The fallback applied a deterministic operation to cited text and explicit prompt values. This verifies the exercise key, not the source’s real-world truth.", locale: NFAppLocalization.preferredLocale, comment: "Disclosure explaining the limits of deterministic source-grounded answer validation.")
            } else {
                NFAppLocalization.localized("The fallback generated its answer key deterministically. This checks the exercise key, not every real-world claim in its context.", locale: NFAppLocalization.preferredLocale, comment: "Disclosure explaining the limits of deterministic answer validation.")
            }
        case .deterministicKeyWithModelContext:
            if sourceSupport == .exactAnswerText {
                NFAppLocalization.localized("NeuroForge fixed the prompt and reference answer from an exact cited-source contract. Optional presentation text could not change the key, rubric, or score.", locale: NFAppLocalization.preferredLocale, comment: "Compatibility disclosure for a restored question with optional presentation text.")
            } else if sourceSupport == .deterministicSourceTransformation {
                NFAppLocalization.localized("NeuroForge computed the prompt, source transformation, key, rubric, and score deterministically. Optional presentation text could not change them.", locale: NFAppLocalization.preferredLocale, comment: "Compatibility disclosure for a restored source question with optional presentation text.")
            } else {
                NFAppLocalization.localized("NeuroForge computed the prompt, key, rubric, and score deterministically. Optional presentation text could not change them.", locale: NFAppLocalization.preferredLocale, comment: "Compatibility disclosure for a restored question with optional presentation text.")
            }
        case .exactSourceRestatement:
            NFAppLocalization.localized("The reference answer is copied from the cited excerpt. NeuroForge does not independently verify that the source itself is true.", locale: NFAppLocalization.preferredLocale, comment: "Disclosure explaining the limits of an exact cited-source restatement.")
        case .independentlyCheckedModelKey:
            NFAppLocalization.localized("The model selected an answer that NeuroForge independently matched as an exact restatement of one cited excerpt under a fixed response contract. The source itself is not independently verified.", locale: NFAppLocalization.preferredLocale, comment: "Disclosure explaining an independently checked model answer and its limits.")
        case .sourceLinkedModelOutput:
            NFAppLocalization.localized("Structure, citation IDs, and lexical overlap with cited excerpts passed automated checks. This does not prove the proposed answer or reasoning is factually correct.", locale: NFAppLocalization.preferredLocale, comment: "Disclosure explaining the limits of source-linked model output.")
        case .schemaCheckedModelOutput:
            NFAppLocalization.localized("Structure passed automated checks. The proposed answer and explanation are model-generated and were not factually verified.", locale: NFAppLocalization.preferredLocale, comment: "Disclosure explaining the limits of schema-checked model output.")
        case .rubricModelOutput:
            NFAppLocalization.localized("The question, reference answer and rubric are saved together. Response structure and source references were checked; these checks do not certify factual accuracy or grading quality.", locale: NFAppLocalization.preferredLocale, comment: "Details of structural checks for an AI-authored question and fixed rubric.")
        }
    }

    /// Result-level authoring checks never certify broad factual truth. A
    /// deterministic key can verify an exercise operation, while cited text can
    /// verify an exact restatement, but neither establishes external truth.
    var establishesFactualTruth: Bool { false }

    var isModelOutput: Bool {
        level == .deterministicKeyWithModelContext
            || level == .independentlyCheckedModelKey
            || level == .sourceLinkedModelOutput
            || level == .schemaCheckedModelOutput
            || level == .rubricModelOutput
    }

    var hasDeterministicAnswerAuthority: Bool {
        level == .deterministicKey
            || level == .deterministicKeyWithModelContext
            || level == .exactSourceRestatement
            || level == .independentlyCheckedModelKey
    }
}

enum NFAuthoringScaffoldingLevel: String, Codable, CaseIterable, Sendable {
    case foundation
    case developing
    case advanced
    case expert

    init(difficulty: Double) {
        switch difficulty {
        case ..<0.35: self = .foundation
        case ..<0.60: self = .developing
        case ..<0.80: self = .advanced
        default: self = .expert
        }
    }

    var title: String { localizedTitle(locale: NFAppLocalization.preferredLocale) }

    func localizedTitle(locale: Locale) -> String {
        switch self {
        case .foundation: NFAppLocalization.localized("Step-by-step guidance", locale: locale, comment: "AI Practice Studio support level for introductory practice.")
        case .developing: NFAppLocalization.localized("Strategy guidance", locale: locale, comment: "AI Practice Studio support level for intermediate practice.")
        case .advanced: NFAppLocalization.localized("Light guidance", locale: locale, comment: "AI Practice Studio support level for advanced practice.")
        case .expert: NFAppLocalization.localized("Minimal guidance", locale: locale, comment: "AI Practice Studio support level for expert practice.")
        }
    }

    var modelInstruction: String {
        switch self {
        case .foundation:
            "Name the first useful representation and a concrete first step, but stop before performing it."
        case .developing:
            "Name a strategy and one intermediate checkpoint, but do not carry out the computation or inference."
        case .advanced:
            "Point to the governing constraint and a useful self-check without resolving the task."
        case .expert:
            "Use a minimal audit cue focused on assumptions, edge cases, or transfer limits."
        }
    }
}

enum NFQuestionStyle: String, Codable, CaseIterable, Identifiable, Sendable {
    case multipleChoice
    case shortAnswer
    case numerical
    case proofOrDerivation
    case debugging
    case experimentalDesign
    case dataInterpretation
    case spatialTransformation

    var id: String { rawValue }

    var title: String { localizedTitle(locale: NFAppLocalization.preferredLocale) }

    func localizedTitle(locale: Locale) -> String {
        switch self {
        case .multipleChoice: NFAppLocalization.localized("Multiple choice", locale: locale, comment: "AI-authored question style.")
        case .shortAnswer: NFAppLocalization.localized("Short answer", locale: locale, comment: "AI-authored question style.")
        case .numerical: NFAppLocalization.localized("Numerical problem", locale: locale, comment: "AI-authored question style.")
        case .proofOrDerivation: NFAppLocalization.localized("Proof or derivation", locale: locale, comment: "AI-authored question style.")
        case .debugging: NFAppLocalization.localized("Debugging", locale: locale, comment: "AI-authored question style.")
        case .experimentalDesign: NFAppLocalization.localized("Experimental design", locale: locale, comment: "AI-authored question style.")
        case .dataInterpretation: NFAppLocalization.localized("Data interpretation", locale: locale, comment: "AI-authored question style.")
        case .spatialTransformation: NFAppLocalization.localized("Spatial transformation", locale: locale, comment: "AI-authored question style.")
        }
    }
}

/// Deterministic request policy for models that expose a reasoning-effort
/// control. It is metadata and a resource bound, never answer authority.
enum NFAuthoringReasoningLevel: String, Codable, Equatable, Sendable {
    case low
    case medium
    case high

    var responseTokenCeiling: Int {
        switch self {
        case .low: 2_048
        case .medium: 3_072
        case .high: 4_096
        }
    }
}

enum NFAuthoringTokenPolicy {
    static func maximumResponseTokens(
        for level: NFAuthoringReasoningLevel,
        itemCount: Int,
        base: Int,
        perItem: Int
    ) -> Int {
        let boundedCount = min(12, max(1, itemCount))
        return min(level.responseTokenCeiling, max(256, base + boundedCount * perItem))
    }
}

enum NFExternalModelScope: String, Codable, Equatable, Sendable {
    case userConfiguredQuestionWriterShortcut = "user_configured_question_writer_shortcut"
}

struct NFExternalSourceExcerptBinding: Codable, Hashable, Sendable {
    let chunkID: String
    let documentID: UUID
    let documentVersion: Int
    let contentHash: String

    init(chunk: NFSourceChunk) {
        chunkID = chunk.id
        documentID = chunk.documentID
        documentVersion = chunk.documentVersion
        contentHash = chunk.contentHash
    }
}

/// One-run disclosure consent for sending selected source excerpts through a
/// user-owned Shortcut. It is deliberately bound to exact chunk identities and
/// is not inferred from the global AI preference or a synced document policy.
struct NFExternalSourceConsent: Codable, Equatable, Sendable {
    static let currentPolicyVersion = 1

    let policyVersion: Int
    let scope: NFExternalModelScope
    let requestID: UUID
    let consentedAt: Date
    let excerptBindings: [NFExternalSourceExcerptBinding]

    static func make(
        explicitlyGranted: Bool,
        requestID: UUID,
        sourceChunks: [NFSourceChunk],
        consentedAt: Date = Date()
    ) -> Self? {
        guard explicitlyGranted, !sourceChunks.isEmpty else { return nil }
        let bindings = sourceChunks.map(NFExternalSourceExcerptBinding.init(chunk:))
        guard Set(bindings).count == bindings.count else { return nil }
        return Self(
            policyVersion: currentPolicyVersion,
            scope: .userConfiguredQuestionWriterShortcut,
            requestID: requestID,
            consentedAt: consentedAt,
            excerptBindings: bindings
        )
    }

    func matches(requestID: UUID, sourceChunks: [NFSourceChunk]) -> Bool {
        policyVersion == Self.currentPolicyVersion
            && scope == .userConfiguredQuestionWriterShortcut
            && self.requestID == requestID
            && Set(excerptBindings) == Set(sourceChunks.map(NFExternalSourceExcerptBinding.init(chunk:)))
    }
}

struct NFAuthoringRequest: Codable, Sendable {
    /// Version 14 adds provider-neutral Shortcut provenance plus the bounded,
    /// instruction-isolated source-excerpt contract.
    static let promptVersion = 14

    let id: UUID
    let capability: NFAICapability
    let lab: TrainingLab
    let field: STEMField
    let customTopic: String
    let learningObjective: String
    let style: NFQuestionStyle
    let difficulty: Double
    let count: Int
    let localeIdentifier: String
    let seed: UInt64
    var sourceChunks: [NFSourceChunk]
    let documentPolicies: [DocumentAIPolicy]
    let externalSourceConsent: NFExternalSourceConsent?
    let aiMode: AIMode
    let allowsShortcutAuthoring: Bool

    init(
        id: UUID = UUID(),
        capability: NFAICapability,
        lab: TrainingLab,
        field: STEMField,
        customTopic: String,
        learningObjective: String,
        style: NFQuestionStyle,
        difficulty: Double,
        count: Int,
        localeIdentifier: String = Locale.current.identifier,
        seed: UInt64,
        sourceChunks: [NFSourceChunk] = [],
        documentPolicies: [DocumentAIPolicy] = [],
        externalSourceConsent: NFExternalSourceConsent? = nil,
        aiMode: AIMode,
        allowsShortcutAuthoring: Bool = false
    ) {
        self.id = id
        self.capability = capability
        self.lab = lab
        self.field = field
        self.customTopic = customTopic
        self.learningObjective = learningObjective
        self.style = style
        self.difficulty = difficulty.isFinite ? min(1, max(0, difficulty)) : 0.5
        self.count = min(12, max(1, count))
        self.localeIdentifier = localeIdentifier
        self.seed = seed
        self.sourceChunks = sourceChunks
        self.documentPolicies = documentPolicies
        self.externalSourceConsent = externalSourceConsent
        self.aiMode = aiMode
        self.allowsShortcutAuthoring = allowsShortcutAuthoring
    }

    var usesSourceMaterial: Bool { !sourceChunks.isEmpty }

    var reasoningLevel: NFAuthoringReasoningLevel {
        switch style {
        case .proofOrDerivation, .debugging, .experimentalDesign, .dataInterpretation:
            difficulty >= 0.65 ? .high : .medium
        case .numerical, .spatialTransformation:
            difficulty >= 0.80 ? .high : .medium
        case .multipleChoice, .shortAnswer:
            difficulty >= 0.85 ? .medium : .low
        }
    }

    var sourceDocumentIDs: Set<UUID> { Set(sourceChunks.map(\.documentID)) }
}

struct NFAuthoredQuestion: Identifiable, Codable, Equatable, Sendable {
    let id: String
    let lab: TrainingLab
    let style: NFQuestionStyle
    let prompt: String
    let context: String
    let choices: [String]
    let correctAnswer: String
    let acceptedAnswers: [String]
    let explanation: String
    let hint: String
    let decisiveStep: String
    let difficulty: Double
    let citationChunkIDs: [String]
    let evidenceClass: EvidenceClass
    /// The complete immutable response schema, rubric, provenance, and scoring
    /// contract. Presentation-model output is stored separately and cannot
    /// replace this deterministic authority.
    let authoritativeExercise: NFExercise
    let presentationEnhancement: NFExercisePresentationEnhancement?

    init(
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
        authoritativeExercise: NFExercise? = nil,
        presentationEnhancement: NFExercisePresentationEnhancement? = nil
    ) {
        self.id = id
        self.lab = lab
        self.style = style
        self.prompt = prompt
        self.context = context
        self.choices = choices
        self.correctAnswer = correctAnswer
        self.acceptedAnswers = acceptedAnswers
        self.explanation = explanation
        self.hint = hint
        self.decisiveStep = decisiveStep
        self.difficulty = difficulty
        self.citationChunkIDs = citationChunkIDs
        self.evidenceClass = evidenceClass
        self.authoritativeExercise = authoritativeExercise ?? NFAuthoredExerciseAuthority.make(
            id: id,
            lab: lab,
            style: style,
            prompt: prompt,
            context: context,
            choices: choices,
            correctAnswer: correctAnswer,
            acceptedAnswers: acceptedAnswers,
            explanation: explanation,
            hint: hint,
            decisiveStep: decisiveStep,
            difficulty: difficulty,
            citationChunkIDs: citationChunkIDs,
            evidenceClass: evidenceClass
        )
        self.presentationEnhancement = presentationEnhancement
    }

    var hasObjectiveKey: Bool {
        switch style {
        case .proofOrDerivation, .experimentalDesign:
            !acceptedAnswers.isEmpty
        default:
            !correctAnswer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    /// The response surface and key must agree before an authored item can be
    /// cached or restored. Free-response rubrics remain user-compared, while
    /// numerical and choice keys are mechanically comparable.
    var hasValidResponseSchema: Bool {
        let normalizedAnswer = correctAnswer.trimmingCharacters(in: .whitespacesAndNewlines)
        let legacySurfaceIsValid: Bool
        if case .selfCheck = authoritativeExercise.interaction {
            // Model-authored and open deterministic reasoning use a typed
            // recall → reveal → self-rate contract. Their reference remains
            // presentation content, never an automatic scoring authority.
            legacySurfaceIsValid = choices.isEmpty && !normalizedAnswer.isEmpty
        } else {
            legacySurfaceIsValid = switch style {
            case .multipleChoice:
                choices.count == 4
                    && Set(choices).count == 4
                    && choices.contains(normalizedAnswer)
            case .numerical:
                choices.isEmpty
                    && Double(normalizedAnswer.replacingOccurrences(of: ",", with: "")) != nil
            case .proofOrDerivation, .experimentalDesign:
                choices.isEmpty
                    && !normalizedAnswer.isEmpty
                    && acceptedAnswers.contains { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            case .shortAnswer, .debugging, .dataInterpretation, .spatialTransformation:
                choices.isEmpty && !normalizedAnswer.isEmpty
            }
        }
        return legacySurfaceIsValid && NFAuthoredExerciseAuthority.validatesBinding(self)
    }

    var hasValidBoundedPresentationLayer: Bool {
        guard let enhancement = presentationEnhancement,
              enhancement.deterministicExerciseID == id,
              enhancement.route == .onDevice,
              NFAuthoringScaffoldingLevel(rawValue: enhancement.scaffoldingLevel ?? "") != nil,
              enhancement.sourceChunkIDs == citationChunkIDs else {
            return false
        }
        let seed = NFPresentationEnhancementSeed(
            deterministicExerciseID: id,
            lab: lab,
            field: .general,
            title: style.title,
            prompt: prompt,
            instructions: context,
            forbiddenAnswerStrings: [correctAnswer] + acceptedAnswers
        )
        return (try? NFPresentationEnhancementValidator.validate(
            [enhancement],
            for: NFPresentationEnhancementGenerationRequest(
                compatibilityFingerprint: "authored-presentation-recovery",
                localeIdentifier: localeIdentifierForPresentationValidation,
                aiMode: .onDeviceOnly,
                seeds: [seed]
            )
        )) != nil
    }

    private var localeIdentifierForPresentationValidation: String { "en" }
}

struct NFAIGenerationProvenance: Codable, Sendable {
    let requestID: UUID
    let generatedAt: Date
    let route: NFAIRoute
    let routeReason: String
    let promptVersion: Int
    let modelIdentifier: String
    let sourceChunkIDs: [String]
    let sourceDocumentIDs: [UUID]
    let validationVersion: Int
    let repairCount: Int
    let cacheKey: String
    let isFallback: Bool
}

struct NFAuthoringResult: Codable, Sendable {
    let questions: [NFAuthoredQuestion]
    let provenance: NFAIGenerationProvenance
    let routeCandidates: [NFAIRouteSnapshot]
    let validationStatus: NFAuthoringValidationStatus
    let validationNotes: [String]
}

enum NFAIError: Error, LocalizedError, Sendable {
    case disabled
    case sourcePolicyForbidsAI
    case modelUnavailable(String)
    case unsupportedLocale
    case timedOut
    case invalidOutput([String])
    case generationFailed(String)

    var errorDescription: String? {
        switch self {
        case .disabled: NFAppLocalization.localized("Question Writer is off in Settings.", locale: NFAppLocalization.preferredLocale, comment: "Question Writer preference error.")
        case .sourcePolicyForbidsAI: NFAppLocalization.localized("Question Writer is off for a selected source.", locale: NFAppLocalization.preferredLocale, comment: "Question Writer error when a selected source is excluded.")
        case .modelUnavailable: NFAppLocalization.localized("Question Writer is unavailable.", locale: NFAppLocalization.preferredLocale, comment: "Question Writer availability error.")
        case .unsupportedLocale: NFAppLocalization.localized("Question writing does not support the current language.", locale: NFAppLocalization.preferredLocale, comment: "Question Writer language-availability error.")
        case .timedOut: NFAppLocalization.localized("Question writing took too long and was cancelled.", locale: NFAppLocalization.preferredLocale, comment: "Question Writer timeout error.")
        case .invalidOutput: NFAppLocalization.localized("The returned questions did not pass NeuroForge checks.", locale: NFAppLocalization.preferredLocale, comment: "Question Writer validation error.")
        case .generationFailed: NFAppLocalization.localized("Question writing did not finish.", locale: NFAppLocalization.preferredLocale, comment: "Question Writer generic error.")
        }
    }
}

protocol NFQuestionAuthoring: Sendable {
    func author(_ request: NFAuthoringRequest) async throws -> NFAuthoringResult
    func routeStatus(for request: NFAuthoringRequest) async -> [NFAIRouteSnapshot]
}

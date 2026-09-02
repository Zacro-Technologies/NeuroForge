import Foundation
import Observation
import SwiftData

private enum NFTelemetryCodec {
    static func encode<T: Encodable>(_ value: T) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(value) else { return "" }
        return String(data: data, encoding: .utf8) ?? ""
    }

    static func decode<T: Decodable>(_ type: T.Type, from value: String) -> T? {
        guard let data = value.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }
}

@Model
final class UserProfileRecord {
    var id: UUID = UUID()
    var createdAt: Date = Date()
    var modifiedAt: Date = Date()
    @Attribute(.allowsCloudEncryption)
    var stageRaw: String = Stage.undisclosed.rawValue
    @Attribute(.allowsCloudEncryption)
    var fieldsRaw: String = STEMField.general.rawValue
    @Attribute(.allowsCloudEncryption)
    var goalsRaw: String = "\(TrainingGoal.mentalMath.rawValue),\(TrainingGoal.dataReasoning.rawValue)"
    var dailyDuration: Int = 10
    var timingModeRaw: String = TimingMode.adaptive.rawValue
    var aiModeRaw: String = AIMode.automatic.rawValue
    var iCloudEnabled: Bool = false
    var reducedMotion: Bool = false
    var hideTimers: Bool = false
    var excludeVisualSpatial: Bool = false
    var onboardingVersion: Int = 1
    var claimsPolicyAcknowledgedVersion: Int = 0
    var pccConsentVersion: Int = 0
    var pccConsentAt: Date?
    var preferredLanguageCode: String = "en"
    var trainingDaysRaw: String = "1,2,3,4,5,6,7"
    var dayBoundaryHour: Int = 4
    var ageBandAcknowledged16Plus: Bool = false
    var preferredAnswerModeRaw: String = NFPreferredAnswerMode.adaptive.rawValue
    var reinforcementHapticsEnabled: Bool = false
    var reinforcementSoundEnabled: Bool = false

    init(draft: OnboardingDraft) {
        apply(draft)
    }

    func apply(_ draft: OnboardingDraft) {
        stageRaw = draft.stage.rawValue
        fieldsRaw = draft.fields.map(\.rawValue).sorted().joined(separator: ",")
        goalsRaw = draft.goals.map(\.rawValue).sorted().joined(separator: ",")
        dailyDuration = draft.dailyDuration
        timingModeRaw = draft.timingMode.rawValue
        aiModeRaw = draft.aiMode.rawValue
        iCloudEnabled = draft.iCloudEnabled
        reducedMotion = draft.reducedMotion
        hideTimers = draft.hideTimers
        excludeVisualSpatial = draft.excludeVisualSpatial
        preferredLanguageCode = draft.preferredLanguageCode
        trainingDaysRaw = draft.trainingDays.sorted().map(String.init).joined(separator: ",")
        dayBoundaryHour = min(12, max(0, draft.dayBoundaryHour))
        claimsPolicyAcknowledgedVersion = draft.claimsPolicyAcknowledgedVersion ?? 0
        ageBandAcknowledged16Plus = draft.ageBandAcknowledged16Plus
        preferredAnswerModeRaw = draft.preferredAnswerMode.rawValue
        reinforcementHapticsEnabled = draft.reinforcementHapticsEnabled
        reinforcementSoundEnabled = draft.reinforcementSoundEnabled
        modifiedAt = Date()
    }

    var snapshot: ProfileSnapshot {
        ProfileSnapshot(
            id: id,
            stage: Stage(rawValue: stageRaw) ?? .undisclosed,
            fields: Set(fieldsRaw.split(separator: ",").compactMap { STEMField(rawValue: String($0)) }),
            goals: Set(goalsRaw.split(separator: ",").compactMap { TrainingGoal(rawValue: String($0)) }),
            dailyDuration: dailyDuration,
            timingMode: TimingMode(rawValue: timingModeRaw) ?? .adaptive,
            aiMode: AIMode(rawValue: aiModeRaw) ?? .automatic,
            iCloudEnabled: iCloudEnabled,
            trainingDays: Set(trainingDaysRaw.split(separator: ",").compactMap { Int($0) }),
            dayBoundaryHour: dayBoundaryHour
        )
    }
}

@Model
final class InputCalibrationRecord {
    var id: UUID = UUID()
    var profileID: UUID = UUID()
    var completedAt: Date = Date()
    var preferredAnswerModeRaw: String = NFPreferredAnswerMode.adaptive.rawValue
    var keyboardLatencyMilliseconds: Double?
    var touchLatencyMilliseconds: Double?
    var pencilLatencyMilliseconds: Double?

    init(
        profileID: UUID,
        completedAt: Date = Date(),
        preferredAnswerMode: NFPreferredAnswerMode,
        keyboardLatencyMilliseconds: Double?,
        touchLatencyMilliseconds: Double?,
        pencilLatencyMilliseconds: Double?
    ) {
        self.profileID = profileID
        self.completedAt = completedAt
        preferredAnswerModeRaw = preferredAnswerMode.rawValue
        self.keyboardLatencyMilliseconds = Self.sanitized(keyboardLatencyMilliseconds)
        self.touchLatencyMilliseconds = Self.sanitized(touchLatencyMilliseconds)
        self.pencilLatencyMilliseconds = Self.sanitized(pencilLatencyMilliseconds)
    }

    var preferredAnswerMode: NFPreferredAnswerMode {
        NFPreferredAnswerMode(rawValue: preferredAnswerModeRaw) ?? .adaptive
    }

    private static func sanitized(_ value: Double?) -> Double? {
        guard let value, value.isFinite else { return nil }
        return min(60_000, max(0, value))
    }
}

@Model
final class ProgressAnnotationRecord {
    static let maximumNoteCharacters = 500

    var id: UUID = UUID()
    var startDate: Date = Date()
    var endDate: Date = Date()
    @Attribute(.allowsCloudEncryption)
    var note: String = ""
    var includeInExport: Bool = false
    var createdAt: Date = Date()
    var modifiedAt: Date = Date()

    init(
        id: UUID = UUID(),
        startDate: Date,
        endDate: Date,
        note: String,
        includeInExport: Bool,
        calendar: Calendar = .current
    ) {
        self.id = id
        let normalizedStart = calendar.startOfDay(for: startDate)
        let normalizedEnd = calendar.startOfDay(for: endDate)
        self.startDate = min(normalizedStart, normalizedEnd)
        self.endDate = max(normalizedStart, normalizedEnd)
        self.note = note.trimmingCharacters(in: .whitespacesAndNewlines)
        self.includeInExport = includeInExport
    }
}

enum NFProgressAnnotationPersistenceError: Error, Equatable, LocalizedError {
    case noteTooLong(maximum: Int)

    var errorDescription: String? {
        switch self {
        case let .noteTooLong(maximum):
            NFAppLocalization.localized(
                "Keep the annotation at \(maximum) characters or fewer. Nothing was saved or shortened.",
                locale: NFAppLocalization.preferredLocale,
                comment: "Progress-annotation persistence validation when submitted text exceeds the maximum length."
            )
        }
    }
}

@Model
final class AttemptRecord {
    var id: UUID = UUID()
    var sessionID: UUID = UUID()
    var itemID: String = ""
    var templateID: String = ""
    var seed: UInt64 = 0
    var gameID: String = TrainingLab.mentalMath.rawValue
    var skillID: String = TrainingLab.mentalMath.skillID
    @Attribute(.allowsCloudEncryption)
    var skillWeightsRaw: String = ""
    var domainContextRaw: String = STEMField.general.rawValue
    @Attribute(.allowsCloudEncryption)
    var transferBriefRaw: String = ""
    @Attribute(.allowsCloudEncryption)
    var spatialDifficultyParametersRaw: String = ""
    @Attribute(.allowsCloudEncryption)
    var prompt: String = ""
    @Attribute(.allowsCloudEncryption)
    var response: String = ""
    var correctAnswer: Double = 0
    @Attribute(.allowsCloudEncryption)
    var correctAnswerText: String = ""
    var isCorrect: Bool = false
    var confidenceRaw: String?
    var shownAt: Date = Date()
    var submittedAt: Date = Date()
    var activeDurationSeconds: Double = 0
    var evidenceClassRaw: String = EvidenceClass.practice.rawValue
    var sessionSourceRaw: String = SessionSource.focused.rawValue
    var evidenceWeight: Double = 1
    var errorCode: String?
    var scoringVersion: Int = 1
    var deviceID: UUID = UUID()
    var generationID: UUID?
    var sourceDocumentIDsRaw: String = ""
    var sourceChunkIDsRaw: String = ""
    var responseFormatRaw: String = "number"
    var wasSkipped: Bool = false
    var validationVersion: Int = 1
    var assessmentBlockRaw: String?
    var planID: String?
    var planBlockID: String?
    var deterministicCredit: Double = 0
    var hintCount: Int = 0
    var inputModeRaw: String = "unknown"
    var interruptionCount: Int = 0
    var revisionCount: Int = 0
    @Attribute(.allowsCloudEncryption)
    var accommodationFlagsRaw: String = ""
    var wasTimed: Bool = false
    var assessmentDescriptorID: String?
    var assessmentTemplateFamily: String?
    var assessmentFormatRaw: String?
    var assessmentMechanicID: String?
    var assessmentSubskillID: String?
    var assessmentSeed: UInt64?
    var assessmentCycle: Int?

    var skillWeights: [String: Double] {
        let decoded = NFTelemetryCodec.decode([String: Double].self, from: skillWeightsRaw) ?? [:]
        return decoded.isEmpty ? [skillID: 1] : decoded
    }

    var transferBrief: NFExerciseTransferBrief? {
        NFTelemetryCodec.decode(NFExerciseTransferBrief.self, from: transferBriefRaw)
    }

    var spatialDifficultyParameters: NFSpatialDifficultyParameters? {
        NFTelemetryCodec.decode(NFSpatialDifficultyParameters.self, from: spatialDifficultyParametersRaw)
    }

    init(
        sessionID: UUID,
        item: MentalMathItem,
        response: String,
        score: DeterministicScore,
        confidence: ConfidenceLevel,
        shownAt: Date,
        submittedAt: Date,
        activeDuration: TimeInterval,
        source: SessionSource
    ) {
        self.sessionID = sessionID
        itemID = item.id
        templateID = item.templateID
        seed = item.seed
        gameID = TrainingLab.mentalMath.rawValue
        skillID = TrainingLab.mentalMath.skillID
        prompt = item.prompt
        self.response = response
        correctAnswer = item.answer
        correctAnswerText = item.answer.formatted()
        isCorrect = score.isCorrect
        confidenceRaw = confidence.rawValue
        self.shownAt = shownAt
        self.submittedAt = submittedAt
        activeDurationSeconds = max(0, activeDuration)
        evidenceClassRaw = item.evidenceClass.rawValue
        sessionSourceRaw = source.rawValue
        evidenceWeight = item.evidenceClass == .documentPractice ? 0 : 1
        deterministicCredit = score.isCorrect ? 1 : 0
        errorCode = score.errorCode
        scoringVersion = MentalMathGenerator.scoringVersion
    }

    init(
        sessionID: UUID,
        lab: TrainingLab,
        itemID: String,
        prompt: String,
        response: String,
        correctAnswer: String,
        isCorrect: Bool,
        confidence: ConfidenceLevel,
        evidenceClass: EvidenceClass = .practice,
        source: SessionSource = .focused,
        sourceDocumentIDs: [UUID] = [],
        sourceChunkIDs: [String] = [],
        responseFormat: String = "singleChoice"
    ) {
        self.sessionID = sessionID
        self.itemID = itemID
        templateID = itemID
        seed = AdaptiveEngine.fnv1a64(itemID)
        gameID = lab.rawValue
        skillID = lab.skillID
        self.prompt = prompt
        self.response = response
        self.correctAnswer = Double(correctAnswer) ?? 0
        correctAnswerText = correctAnswer
        self.isCorrect = isCorrect
        confidenceRaw = confidence.rawValue
        shownAt = Date()
        submittedAt = Date()
        activeDurationSeconds = 0
        evidenceClassRaw = evidenceClass.rawValue
        sessionSourceRaw = source.rawValue
        evidenceWeight = evidenceClass == .documentPractice ? 0 : 1
        deterministicCredit = isCorrect ? 1 : 0
        errorCode = isCorrect ? nil : "operation_selection"
        scoringVersion = 1
        sourceDocumentIDsRaw = sourceDocumentIDs.map(\.uuidString).joined(separator: ",")
        sourceChunkIDsRaw = sourceChunkIDs.joined(separator: ",")
        responseFormatRaw = responseFormat
    }

    var dto: AttemptDTO {
        AttemptDTO(
            id: id,
            itemID: itemID,
            alternateFormID: assessmentTemplateFamily ?? itemID,
            skillID: skillID,
            skillWeights: skillWeights,
            lab: TrainingLab(rawValue: gameID) ?? .mentalMath,
            correct: isCorrect,
            credit: deterministicCredit,
            confidence: confidenceRaw.flatMap(ConfidenceLevel.init(rawValue:)),
            submittedAt: submittedAt,
            evidenceClass: EvidenceClass(rawValue: evidenceClassRaw) ?? .practice,
            evidenceWeight: evidenceWeight,
            interruptionCount: interruptionCount,
            accommodationFlags: Set(accommodationFlagsRaw.split(separator: ",").map(String.init)),
            wasTimed: wasTimed,
            spatialDifficultyParameters: spatialDifficultyParameters,
            assessmentFormat: assessmentFormatRaw.flatMap(NFAssessmentItemFormat.init(rawValue:))
        )
    }
}

/// Supplemental learner interpretation of one immutable attempt. This record
/// never changes the deterministic score, key, telemetry, or evidence weight.
@Model
final class AttemptReflectionRecord {
    static let maximumNoteCharacters = 500

    var id: UUID = UUID()
    var attemptID: UUID = UUID()
    var deterministicErrorCode: String?
    var selectedErrorCodeRaw: String?
    var triggerRaw: String = NFAttemptReflectionTrigger.highConfidenceError.rawValue
    @Attribute(.allowsCloudEncryption)
    var note: String = ""
    var createdAt: Date = Date()
    var policyVersion: Int = 1

    init(
        attemptID: UUID,
        deterministicErrorCode: String?,
        selectedErrorCode: NFErrorReflectionCode?,
        trigger: NFAttemptReflectionTrigger,
        note: String,
        createdAt: Date = Date()
    ) {
        self.attemptID = attemptID
        self.deterministicErrorCode = deterministicErrorCode
        selectedErrorCodeRaw = selectedErrorCode?.rawValue
        triggerRaw = trigger.rawValue
        self.note = note.trimmingCharacters(in: .whitespacesAndNewlines)
        self.createdAt = createdAt
    }

    var selectedErrorCode: NFErrorReflectionCode? {
        selectedErrorCodeRaw.flatMap(NFErrorReflectionCode.init(rawValue:))
    }

    var trigger: NFAttemptReflectionTrigger {
        NFAttemptReflectionTrigger(rawValue: triggerRaw) ?? .highConfidenceError
    }
}

enum NFAttemptReflectionPersistenceError: Error, Equatable, LocalizedError {
    case noteTooLong(maximum: Int)

    var errorDescription: String? {
        switch self {
        case let .noteTooLong(maximum):
            NFAppLocalization.localized(
                "Keep the reflection at \(maximum) characters or fewer. Nothing was saved or shortened.",
                locale: NFAppLocalization.preferredLocale,
                comment: "Attempt-reflection persistence validation when submitted text exceeds the maximum length."
            )
        }
    }
}

struct NFAuthoredReportDiagnostic: Codable, Sendable, Equatable {
    static let schemaVersion = 2

    let schemaVersion: Int
    let questionID: String
    let lab: String
    let style: String
    let prompt: String
    let context: String
    let choices: [String]
    let correctAnswer: String
    let acceptedAnswers: [String]
    let explanation: String
    let hint: String
    let decisiveStep: String
    let citationChunkIDs: [String]
    let authoritativeExercise: NFExercise
    let requestID: UUID
    let generatedAt: Date
    let route: String
    let routeReason: String
    let promptVersion: Int
    let validationVersion: Int
    let modelIdentifier: String
    let sourceDocumentIDs: [UUID]
    let generationSourceChunkIDs: [String]
    let repairCount: Int
    let cacheKey: String
    let isFallback: Bool
    let validationLevel: String
    let sourceSupport: String
    let validationNotes: [String]

    init(question: NFAuthoredQuestion, result: NFAuthoringResult) {
        schemaVersion = Self.schemaVersion
        questionID = question.id
        lab = question.lab.rawValue
        style = question.style.rawValue
        prompt = question.prompt
        context = question.context
        choices = question.choices
        correctAnswer = question.correctAnswer
        acceptedAnswers = question.acceptedAnswers
        explanation = question.explanation
        hint = question.hint
        decisiveStep = question.decisiveStep
        citationChunkIDs = question.citationChunkIDs
        authoritativeExercise = question.authoritativeExercise
        requestID = result.provenance.requestID
        generatedAt = result.provenance.generatedAt
        route = result.provenance.route.rawValue
        routeReason = result.provenance.routeReason
        promptVersion = result.provenance.promptVersion
        validationVersion = result.provenance.validationVersion
        modelIdentifier = result.provenance.modelIdentifier
        sourceDocumentIDs = result.provenance.sourceDocumentIDs
        generationSourceChunkIDs = result.provenance.sourceChunkIDs
        repairCount = result.provenance.repairCount
        cacheKey = result.provenance.cacheKey
        isFallback = result.provenance.isFallback
        validationLevel = result.validationStatus.level.rawValue
        sourceSupport = result.validationStatus.sourceSupport.rawValue
        validationNotes = result.validationNotes
    }

    func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(self)
    }

    static func decode(_ data: Data) -> NFAuthoredReportDiagnostic? {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(Self.self, from: data)
    }

    static func digest(of data: Data) -> String {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in data {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }
        return "fnv1a64:\(String(hash, radix: 16))"
    }
}

@Model
final class ItemReportRecord {
    static let maximumAuthoredDiagnosticPayloadBytes = 32 * 1_024

    var id: UUID = UUID()
    var itemID: String = ""
    var templateID: String = ""
    @Attribute(.allowsCloudEncryption)
    var prompt: String = ""
    @Attribute(.allowsCloudEncryption)
    var reason: String = ""
    @Attribute(.allowsCloudEncryption)
    var note: String = ""
    var createdAt: Date = Date()
    var status: String = "quarantined"
    var seed: UInt64 = 0
    var generatorVersion: Int = 0
    var provenanceSummary: String = "legacy deterministic item"
    var sourceIDsRaw: String = ""
    var sourceChunkIDsRaw: String = ""
    var assessmentDescriptorID: String?
    @Attribute(.allowsCloudEncryption)
    var diagnosticPayload: Data = Data()
    var diagnosticDigest: String = ""
    var diagnosticPayloadState: String = "notApplicable"

    init(item: MentalMathItem, reason: String, note: String) {
        itemID = item.id
        templateID = item.templateID
        prompt = item.prompt
        self.reason = reason
        self.note = note
        seed = item.seed
        generatorVersion = 1
    }

    init(
        exercise: NFExercise,
        assessmentDescriptorID: String? = nil,
        reason: String,
        note: String
    ) {
        itemID = exercise.id
        templateID = exercise.templateID
        prompt = exercise.prompt
        self.reason = reason
        self.note = note
        seed = exercise.seed
        generatorVersion = exercise.generatorVersion
        provenanceSummary = [
            exercise.provenance.contentTier.rawValue,
            exercise.provenance.generatorID,
            "validator-v\(exercise.provenance.validatorVersion)",
            exercise.provenance.contentDigest
        ].joined(separator: "|")
        sourceIDsRaw = exercise.provenance.sourceDocumentIDs.joined(separator: ",")
        self.assessmentDescriptorID = assessmentDescriptorID
    }

    init(question: NFAuthoredQuestion, result: NFAuthoringResult, reason: String, note: String) {
        itemID = Self.authoredItemIdentity(question: question, provenance: result.provenance)
        templateID = "ai.\(result.provenance.cacheKey).\(question.style.rawValue)"
        prompt = question.prompt
        self.reason = reason
        self.note = note
        seed = AdaptiveEngine.fnv1a64("\(result.provenance.cacheKey)|\(question.prompt)")
        generatorVersion = result.provenance.promptVersion
        provenanceSummary = [
            result.provenance.route.rawValue,
            result.provenance.modelIdentifier,
            "prompt-v\(result.provenance.promptVersion)",
            "validator-v\(result.provenance.validationVersion)",
            result.validationStatus.level.rawValue,
            result.provenance.requestID.uuidString
        ].joined(separator: "|")
        sourceIDsRaw = result.provenance.sourceDocumentIDs.map(\.uuidString).joined(separator: ",")
        sourceChunkIDsRaw = question.citationChunkIDs.joined(separator: ",")

        let diagnostic = NFAuthoredReportDiagnostic(question: question, result: result)
        if let encoded = try? diagnostic.encoded() {
            diagnosticDigest = NFAuthoredReportDiagnostic.digest(of: encoded)
            if encoded.count <= Self.maximumAuthoredDiagnosticPayloadBytes {
                diagnosticPayload = encoded
                diagnosticPayloadState = "available"
            } else {
                diagnosticPayloadState = "digestOnly"
            }
        } else {
            let identityData = Data(
                "\(itemID)|\(question.prompt)|\(question.correctAnswer)|\(provenanceSummary)".utf8
            )
            diagnosticDigest = NFAuthoredReportDiagnostic.digest(of: identityData)
            diagnosticPayloadState = "digestOnly"
        }
    }

    var authoredDiagnostic: NFAuthoredReportDiagnostic? {
        guard diagnosticPayloadState == "available",
              !diagnosticPayload.isEmpty,
              diagnosticPayload.count <= Self.maximumAuthoredDiagnosticPayloadBytes else {
            return nil
        }
        return NFAuthoredReportDiagnostic.decode(diagnosticPayload)
    }

    static func authoredItemIdentity(
        question: NFAuthoredQuestion,
        provenance: NFAIGenerationProvenance
    ) -> String {
        let contentIdentity = AdaptiveEngine.fnv1a64(
            "\(question.style.rawValue)|\(question.prompt)|\(question.correctAnswer)"
        )
        return "ai.\(provenance.cacheKey).\(String(contentIdentity, radix: 16))"
    }
}

@Model
final class SourceDocumentRecord {
    var id: UUID = UUID()
    var filename: String = ""
    var typeIdentifier: String = "public.data"
    var sizeBytes: Int64 = 0
    var importedAt: Date = Date()
    var indexState: String = "stored"
    var aiPolicyRaw: String = DocumentAIPolicy.onDeviceOnly.rawValue
    var pccExcerptConsentPolicyVersion: Int = 0
    var pccExcerptConsentDocumentIDRaw: String = ""
    var pccExcerptConsentedAt: Date?
    var syncPolicy: String = "localOnly"
    var localPath: String = ""
    var characterCount: Int = 0
    var chunkCount: Int = 0
    var extractionVersion: Int = 0
    var csvSelectedColumnIDsRaw: String = ""
    var indexError: String?
    var modifiedAt: Date = Date()

    init(filename: String, typeIdentifier: String, sizeBytes: Int64, localPath: String) {
        self.filename = filename
        self.typeIdentifier = typeIdentifier
        self.sizeBytes = sizeBytes
        self.localPath = localPath
    }

    var csvSelectedColumnIDs: [String] {
        csvSelectedColumnIDsRaw.split(separator: "\u{001F}").map(String.init)
    }
}

@Model
final class SourceChunkRecord {
    var id: String = ""
    var documentID: UUID = UUID()
    var documentVersion: Int = 1
    var sourceName: String = ""
    var page: Int?
    var lineStart: Int?
    var lineEnd: Int?
    var section: String?
    var characterStart: Int?
    var characterEnd: Int?
    var nearbyHeading: String?
    var language: String?
    var contentTypeTagsRaw: String = ""
    var text: String = ""
    var contentHash: String = ""
    var ordinal: Int = 0
    var createdAt: Date = Date()

    var contentTypeTags: [String] {
        contentTypeTagsRaw.split(separator: "\u{001F}").map(String.init)
    }

    init(chunk: NFSourceChunk) {
        id = chunk.id
        documentID = chunk.documentID
        documentVersion = chunk.documentVersion
        sourceName = chunk.sourceName
        page = chunk.locator.page
        lineStart = chunk.locator.lineStart
        lineEnd = chunk.locator.lineEnd
        section = chunk.locator.section
        characterStart = chunk.characterStart
        characterEnd = chunk.characterEnd
        nearbyHeading = chunk.nearbyHeading
        language = chunk.language
        contentTypeTagsRaw = chunk.contentTypeTags.joined(separator: "\u{001F}")
        text = chunk.text
        contentHash = chunk.contentHash
        ordinal = chunk.ordinal
    }

    var snapshot: NFSourceChunk {
        NFSourceChunk(
            id: id,
            documentID: documentID,
            documentVersion: documentVersion,
            sourceName: sourceName,
            locator: NFSourceLocator(page: page, lineStart: lineStart, lineEnd: lineEnd, section: section),
            text: text,
            contentHash: contentHash,
            ordinal: ordinal,
            characterStart: characterStart,
            characterEnd: characterEnd,
            nearbyHeading: nearbyHeading,
            language: language,
            contentTypeTags: contentTypeTags
        )
    }
}

@Model
final class AIGenerationRecord {
    static let defaultPayloadTTL: TimeInterval = 7 * 24 * 60 * 60
    static let maximumPersistedPayloadCount = 64
    static let maximumPersistedPayloadBytes: Int64 = 32 * 1_024 * 1_024

    var id: UUID = UUID()
    var createdAt: Date = Date()
    var capabilityRaw: String = ""
    var labRaw: String = ""
    var fieldRaw: String = ""
    var topic: String = ""
    var routeRaw: String = NFAIRoute.deterministicFallback.rawValue
    var routeReason: String = ""
    var promptVersion: Int = 0
    var validationVersion: Int = 0
    var modelIdentifier: String = ""
    var sourceDocumentIDsRaw: String = ""
    var sourceChunkIDsRaw: String = ""
    var repairCount: Int = 0
    var cacheKey: String = ""
    var isFallback: Bool = false
    var questionCount: Int = 0
    var resultPayload: Data = Data()
    var payloadExpiresAt: Date = Date.distantPast

    init(
        request: NFAuthoringRequest,
        result: NFAuthoringResult,
        payloadTTL: TimeInterval = AIGenerationRecord.defaultPayloadTTL
    ) throws {
        id = result.provenance.requestID
        createdAt = result.provenance.generatedAt
        capabilityRaw = request.capability.rawValue
        labRaw = request.lab.rawValue
        fieldRaw = request.field.rawValue
        topic = request.customTopic
        routeRaw = result.provenance.route.rawValue
        routeReason = result.provenance.routeReason
        promptVersion = result.provenance.promptVersion
        validationVersion = result.provenance.validationVersion
        modelIdentifier = result.provenance.modelIdentifier
        sourceDocumentIDsRaw = result.provenance.sourceDocumentIDs.map(\.uuidString).joined(separator: ",")
        sourceChunkIDsRaw = result.provenance.sourceChunkIDs.joined(separator: ",")
        repairCount = result.provenance.repairCount
        cacheKey = result.provenance.cacheKey
        isFallback = result.provenance.isFallback
        questionCount = result.questions.count
        resultPayload = try JSONEncoder().encode(result)
        payloadExpiresAt = result.provenance.generatedAt.addingTimeInterval(max(0, payloadTTL))
    }

    func recoverableResult(at date: Date = Date()) -> NFAuthoringResult? {
        guard !resultPayload.isEmpty, payloadExpiresAt > date,
              let result = try? JSONDecoder().decode(NFAuthoringResult.self, from: resultPayload),
              result.provenance.requestID == id,
              result.provenance.cacheKey == cacheKey,
              result.provenance.promptVersion == promptVersion,
              promptVersion == NFAuthoringRequest.promptVersion,
              result.provenance.validationVersion == validationVersion,
              validationVersion == NFAuthoringEngine.validationVersion,
              (result.provenance.route != .onDevice
                  || (result.validationStatus.level == .deterministicKeyWithModelContext
                      && result.questions.allSatisfy(\.hasValidBoundedPresentationLayer))),
              result.questions.count == questionCount,
              result.questions.allSatisfy({ question in
                  let provenanceCitations = Set(result.provenance.sourceChunkIDs)
                  return question.hasValidResponseSchema
                      && question.evidenceClass == .documentPractice
                      && Set(question.citationChunkIDs).isSubset(of: provenanceCitations)
                      && (provenanceCitations.isEmpty || !question.citationChunkIDs.isEmpty)
              }) else {
            return nil
        }
        return result
    }

    func discardExpiredOrInvalidPayload(at date: Date = Date()) -> Bool {
        guard !resultPayload.isEmpty else { return false }
        guard payloadExpiresAt <= date || recoverableResult(at: date) == nil else { return false }
        resultPayload = Data()
        return true
    }

    func discardPayload() {
        resultPayload = Data()
    }
}

@Model
final class WeeklyTransferStateRecord {
    var id: String = "weekly-transfer-state"
    var completedMissionIDsRaw: String = ""
    var deferredUntilPayload: Data = Data()
    var modifiedAt: Date = Date()

    init(state: NFWeeklyTransferState = NFWeeklyTransferState()) {
        apply(state)
    }

    private struct StatePayload: Codable {
        let deferredUntilByMissionID: [String: Date]
        let pinnedMissionByWeekKey: [String: NFWeeklyTransferMission]
    }

    var snapshot: NFWeeklyTransferState {
        let completed = Set(completedMissionIDsRaw.split(separator: ",").map(String.init))
        let decoder = JSONDecoder()
        let payload = try? decoder.decode(StatePayload.self, from: deferredUntilPayload)
        // Version-one stores encoded only the deferral dictionary. Decode it
        // as a fallback so adding pinned missions is migration-safe.
        let legacyDeferrals = (try? decoder.decode([String: Date].self, from: deferredUntilPayload)) ?? [:]
        return NFWeeklyTransferState(
            completedMissionIDs: completed,
            deferredUntilByMissionID: payload?.deferredUntilByMissionID ?? legacyDeferrals,
            pinnedMissionByWeekKey: payload?.pinnedMissionByWeekKey ?? [:]
        )
    }

    func apply(
        _ state: NFWeeklyTransferState,
        modifiedAt: Date = Date()
    ) {
        completedMissionIDsRaw = state.completedMissionIDs.sorted().joined(separator: ",")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        deferredUntilPayload = (try? encoder.encode(StatePayload(
            deferredUntilByMissionID: state.deferredUntilByMissionID,
            pinnedMissionByWeekKey: state.pinnedMissionByWeekKey
        ))) ?? Data()
        self.modifiedAt = modifiedAt
    }
}

@Model
final class ReassessmentStateRecord {
    var id: String = "reassessment-state"
    var completedCycle: Int = 0
    var activeDayAnchor: Date?
    var dueAt: Date?
    var deferredUntil: Date?
    var targetBlockRaw: String?
    var lastCompletedAt: Date?
    var lastCompletedBlockRaw: String?
    var modifiedAt: Date = Date()

    init(state: NFReassessmentState = NFReassessmentState()) {
        apply(state)
    }

    var snapshot: NFReassessmentState {
        NFReassessmentState(
            completedCycle: completedCycle,
            activeDayAnchor: activeDayAnchor,
            dueAt: dueAt,
            deferredUntil: deferredUntil,
            targetBlock: targetBlockRaw.flatMap(NFAssessmentBlockKind.init(rawValue:)),
            lastCompletedAt: lastCompletedAt,
            lastCompletedBlock: lastCompletedBlockRaw.flatMap(NFAssessmentBlockKind.init(rawValue:))
        )
    }

    func apply(_ state: NFReassessmentState, modifiedAt: Date = Date()) {
        completedCycle = state.completedCycle
        activeDayAnchor = state.activeDayAnchor
        dueAt = state.dueAt
        deferredUntil = state.deferredUntil
        targetBlockRaw = state.targetBlock?.rawValue
        lastCompletedAt = state.lastCompletedAt
        lastCompletedBlockRaw = state.lastCompletedBlock?.rawValue
        self.modifiedAt = modifiedAt
    }
}

@Model
final class SessionCheckpointRecord {
    var id: UUID = UUID()
    var sessionID: UUID = UUID()
    var labRaw: String = TrainingLab.mentalMath.rawValue
    var sourceRaw: String = SessionSource.focused.rawValue
    var seed: UInt64 = 0
    var currentIndex: Int = 0
    var itemCount: Int = 0
    @Attribute(.allowsCloudEncryption)
    var response: String = ""
    @Attribute(.allowsCloudEncryption)
    var scratchpad: String = ""
    @Attribute(.allowsCloudEncryption)
    var resultsRaw: String = ""
    @Attribute(.allowsCloudEncryption)
    var creditsRaw: String = ""
    var assessmentDescriptorIDsRaw: String = ""
    var assessmentEventsRaw: String = ""
    var evidenceClassRaw: String = EvidenceClass.practice.rawValue
    var updatedAt: Date = Date()
    var isComplete: Bool = false
    var planID: String?
    var planBlockID: String?
    @Attribute(.allowsCloudEncryption)
    var recommendationRationale: String?
    var hasCommittedCurrentItem: Bool = false
    var assessmentBlockRaw: String?
    var assessmentCycle: Int?
    var activeDurationSeconds: Double = 0
    var assessmentStopReasonRaw: String?
    var pendingReflectionAttemptID: UUID?
    var reflectionTriggerRaw: String?
    var selectedReflectionCodeRaw: String?
    @Attribute(.allowsCloudEncryption)
    var reflectionNote: String?

    init(
        sessionID: UUID,
        lab: TrainingLab,
        source: SessionSource,
        seed: UInt64,
        currentIndex: Int,
        itemCount: Int,
        response: String,
        scratchpad: String,
        results: [Bool],
        credits: [Double] = [],
        assessmentDescriptorIDs: [String] = [],
        assessmentEvents: [String] = [],
        evidenceClass: EvidenceClass,
        planID: String? = nil,
        planBlockID: String? = nil,
        recommendationRationale: String? = nil,
        assessmentBlock: NFAssessmentBlockKind? = nil,
        assessmentCycle: Int? = nil,
        activeDurationSeconds: TimeInterval = 0,
        assessmentStopReason: NFAssessmentStopReason? = nil,
        pendingReflectionAttemptID: UUID? = nil,
        reflectionTrigger: NFAttemptReflectionTrigger? = nil,
        selectedReflectionCode: NFErrorReflectionCode? = nil,
        reflectionNote: String? = nil,
        hasCommittedCurrentItem: Bool = false,
        isComplete: Bool = false
    ) {
        self.sessionID = sessionID
        labRaw = lab.rawValue
        sourceRaw = source.rawValue
        self.seed = seed
        self.currentIndex = currentIndex
        self.itemCount = itemCount
        self.response = response
        self.scratchpad = scratchpad
        resultsRaw = results.map { $0 ? "1" : "0" }.joined(separator: ",")
        creditsRaw = credits.map(Self.encodeCredit).joined(separator: ",")
        assessmentDescriptorIDsRaw = assessmentDescriptorIDs.joined(separator: ",")
        assessmentEventsRaw = assessmentEvents.joined(separator: ",")
        evidenceClassRaw = evidenceClass.rawValue
        self.planID = planID
        self.planBlockID = planBlockID
        self.recommendationRationale = recommendationRationale
        assessmentBlockRaw = assessmentBlock?.rawValue
        self.assessmentCycle = assessmentCycle
        self.activeDurationSeconds = max(0, activeDurationSeconds)
        assessmentStopReasonRaw = assessmentStopReason?.rawValue
        self.pendingReflectionAttemptID = pendingReflectionAttemptID
        reflectionTriggerRaw = reflectionTrigger?.rawValue
        selectedReflectionCodeRaw = selectedReflectionCode?.rawValue
        self.reflectionNote = reflectionNote
        self.hasCommittedCurrentItem = hasCommittedCurrentItem
        self.isComplete = isComplete
    }

    private static func encodeCredit(_ credit: Double) -> String {
        String(format: "%.17g", min(1, max(0, credit)))
    }
}

@Model
final class DailyPlanRecord {
    var id: String = ""
    var profileID: UUID = UUID()
    var localDayKey: String = ""
    var policyVersion: Int = 0
    @Attribute(.allowsCloudEncryption)
    var payload: Data = Data()
    var createdAt: Date = Date()
    var timeZoneIdentifier: String = TimeZone.current.identifier
    var utcOffsetSeconds: Int = TimeZone.current.secondsFromGMT()
    var dayBoundaryHour: Int = 4
    var boundaryStart: Date = Date()
    var nextBoundaryAt: Date = Date()
    var travelPreservedUntil: Date?

    init(plan: NFCanonicalDailyPlan, boundaryContext: NFPlanBoundaryContext? = nil) throws {
        let boundaryContext = boundaryContext ?? .make(at: Date(), dayBoundaryHour: 4)
        id = plan.id
        profileID = plan.profileID
        localDayKey = plan.localDayKey
        policyVersion = plan.policyVersion
        payload = try JSONEncoder().encode(plan)
        createdAt = boundaryContext.evaluatedAt
        timeZoneIdentifier = boundaryContext.timeZoneIdentifier
        utcOffsetSeconds = boundaryContext.utcOffsetSeconds
        dayBoundaryHour = boundaryContext.dayBoundaryHour
        boundaryStart = boundaryContext.boundaryStart
        nextBoundaryAt = boundaryContext.nextBoundary
    }

    var snapshot: NFCanonicalDailyPlan? { try? JSONDecoder().decode(NFCanonicalDailyPlan.self, from: payload) }

    func applyTravelContext(_ context: NFPlanBoundaryContext) {
        timeZoneIdentifier = context.timeZoneIdentifier
        utcOffsetSeconds = context.utcOffsetSeconds
        dayBoundaryHour = context.dayBoundaryHour
        boundaryStart = context.boundaryStart
        nextBoundaryAt = context.nextBoundary
        travelPreservedUntil = NFPlanTravelPolicy.preservationDeadline(
            planCreatedAt: createdAt,
            newContext: context
        )
    }

    /// Keeps an already materialized learner-day plan alive when the learner
    /// changes the clock boundary in Settings. The plan payload and identity
    /// stay immutable; only its lookup window moves to the newly chosen
    /// boundary so a second same-day plan cannot be created.
    func preserveAcrossPreferenceBoundaryChange(_ context: NFPlanBoundaryContext) {
        timeZoneIdentifier = context.timeZoneIdentifier
        utcOffsetSeconds = context.utcOffsetSeconds
        dayBoundaryHour = context.dayBoundaryHour
        boundaryStart = context.boundaryStart
        nextBoundaryAt = context.nextBoundary
        travelPreservedUntil = context.nextBoundary
    }
}

@MainActor
@Observable
final class AppStore {
    let context: ModelContext
    let nextDayEnhancementCache: NFNextDayEnhancementCache
    private let offlineQuestionRotation: NFOfflineQuestionRotation
    private let documentStorageRootURLOverride: URL?
    private let adaptivePlanHistoryRepository: NFAdaptivePlanHistoryRepository
    private(set) var profile: UserProfileRecord?
    private(set) var attempts: [AttemptRecord] = []
    private(set) var attemptReflections: [AttemptReflectionRecord] = []
    private(set) var documents: [SourceDocumentRecord] = []
    private(set) var itemReports: [ItemReportRecord] = []
    private(set) var sourceChunks: [SourceChunkRecord] = []
    private(set) var aiGenerations: [AIGenerationRecord] = []
    private(set) var sessionCheckpoints: [SessionCheckpointRecord] = []
    private(set) var dailyPlans: [DailyPlanRecord] = []
    private(set) var weeklyTransferStateRecord: WeeklyTransferStateRecord?
    private(set) var reassessmentStateRecord: ReassessmentStateRecord?
    private(set) var inputCalibrations: [InputCalibrationRecord] = []
    private(set) var progressAnnotations: [ProgressAnnotationRecord] = []
    private(set) var adaptivePlanHistory: [NFAdaptivePlanChangeRecord] = []
    private(set) var pendingAttemptRecords: [AttemptRecord] = []
    private(set) var readiness: Readiness = .normal {
        didSet {
            if oldValue != readiness { nextDayEnhancementCache.removeAll() }
        }
    }
    var selectedDestination: AppDestination = .today {
        didSet {
            guard !isApplyingConfirmedDestination,
                  selectedDestination != oldValue,
                  activeDirtyEditor != nil else { return }
            pendingAppIntentAfterDirtyEditor = nil
            pendingExternalRouteAfterDirtyEditor = nil
            pendingDestinationAfterDirtyEditor = selectedDestination
            isApplyingConfirmedDestination = true
            selectedDestination = oldValue
            isApplyingConfirmedDestination = false
        }
    }
    private(set) var pendingSettingsSubroute: NFSettingsSubroute?
    private(set) var activeDirtyEditor: NFDirtyEditorRegistration?
    private(set) var pendingDestinationAfterDirtyEditor: AppDestination?
    private(set) var pendingExternalRouteAfterDirtyEditor: NFExternalRoute?
    private(set) var pendingAppIntentAfterDirtyEditor: NFDeferredAppIntent?
    private(set) var lastDiscardedDirtyEditorID: UUID?
    private var isApplyingConfirmedDestination = false
    private var pendingSettingsSubrouteRequiresNavigationConfirmation = false
    var activeSessionRequest: SessionRequest?
    var shouldPresentDocumentImporter = false
    var shouldOpenTodayPlan = false
    var shouldOpenSourceReviews = false
    var shouldOpenBaseline = false
    var shouldOpenAIStudio = false
    var requestedLibraryDocumentID: UUID?
    var requestedSourceChunkID: String?
    var requestedSourceReviewID: UUID?
    var shouldOpenCompletedTodayReview = false
    var lastErrorMessage: String?
    var notice: AppNotice?
    private(set) var persistenceRecoveryPackage: NFStoreRecoveryPackage?

    func requestSettingsSubroute(_ subroute: NFSettingsSubroute) {
        pendingSettingsSubroute = subroute
        if activeDirtyEditor != nil {
            pendingAppIntentAfterDirtyEditor = nil
            pendingExternalRouteAfterDirtyEditor = nil
            pendingDestinationAfterDirtyEditor = .settings
            pendingSettingsSubrouteRequiresNavigationConfirmation = true
            return
        }
        pendingSettingsSubrouteRequiresNavigationConfirmation = false
        selectedDestination = .settings
    }

    /// Defers the complete external-route transaction while an editor is
    /// dirty. Payload fields must be committed only after the learner saves or
    /// explicitly discards, including when the route targets the section that
    /// is already selected.
    @discardableResult
    func deferExternalRouteIfDirty(
        _ route: NFExternalRoute,
        destination: AppDestination
    ) -> Bool {
        deferAppIntentIfDirty(
            .externalRoute(route),
            destination: destination
        )
    }

    @discardableResult
    func deferAppIntentIfDirty(
        _ intent: NFDeferredAppIntent,
        destination: AppDestination
    ) -> Bool {
        guard activeDirtyEditor != nil else { return false }
        pendingAppIntentAfterDirtyEditor = intent
        if case let .externalRoute(route) = intent {
            pendingExternalRouteAfterDirtyEditor = route
        } else {
            pendingExternalRouteAfterDirtyEditor = nil
        }
        pendingDestinationAfterDirtyEditor = destination
        if pendingSettingsSubrouteRequiresNavigationConfirmation {
            pendingSettingsSubroute = nil
            pendingSettingsSubrouteRequiresNavigationConfirmation = false
        }
        return true
    }

    func acknowledgeSettingsSubroute(_ subroute: NFSettingsSubroute) {
        guard pendingSettingsSubroute == subroute else { return }
        pendingSettingsSubroute = nil
        pendingSettingsSubrouteRequiresNavigationConfirmation = false
    }

    func updateDirtyEditor(
        id: UUID,
        title: String,
        isDirty: Bool
    ) {
        if isDirty {
            activeDirtyEditor = NFDirtyEditorRegistration(id: id, title: title)
        } else if activeDirtyEditor?.id == id {
            finishDirtyEditorRegistration(id: id)
        }
    }

    func clearDirtyEditor(id: UUID) {
        finishDirtyEditorRegistration(id: id)
    }

    private func finishDirtyEditorRegistration(id: UUID) {
        guard activeDirtyEditor?.id == id else { return }
        let appIntent = pendingAppIntentAfterDirtyEditor
        let destination = pendingDestinationAfterDirtyEditor
        activeDirtyEditor = nil
        pendingDestinationAfterDirtyEditor = nil
        pendingExternalRouteAfterDirtyEditor = nil
        pendingAppIntentAfterDirtyEditor = nil
        pendingSettingsSubrouteRequiresNavigationConfirmation = false
        if let appIntent {
            performDeferredAppIntent(appIntent)
            return
        }
        guard let destination else { return }
        isApplyingConfirmedDestination = true
        selectedDestination = destination
        isApplyingConfirmedDestination = false
    }

    func cancelPendingDestinationChange() {
        pendingDestinationAfterDirtyEditor = nil
        pendingExternalRouteAfterDirtyEditor = nil
        pendingAppIntentAfterDirtyEditor = nil
        if pendingSettingsSubrouteRequiresNavigationConfirmation {
            pendingSettingsSubroute = nil
            pendingSettingsSubrouteRequiresNavigationConfirmation = false
        }
    }

    func discardDirtyEditorAndNavigate() {
        guard let editorID = activeDirtyEditor?.id else { return }
        let appIntent = pendingAppIntentAfterDirtyEditor
        let destination = pendingDestinationAfterDirtyEditor
        guard appIntent != nil || destination != nil else { return }
        lastDiscardedDirtyEditorID = editorID
        activeDirtyEditor = nil
        pendingDestinationAfterDirtyEditor = nil
        pendingExternalRouteAfterDirtyEditor = nil
        pendingAppIntentAfterDirtyEditor = nil
        pendingSettingsSubrouteRequiresNavigationConfirmation = false
        if let appIntent {
            performDeferredAppIntent(appIntent)
            return
        }
        guard let destination else { return }
        isApplyingConfirmedDestination = true
        selectedDestination = destination
        isApplyingConfirmedDestination = false
    }

    private func performDeferredAppIntent(_ intent: NFDeferredAppIntent) {
        switch intent {
        case let .externalRoute(route):
            NFExternalRouteRouter.apply(route, to: self)
        case .todayPlan:
            requestTodayPlan()
        case let .reviewsDue(date, calendar):
            _ = requestReviewsDue(at: date, calendar: calendar)
        case .sourceReviews:
            requestSourceReviews()
        case .documentImport:
            requestDocumentImport()
        case .sourceReviewDocumentImport:
            requestSourceReviewDocumentImport()
        case .questionWriterCallback:
            requestAIStudioForPendingShortcutCallback()
        case let .mentalMathPractice(requestedMinutes, preferredKind):
            _ = requestFocusedMentalMathPractice(
                requestedMinutes: requestedMinutes,
                preferredMentalMathKind: preferredKind
            )
        }
    }

    func dirtyEditorWasDiscarded(id: UUID) -> Bool {
        lastDiscardedDirtyEditorID == id
    }

    init(
        context: ModelContext,
        nextDayEnhancementCache: NFNextDayEnhancementCache = .shared,
        documentStorageRootURL: URL? = nil,
        adaptivePlanHistoryRepository: NFAdaptivePlanHistoryRepository = .processDefault(),
        offlineQuestionRotation: NFOfflineQuestionRotation = NFOfflineQuestionRotation(
            store: NFUserDefaultsOfflineQuestionRotationStateStore()
        )
    ) {
        self.context = context
        self.nextDayEnhancementCache = nextDayEnhancementCache
        self.offlineQuestionRotation = offlineQuestionRotation
        documentStorageRootURLOverride = documentStorageRootURL
        self.adaptivePlanHistoryRepository = adaptivePlanHistoryRepository
        adaptivePlanHistory = (try? adaptivePlanHistoryRepository.load()) ?? []
        reload()
        _ = refreshReassessmentSchedule()
    }

    private func managedDocumentFolderURL(fileManager: FileManager = .default) throws -> URL {
        if let documentStorageRootURLOverride {
            return documentStorageRootURLOverride.standardizedFileURL
        }
        let support = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        return support
            .appending(path: "NeuroForge/Documents", directoryHint: .isDirectory)
            .standardizedFileURL
    }

    func enterPersistenceRecoveryMode(_ package: NFStoreRecoveryPackage) {
        persistenceRecoveryPackage = package
        activeSessionRequest = nil
    }

    var isOnboardingComplete: Bool {
        guard let profile else { return false }
        return profile.onboardingVersion >= 1
    }

    var profileSnapshot: ProfileSnapshot {
        profile?.snapshot ?? ProfileSnapshot(
            id: UUID(uuidString: "A6B79B3A-78C8-41D1-8761-3A01F0039F53")!,
            stage: .undisclosed,
            fields: [.general],
            goals: [.mentalMath, .dataReasoning],
            dailyDuration: 10,
            timingMode: .adaptive,
            aiMode: .automatic,
            iCloudEnabled: false
        )
    }

    var reversedAdaptivePlanChangeIDs: Set<UUID> {
        Set(adaptivePlanHistory.compactMap(\.reversesChangeID))
    }

    func canUndoAdaptivePlanChange(_ change: NFAdaptivePlanChangeRecord) -> Bool {
        guard change.profileID == profileSnapshot.id,
              change.undoPayload != nil,
              !reversedAdaptivePlanChangeIDs.contains(change.id) else {
            return false
        }
        switch change.undoPayload {
        case let .dailyPlan(planID, expectedCurrentPayload, _):
            guard let record = dailyPlans.first(where: { $0.id == planID }),
                  record.payload == expectedCurrentPayload else { return false }
            return !attempts.contains(where: { $0.planID == planID && $0.submittedAt >= change.occurredAt })
                && !sessionCheckpoints.contains(where: { $0.planID == planID && $0.updatedAt >= change.occurredAt })
                && activeSessionRequest?.planID != planID
        case let .readiness(_, expectedCurrent):
            return readiness == expectedCurrent && activeSessionRequest == nil
        case nil:
            return false
        }
    }

    @discardableResult
    func undoAdaptivePlanChange(_ changeID: UUID) -> Bool {
        guard let change = adaptivePlanHistory.first(where: { $0.id == changeID }),
              canUndoAdaptivePlanChange(change),
              let undoPayload = change.undoPayload else {
            notice = AppNotice(
                title: NFAppLocalization.localized(
                    "Undo unavailable",
                    locale: NFAppLocalization.preferredLocale,
                    comment: "Adaptive-plan history undo failure title."
                ),
                message: NFAppLocalization.localized(
                    "This change is already in use, has already been undone, or no longer matches the current plan.",
                    locale: NFAppLocalization.preferredLocale,
                    comment: "Adaptive-plan history undo failure explanation."
                )
            )
            return false
        }

        do {
            let restoredState: String
            switch undoPayload {
            case let .dailyPlan(planID, _, previousPayload):
                guard let record = dailyPlans.first(where: { $0.id == planID }) else { return false }
                record.payload = previousPayload
                try context.save()
                reload()
                publishWidgetSnapshot()
                restoredState = change.previousState ?? NFAppLocalization.localized(
                    "Previous daily plan",
                    locale: NFAppLocalization.preferredLocale,
                    comment: "Fallback state name after undoing an adaptive plan change."
                )
            case let .readiness(previous, _):
                readiness = previous
                restoredState = previous.title
            }

            let undoRecord = NFAdaptivePlanChangeRecord(
                profileID: profileSnapshot.id,
                kind: .undo,
                title: NFAppLocalization.localized(
                    "Adaptive change undone",
                    locale: NFAppLocalization.preferredLocale,
                    comment: "Adaptive-plan history undo event title."
                ),
                previousState: change.newState,
                newState: restoredState,
                reason: NFAppLocalization.localized(
                    "You restored the last safe state before this change.",
                    locale: NFAppLocalization.preferredLocale,
                    comment: "Adaptive-plan history undo event explanation."
                ),
                reversesChangeID: change.id
            )
            try appendAdaptivePlanHistory(undoRecord)
            notice = AppNotice(
                title: NFAppLocalization.localized(
                    "Change undone",
                    locale: NFAppLocalization.preferredLocale,
                    comment: "Adaptive-plan undo confirmation title."
                ),
                message: NFAppLocalization.localized(
                    "The previous safe plan state has been restored.",
                    locale: NFAppLocalization.preferredLocale,
                    comment: "Adaptive-plan undo confirmation message."
                )
            )
            return true
        } catch {
            context.rollback()
            reload()
            lastErrorMessage = (error as? LocalizedError)?.errorDescription
                ?? NFAppLocalization.localized(
                    "The adaptive change could not be undone.",
                    locale: NFAppLocalization.preferredLocale,
                    comment: "Adaptive-plan undo persistence error."
                )
            return false
        }
    }

    func appendAdaptivePlanHistory(_ record: NFAdaptivePlanChangeRecord) throws {
        adaptivePlanHistory = try adaptivePlanHistoryRepository.appending(record, to: adaptivePlanHistory)
    }

    func replaceAdaptivePlanHistoryForRestore(_ records: [NFAdaptivePlanChangeRecord]) throws {
        try adaptivePlanHistoryRepository.replacingHistory(with: records)
        adaptivePlanHistory = try adaptivePlanHistoryRepository.load()
    }

    private func recordAdaptivePlanChange(_ record: NFAdaptivePlanChangeRecord) {
        do {
            try appendAdaptivePlanHistory(record)
        } catch {
            lastErrorMessage = (error as? LocalizedError)?.errorDescription
                ?? NFAppLocalization.localized(
                    "The adaptive-plan explanation could not be saved.",
                    locale: NFAppLocalization.preferredLocale,
                    comment: "Adaptive-plan audit-log persistence error."
                )
        }
    }

    var todayPlan: DailyPlan {
        dailyPlan(at: Date(), calendar: .current)
    }

    func dailyPlan(at date: Date, calendar: Calendar) -> DailyPlan {
        let snapshot = dailySchedulingSnapshot(at: date, calendar: calendar)
        let boundaryContext = NFPlanBoundaryContext.make(
            at: date,
            dayBoundaryHour: snapshot.dayBoundaryHour,
            calendar: calendar
        )
        let dayKey = NFDailyScheduler.localDayKey(
            for: snapshot.date,
            dayBoundaryHour: snapshot.dayBoundaryHour,
            calendar: calendar
        )
        let contextMatches: (DailyPlanRecord) -> Bool = { record in
            record.timeZoneIdentifier == boundaryContext.timeZoneIdentifier
                && record.utcOffsetSeconds == boundaryContext.utcOffsetSeconds
                && record.dayBoundaryHour == boundaryContext.dayBoundaryHour
        }
        let candidates = dailyPlans.filter {
            $0.profileID == snapshot.profile.id
                && $0.policyVersion == NFDailyScheduler.policyVersion
                && $0.dayBoundaryHour == boundaryContext.dayBoundaryHour
        }
        let exact = candidates
            .filter {
                contextMatches($0)
                    && ($0.localDayKey == dayKey || ($0.travelPreservedUntil ?? .distantPast) > date)
            }
            .min(by: { $0.createdAt < $1.createdAt })
        let travelCandidate = exact == nil ? candidates
            .filter {
                NFPlanTravelPolicy.canPreserve(
                    planCreatedAt: $0.createdAt,
                    at: date,
                    storedTimeZoneIdentifier: $0.timeZoneIdentifier,
                    storedUTCOffsetSeconds: $0.utcOffsetSeconds,
                    newContext: boundaryContext
                )
            }
            .max(by: { $0.createdAt < $1.createdAt }) : nil

        if let travelCandidate {
            travelCandidate.applyTravelContext(boundaryContext)
            try? context.save()
        }
        let existingRecord = exact ?? travelCandidate
        let existingSnapshot = existingRecord?.snapshot
        let canonical: NFCanonicalDailyPlan
        if let existingRecord, let existingSnapshot, existingRecord.localDayKey != dayKey {
            canonical = existingSnapshot
        } else {
            canonical = NFDailyScheduler.canonicalPlan(
                for: snapshot,
                existingPlan: existingSnapshot,
                calendar: calendar
            )
        }
        if !dailyPlans.contains(where: { $0.id == canonical.id }),
           let record = try? DailyPlanRecord(plan: canonical, boundaryContext: boundaryContext) {
            context.insert(record)
            if (try? context.save()) != nil {
                dailyPlans.insert(record, at: 0)
                recordAdaptivePlanChange(NFAdaptivePlanChangeRecord(
                    profileID: canonical.profileID,
                    occurredAt: boundaryContext.evaluatedAt,
                    kind: .planMaterialized,
                    title: NFAppLocalization.localized(
                        "Today’s plan created",
                        locale: NFAppLocalization.preferredLocale,
                        comment: "Adaptive-plan history event title."
                    ),
                    newState: adaptivePlanSummary(
                        blockCount: canonical.blocks.count,
                        minutes: canonical.scheduledMinutes
                    ),
                    reason: NFAppLocalization.localized(
                        "Built once for this learner day from your goals, due reviews, accessibility choices, readiness, and recent evidence.",
                        locale: NFAppLocalization.preferredLocale,
                        comment: "Adaptive-plan history plan-materialization explanation."
                    )
                ))
            }
        }
        return canonical.domainPlan
    }

    private func adaptivePlanSummary(blockCount: Int, minutes: Int) -> String {
        let blockText = blockCount == 1
            ? NFAppLocalization.localized("1 block", locale: NFAppLocalization.preferredLocale, comment: "Singular adaptive-plan block count.")
            : NFAppLocalization.localized("\(blockCount) blocks", locale: NFAppLocalization.preferredLocale, comment: "Plural adaptive-plan block count; the placeholder is the count.")
        let minuteText = NFAppLocalization.formattedMinutes(minutes)
        return "\(blockText) · \(minuteText)"
    }

    func retentionReviewTargets(
        forPlanID planID: String?,
        blockID: String?,
        fallbackItemIDs: [String],
        fallbackSeed: UInt64
    ) -> [NFRetentionReviewTarget] {
        if let planID,
           let blockID,
           let block = dailyPlans.lazy.compactMap(\.snapshot).first(where: { $0.id == planID })?
            .blocks.first(where: { $0.id == blockID }),
           !block.retentionTargets.isEmpty {
            return block.retentionTargets
        }
        return fallbackItemIDs.enumerated().map { index, memoryItemID in
            .legacy(
                memoryItemID: memoryItemID,
                fallbackSeed: fallbackSeed ^ NFStableDeterminism.hash64(
                    "legacy-session-retention|\(planID ?? "none")|\(blockID ?? "none")|\(index)|\(memoryItemID)"
                )
            )
        }
    }

    /// Readiness is a presentation/load override, never a parallel plan
    /// namespace. Before work starts, an explicit readiness change replaces
    /// the sole current-day plan. Once any attempt or checkpoint exists, the
    /// immutable canonical plan is preserved and low readiness is enforced at
    /// the session boundary by disabling timed execution.
    func updateReadiness(
        _ newValue: Readiness,
        at date: Date = .now,
        calendar: Calendar = .current
    ) {
        guard newValue != readiness else { return }
        let previousReadiness = readiness
        let boundaryHour = profileSnapshot.dayBoundaryHour
        let dayKey = NFDailyScheduler.localDayKey(
            for: date,
            dayBoundaryHour: boundaryHour,
            calendar: calendar
        )
        let profileID = profileSnapshot.id
        let currentRecords = dailyPlans.filter { record in
            record.profileID == profileID
                && record.dayBoundaryHour == boundaryHour
                && (record.localDayKey == dayKey || (record.travelPreservedUntil ?? .distantPast) > date)
        }
        let currentPlanIDs = Set(currentRecords.map(\.id))
        let hasStarted = attempts.contains { attempt in
            attempt.planID.map(currentPlanIDs.contains) == true
        } || sessionCheckpoints.contains { checkpoint in
            checkpoint.planID.map(currentPlanIDs.contains) == true
        } || activeSessionRequest?.planID.map(currentPlanIDs.contains) == true

        guard !currentRecords.isEmpty, !hasStarted else {
            readiness = newValue
            recordAdaptivePlanChange(NFAdaptivePlanChangeRecord(
                profileID: profileSnapshot.id,
                occurredAt: date,
                kind: .readinessChanged,
                title: NFAppLocalization.localized(
                    "Readiness changed",
                    locale: NFAppLocalization.preferredLocale,
                    comment: "Adaptive-plan history readiness event title."
                ),
                previousState: previousReadiness.title,
                newState: newValue.title,
                reason: hasStarted
                    ? NFAppLocalization.localized(
                        "Today’s plan was already in progress, so its blocks stayed fixed. Low readiness disables timing and lets you shorten the remaining session.",
                        locale: NFAppLocalization.preferredLocale,
                        comment: "Adaptive-plan history readiness explanation after a session starts."
                    )
                    : NFAppLocalization.localized(
                        "No plan had been committed yet, so readiness will shape the next plan’s pacing and length.",
                        locale: NFAppLocalization.preferredLocale,
                        comment: "Adaptive-plan history readiness explanation before a daily plan exists."
                    ),
                undoPayload: .readiness(previous: previousReadiness, expectedCurrent: newValue)
            ))
            return
        }

        for record in currentRecords { context.delete(record) }
        do {
            try context.save()
            dailyPlans.removeAll { currentPlanIDs.contains($0.id) }
            readiness = newValue
            recordAdaptivePlanChange(NFAdaptivePlanChangeRecord(
                profileID: profileSnapshot.id,
                occurredAt: date,
                kind: .readinessChanged,
                title: NFAppLocalization.localized(
                    "Readiness changed before practice",
                    locale: NFAppLocalization.preferredLocale,
                    comment: "Adaptive-plan history readiness event title before a session starts."
                ),
                previousState: previousReadiness.title,
                newState: newValue.title,
                reason: NFAppLocalization.localized(
                    "No answer or checkpoint existed, so the unstarted plan was safely regenerated. Low readiness shortens work and removes timed pressure; high readiness can keep the full schedule.",
                    locale: NFAppLocalization.preferredLocale,
                    comment: "Adaptive-plan history readiness effect explanation."
                ),
                undoPayload: .readiness(previous: previousReadiness, expectedCurrent: newValue)
            ))
        } catch {
            context.rollback()
            reload()
            lastErrorMessage = NFAppLocalization.localized("The preference could not be saved.",
                locale: NFAppLocalization.preferredLocale,
                comment: "Generic local preference persistence error."
            )
        }
    }

    var currentPriorityBreakdowns: [NFSchedulingScoreBreakdown] {
        NFDailyScheduler.priorityBreakdowns(for: dailySchedulingSnapshot(at: Date(), calendar: .current))
    }

    var weeklyTransferMission: NFWeeklyTransferMission? {
        let calendar = Calendar.current
        let now = Date()
        let interval = calendar.dateInterval(of: .weekOfYear, for: now)
        let activeDays = Set(standardizedAttempts.compactMap { attempt -> Date? in
            guard !attempt.wasSkipped, attempt.evidenceWeight > 0 else { return nil }
            guard let interval, interval.contains(attempt.submittedAt) else { return nil }
            return calendar.startOfDay(for: attempt.submittedAt)
        }).count
        let candidates = currentPriorityBreakdowns.map {
            NFWeeklyTransferCandidate(
                lab: $0.lab,
                skillID: $0.skillID,
                priority: $0.totalPriority,
                transferGap: $0.transferGap
            )
        }
        var state = weeklyTransferStateRecord?.snapshot ?? NFWeeklyTransferState()
        for checkpoint in sessionCheckpoints
        where checkpoint.isComplete && checkpoint.sourceRaw == SessionSource.weeklyMission.rawValue {
            if let missionID = checkpoint.planID {
                state = state.completing(missionID: missionID)
            }
        }
        let mission = NFWeeklyTransferScheduler.mission(
            profileID: profileSnapshot.id,
            date: now,
            activeDaysThisWeek: activeDays,
            candidates: candidates,
            state: state,
            calendar: calendar
        )
        guard let mission else { return nil }
        if state.pinnedMissionByWeekKey[mission.weekKey] == nil {
            state = state.pinning(mission)
            let record = weeklyTransferStateRecord ?? WeeklyTransferStateRecord()
            if weeklyTransferStateRecord == nil {
                context.insert(record)
                weeklyTransferStateRecord = record
            }
            record.apply(state)
            do {
                try context.save()
                lastErrorMessage = nil
                let locale = NFAppLocalization.preferredLocale
                let labSummary = mission.labs
                    .map { $0.localizedShortTitle(locale: locale) }
                    .joined(separator: " + ")
                recordAdaptivePlanChange(NFAdaptivePlanChangeRecord(
                    profileID: profileSnapshot.id,
                    occurredAt: now,
                    kind: .weeklyMissionPinned,
                    title: NFAppLocalization.localized(
                        "Weekly mission pinned",
                        locale: locale,
                        comment: "Adaptive-plan history weekly mission event title."
                    ),
                    newState: "\(mission.kind.localizedTitle(locale: locale)) · \(labSummary)",
                    reason: NFAppLocalization.localized(
                        "The mission was selected from this week’s transfer gaps and is now fixed until the next learner-week boundary or an explicit deferral.",
                        locale: locale,
                        comment: "Adaptive-plan history weekly mission explanation."
                    )
                ))
            } catch {
                context.rollback()
                reload()
                lastErrorMessage = NFAppLocalization.localized(
                    "The weekly mission could not be saved. Try again.",
                    locale: NFAppLocalization.preferredLocale,
                    comment: "Weekly transfer-mission persistence error."
                )
                return nil
            }
        }
        return mission
    }

    func deferWeeklyTransferMission(_ mission: NFWeeklyTransferMission) {
        let nextDay = Calendar.current.date(byAdding: .day, value: 1, to: Date())
            ?? Date().addingTimeInterval(86_400)
        let existing = weeklyTransferStateRecord ?? WeeklyTransferStateRecord()
        if weeklyTransferStateRecord == nil {
            context.insert(existing)
            weeklyTransferStateRecord = existing
        }
        existing.apply(existing.snapshot.deferring(missionID: mission.id, until: nextDay))
        do {
            try context.save()
            lastErrorMessage = nil
            notice = AppNotice(
                title: NFAppLocalization.localized("Mission deferred", locale: NFAppLocalization.preferredLocale, comment: "Confirmation after deferring the optional weekly transfer mission."),
                message: NFAppLocalization.localized("The mission will be offered again after the deferral. Today’s progress and active-day history are unchanged.", locale: NFAppLocalization.preferredLocale, comment: "Confirmation after deferring the optional weekly transfer mission.")
            )
        } catch {
            context.rollback()
            reload()
            lastErrorMessage = NFAppLocalization.localized("The mission deferral could not be saved.", locale: NFAppLocalization.preferredLocale, comment: "Weekly transfer-mission persistence error.")
            notice = AppNotice(
                title: NFAppLocalization.localized("Deferral not saved", locale: NFAppLocalization.preferredLocale, comment: "Title for a deferral persistence error."),
                message: lastErrorMessage ?? NFAppLocalization.localized("Retry the action.", locale: NFAppLocalization.preferredLocale, comment: "Generic recovery suggestion after a local persistence error.")
            )
        }
    }

    private func dailySchedulingSnapshot(at date: Date, calendar: Calendar) -> NFDailySchedulingSnapshot {
        let evidenceAttempts = standardizedAttempts.filter { !$0.wasSkipped && $0.evidenceWeight > 0 }
        let retentionStates = Dictionary(grouping: evidenceAttempts, by: \.templateID).compactMap { templateID, records -> NFRetentionItemState? in
            guard let latest = records.max(by: { $0.submittedAt < $1.submittedAt }), !templateID.isEmpty else { return nil }
            return NFRetentionItemState(
                id: templateID,
                templateFamily: latest.assessmentTemplateFamily
                    ?? Self.retentionTemplateFamily(from: templateID),
                lab: TrainingLab(rawValue: latest.gameID) ?? .mentalMath,
                lastReviewedAt: latest.submittedAt,
                stabilityDays: max(0.5, 1 + Double(records.filter(\.isCorrect).count) * 0.6),
                repetitions: records.count,
                lapses: records.filter { !$0.isCorrect }.count,
                exposedSeeds: Set(records.map { $0.assessmentSeed ?? $0.seed }),
                lastRepresentationID: latest.assessmentFormatRaw ?? latest.responseFormatRaw
            )
        }
        return NFDailySchedulingSnapshot(
            profile: profileSnapshot,
            date: date,
            dayBoundaryHour: profileSnapshot.dayBoundaryHour,
            skillSummaries: skillSummaries,
            attempts: standardizedAttempts.map(\.dto),
            retentionStates: retentionStates,
            accessibilityExcludedLabs: profile?.excludeVisualSpatial == true ? [.spatial] : [],
            readiness: readiness,
            mentalMathTimingEligible: NFMentalMathProgressionPolicy.status(
                for: standardizedAttempts
                    .filter {
                        $0.gameID == TrainingLab.mentalMath.rawValue
                            && $0.evidenceClassRaw != EvidenceClass.documentPractice.rawValue
                    }
                    .map {
                        NFMentalMathProgressionObservation(
                            submittedAt: $0.submittedAt,
                            isCorrect: $0.isCorrect,
                            errorCode: $0.errorCode,
                            strategyID: $0.templateID,
                            wasTimed: $0.wasTimed,
                            wasSkipped: $0.wasSkipped,
                            evidenceWeight: $0.evidenceWeight
                        )
                    }
            ).timingEligible
        )
    }

    private static func retentionTemplateFamily(from templateID: String) -> String {
        guard let version = templateID.range(of: ".v3.", options: .backwards) else {
            return templateID
        }
        return String(templateID[..<version.upperBound].dropLast())
    }

    var skillSummaries: [SkillSummary] {
        AdaptiveEngine.reduce(standardizedAttempts.map(\.dto))
    }

    /// Cosmetic engagement progression rebuilt from durable attempts and
    /// completed sessions. It never participates in skill or plan reduction.
    var forgeProgress: NFForgeProgressSnapshot {
        NFForgeProgressEngine.makeSnapshot(
            at: Date(),
            attempts: attempts,
            checkpoints: sessionCheckpoints,
            trainingDays: profileSnapshot.trainingDays,
            trackingStartDate: profile?.createdAt,
            excludedLabs: profile?.excludeVisualSpatial == true
                ? [.spatial, .transfer]
                : [.transfer]
        )
    }

    var baselineSkillSummaries: [SkillSummary] {
        AdaptiveEngine.reduce(baselineAssessmentAttempts.map(\.dto))
    }

    var baselineDimensionSummaries: [SkillSummary] {
        NFAssessmentDimensionReducer.reduce(baselineAssessmentAttempts.map(\.dto))
    }

    /// Current protected estimates may incorporate alternate-form reassessment,
    /// but never ordinary practice or document-derived evidence.
    var protectedAssessmentDimensionSummaries: [SkillSummary] {
        NFAssessmentDimensionReducer.reduce(attempts.lazy.filter {
            ($0.sessionSourceRaw == SessionSource.baseline.rawValue
                || $0.sessionSourceRaw == SessionSource.reassessment.rawValue)
                && $0.evidenceClassRaw == EvidenceClass.assessmentHoldout.rawValue
                && !$0.wasSkipped
                && $0.evidenceWeight > 0
        }.map(\.dto))
    }

    private var baselineAssessmentAttempts: [AttemptRecord] {
        attempts.filter {
            $0.sessionSourceRaw == SessionSource.baseline.rawValue
                && $0.evidenceClassRaw == EvidenceClass.assessmentHoldout.rawValue
                && !$0.wasSkipped
                && $0.evidenceWeight > 0
        }
    }

    var standardizedAttempts: [AttemptRecord] {
        attempts.filter { $0.evidenceClassRaw != EvidenceClass.documentPractice.rawValue }
    }

    func baselineScorableAttemptCount(for block: NFAssessmentBlockKind) -> Int {
        var identities: Set<String> = []
        for attempt in attempts where
            attempt.sessionSourceRaw == SessionSource.baseline.rawValue
                && attempt.assessmentBlockRaw == block.rawValue
                && attempt.evidenceClassRaw == EvidenceClass.assessmentHoldout.rawValue
                && !attempt.wasSkipped
                && attempt.evidenceWeight > 0
        {
            identities.insert(attempt.assessmentDescriptorID ?? attempt.itemID)
        }
        return identities.count
    }

    func baselineScorableAttemptCount(for dimension: NFAssessmentDimension) -> Int {
        var identities: Set<String> = []
        for attempt in baselineAssessmentAttempts where
            attempt.assessmentBlockRaw == dimension.block.rawValue
                && (attempt.skillID == dimension.skillID
                    || (attempt.skillWeights[dimension.skillID] ?? 0) > 0)
        {
            identities.insert(attempt.assessmentDescriptorID ?? attempt.itemID)
        }
        return identities.count
    }

    func baselineScorableFormats(for dimension: NFAssessmentDimension) -> Set<NFAssessmentItemFormat> {
        Set(baselineAssessmentAttempts.compactMap { attempt in
            guard attempt.assessmentBlockRaw == dimension.block.rawValue,
                  attempt.skillID == dimension.skillID
                    || (attempt.skillWeights[dimension.skillID] ?? 0) > 0 else {
                return nil
            }
            return attempt.assessmentFormatRaw.flatMap(NFAssessmentItemFormat.init(rawValue:))
        })
    }

    func baselineDimensionIsEstablished(_ dimension: NFAssessmentDimension) -> Bool {
        baselineScorableAttemptCount(for: dimension)
            >= NFAssessmentCatalog.minimumBaselineItemsPerDimension
            && baselineScorableFormats(for: dimension).count
                >= NFAssessmentCatalog.minimumFormatsPerDimension
    }

    func baselineBlockIsEstablished(_ block: NFAssessmentBlockKind) -> Bool {
        guard NFAssessmentCatalog.dimensions(for: block).allSatisfy({
            baselineDimensionIsEstablished($0)
        }) else {
            return false
        }
        return sessionCheckpoints.contains {
            $0.isComplete
                && $0.sourceRaw == SessionSource.baseline.rawValue
                && $0.assessmentBlockRaw == block.rawValue
        }
    }

    func baselineBlockCanResume(_ block: NFAssessmentBlockKind) -> Bool {
        sessionCheckpoints.contains {
            !$0.isComplete
                && $0.assessmentStopReasonRaw == nil
                && $0.sourceRaw == SessionSource.baseline.rawValue
                && $0.assessmentBlockRaw == block.rawValue
        } || attempts.contains {
            $0.sessionSourceRaw == SessionSource.baseline.rawValue
                && $0.assessmentBlockRaw == block.rawValue
        }
    }

    func baselineBlockNeedsRetry(_ block: NFAssessmentBlockKind) -> Bool {
        !baselineBlockIsEstablished(block) && sessionCheckpoints.contains {
            $0.assessmentStopReasonRaw != nil
                && $0.sourceRaw == SessionSource.baseline.rawValue
                && $0.assessmentBlockRaw == block.rawValue
        }
    }

    func reassessmentStatus(at date: Date = Date(), calendar: Calendar = .current) -> NFReassessmentStatus? {
        reassessmentScheduleResult(at: date, calendar: calendar).status
    }

    @discardableResult
    func refreshReassessmentSchedule(
        at date: Date = Date(),
        calendar: Calendar = .current
    ) -> NFReassessmentStatus? {
        let result = reassessmentScheduleResult(at: date, calendar: calendar)
        guard let status = result.status else { return nil }
        let record = reassessmentStateRecord ?? ReassessmentStateRecord(state: result.state)
        let isNewRecord = reassessmentStateRecord == nil
        guard isNewRecord || record.snapshot != result.state else { return status }
        if isNewRecord {
            context.insert(record)
            reassessmentStateRecord = record
        } else {
            record.apply(result.state, modifiedAt: date)
        }
        do {
            try context.save()
            lastErrorMessage = nil
        } catch {
            context.rollback()
            reload()
            lastErrorMessage = NFAppLocalization.localized("The reassessment schedule could not be saved. Training remains available.", locale: NFAppLocalization.preferredLocale, comment: "Non-blocking reassessment-schedule persistence error.")
        }
        return status
    }

    @discardableResult
    func beginDueReassessment(at date: Date = Date(), calendar: Calendar = .current) -> Bool {
        guard let status = refreshReassessmentSchedule(at: date, calendar: calendar),
              status.isDue,
              let block = status.block else {
            notice = AppNotice(
                title: NFAppLocalization.localized("Reassessment is not due", locale: NFAppLocalization.preferredLocale, comment: "Status shown when the user tries to begin reassessment early."),
                message: NFAppLocalization.localized("Your daily plan remains available; reassessment never blocks practice.", locale: NFAppLocalization.preferredLocale, comment: "Status shown when the user tries to begin reassessment early.")
            )
            return false
        }
        let definition = NFAssessmentCatalog.definition(for: block)
        return beginSession(
            lab: definition.coveredLabs.first ?? .mentalMath,
            source: .reassessment,
            requestedMinutes: 6,
            evidenceClass: .assessmentHoldout,
            targetDifficulty: 0.5,
            requestedItemCount: NFAssessmentCatalog.minimumItemsPerDimension(
                for: .reassessmentHoldout,
                block: block
            ) * NFAssessmentCatalog.dimensions(for: block).count,
            assessmentBlock: block,
            reassessmentCycle: status.cycle,
            seedOverride: AdaptiveEngine.fnv1a64(
                "reassessment|v1|\(profileSnapshot.id.uuidString)"
            ),
            isTimed: false
        )
    }

    func deferDueReassessment(at date: Date = Date(), calendar: Calendar = .current) {
        guard let status = refreshReassessmentSchedule(at: date, calendar: calendar),
              status.isDue,
              status.canDefer,
              let record = reassessmentStateRecord,
              let deferred = NFReassessmentScheduler.deferring(record.snapshot, at: date) else {
            notice = AppNotice(
                title: NFAppLocalization.localized("Deferral unavailable", locale: NFAppLocalization.preferredLocale, comment: "Status shown when reassessment cannot be deferred."),
                message: NFAppLocalization.localized("This reassessment is not currently eligible for a new seven-day deferral.", locale: NFAppLocalization.preferredLocale, comment: "Status shown when reassessment cannot be deferred.")
            )
            return
        }
        record.apply(deferred, modifiedAt: date)
        do {
            try context.save()
            lastErrorMessage = nil
            let until = deferred.deferredUntil.map {
                NFAppLocalization.formattedDate($0, date: .long, time: .omitted)
            }
                ?? NFAppLocalization.localized("the saved date", locale: NFAppLocalization.preferredLocale, comment: "Fallback date phrase in a reassessment-deferral confirmation.")
            notice = AppNotice(
                title: NFAppLocalization.localized("Reassessment deferred", locale: NFAppLocalization.preferredLocale, comment: "Confirmation after deferring a reassessment by seven days."),
                message: NFAppLocalization.localized("It will return on \(until). Today’s progress, active-day count, and consistency history are unchanged.", locale: NFAppLocalization.preferredLocale, comment: "Confirmation after deferring a reassessment; the placeholder is a locale-formatted date.")
            )
        } catch {
            context.rollback()
            reload()
            lastErrorMessage = NFAppLocalization.localized("The seven-day deferral could not be saved.", locale: NFAppLocalization.preferredLocale, comment: "Reassessment-deferral persistence error.")
            notice = AppNotice(
                title: NFAppLocalization.localized("Deferral not saved", locale: NFAppLocalization.preferredLocale, comment: "Title for a deferral persistence error."),
                message: lastErrorMessage ?? NFAppLocalization.localized("Retry the action.", locale: NFAppLocalization.preferredLocale, comment: "Generic recovery suggestion after a local persistence error.")
            )
        }
    }

    private func reassessmentScheduleResult(
        at date: Date,
        calendar: Calendar
    ) -> NFReassessmentScheduleResult {
        var baselineEvidenceDates: [NFAssessmentBlockKind: Date] = [:]
        for block in NFAssessmentBlockKind.allCases {
            if block == .spatialRepresentation, profile?.excludeVisualSpatial == true { continue }
            guard baselineBlockIsEstablished(block) else { continue }
            baselineEvidenceDates[block] = sessionCheckpoints
                .filter {
                    $0.isComplete
                        && $0.sourceRaw == SessionSource.baseline.rawValue
                        && $0.assessmentBlockRaw == block.rawValue
                }
                .map(\.updatedAt)
                .min()
        }
        var completedReassessmentDates: [NFAssessmentBlockKind: Date] = [:]
        for checkpoint in sessionCheckpoints where
            checkpoint.isComplete && checkpoint.sourceRaw == SessionSource.reassessment.rawValue
        {
            guard let raw = checkpoint.assessmentBlockRaw,
                  let block = NFAssessmentBlockKind(rawValue: raw) else { continue }
            completedReassessmentDates[block] = max(
                completedReassessmentDates[block] ?? .distantPast,
                checkpoint.updatedAt
            )
        }
        let activeDates = standardizedAttempts.compactMap { attempt -> Date? in
            guard !attempt.wasSkipped, attempt.evidenceWeight > 0 else { return nil }
            return attempt.submittedAt
        }
        return NFReassessmentScheduler.reconcile(
            state: reassessmentStateRecord?.snapshot ?? NFReassessmentState(),
            baselineEvidenceDates: baselineEvidenceDates,
            completedReassessmentDates: completedReassessmentDates,
            activeDates: activeDates,
            now: date,
            calendar: calendar
        )
    }

    var todayAttemptCount: Int {
        standardizedAttempts.filter {
            Calendar.current.isDateInToday($0.submittedAt) &&
            $0.sessionSourceRaw == SessionSource.today.rawValue
        }.count
    }

    var todayCorrectCount: Int {
        standardizedAttempts.filter {
            Calendar.current.isDateInToday($0.submittedAt) &&
            $0.sessionSourceRaw == SessionSource.today.rawValue &&
            $0.isCorrect
        }.count
    }

    var unsavedAttemptCount: Int { pendingAttemptRecords.count }
    var attemptRecordsForExport: [AttemptRecord] { attempts + pendingAttemptRecords }
    var latestInputCalibration: InputCalibrationRecord? { inputCalibrations.first }

    @discardableResult
    func completeOnboarding(_ draft: OnboardingDraft) -> Bool {
        let record: UserProfileRecord
        if let profile {
            record = profile
            record.apply(draft)
        } else {
            record = UserProfileRecord(draft: draft)
            context.insert(record)
        }
        record.onboardingVersion = 2
        let calibration: InputCalibrationRecord? = if draft.hasInputCalibrationSample {
            InputCalibrationRecord(
                profileID: record.id,
                preferredAnswerMode: draft.preferredAnswerMode,
                keyboardLatencyMilliseconds: draft.keyboardLatencyMilliseconds,
                touchLatencyMilliseconds: draft.touchLatencyMilliseconds,
                pencilLatencyMilliseconds: draft.pencilLatencyMilliseconds
            )
        } else {
            nil
        }
        if let calibration { context.insert(calibration) }
        do {
            try context.save()
            profile = record
            NFPrivateSyncBootstrapPreference.setAfterExplicitUserChoice(record.iCloudEnabled)
            if let calibration { inputCalibrations.insert(calibration, at: 0) }
            shouldOpenBaseline = draft.startBaselineImmediately
            lastErrorMessage = nil
            self.publishWidgetSnapshot()
            return true
        } catch {
            context.rollback()
            reload()
            lastErrorMessage = NFAppLocalization.localized("Your profile could not be saved. Your prior profile remains intact; retry to finish onboarding.", locale: NFAppLocalization.preferredLocale, comment: "Onboarding profile-persistence error.")
            notice = AppNotice(
                title: NFAppLocalization.localized("Profile not saved", locale: NFAppLocalization.preferredLocale, comment: "Title for an onboarding profile-persistence error."),
                message: lastErrorMessage ?? NFAppLocalization.localized("Retry onboarding.", locale: NFAppLocalization.preferredLocale, comment: "Recovery suggestion after an onboarding profile-persistence error.")
            )
            return false
        }
    }

    func updateDailyDuration(_ minutes: Int) {
        guard let profile else { return }
        profile.dailyDuration = minutes
        profile.modifiedAt = Date()
        saveAndReload()
        nextDayEnhancementCache.removeAll()
    }

    func updateAIMode(_ mode: AIMode) {
        guard let profile else { return }
        profile.aiModeRaw = mode.rawValue
        profile.modifiedAt = Date()
        saveAndReload()
        nextDayEnhancementCache.removeAll()
    }

    func updatePrivateSyncEnabled(_ enabled: Bool) {
        guard let profile else { return }
        profile.iCloudEnabled = enabled
        profile.modifiedAt = Date()
        do {
            try context.save()
            NFPrivateSyncBootstrapPreference.setAfterExplicitUserChoice(enabled)
            reload()
            lastErrorMessage = nil
            notice = AppNotice(
                title: enabled
                    ? NFAppLocalization.localized("iCloud sync will start after reopening",
                        locale: NFAppLocalization.preferredLocale,
                        comment: "Confirmation after enabling iCloud sync for the next launch."
                    )
                    : NFAppLocalization.localized("iCloud sync will stop after reopening",
                        locale: NFAppLocalization.preferredLocale,
                        comment: "Confirmation after disabling iCloud sync for the next launch."
                    ),
                message: enabled
                    ? NFAppLocalization.localized("Reopen NeuroForge to start syncing. You can keep using the app now.",
                        locale: NFAppLocalization.preferredLocale,
                        comment: "iCloud-sync enable confirmation with a concise restart instruction."
                    )
                    : NFAppLocalization.localized("Reopen NeuroForge to finish turning sync off. Your data stays on this device.",
                        locale: NFAppLocalization.preferredLocale,
                        comment: "iCloud-sync disable confirmation with a concise restart instruction."
                    )
            )
        } catch {
            context.rollback()
            reload()
            lastErrorMessage = NFAppLocalization.localized("The private sync preference could not be saved.",
                locale: NFAppLocalization.preferredLocale,
                comment: "Private-sync preference persistence error."
            )
            notice = AppNotice(
                title: NFAppLocalization.localized(
                    "iCloud sync setting not saved",
                    locale: NFAppLocalization.preferredLocale,
                    comment: "Alert title after an iCloud-sync preference fails to save."
                ),
                message: NFAppLocalization.localized(
                    "Your previous setting is unchanged. Try again after freeing local storage.",
                    locale: NFAppLocalization.preferredLocale,
                    comment: "Recovery guidance after an iCloud-sync preference fails to save."
                )
            )
        }
    }

    /// Makes the shared, device-local document library safe before the user
    /// accepts a different iCloud account. Files, extraction metadata, chunks,
    /// and AI policy remain intact, but every original requires a fresh explicit
    /// per-document sync opt-in in the newly selected account namespace.
    func prepareDocumentsForFreshCloudAccount() throws {
        let linkedDocuments = documents.filter {
            NFDocumentSyncPolicy(rawValue: $0.syncPolicy) != .localOnly
        }
        guard !linkedDocuments.isEmpty else { return }
        let changedAt = Date()
        for document in linkedDocuments {
            document.syncPolicy = NFDocumentSyncPolicy.localOnly.rawValue
            document.modifiedAt = changedAt
        }
        do {
            try context.save()
            reload()
            lastErrorMessage = nil
        } catch {
            context.rollback()
            reload()
            lastErrorMessage = NFAppLocalization.localized(
                "The private sync preference could not be saved.",
                locale: NFAppLocalization.preferredLocale,
                comment: "Private-sync preference persistence error."
            )
            throw error
        }
    }

    func updateTimingMode(_ mode: TimingMode) {
        guard let profile else { return }
        let didChange = profile.timingModeRaw != mode.rawValue
        profile.timingModeRaw = mode.rawValue
        profile.modifiedAt = Date()
        // A materialized plan is today's durable contract. Session launch
        // applies the current global timing accommodation, so changing this
        // preference never needs to erase or replace the plan.
        saveAndReload()
        if didChange { nextDayEnhancementCache.removeAll() }
    }

    func updateProfile(
        from draft: OnboardingDraft,
        at date: Date = .now,
        calendar: Calendar = .current
    ) throws {
        guard let profile else { return }
        let previousPreferenceSummary = adaptivePreferenceSummary(
            duration: profile.dailyDuration,
            timingMode: TimingMode(rawValue: profile.timingModeRaw) ?? .adaptive,
            boundaryHour: profile.dayBoundaryHour,
            trainingDayCount: profile.trainingDaysRaw.split(separator: ",").count
        )
        let privateSyncChoiceChanged = profile.iCloudEnabled != draft.iCloudEnabled
        let boundaryChanged = profile.dayBoundaryHour != min(12, max(0, draft.dayBoundaryHour))
        let oldBoundaryHour = profile.dayBoundaryHour
        let oldDayKey = NFDailyScheduler.localDayKey(
            for: date,
            dayBoundaryHour: oldBoundaryHour,
            calendar: calendar
        )
        let currentPlanRecords = dailyPlans.filter {
            $0.profileID == profile.id
                && $0.dayBoundaryHour == oldBoundaryHour
                && ($0.localDayKey == oldDayKey || ($0.travelPreservedUntil ?? .distantPast) > date)
        }
        profile.stageRaw = draft.stage.rawValue
        profile.fieldsRaw = draft.fields.map(\.rawValue).sorted().joined(separator: ",")
        profile.goalsRaw = draft.goals.map(\.rawValue).sorted().joined(separator: ",")
        profile.dailyDuration = draft.dailyDuration
        profile.timingModeRaw = draft.timingMode.rawValue
        profile.aiModeRaw = draft.aiMode.rawValue
        profile.iCloudEnabled = draft.iCloudEnabled
        profile.reducedMotion = draft.reducedMotion
        profile.hideTimers = draft.hideTimers
        profile.excludeVisualSpatial = draft.excludeVisualSpatial
        profile.preferredLanguageCode = draft.preferredLanguageCode
        profile.trainingDaysRaw = draft.trainingDays.sorted().map(String.init).joined(separator: ",")
        profile.dayBoundaryHour = min(12, max(0, draft.dayBoundaryHour))
        profile.preferredAnswerModeRaw = draft.preferredAnswerMode.rawValue
        profile.reinforcementHapticsEnabled = draft.reinforcementHapticsEnabled
        profile.reinforcementSoundEnabled = draft.reinforcementSoundEnabled
        profile.modifiedAt = Date()
        if boundaryChanged {
            let boundaryContext = NFPlanBoundaryContext.make(
                at: date,
                dayBoundaryHour: profile.dayBoundaryHour,
                calendar: calendar
            )
            for record in currentPlanRecords {
                record.preserveAcrossPreferenceBoundaryChange(boundaryContext)
            }
        }
        do {
            try context.save()
            reload()
            lastErrorMessage = nil
            recordAdaptivePlanChange(NFAdaptivePlanChangeRecord(
                profileID: profile.id,
                occurredAt: date,
                kind: .preferencesApplied,
                title: NFAppLocalization.localized(
                    "Training preferences saved",
                    locale: NFAppLocalization.preferredLocale,
                    comment: "Adaptive-plan history preference event title."
                ),
                previousState: previousPreferenceSummary,
                newState: adaptivePreferenceSummary(
                    duration: draft.dailyDuration,
                    timingMode: draft.timingMode,
                    boundaryHour: min(12, max(0, draft.dayBoundaryHour)),
                    trainingDayCount: draft.trainingDays.count
                ),
                reason: boundaryChanged
                    ? NFAppLocalization.localized(
                        "The new day boundary will apply after the preserved current plan. Completed work and today’s plan identity were not replaced.",
                        locale: NFAppLocalization.preferredLocale,
                        comment: "Adaptive-plan history preference explanation when the day boundary changes."
                    )
                    : NFAppLocalization.localized(
                        "New scheduling preferences apply at the next plan boundary. Completed work and today’s committed plan were preserved.",
                        locale: NFAppLocalization.preferredLocale,
                        comment: "Adaptive-plan history preference explanation."
                    )
            ))
        } catch {
            context.rollback()
            reload()
            lastErrorMessage = NFAppLocalization.localized(
                "The preference could not be saved.",
                locale: NFAppLocalization.preferredLocale,
                comment: "Generic local preference persistence error."
            )
            throw error
        }
        if privateSyncChoiceChanged {
            NFPrivateSyncBootstrapPreference.setAfterExplicitUserChoice(profile.iCloudEnabled)
        }
        nextDayEnhancementCache.removeAll()
        publishWidgetSnapshot(at: date, calendar: calendar)
    }

    private func adaptivePreferenceSummary(
        duration: Int,
        timingMode: TimingMode,
        boundaryHour: Int,
        trainingDayCount: Int
    ) -> String {
        let durationText = NFAppLocalization.formattedMinutes(duration)
        let dayText = trainingDayCount == 1
            ? NFAppLocalization.localized("1 training day", locale: NFAppLocalization.preferredLocale, comment: "Singular weekly training-day count.")
            : NFAppLocalization.localized("\(trainingDayCount) training days", locale: NFAppLocalization.preferredLocale, comment: "Weekly training-day count; the placeholder is the count.")
        let boundaryText = DateComponents(calendar: .current, hour: boundaryHour)
            .date
            .map { NFAppLocalization.formattedDate($0, date: .omitted, time: .shortened) }
            ?? "\(boundaryHour):00"
        return "\(durationText) · \(timingMode.title) · \(dayText) · \(boundaryText)"
    }

    func restartOnboardingPreferences() {
        guard let profile else { return }
        profile.apply(OnboardingDraft())
        profile.onboardingVersion = 0
        profile.claimsPolicyAcknowledgedVersion = 0
        profile.ageBandAcknowledged16Plus = false
        // Setup can be revisited without deleting today's durable completion
        // record. New preferences take effect at the next plan boundary.
        activeSessionRequest = nil
        shouldOpenTodayPlan = false
        saveAndReload()
        NFPrivateSyncBootstrapPreference.set(profile.iCloudEnabled)
        nextDayEnhancementCache.removeAll()
    }

    func updateReinforcementPreferences(hapticsEnabled: Bool? = nil, soundEnabled: Bool? = nil) {
        guard let profile else { return }
        if let hapticsEnabled { profile.reinforcementHapticsEnabled = hapticsEnabled }
        if let soundEnabled { profile.reinforcementSoundEnabled = soundEnabled }
        profile.modifiedAt = Date()
        saveAndReload()
    }

    func saveInputCalibration(
        preferredAnswerMode: NFPreferredAnswerMode,
        keyboardLatencyMilliseconds: Double?,
        touchLatencyMilliseconds: Double?,
        pencilLatencyMilliseconds: Double?
    ) throws {
        guard let profile else { return }
        let calibration = InputCalibrationRecord(
            profileID: profile.id,
            preferredAnswerMode: preferredAnswerMode,
            keyboardLatencyMilliseconds: keyboardLatencyMilliseconds,
            touchLatencyMilliseconds: touchLatencyMilliseconds,
            pencilLatencyMilliseconds: pencilLatencyMilliseconds
        )
        profile.preferredAnswerModeRaw = preferredAnswerMode.rawValue
        profile.modifiedAt = Date()
        context.insert(calibration)
        do {
            try context.save()
            inputCalibrations.insert(calibration, at: 0)
            lastErrorMessage = nil
        } catch {
            context.rollback()
            reload()
            lastErrorMessage = NFAppLocalization.localized("The input calibration could not be saved.", locale: NFAppLocalization.preferredLocale, comment: "Input-calibration persistence error.")
            throw error
        }
    }

    func saveProgressAnnotation(
        id: UUID? = nil,
        startDate: Date,
        endDate: Date,
        note: String,
        includeInExport: Bool,
        calendar: Calendar = .current
    ) throws {
        let normalizedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalizedNote.count <= ProgressAnnotationRecord.maximumNoteCharacters else {
            let error = NFProgressAnnotationPersistenceError.noteTooLong(
                maximum: ProgressAnnotationRecord.maximumNoteCharacters
            )
            lastErrorMessage = error.localizedDescription
            throw error
        }
        if let id, let existing = progressAnnotations.first(where: { $0.id == id }) {
            let normalizedStart = calendar.startOfDay(for: min(startDate, endDate))
            let normalizedEnd = calendar.startOfDay(for: max(startDate, endDate))
            existing.startDate = normalizedStart
            existing.endDate = normalizedEnd
            existing.note = normalizedNote
            existing.includeInExport = includeInExport
            existing.modifiedAt = Date()
        } else {
            context.insert(ProgressAnnotationRecord(
                startDate: startDate,
                endDate: endDate,
                note: normalizedNote,
                includeInExport: includeInExport,
                calendar: calendar
            ))
        }
        do {
            try context.save()
            reload()
            lastErrorMessage = nil
        } catch {
            context.rollback()
            reload()
            lastErrorMessage = NFAppLocalization.localized("The private progress annotation could not be saved.", locale: NFAppLocalization.preferredLocale, comment: "Private progress-annotation persistence error.")
            throw error
        }
    }

    func deleteProgressAnnotation(_ annotation: ProgressAnnotationRecord) throws {
        context.delete(annotation)
        do {
            try context.save()
            reload()
            lastErrorMessage = nil
        } catch {
            context.rollback()
            reload()
            lastErrorMessage = NFAppLocalization.localized("The private progress annotation could not be deleted.", locale: NFAppLocalization.preferredLocale, comment: "Private progress-annotation deletion error.")
            throw error
        }
    }

    @discardableResult
    func beginSession(
        lab: TrainingLab = .mentalMath,
        source: SessionSource = .today,
        requestedMinutes: Int? = nil,
        preferredMentalMathKind: MentalMathKind? = nil,
        evidenceClass: EvidenceClass = .practice,
        field: STEMField? = nil,
        topic: String? = nil,
        recommendationRationale: String? = nil,
        targetDifficulty: Double? = nil,
        requestedItemCount: Int? = nil,
        startingIndex: Int = 0,
        assessmentBlock: NFAssessmentBlockKind? = nil,
        reassessmentCycle: Int? = nil,
        seedOverride: UInt64? = nil,
        planID: String? = nil,
        planBlockID: String? = nil,
        isTimed: Bool? = nil,
        mechanicID: String? = nil,
        retentionItemIDs: [String] = [],
        retentionTargets: [NFRetentionReviewTarget] = [],
        transferBrief: NFExerciseTransferBrief? = nil
    ) -> Bool {
        guard activeSessionRequest == nil else {
            lastErrorMessage = NFAppLocalization.localized("Finish or end the current session before starting another one.", locale: NFAppLocalization.preferredLocale, comment: "Error shown when a second session is requested while one is active.")
            notice = AppNotice(
                title: NFAppLocalization.localized("Session already in progress", locale: NFAppLocalization.preferredLocale, comment: "Title for an attempt to start a second active session."),
                message: NFAppLocalization.localized("Finish or end the current session before starting another one. Your current answer was not replaced.", locale: NFAppLocalization.preferredLocale, comment: "Error shown when a second session is requested while one is active.")
            )
            return false
        }
        let transferContractIsValid = if transferBrief != nil || source == .weeklyMission {
            lab == .transfer
                && evidenceClass == .appliedTransfer
                && transferBrief != nil
        } else {
            true
        }
        guard transferContractIsValid else {
            lastErrorMessage = NFTransferTaxonomyError.transferBriefOutsideTransferLab.errorDescription
            notice = AppNotice(
                title: NFAppLocalization.localized(
                    "Transfer mission not started",
                    locale: NFAppLocalization.preferredLocale,
                    comment: "Transfer taxonomy validation failure title."
                ),
                message: lastErrorMessage ?? NFAppLocalization.localized(
                    "The mission request did not preserve its Transfer classification.",
                    locale: NFAppLocalization.preferredLocale,
                    comment: "Transfer taxonomy validation failure message."
                )
            )
            return false
        }
        let resolvedRequestedItemCount = requestedItemCount.map { min(50, max(1, $0)) }
        let rotationItemCount = resolvedRequestedItemCount
            ?? requestedMinutes.map { max(3, min(12, $0 / 2)) }
            ?? 5
        let offlineRotationPlan: NFOfflineQuestionRotationPlan? = {
            guard source == .focused,
                  evidenceClass == .practice,
                  assessmentBlock == nil,
                  retentionTargets.isEmpty,
                  retentionItemIDs.isEmpty,
                  transferBrief == nil else { return nil }
            return try? offlineQuestionRotation.reserve(
                profileID: profileSnapshot.id,
                lab: lab,
                laneID: mechanicID ?? "mixed",
                itemCount: rotationItemCount,
                bank: NFOfflineQuestionBank.rotationBank
            )
        }()
        if source == .focused,
           evidenceClass == .practice,
           assessmentBlock == nil,
           retentionTargets.isEmpty,
           retentionItemIDs.isEmpty,
           transferBrief == nil,
           offlineRotationPlan == nil {
            lastErrorMessage = NFAppLocalization.localized(
                "The offline question rotation could not be reserved. Your current catalog data was left unchanged.",
                locale: NFAppLocalization.preferredLocale,
                comment: "Error shown when a focused quiz cannot reserve a non-repeating offline question slice."
            )
            notice = AppNotice(
                title: NFAppLocalization.localized(
                    "Question set unavailable",
                    locale: NFAppLocalization.preferredLocale,
                    comment: "Title for a focused quiz whose offline question reservation failed."
                ),
                message: lastErrorMessage ?? ""
            )
            return false
        }
        let offlineQuestionOrdinals: [Int] = if mechanicID == nil,
            let offlineRotationPlan {
            offlineRotationPlan.items.compactMap {
                NFOfflineQuestionBank.ordinal(forQuestionID: $0.questionID, lab: lab)
            }
        } else {
            []
        }
        if mechanicID == nil,
           offlineRotationPlan != nil,
           offlineQuestionOrdinals.count != rotationItemCount {
            lastErrorMessage = NFAppLocalization.localized(
                "The offline question set did not match the installed catalog version.",
                locale: NFAppLocalization.preferredLocale,
                comment: "Error shown when a reserved question set cannot be mapped to the installed catalog."
            )
            return false
        }
        let resumableCheckpoint = sessionCheckpoints.first { checkpoint in
            guard !checkpoint.isComplete else { return false }
            if let planBlockID {
                return checkpoint.planID == planID && checkpoint.planBlockID == planBlockID
            }
            if source == .baseline, let assessmentBlock {
                return checkpoint.sourceRaw == SessionSource.baseline.rawValue
                    && checkpoint.assessmentBlockRaw == assessmentBlock.rawValue
                    && checkpoint.assessmentStopReasonRaw == nil
            }
            if source == .reassessment, let assessmentBlock, let reassessmentCycle {
                return checkpoint.sourceRaw == SessionSource.reassessment.rawValue
                    && checkpoint.assessmentBlockRaw == assessmentBlock.rawValue
                    && checkpoint.assessmentCycle == reassessmentCycle
                    && checkpoint.assessmentStopReasonRaw == nil
            }
            return false
        }
        let baselineAlreadyEstablished = assessmentBlock.map {
            baselineBlockIsEstablished($0)
        } ?? false
        let isProtectedAssessmentSession = source == .baseline || source == .reassessment
        let terminalIncompleteCheckpoints = sessionCheckpoints.filter { checkpoint in
            isProtectedAssessmentSession
                && checkpoint.sourceRaw == source.rawValue
                && checkpoint.assessmentBlockRaw == assessmentBlock?.rawValue
                && (source != .reassessment || checkpoint.assessmentCycle == reassessmentCycle)
                && checkpoint.assessmentStopReasonRaw != nil
                && (source != .baseline || !baselineAlreadyEstablished)
        }
        let requestedBaseSeed = seedOverride ?? todayPlan.seed
        let baseSeed = offlineRotationPlan.map { plan in
            NFStableDeterminism.hash64(
                "focused-launch|\(requestedBaseSeed)|\(plan.id)|\(mechanicID ?? "mixed")"
            )
        } ?? requestedBaseSeed
        let resolvedSeed: UInt64 = {
            if let resumableCheckpoint { return resumableCheckpoint.seed }
            guard let assessmentBlock, !terminalIncompleteCheckpoints.isEmpty else { return baseSeed }
            return AdaptiveEngine.fnv1a64(
                "assessment-retry|\(source.rawValue)|\(baseSeed)|\(assessmentBlock.rawValue)|\(reassessmentCycle ?? 0)|\(terminalIncompleteCheckpoints.count)"
            )
        }()
        let assessmentSessionHistory: [AttemptRecord] = {
            guard resumableCheckpoint == nil,
                  isProtectedAssessmentSession,
                  let assessmentBlock,
                  terminalIncompleteCheckpoints.isEmpty else { return [] }
            var seenIdentities: Set<String> = []
            return attempts
                .filter {
                    $0.sessionSourceRaw == source.rawValue
                        && $0.assessmentBlockRaw == assessmentBlock.rawValue
                        && (source != .reassessment || $0.assessmentCycle == reassessmentCycle)
                }
                .sorted {
                    if $0.submittedAt != $1.submittedAt { return $0.submittedAt < $1.submittedAt }
                    return $0.id.uuidString < $1.id.uuidString
                }
                .filter { attempt in
                    seenIdentities.insert(attempt.assessmentDescriptorID ?? attempt.itemID).inserted
                }
        }()
        let assessmentAttemptHistory = assessmentSessionHistory.filter {
            !$0.wasSkipped
                && $0.evidenceWeight > 0
                && $0.evidenceClassRaw == EvidenceClass.assessmentHoldout.rawValue
        }
        let resumeIndex = resumableCheckpoint.map {
            let mustFinishReflection = $0.pendingReflectionAttemptID != nil
                && $0.reflectionTriggerRaw.flatMap(NFAttemptReflectionTrigger.init(rawValue:)) != nil
            return $0.currentIndex + ($0.hasCommittedCurrentItem && !mustFinishReflection ? 1 : 0)
        } ?? (assessmentAttemptHistory.isEmpty ? startingIndex : assessmentAttemptHistory.count)
        let resumedResults = resumableCheckpoint?.resultsRaw
            .split(separator: ",")
            .map { $0 == "1" }
            ?? assessmentAttemptHistory.map(\.isCorrect)
        let decodedCredits = resumableCheckpoint?.creditsRaw
            .split(separator: ",")
            .compactMap { Double($0) }
            ?? assessmentAttemptHistory.map { attempt in
                attempt.isCorrect && attempt.deterministicCredit == 0
                    ? 1
                    : attempt.deterministicCredit
            }
        let resumedCredits = decodedCredits.count == resumedResults.count
            ? decodedCredits.map { min(1, max(0, $0)) }
            : resumedResults.map { $0 ? 1 : 0 }
        let checkpointDescriptorIDs = resumableCheckpoint?.assessmentDescriptorIDsRaw
            .split(separator: ",")
            .map(String.init)
        let attemptDescriptorIDs = assessmentAttemptHistory.compactMap(\.assessmentDescriptorID)
        let resumedAssessmentDescriptorIDs = checkpointDescriptorIDs
            ?? (attemptDescriptorIDs.count == assessmentAttemptHistory.count ? attemptDescriptorIDs : [])
        let checkpointAssessmentEvents = resumableCheckpoint?.assessmentEventsRaw
            .split(separator: ",")
            .map(String.init)
        let historyAssessmentEvents = assessmentSessionHistory.compactMap { attempt in
            attempt.assessmentDescriptorID.map {
                if attempt.evidenceClassRaw == EvidenceClass.practice.rawValue,
                   !attempt.wasSkipped,
                   attempt.evidenceWeight == 0 {
                    return "practice:\($0)"
                }
                return "\(attempt.wasSkipped ? "skipped" : "answered"):\($0)"
            }
        }
        let resumedAssessmentEvents = checkpointAssessmentEvents?.isEmpty == false
            ? checkpointAssessmentEvents ?? []
            : (historyAssessmentEvents.isEmpty
                ? resumedAssessmentDescriptorIDs.map { "answered:\($0)" }
                : historyAssessmentEvents)
        let resumedSessionID = resumableCheckpoint?.sessionID
            ?? assessmentSessionHistory.last?.sessionID
        let resumedActiveDuration = resumableCheckpoint?.activeDurationSeconds
            ?? assessmentSessionHistory.reduce(0) { $0 + max(0, $1.activeDurationSeconds) }
        let practiceDurationHistory = resumedSessionID.map { sessionID in
            attempts.filter { $0.sessionID == sessionID }
        } ?? assessmentSessionHistory
        let resumedAssessmentPracticeDuration = practiceDurationHistory
            .filter {
                $0.evidenceClassRaw == EvidenceClass.practice.rawValue
                    && $0.evidenceWeight == 0
            }
            .reduce(0) { $0 + max(0, $1.activeDurationSeconds) }
        let resolvedField = field
            ?? (source == .today ? assignedField(forPlanID: planID, blockID: planBlockID) : nil)
            ?? profileSnapshot.fields.sorted(by: { $0.rawValue < $1.rawValue }).first
            ?? .general
        let resolvedRetentionTargets = retentionTargets.isEmpty
            ? retentionReviewTargets(
                forPlanID: planID,
                blockID: planBlockID,
                fallbackItemIDs: retentionItemIDs,
                fallbackSeed: resolvedSeed
            )
            : retentionTargets
        activeSessionRequest = SessionRequest(
            lab: lab,
            source: source,
            seed: resolvedSeed,
            localeIdentifier: profile?.preferredLanguageCode ?? Locale.current.identifier,
            requestedMinutes: requestedMinutes,
            preferredMentalMathKind: preferredMentalMathKind,
            evidenceClass: evidenceClass,
            field: resolvedField,
            topic: topic,
            recommendationRationale: recommendationRationale
                ?? resumableCheckpoint?.recommendationRationale,
            targetDifficulty: targetDifficulty,
            requestedItemCount: resolvedRequestedItemCount,
            offlineQuestionOrdinals: offlineQuestionOrdinals,
            startingIndex: max(startingIndex, resumeIndex),
            assessmentBlock: assessmentBlock,
            reassessmentCycle: reassessmentCycle,
            planID: planID,
            planBlockID: planBlockID,
            // Untimed is a store-boundary invariant, including explicit calls
            // originating from stale UI state or restored plans.
            isTimed: profileSnapshot.timingMode == .untimed
                || (source == .today && readiness == .low)
                ? false
                : (isTimed ?? true),
            resumeSessionID: resumedSessionID,
            resumedResults: resumedResults,
            resumedCredits: resumedCredits,
            resumedAssessmentDescriptorIDs: resumedAssessmentDescriptorIDs,
            resumedAssessmentEvents: resumedAssessmentEvents,
            resumedResponsePayload: resumableCheckpoint?.response,
            resumedScratchpad: resumableCheckpoint?.scratchpad ?? "",
            resumeCurrentItemWasCommitted: resumableCheckpoint?.hasCommittedCurrentItem
                ?? !assessmentSessionHistory.isEmpty,
            resumedPendingReflectionAttemptID: resumableCheckpoint?.pendingReflectionAttemptID,
            resumedReflectionTrigger: resumableCheckpoint?.reflectionTriggerRaw
                .flatMap(NFAttemptReflectionTrigger.init(rawValue:)),
            resumedSelectedReflectionCode: resumableCheckpoint?.selectedReflectionCodeRaw
                .flatMap(NFErrorReflectionCode.init(rawValue:)),
            resumedReflectionNote: resumableCheckpoint?.reflectionNote ?? "",
            resumedActiveDurationSeconds: resumedActiveDuration,
            resumedAssessmentPracticeDurationSeconds: resumedAssessmentPracticeDuration,
            mechanicID: mechanicID,
            retentionItemIDs: retentionItemIDs,
            retentionTargets: resolvedRetentionTargets,
            transferBrief: transferBrief,
            // Daily practice is intentionally model-free. External authoring
            // is used only through the explicit Question Writer Shortcut.
            presentationEnhancements: [:],
            quarantinedItemIDs: Set(itemReports.filter { $0.status == "quarantined" }.map(\.itemID)),
            quarantinedAssessmentDescriptorIDs: Set(
                itemReports
                    .filter { $0.status == "quarantined" }
                    .compactMap(\.assessmentDescriptorID)
            )
        )
        return true
    }

    func requestTodayPlan() {
        guard !deferAppIntentIfDirty(.todayPlan, destination: .today) else { return }
        selectedDestination = .today
        shouldOpenTodayPlan = true
    }

    func consumeTodayPlanRequest() {
        shouldOpenTodayPlan = false
    }

    /// Opens the first genuinely due retention block, rather than conflating
    /// scheduled review with arbitrary source-document practice. If no memory
    /// item is due, the handoff lands on Today without manufacturing evidence.
    @discardableResult
    func requestReviewsDue(
        at date: Date = Date(),
        calendar: Calendar = .current
    ) -> Bool {
        guard !deferAppIntentIfDirty(
            .reviewsDue(date: date, calendar: calendar),
            destination: .today
        ) else { return true }
        selectedDestination = .today
        let plan = dailyPlan(at: date, calendar: calendar)
        let completed = completedPlanBlockIDs(planID: plan.id)
        guard let block = plan.blocks.first(where: {
            $0.kindRaw == NFDailyPlanBlockKind.retentionReview.rawValue
                && !$0.retentionItemIDs.isEmpty
                && !completed.contains($0.id)
        }) else {
            shouldOpenTodayPlan = true
            return false
        }
        shouldOpenTodayPlan = false
        return beginSession(
            lab: block.lab,
            source: .today,
            requestedMinutes: block.minutes,
            evidenceClass: block.evidenceClass,
            topic: block.mechanicID,
            planID: plan.id,
            planBlockID: block.id,
            isTimed: block.timed,
            mechanicID: block.mechanicID,
            retentionItemIDs: block.retentionItemIDs,
            retentionTargets: retentionReviewTargets(
                forPlanID: plan.id,
                blockID: block.id,
                fallbackItemIDs: block.retentionItemIDs,
                fallbackSeed: plan.seed
            )
        )
    }

    func requestSourceReviews() {
        guard !deferAppIntentIfDirty(.sourceReviews, destination: .library) else { return }
        selectedDestination = .library
        requestedLibraryDocumentID = nil
        requestedSourceChunkID = nil
        requestedSourceReviewID = nil
        shouldOpenSourceReviews = true
    }

    func consumeSourceReviewRequest() {
        shouldOpenSourceReviews = false
    }

    func consumeBaselineRequest() { shouldOpenBaseline = false }

    func requestDocumentImport() {
        guard !deferAppIntentIfDirty(.documentImport, destination: .library) else { return }
        selectedDestination = .library
        shouldPresentDocumentImporter = true
    }

    /// Preserves Retrieval's complete handoff as one transaction: open the
    /// importer now, then continue into the newly indexed source review. A
    /// dirty editor must defer both pieces together rather than letting the
    /// importer request replace the pending review intent.
    func requestSourceReviewDocumentImport() {
        guard !deferAppIntentIfDirty(
            .sourceReviewDocumentImport,
            destination: .library
        ) else { return }
        selectedDestination = .library
        requestedLibraryDocumentID = nil
        requestedSourceChunkID = nil
        requestedSourceReviewID = nil
        shouldOpenSourceReviews = true
        shouldPresentDocumentImporter = true
    }

    func requestAIStudioForPendingShortcutCallback() {
        guard !deferAppIntentIfDirty(.questionWriterCallback, destination: .train) else { return }
        selectedDestination = .train
        shouldOpenAIStudio = true
    }

    @discardableResult
    func requestFocusedMentalMathPractice(
        requestedMinutes: Int? = nil,
        preferredMentalMathKind: MentalMathKind? = nil
    ) -> Bool {
        guard !deferAppIntentIfDirty(
            .mentalMathPractice(
                requestedMinutes: requestedMinutes,
                preferredKind: preferredMentalMathKind
            ),
            destination: .train
        ) else { return true }
        selectedDestination = .train
        return beginSession(
            lab: .mentalMath,
            source: .focused,
            requestedMinutes: requestedMinutes,
            preferredMentalMathKind: preferredMentalMathKind
        )
    }

    func consumeDocumentImportRequest() {
        shouldPresentDocumentImporter = false
    }

    func saveAttempt(
        sessionID: UUID,
        item: MentalMathItem,
        response: String,
        score: DeterministicScore,
        confidence: ConfidenceLevel,
        shownAt: Date,
        activeDuration: TimeInterval,
        source: SessionSource
    ) throws {
        let record = AttemptRecord(
            sessionID: sessionID,
            item: item,
            response: response,
            score: score,
            confidence: confidence,
            shownAt: shownAt,
            submittedAt: Date(),
            activeDuration: activeDuration,
            source: source
        )
        try insertAttempt(record)
    }

    func saveLabAttempt(
        lab: TrainingLab,
        itemID: String,
        prompt: String,
        response: String,
        correctAnswer: String,
        isCorrect: Bool,
        confidence: ConfidenceLevel,
        evidenceClass: EvidenceClass = .practice,
        source: SessionSource = .focused,
        sourceDocumentIDs: [UUID] = [],
        sourceChunkIDs: [String] = [],
        responseFormat: String = "singleChoice"
    ) throws {
        let record = AttemptRecord(
            sessionID: UUID(),
            lab: lab,
            itemID: itemID,
            prompt: prompt,
            response: response,
            correctAnswer: correctAnswer,
            isCorrect: isCorrect,
            confidence: confidence,
            evidenceClass: evidenceClass,
            source: source,
            sourceDocumentIDs: sourceDocumentIDs,
            sourceChunkIDs: sourceChunkIDs,
            responseFormat: responseFormat
        )
        try insertAttempt(record)
    }

    func saveAuthoredAttempt(
        generationID: UUID,
        question: NFAuthoredQuestion,
        response: String,
        isCorrect: Bool,
        confidence: ConfidenceLevel,
        sourceDocumentIDs: [UUID],
        source: SessionSource = .focused
    ) throws {
        let record = AttemptRecord(
            sessionID: generationID,
            lab: question.lab,
            itemID: question.id,
            prompt: question.prompt,
            response: response,
            correctAnswer: question.correctAnswer,
            isCorrect: isCorrect,
            confidence: confidence,
            evidenceClass: .documentPractice,
            source: source
        )
        record.generationID = generationID
        record.sourceDocumentIDsRaw = sourceDocumentIDs.map(\.uuidString).joined(separator: ",")
        record.sourceChunkIDsRaw = question.citationChunkIDs.joined(separator: ",")
        record.responseFormatRaw = question.style.rawValue
        record.validationVersion = NFAuthoringEngine.validationVersion
        record.skillWeightsRaw = NFTelemetryCodec.encode([question.lab.skillID: 1.0])
        record.domainContextRaw = aiGenerations.first(where: { $0.id == generationID })?.fieldRaw
            ?? STEMField.general.rawValue
        try insertAttempt(record)
    }

    private func retentionTarget(
        for exercise: NFExercise,
        planID: String?,
        planBlockID: String?
    ) -> NFRetentionReviewTarget? {
        guard exercise.evidenceClass == .retention,
              let request = activeSessionRequest,
              request.evidenceClass == .retention,
              request.lab == exercise.lab else {
            return nil
        }
        if let planID, request.planID != planID { return nil }
        if let planBlockID, request.planBlockID != planBlockID { return nil }
        guard let itemOrdinal = exercise.id.split(separator: ".").last.flatMap({ Int($0) }) else {
            return nil
        }
        return request.retentionTarget(at: itemOrdinal)
    }

    func saveExerciseAttempt(
        attemptID: UUID,
        sessionID: UUID,
        exercise: NFExercise,
        response: NFExerciseResponse,
        result: NFExerciseScoringResult,
        confidence: ConfidenceLevel,
        shownAt: Date,
        activeDuration: TimeInterval,
        source: SessionSource,
        assessmentBlock: NFAssessmentBlockKind? = nil,
        assessmentDescriptorID: String? = nil,
        assessmentDescriptor: NFAssessmentItemDescriptor? = nil,
        assessmentCycle: Int? = nil,
        planID: String? = nil,
        planBlockID: String? = nil,
        hintCount: Int = 0,
        inputMode: String = "unknown",
        interruptionCount: Int = 0,
        revisionCount: Int = 0,
        accommodationFlags: [String] = [],
        wasTimed: Bool = false,
        generationID: UUID? = nil
    ) throws {
        let retentionTarget = retentionTarget(
            for: exercise,
            planID: planID,
            planBlockID: planBlockID
        )
        let responseText = (try? String(
            data: JSONEncoder().encode(response),
            encoding: .utf8
        )) ?? result.normalizedResponse ?? ""
        let record = AttemptRecord(
            sessionID: sessionID,
            lab: exercise.lab,
            itemID: exercise.id,
            prompt: exercise.prompt,
            response: responseText,
            correctAnswer: result.expectedAnswerSummary ?? "Delayed assessment key",
            isCorrect: result.isCorrect,
            confidence: confidence,
            evidenceClass: exercise.evidenceClass,
            source: source
        )
        record.id = attemptID
        record.generationID = generationID
        // Retention evidence belongs to the scheduled memory item, while the
        // generated exercise ID remains intact for provenance and reporting.
        record.templateID = retentionTarget?.memoryItemID ?? exercise.templateID
        record.seed = exercise.seed
        record.skillID = assessmentDescriptor?.skillID
            ?? exercise.skillWeights.max(by: { $0.value < $1.value })?.key
            ?? exercise.lab.skillID
        record.skillWeightsRaw = NFTelemetryCodec.encode(
            assessmentDescriptor.map { [$0.skillID: 1.0] } ?? exercise.skillWeights
        )
        record.domainContextRaw = exercise.sourceContext.primaryField.rawValue
        record.transferBriefRaw = exercise.sourceContext.transferBrief.map(NFTelemetryCodec.encode) ?? ""
        record.spatialDifficultyParametersRaw = exercise.spatialDifficultyParameters.map(NFTelemetryCodec.encode) ?? ""
        record.shownAt = shownAt
        record.submittedAt = Date()
        record.activeDurationSeconds = max(0, activeDuration)
        record.evidenceWeight = assessmentDescriptor?.assessmentWeight
            ?? (exercise.evidenceClass == .documentPractice ? 0 : 1)
        record.errorCode = result.errorCode
        record.scoringVersion = result.scoringVersion
        record.correctAnswerText = result.expectedAnswerSummary ?? ""
        record.responseFormatRaw = response.responseFormatRaw
        record.sourceDocumentIDsRaw = exercise.provenance.sourceDocumentIDs.joined(separator: ",")
        record.sourceChunkIDsRaw = exercise.provenance.sourceChunkIDs.joined(separator: ",")
        record.validationVersion = exercise.provenance.validatorVersion
        record.assessmentBlockRaw = assessmentBlock?.rawValue
        record.assessmentDescriptorID = assessmentDescriptor?.id ?? assessmentDescriptorID
        record.assessmentTemplateFamily = assessmentDescriptor?.templateFamily
            ?? retentionTarget?.templateFamily
        record.assessmentFormatRaw = assessmentDescriptor?.format.rawValue
            ?? retentionTarget.map { _ in NFRetentionRepresentation.identifier(for: exercise) }
        // This column also carries the stable requested mechanic for ordinary
        // deterministic practice. The historical name is retained for schema
        // compatibility, while exports continue to expose the exact value.
        record.assessmentMechanicID = assessmentDescriptor?.mechanicID
            ?? activeSessionRequest?.mechanicID
        record.assessmentSubskillID = assessmentDescriptor?.subskillID
        record.assessmentSeed = assessmentDescriptor?.seed ?? retentionTarget?.alternateSeed
        record.assessmentCycle = assessmentCycle
        record.planID = planID
        record.planBlockID = planBlockID
        record.deterministicCredit = min(1, max(0, result.credit))
        record.hintCount = max(0, hintCount)
        record.inputModeRaw = NFInputModality(rawValue: inputMode)?.rawValue
            ?? NFInputModality.unknown.rawValue
        record.interruptionCount = max(0, interruptionCount)
        record.revisionCount = max(0, revisionCount)
        record.accommodationFlagsRaw = accommodationFlags.sorted().joined(separator: ",")
        record.wasTimed = wasTimed
        try NFTransferTaxonomy.validate(exercise: exercise)
        try NFTransferTaxonomy.validate(attempt: record)
        try insertAttempt(record)
    }

    /// Persists a personal AI Practice Studio response using the exact typed
    /// exercise and deterministic scorer that were stored with the question.
    /// `attemptID` is retained by the runtime across retries so a transient
    /// save error cannot create a duplicate answer.
    func saveAuthoredExerciseAttempt(
        attemptID: UUID,
        generationID: UUID,
        question: NFAuthoredQuestion,
        response: NFExerciseResponse,
        score: NFExerciseScoringResult,
        confidence: ConfidenceLevel,
        sourceDocumentIDs: [UUID],
        shownAt: Date,
        activeDuration: TimeInterval
    ) throws {
        let exercise = question.authoritativeExercise
        guard NFAuthoredExerciseAuthority.validatesBinding(question),
              exercise.evidenceClass == .documentPractice,
              score == NFExerciseScoringEngine.score(response, for: exercise),
              Set(exercise.provenance.sourceDocumentIDs) == Set(sourceDocumentIDs.map(\.uuidString))
                || exercise.provenance.sourceDocumentIDs == ["legacy-personal-document"] else {
            throw LocalDataError.verificationFailed
        }
        try saveExerciseAttempt(
            attemptID: attemptID,
            sessionID: generationID,
            exercise: exercise,
            response: response,
            result: score,
            confidence: confidence,
            shownAt: shownAt,
            activeDuration: activeDuration,
            source: .focused,
            generationID: generationID
        )
    }

    func reflectionTrigger(
        for result: NFExerciseScoringResult,
        confidence: ConfidenceLevel,
        exercise: NFExercise,
        source: SessionSource
    ) -> NFAttemptReflectionTrigger? {
        guard !exercise.assessmentProtected, !result.feedback.isDelayed else { return nil }
        if !result.isCorrect,
           confidence.probability >= ConfidenceLevel.fairlyConfident.probability {
            return .highConfidenceError
        }
        if !result.isCorrect, let code = result.errorCode {
            let recentMatches = attempts.lazy
                .filter { !$0.wasSkipped && $0.gameID == exercise.lab.rawValue }
                .prefix(10)
                .filter { $0.errorCode == code }
                .count
            if recentMatches >= 2 { return .repeatedError }
            if ["operation_selection", "ordered_steps_sequence", "logic_rule", "claim_evidence_support"]
                .contains(code) {
                return .strategyMismatch
            }
        }
        if source == .weeklyMission { return .weeklyTransfer }
        return nil
    }

    func saveAttemptReflection(
        attemptID: UUID,
        deterministicErrorCode: String?,
        selectedErrorCode: NFErrorReflectionCode?,
        trigger: NFAttemptReflectionTrigger,
        note: String
    ) throws {
        let normalizedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalizedNote.count <= AttemptReflectionRecord.maximumNoteCharacters else {
            let error = NFAttemptReflectionPersistenceError.noteTooLong(
                maximum: AttemptReflectionRecord.maximumNoteCharacters
            )
            lastErrorMessage = error.localizedDescription
            throw error
        }
        guard attempts.contains(where: { $0.id == attemptID }) else {
            throw LocalDataError.missingAttempt
        }
        if attemptReflections.contains(where: { $0.attemptID == attemptID }) { return }
        if trigger != .weeklyTransfer, selectedErrorCode == nil {
            throw LocalDataError.incompleteReflection
        }
        if trigger == .weeklyTransfer,
           normalizedNote.isEmpty {
            throw LocalDataError.incompleteReflection
        }
        let reflection = AttemptReflectionRecord(
            attemptID: attemptID,
            deterministicErrorCode: deterministicErrorCode,
            selectedErrorCode: selectedErrorCode,
            trigger: trigger,
            note: normalizedNote
        )
        context.insert(reflection)
        do {
            try context.save()
            attemptReflections.insert(reflection, at: 0)
            lastErrorMessage = nil
        } catch {
            context.delete(reflection)
            lastErrorMessage = NFAppLocalization.localized("The reflection could not be saved locally. Your scored attempt is unchanged; retry the reflection.", locale: NFAppLocalization.preferredLocale, comment: "Error shown when an item-level learner reflection could not be persisted.")
            throw error
        }
    }

    func effectiveErrorCode(for attempt: AttemptRecord) -> String? {
        attemptReflections.first(where: { $0.attemptID == attempt.id })?.selectedErrorCodeRaw
            ?? attempt.errorCode
    }

    func saveSkippedExercise(
        attemptID: UUID,
        sessionID: UUID,
        exercise: NFExercise,
        shownAt: Date,
        activeDuration: TimeInterval,
        source: SessionSource,
        assessmentBlock: NFAssessmentBlockKind? = nil,
        assessmentDescriptor: NFAssessmentItemDescriptor? = nil,
        assessmentCycle: Int? = nil,
        planID: String? = nil,
        planBlockID: String? = nil,
        interruptionCount: Int = 0,
        accommodationFlags: [String] = [],
        wasTimed: Bool = false
    ) throws {
        let retentionTarget = retentionTarget(
            for: exercise,
            planID: planID,
            planBlockID: planBlockID
        )
        let record = AttemptRecord(
            sessionID: sessionID,
            lab: exercise.lab,
            itemID: exercise.id,
            prompt: exercise.prompt,
            response: "",
            correctAnswer: "Not evaluated",
            isCorrect: false,
            confidence: .guessing,
            evidenceClass: exercise.evidenceClass,
            source: source
        )
        record.id = attemptID
        record.templateID = retentionTarget?.memoryItemID ?? exercise.templateID
        record.seed = exercise.seed
        record.skillID = assessmentDescriptor?.skillID
            ?? exercise.skillWeights.max(by: { $0.value < $1.value })?.key
            ?? exercise.lab.skillID
        record.skillWeightsRaw = NFTelemetryCodec.encode(
            assessmentDescriptor.map { [$0.skillID: 1.0] } ?? exercise.skillWeights
        )
        record.domainContextRaw = exercise.sourceContext.primaryField.rawValue
        record.transferBriefRaw = exercise.sourceContext.transferBrief.map(NFTelemetryCodec.encode) ?? ""
        record.spatialDifficultyParametersRaw = exercise.spatialDifficultyParameters.map(NFTelemetryCodec.encode) ?? ""
        record.confidenceRaw = nil
        record.shownAt = shownAt
        record.submittedAt = Date()
        record.activeDurationSeconds = max(0, activeDuration)
        record.evidenceWeight = 0
        record.deterministicCredit = 0
        record.errorCode = nil
        record.correctAnswerText = "Not evaluated"
        record.responseFormatRaw = "skipped"
        record.inputModeRaw = "skipped"
        record.wasSkipped = true
        record.sourceDocumentIDsRaw = exercise.provenance.sourceDocumentIDs.joined(separator: ",")
        record.sourceChunkIDsRaw = exercise.provenance.sourceChunkIDs.joined(separator: ",")
        record.validationVersion = exercise.provenance.validatorVersion
        record.assessmentBlockRaw = assessmentBlock?.rawValue
        record.assessmentDescriptorID = assessmentDescriptor?.id
        record.assessmentTemplateFamily = assessmentDescriptor?.templateFamily
            ?? retentionTarget?.templateFamily
        record.assessmentFormatRaw = assessmentDescriptor?.format.rawValue
            ?? retentionTarget.map { _ in NFRetentionRepresentation.identifier(for: exercise) }
        record.assessmentMechanicID = assessmentDescriptor?.mechanicID
            ?? activeSessionRequest?.mechanicID
        record.assessmentSubskillID = assessmentDescriptor?.subskillID
        record.assessmentSeed = assessmentDescriptor?.seed ?? retentionTarget?.alternateSeed
        record.assessmentCycle = assessmentCycle
        record.planID = planID
        record.planBlockID = planBlockID
        record.interruptionCount = max(0, interruptionCount)
        record.accommodationFlagsRaw = accommodationFlags.sorted().joined(separator: ",")
        record.wasTimed = wasTimed
        try insertAttempt(record)
    }

    func saveAIGeneration(request: NFAuthoringRequest, result: NFAuthoringResult) throws {
        if aiGenerations.contains(where: { $0.id == result.provenance.requestID }) { return }
        let record = try AIGenerationRecord(request: request, result: result)
        context.insert(record)
        _ = enforceAIGenerationPayloadBounds(on: [record] + aiGenerations)
        do {
            try context.save()
            aiGenerations.insert(record, at: 0)
        } catch {
            context.delete(record)
            lastErrorMessage = NFAppLocalization.localized("The questions are still available, but their AI provenance could not be saved.", locale: NFAppLocalization.preferredLocale, comment: "Non-destructive AI-generation provenance persistence error.")
            throw error
        }
    }

    func recoverAIGeneration(id: UUID, at date: Date = Date()) -> NFAuthoringResult? {
        aiGenerations.first(where: { $0.id == id })?.recoverableResult(at: date)
    }

    func discardAIGenerationPayload(id: UUID) throws {
        guard let record = aiGenerations.first(where: { $0.id == id }) else { return }
        record.discardPayload()
        do {
            try context.save()
        } catch {
            context.rollback()
            reload()
            lastErrorMessage = NFAppLocalization.localized(
                "The question set could not be removed. Try again.",
                locale: NFAppLocalization.preferredLocale,
                comment: "Error after removing a recoverable generated question set."
            )
            throw error
        }
    }

    /// Deletes the learner's personal attempts for one generated set without
    /// conflating them with the separately retained question payload or its
    /// lightweight provenance record.
    @discardableResult
    func deleteAIGenerationAttempts(id: UUID) throws -> Int {
        let saved = attempts.filter { $0.generationID == id }
        let pending = pendingAttemptRecords.filter { $0.generationID == id }
        let identifiers = Set((saved + pending).map(\.id))
        guard !identifiers.isEmpty else { return 0 }
        let reflections = attemptReflections.filter { identifiers.contains($0.attemptID) }

        for attempt in saved { context.delete(attempt) }
        for attempt in pending { context.delete(attempt) }
        for reflection in reflections { context.delete(reflection) }
        do {
            try context.save()
            attempts.removeAll { identifiers.contains($0.id) }
            pendingAttemptRecords.removeAll { identifiers.contains($0.id) }
            attemptReflections.removeAll { identifiers.contains($0.attemptID) }
            return identifiers.count
        } catch {
            context.rollback()
            reload()
            lastErrorMessage = NFAppLocalization.localized(
                "The attempt history could not be deleted. Try again.",
                locale: NFAppLocalization.preferredLocale,
                comment: "Error after deleting personal attempt history for one generated question set."
            )
            throw error
        }
    }

    @discardableResult
    func purgeExpiredAIGenerationPayloads(at date: Date = Date()) throws -> Int {
        let expiredOrInvalidCount = aiGenerations.count { $0.discardExpiredOrInvalidPayload(at: date) }
        let overLimitCount = enforceAIGenerationPayloadBounds(on: aiGenerations)
        let discardedCount = expiredOrInvalidCount + overLimitCount
        guard discardedCount > 0 else { return 0 }
        do {
            try context.save()
            return discardedCount
        } catch {
            context.rollback()
            reload()
            lastErrorMessage = NFAppLocalization.localized("Expired generated-question payloads could not be cleared; provenance records were left intact.", locale: NFAppLocalization.preferredLocale, comment: "Generated-question cache cleanup error.")
            throw error
        }
    }

    var generatedQuestionCacheBytes: Int64 {
        aiGenerations.reduce(0) { $0 + Int64($1.resultPayload.count) }
    }

    func expiredAIGenerationPayloadCount(at date: Date = Date()) -> Int {
        aiGenerations.count { !$0.resultPayload.isEmpty && $0.recoverableResult(at: date) == nil }
    }

    private func enforceAIGenerationPayloadBounds(on records: [AIGenerationRecord]) -> Int {
        let newestFirst = records.sorted { lhs, rhs in
            if lhs.createdAt == rhs.createdAt { return lhs.id.uuidString > rhs.id.uuidString }
            return lhs.createdAt > rhs.createdAt
        }
        var retainedCount = 0
        var retainedBytes: Int64 = 0
        var discardedCount = 0
        for record in newestFirst where !record.resultPayload.isEmpty {
            let byteCount = Int64(record.resultPayload.count)
            let fitsCount = retainedCount < AIGenerationRecord.maximumPersistedPayloadCount
            let fitsBytes = byteCount <= AIGenerationRecord.maximumPersistedPayloadBytes - retainedBytes
            if fitsCount && fitsBytes {
                retainedCount += 1
                retainedBytes += byteCount
            } else {
                record.discardPayload()
                discardedCount += 1
            }
        }
        return discardedCount
    }

    func saveItemReport(item: MentalMathItem, reason: String, note: String) throws {
        let report = ItemReportRecord(item: item, reason: reason, note: note)
        try insertItemReport(report)
    }

    func saveItemReport(
        exercise: NFExercise,
        assessmentDescriptorID: String? = nil,
        reason: String,
        note: String
    ) throws {
        let report = ItemReportRecord(
            exercise: exercise,
            assessmentDescriptorID: assessmentDescriptorID,
            reason: reason,
            note: note
        )
        try insertItemReport(report)
    }

    func saveItemReport(
        question: NFAuthoredQuestion,
        result: NFAuthoringResult,
        reason: String,
        note: String
    ) throws {
        try insertItemReport(ItemReportRecord(
            question: question,
            result: result,
            reason: reason,
            note: note
        ))
    }

    func isQuarantined(question: NFAuthoredQuestion, in result: NFAuthoringResult) -> Bool {
        let identity = ItemReportRecord.authoredItemIdentity(
            question: question,
            provenance: result.provenance
        )
        return itemReports.contains { $0.status == "quarantined" && $0.itemID == identity }
    }

    private func insertItemReport(_ report: ItemReportRecord) throws {
        context.insert(report)
        do {
            try context.save()
            itemReports.insert(report, at: 0)
            nextDayEnhancementCache.removeAll()
            lastErrorMessage = nil
        } catch {
            context.delete(report)
            lastErrorMessage = NFAppLocalization.localized("The report remains on screen but could not be saved locally.", locale: NFAppLocalization.preferredLocale, comment: "Private item-report persistence error.")
            throw error
        }
    }

    func allowReportedItemAgain(_ report: ItemReportRecord) {
        let matchingReports = itemReports.filter { candidate in
            guard candidate.status == "quarantined" else { return false }
            if candidate.itemID == report.itemID { return true }
            guard let descriptorID = report.assessmentDescriptorID else { return false }
            return candidate.assessmentDescriptorID == descriptorID
        }
        guard !matchingReports.isEmpty else { return }
        for candidate in matchingReports { candidate.status = "retryAllowed" }
        do {
            try context.save()
            nextDayEnhancementCache.removeAll()
            reload()
            lastErrorMessage = nil
            notice = AppNotice(
                title: NFAppLocalization.localized("Item allowed again", locale: NFAppLocalization.preferredLocale, comment: "Confirmation after removing a reported item from local quarantine."),
                message: NFAppLocalization.localized("Future sessions may schedule this exact item again. The original report remains in your export.", locale: NFAppLocalization.preferredLocale, comment: "Confirmation after removing a reported item from local quarantine.")
            )
        } catch {
            context.rollback()
            reload()
            lastErrorMessage = NFAppLocalization.localized("The item remains quarantined because the retry preference could not be saved.", locale: NFAppLocalization.preferredLocale, comment: "Reported-item quarantine preference persistence error.")
            notice = AppNotice(
                title: NFAppLocalization.localized("Preference not saved", locale: NFAppLocalization.preferredLocale, comment: "Title for a local preference persistence error."),
                message: lastErrorMessage ?? NFAppLocalization.localized("Retry the action.", locale: NFAppLocalization.preferredLocale, comment: "Generic recovery suggestion after a local persistence error.")
            )
        }
    }

    @discardableResult
    func importDocumentAsync(
        from sourceURL: URL,
        progress: @escaping @MainActor (NFDocumentImportStage) -> Void
    ) async throws -> SourceDocumentRecord {
        progress(.copying)
        let managedStorageRootURL = try managedDocumentFolderURL()
        let copy = try await NFDocumentImportPipeline.copyIntoManagedStorage(
            from: sourceURL,
            managedStorageRootURL: managedStorageRootURL
        )
        do {
            try Task.checkCancellation()
            progress(.extracting)
            let extraction: NFSourceExtraction?
            let extractionDiagnostic: String?
            do {
                extraction = try await NFDocumentImportPipeline.extract(copy)
                extractionDiagnostic = extraction?.warning
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                extraction = nil
                extractionDiagnostic = NFDiagnosticRedactor.persistedMessage(
                    for: error,
                    context: .documentExtraction
                )
            }

            try Task.checkCancellation()
            progress(.saving)
            let record = SourceDocumentRecord(
                filename: copy.filename,
                typeIdentifier: copy.typeIdentifier,
                sizeBytes: copy.sizeBytes,
                localPath: copy.destinationURL.path
            )
            record.id = copy.documentID
            let extractedRecords = extraction?.chunks.map(SourceChunkRecord.init(chunk:)) ?? []
            record.characterCount = extraction?.characterCount ?? 0
            record.chunkCount = extractedRecords.count
            record.extractionVersion = extraction == nil ? 0 : NFSourceExtractor.extractorVersion
            record.indexState = extraction == nil ? "extractionFailed" : "ready"
            record.indexError = extractionDiagnostic
            context.insert(record)
            for chunk in extractedRecords { context.insert(chunk) }
            do {
                try context.save()
                documents.insert(record, at: 0)
                sourceChunks.append(contentsOf: extractedRecords)
                lastErrorMessage = nil
                progress(.complete)
                return record
            } catch {
                context.rollback()
                reload()
                NFDocumentImportPipeline.removeManagedCopy(copy)
                lastErrorMessage = NFAppLocalization.localized("The import was rolled back because its metadata could not be saved.", locale: NFAppLocalization.preferredLocale, comment: "Study-material import persistence error.")
                throw error
            }
        } catch {
            NFDocumentImportPipeline.removeManagedCopy(copy)
            throw error
        }
    }

    func retryDocumentExtraction(for document: SourceDocumentRecord) async throws {
        guard documents.contains(where: { $0.id == document.id }) else {
            throw LocalDataError.missingDocument
        }
        let priorDiagnostic = document.indexError
        document.indexState = "extracting"
        document.indexError = nil
        try context.save()
        let copy = NFManagedDocumentCopy(
            documentID: document.id,
            filename: document.filename,
            typeIdentifier: document.typeIdentifier,
            sizeBytes: document.sizeBytes,
            destinationURL: URL(fileURLWithPath: document.localPath)
        )
        do {
            let csvSelection = document.csvSelectedColumnIDs.isEmpty
                ? nil
                : NFCSVColumnSelection(columnIDs: document.csvSelectedColumnIDs)
            let extraction = try await NFDocumentImportPipeline.extract(
                copy,
                csvSelection: csvSelection
            )
            try Task.checkCancellation()
            guard let persisted = documents.first(where: { $0.id == document.id }) else {
                throw LocalDataError.missingDocument
            }
            let priorChunks = sourceChunks.filter { $0.documentID == document.id }
            for chunk in priorChunks { context.delete(chunk) }
            let replacements = extraction.chunks.map(SourceChunkRecord.init(chunk:))
            for chunk in replacements { context.insert(chunk) }
            persisted.characterCount = extraction.characterCount
            persisted.chunkCount = replacements.count
            persisted.extractionVersion = NFSourceExtractor.extractorVersion
            persisted.indexState = "ready"
            persisted.indexError = extraction.warning
            try context.save()
            sourceChunks.removeAll { $0.documentID == document.id }
            sourceChunks.append(contentsOf: replacements)
            lastErrorMessage = nil
        } catch {
            context.rollback()
            reload()
            if let persisted = documents.first(where: { $0.id == document.id }) {
                persisted.indexState = "extractionFailed"
                persisted.indexError = error is CancellationError
                    ? priorDiagnostic
                    : NFDiagnosticRedactor.persistedMessage(for: error, context: .documentExtraction)
                try? context.save()
            }
            throw error
        }
    }

    func csvPreview(for document: SourceDocumentRecord) async throws -> NFCSVSchemaPreview {
        guard documents.contains(where: { $0.id == document.id }) else {
            throw LocalDataError.missingDocument
        }
        return try await NFDocumentImportPipeline.csvPreview(NFManagedDocumentCopy(
            documentID: document.id,
            filename: document.filename,
            typeIdentifier: document.typeIdentifier,
            sizeBytes: document.sizeBytes,
            destinationURL: URL(fileURLWithPath: document.localPath)
        ))
    }

    func updateCSVColumnSelection(
        for document: SourceDocumentRecord,
        selection: NFCSVColumnSelection
    ) async throws {
        guard documents.contains(where: { $0.id == document.id }) else {
            throw LocalDataError.missingDocument
        }
        let priorIndexState = document.indexState
        let priorDiagnostic = document.indexError
        document.indexState = "extracting"
        document.indexError = nil
        try context.save()
        let copy = NFManagedDocumentCopy(
            documentID: document.id,
            filename: document.filename,
            typeIdentifier: document.typeIdentifier,
            sizeBytes: document.sizeBytes,
            destinationURL: URL(fileURLWithPath: document.localPath)
        )
        do {
            let extraction = try await NFDocumentImportPipeline.extract(
                copy,
                csvSelection: selection
            )
            try Task.checkCancellation()
            guard let persisted = documents.first(where: { $0.id == document.id }) else {
                throw LocalDataError.missingDocument
            }
            let priorChunks = sourceChunks.filter { $0.documentID == document.id }
            for chunk in priorChunks { context.delete(chunk) }
            let replacements = extraction.chunks.map(SourceChunkRecord.init(chunk:))
            for chunk in replacements { context.insert(chunk) }
            persisted.csvSelectedColumnIDsRaw = selection.columnIDs.joined(separator: "\u{001F}")
            persisted.characterCount = extraction.characterCount
            persisted.chunkCount = replacements.count
            persisted.extractionVersion = NFSourceExtractor.extractorVersion
            persisted.indexState = "ready"
            persisted.indexError = extraction.warning
            try context.save()
            sourceChunks.removeAll { $0.documentID == document.id }
            sourceChunks.append(contentsOf: replacements)
            lastErrorMessage = nil
        } catch {
            context.rollback()
            reload()
            if let persisted = documents.first(where: { $0.id == document.id }) {
                persisted.indexState = priorIndexState
                persisted.indexError = error is CancellationError
                    ? priorDiagnostic
                    : NFDiagnosticRedactor.persistedMessage(for: error, context: .documentExtraction)
                try? context.save()
            }
            throw error
        }
    }

    func materializeSyncedDocument(_ revision: NFDocumentOriginalRevision) async throws {
        guard documents.contains(where: { $0.id == revision.documentID }) == false else { return }
        try Task.checkCancellation()
        guard !revision.localFilePath.isEmpty else {
            throw NFDocumentAssetIntegrityError.unreadableFile
        }
        let sourceURL = URL(fileURLWithPath: revision.localFilePath)
        let folder = try managedDocumentFolderURL()
        let safeFilename = URL(fileURLWithPath: revision.filename).lastPathComponent
        let displayFilename = safeFilename.isEmpty ? "Synced Document" : String(safeFilename.prefix(180))
        let applicationNonce = UUID().uuidString.prefix(12)
        let prepared = try await NFDocumentImportPipeline.copyVerifiedSyncedOriginal(
            from: sourceURL,
            expectedContentHash: revision.contentHash,
            managedStorageRootURL: folder,
            storageFilename: "\(revision.documentID.uuidString)-\(revision.contentHash.prefix(16))-\(applicationNonce)-\(displayFilename)",
            documentID: revision.documentID,
            displayFilename: displayFilename,
            typeIdentifier: revision.typeIdentifier,
            sizeBytes: revision.sizeBytes
        )
        do {
            let extraction: NFSourceExtraction?
            let extractionDiagnostic: String?
            do {
                extraction = try await NFDocumentImportPipeline.extract(prepared.copy)
                extractionDiagnostic = extraction?.warning
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                extraction = nil
                extractionDiagnostic = NFDiagnosticRedactor.persistedMessage(
                    for: error,
                    context: .documentExtraction
                )
            }
            try Task.checkCancellation()

            // Another received revision may have converged this identity while
            // detached file work was in flight.
            guard documents.contains(where: { $0.id == revision.documentID }) == false else {
                if prepared.createdDestination {
                    await NFDocumentImportPipeline.removeManagedFile(
                        at: prepared.copy.destinationURL,
                        managedStorageRootURL: folder
                    )
                }
                return
            }

            let record = SourceDocumentRecord(
                filename: displayFilename,
                typeIdentifier: revision.typeIdentifier,
                sizeBytes: revision.sizeBytes,
                localPath: prepared.copy.destinationURL.path
            )
            record.id = revision.documentID
            record.importedAt = revision.modifiedAt
            record.modifiedAt = revision.modifiedAt
            record.aiPolicyRaw = revision.aiPolicyRaw
            record.syncPolicy = NFDocumentSyncPolicy.privateOriginal.rawValue
            record.pccExcerptConsentPolicyVersion = revision.pccConsentPolicyVersion
            record.pccExcerptConsentedAt = revision.pccConsentedAt
            record.pccExcerptConsentDocumentIDRaw = revision.pccConsentedAt == nil
                ? ""
                : revision.documentID.uuidString
            let extractedRecords = extraction?.chunks.map(SourceChunkRecord.init(chunk:)) ?? []
            record.characterCount = extraction?.characterCount ?? 0
            record.chunkCount = extractedRecords.count
            record.extractionVersion = extraction == nil ? 0 : NFSourceExtractor.extractorVersion
            record.indexState = extraction == nil ? "extractionFailed" : "ready"
            record.indexError = extractionDiagnostic

            context.insert(record)
            for chunk in extractedRecords { context.insert(chunk) }
            do {
                try context.save()
                documents.insert(record, at: 0)
                sourceChunks.append(contentsOf: extractedRecords)
                lastErrorMessage = nil
            } catch {
                context.rollback()
                reload()
                throw error
            }
        } catch {
            if prepared.createdDestination {
                await NFDocumentImportPipeline.removeManagedFile(
                    at: prepared.copy.destinationURL,
                    managedStorageRootURL: folder
                )
            }
            throw error
        }
    }

    /// Applies a conflict-winning private-cloud revision to the device-local
    /// mirror. Device paths and extracted caches never participate in conflict
    /// resolution, and an explicit local-only policy is never overwritten by a
    /// remote link record.
    @discardableResult
    func reconcileSyncedDocument(_ revision: NFDocumentOriginalRevision) async throws -> Bool {
        try await reconcileSyncedDocument(revision, remainingSnapshotRetries: 2)
    }

    private func reconcileSyncedDocument(
        _ revision: NFDocumentOriginalRevision,
        remainingSnapshotRetries: Int
    ) async throws -> Bool {
        guard let document = documents.first(where: { $0.id == revision.documentID }) else {
            try await materializeSyncedDocument(revision)
            return true
        }
        guard NFDocumentSyncPolicy(rawValue: document.syncPolicy) == .privateOriginal else {
            return false
        }

        try Task.checkCancellation()
        let remoteURL = URL(fileURLWithPath: revision.localFilePath)
        guard !revision.localFilePath.isEmpty else {
            throw NFDocumentAssetIntegrityError.unreadableFile
        }
        let localURL = URL(fileURLWithPath: document.localPath)
        let snapshotFilename = document.filename
        let snapshotTypeIdentifier = document.typeIdentifier
        let snapshotSizeBytes = document.sizeBytes
        let snapshotLocalPath = document.localPath
        let snapshotModifiedAt = document.modifiedAt
        let snapshotAIPolicyRaw = document.aiPolicyRaw
        let snapshotConsentVersion = document.pccExcerptConsentPolicyVersion
        let snapshotConsentedAt = document.pccExcerptConsentedAt
        let snapshotCSVSelectedColumnIDsRaw = document.csvSelectedColumnIDsRaw
        let inspection = try await NFDocumentImportPipeline.inspectSyncedOriginal(
            remoteURL: remoteURL,
            expectedContentHash: revision.contentHash,
            localURL: localURL
        )

        guard let currentDocument = documents.first(where: { $0.id == revision.documentID }) else {
            try await materializeSyncedDocument(revision)
            return true
        }
        guard NFDocumentSyncPolicy(rawValue: currentDocument.syncPolicy) == .privateOriginal else {
            return false
        }
        guard currentDocument.filename == snapshotFilename,
              currentDocument.typeIdentifier == snapshotTypeIdentifier,
              currentDocument.sizeBytes == snapshotSizeBytes,
              currentDocument.localPath == snapshotLocalPath,
              currentDocument.modifiedAt == snapshotModifiedAt,
              currentDocument.aiPolicyRaw == snapshotAIPolicyRaw,
              currentDocument.pccExcerptConsentPolicyVersion == snapshotConsentVersion,
              currentDocument.pccExcerptConsentedAt == snapshotConsentedAt,
              currentDocument.csvSelectedColumnIDsRaw == snapshotCSVSelectedColumnIDsRaw else {
            guard remainingSnapshotRetries > 0 else { return false }
            return try await reconcileSyncedDocument(
                revision,
                remainingSnapshotRetries: remainingSnapshotRetries - 1
            )
        }

        let localHash = inspection.localContentHash
        if let localHash {
            let localRevision = NFDocumentOriginalRevision(
                documentID: currentDocument.id,
                contentHash: localHash,
                filename: snapshotFilename,
                typeIdentifier: snapshotTypeIdentifier,
                sizeBytes: snapshotSizeBytes,
                localFilePath: snapshotLocalPath,
                modifiedAt: snapshotModifiedAt,
                aiPolicyRaw: snapshotAIPolicyRaw,
                pccConsentPolicyVersion: snapshotConsentVersion,
                pccConsentedAt: snapshotConsentedAt
            )
            if localRevision.isSemanticallyEqual(to: revision) { return false }
            let winner = NFDocumentOriginalConflictPolicy.winner(localRevision, revision)
            guard winner.isSemanticallyEqual(to: revision) else { return false }
        }

        let safeFilename = URL(fileURLWithPath: revision.filename).lastPathComponent
        let displayFilename = safeFilename.isEmpty ? "Synced Document" : String(safeFilename.prefix(180))
        let contentChanged = localHash != revision.contentHash
        var replacementURL = localURL
        var preparedReplacement: NFPreparedSyncedDocumentCopy?
        var replacementChunks: [SourceChunkRecord] = []
        var extractionFailure: String?
        var extractionCharacterCount = currentDocument.characterCount
        var extractionVersion = currentDocument.extractionVersion
        let folder = try managedDocumentFolderURL()
        var documentForUpdate = currentDocument

        if contentChanged {
            let applicationNonce = UUID().uuidString.prefix(12)
            let prepared = try await NFDocumentImportPipeline.copyVerifiedSyncedOriginal(
                from: remoteURL,
                expectedContentHash: revision.contentHash,
                managedStorageRootURL: folder,
                storageFilename: "\(revision.documentID.uuidString)-\(revision.contentHash.prefix(16))-\(applicationNonce)-\(displayFilename)",
                documentID: revision.documentID,
                displayFilename: displayFilename,
                typeIdentifier: revision.typeIdentifier,
                sizeBytes: revision.sizeBytes
            )
            preparedReplacement = prepared
            replacementURL = prepared.copy.destinationURL

            do {
                let selectedColumnIDs = snapshotCSVSelectedColumnIDsRaw
                    .split(separator: "\u{001F}")
                    .map(String.init)
                let extraction = try await NFDocumentImportPipeline.extract(
                    prepared.copy,
                    csvSelection: selectedColumnIDs.isEmpty
                        ? nil
                        : NFCSVColumnSelection(columnIDs: selectedColumnIDs)
                )
                replacementChunks = extraction.chunks.map(SourceChunkRecord.init(chunk:))
                extractionCharacterCount = extraction.characterCount
                extractionVersion = NFSourceExtractor.extractorVersion
                extractionFailure = extraction.warning
            } catch is CancellationError {
                if prepared.createdDestination {
                    await NFDocumentImportPipeline.removeManagedFile(
                        at: prepared.copy.destinationURL,
                        managedStorageRootURL: folder
                    )
                }
                throw CancellationError()
            } catch {
                extractionCharacterCount = 0
                extractionVersion = NFSourceExtractor.extractorVersion
                extractionFailure = NFDiagnosticRedactor.persistedMessage(
                    for: error,
                    context: .documentExtraction
                )
            }
            do {
                try Task.checkCancellation()
            } catch {
                if prepared.createdDestination {
                    await NFDocumentImportPipeline.removeManagedFile(
                        at: prepared.copy.destinationURL,
                        managedStorageRootURL: folder
                    )
                }
                throw error
            }

            guard let refreshedDocument = documents.first(where: { $0.id == revision.documentID }),
                  NFDocumentSyncPolicy(rawValue: refreshedDocument.syncPolicy) == .privateOriginal,
                  refreshedDocument.filename == snapshotFilename,
                  refreshedDocument.typeIdentifier == snapshotTypeIdentifier,
                  refreshedDocument.sizeBytes == snapshotSizeBytes,
                  refreshedDocument.localPath == snapshotLocalPath,
                  refreshedDocument.modifiedAt == snapshotModifiedAt,
                  refreshedDocument.aiPolicyRaw == snapshotAIPolicyRaw,
                  refreshedDocument.pccExcerptConsentPolicyVersion == snapshotConsentVersion,
                  refreshedDocument.pccExcerptConsentedAt == snapshotConsentedAt,
                  refreshedDocument.csvSelectedColumnIDsRaw == snapshotCSVSelectedColumnIDsRaw else {
                if prepared.createdDestination {
                    await NFDocumentImportPipeline.removeManagedFile(
                        at: prepared.copy.destinationURL,
                        managedStorageRootURL: folder
                    )
                }
                guard remainingSnapshotRetries > 0 else { return false }
                return try await reconcileSyncedDocument(
                    revision,
                    remainingSnapshotRetries: remainingSnapshotRetries - 1
                )
            }
            documentForUpdate = refreshedDocument
        }

        documentForUpdate.filename = displayFilename
        documentForUpdate.typeIdentifier = revision.typeIdentifier
        documentForUpdate.sizeBytes = revision.sizeBytes
        documentForUpdate.localPath = replacementURL.path
        documentForUpdate.modifiedAt = revision.modifiedAt
        documentForUpdate.aiPolicyRaw = revision.aiPolicyRaw
        documentForUpdate.pccExcerptConsentPolicyVersion = revision.pccConsentPolicyVersion
        documentForUpdate.pccExcerptConsentedAt = revision.pccConsentedAt
        documentForUpdate.pccExcerptConsentDocumentIDRaw = revision.pccConsentedAt == nil
            ? ""
            : revision.documentID.uuidString

        if contentChanged {
            for chunk in sourceChunks where chunk.documentID == documentForUpdate.id {
                context.delete(chunk)
            }
            for generation in aiGenerations where generation.sourceDocumentIDsRaw
                .split(separator: ",").contains(Substring(documentForUpdate.id.uuidString)) {
                context.delete(generation)
            }
            for chunk in replacementChunks { context.insert(chunk) }
            documentForUpdate.characterCount = extractionCharacterCount
            documentForUpdate.chunkCount = replacementChunks.count
            documentForUpdate.extractionVersion = extractionVersion
            documentForUpdate.indexState = extractionFailure == nil ? "ready" : "extractionFailed"
            documentForUpdate.indexError = extractionFailure
        } else {
            for chunk in sourceChunks where chunk.documentID == documentForUpdate.id {
                chunk.sourceName = displayFilename
            }
        }

        do {
            try context.save()
        } catch {
            context.rollback()
            reload()
            if let preparedReplacement, preparedReplacement.createdDestination {
                await NFDocumentImportPipeline.removeManagedFile(
                    at: preparedReplacement.copy.destinationURL,
                    managedStorageRootURL: folder
                )
            }
            throw error
        }

        reload()
        lastErrorMessage = nil
        if contentChanged, localURL != replacementURL {
            await NFDocumentImportPipeline.removeManagedFile(
                at: localURL,
                managedStorageRootURL: folder
            )
        }
        return true
    }

    /// A tombstone accepted by the transport removes only a document that is
    /// still participating in private-original sync. A document the user made
    /// local-only is deliberately retained on this device.
    @discardableResult
    func applySyncedDocumentTombstone(_ tombstone: NFDocumentOriginalTombstone) throws -> Bool {
        guard let document = documents.first(where: { $0.id == tombstone.documentID }),
              NFDocumentSyncPolicy(rawValue: document.syncPolicy) == .privateOriginal,
              tombstone.deletedAt >= document.modifiedAt else {
            return false
        }
        try deleteDocument(document)
        return true
    }

    func runLocalOCR(for document: SourceDocumentRecord) async throws {
        let url = URL(fileURLWithPath: document.localPath)
        guard url.pathExtension.lowercased() == "pdf" else { throw NFOCRError.unsupportedDocument }

        document.indexState = "extracting"
        document.indexError = "Running explicit on-device Vision OCR…"
        document.modifiedAt = Date()
        try context.save()

        do {
            let extraction = try await NFOCRService.recognizePDF(
                documentID: document.id,
                sourceName: document.filename,
                url: url
            )
            let priorChunks = sourceChunks.filter { $0.documentID == document.id }
            for chunk in priorChunks { context.delete(chunk) }
            let replacementChunks = extraction.chunks.map(SourceChunkRecord.init(chunk:))
            for chunk in replacementChunks { context.insert(chunk) }

            document.characterCount = extraction.characterCount
            document.chunkCount = replacementChunks.count
            document.extractionVersion = NFSourceExtractor.extractorVersion
            document.indexState = "ready"
            document.indexError = extraction.warning
            document.modifiedAt = Date()
            try context.save()

            sourceChunks.removeAll { $0.documentID == document.id }
            sourceChunks.append(contentsOf: replacementChunks)
            lastErrorMessage = nil
            notice = AppNotice(
                title: NFAppLocalization.localized("Local OCR complete", locale: NFAppLocalization.preferredLocale, comment: "Confirmation after on-device optical character recognition finishes."),
                message: NFAppLocalization.localized(
                    "NeuroForge indexed \(NFAppLocalization.formattedChunkCount(replacementChunks.count)). Review equations and symbols against the original scan before relying on them.",
                    locale: NFAppLocalization.preferredLocale,
                    comment: "Confirmation after on-device OCR with a localized indexed-chunk count."
                )
            )
        } catch {
            context.rollback()
            reload()
            if let persisted = documents.first(where: { $0.id == document.id }) {
                persisted.indexState = "extractionFailed"
                persisted.indexError = NFDiagnosticRedactor.persistedMessage(
                    for: error,
                    context: .localOCR
                )
                persisted.modifiedAt = Date()
                try? context.save()
            }
            let safeMessage = NFDiagnosticRedactor.userMessage(for: error, context: .localOCR)
            lastErrorMessage = safeMessage
            notice = AppNotice(
                title: NFAppLocalization.localized("Local OCR did not finish", locale: NFAppLocalization.preferredLocale, comment: "Title for an on-device optical-character-recognition error."),
                message: safeMessage
            )
            throw error
        }
    }

    @discardableResult
    func updateDocumentAIPolicy(
        _ document: SourceDocumentRecord,
        policy: DocumentAIPolicy,
        persist: (() throws -> Void)? = nil
    ) -> Bool {
        document.aiPolicyRaw = policy.rawValue
        document.modifiedAt = Date()
        if policy != .privateCloudAllowed {
            document.pccExcerptConsentPolicyVersion = 0
            document.pccExcerptConsentDocumentIDRaw = ""
            document.pccExcerptConsentedAt = nil
        }
        do {
            if let persist {
                try persist()
            } else {
                try context.save()
            }
            lastErrorMessage = nil
            return true
        } catch {
            context.rollback()
            reload()
            lastErrorMessage = NFAppLocalization.localized("The document preference could not be saved.", locale: NFAppLocalization.preferredLocale, comment: "Per-document AI preference persistence error.")
            notice = AppNotice(
                title: NFAppLocalization.localized("Preference not saved", locale: NFAppLocalization.preferredLocale, comment: "Title for a local preference persistence error."),
                message: lastErrorMessage ?? NFAppLocalization.localized("Retry the change.", locale: NFAppLocalization.preferredLocale, comment: "Recovery suggestion after a local preference persistence error.")
            )
            return false
        }
    }

    @discardableResult
    func updateDocumentSyncPolicy(
        _ document: SourceDocumentRecord,
        policy: NFDocumentSyncPolicy,
        persist: (() throws -> Void)? = nil
    ) -> Bool {
        document.syncPolicy = policy.rawValue
        document.modifiedAt = Date()
        do {
            if let persist {
                try persist()
            } else {
                try context.save()
            }
            lastErrorMessage = nil
            return true
        } catch {
            context.rollback()
            reload()
            lastErrorMessage = NFAppLocalization.localized("The document sync preference could not be saved.",
                locale: NFAppLocalization.preferredLocale,
                comment: "Per-document private iCloud sync preference persistence error."
            )
            notice = AppNotice(
                title: NFAppLocalization.localized("Sync preference not saved",
                    locale: NFAppLocalization.preferredLocale,
                    comment: "Title for a per-document private iCloud sync preference error."
                ),
                message: lastErrorMessage ?? NFAppLocalization.localized("Retry the change.",
                    locale: NFAppLocalization.preferredLocale,
                    comment: "Recovery suggestion after a local preference persistence error."
                )
            )
            return false
        }
    }

    func deleteDocument(_ document: SourceDocumentRecord) throws {
        let fileManager = FileManager.default
        let originalURL = URL(fileURLWithPath: document.localPath)
        let stagedURL = originalURL.appendingPathExtension("pending-deletion-\(UUID().uuidString)")
        var stagedFile = false
        if !document.localPath.isEmpty, fileManager.fileExists(atPath: document.localPath) {
            try fileManager.moveItem(at: originalURL, to: stagedURL)
            stagedFile = true
        }
        let reviewPrefix = "document.\(document.id.uuidString)."
        let documentID = document.id.uuidString
        let linkedAttemptIDs = Set(attempts.lazy.filter { attempt in
            attempt.itemID.hasPrefix(reviewPrefix)
                || attempt.sourceDocumentIDsRaw.split(separator: ",").contains(Substring(documentID))
        }.map(\.id))
        let linkedPendingAttemptIDs = Set(pendingAttemptRecords.lazy.filter { attempt in
            attempt.itemID.hasPrefix(reviewPrefix)
                || attempt.sourceDocumentIDsRaw.split(separator: ",").contains(Substring(documentID))
        }.map(\.id))
        for attempt in attempts where attempt.itemID.hasPrefix(reviewPrefix) {
            context.delete(attempt)
        }
        for attempt in attempts where attempt.sourceDocumentIDsRaw.split(separator: ",").contains(Substring(documentID)) {
            context.delete(attempt)
        }
        for attempt in pendingAttemptRecords where linkedPendingAttemptIDs.contains(attempt.id) {
            context.delete(attempt)
        }
        for reflection in attemptReflections where linkedAttemptIDs.contains(reflection.attemptID) {
            context.delete(reflection)
        }
        for report in itemReports where report.sourceIDsRaw.split(separator: ",").contains(Substring(documentID)) {
            context.delete(report)
        }
        for chunk in sourceChunks where chunk.documentID == document.id {
            context.delete(chunk)
        }
        for generation in aiGenerations where generation.sourceDocumentIDsRaw.split(separator: ",").contains(Substring(documentID)) {
            context.delete(generation)
        }
        context.delete(document)
        do {
            try context.save()
        } catch {
            context.rollback()
            if stagedFile, fileManager.fileExists(atPath: stagedURL.path) {
                try? fileManager.moveItem(at: stagedURL, to: originalURL)
            }
            reload()
            lastErrorMessage = NFAppLocalization.localized("Deletion was rolled back because NeuroForge could not verify every local record. The app-managed file was restored; retry from Library.", locale: NFAppLocalization.preferredLocale, comment: "Transactional study-document deletion error.")
            notice = AppNotice(
                title: NFAppLocalization.localized("Deletion incomplete", locale: NFAppLocalization.preferredLocale, comment: "Title for a transactional local deletion error."),
                message: lastErrorMessage ?? NFAppLocalization.localized("Retry from Library.", locale: NFAppLocalization.preferredLocale, comment: "Recovery suggestion after a study-document deletion error.")
            )
            throw error
        }
        pendingAttemptRecords.removeAll { linkedPendingAttemptIDs.contains($0.id) }
        if stagedFile {
            do {
                try fileManager.removeItem(at: stagedURL)
            } catch {
                reload()
                lastErrorMessage = NFAppLocalization.localized("Database records were deleted, but a staged app-managed file could not be removed. Restart and use Delete all local data before uninstalling.", locale: NFAppLocalization.preferredLocale, comment: "Study-document file cleanup verification error.")
                notice = AppNotice(
                    title: NFAppLocalization.localized("File cleanup incomplete", locale: NFAppLocalization.preferredLocale, comment: "Title for a local file-cleanup verification error."),
                    message: lastErrorMessage ?? NFAppLocalization.localized("Retry local cleanup.", locale: NFAppLocalization.preferredLocale, comment: "Recovery suggestion after a local file-cleanup error.")
                )
                throw error
            }
        }
        reload()
        lastErrorMessage = nil
        notice = AppNotice(
            title: NFAppLocalization.localized("Document deleted", locale: NFAppLocalization.preferredLocale, comment: "Confirmation after verified deletion of a study document."),
            message: NFAppLocalization.localized("The app-managed copy, metadata, source chunks, queued and saved practice history, reports, and AI provenance were removed from this device.", locale: NFAppLocalization.preferredLocale, comment: "Detailed confirmation after verified deletion of a study document.")
        )
    }

    func deleteAllLocalData() throws {
        let fileManager = FileManager.default
        var stagedFiles: [(original: URL, staged: URL)] = []
        var metadataCommitted = false
        for document in documents {
            if !document.localPath.isEmpty, fileManager.fileExists(atPath: document.localPath) {
                let original = URL(fileURLWithPath: document.localPath)
                let staged = original.appendingPathExtension("pending-delete-all-\(UUID().uuidString)")
                try fileManager.moveItem(at: original, to: staged)
                stagedFiles.append((original, staged))
            }
        }
        for attempt in attempts { context.delete(attempt) }
        for attempt in pendingAttemptRecords { context.delete(attempt) }
        for reflection in attemptReflections { context.delete(reflection) }
        for report in itemReports { context.delete(report) }
        for chunk in sourceChunks { context.delete(chunk) }
        for generation in aiGenerations { context.delete(generation) }
        for checkpoint in sessionCheckpoints { context.delete(checkpoint) }
        for plan in dailyPlans { context.delete(plan) }
        for calibration in inputCalibrations { context.delete(calibration) }
        for annotation in progressAnnotations { context.delete(annotation) }
        if let weeklyTransferStateRecord { context.delete(weeklyTransferStateRecord) }
        if let reassessmentStateRecord { context.delete(reassessmentStateRecord) }
        for document in documents {
            context.delete(document)
        }
        if let profile { context.delete(profile) }
        do {
            try context.save()
            metadataCommitted = true
            try nextDayEnhancementCache.removeAllVerifying()
            try NFUserDefaultsOfflineQuestionRotationStateStore.removeAll()
            reload()
            guard profile == nil, attempts.isEmpty, documents.isEmpty, itemReports.isEmpty,
                  attemptReflections.isEmpty,
                  sourceChunks.isEmpty, aiGenerations.isEmpty, sessionCheckpoints.isEmpty, dailyPlans.isEmpty,
                  inputCalibrations.isEmpty, progressAnnotations.isEmpty,
                  weeklyTransferStateRecord == nil, reassessmentStateRecord == nil else {
                throw LocalDataError.verificationFailed
            }
            for stagedFile in stagedFiles {
                try fileManager.removeItem(at: stagedFile.staged)
            }
            let managedDocumentsFolder = try managedDocumentFolderURL(fileManager: fileManager)
            if fileManager.fileExists(atPath: managedDocumentsFolder.path) {
                let orphanURLs = try fileManager.contentsOfDirectory(
                    at: managedDocumentsFolder,
                    includingPropertiesForKeys: nil,
                    options: []
                )
                for orphanURL in orphanURLs {
                    try fileManager.removeItem(at: orphanURL)
                }
                let remainingURLs = try fileManager.contentsOfDirectory(
                    at: managedDocumentsFolder,
                    includingPropertiesForKeys: nil,
                    options: []
                )
                guard remainingURLs.isEmpty else { throw LocalDataError.verificationFailed }
            }
            activeSessionRequest = nil
            pendingAttemptRecords.removeAll()
            shouldPresentDocumentImporter = false
            shouldOpenTodayPlan = false
            shouldOpenSourceReviews = false
            shouldOpenAIStudio = false
            readiness = .normal
            selectedDestination = .today
            lastErrorMessage = nil
            // The integration coordinator publishes success only after every
            // privacy subsystem has also completed and verified its cleanup.
            notice = nil
        } catch {
            if metadataCommitted {
                for stagedFile in stagedFiles where fileManager.fileExists(atPath: stagedFile.staged.path) {
                    try? fileManager.removeItem(at: stagedFile.staged)
                }
            } else {
                context.rollback()
                for stagedFile in stagedFiles where fileManager.fileExists(atPath: stagedFile.staged.path) {
                    try? fileManager.moveItem(at: stagedFile.staged, to: stagedFile.original)
                }
            }
            reload()
            lastErrorMessage = metadataCommitted
                ? NFAppLocalization.localized("Database deletion succeeded, but file cleanup could not be fully verified. Restart and retry local cleanup before uninstalling.", locale: NFAppLocalization.preferredLocale, comment: "All-local-data deletion file-cleanup verification error.")
                : NFAppLocalization.localized("Local data deletion was rolled back and could not be verified. Retry before removing the app.", locale: NFAppLocalization.preferredLocale, comment: "Transactional all-local-data deletion error.")
            notice = AppNotice(
                title: NFAppLocalization.localized("Deletion not verified", locale: NFAppLocalization.preferredLocale, comment: "Title for an all-local-data deletion verification error."),
                message: lastErrorMessage ?? NFAppLocalization.localized("Retry deletion.", locale: NFAppLocalization.preferredLocale, comment: "Recovery suggestion after a local deletion verification error.")
            )
            throw error
        }
    }

    func reload() {
        do {
            // CloudKit can briefly surface multiple profile objects when two
            // devices complete onboarding before their first import. Always
            // select the same latest-modified winner on every device instead
            // of depending on persistent-store fetch order.
            profile = try context.fetch(FetchDescriptor<UserProfileRecord>())
                .sorted(by: Self.profilePrecedes)
                .first
            NFAppLocalization.setPreferredLanguageCode(
                profile?.preferredLanguageCode ?? Locale.current.identifier
            )
            let attemptDescriptor = FetchDescriptor<AttemptRecord>(sortBy: [SortDescriptor(\.submittedAt, order: .reverse)])
            attempts = Self.deterministicWinners(
                try context.fetch(attemptDescriptor),
                identifiedBy: \.id,
                winnerPrecedes: Self.attemptPrecedes
            )
            if NFTransferTaxonomy.migrateLegacyAttempts(attempts) {
                try context.save()
            }
            attemptReflections = Self.deterministicWinners(
                try context.fetch(FetchDescriptor<AttemptReflectionRecord>(sortBy: [SortDescriptor(\.createdAt, order: .reverse)])),
                identifiedBy: \.attemptID,
                winnerPrecedes: Self.reflectionPrecedes
            )
            documents = try context.fetch(FetchDescriptor<SourceDocumentRecord>(sortBy: [SortDescriptor(\.importedAt, order: .reverse)]))
            var redactedLegacyDocumentDiagnostic = false
            for document in documents {
                let diagnosticContext: NFDiagnosticContext = document.indexError?.hasPrefix("document.ocr.") == true
                    ? .localOCR
                    : .documentExtraction
                let safeDiagnostic = NFDiagnosticRedactor.sanitizedPersistedMessage(
                    document.indexError,
                    context: diagnosticContext
                )
                if safeDiagnostic != document.indexError {
                    document.indexError = safeDiagnostic
                    redactedLegacyDocumentDiagnostic = true
                }
            }
            if redactedLegacyDocumentDiagnostic { try? context.save() }
            itemReports = Self.deterministicWinners(
                try context.fetch(FetchDescriptor<ItemReportRecord>(sortBy: [SortDescriptor(\.createdAt, order: .reverse)])),
                identifiedBy: \.id,
                winnerPrecedes: Self.itemReportPrecedes
            )
            sourceChunks = try context.fetch(FetchDescriptor<SourceChunkRecord>(sortBy: [SortDescriptor(\.ordinal)]))
            aiGenerations = try context.fetch(FetchDescriptor<AIGenerationRecord>(sortBy: [SortDescriptor(\.createdAt, order: .reverse)]))
            sessionCheckpoints = Self.deterministicWinners(
                try context.fetch(FetchDescriptor<SessionCheckpointRecord>(sortBy: [SortDescriptor(\.updatedAt, order: .reverse)])),
                identifiedBy: \.sessionID,
                winnerPrecedes: Self.checkpointPrecedes
            )
            dailyPlans = Self.deterministicWinners(
                try context.fetch(FetchDescriptor<DailyPlanRecord>(sortBy: [SortDescriptor(\.createdAt, order: .reverse)])),
                identifiedBy: \.id,
                winnerPrecedes: Self.dailyPlanWinnerPrecedes,
                outputPrecedes: Self.dailyPlanOutputPrecedes
            )
            inputCalibrations = try context.fetch(FetchDescriptor<InputCalibrationRecord>(sortBy: [SortDescriptor(\.completedAt, order: .reverse)]))
            progressAnnotations = Self.deterministicWinners(
                try context.fetch(FetchDescriptor<ProgressAnnotationRecord>(sortBy: [SortDescriptor(\.startDate, order: .reverse)])),
                identifiedBy: \.id,
                winnerPrecedes: Self.progressAnnotationPrecedes
            )
            let weeklyMerge = Self.mergeWeeklyTransferStates(
                try context.fetch(FetchDescriptor<WeeklyTransferStateRecord>())
            )
            weeklyTransferStateRecord = weeklyMerge.record
            if weeklyMerge.didChange { try? context.save() }
            reassessmentStateRecord = try context.fetch(FetchDescriptor<ReassessmentStateRecord>())
                .sorted(by: Self.reassessmentStatePrecedes)
                .first
        } catch {
            lastErrorMessage = NFAppLocalization.localized("NeuroForge could not read all local records. Existing data was left untouched.", locale: NFAppLocalization.preferredLocale, comment: "Non-destructive local database reload error.")
        }
    }

    private static func profilePrecedes(
        _ lhs: UserProfileRecord,
        _ rhs: UserProfileRecord
    ) -> Bool {
        if lhs.modifiedAt != rhs.modifiedAt {
            return lhs.modifiedAt > rhs.modifiedAt
        }
        return lhs.id.uuidString < rhs.id.uuidString
    }

    /// CloudKit's object identity is not the same thing as the app's domain
    /// identity. During concurrent first imports the framework may briefly
    /// expose two backing objects for one attempt, session, reflection, or plan.
    /// Keep a deterministic, non-destructive projection in memory. We do not
    /// delete either backing object here because reload cannot prove that every
    /// peer has observed a corresponding CloudKit deletion.
    private static func deterministicWinners<Record, Identity: Hashable>(
        _ records: [Record],
        identifiedBy identity: (Record) -> Identity,
        winnerPrecedes: (Record, Record) -> Bool,
        outputPrecedes: ((Record, Record) -> Bool)? = nil
    ) -> [Record] {
        var winners: [Identity: Record] = [:]
        for record in records {
            let key = identity(record)
            if let current = winners[key] {
                if winnerPrecedes(record, current) { winners[key] = record }
            } else {
                winners[key] = record
            }
        }
        if let outputPrecedes {
            return winners.values.sorted(by: outputPrecedes)
        }
        return winners.values.sorted(by: winnerPrecedes)
    }

    private static func attemptPrecedes(_ lhs: AttemptRecord, _ rhs: AttemptRecord) -> Bool {
        if lhs.submittedAt != rhs.submittedAt { return lhs.submittedAt > rhs.submittedAt }
        if lhs.shownAt != rhs.shownAt { return lhs.shownAt > rhs.shownAt }
        if lhs.scoringVersion != rhs.scoringVersion { return lhs.scoringVersion > rhs.scoringVersion }
        if lhs.response != rhs.response { return lhs.response < rhs.response }
        if lhs.deviceID != rhs.deviceID { return lhs.deviceID.uuidString < rhs.deviceID.uuidString }
        return lhs.id.uuidString < rhs.id.uuidString
    }

    private static func reflectionPrecedes(
        _ lhs: AttemptReflectionRecord,
        _ rhs: AttemptReflectionRecord
    ) -> Bool {
        // The first accepted interpretation wins, matching saveAttemptReflection.
        if lhs.createdAt != rhs.createdAt { return lhs.createdAt < rhs.createdAt }
        return lhs.id.uuidString < rhs.id.uuidString
    }

    private static func itemReportPrecedes(_ lhs: ItemReportRecord, _ rhs: ItemReportRecord) -> Bool {
        if lhs.createdAt != rhs.createdAt { return lhs.createdAt > rhs.createdAt }
        if lhs.status != rhs.status { return lhs.status < rhs.status }
        if lhs.diagnosticDigest != rhs.diagnosticDigest {
            return lhs.diagnosticDigest < rhs.diagnosticDigest
        }
        return lhs.id.uuidString < rhs.id.uuidString
    }

    private static func checkpointPrecedes(
        _ lhs: SessionCheckpointRecord,
        _ rhs: SessionCheckpointRecord
    ) -> Bool {
        // Completion is terminal for a session identity. A clock-skewed or
        // delayed active checkpoint must never resurrect a completed session.
        if lhs.isComplete != rhs.isComplete { return lhs.isComplete }
        if lhs.updatedAt != rhs.updatedAt { return lhs.updatedAt > rhs.updatedAt }
        if lhs.currentIndex != rhs.currentIndex { return lhs.currentIndex > rhs.currentIndex }
        if lhs.hasCommittedCurrentItem != rhs.hasCommittedCurrentItem {
            return lhs.hasCommittedCurrentItem
        }
        if lhs.activeDurationSeconds != rhs.activeDurationSeconds {
            return lhs.activeDurationSeconds > rhs.activeDurationSeconds
        }
        return lhs.id.uuidString < rhs.id.uuidString
    }

    private static func dailyPlanWinnerPrecedes(
        _ lhs: DailyPlanRecord,
        _ rhs: DailyPlanRecord
    ) -> Bool {
        let lhsSnapshot = lhs.snapshot
        let rhsSnapshot = rhs.snapshot
        if (lhsSnapshot != nil) != (rhsSnapshot != nil) { return lhsSnapshot != nil }
        let lhsReplacement = lhsSnapshot?.replacement?.replacedAt
        let rhsReplacement = rhsSnapshot?.replacement?.replacedAt
        if lhsReplacement != rhsReplacement {
            return (lhsReplacement ?? .distantPast) > (rhsReplacement ?? .distantPast)
        }
        // Canonical daily plans are first-writer-wins once work begins.
        if lhs.createdAt != rhs.createdAt { return lhs.createdAt < rhs.createdAt }
        if lhs.payload != rhs.payload {
            return lhs.payload.lexicographicallyPrecedes(rhs.payload)
        }
        return lhs.id < rhs.id
    }

    private static func dailyPlanOutputPrecedes(
        _ lhs: DailyPlanRecord,
        _ rhs: DailyPlanRecord
    ) -> Bool {
        if lhs.createdAt != rhs.createdAt { return lhs.createdAt > rhs.createdAt }
        if lhs.id != rhs.id { return lhs.id < rhs.id }
        return lhs.payload.lexicographicallyPrecedes(rhs.payload)
    }

    private static func progressAnnotationPrecedes(
        _ lhs: ProgressAnnotationRecord,
        _ rhs: ProgressAnnotationRecord
    ) -> Bool {
        if lhs.modifiedAt != rhs.modifiedAt { return lhs.modifiedAt > rhs.modifiedAt }
        if lhs.createdAt != rhs.createdAt { return lhs.createdAt > rhs.createdAt }
        if lhs.note != rhs.note { return lhs.note < rhs.note }
        return lhs.id.uuidString < rhs.id.uuidString
    }

    private static func weeklyTransferStatePrecedes(
        _ lhs: WeeklyTransferStateRecord,
        _ rhs: WeeklyTransferStateRecord
    ) -> Bool {
        if lhs.modifiedAt != rhs.modifiedAt { return lhs.modifiedAt > rhs.modifiedAt }
        if lhs.id != rhs.id { return lhs.id < rhs.id }
        if lhs.completedMissionIDsRaw != rhs.completedMissionIDsRaw {
            return lhs.completedMissionIDsRaw < rhs.completedMissionIDsRaw
        }
        return lhs.deferredUntilPayload.lexicographicallyPrecedes(rhs.deferredUntilPayload)
    }

    private static func mergeWeeklyTransferStates(
        _ records: [WeeklyTransferStateRecord]
    ) -> (record: WeeklyTransferStateRecord?, didChange: Bool) {
        guard let winner = records.sorted(by: weeklyTransferStatePrecedes).first else {
            return (nil, false)
        }
        var completedMissionIDs: Set<String> = []
        var deferredUntilByMissionID: [String: Date] = [:]
        var pinnedMissionByWeekKey: [String: NFWeeklyTransferMission] = [:]
        for record in records.sorted(by: { lhs, rhs in
            if lhs.modifiedAt != rhs.modifiedAt { return lhs.modifiedAt < rhs.modifiedAt }
            return lhs.id < rhs.id
        }) {
            let snapshot = record.snapshot
            completedMissionIDs.formUnion(snapshot.completedMissionIDs)
            for (missionID, date) in snapshot.deferredUntilByMissionID {
                deferredUntilByMissionID[missionID] = max(
                    deferredUntilByMissionID[missionID] ?? .distantPast,
                    date
                )
            }
            for (weekKey, mission) in snapshot.pinnedMissionByWeekKey {
                // The earliest successfully persisted weekly snapshot wins,
                // matching the first-writer-wins daily-plan contract.
                pinnedMissionByWeekKey[weekKey] = pinnedMissionByWeekKey[weekKey] ?? mission
            }
        }
        let merged = NFWeeklyTransferState(
            completedMissionIDs: completedMissionIDs,
            deferredUntilByMissionID: deferredUntilByMissionID,
            pinnedMissionByWeekKey: pinnedMissionByWeekKey
        )
        guard winner.snapshot != merged else { return (winner, false) }
        // Preserve the source logical clock instead of stamping Date() on every
        // reload. The merged value is monotonic and a second reload is a no-op.
        winner.apply(
            merged,
            modifiedAt: records.map(\.modifiedAt).max() ?? winner.modifiedAt
        )
        return (winner, true)
    }

    private static func reassessmentStatePrecedes(
        _ lhs: ReassessmentStateRecord,
        _ rhs: ReassessmentStateRecord
    ) -> Bool {
        // Completion is monotonic and authoritative. Scheduling/deferral fields
        // are derived again after reload, so a newer incomplete peer must not
        // regress a cycle already completed on another device.
        if lhs.completedCycle != rhs.completedCycle {
            return lhs.completedCycle > rhs.completedCycle
        }
        let lhsCompletion = lhs.lastCompletedAt ?? .distantPast
        let rhsCompletion = rhs.lastCompletedAt ?? .distantPast
        if lhsCompletion != rhsCompletion { return lhsCompletion > rhsCompletion }
        if lhs.modifiedAt != rhs.modifiedAt { return lhs.modifiedAt > rhs.modifiedAt }
        if lhs.id != rhs.id { return lhs.id < rhs.id }
        let lhsLatest = [lhs.lastCompletedAt, lhs.deferredUntil, lhs.dueAt]
            .compactMap { $0 }
            .max() ?? .distantPast
        let rhsLatest = [rhs.lastCompletedAt, rhs.deferredUntil, rhs.dueAt]
            .compactMap { $0 }
            .max() ?? .distantPast
        if lhsLatest != rhsLatest { return lhsLatest > rhsLatest }
        return (lhs.targetBlockRaw ?? "") < (rhs.targetBlockRaw ?? "")
    }

    private func saveAndReload() {
        do {
            try context.save()
            reload()
        } catch {
            context.rollback()
            reload()
            lastErrorMessage = NFAppLocalization.localized("The preference could not be saved.", locale: NFAppLocalization.preferredLocale, comment: "Generic local preference persistence error.")
        }
    }

    func chunks(for document: SourceDocumentRecord) -> [NFSourceChunk] {
        sourceChunks
            .filter { $0.documentID == document.id }
            .sorted { $0.ordinal < $1.ordinal }
            .map(\.snapshot)
    }

    func searchDocuments(_ query: String) -> [SourceDocumentRecord] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return documents }
        let matchingDocumentIDs = Set(sourceChunks.lazy.filter {
            $0.text.localizedCaseInsensitiveContains(trimmed)
        }.map(\.documentID))
        return documents.filter {
            $0.filename.localizedCaseInsensitiveContains(trimmed) || matchingDocumentIDs.contains($0.id)
        }
    }

    func upsertCheckpoint(
        sessionID: UUID,
        request: SessionRequest,
        currentIndex: Int,
        itemCount: Int,
        response: String,
        scratchpad: String,
        results: [Bool],
        credits: [Double] = [],
        assessmentDescriptorIDs: [String] = [],
        assessmentEvents: [String] = [],
        activeDurationSeconds: TimeInterval = 0,
        assessmentStopReason: NFAssessmentStopReason? = nil,
        pendingReflectionAttemptID: UUID? = nil,
        reflectionTrigger: NFAttemptReflectionTrigger? = nil,
        selectedReflectionCode: NFErrorReflectionCode? = nil,
        reflectionNote: String? = nil,
        hasCommittedCurrentItem: Bool = false,
        isComplete: Bool = false
    ) throws {
        let record = sessionCheckpoints.first(where: { $0.sessionID == sessionID }) ?? SessionCheckpointRecord(
            sessionID: sessionID,
            lab: request.lab,
            source: request.source,
            seed: request.seed,
            currentIndex: currentIndex,
            itemCount: itemCount,
            response: response,
            scratchpad: scratchpad,
            results: results,
            credits: credits,
            assessmentDescriptorIDs: assessmentDescriptorIDs,
            assessmentEvents: assessmentEvents,
            evidenceClass: request.evidenceClass,
            planID: request.planID,
            planBlockID: request.planBlockID,
            recommendationRationale: request.recommendationRationale,
            assessmentBlock: request.assessmentBlock,
            assessmentCycle: request.reassessmentCycle,
            activeDurationSeconds: activeDurationSeconds,
            assessmentStopReason: assessmentStopReason,
            pendingReflectionAttemptID: pendingReflectionAttemptID,
            reflectionTrigger: reflectionTrigger,
            selectedReflectionCode: selectedReflectionCode,
            reflectionNote: reflectionNote,
            hasCommittedCurrentItem: hasCommittedCurrentItem
        )
        if !sessionCheckpoints.contains(where: { $0.id == record.id }) {
            context.insert(record)
            sessionCheckpoints.insert(record, at: 0)
        }
        record.currentIndex = currentIndex
        record.itemCount = itemCount
        record.response = response
        record.scratchpad = scratchpad
        record.resultsRaw = results.map { $0 ? "1" : "0" }.joined(separator: ",")
        record.creditsRaw = credits.map {
            String(format: "%.17g", min(1, max(0, $0)))
        }.joined(separator: ",")
        record.assessmentDescriptorIDsRaw = assessmentDescriptorIDs.joined(separator: ",")
        record.assessmentEventsRaw = assessmentEvents.joined(separator: ",")
        let updatedAt = Date()
        record.updatedAt = updatedAt
        record.planID = request.planID
        record.planBlockID = request.planBlockID
        record.recommendationRationale = request.recommendationRationale
        record.assessmentBlockRaw = request.assessmentBlock?.rawValue
        record.assessmentCycle = request.reassessmentCycle
        record.activeDurationSeconds = max(0, activeDurationSeconds)
        record.assessmentStopReasonRaw = assessmentStopReason?.rawValue
        record.pendingReflectionAttemptID = pendingReflectionAttemptID
        record.reflectionTriggerRaw = reflectionTrigger?.rawValue
        record.selectedReflectionCodeRaw = selectedReflectionCode?.rawValue
        record.reflectionNote = reflectionNote
        record.hasCommittedCurrentItem = hasCommittedCurrentItem
        // Completion is monotonic for a stable session identity. A stale draft
        // or resumed peer must never turn a durably completed session back into
        // an incomplete one.
        record.isComplete = record.isComplete || isComplete
        if isComplete,
           request.source == .reassessment,
           let cycle = request.reassessmentCycle,
           let block = request.assessmentBlock,
           let currentState = reassessmentStateRecord?.snapshot,
           let completedState = NFReassessmentScheduler.completing(
               currentState,
               cycle: cycle,
               block: block,
               at: updatedAt
           ) {
            let stateRecord = reassessmentStateRecord ?? ReassessmentStateRecord(state: completedState)
            if reassessmentStateRecord == nil {
                context.insert(stateRecord)
                reassessmentStateRecord = stateRecord
            } else {
                stateRecord.apply(completedState, modifiedAt: updatedAt)
            }
        }
        do {
            try context.save()
            lastErrorMessage = nil
        } catch {
            // A failed checkpoint must not remain visible through mutated
            // in-memory model objects as though it were durable.
            context.rollback()
            reload()
            lastErrorMessage = NFAppLocalization.localized(
                "The session checkpoint could not be saved. The session remains open so you can retry.",
                locale: NFAppLocalization.preferredLocale,
                comment: "Transactional session-checkpoint persistence failure."
            )
            throw error
        }
        if isComplete {
            if request.source == .baseline { _ = refreshReassessmentSchedule(at: updatedAt) }
            self.publishWidgetSnapshot()
        }
    }

    func completedPlanBlockIDs(planID: String) -> Set<String> {
        Set(sessionCheckpoints.compactMap { checkpoint in
            guard checkpoint.isComplete, checkpoint.planID == planID else { return nil }
            return checkpoint.planBlockID
        })
    }

    private func insertAttempt(_ record: AttemptRecord) throws {
        if attempts.contains(where: { $0.id == record.id }) { return }
        if let pending = pendingAttemptRecords.first(where: { $0.id == record.id }) {
            do {
                try context.save()
                pendingAttemptRecords.removeAll { $0.id == pending.id }
                if !attempts.contains(where: { $0.id == pending.id }) { attempts.insert(pending, at: 0) }
                if pending.sessionSourceRaw == SessionSource.today.rawValue { self.publishWidgetSnapshot() }
                return
            } catch {
                lastErrorMessage = NFAppLocalization.localized("Your answer remains queued under the same response ID; no duplicate was created.", locale: NFAppLocalization.preferredLocale, comment: "Attempt persistence status after a safe retry with the same response identifier.")
                throw error
            }
        }
        context.insert(record)
        do {
            try context.save()
            attempts.insert(record, at: 0)
            if record.sessionSourceRaw == SessionSource.today.rawValue { self.publishWidgetSnapshot() }
        } catch {
            do {
                // One immediate retry handles transient file coordination and store-busy failures.
                try context.save()
                attempts.insert(record, at: 0)
                if record.sessionSourceRaw == SessionSource.today.rawValue { self.publishWidgetSnapshot() }
            } catch {
                if !pendingAttemptRecords.contains(where: { $0.id == record.id }) {
                    pendingAttemptRecords.append(record)
                }
                lastErrorMessage = NFAppLocalization.localized("Your answer is still on screen. NeuroForge queued an automatic local retry; a recovery export remains available.", locale: NFAppLocalization.preferredLocale, comment: "Attempt persistence error with safe local retry and recovery guidance.")
                throw error
            }
        }
    }

    func retryPendingWrites() {
        guard !pendingAttemptRecords.isEmpty else { return }
        do {
            try context.save()
            for record in pendingAttemptRecords where !attempts.contains(where: { $0.id == record.id }) {
                attempts.insert(record, at: 0)
            }
            pendingAttemptRecords.removeAll()
            lastErrorMessage = nil
            self.publishWidgetSnapshot()
            notice = AppNotice(
                title: NFAppLocalization.localized("Pending answers saved", locale: NFAppLocalization.preferredLocale, comment: "Confirmation after queued response records are saved."),
                message: NFAppLocalization.localized("NeuroForge recovered and verified the locally queued responses.", locale: NFAppLocalization.preferredLocale, comment: "Confirmation after queued response records are saved.")
            )
        } catch {
            lastErrorMessage = NFAppLocalization.formattedQueuedResponseRecovery(pendingAttemptRecords.count)
        }
    }
}

struct AppNotice: Identifiable, Equatable {
    let id = UUID()
    let title: String
    let message: String
}

private enum LocalDataError: Error {
    case verificationFailed
    case missingAttempt
    case incompleteReflection
    case missingDocument
}

enum AppDestination: String, CaseIterable, Identifiable, Sendable {
    case today
    case train
    case progress
    case library
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .today: NFAppLocalization.localized("Forge", locale: NFAppLocalization.preferredLocale, comment: "Primary app navigation destination for the daily training circuit.")
        case .train: NFAppLocalization.localized("Practice", locale: NFAppLocalization.preferredLocale, comment: "Primary app navigation destination for learner-directed ability practice.")
        case .progress: NFAppLocalization.localized("Progress", locale: NFAppLocalization.preferredLocale, comment: "Primary app navigation destination.")
        case .library: NFAppLocalization.localized("Sources", locale: NFAppLocalization.preferredLocale, comment: "Primary app navigation destination for imported study sources and personal practice.")
        case .settings: NFAppLocalization.localized("Settings", locale: NFAppLocalization.preferredLocale, comment: "Primary app navigation destination.")
        }
    }

    var symbol: String {
        switch self {
        case .today: "flame.fill"
        case .train: "scope"
        case .progress: "chart.line.uptrend.xyaxis"
        case .library: "books.vertical.fill"
        case .settings: "gearshape.fill"
        }
    }
}

enum NFSettingsSubroute: String, Equatable, Sendable {
    case export
    case methodology
}

struct NFDirtyEditorRegistration: Equatable, Sendable {
    let id: UUID
    let title: String
}

enum NFDeferredAppIntent: Equatable, Sendable {
    case externalRoute(NFExternalRoute)
    case todayPlan
    case reviewsDue(date: Date, calendar: Calendar)
    case sourceReviews
    case documentImport
    case sourceReviewDocumentImport
    case questionWriterCallback
    case mentalMathPractice(requestedMinutes: Int?, preferredKind: MentalMathKind?)
}

enum SessionSource: String, Sendable {
    case today
    case focused
    case baseline
    case reassessment
    case weeklyMission
}

struct SessionRequest: Identifiable, Sendable {
    let id = UUID()
    let lab: TrainingLab
    let source: SessionSource
    let seed: UInt64
    let localeIdentifier: String
    let requestedMinutes: Int?
    let preferredMentalMathKind: MentalMathKind?
    let evidenceClass: EvidenceClass
    let field: STEMField?
    let topic: String?
    let recommendationRationale: String?
    let targetDifficulty: Double?
    let requestedItemCount: Int?
    /// Reserved ordinals from the versioned offline bank. The reservation is
    /// made when a focused quiz launches, so abandoning it cannot return the
    /// same slice to the front of the queue.
    let offlineQuestionOrdinals: [Int]
    let startingIndex: Int
    let assessmentBlock: NFAssessmentBlockKind?
    let reassessmentCycle: Int?
    let planID: String?
    let planBlockID: String?
    let isTimed: Bool?
    let resumeSessionID: UUID?
    let resumedResults: [Bool]
    let resumedCredits: [Double]
    let resumedAssessmentDescriptorIDs: [String]
    let resumedAssessmentEvents: [String]
    let resumedResponsePayload: String?
    let resumedScratchpad: String
    let resumeCurrentItemWasCommitted: Bool
    let resumedPendingReflectionAttemptID: UUID?
    let resumedReflectionTrigger: NFAttemptReflectionTrigger?
    let resumedSelectedReflectionCode: NFErrorReflectionCode?
    let resumedReflectionNote: String
    let resumedActiveDurationSeconds: TimeInterval
    let resumedAssessmentPracticeDurationSeconds: TimeInterval
    let mechanicID: String?
    let retentionItemIDs: [String]
    let retentionTargets: [NFRetentionReviewTarget]
    let transferBrief: NFExerciseTransferBrief?
    let presentationEnhancements: [String: NFExercisePresentationEnhancement]
    let quarantinedItemIDs: Set<String>
    let quarantinedAssessmentDescriptorIDs: Set<String>

    init(
        lab: TrainingLab,
        source: SessionSource,
        seed: UInt64,
        localeIdentifier: String = Locale.current.identifier,
        requestedMinutes: Int? = nil,
        preferredMentalMathKind: MentalMathKind? = nil,
        evidenceClass: EvidenceClass = .practice,
        field: STEMField? = nil,
        topic: String? = nil,
        recommendationRationale: String? = nil,
        targetDifficulty: Double? = nil,
        requestedItemCount: Int? = nil,
        offlineQuestionOrdinals: [Int] = [],
        startingIndex: Int = 0,
        assessmentBlock: NFAssessmentBlockKind? = nil,
        reassessmentCycle: Int? = nil,
        planID: String? = nil,
        planBlockID: String? = nil,
        isTimed: Bool? = nil,
        resumeSessionID: UUID? = nil,
        resumedResults: [Bool] = [],
        resumedCredits: [Double] = [],
        resumedAssessmentDescriptorIDs: [String] = [],
        resumedAssessmentEvents: [String] = [],
        resumedResponsePayload: String? = nil,
        resumedScratchpad: String = "",
        resumeCurrentItemWasCommitted: Bool = false,
        resumedPendingReflectionAttemptID: UUID? = nil,
        resumedReflectionTrigger: NFAttemptReflectionTrigger? = nil,
        resumedSelectedReflectionCode: NFErrorReflectionCode? = nil,
        resumedReflectionNote: String = "",
        resumedActiveDurationSeconds: TimeInterval = 0,
        resumedAssessmentPracticeDurationSeconds: TimeInterval = 0,
        mechanicID: String? = nil,
        retentionItemIDs: [String] = [],
        retentionTargets: [NFRetentionReviewTarget] = [],
        transferBrief: NFExerciseTransferBrief? = nil,
        presentationEnhancements: [String: NFExercisePresentationEnhancement] = [:],
        quarantinedItemIDs: Set<String> = [],
        quarantinedAssessmentDescriptorIDs: Set<String> = []
    ) {
        self.lab = lab
        self.source = source
        self.seed = seed
        self.localeIdentifier = localeIdentifier
        self.requestedMinutes = requestedMinutes
        self.preferredMentalMathKind = preferredMentalMathKind
        self.evidenceClass = evidenceClass
        self.field = field
        self.topic = topic
        let trimmedRecommendationRationale = recommendationRationale?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        self.recommendationRationale = trimmedRecommendationRationale?.isEmpty == false
            ? String(trimmedRecommendationRationale!.prefix(500))
            : nil
        self.targetDifficulty = targetDifficulty
        self.requestedItemCount = requestedItemCount.map { min(50, max(1, $0)) }
        self.offlineQuestionOrdinals = offlineQuestionOrdinals
        self.startingIndex = max(0, startingIndex)
        self.assessmentBlock = assessmentBlock
        self.reassessmentCycle = reassessmentCycle.map { max(1, $0) }
        self.planID = planID
        self.planBlockID = planBlockID
        self.isTimed = isTimed
        self.resumeSessionID = resumeSessionID
        self.resumedResults = resumedResults
        self.resumedCredits = resumedCredits.count == resumedResults.count
            ? resumedCredits.map { min(1, max(0, $0)) }
            : resumedResults.map { $0 ? 1 : 0 }
        self.resumedAssessmentDescriptorIDs = resumedAssessmentDescriptorIDs
        self.resumedAssessmentEvents = resumedAssessmentEvents
        self.resumedResponsePayload = resumedResponsePayload
        self.resumedScratchpad = resumedScratchpad
        self.resumeCurrentItemWasCommitted = resumeCurrentItemWasCommitted
        self.resumedPendingReflectionAttemptID = resumedPendingReflectionAttemptID
        self.resumedReflectionTrigger = resumedReflectionTrigger
        self.resumedSelectedReflectionCode = resumedSelectedReflectionCode
        self.resumedReflectionNote = resumedReflectionNote
        self.resumedActiveDurationSeconds = max(0, resumedActiveDurationSeconds)
        self.resumedAssessmentPracticeDurationSeconds = min(
            self.resumedActiveDurationSeconds,
            max(0, resumedAssessmentPracticeDurationSeconds)
        )
        self.mechanicID = mechanicID
        let resolvedRetentionTargets = retentionTargets.isEmpty
            ? retentionItemIDs.enumerated().map { index, memoryItemID in
                NFRetentionReviewTarget.legacy(
                    memoryItemID: memoryItemID,
                    fallbackSeed: seed ^ NFStableDeterminism.hash64(
                        "legacy-session-request|\(index)|\(memoryItemID)"
                    )
                )
            }
            : retentionTargets
        self.retentionTargets = resolvedRetentionTargets
        self.retentionItemIDs = resolvedRetentionTargets.isEmpty
            ? retentionItemIDs
            : resolvedRetentionTargets.map(\.memoryItemID)
        self.transferBrief = transferBrief
        self.presentationEnhancements = presentationEnhancements
        self.quarantinedItemIDs = quarantinedItemIDs
        self.quarantinedAssessmentDescriptorIDs = quarantinedAssessmentDescriptorIDs
    }

    func retentionTarget(at index: Int) -> NFRetentionReviewTarget? {
        guard index >= 0, !retentionTargets.isEmpty else { return nil }
        return retentionTargets[index % retentionTargets.count]
    }
}

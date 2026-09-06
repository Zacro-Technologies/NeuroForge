import Foundation
import CryptoKit
import Observation
import Darwin

/// Exact value snapshot of every shipped AttemptRecord column. Serialized raw
/// response strings and telemetry envelopes are retained without normalization.
struct NFImmutableAttemptRecordSnapshot: Codable, Equatable, Sendable {
    let id: UUID
    let sessionID: UUID
    let itemID: String
    let templateID: String
    let seed: UInt64
    let gameID: String
    let skillID: String
    let skillWeightsRaw: String
    let domainContextRaw: String
    let transferBriefRaw: String
    let spatialDifficultyParametersRaw: String
    let prompt: String
    let response: String
    let correctAnswer: Double
    let correctAnswerText: String
    let isCorrect: Bool
    let confidenceRaw: String?
    let shownAt: Date
    let submittedAt: Date
    let activeDurationSeconds: Double
    let evidenceClassRaw: String
    let sessionSourceRaw: String
    let evidenceWeight: Double
    let errorCode: String?
    let scoringVersion: Int
    let deviceID: UUID
    let generationID: UUID?
    let sourceDocumentIDsRaw: String
    let sourceChunkIDsRaw: String
    let responseFormatRaw: String
    let wasSkipped: Bool
    let validationVersion: Int
    let assessmentBlockRaw: String?
    let planID: String?
    let planBlockID: String?
    let deterministicCredit: Double
    let hintCount: Int
    let inputModeRaw: String
    let interruptionCount: Int
    let revisionCount: Int
    let accommodationFlagsRaw: String
    let wasTimed: Bool
    let assessmentDescriptorID: String?
    let assessmentTemplateFamily: String?
    let assessmentFormatRaw: String?
    let assessmentMechanicID: String?
    let assessmentSubskillID: String?
    let assessmentSeed: UInt64?
    let assessmentCycle: Int?

    @MainActor init(_ record: AttemptRecord) {
        id = record.id
        sessionID = record.sessionID
        itemID = record.itemID
        templateID = record.templateID
        seed = record.seed
        gameID = record.gameID
        skillID = record.skillID
        skillWeightsRaw = record.skillWeightsRaw
        domainContextRaw = record.domainContextRaw
        transferBriefRaw = record.transferBriefRaw
        spatialDifficultyParametersRaw = record.spatialDifficultyParametersRaw
        prompt = record.prompt
        response = record.response
        correctAnswer = record.correctAnswer
        correctAnswerText = record.correctAnswerText
        isCorrect = record.isCorrect
        confidenceRaw = record.confidenceRaw
        shownAt = record.shownAt
        submittedAt = record.submittedAt
        activeDurationSeconds = record.activeDurationSeconds
        evidenceClassRaw = record.evidenceClassRaw
        sessionSourceRaw = record.sessionSourceRaw
        evidenceWeight = record.evidenceWeight
        errorCode = record.errorCode
        scoringVersion = record.scoringVersion
        deviceID = record.deviceID
        generationID = record.generationID
        sourceDocumentIDsRaw = record.sourceDocumentIDsRaw
        sourceChunkIDsRaw = record.sourceChunkIDsRaw
        responseFormatRaw = record.responseFormatRaw
        wasSkipped = record.wasSkipped
        validationVersion = record.validationVersion
        assessmentBlockRaw = record.assessmentBlockRaw
        planID = record.planID
        planBlockID = record.planBlockID
        deterministicCredit = record.deterministicCredit
        hintCount = record.hintCount
        inputModeRaw = record.inputModeRaw
        interruptionCount = record.interruptionCount
        revisionCount = record.revisionCount
        accommodationFlagsRaw = record.accommodationFlagsRaw
        wasTimed = record.wasTimed
        assessmentDescriptorID = record.assessmentDescriptorID
        assessmentTemplateFamily = record.assessmentTemplateFamily
        assessmentFormatRaw = record.assessmentFormatRaw
        assessmentMechanicID = record.assessmentMechanicID
        assessmentSubskillID = record.assessmentSubskillID
        assessmentSeed = record.assessmentSeed
        assessmentCycle = record.assessmentCycle
    }

    var containsProtectedContent: Bool {
        evidenceClassRaw == EvidenceClass.assessmentHoldout.rawValue
            || evidenceClassRaw == EvidenceClass.nearTransfer.rawValue
            || sessionSourceRaw == SessionSource.baseline.rawValue
            || sessionSourceRaw == SessionSource.reassessment.rawValue
            || assessmentBlockRaw != nil || errorCode == "protected_evaluator_unavailable"
    }

    /// Excludes retry-created telemetry, while retaining the frozen semantic
    /// answer/result/provenance identity used by the existing commit boundary.
    func commitDigest() throws -> String {
        let keys = Set("id sessionID itemID templateID seed gameID prompt scoringVersion correctAnswerText isCorrect deterministicCredit errorCode confidenceRaw evidenceClassRaw sessionSourceRaw responseFormatRaw wasSkipped generationID hintCount sourceDocumentIDsRaw sourceChunkIDsRaw assessmentDescriptorID assessmentBlockRaw planID planBlockID".split(separator: " ").map(String.init))
        var value = (try JSONSerialization.jsonObject(with: Self.encoded(self)) as? [String: Any] ?? [:])
            .filter { keys.contains($0.key) }
        if let typed = try? JSONDecoder().decode(NFExerciseResponse.self, from: Data(response.utf8)) {
            value["response"] = try JSONSerialization.jsonObject(with: Self.encoded(typed))
        } else { value["response"] = response }
        return Self.digest(try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]))
    }

    static func encoded<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(value)
    }
    static func digest(_ bytes: Data) -> String {
        SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
    }
}

/// Separate recovery diagnostics never become AttemptRecords or award XP.
/// The proposed snapshot is explicitly distinct from an authenticated original.
struct NFAttemptConflictJournalEntry: Codable, Equatable, Sendable, Identifiable {
    var schemaVersion = 1
    let id: String
    let attemptID: UUID
    let recordedAt: Date
    let original: NFImmutableAttemptRecordSnapshot
    let proposed: NFImmutableAttemptRecordSnapshot
    let originalPayloadDigest: String
    let proposedPayloadDigest: String
    let originalCommitDigest: String
    let proposedCommitDigest: String
    let originalExercise: NFExercise?
    let proposedExercise: NFExercise?
    let originalExerciseDigest: String?
    let proposedExerciseDigest: String?
    let originalSnapshotVerified: Bool
    let proposedScore: NFExerciseScoringResult?
    let proposedScoreDigest: String?

    init(original: NFImmutableAttemptRecordSnapshot, proposed: NFImmutableAttemptRecordSnapshot,
         originalExercise: NFExercise?, proposedExercise: NFExercise?, proposedScore: NFExerciseScoringResult?) throws {
        self.original = original; self.proposed = proposed
        attemptID = original.id
        recordedAt = proposed.submittedAt
        originalPayloadDigest = try NFImmutableAttemptRecordSnapshot.digest(NFImmutableAttemptRecordSnapshot.encoded(original))
        proposedPayloadDigest = try NFImmutableAttemptRecordSnapshot.digest(NFImmutableAttemptRecordSnapshot.encoded(proposed))
        originalCommitDigest = try original.commitDigest()
        proposedCommitDigest = try proposed.commitDigest()
        self.originalExercise = originalExercise; self.proposedExercise = proposedExercise
        originalExerciseDigest = try originalExercise.map { NFImmutableAttemptRecordSnapshot.digest(try NFImmutableAttemptRecordSnapshot.encoded($0)) }
        proposedExerciseDigest = try proposedExercise.map { NFImmutableAttemptRecordSnapshot.digest(try NFImmutableAttemptRecordSnapshot.encoded($0)) }
        originalSnapshotVerified = originalExercise != nil
        self.proposedScore = proposedScore
        proposedScoreDigest = try proposedScore.map { NFImmutableAttemptRecordSnapshot.digest(try NFImmutableAttemptRecordSnapshot.encoded($0)) }
        id = Self.identity(attemptID: attemptID, originalCommitDigest: originalCommitDigest, proposedCommitDigest: proposedCommitDigest,
            originalExerciseDigest: originalExerciseDigest, proposedExerciseDigest: proposedExerciseDigest, proposedScoreDigest: proposedScoreDigest)
    }

    var containsProtectedContent: Bool {
        original.containsProtectedContent || proposed.containsProtectedContent
            || originalExercise?.assessmentProtected == true || proposedExercise?.assessmentProtected == true
    }

    private static func identity(attemptID: UUID, originalCommitDigest: String, proposedCommitDigest: String,
                                 originalExerciseDigest: String?, proposedExerciseDigest: String?, proposedScoreDigest: String?) -> String {
        NFImmutableAttemptRecordSnapshot.digest(Data(["attempt-conflict.v1", attemptID.uuidString, originalCommitDigest,
            proposedCommitDigest, originalExerciseDigest ?? "missing-original", proposedExerciseDigest ?? "missing-proposal",
            proposedScoreDigest ?? "missing-result"].joined(separator: "\u{0}").utf8))
    }

    func validate() throws {
        guard schemaVersion == 1, original.id == attemptID, proposed.id == attemptID,
              originalSnapshotVerified == (originalExercise != nil),
              originalExercise.map({ $0.id == original.itemID && $0.prompt == original.prompt }) != false,
              proposedExercise.map({ $0.id == proposed.itemID && $0.prompt == proposed.prompt }) != false,
              proposedScore.map({ $0.exerciseID == proposed.itemID && $0.scoringVersion == proposed.scoringVersion }) != false,
              try originalPayloadDigest == NFImmutableAttemptRecordSnapshot.digest(NFImmutableAttemptRecordSnapshot.encoded(original)),
              try proposedPayloadDigest == NFImmutableAttemptRecordSnapshot.digest(NFImmutableAttemptRecordSnapshot.encoded(proposed)),
              try originalCommitDigest == original.commitDigest(), try proposedCommitDigest == proposed.commitDigest(),
              try originalExerciseDigest == originalExercise.map({ NFImmutableAttemptRecordSnapshot.digest(try NFImmutableAttemptRecordSnapshot.encoded($0)) }),
              try proposedExerciseDigest == proposedExercise.map({ NFImmutableAttemptRecordSnapshot.digest(try NFImmutableAttemptRecordSnapshot.encoded($0)) }),
              try proposedScoreDigest == proposedScore.map({ NFImmutableAttemptRecordSnapshot.digest(try NFImmutableAttemptRecordSnapshot.encoded($0)) }),
              id == Self.identity(attemptID: attemptID, originalCommitDigest: originalCommitDigest, proposedCommitDigest: proposedCommitDigest,
                  originalExerciseDigest: originalExerciseDigest, proposedExerciseDigest: proposedExerciseDigest, proposedScoreDigest: proposedScoreDigest) else {
            throw NFAttemptConflictValidationError.invalidJournal
        }
    }
}
private enum NFAttemptConflictValidationError: Error { case invalidJournal }

struct NFLocalAssistanceEvent: Codable, Equatable, Sendable {
    enum Kind: String, Codable, Sendable { case hint, workedSolution, codeTrace }
    let id: UUID
    let kind: Kind
    let stage: Int
    let activeOffset: TimeInterval
    let generatorVersion: Int
}

/// Device-local additions deliberately leave the shipped SwiftData metadata intact.
/// No record in this repository participates in CloudKit synchronization.
struct NFLocalItemCheckpoint: Codable, Equatable, Sendable {
    var schemaVersion = 1
    var slotID: UUID
    var attemptID: UUID
    var index: Int
    var itemCount: Int
    var phase: NFSessionStage
    var exercise: NFExercise?
    var exerciseDigest: String
    var descriptor: NFAssessmentItemDescriptor?
    var response: NFExerciseResponse
    var confidence: ConfidenceLevel?
    var scratchpad: String
    var hintCount: Int
    var solutionRevealed: Bool
    var referenceRevealed: Bool
    var selfCheckRating: NFSelfCheckRating?
    var result: NFExerciseScoringResult?
    var committedAttemptID: UUID?
    var correctness: [Bool]
    var credits: [Double]
    var assessmentDescriptorIDs: [String]
    var assessmentEvents: [String]
    var cumulativeActiveDuration: TimeInterval
    var itemActiveDuration: TimeInterval
    var assessmentPracticeDuration: TimeInterval
    var interruptionCount: Int
    var revisionCount: Int
    var inputModality: NFInputModality
    var reflectionTrigger: NFAttemptReflectionTrigger?
    var suggestedReflectionCode: NFErrorReflectionCode?
    var selectedReflectionCode: NFErrorReflectionCode?
    var reflectionNote: String
    var semanticExclusions: Set<String>
    var shownAt: Date
    var endedEarly: Bool? = nil
    var pendingOutcome: String? = nil
    var scorerVersion: Int? = NFExerciseScoringEngine.scoringVersion
    var sittingActiveDuration: TimeInterval? = nil
    var sittingOrdinal: Int? = nil
    var awaitingNextSitting: Bool? = nil
    var assessmentStopReason: NFAssessmentStopReason? = nil
    var assessmentState: NFAdaptiveAssessmentState? = nil
    var assessmentCatalogSnapshot: NFAssessmentBlockSession? = nil
    var answerDurationComplete: Bool? = nil
    var timeBudgetUsed: Bool? = nil
    var assistanceEvents: [NFLocalAssistanceEvent]? = nil
    var clarificationMessage: String? = nil
    var mathWork: NFMathWorkDraft? = nil
    var timingConditionOverride: NFSessionTimingCondition? = nil
    var protectedCommitReceipt: NFProtectedCommitReceipt? = nil
    var ordinaryReservationDecisionID: String? = nil
    var traceInspection: NFTraceInspectionDraft? = nil
    var dataInspection: NFDataInspectionDraft? = nil
    var scienceStudy: NFScienceStudyDraft? = nil
    var transferRelationship: NFTransferRelationshipDraft? = nil

    var capturedSupportCount: Int { hintCount + (traceInspection == nil ? 0 : 1) + (dataInspection?.supportCount ?? 0) }

    var hasSupportedTraceInspection: Bool {
        guard let traceInspection else { return true }
        guard let exercise else { return false }
        return traceInspection.isValid(for: exercise)
    }

    var hasSupportedTransferRelationship: Bool {
        guard let exercise else { return transferRelationship == nil }
        return NFTransferRelationshipDraft.permits(transferRelationship, exercise: exercise, response: response, committing: pendingOutcome == "answer")
            && (transferRelationship?.awaitsRelationship != true || capturedSupportCount == 0)
    }

    var hasSupportedGraphConstruction: Bool { exercise?.hasSupportedGraphConstruction ?? true }

    var hasSupportedScienceStudy: Bool {
        guard let exercise else { return scienceStudy == nil }
        return NFScienceStudyDraft.permits(scienceStudy, exercise: exercise, response: response, committing: pendingOutcome == "answer")
    }

    var hasSupportedDataInspection: Bool {
        guard let dataInspection else { return true }
        guard let exercise else { return false }
        return dataInspection.isCompatible(with: exercise)
    }

    var hasSupportedMathWork: Bool {
        guard let mathWork else { return true }
        guard let exercise else { return false }
        return mathWork.isCompatible(with: exercise, response: response)
            && !(pendingOutcome == "answer" && mathWork.awaitsEstimate)
            && (!mathWork.requiresCompensationSupport || hintCount >= 2)
    }

    var hasSupportedTimingCondition: Bool {
        timingConditionOverride.map { $0.isSupported && $0.mode != .timedFluency } ?? true
    }

    var hasValidTimingDurations: Bool {
        [cumulativeActiveDuration, itemActiveDuration, assessmentPracticeDuration]
            .allSatisfy(NFSessionDurationPolicy.isValid)
            && (sittingActiveDuration.map(NFSessionDurationPolicy.isValid) ?? true)
            && (assistanceEvents ?? []).allSatisfy { NFSessionDurationPolicy.isValid($0.activeOffset) }
    }

    static func digest(_ exercise: NFExercise) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return SHA256.hash(data: try encoder.encode(exercise)).map { String(format: "%02x", $0) }.joined()
    }
}

struct NFLocalSessionEnvelope: Codable, Identifiable, Sendable {
    var schemaVersion = 1
    let id: UUID
    let ownerDeviceID: UUID
    var revision: Int
    var request: SessionRequest
    var checkpoint: NFLocalItemCheckpoint
    var status: Status
    var updatedAt: Date
    enum Status: String, Codable, Sendable { case suspended, completed, endedEarly, migrationRecovery }
    var index: Int { checkpoint.index }
    var itemCount: Int { checkpoint.itemCount }
    var phase: NFSessionStage { checkpoint.phase }
}

struct NFLocalAttemptSnapshot: Codable, Sendable {
    let attemptID: UUID
    let exercise: NFExercise
    var editorialCapture: NFEditorialCommitCapture? = nil
    var mathWork: NFMathWorkDraft? = nil
    var traceInspection: NFTraceInspectionDraft? = nil
    var dataInspection: NFDataInspectionDraft? = nil
    var scienceStudy: NFScienceStudyDraft? = nil
    var transferRelationship: NFTransferRelationshipDraft? = nil
}

/// A diagnostic reference, never a replacement exercise or an answer key.
/// Opaque original bytes stay exclusively in the local recovery directory.
struct NFUnavailableHistorySnapshot: Codable, Equatable, Sendable, Identifiable {
    enum Reason: String, Codable, Sendable { case malformed, oversized, protectedContent, unsupportedExerciseVersion }
    let attemptID: UUID
    let digest: String
    let reason: Reason
    var id: UUID { attemptID }
}

struct NFLocalSavedStudySet: Codable, Identifiable, Sendable {
    let id: UUID
    let savedAt: Date
    let result: NFAuthoringResult
    var schemaVersion: Int? = 1

    var unavailableReason: String? {
        guard schemaVersion == nil || schemaVersion == 1 else {
            return "This saved work needs a newer version of NeuroForge."
        }
        return NFGeneratedPracticeCompatibility.unavailableReason(for: result)
    }
}

struct NFLocalPrivateStudyRun: Codable, Identifiable, Sendable {
    let id: UUID
    let generationID: UUID
    let payload: Data
    let updatedAt: Date
}

struct NFLocalRotationMigrationReceipt: Codable, Equatable, Sendable {
    let schemaVersion: Int
    let sourceDigest: String
    let sourceRevision: UInt64?
    let importedAt: Date
}

struct NFLocalFixedLaunchReceipt: Codable, Equatable, Sendable {
    let commandID: UUID
    let sessionID: UUID
    let configurationDigest: String
    let plan: NFOfflineQuestionRotationPlan
    /// The caller's provisional plan can differ after eligibility preflight.
    /// Retrying that same accepted input returns the canonical saved plan.
    var acceptedInputConfigurationDigest: String? = nil
}

/// Delivery is independent of academic challenge. Nil on old requests retains
/// their original recipe; unknown future pins remain readable but not writable.
struct NFOrdinaryDeliveryPin: Codable, Equatable, Sendable {
    var schemaVersion = 1
    let strategyRaw: String
    let profileID: UUID
    let bankVersion: Int
    let bankFingerprint: String
    let laneID: String
    var editorialPolicy: NFEditorialSessionPin? = nil
    var strategy: NFReservationStrategy? { NFReservationStrategy(rawValue: strategyRaw) }
    var isSupported: Bool { schemaVersion == 1 && strategy != nil && bankVersion > 0 && !bankFingerprint.isEmpty && laneID == "mixed" && editorialPolicy?.isSupported != false }
    init(strategy: NFReservationStrategy, profileID: UUID, bank: NFVersionedOfflineQuestionBank) {
        strategyRaw = strategy.rawValue; self.profileID = profileID
        bankVersion = bank.version; bankFingerprint = bank.catalogFingerprint; laneID = "mixed"
    }
}
struct NFLocalAdaptiveItemReceipt: Codable, Equatable, Sendable {
    var schemaVersion = 1
    let decisionID: String
    let sessionID: UUID
    let ownerDeviceID: UUID
    let configurationDigest: String
    let questionIndex: Int
    let predecessorSlotID: UUID?
    let slotID: UUID
    let attemptID: UUID
    let exerciseDigest: String
    let plan: NFOfflineQuestionRotationPlan
    let eligibilityRevision: String
    var operationRaw: String? = nil
    var decisionOrdinal: UInt64? = nil
    var predecessorCheckpointDigest: String? = nil
    var editorialDecision: NFEditorialControllerDecision? = nil
    var mixedDecision: NFEditorialMixedDecision? = nil
    /// Exact condition when this slot was selected. A later display override
    /// never reclassifies an earlier receipt or its evidence group.
    var selectionTimingCondition: NFSessionTimingCondition? = nil

    var operation: NFReservationOperation? {
        schemaVersion == 1 ? (questionIndex == 0 ? .launch : .next) : operationRaw.flatMap(NFReservationOperation.init(rawValue:))
    }
    var effectiveDecisionOrdinal: UInt64? {
        schemaVersion == 1 ? (questionIndex >= 0 ? UInt64(questionIndex) : nil) : decisionOrdinal
    }
    var isSupported: Bool {
        guard selectionTimingCondition.map({ condition in
            condition.isSupported && editorialDecision?.criterionSelection != nil
                && condition.mode?.rawValue == editorialDecision?.criterionSelection?.group.pacingConditionID
        }) ?? true else { return false }
        if schemaVersion == 1 {
            return questionIndex >= 0 && operationRaw == nil && decisionOrdinal == nil && predecessorCheckpointDigest == nil && editorialDecision == nil && mixedDecision == nil
        }
        guard (schemaVersion == 2 && editorialDecision == nil && mixedDecision == nil)
            || (schemaVersion == 3 && editorialDecision?.schemaVersion == 1 && editorialDecision?.isSupported == true && mixedDecision == nil)
            || (schemaVersion == 4 && editorialDecision?.schemaVersion == 2 && editorialDecision?.isSupported == true && mixedDecision == nil)
            || (schemaVersion == 5 && editorialDecision?.isSupported == true && mixedDecision?.isSupported == true) else { return false }
        guard let operation, decisionOrdinal != nil else { return false }
        if operation == .replace {
            return predecessorSlotID != nil && predecessorCheckpointDigest?.count == 64
                && predecessorCheckpointDigest?.allSatisfy({ "0123456789abcdef".contains($0) }) == true
        }
        return predecessorCheckpointDigest == nil
    }
}

/// A replaced editor remains readable without duplicating its retained exercise
/// payload. Its snapshot is authenticated by slot ID and exerciseDigest.
struct NFLocalRetiredOrdinaryDraft: Codable, Equatable, Sendable {
    var schemaVersion = 1
    var eventKind = "itemReplacedByUser"
    let sessionID: UUID
    let ownerDeviceID: UUID
    let replacementDecisionID: String
    let checkpoint: NFLocalItemCheckpoint
    let checkpointDigest: String
    let replacedAt: Date

    static func retainedCheckpoint(_ original: NFLocalItemCheckpoint) -> NFLocalItemCheckpoint {
        var value = original
        value.exercise = nil
        return value
    }
    static func digest(_ checkpoint: NFLocalItemCheckpoint) throws -> String {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let bytes = try encoder.encode(retainedCheckpoint(checkpoint))
        guard var object = try JSONSerialization.jsonObject(with: bytes) as? [String: Any] else {
            throw NFLocalSessionRepository.RepositoryError.corruptSnapshot
        }
        object["semanticExclusions"] = checkpoint.semanticExclusions.sorted()
        return NFReservationSnapshot.digest(try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]))
    }
}
struct NFLocalAdaptiveItemPreparation: Sendable {
    let expectedArchiveRevision: UInt64
    let expectedRunRevision: Int?
    let request: SessionRequest
    let receipt: NFLocalAdaptiveItemReceipt
    let checkpoint: NFLocalItemCheckpoint
    let replacementRotationLedger: NFOfflineQuestionRotationLedger?
    let importsLegacy: Bool
    let legacySnapshot: NFOfflineQuestionRotationLedger?
    let replay: NFLocalSessionEnvelope?
    var overrideWriterAuthority: NFLocalWriterAuthority? = nil
    var sessionWriterCommand: NFSessionWriterCommand? = nil
}

struct NFLocalFixedLaunchPreparation: Sendable {
    let commandID: UUID
    let expectedArchiveRevision: UInt64
    let plan: NFOfflineQuestionRotationPlan
    let replacementRotationLedger: NFOfflineQuestionRotationLedger?
    let importsLegacy: Bool
    let legacySnapshot: NFOfflineQuestionRotationLedger?
    let replay: NFLocalSessionEnvelope?
    var bank: NFVersionedOfflineQuestionBank? = nil
}

/// An atomic file replacement is the acknowledgement boundary. In-memory state is
/// published only after the replacement succeeds; failures leave the predecessor.
@MainActor
@Observable
final class NFLocalSessionRepository {
    struct Archive: Codable, Sendable {
        var schemaVersion = 1
        var sessions: [NFLocalSessionEnvelope] = []
        var snapshots: [NFLocalAttemptSnapshot] = []
        var savedSets: [NFLocalSavedStudySet]?
        var privateStudyRuns: [NFLocalPrivateStudyRun]?
        var evidenceDispositions: [NFHistoricalPracticeDispositionRecord]?
        var contentCorrections: [NFHistoricalContentCorrectionRecommendation]?
        var attemptConflicts: [NFAttemptConflictJournalEntry]?
        var withheldProtectedConflictAttemptIDs: [UUID]?
        var activeContentCorrectionIDs: [String: [String]]?
        var selectionLedger: NFSelectionReservationLedger?
        var transactionRevision: UInt64?
        var offlineRotationLedger: NFOfflineQuestionRotationLedger?
        var rotationMigration: NFLocalRotationMigrationReceipt?
        var fixedLaunchReceipts: [String: NFLocalFixedLaunchReceipt]?
        var adaptiveItemReceipts: [String: NFLocalAdaptiveItemReceipt]?
        var editorialOverrideCommands: [String: NFEditorialOverrideCommand]?
        var editorialExplanationPresentations: [String: NFEditorialExplanationPresentation]?
        var retiredOrdinaryDrafts: [String: NFLocalRetiredOrdinaryDraft]?
        var deletedAdaptiveRunIDs: Set<UUID>?
        var deletedFixedLaunchCommandIDs: Set<String>?
        var dismissedCorrectionIDs: Set<String>?
        var unavailablePrivateRunIDs: [UUID]?
        var unavailableHistorySnapshots: [NFUnavailableHistorySnapshot]?
    }
    enum RepositoryError: Error, LocalizedError {
        case unsupportedVersion, corruptSnapshot, conflictingAttempt, wrongOwner, oversized, staleRevision, unavailableLaunch, busy
        var errorDescription: String? {
            switch self {
            case .unsupportedVersion: "This saved work needs a newer version of NeuroForge."
            case .corruptSnapshot: "This saved question could not be verified. Your original answer is retained."
            case .conflictingAttempt: "Two different answers have the same saved identity. Your work is retained for recovery."
            case .wrongOwner: "This session was saved on another device. Its answer is available for review."
            case .oversized: "This saved work exceeds the supported size. Your original file is retained."
            case .staleRevision: "Saved work changed in another window. Your answer is retained. Retry from the latest saved state."
            case .unavailableLaunch: "No fresh question is available for this activity. Your completed answers are saved. Choose another activity or return later."
            case .busy: "Saved work is busy. Your work is retained. Please try again."
            }
        }
    }
    nonisolated static let maximumBytes = 64 * 1_024 * 1_024
    static let folderName = "NeuroForge/LocalLearning"
    static let shared = NFLocalSessionRepository.persistent()
    private static var scopedRepositories: [String: NFLocalSessionRepository] = [:]
    private static var persistentRepositories: [String: NFLocalSessionRepository] = [:]
    nonisolated private static let publicationLock = NSLock()

    /// Match the established durable-store account namespace. New local private
    /// snapshots must never follow the next account into its unrelated history.
    private static func durableNamespace(at storeURL: URL) -> String {
        SHA256.hash(data: Data(storeURL.standardizedFileURL.path.utf8)).map { String(format: "%02x", $0) }.joined()
    }
    static func forDurableStore(at storeURL: URL) -> NFLocalSessionRepository {
        let namespace = durableNamespace(at: storeURL)
        if let existing = scopedRepositories[namespace] { return existing }
        let repository = persistent(namespace: namespace)
        scopedRepositories[namespace] = repository
        return repository
    }
    let ownerDeviceID: UUID
    let editorialAdmissions: NFEditorialAdmissionContext
    private let url: URL?
    @ObservationIgnored private var acknowledgedOriginalDigest: String?
    @ObservationIgnored private var pendingWriteTicket: NFLocalArchiveWriteTicket?
    @ObservationIgnored private var deferredArchiveReloads: [ObjectIdentifier: () -> Void] = [:]
    var hasPendingArchiveWrite: Bool { pendingWriteTicket != nil }
    private(set) var archiveWriteVerificationNeeded = false
    #if DEBUG
    @ObservationIgnored private var debugArchiveWriteObserver: (@Sendable (NFLocalArchiveWriteStage, Bool) -> Void)?
    #endif
    @ObservationIgnored private var startupPublicationGeneration: UInt64 = 0
    private(set) var archive = Archive() {
        didSet { capturedEditorialSnapshots = nil; startupPublicationGeneration &+= 1 }
    }
    @ObservationIgnored private var capturedEditorialSnapshots: [UUID: NFLocalAttemptSnapshot]?
    func editorialSnapshot(for attemptID: UUID) -> NFLocalAttemptSnapshot? {
        if capturedEditorialSnapshots == nil {
            capturedEditorialSnapshots = Dictionary(archive.snapshots.filter { $0.editorialCapture != nil }
                .map { ($0.attemptID, $0) }, uniquingKeysWith: { original, _ in original })
        }
        return capturedEditorialSnapshots?[attemptID]
    }
    private(set) var loadError: String?
    private let writerRepositoryIdentity = UUID()
    private var writerGeneration = UUID()
    private var writerID: UUID?
    var hasActiveWriter: Bool { writerID != nil }
    private var writerSessionID: UUID?
    @ObservationIgnored private var writerCheckpoint: (() -> Bool)?

    func isWriter(_ id: UUID, sessionID: UUID) -> Bool {
        writerID == id && writerSessionID == sessionID
    }

    func writerAuthority(for id: UUID, sessionID: UUID) -> NFLocalWriterAuthority? {
        guard isWriter(id, sessionID: sessionID) else { return nil }
        return .init(repositoryIdentity: writerRepositoryIdentity, writerID: id,
            sessionID: sessionID, generation: writerGeneration)
    }

    func isWriter(_ authority: NFLocalWriterAuthority?, sessionID: UUID) -> Bool {
        acceptsWriterAuthority(authority, sessionID: sessionID)
    }

    private func acceptsWriterAuthority(_ authority: NFLocalWriterAuthority?, sessionID: UUID) -> Bool {
        guard let authority else { return false }
        return authority.repositoryIdentity == writerRepositoryIdentity
            && authority.generation == writerGeneration && authority.sessionID == sessionID
            && isWriter(authority.writerID, sessionID: sessionID)
    }

    func claimWriter(_ id: UUID, sessionID: UUID, checkpoint: @escaping () -> Bool) -> Bool {
        guard pendingWriteTicket == nil else { return false }
        if let writerID, writerID != id {
            if writerSessionID == sessionID { return false }
            guard writerCheckpoint?() != false else { return false }
        }
        if writerID != id || writerSessionID != sessionID { writerGeneration = UUID() }
        writerID = id
        writerSessionID = sessionID
        writerCheckpoint = checkpoint
        return true
    }

    func takeOver(_ id: UUID, sessionID: UUID, checkpoint: @escaping () -> Bool) -> Bool {
        guard pendingWriteTicket == nil else { return false }
        if writerID != nil, writerID != id, writerCheckpoint?() == false { return false }
        writerGeneration = UUID()
        writerID = id
        writerSessionID = sessionID
        writerCheckpoint = checkpoint
        return true
    }

    func releaseWriter(_ id: UUID) {
        guard writerID == id else { return }
        pendingWriteTicket?.cancelPreparation()
        writerID = nil
        writerSessionID = nil
        writerCheckpoint = nil
    }

    private init(emptyURL: URL, ownerDeviceID: UUID) {
        editorialAdmissions = .released
        url = emptyURL; self.ownerDeviceID = ownerDeviceID
    }

    init(url: URL? = nil, ownerDeviceID: UUID = UUID(),
         editorialAdmissions: NFEditorialAdmissionContext = .released) {
        self.editorialAdmissions = editorialAdmissions
        self.url = url
        self.ownerDeviceID = ownerDeviceID
        guard let url, FileManager.default.fileExists(atPath: url.path) else { return }
        do {
            let original = try Self.boundedData(at: url)
            let recovered = try Self.decodedArchive(original)
            archive = recovered.archive
            acknowledgedOriginalDigest = NFReservationSnapshot.digest(original)
            if recovered.requiresBackup { try preserveHistoryRecoveryOriginal(original) }
        } catch { loadError = error.localizedDescription }
    }

    nonisolated private static func boundedData(at url: URL, checkCancellation: () throws -> Void = {}) throws -> Data {
        try checkCancellation()
        guard let identity = try NFLocalSessionStartupFileIdentity.capture(at: url), identity.size >= 0,
              identity.size <= maximumBytes else { throw RepositoryError.oversized }
        let descriptor = Darwin.open(url.path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC | O_NONBLOCK)
        guard descriptor >= 0 else { throw CocoaError(.fileReadUnknown) }
        let file = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        defer { try? file.close() }
        var info = stat()
        guard fstat(descriptor, &info) == 0, info.st_mode & S_IFMT == S_IFREG,
              UInt64(truncatingIfNeeded: info.st_dev) == identity.device, UInt64(info.st_ino) == identity.inode else {
            throw RepositoryError.staleRevision
        }
        var data = Data(); data.reserveCapacity(Int(identity.size))
        while true {
            try checkCancellation()
            let chunk = try file.read(upToCount: min(1_024 * 1_024, maximumBytes + 1 - data.count)) ?? Data()
            guard !chunk.isEmpty else { break }
            data.append(chunk)
            guard data.count <= maximumBytes else { throw RepositoryError.oversized }
        }
        guard try NFLocalSessionStartupFileIdentity.capture(at: url) == identity else { throw RepositoryError.staleRevision }
        return data
    }

    /// Only independent attempted-history snapshots are decoded individually.
    /// Every session, ledger, receipt and global identity remains strictly decoded
    /// and validated as a whole. No accepted-run member is silently dropped.
    @inline(never)
    nonisolated private static func decodedArchive(_ data: Data, checkCancellation: () throws -> Void = {}) throws -> (archive: Archive, requiresBackup: Bool) {
        let decoded = try normalizedArchive(data, checkCancellation: checkCancellation)
        return (try validatedArchive(decoded.archive, checkCancellation: checkCancellation), decoded.requiresBackup)
    }

    @inline(never)
    nonisolated private static func normalizedArchive(_ data: Data, checkCancellation: () throws -> Void) throws -> (archive: Archive, requiresBackup: Bool) {
        try checkCancellation()
        guard data.count <= maximumBytes else { throw RepositoryError.oversized }
        guard var object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let version = object["schemaVersion"] as? Int, version == 1 else {
            throw RepositoryError.unsupportedVersion
        }
        guard let rawSnapshots = object["snapshots"] as? [Any] else { throw RepositoryError.corruptSnapshot }
        var identifiers: Set<UUID> = []
        var retained: [Any] = []
        var unavailable: [NFUnavailableHistorySnapshot] = []
        for raw in rawSnapshots {
            try checkCancellation()
            guard let entry = raw as? [String: Any], let rawID = entry["attemptID"] as? String,
                  let attemptID = UUID(uuidString: rawID), identifiers.insert(attemptID).inserted else {
                throw RepositoryError.conflictingAttempt
            }
            let bytes = try JSONSerialization.data(withJSONObject: entry, options: [.sortedKeys])
            let reason: NFUnavailableHistorySnapshot.Reason?
            let rawExercise = entry["exercise"] as? [String: Any] ?? [:]
            if rawExercise["assessmentProtected"] as? Bool == true { reason = .protectedContent }
            else if bytes.count > NFSelectionReservationPolicy.maximumSnapshotBytes { reason = .oversized }
            else if let snapshot = try? JSONDecoder().decode(NFLocalAttemptSnapshot.self, from: bytes) {
                if snapshot.exercise.assessmentProtected { reason = .protectedContent }
                else if !NFExerciseSchemaValidator.supportsExerciseSchemaVersion(snapshot.exercise.schemaVersion) {
                    reason = .unsupportedExerciseVersion
                } else if !snapshot.exercise.hasSupportedTraceContract
                    || !(snapshot.traceInspection.map({ $0.isValid(for: snapshot.exercise) }) ?? true)
                    || snapshot.dataInspection?.isCompatible(with: snapshot.exercise) == false
                    || !NFScienceStudyDraft.permits(snapshot.scienceStudy, exercise: snapshot.exercise)
                    || !NFTransferRelationshipDraft.permits(snapshot.transferRelationship, exercise: snapshot.exercise) {
                    reason = .malformed
                } else { reason = nil }
            } else { reason = .malformed }
            if let reason {
                unavailable.append(.init(attemptID: attemptID, digest: NFReservationSnapshot.digest(bytes), reason: reason))
            } else { retained.append(entry) }
        }
        object["snapshots"] = retained
        // Strictly decode pre-existing markers and every unrelated field before
        // publishing a recovered projection or preserving a backup.
        try checkCancellation()
        let normalized = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        var archive = try JSONDecoder().decode(Archive.self, from: normalized)
        let priorIDs = Set((archive.unavailableHistorySnapshots ?? []).map(\.attemptID))
        guard unavailable.allSatisfy({ !priorIDs.contains($0.attemptID) }) else { throw RepositoryError.conflictingAttempt }
        if !unavailable.isEmpty {
            archive.unavailableHistorySnapshots = (archive.unavailableHistorySnapshots ?? []) + unavailable
        }
        return (archive, !unavailable.isEmpty)
    }

    /// Original corrupt content may contain private data or hidden protected
    /// fields. This directory is local-only and never appears in Archive/export.
    var historyRecoveryDirectoryURL: URL? { url?.appendingPathExtension("history-recovery") }

    private func preserveHistoryRecoveryOriginal(_ data: Data) throws {
        guard let url else { return }
        try Self.preserveHistoryRecoveryOriginal(data, at: url)
    }
    nonisolated private static func preserveHistoryRecoveryOriginal(_ data: Data, at url: URL) throws {
        let directory = url.appendingPathExtension("history-recovery")
        guard data.count <= Self.maximumBytes else { throw RepositoryError.oversized }
        let manager = FileManager.default
        if manager.fileExists(atPath: directory.path) {
            let attributes = try manager.attributesOfItem(atPath: directory.path)
            guard attributes[.type] as? FileAttributeType == .typeDirectory else { throw RepositoryError.corruptSnapshot }
        } else {
            try manager.createDirectory(at: directory, withIntermediateDirectories: false,
                attributes: [.posixPermissions: 0o700])
        }
        try manager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
        let target = directory.appending(path: NFReservationSnapshot.digest(data) + ".json")
        if manager.fileExists(atPath: target.path) {
            guard try manager.attributesOfItem(atPath: target.path)[.type] as? FileAttributeType == .typeRegular else {
                throw RepositoryError.corruptSnapshot
            }
            try manager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: target.path)
            guard try Self.boundedData(at: target) == data else { throw RepositoryError.corruptSnapshot }
            return
        }
        let files = try manager.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.fileSizeKey])
        var total = data.count
        for file in files {
            let size = try file.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? Self.maximumBytes
            guard size >= 0, size <= Self.maximumBytes - total else { throw RepositoryError.oversized }
            total += size
        }
        #if os(iOS)
        try data.write(to: target, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        #else
        // The containing directory is private before an atomic writer creates
        // any temporary bytes; the final file is private as well.
        try data.write(to: target, options: [.atomic])
        try manager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: target.path)
        #endif
        guard try Self.boundedData(at: target) == data else { throw RepositoryError.corruptSnapshot }
    }

    /// Privacy cleanup cannot attribute corrupt opaque bytes safely. Any linked
    /// content deletion conservatively removes this diagnostic backup directory.
    func purgeHistoryRecoveryBackups() throws {
        try requireArchiveWriteAvailability()
        guard let directory = historyRecoveryDirectoryURL,
              FileManager.default.fileExists(atPath: directory.path) else { return }
        try FileManager.default.removeItem(at: directory)
    }

    // Keep independent validation phases out of one enormous Swift debug
    // frame. These same checks run on ordinary-size iOS storage-worker stacks,
    // including cold restore and autosave; no phase is skipped or moved to UI.
    @inline(never)
    nonisolated private static func validatedArchive(_ input: Archive, checkCancellation: () throws -> Void = {}) throws -> Archive {
        try checkCancellation()
        var decoded = input
        try validateArchiveIdentities(decoded, checkCancellation: checkCancellation)
        try classifyArchiveSessionCompatibility(&decoded, checkCancellation: checkCancellation)
        try validateArchiveHistorySnapshots(decoded, checkCancellation: checkCancellation)
        try validateArchiveRotationAndFixedReceipts(decoded, checkCancellation: checkCancellation)
        try validateArchiveAdaptiveReceipts(&decoded, checkCancellation: checkCancellation)
        try validateArchiveOverrideCommands(&decoded, checkCancellation: checkCancellation)
        try validateArchiveEditorialDecisions(decoded, checkCancellation: checkCancellation)
        try validateEditorialExplanationPresentations(decoded, checkCancellation: checkCancellation)
        try validateArchiveAdaptiveRunLineage(decoded, checkCancellation: checkCancellation)
        try validateArchiveRetiredDrafts(&decoded, checkCancellation: checkCancellation)
        return decoded
    }

    @inline(never)
    nonisolated private static func validateArchiveIdentities(_ decoded: Archive, checkCancellation: () throws -> Void) throws {
    guard decoded.schemaVersion == 1 else { throw RepositoryError.unsupportedVersion }
    try Self.validateAttemptConflicts(decoded.attemptConflicts ?? [], checkCancellation: checkCancellation)
    if let ledger = decoded.selectionLedger { try Self.validateSelectionLedger(ledger, checkCancellation: checkCancellation) }
    guard Set(decoded.sessions.map(\.id)).count == decoded.sessions.count,
          Set(decoded.snapshots.map(\.attemptID)).count == decoded.snapshots.count,
          Set((decoded.evidenceDispositions ?? []).map(\.id)).count == (decoded.evidenceDispositions ?? []).count,
          Set((decoded.contentCorrections ?? []).map(\.id)).count == (decoded.contentCorrections ?? []).count else {
        throw RepositoryError.conflictingAttempt
    }
    let unavailable = decoded.unavailableHistorySnapshots ?? []
    guard Set(unavailable.map(\.attemptID)).count == unavailable.count,
          unavailable.allSatisfy({ $0.digest.count == 64 && $0.digest.allSatisfy { $0.isHexDigit } }),
          Set(unavailable.map(\.attemptID)).isDisjoint(with: Set(decoded.snapshots.map(\.attemptID))) else {
        throw RepositoryError.conflictingAttempt
    }
    }

    @inline(never)
    nonisolated private static func classifyArchiveSessionCompatibility(_ decoded: inout Archive, checkCancellation: () throws -> Void) throws {
    for index in decoded.sessions.indices {
            try checkCancellation()
        let checkpoint = decoded.sessions[index].checkpoint
        let invalidVersion = decoded.sessions[index].schemaVersion != 1 || checkpoint.schemaVersion != 1
        let invalidSnapshot = checkpoint.exercise.map {
            $0.assessmentProtected || (try? NFLocalItemCheckpoint.digest($0)) != checkpoint.exerciseDigest
        } ?? false
        let presentationPin = decoded.selectionLedger?.runs[decoded.sessions[index].id.uuidString]?.versions.presentationVersion
        let unsupportedPresentation = presentationPin.map { !NFSessionPresentationPolicy.supportedVersions.contains($0) } ?? false
        let unsupportedTiming = decoded.sessions[index].request.timingCondition?.isSupported == false
            || !checkpoint.hasSupportedTimingCondition || !checkpoint.hasSupportedMathWork || !checkpoint.hasSupportedDataInspection || !checkpoint.hasSupportedScienceStudy || !decoded.sessions[index].request.hasSupportedScienceStudyPolicy || !checkpoint.hasSupportedGraphConstruction || !decoded.sessions[index].request.permitsSpatialAssembly(exercise:checkpoint.exercise) || !decoded.sessions[index].request.permitsCoordinateReasoning(exercise:checkpoint.exercise) || !decoded.sessions[index].request.permitsNetFolding(exercise:checkpoint.exercise) || !decoded.sessions[index].request.permitsSolidSection(exercise: checkpoint.exercise) || !decoded.sessions[index].request.permitsCoordinateTransform(exercise: checkpoint.exercise) || !decoded.sessions[index].request.permitsSpatialStructure(exercise: checkpoint.exercise) || !decoded.sessions[index].request.permitsRetrievalAsset(exercise: checkpoint.exercise) || !decoded.sessions[index].request.permitsRetrievalAuthority(exercise: checkpoint.exercise) || !decoded.sessions[index].request.hasSupportedGraphConstructionPolicy || !decoded.sessions[index].request.permitsGraphConstruction(exercise: checkpoint.exercise) || !checkpoint.hasSupportedTransferRelationship || !decoded.sessions[index].request.supportsTransferRecipe(in: checkpoint) || !checkpoint.hasSupportedTraceInspection
        let invalidDuration = !checkpoint.hasValidTimingDurations || !decoded.sessions[index].request.hasValidTimingDurations
        let delivery = decoded.sessions[index].request.ordinaryDelivery
        let unsupportedDelivery = delivery.map { !$0.isSupported } ?? false
        let missingAdaptiveAuthority = delivery?.strategy == .adaptiveItem && (
            checkpoint.ordinaryReservationDecisionID.flatMap { decoded.adaptiveItemReceipts?[$0] } == nil
                || decoded.offlineRotationLedger == nil)
        if invalidVersion || invalidSnapshot || unsupportedPresentation || unsupportedTiming || invalidDuration || unsupportedDelivery || missingAdaptiveAuthority {
            decoded.sessions[index].status = .migrationRecovery
        }
    }
    }

    @inline(never)
    nonisolated private static func validateArchiveHistorySnapshots(_ decoded: Archive, checkCancellation: () throws -> Void) throws {
        for snapshot in decoded.snapshots {
            try checkCancellation()
            guard !snapshot.exercise.assessmentProtected, snapshot.exercise.hasSupportedTraceContract,
                  snapshot.traceInspection.map({ $0.isValid(for: snapshot.exercise) }) ?? true,
                  snapshot.dataInspection?.isCompatible(with: snapshot.exercise) != false,
                  NFScienceStudyDraft.permits(snapshot.scienceStudy, exercise: snapshot.exercise),
                  NFTransferRelationshipDraft.permits(snapshot.transferRelationship, exercise: snapshot.exercise) else { throw RepositoryError.corruptSnapshot }
        }
    }

    @inline(never)
    nonisolated private static func validateArchiveRotationAndFixedReceipts(_ decoded: Archive, checkCancellation: () throws -> Void) throws {
        if let rotation = decoded.offlineRotationLedger {
            guard rotation.schemaVersion == NFOfflineQuestionRotationLedger.schemaVersion,
                  let migration = decoded.rotationMigration, migration.schemaVersion == 1,
                  migration.sourceDigest.count == 64,
                  migration.sourceRevision.map({ $0 < rotation.revision }) ?? true,
                  rotation.scopes.values.allSatisfy({ !$0.bankFingerprint.isEmpty && $0.hasValidConsumption
                    && Set($0.boundaryExclusions).count == $0.boundaryExclusions.count }) else { throw RepositoryError.corruptSnapshot }
        } else if decoded.rotationMigration != nil || decoded.fixedLaunchReceipts?.isEmpty == false {
            throw RepositoryError.corruptSnapshot
        }
        for (key, receipt) in decoded.fixedLaunchReceipts ?? [:] {
            try checkCancellation()
            guard key == receipt.commandID.uuidString, receipt.sessionID == receipt.commandID,
                  receipt.acceptedInputConfigurationDigest.map({ $0.count == 64 }) ?? true,
                  !(decoded.deletedFixedLaunchCommandIDs ?? []).contains(key),
                  let run = decoded.sessions.first(where: { $0.id == receipt.sessionID }),
                  run.request.id == receipt.commandID, run.request.offlineRotationPlan == receipt.plan,
                  try NFLocalReservationBridge.configurationDigest(run.request) == receipt.configurationDigest,
                  !receipt.plan.items.isEmpty,
                  let rotationScope = decoded.offlineRotationLedger?.scopes[NFOfflineQuestionRotation.scopeKey(
                    profileID: receipt.plan.profileID, lab: receipt.plan.lab, laneID: receipt.plan.laneID, bankVersion: receipt.plan.bankVersion)],
                  receipt.plan.reservationOrdinal < rotationScope.nextReservationOrdinal,
                  receipt.plan.items.enumerated().allSatisfy({
                    $0.offset == $0.element.quizOrdinal && $0.element.epochOrdinal >= 0 && $0.element.epochOrdinal < rotationScope.bankQuestionCount
                    && rotationScope.containsConsumed(epoch: $0.element.epoch, ordinal: $0.element.epochOrdinal)
                  }),
                  Set(receipt.plan.items.map(\.questionID)).count == receipt.plan.items.count,
                  Set(receipt.plan.items.map { NFReservationPosition(epoch: $0.epoch, ordinal: $0.epochOrdinal) }).count == receipt.plan.items.count else { throw RepositoryError.corruptSnapshot }
        }
    }

    @inline(never)
    nonisolated private static func validateArchiveAdaptiveReceipts(_ decoded: inout Archive, checkCancellation: () throws -> Void) throws {
        for (key, receipt) in decoded.adaptiveItemReceipts ?? [:] {
            try checkCancellation()
            guard let runIndex = decoded.sessions.firstIndex(where: { $0.id == receipt.sessionID }),
                  let pin = decoded.sessions[runIndex].request.ordinaryDelivery else { throw RepositoryError.corruptSnapshot }
            if !receipt.isSupported || !pin.isSupported {
                decoded.sessions[runIndex].status = .migrationRecovery
                continue
            }
            let run = decoded.sessions[runIndex]
            guard let ordinal = receipt.effectiveDecisionOrdinal, let operation = receipt.operation,
                  pin.strategy == .adaptiveItem, key == receipt.decisionID, receipt.ownerDeviceID == run.ownerDeviceID,
                  (receipt.editorialDecision == nil) == (pin.editorialPolicy == nil),
                  receipt.editorialDecision.map({ decision in
                    decision.controlBefore.sessionID == run.id.uuidString
                        && decision.selection.catalogVersion == pin.editorialPolicy?.catalogVersion
                        && decision.controllerVersion == pin.editorialPolicy?.familyControllerVersion
                        && pin.editorialPolicy?.contains(objectiveID: decision.controlBefore.objectiveID, familyID: decision.controlBefore.familyID) == true
                        && (receipt.mixedDecision != nil) == (pin.editorialPolicy?.isMixed == true)
                        && decision.admission.exerciseDigest == receipt.exerciseDigest
                        && decision.admission.bankQuestionID == receipt.plan.items.first?.questionID
                  }) ?? true,
                  receipt.questionIndex >= 0, receipt.questionIndex <= run.checkpoint.index,
                  receipt.questionIndex < (run.request.requestedItemCount ?? 5),
                  receipt.slotID == Self.adaptiveIdentity(key, role: "slot"),
                  receipt.attemptID == Self.adaptiveIdentity(key, role: "attempt"),
                  key == NFSelectionReservationPolicy.decisionID(runID: run.id.uuidString, ordinal: ordinal),
                  !(decoded.deletedAdaptiveRunIDs ?? []).contains(run.id), receipt.plan.items.count == 1,
                  receipt.plan.profileID == pin.profileID, receipt.plan.lab == run.request.lab,
                  receipt.plan.bankVersion == pin.bankVersion, receipt.plan.laneID == pin.laneID,
                  receipt.configurationDigest == (try NFLocalReservationBridge.configurationDigest(run.request)),
                  receipt.eligibilityRevision.count == 64,
                  receipt.eligibilityRevision.allSatisfy({ "0123456789abcdef".contains($0) }),
                  let item = receipt.plan.items.first, item.quizOrdinal == 0,
                  let scope = decoded.offlineRotationLedger?.scopes[NFOfflineQuestionRotation.scopeKey(
                    profileID: pin.profileID, lab: run.request.lab, laneID: pin.laneID, bankVersion: pin.bankVersion)],
                  scope.bankFingerprint == pin.bankFingerprint,
                  receipt.plan.reservationOrdinal < scope.nextReservationOrdinal,
                  scope.containsConsumed(epoch: item.epoch, ordinal: item.epochOrdinal),
                  let ledger = decoded.selectionLedger, let slot = ledger.slots[receipt.slotID.uuidString],
                  slot.runID == run.id.uuidString, slot.attemptID == receipt.attemptID.uuidString,
                  slot.decisionID == key, slot.plannedQuestionOrdinal == receipt.questionIndex,
                  slot.snapshotDigest == receipt.exerciseDigest, slot.candidateID == item.questionID,
                  slot.position == NFReservationPosition(epoch: item.epoch, ordinal: item.epochOrdinal),
                  ledger.decisions[key]?.command.predecessorSlotID == receipt.predecessorSlotID?.uuidString,
                  ledger.decisions[key]?.command.operation == operation,
                  ledger.decisions[key]?.command.decisionOrdinal == ordinal,
                  ledger.decisions[key]?.command.strategy == .adaptiveItem,
                  ledger.decisions[key]?.acceptedSlotIDs == [slot.id] else { throw RepositoryError.corruptSnapshot }
            if operation == .replace {
                guard let priorID = receipt.predecessorSlotID,
                      let retired = decoded.retiredOrdinaryDrafts?[priorID.uuidString],
                      retired.replacementDecisionID == receipt.decisionID,
                      retired.checkpointDigest == receipt.predecessorCheckpointDigest,
                      ledger.slots[priorID.uuidString]?.status == .replaced,
                      slot.replacesSlotID == priorID.uuidString else { throw RepositoryError.corruptSnapshot }
            }
        }
    }

    @inline(never)
    nonisolated private static func validateArchiveOverrideCommands(_ decoded: inout Archive, checkCancellation: () throws -> Void) throws {
        guard (decoded.editorialOverrideCommands?.count ?? 0) <= 4_096 else { throw RepositoryError.oversized }
        for (key, command) in decoded.editorialOverrideCommands ?? [:] {
            try checkCancellation()
            guard let runIndex = decoded.sessions.firstIndex(where: { $0.id == command.sessionID }) else { throw RepositoryError.corruptSnapshot }
            if !command.isSupported { decoded.sessions[runIndex].status = .migrationRecovery; continue }
            guard key == command.id.uuidString, command.ownerDeviceID == decoded.sessions[runIndex].ownerDeviceID,
                  let prior = decoded.adaptiveItemReceipts?.values.first(where: { $0.slotID == command.slotID }),
                  prior.sessionID == command.sessionID,
                  let decision = prior.editorialDecision,
                  command.objectiveID == decision.controlAfter.objectiveID,
                  command.familyID == decision.controlAfter.familyID,
                  command.controlDigest == (try NFEditorialCanonicalData.digest(decision.controlAfter)),
                  command.targetBand == (try command.action.target(deliveredBand: decision.selection.deliveredBand,
                    targetBand: decision.controlAfter.currentTargetBand)),
                  command.predecessorCommandID.map({ id in
                    guard let previous = decoded.editorialOverrideCommands?[id.uuidString] else { return false }
                    return previous.sessionID == command.sessionID && previous.slotID == command.slotID
                        && previous.id != command.id && previous.createdAt <= command.createdAt
                  }) ?? true else { throw RepositoryError.corruptSnapshot }
        }
        let unsupportedCommandSlots = Set((decoded.editorialOverrideCommands ?? [:]).values.filter { !$0.isSupported }.map(\.slotID))
        let commandGroups = Dictionary(grouping: (decoded.editorialOverrideCommands ?? [:]).values.filter {
            $0.isSupported && !unsupportedCommandSlots.contains($0.slotID)
        }, by: \.slotID)
        for group in commandGroups.values {
            let superseded = Set(group.compactMap(\.predecessorCommandID))
            let heads = group.filter { !superseded.contains($0.id) }
            guard heads.count == 1 else { throw RepositoryError.corruptSnapshot }
            var visited: Set<UUID> = []
            var current: UUID? = heads[0].id
            while let id = current {
                try checkCancellation()
                guard visited.insert(id).inserted else { throw RepositoryError.corruptSnapshot }
                current = decoded.editorialOverrideCommands?[id.uuidString]?.predecessorCommandID
            }
            // One walk per slot also catches disconnected cycles and branches.
            guard visited.count == group.count else { throw RepositoryError.corruptSnapshot }
        }
    }

    @inline(never)
    nonisolated private static func validateArchiveEditorialDecisions(_ decoded: Archive, checkCancellation: () throws -> Void) throws {
        for receipt in (decoded.adaptiveItemReceipts ?? [:]).values where receipt.editorialDecision != nil {
            try checkCancellation()
            guard let decision = receipt.editorialDecision, receipt.isSupported, decision.isSupported else { continue }
            // The first pass already retained unsupported run pins as recovery
            // work. Do not interpret their controller graph under today's rules
            // or turn one future run into a corrupt whole archive.
            guard let run = decoded.sessions.first(where: { $0.id == receipt.sessionID }),
                  run.request.ordinaryDelivery?.editorialPolicy?.isSupported == true else { continue }
            if let command = decision.overrideCommand {
                guard decoded.editorialOverrideCommands?[command.id.uuidString] == command,
                      command.slotID == receipt.predecessorSlotID,
                      command.boundary == (receipt.operation == .replace ? .replaceCurrent : .nextQuestion) else { throw RepositoryError.corruptSnapshot }
            }
            if receipt.mixedDecision != nil {
                try Self.validateMixedDecision(receipt, archive: decoded)
            } else if let predecessor = receipt.predecessorSlotID {
                guard let prior = decoded.adaptiveItemReceipts?.values.first(where: { $0.slotID == predecessor }),
                      decision.controlBefore == prior.editorialDecision?.controlAfter,
                      decision.initialTargetDecision == prior.editorialDecision?.initialTargetDecision,
                      decision.initialReason == prior.editorialDecision?.initialReason,
                      decision.supportPresentation.map({ $0.slotID == predecessor.uuidString }) ?? true
                      else { throw RepositoryError.corruptSnapshot }
            } else if decision.controlBefore.decisionOrdinal != 0 { throw RepositoryError.corruptSnapshot }
            if decision.controlBefore.decisionOrdinal == 0, let initial = decision.initialTargetDecision {
                guard Set(initial.supportingObservationIDs).isSubset(of: Set(decision.evidence.independentObservationIDs)),
                      initial.lastRelevantPracticeDay.map({ $0 <= decision.decisionDay.ordinal }) ?? true else { throw RepositoryError.corruptSnapshot }
                if let group = initial.evidenceGroup {
                    guard let slot = decoded.selectionLedger?.slots[receipt.slotID.uuidString],
                          let ledger = decoded.selectionLedger,
                          let snapshot = NFSelectionReservationPolicy.snapshot(for: slot, in: ledger),
                          let exercise = try? JSONDecoder().decode(NFExercise.self, from: snapshot.payload),
                          NFEditorialInitialTargetContract.make(exercise: exercise, admission: decision.admission).matches(group),
                          initial.basis != .demonstratedPractice || decision.evidence.summaries.contains(where: {
                            $0.group == group && $0.lastDemonstratedAt == initial.lastDemonstratedAt
                                && $0.coverage != .evidenceAffected && $0.coverage != .notCurrentlySupported
                          }) else { throw RepositoryError.corruptSnapshot }
                }
            }
            try validateEditorialCriterionSelection(receipt, decision: decision, archive: decoded)
            try validateEditorialReviewAssignment(receipt, decision: decision, archive: decoded)
            try validateEditorialGoalSelection(receipt, decision: decision, archive: decoded)
            let input = NFEditorialLiveController.FrozenInputIdentity(observationDigests: decision.observationDigests,
                validity: decision.validity, day: decision.decisionDay)
            guard try NFEditorialCanonicalData.digest(input) == decision.evidenceDigest,
                  decision.observationDigests.values.allSatisfy({ $0.count == 64 && $0.allSatisfy(\.isHexDigit) }),
                  Set(decision.evidence.independentObservationIDs).isSubset(of: Set(decision.observationDigests.keys)),
                  decision.evidence.decisionDayOrdinal == decision.decisionDay.ordinal,
                  decision.evidence.summaries.allSatisfy({ $0.creditSum.isFinite && $0.creditSum >= 0
                    && $0.creditSum <= Double($0.count) && ($0.recentMeanCredit.map { $0.isFinite && (0...1).contains($0) } ?? true) })
                  else { throw RepositoryError.corruptSnapshot }
        }
    }

    @inline(never)
    nonisolated private static func validateEditorialCriterionSelection(_ receipt: NFLocalAdaptiveItemReceipt,
        decision: NFEditorialControllerDecision, archive: Archive) throws {
        if let criterion = decision.criterionSelection {
                guard let run = archive.sessions.first(where: { $0.id == receipt.sessionID }),
                      let timing = NFEditorialTimingMode(rawValue: criterion.group.pacingConditionID),
                      let slot = archive.selectionLedger?.slots[receipt.slotID.uuidString],
                      let ledger = archive.selectionLedger,
                      let snapshot = NFSelectionReservationPolicy.snapshot(for: slot, in: ledger),
                      let exercise = try? JSONDecoder().decode(NFExercise.self, from: snapshot.payload),
                      var expected = NFEditorialCriterionRankingPolicy.contract(exercise: exercise, admission: decision.admission,
                        timing: timing),
                      criterion.supportingObservationIDs.allSatisfy({ decision.validity.correctedScoreByObservationID[$0] == nil }) else {
                    throw RepositoryError.corruptSnapshot
                }
                if let condition = receipt.selectionTimingCondition {
                    guard condition.isSupported, condition.mode == timing,
                          condition.accepts(exercise, reviewedDemand: decision.admission.demand),
                          // Timed authority cannot be introduced by a display
                          // override. Only the original accepted scope grants it.
                          condition.mode != .timedFluency || condition == run.request.timingCondition,
                          receipt.predecessorSlotID != nil || condition == run.request.timingCondition else {
                        throw RepositoryError.corruptSnapshot
                    }
                } else {
                    // Known older receipts did not retain a per-slot condition.
                    // Preserve their original validation; do not backfill them
                    // from today's current checkpoint or display preference.
                    guard (run.request.timingCondition?.mode == .timedFluency) == (timing == .timedFluency) else {
                        throw RepositoryError.corruptSnapshot
                    }
                }
                expected.matches = criterion.matches
                guard expected == criterion else { throw RepositoryError.corruptSnapshot }
            }
    }

    @inline(never)
    nonisolated private static func validateArchiveAdaptiveRunLineage(_ decoded: Archive, checkCancellation: () throws -> Void) throws {
        for run in decoded.sessions where run.request.ordinaryDelivery?.strategy == .adaptiveItem
            && run.request.ordinaryDelivery?.isSupported == true {
            try checkCancellation()
            let receipts = (decoded.adaptiveItemReceipts ?? [:]).values.filter { $0.sessionID == run.id }
            // A portable recovery run deliberately has no device authority.
            guard !receipts.isEmpty, receipts.allSatisfy(\.isSupported) else { continue }
            let ordered = receipts.sorted { ($0.effectiveDecisionOrdinal ?? 0) < ($1.effectiveDecisionOrdinal ?? 0) }
            guard (0..<50).contains(run.checkpoint.index),
                  ordered.enumerated().allSatisfy({ $0.element.effectiveDecisionOrdinal == UInt64($0.offset) }),
                  ordered.first?.operation == .launch, ordered.first?.questionIndex == 0,
                  ordered.first?.predecessorSlotID == nil,
                  ordered.last?.slotID == run.checkpoint.slotID,
                  ordered.last?.attemptID == run.checkpoint.attemptID,
                  ordered.last?.decisionID == run.checkpoint.ordinaryReservationDecisionID,
                  ordered.last?.questionIndex == run.checkpoint.index,
                  ordered.last?.exerciseDigest == run.checkpoint.exerciseDigest,
                  decoded.selectionLedger?.runs[run.id.uuidString]?.slotIDs == ordered.map({ $0.slotID.uuidString }) else {
                throw RepositoryError.corruptSnapshot
            }
            for (prior, next) in zip(ordered, ordered.dropFirst()) {
                guard next.predecessorSlotID == prior.slotID,
                      next.operation == .replace ? next.questionIndex == prior.questionIndex
                        : (next.operation == .next && next.questionIndex == prior.questionIndex + 1) else {
                    throw RepositoryError.corruptSnapshot
                }
            }
        }
    }

    @inline(never)
    nonisolated private static func validateArchiveRetiredDrafts(_ decoded: inout Archive, checkCancellation: () throws -> Void) throws {
        for (key, retired) in decoded.retiredOrdinaryDrafts ?? [:] {
            try checkCancellation()
            guard let runIndex = decoded.sessions.firstIndex(where: { $0.id == retired.sessionID }) else { throw RepositoryError.corruptSnapshot }
            if retired.schemaVersion != 1 || retired.checkpoint.schemaVersion != 1 {
                decoded.sessions[runIndex].status = .migrationRecovery
                continue
            }
            let run = decoded.sessions[runIndex], checkpoint = retired.checkpoint
            guard run.request.ordinaryDelivery?.strategy == .adaptiveItem,
                  retired.eventKind == "itemReplacedByUser",
                  run.ownerDeviceID == retired.ownerDeviceID, run.checkpoint.slotID != checkpoint.slotID,
                  key == checkpoint.slotID.uuidString, checkpoint.exercise == nil,
                  checkpoint.descriptor == nil, checkpoint.protectedCommitReceipt == nil,
                  checkpoint.assessmentState == nil, checkpoint.assessmentCatalogSnapshot == nil,
                  checkpoint.committedAttemptID == nil, checkpoint.result == nil, checkpoint.pendingOutcome == nil,
                  checkpoint.phase == .item, checkpoint.hasValidTimingDurations,
                  retired.checkpointDigest == (try NFLocalRetiredOrdinaryDraft.digest(checkpoint)),
                  retired.replacedAt.timeIntervalSinceReferenceDate.isFinite,
                  let ledger = decoded.selectionLedger, let slot = ledger.slots[key],
                  slot.runID == run.id.uuidString, slot.attemptID == checkpoint.attemptID.uuidString,
                  slot.snapshotDigest == checkpoint.exerciseDigest, slot.status == .replaced,
                  let snapshot = NFSelectionReservationPolicy.snapshot(for: slot, in: ledger),
                  let exercise = try? JSONDecoder().decode(NFExercise.self, from: snapshot.payload),
                  !exercise.assessmentProtected, exercise.evidenceClass == .practice,
                  exercise.provenance.sourceDocumentIDs.isEmpty,
                  ledger.decisions[retired.replacementDecisionID]?.command.operation == .replace,
                  ledger.decisions[retired.replacementDecisionID]?.command.predecessorSlotID == key else {
                throw RepositoryError.corruptSnapshot
            }
        }
    }

    private static func persistentConfiguration(namespace: String? = nil) -> (url: URL, owner: UUID) {
        let defaults = UserDefaults.standard
        let key = "NeuroForge.localSessionOwner.v1"
        let owner = defaults.string(forKey: key).flatMap(UUID.init(uuidString:)) ?? UUID()
        defaults.set(owner.uuidString, forKey: key)
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let path = namespace.map { "\(folderName)/\($0)/sessions-v1.json" }
            ?? "\(folderName)/sessions-v1.json"
        let fileURL = base.appending(path: path)
        return (fileURL, owner)
    }
    static func persistent(namespace: String? = nil) -> NFLocalSessionRepository {
        let (fileURL, owner) = persistentConfiguration(namespace: namespace)
        if let existing = persistentRepositories[fileURL.path] { return existing }
        let repository = NFLocalSessionRepository(url: fileURL, ownerDeviceID: owner)
        persistentRepositories[fileURL.path] = repository
        return repository
    }

    /// Called only by the existing whole-device deletion journal after its
    /// durable intent has been saved. Covers inactive accounts and future or
    /// corrupt envelopes that cannot be decoded for ordinary record cleanup.
    /// The supplied support root also keeps disposable fixture purges isolated.
    static func purgeAllApplicationState(
        fileManager: FileManager = .default,
        applicationSupportURL: URL
    ) throws {
        let root = applicationSupportURL.appending(path: folderName, directoryHint: .isDirectory)
        let affectedPrefix = root.standardizedFileURL.path + "/"
        for repository in persistentRepositories.values {
            if repository.url?.standardizedFileURL.path.hasPrefix(affectedPrefix) == true {
                try repository.requireArchiveWriteAvailability()
            }
        }
        if fileManager.fileExists(atPath: root.path) { try fileManager.removeItem(at: root) }
        guard !fileManager.fileExists(atPath: root.path) else {
            throw NFPrivateCloudLocalPurgeError.verificationFailed
        }
        let prefix = root.standardizedFileURL.path + "/"
        for repository in persistentRepositories.values {
            guard let path = repository.url?.standardizedFileURL.path, path.hasPrefix(prefix) else { continue }
            repository.archive = Archive()
            repository.acknowledgedOriginalDigest = nil
            repository.loadError = nil
            repository.writerID = nil
            repository.writerSessionID = nil
            repository.writerCheckpoint = nil
        }
    }

    /// Planning is read-only. A proposal consumes neither the imported source
    /// nor the local cursor; only acceptFixedLaunch publishes it with the run.
    func prepareFixedLaunch(commandID: UUID, rotation: NFOfflineQuestionRotation,
                            profileID: UUID, lab: TrainingLab, laneID: String,
                            itemCount: Int, bank: NFVersionedOfflineQuestionBank) throws -> NFLocalFixedLaunchPreparation {
        guard loadError == nil, writerCheckpoint?() != false else { throw RepositoryError.corruptSnapshot }
        try withPublicationLock {
            if let latest = try readArchiveFromDisk() {
                archive = latest
            }
        }
        guard !(archive.deletedFixedLaunchCommandIDs ?? []).contains(commandID.uuidString) else { throw RepositoryError.conflictingAttempt }
        if let receipt = archive.fixedLaunchReceipts?[commandID.uuidString] {
            guard receipt.plan.profileID == profileID, receipt.plan.lab == lab, receipt.plan.laneID == laneID,
                  receipt.plan.items.count == itemCount,
                  let run = archive.sessions.first(where: { $0.id == receipt.sessionID }),
                  run.ownerDeviceID == ownerDeviceID, run.status != .migrationRecovery else { throw RepositoryError.conflictingAttempt }
            return .init(commandID: commandID, expectedArchiveRevision: archive.transactionRevision ?? 0,
                plan: receipt.plan, replacementRotationLedger: nil, importsLegacy: false,
                legacySnapshot: nil, replay: run)
        }
        let importsLegacy = archive.offlineRotationLedger == nil
        guard !importsLegacy || archive.rotationMigration == nil else { throw RepositoryError.corruptSnapshot }
        let source = try importsLegacy ? rotation.legacySnapshot() : archive.offlineRotationLedger
        let proposal = try rotation.prepareReservation(profileID: profileID, lab: lab, laneID: laneID,
            itemCount: itemCount, bank: bank, loadedLedger: source)
        return .init(commandID: commandID, expectedArchiveRevision: archive.transactionRevision ?? 0,
            plan: proposal.plan, replacementRotationLedger: proposal.replacement, importsLegacy: importsLegacy,
            legacySnapshot: importsLegacy ? source : nil, replay: nil, bank: bank)
    }

    /// Publishes cursor, full fixed plan, decision, exact first snapshot and run
    /// in one file replacement. Failed publication leaves every predecessor.
    func acceptFixedLaunch(_ preparation: NFLocalFixedLaunchPreparation, request: SessionRequest,
                           rotation: NFOfflineQuestionRotation, at date: Date = Date()) throws -> NFLocalSessionEnvelope {
        try withPublicationLock {
            let currentRevision = try diskRevision()
            guard currentRevision == (archive.transactionRevision ?? 0) else { throw RepositoryError.staleRevision }
            let configurationDigest = try NFLocalReservationBridge.configurationDigest(request)
            if let receipt = archive.fixedLaunchReceipts?[preparation.commandID.uuidString] {
                guard receipt.configurationDigest == configurationDigest || receipt.acceptedInputConfigurationDigest == configurationDigest,
                      let run = archive.sessions.first(where: { $0.id == receipt.sessionID }),
                      run.ownerDeviceID == ownerDeviceID else { throw RepositoryError.conflictingAttempt }
                return run
            }
            guard currentRevision == preparation.expectedArchiveRevision else { throw RepositoryError.staleRevision }
            guard !archive.sessions.contains(where: { $0.id == preparation.commandID }),
                  request.id == preparation.commandID, request.localSessionID == preparation.commandID,
                  request.source == .focused, request.evidenceClass == .practice, request.assessmentBlock == nil,
                  request.retentionTargets.isEmpty, request.retentionItemIDs.isEmpty, request.transferBrief == nil,
                  request.startingIndex == 0, request.localCheckpoint == nil,
                  preparation.plan.lab == request.lab, preparation.plan.items.count == (request.requestedItemCount ?? 5),
                  request.offlineRotationPlan == preparation.plan,
                  let replacement = preparation.replacementRotationLedger,
                  !(archive.deletedFixedLaunchCommandIDs ?? []).contains(preparation.commandID.uuidString) else { throw RepositoryError.conflictingAttempt }
            var acceptedRequest = request
            var acceptedReplacement = replacement
            let exercise: NFExercise
            if request.mechanicID == nil {
                guard let bank = preparation.bank, bank.version == preparation.plan.bankVersion,
                      request.offlineQuestionOrdinals == preparation.plan.items.compactMap({
                        NFOfflineQuestionBank.ordinal(forQuestionID: $0.questionID, lab: request.lab)
                      }) else { throw RepositoryError.corruptSnapshot }
                var seen = request.repairSemanticExclusions ?? []
                var firstExercise: NFExercise?
                let eligible: NFOfflineQuestionRotationProposal
                do {
                    eligible = try rotation.prepareReservation(profileID: preparation.plan.profileID, lab: request.lab,
                        laneID: preparation.plan.laneID, itemCount: preparation.plan.items.count, bank: bank,
                        loadedLedger: preparation.importsLegacy ? preparation.legacySnapshot : archive.offlineRotationLedger) { item in
                            guard let ordinal = NFOfflineQuestionBank.ordinal(forQuestionID: item.questionID, lab: request.lab) else { return false }
                            let candidateRequest = request.launchOnly(offlineQuestionOrdinals: [ordinal])
                            let candidate = NFDeterministicSessionExerciseFactory.makeExercise(request: candidateRequest, index: 0,
                                assessmentDescriptor: nil, excludingContentFingerprints: seen)
                            guard candidate.availabilityReason == nil, !candidate.assessmentProtected else { return false }
                            seen.insert(NFQuestionFingerprint.fingerprint(for: candidate))
                            firstExercise = firstExercise ?? candidate
                            return true
                        }
                } catch NFOfflineQuestionRotationError.insufficientEligibleQuestions {
                    throw RepositoryError.unavailableLaunch
                }
                guard let firstExercise, eligible.plan.id == preparation.plan.id else { throw RepositoryError.corruptSnapshot }
                acceptedRequest = request.launchOnly(offlineQuestionOrdinals: eligible.plan.items.compactMap {
                    NFOfflineQuestionBank.ordinal(forQuestionID: $0.questionID, lab: request.lab)
                })
                acceptedRequest.offlineRotationPlan = eligible.plan
                acceptedReplacement = eligible.replacement
                exercise = firstExercise
            } else {
                // Mechanic-filtered seed lanes do not claim exact bank delivery.
                exercise = NFDeterministicSessionExerciseFactory.makeExercise(request: request, index: 0, assessmentDescriptor: nil,
                    excludingContentFingerprints: request.repairSemanticExclusions ?? [])
            }
            guard exercise.availabilityReason == nil else { throw RepositoryError.unavailableLaunch }
            guard !exercise.assessmentProtected else { throw RepositoryError.corruptSnapshot }
            let acceptedConfigurationDigest = try NFLocalReservationBridge.configurationDigest(acceptedRequest)
            let checkpoint = try NFLocalItemCheckpoint.initial(request: acceptedRequest, exercise: exercise,
                slotID: Self.launchIdentity(preparation.commandID, role: "slot"),
                attemptID: Self.launchIdentity(preparation.commandID, role: "attempt"), at: date)
            let envelope = NFLocalSessionEnvelope(id: preparation.commandID, ownerDeviceID: ownerDeviceID,
                revision: 1, request: acceptedRequest.launchOnly(), checkpoint: checkpoint, status: .suspended, updatedAt: date)
            @MainActor func publish() throws -> NFLocalSessionEnvelope {
                var next = archive
                next.offlineRotationLedger = acceptedReplacement
                if preparation.importsLegacy {
                    let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
                    next.rotationMigration = .init(schemaVersion: 1,
                        sourceDigest: NFReservationSnapshot.digest(try encoder.encode(preparation.legacySnapshot)),
                        sourceRevision: preparation.legacySnapshot?.revision, importedAt: date)
                }
                next.selectionLedger = try NFLocalReservationBridge.accepting(envelope: envelope, ledger: next.selectionLedger ?? .init())
                next.sessions.append(envelope)
                var receipts = next.fixedLaunchReceipts ?? [:]
                receipts[preparation.commandID.uuidString] = .init(commandID: preparation.commandID,
                    sessionID: envelope.id, configurationDigest: acceptedConfigurationDigest,
                    plan: acceptedRequest.offlineRotationPlan ?? preparation.plan, acceptedInputConfigurationDigest: configurationDigest)
                next.fixedLaunchReceipts = receipts
                try replaceUnlocked(next)
                return envelope
            }
            if preparation.importsLegacy {
                // The production UserDefaults source holds its process lock
                // through publication. New launches never write it afterward.
                return try rotation.withLegacySnapshot { source in
                    guard source == preparation.legacySnapshot else { throw RepositoryError.staleRevision }
                    return try publish()
                }
            }
            return try publish()
        }
    }

    /// Read-only one-item proposal. The original sparse epoch remains the
    /// shared authority; speculative preparation neither consumes nor exposes.
    func prepareAdaptiveItem(request: SessionRequest, predecessor: NFLocalItemCheckpoint?,
                             rotation: NFOfflineQuestionRotation, bank: NFVersionedOfflineQuestionBank,
                             quarantinedItemIDs: Set<String>, at date: Date,
                             editorialRecords: [NFImmutableAttemptRecordSnapshot] = [],
                             editorialDay: NFEditorialCapturedDay? = nil,
                             command: NFSessionWriterCommand? = nil) throws -> NFLocalAdaptiveItemPreparation {
        try prepareOrdinaryItemDecision(request: request, predecessor: predecessor,
            operation: predecessor == nil ? .launch : .next, rotation: rotation, bank: bank,
            quarantinedItemIDs: quarantinedItemIDs, at: date,
            editorialRecords: editorialRecords, editorialDay: editorialDay, command: command)
    }

    func prepareAdaptiveReplacement(request: SessionRequest, predecessor: NFLocalItemCheckpoint,
                                    rotation: NFOfflineQuestionRotation, bank: NFVersionedOfflineQuestionBank,
                                    quarantinedItemIDs: Set<String>, at date: Date,
                             editorialRecords: [NFImmutableAttemptRecordSnapshot] = [],
                             editorialDay: NFEditorialCapturedDay? = nil,
                             overrideIntent: NFEditorialOverrideIntent? = nil,
                             command: NFSessionWriterCommand? = nil) throws -> NFLocalAdaptiveItemPreparation {
        try prepareOrdinaryItemDecision(request: request, predecessor: predecessor, operation: .replace,
            rotation: rotation, bank: bank, quarantinedItemIDs: quarantinedItemIDs, at: date,
            editorialRecords: editorialRecords, editorialDay: editorialDay, overrideIntent: overrideIntent, command: command)
    }

    private func prepareOrdinaryItemDecision(request: SessionRequest, predecessor: NFLocalItemCheckpoint?,
                                             operation: NFReservationOperation,
                                             rotation: NFOfflineQuestionRotation, bank: NFVersionedOfflineQuestionBank,
                                             quarantinedItemIDs: Set<String>, at date: Date,
                                             editorialRecords: [NFImmutableAttemptRecordSnapshot],
                                             editorialDay: NFEditorialCapturedDay?,
                                             overrideIntent: NFEditorialOverrideIntent? = nil,
                             command: NFSessionWriterCommand? = nil) throws -> NFLocalAdaptiveItemPreparation {
        guard loadError == nil, let pin = request.ordinaryDelivery, pin.isSupported, pin.strategy == .adaptiveItem,
              overrideIntent == nil || pin.editorialPolicy != nil,
              pin.bankVersion == bank.version, pin.bankFingerprint == bank.catalogFingerprint,
              bank.version == NFOfflineQuestionBank.rotationBank.version,
              bank.catalogFingerprint == NFOfflineQuestionBank.rotationBank.catalogFingerprint,
              request.mechanicID == nil, request.evidenceClass == .practice,
              request.assessmentBlock == nil, request.transferBrief == nil,
              request.retentionTargets.isEmpty, request.retentionItemIDs.isEmpty,
              [.focused, .today].contains(request.source), request.offlineRotationPlan == nil,
              request.offlineQuestionOrdinals.isEmpty, request.hasValidTimingDurations,
              !(request.requestedItemCount == nil && request.requestedMinutes != nil),
              date.timeIntervalSinceReferenceDate.isFinite else { throw RepositoryError.unsupportedVersion }
        if predecessor != nil {
            guard let command else { throw RepositoryError.staleRevision }
            try validateSessionCommand(command, sessionID: request.id)
        }
        if let overrideIntent, !acceptsWriterAuthority(overrideIntent.writerAuthority, sessionID: request.id) {
            throw NFEditorialOverrideError.staleOwner
        }
        if predecessor == nil, writerCheckpoint?() == false { throw RepositoryError.corruptSnapshot }
        try withPublicationLock {
            if let latest = try readArchiveFromDisk() { archive = latest }
            _ = try diskRevision()
        }
        guard !(archive.deletedAdaptiveRunIDs ?? []).contains(request.id) else { throw RepositoryError.conflictingAttempt }
        guard predecessor.map({ (0..<50).contains($0.index) }) ?? true else { throw RepositoryError.corruptSnapshot }
        let nextIndex = predecessor.map { $0.index + (operation == .next ? 1 : 0) } ?? 0
        guard nextIndex >= 0, nextIndex < (request.requestedItemCount ?? 5), nextIndex < 50 else { throw RepositoryError.conflictingAttempt }
        let config = try NFLocalReservationBridge.configurationDigest(request)
        // The command is identified by its operation and exact predecessor,
        // before allocating a new ordinal. A retry cannot become another Replace.
        if let receipt = archive.adaptiveItemReceipts?.values.first(where: {
            $0.sessionID == request.id && $0.operation == operation && $0.predecessorSlotID == predecessor?.slotID
        }) {
            let predecessorDigest: String?
            if operation == .replace { predecessorDigest = try predecessor.map(NFLocalRetiredOrdinaryDraft.digest) }
            else { predecessorDigest = nil }
            guard receipt.configurationDigest == config, receipt.predecessorSlotID == predecessor?.slotID,
                  receipt.ownerDeviceID == ownerDeviceID, receipt.isSupported,
                  operation != .replace || receipt.predecessorCheckpointDigest == predecessorDigest,
                  overrideIntent.map({ receipt.editorialDecision?.overrideCommand?.id == $0.id
                    && receipt.editorialDecision?.overrideCommand?.action == $0.action }) ?? (receipt.editorialDecision?.overrideCommand?.boundary != .replaceCurrent),
                  let run = archive.sessions.first(where: { $0.id == request.id }), run.status != .migrationRecovery,
                  run.checkpoint.index == nextIndex, run.checkpoint.slotID == receipt.slotID else { throw RepositoryError.staleRevision }
            return .init(expectedArchiveRevision: archive.transactionRevision ?? 0, expectedRunRevision: run.revision,
                request: run.request, receipt: receipt, checkpoint: run.checkpoint, replacementRotationLedger: nil,
                importsLegacy: false, legacySnapshot: nil, replay: run,
                overrideWriterAuthority: overrideIntent?.writerAuthority, sessionWriterCommand: command)
        }
        let existing = archive.sessions.first { $0.id == request.id }
        if let predecessor {
            guard let existing, existing.ownerDeviceID == ownerDeviceID, existing.status == .suspended,
                  existing.checkpoint == predecessor,
                  try NFLocalReservationBridge.configurationDigest(existing.request) == config else { throw RepositoryError.staleRevision }
            if operation == .replace {
                guard predecessor.phase == .item, predecessor.committedAttemptID == nil,
                      predecessor.result == nil, predecessor.pendingOutcome == nil,
                      predecessor.descriptor == nil, predecessor.protectedCommitReceipt == nil,
                      predecessor.exercise?.assessmentProtected == false,
                      predecessor.exercise?.evidenceClass == .practice else { throw RepositoryError.conflictingAttempt }
            } else {
                guard operation == .next, predecessor.committedAttemptID == predecessor.attemptID
                    || (["skip", "reveal"].contains(predecessor.pendingOutcome ?? "")
                        && predecessor.assessmentEvents.contains("\(predecessor.pendingOutcome == "reveal" ? "revealed" : "skipped"):\(predecessor.exercise?.id ?? "")")) else { throw RepositoryError.staleRevision }
            }
        } else if existing != nil || operation != .launch { throw RepositoryError.conflictingAttempt }
        let decisionOrdinal = existing.flatMap { archive.selectionLedger?.runs[$0.id.uuidString]?.nextDecisionOrdinal } ?? 0
        guard decisionOrdinal < UInt64.max else { throw RepositoryError.unsupportedVersion }
        let decisionID = NFSelectionReservationPolicy.decisionID(runID: request.id.uuidString, ordinal: decisionOrdinal)
        let importsLegacy = archive.offlineRotationLedger == nil
        guard !importsLegacy || (predecessor == nil && archive.rotationMigration == nil) else { throw RepositoryError.corruptSnapshot }
        let source = try importsLegacy ? rotation.legacySnapshot() : archive.offlineRotationLedger
        let excluded = (predecessor?.semanticExclusions ?? []).union(request.repairSemanticExclusions ?? [])
        let quarantined = quarantinedItemIDs.union(request.quarantinedItemIDs)
        var selectedExercise: NFExercise?
        var editorialDecision: NFEditorialControllerDecision?
        var mixedDecision: NFEditorialMixedDecision?
        let proposal: NFOfflineQuestionRotationProposal
        if pin.editorialPolicy != nil {
            guard let editorialDay else { throw RepositoryError.unsupportedVersion }
            let selected = try reviewedSelection(request: request, previous: existing, operation: operation,
                rotation: rotation, source: source, quarantined: quarantined, records: editorialRecords,
                day: editorialDay, at: date,
                overrideCommand: try overrideIntent.map { try makeEditorialOverride($0, boundary: .replaceCurrent,
                    previous: existing, at: date) })
            proposal = selected.proposal; selectedExercise = selected.exercise; editorialDecision = selected.decision; mixedDecision = selected.mixed
        } else {
        do {
            proposal = try rotation.prepareReservation(profileID: pin.profileID, lab: request.lab, laneID: pin.laneID,
                itemCount: 1, bank: bank, loadedLedger: source) { item in
                    guard let ordinal = NFOfflineQuestionBank.ordinal(forQuestionID: item.questionID, lab: request.lab) else { return false }
                    let candidate = NFDeterministicSessionExerciseFactory.makeExercise(
                        request: request.launchOnly(offlineQuestionOrdinals: [ordinal]), index: 0,
                        assessmentDescriptor: nil, excludingContentFingerprints: excluded)
                    guard candidate.availabilityReason == nil, !candidate.assessmentProtected,
                          !quarantined.contains(candidate.id), request.timingCondition?.accepts(candidate) != false else { return false }
                    if case .selfCheck = candidate.interaction { return false }
                    selectedExercise = candidate
                    return true
                }
        } catch NFOfflineQuestionRotationError.insufficientEligibleQuestions { throw RepositoryError.unavailableLaunch }
        }
        guard let exercise = selectedExercise else { throw RepositoryError.unavailableLaunch }
        var checkpoint = try NFLocalItemCheckpoint.initial(request: request, exercise: exercise,
            slotID: Self.adaptiveIdentity(decisionID, role: "slot"), attemptID: Self.adaptiveIdentity(decisionID, role: "attempt"), at: date,
            reviewedDemand: editorialDecision?.admission.demand, timingConditionOverride: predecessor?.timingConditionOverride)
        checkpoint.index = nextIndex
        checkpoint.ordinaryReservationDecisionID = decisionID
        checkpoint.semanticExclusions.formUnion(excluded)
        if operation == .replace, let predecessor {
            try Self.carryOrdinaryHistory(predecessor, into: &checkpoint, replacing: true)
        }
        let receipt = NFLocalAdaptiveItemReceipt(schemaVersion: mixedDecision != nil ? 5 : (editorialDecision == nil ? 2 : (editorialDecision?.overrideCommand == nil ? 3 : 4)), decisionID: decisionID, sessionID: request.id, ownerDeviceID: ownerDeviceID,
            configurationDigest: config, questionIndex: nextIndex, predecessorSlotID: predecessor?.slotID,
            slotID: checkpoint.slotID, attemptID: checkpoint.attemptID, exerciseDigest: checkpoint.exerciseDigest,
            plan: proposal.plan, eligibilityRevision: Self.adaptiveEligibilityRevision(quarantined),
            operationRaw: operation.rawValue, decisionOrdinal: decisionOrdinal,
            predecessorCheckpointDigest: operation == .replace ? try predecessor.map(NFLocalRetiredOrdinaryDraft.digest) : nil,
            editorialDecision: editorialDecision, mixedDecision: mixedDecision,
            selectionTimingCondition: editorialDecision?.criterionSelection == nil ? nil
                : (predecessor?.timingConditionOverride ?? request.timingCondition))
        return .init(expectedArchiveRevision: archive.transactionRevision ?? 0, expectedRunRevision: existing?.revision,
            request: request.launchOnly(), receipt: receipt, checkpoint: checkpoint,
            replacementRotationLedger: proposal.replacement, importsLegacy: importsLegacy,
            legacySnapshot: importsLegacy ? source : nil, replay: nil,
            overrideWriterAuthority: overrideIntent?.writerAuthority, sessionWriterCommand: command)
    }

    /// The one atomic acknowledgement contains bank consumption, selection and
    /// exact next checkpoint. Generic checkpoint writes cannot mint a receipt.
    func acceptAdaptiveItem(_ preparation: NFLocalAdaptiveItemPreparation, checkpoint: NFLocalItemCheckpoint,
                            rotation: NFOfflineQuestionRotation, quarantinedItemIDs: Set<String>,
                            editorialRecords: [NFImmutableAttemptRecordSnapshot] = []) throws -> NFLocalSessionEnvelope {
        try withPublicationLock {
            let revision = try diskRevision()
            guard revision == (archive.transactionRevision ?? 0) else { throw RepositoryError.staleRevision }
            let receipt = preparation.receipt, request = preparation.request
            if receipt.predecessorSlotID != nil {
                guard let command = preparation.sessionWriterCommand else { throw RepositoryError.staleRevision }
                try validateSessionCommand(command, sessionID: request.id)
            }
            if receipt.editorialDecision?.overrideCommand?.boundary == .replaceCurrent,
               !acceptsWriterAuthority(preparation.overrideWriterAuthority, sessionID: request.id) {
                throw NFEditorialOverrideError.staleOwner
            }
            if let accepted = archive.adaptiveItemReceipts?[receipt.decisionID] {
                guard accepted == receipt, let run = archive.sessions.first(where: { $0.id == receipt.sessionID }),
                      run.ownerDeviceID == ownerDeviceID, run.status != .migrationRecovery else { throw RepositoryError.conflictingAttempt }
                return run
            }
            guard (2...5).contains(receipt.schemaVersion), receipt.isSupported, let operation = receipt.operation,
                  let decisionOrdinal = receipt.effectiveDecisionOrdinal,
                  revision == preparation.expectedArchiveRevision, receipt.ownerDeviceID == ownerDeviceID,
                  receipt.sessionID == request.id, !(archive.deletedAdaptiveRunIDs ?? []).contains(request.id),
                  let pin = request.ordinaryDelivery, pin.isSupported, pin.strategy == .adaptiveItem,
                  receipt.configurationDigest == (try NFLocalReservationBridge.configurationDigest(request)),
                  receipt.eligibilityRevision == Self.adaptiveEligibilityRevision(quarantinedItemIDs.union(request.quarantinedItemIDs)),
                  let replacement = preparation.replacementRotationLedger,
                  checkpoint.slotID == receipt.slotID, checkpoint.attemptID == receipt.attemptID,
                  checkpoint.ordinaryReservationDecisionID == receipt.decisionID,
                  checkpoint.index == receipt.questionIndex, checkpoint.itemCount == (request.requestedItemCount ?? 5),
                  checkpoint.exercise == preparation.checkpoint.exercise, checkpoint.exerciseDigest == receipt.exerciseDigest,
                  checkpoint.phase == .item, checkpoint.committedAttemptID == nil, checkpoint.result == nil,
                  checkpoint.response == preparation.checkpoint.response, checkpoint.hasValidTimingDurations,
                  checkpoint.semanticExclusions.isSuperset(of: preparation.checkpoint.semanticExclusions) else { throw RepositoryError.staleRevision }
            let previous = archive.sessions.first { $0.id == receipt.sessionID }
            guard previous?.revision == preparation.expectedRunRevision,
                  previous?.checkpoint.slotID == receipt.predecessorSlotID,
                  previous?.ownerDeviceID == nil || previous?.ownerDeviceID == ownerDeviceID else { throw RepositoryError.staleRevision }
            guard decisionOrdinal == (previous.flatMap({ archive.selectionLedger?.runs[$0.id.uuidString]?.nextDecisionOrdinal }) ?? 0),
                  receipt.decisionID == NFSelectionReservationPolicy.decisionID(runID: request.id.uuidString, ordinal: decisionOrdinal) else {
                throw RepositoryError.staleRevision
            }
            if operation == .replace {
                guard let previous, previous.status == .suspended,
                      previous.checkpoint.phase == .item, previous.checkpoint.committedAttemptID == nil,
                      previous.checkpoint.pendingOutcome == nil, previous.checkpoint.result == nil,
                      previous.checkpoint.index == checkpoint.index,
                      receipt.predecessorCheckpointDigest == (try NFLocalRetiredOrdinaryDraft.digest(previous.checkpoint)),
                      archive.retiredOrdinaryDrafts?[previous.checkpoint.slotID.uuidString] == nil else {
                    throw RepositoryError.conflictingAttempt
                }
            } else {
                guard operation == (previous == nil ? .launch : .next),
                      checkpoint.index == (previous.map { $0.checkpoint.index + 1 } ?? 0) else { throw RepositoryError.conflictingAttempt }
            }
            guard pin.bankVersion == NFOfflineQuestionBank.rotationBank.version,
                  pin.bankFingerprint == NFOfflineQuestionBank.rotationBank.catalogFingerprint,
                  let selected = receipt.plan.items.first,
                  let ordinal = NFOfflineQuestionBank.ordinal(forQuestionID: selected.questionID, lab: request.lab) else {
                throw RepositoryError.unsupportedVersion
            }
            let exclusions = (previous?.checkpoint.semanticExclusions ?? []).union(request.repairSemanticExclusions ?? [])
            let exact = NFDeterministicSessionExerciseFactory.makeExercise(
                request: request.launchOnly(offlineQuestionOrdinals: [ordinal]), index: 0, assessmentDescriptor: nil,
                excludingContentFingerprints: exclusions)
            if let decision = receipt.editorialDecision {
                if decision.criterionSelection != nil {
                    // This comparison uses the exact durable predecessor under
                    // the same publication lock as the full selection replay.
                    let actualTiming = previous?.checkpoint.timingConditionOverride ?? request.timingCondition
                    guard let actualTiming, actualTiming.isSupported,
                          receipt.selectionTimingCondition == actualTiming,
                          actualTiming.mode?.rawValue == decision.criterionSelection?.group.pacingConditionID else {
                        throw RepositoryError.staleRevision
                    }
                } else if receipt.selectionTimingCondition != nil { throw RepositoryError.corruptSnapshot }
                let selectedAgain = try reviewedSelection(request: request, previous: previous, operation: operation,
                    rotation: rotation, source: preparation.importsLegacy ? preparation.legacySnapshot : archive.offlineRotationLedger,
                    quarantined: quarantinedItemIDs.union(request.quarantinedItemIDs), records: editorialRecords,
                    day: decision.decisionDay, at: preparation.checkpoint.shownAt,
                    overrideCommand: decision.overrideCommand?.boundary == .replaceCurrent ? decision.overrideCommand : nil)
                guard selectedAgain.decision == decision, selectedAgain.mixed == receipt.mixedDecision, selectedAgain.proposal.plan == receipt.plan,
                      selectedAgain.proposal.replacement == replacement, selectedAgain.exercise == exact else {
                    throw RepositoryError.staleRevision
                }
            } else if pin.editorialPolicy != nil { throw RepositoryError.corruptSnapshot }

            guard exact.availabilityReason == nil, exact == checkpoint.exercise,
                  !quarantinedItemIDs.union(request.quarantinedItemIDs).contains(exact.id),
                  try NFLocalItemCheckpoint.digest(exact) == receipt.exerciseDigest else { throw RepositoryError.corruptSnapshot }
            var canonical = try NFLocalItemCheckpoint.initial(request: request, exercise: exact,
                slotID: Self.adaptiveIdentity(receipt.decisionID, role: "slot"),
                attemptID: Self.adaptiveIdentity(receipt.decisionID, role: "attempt"), at: preparation.checkpoint.shownAt,
                reviewedDemand: receipt.editorialDecision?.admission.demand, timingConditionOverride: previous?.checkpoint.timingConditionOverride)
            canonical.index = receipt.questionIndex
            canonical.ordinaryReservationDecisionID = receipt.decisionID
            canonical.semanticExclusions.formUnion(exclusions)
            if let previous {
                let prior = previous.checkpoint
                try Self.carryOrdinaryHistory(prior, into: &canonical, replacing: operation == .replace)
                // The coordinator may include the small active interval spent
                // preparing the next item. This cannot rewrite prior elapsed
                // time or substitute an arbitrary cumulative duration.
                let additional = (checkpoint.sittingActiveDuration ?? 0) - (prior.sittingActiveDuration ?? 0)
                let preparationInterval = max(0, checkpoint.shownAt.timeIntervalSince(previous.updatedAt))
                guard additional >= 0, additional <= preparationInterval + 1 else { throw RepositoryError.corruptSnapshot }
                canonical.sittingActiveDuration = checkpoint.sittingActiveDuration
            }
            guard checkpoint == canonical else { throw RepositoryError.corruptSnapshot }
            let run = NFLocalSessionEnvelope(id: request.id, ownerDeviceID: ownerDeviceID,
                revision: try NFSessionWriterRevision.next(after: previous?.revision), request: request.launchOnly(), checkpoint: checkpoint,
                status: .suspended, updatedAt: checkpoint.shownAt)
            @MainActor func publish() throws -> NFLocalSessionEnvelope {
                // Reconstruct the exact one-position delta from the accepted
                // predecessor. A forged preparation cannot consume extra slots
                // or substitute another epoch recipe under a valid snapshot.
                let source = preparation.importsLegacy ? preparation.legacySnapshot : archive.offlineRotationLedger
                guard preparation.importsLegacy == (archive.offlineRotationLedger == nil),
                      !preparation.importsLegacy || archive.rotationMigration == nil else { throw RepositoryError.staleRevision }
                let expected = try rotation.prepareReservation(profileID: pin.profileID, lab: request.lab,
                    laneID: pin.laneID, itemCount: 1, bank: NFOfflineQuestionBank.rotationBank, loadedLedger: source,
                    isEligible: { $0 == receipt.plan.items.first })
                guard expected.plan == receipt.plan, expected.replacement == replacement else { throw RepositoryError.corruptSnapshot }
                var next = archive
                next.offlineRotationLedger = replacement
                if preparation.importsLegacy {
                    let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
                    next.rotationMigration = .init(schemaVersion: 1,
                        sourceDigest: NFReservationSnapshot.digest(try encoder.encode(preparation.legacySnapshot)),
                        sourceRevision: preparation.legacySnapshot?.revision, importedAt: checkpoint.shownAt)
                }
                next.selectionLedger = try NFLocalReservationBridge.accepting(envelope: run, previous: previous,
                    ledger: next.selectionLedger ?? .init(), adaptiveReceipt: receipt)
                if operation == .replace, let previous {
                    if next.retiredOrdinaryDrafts == nil { next.retiredOrdinaryDrafts = [:] }
                    next.retiredOrdinaryDrafts?[previous.checkpoint.slotID.uuidString] = .init(
                        sessionID: run.id, ownerDeviceID: ownerDeviceID, replacementDecisionID: receipt.decisionID,
                        checkpoint: NFLocalRetiredOrdinaryDraft.retainedCheckpoint(previous.checkpoint),
                        checkpointDigest: try NFLocalRetiredOrdinaryDraft.digest(previous.checkpoint), replacedAt: checkpoint.shownAt)
                }
                next.sessions.removeAll { $0.id == run.id }; next.sessions.append(run)
                if next.adaptiveItemReceipts == nil { next.adaptiveItemReceipts = [:] }
                next.adaptiveItemReceipts?[receipt.decisionID] = receipt
                if let command = receipt.editorialDecision?.overrideCommand {
                    if let original = next.editorialOverrideCommands?[command.id.uuidString], original != command {
                        throw RepositoryError.conflictingAttempt
                    }
                    if next.editorialOverrideCommands == nil { next.editorialOverrideCommands = [:] }
                    next.editorialOverrideCommands?[command.id.uuidString] = command
                }
                next = try Self.validatedArchive(next)
                try replaceUnlocked(next)
                return run
            }
            if preparation.importsLegacy {
                return try rotation.withLegacySnapshot { source in
                    guard source == preparation.legacySnapshot else { throw RepositoryError.staleRevision }
                    return try publish()
                }
            }
            return try publish()
        }
    }

    private static func carryOrdinaryHistory(_ prior: NFLocalItemCheckpoint, into value: inout NFLocalItemCheckpoint,
                                              replacing: Bool) throws {
        value.scratchpad = prior.scratchpad
        value.correctness = prior.correctness; value.credits = prior.credits
        value.assessmentDescriptorIDs = prior.assessmentDescriptorIDs
        value.assessmentEvents = prior.assessmentEvents
        value.cumulativeActiveDuration = prior.cumulativeActiveDuration + (replacing ? prior.itemActiveDuration : 0)
        value.assessmentPracticeDuration = prior.assessmentPracticeDuration
        value.sittingOrdinal = prior.sittingOrdinal
        value.sittingActiveDuration = prior.sittingActiveDuration
        value.timingConditionOverride = prior.timingConditionOverride
        guard value.hasValidTimingDurations else { throw RepositoryError.corruptSnapshot }
    }

    private static func adaptiveEligibilityRevision(_ quarantined: Set<String>) -> String {
        NFReservationSnapshot.digest(Data(NFSelectionReservationPolicy.identity(quarantined.sorted()).utf8))
    }
    nonisolated private static func adaptiveIdentity(_ decisionID: String, role: String) -> UUID {
        let hex = Array(NFReservationSnapshot.digest(Data("adaptive-bank-slot.v1|\(decisionID)|\(role)".utf8)).prefix(32))
        let value = String(hex[0..<8]) + "-" + String(hex[8..<12]) + "-" + String(hex[12..<16]) + "-" + String(hex[16..<20]) + "-" + String(hex[20..<32])
        return UUID(uuidString: value)!
    }

    private static func launchIdentity(_ commandID: UUID, role: String) -> UUID {
        let hex = Array(NFReservationSnapshot.digest(Data("local-fixed-launch.v1|\(commandID.uuidString)|\(role)".utf8)).prefix(32))
        let value = String(hex[0..<8]) + "-" + String(hex[8..<12]) + "-" + String(hex[12..<16]) + "-" + String(hex[16..<20]) + "-" + String(hex[20..<32])
        return UUID(uuidString: value)!
    }

    func save(_ envelope: NFLocalSessionEnvelope) throws {
        try requireArchiveWriteAvailability()
        try replace(Self.sessionCandidate(envelope, in: archive, ownerDeviceID: ownerDeviceID))
    }

    nonisolated static func sessionCandidate(_ envelope: NFLocalSessionEnvelope, in archive: Archive,
                                              ownerDeviceID: UUID) throws -> Archive {
        guard envelope.checkpoint.hasSupportedTraceInspection, envelope.checkpoint.hasSupportedScienceStudy, envelope.request.hasSupportedScienceStudyPolicy, envelope.checkpoint.hasSupportedGraphConstruction, envelope.request.permitsSpatialAssembly(exercise:envelope.checkpoint.exercise), envelope.request.permitsCoordinateReasoning(exercise:envelope.checkpoint.exercise), envelope.request.permitsNetFolding(exercise:envelope.checkpoint.exercise), envelope.request.permitsSolidSection(exercise: envelope.checkpoint.exercise), envelope.request.permitsCoordinateTransform(exercise: envelope.checkpoint.exercise), envelope.request.permitsSpatialStructure(exercise: envelope.checkpoint.exercise), envelope.request.permitsRetrievalAsset(exercise: envelope.checkpoint.exercise), envelope.request.permitsRetrievalAuthority(exercise: envelope.checkpoint.exercise), envelope.request.hasSupportedGraphConstructionPolicy, envelope.request.permitsGraphConstruction(exercise: envelope.checkpoint.exercise), envelope.checkpoint.hasSupportedTransferRelationship, envelope.request.supportsTransferRecipe(in: envelope.checkpoint) else { throw RepositoryError.corruptSnapshot }
        guard envelope.ownerDeviceID == ownerDeviceID,
              archive.sessions.first(where: { $0.id == envelope.id }).map({ $0.ownerDeviceID == ownerDeviceID }) ?? true else { throw RepositoryError.wrongOwner }
        guard archive.sessions.first(where: { $0.id == envelope.id })?.status != .migrationRecovery else {
            throw RepositoryError.unsupportedVersion
        }
        if envelope.request.ordinaryDelivery?.strategy == .adaptiveItem,
           let previous = archive.sessions.first(where: { $0.id == envelope.id }),
           previous.checkpoint.slotID != envelope.checkpoint.slotID {
            // Only the accepted selection transaction may change the active
            // adaptive slot. An old editor cannot rewind a replaced/answered slot.
            throw RepositoryError.staleRevision
        }
        guard envelope.schemaVersion == 1, envelope.checkpoint.schemaVersion == 1 else {
            throw RepositoryError.unsupportedVersion
        }
        if let exercise = envelope.checkpoint.exercise {
            guard !exercise.assessmentProtected,
                  try NFLocalItemCheckpoint.digest(exercise) == envelope.checkpoint.exerciseDigest else {
                throw RepositoryError.corruptSnapshot
            }
        }
        var next = archive
        next.selectionLedger = try NFLocalReservationBridge.accepting(envelope: envelope,
            previous: archive.sessions.first { $0.id == envelope.id }, ledger: archive.selectionLedger ?? .init(),
            adaptiveReceipt: envelope.checkpoint.ordinaryReservationDecisionID.flatMap { archive.adaptiveItemReceipts?[$0] })
        next.sessions.removeAll { $0.id == envelope.id }
        next.sessions.append(envelope)
        return next
    }

    func acknowledgePresentation(sessionID: UUID, slotID: UUID, at date: Date) throws {
        guard let envelope = archive.sessions.first(where: { $0.id == sessionID }),
              envelope.checkpoint.slotID == slotID, let ledger = archive.selectionLedger else { return }
        let updated = try NFLocalReservationBridge.acknowledge(envelope: envelope, ledger: ledger, at: date)
        guard updated != ledger else { return }
        var next = archive
        next.selectionLedger = updated
        try replace(next)
    }

    func retainSnapshot(attemptID: UUID, exercise: NFExercise,
                        editorialCapture: NFEditorialCommitCapture? = nil, mathWork: NFMathWorkDraft? = nil,
                        traceInspection: NFTraceInspectionDraft? = nil, dataInspection: NFDataInspectionDraft? = nil, scienceStudy: NFScienceStudyDraft? = nil, transferRelationship: NFTransferRelationshipDraft? = nil) throws {
        try requireArchiveWriteAvailability()
        let candidate = try Self.retainedSnapshotCandidate(attemptID: attemptID, exercise: exercise, editorialCapture: editorialCapture, mathWork: mathWork, traceInspection: traceInspection, dataInspection: dataInspection, scienceStudy: scienceStudy, transferRelationship: transferRelationship, in: archive)
        guard candidate.snapshots.count != archive.snapshots.count else { return }
        try replace(candidate)
    }

    @inline(never)
    nonisolated static func attemptRetentionCandidate(_ input: NFLocalAttemptRetentionInput,
        in original: Archive, ownerDeviceID: UUID) throws -> Archive {
        let sessionID = input.sessionID, revision = input.revision
        let predecessor = input.predecessor, snapshot = input.snapshot
            guard let run = original.sessions.first(where: { $0.id == sessionID }),
                  run.ownerDeviceID == ownerDeviceID, run.revision == revision, run.status == .suspended,
                  run.checkpoint == predecessor, predecessor.schemaVersion == 1,
                  predecessor.scorerVersion == NFExerciseScoringEngine.scoringVersion,
                  predecessor.phase == .confidence,
                  predecessor.pendingOutcome == "answer", predecessor.committedAttemptID == nil,
                  predecessor.attemptID == snapshot.attemptID,
                  let score = predecessor.result, score.exerciseID == snapshot.exercise.id,
                  score.scoringVersion == predecessor.scorerVersion,
                  [.correct, .partial, .incorrect, .selfReported].contains(score.outcome),
                  predecessor.exercise == snapshot.exercise, !snapshot.exercise.assessmentProtected,
                  predecessor.mathWork == snapshot.mathWork, predecessor.traceInspection == snapshot.traceInspection,
                  predecessor.dataInspection == snapshot.dataInspection, predecessor.scienceStudy == snapshot.scienceStudy,
                  predecessor.transferRelationship == snapshot.transferRelationship else {
                throw NFLocalSessionRepository.RepositoryError.staleRevision
            }
            return try NFLocalSessionRepository.retainedSnapshotCandidate(attemptID: snapshot.attemptID,
                exercise: snapshot.exercise, editorialCapture: snapshot.editorialCapture, mathWork: snapshot.mathWork,
                traceInspection: snapshot.traceInspection, dataInspection: snapshot.dataInspection,
                scienceStudy: snapshot.scienceStudy, transferRelationship: snapshot.transferRelationship, in: original)
    }

    nonisolated static func retainedSnapshotCandidate(attemptID: UUID, exercise: NFExercise,
                        editorialCapture: NFEditorialCommitCapture? = nil, mathWork: NFMathWorkDraft? = nil,
                        traceInspection: NFTraceInspectionDraft? = nil, dataInspection: NFDataInspectionDraft? = nil, scienceStudy: NFScienceStudyDraft? = nil, transferRelationship: NFTransferRelationshipDraft? = nil, in archive: Archive) throws -> Archive {
        guard traceInspection.map({ $0.isValid(for: exercise) }) ?? true else { throw RepositoryError.corruptSnapshot }
        guard !exercise.assessmentProtected else { return archive }
        guard archive.unavailableHistorySnapshots?.contains(where: { $0.attemptID == attemptID }) != true else {
            throw RepositoryError.conflictingAttempt
        }
        if let old = archive.snapshots.first(where: { $0.attemptID == attemptID }) {
            guard old.exercise == exercise, old.editorialCapture == editorialCapture, old.mathWork == mathWork,
                  old.traceInspection == traceInspection, old.dataInspection == dataInspection, old.scienceStudy == scienceStudy, old.transferRelationship == transferRelationship else { throw RepositoryError.conflictingAttempt }
            return archive
        }
        if let editorialCapture {
            guard editorialCapture.isSupported, editorialCapture.attemptID == attemptID,
                  editorialCapture.exerciseDigest == (try NFLocalItemCheckpoint.digest(exercise)) else {
                throw RepositoryError.corruptSnapshot
            }
        }
        guard mathWork?.isCompatible(with: exercise) != false, dataInspection?.isCompatible(with: exercise) != false, NFScienceStudyDraft.permits(scienceStudy, exercise: exercise), NFTransferRelationshipDraft.permits(transferRelationship, exercise: exercise) else { throw RepositoryError.corruptSnapshot }
        var next = archive
        next.snapshots.append(NFLocalAttemptSnapshot(attemptID: attemptID, exercise: exercise, editorialCapture: editorialCapture, mathWork: mathWork, traceInspection: traceInspection, dataInspection: dataInspection, scienceStudy: scienceStudy, transferRelationship: transferRelationship))
        return next
    }

    func end(_ sessionID: UUID) throws {
        var next = archive
        guard let index = next.sessions.firstIndex(where: { $0.id == sessionID }) else { return }
        next.sessions[index].status = .endedEarly
        next.sessions[index].updatedAt = Date()
        if let ledger = next.selectionLedger, ledger.runs[sessionID.uuidString] != nil {
            next.selectionLedger = try NFSelectionReservationPolicy.endRun(sessionID.uuidString,
                ownerDeviceID: ownerDeviceID.uuidString, in: ledger)
        }
        try replace(next)
    }

    func removeAll() throws {
        try replace(Archive())
        writerID = nil
        writerSessionID = nil
        writerCheckpoint = nil
    }

    func saveSet(_ result: NFAuthoringResult, at date: Date) throws {
        guard NFGeneratedPracticeCompatibility.unavailableReason(for: result) == nil else { throw RepositoryError.unsupportedVersion }
        var next = archive
        var sets = next.savedSets ?? []
        guard !sets.contains(where: { $0.id == result.provenance.requestID }) else { return }
        sets.append(NFLocalSavedStudySet(id: result.provenance.requestID, savedAt: date, result: result))
        next.savedSets = sets
        try replace(next)
    }

    func unsaveSet(_ id: UUID) throws {
        var next = archive
        next.savedSets?.removeAll { $0.id == id }
        try updateOrganization(in: &next) { metadata in
            for index in metadata.collections.indices { metadata.collections[index].savedSetIDs.remove(id) }
        }
        try replace(next)
    }

    /// Explicit linked-data deletion traverses the local additions as well as
    /// the legacy store. Callers keep a predecessor until both stores commit.
    func removeReferences(attemptIDs: Set<UUID>, generationIDs: Set<UUID> = [], sourceID: UUID? = nil) throws {
        var next = archive
        if !attemptIDs.isEmpty || !generationIDs.isEmpty || sourceID != nil { try purgeHistoryRecoveryBackups() }
        next.unavailableHistorySnapshots?.removeAll { attemptIDs.contains($0.attemptID) || sourceID != nil || !generationIDs.isEmpty }
        next.attemptConflicts?.removeAll { entry in
            attemptIDs.contains(entry.attemptID)
                || [entry.original.generationID, entry.proposed.generationID].compactMap { $0 }.contains(where: generationIDs.contains)
                || sourceID.map { id in
                    [entry.original.sourceDocumentIDsRaw, entry.proposed.sourceDocumentIDsRaw]
                        .contains { $0.split(separator: ",").contains { UUID(uuidString: String($0).trimmingCharacters(in: .whitespacesAndNewlines)) == id } }
                } == true
        }
        next.withheldProtectedConflictAttemptIDs?.removeAll { attemptIDs.contains($0) || sourceID != nil || !generationIDs.isEmpty }
        next.editorialExplanationPresentations = next.editorialExplanationPresentations?.filter { !attemptIDs.contains($0.value.attemptID) }
        next.snapshots.removeAll { snapshot in
            attemptIDs.contains(snapshot.attemptID)
                || sourceID.map { snapshot.exercise.provenance.sourceDocumentIDs.contains($0.uuidString) } == true
        }
        next.evidenceDispositions?.removeAll { record in
            UUID(uuidString: record.attemptID).map { attemptIDs.contains($0) } == true
        }
        next.contentCorrections?.removeAll { record in
            UUID(uuidString: record.originalAttemptID).map { attemptIDs.contains($0) } == true
        }
        for id in attemptIDs { next.activeContentCorrectionIDs?.removeValue(forKey: id.uuidString) }
        if var ledger = next.selectionLedger {
            let removedRunIDs = Set(ledger.slots.values.filter { slot in
                UUID(uuidString: slot.attemptID).map { attemptIDs.contains($0) } == true
            }.map(\.runID))
            let removedSlotIDs = Set(ledger.slots.values.filter { removedRunIDs.contains($0.runID) }.map(\.id))
            next.sessions.removeAll { removedRunIDs.contains($0.id.uuidString) }
            let removedSnapshotKeys = Set(ledger.snapshots.keys.filter { key in
                guard let value = ledger.snapshots[key] else { return false }
                return ledger.slots.values.contains { removedSlotIDs.contains($0.id) &&
                    NFSelectionReservationPolicy.snapshot(for: $0, in: ledger) == value }
                    && !ledger.slots.values.contains { !removedSlotIDs.contains($0.id) &&
                        NFSelectionReservationPolicy.snapshot(for: $0, in: ledger) == value }
            })
            ledger.runs = ledger.runs.filter { !removedRunIDs.contains($0.key) }
            ledger.slots = ledger.slots.filter { !removedSlotIDs.contains($0.key) }
            ledger.decisions = ledger.decisions.filter { !removedRunIDs.contains($0.value.command.runID) }
            ledger.exposures = ledger.exposures.filter { !removedRunIDs.contains($0.value.runID) }
            ledger.outcomes = ledger.outcomes.filter { !removedRunIDs.contains($0.value.runID) }
            ledger.snapshots = ledger.snapshots.filter { !removedSnapshotKeys.contains($0.key) }
            let removedPlans = Set(ledger.legacyReservationOwners.filter { removedRunIDs.contains($0.value) }.map(\.key))
            ledger.legacyReservationOwners = ledger.legacyReservationOwners.filter { !removedPlans.contains($0.key) }
            ledger.legacyPlans = ledger.legacyPlans.filter { !removedPlans.contains($0.key) }
            // Retain only anonymous consumed positions. Deleting history cannot
            // make the same already-reserved positions look novel again.
            next.selectionLedger = ledger
        }
        next.savedSets?.removeAll { generationIDs.contains($0.id) }
        next.privateStudyRuns?.removeAll { generationIDs.contains($0.generationID) }
        next.sessions.removeAll { attemptIDs.contains($0.checkpoint.attemptID) }
        if let sourceID {
            next.sessions.removeAll { $0.checkpoint.exercise?.provenance.sourceDocumentIDs.contains(sourceID.uuidString) == true }
        }
        // Removing any member of an origin run can also remove the authority
        // of its other observations. Follow that dependency graph to a fixed
        // point; preserve successor drafts, but never keep dangling review proof.
        let survivingRunIDs = Set(next.sessions.map(\.id))
        var reviewRecoveryRuns: Set<UUID> = []
        while true {
            let usableOrigins = Set(next.snapshots.compactMap { snapshot -> String? in
                guard let witness = snapshot.editorialCapture?.runtimeWitness,
                      let receipt = next.adaptiveItemReceipts?[witness.decisionID],
                      receipt.attemptID == snapshot.attemptID,
                      survivingRunIDs.contains(receipt.sessionID),
                      !reviewRecoveryRuns.contains(receipt.sessionID) else { return nil }
                return snapshot.attemptID.uuidString
            })
            let additional = Set((next.adaptiveItemReceipts ?? [:]).values.filter { receipt in
                guard let origin = receipt.editorialDecision?.reviewAssignment?.originObservationID else { return false }
                return !usableOrigins.contains(origin)
            }.map(\.sessionID)).subtracting(reviewRecoveryRuns)
            guard !additional.isEmpty else { break }
            reviewRecoveryRuns.formUnion(additional)
        }
        for index in next.sessions.indices where reviewRecoveryRuns.contains(next.sessions[index].id) {
            next.sessions[index].status = .migrationRecovery
        }
        next.adaptiveItemReceipts = next.adaptiveItemReceipts?.filter { !reviewRecoveryRuns.contains($0.value.sessionID) }
        next.editorialOverrideCommands = next.editorialOverrideCommands?.filter { !reviewRecoveryRuns.contains($0.value.sessionID) }
        next.editorialExplanationPresentations = next.editorialExplanationPresentations?.filter { _, fact in
            survivingRunIDs.contains(fact.sessionID) && !reviewRecoveryRuns.contains(fact.sessionID)
                && next.snapshots.contains(where: { $0.attemptID == fact.attemptID })
        }
        let retainedRunIDs = Set(next.sessions.map(\.id))
        let deletedCommands = Set((next.fixedLaunchReceipts ?? [:]).filter { !retainedRunIDs.contains($0.value.sessionID) }.map(\.key))
        next.deletedFixedLaunchCommandIDs = (next.deletedFixedLaunchCommandIDs ?? []).union(deletedCommands)
        next.fixedLaunchReceipts = next.fixedLaunchReceipts?.filter { !deletedCommands.contains($0.key) }
        let deletedAdaptiveRuns = Set((archive.adaptiveItemReceipts ?? [:]).values.filter { !retainedRunIDs.contains($0.sessionID) }.map(\.sessionID))
        next.deletedAdaptiveRunIDs = (next.deletedAdaptiveRunIDs ?? []).union(deletedAdaptiveRuns)
        next.adaptiveItemReceipts = next.adaptiveItemReceipts?.filter { retainedRunIDs.contains($0.value.sessionID) }
        next.editorialOverrideCommands = next.editorialOverrideCommands?.filter { retainedRunIDs.contains($0.value.sessionID) }
        next.editorialExplanationPresentations = next.editorialExplanationPresentations?.filter { retainedRunIDs.contains($0.value.sessionID) && !attemptIDs.contains($0.value.attemptID) }
        next.retiredOrdinaryDrafts = next.retiredOrdinaryDrafts?.filter { retainedRunIDs.contains($0.value.sessionID) }
        try updateOrganization(in: &next) { metadata in
            metadata.annotations.removeAll { attemptIDs.contains($0.id) }
            metadata.reviewDeferrals?.removeAll { attemptIDs.contains($0.anchorAttemptID) }
            for index in metadata.collections.indices {
                metadata.collections[index].savedSetIDs.subtract(generationIDs)
                if let sourceID { metadata.collections[index].sourceIDs.remove(sourceID) }
            }
        }
        try replace(next)
        if let writerSessionID, !next.sessions.contains(where: { $0.id == writerSessionID }) {
            self.writerID = nil
            self.writerSessionID = nil
            writerCheckpoint = nil
        }
    }

    private func updateOrganization(in archive: inout Archive, _ update: (inout NFPrivateStudyMetadata) -> Void) throws {
        guard let index = archive.privateStudyRuns?.firstIndex(where: { $0.id == NFPrivateStudyMetadata.recordID }),
              let record = archive.privateStudyRuns?[index] else { return }
        var metadata = try JSONDecoder().decode(NFPrivateStudyMetadata.self, from: record.payload)
        guard metadata.isSupported else { throw RepositoryError.unsupportedVersion }
        update(&metadata)
        archive.privateStudyRuns?[index] = NFLocalPrivateStudyRun(id: record.id, generationID: record.generationID,
            payload: try JSONEncoder().encode(metadata), updatedAt: Date())
    }

    func savePrivateStudyRun(id: UUID, generationID: UUID, payload: Data) throws {
        try requireArchiveWriteAvailability()
        try replace(Self.privateRunCandidate(id: id, generationID: generationID, payload: payload, in: archive, at: Date()))
    }

    nonisolated static func privateRunCandidate(id: UUID, generationID: UUID, payload: Data,
                                                in archive: Archive, at: Date) throws -> Archive {
        guard payload.count <= 8 * 1_024 * 1_024 else { throw RepositoryError.oversized }
        var next = archive
        var runs = next.privateStudyRuns ?? []
        runs.removeAll { $0.id == id }
        runs.append(NFLocalPrivateStudyRun(id: id, generationID: generationID, payload: payload, updatedAt: at))
        next.privateStudyRuns = runs
        return next
    }

    func removePrivateStudyRun(id: UUID) throws {
        var next = archive
        next.privateStudyRuns?.removeAll { $0.id == id }
        try replace(next)
    }

    func canonicalPrivateStudyPayload(_ run: NFLocalPrivateStudyRun) throws -> Data {
        guard run.payload.count <= 8 * 1_024 * 1_024 else { throw RepositoryError.oversized }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        if run.id == NFPrivateStudyMetadata.recordID {
            let metadata = try JSONDecoder().decode(NFPrivateStudyMetadata.self, from: run.payload)
            guard metadata.isSupported, run.generationID == run.id else { throw RepositoryError.unsupportedVersion }
            return try encoder.encode(metadata)
        }
        let draft = try JSONDecoder().decode(NFGeneratedPracticeDraft.self, from: run.payload)
        guard draft.valid, draft.id == run.id, draft.result.provenance.requestID == run.generationID,
              draft.activeDuration.isFinite, draft.activeDuration >= 0 else { throw RepositoryError.corruptSnapshot }
        return try encoder.encode(draft)
    }

    func appendDispositions(_ records: [NFHistoricalPracticeDispositionRecord],
                            contentCorrections: [NFHistoricalContentCorrectionRecommendation] = [],
                            activeContentCorrectionIDs: [String: [String]] = [:]) throws {
        var next = archive
        var recordsByID = Dictionary(uniqueKeysWithValues: (next.evidenceDispositions ?? []).map { ($0.id, $0) })
        for record in records {
            if let existing = recordsByID[record.id], existing != record { throw RepositoryError.conflictingAttempt }
            recordsByID[record.id] = record
        }
        next.evidenceDispositions = recordsByID.values.sorted { $0.id < $1.id }
        var correctionsByID = Dictionary(uniqueKeysWithValues: (next.contentCorrections ?? []).map { ($0.id, $0) })
        for record in contentCorrections {
            if let old = correctionsByID[record.id], old != record { throw RepositoryError.conflictingAttempt }
            correctionsByID[record.id] = record
        }
        next.contentCorrections = correctionsByID.values.sorted { $0.id < $1.id }
        if !activeContentCorrectionIDs.isEmpty {
            next.activeContentCorrectionIDs = (next.activeContentCorrectionIDs ?? [:]).merging(activeContentCorrectionIDs) { _, current in current }
        }
        if next.evidenceDispositions != archive.evidenceDispositions || next.contentCorrections != archive.contentCorrections
            || next.activeContentCorrectionIDs != archive.activeContentCorrectionIDs {
            try replace(next)
        }
    }

    nonisolated static func validateAttemptConflicts(_ records: [NFAttemptConflictJournalEntry], checkCancellation: () throws -> Void = {}) throws {
        guard Set(records.map(\.id)).count == records.count else { throw RepositoryError.conflictingAttempt }
        for record in records { try checkCancellation(); try record.validate() }
    }

    /// Durably capture both payloads in one local publication. Repeated retry
    /// telemetry never replaces the first captured proposal or creates XP.
    func appendAttemptConflict(_ record: NFAttemptConflictJournalEntry) throws {
        try requireArchiveWriteAvailability()
        let candidate = try Self.attemptConflictCandidate(record, in: archive)
        guard (candidate.attemptConflicts?.count ?? 0) != (archive.attemptConflicts?.count ?? 0) else { return }
        try replace(candidate)
    }

    nonisolated static func attemptConflictCandidate(_ record: NFAttemptConflictJournalEntry, in archive: Archive) throws -> Archive {
        try record.validate()
        if let original = archive.attemptConflicts?.first(where: { $0.id == record.id }) {
            guard original.originalCommitDigest == record.originalCommitDigest,
                  original.proposedCommitDigest == record.proposedCommitDigest else { throw RepositoryError.conflictingAttempt }
            return archive
        }
        var next = archive
        if next.attemptConflicts == nil { next.attemptConflicts = [] }
        next.attemptConflicts?.append(record)
        return next
    }

    func dismissCorrections(_ ids: Set<String>) throws {
        var next = archive
        next.dismissedCorrectionIDs = (next.dismissedCorrectionIDs ?? []).union(ids)
        try replace(next)
    }

    /// The exported form has no nested protected outcome inputs or reusable keys.
    /// Restricted assessment aggregates stay behind their existing repository.
    var exportArchive: Archive {
        var safe = archive
        let protectedSessionIDs = Set(archive.sessions.filter {
            $0.request.evidenceClass == .assessmentHoldout || $0.request.evidenceClass == .nearTransfer
                || $0.request.assessmentBlock != nil || $0.checkpoint.exercise?.assessmentProtected == true
        }.map(\.id))
        let privateConflicts = (archive.attemptConflicts ?? []).filter {
            $0.containsProtectedContent || protectedSessionIDs.contains($0.original.sessionID) || protectedSessionIDs.contains($0.proposed.sessionID)
        }
        let protectedHistoryIDs = (archive.unavailableHistorySnapshots ?? []).filter { $0.reason == .protectedContent }.map(\.attemptID)
        let withheld = Set(privateConflicts.map(\.attemptID)).union(archive.withheldProtectedConflictAttemptIDs ?? []).union(protectedHistoryIDs)
        safe.attemptConflicts = archive.attemptConflicts?.filter { !withheld.contains($0.attemptID) }
        safe.withheldProtectedConflictAttemptIDs = withheld.isEmpty ? nil : withheld.sorted { $0.uuidString < $1.uuidString }
        // Device-local launch authority is never transplanted by a portable archive.
        safe.offlineRotationLedger = nil; safe.rotationMigration = nil
        safe.fixedLaunchReceipts = nil; safe.deletedFixedLaunchCommandIDs = nil
        safe.adaptiveItemReceipts = nil; safe.editorialOverrideCommands = nil; safe.deletedAdaptiveRunIDs = nil
        safe.editorialExplanationPresentations = nil
        safe.retiredOrdinaryDrafts = safe.retiredOrdinaryDrafts?.filter {
            $0.value.schemaVersion == 1 && $0.value.checkpoint.schemaVersion == 1
                && !protectedSessionIDs.contains($0.value.sessionID)
        }
        safe.transactionRevision = nil
        safe.sessions = safe.sessions.map { run in
            var copy = run
            copy.request = run.request.launchOnly()
            if run.checkpoint.exercise == nil {
                copy.checkpoint.result = nil
                copy.checkpoint.protectedCommitReceipt = nil
                copy.checkpoint.correctness = []
                copy.checkpoint.credits = []
                copy.checkpoint.assessmentState = nil
                copy.checkpoint.assessmentCatalogSnapshot = nil
                copy.checkpoint.reflectionTrigger = nil
                copy.checkpoint.suggestedReflectionCode = nil
                copy.checkpoint.selectedReflectionCode = nil
                copy.checkpoint.reflectionNote = ""
                // A portable receipt is recovery-only until the protected
                // evaluator and original ownership have been reconciled.
                copy.status = .migrationRecovery
            }
            copy.request.localCheckpoint = nil
            return copy
        }
        safe.privateStudyRuns = (archive.privateStudyRuns ?? []).compactMap { run in
            guard let data = try? canonicalPrivateStudyPayload(run) else {
                if safe.unavailablePrivateRunIDs == nil { safe.unavailablePrivateRunIDs = [] }
                safe.unavailablePrivateRunIDs?.append(run.id)
                return nil
            }
            return NFLocalPrivateStudyRun(id: run.id, generationID: run.generationID, payload: data, updatedAt: run.updatedAt)
        }
        return NFDataExportService.protectedLocalLearningArchive(safe)
    }

    func restorePredecessor(_ predecessor: Archive) throws { try replace(predecessor) }

    func importArchive(_ incoming: Archive) throws {
        guard incoming.schemaVersion == 1 else { throw RepositoryError.unsupportedVersion }
        guard Set(incoming.sessions.map(\.id)).count == incoming.sessions.count,
              Set(incoming.snapshots.map(\.attemptID)).count == incoming.snapshots.count else {
            throw RepositoryError.conflictingAttempt
        }
        var next = archive
        try Self.validateAttemptConflicts(incoming.attemptConflicts ?? [])
        var conflictByID = Dictionary(uniqueKeysWithValues: (next.attemptConflicts ?? []).map { ($0.id, $0) })
        for record in incoming.attemptConflicts ?? [] {
            guard !record.containsProtectedContent else { throw RepositoryError.corruptSnapshot }
            if let original = conflictByID[record.id] {
                guard original == record else { throw RepositoryError.conflictingAttempt }
            } else { conflictByID[record.id] = record }
        }
        next.attemptConflicts = conflictByID.isEmpty ? next.attemptConflicts : conflictByID.values.sorted { $0.id < $1.id }
        let withheld = Set(next.withheldProtectedConflictAttemptIDs ?? []).union(incoming.withheldProtectedConflictAttemptIDs ?? [])
        next.withheldProtectedConflictAttemptIDs = withheld.isEmpty ? nil : withheld.sorted { $0.uuidString < $1.uuidString }
        let unavailableRuns = Set(next.unavailablePrivateRunIDs ?? []).union(incoming.unavailablePrivateRunIDs ?? [])
        next.unavailablePrivateRunIDs = unavailableRuns.isEmpty ? nil : unavailableRuns.sorted()
        var unavailableByID = Dictionary(uniqueKeysWithValues: (next.unavailableHistorySnapshots ?? []).map { ($0.attemptID, $0) })
        for marker in incoming.unavailableHistorySnapshots ?? [] {
            guard marker.digest.count == 64, marker.digest.allSatisfy(\.isHexDigit) else { throw RepositoryError.corruptSnapshot }
            if let original = unavailableByID[marker.attemptID], original != marker { throw RepositoryError.conflictingAttempt }
            unavailableByID[marker.attemptID] = marker
        }
        guard Set(unavailableByID.keys).isDisjoint(with: Set((next.snapshots + incoming.snapshots).map(\.attemptID))) else {
            throw RepositoryError.conflictingAttempt
        }
        next.unavailableHistorySnapshots = unavailableByID.isEmpty ? next.unavailableHistorySnapshots : unavailableByID.values.sorted { $0.attemptID.uuidString < $1.attemptID.uuidString }
        for var run in incoming.sessions {
            // A portable receipt is not local evaluator or selection authority.
            run.checkpoint.protectedCommitReceipt = nil
            if run.request.ordinaryDelivery?.strategy == .adaptiveItem { run.status = .migrationRecovery }
            guard run.schemaVersion == 1, run.checkpoint.schemaVersion == 1 else { throw RepositoryError.unsupportedVersion }
            if let exercise = run.checkpoint.exercise {
                guard !exercise.assessmentProtected,
                      try NFLocalItemCheckpoint.digest(exercise) == run.checkpoint.exerciseDigest else {
                    throw RepositoryError.corruptSnapshot
                }
            }
            if let old = next.sessions.first(where: { $0.id == run.id }) {
                // Never merge response fields from different revisions.
                guard old.checkpoint.exerciseDigest == run.checkpoint.exerciseDigest,
                      old.checkpoint.response == run.checkpoint.response else { throw RepositoryError.conflictingAttempt }
                continue
            }
            if run.ownerDeviceID != ownerDeviceID { run.status = .migrationRecovery }
            next.sessions.append(run)
        }
        for snapshot in incoming.snapshots {
            guard !snapshot.exercise.assessmentProtected, snapshot.exercise.hasSupportedTraceContract,
                  snapshot.traceInspection.map({ $0.isValid(for: snapshot.exercise) }) ?? true,
                  snapshot.dataInspection?.isCompatible(with: snapshot.exercise) != false,
                  NFScienceStudyDraft.permits(snapshot.scienceStudy, exercise: snapshot.exercise),
                  NFTransferRelationshipDraft.permits(snapshot.transferRelationship, exercise: snapshot.exercise) else { throw RepositoryError.corruptSnapshot }
            if let old = next.snapshots.first(where: { $0.attemptID == snapshot.attemptID }) {
                guard old.exercise == snapshot.exercise,
                      (snapshot.editorialCapture == nil || old.editorialCapture == snapshot.editorialCapture),
                      (snapshot.mathWork == nil || old.mathWork == snapshot.mathWork),
                      (snapshot.traceInspection == nil || old.traceInspection == snapshot.traceInspection),
                      (snapshot.dataInspection == nil || old.dataInspection == snapshot.dataInspection),
                      (snapshot.scienceStudy == nil || old.scienceStudy == snapshot.scienceStudy),
                      (snapshot.transferRelationship == nil || old.transferRelationship == snapshot.transferRelationship) else {
                    throw RepositoryError.conflictingAttempt
                }
            } else { next.snapshots.append(snapshot) }
        }
        for set in incoming.savedSets ?? [] {
            guard set.unavailableReason == nil, set.id == set.result.provenance.requestID else { throw RepositoryError.unsupportedVersion }
            if next.savedSets == nil { next.savedSets = [] }
            if let old = next.savedSets?.first(where: { $0.id == set.id }) {
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.sortedKeys]
                guard try encoder.encode(old.result) == encoder.encode(set.result) else { throw RepositoryError.conflictingAttempt }
            } else { next.savedSets?.append(set) }
        }
        for original in incoming.privateStudyRuns ?? [] {
            let run = NFLocalPrivateStudyRun(id: original.id, generationID: original.generationID,
                payload: try canonicalPrivateStudyPayload(original), updatedAt: original.updatedAt)
            guard run.payload.count <= 8 * 1_024 * 1_024 else { throw RepositoryError.oversized }
            if next.privateStudyRuns == nil { next.privateStudyRuns = [] }
            if let old = next.privateStudyRuns?.first(where: { $0.id == run.id }) {
                guard old.generationID == run.generationID,
                      try canonicalPrivateStudyPayload(old) == run.payload else { throw RepositoryError.conflictingAttempt }
            } else { next.privateStudyRuns?.append(run) }
        }
        var dispositions = Dictionary(uniqueKeysWithValues: (next.evidenceDispositions ?? []).map { ($0.id, $0) })
        for record in incoming.evidenceDispositions ?? [] {
            if let existing = dispositions[record.id], existing != record { throw RepositoryError.conflictingAttempt }
            dispositions[record.id] = record
        }
        next.evidenceDispositions = dispositions.values.sorted { $0.id < $1.id }
        var corrections = Dictionary(uniqueKeysWithValues: (next.contentCorrections ?? []).map { ($0.id, $0) })
        for record in incoming.contentCorrections ?? [] {
            if let existing = corrections[record.id], existing != record { throw RepositoryError.conflictingAttempt }
            corrections[record.id] = record
        }
        next.contentCorrections = corrections.values.sorted { $0.id < $1.id }
        next.activeContentCorrectionIDs = (next.activeContentCorrectionIDs ?? [:])
            .merging(incoming.activeContentCorrectionIDs ?? [:]) { existing, _ in existing }
        if let incomingLedger = incoming.selectionLedger {
            try Self.validateSelectionLedger(incomingLedger)
            next.selectionLedger = try Self.mergeSelectionLedgers(next.selectionLedger ?? .init(), incomingLedger)
        }
        for (key, retired) in incoming.retiredOrdinaryDrafts ?? [:] {
            guard retired.schemaVersion == 1, retired.checkpoint.schemaVersion == 1 else { throw RepositoryError.unsupportedVersion }
            if let existing = next.retiredOrdinaryDrafts?[key], existing != retired { throw RepositoryError.conflictingAttempt }
            if next.retiredOrdinaryDrafts == nil { next.retiredOrdinaryDrafts = [:] }
            next.retiredOrdinaryDrafts?[key] = retired
        }
        next = try Self.validatedArchive(next)
        try replace(next)
    }

    nonisolated private static func validateSelectionLedger(_ ledger: NFSelectionReservationLedger, checkCancellation: () throws -> Void = {}) throws {
        guard ledger.schemaVersion == 1 else { throw RepositoryError.unsupportedVersion }
        for snapshot in ledger.snapshots.values {
            try checkCancellation()
            guard snapshot.payload.count <= NFSelectionReservationPolicy.maximumSnapshotBytes,
                  snapshot.digest == NFReservationSnapshot.digest(snapshot.payload),
                  let exercise = try? JSONDecoder().decode(NFExercise.self, from: snapshot.payload),
                  !exercise.assessmentProtected, exercise.evidenceClass != .documentPractice else {
                throw RepositoryError.corruptSnapshot
            }
        }
        for (id, slot) in ledger.slots {
            try checkCancellation()
            guard id == slot.id, ledger.runs[slot.runID]?.slotIDs.contains(id) == true,
                  NFSelectionReservationPolicy.snapshot(for: slot, in: ledger)?.digest == slot.snapshotDigest else {
                throw RepositoryError.corruptSnapshot
            }
        }
        guard ledger.runs.allSatisfy({ $0.key == $0.value.id && UUID(uuidString: $0.value.ownerDeviceID) != nil }),
              ledger.exposures.allSatisfy({ $0.key == $0.value.eventID && ledger.slots[$0.value.slotID]?.runID == $0.value.runID }),
              ledger.outcomes.allSatisfy({ $0.key == $0.value.eventID && ledger.slots[$0.value.slotID]?.runID == $0.value.runID }) else {
            throw RepositoryError.corruptSnapshot
        }
    }

    private static func mergeSelectionLedgers(_ current: NFSelectionReservationLedger,
                                               _ incoming: NFSelectionReservationLedger) throws -> NFSelectionReservationLedger {
        func merged<T: Equatable>(_ a: [String: T], _ b: [String: T]) throws -> [String: T] {
            var result = a
            for (key, value) in b {
                if let old = result[key], old != value { throw RepositoryError.conflictingAttempt }
                result[key] = value
            }
            return result
        }
        var result = current
        result.scopes = try merged(current.scopes, incoming.scopes)
        result.runs = try merged(current.runs, incoming.runs)
        result.slots = try merged(current.slots, incoming.slots)
        result.snapshots = try merged(current.snapshots, incoming.snapshots)
        result.decisions = try merged(current.decisions, incoming.decisions)
        result.exposures = try merged(current.exposures, incoming.exposures)
        result.outcomes = try merged(current.outcomes, incoming.outcomes)
        result.legacyPlans = try merged(current.legacyPlans, incoming.legacyPlans)
        result.legacyReservationOwners = try merged(current.legacyReservationOwners, incoming.legacyReservationOwners)
        result.revision = max(current.revision, incoming.revision)
        return result
    }

    private func withPublicationLock<Result>(_ operation: () throws -> Result) throws -> Result {
        try requireArchiveWriteAvailability()
        guard Self.publicationLock.try() else { throw RepositoryError.busy }
        defer { Self.publicationLock.unlock() }
        return try withDiskPublicationLock(operation)
    }

    private func withDiskPublicationLock<Result>(_ operation: () throws -> Result) throws -> Result {
            guard let url else { return try operation() }
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let descriptor = Darwin.open(url.path + ".lock", O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
            guard descriptor >= 0 else { throw CocoaError(.fileWriteUnknown) }
            defer { Darwin.close(descriptor) }
            // This coordinator owns UI state. Competing processes must cause a
            // recoverable retry before transaction work, never an unbounded UI
            // wait. Once acquired, the lock still covers the entire publication.
            guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else {
                let failure = errno
                if failure == EWOULDBLOCK || failure == EAGAIN { throw RepositoryError.busy }
                throw CocoaError(.fileWriteUnknown)
            }
            defer { flock(descriptor, LOCK_UN) }
            return try operation()
    }

    private func readArchiveFromDisk() throws -> Archive? {
        guard let url, FileManager.default.fileExists(atPath: url.path) else { return nil }
        let original = try Self.boundedData(at: url)
        let recovered = try Self.decodedArchive(original)
        if recovered.requiresBackup { try preserveHistoryRecoveryOriginal(original) }
        acknowledgedOriginalDigest = NFReservationSnapshot.digest(original)
        return recovered.archive
    }

    private func diskRevision() throws -> UInt64 {
        guard let url else { return archive.transactionRevision ?? 0 }
        guard FileManager.default.fileExists(atPath: url.path) else {
            guard archive.transactionRevision == nil else { throw RepositoryError.staleRevision }
            return 0
        }
        struct Header: Decodable { let schemaVersion: Int; let transactionRevision: UInt64? }
        let original = try Self.boundedData(at: url)
        guard acknowledgedOriginalDigest == NFReservationSnapshot.digest(original) else { throw RepositoryError.staleRevision }
        let header = try JSONDecoder().decode(Header.self, from: original)
        guard header.schemaVersion == 1 else { throw RepositoryError.unsupportedVersion }
        return header.transactionRevision ?? 0
    }

    private func replace(_ next: Archive) throws {
        try withPublicationLock { try replaceUnlocked(next) }
    }

    private func replaceUnlocked(_ replacement: Archive) throws {
        try requireArchiveWriteAvailability()
        guard loadError == nil else { throw RepositoryError.corruptSnapshot }
        let expected = archive.transactionRevision ?? 0
        guard try diskRevision() == expected else { throw RepositoryError.staleRevision }
        let (revision, overflow) = expected.addingReportingOverflow(1)
        guard !overflow else { throw RepositoryError.unsupportedVersion }
        var next = replacement
        next.transactionRevision = revision
        let data = try JSONEncoder().encode(next)
        guard data.count <= Self.maximumBytes else { throw RepositoryError.oversized }
        if let url {
            #if os(iOS)
            try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            #else
            // Set restrictive permissions on the temporary file BEFORE the
            // atomic rename so a post-commit chmod cannot create an ambiguous failure.
            let temporary = url.deletingLastPathComponent().appending(path: ".local-transaction-\(UUID().uuidString)")
            defer { try? FileManager.default.removeItem(at: temporary) }
            try data.write(to: temporary)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: temporary.path)
            guard Darwin.rename(temporary.path, url.path) == 0 else { throw CocoaError(.fileWriteUnknown) }
            #endif
        }
        archive = next
        acknowledgedOriginalDigest = url == nil ? nil : NFReservationSnapshot.digest(data)
        archiveWriteVerificationNeeded = false
    }

}

extension SessionRequest {
    /// Canonical configuration is separate from a recovery payload. This also
    /// prevents nested legacy checkpoints from leaking into portable receipts.
    // Catalog inspection authenticates the original contract before separately
    // reporting quarantine. Delivery copies keep their original filter by default.
    func launchOnly(offlineQuestionOrdinals replacementOrdinals: [Int]? = nil,
                    omittingQuarantineForCatalogInspection: Bool = false) -> SessionRequest {
        var clean = SessionRequest(lab: lab, source: source, seed: seed, localeIdentifier: localeIdentifier,
            requestedMinutes: requestedMinutes, preferredMentalMathKind: preferredMentalMathKind,
            evidenceClass: evidenceClass, field: field, topic: topic, recommendationRationale: recommendationRationale,
            targetDifficulty: targetDifficulty, requestedItemCount: requestedItemCount,
            offlineQuestionOrdinals: replacementOrdinals ?? offlineQuestionOrdinals, assessmentBlock: assessmentBlock,
            reassessmentCycle: reassessmentCycle, planID: planID, planBlockID: planBlockID,
            isTimed: isTimed, timingCondition: timingCondition, mechanicID: mechanicID, retentionItemIDs: retentionItemIDs,
            retentionTargets: retentionTargets, transferBrief: transferBrief,
            quarantinedItemIDs: omittingQuarantineForCatalogInspection && assessmentBlock == nil && evidenceClass == .practice ? [] : quarantinedItemIDs,
            quarantinedAssessmentDescriptorIDs: quarantinedAssessmentDescriptorIDs)
        clean.id = id
        clean.localSessionID = localSessionID
        clean.repairOriginAttemptID = repairOriginAttemptID
        clean.repairSemanticExclusions = repairSemanticExclusions
        clean.offlineRotationPlan = offlineRotationPlan
        clean.ordinaryDelivery = ordinaryDelivery
        clean.tracePolicyVersion = tracePolicyVersion
        clean.scienceStudyPolicyVersion = scienceStudyPolicyVersion
        clean.scienceStudyExcludedContextID = scienceStudyExcludedContextID
        clean.graphConstructionPolicyVersion = graphConstructionPolicyVersion
        clean.retrievalAuthorityPolicyVersion = retrievalAuthorityPolicyVersion
        clean.retrievalAssetPolicyVersion = retrievalAssetPolicyVersion
        clean.spatialStructurePolicyVersion = spatialStructurePolicyVersion
        clean.coordinateTransformPolicyVersion = coordinateTransformPolicyVersion
        clean.solidSectionPolicyVersion = solidSectionPolicyVersion
        clean.netFoldingPolicyVersion = netFoldingPolicyVersion
        clean.coordinateReasoningPolicyVersion = coordinateReasoningPolicyVersion
        clean.spatialAssemblyPolicyVersion = spatialAssemblyPolicyVersion
        clean.transferPolicyVersion = transferPolicyVersion
        clean.transferExcludedContextID = transferExcludedContextID
        return clean
    }
}

extension AppStore {
    var evidenceDispositions: [NFHistoricalPracticeDispositionRecord] { localSessions.archive.evidenceDispositions ?? [] }
    var unacknowledgedCorrections: [NFHistoricalPracticeDispositionRecord] {
        evidenceDispositions.filter { !(localSessions.archive.dismissedCorrectionIDs ?? []).contains($0.id) }
    }
    func acknowledgeCorrections() throws {
        try localSessions.dismissCorrections(Set(unacknowledgedCorrections.map(\.id)))
        localSessionRevision += 1
    }

    /// Provenance-based authority correction; no old response or score is edited.
    func reconcileHistoricalAuthority() throws {
        var records = attempts.compactMap { attempt -> NFHistoricalPracticeDispositionRecord? in
            if attempt.errorCode == "protected_evaluator_unavailable" {
                return NFHistoricalPracticeDispositionRecord(
                    id: "protected-receipt-v1:\(attempt.id.uuidString.lowercased())", attemptID: attempt.id.uuidString,
                    revision: 1, policyVersion: NFHistoricalPracticeProjection.policyVersion,
                    occurredAt: attempt.submittedAt, disposition: .excludedContentCorrection,
                    reason: "This protected response was restored without its restricted evaluator. The original answer is retained; no incorrect result or skill estimate is inferred.",
                    correctedDerivedCredit: nil, supersedesDispositionID: nil)
            }
            guard attempt.scoringVersion < 8,
                  ["selfCheck", "sourceSelfCheck"].contains(attempt.responseFormatRaw) else { return nil }
            return NFHistoricalPracticeDispositionRecord(
                id: "self-reported-v1:\(attempt.id.uuidString.lowercased())", attemptID: attempt.id.uuidString,
                revision: 1, policyVersion: NFHistoricalPracticeProjection.policyVersion,
                occurredAt: attempt.submittedAt, disposition: .personalStudy,
                reason: "This was a personal self-check. The original answer and match rating are retained; it is excluded from verified accuracy and skill evidence.",
                correctedDerivedCredit: nil, supersedesDispositionID: nil)
        }
        var recommendations: [NFHistoricalContentCorrectionRecommendation] = []
        var activeRecommendationIDs: [String: [String]] = [:]
        let originalSnapshots = Dictionary(uniqueKeysWithValues: localSessions.archive.snapshots.map { ($0.attemptID, $0.exercise) })
        for attempt in attempts where !attempt.wasSkipped
            && attempt.assessmentBlockRaw == nil && attempt.errorCode != "protected_evaluator_unavailable" {
            let snapshot = originalSnapshots[attempt.id]
            guard attempt.scoringVersion < 8 || (attempt.scoringVersion == 8
                && snapshot.map({ NFContentCorrectionPolicy.hasContradictoryEstimateExactNumericAliases($0)
                    || NFContentCorrectionPolicy.knownWorkflowOnly($0) || NFRetrievalResponseAuthority.legacySuccessorTarget(in: $0) != nil }) == true) else { continue }
            guard snapshot?.assessmentProtected != true,
                  ![EvidenceClass.assessmentHoldout.rawValue, EvidenceClass.nearTransfer.rawValue].contains(attempt.evidenceClassRaw) else { continue }
            var input = NFHistoricalContentCorrectionInput(attemptID: attempt.id.uuidString,
                itemID: attempt.itemID, templateID: attempt.templateID, originalScoringVersion: attempt.scoringVersion,
                prompt: attempt.prompt, rawResponse: attempt.response, originalExpectedAnswer: attempt.correctAnswerText,
                originalIsCorrect: attempt.isCorrect, originalCredit: attempt.deterministicCredit)
            input.responseFormatRaw = attempt.responseFormatRaw
            input.originalRecordedAt = attempt.submittedAt
            input.originalConfidenceRaw = attempt.confidenceRaw
            input.exactSnapshot = snapshot
            input.snapshotVerifiedAsOriginal = snapshot != nil
            input.generatorVersion = snapshot?.generatorVersion
            input.hasUnresolvedContentReport = itemReports.contains { $0.itemID == attempt.itemID && $0.status == "quarantined" }
            let audit = NFContentCorrectionPolicy.audit(input)
            let substantive = audit.recommendations.filter { $0.disposition != .legacyUncalibrated }
            recommendations.append(contentsOf: substantive)
            activeRecommendationIDs[attempt.id.uuidString] = substantive.map(\.id).sorted()
            // Broader speed/independence exclusions are retained separately.
            // They cannot erase a valid historical accuracy result.
            let excludesAccuracy = substantive.contains { $0.excludedScopes.contains(.accuracy) }
            let credits = Set(substantive.compactMap(\.correctedCredit))
            let predecessor = evidenceDispositions.filter { $0.attemptID == attempt.id.uuidString }
                .max { $0.revision < $1.revision }
            let restoresResolvedContract = predecessor?.id.hasPrefix("content-correction:") == true
                && (localSessions.archive.activeContentCorrectionIDs?[attempt.id.uuidString] ?? []) != substantive.map(\.id).sorted()
            guard excludesAccuracy || !credits.isEmpty || restoresResolvedContract else { continue }
            // The established self-report repair already owns this disposition.
            let personal = substantive.contains(where: { $0.disposition == .selfReported })
            if personal && records.contains(where: { $0.attemptID == attempt.id.uuidString && $0.disposition == .personalStudy }) { continue }
            let identity = substantive.map(\.id).sorted().joined(separator: "|")
            let id = "content-correction:" + SHA256.hash(data: Data((attempt.id.uuidString + identity).utf8)).map { String(format: "%02x", $0) }.joined()
            if evidenceDispositions.contains(where: { $0.id == id }) { continue }
            let invalid = excludesAccuracy || credits.count > 1
            let rationale = substantive.filter { $0.excludedScopes.contains(.accuracy) || $0.correctedCredit != nil }
                .map(\.rationale).joined(separator: " ")
            records.append(NFHistoricalPracticeDispositionRecord(id: id, attemptID: attempt.id.uuidString,
                revision: (predecessor?.revision ?? 0) + 1, policyVersion: NFHistoricalPracticeProjection.policyVersion,
                occurredAt: attempt.submittedAt, disposition: personal ? .personalStudy : invalid ? .excludedContentCorrection : .legacyPracticeHistory,
                reason: rationale.isEmpty ? "The retained original contract now resolves the earlier grading uncertainty. Valid historical practice is retained without a new skill or difficulty claim." : rationale,
                correctedDerivedCredit: invalid ? nil : credits.first, supersedesDispositionID: predecessor?.id))
        }
        try localSessions.appendDispositions(records, contentCorrections: recommendations, activeContentCorrectionIDs: activeRecommendationIDs)
    }

    func hasAttemptEvidenceConflict(_ id: UUID) -> Bool {
        conflictingPhysicalAttemptIDs.contains(id) || unresolvedAttemptConflictIDs.contains(id)
            || localSessions.archive.attemptConflicts?.contains(where: { $0.attemptID == id }) == true
            || localSessions.archive.withheldProtectedConflictAttemptIDs?.contains(id) == true
    }

    var historicalPracticeSummaries: [NFHistoricalPracticeSummary] {
        NFHistoricalPracticeProjection.reduce(attempts: attempts.filter { !hasAttemptEvidenceConflict($0.id) }
            .map(effectiveAttemptDTO), dispositions: evidenceDispositions)
    }

    func effectiveAttemptDTO(_ attempt: AttemptRecord) -> AttemptDTO {
        let raw = attempt.dto
        let conflicted = hasAttemptEvidenceConflict(attempt.id)
        let protectedHistoryUnavailable = localSessions.archive.unavailableHistorySnapshots?.contains {
            $0.attemptID == attempt.id && $0.reason == .protectedContent
        } == true
        let disposition = evidenceDispositions.filter { $0.attemptID == attempt.id.uuidString }.max { $0.revision < $1.revision }
        let excluded = conflicted || protectedHistoryUnavailable
            || (disposition.map { $0.disposition != .legacyPracticeHistory && $0.disposition != .editorialEvidence } ?? false)
        let scopeExclusions = Set((localSessions.archive.contentCorrections ?? [])
            .filter { record in record.originalAttemptID == attempt.id.uuidString
                && record.policyVersion == NFContentCorrectionPolicy.historicalPolicyVersion
                && (localSessions.archive.activeContentCorrectionIDs?[attempt.id.uuidString].map { $0.contains(record.id) } ?? true) }
            .flatMap(\.excludedScopes))
        let effectiveCredit = disposition?.correctedDerivedCredit ?? raw.credit
        let observation = NFEditorialCommitCapturePolicy.project(snapshot: localSessions.editorialSnapshot(for: attempt.id),
            record: NFImmutableAttemptRecordSnapshot(attempt), effectiveCredit: effectiveCredit,
            excluded: excluded || scopeExclusions.contains(.bandEvidence) || scopeExclusions.contains(.proficiency)
                || scopeExclusions.contains(.independentEvidence) || scopeExclusions.contains(.accuracy)
                || itemReports.contains { $0.status == "quarantined" && $0.itemID == attempt.itemID },
            admissions: localSessions.editorialAdmissions,
            localAuthorityVerified: localSessions.editorialSnapshot(for: attempt.id)?.editorialCapture
                .map { localSessions.hasEditorialAuthority(for: $0) } ?? false).observation
        return AttemptDTO(id: raw.id, itemID: raw.itemID, alternateFormID: raw.alternateFormID,
            skillID: raw.skillID, skillWeights: raw.skillWeights, lab: raw.lab,
            correct: disposition?.correctedDerivedCredit.map { $0 >= 1 } ?? raw.correct,
            credit: disposition?.correctedDerivedCredit ?? raw.credit,
            confidence: excluded || scopeExclusions.contains(.calibration) ? nil : raw.confidence, submittedAt: raw.submittedAt,
            evidenceClass: raw.evidenceClass, evidenceWeight: excluded || scopeExclusions.contains(.proficiency) || scopeExclusions.contains(.independentEvidence) ? 0 : raw.evidenceWeight,
            interruptionCount: raw.interruptionCount, accommodationFlags: raw.accommodationFlags,
            wasTimed: raw.wasTimed && !conflicted && !protectedHistoryUnavailable && !scopeExclusions.contains(.cleanSpeed), spatialDifficultyParameters: raw.spatialDifficultyParameters,
            assessmentFormat: raw.assessmentFormat, editorialObservation: observation,
            responseFormatRaw: raw.responseFormatRaw, wasSkipped: raw.wasSkipped, hintCount: raw.hintCount)
    }

    /// Called only for a new immutable attempt, after conflict preflight and
    /// after the exact prepared checkpoint is durable. Never backfills legacy rows.
    func captureEditorialCommit(record: AttemptRecord, exercise: NFExercise,
                                result: NFExerciseScoringResult, calendar: Calendar = .current) -> NFEditorialCommitCapture? {
        guard let profile, let ledger = localSessions.archive.selectionLedger,
              let envelope = localSessions.archive.sessions.first(where: { $0.id == record.sessionID }) else { return nil }
        return NFEditorialCommitCapturePolicy.make(record: NFImmutableAttemptRecordSnapshot(record), exercise: exercise,
            result: result, envelope: envelope, ledger: ledger, profileID: profile.id,
            dayBoundaryHour: profile.dayBoundaryHour, calendar: calendar,
            transactionRevision: localSessions.archive.transactionRevision ?? 0,
            runtimeWitness: localSessions.editorialRuntimeWitness(for: envelope, exercise: exercise))
    }

    func isGenerationSaved(_ id: UUID) -> Bool {
        _ = localSessionRevision
        return localSessions.archive.savedSets?.contains { $0.id == id } == true
    }

    func saveGenerationSet(_ id: UUID) throws {
        guard let result = recoverAIGeneration(id: id) else { throw NFLocalSessionRepository.RepositoryError.corruptSnapshot }
        try localSessions.saveSet(result, at: Date())
        localSessionRevision += 1
    }

    func unsaveGenerationSet(_ id: UUID) throws {
        try localSessions.unsaveSet(id)
        localSessionRevision += 1
    }

    var resumableSessions: [NFLocalSessionEnvelope] {
        _ = localSessionRevision
        return localSessions.archive.sessions.filter { $0.status == .suspended && $0.ownerDeviceID == localSessions.ownerDeviceID }
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    @discardableResult
    func resumeSession(_ sessionID: UUID) -> Bool {
        guard activeSessionRequest == nil,
              let run = resumableSessions.first(where: { $0.id == sessionID }) else { return false }
        var request = run.request
        request.localCheckpoint = run.checkpoint
        request.localSessionID = run.id
        activeSessionRequest = request
        return true
    }

    func historySnapshotUnavailableReason(for attemptID: UUID) -> String? {
        _ = localSessionRevision
        guard localSessions.archive.unavailableHistorySnapshots?.contains(where: { $0.attemptID == attemptID }) == true else { return nil }
        return NFAppLocalization.localizedCatalogValue("This saved question could not be verified. Your original answer is retained.", locale: NFAppLocalization.preferredLocale)
    }

    func exerciseSnapshot(for attemptID: UUID) -> NFExercise? {
        localSessions.archive.snapshots.first { $0.attemptID == attemptID }?.exercise
    }

    func endSavedSession(_ sessionID: UUID) throws {
        try localSessions.end(sessionID)
        localSessionRevision += 1
    }
}


/// File identity is cheap to recheck on MainActor; its content digest is computed
/// off actor while the same writer lock remains held through adoption.
struct NFLocalSessionStartupFileIdentity: Equatable, Sendable {
    let device: UInt64
    let inode: UInt64
    let size: Int64
    let modificationSeconds: Int64
    let modificationNanoseconds: Int64
    let changeSeconds: Int64
    let changeNanoseconds: Int64

    static func capture(at url: URL) throws -> Self? {
        var info = stat()
        if Darwin.lstat(url.path, &info) != 0 {
            if errno == ENOENT { return nil }
            throw CocoaError(.fileReadUnknown)
        }
        guard info.st_mode & S_IFMT == S_IFREG else { throw NFLocalSessionRepository.RepositoryError.corruptSnapshot }
        return .init(device: UInt64(truncatingIfNeeded: info.st_dev), inode: UInt64(info.st_ino), size: Int64(info.st_size),
            modificationSeconds: Int64(info.st_mtimespec.tv_sec), modificationNanoseconds: Int64(info.st_mtimespec.tv_nsec),
            changeSeconds: Int64(info.st_ctimespec.tv_sec), changeNanoseconds: Int64(info.st_ctimespec.tv_nsec))
    }
}

/// The sole mutable resource in a preparation is an idempotently closed FD.
/// Its lock synchronizes with the repository's existing `.lock` writer scope.
/// No NSLock is held across an await, and no model/context crosses actors.
final class NFLocalSessionStartupReadLease: @unchecked Sendable {
    private let state = NSLock()
    private var descriptor: Int32?
    private let lockURL: URL
    private let lockDevice: UInt64
    private let lockInode: UInt64

    init(at url: URL) throws {
        let manager = FileManager.default, directory = url.deletingLastPathComponent()
        try manager.createDirectory(at: directory, withIntermediateDirectories: true)
        let descriptor = Darwin.open(url.path + ".lock", O_CREAT | O_RDWR | O_NOFOLLOW | O_CLOEXEC | O_NONBLOCK, S_IRUSR | S_IWUSR)
        guard descriptor >= 0 else { throw CocoaError(.fileReadUnknown) }
        var info = stat()
        guard fstat(descriptor, &info) == 0, info.st_mode & S_IFMT == S_IFREG else {
            Darwin.close(descriptor); throw NFLocalSessionRepository.RepositoryError.corruptSnapshot
        }
        guard flock(descriptor, LOCK_SH | LOCK_NB) == 0 else {
            let failure = errno; Darwin.close(descriptor)
            if failure == EWOULDBLOCK || failure == EAGAIN { throw NFLocalSessionRepository.RepositoryError.busy }
            throw CocoaError(.fileReadUnknown)
        }
        self.descriptor = descriptor
        lockURL = URL(fileURLWithPath: url.path + ".lock")
        lockDevice = UInt64(truncatingIfNeeded: info.st_dev); lockInode = UInt64(info.st_ino)
    }
    func withHeld<Value>(_ operation: () throws -> Value) throws -> Value {
        try state.withLock {
            guard descriptor != nil, let current = try NFLocalSessionStartupFileIdentity.capture(at: lockURL),
                  current.device == lockDevice, current.inode == lockInode else {
                throw NFLocalSessionRepository.RepositoryError.staleRevision
            }
            return try operation()
        }
    }
    func release() {
        state.withLock {
            guard let descriptor else { return }
            self.descriptor = nil; flock(descriptor, LOCK_UN); Darwin.close(descriptor)
        }
    }
    deinit { release() }
}

extension NFLocalSessionRepository {
    enum StartupWorkStage: Sendable { case acquiredInput, decoding, validated, preservedOriginal }

    /// Initialization is private to the verified worker. Callers can inspect the
    /// receipt, but cannot substitute an archive, digest, revision or lease.
    struct PreparedStartup: Sendable {
        let sourceURL: URL
        let ownerDeviceID: UUID
        let sourceDigest: String?
        let archiveRevision: UInt64?
        let loadError: String?
        fileprivate let sourceIdentity: NFLocalSessionStartupFileIdentity?
        fileprivate let value: Archive
        fileprivate let lease: NFLocalSessionStartupReadLease

        fileprivate init(sourceURL: URL, ownerDeviceID: UUID, sourceDigest: String?, loadError: String?,
                         sourceIdentity: NFLocalSessionStartupFileIdentity?, value: Archive,
                         lease: NFLocalSessionStartupReadLease) {
            self.sourceURL = sourceURL; self.ownerDeviceID = ownerDeviceID
            self.sourceDigest = sourceDigest; self.loadError = loadError
            self.sourceIdentity = sourceIdentity; self.value = value; self.lease = lease
            archiveRevision = value.transactionRevision
        }
        func discard() { lease.release() }
    }

    /// Disposable startup work only. Cancellation never interrupts an answer
    /// transaction and never replaces the original local archive.
    nonisolated static func prepareStartup(at url: URL, ownerDeviceID: UUID,
        observe: (@Sendable (StartupWorkStage) -> Void)? = nil) async throws -> PreparedStartup {
        let sourceURL = url.standardizedFileURL
        let worker = Task.detached(priority: .userInitiated) {
            try Task.checkCancellation()
            let lease = try NFLocalSessionStartupReadLease(at: sourceURL)
            var returned = false
            defer { if !returned { lease.release() } }
            let identity = try NFLocalSessionStartupFileIdentity.capture(at: sourceURL)
            observe?(.acquiredInput)
            try Task.checkCancellation()
            var decoded = Archive(), digest: String?, failure: String?
            if identity != nil {
                do {
                    let original = try boundedData(at: sourceURL, checkCancellation: { try Task.checkCancellation() })
                    digest = NFReservationSnapshot.digest(original)
                    guard try NFLocalSessionStartupFileIdentity.capture(at: sourceURL) == identity else { throw RepositoryError.staleRevision }
                    observe?(.decoding)
                    let recovered = try decodedArchive(original, checkCancellation: { try Task.checkCancellation() })
                    try Task.checkCancellation()
                    decoded = recovered.archive
                    observe?(.validated)
                    if recovered.requiresBackup {
                        // Preserve an exact private original before making the
                        // granular unavailable-item projection adoptable.
                        try preserveHistoryRecoveryOriginal(original, at: sourceURL)
                        observe?(.preservedOriginal)
                    }
                } catch is CancellationError { throw CancellationError() }
                catch RepositoryError.staleRevision { throw RepositoryError.staleRevision }
                catch {
                    // Match synchronous recovery. A fully validated granular
                    // projection remains readable if backup preservation fails,
                    // but loadError continues to prevent every repository write.
                    failure = error.localizedDescription
                }
            }
            try Task.checkCancellation()
            guard try NFLocalSessionStartupFileIdentity.capture(at: sourceURL) == identity else { throw RepositoryError.staleRevision }
            let result = PreparedStartup(sourceURL: sourceURL, ownerDeviceID: ownerDeviceID,
                sourceDigest: digest, loadError: failure, sourceIdentity: identity, value: decoded, lease: lease)
            returned = true; return result
        }
        return try await withTaskCancellationHandler {
            let prepared = try await worker.value
            do { try Task.checkCancellation(); return prepared }
            catch { prepared.discard(); throw error }
        } onCancel: { worker.cancel() }
    }

    /// This performs no archive read, JSON decode, hash, or full validation on
    /// MainActor. The verified read lease stays held until publication finishes.
    static func adoptPreparedStartup(_ prepared: PreparedStartup, at url: URL,
                                     ownerDeviceID: UUID, isCurrentLaunch: () -> Bool = { true }) throws -> NFLocalSessionRepository {
        defer { prepared.discard() }
        return try prepared.lease.withHeld {
        guard isCurrentLaunch() else { throw CancellationError() }
        guard prepared.sourceURL == url.standardizedFileURL else { throw RepositoryError.staleRevision }
        guard prepared.ownerDeviceID == ownerDeviceID else { throw RepositoryError.wrongOwner }
        guard prepared.archiveRevision == prepared.value.transactionRevision,
              prepared.sourceDigest.map({ $0.count == 64 && $0.allSatisfy(\.isHexDigit) }) ?? (prepared.sourceIdentity == nil || prepared.loadError != nil),
              try NFLocalSessionStartupFileIdentity.capture(at: url) == prepared.sourceIdentity else { throw RepositoryError.staleRevision }
        let repository = NFLocalSessionRepository(emptyURL: url, ownerDeviceID: ownerDeviceID)
        repository.archive = prepared.value
        repository.acknowledgedOriginalDigest = prepared.sourceDigest
        repository.loadError = prepared.loadError
        return repository
        }
    }

    /// Called only after the cold restore coordinator has finished replay and
    /// after any account transition is classified. Cache publication is guarded
    /// against both a superseded launch and any intervening same-process change.
    static func loadForDurableStore(at storeURL: URL,
                                   isCurrentLaunch: () -> Bool) async throws -> NFLocalSessionRepository {
        let namespace = durableNamespace(at: storeURL)
        let configuration = persistentConfiguration(namespace: namespace)
        let original = persistentRepositories[configuration.url.path]
        let originalGeneration = original?.startupPublicationGeneration
        guard original?.hasActiveWriter != true, original?.hasPendingArchiveWrite != true else { throw RepositoryError.busy }
        let prepared = try await prepareStartup(at: configuration.url, ownerDeviceID: configuration.owner)
        defer { prepared.discard() }
        try Task.checkCancellation()
        guard isCurrentLaunch() else { throw CancellationError() }
        guard UserDefaults.standard.string(forKey: "NeuroForge.localSessionOwner.v1") == configuration.owner.uuidString else {
            throw RepositoryError.wrongOwner
        }
        guard persistentRepositories[configuration.url.path] === original,
              original?.startupPublicationGeneration == originalGeneration,
              original?.hasActiveWriter != true, original?.hasPendingArchiveWrite != true else { throw RepositoryError.staleRevision }
        let repository = try adoptPreparedStartup(prepared, at: configuration.url, ownerDeviceID: configuration.owner, isCurrentLaunch: isCurrentLaunch)
        persistentRepositories[configuration.url.path] = repository
        scopedRepositories[namespace] = repository
        return repository
    }
}

extension NFLocalSessionRepository {
    func hasEditorialAuthority(for capture: NFEditorialCommitCapture) -> Bool {
        guard let witness = capture.runtimeWitness, witness.isSupported,
              capture.ownerDeviceID == ownerDeviceID,
              let run = archive.sessions.first(where: { $0.id == capture.sessionID }),
              run.ownerDeviceID == ownerDeviceID, run.status != .migrationRecovery,
              run.request.ordinaryDelivery?.profileID == capture.profileID,
              run.request.ordinaryDelivery?.editorialPolicy?.catalogVersion == editorialAdmissions.version,
              run.request.ordinaryDelivery?.editorialPolicy?.catalogDigest == editorialAdmissions.fingerprint,
              let receipt = archive.adaptiveItemReceipts?[witness.decisionID], receipt.isSupported,
              receipt.sessionID == capture.sessionID, receipt.ownerDeviceID == ownerDeviceID,
              receipt.slotID.uuidString == capture.slotID, receipt.attemptID == capture.attemptID,
              receipt.exerciseDigest == capture.exerciseDigest,
              receipt.editorialDecision?.admission == witness.admission,
              receipt.editorialDecision?.reviewAssignment == witness.reviewAssignment,
              receipt.editorialDecision?.selection.catalogVersion == witness.catalogVersion,
              let slot = archive.selectionLedger?.slots[capture.slotID],
              slot.runID == capture.sessionID.uuidString, slot.attemptID == capture.attemptID.uuidString,
              slot.snapshotDigest == capture.exerciseDigest else { return false }
        return true
    }

    /// Writable timing belongs to an authenticated accepted slot, not to a
    /// caller-supplied demand or a portable timing label. No observation is minted.
    func admittedTimingDemand(request: SessionRequest, exercise: NFExercise, slotID: UUID,
                              decisionID: String?, profileID: UUID?) -> NFEditorialDemandRecord? {
        guard loadError == nil, let delivery = request.ordinaryDelivery, delivery.isSupported,
              let profileID, delivery.profileID == profileID,
              let pin = delivery.editorialPolicy, pin.isSupported,
              let run = archive.sessions.first(where: { $0.id == request.id }),
              run.ownerDeviceID == ownerDeviceID, run.status != .migrationRecovery,
              run.request.ordinaryDelivery == delivery, run.checkpoint.slotID == slotID,
              let decisionID, run.checkpoint.ordinaryReservationDecisionID == decisionID,
              let receipt = archive.adaptiveItemReceipts?[decisionID], receipt.isSupported,
              receipt.sessionID == run.id, receipt.ownerDeviceID == ownerDeviceID,
              receipt.slotID == slotID, receipt.attemptID == run.checkpoint.attemptID,
              receipt.configurationDigest == (try? NFLocalReservationBridge.configurationDigest(request)),
              let admission = editorialAdmissions.entry(exercise: exercise, pin: pin),
              receipt.editorialDecision?.admission == admission,
              receipt.exerciseDigest == admission.exerciseDigest,
              run.checkpoint.exerciseDigest == admission.exerciseDigest,
              let slot = archive.selectionLedger?.slots[slotID.uuidString],
              slot.runID == run.id.uuidString, slot.attemptID == receipt.attemptID.uuidString,
              slot.snapshotDigest == admission.exerciseDigest else { return nil }
        return admission.demand
    }

    func editorialRuntimeWitness(for envelope: NFLocalSessionEnvelope, exercise: NFExercise) -> NFEditorialRuntimeWitness? {
        guard let pin = envelope.request.ordinaryDelivery?.editorialPolicy, pin.isSupported,
              envelope.ownerDeviceID == ownerDeviceID, envelope.status == .suspended,
              let decisionID = envelope.checkpoint.ordinaryReservationDecisionID,
              let receipt = archive.adaptiveItemReceipts?[decisionID], receipt.isSupported,
              receipt.slotID == envelope.checkpoint.slotID, receipt.attemptID == envelope.checkpoint.attemptID,
              receipt.ownerDeviceID == ownerDeviceID, receipt.sessionID == envelope.id,
              let selected = receipt.editorialDecision, selected.isSupported,
              let admission = editorialAdmissions.entry(exercise: exercise, pin: pin), admission == selected.admission,
              envelope.checkpoint.pendingOutcome == "answer", envelope.checkpoint.phase == .confidence,
              envelope.checkpoint.committedAttemptID == nil,
              let slot = archive.selectionLedger?.slots[envelope.checkpoint.slotID.uuidString], slot.status == .presented,
              slot.snapshotDigest == admission.exerciseDigest else { return nil }
        let revealed = archive.selectionLedger?.slots.values.contains {
            $0.id != slot.id && $0.semanticID == admission.demand.semanticFingerprint
                && ($0.status == .answered || $0.status == .revealed)
        } ?? false
        return .init(version: NFEditorialNativeProtocol.version, decisionID: decisionID,
            ownerDeviceID: ownerDeviceID, admission: admission, catalogVersion: editorialAdmissions.version,
            catalogDigest: editorialAdmissions.fingerprint, presentedSlotID: slot.id, responseLockedBeforeFeedback: true,
            inAppAssistanceKnown: true, previouslyRevealedSemantic: revealed, reviewAssignment: selected.reviewAssignment)
    }

    private func editorialInput(records: [NFImmutableAttemptRecordSnapshot], day: NFEditorialCapturedDay,
                                at date: Date, quarantinedItemIDs: Set<String>, profileID: UUID? = nil)
        throws -> NFEditorialLiveController.Input {
        let grouped = Dictionary(grouping: records, by: \.id)
        var observations: [NFEditorialObservation] = []
        var validity = NFEditorialValidityProjection()
        for id in grouped.keys.sorted(by: { $0.uuidString < $1.uuidString }) {
            guard let copies = grouped[id], let record = copies.first,
                  record.submittedAt <= date,
                  copies.allSatisfy({ $0 == record }), let snapshot = editorialSnapshot(for: id),
                  let capture = snapshot.editorialCapture, profileID == nil || capture.profileID == profileID else { continue }
            let projected = NFEditorialCommitCapturePolicy.project(snapshot: snapshot, record: record,
                effectiveCredit: record.deterministicCredit, excluded: false, admissions: editorialAdmissions,
                localAuthorityVerified: hasEditorialAuthority(for: capture))
            guard let observation = projected.observation else { continue }
            observations.append(observation)
            let disposition = (archive.evidenceDispositions ?? []).filter { UUID(uuidString: $0.attemptID) == id }
                .max { $0.revision < $1.revision }
            let excluded = quarantinedItemIDs.contains(record.itemID)
                || archive.attemptConflicts?.contains { $0.attemptID == id } == true
                || archive.withheldProtectedConflictAttemptIDs?.contains(id) == true
                || archive.unavailableHistorySnapshots?.contains { $0.attemptID == id && $0.reason == .protectedContent } == true
                || (disposition.map { $0.disposition != .legacyPracticeHistory && $0.disposition != .editorialEvidence } ?? false)
            let corrections = (archive.contentCorrections ?? []).filter { correction in
                UUID(uuidString: correction.originalAttemptID) == id && correction.policyVersion == NFContentCorrectionPolicy.historicalPolicyVersion
                    && (archive.activeContentCorrectionIDs?[id.uuidString].map { $0.contains(correction.id) } ?? true)
            }
            let scopes = Set(corrections.flatMap(\.excludedScopes))
            if excluded || !scopes.isDisjoint(with: [.bandEvidence, .proficiency, .independentEvidence, .accuracy]) {
                validity.dispositionByObservationID[id.uuidString] = .invalid
            }
            if let credit = disposition?.correctedDerivedCredit {
                validity.correctedScoreByObservationID[id.uuidString] = .init(credit: credit,
                    isFullCredit: credit == 1, isZeroCredit: credit == 0,
                    correctionID: disposition?.id ?? "", explanation: "Current appended score disposition")
            }
        }
        guard observations.count <= 4_096 else { throw RepositoryError.oversized }
        observations.sort(by: EditorialBandEvidenceV1.stableOrder)
        validity.revision = try NFEditorialCanonicalData.digest(validity)
        return .init(observations: observations, validity: validity, day: day)
    }

    private func reviewedSelection(request: SessionRequest, previous: NFLocalSessionEnvelope?, operation: NFReservationOperation,
                                   rotation: NFOfflineQuestionRotation, source: NFOfflineQuestionRotationLedger?,
                                   quarantined: Set<String>, records: [NFImmutableAttemptRecordSnapshot],
                                   day: NFEditorialCapturedDay, at date: Date,
                                   overrideCommand suppliedCommand: NFEditorialOverrideCommand? = nil)
        throws -> (proposal: NFOfflineQuestionRotationProposal, exercise: NFExercise, decision: NFEditorialControllerDecision, mixed: NFEditorialMixedDecision?) {
        guard let delivery = request.ordinaryDelivery, let pin = delivery.editorialPolicy,
              pin.isSupported, pin.catalogVersion == editorialAdmissions.version,
              pin.catalogDigest == editorialAdmissions.fingerprint, day.isSupported, day.boundaryStart <= date, date < day.nextBoundary else { throw RepositoryError.unsupportedVersion }
        if pin.usesGoalRanking {
            guard editorialAdmissions.goalAlignmentsAreConsistent, let preferences = pin.goalPreferences,
                  preferences.isSupported, preferences.profileID == delivery.profileID else { throw RepositoryError.unsupportedVersion }
        }
        let effectiveTiming = previous?.checkpoint.timingConditionOverride ?? request.timingCondition
        guard effectiveTiming?.isSupported == true else { throw RepositoryError.unsupportedVersion }
        let previousDecision = previous?.checkpoint.ordinaryReservationDecisionID
            .flatMap { archive.adaptiveItemReceipts?[$0]?.editorialDecision }
        guard previous == nil || previousDecision != nil else { throw RepositoryError.corruptSnapshot }
        let command = suppliedCommand ?? (operation == .next ? previous.flatMap { pendingEditorialOverride(for: $0.checkpoint.slotID) } : nil)
        if let command {
            guard let previous, permitsEditorialControls(previous), command.ownerDeviceID == ownerDeviceID,
                  command.sessionID == request.id, command.slotID == previous.checkpoint.slotID,
                  command.boundary == (operation == .replace ? .replaceCurrent : .nextQuestion),
                  command.isSupported else { throw RepositoryError.staleRevision }
            if command.boundary == .replaceCurrent {
                let reproduced = try makeEditorialOverride(.init(id: command.id, action: command.action),
                    boundary: .replaceCurrent, previous: previous, at: command.createdAt)
                guard reproduced == command else { throw RepositoryError.staleRevision }
            }
        }
        let excluded = (previous?.checkpoint.semanticExclusions ?? []).union(request.repairSemanticExclusions ?? [])
        let positions = try rotation.availablePositions(profileID: delivery.profileID, lab: request.lab,
            laneID: delivery.laneID, bank: NFOfflineQuestionBank.rotationBank, loadedLedger: source)
        let allowed = Set(editorialAdmissions.entries.filter { $0.lab == request.lab
            && $0.contentLocale == request.localeIdentifier && pin.contains(objectiveID: $0.demand.objectiveID, familyID: $0.demand.familyID) }.map(\.bankQuestionID))
        let input = try editorialInput(records: records, day: day, at: date, quarantinedItemIDs: quarantined,
            profileID: pin.usesDemonstratedInitialTarget ? delivery.profileID : nil)
        let evidence = EditorialBandEvidenceV1.reduce(input.observations,
            decisionDayOrdinal: day.ordinal, validity: input.validity)
        let demonstratedPrerequisites = Set(evidence.summaries.filter { $0.lastDemonstratedAt != nil }.map { $0.group.objectiveID })
        var candidates: [NFEditorialSelectionCandidate] = []
        var admissions: [String: NFEditorialAdmissionEntry] = [:]
        var exercises: [String: NFExercise] = [:]
        var initialContracts: [NFEditorialInitialTargetContract] = []
        var criterionContracts: [String: NFEditorialCriterionSelection] = [:]
        var reviewContracts: [String: NFEditorialReviewAssignment] = [:]
        var reviewBudgetDurations: [Double] = []
        var goalSelections: [String: NFEditorialGoalSelection] = [:]
        let availableIDs = Set(positions.map(\.questionID))
        // V1 retains its original available-position traversal. V2 additionally
        // authenticates consumed contracts for initial-demand compatibility;
        // inventory depletion is not loss of a demonstrated band.
        let inspectedIDs = pin.usesDemonstratedInitialTarget ? allowed.sorted()
            : positions.filter { allowed.contains($0.questionID) }.map(\.questionID)
        for questionID in inspectedIDs {
            guard let ordinal = NFOfflineQuestionBank.ordinal(forQuestionID: questionID, lab: request.lab) else { continue }
            let exact = NFDeterministicSessionExerciseFactory.makeExercise(
                // V2 authenticates the complete compatible catalog before
                // candidate filtering. Quarantine cannot erase this contract
                // proof or silently lower a still-valid historical target.
                request: request.launchOnly(offlineQuestionOrdinals: [ordinal],
                    omittingQuarantineForCatalogInspection: pin.usesDemonstratedInitialTarget), index: 0,
                assessmentDescriptor: nil, excludingContentFingerprints: pin.usesDemonstratedInitialTarget ? [] : excluded)
            guard let exactEntry = editorialAdmissions.entry(exercise: exact, pin: pin),
                  exactEntry.bankQuestionID == questionID else { continue }
            if pin.usesDemonstratedInitialTarget { initialContracts.append(.make(exercise: exact, admission: exactEntry)) }
            if pin.usesDeclaredReviewSlots, let review = NFEditorialReviewSlotPolicy.contract(exercise: exact, admission: exactEntry,
                timing: previous?.checkpoint.timingConditionOverride?.mode ?? request.timingCondition?.mode, day: day.ordinal) {
                reviewBudgetDurations.append(review.expectedSeconds)
            }
            guard availableIDs.contains(questionID) else { continue }
            let exercise = pin.usesDemonstratedInitialTarget && !excluded.isEmpty
                ? NFDeterministicSessionExerciseFactory.makeExercise(
                    request: request.launchOnly(offlineQuestionOrdinals: [ordinal]), index: 0,
                    assessmentDescriptor: nil, excludingContentFingerprints: excluded) : exact
            guard !quarantined.contains(exercise.id),
                  let entry = editorialAdmissions.entry(exercise: exercise, pin: pin), entry.bankQuestionID == questionID,
                  effectiveTiming?.accepts(exercise, reviewedDemand: entry.demand) != false else { continue }
            if pin.usesObservedCriterionRanking {
                guard let contract = NFEditorialCriterionRankingPolicy.contract(exercise: exercise, admission: entry,
                    timing: effectiveTiming?.mode) else { continue }
                criterionContracts[questionID] = contract
            }
            if pin.usesDeclaredReviewSlots, entry.demand.reviewContract != nil {
                guard let review = NFEditorialReviewSlotPolicy.contract(exercise: exercise, admission: entry,
                    timing: previous?.checkpoint.timingConditionOverride?.mode ?? request.timingCondition?.mode,
                    day: day.ordinal) else { continue }
                reviewContracts[questionID] = review
            }
            if pin.usesGoalRanking {
                guard let preferences = pin.goalPreferences,
                      let goal = NFEditorialGoalRankingPolicy.selection(admission: entry, preferences: preferences) else { continue }
                goalSelections[questionID] = goal
            }
            let seen = archive.selectionLedger?.slots.values.contains {
                $0.semanticID == entry.demand.semanticFingerprint && $0.status != .reserved
            } ?? false
            candidates.append(.init(id: questionID, item: entry.demand,
                prerequisitesMet: Set(entry.demand.prerequisiteObjectiveIDs).isSubset(of: demonstratedPrerequisites),
                previouslyExposed: seen))
            admissions[questionID] = entry; exercises[questionID] = exercise
        }
        let criterionSelections = pin.usesObservedCriterionRanking
            ? NFEditorialCriterionRankingPolicy.project(contracts: criterionContracts, observations: input.observations,
                evidence: evidence, validity: input.validity) : nil
        let reviewAssignments = pin.usesDeclaredReviewSlots
            ? try reviewedSlotAssignments(request: request, previous: previous, operation: operation,
                contracts: reviewContracts, input: input, evidence: evidence,
                sessionBudgetSeconds: request.requestedMinutes.map { Double($0) * 60 }
                    ?? Double(request.requestedItemCount ?? 5) * (reviewBudgetDurations.min() ?? 0)) : nil
        for index in candidates.indices {
            let id = candidates[index].id
            candidates[index].observedWeakCriterionMatch = criterionSelections?[id]?.preference ?? 0
            candidates[index].goalRelevance = pin.usesGoalRanking ? (goalSelections[id]?.preference ?? 0) : 0
            if pin.usesDeclaredReviewSlots {
                candidates[index].dueRepairPriority = reviewAssignments?[id]?.priority ?? 0
                if candidates[index].item.reviewContract != nil {
                    candidates[index].reviewContractCompatible = reviewAssignments?[id]?.isSupported == true
                }
                if let intent = pin.reviewIntent {
                    candidates[index].reviewContractCompatible = reviewAssignments?[id]?.role == intent.role
                        && reviewAssignments?[id]?.originObservationID == intent.originObservationID
                }
            }
        }
        let committedID = operation == .next ? previous?.checkpoint.committedAttemptID?.uuidString : nil
        let consumed = previous.map { archive.selectionLedger?.runs[$0.id.uuidString]?.slotIDs ?? [] } ?? []
        let semantics = Set(consumed.compactMap { archive.selectionLedger?.slots[$0]?.semanticID })
        let recent = input.observations.filter { $0.lane == .practice }.suffix(100)
        let remaining = request.requestedItemCount != nil ? NFSessionDurationPolicy.maximumSeconds
            : max(0, Double(request.requestedMinutes ?? 0) * 60 - (previous?.checkpoint.sittingActiveDuration ?? 0))
        let supportPresentation: NFEditorialSupportPresentation? = previous.flatMap { prior in
            let id = prior.checkpoint.slotID.uuidString
            guard archive.selectionLedger?.exposures.values.contains(where: { $0.slotID == id }) == true else { return nil }
            return .init(slotID: id, usedSupport: (operation == .replace && (command == nil || command?.action == .easier))
                || prior.checkpoint.capturedSupportCount > 0 || prior.checkpoint.solutionRevealed)
        }
        let context = NFEditorialSelectionContext(catalogVersion: pin.catalogVersion,
            profilePseudonymousID: delivery.profileID.uuidString, remainingSittingSeconds: remaining,
            mixedPractice: false, recentFamilyIDs: recent.compactMap { $0.item?.familyID },
            recentStructureIDs: recent.compactMap { $0.item?.structureID }, sessionSemanticIDs: semantics,
            initialTargetContracts: pin.usesDemonstratedInitialTarget ? initialContracts : nil,
            criterionSelections: criterionSelections, reviewAssignments: reviewAssignments,
            goalSelections: pin.usesGoalRanking ? goalSelections : nil)
        let decision: NFEditorialControllerDecision
        let mixed: NFEditorialMixedDecision?
        if pin.isMixed {
            let selected = try mixedReviewedDecision(request: request, previous: previous, operation: operation,
                input: input, candidates: candidates, admissions: admissions, context: context,
                support: supportPresentation, command: command, at: date)
            decision = selected.decision; mixed = selected.mixed
        } else {
        guard let singleDecision = try NFEditorialLiveController.decide(pin: pin, sessionID: request.id.uuidString,
            previous: previousDecision, committedID: committedID, input: input,
            candidates: candidates,
            supportPresentation: supportPresentation, overrideCommand: command,
            admissions: admissions, context: context),
              exercises[singleDecision.selection.candidateID] != nil else {
            if let command, let previousDecision {
                let feasible = NFEditorialPracticePolicy.feasibleCandidates(candidates,
                    control: previousDecision.controlAfter, context: context, validity: input.validity)
                throw NFEditorialOverrideError.unavailable(command.targetBand,
                    availableBands: Set(feasible.map { $0.item.editorialBand }).sorted())
            }
            throw RepositoryError.unavailableLaunch
        }
            decision = singleDecision; mixed = nil
        }
        guard let exercise = exercises[decision.selection.candidateID] else { throw RepositoryError.corruptSnapshot }
        if previous == nil, pin.catalogScope != nil {
            let feasible = NFEditorialPracticePolicy.feasibleCandidates(candidates, control: decision.controlBefore,
                context: context, validity: input.validity).filter { $0.item.editorialBand == decision.selection.deliveredBand }
            guard Set(feasible.map { $0.item.semanticFingerprint }).count >= (request.requestedItemCount ?? 5) else {
                throw NFEditorialOverrideError.unavailable(decision.selection.deliveredBand, availableBands: [])
            }
        }
        let proposal = try rotation.prepareReservation(profileID: delivery.profileID, lab: request.lab,
            laneID: delivery.laneID, itemCount: 1, bank: NFOfflineQuestionBank.rotationBank,
            loadedLedger: source, isEligible: { $0.questionID == decision.selection.candidateID })
        return (proposal, exercise, decision, mixed)
    }
}


/// A capability for one process-local writer generation. It is deliberately
/// not Codable and cannot be imported or resurrected from a saved command.
struct NFLocalWriterAuthority: Equatable, Sendable {
    fileprivate let repositoryIdentity: UUID
    fileprivate let writerID: UUID
    fileprivate let sessionID: UUID
    fileprivate let generation: UUID
}

struct NFEditorialOverrideIntent: Equatable, Sendable {
    let id: UUID
    let action: NFEditorialOverrideAction
    var writerAuthority: NFLocalWriterAuthority? = nil
}

extension NFLocalSessionRepository {
    private func permitsEditorialControls(_ run: NFLocalSessionEnvelope) -> Bool {
        guard run.request.assessmentBlock == nil, run.request.evidenceClass == .practice,
              run.checkpoint.exercise?.assessmentProtected == false,
              run.checkpoint.exercise?.evidenceClass == .practice,
              run.checkpoint.exercise?.provenance.sourceDocumentIDs.isEmpty == true,
              run.checkpoint.descriptor == nil, run.checkpoint.protectedCommitReceipt == nil else { return false }
        let slots = archive.selectionLedger?.runs[run.id.uuidString]?.slotIDs ?? []
        let attempts = Set(slots.compactMap { archive.selectionLedger?.slots[$0]?.attemptID }.compactMap { UUID(uuidString: $0) })
            .union([run.checkpoint.attemptID])
        let protected = Set(archive.withheldProtectedConflictAttemptIDs ?? [])
            .union((archive.unavailableHistorySnapshots ?? []).filter { $0.reason == .protectedContent }.map(\.attemptID))
            .union((archive.attemptConflicts ?? []).filter(\.containsProtectedContent).map(\.attemptID))
        return attempts.isDisjoint(with: protected)
    }

    private func pendingEditorialOverride(for slotID: UUID) -> NFEditorialOverrideCommand? {
        let commands = (archive.editorialOverrideCommands ?? [:]).values.filter { $0.slotID == slotID }
        let superseded = Set(commands.compactMap(\.predecessorCommandID))
        return commands.first { !superseded.contains($0.id) }
    }

    private func makeEditorialOverride(_ intent: NFEditorialOverrideIntent, boundary: NFEditorialOverrideBoundary,
                                       previous: NFLocalSessionEnvelope?, at date: Date) throws -> NFEditorialOverrideCommand {
        guard let previous, previous.ownerDeviceID == ownerDeviceID, previous.status == .suspended,
              permitsEditorialControls(previous),
              let pin = previous.request.ordinaryDelivery?.editorialPolicy,
              pin.isSupported, pin.catalogVersion == editorialAdmissions.version,
              pin.catalogDigest == editorialAdmissions.fingerprint,
              let decisionID = previous.checkpoint.ordinaryReservationDecisionID,
              let decision = archive.adaptiveItemReceipts?[decisionID]?.editorialDecision, decision.isSupported,
              previous.checkpoint.exercise?.assessmentProtected == false,
              previous.checkpoint.protectedCommitReceipt == nil,
              date.timeIntervalSinceReferenceDate.isFinite else { throw NFEditorialOverrideError.unsupported }
        guard previous.checkpoint.phase == .item || previous.checkpoint.phase == .feedback,
              previous.checkpoint.pendingOutcome == nil,
              previous.checkpoint.phase != .feedback || previous.checkpoint.committedAttemptID == previous.checkpoint.attemptID
              else { throw RepositoryError.staleRevision }
        if boundary == .replaceCurrent {
            guard previous.checkpoint.phase == .item, previous.checkpoint.committedAttemptID == nil,
                  previous.checkpoint.result == nil else { throw RepositoryError.staleRevision }
        } else if previous.checkpoint.index + 1 >= previous.checkpoint.itemCount { throw NFEditorialOverrideError.noRemainingQuestion }
        let target = try intent.action.target(deliveredBand: decision.selection.deliveredBand,
            targetBand: decision.controlAfter.currentTargetBand)
        let priorCommand = pendingEditorialOverride(for: previous.checkpoint.slotID)
        return .init(id: intent.id, sessionID: previous.id, ownerDeviceID: ownerDeviceID,
            slotID: previous.checkpoint.slotID, objectiveID: decision.controlAfter.objectiveID, familyID: decision.controlAfter.familyID,
            controlDigest: try NFEditorialCanonicalData.digest(decision.controlAfter), action: intent.action,
            boundary: boundary, targetBand: target, predecessorCommandID: priorCommand?.id,
            createdAt: max(date, priorCommand?.createdAt ?? date))
    }

    /// Preference acceptance consumes no content and rewrites no current receipt.
    /// The later Next publication rechecks current evidence, availability and CAS.
    func setEditorialNextQuestion(_ intent: NFEditorialOverrideIntent, request: SessionRequest,
                                 predecessor: NFLocalItemCheckpoint, rotation: NFOfflineQuestionRotation,
                                 quarantinedItemIDs: Set<String>, records: [NFImmutableAttemptRecordSnapshot],
                                 day: NFEditorialCapturedDay, at date: Date) throws -> NFEditorialOverrideCommand {
        try withPublicationLock {
            guard acceptsWriterAuthority(intent.writerAuthority, sessionID: request.id) else {
                throw NFEditorialOverrideError.staleOwner
            }
            guard try diskRevision() == (archive.transactionRevision ?? 0) else { throw RepositoryError.staleRevision }
            if let prior = archive.editorialOverrideCommands?[intent.id.uuidString] {
                guard prior.sessionID == request.id, prior.slotID == predecessor.slotID,
                      prior.action == intent.action, prior.boundary == .nextQuestion,
                      prior.ownerDeviceID == ownerDeviceID, prior.isSupported else { throw RepositoryError.conflictingAttempt }
                return prior
            }
            guard (archive.editorialOverrideCommands?.count ?? 0) < 4_096 else { throw RepositoryError.oversized }
            guard let run = archive.sessions.first(where: { $0.id == request.id }), run.checkpoint == predecessor,
                  try NFLocalReservationBridge.configurationDigest(request) == NFLocalReservationBridge.configurationDigest(run.request),
                  archive.selectionLedger?.exposures.values.contains(where: { $0.slotID == predecessor.slotID.uuidString }) == true else {
                throw RepositoryError.staleRevision
            }
            let command = try makeEditorialOverride(intent, boundary: .nextQuestion, previous: run, at: date)
            do {
                _ = try reviewedSelection(request: run.request, previous: run, operation: .next,
                    rotation: rotation, source: archive.offlineRotationLedger,
                    quarantined: quarantinedItemIDs.union(request.quarantinedItemIDs), records: records,
                    day: day, at: date, overrideCommand: command)
            } catch RepositoryError.unavailableLaunch { throw NFEditorialOverrideError.unavailable(command.targetBand, availableBands: []) }
            var next = archive
            if next.editorialOverrideCommands == nil { next.editorialOverrideCommands = [:] }
            next.editorialOverrideCommands?[command.id.uuidString] = command
            next = try Self.validatedArchive(next)
            try replaceUnlocked(next)
            return command
        }
    }

    func canStartSeparateReviewedActivity(sessionID: UUID) -> Bool {
        guard !editorialAdmissions.entries.isEmpty,
              let run = archive.sessions.first(where: { $0.id == sessionID }),
              run.ownerDeviceID == ownerDeviceID, run.status == .suspended,
              run.request.ordinaryDelivery?.strategy == .fixedBlock,
              permitsEditorialControls(run), run.checkpoint.pendingOutcome == nil,
              run.checkpoint.phase == .item || run.checkpoint.phase == .feedback,
              run.checkpoint.itemCount - run.checkpoint.index - (run.checkpoint.committedAttemptID == nil ? 0 : 1) > 0 else { return false }
        return editorialAdmissions.entries.contains { $0.isSupported && $0.lab == run.request.lab
            && $0.contentLocale == run.request.localeIdentifier }
    }

    func reviewedStartingBands(sessionID: UUID) -> [NFEditorialBand] {
        guard canStartSeparateReviewedActivity(sessionID: sessionID),
              let run = archive.sessions.first(where: { $0.id == sessionID }) else { return [] }
        return Set(editorialAdmissions.entries.filter { $0.isSupported && $0.lab == run.request.lab
            && $0.contentLocale == run.request.localeIdentifier }.map { $0.demand.editorialBand }).sorted()
    }

    func editorialChallengePresentation(sessionID: UUID) -> NFEditorialChallengePresentation? {
        guard let run = archive.sessions.first(where: { $0.id == sessionID }), run.ownerDeviceID == ownerDeviceID,
              run.status != .migrationRecovery, permitsEditorialControls(run), let pin = run.request.ordinaryDelivery?.editorialPolicy,
              pin.isSupported, pin.catalogVersion == editorialAdmissions.version, pin.catalogDigest == editorialAdmissions.fingerprint,
              let id = run.checkpoint.ordinaryReservationDecisionID,
              let decision = archive.adaptiveItemReceipts?[id]?.editorialDecision, decision.isSupported else { return nil }
        let pending = pendingEditorialOverride(for: run.checkpoint.slotID)
        let mixed = archive.adaptiveItemReceipts?[id]?.mixedDecision
        let bands = Set(editorialAdmissions.entries.filter { $0.isSupported && $0.lab == run.request.lab
            && $0.contentLocale == run.request.localeIdentifier && $0.demand.objectiveID == decision.controlAfter.objectiveID
            && $0.demand.familyID == decision.controlAfter.familyID }.map { $0.demand.editorialBand }).sorted()
        // These are catalog bands, not a promise of unseen feasible supply.
        // The acceptance path checks prerequisites, exposure, timing and reports.
        return .init(deliveredBand: decision.selection.deliveredBand, targetBand: decision.controlAfter.currentTargetBand,
            mode: decision.controlAfter.challengeMode,
            reason: decision.selection.reason == .continueCurrentChallenge && decision.controlBefore.decisionOrdinal == 0
                ? decision.initialReason : decision.selection.reason,
            pendingBand: pending?.targetBand,
            pendingChallengeMode: pending.map { $0.action.isFixed ? .fixedBand($0.targetBand) : .adaptive },
            userAction: decision.overrideCommand?.action,
            policyVersion: decision.overrideCommand?.policyVersion ?? decision.controllerVersion,
            decisionID: id, objectiveID: decision.controlAfter.objectiveID, familyID: decision.controlAfter.familyID,
            shouldOfferSupport: mixed.map { $0.stateAfter.recentSupportPresentations.filter(\.usedSupport).count >= 2 } ?? decision.controlAfter.shouldOfferSupport,
            reviewedCatalogBands: bands,
            reasoningSteps: decision.admission.demand.demandVector.reasoningSteps,
            mixedFamilyTitle: pin.isMixed ? run.checkpoint.exercise?.title : nil,
            mixedFeasibleFamilyCount: mixed?.feasibleFamilyKeys.count,
            varietyUnavailableReasons: mixed?.unmetVarietyPreferences ?? [])
    }
}


extension NFLocalSessionRepository {
    private struct MixedExposureFact: Codable {
        let slotID: String
        let eventID: String
        let sessionID: String
        let pathOrdinal: Int
        let occurredAt: Date
        let scope: NFEditorialFamilyScope
        let semanticID: String
        let structureID: String
        let representationIDs: [String]
    }
    private func mixedHistory(sessionID: UUID, profileID: UUID, at date: Date) throws
        -> (summary: NFEditorialMixedHistory, recent: [MixedExposureFact]) {
        let eligibleRuns = Set(archive.sessions.filter { $0.ownerDeviceID == ownerDeviceID
            && $0.request.ordinaryDelivery?.profileID == profileID
            && $0.request.ordinaryDelivery?.editorialPolicy?.isMixed == true && permitsEditorialControls($0) }.map { $0.id.uuidString })
        let bySlot = Dictionary((archive.adaptiveItemReceipts ?? [:]).values.map { ($0.slotID.uuidString, $0) }, uniquingKeysWith: { first, _ in first })
        var firstExposures: [String: NFReservationExposure] = [:]
        for event in (archive.selectionLedger?.exposures ?? [:]).values where eligibleRuns.contains(event.runID) && event.occurredAt <= date {
            if let prior = firstExposures[event.slotID], prior.occurredAt < event.occurredAt
                || (prior.occurredAt == event.occurredAt && prior.eventID < event.eventID) { continue }
            firstExposures[event.slotID] = event
        }
        let facts = firstExposures.values.compactMap { event -> MixedExposureFact? in
            guard let receipt = bySlot[event.slotID], receipt.mixedDecision?.isSupported == true,
                  let decision = receipt.editorialDecision, decision.isSupported else { return nil }
            let demand = decision.admission.demand
            return .init(slotID: event.slotID, eventID: event.eventID, sessionID: event.runID,
                pathOrdinal: archive.selectionLedger?.slots[event.slotID]?.pathOrdinal ?? 0,
                occurredAt: event.occurredAt, scope: NFEditorialMixedController.scope(of: decision),
                semanticID: demand.semanticFingerprint, structureID: demand.structureID,
                representationIDs: Set(demand.representationIDs).sorted())
        }.sorted { $0.occurredAt == $1.occurredAt ? $0.eventID < $1.eventID : $0.occurredAt < $1.occurredAt }
        // The next displayed slot would complete the prospective 100-item window.
        let recent = Array(facts.suffix(99)), session = facts.filter { $0.sessionID == sessionID.uuidString }.sorted { $0.pathOrdinal < $1.pathOrdinal }
        guard session.count <= 4_096 else { throw RepositoryError.oversized }
        func counts(_ values: [String]) -> [String: Int] { values.reduce(into: [:]) { $0[$1, default: 0] += 1 } }
        let last = session.last?.scope.key
        let run = last.map { key in session.reversed().prefix { $0.scope.key == key }.count } ?? 0
        let summary = NFEditorialMixedHistory(exposureDigest: try NFEditorialCanonicalData.digest(recent + session),
            recentCount: recent.count, recentSemanticCount: Set(recent.map(\.semanticID)).count,
            recentFamilyCounts: counts(recent.map { $0.scope.key }), recentStructureCounts: counts(recent.map(\.structureID)),
            recentRepresentationCounts: counts(recent.flatMap(\.representationIDs)),
            sessionCount: session.count, sessionSemanticCount: Set(session.map(\.semanticID)).count,
            sessionFamilyCounts: counts(session.map { $0.scope.key }), sessionStructureCounts: counts(session.map(\.structureID)),
            sessionRepresentationCounts: counts(session.flatMap(\.representationIDs)), previousFamilyKey: last, previousFamilyRunCount: run)
        return (summary, recent)
    }

    private func mixedReviewedDecision(request: SessionRequest, previous: NFLocalSessionEnvelope?, operation: NFReservationOperation,
                                       input: NFEditorialLiveController.Input, candidates: [NFEditorialSelectionCandidate],
                                       admissions: [String: NFEditorialAdmissionEntry], context originalContext: NFEditorialSelectionContext,
                                       support: NFEditorialSupportPresentation?, command: NFEditorialOverrideCommand?, at date: Date)
        throws -> (decision: NFEditorialControllerDecision, mixed: NFEditorialMixedDecision) {
        guard let delivery = request.ordinaryDelivery, let pin = delivery.editorialPolicy, pin.isSupported, pin.isMixed else {
            throw RepositoryError.unsupportedVersion
        }
        let previousReceipt = previous?.checkpoint.ordinaryReservationDecisionID.flatMap { archive.adaptiveItemReceipts?[$0] }
        guard previous == nil || previousReceipt?.mixedDecision?.isSupported == true else { throw RepositoryError.corruptSnapshot }
        let before = previousReceipt?.mixedDecision?.stateAfter ?? .init()
        let outgoing: NFEditorialMixedPendingEvent? = previousReceipt.flatMap { receipt in
            guard let decision = receipt.editorialDecision else { return nil }
            return .init(scope: NFEditorialMixedController.scope(of: decision), decisionID: receipt.decisionID,
                slotID: receipt.slotID.uuidString,
                committedAttemptID: operation == .next ? previous?.checkpoint.committedAttemptID?.uuidString : nil,
                support: support)
        }
        let pending = try NFEditorialMixedController.applying(outgoing, to: before)
        let history = try mixedHistory(sessionID: request.id, profileID: delivery.profileID, at: date)
        var context = originalContext
        context.recentFamilyIDs = history.recent.map { $0.scope.familyID }
        context.recentStructureIDs = history.recent.map(\.structureID)
        let ordinal = archive.selectionLedger?.runs[request.id.uuidString]?.nextDecisionOrdinal ?? 0
        let decisionID = NFSelectionReservationPolicy.decisionID(runID: request.id.uuidString, ordinal: ordinal)
        let forced = command.map { NFEditorialFamilyScope(objectiveID: $0.objectiveID, familyID: $0.familyID).key }
        // Replace is an explicit same-family alternative, even without a band
        // command. Ordinary Next may move to another eligible family.
        let selectedFamily = forced ?? (operation == .replace ? previousReceipt?.mixedDecision?.selectedScope.key : nil)
        var decisions: [String: NFEditorialControllerDecision] = [:]
        for scope in pin.scopes {
            let familyPrevious = before.lastDecisionByFamily[scope.key].flatMap { archive.adaptiveItemReceipts?[$0]?.editorialDecision }
            guard before.lastDecisionByFamily[scope.key] == nil || familyPrevious?.isSupported == true else { throw RepositoryError.corruptSnapshot }
            let event = pending.pendingByFamily[scope.key]
            let next = try NFEditorialLiveController.decide(pin: pin.singleFamily(scope), sessionID: request.id.uuidString,
                previous: familyPrevious, committedID: event?.committedAttemptID, input: input, candidates: candidates,
                supportPresentation: event?.support, overrideCommand: forced == scope.key ? command : nil,
                admissions: admissions, context: context)
            if let next { decisions[scope.key] = next }
        }
        guard let mixed = try NFEditorialMixedController.select(decisions: decisions,
            candidates: Dictionary(candidates.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first }),
            feasibleFamilyKeys: decisions.keys.sorted(), pin: pin, sessionID: request.id.uuidString,
            profileID: delivery.profileID.uuidString, ordinal: ordinal, decisionID: decisionID,
            before: before, outgoing: outgoing, history: history.summary, explicitlySelectedFamily: selectedFamily),
              let selected = decisions[mixed.selectedScope.key] else {
            if let command, let previousDecision = previousReceipt?.editorialDecision {
                let feasible = NFEditorialPracticePolicy.feasibleCandidates(candidates, control: previousDecision.controlAfter,
                    context: context, validity: input.validity)
                throw NFEditorialOverrideError.unavailable(command.targetBand, availableBands: Set(feasible.map { $0.item.editorialBand }).sorted())
            }
            throw RepositoryError.unavailableLaunch
        }
        return (selected, mixed)
    }

    nonisolated private static func validateMixedDecision(_ receipt: NFLocalAdaptiveItemReceipt, archive: Archive) throws {
        guard let mixed = receipt.mixedDecision, mixed.isSupported, let selected = receipt.editorialDecision,
              let run = archive.sessions.first(where: { $0.id == receipt.sessionID }),
              let pin = run.request.ordinaryDelivery?.editorialPolicy, pin.isMixed,
              mixed.globalDecisionOrdinal == receipt.effectiveDecisionOrdinal,
              mixed.policyVersion == pin.controllerVersion,
              selected.controllerVersion == pin.familyControllerVersion,
              mixed.selectedScope == NFEditorialMixedController.scope(of: selected),
              mixed.rankedFamilies.first?.candidateID == selected.selection.candidateID,
              Set(mixed.stateBefore.lastDecisionByFamily.keys).isSubset(of: Set(pin.scopes.map(\.key))),
              Set(mixed.feasibleFamilyKeys).isSubset(of: Set(pin.scopes.map(\.key))) else { throw RepositoryError.corruptSnapshot }
        let prior = receipt.predecessorSlotID.flatMap { slot in archive.adaptiveItemReceipts?.values.first { $0.slotID == slot } }
        guard mixed.stateBefore == (prior?.mixedDecision?.stateAfter ?? .init()) else { throw RepositoryError.corruptSnapshot }
        if let prior, let priorDecision = prior.editorialDecision {
            guard let event = mixed.outgoingEvent, event.decisionID == prior.decisionID,
                  event.slotID == prior.slotID.uuidString, event.scope == NFEditorialMixedController.scope(of: priorDecision),
                  event.committedAttemptID == (archive.selectionLedger?.slots[prior.slotID.uuidString]?.status == .answered ? prior.attemptID.uuidString : nil),
                  event.support.map({ support in support.slotID == event.slotID
                    && archive.selectionLedger?.exposures.values.contains(where: { $0.slotID == event.slotID }) == true }) ?? true else {
                throw RepositoryError.corruptSnapshot
            }
        } else if mixed.outgoingEvent != nil { throw RepositoryError.corruptSnapshot }
        let pending = try NFEditorialMixedController.applying(mixed.outgoingEvent, to: mixed.stateBefore)
        let event = pending.pendingByFamily[mixed.selectedScope.key]
        guard selected.supportPresentation == event?.support else { throw RepositoryError.corruptSnapshot }
        if let id = mixed.stateBefore.lastDecisionByFamily[mixed.selectedScope.key] {
            guard let familyPrior = archive.adaptiveItemReceipts?[id], familyPrior.sessionID == receipt.sessionID,
                  familyPrior.mixedDecision?.selectedScope == mixed.selectedScope,
                  familyPrior.editorialDecision?.controlAfter == selected.controlBefore,
                  familyPrior.editorialDecision?.initialTargetDecision == selected.initialTargetDecision,
                  familyPrior.editorialDecision?.initialReason == selected.initialReason else { throw RepositoryError.corruptSnapshot }
        } else if selected.controlBefore.decisionOrdinal != 0 { throw RepositoryError.corruptSnapshot }
        var expected = pending
        expected.lastDecisionByFamily[mixed.selectedScope.key] = receipt.decisionID
        expected.pendingByFamily.removeValue(forKey: mixed.selectedScope.key)
        guard expected == mixed.stateAfter else { throw RepositoryError.corruptSnapshot }
        for (key, event) in mixed.stateAfter.pendingByFamily {
            guard let source = archive.adaptiveItemReceipts?[event.decisionID], source.sessionID == receipt.sessionID,
                  source.mixedDecision?.selectedScope == event.scope, source.slotID.uuidString == event.slotID,
                  mixed.stateAfter.lastDecisionByFamily[key] == event.decisionID else { throw RepositoryError.corruptSnapshot }
        }
    }
}

extension NFLocalSessionRepository {
    /// One archive replacement performs the reference scan and release together.
    /// There are no detached blob deletions requiring a separate tombstone. A
    /// failed transaction leaves every original payload in place for later retry.
    @discardableResult
    func compactGeneratedTerminalInventory() throws -> Int {
        var next = archive
        var count = 0
        for index in (next.privateStudyRuns ?? []).indices {
            guard let record = next.privateStudyRuns?[index], record.id != NFPrivateStudyMetadata.recordID,
                  writerSessionID != record.id,
                  let draft = try? JSONDecoder().decode(NFGeneratedPracticeDraft.self, from: record.payload),
                  draft.id == record.id, draft.ownerDeviceID == ownerDeviceID,
                  draft.result.provenance.requestID == record.generationID,
                  draft.valid, draft.stage == 3, draft.terminalState != nil,
                  draft.terminalInventory == nil else { continue }
            guard var compact = try? draft.releasingUnneededTerminalInventory() else { continue }
            if var state = compact.runState {
                guard state.revision < Int.max else { continue }
                state.revision += 1
                compact.runState = state
            }
            let payload = try JSONEncoder().encode(compact)
            // `updatedAt` is the original study update, not maintenance time.
            next.privateStudyRuns?[index] = .init(id: record.id, generationID: record.generationID,
                payload: payload, updatedAt: record.updatedAt)
            count += 1
        }
        if count > 0 { try replace(next) }
        return count
    }
}

extension NFLocalSessionRepository {
    /// Captures immutable values only. It does not claim a writer, checkpoint,
    /// reserve inventory, acknowledge display, or publish a selection receipt.
    func editorialPrelaunchInput(request: SessionRequest, catalogScope: NFEditorialCatalogScope?,
                                rotation: NFOfflineQuestionRotation, records: [NFImmutableAttemptRecordSnapshot],
                                day: NFEditorialCapturedDay, at date: Date) throws -> NFEditorialPrelaunchInput {
        guard loadError == nil, let delivery = request.ordinaryDelivery, delivery.strategy == .adaptiveItem,
              day.isSupported else { throw RepositoryError.unsupportedVersion }
        let source = try archive.offlineRotationLedger ?? rotation.legacySnapshot()
        let positions = try rotation.availablePositions(profileID: delivery.profileID, lab: request.lab,
            laneID: delivery.laneID, bank: NFOfflineQuestionBank.rotationBank, loadedLedger: source)
        let evidence = try editorialInput(records: records, day: day, at: date, quarantinedItemIDs: request.quarantinedItemIDs,
            profileID: delivery.profileID)
        return .init(request: request, catalogScope: catalogScope, admissions: editorialAdmissions,
            availableBankQuestionIDs: Set(positions.map(\.questionID)),
            exposedSemanticIDs: Set((archive.selectionLedger?.slots ?? [:]).values.filter { $0.status != .reserved }.map(\.semanticID)),
            quarantinedItemIDs: request.quarantinedItemIDs, evidenceInput: evidence, archiveRevision: archive.transactionRevision ?? 0)
    }
}

/// Exhausted or malformed counters retain the original archive for recovery.
/// No authenticated command is permitted to wrap an accepted revision.
enum NFSessionWriterRevision {
    static func next(after previous: Int?) throws -> Int {
        let value = previous ?? 0
        guard value >= 0, value < Int.max else { throw NFLocalSessionRepository.RepositoryError.unsupportedVersion }
        return value + 1
    }
}

/// In-process command authority. It is never serialized into portable history.
/// A command keeps this exact generation through every prepared/receipt write.
struct NFSessionWriterCommand: Equatable, Sendable {
    let sessionID: UUID
    fileprivate let authority: NFLocalWriterAuthority
}

extension NFLocalSessionRepository {
    func sessionCommand(authority: NFLocalWriterAuthority?, sessionID: UUID) throws -> NFSessionWriterCommand {
        guard let authority, isWriter(authority, sessionID: sessionID) else { throw RepositoryError.staleRevision }
        return .init(sessionID: sessionID, authority: authority)
    }

    func validateSessionCommand(_ command: NFSessionWriterCommand, sessionID: UUID) throws {
        guard command.sessionID == sessionID,
              isWriter(command.authority, sessionID: sessionID) else { throw RepositoryError.staleRevision }
    }

    func saveSession(_ envelope: NFLocalSessionEnvelope, command: NFSessionWriterCommand,
                     expectedRevision: Int?) throws {
        try validateSessionCommand(command, sessionID: envelope.id)
        let previous = archive.sessions.first { $0.id == envelope.id }
        guard previous?.revision == expectedRevision,
              envelope.revision == (try NFSessionWriterRevision.next(after: expectedRevision)) else { throw RepositoryError.staleRevision }
        try save(envelope)
    }

    func acknowledgeSessionPresentation(sessionID: UUID, slotID: UUID, at date: Date,
                                        command: NFSessionWriterCommand) throws {
        try validateSessionCommand(command, sessionID: sessionID)
        guard archive.sessions.first(where: { $0.id == sessionID })?.checkpoint.slotID == slotID else {
            throw RepositoryError.staleRevision
        }
        try acknowledgePresentation(sessionID: sessionID, slotID: slotID, at: date)
        try acknowledgeEditorialExplanation(sessionID: sessionID, slotID: slotID, at: date)
    }

    /// Legacy authored drafts have no invented slot ledger. Compare their exact
    /// original payload identity in addition to the captured writer generation.
    func saveLegacyGeneratedSession(_ draft: NFGeneratedPracticeDraft, command: NFSessionWriterCommand,
                                    expectedPayloadDigest: String?) throws {
        try requireArchiveWriteAvailability()
        try validateSessionCommand(command, sessionID: draft.id)
        try replace(Self.legacyGeneratedCandidate(draft, expectedPayloadDigest: expectedPayloadDigest,
            in: archive, ownerDeviceID: ownerDeviceID, at: Date()))
    }

    nonisolated static func legacyGeneratedCandidate(_ draft: NFGeneratedPracticeDraft,
        expectedPayloadDigest: String?, in archive: Archive, ownerDeviceID: UUID, at: Date) throws -> Archive {
        guard draft.runState == nil, draft.valid, draft.ownerDeviceID == ownerDeviceID else { throw RepositoryError.corruptSnapshot }
        let record = archive.privateStudyRuns?.first { $0.id == draft.id }
        guard record.map({ NFReservationSnapshot.digest($0.payload) }) == expectedPayloadDigest else { throw RepositoryError.staleRevision }
        if let record {
            guard let original = try? JSONDecoder().decode(NFGeneratedPracticeDraft.self, from: record.payload),
                  original.valid, original.runState == nil, original.ownerDeviceID == draft.ownerDeviceID,
                  original.result.provenance.requestID == draft.result.provenance.requestID,
                  try draft.preservesAcceptedInventory(from: original),
                  draft.index >= original.index, draft.index <= original.index + 1,
                  draft.index == original.index || original.stage == 2,
                  original.stage != 3 || draft.stage == 3 else { throw RepositoryError.corruptSnapshot }
            if draft.index == original.index {
                guard original.pendingAttemptID == nil || original.pendingAttemptID == draft.pendingAttemptID else { throw RepositoryError.staleRevision }
                if original.stage == 1 || original.stage == 2 {
                    guard original.response == draft.response, original.scoredResponse == draft.scoredResponse,
                          original.confidence == draft.confidence, original.lastScore == draft.lastScore,
                          original.referenceRevealed == draft.referenceRevealed,
                          original.mathWork == draft.mathWork, original.traceInspection == draft.traceInspection,
                          original.dataInspection == draft.dataInspection, original.scienceStudy == draft.scienceStudy,
                          original.transferRelationship == draft.transferRelationship,
                          original.pendingUnscored == draft.pendingUnscored else { throw RepositoryError.conflictingAttempt }
                }
                if original.referenceRevealed, !draft.referenceRevealed { throw RepositoryError.staleRevision }
            }
        }
        return try privateRunCandidate(id: draft.id, generationID: draft.result.provenance.requestID,
            payload: JSONEncoder().encode(draft), in: archive, at: at)
    }

    func saveGeneratedSession(_ draft: NFGeneratedPracticeDraft, command: NFSessionWriterCommand,
                              expectedRevision: Int?) throws {
        try validateSessionCommand(command, sessionID: draft.id)
        guard draft.runState?.revision == (try NFSessionWriterRevision.next(after: expectedRevision)) else { throw RepositoryError.staleRevision }
        try saveGeneratedPracticeDraft(draft, expectedRevision: expectedRevision)
    }
}

extension AppStore {
    /// Session commits are distinct from historical annotation and maintenance.
    /// Receipt storage remains immutable; loss of ownership after a successful
    /// write prevents old-view publication without erasing the saved receipt.
    func withSessionCommand<T>(_ command: NFSessionWriterCommand, sessionID: UUID,
                               perform body: () throws -> T) throws -> T {
        try localSessions.requireArchiveWriteAvailability()
        try localSessions.validateSessionCommand(command, sessionID: sessionID)
        let result = try body()
        try localSessions.validateSessionCommand(command, sessionID: sessionID)
        return result
    }
}


/// Small cross-executor arbitration state. Learner payloads remain in immutable
/// prepared values; no lock is held while encoding or accessing the filesystem.
final class NFLocalArchiveWriteTicket: @unchecked Sendable {
    enum Phase: Equatable, Sendable { case preparing, cancelled, committing, finished }
    let id = UUID()
    let command: NFSessionWriterCommand
    private let lock = NSLock()
    private var phase: Phase = .preparing

    fileprivate init(command: NFSessionWriterCommand) { self.command = command }

    var currentPhase: Phase { lock.withLock { phase } }

    @discardableResult
    func cancelPreparation() -> Bool {
        lock.withLock {
            guard phase == .preparing else { return false }
            phase = .cancelled
            return true
        }
    }

    func checkPreparation() throws {
        try lock.withLock {
            guard phase == .preparing else { throw CancellationError() }
        }
    }

    /// The final cancellable boundary. Once this succeeds the worker completes
    /// the atomic replacement and reports a committed receipt despite cancellation.
    func beginCommit() throws {
        try lock.withLock {
            guard phase == .preparing else { throw CancellationError() }
            phase = .committing
        }
    }

    func finish() { lock.withLock { phase = .finished } }
}

/// Reference-backed immutable commands keep large checkpoint/exercise values
/// out of the operation enum's cooperative-worker stack frame.
final class NFLocalAttemptRetentionInput: Sendable {
    let sessionID: UUID
    let revision: Int
    let predecessor: NFLocalItemCheckpoint
    let snapshot: NFLocalAttemptSnapshot
    init(sessionID: UUID, revision: Int, predecessor: NFLocalItemCheckpoint, snapshot: NFLocalAttemptSnapshot) {
        self.sessionID = sessionID; self.revision = revision
        self.predecessor = predecessor; self.snapshot = snapshot
    }
}

final class NFLocalAttemptConflictInput: Sendable {
    let sessionID: UUID
    let record: NFAttemptConflictJournalEntry
    init(sessionID: UUID, record: NFAttemptConflictJournalEntry) {
        self.sessionID = sessionID; self.record = record
    }
}

enum NFLocalArchiveWriteOperation: Sendable {
    case ordinary(NFLocalSessionEnvelope, expectedRevision: Int?)
    case attemptRetention(NFLocalAttemptRetentionInput)
    case generatedAttempt(NFLocalGeneratedAttemptInput)
    case attemptConflict(NFLocalAttemptConflictInput)
    case generated(NFGeneratedPracticeDraft, expectedRevision: Int?)
    case legacyGenerated(NFGeneratedPracticeDraft, expectedPayloadDigest: String?)

    var sessionID: UUID {
        switch self {
        case .ordinary(let envelope, _): envelope.id
        case .attemptRetention(let input): input.sessionID
        case .generatedAttempt(let input): input.runID
        case .attemptConflict(let input): input.sessionID
        case .generated(let draft, _), .legacyGenerated(let draft, _): draft.id
        }
    }

    func candidate(in original: NFLocalSessionRepository.Archive, ownerDeviceID: UUID,
                   at date: Date) throws -> NFLocalSessionRepository.Archive {
        switch self {
        case .ordinary(let envelope, let expected):
            guard original.sessions.first(where: { $0.id == envelope.id })?.revision == expected,
                  envelope.revision == (try NFSessionWriterRevision.next(after: expected)) else {
                throw NFLocalSessionRepository.RepositoryError.staleRevision
            }
            return try NFLocalSessionRepository.sessionCandidate(envelope, in: original, ownerDeviceID: ownerDeviceID)
        case .generatedAttempt(let input):
            return try NFLocalSessionRepository.generatedAttemptCandidate(input, in: original, ownerDeviceID: ownerDeviceID)
        case .attemptRetention(let input):
            return try NFLocalSessionRepository.attemptRetentionCandidate(input, in: original, ownerDeviceID: ownerDeviceID)
        case .attemptConflict(let input):
            guard input.record.proposed.sessionID == input.sessionID else { throw NFLocalSessionRepository.RepositoryError.staleRevision }
            return try NFLocalSessionRepository.attemptConflictCandidate(input.record, in: original)
        case .generated(let draft, let expected):
            guard draft.runState?.revision == (try NFSessionWriterRevision.next(after: expected)) else {
                throw NFLocalSessionRepository.RepositoryError.staleRevision
            }
            return try NFLocalSessionRepository.generatedCandidate(draft, expectedRevision: expected,
                in: original, ownerDeviceID: ownerDeviceID, at: date)
        case .legacyGenerated(let draft, let digest):
            return try NFLocalSessionRepository.legacyGeneratedCandidate(draft, expectedPayloadDigest: digest,
                in: original, ownerDeviceID: ownerDeviceID, at: date)
        }
    }
}

struct NFLocalArchiveWriteInput: Sendable {
    let ticket: NFLocalArchiveWriteTicket
    let ownerDeviceID: UUID
    let sourceURL: URL?
    let expectedRevision: UInt64
    let expectedOriginalDigest: String?
    let original: NFLocalSessionRepository.Archive
    let operation: NFLocalArchiveWriteOperation
    let capturedAt: Date
    fileprivate init(ticket: NFLocalArchiveWriteTicket, ownerDeviceID: UUID, sourceURL: URL?,
                     expectedRevision: UInt64, expectedOriginalDigest: String?,
                     original: NFLocalSessionRepository.Archive, operation: NFLocalArchiveWriteOperation, capturedAt: Date) {
        self.ticket = ticket; self.ownerDeviceID = ownerDeviceID; self.sourceURL = sourceURL
        self.expectedRevision = expectedRevision; self.expectedOriginalDigest = expectedOriginalDigest
        self.original = original; self.operation = operation; self.capturedAt = capturedAt
    }
}

struct NFLocalArchiveWriteAcknowledgement: Sendable {
    let ticketID: UUID
    let ownerDeviceID: UUID
    let archive: NFLocalSessionRepository.Archive
    let byteDigest: String
    /// Atomic rename succeeded. A later filesystem verification problem cannot
    /// be reported as if the predecessor were still the only committed content.
    let verificationNeeded: Bool
}

enum NFLocalArchiveWriteStage: Equatable, Sendable { case encoding, inputVerified, staged, renamed, committed }

actor NFLocalArchiveWriteWorker {
    static let shared = NFLocalArchiveWriteWorker()

    fileprivate func commit(_ input: NFLocalArchiveWriteInput,
                observe: (@Sendable (NFLocalArchiveWriteStage, Bool) -> Void)? = nil) throws -> NFLocalArchiveWriteAcknowledgement {
        // Synchronous actor method: no executor hop back to MainActor and no
        // reentrant suspension while the actual publication lock is held.
        try NFLocalSessionRepository.commitPreparedArchive(input, observe: observe)
    }
}


extension NFLocalSessionRepository {
    /// Off-main storage implementation. The MainActor factory must reserve the
    /// ticket and construct a validated immutable operation before calling this.
    nonisolated fileprivate static func commitPreparedArchive(_ input: NFLocalArchiveWriteInput,
        observe: (@Sendable (NFLocalArchiveWriteStage, Bool) -> Void)? = nil) throws -> NFLocalArchiveWriteAcknowledgement {
        try Task.checkCancellation()
        try input.ticket.checkPreparation()
        guard (input.original.transactionRevision ?? 0) == input.expectedRevision else { throw RepositoryError.staleRevision }
        let (revision, overflow) = input.expectedRevision.addingReportingOverflow(1)
        guard !overflow else { throw RepositoryError.unsupportedVersion }
        let proposal = try input.operation.candidate(in: input.original, ownerDeviceID: input.ownerDeviceID, at: input.capturedAt)
        // Validation may classify unsupported legacy rows for display. This
        // transaction preserves every unrelated accepted payload verbatim.
        _ = try validatedArchive(proposal, checkCancellation: { try Task.checkCancellation(); try input.ticket.checkPreparation() })
        var next = proposal
        next.transactionRevision = revision
        observe?(.encoding, Thread.isMainThread)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(next)
        guard data.count <= maximumBytes else { throw RepositoryError.oversized }
        let digest = NFReservationSnapshot.digest(data)
        try Task.checkCancellation()
        try input.ticket.checkPreparation()
        let acknowledgement: (Bool) -> NFLocalArchiveWriteAcknowledgement = { verification in
            .init(ticketID: input.ticket.id, ownerDeviceID: input.ownerDeviceID,
                  archive: next, byteDigest: digest, verificationNeeded: verification)
        }
        guard let url = input.sourceURL else {
            try input.ticket.beginCommit()
            observe?(.committed, Thread.isMainThread)
            return acknowledgement(false)
        }
        // This is the same process lock and flock namespace as synchronous
        // transactions. MainActor acquisition must use try(), never wait for us.
        guard publicationLock.try() else { throw RepositoryError.busy }
        defer { publicationLock.unlock() }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let lease = try NFLocalSessionStartupReadLease(at: url)
        defer { lease.release() }
        let identity = try NFLocalSessionStartupFileIdentity.capture(at: url)
        if let expected = input.expectedOriginalDigest {
            guard identity != nil else { throw RepositoryError.staleRevision }
            let original = try boundedData(at: url, checkCancellation: { try Task.checkCancellation(); try input.ticket.checkPreparation() })
            guard NFReservationSnapshot.digest(original) == expected else { throw RepositoryError.staleRevision }
            struct Header: Decodable { let schemaVersion: Int; let transactionRevision: UInt64? }
            let header = try JSONDecoder().decode(Header.self, from: original)
            guard header.schemaVersion == 1, (header.transactionRevision ?? 0) == input.expectedRevision else { throw RepositoryError.staleRevision }
        } else {
            guard identity == nil, input.expectedRevision == 0 else { throw RepositoryError.staleRevision }
        }
        observe?(.inputVerified, Thread.isMainThread)
        try Task.checkCancellation()
        try input.ticket.checkPreparation()
        let temporary = url.deletingLastPathComponent().appending(path: ".local-transaction-\(input.ticket.id.uuidString)")
        defer { try? FileManager.default.removeItem(at: temporary) }
        let descriptor = Darwin.open(temporary.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, S_IRUSR | S_IWUSR)
        guard descriptor >= 0 else { throw CocoaError(.fileWriteUnknown) }
        var descriptorOpen = true
        defer { if descriptorOpen { Darwin.close(descriptor) } }
        #if os(iOS)
        try FileManager.default.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication], ofItemAtPath: temporary.path)
        #endif
        try data.withUnsafeBytes { buffer in
            guard let base = buffer.baseAddress else { return }
            var offset = 0
            while offset < buffer.count {
                try Task.checkCancellation()
                try input.ticket.checkPreparation()
                let written = Darwin.write(descriptor, base.advanced(by: offset), min(64 * 1_024, buffer.count - offset))
                if written < 0, errno == EINTR { continue }
                guard written > 0 else { throw CocoaError(.fileWriteUnknown) }
                offset += written
            }
        }
        guard fsync(descriptor) == 0 else { throw CocoaError(.fileWriteUnknown) }
        guard Darwin.close(descriptor) == 0 else { descriptorOpen = false; throw CocoaError(.fileWriteUnknown) }
        descriptorOpen = false
        observe?(.staged, Thread.isMainThread)
        try Task.checkCancellation()
        guard try NFLocalSessionStartupFileIdentity.capture(at: url) == identity else { throw RepositoryError.staleRevision }
        try input.ticket.beginCommit()
        // From here onward cancellation cannot retract or hide an accepted
        // replacement. No Task.checkCancellation belongs below this boundary.
        guard Darwin.rename(temporary.path, url.path) == 0 else { throw CocoaError(.fileWriteUnknown) }
        observe?(.renamed, Thread.isMainThread)
        let directory = Darwin.open(url.deletingLastPathComponent().path, O_RDONLY | O_DIRECTORY | O_CLOEXEC)
        var verificationNeeded = directory < 0
        if directory >= 0 {
            verificationNeeded = fsync(directory) != 0
            Darwin.close(directory)
        }
        observe?(.committed, Thread.isMainThread)
        return acknowledgement(verificationNeeded)
    }
}

extension NFLocalSessionRepository {
    /// Every synchronous mutation uses this before touching another store and
    /// again inside the shared publication boundary. A writer never waits on
    /// the MainActor for the storage actor's filesystem lease.
    func requireArchiveWriteAvailability() throws {
        guard pendingWriteTicket == nil else { throw RepositoryError.busy }
        guard !archiveWriteVerificationNeeded else { throw RepositoryError.busy }
    }

    /// Read projections remain available, but reload's legacy model migrations
    /// wait for the archive boundary. Repeated requests from one store coalesce.
    func deferReloadUntilArchiveAvailable(owner: AnyObject, perform operation: @escaping () -> Void) -> Bool {
        guard pendingWriteTicket != nil || archiveWriteVerificationNeeded else { return false }
        deferredArchiveReloads[ObjectIdentifier(owner)] = operation
        return true
    }

    func replaceGeneratedCandidate(_ candidate: Archive) throws { try replace(candidate) }

    func saveSessionAsync(_ envelope: NFLocalSessionEnvelope, command: NFSessionWriterCommand,
                          expectedRevision: Int?) async throws -> NFLocalArchiveWriteAcknowledgement {
        try await writeArchive(.ordinary(envelope, expectedRevision: expectedRevision), command: command)
    }

    func saveGeneratedSessionAsync(_ draft: NFGeneratedPracticeDraft, command: NFSessionWriterCommand,
        expectedRevision: Int?, expectedPayloadDigest: String?) async throws -> NFLocalArchiveWriteAcknowledgement {
        let operation: NFLocalArchiveWriteOperation = draft.runState == nil
            ? .legacyGenerated(draft, expectedPayloadDigest: expectedPayloadDigest)
            : .generated(draft, expectedRevision: expectedRevision)
        return try await writeArchive(operation, command: command)
    }

    #if DEBUG
    /// Receives event names and execution location only. Fixtures may hold a
    /// deterministic boundary; production never installs a hook.
    var archiveWriteObserver: (@Sendable (NFLocalArchiveWriteStage, Bool) -> Void)? {
        get { debugArchiveWriteObserver }
        set { debugArchiveWriteObserver = newValue }
    }
    #endif

    func retainAttemptSnapshotAsync(_ snapshot: NFLocalAttemptSnapshot, sessionID: UUID,
        command: NFSessionWriterCommand) async throws -> NFLocalArchiveWriteAcknowledgement {
        guard let run = archive.sessions.first(where: { $0.id == sessionID }) else { throw RepositoryError.staleRevision }
        return try await writeArchive(.attemptRetention(.init(sessionID: sessionID, revision: run.revision,
            predecessor: run.checkpoint, snapshot: snapshot)), command: command)
    }

    func appendAttemptConflictAsync(_ record: NFAttemptConflictJournalEntry, sessionID: UUID,
        command: NFSessionWriterCommand) async throws -> NFLocalArchiveWriteAcknowledgement {
        try await writeArchive(.attemptConflict(.init(sessionID: sessionID, record: record)), command: command)
    }

    private func writeArchive(_ operation: NFLocalArchiveWriteOperation,
                              command: NFSessionWriterCommand) async throws -> NFLocalArchiveWriteAcknowledgement {
        try Task.checkCancellation()
        guard pendingWriteTicket == nil else { throw RepositoryError.busy }
        guard loadError == nil else { throw RepositoryError.corruptSnapshot }
        // An adopted-but-unverified rename may retry only through this async
        // boundary. The authenticated operation captures the adopted revision
        // and exact byte digest, then rechecks, rewrites and flushes that file.
        // Synchronous writers remain blocked by requireArchiveWriteAvailability.
        // Only a verified acknowledgement clears archiveWriteVerificationNeeded.
        try validateSessionCommand(command, sessionID: operation.sessionID)
        let ticket = NFLocalArchiveWriteTicket(command: command)
        let input = NFLocalArchiveWriteInput(ticket: ticket, ownerDeviceID: ownerDeviceID,
            sourceURL: url, expectedRevision: archive.transactionRevision ?? 0,
            expectedOriginalDigest: acknowledgedOriginalDigest, original: archive,
            operation: operation, capturedAt: Date())
        pendingWriteTicket = ticket
        #if DEBUG
        let observer = debugArchiveWriteObserver
        #else
        let observer: (@Sendable (NFLocalArchiveWriteStage, Bool) -> Void)? = nil
        #endif
        defer {
            ticket.finish()
            if pendingWriteTicket?.id == ticket.id { pendingWriteTicket = nil }
            if !archiveWriteVerificationNeeded {
                let callbacks = Array(deferredArchiveReloads.values)
                deferredArchiveReloads = [:]
                callbacks.forEach { $0() }
            }
        }
        let acknowledgement = try await withTaskCancellationHandler {
            try await NFLocalArchiveWriteWorker.shared.commit(input, observe: observer)
        } onCancel: {
            ticket.cancelPreparation()
        }
        // No cancellation or current-writer guard belongs before adoption.
        // The worker may already have renamed the committed file before a view
        // disappears. Its accepted bytes remain authoritative for the next view.
        guard pendingWriteTicket?.id == ticket.id,
              acknowledgement.ticketID == ticket.id, acknowledgement.ownerDeviceID == ownerDeviceID,
              acknowledgement.archive.transactionRevision == input.expectedRevision.addingReportingOverflow(1).partialValue,
              archive.transactionRevision == input.original.transactionRevision,
              acknowledgedOriginalDigest == input.expectedOriginalDigest else {
            loadError = RepositoryError.staleRevision.localizedDescription
            throw RepositoryError.staleRevision
        }
        archive = acknowledgement.archive
        acknowledgedOriginalDigest = url == nil ? nil : acknowledgement.byteDigest
        archiveWriteVerificationNeeded = acknowledgement.verificationNeeded
        return acknowledgement
    }
}

/// The actor owns immutable values only. The original private payload digest
/// authenticates modern and legacy runs without inventing historical slot IDs.
final class NFLocalGeneratedAttemptInput: Sendable {
    enum Change: Sendable {
        case retain(NFLocalAttemptSnapshot, proposed: NFImmutableAttemptRecordSnapshot)
        case conflict(NFAttemptConflictJournalEntry)
        case retainUnscored(NFLocalAttemptSnapshot, proposed: NFImmutableAttemptRecordSnapshot)
        case conflictUnscored(NFAttemptConflictJournalEntry)
    }
    let runID: UUID
    let predecessorDigest: String
    let change: Change
    init(runID: UUID, predecessorDigest: String, change: Change) {
        self.runID = runID; self.predecessorDigest = predecessorDigest; self.change = change
    }
}

extension NFLocalSessionRepository {
    func retainGeneratedAttemptSnapshotAsync(_ snapshot: NFLocalAttemptSnapshot,
        proposed: NFImmutableAttemptRecordSnapshot, runID: UUID,
        command: NFSessionWriterCommand, unscored: Bool = false) async throws -> NFLocalArchiveWriteAcknowledgement {
        let change: NFLocalGeneratedAttemptInput.Change = unscored
            ? .retainUnscored(snapshot, proposed: proposed) : .retain(snapshot, proposed: proposed)
        return try await writeGeneratedAttempt(change, runID: runID, command: command)
    }

    func appendGeneratedAttemptConflictAsync(_ record: NFAttemptConflictJournalEntry, runID: UUID,
        command: NFSessionWriterCommand) async throws -> NFLocalArchiveWriteAcknowledgement {
        let change: NFLocalGeneratedAttemptInput.Change = record.proposed.wasSkipped ? .conflictUnscored(record) : .conflict(record)
        return try await writeGeneratedAttempt(change, runID: runID, command: command)
    }

    private func writeGeneratedAttempt(_ change: NFLocalGeneratedAttemptInput.Change, runID: UUID,
        command: NFSessionWriterCommand) async throws -> NFLocalArchiveWriteAcknowledgement {
        guard let record = archive.privateStudyRuns?.first(where: { $0.id == runID }) else {
            throw RepositoryError.staleRevision
        }
        return try await writeArchive(.generatedAttempt(.init(runID: runID,
            predecessorDigest: NFReservationSnapshot.digest(record.payload), change: change)), command: command)
    }

    @inline(never)
    nonisolated static func generatedAttemptCandidate(_ input: NFLocalGeneratedAttemptInput,
        in archive: Archive, ownerDeviceID: UUID) throws -> Archive {
        guard let record = archive.privateStudyRuns?.first(where: { $0.id == input.runID }),
              NFReservationSnapshot.digest(record.payload) == input.predecessorDigest else {
            throw RepositoryError.staleRevision
        }
        let draft = try decodedGeneratedAttemptPredecessor(record.payload, runID: input.runID, ownerDeviceID: ownerDeviceID)
        return try applyGeneratedAttempt(input.change, predecessor: draft, in: archive)
    }

    @inline(never)
    nonisolated private static func decodedGeneratedAttemptPredecessor(_ payload: Data,
        runID: UUID, ownerDeviceID: UUID) throws -> NFGeneratedPracticeDraft {
        let draft = try JSONDecoder().decode(NFGeneratedPracticeDraft.self, from: payload)
        guard draft.valid, draft.id == runID, draft.ownerDeviceID == ownerDeviceID,
              draft.stage == 1, draft.pendingAttemptID != nil,
              draft.scoredResponse == draft.response else { throw RepositoryError.staleRevision }
        return draft
    }

    @inline(never)
    nonisolated private static func applyGeneratedAttempt(_ change: NFLocalGeneratedAttemptInput.Change,
        predecessor draft: NFGeneratedPracticeDraft, in archive: Archive) throws -> Archive {
        switch change {
        case .retainUnscored, .conflictUnscored:
            return try applyGeneratedUnscoredAttempt(change, predecessor: draft, in: archive)
        case .retain, .conflict: break
        }
        let exercise = draft.result.questions[draft.index].authoritativeExercise
        guard !exercise.assessmentProtected, exercise.evidenceClass == .documentPractice,
              draft.pendingUnscored == nil, draft.runState?.pendingUnscored == nil,
              let score = draft.lastScore else { throw RepositoryError.corruptSnapshot }
        switch change {
        case .retain(let snapshot, let proposed):
            guard snapshot.attemptID == draft.pendingAttemptID, snapshot.exercise == exercise,
                  snapshot.mathWork == draft.mathWork, snapshot.traceInspection == draft.traceInspection,
                  snapshot.dataInspection == draft.dataInspection, snapshot.scienceStudy == draft.scienceStudy,
                  snapshot.transferRelationship == draft.transferRelationship,
                  matchesGeneratedPreparedRecord(proposed, draft: draft, exercise: exercise, score: score) else {
                throw RepositoryError.staleRevision
            }
            return try retainedSnapshotCandidate(attemptID: snapshot.attemptID, exercise: snapshot.exercise,
                editorialCapture: snapshot.editorialCapture, mathWork: snapshot.mathWork,
                traceInspection: snapshot.traceInspection, dataInspection: snapshot.dataInspection,
                scienceStudy: snapshot.scienceStudy, transferRelationship: snapshot.transferRelationship, in: archive)
        case .conflict(let record):
            guard record.proposedExercise == exercise, record.proposedScore == score,
                  matchesGeneratedPreparedRecord(record.proposed, draft: draft, exercise: exercise, score: score) else {
                throw RepositoryError.staleRevision
            }
            return try attemptConflictCandidate(record, in: archive)
        case .retainUnscored, .conflictUnscored: throw RepositoryError.corruptSnapshot
        }
    }

    @inline(never)
    nonisolated private static func matchesGeneratedPreparedRecord(_ proposed: NFImmutableAttemptRecordSnapshot,
        draft: NFGeneratedPracticeDraft, exercise: NFExercise, score: NFExerciseScoringResult) -> Bool {
        let attemptSessionID = draft.runState == nil ? draft.result.provenance.requestID : draft.id
        let hintCount = (draft.runState?.nextHintIndex ?? (draft.hintRevealed ? 1 : 0))
            + (draft.traceInspection == nil ? 0 : 1) + (draft.dataInspection?.supportCount ?? 0)
        let expected: String
        if case .selfCheck = exercise.interaction, !exercise.provenance.sourceDocumentIDs.isEmpty { expected = "" }
        else { expected = score.expectedAnswerSummary ?? "" }
        return proposed.id == draft.pendingAttemptID && proposed.sessionID == attemptSessionID
            && proposed.generationID == draft.result.provenance.requestID
            && proposed.itemID == exercise.id && proposed.templateID == exercise.templateID && proposed.seed == exercise.seed
            && proposed.gameID == exercise.lab.rawValue && proposed.prompt == exercise.prompt
            && proposed.evidenceClassRaw == EvidenceClass.documentPractice.rawValue
            && proposed.sessionSourceRaw == SessionSource.focused.rawValue && proposed.assessmentBlockRaw == nil
            && !proposed.wasSkipped && !proposed.wasTimed
            && proposed.scoringVersion == score.scoringVersion && proposed.isCorrect == score.isCorrect
            && proposed.deterministicCredit == score.credit && proposed.errorCode == score.errorCode
            && proposed.correctAnswerText == expected
            && proposed.confidenceRaw == (score.outcome == .selfReported ? nil : draft.confidence?.rawValue)
            && proposed.responseFormatRaw == draft.response.responseFormatRaw
            && (try? JSONDecoder().decode(NFExerciseResponse.self, from: Data(proposed.response.utf8))) == draft.response
            && proposed.shownAt == draft.shownAt && proposed.activeDurationSeconds == draft.activeDuration
            && proposed.hintCount == hintCount
            && proposed.sourceDocumentIDsRaw == exercise.provenance.sourceDocumentIDs.joined(separator: ",")
            && proposed.sourceChunkIDsRaw == exercise.provenance.sourceChunkIDs.joined(separator: ",")
    }
}


extension NFLocalSessionRepository {
    /// This is called only by the writer-fenced visible presentation callback.
    /// It records displayed committed feedback, not understanding or proficiency.
    private func acknowledgeEditorialExplanation(sessionID: UUID, slotID: UUID, at date: Date) throws {
        guard let run = archive.sessions.first(where: { $0.id == sessionID }),
              permitsEditorialControls(run), run.ownerDeviceID == ownerDeviceID, run.status == .suspended,
              run.request.ordinaryDelivery?.editorialPolicy?.usesDeclaredReviewSlots == true,
              run.checkpoint.slotID == slotID, run.checkpoint.phase == .feedback,
              run.checkpoint.committedAttemptID == run.checkpoint.attemptID,
              let result = run.checkpoint.result, result.objectiveCorrectness != nil,
              let id = run.checkpoint.ordinaryReservationDecisionID,
              let receipt = archive.adaptiveItemReceipts?[id], let decision = receipt.editorialDecision,
              decision.isSupported, decision.reviewAssignment != nil,
              let snapshot = editorialSnapshot(for: run.checkpoint.attemptID),
              let capture = snapshot.editorialCapture, hasEditorialAuthority(for: capture),
              capture.rubricComponents == result.components,
              capture.reviewFeedbackDigest == (try NFEditorialCanonicalData.digest(result)),
              capture.exerciseDigest == receipt.exerciseDigest else { return }
        let key = run.checkpoint.attemptID.uuidString
        if let existing = archive.editorialExplanationPresentations?[key] {
            guard existing.sessionID == sessionID, existing.slotID == slotID,
                  existing.exerciseDigest == receipt.exerciseDigest,
                  existing.feedbackDigest == (try NFEditorialCanonicalData.digest(result)) else { throw RepositoryError.corruptSnapshot }
            return
        }
        let fact = NFEditorialExplanationPresentation(attemptID: run.checkpoint.attemptID, sessionID: sessionID,
            slotID: slotID, decisionID: id, ownerDeviceID: ownerDeviceID,
            exerciseDigest: receipt.exerciseDigest, feedbackDigest: try NFEditorialCanonicalData.digest(result), occurredAt: date)
        guard fact.isSupported else { throw RepositoryError.corruptSnapshot }
        var next = archive
        if next.editorialExplanationPresentations == nil { next.editorialExplanationPresentations = [:] }
        guard (next.editorialExplanationPresentations?.count ?? 0) < 4_096 else { throw RepositoryError.oversized }
        next.editorialExplanationPresentations?[key] = fact
        try replace(next)
    }

    private func reviewedSlotAssignments(request: SessionRequest, previous: NFLocalSessionEnvelope?,
        operation: NFReservationOperation, contracts: [String: NFEditorialReviewAssignment],
        input: NFEditorialLiveController.Input, evidence: NFEditorialEvidenceState, sessionBudgetSeconds: Double) throws -> [String: NFEditorialReviewAssignment] {
        let pin = request.ordinaryDelivery?.editorialPolicy
        let used = (archive.adaptiveItemReceipts ?? [:]).values.filter { $0.sessionID == request.id }
            .sorted { $0.decisionID < $1.decisionID }.compactMap { $0.editorialDecision?.reviewAssignment }.filter { $0.role != .probe }
        let budget = NFEditorialReviewSlotPolicy.Budget(totalSeconds: sessionBudgetSeconds,
            usedSeconds: used.reduce(0) { $0 + $1.expectedSeconds }, usedCount: used.count,
            explicitReview: pin?.reviewIntent != nil)
        let facts = (archive.editorialExplanationPresentations ?? [:]).filter { _, fact in
            fact.ownerDeviceID == ownerDeviceID && fact.isSupported
        }
        return try NFEditorialReviewSlotPolicy.project(contracts: contracts, input: input, evidence: evidence,
            explanations: facts, repairOriginID: operation == .next ? previous?.checkpoint.committedAttemptID?.uuidString : nil,
            intent: pin?.reviewIntent, budget: budget, currentSessionID: request.id.uuidString)
    }

    @inline(never)
    nonisolated private static func validateEditorialReviewAssignment(_ receipt: NFLocalAdaptiveItemReceipt,
        decision: NFEditorialControllerDecision, archive: Archive) throws {
        guard let assigned = decision.reviewAssignment else { return }
        guard let criterion = decision.criterionSelection,
              let timing = NFEditorialTimingMode(rawValue: criterion.group.pacingConditionID),
              let ledger = archive.selectionLedger, let slot = ledger.slots[receipt.slotID.uuidString],
              let snapshot = NFSelectionReservationPolicy.snapshot(for: slot, in: ledger),
              let exercise = try? JSONDecoder().decode(NFExercise.self, from: snapshot.payload),
              let expected = NFEditorialReviewSlotPolicy.contract(exercise: exercise, admission: decision.admission,
                timing: timing, day: decision.decisionDay.ordinal),
              expected.contract == assigned.contract, expected.group == assigned.group,
              expected.semanticFingerprint == assigned.semanticFingerprint,
              expected.expectedSeconds == assigned.expectedSeconds else { throw RepositoryError.corruptSnapshot }
        if let explanation = assigned.explanation {
            guard archive.editorialExplanationPresentations?[explanation.attemptID.uuidString] == explanation,
                  explanation.ownerDeviceID == receipt.ownerDeviceID else { throw RepositoryError.corruptSnapshot }
        }
        if let intent = archive.sessions.first(where: { $0.id == receipt.sessionID })?.request.ordinaryDelivery?.editorialPolicy?.reviewIntent {
            guard assigned.role == intent.role, assigned.originObservationID == intent.originObservationID else { throw RepositoryError.corruptSnapshot }
        }
    }

    @inline(never)
    nonisolated private static func validateEditorialExplanationPresentations(_ archive: Archive, checkCancellation: () throws -> Void) throws {
        guard (archive.editorialExplanationPresentations?.count ?? 0) <= 4_096 else { throw RepositoryError.oversized }
        for (key, fact) in archive.editorialExplanationPresentations ?? [:] {
            try checkCancellation()
            guard key == fact.attemptID.uuidString, fact.isSupported,
                  let receipt = archive.adaptiveItemReceipts?[fact.decisionID], receipt.isSupported,
                  receipt.sessionID == fact.sessionID, receipt.slotID == fact.slotID,
                  receipt.attemptID == fact.attemptID, receipt.ownerDeviceID == fact.ownerDeviceID,
                  receipt.exerciseDigest == fact.exerciseDigest,
                  let capture = archive.snapshots.first(where: { $0.attemptID == fact.attemptID })?.editorialCapture,
                  capture.exerciseDigest == fact.exerciseDigest,
                  capture.reviewFeedbackDigest == fact.feedbackDigest,
                  capture.runtimeWitness?.decisionID == fact.decisionID,
                  capture.runtimeWitness?.reviewAssignment == receipt.editorialDecision?.reviewAssignment else { throw RepositoryError.corruptSnapshot }
        }
    }

    /// Public presentation contains no answer or source text. The caller can
    /// offer a declared repair only after its current feedback was acknowledged.
    func editorialReviewOrigin(sessionID: UUID) -> (observationID: UUID, band: NFEditorialBand, scope: NFEditorialFamilyScope)? {
        guard let run = archive.sessions.first(where: { $0.id == sessionID }), permitsEditorialControls(run),
              run.ownerDeviceID == ownerDeviceID, run.status == .suspended, run.checkpoint.phase == .feedback,
              run.checkpoint.committedAttemptID == run.checkpoint.attemptID, run.checkpoint.result?.isCorrect == false,
              archive.editorialExplanationPresentations?[run.checkpoint.attemptID.uuidString] != nil,
              let id = run.checkpoint.ordinaryReservationDecisionID,
              let decision = archive.adaptiveItemReceipts?[id]?.editorialDecision,
              decision.isSupported, decision.admission.demand.reviewContract?.allowedRoles.contains(.repair) == true else { return nil }
        return (run.checkpoint.attemptID, decision.selection.deliveredBand,
                .init(objectiveID: decision.admission.demand.objectiveID, familyID: decision.admission.demand.familyID))
    }
}

extension NFLocalSessionRepository {
    @inline(never)
    nonisolated private static func applyGeneratedUnscoredAttempt(_ change: NFLocalGeneratedAttemptInput.Change,
        predecessor draft: NFGeneratedPracticeDraft, in archive: Archive) throws -> Archive {
        let exercise = draft.result.questions[draft.index].authoritativeExercise
        guard !exercise.assessmentProtected, exercise.evidenceClass == .documentPractice,
              draft.lastScore == nil,
              let outcome = draft.runState?.pendingUnscored ?? draft.pendingUnscored,
              outcome == .skipped || outcome == .revealed else { throw RepositoryError.corruptSnapshot }
        switch change {
        case .retainUnscored(let snapshot, let proposed):
            guard snapshot.attemptID == draft.pendingAttemptID, snapshot.exercise == exercise, snapshot.editorialCapture == nil,
                  snapshot.mathWork == draft.mathWork, snapshot.traceInspection == draft.traceInspection,
                  snapshot.dataInspection == draft.dataInspection, snapshot.scienceStudy == draft.scienceStudy,
                  snapshot.transferRelationship == draft.transferRelationship,
                  matchesGeneratedUnscoredRecord(proposed, draft: draft, exercise: exercise, outcome: outcome) else {
                throw RepositoryError.staleRevision
            }
            return try retainedSnapshotCandidate(attemptID: snapshot.attemptID, exercise: snapshot.exercise,
                editorialCapture: snapshot.editorialCapture, mathWork: snapshot.mathWork,
                traceInspection: snapshot.traceInspection, dataInspection: snapshot.dataInspection,
                scienceStudy: snapshot.scienceStudy, transferRelationship: snapshot.transferRelationship, in: archive)
        case .conflictUnscored(let record):
            guard record.proposedExercise == exercise, record.proposedScore == nil,
                  matchesGeneratedUnscoredRecord(record.proposed, draft: draft, exercise: exercise, outcome: outcome) else {
                throw RepositoryError.staleRevision
            }
            return try attemptConflictCandidate(record, in: archive)
        case .retain, .conflict: throw RepositoryError.corruptSnapshot
        }
    }

    @inline(never)
    nonisolated private static func matchesGeneratedUnscoredRecord(_ proposed: NFImmutableAttemptRecordSnapshot,
        draft: NFGeneratedPracticeDraft, exercise: NFExercise, outcome: NFGeneratedRunState.Outcome) -> Bool {
        let sessionID = draft.runState == nil ? draft.result.provenance.requestID : draft.id
        let format = outcome == .revealed ? "revealed" : "skipped"
        let hintCount = (draft.runState?.nextHintIndex ?? (draft.hintRevealed ? 1 : 0))
            + (draft.traceInspection == nil ? 0 : 1) + (draft.dataInspection?.supportCount ?? 0)
        return proposed.id == draft.pendingAttemptID && proposed.sessionID == sessionID
            && proposed.generationID == draft.result.provenance.requestID
            && proposed.itemID == exercise.id && proposed.templateID == exercise.templateID && proposed.seed == exercise.seed
            && proposed.gameID == exercise.lab.rawValue && proposed.prompt == exercise.prompt
            && proposed.evidenceClassRaw == EvidenceClass.documentPractice.rawValue
            && proposed.sessionSourceRaw == SessionSource.focused.rawValue && proposed.assessmentBlockRaw == nil
            && proposed.wasSkipped && !proposed.wasTimed && proposed.confidenceRaw == nil
            && proposed.scoringVersion == draft.scorerVersion && !proposed.isCorrect
            && proposed.deterministicCredit == 0 && proposed.evidenceWeight == 0
            && proposed.errorCode == (outcome == .revealed ? "solution_revealed" : nil)
            && proposed.correctAnswerText == "Not evaluated"
            && proposed.inputModeRaw == format && proposed.responseFormatRaw == format
            && (try? JSONDecoder().decode(NFExerciseResponse.self, from: Data(proposed.response.utf8))) == draft.response
            && proposed.shownAt == draft.shownAt && proposed.activeDurationSeconds == draft.activeDuration
            && proposed.hintCount == hintCount
            && proposed.sourceDocumentIDsRaw == exercise.provenance.sourceDocumentIDs.joined(separator: ",")
            && proposed.sourceChunkIDsRaw == exercise.provenance.sourceChunkIDs.joined(separator: ",")
    }
}

extension NFLocalSessionRepository {
    @inline(never)
    nonisolated private static func validateEditorialGoalSelection(_ receipt: NFLocalAdaptiveItemReceipt,
        decision: NFEditorialControllerDecision, archive: Archive) throws {
        guard let goal = decision.goalSelection else { return }
        guard let run = archive.sessions.first(where: { $0.id == receipt.sessionID }),
              let delivery = run.request.ordinaryDelivery, let pin = delivery.editorialPolicy,
              pin.isSupported, pin.usesGoalRanking, goal.preferences == pin.goalPreferences,
              goal.preferences.profileID == delivery.profileID,
              NFEditorialGoalRankingPolicy.selection(admission: decision.admission, preferences: goal.preferences) == goal else {
            throw RepositoryError.corruptSnapshot
        }
    }
}

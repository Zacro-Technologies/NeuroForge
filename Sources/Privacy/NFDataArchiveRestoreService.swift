import Foundation
import SwiftData

enum NFDataArchiveRestorePolicy: String, CaseIterable, Identifiable, Sendable {
    case abortOnConflict
    case keepExisting
    case replaceMatching
    case replaceAll

    var id: String { rawValue }
}

enum NFDataArchiveCategory: String, CaseIterable, Identifiable, Sendable {
    case profile
    case attempts
    case reflections
    case documents
    case sourceChunks
    case generatedSets
    case checkpoints
    case dailyPlans
    case calibrations
    case annotations
    case weeklyMission
    case reassessment
    case adaptiveHistory
    case reports

    var id: String { rawValue }
}

struct NFDataArchiveRecordCounts: Equatable, Sendable {
    let values: [NFDataArchiveCategory: Int]

    subscript(_ category: NFDataArchiveCategory) -> Int { values[category, default: 0] }
    var total: Int { values.values.reduce(0, +) }
}

struct NFDataArchiveRestorePreview: Equatable, Sendable {
    let archiveVersion: Int
    let exportedAt: Date
    let appVersion: String
    let incoming: NFDataArchiveRecordCounts
    let conflicts: NFDataArchiveRecordCounts
    let excludedPrivateAnnotationCount: Int
    let warnings: [String]

    var hasConflicts: Bool { conflicts.total > 0 }
}

struct NFDataArchiveRestoreResult: Equatable, Sendable {
    let preview: NFDataArchiveRestorePreview
    let policy: NFDataArchiveRestorePolicy
    let restored: NFDataArchiveRecordCounts
    let skipped: NFDataArchiveRecordCounts
    let warnings: [String]
}

enum NFDataArchiveRestoreError: Error, Equatable, LocalizedError {
    case unsupportedArchiveVersion(Int)
    case invalidArchive(String)
    case conflictsRequireDecision(Int)
    case activeSession
    case persistenceFailed

    var errorDescription: String? {
        switch self {
        case let .unsupportedArchiveVersion(version):
            NFAppLocalization.localized(
                "Archive version \(version) cannot be restored by this version of NeuroForge.",
                locale: NFAppLocalization.preferredLocale,
                comment: "Archive restore version error; the placeholder is the archive version."
            )
        case let .invalidArchive(reason):
            NFAppLocalization.localized(
                "The archive did not pass validation: \(reason)",
                locale: NFAppLocalization.preferredLocale,
                comment: "Archive restore validation error; the placeholder is a non-sensitive validation reason."
            )
        case let .conflictsRequireDecision(count):
            NFAppLocalization.localized(
                "Review \(NFAppLocalization.formattedRecordCount(count)) in conflict and choose how to continue.",
                locale: NFAppLocalization.preferredLocale,
                comment: "Archive restore conflict error with a localized record count."
            )
        case .activeSession:
            NFAppLocalization.localized(
                "Finish or save and close the current session before restoring a backup.",
                locale: NFAppLocalization.preferredLocale,
                comment: "Archive restore blocked by an active session."
            )
        case .persistenceFailed:
            NFAppLocalization.localized(
                "The restore was rolled back because NeuroForge could not verify the imported records.",
                locale: NFAppLocalization.preferredLocale,
                comment: "Archive restore transactional persistence error."
            )
        }
    }
}

/// Versioned, preview-first restore for the full JSON export. The entire file
/// is decoded and semantically checked before SwiftData is mutated. Model
/// changes are saved once; any failure rolls the context back and reloads the
/// prior store state. The separate adaptive-history file is replaced before
/// the model commit so a history-write failure cannot leave a partial restore;
/// a later model failure restores the original history before returning.
@MainActor
enum NFDataArchiveRestoreService {
    static func preview(
        archiveAt url: URL,
        into store: AppStore
    ) throws -> NFDataArchiveRestorePreview {
        let archive = try decodedArchive(at: url)
        try validate(archive, existingStore: store, policy: nil)
        return makePreview(archive, store: store)
    }

    static func restore(
        archiveAt url: URL,
        into store: AppStore,
        policy: NFDataArchiveRestorePolicy,
        corePersistence: ((ModelContext) throws -> Void)? = nil
    ) throws -> NFDataArchiveRestoreResult {
        guard store.activeSessionRequest == nil else { throw NFDataArchiveRestoreError.activeSession }
        let archive = try decodedArchive(at: url)
        try validate(archive, existingStore: store, policy: policy)
        let preview = makePreview(archive, store: store)
        if policy == .abortOnConflict, preview.hasConflicts {
            throw NFDataArchiveRestoreError.conflictsRequireDecision(preview.conflicts.total)
        }

        var restored = emptyCounts()
        var skipped = emptyCounts()
        let context = store.context

        // Adaptive history intentionally lives outside SwiftData. Resolve and
        // persist it before touching core records so an unwritable history
        // destination fails the entire restore without committing core data.
        // `replaceAll` must run even when the incoming history is empty.
        let oldHistory = store.adaptivePlanHistory
        let incomingHistory = archive.adaptivePlanHistory ?? []
        let incomingHistoryIDs = Set(incomingHistory.map(\.id))
        var skippedIncomingHistoryIDs: Set<UUID> = []
        let selectedHistory: [NFAdaptivePlanChangeRecord]
        switch policy {
        case .replaceAll:
            selectedHistory = incomingHistory
        case .replaceMatching:
            selectedHistory = incomingHistory + oldHistory.filter { !incomingHistoryIDs.contains($0.id) }
        case .abortOnConflict, .keepExisting:
            let existingIDs = Set(oldHistory.map(\.id))
            skippedIncomingHistoryIDs = incomingHistoryIDs.intersection(existingIDs)
            selectedHistory = oldHistory + incomingHistory.filter { !existingIDs.contains($0.id) }
        }
        let shouldReplaceHistory = policy == .replaceAll || !incomingHistory.isEmpty
        var historyWasReplaced = false
        if shouldReplaceHistory {
            do {
                try store.replaceAdaptivePlanHistoryForRestore(selectedHistory)
                historyWasReplaced = true
                let persistedIDs = Set(store.adaptivePlanHistory.map(\.id))
                let eligibleIncomingIDs = incomingHistoryIDs.subtracting(skippedIncomingHistoryIDs)
                restored[.adaptiveHistory] = persistedIDs.intersection(eligibleIncomingIDs).count
                skipped[.adaptiveHistory] = skippedIncomingHistoryIDs.count
                    + eligibleIncomingIDs.subtracting(persistedIDs).count
            } catch {
                // `replacingHistory` writes atomically, then reloads. If that
                // reload is the failing step, the new file may already be in
                // place even though the call threw; compensate before failing.
                try? store.replaceAdaptivePlanHistoryForRestore(oldHistory)
                throw NFDataArchiveRestoreError.persistenceFailed
            }
        }

        do {
            if policy == .replaceAll {
                deleteAllModelRecords(from: store)
            } else if policy == .replaceMatching {
                deleteMatchingModelRecords(in: archive, from: store)
            }

            if let profile = archive.profile {
                if policy != .keepExisting || store.profile == nil {
                    context.insert(makeProfile(profile))
                    restored[.profile, default: 0] += 1
                } else {
                    skipped[.profile, default: 0] += 1
                }
            }

            let existingAttemptIDs = Set(store.attempts.map(\.id))
            for payload in archive.attempts {
                if policy == .keepExisting, existingAttemptIDs.contains(payload.id) {
                    skipped[.attempts, default: 0] += 1
                } else {
                    context.insert(makeAttempt(payload))
                    restored[.attempts, default: 0] += 1
                }
            }

            let existingReflectionIDs = Set(store.attemptReflections.map(\.id))
            for payload in archive.attemptReflections {
                if policy == .keepExisting, existingReflectionIDs.contains(payload.id) {
                    skipped[.reflections, default: 0] += 1
                } else {
                    context.insert(makeReflection(payload))
                    restored[.reflections, default: 0] += 1
                }
            }

            let existingDocumentIDs = Set(store.documents.map(\.id))
            for payload in archive.documents {
                if policy == .keepExisting, existingDocumentIDs.contains(payload.id) {
                    skipped[.documents, default: 0] += 1
                } else {
                    context.insert(makeDocument(payload))
                    restored[.documents, default: 0] += 1
                }
            }

            let existingChunkIDs = Set(store.sourceChunks.map(\.id))
            for payload in archive.sourceChunks {
                if policy == .keepExisting, existingChunkIDs.contains(payload.id) {
                    skipped[.sourceChunks, default: 0] += 1
                } else {
                    context.insert(makeChunk(payload))
                    restored[.sourceChunks, default: 0] += 1
                }
            }

            let existingGenerationIDs = Set(store.aiGenerations.map(\.id))
            for payload in archive.aiGenerations {
                if policy == .keepExisting, existingGenerationIDs.contains(payload.id) {
                    skipped[.generatedSets, default: 0] += 1
                } else {
                    context.insert(try makeGeneration(payload))
                    restored[.generatedSets, default: 0] += 1
                }
            }

            let existingCheckpointIDs = Set(store.sessionCheckpoints.map(\.id))
            for payload in archive.sessionCheckpoints {
                if policy == .keepExisting, existingCheckpointIDs.contains(payload.id) {
                    skipped[.checkpoints, default: 0] += 1
                } else {
                    context.insert(makeCheckpoint(payload))
                    restored[.checkpoints, default: 0] += 1
                }
            }

            let existingPlanIDs = Set(store.dailyPlans.map(\.id))
            for payload in archive.dailyPlans {
                if policy == .keepExisting, existingPlanIDs.contains(payload.id) {
                    skipped[.dailyPlans, default: 0] += 1
                } else {
                    context.insert(try makeDailyPlan(payload))
                    restored[.dailyPlans, default: 0] += 1
                }
            }

            let existingCalibrationIDs = Set(store.inputCalibrations.map(\.id))
            for payload in archive.inputCalibrations {
                if policy == .keepExisting, existingCalibrationIDs.contains(payload.id) {
                    skipped[.calibrations, default: 0] += 1
                } else {
                    context.insert(makeCalibration(payload))
                    restored[.calibrations, default: 0] += 1
                }
            }

            let existingAnnotationIDs = Set(store.progressAnnotations.map(\.id))
            for payload in archive.progressAnnotations {
                if policy == .keepExisting, existingAnnotationIDs.contains(payload.id) {
                    skipped[.annotations, default: 0] += 1
                } else {
                    context.insert(makeAnnotation(payload))
                    restored[.annotations, default: 0] += 1
                }
            }

            if let state = archive.weeklyTransferState {
                if policy == .keepExisting, store.weeklyTransferStateRecord != nil {
                    skipped[.weeklyMission, default: 0] += 1
                } else {
                    context.insert(WeeklyTransferStateRecord(state: state))
                    restored[.weeklyMission, default: 0] += 1
                }
            }
            if let state = archive.reassessmentState {
                if policy == .keepExisting, store.reassessmentStateRecord != nil {
                    skipped[.reassessment, default: 0] += 1
                } else {
                    context.insert(ReassessmentStateRecord(state: state))
                    restored[.reassessment, default: 0] += 1
                }
            }

            let existingReportIDs = Set(store.itemReports.map(\.id))
            for payload in archive.quarantinedReports {
                if policy == .keepExisting, existingReportIDs.contains(payload.id) {
                    skipped[.reports, default: 0] += 1
                } else {
                    context.insert(makeReport(payload))
                    restored[.reports, default: 0] += 1
                }
            }

            if let corePersistence {
                try corePersistence(context)
            } else {
                try context.save()
            }
            store.reload()

            store.publishWidgetSnapshot()
            store.notice = AppNotice(
                title: NFAppLocalization.localized(
                    "Backup restored",
                    locale: NFAppLocalization.preferredLocale,
                    comment: "Archive restore success title."
                ),
                message: NFAppLocalization.localized(
                    "NeuroForge validated and restored \(NFAppLocalization.formattedRecordCount(restored.values.reduce(0, +))). Review Sources for reconstructed text and Progress for retained history.",
                    locale: NFAppLocalization.preferredLocale,
                    comment: "Archive restore success message with a localized restored-record count."
                )
            )
            return NFDataArchiveRestoreResult(
                preview: preview,
                policy: policy,
                restored: NFDataArchiveRecordCounts(values: restored),
                skipped: NFDataArchiveRecordCounts(values: skipped),
                warnings: preview.warnings
            )
        } catch {
            context.rollback()
            var historyRollbackFailed = false
            if historyWasReplaced {
                do {
                    try store.replaceAdaptivePlanHistoryForRestore(oldHistory)
                } catch {
                    historyRollbackFailed = true
                }
            }
            store.reload()
            guard !historyRollbackFailed else {
                throw NFDataArchiveRestoreError.persistenceFailed
            }
            if let restoreError = error as? NFDataArchiveRestoreError {
                throw restoreError
            }
            throw NFDataArchiveRestoreError.persistenceFailed
        }
    }

    // MARK: Decode and validation

    private static func decodedArchive(at url: URL) throws -> NFDataExportService.Archive {
        do {
            _ = try NFDataExportRoundTripValidator.decodeArchive(at: url)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let data = try NFDataArchiveMigration.normalizedData(from: Data(contentsOf: url))
            return try decoder.decode(NFDataExportService.Archive.self, from: data)
        } catch let error as NFDataArchiveValidationError {
            switch error {
            case let .unsupportedArchiveVersion(version):
                throw NFDataArchiveRestoreError.unsupportedArchiveVersion(version)
            case let .duplicateIdentity(category):
                throw NFDataArchiveRestoreError.invalidArchive("duplicate identity in \(category)")
            }
        } catch {
            throw NFDataArchiveRestoreError.invalidArchive("the JSON structure or dates are invalid")
        }
    }

    private static func validate(
        _ archive: NFDataExportService.Archive,
        existingStore store: AppStore,
        policy: NFDataArchiveRestorePolicy?
    ) throws {
        guard (NFDataExportService.oldestRestorableArchiveVersion...NFDataExportService.archiveVersion)
            .contains(archive.archiveVersion) else {
            throw NFDataArchiveRestoreError.unsupportedArchiveVersion(archive.archiveVersion)
        }
        if let profile = archive.profile {
            guard Stage(rawValue: profile.stage) != nil,
                  profile.fields.allSatisfy({ STEMField(rawValue: $0) != nil }),
                  profile.goals.allSatisfy({ TrainingGoal(rawValue: $0) != nil }),
                  TimingMode(rawValue: profile.timingMode) != nil,
                  AIMode(rawValue: profile.aiMode) != nil,
                  NFPreferredAnswerMode(rawValue: profile.preferredAnswerMode) != nil,
                  (1...240).contains(profile.dailyDuration),
                  (0...12).contains(profile.dayBoundaryHour),
                  !profile.trainingDays.isEmpty,
                  profile.trainingDays.allSatisfy({ (1...7).contains(Int($0) ?? -1) }) else {
                throw NFDataArchiveRestoreError.invalidArchive("profile values are outside supported bounds")
            }
        }

        let incomingProfileIDs = Set(archive.profile.map { [$0.id] } ?? [])
        let existingProfileIDs = Set(store.profile.map { [$0.id] } ?? [])
        let availableProfileIDs: Set<UUID> = switch policy {
        case .replaceAll:
            incomingProfileIDs
        case .keepExisting:
            existingProfileIDs.isEmpty ? incomingProfileIDs : existingProfileIDs
        case .replaceMatching:
            incomingProfileIDs.isEmpty ? existingProfileIDs : incomingProfileIDs
        case .abortOnConflict, nil:
            incomingProfileIDs.union(existingProfileIDs)
        }

        let incomingAttemptIDs = Set(archive.attempts.map(\.id))
        let availableAttemptIDs = availableReferenceIDs(
            incoming: incomingAttemptIDs,
            existing: Set(store.attempts.map(\.id)),
            policy: policy
        )
        guard archive.attemptReflections.allSatisfy({ availableAttemptIDs.contains($0.attemptID) }) else {
            throw NFDataArchiveRestoreError.invalidArchive("a reflection references a missing attempt")
        }
        let incomingReflectionIDs = Set(archive.attemptReflections.map(\.id))
        guard store.attemptReflections
            .filter({ retainsExistingRecord(id: $0.id, replacedBy: incomingReflectionIDs, policy: policy) })
            .allSatisfy({ availableAttemptIDs.contains($0.attemptID) }) else {
            throw NFDataArchiveRestoreError.invalidArchive(
                "the selected conflict policy would retain a reflection whose attempt is removed"
            )
        }
        guard archive.attempts.allSatisfy({
            TrainingLab(rawValue: $0.lab) != nil
                && EvidenceClass(rawValue: $0.evidenceClass) != nil
                && SessionSource(rawValue: $0.sessionSource) != nil
                && $0.activeDurationSeconds.isFinite && $0.activeDurationSeconds >= 0
                && $0.evidenceWeight.isFinite && $0.evidenceWeight >= 0
                && $0.deterministicCredit.isFinite && (0...1).contains($0.deterministicCredit)
        }) else {
            throw NFDataArchiveRestoreError.invalidArchive("attempt telemetry is invalid")
        }
        guard archive.sessionCheckpoints.allSatisfy({ checkpoint in
            guard TrainingLab(rawValue: checkpoint.lab) != nil,
                  SessionSource(rawValue: checkpoint.source) != nil,
                  EvidenceClass(rawValue: checkpoint.evidenceClass) != nil,
                  checkpoint.currentIndex >= 0,
                  checkpoint.itemCount >= 0,
                  checkpoint.activeDurationSeconds.isFinite,
                  checkpoint.activeDurationSeconds >= 0 else { return false }
            guard let pendingAttemptID = checkpoint.pendingReflectionAttemptID else {
                return checkpoint.reflectionTrigger == nil
                    && checkpoint.selectedReflectionCode == nil
                    && checkpoint.reflectionNote == nil
            }
            guard !checkpoint.isComplete,
                  checkpoint.hasCommittedCurrentItem,
                  availableAttemptIDs.contains(pendingAttemptID),
                  let triggerRaw = checkpoint.reflectionTrigger,
                  let trigger = NFAttemptReflectionTrigger(rawValue: triggerRaw),
                  checkpoint.reflectionNote?.count ?? 0 <= AttemptReflectionRecord.maximumNoteCharacters,
                  let responseData = checkpoint.response.data(using: .utf8),
                  (try? JSONDecoder().decode(NFExerciseResponse.self, from: responseData)) != nil else {
                return false
            }
            if trigger == .weeklyTransfer {
                return checkpoint.selectedReflectionCode == nil
            }
            return checkpoint.selectedReflectionCode
                .flatMap(NFErrorReflectionCode.init(rawValue:)) != nil
        }) else {
            throw NFDataArchiveRestoreError.invalidArchive("a session checkpoint has invalid reflection recovery state")
        }
        let incomingCheckpointIDs = Set(archive.sessionCheckpoints.map(\.id))
        guard store.sessionCheckpoints
            .filter({ retainsExistingRecord(id: $0.id, replacedBy: incomingCheckpointIDs, policy: policy) })
            .allSatisfy({ checkpoint in
                checkpoint.pendingReflectionAttemptID.map(availableAttemptIDs.contains) ?? true
            }) else {
            throw NFDataArchiveRestoreError.invalidArchive(
                "the selected conflict policy would retain a checkpoint whose pending attempt is removed"
            )
        }
        guard archive.progressAnnotations.allSatisfy({
            $0.note.trimmingCharacters(in: .whitespacesAndNewlines).count
                <= ProgressAnnotationRecord.maximumNoteCharacters
        }) else {
            throw NFDataArchiveRestoreError.invalidArchive("a progress annotation exceeds the supported note length")
        }

        let incomingDocumentIDs = Set(archive.documents.map(\.id))
        let availableDocumentIDs = availableReferenceIDs(
            incoming: incomingDocumentIDs,
            existing: Set(store.documents.map(\.id)),
            policy: policy
        )
        guard archive.sourceChunks.allSatisfy({ availableDocumentIDs.contains($0.documentID) }) else {
            throw NFDataArchiveRestoreError.invalidArchive("a source chunk references a missing document")
        }
        let incomingChunkIDs = Set(archive.sourceChunks.map(\.id))
        guard store.sourceChunks
            .filter({ retainsExistingRecord(id: $0.id, replacedBy: incomingChunkIDs, policy: policy) })
            .allSatisfy({ availableDocumentIDs.contains($0.documentID) }) else {
            throw NFDataArchiveRestoreError.invalidArchive(
                "the selected conflict policy would retain a source chunk whose document is removed"
            )
        }
        let availableChunkIDs = availableReferenceIDs(
            incoming: incomingChunkIDs,
            existing: Set(store.sourceChunks.map(\.id)),
            policy: policy
        )
        for generation in archive.aiGenerations {
            guard NFAICapability(rawValue: generation.capability) != nil,
                  TrainingLab(rawValue: generation.lab) != nil,
                  STEMField(rawValue: generation.field) != nil,
                  NFAIRoute(rawValue: generation.route) != nil,
                  generation.questionCount >= generation.questions.count,
                  generation.sourceDocumentIDs.allSatisfy({ UUID(uuidString: $0).map(availableDocumentIDs.contains) == true }),
                  generation.sourceChunkIDs.allSatisfy(availableChunkIDs.contains),
                  generation.questions.allSatisfy(\.hasValidResponseSchema) else {
                throw NFDataArchiveRestoreError.invalidArchive("a generated set has invalid provenance or response schema")
            }
        }
        let incomingGenerationIDs = Set(archive.aiGenerations.map(\.id))
        guard store.aiGenerations
            .filter({ retainsExistingRecord(id: $0.id, replacedBy: incomingGenerationIDs, policy: policy) })
            .allSatisfy({ generation in
                let documentTokens = generation.sourceDocumentIDsRaw.split(separator: ",")
                let documentIDs = documentTokens.compactMap { UUID(uuidString: String($0)) }
                let chunkIDs = generation.sourceChunkIDsRaw.split(separator: ",").map(String.init)
                return documentIDs.count == documentTokens.count
                    && documentIDs.allSatisfy(availableDocumentIDs.contains)
                    && chunkIDs.allSatisfy(availableChunkIDs.contains)
            }) else {
            throw NFDataArchiveRestoreError.invalidArchive(
                "the selected conflict policy would retain a generated set with missing source provenance"
            )
        }

        for payload in archive.dailyPlans {
            guard let data = Data(base64Encoded: payload.canonicalPayloadBase64),
                  let plan = try? JSONDecoder().decode(NFCanonicalDailyPlan.self, from: data),
                  availableProfileIDs.contains(payload.profileID),
                  plan.id == payload.id,
                  plan.profileID == payload.profileID,
                  plan.policyVersion == payload.policyVersion,
                  plan.scheduledMinutes > 0,
                  plan.scheduledMinutes == plan.blocks.reduce(0, { $0 + $1.minutes }),
                  payload.nextBoundaryAt > payload.boundaryStart,
                  (0...12).contains(payload.dayBoundaryHour) else {
                throw NFDataArchiveRestoreError.invalidArchive("a daily plan failed identity or duration checks")
            }
        }
        let incomingPlanIDs = Set(archive.dailyPlans.map(\.id))
        guard store.dailyPlans
            .filter({ retainsExistingRecord(id: $0.id, replacedBy: incomingPlanIDs, policy: policy) })
            .allSatisfy({ availableProfileIDs.contains($0.profileID) }) else {
            throw NFDataArchiveRestoreError.invalidArchive(
                "the selected conflict policy would retain a daily plan whose profile is removed"
            )
        }
        guard archive.inputCalibrations.allSatisfy({
            availableProfileIDs.contains($0.profileID)
                && NFPreferredAnswerMode(rawValue: $0.preferredAnswerMode) != nil
                && [$0.keyboardLatencyMilliseconds, $0.touchLatencyMilliseconds, $0.pencilLatencyMilliseconds]
                    .compactMap { $0 }
                    .allSatisfy { $0.isFinite && (0...60_000).contains($0) }
        }) else {
            throw NFDataArchiveRestoreError.invalidArchive("input calibration values are invalid")
        }
        let incomingCalibrationIDs = Set(archive.inputCalibrations.map(\.id))
        guard store.inputCalibrations
            .filter({ retainsExistingRecord(id: $0.id, replacedBy: incomingCalibrationIDs, policy: policy) })
            .allSatisfy({ availableProfileIDs.contains($0.profileID) }) else {
            throw NFDataArchiveRestoreError.invalidArchive(
                "the selected conflict policy would retain an input calibration whose profile is removed"
            )
        }
        guard (archive.adaptivePlanHistory?.count ?? 0) <= NFAdaptivePlanHistoryRepository.maximumRecordCount,
              (archive.adaptivePlanHistory ?? []).allSatisfy({
            $0.schemaVersion == NFAdaptivePlanChangeRecord.schemaVersion
                && availableProfileIDs.contains($0.profileID)
        }) else {
            throw NFDataArchiveRestoreError.invalidArchive("adaptive history uses an unsupported schema")
        }
        let incomingHistoryIDs = Set((archive.adaptivePlanHistory ?? []).map(\.id))
        guard store.adaptivePlanHistory
            .filter({ retainsExistingRecord(id: $0.id, replacedBy: incomingHistoryIDs, policy: policy) })
            .allSatisfy({ availableProfileIDs.contains($0.profileID) }) else {
            throw NFDataArchiveRestoreError.invalidArchive(
                "the selected conflict policy would retain adaptive history whose profile is removed"
            )
        }
    }

    /// Preview has no merge policy yet, so it reports whether the archive can
    /// be merged with the destination. A concrete replace-all restore is more
    /// restrictive because every destination-only referenced record is about
    /// to be removed.
    private static func availableReferenceIDs<ID: Hashable>(
        incoming: Set<ID>,
        existing: Set<ID>,
        policy: NFDataArchiveRestorePolicy?
    ) -> Set<ID> {
        policy == .replaceAll ? incoming : incoming.union(existing)
    }

    /// Whether a destination record survives the selected merge operation.
    /// Replace-matching deletes only records whose own identity is supplied by
    /// the archive; replace-all deletes every destination record.
    private static func retainsExistingRecord<ID: Hashable>(
        id: ID,
        replacedBy incomingIDs: Set<ID>,
        policy: NFDataArchiveRestorePolicy?
    ) -> Bool {
        switch policy {
        case .replaceAll:
            false
        case .replaceMatching:
            !incomingIDs.contains(id)
        case .abortOnConflict, .keepExisting, nil:
            true
        }
    }

    // MARK: Preview

    private static func makePreview(
        _ archive: NFDataExportService.Archive,
        store: AppStore
    ) -> NFDataArchiveRestorePreview {
        let incoming = counts(for: archive)
        let conflicts = NFDataArchiveRecordCounts(values: [
            .profile: archive.profile != nil && store.profile != nil ? 1 : 0,
            .attempts: overlap(archive.attempts.map(\.id), store.attempts.map(\.id)),
            .reflections: overlap(archive.attemptReflections.map(\.id), store.attemptReflections.map(\.id)),
            .documents: overlap(archive.documents.map(\.id), store.documents.map(\.id)),
            .sourceChunks: overlap(archive.sourceChunks.map(\.id), store.sourceChunks.map(\.id)),
            .generatedSets: overlap(archive.aiGenerations.map(\.id), store.aiGenerations.map(\.id)),
            .checkpoints: overlap(archive.sessionCheckpoints.map(\.id), store.sessionCheckpoints.map(\.id)),
            .dailyPlans: overlap(archive.dailyPlans.map(\.id), store.dailyPlans.map(\.id)),
            .calibrations: overlap(archive.inputCalibrations.map(\.id), store.inputCalibrations.map(\.id)),
            .annotations: overlap(archive.progressAnnotations.map(\.id), store.progressAnnotations.map(\.id)),
            .weeklyMission: archive.weeklyTransferState != nil && store.weeklyTransferStateRecord != nil ? 1 : 0,
            .reassessment: archive.reassessmentState != nil && store.reassessmentStateRecord != nil ? 1 : 0,
            .adaptiveHistory: overlap((archive.adaptivePlanHistory ?? []).map(\.id), store.adaptivePlanHistory.map(\.id)),
            .reports: overlap(archive.quarantinedReports.map(\.id), store.itemReports.map(\.id))
        ])
        var warnings: [String] = []
        if !archive.documents.isEmpty {
            warnings.append(NFAppLocalization.localized(
                "Source text and citations can be restored, but original PDF, image, and document formatting is not embedded in this JSON archive.",
                locale: NFAppLocalization.preferredLocale,
                comment: "Archive restore preview warning about reconstructed imported sources."
            ))
        }
        if archive.excludedPrivateAnnotationCount > 0 {
            warnings.append(NFAppLocalization.formattedExcludedPrivateNoteWarning(
                archive.excludedPrivateAnnotationCount
            ))
        }
        return NFDataArchiveRestorePreview(
            archiveVersion: archive.archiveVersion,
            exportedAt: archive.exportedAt,
            appVersion: archive.appVersion,
            incoming: incoming,
            conflicts: conflicts,
            excludedPrivateAnnotationCount: archive.excludedPrivateAnnotationCount,
            warnings: warnings
        )
    }

    private static func counts(for archive: NFDataExportService.Archive) -> NFDataArchiveRecordCounts {
        NFDataArchiveRecordCounts(values: [
            .profile: archive.profile == nil ? 0 : 1,
            .attempts: archive.attempts.count,
            .reflections: archive.attemptReflections.count,
            .documents: archive.documents.count,
            .sourceChunks: archive.sourceChunks.count,
            .generatedSets: archive.aiGenerations.count,
            .checkpoints: archive.sessionCheckpoints.count,
            .dailyPlans: archive.dailyPlans.count,
            .calibrations: archive.inputCalibrations.count,
            .annotations: archive.progressAnnotations.count,
            .weeklyMission: archive.weeklyTransferState == nil ? 0 : 1,
            .reassessment: archive.reassessmentState == nil ? 0 : 1,
            .adaptiveHistory: archive.adaptivePlanHistory?.count ?? 0,
            .reports: archive.quarantinedReports.count
        ])
    }

    private static func overlap<Value: Hashable>(_ lhs: [Value], _ rhs: [Value]) -> Int {
        Set(lhs).intersection(rhs).count
    }

    private static func emptyCounts() -> [NFDataArchiveCategory: Int] {
        Dictionary(uniqueKeysWithValues: NFDataArchiveCategory.allCases.map { ($0, 0) })
    }

    // MARK: Record construction

    private static func makeProfile(_ payload: NFDataExportService.Profile) -> UserProfileRecord {
        var draft = OnboardingDraft()
        draft.stage = Stage(rawValue: payload.stage) ?? .undisclosed
        draft.fields = Set(payload.fields.compactMap(STEMField.init(rawValue:)))
        draft.goals = Set(payload.goals.compactMap(TrainingGoal.init(rawValue:)))
        draft.dailyDuration = payload.dailyDuration
        draft.timingMode = TimingMode(rawValue: payload.timingMode) ?? .adaptive
        draft.aiMode = AIMode(rawValue: payload.aiMode) ?? .automatic
        draft.iCloudEnabled = payload.iCloudEnabled
        draft.reducedMotion = payload.reducedMotion
        draft.hideTimers = payload.hideTimers
        draft.excludeVisualSpatial = payload.excludeVisualSpatial
        draft.preferredLanguageCode = payload.preferredLanguageCode
        draft.trainingDays = Set(payload.trainingDays.compactMap(Int.init))
        draft.dayBoundaryHour = payload.dayBoundaryHour
        draft.claimsPolicyAcknowledgedVersion = payload.claimsPolicyAcknowledgedVersion
        draft.ageBandAcknowledged16Plus = payload.ageBandAcknowledged16Plus
        draft.preferredAnswerMode = NFPreferredAnswerMode(rawValue: payload.preferredAnswerMode) ?? .adaptive
        draft.reinforcementHapticsEnabled = payload.reinforcementHapticsEnabled
        draft.reinforcementSoundEnabled = payload.reinforcementSoundEnabled
        let record = UserProfileRecord(draft: draft)
        record.id = payload.id
        record.createdAt = payload.createdAt
        record.modifiedAt = payload.modifiedAt
        record.onboardingVersion = payload.onboardingVersion
        record.pccConsentVersion = payload.pccConsentVersion
        record.pccConsentAt = payload.pccConsentAt
        return record
    }

    private static func makeAttempt(_ p: NFDataExportService.Attempt) -> AttemptRecord {
        let record = AttemptRecord(
            sessionID: p.sessionID,
            lab: TrainingLab(rawValue: p.lab) ?? .mentalMath,
            itemID: p.itemID,
            prompt: p.prompt,
            response: p.response,
            correctAnswer: p.correctAnswer,
            isCorrect: p.isCorrect,
            confidence: p.confidence.flatMap(ConfidenceLevel.init(rawValue:)) ?? .uncertain,
            evidenceClass: EvidenceClass(rawValue: p.evidenceClass) ?? .practice,
            source: SessionSource(rawValue: p.sessionSource) ?? .focused,
            sourceDocumentIDs: p.sourceDocumentIDs.compactMap(UUID.init(uuidString:)),
            sourceChunkIDs: p.sourceChunkIDs,
            responseFormat: p.responseFormat
        )
        record.id = p.id
        record.templateID = p.templateID
        record.seed = p.seed
        record.skillID = p.skillID
        record.skillWeightsRaw = encodedJSONString(p.skillWeights)
        record.domainContextRaw = p.domainContext
        record.transferBriefRaw = encodedJSONString(p.transferBrief)
        record.spatialDifficultyParametersRaw = encodedJSONString(p.spatialDifficultyParameters)
        record.correctAnswer = Double(p.correctAnswer) ?? 0
        record.correctAnswerText = p.correctAnswer
        record.confidenceRaw = p.confidence
        record.shownAt = p.shownAt
        record.submittedAt = p.submittedAt
        record.activeDurationSeconds = p.activeDurationSeconds
        record.evidenceWeight = p.evidenceWeight
        record.errorCode = p.errorCode
        record.scoringVersion = p.scoringVersion
        record.deviceID = p.deviceID
        record.generationID = p.generationID
        record.wasSkipped = p.wasSkipped
        record.validationVersion = p.validationVersion
        record.assessmentBlockRaw = p.assessmentBlock
        record.planID = p.planID
        record.planBlockID = p.planBlockID
        record.deterministicCredit = p.deterministicCredit
        record.hintCount = p.hintCount
        record.inputModeRaw = p.inputMode
        record.interruptionCount = p.interruptionCount
        record.revisionCount = p.revisionCount
        record.accommodationFlagsRaw = p.accommodationFlags.joined(separator: ",")
        record.wasTimed = p.wasTimed
        record.assessmentDescriptorID = p.assessmentDescriptorID
        record.assessmentTemplateFamily = p.assessmentTemplateFamily
        record.assessmentFormatRaw = p.assessmentFormat
        record.assessmentMechanicID = p.assessmentMechanicID
        record.assessmentSubskillID = p.assessmentSubskillID
        record.assessmentSeed = p.assessmentSeed
        record.assessmentCycle = p.assessmentCycle
        return record
    }

    private static func makeReflection(_ p: NFDataExportService.AttemptReflection) -> AttemptReflectionRecord {
        let record = AttemptReflectionRecord(
            attemptID: p.attemptID,
            deterministicErrorCode: p.deterministicErrorCode,
            selectedErrorCode: p.selectedErrorCode.flatMap(NFErrorReflectionCode.init(rawValue:)),
            trigger: NFAttemptReflectionTrigger(rawValue: p.trigger) ?? .highConfidenceError,
            note: p.note,
            createdAt: p.createdAt
        )
        record.id = p.id
        record.policyVersion = p.policyVersion
        return record
    }

    private static func makeDocument(_ p: NFDataExportService.Document) -> SourceDocumentRecord {
        let record = SourceDocumentRecord(
            filename: p.filename,
            typeIdentifier: p.typeIdentifier,
            sizeBytes: p.sizeBytes,
            localPath: ""
        )
        record.id = p.id
        record.importedAt = p.importedAt
        record.indexState = p.indexState
        record.aiPolicyRaw = p.aiPolicy
        record.syncPolicy = p.syncPolicy
        record.pccExcerptConsentPolicyVersion = p.pccExcerptConsentPolicyVersion
        record.pccExcerptConsentDocumentIDRaw = p.pccExcerptConsentDocumentID
        record.pccExcerptConsentedAt = p.pccExcerptConsentedAt
        record.characterCount = p.characterCount
        record.chunkCount = p.chunkCount
        record.extractionVersion = p.extractionVersion
        record.csvSelectedColumnIDsRaw = p.csvSelectedColumnIDs.joined(separator: "\u{001F}")
        record.indexError = p.indexError
        record.modifiedAt = p.importedAt
        return record
    }

    private static func makeChunk(_ p: NFDataExportService.Chunk) -> SourceChunkRecord {
        SourceChunkRecord(chunk: NFSourceChunk(
            id: p.id,
            documentID: p.documentID,
            documentVersion: p.documentVersion,
            sourceName: p.sourceName,
            locator: NFSourceLocator(page: p.page, lineStart: p.lineStart, lineEnd: p.lineEnd, section: p.section),
            text: p.text,
            contentHash: p.contentHash,
            ordinal: p.ordinal,
            characterStart: p.characterStart,
            characterEnd: p.characterEnd,
            nearbyHeading: p.nearbyHeading,
            language: p.language,
            contentTypeTags: p.contentTypeTags
        ))
    }

    private static func makeGeneration(_ p: NFDataExportService.Generation) throws -> AIGenerationRecord {
        let route = NFAIRoute(rawValue: p.route) ?? .deterministicFallback
        let status = p.validationStatus ?? NFAuthoringValidationStatus(
            level: route == .onDevice
                ? .deterministicKeyWithModelContext
                : (p.isFallback ? .deterministicKey : (p.sourceChunkIDs.isEmpty ? .schemaCheckedModelOutput : .sourceLinkedModelOutput)),
            sourceSupport: p.sourceChunkIDs.isEmpty ? .notApplicable : .lexicalOverlap
        )
        let provenance = NFAIGenerationProvenance(
            requestID: p.id,
            generatedAt: p.createdAt,
            route: route,
            routeReason: p.routeReason,
            promptVersion: p.promptVersion,
            modelIdentifier: p.modelIdentifier,
            sourceChunkIDs: p.sourceChunkIDs,
            sourceDocumentIDs: p.sourceDocumentIDs.compactMap(UUID.init(uuidString:)),
            validationVersion: p.validationVersion,
            repairCount: p.repairCount,
            cacheKey: p.cacheKey,
            isFallback: p.isFallback
        )
        let result = NFAuthoringResult(
            questions: p.questions,
            provenance: provenance,
            routeCandidates: p.routeCandidates ?? [],
            validationStatus: status,
            validationNotes: p.validationNotes ?? [NFAppLocalization.localized(
                "Restored from a validated NeuroForge archive.",
                locale: NFAppLocalization.preferredLocale,
                comment: "Validation note attached to a legacy generated set restored from an archive."
            )]
        )
        let request = NFAuthoringRequest(
            id: p.id,
            capability: NFAICapability(rawValue: p.capability) ?? .contextualize,
            lab: TrainingLab(rawValue: p.lab) ?? .mentalMath,
            field: STEMField(rawValue: p.field) ?? .general,
            customTopic: p.topic,
            learningObjective: p.topic,
            style: p.questions.first?.style ?? .shortAnswer,
            difficulty: p.questions.first?.difficulty ?? 0.5,
            count: max(1, p.questionCount),
            seed: AdaptiveEngine.fnv1a64("restore|\(p.id.uuidString)"),
            aiMode: p.isFallback ? .disabled : .automatic,
            allowsShortcutAuthoring: route == .externalShortcut || route == .shortcutsAppleIntelligence
        )
        let record = try AIGenerationRecord(
            request: request,
            result: result,
            payloadTTL: max(0, p.payloadExpiresAt.timeIntervalSince(p.createdAt))
        )
        record.questionCount = p.questionCount
        record.payloadExpiresAt = p.payloadExpiresAt
        if p.questions.isEmpty { record.resultPayload = Data() }
        return record
    }

    private static func makeCheckpoint(_ p: NFDataExportService.Checkpoint) -> SessionCheckpointRecord {
        let record = SessionCheckpointRecord(
            sessionID: p.sessionID,
            lab: TrainingLab(rawValue: p.lab) ?? .mentalMath,
            source: SessionSource(rawValue: p.source) ?? .focused,
            seed: p.seed,
            currentIndex: p.currentIndex,
            itemCount: p.itemCount,
            response: p.response,
            scratchpad: p.scratchpad,
            results: p.results.map { $0 == "1" || $0.lowercased() == "true" },
            credits: p.credits.compactMap(Double.init),
            assessmentDescriptorIDs: p.assessmentDescriptorIDs,
            assessmentEvents: p.assessmentEvents,
            evidenceClass: EvidenceClass(rawValue: p.evidenceClass) ?? .practice,
            planID: p.planID,
            planBlockID: p.planBlockID,
            recommendationRationale: p.recommendationRationale,
            assessmentBlock: p.assessmentBlock.flatMap(NFAssessmentBlockKind.init(rawValue:)),
            assessmentCycle: p.assessmentCycle,
            activeDurationSeconds: p.activeDurationSeconds,
            assessmentStopReason: p.assessmentStopReason.flatMap(NFAssessmentStopReason.init(rawValue:)),
            pendingReflectionAttemptID: p.pendingReflectionAttemptID,
            reflectionTrigger: p.reflectionTrigger.flatMap(NFAttemptReflectionTrigger.init(rawValue:)),
            selectedReflectionCode: p.selectedReflectionCode.flatMap(NFErrorReflectionCode.init(rawValue:)),
            reflectionNote: p.reflectionNote,
            hasCommittedCurrentItem: p.hasCommittedCurrentItem,
            isComplete: p.isComplete
        )
        record.id = p.id
        record.updatedAt = p.updatedAt
        return record
    }

    private static func makeDailyPlan(_ p: NFDataExportService.DailyPlan) throws -> DailyPlanRecord {
        guard let data = Data(base64Encoded: p.canonicalPayloadBase64),
              let plan = try? JSONDecoder().decode(NFCanonicalDailyPlan.self, from: data) else {
            throw NFDataArchiveRestoreError.invalidArchive("a daily-plan payload cannot be decoded")
        }
        let context = NFPlanBoundaryContext(
            evaluatedAt: p.createdAt,
            timeZoneIdentifier: p.timeZoneIdentifier,
            utcOffsetSeconds: p.utcOffsetSeconds,
            dayBoundaryHour: p.dayBoundaryHour,
            boundaryStart: p.boundaryStart,
            nextBoundary: p.nextBoundaryAt
        )
        let record = try DailyPlanRecord(plan: plan, boundaryContext: context)
        record.payload = data
        record.travelPreservedUntil = p.travelPreservedUntil
        return record
    }

    private static func makeCalibration(_ p: NFDataExportService.InputCalibration) -> InputCalibrationRecord {
        let record = InputCalibrationRecord(
            profileID: p.profileID,
            completedAt: p.completedAt,
            preferredAnswerMode: NFPreferredAnswerMode(rawValue: p.preferredAnswerMode) ?? .adaptive,
            keyboardLatencyMilliseconds: p.keyboardLatencyMilliseconds,
            touchLatencyMilliseconds: p.touchLatencyMilliseconds,
            pencilLatencyMilliseconds: p.pencilLatencyMilliseconds
        )
        record.id = p.id
        return record
    }

    private static func makeAnnotation(_ p: NFDataExportService.ProgressAnnotation) -> ProgressAnnotationRecord {
        let record = ProgressAnnotationRecord(
            id: p.id,
            startDate: p.startDate,
            endDate: p.endDate,
            note: p.note,
            includeInExport: true
        )
        record.createdAt = p.createdAt
        record.modifiedAt = p.modifiedAt
        return record
    }

    private static func makeReport(_ p: NFDataExportService.Report) -> ItemReportRecord {
        let item = MentalMathItem(
            id: p.itemID,
            templateID: p.templateID,
            seed: p.seed,
            kind: .multiplication,
            prompt: p.prompt,
            context: "",
            answer: 0,
            tolerance: 0,
            strategy: "",
            decisiveStep: "",
            difficulty: 0.5,
            evidenceClass: .practice
        )
        let record = ItemReportRecord(item: item, reason: p.reason, note: p.note)
        record.id = p.id
        record.createdAt = p.createdAt
        record.status = p.status
        record.generatorVersion = p.generatorVersion
        record.provenanceSummary = p.provenanceSummary
        record.sourceIDsRaw = p.sourceIDs.joined(separator: ",")
        record.sourceChunkIDsRaw = p.sourceChunkIDs.joined(separator: ",")
        record.assessmentDescriptorID = p.assessmentDescriptorID
        record.diagnosticPayloadState = p.diagnosticPayloadState
        record.diagnosticDigest = p.diagnosticDigest
        if let diagnostic = p.authoredDiagnostic, let data = try? diagnostic.encoded() {
            record.diagnosticPayload = data
        }
        return record
    }

    private static func encodedJSONString<Value: Encodable>(_ value: Value?) -> String {
        guard let value, let data = try? JSONEncoder().encode(value) else { return "" }
        return String(data: data, encoding: .utf8) ?? ""
    }

    // MARK: Conflict deletion

    private static func deleteAllModelRecords(from store: AppStore) {
        for record in store.attempts { store.context.delete(record) }
        for record in store.attemptReflections { store.context.delete(record) }
        for record in store.itemReports { store.context.delete(record) }
        for record in store.sourceChunks { store.context.delete(record) }
        for record in store.aiGenerations { store.context.delete(record) }
        for record in store.sessionCheckpoints { store.context.delete(record) }
        for record in store.dailyPlans { store.context.delete(record) }
        for record in store.inputCalibrations { store.context.delete(record) }
        for record in store.progressAnnotations { store.context.delete(record) }
        for record in store.documents { store.context.delete(record) }
        if let record = store.weeklyTransferStateRecord { store.context.delete(record) }
        if let record = store.reassessmentStateRecord { store.context.delete(record) }
        if let record = store.profile { store.context.delete(record) }
    }

    private static func deleteMatchingModelRecords(
        in archive: NFDataExportService.Archive,
        from store: AppStore
    ) {
        delete(store.attempts, IDs: Set(archive.attempts.map(\.id)), context: store.context)
        delete(store.attemptReflections, IDs: Set(archive.attemptReflections.map(\.id)), context: store.context)
        delete(store.documents, IDs: Set(archive.documents.map(\.id)), context: store.context)
        delete(store.sourceChunks, IDs: Set(archive.sourceChunks.map(\.id)), context: store.context)
        delete(store.aiGenerations, IDs: Set(archive.aiGenerations.map(\.id)), context: store.context)
        delete(store.sessionCheckpoints, IDs: Set(archive.sessionCheckpoints.map(\.id)), context: store.context)
        delete(store.dailyPlans, IDs: Set(archive.dailyPlans.map(\.id)), context: store.context)
        delete(store.inputCalibrations, IDs: Set(archive.inputCalibrations.map(\.id)), context: store.context)
        delete(store.progressAnnotations, IDs: Set(archive.progressAnnotations.map(\.id)), context: store.context)
        delete(store.itemReports, IDs: Set(archive.quarantinedReports.map(\.id)), context: store.context)
        if archive.profile != nil, let record = store.profile { store.context.delete(record) }
        if archive.weeklyTransferState != nil, let record = store.weeklyTransferStateRecord { store.context.delete(record) }
        if archive.reassessmentState != nil, let record = store.reassessmentStateRecord { store.context.delete(record) }
    }

    private static func delete<Record: PersistentModel, ID: Hashable>(
        _ records: [Record],
        IDs: Set<ID>,
        context: ModelContext
    ) where Record: Identifiable, Record.ID == ID {
        for record in records where IDs.contains(record.id) { context.delete(record) }
    }
}

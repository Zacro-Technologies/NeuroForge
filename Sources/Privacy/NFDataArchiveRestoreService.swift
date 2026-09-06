import Foundation
import SwiftData
import CryptoKit

/// Held for the entire application launch, before deletion gates, migration or
/// any store open. The kernel releases the lock on process exit, so a staged
/// restore cannot run in a second process while the original runtime still owns
/// CloudKit or asynchronous file workers. The file contains no user data.
final class NFApplicationStoreLease: @unchecked Sendable {
    private let descriptor: Int32
    enum Failure: Error { case busy, unavailable }

    init(applicationSupportURL: URL? = nil) throws {
        let support = try applicationSupportURL ?? FileManager.default.url(for: .applicationSupportDirectory,
            in: .userDomainMask, appropriateFor: nil, create: true)
        try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        let url = support.appendingPathComponent("NeuroForgeStoreAccess.lock")
        let opened = Darwin.open(url.path, O_CREAT | O_RDWR | O_NOFOLLOW | O_NONBLOCK, 0o600)
        guard opened >= 0 else { throw Failure.unavailable }
        var metadata = stat()
        guard fstat(opened, &metadata) == 0, metadata.st_mode & S_IFMT == S_IFREG,
              metadata.st_nlink == 1, fchmod(opened, 0o600) == 0 else {
            Darwin.close(opened); throw Failure.unavailable
        }
        guard flock(opened, LOCK_EX | LOCK_NB) == 0 else {
            let blocked = errno == EWOULDBLOCK || errno == EAGAIN
            Darwin.close(opened)
            throw blocked ? Failure.busy : Failure.unavailable
        }
        descriptor = opened
    }

    deinit { flock(descriptor, LOCK_UN); Darwin.close(descriptor) }
}

/// Restore artifacts are private and shared across account namespaces because
/// the local-derived database and managed source directory are shared too.
enum NFRestoreJournalLocation {
    static let folderName = "NeuroForge/RestoreTransactions"
    static func root(applicationSupportURL: URL? = nil) throws -> URL {
        let support = try applicationSupportURL ?? FileManager.default.url(for: .applicationSupportDirectory,
            in: .userDomainMask, appropriateFor: nil, create: false)
        return support.appending(path: folderName, directoryHint: .isDirectory)
    }

    /// Whole-device deletion already has durable intent and stopped writers.
    /// Remove unknown and interrupted artifacts too; decoding is not necessary
    /// to remove all local private material authorized by that intent.
    static func purgeAllApplicationState(fileManager: FileManager = .default,
                                        applicationSupportURL: URL) throws {
        for url in [try root(applicationSupportURL: applicationSupportURL),
                    NFRestoreRequestStore.root(applicationSupportURL: applicationSupportURL)] {
        var metadata = stat()
        if lstat(url.path, &metadata) == 0 { try fileManager.removeItem(at: url) }
        else if errno != ENOENT { throw NFRestoreJournalError.ioFailure }
        guard lstat(url.path, &metadata) != 0, errno == ENOENT else {
            throw NFRestoreJournalError.ioFailure
        }
        }
    }
}

struct NFRestoreStartupBlock: Equatable, Sendable {
    enum Reason: String, Sendable { case unfinished, cleanupRequired, unverified, reviewChanged, restartRequired, wrongAccount }
    let reason: Reason
}

enum NFRestoreStartupResolution: Equatable, Sendable {
    case clear
    case blocked(NFRestoreStartupBlock)
    var block: NFRestoreStartupBlock? { if case let .blocked(value) = self { value } else { nil } }
    var permitsModelContainerOpen: Bool { self == .clear }
}

enum NFRestoreStartupGate {
    /// No payload or account identifier is exposed to startup UI. A current
    /// completed receipt releases the fence; an unknown or incomplete artifact
    /// never falls through to an ordinary writable runtime.
    static func inspect(applicationSupportURL: URL? = nil) async -> NFRestoreStartupResolution {
        do {
            let root = try NFRestoreJournalLocation.root(applicationSupportURL: applicationSupportURL)
            var metadata = stat()
            guard lstat(root.path, &metadata) == 0 else {
                if errno == ENOENT { return .clear }
                return .blocked(.init(reason: .unverified))
            }
            guard metadata.st_mode & S_IFMT == S_IFDIR else { return .blocked(.init(reason: .unverified)) }
            let journal = NFDataArchiveRestoreJournal(root: root)
            let entries = try await journal.inspectAllNamespaces()
            if entries.contains(where: { $0.isStaging || [.accepted, .mutationMayHaveStarted, .recoveryRequired].contains($0.progress?.phase) }) {
                return .blocked(.init(reason: .unfinished))
            }
            if entries.contains(where: { $0.progress?.phase == .invalidated }) {
                return .blocked(.init(reason: .cleanupRequired))
            }
            guard entries.allSatisfy({ [.verifiedComplete, .cleaned].contains($0.progress?.phase) }) else {
                return .blocked(.init(reason: .unverified))
            }
            for entry in entries where entry.progress?.phase == .verifiedComplete {
                guard let descriptor = entry.descriptor else { return .blocked(.init(reason: .unverified)) }
                _ = try await journal.load(transactionID: descriptor.transactionID, namespace: descriptor.namespace,
                    installationOwnerID: descriptor.installationOwnerID)
            }
            return .clear
        } catch { return .blocked(.init(reason: .unverified)) }
    }
}

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

    /// Cold-start preview can account for private content without AppStore.
    /// These values are UI-only, not a persisted archive or migration schema.
    var localIncoming: [String: Int] = [:]
    var localConflicts: [String: Int] = [:]
    var hasConflicts: Bool { conflicts.total > 0 || localConflicts.values.contains(where: { $0 > 0 }) }
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
    case ambiguousDestinationRecords
    case requiresStagedRestore

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
        case .ambiguousDestinationRecords:
            NFAppLocalization.localized(
                "Some saved records have conflicting identities. Restore is paused to preserve every original record. Your backup and saved data have not been changed.",
                locale: NFAppLocalization.preferredLocale,
                comment: "Archive restore refuses ambiguous raw destination records before any mutation."
            )
        case .persistenceFailed:
            NFAppLocalization.localized(
                "The restore could not be verified. Keep the original backup and review your saved records before trying again.",
                locale: NFAppLocalization.preferredLocale,
                comment: "Unverified archive restore; no cross-store rollback guarantee is claimed."
            )
        case .requiresStagedRestore:
            NFAILearningCopy.text(
                "Restore this backup from Settings so saved AI explanations and evaluations are included in the verified restart transaction.",
                "保存したAIの解説と評価を再起動時に検証して復元するため、設定からこのバックアップを復元してください。"
            )
        }
    }
}

/// Exact immutable decode result. Preview and commit use the same bytes even
/// when the selected external file changes or loses its security-scoped lease.
struct NFPreparedDataArchive: Sendable {
    fileprivate let archive: NFDataExportService.Archive
    let sourceDigest: String
    let sourceByteCount: Int
    let sourceFilename: String
}

enum NFDataArchiveReadBoundary {
    static func boundedData(at url: URL) throws -> Data {
        let maximum = NFLocalSessionRepository.maximumBytes
        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? Int.max
        guard size <= maximum else { throw NFDataArchiveRestoreError.invalidArchive("archive size limit") }
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var result = Data()
        while result.count <= maximum {
            try Task.checkCancellation()
            let remaining = maximum + 1 - result.count
            let chunk = try handle.read(upToCount: min(1_048_576, remaining)) ?? Data()
            if chunk.isEmpty { return result }
            result.append(chunk)
            if result.count > maximum { throw NFDataArchiveRestoreError.invalidArchive("archive size limit") }
        }
        throw NFDataArchiveRestoreError.invalidArchive("archive size limit")
    }
}

/// A restore must inspect physical rows, including records hidden by normal
/// winner projections. Capture once, before any side-store write, and keep this
/// exact membership through validation and deletion. This is not a crash journal
/// or a cross-process write fence.
@MainActor
private struct NFDataArchiveDestinationCensus {
    let profiles: [UserProfileRecord]
    let attempts: [AttemptRecord]
    let attemptReflections: [AttemptReflectionRecord]
    let documents: [SourceDocumentRecord]
    let sourceChunks: [SourceChunkRecord]
    let aiGenerations: [AIGenerationRecord]
    let sessionCheckpoints: [SessionCheckpointRecord]
    let dailyPlans: [DailyPlanRecord]
    let inputCalibrations: [InputCalibrationRecord]
    let progressAnnotations: [ProgressAnnotationRecord]
    let weeklyTransferStates: [WeeklyTransferStateRecord]
    let reassessmentStates: [ReassessmentStateRecord]
    let itemReports: [ItemReportRecord]
    var profile: UserProfileRecord? { profiles.first }
    var weeklyTransferStateRecord: WeeklyTransferStateRecord? { weeklyTransferStates.first }
    var reassessmentStateRecord: ReassessmentStateRecord? { reassessmentStates.first }

    init(context: ModelContext) throws {
        profiles = try context.fetch(FetchDescriptor<UserProfileRecord>())
        attempts = try context.fetch(FetchDescriptor<AttemptRecord>())
        attemptReflections = try context.fetch(FetchDescriptor<AttemptReflectionRecord>())
        documents = try context.fetch(FetchDescriptor<SourceDocumentRecord>())
        sourceChunks = try context.fetch(FetchDescriptor<SourceChunkRecord>())
        aiGenerations = try context.fetch(FetchDescriptor<AIGenerationRecord>())
        sessionCheckpoints = try context.fetch(FetchDescriptor<SessionCheckpointRecord>())
        dailyPlans = try context.fetch(FetchDescriptor<DailyPlanRecord>())
        inputCalibrations = try context.fetch(FetchDescriptor<InputCalibrationRecord>())
        progressAnnotations = try context.fetch(FetchDescriptor<ProgressAnnotationRecord>())
        weeklyTransferStates = try context.fetch(FetchDescriptor<WeeklyTransferStateRecord>())
        reassessmentStates = try context.fetch(FetchDescriptor<ReassessmentStateRecord>())
        itemReports = try context.fetch(FetchDescriptor<ItemReportRecord>())
        // Neither deleting a projected winner nor silently keeping a duplicate
        // is a valid resolution. Preserve raw originals until a recovery flow
        // can present and reconcile the complete identity group.
        guard profiles.count <= 1, weeklyTransferStates.count <= 1, reassessmentStates.count <= 1,
              Self.isUnique(attempts.map(\.id)),
              Self.isUnique(attemptReflections.map(\.id)),
              Self.isUnique(documents.map(\.id)),
              Self.isUnique(sourceChunks.map(\.id)),
              Self.isUnique(aiGenerations.map(\.id)),
              Self.isUnique(sessionCheckpoints.map(\.id)),
              Self.isUnique(dailyPlans.map(\.id)),
              Self.isUnique(inputCalibrations.map(\.id)),
              Self.isUnique(progressAnnotations.map(\.id)),
              Self.isUnique(itemReports.map(\.id)),
              Self.isUnique(attemptReflections.map(\.attemptID)),
              Self.isUnique(sessionCheckpoints.map(\.sessionID)) else {
            throw NFDataArchiveRestoreError.ambiguousDestinationRecords
        }
    }

    private static func isUnique<ID: Hashable>(_ identities: [ID]) -> Bool {
        Set(identities).count == identities.count
    }
}

/// Versioned, preview-first restore for the full JSON export. Immutable decode
/// and semantic validation precede live mutation. Current predecessor repair is
/// an in-process compatibility path, not a durable multi-store transaction.
/// MIG-007 still requires the staged journal and startup recovery fence described
/// in Restore_Recovery_Design.md; this service must not promise crash rollback.
@MainActor
enum NFDataArchiveRestoreService {
    static func prepare(archiveAt url: URL) async throws -> NFPreparedDataArchive {
        let worker = Task.detached(priority: .userInitiated) {
            try Task.checkCancellation()
            let value = try decodedPreparedArchive(at: url)
            try Task.checkCancellation()
            return value
        }
        return try await withTaskCancellationHandler(operation: {
            let value = try await worker.value
            try Task.checkCancellation()
            return value
        }, onCancel: { worker.cancel() })
    }

    static func preview(archiveAt url: URL, into store: AppStore) throws -> NFDataArchiveRestorePreview {
        try preview(prepared: decodedPreparedArchive(at: url), into: store)
    }

    static func preview(prepared: NFPreparedDataArchive, into store: AppStore) throws -> NFDataArchiveRestorePreview {
        let census = try NFDataArchiveDestinationCensus(context: store.context)
        try validate(prepared.archive, existingStore: store, census: census, policy: nil)
        return makePreview(prepared.archive, store: store, census: census)
    }

    static func restore(
        archiveAt url: URL, into store: AppStore, policy: NFDataArchiveRestorePolicy,
        corePersistence: ((ModelContext) throws -> Void)? = nil
    ) throws -> NFDataArchiveRestoreResult {
        try store.localSessions.requireArchiveWriteAvailability()
        guard store.activeSessionRequest == nil else { throw NFDataArchiveRestoreError.activeSession }
        return try restore(prepared: decodedPreparedArchive(at: url), into: store, policy: policy, corePersistence: corePersistence)
    }

    static func restore(
        prepared: NFPreparedDataArchive, into store: AppStore, policy: NFDataArchiveRestorePolicy,
        corePersistence: ((ModelContext) throws -> Void)? = nil
    ) throws -> NFDataArchiveRestoreResult {
        try store.localSessions.requireArchiveWriteAvailability()
        guard store.activeSessionRequest == nil else { throw NFDataArchiveRestoreError.activeSession }
        let archive = prepared.archive
        guard (archive.aiLearningArtifacts ?? []).isEmpty,
              try NFAILearningArtifactArchive.capture(at: store.localSessions.aiArtifactDirectoryURL).isEmpty else {
            throw NFDataArchiveRestoreError.requiresStagedRestore
        }
        let census = try NFDataArchiveDestinationCensus(context: store.context)
        try validate(archive, existingStore: store, census: census, policy: policy)
        let preview = makePreview(archive, store: store, census: census)
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
        let oldLocalLearning = store.localSessions.archive
        var localLearningWasWritten = false
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
                deleteAllModelRecords(from: store, census: census)
            } else if policy == .replaceMatching {
                deleteMatchingModelRecords(in: archive, from: store, census: census)
            }

            if let profile = archive.profile {
                if policy != .keepExisting || census.profile == nil {
                    context.insert(makeProfile(profile))
                    restored[.profile, default: 0] += 1
                } else {
                    skipped[.profile, default: 0] += 1
                }
            }

            let existingAttemptIDs = Set(census.attempts.map(\.id))
            for payload in archive.attempts {
                if policy == .keepExisting, existingAttemptIDs.contains(payload.id) {
                    skipped[.attempts, default: 0] += 1
                } else {
                    context.insert(makeAttempt(payload))
                    restored[.attempts, default: 0] += 1
                }
            }

            let existingReflectionIDs = Set(census.attemptReflections.map(\.id))
            let reflectedAttemptIDs = Set(census.attemptReflections.map(\.attemptID))
            for payload in archive.attemptReflections {
                if policy == .keepExisting, existingReflectionIDs.contains(payload.id) || reflectedAttemptIDs.contains(payload.attemptID) {
                    skipped[.reflections, default: 0] += 1
                } else {
                    context.insert(makeReflection(payload))
                    restored[.reflections, default: 0] += 1
                }
            }

            let existingDocumentIDs = Set(census.documents.map(\.id))
            for payload in archive.documents {
                if policy == .keepExisting, existingDocumentIDs.contains(payload.id) {
                    skipped[.documents, default: 0] += 1
                } else {
                    context.insert(makeDocument(payload))
                    restored[.documents, default: 0] += 1
                }
            }

            let existingChunkIDs = Set(census.sourceChunks.map(\.id))
            for payload in archive.sourceChunks {
                if policy == .keepExisting, existingChunkIDs.contains(payload.id) {
                    skipped[.sourceChunks, default: 0] += 1
                } else {
                    context.insert(makeChunk(payload))
                    restored[.sourceChunks, default: 0] += 1
                }
            }

            let existingGenerationIDs = Set(census.aiGenerations.map(\.id))
            for payload in archive.aiGenerations {
                if policy == .keepExisting, existingGenerationIDs.contains(payload.id) {
                    skipped[.generatedSets, default: 0] += 1
                } else {
                    context.insert(try makeGeneration(payload))
                    restored[.generatedSets, default: 0] += 1
                }
            }

            let existingCheckpointIDs = Set(census.sessionCheckpoints.map(\.id))
            let checkpointSessionIDs = Set(census.sessionCheckpoints.map(\.sessionID))
            for payload in archive.sessionCheckpoints {
                if policy == .keepExisting, existingCheckpointIDs.contains(payload.id) || checkpointSessionIDs.contains(payload.sessionID) {
                    skipped[.checkpoints, default: 0] += 1
                } else {
                    context.insert(makeCheckpoint(payload))
                    restored[.checkpoints, default: 0] += 1
                }
            }

            let existingPlanIDs = Set(census.dailyPlans.map(\.id))
            for payload in archive.dailyPlans {
                if policy == .keepExisting, existingPlanIDs.contains(payload.id) {
                    skipped[.dailyPlans, default: 0] += 1
                } else {
                    context.insert(try makeDailyPlan(payload))
                    restored[.dailyPlans, default: 0] += 1
                }
            }

            let existingCalibrationIDs = Set(census.inputCalibrations.map(\.id))
            for payload in archive.inputCalibrations {
                if policy == .keepExisting, existingCalibrationIDs.contains(payload.id) {
                    skipped[.calibrations, default: 0] += 1
                } else {
                    context.insert(makeCalibration(payload))
                    restored[.calibrations, default: 0] += 1
                }
            }

            let existingAnnotationIDs = Set(census.progressAnnotations.map(\.id))
            for payload in archive.progressAnnotations {
                if policy == .keepExisting, existingAnnotationIDs.contains(payload.id) {
                    skipped[.annotations, default: 0] += 1
                } else {
                    context.insert(makeAnnotation(payload))
                    restored[.annotations, default: 0] += 1
                }
            }

            if let state = archive.weeklyTransferState {
                if policy == .keepExisting, census.weeklyTransferStateRecord != nil {
                    skipped[.weeklyMission, default: 0] += 1
                } else {
                    context.insert(WeeklyTransferStateRecord(state: state))
                    restored[.weeklyMission, default: 0] += 1
                }
            }
            if let state = archive.reassessmentState {
                if policy == .keepExisting, census.reassessmentStateRecord != nil {
                    skipped[.reassessment, default: 0] += 1
                } else {
                    context.insert(ReassessmentStateRecord(state: state))
                    restored[.reassessment, default: 0] += 1
                }
            }

            let existingReportIDs = Set(census.itemReports.map(\.id))
            for payload in archive.quarantinedReports {
                if policy == .keepExisting, existingReportIDs.contains(payload.id) {
                    skipped[.reports, default: 0] += 1
                } else {
                    context.insert(makeReport(payload))
                    restored[.reports, default: 0] += 1
                }
            }

            if let localLearning = archive.localLearning {
                try store.localSessions.importArchive(localLearning)
                localLearningWasWritten = true
                store.localSessionRevision += 1
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
            if localLearningWasWritten {
                do { try store.localSessions.restorePredecessor(oldLocalLearning) }
                catch { historyRollbackFailed = true }
                store.localSessionRevision += 1
            }
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

    nonisolated private static func decodedPreparedArchive(at url: URL) throws -> NFPreparedDataArchive {
        do {
            let original = try NFDataArchiveReadBoundary.boundedData(at: url)
            _ = try NFDataExportRoundTripValidator.decodeArchive(data: original)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let data = try NFDataArchiveMigration.normalizedData(from: original)
            let permittedData = try NFDataExportService.protectedPortableData(data, forRestore: true)
            let archive = try decoder.decode(NFDataExportService.Archive.self, from: permittedData)
            return NFPreparedDataArchive(archive: archive,
                sourceDigest: NFReservationSnapshot.digest(original), sourceByteCount: original.count,
                sourceFilename: url.lastPathComponent)
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as NFDataArchiveRestoreError {
            throw error
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
        census: NFDataArchiveDestinationCensus,
        policy: NFDataArchiveRestorePolicy?
    ) throws {
        try validate(archive, existingHistory: store.adaptivePlanHistory, census: census, policy: policy)
    }

    private static func validate(
        _ archive: NFDataExportService.Archive,
        existingHistory: [NFAdaptivePlanChangeRecord],
        census: NFDataArchiveDestinationCensus,
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

        let incomingReflectedAttemptIDs = Set(archive.attemptReflections.map(\.attemptID))
        let incomingCheckpointSessionIDs = Set(archive.sessionCheckpoints.map(\.sessionID))
        guard incomingReflectedAttemptIDs.count == archive.attemptReflections.count,
              incomingCheckpointSessionIDs.count == archive.sessionCheckpoints.count else {
            throw NFDataArchiveRestoreError.invalidArchive("multiple records describe the same reflection or session")
        }

        // A peer may assign a new physical record ID to the same domain
        // identity. It may not reuse an existing ID for a different answer or
        // run: OR-matching that crossed pair could otherwise delete two saved
        // originals while the preview describes only one incoming conflict.
        let reflectedDomainByRecordID = Dictionary(uniqueKeysWithValues: census.attemptReflections.map { ($0.id, $0.attemptID) })
        let checkpointDomainByRecordID = Dictionary(uniqueKeysWithValues: census.sessionCheckpoints.map { ($0.id, $0.sessionID) })
        guard archive.attemptReflections.allSatisfy({ incoming in
            reflectedDomainByRecordID[incoming.id].map { $0 == incoming.attemptID } ?? true
        }), archive.sessionCheckpoints.allSatisfy({ incoming in
            checkpointDomainByRecordID[incoming.id].map { $0 == incoming.sessionID } ?? true
        }) else { throw NFDataArchiveRestoreError.ambiguousDestinationRecords }

        let incomingProfileIDs = Set(archive.profile.map { [$0.id] } ?? [])
        let existingProfileIDs = Set(census.profile.map { [$0.id] } ?? [])
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
            existing: Set(census.attempts.map(\.id)),
            policy: policy
        )
        guard archive.attemptReflections.allSatisfy({ availableAttemptIDs.contains($0.attemptID) }) else {
            throw NFDataArchiveRestoreError.invalidArchive("a reflection references a missing attempt")
        }
        let incomingReflectionIDs = Set(archive.attemptReflections.map(\.id))
        guard census.attemptReflections
            .filter({ retainsExistingRecord(id: $0.id, replacedBy: incomingReflectionIDs, policy: policy)
                && (policy != .replaceMatching || !incomingReflectedAttemptIDs.contains($0.attemptID)) })
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
        guard census.sessionCheckpoints
            .filter({ retainsExistingRecord(id: $0.id, replacedBy: incomingCheckpointIDs, policy: policy)
                && (policy != .replaceMatching || !incomingCheckpointSessionIDs.contains($0.sessionID)) })
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
            existing: Set(census.documents.map(\.id)),
            policy: policy
        )
        guard archive.sourceChunks.allSatisfy({ availableDocumentIDs.contains($0.documentID) }) else {
            throw NFDataArchiveRestoreError.invalidArchive("a source chunk references a missing document")
        }
        let incomingChunkIDs = Set(archive.sourceChunks.map(\.id))
        guard census.sourceChunks
            .filter({ retainsExistingRecord(id: $0.id, replacedBy: incomingChunkIDs, policy: policy) })
            .allSatisfy({ availableDocumentIDs.contains($0.documentID) }) else {
            throw NFDataArchiveRestoreError.invalidArchive(
                "the selected conflict policy would retain a source chunk whose document is removed"
            )
        }
        let availableChunkIDs = availableReferenceIDs(
            incoming: incomingChunkIDs,
            existing: Set(census.sourceChunks.map(\.id)),
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
            if isNativeGenerationEnvelope(generation), !generation.questions.isEmpty {
                _ = try makeGeneration(generation)
            }
        }
        let incomingGenerationIDs = Set(archive.aiGenerations.map(\.id))
        guard census.aiGenerations
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
        guard census.dailyPlans
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
        guard census.inputCalibrations
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
        guard existingHistory
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
        store: AppStore,
        census: NFDataArchiveDestinationCensus
    ) -> NFDataArchiveRestorePreview {
        makePreview(archive, existingHistory: store.adaptivePlanHistory,
            ownerDeviceID: store.localSessions.ownerDeviceID, census: census,
            locale: NFAppLocalization.preferredLocale)
    }

    private static func makePreview(
        _ archive: NFDataExportService.Archive,
        existingHistory: [NFAdaptivePlanChangeRecord], ownerDeviceID: UUID?,
        census: NFDataArchiveDestinationCensus, locale: Locale
    ) -> NFDataArchiveRestorePreview {
        let incoming = counts(for: archive)
        let conflicts = NFDataArchiveRecordCounts(values: [
            .profile: archive.profile != nil && census.profile != nil ? 1 : 0,
            .attempts: overlap(archive.attempts.map(\.id), census.attempts.map(\.id)),
            .reflections: overlap(incomingIDs: archive.attemptReflections.map(\.id), incomingDomainIDs: archive.attemptReflections.map(\.attemptID),
                existingIDs: census.attemptReflections.map(\.id), existingDomainIDs: census.attemptReflections.map(\.attemptID)),
            .documents: overlap(archive.documents.map(\.id), census.documents.map(\.id)),
            .sourceChunks: overlap(archive.sourceChunks.map(\.id), census.sourceChunks.map(\.id)),
            .generatedSets: overlap(archive.aiGenerations.map(\.id), census.aiGenerations.map(\.id)),
            .checkpoints: overlap(incomingIDs: archive.sessionCheckpoints.map(\.id), incomingDomainIDs: archive.sessionCheckpoints.map(\.sessionID),
                existingIDs: census.sessionCheckpoints.map(\.id), existingDomainIDs: census.sessionCheckpoints.map(\.sessionID)),
            .dailyPlans: overlap(archive.dailyPlans.map(\.id), census.dailyPlans.map(\.id)),
            .calibrations: overlap(archive.inputCalibrations.map(\.id), census.inputCalibrations.map(\.id)),
            .annotations: overlap(archive.progressAnnotations.map(\.id), census.progressAnnotations.map(\.id)),
            .weeklyMission: archive.weeklyTransferState != nil && census.weeklyTransferStateRecord != nil ? 1 : 0,
            .reassessment: archive.reassessmentState != nil && census.reassessmentStateRecord != nil ? 1 : 0,
            .adaptiveHistory: overlap((archive.adaptivePlanHistory ?? []).map(\.id), existingHistory.map(\.id)),
            .reports: overlap(archive.quarantinedReports.map(\.id), census.itemReports.map(\.id))
        ])
        var warnings: [String] = []
        if archive.attempts.contains(where: { $0.protectedReceipt != nil }) || archive.sessionCheckpoints.contains(where: { $0.protectedReceipt != nil }) {
            warnings.append("Protected responses and notes are retained for recovery. Per-question results and unfinished protected sessions require their verified evaluator and cannot be resumed from this archive.")
        }
        if !archive.documents.isEmpty {
            warnings.append(NFAppLocalization.localized(
                "Source text and citations can be restored, but original PDF, image, and document formatting is not embedded in this JSON archive.",
                locale: locale,
                comment: "Archive restore preview warning about reconstructed imported sources."
            ))
        }
        if let local = archive.localLearning {
            let resumable = local.sessions.filter { $0.ownerDeviceID == ownerDeviceID && $0.status == .suspended }.count
            let recovery = local.sessions.filter { $0.status == .migrationRecovery || $0.ownerDeviceID != ownerDeviceID }.count
            warnings.append("Saved sessions: \(resumable) available for same-device continuation; \(recovery) retained for read-only recovery.")
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

    private static func overlap<ID: Hashable, DomainID: Hashable>(
        incomingIDs: [ID], incomingDomainIDs: [DomainID], existingIDs: [ID], existingDomainIDs: [DomainID]
    ) -> Int {
        let recordIDs = Set(existingIDs), domainIDs = Set(existingDomainIDs)
        return zip(incomingIDs, incomingDomainIDs).filter { recordIDs.contains($0.0) || domainIDs.contains($0.1) }.count
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
        // Unknown protected receipt triggers must not become inferred errors.
        record.triggerRaw = p.trigger
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

    private static func makeGeneration(_ p: NFDataExportService.Generation, locale: Locale = NFAppLocalization.preferredLocale) throws -> AIGenerationRecord {
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
                locale: locale,
                comment: "Validation note attached to a legacy generated set restored from an archive."
            )]
        )
        if isNativeGenerationEnvelope(p), !p.questions.isEmpty {
            guard NFAILearningAuthoringService.isCompatibleResult(result),
                  p.questionCount == p.questions.count,
                  p.payloadExpiresAt == .distantFuture else {
                throw NFDataArchiveRestoreError.invalidArchive("a native question set has an incompatible saved rubric, provenance, or retention contract")
            }
        }
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
            localeIdentifier: locale.identifier,
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

    private static func isNativeGenerationEnvelope(_ payload: NFDataExportService.Generation) -> Bool {
        payload.route == NFAIRoute.directCloud.rawValue
            || payload.validationStatus?.level == .rubricModelOutput
            || payload.cacheKey.hasPrefix("native-rubric|")
            || payload.questions.contains { $0.authoritativeExercise.aiRubric != nil
                || $0.authoritativeExercise.provenance.generatorID == "neuroforge.native-rubric-author" }
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
        if p.protectedReceipt != nil {
            record.assessmentStopReasonRaw = "protected_evaluator_unavailable"
        }
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

    private static func deleteAllModelRecords(from store: AppStore, census: NFDataArchiveDestinationCensus) {
        for record in census.attempts { store.context.delete(record) }
        for record in census.attemptReflections { store.context.delete(record) }
        for record in census.itemReports { store.context.delete(record) }
        for record in census.sourceChunks { store.context.delete(record) }
        for record in census.aiGenerations { store.context.delete(record) }
        for record in census.sessionCheckpoints { store.context.delete(record) }
        for record in census.dailyPlans { store.context.delete(record) }
        for record in census.inputCalibrations { store.context.delete(record) }
        for record in census.progressAnnotations { store.context.delete(record) }
        for record in census.documents { store.context.delete(record) }
        if let record = census.weeklyTransferStateRecord { store.context.delete(record) }
        if let record = census.reassessmentStateRecord { store.context.delete(record) }
        if let record = census.profile { store.context.delete(record) }
    }

    private static func deleteMatchingModelRecords(
        in archive: NFDataExportService.Archive,
        from store: AppStore,
        census: NFDataArchiveDestinationCensus
    ) {
        delete(census.attempts, IDs: Set(archive.attempts.map(\.id)), context: store.context)
        let reflectionIDs = Set(archive.attemptReflections.map(\.id))
        let reflectedAttemptIDs = Set(archive.attemptReflections.map(\.attemptID))
        for record in census.attemptReflections where reflectionIDs.contains(record.id) || reflectedAttemptIDs.contains(record.attemptID) {
            store.context.delete(record)
        }
        delete(census.documents, IDs: Set(archive.documents.map(\.id)), context: store.context)
        delete(census.sourceChunks, IDs: Set(archive.sourceChunks.map(\.id)), context: store.context)
        delete(census.aiGenerations, IDs: Set(archive.aiGenerations.map(\.id)), context: store.context)
        let checkpointIDs = Set(archive.sessionCheckpoints.map(\.id))
        let checkpointSessionIDs = Set(archive.sessionCheckpoints.map(\.sessionID))
        for record in census.sessionCheckpoints where checkpointIDs.contains(record.id) || checkpointSessionIDs.contains(record.sessionID) {
            store.context.delete(record)
        }
        delete(census.dailyPlans, IDs: Set(archive.dailyPlans.map(\.id)), context: store.context)
        delete(census.inputCalibrations, IDs: Set(archive.inputCalibrations.map(\.id)), context: store.context)
        delete(census.progressAnnotations, IDs: Set(archive.progressAnnotations.map(\.id)), context: store.context)
        delete(census.itemReports, IDs: Set(archive.quarantinedReports.map(\.id)), context: store.context)
        if archive.profile != nil, let record = census.profile { store.context.delete(record) }
        if archive.weeklyTransferState != nil, let record = census.weeklyTransferStateRecord { store.context.delete(record) }
        if archive.reassessmentState != nil, let record = census.reassessmentStateRecord { store.context.delete(record) }
    }

    private static func delete<Record: PersistentModel, ID: Hashable>(
        _ records: [Record],
        IDs: Set<ID>,
        context: ModelContext
    ) where Record: Identifiable, Record.ID == ID {
        for record in records where IDs.contains(record.id) { context.delete(record) }
    }
}

// MIG-007 building block only: no journal I/O, save(), live write fence, or
// automatic replay is supplied here. These values are PRIVATE predecessors;
// they MUST NOT enter the portable export or CloudKit payloads.
enum NFDataArchiveRawSnapshotError: Error, Equatable {
    case unsupportedVersion
    case unsupportedModel(String)
    case columnCensusMismatch(String)
    case invalidScalar(String)
    case dirtyContext
    case autosaveMustBeDisabled
    case destinationNotEmpty
    case conflictingPredecessor
    case materializationMismatch(String)
    case unrepresentableText(String)
    case oversized
}

/// Representation does not use JSON floating-point numbers or normalize text.
/// In particular -0, NaN payloads, infinities and subnormal bit patterns survive
/// journal encoding. The persistent backend may reject/canonicalize a value;
/// callers must verify the freshly fetched after-state and retain recovery.
enum NFDataArchiveRawValue: Codable, Equatable, Sendable {
    case null
    case boolean(Bool)
    case textUTF8(Data)
    case signedBits(String)
    case unsignedBits(String)
    case doubleBits(String)
    case dateReferenceIntervalBits(String)
    case uuid(UUID)
    case blob(Data)

    static func hex(_ bits: UInt64) -> String {
        let text = String(bits, radix: 16)
        return String(repeating: "0", count: 16 - text.count) + text
    }
    static func bits(_ text: String) throws -> UInt64 {
        guard text.count == 16, text.allSatisfy({ "0123456789abcdef".contains($0) }),
              let bits = UInt64(text, radix: 16) else {
            throw NFDataArchiveRawSnapshotError.invalidScalar("64-bit hexadecimal")
        }
        return bits
    }
}

protocol NFDataArchiveRawScalar {
    static var rawTypeName: String { get }
    var archiveRawValue: NFDataArchiveRawValue { get }
    static func fromArchiveRawValue(_ value: NFDataArchiveRawValue) throws -> Self
}
extension Bool: NFDataArchiveRawScalar {
    static var rawTypeName: String { "Bool" }
    var archiveRawValue: NFDataArchiveRawValue { .boolean(self) }
    static func fromArchiveRawValue(_ value: NFDataArchiveRawValue) throws -> Bool {
        guard case let .boolean(value) = value else { throw NFDataArchiveRawSnapshotError.invalidScalar(rawTypeName) }
        return value
    }
}
extension String: NFDataArchiveRawScalar {
    static var rawTypeName: String { "String" }
    var archiveRawValue: NFDataArchiveRawValue { .textUTF8(Data(utf8)) }
    static func fromArchiveRawValue(_ value: NFDataArchiveRawValue) throws -> String {
        guard case let .textUTF8(bytes) = value, let text = String(data: bytes, encoding: .utf8),
              Data(text.utf8) == bytes else { throw NFDataArchiveRawSnapshotError.invalidScalar(rawTypeName) }
        return text
    }
}
extension Int: NFDataArchiveRawScalar {
    static var rawTypeName: String { "Int" }
    var archiveRawValue: NFDataArchiveRawValue { .signedBits(NFDataArchiveRawValue.hex(UInt64(bitPattern: Int64(self)))) }
    static func fromArchiveRawValue(_ value: NFDataArchiveRawValue) throws -> Int {
        guard case let .signedBits(text) = value else { throw NFDataArchiveRawSnapshotError.invalidScalar(rawTypeName) }
        guard let value = Int(exactly: Int64(bitPattern: try NFDataArchiveRawValue.bits(text))) else {
            throw NFDataArchiveRawSnapshotError.invalidScalar(rawTypeName)
        }
        return value
    }
}
extension Int64: NFDataArchiveRawScalar {
    static var rawTypeName: String { "Int64" }
    var archiveRawValue: NFDataArchiveRawValue { .signedBits(NFDataArchiveRawValue.hex(UInt64(bitPattern: self))) }
    static func fromArchiveRawValue(_ value: NFDataArchiveRawValue) throws -> Int64 {
        guard case let .signedBits(text) = value else { throw NFDataArchiveRawSnapshotError.invalidScalar(rawTypeName) }
        return Int64(bitPattern: try NFDataArchiveRawValue.bits(text))
    }
}
extension UInt64: NFDataArchiveRawScalar {
    static var rawTypeName: String { "UInt64" }
    var archiveRawValue: NFDataArchiveRawValue { .unsignedBits(NFDataArchiveRawValue.hex(self)) }
    static func fromArchiveRawValue(_ value: NFDataArchiveRawValue) throws -> UInt64 {
        guard case let .unsignedBits(text) = value else { throw NFDataArchiveRawSnapshotError.invalidScalar(rawTypeName) }
        return try NFDataArchiveRawValue.bits(text)
    }
}
extension Double: NFDataArchiveRawScalar {
    static var rawTypeName: String { "Double" }
    var archiveRawValue: NFDataArchiveRawValue { .doubleBits(NFDataArchiveRawValue.hex(bitPattern)) }
    static func fromArchiveRawValue(_ value: NFDataArchiveRawValue) throws -> Double {
        guard case let .doubleBits(text) = value else { throw NFDataArchiveRawSnapshotError.invalidScalar(rawTypeName) }
        return Double(bitPattern: try NFDataArchiveRawValue.bits(text))
    }
}
extension Date: NFDataArchiveRawScalar {
    static var rawTypeName: String { "Date" }
    var archiveRawValue: NFDataArchiveRawValue {
        .dateReferenceIntervalBits(NFDataArchiveRawValue.hex(timeIntervalSinceReferenceDate.bitPattern))
    }
    static func fromArchiveRawValue(_ value: NFDataArchiveRawValue) throws -> Date {
        guard case let .dateReferenceIntervalBits(text) = value else { throw NFDataArchiveRawSnapshotError.invalidScalar(rawTypeName) }
        return Date(timeIntervalSinceReferenceDate: Double(bitPattern: try NFDataArchiveRawValue.bits(text)))
    }
}
extension UUID: NFDataArchiveRawScalar {
    static var rawTypeName: String { "UUID" }
    var archiveRawValue: NFDataArchiveRawValue { .uuid(self) }
    static func fromArchiveRawValue(_ value: NFDataArchiveRawValue) throws -> UUID {
        guard case let .uuid(value) = value else { throw NFDataArchiveRawSnapshotError.invalidScalar(rawTypeName) }
        return value
    }
}
extension Data: NFDataArchiveRawScalar {
    static var rawTypeName: String { "Data" }
    var archiveRawValue: NFDataArchiveRawValue { .blob(self) }
    static func fromArchiveRawValue(_ value: NFDataArchiveRawValue) throws -> Data {
        guard case let .blob(value) = value else { throw NFDataArchiveRawSnapshotError.invalidScalar(rawTypeName) }
        return value
    }
}
extension Optional: NFDataArchiveRawScalar where Wrapped: NFDataArchiveRawScalar {
    static var rawTypeName: String { Wrapped.rawTypeName + "?" }
    var archiveRawValue: NFDataArchiveRawValue { map(\.archiveRawValue) ?? .null }
    static func fromArchiveRawValue(_ value: NFDataArchiveRawValue) throws -> Optional<Wrapped> {
        if case .null = value { return nil }
        return try Wrapped.fromArchiveRawValue(value)
    }
}

enum NFDataArchiveRawDatabaseDomain: String, Codable, Sendable { case durable, localOnly }
struct NFDataArchiveRawColumnManifest: Codable, Equatable, Sendable {
    let name: String
    let type: String
}
struct NFDataArchiveRawRow: Codable, Equatable, Sendable {
    // Supported SwiftData identity is diagnostic and identifies an existing
    // captured row. It is NEVER assigned to a new model or treated as a domain
    // ID. It may be temporary and is not a cross-store restoration authority.
    let capturedPersistentID: PersistentIdentifier?
    var columns: [String: NFDataArchiveRawValue]
    func contentBytes() throws -> Data { try NFDataArchiveRawSnapshot.canonicalEncode(columns) }
}
struct NFDataArchiveRawTable: Codable, Equatable, Sendable {
    let model: String
    let domain: NFDataArchiveRawDatabaseDomain
    let columnManifest: [NFDataArchiveRawColumnManifest]
    var rows: [NFDataArchiveRawRow]

    /// A multiset, not a map keyed by application ID. Exact duplicate rows are
    /// repeated. No domain winner, enum conversion, blob decode or dedup runs.
    func canonicalContent() throws -> NFDataArchiveRawTable {
        let values = try rows.map { (bytes: try $0.contentBytes(), row: $0) }
            .sorted { $0.bytes.lexicographicallyPrecedes($1.bytes) }
        return .init(model: model, domain: domain, columnManifest: columnManifest,
            rows: values.map { .init(capturedPersistentID: nil, columns: $0.row.columns) })
    }
    /// For explicit plan conflict groups, including crossed attemptID/sessionID
    /// groups. Payload bytes preserve multiplicity; hashes are not group keys.
    func groups(by identityColumns: [String]) throws -> [Data: [NFDataArchiveRawRow]] {
        guard !identityColumns.isEmpty, Set(identityColumns).count == identityColumns.count,
              Set(identityColumns).isSubset(of: Set(columnManifest.map(\.name))) else {
            throw NFDataArchiveRawSnapshotError.columnCensusMismatch(model)
        }
        var groups: [Data: [NFDataArchiveRawRow]] = [:]
        for row in rows {
            let identity = try identityColumns.map { name -> NFDataArchiveRawValue in
                guard let value = row.columns[name] else { throw NFDataArchiveRawSnapshotError.columnCensusMismatch(model) }
                return value
            }
            groups[try NFDataArchiveRawSnapshot.canonicalEncode(identity), default: []].append(row)
        }
        return groups
    }
}
struct NFDataArchiveRawSnapshot: Codable, Equatable, Sendable {
    let version: Int
    let modelSchemaVersion: String
    var tables: [NFDataArchiveRawTable]

    init(tables: [NFDataArchiveRawTable]) {
        version = 1
        modelSchemaVersion = "NFSchemaV1:1.0.0;raw-columns.v1"
        self.tables = tables
    }
    static func canonicalEncode<Value: Encodable>(_ value: Value) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(value)
    }
    func encoded(maximumBytes: Int) throws -> Data {
        guard maximumBytes > 0 else { throw NFDataArchiveRawSnapshotError.oversized }
        let bytes = try Self.canonicalEncode(self)
        guard bytes.count <= maximumBytes else { throw NFDataArchiveRawSnapshotError.oversized }
        return bytes
    }
    static func decode(_ bytes: Data, maximumBytes: Int) throws -> Self {
        guard maximumBytes > 0, bytes.count <= maximumBytes else { throw NFDataArchiveRawSnapshotError.oversized }
        let value = try JSONDecoder().decode(Self.self, from: bytes)
        guard value.version == 1, value.modelSchemaVersion == "NFSchemaV1:1.0.0;raw-columns.v1" else {
            throw NFDataArchiveRawSnapshotError.unsupportedVersion
        }
        return value
    }
    func contentBytes() throws -> Data {
        struct Content: Encodable {
            let version: Int
            let modelSchemaVersion: String
            let tables: [NFDataArchiveRawTable]
        }
        return try Self.canonicalEncode(Content(version: version, modelSchemaVersion: modelSchemaVersion,
            tables: tables.sorted { $0.model < $1.model }.map { try $0.canonicalContent() }))
    }
    func contentDigest() throws -> String {
        SHA256.hash(data: try contentBytes()).map { String(format: "%02x", $0) }.joined()
    }
}

@MainActor
private struct NFDataArchiveRawColumn<Model: PersistentModel> {
    let manifest: NFDataArchiveRawColumnManifest
    let capture: @MainActor (Model) -> NFDataArchiveRawValue
    let validate: @MainActor (NFDataArchiveRawValue) throws -> Void
    let apply: @MainActor (Model, NFDataArchiveRawValue) throws -> Void

    init<Value: NFDataArchiveRawScalar>(_ name: String, _ keyPath: ReferenceWritableKeyPath<Model, Value>) {
        manifest = .init(name: name, type: Value.rawTypeName)
        capture = { record in record[keyPath: keyPath].archiveRawValue }
        validate = { value in _ = try Value.fromArchiveRawValue(value) }
        apply = { record, value in record[keyPath: keyPath] = try Value.fromArchiveRawValue(value) }
    }
}
@MainActor
private struct NFDataArchiveRawHydration {
    let insert: @MainActor (ModelContext) -> Void
}
@MainActor
private struct NFDataArchiveRawCapturedTable {
    let table: NFDataArchiveRawTable
    let deleteCapturedRowsAt: @MainActor (Set<Int>, ModelContext) -> Void
}
@MainActor
private struct NFDataArchiveRawAdapter {
    let model: String
    let domain: NFDataArchiveRawDatabaseDomain
    let manifest: [NFDataArchiveRawColumnManifest]
    let capture: @MainActor (ModelContext) throws -> NFDataArchiveRawCapturedTable
    let validate: @MainActor (NFDataArchiveRawRow) throws -> Void
    let hydrate: @MainActor (NFDataArchiveRawRow) throws -> NFDataArchiveRawHydration

    init<Model: PersistentModel>(model: String, domain: NFDataArchiveRawDatabaseDomain,
                                columns: [NFDataArchiveRawColumn<Model>], makeBlank: @escaping @MainActor () throws -> Model) {
        self.model = model; self.domain = domain
        manifest = columns.map(\.manifest)
        let names = Set(columns.map { $0.manifest.name })
        precondition(names.count == columns.count, "Duplicate typed binding in the reviewed static census")
        @MainActor func read(_ record: Model, withIdentity: Bool) -> NFDataArchiveRawRow {
            var values: [String: NFDataArchiveRawValue] = [:]
            for column in columns { values[column.manifest.name] = column.capture(record) }
            return .init(capturedPersistentID: withIdentity ? record.persistentModelID : nil, columns: values)
        }
        @MainActor func check(_ row: NFDataArchiveRawRow) throws {
            guard Set(row.columns.keys) == names else { throw NFDataArchiveRawSnapshotError.columnCensusMismatch(model) }
            for column in columns {
                guard let value = row.columns[column.manifest.name] else { throw NFDataArchiveRawSnapshotError.columnCensusMismatch(model) }
                try column.validate(value)
            }
        }
        validate = check
        capture = { context in
            let records = try context.fetch(FetchDescriptor<Model>()).sorted { $0.persistentModelID < $1.persistentModelID }
            let table = NFDataArchiveRawTable(model: model, domain: domain, columnManifest: columns.map(\.manifest),
                rows: records.map { read($0, withIdentity: true) })
            return .init(table: table, deleteCapturedRowsAt: { indices, destination in
                for index in indices.sorted() { destination.delete(records[index]) }
            })
        }
        hydrate = { row in
            try check(row)
            let record = try makeBlank()
            for column in columns {
                guard let value = row.columns[column.manifest.name] else { throw NFDataArchiveRawSnapshotError.columnCensusMismatch(model) }
                try column.apply(record, value)
            }
            // Verify all typed accessors before the first live context mutation.
            guard try read(record, withIdentity: false).contentBytes() == row.contentBytes() else {
                throw NFDataArchiveRawSnapshotError.materializationMismatch(model)
            }
            return .init(insert: { context in context.insert(record) })
        }
    }
}

/// Both snapshots must come from the accepted, immutable restore plan. This is
/// a full-census conservative reconciliation building block: an unrelated row
/// arriving later is a conflict, never a reason to expand an accepted deletion.
struct NFDataArchiveRawTransition: Codable, Equatable, Sendable {
    let version: Int
    let before: NFDataArchiveRawSnapshot
    let after: NFDataArchiveRawSnapshot
    let beforeDigest: String
    let afterDigest: String
    init(before: NFDataArchiveRawSnapshot, after: NFDataArchiveRawSnapshot) throws {
        version = 1; self.before = before; self.after = after
        beforeDigest = try before.contentDigest(); afterDigest = try after.contentDigest()
    }
    enum Disposition: Equatable, Sendable { case alreadyApplied, needsApplication, conflict }
    func disposition(current: NFDataArchiveRawSnapshot) throws -> Disposition {
        guard version == 1, before.version == 1, after.version == 1, current.version == 1,
              before.modelSchemaVersion == "NFSchemaV1:1.0.0;raw-columns.v1",
              after.modelSchemaVersion == before.modelSchemaVersion, current.modelSchemaVersion == before.modelSchemaVersion,
              beforeDigest == (try before.contentDigest()), afterDigest == (try after.contentDigest()) else {
            throw NFDataArchiveRawSnapshotError.unsupportedVersion
        }
        // Compare complete canonical multisets too; checksums alone are not an
        // authority to choose a mutation or collapse duplicate logical records.
        let value = try current.contentBytes()
        if value == (try after.contentBytes()) { return .alreadyApplied }
        if value == (try before.contentBytes()) { return .needsApplication }
        return .conflict
    }
}

@MainActor
enum NFDataArchiveRawCapture {
    static var columnCensus: [String: [NFDataArchiveRawColumnManifest]] {
        Dictionary(uniqueKeysWithValues: adapters.map { ($0.model, $0.manifest) })
    }
    static func emptySnapshot() -> NFDataArchiveRawSnapshot {
        .init(tables: adapters.map { .init(model: $0.model, domain: $0.domain, columnManifest: $0.manifest, rows: []) })
    }
    static func capture(context: ModelContext) throws -> NFDataArchiveRawSnapshot {
        guard !context.hasChanges else { throw NFDataArchiveRawSnapshotError.dirtyContext }
        return .init(tables: try adapters.map { try $0.capture(context).table })
    }
    static func validate(_ snapshot: NFDataArchiveRawSnapshot) throws {
        guard snapshot.version == 1, snapshot.modelSchemaVersion == "NFSchemaV1:1.0.0;raw-columns.v1" else {
            throw NFDataArchiveRawSnapshotError.unsupportedVersion
        }
        guard Set(snapshot.tables.map(\.model)).count == snapshot.tables.count,
              Set(snapshot.tables.map(\.model)) == Set(adapters.map(\.model)) else {
            throw NFDataArchiveRawSnapshotError.columnCensusMismatch("model membership")
        }
        for table in snapshot.tables {
            guard let adapter = adapters.first(where: { $0.model == table.model }),
                  table.domain == adapter.domain, table.columnManifest == adapter.manifest else {
                throw NFDataArchiveRawSnapshotError.columnCensusMismatch(table.model)
            }
            for row in table.rows { try adapter.validate(row) }
        }
    }
    /// SQLite/Core Data text persistence truncates embedded NUL in the tested
    /// backend. Keep that original text in the raw journal, but refuse to stage
    /// a changed after-state containing it. Never repair it by trimming bytes.
    /// Other backend transformations still require fresh post-save verification.
    static func validateMaterialization(_ snapshot: NFDataArchiveRawSnapshot) throws {
        try validate(snapshot)
        for table in snapshot.tables {
            for row in table.rows {
                for (column, value) in row.columns {
                    if case let .textUTF8(bytes) = value, bytes.contains(0) {
                        throw NFDataArchiveRawSnapshotError.unrepresentableText("\(table.model).\(column)")
                    }
                }
            }
        }
    }

    /// Exercises all typed writers/readers without attaching models to any
    /// context. This verifies malformed/future opaque blobs and unusual scalar
    /// representations independently of a backend's storage restrictions.
    static func verifyHydration(_ snapshot: NFDataArchiveRawSnapshot) throws {
        try validate(snapshot)
        for table in snapshot.tables {
            guard let adapter = adapters.first(where: { $0.model == table.model }) else {
                throw NFDataArchiveRawSnapshotError.unsupportedModel(table.model)
            }
            for row in table.rows { _ = try adapter.hydrate(row) }
        }
    }
    /// Useful for a disposable staging container and raw round-trip verification.
    /// Does not save; all after-models are constructed/verified before insertion.
    static func materializeInEmptyContext(_ snapshot: NFDataArchiveRawSnapshot, context: ModelContext) throws {
        guard !context.hasChanges else { throw NFDataArchiveRawSnapshotError.dirtyContext }
        guard !context.autosaveEnabled else { throw NFDataArchiveRawSnapshotError.autosaveMustBeDisabled }
        let before = try capture(context: context)
        guard before.tables.allSatisfy({ $0.rows.isEmpty }) else { throw NFDataArchiveRawSnapshotError.destinationNotEmpty }
        _ = try stageAcceptedTransition(.init(before: before, after: snapshot), context: context)
    }
    /// Requires the caller's durable accepted marker and exclusive write fence.
    /// This only stages ONE ModelContext change. Caller owns save, fresh fetch
    /// verification, per-store uncertainty and the durable completion marker.
    /// It deliberately does not catch an ambiguous save or claim crash rollback.
    @discardableResult
    static func stageAcceptedTransition(_ transition: NFDataArchiveRawTransition, context: ModelContext) throws -> NFDataArchiveRawTransition.Disposition {
        guard !context.hasChanges else { throw NFDataArchiveRawSnapshotError.dirtyContext }
        guard !context.autosaveEnabled else { throw NFDataArchiveRawSnapshotError.autosaveMustBeDisabled }
        try validate(transition.before); try validate(transition.after)
        let captured = try adapters.map { try $0.capture(context) }
        let disposition = try transition.disposition(current: .init(tables: captured.map(\.table)))
        switch disposition {
        case .alreadyApplied: return .alreadyApplied
        case .conflict: throw NFDataArchiveRawSnapshotError.conflictingPredecessor
        case .needsApplication: break
        }
        try validateMaterialization(transition.after)
        var insertions: [NFDataArchiveRawHydration] = []
        var deletions: [(captured: NFDataArchiveRawCapturedTable, indices: Set<Int>)] = []
        for table in transition.after.tables {
            guard let adapter = adapters.first(where: { $0.model == table.model }),
                  let original = captured.first(where: { $0.table.model == table.model }) else {
                throw NFDataArchiveRawSnapshotError.unsupportedModel(table.model)
            }
            // Preserve every unchanged physical row. Match complete payload
            // bytes with multiplicity; do not upsert by a duplicate domain ID.
            var matches: [Data: [Int]] = [:]
            for (index, row) in original.table.rows.enumerated() {
                matches[try row.contentBytes(), default: []].append(index)
            }
            var removed = Set(original.table.rows.indices)
            for row in table.rows {
                let bytes = try row.contentBytes()
                if let kept = matches[bytes]?.popLast() {
                    // The captured list is sorted by persistent ID. Pop through
                    // the dictionary's mutable subscript without copying and
                    // shifting an identical-row group for every match.
                    removed.remove(kept)
                } else { insertions.append(try adapter.hydrate(row)) }
            }
            deletions.append((original, removed))
        }
        // Same captured objects, never an unbounded second delete-all fetch.
        // All new objects and typed values verified before this first mutation.
        for deletion in deletions { deletion.captured.deleteCapturedRowsAt(deletion.indices, context) }
        for insertion in insertions { insertion.insert(context) }
        return .needsApplication
    }

    private static let adapters: [NFDataArchiveRawAdapter] = [
            .init(model: "UserProfileRecord", domain: .durable, columns: [
                .init("id", \UserProfileRecord.id),
                .init("createdAt", \UserProfileRecord.createdAt),
                .init("modifiedAt", \UserProfileRecord.modifiedAt),
                .init("stageRaw", \UserProfileRecord.stageRaw),
                .init("fieldsRaw", \UserProfileRecord.fieldsRaw),
                .init("goalsRaw", \UserProfileRecord.goalsRaw),
                .init("dailyDuration", \UserProfileRecord.dailyDuration),
                .init("timingModeRaw", \UserProfileRecord.timingModeRaw),
                .init("aiModeRaw", \UserProfileRecord.aiModeRaw),
                .init("iCloudEnabled", \UserProfileRecord.iCloudEnabled),
                .init("reducedMotion", \UserProfileRecord.reducedMotion),
                .init("hideTimers", \UserProfileRecord.hideTimers),
                .init("excludeVisualSpatial", \UserProfileRecord.excludeVisualSpatial),
                .init("onboardingVersion", \UserProfileRecord.onboardingVersion),
                .init("claimsPolicyAcknowledgedVersion", \UserProfileRecord.claimsPolicyAcknowledgedVersion),
                .init("pccConsentVersion", \UserProfileRecord.pccConsentVersion),
                .init("pccConsentAt", \UserProfileRecord.pccConsentAt),
                .init("preferredLanguageCode", \UserProfileRecord.preferredLanguageCode),
                .init("trainingDaysRaw", \UserProfileRecord.trainingDaysRaw),
                .init("dayBoundaryHour", \UserProfileRecord.dayBoundaryHour),
                .init("ageBandAcknowledged16Plus", \UserProfileRecord.ageBandAcknowledged16Plus),
                .init("preferredAnswerModeRaw", \UserProfileRecord.preferredAnswerModeRaw),
                .init("reinforcementHapticsEnabled", \UserProfileRecord.reinforcementHapticsEnabled),
                .init("reinforcementSoundEnabled", \UserProfileRecord.reinforcementSoundEnabled)
            ], makeBlank: makeBlankUserProfileRecord),
            .init(model: "InputCalibrationRecord", domain: .localOnly, columns: [
                .init("id", \InputCalibrationRecord.id),
                .init("profileID", \InputCalibrationRecord.profileID),
                .init("completedAt", \InputCalibrationRecord.completedAt),
                .init("preferredAnswerModeRaw", \InputCalibrationRecord.preferredAnswerModeRaw),
                .init("keyboardLatencyMilliseconds", \InputCalibrationRecord.keyboardLatencyMilliseconds),
                .init("touchLatencyMilliseconds", \InputCalibrationRecord.touchLatencyMilliseconds),
                .init("pencilLatencyMilliseconds", \InputCalibrationRecord.pencilLatencyMilliseconds)
            ], makeBlank: makeBlankInputCalibrationRecord),
            .init(model: "ProgressAnnotationRecord", domain: .durable, columns: [
                .init("id", \ProgressAnnotationRecord.id),
                .init("startDate", \ProgressAnnotationRecord.startDate),
                .init("endDate", \ProgressAnnotationRecord.endDate),
                .init("note", \ProgressAnnotationRecord.note),
                .init("includeInExport", \ProgressAnnotationRecord.includeInExport),
                .init("createdAt", \ProgressAnnotationRecord.createdAt),
                .init("modifiedAt", \ProgressAnnotationRecord.modifiedAt)
            ], makeBlank: makeBlankProgressAnnotationRecord),
            .init(model: "AttemptRecord", domain: .durable, columns: [
                .init("id", \AttemptRecord.id),
                .init("sessionID", \AttemptRecord.sessionID),
                .init("itemID", \AttemptRecord.itemID),
                .init("templateID", \AttemptRecord.templateID),
                .init("seed", \AttemptRecord.seed),
                .init("gameID", \AttemptRecord.gameID),
                .init("skillID", \AttemptRecord.skillID),
                .init("skillWeightsRaw", \AttemptRecord.skillWeightsRaw),
                .init("domainContextRaw", \AttemptRecord.domainContextRaw),
                .init("transferBriefRaw", \AttemptRecord.transferBriefRaw),
                .init("spatialDifficultyParametersRaw", \AttemptRecord.spatialDifficultyParametersRaw),
                .init("prompt", \AttemptRecord.prompt),
                .init("response", \AttemptRecord.response),
                .init("correctAnswer", \AttemptRecord.correctAnswer),
                .init("correctAnswerText", \AttemptRecord.correctAnswerText),
                .init("isCorrect", \AttemptRecord.isCorrect),
                .init("confidenceRaw", \AttemptRecord.confidenceRaw),
                .init("shownAt", \AttemptRecord.shownAt),
                .init("submittedAt", \AttemptRecord.submittedAt),
                .init("activeDurationSeconds", \AttemptRecord.activeDurationSeconds),
                .init("evidenceClassRaw", \AttemptRecord.evidenceClassRaw),
                .init("sessionSourceRaw", \AttemptRecord.sessionSourceRaw),
                .init("evidenceWeight", \AttemptRecord.evidenceWeight),
                .init("errorCode", \AttemptRecord.errorCode),
                .init("scoringVersion", \AttemptRecord.scoringVersion),
                .init("deviceID", \AttemptRecord.deviceID),
                .init("generationID", \AttemptRecord.generationID),
                .init("sourceDocumentIDsRaw", \AttemptRecord.sourceDocumentIDsRaw),
                .init("sourceChunkIDsRaw", \AttemptRecord.sourceChunkIDsRaw),
                .init("responseFormatRaw", \AttemptRecord.responseFormatRaw),
                .init("wasSkipped", \AttemptRecord.wasSkipped),
                .init("validationVersion", \AttemptRecord.validationVersion),
                .init("assessmentBlockRaw", \AttemptRecord.assessmentBlockRaw),
                .init("planID", \AttemptRecord.planID),
                .init("planBlockID", \AttemptRecord.planBlockID),
                .init("deterministicCredit", \AttemptRecord.deterministicCredit),
                .init("hintCount", \AttemptRecord.hintCount),
                .init("inputModeRaw", \AttemptRecord.inputModeRaw),
                .init("interruptionCount", \AttemptRecord.interruptionCount),
                .init("revisionCount", \AttemptRecord.revisionCount),
                .init("accommodationFlagsRaw", \AttemptRecord.accommodationFlagsRaw),
                .init("wasTimed", \AttemptRecord.wasTimed),
                .init("assessmentDescriptorID", \AttemptRecord.assessmentDescriptorID),
                .init("assessmentTemplateFamily", \AttemptRecord.assessmentTemplateFamily),
                .init("assessmentFormatRaw", \AttemptRecord.assessmentFormatRaw),
                .init("assessmentMechanicID", \AttemptRecord.assessmentMechanicID),
                .init("assessmentSubskillID", \AttemptRecord.assessmentSubskillID),
                .init("assessmentSeed", \AttemptRecord.assessmentSeed),
                .init("assessmentCycle", \AttemptRecord.assessmentCycle)
            ], makeBlank: makeBlankAttemptRecord),
            .init(model: "AttemptReflectionRecord", domain: .durable, columns: [
                .init("id", \AttemptReflectionRecord.id),
                .init("attemptID", \AttemptReflectionRecord.attemptID),
                .init("deterministicErrorCode", \AttemptReflectionRecord.deterministicErrorCode),
                .init("selectedErrorCodeRaw", \AttemptReflectionRecord.selectedErrorCodeRaw),
                .init("triggerRaw", \AttemptReflectionRecord.triggerRaw),
                .init("note", \AttemptReflectionRecord.note),
                .init("createdAt", \AttemptReflectionRecord.createdAt),
                .init("policyVersion", \AttemptReflectionRecord.policyVersion)
            ], makeBlank: makeBlankAttemptReflectionRecord),
            .init(model: "ItemReportRecord", domain: .durable, columns: [
                .init("id", \ItemReportRecord.id),
                .init("itemID", \ItemReportRecord.itemID),
                .init("templateID", \ItemReportRecord.templateID),
                .init("prompt", \ItemReportRecord.prompt),
                .init("reason", \ItemReportRecord.reason),
                .init("note", \ItemReportRecord.note),
                .init("createdAt", \ItemReportRecord.createdAt),
                .init("status", \ItemReportRecord.status),
                .init("seed", \ItemReportRecord.seed),
                .init("generatorVersion", \ItemReportRecord.generatorVersion),
                .init("provenanceSummary", \ItemReportRecord.provenanceSummary),
                .init("sourceIDsRaw", \ItemReportRecord.sourceIDsRaw),
                .init("sourceChunkIDsRaw", \ItemReportRecord.sourceChunkIDsRaw),
                .init("assessmentDescriptorID", \ItemReportRecord.assessmentDescriptorID),
                .init("diagnosticPayload", \ItemReportRecord.diagnosticPayload),
                .init("diagnosticDigest", \ItemReportRecord.diagnosticDigest),
                .init("diagnosticPayloadState", \ItemReportRecord.diagnosticPayloadState)
            ], makeBlank: makeBlankItemReportRecord),
            .init(model: "SourceDocumentRecord", domain: .localOnly, columns: [
                .init("id", \SourceDocumentRecord.id),
                .init("filename", \SourceDocumentRecord.filename),
                .init("typeIdentifier", \SourceDocumentRecord.typeIdentifier),
                .init("sizeBytes", \SourceDocumentRecord.sizeBytes),
                .init("importedAt", \SourceDocumentRecord.importedAt),
                .init("indexState", \SourceDocumentRecord.indexState),
                .init("aiPolicyRaw", \SourceDocumentRecord.aiPolicyRaw),
                .init("pccExcerptConsentPolicyVersion", \SourceDocumentRecord.pccExcerptConsentPolicyVersion),
                .init("pccExcerptConsentDocumentIDRaw", \SourceDocumentRecord.pccExcerptConsentDocumentIDRaw),
                .init("pccExcerptConsentedAt", \SourceDocumentRecord.pccExcerptConsentedAt),
                .init("syncPolicy", \SourceDocumentRecord.syncPolicy),
                .init("localPath", \SourceDocumentRecord.localPath),
                .init("characterCount", \SourceDocumentRecord.characterCount),
                .init("chunkCount", \SourceDocumentRecord.chunkCount),
                .init("extractionVersion", \SourceDocumentRecord.extractionVersion),
                .init("csvSelectedColumnIDsRaw", \SourceDocumentRecord.csvSelectedColumnIDsRaw),
                .init("indexError", \SourceDocumentRecord.indexError),
                .init("modifiedAt", \SourceDocumentRecord.modifiedAt)
            ], makeBlank: makeBlankSourceDocumentRecord),
            .init(model: "SourceChunkRecord", domain: .localOnly, columns: [
                .init("id", \SourceChunkRecord.id),
                .init("documentID", \SourceChunkRecord.documentID),
                .init("documentVersion", \SourceChunkRecord.documentVersion),
                .init("sourceName", \SourceChunkRecord.sourceName),
                .init("page", \SourceChunkRecord.page),
                .init("lineStart", \SourceChunkRecord.lineStart),
                .init("lineEnd", \SourceChunkRecord.lineEnd),
                .init("section", \SourceChunkRecord.section),
                .init("characterStart", \SourceChunkRecord.characterStart),
                .init("characterEnd", \SourceChunkRecord.characterEnd),
                .init("nearbyHeading", \SourceChunkRecord.nearbyHeading),
                .init("language", \SourceChunkRecord.language),
                .init("contentTypeTagsRaw", \SourceChunkRecord.contentTypeTagsRaw),
                .init("text", \SourceChunkRecord.text),
                .init("contentHash", \SourceChunkRecord.contentHash),
                .init("ordinal", \SourceChunkRecord.ordinal),
                .init("createdAt", \SourceChunkRecord.createdAt)
            ], makeBlank: makeBlankSourceChunkRecord),
            .init(model: "AIGenerationRecord", domain: .localOnly, columns: [
                .init("id", \AIGenerationRecord.id),
                .init("createdAt", \AIGenerationRecord.createdAt),
                .init("capabilityRaw", \AIGenerationRecord.capabilityRaw),
                .init("labRaw", \AIGenerationRecord.labRaw),
                .init("fieldRaw", \AIGenerationRecord.fieldRaw),
                .init("topic", \AIGenerationRecord.topic),
                .init("routeRaw", \AIGenerationRecord.routeRaw),
                .init("routeReason", \AIGenerationRecord.routeReason),
                .init("promptVersion", \AIGenerationRecord.promptVersion),
                .init("validationVersion", \AIGenerationRecord.validationVersion),
                .init("modelIdentifier", \AIGenerationRecord.modelIdentifier),
                .init("sourceDocumentIDsRaw", \AIGenerationRecord.sourceDocumentIDsRaw),
                .init("sourceChunkIDsRaw", \AIGenerationRecord.sourceChunkIDsRaw),
                .init("repairCount", \AIGenerationRecord.repairCount),
                .init("cacheKey", \AIGenerationRecord.cacheKey),
                .init("isFallback", \AIGenerationRecord.isFallback),
                .init("questionCount", \AIGenerationRecord.questionCount),
                .init("resultPayload", \AIGenerationRecord.resultPayload),
                .init("payloadExpiresAt", \AIGenerationRecord.payloadExpiresAt)
            ], makeBlank: makeBlankAIGenerationRecord),
            .init(model: "WeeklyTransferStateRecord", domain: .durable, columns: [
                .init("id", \WeeklyTransferStateRecord.id),
                .init("completedMissionIDsRaw", \WeeklyTransferStateRecord.completedMissionIDsRaw),
                .init("deferredUntilPayload", \WeeklyTransferStateRecord.deferredUntilPayload),
                .init("modifiedAt", \WeeklyTransferStateRecord.modifiedAt)
            ], makeBlank: makeBlankWeeklyTransferStateRecord),
            .init(model: "ReassessmentStateRecord", domain: .durable, columns: [
                .init("id", \ReassessmentStateRecord.id),
                .init("completedCycle", \ReassessmentStateRecord.completedCycle),
                .init("activeDayAnchor", \ReassessmentStateRecord.activeDayAnchor),
                .init("dueAt", \ReassessmentStateRecord.dueAt),
                .init("deferredUntil", \ReassessmentStateRecord.deferredUntil),
                .init("targetBlockRaw", \ReassessmentStateRecord.targetBlockRaw),
                .init("lastCompletedAt", \ReassessmentStateRecord.lastCompletedAt),
                .init("lastCompletedBlockRaw", \ReassessmentStateRecord.lastCompletedBlockRaw),
                .init("modifiedAt", \ReassessmentStateRecord.modifiedAt)
            ], makeBlank: makeBlankReassessmentStateRecord),
            .init(model: "SessionCheckpointRecord", domain: .durable, columns: [
                .init("id", \SessionCheckpointRecord.id),
                .init("sessionID", \SessionCheckpointRecord.sessionID),
                .init("labRaw", \SessionCheckpointRecord.labRaw),
                .init("sourceRaw", \SessionCheckpointRecord.sourceRaw),
                .init("seed", \SessionCheckpointRecord.seed),
                .init("currentIndex", \SessionCheckpointRecord.currentIndex),
                .init("itemCount", \SessionCheckpointRecord.itemCount),
                .init("response", \SessionCheckpointRecord.response),
                .init("scratchpad", \SessionCheckpointRecord.scratchpad),
                .init("resultsRaw", \SessionCheckpointRecord.resultsRaw),
                .init("creditsRaw", \SessionCheckpointRecord.creditsRaw),
                .init("assessmentDescriptorIDsRaw", \SessionCheckpointRecord.assessmentDescriptorIDsRaw),
                .init("assessmentEventsRaw", \SessionCheckpointRecord.assessmentEventsRaw),
                .init("evidenceClassRaw", \SessionCheckpointRecord.evidenceClassRaw),
                .init("updatedAt", \SessionCheckpointRecord.updatedAt),
                .init("isComplete", \SessionCheckpointRecord.isComplete),
                .init("planID", \SessionCheckpointRecord.planID),
                .init("planBlockID", \SessionCheckpointRecord.planBlockID),
                .init("recommendationRationale", \SessionCheckpointRecord.recommendationRationale),
                .init("hasCommittedCurrentItem", \SessionCheckpointRecord.hasCommittedCurrentItem),
                .init("assessmentBlockRaw", \SessionCheckpointRecord.assessmentBlockRaw),
                .init("assessmentCycle", \SessionCheckpointRecord.assessmentCycle),
                .init("activeDurationSeconds", \SessionCheckpointRecord.activeDurationSeconds),
                .init("assessmentStopReasonRaw", \SessionCheckpointRecord.assessmentStopReasonRaw),
                .init("pendingReflectionAttemptID", \SessionCheckpointRecord.pendingReflectionAttemptID),
                .init("reflectionTriggerRaw", \SessionCheckpointRecord.reflectionTriggerRaw),
                .init("selectedReflectionCodeRaw", \SessionCheckpointRecord.selectedReflectionCodeRaw),
                .init("reflectionNote", \SessionCheckpointRecord.reflectionNote)
            ], makeBlank: makeBlankSessionCheckpointRecord),
            .init(model: "DailyPlanRecord", domain: .durable, columns: [
                .init("id", \DailyPlanRecord.id),
                .init("profileID", \DailyPlanRecord.profileID),
                .init("localDayKey", \DailyPlanRecord.localDayKey),
                .init("policyVersion", \DailyPlanRecord.policyVersion),
                .init("payload", \DailyPlanRecord.payload),
                .init("createdAt", \DailyPlanRecord.createdAt),
                .init("timeZoneIdentifier", \DailyPlanRecord.timeZoneIdentifier),
                .init("utcOffsetSeconds", \DailyPlanRecord.utcOffsetSeconds),
                .init("dayBoundaryHour", \DailyPlanRecord.dayBoundaryHour),
                .init("boundaryStart", \DailyPlanRecord.boundaryStart),
                .init("nextBoundaryAt", \DailyPlanRecord.nextBoundaryAt),
                .init("travelPreservedUntil", \DailyPlanRecord.travelPreservedUntil)
            ], makeBlank: makeBlankDailyPlanRecord)
    ]

    private static let neutralID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
    private static let neutralDate = Date(timeIntervalSinceReferenceDate: 0)
    // These constructors allocate transient models only. All 219 columns are
    // overwritten through their typed bindings before insertion. Their domain
    // defaults/normalization never become the restored representation. No model
    // generation, scorer, decoder of original blobs, or localized UI API runs.
    private static func makeBlankUserProfileRecord() -> UserProfileRecord {
        UserProfileRecord(draft: OnboardingDraft(preferredLanguageCode: "en"))
    }
    private static func makeBlankInputCalibrationRecord() -> InputCalibrationRecord {
        InputCalibrationRecord(profileID: neutralID, completedAt: neutralDate, preferredAnswerMode: .adaptive,
            keyboardLatencyMilliseconds: nil, touchLatencyMilliseconds: nil, pencilLatencyMilliseconds: nil)
    }
    private static func makeBlankProgressAnnotationRecord() -> ProgressAnnotationRecord {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return ProgressAnnotationRecord(id: neutralID, startDate: neutralDate, endDate: neutralDate,
            note: "", includeInExport: false, calendar: calendar)
    }
    private static func makeBlankAttemptRecord() -> AttemptRecord {
        AttemptRecord(sessionID: neutralID, lab: .mentalMath, itemID: "", prompt: "", response: "",
            correctAnswer: "", isCorrect: false, confidence: .certain)
    }
    private static func makeBlankAttemptReflectionRecord() -> AttemptReflectionRecord {
        AttemptReflectionRecord(attemptID: neutralID, deterministicErrorCode: nil, selectedErrorCode: nil,
            trigger: .highConfidenceError, note: "", createdAt: neutralDate)
    }
    private static func makeBlankItemReportRecord() -> ItemReportRecord {
        let item = MentalMathItem(id: "", templateID: "", seed: 0, kind: .multiplication,
            prompt: "", context: "", answer: 0, tolerance: 0, strategy: "", decisiveStep: "",
            difficulty: 0, evidenceClass: .practice)
        return ItemReportRecord(item: item, reason: "", note: "")
    }
    private static func makeBlankSourceDocumentRecord() -> SourceDocumentRecord {
        SourceDocumentRecord(filename: "", typeIdentifier: "", sizeBytes: 0, localPath: "")
    }
    private static func makeBlankSourceChunkRecord() -> SourceChunkRecord {
        SourceChunkRecord(chunk: NFSourceChunk(id: "", documentID: neutralID, documentVersion: 1,
            sourceName: "", locator: .init(page: nil, lineStart: nil, lineEnd: nil, section: nil),
            text: "", contentHash: "", ordinal: 0))
    }
    private static func makeBlankAIGenerationRecord() throws -> AIGenerationRecord {
        let request = NFAuthoringRequest(id: neutralID, capability: .contextualize, lab: .mentalMath, field: .general,
            customTopic: "", learningObjective: "", style: .shortAnswer, difficulty: 0, count: 1,
            localeIdentifier: "en", seed: 0, aiMode: .disabled)
        let provenance = NFAIGenerationProvenance(requestID: neutralID, generatedAt: neutralDate,
            route: .deterministicFallback, routeReason: "", promptVersion: 0, modelIdentifier: "",
            sourceChunkIDs: [], sourceDocumentIDs: [], validationVersion: 0, repairCount: 0, cacheKey: "", isFallback: false)
        let result = NFAuthoringResult(questions: [], provenance: provenance, routeCandidates: [],
            validationStatus: .init(level: .deterministicKey, sourceSupport: .notApplicable), validationNotes: [])
        return try AIGenerationRecord(request: request, result: result, payloadTTL: 0)
    }
    private static func makeBlankWeeklyTransferStateRecord() -> WeeklyTransferStateRecord {
        WeeklyTransferStateRecord()
    }
    private static func makeBlankReassessmentStateRecord() -> ReassessmentStateRecord {
        ReassessmentStateRecord()
    }
    private static func makeBlankSessionCheckpointRecord() -> SessionCheckpointRecord {
        SessionCheckpointRecord(sessionID: neutralID, lab: .mentalMath, source: .focused, seed: 0,
            currentIndex: 0, itemCount: 0, response: "", scratchpad: "", results: [], evidenceClass: .practice)
    }
    private static func makeBlankDailyPlanRecord() throws -> DailyPlanRecord {
        let plan = NFCanonicalDailyPlan(id: "", profileID: neutralID, localDayKey: "", seed: 0,
            policyVersion: 0, requestedMinutes: 0, scheduledMinutes: 0, blocks: [], prioritySnapshot: [], replacement: nil)
        let boundary = NFPlanBoundaryContext(evaluatedAt: neutralDate, timeZoneIdentifier: "UTC", utcOffsetSeconds: 0,
            dayBoundaryHour: 0, boundaryStart: neutralDate, nextBoundary: neutralDate)
        return try DailyPlanRecord(plan: plan, boundaryContext: boundary)
    }
}

// MARK: - Private durable restore journal

import Darwin

/// This file store does not acquire the application/CloudKit write fence, stage
/// merge decisions, save SwiftData, materialize files, or open an AppStore.
/// Callers must integrate those boundaries before this can authorize recovery.
enum NFRestoreJournalError: Error, Equatable, LocalizedError {
    case unsupportedVersion, malformed, oversized, digestMismatch, wrongOwner
    case conflictingPlan, staleRevision, recoveryConflict, invalidated, busy
    case unsafePath, ioFailure, tooManyTransactions

    var errorDescription: String? {
        switch self {
        case .busy: "Restore recovery is busy in another process. Please try again."
        case .wrongOwner: "This restore belongs to another account or installation."
        case .unsupportedVersion: "This restore needs a compatible version of the app."
        case .invalidated: "This restore was invalidated and cannot be replayed."
        case .recoveryConflict: "Saved data differs from the accepted restore. Recovery is paused."
        default: "The restore journal could not be verified. Your recovery material has been retained."
        }
    }
}

/// Paths are relative to a coordinator-supplied, allowlisted domain root. This
/// building block never resolves these paths or writes their live destinations.
struct NFRestoreJournalFileOperation: Codable, Equatable, Sendable {
    enum Domain: String, Codable, Sendable { case localLearning, adaptiveHistory, sourceFile, aiTutor, aiGrading }
    let id: String
    let domain: Domain
    let relativePath: String
    let before: Data?
    let after: Data?
}

struct NFRestoreJournalPlan: Codable, Equatable, Sendable {
    let version: Int
    let transactionID: UUID
    let namespace: String
    let installationOwnerID: UUID
    let sourceDigest: String
    let permittedPayload: Data
    let permittedPayloadDigest: String
    let acceptedPolicyRaw: String
    let acceptedCounts: [String: Int]
    /// Nil preserves the original schema-1 restored-only category contract.
    let resultCountsVersion: Int?
    let raw: NFDataArchiveRawTransition
    let files: [NFRestoreJournalFileOperation]

    init(transactionID: UUID, namespace: String, installationOwnerID: UUID,
         sourceDigest: String, permittedPayload: Data, policy: NFDataArchiveRestorePolicy,
         acceptedCounts: [String: Int], raw: NFDataArchiveRawTransition,
         files: [NFRestoreJournalFileOperation] = [], resultCountsVersion: Int? = nil) {
        version = 1
        self.transactionID = transactionID; self.namespace = namespace
        self.installationOwnerID = installationOwnerID; self.sourceDigest = sourceDigest
        self.permittedPayload = permittedPayload
        permittedPayloadDigest = NFRestoreJournalCodec.digest(permittedPayload)
        acceptedPolicyRaw = policy.rawValue; self.acceptedCounts = acceptedCounts
        self.resultCountsVersion = resultCountsVersion
        self.raw = raw; self.files = files
    }

    /// Typed schema validation remains on the model-owning actor, but no live
    /// model is read or mutated. File I/O and JSON work belong to the journal actor.
    @MainActor
    func validateSupportedRawContract() throws {
        try NFDataArchiveRawCapture.validate(raw.before)
        try NFDataArchiveRawCapture.validateMaterialization(raw.after)
    }
}

struct NFRestoreJournalDescriptor: Codable, Equatable, Sendable {
    let version: Int
    let transactionID: UUID
    let namespace: String
    let installationOwnerID: UUID
    let planDigest: String
    let planByteCount: Int
}

enum NFRestoreJournalPhase: String, Codable, Sendable {
    case accepted, mutationMayHaveStarted, recoveryRequired, verifiedComplete, invalidated, cleaned
}

struct NFRestoreJournalCompletion: Codable, Equatable, Sendable {
    let rawAfterDigest: String
    let fileAfterDigests: [String: String]
    let acceptedCounts: [String: Int]
}

struct NFRestoreJournalProgress: Codable, Equatable, Sendable {
    let version: Int
    let transactionID: UUID
    let planDigest: String
    let revision: UInt64
    let phase: NFRestoreJournalPhase
    let completion: NFRestoreJournalCompletion?
}

/// Contains IDs and hashes only. Neither raw answers nor source titles can enter
/// a recovery status view by accidentally rendering this inspection value.
struct NFRestoreJournalInspection: Equatable, Sendable {
    let transactionID: UUID
    let isStaging: Bool
    let descriptor: NFRestoreJournalDescriptor?
    let progress: NFRestoreJournalProgress?
}

struct NFRestoreJournalLoaded: Sendable {
    let descriptor: NFRestoreJournalDescriptor
    let progress: NFRestoreJournalProgress
    let plan: NFRestoreJournalPlan
}

struct NFRestoreJournalReconciliation: Equatable, Sendable {
    enum Disposition: String, Equatable, Sendable { case alreadyApplied, needsApplication, conflict }
    let durableDatabase: Disposition
    let localDatabase: Disposition
    let files: [String: Disposition]
    var hasConflict: Bool {
        durableDatabase == .conflict || localDatabase == .conflict || files.values.contains(.conflict)
    }
    var isComplete: Bool {
        durableDatabase == .alreadyApplied && localDatabase == .alreadyApplied &&
            files.values.allSatisfy { $0 == .alreadyApplied }
    }
}

/// Codec accepts only its own canonical, versioned encoding. Unknown keys,
/// duplicate keys, future enum values and noncanonical corruption are retained
/// on disk and rejected, rather than decoded and silently rewritten away.
enum NFRestoreJournalCodec {
    static func digest(_ bytes: Data) -> String {
        SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
    }
    static func isDigest(_ value: String) -> Bool {
        value.utf8.count == 64 && value.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
    }
    static func encode<T: Encodable>(_ value: T, maximumBytes: Int) throws -> Data {
        guard maximumBytes > 0 else { throw NFRestoreJournalError.oversized }
        let bytes = try NFDataArchiveRawSnapshot.canonicalEncode(value)
        guard bytes.count <= maximumBytes else { throw NFRestoreJournalError.oversized }
        return bytes
    }
    static func decode<T: Codable>(_ type: T.Type, bytes: Data, maximumBytes: Int) throws -> T {
        guard maximumBytes > 0, bytes.count <= maximumBytes else { throw NFRestoreJournalError.oversized }
        let value: T
        do { value = try JSONDecoder().decode(type, from: bytes) }
        catch { throw NFRestoreJournalError.malformed }
        guard try encode(value, maximumBytes: maximumBytes) == bytes else { throw NFRestoreJournalError.malformed }
        return value
    }
    static func validate(_ plan: NFRestoreJournalPlan) throws {
        guard plan.version == 1 else { throw NFRestoreJournalError.unsupportedVersion }
        guard !plan.namespace.isEmpty, plan.namespace.utf8.count <= 256,
              isDigest(plan.sourceDigest), isDigest(plan.permittedPayloadDigest),
              NFDataArchiveRestorePolicy(rawValue: plan.acceptedPolicyRaw) != nil,
              plan.files.count <= NFAILearningArtifactArchive.maximumFiles * 2 + 2,
              Set(plan.files.map(\.id)).count == plan.files.count,
              Set(plan.files.map { $0.domain.rawValue + ":" + $0.relativePath }).count == plan.files.count else {
            throw NFRestoreJournalError.malformed
        }
        guard digest(plan.permittedPayload) == plan.permittedPayloadDigest else { throw NFRestoreJournalError.digestMismatch }
        var total = 0
        let categories: Set<String>
        switch plan.resultCountsVersion {
        case nil: categories = Set(NFDataArchiveCategory.allCases.map(\.rawValue))
        case 1: categories = NFRestoreCompiledCounts.supportedKeys
        default: throw NFRestoreJournalError.unsupportedVersion
        }
        for (key, count) in plan.acceptedCounts {
            let sum = total.addingReportingOverflow(count)
            guard categories.contains(key), count >= 0, !sum.overflow else { throw NFRestoreJournalError.malformed }
            total = sum.partialValue
        }
        for file in plan.files {
            guard !file.id.isEmpty, file.id.utf8.count <= 256,
                  isSafeRelativePath(file.relativePath) else { throw NFRestoreJournalError.unsafePath }
        }
        _ = try NFAILearningArtifactArchive.files(from: plan.files, before: true)
        _ = try NFAILearningArtifactArchive.files(from: plan.files, before: false)
        _ = try plan.raw.disposition(current: plan.raw.before)
    }
    static func isSafeRelativePath(_ path: String) -> Bool {
        let components = path.split(separator: "/", omittingEmptySubsequences: false)
        return !path.isEmpty && path.utf8.count <= 2_048 && !path.contains("\\") &&
            !path.utf8.contains(0) && components.allSatisfy { !$0.isEmpty && $0 != "." && $0 != ".." }
    }
    static func validate(_ descriptor: NFRestoreJournalDescriptor) throws {
        guard descriptor.version == 1 else { throw NFRestoreJournalError.unsupportedVersion }
        guard !descriptor.namespace.isEmpty, descriptor.namespace.utf8.count <= 256,
              isDigest(descriptor.planDigest), descriptor.planByteCount > 0 else { throw NFRestoreJournalError.malformed }
    }
    static func validate(_ progress: NFRestoreJournalProgress, descriptor: NFRestoreJournalDescriptor) throws {
        guard progress.version == 1 else { throw NFRestoreJournalError.unsupportedVersion }
        guard progress.transactionID == descriptor.transactionID, progress.planDigest == descriptor.planDigest,
              (progress.phase == .verifiedComplete) == (progress.completion != nil),
              (progress.revision == 0) == (progress.phase == .accepted) else { throw NFRestoreJournalError.malformed }
        if let completion = progress.completion {
            guard isDigest(completion.rawAfterDigest),
                  completion.fileAfterDigests.values.allSatisfy(isDigest),
                  completion.acceptedCounts.values.allSatisfy({ $0 >= 0 }) else { throw NFRestoreJournalError.malformed }
        }
    }
    static func fileStateDigest(_ bytes: Data?) -> String {
        // Encode absence explicitly; absent and a present zero-byte file differ.
        var tagged = Data([bytes == nil ? 0 : 1])
        if let bytes { tagged.append(bytes) }
        return digest(tagged)
    }
    static func completion(for plan: NFRestoreJournalPlan) -> NFRestoreJournalCompletion {
        .init(rawAfterDigest: plan.raw.afterDigest,
              fileAfterDigests: Dictionary(uniqueKeysWithValues: plan.files.map { ($0.id, fileStateDigest($0.after)) }),
              acceptedCounts: plan.acceptedCounts)
    }

    @MainActor
    static func reconcile(_ loaded: NFRestoreJournalLoaded, current: NFDataArchiveRawSnapshot,
                          files: [String: Data?]) throws -> NFRestoreJournalReconciliation {
        try validate(loaded.descriptor)
        try validate(loaded.progress, descriptor: loaded.descriptor)
        try validate(loaded.plan)
        let bytes = try encode(loaded.plan, maximumBytes: loaded.descriptor.planByteCount)
        guard digest(bytes) == loaded.descriptor.planDigest, bytes.count == loaded.descriptor.planByteCount,
              loaded.plan.transactionID == loaded.descriptor.transactionID,
              loaded.plan.namespace == loaded.descriptor.namespace,
              loaded.plan.installationOwnerID == loaded.descriptor.installationOwnerID,
              loaded.progress.completion == nil || loaded.progress.completion == completion(for: loaded.plan) else {
            throw NFRestoreJournalError.digestMismatch
        }
        try loaded.plan.validateSupportedRawContract()
        try NFDataArchiveRawCapture.validate(current)
        guard loaded.progress.phase != .invalidated && loaded.progress.phase != .cleaned else { throw NFRestoreJournalError.invalidated }
        guard Set(files.keys) == Set(loaded.plan.files.map(\.id)) else { throw NFRestoreJournalError.recoveryConflict }
        func domain(_ domain: NFDataArchiveRawDatabaseDomain) throws -> NFRestoreJournalReconciliation.Disposition {
            let before = NFDataArchiveRawSnapshot(tables: loaded.plan.raw.before.tables.filter { $0.domain == domain })
            let after = NFDataArchiveRawSnapshot(tables: loaded.plan.raw.after.tables.filter { $0.domain == domain })
            let actual = NFDataArchiveRawSnapshot(tables: current.tables.filter { $0.domain == domain })
            let bytes = try actual.contentBytes()
            if bytes == (try after.contentBytes()) { return .alreadyApplied }
            if bytes == (try before.contentBytes()) { return .needsApplication }
            return .conflict
        }
        var dispositions: [String: NFRestoreJournalReconciliation.Disposition] = [:]
        for operation in loaded.plan.files {
            // Key membership was checked above; its value may explicitly be nil.
            let actual = files[operation.id]!
            dispositions[operation.id] = actual == operation.after ? .alreadyApplied :
                (actual == operation.before ? .needsApplication : .conflict)
        }
        let result = try NFRestoreJournalReconciliation(durableDatabase: domain(.durable),
            localDatabase: domain(.localOnly), files: dispositions)
        // A later deletion must not resurrect an already completed restore.
        if loaded.progress.phase == .verifiedComplete && !result.isComplete { throw NFRestoreJournalError.recoveryConflict }
        return result
    }
}

/// A single actor serializes this instance; a nonblocking advisory file lock
/// serializes cooperating processes. It is NOT the application/CloudKit fence.
/// Directory names are the bounded discovery index: a staged directory is never
/// accepted; atomically renaming it to its UUID publishes immutable authority.
actor NFDataArchiveRestoreJournal {
    enum Boundary: CaseIterable, Equatable, Sendable {
        case beforePlanWrite, afterPlanWrite, beforeDescriptorWrite, afterDescriptorWrite
        case beforeInitialProgressWrite, afterInitialProgressWrite
        case beforeAcceptancePublish, afterAcceptancePublish
        case beforeProgressPublish, afterProgressPublish
        case beforeInvalidationPublish, afterInvalidationPublish, beforeCleanup, beforeCleanupReceipt, afterCleanup
    }
    private let root: URL
    private let maximumPlanBytes: Int
    private let maximumTransactions: Int
    private let fault: @Sendable (Boundary) throws -> Void
    private static let maximumMetadataBytes = 64 * 1_024

    init(root: URL, maximumPlanBytes: Int = 64 * 1_024 * 1_024, maximumTransactions: Int = 32,
         fault: @escaping @Sendable (Boundary) throws -> Void = { _ in }) {
        self.root = root; self.maximumPlanBytes = maximumPlanBytes
        self.maximumTransactions = maximumTransactions; self.fault = fault
    }

    func inspect(namespace: String, installationOwnerID: UUID) throws -> [NFRestoreJournalInspection] {
        try withLock { try inspections(namespace: namespace, owner: installationOwnerID) }
    }

    /// Shared source and local-derived stores require discovery across account
    /// namespaces before opening any container. This reveals metadata only;
    /// loading or replaying a payload still requires its exact owner binding.
    func inspectAllNamespaces() throws -> [NFRestoreJournalInspection] {
        try withLock { try inspections(namespace: nil, owner: nil) }
    }

    func accept(_ plan: NFRestoreJournalPlan) async throws -> NFRestoreJournalLoaded {
        try NFRestoreJournalCodec.validate(plan)
        try await plan.validateSupportedRawContract()
        let bytes = try NFRestoreJournalCodec.encode(plan, maximumBytes: maximumPlanBytes)
        let descriptor = NFRestoreJournalDescriptor(version: 1, transactionID: plan.transactionID,
            namespace: plan.namespace, installationOwnerID: plan.installationOwnerID,
            planDigest: NFRestoreJournalCodec.digest(bytes), planByteCount: bytes.count)
        return try withLock {
            // Completed transactions from a different account retain private
            // before-images but do not own a new restore. Payload access for a
            // reused ID still checks the exact namespace and installation.
            let all = try inspections(namespace: nil, owner: nil)
            if let prior = all.first(where: { !$0.isStaging && $0.transactionID == plan.transactionID }) {
                guard prior.progress?.phase != .invalidated && prior.progress?.phase != .cleaned else {
                    throw NFRestoreJournalError.invalidated
                }
                let existing = try loadUnlocked(plan.transactionID, namespace: plan.namespace, owner: plan.installationOwnerID)
                guard existing.descriptor == descriptor,
                      try NFRestoreJournalCodec.encode(existing.plan, maximumBytes: maximumPlanBytes) == bytes else {
                    throw NFRestoreJournalError.conflictingPlan
                }
                guard existing.progress.phase != .invalidated else { throw NFRestoreJournalError.invalidated }
                return existing
            }
            guard !all.contains(where: { !$0.isStaging &&
                $0.progress?.phase != .verifiedComplete && $0.progress?.phase != .invalidated && $0.progress?.phase != .cleaned }) else {
                throw NFRestoreJournalError.conflictingPlan
            }
            guard all.contains(where: { $0.transactionID == plan.transactionID }) || all.count < maximumTransactions else {
                throw NFRestoreJournalError.tooManyTransactions
            }
            let staging = directory(plan.transactionID, staging: true)
            try makePrivateDirectory(staging)
            let planURL = staging.appendingPathComponent("plan.json")
            if exists(planURL) {
                guard try read(planURL, maximumBytes: maximumPlanBytes) == bytes else { throw NFRestoreJournalError.conflictingPlan }
            }
            try fault(.beforePlanWrite)
            try atomicWrite(bytes, to: planURL)
            try fault(.afterPlanWrite)
            try fault(.beforeDescriptorWrite)
            try atomicWrite(NFRestoreJournalCodec.encode(descriptor, maximumBytes: Self.maximumMetadataBytes),
                            to: staging.appendingPathComponent("accepted.json"))
            try fault(.afterDescriptorWrite)
            let progress = NFRestoreJournalProgress(version: 1, transactionID: plan.transactionID,
                planDigest: descriptor.planDigest, revision: 0, phase: .accepted, completion: nil)
            try fault(.beforeInitialProgressWrite)
            try atomicWrite(NFRestoreJournalCodec.encode(progress, maximumBytes: Self.maximumMetadataBytes),
                            to: staging.appendingPathComponent("progress.json"))
            try fault(.afterInitialProgressWrite)
            // Re-read all preserved originals before publishing acceptance.
            let verified = try loadDirectory(staging, transactionID: plan.transactionID, namespace: plan.namespace,
                                             owner: plan.installationOwnerID)
            guard verified.descriptor == descriptor else { throw NFRestoreJournalError.digestMismatch }
            try syncDirectory(staging)
            try fault(.beforeAcceptancePublish)
            guard Darwin.rename(staging.path, directory(plan.transactionID).path) == 0 else { throw NFRestoreJournalError.ioFailure }
            try syncDirectory(root)
            try fault(.afterAcceptancePublish)
            return verified
        }
    }

    func load(transactionID: UUID, namespace: String, installationOwnerID: UUID) async throws -> NFRestoreJournalLoaded {
        let value = try withLock { try loadUnlocked(transactionID, namespace: namespace, owner: installationOwnerID) }
        try await value.plan.validateSupportedRawContract()
        return value
    }

    /// A fully written plan may exist before the accepted-directory rename.
    /// This value has NO mutation authority. A cold coordinator must authenticate
    /// it against the exact restart request, reviewed/fresh predecessor and owner,
    /// then call accept. Reusing its bytes avoids recompiling opaque Set payloads.
    /// Missing plan is nil; an existing corrupt/unknown/foreign plan stays blocked.
    func loadUnacceptedCandidate(transactionID: UUID, namespace: String,
                                 installationOwnerID: UUID) async throws -> NFRestoreJournalPlan? {
        let candidate: NFRestoreJournalPlan? = try withLock {
            var metadata = stat()
            let accepted = directory(transactionID)
            if lstat(accepted.path, &metadata) == 0 { throw NFRestoreJournalError.conflictingPlan }
            guard errno == ENOENT else { throw NFRestoreJournalError.ioFailure }
            let staging = directory(transactionID, staging: true)
            if lstat(staging.path, &metadata) != 0 {
                guard errno == ENOENT else { throw NFRestoreJournalError.ioFailure }
                return nil
            }
            try ensureDirectory(staging)
            let url = staging.appendingPathComponent("plan.json")
            if lstat(url.path, &metadata) != 0 {
                guard errno == ENOENT else { throw NFRestoreJournalError.ioFailure }
                return nil
            }
            let bytes = try read(url, maximumBytes: maximumPlanBytes)
            let plan = try NFRestoreJournalCodec.decode(NFRestoreJournalPlan.self, bytes: bytes, maximumBytes: maximumPlanBytes)
            try NFRestoreJournalCodec.validate(plan)
            guard plan.transactionID == transactionID, plan.namespace == namespace,
                  plan.installationOwnerID == installationOwnerID else { throw NFRestoreJournalError.wrongOwner }
            return plan
        }
        if let candidate { try await candidate.validateSupportedRawContract() }
        return candidate
    }

    /// CAS plus exact-state idempotency: a write that succeeded before a thrown
    /// callback is acknowledged on retry without incrementing the revision.
    func mark(transactionID: UUID, namespace: String, installationOwnerID: UUID,
              expectedRevision: UInt64, phase: NFRestoreJournalPhase) async throws -> NFRestoreJournalProgress {
        guard phase == .mutationMayHaveStarted || phase == .recoveryRequired else { throw NFRestoreJournalError.malformed }
        let verified = try await load(transactionID: transactionID, namespace: namespace, installationOwnerID: installationOwnerID)
        return try withLock {
            let loaded = try loadUnlocked(transactionID, namespace: namespace, owner: installationOwnerID)
            guard loaded.descriptor == verified.descriptor else { throw NFRestoreJournalError.conflictingPlan }
            return try publishProgress(loaded, expectedRevision: expectedRevision, phase: phase, completion: nil)
        }
    }

    /// Caller supplies a freshly captured full census and observed file bytes
    /// while holding the external write fence. This API does not acquire it.
    func verifyComplete(transactionID: UUID, namespace: String, installationOwnerID: UUID,
                        expectedRevision: UInt64, current: NFDataArchiveRawSnapshot,
                        files: [String: Data?]) async throws -> NFRestoreJournalProgress {
        let loaded = try await load(transactionID: transactionID, namespace: namespace, installationOwnerID: installationOwnerID)
        let reconciliation = try await NFRestoreJournalCodec.reconcile(loaded, current: current, files: files)
        guard reconciliation.isComplete else { throw NFRestoreJournalError.recoveryConflict }
        return try withLock {
            let fresh = try loadUnlocked(transactionID, namespace: namespace, owner: installationOwnerID)
            guard fresh.descriptor == loaded.descriptor else { throw NFRestoreJournalError.conflictingPlan }
            return try publishProgress(fresh, expectedRevision: expectedRevision, phase: .verifiedComplete,
                                       completion: NFRestoreJournalCodec.completion(for: fresh.plan))
        }
    }

    /// Must succeed BEFORE linked live-data deletion. Invalidation survives a
    /// subsequent cleanup failure and permanently removes replay authority.
    func invalidate(transactionID: UUID, namespace: String, installationOwnerID: UUID,
                    expectedRevision: UInt64) throws -> NFRestoreJournalProgress {
        try withLock {
            let (_, progress) = try metadata(directory(transactionID), transactionID: transactionID,
                namespace: namespace, owner: installationOwnerID)
            if progress.phase == .cleaned || progress.phase == .invalidated { return progress }
            let loaded = try loadUnlocked(transactionID, namespace: namespace, owner: installationOwnerID)
            try fault(.beforeInvalidationPublish)
            let value = try publishProgress(loaded, expectedRevision: expectedRevision, phase: .invalidated, completion: nil)
            try fault(.afterInvalidationPublish)
            return value
        }
    }

    /// Completion alone never drops before-images. Cleanup is explicit and
    /// requires a durable invalidation (or an unaccepted staging directory).
    func removeInvalidated(transactionID: UUID, namespace: String, installationOwnerID: UUID) throws {
        try withLock {
            let accepted = directory(transactionID)
            let staging = directory(transactionID, staging: true)
            if exists(accepted) {
                let (descriptor, progress) = try metadata(accepted, transactionID: transactionID,
                    namespace: namespace, owner: installationOwnerID)
                if progress.phase == .cleaned { return }
                guard progress.phase == .invalidated else { throw NFRestoreJournalError.recoveryConflict }
                try fault(.beforeCleanup)
                // Keep a small command tombstone: removing its identity would
                // let an old pending caller accept the same plan after deletion.
                let removals = try directoryEntries(accepted, maximum: 32).filter {
                    !["accepted.json", "progress.json"].contains($0.lastPathComponent)
                }
                // Interrupted atomic writes can retain temporary copies of raw
                // bytes; they are linked private material too, never just noise.
                for artifact in removals { try FileManager.default.removeItem(at: artifact) }
                try syncDirectory(accepted)
                try fault(.beforeCleanupReceipt)
                guard progress.revision < UInt64.max else { throw NFRestoreJournalError.staleRevision }
                let cleaned = NFRestoreJournalProgress(version: 1, transactionID: transactionID,
                    planDigest: descriptor.planDigest, revision: progress.revision + 1, phase: .cleaned, completion: nil)
                try atomicWrite(NFRestoreJournalCodec.encode(cleaned, maximumBytes: Self.maximumMetadataBytes),
                    to: accepted.appendingPathComponent("progress.json"))
                try fault(.afterCleanup)
            } else if exists(staging) {
                // No accepted-directory rename ever occurred for this ID.
                try ensureDirectory(staging)
                try fault(.beforeCleanup)
                try FileManager.default.removeItem(at: staging)
                try syncDirectory(root)
                try fault(.afterCleanup)
            }
        }
    }

    private func publishProgress(_ loaded: NFRestoreJournalLoaded, expectedRevision: UInt64,
                                 phase: NFRestoreJournalPhase, completion: NFRestoreJournalCompletion?) throws -> NFRestoreJournalProgress {
        let old = loaded.progress
        if old.phase == phase, old.completion == completion,
           old.revision == expectedRevision || (expectedRevision < UInt64.max && old.revision == expectedRevision + 1) { return old }
        guard old.phase != .invalidated && old.phase != .cleaned else { throw NFRestoreJournalError.invalidated }
        guard old.revision == expectedRevision, old.revision < UInt64.max else { throw NFRestoreJournalError.staleRevision }
        guard phase == .invalidated || (old.phase != .verifiedComplete &&
              !(old.phase == .recoveryRequired && phase == .mutationMayHaveStarted)) else { throw NFRestoreJournalError.recoveryConflict }
        let next = NFRestoreJournalProgress(version: 1, transactionID: old.transactionID, planDigest: old.planDigest,
            revision: old.revision + 1, phase: phase, completion: completion)
        try NFRestoreJournalCodec.validate(next, descriptor: loaded.descriptor)
        try fault(.beforeProgressPublish)
        try atomicWrite(NFRestoreJournalCodec.encode(next, maximumBytes: Self.maximumMetadataBytes),
                        to: directory(old.transactionID).appendingPathComponent("progress.json"))
        try fault(.afterProgressPublish)
        return next
    }

    private func inspections(namespace: String?, owner: UUID?) throws -> [NFRestoreJournalInspection] {
        guard maximumTransactions > 0, maximumTransactions <= 1_024 else { throw NFRestoreJournalError.tooManyTransactions }
        var values: [NFRestoreJournalInspection] = []
        for url in try directoryEntries(root, maximum: maximumTransactions + 1) {
            if url.lastPathComponent == "journal.lock" { continue }
            let name = url.lastPathComponent
            let staging = name.hasPrefix(".staging-")
            let identity = staging ? String(name.dropFirst(".staging-".count)) : name
            guard let id = UUID(uuidString: identity), identity == id.uuidString.lowercased() else { throw NFRestoreJournalError.malformed }
            try ensureDirectory(url)
            if staging {
                values.append(.init(transactionID: id, isStaging: true, descriptor: nil, progress: nil))
            } else {
                let (descriptor, progress) = try metadata(url, transactionID: id, namespace: namespace, owner: owner)
                values.append(.init(transactionID: id, isStaging: false, descriptor: descriptor, progress: progress))
            }
        }
        guard Set(values.map(\.transactionID)).count == values.count else { throw NFRestoreJournalError.malformed }
        return values.sorted { $0.transactionID.uuidString < $1.transactionID.uuidString }
    }

    private func loadUnlocked(_ id: UUID, namespace: String, owner: UUID) throws -> NFRestoreJournalLoaded {
        try loadDirectory(directory(id), transactionID: id, namespace: namespace, owner: owner)
    }
    private func loadDirectory(_ url: URL, transactionID: UUID, namespace: String, owner: UUID) throws -> NFRestoreJournalLoaded {
        try ensureDirectory(url)
        let (descriptor, progress) = try metadata(url, transactionID: transactionID, namespace: namespace, owner: owner)
        guard progress.phase != .cleaned else { throw NFRestoreJournalError.invalidated }
        let bytes = try read(url.appendingPathComponent("plan.json"), maximumBytes: maximumPlanBytes)
        guard bytes.count == descriptor.planByteCount, NFRestoreJournalCodec.digest(bytes) == descriptor.planDigest else {
            throw NFRestoreJournalError.digestMismatch
        }
        let plan = try NFRestoreJournalCodec.decode(NFRestoreJournalPlan.self, bytes: bytes, maximumBytes: maximumPlanBytes)
        try NFRestoreJournalCodec.validate(plan)
        guard plan.transactionID == descriptor.transactionID, plan.namespace == descriptor.namespace,
              plan.installationOwnerID == descriptor.installationOwnerID else { throw NFRestoreJournalError.wrongOwner }
        if let completion = progress.completion {
            guard completion == NFRestoreJournalCodec.completion(for: plan) else { throw NFRestoreJournalError.digestMismatch }
        }
        return .init(descriptor: descriptor, progress: progress, plan: plan)
    }
    private func metadata(_ url: URL, transactionID: UUID, namespace: String?, owner: UUID?) throws -> (NFRestoreJournalDescriptor, NFRestoreJournalProgress) {
        let descriptor = try NFRestoreJournalCodec.decode(NFRestoreJournalDescriptor.self,
            bytes: read(url.appendingPathComponent("accepted.json"), maximumBytes: Self.maximumMetadataBytes),
            maximumBytes: Self.maximumMetadataBytes)
        try NFRestoreJournalCodec.validate(descriptor)
        guard descriptor.transactionID == transactionID,
              namespace.map({ descriptor.namespace == $0 }) ?? true,
              owner.map({ descriptor.installationOwnerID == $0 }) ?? true else { throw NFRestoreJournalError.wrongOwner }
        guard descriptor.planByteCount <= maximumPlanBytes else { throw NFRestoreJournalError.oversized }
        let progress = try NFRestoreJournalCodec.decode(NFRestoreJournalProgress.self,
            bytes: read(url.appendingPathComponent("progress.json"), maximumBytes: Self.maximumMetadataBytes),
            maximumBytes: Self.maximumMetadataBytes)
        try NFRestoreJournalCodec.validate(progress, descriptor: descriptor)
        return (descriptor, progress)
    }
    private func directory(_ id: UUID, staging: Bool = false) -> URL {
        root.appendingPathComponent((staging ? ".staging-" : "") + id.uuidString.lowercased(), isDirectory: true)
    }
    /// Bounded POSIX enumeration propagates a directory read failure. A
    /// Foundation enumerator's default error handler could silently skip it.
    private func directoryEntries(_ url: URL, maximum: Int) throws -> [URL] {
        let fd = Darwin.open(url.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW)
        guard fd >= 0 else { throw NFRestoreJournalError.ioFailure }
        guard let directory = fdopendir(fd) else { Darwin.close(fd); throw NFRestoreJournalError.ioFailure }
        defer { closedir(directory) }
        var values: [URL] = []
        while true {
            errno = 0
            guard let entry = readdir(directory) else {
                guard errno == 0 else { throw NFRestoreJournalError.ioFailure }
                break
            }
            let capacity = Int(entry.pointee.d_namlen) + 1
            let name = withUnsafePointer(to: &entry.pointee.d_name) { tuple in
                tuple.withMemoryRebound(to: CChar.self, capacity: capacity) { String(validatingCString: $0) }
            }
            guard let name else { throw NFRestoreJournalError.unsafePath }
            if name == "." || name == ".." { continue }
            guard values.count < maximum else { throw NFRestoreJournalError.tooManyTransactions }
            values.append(url.appendingPathComponent(name))
        }
        return values
    }
    private func exists(_ url: URL) -> Bool {
        var value = stat()
        return lstat(url.path, &value) == 0
    }
    private func ensureDirectory(_ url: URL) throws {
        var value = stat()
        guard lstat(url.path, &value) == 0, value.st_mode & S_IFMT == S_IFDIR else { throw NFRestoreJournalError.unsafePath }
    }
    private func makePrivateDirectory(_ url: URL) throws {
        guard url.isFileURL else { throw NFRestoreJournalError.unsafePath }
        if !exists(url) {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700])
        }
        try ensureDirectory(url)
        guard chmod(url.path, 0o700) == 0 else { throw NFRestoreJournalError.ioFailure }
        #if os(iOS)
        try FileManager.default.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication], ofItemAtPath: url.path)
        #endif
    }
    private func withLock<T>(_ operation: () throws -> T) throws -> T {
        try makePrivateDirectory(root)
        let fd = Darwin.open(root.appendingPathComponent("journal.lock").path, O_CREAT | O_RDWR | O_NOFOLLOW | O_NONBLOCK, 0o600)
        guard fd >= 0 else { throw NFRestoreJournalError.ioFailure }
        defer { Darwin.close(fd) }
        var value = stat()
        guard fstat(fd, &value) == 0, value.st_mode & S_IFMT == S_IFREG, value.st_nlink == 1 else {
            throw NFRestoreJournalError.unsafePath
        }
        guard flock(fd, LOCK_EX | LOCK_NB) == 0 else {
            if errno == EWOULDBLOCK || errno == EAGAIN { throw NFRestoreJournalError.busy }
            throw NFRestoreJournalError.ioFailure
        }
        defer { flock(fd, LOCK_UN) }
        return try operation()
    }
    private func read(_ url: URL, maximumBytes: Int) throws -> Data {
        guard maximumBytes > 0 else { throw NFRestoreJournalError.oversized }
        // Reject pipes and other special files after opening without blocking
        // startup recovery while waiting for a writer that may never arrive.
        let fd = Darwin.open(url.path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK)
        guard fd >= 0 else { throw NFRestoreJournalError.ioFailure }
        defer { Darwin.close(fd) }
        var value = stat()
        guard fstat(fd, &value) == 0, value.st_mode & S_IFMT == S_IFREG, value.st_nlink == 1 else {
            throw NFRestoreJournalError.unsafePath
        }
        guard value.st_size >= 0, value.st_size <= maximumBytes else { throw NFRestoreJournalError.oversized }
        var result = Data()
        var buffer = [UInt8](repeating: 0, count: min(65_536, maximumBytes))
        while true {
            let count = buffer.withUnsafeMutableBytes { Darwin.read(fd, $0.baseAddress, $0.count) }
            if count < 0 { if errno == EINTR { continue }; throw NFRestoreJournalError.ioFailure }
            if count == 0 { break }
            guard count <= maximumBytes - result.count else { throw NFRestoreJournalError.oversized }
            result.append(contentsOf: buffer.prefix(count))
        }
        return result
    }
    private func atomicWrite(_ bytes: Data, to destination: URL) throws {
        let parent = destination.deletingLastPathComponent()
        try ensureDirectory(parent)
        let temporary = parent.appendingPathComponent(".write-" + UUID().uuidString.lowercased())
        let fd = Darwin.open(temporary.path, O_CREAT | O_EXCL | O_WRONLY | O_NOFOLLOW, 0o600)
        guard fd >= 0 else { throw NFRestoreJournalError.ioFailure }
        defer { Darwin.close(fd); _ = unlink(temporary.path) }
        #if os(iOS)
        try FileManager.default.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication], ofItemAtPath: temporary.path)
        #endif
        try bytes.withUnsafeBytes { raw in
            var offset = 0
            while offset < raw.count {
                guard let base = raw.baseAddress else { throw NFRestoreJournalError.ioFailure }
                let count = Darwin.write(fd, base.advanced(by: offset), raw.count - offset)
                if count < 0 { if errno == EINTR { continue }; throw NFRestoreJournalError.ioFailure }
                guard count > 0 else { throw NFRestoreJournalError.ioFailure }
                offset += count
            }
        }
        guard fsync(fd) == 0 else { throw NFRestoreJournalError.ioFailure }
        guard Darwin.rename(temporary.path, destination.path) == 0 else { throw NFRestoreJournalError.ioFailure }
        try syncDirectory(parent)
    }
    private func syncDirectory(_ url: URL) throws {
        let fd = Darwin.open(url.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW)
        guard fd >= 0 else { throw NFRestoreJournalError.ioFailure }
        defer { Darwin.close(fd) }
        guard fsync(fd) == 0 else { throw NFRestoreJournalError.ioFailure }
    }
}

// MARK: - Cold-start restore plan compiler and domain bridge

/// Not startup authority: the owning coordinator must hold the process-lifetime
/// NFApplicationStoreLease and open a fresh local-only container. A UI preview
/// captures this value; cold startup captures it again before compilation.
struct NFRestoreDestinationSnapshot: Codable, Sendable {
    let version: Int
    let raw: NFDataArchiveRawSnapshot
    let localLearningBytes: Data?
    let adaptiveHistoryBytes: Data?
    let aiLearningArtifacts: [NFAILearningArtifactFile]?

    init(raw: NFDataArchiveRawSnapshot, localLearningBytes: Data?, adaptiveHistoryBytes: Data?,
         aiLearningArtifacts: [NFAILearningArtifactFile] = []) {
        version = 1; self.raw = raw
        self.localLearningBytes = localLearningBytes; self.adaptiveHistoryBytes = adaptiveHistoryBytes
        self.aiLearningArtifacts = aiLearningArtifacts.isEmpty ? nil : aiLearningArtifacts.sorted { $0.relativePath < $1.relativePath }
    }

    var reviewDigest: String {
        get throws {
            struct Identity: Encodable {
                let version: Int
                let rawDigest: String
                let localLearningBytes: Data?
                let adaptiveHistoryBytes: Data?
                let aiLearningArtifacts: [NFAILearningArtifactFile]?
            }
            return NFRestoreJournalCodec.digest(try NFDataArchiveRawSnapshot.canonicalEncode(
                Identity(version: version, rawDigest: raw.contentDigest(),
                    localLearningBytes: localLearningBytes, adaptiveHistoryBytes: adaptiveHistoryBytes,
                    aiLearningArtifacts: aiLearningArtifacts)))
        }
    }
}

struct NFRestoreCompiledCounts: Equatable, Sendable {
    let restored: [String: Int]
    let skipped: [String: Int]
    static var supportedKeys: Set<String> {
        let categories = NFDataArchiveCategory.allCases.map(\.rawValue) + [
            "local.sessions", "local.snapshots", "local.savedSets", "local.privateStudyRuns",
            "local.evidenceDispositions", "local.contentCorrections", "local.attemptConflicts", "local.unavailableHistorySnapshots", "local.aiArtifacts"
        ]
        return Set(categories.flatMap { ["restored." + $0, "skipped." + $0] })
    }
    init(plan: NFRestoreJournalPlan) throws {
        if plan.resultCountsVersion == nil {
            guard Set(plan.acceptedCounts.keys).isSubset(of: Set(NFDataArchiveCategory.allCases.map(\.rawValue))),
                  plan.acceptedCounts.values.allSatisfy({ $0 >= 0 }) else { throw NFRestoreJournalError.malformed }
            restored = plan.acceptedCounts; skipped = [:]; return
        }
        guard plan.resultCountsVersion == 1 else { throw NFRestoreJournalError.unsupportedVersion }
        var restored: [String: Int] = [:], skipped: [String: Int] = [:]
        for (key, count) in plan.acceptedCounts {
            guard count >= 0 else { throw NFRestoreJournalError.malformed }
            if key.hasPrefix("restored.") { restored[String(key.dropFirst(9))] = count }
            else if key.hasPrefix("skipped.") { skipped[String(key.dropFirst(8))] = count }
            else { throw NFRestoreJournalError.unsupportedVersion }
        }
        self.restored = restored; self.skipped = skipped
    }
}

@MainActor
enum NFRestorePlanCompiler {
    static let maximumBytes = NFLocalSessionRepository.maximumBytes
    static let localLearningFilename = "sessions-v1.json"
    static let adaptiveHistoryFilename = "AdaptivePlanHistory-v1.json"

    static func captureDestination(context: ModelContext, localLearningBytes: Data?,
                                   adaptiveHistoryBytes: Data?, aiLearningArtifacts: [NFAILearningArtifactFile] = []) throws -> NFRestoreDestinationSnapshot {
        for bytes in [localLearningBytes, adaptiveHistoryBytes].compactMap({ $0 }) {
            guard bytes.count <= maximumBytes else { throw NFRestoreJournalError.oversized }
        }
        try NFAILearningArtifactArchive.validate(aiLearningArtifacts)
        return .init(raw: try NFDataArchiveRawCapture.capture(context: context),
            localLearningBytes: localLearningBytes, adaptiveHistoryBytes: adaptiveHistoryBytes,
            aiLearningArtifacts: aiLearningArtifacts)
    }

    nonisolated static func permittedPayload(prepared: NFPreparedDataArchive) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        let bytes = try encoder.encode(prepared.archive)
        guard bytes.count <= NFLocalSessionRepository.maximumBytes else { throw NFRestoreJournalError.oversized }
        // The full export/restore protection boundary is repeated at staging,
        // including marker-only evaluator aliases and opaque payload graphs.
        return try NFDataExportService.protectedPortableData(bytes, forRestore: true)
    }

    /// JSON object key order/whitespace is not semantic. Known Set fields and
    /// canonical JSON inside private payload Data may reorder on decoding. Keep
    /// all ordered question/response/event arrays exact. A dropped evaluator,
    /// field, record, scalar change or protected graph can never compare equal.
    nonisolated private static func validateFrozenPermittedPayload(_ bytes: Data) throws {
        guard bytes.count <= NFLocalSessionRepository.maximumBytes else { throw NFRestoreJournalError.oversized }
        _ = try NFDataExportRoundTripValidator.decodeArchive(data: bytes)
        let protected = try NFDataExportService.protectedPortableData(bytes, forRestore: true)
        let unorderedKeys: Set<String> = ["consumedPositions", "retainedPlanPositions", "semanticExclusions",
            "favoriteActivities", "sourceIDs", "savedSetIDs"]
        func canonical(_ value: Any, key: String? = nil, depth: Int = 0) throws -> Any {
            guard depth <= 48 else { throw NFRestoreJournalError.oversized }
            if key == "payload", let text = value as? String,
               text.utf8.count <= 12 * 1_024 * 1_024, let data = Data(base64Encoded: text),
               data.count <= 8 * 1_024 * 1_024,
               let object = try? JSONSerialization.jsonObject(with: data), JSONSerialization.isValidJSONObject(object) {
                return ["$base64JSON": try canonical(object, depth: depth + 1)]
            }
            if let object = value as? [String: Any] {
                return try object.keys.reduce(into: [String: Any]()) { result, field in
                    result[field] = try canonical(object[field]!, key: field, depth: depth + 1)
                }
            }
            if let array = value as? [Any] {
                let normalized = try array.map { try canonical($0, depth: depth + 1) }
                guard key.map({ unorderedKeys.contains($0) }) == true else { return normalized }
                return try normalized.map { (bytes: try JSONSerialization.data(withJSONObject: $0,
                    options: [.sortedKeys, .fragmentsAllowed, .withoutEscapingSlashes]), value: $0) }
                    .sorted { $0.bytes.lexicographicallyPrecedes($1.bytes) }.map(\.value)
            }
            return value
        }
        let original = try JSONSerialization.data(withJSONObject: canonical(JSONSerialization.jsonObject(with: bytes)),
            options: [.sortedKeys, .fragmentsAllowed, .withoutEscapingSlashes])
        let permitted = try JSONSerialization.data(withJSONObject: canonical(JSONSerialization.jsonObject(with: protected)),
            options: [.sortedKeys, .fragmentsAllowed, .withoutEscapingSlashes])
        guard original == permitted else { throw NFRestoreJournalError.malformed }
    }

    nonisolated static func preparedFromPermittedPayload(_ data: Data, sourceDigest: String,
        sourceByteCount: Int, sourceFilename: String) throws -> NFPreparedDataArchive {
        guard data.count <= NFLocalSessionRepository.maximumBytes,
              (0...NFLocalSessionRepository.maximumBytes).contains(sourceByteCount),
              sourceDigest.count == 64, sourceDigest.allSatisfy({ $0.isHexDigit }),
              sourceFilename.utf8.count <= 1_024 else { throw NFRestoreJournalError.malformed }
        _ = try NFDataExportRoundTripValidator.decodeArchive(data: data)
        let normalized = try NFDataArchiveMigration.normalizedData(from: data)
        let permitted = try NFDataExportService.protectedPortableData(normalized, forRestore: true)
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        let archive = try decoder.decode(NFDataExportService.Archive.self, from: permitted)
        return .init(archive: archive, sourceDigest: sourceDigest, sourceByteCount: sourceByteCount,
            sourceFilename: sourceFilename)
    }

    static func preview(prepared: NFPreparedDataArchive, destination: NFRestoreDestinationSnapshot,
                        locale: Locale) throws -> NFDataArchiveRestorePreview {
        guard destination.version == 1 else { throw NFRestoreJournalError.unsupportedVersion }
        for bytes in [destination.localLearningBytes, destination.adaptiveHistoryBytes].compactMap({ $0 }) {
            guard bytes.count <= maximumBytes else { throw NFRestoreJournalError.oversized }
        }
        let payload = try permittedPayload(prepared: prepared)
        let frozen = try preparedFromPermittedPayload(payload, sourceDigest: prepared.sourceDigest,
            sourceByteCount: prepared.sourceByteCount, sourceFilename: prepared.sourceFilename)
        let history = try decodeHistory(destination.adaptiveHistoryBytes)
        var result = try NFDataArchiveRestoreService.previewRawInputs(archive: frozen.archive,
            before: destination.raw, existingHistory: history, locale: locale)
        let prior: NFLocalSessionRepository.Archive
        if let bytes = destination.localLearningBytes {
            prior = try JSONDecoder().decode(NFLocalSessionRepository.Archive.self, from: bytes)
            try requireNoUnknownFields(bytes, encoded: JSONEncoder().encode(prior))
        } else { prior = .init() }
        // Fixed arbitrary owner is confined to validation-only in-memory stores;
        // no imported run is granted continuation by a cold restore preview.
        let validationOwner = UUID(uuidString: "00000000-0000-0000-0000-000000000000")!
        let validation = NFLocalSessionRepository(ownerDeviceID: validationOwner)
        try validation.restorePredecessor(prior); try validation.importArchive(.init())
        let incoming = frozen.archive.localLearning ?? .init()
        let incomingValidation = NFLocalSessionRepository(ownerDeviceID: validationOwner)
        try incomingValidation.importArchive(incoming)
        func count<ID: Hashable>(_ key: String, old: [ID], new: [ID]) {
            result.localIncoming[key] = new.count
            result.localConflicts[key] = Set(old).intersection(Set(new)).count
        }
        count("sessions", old: prior.sessions.map(\.id), new: incoming.sessions.map(\.id))
        count("snapshots", old: prior.snapshots.map(\.attemptID), new: incoming.snapshots.map(\.attemptID))
        count("savedSets", old: (prior.savedSets ?? []).map(\.id), new: (incoming.savedSets ?? []).map(\.id))
        count("privateStudyRuns", old: (prior.privateStudyRuns ?? []).map(\.id), new: (incoming.privateStudyRuns ?? []).map(\.id))
        count("evidenceDispositions", old: (prior.evidenceDispositions ?? []).map(\.id), new: (incoming.evidenceDispositions ?? []).map(\.id))
        count("contentCorrections", old: (prior.contentCorrections ?? []).map(\.id), new: (incoming.contentCorrections ?? []).map(\.id))
        count("attemptConflicts", old: (prior.attemptConflicts ?? []).map(\.id), new: (incoming.attemptConflicts ?? []).map(\.id))
        count("unavailableHistorySnapshots", old: (prior.unavailableHistorySnapshots ?? []).map(\.attemptID), new: (incoming.unavailableHistorySnapshots ?? []).map(\.attemptID))
        let oldArtifacts = destination.aiLearningArtifacts ?? []
        let newArtifacts = frozen.archive.aiLearningArtifacts ?? []
        try NFAILearningArtifactArchive.validate(oldArtifacts)
        try NFAILearningArtifactArchive.validate(newArtifacts)
        result.localIncoming["aiArtifacts"] = newArtifacts.count
        let oldFiles = Dictionary(uniqueKeysWithValues: oldArtifacts.map { ($0.relativePath, $0) })
        result.localConflicts["aiArtifacts"] = newArtifacts.filter { incoming in
            oldFiles[incoming.relativePath].map { $0.digest != incoming.digest } == true
        }.count
        return result
    }

    static func compile(prepared: NFPreparedDataArchive, policy: NFDataArchiveRestorePolicy,
        expectedReviewDigest: String, destination: NFRestoreDestinationSnapshot,
        transactionID: UUID, namespace: String, ownerDeviceID: UUID,
        compiledAt: Date, locale: Locale, frozenPermittedPayload: Data? = nil) throws -> NFRestoreJournalPlan {
        guard destination.version == 1, compiledAt.timeIntervalSinceReferenceDate.isFinite,
              try destination.reviewDigest == expectedReviewDigest else { throw NFRestoreJournalError.recoveryConflict }
        for bytes in [destination.localLearningBytes, destination.adaptiveHistoryBytes].compactMap({ $0 }) {
            guard bytes.count <= maximumBytes else { throw NFRestoreJournalError.oversized }
        }
        try NFDataArchiveRawCapture.validate(destination.raw)
        // A restart request already froze the approved permitted bytes. Decode
        // and apply their protected value below, but retain those exact bytes in
        // the plan rather than re-encoding opaque Sets and changing request binding.
        let payload = try frozenPermittedPayload ?? permittedPayload(prepared: prepared)
        if frozenPermittedPayload != nil { try validateFrozenPermittedPayload(payload) }
        let frozen = try preparedFromPermittedPayload(payload, sourceDigest: prepared.sourceDigest,
            sourceByteCount: prepared.sourceByteCount, sourceFilename: prepared.sourceFilename)
        let oldHistory = try decodeHistory(destination.adaptiveHistoryBytes)
        let compiled = try NFDataArchiveRestoreService.compileRawInputs(archive: frozen.archive,
            before: destination.raw, existingHistory: oldHistory, policy: policy, at: compiledAt, locale: locale)
        let history = try compileHistory(incoming: frozen.archive.adaptivePlanHistory ?? [],
            existing: oldHistory, before: destination.adaptiveHistoryBytes, policy: policy)
        let local = try compileLocalLearning(before: destination.localLearningBytes,
            incoming: frozen.archive.localLearning, ownerDeviceID: ownerDeviceID,
            after: compiled.after, incomingCore: frozen.archive, policy: policy, priorRaw: destination.raw)
        let artifacts = try NFAILearningArtifactArchive.operations(existing: destination.aiLearningArtifacts ?? [],
            incoming: frozen.archive.aiLearningArtifacts ?? [], policy: policy)
        var counts = compiled.counts
        counts.merge(local.counts) { _, new in new }
        counts["restored.adaptiveHistory"] = history.restored
        counts["skipped.adaptiveHistory"] = history.skipped
        counts["restored.local.aiArtifacts"] = artifacts.restored
        counts["skipped.local.aiArtifacts"] = artifacts.skipped
        let plan = NFRestoreJournalPlan(transactionID: transactionID, namespace: namespace,
            installationOwnerID: ownerDeviceID, sourceDigest: frozen.sourceDigest,
            permittedPayload: payload, policy: policy, acceptedCounts: counts,
            raw: try .init(before: destination.raw, after: compiled.after), files: [
                .init(id: "local-learning", domain: .localLearning, relativePath: localLearningFilename,
                    before: destination.localLearningBytes, after: local.bytes),
                .init(id: "adaptive-history", domain: .adaptiveHistory, relativePath: adaptiveHistoryFilename,
                    before: destination.adaptiveHistoryBytes, after: history.bytes)
            ] + artifacts.operations, resultCountsVersion: 1)
        try NFRestoreJournalCodec.validate(plan)
        try plan.validateSupportedRawContract()
        _ = try NFRestoreCompiledCounts(plan: plan)
        return plan
    }

    private struct HistoryEnvelope: Codable { let version: Int; let records: [NFAdaptivePlanChangeRecord] }

    private static func decodeHistory(_ bytes: Data?) throws -> [NFAdaptivePlanChangeRecord] {
        guard let bytes else { return [] }
        guard bytes.count <= maximumBytes else { throw NFRestoreJournalError.oversized }
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        let envelope = try decoder.decode(HistoryEnvelope.self, from: bytes)
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        try requireNoUnknownFields(bytes, encoded: encoder.encode(envelope))
        guard envelope.version == 1,
              envelope.records.count <= NFAdaptivePlanHistoryRepository.maximumRecordCount,
              Set(envelope.records.map(\.id)).count == envelope.records.count,
              envelope.records.allSatisfy({ $0.schemaVersion == NFAdaptivePlanChangeRecord.schemaVersion }) else {
            throw NFRestoreJournalError.unsupportedVersion
        }
        return envelope.records
    }

    private static func compileHistory(incoming: [NFAdaptivePlanChangeRecord], existing: [NFAdaptivePlanChangeRecord],
        before: Data?, policy: NFDataArchiveRestorePolicy) throws -> (bytes: Data?, restored: Int, skipped: Int) {
        let incomingIDs = Set(incoming.map(\.id)), existingIDs = Set(existing.map(\.id))
        guard incomingIDs.count == incoming.count else { throw NFRestoreJournalError.malformed }
        let overlap = incomingIDs.intersection(existingIDs)
        if policy == .abortOnConflict, !overlap.isEmpty { throw NFDataArchiveRestoreError.conflictsRequireDecision(overlap.count) }
        let records: [NFAdaptivePlanChangeRecord]
        switch policy {
        case .replaceAll: records = incoming
        case .replaceMatching: records = existing.filter { !incomingIDs.contains($0.id) } + incoming
        case .keepExisting, .abortOnConflict: records = existing + incoming.filter { !existingIDs.contains($0.id) }
        }
        // Never silently evict an old history record when the merged capacity
        // is exceeded. The caller can export or choose another reviewed policy.
        guard records.count <= NFAdaptivePlanHistoryRepository.maximumRecordCount else { throw NFRestoreJournalError.oversized }
        let skipped = policy == .keepExisting ? overlap.count : 0
        guard policy == .replaceAll || !incoming.isEmpty else { return (before, 0, 0) }
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let sorted = records.sorted { $0.occurredAt == $1.occurredAt ? $0.id.uuidString > $1.id.uuidString : $0.occurredAt > $1.occurredAt }
        return (try encoder.encode(HistoryEnvelope(version: 1, records: sorted)), incoming.count - skipped, skipped)
    }

    private static func compileLocalLearning(before: Data?, incoming: NFLocalSessionRepository.Archive?,
        ownerDeviceID: UUID, after: NFDataArchiveRawSnapshot, incomingCore: NFDataExportService.Archive,
        policy: NFDataArchiveRestorePolicy, priorRaw: NFDataArchiveRawSnapshot) throws -> (bytes: Data?, counts: [String: Int]) {
        let predecessor: NFLocalSessionRepository.Archive
        if let before {
            guard before.count <= maximumBytes else { throw NFRestoreJournalError.oversized }
            predecessor = try JSONDecoder().decode(NFLocalSessionRepository.Archive.self, from: before)
            try requireNoUnknownFields(before, encoded: JSONEncoder().encode(predecessor))
        } else { predecessor = .init() }
        let validation = NFLocalSessionRepository(ownerDeviceID: ownerDeviceID)
        try validation.restorePredecessor(predecessor)
        try validation.importArchive(.init())
        let selected = try applyingLocalPolicy(existing: predecessor, incoming: incoming,
            policy: policy, priorRaw: priorRaw, incomingCore: incomingCore)
        let repository = NFLocalSessionRepository(ownerDeviceID: ownerDeviceID)
        try repository.restorePredecessor(selected.existing)
        try repository.importArchive(selected.incoming)
        var merged = repository.archive
        // importArchive also preserves unavailable markers; copy explicitly for
        // compatibility with the already-built older import implementation.
        merged.unavailablePrivateRunIDs = Array(Set(selected.existing.unavailablePrivateRunIDs ?? [])
            .union(selected.incoming.unavailablePrivateRunIDs ?? [])).sorted { $0.uuidString < $1.uuidString }
        try validateLocalReferences(merged, after: after, incomingCore: incomingCore)
        guard incoming != nil || policy == .replaceAll || (policy == .replaceMatching && !incomingCore.attempts.isEmpty) else { return (before, selected.counts) }
        let (revision, overflow) = (predecessor.transactionRevision ?? 0).addingReportingOverflow(1)
        guard !overflow else { throw NFRestoreJournalError.staleRevision }
        merged.transactionRevision = revision
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let bytes = try encoder.encode(merged)
        guard bytes.count <= maximumBytes else { throw NFRestoreJournalError.oversized }
        return (bytes, selected.counts)
    }

    private static func validateLocalReferences(_ archive: NFLocalSessionRepository.Archive,
        after: NFDataArchiveRawSnapshot, incomingCore: NFDataExportService.Archive) throws {
        func ids(_ model: String) throws -> Set<UUID> {
            guard let table = after.tables.first(where: { $0.model == model }) else { throw NFRestoreJournalError.malformed }
            return try Set(table.rows.map { row in
                guard let value = row.columns["id"] else { throw NFRestoreJournalError.malformed }
                return try UUID.fromArchiveRawValue(value)
            })
        }
        let attempts = try ids("AttemptRecord"), generations = try ids("AIGenerationRecord"), documents = try ids("SourceDocumentRecord")
        let pending = Set(archive.sessions.map { $0.checkpoint.attemptID })
        guard archive.snapshots.allSatisfy({ attempts.contains($0.attemptID) || pending.contains($0.attemptID) }),
              (archive.attemptConflicts ?? []).allSatisfy({ attempts.contains($0.attemptID) }) else {
            throw NFDataArchiveRestoreError.invalidArchive("the accepted policy would leave local attempted history without its original record")
        }
        for run in archive.sessions {
            if let committed = run.checkpoint.committedAttemptID, !attempts.contains(committed) {
                throw NFDataArchiveRestoreError.invalidArchive("a retained local session references a removed attempt")
            }
            guard (run.checkpoint.exercise?.provenance.sourceDocumentIDs ?? []).allSatisfy({ UUID(uuidString: $0).map(documents.contains) == true }) else {
                throw NFDataArchiveRestoreError.invalidArchive("a retained local session references a removed source")
            }
        }
        for set in archive.savedSets ?? [] {
            guard set.result.provenance.sourceDocumentIDs.allSatisfy({ documents.contains($0) }) else {
                throw NFDataArchiveRestoreError.invalidArchive("a saved set references a removed source")
            }
        }
        let savedSetIDs = Set((archive.savedSets ?? []).map(\.id))
        if let record = archive.privateStudyRuns?.first(where: { $0.id == NFPrivateStudyMetadata.recordID }) {
            let metadata = try JSONDecoder().decode(NFPrivateStudyMetadata.self, from: record.payload)
            guard metadata.isSupported,
                  metadata.annotations.allSatisfy({ attempts.contains($0.id) }),
                  (metadata.reviewDeferrals ?? []).allSatisfy({ attempts.contains($0.anchorAttemptID) }),
                  metadata.collections.allSatisfy({ $0.sourceIDs.isSubset(of: documents) && $0.savedSetIDs.isSubset(of: savedSetIDs) }) else {
                throw NFDataArchiveRestoreError.invalidArchive("personal organization references removed records")
            }
        }
        for run in archive.privateStudyRuns ?? [] where run.id != NFPrivateStudyMetadata.recordID {
            // Generated drafts carry an actual generation UUID; metadata has its
            // own stable ID and is validated by the repository. Unknown scopes
            // require a compatible migration, never guessed cross-domain refs.
            if !generations.contains(run.generationID) {
                throw NFDataArchiveRestoreError.invalidArchive("a retained draft references a removed generated set")
            }
        }
        _ = incomingCore // Incoming bindings already passed the portable validator.
    }

    /// When changing a side-file, synthesized Codable must not discard unknown
    /// fields. Exact before bytes remain in the plan regardless of this check.
    private static func requireNoUnknownFields(_ original: Data, encoded: Data) throws {
        func containsOnlyKnown(_ original: Any, _ known: Any) -> Bool {
            if let object = original as? [String: Any], let reference = known as? [String: Any] {
                return object.allSatisfy { key, value in
                    guard let expected = reference[key] else { return value is NSNull }
                    return containsOnlyKnown(value, expected)
                }
            }
            if let values = original as? [Any], let reference = known as? [Any] {
                guard values.count == reference.count else { return false }
                return zip(values, reference).allSatisfy { containsOnlyKnown($0.0, $0.1) }
            }
            return true
        }
        guard containsOnlyKnown(try JSONSerialization.jsonObject(with: original),
                               try JSONSerialization.jsonObject(with: encoded)) else {
            throw NFRestoreJournalError.unsupportedVersion
        }
    }
}

fileprivate extension NFDataArchiveRestoreService {
    struct CompiledRawInputs { let after: NFDataArchiveRawSnapshot; let counts: [String: Int] }

    static func previewRawInputs(archive: NFDataExportService.Archive, before: NFDataArchiveRawSnapshot,
        existingHistory: [NFAdaptivePlanChangeRecord], locale: Locale) throws -> NFDataArchiveRestorePreview {
        let schema = Schema(NFSchemaV1.models)
        let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema,
            isStoredInMemoryOnly: true, cloudKitDatabase: .none)])
        let context = ModelContext(container); context.autosaveEnabled = false
        try NFDataArchiveRawCapture.materializeInEmptyContext(before, context: context); try context.save()
        guard try NFDataArchiveRawCapture.capture(context: context).contentBytes() == before.contentBytes() else {
            throw NFDataArchiveRawSnapshotError.materializationMismatch("preview predecessor")
        }
        let census = try NFDataArchiveDestinationCensus(context: context)
        try validate(archive, existingHistory: existingHistory, census: census, policy: nil)
        return makePreview(archive, existingHistory: existingHistory, ownerDeviceID: nil, census: census, locale: locale)
    }

    static func compileRawInputs(archive: NFDataExportService.Archive, before: NFDataArchiveRawSnapshot,
        existingHistory: [NFAdaptivePlanChangeRecord], policy: NFDataArchiveRestorePolicy,
        at date: Date, locale: Locale) throws -> CompiledRawInputs {
        let schema = Schema(NFSchemaV1.models)
        let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema,
            isStoredInMemoryOnly: true, cloudKitDatabase: .none)])
        let original = ModelContext(container); original.autosaveEnabled = false
        try NFDataArchiveRawCapture.materializeInEmptyContext(before, context: original)
        try original.save()
        guard try NFDataArchiveRawCapture.capture(context: original).contentBytes() == before.contentBytes() else {
            throw NFDataArchiveRawSnapshotError.materializationMismatch("staged predecessor")
        }
        let census = try NFDataArchiveDestinationCensus(context: original)
        try validate(archive, existingHistory: existingHistory, census: census, policy: policy)

        let incomingContainer = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema,
            isStoredInMemoryOnly: true, cloudKitDatabase: .none)])
        let incoming = ModelContext(incomingContainer); incoming.autosaveEnabled = false
        if let value = archive.profile { incoming.insert(makeProfile(value)) }
        for value in archive.attempts {
            let record = makeAttempt(value)
            let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
            record.skillWeightsRaw = String(decoding: try encoder.encode(value.skillWeights), as: UTF8.self)
            if let payload = value.transferBrief { record.transferBriefRaw = String(decoding: try encoder.encode(payload), as: UTF8.self) }
            if let payload = value.spatialDifficultyParameters { record.spatialDifficultyParametersRaw = String(decoding: try encoder.encode(payload), as: UTF8.self) }
            incoming.insert(record)
        }
        for value in archive.attemptReflections { incoming.insert(makeReflection(value)) }
        for value in archive.documents { incoming.insert(makeDocument(value)) }
        for value in archive.sourceChunks {
            let record = makeChunk(value); record.createdAt = date; incoming.insert(record)
        }
        for value in archive.aiGenerations {
            guard value.createdAt.timeIntervalSince1970.isFinite,
                  value.payloadExpiresAt.timeIntervalSince1970.isFinite else {
                throw NFDataArchiveRestoreError.invalidArchive("generated-set date cannot be materialized")
            }
            let record = try makeGeneration(value, locale: locale)
            if !record.resultPayload.isEmpty {
                let result = try JSONDecoder().decode(NFAuthoringResult.self, from: record.resultPayload)
                let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
                record.resultPayload = try encoder.encode(result)
            }
            incoming.insert(record)
        }
        for value in archive.sessionCheckpoints { incoming.insert(makeCheckpoint(value)) }
        for value in archive.dailyPlans { incoming.insert(try makeDailyPlan(value)) }
        for value in archive.inputCalibrations { incoming.insert(makeCalibration(value)) }
        for value in archive.progressAnnotations { incoming.insert(makeAnnotation(value)) }
        for value in archive.quarantinedReports { incoming.insert(makeReport(value)) }
        if let value = archive.weeklyTransferState {
            let record = WeeklyTransferStateRecord(state: value); record.modifiedAt = date; incoming.insert(record)
        }
        if let value = archive.reassessmentState {
            let record = ReassessmentStateRecord(state: value); record.modifiedAt = date; incoming.insert(record)
        }
        // Capture typed unsaved objects before a backend can truncate NUL text.
        // This helper is restricted to isolated compilation, never live capture.
        let incomingRaw = try NFDataArchiveRawCapture.captureUnsavedForCompilation(context: incoming)
        try NFDataArchiveRawCapture.validateMaterialization(incomingRaw)
        let categoryByModel: [String: String] = [
            "UserProfileRecord": "profile", "AttemptRecord": "attempts", "AttemptReflectionRecord": "reflections",
            "SourceDocumentRecord": "documents", "SourceChunkRecord": "sourceChunks", "AIGenerationRecord": "generatedSets",
            "SessionCheckpointRecord": "checkpoints", "DailyPlanRecord": "dailyPlans", "InputCalibrationRecord": "calibrations",
            "ProgressAnnotationRecord": "annotations", "WeeklyTransferStateRecord": "weeklyMission",
            "ReassessmentStateRecord": "reassessment", "ItemReportRecord": "reports"
        ]
        var result = before
        var counts: [String: Int] = [:]
        for index in result.tables.indices {
            let prior = before.tables[index]
            guard let input = incomingRaw.tables.first(where: { $0.model == prior.model }),
                  let category = categoryByModel[prior.model] else { throw NFRestoreJournalError.unsupportedVersion }
            let singleton = ["UserProfileRecord", "WeeklyTransferStateRecord", "ReassessmentStateRecord"].contains(prior.model)
            let secondary = prior.model == "AttemptReflectionRecord" ? "attemptID"
                : (prior.model == "SessionCheckpointRecord" ? "sessionID" : nil)
            func matches(_ a: NFDataArchiveRawRow, _ b: NFDataArchiveRawRow) -> Bool {
                singleton || a.columns["id"] == b.columns["id"]
                    || secondary.map { a.columns[$0] == b.columns[$0] } == true
            }
            let conflicts = input.rows.filter { row in prior.rows.contains { matches($0, row) } }
            if policy == .abortOnConflict, !conflicts.isEmpty {
                throw NFDataArchiveRestoreError.conflictsRequireDecision(conflicts.count)
            }
            let admitted = policy == .keepExisting ? input.rows.filter { row in !prior.rows.contains { matches($0, row) } } : input.rows
            let retained: [NFDataArchiveRawRow]
            switch policy {
            case .replaceAll: retained = []
            case .replaceMatching: retained = prior.rows.filter { row in !input.rows.contains { matches(row, $0) } }
            case .keepExisting, .abortOnConflict: retained = prior.rows
            }
            result.tables[index].rows = retained + admitted
            counts["restored.\(category)"] = admitted.count
            counts["skipped.\(category)"] = input.rows.count - admitted.count
        }
        try NFDataArchiveRawCapture.validateMaterialization(result)
        try NFDataArchiveRawCapture.verifyHydration(result)
        return .init(after: result, counts: counts)
    }
}

fileprivate extension NFDataArchiveRawCapture {
    static func captureUnsavedForCompilation(context: ModelContext) throws -> NFDataArchiveRawSnapshot {
        .init(tables: try adapters.map { try $0.capture(context).table })
    }
}

/// The caller keeps ordinary startup blocked and holds NFApplicationStoreLease.
/// These APIs consume an already authenticated accepted journal plan. They never
/// infer transaction authority from a standalone portable archive or phase label.
@MainActor
enum NFRestoreDomainApplier {
    static func reconcileAndStage(plan: NFRestoreJournalPlan, domain: NFDataArchiveRawDatabaseDomain,
                                  context: ModelContext) throws -> NFDataArchiveRawTransition.Disposition {
        try NFRestoreJournalCodec.validate(plan)
        try plan.validateSupportedRawContract()
        let current = try NFDataArchiveRawCapture.capture(context: context)
        for inspected in [NFDataArchiveRawDatabaseDomain.durable, .localOnly] {
            guard try domainDisposition(plan: plan, domain: inspected, current: current) != .conflict else {
                throw NFRestoreJournalError.recoveryConflict
            }
        }
        let before = try rebasingOtherDomain(plan.raw.before, from: current, selected: domain)
        let after = try rebasingOtherDomain(plan.raw.after, from: current, selected: domain)
        // Rebase only the other database, which may already have committed.
        // The selected database is a complete exact multiset: third states and
        // unrelated arrivals stop before any mutation, preserving those rows.
        return try NFDataArchiveRawCapture.stageAcceptedTransition(.init(before: before, after: after), context: context)
    }

    @discardableResult
    static func applyDatabaseDomain(plan: NFRestoreJournalPlan, domain: NFDataArchiveRawDatabaseDomain,
        container: ModelContainer, save: @MainActor (ModelContext) throws -> Void = { try $0.save() }) throws
        -> NFDataArchiveRawTransition.Disposition {
        let context = ModelContext(container); context.autosaveEnabled = false
        let disposition = try reconcileAndStage(plan: plan, domain: domain, context: context)
        guard disposition == .needsApplication else { return disposition }
        do { try save(context) }
        catch {
            // Only unsaved changes in this context are discarded. A completed
            // store save followed by an error remains in the accepted journal.
            if context.hasChanges { context.rollback() }
            throw error
        }
        let fresh = ModelContext(container); fresh.autosaveEnabled = false
        guard try domainDisposition(plan: plan, domain: domain, current: NFDataArchiveRawCapture.capture(context: fresh)) == .alreadyApplied else {
            throw NFRestoreJournalError.recoveryConflict
        }
        return .needsApplication
    }

    static func domainDisposition(plan: NFRestoreJournalPlan, domain: NFDataArchiveRawDatabaseDomain,
        current: NFDataArchiveRawSnapshot) throws -> NFDataArchiveRawTransition.Disposition {
        try NFRestoreJournalCodec.validate(plan); try plan.validateSupportedRawContract()
        try NFDataArchiveRawCapture.validate(current)
        let before = try rebasingOtherDomain(plan.raw.before, from: current, selected: domain)
        let after = try rebasingOtherDomain(plan.raw.after, from: current, selected: domain)
        return try NFDataArchiveRawTransition(before: before, after: after).disposition(current: current)
    }

    private static func rebasingOtherDomain(_ accepted: NFDataArchiveRawSnapshot,
        from current: NFDataArchiveRawSnapshot, selected: NFDataArchiveRawDatabaseDomain) throws -> NFDataArchiveRawSnapshot {
        try NFDataArchiveRawCapture.validate(current)
        var result = accepted
        for index in result.tables.indices where result.tables[index].domain != selected {
            guard let table = current.tables.first(where: { $0.model == result.tables[index].model }) else {
                throw NFRestoreJournalError.malformed
            }
            result.tables[index] = table
        }
        return result
    }
}

/// Side-file publication runs off the UI actor and retains the same application
/// lease for its lifetime. Existing side files and validated AI artifact names
/// are supported; a supplied source-file/path operation remains unavailable.
actor NFRestoreFileApplier {
    enum Boundary: Equatable, Sendable { case beforeTemporaryWrite, afterTemporaryWrite, beforePublish, afterPublish, afterReadback }
    typealias Fault = @Sendable (Boundary) throws -> Void
    private let roots: [NFRestoreJournalFileOperation.Domain: URL]
    private let lease: NFApplicationStoreLease
    private let maximumBytes: Int
    private let fault: Fault

    init(roots: [NFRestoreJournalFileOperation.Domain: URL], lease: NFApplicationStoreLease,
         maximumBytes: Int = NFLocalSessionRepository.maximumBytes, fault: @escaping Fault = { _ in }) {
        self.roots = roots; self.lease = lease; self.maximumBytes = maximumBytes; self.fault = fault
    }

    func captureFiles(operations: [NFRestoreJournalFileOperation]? = nil) throws -> [String: Data?] {
        var values: [String: Data?] = [:]
        for (domain, id, name) in [(NFRestoreJournalFileOperation.Domain.localLearning, "local-learning", "sessions-v1.json"),
                                  (.adaptiveHistory, "adaptive-history", "AdaptivePlanHistory-v1.json")] {
            guard let root = roots[domain] else { throw NFRestoreJournalError.unsafePath }
            let fd = try openRoot(root)
            defer { Darwin.close(fd) }
            values[id] = .some(try read(name, directory: fd))
        }
        if let operations {
            let expectedIDs = Set(operations.map(\.id))
            let artifacts = try captureAIArtifacts()
            for file in artifacts {
                let location = try NFAILearningArtifactArchive.location(for: file.relativePath)
                guard expectedIDs.contains(location.operationID) else { throw NFRestoreJournalError.recoveryConflict }
                values[location.operationID] = .some(file.bytes)
            }
            for operation in operations where operation.domain == .aiTutor || operation.domain == .aiGrading {
                if !values.keys.contains(operation.id) { values[operation.id] = .some(nil) }
            }
            values = values.filter { expectedIDs.contains($0.key) }
        }
        return values
    }

    func captureAIArtifacts() throws -> [NFAILearningArtifactFile] {
        var values: [NFAILearningArtifactFile] = []
        for (domain, folder) in [(NFRestoreJournalFileOperation.Domain.aiTutor, "Tutor"), (.aiGrading, "Grading")] {
            if let root = roots[domain] {
                values += try NFAILearningArtifactArchive.captureDirectory(root, folder: folder)
            }
        }
        try NFAILearningArtifactArchive.validate(values)
        return values.sorted { $0.relativePath < $1.relativePath }
    }

    @discardableResult
    func apply(_ operation: NFRestoreJournalFileOperation, transactionID: UUID) throws -> NFRestoreJournalReconciliation.Disposition {
        let expected: (String, String)
        switch operation.domain {
        case .localLearning: expected = ("local-learning", "sessions-v1.json")
        case .adaptiveHistory: expected = ("adaptive-history", "AdaptivePlanHistory-v1.json")
        case .sourceFile: throw NFRestoreJournalError.unsupportedVersion
        case .aiTutor, .aiGrading:
            let folder = operation.domain == .aiTutor ? "Tutor" : "Grading"
            let path = folder + "/" + operation.relativePath
            let location = try NFAILearningArtifactArchive.location(for: path)
            expected = (location.operationID, location.filename)
            for bytes in [operation.before, operation.after].compactMap({ $0 }) {
                try NFAILearningArtifactArchive.validate(.init(relativePath: path, bytes: bytes))
            }
        }
        guard operation.id == expected.0, operation.relativePath == expected.1,
              let root = roots[operation.domain] else { throw NFRestoreJournalError.unsafePath }
        guard maximumBytes > 0, [operation.before, operation.after].compactMap({ $0 }).allSatisfy({ $0.count <= maximumBytes }) else {
            throw NFRestoreJournalError.oversized
        }
        let directory = try openRoot(root)
        defer { Darwin.close(directory) }
        let temporary = ".restore-domain-\(transactionID.uuidString.lowercased())-\(operation.id).tmp"
        let current = try read(operation.relativePath, directory: directory)
        if current == operation.after {
            try removeKnownTemporary(temporary, expected: operation.after, directory: directory)
            return .alreadyApplied
        }
        guard current == operation.before else { throw NFRestoreJournalError.recoveryConflict }
        try removeKnownTemporary(temporary, expected: operation.after, directory: directory)
        if let after = operation.after {
            try fault(.beforeTemporaryWrite)
            let fd = openat(directory, temporary, O_CREAT | O_EXCL | O_WRONLY | O_NOFOLLOW | O_NONBLOCK, 0o600)
            guard fd >= 0 else { throw NFRestoreJournalError.ioFailure }
            defer { Darwin.close(fd); _ = unlinkat(directory, temporary, 0) }
            #if os(iOS)
            try FileManager.default.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
                ofItemAtPath: root.appendingPathComponent(temporary).path)
            #endif
            try after.withUnsafeBytes { bytes in
                var offset = 0
                while offset < bytes.count {
                    guard let address = bytes.baseAddress else { throw NFRestoreJournalError.ioFailure }
                    let count = Darwin.write(fd, address.advanced(by: offset), bytes.count - offset)
                    if count < 0 { if errno == EINTR { continue }; throw NFRestoreJournalError.ioFailure }
                    guard count > 0 else { throw NFRestoreJournalError.ioFailure }
                    offset += count
                }
            }
            guard fsync(fd) == 0 else { throw NFRestoreJournalError.ioFailure }
            try fault(.afterTemporaryWrite)
            guard try read(operation.relativePath, directory: directory) == operation.before else { throw NFRestoreJournalError.recoveryConflict }
            try fault(.beforePublish)
            guard renameat(directory, temporary, directory, operation.relativePath) == 0 else { throw NFRestoreJournalError.ioFailure }
        } else {
            try fault(.beforePublish)
            guard try read(operation.relativePath, directory: directory) == operation.before else { throw NFRestoreJournalError.recoveryConflict }
            guard unlinkat(directory, operation.relativePath, 0) == 0 else { throw NFRestoreJournalError.ioFailure }
        }
        guard fsync(directory) == 0 else { throw NFRestoreJournalError.ioFailure }
        try fault(.afterPublish)
        guard try read(operation.relativePath, directory: directory) == operation.after else { throw NFRestoreJournalError.recoveryConflict }
        try fault(.afterReadback)
        return .needsApplication
    }

    private func openRoot(_ root: URL) throws -> Int32 {
        guard root.isFileURL else { throw NFRestoreJournalError.unsafePath }
        // Caller creates/approves these private parent roots during cold-start
        // staging. This primitive never recursively creates an arbitrary path.
        let fd = Darwin.open(root.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_NONBLOCK)
        guard fd >= 0 else { throw NFRestoreJournalError.unsafePath }
        return fd
    }

    private func read(_ name: String, directory: Int32) throws -> Data? {
        guard maximumBytes > 0 else { throw NFRestoreJournalError.oversized }
        let fd = openat(directory, name, O_RDONLY | O_NOFOLLOW | O_NONBLOCK)
        if fd < 0 {
            if errno == ENOENT { return nil }
            throw NFRestoreJournalError.unsafePath
        }
        defer { Darwin.close(fd) }
        var metadata = stat()
        guard fstat(fd, &metadata) == 0, metadata.st_mode & S_IFMT == S_IFREG, metadata.st_nlink == 1 else {
            throw NFRestoreJournalError.unsafePath
        }
        guard metadata.st_size >= 0, metadata.st_size <= maximumBytes else { throw NFRestoreJournalError.oversized }
        var bytes = Data(), buffer = [UInt8](repeating: 0, count: min(65_536, maximumBytes))
        while true {
            let count = buffer.withUnsafeMutableBytes { Darwin.read(fd, $0.baseAddress, $0.count) }
            if count < 0 { if errno == EINTR { continue }; throw NFRestoreJournalError.ioFailure }
            if count == 0 { return bytes }
            guard count <= maximumBytes - bytes.count else { throw NFRestoreJournalError.oversized }
            bytes.append(contentsOf: buffer.prefix(count))
        }
    }

    private func removeKnownTemporary(_ name: String, expected: Data?, directory: Int32) throws {
        guard let bytes = try read(name, directory: directory) else { return }
        // A partial prior write is also private recovery material. It can only
        // be removed when it is an exact prefix of this accepted postimage.
        guard let expected, expected.starts(with: bytes) else { throw NFRestoreJournalError.recoveryConflict }
        guard unlinkat(directory, name, 0) == 0, fsync(directory) == 0 else { throw NFRestoreJournalError.ioFailure }
    }
}

private extension NFRestorePlanCompiler {
    /// Every v1 Archive field is inventoried in the accompanying policy table.
    /// Device authority is not a portable content collection. Its consumption
    /// survives every policy; removed/replaced runs lose writer receipts.
    static func applyingLocalPolicy(existing: NFLocalSessionRepository.Archive,
        incoming original: NFLocalSessionRepository.Archive?, policy: NFDataArchiveRestorePolicy,
        priorRaw: NFDataArchiveRawSnapshot, incomingCore: NFDataExportService.Archive)
        throws -> (existing: NFLocalSessionRepository.Archive, incoming: NFLocalSessionRepository.Archive, counts: [String: Int]) {
        var base = existing, incoming = original ?? .init()
        var counts: [String: Int] = [:]
        let priorRows: [NFDataArchiveRawRow] = priorRaw.tables.first(where: { $0.model == "AttemptRecord" })?.rows ?? []
        let priorAttempts = Set<UUID>(try priorRows.map { row -> UUID in
            guard let value = row.columns["id"] else { throw NFRestoreJournalError.malformed }
            return try UUID.fromArchiveRawValue(value)
        })
        let coreReplaced: Set<UUID> = policy == .replaceAll ? priorAttempts
            : (policy == .replaceMatching ? priorAttempts.intersection(Set(incomingCore.attempts.map(\.id))) : [])
        let coreKept: Set<UUID> = policy == .keepExisting ? priorAttempts : []

        func partition<Value, ID: Hashable>(_ old: [Value], _ proposed: [Value],
            id: (Value) -> ID, category: String) throws -> ([Value], [Value]) {
            let oldIDs = Set(old.map(id)), proposedIDs = Set(proposed.map(id))
            guard oldIDs.count == old.count, proposedIDs.count == proposed.count else { throw NFRestoreJournalError.malformed }
            let conflicts = oldIDs.intersection(proposedIDs)
            if policy == .abortOnConflict, !conflicts.isEmpty { throw NFDataArchiveRestoreError.conflictsRequireDecision(conflicts.count) }
            let admitted = policy == .keepExisting ? proposed.filter { !oldIDs.contains(id($0)) } : proposed
            let retained = policy == .replaceAll ? [] : (policy == .replaceMatching ? old.filter { !proposedIDs.contains(id($0)) } : old)
            counts["restored.local.\(category)"] = admitted.count
            counts["skipped.local.\(category)"] = proposed.count - admitted.count
            return (retained, admitted)
        }
        let proposedSnapshotCount = incoming.snapshots.count
        let proposedCorrectionCount = incoming.contentCorrections?.count ?? 0
        let proposedConflictCount = incoming.attemptConflicts?.count ?? 0
        // A new imported snapshot must not attach an alternate evaluator to a
        // kept original core attempt solely because the UUID is the same.
        incoming.snapshots.removeAll { coreKept.contains($0.attemptID) }
        incoming.contentCorrections?.removeAll { UUID(uuidString: $0.originalAttemptID).map { coreKept.contains($0) } == true }
        incoming.attemptConflicts?.removeAll { coreKept.contains($0.attemptID) }
        base.snapshots.removeAll { coreReplaced.contains($0.attemptID) }
        base.contentCorrections?.removeAll { UUID(uuidString: $0.originalAttemptID).map { coreReplaced.contains($0) } == true }
        base.attemptConflicts?.removeAll { coreReplaced.contains($0.attemptID) }
        base.evidenceDispositions?.removeAll { UUID(uuidString: $0.attemptID).map { coreReplaced.contains($0) } == true }
        base.unavailableHistorySnapshots?.removeAll { coreReplaced.contains($0.attemptID) && $0.reason != .protectedContent }
        for id in coreReplaced { base.activeContentCorrectionIDs?.removeValue(forKey: id.uuidString) }
        let linkedRemoved = Set(base.sessions.filter { run in
            coreReplaced.contains(run.checkpoint.attemptID)
                || run.checkpoint.committedAttemptID.map { coreReplaced.contains($0) } == true
        }.map(\.id))
        base.sessions.removeAll { linkedRemoved.contains($0.id) }

        (base.sessions, incoming.sessions) = try partition(base.sessions, incoming.sessions, id: { $0.id }, category: "sessions")
        (base.snapshots, incoming.snapshots) = try partition(base.snapshots, incoming.snapshots, id: { $0.attemptID }, category: "snapshots")
        let sets = try partition(base.savedSets ?? [], incoming.savedSets ?? [], id: { $0.id }, category: "savedSets")
        base.savedSets = sets.0; incoming.savedSets = sets.1
        let drafts = try partition(base.privateStudyRuns ?? [], incoming.privateStudyRuns ?? [], id: { $0.id }, category: "privateStudyRuns")
        base.privateStudyRuns = drafts.0; incoming.privateStudyRuns = drafts.1
        let dispositions = try partition(base.evidenceDispositions ?? [], incoming.evidenceDispositions ?? [], id: { $0.id }, category: "evidenceDispositions")
        base.evidenceDispositions = dispositions.0; incoming.evidenceDispositions = dispositions.1
        let corrections = try partition(base.contentCorrections ?? [], incoming.contentCorrections ?? [], id: { $0.id }, category: "contentCorrections")
        base.contentCorrections = corrections.0; incoming.contentCorrections = corrections.1
        let conflicts = try partition(base.attemptConflicts ?? [], incoming.attemptConflicts ?? [], id: { $0.id }, category: "attemptConflicts")
        base.attemptConflicts = conflicts.0; incoming.attemptConflicts = conflicts.1
        let unavailable = try partition(base.unavailableHistorySnapshots ?? [], incoming.unavailableHistorySnapshots ?? [], id: { $0.attemptID }, category: "unavailableHistorySnapshots")
        base.unavailableHistorySnapshots = unavailable.0; incoming.unavailableHistorySnapshots = unavailable.1

        // Privacy restrictions remain sticky even when a replaced identity is
        // imported as ordinary. This stores no evaluator and grants no writer.
        base.withheldProtectedConflictAttemptIDs = Array(Set(existing.withheldProtectedConflictAttemptIDs ?? [])
            .union((existing.unavailableHistorySnapshots ?? []).filter { $0.reason == .protectedContent }.map(\.attemptID))).sorted { $0.uuidString < $1.uuidString }
        counts["skipped.local.snapshots", default: 0] += proposedSnapshotCount - (original?.snapshots.filter { !coreKept.contains($0.attemptID) }.count ?? 0)
        counts["skipped.local.contentCorrections", default: 0] += proposedCorrectionCount - (original?.contentCorrections?.filter { UUID(uuidString: $0.originalAttemptID).map { coreKept.contains($0) } != true }.count ?? 0)
        counts["skipped.local.attemptConflicts", default: 0] += proposedConflictCount - (original?.attemptConflicts?.filter { !coreKept.contains($0.attemptID) }.count ?? 0)
        let oldRunIDs = Set(base.sessions.map(\.id)), newRunIDs = Set(incoming.sessions.map(\.id))
        let removed = Set(existing.sessions.map(\.id)).subtracting(oldRunIDs)
        let removedCommands = Set((base.fixedLaunchReceipts ?? [:]).filter { removed.contains($0.value.sessionID) }.map(\.key))
        base.deletedFixedLaunchCommandIDs = (base.deletedFixedLaunchCommandIDs ?? []).union(removedCommands)
        base.deletedAdaptiveRunIDs = (base.deletedAdaptiveRunIDs ?? []).union(removed)
        base.fixedLaunchReceipts = base.fixedLaunchReceipts?.filter { oldRunIDs.contains($0.value.sessionID) }
        base.adaptiveItemReceipts = base.adaptiveItemReceipts?.filter { oldRunIDs.contains($0.value.sessionID) }
        base.editorialOverrideCommands = base.editorialOverrideCommands?.filter { oldRunIDs.contains($0.value.sessionID) }
        base.retiredOrdinaryDrafts = base.retiredOrdinaryDrafts?.filter { oldRunIDs.contains($0.value.sessionID) }
        incoming.retiredOrdinaryDrafts = incoming.retiredOrdinaryDrafts?.filter { newRunIDs.contains($0.value.sessionID) }
        if let ledger = base.selectionLedger { base.selectionLedger = pruning(ledger, retainingRuns: Set(oldRunIDs.map(\.uuidString))) }
        if let ledger = incoming.selectionLedger { incoming.selectionLedger = pruning(ledger, retainingRuns: Set(newRunIDs.map(\.uuidString))) }

        // Union observed consumption only when its meaning/authority is exactly
        // the same. A different catalog or legacy prefix is a genuine ambiguity.
        if var proposed = incoming.selectionLedger, var current = base.selectionLedger {
            for (key, value) in proposed.scopes {
                if var retained = current.scopes[key] {
                    guard retained.catalogFingerprint == value.catalogFingerprint,
                          retained.authorityID == value.authorityID,
                          retained.legacyConsumption == value.legacyConsumption else { throw NFRestoreJournalError.recoveryConflict }
                    retained.consumedPositions.formUnion(value.consumedPositions)
                    retained.retainedPlanPositions.formUnion(value.retainedPlanPositions)
                    current.scopes[key] = retained; proposed.scopes[key] = retained
                }
            }
            base.selectionLedger = current; incoming.selectionLedger = proposed
        }
        let correctionIDs = Set((base.contentCorrections ?? []).map(\.id) + (incoming.contentCorrections ?? []).map(\.id))
        func memberships(_ value: [String: [String]]?) -> [String: [String]] {
            (value ?? [:]).mapValues { $0.filter(correctionIDs.contains) }.filter { !$0.value.isEmpty }
        }
        base.activeContentCorrectionIDs = policy == .replaceAll ? [:] : memberships(base.activeContentCorrectionIDs)
        incoming.activeContentCorrectionIDs = memberships(incoming.activeContentCorrectionIDs)
        if policy == .replaceMatching {
            for key in Array((incoming.activeContentCorrectionIDs ?? [:]).keys) {
                base.activeContentCorrectionIDs?.removeValue(forKey: key)
            }
        }
        if policy == .replaceAll { base.unavailablePrivateRunIDs = [] }
        base.dismissedCorrectionIDs = (base.dismissedCorrectionIDs ?? []).intersection(correctionIDs)
        // Do not import installation-specific launch authority or tombstones.
        incoming.offlineRotationLedger = nil; incoming.rotationMigration = nil
        incoming.fixedLaunchReceipts = nil; incoming.adaptiveItemReceipts = nil; incoming.editorialOverrideCommands = nil
        incoming.deletedFixedLaunchCommandIDs = nil; incoming.deletedAdaptiveRunIDs = nil
        incoming.dismissedCorrectionIDs = nil; incoming.transactionRevision = nil
        for index in incoming.sessions.indices {
            incoming.sessions[index].status = .migrationRecovery
            incoming.sessions[index].checkpoint.protectedCommitReceipt = nil
            incoming.sessions[index].request.localCheckpoint = nil
        }
        return (base, incoming, counts)
    }

    static func pruning(_ original: NFSelectionReservationLedger, retainingRuns: Set<String>) -> NFSelectionReservationLedger {
        var ledger = original
        ledger.runs = ledger.runs.filter { retainingRuns.contains($0.key) }
        ledger.slots = ledger.slots.filter { retainingRuns.contains($0.value.runID) }
        ledger.decisions = ledger.decisions.filter { retainingRuns.contains($0.value.command.runID) }
        ledger.exposures = ledger.exposures.filter { retainingRuns.contains($0.value.runID) }
        ledger.outcomes = ledger.outcomes.filter { retainingRuns.contains($0.value.runID) }
        let retained = ledger.slots.values.compactMap { NFSelectionReservationPolicy.snapshot(for: $0, in: original) }
        ledger.snapshots = ledger.snapshots.filter { retained.contains($0.value) }
        ledger.legacyReservationOwners = ledger.legacyReservationOwners.filter { retainingRuns.contains($0.value) }
        ledger.legacyPlans = ledger.legacyPlans.filter { ledger.legacyReservationOwners[$0.key] != nil }
        // scopes deliberately retain anonymous consumed positions.
        return ledger
    }
}

// MARK: - Explicit-deletion cleanup of completed restore artifacts

/// The caller holds the application lease and seals every request producer
/// before this preflight. Completed backups contain an entire raw census, so an
/// explicit private-data deletion retires all completed backups for this
/// installation owner, including its prior account namespaces. Primary records
/// are untouched. Unknown artifacts and unfinished recovery remain blocked.
extension NFDataArchiveRestoreJournal {
    func preflightExplicitDeletionCleanup(installationOwnerID: UUID) async throws -> [NFRestoreJournalInspection] {
        let entries = try withLock { try inspections(namespace: nil, owner: nil) }
        for entry in entries {
            guard !entry.isStaging, let descriptor = entry.descriptor, let progress = entry.progress else {
                throw NFRestoreJournalError.recoveryConflict
            }
            guard descriptor.installationOwnerID == installationOwnerID else { throw NFRestoreJournalError.wrongOwner }
            guard [.verifiedComplete, .invalidated, .cleaned].contains(progress.phase) else {
                throw NFRestoreJournalError.recoveryConflict
            }
            try withLock {
                let current = try metadata(directory(entry.transactionID), transactionID: entry.transactionID,
                    namespace: descriptor.namespace, owner: installationOwnerID)
                guard current.0 == descriptor, current.1 == progress else { throw NFRestoreJournalError.staleRevision }
                try validateExplicitDeletionFiles(directory(entry.transactionID), phase: progress.phase)
            }
            if progress.phase == .verifiedComplete {
                // Validate one bounded payload at a time, retaining only small
                // authenticated metadata through the rest of the preflight.
                let loaded = try await load(transactionID: entry.transactionID,
                    namespace: descriptor.namespace, installationOwnerID: installationOwnerID)
                guard loaded.descriptor == descriptor, loaded.progress == progress else { throw NFRestoreJournalError.staleRevision }
            }
        }
        return entries
    }

    /// Called only after every artifact and request has passed preflight. Each
    /// plan loses authority durably before its bytes are removed. Partial cleanup
    /// is retryable from invalidated metadata even when plan.json is already gone.
    func finishExplicitDeletionCleanup(installationOwnerID: UUID,
        expected: [NFRestoreJournalInspection], retireVerifiedCompletions: Bool = true) throws {
        try withLock {
            guard try inspections(namespace: nil, owner: nil) == expected else { throw NFRestoreJournalError.staleRevision }
            for entry in expected {
                guard !entry.isStaging, let descriptor = entry.descriptor, let progress = entry.progress,
                      descriptor.installationOwnerID == installationOwnerID,
                      [.verifiedComplete, .invalidated, .cleaned].contains(progress.phase) else {
                    throw NFRestoreJournalError.recoveryConflict
                }
                try validateExplicitDeletionFiles(directory(entry.transactionID), phase: progress.phase)
            }
        }
        for entry in expected {
            guard let descriptor = entry.descriptor, let progress = entry.progress else { throw NFRestoreJournalError.malformed }
            if progress.phase == .verifiedComplete, !retireVerifiedCompletions { continue }
            if progress.phase == .verifiedComplete {
                _ = try invalidate(transactionID: entry.transactionID, namespace: descriptor.namespace,
                    installationOwnerID: installationOwnerID, expectedRevision: progress.revision)
            }
            try withLock {
                let current = try metadata(directory(entry.transactionID), transactionID: entry.transactionID,
                    namespace: descriptor.namespace, owner: installationOwnerID)
                guard current.0 == descriptor, [.invalidated, .cleaned].contains(current.1.phase) else {
                    throw NFRestoreJournalError.staleRevision
                }
                try validateExplicitDeletionFiles(directory(entry.transactionID), phase: current.1.phase)
            }
            try removeInvalidated(transactionID: entry.transactionID, namespace: descriptor.namespace,
                installationOwnerID: installationOwnerID)
        }
        try withLock {
            let final = try inspections(namespace: nil, owner: nil)
            guard final.map(\.transactionID) == expected.map(\.transactionID) else { throw NFRestoreJournalError.staleRevision }
            for entry in final {
                guard let descriptor = entry.descriptor, descriptor.installationOwnerID == installationOwnerID else {
                    throw NFRestoreJournalError.wrongOwner
                }
                if !retireVerifiedCompletions, let original = expected.first(where: { $0.transactionID == entry.transactionID }),
                   original.progress?.phase == .verifiedComplete {
                    guard original == entry else { throw NFRestoreJournalError.staleRevision }
                    try validateExplicitDeletionFiles(directory(entry.transactionID), phase: .verifiedComplete)
                } else {
                    guard entry.progress?.phase == .cleaned else { throw NFRestoreJournalError.recoveryConflict }
                    try validateExplicitDeletionFiles(directory(entry.transactionID), phase: .cleaned)
                }
            }
        }
    }

    private func validateExplicitDeletionFiles(_ folder: URL, phase: NFRestoreJournalPhase) throws {
        let entries = try directoryEntries(folder, maximum: 32)
        let names = Set(entries.map(\.lastPathComponent))
        guard names.isSuperset(of: ["accepted.json", "progress.json"]) else { throw NFRestoreJournalError.malformed }
        if phase == .cleaned {
            guard names == ["accepted.json", "progress.json"] else { throw NFRestoreJournalError.malformed }
        }
        for file in entries {
            let name = file.lastPathComponent
            if ["accepted.json", "progress.json"].contains(name) {
                _ = try read(file, maximumBytes: Self.maximumMetadataBytes)
            } else if name == "plan.json" {
                _ = try read(file, maximumBytes: maximumPlanBytes)
            } else {
                guard name.hasPrefix(".write-"), let id = UUID(uuidString: String(name.dropFirst(7))),
                      name == ".write-" + id.uuidString.lowercased() else { throw NFRestoreJournalError.malformed }
                // Only this journal's reserved atomic-write filenames are
                // disposable. No unknown name, directory, symlink, or FIFO is.
                _ = try read(file, maximumBytes: maximumPlanBytes)
            }
        }
        if phase == .verifiedComplete, !names.contains("plan.json") { throw NFRestoreJournalError.ioFailure }
    }
}

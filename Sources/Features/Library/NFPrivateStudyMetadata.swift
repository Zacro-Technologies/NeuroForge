import Foundation

/// Personal organization is separate from immutable answers and never participates
/// in proficiency or CloudKit. The opaque local archive also carries it in backups.
struct NFPrivateStudyMetadata: Codable, Equatable, Sendable {
    static let recordID = UUID(uuidString: "78A5D4CA-8C43-44E1-9D9A-4D7C6BF54295")!
    var schemaVersion = 1
    var annotations: [NFStudyAnnotation] = []
    var collections: [NFStudyCollection] = []
    var favoriteActivities: Set<String> = []
    var recentActivityIDs: [String] = []
    var reviewDeferrals: [NFReviewDeferral]?

    var isSupported: Bool {
        schemaVersion == 1 && Set(annotations.map(\.id)).count == annotations.count
            && annotations.allSatisfy { $0.hasValidReflectionHistory }
            && NFReviewDeferralPolicy.supports(reviewDeferrals ?? [])
    }
}

struct NFStudyAnnotation: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    var note = ""
    var bookmarked = false
    var updatedAt = Date()
    var reflectionRevisions: [NFStudyReflectionRevision]?

    var hasValidReflectionHistory: Bool {
        let revisions = reflectionRevisions ?? []
        guard Set(revisions.map(\.id)).count == revisions.count else { return false }
        for (index, revision) in revisions.enumerated() {
            guard revision.schemaVersion == 1, revision.attemptID == id,
                  revision.revision == index + 1,
                  revision.predecessorID == (index == 0 ? nil : revisions[index - 1].id),
                  revision.originalReflectionID == revisions.first?.originalReflectionID,
                  revision.note.count <= AttemptReflectionRecord.maximumNoteCharacters,
                  revision.selectedErrorCodeRaw == nil || revision.selectedErrorCodeRaw.flatMap(NFErrorReflectionCode.init(rawValue:)) != nil
            else { return false }
        }
        return true
    }
}

/// Later interpretations are local supplements. The first reflection and scored
/// attempt remain immutable, including when the learner withdraws a diagnosis.
struct NFStudyReflectionRevision: Codable, Equatable, Identifiable, Sendable {
    var schemaVersion = 1
    let id: UUID
    let attemptID: UUID
    let originalReflectionID: UUID
    let revision: Int
    let predecessorID: UUID?
    let selectedErrorCodeRaw: String?
    let note: String
    let createdAt: Date
}

struct NFStudyCollection: Codable, Equatable, Identifiable, Sendable {
    var id = UUID()
    var title: String
    var description = ""
    var sourceIDs: Set<UUID> = []
    var savedSetIDs: Set<UUID> = []
}

extension AppStore {
    var privateStudyMetadataUnavailableReason: String? {
        _ = privateStudyMetadata
        if cachedStudyMetadataIsUnavailable {
            return NFAppLocalization.localizedCatalogValue("This saved work needs a compatible version of NeuroForge. Your original answers remain saved.", locale: NFAppLocalization.preferredLocale)
        }
        return nil
    }

    var privateStudyMetadata: NFPrivateStudyMetadata {
        _ = localSessionRevision
        let revision = localSessions.archive.transactionRevision
        if cachedStudyMetadataRevision == revision, let cachedStudyMetadata { return cachedStudyMetadata }
        let metadata: NFPrivateStudyMetadata
        let record = localSessions.archive.privateStudyRuns?.first(where: { $0.id == NFPrivateStudyMetadata.recordID })
        if let record,
           let decoded = try? JSONDecoder().decode(NFPrivateStudyMetadata.self, from: record.payload), decoded.isSupported {
            metadata = decoded
            cachedStudyMetadataIsUnavailable = false
        } else {
            metadata = NFPrivateStudyMetadata()
            cachedStudyMetadataIsUnavailable = record != nil
        }
        cachedStudyMetadata = metadata
        cachedStudyMetadataRevision = revision
        return metadata
    }

    func savePrivateStudyMetadata(_ metadata: NFPrivateStudyMetadata) throws {
        if let existing = localSessions.archive.privateStudyRuns?.first(where: { $0.id == NFPrivateStudyMetadata.recordID }) {
            guard let previous = try? JSONDecoder().decode(NFPrivateStudyMetadata.self, from: existing.payload), previous.isSupported else {
                throw NFLocalSessionRepository.RepositoryError.unsupportedVersion
            }
            for annotation in previous.annotations where !(annotation.reflectionRevisions ?? []).isEmpty {
                let original = annotation.reflectionRevisions ?? []
                let revised = metadata.annotations.first { $0.id == annotation.id }?.reflectionRevisions ?? []
                guard revised.count >= original.count, Array(revised.prefix(original.count)) == original else {
                    throw NFLocalSessionRepository.RepositoryError.conflictingAttempt
                }
            }
        }
        guard metadata.isSupported else { throw NFLocalSessionRepository.RepositoryError.unsupportedVersion }
        try localSessions.savePrivateStudyRun(
            id: NFPrivateStudyMetadata.recordID,
            generationID: NFPrivateStudyMetadata.recordID,
            payload: JSONEncoder().encode(metadata)
        )
        localSessionRevision += 1
    }

    func saveStudyAnnotation(_ annotation: NFStudyAnnotation) throws {
        var metadata = privateStudyMetadata
        metadata.annotations.removeAll { $0.id == annotation.id }
        if !annotation.note.isEmpty || annotation.bookmarked || !(annotation.reflectionRevisions ?? []).isEmpty {
            metadata.annotations.append(annotation)
        }
        try savePrivateStudyMetadata(metadata)
    }

    func saveStudyCollection(_ collection: NFStudyCollection) throws {
        var metadata = privateStudyMetadata
        metadata.collections.removeAll { $0.id == collection.id }
        metadata.collections.append(collection)
        try savePrivateStudyMetadata(metadata)
    }
}

enum NFReviewDeferralError: Error, Equatable, LocalizedError {
    case unavailableMetadata, noDueEntries, acceptedReviewInProgress, invalidBoundary

    var errorDescription: String? {
        let key: String = switch self {
        case .unavailableMetadata: "Your saved review preferences are unavailable. Regular reminders remain active, and your original saved data is unchanged."
        case .noDueEntries: "These reviews are no longer ready. The queue has been refreshed."
        case .acceptedReviewInProgress: "Continue or end the saved review before deferring its remaining questions."
        case .invalidBoundary: "The next review day could not be verified. Your review schedule is unchanged."
        }
        return NFAppLocalization.localizedCatalogValue(key, locale: NFAppLocalization.preferredLocale)
    }
}

extension AppStore {
    func reviewDueEntries(at date: Date, calendar: Calendar) -> [NFReviewDueEntry] {
        let reports = itemReports.filter { $0.status == "quarantined" }
        let reportedItems = Set(reports.map(\.itemID))
        let reportedTemplates = Set(reports.map(\.templateID).filter { !$0.isEmpty })
        let records = Dictionary(attempts.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let origins = retentionReminderOrigins(at: date, calendar: calendar).filter { origin in
            guard !(profile?.excludeVisualSpatial == true && origin.state.lab == .spatial),
                  let record = records[origin.anchorAttemptID],
                  historyPresentation(for: .init(attempt: record)).source != .protectedAssessment,
                  !reportedItems.contains(record.itemID), !reportedTemplates.contains(record.templateID),
                  !reportedTemplates.contains(origin.state.id),
                  exerciseSnapshot(for: record.id).map({ !reportedTemplates.contains($0.templateID) }) ?? true else { return false }
            return true
        }
        return NFReviewDeferralPolicy.project(origins: origins,
            profileID: profileSnapshot.id, deferrals: privateStudyMetadata.reviewDeferrals ?? [], calendar: calendar)
    }

    var acceptedReviewMemoryItemIDs: Set<String> {
        let suspended = localSessions.archive.sessions.filter {
            $0.status == .suspended && $0.checkpoint.phase != .summary && $0.request.evidenceClass == .retention
        }.flatMap { $0.request.retentionItemIDs }
        let live = activeSessionRequest.flatMap { $0.evidenceClass == .retention ? $0.retentionItemIDs : nil } ?? []
        return Set(suspended).union(live)
    }

    func readyReviewEntries(at date: Date, calendar: Calendar) -> [NFReviewDueEntry] {
        let accepted = acceptedReviewMemoryItemIDs
        return reviewDueEntries(at: date, calendar: calendar).filter { $0.isDue(at: date) && !accepted.contains($0.id) }
    }

    func eligibleReviewTargets(_ targets: [NFRetentionReviewTarget], lab: TrainingLab,
                               at date: Date, calendar: Calendar) -> [NFRetentionReviewTarget] {
        let due = Dictionary(readyReviewEntries(at: date, calendar: calendar).map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first })
        var seen: Set<String> = []
        return targets.filter { target in
            guard let entry = due[target.memoryItemID], entry.origin.state.lab == lab,
                  target.templateFamily == entry.origin.state.templateFamily || target.templateFamily == entry.id,
                  seen.insert(target.memoryItemID).inserted else { return false }
            return true
        }
    }

    func nextReviewBatch(at date: Date, calendar: Calendar) -> [NFRetentionReviewTarget] {
        let ready = readyReviewEntries(at: date, calendar: calendar)
        guard let lab = ready.first?.origin.state.lab else { return [] }
        return NFRetentionScheduler.schedule(states: ready.filter { $0.origin.state.lab == lab }.map { $0.origin.state },
            at: date, maximumItems: 5, calendar: calendar).map(\.reviewTarget)
    }

    /// A disposable execution/presentation projection. The frozen plan record
    /// and any accepted checkpoint retain their exact original contract.
    func reviewExecutionPlan(_ plan: DailyPlan, at date: Date, calendar: Calendar) -> DailyPlan {
        let completed = completedPlanBlockIDs(planID: plan.id)
        let acceptedBlocks = Set(localSessions.archive.sessions.filter {
            $0.request.planID == plan.id && $0.status == .suspended
        }.compactMap { $0.request.planBlockID })
        let due = readyReviewEntries(at: date, calendar: calendar)
        let byID = Dictionary(due.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let blocks = plan.blocks.compactMap { block -> PlanBlock? in
            guard block.kindRaw == NFDailyPlanBlockKind.retentionReview.rawValue,
                  !completed.contains(block.id), !acceptedBlocks.contains(block.id),
                  activeSessionRequest?.planBlockID != block.id else { return block }
            let targets = retentionReviewTargets(forPlanID: plan.id, blockID: block.id,
                fallbackItemIDs: block.retentionItemIDs, fallbackSeed: plan.seed)
            var seen: Set<String> = []
            let retained = targets.filter { target in
                guard let entry = byID[target.memoryItemID], entry.origin.state.lab == block.lab,
                      target.templateFamily == entry.origin.state.templateFamily || target.templateFamily == entry.id,
                      seen.insert(target.memoryItemID).inserted else { return false }
                return true
            }
            guard !retained.isEmpty else { return nil }
            let originalCount = max(1, targets.count)
            let minutes = max(1, Int(ceil(Double(min(240, max(1, block.minutes))) * Double(retained.count) / Double(originalCount))))
            return PlanBlock(id: block.id, lab: block.lab, title: block.title, detail: block.detail,
                minutes: minutes, reasons: block.reasons, evidenceClass: block.evidenceClass, offlineReady: block.offlineReady,
                kindRaw: block.kindRaw, mechanicID: block.mechanicID, timed: block.timed,
                retentionItemIDs: retained.map(\.memoryItemID), targetSkillID: block.targetSkillID)
        }
        return DailyPlan(id: plan.id, localDayKey: plan.localDayKey, seed: plan.seed, policyVersion: plan.policyVersion,
            minutes: blocks.reduce(0) { $0 + $1.minutes }, blocks: blocks)
    }

    func reviewSemanticExclusions(memoryItemIDs: Set<String>) -> Set<String> {
        let ids = Set(attempts.filter { memoryItemIDs.contains($0.templateID) }.map(\.id))
        return Set(localSessions.archive.snapshots.filter {
            ids.contains($0.attemptID) && !$0.exercise.assessmentProtected
        }.map { NFQuestionFingerprint.fingerprint(for: $0.exercise) })
    }

    /// All consumers use this projection. A future preference returns normal
    /// reminders with an explicit recovery notice in the queue, never an empty
    /// schedule. Existing accepted session requests are not changed here.
    func reviewReminderStates(at date: Date, calendar: Calendar) -> [NFRetentionItemState] {
        reviewDueEntries(at: date, calendar: calendar).filter { !$0.isDeferred(at: date) }.map { $0.origin.state }
    }

    func nextEffectiveReviewDate(at date: Date, calendar: Calendar) -> Date? {
        reviewDueEntries(at: date, calendar: calendar).map(\.dueAt).min()
    }

    @discardableResult
    func deferReviews(memoryItemIDs: Set<String>, at date: Date,
                      calendar: Calendar) throws -> [NFReviewDeferral] {
        guard privateStudyMetadataUnavailableReason == nil else { throw NFReviewDeferralError.unavailableMetadata }
        guard !memoryItemIDs.isEmpty else { throw NFReviewDeferralError.noDueEntries }
        guard memoryItemIDs.isDisjoint(with: acceptedReviewMemoryItemIDs) else {
            throw NFReviewDeferralError.acceptedReviewInProgress
        }
        let entries = reviewDueEntries(at: date, calendar: calendar).filter { memoryItemIDs.contains($0.id) && $0.isDue(at: date) }
        guard Set(entries.map(\.id)) == memoryItemIDs else { throw NFReviewDeferralError.noDueEntries }
        let records = entries.compactMap {
            NFReviewDeferralPolicy.make(entry: $0, profileID: profileSnapshot.id, at: date,
                dayBoundaryHour: profileSnapshot.dayBoundaryHour, calendar: calendar)
        }
        guard records.count == entries.count else { throw NFReviewDeferralError.invalidBoundary }
        var metadata = privateStudyMetadata
        let replaced = Set(records.map(\.id))
        var retained = (metadata.reviewDeferrals ?? []).filter {
            !replaced.contains($0.id) && $0.deferredUntil > date
        }
        retained.append(contentsOf: records)
        metadata.reviewDeferrals = retained.sorted { $0.id < $1.id }
        // Existing repository publication compares transactionRevision and only
        // replaces memory after atomic rename. Errors leave metadata/attempts
        // and the observable localSessionRevision unchanged.
        try savePrivateStudyMetadata(metadata)
        return records
    }
}

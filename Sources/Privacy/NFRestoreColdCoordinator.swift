import Foundation
import SwiftData

@MainActor
enum NFRestoreColdCoordinator {
    struct Outcome {
        let container: ModelContainer?
        let completion: NFRestoreRequestReceipt?
    }
    enum Failure: Error {
        case fullRestartRequired, ownershipUnavailable, unresolvedArtifacts, renewedReviewRequired
    }

    static func namespace(for durableStoreURL: URL) -> String {
        NFRestoreJournalCodec.digest(Data(durableStoreURL.standardizedFileURL.path.utf8))
    }

    static func sideFileRoots(applicationSupportURL: URL, namespace: String) -> [NFRestoreJournalFileOperation.Domain: URL] {
        [.localLearning: applicationSupportURL.appending(path: "NeuroForge/LocalLearning/\(namespace)", directoryHint: .isDirectory),
         .adaptiveHistory: applicationSupportURL.appending(path: "NeuroForge", directoryHint: .isDirectory),
         .aiTutor: applicationSupportURL.appending(path: "NeuroForge/LocalLearning/\(namespace)/AILearning/Tutor", directoryHint: .isDirectory),
         .aiGrading: applicationSupportURL.appending(path: "NeuroForge/LocalLearning/\(namespace)/AILearning/Grading", directoryHint: .isDirectory)]
    }

    static func prepareSideFileRoots(applicationSupportURL: URL, namespace: String) throws -> [NFRestoreJournalFileOperation.Domain: URL] {
        guard NFRestoreJournalCodec.isDigest(namespace), applicationSupportURL.isFileURL else { throw NFRestoreJournalError.unsafePath }
        let base = Darwin.open(applicationSupportURL.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_NONBLOCK)
        guard base >= 0 else { throw NFRestoreJournalError.ioFailure }
        defer { Darwin.close(base) }
        var parent = base
        var opened: [Int32] = []
        defer { for fd in opened { Darwin.close(fd) } }
        for component in ["NeuroForge", "LocalLearning", namespace, "AILearning"] {
            guard mkdirat(parent, component, 0o700) == 0 || errno == EEXIST else { throw NFRestoreJournalError.ioFailure }
            let child = openat(parent, component, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_NONBLOCK)
            guard child >= 0 else { throw NFRestoreJournalError.unsafePath }
            opened.append(child)
            guard fchmod(child, 0o700) == 0, fsync(parent) == 0 else { throw NFRestoreJournalError.ioFailure }
            parent = child
        }
        for component in ["Tutor", "Grading"] {
            guard mkdirat(parent, component, 0o700) == 0 || errno == EEXIST else { throw NFRestoreJournalError.ioFailure }
            let child = openat(parent, component, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_NONBLOCK)
            guard child >= 0 else { throw NFRestoreJournalError.unsafePath }
            defer { Darwin.close(child) }
            guard fchmod(child, 0o700) == 0, fsync(parent) == 0 else { throw NFRestoreJournalError.ioFailure }
        }
        return sideFileRoots(applicationSupportURL: applicationSupportURL, namespace: namespace)
    }

    /// No AppStore, cached repository, background task, or CloudKit transport
    /// exists at this boundary. A container returned here remains local-only
    /// for the rest of this launch; ordinary startup reuses it after completion.
    static func recover(selection: NFPrivateCloudStoreSelection, applicationSupportURL: URL,
        lease: NFApplicationStoreLease, installationOwnerID: UUID?, hasOpenedRuntime: Bool,
        isCurrentLaunch: () -> Bool,
        makeContainer: (() throws -> ModelContainer)? = nil) async throws -> Outcome {
        let requests = NFRestoreRequestStore(root: NFRestoreRequestStore.root(applicationSupportURL: applicationSupportURL), lease: lease)
        let requestEntries = try await requests.inspectAll()
        let selectedNamespace = Self.namespace(for: selection.durableStoreURL)
        var pendingCompletion: NFRestoreRequestReceipt?
        for entry in requestEntries where !entry.completionAcknowledged {
            if let receipt = entry.receipt, receipt.resolution == .completed,
               entry.namespace == selectedNamespace, entry.installationOwnerID == installationOwnerID {
                pendingCompletion = receipt
                break
            }
        }
        let journalRoot = try NFRestoreJournalLocation.root(applicationSupportURL: applicationSupportURL)
        let journal = NFDataArchiveRestoreJournal(root: journalRoot)
        var metadata = stat()
        var journalEntries: [NFRestoreJournalInspection]
        if lstat(journalRoot.path, &metadata) == 0 { journalEntries = try await journal.inspectAllNamespaces() }
        else if errno == ENOENT { journalEntries = [] }
        else { throw Failure.unresolvedArtifacts }

        // Resume cancellation interrupted after its receipt but before removal
        // of an unaccepted candidate. The receipt always wins over staging.
        let cancelled = requestEntries.compactMap(\.receipt).filter { $0.resolution == .cancelled }
        for entry in journalEntries where entry.isStaging {
            guard let receipt = cancelled.first(where: { $0.transactionID == entry.transactionID }) else { continue }
            guard !hasOpenedRuntime, isCurrentLaunch(), receipt.installationOwnerID == installationOwnerID,
                  receipt.namespace == namespace(for: selection.durableStoreURL) else { throw Failure.ownershipUnavailable }
            try await journal.removeInvalidated(transactionID: entry.transactionID,
                namespace: receipt.namespace, installationOwnerID: receipt.installationOwnerID)
            journalEntries.removeAll { $0.transactionID == entry.transactionID }
        }

        let openRequests = requestEntries.filter { $0.receipt == nil }
        let openJournals = journalEntries.filter { $0.isStaging || ![.verifiedComplete, .cleaned].contains($0.progress?.phase) }
        guard openRequests.count <= 1, openJournals.count <= 1 else { throw Failure.unresolvedArtifacts }
        // Unknown versions/bytes were already rejected by both private stores.
        // Cleaned receipts from older accounts do not grant new write authority.
        guard !openJournals.contains(where: { $0.progress?.phase == .invalidated }) else { throw Failure.unresolvedArtifacts }
        if openRequests.isEmpty, openJournals.isEmpty, !requestEntries.contains(where: \.cleanupRequired) {
            return .init(container: nil, completion: pendingCompletion)
        }
        guard !hasOpenedRuntime, isCurrentLaunch() else { throw Failure.fullRestartRequired }
        guard let installationOwnerID else { throw Failure.ownershipUnavailable }
        let namespace = namespace(for: selection.durableStoreURL)
        for entry in requestEntries where entry.receipt == nil || entry.cleanupRequired {
            guard entry.namespace == namespace, entry.installationOwnerID == installationOwnerID else { throw Failure.ownershipUnavailable }
            if let receipt = entry.receipt { try await requests.finishReceiptCleanup(receipt) }
        }
        for entry in openJournals where !entry.isStaging {
            guard entry.descriptor?.namespace == namespace, entry.descriptor?.installationOwnerID == installationOwnerID else { throw Failure.ownershipUnavailable }
        }
        guard isCurrentLaunch() else { throw Failure.fullRestartRequired }
        guard let transactionID = openRequests.first?.transactionID ?? openJournals.first?.transactionID else {
            return .init(container: nil, completion: pendingCompletion)
        }
        guard openJournals.first?.transactionID == nil || openJournals.first?.transactionID == transactionID else {
            throw Failure.unresolvedArtifacts
        }
        let request: NFRestoreRestartRequest? = if openRequests.first != nil {
            try await requests.load(transactionID: transactionID, namespace: namespace, owner: installationOwnerID)
        } else { nil }

        let existing = journalEntries.first { $0.transactionID == transactionID && !$0.isStaging }
        var loaded: NFRestoreJournalLoaded?
        if existing != nil {
            loaded = try await journal.load(transactionID: transactionID, namespace: namespace, installationOwnerID: installationOwnerID)
            if let request { try validateBinding(request, plan: loaded!.plan) }
            if loaded?.progress.phase == .verifiedComplete {
                // A later legitimate deletion/edit must never replay this plan.
                // Only a missing request receipt is completed here.
                let completion = if let request {
                    try await requests.resolve(request, resolution: .completed,
                        acceptedPlanDigest: loaded!.descriptor.planDigest, counts: loaded!.plan.acceptedCounts)
                } else { nil as NFRestoreRequestReceipt? }
                return .init(container: nil, completion: completion)
            }
        }
        guard isCurrentLaunch() else { throw Failure.fullRestartRequired }
        let container = try makeContainer?() ?? ModelContainer(for: Schema(versionedSchema: NFSchemaV1.self),
            migrationPlan: NFSchemaMigrationPlan.self,
            configurations: NFPersistentStoreLocation.configurations(durableStoreURL: selection.durableStoreURL, privateCloudConfiguration: nil))
        container.mainContext.autosaveEnabled = false
        let fileApplier = NFRestoreFileApplier(roots: try prepareSideFileRoots(applicationSupportURL: applicationSupportURL, namespace: namespace), lease: lease)
        if loaded == nil {
            guard let request, let policy = NFDataArchiveRestorePolicy(rawValue: request.policyRaw) else { throw Failure.unresolvedArtifacts }
            let files = try await fileApplier.captureFiles()
            let aiArtifacts = try await fileApplier.captureAIArtifacts()
            let context = ModelContext(container); context.autosaveEnabled = false
            let destination = try NFRestorePlanCompiler.captureDestination(context: context,
                localLearningBytes: files["local-learning"]!, adaptiveHistoryBytes: files["adaptive-history"]!, aiLearningArtifacts: aiArtifacts)
            guard try destination.reviewDigest == request.reviewedDestinationDigest else { throw Failure.renewedReviewRequired }
            let plan: NFRestoreJournalPlan
            if let candidate = try await journal.loadUnacceptedCandidate(transactionID: transactionID, namespace: namespace,
                installationOwnerID: installationOwnerID) {
                try validateBinding(request, plan: candidate)
                let candidateBefore = NFRestoreDestinationSnapshot(raw: candidate.raw.before,
                    localLearningBytes: candidate.files.first { $0.id == "local-learning" }?.before,
                    adaptiveHistoryBytes: candidate.files.first { $0.id == "adaptive-history" }?.before,
                    aiLearningArtifacts: try NFAILearningArtifactArchive.files(from: candidate.files, before: true))
                guard try candidateBefore.reviewDigest == request.reviewedDestinationDigest else { throw Failure.renewedReviewRequired }
                plan = candidate
            } else {
                let prepared = try NFRestorePlanCompiler.preparedFromPermittedPayload(request.permittedPayload,
                    sourceDigest: request.sourceDigest, sourceByteCount: request.sourceByteCount, sourceFilename: request.sourceFilename)
                plan = try NFRestorePlanCompiler.compile(prepared: prepared, policy: policy,
                    expectedReviewDigest: request.reviewedDestinationDigest, destination: destination,
                    transactionID: transactionID, namespace: namespace, ownerDeviceID: installationOwnerID,
                    compiledAt: Date(timeIntervalSinceReferenceDate: request.compiledAtReferenceSeconds),
                    locale: Locale(identifier: request.localeIdentifier), frozenPermittedPayload: request.permittedPayload)
            }
            guard isCurrentLaunch() else { throw Failure.fullRestartRequired }
            loaded = try await journal.accept(plan)
        }
        guard let accepted = loaded, isCurrentLaunch() else { throw Failure.fullRestartRequired }
        // Record potential mutation before the first store transaction. A lost
        // save acknowledgement is reconciled against the same accepted bytes.
        if accepted.progress.phase == .accepted {
            _ = try await journal.mark(transactionID: transactionID, namespace: namespace,
                installationOwnerID: installationOwnerID, expectedRevision: accepted.progress.revision, phase: .mutationMayHaveStarted)
        }
        guard isCurrentLaunch() else { throw Failure.fullRestartRequired }
        do {
            let beforeFiles = try await fileApplier.captureFiles(operations: accepted.plan.files)
            let fresh = ModelContext(container); fresh.autosaveEnabled = false
            let before = try NFDataArchiveRawCapture.capture(context: fresh)
            let status = try NFRestoreJournalCodec.reconcile(accepted, current: before, files: beforeFiles)
            guard !status.hasConflict else { throw NFRestoreJournalError.recoveryConflict }
            for domain in [NFDataArchiveRawDatabaseDomain.durable, .localOnly] {
                guard isCurrentLaunch() else { throw Failure.fullRestartRequired }
                _ = try NFRestoreDomainApplier.applyDatabaseDomain(plan: accepted.plan, domain: domain, container: container)
            }
            for operation in accepted.plan.files {
                guard isCurrentLaunch() else { throw Failure.fullRestartRequired }
                _ = try await fileApplier.apply(operation, transactionID: transactionID)
            }
            guard isCurrentLaunch() else { throw Failure.fullRestartRequired }
            let finalContext = ModelContext(container); finalContext.autosaveEnabled = false
            let actual = try NFDataArchiveRawCapture.capture(context: finalContext)
            let actualFiles = try await fileApplier.captureFiles(operations: accepted.plan.files)
            let current = try await journal.load(transactionID: transactionID, namespace: namespace, installationOwnerID: installationOwnerID)
            _ = try await journal.verifyComplete(transactionID: transactionID, namespace: namespace,
                installationOwnerID: installationOwnerID, expectedRevision: current.progress.revision, current: actual, files: actualFiles)
            let completion = if let request {
                try await requests.resolve(request, resolution: .completed,
                    acceptedPlanDigest: accepted.descriptor.planDigest, counts: accepted.plan.acceptedCounts)
            } else { nil as NFRestoreRequestReceipt? }
            return .init(container: container, completion: completion)
        } catch {
            if let latest = try? await journal.load(transactionID: transactionID, namespace: namespace, installationOwnerID: installationOwnerID),
               latest.progress.phase != .verifiedComplete {
                _ = try? await journal.mark(transactionID: transactionID, namespace: namespace,
                    installationOwnerID: installationOwnerID, expectedRevision: latest.progress.revision, phase: .recoveryRequired)
            }
            throw error
        }
    }

    private static func validateBinding(_ request: NFRestoreRestartRequest, plan: NFRestoreJournalPlan) throws {
        guard plan.transactionID == request.transactionID, plan.namespace == request.namespace,
              plan.installationOwnerID == request.installationOwnerID, plan.sourceDigest == request.sourceDigest,
              plan.permittedPayloadDigest == request.permittedPayloadDigest,
              plan.permittedPayload == request.permittedPayload, plan.acceptedPolicyRaw == request.policyRaw else {
            throw NFRestoreJournalError.conflictingPlan
        }
    }
}

extension NFRestoreColdCoordinator {
    /// Cancellation is available only before journal acceptance. A staged plan
    /// has no mutation authority, but an accepted plan must finish recovery.
    static func pendingUnacceptedRequest(selection: NFPrivateCloudStoreSelection, applicationSupportURL: URL,
        lease: NFApplicationStoreLease, installationOwnerID: UUID?) async throws -> NFRestoreRestartRequest? {
        guard let installationOwnerID else { return nil }
        let namespace = namespace(for: selection.durableStoreURL)
        let requests = NFRestoreRequestStore(root: NFRestoreRequestStore.root(applicationSupportURL: applicationSupportURL), lease: lease)
        let pending = try await requests.inspectAll().filter { $0.receipt == nil }
        guard pending.count == 1, let entry = pending.first,
              entry.namespace == namespace, entry.installationOwnerID == installationOwnerID else { return nil }
        let root = try NFRestoreJournalLocation.root(applicationSupportURL: applicationSupportURL)
        var metadata = stat()
        if lstat(root.path, &metadata) == 0 {
            let journal = NFDataArchiveRestoreJournal(root: root)
            let entries = try await journal.inspectAllNamespaces()
            guard !entries.contains(where: { !$0.isStaging && $0.transactionID == entry.transactionID }),
                  !entries.contains(where: { $0.isStaging && $0.transactionID != entry.transactionID }),
                  !entries.contains(where: { !$0.isStaging && ![.verifiedComplete, .cleaned].contains($0.progress?.phase) }) else { return nil }
            if let candidate = try await journal.loadUnacceptedCandidate(transactionID: entry.transactionID,
                namespace: namespace, installationOwnerID: installationOwnerID) {
                let request = try await requests.load(transactionID: entry.transactionID, namespace: namespace, owner: installationOwnerID)
                guard candidate.sourceDigest == request.sourceDigest, candidate.permittedPayload == request.permittedPayload,
                      candidate.acceptedPolicyRaw == request.policyRaw else { throw NFRestoreJournalError.conflictingPlan }
            }
        } else if errno != ENOENT { throw NFRestoreJournalError.ioFailure }
        return try await requests.load(transactionID: entry.transactionID, namespace: namespace, owner: installationOwnerID)
    }

    static func cancelUnacceptedRequest(selection: NFPrivateCloudStoreSelection, applicationSupportURL: URL,
        lease: NFApplicationStoreLease, installationOwnerID: UUID?, isCurrentLaunch: () -> Bool) async throws {
        guard let request = try await pendingUnacceptedRequest(selection: selection, applicationSupportURL: applicationSupportURL,
            lease: lease, installationOwnerID: installationOwnerID), isCurrentLaunch() else { throw Failure.unresolvedArtifacts }
        let requests = NFRestoreRequestStore(root: NFRestoreRequestStore.root(applicationSupportURL: applicationSupportURL), lease: lease)
        // This is the durable cancellation boundary. A crash after it cannot
        // make the same request eligible for compilation or staging again.
        _ = try await requests.resolve(request, resolution: .cancelled)
        let journalRoot = try NFRestoreJournalLocation.root(applicationSupportURL: applicationSupportURL)
        var metadata = stat()
        if lstat(journalRoot.path, &metadata) == 0 {
            let journal = NFDataArchiveRestoreJournal(root: journalRoot)
            let entries = try await journal.inspectAllNamespaces()
            if entries.contains(where: { $0.isStaging && $0.transactionID == request.transactionID }) {
                try await journal.removeInvalidated(transactionID: request.transactionID,
                    namespace: request.namespace, installationOwnerID: request.installationOwnerID)
            }
        } else if errno != ENOENT { throw NFRestoreJournalError.ioFailure }
    }
}

extension NFRestoreColdCoordinator {
    /// Explicit Retry cleanup only finishes an existing authenticated
    /// invalidation. It grants no restore/primary-deletion authority and creates
    /// no container, AppStore, account migration, or source transport.
    static func retryInvalidatedCleanup(applicationSupportURL: URL, lease: NFApplicationStoreLease,
        installationOwnerID: UUID?, hasOpenedRuntime: Bool, isCurrentLaunch: () -> Bool) async throws {
        guard !hasOpenedRuntime, isCurrentLaunch() else { throw Failure.fullRestartRequired }
        guard let installationOwnerID else { throw Failure.ownershipUnavailable }
        let requests = NFRestoreRequestStore(root: NFRestoreRequestStore.root(applicationSupportURL: applicationSupportURL), lease: lease)
        await requests.seal()
        let requestEntries = try await requests.inspectAll()
        guard requestEntries.allSatisfy({ $0.receipt != nil }) else { throw Failure.unresolvedArtifacts }
        guard requestEntries.allSatisfy({ $0.installationOwnerID == installationOwnerID }) else { throw Failure.ownershipUnavailable }
        let journal = NFDataArchiveRestoreJournal(root: try NFRestoreJournalLocation.root(applicationSupportURL: applicationSupportURL))
        let candidates = try await journal.preflightExplicitDeletionCleanup(installationOwnerID: installationOwnerID)
        guard candidates.contains(where: { $0.progress?.phase == .invalidated }) else { throw Failure.unresolvedArtifacts }
        guard isCurrentLaunch() else { throw Failure.fullRestartRequired }
        try await journal.finishExplicitDeletionCleanup(installationOwnerID: installationOwnerID,
            expected: candidates, retireVerifiedCompletions: false)
        for entry in requestEntries where entry.cleanupRequired {
            guard let receipt = entry.receipt, isCurrentLaunch() else { throw Failure.fullRestartRequired }
            try await requests.finishReceiptCleanup(receipt)
        }
        guard isCurrentLaunch() else { throw Failure.fullRestartRequired }
        let remaining = try await requests.inspectAll()
        guard remaining.allSatisfy({ $0.receipt != nil && !$0.cleanupRequired }) else { throw Failure.unresolvedArtifacts }
    }
}

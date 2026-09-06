import Foundation
import SwiftUI
import SwiftData

struct NFRestoreReviewedArchive {
    let prepared: NFPreparedDataArchive
    let preview: NFDataArchiveRestorePreview
    let destinationDigest: String
    let permittedPayload: Data
}

enum NFRestoreArtifactCleanupComponent: String, Sendable { case requests, recoveryBackups }

@MainActor @Observable
final class NFRestoreRuntimeController {
    private let applicationSupportURL: URL
    private let namespace: String
    private let owner: UUID
    private var requests: NFRestoreRequestStore
    private let lease: NFApplicationStoreLease
    private let journal: NFDataArchiveRestoreJournal
    private let files: NFRestoreFileApplier
    private var pendingRequest: NFRestoreRestartRequest?
    private var sealed = false
    private var generation = 0
    private(set) var isStaging = false
    private(set) var requiresRestart = false
    private(set) var isCleaningRestoreArtifacts = false
    private(set) var restoreArtifactCleanupRequired = false
    private(set) var restoreArtifactCleanupComponent: NFRestoreArtifactCleanupComponent?
    private(set) var isPerformingLinkedDeletion = false

    var canPrepareRestore: Bool {
        !sealed && !requiresRestart && !isStaging && !isCleaningRestoreArtifacts && !restoreArtifactCleanupRequired
    }

    init(applicationSupportURL: URL, durableStoreURL: URL, owner: UUID, lease: NFApplicationStoreLease,
         requestStore: NFRestoreRequestStore? = nil, journal: NFDataArchiveRestoreJournal? = nil) throws {
        self.applicationSupportURL = applicationSupportURL
        namespace = NFRestoreColdCoordinator.namespace(for: durableStoreURL)
        self.owner = owner
        self.lease = lease
        self.journal = try journal ?? NFDataArchiveRestoreJournal(root: NFRestoreJournalLocation.root(applicationSupportURL: applicationSupportURL))
        requests = requestStore ?? NFRestoreRequestStore(root: NFRestoreRequestStore.root(applicationSupportURL: applicationSupportURL), lease: lease)
        let roots = try NFRestoreColdCoordinator.prepareSideFileRoots(applicationSupportURL: applicationSupportURL, namespace: namespace)
        files = NFRestoreFileApplier(roots: roots, lease: lease)
    }

    func prepareReview(_ prepared: NFPreparedDataArchive, store: AppStore) async throws -> NFRestoreReviewedArchive {
        guard canPrepareRestore, store.activeSessionRequest == nil, !store.localSessions.hasActiveWriter else { throw NFDataArchiveRestoreError.activeSession }
        let version = generation
        let side = try await files.captureFiles()
        guard !sealed, version == generation else { throw NFRestoreJournalError.invalidated }
        let destination = try NFRestorePlanCompiler.captureDestination(context: store.context,
            localLearningBytes: side["local-learning"]!, adaptiveHistoryBytes: side["adaptive-history"]!)
        let preview = try NFRestorePlanCompiler.preview(prepared: prepared, destination: destination, locale: NFAppLocalization.preferredLocale)
        return .init(prepared: prepared, preview: preview, destinationDigest: try destination.reviewDigest,
            permittedPayload: try NFRestorePlanCompiler.permittedPayload(prepared: prepared))
    }

    func stage(_ review: NFRestoreReviewedArchive, policy: NFDataArchiveRestorePolicy,
               store: AppStore, integrations: NFSystemIntegrationCoordinator) async throws {
        guard canPrepareRestore, store.activeSessionRequest == nil, !store.localSessions.hasActiveWriter else { throw NFDataArchiveRestoreError.activeSession }
        isStaging = true; defer { isStaging = false }
        let requestStore = requests
        let version = generation
        let side = try await files.captureFiles()
        guard !sealed, version == generation else { throw NFRestoreJournalError.invalidated }
        let current = try NFRestorePlanCompiler.captureDestination(context: store.context,
            localLearningBytes: side["local-learning"]!, adaptiveHistoryBytes: side["adaptive-history"]!)
        guard try current.reviewDigest == review.destinationDigest else { throw NFRestoreColdCoordinator.Failure.renewedReviewRequired }
        if policy == .abortOnConflict, review.preview.hasConflicts {
            throw NFDataArchiveRestoreError.conflictsRequireDecision(review.preview.conflicts.total + review.preview.localConflicts.values.reduce(0, +))
        }
        let payload = review.permittedPayload
        let request: NFRestoreRestartRequest
        if let pendingRequest {
            guard pendingRequest.sourceDigest == review.prepared.sourceDigest,
                  pendingRequest.reviewedDestinationDigest == review.destinationDigest,
                  pendingRequest.policyRaw == policy.rawValue,
                  pendingRequest.permittedPayload == payload else { throw NFRestoreJournalError.conflictingPlan }
            request = pendingRequest
        } else {
            request = .init(version: 1, transactionID: UUID(), namespace: namespace, installationOwnerID: owner,
                sourceDigest: review.prepared.sourceDigest, sourceByteCount: review.prepared.sourceByteCount,
                sourceFilename: review.prepared.sourceFilename, permittedPayload: payload,
                permittedPayloadDigest: NFRestoreJournalCodec.digest(payload), reviewedDestinationDigest: review.destinationDigest,
                policyRaw: policy.rawValue, localeIdentifier: NFAppLocalization.preferredLocale.identifier,
                compiledAtReferenceSeconds: Date().timeIntervalSinceReferenceDate)
            pendingRequest = request
        }
        do { try await requestStore.stage(request) }
        catch {
            // An error after atomic publication is an acknowledgement problem,
            // never permission to issue a second restore command.
            let saved = try? await requestStore.load(transactionID: request.transactionID, namespace: namespace, owner: owner)
            guard saved == request else { throw error }
        }
        guard !sealed, version == generation else { throw NFRestoreJournalError.invalidated }
        requiresRestart = true
        await integrations.stopForAccountIdentityChange()
    }


    /// A narrow pre-mutation privacy barrier. It must wrap the actual synchronous
    /// AppStore/file deletion, not only the confirmation UI. The callback is
    /// never invoked until every completed restore payload has been removed and
    /// verified. It cannot run after account/whole-device invalidation.
    func performLinkedDeletion<Result>(_ operation: () throws -> Result) async throws -> Result {
        guard !sealed, !isStaging, !isCleaningRestoreArtifacts, !requiresRestart else {
            throw NFRestoreJournalError.recoveryConflict
        }
        isCleaningRestoreArtifacts = true
        restoreArtifactCleanupComponent = .requests
        generation &+= 1
        let version = generation
        let previousRequests = requests
        await previousRequests.seal()
        var artifactsVerified = false
        do {
            guard !sealed, generation == version else { throw NFRestoreJournalError.invalidated }
            let requestEntries = try await previousRequests.inspectAll()
            // An active pre-plan request must be cancelled through the existing
            // explicit cancellation flow. It is never inferred to be completed.
            guard requestEntries.allSatisfy({ $0.receipt != nil }) else { throw NFRestoreJournalError.recoveryConflict }
            guard requestEntries.allSatisfy({ $0.installationOwnerID == owner }) else { throw NFRestoreJournalError.wrongOwner }
            restoreArtifactCleanupComponent = .recoveryBackups
            let candidates = try await journal.preflightExplicitDeletionCleanup(installationOwnerID: owner)
            guard !sealed, generation == version else { throw NFRestoreJournalError.invalidated }
            try await journal.finishExplicitDeletionCleanup(installationOwnerID: owner, expected: candidates)
            restoreArtifactCleanupComponent = .requests
            for entry in requestEntries where entry.cleanupRequired {
                guard let receipt = entry.receipt else { throw NFRestoreJournalError.malformed }
                try await previousRequests.finishReceiptCleanup(receipt)
            }
            let remaining = try await previousRequests.inspectAll()
            guard remaining.allSatisfy({ $0.receipt != nil && !$0.cleanupRequired && $0.installationOwnerID == owner }) else {
                throw NFRestoreJournalError.recoveryConflict
            }
            guard !sealed, generation == version else { throw NFRestoreJournalError.invalidated }
            artifactsVerified = true
            try Task.checkCancellation()
            // No suspension point between granting mutation and removing it.
            isPerformingLinkedDeletion = true
            defer { isPerformingLinkedDeletion = false }
            let result = try operation()
            renewRestoreRequestsAfterDeletion()
            isCleaningRestoreArtifacts = false
            restoreArtifactCleanupRequired = false
            restoreArtifactCleanupComponent = nil
            return result
        } catch {
            isCleaningRestoreArtifacts = false
            if artifactsVerified {
                // Primary database/file deletion can fail independently. Its
                // own retry/rollback remains responsible for those records;
                // completed restore backups must not be recreated as rollback.
                renewRestoreRequestsAfterDeletion()
                restoreArtifactCleanupRequired = false
                restoreArtifactCleanupComponent = nil
            } else {
                restoreArtifactCleanupRequired = true
            }
            throw error
        }
    }

    private func renewRestoreRequestsAfterDeletion() {
        guard !sealed else { return }
        pendingRequest = nil
        requests = NFRestoreRequestStore(root: NFRestoreRequestStore.root(applicationSupportURL: applicationSupportURL), lease: lease)
    }

    func ownsDeletionBoundary(for installationOwnerID: UUID, storeURLs: [URL]) -> Bool {
        owner == installationOwnerID && storeURLs.contains { NFRestoreColdCoordinator.namespace(for: $0) == namespace }
    }

    func seal() async {
        sealed = true; generation &+= 1
        await requests.seal()
    }
}

extension EnvironmentValues {
    @Entry var archiveRestoreController: NFRestoreRuntimeController? = nil
}

enum NFRestoreArtifactDeletionPolicy: Sendable {
    case automatic
    case required
    /// Only explicit disposable stores with isolated artifact roots may opt out.
    case isolatedNoRestoreArtifacts
}

enum NFRestoreLinkedDeletionError: Error, LocalizedError {
    case unavailable
    case unfinished(NFRestoreArtifactCleanupComponent)

    var errorDescription: String? {
        switch self {
        case .unavailable:
            NFAppLocalization.localized("Restore cleanup is unavailable. Your data has not been deleted. Restart and try again.")
        case .unfinished(.recoveryBackups):
            NFAppLocalization.localized("Restore recovery-file cleanup is unfinished. Your data has not been deleted. Retry cleanup before deleting it.")
        case .unfinished(.requests):
            NFAppLocalization.localized("Pending restore-request cleanup is unfinished. Your data has not been deleted. Finish or cancel the pending restore, then retry deletion.")
        }
    }
}

extension AppStore {
    func bindRestoreArtifactDeletionController(_ controller: NFRestoreRuntimeController?) {
        restoreArtifactDeletionController = controller
    }

    /// The synchronous methods also enforce this boundary, so a new caller
    /// cannot bypass it merely by omitting the UI wrapper.
    func requireRestoreArtifactDeletionAuthorization() throws {
        try localSessions.requireArchiveWriteAvailability()
        guard requiresRestoreArtifactDeletionGate else { return }
        guard let controller = restoreArtifactDeletionController,
              controller.ownsDeletionBoundary(for: localSessions.ownerDeviceID, storeURLs: context.container.configurations.map(\.url)),
              controller.isPerformingLinkedDeletion else { throw NFRestoreLinkedDeletionError.unavailable }
    }

    func withLinkedRestoreArtifactDeletion<Result>(_ operation: () throws -> Result) async throws -> Result {
        guard requiresRestoreArtifactDeletionGate else { return try operation() }
        guard let controller = restoreArtifactDeletionController,
              controller.ownsDeletionBoundary(for: localSessions.ownerDeviceID, storeURLs: context.container.configurations.map(\.url)) else { throw NFRestoreLinkedDeletionError.unavailable }
        do { return try await controller.performLinkedDeletion(operation) }
        catch {
            if controller.restoreArtifactCleanupRequired {
                throw NFRestoreLinkedDeletionError.unfinished(controller.restoreArtifactCleanupComponent ?? .recoveryBackups)
            }
            throw error
        }
    }
}

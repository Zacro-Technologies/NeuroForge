import CloudKit
import Foundation

struct NFPrivateDocumentTransportSnapshot: Equatable, Sendable {
    let isInstalled: Bool
    let accountState: NFCloudAccountState
    let phase: NFSyncEnginePhase
    let queue: NFSyncQueueMetrics
    let lastSuccessfulSyncAt: Date?
}

struct NFPrivateDocumentDeletionVerification: Equatable, Sendable {
    let requestedDocumentIDs: Set<UUID>
    let durableTombstoneDocumentIDs: Set<UUID>
    let pendingChangeCount: Int
    let lastSuccessfulSyncAt: Date?

    var allRequestsAreDurable: Bool {
        requestedDocumentIDs.isSubset(of: durableTombstoneDocumentIDs)
    }

    var isRemotelyAcknowledged: Bool {
        allRequestsAreDurable
            && pendingChangeCount == 0
            && lastSuccessfulSyncAt != nil
    }
}

enum NFDocumentPrivateSyncState: String, Codable, Equatable, Sendable {
    case localOnly
    case unavailable
    case queued
    case uploaded
    case paused
    case error
}

protocol NFPrivateDocumentAssetTransport: Sendable {
    func start() async -> NFPrivateDocumentTransportSnapshot
    func reconcile(_ inputs: [NFDocumentOriginalInput]) async
    func enqueueDeletion(documentID: UUID) async
    func synchronize() async -> NFPrivateDocumentTransportSnapshot
    func snapshot() async -> NFPrivateDocumentTransportSnapshot
    func documentState(documentID: UUID) async -> NFDocumentPrivateSyncState
    func receivedRevisions() async -> [NFDocumentOriginalRevision]
    func receivedTombstones() async -> [NFDocumentOriginalTombstone]
    func deletionVerification(
        requestedDocumentIDs: Set<UUID>
    ) async -> NFPrivateDocumentDeletionVerification
    func clearLocalStatePreservingRemote() async throws
    func stop() async
}

/// Coalesces actor-reentrant callers onto one async operation. The generation
/// token prevents a waiter from an older completed flight from clearing a newer
/// task that started before that waiter resumed.
actor NFAsyncSingleFlight<Value: Sendable> {
    private var flight: (id: UUID, task: Task<Value, Never>)?

    func run(
        _ operation: @escaping @Sendable () async -> Value
    ) async -> Value {
        if let flight { return await flight.task.value }
        let id = UUID()
        let task = Task { await operation() }
        flight = (id, task)
        let value = await task.value
        if flight?.id == id { flight = nil }
        return value
    }

    func cancelAndWait() async {
        guard let current = flight else { return }
        current.task.cancel()
        _ = await current.task.value
        if flight?.id == current.id { flight = nil }
    }
}

enum NFCloudKitErrorMapper {
    static func map(_ error: any Error) -> NFCloudTransportFailure {
        let nsError = error as NSError
        guard nsError.domain == CKErrorDomain,
              let code = CKError.Code(rawValue: nsError.code) else {
            return .unknown(redactedCode: "non-cloudkit")
        }
        let retryAfter = (nsError.userInfo[CKErrorRetryAfterKey] as? NSNumber)?.doubleValue
        switch code {
        case .notAuthenticated:
            return .accountUnavailable(temporary: false)
        case .accountTemporarilyUnavailable:
            return .accountUnavailable(temporary: true)
        case .networkUnavailable, .networkFailure, .serverResponseLost:
            return .networkUnavailable(retryAfterSeconds: retryAfter)
        case .quotaExceeded:
            return .quotaExceeded
        case .serviceUnavailable, .zoneBusy:
            return .serviceUnavailable(retryAfterSeconds: retryAfter)
        case .requestRateLimited:
            return .rateLimited(retryAfterSeconds: retryAfter)
        case .partialFailure, .batchRequestFailed:
            let itemErrors = nsError.userInfo[CKPartialErrorsByItemIDKey] as? [AnyHashable: any Error] ?? [:]
            let names = itemErrors.keys.compactMap(recordName).sorted()
            return .partialFailure(failedRecordNames: names)
        case .serverRecordChanged:
            return .conflict
        case .assetFileNotFound, .assetFileModified, .assetNotAvailable:
            return .assetUnavailable
        case .zoneNotFound, .userDeletedZone, .changeTokenExpired:
            return .zoneUnavailable
        case .permissionFailure, .managedAccountRestricted, .missingEntitlement, .badContainer:
            return .permissionDenied
        case .operationCancelled:
            return .cancelled
        default:
            return .unknown(redactedCode: "ck-\(nsError.code)")
        }
    }

    static func deletionIsAlreadyConverged(_ error: any Error) -> Bool {
        let nsError = error as NSError
        return nsError.domain == CKErrorDomain
            && nsError.code == CKError.Code.unknownItem.rawValue
    }

    private static func recordName(_ key: AnyHashable) -> String? {
        if let id = key.base as? CKRecord.ID { return id.recordName }
        if let value = key.base as? String {
            let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_."))
            guard !value.isEmpty, value.unicodeScalars.allSatisfy(allowed.contains) else { return nil }
            return String(value.prefix(160))
        }
        return nil
    }
}

enum NFCloudAccountStateMapper {
    static func map(_ status: CKAccountStatus) -> NFCloudAccountState {
        switch status {
        case .available: .available
        case .noAccount: .noAccount
        case .restricted: .restricted
        case .temporarilyUnavailable: .temporarilyUnavailable
        case .couldNotDetermine: .unknown
        @unknown default: .unknown
        }
    }
}

private enum NFPrivateDocumentCloudField {
    static let schemaVersion = "schemaVersion"
    static let documentID = "documentID"
    static let contentHash = "contentHash"
    static let filename = "filename"
    static let typeIdentifier = "typeIdentifier"
    static let sizeBytes = "sizeBytes"
    static let modifiedAt = "modifiedAt"
    static let aiPolicy = "aiPolicy"
    static let pccConsentPolicyVersion = "pccConsentPolicyVersion"
    static let pccConsentedAt = "pccConsentedAt"
    static let assetReference = "assetReference"
    static let payload = "payload"
    static let deletedAt = "deletedAt"
}

enum NFPrivateDocumentCloudRecordCodec {
    static let schemaVersion = 1

    static func makeRecord(
        for mutation: NFDocumentAssetPendingMutation,
        zoneID: CKRecordZone.ID,
        baseRecord: CKRecord? = nil
    ) throws -> CKRecord? {
        let recordID = CKRecord.ID(recordName: mutation.recordName, zoneID: zoneID)
        switch mutation.operation {
        case .saveAsset:
            guard let revision = mutation.revision,
                  NFContentAddressedAssetHasher.isValidSHA256(revision.contentHash) else {
                throw NFDocumentAssetIntegrityError.invalidContentHash
            }
            let url = URL(fileURLWithPath: revision.localFilePath)
            guard try NFContentAddressedAssetHasher.sha256(fileURL: url) == revision.contentHash else {
                throw NFDocumentAssetIntegrityError.contentHashMismatch
            }
            let record = record(
                type: NFPrivateCloudSchemaManifest.assetRecordType,
                id: recordID,
                base: baseRecord
            )
            record[NFPrivateDocumentCloudField.schemaVersion] = schemaVersion as CKRecordValue
            record[NFPrivateDocumentCloudField.contentHash] = revision.contentHash as CKRecordValue
            record[NFPrivateDocumentCloudField.sizeBytes] = revision.sizeBytes as CKRecordValue
            record[NFPrivateDocumentCloudField.payload] = CKAsset(fileURL: url)
            try validateFieldBoundary(record)
            return record

        case .saveDocument:
            guard let revision = mutation.revision else { return nil }
            let record = record(
                type: NFPrivateCloudSchemaManifest.documentRecordType,
                id: recordID,
                base: baseRecord
            )
            let assetID = CKRecord.ID(recordName: revision.assetRecordName, zoneID: zoneID)
            record[NFPrivateDocumentCloudField.schemaVersion] = schemaVersion as CKRecordValue
            record[NFPrivateDocumentCloudField.documentID] = revision.documentID.uuidString as CKRecordValue
            record[NFPrivateDocumentCloudField.contentHash] = revision.contentHash as CKRecordValue
            record[NFPrivateDocumentCloudField.filename] = revision.filename as CKRecordValue
            record[NFPrivateDocumentCloudField.typeIdentifier] = revision.typeIdentifier as CKRecordValue
            record[NFPrivateDocumentCloudField.sizeBytes] = revision.sizeBytes as CKRecordValue
            record[NFPrivateDocumentCloudField.modifiedAt] = revision.modifiedAt as CKRecordValue
            record[NFPrivateDocumentCloudField.aiPolicy] = revision.aiPolicyRaw as CKRecordValue
            record[NFPrivateDocumentCloudField.pccConsentPolicyVersion] = revision.pccConsentPolicyVersion as CKRecordValue
            if let consentedAt = revision.pccConsentedAt {
                record[NFPrivateDocumentCloudField.pccConsentedAt] = consentedAt as CKRecordValue
            }
            record[NFPrivateDocumentCloudField.assetReference] = CKRecord.Reference(
                recordID: assetID,
                action: .none
            )
            try validateFieldBoundary(record)
            return record

        case .saveTombstone:
            guard let tombstone = mutation.tombstone else { return nil }
            let record = record(
                type: NFPrivateCloudSchemaManifest.tombstoneRecordType,
                id: recordID,
                base: baseRecord
            )
            record[NFPrivateDocumentCloudField.schemaVersion] = schemaVersion as CKRecordValue
            record[NFPrivateDocumentCloudField.documentID] = tombstone.documentID.uuidString as CKRecordValue
            if let hash = tombstone.contentHash {
                record[NFPrivateDocumentCloudField.contentHash] = hash as CKRecordValue
            }
            record[NFPrivateDocumentCloudField.deletedAt] = tombstone.deletedAt as CKRecordValue
            try validateFieldBoundary(record)
            return record

        case .deleteDocument, .deleteAsset, .deleteTombstone:
            return nil
        }
    }

    static func decodeRevision(
        _ record: CKRecord,
        downloadedAssetPath: String?
    ) -> NFDocumentOriginalRevision? {
        guard record.recordType == NFPrivateCloudSchemaManifest.documentRecordType,
              let idRaw = record[NFPrivateDocumentCloudField.documentID] as? String,
              let documentID = UUID(uuidString: idRaw),
              let hash = record[NFPrivateDocumentCloudField.contentHash] as? String,
              NFContentAddressedAssetHasher.isValidSHA256(hash),
              let filename = record[NFPrivateDocumentCloudField.filename] as? String,
              let typeIdentifier = record[NFPrivateDocumentCloudField.typeIdentifier] as? String,
              let size = record[NFPrivateDocumentCloudField.sizeBytes] as? NSNumber,
              let modifiedAt = record[NFPrivateDocumentCloudField.modifiedAt] as? Date,
              let aiPolicy = record[NFPrivateDocumentCloudField.aiPolicy] as? String,
              let policyVersion = record[NFPrivateDocumentCloudField.pccConsentPolicyVersion] as? NSNumber else {
            return nil
        }
        return NFDocumentOriginalRevision(
            documentID: documentID,
            contentHash: hash,
            filename: filename,
            typeIdentifier: typeIdentifier,
            sizeBytes: size.int64Value,
            localFilePath: downloadedAssetPath ?? "",
            modifiedAt: modifiedAt,
            aiPolicyRaw: aiPolicy,
            pccConsentPolicyVersion: policyVersion.intValue,
            pccConsentedAt: record[NFPrivateDocumentCloudField.pccConsentedAt] as? Date
        )
    }

    static func decodeTombstone(_ record: CKRecord) -> NFDocumentOriginalTombstone? {
        guard record.recordType == NFPrivateCloudSchemaManifest.tombstoneRecordType,
              let idRaw = record[NFPrivateDocumentCloudField.documentID] as? String,
              let documentID = UUID(uuidString: idRaw),
              let deletedAt = record[NFPrivateDocumentCloudField.deletedAt] as? Date else {
            return nil
        }
        return NFDocumentOriginalTombstone(
            documentID: documentID,
            contentHash: record[NFPrivateDocumentCloudField.contentHash] as? String,
            deletedAt: deletedAt
        )
    }

    static func asset(_ record: CKRecord) -> (hash: String, fileURL: URL)? {
        guard record.recordType == NFPrivateCloudSchemaManifest.assetRecordType,
              let hash = record[NFPrivateDocumentCloudField.contentHash] as? String,
              NFContentAddressedAssetHasher.isValidSHA256(hash),
              let asset = record[NFPrivateDocumentCloudField.payload] as? CKAsset,
              let fileURL = asset.fileURL else {
            return nil
        }
        return (hash, fileURL)
    }

    static func validateFieldBoundary(_ record: CKRecord) throws {
        guard NFPrivateCloudSchemaManifest.isAllowedRecordType(record.recordType),
              NFPrivateCloudSchemaManifest.fieldsArePrivacySafe(
                recordType: record.recordType,
                keys: Set(record.allKeys())
              ) else {
            throw NFDocumentAssetIntegrityError.invalidContentHash
        }
    }

    private static func record(type: String, id: CKRecord.ID, base: CKRecord?) -> CKRecord {
        guard let base, base.recordType == type, base.recordID == id else {
            return CKRecord(recordType: type, recordID: id)
        }
        return base
    }
}

actor NFCKSyncEngineDocumentAssetAdapter: NFPrivateDocumentAssetTransport, CKSyncEngineDelegate {
    private let container: CKContainer
    private let database: CKDatabase
    private let zoneID: CKRecordZone.ID
    private let queue: NFDocumentAssetMutationQueue
    private let receivedAssetRoot: URL
    private var engine: CKSyncEngine?
    private var accountState: NFCloudAccountState = .unknown
    private var phase: NFSyncEnginePhase = .notStarted
    private var accountSwitchRequiresFreshOptIn = false
    private var isStopping = false
    private var isStopped = false
    private let startFlight = NFAsyncSingleFlight<NFPrivateDocumentTransportSnapshot>()
    private let synchronizationFlight = NFAsyncSingleFlight<NFPrivateDocumentTransportSnapshot>()

    init(
        containerIdentifier: String,
        stateStore: any NFDocumentAssetSyncStateStore,
        receivedAssetRoot: URL
    ) {
        let container = CKContainer(identifier: containerIdentifier)
        self.container = container
        database = container.privateCloudDatabase
        zoneID = CKRecordZone.ID(
            zoneName: NFPrivateCloudSchemaManifest.zoneName,
            ownerName: CKCurrentUserDefaultName
        )
        queue = NFDocumentAssetMutationQueue(store: stateStore)
        self.receivedAssetRoot = receivedAssetRoot
    }

    static func makeApplicationAdapter(
        configuration: NFPrivateCloudRuntimeConfiguration
    ) throws -> NFCKSyncEngineDocumentAssetAdapter {
        let fileManager = FileManager.default
        let locations = try NFFileDocumentAssetSyncStateStore.applicationStorageLocations(
            fileManager: fileManager
        )
        return NFCKSyncEngineDocumentAssetAdapter(
            containerIdentifier: configuration.containerIdentifier,
            stateStore: NFFileDocumentAssetSyncStateStore(fileURL: locations.stateURL),
            receivedAssetRoot: locations.receivedAssetRootURL
        )
    }

    func start() async -> NFPrivateDocumentTransportSnapshot {
        guard !isStopping, !isStopped else { return await snapshot() }
        return await startFlight.run { [self] in
            await performStart()
        }
    }

    private func performStart() async -> NFPrivateDocumentTransportSnapshot {
        guard !isStopping, !isStopped, !Task.isCancelled, engine == nil else {
            return await snapshot()
        }
        do {
            let queueSnapshot = try await queue.snapshot()
            guard !isStopping, !isStopped, !Task.isCancelled else {
                return await snapshot()
            }
            let serialization = queueSnapshot.engineStateSerialization.flatMap {
                try? JSONDecoder().decode(CKSyncEngine.State.Serialization.self, from: $0)
            }
            var configuration = CKSyncEngine.Configuration(
                database: database,
                stateSerialization: serialization,
                delegate: self
            )
            configuration.automaticallySync = true
            let newEngine = CKSyncEngine(configuration)
            engine = newEngine
            if serialization == nil {
                newEngine.state.add(pendingDatabaseChanges: [
                    .saveZone(CKRecordZone(zoneID: zoneID))
                ])
            }
            try await alignEnginePendingChanges()
            guard !isStopping, !isStopped, !Task.isCancelled, engine === newEngine else {
                return await snapshot()
            }
            accountState = try await NFCloudAccountStateMapper.map(container.accountStatus())
            guard !isStopping, !isStopped, !Task.isCancelled, engine === newEngine else {
                return await snapshot()
            }
            phase = .idle
            return await snapshot()
        } catch {
            let failure = NFCloudKitErrorMapper.map(error)
            phase = .failed(redactedCode: failure.redactedCode)
            return await snapshot()
        }
    }

    func reconcile(_ inputs: [NFDocumentOriginalInput]) async {
        guard !isStopping, !isStopped else { return }
        do {
            try await queue.reconcile(inputs)
            try await alignEnginePendingChanges()
        } catch {
            let failure = (error as? NFDocumentAssetIntegrityError) == nil
                ? NFCloudKitErrorMapper.map(error)
                : NFCloudTransportFailure.invalidLocalAsset
            phase = .failed(redactedCode: failure.redactedCode)
        }
    }

    func enqueueDeletion(documentID: UUID) async {
        guard !isStopping, !isStopped else { return }
        do {
            try await queue.enqueueDelete(documentID: documentID)
            try await alignEnginePendingChanges()
        } catch {
            phase = .failed(redactedCode: NFCloudTransportFailure.invalidLocalAsset.redactedCode)
        }
    }

    func synchronize() async -> NFPrivateDocumentTransportSnapshot {
        guard !isStopping, !isStopped else { return await snapshot() }
        return await synchronizationFlight.run { [self] in
            await performSynchronization()
        }
    }

    private func performSynchronization() async -> NFPrivateDocumentTransportSnapshot {
        guard !isStopping, !isStopped, !Task.isCancelled else {
            return await snapshot()
        }
        guard let engine else { return await start() }
        guard !accountSwitchRequiresFreshOptIn else { return await snapshot() }
        phase = .processing
        do {
            accountState = try await NFCloudAccountStateMapper.map(container.accountStatus())
            guard synchronizationCanContinue(with: engine) else { return await snapshot() }
            guard accountState == .available else {
                phase = .idle
                return await snapshot()
            }
            try await alignEnginePendingChanges()
            guard synchronizationCanContinue(with: engine) else { return await snapshot() }
            // A brand-new engine has a pending custom-zone save. Send database
            // changes before fetching that zone; fetching first can report
            // zone-not-found before CloudKit has created it. The second send
            // flushes any conflict-resolution mutations produced by the fetch.
            try await engine.sendChanges(
                CKSyncEngine.SendChangesOptions(scope: .zoneIDs([zoneID]))
            )
            guard synchronizationCanContinue(with: engine) else { return await snapshot() }
            if case .failed = phase { return await snapshot() }
            try await engine.fetchChanges(
                CKSyncEngine.FetchChangesOptions(scope: .zoneIDs([zoneID]))
            )
            guard synchronizationCanContinue(with: engine) else { return await snapshot() }
            if case .failed = phase { return await snapshot() }
            try await alignEnginePendingChanges()
            guard synchronizationCanContinue(with: engine) else { return await snapshot() }
            try await engine.sendChanges(
                CKSyncEngine.SendChangesOptions(scope: .zoneIDs([zoneID]))
            )
            guard synchronizationCanContinue(with: engine) else { return await snapshot() }
            if case .failed = phase { return await snapshot() }
            try await queue.markSyncPassSuccessful()
            guard synchronizationCanContinue(with: engine) else { return await snapshot() }
            phase = .idle
        } catch {
            let failure = NFCloudKitErrorMapper.map(error)
            phase = .failed(redactedCode: failure.redactedCode)
        }
        return await snapshot()
    }

    func snapshot() async -> NFPrivateDocumentTransportSnapshot {
        let queueSnapshot = try? await queue.snapshot()
        return NFPrivateDocumentTransportSnapshot(
            isInstalled: engine != nil,
            accountState: accountState,
            phase: phase,
            queue: queueSnapshot?.metrics ?? NFSyncQueueMetrics(
                pendingRecordCount: 0,
                pendingAssetCount: 0
            ),
            lastSuccessfulSyncAt: queueSnapshot?.lastSuccessfulSyncAt
        )
    }

    func documentState(documentID: UUID) async -> NFDocumentPrivateSyncState {
        guard engine != nil else { return .unavailable }
        guard let snapshot = try? await queue.snapshot() else { return .error }
        if case .failed = phase { return .error }
        if accountState != .available { return .paused }
        if snapshot.pending.contains(where: { $0.documentID == documentID }) {
            return .queued
        }
        guard let revision = snapshot.revisions.first(where: { $0.documentID == documentID }) else {
            return snapshot.tombstones.contains(where: { $0.documentID == documentID }) ? .queued : .localOnly
        }
        return snapshot.confirmedRemoteAssetHashes.contains(revision.contentHash) ? .uploaded : .queued
    }

    func receivedRevisions() async -> [NFDocumentOriginalRevision] {
        guard let snapshot = try? await queue.snapshot() else { return [] }
        return snapshot.revisions.filter { !$0.localFilePath.isEmpty }
    }

    func receivedTombstones() async -> [NFDocumentOriginalTombstone] {
        guard let snapshot = try? await queue.snapshot() else { return [] }
        return snapshot.tombstones
    }

    func deletionVerification(
        requestedDocumentIDs: Set<UUID>
    ) async -> NFPrivateDocumentDeletionVerification {
        guard let snapshot = try? await queue.snapshot() else {
            return NFPrivateDocumentDeletionVerification(
                requestedDocumentIDs: requestedDocumentIDs,
                durableTombstoneDocumentIDs: [],
                pendingChangeCount: Int.max,
                lastSuccessfulSyncAt: nil
            )
        }
        return NFPrivateDocumentDeletionVerification(
            requestedDocumentIDs: requestedDocumentIDs,
            durableTombstoneDocumentIDs: Set(snapshot.tombstones.map(\.documentID)),
            pendingChangeCount: snapshot.metrics.totalPendingCount,
            lastSuccessfulSyncAt: snapshot.lastSuccessfulSyncAt
        )
    }

    func clearLocalStatePreservingRemote() async throws {
        isStopping = true
        isStopped = true
        await cancelAndDrainTransportOperations()
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: receivedAssetRoot.path) {
            try fileManager.removeItem(at: receivedAssetRoot)
        }
        try await queue.resetLocalStatePreservingRemote()
        accountState = .unknown
        phase = .notStarted
        isStopping = false
    }

    func stop() async {
        isStopping = true
        isStopped = true
        await cancelAndDrainTransportOperations()
        phase = .notStarted
        isStopping = false
    }

    func handleEvent(_ event: CKSyncEngine.Event, syncEngine: CKSyncEngine) async {
        guard !isStopping, !isStopped, engine === syncEngine else { return }
        switch event {
        case let .stateUpdate(update):
            if !accountSwitchRequiresFreshOptIn,
               let data = try? JSONEncoder().encode(update.stateSerialization) {
                try? await queue.replaceEngineStateSerialization(data)
            }

        case let .accountChange(change):
            switch change.changeType {
            case .signIn: accountState = .available
            case .signOut: accountState = .noAccount
            case .switchAccounts:
                // Never carry document mutations or saved CloudKit system
                // fields into a different person's account automatically.
                // Keep every local file, discard account-scoped state, stop
                // offering upload batches for this launch, and require an
                // explicit off/on opt-in before a later launch creates a fresh
                // engine.
                accountSwitchRequiresFreshOptIn = true
                try? await queue.prepareForAccountSwitch()
                accountState = .temporarilyUnavailable
                phase = .failed(redactedCode: "account-changed")
                NFPrivateSyncBootstrapPreference.lockAfterAccountChange()
            @unknown default: accountState = .unknown
            }

        case let .fetchedDatabaseChanges(changes):
            if changes.deletions.contains(where: { $0.zoneID == zoneID }) {
                try? await queue.recoverFromZoneLoss()
                syncEngine.state.add(pendingDatabaseChanges: [
                    .saveZone(CKRecordZone(zoneID: zoneID))
                ])
                phase = .failed(redactedCode: NFCloudTransportFailure.zoneUnavailable.redactedCode)
            }

        case let .fetchedRecordZoneChanges(changes):
            for modification in changes.modifications where modification.record.recordID.zoneID == zoneID {
                await applyRemoteRecord(modification.record)
            }
            for deletion in changes.deletions where deletion.recordID.zoneID == zoneID {
                try? await queue.remoteRecordWasDeleted(recordName: deletion.recordID.recordName)
            }

        case let .sentDatabaseChanges(changes):
            if let failure = changes.failedZoneSaves.first(where: { $0.zone.zoneID == zoneID }) {
                phase = .failed(redactedCode: NFCloudKitErrorMapper.map(failure.error).redactedCode)
            } else if let error = changes.failedZoneDeletes[zoneID] {
                phase = .failed(redactedCode: NFCloudKitErrorMapper.map(error).redactedCode)
            }

        case let .sentRecordZoneChanges(changes):
            for record in changes.savedRecords where record.recordID.zoneID == zoneID {
                if let data = systemFieldsData(for: record) {
                    try? await queue.recordServerSystemFields(
                        recordName: record.recordID.recordName,
                        data: data
                    )
                }
                if let operation = saveOperation(for: record) {
                    try? await queue.acknowledge(
                        recordName: record.recordID.recordName,
                        completedOperation: operation
                    )
                }
            }
            for recordID in changes.deletedRecordIDs where recordID.zoneID == zoneID {
                if let operation = deleteOperation(recordName: recordID.recordName) {
                    try? await queue.acknowledge(
                        recordName: recordID.recordName,
                        completedOperation: operation
                    )
                }
            }
            for failed in changes.failedRecordSaves where failed.record.recordID.zoneID == zoneID {
                let failure = NFCloudKitErrorMapper.map(failed.error)
                if let serverRecord = failed.error.serverRecord {
                    if let data = systemFieldsData(for: serverRecord) {
                        try? await queue.recordServerSystemFields(
                            recordName: serverRecord.recordID.recordName,
                            data: data
                        )
                    }
                    await applyRemoteRecord(serverRecord)
                }
                try? await queue.recordFailure(
                    recordName: failed.record.recordID.recordName,
                    failure: failure
                )
                phase = .failed(redactedCode: failure.redactedCode)
            }
            for (recordID, error) in changes.failedRecordDeletes where recordID.zoneID == zoneID {
                if NFCloudKitErrorMapper.deletionIsAlreadyConverged(error),
                   let operation = deleteOperation(recordName: recordID.recordName) {
                    try? await queue.acknowledge(
                        recordName: recordID.recordName,
                        completedOperation: operation
                    )
                    continue
                }
                let failure = NFCloudKitErrorMapper.map(error)
                try? await queue.recordFailure(recordName: recordID.recordName, failure: failure)
                phase = .failed(redactedCode: failure.redactedCode)
            }
            try? await alignEnginePendingChanges()

        case .willFetchChanges, .willFetchRecordZoneChanges, .willSendChanges:
            phase = .processing

        case let .didFetchRecordZoneChanges(event):
            if let error = event.error {
                phase = .failed(redactedCode: NFCloudKitErrorMapper.map(error).redactedCode)
            }

        case .didFetchChanges, .didSendChanges:
            if case .failed = phase { break }
            phase = .idle

        @unknown default:
            break
        }
    }

    func nextRecordZoneChangeBatch(
        _ context: CKSyncEngine.SendChangesContext,
        syncEngine: CKSyncEngine
    ) async -> CKSyncEngine.RecordZoneChangeBatch? {
        guard !isStopping,
              !isStopped,
              engine === syncEngine,
              !accountSwitchRequiresFreshOptIn else {
            return nil
        }
        guard let snapshot = try? await queue.snapshot(eligibleOnly: true) else { return nil }
        let pending = snapshot.pending.prefix(64).filter { mutation in
            let id = CKRecord.ID(recordName: mutation.recordName, zoneID: zoneID)
            let change: CKSyncEngine.PendingRecordZoneChange = mutation.isSave
                ? .saveRecord(id)
                : .deleteRecord(id)
            return context.options.scope.contains(change)
        }
        guard !pending.isEmpty else { return nil }

        var records: [CKRecord] = []
        var deletions: [CKRecord.ID] = []
        for mutation in pending {
            let id = CKRecord.ID(recordName: mutation.recordName, zoneID: zoneID)
            if mutation.isSave {
                do {
                    let baseData = try? await queue.serverSystemFields(
                        recordName: mutation.recordName
                    )
                    if let record = try NFPrivateDocumentCloudRecordCodec.makeRecord(
                        for: mutation,
                        zoneID: zoneID,
                        baseRecord: baseData.flatMap(recordFromSystemFields)
                    ) {
                        records.append(record)
                    }
                } catch {
                    try? await queue.recordFailure(
                        recordName: mutation.recordName,
                        failure: .invalidLocalAsset
                    )
                }
            } else {
                deletions.append(id)
            }
        }
        guard !records.isEmpty || !deletions.isEmpty else { return nil }
        return CKSyncEngine.RecordZoneChangeBatch(
            recordsToSave: records,
            recordIDsToDelete: deletions,
            atomicByZone: false
        )
    }

    private func alignEnginePendingChanges() async throws {
        guard let engine, !accountSwitchRequiresFreshOptIn else { return }
        let snapshot = try await queue.snapshot(eligibleOnly: true)
        let desired = Set(snapshot.pending.map { mutation -> CKSyncEngine.PendingRecordZoneChange in
            let id = CKRecord.ID(recordName: mutation.recordName, zoneID: zoneID)
            return mutation.isSave ? .saveRecord(id) : .deleteRecord(id)
        })
        let existing = Set(engine.state.pendingRecordZoneChanges.filter { change in
            switch change {
            case let .saveRecord(id), let .deleteRecord(id): id.zoneID == zoneID
            @unknown default: false
            }
        })
        let stale = existing.subtracting(desired)
        let missing = desired.subtracting(existing)
        if !stale.isEmpty { engine.state.remove(pendingRecordZoneChanges: Array(stale)) }
        if !missing.isEmpty { engine.state.add(pendingRecordZoneChanges: Array(missing)) }
    }

    private func synchronizationCanContinue(with activeEngine: CKSyncEngine) -> Bool {
        !isStopping
            && !isStopped
            && !Task.isCancelled
            && engine === activeEngine
            && !accountSwitchRequiresFreshOptIn
    }

    private func cancelAndDrainTransportOperations() async {
        let activeEngine = engine
        engine = nil
        await activeEngine?.cancelOperations()
        await synchronizationFlight.cancelAndWait()
        await startFlight.cancelAndWait()
    }

    private func applyRemoteRecord(_ record: CKRecord) async {
        if let data = systemFieldsData(for: record) {
            try? await queue.recordServerSystemFields(
                recordName: record.recordID.recordName,
                data: data
            )
        }
        switch record.recordType {
        case NFPrivateCloudSchemaManifest.assetRecordType:
            guard let remote = NFPrivateDocumentCloudRecordCodec.asset(record) else { return }
            do {
                let localURL = try copyVerifiedRemoteAsset(from: remote.fileURL, hash: remote.hash)
                try await queue.acceptDownloadedAsset(hash: remote.hash, localURL: localURL)
            } catch {
                phase = .failed(redactedCode: NFCloudTransportFailure.assetUnavailable.redactedCode)
            }

        case NFPrivateCloudSchemaManifest.documentRecordType:
            let snapshot = try? await queue.snapshot()
            let hash = record[NFPrivateDocumentCloudField.contentHash] as? String
            let path = hash.flatMap { snapshot?.downloadedAssetPathsByHash[$0] }
            if let revision = NFPrivateDocumentCloudRecordCodec.decodeRevision(
                record,
                downloadedAssetPath: path
            ) {
                _ = try? await queue.applyRemoteRevision(revision)
            }

        case NFPrivateCloudSchemaManifest.tombstoneRecordType:
            if let tombstone = NFPrivateDocumentCloudRecordCodec.decodeTombstone(record) {
                _ = try? await queue.applyRemoteTombstone(tombstone)
            }

        default:
            // Unknown record types in this custom zone are ignored. They can
            // never be translated into SwiftData or the local asset cache.
            break
        }
    }

    private func saveOperation(for record: CKRecord) -> NFDocumentAssetPendingOperation? {
        switch record.recordType {
        case NFPrivateCloudSchemaManifest.assetRecordType: .saveAsset
        case NFPrivateCloudSchemaManifest.documentRecordType: .saveDocument
        case NFPrivateCloudSchemaManifest.tombstoneRecordType: .saveTombstone
        default: nil
        }
    }

    private func deleteOperation(
        recordName: String
    ) -> NFDocumentAssetPendingOperation? {
        if recordName.hasPrefix("asset-") { return .deleteAsset }
        if recordName.hasPrefix("document-") { return .deleteDocument }
        if recordName.hasPrefix("tombstone-") { return .deleteTombstone }
        return nil
    }

    private func copyVerifiedRemoteAsset(from sourceURL: URL, hash: String) throws -> URL {
        let fileManager = FileManager.default
        guard NFContentAddressedAssetHasher.isValidSHA256(hash),
              try NFContentAddressedAssetHasher.sha256(fileURL: sourceURL) == hash else {
            throw NFDocumentAssetIntegrityError.contentHashMismatch
        }
        try fileManager.createDirectory(at: receivedAssetRoot, withIntermediateDirectories: true)
        let destination = receivedAssetRoot.appending(path: hash, directoryHint: .notDirectory)
        if fileManager.fileExists(atPath: destination.path) {
            guard try NFContentAddressedAssetHasher.sha256(fileURL: destination) == hash else {
                throw NFDocumentAssetIntegrityError.contentHashMismatch
            }
            return destination
        }
        let temporary = receivedAssetRoot.appending(
            path: ".incoming-\(UUID().uuidString)",
            directoryHint: .notDirectory
        )
        try fileManager.copyItem(at: sourceURL, to: temporary)
        do {
            guard try NFContentAddressedAssetHasher.sha256(fileURL: temporary) == hash else {
                throw NFDocumentAssetIntegrityError.contentHashMismatch
            }
            try fileManager.moveItem(at: temporary, to: destination)
            try? fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: destination.path)
            return destination
        } catch {
            try? fileManager.removeItem(at: temporary)
            throw error
        }
    }

    private func systemFieldsData(for record: CKRecord) -> Data? {
        let archiver = NSKeyedArchiver(requiringSecureCoding: true)
        record.encodeSystemFields(with: archiver)
        archiver.finishEncoding()
        return archiver.encodedData
    }

    private func recordFromSystemFields(_ data: Data) -> CKRecord? {
        guard let unarchiver = try? NSKeyedUnarchiver(forReadingFrom: data) else { return nil }
        unarchiver.requiresSecureCoding = true
        defer { unarchiver.finishDecoding() }
        return CKRecord(coder: unarchiver)
    }
}

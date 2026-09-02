import CryptoKit
import Foundation

enum NFDocumentSyncPolicy: String, Codable, CaseIterable, Sendable {
    case localOnly
    case privateOriginal
}

struct NFDocumentOriginalInput: Equatable, Sendable {
    let documentID: UUID
    let filename: String
    let typeIdentifier: String
    let localURL: URL
    let modifiedAt: Date
    let aiPolicyRaw: String
    let pccConsentPolicyVersion: Int
    let pccConsentedAt: Date?
}

struct NFDocumentOriginalRevision: Codable, Equatable, Sendable {
    let documentID: UUID
    let contentHash: String
    let filename: String
    let typeIdentifier: String
    let sizeBytes: Int64
    let localFilePath: String
    let modifiedAt: Date
    let aiPolicyRaw: String
    let pccConsentPolicyVersion: Int
    let pccConsentedAt: Date?

    var documentRecordName: String {
        NFPrivateCloudRecordIdentity.document(documentID)
    }

    var assetRecordName: String {
        NFPrivateCloudRecordIdentity.asset(contentHash)
    }

    func isSemanticallyEqual(to other: Self) -> Bool {
        documentID == other.documentID
            && contentHash == other.contentHash
            && filename == other.filename
            && typeIdentifier == other.typeIdentifier
            && sizeBytes == other.sizeBytes
            && modifiedAt == other.modifiedAt
            && aiPolicyRaw == other.aiPolicyRaw
            && pccConsentPolicyVersion == other.pccConsentPolicyVersion
            && pccConsentedAt == other.pccConsentedAt
    }
}

struct NFDocumentOriginalTombstone: Codable, Equatable, Sendable {
    let documentID: UUID
    let contentHash: String?
    let deletedAt: Date

    var recordName: String {
        NFPrivateCloudRecordIdentity.tombstone(documentID)
    }
}

enum NFDocumentOriginalMergeDecision: Equatable, Sendable {
    case keepLocal
    case acceptRemote
    case deleteRemoteRevision
    case alreadyConverged
}

enum NFDocumentOriginalConflictPolicy {
    /// Latest modification wins. Equal timestamps converge by content hash,
    /// then filename and type identifier, independent of merge direction.
    static func winner(
        _ lhs: NFDocumentOriginalRevision,
        _ rhs: NFDocumentOriginalRevision
    ) -> NFDocumentOriginalRevision {
        if lhs.modifiedAt != rhs.modifiedAt {
            return lhs.modifiedAt > rhs.modifiedAt ? lhs : rhs
        }
        if lhs.contentHash != rhs.contentHash {
            return lhs.contentHash < rhs.contentHash ? lhs : rhs
        }
        if lhs.filename != rhs.filename {
            return lhs.filename < rhs.filename ? lhs : rhs
        }
        if lhs.typeIdentifier != rhs.typeIdentifier {
            return lhs.typeIdentifier < rhs.typeIdentifier ? lhs : rhs
        }
        if lhs.sizeBytes != rhs.sizeBytes {
            return lhs.sizeBytes < rhs.sizeBytes ? lhs : rhs
        }
        if lhs.aiPolicyRaw != rhs.aiPolicyRaw {
            return lhs.aiPolicyRaw < rhs.aiPolicyRaw ? lhs : rhs
        }
        if lhs.pccConsentPolicyVersion != rhs.pccConsentPolicyVersion {
            return lhs.pccConsentPolicyVersion < rhs.pccConsentPolicyVersion ? lhs : rhs
        }
        if lhs.pccConsentedAt != rhs.pccConsentedAt {
            let lhsDate = lhs.pccConsentedAt ?? .distantPast
            let rhsDate = rhs.pccConsentedAt ?? .distantPast
            return lhsDate < rhsDate ? lhs : rhs
        }
        return lhs
    }

    static func tombstoneWins(
        _ tombstone: NFDocumentOriginalTombstone,
        over revision: NFDocumentOriginalRevision
    ) -> Bool {
        tombstone.deletedAt >= revision.modifiedAt
    }
}

enum NFCloudTransportFailure: Codable, Equatable, Sendable {
    case accountUnavailable(temporary: Bool)
    case networkUnavailable(retryAfterSeconds: Double?)
    case quotaExceeded
    case serviceUnavailable(retryAfterSeconds: Double?)
    case rateLimited(retryAfterSeconds: Double?)
    case partialFailure(failedRecordNames: [String])
    case conflict
    case assetUnavailable
    case zoneUnavailable
    case permissionDenied
    case invalidLocalAsset
    case cancelled
    case unknown(redactedCode: String)

    var isRetryable: Bool {
        switch self {
        case .accountUnavailable, .networkUnavailable, .quotaExceeded,
             .serviceUnavailable, .rateLimited, .partialFailure,
             .conflict, .assetUnavailable, .zoneUnavailable:
            true
        case .permissionDenied, .invalidLocalAsset, .cancelled, .unknown:
            false
        }
    }

    var requestedRetryDelay: TimeInterval? {
        switch self {
        case let .networkUnavailable(retryAfterSeconds),
             let .serviceUnavailable(retryAfterSeconds),
             let .rateLimited(retryAfterSeconds):
            retryAfterSeconds
        case let .accountUnavailable(temporary):
            temporary ? 60 : 300
        case .quotaExceeded:
            3_600
        default:
            nil
        }
    }

    var redactedCode: String {
        switch self {
        case let .accountUnavailable(temporary): temporary ? "account-temporary" : "account-unavailable"
        case .networkUnavailable: "network-unavailable"
        case .quotaExceeded: "quota-exceeded"
        case .serviceUnavailable: "service-unavailable"
        case .rateLimited: "rate-limited"
        case .partialFailure: "partial-failure"
        case .conflict: "record-conflict"
        case .assetUnavailable: "asset-unavailable"
        case .zoneUnavailable: "zone-unavailable"
        case .permissionDenied: "permission-denied"
        case .invalidLocalAsset: "invalid-local-asset"
        case .cancelled: "cancelled"
        case let .unknown(code): code
        }
    }
}

enum NFDocumentAssetPendingOperation: String, Codable, Equatable, Sendable {
    case saveAsset
    case saveDocument
    case saveTombstone
    case deleteDocument
    case deleteAsset
    case deleteTombstone

    var priority: Int {
        switch self {
        case .saveAsset: 0
        case .saveTombstone: 1
        case .saveDocument: 2
        case .deleteDocument: 3
        case .deleteAsset: 4
        case .deleteTombstone: 5
        }
    }

    var isSave: Bool {
        switch self {
        case .saveAsset, .saveDocument, .saveTombstone: true
        case .deleteDocument, .deleteAsset, .deleteTombstone: false
        }
    }
}

struct NFDocumentAssetPendingMutation: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let operation: NFDocumentAssetPendingOperation
    let recordName: String
    let documentID: UUID?
    let contentHash: String?
    let revision: NFDocumentOriginalRevision?
    let tombstone: NFDocumentOriginalTombstone?
    var attemptCount: Int
    var notBefore: Date?
    var lastFailure: NFCloudTransportFailure?

    var isSave: Bool {
        operation.isSave
    }

    func isEligible(at date: Date) -> Bool {
        guard lastFailure?.isRetryable != false else { return false }
        return notBefore.map { $0 <= date } ?? true
    }
}

enum NFDocumentAssetStateCodingError: Error, Equatable {
    case unsupportedSchemaVersion(Int)
}

enum NFDocumentAssetApplicationStateCleanupError: Error, Equatable {
    case verificationFailed
}

struct NFDocumentAssetSyncState: Codable, Equatable, Sendable {
    static let currentSchemaVersion = 1

    var schemaVersion: Int = currentSchemaVersion
    var revisionsByDocumentID: [UUID: NFDocumentOriginalRevision] = [:]
    var tombstonesByDocumentID: [UUID: NFDocumentOriginalTombstone] = [:]
    var confirmedRemoteAssetHashes: Set<String> = []
    var downloadedAssetPathsByHash: [String: String] = [:]
    var pendingByRecordName: [String: NFDocumentAssetPendingMutation] = [:]
    var serverRecordSystemFieldsByName: [String: Data] = [:]
    var engineStateSerialization: Data?
    var lastSuccessfulSyncAt: Date?

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case revisionsByDocumentID
        case tombstonesByDocumentID
        case confirmedRemoteAssetHashes
        case downloadedAssetPathsByHash
        case pendingByRecordName
        case serverRecordSystemFieldsByName
        case engineStateSerialization
        case lastSuccessfulSyncAt
    }

    init() {}

    init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let decodedVersion = try values.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 0
        guard decodedVersion <= Self.currentSchemaVersion else {
            throw NFDocumentAssetStateCodingError.unsupportedSchemaVersion(decodedVersion)
        }
        schemaVersion = Self.currentSchemaVersion
        revisionsByDocumentID = try values.decodeIfPresent(
            [UUID: NFDocumentOriginalRevision].self,
            forKey: .revisionsByDocumentID
        ) ?? [:]
        tombstonesByDocumentID = try values.decodeIfPresent(
            [UUID: NFDocumentOriginalTombstone].self,
            forKey: .tombstonesByDocumentID
        ) ?? [:]
        confirmedRemoteAssetHashes = try values.decodeIfPresent(
            Set<String>.self,
            forKey: .confirmedRemoteAssetHashes
        ) ?? []
        downloadedAssetPathsByHash = try values.decodeIfPresent(
            [String: String].self,
            forKey: .downloadedAssetPathsByHash
        ) ?? [:]
        pendingByRecordName = try values.decodeIfPresent(
            [String: NFDocumentAssetPendingMutation].self,
            forKey: .pendingByRecordName
        ) ?? [:]
        serverRecordSystemFieldsByName = try values.decodeIfPresent(
            [String: Data].self,
            forKey: .serverRecordSystemFieldsByName
        ) ?? [:]
        engineStateSerialization = try values.decodeIfPresent(
            Data.self,
            forKey: .engineStateSerialization
        )
        lastSuccessfulSyncAt = try values.decodeIfPresent(
            Date.self,
            forKey: .lastSuccessfulSyncAt
        )
    }

    func encode(to encoder: any Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(Self.currentSchemaVersion, forKey: .schemaVersion)
        try values.encode(revisionsByDocumentID, forKey: .revisionsByDocumentID)
        try values.encode(tombstonesByDocumentID, forKey: .tombstonesByDocumentID)
        try values.encode(confirmedRemoteAssetHashes, forKey: .confirmedRemoteAssetHashes)
        try values.encode(downloadedAssetPathsByHash, forKey: .downloadedAssetPathsByHash)
        try values.encode(pendingByRecordName, forKey: .pendingByRecordName)
        try values.encode(serverRecordSystemFieldsByName, forKey: .serverRecordSystemFieldsByName)
        try values.encodeIfPresent(engineStateSerialization, forKey: .engineStateSerialization)
        try values.encodeIfPresent(lastSuccessfulSyncAt, forKey: .lastSuccessfulSyncAt)
    }
}

struct NFDocumentAssetQueueSnapshot: Codable, Equatable, Sendable {
    let revisions: [NFDocumentOriginalRevision]
    let tombstones: [NFDocumentOriginalTombstone]
    let pending: [NFDocumentAssetPendingMutation]
    let confirmedRemoteAssetHashes: Set<String>
    let downloadedAssetPathsByHash: [String: String]
    let engineStateSerialization: Data?
    let lastSuccessfulSyncAt: Date?

    var metrics: NFSyncQueueMetrics {
        NFSyncQueueMetrics(
            pendingRecordCount: pending.filter {
                $0.operation != .saveAsset && $0.operation != .deleteAsset
            }.count,
            pendingAssetCount: pending.filter {
                $0.operation == .saveAsset || $0.operation == .deleteAsset
            }.count
        )
    }
}

protocol NFDocumentAssetSyncStateStore: Sendable {
    func load() async throws -> NFDocumentAssetSyncState?
    func save(_ state: NFDocumentAssetSyncState) async throws
    func reset() async throws
}

actor NFInMemoryDocumentAssetSyncStateStore: NFDocumentAssetSyncStateStore {
    private var state: NFDocumentAssetSyncState?

    init(state: NFDocumentAssetSyncState? = nil) {
        self.state = state
    }

    func load() -> NFDocumentAssetSyncState? { state }
    func save(_ state: NFDocumentAssetSyncState) { self.state = state }
    func reset() { state = nil }
}

actor NFFileDocumentAssetSyncStateStore: NFDocumentAssetSyncStateStore {
    struct ApplicationStorageLocations: Equatable, Sendable {
        let stateURL: URL
        let receivedAssetRootURL: URL
    }

    static let legacyAccountClaimKey = "nf.private-sync.document-assets-legacy-claim.v1"

    let fileURL: URL

    init(fileURL: URL) {
        self.fileURL = fileURL
    }

    static func applicationStoreURL(
        fileManager: FileManager = .default,
        defaults: UserDefaults = .standard,
        applicationSupportURL: URL? = nil
    ) throws -> URL {
        try applicationStorageLocations(
            fileManager: fileManager,
            defaults: defaults,
            applicationSupportURL: applicationSupportURL
        ).stateURL
    }

    static func applicationStorageLocations(
        fileManager: FileManager = .default,
        defaults: UserDefaults = .standard,
        applicationSupportURL: URL? = nil
    ) throws -> ApplicationStorageLocations {
        let support = if let applicationSupportURL {
            applicationSupportURL
        } else {
            try fileManager.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
        }
        let legacyStateURL = support
            .appending(path: "NeuroForge/Sync", directoryHint: .isDirectory)
            .appending(path: "private-document-assets.json", directoryHint: .notDirectory)
        let legacyAssetRoot = support.appending(
            path: "NeuroForge/CloudAssets",
            directoryHint: .isDirectory
        )
        guard let namespace = NFPrivateCloudStoreIdentityResolver.activeNamespace(
            defaults: defaults
        ) else {
            return ApplicationStorageLocations(
                stateURL: legacyStateURL,
                receivedAssetRootURL: legacyAssetRoot
            )
        }

        let accountStateURL = support
            .appending(path: "NeuroForge/Sync/Accounts", directoryHint: .isDirectory)
            .appending(path: namespace, directoryHint: .isDirectory)
            .appending(path: "private-document-assets.json", directoryHint: .notDirectory)
        let accountAssetRoot = support
            .appending(path: "NeuroForge/CloudAssetAccounts", directoryHint: .isDirectory)
            .appending(path: namespace, directoryHint: .isDirectory)
        try fileManager.createDirectory(
            at: accountStateURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try fileManager.createDirectory(
            at: accountAssetRoot.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try claimLegacyApplicationStateIfNeeded(
            namespace: namespace,
            legacyStateURL: legacyStateURL,
            legacyAssetRoot: legacyAssetRoot,
            accountStateURL: accountStateURL,
            accountAssetRoot: accountAssetRoot,
            fileManager: fileManager,
            defaults: defaults
        )
        return ApplicationStorageLocations(
            stateURL: accountStateURL,
            receivedAssetRootURL: accountAssetRoot
        )
    }

    /// Removes only the custom document-original transport's application-wide
    /// state: the legacy queue/cache and every account-namespaced queue/cache.
    /// The caller must first stop the active adapter so its in-memory queue can
    /// never write one of these files back after deletion is verified.
    static func purgeAllApplicationState(
        fileManager: FileManager = .default,
        defaults: UserDefaults = .standard,
        applicationSupportURL: URL? = nil
    ) throws {
        let targets = try applicationStatePurgeTargets(
            fileManager: fileManager,
            applicationSupportURL: applicationSupportURL
        )
        for target in targets where applicationStateItemExists(
            at: target,
            fileManager: fileManager
        ) {
            try fileManager.removeItem(at: target)
        }
        guard targets.allSatisfy({
            !applicationStateItemExists(at: $0, fileManager: fileManager)
        }) else {
            throw NFDocumentAssetApplicationStateCleanupError.verificationFailed
        }
        // A later, genuinely fresh installation state must not inherit a claim
        // marker whose queue and cache have just been verified absent.
        defaults.removeObject(forKey: legacyAccountClaimKey)
    }

    func load() throws -> NFDocumentAssetSyncState? {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: fileURL.path) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(
            NFDocumentAssetSyncState.self,
            from: Data(contentsOf: fileURL, options: [.mappedIfSafe])
        )
    }

    func save(_ state: NFDocumentAssetSyncState) throws {
        let fileManager = FileManager.default
        let folder = fileURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(state).write(to: fileURL, options: [.atomic, .completeFileProtection])
        try? fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
    }

    func reset() throws {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: fileURL.path) else { return }
        try fileManager.removeItem(at: fileURL)
    }

    private static func claimLegacyApplicationStateIfNeeded(
        namespace: String,
        legacyStateURL: URL,
        legacyAssetRoot: URL,
        accountStateURL: URL,
        accountAssetRoot: URL,
        fileManager: FileManager,
        defaults: UserDefaults
    ) throws {
        if defaults.string(forKey: legacyAccountClaimKey) != nil { return }
        guard NFPrivateCloudStoreIdentityResolver.canClaimLegacyDocumentAssetState(
            namespace: namespace,
            defaults: defaults
        ) else {
            return
        }

        if fileManager.fileExists(atPath: legacyAssetRoot.path) {
            try fileManager.createDirectory(
                at: accountAssetRoot,
                withIntermediateDirectories: true
            )
            for sourceURL in try fileManager.contentsOfDirectory(
                at: legacyAssetRoot,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            ) {
                let hash = sourceURL.lastPathComponent
                guard NFContentAddressedAssetHasher.isValidSHA256(hash),
                      try NFContentAddressedAssetHasher.sha256(fileURL: sourceURL) == hash else {
                    continue
                }
                let destination = accountAssetRoot.appending(
                    path: hash,
                    directoryHint: .notDirectory
                )
                if !fileManager.fileExists(atPath: destination.path) {
                    try fileManager.copyItem(at: sourceURL, to: destination)
                    try? fileManager.setAttributes(
                        [.posixPermissions: 0o600],
                        ofItemAtPath: destination.path
                    )
                }
            }
        }

        if fileManager.fileExists(atPath: legacyStateURL.path),
           !fileManager.fileExists(atPath: accountStateURL.path) {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            var state = try decoder.decode(
                NFDocumentAssetSyncState.self,
                from: Data(contentsOf: legacyStateURL, options: [.mappedIfSafe])
            )
            for (hash, path) in state.downloadedAssetPathsByHash {
                let legacyPath = legacyAssetRoot.appending(
                    path: hash,
                    directoryHint: .notDirectory
                ).standardizedFileURL.path
                let accountPath = accountAssetRoot.appending(
                    path: hash,
                    directoryHint: .notDirectory
                ).standardizedFileURL.path
                guard URL(fileURLWithPath: path).standardizedFileURL.path == legacyPath,
                      fileManager.fileExists(atPath: accountPath) else {
                    continue
                }
                state.downloadedAssetPathsByHash[hash] = accountPath
                for (documentID, revision) in state.revisionsByDocumentID
                where revision.contentHash == hash
                    && URL(fileURLWithPath: revision.localFilePath).standardizedFileURL.path == legacyPath {
                    state.revisionsByDocumentID[documentID] = NFDocumentOriginalRevision(
                        documentID: revision.documentID,
                        contentHash: revision.contentHash,
                        filename: revision.filename,
                        typeIdentifier: revision.typeIdentifier,
                        sizeBytes: revision.sizeBytes,
                        localFilePath: accountPath,
                        modifiedAt: revision.modifiedAt,
                        aiPolicyRaw: revision.aiPolicyRaw,
                        pccConsentPolicyVersion: revision.pccConsentPolicyVersion,
                        pccConsentedAt: revision.pccConsentedAt
                    )
                }
            }
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.sortedKeys]
            try encoder.encode(state).write(
                to: accountStateURL,
                options: [.atomic, .completeFileProtection]
            )
            try? fileManager.setAttributes(
                [.posixPermissions: 0o600],
                ofItemAtPath: accountStateURL.path
            )
        }

        // The legacy source is intentionally preserved as a recovery copy. The
        // marker is written only after every requested copy and rewrite succeeds.
        defaults.set(namespace, forKey: legacyAccountClaimKey)
    }

    private static func applicationStatePurgeTargets(
        fileManager: FileManager,
        applicationSupportURL: URL?
    ) throws -> [URL] {
        let support = if let applicationSupportURL {
            applicationSupportURL
        } else {
            try fileManager.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
        }
        return [
            support
                .appending(path: "NeuroForge/Sync", directoryHint: .isDirectory)
                .appending(
                    path: "private-document-assets.json",
                    directoryHint: .notDirectory
                ),
            support.appending(
                path: "NeuroForge/Sync/Accounts",
                directoryHint: .isDirectory
            ),
            support.appending(
                path: "NeuroForge/CloudAssets",
                directoryHint: .isDirectory
            ),
            support.appending(
                path: "NeuroForge/CloudAssetAccounts",
                directoryHint: .isDirectory
            )
        ]
    }

    private static func applicationStateItemExists(
        at url: URL,
        fileManager: FileManager
    ) -> Bool {
        fileManager.fileExists(atPath: url.path)
            || (try? fileManager.destinationOfSymbolicLink(atPath: url.path)) != nil
    }
}

enum NFDocumentAssetIntegrityError: Error, Equatable {
    case unreadableFile
    case contentHashMismatch
    case invalidContentHash
}

enum NFContentAddressedAssetHasher {
    static func sha256(
        fileURL: URL,
        checkingCancellation: Bool = false
    ) throws -> String {
        if checkingCancellation { try Task.checkCancellation() }
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            throw NFDocumentAssetIntegrityError.unreadableFile
        }
        let handle = try FileHandle(forReadingFrom: fileURL)
        defer { try? handle.close() }
        var hasher = SHA256()
        while true {
            if checkingCancellation { try Task.checkCancellation() }
            let data = try handle.read(upToCount: 1_024 * 1_024) ?? Data()
            guard !data.isEmpty else { break }
            hasher.update(data: data)
        }
        if checkingCancellation { try Task.checkCancellation() }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    static func isValidSHA256(_ value: String) -> Bool {
        value.count == 64 && value.allSatisfy { $0.isHexDigit && !$0.isUppercase }
    }
}

enum NFPrivateCloudRecordIdentity {
    static func asset(_ contentHash: String) -> String { "asset-\(contentHash)" }
    static func document(_ id: UUID) -> String { "document-\(id.uuidString.lowercased())" }
    static func tombstone(_ id: UUID) -> String { "tombstone-\(id.uuidString.lowercased())" }
}

actor NFDocumentAssetMutationQueue {
    private let store: any NFDocumentAssetSyncStateStore
    private var state = NFDocumentAssetSyncState()
    private var hasLoaded = false

    init(store: any NFDocumentAssetSyncStateStore) {
        self.store = store
    }

    @discardableResult
    func enqueueUpsert(_ input: NFDocumentOriginalInput) async throws -> NFDocumentOriginalRevision {
        try await ensureLoaded()
        let hash = try NFContentAddressedAssetHasher.sha256(fileURL: input.localURL)
        let values = try input.localURL.resourceValues(forKeys: [.fileSizeKey])
        let revision = NFDocumentOriginalRevision(
            documentID: input.documentID,
            contentHash: hash,
            filename: input.filename,
            typeIdentifier: input.typeIdentifier,
            sizeBytes: Int64(values.fileSize ?? 0),
            localFilePath: input.localURL.path,
            modifiedAt: input.modifiedAt,
            aiPolicyRaw: input.aiPolicyRaw,
            pccConsentPolicyVersion: input.pccConsentPolicyVersion,
            pccConsentedAt: input.pccConsentedAt
        )

        if let tombstone = state.tombstonesByDocumentID[input.documentID] {
            guard !NFDocumentOriginalConflictPolicy.tombstoneWins(tombstone, over: revision) else {
                return revision
            }
            state.tombstonesByDocumentID[input.documentID] = nil
            enqueueDeleteTombstone(tombstone)
        }

        let prior = state.revisionsByDocumentID.updateValue(revision, forKey: input.documentID)
        if let prior, prior.isSemanticallyEqual(to: revision) {
            // A received revision is materialized at a different device-local
            // path. Updating that path must not turn a converged remote record
            // into a fresh save on every foreground reconciliation.
            enqueueSaveAssetIfNeeded(revision)
            try await persist()
            return revision
        }
        if let prior, prior.contentHash != revision.contentHash {
            removeOrDeleteUnreferencedAsset(prior.contentHash)
        }
        enqueueSaveAssetIfNeeded(revision)
        put(makeSaveDocument(revision))
        try await persist()
        return revision
    }

    func reconcile(_ inputs: [NFDocumentOriginalInput]) async throws {
        try await ensureLoaded()
        // Hashing is intentionally performed on this transport actor after the
        // local SwiftData save; callers never await this from a training write.
        for input in inputs.sorted(by: inputOrder) {
            _ = try await enqueueUpsert(input)
        }
    }

    func enqueueDelete(documentID: UUID, deletedAt: Date = Date()) async throws {
        try await ensureLoaded()
        enqueueDeleteLoaded(documentID: documentID, deletedAt: deletedAt)
        try await persist()
    }

    func snapshot(now: Date = Date(), eligibleOnly: Bool = false) async throws -> NFDocumentAssetQueueSnapshot {
        try await ensureLoaded()
        let pending = state.pendingByRecordName.values
            .filter {
                !eligibleOnly
                    || ($0.isEligible(at: now) && dependenciesAreSatisfied(for: $0))
            }
            .sorted(by: pendingOrder)
        return NFDocumentAssetQueueSnapshot(
            revisions: state.revisionsByDocumentID.values.sorted(by: revisionOrder),
            tombstones: state.tombstonesByDocumentID.values.sorted(by: tombstoneOrder),
            pending: pending,
            confirmedRemoteAssetHashes: state.confirmedRemoteAssetHashes,
            downloadedAssetPathsByHash: state.downloadedAssetPathsByHash,
            engineStateSerialization: state.engineStateSerialization,
            lastSuccessfulSyncAt: state.lastSuccessfulSyncAt
        )
    }

    func pendingMutation(recordName: String) async throws -> NFDocumentAssetPendingMutation? {
        try await ensureLoaded()
        return state.pendingByRecordName[recordName]
    }

    func acknowledge(
        recordName: String,
        completedOperation: NFDocumentAssetPendingOperation? = nil,
        at date: Date = Date()
    ) async throws {
        try await ensureLoaded()
        guard let mutation = state.pendingByRecordName[recordName] else {
            if let completedOperation, !completedOperation.isSave,
               recoverFromObservedStaleDeletion(recordName: recordName) {
                try await persist()
            }
            return
        }
        // A record name is intentionally stable across saves and deletes. A
        // delayed save completion must never consume a newer delete mutation
        // (or vice versa), even after that delete's tombstone is acknowledged.
        if let completedOperation, completedOperation != mutation.operation {
            if !completedOperation.isSave,
               recoverFromObservedStaleDeletion(recordName: recordName) {
                try await persist()
            }
            return
        }
        // CKSyncEngine can deliver completion events from work prepared before
        // the current process launch. Do not let one of those callbacks advance
        // a destructive chain out of order. Keeping the mutation makes the
        // eventual retry idempotent after its prerequisite is acknowledged.
        guard dependenciesAreSatisfied(for: mutation) else { return }
        state.pendingByRecordName[recordName] = nil
        switch mutation.operation {
        case .saveAsset:
            if let hash = mutation.contentHash { state.confirmedRemoteAssetHashes.insert(hash) }
        case .deleteAsset:
            if let hash = mutation.contentHash {
                state.confirmedRemoteAssetHashes.remove(hash)
                state.downloadedAssetPathsByHash[hash] = nil
            }
        case .deleteTombstone:
            if let documentID = mutation.documentID {
                state.tombstonesByDocumentID[documentID] = nil
            }
        case .saveDocument, .saveTombstone, .deleteDocument:
            break
        }
        if !mutation.isSave { state.serverRecordSystemFieldsByName[recordName] = nil }
        if state.pendingByRecordName.isEmpty { state.lastSuccessfulSyncAt = date }
        try await persist()
    }

    func recordFailure(
        recordName: String,
        failure: NFCloudTransportFailure,
        now: Date = Date()
    ) async throws {
        try await ensureLoaded()
        guard var mutation = state.pendingByRecordName[recordName] else { return }
        mutation.attemptCount += 1
        mutation.lastFailure = failure
        if failure.isRetryable {
            let requested = max(1, failure.requestedRetryDelay ?? 0)
            let exponential = min(6 * 60 * 60, pow(2, Double(min(mutation.attemptCount, 12))))
            mutation.notBefore = now.addingTimeInterval(max(requested, exponential))
        } else {
            mutation.notBefore = nil
        }
        state.pendingByRecordName[recordName] = mutation
        try await persist()
    }

    func applyRemoteRevision(_ remote: NFDocumentOriginalRevision) async throws -> NFDocumentOriginalMergeDecision {
        try await ensureLoaded()
        if let tombstone = state.tombstonesByDocumentID[remote.documentID] {
            if NFDocumentOriginalConflictPolicy.tombstoneWins(tombstone, over: remote) {
                put(makeDeleteDocument(documentID: remote.documentID))
                try await persist()
                return .deleteRemoteRevision
            }
            // A genuinely newer revision supersedes the durable deletion. Stop
            // publishing the stale tombstone immediately so the local mirror
            // cannot report both a live document and a deletion for one domain
            // identity while the tombstone removal is in flight.
            state.tombstonesByDocumentID[remote.documentID] = nil
            enqueueDeleteTombstone(tombstone)
        }
        guard let local = state.revisionsByDocumentID[remote.documentID] else {
            state.revisionsByDocumentID[remote.documentID] = remote
            try await persist()
            return .acceptRemote
        }
        guard !local.isSemanticallyEqual(to: remote) else {
            state.pendingByRecordName[remote.documentRecordName] = nil
            try await persist()
            return .alreadyConverged
        }

        let winner = NFDocumentOriginalConflictPolicy.winner(local, remote)
        if winner == local {
            enqueueSaveAssetIfNeeded(local)
            put(makeSaveDocument(local))
            try await persist()
            return .keepLocal
        }
        state.revisionsByDocumentID[remote.documentID] = remote
        state.pendingByRecordName[remote.documentRecordName] = nil
        removeOrDeleteUnreferencedAsset(local.contentHash)
        try await persist()
        return .acceptRemote
    }

    func applyRemoteTombstone(_ remote: NFDocumentOriginalTombstone) async throws -> NFDocumentOriginalMergeDecision {
        try await ensureLoaded()
        if let local = state.revisionsByDocumentID[remote.documentID],
           !NFDocumentOriginalConflictPolicy.tombstoneWins(remote, over: local) {
            enqueueSaveAssetIfNeeded(local)
            put(makeSaveDocument(local))
            enqueueDeleteTombstone(remote)
            try await persist()
            return .keepLocal
        }
        if let local = state.revisionsByDocumentID.removeValue(forKey: remote.documentID) {
            removeOrDeleteUnreferencedAsset(local.contentHash)
        }
        state.tombstonesByDocumentID[remote.documentID] = remote
        state.pendingByRecordName[remote.recordName] = nil
        put(makeDeleteDocument(documentID: remote.documentID))
        try await persist()
        return .acceptRemote
    }

    func acceptDownloadedAsset(hash: String, localURL: URL) async throws {
        try await ensureLoaded()
        guard NFContentAddressedAssetHasher.isValidSHA256(hash) else {
            throw NFDocumentAssetIntegrityError.invalidContentHash
        }
        guard try NFContentAddressedAssetHasher.sha256(fileURL: localURL) == hash else {
            throw NFDocumentAssetIntegrityError.contentHashMismatch
        }
        state.confirmedRemoteAssetHashes.insert(hash)
        state.downloadedAssetPathsByHash[hash] = localURL.path
        let assetRecordName = NFPrivateCloudRecordIdentity.asset(hash)
        if state.pendingByRecordName[assetRecordName]?.operation == .saveAsset {
            state.pendingByRecordName[assetRecordName] = nil
        }
        for (documentID, revision) in state.revisionsByDocumentID where revision.contentHash == hash {
            state.revisionsByDocumentID[documentID] = revisionWithLocalPath(
                revision,
                localFilePath: localURL.path
            )
        }
        try await persist()
    }

    func recoverFromZoneLoss() async throws {
        try await ensureLoaded()
        state.confirmedRemoteAssetHashes.removeAll()
        // Change tags and other server system fields belong to the deleted
        // zone incarnation and cannot safely seed records in the replacement.
        state.serverRecordSystemFieldsByName.removeAll()
        for revision in state.revisionsByDocumentID.values {
            enqueueSaveAssetIfNeeded(revision)
            put(makeSaveDocument(revision))
        }
        for tombstone in state.tombstonesByDocumentID.values {
            put(makeSaveTombstone(tombstone))
        }
        try await persist()
    }

    /// Removes every piece of state that is scoped to the prior CloudKit
    /// account while preserving device-local originals. Pending deletions and
    /// tombstones must not cross an account boundary. Live revisions are
    /// rebuilt as fresh saves, but the adapter will not offer them to
    /// CKSyncEngine until the user has explicitly opted in again and relaunched.
    func prepareForAccountSwitch() async throws {
        try await ensureLoaded()
        state.engineStateSerialization = nil
        state.serverRecordSystemFieldsByName.removeAll()
        state.confirmedRemoteAssetHashes.removeAll()
        state.downloadedAssetPathsByHash.removeAll()
        state.pendingByRecordName.removeAll()
        state.tombstonesByDocumentID.removeAll()
        state.lastSuccessfulSyncAt = nil
        for revision in state.revisionsByDocumentID.values {
            enqueueSaveAssetIfNeeded(revision)
            put(makeSaveDocument(revision))
        }
        try await persist()
    }

    func remoteRecordWasDeleted(recordName: String) async throws {
        try await ensureLoaded()
        if recordName.hasPrefix("asset-") {
            let hash = String(recordName.dropFirst("asset-".count))
            state.confirmedRemoteAssetHashes.remove(hash)
            state.downloadedAssetPathsByHash[hash] = nil
            if let revision = state.revisionsByDocumentID.values.first(where: { $0.contentHash == hash }) {
                enqueueSaveAssetIfNeeded(revision)
            }
        } else if recordName.hasPrefix("document-"),
                  let revision = state.revisionsByDocumentID.values.first(where: { $0.documentRecordName == recordName }),
                  state.tombstonesByDocumentID[revision.documentID] == nil {
            enqueueSaveAssetIfNeeded(revision)
            put(makeSaveDocument(revision))
        }
        try await persist()
    }

    func replaceEngineStateSerialization(_ data: Data?) async throws {
        try await ensureLoaded()
        state.engineStateSerialization = data
        try await persist()
    }

    func recordServerSystemFields(recordName: String, data: Data) async throws {
        try await ensureLoaded()
        state.serverRecordSystemFieldsByName[recordName] = data
        try await persist()
    }

    func serverSystemFields(recordName: String) async throws -> Data? {
        try await ensureLoaded()
        return state.serverRecordSystemFieldsByName[recordName]
    }

    func markSyncPassSuccessful(at date: Date = Date()) async throws {
        try await ensureLoaded()
        state.lastSuccessfulSyncAt = date
        try await persist()
    }

    func resetLocalStatePreservingRemote() async throws {
        state = NFDocumentAssetSyncState()
        hasLoaded = true
        try await store.reset()
    }

    private func ensureLoaded() async throws {
        guard !hasLoaded else { return }
        state = try await store.load() ?? NFDocumentAssetSyncState()
        hasLoaded = true
    }

    private func persist() async throws {
        try await store.save(state)
    }

    private func revisionWithLocalPath(
        _ revision: NFDocumentOriginalRevision,
        localFilePath: String
    ) -> NFDocumentOriginalRevision {
        NFDocumentOriginalRevision(
            documentID: revision.documentID,
            contentHash: revision.contentHash,
            filename: revision.filename,
            typeIdentifier: revision.typeIdentifier,
            sizeBytes: revision.sizeBytes,
            localFilePath: localFilePath,
            modifiedAt: revision.modifiedAt,
            aiPolicyRaw: revision.aiPolicyRaw,
            pccConsentPolicyVersion: revision.pccConsentPolicyVersion,
            pccConsentedAt: revision.pccConsentedAt
        )
    }

    private func enqueueDeleteLoaded(documentID: UUID, deletedAt: Date) {
        let prior = state.revisionsByDocumentID.removeValue(forKey: documentID)
        let tombstone = NFDocumentOriginalTombstone(
            documentID: documentID,
            contentHash: prior?.contentHash,
            deletedAt: deletedAt
        )
        state.tombstonesByDocumentID[documentID] = tombstone
        put(makeSaveTombstone(tombstone))
        put(makeDeleteDocument(documentID: documentID))
        if let prior { removeOrDeleteUnreferencedAsset(prior.contentHash) }
    }

    private func enqueueSaveAssetIfNeeded(_ revision: NFDocumentOriginalRevision) {
        let recordName = revision.assetRecordName
        if state.confirmedRemoteAssetHashes.contains(revision.contentHash) {
            // A new local reference can appear while deletion of the previously
            // last reference is queued. Cancelling that unsent deletion is the
            // only safe ordering; otherwise one non-atomic batch could save the
            // new document and remove its content-addressed asset.
            if state.pendingByRecordName[recordName]?.operation == .deleteAsset {
                state.pendingByRecordName[recordName] = nil
            }
            return
        }
        let mutation = NFDocumentAssetPendingMutation(
            id: recordName,
            operation: .saveAsset,
            recordName: recordName,
            documentID: nil,
            contentHash: revision.contentHash,
            revision: revision,
            tombstone: nil,
            attemptCount: 0,
            notBefore: nil,
            lastFailure: nil
        )
        if state.pendingByRecordName[mutation.recordName]?.operation != .saveAsset {
            put(mutation)
        }
    }

    private func removeOrDeleteUnreferencedAsset(_ hash: String) {
        guard !state.revisionsByDocumentID.values.contains(where: { $0.contentHash == hash }) else { return }
        let recordName = NFPrivateCloudRecordIdentity.asset(hash)
        if state.confirmedRemoteAssetHashes.contains(hash) {
            put(NFDocumentAssetPendingMutation(
                id: recordName,
                operation: .deleteAsset,
                recordName: recordName,
                documentID: nil,
                contentHash: hash,
                revision: nil,
                tombstone: nil,
                attemptCount: 0,
                notBefore: nil,
                lastFailure: nil
            ))
        } else {
            state.pendingByRecordName[recordName] = nil
        }
    }

    /// A deletion completion can arrive after a new local mutation replaced or
    /// cancelled the operation that originally produced it. Treat the server's
    /// now-absent record as authoritative transport state and rebuild any live
    /// record, rather than letting a stale callback create a dangling reference.
    private func recoverFromObservedStaleDeletion(recordName: String) -> Bool {
        state.serverRecordSystemFieldsByName[recordName] = nil
        if recordName.hasPrefix("asset-") {
            let hash = String(recordName.dropFirst("asset-".count))
            guard NFContentAddressedAssetHasher.isValidSHA256(hash) else { return false }
            state.confirmedRemoteAssetHashes.remove(hash)
            state.downloadedAssetPathsByHash[hash] = nil
            for revision in state.revisionsByDocumentID.values
            where revision.contentHash == hash {
                enqueueSaveAssetIfNeeded(revision)
            }
            return true
        }
        if recordName.hasPrefix("document-"),
           let revision = state.revisionsByDocumentID.values.first(where: {
               $0.documentRecordName == recordName
           }),
           state.tombstonesByDocumentID[revision.documentID] == nil {
            enqueueSaveAssetIfNeeded(revision)
            put(makeSaveDocument(revision))
            return true
        }
        if recordName.hasPrefix("tombstone-"),
           let tombstone = state.tombstonesByDocumentID.values.first(where: {
               $0.recordName == recordName
           }) {
            put(makeSaveTombstone(tombstone))
            return true
        }
        return false
    }

    private func enqueueDeleteTombstone(_ tombstone: NFDocumentOriginalTombstone) {
        put(NFDocumentAssetPendingMutation(
            id: tombstone.recordName,
            operation: .deleteTombstone,
            recordName: tombstone.recordName,
            documentID: tombstone.documentID,
            contentHash: tombstone.contentHash,
            revision: nil,
            tombstone: tombstone,
            attemptCount: 0,
            notBefore: nil,
            lastFailure: nil
        ))
    }

    private func makeSaveDocument(_ revision: NFDocumentOriginalRevision) -> NFDocumentAssetPendingMutation {
        NFDocumentAssetPendingMutation(
            id: revision.documentRecordName,
            operation: .saveDocument,
            recordName: revision.documentRecordName,
            documentID: revision.documentID,
            contentHash: revision.contentHash,
            revision: revision,
            tombstone: nil,
            attemptCount: 0,
            notBefore: nil,
            lastFailure: nil
        )
    }

    private func makeSaveTombstone(_ tombstone: NFDocumentOriginalTombstone) -> NFDocumentAssetPendingMutation {
        NFDocumentAssetPendingMutation(
            id: tombstone.recordName,
            operation: .saveTombstone,
            recordName: tombstone.recordName,
            documentID: tombstone.documentID,
            contentHash: tombstone.contentHash,
            revision: nil,
            tombstone: tombstone,
            attemptCount: 0,
            notBefore: nil,
            lastFailure: nil
        )
    }

    private func makeDeleteDocument(documentID: UUID) -> NFDocumentAssetPendingMutation {
        let recordName = NFPrivateCloudRecordIdentity.document(documentID)
        return NFDocumentAssetPendingMutation(
            id: recordName,
            operation: .deleteDocument,
            recordName: recordName,
            documentID: documentID,
            contentHash: nil,
            revision: nil,
            tombstone: nil,
            attemptCount: 0,
            notBefore: nil,
            lastFailure: nil
        )
    }

    private func put(_ mutation: NFDocumentAssetPendingMutation) {
        state.pendingByRecordName[mutation.recordName] = mutation
    }

    /// Destructive records are deliberately offered in separate CloudKit
    /// batches. `atomicByZone` is false because assets can be large, so numeric
    /// priority alone cannot establish safety when a partial batch fails.
    private func dependenciesAreSatisfied(
        for mutation: NFDocumentAssetPendingMutation
    ) -> Bool {
        switch mutation.operation {
        case .saveDocument:
            guard let revision = mutation.revision else { return false }
            let assetRecordName = NFPrivateCloudRecordIdentity.asset(revision.contentHash)
            return state.confirmedRemoteAssetHashes.contains(revision.contentHash)
                && state.pendingByRecordName[assetRecordName]?.operation != .saveAsset

        case .deleteDocument:
            guard let documentID = mutation.documentID,
                  state.tombstonesByDocumentID[documentID] != nil else {
                return false
            }
            let tombstoneRecordName = NFPrivateCloudRecordIdentity.tombstone(documentID)
            return state.pendingByRecordName[tombstoneRecordName]?.operation != .saveTombstone

        case .deleteAsset:
            guard let hash = mutation.contentHash else { return false }
            // Never remove an asset while any live document references it.
            guard !state.revisionsByDocumentID.values.contains(where: {
                $0.contentHash == hash
            }) else {
                return false
            }
            // Every deleted document that referenced this asset must first have
            // a durable tombstone and an acknowledged document deletion. This
            // keeps a stale device from resurrecting a dangling document after
            // a partially successful non-atomic batch.
            for tombstone in state.tombstonesByDocumentID.values
            where tombstone.contentHash == hash {
                let tombstoneRecordName = tombstone.recordName
                if state.pendingByRecordName[tombstoneRecordName]?.operation == .saveTombstone {
                    return false
                }
                let documentRecordName = NFPrivateCloudRecordIdentity.document(
                    tombstone.documentID
                )
                if state.pendingByRecordName[documentRecordName]?.operation == .deleteDocument {
                    return false
                }
            }
            return true

        case .deleteTombstone:
            guard let documentID = mutation.documentID,
                  let revision = state.revisionsByDocumentID[documentID] else {
                return false
            }
            let documentRecordName = NFPrivateCloudRecordIdentity.document(documentID)
            let assetRecordName = NFPrivateCloudRecordIdentity.asset(revision.contentHash)
            return state.pendingByRecordName[documentRecordName]?.operation != .saveDocument
                && state.pendingByRecordName[assetRecordName]?.operation != .saveAsset
                && state.confirmedRemoteAssetHashes.contains(revision.contentHash)

        case .saveAsset, .saveTombstone:
            return true
        }
    }

    private func pendingOrder(_ lhs: NFDocumentAssetPendingMutation, _ rhs: NFDocumentAssetPendingMutation) -> Bool {
        if lhs.operation.priority != rhs.operation.priority {
            return lhs.operation.priority < rhs.operation.priority
        }
        return lhs.recordName < rhs.recordName
    }

    private func revisionOrder(_ lhs: NFDocumentOriginalRevision, _ rhs: NFDocumentOriginalRevision) -> Bool {
        uuidOrder(lhs.documentID, rhs.documentID)
    }

    private func tombstoneOrder(_ lhs: NFDocumentOriginalTombstone, _ rhs: NFDocumentOriginalTombstone) -> Bool {
        uuidOrder(lhs.documentID, rhs.documentID)
    }

    private func inputOrder(_ lhs: NFDocumentOriginalInput, _ rhs: NFDocumentOriginalInput) -> Bool {
        uuidOrder(lhs.documentID, rhs.documentID)
    }

    private func uuidOrder(_ lhs: UUID, _ rhs: UUID) -> Bool {
        lhs.uuidString < rhs.uuidString
    }
}

import Foundation
import SwiftData

/// The shipped local-store schema is explicitly versioned from the first
/// release. Future releases append a VersionedSchema type and a migration stage
/// instead of asking SwiftData to infer an untracked production migration.
enum NFSchemaV1: VersionedSchema {
    static let versionIdentifier = Schema.Version(1, 0, 0)

    static var models: [any PersistentModel.Type] {
        [
            UserProfileRecord.self,
            InputCalibrationRecord.self,
            ProgressAnnotationRecord.self,
            AttemptRecord.self,
            AttemptReflectionRecord.self,
            SourceDocumentRecord.self,
            SourceChunkRecord.self,
            AIGenerationRecord.self,
            WeeklyTransferStateRecord.self,
            ReassessmentStateRecord.self,
            SessionCheckpointRecord.self,
            DailyPlanRecord.self,
            ItemReportRecord.self
        ]
    }
}

enum NFSchemaMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] { [NFSchemaV1.self] }
    static var stages: [MigrationStage] { [] }
}

struct NFCloudStoreBootstrapResult<Store> {
    let store: Store
    let activePrivateCloudConfiguration: NFPrivateCloudRuntimeConfiguration?
    let usedLocalFallback: Bool
}

enum NFPrivateCloudStartupTransition: String, Codable, Equatable, Sendable {
    case none
    case noAccount
    case restricted
    case temporarilyUnavailable
    case accountStatusUnavailable
    case accountChanged
    case legacyClaimFailed
    case identityStateUnavailable

    var requiresUserAttention: Bool {
        switch self {
        case .accountChanged, .legacyClaimFailed, .identityStateUnavailable:
            true
        case .none, .noAccount, .restricted, .temporarilyUnavailable, .accountStatusUnavailable:
            false
        }
    }
}

struct NFPrivateCloudStoreSelection: Equatable, Sendable {
    let durableStoreURL: URL
    let privateCloudConfiguration: NFPrivateCloudRuntimeConfiguration?
    let transition: NFPrivateCloudStartupTransition
    let claimedLegacyArtifacts: Bool
}

struct NFPrivateCloudLocalPurgePreparation: Equatable, Sendable {
    /// The open durable store and the shared local-only store are intentionally
    /// left in place until the next launch, before either can be opened again.
    let requiresRelaunch: Bool
    let removedInactiveNamespaceCount: Int
}

enum NFPrivateCloudPendingLocalPurgeResult: Equatable, Sendable {
    case notRequested
    case completed
    case failed
}

enum NFPrivateCloudLocalPurgeError: Error, Equatable {
    case identityStateUnavailable
    case openStoreDoesNotMatchActiveIdentity
    case existingPurgeRequestMismatch
    case couldNotPersistRequest
    case verificationFailed
}

private struct NFPrivateCloudStoreIdentityRegistry: Codable, Equatable {
    static let currentSchemaVersion = 1

    var schemaVersion = currentSchemaVersion
    var namespaceByFingerprint: [String: String] = [:]
    var lastObservedFingerprint: String?
    var pendingAccountFingerprint: String?
}

private struct NFPrivateCloudPendingLocalPurge: Codable, Equatable {
    static let currentSchemaVersion = 1

    var schemaVersion = currentSchemaVersion
    let requestID: UUID?
    let openStoreNamespace: String?
    let openStoreWasLegacy: Bool
}

private struct NFPrivateCloudVerifiedLocalPurgeReceipt: Codable, Equatable {
    static let currentSchemaVersion = 1

    var schemaVersion = currentSchemaVersion
    let requestID: UUID?
    let verifiedAt: Date
}

/// Selects one durable SwiftData store per one-way iCloud account fingerprint.
/// The registry contains only salted fingerprints and random local namespace
/// names. A CloudKit user record identifier never reaches this layer.
enum NFPrivateCloudStoreIdentityResolver {
    static let registryKey = "nf.private-sync.structured-store-identities.v1"
    static let activeNamespaceKey = "nf.private-sync.active-account-namespace.v1"
    static let pendingLocalPurgeKey = "nf.private-sync.structured-local-purge.v1"
    static let verifiedLocalPurgeReceiptKey = "nf.private-sync.structured-local-purge-receipt.v1"
    static let accountStoreFolderName = "NeuroForge/StructuredCloudAccounts"

    static func activeNamespace(defaults: UserDefaults = .standard) -> String? {
        guard let namespace = defaults.string(forKey: activeNamespaceKey),
              isSafeNamespace(namespace)
        else {
            return nil
        }
        return namespace
    }

    /// Lets the document-asset transport copy its pre-namespacing state only
    /// for the installation's first claimed account. The transport records its
    /// own successful claim so this predicate alone never causes repeat copies.
    static func canClaimLegacyDocumentAssetState(
        namespace: String,
        defaults: UserDefaults = .standard
    ) -> Bool {
        guard isSafeNamespace(namespace),
              case let .valid(registry) = loadRegistry(defaults: defaults),
              registry.namespaceByFingerprint.count == 1,
              registry.namespaceByFingerprint.values.first == namespace,
              registry.lastObservedFingerprint.flatMap({
                  registry.namespaceByFingerprint[$0]
              }) == namespace,
              registry.pendingAccountFingerprint == nil
        else {
            return false
        }
        return true
    }

    static func hasPendingLocalPurge(defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: pendingLocalPurgeKey) != nil
    }

    static func hasStagedLocalPurge(
        requestID: UUID,
        defaults: UserDefaults = .standard
    ) -> Bool {
        guard let data = defaults.data(forKey: pendingLocalPurgeKey),
              let request = try? JSONDecoder().decode(
                  NFPrivateCloudPendingLocalPurge.self,
                  from: data
              ), request.schemaVersion == NFPrivateCloudPendingLocalPurge.currentSchemaVersion,
              request.requestID == requestID,
              request.openStoreNamespace.map(isSafeNamespace) ?? true
        else {
            return false
        }
        return true
    }

    /// Used only by request-creation rollback before any remote zone mutation.
    /// A mismatched request can never discard another transaction's intent.
    @discardableResult
    static func discardStagedLocalPurge(
        requestID: UUID,
        defaults: UserDefaults = .standard
    ) -> Bool {
        guard hasStagedLocalPurge(requestID: requestID, defaults: defaults) else {
            return false
        }
        defaults.removeObject(forKey: pendingLocalPurgeKey)
        return defaults.object(forKey: pendingLocalPurgeKey) == nil
    }

    /// Writes and verifies the complete local-purge intent without deleting a
    /// byte. Complete private-cloud deletion uses this on launch 1, binding the
    /// intent to its durable request UUID. Remote zone absence is verified on
    /// launch 2 before App startup calls the destructive pre-container hook.
    @MainActor
    static func stageLocalPurge(
        requestID: UUID? = nil,
        openDurableStoreURL: URL,
        defaults: UserDefaults = .standard,
        fileManager: FileManager = .default,
        applicationSupportURL: URL? = nil
    ) throws -> NFPrivateCloudLocalPurgePreparation {
        let supportURL = try resolvedApplicationSupportURL(
            fileManager: fileManager,
            applicationSupportURL: applicationSupportURL
        )
        guard case let .valid(registry) = loadRegistry(defaults: defaults) else {
            throw NFPrivateCloudLocalPurgeError.identityStateUnavailable
        }
        let legacyURL = supportURL.appending(path: "default.store", directoryHint: .notDirectory)
        let expectedOpenURL = localStoreURL(
            registry: registry,
            supportURL: supportURL,
            legacyURL: legacyURL
        )
        guard urlsReferToSameLocation(openDurableStoreURL, expectedOpenURL) else {
            throw NFPrivateCloudLocalPurgeError.openStoreDoesNotMatchActiveIdentity
        }
        let request = NFPrivateCloudPendingLocalPurge(
            requestID: requestID,
            openStoreNamespace: namespaceForStoreURL(
                expectedOpenURL,
                registry: registry,
                supportURL: supportURL
            ),
            openStoreWasLegacy: urlsReferToSameLocation(expectedOpenURL, legacyURL)
        )
        if let existingData = defaults.data(forKey: pendingLocalPurgeKey) {
            guard let existing = try? JSONDecoder().decode(
                NFPrivateCloudPendingLocalPurge.self,
                from: existingData
            ), existing == request else {
                throw NFPrivateCloudLocalPurgeError.existingPurgeRequestMismatch
            }
        }
        guard let requestData = try? JSONEncoder().encode(request) else {
            throw NFPrivateCloudLocalPurgeError.couldNotPersistRequest
        }
        defaults.set(requestData, forKey: pendingLocalPurgeKey)
        guard defaults.data(forKey: pendingLocalPurgeKey) == requestData else {
            throw NFPrivateCloudLocalPurgeError.couldNotPersistRequest
        }
        NFPrivateSyncBootstrapPreference.set(false, defaults: defaults)
        return NFPrivateCloudLocalPurgePreparation(
            requiresRelaunch: true,
            removedInactiveNamespaceCount: 0
        )
    }

    /// Repairs the narrow crash window where the account-bound cloud deletion
    /// request was persisted but its zero-deletion local intent was not. The
    /// active URL is derived only from the validated identity registry; no
    /// caller-provided path is trusted and no artifact is removed here.
    @MainActor
    static func repairOrStageLocalPurge(
        requestID: UUID,
        defaults: UserDefaults = .standard,
        fileManager: FileManager = .default,
        applicationSupportURL: URL? = nil
    ) throws -> NFPrivateCloudLocalPurgePreparation {
        if hasStagedLocalPurge(requestID: requestID, defaults: defaults) {
            return NFPrivateCloudLocalPurgePreparation(
                requiresRelaunch: true,
                removedInactiveNamespaceCount: 0
            )
        }
        let supportURL = try resolvedApplicationSupportURL(
            fileManager: fileManager,
            applicationSupportURL: applicationSupportURL
        )
        guard case let .valid(registry) = loadRegistry(defaults: defaults) else {
            throw NFPrivateCloudLocalPurgeError.identityStateUnavailable
        }
        let legacyURL = supportURL.appending(path: "default.store", directoryHint: .notDirectory)
        return try stageLocalPurge(
            requestID: requestID,
            openDurableStoreURL: localStoreURL(
                registry: registry,
                supportURL: supportURL,
                legacyURL: legacyURL
            ),
            defaults: defaults,
            fileManager: fileManager,
            applicationSupportURL: supportURL
        )
    }

    /// Starts whole-device structured-store cleanup while a ModelContainer is
    /// still open. It removes every *inactive* account namespace and all custom
    /// asset queue/cache namespaces, but never removes the supplied open store
    /// or the shared local-only SwiftData store. Those two are durably marked
    /// for deletion by `performPendingLocalPurgeBeforeOpeningContainer` on the
    /// next launch.
    ///
    /// The caller must first stop and drain the custom document transport. Its
    /// terminal stop prevents an in-memory queue from recreating purged files.
    @MainActor
    static func scheduleLocalPurge(
        openDurableStoreURL: URL,
        defaults: UserDefaults = .standard,
        fileManager: FileManager = .default,
        applicationSupportURL: URL? = nil
    ) throws -> NFPrivateCloudLocalPurgePreparation {
        _ = try stageLocalPurge(
            openDurableStoreURL: openDurableStoreURL,
            defaults: defaults,
            fileManager: fileManager,
            applicationSupportURL: applicationSupportURL
        )
        let supportURL = try resolvedApplicationSupportURL(
            fileManager: fileManager,
            applicationSupportURL: applicationSupportURL
        )
        guard case let .valid(registry) = loadRegistry(defaults: defaults) else {
            throw NFPrivateCloudLocalPurgeError.identityStateUnavailable
        }
        let legacyURL = supportURL.appending(path: "default.store", directoryHint: .notDirectory)
        let expectedOpenURL = localStoreURL(
            registry: registry,
            supportURL: supportURL,
            legacyURL: legacyURL
        )
        guard urlsReferToSameLocation(openDurableStoreURL, expectedOpenURL) else {
            throw NFPrivateCloudLocalPurgeError.openStoreDoesNotMatchActiveIdentity
        }

        let openNamespace = namespaceForStoreURL(
            expectedOpenURL,
            registry: registry,
            supportURL: supportURL
        )
        try NFFileDocumentAssetSyncStateStore.purgeAllApplicationState(
            fileManager: fileManager,
            defaults: defaults,
            applicationSupportURL: supportURL
        )

        var removedInactiveNamespaceCount = 0
        let accountRoot = accountStoreRootURL(supportURL: supportURL)
        if itemExists(at: accountRoot, fileManager: fileManager) {
            for candidate in try fileManager.contentsOfDirectory(
                at: accountRoot,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            ) {
                if let openNamespace,
                   candidate.lastPathComponent == openNamespace {
                    continue
                }
                try fileManager.removeItem(at: candidate)
                guard !itemExists(at: candidate, fileManager: fileManager) else {
                    throw NFPrivateCloudLocalPurgeError.verificationFailed
                }
                removedInactiveNamespaceCount += 1
            }
        }
        if !urlsReferToSameLocation(expectedOpenURL, legacyURL) {
            try removeLegacyStoreArtifacts(
                legacyStoreURL: legacyURL,
                fileManager: fileManager
            )
        }

        return NFPrivateCloudLocalPurgePreparation(
            requiresRelaunch: true,
            removedInactiveNamespaceCount: removedInactiveNamespaceCount
        )
    }

    /// Completes a scheduled purge before any SwiftData or CloudKit-backed
    /// ModelContainer is constructed. Registry and fingerprint salt are cleared
    /// only after every structured store, sidecar, support directory, and custom
    /// queue/cache root is verified gone.
    @MainActor
    static func performPendingLocalPurgeBeforeOpeningContainer(
        requiredRequestID: UUID? = nil,
        defaults: UserDefaults = .standard,
        fileManager: FileManager = .default,
        applicationSupportURL: URL? = nil
    ) -> NFPrivateCloudPendingLocalPurgeResult {
        guard let requestData = defaults.data(forKey: pendingLocalPurgeKey) else {
            return .notRequested
        }
        guard let request = try? JSONDecoder().decode(
            NFPrivateCloudPendingLocalPurge.self,
            from: requestData
        ), request.schemaVersion == NFPrivateCloudPendingLocalPurge.currentSchemaVersion,
           request.openStoreNamespace.map(isSafeNamespace) ?? true,
           request.requestID == requiredRequestID
        else {
            return .failed
        }

        do {
            let supportURL = try resolvedApplicationSupportURL(
                fileManager: fileManager,
                applicationSupportURL: applicationSupportURL
            )
            let legacyURL = supportURL.appending(path: "default.store", directoryHint: .notDirectory)
            try removeLegacyStoreArtifacts(
                legacyStoreURL: legacyURL,
                fileManager: fileManager
            )

            let accountRoot = accountStoreRootURL(supportURL: supportURL)
            if itemExists(at: accountRoot, fileManager: fileManager) {
                try fileManager.removeItem(at: accountRoot)
            }
            guard !itemExists(at: accountRoot, fileManager: fileManager) else {
                throw NFPrivateCloudLocalPurgeError.verificationFailed
            }

            let localOnlyURL = supportURL.appending(
                path: "local-derived.store",
                directoryHint: .notDirectory
            )
            try removeLegacyStoreArtifacts(
                legacyStoreURL: localOnlyURL,
                fileManager: fileManager
            )
            try NFFileDocumentAssetSyncStateStore.purgeAllApplicationState(
                fileManager: fileManager,
                defaults: defaults,
                applicationSupportURL: supportURL
            )

            // The ModelContext cleanup normally removes these before staging.
            // Repeating and verifying them here closes the crash window between
            // its commit and the pre-container structured-store purge.
            let localArtifactRoots = [
                supportURL.appending(path: "NeuroForge/Documents", directoryHint: .isDirectory),
                supportURL.appending(
                    path: NFNextDayEnhancementCache.folderName,
                    directoryHint: .isDirectory
                )
            ]
            for root in localArtifactRoots where itemExists(at: root, fileManager: fileManager) {
                try fileManager.removeItem(at: root)
            }
            guard localArtifactRoots.allSatisfy({ !itemExists(at: $0, fileManager: fileManager) }) else {
                throw NFPrivateCloudLocalPurgeError.verificationFailed
            }

            let receipt = NFPrivateCloudVerifiedLocalPurgeReceipt(
                requestID: request.requestID,
                verifiedAt: Date()
            )
            guard let receiptData = try? JSONEncoder().encode(receipt) else {
                throw NFPrivateCloudLocalPurgeError.couldNotPersistRequest
            }
            defaults.set(receiptData, forKey: verifiedLocalPurgeReceiptKey)
            guard defaults.data(forKey: verifiedLocalPurgeReceiptKey) == receiptData else {
                throw NFPrivateCloudLocalPurgeError.couldNotPersistRequest
            }

            defaults.removeObject(forKey: registryKey)
            defaults.removeObject(forKey: activeNamespaceKey)
            defaults.removeObject(forKey: NFPrivateCloudAccountFingerprint.saltKey)
            defaults.removeObject(forKey: NFPrivateSyncBootstrapPreference.accountChangeLockKey)
            defaults.removeObject(forKey: pendingLocalPurgeKey)
            return .completed
        } catch {
            // Preserve the request, registry, and salt. A retry cannot attach a
            // partially purged history to a newly derived identity.
            return .failed
        }
    }

    static func hasVerifiedLocalPurgeReceipt(
        requestID: UUID? = nil,
        defaults: UserDefaults = .standard
    ) -> Bool {
        guard let data = defaults.data(forKey: verifiedLocalPurgeReceiptKey),
              let receipt = try? JSONDecoder().decode(
                  NFPrivateCloudVerifiedLocalPurgeReceipt.self,
                  from: data
              ), receipt.schemaVersion == NFPrivateCloudVerifiedLocalPurgeReceipt.currentSchemaVersion,
              receipt.requestID == requestID
        else {
            return false
        }
        return true
    }

    @discardableResult
    static func consumeVerifiedLocalPurgeReceipt(
        requestID: UUID? = nil,
        defaults: UserDefaults = .standard
    ) -> Bool {
        guard hasVerifiedLocalPurgeReceipt(requestID: requestID, defaults: defaults) else {
            return false
        }
        defaults.removeObject(forKey: verifiedLocalPurgeReceiptKey)
        return defaults.object(forKey: verifiedLocalPurgeReceiptKey) == nil
    }

    /// Commits the explicit start-fresh choice made in the account-transition
    /// UI. The previous namespace remains active, mapped, and untouched for
    /// later export or a future return to that account. The new namespace is
    /// activated only after relaunch, when CloudKit identity is checked again.
    @MainActor
    static func acceptPendingAccountChange(defaults: UserDefaults = .standard) -> Bool {
        guard !NFPrivateSyncBootstrapPreference.isCloudDeletionLocked(defaults: defaults),
              case var .valid(registry) = loadRegistry(defaults: defaults),
              let pendingFingerprint = registry.pendingAccountFingerprint,
              let pendingNamespace = registry.namespaceByFingerprint[pendingFingerprint],
              isSafeNamespace(pendingNamespace)
        else {
            return false
        }
        registry.lastObservedFingerprint = pendingFingerprint
        registry.pendingAccountFingerprint = nil
        saveRegistry(registry, defaults: defaults)
        NFPrivateSyncBootstrapPreference.setAfterExplicitUserChoice(true, defaults: defaults)
        return true
    }

    @MainActor
    static func resolve(
        requestedPrivateCloudConfiguration: NFPrivateCloudRuntimeConfiguration?,
        accountProbe: NFPrivateCloudAccountProbeResult?,
        defaults: UserDefaults = .standard,
        fileManager: FileManager = .default,
        applicationSupportURL: URL? = nil,
        namespaceFactory: () -> String = { UUID().uuidString.lowercased() }
    ) -> NFPrivateCloudStoreSelection {
        let supportURL: URL
        do {
            supportURL = if let applicationSupportURL {
                applicationSupportURL
            } else {
                try NFPersistentStoreLocation.applicationSupportDirectory(fileManager: fileManager)
            }
            try fileManager.createDirectory(at: supportURL, withIntermediateDirectories: true)
        } catch {
            let emergencyURL = fileManager.temporaryDirectory.appending(
                path: "NeuroForge-local-unavailable.store",
                directoryHint: .notDirectory
            )
            return NFPrivateCloudStoreSelection(
                durableStoreURL: emergencyURL,
                privateCloudConfiguration: nil,
                transition: .identityStateUnavailable,
                claimedLegacyArtifacts: false
            )
        }

        let legacyURL = supportURL.appending(path: "default.store", directoryHint: .notDirectory)
        let registryResult = loadRegistry(defaults: defaults)
        guard case let .valid(registry) = registryResult else {
            NFPrivateSyncBootstrapPreference.lockAfterAccountChange(defaults: defaults)
            return NFPrivateCloudStoreSelection(
                durableStoreURL: legacyURL,
                privateCloudConfiguration: nil,
                transition: .identityStateUnavailable,
                claimedLegacyArtifacts: false
            )
        }
        updateActiveNamespace(from: registry, defaults: defaults)

        guard let requestedPrivateCloudConfiguration else {
            let transition: NFPrivateCloudStartupTransition = if
                registry.pendingAccountFingerprint != nil,
                NFPrivateSyncBootstrapPreference.isAccountChangeLocked(defaults: defaults)
            {
                .accountChanged
            } else {
                .none
            }
            return NFPrivateCloudStoreSelection(
                durableStoreURL: localStoreURL(
                    registry: registry,
                    supportURL: supportURL,
                    legacyURL: legacyURL
                ),
                privateCloudConfiguration: nil,
                transition: transition,
                claimedLegacyArtifacts: false
            )
        }

        switch accountProbe ?? .couldNotDetermine {
        case .noAccount:
            return localFallback(
                transition: .noAccount,
                registry: registry,
                supportURL: supportURL,
                legacyURL: legacyURL
            )
        case .restricted:
            return localFallback(
                transition: .restricted,
                registry: registry,
                supportURL: supportURL,
                legacyURL: legacyURL
            )
        case .temporarilyUnavailable:
            return localFallback(
                transition: .temporarilyUnavailable,
                registry: registry,
                supportURL: supportURL,
                legacyURL: legacyURL
            )
        case .couldNotDetermine:
            return localFallback(
                transition: .accountStatusUnavailable,
                registry: registry,
                supportURL: supportURL,
                legacyURL: legacyURL
            )
        case let .available(fingerprint):
            return resolveAvailableAccount(
                fingerprint: fingerprint,
                configuration: requestedPrivateCloudConfiguration,
                registry: registry,
                defaults: defaults,
                fileManager: fileManager,
                supportURL: supportURL,
                legacyURL: legacyURL,
                namespaceFactory: namespaceFactory
            )
        }
    }

    private enum RegistryLoadResult {
        case valid(NFPrivateCloudStoreIdentityRegistry)
        case invalid
    }

    private static func loadRegistry(defaults: UserDefaults) -> RegistryLoadResult {
        guard let data = defaults.data(forKey: registryKey) else {
            return .valid(NFPrivateCloudStoreIdentityRegistry())
        }
        guard let registry = try? JSONDecoder().decode(
            NFPrivateCloudStoreIdentityRegistry.self,
            from: data
        ), registry.schemaVersion == NFPrivateCloudStoreIdentityRegistry.currentSchemaVersion,
           registry.namespaceByFingerprint.values.allSatisfy(isSafeNamespace)
        else {
            return .invalid
        }
        return .valid(registry)
    }

    private static func saveRegistry(
        _ registry: NFPrivateCloudStoreIdentityRegistry,
        defaults: UserDefaults
    ) {
        guard let data = try? JSONEncoder().encode(registry) else { return }
        defaults.set(data, forKey: registryKey)
    }

    private static func resolveAvailableAccount(
        fingerprint: String,
        configuration: NFPrivateCloudRuntimeConfiguration,
        registry initialRegistry: NFPrivateCloudStoreIdentityRegistry,
        defaults: UserDefaults,
        fileManager: FileManager,
        supportURL: URL,
        legacyURL: URL,
        namespaceFactory: () -> String
    ) -> NFPrivateCloudStoreSelection {
        var registry = initialRegistry
        let mappedNamespace = registry.namespaceByFingerprint[fingerprint]
        let hasOtherKnownIdentity = registry.namespaceByFingerprint.keys.contains { $0 != fingerprint }
        let accountChanged = registry.lastObservedFingerprint.map { $0 != fingerprint }
            ?? (mappedNamespace == nil && hasOtherKnownIdentity)

        if accountChanged {
            let namespace = mappedNamespace ?? uniqueNamespace(
                excluding: Set(registry.namespaceByFingerprint.values),
                namespaceFactory: namespaceFactory
            )
            let storeURL = accountStoreURL(namespace: namespace, supportURL: supportURL)
            do {
                try fileManager.createDirectory(
                    at: storeURL.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
            } catch {
                NFPrivateSyncBootstrapPreference.lockAfterAccountChange(defaults: defaults)
                return NFPrivateCloudStoreSelection(
                    durableStoreURL: legacyURL,
                    privateCloudConfiguration: nil,
                    transition: .identityStateUnavailable,
                    claimedLegacyArtifacts: false
                )
            }
            registry.namespaceByFingerprint[fingerprint] = namespace
            registry.pendingAccountFingerprint = fingerprint
            saveRegistry(registry, defaults: defaults)
            NFPrivateSyncBootstrapPreference.lockAfterAccountChange(defaults: defaults)
            return NFPrivateCloudStoreSelection(
                durableStoreURL: localStoreURL(
                    registry: initialRegistry,
                    supportURL: supportURL,
                    legacyURL: legacyURL
                ),
                privateCloudConfiguration: nil,
                transition: .accountChanged,
                claimedLegacyArtifacts: false
            )
        }

        if let mappedNamespace {
            let storeURL = accountStoreURL(namespace: mappedNamespace, supportURL: supportURL)
            do {
                try fileManager.createDirectory(
                    at: storeURL.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
            } catch {
                return NFPrivateCloudStoreSelection(
                    durableStoreURL: legacyURL,
                    privateCloudConfiguration: nil,
                    transition: .identityStateUnavailable,
                    claimedLegacyArtifacts: false
                )
            }
            registry.lastObservedFingerprint = fingerprint
            registry.pendingAccountFingerprint = nil
            saveRegistry(registry, defaults: defaults)
            defaults.set(mappedNamespace, forKey: activeNamespaceKey)
            return NFPrivateCloudStoreSelection(
                durableStoreURL: storeURL,
                privateCloudConfiguration: configuration,
                transition: .none,
                claimedLegacyArtifacts: false
            )
        }

        // This is the first identity ever observed by this installation. Copy
        // the legacy database and every recognized SQLite/support sidecar into
        // the new namespace before recording the claim. The legacy artifacts
        // remain untouched as a quarantined recovery copy.
        let namespace = uniqueNamespace(
            excluding: Set(registry.namespaceByFingerprint.values),
            namespaceFactory: namespaceFactory
        )
        let storeURL = accountStoreURL(namespace: namespace, supportURL: supportURL)
        do {
            let claimed = try cloneLegacyStoreArtifacts(
                from: legacyURL,
                to: storeURL,
                fileManager: fileManager
            )
            registry.namespaceByFingerprint[fingerprint] = namespace
            registry.lastObservedFingerprint = fingerprint
            registry.pendingAccountFingerprint = nil
            saveRegistry(registry, defaults: defaults)
            defaults.set(namespace, forKey: activeNamespaceKey)
            return NFPrivateCloudStoreSelection(
                durableStoreURL: storeURL,
                privateCloudConfiguration: configuration,
                transition: .none,
                claimedLegacyArtifacts: claimed
            )
        } catch {
            return NFPrivateCloudStoreSelection(
                durableStoreURL: legacyURL,
                privateCloudConfiguration: nil,
                transition: .legacyClaimFailed,
                claimedLegacyArtifacts: false
            )
        }
    }

    private static func localFallback(
        transition: NFPrivateCloudStartupTransition,
        registry: NFPrivateCloudStoreIdentityRegistry,
        supportURL: URL,
        legacyURL: URL
    ) -> NFPrivateCloudStoreSelection {
        NFPrivateCloudStoreSelection(
            durableStoreURL: localStoreURL(
                registry: registry,
                supportURL: supportURL,
                legacyURL: legacyURL
            ),
            privateCloudConfiguration: nil,
            transition: transition,
            claimedLegacyArtifacts: false
        )
    }

    private static func localStoreURL(
        registry: NFPrivateCloudStoreIdentityRegistry,
        supportURL: URL,
        legacyURL: URL
    ) -> URL {
        guard let fingerprint = registry.lastObservedFingerprint,
              let namespace = registry.namespaceByFingerprint[fingerprint],
              isSafeNamespace(namespace)
        else {
            return legacyURL
        }
        return accountStoreURL(namespace: namespace, supportURL: supportURL)
    }

    private static func updateActiveNamespace(
        from registry: NFPrivateCloudStoreIdentityRegistry,
        defaults: UserDefaults
    ) {
        guard let fingerprint = registry.lastObservedFingerprint,
              let namespace = registry.namespaceByFingerprint[fingerprint],
              isSafeNamespace(namespace)
        else {
            return
        }
        defaults.set(namespace, forKey: activeNamespaceKey)
    }

    private static func accountStoreURL(namespace: String, supportURL: URL) -> URL {
        supportURL
            .appending(path: accountStoreFolderName, directoryHint: .isDirectory)
            .appending(path: namespace, directoryHint: .isDirectory)
            .appending(path: "default.store", directoryHint: .notDirectory)
    }

    private static func accountStoreRootURL(supportURL: URL) -> URL {
        supportURL.appending(path: accountStoreFolderName, directoryHint: .isDirectory)
    }

    private static func resolvedApplicationSupportURL(
        fileManager: FileManager,
        applicationSupportURL: URL?
    ) throws -> URL {
        if let applicationSupportURL { return applicationSupportURL }
        return try NFPersistentStoreLocation.applicationSupportDirectory(fileManager: fileManager)
    }

    private static func namespaceForStoreURL(
        _ storeURL: URL,
        registry: NFPrivateCloudStoreIdentityRegistry,
        supportURL: URL
    ) -> String? {
        registry.namespaceByFingerprint.values.first {
            urlsReferToSameLocation(
                accountStoreURL(namespace: $0, supportURL: supportURL),
                storeURL
            )
        }
    }

    private static func urlsReferToSameLocation(_ lhs: URL, _ rhs: URL) -> Bool {
        lhs.standardizedFileURL.resolvingSymlinksInPath().path
            == rhs.standardizedFileURL.resolvingSymlinksInPath().path
    }

    private static func itemExists(at url: URL, fileManager: FileManager) -> Bool {
        fileManager.fileExists(atPath: url.path)
            || (try? fileManager.destinationOfSymbolicLink(atPath: url.path)) != nil
    }

    private static func removeLegacyStoreArtifacts(
        legacyStoreURL: URL,
        fileManager: FileManager
    ) throws {
        let folder = legacyStoreURL.deletingLastPathComponent()
        guard itemExists(at: folder, fileManager: fileManager) else { return }
        let baseName = legacyStoreURL.lastPathComponent
        let artifacts = try fileManager.contentsOfDirectory(
            at: folder,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ).filter {
            let name = $0.lastPathComponent
            return name == baseName
                || name.hasPrefix(baseName + "-")
                || name.hasPrefix(baseName + ".")
                || name.hasPrefix(baseName + "_")
        }
        for artifact in artifacts {
            try fileManager.removeItem(at: artifact)
        }
        guard artifacts.allSatisfy({ !itemExists(at: $0, fileManager: fileManager) }) else {
            throw NFPrivateCloudLocalPurgeError.verificationFailed
        }
    }

    private static func uniqueNamespace(
        excluding existing: Set<String>,
        namespaceFactory: () -> String
    ) -> String {
        for _ in 0..<8 {
            let candidate = namespaceFactory().lowercased()
            if isSafeNamespace(candidate), !existing.contains(candidate) {
                return candidate
            }
        }
        var candidate: String
        repeat {
            candidate = UUID().uuidString.lowercased()
        } while existing.contains(candidate)
        return candidate
    }

    private static func isSafeNamespace(_ namespace: String) -> Bool {
        !namespace.isEmpty
            && namespace.count <= 96
            && namespace.unicodeScalars.allSatisfy {
                CharacterSet.alphanumerics.contains($0) || $0.value == 45 || $0.value == 95
            }
    }

    /// Returns whether at least one legacy artifact was copied. Originals are
    /// intentionally retained. On any failure the incomplete destination is
    /// removed, while the legacy source remains byte-for-byte unchanged.
    private static func cloneLegacyStoreArtifacts(
        from legacyStoreURL: URL,
        to destinationStoreURL: URL,
        fileManager: FileManager
    ) throws -> Bool {
        let sourceFolder = legacyStoreURL.deletingLastPathComponent()
        let baseName = legacyStoreURL.lastPathComponent
        let candidates = try fileManager.contentsOfDirectory(
            at: sourceFolder,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ).filter {
            let name = $0.lastPathComponent
            return name == baseName
                || name.hasPrefix(baseName + "-")
                || name.hasPrefix(baseName + ".")
                || name.hasPrefix(baseName + "_")
        }
        let destinationFolder = destinationStoreURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: destinationFolder, withIntermediateDirectories: true)
        guard !candidates.isEmpty else {
            try? fileManager.removeItem(at: destinationFolder)
            return false
        }

        do {
            for source in candidates {
                let destination = destinationFolder.appending(
                    path: source.lastPathComponent,
                    directoryHint: .notDirectory
                )
                try fileManager.copyItem(at: source, to: destination)
            }
            return true
        } catch {
            try? fileManager.removeItem(at: destinationFolder)
            throw error
        }
    }
}

/// Opens the CloudKit-backed store when it is both requested and available,
/// but never makes CloudKit availability a prerequisite for opening the local
/// source of truth. The fallback passes `nil` to the same store opener, so it
/// reopens the existing database at the same URL without moving, replacing, or
/// deleting any user data.
enum NFCloudStoreBootstrap {
    static func open<Store>(
        requestedPrivateCloudConfiguration: NFPrivateCloudRuntimeConfiguration?,
        opener: (NFPrivateCloudRuntimeConfiguration?) throws -> Store
    ) throws -> NFCloudStoreBootstrapResult<Store> {
        guard let requestedPrivateCloudConfiguration else {
            return NFCloudStoreBootstrapResult(
                store: try opener(nil),
                activePrivateCloudConfiguration: nil,
                usedLocalFallback: false
            )
        }

        do {
            return NFCloudStoreBootstrapResult(
                store: try opener(requestedPrivateCloudConfiguration),
                activePrivateCloudConfiguration: requestedPrivateCloudConfiguration,
                usedLocalFallback: false
            )
        } catch {
            return NFCloudStoreBootstrapResult(
                store: try opener(nil),
                activePrivateCloudConfiguration: nil,
                usedLocalFallback: true
            )
        }
    }
}

enum NFPersistentStoreLocation {
    /// Records that are authoritative learning history or user-authored state.
    /// This is the only configuration eligible for the capability-gated private
    /// CloudKit transport; local caches can never leak into that schema.
    static var durableModels: [any PersistentModel.Type] {
        [
            UserProfileRecord.self,
            ProgressAnnotationRecord.self,
            AttemptRecord.self,
            AttemptReflectionRecord.self,
            WeeklyTransferStateRecord.self,
            ReassessmentStateRecord.self,
            SessionCheckpointRecord.self,
            DailyPlanRecord.self,
            ItemReportRecord.self
        ]
    }

    /// Device-derived or disposable state. These records live in a separate
    /// local-only store even while private sync is active.
    static var localOnlyModels: [any PersistentModel.Type] {
        [
            InputCalibrationRecord.self,
            SourceDocumentRecord.self,
            SourceChunkRecord.self,
            AIGenerationRecord.self
        ]
    }

    static func applicationSupportDirectory(fileManager: FileManager = .default) throws -> URL {
        try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
    }

    static func applicationStoreURL(fileManager: FileManager = .default) throws -> URL {
        try applicationSupportDirectory(fileManager: fileManager)
            .appending(path: "default.store", directoryHint: .notDirectory)
    }

    static func localOnlyStoreURL(fileManager: FileManager = .default) throws -> URL {
        let support = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        return support.appending(path: "local-derived.store", directoryHint: .notDirectory)
    }

    static func configurations(
        fileManager: FileManager = .default,
        storeRootURL: URL? = nil,
        durableStoreURL: URL? = nil,
        inMemory: Bool = false,
        privateCloudConfiguration: NFPrivateCloudRuntimeConfiguration? = .current()
    ) throws -> [ModelConfiguration] {
        let durableURL: URL
        let localURL: URL
        if let storeRootURL {
            localURL = storeRootURL.appending(path: "local-derived.store")
        } else {
            localURL = try localOnlyStoreURL(fileManager: fileManager)
        }
        if let durableStoreURL {
            durableURL = durableStoreURL
        } else if let storeRootURL {
            durableURL = storeRootURL.appending(path: "default.store")
        } else {
            durableURL = try applicationStoreURL(fileManager: fileManager)
        }
        if let storeRootURL {
            try fileManager.createDirectory(at: storeRootURL, withIntermediateDirectories: true)
        }
        if !inMemory {
            try fileManager.createDirectory(
                at: durableURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try fileManager.createDirectory(
                at: localURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
        }
        let durableSchema = Schema(durableModels, version: NFSchemaV1.versionIdentifier)
        let localSchema = Schema(localOnlyModels, version: NFSchemaV1.versionIdentifier)
        if inMemory {
            return [
                ModelConfiguration("NeuroForgeDurable", schema: durableSchema, isStoredInMemoryOnly: true, cloudKitDatabase: .none),
                ModelConfiguration("NeuroForgeLocalOnly", schema: localSchema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
            ]
        }
        // The runtime configuration is non-nil only when the requested
        // container appears in both build configuration and the process's
        // validated code-signing entitlements. Unsigned development builds
        // therefore remain local-only. The disposable configuration never
        // receives a CloudKit database under any circumstances.
        let durableCloudDatabase: ModelConfiguration.CloudKitDatabase = if let privateCloudConfiguration {
            .private(privateCloudConfiguration.containerIdentifier)
        } else {
            .none
        }
        return [
            ModelConfiguration(
                "NeuroForgeDurable",
                schema: durableSchema,
                url: durableURL,
                allowsSave: true,
                cloudKitDatabase: durableCloudDatabase
            ),
            ModelConfiguration(
                "NeuroForgeLocalOnly",
                schema: localSchema,
                url: localURL,
                allowsSave: true,
                cloudKitDatabase: .none
            )
        ]
    }
}

struct NFStoreRecoveryPackage: Sendable {
    let artifactURLs: [URL]
    let failureSummary: String
}

enum NFStoreRecoveryService {
    static let packageFolderName = "NeuroForge-Store-Recovery"

    /// Copies the inaccessible store and SQLite sidecars without mutating them.
    /// The recovery UI blocks normal writes and lets the learner share these raw
    /// artifacts with a trusted migration build or support channel. A single
    /// stable package is rotated on every failed launch so repeated failures do
    /// not accumulate private database copies in the temporary directory.
    static func preparePackage(
        storeURL: URL,
        openingError: Error,
        fileManager: FileManager = .default,
        recoveryRootURL: URL? = nil
    ) -> NFStoreRecoveryPackage {
        let root = recoveryRootURL ?? fileManager.temporaryDirectory
        let folder = root.appending(path: packageFolderName, directoryHint: .isDirectory)

        // Purge packages created by prerelease builds as well as the current
        // stable package. If a protected copy cannot be removed, do not create
        // an additional one beside it.
        let priorPackages = (try? fileManager.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ))?.filter { $0.lastPathComponent.hasPrefix(packageFolderName) } ?? []
        var rotationSucceeded = true
        for priorPackage in priorPackages {
            do {
                try fileManager.removeItem(at: priorPackage)
            } catch {
                rotationSucceeded = false
            }
        }

        guard rotationSucceeded else {
            return NFStoreRecoveryPackage(
                artifactURLs: [],
                failureSummary: NFAppLocalization.localized("The saved database could not be opened, and an older protected recovery package could not be safely rotated. Preserve the app container and retry with a migration-capable build.",
                    locale: NFAppLocalization.preferredLocale,
                    comment: "Recovery-mode explanation when a previous protected database recovery package cannot be safely replaced."
                )
            )
        }

        do {
            try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
            try? fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: folder.path)
        } catch {
            return NFStoreRecoveryPackage(
                artifactURLs: [],
                failureSummary: NFAppLocalization.localized("The saved database could not be opened, and NeuroForge could not prepare its protected recovery package. Preserve the app container and retry with a migration-capable build.",
                    locale: NFAppLocalization.preferredLocale,
                    comment: "Recovery-mode explanation when the app cannot create a protected database recovery package."
                )
            )
        }

        let candidateURLs = [
            storeURL,
            URL(fileURLWithPath: storeURL.path + "-wal"),
            URL(fileURLWithPath: storeURL.path + "-shm")
        ]
        var artifacts: [URL] = []
        for source in candidateURLs where fileManager.fileExists(atPath: source.path) {
            let destination = folder.appending(path: source.lastPathComponent, directoryHint: .notDirectory)
            if (try? fileManager.copyItem(at: source, to: destination)) != nil {
                protectArtifact(at: destination, fileManager: fileManager)
                artifacts.append(destination)
            }
        }

        let manifestURL = folder.appending(path: "Recovery-Read-Me.txt", directoryHint: .notDirectory)
        let schemaTarget = String(describing: NFSchemaV1.versionIdentifier)
        let manifest = [
            NFAppLocalization.localized("NeuroForge local-store recovery package", locale: NFAppLocalization.preferredLocale, comment: "Heading in the exported database recovery read-me."),
            NFAppLocalization.localized("Created: \(Date().ISO8601Format())", locale: NFAppLocalization.preferredLocale, comment: "Creation timestamp in the exported database recovery read-me."),
            NFAppLocalization.localized("Schema target: \(schemaTarget)", locale: NFAppLocalization.preferredLocale, comment: "Target database schema in the exported database recovery read-me."),
            "",
            NFAppLocalization.localized("The production store could not be opened. NeuroForge did not reset, migrate in place, or overwrite it.", locale: NFAppLocalization.preferredLocale, comment: "Data-safety explanation in the exported database recovery read-me."),
            NFAppLocalization.localized("Keep all files in this package together. They can contain private training responses and source text; share them only with a destination you trust.", locale: NFAppLocalization.preferredLocale, comment: "Privacy warning in the exported database recovery read-me."),
            "",
            NFAppLocalization.localized("Failure category: \(String(reflecting: type(of: openingError)))", locale: NFAppLocalization.preferredLocale, comment: "Technical failure category in the exported database recovery read-me.")
        ].joined(separator: "\n")
        if let data = manifest.data(using: .utf8),
           (try? data.write(to: manifestURL, options: .atomic)) != nil {
            protectArtifact(at: manifestURL, fileManager: fileManager)
            artifacts.append(manifestURL)
        }
        return NFStoreRecoveryPackage(
            artifactURLs: artifacts,
            failureSummary: NFAppLocalization.localized("The saved database could not be opened or migrated with schema \(schemaTarget).",
                locale: NFAppLocalization.preferredLocale,
                comment: "Recovery-mode explanation when the saved database cannot be opened or migrated; the placeholder is the required schema version."
            )
        )
    }

    private static func protectArtifact(at url: URL, fileManager: FileManager) {
        var attributes: [FileAttributeKey: Any] = [.posixPermissions: 0o600]
        #if os(iOS) || os(tvOS) || os(watchOS) || os(visionOS)
        attributes[.protectionKey] = FileProtectionType.complete
        #endif
        try? fileManager.setAttributes(attributes, ofItemAtPath: url.path)
    }
}

import CloudKit
import CryptoKit
import Foundation
#if os(macOS)
import Security
#endif

/// A runtime view of the code signature, kept separate from Info.plist. An
/// Info.plist string alone is never sufficient authority to open CloudKit.
struct NFCloudKitEntitlementSnapshot: Codable, Equatable, Sendable {
    let containerIdentifiers: Set<String>
    let services: Set<String>
    let hasContainerEnvironment: Bool
    let hasSigningIdentifier: Bool

    init(
        containerIdentifiers: Set<String> = [],
        services: Set<String> = [],
        hasContainerEnvironment: Bool = false,
        hasSigningIdentifier: Bool = false
    ) {
        self.containerIdentifiers = containerIdentifiers
        self.services = services
        self.hasContainerEnvironment = hasContainerEnvironment
        self.hasSigningIdentifier = hasSigningIdentifier
    }

    var permitsCloudKit: Bool {
        hasSigningIdentifier
            && hasContainerEnvironment
            && services.contains("CloudKit")
            && !containerIdentifiers.isEmpty
    }
}

struct NFPrivateCloudRuntimeConfiguration: Codable, Equatable, Sendable {
    let containerIdentifier: String

    static func evaluate(
        userEnabledPrivateSync: Bool,
        requestedContainerIdentifier: String?,
        configuredContainerIdentifiers: Set<String>,
        entitlements: NFCloudKitEntitlementSnapshot
    ) -> NFPrivateCloudRuntimeConfiguration? {
        guard userEnabledPrivateSync,
            let requested = requestedContainerIdentifier?
                .trimmingCharacters(in: .whitespacesAndNewlines),
            !requested.isEmpty,
            configuredContainerIdentifiers.contains(requested),
            entitlements.permitsCloudKit,
            entitlements.containerIdentifiers.contains(requested)
        else {
            return nil
        }
        return NFPrivateCloudRuntimeConfiguration(containerIdentifier: requested)
    }

    static func current(
        bundle: Bundle = .main,
        defaults: UserDefaults = .standard
    ) -> NFPrivateCloudRuntimeConfiguration? {
        let requested = bundle.object(forInfoDictionaryKey: "NFCloudKitContainerIdentifier") as? String
        let configured = Set(
            bundle.object(forInfoDictionaryKey: "NFEntitledCloudKitContainerIdentifiers") as? [String] ?? []
        )
        return evaluate(
            userEnabledPrivateSync: NFPrivateSyncBootstrapPreference.isEnabled(defaults: defaults),
            requestedContainerIdentifier: requested,
            configuredContainerIdentifiers: configured,
            entitlements: NFRuntimeEntitlementReader.snapshot(bundle: bundle)
        )
    }
}

enum NFPrivateSyncBootstrapPreference {
    static let key = "nf.private-sync.enabled-at-next-launch.v1"
    static let accountChangeLockKey = "nf.private-sync.account-change-lock.v1"
    static let cloudDeletionLockKey = "nf.private-sync.cloud-deletion-lock.v1"

    static func isEnabled(defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: key)
            && !isAccountChangeLocked(defaults: defaults)
            && !isCloudDeletionLocked(defaults: defaults)
    }

    static func set(_ enabled: Bool, defaults: UserDefaults = .standard) {
        // System reconciliation and imported profile values may turn sync off,
        // but cannot silently defeat a durable account-change lock by turning
        // it back on. Only the explicit user-choice API clears that lock.
        defaults.set(
            enabled
                && !isAccountChangeLocked(defaults: defaults)
                && !isCloudDeletionLocked(defaults: defaults),
            forKey: key
        )
    }

    static func isAccountChangeLocked(defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: accountChangeLockKey)
    }

    static func lockAfterAccountChange(defaults: UserDefaults = .standard) {
        defaults.set(true, forKey: accountChangeLockKey)
        defaults.set(false, forKey: key)
    }

    static func isCloudDeletionLocked(defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: cloudDeletionLockKey)
    }

    static func lockForCloudDeletion(defaults: UserDefaults = .standard) {
        defaults.set(true, forKey: cloudDeletionLockKey)
        defaults.set(false, forKey: key)
    }

    /// Only the verified deletion workflow may release this lock. Preference
    /// toggles and imported profiles deliberately cannot clear it.
    static func unlockAfterCloudDeletion(defaults: UserDefaults = .standard) {
        defaults.set(false, forKey: cloudDeletionLockKey)
    }

    static func applyImportedProfilePreference(
        _ enabled: Bool,
        defaults: UserDefaults = .standard
    ) {
        set(enabled, defaults: defaults)
    }

    static func setAfterExplicitUserChoice(
        _ enabled: Bool,
        defaults: UserDefaults = .standard
    ) {
        defaults.set(false, forKey: accountChangeLockKey)
        defaults.set(
            enabled && !isCloudDeletionLocked(defaults: defaults),
            forKey: key
        )
    }
}

/// The result of the launch-time iCloud identity check. The available case
/// contains only an app-scoped, salted digest. A CloudKit user record name is
/// used in memory long enough to derive that digest and is never returned,
/// persisted, or logged.
enum NFPrivateCloudAccountProbeResult: Equatable, Sendable {
    case available(fingerprint: String)
    case noAccount
    case restricted
    case temporarilyUnavailable
    case couldNotDetermine
}

enum NFPrivateCloudAccountFingerprint {
    static let saltKey = "nf.private-sync.account-fingerprint-salt.v1"

    /// Produces a one-way, installation-scoped identity. Including the
    /// container prevents a digest from being correlated across containers;
    /// the random salt prevents correlation across app installations.
    static func derive(
        cloudKitRecordName: String,
        containerIdentifier: String,
        salt: Data
    ) -> String {
        var payload = Data("NeuroForge.PrivateCloudIdentity.v1\u{0}".utf8)
        payload.append(salt)
        payload.append(0)
        payload.append(Data(containerIdentifier.utf8))
        payload.append(0)
        payload.append(Data(cloudKitRecordName.utf8))
        return SHA256.hash(data: payload).map { String(format: "%02x", $0) }.joined()
    }

    @MainActor
    static func installationSalt(defaults: UserDefaults = .standard) -> Data {
        if let stored = defaults.data(forKey: saltKey), stored.count >= 32 {
            return stored
        }
        var generator = SystemRandomNumberGenerator()
        let generated = Data((0..<32).map { _ in UInt8.random(in: .min ... .max, using: &generator) })
        defaults.set(generated, forKey: saltKey)
        return generated
    }
}

enum NFPrivateCloudAccountProbe {
    static let launchTimeout: Duration = .seconds(4)

    /// CloudKit identity is checked before a CloudKit-backed SwiftData store is
    /// constructed. Errors intentionally collapse to an indeterminate local-
    /// first state; no user or record identifier is included in diagnostics.
    @MainActor
    static func check(
        containerIdentifier: String,
        defaults: UserDefaults = .standard
    ) async -> NFPrivateCloudAccountProbeResult {
        await resultWithTimeout(timeout: launchTimeout) {
            await queryCloudKitIdentity(
                containerIdentifier: containerIdentifier,
                defaults: defaults
            )
        }
    }

    /// Kept injectable so the offline/stalled-service launch behavior can be
    /// tested without contacting CloudKit.
    @MainActor
    static func resultWithTimeout(
        timeout: Duration,
        operation: @escaping @MainActor @Sendable () async -> NFPrivateCloudAccountProbeResult
    ) async -> NFPrivateCloudAccountProbeResult {
        let race = NFPrivateCloudAccountProbeRace()
        let probeTask = Task { @MainActor in
            let result = await operation()
            guard !Task.isCancelled else { return }
            await race.offer(result)
        }
        let timeoutTask = Task { @MainActor in
            do {
                try await Task.sleep(for: timeout)
            } catch {
                return
            }
            await race.offer(.couldNotDetermine)
        }
        let result = await withTaskCancellationHandler {
            await race.wait()
        } onCancel: {
            probeTask.cancel()
            timeoutTask.cancel()
            Task { await race.offer(.couldNotDetermine) }
        }
        probeTask.cancel()
        timeoutTask.cancel()
        return result
    }

    @MainActor
    private static func queryCloudKitIdentity(
        containerIdentifier: String,
        defaults: UserDefaults
    ) async -> NFPrivateCloudAccountProbeResult {
        let container = CKContainer(identifier: containerIdentifier)
        let status: CKAccountStatus
        do {
            status = try await container.accountStatus()
        } catch {
            return .couldNotDetermine
        }
        guard !Task.isCancelled else { return .couldNotDetermine }

        switch status {
        case .available:
            do {
                let recordID = try await container.userRecordID()
                guard !Task.isCancelled else { return .couldNotDetermine }
                let fingerprint = NFPrivateCloudAccountFingerprint.derive(
                    cloudKitRecordName: recordID.recordName,
                    containerIdentifier: containerIdentifier,
                    salt: NFPrivateCloudAccountFingerprint.installationSalt(defaults: defaults)
                )
                return .available(fingerprint: fingerprint)
            } catch {
                return .couldNotDetermine
            }
        case .noAccount:
            return .noAccount
        case .restricted:
            return .restricted
        case .temporarilyUnavailable:
            return .temporarilyUnavailable
        case .couldNotDetermine:
            return .couldNotDetermine
        @unknown default:
            return .couldNotDetermine
        }
    }
}

private actor NFPrivateCloudAccountProbeRace {
    private var result: NFPrivateCloudAccountProbeResult?
    private var continuation: CheckedContinuation<NFPrivateCloudAccountProbeResult, Never>?

    func wait() async -> NFPrivateCloudAccountProbeResult {
        if let result { return result }
        return await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
    }

    func offer(_ offeredResult: NFPrivateCloudAccountProbeResult) {
        guard result == nil else { return }
        result = offeredResult
        continuation?.resume(returning: offeredResult)
        continuation = nil
    }
}

enum NFRuntimeEntitlementReader {
    private static let containersKey = "com.apple.developer.icloud-container-identifiers"
    private static let servicesKey = "com.apple.developer.icloud-services"
    private static let environmentKey = "com.apple.developer.icloud-container-environment"

    static func snapshot(bundle: Bundle = .main) -> NFCloudKitEntitlementSnapshot {
        #if os(macOS)
        guard let task = SecTaskCreateFromSelf(nil) else {
            return NFCloudKitEntitlementSnapshot()
        }

        let containers = stringSet(entitlement: containersKey, task: task)
        let services = stringSet(entitlement: servicesKey, task: task)
        let environment = entitlementValue(environmentKey, task: task)
        var signingError: Unmanaged<CFError>?
        let signingIdentifier = SecTaskCopySigningIdentifier(task, &signingError) as String?

        return NFCloudKitEntitlementSnapshot(
            containerIdentifiers: containers,
            services: services,
            hasContainerEnvironment: environment != nil,
            hasSigningIdentifier: signingIdentifier?.isEmpty == false
        )
        #else
        // iOS does not expose SecTask as public SDK API. The code-signed bundle
        // manifest therefore decides only whether the app should *attempt* to
        // open CloudKit. The OS and CloudKit still validate the actual signed
        // entitlements before granting access; a missing or mismatched
        // provisioning capability fails the cloud open and the app falls back
        // to the same on-device store without deleting it.
        let containers = Set(
            bundle.object(forInfoDictionaryKey: "NFEntitledCloudKitContainerIdentifiers") as? [String] ?? []
        )
        let cloudKitEnabled = bundle.object(
            forInfoDictionaryKey: "NFCloudKitServiceEnabled"
        ) as? Bool ?? false
        let hasBundleIdentifier = bundle.bundleIdentifier?.isEmpty == false
        return NFCloudKitEntitlementSnapshot(
            containerIdentifiers: cloudKitEnabled ? containers : [],
            services: cloudKitEnabled ? ["CloudKit"] : [],
            hasContainerEnvironment: cloudKitEnabled && !containers.isEmpty,
            hasSigningIdentifier: hasBundleIdentifier
        )
        #endif
    }

    #if os(macOS)
    private static func stringSet(entitlement: String, task: SecTask) -> Set<String> {
        guard let value = entitlementValue(entitlement, task: task) else { return [] }
        if let strings = value as? [String] { return Set(strings) }
        if let string = value as? String { return [string] }
        return []
    }

    private static func entitlementValue(_ key: String, task: SecTask) -> CFTypeRef? {
        var error: Unmanaged<CFError>?
        return SecTaskCopyValueForEntitlement(task, key as CFString, &error)
    }
    #endif
}

/// The custom asset transport has a deliberately tiny record-type surface.
/// SwiftData cache model names are never generated dynamically as CloudKit
/// types, preventing a future local cache from silently entering cloud schema.
enum NFPrivateCloudSchemaManifest {
    static let zoneName = "NeuroForgePrivateDocumentsV1"
    static let assetRecordType = "NFDocumentOriginalAsset"
    static let documentRecordType = "NFDocumentOriginalLink"
    static let tombstoneRecordType = "NFDocumentOriginalTombstone"

    static let allowedRecordTypes: Set<String> = [
        assetRecordType,
        documentRecordType,
        tombstoneRecordType
    ]

    static let prohibitedLocalCacheEntityNames: Set<String> = [
        "InputCalibrationRecord",
        "SourceChunkRecord",
        "AIGenerationRecord",
        "NFPreparedEnhancementCacheEntry"
    ]

    static let assetFieldKeys: Set<String> = [
        "schemaVersion", "contentHash", "sizeBytes", "payload"
    ]
    static let documentFieldKeys: Set<String> = [
        "schemaVersion", "documentID", "contentHash", "filename",
        "typeIdentifier", "sizeBytes", "modifiedAt", "aiPolicy",
        "pccConsentPolicyVersion", "pccConsentedAt", "assetReference"
    ]
    static let tombstoneFieldKeys: Set<String> = [
        "schemaVersion", "documentID", "contentHash", "deletedAt"
    ]
    static let prohibitedDeviceLocalFieldKeys: Set<String> = [
        "localPath", "localFilePath", "indexState", "indexError",
        "characterCount", "chunkCount", "text", "extractedText",
        "sourceChunks", "generatedPayload", "inputLatency"
    ]

    static func isAllowedRecordType(_ recordType: String) -> Bool {
        allowedRecordTypes.contains(recordType)
            && !prohibitedLocalCacheEntityNames.contains(recordType)
    }

    static func fieldsArePrivacySafe(recordType: String, keys: Set<String>) -> Bool {
        let allowlist: Set<String>
        switch recordType {
        case assetRecordType: allowlist = assetFieldKeys
        case documentRecordType: allowlist = documentFieldKeys
        case tombstoneRecordType: allowlist = tombstoneFieldKeys
        default: return false
        }
        return keys.isSubset(of: allowlist)
            && keys.isDisjoint(with: prohibitedDeviceLocalFieldKeys)
    }
}

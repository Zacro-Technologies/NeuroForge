import CloudKit
import Foundation

enum NFSyncRecordCategory: String, Codable, CaseIterable, Sendable {
    case attempt
    case attemptReflection
    case itemExposure
    case profileOrSettings
    case dailyPlan
    case sessionState
    case documentMetadata
    case contentAddressedAsset
    case derivedState
}

enum NFMergeStrategy: String, Codable, Equatable, Sendable {
    case appendOnlyIdempotent
    case exposureEventUnion
    case latestModifiedWithIdentifierTieBreak
    case earliestValidCandidate
    case completedSessionDominates
    case newRevisionForContentHashChange
    case contentAddressedDeduplication
    case discardAndRecompute
}

enum NFSyncMergePolicyCatalog {
    static func strategy(for category: NFSyncRecordCategory) -> NFMergeStrategy {
        switch category {
        case .attempt, .attemptReflection:
            .appendOnlyIdempotent
        case .itemExposure:
            .exposureEventUnion
        case .profileOrSettings:
            .latestModifiedWithIdentifierTieBreak
        case .dailyPlan:
            .earliestValidCandidate
        case .sessionState:
            .completedSessionDominates
        case .documentMetadata:
            .newRevisionForContentHashChange
        case .contentAddressedAsset:
            .contentAddressedDeduplication
        case .derivedState:
            .discardAndRecompute
        }
    }
}

enum NFLocalOnlySyncReason: String, Codable, Equatable, Sendable {
    case userDisabled
    case missingCloudKitEntitlement
    case missingContainerConfiguration
    case configuredContainerIsNotEntitled
    case syncEngineUnavailable
    case restartRequiredToEnable
    case restartRequiredToDisable
}

enum NFSyncCapability: Codable, Equatable, Sendable {
    case localOnly(reason: NFLocalOnlySyncReason)
    /// This means the build is configured to attempt private sync. It does not
    /// mean that an account is available or that any record has synchronized.
    case privateCloudConfigured(containerIdentifier: String)

    var supportsPrivateSyncAttempt: Bool {
        if case .privateCloudConfigured = self { return true }
        return false
    }
}

struct NFSyncBuildConfiguration: Codable, Equatable, Sendable {
    var userEnabledPrivateSync: Bool
    var requestedContainerIdentifier: String?
    var entitledContainerIdentifiers: Set<String>
    var syncEngineInstalled: Bool

    init(
        userEnabledPrivateSync: Bool,
        requestedContainerIdentifier: String?,
        entitledContainerIdentifiers: Set<String> = [],
        syncEngineInstalled: Bool = false
    ) {
        self.userEnabledPrivateSync = userEnabledPrivateSync
        self.requestedContainerIdentifier = requestedContainerIdentifier
        self.entitledContainerIdentifiers = entitledContainerIdentifiers
        self.syncEngineInstalled = syncEngineInstalled
    }
}

enum NFSyncCapabilityEvaluator {
    static func evaluate(_ configuration: NFSyncBuildConfiguration) -> NFSyncCapability {
        guard configuration.userEnabledPrivateSync else {
            return .localOnly(reason: .userDisabled)
        }
        guard !configuration.entitledContainerIdentifiers.isEmpty else {
            return .localOnly(reason: .missingCloudKitEntitlement)
        }
        guard
            let requestedContainer = configuration.requestedContainerIdentifier?
                .trimmingCharacters(in: .whitespacesAndNewlines),
            !requestedContainer.isEmpty
        else {
            return .localOnly(reason: .missingContainerConfiguration)
        }
        guard configuration.entitledContainerIdentifiers.contains(requestedContainer) else {
            return .localOnly(reason: .configuredContainerIsNotEntitled)
        }
        guard configuration.syncEngineInstalled else {
            return .localOnly(reason: .syncEngineUnavailable)
        }
        return .privateCloudConfigured(containerIdentifier: requestedContainer)
    }
}

enum NFCloudAccountState: String, Codable, Equatable, Sendable {
    case unknown
    case available
    case noAccount
    case restricted
    case temporarilyUnavailable
}

enum NFSyncEnginePhase: Codable, Equatable, Sendable {
    case notStarted
    case idle
    case processing
    case failed(redactedCode: String)
}

struct NFSyncQueueMetrics: Codable, Equatable, Sendable {
    let pendingRecordCount: Int
    let pendingAssetCount: Int

    init(pendingRecordCount: Int, pendingAssetCount: Int) {
        self.pendingRecordCount = max(0, pendingRecordCount)
        self.pendingAssetCount = max(0, pendingAssetCount)
    }

    var totalPendingCount: Int {
        pendingRecordCount + pendingAssetCount
    }
}

enum NFSyncDisplayState: String, Codable, Equatable, Sendable {
    case localOnly
    case queued
    case syncing
    case synced
    case paused
    case error
}

enum NFStructuredSyncEventKind: String, Codable, Equatable, Sendable {
    case setup
    case importChanges
    case exportChanges
}

struct NFStructuredSyncEvent: Equatable, Sendable {
    let id: UUID
    let kind: NFStructuredSyncEventKind
    let startDate: Date
    let endDate: Date?
    let succeeded: Bool
    let redactedFailureCode: String?
}

enum NFStructuredSyncStatusReason: Codable, Equatable, Sendable {
    case localOnly(NFLocalOnlySyncReason)
    case awaitingInitialFrameworkEvent
    case localWritesAwaitingExport
    case frameworkProcessing(Int)
    case frameworkFailure(redactedCode: String)
    case frameworkReportedSuccess
}

/// SwiftData structured-record delivery and the custom original-file transport
/// are deliberately observed independently. A successful CKAsset pass cannot
/// make this snapshot "synced", and a SwiftData export cannot clear the asset
/// queue. `hasPendingLocalWrites` is set by durable-model saves and is cleared
/// only by a successful framework export event.
struct NFStructuredSyncStatusSnapshot: Codable, Equatable, Sendable {
    let displayState: NFSyncDisplayState
    let reason: NFStructuredSyncStatusReason
    let lastSuccessfulImportAt: Date?
    let lastSuccessfulExportAt: Date?
    let hasPendingLocalWrites: Bool
    let activeEventCount: Int
    let configurationChangeRequiresRestart: Bool
    let localWritesRemainAvailable: Bool

    var lastSuccessfulSyncAt: Date? {
        [lastSuccessfulImportAt, lastSuccessfulExportAt]
            .compactMap { $0 }
            .max()
    }
}

enum NFStructuredSyncStatusResolver {
    static func resolve(
        isConfiguredAtLaunch: Bool,
        localOnlyReason: NFLocalOnlySyncReason,
        lastSuccessfulImportAt: Date?,
        lastSuccessfulExportAt: Date?,
        hasPendingLocalWrites: Bool,
        activeEventCount: Int,
        lastFailureCode: String?,
        configurationChangeRequiresRestart: Bool
    ) -> NFStructuredSyncStatusSnapshot {
        guard isConfiguredAtLaunch else {
            return snapshot(
                state: .localOnly,
                reason: .localOnly(localOnlyReason),
                lastSuccessfulImportAt: lastSuccessfulImportAt,
                lastSuccessfulExportAt: lastSuccessfulExportAt,
                hasPendingLocalWrites: hasPendingLocalWrites,
                activeEventCount: 0,
                configurationChangeRequiresRestart: configurationChangeRequiresRestart
            )
        }

        if activeEventCount > 0 {
            return snapshot(
                state: .syncing,
                reason: .frameworkProcessing(activeEventCount),
                lastSuccessfulImportAt: lastSuccessfulImportAt,
                lastSuccessfulExportAt: lastSuccessfulExportAt,
                hasPendingLocalWrites: hasPendingLocalWrites,
                activeEventCount: activeEventCount,
                configurationChangeRequiresRestart: configurationChangeRequiresRestart
            )
        }
        if let lastFailureCode {
            return snapshot(
                state: .error,
                reason: .frameworkFailure(redactedCode: lastFailureCode),
                lastSuccessfulImportAt: lastSuccessfulImportAt,
                lastSuccessfulExportAt: lastSuccessfulExportAt,
                hasPendingLocalWrites: hasPendingLocalWrites,
                activeEventCount: 0,
                configurationChangeRequiresRestart: configurationChangeRequiresRestart
            )
        }
        if hasPendingLocalWrites {
            return snapshot(
                state: .queued,
                reason: .localWritesAwaitingExport,
                lastSuccessfulImportAt: lastSuccessfulImportAt,
                lastSuccessfulExportAt: lastSuccessfulExportAt,
                hasPendingLocalWrites: true,
                activeEventCount: 0,
                configurationChangeRequiresRestart: configurationChangeRequiresRestart
            )
        }
        guard lastSuccessfulImportAt != nil || lastSuccessfulExportAt != nil else {
            return snapshot(
                state: .queued,
                reason: .awaitingInitialFrameworkEvent,
                lastSuccessfulImportAt: nil,
                lastSuccessfulExportAt: nil,
                hasPendingLocalWrites: false,
                activeEventCount: 0,
                configurationChangeRequiresRestart: configurationChangeRequiresRestart
            )
        }
        return snapshot(
            state: .synced,
            reason: .frameworkReportedSuccess,
            lastSuccessfulImportAt: lastSuccessfulImportAt,
            lastSuccessfulExportAt: lastSuccessfulExportAt,
            hasPendingLocalWrites: false,
            activeEventCount: 0,
            configurationChangeRequiresRestart: configurationChangeRequiresRestart
        )
    }

    private static func snapshot(
        state: NFSyncDisplayState,
        reason: NFStructuredSyncStatusReason,
        lastSuccessfulImportAt: Date?,
        lastSuccessfulExportAt: Date?,
        hasPendingLocalWrites: Bool,
        activeEventCount: Int,
        configurationChangeRequiresRestart: Bool
    ) -> NFStructuredSyncStatusSnapshot {
        NFStructuredSyncStatusSnapshot(
            displayState: state,
            reason: reason,
            lastSuccessfulImportAt: lastSuccessfulImportAt,
            lastSuccessfulExportAt: lastSuccessfulExportAt,
            hasPendingLocalWrites: hasPendingLocalWrites,
            activeEventCount: max(0, activeEventCount),
            configurationChangeRequiresRestart: configurationChangeRequiresRestart,
            localWritesRemainAvailable: true
        )
    }
}

enum NFSyncStatusReason: Codable, Equatable, Sendable {
    case localOnly(NFLocalOnlySyncReason)
    case accountUnknown
    case noAccount
    case accountRestricted
    case accountTemporarilyUnavailable
    case awaitingInitialSuccessfulSync
    case pendingChanges(Int)
    case processing
    case engineFailure(redactedCode: String)
    case fullyProcessed
}

struct NFSyncStatusSnapshot: Codable, Equatable, Sendable {
    let displayState: NFSyncDisplayState
    let reason: NFSyncStatusReason
    let lastSuccessfulSyncAt: Date?
    let queue: NFSyncQueueMetrics
    /// Sync is secondary to the local source of truth and never gates attempts.
    let localWritesRemainAvailable: Bool
}

enum NFSyncStatusResolver {
    static func resolve(
        capability: NFSyncCapability,
        accountState: NFCloudAccountState,
        enginePhase: NFSyncEnginePhase,
        queue: NFSyncQueueMetrics,
        lastSuccessfulSyncAt: Date?
    ) -> NFSyncStatusSnapshot {
        if case let .localOnly(reason) = capability {
            return snapshot(
                state: .localOnly,
                reason: .localOnly(reason),
                queue: queue,
                lastSuccessfulSyncAt: lastSuccessfulSyncAt
            )
        }

        switch accountState {
        case .unknown:
            return snapshot(
                state: .paused,
                reason: .accountUnknown,
                queue: queue,
                lastSuccessfulSyncAt: lastSuccessfulSyncAt
            )
        case .noAccount:
            return snapshot(
                state: .paused,
                reason: .noAccount,
                queue: queue,
                lastSuccessfulSyncAt: lastSuccessfulSyncAt
            )
        case .restricted:
            return snapshot(
                state: .paused,
                reason: .accountRestricted,
                queue: queue,
                lastSuccessfulSyncAt: lastSuccessfulSyncAt
            )
        case .temporarilyUnavailable:
            return snapshot(
                state: .paused,
                reason: .accountTemporarilyUnavailable,
                queue: queue,
                lastSuccessfulSyncAt: lastSuccessfulSyncAt
            )
        case .available:
            break
        }

        switch enginePhase {
        case let .failed(redactedCode):
            return snapshot(
                state: .error,
                reason: .engineFailure(redactedCode: redactedCode),
                queue: queue,
                lastSuccessfulSyncAt: lastSuccessfulSyncAt
            )
        case .processing:
            return snapshot(
                state: .syncing,
                reason: .processing,
                queue: queue,
                lastSuccessfulSyncAt: lastSuccessfulSyncAt
            )
        case .notStarted, .idle:
            break
        }

        if queue.totalPendingCount > 0 {
            return snapshot(
                state: .queued,
                reason: .pendingChanges(queue.totalPendingCount),
                queue: queue,
                lastSuccessfulSyncAt: lastSuccessfulSyncAt
            )
        }

        guard lastSuccessfulSyncAt != nil else {
            return snapshot(
                state: .queued,
                reason: .awaitingInitialSuccessfulSync,
                queue: queue,
                lastSuccessfulSyncAt: nil
            )
        }

        return snapshot(
            state: .synced,
            reason: .fullyProcessed,
            queue: queue,
            lastSuccessfulSyncAt: lastSuccessfulSyncAt
        )
    }

    private static func snapshot(
        state: NFSyncDisplayState,
        reason: NFSyncStatusReason,
        queue: NFSyncQueueMetrics,
        lastSuccessfulSyncAt: Date?
    ) -> NFSyncStatusSnapshot {
        NFSyncStatusSnapshot(
            displayState: state,
            reason: reason,
            lastSuccessfulSyncAt: lastSuccessfulSyncAt,
            queue: queue,
            localWritesRemainAvailable: true
        )
    }
}

struct NFAppendOnlySyncRecord<Payload: Codable & Equatable & Sendable>: Codable, Equatable, Sendable {
    let id: UUID
    let contentFingerprint: String
    let payload: Payload
}

struct NFAppendOnlyMergeConflict: Codable, Equatable, Sendable {
    let id: UUID
    let retainedFingerprint: String
    let rejectedFingerprint: String
}

struct NFAppendOnlyMergeResult<Payload: Codable & Equatable & Sendable>: Codable, Equatable, Sendable {
    let records: [NFAppendOnlySyncRecord<Payload>]
    let conflicts: [NFAppendOnlyMergeConflict]
}

enum NFSyncMergeEngine {
    static func mergeAppendOnly<Payload: Codable & Equatable & Sendable>(
        local: [NFAppendOnlySyncRecord<Payload>],
        remote: [NFAppendOnlySyncRecord<Payload>]
    ) -> NFAppendOnlyMergeResult<Payload> {
        var byID: [UUID: NFAppendOnlySyncRecord<Payload>] = [:]
        var conflicts: [NFAppendOnlyMergeConflict] = []

        for candidate in (local + remote).sorted(by: appendOnlyOrder) {
            guard let existing = byID[candidate.id] else {
                byID[candidate.id] = candidate
                continue
            }
            guard existing != candidate else { continue }

            let retained: NFAppendOnlySyncRecord<Payload>
            let rejected: NFAppendOnlySyncRecord<Payload>
            if candidate.contentFingerprint < existing.contentFingerprint {
                retained = candidate
                rejected = existing
                byID[candidate.id] = candidate
            } else {
                retained = existing
                rejected = candidate
            }
            conflicts.append(
                NFAppendOnlyMergeConflict(
                    id: candidate.id,
                    retainedFingerprint: retained.contentFingerprint,
                    rejectedFingerprint: rejected.contentFingerprint
                )
            )
        }

        return NFAppendOnlyMergeResult(
            records: byID.values.sorted(by: appendOnlyOrder),
            conflicts: deduplicated(conflicts).sorted { lhs, rhs in
                if lhs.id == rhs.id {
                    return lhs.rejectedFingerprint < rhs.rejectedFingerprint
                }
                return lhs.id.uuidString < rhs.id.uuidString
            }
        )
    }

    static func latestModified<Value: Codable & Equatable & Sendable>(
        _ lhs: NFMutableSyncRecord<Value>,
        _ rhs: NFMutableSyncRecord<Value>
    ) -> NFMutableSyncRecord<Value> {
        if lhs.modifiedAt != rhs.modifiedAt {
            return lhs.modifiedAt > rhs.modifiedAt ? lhs : rhs
        }
        return lhs.id.uuidString < rhs.id.uuidString ? lhs : rhs
    }

    static func mergeExposure(
        _ lhs: NFItemExposureSyncState,
        _ rhs: NFItemExposureSyncState
    ) -> NFItemExposureSyncState? {
        guard lhs.itemIdentity == rhs.itemIdentity else { return nil }
        let eventIDs = lhs.observedEventIDs.union(rhs.observedEventIDs)
        return NFItemExposureSyncState(
            itemIdentity: lhs.itemIdentity,
            firstSeenAt: min(lhs.firstSeenAt, rhs.firstSeenAt),
            lastSeenAt: max(lhs.lastSeenAt, rhs.lastSeenAt),
            count: max(lhs.count, rhs.count, eventIDs.count),
            observedEventIDs: eventIDs
        )
    }

    static func canonicalDailyPlan(
        for localDayKey: String,
        from candidates: [NFDailyPlanSyncCandidate]
    ) -> NFDailyPlanSyncCandidate? {
        candidates
            .filter { $0.isValid && $0.localDayKey == localDayKey }
            .min { lhs, rhs in
                if lhs.createdAt == rhs.createdAt {
                    return lhs.id.uuidString < rhs.id.uuidString
                }
                return lhs.createdAt < rhs.createdAt
            }
    }

    static func mergeSession(
        _ lhs: NFSessionSyncState,
        _ rhs: NFSessionSyncState
    ) -> NFSessionSyncState? {
        guard lhs.id == rhs.id else { return nil }
        if lhs.phase != rhs.phase {
            if lhs.phase == .completed { return lhs }
            if rhs.phase == .completed { return rhs }
        }

        let lhsDate = lhs.endedAt ?? lhs.modifiedAt
        let rhsDate = rhs.endedAt ?? rhs.modifiedAt
        if lhsDate != rhsDate {
            return lhsDate > rhsDate ? lhs : rhs
        }
        return lhs.id.uuidString < rhs.id.uuidString ? lhs : rhs
    }

    private static func appendOnlyOrder<Payload>(
        _ lhs: NFAppendOnlySyncRecord<Payload>,
        _ rhs: NFAppendOnlySyncRecord<Payload>
    ) -> Bool where Payload: Codable & Equatable & Sendable {
        if lhs.id == rhs.id {
            return lhs.contentFingerprint < rhs.contentFingerprint
        }
        return lhs.id.uuidString < rhs.id.uuidString
    }

    private static func deduplicated(
        _ conflicts: [NFAppendOnlyMergeConflict]
    ) -> [NFAppendOnlyMergeConflict] {
        var seen: Set<String> = []
        return conflicts.filter { conflict in
            seen.insert(
                [
                    conflict.id.uuidString,
                    conflict.retainedFingerprint,
                    conflict.rejectedFingerprint
                ].joined(separator: "|")
            ).inserted
        }
    }
}

struct NFMutableSyncRecord<Value: Codable & Equatable & Sendable>: Codable, Equatable, Sendable {
    let id: UUID
    let modifiedAt: Date
    let value: Value
}

struct NFItemExposureSyncState: Codable, Equatable, Sendable {
    let itemIdentity: String
    let firstSeenAt: Date
    let lastSeenAt: Date
    let count: Int
    let observedEventIDs: Set<UUID>

    init(
        itemIdentity: String,
        firstSeenAt: Date,
        lastSeenAt: Date,
        count: Int,
        observedEventIDs: Set<UUID>
    ) {
        self.itemIdentity = itemIdentity
        self.firstSeenAt = firstSeenAt
        self.lastSeenAt = lastSeenAt
        self.count = max(0, count)
        self.observedEventIDs = observedEventIDs
    }
}

struct NFDailyPlanSyncCandidate: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let localDayKey: String
    let createdAt: Date
    let isValid: Bool
}

enum NFSessionSyncPhase: Int, Codable, Equatable, Sendable {
    case active
    case paused
    case completed
}

struct NFSessionSyncState: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let phase: NFSessionSyncPhase
    let modifiedAt: Date
    let endedAt: Date?
}

enum NFPrivacyDataPath: String, Codable, CaseIterable, Equatable, Sendable {
    case localDevice
    case privateStructuredCloud
    case privateDocumentAssets
}

struct NFPrivacyDashboardSnapshot: Codable, Equatable, Sendable {
    let localDurableRecordCount: Int
    let localOnlyRecordCount: Int
    let structuredCloudEligibleRecordCount: Int
    let privateOriginalDocumentCount: Int
    let availablePaths: Set<NFPrivacyDataPath>
}

enum NFDataDeletionScope: String, Codable, CaseIterable, Equatable, Identifiable, Sendable {
    case thisDeviceOnly
    case privateCloudAndThisDevice

    var id: String { rawValue }
}

enum NFStructuredCloudDeletionStatus: Codable, Equatable, Sendable {
    case notRequested
    case awaitingRestart(requestedAt: Date)
    case verified(exportedAt: Date)
    case failed(redactedCode: String)
}

enum NFOriginalCloudDeletionStatus: Codable, Equatable, Sendable {
    case notRequested
    case notApplicable
    case verified(lastSuccessfulSyncAt: Date)
}

struct NFDataDeletionReceipt: Equatable, Sendable {
    let scope: NFDataDeletionScope
    let localReceipt: NFLocalDataCleanupReceipt
    let originalCloudStatus: NFOriginalCloudDeletionStatus
    let structuredCloudStatus: NFStructuredCloudDeletionStatus
}

/// The only private CloudKit zones a complete NeuroForge deletion may target.
///
/// `com.apple.coredata.cloudkit.zone` is the private mirroring zone documented
/// by Apple in TN3163/TN3164. The second zone is created explicitly by
/// `NFPrivateDocumentAssetCloudKitAdapter`. Keeping these identifiers in a
/// closed enum prevents persisted state or UI input from becoming a general
/// purpose CloudKit zone-deletion primitive.
enum NFPrivateCloudOwnedZone: String, Codable, CaseIterable, Equatable, Hashable, Sendable {
    case structuredStore = "com.apple.coredata.cloudkit.zone"
    case privateDocumentAssets = "NeuroForgePrivateDocumentsV1"

    static var deletionOrder: [Self] {
        allCases.sorted { $0.rawValue < $1.rawValue }
    }
}

enum NFPrivateCloudZoneDeleteResult: Equatable, Sendable {
    case accepted
    case zoneNotFound
    case failed(redactedCode: String, retryable: Bool)
}

enum NFPrivateCloudZoneReadResult: Equatable, Sendable {
    case present
    /// A successful exact read proved that this zone is omitted.
    case absent
    case failed(redactedCode: String, retryable: Bool)
}

/// A narrow, injectable surface for deleting the app's allowlisted private
/// zones. Implementations must never accept an arbitrary zone name.
@MainActor
protocol NFPrivateCloudZoneDeletionClient: AnyObject {
    var containerIdentifier: String { get }

    func currentAccount() async -> NFPrivateCloudAccountProbeResult
    func deleteZones(
        _ zones: Set<NFPrivateCloudOwnedZone>
    ) async -> [NFPrivateCloudOwnedZone: NFPrivateCloudZoneDeleteResult]
    func readZones(
        _ zones: Set<NFPrivateCloudOwnedZone>
    ) async -> [NFPrivateCloudOwnedZone: NFPrivateCloudZoneReadResult]
}

/// Production CloudKit implementation. It is intentionally bound to one
/// container and always uses that container's private database.
@MainActor
final class NFCloudKitPrivateZoneDeletionClient: NFPrivateCloudZoneDeletionClient {
    let containerIdentifier: String

    private let database: CKDatabase
    private let defaults: UserDefaults

    init(
        containerIdentifier: String,
        defaults: UserDefaults = .standard
    ) {
        self.containerIdentifier = containerIdentifier
        self.defaults = defaults
        database = CKContainer(identifier: containerIdentifier).privateCloudDatabase
    }

    func currentAccount() async -> NFPrivateCloudAccountProbeResult {
        await NFPrivateCloudAccountProbe.check(
            containerIdentifier: containerIdentifier,
            defaults: defaults
        )
    }

    func deleteZones(
        _ zones: Set<NFPrivateCloudOwnedZone>
    ) async -> [NFPrivateCloudOwnedZone: NFPrivateCloudZoneDeleteResult] {
        guard zones.isSubset(of: Set(NFPrivateCloudOwnedZone.allCases)) else {
            return Dictionary(uniqueKeysWithValues: zones.map {
                ($0, .failed(redactedCode: "zone-not-allowlisted", retryable: false))
            })
        }

        let orderedZones = NFPrivateCloudOwnedZone.deletionOrder.filter(zones.contains)
        let ids = orderedZones.map(Self.zoneID)
        do {
            let result = try await database.modifyRecordZones(
                saving: [],
                deleting: ids
            )
            return Dictionary(uniqueKeysWithValues: orderedZones.map { zone in
                let id = Self.zoneID(zone)
                guard let perZone = result.deleteResults[id] else {
                    return (
                        zone,
                        .failed(redactedCode: "missing-delete-result", retryable: true)
                    )
                }
                switch perZone {
                case .success:
                    return (zone, .accepted)
                case let .failure(error):
                    if Self.isZoneNotFound(error) {
                        return (zone, .zoneNotFound)
                    }
                    let failure = NFCloudKitErrorMapper.map(error)
                    return (
                        zone,
                        .failed(
                            redactedCode: failure.redactedCode,
                            retryable: failure.isRetryable
                        )
                    )
                }
            })
        } catch {
            let failure = NFCloudKitErrorMapper.map(error)
            return Dictionary(uniqueKeysWithValues: orderedZones.map {
                (
                    $0,
                    .failed(
                        redactedCode: failure.redactedCode,
                        retryable: failure.isRetryable
                    )
                )
            })
        }
    }

    func readZones(
        _ zones: Set<NFPrivateCloudOwnedZone>
    ) async -> [NFPrivateCloudOwnedZone: NFPrivateCloudZoneReadResult] {
        guard zones.isSubset(of: Set(NFPrivateCloudOwnedZone.allCases)) else {
            return Dictionary(uniqueKeysWithValues: zones.map {
                ($0, .failed(redactedCode: "zone-not-allowlisted", retryable: false))
            })
        }

        let orderedZones = NFPrivateCloudOwnedZone.deletionOrder.filter(zones.contains)
        let ids = orderedZones.map(Self.zoneID)
        do {
            // This is an exact read of each allowlisted zone ID, not a generic
            // SwiftData import/export event or timestamp.
            let result = try await database.recordZones(for: ids)
            return Dictionary(uniqueKeysWithValues: orderedZones.map { zone in
                let id = Self.zoneID(zone)
                guard let perZone = result[id] else {
                    return (
                        zone,
                        .failed(redactedCode: "missing-read-result", retryable: true)
                    )
                }
                switch perZone {
                case .success:
                    return (zone, .present)
                case let .failure(error):
                    if Self.isZoneNotFound(error) {
                        return (zone, .absent)
                    }
                    let failure = NFCloudKitErrorMapper.map(error)
                    return (
                        zone,
                        .failed(
                            redactedCode: failure.redactedCode,
                            retryable: failure.isRetryable
                        )
                    )
                }
            })
        } catch {
            let failure = NFCloudKitErrorMapper.map(error)
            return Dictionary(uniqueKeysWithValues: orderedZones.map {
                (
                    $0,
                    .failed(
                        redactedCode: failure.redactedCode,
                        retryable: failure.isRetryable
                    )
                )
            })
        }
    }

    private static func zoneID(_ zone: NFPrivateCloudOwnedZone) -> CKRecordZone.ID {
        CKRecordZone.ID(
            zoneName: zone.rawValue,
            ownerName: CKCurrentUserDefaultName
        )
    }

    private static func isZoneNotFound(_ error: any Error) -> Bool {
        let nsError = error as NSError
        return nsError.domain == CKErrorDomain
            && nsError.code == CKError.zoneNotFound.rawValue
    }
}

/// The signed app manifest and runtime entitlements define the only container
/// in which the production workflow may operate. This policy intentionally
/// ignores the user's bootstrap toggle so a pending request can execute before
/// any ModelContainer exists on the next launch.
struct NFPrivateCloudCompleteDeletionPolicy: Equatable, Sendable {
    let containerIdentifier: String
    let requiredZones: Set<NFPrivateCloudOwnedZone>

    init(validatedContainerIdentifier: String) {
        containerIdentifier = validatedContainerIdentifier
        requiredZones = Set(NFPrivateCloudOwnedZone.allCases)
    }

    static func current(bundle: Bundle = .main) -> Self? {
        guard
            let requested = (
                bundle.object(forInfoDictionaryKey: "NFCloudKitContainerIdentifier") as? String
            )?.trimmingCharacters(in: .whitespacesAndNewlines),
            !requested.isEmpty
        else {
            return nil
        }
        let configured = Set(
            bundle.object(
                forInfoDictionaryKey: "NFEntitledCloudKitContainerIdentifiers"
            ) as? [String] ?? []
        )
        let entitlements = NFRuntimeEntitlementReader.snapshot(bundle: bundle)
        guard configured.contains(requested),
              entitlements.permitsCloudKit,
              entitlements.containerIdentifiers.contains(requested) else {
            return nil
        }
        return Self(validatedContainerIdentifier: requested)
    }
}

enum NFPrivateCloudPersistedZoneDeleteStatus: Codable, Equatable, Sendable {
    case notAttempted
    case accepted(at: Date)
    case zoneNotFound(at: Date)
    case failed(redactedCode: String, retryable: Bool, at: Date)
}

enum NFPrivateCloudPersistedZoneReadStatus: Codable, Equatable, Sendable {
    case notChecked
    case present(checkedAt: Date)
    case absent(checkedAt: Date)
    case failed(redactedCode: String, retryable: Bool, checkedAt: Date)
}

struct NFPrivateCloudZoneDeletionState: Codable, Equatable, Sendable {
    let zone: NFPrivateCloudOwnedZone
    var deletion: NFPrivateCloudPersistedZoneDeleteStatus
    var readback: NFPrivateCloudPersistedZoneReadStatus

    init(zone: NFPrivateCloudOwnedZone) {
        self.zone = zone
        deletion = .notAttempted
        readback = .notChecked
    }

    var isVerifiedAbsent: Bool {
        if case .zoneNotFound = deletion { return true }
        if case .absent = readback { return true }
        return false
    }

    var firstFailure: NFPrivateCloudDeletionFailure? {
        if case let .failed(code, retryable, at) = readback {
            return NFPrivateCloudDeletionFailure(
                redactedCode: code,
                retryable: retryable,
                occurredAt: at
            )
        }
        if case let .failed(code, retryable, at) = deletion {
            return NFPrivateCloudDeletionFailure(
                redactedCode: code,
                retryable: retryable,
                occurredAt: at
            )
        }
        if case let .present(checkedAt) = readback {
            return NFPrivateCloudDeletionFailure(
                redactedCode: "zone-still-present",
                retryable: true,
                occurredAt: checkedAt
            )
        }
        return nil
    }
}

struct NFPrivateCloudDeletionFailure: Codable, Equatable, Sendable {
    let redactedCode: String
    let retryable: Bool
    let occurredAt: Date
}

struct NFPrivateCloudCompleteDeletionRequest: Codable, Equatable, Identifiable, Sendable {
    static let schemaVersion = 1

    let version: Int
    let id: UUID
    let containerIdentifier: String
    let accountFingerprint: String
    let requestedAt: Date
    var zones: [NFPrivateCloudZoneDeletionState]
    var lastFailure: NFPrivateCloudDeletionFailure?

    init(
        id: UUID,
        policy: NFPrivateCloudCompleteDeletionPolicy,
        accountFingerprint: String,
        requestedAt: Date
    ) {
        version = Self.schemaVersion
        self.id = id
        containerIdentifier = policy.containerIdentifier
        self.accountFingerprint = accountFingerprint
        self.requestedAt = requestedAt
        zones = NFPrivateCloudOwnedZone.deletionOrder.map(
            NFPrivateCloudZoneDeletionState.init(zone:)
        )
        lastFailure = nil
    }

    var isRemotelyVerified: Bool {
        zones.count == NFPrivateCloudOwnedZone.allCases.count
            && zones.allSatisfy(\.isVerifiedAbsent)
    }

    func state(for zone: NFPrivateCloudOwnedZone) -> NFPrivateCloudZoneDeletionState? {
        zones.first { $0.zone == zone }
    }

    mutating func update(
        _ zone: NFPrivateCloudOwnedZone,
        _ body: (inout NFPrivateCloudZoneDeletionState) -> Void
    ) {
        guard let index = zones.firstIndex(where: { $0.zone == zone }) else { return }
        body(&zones[index])
    }

    func isValid(for policy: NFPrivateCloudCompleteDeletionPolicy) -> Bool {
        version == Self.schemaVersion
            && containerIdentifier == policy.containerIdentifier
            && Self.isValidFingerprint(accountFingerprint)
            && zones.count == policy.requiredZones.count
            && Set(zones.map(\.zone)) == policy.requiredZones
    }

    static func isValidFingerprint(_ value: String) -> Bool {
        value.utf8.count == 64 && value.utf8.allSatisfy {
            (48 ... 57).contains($0) || (97 ... 102).contains($0)
        }
    }
}

struct NFPrivateCloudCompleteDeletionReceipt: Codable, Equatable, Identifiable, Sendable {
    static let schemaVersion = 1

    let version: Int
    let id: UUID
    let requestID: UUID
    let containerIdentifier: String
    let accountFingerprint: String
    let requestedAt: Date
    let verifiedAt: Date
    let zones: [NFPrivateCloudZoneDeletionState]

    init(request: NFPrivateCloudCompleteDeletionRequest, verifiedAt: Date) {
        version = Self.schemaVersion
        id = UUID()
        requestID = request.id
        containerIdentifier = request.containerIdentifier
        accountFingerprint = request.accountFingerprint
        requestedAt = request.requestedAt
        self.verifiedAt = verifiedAt
        zones = request.zones
    }

    func isValid(
        for policy: NFPrivateCloudCompleteDeletionPolicy,
        request: NFPrivateCloudCompleteDeletionRequest
    ) -> Bool {
        version == Self.schemaVersion
            && requestID == request.id
            && containerIdentifier == policy.containerIdentifier
            && accountFingerprint == request.accountFingerprint
            && requestedAt == request.requestedAt
            && zones == request.zones
            && request.isRemotelyVerified
    }
}

@MainActor
protocol NFPrivateCloudDeletionStateStoring: AnyObject {
    var hasPersistedRequest: Bool { get }

    func loadRequest() throws -> NFPrivateCloudCompleteDeletionRequest?
    func saveRequest(_ request: NFPrivateCloudCompleteDeletionRequest) throws
    func loadReceipt() throws -> NFPrivateCloudCompleteDeletionReceipt?
    func saveReceipt(_ receipt: NFPrivateCloudCompleteDeletionReceipt) throws
    func clear() throws
}

enum NFPrivateCloudDeletionStateStoreError: Error, Equatable, Sendable {
    case unreadableRequest
    case unreadableReceipt
    case persistenceVerificationFailed
}

@MainActor
final class NFUserDefaultsPrivateCloudDeletionStateStore: NFPrivateCloudDeletionStateStoring {
    static let requestKey = "nf.private-cloud.complete-deletion.request.v1"
    static let receiptKey = "nf.private-cloud.complete-deletion.receipt.v1"

    private let defaults: UserDefaults
    private let encoder: JSONEncoder
    private let decoder = JSONDecoder()

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
    }

    var hasPersistedRequest: Bool {
        defaults.object(forKey: Self.requestKey) != nil
    }

    func loadRequest() throws -> NFPrivateCloudCompleteDeletionRequest? {
        guard let data = defaults.data(forKey: Self.requestKey) else { return nil }
        guard let request = try? decoder.decode(
            NFPrivateCloudCompleteDeletionRequest.self,
            from: data
        ) else {
            throw NFPrivateCloudDeletionStateStoreError.unreadableRequest
        }
        return request
    }

    func saveRequest(_ request: NFPrivateCloudCompleteDeletionRequest) throws {
        let data = try encoder.encode(request)
        defaults.set(data, forKey: Self.requestKey)
        guard try loadRequest() == request else {
            throw NFPrivateCloudDeletionStateStoreError.persistenceVerificationFailed
        }
    }

    func loadReceipt() throws -> NFPrivateCloudCompleteDeletionReceipt? {
        guard let data = defaults.data(forKey: Self.receiptKey) else { return nil }
        guard let receipt = try? decoder.decode(
            NFPrivateCloudCompleteDeletionReceipt.self,
            from: data
        ) else {
            throw NFPrivateCloudDeletionStateStoreError.unreadableReceipt
        }
        return receipt
    }

    func saveReceipt(_ receipt: NFPrivateCloudCompleteDeletionReceipt) throws {
        let data = try encoder.encode(receipt)
        defaults.set(data, forKey: Self.receiptKey)
        guard try loadReceipt() == receipt else {
            throw NFPrivateCloudDeletionStateStoreError.persistenceVerificationFailed
        }
    }

    func clear() throws {
        defaults.removeObject(forKey: Self.receiptKey)
        defaults.removeObject(forKey: Self.requestKey)
        guard defaults.object(forKey: Self.receiptKey) == nil,
              defaults.object(forKey: Self.requestKey) == nil else {
            throw NFPrivateCloudDeletionStateStoreError.persistenceVerificationFailed
        }
    }
}

enum NFPrivateCloudCompleteDeletionError: Error, Equatable, LocalizedError, Sendable {
    case policyUnavailable
    case clientContainerMismatch
    case accountUnavailable(redactedCode: String)
    case accountMismatch
    case existingRequestMismatch
    case localCleanupPending
    case localPurgeNotStaged
    case invalidPersistentState
    case statePersistenceFailed

    var errorDescription: String? {
        switch self {
        case .policyUnavailable:
            NFAppLocalization.localized(
                "The signed private-iCloud deletion capability is unavailable. Nothing was deleted.",
                locale: NFAppLocalization.preferredLocale,
                comment: "Complete private-iCloud deletion failure when the signed capability is unavailable."
            )
        case .clientContainerMismatch, .existingRequestMismatch, .invalidPersistentState:
            NFAppLocalization.localized(
                "The saved deletion request could not be matched exactly. Nothing was deleted.",
                locale: NFAppLocalization.preferredLocale,
                comment: "Complete private-iCloud deletion failure when durable request identity cannot be matched exactly."
            )
        case .accountUnavailable:
            NFAppLocalization.localized(
                "The iCloud account could not be verified. Nothing was deleted; retry after iCloud is available.",
                locale: NFAppLocalization.preferredLocale,
                comment: "Complete private-iCloud deletion failure when the account cannot be verified."
            )
        case .accountMismatch:
            NFAppLocalization.localized(
                "The iCloud account changed after this deletion was requested. Nothing was deleted from the current account.",
                locale: NFAppLocalization.preferredLocale,
                comment: "Complete private-iCloud deletion failure after an account identity change."
            )
        case .localCleanupPending:
            NFAppLocalization.localized(
                "Private iCloud deletion is verified. Finish the saved local cleanup before starting another request.",
                locale: NFAppLocalization.preferredLocale,
                comment: "Complete private-iCloud deletion status while verified device cleanup remains pending."
            )
        case .localPurgeNotStaged:
            NFAppLocalization.localized(
                "The saved cloud request is not bound to a verified device-cleanup intent. Nothing was deleted. Retry staging from the original launch.",
                locale: NFAppLocalization.preferredLocale,
                comment: "Complete private-iCloud deletion failure when the matching local purge was not durably staged."
            )
        case .statePersistenceFailed:
            NFAppLocalization.localized(
                "The deletion request could not be saved and verified. Nothing was deleted.",
                locale: NFAppLocalization.preferredLocale,
                comment: "Complete private-iCloud deletion failure when request state cannot be saved and verified."
            )
        }
    }
}

enum NFPrivateCloudPreContainerCleanupComponent: String, Codable, CaseIterable, Equatable, Sendable {
    case backgroundTasks
    case notifications
    case spotlightIndex
    case managedDocuments
    case presentationCache
    case authoringCache
    case preparedExports
    case storeRecoveryPackages
    case widgetSnapshot
    case allowlistedDefaults
    case structuredStores

    static let cleanupOrder: [Self] = [
        .backgroundTasks,
        .notifications,
        .spotlightIndex,
        .managedDocuments,
        .presentationCache,
        .authoringCache,
        .preparedExports,
        .storeRecoveryPackages,
        .widgetSnapshot,
        .allowlistedDefaults,
        // Identity-bound structured stores and the fingerprint salt are the
        // final destructive boundary, after every retryable external surface.
        .structuredStores
    ]
}

struct NFPrivateCloudPreContainerCleanupProgress: Codable, Equatable, Sendable {
    static let schemaVersion = 1

    let version: Int
    let requestID: UUID
    var completedComponents: [NFPrivateCloudPreContainerCleanupComponent]
    var lastFailure: NFPrivateCloudDeletionFailure?

    init(requestID: UUID) {
        version = Self.schemaVersion
        self.requestID = requestID
        completedComponents = []
        lastFailure = nil
    }

    mutating func recordCompleted(_ component: NFPrivateCloudPreContainerCleanupComponent) {
        if !completedComponents.contains(component) {
            completedComponents.append(component)
        }
        lastFailure = nil
    }

    var isComplete: Bool {
        completedComponents == NFPrivateCloudPreContainerCleanupComponent.cleanupOrder
    }
}

struct NFPrivateCloudCompleteDeletionCompletion: Codable, Equatable, Identifiable, Sendable {
    static let schemaVersion = 1

    let version: Int
    let id: UUID
    let requestID: UUID
    let remoteReceiptID: UUID
    let remoteVerifiedAt: Date
    let localVerifiedAt: Date

    init(
        requestID: UUID,
        remoteReceiptID: UUID,
        remoteVerifiedAt: Date,
        localVerifiedAt: Date
    ) {
        version = Self.schemaVersion
        id = UUID()
        self.requestID = requestID
        self.remoteReceiptID = remoteReceiptID
        self.remoteVerifiedAt = remoteVerifiedAt
        self.localVerifiedAt = localVerifiedAt
    }
}

@MainActor
protocol NFPrivateCloudPreContainerCleanupStateStoring: AnyObject {
    func loadProgress() throws -> NFPrivateCloudPreContainerCleanupProgress?
    func saveProgress(_ progress: NFPrivateCloudPreContainerCleanupProgress) throws
    func clearProgress() throws
    func loadCompletion() throws -> NFPrivateCloudCompleteDeletionCompletion?
    func saveCompletion(_ completion: NFPrivateCloudCompleteDeletionCompletion) throws
    func clearCompletion() throws
}

@MainActor
final class NFUserDefaultsPrivateCloudPreContainerCleanupStateStore:
    NFPrivateCloudPreContainerCleanupStateStoring
{
    static let progressKey = "nf.private-cloud.complete-deletion.local-progress.v1"
    static let completionKey = "nf.private-cloud.complete-deletion.completion.v1"

    private let defaults: UserDefaults
    private let encoder: JSONEncoder
    private let decoder = JSONDecoder()

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
    }

    func loadProgress() throws -> NFPrivateCloudPreContainerCleanupProgress? {
        try decode(NFPrivateCloudPreContainerCleanupProgress.self, key: Self.progressKey)
    }

    func saveProgress(_ progress: NFPrivateCloudPreContainerCleanupProgress) throws {
        try save(progress, key: Self.progressKey)
        guard try loadProgress() == progress else {
            throw NFPrivateCloudDeletionStateStoreError.persistenceVerificationFailed
        }
    }

    func clearProgress() throws {
        try clear(Self.progressKey)
    }

    func loadCompletion() throws -> NFPrivateCloudCompleteDeletionCompletion? {
        try decode(NFPrivateCloudCompleteDeletionCompletion.self, key: Self.completionKey)
    }

    func saveCompletion(_ completion: NFPrivateCloudCompleteDeletionCompletion) throws {
        try save(completion, key: Self.completionKey)
        guard try loadCompletion() == completion else {
            throw NFPrivateCloudDeletionStateStoreError.persistenceVerificationFailed
        }
    }

    func clearCompletion() throws {
        try clear(Self.completionKey)
    }

    private func decode<Value: Decodable>(_ type: Value.Type, key: String) throws -> Value? {
        guard let data = defaults.data(forKey: key) else { return nil }
        do {
            return try decoder.decode(type, from: data)
        } catch {
            throw NFPrivateCloudDeletionStateStoreError.unreadableReceipt
        }
    }

    private func save<Value: Encodable>(_ value: Value, key: String) throws {
        defaults.set(try encoder.encode(value), forKey: key)
        guard defaults.object(forKey: key) != nil else {
            throw NFPrivateCloudDeletionStateStoreError.persistenceVerificationFailed
        }
    }

    private func clear(_ key: String) throws {
        defaults.removeObject(forKey: key)
        guard defaults.object(forKey: key) == nil else {
            throw NFPrivateCloudDeletionStateStoreError.persistenceVerificationFailed
        }
    }
}

@MainActor
protocol NFPrivateCloudPreContainerCleanupClient: AnyObject {
    func removeAndVerify(
        _ component: NFPrivateCloudPreContainerCleanupComponent,
        requestID: UUID
    ) async throws

    func consumeStructuredStorePurgeReceipt(requestID: UUID) -> Bool
}

private enum NFPrivateCloudPreContainerCleanupError: Error {
    case managedDocumentsRemain
    case widgetSnapshotRemains
    case authoringCacheRemains
    case structuredStorePurgeUnverified
}

enum NFApplicationPrivacyArtifactCleaner {
    static let allowlistedDefaultsKeys: Set<String> = [
        "nf.system.notifications.preferences.v1",
        "nf.system.spotlight.consent.v1",
        "nf.system.spotlight.indexed-chunks.v1",
        "nf.sync.structured.last-import.v1",
        "nf.sync.structured.last-export.v1",
        "nf.sync.structured.pending-local-write.v1",
        "nf.sync.structured.deletion-requested.v1",
        "nf.sync.structured.deletion-verified.v1",
        "nf.onboarding.step",
        "nf.onboarding.draft",
        NFShortcutAuthoringConfiguration.setupVerifiedDefaultsKey,
        NFShortcutAuthoringConfiguration.setupVersionDefaultsKey,
        NFShortcutAuthoringConfiguration.installPageVisitedDefaultsKey,
        NFShortcutAuthoringConfiguration.installPageVisitedVersionDefaultsKey,
        NFShortcutAuthoringConfiguration.callbackRequestIDDefaultsKey,
        NFShortcutAuthoringConfiguration.callbackNonceDefaultsKey,
        NFShortcutAuthoringConfiguration.callbackKindDefaultsKey,
        NFShortcutAuthoringConfiguration.callbackPayloadDefaultsKey,
        NFShortcutAuthoringConfiguration.callbackQueueDefaultsKey,
        NFAppLocalization.preferredLanguageDefaultsKey
    ]

    static func removeAllowlistedDefaults(
        defaults: UserDefaults = .standard
    ) throws {
        for key in allowlistedDefaultsKeys {
            defaults.removeObject(forKey: key)
        }
        try NeuroForgeShortcutHandoff.clearAllState(defaults: defaults)
        guard allowlistedDefaultsKeys.allSatisfy({ defaults.object(forKey: $0) == nil }) else {
            throw CocoaError(.fileWriteUnknown)
        }
    }

    static func removeStoreRecoveryPackages(
        fileManager: FileManager = .default,
        temporaryDirectory: URL? = nil
    ) throws {
        let root = temporaryDirectory ?? fileManager.temporaryDirectory
        let candidates = try fileManager.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ).filter {
            $0.lastPathComponent.hasPrefix(NFStoreRecoveryService.packageFolderName)
        }
        for candidate in candidates {
            try fileManager.removeItem(at: candidate)
        }
        let remaining = try fileManager.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )
        guard !remaining.contains(where: {
            $0.lastPathComponent.hasPrefix(NFStoreRecoveryService.packageFolderName)
        }) else {
            throw CocoaError(.fileWriteUnknown)
        }
    }
}

@MainActor
final class NFApplicationPrivateCloudPreContainerCleanupClient:
    NFPrivateCloudPreContainerCleanupClient
{
    private let defaults: UserDefaults
    private let fileManager: FileManager
    private let applicationSupportURL: URL?
    private let temporaryDirectory: URL?
    private let notificationCoordinator: NFNotificationOptInCoordinator
    private let spotlightClient: any NFSpotlightIndexClient
    private let backgroundScheduler: NFBGTaskSchedulerAdapter

    init(
        defaults: UserDefaults = .standard,
        fileManager: FileManager = .default,
        applicationSupportURL: URL? = nil,
        temporaryDirectory: URL? = nil,
        notificationClient: (any NFNotificationCenterClient)? = nil,
        spotlightClient: (any NFSpotlightIndexClient)? = nil
    ) {
        self.defaults = defaults
        self.fileManager = fileManager
        self.applicationSupportURL = applicationSupportURL
        self.temporaryDirectory = temporaryDirectory
        notificationCoordinator = NFNotificationOptInCoordinator(
            client: notificationClient ?? NFUserNotificationCenterAdapter()
        )
        self.spotlightClient = spotlightClient ?? NFCoreSpotlightIndexAdapter()
        backgroundScheduler = NFBGTaskSchedulerAdapter()
    }

    func removeAndVerify(
        _ component: NFPrivateCloudPreContainerCleanupComponent,
        requestID: UUID
    ) async throws {
        switch component {
        case .backgroundTasks:
            for kind in NFBackgroundTaskKind.allCases {
                backgroundScheduler.cancel(kind)
            }
        case .notifications:
            try await notificationCoordinator.removeAllManagedSchedules()
        case .spotlightIndex:
            try await spotlightClient.apply(NFSpotlightIndexPlanner.planGlobalDisable())
        case .managedDocuments:
            let root = try supportURL().appending(
                path: "NeuroForge/Documents",
                directoryHint: .isDirectory
            )
            if fileManager.fileExists(atPath: root.path) {
                try fileManager.removeItem(at: root)
            }
            guard !fileManager.fileExists(atPath: root.path) else {
                throw NFPrivateCloudPreContainerCleanupError.managedDocumentsRemain
            }
        case .presentationCache:
            try NFNextDayEnhancementCache.shared.removeAllVerifying()
        case .authoringCache:
            await NFAuthoringEngine.shared.removeAllCachedResults()
            try NFShortcutAuthoringRequestStore.removeAllVerifying(
                fileManager: fileManager,
                applicationSupportURL: applicationSupportURL
            )
            guard await NFAuthoringEngine.shared.cachedResultCount() == 0 else {
                throw NFPrivateCloudPreContainerCleanupError.authoringCacheRemains
            }
        case .preparedExports:
            try NFDataExportService.removePreparedExports(
                fileManager: fileManager,
                temporaryDirectory: temporaryDirectory
            )
        case .storeRecoveryPackages:
            try NFApplicationPrivacyArtifactCleaner.removeStoreRecoveryPackages(
                fileManager: fileManager,
                temporaryDirectory: temporaryDirectory
            )
        case .widgetSnapshot:
            NFWidgetSnapshotStore.delete()
            guard NFWidgetSnapshotStore.read() == nil else {
                throw NFPrivateCloudPreContainerCleanupError.widgetSnapshotRemains
            }
        case .allowlistedDefaults:
            try NFApplicationPrivacyArtifactCleaner.removeAllowlistedDefaults(
                defaults: defaults
            )
        case .structuredStores:
            let result = NFPrivateCloudStoreIdentityResolver
                .performPendingLocalPurgeBeforeOpeningContainer(
                    requiredRequestID: requestID,
                    defaults: defaults,
                    fileManager: fileManager,
                    applicationSupportURL: applicationSupportURL
                )
            guard result == .completed
                    || NFPrivateCloudStoreIdentityResolver.hasVerifiedLocalPurgeReceipt(
                        requestID: requestID,
                        defaults: defaults
                    ) else {
                throw NFPrivateCloudPreContainerCleanupError.structuredStorePurgeUnverified
            }
        }
    }

    func consumeStructuredStorePurgeReceipt(requestID: UUID) -> Bool {
        NFPrivateCloudStoreIdentityResolver.consumeVerifiedLocalPurgeReceipt(
            requestID: requestID,
            defaults: defaults
        )
    }

    private func supportURL() throws -> URL {
        if let applicationSupportURL { return applicationSupportURL }
        return try NFPersistentStoreLocation.applicationSupportDirectory(
            fileManager: fileManager
        )
    }
}

enum NFPrivateCloudDeletionStartupOutcome: Equatable, Sendable {
    case noRequest
    case unfinished(NFPrivateCloudCompleteDeletionRequest)
    case verified(NFPrivateCloudCompleteDeletionReceipt)
    case completed(NFPrivateCloudCompleteDeletionCompletion)
    case failed(redactedCode: String, retryable: Bool)

    var requiresLocalOnlyLaunch: Bool {
        switch self {
        case .noRequest, .completed: false
        case .unfinished, .verified, .failed: true
        }
    }
}

/// Durable two-launch complete-deletion transaction.
///
/// Launch 1 only saves an account/container-bound request and freezes private
/// sync. Launch 2 executes here before any SwiftData/Core Data container is
/// created. Local cleanup is allowed only after a receipt proves both exact
/// zone IDs are absent.
@MainActor
enum NFPrivateCloudCompleteDeletionWorkflow {
    static func requestFromCloudBackedLaunch(
        containerIdentifier: String,
        bundle: Bundle = .main,
        defaults: UserDefaults = .standard,
        requestedAt: Date = Date(),
        requestID: UUID = UUID()
    ) async throws -> NFPrivateCloudCompleteDeletionRequest {
        guard let policy = NFPrivateCloudCompleteDeletionPolicy.current(bundle: bundle),
              policy.containerIdentifier == containerIdentifier else {
            throw NFPrivateCloudCompleteDeletionError.policyUnavailable
        }
        let client = NFCloudKitPrivateZoneDeletionClient(
            containerIdentifier: containerIdentifier,
            defaults: defaults
        )
        let stateStore = NFUserDefaultsPrivateCloudDeletionStateStore(defaults: defaults)
        return try await request(
            policy: policy,
            defaults: defaults,
            stateStore: stateStore,
            client: client,
            requestedAt: requestedAt,
            requestID: requestID
        )
    }

    static func request(
        policy: NFPrivateCloudCompleteDeletionPolicy,
        defaults: UserDefaults,
        stateStore: any NFPrivateCloudDeletionStateStoring,
        client: any NFPrivateCloudZoneDeletionClient,
        requestedAt: Date = Date(),
        requestID: UUID = UUID()
    ) async throws -> NFPrivateCloudCompleteDeletionRequest {
        guard client.containerIdentifier == policy.containerIdentifier else {
            throw NFPrivateCloudCompleteDeletionError.clientContainerMismatch
        }
        if try loadReceipt(from: stateStore) != nil {
            throw NFPrivateCloudCompleteDeletionError.localCleanupPending
        }

        let fingerprint = try await verifiedFingerprint(client: client)
        if let existing = try loadRequest(from: stateStore) {
            guard existing.isValid(for: policy),
                  existing.accountFingerprint == fingerprint else {
                throw NFPrivateCloudCompleteDeletionError.existingRequestMismatch
            }
            NFPrivateSyncBootstrapPreference.lockForCloudDeletion(defaults: defaults)
            return existing
        }

        let request = NFPrivateCloudCompleteDeletionRequest(
            id: requestID,
            policy: policy,
            accountFingerprint: fingerprint,
            requestedAt: requestedAt
        )
        do {
            try stateStore.saveRequest(request)
            guard try stateStore.loadRequest() == request else {
                throw NFPrivateCloudDeletionStateStoreError.persistenceVerificationFailed
            }
        } catch {
            throw NFPrivateCloudCompleteDeletionError.statePersistenceFailed
        }
        // The request is durable before the next-launch sync preference is
        // frozen. Startup repeats this lock before any remote operation.
        NFPrivateSyncBootstrapPreference.lockForCloudDeletion(defaults: defaults)
        return request
    }

    /// Production entry point intended to run before ModelContainer creation.
    static func executePendingRequestBeforeModelContainer(
        bundle: Bundle = .main,
        defaults: UserDefaults = .standard,
        now: Date = Date()
    ) async -> NFPrivateCloudDeletionStartupOutcome {
        let stateStore = NFUserDefaultsPrivateCloudDeletionStateStore(defaults: defaults)
        let cleanupStateStore = NFUserDefaultsPrivateCloudPreContainerCleanupStateStore(
            defaults: defaults
        )
        let cleanupClient = NFApplicationPrivateCloudPreContainerCleanupClient(
            defaults: defaults
        )
        let savedCompletion: NFPrivateCloudCompleteDeletionCompletion?
        do {
            savedCompletion = try cleanupStateStore.loadCompletion()
        } catch {
            return .failed(redactedCode: "local-state-invalid", retryable: false)
        }

        // A completion marker is written only after every local surface is
        // verified. It precedes cloud-request finalization so a crash in that
        // narrow window can finish the transaction without repeating deletion
        // or losing the success acknowledgement.
        if let savedCompletion {
            do {
                guard savedCompletion.version
                        == NFPrivateCloudCompleteDeletionCompletion.schemaVersion else {
                    throw NFPrivateCloudCompleteDeletionError.invalidPersistentState
                }
                if stateStore.hasPersistedRequest {
                    guard let request = try stateStore.loadRequest(),
                          let receipt = try stateStore.loadReceipt(),
                          request.id == savedCompletion.requestID,
                          receipt.id == savedCompletion.remoteReceiptID,
                          NFPrivateCloudStoreIdentityResolver.hasVerifiedLocalPurgeReceipt(
                              requestID: request.id,
                              defaults: defaults
                          ) else {
                        throw NFPrivateCloudCompleteDeletionError.invalidPersistentState
                    }
                    try finishAfterVerifiedLocalCleanup(
                        receiptID: receipt.id,
                        defaults: defaults,
                        stateStore: stateStore
                    )
                } else if try stateStore.loadReceipt() != nil {
                    throw NFPrivateCloudCompleteDeletionError.invalidPersistentState
                }
                NFPrivateSyncBootstrapPreference.set(false, defaults: defaults)
                NFPrivateSyncBootstrapPreference.unlockAfterCloudDeletion(defaults: defaults)
                _ = cleanupClient.consumeStructuredStorePurgeReceipt(
                    requestID: savedCompletion.requestID
                )
                try? cleanupStateStore.clearProgress()
                return .completed(savedCompletion)
            } catch let error as NFPrivateCloudCompleteDeletionError {
                return .failed(
                    redactedCode: error.redactedCode,
                    retryable: error.isRetryable
                )
            } catch {
                return .failed(redactedCode: "state-finalization-failed", retryable: true)
            }
        }

        guard stateStore.hasPersistedRequest else {
            if (try? stateStore.loadReceipt()) != nil {
                NFPrivateSyncBootstrapPreference.lockForCloudDeletion(defaults: defaults)
                return .failed(redactedCode: "state-invalid", retryable: false)
            }
            if NFPrivateSyncBootstrapPreference.isCloudDeletionLocked(defaults: defaults) {
                // A crash after finalization may leave only the workflow lock.
                // Keep the raw preference off, release the orphan lock, and
                // force this launch to remain local-only. No remote mutation
                // is attempted without the durable account-bound request.
                NFPrivateSyncBootstrapPreference.set(false, defaults: defaults)
                NFPrivateSyncBootstrapPreference.unlockAfterCloudDeletion(defaults: defaults)
                return .noRequest
            }
            return .noRequest
        }

        // Fail closed even when the saved payload is corrupt or the signed
        // policy is temporarily unavailable. A cloud-backed store must not be
        // opened while the destructive transaction is unresolved.
        NFPrivateSyncBootstrapPreference.lockForCloudDeletion(defaults: defaults)
        guard let pendingRequest = try? stateStore.loadRequest() else {
            return .failed(redactedCode: "state-invalid", retryable: false)
        }
        // Launch 1 must durably bind the pre-container local purge to the same
        // request UUID before startup may even read, and therefore before it
        // may delete, either CloudKit zone. A crash between request persistence
        // and staging remains a recoverable blocked transaction.
        if !NFPrivateCloudStoreIdentityResolver.hasStagedLocalPurge(
            requestID: pendingRequest.id,
            defaults: defaults
        ) && !NFPrivateCloudStoreIdentityResolver.hasVerifiedLocalPurgeReceipt(
            requestID: pendingRequest.id,
            defaults: defaults
        ) {
            do {
                _ = try NFPrivateCloudStoreIdentityResolver.repairOrStageLocalPurge(
                    requestID: pendingRequest.id,
                    defaults: defaults
                )
            } catch {
                return .failed(redactedCode: "local-purge-not-staged", retryable: true)
            }
            guard NFPrivateCloudStoreIdentityResolver.hasStagedLocalPurge(
                requestID: pendingRequest.id,
                defaults: defaults
            ) else {
                return .failed(redactedCode: "local-purge-not-staged", retryable: true)
            }
        }
        guard let policy = NFPrivateCloudCompleteDeletionPolicy.current(bundle: bundle) else {
            return .failed(redactedCode: "policy-unavailable", retryable: false)
        }
        let client = NFCloudKitPrivateZoneDeletionClient(
            containerIdentifier: policy.containerIdentifier,
            defaults: defaults
        )
        do {
            let remoteOutcome = try await executePendingRequestBeforeModelContainer(
                policy: policy,
                defaults: defaults,
                stateStore: stateStore,
                client: client,
                now: now
            )
            guard case let .verified(receipt) = remoteOutcome else {
                return remoteOutcome
            }
            return try await finishVerifiedRequestBeforeModelContainer(
                receipt: receipt,
                defaults: defaults,
                stateStore: stateStore,
                cleanupStateStore: cleanupStateStore,
                cleanupClient: cleanupClient,
                now: now
            )
        } catch let error as NFPrivateCloudCompleteDeletionError {
            return .failed(
                redactedCode: error.redactedCode,
                retryable: error.isRetryable
            )
        } catch {
            return .failed(redactedCode: "state-unavailable", retryable: true)
        }
    }

    /// Deterministic cleanup/finalization seam used by startup and focused
    /// tests. Every component is deliberately invoked again on retry even when
    /// it appears in the ledger; the app is blocked at this boundary and the
    /// idempotent re-verification prevents an extension or interrupted process
    /// from recreating a surface between attempts.
    static func finishVerifiedRequestBeforeModelContainer(
        receipt: NFPrivateCloudCompleteDeletionReceipt,
        defaults: UserDefaults,
        stateStore: any NFPrivateCloudDeletionStateStoring,
        cleanupStateStore: any NFPrivateCloudPreContainerCleanupStateStoring,
        cleanupClient: any NFPrivateCloudPreContainerCleanupClient,
        now: Date = Date()
    ) async throws -> NFPrivateCloudDeletionStartupOutcome {
        guard let request = try loadRequest(from: stateStore),
              let persistedReceipt = try loadReceipt(from: stateStore),
              persistedReceipt == receipt,
              receipt.requestID == request.id,
              request.isRemotelyVerified else {
            throw NFPrivateCloudCompleteDeletionError.invalidPersistentState
        }

        var progress: NFPrivateCloudPreContainerCleanupProgress
        do {
            if let existing = try cleanupStateStore.loadProgress() {
                guard existing.version == NFPrivateCloudPreContainerCleanupProgress.schemaVersion,
                      existing.requestID == request.id else {
                    throw NFPrivateCloudCompleteDeletionError.invalidPersistentState
                }
                progress = existing
            } else {
                progress = NFPrivateCloudPreContainerCleanupProgress(requestID: request.id)
                try cleanupStateStore.saveProgress(progress)
            }
        } catch let error as NFPrivateCloudCompleteDeletionError {
            throw error
        } catch {
            throw NFPrivateCloudCompleteDeletionError.statePersistenceFailed
        }

        for component in NFPrivateCloudPreContainerCleanupComponent.cleanupOrder {
            do {
                try await cleanupClient.removeAndVerify(
                    component,
                    requestID: request.id
                )
                progress.recordCompleted(component)
                try cleanupStateStore.saveProgress(progress)
            } catch {
                progress.lastFailure = NFPrivateCloudDeletionFailure(
                    redactedCode: "local-cleanup-\(component.rawValue)",
                    retryable: true,
                    occurredAt: now
                )
                try? cleanupStateStore.saveProgress(progress)
                return .failed(
                    redactedCode: "local-cleanup-\(component.rawValue)",
                    retryable: true
                )
            }
        }
        guard progress.isComplete else {
            return .failed(redactedCode: "local-cleanup-incomplete", retryable: true)
        }

        let completion: NFPrivateCloudCompleteDeletionCompletion
        do {
            if let existing = try cleanupStateStore.loadCompletion() {
                guard existing.version == NFPrivateCloudCompleteDeletionCompletion.schemaVersion,
                      existing.requestID == request.id,
                      existing.remoteReceiptID == receipt.id else {
                    throw NFPrivateCloudCompleteDeletionError.invalidPersistentState
                }
                completion = existing
            } else {
                completion = NFPrivateCloudCompleteDeletionCompletion(
                    requestID: request.id,
                    remoteReceiptID: receipt.id,
                    remoteVerifiedAt: receipt.verifiedAt,
                    localVerifiedAt: now
                )
                try cleanupStateStore.saveCompletion(completion)
            }
        } catch let error as NFPrivateCloudCompleteDeletionError {
            throw error
        } catch {
            throw NFPrivateCloudCompleteDeletionError.statePersistenceFailed
        }

        try finishAfterVerifiedLocalCleanup(
            receiptID: receipt.id,
            defaults: defaults,
            stateStore: stateStore
        )
        _ = cleanupClient.consumeStructuredStorePurgeReceipt(requestID: request.id)
        try? cleanupStateStore.clearProgress()
        return .completed(completion)
    }

    /// Clears only the non-sensitive success marker after the launch UI has
    /// shown the verified private-cloud-and-device result.
    @discardableResult
    static func acknowledgeCompletion(
        id: UUID,
        defaults: UserDefaults = .standard
    ) -> Bool {
        let deletionStore = NFUserDefaultsPrivateCloudDeletionStateStore(defaults: defaults)
        let cleanupStore = NFUserDefaultsPrivateCloudPreContainerCleanupStateStore(
            defaults: defaults
        )
        guard !deletionStore.hasPersistedRequest,
              (try? deletionStore.loadReceipt()) == nil,
              !NFPrivateSyncBootstrapPreference.isCloudDeletionLocked(defaults: defaults),
              let completion = try? cleanupStore.loadCompletion(),
              completion.id == id else {
            return false
        }
        do {
            try cleanupStore.clearProgress()
            try cleanupStore.clearCompletion()
            return try cleanupStore.loadCompletion() == nil
        } catch {
            return false
        }
    }

    static func executePendingRequestBeforeModelContainer(
        policy: NFPrivateCloudCompleteDeletionPolicy,
        defaults: UserDefaults,
        stateStore: any NFPrivateCloudDeletionStateStoring,
        client: any NFPrivateCloudZoneDeletionClient,
        localPurgeBindingVerified: Bool = true,
        now: Date = Date()
    ) async throws -> NFPrivateCloudDeletionStartupOutcome {
        guard localPurgeBindingVerified else {
            throw NFPrivateCloudCompleteDeletionError.localPurgeNotStaged
        }
        if let receipt = try loadReceipt(from: stateStore) {
            guard let request = try loadRequest(from: stateStore),
                  receipt.isValid(for: policy, request: request) else {
                throw NFPrivateCloudCompleteDeletionError.invalidPersistentState
            }
            NFPrivateSyncBootstrapPreference.lockForCloudDeletion(defaults: defaults)
            return .verified(receipt)
        }
        guard var request = try loadRequest(from: stateStore) else {
            return .noRequest
        }

        NFPrivateSyncBootstrapPreference.lockForCloudDeletion(defaults: defaults)
        guard client.containerIdentifier == policy.containerIdentifier else {
            throw NFPrivateCloudCompleteDeletionError.clientContainerMismatch
        }
        guard request.isValid(for: policy) else {
            throw NFPrivateCloudCompleteDeletionError.invalidPersistentState
        }

        if let accountFailure = await accountBindingFailure(
            request: request,
            client: client,
            now: now
        ) {
            request.lastFailure = accountFailure
            try persist(request, in: stateStore)
            return .unfinished(request)
        }

        request.lastFailure = nil
        let unresolved = Set(request.zones.filter { !$0.isVerifiedAbsent }.map(\.zone))
        guard !unresolved.isEmpty else {
            return try await finalizeRemoteVerification(
                request: request,
                policy: policy,
                stateStore: stateStore,
                client: client,
                verifiedAt: now
            )
        }

        // A complete exact-read preflight ensures an auth/network failure is
        // observed before either zone is mutated.
        let preflight = await client.readZones(unresolved)
        for zone in unresolved {
            applyReadResult(
                preflight[zone] ?? .failed(
                    redactedCode: "missing-read-result",
                    retryable: true
                ),
                to: zone,
                request: &request,
                at: now
            )
        }
        if let failure = request.zones.compactMap({ state -> NFPrivateCloudDeletionFailure? in
            guard unresolved.contains(state.zone),
                  case let .failed(code, retryable, checkedAt) = state.readback else {
                return nil
            }
            return NFPrivateCloudDeletionFailure(
                redactedCode: code,
                retryable: retryable,
                occurredAt: checkedAt
            )
        }).first {
            request.lastFailure = failure
            try persist(request, in: stateStore)
            return .unfinished(request)
        }

        try persist(request, in: stateStore)
        let presentZones = Set(request.zones.compactMap { state -> NFPrivateCloudOwnedZone? in
            guard unresolved.contains(state.zone),
                  !state.isVerifiedAbsent,
                  case .present = state.readback else { return nil }
            return state.zone
        })
        guard !presentZones.isEmpty else {
            return try await finalizeRemoteVerification(
                request: request,
                policy: policy,
                stateStore: stateStore,
                client: client,
                verifiedAt: now
            )
        }

        // Re-check after the read preflight and immediately before mutation.
        // A switch in this window must never apply the old account's intent to
        // the newly signed-in account.
        if let accountFailure = await accountBindingFailure(
            request: request,
            client: client,
            now: now
        ) {
            request.lastFailure = accountFailure
            try persist(request, in: stateStore)
            return .unfinished(request)
        }

        let deletionResults = await client.deleteZones(presentZones)
        for zone in presentZones {
            applyDeleteResult(
                deletionResults[zone] ?? .failed(
                    redactedCode: "missing-delete-result",
                    retryable: true
                ),
                to: zone,
                request: &request,
                at: now
            )
        }
        try persist(request, in: stateStore)

        // Exact post-delete readback is required even when the delete call
        // returned success. A generic SwiftData event never reaches this path.
        let readback = await client.readZones(presentZones)
        for zone in presentZones {
            applyReadResult(
                readback[zone] ?? .failed(
                    redactedCode: "missing-read-result",
                    retryable: true
                ),
                to: zone,
                request: &request,
                at: now
            )
        }

        if request.isRemotelyVerified {
            request.lastFailure = nil
            return try await finalizeRemoteVerification(
                request: request,
                policy: policy,
                stateStore: stateStore,
                client: client,
                verifiedAt: now
            )
        }

        let failure = request.zones
            .filter { !$0.isVerifiedAbsent }
            .compactMap(\.firstFailure)
            .first
            ?? NFPrivateCloudDeletionFailure(
                redactedCode: "verification-incomplete",
                retryable: true,
                occurredAt: now
            )
        request.lastFailure = failure
        try persist(request, in: stateStore)
        return .unfinished(request)
    }

    static func verifiedReceipt(
        policy: NFPrivateCloudCompleteDeletionPolicy,
        stateStore: any NFPrivateCloudDeletionStateStoring
    ) throws -> NFPrivateCloudCompleteDeletionReceipt? {
        guard let receipt = try loadReceipt(from: stateStore) else { return nil }
        guard let request = try loadRequest(from: stateStore),
              receipt.isValid(for: policy, request: request) else {
            throw NFPrivateCloudCompleteDeletionError.invalidPersistentState
        }
        return receipt
    }

    /// Call only after local cleanup succeeds on the local-only launch.
    static func finishAfterVerifiedLocalCleanup(
        receiptID: UUID,
        defaults: UserDefaults,
        stateStore: any NFPrivateCloudDeletionStateStoring
    ) throws {
        guard let request = try loadRequest(from: stateStore),
              let receipt = try loadReceipt(from: stateStore),
              receipt.id == receiptID,
              receipt.requestID == request.id,
              request.isRemotelyVerified else {
            throw NFPrivateCloudCompleteDeletionError.invalidPersistentState
        }
        // Unlock before clearing the durable state. If clearing fails, the
        // still-present request causes startup to acquire the lock again. This
        // ordering avoids an unrecoverable orphan lock if the process exits
        // between the two operations.
        NFPrivateSyncBootstrapPreference.set(false, defaults: defaults)
        NFPrivateSyncBootstrapPreference.unlockAfterCloudDeletion(defaults: defaults)
        do {
            try stateStore.clear()
        } catch {
            throw NFPrivateCloudCompleteDeletionError.statePersistenceFailed
        }
    }

    private static func verifiedFingerprint(
        client: any NFPrivateCloudZoneDeletionClient
    ) async throws -> String {
        switch await client.currentAccount() {
        case let .available(fingerprint):
            guard NFPrivateCloudCompleteDeletionRequest.isValidFingerprint(fingerprint) else {
                throw NFPrivateCloudCompleteDeletionError.accountUnavailable(
                    redactedCode: "invalid-fingerprint"
                )
            }
            return fingerprint
        case .noAccount:
            throw NFPrivateCloudCompleteDeletionError.accountUnavailable(
                redactedCode: "account-unavailable"
            )
        case .restricted:
            throw NFPrivateCloudCompleteDeletionError.accountUnavailable(
                redactedCode: "account-restricted"
            )
        case .temporarilyUnavailable:
            throw NFPrivateCloudCompleteDeletionError.accountUnavailable(
                redactedCode: "account-temporary"
            )
        case .couldNotDetermine:
            throw NFPrivateCloudCompleteDeletionError.accountUnavailable(
                redactedCode: "account-undetermined"
            )
        }
    }

    private static func applyDeleteResult(
        _ result: NFPrivateCloudZoneDeleteResult,
        to zone: NFPrivateCloudOwnedZone,
        request: inout NFPrivateCloudCompleteDeletionRequest,
        at date: Date
    ) {
        request.update(zone) { state in
            switch result {
            case .accepted:
                state.deletion = .accepted(at: date)
            case .zoneNotFound:
                state.deletion = .zoneNotFound(at: date)
            case let .failed(code, retryable):
                state.deletion = .failed(
                    redactedCode: code,
                    retryable: retryable,
                    at: date
                )
            }
        }
    }

    private static func applyReadResult(
        _ result: NFPrivateCloudZoneReadResult,
        to zone: NFPrivateCloudOwnedZone,
        request: inout NFPrivateCloudCompleteDeletionRequest,
        at date: Date
    ) {
        request.update(zone) { state in
            switch result {
            case .present:
                state.readback = .present(checkedAt: date)
            case .absent:
                state.readback = .absent(checkedAt: date)
            case let .failed(code, retryable):
                state.readback = .failed(
                    redactedCode: code,
                    retryable: retryable,
                    checkedAt: date
                )
            }
        }
    }

    private static func finalizeRemoteVerification(
        request: NFPrivateCloudCompleteDeletionRequest,
        policy: NFPrivateCloudCompleteDeletionPolicy,
        stateStore: any NFPrivateCloudDeletionStateStoring,
        client: any NFPrivateCloudZoneDeletionClient,
        verifiedAt: Date
    ) async throws -> NFPrivateCloudDeletionStartupOutcome {
        guard request.isValid(for: policy), request.isRemotelyVerified else {
            throw NFPrivateCloudCompleteDeletionError.invalidPersistentState
        }
        var verifiedRequest = request
        // The final receipt is account-bound too. Never turn an operation that
        // raced an account switch into proof for either account.
        if let accountFailure = await accountBindingFailure(
            request: request,
            client: client,
            now: verifiedAt
        ) {
            verifiedRequest.lastFailure = accountFailure
            try persist(verifiedRequest, in: stateStore)
            return .unfinished(verifiedRequest)
        }
        verifiedRequest.lastFailure = nil
        try persist(verifiedRequest, in: stateStore)
        let receipt = NFPrivateCloudCompleteDeletionReceipt(
            request: verifiedRequest,
            verifiedAt: verifiedAt
        )
        do {
            try stateStore.saveReceipt(receipt)
            guard try stateStore.loadReceipt() == receipt else {
                throw NFPrivateCloudDeletionStateStoreError.persistenceVerificationFailed
            }
        } catch {
            throw NFPrivateCloudCompleteDeletionError.statePersistenceFailed
        }
        return .verified(receipt)
    }

    private static func accountBindingFailure(
        request: NFPrivateCloudCompleteDeletionRequest,
        client: any NFPrivateCloudZoneDeletionClient,
        now: Date
    ) async -> NFPrivateCloudDeletionFailure? {
        switch await client.currentAccount() {
        case let .available(fingerprint):
            guard fingerprint == request.accountFingerprint else {
                return NFPrivateCloudDeletionFailure(
                    redactedCode: "account-mismatch",
                    retryable: false,
                    occurredAt: now
                )
            }
            return nil
        case .noAccount:
            return NFPrivateCloudDeletionFailure(
                redactedCode: "account-unavailable",
                retryable: true,
                occurredAt: now
            )
        case .restricted:
            return NFPrivateCloudDeletionFailure(
                redactedCode: "account-restricted",
                retryable: false,
                occurredAt: now
            )
        case .temporarilyUnavailable:
            return NFPrivateCloudDeletionFailure(
                redactedCode: "account-temporary",
                retryable: true,
                occurredAt: now
            )
        case .couldNotDetermine:
            return NFPrivateCloudDeletionFailure(
                redactedCode: "account-undetermined",
                retryable: true,
                occurredAt: now
            )
        }
    }

    private static func persist(
        _ request: NFPrivateCloudCompleteDeletionRequest,
        in stateStore: any NFPrivateCloudDeletionStateStoring
    ) throws {
        do {
            try stateStore.saveRequest(request)
            guard try stateStore.loadRequest() == request else {
                throw NFPrivateCloudDeletionStateStoreError.persistenceVerificationFailed
            }
        } catch {
            throw NFPrivateCloudCompleteDeletionError.statePersistenceFailed
        }
    }

    private static func loadRequest(
        from stateStore: any NFPrivateCloudDeletionStateStoring
    ) throws -> NFPrivateCloudCompleteDeletionRequest? {
        do {
            return try stateStore.loadRequest()
        } catch {
            throw NFPrivateCloudCompleteDeletionError.invalidPersistentState
        }
    }

    private static func loadReceipt(
        from stateStore: any NFPrivateCloudDeletionStateStoring
    ) throws -> NFPrivateCloudCompleteDeletionReceipt? {
        do {
            return try stateStore.loadReceipt()
        } catch {
            throw NFPrivateCloudCompleteDeletionError.invalidPersistentState
        }
    }

}

private extension NFPrivateCloudCompleteDeletionError {
    var redactedCode: String {
        switch self {
        case .policyUnavailable: "policy-unavailable"
        case .clientContainerMismatch: "container-mismatch"
        case let .accountUnavailable(code): code
        case .accountMismatch: "account-mismatch"
        case .existingRequestMismatch: "request-mismatch"
        case .localCleanupPending: "local-cleanup-pending"
        case .localPurgeNotStaged: "local-purge-not-staged"
        case .invalidPersistentState: "state-invalid"
        case .statePersistenceFailed: "state-persistence-failed"
        }
    }

    var isRetryable: Bool {
        switch self {
        case let .accountUnavailable(code):
            code == "account-unavailable"
                || code == "account-temporary"
                || code == "account-undetermined"
        case .statePersistenceFailed:
            true
        case .policyUnavailable,
             .clientContainerMismatch,
             .accountMismatch,
             .existingRequestMismatch,
             .localCleanupPending,
             .localPurgeNotStaged,
             .invalidPersistentState:
            false
        }
    }
}

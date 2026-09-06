import CoreData
import Foundation
import Observation
import SwiftData

enum NFLocalDataCleanupComponent: String, CaseIterable, Equatable, Sendable {
    case preparedExports
    case authoringCache
    case spotlightIndex
    case notifications
    case widgetSnapshot
    case privateSyncState
    case localDatabase
    case structuredStoreFiles

    var displayName: String {
        switch self {
        case .preparedExports:
            NFAppLocalization.localized("prepared export folders", locale: NFAppLocalization.preferredLocale, comment: "Local-data cleanup component name.")
        case .authoringCache:
            NFAppLocalization.localized("the generated-question cache", locale: NFAppLocalization.preferredLocale, comment: "Local-data cleanup component name.")
        case .spotlightIndex:
            NFAppLocalization.localized("the Spotlight search index", locale: NFAppLocalization.preferredLocale, comment: "Local-data cleanup component name.")
        case .notifications:
            NFAppLocalization.localized("managed notifications", locale: NFAppLocalization.preferredLocale, comment: "Local-data cleanup component name.")
        case .widgetSnapshot:
            NFAppLocalization.localized("the widget snapshot", locale: NFAppLocalization.preferredLocale, comment: "Local-data cleanup component name.")
        case .privateSyncState:
            NFAppLocalization.localized("the private-sync queue and launch preference", locale: NFAppLocalization.preferredLocale, comment: "Local-data cleanup component name.")
        case .localDatabase:
            NFAppLocalization.localized("the local database and imported copies", locale: NFAppLocalization.preferredLocale, comment: "Local-data cleanup component name.")
        case .structuredStoreFiles:
            NFAppLocalization.localized("the account-scoped structured-store files", locale: NFAppLocalization.preferredLocale, comment: "Local-data cleanup component name.")
        }
    }
}

struct NFLocalDataCleanupReceipt: Equatable, Sendable {
    let completedComponents: [NFLocalDataCleanupComponent]
    let requiresRelaunchToFinish: Bool

    init(
        completedComponents: [NFLocalDataCleanupComponent],
        requiresRelaunchToFinish: Bool = false
    ) {
        self.completedComponents = completedComponents
        self.requiresRelaunchToFinish = requiresRelaunchToFinish
    }
}

struct NFLocalDataCleanupFailure: Error, Equatable, LocalizedError, Sendable {
    let failedComponent: NFLocalDataCleanupComponent
    let completedComponents: [NFLocalDataCleanupComponent]

    var errorDescription: String? {
        NFAppLocalization.localized("NeuroForge could not verify removal of \(failedComponent.displayName). No deletion success was reported. Retry Delete all local data; components already cleared are safe to clear again.",
            locale: NFAppLocalization.preferredLocale,
            comment: "Local-data cleanup failure; the placeholder is the localized component name."
        )
    }
}

enum NFPrivateSyncDeletionError: Error, LocalizedError {
    case transportUnavailable
    case queuePersistenceFailed
    case restartRequiredForLocalDeletion
    case structuredCloudUnavailable
    case structuredDeletionVerificationUnavailable
    case restartRequiredForCompleteDeletion
    case completeDeletionStagingFailed
    case restartRequiredForFinalLocalPurge
    case finalLocalPurgeFailed
    case originalDeletionNotDurable
    case originalDeletionNotAcknowledged(redactedCode: String)

    var errorDescription: String? {
        switch self {
        case .transportUnavailable:
            NFAppLocalization.localized("Private iCloud deletion is unavailable. Keep the local copy and retry after the signed sync capability and account are available.",
                locale: NFAppLocalization.preferredLocale,
                comment: "Error when deleting a synced source document everywhere cannot safely queue."
            )
        case .queuePersistenceFailed:
            NFAppLocalization.localized("The private deletion tombstone could not be saved. The local document was kept so the deletion can be retried safely.",
                locale: NFAppLocalization.preferredLocale,
                comment: "Error when a private CloudKit deletion tombstone cannot be persisted locally."
            )
        case .restartRequiredForLocalDeletion:
            NFAppLocalization.localized("Private structured sync is active for this launch. NeuroForge turned off sync for the next launch; quit and reopen the app, then retry local-only deletion so it cannot propagate to iCloud.",
                locale: NFAppLocalization.preferredLocale,
                comment: "Safety error requiring a restart before deleting only local data from a CloudKit-backed SwiftData launch."
            )
        case .structuredCloudUnavailable:
            NFAppLocalization.localized("Complete private-iCloud deletion requires an active signed structured-sync configuration. Local deletion remains available.",
                locale: NFAppLocalization.preferredLocale,
                comment: "Error when all-cloud deletion is requested without an active signed structured CloudKit store."
            )
        case .structuredDeletionVerificationUnavailable:
            NFAppLocalization.localized("NeuroForge cannot yet prove that SwiftData deleted this profile and study history from private iCloud. Nothing was deleted. Keep private sync on and use local-only deletion only if you intend to preserve the iCloud copy.",
                locale: NFAppLocalization.preferredLocale,
                comment: "Fail-closed error when SwiftData does not expose enough transaction identity to verify complete structured-record deletion from private CloudKit."
            )
        case .restartRequiredForCompleteDeletion:
            NFAppLocalization.localized("The complete-deletion request is saved and private sync is frozen. Quit and reopen NeuroForge so it can remove and verify its two private iCloud zones before opening any local database. Local data has not been deleted yet.",
                locale: NFAppLocalization.preferredLocale,
                comment: "Expected two-launch boundary after a durable complete private-iCloud deletion request."
            )
        case .completeDeletionStagingFailed:
            NFAppLocalization.localized("The account-bound deletion request is saved and private sync remains frozen, but NeuroForge could not safely stage this device’s pre-container cleanup. Nothing has been deleted yet. Retry this action before quitting.",
                locale: NFAppLocalization.preferredLocale,
                comment: "Fail-closed error when complete-deletion local purge intent cannot be durably staged."
            )
        case .restartRequiredForFinalLocalPurge:
            NFAppLocalization.localized("This device’s open database is cleared and its account-scoped store purge is scheduled. Quit and reopen NeuroForge once more so it can verify removal before opening any database.",
                locale: NFAppLocalization.preferredLocale,
                comment: "Expected restart boundary after local cleanup schedules deletion of the currently open structured store."
            )
        case .finalLocalPurgeFailed:
            NFAppLocalization.localized("NeuroForge could not verify removal of the scheduled account-scoped store files. Private sync remains frozen and no deletion success was reported. Quit and reopen to retry before continuing.",
                locale: NFAppLocalization.preferredLocale,
                comment: "Fail-closed error when pre-container local structured-store purge remains unfinished."
            )
        case .originalDeletionNotDurable:
            NFAppLocalization.localized("NeuroForge could not verify durable deletion requests for every synced original. Local copies were kept so you can retry safely.",
                locale: NFAppLocalization.preferredLocale,
                comment: "Error when global private-original deletion tombstones cannot be verified locally."
            )
        case let .originalDeletionNotAcknowledged(redactedCode):
            NFAppLocalization.localized("Private-original deletion is not yet acknowledged (\(redactedCode)). Local copies were kept; retry after iCloud recovers.",
                locale: NFAppLocalization.preferredLocale,
                comment: "Error when global private-original deletion is queued but CloudKit has not acknowledged every change; placeholder is a redacted category."
            )
        }
    }
}

private enum NFLocalDataCleanupVerificationError: Error {
    case authoringCacheNotEmpty
    case widgetSnapshotStillPresent
}

typealias NFAsyncPrivacyCleaner = @MainActor @Sendable () async throws -> Void
typealias NFSyncPrivacyCleaner = @MainActor @Sendable () throws -> Void
typealias NFDurableStoreCleaner = @MainActor @Sendable (AppStore) throws -> Void
typealias NFNextDayPlanPreparer = @MainActor @Sendable (AppStore) async -> Bool
typealias NFCompleteCloudDeletionRequester = @MainActor @Sendable (
    _ containerIdentifier: String
) async throws -> NFPrivateCloudCompleteDeletionRequest
typealias NFStructuredStorePurgeScheduler = @MainActor @Sendable (
    _ openDurableStoreURL: URL
) throws -> NFPrivateCloudLocalPurgePreparation
typealias NFStructuredStorePurgeStager = @MainActor @Sendable (
    _ requestID: UUID,
    _ openDurableStoreURL: URL
) throws -> NFPrivateCloudLocalPurgePreparation

@MainActor
@Observable
final class NFSystemIntegrationCoordinator {
    private enum DefaultsKey {
        static let notificationPreferences = "nf.system.notifications.preferences.v1"
        static let spotlightConsent = "nf.system.spotlight.consent.v1"
        static let spotlightIndexedChunkIDs = "nf.system.spotlight.indexed-chunks.v1"
        static let structuredLastImportAt = "nf.sync.structured.last-import.v1"
        static let structuredLastExportAt = "nf.sync.structured.last-export.v1"
        static let structuredHasPendingLocalWrites = "nf.sync.structured.pending-local-write.v1"
        static let structuredCloudDeletionRequestedAt = "nf.sync.structured.deletion-requested.v1"
        static let structuredCloudDeletionVerifiedAt = "nf.sync.structured.deletion-verified.v1"
    }

    private struct NotificationApplicationRequest {
        let store: AppStore
        let explicitlyOptedIn: Bool
    }

    private let defaults: UserDefaults
    private let notificationClient: any NFNotificationCenterClient
    private let notificationCoordinator: NFNotificationOptInCoordinator
    private let spotlightClient: any NFSpotlightIndexClient
    private let backgroundScheduler: NFBGTaskSchedulerAdapter
    private let preparedExportCleaner: NFSyncPrivacyCleaner
    private let authoringCacheCleaner: NFAsyncPrivacyCleaner
    private let widgetSnapshotCleaner: NFSyncPrivacyCleaner
    private let privateSyncApplicationStateCleaner: NFSyncPrivacyCleaner
    private let durableStoreCleaner: NFDurableStoreCleaner
    private let nextDayPlanPreparer: NFNextDayPlanPreparer
    private let metricKitSubscriber: NFMetricKitSubscriber
    private let launchPrivateCloudConfiguration: NFPrivateCloudRuntimeConfiguration?
    private let launchStructuredCloudFallbackUsed: Bool
    private let launchDurableStoreURL: URL?
    private let completeCloudDeletionRequester: NFCompleteCloudDeletionRequester
    private let structuredStorePurgeStager: NFStructuredStorePurgeStager
    private let structuredStorePurgeScheduler: NFStructuredStorePurgeScheduler
    private var privateDocumentTransport: (any NFPrivateDocumentAssetTransport)?
    @ObservationIgnored
    nonisolated(unsafe) private var structuredCloudEventObserver: NSObjectProtocol?
    @ObservationIgnored
    nonisolated(unsafe) private var structuredStoreSaveObserver: NSObjectProtocol?
    @ObservationIgnored
    private var activationTask: Task<Void, Never>?
    @ObservationIgnored
    private weak var activatingStore: AppStore?
    @ObservationIgnored
    private var activationGeneration: UUID?
    @ObservationIgnored
    private var pendingNotificationApplication: NotificationApplicationRequest?
    @ObservationIgnored
    private var isStoppingForAccountIdentityChange = false
    private weak var observedStructuredStore: AppStore?
    private weak var observedStructuredContext: ModelContext?
    private var activeStructuredEventIDs: Set<UUID> = []
    private var structuredLastFailureCode: String?
    private var structuredLocalOnlyReason: NFLocalOnlySyncReason = .userDisabled

    var notificationPreferences: NFNotificationPreferences
    private(set) var notificationAuthorization: NFNotificationAuthorizationStatus = .notDetermined
    private(set) var notificationStatus = "Not configured"
    private(set) var notificationDetail = "Choose a reminder and save before NeuroForge asks for permission."
    private(set) var notificationIsApplying = false
    private(set) var localDataDeletionIsRunning = false
    private(set) var localDataDeletionError: String?

    var spotlightDraftEnabled: Bool
    var spotlightDraftIncludesDocumentTitles: Bool
    var spotlightDraftIncludesSourceText: Bool
    private(set) var spotlightStatus = "Off"
    private(set) var spotlightDetail = "Study material is excluded from system-wide search."
    private(set) var spotlightIsApplying = false

    private(set) var syncStatus = NFSyncStatusResolver.resolve(
        capability: .localOnly(reason: .userDisabled),
        accountState: .unknown,
        enginePhase: .notStarted,
        queue: NFSyncQueueMetrics(pendingRecordCount: 0, pendingAssetCount: 0),
        lastSuccessfulSyncAt: nil
    )
    private(set) var syncCapability: NFSyncCapability = .localOnly(reason: .userDisabled)
    private(set) var documentSyncStates: [UUID: NFDocumentPrivateSyncState] = [:]
    private(set) var structuredSyncStatus = NFStructuredSyncStatusResolver.resolve(
        isConfiguredAtLaunch: false,
        localOnlyReason: .userDisabled,
        lastSuccessfulImportAt: nil,
        lastSuccessfulExportAt: nil,
        hasPendingLocalWrites: false,
        activeEventCount: 0,
        lastFailureCode: nil,
        configurationChangeRequiresRestart: false
    )
    private(set) var structuredCloudDeletionStatus: NFStructuredCloudDeletionStatus = .notRequested

    private(set) var backgroundStatus = "Best effort"
    private(set) var backgroundDetail = "Core training never depends on background execution."
    private(set) var backgroundRegistration: [NFBackgroundTaskKind: Bool] = [:]

    init(
        defaults: UserDefaults = .standard,
        notificationClient suppliedNotificationClient: (any NFNotificationCenterClient)? = nil,
        spotlightClient suppliedSpotlightClient: (any NFSpotlightIndexClient)? = nil,
        preparedExportCleaner: NFSyncPrivacyCleaner? = nil,
        authoringCacheCleaner: NFAsyncPrivacyCleaner? = nil,
        widgetSnapshotCleaner: NFSyncPrivacyCleaner? = nil,
        privateSyncApplicationStateCleaner: NFSyncPrivacyCleaner? = nil,
        durableStoreCleaner: NFDurableStoreCleaner? = nil,
        nextDayPlanPreparer: NFNextDayPlanPreparer? = nil,
        launchPrivateCloudConfiguration: NFPrivateCloudRuntimeConfiguration? = nil,
        launchStructuredCloudFallbackUsed: Bool = false,
        launchDurableStoreURL: URL? = nil,
        launchPendingLocalPurgeResult: NFPrivateCloudPendingLocalPurgeResult = .notRequested,
        privateDocumentTransport suppliedPrivateDocumentTransport: (any NFPrivateDocumentAssetTransport)? = nil,
        completeCloudDeletionRequester suppliedCompleteCloudDeletionRequester: NFCompleteCloudDeletionRequester? = nil,
        structuredStorePurgeStager suppliedStructuredStorePurgeStager: NFStructuredStorePurgeStager? = nil,
        structuredStorePurgeScheduler suppliedStructuredStorePurgeScheduler: NFStructuredStorePurgeScheduler? = nil
    ) {
        self.defaults = defaults
        self.launchPrivateCloudConfiguration = launchPrivateCloudConfiguration
        self.launchStructuredCloudFallbackUsed = launchStructuredCloudFallbackUsed
        self.launchDurableStoreURL = launchDurableStoreURL
        _ = launchPendingLocalPurgeResult
        privateDocumentTransport = suppliedPrivateDocumentTransport
        completeCloudDeletionRequester = suppliedCompleteCloudDeletionRequester ?? { containerIdentifier in
            try await NFPrivateCloudCompleteDeletionWorkflow.requestFromCloudBackedLaunch(
                containerIdentifier: containerIdentifier,
                defaults: defaults
            )
        }
        structuredStorePurgeStager = suppliedStructuredStorePurgeStager ?? { requestID, openURL in
            try NFPrivateCloudStoreIdentityResolver.stageLocalPurge(
                requestID: requestID,
                openDurableStoreURL: openURL,
                defaults: defaults
            )
        }
        structuredStorePurgeScheduler = suppliedStructuredStorePurgeScheduler ?? { openURL in
            try NFPrivateCloudStoreIdentityResolver.scheduleLocalPurge(
                openDurableStoreURL: openURL,
                defaults: defaults
            )
        }

        let notificationClient: any NFNotificationCenterClient = suppliedNotificationClient
            ?? NFUserNotificationCenterAdapter()
        self.notificationClient = notificationClient
        notificationCoordinator = NFNotificationOptInCoordinator(client: notificationClient)
        spotlightClient = suppliedSpotlightClient ?? NFCoreSpotlightIndexAdapter()
        backgroundScheduler = NFBGTaskSchedulerAdapter()
        self.preparedExportCleaner = preparedExportCleaner ?? {
            try NFDataExportService.removePreparedExports()
        }
        self.authoringCacheCleaner = authoringCacheCleaner ?? {
            await NFAuthoringEngine.shared.removeAllCachedResults()
            guard await NFAuthoringEngine.shared.cachedResultCount() == 0 else {
                throw NFLocalDataCleanupVerificationError.authoringCacheNotEmpty
            }
        }
        self.widgetSnapshotCleaner = widgetSnapshotCleaner ?? {
            NFWidgetSnapshotStore.delete()
            guard NFWidgetSnapshotStore.read() == nil else {
                throw NFLocalDataCleanupVerificationError.widgetSnapshotStillPresent
            }
        }
        self.privateSyncApplicationStateCleaner = privateSyncApplicationStateCleaner ?? {
            try NFFileDocumentAssetSyncStateStore.purgeAllApplicationState(
                defaults: defaults
            )
            try NFApplicationPrivacyArtifactCleaner.removeAllowlistedDefaults(
                defaults: defaults
            )
            try NFApplicationPrivacyArtifactCleaner.removeStoreRecoveryPackages()
        }
        self.durableStoreCleaner = durableStoreCleaner ?? { store in
            try store.deleteAllLocalData()
        }
        self.nextDayPlanPreparer = nextDayPlanPreparer ?? { store in
            // Question Writer is the app's only learner-facing model route.
            // Daily practice remains deterministic and does not silently run
            // the on-device language model in the background.
            store.nextDayEnhancementCache.removeAll()
            return true
        }
        metricKitSubscriber = .shared
        metricKitSubscriber.start()

        if
            let data = defaults.data(forKey: DefaultsKey.notificationPreferences),
            let decoded = try? JSONDecoder().decode(NFNotificationPreferences.self, from: data)
        {
            notificationPreferences = decoded
        } else {
            notificationPreferences = NFNotificationPreferences()
        }

        let storedConsent: NFSpotlightPrivacyConsent
        if
            let data = defaults.data(forKey: DefaultsKey.spotlightConsent),
            let decoded = try? JSONDecoder().decode(NFSpotlightPrivacyConsent.self, from: data)
        {
            storedConsent = decoded
        } else {
            storedConsent = NFSpotlightPrivacyConsent()
        }
        spotlightDraftEnabled = storedConsent.isExplicitlyEnabled
        spotlightDraftIncludesDocumentTitles = storedConsent.includeDocumentTitles
        spotlightDraftIncludesSourceText = storedConsent.includeSourceText

        // Older builds treated any later framework export timestamp as proof
        // of a specific destructive transaction. SwiftData does not expose
        // that transaction identity, so those receipts cannot be trusted.
        // Invalidate them without changing the user's launch preference.
        if defaults.object(forKey: DefaultsKey.structuredCloudDeletionVerifiedAt) != nil
            || defaults.object(forKey: DefaultsKey.structuredCloudDeletionRequestedAt) != nil {
            defaults.removeObject(forKey: DefaultsKey.structuredCloudDeletionVerifiedAt)
            defaults.removeObject(forKey: DefaultsKey.structuredCloudDeletionRequestedAt)
            structuredCloudDeletionStatus = .failed(
                redactedCode: "verification-unavailable"
            )
        }
        let deletionStateStore = NFUserDefaultsPrivateCloudDeletionStateStore(defaults: defaults)
        if let request = try? deletionStateStore.loadRequest() {
            structuredCloudDeletionStatus = .awaitingRestart(
                requestedAt: request.requestedAt
            )
        }
        refreshStructuredSyncStatus(
            userEnabled: NFPrivateSyncBootstrapPreference.isEnabled(defaults: defaults),
            localOnlyReason: launchStructuredCloudFallbackUsed
                ? .syncEngineUnavailable
                : .userDisabled
        )
        if launchPrivateCloudConfiguration != nil {
            installStructuredCloudEventObserver()
        }
    }

    deinit {
        if let structuredCloudEventObserver {
            NotificationCenter.default.removeObserver(structuredCloudEventObserver)
        }
        if let structuredStoreSaveObserver {
            NotificationCenter.default.removeObserver(structuredStoreSaveObserver)
        }
    }

    func registerBackgroundTasks(store: AppStore) {
        guard backgroundRegistration.isEmpty else { return }
        backgroundRegistration = backgroundScheduler.registerAll { [weak self, weak store] kind in
            guard let self, let store else { return false }
            return await self.performBackgroundTask(kind, store: store)
        }

        #if os(iOS)
        let registeredCount = backgroundRegistration.values.filter { $0 }.count
        backgroundStatus = registeredCount == NFBackgroundTaskKind.allCases.count
            ? "Registered"
            : "Partially unavailable"
        backgroundDetail = registeredCount == NFBackgroundTaskKind.allCases.count
            ? "Plan preparation and maintenance may run when iOS grants time."
            : "iOS did not register every optional task; foreground recovery remains complete."
        #else
        backgroundStatus = "Foreground on Mac"
        backgroundDetail = "macOS performs the same maintenance when NeuroForge is active."
        #endif
    }

    func activate(store: AppStore) async {
        guard !isStoppingForAccountIdentityChange else { return }
        if let activationTask {
            let isSameStore = activatingStore === store
            await activationTask.value
            if isSameStore { return }
            await activate(store: store)
            return
        }

        let generation = UUID()
        activationGeneration = generation
        activatingStore = store
        let task = Task { @MainActor [weak self, weak store] in
            guard let self else { return }
            defer { self.finishActivation(generation: generation) }
            guard let store else { return }
            await self.performActivation(store: store)
        }
        activationTask = task
        await task.value
    }

    /// Terminates account-bound work before the app releases this launch's
    /// ModelContainer. Queue files are deliberately preserved for the owning
    /// account; only in-memory adapters and scheduled work are stopped.
    func stopForAccountIdentityChange() async {
        guard !isStoppingForAccountIdentityChange else { return }
        isStoppingForAccountIdentityChange = true
        activationTask?.cancel()
        activationGeneration = nil
        activatingStore = nil
        for kind in NFBackgroundTaskKind.allCases {
            backgroundScheduler.cancel(kind)
        }
        backgroundRegistration.removeAll()
        if let transport = privateDocumentTransport {
            await transport.stop()
        }
        privateDocumentTransport = nil
        documentSyncStates.removeAll()
        activeStructuredEventIDs.removeAll()
        syncCapability = .localOnly(reason: .syncEngineUnavailable)
        syncStatus = NFSyncStatusResolver.resolve(
            capability: syncCapability,
            accountState: .unknown,
            enginePhase: .notStarted,
            queue: NFSyncQueueMetrics(pendingRecordCount: 0, pendingAssetCount: 0),
            lastSuccessfulSyncAt: nil
        )
    }

    private func performActivation(store: AppStore) async {
        _ = try? await NFShortcutAuthoringRequestStore.shared.purgeExpiredVerifying()
        installStructuredStoreSaveObserver(store: store)
        await configurePrivateDocumentTransport(store: store)
        notificationPreferences.trainingDays = notificationWeekdays(from: store.profileSnapshot.trainingDays)
        notificationAuthorization = await notificationClient.authorizationStatus()

        if notificationPreferences.hasConfiguredReminder, notificationAuthorization.permitsScheduling {
            await applyNotificationPreferences(store: store, explicitlyOptedIn: false)
        } else {
            await notificationClient.refreshCategories(
                using: notificationCategoryPresentation(for: store)
            )
            updateNotificationCopyForCurrentState()
        }

        await refreshSpotlightIndex(store: store)
    }

    private func finishActivation(generation: UUID) {
        guard activationGeneration == generation else { return }
        activationTask = nil
        activatingStore = nil
        activationGeneration = nil
    }

    func prepareForBackground(store: AppStore) {
        let snapshot = NFBackgroundWorkSnapshot(
            shouldPrepareNextPlan: store.isOnboardingComplete
                && store.profileSnapshot.aiMode != .disabled,
            pendingSourceChunkCount: store.documents.filter { $0.indexState == "extracting" || $0.indexState == "stored" }.count,
            expiredGeneratedCacheCount: store.expiredAIGenerationPayloadCount()
                + store.expiredPreparedEnhancementCacheCount(),
            generatedCacheBytes: store.generatedQuestionCacheBytes
                + store.preparedEnhancementCacheBytes,
            privateSyncAssistanceRequested: store.profileSnapshot.iCloudEnabled,
            privateSyncIsConfigured: syncCapability.supportsPrivateSyncAttempt
        )
        let requests = NFBackgroundTaskPlanner.makeRequests(snapshot: snapshot, now: Date())
        let requestedKinds = Set(requests.map(\.kind))
        for kind in NFBackgroundTaskKind.allCases where !requestedKinds.contains(kind) {
            backgroundScheduler.cancel(kind)
        }

        var submittedCount = 0
        var failureCount = 0
        for request in requests {
            do {
                if try backgroundScheduler.submit(request) == .submitted {
                    submittedCount += 1
                }
            } catch {
                failureCount += 1
            }
        }

        #if os(iOS)
        if failureCount > 0 {
            backgroundStatus = "Foreground fallback"
            backgroundDetail = "Some optional requests were declined; work resumes when the app opens."
        } else if submittedCount > 0 {
            backgroundStatus = "Requested"
            backgroundDetail = "iOS decides when to grant optional maintenance time."
        } else {
            backgroundStatus = "No work pending"
            backgroundDetail = "There is no optional maintenance waiting to run."
        }
        #endif
    }

    func setDailyReminderEnabled(_ enabled: Bool) {
        notificationPreferences.dailyReminderTime = enabled ? (notificationPreferences.dailyReminderTime ?? .nineAM) : nil
    }

    func setDailyReminder(date: Date) {
        let components = Calendar.current.dateComponents([.hour, .minute], from: date)
        if let time = NFLocalClockTime(hour: components.hour ?? 9, minute: components.minute ?? 0) {
            notificationPreferences.dailyReminderTime = time
        }
    }

    func setWeeklySummaryEnabled(_ enabled: Bool) {
        notificationPreferences.weeklySummaryEnabled = enabled
    }

    func setWeeklySummaryWeekday(_ weekday: NFWeekday) {
        notificationPreferences.weeklySummaryWeekday = weekday
    }

    func setWeeklySummaryTime(date: Date) {
        if let time = clockTime(from: date) {
            notificationPreferences.weeklySummaryTime = time
        }
    }

    func setDueReviewReminderEnabled(_ enabled: Bool) {
        notificationPreferences.dueReviewReminderEnabled = enabled
    }

    func setQuietHoursEnabled(_ enabled: Bool) {
        notificationPreferences.quietHours = enabled
            ? (notificationPreferences.quietHours ?? NFQuietHours(
                startsAt: NFLocalClockTime(hour: 22, minute: 0)!,
                endsAt: NFLocalClockTime(hour: 7, minute: 0)!
            ))
            : nil
    }

    func setQuietHoursStart(date: Date) {
        guard
            let existing = notificationPreferences.quietHours,
            let replacement = clockTime(from: date)
        else { return }
        notificationPreferences.quietHours = NFQuietHours(startsAt: replacement, endsAt: existing.endsAt)
    }

    func setQuietHoursEnd(date: Date) {
        guard
            let existing = notificationPreferences.quietHours,
            let replacement = clockTime(from: date)
        else { return }
        notificationPreferences.quietHours = NFQuietHours(startsAt: existing.startsAt, endsAt: replacement)
    }

    func applyNotificationPreferences(store: AppStore, explicitlyOptedIn: Bool = true) async {
        if notificationIsApplying {
            pendingNotificationApplication = NotificationApplicationRequest(
                store: store,
                explicitlyOptedIn: explicitlyOptedIn
                    || pendingNotificationApplication?.explicitlyOptedIn == true
            )
            return
        }
        notificationIsApplying = true
        defer {
            notificationIsApplying = false
            pendingNotificationApplication = nil
        }

        var request = NotificationApplicationRequest(
            store: store,
            explicitlyOptedIn: explicitlyOptedIn
        )
        while true {
            await performNotificationPreferencesApplication(request)
            guard let pending = pendingNotificationApplication else { break }
            pendingNotificationApplication = nil
            request = pending
        }
    }

    /// Re-registers category/action copy and rewrites any existing managed
    /// schedules after an in-app language change. Concurrent calls are replayed
    /// after an in-flight application so the newest language cannot be lost.
    func refreshNotificationLanguage(store: AppStore) async {
        await applyNotificationPreferences(store: store, explicitlyOptedIn: false)
    }

    private func performNotificationPreferencesApplication(
        _ request: NotificationApplicationRequest
    ) async {
        let store = request.store
        let language = NFNotificationLanguage(
            localeIdentifier: store.profile?.preferredLanguageCode
                ?? NFAppLocalization.preferredLanguageCode
        )
        await notificationClient.refreshCategories(
            using: NFNotificationCategoryPresentation(language: language)
        )

        notificationPreferences.trainingDays = notificationWeekdays(from: store.profileSnapshot.trainingDays)
        persist(notificationPreferences, key: DefaultsKey.notificationPreferences)

        do {
            let outcome = try await notificationCoordinator.apply(
                preferences: notificationPreferences,
                dueReviewAt: nextDueReviewDate(store: store),
                now: Date(),
                calendar: .current,
                timeZone: .current,
                language: language,
                userExplicitlySavedAndOptedIn: request.explicitlyOptedIn
            )
            notificationAuthorization = await notificationClient.authorizationStatus()
            applyNotificationOutcome(outcome)
        } catch {
            notificationStatus = "Could not schedule"
            notificationDetail = "Your choices were saved locally. Open the app later to retry scheduling."
        }
    }

    func disableAllNotifications(store: AppStore) async {
        notificationPreferences.dailyReminderTime = nil
        notificationPreferences.weeklySummaryEnabled = false
        notificationPreferences.dueReviewReminderEnabled = false
        await applyNotificationPreferences(store: store, explicitlyOptedIn: false)
    }

    @discardableResult
    func deleteAllLocalData(store: AppStore) async throws -> NFLocalDataCleanupReceipt {
        await willDeletePrivateData?()
        return try await performLocalDataDeletion(store: store)
    }

    var willDeletePrivateData: (@MainActor () async -> Void)?

    @discardableResult
    func deleteAllData(
        scope: NFDataDeletionScope,
        store: AppStore
    ) async throws -> NFDataDeletionReceipt {
        guard scope == .privateCloudAndThisDevice else {
            return NFDataDeletionReceipt(
                scope: scope,
                localReceipt: try await deleteAllLocalData(store: store),
                originalCloudStatus: .notRequested,
                structuredCloudStatus: .notRequested
            )
        }
        guard let launchPrivateCloudConfiguration else {
            throw NFPrivateSyncDeletionError.structuredCloudUnavailable
        }

        // The open durable store identity must be known before the cloud
        // request is committed. Staging itself is deliberately non-destructive
        // and binds launch 2's pre-container purge to the same request UUID.
        guard let launchDurableStoreURL else {
            throw NFPrivateSyncDeletionError.completeDeletionStagingFailed
        }

        await willDeletePrivateData?()

        let request = try await completeCloudDeletionRequester(
            launchPrivateCloudConfiguration.containerIdentifier
        )
        do {
            _ = try structuredStorePurgeStager(request.id, launchDurableStoreURL)
        } catch {
            structuredCloudDeletionStatus = .failed(
                redactedCode: "local-purge-staging-failed"
            )
            let stagingError = NFPrivateSyncDeletionError.completeDeletionStagingFailed
            localDataDeletionError = stagingError.errorDescription
            store.lastErrorMessage = stagingError.errorDescription
            throw stagingError
        }
        structuredCloudDeletionStatus = .awaitingRestart(
            requestedAt: request.requestedAt
        )
        localDataDeletionError = nil
        store.lastErrorMessage = nil
        let restartError = NFPrivateSyncDeletionError.restartRequiredForCompleteDeletion
        let message = restartError.errorDescription
            ?? "Restart NeuroForge to continue complete deletion."
        store.notice = AppNotice(
            title: NFAppLocalization.localized("Restart to continue deletion",
                locale: NFAppLocalization.preferredLocale,
                comment: "Title after persisting the first half of two-launch private-iCloud deletion."
            ),
            message: message
        )
        throw restartError
    }

    private func performLocalDataDeletion(
        store: AppStore
    ) async throws -> NFLocalDataCleanupReceipt {
        guard !localDataDeletionIsRunning else {
            let failure = NFLocalDataCleanupFailure(
                failedComponent: .localDatabase,
                completedComponents: []
            )
            throw failure
        }

        if launchPrivateCloudConfiguration != nil {
            NFPrivateSyncBootstrapPreference.set(false, defaults: defaults)
            let error = NFPrivateSyncDeletionError.restartRequiredForLocalDeletion
            localDataDeletionError = error.errorDescription
            store.lastErrorMessage = error.errorDescription
            throw error
        }

        localDataDeletionIsRunning = true
        localDataDeletionError = nil
        defer { localDataDeletionIsRunning = false }
        var completed: [NFLocalDataCleanupComponent] = []

        // External cleanup runs before the durable store is removed. If any
        // subsystem fails, Settings remains available and the operation can be
        // retried. The database is the final commit point that sends the app
        // back to onboarding.
        try await performPrivacyCleanupStep(
            .preparedExports,
            completed: &completed,
            store: store
        ) {
            try preparedExportCleaner()
        }
        try await performPrivacyCleanupStep(
            .authoringCache,
            completed: &completed,
            store: store
        ) {
            try await authoringCacheCleaner()
        }
        try await performPrivacyCleanupStep(
            .spotlightIndex,
            completed: &completed,
            store: store
        ) {
            try await spotlightClient.apply(NFSpotlightIndexPlanner.planGlobalDisable())
        }
        spotlightDraftEnabled = false
        spotlightDraftIncludesDocumentTitles = false
        spotlightDraftIncludesSourceText = false
        defaults.removeObject(forKey: DefaultsKey.spotlightConsent)
        defaults.removeObject(forKey: DefaultsKey.spotlightIndexedChunkIDs)
        spotlightStatus = "Off"
        spotlightDetail = "NeuroForge removed its study-material search domain from this device."

        try await performPrivacyCleanupStep(
            .notifications,
            completed: &completed,
            store: store
        ) {
            try await notificationCoordinator.removeAllManagedSchedules()
        }
        notificationPreferences = NFNotificationPreferences()
        defaults.removeObject(forKey: DefaultsKey.notificationPreferences)
        notificationStatus = "Off"
        notificationDetail = "NeuroForge removed all reminders and delivered notifications it manages."

        try await performPrivacyCleanupStep(
            .widgetSnapshot,
            completed: &completed,
            store: store
        ) {
            try widgetSnapshotCleaner()
        }
        try await performPrivacyCleanupStep(
            .privateSyncState,
            completed: &completed,
            store: store
        ) {
            NFPrivateSyncBootstrapPreference.set(false, defaults: self.defaults)
            if let transport = self.privateDocumentTransport {
                await transport.stop()
                try await transport.clearLocalStatePreservingRemote()
            }
            try self.privateSyncApplicationStateCleaner()
            self.privateDocumentTransport = nil
            self.documentSyncStates.removeAll()
        }
        try await performPrivacyCleanupStep(
            .localDatabase,
            completed: &completed,
            store: store
        ) {
            try durableStoreCleaner(store)
        }

        var requiresRelaunchToFinish = false
        if let launchDurableStoreURL {
            do {
                let preparation = try structuredStorePurgeScheduler(launchDurableStoreURL)
                requiresRelaunchToFinish = preparation.requiresRelaunch
                if !preparation.requiresRelaunch {
                    completed.append(.structuredStoreFiles)
                }
            } catch {
                let failure = NFLocalDataCleanupFailure(
                    failedComponent: .structuredStoreFiles,
                    completedComponents: completed
                )
                localDataDeletionError = failure.errorDescription
                store.lastErrorMessage = failure.errorDescription
                store.notice = AppNotice(
                    title: NFAppLocalization.localized("Deletion needs retry",
                        locale: NFAppLocalization.preferredLocale,
                        comment: "Title for a scoped data-deletion failure."
                    ),
                    message: failure.errorDescription ?? "Local cleanup needs retry."
                )
                throw failure
            }
        } else {
            // In-memory/recovery stores have no account-scoped files to defer.
            completed.append(.structuredStoreFiles)
        }

        localDataDeletionError = nil
        store.lastErrorMessage = nil
        if requiresRelaunchToFinish {
            let message = NFPrivateSyncDeletionError.restartRequiredForFinalLocalPurge
                .errorDescription ?? "Restart NeuroForge to finish local cleanup."
            store.notice = AppNotice(
                title: NFAppLocalization.localized("Restart to finish deletion",
                    locale: NFAppLocalization.preferredLocale,
                    comment: "Title after scheduling deletion of the currently open structured store."
                ),
                message: message
            )
            return NFLocalDataCleanupReceipt(
                completedComponents: completed,
                requiresRelaunchToFinish: true
            )
        }
        let verifiedDeletionMessage = NFAppLocalization.localized("NeuroForge verified removal of this device’s database, imported copies, prepared exports, generated-question cache, private-sync queue, Spotlight entries, managed notifications, and widget snapshot. Private iCloud copies were not represented as deleted.",
            locale: NFAppLocalization.preferredLocale,
            comment: "Verified privacy-deletion result for only this device; private-iCloud copies are explicitly excluded."
        )
        store.notice = AppNotice(
            title: NFAppLocalization.localized("Local data deleted",
                locale: NFAppLocalization.preferredLocale,
                comment: "Confirmation title after deleting data from only the current device."
            ),
            message: verifiedDeletionMessage
        )
        return NFLocalDataCleanupReceipt(completedComponents: completed)
    }

    private func performPrivacyCleanupStep(
        _ component: NFLocalDataCleanupComponent,
        completed: inout [NFLocalDataCleanupComponent],
        store: AppStore,
        operation: NFAsyncPrivacyCleaner
    ) async throws {
        do {
            try await operation()
            completed.append(component)
        } catch {
            let failure = NFLocalDataCleanupFailure(
                failedComponent: component,
                completedComponents: completed
            )
            let message = failure.errorDescription ?? "Local data cleanup needs to be retried."
            localDataDeletionError = message
            store.lastErrorMessage = message
            store.notice = AppNotice(title: "Deletion needs retry", message: message)
            throw failure
        }
    }

    func applySpotlightPreferences(store: AppStore) async {
        guard !spotlightIsApplying else { return }
        spotlightIsApplying = true
        defer { spotlightIsApplying = false }

        let consent = NFSpotlightPrivacyConsent(
            explicitlyEnabledAt: spotlightDraftEnabled ? Date() : nil,
            includeDocumentTitles: spotlightDraftEnabled && spotlightDraftIncludesDocumentTitles,
            includeSourceText: spotlightDraftEnabled && spotlightDraftIncludesSourceText
        )
        persist(consent, key: DefaultsKey.spotlightConsent)
        await applySpotlight(consent: consent, store: store)
    }

    func refreshSpotlightIndex(store: AppStore) async {
        let consent = storedSpotlightConsent
        spotlightDraftEnabled = consent.isExplicitlyEnabled
        spotlightDraftIncludesDocumentTitles = consent.includeDocumentTitles
        spotlightDraftIncludesSourceText = consent.includeSourceText
        await applySpotlight(consent: consent, store: store)
    }

    func privacyDashboardSnapshot(store: AppStore) -> NFPrivacyDashboardSnapshot {
        let durableCount = (store.profile == nil ? 0 : 1)
            + store.attempts.count
            + store.attemptReflections.count
            + store.progressAnnotations.count
            + store.sessionCheckpoints.count
            + store.dailyPlans.count
            + store.itemReports.count
            + (store.weeklyTransferStateRecord == nil ? 0 : 1)
            + (store.reassessmentStateRecord == nil ? 0 : 1)
        let localOnlyCount = store.inputCalibrations.count
            + store.documents.count
            + store.sourceChunks.count
            + store.aiGenerations.count
        let privateOriginals = store.documents.filter {
            NFDocumentSyncPolicy(rawValue: $0.syncPolicy) == .privateOriginal
        }
        var paths: Set<NFPrivacyDataPath> = [.localDevice]
        if launchPrivateCloudConfiguration != nil { paths.insert(.privateStructuredCloud) }
        if syncCapability.supportsPrivateSyncAttempt || !privateOriginals.isEmpty {
            paths.insert(.privateDocumentAssets)
        }
        return NFPrivacyDashboardSnapshot(
            localDurableRecordCount: durableCount,
            localOnlyRecordCount: localOnlyCount,
            structuredCloudEligibleRecordCount: durableCount,
            privateOriginalDocumentCount: privateOriginals.count,
            availablePaths: paths
        )
    }

    func recordStructuredSyncEvent(_ event: NFStructuredSyncEvent) {
        if event.endDate == nil {
            activeStructuredEventIDs.insert(event.id)
        } else {
            activeStructuredEventIDs.remove(event.id)
            if event.succeeded, let completedAt = event.endDate {
                structuredLastFailureCode = nil
                switch event.kind {
                case .setup:
                    break
                case .importChanges:
                    defaults.set(completedAt, forKey: DefaultsKey.structuredLastImportAt)
                    // SwiftData merges the imported transaction into the model
                    // context, while AppStore intentionally keeps materialized
                    // arrays for deterministic scheduling. Refresh those arrays
                    // only after the framework reports a completed import.
                    if let observedStructuredStore {
                        observedStructuredStore.reload()
                        reconcileBootstrapPreferenceWithImportedProfile(
                            store: observedStructuredStore
                        )
                    }
                case .exportChanges:
                    defaults.set(completedAt, forKey: DefaultsKey.structuredLastExportAt)
                    defaults.set(false, forKey: DefaultsKey.structuredHasPendingLocalWrites)
                }
            } else if let redactedFailureCode = event.redactedFailureCode {
                structuredLastFailureCode = redactedFailureCode
            }
        }
        refreshStructuredSyncStatus(
            userEnabled: NFPrivateSyncBootstrapPreference.isEnabled(defaults: defaults),
            localOnlyReason: structuredLocalOnlyReason
        )
    }

    private func installStructuredCloudEventObserver() {
        guard structuredCloudEventObserver == nil else { return }
        structuredCloudEventObserver = NotificationCenter.default.addObserver(
            forName: NSPersistentCloudKitContainer.eventChangedNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let cloudEvent = notification.userInfo?[
                NSPersistentCloudKitContainer.eventNotificationUserInfoKey
            ] as? NSPersistentCloudKitContainer.Event else { return }
            let kind: NFStructuredSyncEventKind = switch cloudEvent.type {
            case .setup: .setup
            case .import: .importChanges
            case .export: .exportChanges
            @unknown default: .setup
            }
            let failureCode = cloudEvent.error.map {
                NFCloudKitErrorMapper.map($0).redactedCode
            }
            let event = NFStructuredSyncEvent(
                id: cloudEvent.identifier,
                kind: kind,
                startDate: cloudEvent.startDate,
                endDate: cloudEvent.endDate,
                succeeded: cloudEvent.succeeded,
                redactedFailureCode: failureCode
            )
            Task { @MainActor [weak self] in
                self?.recordStructuredSyncEvent(event)
            }
        }
    }

    private func installStructuredStoreSaveObserver(store: AppStore) {
        guard launchPrivateCloudConfiguration != nil else { return }
        if observedStructuredContext === store.context,
           structuredStoreSaveObserver != nil { return }
        if let structuredStoreSaveObserver {
            NotificationCenter.default.removeObserver(structuredStoreSaveObserver)
        }
        observedStructuredStore = store
        observedStructuredContext = store.context
        let durableEntityNames = Set(
            NFPersistentStoreLocation.durableModels.map { String(describing: $0) }
        )
        structuredStoreSaveObserver = NotificationCenter.default.addObserver(
            forName: ModelContext.didSave,
            object: store.context,
            queue: .main
        ) { [weak self] notification in
            let keys: [ModelContext.NotificationKey] = [
                .insertedIdentifiers, .updatedIdentifiers, .deletedIdentifiers
            ]
            let identifiers = keys.flatMap { key -> [PersistentIdentifier] in
                let value = notification.userInfo?[key]
                    ?? notification.userInfo?[key.rawValue]
                if let values = value as? Set<PersistentIdentifier> { return Array(values) }
                if let values = value as? [PersistentIdentifier] { return values }
                return []
            }
            guard identifiers.contains(where: { durableEntityNames.contains($0.entityName) }) else {
                return
            }
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.defaults.set(
                    true,
                    forKey: DefaultsKey.structuredHasPendingLocalWrites
                )
                self.refreshStructuredSyncStatus(
                    userEnabled: NFPrivateSyncBootstrapPreference.isEnabled(defaults: self.defaults),
                    localOnlyReason: self.structuredLocalOnlyReason
                )
            }
        }
    }

    private func refreshStructuredSyncStatus(
        userEnabled: Bool,
        localOnlyReason: NFLocalOnlySyncReason
    ) {
        structuredLocalOnlyReason = localOnlyReason
        structuredSyncStatus = NFStructuredSyncStatusResolver.resolve(
            isConfiguredAtLaunch: launchPrivateCloudConfiguration != nil,
            localOnlyReason: localOnlyReason,
            lastSuccessfulImportAt: defaults.object(
                forKey: DefaultsKey.structuredLastImportAt
            ) as? Date,
            lastSuccessfulExportAt: defaults.object(
                forKey: DefaultsKey.structuredLastExportAt
            ) as? Date,
            hasPendingLocalWrites: defaults.bool(
                forKey: DefaultsKey.structuredHasPendingLocalWrites
            ),
            activeEventCount: activeStructuredEventIDs.count,
            lastFailureCode: structuredLastFailureCode,
            configurationChangeRequiresRestart:
                (launchPrivateCloudConfiguration != nil) != userEnabled
        )
    }

    private func reconcileBootstrapPreferenceWithImportedProfile(store: AppStore) {
        guard let importedProfile = store.profile else { return }
        let isAccountChangeLocked = NFPrivateSyncBootstrapPreference
            .isAccountChangeLocked(defaults: defaults)

        // A profile imported from a newly selected iCloud account must not
        // silently opt this device back in after the asset transport locked
        // itself for an explicit account-switch decision. Persist the same
        // fail-closed value the UI displays; the user's next explicit toggle
        // is the only operation that may clear the durable lock.
        if isAccountChangeLocked, importedProfile.iCloudEnabled {
            importedProfile.iCloudEnabled = false
            importedProfile.modifiedAt = Date()
            do {
                try store.context.save()
                store.reload()
            } catch {
                store.context.rollback()
                store.reload()
                structuredLastFailureCode = "preference-lock-save"
            }
        }

        let effectivePreference = (store.profile?.iCloudEnabled ?? false)
            && !isAccountChangeLocked
        NFPrivateSyncBootstrapPreference.applyImportedProfilePreference(
            effectivePreference,
            defaults: defaults
        )
        refreshSyncStatus(userEnabled: effectivePreference)
    }

    func refreshSyncStatus(userEnabled: Bool) {
        let requestedContainer = Bundle.main.object(
            forInfoDictionaryKey: "NFCloudKitContainerIdentifier"
        ) as? String
        let runtimeEntitlements = NFRuntimeEntitlementReader.snapshot()
        let configuredContainers = Self.entitledCloudContainerIdentifiers()
        let reason: NFLocalOnlySyncReason?
        if !userEnabled {
            reason = launchPrivateCloudConfiguration == nil ? .userDisabled : .restartRequiredToDisable
        } else if launchStructuredCloudFallbackUsed {
            reason = .syncEngineUnavailable
        } else if launchPrivateCloudConfiguration == nil {
            if runtimeEntitlements.containerIdentifiers.isEmpty {
                reason = .missingCloudKitEntitlement
            } else if requestedContainer?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false {
                reason = .missingContainerConfiguration
            } else if let requestedContainer, !configuredContainers.contains(requestedContainer) {
                reason = .configuredContainerIsNotEntitled
            } else {
                reason = .restartRequiredToEnable
            }
        } else if privateDocumentTransport == nil {
            reason = .syncEngineUnavailable
        } else {
            reason = nil
        }

        let capability = NFSyncCapabilityEvaluator.evaluate(
            NFSyncBuildConfiguration(
                userEnabledPrivateSync: userEnabled,
                requestedContainerIdentifier: requestedContainer,
                entitledContainerIdentifiers: configuredContainers.intersection(
                    runtimeEntitlements.containerIdentifiers
                ),
                syncEngineInstalled: privateDocumentTransport != nil
            )
        )
        syncCapability = reason.map { .localOnly(reason: $0) } ?? capability
        syncStatus = NFSyncStatusResolver.resolve(
            capability: syncCapability,
            accountState: .unknown,
            enginePhase: .notStarted,
            queue: NFSyncQueueMetrics(pendingRecordCount: 0, pendingAssetCount: 0),
            lastSuccessfulSyncAt: nil
        )
        refreshStructuredSyncStatus(
            userEnabled: userEnabled,
            localOnlyReason: reason ?? .userDisabled
        )
    }

    func reconcilePrivateDocumentSync(store: AppStore, synchronize: Bool = false) async {
        guard let transport = privateDocumentTransport,
              store.profileSnapshot.iCloudEnabled,
              launchPrivateCloudConfiguration != nil else {
            refreshSyncStatus(userEnabled: store.profileSnapshot.iCloudEnabled)
            await refreshDocumentSyncStates(store: store)
            return
        }
        await transport.reconcile(privateDocumentInputs(store: store))
        let snapshot = synchronize ? await transport.synchronize() : await transport.snapshot()
        applyTransportSnapshot(snapshot)
        await applyReceivedDocuments(from: transport, store: store)
        await refreshDocumentSyncStates(store: store)
    }

    func deleteDocumentEverywhere(_ document: SourceDocumentRecord, store: AppStore) async throws {
        guard NFDocumentSyncPolicy(rawValue: document.syncPolicy) == .privateOriginal else {
            try await store.withLinkedRestoreArtifactDeletion { try store.deleteDocument(document) }
            return
        }
        guard let transport = privateDocumentTransport,
              syncCapability.supportsPrivateSyncAttempt else {
            throw NFPrivateSyncDeletionError.transportUnavailable
        }
        let documentID = document.id
        await transport.reconcile(privateDocumentInputs(store: store))
        await transport.enqueueDeletion(documentID: documentID)
        let snapshot = await transport.snapshot()
        let verification = await transport.deletionVerification(
            requestedDocumentIDs: [documentID]
        )
        guard verification.allRequestsAreDurable else {
            throw NFPrivateSyncDeletionError.queuePersistenceFailed
        }
        try await store.withLinkedRestoreArtifactDeletion { try store.deleteDocument(document) }
        documentSyncStates[documentID] = .queued
        applyTransportSnapshot(snapshot)

        // Network completion is best effort. The durable tombstone is already
        // persisted before the local copy is removed and resumes next launch.
        Task { @MainActor [weak self, weak store] in
            guard let self, let store else { return }
            let completed = await transport.synchronize()
            self.applyTransportSnapshot(completed)
            await self.refreshDocumentSyncStates(store: store)
        }
    }

    func removeDocumentFromPrivateSync(documentID: UUID, store: AppStore) async {
        let input = store.documents.first(where: { $0.id == documentID }).flatMap {
            privateDocumentInput(document: $0, requirePrivatePolicy: false)
        }
        if let transport = privateDocumentTransport {
            if let input { await transport.reconcile([input]) }
            await transport.enqueueDeletion(documentID: documentID)
            documentSyncStates[documentID] = .queued
            let result = await transport.synchronize()
            applyTransportSnapshot(result)
        } else {
            do {
                let stateURL = try NFFileDocumentAssetSyncStateStore.applicationStoreURL()
                let queue = NFDocumentAssetMutationQueue(
                    store: NFFileDocumentAssetSyncStateStore(fileURL: stateURL)
                )
                if let input { _ = try await queue.enqueueUpsert(input) }
                try await queue.enqueueDelete(documentID: documentID)
                documentSyncStates[documentID] = .queued
            } catch {
                documentSyncStates[documentID] = .error
            }
        }
    }

    private func configurePrivateDocumentTransport(store: AppStore) async {
        guard !isStoppingForAccountIdentityChange else { return }
        guard store.profileSnapshot.iCloudEnabled,
              let launchPrivateCloudConfiguration else {
            await privateDocumentTransport?.stop()
            privateDocumentTransport = nil
            refreshSyncStatus(userEnabled: store.profileSnapshot.iCloudEnabled)
            await refreshDocumentSyncStates(store: store)
            return
        }
        if privateDocumentTransport == nil {
            do {
                privateDocumentTransport = try NFCKSyncEngineDocumentAssetAdapter.makeApplicationAdapter(
                    configuration: launchPrivateCloudConfiguration
                )
            } catch {
                privateDocumentTransport = nil
                refreshSyncStatus(userEnabled: true)
                return
            }
        }
        guard let transport = privateDocumentTransport else { return }
        let started = await transport.start()
        guard !isStoppingForAccountIdentityChange else {
            await transport.stop()
            return
        }
        guard started.isInstalled else {
            privateDocumentTransport = nil
            refreshSyncStatus(userEnabled: true)
            return
        }
        await transport.reconcile(privateDocumentInputs(store: store))
        guard !isStoppingForAccountIdentityChange else {
            await transport.stop()
            return
        }
        let synchronized = await transport.synchronize()
        guard !isStoppingForAccountIdentityChange else {
            await transport.stop()
            return
        }
        applyTransportSnapshot(synchronized)
        await applyReceivedDocuments(from: transport, store: store)
        await refreshDocumentSyncStates(store: store)
    }

    private func applyTransportSnapshot(_ snapshot: NFPrivateDocumentTransportSnapshot) {
        guard let launchPrivateCloudConfiguration, snapshot.isInstalled else {
            syncCapability = .localOnly(reason: .syncEngineUnavailable)
            syncStatus = NFSyncStatusResolver.resolve(
                capability: syncCapability,
                accountState: snapshot.accountState,
                enginePhase: snapshot.phase,
                queue: snapshot.queue,
                lastSuccessfulSyncAt: snapshot.lastSuccessfulSyncAt
            )
            return
        }
        syncCapability = .privateCloudConfigured(
            containerIdentifier: launchPrivateCloudConfiguration.containerIdentifier
        )
        syncStatus = NFSyncStatusResolver.resolve(
            capability: syncCapability,
            accountState: snapshot.accountState,
            enginePhase: snapshot.phase,
            queue: snapshot.queue,
            lastSuccessfulSyncAt: snapshot.lastSuccessfulSyncAt
        )
    }

    private func refreshDocumentSyncStates(store: AppStore) async {
        var states: [UUID: NFDocumentPrivateSyncState] = [:]
        for document in store.documents {
            guard NFDocumentSyncPolicy(rawValue: document.syncPolicy) == .privateOriginal else {
                states[document.id] = .localOnly
                continue
            }
            guard let transport = privateDocumentTransport,
                  syncCapability.supportsPrivateSyncAttempt else {
                states[document.id] = .unavailable
                continue
            }
            states[document.id] = await transport.documentState(documentID: document.id)
        }
        documentSyncStates = states
    }

    private func privateDocumentInputs(store: AppStore) -> [NFDocumentOriginalInput] {
        store.documents.compactMap { document in
            privateDocumentInput(document: document, requirePrivatePolicy: true)
        }
    }

    private func privateDocumentInput(
        document: SourceDocumentRecord,
        requirePrivatePolicy: Bool
    ) -> NFDocumentOriginalInput? {
        guard (!requirePrivatePolicy
               || NFDocumentSyncPolicy(rawValue: document.syncPolicy) == .privateOriginal),
              !document.localPath.isEmpty else { return nil }
        return NFDocumentOriginalInput(
            documentID: document.id,
            filename: document.filename,
            typeIdentifier: document.typeIdentifier,
            localURL: URL(fileURLWithPath: document.localPath),
            modifiedAt: document.modifiedAt,
            aiPolicyRaw: document.aiPolicyRaw,
            pccConsentPolicyVersion: document.pccExcerptConsentPolicyVersion,
            pccConsentedAt: document.pccExcerptConsentedAt
        )
    }

    private func applyReceivedDocuments(
        from transport: any NFPrivateDocumentAssetTransport,
        store: AppStore
    ) async {
        for tombstone in await transport.receivedTombstones() {
            do {
                // Ignore stale/nonparticipating tombstones without retiring
                // backups; the actual eligible deletion still checks its gate.
                if store.documents.contains(where: { $0.id == tombstone.documentID
                    && NFDocumentSyncPolicy(rawValue: $0.syncPolicy) == .privateOriginal && tombstone.deletedAt >= $0.modifiedAt }) {
                    _ = try await store.withLinkedRestoreArtifactDeletion { try store.applySyncedDocumentTombstone(tombstone) }
                }
            } catch {
                markDownloadedDocumentApplicationFailed()
            }
        }
        for revision in await transport.receivedRevisions() {
            do {
                try await store.reconcileSyncedDocument(revision)
            } catch is CancellationError {
                return
            } catch {
                markDownloadedDocumentApplicationFailed()
            }
        }
    }

    private func markDownloadedDocumentApplicationFailed() {
        syncStatus = NFSyncStatusResolver.resolve(
            capability: syncCapability,
            accountState: .available,
            enginePhase: .failed(redactedCode: "download-integrity"),
            queue: syncStatus.queue,
            lastSuccessfulSyncAt: syncStatus.lastSuccessfulSyncAt
        )
    }

    func performBackgroundTask(_ kind: NFBackgroundTaskKind, store: AppStore) async -> Bool {
        switch kind {
        case .prepareDailyPlan:
            return await nextDayPlanPreparer(store)
        case .indexSourceChunks:
            await refreshSpotlightIndex(store: store)
            return true
        case .cleanGeneratedCache:
            // Only the expiring generated payload is disposable. Provenance
            // metadata remains durable for attempts and export.
            do {
                try store.purgeExpiredAIGenerationPayloads()
                store.purgeExpiredPreparedEnhancements()
                await NFAuthoringEngine.shared.removeAllCachedResults()
                try await NFShortcutAuthoringRequestStore.shared.purgeExpiredVerifying()
                return true
            } catch {
                return false
            }
        case .assistPrivateSync:
            await reconcilePrivateDocumentSync(store: store, synchronize: true)
            return syncCapability.supportsPrivateSyncAttempt
                && syncStatus.displayState != .error
        }
    }

    private func applySpotlight(consent: NFSpotlightPrivacyConsent, store: AppStore) async {
        let priorIDs = Set(defaults.stringArray(forKey: DefaultsKey.spotlightIndexedChunkIDs) ?? [])
        let plan: NFSpotlightIndexPlan
        if consent.isExplicitlyEnabled {
            let documentNames = Dictionary(uniqueKeysWithValues: store.documents.map { ($0.id, $0.filename) })
            let chunks = store.sourceChunks.map { chunk in
                NFSpotlightSourceChunk(
                    stableChunkID: chunk.id,
                    documentID: chunk.documentID,
                    documentTitle: documentNames[chunk.documentID] ?? chunk.sourceName,
                    heading: chunk.section,
                    normalizedText: chunk.text,
                    languageCode: store.profile?.preferredLanguageCode,
                    modifiedAt: chunk.createdAt
                )
            }
            plan = NFSpotlightIndexPlanner.planReplacement(
                chunks: chunks,
                previouslyIndexedChunkIDs: priorIDs,
                consent: consent,
                language: NFNotificationLanguage(localeIdentifier: store.profile?.preferredLanguageCode ?? Locale.current.identifier)
            )
        } else {
            plan = NFSpotlightIndexPlanner.planGlobalDisable()
        }

        do {
            try await spotlightClient.apply(plan)
            let indexedIDs = consent.isExplicitlyEnabled ? store.sourceChunks.map(\.id).sorted() : []
            defaults.set(indexedIDs, forKey: DefaultsKey.spotlightIndexedChunkIDs)
            if consent.isExplicitlyEnabled {
                spotlightStatus = "On"
                if consent.includeSourceText {
                    spotlightDetail = "Document titles and selected source text are searchable by the system on this device."
                } else if consent.includeDocumentTitles {
                    spotlightDetail = "Document titles are searchable; source text remains private to NeuroForge."
                } else {
                    spotlightDetail = "Only generic NeuroForge study entries are visible to system search."
                }
            } else {
                spotlightStatus = "Off"
                spotlightDetail = "NeuroForge removed its study-material search domain from this device."
            }
        } catch {
            spotlightStatus = "Needs retry"
            spotlightDetail = "The preference is saved, but the local system index could not be updated yet."
        }
    }

    private var storedSpotlightConsent: NFSpotlightPrivacyConsent {
        guard
            let data = defaults.data(forKey: DefaultsKey.spotlightConsent),
            let consent = try? JSONDecoder().decode(NFSpotlightPrivacyConsent.self, from: data)
        else { return NFSpotlightPrivacyConsent() }
        return consent
    }

    private func persist<Value: Encodable>(_ value: Value, key: String) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        defaults.set(data, forKey: key)
    }

    private func notificationWeekdays(from rawValues: Set<Int>) -> Set<NFWeekday> {
        let converted = Set(rawValues.compactMap(NFWeekday.init(rawValue:)))
        return converted.isEmpty ? Set(NFWeekday.allCases) : converted
    }

    private func notificationCategoryPresentation(
        for store: AppStore
    ) -> NFNotificationCategoryPresentation {
        NFNotificationCategoryPresentation(language: NFNotificationLanguage(
            localeIdentifier: store.profile?.preferredLanguageCode
                ?? NFAppLocalization.preferredLanguageCode
        ))
    }

    private func clockTime(from date: Date) -> NFLocalClockTime? {
        let components = Calendar.current.dateComponents([.hour, .minute], from: date)
        return NFLocalClockTime(hour: components.hour ?? 0, minute: components.minute ?? 0)
    }

    private func nextDueReviewDate(store: AppStore) -> Date? {
        let now = Date()
        let calendar = Calendar.current
        guard let earliest = store.nextEffectiveReviewDate(at: now, calendar: calendar) else { return nil }
        return earliest <= now ? now.addingTimeInterval(120) : earliest
    }

    private func applyNotificationOutcome(_ outcome: NFNotificationConfigurationOutcome) {
        switch outcome {
        case .noRemindersConfigured:
            notificationStatus = "Off"
            notificationDetail = "NeuroForge removed all reminders it manages."
        case .awaitingExplicitOptIn:
            notificationStatus = "Ready to save"
            notificationDetail = "Saving this schedule is the action that may request notification permission."
        case .denied:
            notificationStatus = "Blocked by system"
            notificationDetail = "Notifications are denied in System Settings; your schedule remains saved locally."
        case let .scheduled(plan):
            notificationStatus = "Scheduled"
            notificationDetail = plan.descriptors.count == 1
                ? NFAppLocalization.localized("One private reminder is active in your current timezone.", locale: NFAppLocalization.preferredLocale, comment: "Notification status when one private reminder is scheduled.")
                : NFAppLocalization.localized("\(plan.descriptors.count) private reminders are active in your current timezone.", locale: NFAppLocalization.preferredLocale, comment: "Notification status when multiple private reminders are scheduled; the placeholder is the reminder count.")
        case .unavailable:
            notificationStatus = "Unavailable"
            notificationDetail = "This system cannot currently schedule notifications; training remains fully available."
        }
    }

    private func updateNotificationCopyForCurrentState() {
        if !notificationPreferences.hasConfiguredReminder {
            notificationStatus = "Off"
            notificationDetail = "Choose a reminder and save before NeuroForge asks for permission."
        } else if notificationAuthorization == .denied {
            notificationStatus = "Blocked by system"
            notificationDetail = "Notifications are denied in System Settings; your schedule remains saved locally."
        } else if notificationAuthorization == .notDetermined {
            notificationStatus = "Ready to save"
            notificationDetail = "Saving this schedule is the action that may request notification permission."
        } else if notificationAuthorization.permitsScheduling {
            notificationStatus = "Scheduled"
            notificationDetail = "Your saved private reminder schedule is active."
        } else {
            notificationStatus = "Unavailable"
            notificationDetail = "Training remains fully available without reminders."
        }
    }

    private static func entitledCloudContainerIdentifiers() -> Set<String> {
        // Kept as an explicit build setting because SecTask entitlement inspection
        // is not available on every supported destination (including Simulator).
        // Production configuration must populate this only alongside code signing.
        let configured = Bundle.main.object(
            forInfoDictionaryKey: "NFEntitledCloudKitContainerIdentifiers"
        ) as? [String] ?? []
        return Set(configured)
    }
}

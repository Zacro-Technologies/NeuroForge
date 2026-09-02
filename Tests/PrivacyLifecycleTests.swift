import Foundation
import SwiftData
import XCTest

@testable import NeuroForge

final class PrivacyLifecycleTests: XCTestCase {
    @MainActor
    func testDeleteAllAwaitsEveryPrivacySurfaceBeforePublishingSuccess() async throws {
        let (store, container) = try makeStoreWithProfile()
        defer { _ = container }
        let notificationClient = PrivacyNotificationClient()
        let spotlightClient = PrivacySpotlightClient()
        let probe = PrivacyCleanupProbe()
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "NF-Privacy-Lifecycle-\(UUID().uuidString)"))

        let coordinator = NFSystemIntegrationCoordinator(
            defaults: defaults,
            notificationClient: notificationClient,
            spotlightClient: spotlightClient,
            preparedExportCleaner: { probe.preparedExportCleanupCount += 1 },
            authoringCacheCleaner: { probe.authoringCacheCleanupCount += 1 },
            widgetSnapshotCleaner: { probe.widgetCleanupCount += 1 },
            privateSyncApplicationStateCleaner: {}
        )

        let receipt = try await coordinator.deleteAllLocalData(store: store)
        let spotlightApplicationCount = await spotlightClient.applicationCount()
        let notificationRemovalCount = await notificationClient.removalCount()

        XCTAssertEqual(receipt.completedComponents, NFLocalDataCleanupComponent.allCases)
        XCTAssertEqual(probe.preparedExportCleanupCount, 1)
        XCTAssertEqual(probe.authoringCacheCleanupCount, 1)
        XCTAssertEqual(probe.widgetCleanupCount, 1)
        XCTAssertEqual(spotlightApplicationCount, 1)
        XCTAssertEqual(notificationRemovalCount, 1)
        XCTAssertNil(store.profile)
        XCTAssertEqual(store.notice?.title, "Local data deleted")
        XCTAssertNil(coordinator.localDataDeletionError)
        XCTAssertFalse(coordinator.localDataDeletionIsRunning)
    }

    @MainActor
    func testFailedExternalCleanupKeepsDatabaseAndSupportsIdempotentRetry() async throws {
        let (store, container) = try makeStoreWithProfile()
        defer { _ = container }
        let notificationClient = PrivacyNotificationClient()
        let spotlightClient = PrivacySpotlightClient(failuresRemaining: 1)
        let probe = PrivacyCleanupProbe()
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "NF-Privacy-Retry-\(UUID().uuidString)"))
        let coordinator = NFSystemIntegrationCoordinator(
            defaults: defaults,
            notificationClient: notificationClient,
            spotlightClient: spotlightClient,
            preparedExportCleaner: { probe.preparedExportCleanupCount += 1 },
            authoringCacheCleaner: { probe.authoringCacheCleanupCount += 1 },
            widgetSnapshotCleaner: { probe.widgetCleanupCount += 1 },
            privateSyncApplicationStateCleaner: {}
        )

        do {
            _ = try await coordinator.deleteAllLocalData(store: store)
            XCTFail("Expected the first Spotlight cleanup to fail")
        } catch let failure as NFLocalDataCleanupFailure {
            XCTAssertEqual(failure.failedComponent, .spotlightIndex)
            XCTAssertEqual(failure.completedComponents, [.preparedExports, .authoringCache])
        }

        XCTAssertNotNil(store.profile, "The durable database is the final commit point")
        XCTAssertEqual(store.notice?.title, "Deletion needs retry")
        XCTAssertNotNil(coordinator.localDataDeletionError)
        let firstNotificationRemovalCount = await notificationClient.removalCount()
        XCTAssertEqual(firstNotificationRemovalCount, 0)
        XCTAssertEqual(probe.widgetCleanupCount, 0)

        let receipt = try await coordinator.deleteAllLocalData(store: store)
        let spotlightApplicationCount = await spotlightClient.applicationCount()
        let notificationRemovalCount = await notificationClient.removalCount()

        XCTAssertEqual(receipt.completedComponents, NFLocalDataCleanupComponent.allCases)
        XCTAssertEqual(probe.preparedExportCleanupCount, 2)
        XCTAssertEqual(probe.authoringCacheCleanupCount, 2)
        XCTAssertEqual(probe.widgetCleanupCount, 1)
        XCTAssertEqual(spotlightApplicationCount, 2)
        XCTAssertEqual(notificationRemovalCount, 1)
        XCTAssertNil(store.profile)
        XCTAssertEqual(store.notice?.title, "Local data deleted")
    }

    @MainActor
    func testOpenStructuredStoreSchedulesRelaunchBeforePublishingFinalDeletionSuccess() async throws {
        let (store, container) = try makeStoreWithProfile()
        defer { _ = container }
        let notificationClient = PrivacyNotificationClient()
        let spotlightClient = PrivacySpotlightClient()
        let probe = PrivacyCleanupProbe()
        let defaults = try XCTUnwrap(UserDefaults(
            suiteName: "NF-Privacy-Structured-Purge-\(UUID().uuidString)"
        ))
        let openStoreURL = FileManager.default.temporaryDirectory.appending(
            path: "open-private-store-\(UUID().uuidString).store",
            directoryHint: .notDirectory
        )
        let coordinator = NFSystemIntegrationCoordinator(
            defaults: defaults,
            notificationClient: notificationClient,
            spotlightClient: spotlightClient,
            preparedExportCleaner: {},
            authoringCacheCleaner: {},
            widgetSnapshotCleaner: {},
            privateSyncApplicationStateCleaner: {},
            launchDurableStoreURL: openStoreURL,
            structuredStorePurgeScheduler: { receivedURL in
                probe.scheduledStructuredStoreURL = receivedURL
                return NFPrivateCloudLocalPurgePreparation(
                    requiresRelaunch: true,
                    removedInactiveNamespaceCount: 2
                )
            }
        )

        let receipt = try await coordinator.deleteAllLocalData(store: store)

        XCTAssertTrue(receipt.requiresRelaunchToFinish)
        XCTAssertEqual(probe.scheduledStructuredStoreURL, openStoreURL)
        XCTAssertFalse(receipt.completedComponents.contains(.structuredStoreFiles))
        XCTAssertEqual(store.notice?.title, "Restart to finish deletion")
        XCTAssertNil(store.profile)
    }

    @MainActor
    func testLocalOnlyDeletionClearsOnboardingAndRecoveryArtifactsButKeepsUnrelatedDefaults() async throws {
        let (store, container) = try makeStoreWithProfile()
        defer { _ = container }
        let suiteName = "NF-Privacy-Local-Allowlist-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(4, forKey: "nf.onboarding.step")
        defaults.set("private onboarding draft", forKey: "nf.onboarding.draft")
        defaults.set("preserve", forKey: "unrelated.preference")
        NFPrivateSyncBootstrapPreference.set(true, defaults: defaults)
        let fileManager = FileManager.default
        let temporaryRoot = fileManager.temporaryDirectory.appending(
            path: "NF-Privacy-Recovery-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        try fileManager.createDirectory(at: temporaryRoot, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: temporaryRoot) }
        let recoveryPackage = temporaryRoot.appending(
            path: NFStoreRecoveryService.packageFolderName,
            directoryHint: .isDirectory
        )
        try fileManager.createDirectory(at: recoveryPackage, withIntermediateDirectories: true)
        try Data("private recovery payload".utf8).write(
            to: recoveryPackage.appending(path: "default.store")
        )

        let coordinator = NFSystemIntegrationCoordinator(
            defaults: defaults,
            notificationClient: PrivacyNotificationClient(),
            spotlightClient: PrivacySpotlightClient(),
            preparedExportCleaner: {},
            authoringCacheCleaner: {},
            widgetSnapshotCleaner: {},
            privateSyncApplicationStateCleaner: {
                try NFApplicationPrivacyArtifactCleaner.removeAllowlistedDefaults(
                    defaults: defaults
                )
                try NFApplicationPrivacyArtifactCleaner.removeStoreRecoveryPackages(
                    fileManager: fileManager,
                    temporaryDirectory: temporaryRoot
                )
            }
        )

        _ = try await coordinator.deleteAllLocalData(store: store)

        XCTAssertNil(defaults.object(forKey: "nf.onboarding.step"))
        XCTAssertNil(defaults.object(forKey: "nf.onboarding.draft"))
        XCTAssertEqual(defaults.string(forKey: "unrelated.preference"), "preserve")
        XCTAssertFalse(NFPrivateSyncBootstrapPreference.isEnabled(defaults: defaults))
        XCTAssertFalse(fileManager.fileExists(atPath: recoveryPackage.path))
        XCTAssertNil(store.profile)
    }

    @MainActor
    private func makeStoreWithProfile() throws -> (AppStore, ModelContainer) {
        let schema = Schema(versionedSchema: NFSchemaV1.self)
        let container = try ModelContainer(
            for: schema,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let documentRoot = FileManager.default.temporaryDirectory.appending(
            path: "NF-Privacy-Lifecycle-Documents-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        let store = AppStore(
            context: container.mainContext,
            documentStorageRootURL: documentRoot
        )
        container.mainContext.insert(UserProfileRecord(draft: OnboardingDraft()))
        try container.mainContext.save()
        store.reload()
        return (store, container)
    }
}

@MainActor
private final class PrivacyCleanupProbe {
    var preparedExportCleanupCount = 0
    var authoringCacheCleanupCount = 0
    var widgetCleanupCount = 0
    var scheduledStructuredStoreURL: URL?
}

private enum PrivacyCleanupTestError: Error {
    case intentionalFailure
}

private actor PrivacySpotlightClient: NFSpotlightIndexClient {
    private var failuresRemaining: Int
    private var applyCount = 0

    init(failuresRemaining: Int = 0) {
        self.failuresRemaining = failuresRemaining
    }

    func apply(_ plan: NFSpotlightIndexPlan) async throws {
        applyCount += 1
        guard plan == NFSpotlightIndexPlanner.planGlobalDisable() else {
            throw PrivacyCleanupTestError.intentionalFailure
        }
        if failuresRemaining > 0 {
            failuresRemaining -= 1
            throw PrivacyCleanupTestError.intentionalFailure
        }
    }

    func applicationCount() -> Int { applyCount }
}

private actor PrivacyNotificationClient: NFNotificationCenterClient {
    private var managedRemovalCount = 0

    func refreshCategories(using presentation: NFNotificationCategoryPresentation) async {}

    func authorizationStatus() async -> NFNotificationAuthorizationStatus { .authorized }

    func requestAuthorizationAfterExplicitOptIn() async throws -> NFNotificationAuthorizationStatus {
        .authorized
    }

    func replaceManagedSchedules(with descriptors: [NFNotificationScheduleDescriptor]) async throws {}

    func removeManagedSchedules() async throws {
        managedRemovalCount += 1
    }

    func removalCount() -> Int { managedRemovalCount }
}

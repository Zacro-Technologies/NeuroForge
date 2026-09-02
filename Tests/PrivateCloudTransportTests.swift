import CloudKit
import Foundation
import SwiftData
import XCTest

@testable import NeuroForge

final class PrivateCloudTransportTests: XCTestCase {
    func testCloudStoreBootstrapRetriesTheSameStoreLocallyWithoutDiscardingData() throws {
        let identifier = "iCloud.com.zacrotech.NeuroForge"
        let requested = NFPrivateCloudRuntimeConfiguration(containerIdentifier: identifier)
        var attempts: [String?] = []

        let result = try NFCloudStoreBootstrap.open(
            requestedPrivateCloudConfiguration: requested
        ) { configuration in
            attempts.append(configuration?.containerIdentifier)
            if configuration != nil { throw CloudBootstrapProbeError.cloudUnavailable }
            return "existing-local-store"
        }

        XCTAssertEqual(attempts, [identifier, nil])
        XCTAssertEqual(result.store, "existing-local-store")
        XCTAssertNil(result.activePrivateCloudConfiguration)
        XCTAssertTrue(result.usedLocalFallback)
    }

    func testCloudStoreBootstrapDoesNotRetryWhenPrivateSyncWasNotRequested() throws {
        var attempts = 0
        let result = try NFCloudStoreBootstrap.open(
            requestedPrivateCloudConfiguration: nil
        ) { configuration in
            attempts += 1
            XCTAssertNil(configuration)
            return "local-store"
        }

        XCTAssertEqual(attempts, 1)
        XCTAssertEqual(result.store, "local-store")
        XCTAssertFalse(result.usedLocalFallback)
    }

    func testCompleteDeletionStartupGateBlocksTransitionsBeforeOpeningAContainer() {
        let policy = NFPrivateCloudCompleteDeletionPolicy(
            validatedContainerIdentifier: "iCloud.com.zacrotech.NeuroForge"
        )
        let request = NFPrivateCloudCompleteDeletionRequest(
            id: UUID(),
            policy: policy,
            accountFingerprint: String(repeating: "a", count: 64),
            requestedAt: Date(timeIntervalSince1970: 1_900_000_000)
        )
        let receipt = NFPrivateCloudCompleteDeletionReceipt(
            request: request,
            verifiedAt: Date(timeIntervalSince1970: 1_900_000_100)
        )
        let blockedOutcomes: [NFPrivateCloudDeletionStartupOutcome] = [
            .unfinished(request),
            .verified(receipt),
            .failed(redactedCode: "state-invalid", retryable: false)
        ]

        for outcome in blockedOutcomes {
            let resolution = NFCompleteDeletionStartupGate.resolve(outcome)
            XCTAssertFalse(resolution.permitsModelContainerOpen)
            XCTAssertFalse(resolution.completedPrivateCloudDeletion)
            guard case .blocked = resolution else {
                return XCTFail("Transitional deletion outcome must block startup: \(outcome)")
            }
        }

        let completion = NFPrivateCloudCompleteDeletionCompletion(
            requestID: request.id,
            remoteReceiptID: receipt.id,
            remoteVerifiedAt: receipt.verifiedAt,
            localVerifiedAt: Date(timeIntervalSince1970: 1_900_000_200)
        )
        let completedResolution = NFCompleteDeletionStartupGate.resolve(.completed(completion))
        XCTAssertTrue(completedResolution.permitsModelContainerOpen)
        XCTAssertTrue(completedResolution.completedPrivateCloudDeletion)
        XCTAssertEqual(completedResolution, .completed(completion))

        let ordinaryResolution = NFCompleteDeletionStartupGate.resolve(.noRequest)
        XCTAssertTrue(ordinaryResolution.permitsModelContainerOpen)
        XCTAssertFalse(ordinaryResolution.completedPrivateCloudDeletion)
        XCTAssertEqual(ordinaryResolution, .proceed)
    }

    func testCapabilityRequiresUserOptInConfiguredContainerAndEntitlementEvidence() {
        let identifier = "iCloud.com.zacrotech.NeuroForge"
        let evidence = NFCloudKitEntitlementSnapshot(
            containerIdentifiers: [identifier],
            services: ["CloudKit"],
            hasContainerEnvironment: true,
            hasSigningIdentifier: true
        )

        XCTAssertNil(NFPrivateCloudRuntimeConfiguration.evaluate(
            userEnabledPrivateSync: false,
            requestedContainerIdentifier: identifier,
            configuredContainerIdentifiers: [identifier],
            entitlements: evidence
        ))
        XCTAssertNil(NFPrivateCloudRuntimeConfiguration.evaluate(
            userEnabledPrivateSync: true,
            requestedContainerIdentifier: identifier,
            configuredContainerIdentifiers: [],
            entitlements: evidence
        ))
        XCTAssertEqual(
            NFPrivateCloudRuntimeConfiguration.evaluate(
                userEnabledPrivateSync: true,
                requestedContainerIdentifier: identifier,
                configuredContainerIdentifiers: [identifier],
                entitlements: evidence
            ),
            NFPrivateCloudRuntimeConfiguration(containerIdentifier: identifier)
        )
    }

    func testBootstrapPreferenceDefaultsOffAndIsExplicit() throws {
        let suiteName = "NFPrivateCloudTransportTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        XCTAssertFalse(NFPrivateSyncBootstrapPreference.isEnabled(defaults: defaults))
        NFPrivateSyncBootstrapPreference.set(true, defaults: defaults)
        XCTAssertTrue(NFPrivateSyncBootstrapPreference.isEnabled(defaults: defaults))
        NFPrivateSyncBootstrapPreference.set(false, defaults: defaults)
        XCTAssertFalse(NFPrivateSyncBootstrapPreference.isEnabled(defaults: defaults))
    }

    func testAsyncSingleFlightCoalescesAnOverlappingSynchronizationWave() async {
        let flight = NFAsyncSingleFlight<Int>()
        let operationGate = PrivateCloudAsyncGate()
        let probe = PrivateCloudSingleFlightProbe(operationGate: operationGate)
        let callers = (0..<24).map { _ in
            Task {
                await flight.run {
                    await probe.perform()
                }
            }
        }

        await probe.waitUntilStarted()
        // The operation remains suspended at a controlled gate while every
        // caller gets an opportunity to join the active flight. No timing or
        // CloudKit service behavior is involved in this concurrency probe.
        for _ in callers { await Task.yield() }
        await operationGate.open()
        let values = await callers.asyncMap { await $0.value }
        let invocationCount = await probe.invocationCount()

        XCTAssertEqual(Set(values), [73])
        XCTAssertEqual(invocationCount, 1)

        // Once the first generation has drained, a later request owns a new
        // operation instead of receiving a stale cached result.
        let next = await flight.run { 91 }
        XCTAssertEqual(next, 91)
    }

    func testCloudAccountFingerprintIsSaltedDeterministicAndDoesNotExposeRecordName() {
        let rawRecordName = "_a-private-cloudkit-user-record-name_"
        let firstSalt = Data(repeating: 0x2A, count: 32)
        let secondSalt = Data(repeating: 0x7C, count: 32)
        let first = NFPrivateCloudAccountFingerprint.derive(
            cloudKitRecordName: rawRecordName,
            containerIdentifier: "iCloud.com.zacrotech.NeuroForge",
            salt: firstSalt
        )
        let repeated = NFPrivateCloudAccountFingerprint.derive(
            cloudKitRecordName: rawRecordName,
            containerIdentifier: "iCloud.com.zacrotech.NeuroForge",
            salt: firstSalt
        )
        let otherInstallation = NFPrivateCloudAccountFingerprint.derive(
            cloudKitRecordName: rawRecordName,
            containerIdentifier: "iCloud.com.zacrotech.NeuroForge",
            salt: secondSalt
        )

        XCTAssertEqual(first, repeated)
        XCTAssertNotEqual(first, otherInstallation)
        XCTAssertEqual(first.count, 64)
        XCTAssertFalse(first.contains(rawRecordName))
    }

    @MainActor
    func testCloudAccountProbeTimeoutReturnsLocalFirstStateWithoutWaitingForStalledService() async {
        let clock = ContinuousClock()
        let started = clock.now
        let result = await NFPrivateCloudAccountProbe.resultWithTimeout(
            timeout: .milliseconds(20)
        ) {
            try? await Task.sleep(for: .seconds(2))
            return .available(fingerprint: "must-not-win")
        }

        XCTAssertEqual(result, .couldNotDetermine)
        XCTAssertLessThan(started.duration(to: clock.now), .seconds(1))
    }

    @MainActor
    func testCloudAccountProbeReturnsAvailableIdentityBeforeTimeout() async {
        let result = await NFPrivateCloudAccountProbe.resultWithTimeout(
            timeout: .seconds(1)
        ) {
            .available(fingerprint: "one-way-fingerprint")
        }
        XCTAssertEqual(result, .available(fingerprint: "one-way-fingerprint"))
    }

    @MainActor
    func testFirstCloudIdentityClaimsLegacyStoreAndAllRecognizedSidecarsWithoutMutation() throws {
        let fixture = try makeIdentityFixture()
        defer { fixture.cleanup() }
        let legacy = fixture.root.appending(path: "default.store")
        let wal = URL(fileURLWithPath: legacy.path + "-wal")
        let shm = URL(fileURLWithPath: legacy.path + "-shm")
        let support = fixture.root.appending(path: "default.store_SUPPORT", directoryHint: .isDirectory)
        try Data("legacy-main".utf8).write(to: legacy)
        try Data("legacy-wal".utf8).write(to: wal)
        try Data("legacy-shm".utf8).write(to: shm)
        try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        try Data("external-payload".utf8).write(to: support.appending(path: "payload.bin"))

        let configuration = NFPrivateCloudRuntimeConfiguration(
            containerIdentifier: "iCloud.com.zacrotech.NeuroForge"
        )
        let selection = NFPrivateCloudStoreIdentityResolver.resolve(
            requestedPrivateCloudConfiguration: configuration,
            accountProbe: .available(fingerprint: "fingerprint-a"),
            defaults: fixture.defaults,
            applicationSupportURL: fixture.root,
            namespaceFactory: { "account-a" }
        )

        XCTAssertEqual(selection.privateCloudConfiguration, configuration)
        XCTAssertEqual(selection.transition, .none)
        XCTAssertTrue(selection.claimedLegacyArtifacts)
        XCTAssertNotEqual(selection.durableStoreURL, legacy)
        XCTAssertEqual(try Data(contentsOf: selection.durableStoreURL), Data("legacy-main".utf8))
        XCTAssertEqual(
            try Data(contentsOf: URL(fileURLWithPath: selection.durableStoreURL.path + "-wal")),
            Data("legacy-wal".utf8)
        )
        XCTAssertEqual(
            try Data(contentsOf: URL(fileURLWithPath: selection.durableStoreURL.path + "-shm")),
            Data("legacy-shm".utf8)
        )
        XCTAssertEqual(
            try Data(contentsOf: selection.durableStoreURL.deletingLastPathComponent()
                .appending(path: "default.store_SUPPORT/payload.bin")),
            Data("external-payload".utf8)
        )
        XCTAssertEqual(try Data(contentsOf: legacy), Data("legacy-main".utf8))
        XCTAssertEqual(try Data(contentsOf: wal), Data("legacy-wal".utf8))
        let persistedRegistry = try XCTUnwrap(
            fixture.defaults.data(forKey: NFPrivateCloudStoreIdentityResolver.registryKey)
        )
        XCTAssertFalse(String(decoding: persistedRegistry, as: UTF8.self).contains("cloudkit-user"))
    }

    @MainActor
    func testSameCloudIdentityReusesItsDurableStoreNamespace() throws {
        let fixture = try makeIdentityFixture()
        defer { fixture.cleanup() }
        let configuration = NFPrivateCloudRuntimeConfiguration(
            containerIdentifier: "iCloud.com.zacrotech.NeuroForge"
        )
        let first = NFPrivateCloudStoreIdentityResolver.resolve(
            requestedPrivateCloudConfiguration: configuration,
            accountProbe: .available(fingerprint: "fingerprint-a"),
            defaults: fixture.defaults,
            applicationSupportURL: fixture.root,
            namespaceFactory: { "account-a" }
        )
        try writeIdentityStore("account-a-history", to: first.durableStoreURL)

        let second = NFPrivateCloudStoreIdentityResolver.resolve(
            requestedPrivateCloudConfiguration: configuration,
            accountProbe: .available(fingerprint: "fingerprint-a"),
            defaults: fixture.defaults,
            applicationSupportURL: fixture.root,
            namespaceFactory: { "must-not-be-used" }
        )

        XCTAssertEqual(second.durableStoreURL, first.durableStoreURL)
        XCTAssertEqual(second.privateCloudConfiguration, configuration)
        XCTAssertEqual(try Data(contentsOf: second.durableStoreURL), Data("account-a-history".utf8))
    }

    @MainActor
    func testDocumentAssetQueueAndCacheAreNamespacedAndLegacyStateIsClaimedOnlyByFirstAccount() async throws {
        let fixture = try makeIdentityFixture()
        defer { fixture.cleanup() }
        let configuration = NFPrivateCloudRuntimeConfiguration(
            containerIdentifier: "iCloud.com.zacrotech.NeuroForge"
        )
        _ = NFPrivateCloudStoreIdentityResolver.resolve(
            requestedPrivateCloudConfiguration: configuration,
            accountProbe: .available(fingerprint: "fingerprint-a"),
            defaults: fixture.defaults,
            applicationSupportURL: fixture.root,
            namespaceFactory: { "account-a" }
        )

        let legacyAssetRoot = fixture.root.appending(
            path: "NeuroForge/CloudAssets",
            directoryHint: .isDirectory
        )
        try FileManager.default.createDirectory(
            at: legacyAssetRoot,
            withIntermediateDirectories: true
        )
        let payload = Data("legacy account-a private asset".utf8)
        let temporary = fixture.root.appending(path: "legacy-payload.txt")
        try payload.write(to: temporary)
        let hash = try NFContentAddressedAssetHasher.sha256(fileURL: temporary)
        let legacyAsset = legacyAssetRoot.appending(path: hash)
        try FileManager.default.moveItem(at: temporary, to: legacyAsset)
        let legacyStateURL = fixture.root
            .appending(path: "NeuroForge/Sync", directoryHint: .isDirectory)
            .appending(path: "private-document-assets.json")
        let legacyQueue = NFDocumentAssetMutationQueue(
            store: NFFileDocumentAssetSyncStateStore(fileURL: legacyStateURL)
        )
        let live = try await legacyQueue.enqueueUpsert(input(id: UUID(), file: legacyAsset))
        try await legacyQueue.acknowledge(recordName: live.assetRecordName)
        try await legacyQueue.acknowledge(recordName: live.documentRecordName)
        try await legacyQueue.acceptDownloadedAsset(hash: hash, localURL: legacyAsset)
        let deleted = try await legacyQueue.enqueueUpsert(input(id: UUID(), file: legacyAsset))
        try await legacyQueue.acknowledge(recordName: deleted.documentRecordName)
        try await legacyQueue.enqueueDelete(documentID: deleted.documentID)
        try await legacyQueue.recordServerSystemFields(
            recordName: live.documentRecordName,
            data: Data("account-a-change-tag".utf8)
        )

        let accountALocations = try NFFileDocumentAssetSyncStateStore.applicationStorageLocations(
            defaults: fixture.defaults,
            applicationSupportURL: fixture.root
        )
        XCTAssertNotEqual(accountALocations.stateURL, legacyStateURL)
        XCTAssertTrue(FileManager.default.fileExists(atPath: legacyStateURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: legacyAsset.path))
        let accountAQueue = NFDocumentAssetMutationQueue(
            store: NFFileDocumentAssetSyncStateStore(fileURL: accountALocations.stateURL)
        )
        let accountASnapshot = try await accountAQueue.snapshot()
        XCTAssertEqual(accountASnapshot.revisions.map(\.documentID), [live.documentID])
        XCTAssertTrue(accountASnapshot.tombstones.contains { $0.documentID == deleted.documentID })
        XCTAssertEqual(
            accountASnapshot.downloadedAssetPathsByHash[hash],
            accountALocations.receivedAssetRootURL.appending(path: hash).path
        )
        let accountASystemFields = try await accountAQueue.serverSystemFields(
            recordName: live.documentRecordName
        )
        XCTAssertEqual(accountASystemFields, Data("account-a-change-tag".utf8))
        XCTAssertEqual(
            try Data(contentsOf: accountALocations.receivedAssetRootURL.appending(path: hash)),
            payload
        )

        _ = NFPrivateCloudStoreIdentityResolver.resolve(
            requestedPrivateCloudConfiguration: configuration,
            accountProbe: .available(fingerprint: "fingerprint-b"),
            defaults: fixture.defaults,
            applicationSupportURL: fixture.root,
            namespaceFactory: { "account-b" }
        )
        XCTAssertTrue(NFPrivateCloudStoreIdentityResolver.acceptPendingAccountChange(
            defaults: fixture.defaults
        ))
        XCTAssertEqual(
            NFPrivateCloudStoreIdentityResolver.activeNamespace(defaults: fixture.defaults),
            "account-a",
            "Accepting B must not let the still-running A process open B's queue"
        )
        let relaunchedB = NFPrivateCloudStoreIdentityResolver.resolve(
            requestedPrivateCloudConfiguration: configuration,
            accountProbe: .available(fingerprint: "fingerprint-b"),
            defaults: fixture.defaults,
            applicationSupportURL: fixture.root
        )
        XCTAssertEqual(relaunchedB.privateCloudConfiguration, configuration)
        XCTAssertEqual(
            NFPrivateCloudStoreIdentityResolver.activeNamespace(defaults: fixture.defaults),
            "account-b"
        )
        let accountBLocations = try NFFileDocumentAssetSyncStateStore.applicationStorageLocations(
            defaults: fixture.defaults,
            applicationSupportURL: fixture.root
        )
        XCTAssertNotEqual(accountBLocations.stateURL, accountALocations.stateURL)
        XCTAssertNotEqual(
            accountBLocations.receivedAssetRootURL,
            accountALocations.receivedAssetRootURL
        )
        let accountBState = try await NFFileDocumentAssetSyncStateStore(
            fileURL: accountBLocations.stateURL
        ).load()
        XCTAssertNil(accountBState)
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: accountBLocations.receivedAssetRootURL.appending(path: hash).path
        ))
    }

    @MainActor
    func testChangedCloudIdentityGetsDistinctLocalStoreAndDurableBootstrapLock() throws {
        let fixture = try makeIdentityFixture()
        defer { fixture.cleanup() }
        let configuration = NFPrivateCloudRuntimeConfiguration(
            containerIdentifier: "iCloud.com.zacrotech.NeuroForge"
        )
        NFPrivateSyncBootstrapPreference.setAfterExplicitUserChoice(true, defaults: fixture.defaults)
        let first = NFPrivateCloudStoreIdentityResolver.resolve(
            requestedPrivateCloudConfiguration: configuration,
            accountProbe: .available(fingerprint: "fingerprint-a"),
            defaults: fixture.defaults,
            applicationSupportURL: fixture.root,
            namespaceFactory: { "account-a" }
        )
        try writeIdentityStore("account-a-history", to: first.durableStoreURL)

        let changed = NFPrivateCloudStoreIdentityResolver.resolve(
            requestedPrivateCloudConfiguration: configuration,
            accountProbe: .available(fingerprint: "fingerprint-b"),
            defaults: fixture.defaults,
            applicationSupportURL: fixture.root,
            namespaceFactory: { "account-b" }
        )

        XCTAssertEqual(changed.transition, .accountChanged)
        XCTAssertNil(changed.privateCloudConfiguration)
        XCTAssertEqual(changed.durableStoreURL, first.durableStoreURL)
        XCTAssertEqual(try Data(contentsOf: first.durableStoreURL), Data("account-a-history".utf8))
        XCTAssertTrue(NFPrivateSyncBootstrapPreference.isAccountChangeLocked(defaults: fixture.defaults))
        XCTAssertFalse(NFPrivateSyncBootstrapPreference.isEnabled(defaults: fixture.defaults))

        let lockedRelaunch = NFPrivateCloudStoreIdentityResolver.resolve(
            requestedPrivateCloudConfiguration: nil,
            accountProbe: nil,
            defaults: fixture.defaults,
            applicationSupportURL: fixture.root
        )
        XCTAssertEqual(lockedRelaunch.durableStoreURL, first.durableStoreURL)
        XCTAssertEqual(lockedRelaunch.transition, .accountChanged)
        XCTAssertNil(lockedRelaunch.privateCloudConfiguration)

        XCTAssertTrue(NFPrivateCloudStoreIdentityResolver.acceptPendingAccountChange(
            defaults: fixture.defaults
        ))
        let accepted = NFPrivateCloudStoreIdentityResolver.resolve(
            requestedPrivateCloudConfiguration: configuration,
            accountProbe: .available(fingerprint: "fingerprint-b"),
            defaults: fixture.defaults,
            applicationSupportURL: fixture.root,
            namespaceFactory: { "must-not-be-used" }
        )
        XCTAssertNotEqual(accepted.durableStoreURL, first.durableStoreURL)
        XCTAssertEqual(accepted.privateCloudConfiguration, configuration)
        XCTAssertEqual(
            NFPrivateCloudStoreIdentityResolver.activeNamespace(defaults: fixture.defaults),
            "account-b"
        )
        XCTAssertEqual(try Data(contentsOf: first.durableStoreURL), Data("account-a-history".utf8))
    }

    @MainActor
    func testForcedIdentityClassificationStillLearnsPendingAccountAfterAdapterLockedBootstrap() throws {
        let fixture = try makeIdentityFixture()
        defer { fixture.cleanup() }
        let configuration = NFPrivateCloudRuntimeConfiguration(
            containerIdentifier: "iCloud.com.zacrotech.NeuroForge"
        )
        let accountA = NFPrivateCloudStoreIdentityResolver.resolve(
            requestedPrivateCloudConfiguration: configuration,
            accountProbe: .available(fingerprint: "fingerprint-a"),
            defaults: fixture.defaults,
            applicationSupportURL: fixture.root,
            namespaceFactory: { "account-a" }
        )
        try writeIdentityStore("account-a-history", to: accountA.durableStoreURL)
        NFPrivateSyncBootstrapPreference.lockAfterAccountChange(defaults: fixture.defaults)
        XCTAssertFalse(NFPrivateSyncBootstrapPreference.isEnabled(defaults: fixture.defaults))

        // The runtime restart carries its previously entitled configuration
        // solely for this identity probe; it does not rely on current(), which
        // correctly remains nil behind the adapter's durable switch lock.
        let classified = NFPrivateCloudStoreIdentityResolver.resolve(
            requestedPrivateCloudConfiguration: configuration,
            accountProbe: .available(fingerprint: "fingerprint-b"),
            defaults: fixture.defaults,
            applicationSupportURL: fixture.root,
            namespaceFactory: { "account-b" }
        )

        XCTAssertEqual(classified.transition, .accountChanged)
        XCTAssertNil(classified.privateCloudConfiguration)
        XCTAssertEqual(classified.durableStoreURL, accountA.durableStoreURL)
        XCTAssertEqual(try Data(contentsOf: accountA.durableStoreURL), Data("account-a-history".utf8))
        XCTAssertTrue(NFPrivateCloudStoreIdentityResolver.acceptPendingAccountChange(
            defaults: fixture.defaults
        ))
    }

    @MainActor
    func testReturningIdentityReusesItsStoreButStillRequiresFreshOptIn() throws {
        let fixture = try makeIdentityFixture()
        defer { fixture.cleanup() }
        let configuration = NFPrivateCloudRuntimeConfiguration(
            containerIdentifier: "iCloud.com.zacrotech.NeuroForge"
        )
        let accountA = NFPrivateCloudStoreIdentityResolver.resolve(
            requestedPrivateCloudConfiguration: configuration,
            accountProbe: .available(fingerprint: "fingerprint-a"),
            defaults: fixture.defaults,
            applicationSupportURL: fixture.root,
            namespaceFactory: { "account-a" }
        )
        let detectedB = NFPrivateCloudStoreIdentityResolver.resolve(
            requestedPrivateCloudConfiguration: configuration,
            accountProbe: .available(fingerprint: "fingerprint-b"),
            defaults: fixture.defaults,
            applicationSupportURL: fixture.root,
            namespaceFactory: { "account-b" }
        )
        XCTAssertEqual(detectedB.durableStoreURL, accountA.durableStoreURL)
        XCTAssertTrue(NFPrivateCloudStoreIdentityResolver.acceptPendingAccountChange(
            defaults: fixture.defaults
        ))
        let accountB = NFPrivateCloudStoreIdentityResolver.resolve(
            requestedPrivateCloudConfiguration: configuration,
            accountProbe: .available(fingerprint: "fingerprint-b"),
            defaults: fixture.defaults,
            applicationSupportURL: fixture.root
        )
        let returningA = NFPrivateCloudStoreIdentityResolver.resolve(
            requestedPrivateCloudConfiguration: configuration,
            accountProbe: .available(fingerprint: "fingerprint-a"),
            defaults: fixture.defaults,
            applicationSupportURL: fixture.root,
            namespaceFactory: { "must-not-be-used" }
        )

        XCTAssertNotEqual(accountA.durableStoreURL, accountB.durableStoreURL)
        XCTAssertEqual(returningA.durableStoreURL, accountB.durableStoreURL)
        XCTAssertEqual(returningA.transition, .accountChanged)
        XCTAssertNil(returningA.privateCloudConfiguration)

        XCTAssertTrue(NFPrivateCloudStoreIdentityResolver.acceptPendingAccountChange(
            defaults: fixture.defaults
        ))
        let acceptedA = NFPrivateCloudStoreIdentityResolver.resolve(
            requestedPrivateCloudConfiguration: configuration,
            accountProbe: .available(fingerprint: "fingerprint-a"),
            defaults: fixture.defaults,
            applicationSupportURL: fixture.root
        )
        XCTAssertEqual(acceptedA.durableStoreURL, accountA.durableStoreURL)
        XCTAssertEqual(acceptedA.privateCloudConfiguration, configuration)
    }

    @MainActor
    func testSignedOutRestrictedAndUnavailableStatesReuseLocalStoreWithoutErasing() throws {
        let fixture = try makeIdentityFixture()
        defer { fixture.cleanup() }
        let configuration = NFPrivateCloudRuntimeConfiguration(
            containerIdentifier: "iCloud.com.zacrotech.NeuroForge"
        )
        let available = NFPrivateCloudStoreIdentityResolver.resolve(
            requestedPrivateCloudConfiguration: configuration,
            accountProbe: .available(fingerprint: "fingerprint-a"),
            defaults: fixture.defaults,
            applicationSupportURL: fixture.root,
            namespaceFactory: { "account-a" }
        )
        try writeIdentityStore("offline-authoritative-copy", to: available.durableStoreURL)

        let cases: [(NFPrivateCloudAccountProbeResult, NFPrivateCloudStartupTransition)] = [
            (.noAccount, .noAccount),
            (.restricted, .restricted),
            (.temporarilyUnavailable, .temporarilyUnavailable),
            (.couldNotDetermine, .accountStatusUnavailable)
        ]
        for (probe, expectedTransition) in cases {
            let local = NFPrivateCloudStoreIdentityResolver.resolve(
                requestedPrivateCloudConfiguration: configuration,
                accountProbe: probe,
                defaults: fixture.defaults,
                applicationSupportURL: fixture.root
            )
            XCTAssertEqual(local.durableStoreURL, available.durableStoreURL)
            XCTAssertNil(local.privateCloudConfiguration)
            XCTAssertEqual(local.transition, expectedTransition)
            XCTAssertEqual(
                try Data(contentsOf: local.durableStoreURL),
                Data("offline-authoritative-copy".utf8)
            )
        }
    }

    @MainActor
    func testStructuredLocalPurgePreservesOpenStoreUntilRelaunchAndRemovesEveryAccountQueue() throws {
        let fixture = try makeIdentityFixture()
        defer { fixture.cleanup() }
        let fileManager = FileManager.default
        let configuration = NFPrivateCloudRuntimeConfiguration(
            containerIdentifier: "iCloud.com.zacrotech.NeuroForge"
        )
        fixture.defaults.set(
            Data(repeating: 0x6a, count: 32),
            forKey: NFPrivateCloudAccountFingerprint.saltKey
        )

        let accountA = NFPrivateCloudStoreIdentityResolver.resolve(
            requestedPrivateCloudConfiguration: configuration,
            accountProbe: .available(fingerprint: "fingerprint-a"),
            defaults: fixture.defaults,
            applicationSupportURL: fixture.root,
            namespaceFactory: { "account-a" }
        )
        _ = NFPrivateCloudStoreIdentityResolver.resolve(
            requestedPrivateCloudConfiguration: configuration,
            accountProbe: .available(fingerprint: "fingerprint-b"),
            defaults: fixture.defaults,
            applicationSupportURL: fixture.root,
            namespaceFactory: { "account-b" }
        )
        XCTAssertTrue(NFPrivateCloudStoreIdentityResolver.acceptPendingAccountChange(
            defaults: fixture.defaults
        ))
        let accountB = NFPrivateCloudStoreIdentityResolver.resolve(
            requestedPrivateCloudConfiguration: configuration,
            accountProbe: .available(fingerprint: "fingerprint-b"),
            defaults: fixture.defaults,
            applicationSupportURL: fixture.root
        )
        _ = NFPrivateCloudStoreIdentityResolver.resolve(
            requestedPrivateCloudConfiguration: configuration,
            accountProbe: .available(fingerprint: "fingerprint-a"),
            defaults: fixture.defaults,
            applicationSupportURL: fixture.root
        )
        XCTAssertTrue(NFPrivateCloudStoreIdentityResolver.acceptPendingAccountChange(
            defaults: fixture.defaults
        ))
        let reopenedA = NFPrivateCloudStoreIdentityResolver.resolve(
            requestedPrivateCloudConfiguration: configuration,
            accountProbe: .available(fingerprint: "fingerprint-a"),
            defaults: fixture.defaults,
            applicationSupportURL: fixture.root
        )
        XCTAssertEqual(reopenedA.durableStoreURL, accountA.durableStoreURL)

        try writeIdentityStore("open-a-history", to: accountA.durableStoreURL)
        try writeIdentityStore("inactive-b-history", to: accountB.durableStoreURL)
        let legacyStore = fixture.root.appending(path: "default.store")
        try Data("legacy-recovery".utf8).write(to: legacyStore)
        try Data("legacy-wal".utf8).write(to: URL(fileURLWithPath: legacyStore.path + "-wal"))
        let legacySupport = fixture.root.appending(
            path: "default.store_SUPPORT",
            directoryHint: .isDirectory
        )
        try fileManager.createDirectory(at: legacySupport, withIntermediateDirectories: true)
        try Data("support".utf8).write(to: legacySupport.appending(path: "payload"))
        let localDerived = fixture.root.appending(path: "local-derived.store")
        try Data("open-local-derived".utf8).write(to: localDerived)

        let queueTargets = [
            fixture.root.appending(path: "NeuroForge/Sync/private-document-assets.json"),
            fixture.root.appending(path: "NeuroForge/Sync/Accounts/account-a/private-document-assets.json"),
            fixture.root.appending(path: "NeuroForge/Sync/Accounts/account-b/private-document-assets.json"),
            fixture.root.appending(path: "NeuroForge/CloudAssets/legacy-hash"),
            fixture.root.appending(path: "NeuroForge/CloudAssetAccounts/account-a/a-hash"),
            fixture.root.appending(path: "NeuroForge/CloudAssetAccounts/account-b/b-hash")
        ]
        for target in queueTargets {
            try fileManager.createDirectory(
                at: target.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try Data("private-queue-or-asset".utf8).write(to: target)
        }
        let managedDocument = fixture.root.appending(
            path: "NeuroForge/Documents/learner-source.pdf"
        )
        try fileManager.createDirectory(
            at: managedDocument.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("managed-by-AppStore-cleanup".utf8).write(to: managedDocument)

        let preparation = try NFPrivateCloudStoreIdentityResolver.scheduleLocalPurge(
            openDurableStoreURL: accountA.durableStoreURL,
            defaults: fixture.defaults,
            applicationSupportURL: fixture.root
        )

        XCTAssertTrue(preparation.requiresRelaunch)
        XCTAssertGreaterThanOrEqual(preparation.removedInactiveNamespaceCount, 1)
        XCTAssertTrue(fileManager.fileExists(atPath: accountA.durableStoreURL.path))
        XCTAssertFalse(fileManager.fileExists(atPath: accountB.durableStoreURL.path))
        XCTAssertTrue(fileManager.fileExists(atPath: localDerived.path))
        XCTAssertFalse(fileManager.fileExists(atPath: legacyStore.path))
        XCTAssertFalse(fileManager.fileExists(atPath: legacySupport.path))
        XCTAssertTrue(queueTargets.allSatisfy { !fileManager.fileExists(atPath: $0.path) })
        XCTAssertTrue(fileManager.fileExists(atPath: managedDocument.path))
        XCTAssertNotNil(fixture.defaults.data(
            forKey: NFPrivateCloudStoreIdentityResolver.registryKey
        ))
        XCTAssertNotNil(fixture.defaults.data(
            forKey: NFPrivateCloudAccountFingerprint.saltKey
        ))
        XCTAssertTrue(NFPrivateCloudStoreIdentityResolver.hasPendingLocalPurge(
            defaults: fixture.defaults
        ))

        XCTAssertEqual(
            NFPrivateCloudStoreIdentityResolver.performPendingLocalPurgeBeforeOpeningContainer(
                defaults: fixture.defaults,
                applicationSupportURL: fixture.root
            ),
            .completed
        )
        XCTAssertFalse(fileManager.fileExists(atPath: accountA.durableStoreURL.path))
        XCTAssertFalse(fileManager.fileExists(atPath: localDerived.path))
        XCTAssertFalse(fileManager.fileExists(atPath: managedDocument.path))
        XCTAssertNil(fixture.defaults.object(
            forKey: NFPrivateCloudStoreIdentityResolver.registryKey
        ))
        XCTAssertNil(fixture.defaults.object(
            forKey: NFPrivateCloudAccountFingerprint.saltKey
        ))
        XCTAssertFalse(NFPrivateCloudStoreIdentityResolver.hasPendingLocalPurge(
            defaults: fixture.defaults
        ))
        XCTAssertTrue(NFPrivateCloudStoreIdentityResolver.hasVerifiedLocalPurgeReceipt(
            defaults: fixture.defaults
        ))
    }

    @MainActor
    func testCorruptStructuredPurgeRequestFailsClosedWithoutClearingIdentityState() throws {
        let fixture = try makeIdentityFixture()
        defer { fixture.cleanup() }
        fixture.defaults.set(Data("identity-registry".utf8), forKey: NFPrivateCloudStoreIdentityResolver.registryKey)
        fixture.defaults.set(Data(repeating: 0x2c, count: 32), forKey: NFPrivateCloudAccountFingerprint.saltKey)
        fixture.defaults.set(Data("not-a-purge-request".utf8), forKey: NFPrivateCloudStoreIdentityResolver.pendingLocalPurgeKey)

        XCTAssertEqual(
            NFPrivateCloudStoreIdentityResolver.performPendingLocalPurgeBeforeOpeningContainer(
                defaults: fixture.defaults,
                applicationSupportURL: fixture.root
            ),
            .failed
        )
        XCTAssertNotNil(fixture.defaults.object(forKey: NFPrivateCloudStoreIdentityResolver.registryKey))
        XCTAssertNotNil(fixture.defaults.object(forKey: NFPrivateCloudAccountFingerprint.saltKey))
        XCTAssertTrue(NFPrivateCloudStoreIdentityResolver.hasPendingLocalPurge(defaults: fixture.defaults))
    }

    @MainActor
    func testRequestBoundPurgeStagingDeletesNothingUntilMatchingVerifiedLaunch() throws {
        let fixture = try makeIdentityFixture()
        defer { fixture.cleanup() }
        let fileManager = FileManager.default
        let requestID = UUID()
        let selection = NFPrivateCloudStoreIdentityResolver.resolve(
            requestedPrivateCloudConfiguration: NFPrivateCloudRuntimeConfiguration(
                containerIdentifier: "iCloud.com.zacrotech.NeuroForge"
            ),
            accountProbe: .available(fingerprint: "fingerprint-a"),
            defaults: fixture.defaults,
            applicationSupportURL: fixture.root,
            namespaceFactory: { "account-a" }
        )
        try writeIdentityStore("structured-history", to: selection.durableStoreURL)
        let queueState = fixture.root.appending(
            path: "NeuroForge/Sync/Accounts/account-a/private-document-assets.json"
        )
        let document = fixture.root.appending(path: "NeuroForge/Documents/source.txt")
        let presentationCache = fixture.root.appending(
            path: "AI-Presentation-Cache/next-day-enhancements-v1.json"
        )
        for artifact in [queueState, document, presentationCache] {
            try fileManager.createDirectory(
                at: artifact.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try Data("must-survive-staging".utf8).write(to: artifact)
        }

        let staged = try NFPrivateCloudStoreIdentityResolver.stageLocalPurge(
            requestID: requestID,
            openDurableStoreURL: selection.durableStoreURL,
            defaults: fixture.defaults,
            applicationSupportURL: fixture.root
        )

        XCTAssertTrue(staged.requiresRelaunch)
        XCTAssertEqual(staged.removedInactiveNamespaceCount, 0)
        XCTAssertTrue(NFPrivateCloudStoreIdentityResolver.hasStagedLocalPurge(
            requestID: requestID,
            defaults: fixture.defaults
        ))
        XCTAssertFalse(NFPrivateCloudStoreIdentityResolver.hasStagedLocalPurge(
            requestID: UUID(),
            defaults: fixture.defaults
        ))
        for artifact in [selection.durableStoreURL, queueState, document, presentationCache] {
            XCTAssertTrue(fileManager.fileExists(atPath: artifact.path))
        }
        XCTAssertEqual(
            NFPrivateCloudStoreIdentityResolver.performPendingLocalPurgeBeforeOpeningContainer(
                defaults: fixture.defaults,
                applicationSupportURL: fixture.root
            ),
            .failed
        )
        XCTAssertTrue(fileManager.fileExists(atPath: selection.durableStoreURL.path))

        XCTAssertEqual(
            NFPrivateCloudStoreIdentityResolver.performPendingLocalPurgeBeforeOpeningContainer(
                requiredRequestID: requestID,
                defaults: fixture.defaults,
                applicationSupportURL: fixture.root
            ),
            .completed
        )
        for artifact in [selection.durableStoreURL, queueState, document, presentationCache] {
            XCTAssertFalse(fileManager.fileExists(atPath: artifact.path))
        }
        XCTAssertTrue(NFPrivateCloudStoreIdentityResolver.hasVerifiedLocalPurgeReceipt(
            requestID: requestID,
            defaults: fixture.defaults
        ))
        XCTAssertFalse(NFPrivateCloudStoreIdentityResolver.consumeVerifiedLocalPurgeReceipt(
            requestID: UUID(),
            defaults: fixture.defaults
        ))
        XCTAssertTrue(NFPrivateCloudStoreIdentityResolver.consumeVerifiedLocalPurgeReceipt(
            requestID: requestID,
            defaults: fixture.defaults
        ))
    }

    func testQueueStateMigratesMissingFieldsAndRejectsUnknownFutureSchema() throws {
        let legacy = try JSONDecoder().decode(
            NFDocumentAssetSyncState.self,
            from: Data("{}".utf8)
        )
        XCTAssertEqual(legacy.schemaVersion, NFDocumentAssetSyncState.currentSchemaVersion)
        XCTAssertTrue(legacy.serverRecordSystemFieldsByName.isEmpty)

        XCTAssertThrowsError(try JSONDecoder().decode(
            NFDocumentAssetSyncState.self,
            from: Data("{\"schemaVersion\":2}".utf8)
        )) { error in
            XCTAssertEqual(error as? NFDocumentAssetStateCodingError, .unsupportedSchemaVersion(2))
        }
    }

    func testOnlyDurablePartitionCanReceivePrivateSwiftDataConfiguration() throws {
        let root = FileManager.default.temporaryDirectory.appending(
            path: "NF-Cloud-Config-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        defer { try? FileManager.default.removeItem(at: root) }
        let identifier = "iCloud.com.zacrotech.NeuroForge"
        let configurations = try NFPersistentStoreLocation.configurations(
            storeRootURL: root,
            privateCloudConfiguration: NFPrivateCloudRuntimeConfiguration(
                containerIdentifier: identifier
            )
        )
        let durable = try XCTUnwrap(configurations.first { $0.name == "NeuroForgeDurable" })
        let local = try XCTUnwrap(configurations.first { $0.name == "NeuroForgeLocalOnly" })

        XCTAssertEqual(durable.cloudKitContainerIdentifier, identifier)
        XCTAssertNil(local.cloudKitContainerIdentifier)

        let disabled = try NFPersistentStoreLocation.configurations(
            storeRootURL: root.appending(path: "disabled", directoryHint: .isDirectory),
            privateCloudConfiguration: nil
        )
        XCTAssertTrue(disabled.allSatisfy { $0.cloudKitContainerIdentifier == nil })
    }

    func testSourceDeviceStateAndLocalCachesCannotEnterCloudSchema() {
        let durableNames = Set(NFPersistentStoreLocation.durableModels.map { String(describing: $0) })
        let localNames = Set(NFPersistentStoreLocation.localOnlyModels.map { String(describing: $0) })
        XCTAssertFalse(durableNames.contains("SourceDocumentRecord"))
        XCTAssertTrue(localNames.contains("SourceDocumentRecord"))
        XCTAssertTrue(localNames.contains("SourceChunkRecord"))
        XCTAssertTrue(localNames.contains("AIGenerationRecord"))
        XCTAssertTrue(localNames.contains("InputCalibrationRecord"))
        XCTAssertTrue(
            NFPrivateCloudSchemaManifest.allowedRecordTypes.isDisjoint(
                with: NFPrivateCloudSchemaManifest.prohibitedLocalCacheEntityNames
            )
        )
        XCTAssertTrue(NFPrivateCloudSchemaManifest.documentFieldKeys.isDisjoint(
            with: NFPrivateCloudSchemaManifest.prohibitedDeviceLocalFieldKeys
        ))
        for prohibited in ["localPath", "indexState", "indexError", "characterCount", "chunkCount", "text"] {
            XCTAssertFalse(NFPrivateCloudSchemaManifest.documentFieldKeys.contains(prohibited))
        }
    }

    func testSensitiveDurableContentRequestsCloudEncryptionWithoutChangingStorePartition() throws {
        let schema = Schema(versionedSchema: NFSchemaV1.self)
        let expectedEncryptedAttributes: [String: Set<String>] = [
            "UserProfileRecord": ["stageRaw", "fieldsRaw", "goalsRaw"],
            "ProgressAnnotationRecord": ["note"],
            "AttemptRecord": [
                "skillWeightsRaw", "transferBriefRaw", "spatialDifficultyParametersRaw",
                "prompt", "response", "correctAnswerText", "accommodationFlagsRaw"
            ],
            "AttemptReflectionRecord": ["note"],
            "WeeklyTransferStateRecord": [],
            "ReassessmentStateRecord": [],
            "SessionCheckpointRecord": [
                "response", "scratchpad", "resultsRaw", "creditsRaw",
                "recommendationRationale", "reflectionNote"
            ],
            "DailyPlanRecord": ["payload"],
            "ItemReportRecord": ["prompt", "reason", "note", "diagnosticPayload"]
        ]

        XCTAssertEqual(
            Set(NFPersistentStoreLocation.durableModels.map { String(describing: $0) }),
            Set(expectedEncryptedAttributes.keys)
        )
        for (entityName, expectedAttributes) in expectedEncryptedAttributes {
            let entity = try XCTUnwrap(schema.entitiesByName[entityName])
            XCTAssertEqual(
                cloudEncryptedAttributeNames(in: entity),
                expectedAttributes,
                "Unexpected CloudKit encryption contract for \(entityName)"
            )
        }

        let expectedLocalOnlyModels: Set<String> = [
            "InputCalibrationRecord", "SourceDocumentRecord", "SourceChunkRecord", "AIGenerationRecord"
        ]
        XCTAssertEqual(
            Set(NFPersistentStoreLocation.localOnlyModels.map { String(describing: $0) }),
            expectedLocalOnlyModels
        )
        for entityName in expectedLocalOnlyModels {
            let entity = try XCTUnwrap(schema.entitiesByName[entityName])
            XCTAssertTrue(
                cloudEncryptedAttributeNames(in: entity).isEmpty,
                "Device-local entity \(entityName) must not opt into CloudKit field encryption"
            )
        }

        let queryAndIdentityAttributes: [String: Set<String>] = [
            "UserProfileRecord": ["id", "createdAt", "modifiedAt"],
            "ProgressAnnotationRecord": ["id", "startDate", "endDate", "createdAt", "modifiedAt"],
            "AttemptRecord": [
                "id", "sessionID", "itemID", "templateID", "seed", "gameID", "skillID",
                "shownAt", "submittedAt", "deviceID", "generationID", "planID", "planBlockID"
            ],
            "AttemptReflectionRecord": ["id", "attemptID", "createdAt"],
            "ItemReportRecord": ["id", "itemID", "templateID", "createdAt", "status"],
            "WeeklyTransferStateRecord": ["id", "modifiedAt"],
            "ReassessmentStateRecord": ["id", "dueAt", "modifiedAt"],
            "SessionCheckpointRecord": ["id", "sessionID", "updatedAt", "planID", "planBlockID"],
            "DailyPlanRecord": ["id", "profileID", "localDayKey", "createdAt"]
        ]
        for (entityName, attributeNames) in queryAndIdentityAttributes {
            let entity = try XCTUnwrap(schema.entitiesByName[entityName])
            XCTAssertTrue(attributeNames.isDisjoint(with: cloudEncryptedAttributeNames(in: entity)))
        }
    }

    func testContentAddressedQueueDeduplicatesAssetsButNotDocumentIdentities() async throws {
        let file = try makeFile(contents: "shared original")
        defer { try? FileManager.default.removeItem(at: file) }
        let store = NFInMemoryDocumentAssetSyncStateStore()
        let queue = NFDocumentAssetMutationQueue(store: store)
        let firstID = UUID()
        let secondID = UUID()

        _ = try await queue.enqueueUpsert(input(id: firstID, file: file))
        _ = try await queue.enqueueUpsert(input(id: secondID, file: file))
        let snapshot = try await queue.snapshot()
        let assetSaves = snapshot.pending.filter { $0.operation == .saveAsset }
        let documentSaves = snapshot.pending.filter { $0.operation == .saveDocument }

        XCTAssertEqual(assetSaves.count, 1)
        XCTAssertEqual(documentSaves.count, 2)
        XCTAssertEqual(Set(documentSaves.map(\.recordName)).count, 2)
        XCTAssertTrue(documentSaves.contains { $0.recordName.contains(firstID.uuidString.lowercased()) })
        XCTAssertTrue(documentSaves.contains { $0.recordName.contains(secondID.uuidString.lowercased()) })
        XCTAssertTrue(assetSaves[0].recordName.hasPrefix("asset-"))
        XCTAssertEqual(assetSaves[0].recordName.count, "asset-".count + 64)

        let resumed = NFDocumentAssetMutationQueue(store: store)
        let resumedSnapshot = try await resumed.snapshot()
        XCTAssertEqual(resumedSnapshot, snapshot)
    }

    func testDeletesUseTombstonesAndOnlyDeleteLastReferencedAsset() async throws {
        let file = try makeFile(contents: "deduplicated delete")
        defer { try? FileManager.default.removeItem(at: file) }
        let queue = NFDocumentAssetMutationQueue(store: NFInMemoryDocumentAssetSyncStateStore())
        let firstID = UUID()
        let secondID = UUID()
        let first = try await queue.enqueueUpsert(input(id: firstID, file: file))
        _ = try await queue.enqueueUpsert(input(id: secondID, file: file))
        try await queue.acknowledge(recordName: first.assetRecordName)

        try await queue.enqueueDelete(documentID: firstID)
        var snapshot = try await queue.snapshot()
        XCTAssertFalse(snapshot.pending.contains { $0.operation == .deleteAsset })
        XCTAssertTrue(snapshot.pending.contains {
            $0.operation == .saveTombstone && $0.documentID == firstID
        })

        try await queue.enqueueDelete(documentID: secondID)
        snapshot = try await queue.snapshot()
        XCTAssertTrue(snapshot.pending.contains {
            $0.operation == .deleteAsset && $0.contentHash == first.contentHash
        })
        XCTAssertEqual(snapshot.tombstones.count, 2)
    }

    func testPartialFailureCannotAcknowledgeDocumentDeleteBeforeTombstoneOrAssetDeleteBeforeDocument() async throws {
        let file = try makeFile(contents: "ordered destructive chain")
        defer { try? FileManager.default.removeItem(at: file) }
        let queue = NFDocumentAssetMutationQueue(store: NFInMemoryDocumentAssetSyncStateStore())
        let documentID = UUID()
        let saved = try await queue.enqueueUpsert(input(id: documentID, file: file))
        try await queue.acknowledge(recordName: saved.assetRecordName)
        try await queue.acknowledge(
            recordName: saved.documentRecordName,
            completedOperation: .saveDocument
        )
        try await queue.enqueueDelete(
            documentID: documentID,
            deletedAt: Date(timeIntervalSince1970: 1_900_000_000)
        )

        var eligible = try await queue.snapshot(eligibleOnly: true)
        XCTAssertEqual(eligible.pending.map(\.operation), [.saveTombstone])

        // A delayed CKSyncEngine callback from a prior non-atomic batch must not
        // be able to consume the blocked document deletion.
        try await queue.acknowledge(
            recordName: saved.documentRecordName,
            completedOperation: .deleteDocument
        )
        var allPending = try await queue.snapshot()
        XCTAssertTrue(allPending.pending.contains { $0.operation == .deleteDocument })

        let failureTime = Date(timeIntervalSince1970: 1_900_000_100)
        try await queue.recordFailure(
            recordName: NFPrivateCloudRecordIdentity.tombstone(documentID),
            failure: .partialFailure(failedRecordNames: [
                NFPrivateCloudRecordIdentity.tombstone(documentID)
            ]),
            now: failureTime
        )
        eligible = try await queue.snapshot(now: failureTime, eligibleOnly: true)
        XCTAssertTrue(eligible.pending.isEmpty)
        eligible = try await queue.snapshot(
            now: failureTime.addingTimeInterval(10),
            eligibleOnly: true
        )
        XCTAssertEqual(eligible.pending.map(\.operation), [.saveTombstone])

        try await queue.acknowledge(
            recordName: NFPrivateCloudRecordIdentity.tombstone(documentID)
        )
        eligible = try await queue.snapshot(eligibleOnly: true)
        XCTAssertEqual(eligible.pending.map(\.operation), [.deleteDocument])

        // Record names are stable across operations. A late success for the old
        // document save must not be mistaken for success of the newer delete,
        // even though its tombstone prerequisite is now acknowledged.
        try await queue.acknowledge(
            recordName: saved.documentRecordName,
            completedOperation: .saveDocument
        )
        allPending = try await queue.snapshot()
        XCTAssertTrue(allPending.pending.contains { $0.operation == .deleteDocument })

        // The asset callback is also ignored until the document delete is
        // acknowledged, preventing a dangling or resurrected document record.
        try await queue.acknowledge(
            recordName: saved.assetRecordName,
            completedOperation: .deleteAsset
        )
        allPending = try await queue.snapshot()
        XCTAssertTrue(allPending.pending.contains { $0.operation == .deleteAsset })
        try await queue.acknowledge(
            recordName: saved.documentRecordName,
            completedOperation: .deleteDocument
        )
        eligible = try await queue.snapshot(eligibleOnly: true)
        XCTAssertEqual(eligible.pending.map(\.operation), [.deleteAsset])
        try await queue.acknowledge(
            recordName: saved.assetRecordName,
            completedOperation: .deleteAsset
        )
        let completed = try await queue.snapshot()
        XCTAssertTrue(completed.pending.isEmpty)
    }

    func testNewReferenceCancelsQueuedDeletionOfSharedAsset() async throws {
        let file = try makeFile(contents: "asset reused during deletion")
        defer { try? FileManager.default.removeItem(at: file) }
        let queue = NFDocumentAssetMutationQueue(store: NFInMemoryDocumentAssetSyncStateStore())
        let deletedID = UUID()
        let saved = try await queue.enqueueUpsert(input(id: deletedID, file: file))
        try await queue.acknowledge(recordName: saved.assetRecordName)
        try await queue.acknowledge(recordName: saved.documentRecordName)
        try await queue.enqueueDelete(documentID: deletedID)
        let deleting = try await queue.snapshot()
        XCTAssertTrue(deleting.pending.contains {
            $0.operation == .deleteAsset
        })

        let replacementID = UUID()
        _ = try await queue.enqueueUpsert(input(id: replacementID, file: file))
        var interleaved = try await queue.snapshot()
        XCTAssertFalse(interleaved.pending.contains { $0.operation == .deleteAsset })
        XCTAssertTrue(interleaved.revisions.contains { $0.documentID == replacementID })

        // Cancellation cannot recall a delete already handed to CloudKit. If
        // that stale deletion succeeds, the live replacement must force a new
        // asset save instead of trusting the prior remote-confirmed bit.
        try await queue.acknowledge(
            recordName: saved.assetRecordName,
            completedOperation: .deleteAsset
        )
        interleaved = try await queue.snapshot()
        XCTAssertFalse(interleaved.confirmedRemoteAssetHashes.contains(saved.contentHash))
        XCTAssertTrue(interleaved.pending.contains {
            $0.operation == .saveAsset && $0.contentHash == saved.contentHash
        })
        XCTAssertTrue(interleaved.pending.contains {
            $0.operation == .saveDocument && $0.documentID == replacementID
        })
    }

    func testRemoteOnlyDocumentSurvivesEmptyReconcileAndAssetArrivalUpdatesLocalMirrorPath() async throws {
        let file = try makeFile(contents: "remote original")
        defer { try? FileManager.default.removeItem(at: file) }
        let hash = try NFContentAddressedAssetHasher.sha256(fileURL: file)
        let queue = NFDocumentAssetMutationQueue(store: NFInMemoryDocumentAssetSyncStateStore())
        let remote = revision(id: UUID(), hash: hash, path: "")

        let decision = try await queue.applyRemoteRevision(remote)
        XCTAssertEqual(decision, .acceptRemote)
        try await queue.reconcile([])
        var snapshot = try await queue.snapshot()
        XCTAssertEqual(snapshot.revisions.map(\.documentID), [remote.documentID])
        XCTAssertTrue(snapshot.tombstones.isEmpty)

        try await queue.acceptDownloadedAsset(hash: hash, localURL: file)
        snapshot = try await queue.snapshot()
        XCTAssertEqual(snapshot.revisions.first?.localFilePath, file.path)
        XCTAssertEqual(snapshot.downloadedAssetPathsByHash[hash], file.path)
    }

    func testMaterializedRemoteRevisionDoesNotBecomeAFreshSaveOnReconcile() async throws {
        let file = try makeFile(contents: "already converged remote source")
        defer { try? FileManager.default.removeItem(at: file) }
        let hash = try NFContentAddressedAssetHasher.sha256(fileURL: file)
        let queue = NFDocumentAssetMutationQueue(store: NFInMemoryDocumentAssetSyncStateStore())
        let remote = revision(
            id: UUID(),
            hash: hash,
            path: file.path,
            sizeBytes: fileSize(file)
        )

        _ = try await queue.applyRemoteRevision(remote)
        try await queue.acceptDownloadedAsset(hash: hash, localURL: file)
        try await queue.reconcile([input(id: remote.documentID, file: file)])

        let snapshot = try await queue.snapshot()
        XCTAssertFalse(snapshot.pending.contains { $0.operation == .saveAsset })
        XCTAssertFalse(snapshot.pending.contains { $0.operation == .saveDocument })
    }

    func testAcceptedTombstoneIsNotReversedByAbsentLocalReconcile() async throws {
        let file = try makeFile(contents: "remote tombstone convergence")
        defer { try? FileManager.default.removeItem(at: file) }
        let hash = try NFContentAddressedAssetHasher.sha256(fileURL: file)
        let queue = NFDocumentAssetMutationQueue(store: NFInMemoryDocumentAssetSyncStateStore())
        let remote = revision(
            id: UUID(),
            hash: hash,
            path: file.path,
            sizeBytes: fileSize(file)
        )
        _ = try await queue.applyRemoteRevision(remote)
        try await queue.acceptDownloadedAsset(hash: hash, localURL: file)
        let tombstone = NFDocumentOriginalTombstone(
            documentID: remote.documentID,
            contentHash: hash,
            deletedAt: remote.modifiedAt.addingTimeInterval(1)
        )
        let decision = try await queue.applyRemoteTombstone(tombstone)
        XCTAssertEqual(decision, .acceptRemote)

        try await queue.reconcile([])
        let snapshot = try await queue.snapshot()
        XCTAssertFalse(snapshot.revisions.contains { $0.documentID == remote.documentID })
        XCTAssertTrue(snapshot.tombstones.contains { $0.documentID == remote.documentID })
        XCTAssertFalse(snapshot.pending.contains {
            $0.operation == .saveAsset || $0.operation == .saveDocument
        })
    }

    func testConflictPolicyIsCommutativeAcrossPolicyAndConsentFieldsAndIgnoresPath() {
        let id = UUID()
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        let lhs = revision(
            id: id,
            hash: String(repeating: "a", count: 64),
            path: "/device-a/private/path",
            modifiedAt: date,
            aiPolicy: "noAI",
            consentVersion: 0,
            consentedAt: nil
        )
        let rhs = revision(
            id: id,
            hash: String(repeating: "a", count: 64),
            path: "/device-b/different/path",
            modifiedAt: date,
            aiPolicy: "onDeviceOnly",
            consentVersion: 4,
            consentedAt: date
        )

        let forward = NFDocumentOriginalConflictPolicy.winner(lhs, rhs)
        let reverse = NFDocumentOriginalConflictPolicy.winner(rhs, lhs)
        XCTAssertTrue(forward.isSemanticallyEqual(to: reverse))
        XCTAssertEqual(forward.aiPolicyRaw, "noAI")

        let mirrorOnly = revision(
            id: id,
            hash: lhs.contentHash,
            path: "/third/device",
            modifiedAt: date,
            aiPolicy: lhs.aiPolicyRaw,
            consentVersion: lhs.pccConsentPolicyVersion,
            consentedAt: lhs.pccConsentedAt
        )
        XCTAssertTrue(lhs.isSemanticallyEqual(to: mirrorOnly))
    }

    func testZoneLossClearsRemoteConfirmationAndRequeuesLiveAssets() async throws {
        let file = try makeFile(contents: "zone recovery")
        defer { try? FileManager.default.removeItem(at: file) }
        let queue = NFDocumentAssetMutationQueue(store: NFInMemoryDocumentAssetSyncStateStore())
        let saved = try await queue.enqueueUpsert(input(id: UUID(), file: file))
        try await queue.acknowledge(recordName: saved.assetRecordName)
        try await queue.acknowledge(recordName: saved.documentRecordName)
        try await queue.recordServerSystemFields(
            recordName: saved.documentRecordName,
            data: Data("obsolete-zone-fields".utf8)
        )
        let completed = try await queue.snapshot()
        XCTAssertTrue(completed.pending.isEmpty)

        try await queue.recoverFromZoneLoss()
        let recovered = try await queue.snapshot()
        let staleSystemFields = try await queue.serverSystemFields(
            recordName: saved.documentRecordName
        )
        XCTAssertFalse(recovered.confirmedRemoteAssetHashes.contains(saved.contentHash))
        XCTAssertNil(staleSystemFields)
        XCTAssertTrue(recovered.pending.contains { $0.operation == .saveAsset })
        XCTAssertTrue(recovered.pending.contains { $0.operation == .saveDocument })
    }

    func testAccountSwitchDiscardsAccountScopedStateAndPreservesLiveOriginals() async throws {
        let file = try makeFile(contents: "account switch local original")
        defer { try? FileManager.default.removeItem(at: file) }
        let queue = NFDocumentAssetMutationQueue(store: NFInMemoryDocumentAssetSyncStateStore())
        let live = try await queue.enqueueUpsert(input(id: UUID(), file: file))
        try await queue.acknowledge(recordName: live.assetRecordName)
        try await queue.acknowledge(recordName: live.documentRecordName)
        try await queue.recordServerSystemFields(
            recordName: live.documentRecordName,
            data: Data("prior-account-change-tag".utf8)
        )
        try await queue.replaceEngineStateSerialization(Data("prior-account-engine".utf8))

        let deletedID = UUID()
        _ = try await queue.enqueueUpsert(input(id: deletedID, file: file))
        try await queue.enqueueDelete(documentID: deletedID)

        try await queue.prepareForAccountSwitch()

        let reset = try await queue.snapshot()
        XCTAssertNil(reset.engineStateSerialization)
        XCTAssertNil(reset.lastSuccessfulSyncAt)
        XCTAssertTrue(reset.confirmedRemoteAssetHashes.isEmpty)
        XCTAssertTrue(reset.tombstones.isEmpty)
        let staleSystemFields = try await queue.serverSystemFields(
            recordName: live.documentRecordName
        )
        XCTAssertNil(staleSystemFields)
        XCTAssertEqual(reset.revisions.map(\.documentID), [live.documentID])
        XCTAssertTrue(reset.pending.contains {
            $0.operation == .saveAsset && $0.contentHash == live.contentHash
        })
        XCTAssertTrue(reset.pending.contains {
            $0.operation == .saveDocument && $0.documentID == live.documentID
        })
        XCTAssertFalse(reset.pending.contains {
            $0.documentID == deletedID || $0.operation == .saveTombstone
        })
    }

    func testAccountSwitchIsolationSurvivesQueueRelaunchWithoutOldTagsTombstonesOrDeletions() async throws {
        let root = FileManager.default.temporaryDirectory.appending(
            path: "NF-Account-Switch-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        let stateURL = root.appending(path: "queue.json", directoryHint: .notDirectory)
        let file = try makeFile(contents: "persisted account switch original")
        defer {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: file)
        }
        let firstStore = NFFileDocumentAssetSyncStateStore(fileURL: stateURL)
        let firstQueue = NFDocumentAssetMutationQueue(store: firstStore)
        let live = try await firstQueue.enqueueUpsert(input(id: UUID(), file: file))
        try await firstQueue.acknowledge(recordName: live.assetRecordName)
        try await firstQueue.acknowledge(recordName: live.documentRecordName)
        try await firstQueue.acceptDownloadedAsset(hash: live.contentHash, localURL: file)
        try await firstQueue.recordServerSystemFields(
            recordName: live.assetRecordName,
            data: Data("old-account-asset-tag".utf8)
        )
        try await firstQueue.recordServerSystemFields(
            recordName: live.documentRecordName,
            data: Data("old-account-document-tag".utf8)
        )
        try await firstQueue.replaceEngineStateSerialization(Data("old-account-engine".utf8))

        let deleted = try await firstQueue.enqueueUpsert(input(id: UUID(), file: file))
        try await firstQueue.acknowledge(recordName: deleted.documentRecordName)
        try await firstQueue.enqueueDelete(documentID: deleted.documentID)
        try await firstQueue.recordServerSystemFields(
            recordName: NFPrivateCloudRecordIdentity.tombstone(deleted.documentID),
            data: Data("old-account-tombstone-tag".utf8)
        )
        try await firstQueue.prepareForAccountSwitch()

        // A fresh queue instance proves isolation is durable rather than an
        // adapter-instance guard that disappears on process relaunch.
        let relaunched = NFDocumentAssetMutationQueue(
            store: NFFileDocumentAssetSyncStateStore(fileURL: stateURL)
        )
        let snapshot = try await relaunched.snapshot()
        XCTAssertNil(snapshot.engineStateSerialization)
        XCTAssertNil(snapshot.lastSuccessfulSyncAt)
        XCTAssertTrue(snapshot.tombstones.isEmpty)
        XCTAssertTrue(snapshot.confirmedRemoteAssetHashes.isEmpty)
        XCTAssertTrue(snapshot.downloadedAssetPathsByHash.isEmpty)
        XCTAssertEqual(snapshot.revisions.map(\.documentID), [live.documentID])
        XCTAssertEqual(
            Set(snapshot.pending.map(\.operation)),
            Set([.saveAsset, .saveDocument])
        )
        XCTAssertFalse(snapshot.pending.contains {
            !$0.isSave || $0.documentID == deleted.documentID
        })
        let relaunchedAssetFields = try await relaunched.serverSystemFields(
            recordName: live.assetRecordName
        )
        let relaunchedDocumentFields = try await relaunched.serverSystemFields(
            recordName: live.documentRecordName
        )
        let relaunchedTombstoneFields = try await relaunched.serverSystemFields(
            recordName: NFPrivateCloudRecordIdentity.tombstone(deleted.documentID)
        )
        XCTAssertNil(relaunchedAssetFields)
        XCTAssertNil(relaunchedDocumentFields)
        XCTAssertNil(relaunchedTombstoneFields)
    }

    func testAccountChangeLockSurvivesRelaunchAndImportedProfileCannotClearIt() throws {
        let suiteName = "NFPrivateCloudAccountLock.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        NFPrivateSyncBootstrapPreference.setAfterExplicitUserChoice(true, defaults: defaults)
        XCTAssertTrue(NFPrivateSyncBootstrapPreference.isEnabled(defaults: defaults))
        NFPrivateSyncBootstrapPreference.lockAfterAccountChange(defaults: defaults)
        XCTAssertTrue(NFPrivateSyncBootstrapPreference.isAccountChangeLocked(defaults: defaults))
        XCTAssertFalse(NFPrivateSyncBootstrapPreference.isEnabled(defaults: defaults))

        let relaunchedDefaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        NFPrivateSyncBootstrapPreference.applyImportedProfilePreference(
            true,
            defaults: relaunchedDefaults
        )
        XCTAssertTrue(NFPrivateSyncBootstrapPreference.isAccountChangeLocked(
            defaults: relaunchedDefaults
        ))
        XCTAssertFalse(NFPrivateSyncBootstrapPreference.isEnabled(defaults: relaunchedDefaults))

        NFPrivateSyncBootstrapPreference.setAfterExplicitUserChoice(
            false,
            defaults: relaunchedDefaults
        )
        XCTAssertFalse(NFPrivateSyncBootstrapPreference.isAccountChangeLocked(
            defaults: relaunchedDefaults
        ))
        XCTAssertFalse(NFPrivateSyncBootstrapPreference.isEnabled(defaults: relaunchedDefaults))

        NFPrivateSyncBootstrapPreference.lockAfterAccountChange(defaults: relaunchedDefaults)
        NFPrivateSyncBootstrapPreference.setAfterExplicitUserChoice(
            true,
            defaults: relaunchedDefaults
        )
        XCTAssertFalse(NFPrivateSyncBootstrapPreference.isAccountChangeLocked(
            defaults: relaunchedDefaults
        ))
        XCTAssertTrue(NFPrivateSyncBootstrapPreference.isEnabled(defaults: relaunchedDefaults))
    }

    @MainActor
    func testReloadDeterministicallyReconcilesCloudDomainDuplicatesWithoutDeletingBackingRows() throws {
        let schema = Schema(versionedSchema: NFSchemaV1.self)
        let container = try ModelContainer(
            for: schema,
            migrationPlan: NFSchemaMigrationPlan.self,
            configurations: try NFPersistentStoreLocation.configurations(inMemory: true)
        )
        let store = AppStore(context: container.mainContext)
        let early = Date(timeIntervalSince1970: 1_700_000_000)
        let late = Date(timeIntervalSince1970: 1_800_000_000)

        let weeklyA = WeeklyTransferStateRecord(state: NFWeeklyTransferState(
            completedMissionIDs: ["mission-a"],
            deferredUntilByMissionID: ["shared": late.addingTimeInterval(500)]
        ))
        weeklyA.modifiedAt = early
        let weeklyB = WeeklyTransferStateRecord(state: NFWeeklyTransferState(
            completedMissionIDs: ["mission-b"],
            deferredUntilByMissionID: ["shared": late]
        ))
        weeklyB.modifiedAt = late

        let completedReassessment = ReassessmentStateRecord(state: NFReassessmentState(
            completedCycle: 3,
            lastCompletedAt: early,
            lastCompletedBlock: .logicMetacognition
        ))
        completedReassessment.modifiedAt = early
        let newerButRegressedReassessment = ReassessmentStateRecord(state: NFReassessmentState(
            completedCycle: 2,
            dueAt: late
        ))
        newerButRegressedReassessment.modifiedAt = late

        let sessionID = UUID()
        let completedCheckpoint = SessionCheckpointRecord(
            sessionID: sessionID,
            lab: .logicDebugging,
            source: .focused,
            seed: 1,
            currentIndex: 2,
            itemCount: 2,
            response: "done",
            scratchpad: "",
            results: [true, true],
            evidenceClass: .practice,
            isComplete: true
        )
        completedCheckpoint.updatedAt = early
        let clockSkewedActiveCheckpoint = SessionCheckpointRecord(
            sessionID: sessionID,
            lab: .logicDebugging,
            source: .focused,
            seed: 1,
            currentIndex: 1,
            itemCount: 2,
            response: "active",
            scratchpad: "",
            results: [true],
            evidenceClass: .practice,
            isComplete: false
        )
        clockSkewedActiveCheckpoint.updatedAt = late

        let profileID = UUID()
        let planID = "nf.plan.test.duplicate"
        let firstPlan = try DailyPlanRecord(plan: NFCanonicalDailyPlan(
            id: planID,
            profileID: profileID,
            localDayKey: "2026-08-12",
            seed: 10,
            policyVersion: NFDailyScheduler.policyVersion,
            requestedMinutes: 10,
            scheduledMinutes: 0,
            blocks: [],
            prioritySnapshot: [],
            replacement: nil
        ))
        firstPlan.createdAt = early
        let laterDuplicatePlan = try DailyPlanRecord(plan: NFCanonicalDailyPlan(
            id: planID,
            profileID: profileID,
            localDayKey: "2026-08-12",
            seed: 99,
            policyVersion: NFDailyScheduler.policyVersion,
            requestedMinutes: 10,
            scheduledMinutes: 0,
            blocks: [],
            prioritySnapshot: [],
            replacement: nil
        ))
        laterDuplicatePlan.createdAt = late

        for record in [weeklyA, weeklyB] { container.mainContext.insert(record) }
        for record in [completedReassessment, newerButRegressedReassessment] {
            container.mainContext.insert(record)
        }
        for record in [completedCheckpoint, clockSkewedActiveCheckpoint] {
            container.mainContext.insert(record)
        }
        for record in [firstPlan, laterDuplicatePlan] { container.mainContext.insert(record) }
        try container.mainContext.save()

        store.reload()
        XCTAssertEqual(
            store.weeklyTransferStateRecord?.snapshot.completedMissionIDs,
            Set(["mission-a", "mission-b"])
        )
        XCTAssertEqual(
            store.weeklyTransferStateRecord?.snapshot.deferredUntilByMissionID["shared"],
            late.addingTimeInterval(500)
        )
        XCTAssertEqual(store.weeklyTransferStateRecord?.modifiedAt, late)
        XCTAssertEqual(store.reassessmentStateRecord?.completedCycle, 3)
        XCTAssertEqual(store.sessionCheckpoints.count, 1)
        XCTAssertTrue(store.sessionCheckpoints[0].isComplete)
        XCTAssertEqual(store.dailyPlans.count, 1)
        XCTAssertEqual(store.dailyPlans[0].snapshot?.seed, 10)

        // A second reload is stable and does not advance the merge clock.
        let weeklyPayload = store.weeklyTransferStateRecord?.deferredUntilPayload
        store.reload()
        XCTAssertEqual(store.weeklyTransferStateRecord?.modifiedAt, late)
        XCTAssertEqual(store.weeklyTransferStateRecord?.deferredUntilPayload, weeklyPayload)

        // Reload projects one deterministic domain winner but does not emit
        // speculative CloudKit deletions for still-unconverged backing objects.
        XCTAssertEqual(try container.mainContext.fetch(
            FetchDescriptor<WeeklyTransferStateRecord>()
        ).count, 2)
        XCTAssertEqual(try container.mainContext.fetch(
            FetchDescriptor<ReassessmentStateRecord>()
        ).count, 2)
        XCTAssertEqual(try container.mainContext.fetch(
            FetchDescriptor<SessionCheckpointRecord>()
        ).count, 2)
        XCTAssertEqual(try container.mainContext.fetch(
            FetchDescriptor<DailyPlanRecord>()
        ).count, 2)
    }

    @MainActor
    func testFreshAccountPreparationPreservesDocumentsButRequiresNewOriginalOptIn() throws {
        let schema = Schema(versionedSchema: NFSchemaV1.self)
        let container = try ModelContainer(
            for: schema,
            migrationPlan: NFSchemaMigrationPlan.self,
            configurations: try NFPersistentStoreLocation.configurations(inMemory: true)
        )
        let root = FileManager.default.temporaryDirectory.appending(
            path: "NF-Fresh-Account-Documents-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let syncedURL = root.appending(path: "synced.txt")
        let localURL = root.appending(path: "local.txt")
        try Data("preserve synced original".utf8).write(to: syncedURL)
        try Data("preserve local original".utf8).write(to: localURL)
        let synced = SourceDocumentRecord(
            filename: "synced.txt",
            typeIdentifier: "public.plain-text",
            sizeBytes: 24,
            localPath: syncedURL.path
        )
        synced.syncPolicy = NFDocumentSyncPolicy.privateOriginal.rawValue
        synced.characterCount = 777
        let local = SourceDocumentRecord(
            filename: "local.txt",
            typeIdentifier: "public.plain-text",
            sizeBytes: 23,
            localPath: localURL.path
        )
        container.mainContext.insert(synced)
        container.mainContext.insert(local)
        try container.mainContext.save()
        let store = AppStore(context: container.mainContext, documentStorageRootURL: root)

        try store.prepareDocumentsForFreshCloudAccount()

        XCTAssertEqual(store.documents.count, 2)
        XCTAssertTrue(store.documents.allSatisfy {
            $0.syncPolicy == NFDocumentSyncPolicy.localOnly.rawValue
        })
        XCTAssertEqual(
            store.documents.first(where: { $0.id == synced.id })?.characterCount,
            777
        )
        XCTAssertEqual(try Data(contentsOf: syncedURL), Data("preserve synced original".utf8))
        XCTAssertEqual(try Data(contentsOf: localURL), Data("preserve local original".utf8))
    }

    func testCloudRecordCodecUsesOnlyAllowlistedFields() throws {
        let file = try makeFile(contents: "field boundary")
        defer { try? FileManager.default.removeItem(at: file) }
        let hash = try NFContentAddressedAssetHasher.sha256(fileURL: file)
        let value = revision(id: UUID(), hash: hash, path: file.path)
        let mutation = NFDocumentAssetPendingMutation(
            id: value.documentRecordName,
            operation: .saveDocument,
            recordName: value.documentRecordName,
            documentID: value.documentID,
            contentHash: value.contentHash,
            revision: value,
            tombstone: nil,
            attemptCount: 0,
            notBefore: nil,
            lastFailure: nil
        )
        let zone = CKRecordZone.ID(zoneName: "test", ownerName: CKCurrentUserDefaultName)
        let record = try XCTUnwrap(NFPrivateDocumentCloudRecordCodec.makeRecord(
            for: mutation,
            zoneID: zone
        ))

        XCTAssertTrue(NFPrivateCloudSchemaManifest.fieldsArePrivacySafe(
            recordType: record.recordType,
            keys: Set(record.allKeys())
        ))
        XCTAssertTrue(Set(record.allKeys()).isDisjoint(
            with: NFPrivateCloudSchemaManifest.prohibitedDeviceLocalFieldKeys
        ))
        XCTAssertFalse(record.allKeys().contains("localFilePath"))
    }

    func testCloudKitErrorsMapWithoutRawDescriptions() throws {
        let network = NSError(
            domain: CKErrorDomain,
            code: CKError.Code.networkFailure.rawValue,
            userInfo: [CKErrorRetryAfterKey: 12]
        )
        XCTAssertEqual(
            NFCloudKitErrorMapper.map(network),
            .networkUnavailable(retryAfterSeconds: 12)
        )
        let quota = NSError(domain: CKErrorDomain, code: CKError.Code.quotaExceeded.rawValue)
        XCTAssertEqual(NFCloudKitErrorMapper.map(quota), .quotaExceeded)
        XCTAssertTrue(NFCloudKitErrorMapper.map(quota).isRetryable)
        XCTAssertEqual(NFCloudKitErrorMapper.map(quota).requestedRetryDelay, 3_600)
        let alreadyDeleted = NSError(
            domain: CKErrorDomain,
            code: CKError.Code.unknownItem.rawValue
        )
        XCTAssertTrue(NFCloudKitErrorMapper.deletionIsAlreadyConverged(alreadyDeleted))
        XCTAssertFalse(NFCloudKitErrorMapper.deletionIsAlreadyConverged(network))

        let failedID = CKRecord.ID(recordName: "document-safe-id")
        let partial = NSError(
            domain: CKErrorDomain,
            code: CKError.Code.partialFailure.rawValue,
            userInfo: [
                CKPartialErrorsByItemIDKey: [
                    failedID: NSError(
                        domain: CKErrorDomain,
                        code: CKError.Code.serviceUnavailable.rawValue
                    )
                ]
            ]
        )
        XCTAssertEqual(
            NFCloudKitErrorMapper.map(partial),
            .partialFailure(failedRecordNames: ["document-safe-id"])
        )
        XCTAssertEqual(NFCloudKitErrorMapper.map(partial).redactedCode, "partial-failure")
    }

    @MainActor
    func testVerifiedRemoteOriginalMaterializesIntoLocalLibraryAndChunks() async throws {
        let file = try makeFile(contents: "Remote source text for citation-grounded retrieval.")
        defer { try? FileManager.default.removeItem(at: file) }
        let hash = try NFContentAddressedAssetHasher.sha256(fileURL: file)
        let id = UUID()
        let remote = revision(id: id, hash: hash, path: file.path)
        let schema = Schema(versionedSchema: NFSchemaV1.self)
        let container = try ModelContainer(
            for: schema,
            migrationPlan: NFSchemaMigrationPlan.self,
            configurations: try NFPersistentStoreLocation.configurations(inMemory: true)
        )
        let documentRoot = FileManager.default.temporaryDirectory.appending(
            path: "NF-Private-Cloud-Documents-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        defer { try? FileManager.default.removeItem(at: documentRoot) }
        let appStore = AppStore(
            context: container.mainContext,
            documentStorageRootURL: documentRoot
        )

        try await appStore.materializeSyncedDocument(remote)

        let document = try XCTUnwrap(appStore.documents.first { $0.id == id })
        XCTAssertEqual(document.syncPolicy, NFDocumentSyncPolicy.privateOriginal.rawValue)
        XCTAssertNotEqual(document.localPath, file.path)
        XCTAssertTrue(FileManager.default.fileExists(atPath: document.localPath))
        XCTAssertFalse(appStore.sourceChunks.filter { $0.documentID == id }.isEmpty)
        try appStore.deleteDocument(document)
    }

    @MainActor
    func testCancelledRemoteMaterializationLeavesNoRecordOrManagedCopy() async throws {
        let file = try makeFile(contents: "Cancellation-safe remote source.")
        defer { try? FileManager.default.removeItem(at: file) }
        let hash = try NFContentAddressedAssetHasher.sha256(fileURL: file)
        let documentID = UUID()
        let remote = revision(
            id: documentID,
            hash: hash,
            path: file.path,
            sizeBytes: fileSize(file)
        )
        let (appStore, container, documentRoot) = try makeStore(iCloudEnabled: true)
        defer {
            _ = container
            try? FileManager.default.removeItem(at: documentRoot)
        }
        let gate = PrivateCloudAsyncGate()
        let task = Task { @MainActor in
            await gate.wait()
            try await appStore.materializeSyncedDocument(remote)
        }

        task.cancel()
        await gate.open()
        do {
            try await task.value
            XCTFail("Expected cancellation")
        } catch is CancellationError {
            // Expected: cancellation is not converted into an extraction failure.
        }

        XCTAssertFalse(appStore.documents.contains { $0.id == documentID })
        let managedEntries = (try? FileManager.default.contentsOfDirectory(
            at: documentRoot,
            includingPropertiesForKeys: nil
        )) ?? []
        XCTAssertTrue(managedEntries.isEmpty)
    }

    @MainActor
    func testRemoteHashMismatchLeavesManagedStorageWithoutPartialCopies() async throws {
        let file = try makeFile(contents: "Remote source whose declared digest is invalid.")
        defer { try? FileManager.default.removeItem(at: file) }
        let documentID = UUID()
        let remote = revision(
            id: documentID,
            hash: String(repeating: "0", count: 64),
            path: file.path,
            sizeBytes: fileSize(file)
        )
        let (appStore, container, documentRoot) = try makeStore(iCloudEnabled: true)
        defer {
            _ = container
            try? FileManager.default.removeItem(at: documentRoot)
        }

        do {
            try await appStore.materializeSyncedDocument(remote)
            XCTFail("Expected the mismatched digest to fail closed")
        } catch let error as NFDocumentAssetIntegrityError {
            XCTAssertEqual(error, .contentHashMismatch)
        }

        XCTAssertFalse(appStore.documents.contains { $0.id == documentID })
        let managedEntries = (try? FileManager.default.contentsOfDirectory(
            at: documentRoot,
            includingPropertiesForKeys: nil
        )) ?? []
        XCTAssertTrue(managedEntries.isEmpty)
    }

    @MainActor
    func testEqualTimestampRemoteWinnerUpdatesExistingDocumentMetadataContentAndChunks() async throws {
        let firstFile = try makeFile(contents: "First synced source with an older representation.")
        let secondFile = try makeFile(contents: "Second synced source with replacement evidence.")
        defer {
            try? FileManager.default.removeItem(at: firstFile)
            try? FileManager.default.removeItem(at: secondFile)
        }
        let firstHash = try NFContentAddressedAssetHasher.sha256(fileURL: firstFile)
        let secondHash = try NFContentAddressedAssetHasher.sha256(fileURL: secondFile)
        let candidates = [(firstFile, firstHash), (secondFile, secondHash)].sorted { $0.1 < $1.1 }
        let remoteCandidate = candidates[0]
        let localCandidate = candidates[1]
        let expectedRemoteText = String(
            decoding: try Data(contentsOf: remoteCandidate.0),
            as: UTF8.self
        )
        let documentID = UUID()
        let tieDate = Date(timeIntervalSince1970: 1_800_000_000)
        let (appStore, container, documentRoot) = try makeStore(iCloudEnabled: true)
        defer {
            _ = container
            try? FileManager.default.removeItem(at: documentRoot)
        }
        let local = revision(
            id: documentID,
            hash: localCandidate.1,
            path: localCandidate.0.path,
            modifiedAt: tieDate,
            filename: "local-source.txt",
            sizeBytes: fileSize(localCandidate.0)
        )
        try await appStore.materializeSyncedDocument(local)
        let priorMirrorPath = try XCTUnwrap(appStore.documents.first).localPath
        let remote = revision(
            id: documentID,
            hash: remoteCandidate.1,
            path: remoteCandidate.0.path,
            modifiedAt: tieDate,
            aiPolicy: DocumentAIPolicy.noAI.rawValue,
            consentVersion: 0,
            consentedAt: nil,
            filename: "remote-winner.txt",
            sizeBytes: fileSize(remoteCandidate.0)
        )
        let transport = PrivateCloudTransportProbe(revisions: [remote])
        let coordinator = NFSystemIntegrationCoordinator(
            launchPrivateCloudConfiguration: NFPrivateCloudRuntimeConfiguration(
                containerIdentifier: "iCloud.com.zacrotech.NeuroForge"
            ),
            privateDocumentTransport: transport
        )

        await coordinator.reconcilePrivateDocumentSync(store: appStore)

        let updated = try XCTUnwrap(appStore.documents.first { $0.id == documentID })
        XCTAssertEqual(updated.filename, "remote-winner.txt")
        XCTAssertEqual(updated.aiPolicyRaw, DocumentAIPolicy.noAI.rawValue)
        XCTAssertEqual(
            try NFContentAddressedAssetHasher.sha256(fileURL: URL(fileURLWithPath: updated.localPath)),
            remoteCandidate.1
        )
        XCTAssertNotEqual(updated.localPath, remoteCandidate.0.path)
        XCTAssertFalse(FileManager.default.fileExists(atPath: priorMirrorPath))
        XCTAssertTrue(appStore.sourceChunks.contains {
            $0.documentID == documentID && $0.text.contains(expectedRemoteText)
        })
        try appStore.deleteDocument(updated)
    }

    @MainActor
    func testAcceptedRemoteTombstoneDeletesLocalMirrorChunksAndGenerationsWithoutRequeue() async throws {
        let file = try makeFile(contents: "Source that will be remotely deleted.")
        defer { try? FileManager.default.removeItem(at: file) }
        let hash = try NFContentAddressedAssetHasher.sha256(fileURL: file)
        let documentID = UUID()
        let (appStore, container, documentRoot) = try makeStore(iCloudEnabled: true)
        defer {
            _ = container
            try? FileManager.default.removeItem(at: documentRoot)
        }
        let local = revision(
            id: documentID,
            hash: hash,
            path: file.path,
            sizeBytes: fileSize(file)
        )
        try await appStore.materializeSyncedDocument(local)
        try saveGeneration(in: appStore, documentID: documentID)
        XCTAssertFalse(appStore.sourceChunks.filter { $0.documentID == documentID }.isEmpty)
        XCTAssertEqual(appStore.aiGenerations.count, 1)

        let tombstone = NFDocumentOriginalTombstone(
            documentID: documentID,
            contentHash: hash,
            deletedAt: local.modifiedAt.addingTimeInterval(1)
        )
        let transport = PrivateCloudTransportProbe(tombstones: [tombstone])
        let coordinator = NFSystemIntegrationCoordinator(
            launchPrivateCloudConfiguration: NFPrivateCloudRuntimeConfiguration(
                containerIdentifier: "iCloud.com.zacrotech.NeuroForge"
            ),
            privateDocumentTransport: transport
        )

        await coordinator.reconcilePrivateDocumentSync(store: appStore)
        XCTAssertFalse(appStore.documents.contains { $0.id == documentID })
        XCTAssertFalse(appStore.sourceChunks.contains { $0.documentID == documentID })
        XCTAssertFalse(appStore.aiGenerations.contains {
            $0.sourceDocumentIDsRaw.split(separator: ",").contains(Substring(documentID.uuidString))
        })

        await coordinator.reconcilePrivateDocumentSync(store: appStore)
        let lastReconciledIDs = await transport.lastReconciledDocumentIDs()
        XCTAssertTrue(lastReconciledIDs.isEmpty)
    }

    @MainActor
    func testDeleteAllClearsInjectedTransportQueueAssetCacheAndState() async throws {
        let (appStore, container, documentRoot) = try makeStore(iCloudEnabled: false)
        defer {
            _ = container
            try? FileManager.default.removeItem(at: documentRoot)
        }
        try FileManager.default.createDirectory(at: documentRoot, withIntermediateDirectories: true)
        let orphanURL = documentRoot.appending(
            path: ".pending-replacement-orphan",
            directoryHint: .notDirectory
        )
        try Data("orphaned prior revision".utf8).write(to: orphanURL)
        let defaults = try XCTUnwrap(UserDefaults(
            suiteName: "NFPrivateCloudCleanup.\(UUID().uuidString)"
        ))
        let transport = PrivateCloudTransportProbe(hasLocalQueueState: true, hasCachedAssets: true)
        let coordinator = NFSystemIntegrationCoordinator(
            defaults: defaults,
            notificationClient: PrivateCloudNoopNotificationClient(),
            spotlightClient: PrivateCloudNoopSpotlightClient(),
            preparedExportCleaner: {},
            authoringCacheCleaner: {},
            widgetSnapshotCleaner: {},
            privateSyncApplicationStateCleaner: {},
            privateDocumentTransport: transport
        )

        let receipt = try await coordinator.deleteAllLocalData(store: appStore)
        let cleanup = await transport.cleanupSnapshot()

        XCTAssertTrue(receipt.completedComponents.contains(.privateSyncState))
        XCTAssertEqual(cleanup.clearCount, 1)
        XCTAssertFalse(cleanup.hasLocalQueueState)
        XCTAssertFalse(cleanup.hasCachedAssets)
        XCTAssertFalse(NFPrivateSyncBootstrapPreference.isEnabled(defaults: defaults))
        XCTAssertFalse(FileManager.default.fileExists(atPath: orphanURL.path))
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: documentRoot.path).isEmpty)
    }

    @MainActor
    func testLocalOnlyDeleteRequiresReopenWhenStructuredCloudWasActive() async throws {
        let suiteName = "NFPrivateCloudDeleteGate.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        NFPrivateSyncBootstrapPreference.set(true, defaults: defaults)
        let schema = Schema(versionedSchema: NFSchemaV1.self)
        let container = try ModelContainer(
            for: schema,
            migrationPlan: NFSchemaMigrationPlan.self,
            configurations: try NFPersistentStoreLocation.configurations(inMemory: true)
        )
        let appStore = AppStore(context: container.mainContext)
        let coordinator = NFSystemIntegrationCoordinator(
            defaults: defaults,
            launchPrivateCloudConfiguration: NFPrivateCloudRuntimeConfiguration(
                containerIdentifier: "iCloud.com.zacrotech.NeuroForge"
            )
        )

        do {
            _ = try await coordinator.deleteAllLocalData(store: appStore)
            XCTFail("Expected a restart gate before local-only deletion")
        } catch let error as NFPrivateSyncDeletionError {
            guard case .restartRequiredForLocalDeletion = error else {
                return XCTFail("Unexpected deletion gate: \(error)")
            }
        }
        XCTAssertFalse(NFPrivateSyncBootstrapPreference.isEnabled(defaults: defaults))
        XCTAssertNotNil(coordinator.localDataDeletionError)
    }

    @MainActor
    func testCloudAndDeviceDeletePersistsRestartBoundaryBeforeAnyLocalMutation() async throws {
        let file = try makeFile(contents: "Private original scheduled for complete deletion.")
        defer { try? FileManager.default.removeItem(at: file) }
        let hash = try NFContentAddressedAssetHasher.sha256(fileURL: file)
        let (appStore, container, documentRoot) = try makeStore(iCloudEnabled: true)
        defer {
            _ = container
            try? FileManager.default.removeItem(at: documentRoot)
        }
        let documentID = UUID()
        try await appStore.materializeSyncedDocument(revision(
            id: documentID,
            hash: hash,
            path: file.path,
            sizeBytes: fileSize(file)
        ))
        let suiteName = "NFPrivateCloudCompleteDelete.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        NFPrivateSyncBootstrapPreference.set(true, defaults: defaults)
        let transport = PrivateCloudTransportProbe()
        let deletionRequest = NFPrivateCloudCompleteDeletionRequest(
            id: UUID(),
            policy: NFPrivateCloudCompleteDeletionPolicy(
                validatedContainerIdentifier: "iCloud.com.zacrotech.NeuroForge"
            ),
            accountFingerprint: String(repeating: "a", count: 64),
            requestedAt: Date(timeIntervalSince1970: 1_900_000_000)
        )
        let coordinator = NFSystemIntegrationCoordinator(
            defaults: defaults,
            notificationClient: PrivateCloudNoopNotificationClient(),
            spotlightClient: PrivateCloudNoopSpotlightClient(),
            preparedExportCleaner: {},
            authoringCacheCleaner: {},
            widgetSnapshotCleaner: {},
            launchPrivateCloudConfiguration: NFPrivateCloudRuntimeConfiguration(
                containerIdentifier: "iCloud.com.zacrotech.NeuroForge"
            ),
            launchDurableStoreURL: documentRoot.appending(path: "injected-durable.store"),
            privateDocumentTransport: transport,
            completeCloudDeletionRequester: { _ in
                NFPrivateSyncBootstrapPreference.lockForCloudDeletion(defaults: defaults)
                return deletionRequest
            },
            structuredStorePurgeStager: { _, _ in
                NFPrivateCloudLocalPurgePreparation(
                    requiresRelaunch: true,
                    removedInactiveNamespaceCount: 0
                )
            }
        )
        let managedPath = try XCTUnwrap(
            appStore.documents.first(where: { $0.id == documentID })?.localPath
        )

        do {
            _ = try await coordinator.deleteAllData(
                scope: .privateCloudAndThisDevice,
                store: appStore
            )
            XCTFail("Complete deletion must stop at its durable restart boundary")
        } catch let error as NFPrivateSyncDeletionError {
            guard case .restartRequiredForCompleteDeletion = error else {
                return XCTFail("Unexpected deletion error: \(error)")
            }
        }

        XCTAssertNotNil(appStore.profile)
        XCTAssertTrue(appStore.documents.contains { $0.id == documentID })
        XCTAssertTrue(FileManager.default.fileExists(atPath: managedPath))
        XCTAssertFalse(NFPrivateSyncBootstrapPreference.isEnabled(defaults: defaults))
        XCTAssertTrue(NFPrivateSyncBootstrapPreference.isCloudDeletionLocked(defaults: defaults))
        let enqueuedDeletionIDs = await transport.enqueuedDeletionDocumentIDs()
        XCTAssertTrue(enqueuedDeletionIDs.isEmpty)
    }

    private struct IdentityFixture {
        let root: URL
        let defaults: UserDefaults
        let suiteName: String

        func cleanup() {
            try? FileManager.default.removeItem(at: root)
            defaults.removePersistentDomain(forName: suiteName)
        }
    }

    private func makeIdentityFixture() throws -> IdentityFixture {
        let suiteName = "NFPrivateCloudIdentityTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        let root = FileManager.default.temporaryDirectory.appending(
            path: "NF-Structured-Identity-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return IdentityFixture(root: root, defaults: defaults, suiteName: suiteName)
    }

    private func writeIdentityStore(_ contents: String, to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data(contents.utf8).write(to: url)
    }

    private func makeFile(contents: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(
            path: "NF-Asset-\(UUID().uuidString).txt",
            directoryHint: .notDirectory
        )
        try Data(contents.utf8).write(to: url, options: .atomic)
        return url
    }

    private enum CloudBootstrapProbeError: Error {
        case cloudUnavailable
    }

    private func input(id: UUID, file: URL) -> NFDocumentOriginalInput {
        NFDocumentOriginalInput(
            documentID: id,
            filename: "source.txt",
            typeIdentifier: "public.plain-text",
            localURL: file,
            modifiedAt: Date(timeIntervalSince1970: 1_800_000_000),
            aiPolicyRaw: "onDeviceOnly",
            pccConsentPolicyVersion: 0,
            pccConsentedAt: nil
        )
    }

    private func revision(
        id: UUID,
        hash: String,
        path: String,
        modifiedAt: Date = Date(timeIntervalSince1970: 1_800_000_000),
        aiPolicy: String = "onDeviceOnly",
        consentVersion: Int = 0,
        consentedAt: Date? = nil,
        filename: String = "source.txt",
        sizeBytes: Int64 = 42
    ) -> NFDocumentOriginalRevision {
        NFDocumentOriginalRevision(
            documentID: id,
            contentHash: hash,
            filename: filename,
            typeIdentifier: "public.plain-text",
            sizeBytes: sizeBytes,
            localFilePath: path,
            modifiedAt: modifiedAt,
            aiPolicyRaw: aiPolicy,
            pccConsentPolicyVersion: consentVersion,
            pccConsentedAt: consentedAt
        )
    }

    private func fileSize(_ url: URL) -> Int64 {
        Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
    }

    @MainActor
    private func makeStore(iCloudEnabled: Bool) throws -> (AppStore, ModelContainer, URL) {
        let schema = Schema(versionedSchema: NFSchemaV1.self)
        let container = try ModelContainer(
            for: schema,
            migrationPlan: NFSchemaMigrationPlan.self,
            configurations: try NFPersistentStoreLocation.configurations(inMemory: true)
        )
        let documentRoot = FileManager.default.temporaryDirectory.appending(
            path: "NF-Private-Cloud-Documents-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        let store = AppStore(
            context: container.mainContext,
            documentStorageRootURL: documentRoot
        )
        var draft = OnboardingDraft()
        draft.iCloudEnabled = iCloudEnabled
        container.mainContext.insert(UserProfileRecord(draft: draft))
        try container.mainContext.save()
        store.reload()
        return (store, container, documentRoot)
    }

    @MainActor
    private func saveGeneration(in store: AppStore, documentID: UUID) throws {
        let chunk = try XCTUnwrap(store.sourceChunks.first { $0.documentID == documentID }).snapshot
        let generationID = UUID()
        let request = NFAuthoringRequest(
            id: generationID,
            capability: .sourceGroundedPractice,
            lab: .scientificReasoning,
            field: .general,
            customTopic: "remote deletion",
            learningObjective: "use cited evidence",
            style: .shortAnswer,
            difficulty: 0.5,
            count: 1,
            seed: 7,
            sourceChunks: [chunk],
            documentPolicies: [.onDeviceOnly],
            aiMode: .disabled
        )
        let question = NFAuthoredQuestion(
            id: "remote-deletion-question",
            lab: .scientificReasoning,
            style: .shortAnswer,
            prompt: "What does the source state?",
            context: "Use the cited source.",
            choices: [],
            correctAnswer: "Source that will be remotely deleted.",
            acceptedAnswers: ["Source that will be remotely deleted."],
            explanation: "This is an exact source restatement.",
            hint: "Read the cited excerpt.",
            decisiveStep: "Restate the excerpt.",
            difficulty: 0.5,
            citationChunkIDs: [chunk.id],
            evidenceClass: .documentPractice
        )
        let result = NFAuthoringResult(
            questions: [question],
            provenance: NFAIGenerationProvenance(
                requestID: generationID,
                generatedAt: Date(),
                route: .deterministicFallback,
                routeReason: "Test fixture",
                promptVersion: NFAuthoringRequest.promptVersion,
                modelIdentifier: "deterministic-test",
                sourceChunkIDs: [chunk.id],
                sourceDocumentIDs: [documentID],
                validationVersion: NFAuthoringEngine.validationVersion,
                repairCount: 0,
                cacheKey: "remote-deletion-test",
                isFallback: true
            ),
            routeCandidates: [],
            validationStatus: NFAuthoringValidationStatus(
                level: .exactSourceRestatement,
                sourceSupport: .exactAnswerText
            ),
            validationNotes: []
        )
        try store.saveAIGeneration(request: request, result: result)
    }

    private func cloudEncryptedAttributeNames(in entity: Schema.Entity) -> Set<String> {
        Set(entity.attributes.compactMap { attribute in
            attribute.options.contains { String(describing: $0) == "allowsCloudEncryption" }
                ? attribute.name
                : nil
        })
    }
}

private actor PrivateCloudAsyncGate {
    private var isOpen = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        guard !isOpen else { return }
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    func open() {
        guard !isOpen else { return }
        isOpen = true
        let pending = waiters
        waiters.removeAll()
        for waiter in pending { waiter.resume() }
    }
}

private actor PrivateCloudSingleFlightProbe {
    private let operationGate: PrivateCloudAsyncGate
    private var operations = 0
    private var startWaiters: [CheckedContinuation<Void, Never>] = []

    init(operationGate: PrivateCloudAsyncGate) {
        self.operationGate = operationGate
    }

    func perform() async -> Int {
        operations += 1
        let waiters = startWaiters
        startWaiters.removeAll()
        for waiter in waiters { waiter.resume() }
        await operationGate.wait()
        return 73
    }

    func waitUntilStarted() async {
        guard operations == 0 else { return }
        await withCheckedContinuation { continuation in
            startWaiters.append(continuation)
        }
    }

    func invocationCount() -> Int { operations }
}

private extension Array {
    func asyncMap<Output>(
        _ transform: (Element) async -> Output
    ) async -> [Output] {
        var output: [Output] = []
        output.reserveCapacity(count)
        for element in self { output.append(await transform(element)) }
        return output
    }
}

private actor PrivateCloudTransportProbe: NFPrivateDocumentAssetTransport {
    private let revisions: [NFDocumentOriginalRevision]
    private let tombstones: [NFDocumentOriginalTombstone]
    private var reconciledDocumentIDBatches: [[UUID]] = []
    private var clearCount = 0
    private var hasLocalQueueState: Bool
    private var hasCachedAssets: Bool
    private var enqueuedDeletionIDs: Set<UUID> = []

    init(
        revisions: [NFDocumentOriginalRevision] = [],
        tombstones: [NFDocumentOriginalTombstone] = [],
        hasLocalQueueState: Bool = false,
        hasCachedAssets: Bool = false
    ) {
        self.revisions = revisions
        self.tombstones = tombstones
        self.hasLocalQueueState = hasLocalQueueState
        self.hasCachedAssets = hasCachedAssets
    }

    func start() -> NFPrivateDocumentTransportSnapshot { transportSnapshot }

    func reconcile(_ inputs: [NFDocumentOriginalInput]) {
        reconciledDocumentIDBatches.append(inputs.map(\.documentID))
    }

    func enqueueDeletion(documentID: UUID) {
        enqueuedDeletionIDs.insert(documentID)
    }
    func synchronize() -> NFPrivateDocumentTransportSnapshot { transportSnapshot }
    func snapshot() -> NFPrivateDocumentTransportSnapshot { transportSnapshot }
    func documentState(documentID: UUID) -> NFDocumentPrivateSyncState { .uploaded }
    func receivedRevisions() -> [NFDocumentOriginalRevision] { revisions }
    func receivedTombstones() -> [NFDocumentOriginalTombstone] { tombstones }

    func deletionVerification(
        requestedDocumentIDs: Set<UUID>
    ) -> NFPrivateDocumentDeletionVerification {
        NFPrivateDocumentDeletionVerification(
            requestedDocumentIDs: requestedDocumentIDs,
            durableTombstoneDocumentIDs: enqueuedDeletionIDs,
            pendingChangeCount: 0,
            lastSuccessfulSyncAt: transportSnapshot.lastSuccessfulSyncAt
        )
    }

    func clearLocalStatePreservingRemote() {
        clearCount += 1
        hasLocalQueueState = false
        hasCachedAssets = false
        enqueuedDeletionIDs.removeAll()
    }

    func stop() {}

    func lastReconciledDocumentIDs() -> [UUID] {
        reconciledDocumentIDBatches.last ?? []
    }

    func enqueuedDeletionDocumentIDs() -> Set<UUID> {
        enqueuedDeletionIDs
    }

    func cleanupSnapshot() -> (clearCount: Int, hasLocalQueueState: Bool, hasCachedAssets: Bool) {
        (clearCount, hasLocalQueueState, hasCachedAssets)
    }

    private var transportSnapshot: NFPrivateDocumentTransportSnapshot {
        NFPrivateDocumentTransportSnapshot(
            isInstalled: true,
            accountState: .available,
            phase: .idle,
            queue: NFSyncQueueMetrics(pendingRecordCount: 0, pendingAssetCount: 0),
            lastSuccessfulSyncAt: Date()
        )
    }
}

private actor PrivateCloudNoopNotificationClient: NFNotificationCenterClient {
    func refreshCategories(using presentation: NFNotificationCategoryPresentation) async {}
    func authorizationStatus() async -> NFNotificationAuthorizationStatus { .authorized }
    func requestAuthorizationAfterExplicitOptIn() async throws -> NFNotificationAuthorizationStatus { .authorized }
    func replaceManagedSchedules(with descriptors: [NFNotificationScheduleDescriptor]) async throws {}
    func removeManagedSchedules() async throws {}
}

private actor PrivateCloudNoopSpotlightClient: NFSpotlightIndexClient {
    func apply(_ plan: NFSpotlightIndexPlan) async throws {}
}

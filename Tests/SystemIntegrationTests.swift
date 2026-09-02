import Foundation
import SwiftData
import XCTest

@testable import NeuroForge

final class SystemIntegrationTests: XCTestCase {
    func testWidgetPlanStateKeepsActionAndDeepLinkConsistent() {
        let empty = NFWidgetSnapshot(
            schemaVersion: NFWidgetSnapshot.schemaVersion,
            language: .english,
            generatedAt: .now,
            localDayKey: "today",
            scheduledMinutes: 0,
            completedItems: 0,
            expectedItems: 0,
            reviewsDue: 0,
            blocks: []
        )
        XCTAssertEqual(empty.planState, .noPlan)
        XCTAssertEqual(empty.planState.deepLink.absoluteString, "neuroforge://today")

        let completed = NFWidgetSnapshot(
            schemaVersion: NFWidgetSnapshot.schemaVersion,
            language: .english,
            generatedAt: .now,
            localDayKey: "today",
            scheduledMinutes: 10,
            completedItems: 2,
            expectedItems: 3,
            reviewsDue: 0,
            blocks: [NFWidgetBlockSnapshot(title: "Practice", minutes: 10, isComplete: true)]
        )
        XCTAssertEqual(completed.planState, .completed)
        XCTAssertEqual(
            completed.planState.deepLink.absoluteString,
            "neuroforge://today?review=completed"
        )

        let encoded = try! JSONEncoder().encode(completed)
        let decoded = try! JSONDecoder().decode(NFWidgetSnapshot.self, from: encoded)
        XCTAssertEqual(decoded.language, .english)
        XCTAssertEqual(decoded.schemaVersion, 2)
        XCTAssertTrue(String(decoding: encoded, as: UTF8.self).contains("\"language\":\"en\""))
    }

    func testWidgetPresentationUsesSnapshotLanguageForAllRenderedCopyAndFormats() throws {
        let bundleURL = FileManager.default.temporaryDirectory
            .appending(path: "NFWidgetLocalizationTests-\(UUID().uuidString).bundle", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: bundleURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: bundleURL) }

        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        process.arguments = [
            "xcstringstool", "compile",
            repositoryRoot.appending(path: "Widgets/Localizable.xcstrings").path,
            "--output-directory", bundleURL.path,
            "--language", "en",
            "--language", "ja"
        ]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0)
        let widgetBundle = try XCTUnwrap(Bundle(path: bundleURL.path))

        func snapshot(
            language: NFWidgetLanguage,
            completedItems: Int,
            blocks: [NFWidgetBlockSnapshot]
        ) -> NFWidgetSnapshot {
            NFWidgetSnapshot(
                schemaVersion: NFWidgetSnapshot.schemaVersion,
                language: language,
                generatedAt: Date(timeIntervalSince1970: 1_800_000_000),
                localDayKey: "2027-01-15@04",
                scheduledMinutes: 10,
                completedItems: completedItems,
                expectedItems: blocks.isEmpty ? 0 : 2,
                reviewsDue: 1,
                blocks: blocks
            )
        }

        let activeBlocks = [
            NFWidgetBlockSnapshot(title: "Review", minutes: 2, isComplete: true),
            NFWidgetBlockSnapshot(title: "Practice", minutes: 8, isComplete: false)
        ]
        let english = NFWidgetPresentation(
            snapshot: snapshot(language: .english, completedItems: 1, blocks: activeBlocks),
            bundle: widgetBundle
        )
        let japanese = NFWidgetPresentation(
            snapshot: snapshot(language: .japanese, completedItems: 1, blocks: activeBlocks),
            bundle: widgetBundle
        )

        XCTAssertEqual(english.todayTitle, "Today")
        XCTAssertEqual(japanese.todayTitle, "今日")
        XCTAssertEqual(english.widgetDisplayName, "NeuroForge Today")
        XCTAssertEqual(japanese.widgetDisplayName, "NeuroForge 今日")
        XCTAssertEqual(
            japanese.widgetDescription,
            "今日のプライバシーに配慮したトレーニングプランを開始または続行します。"
        )
        XCTAssertEqual(english.planDateLabel, "Jan 15, 2027")
        XCTAssertEqual(japanese.planDateLabel, "2027年1月15日")
        XCTAssertEqual(english.duration(1), "1 minute")
        XCTAssertEqual(japanese.duration(1), "1分")
        XCTAssertEqual(english.duration(10, style: .compact), "10 min")
        XCTAssertEqual(japanese.duration(10, style: .compact), "10分")
        XCTAssertEqual(english.actionTitle, "Continue · 10 min plan")
        XCTAssertEqual(japanese.actionTitle, "続ける・10分プラン")
        XCTAssertEqual(english.accessorySummary, "1/2 complete")
        XCTAssertEqual(japanese.accessorySummary, "1/2 完了")
        XCTAssertEqual(english.progressPercent, "50%")
        XCTAssertEqual(japanese.progressPercent, "50%")
        XCTAssertTrue(english.accessibilityLabel.contains("Jan 15, 2027"))
        XCTAssertTrue(japanese.accessibilityLabel.contains("2027年1月15日"))
        XCTAssertTrue(japanese.accessibilityLabel.contains("プランを続けてください"))

        let emptyJapanese = NFWidgetPresentation(
            snapshot: snapshot(language: .japanese, completedItems: 0, blocks: []),
            bundle: widgetBundle
        )
        XCTAssertEqual(emptyJapanese.emptyPlanInstruction, "NeuroForgeを開いて、今日の非公開プランを準備してください。")
        XCTAssertEqual(emptyJapanese.actionTitle, "NeuroForgeを開く")
        XCTAssertEqual(emptyJapanese.accessorySummary, "プランはまだありません")
        XCTAssertTrue(emptyJapanese.accessibilityLabel.contains("プランはまだありません"))

        let readyJapanese = NFWidgetPresentation(
            snapshot: snapshot(
                language: .japanese,
                completedItems: 0,
                blocks: activeBlocks.map {
                    NFWidgetBlockSnapshot(title: $0.title, minutes: $0.minutes, isComplete: false)
                }
            ),
            bundle: widgetBundle
        )
        XCTAssertEqual(readyJapanese.actionTitle, "開始・10分プラン")
        XCTAssertTrue(readyJapanese.accessibilityLabel.contains("プランは未開始です"))

        let completedJapanese = NFWidgetPresentation(
            snapshot: snapshot(
                language: .japanese,
                completedItems: 2,
                blocks: activeBlocks.map {
                    NFWidgetBlockSnapshot(title: $0.title, minutes: $0.minutes, isComplete: true)
                }
            ),
            bundle: widgetBundle
        )
        XCTAssertEqual(completedJapanese.actionTitle, "今日を振り返る")
        XCTAssertEqual(completedJapanese.accessorySummary, "今日のプラン完了")
        XCTAssertTrue(completedJapanese.accessibilityLabel.contains("今日の学習を確認しましょう"))
    }
    func testMetricKitUsesFirstPartySubscriberWithoutPayloadPersistence() {
        NFMetricKitSubscriber.shared.start()
        let snapshot = NFMetricKitSubscriber.shared.snapshot()
        #if canImport(MetricKit)
        XCTAssertTrue(snapshot.isRegistered)
        #else
        XCTAssertFalse(snapshot.isRegistered)
        #endif
        XCTAssertGreaterThanOrEqual(snapshot.metricPayloadCount, 0)
        XCTAssertGreaterThanOrEqual(snapshot.diagnosticPayloadCount, 0)
    }

    func testNotificationPlanIsDeterministicLocalizedAndPrivacySafe() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let quietHours = NFQuietHours(
            startsAt: try XCTUnwrap(NFLocalClockTime(hour: 22, minute: 0)),
            endsAt: try XCTUnwrap(NFLocalClockTime(hour: 8, minute: 0))
        )
        let preferences = NFNotificationPreferences(
            dailyReminderTime: try XCTUnwrap(NFLocalClockTime(hour: 7, minute: 30)),
            trainingDays: [.monday, .wednesday],
            weeklySummaryEnabled: true,
            weeklySummaryWeekday: .sunday,
            weeklySummaryTime: try XCTUnwrap(NFLocalClockTime(hour: 9, minute: 15)),
            dueReviewReminderEnabled: false,
            quietHours: quietHours
        )
        let calendar = utcCalendar()
        let timeZone = try XCTUnwrap(TimeZone(identifier: "Asia/Tokyo"))

        let first = NFNotificationPlanner.makePlan(
            preferences: preferences,
            dueReviewAt: nil,
            now: now,
            calendar: calendar,
            timeZone: timeZone,
            language: .japanese
        )
        let duplicate = NFNotificationPlanner.makePlan(
            preferences: preferences,
            dueReviewAt: nil,
            now: now,
            calendar: calendar,
            timeZone: timeZone,
            language: .japanese
        )

        XCTAssertEqual(first, duplicate)
        XCTAssertEqual(first.descriptors.map(\.id), [
            "nf.notification.daily.2",
            "nf.notification.daily.4",
            "nf.notification.weekly-summary"
        ])
        XCTAssertEqual(first.notices, [.adjustedDailyReminderForQuietHours])
        XCTAssertTrue(first.descriptors.allSatisfy { $0.title.contains("NeuroForge") || $0.title.contains("練習") || $0.title.contains("振り返り") })

        for descriptor in first.descriptors where descriptor.kind == .dailyTraining {
            guard case let .weekly(_, time, identifier) = descriptor.recurrence else {
                return XCTFail("Expected weekly recurrence")
            }
            XCTAssertEqual(time, NFLocalClockTime(hour: 8, minute: 0))
            XCTAssertEqual(identifier, "Asia/Tokyo")
            XCTAssertFalse(descriptor.body.contains("notes"))
            XCTAssertFalse(descriptor.body.contains("score"))
        }
    }

    func testNotificationCategoryActionCopyUsesSelectedEnglishAndJapaneseLanguage() {
        let english = NFNotificationCategoryPresentation(language: .english)
        let japanese = NFNotificationCategoryPresentation(language: .japanese)

        XCTAssertEqual(english.openActionTitle, "Open NeuroForge")
        XCTAssertEqual(japanese.openActionTitle, "NeuroForgeを開く")
        XCTAssertNotEqual(english.openActionTitle, japanese.openActionTitle)
    }

    func testNotificationPlannerOmitsPastDueAndNeverImplicitlyOptsIn() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let preferences = NFNotificationPreferences(
            dueReviewReminderEnabled: true
        )

        XCTAssertTrue(preferences.hasConfiguredReminder)
        let plan = NFNotificationPlanner.makePlan(
            preferences: preferences,
            dueReviewAt: now.addingTimeInterval(-60),
            now: now,
            calendar: utcCalendar(),
            timeZone: try XCTUnwrap(TimeZone(identifier: "UTC")),
            language: .english
        )
        XCTAssertTrue(plan.descriptors.isEmpty)
        XCTAssertEqual(plan.notices, [.omittedPastDueReview])
        XCTAssertFalse(NFSpotlightPrivacyConsent().isExplicitlyEnabled)
    }

    func testBackgroundPlannerOnlyRequestsRelevantBestEffortWork() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let snapshot = NFBackgroundWorkSnapshot(
            shouldPrepareNextPlan: true,
            pendingSourceChunkCount: 800,
            expiredGeneratedCacheCount: 12,
            generatedCacheBytes: 600 * 1_024 * 1_024,
            privateSyncAssistanceRequested: true,
            privateSyncIsConfigured: false
        )

        let requests = NFBackgroundTaskPlanner.makeRequests(snapshot: snapshot, now: now)

        XCTAssertEqual(requests.map(\.kind), [
            .indexSourceChunks,
            .prepareDailyPlan,
            .cleanGeneratedCache
        ])
        XCTAssertFalse(requests.contains { $0.kind == .assistPrivateSync })
        XCTAssertEqual(requests.first?.earliestBeginDate, now.addingTimeInterval(5 * 60))
        XCTAssertEqual(requests.first?.requestClass, .processing)
        XCTAssertEqual(requests.first?.requiresExternalPower, true)
        XCTAssertTrue(requests.allSatisfy { !$0.requiresNetworkConnectivity })
    }

    func testEveryNotificationCarriesAnExactRouteAndCategory() {
        let plan = NFNotificationPlanner.makePlan(
            preferences: NFNotificationPreferences(
                dailyReminderTime: NFLocalClockTime(hour: 9, minute: 0),
                trainingDays: [.monday],
                weeklySummaryEnabled: true,
                weeklySummaryWeekday: .sunday,
                weeklySummaryTime: .nineAM,
                dueReviewReminderEnabled: true
            ),
            dueReviewAt: Date(timeIntervalSince1970: 1_800_003_600),
            now: Date(timeIntervalSince1970: 1_800_000_000),
            calendar: Calendar(identifier: .gregorian),
            timeZone: TimeZone(secondsFromGMT: 0)!,
            language: .english
        )

        XCTAssertEqual(Set(plan.descriptors.map(\.kind)), Set(NFNotificationScheduleKind.allCases))
        XCTAssertTrue(plan.descriptors.allSatisfy {
            $0.deepLinkURL.scheme == "neuroforge" && !$0.categoryIdentifier.isEmpty
        })
        XCTAssertEqual(
            plan.descriptors.first(where: { $0.kind == .weeklySummary })?.deepLinkURL.host,
            "progress"
        )
    }

    func testBackgroundPlannerMarksSyncAssistanceAsNetworkDependent() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let requests = NFBackgroundTaskPlanner.makeRequests(
            snapshot: NFBackgroundWorkSnapshot(
                privateSyncAssistanceRequested: true,
                privateSyncIsConfigured: true
            ),
            now: now
        )
        let request = try XCTUnwrap(requests.first)

        XCTAssertEqual(request.kind, .assistPrivateSync)
        XCTAssertTrue(request.requiresNetworkConnectivity)
        XCTAssertFalse(request.requiresExternalPower)
        XCTAssertEqual(request.earliestBeginDate, now.addingTimeInterval(15 * 60))
    }

    func testSpotlightPlannerRequiresExplicitConsentAndRedactsByDefault() throws {
        let chunk = makeSpotlightChunk()
        let priorID = "old-private-chunk"

        let disabled = NFSpotlightIndexPlanner.planReplacement(
            chunks: [chunk],
            previouslyIndexedChunkIDs: [priorID],
            consent: NFSpotlightPrivacyConsent(),
            language: .english
        )
        XCTAssertFalse(disabled.privacyOptInApplied)
        XCTAssertEqual(disabled.mutations, [
            .deleteIdentifiers([
                NFSpotlightIndexPlanner.searchableIdentifier(for: priorID),
                NFSpotlightIndexPlanner.searchableIdentifier(for: chunk.stableChunkID)
            ].sorted())
        ])

        let metadataOnly = NFSpotlightIndexPlanner.planReplacement(
            chunks: [chunk],
            previouslyIndexedChunkIDs: [],
            consent: NFSpotlightPrivacyConsent(
                explicitlyEnabledAt: Date(timeIntervalSince1970: 1_799_000_000)
            ),
            language: .english
        )
        let metadataRecord = try XCTUnwrap(firstSpotlightRecord(in: metadataOnly))
        XCTAssertEqual(metadataRecord.title, "NeuroForge study material")
        XCTAssertNil(metadataRecord.searchableText)
        XCTAssertFalse(metadataRecord.contentDescription?.contains("unpublished") == true)
        XCTAssertEqual(metadataRecord.keywords, ["NeuroForge"])
        XCTAssertEqual(
            metadataRecord.contentURL,
            NFSpotlightIndexPlanner.contentURL(
                documentID: chunk.documentID,
                stableChunkID: chunk.stableChunkID
            )
        )
    }

    func testSpotlightTextAndTitlesNeedSeparateExplicitChoices() throws {
        let chunk = makeSpotlightChunk()
        let plan = NFSpotlightIndexPlanner.planReplacement(
            chunks: [chunk],
            previouslyIndexedChunkIDs: [],
            consent: NFSpotlightPrivacyConsent(
                explicitlyEnabledAt: Date(timeIntervalSince1970: 1_799_000_000),
                includeDocumentTitles: true,
                includeSourceText: true
            ),
            language: .english
        )
        let record = try XCTUnwrap(firstSpotlightRecord(in: plan))

        XCTAssertEqual(record.title, chunk.documentTitle)
        XCTAssertEqual(record.searchableText, chunk.normalizedText)
        XCTAssertEqual(record.contentDescription, chunk.heading)
    }

    func testSyncCapabilityDefaultsToLocalOnlyUntilEntitlementAndEngineExist() {
        let missingEntitlement = NFSyncCapabilityEvaluator.evaluate(
            NFSyncBuildConfiguration(
                userEnabledPrivateSync: true,
                requestedContainerIdentifier: "iCloud.com.zacrotech.NeuroForge"
            )
        )
        XCTAssertEqual(missingEntitlement, .localOnly(reason: .missingCloudKitEntitlement))

        let configuredButNoEngine = NFSyncCapabilityEvaluator.evaluate(
            NFSyncBuildConfiguration(
                userEnabledPrivateSync: true,
                requestedContainerIdentifier: "iCloud.com.zacrotech.NeuroForge",
                entitledContainerIdentifiers: ["iCloud.com.zacrotech.NeuroForge"]
            )
        )
        XCTAssertEqual(configuredButNoEngine, .localOnly(reason: .syncEngineUnavailable))

        let configured = NFSyncCapabilityEvaluator.evaluate(
            NFSyncBuildConfiguration(
                userEnabledPrivateSync: true,
                requestedContainerIdentifier: "iCloud.com.zacrotech.NeuroForge",
                entitledContainerIdentifiers: ["iCloud.com.zacrotech.NeuroForge"],
                syncEngineInstalled: true
            )
        )
        XCTAssertEqual(
            configured,
            .privateCloudConfigured(containerIdentifier: "iCloud.com.zacrotech.NeuroForge")
        )
    }

    func testSyncStatusOnlySaysSyncedAfterSuccessfulEmptyQueue() {
        let capability = NFSyncCapability.privateCloudConfigured(
            containerIdentifier: "iCloud.com.zacrotech.NeuroForge"
        )
        let emptyQueue = NFSyncQueueMetrics(pendingRecordCount: 0, pendingAssetCount: 0)

        let initial = NFSyncStatusResolver.resolve(
            capability: capability,
            accountState: .available,
            enginePhase: .idle,
            queue: emptyQueue,
            lastSuccessfulSyncAt: nil
        )
        XCTAssertEqual(initial.displayState, .queued)
        XCTAssertEqual(initial.reason, .awaitingInitialSuccessfulSync)

        let pending = NFSyncStatusResolver.resolve(
            capability: capability,
            accountState: .available,
            enginePhase: .idle,
            queue: NFSyncQueueMetrics(pendingRecordCount: 2, pendingAssetCount: 1),
            lastSuccessfulSyncAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        XCTAssertEqual(pending.displayState, .queued)
        XCTAssertEqual(pending.reason, .pendingChanges(3))

        let successfulDate = Date(timeIntervalSince1970: 1_799_000_000)
        let synced = NFSyncStatusResolver.resolve(
            capability: capability,
            accountState: .available,
            enginePhase: .idle,
            queue: emptyQueue,
            lastSuccessfulSyncAt: successfulDate
        )
        XCTAssertEqual(synced.displayState, .synced)
        XCTAssertEqual(synced.reason, .fullyProcessed)
        XCTAssertEqual(synced.lastSuccessfulSyncAt, successfulDate)
        XCTAssertTrue(synced.localWritesRemainAvailable)
    }

    func testStructuredStatusRequiresFrameworkSuccessAfterLatestLocalWrite() {
        let successfulDate = Date(timeIntervalSince1970: 1_799_000_000)
        let initial = NFStructuredSyncStatusResolver.resolve(
            isConfiguredAtLaunch: true,
            localOnlyReason: .userDisabled,
            lastSuccessfulImportAt: nil,
            lastSuccessfulExportAt: nil,
            hasPendingLocalWrites: false,
            activeEventCount: 0,
            lastFailureCode: nil,
            configurationChangeRequiresRestart: false
        )
        XCTAssertEqual(initial.displayState, .queued)
        XCTAssertEqual(initial.reason, .awaitingInitialFrameworkEvent)

        let pending = NFStructuredSyncStatusResolver.resolve(
            isConfiguredAtLaunch: true,
            localOnlyReason: .userDisabled,
            lastSuccessfulImportAt: successfulDate,
            lastSuccessfulExportAt: successfulDate,
            hasPendingLocalWrites: true,
            activeEventCount: 0,
            lastFailureCode: nil,
            configurationChangeRequiresRestart: false
        )
        XCTAssertEqual(pending.displayState, .queued)
        XCTAssertEqual(pending.reason, .localWritesAwaitingExport)

        let processing = NFStructuredSyncStatusResolver.resolve(
            isConfiguredAtLaunch: true,
            localOnlyReason: .userDisabled,
            lastSuccessfulImportAt: successfulDate,
            lastSuccessfulExportAt: successfulDate,
            hasPendingLocalWrites: true,
            activeEventCount: 2,
            lastFailureCode: nil,
            configurationChangeRequiresRestart: false
        )
        XCTAssertEqual(processing.displayState, .syncing)
        XCTAssertEqual(processing.reason, .frameworkProcessing(2))

        let synced = NFStructuredSyncStatusResolver.resolve(
            isConfiguredAtLaunch: true,
            localOnlyReason: .userDisabled,
            lastSuccessfulImportAt: successfulDate,
            lastSuccessfulExportAt: successfulDate,
            hasPendingLocalWrites: false,
            activeEventCount: 0,
            lastFailureCode: nil,
            configurationChangeRequiresRestart: false
        )
        XCTAssertEqual(synced.displayState, .synced)
        XCTAssertEqual(synced.reason, .frameworkReportedSuccess)
        XCTAssertEqual(synced.lastSuccessfulSyncAt, successfulDate)
    }

    @MainActor
    func testStructuredEventObserverStateSeparatesImportAndExportSuccess() throws {
        let suiteName = "NFStructuredSyncStatus.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        NFPrivateSyncBootstrapPreference.set(true, defaults: defaults)
        let coordinator = NFSystemIntegrationCoordinator(
            defaults: defaults,
            launchPrivateCloudConfiguration: NFPrivateCloudRuntimeConfiguration(
                containerIdentifier: "iCloud.com.zacrotech.NeuroForge"
            )
        )
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let eventID = UUID()
        coordinator.recordStructuredSyncEvent(NFStructuredSyncEvent(
            id: eventID,
            kind: .exportChanges,
            startDate: start,
            endDate: nil,
            succeeded: false,
            redactedFailureCode: nil
        ))
        XCTAssertEqual(coordinator.structuredSyncStatus.displayState, .syncing)

        let completed = start.addingTimeInterval(2)
        coordinator.recordStructuredSyncEvent(NFStructuredSyncEvent(
            id: eventID,
            kind: .exportChanges,
            startDate: start,
            endDate: completed,
            succeeded: true,
            redactedFailureCode: nil
        ))
        XCTAssertEqual(coordinator.structuredSyncStatus.displayState, .synced)
        XCTAssertEqual(coordinator.structuredSyncStatus.lastSuccessfulExportAt, completed)
        XCTAssertNil(coordinator.structuredSyncStatus.lastSuccessfulImportAt)
    }

    @MainActor
    func testLegacyDeletionReceiptAndUnrelatedExportNeverVerifyOrDisableBootstrap() throws {
        let suiteName = "NFStructuredDeletionMigration.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        NFPrivateSyncBootstrapPreference.set(true, defaults: defaults)
        defaults.set(
            Date(timeIntervalSince1970: 1_799_999_900),
            forKey: "nf.sync.structured.deletion-requested.v1"
        )
        defaults.set(
            Date(timeIntervalSince1970: 1_799_999_950),
            forKey: "nf.sync.structured.deletion-verified.v1"
        )
        let coordinator = NFSystemIntegrationCoordinator(
            defaults: defaults,
            launchPrivateCloudConfiguration: NFPrivateCloudRuntimeConfiguration(
                containerIdentifier: "iCloud.com.zacrotech.NeuroForge"
            )
        )

        XCTAssertEqual(
            coordinator.structuredCloudDeletionStatus,
            .failed(redactedCode: "verification-unavailable")
        )
        XCTAssertNil(defaults.object(forKey: "nf.sync.structured.deletion-requested.v1"))
        XCTAssertNil(defaults.object(forKey: "nf.sync.structured.deletion-verified.v1"))

        let start = Date(timeIntervalSince1970: 1_800_000_000)
        coordinator.recordStructuredSyncEvent(NFStructuredSyncEvent(
            id: UUID(),
            kind: .exportChanges,
            startDate: start,
            endDate: start.addingTimeInterval(2),
            succeeded: true,
            redactedFailureCode: nil
        ))

        XCTAssertEqual(
            coordinator.structuredCloudDeletionStatus,
            .failed(redactedCode: "verification-unavailable")
        )
        XCTAssertTrue(NFPrivateSyncBootstrapPreference.isEnabled(defaults: defaults))
    }

    @MainActor
    func testCompleteCloudDeletionPersistsRestartBoundaryBeforeOriginalOrLocalMutation() async throws {
        let suiteName = "NFStructuredDeletionFailClosed.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        NFPrivateSyncBootstrapPreference.set(true, defaults: defaults)
        let schema = Schema(versionedSchema: NFSchemaV1.self)
        let container = try ModelContainer(
            for: schema,
            migrationPlan: NFSchemaMigrationPlan.self,
            configurations: try NFPersistentStoreLocation.configurations(inMemory: true)
        )
        var draft = OnboardingDraft()
        draft.iCloudEnabled = true
        let profile = UserProfileRecord(draft: draft)
        let document = SourceDocumentRecord(
            filename: "private-notes.txt",
            typeIdentifier: "public.plain-text",
            sizeBytes: 12,
            localPath: ""
        )
        document.syncPolicy = NFDocumentSyncPolicy.privateOriginal.rawValue
        container.mainContext.insert(profile)
        container.mainContext.insert(document)
        try container.mainContext.save()
        let store = AppStore(context: container.mainContext)
        let transport = StructuredDeletionTransportProbe()
        let policy = NFPrivateCloudCompleteDeletionPolicy(
            validatedContainerIdentifier: "iCloud.com.zacrotech.NeuroForge"
        )
        let requestedAt = Date(timeIntervalSince1970: 1_800_000_000)
        let request = NFPrivateCloudCompleteDeletionRequest(
            id: UUID(uuidString: "DBB249C3-1D1A-4F4D-A8C5-D5DB4303C73A")!,
            policy: policy,
            accountFingerprint: String(repeating: "a", count: 64),
            requestedAt: requestedAt
        )
        let launchStoreURL = FileManager.default.temporaryDirectory
            .appending(path: "structured-deletion-staging.store")
        var stagedRequestIDs: [UUID] = []
        let coordinator = NFSystemIntegrationCoordinator(
            defaults: defaults,
            notificationClient: StructuredImportNotificationClient(),
            spotlightClient: StructuredImportSpotlightClient(),
            preparedExportCleaner: { XCTFail("Prepared exports must remain untouched") },
            authoringCacheCleaner: { XCTFail("Authoring cache must remain untouched") },
            widgetSnapshotCleaner: { XCTFail("Widget state must remain untouched") },
            durableStoreCleaner: { _ in XCTFail("Durable store must remain untouched") },
            launchPrivateCloudConfiguration: NFPrivateCloudRuntimeConfiguration(
                containerIdentifier: "iCloud.com.zacrotech.NeuroForge"
            ),
            launchDurableStoreURL: launchStoreURL,
            privateDocumentTransport: transport,
            completeCloudDeletionRequester: { containerIdentifier in
                XCTAssertEqual(containerIdentifier, policy.containerIdentifier)
                NFPrivateSyncBootstrapPreference.lockForCloudDeletion(defaults: defaults)
                return request
            },
            structuredStorePurgeStager: { requestID, receivedURL in
                stagedRequestIDs.append(requestID)
                XCTAssertEqual(receivedURL, launchStoreURL)
                return NFPrivateCloudLocalPurgePreparation(
                    requiresRelaunch: true,
                    removedInactiveNamespaceCount: 0
                )
            }
        )

        do {
            _ = try await coordinator.deleteAllData(
                scope: .privateCloudAndThisDevice,
                store: store
            )
            XCTFail("The first launch must stop at the durable restart boundary")
        } catch let error as NFPrivateSyncDeletionError {
            guard case .restartRequiredForCompleteDeletion = error else {
                return XCTFail("Unexpected restart boundary: \(error)")
            }
        }

        XCTAssertEqual(store.profile?.id, profile.id)
        XCTAssertEqual(store.documents.map(\.id), [document.id])
        let transportMutationCalls = await transport.mutationCallCount()
        XCTAssertEqual(transportMutationCalls, 0)
        XCTAssertEqual(stagedRequestIDs, [request.id])
        XCTAssertFalse(NFPrivateSyncBootstrapPreference.isEnabled(defaults: defaults))
        XCTAssertTrue(NFPrivateSyncBootstrapPreference.isCloudDeletionLocked(defaults: defaults))
        XCTAssertEqual(
            coordinator.structuredCloudDeletionStatus,
            .awaitingRestart(requestedAt: requestedAt)
        )
        XCTAssertNil(coordinator.localDataDeletionError)
        XCTAssertEqual(store.notice?.title, "Restart to continue deletion")
    }

    @MainActor
    func testCompleteDeletionRequestIsDurableAccountBoundAndFreezesBootstrap() async throws {
        let suiteName = "NFCompleteDeletionRequest.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        NFPrivateSyncBootstrapPreference.setAfterExplicitUserChoice(true, defaults: defaults)
        let policy = NFPrivateCloudCompleteDeletionPolicy(
            validatedContainerIdentifier: "iCloud.com.zacrotech.NeuroForge"
        )
        let fingerprint = String(repeating: "a", count: 64)
        let client = PrivateZoneDeletionClientProbe(
            containerIdentifier: policy.containerIdentifier,
            accounts: [.available(fingerprint: fingerprint)]
        )
        let stateStore = NFUserDefaultsPrivateCloudDeletionStateStore(defaults: defaults)
        let requestedAt = Date(timeIntervalSince1970: 1_800_000_000)
        let requestID = UUID(uuidString: "7ED2AF03-B91C-46A4-908E-F3EF26B04F19")!

        let request = try await NFPrivateCloudCompleteDeletionWorkflow.request(
            policy: policy,
            defaults: defaults,
            stateStore: stateStore,
            client: client,
            requestedAt: requestedAt,
            requestID: requestID
        )

        XCTAssertEqual(request.id, requestID)
        XCTAssertEqual(request.containerIdentifier, policy.containerIdentifier)
        XCTAssertEqual(request.accountFingerprint, fingerprint)
        XCTAssertEqual(Set(request.zones.map(\.zone)), policy.requiredZones)
        XCTAssertEqual(try stateStore.loadRequest(), request)
        XCTAssertNil(try stateStore.loadReceipt())
        XCTAssertTrue(NFPrivateSyncBootstrapPreference.isCloudDeletionLocked(defaults: defaults))
        XCTAssertFalse(NFPrivateSyncBootstrapPreference.isEnabled(defaults: defaults))
        XCTAssertTrue(client.readCalls.isEmpty)
        XCTAssertTrue(client.deleteCalls.isEmpty)
    }

    @MainActor
    func testStartupDeletionNeverTouchesCloudWhenMatchingLocalPurgeWasNotStaged() async throws {
        let suiteName = "NFCompleteDeletionMissingStage.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let policy = NFPrivateCloudCompleteDeletionPolicy(
            validatedContainerIdentifier: "iCloud.com.zacrotech.NeuroForge"
        )
        let fingerprint = String(repeating: "a", count: 64)
        let client = PrivateZoneDeletionClientProbe(
            containerIdentifier: policy.containerIdentifier,
            accounts: [.available(fingerprint: fingerprint)]
        )
        let stateStore = NFUserDefaultsPrivateCloudDeletionStateStore(defaults: defaults)
        _ = try await NFPrivateCloudCompleteDeletionWorkflow.request(
            policy: policy,
            defaults: defaults,
            stateStore: stateStore,
            client: client
        )
        let accountCallsBeforeStartup = client.accountCallCount

        do {
            _ = try await NFPrivateCloudCompleteDeletionWorkflow
                .executePendingRequestBeforeModelContainer(
                    policy: policy,
                    defaults: defaults,
                    stateStore: stateStore,
                    client: client,
                    localPurgeBindingVerified: false
                )
            XCTFail("A request without its matching staged purge must fail closed")
        } catch let error as NFPrivateCloudCompleteDeletionError {
            XCTAssertEqual(error, .localPurgeNotStaged)
        }

        XCTAssertEqual(client.accountCallCount, accountCallsBeforeStartup)
        XCTAssertTrue(client.readCalls.isEmpty)
        XCTAssertTrue(client.deleteCalls.isEmpty)
        XCTAssertNotNil(try stateStore.loadRequest())
        XCTAssertTrue(NFPrivateSyncBootstrapPreference.isCloudDeletionLocked(defaults: defaults))
    }

    @MainActor
    func testStartupDeletionVerifiesBothExactAllowlistedZonesAndPersistsReceipt() async throws {
        let suiteName = "NFCompleteDeletionSuccess.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let policy = NFPrivateCloudCompleteDeletionPolicy(
            validatedContainerIdentifier: "iCloud.com.zacrotech.NeuroForge"
        )
        let fingerprint = String(repeating: "b", count: 64)
        let allZones = policy.requiredZones
        let client = PrivateZoneDeletionClientProbe(
            containerIdentifier: policy.containerIdentifier,
            accounts: Array(repeating: .available(fingerprint: fingerprint), count: 4),
            reads: [
                Dictionary(uniqueKeysWithValues: allZones.map { ($0, .present) }),
                Dictionary(uniqueKeysWithValues: allZones.map { ($0, .absent) })
            ],
            deletions: [
                Dictionary(uniqueKeysWithValues: allZones.map { ($0, .accepted) })
            ]
        )
        let stateStore = NFUserDefaultsPrivateCloudDeletionStateStore(defaults: defaults)
        _ = try await NFPrivateCloudCompleteDeletionWorkflow.request(
            policy: policy,
            defaults: defaults,
            stateStore: stateStore,
            client: client,
            requestedAt: Date(timeIntervalSince1970: 1_800_000_000)
        )

        let outcome = try await NFPrivateCloudCompleteDeletionWorkflow
            .executePendingRequestBeforeModelContainer(
                policy: policy,
                defaults: defaults,
                stateStore: stateStore,
                client: client,
                now: Date(timeIntervalSince1970: 1_800_000_100)
            )
        guard case let .verified(receipt) = outcome else {
            return XCTFail("Expected exact post-delete verification, got \(outcome)")
        }

        XCTAssertEqual(client.readCalls, [allZones, allZones])
        XCTAssertEqual(client.deleteCalls, [allZones])
        XCTAssertEqual(Set(receipt.zones.map(\.zone)), allZones)
        XCTAssertTrue(receipt.zones.allSatisfy(\.isVerifiedAbsent))
        XCTAssertEqual(try stateStore.loadReceipt(), receipt)
        XCTAssertTrue(NFPrivateSyncBootstrapPreference.isCloudDeletionLocked(defaults: defaults))

        try NFPrivateCloudCompleteDeletionWorkflow.finishAfterVerifiedLocalCleanup(
            receiptID: receipt.id,
            defaults: defaults,
            stateStore: stateStore
        )
        XCTAssertNil(try stateStore.loadRequest())
        XCTAssertNil(try stateStore.loadReceipt())
        XCTAssertFalse(NFPrivateSyncBootstrapPreference.isCloudDeletionLocked(defaults: defaults))
        XCTAssertFalse(NFPrivateSyncBootstrapPreference.isEnabled(defaults: defaults))
    }

    @MainActor
    func testVerifiedRemoteDeletionAutomaticallyCleansEveryLocalSurfaceAndFinalizes() async throws {
        let suiteName = "NFCompleteDeletionAutomaticLocalCleanup.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let policy = NFPrivateCloudCompleteDeletionPolicy(
            validatedContainerIdentifier: "iCloud.com.zacrotech.NeuroForge"
        )
        var request = NFPrivateCloudCompleteDeletionRequest(
            id: UUID(),
            policy: policy,
            accountFingerprint: String(repeating: "b", count: 64),
            requestedAt: Date(timeIntervalSince1970: 1_800_000_000)
        )
        for zone in policy.requiredZones {
            request.update(zone) {
                $0.readback = .absent(checkedAt: Date(timeIntervalSince1970: 1_800_000_100))
            }
        }
        let receipt = NFPrivateCloudCompleteDeletionReceipt(
            request: request,
            verifiedAt: Date(timeIntervalSince1970: 1_800_000_100)
        )
        let deletionStore = NFUserDefaultsPrivateCloudDeletionStateStore(defaults: defaults)
        try deletionStore.saveRequest(request)
        try deletionStore.saveReceipt(receipt)
        NFPrivateSyncBootstrapPreference.lockForCloudDeletion(defaults: defaults)
        let cleanupStore = NFUserDefaultsPrivateCloudPreContainerCleanupStateStore(
            defaults: defaults
        )
        let cleanupClient = PrivateCloudPreContainerCleanupClientProbe()

        let outcome = try await NFPrivateCloudCompleteDeletionWorkflow
            .finishVerifiedRequestBeforeModelContainer(
                receipt: receipt,
                defaults: defaults,
                stateStore: deletionStore,
                cleanupStateStore: cleanupStore,
                cleanupClient: cleanupClient,
                now: Date(timeIntervalSince1970: 1_800_000_200)
            )
        guard case let .completed(completion) = outcome else {
            return XCTFail("Expected automatic two-launch completion, got \(outcome)")
        }

        XCTAssertEqual(
            cleanupClient.calls,
            NFPrivateCloudPreContainerCleanupComponent.cleanupOrder
        )
        XCTAssertEqual(cleanupClient.consumedRequestIDs, [request.id])
        XCTAssertEqual(completion.requestID, request.id)
        XCTAssertEqual(completion.remoteReceiptID, receipt.id)
        XCTAssertNil(try deletionStore.loadRequest())
        XCTAssertNil(try deletionStore.loadReceipt())
        XCTAssertFalse(NFPrivateSyncBootstrapPreference.isCloudDeletionLocked(defaults: defaults))
        XCTAssertEqual(try cleanupStore.loadCompletion(), completion)
        XCTAssertNil(try cleanupStore.loadProgress())

        XCTAssertTrue(
            NFPrivateCloudCompleteDeletionWorkflow.acknowledgeCompletion(
                id: completion.id,
                defaults: defaults
            )
        )
        XCTAssertNil(try cleanupStore.loadCompletion())
    }

    @MainActor
    func testFailedAutomaticLocalCleanupBlocksAndRetryReverifiesEveryComponent() async throws {
        let suiteName = "NFCompleteDeletionAutomaticLocalRetry.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let policy = NFPrivateCloudCompleteDeletionPolicy(
            validatedContainerIdentifier: "iCloud.com.zacrotech.NeuroForge"
        )
        var request = NFPrivateCloudCompleteDeletionRequest(
            id: UUID(),
            policy: policy,
            accountFingerprint: String(repeating: "c", count: 64),
            requestedAt: Date(timeIntervalSince1970: 1_800_000_000)
        )
        for zone in policy.requiredZones {
            request.update(zone) {
                $0.readback = .absent(checkedAt: Date(timeIntervalSince1970: 1_800_000_100))
            }
        }
        let receipt = NFPrivateCloudCompleteDeletionReceipt(
            request: request,
            verifiedAt: Date(timeIntervalSince1970: 1_800_000_100)
        )
        let deletionStore = NFUserDefaultsPrivateCloudDeletionStateStore(defaults: defaults)
        try deletionStore.saveRequest(request)
        try deletionStore.saveReceipt(receipt)
        NFPrivateSyncBootstrapPreference.lockForCloudDeletion(defaults: defaults)
        let cleanupStore = NFUserDefaultsPrivateCloudPreContainerCleanupStateStore(
            defaults: defaults
        )
        let cleanupClient = PrivateCloudPreContainerCleanupClientProbe(
            failingComponent: .spotlightIndex
        )

        let first = try await NFPrivateCloudCompleteDeletionWorkflow
            .finishVerifiedRequestBeforeModelContainer(
                receipt: receipt,
                defaults: defaults,
                stateStore: deletionStore,
                cleanupStateStore: cleanupStore,
                cleanupClient: cleanupClient
            )
        XCTAssertEqual(
            first,
            .failed(redactedCode: "local-cleanup-spotlightIndex", retryable: true)
        )
        XCTAssertEqual(
            cleanupClient.calls,
            [.backgroundTasks, .notifications, .spotlightIndex]
        )
        XCTAssertNotNil(try deletionStore.loadRequest())
        XCTAssertNotNil(try deletionStore.loadReceipt())
        XCTAssertTrue(NFPrivateSyncBootstrapPreference.isCloudDeletionLocked(defaults: defaults))

        cleanupClient.failingComponent = nil
        cleanupClient.calls.removeAll()
        let second = try await NFPrivateCloudCompleteDeletionWorkflow
            .finishVerifiedRequestBeforeModelContainer(
                receipt: receipt,
                defaults: defaults,
                stateStore: deletionStore,
                cleanupStateStore: cleanupStore,
                cleanupClient: cleanupClient
            )
        guard case .completed = second else {
            return XCTFail("The retry should finish the same durable request")
        }
        XCTAssertEqual(
            cleanupClient.calls,
            NFPrivateCloudPreContainerCleanupComponent.cleanupOrder
        )
        XCTAssertNil(try deletionStore.loadRequest())
        XCTAssertFalse(NFPrivateSyncBootstrapPreference.isCloudDeletionLocked(defaults: defaults))
    }

    @MainActor
    func testPreContainerDefaultsCleanupUsesExactAllowlist() async throws {
        let suiteName = "NFCompleteDeletionAllowlistedDefaults.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let keysToRemove = [
            "nf.system.notifications.preferences.v1",
            "nf.system.spotlight.consent.v1",
            "nf.system.spotlight.indexed-chunks.v1",
            "nf.sync.structured.last-import.v1",
            "nf.sync.structured.last-export.v1",
            "nf.sync.structured.pending-local-write.v1",
            "nf.onboarding.step",
            "nf.onboarding.draft",
            NFAppLocalization.preferredLanguageDefaultsKey
        ]
        for key in keysToRemove { defaults.set("sensitive", forKey: key) }
        for key in NeuroForgeShortcutHandoff.allDefaultsKeys {
            defaults.set("shortcut", forKey: key)
        }
        defaults.set("preserve", forKey: "unrelated.preference")
        let cleanupClient = NFApplicationPrivateCloudPreContainerCleanupClient(
            defaults: defaults
        )

        try await cleanupClient.removeAndVerify(
            .allowlistedDefaults,
            requestID: UUID()
        )

        XCTAssertTrue(keysToRemove.allSatisfy { defaults.object(forKey: $0) == nil })
        XCTAssertTrue(
            NeuroForgeShortcutHandoff.allDefaultsKeys.allSatisfy {
                defaults.object(forKey: $0) == nil
            }
        )
        XCTAssertEqual(defaults.string(forKey: "unrelated.preference"), "preserve")
    }

    @MainActor
    func testPreContainerCleanupRemovesOnlyAllowlistedStoreRecoveryPackages() async throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory.appending(
            path: "NFRecoveryCleanupFixture-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: root) }
        let stablePackage = root.appending(
            path: NFStoreRecoveryService.packageFolderName,
            directoryHint: .isDirectory
        )
        let legacyOwnedPackage = root.appending(
            path: "\(NFStoreRecoveryService.packageFolderName)-prerelease",
            directoryHint: .isDirectory
        )
        let unrelated = root.appending(
            path: "Other-App-Store-Recovery",
            directoryHint: .isDirectory
        )
        for folder in [stablePackage, legacyOwnedPackage, unrelated] {
            try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
            try Data("private sqlite content".utf8).write(
                to: folder.appending(path: "default.store")
            )
        }
        let cleanupClient = NFApplicationPrivateCloudPreContainerCleanupClient(
            fileManager: fileManager,
            temporaryDirectory: root
        )

        try await cleanupClient.removeAndVerify(
            .storeRecoveryPackages,
            requestID: UUID()
        )

        XCTAssertFalse(fileManager.fileExists(atPath: stablePackage.path))
        XCTAssertFalse(fileManager.fileExists(atPath: legacyOwnedPackage.path))
        XCTAssertTrue(fileManager.fileExists(atPath: unrelated.path))
    }

    @MainActor
    func testStartupDeletionAbortsBeforeAnyZoneMutationWhenPreflightReadPartiallyFails() async throws {
        let suiteName = "NFCompleteDeletionPreflight.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let policy = NFPrivateCloudCompleteDeletionPolicy(
            validatedContainerIdentifier: "iCloud.com.zacrotech.NeuroForge"
        )
        let fingerprint = String(repeating: "c", count: 64)
        let client = PrivateZoneDeletionClientProbe(
            containerIdentifier: policy.containerIdentifier,
            accounts: Array(repeating: .available(fingerprint: fingerprint), count: 2),
            reads: [[
                .structuredStore: .present,
                .privateDocumentAssets: .failed(
                    redactedCode: "network-unavailable",
                    retryable: true
                )
            ]],
            deletions: [[
                .structuredStore: .accepted,
                .privateDocumentAssets: .accepted
            ]]
        )
        let stateStore = NFUserDefaultsPrivateCloudDeletionStateStore(defaults: defaults)
        _ = try await NFPrivateCloudCompleteDeletionWorkflow.request(
            policy: policy,
            defaults: defaults,
            stateStore: stateStore,
            client: client
        )

        let outcome = try await NFPrivateCloudCompleteDeletionWorkflow
            .executePendingRequestBeforeModelContainer(
                policy: policy,
                defaults: defaults,
                stateStore: stateStore,
                client: client,
                now: Date(timeIntervalSince1970: 1_800_000_200)
            )
        guard case let .unfinished(request) = outcome else {
            return XCTFail("A partial preflight must remain unfinished")
        }

        XCTAssertEqual(request.lastFailure?.redactedCode, "network-unavailable")
        XCTAssertEqual(client.readCalls, [policy.requiredZones])
        XCTAssertTrue(client.deleteCalls.isEmpty)
        XCTAssertNil(try stateStore.loadReceipt())
        XCTAssertTrue(NFPrivateSyncBootstrapPreference.isCloudDeletionLocked(defaults: defaults))
    }

    @MainActor
    func testPartialZoneDeletePersistsPerZoneEvidenceAndNeverWritesReceipt() async throws {
        let suiteName = "NFCompleteDeletionPartial.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let policy = NFPrivateCloudCompleteDeletionPolicy(
            validatedContainerIdentifier: "iCloud.com.zacrotech.NeuroForge"
        )
        let fingerprint = String(repeating: "d", count: 64)
        let present: [NFPrivateCloudOwnedZone: NFPrivateCloudZoneReadResult] = [
            .structuredStore: .present,
            .privateDocumentAssets: .present
        ]
        let client = PrivateZoneDeletionClientProbe(
            containerIdentifier: policy.containerIdentifier,
            accounts: Array(repeating: .available(fingerprint: fingerprint), count: 3),
            reads: [
                present,
                [
                    .structuredStore: .absent,
                    .privateDocumentAssets: .present
                ]
            ],
            deletions: [[
                .structuredStore: .accepted,
                .privateDocumentAssets: .failed(
                    redactedCode: "partial-failure",
                    retryable: true
                )
            ]]
        )
        let stateStore = NFUserDefaultsPrivateCloudDeletionStateStore(defaults: defaults)
        _ = try await NFPrivateCloudCompleteDeletionWorkflow.request(
            policy: policy,
            defaults: defaults,
            stateStore: stateStore,
            client: client
        )

        let outcome = try await NFPrivateCloudCompleteDeletionWorkflow
            .executePendingRequestBeforeModelContainer(
                policy: policy,
                defaults: defaults,
                stateStore: stateStore,
                client: client,
                now: Date(timeIntervalSince1970: 1_800_000_300)
            )
        guard case let .unfinished(request) = outcome else {
            return XCTFail("Partial deletion cannot be verified")
        }

        XCTAssertTrue(request.state(for: .structuredStore)?.isVerifiedAbsent == true)
        XCTAssertTrue(request.state(for: .privateDocumentAssets)?.isVerifiedAbsent == false)
        if case let .failed(code, retryable, _) = request
            .state(for: .privateDocumentAssets)?.deletion {
            XCTAssertEqual(code, "partial-failure")
            XCTAssertTrue(retryable)
        } else {
            XCTFail("Expected the per-zone partial deletion result to persist")
        }
        XCTAssertNil(try stateStore.loadReceipt())
        XCTAssertEqual(client.deleteCalls, [policy.requiredZones])
    }

    @MainActor
    func testAccountSwitchAfterReadbackPreventsVerifiedReceipt() async throws {
        let suiteName = "NFCompleteDeletionAccountRace.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let policy = NFPrivateCloudCompleteDeletionPolicy(
            validatedContainerIdentifier: "iCloud.com.zacrotech.NeuroForge"
        )
        let originalFingerprint = String(repeating: "e", count: 64)
        let changedFingerprint = String(repeating: "f", count: 64)
        let allZones = policy.requiredZones
        let client = PrivateZoneDeletionClientProbe(
            containerIdentifier: policy.containerIdentifier,
            accounts: [
                .available(fingerprint: originalFingerprint),
                .available(fingerprint: originalFingerprint),
                .available(fingerprint: originalFingerprint),
                .available(fingerprint: changedFingerprint)
            ],
            reads: [
                Dictionary(uniqueKeysWithValues: allZones.map { ($0, .present) }),
                Dictionary(uniqueKeysWithValues: allZones.map { ($0, .absent) })
            ],
            deletions: [
                Dictionary(uniqueKeysWithValues: allZones.map { ($0, .accepted) })
            ]
        )
        let stateStore = NFUserDefaultsPrivateCloudDeletionStateStore(defaults: defaults)
        _ = try await NFPrivateCloudCompleteDeletionWorkflow.request(
            policy: policy,
            defaults: defaults,
            stateStore: stateStore,
            client: client
        )

        let outcome = try await NFPrivateCloudCompleteDeletionWorkflow
            .executePendingRequestBeforeModelContainer(
                policy: policy,
                defaults: defaults,
                stateStore: stateStore,
                client: client,
                now: Date(timeIntervalSince1970: 1_800_000_400)
            )
        guard case let .unfinished(request) = outcome else {
            return XCTFail("An account race must never write a verified receipt")
        }

        XCTAssertTrue(request.isRemotelyVerified)
        XCTAssertEqual(request.lastFailure?.redactedCode, "account-mismatch")
        XCTAssertNil(try stateStore.loadReceipt())
        XCTAssertTrue(NFPrivateSyncBootstrapPreference.isCloudDeletionLocked(defaults: defaults))
    }

    @MainActor
    func testFailedFinalStateClearCanRelockWithoutAnOrphanedDeletionLock() async throws {
        let suiteName = "NFCompleteDeletionFinalization.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let policy = NFPrivateCloudCompleteDeletionPolicy(
            validatedContainerIdentifier: "iCloud.com.zacrotech.NeuroForge"
        )
        var request = NFPrivateCloudCompleteDeletionRequest(
            id: UUID(),
            policy: policy,
            accountFingerprint: String(repeating: "a", count: 64),
            requestedAt: Date(timeIntervalSince1970: 1_800_000_000)
        )
        for zone in policy.requiredZones {
            request.update(zone) {
                $0.deletion = .zoneNotFound(at: Date(timeIntervalSince1970: 1_800_000_500))
                $0.readback = .absent(checkedAt: Date(timeIntervalSince1970: 1_800_000_500))
            }
        }
        let receipt = NFPrivateCloudCompleteDeletionReceipt(
            request: request,
            verifiedAt: Date(timeIntervalSince1970: 1_800_000_500)
        )
        let baseStore = NFUserDefaultsPrivateCloudDeletionStateStore(defaults: defaults)
        try baseStore.saveRequest(request)
        try baseStore.saveReceipt(receipt)
        NFPrivateSyncBootstrapPreference.lockForCloudDeletion(defaults: defaults)
        let failingStore = FailingClearPrivateDeletionStateStore(base: baseStore)

        XCTAssertThrowsError(
            try NFPrivateCloudCompleteDeletionWorkflow.finishAfterVerifiedLocalCleanup(
                receiptID: receipt.id,
                defaults: defaults,
                stateStore: failingStore
            )
        )
        XCTAssertFalse(NFPrivateSyncBootstrapPreference.isCloudDeletionLocked(defaults: defaults))
        XCTAssertNotNil(try baseStore.loadRequest())

        let client = PrivateZoneDeletionClientProbe(
            containerIdentifier: policy.containerIdentifier,
            accounts: []
        )
        let resumed = try await NFPrivateCloudCompleteDeletionWorkflow
            .executePendingRequestBeforeModelContainer(
                policy: policy,
                defaults: defaults,
                stateStore: baseStore,
                client: client
            )
        guard case .verified = resumed else {
            return XCTFail("The persisted receipt should be recoverable")
        }
        XCTAssertTrue(NFPrivateSyncBootstrapPreference.isCloudDeletionLocked(defaults: defaults))
    }

    @MainActor
    func testStartupRecoversOrphanDeletionLockWithoutEnablingSync() async throws {
        let suiteName = "NFCompleteDeletionOrphanLock.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        NFPrivateSyncBootstrapPreference.setAfterExplicitUserChoice(true, defaults: defaults)
        NFPrivateSyncBootstrapPreference.lockForCloudDeletion(defaults: defaults)

        let outcome = await NFPrivateCloudCompleteDeletionWorkflow
            .executePendingRequestBeforeModelContainer(defaults: defaults)

        XCTAssertEqual(outcome, .noRequest)
        XCTAssertFalse(NFPrivateSyncBootstrapPreference.isCloudDeletionLocked(defaults: defaults))
        XCTAssertFalse(NFPrivateSyncBootstrapPreference.isEnabled(defaults: defaults))
    }

    @MainActor
    func testImportedProfileReconcilesPrivateSyncBootstrapPreference() async throws {
        let suiteName = "NFStructuredImportedPreference.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let schema = Schema(versionedSchema: NFSchemaV1.self)
        let container = try ModelContainer(
            for: schema,
            migrationPlan: NFSchemaMigrationPlan.self,
            configurations: try NFPersistentStoreLocation.configurations(inMemory: true)
        )
        let profile = UserProfileRecord(draft: OnboardingDraft())
        container.mainContext.insert(profile)
        try container.mainContext.save()
        let store = AppStore(context: container.mainContext)
        let coordinator = NFSystemIntegrationCoordinator(
            defaults: defaults,
            notificationClient: StructuredImportNotificationClient(),
            spotlightClient: StructuredImportSpotlightClient(),
            launchPrivateCloudConfiguration: NFPrivateCloudRuntimeConfiguration(
                containerIdentifier: "iCloud.com.zacrotech.NeuroForge"
            )
        )
        await coordinator.activate(store: store)

        profile.iCloudEnabled = true
        try container.mainContext.save()
        let firstStart = Date(timeIntervalSince1970: 1_800_000_000)
        coordinator.recordStructuredSyncEvent(NFStructuredSyncEvent(
            id: UUID(),
            kind: .importChanges,
            startDate: firstStart,
            endDate: firstStart.addingTimeInterval(1),
            succeeded: true,
            redactedFailureCode: nil
        ))
        XCTAssertTrue(store.profileSnapshot.iCloudEnabled)
        XCTAssertTrue(NFPrivateSyncBootstrapPreference.isEnabled(defaults: defaults))

        profile.iCloudEnabled = false
        try container.mainContext.save()
        let secondStart = firstStart.addingTimeInterval(10)
        coordinator.recordStructuredSyncEvent(NFStructuredSyncEvent(
            id: UUID(),
            kind: .importChanges,
            startDate: secondStart,
            endDate: secondStart.addingTimeInterval(1),
            succeeded: true,
            redactedFailureCode: nil
        ))
        XCTAssertFalse(store.profileSnapshot.iCloudEnabled)
        XCTAssertFalse(NFPrivateSyncBootstrapPreference.isEnabled(defaults: defaults))
    }

    @MainActor
    func testAccountChangeLockPreventsImportedProfileFromReenablingSync() async throws {
        let suiteName = "NFStructuredImportedPreferenceLock.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        NFPrivateSyncBootstrapPreference.lockAfterAccountChange(defaults: defaults)
        let schema = Schema(versionedSchema: NFSchemaV1.self)
        let container = try ModelContainer(
            for: schema,
            migrationPlan: NFSchemaMigrationPlan.self,
            configurations: try NFPersistentStoreLocation.configurations(inMemory: true)
        )
        let profile = UserProfileRecord(draft: OnboardingDraft())
        container.mainContext.insert(profile)
        try container.mainContext.save()
        let store = AppStore(context: container.mainContext)
        let coordinator = NFSystemIntegrationCoordinator(
            defaults: defaults,
            notificationClient: StructuredImportNotificationClient(),
            spotlightClient: StructuredImportSpotlightClient(),
            launchPrivateCloudConfiguration: NFPrivateCloudRuntimeConfiguration(
                containerIdentifier: "iCloud.com.zacrotech.NeuroForge"
            )
        )
        await coordinator.activate(store: store)

        profile.iCloudEnabled = true
        try container.mainContext.save()
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        coordinator.recordStructuredSyncEvent(NFStructuredSyncEvent(
            id: UUID(),
            kind: .importChanges,
            startDate: start,
            endDate: start.addingTimeInterval(1),
            succeeded: true,
            redactedFailureCode: nil
        ))

        XCTAssertTrue(NFPrivateSyncBootstrapPreference.isAccountChangeLocked(defaults: defaults))
        XCTAssertFalse(NFPrivateSyncBootstrapPreference.isEnabled(defaults: defaults))
        XCTAssertFalse(store.profileSnapshot.iCloudEnabled)

        store.reload()
        XCTAssertFalse(store.profileSnapshot.iCloudEnabled)
    }

    @MainActor
    func testConcurrentActivationIsSingleFlightAndCanRunAgainAfterCompletion() async throws {
        let schema = Schema(versionedSchema: NFSchemaV1.self)
        let container = try ModelContainer(
            for: schema,
            migrationPlan: NFSchemaMigrationPlan.self,
            configurations: try NFPersistentStoreLocation.configurations(inMemory: true)
        )
        let store = AppStore(context: container.mainContext)
        let notificationClient = ActivationNotificationProbe()
        let spotlightClient = ActivationSpotlightProbe()
        let coordinator = NFSystemIntegrationCoordinator(
            notificationClient: notificationClient,
            spotlightClient: spotlightClient
        )

        async let rootActivation: Void = coordinator.activate(store: store)
        async let sceneActivation: Void = coordinator.activate(store: store)
        async let settingsActivation: Void = coordinator.activate(store: store)
        _ = await (rootActivation, sceneActivation, settingsActivation)

        let coalescedAuthorizationRequests = await notificationClient
            .authorizationRequestCount()
        let coalescedSpotlightApplications = await spotlightClient.applyCount()
        XCTAssertEqual(coalescedAuthorizationRequests, 1)
        XCTAssertEqual(coalescedSpotlightApplications, 1)

        await coordinator.activate(store: store)
        let sequentialAuthorizationRequests = await notificationClient
            .authorizationRequestCount()
        let sequentialSpotlightApplications = await spotlightClient.applyCount()
        XCTAssertEqual(sequentialAuthorizationRequests, 2)
        XCTAssertEqual(sequentialSpotlightApplications, 2)
    }

    @MainActor
    func testActivationRefreshesNotificationCategoriesAfterAppLanguageChanges() async throws {
        let suiteName = "NFNotificationLanguageLifecycle.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let originalLanguage = NFAppLocalization.preferredLanguageCode
        defer { NFAppLocalization.setPreferredLanguageCode(originalLanguage) }

        let schema = Schema(versionedSchema: NFSchemaV1.self)
        let container = try ModelContainer(
            for: schema,
            migrationPlan: NFSchemaMigrationPlan.self,
            configurations: try NFPersistentStoreLocation.configurations(inMemory: true)
        )
        var draft = OnboardingDraft()
        draft.preferredLanguageCode = "en"
        let profile = UserProfileRecord(draft: draft)
        container.mainContext.insert(profile)
        try container.mainContext.save()
        let store = AppStore(context: container.mainContext)
        let notificationClient = ActivationNotificationProbe(status: .authorized)
        let coordinator = NFSystemIntegrationCoordinator(
            defaults: defaults,
            notificationClient: notificationClient,
            spotlightClient: ActivationSpotlightProbe()
        )
        coordinator.setDailyReminderEnabled(true)

        await coordinator.activate(store: store)
        profile.preferredLanguageCode = "ja"
        profile.modifiedAt = Date()
        try container.mainContext.save()
        store.reload()
        await coordinator.activate(store: store)

        let categoryPresentations = await notificationClient.categoryPresentations()
        XCTAssertEqual(categoryPresentations.map(\.language), [.english, .japanese])
        XCTAssertEqual(categoryPresentations.map(\.openActionTitle), [
            "Open NeuroForge",
            "NeuroForgeを開く"
        ])
        let scheduledBatches = await notificationClient.scheduledBatches()
        XCTAssertEqual(scheduledBatches.count, 2)
        XCTAssertEqual(scheduledBatches.first?.first?.title, "Your practice is ready")
        XCTAssertEqual(scheduledBatches.last?.first?.title, "今日の練習ができました")
    }

    @MainActor
    func testLanguageChangeDuringNotificationApplicationReplaysNewestLanguage() async throws {
        let suiteName = "NFNotificationLanguageConcurrent.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let originalLanguage = NFAppLocalization.preferredLanguageCode
        defer { NFAppLocalization.setPreferredLanguageCode(originalLanguage) }

        let schema = Schema(versionedSchema: NFSchemaV1.self)
        let container = try ModelContainer(
            for: schema,
            migrationPlan: NFSchemaMigrationPlan.self,
            configurations: try NFPersistentStoreLocation.configurations(inMemory: true)
        )
        var draft = OnboardingDraft()
        draft.preferredLanguageCode = "en"
        let profile = UserProfileRecord(draft: draft)
        container.mainContext.insert(profile)
        try container.mainContext.save()
        let store = AppStore(context: container.mainContext)
        let notificationClient = ActivationNotificationProbe(
            status: .authorized,
            blocksFirstScheduleReplacement: true
        )
        let coordinator = NFSystemIntegrationCoordinator(
            defaults: defaults,
            notificationClient: notificationClient,
            spotlightClient: ActivationSpotlightProbe()
        )
        coordinator.setDailyReminderEnabled(true)

        let activationTask = Task { await coordinator.activate(store: store) }
        await notificationClient.waitUntilFirstScheduleReplacementBegins()

        profile.preferredLanguageCode = "ja"
        profile.modifiedAt = Date()
        try container.mainContext.save()
        store.reload()
        await coordinator.refreshNotificationLanguage(store: store)

        await notificationClient.releaseFirstScheduleReplacement()
        await activationTask.value

        let categoryPresentations = await notificationClient.categoryPresentations()
        XCTAssertEqual(categoryPresentations.map(\.language), [.english, .japanese])
        let scheduledBatches = await notificationClient.scheduledBatches()
        XCTAssertEqual(scheduledBatches.count, 2)
        XCTAssertEqual(scheduledBatches.first?.first?.title, "Your practice is ready")
        XCTAssertEqual(scheduledBatches.last?.first?.title, "今日の練習ができました")
    }

    @MainActor
    func testSuccessfulStructuredImportRefreshesMaterializedAppStoreCollections() async throws {
        let schema = Schema(versionedSchema: NFSchemaV1.self)
        let container = try ModelContainer(
            for: schema,
            migrationPlan: NFSchemaMigrationPlan.self,
            configurations: try NFPersistentStoreLocation.configurations(inMemory: true)
        )
        let store = AppStore(context: container.mainContext)
        let coordinator = NFSystemIntegrationCoordinator(
            notificationClient: StructuredImportNotificationClient(),
            spotlightClient: StructuredImportSpotlightClient(),
            launchPrivateCloudConfiguration: NFPrivateCloudRuntimeConfiguration(
                containerIdentifier: "iCloud.com.zacrotech.NeuroForge"
            )
        )
        await coordinator.activate(store: store)

        let imported = AttemptRecord(
            sessionID: UUID(),
            lab: .mentalMath,
            itemID: "remote-attempt",
            prompt: "1 + 1",
            response: "2",
            correctAnswer: "2",
            isCorrect: true,
            confidence: .certain
        )
        container.mainContext.insert(imported)
        try container.mainContext.save()
        XCTAssertTrue(store.attempts.isEmpty)

        let started = Date(timeIntervalSince1970: 1_800_000_000)
        coordinator.recordStructuredSyncEvent(NFStructuredSyncEvent(
            id: UUID(),
            kind: .importChanges,
            startDate: started,
            endDate: started.addingTimeInterval(1),
            succeeded: true,
            redactedFailureCode: nil
        ))

        XCTAssertEqual(store.attempts.map(\.id), [imported.id])
    }

    func testAppendOnlyMergeIsIdempotentAndQuarantinesFingerprintConflict() throws {
        let firstID = try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000001"))
        let secondID = try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000002"))
        let first = NFAppendOnlySyncRecord(id: firstID, contentFingerprint: "aaa", payload: "local")
        let duplicate = first
        let second = NFAppendOnlySyncRecord(id: secondID, contentFingerprint: "bbb", payload: "remote")
        let conflict = NFAppendOnlySyncRecord(id: firstID, contentFingerprint: "zzz", payload: "tampered")

        let merged = NFSyncMergeEngine.mergeAppendOnly(
            local: [first, duplicate],
            remote: [second, conflict]
        )

        XCTAssertEqual(merged.records, [first, second])
        XCTAssertEqual(merged.conflicts, [
            NFAppendOnlyMergeConflict(
                id: firstID,
                retainedFingerprint: "aaa",
                rejectedFingerprint: "zzz"
            )
        ])
    }

    func testMergeRulesConvergeForExposurePlansSettingsAndSessions() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let eventOne = try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000010"))
        let eventTwo = try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000011"))
        let lhsExposure = NFItemExposureSyncState(
            itemIdentity: "item.1",
            firstSeenAt: now,
            lastSeenAt: now,
            count: 1,
            observedEventIDs: [eventOne]
        )
        let rhsExposure = NFItemExposureSyncState(
            itemIdentity: "item.1",
            firstSeenAt: now.addingTimeInterval(-100),
            lastSeenAt: now.addingTimeInterval(100),
            count: 1,
            observedEventIDs: [eventTwo]
        )
        let exposure = try XCTUnwrap(NFSyncMergeEngine.mergeExposure(lhsExposure, rhsExposure))
        XCTAssertEqual(exposure.count, 2)
        XCTAssertEqual(exposure.firstSeenAt, now.addingTimeInterval(-100))
        XCTAssertEqual(exposure.lastSeenAt, now.addingTimeInterval(100))

        let laterID = try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000020"))
        let earlierID = try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000021"))
        let invalid = NFDailyPlanSyncCandidate(
            id: earlierID,
            localDayKey: "2026-08-05",
            createdAt: now.addingTimeInterval(-200),
            isValid: false
        )
        let earlierValid = NFDailyPlanSyncCandidate(
            id: earlierID,
            localDayKey: "2026-08-05",
            createdAt: now.addingTimeInterval(-100),
            isValid: true
        )
        let laterValid = NFDailyPlanSyncCandidate(
            id: laterID,
            localDayKey: "2026-08-05",
            createdAt: now,
            isValid: true
        )
        XCTAssertEqual(
            NFSyncMergeEngine.canonicalDailyPlan(
                for: "2026-08-05",
                from: [laterValid, invalid, earlierValid]
            ),
            earlierValid
        )

        let sessionID = try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000030"))
        let active = NFSessionSyncState(
            id: sessionID,
            phase: .active,
            modifiedAt: now.addingTimeInterval(100),
            endedAt: nil
        )
        let completed = NFSessionSyncState(
            id: sessionID,
            phase: .completed,
            modifiedAt: now,
            endedAt: now
        )
        XCTAssertEqual(NFSyncMergeEngine.mergeSession(active, completed), completed)

        let oldSettings = NFMutableSyncRecord(id: earlierID, modifiedAt: now, value: "old")
        let newSettings = NFMutableSyncRecord(
            id: laterID,
            modifiedAt: now.addingTimeInterval(1),
            value: "new"
        )
        XCTAssertEqual(NFSyncMergeEngine.latestModified(oldSettings, newSettings), newSettings)
    }

    func testMergeCatalogMatchesAuthoritativeRecordSemantics() {
        XCTAssertEqual(NFSyncMergePolicyCatalog.strategy(for: .attempt), .appendOnlyIdempotent)
        XCTAssertEqual(NFSyncMergePolicyCatalog.strategy(for: .attemptReflection), .appendOnlyIdempotent)
        XCTAssertEqual(NFSyncMergePolicyCatalog.strategy(for: .dailyPlan), .earliestValidCandidate)
        XCTAssertEqual(NFSyncMergePolicyCatalog.strategy(for: .derivedState), .discardAndRecompute)
    }

    private func utcCalendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private func makeSpotlightChunk() -> NFSpotlightSourceChunk {
        NFSpotlightSourceChunk(
            stableChunkID: "document-1:page-4:chunk-2:v1",
            documentID: UUID(uuidString: "00000000-0000-0000-0000-000000000040")!,
            documentTitle: "Unpublished catalyst results",
            heading: "Unexpected activation-energy finding",
            normalizedText: "The unpublished experiment observed a lower activation barrier.",
            languageCode: "en",
            modifiedAt: Date(timeIntervalSince1970: 1_799_000_000)
        )
    }

    private func firstSpotlightRecord(in plan: NFSpotlightIndexPlan) -> NFSpotlightSearchRecord? {
        for mutation in plan.mutations {
            if case let .upsert(records) = mutation {
                return records.first
            }
        }
        return nil
    }
}

private actor StructuredImportNotificationClient: NFNotificationCenterClient {
    func refreshCategories(using presentation: NFNotificationCategoryPresentation) async {}
    func authorizationStatus() async -> NFNotificationAuthorizationStatus { .notDetermined }
    func requestAuthorizationAfterExplicitOptIn() async throws -> NFNotificationAuthorizationStatus {
        .notDetermined
    }
    func replaceManagedSchedules(with descriptors: [NFNotificationScheduleDescriptor]) async throws {}
    func removeManagedSchedules() async throws {}
}

private actor StructuredImportSpotlightClient: NFSpotlightIndexClient {
    func apply(_ plan: NFSpotlightIndexPlan) async throws {}
}

private actor StructuredDeletionTransportProbe: NFPrivateDocumentAssetTransport {
    private var mutationCalls = 0

    func start() async -> NFPrivateDocumentTransportSnapshot { transportSnapshot }

    func reconcile(_ inputs: [NFDocumentOriginalInput]) async {
        mutationCalls += 1
    }

    func enqueueDeletion(documentID: UUID) async {
        mutationCalls += 1
    }

    func synchronize() async -> NFPrivateDocumentTransportSnapshot {
        mutationCalls += 1
        return transportSnapshot
    }

    func snapshot() async -> NFPrivateDocumentTransportSnapshot { transportSnapshot }
    func documentState(documentID: UUID) async -> NFDocumentPrivateSyncState { .uploaded }
    func receivedRevisions() async -> [NFDocumentOriginalRevision] { [] }
    func receivedTombstones() async -> [NFDocumentOriginalTombstone] { [] }

    func deletionVerification(
        requestedDocumentIDs: Set<UUID>
    ) async -> NFPrivateDocumentDeletionVerification {
        mutationCalls += 1
        return NFPrivateDocumentDeletionVerification(
            requestedDocumentIDs: requestedDocumentIDs,
            durableTombstoneDocumentIDs: [],
            pendingChangeCount: 0,
            lastSuccessfulSyncAt: nil
        )
    }

    func clearLocalStatePreservingRemote() async throws {
        mutationCalls += 1
    }

    func stop() async {
        mutationCalls += 1
    }

    func mutationCallCount() -> Int { mutationCalls }

    private var transportSnapshot: NFPrivateDocumentTransportSnapshot {
        NFPrivateDocumentTransportSnapshot(
            isInstalled: true,
            accountState: .available,
            phase: .idle,
            queue: NFSyncQueueMetrics(pendingRecordCount: 0, pendingAssetCount: 0),
            lastSuccessfulSyncAt: nil
        )
    }
}

@MainActor
private final class PrivateZoneDeletionClientProbe: NFPrivateCloudZoneDeletionClient {
    let containerIdentifier: String
    private let accounts: [NFPrivateCloudAccountProbeResult]
    private var accountIndex = 0
    private var reads: [[NFPrivateCloudOwnedZone: NFPrivateCloudZoneReadResult]]
    private var deletions: [[NFPrivateCloudOwnedZone: NFPrivateCloudZoneDeleteResult]]
    private(set) var readCalls: [Set<NFPrivateCloudOwnedZone>] = []
    private(set) var deleteCalls: [Set<NFPrivateCloudOwnedZone>] = []
    var accountCallCount: Int { accountIndex }

    init(
        containerIdentifier: String,
        accounts: [NFPrivateCloudAccountProbeResult],
        reads: [[NFPrivateCloudOwnedZone: NFPrivateCloudZoneReadResult]] = [],
        deletions: [[NFPrivateCloudOwnedZone: NFPrivateCloudZoneDeleteResult]] = []
    ) {
        self.containerIdentifier = containerIdentifier
        self.accounts = accounts
        self.reads = reads
        self.deletions = deletions
    }

    func currentAccount() async -> NFPrivateCloudAccountProbeResult {
        guard !accounts.isEmpty else { return .couldNotDetermine }
        let index = min(accountIndex, accounts.count - 1)
        accountIndex += 1
        return accounts[index]
    }

    func deleteZones(
        _ zones: Set<NFPrivateCloudOwnedZone>
    ) async -> [NFPrivateCloudOwnedZone: NFPrivateCloudZoneDeleteResult] {
        deleteCalls.append(zones)
        guard !deletions.isEmpty else {
            return Dictionary(uniqueKeysWithValues: zones.map {
                ($0, .failed(redactedCode: "missing-fake-delete", retryable: false))
            })
        }
        return deletions.removeFirst()
    }

    func readZones(
        _ zones: Set<NFPrivateCloudOwnedZone>
    ) async -> [NFPrivateCloudOwnedZone: NFPrivateCloudZoneReadResult] {
        readCalls.append(zones)
        guard !reads.isEmpty else {
            return Dictionary(uniqueKeysWithValues: zones.map {
                ($0, .failed(redactedCode: "missing-fake-read", retryable: false))
            })
        }
        return reads.removeFirst()
    }
}

@MainActor
private final class PrivateCloudPreContainerCleanupClientProbe:
    NFPrivateCloudPreContainerCleanupClient
{
    var failingComponent: NFPrivateCloudPreContainerCleanupComponent?
    var calls: [NFPrivateCloudPreContainerCleanupComponent] = []
    private(set) var consumedRequestIDs: [UUID] = []

    init(failingComponent: NFPrivateCloudPreContainerCleanupComponent? = nil) {
        self.failingComponent = failingComponent
    }

    func removeAndVerify(
        _ component: NFPrivateCloudPreContainerCleanupComponent,
        requestID: UUID
    ) async throws {
        _ = requestID
        calls.append(component)
        if component == failingComponent {
            throw CocoaError(.fileWriteUnknown)
        }
    }

    func consumeStructuredStorePurgeReceipt(requestID: UUID) -> Bool {
        consumedRequestIDs.append(requestID)
        return true
    }
}

@MainActor
private final class FailingClearPrivateDeletionStateStore: NFPrivateCloudDeletionStateStoring {
    private let base: NFUserDefaultsPrivateCloudDeletionStateStore

    init(base: NFUserDefaultsPrivateCloudDeletionStateStore) {
        self.base = base
    }

    var hasPersistedRequest: Bool { base.hasPersistedRequest }

    func loadRequest() throws -> NFPrivateCloudCompleteDeletionRequest? {
        try base.loadRequest()
    }

    func saveRequest(_ request: NFPrivateCloudCompleteDeletionRequest) throws {
        try base.saveRequest(request)
    }

    func loadReceipt() throws -> NFPrivateCloudCompleteDeletionReceipt? {
        try base.loadReceipt()
    }

    func saveReceipt(_ receipt: NFPrivateCloudCompleteDeletionReceipt) throws {
        try base.saveReceipt(receipt)
    }

    func clear() throws {
        throw NFPrivateCloudDeletionStateStoreError.persistenceVerificationFailed
    }
}

private actor ActivationNotificationProbe: NFNotificationCenterClient {
    private let status: NFNotificationAuthorizationStatus
    private let blocksFirstScheduleReplacement: Bool
    private var authorizationRequests = 0
    private var refreshedCategoryPresentations: [NFNotificationCategoryPresentation] = []
    private var replacedScheduleBatches: [[NFNotificationScheduleDescriptor]] = []
    private var firstReplacementStartWaiters: [CheckedContinuation<Void, Never>] = []
    private var firstReplacementRelease: CheckedContinuation<Void, Never>?

    init(
        status: NFNotificationAuthorizationStatus = .notDetermined,
        blocksFirstScheduleReplacement: Bool = false
    ) {
        self.status = status
        self.blocksFirstScheduleReplacement = blocksFirstScheduleReplacement
    }

    func refreshCategories(using presentation: NFNotificationCategoryPresentation) async {
        refreshedCategoryPresentations.append(presentation)
    }

    func authorizationStatus() async -> NFNotificationAuthorizationStatus {
        authorizationRequests += 1
        try? await Task.sleep(nanoseconds: 50_000_000)
        return status
    }

    func requestAuthorizationAfterExplicitOptIn() async throws -> NFNotificationAuthorizationStatus {
        .notDetermined
    }

    func replaceManagedSchedules(with descriptors: [NFNotificationScheduleDescriptor]) async throws {
        replacedScheduleBatches.append(descriptors)
        guard blocksFirstScheduleReplacement, replacedScheduleBatches.count == 1 else { return }
        let waiters = firstReplacementStartWaiters
        firstReplacementStartWaiters.removeAll()
        waiters.forEach { $0.resume() }
        await withCheckedContinuation { continuation in
            firstReplacementRelease = continuation
        }
    }
    func removeManagedSchedules() async throws {}
    func authorizationRequestCount() -> Int { authorizationRequests }
    func categoryPresentations() -> [NFNotificationCategoryPresentation] {
        refreshedCategoryPresentations
    }
    func scheduledBatches() -> [[NFNotificationScheduleDescriptor]] {
        replacedScheduleBatches
    }
    func waitUntilFirstScheduleReplacementBegins() async {
        guard replacedScheduleBatches.isEmpty else { return }
        await withCheckedContinuation { continuation in
            firstReplacementStartWaiters.append(continuation)
        }
    }
    func releaseFirstScheduleReplacement() {
        firstReplacementRelease?.resume()
        firstReplacementRelease = nil
    }
}

private actor ActivationSpotlightProbe: NFSpotlightIndexClient {
    private var applications = 0

    func apply(_ plan: NFSpotlightIndexPlan) async throws {
        applications += 1
    }

    func applyCount() -> Int { applications }
}

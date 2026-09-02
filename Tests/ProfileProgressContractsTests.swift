import Foundation
import SwiftData
import XCTest

@testable import NeuroForge

final class ProfileProgressContractsTests: XCTestCase {
    func testSemanticForegroundTokensMeetTextContrastOnSystemSurfaceExtremes() {
        XCTAssertFalse(NFTheme.semanticForegroundSpecifications.isEmpty)
        for (name, specification) in NFTheme.semanticForegroundSpecifications {
            XCTAssertGreaterThanOrEqual(
                specification.light.contrastRatio(against: .white),
                4.5,
                "\(name) must meet WCAG AA contrast on a light system surface"
            )
            XCTAssertGreaterThanOrEqual(
                specification.dark.contrastRatio(against: .black),
                4.5,
                "\(name) must meet WCAG AA contrast on a dark system surface"
            )
        }
    }

    func testRoseProminentControlUsesAnExplicitPassingOnAccentPair() {
        XCTAssertGreaterThanOrEqual(
            NFTheme.roseControlTintSpec.light.contrastRatio(
                against: NFTheme.roseControlForegroundSpec.light
            ),
            4.5
        )
        XCTAssertGreaterThanOrEqual(
            NFTheme.roseControlTintSpec.dark.contrastRatio(
                against: NFTheme.roseControlForegroundSpec.dark
            ),
            4.5
        )
    }

    func testEveryAccentProminentControlUsesAPassingOnAccentPair() {
        XCTAssertFalse(NFTheme.accentControlSpecifications.isEmpty)
        for (name, specification) in NFTheme.accentControlSpecifications {
            XCTAssertGreaterThanOrEqual(
                specification.fill.light.contrastRatio(
                    against: specification.foreground.light
                ),
                4.5,
                "\(name) prominent controls must pass in light appearance"
            )
            XCTAssertGreaterThanOrEqual(
                specification.fill.dark.contrastRatio(
                    against: specification.foreground.dark
                ),
                4.5,
                "\(name) prominent controls must pass in dark appearance"
            )
        }
        XCTAssertGreaterThanOrEqual(
            NFTheme.controlTintSpec.light.contrastRatio(
                against: NFTheme.controlForegroundSpec.light
            ),
            4.5
        )
        XCTAssertGreaterThanOrEqual(
            NFTheme.controlTintSpec.dark.contrastRatio(
                against: NFTheme.controlForegroundSpec.dark
            ),
            4.5
        )
    }

    func testEverySemanticProminentTintCallSiteDeclaresItsPairedForeground() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let sourceRoot = repositoryRoot.appending(path: "Sources")
        let enumerator = try XCTUnwrap(
            FileManager.default.enumerator(
                at: sourceRoot,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            )
        )
        var violations: [String] = []
        for case let url as URL in enumerator where url.pathExtension == "swift" {
            let lines = try String(contentsOf: url, encoding: .utf8)
                .split(separator: "\n", omittingEmptySubsequences: false)
                .map(String.init)
            for (index, line) in lines.enumerated()
                where line.contains(".tint(NFTheme.controlTint") {
                let lowerBound = max(0, index - 3)
                let upperBound = min(lines.count, index + 4)
                let neighborhood = lines[lowerBound..<upperBound].joined(separator: "\n")
                guard neighborhood.contains(".foregroundStyle(NFTheme.controlForeground") else {
                    violations.append("\(url.lastPathComponent):\(index + 1)")
                    continue
                }
            }
        }
        XCTAssertTrue(
            violations.isEmpty,
            "Semantic prominent fills require the matching on-accent foreground: \(violations)"
        )
    }

    func testRoseProminentActionsUseThePairedSemanticFillAndForeground() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        for relativePath in [
            "Sources/Features/AI/AIStudioView.swift",
            "Sources/Features/Library/LibraryView.swift"
        ] {
            let source = try String(
                contentsOf: repositoryRoot.appending(path: relativePath),
                encoding: .utf8
            )
            XCTAssertTrue(source.contains(".tint(NFTheme.roseControlTint)"), relativePath)
            XCTAssertTrue(source.contains(".foregroundStyle(NFTheme.roseControlForeground)"), relativePath)
        }

        let sourceRoot = repositoryRoot.appending(path: "Sources")
        let enumerator = try XCTUnwrap(
            FileManager.default.enumerator(
                at: sourceRoot,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            )
        )
        var rawRoseControlTintUses: [String] = []
        for case let url as URL in enumerator where url.pathExtension == "swift" {
            let source = try String(contentsOf: url, encoding: .utf8)
            for (lineNumber, line) in source.split(separator: "\n", omittingEmptySubsequences: false).enumerated()
                where line.contains(".tint(NFTheme.rose)") && !line.contains("Slider") {
                rawRoseControlTintUses.append("\(url.lastPathComponent):\(lineNumber + 1)")
            }
        }
        XCTAssertTrue(
            rawRoseControlTintUses.isEmpty,
            "Prominent rose controls must use the tested fill/foreground pair: \(rawRoseControlTintUses)"
        )
    }

    func testRawAccentTokensAreNotUsedAsControlTintsOutsideContinuousControls() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let sourceRoot = repositoryRoot.appending(path: "Sources")
        let enumerator = try XCTUnwrap(
            FileManager.default.enumerator(
                at: sourceRoot,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            )
        )
        let rawAccentTokens = [
            "indigo", "cyan", "mint", "amber", "gold", "purple", "blue", "pink", "orange", "green", "rose"
        ]
        var violations: [String] = []
        for case let url as URL in enumerator where url.pathExtension == "swift" {
            let lines = try String(contentsOf: url, encoding: .utf8)
                .split(separator: "\n", omittingEmptySubsequences: false)
                .map(String.init)
            for (lineNumber, line) in lines.enumerated() {
                guard rawAccentTokens.contains(where: { line.contains(".tint(NFTheme.\($0))") }) else {
                    continue
                }
                // Sliders paint a track rather than a text-bearing control and
                // therefore do not need an on-accent foreground pairing.
                if line.contains("Slider") { continue }
                violations.append("\(url.lastPathComponent):\(lineNumber + 1)")
            }
        }
        XCTAssertTrue(
            violations.isEmpty,
            "Text-bearing controls must use a tested semantic tint/foreground pair: \(violations)"
        )
    }

    func testOnboardingKeyboardFocusStartsAtFirstMeaningfulControlForEachStep() {
        XCTAssertEqual(
            NFOnboardingKeyboardFocusPolicy.defaultTarget(forStepRawValue: 0),
            .primaryAction
        )
        XCTAssertEqual(
            NFOnboardingKeyboardFocusPolicy.defaultTarget(forStepRawValue: 1),
            .context(STEMField.general.rawValue)
        )
        XCTAssertEqual(
            NFOnboardingKeyboardFocusPolicy.defaultTarget(forStepRawValue: 2),
            .duration(5)
        )
    }

    func testPencilCalibrationPlatformGateExcludesPhonesMacAndCatalyst() {
        XCTAssertTrue(NFInputCalibrationCapabilities.canOfferPencilCalibration(
            isIOS: true,
            isPad: true,
            isMacCatalyst: false
        ))
        XCTAssertFalse(NFInputCalibrationCapabilities.canOfferPencilCalibration(
            isIOS: true,
            isPad: false,
            isMacCatalyst: false
        ))
        XCTAssertFalse(NFInputCalibrationCapabilities.canOfferPencilCalibration(
            isIOS: false,
            isPad: true,
            isMacCatalyst: false
        ))
        XCTAssertFalse(NFInputCalibrationCapabilities.canOfferPencilCalibration(
            isIOS: true,
            isPad: true,
            isMacCatalyst: true
        ))
    }

    @MainActor
    func testDayBoundaryChangePreservesMaterializedPlanThroughNewBoundary() throws {
        let (store, container) = try makeStore()
        var draft = validDraft()
        draft.dayBoundaryHour = 4
        try installProfile(draft, in: store)

        let calendar = calendar(timeZoneID: "Asia/Tokyo")
        let date = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-08-05T20:30:00Z"))
        let first = store.dailyPlan(at: date, calendar: calendar)
        let duplicate = store.dailyPlan(at: date.addingTimeInterval(300), calendar: calendar)

        XCTAssertEqual(first.id, duplicate.id)
        XCTAssertEqual(first.localDayKey, "2026-08-06")
        XCTAssertEqual(store.profile?.dayBoundaryHour, 4)
        XCTAssertEqual(store.dailyPlans.count, 1)
        XCTAssertEqual(store.dailyPlans.first?.dayBoundaryHour, 4)
        XCTAssertEqual(store.dailyPlans.first?.timeZoneIdentifier, "Asia/Tokyo")

        draft.dayBoundaryHour = 12
        try store.updateProfile(from: draft, at: date, calendar: calendar)
        XCTAssertEqual(store.dailyPlans.count, 1)
        let preserved = store.dailyPlan(at: date, calendar: calendar)
        XCTAssertEqual(preserved.id, first.id)
        XCTAssertEqual(preserved.localDayKey, first.localDayKey)
        XCTAssertEqual(store.dailyPlans.first?.dayBoundaryHour, 12)

        let restored = AppStore(context: container.mainContext)
        XCTAssertEqual(restored.profileSnapshot.dayBoundaryHour, 12)
        XCTAssertEqual(restored.dailyPlan(at: date, calendar: calendar).id, first.id)
    }

    @MainActor
    func testEveryProfilePreferencePreservesEveryMaterializedPlanStateAcrossRelaunch() throws {
        enum MaterializedPlanState: String, CaseIterable {
            case unstarted
            case partiallyCompleted
            case fullyCompleted
        }

        let preferenceMutations: [(name: String, apply: (inout OnboardingDraft) -> Void)] = [
            ("stage", { $0.stage = .professional }),
            ("fields", { $0.fields = [.engineering] }),
            ("goals", { $0.goals = [.programming] }),
            ("dailyDuration", { $0.dailyDuration = 20 }),
            ("timingMode", { $0.timingMode = .untimed }),
            ("aiMode", { $0.aiMode = .disabled }),
            ("iCloudEnabled", { $0.iCloudEnabled = true }),
            ("reducedMotion", { $0.reducedMotion = true }),
            ("hideTimers", { $0.hideTimers = true }),
            ("excludeVisualSpatial", { $0.excludeVisualSpatial = true }),
            ("preferredLanguageCode", {
                $0.preferredLanguageCode = $0.preferredLanguageCode == "ja" ? "en" : "ja"
            }),
            ("trainingDays", { $0.trainingDays = [2, 4, 6] }),
            ("dayBoundaryHour", { $0.dayBoundaryHour = 12 }),
            ("preferredAnswerMode", { $0.preferredAnswerMode = .keyboard }),
            ("reinforcementHapticsEnabled", { $0.reinforcementHapticsEnabled = true }),
            ("reinforcementSoundEnabled", { $0.reinforcementSoundEnabled = true })
        ]
        let calendar = calendar(timeZoneID: "Asia/Tokyo")
        let date = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-08-05T20:30:00Z"))

        let defaults = UserDefaults.standard
        let syncPreferenceKeys = [
            NFPrivateSyncBootstrapPreference.key,
            NFPrivateSyncBootstrapPreference.accountChangeLockKey,
            NFPrivateSyncBootstrapPreference.cloudDeletionLockKey
        ]
        let originalSyncPreferences = syncPreferenceKeys.map {
            (key: $0, value: defaults.object(forKey: $0))
        }
        defer {
            for preference in originalSyncPreferences {
                if let value = preference.value {
                    defaults.set(value, forKey: preference.key)
                } else {
                    defaults.removeObject(forKey: preference.key)
                }
            }
        }

        for state in MaterializedPlanState.allCases {
            for mutation in preferenceMutations {
                for key in syncPreferenceKeys { defaults.removeObject(forKey: key) }
                let (store, container) = try makeStore()
                let baseline = validDraft()
                try installProfile(baseline, in: store)
                let originalPlan = store.dailyPlan(at: date, calendar: calendar)
                XCTAssertGreaterThan(
                    originalPlan.blocks.count,
                    1,
                    "The partial-completion fixture requires at least two blocks."
                )

                let completedBlocks: [PlanBlock]
                switch state {
                case .unstarted:
                    completedBlocks = []
                case .partiallyCompleted:
                    completedBlocks = [try XCTUnwrap(originalPlan.blocks.first)]
                case .fullyCompleted:
                    completedBlocks = originalPlan.blocks
                }
                for block in completedBlocks {
                    try completePlanBlock(block, in: originalPlan, using: store)
                }
                let expectedCompletedBlockIDs = Set(completedBlocks.map(\.id))
                let assertionContext = "\(mutation.name), \(state.rawValue)"
                XCTAssertEqual(
                    store.completedPlanBlockIDs(planID: originalPlan.id),
                    expectedCompletedBlockIDs,
                    assertionContext
                )

                var changedDraft = baseline
                mutation.apply(&changedDraft)
                XCTAssertNotEqual(changedDraft, baseline, "Mutation must be isolated and material: \(mutation.name)")
                try store.updateProfile(from: changedDraft, at: date, calendar: calendar)

                let afterSave = store.dailyPlan(at: date, calendar: calendar)
                assertPlanContract(afterSave, preserves: originalPlan, context: assertionContext)
                XCTAssertEqual(
                    store.dailyPlans.filter { $0.localDayKey == originalPlan.localDayKey }.count,
                    1,
                    assertionContext
                )
                XCTAssertEqual(
                    store.completedPlanBlockIDs(planID: originalPlan.id),
                    expectedCompletedBlockIDs,
                    assertionContext
                )
                assertProfile(store.profile, matches: changedDraft, context: assertionContext)

                let relaunched = AppStore(context: ModelContext(container))
                let afterRelaunch = relaunched.dailyPlan(at: date, calendar: calendar)
                assertPlanContract(afterRelaunch, preserves: originalPlan, context: assertionContext)
                XCTAssertEqual(
                    relaunched.dailyPlans.filter { $0.localDayKey == originalPlan.localDayKey }.count,
                    1,
                    assertionContext
                )
                XCTAssertEqual(
                    relaunched.completedPlanBlockIDs(planID: originalPlan.id),
                    expectedCompletedBlockIDs,
                    assertionContext
                )
                assertProfile(relaunched.profile, matches: changedDraft, context: assertionContext)
            }
        }
    }

    @MainActor
    func testTimezoneTravelWithinEighteenHoursPreservesPlanAndRecalculatesBoundary() throws {
        let (store, container) = try makeStore()
        defer { _ = container }
        var draft = validDraft()
        draft.dayBoundaryHour = 4
        try installProfile(draft, in: store)

        let createdAt = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-08-05T23:00:00Z"))
        let utc = calendar(timeZoneID: "UTC")
        let tokyo = calendar(timeZoneID: "Asia/Tokyo")
        let original = store.dailyPlan(at: createdAt, calendar: utc)
        let travelledAt = createdAt.addingTimeInterval(2 * 3_600)
        let preserved = store.dailyPlan(at: travelledAt, calendar: tokyo)

        XCTAssertEqual(preserved.id, original.id)
        let record = try XCTUnwrap(store.dailyPlans.first)
        XCTAssertEqual(record.timeZoneIdentifier, "Asia/Tokyo")
        let expectedContext = NFPlanBoundaryContext.make(at: travelledAt, dayBoundaryHour: 4, calendar: tokyo)
        XCTAssertEqual(record.nextBoundaryAt, expectedContext.nextBoundary)
        XCTAssertEqual(
            record.travelPreservedUntil,
            min(createdAt.addingTimeInterval(18 * 3_600), expectedContext.nextBoundary)
        )

        let afterLimit = createdAt.addingTimeInterval(19 * 3_600)
        let next = store.dailyPlan(at: afterLimit, calendar: tokyo)
        XCTAssertNotEqual(next.id, original.id)
        XCTAssertEqual(store.dailyPlans.count, 2)
    }

    @MainActor
    func testOnboardingDoesNotRequirePolicyAcknowledgementAndRestartKeepsHistory() throws {
        let (store, container) = try makeStore()
        defer { _ = container }
        var draft = OnboardingDraft()
        draft.touchLatencyMilliseconds = 180
        XCTAssertTrue(store.completeOnboarding(draft))
        XCTAssertTrue(store.isOnboardingComplete)
        XCTAssertFalse(store.profile?.ageBandAcknowledged16Plus ?? true)
        XCTAssertEqual(store.profile?.claimsPolicyAcknowledgedVersion, 0)
        XCTAssertEqual(store.latestInputCalibration?.touchLatencyMilliseconds, 180)

        try store.saveLabAttempt(
            lab: .mentalMath,
            itemID: "history-preserved",
            prompt: "1 + 1",
            response: "2",
            correctAnswer: "2",
            isCorrect: true,
            confidence: .certain
        )
        let attemptIDs = store.attempts.map(\.id)
        store.restartOnboardingPreferences()

        XCTAssertFalse(store.isOnboardingComplete)
        XCTAssertFalse(store.profile?.ageBandAcknowledged16Plus ?? true)
        XCTAssertEqual(store.attempts.map(\.id), attemptIDs)
        XCTAssertFalse(store.inputCalibrations.isEmpty, "Restarting preferences must not delete locally recorded history.")
    }

    @MainActor
    func testLegacyClaimsPolicyStateDoesNotGateOnboardingAfterRelaunch() throws {
        let (store, container) = try makeStore()
        var draft = OnboardingDraft()
        draft.ageBandAcknowledged16Plus = true
        draft.touchLatencyMilliseconds = 120

        store.completeOnboarding(draft)
        XCTAssertNotNil(store.profile)
        XCTAssertTrue(store.isOnboardingComplete)
        XCTAssertEqual(store.profile?.claimsPolicyAcknowledgedVersion, 0)

        let restored = AppStore(context: container.mainContext)
        XCTAssertTrue(restored.isOnboardingComplete)

        restored.profile?.claimsPolicyAcknowledgedVersion = 0
        try restored.context.save()
        let stalePolicyStore = AppStore(context: container.mainContext)
        XCTAssertTrue(stalePolicyStore.isOnboardingComplete)
    }

    @MainActor
    func testInputCalibrationCanBeRerunAndPersistsPreferredMode() throws {
        let (store, container) = try makeStore()
        store.completeOnboarding(validDraft())
        try store.saveInputCalibration(
            preferredAnswerMode: .keyboard,
            keyboardLatencyMilliseconds: 92,
            touchLatencyMilliseconds: nil,
            pencilLatencyMilliseconds: nil
        )

        XCTAssertEqual(store.inputCalibrations.count, 2)
        XCTAssertEqual(store.latestInputCalibration?.preferredAnswerMode, .keyboard)
        XCTAssertEqual(store.profile?.preferredAnswerModeRaw, NFPreferredAnswerMode.keyboard.rawValue)
        let restored = AppStore(context: container.mainContext)
        XCTAssertEqual(restored.latestInputCalibration?.keyboardLatencyMilliseconds, 92)
    }

    @MainActor
    func testReinforcementPreferencesDefaultOffAndDoNotGateAttemptPersistence() throws {
        let (store, container) = try makeStore()
        defer { _ = container }
        try installProfile(validDraft(), in: store)
        XCTAssertFalse(store.profile?.reinforcementHapticsEnabled ?? true)
        XCTAssertFalse(store.profile?.reinforcementSoundEnabled ?? true)

        store.updateReinforcementPreferences(hapticsEnabled: true, soundEnabled: true)
        try store.saveLabAttempt(
            lab: .logicDebugging,
            itemID: "feedback-independent",
            prompt: "Trace",
            response: "state",
            correctAnswer: "state",
            isCorrect: true,
            confidence: .fairlyConfident
        )

        XCTAssertTrue(store.profile?.reinforcementHapticsEnabled == true)
        XCTAssertTrue(store.profile?.reinforcementSoundEnabled == true)
        XCTAssertEqual(store.attempts.first?.itemID, "feedback-independent")
    }

    @MainActor
    func testDeterministicInsightsExposeStrengthErrorConfidenceAndReviewEvidence() {
        let now = Date(timeIntervalSince1970: 1_785_000_000)
        var attempts: [AttemptRecord] = []
        for index in 0..<6 {
            let record = makeAttempt(
                id: "quant-\(index)",
                lab: .quantitative,
                correct: index < 4,
                confidence: index >= 4 ? .certain : .fairlyConfident,
                date: now.addingTimeInterval(Double(-10 - index) * 86_400),
                evidenceClass: index.isMultiple(of: 2) ? .practice : .nearTransfer
            )
            if index >= 4 { record.errorCode = "base_rate_neglect" }
            attempts.append(record)
        }
        for index in 0..<5 {
            attempts.append(makeAttempt(
                id: "logic-\(index)",
                lab: .logicDebugging,
                correct: true,
                confidence: .fairlyConfident,
                date: now.addingTimeInterval(Double(-12 - index) * 86_400),
                evidenceClass: index.isMultiple(of: 2) ? .practice : .retention
            ))
        }

        let snapshot = NFProgressInsightEngine.makeSnapshot(at: now, attempts: attempts)

        XCTAssertEqual(snapshot.strengths.first?.lab, .logicDebugging)
        XCTAssertEqual(snapshot.strengths.first?.ruleID, "progress.strength.v1.n5.credit75.two-channels")
        XCTAssertEqual(snapshot.overconfidenceHotspots.first?.lab, .quantitative)
        XCTAssertEqual(snapshot.overconfidenceHotspots.first?.evidenceAttemptIDs.count, 2)
        XCTAssertEqual(snapshot.repeatedErrors.first?.evidenceAttemptIDs.count, 2)
        XCTAssertFalse(snapshot.reviewsDue.isEmpty)
        XCTAssertTrue(snapshot.reviewsDue.allSatisfy { !$0.evidenceAttemptIDs.isEmpty })
    }

    @MainActor
    func testConsistencyIgnoresPlannedRestAndUsesBoundedProtection() throws {
        let calendar = calendar(timeZoneID: "UTC")
        let wednesday = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-08-05T12:00:00Z"))
        let monday = try XCTUnwrap(calendar.date(byAdding: .day, value: -2, to: wednesday))
        let attempts = [
            makeAttempt(id: "monday", lab: .mentalMath, correct: true, confidence: .certain, date: monday),
            makeAttempt(id: "wednesday", lab: .mentalMath, correct: true, confidence: .certain, date: wednesday)
        ]
        let restAware = NFConsistencyEngine.makeSnapshot(
            at: wednesday,
            attempts: attempts,
            trainingDays: [2, 4],
            windowDays: 3,
            calendar: calendar
        )
        XCTAssertEqual(restAware.currentActiveDayStreak, 2)
        XCTAssertEqual(restAware.days.map(\.status), [.active, .plannedRest, .active])

        let protection = NFConsistencyEngine.makeSnapshot(
            at: wednesday,
            attempts: [],
            trainingDays: Set(1...7),
            windowDays: 4,
            calendar: calendar
        )
        XCTAssertEqual(protection.days.filter { $0.status == .protectedPause }.count, 1)
        XCTAssertTrue(protection.days.contains { $0.status == .missedPlanned })
        XCTAssertFalse(protection.protectionAvailableThisWeek)
    }

    func testConsistencyBeginsAtProfileCreationWithoutRetroactiveMisses() throws {
        let calendar = calendar(timeZoneID: "UTC")
        let now = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-08-05T12:00:00Z"))
        let snapshot = NFConsistencyEngine.makeSnapshot(
            at: now,
            attempts: [],
            trainingDays: Set(1...7),
            trackingStartDate: now,
            windowDays: 28,
            calendar: calendar
        )

        XCTAssertEqual(snapshot.days.count, 1)
        XCTAssertEqual(snapshot.days.first?.status, .availableToday)
        XCTAssertTrue(snapshot.protectionAvailableThisWeek)
        XCTAssertEqual(snapshot.currentActiveDayStreak, 0)
    }

    func testTrainingDayBoundaryFormattingUsesTheConfiguredHour() {
        let english = Locale(identifier: "en_US")
        let fourAM = NFTrainingDayBoundaryFormatter.title(for: 4, locale: english)
        let noon = NFTrainingDayBoundaryFormatter.title(for: 12, locale: english)
        XCTAssertTrue(fourAM.contains("4:00"))
        XCTAssertTrue(fourAM.hasSuffix("AM"))
        XCTAssertTrue(noon.contains("12:00"))
        XCTAssertTrue(noon.hasSuffix("PM"))
        XCTAssertTrue(NFTrainingDayBoundaryFormatter.title(for: 0, locale: english).contains("midnight"))
    }

    @MainActor
    func testPrivateAnnotationsPersistAndExportOnlyWhenIncluded() throws {
        let (store, container) = try makeStore()
        let start = Date(timeIntervalSince1970: 1_785_000_000)
        try store.saveProgressAnnotation(
            startDate: start,
            endDate: start.addingTimeInterval(86_400),
            note: "Exam period",
            includeInExport: true
        )
        try store.saveProgressAnnotation(
            startDate: start.addingTimeInterval(2 * 86_400),
            endDate: start.addingTimeInterval(3 * 86_400),
            note: "Private schedule context",
            includeInExport: false
        )

        let restored = AppStore(context: container.mainContext)
        XCTAssertEqual(restored.progressAnnotations.count, 2)

        let urls = try NFDataExportService.makeExports(from: restored)
        defer { try? FileManager.default.removeItem(at: urls[0].deletingLastPathComponent()) }
        let archiveURL = try XCTUnwrap(urls.first { $0.lastPathComponent == "NeuroForge-Full-Archive.json" })
        let object = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: Data(contentsOf: archiveURL)) as? [String: Any]
        )
        let annotations = try XCTUnwrap(object["progressAnnotations"] as? [[String: Any]])
        XCTAssertEqual(annotations.count, 1)
        XCTAssertEqual(annotations.first?["note"] as? String, "Exam period")
        XCTAssertEqual((object["excludedPrivateAnnotationCount"] as? NSNumber)?.intValue, 1)
        XCTAssertFalse(String(data: try Data(contentsOf: archiveURL), encoding: .utf8)?.contains("Private schedule context") ?? true)
    }

    func testMethodologyCatalogCoversEveryLabWithAllFourSections() {
        XCTAssertEqual(Set(NFMethodologyCatalog.entries.map(\.lab)), Set(TrainingLab.allCases))
        for entry in NFMethodologyCatalog.entries {
            XCTAssertFalse(entry.purpose.isEmpty)
            XCTAssertFalse(entry.method.isEmpty)
            XCTAssertFalse(entry.limits.isEmpty)
            XCTAssertFalse(entry.evidence.isEmpty)
        }
    }

    func testAIQuestionReviewDeclaresRotorNavigableQuestionAndAnswerHeadings() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(
            contentsOf: repositoryRoot.appending(path: "Sources/Features/AI/AIStudioView.swift"),
            encoding: .utf8
        )
        let reviewStart = try XCTUnwrap(source.range(of: "Review questions and reference answers"))
        let reviewEnd = try XCTUnwrap(
            source.range(of: "if practiceResult?.questions.count", range: reviewStart.upperBound..<source.endIndex)
        )
        let review = String(source[reviewStart.lowerBound..<reviewEnd.lowerBound])

        XCTAssertTrue(review.contains("Text(\"Question \\(index + 1)\")"))
        XCTAssertTrue(review.contains(".accessibilityHeading(.h2)"))
        XCTAssertGreaterThanOrEqual(
            review.components(separatedBy: ".accessibilityHeading(.h3)").count - 1,
            2,
            "Reference answer and explanation must both be rotor-navigable headings."
        )
    }

    func testLearnerFacingForegroundsDoNotUseRawLabAccentTokens() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let roots = [
            repositoryRoot.appending(path: "Sources"),
            repositoryRoot.appending(path: "Widgets")
        ]
        let fileManager = FileManager.default
        var violations: [String] = []

        for root in roots {
            let enumerator = try XCTUnwrap(
                fileManager.enumerator(
                    at: root,
                    includingPropertiesForKeys: nil,
                    options: [.skipsHiddenFiles]
                )
            )
            for case let url as URL in enumerator where url.pathExtension == "swift" {
                let source = try String(contentsOf: url, encoding: .utf8)
                for (index, line) in source.split(separator: "\n", omittingEmptySubsequences: false).enumerated()
                    where line.contains("foregroundStyle") && line.contains("NFTheme.color(for:") {
                    violations.append("\(url.lastPathComponent):\(index + 1)")
                }
            }
        }

        XCTAssertTrue(
            violations.isEmpty,
            "Use NFTheme.foregroundColor(for:) for text and status symbols: \(violations)"
        )
    }

    func testInputCalibrationUsesThreeTrialsAndRobustSummaryMetrics() {
        XCTAssertEqual(NFInputCalibrationMetrics.requiredTrialCount, 3)
        XCTAssertEqual(NFInputCalibrationMetrics.median([410, 125, 180]), 180)
        XCTAssertEqual(NFInputCalibrationMetrics.median([100, 200, 300, 400]), 250)
        XCTAssertEqual(NFInputCalibrationMetrics.spread([410, 125, 180]), 285)
        XCTAssertEqual(NFInputCalibrationMetrics.median([]), 0)
        XCTAssertEqual(NFInputCalibrationMetrics.spread([]), 0)
    }

    func testProgressAnnotationValidationReportsExcessInsteadOfTruncating() {
        let exact = String(repeating: "a", count: NFProgressAnnotationValidation.maximumNoteCharacters)
        let excessive = exact + String(repeating: "b", count: 17)

        XCTAssertTrue(NFProgressAnnotationValidation.countMessage(for: exact).contains("0"))
        XCTAssertTrue(NFProgressAnnotationValidation.countMessage(for: excessive).contains("17"))
        XCTAssertEqual(excessive.count, 517, "Validation must inspect the submitted draft without mutating it.")
    }

    @MainActor
    func testProgressAnnotationPersistenceRejectsOverLimitCreateAndEditWithoutMutation() throws {
        let (store, container) = try makeStore()
        defer { _ = container }
        let date = Date(timeIntervalSince1970: 1_785_000_000)
        let original = String(repeating: "a", count: ProgressAnnotationRecord.maximumNoteCharacters)
        let excessive = original + "b"

        try store.saveProgressAnnotation(
            startDate: date,
            endDate: date,
            note: original,
            includeInExport: false
        )
        let persisted = try XCTUnwrap(store.progressAnnotations.first)
        let persistedID = persisted.id

        XCTAssertThrowsError(try store.saveProgressAnnotation(
            id: persistedID,
            startDate: date.addingTimeInterval(86_400),
            endDate: date.addingTimeInterval(86_400),
            note: excessive,
            includeInExport: true
        )) { error in
            XCTAssertEqual(
                error as? NFProgressAnnotationPersistenceError,
                .noteTooLong(maximum: ProgressAnnotationRecord.maximumNoteCharacters)
            )
        }
        XCTAssertEqual(store.progressAnnotations.count, 1)
        XCTAssertEqual(store.progressAnnotations.first?.note, original)
        XCTAssertFalse(store.progressAnnotations.first?.includeInExport ?? true)

        XCTAssertThrowsError(try store.saveProgressAnnotation(
            startDate: date,
            endDate: date,
            note: excessive,
            includeInExport: false
        ))
        XCTAssertEqual(store.progressAnnotations.count, 1)

        let unpersisted = ProgressAnnotationRecord(
            startDate: date,
            endDate: date,
            note: excessive,
            includeInExport: false
        )
        XCTAssertEqual(
            unpersisted.note,
            excessive,
            "The model initializer must never silently shorten submitted text."
        )
    }

    func testSourceReviewDraftIdentityIsStableAndSnapshotDetectsAuthoredState() {
        let documentID = UUID(uuidString: "57C4186A-5B71-4E4E-A225-8D4F0863F5A2")!
        let first = NFSourceReviewDraftIdentity.planID(documentID: documentID)
        let second = NFSourceReviewDraftIdentity.planID(documentID: documentID)

        XCTAssertEqual(first, second)
        XCTAssertTrue(NFSourceReviewDraftIdentity.isDraftPlanID(first))
        XCTAssertFalse(NFSourceReviewDraftIdentity.isDraftPlanID("daily-plan"))
        XCTAssertFalse(NFSourceReviewDraftSnapshot(
            response: "  ",
            confidence: nil,
            stageRawValue: "recall"
        ).hasAuthoredContent)
        XCTAssertTrue(NFSourceReviewDraftSnapshot(
            response: "A recalled explanation",
            confidence: .fairlyConfident,
            stageRawValue: "selfCheck"
        ).hasAuthoredContent)
    }

    @MainActor
    func testSourceReviewDraftRoundTripsResponseConfidenceAndStageDurably() throws {
        let (store, container) = try makeStore()
        defer { _ = container }
        let documentID = UUID(uuidString: "4AA78565-E48C-4D5C-8DCD-F18FCB760113")!
        let sessionID = UUID(uuidString: "3830E566-7028-4E37-BE9F-D10CE686AC36")!
        let chunkID = "source-review-draft-chunk"
        let snapshot = NFSourceReviewDraftSnapshot(
            response: "A durable recalled explanation",
            confidence: .certain,
            stageRawValue: "selfCheck"
        )

        try store.upsertCheckpoint(
            sessionID: sessionID,
            request: SessionRequest(
                lab: .retrieval,
                source: .focused,
                seed: 0,
                evidenceClass: .documentPractice,
                requestedItemCount: 1,
                planID: NFSourceReviewDraftIdentity.planID(documentID: documentID),
                planBlockID: chunkID
            ),
            currentIndex: 0,
            itemCount: 1,
            response: snapshot.response,
            scratchpad: "",
            results: [],
            assessmentEvents: snapshot.checkpointEvents
        )

        let reloaded = AppStore(context: container.mainContext)
        let checkpoint = try XCTUnwrap(reloaded.sessionCheckpoints.first {
            $0.sessionID == sessionID && $0.planBlockID == chunkID
        })
        XCTAssertEqual(NFSourceReviewDraftSnapshot(checkpoint: checkpoint), snapshot)
    }

    @MainActor
    private func completePlanBlock(
        _ block: PlanBlock,
        in plan: DailyPlan,
        using store: AppStore
    ) throws {
        try store.upsertCheckpoint(
            sessionID: UUID(),
            request: SessionRequest(
                lab: block.lab,
                source: .today,
                seed: plan.seed,
                requestedMinutes: block.minutes,
                evidenceClass: block.evidenceClass,
                planID: plan.id,
                planBlockID: block.id,
                isTimed: block.timed
            ),
            currentIndex: 0,
            itemCount: 1,
            response: "",
            scratchpad: "",
            results: [true],
            credits: [1],
            activeDurationSeconds: 10,
            hasCommittedCurrentItem: true,
            isComplete: true
        )
    }

    private func assertPlanContract(
        _ actual: DailyPlan,
        preserves expected: DailyPlan,
        context: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(actual.id, expected.id, context, file: file, line: line)
        XCTAssertEqual(actual.localDayKey, expected.localDayKey, context, file: file, line: line)
        XCTAssertEqual(actual.seed, expected.seed, context, file: file, line: line)
        XCTAssertEqual(actual.policyVersion, expected.policyVersion, context, file: file, line: line)
        XCTAssertEqual(actual.minutes, expected.minutes, context, file: file, line: line)
        XCTAssertEqual(actual.blocks.map(\.id), expected.blocks.map(\.id), context, file: file, line: line)
        XCTAssertEqual(actual.blocks.map(\.lab), expected.blocks.map(\.lab), context, file: file, line: line)
        XCTAssertEqual(actual.blocks.map(\.minutes), expected.blocks.map(\.minutes), context, file: file, line: line)
        XCTAssertEqual(
            actual.blocks.map(\.evidenceClass),
            expected.blocks.map(\.evidenceClass),
            context,
            file: file,
            line: line
        )
        XCTAssertEqual(actual.blocks.map(\.reasons), expected.blocks.map(\.reasons), context, file: file, line: line)
        XCTAssertEqual(actual.blocks.map(\.kindRaw), expected.blocks.map(\.kindRaw), context, file: file, line: line)
        XCTAssertEqual(
            actual.blocks.map(\.mechanicID),
            expected.blocks.map(\.mechanicID),
            context,
            file: file,
            line: line
        )
        XCTAssertEqual(actual.blocks.map(\.timed), expected.blocks.map(\.timed), context, file: file, line: line)
        XCTAssertEqual(
            actual.blocks.map(\.retentionItemIDs),
            expected.blocks.map(\.retentionItemIDs),
            context,
            file: file,
            line: line
        )
        XCTAssertEqual(
            actual.blocks.map(\.targetSkillID),
            expected.blocks.map(\.targetSkillID),
            context,
            file: file,
            line: line
        )
    }

    private func assertProfile(
        _ profile: UserProfileRecord?,
        matches draft: OnboardingDraft,
        context: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard let profile else {
            XCTFail("Profile missing after \(context)", file: file, line: line)
            return
        }
        XCTAssertEqual(profile.stageRaw, draft.stage.rawValue, context, file: file, line: line)
        XCTAssertEqual(
            Set(profile.fieldsRaw.split(separator: ",").map(String.init)),
            Set(draft.fields.map(\.rawValue)),
            context,
            file: file,
            line: line
        )
        XCTAssertEqual(
            Set(profile.goalsRaw.split(separator: ",").map(String.init)),
            Set(draft.goals.map(\.rawValue)),
            context,
            file: file,
            line: line
        )
        XCTAssertEqual(profile.dailyDuration, draft.dailyDuration, context, file: file, line: line)
        XCTAssertEqual(profile.timingModeRaw, draft.timingMode.rawValue, context, file: file, line: line)
        XCTAssertEqual(profile.aiModeRaw, draft.aiMode.rawValue, context, file: file, line: line)
        XCTAssertEqual(profile.iCloudEnabled, draft.iCloudEnabled, context, file: file, line: line)
        XCTAssertEqual(profile.reducedMotion, draft.reducedMotion, context, file: file, line: line)
        XCTAssertEqual(profile.hideTimers, draft.hideTimers, context, file: file, line: line)
        XCTAssertEqual(
            profile.excludeVisualSpatial,
            draft.excludeVisualSpatial,
            context,
            file: file,
            line: line
        )
        XCTAssertEqual(
            profile.preferredLanguageCode,
            draft.preferredLanguageCode,
            context,
            file: file,
            line: line
        )
        XCTAssertEqual(
            Set(profile.trainingDaysRaw.split(separator: ",").compactMap { Int($0) }),
            draft.trainingDays,
            context,
            file: file,
            line: line
        )
        XCTAssertEqual(
            profile.dayBoundaryHour,
            min(12, max(0, draft.dayBoundaryHour)),
            context,
            file: file,
            line: line
        )
        XCTAssertEqual(
            profile.preferredAnswerModeRaw,
            draft.preferredAnswerMode.rawValue,
            context,
            file: file,
            line: line
        )
        XCTAssertEqual(
            profile.reinforcementHapticsEnabled,
            draft.reinforcementHapticsEnabled,
            context,
            file: file,
            line: line
        )
        XCTAssertEqual(
            profile.reinforcementSoundEnabled,
            draft.reinforcementSoundEnabled,
            context,
            file: file,
            line: line
        )
    }

    @MainActor
    private func makeStore() throws -> (AppStore, ModelContainer) {
        let schema = Schema(NFSchemaV1.models)
        let container = try ModelContainer(
            for: schema,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        return (AppStore(context: container.mainContext), container)
    }

    private func validDraft() -> OnboardingDraft {
        var draft = OnboardingDraft()
        draft.claimsPolicyAcknowledgedVersion = NFClaimsPolicy.currentVersion
        draft.ageBandAcknowledged16Plus = true
        draft.touchLatencyMilliseconds = 150
        return draft
    }

    @MainActor
    private func installProfile(_ draft: OnboardingDraft, in store: AppStore) throws {
        let profile = UserProfileRecord(draft: draft)
        profile.onboardingVersion = 1
        store.context.insert(profile)
        try store.context.save()
        store.reload()
    }

    private func calendar(timeZoneID: String) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.timeZone = TimeZone(identifier: timeZoneID)!
        return calendar
    }

    private func makeAttempt(
        id: String,
        lab: TrainingLab,
        correct: Bool,
        confidence: ConfidenceLevel,
        date: Date,
        evidenceClass: EvidenceClass = .practice
    ) -> AttemptRecord {
        let record = AttemptRecord(
            sessionID: UUID(),
            lab: lab,
            itemID: id,
            prompt: "Prompt",
            response: correct ? "correct" : "incorrect",
            correctAnswer: "correct",
            isCorrect: correct,
            confidence: confidence,
            evidenceClass: evidenceClass
        )
        record.submittedAt = date
        record.shownAt = date.addingTimeInterval(-5)
        record.deterministicCredit = correct ? 1 : 0
        record.evidenceWeight = 1
        return record
    }
}

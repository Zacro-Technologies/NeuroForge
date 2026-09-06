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
            "Sources/Features/AI/AIStudioView.swift"
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
            ("timingMode", { $0.timingMode = .adaptive }),
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

        XCTAssertTrue(snapshot.strengths.isEmpty, "Legacy mixed channels do not demonstrate a reviewed band.")
        XCTAssertTrue(snapshot.overconfidenceHotspots.isEmpty, "Two legacy confidence entries do not establish calibration.")
        XCTAssertTrue(snapshot.repeatedErrors.isEmpty, "A protected near-transfer response cannot complete a public error pattern.")
        XCTAssertTrue(snapshot.reviewsDue.isEmpty, "Due entries require the versioned relation-level review queue.")
        XCTAssertTrue(snapshot.reviewsDue.allSatisfy { !$0.evidenceAttemptIDs.isEmpty })
    }

    @MainActor
    func testScoredChartsAndAbilityCoverageUseEffectiveResultsAndExactHistoryMembership() throws {
        let (store, container) = try makeStore()
        defer { _ = container }
        let now = Date(timeIntervalSince1970: 1_785_000_000)
        let records = (0..<3).map { index in
            makeAttempt(id: "chart-effective-\(index)", lab: .quantitative, correct: true,
                confidence: .certain, date: now.addingTimeInterval(Double(index - 10)))
        }
        for record in records { store.context.insert(record) }
        try store.context.save(); store.reload()
        try store.localSessions.appendDispositions([
            .init(id: "chart-corrected", attemptID: records[0].id.uuidString, revision: 100,
                policyVersion: NFHistoricalPracticeProjection.policyVersion, occurredAt: now,
                disposition: .legacyPracticeHistory, reason: "Synthetic rubric correction",
                correctedDerivedCredit: 0.5, supersedesDispositionID: nil),
            .init(id: "chart-withdrawn", attemptID: records[1].id.uuidString, revision: 100,
                policyVersion: NFHistoricalPracticeProjection.policyVersion, occurredAt: now,
                disposition: .excludedContentCorrection, reason: "Synthetic content withdrawal",
                correctedDerivedCredit: nil, supersedesDispositionID: nil)
        ])
        let observations = records.map(store.effectiveAttemptDTO)
        let weekly = try XCTUnwrap(NFWeeklyProgressPoint.make(from: observations,
            calendar: calendar(timeZoneID: "UTC"), at: now).first)
        let expectedIDs = [records[0].id, records[2].id]
        XCTAssertEqual(weekly.credit, 0.75, accuracy: 0.000_001)
        XCTAssertEqual(weekly.count, 2); XCTAssertEqual(weekly.attemptIDs, expectedIDs)
        let ability = NFAbilityEvidenceSnapshot(lab: .quantitative, attempts: records,
            effectiveObservations: observations, at: now)
        XCTAssertEqual(ability.evidenceCount, 2)
        XCTAssertEqual(try XCTUnwrap(ability.credit), 0.75, accuracy: 0.000_001)
        XCTAssertEqual(ability.metric(for: [.practice]).count, 2)
        let cumulative = EvidencePoint.make(from: ability.observations, at: now)
        XCTAssertEqual(cumulative.count, 2)
        XCTAssertEqual(Array(cumulative[0].attemptIDs), [records[0].id])
        XCTAssertEqual(Array(cumulative[1].attemptIDs), expectedIDs)
        XCTAssertEqual(cumulative[1].accuracy, 0.75, accuracy: 0.000_001)
        XCTAssertTrue(records.allSatisfy { $0.isCorrect && $0.deterministicCredit == 1 && $0.response == "correct" })
        XCTAssertEqual(store.attempts.count, 3, "History retains originals after derived points change")
    }

    @MainActor
    func testPublicChartsDoNotRevealProtectedPerAnswerScoresThroughPointInspection() throws {
        let (store, container) = try makeStore()
        defer { _ = container }
        let now = Date(timeIntervalSince1970: 1_785_000_000)
        let protected = makeAttempt(id: "protected-point", lab: .quantitative, correct: true,
            confidence: .certain, date: now, evidenceClass: .assessmentHoldout)
        let markerOnly = makeAttempt(id: "marker-point", lab: .quantitative, correct: false,
            confidence: .certain, date: now)
        markerOnly.sessionSourceRaw = SessionSource.baseline.rawValue
        let publicPractice = makeAttempt(id: "public-point", lab: .quantitative, correct: true,
            confidence: .certain, date: now)
        let records = [protected, markerOnly, publicPractice]
        for record in records { store.context.insert(record) }
        try store.context.save(); store.reload()
        let publicValues = store.publicPracticeChartObservations(from: records)
        XCTAssertEqual(publicValues.map(\.id), [publicPractice.id])
        XCTAssertEqual(NFWeeklyProgressPoint.make(from: publicValues, at: now).flatMap(\.attemptIDs), [publicPractice.id])
        XCTAssertEqual(EvidencePoint.make(from: publicValues, at: now).flatMap(\.attemptIDs), [publicPractice.id])
        XCTAssertTrue(EvidencePoint.make(from: [protected.dto], at: now).isEmpty)
        XCTAssertTrue(NFWeeklyProgressPoint.make(from: [protected.dto], at: now).isEmpty)
        XCTAssertEqual(NFProgressEvidenceProjection.categoryCounts([protected.dto], at: now)[.assessmentHoldout], 1)
        XCTAssertEqual(store.attempts.count, 3)
        XCTAssertEqual(protected.deterministicCredit, 1)
        XCTAssertEqual(markerOnly.deterministicCredit, 0)
    }

    func testChartProjectionDeduplicatesRejectsConflictsAndBoundsNumericInputs() throws {
        let now = Date(timeIntervalSince1970: 1_785_000_000)
        func observation(id: UUID = UUID(), credit: Double = 1, weight: Double = 1,
                         offset: Double = 0, format: String? = nil) -> AttemptDTO {
            AttemptDTO(id: id, skillID: TrainingLab.quantitative.skillID, lab: .quantitative,
                correct: credit == 1, credit: credit, confidence: nil,
                submittedAt: now.addingTimeInterval(offset), evidenceClass: .practice,
                evidenceWeight: weight, responseFormatRaw: format)
        }
        let first = observation(credit: 0.5, weight: 1e308)
        let second = observation(weight: 1e308)
        let values = [first, first, second, observation(credit: .nan), observation(weight: .infinity),
            observation(offset: 60), observation(format: "selfCheck")]
        let weekly = try XCTUnwrap(NFWeeklyProgressPoint.make(from: values, at: now).first)
        XCTAssertEqual(weekly.count, 2)
        XCTAssertEqual(weekly.credit, 0.75, accuracy: 0.000_001)
        XCTAssertTrue(weekly.credit.isFinite)
        let conflict = observation(id: first.id, credit: 0.25, weight: 1e308)
        XCTAssertEqual(NFProgressEvidenceProjection.eligible(values + [conflict], at: now).map(\.id), [second.id])
        XCTAssertEqual(NFProgressEvidenceProjection.eligible(Array((values + [conflict]).reversed()), at: now).map(\.id), [second.id])
    }

    @MainActor
    func testAbilityCumulativeChartUsesTheSameCrossActivityWeightsAsItsHeadline() throws {
        let now = Date(timeIntervalSince1970: 1_785_000_000)
        let direct = makeAttempt(id: "direct-quant", lab: .quantitative, correct: true,
            confidence: .certain, date: now.addingTimeInterval(-10))
        let cross = makeAttempt(id: "cross-quant", lab: .transfer, correct: false,
            confidence: .certain, date: now)
        cross.skillWeightsRaw = try XCTUnwrap(String(data: JSONEncoder().encode([
            TrainingLab.quantitative.skillID: 0.1, TrainingLab.transfer.skillID: 0.9]), encoding: .utf8))
        let snapshot = NFAbilityEvidenceSnapshot(lab: .quantitative, attempts: [direct, cross], at: now)
        let points = EvidencePoint.make(from: snapshot.observations, attributedTo: .quantitative, at: now)
        let last = try XCTUnwrap(points.last)
        XCTAssertEqual(try XCTUnwrap(snapshot.credit), 1 / 1.1, accuracy: 0.000_001)
        XCTAssertEqual(last.accuracy, try XCTUnwrap(snapshot.credit), accuracy: 0.000_001)
        XCTAssertEqual(Array(last.attemptIDs), [direct.id, cross.id])
        XCTAssertEqual(last.index, snapshot.evidenceCount)
    }

    func testCumulativeChartPreservesEarlyPointsAndSharesOneSeriesIdentityBuffer() throws {
        let now = Date(timeIntervalSince1970: 1_785_000_000)
        let records: [AttemptDTO] = (0..<10_000).map { index -> AttemptDTO in
            let weight: Double = index == 0 ? 1e-300 : 1e300
            let submittedAt = now.addingTimeInterval(Double(index - 10_000))
            return AttemptDTO(id: UUID(), skillID: TrainingLab.quantitative.skillID, lab: .quantitative,
                correct: index == 0, confidence: nil,
                submittedAt: submittedAt, evidenceClass: .practice, evidenceWeight: weight)
        }
        let points = EvidencePoint.make(from: records, at: now)
        XCTAssertEqual(points.count, records.count, "Later larger weights cannot remove earlier valid points")
        XCTAssertEqual(points[0].accuracy, 1)
        XCTAssertEqual(points[0].attemptIDs.count, 1)
        XCTAssertEqual(points[9_999].attemptIDs.count, 10_000)
        points[0].attemptIDs.withUnsafeBufferPointer { first in
            points[9_999].attemptIDs.withUnsafeBufferPointer { last in
                XCTAssertEqual(first.baseAddress, last.baseAddress, "Prefixes must share an immutable buffer, not copy quadratic UUID arrays")
            }
        }
        XCTAssertTrue(points.allSatisfy { $0.accuracy.isFinite && (0...1).contains($0.accuracy) })
    }

    func testChartInspectionKeepsWeekSeriesAndCumulativeHistorySeparate() throws {
        let now = Date(timeIntervalSince1970: 1_785_000_000)
        let ids = (0..<3).map { _ in UUID() }
        let records = (0..<3).map { index in
            AttemptDTO(id: ids[index], skillID: TrainingLab.quantitative.skillID,
                lab: index == 1 ? .retrieval : .quantitative, correct: true, confidence: nil,
                submittedAt: now.addingTimeInterval(index == 2 ? -8 * 86_400 : -60),
                evidenceClass: index == 1 ? .retention : .practice, evidenceWeight: 1)
        }
        let points = NFWeeklyProgressPoint.make(from: records, calendar: calendar(timeZoneID: "UTC"), at: now)
        let inspected = NFWeeklyProgressPoint.inspect(at: now, in: points)
        XCTAssertEqual(inspected.count, 2)
        XCTAssertEqual(Set(inspected.flatMap(\.attemptIDs)), Set(ids.prefix(2)))
        XCTAssertTrue(NFWeeklyProgressPoint.inspect(at: nil, in: points).isEmpty)
        let cumulative = EvidencePoint.make(from: records, at: now)
        XCTAssertEqual(cumulative.first(where: { $0.id == ids[0] }).map { Array($0.attemptIDs) }, [ids[2], ids[0]])
        XCTAssertEqual(cumulative.first(where: { $0.id == ids[1] }).map { Array($0.attemptIDs) }, [ids[1]])
    }

    @MainActor
    func testRepeatedErrorProjectionUsesEffectiveCorrectionsAndRetainsOriginals() throws {
        let (store, container) = try makeStore()
        defer { _ = container }
        let now = Date(timeIntervalSince1970: 1_785_000_000)
        let records = (0..<3).map { index in
            let record = makeAttempt(id: "diagnostic-\(index)", lab: .quantitative, correct: false,
                confidence: .certain, date: now.addingTimeInterval(Double(index - 10)))
            record.errorCode = "base_rate_neglect"
            return record
        }
        for record in records { store.context.insert(record) }
        try store.context.save()
        store.reload()
        func observations() -> [NFProgressDiagnosticObservation] {
            records.map { store.progressDiagnosticObservation(for: $0) }
        }
        XCTAssertEqual(NFProgressDiagnosticReducer.reduce(observations(), at: now).first?.evidenceAttemptIDs.count, 3)
        let dispositions = records.prefix(2).enumerated().map { index, record in
            NFHistoricalPracticeDispositionRecord(id: "diagnostic-correction-\(index)",
                attemptID: record.id.uuidString, revision: 100,
                policyVersion: NFHistoricalPracticeProjection.policyVersion, occurredAt: now,
                disposition: index == 0 ? .excludedContentCorrection : .legacyPracticeHistory,
                reason: "Authentic original retained; derived diagnostic withdrawn.",
                correctedDerivedCredit: index == 0 ? nil : 1, supersedesDispositionID: nil)
        }
        try store.localSessions.appendDispositions(dispositions)
        XCTAssertTrue(NFProgressInsightEngine.makeSnapshot(at: now, observations: observations()).repeatedErrors.isEmpty)
        XCTAssertTrue(records.allSatisfy { !$0.isCorrect && $0.deterministicCredit == 0 && $0.errorCode == "base_rate_neglect" })
        XCTAssertEqual(records.count, store.attempts.count)
        var local = store.localSessions.archive
        local.withheldProtectedConflictAttemptIDs = [records[2].id]
        try store.localSessions.importArchive(local)
        let protected = store.progressDiagnosticObservation(for: records[2])
        XCTAssertTrue(protected.isProtected)
        XCTAssertNil(protected.errorCode)
        XCTAssertTrue(NFProgressDiagnosticReducer.reduce([protected], at: now, minimumCount: 1).isEmpty)
        for evidence in [EvidenceClass.assessmentHoldout, .nearTransfer] {
            let rawProtected = NFProgressDiagnosticObservation(attempt: AttemptDTO(id: UUID(),
                skillID: TrainingLab.quantitative.skillID, lab: .quantitative, correct: false,
                confidence: nil, submittedAt: now, evidenceClass: evidence, evidenceWeight: 1), errorCode: "private-error")
            XCTAssertTrue(NFProgressDiagnosticReducer.reduce([rawProtected], at: now, minimumCount: 1).isEmpty)
        }
    }

    @MainActor
    func testDiagnosticProjectionRejectsLatePublicationAfterCorrectionAndCancellation() {
        let now = Date(timeIntervalSince1970: 1_785_000_000)
        let observation = NFProgressDiagnosticObservation(attempt: AttemptDTO(id: UUID(),
            skillID: TrainingLab.quantitative.skillID, lab: .quantitative, correct: false,
            confidence: nil, submittedAt: now, evidenceClass: .practice, evidenceWeight: 1), errorCode: "base_rate_neglect")
        let projection = NFProgressDiagnosticProjection()
        let first = projection.update([observation], at: now)
        let result = NFProgressDiagnosticReducer.reduce([observation], at: now, minimumCount: 1)
        projection.publish(result, for: first)
        XCTAssertEqual(projection.patterns.count, 1)
        let corrected = projection.update([], at: now)
        XCTAssertTrue(projection.patterns.isEmpty, "Invalidated authority disappears before the next worker publishes.")
        projection.publish(result, for: first)
        XCTAssertTrue(projection.patterns.isEmpty)
        projection.cancel()
        projection.publish(result, for: corrected)
        XCTAssertTrue(projection.patterns.isEmpty)
        XCTAssertFalse(projection.isLoading)
    }

    func testDiagnosticReducerRunsOnImmutableValuesAndRejectsDuplicateFutureAndInvalidEvidence() async {
        let now = Date(timeIntervalSince1970: 1_785_000_000)
        func observation(_ id: UUID, date: Date, weight: Double = 1, code: String? = "base_rate_neglect") -> NFProgressDiagnosticObservation {
            NFProgressDiagnosticObservation(attempt: AttemptDTO(id: id, skillID: TrainingLab.quantitative.skillID,
                lab: .quantitative, correct: false, credit: 0, confidence: nil, submittedAt: date,
                evidenceClass: .practice, evidenceWeight: weight), errorCode: code)
        }
        let invalid = NFProgressDiagnosticObservation(attempt: AttemptDTO(id: UUID(), skillID: TrainingLab.quantitative.skillID,
            lab: .quantitative, correct: false, credit: .nan, confidence: nil, submittedAt: now,
            evidenceClass: .practice, evidenceWeight: 1), errorCode: "invalid")
        XCTAssertEqual(invalid, invalid, "Invalid legacy values must not start an endless view update loop.")
        let first = observation(UUID(), date: now.addingTimeInterval(-2))
        let second = observation(UUID(), date: now.addingTimeInterval(-1))
        let values = [invalid, first, first, second, observation(UUID(), date: now.addingTimeInterval(1)),
            observation(UUID(), date: now, weight: .infinity), observation(UUID(), date: now, code: nil)]
        let patterns = await Task.detached { NFProgressDiagnosticReducer.reduce(values, at: now) }.value
        XCTAssertEqual(patterns.count, 1)
        XCTAssertEqual(patterns.first?.evidenceAttemptIDs, [first.attempt.id, second.attempt.id])
        let conflict = observation(first.attempt.id, date: now.addingTimeInterval(-2), weight: 0)
        XCTAssertTrue(NFProgressDiagnosticReducer.reduce(values + [conflict], at: now).isEmpty)
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

    @MainActor
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

    func testLearnerDayBoundariesUseCivilClockTimesAcrossSkippedAndRepeatedHours() throws {
        let formatter = ISO8601DateFormatter()
        func date(_ value: String) throws -> Date { try XCTUnwrap(formatter.date(from: value)) }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "America/Toronto"))
        let fixtures: [(String, Int, String, String)] = [
            ("2026-03-08T07:59:59Z", 4, "2026-03-07T09:00:00Z", "2026-03-08T08:00:00Z"),
            ("2026-03-08T08:00:00Z", 4, "2026-03-08T08:00:00Z", "2026-03-09T08:00:00Z"),
            ("2026-03-08T08:30:00Z", 4, "2026-03-08T08:00:00Z", "2026-03-09T08:00:00Z"),
            ("2026-03-08T06:59:59Z", 2, "2026-03-07T07:00:00Z", "2026-03-08T07:00:00Z"),
            ("2026-03-08T07:00:00Z", 2, "2026-03-08T07:00:00Z", "2026-03-09T06:00:00Z"),
            ("2026-11-01T04:59:59Z", 1, "2026-10-31T05:00:00Z", "2026-11-01T05:00:00Z"),
            ("2026-11-01T05:00:00Z", 1, "2026-11-01T05:00:00Z", "2026-11-02T06:00:00Z"),
            ("2026-11-01T06:30:00Z", 1, "2026-11-01T05:00:00Z", "2026-11-02T06:00:00Z"),
            ("2026-11-01T08:59:59Z", 4, "2026-10-31T08:00:00Z", "2026-11-01T09:00:00Z"),
            ("2026-11-01T09:00:00Z", 4, "2026-11-01T09:00:00Z", "2026-11-02T09:00:00Z")
        ]
        for (input, hour, start, next) in fixtures {
            let instant = try date(input)
            let context = NFPlanBoundaryContext.make(at: instant, dayBoundaryHour: hour, calendar: calendar)
            XCTAssertEqual(context.boundaryStart, try date(start), input)
            XCTAssertEqual(context.nextBoundary, try date(next), input)
            XCTAssertLessThanOrEqual(context.boundaryStart, instant)
            XCTAssertGreaterThan(context.nextBoundary, instant)
            XCTAssertEqual(context.dayBoundaryHour, hour)
        }
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

private final class NFDashboardWorkerProbe: @unchecked Sendable {
    private let lock = NSLock()
    private let releaseSignal = DispatchSemaphore(value: 0)
    private var held = false
    private var offMain = false
    private var timedOut = false
    func hold() {
        lock.withLock { held = true; offMain = !Thread.isMainThread }
        if releaseSignal.wait(timeout: .now() + 15) != .success { lock.withLock { timedOut = true } }
    }
    func release() { releaseSignal.signal() }
    func waitUntilHeld() async -> Bool {
        for _ in 0..<500 {
            if lock.withLock({ held }) { return true }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return false
    }
    var ranOffMain: Bool { lock.withLock { held && offMain && !timedOut } }
}

extension ProfileProgressContractsTests {
    @MainActor
    func testDashboardWorkerLateUncorrectedResultCannotReplaceNewEffectiveStoreProjection() async throws {
        let (store, container) = try makeStore(); defer { _ = container }
        let now = Date(timeIntervalSince1970: 1_785_000_000)
        let records = (0..<3).map { index in
            let value = makeAttempt(id: "dashboard-\(index)", lab: .quantitative, correct: false,
                confidence: .certain, date: now.addingTimeInterval(Double(index - 10)))
            value.errorCode = "base_rate_neglect"
            return value
        }
        for record in records { store.context.insert(record) }
        try store.context.save(); store.reload()
        let original = try NFEditorialCanonicalData.encode(records.map(NFImmutableAttemptRecordSnapshot.init))
        let reloadID = store.progressReloadID
        func input() -> NFProgressDashboardInput {
            .init(effectiveAttempts: records.map(store.effectiveAttemptDTO),
                  publicAttempts: store.publicPracticeChartObservations(from: records),
                  diagnostics: records.map { store.progressDiagnosticObservation(for: $0) },
                  capturedAt: now, calendar: Calendar(identifier: .gregorian))
        }
        let initial = input(), projection = NFProgressDashboardProjection(), probe = NFDashboardWorkerProbe()
        defer { probe.release() }
        let stale = Task { await projection.update(initial) { value in
            let result = try NFProgressDashboardReducer.make(value)
            probe.hold(); return result // Simulate a completed worker delivering late despite cancellation.
        } }
        let held = await probe.waitUntilHeld(); XCTAssertTrue(held)
        XCTAssertTrue(projection.isLoading); XCTAssertNil(projection.snapshot)
        let dispositions = records.prefix(2).enumerated().map { index, record in
            NFHistoricalPracticeDispositionRecord(id: "dashboard-correction-\(index)", attemptID: record.id.uuidString,
                revision: 100, policyVersion: NFHistoricalPracticeProjection.policyVersion, occurredAt: now,
                disposition: .excludedContentCorrection, reason: "Retain original; withdraw derived contribution.",
                correctedDerivedCredit: nil, supersedesDispositionID: nil)
        }
        try store.localSessions.appendDispositions(dispositions)
        store.reload(); XCTAssertNotEqual(store.progressReloadID, reloadID)
        await projection.update(input())
        let corrected = try XCTUnwrap(projection.snapshot)
        XCTAssertEqual(corrected.totalEvidence, 1)
        XCTAssertEqual(Set(corrected.weeklyPoints.flatMap(\.attemptIDs)), [records[2].id])
        XCTAssertEqual(corrected.calibration.eligibleCount, 1)
        XCTAssertEqual(corrected.patterns.flatMap(\.evidenceAttemptIDs), [records[2].id])
        probe.release(); await stale.value
        XCTAssertTrue(probe.ranOffMain); XCTAssertFalse(projection.isLoading)
        XCTAssertEqual(projection.snapshot?.totalEvidence, 1)
        XCTAssertEqual(Set(projection.snapshot?.weeklyPoints.flatMap(\.attemptIDs) ?? []), [records[2].id])
        XCTAssertEqual(try NFEditorialCanonicalData.encode(records.map(NFImmutableAttemptRecordSnapshot.init)), original)
    }

    @MainActor
    func testDashboardCancellationAndEmptyFilterCannotRepublishRetiredObservationsOrWriteArchive() async throws {
        let (store, container) = try makeStore(); defer { _ = container }
        let original = try NFEditorialCanonicalData.encode(store.localSessions.archive)
        let now = Date(timeIntervalSince1970: 1_785_000_000)
        let value = AttemptDTO(id: UUID(), skillID: TrainingLab.quantitative.skillID, lab: .quantitative,
            correct: true, confidence: .certain, submittedAt: now, evidenceClass: .practice, evidenceWeight: 1)
        let input = NFProgressDashboardInput(effectiveAttempts: [value], publicAttempts: [value],
            diagnostics: [], capturedAt: now, calendar: Calendar(identifier: .gregorian))
        let projection = NFProgressDashboardProjection(), probe = NFDashboardWorkerProbe()
        defer { probe.release() }
        let cancelled = Task { await projection.update(input) { value in probe.hold(); return try NFProgressDashboardReducer.make(value) } }
        let held = await probe.waitUntilHeld(); XCTAssertTrue(held)
        cancelled.cancel(); projection.cancel()
        let empty = NFProgressDashboardInput(effectiveAttempts: [], publicAttempts: [], diagnostics: [],
            capturedAt: now, calendar: input.calendar)
        await projection.update(empty)
        XCTAssertEqual(projection.snapshot?.totalEvidence, 0)
        XCTAssertEqual(projection.snapshot?.calibration.eligibleCount, 0)
        XCTAssertTrue(projection.snapshot?.weeklyPoints.isEmpty == true)
        probe.release(); await cancelled.value
        XCTAssertTrue(probe.ranOffMain); XCTAssertFalse(projection.isLoading)
        XCTAssertTrue(projection.snapshot?.weeklyPoints.isEmpty == true)
        XCTAssertEqual(try NFEditorialCanonicalData.encode(store.localSessions.archive), original)
    }

    @MainActor
    func testDashboardTenThousandImmutableRowsReduceOffMainWithExactChartMembership() async throws {
        let now = Date(timeIntervalSince1970: 1_785_000_000)
        let values = (0..<10_000).map { index in AttemptDTO(id: UUID(),
            skillID: TrainingLab.quantitative.skillID, lab: .quantitative, correct: index.isMultiple(of: 2),
            confidence: .certain, submittedAt: now.addingTimeInterval(-Double(index)),
            evidenceClass: .practice, evidenceWeight: 1) }
        let input = NFProgressDashboardInput(effectiveAttempts: values, publicAttempts: values,
            diagnostics: [], capturedAt: now, calendar: Calendar(identifier: .gregorian))
        let projection = NFProgressDashboardProjection(), probe = NFDashboardWorkerProbe()
        defer { probe.release() }
        let task = Task { await projection.update(input) { value in probe.hold(); return try NFProgressDashboardReducer.make(value) } }
        let held = await probe.waitUntilHeld(); XCTAssertTrue(held)
        XCTAssertTrue(projection.isLoading); XCTAssertNil(projection.snapshot)
        // This MainActor assertion executes while the actual worker is held.
        XCTAssertTrue(Thread.isMainThread)
        probe.release(); await task.value
        XCTAssertTrue(probe.ranOffMain)
        let result = try XCTUnwrap(projection.snapshot)
        XCTAssertEqual(result.totalEvidence, 10_000)
        XCTAssertEqual(result.categories[.practice], 10_000)
        XCTAssertEqual(result.calibration.matchingCount, 5_000)
        XCTAssertEqual(Set(result.weeklyPoints.flatMap(\.attemptIDs)), Set(values.map(\.id)))
        XCTAssertEqual(result.weeklyPoints.reduce(0) { $0 + $1.count }, 10_000)
    }
}


extension ProfileProgressContractsTests {
    @MainActor
    private func dashboardReviewedStore() throws -> (AppStore, ModelContainer, NFUniversalSessionRuntime) {
        let template = SessionRequest(lab: .mentalMath, source: .focused, seed: 8840, localeIdentifier: "en",
            field: .general, targetDifficulty: 0.5, requestedItemCount: 1,
            isTimed: false, timingCondition: .init(.untimed))
        var admitted: NFEditorialAdmissionEntry?
        for questionID in NFOfflineQuestionBank.rotationBank.questionIDs(for: .mentalMath) {
            guard let ordinal = NFOfflineQuestionBank.ordinal(forQuestionID: questionID, lab: .mentalMath) else { continue }
            let exercise = NFDeterministicSessionExerciseFactory.makeExercise(
                request: template.launchOnly(offlineQuestionOrdinals: [ordinal]), index: 0, assessmentDescriptor: nil)
            guard exercise.availabilityReason == nil, case .numeric = exercise.interaction,
                  let metadata = exercise.contractMetadata else { continue }
            let demand = NFEditorialDemandRecord(objectiveID: "QA.dashboard.arithmetic", familyID: "QA.dashboard.numeric",
                structureID: "QA.dashboard.structure", semanticFingerprint: metadata.semanticFingerprint,
                editorialBand: .b1, demandVector: .init(reasoningSteps: 1,
                    quantityDomain: ["source": "synthetic policy fixture over exact retained key"],
                    representationMappings: ["numeric"], misconceptionClasses: [], abstraction: "concrete",
                    relevantGivens: 2, irrelevantGivens: 0, missingGivens: 0,
                    scaffoldConditionID: "essential-only", prerequisiteConceptIDs: []),
                bandContractVersion: "QA.dashboard-band.v1", calibrationStatus: .editorial, calibrationVersion: nil,
                independentEligible: true, protectedEligible: false,
                assistancePolicyID: NFEditorialNativeProtocol.toolConditionID,
                answerContractVersion: "QA.dashboard-native.v1", expectedDurationRange: .init(minimumSeconds: 10, maximumSeconds: 40),
                representationIDs: ["numeric"], prerequisiteObjectiveIDs: [])
            admitted = .init(id: "QA.dashboard.entry", bankQuestionID: questionID,
                exerciseDigest: try NFLocalItemCheckpoint.digest(exercise), scorerVersion: NFExerciseScoringEngine.scoringVersion,
                lab: .mentalMath, contentLocale: "en", demand: demand)
            break
        }
        let admissions = NFEditorialAdmissionContext(version: "QA.dashboard-admission.v1", entries: [try XCTUnwrap(admitted)])
        let schema = Schema(NFSchemaV1.models)
        let container = try ModelContainer(for: schema, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        var draft = validDraft(); draft.timingMode = .untimed
        container.mainContext.insert(UserProfileRecord(draft: draft)); try container.mainContext.save()
        let repository = NFLocalSessionRepository(editorialAdmissions: admissions)
        let store = AppStore(context: container.mainContext, localSessionRepository: repository)
        XCTAssertTrue(store.beginSession(lab: .mentalMath, source: .focused, field: .general,
            targetDifficulty: 0.5, requestedItemCount: 1, seedOverride: 8840,
            isTimed: false, timingCondition: .init(.untimed), launchLocaleIdentifier: "en"), store.lastErrorMessage ?? "launch failed")
        let runtime = NFUniversalSessionRuntime(request: try XCTUnwrap(store.activeSessionRequest))
        XCTAssertTrue(runtime.checkpointDraft(store: store)); runtime.resume(); runtime.acknowledgePresented()
        guard case let .numeric(answer) = runtime.exercise.interaction else {
            throw NFLocalSessionRepository.RepositoryError.corruptSnapshot
        }
        runtime.numericValue = String(answer.answer.value); runtime.numericUnit = answer.answer.canonicalUnit ?? ""
        runtime.chooseConfidence(.fairlyConfident); runtime.submitInline(store: store)
        XCTAssertEqual(runtime.stage, .feedback); XCTAssertNil(runtime.saveError)
        XCTAssertNotNil(store.effectiveAttemptDTO(try XCTUnwrap(store.attempts.first)).editorialObservation)
        return (store, container, runtime)
    }

    @MainActor
    func testDashboardIncrementalCoreSaveInvalidatesHeldWorkerWithoutReloadOrArchiveWrite() async throws {
        let (store, container) = try makeStore(); defer { _ = container }
        let clock = NFProgressDashboardClock(capturedAt: Date(), calendar: calendar(timeZoneID: "UTC"))
        let original = try NFEditorialCanonicalData.encode(store.localSessions.archive)
        let key = store.progressDashboardRequest(filters: .unfiltered, clock: clock)
        let initial = store.progressDashboardInput(filters: .unfiltered, clock: clock)
        let projection = NFProgressDashboardProjection(), probe = NFDashboardWorkerProbe()
        defer { probe.release() }
        let stale = Task { await projection.update(initial) { value in
            let result = try NFProgressDashboardReducer.make(value); probe.hold(); return result
        } }
        let held = await probe.waitUntilHeld(); XCTAssertTrue(held)
        let id = UUID()
        try store.saveLabAttempt(lab: .quantitative, itemID: "QA.dashboard.core-only", prompt: "Retained practice",
            response: "A", correctAnswer: "A", isCorrect: true, confidence: .certain, attemptID: id)
        let changed = store.progressDashboardRequest(filters: .unfiltered, clock: clock)
        XCTAssertNotEqual(key.reloadID, changed.reloadID)
        XCTAssertEqual(key.archiveRevision, changed.archiveRevision)
        XCTAssertEqual(key.clock, changed.clock)
        let current = clock.refreshing(isActive: true, at: Date(), calendar: clock.calendar)
        await projection.update(store.progressDashboardInput(filters: .unfiltered, clock: current))
        XCTAssertEqual(projection.snapshot?.totalEvidence, 1)
        XCTAssertEqual(Set(projection.snapshot?.weeklyPoints.flatMap(\.attemptIDs) ?? []), [id])
        probe.release(); await stale.value
        XCTAssertEqual(projection.snapshot?.totalEvidence, 1)
        XCTAssertEqual(try NFEditorialCanonicalData.encode(store.localSessions.archive), original)
        XCTAssertEqual(store.attempts.count, 1)
    }

    @MainActor
    func testDashboardQuarantineAPIWithdrawsReviewedObservationBeforeHeldWorkerReturnsWithoutReload() async throws {
        let (store, container, runtime) = try dashboardReviewedStore()
        defer { runtime.releaseWriter(); _ = container }
        let clock = NFProgressDashboardClock(capturedAt: Date(), calendar: calendar(timeZoneID: "UTC"))
        let key = store.progressDashboardRequest(filters: .unfiltered, clock: clock)
        let original = try NFEditorialCanonicalData.encode(store.localSessions.archive)
        let initial = store.progressDashboardInput(filters: .unfiltered, clock: clock)
        XCTAssertEqual(initial.effectiveAttempts.compactMap(\.editorialObservation).count, 1)
        let projection = NFProgressDashboardProjection(), probe = NFDashboardWorkerProbe()
        defer { probe.release() }
        let stale = Task { await projection.update(initial) { value in
            let result = try NFProgressDashboardReducer.make(value); probe.hold(); return result
        } }
        let held = await probe.waitUntilHeld(); XCTAssertTrue(held)
        try store.saveItemReport(exercise: runtime.exercise, reason: "Ambiguous", note: "Synthetic quarantine regression")
        let changed = store.progressDashboardRequest(filters: .unfiltered, clock: clock)
        XCTAssertNotEqual(key.reloadID, changed.reloadID)
        XCTAssertEqual(key.archiveRevision, changed.archiveRevision)
        let newInput = store.progressDashboardInput(filters: .unfiltered, clock: clock)
        XCTAssertTrue(newInput.effectiveAttempts.compactMap(\.editorialObservation).isEmpty)
        await projection.update(newInput)
        XCTAssertTrue(projection.snapshot?.summaries.allSatisfy { $0.evidenceCount == 0 } == true)
        probe.release(); await stale.value
        XCTAssertTrue(projection.snapshot?.summaries.allSatisfy { $0.evidenceCount == 0 } == true)
        XCTAssertEqual(try NFEditorialCanonicalData.encode(store.localSessions.archive), original)
        XCTAssertEqual(store.attempts.count, 1, "Quarantine changes authority, not the immutable answer")
    }

    @MainActor
    func testDashboardJournalFailureImmediatelyWithholdsConflictingCoreIdentityWithoutReload() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "NFDashboardConflict-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appending(path: "sessions-v1.json"), backup = root.appending(path: "acknowledged.json")
        let repository = NFLocalSessionRepository(url: url)
        try repository.importArchive(.init())
        let schema = Schema(NFSchemaV1.models)
        let container = try ModelContainer(for: schema, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let store = AppStore(context: container.mainContext, localSessionRepository: repository,
            temporaryArtifactsRootURL: root, allowsSharedWidgetPublishing: false)
        let id = UUID()
        try store.saveLabAttempt(lab: .quantitative, itemID: "QA.dashboard.conflict", prompt: "Retained original",
            response: "A", correctAnswer: "A", isCorrect: true, confidence: .certain, attemptID: id)
        let original = try NFImmutableAttemptRecordSnapshot.encoded(NFImmutableAttemptRecordSnapshot(try XCTUnwrap(store.attempts.first)))
        let archive = try NFEditorialCanonicalData.encode(repository.archive), bytes = try Data(contentsOf: url)
        let clock = NFProgressDashboardClock(capturedAt: Date(), calendar: calendar(timeZoneID: "UTC"))
        let key = store.progressDashboardRequest(filters: .unfiltered, clock: clock)
        let initial = store.progressDashboardInput(filters: .unfiltered, clock: clock)
        let projection = NFProgressDashboardProjection(), probe = NFDashboardWorkerProbe()
        defer { probe.release() }
        let stale = Task { await projection.update(initial) { value in
            let result = try NFProgressDashboardReducer.make(value); probe.hold(); return result
        } }
        let held = await probe.waitUntilHeld(); XCTAssertTrue(held)
        // A real publication fault retains the acknowledged predecessor privately.
        try FileManager.default.moveItem(at: url, to: backup)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
        XCTAssertThrowsError(try store.saveLabAttempt(lab: .quantitative, itemID: "QA.dashboard.conflict", prompt: "Retained original",
            response: "B", correctAnswer: "A", isCorrect: false, confidence: .certain, attemptID: id))
        XCTAssertTrue(store.unresolvedAttemptConflictIDs.contains(id))
        let changed = store.progressDashboardRequest(filters: .unfiltered, clock: clock)
        XCTAssertNotEqual(key.reloadID, changed.reloadID)
        XCTAssertEqual(key.archiveRevision, changed.archiveRevision)
        await projection.update(store.progressDashboardInput(filters: .unfiltered, clock: clock))
        XCTAssertEqual(projection.snapshot?.totalEvidence, 0)
        XCTAssertTrue(projection.snapshot?.weeklyPoints.isEmpty == true)
        probe.release(); await stale.value
        XCTAssertEqual(projection.snapshot?.totalEvidence, 0)
        XCTAssertEqual(store.attempts.count, 1)
        XCTAssertEqual(try NFImmutableAttemptRecordSnapshot.encoded(NFImmutableAttemptRecordSnapshot(try XCTUnwrap(store.attempts.first))), original)
        XCTAssertEqual(try NFEditorialCanonicalData.encode(repository.archive), archive)
        XCTAssertEqual(try Data(contentsOf: backup), bytes)
    }

    @MainActor
    func testDashboardCapturedClockRefreshesWeekAndRollingCutoffOnForegroundWithoutWrites() async throws {
        let (store, container) = try makeStore(); defer { _ = container }
        var monday = calendar(timeZoneID: "UTC"); monday.firstWeekday = 2; monday.minimumDaysInFirstWeek = 4
        let sunday = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-08-02T12:00:00Z"))
        let old = makeAttempt(id: "dashboard-clock", lab: .quantitative, correct: true, confidence: .certain,
            date: sunday.addingTimeInterval(-86_400))
        store.context.insert(old); try store.context.save(); store.reload()
        let archive = try NFEditorialCanonicalData.encode(store.localSessions.archive)
        let raw = try NFImmutableAttemptRecordSnapshot.encoded(NFImmutableAttemptRecordSnapshot(old))
        let clock = NFProgressDashboardClock(capturedAt: sunday, calendar: monday)
        let weekFilter = NFProgressFilters(period: .currentWeek)
        let key = store.progressDashboardRequest(filters: weekFilter, clock: clock)
        let input = store.progressDashboardInput(filters: weekFilter, clock: clock)
        XCTAssertEqual(input.capturedAt, sunday); XCTAssertEqual(input.calendar, monday)
        XCTAssertEqual(input.effectiveAttempts.map(\.id), [old.id])
        var sundayCalendar = monday; sundayCalendar.firstWeekday = 1; sundayCalendar.minimumDaysInFirstWeek = 1
        let changedWeek = clock.refreshing(isActive: true, at: sunday, calendar: sundayCalendar)
        XCTAssertEqual(monday.startOfDay(for: sunday), sundayCalendar.startOfDay(for: sunday))
        XCTAssertNotEqual(key, store.progressDashboardRequest(filters: weekFilter, clock: changedWeek))
        XCTAssertTrue(store.progressDashboardInput(filters: weekFilter, clock: changedWeek).effectiveAttempts.isEmpty)
        let nextDay = sunday.addingTimeInterval(13 * 3_600)
        XCTAssertEqual(clock.refreshing(isActive: false, at: nextDay, calendar: sundayCalendar), clock)
        let foreground = clock.refreshing(isActive: true, at: nextDay, calendar: monday)
        let projection = NFProgressDashboardProjection(), probe = NFDashboardWorkerProbe()
        defer { probe.release() }
        let stale = Task { await projection.update(input) { value in
            let result = try NFProgressDashboardReducer.make(value); probe.hold(); return result
        } }
        let held = await probe.waitUntilHeld(); XCTAssertTrue(held)
        await projection.update(store.progressDashboardInput(filters: weekFilter, clock: foreground))
        XCTAssertEqual(projection.snapshot?.totalEvidence, 0)
        probe.release(); await stale.value
        XCTAssertTrue(projection.snapshot?.weeklyPoints.isEmpty == true)
        // A rolling 28-day cutoff can change within a day, so the active minute
        // tick uses the full captured date instead of only a midnight key.
        let fourWeeks = NFProgressFilters(period: .fourWeeks)
        let edge = try XCTUnwrap(monday.date(byAdding: .day, value: 28, to: old.submittedAt)).addingTimeInterval(-1)
        XCTAssertTrue(fourWeeks.includes(old, at: edge, calendar: monday))
        XCTAssertFalse(fourWeeks.includes(old, at: edge.addingTimeInterval(NFProgressDashboardClock.maximumRefreshInterval), calendar: monday))
        XCTAssertEqual(NFProgressDashboardClock.maximumRefreshInterval, 60)
        XCTAssertEqual(try NFImmutableAttemptRecordSnapshot.encoded(NFImmutableAttemptRecordSnapshot(old)), raw)
        XCTAssertEqual(try NFEditorialCanonicalData.encode(store.localSessions.archive), archive)
    }
}

extension ProfileProgressContractsTests {
    @MainActor
    func testDashboardCompletionOnlyUpsertInvalidatesHeldEngagementWithoutReload() async throws {
        let (store, container) = try makeStore()
        defer { withExtendedLifetime(container) {} }
        XCTAssertFalse(store.allowsSharedWidgetPublishing)
        try store.saveLabAttempt(lab: .mentalMath, itemID: "QA.dashboard.completion-only",
            prompt: "A saved practice answer", response: "4", correctAnswer: "4",
            isCorrect: true, confidence: .certain)
        let record = try XCTUnwrap(store.attempts.first)
        let request = SessionRequest(lab: .mentalMath, source: .focused, seed: 71, requestedItemCount: 1)
        try store.upsertCheckpoint(sessionID: record.sessionID, request: request, currentIndex: 0,
            itemCount: 1, response: record.response, scratchpad: "", results: [true], credits: [1],
            hasCommittedCurrentItem: true)
        let clock = NFProgressDashboardClock(capturedAt: Date(), calendar: calendar(timeZoneID: "UTC"))
        let key = store.progressDashboardRequest(filters: .unfiltered, clock: clock)
        let initial = store.progressDashboardInput(filters: .unfiltered, clock: clock)
        let attemptBytes = try NFEditorialCanonicalData.encode(store.attempts.map(NFImmutableAttemptRecordSnapshot.init))
        let archiveBytes = try NFEditorialCanonicalData.encode(store.localSessions.archive)
        let projection = NFProgressDashboardProjection(), probe = NFDashboardWorkerProbe()
        defer { probe.release() }
        let stale = Task { await projection.update(initial) { input in
            let value = try NFProgressDashboardReducer.make(input)
            probe.hold() // A finished pre-completion result ignores cancellation and returns late.
            return value
        } }
        let held = await probe.waitUntilHeld(); XCTAssertTrue(held)
        XCTAssertTrue(Thread.isMainThread); XCTAssertNil(projection.snapshot)
        XCTAssertEqual(try NFProgressDashboardReducer.make(initial).forge?.totalXP, 10)
        try store.upsertCheckpoint(sessionID: record.sessionID, request: request, currentIndex: 0,
            itemCount: 1, response: record.response, scratchpad: "", results: [true], credits: [1],
            hasCommittedCurrentItem: true, isComplete: true)
        // Do not call reload: neither attempts nor private archive revision changed.
        let changed = store.progressDashboardRequest(filters: .unfiltered, clock: clock)
        XCTAssertNotEqual(key.reloadID, changed.reloadID)
        XCTAssertEqual(key.archiveRevision, changed.archiveRevision)
        XCTAssertEqual(key.clock, changed.clock)
        XCTAssertEqual(store.sessionCheckpoints.filter { $0.sessionID == record.sessionID && $0.isComplete }.count, 1)
        XCTAssertEqual(try NFEditorialCanonicalData.encode(store.attempts.map(NFImmutableAttemptRecordSnapshot.init)), attemptBytes)
        XCTAssertEqual(try NFEditorialCanonicalData.encode(store.localSessions.archive), archiveBytes)
        XCTAssertEqual(initial.engagement?.completions.first?.isComplete, false,
            "Capturing a worker value must not retain the mutable checkpoint model")
        await projection.update(store.progressDashboardInput(filters: .unfiltered, clock: clock))
        XCTAssertEqual(projection.snapshot?.forge?.totalXP, 35)
        XCTAssertEqual(projection.snapshot?.forge?.completionXP, 25)
        XCTAssertEqual(projection.snapshot?.forge?.rewardedSessionCount, 1)
        probe.release(); await stale.value
        XCTAssertTrue(probe.ranOffMain)
        XCTAssertEqual(projection.snapshot?.forge?.totalXP, 35, "Late pre-completion work cannot erase earned engagement")
        XCTAssertEqual(projection.snapshot?.forge?.milestones.first { $0.code == .firstCompletedSession }?.evidenceSessionIDs,
            [record.sessionID])
    }

    @MainActor
    func testDashboardEngagementStaysAllTimeWhileMathUsesFilteredEffectiveHistory() async throws {
        let (store, container) = try makeStore()
        defer { withExtendedLifetime(container) {} }
        XCTAssertFalse(store.allowsSharedWidgetPublishing)
        let now = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-09-05T12:00:00Z"))
        let utc = calendar(timeZoneID: "UTC")
        func row(_ key: String, _ lab: TrainingLab, _ day: Int, _ correct: Bool,
            _ evidence: EvidenceClass = .practice) -> AttemptRecord {
            makeAttempt(id: key, lab: lab, correct: correct, confidence: .certain,
                date: now.addingTimeInterval(Double(day) * 86_400 - 5), evidenceClass: evidence)
        }
        let recent = (0..<5).map { row("QA.math.recent.\($0)", .mentalMath, 0, true) }
        let older = (0..<5).map { row("QA.math.older.\($0)", .mentalMath, -10, false) }
        let quantitative = row("QA.quantitative", .quantitative, -2, true)
        let source = row("QA.source", .mentalMath, -3, false, .documentPractice)
        source.responseFormatRaw = "selfCheck"; source.evidenceWeight = 0
        let protected = row("QA.protected", .mentalMath, -4, false, .assessmentHoldout)
        protected.sessionSourceRaw = SessionSource.baseline.rawValue
        let withdrawn = row("QA.withdrawn", .mentalMath, -1, false)
        let skipped = row("QA.skipped", .mentalMath, -5, false); skipped.wasSkipped = true
        let rows = recent + older + [quantitative, source, protected, withdrawn, skipped]
        for record in rows { store.context.insert(record) }
        try store.context.save(); store.reload()
        try store.localSessions.appendDispositions([.init(id: "QA.dashboard.withdrawal", attemptID: withdrawn.id.uuidString,
            revision: 100, policyVersion: NFHistoricalPracticeProjection.policyVersion, occurredAt: now,
            disposition: .excludedContentCorrection, reason: "Synthetic withdrawal preserves raw engagement only.",
            correctedDerivedCredit: nil, supersedesDispositionID: nil)])
        let rawBefore = try NFEditorialCanonicalData.encode(rows.map(NFImmutableAttemptRecordSnapshot.init))
        let archiveBefore = try NFEditorialCanonicalData.encode(store.localSessions.archive)
        let clock = NFProgressDashboardClock(capturedAt: now, calendar: utc)
        let all = store.progressDashboardInput(filters: .unfiltered, clock: clock)
        let filtered = store.progressDashboardInput(filters: .init(period: .currentWeek, lab: .mentalMath), clock: clock)
        XCTAssertEqual(all.engagement?.activities.count, 15)
        XCTAssertEqual(filtered.engagement?.activities.count, 15)
        XCTAssertEqual(Set(filtered.mentalMathInputs.map { $0.attempt.id }), Set((recent + [protected, withdrawn, skipped]).map(\.id)))
        XCTAssertEqual(filtered.mentalMathInputs.first { $0.attempt.id == protected.id }?.isProtected, true)
        XCTAssertEqual(filtered.mentalMathInputs.first { $0.attempt.id == withdrawn.id }?.attempt.evidenceWeight, 0)
        XCTAssertTrue(all.effectiveAttempts.compactMap(\.editorialObservation).isEmpty,
            "Legacy/raw engagement does not grant reviewed provenance")
        let projection = NFProgressDashboardProjection()
        await projection.update(all)
        let allResult = try XCTUnwrap(projection.snapshot)
        let probe = NFDashboardWorkerProbe(); defer { probe.release() }
        let work = Task { await projection.update(filtered) { input in
            probe.hold(); return try NFProgressDashboardReducer.make(input)
        } }
        let held = await probe.waitUntilHeld(); XCTAssertTrue(held)
        XCTAssertTrue(Thread.isMainThread); XCTAssertTrue(projection.isLoading)
        probe.release(); await work.value
        let filteredResult = try XCTUnwrap(projection.snapshot)
        XCTAssertTrue(probe.ranOffMain)
        XCTAssertEqual(filteredResult.forge, allResult.forge)
        XCTAssertEqual(filteredResult.consistency, allResult.consistency)
        XCTAssertEqual(filteredResult.forge?.totalXP, 140, "Source, protected and withdrawn raw engagement still count; skipped does not")
        XCTAssertEqual(filteredResult.forge?.eligibleAttemptCount, 14)
        XCTAssertEqual(filteredResult.consistency?.activeDaysInWindow, 5,
            "All-time standardized raw activity retains days outside the selected math filter")
        XCTAssertEqual(allResult.mentalMathMetrics[.independentAccuracy]?.sampleCount, 10)
        XCTAssertEqual(allResult.mentalMathMetrics[.independentAccuracy]?.value, 0.5)
        XCTAssertEqual(filteredResult.mentalMathMetrics[.independentAccuracy]?.sampleCount, 5)
        XCTAssertEqual(filteredResult.mentalMathMetrics[.independentAccuracy]?.value, 1)
        for kind in [NFMentalMathMetricKind.retrievalFluency, .strategyFlexibility, .retention, .transfer] {
            XCTAssertNil(filteredResult.mentalMathMetrics[kind]?.value, "Legacy records cannot invent reviewed conditions")
        }
        XCTAssertEqual(try NFEditorialCanonicalData.encode(rows.map(NFImmutableAttemptRecordSnapshot.init)), rawBefore)
        XCTAssertEqual(try NFEditorialCanonicalData.encode(store.localSessions.archive), archiveBefore)
    }

    @MainActor
    func testDashboardTenThousandActualRowsCaptureImmutableEngagementAndMathOffMain() async throws {
        let (store, container) = try makeStore()
        defer { withExtendedLifetime(container) {} }
        XCTAssertFalse(store.allowsSharedWidgetPublishing)
        let now = Date(timeIntervalSince1970: 1_785_000_000)
        let sessionID = UUID(uuidString: "E0110000-0000-4000-8000-000000000001")!
        var rows: [AttemptRecord] = []
        for index in 0..<10_000 {
            let record = makeAttempt(id: "QA.dashboard.large.\(index)", lab: .mentalMath,
                correct: index.isMultiple(of: 2), confidence: .certain,
                date: now.addingTimeInterval(-Double(index + 1)))
            record.id = UUID(uuidString: String(format: "E0120000-0000-4000-8000-%012d", index))!
            record.sessionID = sessionID
            store.context.insert(record); rows.append(record)
        }
        try store.context.save(); store.reload()
        try store.upsertCheckpoint(sessionID: sessionID,
            request: .init(lab: .mentalMath, source: .focused, seed: 88, requestedItemCount: 1),
            currentIndex: 0, itemCount: 1, response: "Saved completion", scratchpad: "", results: [true],
            hasCommittedCurrentItem: true, isComplete: true)
        let clock = NFProgressDashboardClock(capturedAt: now, calendar: calendar(timeZoneID: "UTC"))
        let input = store.progressDashboardInput(filters: .unfiltered, clock: clock)
        XCTAssertEqual(input.engagement?.activities.count, 10_000)
        XCTAssertEqual(input.mentalMathInputs.count, 10_000)
        let archive = try NFEditorialCanonicalData.encode(store.localSessions.archive)
        let original = try NFEditorialCanonicalData.encode(rows.map(NFImmutableAttemptRecordSnapshot.init))
        let projection = NFProgressDashboardProjection(), probe = NFDashboardWorkerProbe()
        defer { probe.release() }
        let work = Task { await projection.update(input) { value in
            probe.hold(); return try NFProgressDashboardReducer.make(value)
        } }
        let held = await probe.waitUntilHeld(); XCTAssertTrue(held)
        // Real SwiftData changes after capture cannot mutate any worker input.
        let mutated = try XCTUnwrap(rows.first)
        mutated.wasSkipped = true
        XCTAssertEqual(input.engagement?.activities.first { $0.id == mutated.id }?.wasSkipped, false)
        XCTAssertEqual(input.mentalMathInputs.first { $0.attempt.id == mutated.id }?.originalRecord?.wasSkipped, false)
        store.context.rollback()
        XCTAssertTrue(Thread.isMainThread); XCTAssertTrue(projection.isLoading); XCTAssertNil(projection.snapshot)
        probe.release(); await work.value
        XCTAssertTrue(probe.ranOffMain)
        let result = try XCTUnwrap(projection.snapshot)
        XCTAssertEqual(result.totalEvidence, 10_000)
        XCTAssertEqual(result.forge?.eligibleAttemptCount, 10_000)
        XCTAssertEqual(result.forge?.totalXP, 100_025)
        XCTAssertEqual(result.forge?.rewardedSessionCount, 1)
        XCTAssertEqual(result.mentalMathMetrics[.independentAccuracy]?.sampleCount, 10_000)
        XCTAssertEqual(result.mentalMathMetrics[.independentAccuracy]?.value, 0.5)
        XCTAssertEqual(Set(result.weeklyPoints.flatMap(\.attemptIDs)), Set(rows.map(\.id)))
        XCTAssertEqual(try NFEditorialCanonicalData.encode(rows.map(NFImmutableAttemptRecordSnapshot.init)), original)
        XCTAssertEqual(try NFEditorialCanonicalData.encode(store.localSessions.archive), archive)
    }
}

import Foundation
#if canImport(WidgetKit)
import WidgetKit
#endif

@MainActor
extension AppStore {
    func publishWidgetSnapshot(
        at date: Date = .now,
        calendar: Calendar = .current
    ) {
        guard isOnboardingComplete else {
            if allowsSharedWidgetPublishing { NFWidgetSnapshotStore.delete() }
            return
        }

        // Keep widget materialization in the caller's learner-day context.
        // Profile updates can intentionally evaluate a non-current boundary
        // (including travel and tests); falling back to Date.now/Calendar.current
        // here would create a second canonical plan as a publishing side effect.
        let plan = dailyPlan(at: date, calendar: calendar)
        let language = NFWidgetLanguage(
            localeIdentifier: profile?.preferredLanguageCode
                ?? NFAppLocalization.preferredLanguageCode
        )
        let completedBlockIDs = completedPlanBlockIDs(planID: plan.id)
        var expectedTotal = 0
        let blocks = plan.blocks.map { block in
            let expected = max(1, min(12, block.minutes / 2))
            expectedTotal += expected
            return NFWidgetBlockSnapshot(
                title: genericWidgetTitle(
                    for: block.evidenceClass,
                    locale: language.locale
                ),
                minutes: block.minutes,
                isComplete: completedBlockIDs.contains(block.id)
            )
        }
        let reviewsDue = plan.blocks.filter { $0.evidenceClass == .retention }.count
        let snapshot = NFWidgetSnapshot(
            schemaVersion: NFWidgetSnapshot.schemaVersion,
            language: language,
            generatedAt: date,
            localDayKey: plan.localDayKey,
            scheduledMinutes: plan.minutes,
            completedItems: expectedTotal == 0 ? 0 : min(todayAttemptCount, expectedTotal),
            expectedItems: expectedTotal,
            reviewsDue: reviewsDue,
            blocks: blocks
        )

        do {
            guard allowsSharedWidgetPublishing else { return }
            try NFWidgetSnapshotStore.write(snapshot)
            #if canImport(WidgetKit)
            WidgetCenter.shared.reloadTimelines(ofKind: "NeuroForgeToday")
            #endif
        } catch {
            lastErrorMessage = NFAppLocalization.localized("Today’s widget snapshot could not be refreshed; the app’s training data is unaffected.", locale: NFAppLocalization.preferredLocale, comment: "Non-destructive widget refresh error shown inside the app.")
        }
    }

    private func genericWidgetTitle(
        for evidenceClass: EvidenceClass,
        locale: Locale
    ) -> String {
        switch evidenceClass {
        case .practice: NFAppLocalization.localized("Practice", locale: locale, comment: "Privacy-safe generic widget block title.")
        case .nearTransfer, .appliedTransfer: NFAppLocalization.localized("Transfer", locale: locale, comment: "Privacy-safe generic widget block title for applying a skill in another context.")
        case .retention: NFAppLocalization.localized("Review", locale: locale, comment: "Privacy-safe generic widget block title for delayed recall.")
        case .assessmentHoldout: NFAppLocalization.localized("Assessment", locale: locale, comment: "Privacy-safe generic widget block title.")
        case .documentPractice: NFAppLocalization.localized("Source review", locale: locale, comment: "Privacy-safe generic widget block title for review from a personal source.")
        }
    }
}

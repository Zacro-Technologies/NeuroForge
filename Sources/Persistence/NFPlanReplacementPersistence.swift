import Foundation

@MainActor
extension AppStore {
    func canReplaceTodayPlanBlock(_ blockID: String) -> Bool {
        let plan = todayPlan
        guard let canonical = dailyPlans.first(where: { $0.id == plan.id })?.snapshot,
              canonical.replacement == nil,
              canonical.blocks.contains(where: { $0.id == blockID }) else {
            return false
        }
        return !sessionCheckpoints.contains {
            $0.planID == plan.id && $0.planBlockID == blockID
        }
    }

    @discardableResult
    func replaceTodayPlanBlock(
        _ blockID: String,
        reason: NFPlanReplacementReason
    ) -> PlanBlock? {
        let plan = todayPlan
        guard let record = dailyPlans.first(where: { $0.id == plan.id }),
              let canonical = record.snapshot else {
            notice = AppNotice(
                title: NFAppLocalization.localized("Plan not changed", locale: NFAppLocalization.preferredLocale, comment: "Daily-plan replacement failure title."),
                message: NFAppLocalization.localized("Today’s saved plan could not be loaded. Your existing plan remains intact.", locale: NFAppLocalization.preferredLocale, comment: "Daily-plan replacement failure when the saved plan is unavailable.")
            )
            return nil
        }
        guard canReplaceTodayPlanBlock(blockID) else {
            notice = AppNotice(
                title: NFAppLocalization.localized("Replacement unavailable", locale: NFAppLocalization.preferredLocale, comment: "Daily-plan replacement unavailable title."),
                message: NFAppLocalization.localized("A block can be replaced only before it starts, and only once per daily plan.", locale: NFAppLocalization.preferredLocale, comment: "Daily-plan replacement eligibility explanation.")
            )
            return nil
        }

        do {
            let updated = try NFDailyScheduler.replacingBlock(
                in: canonical,
                blockID: blockID,
                reason: reason
            )
            let previousPayload = record.payload
            let updatedPayload = try JSONEncoder().encode(updated)
            record.payload = updatedPayload
            try context.save()
            let previousBlock = canonical.blocks.first(where: { $0.id == blockID })
            let replacementBlock = updated.blocks.first {
                $0.id == updated.replacement?.replacementBlockID
            }
            do {
                try appendAdaptivePlanHistory(NFAdaptivePlanChangeRecord(
                    profileID: canonical.profileID,
                    kind: .planReplaced,
                    title: NFAppLocalization.localized(
                        "Daily-plan block replaced",
                        locale: NFAppLocalization.preferredLocale,
                        comment: "Adaptive-plan history block-replacement event title."
                    ),
                    previousState: previousBlock?.title,
                    newState: replacementBlock?.title ?? NFAppLocalization.localized(
                        "Replacement block",
                        locale: NFAppLocalization.preferredLocale,
                        comment: "Fallback adaptive-plan replacement block name."
                    ),
                    reason: NFAppLocalization.localized(
                        "You chose \(reason.title). The replacement was selected from the persisted choice and keeps today’s scheduled duration unchanged.",
                        locale: NFAppLocalization.preferredLocale,
                        comment: "Adaptive-plan history block-replacement explanation; the placeholder is the learner-selected reason."
                    ),
                    undoPayload: .dailyPlan(
                        planID: canonical.id,
                        expectedCurrentPayload: updatedPayload,
                        previousPayload: previousPayload
                    )
                ))
            } catch {
                // A changed plan without its promised explanation would be
                // unauditable. Restore the previously committed payload and
                // fail the user action as one logical transaction.
                record.payload = previousPayload
                try context.save()
                reload()
                notice = AppNotice(
                    title: NFAppLocalization.localized(
                        "Plan not changed",
                        locale: NFAppLocalization.preferredLocale,
                        comment: "Plan-replacement failure title."
                    ),
                    message: (error as? LocalizedError)?.errorDescription
                        ?? NFAppLocalization.localized(
                            "The change explanation could not be saved, so the original block was restored.",
                            locale: NFAppLocalization.preferredLocale,
                            comment: "Plan-replacement rollback explanation when its audit event cannot persist."
                        )
                )
                return nil
            }
            reload()
            publishWidgetSnapshot()
            notice = AppNotice(
                title: NFAppLocalization.localized("Block replaced", locale: NFAppLocalization.preferredLocale, comment: "Daily-plan replacement success title."),
                message: NFAppLocalization.localized("The alternative keeps today’s duration at \(NFAppLocalization.formattedMinutes(updated.scheduledMinutes)). Historical evidence was not changed.",
                    locale: NFAppLocalization.preferredLocale,
                    comment: "Plan-replacement confirmation; the placeholder is a localized duration."
                )
            )
            return updated.domainPlan.blocks.first {
                $0.id == updated.replacement?.replacementBlockID
            }
        } catch {
            context.rollback()
            reload()
            notice = AppNotice(
                title: NFAppLocalization.localized("Plan not changed", locale: NFAppLocalization.preferredLocale, comment: "Daily-plan replacement failure title."),
                message: (error as? LocalizedError)?.errorDescription
                    ?? NFAppLocalization.localized("The replacement could not be saved. Your existing plan remains intact.", locale: NFAppLocalization.preferredLocale, comment: "Daily-plan replacement persistence failure explanation.")
            )
            return nil
        }
    }
}

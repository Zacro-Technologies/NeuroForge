import Foundation

/// The exact proposed plan and its original persisted bytes travel together.
/// Looking at this value never changes the saved plan or consumes a replacement.
struct NFPlanReplacementPreview: Identifiable, Equatable, Sendable {
    let originalPayload: Data
    let originalPlan: NFCanonicalDailyPlan
    let proposedPlan: NFCanonicalDailyPlan
    let originalBlock: NFDailyPlanBlock
    let replacementBlock: NFDailyPlanBlock
    var id: String { replacementBlock.id }
}

@MainActor
extension AppStore {
    /// Read-only lookup: previewing may neither materialize a new learner day
    /// nor write travel metadata as the ordinary Today getter can do.
    private func savedReplacementPlanRecord(_ blockID: String, at date: Date = .now) -> DailyPlanRecord? {
        let snapshot = profileSnapshot
        let boundary = NFPlanBoundaryContext.make(at: date, dayBoundaryHour: snapshot.dayBoundaryHour, calendar: .current)
        let dayKey = NFDailyScheduler.localDayKey(for: date, dayBoundaryHour: snapshot.dayBoundaryHour, calendar: .current)
        return dailyPlans.first { record in
            guard record.profileID == snapshot.id,
                  record.dayBoundaryHour == boundary.dayBoundaryHour,
                  record.snapshot?.blocks.contains(where: { $0.id == blockID }) == true else { return false }
            let matches = record.timeZoneIdentifier == boundary.timeZoneIdentifier
                && record.utcOffsetSeconds == boundary.utcOffsetSeconds
            return (matches && (record.localDayKey == dayKey || (record.travelPreservedUntil ?? .distantPast) > date))
                || NFPlanTravelPolicy.canPreserve(planCreatedAt: record.createdAt, at: date,
                    storedTimeZoneIdentifier: record.timeZoneIdentifier, storedUTCOffsetSeconds: record.utcOffsetSeconds,
                    newContext: boundary)
        }
    }

    func canReplaceTodayPlanBlock(_ blockID: String, at date: Date = .now) -> Bool {
        guard let record = savedReplacementPlanRecord(blockID, at: date), let canonical = record.snapshot,
              NFDailyScheduler.supportsFrozenPlanPolicy(canonical.policyVersion), canonical.replacement == nil else { return false }
        guard !sessionCheckpoints.contains(where: { $0.planID == canonical.id && $0.planBlockID == blockID }),
              !localSessions.archive.sessions.contains(where: { $0.request.planID == canonical.id && $0.request.planBlockID == blockID }),
              !(activeSessionRequest.map { $0.planID == canonical.id && $0.planBlockID == blockID } ?? false),
              !attempts.contains(where: { $0.planID == canonical.id && $0.planBlockID == blockID }) else { return false }
        return true
    }

    func previewTodayPlanBlockReplacement(_ blockID: String, reason: NFPlanReplacementReason,
                                         at date: Date = .now) throws -> NFPlanReplacementPreview {
        guard canReplaceTodayPlanBlock(blockID, at: date),
              let record = savedReplacementPlanRecord(blockID, at: date),
              let canonical = record.snapshot,
              let original = canonical.blocks.first(where: { $0.id == blockID }) else {
            throw NFPlanReplacementError.blockNotFound
        }
        let proposed = try NFDailyScheduler.replacingBlock(in: canonical, blockID: blockID, reason: reason, at: date)
        guard let replacement = proposed.blocks.first(where: { $0.id == proposed.replacement?.replacementBlockID }) else {
            throw NFPlanReplacementError.noAccessibleAlternative
        }
        return .init(originalPayload: record.payload, originalPlan: canonical, proposedPlan: proposed,
            originalBlock: original, replacementBlock: replacement)
    }

    @discardableResult
    func replaceTodayPlanBlock(
        _ blockID: String,
        reason: NFPlanReplacementReason,
        preview: NFPlanReplacementPreview? = nil
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
            if let preview {
                guard preview.originalPayload == record.payload,
                      preview.originalPlan == canonical,
                      preview.originalBlock.id == blockID,
                      preview.proposedPlan.replacement?.reason == reason else {
                    throw NFPlanReplacementError.stalePreview
                }
            }
            let updated = try NFDailyScheduler.replacingBlock(
                in: canonical, blockID: blockID, reason: reason,
                at: preview?.proposedPlan.replacement?.replacedAt ?? .now
            )
            guard preview.map({ $0.proposedPlan == updated }) ?? true else {
                throw NFPlanReplacementError.stalePreview
            }
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

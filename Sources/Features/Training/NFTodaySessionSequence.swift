import Foundation
import Observation

/// In-memory orchestration for one deliberate pass through today's immutable
/// plan. The canonical plan and every completed block remain durable in
/// SwiftData; this queue only remembers how many of the remaining blocks the
/// learner chose on the session-intro screen. Losing it never loses evidence.
@MainActor
@Observable
final class NFTodaySessionSequence {
    private var activePlanID: String?
    private var queuedBlockIDs: [String] = []

    init() {}

    func start(
        plan: DailyPlan,
        blockIDs: [String],
        store: AppStore,
        at date: Date = Date(),
        calendar: Calendar = .current
    ) -> Bool {
        guard store.activeSessionRequest == nil else { return false }
        let plan = store.reviewExecutionPlan(plan, at: date, calendar: calendar)
        let completed = store.completedPlanBlockIDs(planID: plan.id)
        let availableIDs = Set(plan.blocks.map(\.id))
        let normalized = blockIDs.filter {
            availableIDs.contains($0) && !completed.contains($0)
        }
        guard let firstID = normalized.first,
              let first = plan.blocks.first(where: { $0.id == firstID }) else {
            return false
        }
        activePlanID = plan.id
        queuedBlockIDs = normalized
        let started = begin(first, plan: plan, store: store, at: date, calendar: calendar)
        if !started { clear() }
        return started
    }

    func nextBlock(
        after blockID: String?,
        planID: String?,
        store: AppStore,
        at date: Date = Date(),
        calendar: Calendar = .current
    ) -> PlanBlock? {
        guard let blockID,
              let planID,
              activePlanID == planID,
              let currentIndex = queuedBlockIDs.firstIndex(of: blockID) else {
            return nil
        }
        let completed = store.completedPlanBlockIDs(planID: planID)
        let candidates = queuedBlockIDs.dropFirst(currentIndex + 1)
        let plan = store.reviewExecutionPlan(store.todayPlan, at: date, calendar: calendar)
        return candidates.lazy
            .filter { !completed.contains($0) }
            .compactMap { candidateID in
                plan.blocks.first(where: { $0.id == candidateID })
            }
            .first
    }

    /// Advances without exposing a transient nil active request to SwiftUI.
    /// AppRoot keys the session view by request ID, so the next block receives
    /// a fresh runtime while the containing sheet remains continuous.
    func advance(
        after blockID: String?,
        planID: String?,
        store: AppStore
    ) -> Bool {
        guard let next = nextBlock(
            after: blockID,
            planID: planID,
            store: store
        ), let planID else {
            clear()
            return false
        }
        let plan = store.todayPlan
        guard plan.id == planID else {
            clear()
            return false
        }
        store.activeSessionRequest = nil
        return begin(next, plan: plan, store: store)
    }

    func clear() {
        activePlanID = nil
        queuedBlockIDs = []
    }

    private func begin(_ block: PlanBlock, plan: DailyPlan, store: AppStore,
                       at date: Date = Date(), calendar: Calendar = .current) -> Bool {
        let transferBrief = dailyTransferBrief(for: block, in: plan)
        let targets = store.retentionReviewTargets(forPlanID: plan.id, blockID: block.id,
            fallbackItemIDs: block.retentionItemIDs, fallbackSeed: plan.seed)
        return store.beginSession(
            lab: block.lab,
            source: .today,
            requestedMinutes: block.minutes,
            evidenceClass: block.evidenceClass,
            topic: block.mechanicID,
            requestedItemCount: block.evidenceClass == .retention ? block.retentionItemIDs.count : nil,
            planID: plan.id,
            planBlockID: block.id,
            isTimed: block.timed,
            mechanicID: block.mechanicID,
            retentionItemIDs: block.retentionItemIDs,
            retentionTargets: targets,
            transferBrief: transferBrief,
            reviewSchedulingDate: date, reviewSchedulingCalendar: calendar
        )
    }

    /// Daily transfer changes representation while preserving the scheduler's
    /// selected source skill. Transfer itself is an evidence layer, never the
    /// source skill to be transferred.
    private func dailyTransferBrief(
        for block: PlanBlock,
        in plan: DailyPlan
    ) -> NFExerciseTransferBrief? {
        guard block.kindRaw == NFDailyPlanBlockKind.unseenTransfer.rawValue else {
            return nil
        }
        let sourceSkillID = [block.targetSkillID]
            .compactMap { $0 }
            .first(where: { $0 != TrainingLab.transfer.skillID })
            ?? plan.blocks.lazy
                .compactMap(\.targetSkillID)
                .first(where: { $0 != TrainingLab.transfer.skillID })
        guard let sourceSkillID,
              let sourceLab = TrainingLab.allCases.first(where: {
                  $0 != .transfer && $0.skillID == sourceSkillID
              }) else {
            return nil
        }
        return NFExerciseTransferBrief(
            missionID: block.id,
            seed: plan.seed,
            kind: .multiRepresentationTransform,
            labs: [sourceLab],
            skillIDs: [sourceSkillID],
            requiredDimensions: ["representation"]
        )
    }
}

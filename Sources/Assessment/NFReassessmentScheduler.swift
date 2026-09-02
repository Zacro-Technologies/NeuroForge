import Foundation

struct NFReassessmentState: Codable, Equatable, Sendable {
    let completedCycle: Int
    let activeDayAnchor: Date?
    let dueAt: Date?
    let deferredUntil: Date?
    let targetBlock: NFAssessmentBlockKind?
    let lastCompletedAt: Date?
    let lastCompletedBlock: NFAssessmentBlockKind?

    init(
        completedCycle: Int = 0,
        activeDayAnchor: Date? = nil,
        dueAt: Date? = nil,
        deferredUntil: Date? = nil,
        targetBlock: NFAssessmentBlockKind? = nil,
        lastCompletedAt: Date? = nil,
        lastCompletedBlock: NFAssessmentBlockKind? = nil
    ) {
        self.completedCycle = max(0, completedCycle)
        self.activeDayAnchor = activeDayAnchor
        self.dueAt = dueAt
        self.deferredUntil = deferredUntil
        self.targetBlock = targetBlock
        self.lastCompletedAt = lastCompletedAt
        self.lastCompletedBlock = lastCompletedBlock
    }
}

struct NFReassessmentStatus: Equatable, Sendable {
    let cycle: Int
    let block: NFAssessmentBlockKind?
    let activeDayAnchor: Date
    let activeDaysCompleted: Int
    let dueAt: Date?
    let deferredUntil: Date?
    let isDeferred: Bool

    var activeDaysRequired: Int { NFReassessmentScheduler.activeDaysRequired }
    var activeDaysRemaining: Int { max(0, activeDaysRequired - activeDaysCompleted) }
    var isDue: Bool { dueAt != nil && !isDeferred && block != nil }
    var canDefer: Bool { isDue && deferredUntil == nil }
}

struct NFReassessmentScheduleResult: Equatable, Sendable {
    let state: NFReassessmentState
    let status: NFReassessmentStatus?
}

enum NFReassessmentScheduler {
    static let activeDaysRequired = 28
    static let deferralDuration: TimeInterval = 7 * 24 * 60 * 60

    static func reconcile(
        state: NFReassessmentState,
        baselineEvidenceDates: [NFAssessmentBlockKind: Date],
        completedReassessmentDates: [NFAssessmentBlockKind: Date],
        activeDates: [Date],
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> NFReassessmentScheduleResult {
        guard !baselineEvidenceDates.isEmpty else {
            return NFReassessmentScheduleResult(state: state, status: nil)
        }

        let initialAnchor = baselineEvidenceDates.values.min()
        guard let anchor = state.activeDayAnchor ?? initialAnchor else {
            return NFReassessmentScheduleResult(state: state, status: nil)
        }
        let anchorDay = calendar.startOfDay(for: anchor)
        let today = calendar.startOfDay(for: now)
        let activeDays = Set(activeDates.map { calendar.startOfDay(for: $0) })
            .filter { $0 > anchorDay && $0 <= today }
            .sorted()

        var dueAt = state.dueAt
        if dueAt == nil, activeDays.count >= activeDaysRequired {
            dueAt = activeDays[activeDaysRequired - 1]
        }

        let eligibleBlocks = Set(baselineEvidenceDates.keys)
        var targetBlock = state.targetBlock.flatMap { eligibleBlocks.contains($0) ? $0 : nil }
        if dueAt != nil, targetBlock == nil {
            targetBlock = eligibleBlocks.sorted { lhs, rhs in
                let lhsDate = completedReassessmentDates[lhs] ?? baselineEvidenceDates[lhs] ?? .distantPast
                let rhsDate = completedReassessmentDates[rhs] ?? baselineEvidenceDates[rhs] ?? .distantPast
                if lhsDate != rhsDate { return lhsDate < rhsDate }
                return blockOrdinal(lhs) < blockOrdinal(rhs)
            }.first
        }

        let reconciled = NFReassessmentState(
            completedCycle: state.completedCycle,
            activeDayAnchor: anchor,
            dueAt: dueAt,
            deferredUntil: state.deferredUntil,
            targetBlock: targetBlock,
            lastCompletedAt: state.lastCompletedAt,
            lastCompletedBlock: state.lastCompletedBlock
        )
        let isDeferred = state.deferredUntil.map { $0 > now } ?? false
        let status = NFReassessmentStatus(
            cycle: state.completedCycle + 1,
            block: targetBlock,
            activeDayAnchor: anchor,
            activeDaysCompleted: min(activeDaysRequired, activeDays.count),
            dueAt: dueAt,
            deferredUntil: state.deferredUntil,
            isDeferred: isDeferred
        )
        return NFReassessmentScheduleResult(state: reconciled, status: status)
    }

    static func deferring(_ state: NFReassessmentState, at date: Date) -> NFReassessmentState? {
        guard state.dueAt != nil, state.targetBlock != nil, state.deferredUntil == nil else { return nil }
        return NFReassessmentState(
            completedCycle: state.completedCycle,
            activeDayAnchor: state.activeDayAnchor,
            dueAt: state.dueAt,
            deferredUntil: date.addingTimeInterval(deferralDuration),
            targetBlock: state.targetBlock,
            lastCompletedAt: state.lastCompletedAt,
            lastCompletedBlock: state.lastCompletedBlock
        )
    }

    static func completing(
        _ state: NFReassessmentState,
        cycle: Int,
        block: NFAssessmentBlockKind,
        at date: Date
    ) -> NFReassessmentState? {
        guard cycle == state.completedCycle + 1,
              block == state.targetBlock,
              state.dueAt != nil else { return nil }
        return NFReassessmentState(
            completedCycle: cycle,
            activeDayAnchor: date,
            dueAt: nil,
            deferredUntil: nil,
            targetBlock: nil,
            lastCompletedAt: date,
            lastCompletedBlock: block
        )
    }

    private static func blockOrdinal(_ block: NFAssessmentBlockKind) -> Int {
        NFAssessmentBlockKind.allCases.firstIndex(of: block) ?? .max
    }
}

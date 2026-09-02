import Foundation

// MARK: - Scheduling inputs and auditable priority

struct NFDailySchedulingSnapshot: Sendable {
    let profile: ProfileSnapshot
    let date: Date
    let dayBoundaryHour: Int
    let skillSummaries: [SkillSummary]
    let attempts: [AttemptDTO]
    let retentionStates: [NFRetentionItemState]
    let accessibilityExcludedLabs: Set<TrainingLab>
    let readiness: Readiness
    /// Mental-math timing is a learned eligibility gate, not a general timing
    /// preference. The durable attempt reducer supplies this independently of
    /// readiness and the user's global timing mode.
    let mentalMathTimingEligible: Bool

    init(
        profile: ProfileSnapshot,
        date: Date,
        dayBoundaryHour: Int = 0,
        skillSummaries: [SkillSummary] = [],
        attempts: [AttemptDTO] = [],
        retentionStates: [NFRetentionItemState] = [],
        accessibilityExcludedLabs: Set<TrainingLab> = [],
        readiness: Readiness = .normal,
        mentalMathTimingEligible: Bool = false
    ) {
        self.profile = profile
        self.date = date
        self.dayBoundaryHour = min(12, max(0, dayBoundaryHour))
        self.skillSummaries = skillSummaries
        self.attempts = attempts
        self.retentionStates = retentionStates
        self.accessibilityExcludedLabs = accessibilityExcludedLabs
        self.readiness = readiness
        self.mentalMathTimingEligible = mentalMathTimingEligible
    }
}

struct NFSchedulingScoreBreakdown: Codable, Equatable, Sendable, Identifiable {
    let skillID: String
    let lab: TrainingLab
    let normalizedGoalWeight: Double
    let reviewUrgency: Double
    let weaknessRelativeToGoal: Double
    let estimateUncertainty: Double
    let transferGap: Double
    let varietyNeed: Double
    let recentLoadPenalty: Double
    let accessibilityPenalty: Double
    let totalPriority: Double
    let reasons: [PrescriptionReason]

    var id: String { skillID }
}

// MARK: - Immutable plan

enum NFDailyPlanBlockKind: String, Codable, CaseIterable, Sendable {
    case retentionReview
    case targetPractice
    case unseenTransfer
    case confidenceReflection
}

struct NFDailyPlanBlock: Codable, Equatable, Sendable, Identifiable {
    let id: String
    let kind: NFDailyPlanBlockKind
    let lab: TrainingLab
    let targetSkillID: String
    let title: String
    let detail: String
    let minutes: Int
    let reasons: [PrescriptionReason]
    let evidenceClass: EvidenceClass
    let priority: NFSchedulingScoreBreakdown?
    let mechanicID: String
    let timed: Bool
    let offlineReady: Bool
    let retentionItemIDs: [String]
    let retentionTargets: [NFRetentionReviewTarget]

    init(
        id: String,
        kind: NFDailyPlanBlockKind,
        lab: TrainingLab,
        targetSkillID: String,
        title: String,
        detail: String,
        minutes: Int,
        reasons: [PrescriptionReason],
        evidenceClass: EvidenceClass,
        priority: NFSchedulingScoreBreakdown?,
        mechanicID: String,
        timed: Bool,
        offlineReady: Bool,
        retentionItemIDs: [String],
        retentionTargets: [NFRetentionReviewTarget] = []
    ) {
        self.id = id
        self.kind = kind
        self.lab = lab
        self.targetSkillID = targetSkillID
        self.title = title
        self.detail = detail
        self.minutes = minutes
        self.reasons = reasons
        self.evidenceClass = evidenceClass
        self.priority = priority
        self.mechanicID = mechanicID
        self.timed = timed
        self.offlineReady = offlineReady
        self.retentionItemIDs = retentionItemIDs
        self.retentionTargets = retentionTargets
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case kind
        case lab
        case targetSkillID
        case title
        case detail
        case minutes
        case reasons
        case evidenceClass
        case priority
        case mechanicID
        case timed
        case offlineReady
        case retentionItemIDs
        case retentionTargets
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        kind = try container.decode(NFDailyPlanBlockKind.self, forKey: .kind)
        lab = try container.decode(TrainingLab.self, forKey: .lab)
        targetSkillID = try container.decode(String.self, forKey: .targetSkillID)
        title = try container.decode(String.self, forKey: .title)
        detail = try container.decode(String.self, forKey: .detail)
        minutes = try container.decode(Int.self, forKey: .minutes)
        reasons = try container.decode([PrescriptionReason].self, forKey: .reasons)
        evidenceClass = try container.decode(EvidenceClass.self, forKey: .evidenceClass)
        priority = try container.decodeIfPresent(NFSchedulingScoreBreakdown.self, forKey: .priority)
        mechanicID = try container.decode(String.self, forKey: .mechanicID)
        timed = try container.decode(Bool.self, forKey: .timed)
        offlineReady = try container.decode(Bool.self, forKey: .offlineReady)
        retentionItemIDs = try container.decodeIfPresent([String].self, forKey: .retentionItemIDs) ?? []
        retentionTargets = try container.decodeIfPresent(
            [NFRetentionReviewTarget].self,
            forKey: .retentionTargets
        ) ?? retentionItemIDs.map { .legacy(memoryItemID: $0) }
    }
}

enum NFPlanReplacementReason: String, Codable, CaseIterable, Identifiable, Sendable {
    case lowerEnergy
    case accessibility
    case needVariety
    case notRelevantToday

    var id: String { rawValue }

    var title: String {
        switch self {
        case .lowerEnergy: NFAppLocalization.localized("Lower energy", locale: NFAppLocalization.preferredLocale, comment: "User-selected reason for replacing one daily-plan block.")
        case .accessibility: NFAppLocalization.localized("Accessibility need", locale: NFAppLocalization.preferredLocale, comment: "User-selected reason for replacing one daily-plan block.")
        case .needVariety: NFAppLocalization.localized("Need variety", locale: NFAppLocalization.preferredLocale, comment: "User-selected reason for replacing one daily-plan block.")
        case .notRelevantToday: NFAppLocalization.localized("Not relevant today", locale: NFAppLocalization.preferredLocale, comment: "User-selected reason for replacing one daily-plan block.")
        }
    }
}

struct NFPlanBlockReplacement: Codable, Equatable, Sendable {
    let originalBlockID: String
    let replacementBlockID: String
    let reason: NFPlanReplacementReason
    let replacedAt: Date
}

struct NFCanonicalDailyPlan: Codable, Equatable, Sendable, Identifiable {
    let id: String
    let profileID: UUID
    let localDayKey: String
    let seed: UInt64
    let policyVersion: Int
    let requestedMinutes: Int
    let scheduledMinutes: Int
    let blocks: [NFDailyPlanBlock]
    let prioritySnapshot: [NFSchedulingScoreBreakdown]
    let replacement: NFPlanBlockReplacement?

    var domainPlan: DailyPlan {
        domainPlan(locale: NFAppLocalization.preferredLocale)
    }

    func domainPlan(locale: Locale) -> DailyPlan {
        DailyPlan(
            id: id,
            localDayKey: localDayKey,
            seed: seed,
            policyVersion: policyVersion,
            minutes: scheduledMinutes,
            blocks: blocks.map { block in
                let targetLab = block.priority?.lab
                    ?? TrainingLab.allCases.first(where: { $0.skillID == block.targetSkillID })
                    ?? block.lab
                let presentation = NFDailyScheduler.localizedBlockPresentation(
                    kind: block.kind,
                    targetLab: targetLab,
                    locale: locale
                )
                return PlanBlock(
                    id: block.id,
                    lab: block.lab,
                    title: presentation.title,
                    detail: presentation.detail,
                    minutes: block.minutes,
                    reasons: block.reasons,
                    evidenceClass: block.evidenceClass,
                    offlineReady: block.offlineReady,
                    kindRaw: block.kind.rawValue,
                    mechanicID: block.mechanicID,
                    timed: block.timed,
                    retentionItemIDs: block.retentionTargets.isEmpty
                        ? block.retentionItemIDs
                        : block.retentionTargets.map(\.memoryItemID),
                    targetSkillID: block.targetSkillID
                )
            }
        )
    }
}

enum NFDailyPlanValidationError: Error, Equatable, Sendable {
    case invalidDuration
    case missingReason(String)
    case timedWorkExceedsPolicy
    case repeatedMechanic(String)
    case missingStandardComponent(NFDailyPlanBlockKind)
}

enum NFPlanReplacementError: Error, LocalizedError, Equatable, Sendable {
    case alreadyUsed
    case blockNotFound
    case noAccessibleAlternative

    var errorDescription: String? {
        switch self {
        case .alreadyUsed: NFAppLocalization.localized("Today’s one block replacement has already been used.", locale: NFAppLocalization.preferredLocale, comment: "Error shown when a user attempts a second daily-plan block replacement.")
        case .blockNotFound: NFAppLocalization.localized("That block is no longer part of today’s plan.", locale: NFAppLocalization.preferredLocale, comment: "Error shown when a plan block changed before replacement.")
        case .noAccessibleAlternative: NFAppLocalization.localized("No suitable offline alternative is available for this block.", locale: NFAppLocalization.preferredLocale, comment: "Error shown when no accessible offline replacement block can be scheduled.")
        }
    }
}

enum NFDailyPlanValidator {
    static func validate(_ plan: NFCanonicalDailyPlan, timingMode: TimingMode) throws {
        guard plan.scheduledMinutes > 0,
              plan.scheduledMinutes <= plan.requestedMinutes,
              plan.scheduledMinutes == plan.blocks.reduce(0, { $0 + $1.minutes }) else {
            throw NFDailyPlanValidationError.invalidDuration
        }
        for block in plan.blocks where block.reasons.isEmpty {
            throw NFDailyPlanValidationError.missingReason(block.id)
        }
        if timingMode != .speedFocus {
            let timedMinutes = plan.blocks.filter(\.timed).reduce(0) { $0 + $1.minutes }
            guard Double(timedMinutes) <= Double(plan.scheduledMinutes) * 0.40 + 0.000_001 else {
                throw NFDailyPlanValidationError.timedWorkExceedsPolicy
            }
        }
        for index in 2..<plan.blocks.count {
            let mechanic = plan.blocks[index].mechanicID
            if plan.blocks[index - 1].mechanicID == mechanic,
               plan.blocks[index - 2].mechanicID == mechanic {
                throw NFDailyPlanValidationError.repeatedMechanic(mechanic)
            }
        }
        if plan.requestedMinutes >= 15 {
            for required in NFDailyPlanBlockKind.allCases
            where !plan.blocks.contains(where: { $0.kind == required }) {
                throw NFDailyPlanValidationError.missingStandardComponent(required)
            }
        }
    }
}

// MARK: - Deterministic construction

enum NFDailyScheduler {
    static let policyVersion = 4
    static let breadthActiveDayWindow = 14

    /// Existing plans win for their canonical local day. This is the persistence
    /// boundary that prevents newly appended attempts from silently rewriting
    /// the plan after a session has started.
    static func canonicalPlan(
        for snapshot: NFDailySchedulingSnapshot,
        existingPlan: NFCanonicalDailyPlan? = nil,
        calendar: Calendar = .current
    ) -> NFCanonicalDailyPlan {
        let dayKey = localDayKey(
            for: snapshot.date,
            dayBoundaryHour: snapshot.dayBoundaryHour,
            calendar: calendar
        )
        if let existingPlan,
           existingPlan.profileID == snapshot.profile.id,
           existingPlan.localDayKey == dayKey,
           existingPlan.policyVersion == policyVersion {
            return existingPlan
        }
        return buildPlan(for: snapshot, localDayKey: dayKey, calendar: calendar)
    }

    static func priorityBreakdowns(
        for snapshot: NFDailySchedulingSnapshot
    ) -> [NFSchedulingScoreBreakdown] {
        let rawGoalWeights = Dictionary(uniqueKeysWithValues: foundationalLabs.map { lab in
            (lab, rawGoalWeight(for: lab, goals: snapshot.profile.goals))
        })
        let maximumGoalWeight = max(0.001, rawGoalWeights.values.max() ?? 1)
        let summaries = Dictionary(uniqueKeysWithValues: snapshot.skillSummaries.map { ($0.lab, $0) })

        return foundationalLabs.map { lab in
            let labAttempts = snapshot.attempts
                .filter { $0.lab == lab && $0.evidenceClass != .documentPractice }
                .sorted { lhs, rhs in
                    if lhs.submittedAt != rhs.submittedAt { return lhs.submittedAt < rhs.submittedAt }
                    return lhs.id.uuidString < rhs.id.uuidString
                }
            let trainingAttempts = labAttempts.filter { $0.evidenceClass == .practice }
            let transferAttempts = labAttempts.filter {
                $0.evidenceClass == .nearTransfer
                    || $0.evidenceClass == .appliedTransfer
                    || $0.evidenceClass == .assessmentHoldout
            }
            let goalWeight = NFStableDeterminism.clampedUnit(
                rawGoalWeights[lab, default: 0] / maximumGoalWeight
            )
            let summary = summaries[lab]
            let weakness: Double
            if let accuracy = summary?.accuracy {
                let targetAccuracy = 0.70 + 0.15 * goalWeight
                weakness = NFStableDeterminism.clampedUnit((targetAccuracy - accuracy) / targetAccuracy)
            } else {
                weakness = 0
            }
            let uncertainty = NFStableDeterminism.clampedUnit(summary?.uncertainty ?? 1)
            let reviewUrgency = reviewUrgency(
                lab: lab,
                date: snapshot.date,
                retentionStates: snapshot.retentionStates,
                lastTrained: summary?.lastTrained ?? labAttempts.last?.submittedAt
            )
            let transferGap = transferGap(
                trainingAttempts: trainingAttempts,
                transferAttempts: transferAttempts
            )
            let varietyNeed = varietyNeed(lastTrained: labAttempts.last?.submittedAt, date: snapshot.date)
            let recentLoad = recentLoadPenalty(attempts: labAttempts, date: snapshot.date)
            let accessibility = snapshot.accessibilityExcludedLabs.contains(lab) ? 1.0 : 0.0
            let total = 0.28 * goalWeight
                + 0.24 * reviewUrgency
                + 0.18 * weakness
                + 0.12 * uncertainty
                + 0.10 * transferGap
                + 0.08 * varietyNeed
                - recentLoad
                - accessibility
            let reasons = reasons(
                goalWeight: goalWeight,
                reviewUrgency: reviewUrgency,
                weakness: weakness,
                uncertainty: uncertainty,
                transferGap: transferGap,
                varietyNeed: varietyNeed
            )
            return NFSchedulingScoreBreakdown(
                skillID: lab.skillID,
                lab: lab,
                normalizedGoalWeight: goalWeight,
                reviewUrgency: reviewUrgency,
                weaknessRelativeToGoal: weakness,
                estimateUncertainty: uncertainty,
                transferGap: transferGap,
                varietyNeed: varietyNeed,
                recentLoadPenalty: recentLoad,
                accessibilityPenalty: accessibility,
                totalPriority: total,
                reasons: reasons
            )
        }
        .sorted(by: prioritySort)
    }

    static func replacingBlock(
        in plan: NFCanonicalDailyPlan,
        blockID: String,
        reason: NFPlanReplacementReason,
        at date: Date = .now
    ) throws -> NFCanonicalDailyPlan {
        guard plan.replacement == nil else { throw NFPlanReplacementError.alreadyUsed }
        guard let index = plan.blocks.firstIndex(where: { $0.id == blockID }) else {
            throw NFPlanReplacementError.blockNotFound
        }

        let original = plan.blocks[index]
        let originalTarget = original.priority?.lab ?? original.lab
        guard let target = plan.prioritySnapshot.first(where: {
            $0.accessibilityPenalty < 1
                && $0.lab != originalTarget
                && $0.lab != .transfer
        }) else {
            throw NFPlanReplacementError.noAccessibleAlternative
        }

        let presentation = blockPresentation(kind: original.kind, target: target)
        let replacementID = original.id + ".replacement." + String(
            NFStableDeterminism.hash64("\(plan.id)|\(original.id)|\(reason.rawValue)|\(target.lab.rawValue)"),
            radix: 16
        )
        var reasons = [PrescriptionReason.userOverride]
        for candidate in target.reasons where !reasons.contains(candidate) {
            reasons.append(candidate)
            if reasons.count == 3 { break }
        }
        let replacementBlock = NFDailyPlanBlock(
            id: replacementID,
            kind: original.kind,
            lab: original.kind == .unseenTransfer ? .transfer : target.lab,
            targetSkillID: target.skillID,
            title: presentation.title,
            detail: presentation.detail,
            minutes: original.minutes,
            reasons: reasons,
            evidenceClass: evidenceClass(for: original.kind),
            priority: target,
            mechanicID: mechanicID(for: original.kind, target: target.lab),
            timed: original.timed,
            offlineReady: true,
            retentionItemIDs: []
        )
        var blocks = plan.blocks
        blocks[index] = replacementBlock
        return NFCanonicalDailyPlan(
            id: plan.id,
            profileID: plan.profileID,
            localDayKey: plan.localDayKey,
            seed: plan.seed,
            policyVersion: plan.policyVersion,
            requestedMinutes: plan.requestedMinutes,
            scheduledMinutes: plan.scheduledMinutes,
            blocks: blocks,
            prioritySnapshot: plan.prioritySnapshot,
            replacement: NFPlanBlockReplacement(
                originalBlockID: original.id,
                replacementBlockID: replacementID,
                reason: reason,
                replacedAt: date
            )
        )
    }

    private static func buildPlan(
        for snapshot: NFDailySchedulingSnapshot,
        localDayKey: String,
        calendar: Calendar
    ) -> NFCanonicalDailyPlan {
        let priorities = priorityBreakdowns(for: snapshot)
        let available = priorities.filter { $0.accessibilityPenalty < 1 }
        let ranked = available.isEmpty ? priorities : available
        let breadthTargets = uncoveredBreadthPriorities(
            for: snapshot,
            among: ranked,
            calendar: calendar
        )
        let breadthTargetLabs = Set(breadthTargets.map(\.lab))
        let firstTarget = breadthTargets.first
            ?? ranked.first
            ?? fallbackPriority(lab: .mentalMath)
        let secondTarget = breadthTargets.dropFirst().first
            ?? ranked.first(where: { $0.lab != firstTarget.lab })
            ?? firstTarget
        let sourceTargets = ranked.filter { $0.lab != .transfer }
        let transferTarget = sourceTargets.sorted { lhs, rhs in
            if abs(lhs.transferGap - rhs.transferGap) > 0.000_000_001 {
                return lhs.transferGap > rhs.transferGap
            }
            return prioritySort(lhs, rhs)
        }.first ?? sourceTargets.first ?? fallbackPriority(lab: .mentalMath)
        let reviewTarget = ranked.sorted { lhs, rhs in
            if abs(lhs.reviewUrgency - rhs.reviewUrgency) > 0.000_000_001 {
                return lhs.reviewUrgency > rhs.reviewUrgency
            }
            return prioritySort(lhs, rhs)
        }.first ?? firstTarget

        let weekday = calendar.component(.weekday, from: snapshot.date)
        let baseBudget = snapshot.profile.trainingDays.contains(weekday)
            ? normalizedBudget(snapshot.profile.dailyDuration)
            : 5
        let budget: Int = switch snapshot.readiness {
        case .low:
            [5, 10, 15, 20].last(where: { $0 < baseBudget }) ?? 5
        case .normal, .high:
            baseBudget
        }
        let seed = NFStableDeterminism.hash64(
            "daily|\(policyVersion)|\(snapshot.profile.id.uuidString)|\(localDayKey)|\(snapshot.readiness.rawValue)"
        )
        let retentionAssignments = NFRetentionScheduler.schedule(
            states: snapshot.retentionStates.filter { $0.lab == reviewTarget.lab },
            at: snapshot.date,
            maximumItems: max(1, budget / 2)
        )
        let specs = durationTemplate(for: budget)
        var blocks: [NFDailyPlanBlock] = []
        var targetOrdinal = 0
        var timedMinutes = 0

        for (index, spec) in specs.enumerated() {
            let priority: NFSchedulingScoreBreakdown
            switch spec.kind {
            case .retentionReview: priority = reviewTarget
            case .targetPractice:
                priority = targetOrdinal == 0 ? firstTarget : secondTarget
                targetOrdinal += 1
            case .unseenTransfer: priority = transferTarget
            case .confidenceReflection: priority = firstTarget
            }

            var reasons: [PrescriptionReason]
            switch spec.kind {
            case .retentionReview:
                reasons = priority.reviewUrgency > 0.25 ? [.reviewDue] : [.variety]
            case .targetPractice:
                reasons = breadthTargetLabs.contains(priority.lab) ? [.variety] : priority.reasons
            case .unseenTransfer:
                reasons = priority.transferGap > 0.10
                    ? [.transferGap, .representationCoverage]
                    : [.representationCoverage, .variety]
            case .confidenceReflection:
                reasons = [.calibration]
            }
            if snapshot.readiness != .normal, !reasons.contains(.userOverride) {
                reasons.append(.userOverride)
            }

            let canBeTimed = spec.kind == .targetPractice
                && (priority.lab != .mentalMath || snapshot.mentalMathTimingEligible)
            let timed: Bool
            if snapshot.readiness == .low {
                timed = false
            } else {
                switch snapshot.profile.timingMode {
                case .untimed:
                    timed = false
                case .speedFocus:
                    timed = canBeTimed
                case .adaptive:
                    let timedLimit = Int(floor(Double(budget) * 0.40))
                    timed = canBeTimed && timedMinutes + spec.minutes <= timedLimit
                }
            }
            if timed { timedMinutes += spec.minutes }

            let presentation = blockPresentation(kind: spec.kind, target: priority)
            blocks.append(
                NFDailyPlanBlock(
                    id: "nf.plan.block.\(String(seed, radix: 16)).\(index)",
                    kind: spec.kind,
                    lab: spec.kind == .unseenTransfer ? .transfer : priority.lab,
                    targetSkillID: priority.skillID,
                    title: presentation.title,
                    detail: presentation.detail,
                    minutes: spec.minutes,
                    reasons: reasons,
                    evidenceClass: evidenceClass(for: spec.kind),
                    priority: priority,
                    mechanicID: mechanicID(for: spec.kind, target: priority.lab),
                    timed: timed,
                    offlineReady: true,
                    retentionItemIDs: spec.kind == .retentionReview
                        ? retentionAssignments.map(\.memoryItemID)
                        : [],
                    retentionTargets: spec.kind == .retentionReview
                        ? retentionAssignments.map(\.reviewTarget)
                        : []
                )
            )
        }

        let plan = NFCanonicalDailyPlan(
            id: "nf.plan.v\(policyVersion).readiness-\(snapshot.readiness.rawValue).\(localDayKey).\(String(seed, radix: 16))",
            profileID: snapshot.profile.id,
            localDayKey: localDayKey,
            seed: seed,
            policyVersion: policyVersion,
            requestedMinutes: budget,
            scheduledMinutes: blocks.reduce(0) { $0 + $1.minutes },
            blocks: blocks,
            prioritySnapshot: priorities,
            replacement: nil
        )
        precondition((try? NFDailyPlanValidator.validate(plan, timingMode: snapshot.profile.timingMode)) != nil)
        return plan
    }

    private struct BlockSpec {
        let kind: NFDailyPlanBlockKind
        let minutes: Int
    }

    private static func durationTemplate(for budget: Int) -> [BlockSpec] {
        switch budget {
        case 5:
            [BlockSpec(kind: .targetPractice, minutes: 3),
             BlockSpec(kind: .unseenTransfer, minutes: 2)]
        case 10:
            [BlockSpec(kind: .retentionReview, minutes: 2),
             BlockSpec(kind: .targetPractice, minutes: 5),
             BlockSpec(kind: .unseenTransfer, minutes: 2),
             BlockSpec(kind: .confidenceReflection, minutes: 1)]
        case 15:
            [BlockSpec(kind: .retentionReview, minutes: 3),
             BlockSpec(kind: .targetPractice, minutes: 5),
             BlockSpec(kind: .targetPractice, minutes: 3),
             BlockSpec(kind: .unseenTransfer, minutes: 3),
             BlockSpec(kind: .confidenceReflection, minutes: 1)]
        default:
            [BlockSpec(kind: .retentionReview, minutes: 4),
             BlockSpec(kind: .targetPractice, minutes: 5),
             BlockSpec(kind: .targetPractice, minutes: 5),
             BlockSpec(kind: .unseenTransfer, minutes: 4),
             BlockSpec(kind: .confidenceReflection, minutes: 2)]
        }
    }

    private static func normalizedBudget(_ requested: Int) -> Int {
        [5, 10, 15, 20].min { lhs, rhs in
            let leftDistance = abs(lhs - requested)
            let rightDistance = abs(rhs - requested)
            if leftDistance != rightDistance { return leftDistance < rightDistance }
            return lhs < rhs
        } ?? 10
    }

    private static func prioritySort(
        _ lhs: NFSchedulingScoreBreakdown,
        _ rhs: NFSchedulingScoreBreakdown
    ) -> Bool {
        if abs(lhs.totalPriority - rhs.totalPriority) > 0.000_000_001 {
            return lhs.totalPriority > rhs.totalPriority
        }
        return lhs.lab.rawValue < rhs.lab.rawValue
    }

    /// Transfer is an evidence mode layered over a source ability. It is never
    /// eligible to occupy a foundational target, review, or breadth slot.
    private static var foundationalLabs: [TrainingLab] {
        TrainingLab.allCases.filter { $0 != .transfer }
    }

    /// Returns only the foundational abilities absent from the rolling active-
    /// day window. A new active day looks back over the previous 13 active days,
    /// so today's target completes a 14-day window. Once every accessible lab is
    /// represented, the ordinary goal-weighted ranking takes over again.
    private static func uncoveredBreadthPriorities(
        for snapshot: NFDailySchedulingSnapshot,
        among candidates: [NFSchedulingScoreBreakdown],
        calendar: Calendar
    ) -> [NFSchedulingScoreBreakdown] {
        guard !candidates.isEmpty else { return [] }
        let currentDayKey = localDayKey(
            for: snapshot.date,
            dayBoundaryHour: snapshot.dayBoundaryHour,
            calendar: calendar
        )
        let eligibleAttempts = snapshot.attempts.filter {
            $0.evidenceWeight > 0
                && $0.evidenceClass != .documentPractice
                && $0.submittedAt <= snapshot.date
        }
        let activeDayKeys = Set(eligibleAttempts.map {
            localDayKey(
                for: $0.submittedAt,
                dayBoundaryHour: snapshot.dayBoundaryHour,
                calendar: calendar
            )
        })
        let precedingDayCount = activeDayKeys.contains(currentDayKey)
            ? breadthActiveDayWindow
            : breadthActiveDayWindow - 1
        let rollingDayKeys = Set(activeDayKeys.sorted().suffix(precedingDayCount))
        let candidateLabs = Set(candidates.map(\.lab))
        var coveredLabs: Set<TrainingLab> = []
        var latestPracticeByLab: [TrainingLab: Date] = [:]

        for attempt in eligibleAttempts
        where attempt.evidenceClass == .practice && candidateLabs.contains(attempt.lab) {
            latestPracticeByLab[attempt.lab] = max(
                latestPracticeByLab[attempt.lab] ?? .distantPast,
                attempt.submittedAt
            )
            let dayKey = localDayKey(
                for: attempt.submittedAt,
                dayBoundaryHour: snapshot.dayBoundaryHour,
                calendar: calendar
            )
            if rollingDayKeys.contains(dayKey) { coveredLabs.insert(attempt.lab) }
        }

        return candidates
            .filter { !coveredLabs.contains($0.lab) }
            .sorted { lhs, rhs in
                let lhsDate = latestPracticeByLab[lhs.lab]
                let rhsDate = latestPracticeByLab[rhs.lab]
                if lhsDate != rhsDate {
                    return (lhsDate ?? .distantPast) < (rhsDate ?? .distantPast)
                }
                return lhs.lab.rawValue < rhs.lab.rawValue
            }
    }

    private static func rawGoalWeight(for lab: TrainingLab, goals: Set<TrainingGoal>) -> Double {
        guard lab != .transfer else { return 0 }
        var weight = 0.20
        for goal in goals {
            let candidate: Double
            switch (goal, lab) {
            case (.mentalMath, .mentalMath), (.spatialReasoning, .spatial): candidate = 1
            case (.dataReasoning, .quantitative), (.dataReasoning, .scientificReasoning): candidate = 1
            case (.experimentalDesign, .scientificReasoning): candidate = 1
            case (.programming, .logicDebugging): candidate = 1
            case (.researchReading, .retrieval): candidate = 1
            case (.problemSolving, .logicDebugging), (.problemSolving, .quantitative): candidate = 0.90
            case (.researchReading, .scientificReasoning), (.experimentalDesign, .logicDebugging),
                 (.programming, .quantitative): candidate = 0.65
            default: candidate = 0.20
            }
            weight = max(weight, candidate)
        }
        return weight
    }

    private static func reviewUrgency(
        lab: TrainingLab,
        date: Date,
        retentionStates: [NFRetentionItemState],
        lastTrained: Date?
    ) -> Double {
        let explicit = retentionStates
            .filter { $0.lab == lab }
            .map { NFRetentionScheduler.urgency(for: $0, at: date) }
            .max()
        if let explicit { return NFStableDeterminism.clampedUnit(explicit) }
        guard let lastTrained else { return 0.35 }
        let elapsedDays = max(0, date.timeIntervalSince(lastTrained) / 86_400)
        return NFStableDeterminism.clampedUnit(1 - exp(-elapsedDays / 7))
    }

    private static func transferGap(
        trainingAttempts: [AttemptDTO],
        transferAttempts: [AttemptDTO]
    ) -> Double {
        guard trainingAttempts.count >= 3 else { return 0 }
        let training = accuracy(trainingAttempts)
        guard !transferAttempts.isEmpty else {
            return NFStableDeterminism.clampedUnit(training * 0.45)
        }
        return NFStableDeterminism.clampedUnit(training - accuracy(transferAttempts))
    }

    private static func accuracy(_ attempts: [AttemptDTO]) -> Double {
        guard !attempts.isEmpty else { return 0 }
        let weightedTotal = attempts.reduce(0) { $0 + max(0, $1.evidenceWeight) }
        guard weightedTotal > 0 else {
            return attempts.reduce(0) { $0 + $1.credit } / Double(attempts.count)
        }
        let earnedCredit = attempts.reduce(0.0) { partial, attempt in
            partial + attempt.credit * max(0, attempt.evidenceWeight)
        }
        return NFStableDeterminism.clampedUnit(earnedCredit / weightedTotal)
    }

    private static func varietyNeed(lastTrained: Date?, date: Date) -> Double {
        guard let lastTrained else { return 1 }
        let days = max(0, date.timeIntervalSince(lastTrained) / 86_400)
        return NFStableDeterminism.clampedUnit(days / 14)
    }

    private static func recentLoadPenalty(attempts: [AttemptDTO], date: Date) -> Double {
        let cutoff = date.addingTimeInterval(-72 * 3_600)
        let recentWeight = attempts
            .filter { $0.submittedAt >= cutoff && $0.submittedAt <= date }
            .reduce(0.0) { $0 + max(0.25, $1.evidenceWeight) }
        return min(0.22, recentWeight * 0.025)
    }

    private static func reasons(
        goalWeight: Double,
        reviewUrgency: Double,
        weakness: Double,
        uncertainty: Double,
        transferGap: Double,
        varietyNeed: Double
    ) -> [PrescriptionReason] {
        var values: [(PrescriptionReason, Double)] = [
            (.goalPriority, 0.28 * goalWeight),
            (.reviewDue, 0.24 * reviewUrgency),
            (.skillGap, 0.18 * weakness),
            (.estimateUncertain, 0.12 * uncertainty),
            (.transferGap, 0.10 * transferGap),
            (.variety, 0.08 * varietyNeed)
        ]
        values.sort { lhs, rhs in
            if abs(lhs.1 - rhs.1) > 0.000_000_001 { return lhs.1 > rhs.1 }
            return reasonOrder(lhs.0) < reasonOrder(rhs.0)
        }
        let selected = values.filter { $0.1 >= 0.075 }.prefix(3).map(\.0)
        return selected.isEmpty ? [values[0].0] : selected
    }

    private static func reasonOrder(_ reason: PrescriptionReason) -> Int {
        switch reason {
        case .goalPriority: 0
        case .reviewDue: 1
        case .skillGap: 2
        case .estimateUncertain: 3
        case .transferGap: 4
        case .errorPattern: 5
        case .representationCoverage: 6
        case .calibration: 7
        case .variety: 8
        case .userOverride: 9
        }
    }

    private static func evidenceClass(for kind: NFDailyPlanBlockKind) -> EvidenceClass {
        switch kind {
        case .retentionReview: .retention
        case .targetPractice: .practice
        case .unseenTransfer: .appliedTransfer
        case .confidenceReflection: .nearTransfer
        }
    }

    private static func mechanicID(for kind: NFDailyPlanBlockKind, target: TrainingLab) -> String {
        switch kind {
        case .retentionReview: "retention.\(target.rawValue)"
        case .targetPractice: "target.\(target.rawValue)"
        case .unseenTransfer: "transfer.cross_representation"
        case .confidenceReflection: "reflection.calibration"
        }
    }

    private static func blockPresentation(
        kind: NFDailyPlanBlockKind,
        target: NFSchedulingScoreBreakdown
    ) -> (title: String, detail: String) {
        localizedBlockPresentation(
            kind: kind,
            targetLab: target.lab,
            locale: NFAppLocalization.preferredLocale
        )
    }

    static func localizedBlockPresentation(
        kind: NFDailyPlanBlockKind,
        targetLab: TrainingLab,
        locale: Locale
    ) -> (title: String, detail: String) {
        let targetTitle = targetLab.localizedShortTitle(locale: locale)
        switch kind {
        case .retentionReview:
            return (
                NFAppLocalization.localized("Recall practice", locale: locale, comment: "Title of a daily-plan block for delayed recall."),
                NFAppLocalization.localized("Recall \(targetTitle) in a different form.", locale: locale, comment: "Description of a delayed-recall daily-plan block; the placeholder is a training-lab name.")
            )
        case .targetPractice:
            return (
                targetTitle,
                NFAppLocalization.localized("Practice \(targetTitle) with a focused set.", locale: locale, comment: "Description of a daily-plan practice block; the placeholder is a training-lab name.")
            )
        case .unseenTransfer:
            return (
                NFAppLocalization.localized("Apply it differently", locale: locale, comment: "Title of a daily-plan transfer block using an unfamiliar form."),
                NFAppLocalization.localized("Use \(targetTitle) in a new context or format.", locale: locale, comment: "Description of a transfer block; the placeholder is a training-lab name.")
            )
        case .confidenceReflection:
            return (
                NFAppLocalization.localized("Confidence check", locale: locale, comment: "Title of a daily-plan confidence-calibration block."),
                NFAppLocalization.localized("Compare how sure you felt with whether the answer was correct.", locale: locale, comment: "Description of a confidence-calibration block.")
            )
        }
    }

    private static func fallbackPriority(lab: TrainingLab) -> NFSchedulingScoreBreakdown {
        NFSchedulingScoreBreakdown(
            skillID: lab.skillID,
            lab: lab,
            normalizedGoalWeight: 1,
            reviewUrgency: 0.35,
            weaknessRelativeToGoal: 0,
            estimateUncertainty: 1,
            transferGap: 0,
            varietyNeed: 1,
            recentLoadPenalty: 0,
            accessibilityPenalty: 0,
            totalPriority: 0.564,
            reasons: [.goalPriority, .estimateUncertain]
        )
    }

    static func localDayKey(
        for date: Date,
        dayBoundaryHour: Int,
        calendar: Calendar = .current
    ) -> String {
        let adjusted = calendar.date(byAdding: .hour, value: -dayBoundaryHour, to: date) ?? date
        let components = calendar.dateComponents([.year, .month, .day], from: adjusted)
        return String(
            format: "%04d-%02d-%02d",
            components.year ?? 0,
            components.month ?? 0,
            components.day ?? 0
        )
    }
}

import Foundation

struct NFProgressInsight: Identifiable, Equatable {
    enum Kind: String, Equatable {
        case strength
        case repeatedError
        case overconfidence
        case reviewDue
    }

    let id: String
    let kind: Kind
    let ruleID: String
    let lab: TrainingLab
    let title: String
    let detail: String
    let evidenceAttemptIDs: [UUID]
}

struct NFProgressInsightSnapshot: Equatable {
    let strengths: [NFProgressInsight]
    let repeatedErrors: [NFProgressInsight]
    let overconfidenceHotspots: [NFProgressInsight]
    let reviewsDue: [NFProgressInsight]
}

enum NFProgressInsightEngine {
    static let version = 1

    static func makeSnapshot(
        at date: Date,
        attempts: [AttemptRecord],
        errorCodeOverrides: [UUID: String] = [:]
    ) -> NFProgressInsightSnapshot {
        let eligible = attempts
            .filter { !$0.wasSkipped && $0.evidenceWeight > 0 }
            .sorted(by: evidenceOrder)
        return NFProgressInsightSnapshot(
            strengths: strengths(from: eligible),
            repeatedErrors: repeatedErrors(from: eligible, errorCodeOverrides: errorCodeOverrides),
            overconfidenceHotspots: overconfidence(from: eligible),
            reviewsDue: reviewsDue(at: date, from: eligible)
        )
    }

    private static func strengths(from attempts: [AttemptRecord]) -> [NFProgressInsight] {
        Dictionary(grouping: attempts) { TrainingLab(rawValue: $0.gameID) ?? .mentalMath }
            .compactMap { lab, records -> (NFProgressInsight, Double)? in
                guard records.count >= 5 else { return nil }
                let available = records.reduce(0) { $0 + max(0, $1.evidenceWeight) }
                guard available > 0 else { return nil }
                let earned = records.reduce(0) {
                    $0 + min(1, max(0, $1.deterministicCredit)) * max(0, $1.evidenceWeight)
                }
                let credit = earned / available
                let evidenceClasses = Set(records.map(\.evidenceClassRaw))
                guard credit >= 0.75, evidenceClasses.count >= 2 else { return nil }
                let insight = NFProgressInsight(
                    id: "strength.\(lab.rawValue)",
                    kind: .strength,
                    ruleID: "progress.strength.v1.n5.credit75.two-channels",
                    lab: lab,
                    title: NFAppLocalization.localized("Current strength: \(lab.shortTitle)", locale: NFAppLocalization.preferredLocale, comment: "Progress insight title; the placeholder is a training-lab name."),
                    detail: NFAppLocalization.localized("\(records.count) scored answers average \(credit.formatted(.percent.precision(.fractionLength(0)))).", locale: NFAppLocalization.preferredLocale, comment: "Progress strength detail; placeholders are an answer count and locale-formatted average score."),
                    evidenceAttemptIDs: records.map(\.id)
                )
                return (insight, credit)
            }
            .sorted {
                if abs($0.1 - $1.1) > 0.000_000_001 { return $0.1 > $1.1 }
                return $0.0.lab.rawValue < $1.0.lab.rawValue
            }
            .map(\.0)
    }

    private static func repeatedErrors(
        from attempts: [AttemptRecord],
        errorCodeOverrides: [UUID: String]
    ) -> [NFProgressInsight] {
        let errors = attempts.compactMap { attempt -> (attempt: AttemptRecord, code: String)? in
            guard !attempt.isCorrect,
                  let code = errorCodeOverrides[attempt.id] ?? attempt.errorCode,
                  !code.isEmpty else { return nil }
            return (attempt, code)
        }
        return Dictionary(grouping: errors) {
            "\($0.attempt.gameID)|\($0.code)"
        }
        .compactMap { key, records -> NFProgressInsight? in
            guard records.count >= 2,
                  let first = records.first else { return nil }
            let lab = TrainingLab(rawValue: first.attempt.gameID) ?? .mentalMath
            return NFProgressInsight(
                id: "error.\(key)",
                kind: .repeatedError,
                ruleID: "progress.repeated-error.v1.n2",
                lab: lab,
                title: NFErrorReflectionCode(rawValue: first.code)?.title
                    ?? NFScoringErrorCopy.title(for: first.code),
                detail: NFAppLocalization.localized("This pattern appeared \(records.count) times in \(lab.shortTitle).", locale: NFAppLocalization.preferredLocale, comment: "Repeated-error progress insight; placeholders are occurrence count and training-lab name."),
                evidenceAttemptIDs: records.map(\.attempt.id)
            )
        }
        .sorted {
            if $0.evidenceAttemptIDs.count != $1.evidenceAttemptIDs.count {
                return $0.evidenceAttemptIDs.count > $1.evidenceAttemptIDs.count
            }
            return $0.id < $1.id
        }
    }

    private static func overconfidence(from attempts: [AttemptRecord]) -> [NFProgressInsight] {
        let candidates = attempts.filter { attempt in
            guard !attempt.isCorrect,
                  let confidence = attempt.confidenceRaw.flatMap(ConfidenceLevel.init(rawValue:)) else {
                return false
            }
            return confidence.probability >= ConfidenceLevel.fairlyConfident.probability
        }
        return Dictionary(grouping: candidates) { TrainingLab(rawValue: $0.gameID) ?? .mentalMath }
            .compactMap { lab, records -> NFProgressInsight? in
                guard records.count >= 2 else { return nil }
                return NFProgressInsight(
                    id: "overconfidence.\(lab.rawValue)",
                    kind: .overconfidence,
                    ruleID: "progress.overconfidence.v1.incorrect-confidence72.n2",
                    lab: lab,
                    title: NFAppLocalization.localized("Confidence check: \(lab.shortTitle)", locale: NFAppLocalization.preferredLocale, comment: "Confidence-calibration progress insight title; the placeholder is a training-lab name."),
                    detail: NFAppLocalization.localized("\(NFAppLocalization.formattedAnswerCount(records.count)) were incorrect despite high confidence. Review the underlying step before retrying.", locale: NFAppLocalization.preferredLocale, comment: "Confidence-calibration progress insight; the placeholder is a localized answer count."),
                    evidenceAttemptIDs: records.map(\.id)
                )
            }
            .sorted {
                if $0.evidenceAttemptIDs.count != $1.evidenceAttemptIDs.count {
                    return $0.evidenceAttemptIDs.count > $1.evidenceAttemptIDs.count
                }
                return $0.lab.rawValue < $1.lab.rawValue
            }
    }

    private static func reviewsDue(at date: Date, from attempts: [AttemptRecord]) -> [NFProgressInsight] {
        Dictionary(grouping: attempts.filter { !$0.templateID.isEmpty }, by: \.templateID)
            .compactMap { templateID, records -> (NFProgressInsight, Date)? in
                guard let latest = records.max(by: evidenceOrder) else { return nil }
                let correctCount = records.filter(\.isCorrect).count
                let stabilityDays = max(0.5, 1 + Double(correctCount) * 0.6)
                let dueAt = latest.submittedAt.addingTimeInterval(stabilityDays * 86_400)
                guard dueAt <= date else { return nil }
                let lab = TrainingLab(rawValue: latest.gameID) ?? .mentalMath
                let insight = NFProgressInsight(
                    id: "review.\(templateID)",
                    kind: .reviewDue,
                    ruleID: "progress.review-due.v1.stability-linear",
                    lab: lab,
                    title: NFAppLocalization.localized("Review due: \(lab.shortTitle)", locale: NFAppLocalization.preferredLocale, comment: "Retention-review insight title; the placeholder is a training-lab name."),
                    detail: NFAppLocalization.localized("A fresh version of this question pattern is ready for review.", locale: NFAppLocalization.preferredLocale, comment: "Retention-review insight detail."),
                    evidenceAttemptIDs: records.map(\.id)
                )
                return (insight, dueAt)
            }
            .sorted {
                if $0.1 != $1.1 { return $0.1 < $1.1 }
                return $0.0.id < $1.0.id
            }
            .map(\.0)
    }

    private static func evidenceOrder(_ lhs: AttemptRecord, _ rhs: AttemptRecord) -> Bool {
        if lhs.submittedAt != rhs.submittedAt { return lhs.submittedAt < rhs.submittedAt }
        return lhs.id.uuidString < rhs.id.uuidString
    }
}

enum NFConsistencyDayStatus: String, Equatable {
    case active
    case plannedRest
    case protectedPause
    case missedPlanned
    case availableToday
}

struct NFConsistencyDay: Identifiable, Equatable {
    let date: Date
    let status: NFConsistencyDayStatus
    var id: Date { date }
}

struct NFConsistencySnapshot: Equatable {
    let currentActiveDayStreak: Int
    let activeDaysInWindow: Int
    let plannedDaysInWindow: Int
    let protectedPauseCount: Int
    let protectionAvailableThisWeek: Bool
    let days: [NFConsistencyDay]
}

enum NFConsistencyEngine {
    static let version = 1

    static func makeSnapshot(
        at date: Date,
        attempts: [AttemptRecord],
        trainingDays: Set<Int>,
        trackingStartDate: Date? = nil,
        windowDays: Int = 28,
        calendar suppliedCalendar: Calendar = .current
    ) -> NFConsistencySnapshot {
        let calendar = suppliedCalendar
        let today = calendar.startOfDay(for: date)
        let activeDates = Set(attempts.compactMap { attempt -> Date? in
            guard !attempt.wasSkipped, attempt.evidenceWeight > 0 else { return nil }
            return calendar.startOfDay(for: attempt.submittedAt)
        })
        let selectedDays = trainingDays.isEmpty ? Set(1...7) : trainingDays
        var protectedWeekKeys: Set<String> = []
        var days: [NFConsistencyDay] = []
        let count = max(1, windowDays)
        let trackingStart = trackingStartDate.map { calendar.startOfDay(for: $0) }

        for offset in stride(from: count - 1, through: 0, by: -1) {
            guard let day = calendar.date(byAdding: .day, value: -offset, to: today) else { continue }
            if let trackingStart, day < trackingStart { continue }
            let isActive = activeDates.contains(day)
            let isPlanned = selectedDays.contains(calendar.component(.weekday, from: day))
            let status: NFConsistencyDayStatus
            if isActive {
                status = .active
            } else if !isPlanned {
                status = .plannedRest
            } else if day == today {
                status = .availableToday
            } else {
                let weekKey = consistencyWeekKey(for: day, calendar: calendar)
                if protectedWeekKeys.insert(weekKey).inserted {
                    status = .protectedPause
                } else {
                    status = .missedPlanned
                }
            }
            days.append(NFConsistencyDay(date: day, status: status))
        }

        var streak = 0
        for day in days.reversed() {
            switch day.status {
            case .active:
                streak += 1
            case .plannedRest, .protectedPause, .availableToday:
                continue
            case .missedPlanned:
                break
            }
            if day.status == .missedPlanned { break }
        }

        let currentWeekKey = consistencyWeekKey(for: today, calendar: calendar)
        return NFConsistencySnapshot(
            currentActiveDayStreak: streak,
            activeDaysInWindow: days.filter { $0.status == .active }.count,
            plannedDaysInWindow: days.filter {
                $0.status == .active || $0.status == .protectedPause || $0.status == .missedPlanned || $0.status == .availableToday
            }.count,
            protectedPauseCount: days.filter { $0.status == .protectedPause }.count,
            protectionAvailableThisWeek: !protectedWeekKeys.contains(currentWeekKey),
            days: days
        )
    }

    private static func consistencyWeekKey(for date: Date, calendar: Calendar) -> String {
        let values = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        return "\(values.yearForWeekOfYear ?? 0)-\(values.weekOfYear ?? 0)"
    }
}

// MARK: - Engagement progression

/// A cosmetic, engagement-only milestone. Forge progression never feeds the
/// adaptive reducer, assessment estimates, evidence weights, or scheduling.
enum NFForgeMilestoneCode: String, Codable, CaseIterable, Sendable {
    case firstAttempt = "first_attempt"
    case firstCompletedSession = "first_completed_session"
    case firstTransferAttempt = "first_transfer_attempt"
    case accessibleLabCircuit = "accessible_lab_circuit"
}

struct NFForgeMilestone: Identifiable, Equatable, Sendable {
    let code: NFForgeMilestoneCode
    let unlockedAt: Date
    let evidenceAttemptIDs: [UUID]
    let evidenceSessionIDs: [UUID]

    var id: String { code.rawValue }
}

struct NFForgeProgressSnapshot: Equatable {
    let policyVersion: Int
    let totalXP: Int
    let attemptXP: Int
    let completionXP: Int
    let eligibleAttemptCount: Int
    let rewardedSessionCount: Int
    let level: Int
    /// Absolute XP threshold at which the current level began.
    let levelStartXP: Int
    /// Absolute XP threshold at which the next level begins.
    let nextLevelXP: Int
    let xpIntoLevel: Int
    let xpToNextLevel: Int
    let levelProgress: Double
    let momentum: NFConsistencySnapshot
    let accessibleLabs: Set<TrainingLab>
    let currentWeekCoveredLabs: Set<TrainingLab>
    let currentWeekCoverage: Double
    let milestones: [NFForgeMilestone]
}

/// Rebuilds the complete Forge progression from durable learning events. The
/// policy rewards showing up and completing work, never correctness or speed.
/// This makes the total replay-safe while keeping learning evidence authoritative
/// in its existing reducers.
enum NFForgeProgressEngine {
    static let policyVersion = 1
    static let xpPerEligibleAttempt = 10
    static let xpPerEligibleCompletedSession = 25

    static func makeSnapshot(
        at date: Date,
        attempts: [AttemptRecord],
        checkpoints: [SessionCheckpointRecord],
        trainingDays: Set<Int>,
        trackingStartDate: Date? = nil,
        excludedLabs: Set<TrainingLab> = [],
        calendar: Calendar = .current
    ) -> NFForgeProgressSnapshot {
        let uniqueAttempts = uniqueAttempts(from: attempts)
        let eligibleAttempts = uniqueAttempts.filter { !$0.wasSkipped }
        let eligibleSessionIDs = Set(eligibleAttempts.map(\.sessionID))
        let completedSessions = completedSessionDates(from: checkpoints)
            .filter { eligibleSessionIDs.contains($0.key) }
        let attemptXP = eligibleAttempts.count * xpPerEligibleAttempt
        let completionXP = completedSessions.count * xpPerEligibleCompletedSession
        let totalXP = attemptXP + completionXP
        let levelState = levelState(for: totalXP)
        // Transfer is a cross-ability evidence mode rather than a foundational
        // path, so it can earn engagement XP without widening the breadth goal.
        let accessibleLabs = Set(TrainingLab.allCases)
            .subtracting(excludedLabs.union([.transfer]))
        let weekInterval = calendar.dateInterval(of: .weekOfYear, for: date)
        let currentWeekAttempts = eligibleAttempts.filter { attempt in
            guard let weekInterval else { return false }
            return weekInterval.contains(attempt.submittedAt) && attempt.submittedAt <= date
        }
        let currentWeekCoveredLabs = Set(currentWeekAttempts.compactMap { attempt in
            TrainingLab(rawValue: attempt.gameID)
        }).intersection(accessibleLabs)
        let currentWeekCoverage = accessibleLabs.isEmpty
            ? 0
            : Double(currentWeekCoveredLabs.count) / Double(accessibleLabs.count)

        return NFForgeProgressSnapshot(
            policyVersion: policyVersion,
            totalXP: totalXP,
            attemptXP: attemptXP,
            completionXP: completionXP,
            eligibleAttemptCount: eligibleAttempts.count,
            rewardedSessionCount: completedSessions.count,
            level: levelState.level,
            levelStartXP: levelState.startXP,
            nextLevelXP: levelState.nextXP,
            xpIntoLevel: totalXP - levelState.startXP,
            xpToNextLevel: max(0, levelState.nextXP - totalXP),
            levelProgress: levelState.progress,
            momentum: NFConsistencyEngine.makeSnapshot(
                at: date,
                attempts: uniqueAttempts,
                trainingDays: trainingDays,
                trackingStartDate: trackingStartDate,
                calendar: calendar
            ),
            accessibleLabs: accessibleLabs,
            currentWeekCoveredLabs: currentWeekCoveredLabs,
            currentWeekCoverage: currentWeekCoverage,
            milestones: milestones(
                eligibleAttempts: eligibleAttempts,
                completedSessions: completedSessions,
                accessibleLabs: accessibleLabs
            )
        )
    }

    private static func uniqueAttempts(from attempts: [AttemptRecord]) -> [AttemptRecord] {
        var winners: [UUID: AttemptRecord] = [:]
        for attempt in attempts {
            if let current = winners[attempt.id] {
                if attemptPrecedes(attempt, current) { winners[attempt.id] = attempt }
            } else {
                winners[attempt.id] = attempt
            }
        }
        return winners.values.sorted(by: attemptChronology)
    }

    /// Mirrors the durable store's deterministic projection closely enough that
    /// a temporary CloudKit duplicate cannot alter an engagement contribution.
    private static func attemptPrecedes(_ lhs: AttemptRecord, _ rhs: AttemptRecord) -> Bool {
        if lhs.submittedAt != rhs.submittedAt { return lhs.submittedAt > rhs.submittedAt }
        if lhs.shownAt != rhs.shownAt { return lhs.shownAt > rhs.shownAt }
        if lhs.scoringVersion != rhs.scoringVersion { return lhs.scoringVersion > rhs.scoringVersion }
        if lhs.response != rhs.response { return lhs.response < rhs.response }
        if lhs.deviceID != rhs.deviceID { return lhs.deviceID.uuidString < rhs.deviceID.uuidString }
        return lhs.itemID < rhs.itemID
    }

    private static func attemptChronology(_ lhs: AttemptRecord, _ rhs: AttemptRecord) -> Bool {
        if lhs.submittedAt != rhs.submittedAt { return lhs.submittedAt < rhs.submittedAt }
        return lhs.id.uuidString < rhs.id.uuidString
    }

    /// Completion is an OR-set by session identity: one completed peer wins over
    /// any number of stale incomplete checkpoints, and the earliest completion
    /// supplies the stable milestone date.
    private static func completedSessionDates(
        from checkpoints: [SessionCheckpointRecord]
    ) -> [UUID: Date] {
        checkpoints.reduce(into: [UUID: Date]()) { result, checkpoint in
            guard checkpoint.isComplete else { return }
            result[checkpoint.sessionID] = min(
                result[checkpoint.sessionID] ?? .distantFuture,
                checkpoint.updatedAt
            )
        }
    }

    private static func milestones(
        eligibleAttempts: [AttemptRecord],
        completedSessions: [UUID: Date],
        accessibleLabs: Set<TrainingLab>
    ) -> [NFForgeMilestone] {
        var unlocked: [NFForgeMilestoneCode: NFForgeMilestone] = [:]

        if let first = eligibleAttempts.first {
            unlocked[.firstAttempt] = NFForgeMilestone(
                code: .firstAttempt,
                unlockedAt: first.submittedAt,
                evidenceAttemptIDs: [first.id],
                evidenceSessionIDs: []
            )
        }

        if let firstSession = completedSessions.min(by: sessionChronology) {
            let sessionAttempts = eligibleAttempts.filter { $0.sessionID == firstSession.key }
            unlocked[.firstCompletedSession] = NFForgeMilestone(
                code: .firstCompletedSession,
                unlockedAt: firstSession.value,
                evidenceAttemptIDs: sessionAttempts.map(\.id),
                evidenceSessionIDs: [firstSession.key]
            )
        }

        if let firstTransfer = eligibleAttempts.first(where: {
            let evidenceClass = EvidenceClass(rawValue: $0.evidenceClassRaw)
            return evidenceClass == .nearTransfer || evidenceClass == .appliedTransfer
        }) {
            unlocked[.firstTransferAttempt] = NFForgeMilestone(
                code: .firstTransferAttempt,
                unlockedAt: firstTransfer.submittedAt,
                evidenceAttemptIDs: [firstTransfer.id],
                evidenceSessionIDs: []
            )
        }

        let firstAttemptByAccessibleLab = Dictionary(grouping: eligibleAttempts.compactMap { attempt in
            TrainingLab(rawValue: attempt.gameID).map { ($0, attempt) }
        }, by: { $0.0 }).compactMapValues { pairs in
            pairs.map(\.1).min(by: attemptChronology)
        }
        let orderedAccessibleLabs = accessibleLabs.sorted { $0.rawValue < $1.rawValue }
        if !orderedAccessibleLabs.isEmpty,
           orderedAccessibleLabs.allSatisfy({ firstAttemptByAccessibleLab[$0] != nil }) {
            let circuitAttempts = orderedAccessibleLabs.compactMap { firstAttemptByAccessibleLab[$0] }
            unlocked[.accessibleLabCircuit] = NFForgeMilestone(
                code: .accessibleLabCircuit,
                unlockedAt: circuitAttempts.map(\.submittedAt).max() ?? .distantPast,
                evidenceAttemptIDs: circuitAttempts.map(\.id),
                evidenceSessionIDs: []
            )
        }

        return NFForgeMilestoneCode.allCases.compactMap { unlocked[$0] }
    }

    private static func sessionChronology(
        _ lhs: Dictionary<UUID, Date>.Element,
        _ rhs: Dictionary<UUID, Date>.Element
    ) -> Bool {
        if lhs.value != rhs.value { return lhs.value < rhs.value }
        return lhs.key.uuidString < rhs.key.uuidString
    }

    private static func levelState(for totalXP: Int) -> (
        level: Int,
        startXP: Int,
        nextXP: Int,
        progress: Double
    ) {
        var level = 1
        while xpThreshold(forLevel: level + 1) <= totalXP { level += 1 }
        let startXP = xpThreshold(forLevel: level)
        let nextXP = xpThreshold(forLevel: level + 1)
        let span = max(1, nextXP - startXP)
        let progress = min(1, max(0, Double(totalXP - startXP) / Double(span)))
        return (level, startXP, nextXP, progress)
    }

    /// Level 1 begins at 0 XP, level 2 at 100, level 3 at 300, and so on.
    private static func xpThreshold(forLevel level: Int) -> Int {
        let completedLevels = Int64(max(0, level - 1))
        let threshold = 50 * completedLevels * (completedLevels + 1)
        return threshold > Int64(Int.max) ? Int.max : Int(threshold)
    }
}

import Foundation
import Observation

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

/// Immutable effective evidence crosses the projection boundary; SwiftData models
/// and original disputed results never enter the diagnostic reducer.
struct NFProgressDiagnosticObservation: Sendable, Equatable {
    let attempt: AttemptDTO
    let errorCode: String?
    let isProtected: Bool

    init(attempt: AttemptDTO, errorCode: String?, isProtected: Bool = false) {
        self.attempt = attempt
        self.isProtected = isProtected
        self.errorCode = isProtected ? nil : errorCode
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        let a = lhs.attempt, b = rhs.attempt
        func same(_ lhs: Double, _ rhs: Double) -> Bool { lhs == rhs || (lhs.isNaN && rhs.isNaN) }
        // Invalid numeric inputs still need reflexive change detection; they
        // are excluded by the worker rather than causing a render/retry loop.
        return a.id == b.id && a.lab == b.lab && a.correct == b.correct && same(a.credit, b.credit)
            && same(a.evidenceWeight, b.evidenceWeight) && a.evidenceClass == b.evidenceClass
            && a.wasSkipped == b.wasSkipped && a.responseFormatRaw == b.responseFormatRaw
            && same(a.submittedAt.timeIntervalSince1970, b.submittedAt.timeIntervalSince1970)
            && lhs.errorCode == rhs.errorCode && lhs.isProtected == rhs.isProtected
    }
}

struct NFRepeatedErrorPattern: Equatable, Sendable {
    let lab: TrainingLab
    let code: String
    let evidenceAttemptIDs: [UUID]
    let lastObservedAt: Date
}

enum NFProgressDiagnosticReducer {
    static func reduce(_ observations: [NFProgressDiagnosticObservation], at date: Date, minimumCount: Int = 2) -> [NFRepeatedErrorPattern] {
        guard date.timeIntervalSince1970.isFinite else { return [] }
        // Duplicate payloads for an identity cannot manufacture repetition. A
        // disagreement at this boundary is conservatively omitted in full.
        let byIdentity = Dictionary(grouping: observations, by: { $0.attempt.id })
        let eligible = byIdentity.values.compactMap { records -> NFProgressDiagnosticObservation? in
            guard let value = records.first else { return nil }
            let attempt = value.attempt
            guard records.allSatisfy({ other in
                let candidate = other.attempt
                return candidate.lab == attempt.lab && candidate.correct == attempt.correct
                    && candidate.credit == attempt.credit && candidate.evidenceWeight == attempt.evidenceWeight
                    && candidate.evidenceClass == attempt.evidenceClass && candidate.wasSkipped == attempt.wasSkipped
                    && candidate.responseFormatRaw == attempt.responseFormatRaw
                    && candidate.submittedAt == attempt.submittedAt && other.errorCode == value.errorCode
                    && other.isProtected == value.isProtected
            }) else { return nil }
            guard !value.isProtected,
                  ![EvidenceClass.assessmentHoldout, .nearTransfer].contains(attempt.evidenceClass),
                  !attempt.wasSkipped, !attempt.correct, attempt.evidenceWeight.isFinite,
                  attempt.evidenceWeight > 0, attempt.evidenceClass != .documentPractice,
                  !["selfcheck", "sourceselfcheck"].contains((attempt.responseFormatRaw ?? "").lowercased()),
                  attempt.credit.isFinite, (0...1).contains(attempt.credit),
                  attempt.submittedAt.timeIntervalSince1970.isFinite, attempt.submittedAt <= date,
                  let code = value.errorCode, !code.isEmpty else { return nil }
            return value
        }
        let groups = Dictionary(grouping: eligible) { value in
            "\(value.attempt.lab.rawValue)|\(value.errorCode ?? "")"
        }
        return groups.values.compactMap { records -> NFRepeatedErrorPattern? in
            guard records.count >= max(1, minimumCount), let first = records.first, let code = first.errorCode else { return nil }
            let ordered = records.sorted {
                $0.attempt.submittedAt == $1.attempt.submittedAt
                    ? $0.attempt.id.uuidString < $1.attempt.id.uuidString
                    : $0.attempt.submittedAt < $1.attempt.submittedAt
            }
            return NFRepeatedErrorPattern(lab: first.attempt.lab, code: code,
                evidenceAttemptIDs: ordered.map { $0.attempt.id }, lastObservedAt: ordered.last!.attempt.submittedAt)
        }.sorted {
            if $0.evidenceAttemptIDs.count != $1.evidenceAttemptIDs.count {
                return $0.evidenceAttemptIDs.count > $1.evidenceAttemptIDs.count
            }
            return "\($0.lab.rawValue)|\($0.code)" < "\($1.lab.rawValue)|\($1.code)"
        }
    }
}

/// A disposable projection owns no model context and cannot cancel a save.
/// Every publication is tied to the exact input generation that requested it.
@MainActor @Observable
final class NFProgressDiagnosticProjection {
    private(set) var patterns: [NFRepeatedErrorPattern] = []
    private(set) var isLoading = false
    private(set) var revision: UInt64 = 0
    @ObservationIgnored private var task: Task<Void, Never>?

    @discardableResult
    func update(_ observations: [NFProgressDiagnosticObservation], at date: Date) -> UInt64 {
        task?.cancel()
        revision &+= 1
        let ticket = revision
        // Previously included results must disappear immediately when a new
        // correction or filter invalidates their authority.
        patterns = []
        isLoading = !observations.isEmpty
        guard !observations.isEmpty else { return ticket }
        task = Task { [weak self] in
            let worker = Task.detached(priority: .userInitiated) {
                guard !Task.isCancelled else { return [NFRepeatedErrorPattern]() }
                return NFProgressDiagnosticReducer.reduce(observations, at: date, minimumCount: 1)
            }
            let result = await withTaskCancellationHandler(operation: { await worker.value }, onCancel: { worker.cancel() })
            guard !Task.isCancelled else { return }
            self?.publish(result, for: ticket)
        }
        return ticket
    }

    func publish(_ result: [NFRepeatedErrorPattern], for ticket: UInt64) {
        guard ticket == revision else { return }
        patterns = result
        isLoading = false
    }

    func cancel() {
        task?.cancel()
        task = nil
        revision &+= 1
        isLoading = false
    }
}

enum NFProgressInsightEngine {
    static let version = 2

    /// Legacy adapter for isolated callers without an AppStore disposition view.
    /// Live progress captures effective DTOs and current interpretations first.
    @MainActor
    static func makeSnapshot(
        at date: Date,
        attempts: [AttemptRecord],
        errorCodeOverrides: [UUID: String] = [:]
    ) -> NFProgressInsightSnapshot {
        makeSnapshot(at: date, observations: attempts.map {
            NFProgressDiagnosticObservation(attempt: $0.dto, errorCode: errorCodeOverrides[$0.id] ?? $0.errorCode,
                isProtected: NFReadOnlyAttemptSnapshot(attempt: $0).source == .protectedAssessment)
        })
    }

    static func makeSnapshot(at date: Date, observations: [NFProgressDiagnosticObservation]) -> NFProgressInsightSnapshot {
        present(NFProgressDiagnosticReducer.reduce(observations, at: date))
    }

    static func present(_ patterns: [NFRepeatedErrorPattern]) -> NFProgressInsightSnapshot {
        NFProgressInsightSnapshot(
            strengths: [], // Reviewed-band summaries supply supported task scope.
            repeatedErrors: patterns.filter { $0.evidenceAttemptIDs.count >= 2 }.map { pattern in
                NFProgressInsight(id: "error.\(pattern.lab.rawValue)|\(pattern.code)",
                    kind: .repeatedError, ruleID: "progress.repeated-error.v2.n2",
                    lab: pattern.lab,
                    title: NFErrorReflectionCode(rawValue: pattern.code)?.title
                        ?? NFScoringErrorCopy.title(for: pattern.code),
                    detail: NFAppLocalization.localized("This pattern appeared \(pattern.evidenceAttemptIDs.count) times in \(pattern.lab.shortTitle).", locale: NFAppLocalization.preferredLocale, comment: "Repeated-error progress insight; placeholders are occurrence count and training-lab name."),
                    evidenceAttemptIDs: pattern.evidenceAttemptIDs)
            },
            overconfidenceHotspots: [], // Legacy conditions cannot establish calibration.
            reviewsDue: [] // Versioned relation-level retention queue supplies due entries.
        )
    }
}

@MainActor
extension AppStore {
    func progressDiagnosticObservation(for attempt: AttemptRecord) -> NFProgressDiagnosticObservation {
        let protected = historyPresentation(for: .init(attempt: attempt)).source == .protectedAssessment
        return NFProgressDiagnosticObservation(attempt: effectiveAttemptDTO(attempt),
            errorCode: protected ? nil : effectiveErrorCode(for: attempt), isProtected: protected)
    }
}

enum NFConsistencyDayStatus: String, Equatable, Sendable {
    case active
    case plannedRest
    case protectedPause
    case missedPlanned
    case availableToday
}

struct NFConsistencyDay: Identifiable, Equatable, Sendable {
    let date: Date
    let status: NFConsistencyDayStatus
    var id: Date { date }
}

struct NFConsistencySnapshot: Equatable, Sendable {
    let currentActiveDayStreak: Int
    let activeDaysInWindow: Int
    let plannedDaysInWindow: Int
    let protectedPauseCount: Int
    let protectionAvailableThisWeek: Bool
    let days: [NFConsistencyDay]
}

enum NFConsistencyEngine {
    static let version = 1

    @MainActor
    static func makeSnapshot(
        at date: Date,
        attempts: [AttemptRecord],
        trainingDays: Set<Int>,
        trackingStartDate: Date? = nil,
        windowDays: Int = 28,
        calendar suppliedCalendar: Calendar = .current
    ) -> NFConsistencySnapshot {
        makeSnapshot(at: date, activities: attempts.map(NFImmutableAttemptRecordSnapshot.init),
            trainingDays: trainingDays, trackingStartDate: trackingStartDate,
            windowDays: windowDays, calendar: suppliedCalendar)
    }

    static func makeSnapshot(at date: Date, activities: [NFImmutableAttemptRecordSnapshot],
        trainingDays: Set<Int>, trackingStartDate: Date? = nil, windowDays: Int = 28,
        calendar suppliedCalendar: Calendar = .current) -> NFConsistencySnapshot {
        let calendar = suppliedCalendar
        let today = calendar.startOfDay(for: date)
        let activeDates = Set(activities.compactMap { attempt -> Date? in
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

struct NFForgeProgressSnapshot: Equatable, Sendable {
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

    @MainActor
    static func makeSnapshot(
        at date: Date,
        attempts: [AttemptRecord],
        checkpoints: [SessionCheckpointRecord],
        trainingDays: Set<Int>,
        trackingStartDate: Date? = nil,
        excludedLabs: Set<TrainingLab> = [],
        calendar: Calendar = .current
    ) -> NFForgeProgressSnapshot {
        makeSnapshot(at: date, activities: attempts.map(NFImmutableAttemptRecordSnapshot.init),
            completions: checkpoints.map { .init(sessionID: $0.sessionID, isComplete: $0.isComplete, updatedAt: $0.updatedAt) },
            trainingDays: trainingDays, trackingStartDate: trackingStartDate, excludedLabs: excludedLabs, calendar: calendar)
    }

    static func makeSnapshot(at date: Date, activities: [NFImmutableAttemptRecordSnapshot],
        completions: [NFForgeCompletionInput], trainingDays: Set<Int>, trackingStartDate: Date? = nil,
        excludedLabs: Set<TrainingLab> = [], calendar: Calendar = .current) -> NFForgeProgressSnapshot {
        let uniqueAttempts = uniqueAttempts(from: activities)
        let eligibleAttempts = uniqueAttempts.filter { !$0.wasSkipped }
        let eligibleSessionIDs = Set(eligibleAttempts.map(\.sessionID))
        let completedSessions = completedSessionDates(from: completions)
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
                activities: uniqueAttempts,
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

    private static func uniqueAttempts(from attempts: [NFImmutableAttemptRecordSnapshot]) -> [NFImmutableAttemptRecordSnapshot] {
        var winners: [UUID: NFImmutableAttemptRecordSnapshot] = [:]
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
    private static func attemptPrecedes(_ lhs: NFImmutableAttemptRecordSnapshot, _ rhs: NFImmutableAttemptRecordSnapshot) -> Bool {
        if lhs.submittedAt != rhs.submittedAt { return lhs.submittedAt > rhs.submittedAt }
        if lhs.shownAt != rhs.shownAt { return lhs.shownAt > rhs.shownAt }
        if lhs.scoringVersion != rhs.scoringVersion { return lhs.scoringVersion > rhs.scoringVersion }
        if lhs.response != rhs.response { return lhs.response < rhs.response }
        if lhs.deviceID != rhs.deviceID { return lhs.deviceID.uuidString < rhs.deviceID.uuidString }
        return lhs.itemID < rhs.itemID
    }

    private static func attemptChronology(_ lhs: NFImmutableAttemptRecordSnapshot, _ rhs: NFImmutableAttemptRecordSnapshot) -> Bool {
        if lhs.submittedAt != rhs.submittedAt { return lhs.submittedAt < rhs.submittedAt }
        return lhs.id.uuidString < rhs.id.uuidString
    }

    /// Completion is an OR-set by session identity: one completed peer wins over
    /// any number of stale incomplete checkpoints, and the earliest completion
    /// supplies the stable milestone date.
    private static func completedSessionDates(
        from checkpoints: [NFForgeCompletionInput]
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
        eligibleAttempts: [NFImmutableAttemptRecordSnapshot],
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

/// Immutable engagement inputs preserve raw activity semantics. They never
/// become reviewed evidence and contain no model or repository references.
struct NFForgeCompletionInput: Sendable {
    let sessionID: UUID
    let isComplete: Bool
    let updatedAt: Date
}

struct NFProgressDashboardEngagementInput: Sendable {
    let activities: [NFImmutableAttemptRecordSnapshot]
    let completions: [NFForgeCompletionInput]
    let trainingDays: Set<Int>
    let trackingStartDate: Date?
    let excludedLabs: Set<TrainingLab>
}

/// Derived dashboard values contain no SwiftData model or repository authority.
struct NFProgressDashboardSnapshot: Sendable {
    let summaries: [SkillSummary]
    let totalEvidence: Int
    let categories: [EvidenceClass: Int]
    let calibration: NFHistoryCalibrationSummary
    let weeklyPoints: [NFWeeklyProgressPoint]
    let patterns: [NFRepeatedErrorPattern]
    var consistency: NFConsistencySnapshot? = nil
    var forge: NFForgeProgressSnapshot? = nil
    var mentalMathMetrics: [NFMentalMathMetricKind: NFMentalMathMetricResult] = [:]
}

struct NFProgressDashboardInput: Sendable {
    let effectiveAttempts: [AttemptDTO]
    let publicAttempts: [AttemptDTO]
    let diagnostics: [NFProgressDiagnosticObservation]
    let capturedAt: Date
    let calendar: Calendar
    var engagement: NFProgressDashboardEngagementInput? = nil
    var mentalMathInputs: [NFMentalMathProgressInput] = []
}

enum NFProgressDashboardReducer {
    static func make(_ input: NFProgressDashboardInput) throws -> NFProgressDashboardSnapshot {
        try Task.checkCancellation()
        let summaries = AdaptiveEngine.reduce(input.effectiveAttempts)
        try Task.checkCancellation()
        let categories = NFProgressEvidenceProjection.categoryCounts(input.effectiveAttempts, at: input.capturedAt)
        let calibration = NFHistoryCalibrationSummary(attempts: input.effectiveAttempts)
        try Task.checkCancellation()
        let points = NFWeeklyProgressPoint.make(from: input.publicAttempts, calendar: input.calendar, at: input.capturedAt)
        try Task.checkCancellation()
        let patterns = NFProgressDiagnosticReducer.reduce(input.diagnostics, at: input.capturedAt, minimumCount: 1)
        try Task.checkCancellation()
        let metrics = NFMentalMathMetricReducer.reduce(NFMentalMathProgressAdapter.observations(
            from: input.mentalMathInputs, at: input.capturedAt))
        try Task.checkCancellation()
        let consistency = input.engagement.map { value in
            NFConsistencyEngine.makeSnapshot(at: input.capturedAt,
                activities: value.activities.filter { $0.evidenceClassRaw != EvidenceClass.documentPractice.rawValue },
                trainingDays: value.trainingDays, trackingStartDate: value.trackingStartDate, calendar: input.calendar)
        }
        try Task.checkCancellation()
        let forge = input.engagement.map { value in
            NFForgeProgressEngine.makeSnapshot(at: input.capturedAt, activities: value.activities,
                completions: value.completions, trainingDays: value.trainingDays,
                trackingStartDate: value.trackingStartDate, excludedLabs: value.excludedLabs, calendar: input.calendar)
        }
        try Task.checkCancellation()
        return .init(summaries: summaries,
            totalEvidence: input.effectiveAttempts.filter { !$0.wasSkipped && $0.evidenceWeight > 0 }.count,
            categories: categories, calibration: calibration, weeklyPoints: points, patterns: patterns,
            consistency: consistency, forge: forge, mentalMathMetrics: metrics)
    }
}

/// A newer filter, import or correction invalidates the previous result before
/// work starts. Cancellation has no relationship to durable session writes.
@MainActor @Observable
final class NFProgressDashboardProjection {
    private(set) var snapshot: NFProgressDashboardSnapshot?
    private(set) var isLoading = false
    @ObservationIgnored private var generation = UUID()
    @ObservationIgnored private var activeWorker: Task<NFProgressDashboardSnapshot, Error>?

    func update(_ input: NFProgressDashboardInput,
        compute: @escaping @Sendable (NFProgressDashboardInput) throws -> NFProgressDashboardSnapshot = NFProgressDashboardReducer.make) async {
        activeWorker?.cancel()
        let ticket = UUID()
        generation = ticket
        snapshot = nil
        isLoading = true
        let worker = Task.detached(priority: .userInitiated) { try compute(input) }
        activeWorker = worker
        let result = await withTaskCancellationHandler(operation: { await worker.result }, onCancel: { worker.cancel() })
        guard generation == ticket else { return }
        activeWorker = nil
        isLoading = false
        guard !Task.isCancelled, case let .success(value) = result else { return }
        snapshot = value
    }

    func cancel() {
        activeWorker?.cancel()
        activeWorker = nil
        generation = UUID()
        snapshot = nil
        isLoading = false
    }
}

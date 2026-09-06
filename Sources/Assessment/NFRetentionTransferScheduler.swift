import Foundation

// MARK: - Retention memory state

struct NFRetentionItemState: Codable, Equatable, Sendable, Identifiable {
    let id: String
    let templateFamily: String
    let lab: TrainingLab
    let lastReviewedAt: Date?
    let stabilityDays: Double
    let repetitions: Int
    let lapses: Int
    let exposedSeeds: Set<UInt64>
    let lastRepresentationID: String?

    init(
        id: String,
        templateFamily: String,
        lab: TrainingLab,
        lastReviewedAt: Date? = nil,
        stabilityDays: Double = 1,
        repetitions: Int = 0,
        lapses: Int = 0,
        exposedSeeds: Set<UInt64> = [],
        lastRepresentationID: String? = nil
    ) {
        self.id = id
        self.templateFamily = templateFamily
        self.lab = lab
        self.lastReviewedAt = lastReviewedAt
        self.stabilityDays = max(0.25, stabilityDays.isFinite ? stabilityDays : 1)
        self.repetitions = max(0, repetitions)
        self.lapses = max(0, lapses)
        self.exposedSeeds = exposedSeeds
        self.lastRepresentationID = lastRepresentationID
    }
}

/// Values copied at the store boundary after content/conflict dispositions.
/// A legacy score can support a reminder without proving independent retention.
struct NFCompatibilityReminderObservation: Equatable, Sendable {
    let id: UUID
    let memoryItemID: String
    let templateFamily: String
    let lab: TrainingLab
    let itemID: String
    let semanticID: String?
    let seed: UInt64
    let representationID: String?
    let submittedAt: Date
    let credit: Double
    let correct: Bool
    let evidenceClass: EvidenceClass
    let evidenceWeight: Double
    let wasSkipped: Bool
    let hintCount: Int
    let responseFormatRaw: String?

    init(attempt: AttemptDTO, memoryItemID: String, templateFamily: String,
         seed: UInt64, representationID: String?, semanticID: String? = nil) {
        id = attempt.id; self.memoryItemID = memoryItemID; self.templateFamily = templateFamily
        lab = attempt.lab; itemID = attempt.itemID; self.semanticID = semanticID
        self.seed = seed; self.representationID = representationID
        submittedAt = attempt.submittedAt; credit = attempt.credit; correct = attempt.correct
        evidenceClass = attempt.evidenceClass; evidenceWeight = attempt.evidenceWeight
        wasSkipped = attempt.wasSkipped; hintCount = attempt.hintCount
        responseFormatRaw = attempt.responseFormatRaw
    }
}

enum NFCompatibilityReminderPolicy {
    static let policyVersion = "LegacyPracticeReminderV1"

    /// The compatibility lane has only a one-day reminder, never demonstrated
    /// retention or an inferred band. Reviewed interval progression belongs to
    /// NFEditorialRetentionPolicy with its explicit independent observations.
    static func reduce(_ inputs: [NFCompatibilityReminderObservation], at date: Date,
                       calendar: Calendar) -> [NFRetentionItemState] {
        reduceWithOrigins(inputs, at: date, calendar: calendar).map(\.state)
    }

    static func reduceWithOrigins(_ inputs: [NFCompatibilityReminderObservation], at date: Date,
                                  calendar: Calendar) -> [NFCompatibilityReminderOrigin] {
        guard date.timeIntervalSince1970.isFinite else { return [] }
        // Conflicting duplicate identities cannot acquire authority from input
        // order. Byte-equivalent repeats contribute at most once.
        let unique = Dictionary(grouping: inputs, by: \.id).values.compactMap { copies in
            guard let first = copies.first, copies.allSatisfy({ $0 == first }) else { return nil as NFCompatibilityReminderObservation? }
            return first
        }
        let ordinary = unique.filter {
            !$0.memoryItemID.isEmpty && !$0.templateFamily.isEmpty && !$0.itemID.isEmpty
                && $0.submittedAt.timeIntervalSince1970.isFinite && $0.submittedAt <= date
                && ($0.evidenceClass == .practice || $0.evidenceClass == .retention)
        }
        let groups = Dictionary(grouping: ordinary, by: \.memoryItemID)
        return groups.keys.sorted().compactMap { key in
            let records = (groups[key] ?? []).sorted {
                $0.submittedAt == $1.submittedAt ? $0.id.uuidString < $1.id.uuidString : $0.submittedAt < $1.submittedAt
            }
            guard let first = records.first,
                  records.allSatisfy({ $0.lab == first.lab && $0.templateFamily == first.templateFamily }) else { return nil }
            var anchor: NFCompatibilityReminderObservation?
            var exposedIdentities: Set<String> = []
            var exposedSeeds: Set<UInt64> = []
            for record in records {
                exposedSeeds.insert(record.seed)
                let identity = record.semanticID.map { "semantic:\($0)" }
                    ?? NFSelectionReservationPolicy.identity(["legacy-item", record.itemID, String(record.seed)])
                let fresh = exposedIdentities.insert(identity).inserted
                let format = record.responseFormatRaw?.lowercased().filter { $0.isLetter || $0.isNumber }
                guard record.evidenceWeight.isFinite, record.evidenceWeight > 0,
                      record.credit.isFinite, record.credit == 1, record.correct,
                      !record.wasSkipped, record.hintCount == 0,
                      !["selfcheck", "sourceselfcheck", "selfreported", "revealed", "solutionrevealed"].contains(format ?? "") else { continue }
                guard let previous = anchor else { anchor = record; continue }
                let due = calendar.date(byAdding: .day, value: 1, to: previous.submittedAt)
                // Early or familiar practice never postpones an existing due
                // reminder. A due fresh full response refreshes the same one-day
                // reminder; it does not promote an unknown-condition result.
                if fresh, let due, record.submittedAt >= due { anchor = record }
            }
            guard let anchor else { return nil }
            return NFCompatibilityReminderOrigin(state: NFRetentionItemState(
                id: key, templateFamily: first.templateFamily, lab: first.lab,
                lastReviewedAt: anchor.submittedAt, stabilityDays: 1, repetitions: 1, lapses: 0,
                exposedSeeds: exposedSeeds, lastRepresentationID: anchor.representationID), anchorAttemptID: anchor.id)
        }
    }
}

struct NFRetentionReviewOutcome: Codable, Equatable, Sendable {
    let reviewedAt: Date
    let correct: Bool
    let confidence: ConfidenceLevel
    let itemDifficulty: Double
    let seed: UInt64
    let representationID: String
}

struct NFRetentionAssignment: Codable, Equatable, Sendable, Identifiable {
    let id: String
    let memoryItemID: String
    let templateFamily: String
    let lab: TrainingLab
    let alternateSeed: UInt64
    let predictedRetention: Double
    let urgency: Double
    let scheduledAt: Date
    let requiresRepresentationShift: Bool
    let priorRepresentationID: String?
}

/// The immutable review identity carried from scheduling through generation
/// and persistence. Older plans stored only `memoryItemID`; `legacy` provides
/// a stable local seed for those payloads without rewriting their plan ID.
struct NFRetentionReviewTarget: Codable, Equatable, Hashable, Sendable {
    let memoryItemID: String
    let templateFamily: String
    let alternateSeed: UInt64
    let requiresRepresentationShift: Bool
    let priorRepresentationID: String?

    init(
        memoryItemID: String,
        templateFamily: String,
        alternateSeed: UInt64,
        requiresRepresentationShift: Bool,
        priorRepresentationID: String?
    ) {
        self.memoryItemID = memoryItemID
        self.templateFamily = templateFamily
        self.alternateSeed = alternateSeed
        self.requiresRepresentationShift = requiresRepresentationShift
        self.priorRepresentationID = priorRepresentationID
    }

    static func legacy(memoryItemID: String, fallbackSeed: UInt64? = nil) -> Self {
        NFRetentionReviewTarget(
            memoryItemID: memoryItemID,
            templateFamily: memoryItemID,
            alternateSeed: fallbackSeed ?? NFStableDeterminism.hash64("legacy-retention|\(memoryItemID)"),
            requiresRepresentationShift: false,
            priorRepresentationID: nil
        )
    }
}

extension NFRetentionAssignment {
    var reviewTarget: NFRetentionReviewTarget {
        NFRetentionReviewTarget(
            memoryItemID: memoryItemID,
            templateFamily: templateFamily,
            alternateSeed: alternateSeed,
            requiresRepresentationShift: requiresRepresentationShift,
            priorRepresentationID: priorRepresentationID
        )
    }
}

enum NFRetentionRepresentation {
    static func identifier(for exercise: NFExercise) -> String {
        if let spatial = exercise.representations.lazy.compactMap({ representation -> NFSpatialRepresentationMetadata? in
            guard case let .spatial(metadata) = representation else { return nil }
            return metadata
        }).first {
            return spatial.difficultyParameters.responseMode.rawValue
        }
        return switch exercise.interaction {
        case .numeric: NFAssessmentItemFormat.numericEntry.rawValue
        case .singleChoice, .multipleChoice: NFAssessmentItemFormat.singleChoice.rawValue
        case .orderedSteps: NFAssessmentItemFormat.orderedSteps.rawValue
        case .shortText: "shortText"
        case .selfCheck: "selfCheck"
        case .claimEvidence: NFAssessmentItemFormat.claimEvidence.rawValue
        case .logicState: NFAssessmentItemFormat.stateTrace.rawValue
        }
    }

    static func alternateFormat(
        for lab: TrainingLab,
        priorRepresentationID: String?
    ) -> NFAssessmentItemFormat? {
        let prior = priorRepresentationID?.lowercased() ?? ""
        let wasNumeric = prior == "numeric" || prior == NFAssessmentItemFormat.numericEntry.rawValue.lowercased()
        let wasChoice = prior == "singlechoice" || prior == "multiplechoice"
        let wasOrdered = prior == NFAssessmentItemFormat.orderedSteps.rawValue.lowercased()

        return switch lab {
        case .mentalMath, .quantitative:
            wasNumeric ? .singleChoice : .numericEntry
        case .spatial:
            prior == NFAssessmentItemFormat.diagramMatch.rawValue.lowercased()
                ? .singleChoice
                : .diagramMatch
        case .scientificReasoning:
            if prior == NFAssessmentItemFormat.claimEvidence.rawValue.lowercased() {
                .orderedSteps
            } else if wasOrdered || wasChoice {
                .claimEvidence
            } else {
                .singleChoice
            }
        case .logicDebugging:
            if prior == NFAssessmentItemFormat.stateTrace.rawValue.lowercased() {
                .orderedSteps
            } else if wasOrdered || wasChoice {
                .stateTrace
            } else {
                .singleChoice
            }
        case .retrieval:
            wasOrdered ? .singleChoice : .orderedSteps
        case .transfer:
            if prior == NFAssessmentItemFormat.claimEvidence.rawValue.lowercased() {
                .orderedSteps
            } else if wasOrdered || wasNumeric {
                .singleChoice
            } else {
                .claimEvidence
            }
        }
    }
}

enum NFRetentionScheduler {
    static let policyVersion = 3
    // Compatibility sentinel only; not a probability of remembering.
    static let targetRetention = 0.85

    static func predictedRetention(
        for state: NFRetentionItemState,
        at date: Date,
        calendar: Calendar
    ) -> Double {
        // Kept for archive compatibility. This binary due marker must not be
        // displayed as a memory probability; scheduling uses explicit local days.
        guard state.lastReviewedAt != nil else { return 0 }
        return date >= nextReviewDate(for: state, after: state.lastReviewedAt!, calendar: calendar) ? 0 : 1
    }

    static func urgency(for state: NFRetentionItemState, at date: Date, calendar: Calendar) -> Double {
        guard let reviewed = state.lastReviewedAt else { return 1 }
        let due = nextReviewDate(for: state, after: reviewed, calendar: calendar)
        return date >= due ? 1 + max(0, date.timeIntervalSince(due)) / 86_400 : 0
    }

    static func nextReviewDate(for state: NFRetentionItemState, after date: Date, calendar: Calendar) -> Date {
        let rung = min(EditorialBandEvidenceV1.intervalDays.count - 1, max(0, state.repetitions - 1))
        return calendar.date(byAdding: .day, value: EditorialBandEvidenceV1.intervalDays[rung], to: date) ?? date
    }

    static func schedule(
        states: [NFRetentionItemState],
        at date: Date,
        maximumItems: Int,
        calendar: Calendar
    ) -> [NFRetentionAssignment] {
        guard maximumItems > 0 else { return [] }
        return states
            .map { state in
                let retention = predictedRetention(for: state, at: date, calendar: calendar)
                return makeAssignment(state: state, date: date, predictedRetention: retention, calendar: calendar)
            }
            .filter { $0.predictedRetention <= targetRetention }
            .sorted { lhs, rhs in
                if abs(lhs.urgency - rhs.urgency) > 0.000_000_001 {
                    return lhs.urgency > rhs.urgency
                }
                if lhs.scheduledAt != rhs.scheduledAt { return lhs.scheduledAt < rhs.scheduledAt }
                return lhs.memoryItemID < rhs.memoryItemID
            }
            .prefix(maximumItems)
            .map { $0 }
    }

    static func updatedState(
        _ state: NFRetentionItemState,
        after outcome: NFRetentionReviewOutcome,
        calendar: Calendar
    ) -> NFRetentionItemState {
        // Confidence and legacy nominal difficulty never alter a review interval.
        let due = state.lastReviewedAt.map { nextReviewDate(for: state, after: $0, calendar: calendar) }
        let fresh = !state.exposedSeeds.contains(outcome.seed)
        let canAdvance = fresh && (due == nil || outcome.reviewedAt >= due!)
        let repetitions = outcome.correct && canAdvance ? state.repetitions + 1 : state.repetitions
        let updatedStability = Double(EditorialBandEvidenceV1.intervalDays[min(4, max(0, repetitions - 1))])
        let updatedLapses = state.lapses + (outcome.correct ? 0 : 1)

        var exposures = state.exposedSeeds
        exposures.insert(outcome.seed)
        return NFRetentionItemState(
            id: state.id,
            templateFamily: state.templateFamily,
            lab: state.lab,
            lastReviewedAt: canAdvance ? outcome.reviewedAt : state.lastReviewedAt,
            stabilityDays: updatedStability,
            repetitions: repetitions,
            lapses: updatedLapses,
            exposedSeeds: exposures,
            lastRepresentationID: outcome.representationID
        )
    }

    private static func makeAssignment(
        state: NFRetentionItemState,
        date: Date,
        predictedRetention: Double,
        calendar: Calendar
    ) -> NFRetentionAssignment {
        let dayOrdinal = Int(floor(date.timeIntervalSince1970 / 86_400))
        var probe = 0
        var seed: UInt64
        repeat {
            seed = NFStableDeterminism.hash64(
                "retention|\(policyVersion)|\(state.id)|\(state.repetitions)|\(dayOrdinal)|\(probe)"
            )
            probe += 1
        } while state.exposedSeeds.contains(seed)

        return NFRetentionAssignment(
            id: "nf.retention.v\(policyVersion).\(state.id).\(String(seed, radix: 16))",
            memoryItemID: state.id,
            templateFamily: state.templateFamily,
            lab: state.lab,
            alternateSeed: seed,
            predictedRetention: predictedRetention,
            urgency: urgency(for: state, at: date, calendar: calendar),
            scheduledAt: date,
            requiresRepresentationShift: false,
            priorRepresentationID: state.lastRepresentationID
        )
    }
}

// MARK: - Weekly transfer mission

typealias NFWeeklyTransferMissionKind = NFTransferChallengeKind

struct NFWeeklyTransferCandidate: Codable, Equatable, Sendable {
    let lab: TrainingLab
    let skillID: String
    let priority: Double
    let transferGap: Double
}

struct NFWeeklyTransferState: Codable, Equatable, Sendable {
    let completedMissionIDs: Set<String>
    let deferredUntilByMissionID: [String: Date]
    /// The first mission materialized for a learner week is immutable. Without
    /// this snapshot, newly recorded evidence can silently change the mission's
    /// labs and skills while retaining the same mission identity.
    let pinnedMissionByWeekKey: [String: NFWeeklyTransferMission]

    init(
        completedMissionIDs: Set<String> = [],
        deferredUntilByMissionID: [String: Date] = [:],
        pinnedMissionByWeekKey: [String: NFWeeklyTransferMission] = [:]
    ) {
        self.completedMissionIDs = completedMissionIDs
        self.deferredUntilByMissionID = deferredUntilByMissionID
        self.pinnedMissionByWeekKey = pinnedMissionByWeekKey
    }

    private enum CodingKeys: String, CodingKey {
        case completedMissionIDs
        case deferredUntilByMissionID
        case pinnedMissionByWeekKey
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        completedMissionIDs = try container.decodeIfPresent(
            Set<String>.self,
            forKey: .completedMissionIDs
        ) ?? []
        deferredUntilByMissionID = try container.decodeIfPresent(
            [String: Date].self,
            forKey: .deferredUntilByMissionID
        ) ?? [:]
        pinnedMissionByWeekKey = try container.decodeIfPresent(
            [String: NFWeeklyTransferMission].self,
            forKey: .pinnedMissionByWeekKey
        ) ?? [:]
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(completedMissionIDs, forKey: .completedMissionIDs)
        try container.encode(deferredUntilByMissionID, forKey: .deferredUntilByMissionID)
        try container.encode(pinnedMissionByWeekKey, forKey: .pinnedMissionByWeekKey)
    }

    func completing(missionID: String) -> NFWeeklyTransferState {
        var completed = completedMissionIDs
        completed.insert(missionID)
        return NFWeeklyTransferState(
            completedMissionIDs: completed,
            deferredUntilByMissionID: deferredUntilByMissionID,
            pinnedMissionByWeekKey: pinnedMissionByWeekKey
        )
    }

    func deferring(missionID: String, until date: Date) -> NFWeeklyTransferState {
        var deferrals = deferredUntilByMissionID
        deferrals[missionID] = date
        return NFWeeklyTransferState(
            completedMissionIDs: completedMissionIDs,
            deferredUntilByMissionID: deferrals,
            pinnedMissionByWeekKey: pinnedMissionByWeekKey
        )
    }

    func pinning(_ mission: NFWeeklyTransferMission) -> NFWeeklyTransferState {
        var missions = pinnedMissionByWeekKey
        missions[mission.weekKey] = missions[mission.weekKey] ?? mission
        return NFWeeklyTransferState(
            completedMissionIDs: completedMissionIDs,
            deferredUntilByMissionID: deferredUntilByMissionID,
            pinnedMissionByWeekKey: missions
        )
    }
}

struct NFWeeklyTransferMission: Codable, Equatable, Sendable, Identifiable {
    let id: String
    let weekKey: String
    let seed: UInt64
    let kind: NFWeeklyTransferMissionKind
    let labs: [TrainingLab]
    let skillIDs: [String]
    let estimatedMinutes: Int
    let evidenceClass: EvidenceClass
    let reasons: [PrescriptionReason]
    let requiredTransferDimensions: [String]

    var exerciseTransferBrief: NFExerciseTransferBrief {
        NFExerciseTransferBrief(
            missionID: id,
            seed: seed,
            kind: kind,
            labs: labs,
            skillIDs: skillIDs,
            requiredDimensions: requiredTransferDimensions
        )
    }
}

enum NFWeeklyTransferScheduler {
    static let policyVersion = 1

    static func mission(
        profileID: UUID,
        date: Date,
        activeDaysThisWeek: Int,
        candidates: [NFWeeklyTransferCandidate],
        state: NFWeeklyTransferState = NFWeeklyTransferState(),
        calendar: Calendar = .current
    ) -> NFWeeklyTransferMission? {
        guard activeDaysThisWeek > 0 else { return nil }
        let weekKey = localWeekKey(for: date, calendar: calendar)
        let seed = NFStableDeterminism.hash64(
            "weekly-transfer|\(policyVersion)|\(profileID.uuidString)|\(weekKey)"
        )
        let missionID = "nf.transfer.weekly.v\(policyVersion).\(weekKey).\(String(seed, radix: 16))"
        guard !state.completedMissionIDs.contains(missionID) else { return nil }
        if let deferredUntil = state.deferredUntilByMissionID[missionID], deferredUntil > date {
            return nil
        }
        if let pinned = state.pinnedMissionByWeekKey[weekKey] {
            return pinned
        }

        let ranked = candidates.sorted { lhs, rhs in
            if abs(lhs.transferGap - rhs.transferGap) > 0.000_000_001 {
                return lhs.transferGap > rhs.transferGap
            }
            if abs(lhs.priority - rhs.priority) > 0.000_000_001 {
                return lhs.priority > rhs.priority
            }
            if lhs.lab.rawValue != rhs.lab.rawValue { return lhs.lab.rawValue < rhs.lab.rawValue }
            return lhs.skillID < rhs.skillID
        }

        var selectedLabs: [TrainingLab] = []
        var selectedSkillIDs: [String] = []
        for candidate in ranked where !selectedLabs.contains(candidate.lab) {
            selectedLabs.append(candidate.lab)
            selectedSkillIDs.append(candidate.skillID)
            if selectedLabs.count == 2 { break }
        }

        let fallbacks: [TrainingLab] = [
            .scientificReasoning, .quantitative, .logicDebugging, .mentalMath, .spatial, .retrieval
        ]
        for lab in fallbacks where selectedLabs.count < 2 && !selectedLabs.contains(lab) {
            selectedLabs.append(lab)
            selectedSkillIDs.append(lab.skillID)
        }

        let kinds = NFWeeklyTransferMissionKind.allCases
        let kind = kinds[Int(seed % UInt64(kinds.count))]
        return NFWeeklyTransferMission(
            id: missionID,
            weekKey: weekKey,
            seed: seed,
            kind: kind,
            labs: selectedLabs,
            skillIDs: selectedSkillIDs,
            estimatedMinutes: 8,
            evidenceClass: .appliedTransfer,
            reasons: [.transferGap, .representationCoverage],
            requiredTransferDimensions: transferDimensions(for: kind)
        )
    }

    private static func localWeekKey(for date: Date, calendar: Calendar) -> String {
        let components = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        return String(
            format: "%04d-W%02d",
            components.yearForWeekOfYear ?? 0,
            components.weekOfYear ?? 0
        )
    }

    private static func transferDimensions(for kind: NFWeeklyTransferMissionKind) -> [String] {
        switch kind {
        case .figureAndClaimAudit:
            ["representation", "response_type", "field"]
        case .numericalSimulationDebug:
            ["surface_context", "interacting_variables", "response_type"]
        case .causalStructureComparison:
            ["field", "surface_context", "interacting_variables"]
        case .abstractReconstruction:
            ["representation", "delay", "surface_context"]
        case .multiRepresentationTransform:
            ["representation", "stimulus_category", "field"]
        }
    }
}

/// Scheduling preferences never change the immutable review outcome or rung.
/// The origin is copied from the same reducer that chooses the success anchor.
struct NFCompatibilityReminderOrigin: Equatable, Sendable {
    let state: NFRetentionItemState
    let anchorAttemptID: UUID
}

struct NFReviewDeferral: Codable, Equatable, Sendable, Identifiable {
    var schemaVersion = 1
    let profileID: UUID
    let memoryItemID: String
    let templateFamily: String
    let lab: TrainingLab
    let anchorAttemptID: UUID
    let anchorReviewedAt: Date
    let requestedAt: Date
    let deferredUntil: Date
    let timeZoneIdentifier: String
    let dayBoundaryHour: Int

    var id: String {
        NFSelectionReservationPolicy.identity([profileID.uuidString, memoryItemID])
    }

    var isSupported: Bool {
        guard schemaVersion == 1, !memoryItemID.isEmpty, memoryItemID.utf8.count <= 1_024,
              !templateFamily.isEmpty, templateFamily.utf8.count <= 1_024,
              anchorReviewedAt.timeIntervalSince1970.isFinite,
              requestedAt.timeIntervalSince1970.isFinite, deferredUntil.timeIntervalSince1970.isFinite,
              anchorReviewedAt <= requestedAt, deferredUntil > requestedAt,
              deferredUntil.timeIntervalSince(requestedAt) <= 48 * 3_600,
              (0...12).contains(dayBoundaryHour),
              let zone = TimeZone(identifier: timeZoneIdentifier) else { return false }
        // Captured local-day boundaries are absolute dates. Travelling later
        // does not move the accepted return instant or repeat a deferral.
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        return deferredUntil == NFPlanBoundaryContext.make(at: requestedAt,
            dayBoundaryHour: dayBoundaryHour, calendar: calendar).nextBoundary
    }

    func matches(_ origin: NFCompatibilityReminderOrigin, profileID: UUID) -> Bool {
        isSupported && self.profileID == profileID && memoryItemID == origin.state.id
            && templateFamily == origin.state.templateFamily && lab == origin.state.lab
            && anchorAttemptID == origin.anchorAttemptID && anchorReviewedAt == origin.state.lastReviewedAt
    }
}

struct NFReviewDueEntry: Equatable, Sendable, Identifiable {
    let origin: NFCompatibilityReminderOrigin
    let naturalDueAt: Date
    let dueAt: Date
    let deferral: NFReviewDeferral?
    var id: String { origin.state.id }
    func isDue(at date: Date) -> Bool { date.timeIntervalSince1970.isFinite && date >= dueAt }
    func isDeferred(at date: Date) -> Bool {
        deferral != nil && naturalDueAt <= date && date < dueAt
    }
}

enum NFReviewDeferralPolicy {
    static let maximumRecords = 10_000

    static func supports(_ records: [NFReviewDeferral]) -> Bool {
        records.count <= maximumRecords && Set(records.map(\.id)).count == records.count
            && records.allSatisfy(\.isSupported)
    }

    static func project(origins: [NFCompatibilityReminderOrigin], profileID: UUID,
                        deferrals: [NFReviewDeferral], calendar: Calendar) -> [NFReviewDueEntry] {
        // A corrupt/future preference cannot silently suppress reminders.
        // The store separately displays metadata recovery and forbids writes.
        let accepted = supports(deferrals) ? deferrals : []
        let byID = Dictionary(uniqueKeysWithValues: accepted.map { ($0.id, $0) })
        return origins.compactMap { origin in
            guard let anchor = origin.state.lastReviewedAt,
                  anchor.timeIntervalSince1970.isFinite else { return nil }
            let natural = NFRetentionScheduler.nextReviewDate(for: origin.state, after: anchor, calendar: calendar)
            guard natural.timeIntervalSince1970.isFinite else { return nil }
            let key = NFSelectionReservationPolicy.identity([profileID.uuidString, origin.state.id])
            let deferral = byID[key].flatMap { $0.matches(origin, profileID: profileID) ? $0 : nil }
            return NFReviewDueEntry(origin: origin, naturalDueAt: natural,
                dueAt: max(natural, deferral?.deferredUntil ?? natural), deferral: deferral)
        }.sorted { $0.dueAt == $1.dueAt ? $0.id < $1.id : $0.dueAt < $1.dueAt }
    }

    static func make(entry: NFReviewDueEntry, profileID: UUID, at date: Date,
                     dayBoundaryHour: Int, calendar: Calendar) -> NFReviewDeferral? {
        guard entry.isDue(at: date), let anchor = entry.origin.state.lastReviewedAt else { return nil }
        let boundary = NFPlanBoundaryContext.make(at: date, dayBoundaryHour: dayBoundaryHour, calendar: calendar)
        let result = NFReviewDeferral(profileID: profileID, memoryItemID: entry.id,
            templateFamily: entry.origin.state.templateFamily, lab: entry.origin.state.lab,
            anchorAttemptID: entry.origin.anchorAttemptID, anchorReviewedAt: anchor,
            requestedAt: date, deferredUntil: boundary.nextBoundary,
            timeZoneIdentifier: boundary.timeZoneIdentifier, dayBoundaryHour: boundary.dayBoundaryHour)
        return result.isSupported ? result : nil
    }
}

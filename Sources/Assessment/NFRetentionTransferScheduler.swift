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
    static let policyVersion = 1
    static let targetRetention = 0.85

    static func predictedRetention(
        for state: NFRetentionItemState,
        at date: Date
    ) -> Double {
        guard let lastReviewedAt = state.lastReviewedAt else { return 0 }
        let elapsedDays = max(0, date.timeIntervalSince(lastReviewedAt) / 86_400)
        return NFStableDeterminism.clampedUnit(exp(-elapsedDays / max(0.25, state.stabilityDays)))
    }

    static func urgency(
        for state: NFRetentionItemState,
        at date: Date
    ) -> Double {
        1 - predictedRetention(for: state, at: date)
    }

    static func nextReviewDate(
        for state: NFRetentionItemState,
        after date: Date
    ) -> Date {
        let intervalDays = -max(0.25, state.stabilityDays) * log(targetRetention)
        return date.addingTimeInterval(intervalDays * 86_400)
    }

    static func schedule(
        states: [NFRetentionItemState],
        at date: Date,
        maximumItems: Int
    ) -> [NFRetentionAssignment] {
        guard maximumItems > 0 else { return [] }
        return states
            .map { state in
                let retention = predictedRetention(for: state, at: date)
                return makeAssignment(state: state, date: date, predictedRetention: retention)
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
        after outcome: NFRetentionReviewOutcome
    ) -> NFRetentionItemState {
        let difficulty = NFStableDeterminism.clampedUnit(outcome.itemDifficulty)
        let confidenceAdjustment: Double
        switch outcome.confidence {
        case .guessing: confidenceAdjustment = -0.12
        case .uncertain: confidenceAdjustment = -0.04
        case .fairlyConfident: confidenceAdjustment = 0.06
        case .certain: confidenceAdjustment = 0.12
        }

        let updatedStability: Double
        let updatedLapses: Int
        if outcome.correct {
            let growth = 1.40 + confidenceAdjustment + 0.20 * (1 - difficulty)
            updatedStability = max(0.5, state.stabilityDays * max(1.08, growth))
            updatedLapses = state.lapses
        } else {
            updatedStability = max(0.5, state.stabilityDays * (0.48 + 0.12 * (1 - difficulty)))
            updatedLapses = state.lapses + 1
        }

        var exposures = state.exposedSeeds
        exposures.insert(outcome.seed)
        return NFRetentionItemState(
            id: state.id,
            templateFamily: state.templateFamily,
            lab: state.lab,
            lastReviewedAt: outcome.reviewedAt,
            stabilityDays: updatedStability,
            repetitions: state.repetitions + 1,
            lapses: updatedLapses,
            exposedSeeds: exposures,
            lastRepresentationID: outcome.representationID
        )
    }

    private static func makeAssignment(
        state: NFRetentionItemState,
        date: Date,
        predictedRetention: Double
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
            urgency: 1 - predictedRetention,
            scheduledAt: date,
            requiresRepresentationShift: state.repetitions > 0,
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

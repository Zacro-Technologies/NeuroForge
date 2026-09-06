import Foundation

/// Editorial demand labels describe a reviewed task, never a learner or a latent ability scale.
enum NFEditorialBand: String, Codable, CaseIterable, Comparable, Sendable {
    case b1 = "B1", b2 = "B2", b3 = "B3", b4 = "B4"
    var ordinal: Int { Self.allCases.firstIndex(of: self)! + 1 }
    var title: String {
        switch self { case .b1: "Foundation"; case .b2: "Developing"; case .b3: "Challenging"; case .b4: "Advanced" }
    }
    var lower: Self? { Self.allCases.first { $0.ordinal == ordinal - 1 } }
    var higher: Self? { Self.allCases.first { $0.ordinal == ordinal + 1 } }
    static func < (lhs: Self, rhs: Self) -> Bool { lhs.ordinal < rhs.ordinal }
}

struct NFDemandVector: Codable, Equatable, Sendable {
    let reasoningSteps: Int
    let quantityDomain: [String: String]
    let representationMappings: [String]
    let misconceptionClasses: [String]
    let abstraction: String
    let relevantGivens: Int
    let irrelevantGivens: Int
    let missingGivens: Int
    let scaffoldConditionID: String
    let prerequisiteConceptIDs: [String]
}

struct NFExpectedDurationRange: Codable, Equatable, Sendable {
    let minimumSeconds: Double
    let maximumSeconds: Double
    var isValid: Bool { minimumSeconds.isFinite && maximumSeconds.isFinite && minimumSeconds > 0 && maximumSeconds >= minimumSeconds }
    var medianSeconds: Double { minimumSeconds + (maximumSeconds - minimumSeconds) / 2 }
}

enum NFEditorialCalibrationStatus: String, Codable, Sendable {
    case editorial, pilotObserved, empiricallyCalibrated
}

/// Catalog admission supplies this record. A requested band or legacy difficulty float is never a constructor input.
struct NFEditorialDemandRecord: Codable, Equatable, Sendable {
    let objectiveID: String
    let familyID: String
    let structureID: String
    let semanticFingerprint: String
    let editorialBand: NFEditorialBand
    let demandVector: NFDemandVector
    let bandContractVersion: String
    let calibrationStatus: NFEditorialCalibrationStatus
    let calibrationVersion: String?
    let independentEligible: Bool
    let protectedEligible: Bool
    let assistancePolicyID: String
    let answerContractVersion: String
    let expectedDurationRange: NFExpectedDurationRange?
    let representationIDs: [String]
    let prerequisiteObjectiveIDs: [String]
    var scoringComparabilityID: String? = nil
    var stimulusComparabilityID: String? = nil
    var localeComparabilityID: String? = nil
    var solutionExposureID: String? = nil
    var requiredDemonstrationFormatIDs: Set<String> = []
    var reviewedFluencyEligible: Bool = false
    var reviewContract: NFEditorialReviewContract? = nil
    var goalAlignment: NFEditorialGoalAlignment? = nil

    var hasRequiredIdentity: Bool {
        [objectiveID, familyID, structureID, semanticFingerprint, bandContractVersion,
         assistancePolicyID, answerContractVersion].allSatisfy { !$0.isEmpty }
            && !representationIDs.isEmpty && demandVector.reasoningSteps > 0
            && demandVector.relevantGivens >= 0 && demandVector.irrelevantGivens >= 0
            && demandVector.missingGivens >= 0
            && (calibrationStatus == .editorial || calibrationVersion?.isEmpty == false)
            && reviewContract?.isSupported != false
            && goalAlignment?.isSupported != false
            && (goalAlignment.map { $0.objectiveID == objectiveID } ?? true)
    }
}

enum NFEditorialTimingMode: String, Codable, Sendable { case untimed, elapsedOnly, timedFluency }
enum NFEditorialEvidenceLane: String, Codable, Sendable { case practice, protectedCheck, retention, transfer, personalStudy }
enum NFEditorialCollectionPolicy: String, Codable, Sendable { case requiredProtected, requiredCalibration, optionalPractice }
enum NFEditorialAttemptOutcome: String, Codable, Sendable { case scored, skipped, abandoned, replaced, selfReported, invalid }
enum NFEditorialValidity: String, Codable, Sendable { case valid, quarantined, superseded, retired, invalid }

struct NFEditorialConditions: Codable, Equatable, Sendable {
    var toolConditionID: String? = nil
    var contentLocale: String? = nil
    var timingMode: NFEditorialTimingMode? = nil
    var stimulusResponseFormatID: String? = nil
    var inputModality: String? = nil
    var deviceClass: String? = nil
    var inputEditorVersion: String? = nil
    var latencyCalibrationVersion: String? = nil
    var timerVisible: Bool? = nil
    var timedFluencyTargetPolicy: String? = nil
    var accommodationFacts: Set<String> = []
}

struct NFEditorialConfidence: Codable, Equatable, Sendable {
    let probability: Double
    let mappingVersion: String
    let collectionPolicy: NFEditorialCollectionPolicy
    let lockedBeforeOutcome: Bool
    var retrospectivelyEdited: Bool = false
}

/// All durations are accumulated monotonic chunks. Missing provenance remains unknown.
struct NFEditorialObservation: Codable, Equatable, Sendable, Identifiable {
    let id: String
    let sessionID: String
    let sessionOrdinal: Int
    let eventOrder: Int64
    let canonicalDayOrdinal: Int
    let canonicalDayKey: String
    let dayPolicyVersion: String
    let occurredAt: Date
    let item: NFEditorialDemandRecord?
    let lane: NFEditorialEvidenceLane
    let outcome: NFEditorialAttemptOutcome
    let originalResponse: String
    var credit: Double
    var isFullCredit: Bool
    var isZeroCredit: Bool
    var policyVersion: String = EditorialBandEvidenceV1.policyVersion
    var validity: NFEditorialValidity = .valid
    var conditions = NFEditorialConditions()
    var assistanceKnown: Bool = false
    var helpBeforeLock: Bool = false
    var workedSolutionBeforeLock: Bool = false
    var answerPreviouslyRevealed: Bool = false
    var isFamiliarReview: Bool = false
    var protectedPreviouslyExposed: Bool = false
    var protectedLeakageReviewPassed: Bool = false
    var sourceOrSetID: String? = nil
    var rubricCriterionCredits: [String: Double] = [:]
    var missingCriterionIDs: Set<String> = []
    var confidence: NFEditorialConfidence? = nil
    var confidenceInvitationShown: Bool = false
    var durationChunksSeconds: [Double] = []
    var durationComplete: Bool = false
    var interruptionCount: Int? = nil
    var resumedAfterRelaunch: Bool? = nil
    var responseRevisedAfterLock: Bool = false
    var dimensionID: String? = nil
    var formProtocolVersion: String? = nil
    var rootFormID: String? = nil
    var transferContractID: String? = nil
    var retentionScopeID: String? = nil
    var isIndependentRepair: Bool = false
    var strategyIDObserved: String? = nil
    var strategyCriterionSatisfied: Bool? = nil

    var knownActiveSeconds: Double? {
        guard !durationChunksSeconds.isEmpty,
              durationChunksSeconds.allSatisfy({ $0.isFinite && $0 >= 0 }) else { return nil }
        let sum = durationChunksSeconds.reduce(0, +)
        return sum.isFinite ? sum : nil
    }
}

struct NFEditorialValidityProjection: Codable, Equatable, Sendable {
    var revision: String = "validity.v1"
    var dispositionByObservationID: [String: NFEditorialValidity] = [:]
    var dispositionBySemanticID: [String: NFEditorialValidity] = [:]
    var dispositionByFamilyID: [String: NFEditorialValidity] = [:]
    var correctedScoreByObservationID: [String: NFEditorialCorrectedScore] = [:]
    func validity(of observation: NFEditorialObservation) -> NFEditorialValidity {
        if let value = dispositionByObservationID[observation.id] { return value }
        guard let item = observation.item else { return observation.validity }
        return dispositionBySemanticID[item.semanticFingerprint] ?? dispositionByFamilyID[item.familyID] ?? observation.validity
    }
    func canSelect(_ item: NFEditorialDemandRecord) -> Bool {
        (dispositionBySemanticID[item.semanticFingerprint] ?? dispositionByFamilyID[item.familyID] ?? .valid) == .valid
    }
}
struct NFEditorialCorrectedScore: Codable, Equatable, Sendable {
    let credit: Double
    let isFullCredit: Bool
    let isZeroCredit: Bool
    let correctionID: String
    let explanation: String
}

/// Exact compatibility buckets avoid assuming equivalence across tools, contracts or task formats.
struct NFEditorialEvidenceGroup: Codable, Hashable, Sendable {
    let lane: NFEditorialEvidenceLane
    let objectiveID: String
    let familyID: String
    let band: NFEditorialBand
    let bandContractVersion: String
    let scoringComparabilityID: String
    let stimulusComparabilityID: String
    let toolConditionID: String
    let localeComparabilityID: String
    let pacingConditionID: String
    let protocolScope: String
    var stableID: String {
        [lane.rawValue, objectiveID, familyID, band.rawValue, bandContractVersion, scoringComparabilityID,
         stimulusComparabilityID, toolConditionID, localeComparabilityID, pacingConditionID, protocolScope]
            .map { "\($0.utf8.count):\($0)" }.joined()
    }
}
enum NFEditorialCoverageStatus: String, Codable, Sendable {
    case noObservations, earlyObservations, limitedBreadth, recentlySupported, needsRefresh, notCurrentlySupported, evidenceAffected
}
struct NFEditorialBandSummary: Codable, Equatable, Sendable {
    let group: NFEditorialEvidenceGroup
    let observationIDs: [String]
    let creditSum: Double
    let recentMeanCredit: Double?
    let fullCorrectCount: Int
    let semanticCount: Int
    let structureCount: Int
    let sessionCount: Int
    let activeDayCount: Int
    let formatCounts: [String: Int]
    let structureCounts: [String: Int]
    let qualifyingObservationIDs: [String]
    let qualifyingMeanCredit: Double?
    let lastDemonstratedAt: Date?
    let coverage: NFEditorialCoverageStatus
    var count: Int { observationIDs.count }
    var planningScore: Double { (1 + creditSum) / Double(2 + count) }
}
struct NFEditorialCalibrationSummary: Codable, Equatable, Sendable {
    let groupID: String
    let observationIDs: [String]
    let sessionCount: Int
    let declinedInvitationCount: Int
    let mappingVersion: String
    let meanBias: Double?
    let meanSquaredError: Double?
}
struct NFEditorialEvidenceState: Codable, Equatable, Sendable {
    let policyVersion: String
    let validityRevision: String
    let decisionDayOrdinal: Int
    let summaries: [NFEditorialBandSummary]
    let calibration: [NFEditorialCalibrationSummary]
    let independentObservationIDs: [String]
    let personalStudyObservationIDs: [String]
    let legacyObservationIDs: [String]
    let exclusions: [String: String]
    let cleanSpeedObservationIDs: [String]
    let declinedConfidenceInvitationIDs: [String]
    let speedExclusions: [String: String]
    let retention: [NFEditorialRetentionEntry]
}

/// Single deterministic policy for online and rebuilt evidence. All thresholds are editorial defaults.
enum EditorialBandEvidenceV1 {
    static let policyVersion = "EditorialBandEvidenceV1"
    static let epsilon = 1e-12
    static let intervalDays = [1, 3, 7, 14, 30]

    static func group(for observation: NFEditorialObservation) -> NFEditorialEvidenceGroup? {
        guard let item = observation.item else { return nil }
        let c = observation.conditions
        return NFEditorialEvidenceGroup(
            lane: observation.lane, objectiveID: item.objectiveID, familyID: item.familyID,
            band: item.editorialBand, bandContractVersion: item.bandContractVersion,
            scoringComparabilityID: item.scoringComparabilityID ?? item.answerContractVersion,
            stimulusComparabilityID: item.stimulusComparabilityID ?? c.stimulusResponseFormatID ?? "unknown",
            toolConditionID: c.toolConditionID ?? "unknown",
            localeComparabilityID: item.localeComparabilityID ?? c.contentLocale ?? "unknown",
            pacingConditionID: c.timingMode?.rawValue ?? "unknown",
            protocolScope: observation.lane == .protectedCheck ? observation.formProtocolVersion ?? "unknown"
                : observation.lane == .transfer ? observation.transferContractID ?? "unknown" : "practice.v1")
    }

    static func exclusionReason(_ o: NFEditorialObservation, validity: NFEditorialValidityProjection) -> String? {
        guard o.lane != .personalStudy && o.sourceOrSetID == nil else { return "personalStudy" }
        guard let item = o.item else { return "legacyUnknownBand" }
        guard o.policyVersion == policyVersion else { return "unsupportedPolicyVersion" }
        guard item.hasRequiredIdentity else { return "invalidBandContract" }
        guard validity.validity(of: o) == .valid else { return "contentExcluded" }
        guard item.independentEligible else { return "notReviewedForIndependentEvidence" }
        guard o.outcome == .scored else { return o.outcome.rawValue }
        guard o.credit.isFinite, (0...1).contains(o.credit),
              (o.isFullCredit == (o.credit == 1)), (o.isZeroCredit == (o.credit == 0)),
              !(o.isFullCredit && o.isZeroCredit),
              o.rubricCriterionCredits.values.allSatisfy({ $0.isFinite && (0...1).contains($0) }) else { return "invalidScorePayload" }
        guard o.assistanceKnown, o.conditions.toolConditionID != nil else { return "unknownAssistance" }
        guard o.conditions.toolConditionID == item.assistancePolicyID else { return "unreviewedToolCondition" }
        guard !o.helpBeforeLock && !o.workedSolutionBeforeLock else { return "assisted" }
        guard !o.answerPreviouslyRevealed else { return "answerPreviouslyRevealed" }
        guard o.conditions.timingMode != nil, o.conditions.contentLocale != nil,
              o.conditions.stimulusResponseFormatID != nil else { return "unknownConditions" }
        if o.lane == .protectedCheck {
            guard item.protectedEligible, o.protectedLeakageReviewPassed else { return "unreviewedProtectedPresentation" }
            guard !o.protectedPreviouslyExposed else { return "protectedPreviouslyExposed" }
            guard o.formProtocolVersion == NFEditorialProtectedPolicy.protocolVersion,
                  o.dimensionID != nil, o.dimensionID != "confidenceCalibration", o.rootFormID != nil else { return "unsupportedProtectedProtocol" }
        }
        if o.lane == .transfer && o.transferContractID == nil { return "missingTransferContract" }
        return nil
    }

    static func reduce(_ observations: [NFEditorialObservation], decisionDayOrdinal: Int,
                       validity: NFEditorialValidityProjection = .init()) -> NFEditorialEvidenceState {
        let ordered = observations.sorted(by: stableOrder)
        let byIdentity = Dictionary(grouping: observations, by: \.id)
        var conflictingIDs = Set(byIdentity.compactMap { id, copies in
            copies.dropFirst().contains(where: { $0 != copies[0] }) ? id : nil
        })
        let bySlot = Dictionary(grouping: observations) { "\($0.sessionID.utf8.count):\($0.sessionID):\($0.sessionOrdinal)" }
        for copies in bySlot.values where Set(copies.map(\.id)).count > 1 {
            conflictingIDs.formUnion(copies.map(\.id))
        }
        var seenIDs: Set<String> = []
        var effective: [NFEditorialObservation] = []
        var exclusions: [String: String] = [:]
        var personal: [String] = []
        var legacy: [String] = []
        var lastSemanticDay: [String: Int] = [:]
        var protectedSemantics: Set<String> = []
        for raw in ordered where seenIDs.insert(raw.id).inserted {
            if conflictingIDs.contains(raw.id) { exclusions[raw.id] = "conflictingDuplicateObservation"; continue }
            guard raw.canonicalDayOrdinal <= decisionDayOrdinal else { exclusions[raw.id] = "futureObservation"; continue }
            if raw.lane == .personalStudy || raw.sourceOrSetID != nil { personal.append(raw.id); continue }
            if raw.item == nil { legacy.append(raw.id); exclusions[raw.id] = "legacyUnknownBand"; continue }
            var o = raw
            if let corrected = validity.correctedScoreByObservationID[raw.id] {
                // The original payload is immutable; corrected credit is an effective projection only.
                o = correctedObservation(raw, score: corrected)
            }
            if let reason = exclusionReason(o, validity: validity) { exclusions[o.id] = reason; continue }
            guard let item = o.item, let group = group(for: o) else { continue }
            let repeatKey = [item.objectiveID, item.familyID, item.editorialBand.rawValue, item.semanticFingerprint].joined(separator: "|")
            if o.lane == .protectedCheck {
                if !protectedSemantics.insert(item.solutionExposureID ?? item.semanticFingerprint).inserted {
                    exclusions[o.id] = "protectedSemanticRepeat"; continue
                }
            } else if let last = lastSemanticDay[repeatKey], o.canonicalDayOrdinal - last < 30 {
                exclusions[o.id] = "semanticRepeatWithin30Days"; continue
            }
            if o.isFamiliarReview { exclusions[o.id] = "familiarItemReview"; continue }
            lastSemanticDay[repeatKey] = o.canonicalDayOrdinal
            _ = group
            effective.append(o)
        }
        let grouped = Dictionary(grouping: effective) { group(for: $0)! }
        let affectedGroups = Set(ordered.filter { exclusions[$0.id] == "contentExcluded" }.compactMap { group(for: $0) })
        let summaries = Set(grouped.keys).union(affectedGroups).sorted { $0.stableID < $1.stableID }.map { key in
            summary(group: key, history: grouped[key] ?? [], decisionDay: decisionDayOrdinal, affected: affectedGroups.contains(key))
        }
        let recent = effective.filter { decisionDayOrdinal - $0.canonicalDayOrdinal < 60 }
        var speedReasons: [String: String] = [:]
        var speed: [String] = []
        for o in recent {
            if let reason = speedExclusion(o) { speedReasons[o.id] = reason } else { speed.append(o.id) }
        }
        return NFEditorialEvidenceState(policyVersion: policyVersion, validityRevision: validity.revision,
            decisionDayOrdinal: decisionDayOrdinal, summaries: summaries,
            calibration: calibrationSummaries(recent, all: ordered, decisionDay: decisionDayOrdinal),
            independentObservationIDs: effective.map(\.id), personalStudyObservationIDs: personal,
            legacyObservationIDs: legacy, exclusions: exclusions, cleanSpeedObservationIDs: speed,
            declinedConfidenceInvitationIDs: Array(Set(ordered.filter {
                $0.canonicalDayOrdinal <= decisionDayOrdinal && decisionDayOrdinal - $0.canonicalDayOrdinal < 60
                    && $0.confidenceInvitationShown && $0.confidence == nil && $0.lane == .practice
                    && $0.conditions.timingMode != .timedFluency && $0.sourceOrSetID == nil
            }.map(\.id))).sorted(),
            speedExclusions: speedReasons, retention: NFEditorialRetentionPolicy.reduce(ordered.filter { $0.canonicalDayOrdinal <= decisionDayOrdinal && !conflictingIDs.contains($0.id) }, independentIDs: Set(effective.map(\.id)), validity: validity))
    }

    static func stableOrder(_ lhs: NFEditorialObservation, _ rhs: NFEditorialObservation) -> Bool {
        if lhs.eventOrder != rhs.eventOrder { return lhs.eventOrder < rhs.eventOrder }
        if lhs.sessionID != rhs.sessionID { return lhs.sessionID < rhs.sessionID }
        if lhs.sessionOrdinal != rhs.sessionOrdinal { return lhs.sessionOrdinal < rhs.sessionOrdinal }
        return lhs.id < rhs.id
    }

    private static func correctedObservation(_ o: NFEditorialObservation, score: NFEditorialCorrectedScore) -> NFEditorialObservation {
        var copy = o
        copy.credit = score.credit
        copy.isFullCredit = score.isFullCredit
        copy.isZeroCredit = score.isZeroCredit
        return copy
    }

    private static func qualifying(_ window: [NFEditorialObservation]) -> [NFEditorialObservation] {
        var structureCounts: [String: Int] = [:]
        var semanticIDs: Set<String> = []
        var result: [NFEditorialObservation] = []
        for o in window.reversed() {
            guard let item = o.item, structureCounts[item.structureID, default: 0] < 4,
                  semanticIDs.insert(item.semanticFingerprint).inserted else { continue }
            structureCounts[item.structureID, default: 0] += 1
            result.append(o)
            if result.count == 8 { break }
        }
        return result.reversed()
    }
    private static func supports(_ q: [NFEditorialObservation]) -> Bool {
        guard q.count == 8, Set(q.map(\.sessionID)).count >= 2,
              Set(q.map(\.canonicalDayKey)).count >= 2,
              Set(q.compactMap { $0.item?.structureID }).count >= 2,
              q.filter(\.isFullCredit).count >= 6,
              q.reduce(0, { $0 + $1.credit }) / 8 + epsilon >= 0.8 else { return false }
        let formats = Set(q.compactMap { $0.conditions.stimulusResponseFormatID })
        return q.allSatisfy { $0.item?.requiredDemonstrationFormatIDs.isSubset(of: formats) == true }
    }
    struct DemonstrationWitness: Equatable, Sendable {
        let endpointObservationID: String
        let occurredAt: Date
        let qualifyingObservationIDs: [String]
    }

    /// Proof follows immutable event order, the same chronology as summary().
    /// A wall-clock rollback or tied timestamp cannot erase an earlier accepted
    /// supporting prefix. Reuse the existing qualification/breadth thresholds.
    static func lastDemonstrationWitness(group: NFEditorialEvidenceGroup, observations: [NFEditorialObservation],
                                         evidence: NFEditorialEvidenceState,
                                         validity: NFEditorialValidityProjection) -> DemonstrationWitness? {
        guard group.lane == .practice else { return nil }
        let independent = Set(evidence.independentObservationIDs)
        let history = observations.filter { independent.contains($0.id) && Self.group(for: $0) == group }
            .sorted(by: stableOrder).map { value in
                validity.correctedScoreByObservationID[value.id].map { correctedObservation(value, score: $0) } ?? value
            }
        var window: [NFEditorialObservation] = []
        var witness: DemonstrationWitness?
        for value in history {
            window.removeAll { value.canonicalDayOrdinal - $0.canonicalDayOrdinal >= 60 }
            window.append(value)
            if window.count > 20 { window.removeFirst(window.count - 20) }
            let qualified = qualifying(window)
            if supports(qualified) {
                witness = .init(endpointObservationID: value.id, occurredAt: value.occurredAt,
                    qualifyingObservationIDs: qualified.map(\.id))
            }
        }
        return witness
    }

    private static func summary(group: NFEditorialEvidenceGroup, history: [NFEditorialObservation], decisionDay: Int, affected: Bool) -> NFEditorialBandSummary {
        let recent = Array(history.filter { decisionDay - $0.canonicalDayOrdinal < 60 }.suffix(20))
        let q = qualifying(recent)
        var lastDemonstrated: Date?
        var demonstrationDay: Int?
        var historicalWindow: [NFEditorialObservation] = []
        for o in history {
            historicalWindow.removeAll { o.canonicalDayOrdinal - $0.canonicalDayOrdinal >= 60 }
            historicalWindow.append(o)
            if historicalWindow.count > 20 { historicalWindow.removeFirst(historicalWindow.count - 20) }
            if group.lane == .practice && supports(qualifying(historicalWindow)) {
                lastDemonstrated = o.occurredAt; demonstrationDay = o.canonicalDayOrdinal
            }
        }
        let mean = q.isEmpty ? nil : q.reduce(0) { $0 + $1.credit } / Double(q.count)
        let status: NFEditorialCoverageStatus
        if affected { status = .evidenceAffected }
        else if group.lane == .practice && supports(q) { status = .recentlySupported }
        else if lastDemonstrated != nil, let latest = history.last, decisionDay - latest.canonicalDayOrdinal >= 30 { status = .needsRefresh }
        else if let day = demonstrationDay, q.count == 8, (mean ?? 1) < 0.6,
                Set(q.filter { $0.canonicalDayOrdinal > day }.map(\.canonicalDayKey)).count >= 2,
                Set(q.filter { $0.canonicalDayOrdinal > day }.map(\.sessionID)).count >= 2 { status = .notCurrentlySupported }
        else if recent.isEmpty { status = .noObservations }
        else if recent.count >= 8 && q.count < 8 { status = .limitedBreadth }
        else if q.count == 8 && !q.allSatisfy({ $0.item!.requiredDemonstrationFormatIDs.isSubset(of: Set(q.compactMap { $0.conditions.stimulusResponseFormatID })) }) { status = .limitedBreadth }
        else { status = .earlyObservations }
        let sum = recent.reduce(0) { $0 + $1.credit }
        return NFEditorialBandSummary(group: group, observationIDs: recent.map(\.id), creditSum: sum,
            recentMeanCredit: recent.isEmpty ? nil : sum / Double(recent.count), fullCorrectCount: recent.filter(\.isFullCredit).count,
            semanticCount: Set(recent.compactMap { $0.item?.semanticFingerprint }).count,
            structureCount: Set(recent.compactMap { $0.item?.structureID }).count,
            sessionCount: Set(recent.map(\.sessionID)).count, activeDayCount: Set(recent.map(\.canonicalDayKey)).count,
            formatCounts: Dictionary(grouping: recent, by: { $0.conditions.stimulusResponseFormatID ?? "unknown" }).mapValues(\.count),
            structureCounts: Dictionary(grouping: recent, by: { $0.item!.structureID }).mapValues(\.count),
            qualifyingObservationIDs: q.map(\.id), qualifyingMeanCredit: mean,
            lastDemonstratedAt: lastDemonstrated, coverage: status)
    }

    static func confidenceInvited(sessionID: String, ordinaryPresentationOrdinal: Int) -> Bool {
        guard ordinaryPresentationOrdinal >= 0 else { return false }
        let group = ordinaryPresentationOrdinal / 5
        let slot = NFStableDeterminism.hash64("\(sessionID)|\(policyVersion)|\(group)|confidence-invitation") % 5
        return UInt64(ordinaryPresentationOrdinal % 5) == slot
    }
    private static func calibrationGroupID(_ o: NFEditorialObservation) -> String? {
        guard let c = o.confidence, let group = group(for: o) else { return nil }
        return "\(group.stableID)|\(c.mappingVersion)|whole-answer-full-credit-v1|\(c.collectionPolicy.rawValue)"
    }
    private static func calibrationSummaries(_ independent: [NFEditorialObservation], all: [NFEditorialObservation], decisionDay: Int) -> [NFEditorialCalibrationSummary] {
        let usable = independent.filter {
            guard let c = $0.confidence else { return false }
            return c.lockedBeforeOutcome && !c.retrospectivelyEdited && c.probability.isFinite
                && [0.25, 0.45, 0.72, 0.92].contains(c.probability) && c.mappingVersion == "confidenceCategoricalV1"
                && $0.conditions.timingMode != .timedFluency
        }
        let grouped = Dictionary(grouping: usable) { calibrationGroupID($0)! }
        return grouped.keys.sorted().map { key in
            let sample = Array(grouped[key]!.suffix(50))
            let sessions = Set(sample.map(\.sessionID)).count
            let enough = sample.count >= 12 && sessions >= 2
            let n = Double(sample.count)
            let pairs = sample.map { $0.confidence!.probability - ($0.isFullCredit ? 1.0 : 0.0) }
            let base = group(for: sample[0])
            let declined = all.filter { $0.canonicalDayOrdinal <= decisionDay && decisionDay - $0.canonicalDayOrdinal < 60
                && $0.confidenceInvitationShown && $0.confidence == nil && group(for: $0) == base }.count
            return NFEditorialCalibrationSummary(groupID: key, observationIDs: sample.map(\.id), sessionCount: sessions,
                declinedInvitationCount: declined, mappingVersion: "confidenceCategoricalV1",
                meanBias: enough ? pairs.reduce(0, +) / n : nil,
                meanSquaredError: enough ? pairs.reduce(0) { $0 + $1 * $1 } / n : nil)
        }
    }
    static func speedExclusion(_ o: NFEditorialObservation) -> String? {
        guard o.conditions.timingMode == .timedFluency, o.item?.reviewedFluencyEligible == true else { return "notReviewedTimedFluency" }
        guard o.isFullCredit else { return "notFullyCorrect" }
        guard o.assistanceKnown, !o.helpBeforeLock, !o.workedSolutionBeforeLock, !o.answerPreviouslyRevealed else { return "assistedOrUnknown" }
        guard o.interruptionCount == 0, o.resumedAfterRelaunch == false else { return "interruptedResumedOrUnknown" }
        guard !o.responseRevisedAfterLock else { return "revisedAfterLock" }
        guard o.durationComplete, let seconds = o.knownActiveSeconds, seconds > 0 else { return "incompleteDuration" }
        let c = o.conditions
        guard [c.inputModality, c.deviceClass, c.inputEditorVersion, c.latencyCalibrationVersion,
               c.timedFluencyTargetPolicy].allSatisfy({ $0?.isEmpty == false }), c.timerVisible != nil else { return "unknownSpeedConditions" }
        return nil
    }
}


// MARK: - Immutable new-commit observation provenance

/// Captured only for a new, acknowledged ordinary run. This is provenance, not
/// admission: there is currently no released reviewed-band admission registry.
/// Legacy snapshots decode with nil and are never retrospectively backfilled.
struct NFEditorialCommitCapture: Codable, Equatable, Sendable {
    var schemaVersion = 1
    let policyVersion: String
    let attemptID: UUID
    let sessionID: UUID
    let ownerDeviceID: UUID
    let originalRecordDeviceID: UUID
    let sessionSourceRaw: String
    let planID: String?
    let planBlockID: String?
    let profileID: UUID
    let slotID: String
    let sessionOrdinal: Int
    let decisionOrdinal: UInt64
    let eventOrder: Int64
    let configurationDigest: String
    let versions: NFReservationVersionPin
    let exerciseDigest: String
    let originalResponseDigest: String
    let originalCredit: Double
    let originalIsCorrect: Bool
    let originalOutcome: NFScoringOutcome
    let scorerVersion: Int
    let rubricComponents: [NFScoringComponentResult]
    let submittedAt: Date
    let day: NFEditorialCapturedDay
    let conditions: NFEditorialConditions
    let assistanceEvents: [NFLocalAssistanceEvent]?
    let hintCount: Int
    let solutionRevealed: Bool
    let answerDurationComplete: Bool?
    let activeDurationSeconds: Double
    let interruptionCount: Int
    let revisionCount: Int
    let confidenceRaw: String?
    let confidenceProbability: Double?
    let confidenceMappingVersion: String?
    let authorityAtCommit: String
    var runtimeWitness: NFEditorialRuntimeWitness? = nil
    var reviewFeedbackDigest: String? = nil

    var isSupported: Bool {
        schemaVersion == 1 && policyVersion == NFEditorialCommitCapturePolicy.version
            && (reviewFeedbackDigest.map { $0.count == 64 && $0.allSatisfy(\.isHexDigit) } ?? true)
            && day.isSupported && sessionOrdinal >= 0 && eventOrder >= 0
            && [exerciseDigest, originalResponseDigest, configurationDigest].allSatisfy {
                $0.count == 64 && $0.allSatisfy(\.isHexDigit)
            }
            && NFSessionPresentationPolicy.supportedVersions.contains(versions.presentationVersion)
            && NFSessionDurationPolicy.isValid(activeDurationSeconds)
            && originalCredit.isFinite && (0...1).contains(originalCredit)
            && originalIsCorrect == (originalOutcome == .correct)
            && (originalOutcome == .correct ? originalCredit == 1
                : originalOutcome == .incorrect ? originalCredit == 0
                : originalOutcome == .partial && originalCredit > 0 && originalCredit < 1)
    }
}

/// The original civil-day label is retained with the exact boundary instants;
/// later time-zone changes cannot relabel a saved observation.
struct NFEditorialCapturedDay: Codable, Equatable, Sendable {
    let policyVersion: String
    let calendarIdentifier: String
    let timeZoneIdentifier: String
    let utcOffsetSeconds: Int
    let dayBoundaryHour: Int
    let boundaryStart: Date
    let nextBoundary: Date
    let ordinal: Int
    let key: String
    var isSupported: Bool {
        policyVersion == "CanonicalTrainingDayV1" && calendarIdentifier == "gregorian"
            && !timeZoneIdentifier.isEmpty && (0...12).contains(dayBoundaryHour)
            && boundaryStart.timeIntervalSince1970.isFinite && nextBoundary.timeIntervalSince1970.isFinite
            && nextBoundary > boundaryStart && ordinal > 0 && !key.isEmpty
    }
    static func capture(at date: Date, dayBoundaryHour: Int, calendar supplied: Calendar) -> Self? {
        guard date.timeIntervalSince1970.isFinite, (0...12).contains(dayBoundaryHour) else { return nil }
        // The policy defines Gregorian training-day labels. Locale formatting
        // and the caller's preferred calendar do not change this saved identity.
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = supplied.timeZone
        let boundary = NFPlanBoundaryContext.make(at: date, dayBoundaryHour: dayBoundaryHour, calendar: calendar)
        guard boundary.boundaryStart <= date, date < boundary.nextBoundary,
              let ordinal = calendar.ordinality(of: .day, in: .era, for: boundary.boundaryStart) else { return nil }
        let parts = calendar.dateComponents([.year, .month, .day], from: boundary.boundaryStart)
        guard let year = parts.year, let month = parts.month, let day = parts.day else { return nil }
        return .init(policyVersion: "CanonicalTrainingDayV1", calendarIdentifier: "gregorian",
            timeZoneIdentifier: boundary.timeZoneIdentifier, utcOffsetSeconds: boundary.utcOffsetSeconds,
            dayBoundaryHour: boundary.dayBoundaryHour, boundaryStart: boundary.boundaryStart,
            nextBoundary: boundary.nextBoundary, ordinal: ordinal,
            key: String(format: "%04d-%02d-%02d", year, month, day))
    }
}

/// Deliberately fail closed. A future implementation must resolve a signed,
/// reviewed manifest entry bound to the complete exercise/contract digest.
/// `editorialDemand`, reviewStatus prose, a bank receipt or an imported claim
/// alone can never create independent academic authority.
enum NFEditorialObservationAdmissionRegistry {
    static let unavailable = "reviewedAdmissionRegistryUnavailable"
    static func exclusionReason(for exercise: NFExercise, context: NFEditorialAdmissionContext = .released) -> String? {
        context.entry(exercise: exercise) == nil ? unavailable : nil
    }
}

struct NFEditorialCommitProjection: Equatable, Sendable {
    let observation: NFEditorialObservation?
    let exclusionReason: String?
}

enum NFEditorialCommitCapturePolicy {
    static let version = "EditorialCommitCaptureV1"

    static func make(record: NFImmutableAttemptRecordSnapshot, exercise: NFExercise,
                     result: NFExerciseScoringResult, envelope: NFLocalSessionEnvelope,
                     ledger: NFSelectionReservationLedger, profileID: UUID, dayBoundaryHour: Int,
                     calendar: Calendar, transactionRevision: UInt64,
                     runtimeWitness: NFEditorialRuntimeWitness? = nil) -> NFEditorialCommitCapture? {
        guard !record.containsProtectedContent, !exercise.assessmentProtected,
              record.generationID == nil, record.evidenceClassRaw == EvidenceClass.practice.rawValue,
              exercise.evidenceClass == .practice, exercise.provenance.sourceDocumentIDs.isEmpty,
              record.sourceDocumentIDsRaw.isEmpty, exercise.provenance.sourceChunkIDs.isEmpty,
              [.bundledAuthored, .deterministicGenerated].contains(exercise.provenance.contentTier),
              let day = NFEditorialCapturedDay.capture(at: record.submittedAt, dayBoundaryHour: dayBoundaryHour, calendar: calendar),
              transactionRevision < UInt64(Int64.max), envelope.schemaVersion == 1,
              envelope.id == record.sessionID, envelope.status == .suspended,
              envelope.request.source.rawValue == record.sessionSourceRaw,
              envelope.request.planID == record.planID, envelope.request.planBlockID == record.planBlockID,
              let run = ledger.runs[record.sessionID.uuidString],
              let slot = ledger.slots[envelope.checkpoint.slotID.uuidString],
              let decision = ledger.decisions[slot.decisionID],
              run.ownerDeviceID == envelope.ownerDeviceID.uuidString, slot.runID == run.id,
              slot.attemptID == record.id.uuidString, slot.status == .presented,
              decision.acceptedSlotIDs.contains(slot.id), decision.command.runID == run.id,
              let digest = try? NFLocalItemCheckpoint.digest(exercise), slot.snapshotDigest == digest,
              let retained = NFSelectionReservationPolicy.snapshot(for: slot, in: ledger),
              (try? JSONDecoder().decode(NFExercise.self, from: retained.payload)) == exercise else { return nil }
        let saved = envelope.checkpoint
        guard saved.schemaVersion == 1, saved.attemptID == record.id, saved.exercise == exercise,
              saved.exerciseDigest == digest, saved.committedAttemptID == nil, saved.pendingOutcome == "answer", saved.phase == .confidence,
              saved.result == result, saved.scorerVersion == result.scoringVersion,
              saved.confidence?.rawValue == record.confidenceRaw,
              saved.capturedSupportCount == record.hintCount, saved.interruptionCount == record.interruptionCount,
              saved.revisionCount == record.revisionCount, saved.inputModality.rawValue == record.inputModeRaw,
              let response = try? JSONDecoder().decode(NFExerciseResponse.self, from: Data(record.response.utf8)),
              response == saved.response, record.itemID == exercise.id, record.prompt == exercise.prompt,
              record.scoringVersion == result.scoringVersion, result.exerciseID == exercise.id,
              record.deterministicCredit == result.credit, record.isCorrect == result.isCorrect else { return nil }
        let timing = saved.timingConditionOverride ?? envelope.request.timingCondition
        // Unknown tool/editor/latency/visibility conditions remain unknown;
        // borrowing them from the desired demand contract would invent evidence.
        let conditions = NFEditorialConditions(
            toolConditionID: runtimeWitness?.isSupported == true ? NFEditorialNativeProtocol.toolConditionID : nil,
            contentLocale: exercise.localeIdentifier,
            timingMode: timing?.isSupported == true ? timing?.mode : nil,
            stimulusResponseFormatID: NFRetentionRepresentation.identifier(for: exercise),
            inputModality: saved.inputModality == .unknown ? nil : saved.inputModality.rawValue,
            accommodationFacts: Set(record.accommodationFlagsRaw.split(separator: ",").map(String.init)))
        let value = NFEditorialCommitCapture(policyVersion: version, attemptID: record.id, sessionID: record.sessionID,
            ownerDeviceID: envelope.ownerDeviceID, originalRecordDeviceID: record.deviceID,
            sessionSourceRaw: record.sessionSourceRaw, planID: record.planID, planBlockID: record.planBlockID, profileID: profileID, slotID: slot.id, sessionOrdinal: slot.pathOrdinal,
            decisionOrdinal: decision.command.decisionOrdinal, eventOrder: Int64(transactionRevision + 1),
            configurationDigest: run.configurationDigest, versions: run.versions, exerciseDigest: digest,
            originalResponseDigest: NFReservationSnapshot.digest(Data(record.response.utf8)),
            originalCredit: result.credit, originalIsCorrect: result.isCorrect, originalOutcome: result.outcome,
            scorerVersion: result.scoringVersion, rubricComponents: result.components, submittedAt: record.submittedAt,
            day: day, conditions: conditions, assistanceEvents: saved.assistanceEvents, hintCount: record.hintCount,
            solutionRevealed: saved.solutionRevealed, answerDurationComplete: saved.answerDurationComplete,
            activeDurationSeconds: record.activeDurationSeconds, interruptionCount: record.interruptionCount,
            revisionCount: record.revisionCount, confidenceRaw: record.confidenceRaw,
            confidenceProbability: saved.confidence?.probability,
            confidenceMappingVersion: saved.confidence == nil ? nil : "confidenceCategoricalV1",
            authorityAtCommit: runtimeWitness?.isSupported == true ? "admitted"
                : NFEditorialObservationAdmissionRegistry.unavailable, runtimeWitness: runtimeWitness,
            reviewFeedbackDigest: runtimeWitness?.reviewAssignment == nil ? nil : try? NFEditorialCanonicalData.digest(result))
        return value.isSupported ? value : nil
    }

    /// The first successful local publication freezes retry-only time/device
    /// fields even when the secondary core write has not happened yet.
    static func matchesRetry(_ capture: NFEditorialCommitCapture, record: NFImmutableAttemptRecordSnapshot,
                             exercise: NFExercise, result: NFExerciseScoringResult) -> Bool {
        capture.isSupported && !record.containsProtectedContent && !exercise.assessmentProtected
            && record.generationID == nil && record.evidenceClassRaw == EvidenceClass.practice.rawValue
            && capture.attemptID == record.id && capture.sessionID == record.sessionID
            && capture.sessionSourceRaw == record.sessionSourceRaw && capture.planID == record.planID
            && capture.planBlockID == record.planBlockID && exercise.id == record.itemID && exercise.prompt == record.prompt
            && capture.exerciseDigest == (try? NFLocalItemCheckpoint.digest(exercise))
            && capture.originalResponseDigest == NFReservationSnapshot.digest(Data(record.response.utf8))
            && capture.scorerVersion == result.scoringVersion && record.scoringVersion == result.scoringVersion
            && record.deterministicCredit == result.credit && record.isCorrect == result.isCorrect
            && result.exerciseID == exercise.id
            && capture.conditions.accommodationFacts == Set(record.accommodationFlagsRaw.split(separator: ",").map(String.init))
            && capture.originalCredit == result.credit && capture.originalIsCorrect == result.isCorrect
            && capture.originalOutcome == result.outcome && capture.rubricComponents == result.components
            && capture.hintCount == record.hintCount && capture.confidenceRaw == record.confidenceRaw
            && (capture.conditions.inputModality ?? NFInputModality.unknown.rawValue) == record.inputModeRaw
            && capture.activeDurationSeconds == record.activeDurationSeconds
            && capture.interruptionCount == record.interruptionCount && capture.revisionCount == record.revisionCount
    }

    /// This adapter consumes immutable values and the already-filtered effective
    /// score. It never mutates an original score, response or capture.
    static func project(snapshot: NFLocalAttemptSnapshot?, record: NFImmutableAttemptRecordSnapshot,
                        effectiveCredit: Double, excluded: Bool,
                        admissions: NFEditorialAdmissionContext = .released,
                        localAuthorityVerified: Bool = false) -> NFEditorialCommitProjection {
        guard !record.containsProtectedContent, !excluded else {
            return .init(observation: nil, exclusionReason: "effectiveEvidenceExcluded")
        }
        guard let snapshot, let capture = snapshot.editorialCapture else {
            return .init(observation: nil, exclusionReason: "missingCommitProvenance")
        }
        guard capture.isSupported, capture.attemptID == record.id, snapshot.attemptID == record.id,
              capture.sessionID == record.sessionID, capture.originalRecordDeviceID == record.deviceID,
              capture.exerciseDigest == (try? NFLocalItemCheckpoint.digest(snapshot.exercise)),
              snapshot.exercise.id == record.itemID, snapshot.exercise.prompt == record.prompt,
              capture.originalResponseDigest == NFReservationSnapshot.digest(Data(record.response.utf8)),
              capture.originalCredit == record.deterministicCredit, capture.originalIsCorrect == record.isCorrect,
              capture.scorerVersion == record.scoringVersion, capture.submittedAt == record.submittedAt,
              capture.confidenceRaw == record.confidenceRaw, capture.hintCount == record.hintCount,
              capture.activeDurationSeconds == record.activeDurationSeconds,
              capture.interruptionCount == record.interruptionCount, capture.revisionCount == record.revisionCount,
              effectiveCredit.isFinite, (0...1).contains(effectiveCredit) else {
            return .init(observation: nil, exclusionReason: "unverifiedCommitProvenance")
        }
        // Keep the explicit effective score input here so no caller later feeds
        // raw credit into a reviewed observation after an append-only correction.
        guard capture.authorityAtCommit == "admitted",
              let admission = admissions.entry(exercise: snapshot.exercise) else {
            return .init(observation: nil, exclusionReason: NFEditorialObservationAdmissionRegistry.unavailable)
        }
        guard localAuthorityVerified, let witness = capture.runtimeWitness, witness.isSupported,
              witness.admission == admission, admission.scorerVersion == capture.scorerVersion,
              witness.catalogVersion == admissions.version,
              witness.catalogDigest == admissions.fingerprint,
              witness.ownerDeviceID == capture.ownerDeviceID,
              witness.presentedSlotID == capture.slotID,
              capture.conditions.toolConditionID == NFEditorialNativeProtocol.toolConditionID,
              capture.conditions.timingMode != nil else {
            return .init(observation: nil, exclusionReason: "independentConditionsUnavailable")
        }
        let currentReview = witness.reviewAssignment.flatMap { assigned -> NFEditorialReviewAssignment? in
            guard let actual = NFEditorialReviewSlotPolicy.contract(exercise: snapshot.exercise, admission: admission,
                timing: capture.conditions.timingMode, day: assigned.decisionDayOrdinal),
                  actual.group == assigned.group else { return nil }
            return assigned
        }
        var observation = NFEditorialObservation(id: record.id.uuidString,
            sessionID: record.sessionID.uuidString, sessionOrdinal: capture.sessionOrdinal,
            eventOrder: capture.eventOrder, canonicalDayOrdinal: capture.day.ordinal,
            canonicalDayKey: capture.day.key, dayPolicyVersion: capture.day.policyVersion,
            occurredAt: capture.submittedAt, item: admission.demand,
            lane: currentReview?.role == .delayedCheck ? .retention : .practice,
            outcome: .scored, originalResponse: record.response, credit: effectiveCredit,
            isFullCredit: effectiveCredit == 1, isZeroCredit: effectiveCredit == 0)
        observation.retentionScopeID = currentReview?.contract.scopeID
        observation.isIndependentRepair = currentReview?.role == .repair
        observation.conditions = capture.conditions
        observation.assistanceKnown = witness.inAppAssistanceKnown
        observation.helpBeforeLock = capture.hintCount > 0
        observation.workedSolutionBeforeLock = capture.solutionRevealed
        observation.answerPreviouslyRevealed = witness.previouslyRevealedSemantic
        observation.durationChunksSeconds = [capture.activeDurationSeconds]
        observation.durationComplete = capture.answerDurationComplete == true
        observation.interruptionCount = capture.interruptionCount
        // A cumulative known duration is not a latency protocol. Missing device,
        // editor, relaunch and invitation facts remain unknown; no speed or
        // confidence authority is inferred by this ordinary-accuracy adapter.
        let components = Dictionary(grouping: capture.rubricComponents, by: \.id)
        guard components.values.allSatisfy({ $0.count == 1 }) else {
            return .init(observation: nil, exclusionReason: "conflictingRubricComponents")
        }
        for component in capture.rubricComponents {
            guard component.maximumCredit.isFinite, component.maximumCredit > 0,
                  component.awardedCredit.isFinite,
                  (0...component.maximumCredit).contains(component.awardedCredit) else {
                return .init(observation: nil, exclusionReason: "invalidRubricComponents")
            }
            let credit = component.awardedCredit / component.maximumCredit
            observation.rubricCriterionCredits[component.id] = credit
            if credit < 1 { observation.missingCriterionIDs.insert(component.id) }
        }
        return .init(observation: observation, exclusionReason: nil)
    }
}

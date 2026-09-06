import Foundation

enum NFEditorialMistakeStatus: String, Codable, Sendable {
    case needsExplanation, readyForRepair, repairedInSession, dueForDelayedCheck, retained, stillNeedsSupport, suspended
}
struct NFEditorialRetentionEntry: Codable, Equatable, Sendable, Identifiable {
    let id: String
    let objectiveID: String
    let familyID: String
    let band: NFEditorialBand
    let scopeID: String
    var originalAttemptID: String
    var missingCriterionIDs: Set<String>
    var rung = 0
    var dueDayOrdinal: Int? = nil
    var lastIndependentObservationID: String? = nil
    var lastIndependentDayOrdinal: Int? = nil
    var semanticExposureIDs: Set<String> = []
    var status: NFEditorialMistakeStatus = .dueForDelayedCheck
    var resetAfterIndependentRepair = false
}

enum NFEditorialRetentionPolicy {
    static func reduce(_ observations: [NFEditorialObservation], independentIDs: Set<String>,
                       validity: NFEditorialValidityProjection) -> [NFEditorialRetentionEntry] {
        var entries: [String: NFEditorialRetentionEntry] = [:]
        var seen: Set<String> = []
        for original in observations.sorted(by: EditorialBandEvidenceV1.stableOrder) where seen.insert(original.id).inserted {
            guard original.lane != .personalStudy, original.lane != .protectedCheck, original.sourceOrSetID == nil,
                  let item = original.item, let scope = original.retentionScopeID,
                  item.independentEligible else { continue }
            var o = original
            if let correction = validity.correctedScoreByObservationID[o.id] {
                o.credit = correction.credit; o.isFullCredit = correction.isFullCredit; o.isZeroCredit = correction.isZeroCredit
            }
            let key = [item.objectiveID, item.familyID, item.editorialBand.rawValue, scope,
                       item.bandContractVersion, item.scoringComparabilityID ?? item.answerContractVersion,
                       item.stimulusComparabilityID ?? o.conditions.stimulusResponseFormatID ?? "unknown",
                       o.conditions.toolConditionID ?? "unknown", item.localeComparabilityID ?? o.conditions.contentLocale ?? "unknown",
                       o.conditions.timingMode?.rawValue ?? "unknown"].joined(separator: "|")
                + (item.reviewContract.map { "|" + $0.compatibilityID } ?? "")
            var entry = entries[key] ?? NFEditorialRetentionEntry(id: key, objectiveID: item.objectiveID,
                familyID: item.familyID, band: item.editorialBand, scopeID: scope, originalAttemptID: o.id,
                missingCriterionIDs: o.missingCriterionIDs)
            if validity.validity(of: o) != .valid {
                entry.status = .suspended; entry.dueDayOrdinal = nil; entries[key] = entry; continue
            }
            let fresh = !entry.semanticExposureIDs.contains(item.semanticFingerprint)
            entry.semanticExposureIDs.insert(item.semanticFingerprint)
            if o.outcome == .skipped || o.outcome == .abandoned || o.outcome == .replaced { entries[key] = entry; continue }
            if o.helpBeforeLock || o.workedSolutionBeforeLock {
                entry.status = .stillNeedsSupport; entries[key] = entry; continue
            }
            guard independentIDs.contains(o.id), fresh else { entries[key] = entry; continue }
            entry.lastIndependentObservationID = o.id
            entry.lastIndependentDayOrdinal = o.canonicalDayOrdinal
            if o.isFullCredit {
                if o.isIndependentRepair, item.reviewContract != nil {
                    // A declared, distinct sibling repairs this scoped mistake;
                    // its immediate success schedules, but cannot be retention.
                    if entry.resetAfterIndependentRepair { entry.rung = 0 }
                    entry.resetAfterIndependentRepair = false
                    entry.missingCriterionIDs = []
                    entry.status = .dueForDelayedCheck
                    let days = min(3, EditorialBandEvidenceV1.intervalDays[entry.rung])
                    entry.dueDayOrdinal = o.canonicalDayOrdinal.addingReportingOverflow(days).overflow ? nil
                        : o.canonicalDayOrdinal + days
                } else if entry.resetAfterIndependentRepair {
                    guard o.isIndependentRepair else { entries[key] = entry; continue }
                    entry.rung = 0; entry.resetAfterIndependentRepair = false
                    entry.status = .dueForDelayedCheck; entry.dueDayOrdinal = o.canonicalDayOrdinal + 1
                } else if let due = entry.dueDayOrdinal {
                    if o.lane == .retention && o.canonicalDayOrdinal >= due {
                        entry.rung = min(EditorialBandEvidenceV1.intervalDays.count - 1, entry.rung + 1)
                        entry.dueDayOrdinal = o.canonicalDayOrdinal + EditorialBandEvidenceV1.intervalDays[entry.rung]
                        entry.status = .retained
                    }
                    // An early voluntary attempt never advances or postpones a scheduled rung.
                } else {
                    entry.dueDayOrdinal = o.canonicalDayOrdinal + 1; entry.status = .dueForDelayedCheck
                }
            } else {
                entry.missingCriterionIDs.formUnion(o.missingCriterionIDs)
                entry.originalAttemptID = entries[key]?.originalAttemptID ?? o.id
                entry.status = o.isIndependentRepair ? .stillNeedsSupport : .needsExplanation
                if o.credit < 0.5 {
                    entry.resetAfterIndependentRepair = true; entry.dueDayOrdinal = nil
                } else {
                    entry.dueDayOrdinal = o.canonicalDayOrdinal + min(3, EditorialBandEvidenceV1.intervalDays[entry.rung])
                }
            }
            entries[key] = entry
        }
        return entries.keys.sorted().compactMap { entries[$0] }
    }

    static func openingExplanation(_ entry: NFEditorialRetentionEntry, hasFreshSibling: Bool) -> NFEditorialRetentionEntry {
        var copy = entry
        if entry.status == .needsExplanation && hasFreshSibling { copy.status = .readyForRepair }
        return copy
    }

    static func dueEntries(_ entries: [NFEditorialRetentionEntry], day: Int, sessionSeconds: Double,
                           expectedSecondsByEntryID: [String: Double], explicitReviewSession: Bool = false) -> [NFEditorialRetentionEntry] {
        var remaining = max(0, sessionSeconds) * (explicitReviewSession ? 1 : 0.30)
        let cap = explicitReviewSession ? Int.max : 5
        let due = entries.filter { $0.status != .suspended && ($0.dueDayOrdinal.map { $0 <= day } ?? false) }
            .sorted { lhs, rhs in
                if lhs.missingCriterionIDs.isEmpty != rhs.missingCriterionIDs.isEmpty { return !lhs.missingCriterionIDs.isEmpty }
                if lhs.dueDayOrdinal != rhs.dueDayOrdinal { return (lhs.dueDayOrdinal ?? Int.max) < (rhs.dueDayOrdinal ?? Int.max) }
                return lhs.id < rhs.id
            }
        var selected: [NFEditorialRetentionEntry] = []
        for entry in due {
            guard selected.count < cap, let estimate = expectedSecondsByEntryID[entry.id],
                  estimate.isFinite, estimate > 0, estimate <= remaining else { continue }
            selected.append(entry); remaining -= estimate
        }
        return selected
    }
}

enum NFEditorialWorkMode: String, Codable, Sendable {
    case practice, repair, retention, protectedCheck, timedFluency, personalStudy, calibration, reflection
    var overheadSeconds: Double {
        switch self { case .practice, .repair, .retention: 8; case .protectedCheck: 6; case .timedFluency: 1
        case .personalStudy: 15; case .calibration: 10; case .reflection: 3 }
    }
}
struct NFEditorialWorkloadEstimate: Codable, Equatable, Sendable {
    enum Authority: String, Codable, Sendable { case reviewedRange, legacyAdvisory }
    let totalSeconds: Double
    let authority: Authority
}
enum NFEditorialWorkloadAdmission: String, Codable, Sendable {
    case fits, saveForLater, shorterTaskNeeded, durationUnavailable
}
enum NFEditorialWorkloadPolicy {
    /// A duration forecast does not grant a band or evidence eligibility. Legacy
    /// estimates remain explicitly advisory until an authored range is reviewed.
    static func runtimeEstimate(reviewedDemand: NFEditorialDemandRecord?, legacyExpectedResponseSeconds: Double?,
                                mode: NFEditorialWorkMode, compatibleCompleteDurations: [Double] = []) -> NFEditorialWorkloadEstimate? {
        if let item = reviewedDemand,
           let seconds = estimate(item: item, mode: mode, compatibleCompleteDurations: compatibleCompleteDurations) {
            return .init(totalSeconds: seconds, authority: .reviewedRange)
        }
        guard let seconds = legacyExpectedResponseSeconds, seconds.isFinite, seconds > 0 else { return nil }
        return .init(totalSeconds: seconds + mode.overheadSeconds, authority: .legacyAdvisory)
    }

    static func admission(estimate: NFEditorialWorkloadEstimate?, remainingSeconds: Double,
                          protected: Bool) -> NFEditorialWorkloadAdmission {
        guard let estimate, estimate.totalSeconds.isFinite, estimate.totalSeconds > 0 else { return .durationUnavailable }
        guard remainingSeconds.isFinite, remainingSeconds >= estimate.totalSeconds else {
            return protected ? .saveForLater : .shorterTaskNeeded
        }
        return .fits
    }

    /// The caller supplies actual candidate estimates in delivery order. Zero is
    /// intentional when no task fits; a nominal minimum must not force work.
    static func plannedItemCount(estimates: [NFEditorialWorkloadEstimate], budgetSeconds: Double,
                                 requestedMaximumCount: Int? = nil, mode: NFEditorialWorkMode) -> Int {
        let fitting = countFitting(estimatedSeconds: estimates.map(\.totalSeconds), remainingSeconds: budgetSeconds, mode: mode)
        return requestedMaximumCount.map { min(fitting, max(0, $0)) } ?? fitting
    }

    static func estimate(item: NFEditorialDemandRecord, mode: NFEditorialWorkMode,
                         compatibleCompleteDurations: [Double] = []) -> Double? {
        guard let range = item.expectedDurationRange, range.isValid else { return nil }
        let valid = Array(compatibleCompleteDurations.filter { $0.isFinite && $0 > 0 }.suffix(20)).sorted()
        let response: Double
        if valid.count >= 8 {
            let midpoint = valid.count / 2
            let median = valid.count.isMultiple(of: 2) ? (valid[midpoint - 1] + valid[midpoint]) / 2 : valid[midpoint]
            response = min(range.maximumSeconds, max(range.minimumSeconds, median))
        } else { response = range.medianSeconds }
        return response + mode.overheadSeconds
    }
    static func countFitting(estimatedSeconds: [Double], remainingSeconds: Double, mode: NFEditorialWorkMode) -> Int {
        guard remainingSeconds.isFinite, remainingSeconds > 0 else { return 0 }
        var consumed = 0.0
        var count = 0
        for seconds in estimatedSeconds {
            guard seconds.isFinite, seconds > 0, consumed + seconds <= remainingSeconds else { break }
            consumed += seconds; count += 1
            if mode == .reflection { break }
        }
        return count
    }
}

struct NFEditorialProtectedForm: Codable, Equatable, Sendable {
    let rootFormID: String
    let formID: String
    let protocolVersion: String
    let catalogVersion: String
    let dimensionID: String
    let requiredFormatIDs: Set<String>
    let supplementOrdinal: Int
    var presentedSemanticIDs: Set<String> = []
    var presentedSlotIDs: Set<String>? = nil
    var observedIDs: [String] = []
    var currentBand: NFEditorialBand = .b1
    var streak: [NFEditorialProtectedResponse] = []
    var sittingBudgetSeconds: Double = 300
    var sittingActiveSeconds: Double = 0
    var disclosed = false
}
struct NFEditorialProtectedResponse: Codable, Equatable, Sendable {
    let observationID: String
    let band: NFEditorialBand
    let isFullCredit: Bool
    let isZeroCredit: Bool
}
enum NFEditorialProtectedStop: String, Codable, Sendable { case complete, saveForLater, coverageIncomplete, replacementRequired }
enum NFEditorialProtectedPolicy {
    static let protocolVersion = "ProtectedEditorialV1"
    static let performanceDimensionIDs = ["mentalArithmetic", "quantitativeEstimation", "probability",
        "spatialTransformations", "dataInterpretation", "experimentalReasoning", "logic"]
    static let minimumObservations = 8
    static let presentationCap = 16

    static func effectiveObservations(form: NFEditorialProtectedForm, history: [NFEditorialObservation], evidence: NFEditorialEvidenceState,
                                      validity: NFEditorialValidityProjection = .init()) -> [NFEditorialObservation] {
        guard validity.revision == evidence.validityRevision else { return [] }
        let ids = Set(evidence.independentObservationIDs)
        var seen: Set<String> = []
        return history.sorted(by: EditorialBandEvidenceV1.stableOrder).filter {
            ids.contains($0.id) && seen.insert($0.id).inserted && $0.rootFormID == form.rootFormID
                && $0.formProtocolVersion == protocolVersion && $0.dimensionID == form.dimensionID
                && $0.lane == .protectedCheck
        }.map { original in
            guard let correction = validity.correctedScoreByObservationID[original.id] else { return original }
            var effective = original
            effective.credit = correction.credit
            effective.isFullCredit = correction.isFullCredit
            effective.isZeroCredit = correction.isZeroCredit
            return effective
        }
    }
    /// Record at durable item presentation, including items later skipped or
    /// invalidated. Replayed acknowledgement of the same slot is idempotent.
    static func presenting(slotID: String, semanticID: String, in form: NFEditorialProtectedForm) -> NFEditorialProtectedForm {
        var next = form
        guard !slotID.isEmpty, !semanticID.isEmpty else { return next }
        if next.presentedSlotIDs == nil { next.presentedSlotIDs = [] }
        next.presentedSlotIDs?.insert(slotID)
        next.presentedSemanticIDs.insert(semanticID)
        return next
    }
    static func stopReason(form: NFEditorialProtectedForm, effective: [NFEditorialObservation],
                           nextItemEstimate: Double?, hasValidPool: Bool) -> NFEditorialProtectedStop? {
        guard form.protocolVersion == protocolVersion, !form.disclosed else { return .replacementRequired }
        let formats = Set(effective.compactMap { $0.conditions.stimulusResponseFormatID })
        if effective.count >= minimumObservations && form.requiredFormatIDs.isSubset(of: formats) { return .complete }
        if max(form.presentedSemanticIDs.count, form.presentedSlotIDs?.count ?? 0) >= presentationCap || !hasValidPool { return .coverageIncomplete }
        guard let nextItemEstimate, nextItemEstimate.isFinite, nextItemEstimate > 0,
              nextItemEstimate <= form.sittingBudgetSeconds - form.sittingActiveSeconds else { return .saveForLater }
        return nil
    }
    static func recording(_ observation: NFEditorialObservation, in form: NFEditorialProtectedForm,
                          independent: Bool, availableBands: Set<NFEditorialBand>) -> NFEditorialProtectedForm {
        var next = form
        guard let item = observation.item, !next.observedIDs.contains(observation.id) else { return next }
        next.presentedSemanticIDs.insert(item.semanticFingerprint)
        next.observedIDs.append(observation.id)
        guard independent, observation.outcome == .scored else { next.streak = []; return next }
        if !observation.isFullCredit && !observation.isZeroCredit { next.streak = []; return next }
        next.streak.append(.init(observationID: observation.id, band: item.editorialBand,
                                isFullCredit: observation.isFullCredit, isZeroCredit: observation.isZeroCredit))
        next.streak = Array(next.streak.suffix(2))
        if next.streak.count == 2, next.streak.allSatisfy({ $0.band == next.currentBand }) {
            let target = next.streak.allSatisfy(\.isFullCredit) ? next.currentBand.higher
                : next.streak.allSatisfy(\.isZeroCredit) ? next.currentBand.lower : nil
            if let target, availableBands.contains(target) { next.currentBand = target; next.streak = [] }
        }
        return next
    }
    static func startingRecommendation(_ effective: [NFEditorialObservation]) -> NFEditorialBand? {
        let groups = Dictionary(grouping: effective) { $0.item!.editorialBand }
        return groups.keys.sorted(by: >).first { band in
            let items = groups[band]!
            return Set(items.filter(\.isFullCredit).compactMap { $0.item?.semanticFingerprint }).count >= 2
                && 2 * items.filter(\.isZeroCredit).count <= items.count
        }
    }
    static func acceptingSupplement(of form: NFEditorialProtectedForm) -> NFEditorialProtectedForm? {
        guard form.protocolVersion == protocolVersion, !form.disclosed else { return nil }
        let ordinal = form.supplementOrdinal + 1
        let id = NFStableDeterminism.hash64("\(form.rootFormID)|\(protocolVersion)|\(ordinal)|supplement")
        return .init(rootFormID: form.rootFormID, formID: "supplement.\(String(id, radix: 16))",
            protocolVersion: protocolVersion, catalogVersion: form.catalogVersion, dimensionID: form.dimensionID,
            requiredFormatIDs: form.requiredFormatIDs, supplementOrdinal: ordinal, currentBand: form.currentBand)
    }
    static func prioritizedFormat(form: NFEditorialProtectedForm, effective: [NFEditorialObservation]) -> String? {
        let counts = Dictionary(grouping: effective) { $0.conditions.stimulusResponseFormatID ?? "unknown" }.mapValues(\.count)
        return form.requiredFormatIDs.sorted().first { counts[$0, default: 0] == 0 }
    }
}

enum NFEditorialBlockStopReason: String, Codable, Sendable {
    case plannedWorkFinished, learnerStopped, timeBudgetUsed, suitableContentUnavailable, persistenceIssue, contentIssue
}
struct NFEditorialBlockCompletion: Codable, Equatable, Sendable {
    let blockID: String
    let validAnsweredItemCount: Int
    let reason: NFEditorialBlockStopReason
    let checkpointCommitted: Bool
    var participationCompleted: Bool { validAnsweredItemCount > 0 && checkpointCommitted && reason != .persistenceIssue }
    var promisedWorkCompleted: Bool { participationCompleted && reason == .plannedWorkFinished }
}


/// Authored compatibility for this exact admitted task. Missing metadata is not
/// inferred from a legacy reminder, a generic component name, or an error code.
enum NFEditorialReviewRole: String, Codable, CaseIterable, Sendable {
    case probe, repair, delayedCheck
}
struct NFEditorialReviewContract: Codable, Equatable, Sendable {
    var schemaVersion = 1
    let scopeID: String
    let criterionIDs: [String]
    let siblingStructureIDs: [String]
    let allowedRoles: [NFEditorialReviewRole]
    /// Role eligibility may differ between siblings; the authored scored scope
    /// cannot silently inherit another declaration's retention ladder.
    var compatibilityID: String {
        let fields = ["DeclaredReviewScopeV1", String(schemaVersion), scopeID, String(criterionIDs.count)]
            + criterionIDs + [String(siblingStructureIDs.count)] + siblingStructureIDs
        return NFReservationSnapshot.digest(Data(NFSelectionReservationPolicy.identity(fields).utf8))
    }
    func hasSameScope(as other: Self) -> Bool {
        schemaVersion == other.schemaVersion && scopeID == other.scopeID
            && criterionIDs == other.criterionIDs && siblingStructureIDs == other.siblingStructureIDs
    }
    var isSupported: Bool {
        schemaVersion == 1 && !scopeID.isEmpty && !scopeID.contains("|") && scopeID.utf8.count <= 256
            && !criterionIDs.isEmpty && criterionIDs.count <= 32
            && criterionIDs == Array(Set(criterionIDs)).sorted()
            && criterionIDs.allSatisfy { !$0.isEmpty && $0.utf8.count <= 256 }
            && !siblingStructureIDs.isEmpty && siblingStructureIDs.count <= 32
            && siblingStructureIDs == Array(Set(siblingStructureIDs)).sorted()
            && siblingStructureIDs.allSatisfy { !$0.isEmpty && $0.utf8.count <= 256 }
            && !allowedRoles.isEmpty && allowedRoles.count <= 3
            && allowedRoles.map(\.rawValue) == Array(Set(allowedRoles.map(\.rawValue))).sorted()
    }
}
struct NFEditorialReviewIntent: Codable, Equatable, Sendable {
    var schemaVersion = 1
    let role: NFEditorialReviewRole
    let originObservationID: String
    var isSupported: Bool { schemaVersion == 1 && role != .probe && UUID(uuidString: originObservationID) != nil }
}

/// A visible feedback acknowledgement, never a claim of understanding. It is
/// device-local authority; its standalone authority table is omitted from portable archives.
struct NFEditorialExplanationPresentation: Codable, Equatable, Sendable {
    var schemaVersion = 1
    let attemptID: UUID
    let sessionID: UUID
    let slotID: UUID
    let decisionID: String
    let ownerDeviceID: UUID
    let exerciseDigest: String
    let feedbackDigest: String
    let occurredAt: Date
    var isSupported: Bool {
        schemaVersion == 1 && !decisionID.isEmpty && occurredAt.timeIntervalSinceReferenceDate.isFinite
            && [exerciseDigest, feedbackDigest].allSatisfy { $0.count == 64 && $0.allSatisfy(\.isHexDigit) }
    }
}

/// The role of one accepted question. The frozen input identity and the exact
/// admitted candidate bind the origin, due day, scored criteria and explanation.
struct NFEditorialReviewAssignment: Codable, Equatable, Sendable {
    var schemaVersion = 1
    let policyVersion: String
    let candidateID: String
    let exerciseDigest: String
    let semanticFingerprint: String
    let contract: NFEditorialReviewContract
    let group: NFEditorialEvidenceGroup
    let role: NFEditorialReviewRole
    let decisionDayOrdinal: Int
    let expectedSeconds: Double
    var originObservationID: String? = nil
    var originObservationDigest: String? = nil
    var entry: NFEditorialRetentionEntry? = nil
    var explanation: NFEditorialExplanationPresentation? = nil
    var priority: Int { role == .probe ? 0 : 1 }
    var isSupported: Bool {
        guard schemaVersion == 1 && policyVersion == NFEditorialReviewSlotPolicy.version,
              !candidateID.isEmpty, !semanticFingerprint.isEmpty, contract.isSupported, contract.allowedRoles.contains(role),
              exerciseDigest.count == 64 && exerciseDigest.allSatisfy(\.isHexDigit), group.lane == .practice,
              NFSessionDurationPolicy.isValid(expectedSeconds), expectedSeconds > 0 else { return false }
        if role == .probe { return originObservationID == nil && originObservationDigest == nil && entry == nil && explanation == nil }
        guard let originObservationID, UUID(uuidString: originObservationID) != nil,
              let originObservationDigest, originObservationDigest.count == 64 && originObservationDigest.allSatisfy(\.isHexDigit),
              let entry, entry.scopeID == contract.scopeID, entry.objectiveID == group.objectiveID,
              entry.familyID == group.familyID, entry.band == group.band,
              entry.rung >= 0 && entry.rung < EditorialBandEvidenceV1.intervalDays.count,
              entry.status != .suspended, !entry.semanticExposureIDs.contains(semanticFingerprint) else { return false }
        if role == .repair {
            return explanation?.isSupported == true && explanation?.attemptID.uuidString == originObservationID
                && entry.status == .readyForRepair && !entry.missingCriterionIDs.isEmpty
                && entry.missingCriterionIDs.isSubset(of: Set(contract.criterionIDs))
        }
        return explanation == nil && !entry.resetAfterIndependentRepair
            && entry.dueDayOrdinal.map { $0 <= decisionDayOrdinal } == true
            && entry.lastIndependentDayOrdinal.map { $0 < decisionDayOrdinal } == true
            && entry.status != .needsExplanation && entry.status != .stillNeedsSupport
    }
}

enum NFEditorialReviewSlotPolicy {
    static let version = "DeclaredReviewSlotV1"

    static func normalizedGroup(_ group: NFEditorialEvidenceGroup) -> NFEditorialEvidenceGroup {
        .init(lane: .practice, objectiveID: group.objectiveID, familyID: group.familyID, band: group.band,
            bandContractVersion: group.bandContractVersion, scoringComparabilityID: group.scoringComparabilityID,
            stimulusComparabilityID: group.stimulusComparabilityID, toolConditionID: group.toolConditionID,
            localeComparabilityID: group.localeComparabilityID, pacingConditionID: group.pacingConditionID,
            protocolScope: "practice.v1")
    }
    static func entryID(item: NFEditorialDemandRecord, group: NFEditorialEvidenceGroup, scopeID: String) -> String {
        [item.objectiveID, item.familyID, item.editorialBand.rawValue, scopeID, item.bandContractVersion,
         group.scoringComparabilityID, group.stimulusComparabilityID, group.toolConditionID,
         group.localeComparabilityID, group.pacingConditionID].joined(separator: "|")
            + (item.reviewContract.map { "|" + $0.compatibilityID } ?? "")
    }
    static func contract(exercise: NFExercise, admission: NFEditorialAdmissionEntry,
                         timing: NFEditorialTimingMode?, day: Int) -> NFEditorialReviewAssignment? {
        guard let authored = admission.demand.reviewContract, authored.isSupported,
              authored.siblingStructureIDs.contains(admission.demand.structureID),
              let criterion = NFEditorialCriterionRankingPolicy.contract(exercise: exercise, admission: admission, timing: timing),
              criterion.coverageRaw == "scoredComponents",
              Set(authored.criterionIDs) == Set(criterion.criterionIDs),
              [criterion.group.objectiveID, criterion.group.familyID, criterion.group.bandContractVersion,
               criterion.group.scoringComparabilityID, criterion.group.stimulusComparabilityID,
               criterion.group.toolConditionID, criterion.group.localeComparabilityID,
               criterion.group.pacingConditionID].allSatisfy({ !$0.contains("|") }),
              let duration = admission.demand.expectedDurationRange, duration.isValid else { return nil }
        // The initial role is selected below; a delayed-only sibling must not be
        // silently delivered as ordinary practice before its origin is eligible.
        return .init(policyVersion: version, candidateID: admission.bankQuestionID,
            exerciseDigest: admission.exerciseDigest, semanticFingerprint: admission.demand.semanticFingerprint, contract: authored, group: criterion.group,
            role: .probe, decisionDayOrdinal: day, expectedSeconds: duration.medianSeconds + 8)
    }

    struct Budget: Sendable {
        let totalSeconds: Double
        let usedSeconds: Double
        let usedCount: Int
        let explicitReview: Bool
        var remainingSeconds: Double {
            guard NFSessionDurationPolicy.isValid(totalSeconds), totalSeconds > 0,
                  NFSessionDurationPolicy.isValid(usedSeconds), usedCount >= 0 else { return 0 }
            return max(0, totalSeconds * (explicitReview ? 1 : 0.30) - usedSeconds)
        }
        var hasCapacity: Bool { usedCount >= 0 && (explicitReview || usedCount < 5) && remainingSeconds > 0 }
    }

    /// Input observations come only from authenticated native captures and the
    /// shared effective-evidence reducer. No self-report or reminder is a source.
    static func project(contracts: [String: NFEditorialReviewAssignment],
        input: NFEditorialLiveController.Input, evidence: NFEditorialEvidenceState,
        explanations: [String: NFEditorialExplanationPresentation], repairOriginID: String?,
        intent: NFEditorialReviewIntent?, budget: Budget, currentSessionID: String? = nil) throws -> [String: NFEditorialReviewAssignment] {
        guard evidence.policyVersion == EditorialBandEvidenceV1.policyVersion,
              evidence.validityRevision == input.validity.revision, intent?.isSupported != false else { return [:] }
        let independent = Set(evidence.independentObservationIDs)
        let grouped = Dictionary(grouping: input.observations, by: \.id)
        let observations = grouped.values.compactMap { copies -> NFEditorialObservation? in
            guard let first = copies.first, copies.allSatisfy({ $0 == first }), independent.contains(first.id),
                  first.sourceOrSetID == nil, first.lane == .practice || first.lane == .retention,
                  input.validity.correctedScoreByObservationID[first.id] == nil,
                  input.validity.validity(of: first) == .valid,
                  first.canonicalDayOrdinal <= input.day.ordinal,
                  first.item?.reviewContract?.isSupported == true else { return nil }
            return first
        }.sorted(by: EditorialBandEvidenceV1.stableOrder)
        let byID = Dictionary(uniqueKeysWithValues: observations.map { ($0.id, $0) })
        struct RepairScope: Hashable { let group: NFEditorialEvidenceGroup; let scopeID: String }
        var recentFailures: [RepairScope: NFEditorialObservation] = [:]
        for value in observations where value.sessionID == currentSessionID && !value.isFullCredit && explanations[value.id] != nil {
            if let scope = value.retentionScopeID, let group = EditorialBandEvidenceV1.group(for: value) {
                recentFailures[.init(group: normalizedGroup(group), scopeID: scope)] = value
            }
        }
        var estimates: [String: Double] = [:]
        func entryKey(_ base: NFEditorialReviewAssignment) -> String {
            [base.group.objectiveID, base.group.familyID, base.group.band.rawValue,
             base.contract.scopeID, base.group.bandContractVersion, base.group.scoringComparabilityID,
             base.group.stimulusComparabilityID, base.group.toolConditionID, base.group.localeComparabilityID,
             base.group.pacingConditionID, base.contract.compatibilityID].joined(separator: "|")
        }
        for base in contracts.values {
            let key = entryKey(base)
            estimates[key] = min(estimates[key] ?? .infinity, base.expectedSeconds)
        }
        let entriesByID = Dictionary(evidence.retention.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let dueIDs = Set(NFEditorialRetentionPolicy.dueEntries(evidence.retention, day: input.day.ordinal,
            sessionSeconds: budget.remainingSeconds, expectedSecondsByEntryID: estimates,
            explicitReviewSession: true).map(\.id))
        var result: [String: NFEditorialReviewAssignment] = [:]
        for (id, base) in contracts where id == base.candidateID {
            if intent == nil, base.contract.allowedRoles.contains(.probe) { result[id] = base }
            guard budget.hasCapacity, base.expectedSeconds <= budget.remainingSeconds else { continue }
            let entries = entriesByID[entryKey(base)].map { [$0] } ?? []
            for stored in entries {
                guard stored.status != .suspended, !stored.semanticExposureIDs.contains(base.semanticFingerprint) else { continue }
                var chosen = base
                let role: NFEditorialReviewRole
                let origin: NFEditorialObservation
                let recentRepair = recentFailures[.init(group: base.group, scopeID: base.contract.scopeID)]?.id
                let hintedRepair = repairOriginID.flatMap { id -> String? in
                    guard let value = byID[id], value.item?.reviewContract?.hasSameScope(as: base.contract) == true,
                          EditorialBandEvidenceV1.group(for: value).map(normalizedGroup) == base.group else { return nil }
                    return id
                }
                if let target = intent?.role == .repair ? intent?.originObservationID : (hintedRepair ?? recentRepair),
                   let failed = byID[target], failed.retentionScopeID == base.contract.scopeID,
                   failed.item?.reviewContract?.hasSameScope(as: base.contract) == true,
                   !failed.isFullCredit, !failed.missingCriterionIDs.isEmpty,
                   let group = EditorialBandEvidenceV1.group(for: failed), normalizedGroup(group) == base.group,
                   let explanation = explanations[target], explanation.attemptID.uuidString == failed.id,
                   explanation.sessionID.uuidString == failed.sessionID,
                   base.contract.allowedRoles.contains(.repair), intent?.role != .delayedCheck {
                    var repair = stored
                    // A displayed explanation is independent of the academic
                    // outcome. Use the existing explicit transition; never claim
                    // the person understood it or completed the sibling.
                    repair = NFEditorialRetentionPolicy.openingExplanation(repair, hasFreshSibling: true)
                    guard repair.status == .readyForRepair,
                          failed.missingCriterionIDs.isSubset(of: Set(base.contract.criterionIDs)) else { continue }
                    role = .repair; origin = failed; chosen.entry = repair; chosen.explanation = explanation
                } else {
                    guard intent?.role != .repair, dueIDs.contains(stored.id),
                          let anchor = stored.lastIndependentObservationID, let latest = byID[anchor],
                          latest.retentionScopeID == base.contract.scopeID, latest.item?.reviewContract?.hasSameScope(as: base.contract) == true,
                          intent?.originObservationID == nil || intent?.originObservationID == anchor,
                          let group = EditorialBandEvidenceV1.group(for: latest), normalizedGroup(group) == base.group,
                          base.contract.allowedRoles.contains(.delayedCheck) else { continue }
                    role = .delayedCheck; origin = latest; chosen.entry = stored
                }
                chosen = .init(policyVersion: version, candidateID: chosen.candidateID, exerciseDigest: chosen.exerciseDigest,
                    semanticFingerprint: chosen.semanticFingerprint, contract: chosen.contract, group: chosen.group, role: role, decisionDayOrdinal: input.day.ordinal,
                    expectedSeconds: chosen.expectedSeconds, originObservationID: origin.id,
                    originObservationDigest: try NFEditorialCanonicalData.digest(origin), entry: chosen.entry,
                    explanation: chosen.explanation)
                if chosen.isSupported { result[id] = chosen; break }
            }
        }
        return result
    }

}

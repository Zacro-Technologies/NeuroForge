import Foundation

enum NFSessionDurationPolicy {
    // Conversion safety, not an estimate of believable solving time. Keep room
    // for cumulative plus in-flight chunks before any Int conversion.
    static let maximumSeconds = Double(Int.max / 4)
    static func isValid(_ value: TimeInterval) -> Bool { value.isFinite && value >= 0 && value <= maximumSeconds }
    static func wholeSeconds(_ value: TimeInterval) -> Int? {
        isValid(value) ? Int(value.rounded(.up)) : nil
    }
}

/// nil on a SessionRequest preserves the prior saved Boolean timing contract.
/// Raw mode/version fields retain future payloads for read-only recovery.
struct NFSessionTimingCondition: Codable, Equatable, Sendable {
    var schemaVersion = 1
    var modeRaw: String
    var fluencyScope: NFEditorialEvidenceGroup? = nil
    init(_ mode: NFEditorialTimingMode, fluencyScope: NFEditorialEvidenceGroup? = nil) {
        modeRaw = mode.rawValue; self.fluencyScope = fluencyScope
    }
    var mode: NFEditorialTimingMode? { NFEditorialTimingMode(rawValue: modeRaw) }
    var isSupported: Bool {
        schemaVersion == 1 && mode != nil && (mode == .timedFluency ? fluencyScope != nil : fluencyScope == nil)
    }
    /// The caller must authenticate this demand against the installed manifest
    /// and exact retained exercise. Serialized generator metadata is not admission.
    func accepts(_ exercise: NFExercise, reviewedDemand: NFEditorialDemandRecord? = nil) -> Bool {
        guard isSupported else { return false }
        guard mode == .timedFluency else { return true }
        guard let scope = fluencyScope, let item = reviewedDemand,
              item.hasRequiredIdentity, item.independentEligible, item.reviewedFluencyEligible,
              !exercise.assessmentProtected, exercise.evidenceClass == .practice else { return false }
        return scope.objectiveID == item.objectiveID && scope.familyID == item.familyID
            && scope.band == item.editorialBand && scope.bandContractVersion == item.bandContractVersion
            && scope.scoringComparabilityID == (item.scoringComparabilityID ?? item.answerContractVersion)
            && scope.stimulusComparabilityID == (item.stimulusComparabilityID ?? NFRetentionRepresentation.identifier(for: exercise))
            && scope.toolConditionID == item.assistancePolicyID
            && scope.localeComparabilityID == (item.localeComparabilityID ?? exercise.localeIdentifier)
    }
}

struct NFReviewedFluencyReadiness: Equatable, Sendable {
    enum Reason: String, Sendable { case reviewedPracticeUnavailable, moreIndependentPractice, unresolvedCriterion, ready }
    let scope: NFEditorialEvidenceGroup?
    let sampleCount: Int
    let reason: Reason
    var transferEligible = false
    var timingEligible: Bool { reason == .ready && scope != nil }
    var condition: NFSessionTimingCondition? { timingEligible ? .init(.timedFluency, fluencyScope: scope) : nil }
    var explanation: String {
        switch reason {
        case .reviewedPracticeUnavailable: "Timed fluency needs reviewed practice for this activity. Untimed and elapsed-only practice are available."
        case .moreIndependentPractice: "Timed fluency needs eight recent independent untimed successes in the same reviewed family and band across two sessions."
        case .unresolvedCriterion: "Practice the unresolved step before choosing timed fluency. Untimed and elapsed-only practice are available."
        case .ready: "Your reviewed practice supports choosing timed fluency for this family and band. Timing remains optional."
        }
    }
}

enum NFEditorialChallengeMode: Codable, Equatable, Sendable { case adaptive, fixedBand(NFEditorialBand) }
enum NFEditorialSelectionReason: String, Codable, Sendable {
    case coldStartDefault, userRequested, protectedCheckSuggestion, recentPracticeTarget, refreshProbe
    case continueCurrentChallenge, userFixedBand, independentDifficultyPattern, independentSuccessPattern
    case foundationSupport, nextBandUnavailable, noCompatibleContent
}
struct NFEditorialPracticeControl: Codable, Equatable, Sendable {
    let sessionID: String
    let objectiveID: String
    let familyID: String
    let initialTargetBand: NFEditorialBand
    var currentTargetBand: NFEditorialBand
    var challengeMode: NFEditorialChallengeMode = .adaptive
    var upwardChangesThisSession = 0
    var totalAutomaticChangesThisSession = 0
    var eligibleResponsesSinceLastAutomaticChange = 0
    var currentBandDecisionResponseIDs: [String] = []
    var presentedSupportEvents: [Bool] = []
    var overrideScope = "session"
    var decisionOrdinal = 0
    var selectedExercisePath: [NFEditorialSelectionReceipt] = []
    var processedObservationIDs: [String]? = nil
    var processedPresentationIDs: [String]? = nil
    var shouldOfferSupport: Bool { presentedSupportEvents.suffix(3).filter { $0 }.count >= 2 }

    mutating func override(to band: NFEditorialBand, keepLevel: Bool = false) {
        if band != currentTargetBand { currentBandDecisionResponseIDs = []; eligibleResponsesSinceLastAutomaticChange = 0 }
        currentTargetBand = band
        challengeMode = keepLevel ? .fixedBand(band) : .adaptive
    }
}
struct NFEditorialSelectionCandidate: Codable, Equatable, Sendable {
    let id: String
    let item: NFEditorialDemandRecord
    var valid = true
    var accessibilityCompatible = true
    var languageCompatible = true
    var prerequisitesMet = true
    var alreadyConsumed = false
    var reservedByOtherOwner = false
    var previouslyExposed = false
    var protectedSolutionExposed = false
    var reviewContractCompatible = true
    var requiredCoverageDeficit = 0
    var dueRepairPriority = 0
    var goalRelevance = 0
    var observedWeakCriterionMatch = 0
}
struct NFEditorialSelectionContext: Codable, Equatable, Sendable {
    let catalogVersion: String
    let profilePseudonymousID: String
    let remainingSittingSeconds: Double
    var explicitOverrunAllowance: Double = 0
    var mixedPractice = false
    var lane: NFEditorialEvidenceLane = .practice
    var recentFamilyIDs: [String] = []
    var recentStructureIDs: [String] = []
    var sessionSemanticIDs: Set<String> = []
    var expectedOverheadSeconds: Double = 8
    var initialTargetContracts: [NFEditorialInitialTargetContract]? = nil
    var criterionSelections: [String: NFEditorialCriterionSelection]? = nil
    var reviewAssignments: [String: NFEditorialReviewAssignment]? = nil
    var goalSelections: [String: NFEditorialGoalSelection]? = nil
}
struct NFEditorialSelectionReceipt: Codable, Equatable, Sendable {
    let candidateID: String
    let semanticFingerprint: String
    let requestedBand: NFEditorialBand
    let deliveredBand: NFEditorialBand
    let reason: NFEditorialSelectionReason
    let policyVersion: String
    let catalogVersion: String
    let validityRevision: String
    let decisionOrdinal: Int
    let observationIDs: [String]
    let ruleCredits: [Double]
    let tieKey: UInt64
    let unmetVarietyPreferences: [String]
    var evidenceLaterExcluded: Bool = false
}
struct NFEditorialSelectionResult: Equatable, Sendable {
    let candidate: NFEditorialSelectionCandidate?
    let control: NFEditorialPracticeControl
    let reason: NFEditorialSelectionReason
    let shortageOptions: [String]
}

enum NFEditorialPracticePolicy {
    static func initialControl(sessionID: String, objectiveID: String, familyID: String,
                               explicitBand: NFEditorialBand? = nil, suggestedProtectedBand: NFEditorialBand? = nil,
                               recentTargetBand: NFEditorialBand? = nil, daysSincePractice: Int? = nil)
        -> (NFEditorialPracticeControl, NFEditorialSelectionReason) {
        let band = explicitBand ?? suggestedProtectedBand ?? recentTargetBand ?? .b1
        let reason: NFEditorialSelectionReason = explicitBand != nil ? .userRequested
            : (daysSincePractice ?? 0) >= 30 && recentTargetBand != nil ? .refreshProbe
            : suggestedProtectedBand != nil ? .protectedCheckSuggestion
            : recentTargetBand != nil ? .recentPracticeTarget : .coldStartDefault
        return (.init(sessionID: sessionID, objectiveID: objectiveID, familyID: familyID,
                      initialTargetBand: band, currentTargetBand: band), reason)
    }

    static func selectNext(control original: NFEditorialPracticeControl, observation: NFEditorialObservation?,
                           history: [NFEditorialObservation], evidence: NFEditorialEvidenceState,
                           candidates: [NFEditorialSelectionCandidate], context: NFEditorialSelectionContext,
                           validity: NFEditorialValidityProjection = .init(),
                           recordsSupportFromObservation: Bool = true,
                           selectionReasonOverride: NFEditorialSelectionReason? = nil) -> NFEditorialSelectionResult {
        var control = original
        let effectiveIDs = Set(evidence.independentObservationIDs)
        control.currentBandDecisionResponseIDs.removeAll { !effectiveIDs.contains($0) }
        control.selectedExercisePath = control.selectedExercisePath.map { receipt in
            var copy = receipt
            if receipt.observationIDs.contains(where: { evidence.exclusions[$0] == "contentExcluded" }) { copy.evidenceLaterExcluded = true }
            return copy
        }
        control.eligibleResponsesSinceLastAutomaticChange = control.currentBandDecisionResponseIDs.count
        var appendedIndependentResponse = false
        if let o = observation, o.sessionID == control.sessionID,
           !(control.processedObservationIDs ?? []).contains(o.id) {
            control.processedObservationIDs = (control.processedObservationIDs ?? []) + [o.id]
            if recordsSupportFromObservation {
                control.presentedSupportEvents.append(o.helpBeforeLock || o.workedSolutionBeforeLock || o.outcome == .replaced)
                control.presentedSupportEvents = Array(control.presentedSupportEvents.suffix(3))
            }
            if effectiveIDs.contains(o.id), o.item?.editorialBand == control.currentTargetBand,
               o.item?.objectiveID == control.objectiveID, o.item?.familyID == control.familyID,
               !control.currentBandDecisionResponseIDs.contains(o.id) {
                control.currentBandDecisionResponseIDs.append(o.id)
                control.eligibleResponsesSinceLastAutomaticChange += 1
                appendedIndependentResponse = true
            }
        }
        let byID = Dictionary(history.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let responses = control.currentBandDecisionResponseIDs.compactMap { byID[$0] }.map { o -> NFEditorialObservation in
            guard let correction = validity.correctedScoreByObservationID[o.id] else { return o }
            var effective = o; effective.credit = correction.credit; effective.isFullCredit = correction.isFullCredit; effective.isZeroCredit = correction.isZeroCredit
            return effective
        }
        let feasible = feasibleCandidates(candidates, control: control, context: context, validity: validity)
        var band = control.currentTargetBand
        var reason: NFEditorialSelectionReason = selectionReasonOverride ?? .continueCurrentChallenge
        switch control.challengeMode {
        case let .fixedBand(fixed): band = fixed; reason = .userFixedBand
        case .adaptive:
            if appendedIndependentResponse, control.totalAutomaticChangesThisSession < 2,
               control.totalAutomaticChangesThisSession == 0 || control.eligibleResponsesSinceLastAutomaticChange >= 2 {
                let down = Array(responses.suffix(3))
                let up = Array(responses.suffix(4))
                if down.count == 3, down.filter(\.isZeroCredit).count >= 2,
                   down.reduce(0, { $0 + $1.credit }) / 3 <= 1.0 / 3 + EditorialBandEvidenceV1.epsilon {
                    if let lower = band.lower, feasible.contains(where: { $0.item.editorialBand == lower }) {
                        band = lower; reason = .independentDifficultyPattern
                    } else { reason = band == .b1 ? .foundationSupport : .nextBandUnavailable }
                } else if control.upwardChangesThisSession == 0, up.count == 4,
                          up.filter(\.isFullCredit).count >= 3, up.allSatisfy({ $0.credit >= 0.5 }),
                          up.reduce(0, { $0 + $1.credit }) / 4 + EditorialBandEvidenceV1.epsilon >= 0.875,
                          let higher = band.higher {
                    if Set(feasible.filter { $0.item.editorialBand == higher }.map { $0.item.semanticFingerprint }).count >= 3 {
                        band = higher; reason = .independentSuccessPattern
                    } else { reason = .nextBandUnavailable }
                }
            }
        }
        // Compute each stable rank/hash once; a large numerical family must not
        // multiply ranking cost or gain extra priority from its raw pool size.
        let ranked = feasible.filter { $0.item.editorialBand == band }.map { candidate in
            (candidate, rank(candidate, context: context), tieKey(candidate.id, control: control, context: context))
        }.sorted { left, right in
            for (a, b) in zip(left.1, right.1) where a != b { return a < b }
            return left.2 == right.2 ? left.0.id < right.0.id : left.2 < right.2
        }.map { $0.0 }
        guard let selected = ranked.first else {
            return .init(candidate: nil, control: control, reason: .noCompatibleContent,
                         shortageOptions: ["Review a familiar problem", "Choose a supported adjacent band", "Choose another activity", "End this block"])
        }
        let supportedFamilies = Set(feasible.map { $0.item.familyID })
        var unmet: [String] = []
        if context.mixedPractice && supportedFamilies.count < 4 { unmet.append("fewerThanFourCompatibleFamilies") }
        if context.mixedPractice && context.recentFamilyIDs.suffix(2).allSatisfy({ $0 == selected.item.familyID }) && context.recentFamilyIDs.count >= 2 { unmet.append("familyRunAboveTwo") }
        let receipt = NFEditorialSelectionReceipt(candidateID: selected.id, semanticFingerprint: selected.item.semanticFingerprint,
            requestedBand: band, deliveredBand: selected.item.editorialBand, reason: reason,
            policyVersion: EditorialBandEvidenceV1.policyVersion, catalogVersion: context.catalogVersion,
            validityRevision: validity.revision, decisionOrdinal: control.decisionOrdinal,
            observationIDs: responses.map(\.id), ruleCredits: responses.map(\.credit),
            tieKey: tieKey(selected.id, control: control, context: context), unmetVarietyPreferences: unmet)
        if band != control.currentTargetBand {
            if band > control.currentTargetBand { control.upwardChangesThisSession += 1 }
            control.totalAutomaticChangesThisSession += 1
            control.currentBandDecisionResponseIDs = []
            control.eligibleResponsesSinceLastAutomaticChange = 0
            control.currentTargetBand = band
        }
        control.selectedExercisePath.append(receipt)
        control.decisionOrdinal += 1
        return .init(candidate: selected, control: control, reason: reason, shortageOptions: [])
    }

    static func feasibleCandidates(_ candidates: [NFEditorialSelectionCandidate], control: NFEditorialPracticeControl,
                                   context: NFEditorialSelectionContext, validity: NFEditorialValidityProjection) -> [NFEditorialSelectionCandidate] {
        return candidates.filter { candidate in
            let i = candidate.item
            guard candidate.valid, validity.canSelect(i), i.hasRequiredIdentity,
                  context.lane == .personalStudy || i.independentEligible else { return false }
            if context.lane == .protectedCheck && (!i.protectedEligible || candidate.protectedSolutionExposed) { return false }
            guard candidate.accessibilityCompatible, candidate.languageCompatible, candidate.prerequisitesMet,
                  i.objectiveID == control.objectiveID,
                  context.mixedPractice || i.familyID == control.familyID else { return false }
            guard !candidate.previouslyExposed, !candidate.protectedSolutionExposed,
                  !context.sessionSemanticIDs.contains(i.semanticFingerprint),
                  !control.selectedExercisePath.contains(where: { $0.semanticFingerprint == i.semanticFingerprint }),
                  !candidate.alreadyConsumed, !candidate.reservedByOtherOwner, candidate.reviewContractCompatible else { return false }
            guard let duration = i.expectedDurationRange, duration.isValid,
                  context.remainingSittingSeconds.isFinite, context.explicitOverrunAllowance.isFinite else { return false }
            return duration.medianSeconds + context.expectedOverheadSeconds
                <= context.remainingSittingSeconds + max(0, context.explicitOverrunAllowance)
        }
    }

    private static func rank(_ c: NFEditorialSelectionCandidate, context: NFEditorialSelectionContext) -> [Int] {
        let family = c.item.familyID
        let familyCount = context.recentFamilyIDs.suffix(100).filter { $0 == family }.count
        let run = context.recentFamilyIDs.count >= 2 && context.recentFamilyIDs.suffix(2).allSatisfy { $0 == family }
        return [-c.requiredCoverageDeficit, -c.dueRepairPriority,
                context.mixedPractice && run ? 1 : 0, context.mixedPractice ? familyCount : 0,
                context.recentStructureIDs.suffix(100).filter { $0 == c.item.structureID }.count,
                -c.goalRelevance, -c.observedWeakCriterionMatch]
    }
    private static func tieKey(_ candidateID: String, control: NFEditorialPracticeControl, context: NFEditorialSelectionContext) -> UInt64 {
        NFStableDeterminism.hash64([EditorialBandEvidenceV1.policyVersion, context.catalogVersion,
            context.profilePseudonymousID, control.sessionID, String(control.decisionOrdinal), candidateID,
            "question-selection"].map { "\($0.utf8.count):\($0)" }.joined())
    }

    static func reviewedFluencyReadiness(observations: [NFEditorialObservation], decisionDayOrdinal: Int,
                                        validity: NFEditorialValidityProjection = .init()) -> NFReviewedFluencyReadiness {
        let evidence = EditorialBandEvidenceV1.reduce(observations, decisionDayOrdinal: decisionDayOrdinal, validity: validity)
        let independent = Set(evidence.independentObservationIDs)
        let eligible = observations.filter {
            independent.contains($0.id) && $0.lane == .practice && $0.item?.reviewedFluencyEligible == true
                && $0.conditions.timingMode == .untimed && decisionDayOrdinal - $0.canonicalDayOrdinal < 60
        }
        let effective = eligible.map { original in
            guard let correction = validity.correctedScoreByObservationID[original.id] else { return original }
            var copy = original; copy.credit = correction.credit
            copy.isFullCredit = correction.isFullCredit; copy.isZeroCredit = correction.isZeroCredit
            return copy
        }
        let groups = Dictionary(grouping: effective) { EditorialBandEvidenceV1.group(for: $0)! }
        let results = groups.keys.sorted { $0.stableID < $1.stableID }.map { group -> NFReviewedFluencyReadiness in
            var seen: Set<String> = []
            let recent = Array((groups[group] ?? []).sorted(by: EditorialBandEvidenceV1.stableOrder)
                .filter { seen.insert($0.id).inserted }.suffix(20))
            var unresolvedCounts: [String: Int] = [:]
            for observation in recent {
                for (criterion, credit) in observation.rubricCriterionCredits where credit == 1 { unresolvedCounts[criterion] = 0 }
                for criterion in observation.missingCriterionIDs { unresolvedCounts[criterion, default: 0] += 1 }
            }
            let unresolved = unresolvedCounts.values.contains { $0 >= 2 }
            let full = recent.filter(\.isFullCredit)
            return .init(scope: group, sampleCount: full.count,
                reason: unresolved ? .unresolvedCriterion
                    : full.count >= 8 && Set(full.map(\.sessionID)).count >= 2 ? .ready : .moreIndependentPractice)
        }
        var result = results.first { $0.timingEligible } ?? results.max { $0.sampleCount < $1.sampleCount }
            ?? .init(scope: nil, sampleCount: 0, reason: .reviewedPracticeUnavailable)
        if let scope = result.scope, result.timingEligible {
            let speed = Set(evidence.cleanSpeedObservationIDs)
            result.transferEligible = observations.filter {
                guard speed.contains($0.id), let group = EditorialBandEvidenceV1.group(for: $0) else { return false }
                return group.objectiveID == scope.objectiveID && group.familyID == scope.familyID
                    && group.band == scope.band && group.bandContractVersion == scope.bandContractVersion
                    && group.scoringComparabilityID == scope.scoringComparabilityID
                    && group.toolConditionID == scope.toolConditionID && group.localeComparabilityID == scope.localeComparabilityID
            }.count >= 8
        }
        return result
    }

    static func timedFluencyEligible(observations: [NFEditorialObservation], evidence: NFEditorialEvidenceState,
                                    familyID: String, band: NFEditorialBand, explicitlyChosen: Bool,
                                    unresolvedConceptualError: Bool) -> Bool {
        guard explicitlyChosen, !unresolvedConceptualError else { return false }
        let ids = Set(evidence.independentObservationIDs)
        let usable = observations.filter { ids.contains($0.id) && $0.isFullCredit
            && $0.item?.familyID == familyID && $0.item?.editorialBand == band
            && $0.item?.reviewedFluencyEligible == true && $0.conditions.timingMode == .untimed
            && evidence.decisionDayOrdinal - $0.canonicalDayOrdinal < 60 }
        let groups = Dictionary(grouping: usable) { EditorialBandEvidenceV1.group(for: $0) }
        return groups.values.contains { $0.count >= 8 && Set($0.map(\.sessionID)).count >= 2 }
    }
}


// MARK: - Authenticated editorial delivery adapter

/// This value is built by the application from a reviewed manifest, never by
/// decoding a backup, learner preference or generator review-status string.
/// Tests inject a synthetic catalog; the released catalog deliberately is empty.
struct NFEditorialAdmissionContext: Sendable {
    let version: String
    let entries: [NFEditorialAdmissionEntry]
    let fingerprint: String
    let goalAlignmentsAreConsistent: Bool
    var hasGoalAlignments: Bool { entries.contains { $0.demand.goalAlignment != nil } }
    static let released = Self(version: "reviewed-catalog-unavailable.v1", entries: [])

    init(version: String, entries: [NFEditorialAdmissionEntry]) {
        self.version = version
        self.entries = entries
        self.goalAlignmentsAreConsistent = NFEditorialGoalRankingPolicy.consistentAlignments(entries)
        self.fingerprint = (try? NFEditorialCanonicalData.digest(entries.sorted { $0.id < $1.id })) ?? ""
    }

    func entry(exercise: NFExercise, pin: NFEditorialSessionPin? = nil) -> NFEditorialAdmissionEntry? {
        guard fingerprint.count == 64, entries.count <= 4_096,
              Set(entries.map(\.id)).count == entries.count,
              let digest = try? NFLocalItemCheckpoint.digest(exercise), !exercise.assessmentProtected,
              exercise.evidenceClass == .practice, exercise.availabilityReason == nil,
              exercise.provenance.sourceDocumentIDs.isEmpty,
              NFEditorialNativeProtocol.supports(exercise) else { return nil }
        let matches = entries.filter { entry in
            entry.exerciseDigest == digest && entry.isSupported
                && entry.demand.semanticFingerprint == (exercise.contractMetadata?.semanticFingerprint
                    ?? NFQuestionFingerprint.fingerprint(for: exercise))
                && entry.contentLocale == exercise.localeIdentifier && entry.lab == exercise.lab
                && (pin.map { $0.catalogVersion == version && $0.catalogDigest == fingerprint
                    && $0.contains(objectiveID: entry.demand.objectiveID, familyID: entry.demand.familyID)
                    && $0.catalogScope?.matches(exercise) != false } ?? true)
        }
        guard matches.count == 1 else { return nil }
        return matches[0]
    }

    func acceptsTiming(_ condition: NFSessionTimingCondition?, exercise: NFExercise,
                       pin: NFEditorialSessionPin? = nil) -> Bool {
        guard let condition else { return true }
        guard condition.mode == .timedFluency else { return condition.isSupported }
        guard let entry = entry(exercise: exercise, pin: pin) else { return false }
        return condition.accepts(exercise, reviewedDemand: entry.demand)
    }

    func sessionPin(for request: SessionRequest, initialUserBand: NFEditorialBand? = nil,
                    startingScope: NFEditorialFamilyScope? = nil, catalogScope: NFEditorialCatalogScope? = nil,
                    goalPreferences: NFEditorialGoalPreferences? = nil) -> NFEditorialSessionPin? {
        guard !entries.isEmpty, request.ordinaryDelivery?.strategy == .adaptiveItem,
              request.mechanicID == nil, request.evidenceClass == .practice,
              request.assessmentBlock == nil, request.transferBrief == nil,
              request.retentionTargets.isEmpty, request.timingCondition?.isSupported == true,
              startingScope?.isSupported != false else { return nil }
        // Each admitted family keeps its own challenge control. Explicit starting
        // bands remain a single-family activity rather than raising all objectives.
        let eligible = entries.filter { $0.isSupported && $0.lab == request.lab
            && $0.contentLocale == request.localeIdentifier
            // New automatic runs retain every admitted family. V2 determines
            // each family's initial target from compatible history; requiring a
            // B1 catalog row here would erase a valid B2-only family before that
            // decision. Cold B1 remains unavailable when no B1 contract exists.
            && (initialUserBand == nil || $0.demand.editorialBand == initialUserBand) }
            .filter { entry in startingScope.map { $0.objectiveID == entry.demand.objectiveID && $0.familyID == entry.demand.familyID } ?? true }
            .sorted { $0.id < $1.id }
        guard let first = eligible.first else { return nil }
        let hasReviewContracts = eligible.contains { $0.demand.reviewContract != nil }
        let usesGoals = eligible.contains { $0.demand.goalAlignment != nil } && goalPreferences != nil
        guard !usesGoals || (goalAlignmentsAreConsistent && goalPreferences?.isSupported == true
            && goalPreferences?.profileID == request.ordinaryDelivery?.profileID) else { return nil }
        let selectedController = usesGoals ? NFEditorialLiveController.goalVersion
            : hasReviewContracts ? NFEditorialLiveController.reviewVersion : NFEditorialLiveController.version
        let frozenGoals = usesGoals ? goalPreferences : nil
        if let catalogScope {
            guard catalogScope.isSupported, catalogScope.field == request.field, startingScope != nil,
                  NFDefaultContentCatalog.activity(id: catalogScope.activityID)?.lab == request.lab else { return nil }
            return .init(schemaVersion: 3, catalogVersion: version, objectiveID: first.demand.objectiveID,
                familyID: first.demand.familyID, initialUserBand: initialUserBand, controllerVersion: selectedController, catalogDigest: fingerprint, catalogScope: catalogScope, goalPreferences: frozenGoals)
        }
        let scopes = Set(eligible.map { NFEditorialFamilyScope(objectiveID: $0.demand.objectiveID, familyID: $0.demand.familyID) })
            .sorted { $0.key < $1.key }
        guard scopes.count <= 32 else { return nil }
        if initialUserBand == nil, scopes.count > 1, let anchor = scopes.first {
            return .init(schemaVersion: 2, catalogVersion: version, objectiveID: anchor.objectiveID,
                familyID: anchor.familyID, controllerVersion: usesGoals ? NFEditorialMixedController.goalVersion
                    : hasReviewContracts ? NFEditorialMixedController.reviewVersion : NFEditorialMixedController.version,
                catalogDigest: fingerprint, familyScopes: scopes, goalPreferences: frozenGoals)
        }
        return .init(catalogVersion: version, objectiveID: first.demand.objectiveID,
            familyID: first.demand.familyID, initialUserBand: initialUserBand, controllerVersion: selectedController, catalogDigest: fingerprint, goalPreferences: frozenGoals)
    }
}

struct NFEditorialAdmissionEntry: Codable, Equatable, Sendable {
    let id: String
    let bankQuestionID: String
    let exerciseDigest: String
    let scorerVersion: Int
    let lab: TrainingLab
    let contentLocale: String
    let demand: NFEditorialDemandRecord
    var isSupported: Bool {
        !id.isEmpty && !bankQuestionID.isEmpty && !contentLocale.isEmpty
            && exerciseDigest.count == 64 && exerciseDigest.allSatisfy(\.isHexDigit)
            && scorerVersion == NFExerciseScoringEngine.scoringVersion
            && demand.hasRequiredIdentity && demand.independentEligible
            && demand.expectedDurationRange?.isValid == true
            && demand.assistancePolicyID == NFEditorialNativeProtocol.toolConditionID
    }
}

struct NFEditorialSessionPin: Codable, Equatable, Sendable {
    var schemaVersion = 1
    let catalogVersion: String
    let objectiveID: String
    let familyID: String
    var initialUserBand: NFEditorialBand? = nil
    var controllerVersion = NFEditorialLiveController.version
    var catalogDigest: String = ""
    var familyScopes: [NFEditorialFamilyScope]? = nil
    var catalogScope: NFEditorialCatalogScope? = nil
    var reviewIntent: NFEditorialReviewIntent? = nil
    var goalPreferences: NFEditorialGoalPreferences? = nil
    var isMixed: Bool { schemaVersion == 2 && familyScopes != nil }
    var scopes: [NFEditorialFamilyScope] { familyScopes ?? [.init(objectiveID: objectiveID, familyID: familyID)] }
    func contains(objectiveID: String, familyID: String) -> Bool {
        scopes.contains(.init(objectiveID: objectiveID, familyID: familyID))
    }
    func singleFamily(_ scope: NFEditorialFamilyScope) -> Self {
        .init(catalogVersion: catalogVersion, objectiveID: scope.objectiveID, familyID: scope.familyID,
            initialUserBand: initialUserBand, controllerVersion: familyControllerVersion, catalogDigest: catalogDigest, reviewIntent: reviewIntent, goalPreferences: goalPreferences)
    }
    var familyControllerVersion: String {
        guard isMixed else { return controllerVersion }
        switch controllerVersion {
        case NFEditorialMixedController.legacyVersion: return NFEditorialLiveController.legacyVersion
        case NFEditorialMixedController.demonstratedVersion: return NFEditorialLiveController.demonstratedVersion
        case NFEditorialMixedController.version: return NFEditorialLiveController.version
        case NFEditorialMixedController.reviewVersion: return NFEditorialLiveController.reviewVersion
        case NFEditorialMixedController.goalVersion: return NFEditorialLiveController.goalVersion
        default: return controllerVersion
        }
    }
    var usesDemonstratedInitialTarget: Bool {
        [NFEditorialLiveController.demonstratedVersion, NFEditorialLiveController.version, NFEditorialLiveController.reviewVersion, NFEditorialLiveController.goalVersion].contains(familyControllerVersion)
    }
    var usesObservedCriterionRanking: Bool { [NFEditorialLiveController.version, NFEditorialLiveController.reviewVersion, NFEditorialLiveController.goalVersion].contains(familyControllerVersion) }
    var usesDeclaredReviewSlots: Bool { [NFEditorialLiveController.reviewVersion, NFEditorialLiveController.goalVersion].contains(familyControllerVersion) }
    var usesGoalRanking: Bool { familyControllerVersion == NFEditorialLiveController.goalVersion }
    var isSupported: Bool {
        guard !catalogVersion.isEmpty && !objectiveID.isEmpty && !familyID.isEmpty,
              catalogDigest.count == 64 && catalogDigest.allSatisfy(\.isHexDigit),
              reviewIntent == nil || (usesDeclaredReviewSlots && !isMixed && reviewIntent?.isSupported == true),
              usesGoalRanking ? goalPreferences?.isSupported == true : goalPreferences == nil else { return false }
        if schemaVersion == 1 { return NFEditorialLiveController.supportedVersions.contains(controllerVersion) && familyScopes == nil && catalogScope == nil }
        if schemaVersion == 3 {
            return NFEditorialLiveController.supportedVersions.contains(controllerVersion) && familyScopes == nil
                && catalogScope?.isSupported == true
        }
        return schemaVersion == 2 && catalogScope == nil && NFEditorialMixedController.supportedVersions.contains(controllerVersion)
            && initialUserBand == nil && (2...32).contains(scopes.count)
            && scopes.allSatisfy(\.isSupported) && Set(scopes).count == scopes.count
            && scopes.map(\.key) == scopes.map(\.key).sorted()
            && scopes.first == NFEditorialFamilyScope(objectiveID: objectiveID, familyID: familyID)
    }
}

/// Only the in-app controls are observed. This does not assert that external
/// tools were absent, nor establish latency, device or clean-speed conditions.
enum NFEditorialNativeProtocol {
    static let version = "NativeOrdinaryCommitProtocolV1"
    static let toolConditionID = "in-app-scratchpad-and-optional-help.v1"
    static func supports(_ exercise: NFExercise) -> Bool {
        guard !exercise.assessmentProtected, exercise.evidenceClass == .practice else { return false }
        switch exercise.interaction {
        case .numeric, .singleChoice: return true
        // This complete, versioned ordinary contract exposes only exact x/y
        // entry before lock. Other logic-state workflows keep their own gate.
        case .logicState:
            if exercise.contractMetadata?.coordinateReasoning != nil { return NFCoordinateReasoningContract.make(exercise:exercise) != nil }
            return NFCoordinateTransformContract.make(exercise: exercise) != nil
        case .multipleChoice:
            if exercise.contractMetadata?.spatialAssembly != nil{return NFSpatialAssemblyContract.make(exercise:exercise) != nil}
            return exercise.contractMetadata?.coordinateReasoning != nil && NFCoordinateReasoningContract.make(exercise:exercise) != nil
        default: return false
        }
    }
}

struct NFEditorialRuntimeWitness: Codable, Equatable, Sendable {
    let version: String
    let decisionID: String
    let ownerDeviceID: UUID
    let admission: NFEditorialAdmissionEntry
    let catalogVersion: String
    let catalogDigest: String
    let presentedSlotID: String
    let responseLockedBeforeFeedback: Bool
    let inAppAssistanceKnown: Bool
    let previouslyRevealedSemantic: Bool
    var reviewAssignment: NFEditorialReviewAssignment? = nil
    var isSupported: Bool {
        version == NFEditorialNativeProtocol.version && admission.isSupported
            && !decisionID.isEmpty && !presentedSlotID.isEmpty && !catalogVersion.isEmpty
            && catalogDigest.count == 64 && catalogDigest.allSatisfy(\.isHexDigit)
            && responseLockedBeforeFeedback && inAppAssistanceKnown
            && reviewAssignment?.isSupported != false
            && (reviewAssignment.map { $0.contract == admission.demand.reviewContract && $0.exerciseDigest == admission.exerciseDigest } ?? true)
    }
}

struct NFEditorialSupportPresentation: Codable, Equatable, Sendable {
    let slotID: String
    let usedSupport: Bool
}

struct NFEditorialControllerDecision: Codable, Equatable, Sendable {
    var schemaVersion = 1
    let controllerVersion: String
    let admission: NFEditorialAdmissionEntry
    let evidenceDigest: String
    let decisionDay: NFEditorialCapturedDay
    let observationDigests: [String: String]
    let validity: NFEditorialValidityProjection
    let evidence: NFEditorialEvidenceState
    let initialReason: NFEditorialSelectionReason
    var initialTargetDecision: NFEditorialInitialTargetDecision? = nil
    var criterionSelection: NFEditorialCriterionSelection? = nil
    var reviewAssignment: NFEditorialReviewAssignment? = nil
    var goalSelection: NFEditorialGoalSelection? = nil
    let controlBefore: NFEditorialPracticeControl
    let supportPresentation: NFEditorialSupportPresentation?
    var overrideCommand: NFEditorialOverrideCommand? = nil
    let controlAfter: NFEditorialPracticeControl
    let selection: NFEditorialSelectionReceipt
    var isSupported: Bool {
        ((schemaVersion == 1 && overrideCommand == nil)
                || (schemaVersion == 2 && overrideCommand?.isSupported == true))
            && NFEditorialLiveController.supportedVersions.contains(controllerVersion)
            && initialTargetIsConsistent && criterionSelectionIsConsistent && reviewAssignmentIsConsistent && goalSelectionIsConsistent
            && decisionDay.isSupported && admission.isSupported
            && evidence.policyVersion == EditorialBandEvidenceV1.policyVersion
            && evidenceDigest.count == 64 && evidenceDigest.allSatisfy(\.isHexDigit)
            && selection.policyVersion == EditorialBandEvidenceV1.policyVersion
            && selection.candidateID == admission.bankQuestionID
            && selection.deliveredBand == admission.demand.editorialBand
            && selection.semanticFingerprint == admission.demand.semanticFingerprint
            && controlAfter.selectedExercisePath.last == selection
            && overrideIsConsistent
            && controlBefore.decisionOrdinal >= 0 && controlBefore.decisionOrdinal < Int.max - 1
            && controlAfter.decisionOrdinal == controlBefore.decisionOrdinal + 1
            && (0...1).contains(controlAfter.upwardChangesThisSession)
            && (0...2).contains(controlAfter.totalAutomaticChangesThisSession)
    }
    private var criterionSelectionIsConsistent: Bool {
        guard [NFEditorialLiveController.version, NFEditorialLiveController.reviewVersion, NFEditorialLiveController.goalVersion].contains(controllerVersion) else { return criterionSelection == nil }
        guard let selected = criterionSelection, selected.isSupported else { return false }
        return selected.candidateID == admission.bankQuestionID && selected.exerciseDigest == admission.exerciseDigest
            && selected.structureID == admission.demand.structureID
            && selected.group.objectiveID == admission.demand.objectiveID && selected.group.familyID == admission.demand.familyID
            && selected.group.band == admission.demand.editorialBand
            && selected.supportingObservationIDs.isSubset(of: Set(evidence.independentObservationIDs))
            && selected.supportingObservationIDs.isSubset(of: Set(observationDigests.keys))
    }
    private var reviewAssignmentIsConsistent: Bool {
        guard [NFEditorialLiveController.reviewVersion, NFEditorialLiveController.goalVersion].contains(controllerVersion) else { return reviewAssignment == nil }
        guard let contract = admission.demand.reviewContract else { return reviewAssignment == nil }
        guard let assigned = reviewAssignment, assigned.isSupported,
              assigned.contract == contract, assigned.candidateID == admission.bankQuestionID,
              assigned.exerciseDigest == admission.exerciseDigest,
              assigned.semanticFingerprint == admission.demand.semanticFingerprint,
              assigned.group == criterionSelection?.group, assigned.decisionDayOrdinal == decisionDay.ordinal else { return false }
        if assigned.role == .probe { return true }
        guard let origin = assigned.originObservationID, let entry = assigned.entry,
              observationDigests[origin] == assigned.originObservationDigest,
              evidence.independentObservationIDs.contains(origin),
              validity.correctedScoreByObservationID[origin] == nil,
              let originalEntry = evidence.retention.first(where: { $0.id == entry.id }) else { return false }
        if assigned.role == .repair {
            return NFEditorialRetentionPolicy.openingExplanation(originalEntry, hasFreshSibling: true) == entry
        }
        return originalEntry == entry
    }
    private var goalSelectionIsConsistent: Bool {
        guard controllerVersion == NFEditorialLiveController.goalVersion else { return goalSelection == nil }
        guard let goalSelection, goalSelection.isSupported else { return false }
        return goalSelection.candidateID == admission.bankQuestionID
            && goalSelection.exerciseDigest == admission.exerciseDigest
            && goalSelection.objectiveID == admission.demand.objectiveID
            && goalSelection.alignment == admission.demand.goalAlignment
    }
    private var initialTargetIsConsistent: Bool {
        if controllerVersion == NFEditorialLiveController.legacyVersion { return initialTargetDecision == nil }
        guard let initial = initialTargetDecision, initial.isSupported else { return false }
        return initial.band == controlBefore.initialTargetBand && initial.band == controlAfter.initialTargetBand
            && initial.reason == initialReason
            && (initial.evidenceGroup.map { $0.objectiveID == controlBefore.objectiveID && $0.familyID == controlBefore.familyID } ?? true)
    }
    private var overrideIsConsistent: Bool {
        guard let command = overrideCommand else { return true }
        return command.controlDigest == (try? NFEditorialCanonicalData.digest(controlBefore))
            && command.sessionID.uuidString == controlBefore.sessionID
            && command.objectiveID == controlBefore.objectiveID && command.familyID == controlBefore.familyID
            && selection.requestedBand == command.targetBand && selection.deliveredBand == command.targetBand
            && controlAfter.currentTargetBand == command.targetBand
            && controlAfter.challengeMode == (command.action.isFixed ? .fixedBand(command.targetBand) : .adaptive)
            && controlAfter.upwardChangesThisSession == controlBefore.upwardChangesThisSession
            && controlAfter.totalAutomaticChangesThisSession == controlBefore.totalAutomaticChangesThisSession
            && (command.targetBand == controlBefore.currentTargetBand || controlAfter.currentBandDecisionResponseIDs.isEmpty)
    }
}

/// Set-valued arrays are canonicalized explicitly; chronology, response fields,
/// structures and actual exercise arrays retain their authored order.
enum NFEditorialCanonicalData {
    static func encode<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let object = try JSONSerialization.jsonObject(with: encoder.encode(value), options: [.fragmentsAllowed])
        func normalized(_ value: Any, key: String? = nil) -> Any {
            if let map = value as? [String: Any] {
                return Dictionary(uniqueKeysWithValues: map.map { ($0.key, normalized($0.value, key: $0.key)) })
            }
            if let array = value as? [Any] {
                let setKeys: Set<String> = ["accommodationFacts", "requiredDemonstrationFormatIDs", "missingCriterionIDs"]
                if let key, setKeys.contains(key), let strings = array as? [String] { return strings.sorted() }
                return array.map { normalized($0) }
            }
            return value
        }
        return try JSONSerialization.data(withJSONObject: normalized(object), options: [.sortedKeys, .fragmentsAllowed])
    }
    static func digest<T: Encodable>(_ value: T) throws -> String { NFReservationSnapshot.digest(try encode(value)) }
}

/// Compatibility comes from exact materialization under the admitted request,
/// including used inventory. A temporary shortage cannot erase demonstrated
/// demand or quietly substitute an easier starting target.
struct NFEditorialInitialTargetContract: Codable, Equatable, Sendable {
    let bankQuestionID: String
    let group: NFEditorialEvidenceGroup
    static func make(exercise: NFExercise, admission: NFEditorialAdmissionEntry) -> Self {
        let item = admission.demand
        return .init(bankQuestionID: admission.bankQuestionID, group: .init(lane: .practice,
            objectiveID: item.objectiveID, familyID: item.familyID, band: item.editorialBand,
            bandContractVersion: item.bandContractVersion,
            scoringComparabilityID: item.scoringComparabilityID ?? item.answerContractVersion,
            stimulusComparabilityID: item.stimulusComparabilityID ?? NFRetentionRepresentation.identifier(for: exercise),
            toolConditionID: item.assistancePolicyID,
            localeComparabilityID: item.localeComparabilityID ?? exercise.localeIdentifier,
            pacingConditionID: NFEditorialTimingMode.untimed.rawValue, protocolScope: "practice.v1"))
    }
    func matches(_ other: NFEditorialEvidenceGroup) -> Bool {
        // Pacing stays a separate recorded condition. This compares demand;
        // it never combines observations across pacing groups or unlocks speed.
        let unpaced = NFEditorialEvidenceGroup(lane: other.lane, objectiveID: other.objectiveID, familyID: other.familyID,
            band: other.band, bandContractVersion: other.bandContractVersion,
            scoringComparabilityID: other.scoringComparabilityID, stimulusComparabilityID: other.stimulusComparabilityID,
            toolConditionID: other.toolConditionID, localeComparabilityID: other.localeComparabilityID,
            pacingConditionID: NFEditorialTimingMode.untimed.rawValue, protocolScope: other.protocolScope)
        return group == unpaced
    }
}

struct NFEditorialInitialTargetDecision: Codable, Equatable, Sendable {
    enum Basis: String, Codable, Sendable { case coldStart, userPreference, recentSuccess, demonstratedPractice }
    var schemaVersion = 1
    let band: NFEditorialBand
    let reason: NFEditorialSelectionReason
    let basis: Basis
    let evidenceGroup: NFEditorialEvidenceGroup?
    let supportingObservationIDs: [String]
    let lastRelevantPracticeDay: Int?
    let lastDemonstratedAt: Date?
    let compatibleContractsDigest: String
    var isSupported: Bool {
        guard schemaVersion == 1, compatibleContractsDigest.count == 64,
              compatibleContractsDigest.allSatisfy(\.isHexDigit),
              Set(supportingObservationIDs).count == supportingObservationIDs.count,
              lastDemonstratedAt.map({ $0.timeIntervalSince1970.isFinite }) ?? true else { return false }
        switch basis {
        case .coldStart:
            return band == .b1 && reason == .coldStartDefault && evidenceGroup == nil
                && supportingObservationIDs.isEmpty && lastDemonstratedAt == nil
        case .userPreference:
            return reason == .userRequested && evidenceGroup == nil && supportingObservationIDs.isEmpty && lastDemonstratedAt == nil
        case .recentSuccess, .demonstratedPractice:
            return (reason == .recentPracticeTarget || reason == .refreshProbe)
                && evidenceGroup?.lane == .practice && evidenceGroup?.band == band
                && lastRelevantPracticeDay != nil
                && (basis == .recentSuccess ? supportingObservationIDs.count == 1 && lastDemonstratedAt == nil
                    : supportingObservationIDs.count == 8 && lastDemonstratedAt != nil)
        }
    }
}

enum NFEditorialInitialTargetPolicy {
    static func select(pin: NFEditorialSessionPin, input: NFEditorialLiveController.Input,
                       contracts: [NFEditorialInitialTargetContract]) throws -> NFEditorialInitialTargetDecision {
        let relevant = contracts.filter { $0.group.objectiveID == pin.objectiveID && $0.group.familyID == pin.familyID }
            .sorted { $0.bankQuestionID == $1.bankQuestionID ? $0.group.stableID < $1.group.stableID : $0.bankQuestionID < $1.bankQuestionID }
        let digest = try NFEditorialCanonicalData.digest(relevant)
        if let band = pin.initialUserBand {
            return .init(band: band, reason: .userRequested, basis: .userPreference,
                evidenceGroup: nil, supportingObservationIDs: [], lastRelevantPracticeDay: nil,
                lastDemonstratedAt: nil, compatibleContractsDigest: digest)
        }
        let observations = input.observations.filter { observation in
            guard observation.lane == .practice, let group = EditorialBandEvidenceV1.group(for: observation) else { return false }
            return relevant.contains { $0.matches(group) }
        }
        // Reduce every compatible observation before picking a band. A family
        // label does not let incompatible contracts or locales share coverage.
        let evidence = EditorialBandEvidenceV1.reduce(observations,
            decisionDayOrdinal: input.day.ordinal, validity: input.validity)
        let independent = Set(evidence.independentObservationIDs)
        let valid = observations.filter { independent.contains($0.id) }
        let lastDay = valid.map(\.canonicalDayOrdinal).max()
        func recency(for group: NFEditorialEvidenceGroup) -> (day: Int?, reason: NFEditorialSelectionReason) {
            let day = valid.filter { EditorialBandEvidenceV1.group(for: $0) == group }.map(\.canonicalDayOrdinal).max()
            return (day, day.map { input.day.ordinal - $0 >= 30 } == true ? .refreshProbe : .recentPracticeTarget)
        }
        let supported = evidence.summaries.filter {
            $0.lastDemonstratedAt != nil && $0.coverage != .notCurrentlySupported && $0.coverage != .evidenceAffected
        }.sorted { a, b in
            if a.group.band != b.group.band { return a.group.band > b.group.band }
            if a.lastDemonstratedAt != b.lastDemonstratedAt { return (a.lastDemonstratedAt ?? .distantPast) > (b.lastDemonstratedAt ?? .distantPast) }
            return a.group.stableID < b.group.stableID
        }
        for summary in supported {
            guard let witness = EditorialBandEvidenceV1.lastDemonstrationWitness(group: summary.group,
                observations: observations, evidence: evidence, validity: input.validity),
                  witness.occurredAt == summary.lastDemonstratedAt else { continue }
            let recency = recency(for: summary.group)
            return .init(band: summary.group.band, reason: recency.reason, basis: .demonstratedPractice,
                evidenceGroup: summary.group, supportingObservationIDs: witness.qualifyingObservationIDs,
                lastRelevantPracticeDay: recency.day, lastDemonstratedAt: witness.occurredAt, compatibleContractsDigest: digest)
        }
        let successful = valid.filter { input.validity.correctedScoreByObservationID[$0.id]?.isFullCredit ?? $0.isFullCredit }
            .sorted(by: EditorialBandEvidenceV1.stableOrder).last
        if let successful, let group = EditorialBandEvidenceV1.group(for: successful) {
            let recency = recency(for: group)
            return .init(band: group.band, reason: recency.reason, basis: .recentSuccess, evidenceGroup: group,
                supportingObservationIDs: [successful.id], lastRelevantPracticeDay: recency.day,
                lastDemonstratedAt: nil, compatibleContractsDigest: digest)
        }
        return .init(band: .b1, reason: .coldStartDefault, basis: .coldStart, evidenceGroup: nil,
            supportingObservationIDs: [], lastRelevantPracticeDay: lastDay, lastDemonstratedAt: nil,
            compatibleContractsDigest: digest)
    }
}

enum NFEditorialLiveController {
    static let legacyVersion = "EditorialLiveControllerV1"
    static let demonstratedVersion = "EditorialLiveControllerV2"
    static let version = "EditorialLiveControllerV3"
    static let reviewVersion = "EditorialLiveControllerV4"
    static let goalVersion = "EditorialLiveControllerV5"
    static let supportedVersions: Set<String> = [legacyVersion, demonstratedVersion, version, reviewVersion, goalVersion]
    struct FrozenInputIdentity: Codable, Equatable, Sendable {
        let observationDigests: [String: String]
        let validity: NFEditorialValidityProjection
        let day: NFEditorialCapturedDay
    }
    struct Input: Codable, Equatable, Sendable {
        let observations: [NFEditorialObservation]
        let validity: NFEditorialValidityProjection
        let day: NFEditorialCapturedDay
        func frozenIdentity() throws -> FrozenInputIdentity {
            var digests: [String: String] = [:]
            for observation in observations {
                let digest = try NFEditorialCanonicalData.digest(observation)
                if let prior = digests[observation.id], prior != digest {
                    throw NFLocalSessionRepository.RepositoryError.conflictingAttempt
                }
                digests[observation.id] = digest
            }
            return .init(observationDigests: digests, validity: validity, day: day)
        }
    }

    static func decide(pin: NFEditorialSessionPin, sessionID: String,
                       previous: NFEditorialControllerDecision?, committedID: String?,
                       input: Input, candidates: [NFEditorialSelectionCandidate],
                       supportPresentation: NFEditorialSupportPresentation? = nil,
                       overrideCommand: NFEditorialOverrideCommand? = nil,
                       admissions: [String: NFEditorialAdmissionEntry], context: NFEditorialSelectionContext)
        throws -> NFEditorialControllerDecision? {
        guard pin.isSupported, input.day.isSupported,
              previous?.isSupported != false, previous == nil || previous?.controllerVersion == pin.familyControllerVersion
        else { throw NFLocalSessionRepository.RepositoryError.unsupportedVersion }
        if pin.usesGoalRanking {
            guard let preferences = pin.goalPreferences,
                  preferences.profileID.uuidString == context.profilePseudonymousID,
                  previous == nil || previous?.goalSelection?.preferences == preferences else {
                throw NFLocalSessionRepository.RepositoryError.corruptSnapshot
            }
            for candidate in candidates {
                guard let admission = admissions[candidate.id],
                      let expected = NFEditorialGoalRankingPolicy.selection(admission: admission, preferences: preferences),
                      context.goalSelections?[candidate.id] == expected,
                      candidate.goalRelevance == expected.preference else {
                    throw NFLocalSessionRepository.RepositoryError.corruptSnapshot
                }
            }
        }
        let evidence = EditorialBandEvidenceV1.reduce(input.observations,
            decisionDayOrdinal: input.day.ordinal, validity: input.validity)
        let effectiveIDs = Set(evidence.independentObservationIDs)
        let compatible = input.observations.filter { effectiveIDs.contains($0.id)
            && $0.lane == .practice && $0.item?.objectiveID == pin.objectiveID && $0.item?.familyID == pin.familyID }
        let recent = compatible.filter { (input.validity.correctedScoreByObservationID[$0.id]?.isFullCredit) ?? $0.isFullCredit }.sorted(by: EditorialBandEvidenceV1.stableOrder).last
        let initialTarget: NFEditorialInitialTargetDecision?
        if pin.usesDemonstratedInitialTarget {
            guard let contracts = context.initialTargetContracts else { throw NFLocalSessionRepository.RepositoryError.unsupportedVersion }
            if let previous { initialTarget = previous.initialTargetDecision }
            else { initialTarget = try NFEditorialInitialTargetPolicy.select(pin: pin, input: input, contracts: contracts) }
        } else { initialTarget = nil }
        let legacyInitial = NFEditorialPracticePolicy.initialControl(sessionID: sessionID, objectiveID: pin.objectiveID,
            familyID: pin.familyID, explicitBand: pin.initialUserBand, recentTargetBand: recent?.item?.editorialBand,
            daysSincePractice: recent.map { input.day.ordinal - $0.canonicalDayOrdinal })
        let initial = initialTarget.map { target in
            (NFEditorialPracticeControl(sessionID: sessionID, objectiveID: pin.objectiveID, familyID: pin.familyID,
                initialTargetBand: target.band, currentTargetBand: target.band), target.reason)
        } ?? legacyInitial
        let before = previous?.controlAfter ?? initial.0
        guard before.decisionOrdinal >= 0, before.decisionOrdinal < Int.max - 1,
              before.sessionID == sessionID, before.objectiveID == pin.objectiveID,
              before.familyID == pin.familyID else { throw NFLocalSessionRepository.RepositoryError.corruptSnapshot }
        var forDecision = before
        if let supportPresentation,
           !(forDecision.processedPresentationIDs ?? []).contains(supportPresentation.slotID) {
            forDecision.processedPresentationIDs = (forDecision.processedPresentationIDs ?? []) + [supportPresentation.slotID]
            forDecision.presentedSupportEvents = Array((forDecision.presentedSupportEvents + [supportPresentation.usedSupport]).suffix(3))
        }
        let committed = committedID.flatMap { id in input.observations.first { $0.id == id } }
        if let overrideCommand {
            guard overrideCommand.isSupported, overrideCommand.sessionID.uuidString == sessionID,
                  overrideCommand.objectiveID == pin.objectiveID, overrideCommand.familyID == pin.familyID,
                  overrideCommand.controlDigest == (try NFEditorialCanonicalData.digest(before)),
                  overrideCommand.targetBand == (try overrideCommand.action.target(deliveredBand: previous?.selection.deliveredBand ?? before.currentTargetBand,
                    targetBand: before.currentTargetBand)) else { throw NFLocalSessionRepository.RepositoryError.staleRevision }
            // The outgoing item's answer belongs to its original band. A user
            // request cannot replay that answer into a new band's staircase.
            if let committed, !(forDecision.processedObservationIDs ?? []).contains(committed.id) {
                forDecision.processedObservationIDs = (forDecision.processedObservationIDs ?? []) + [committed.id]
                if overrideCommand.targetBand == before.currentTargetBand, effectiveIDs.contains(committed.id),
                   committed.item?.objectiveID == before.objectiveID, committed.item?.familyID == before.familyID,
                   committed.item?.editorialBand == before.currentTargetBand,
                   !forDecision.currentBandDecisionResponseIDs.contains(committed.id) {
                    forDecision.currentBandDecisionResponseIDs.append(committed.id)
                }
            }
            forDecision.override(to: overrideCommand.targetBand, keepLevel: overrideCommand.action.isFixed)
        }
        let initialCandidates: [NFEditorialSelectionCandidate]
        if previous == nil, let group = initialTarget?.evidenceGroup {
            let compatibleIDs = Set((context.initialTargetContracts ?? []).filter { $0.matches(group) }.map(\.bankQuestionID))
            initialCandidates = candidates.filter { compatibleIDs.contains($0.id) }
        } else { initialCandidates = candidates }
        let result = NFEditorialPracticePolicy.selectNext(control: forDecision, observation: overrideCommand == nil ? committed : nil,
            history: input.observations, evidence: evidence, candidates: initialCandidates,
            context: context, validity: input.validity, recordsSupportFromObservation: false,
            selectionReasonOverride: overrideCommand == nil ? nil : .userRequested)
        guard let candidate = result.candidate, let admission = admissions[candidate.id],
              let selection = result.control.selectedExercisePath.last else { return nil }
        let criterion = pin.usesObservedCriterionRanking ? context.criterionSelections?[candidate.id] : nil
        guard !pin.usesObservedCriterionRanking || criterion?.isSupported == true else {
            throw NFLocalSessionRepository.RepositoryError.corruptSnapshot
        }
        let identity = try input.frozenIdentity()
        return .init(schemaVersion: overrideCommand == nil ? 1 : 2, controllerVersion: pin.familyControllerVersion, admission: admission,
            evidenceDigest: try NFEditorialCanonicalData.digest(identity), decisionDay: input.day,
            observationDigests: identity.observationDigests, validity: input.validity, evidence: evidence,
            initialReason: previous?.initialReason ?? initial.1, initialTargetDecision: initialTarget, criterionSelection: criterion,
            reviewAssignment: pin.usesDeclaredReviewSlots ? context.reviewAssignments?[candidate.id] : nil,
            goalSelection: pin.usesGoalRanking ? context.goalSelections?[candidate.id] : nil, controlBefore: before,
            supportPresentation: supportPresentation, overrideCommand: overrideCommand, controlAfter: result.control, selection: selection)
    }
}


/// User commands are preferences, never observations. The known current slot
/// and control digest bind them to one objective/family and one safe boundary.
enum NFEditorialOverrideAction: Codable, Equatable, Sendable {
    case easier, harder, keepThisLevel, fixedBand(NFEditorialBand), adaptive
    var isFixed: Bool {
        switch self { case .keepThisLevel, .fixedBand: true; default: false }
    }
    func target(deliveredBand: NFEditorialBand, targetBand: NFEditorialBand) throws -> NFEditorialBand {
        switch self {
        case .easier:
            guard let lower = targetBand.lower else { throw NFEditorialOverrideError.bandBoundary }
            return lower
        case .harder:
            guard let higher = targetBand.higher else { throw NFEditorialOverrideError.bandBoundary }
            return higher
        case .keepThisLevel: return deliveredBand
        case let .fixedBand(band): return band
        case .adaptive: return targetBand
        }
    }
}
enum NFEditorialOverrideBoundary: String, Codable, Sendable { case nextQuestion, replaceCurrent }
enum NFEditorialOverrideError: Error, LocalizedError {
    case bandBoundary, unavailable(NFEditorialBand, availableBands: [NFEditorialBand]), unsupported, noRemainingQuestion, staleOwner
    var availableBands: [NFEditorialBand] {
        if case let .unavailable(_, bands) = self { return bands }
        return []
    }
    var errorDescription: String? {
        switch self {
        case .staleOwner: "This window no longer owns this activity. Reopen the saved activity to choose its next challenge."
        case .bandBoundary: "There is no adjacent band in that direction. Choose an available band explicitly."
        case .unavailable: "No unseen reviewed question at the requested band meets this activity's requirements. Choose another available band or keep the current question."
        case .unsupported: "Reviewed challenge controls are not available for this saved activity. Its questions and progress are retained."
        case .noRemainingQuestion: "This is the last question. Choose a new activity to change the challenge."
        }
    }
}
struct NFEditorialOverrideCommand: Codable, Equatable, Sendable {
    var schemaVersion = 1
    var policyVersion = "EditorialUserOverrideV1"
    let id: UUID
    let sessionID: UUID
    let ownerDeviceID: UUID
    let slotID: UUID
    let objectiveID: String
    let familyID: String
    let controlDigest: String
    let action: NFEditorialOverrideAction
    let boundary: NFEditorialOverrideBoundary
    let targetBand: NFEditorialBand
    let predecessorCommandID: UUID?
    let createdAt: Date
    var isSupported: Bool {
        schemaVersion == 1 && policyVersion == "EditorialUserOverrideV1"
            && !objectiveID.isEmpty && !familyID.isEmpty
            && controlDigest.count == 64 && controlDigest.allSatisfy(\.isHexDigit)
            && createdAt.timeIntervalSinceReferenceDate.isFinite
    }
}

struct NFEditorialChallengePresentation: Equatable, Sendable {
    let deliveredBand: NFEditorialBand
    let targetBand: NFEditorialBand
    let mode: NFEditorialChallengeMode
    let reason: NFEditorialSelectionReason
    let pendingBand: NFEditorialBand?
    let pendingChallengeMode: NFEditorialChallengeMode?
    let userAction: NFEditorialOverrideAction?
    let policyVersion: String
    let decisionID: String
    let objectiveID: String
    let familyID: String
    let shouldOfferSupport: Bool
    let reviewedCatalogBands: [NFEditorialBand]
    let reasoningSteps: Int
    var mixedFamilyTitle: String? = nil
    var mixedFeasibleFamilyCount: Int? = nil
    var varietyUnavailableReasons: [String] = []
    var titleKey: String { "Current question challenge" }
    var explanationKey: String {
        if mixedFamilyTitle != nil && pendingBand != nil { return "Your choice applies to the next question in this family. Other families keep their own challenge." }
        if mixedFamilyTitle != nil && reason == .userFixedBand { return "You chose to keep this challenge in this family. Other families keep their own challenge." }
        if pendingBand != nil { return "Your choice applies to the next question. This question and your recorded level stay unchanged." }
        switch reason {
        case .coldStartDefault: return "Finding a comfortable challenge. This starting question is not a level assessment."
        case .userRequested:
            if userAction == .harder { return "You chose a harder question. Your recorded level has not changed." }
            if userAction == .easier { return "You chose an easier question. Your recorded level has not changed." }
            return "You chose this challenge. Your recorded level has not changed."
        case .userFixedBand: return "You chose to keep this challenge for the rest of this activity."
        case .independentSuccessPattern: return "Your last four independent answers supported trying the next reviewed challenge."
        case .independentDifficultyPattern: return "Let's practice the underlying step before combining it with another."
        case .refreshProbe: return "This question refreshes your previous practice after a break. Your recorded level has not been lowered."
        case .nextBandUnavailable: return "The next reviewed band is not available. This question keeps the current challenge."
        case .foundationSupport: return "Foundation practice and optional help are available. Your recorded level has not been lowered."
        case .protectedCheckSuggestion: return "A recent compatible check suggested this starting challenge."
        case .recentPracticeTarget: return "Continuing the challenge from your recent compatible practice."
        case .continueCurrentChallenge, .noCompatibleContent: return "This question continues your selected challenge."
        }
    }
    static func bandNameKey(_ band: NFEditorialBand) -> String {
        switch band { case .b1: "Foundation"; case .b2: "Developing"; case .b3: "Challenging"; case .b4: "Advanced" }
    }
}


// MARK: - Mixed ordinary practice coordination

struct NFEditorialFamilyScope: Codable, Equatable, Hashable, Sendable {
    let objectiveID: String
    let familyID: String
    var key: String { NFReservationSnapshot.digest(Data((objectiveID + "\u{0}" + familyID).utf8)) }
    var isSupported: Bool { !objectiveID.isEmpty && !familyID.isEmpty && !objectiveID.contains("\u{0}") && !familyID.contains("\u{0}") }
}

/// References are local to this activity. A deferred response is processed only
/// when its own family is selected again; it never updates another objective.
struct NFEditorialMixedPendingEvent: Codable, Equatable, Sendable {
    let scope: NFEditorialFamilyScope
    let decisionID: String
    let slotID: String
    let committedAttemptID: String?
    let support: NFEditorialSupportPresentation?
}
struct NFEditorialMixedState: Codable, Equatable, Sendable {
    var lastDecisionByFamily: [String: String] = [:]
    var pendingByFamily: [String: NFEditorialMixedPendingEvent] = [:]
    var recentSupportPresentations: [NFEditorialSupportPresentation] = []
}

/// Frozen anonymous counts do not create live cross-session references. Deleting
/// an earlier activity cannot rewrite why an already accepted question was chosen.
struct NFEditorialMixedHistory: Codable, Equatable, Sendable {
    let exposureDigest: String
    let recentCount: Int
    let recentSemanticCount: Int
    let recentFamilyCounts: [String: Int]
    let recentStructureCounts: [String: Int]
    let recentRepresentationCounts: [String: Int]
    let sessionCount: Int
    let sessionSemanticCount: Int
    let sessionFamilyCounts: [String: Int]
    let sessionStructureCounts: [String: Int]
    let sessionRepresentationCounts: [String: Int]
    let previousFamilyKey: String?
    let previousFamilyRunCount: Int
    var isSupported: Bool {
        exposureDigest.count == 64 && exposureDigest.allSatisfy(\.isHexDigit)
            && (0...100).contains(recentCount) && (0...recentCount).contains(recentSemanticCount)
            && (0...4_096).contains(sessionCount) && (0...sessionCount).contains(sessionSemanticCount)
            && recentFamilyCounts.values.allSatisfy({ (1...100).contains($0) })
            && recentFamilyCounts.values.reduce(0, +) == recentCount
            && sessionFamilyCounts.values.allSatisfy({ (1...4_096).contains($0) })
            && sessionFamilyCounts.values.reduce(0, +) == sessionCount
            && [recentStructureCounts, recentRepresentationCounts].allSatisfy({ $0.values.allSatisfy { (1...100).contains($0) } })
            && [sessionStructureCounts, sessionRepresentationCounts].allSatisfy({ $0.values.allSatisfy { (1...4_096).contains($0) } })
            && (0...sessionCount).contains(previousFamilyRunCount)
            && (previousFamilyKey == nil) == (previousFamilyRunCount == 0)
    }
}
struct NFEditorialMixedRank: Codable, Equatable, Sendable {
    let familyKey: String
    let candidateID: String
    let values: [Int]
    let tieKey: UInt64
}
struct NFEditorialMixedDecision: Codable, Equatable, Sendable {
    var schemaVersion = 1
    let policyVersion: String
    let globalDecisionOrdinal: UInt64
    let selectedScope: NFEditorialFamilyScope
    let stateBefore: NFEditorialMixedState
    let outgoingEvent: NFEditorialMixedPendingEvent?
    let stateAfter: NFEditorialMixedState
    let history: NFEditorialMixedHistory
    let rankedFamilies: [NFEditorialMixedRank]
    let feasibleFamilyKeys: [String]
    let unmetVarietyPreferences: [String]
    var isSupported: Bool {
        schemaVersion == 1 && NFEditorialMixedController.supportedVersions.contains(policyVersion) && selectedScope.isSupported
            && history.isSupported && !rankedFamilies.isEmpty && rankedFamilies.count <= 32
            && Set(rankedFamilies.map(\.familyKey)).count == rankedFamilies.count
            && Set(feasibleFamilyKeys).count == feasibleFamilyKeys.count && feasibleFamilyKeys.count <= 32
            && feasibleFamilyKeys == feasibleFamilyKeys.sorted()
            && rankedFamilies.first?.familyKey == selectedScope.key
            && zip(rankedFamilies, rankedFamilies.dropFirst()).allSatisfy({ pair in
                let a = pair.0, b = pair.1
                for (x, y) in zip(a.values, b.values) where x != y { return x < y }
                return a.tieKey == b.tieKey ? a.candidateID < b.candidateID : a.tieKey < b.tieKey
            })
            && rankedFamilies.allSatisfy({ $0.values.count == 7 && feasibleFamilyKeys.contains($0.familyKey) })
            && [stateBefore, stateAfter].allSatisfy { state in
                state.lastDecisionByFamily.count <= 32 && state.pendingByFamily.count <= 32
                    && state.recentSupportPresentations.count <= 3
                    && Set(state.recentSupportPresentations.map(\.slotID)).count == state.recentSupportPresentations.count
                    && state.pendingByFamily.allSatisfy { $0.key == $0.value.scope.key && $0.value.scope.isSupported }
            }
    }
}

enum NFEditorialMixedController {
    static let legacyVersion = "EditorialMixedControllerV1"
    static let demonstratedVersion = "EditorialMixedControllerV2"
    static let version = "EditorialMixedControllerV3"
    static let reviewVersion = "EditorialMixedControllerV4"
    static let goalVersion = "EditorialMixedControllerV5"
    static let supportedVersions: Set<String> = [legacyVersion, demonstratedVersion, version, reviewVersion, goalVersion]
    static func scope(of decision: NFEditorialControllerDecision) -> NFEditorialFamilyScope {
        .init(objectiveID: decision.admission.demand.objectiveID, familyID: decision.admission.demand.familyID)
    }
    static func applying(_ event: NFEditorialMixedPendingEvent?, to before: NFEditorialMixedState) throws -> NFEditorialMixedState {
        var next = before
        if let event {
            guard next.pendingByFamily[event.scope.key] == nil,
                  next.lastDecisionByFamily[event.scope.key] == event.decisionID else {
                throw NFLocalSessionRepository.RepositoryError.corruptSnapshot
            }
            next.pendingByFamily[event.scope.key] = event
            if let support = event.support {
                guard support.slotID == event.slotID else { throw NFLocalSessionRepository.RepositoryError.corruptSnapshot }
                next.recentSupportPresentations = Array((next.recentSupportPresentations + [support]).suffix(3))
            }
        }
        return next
    }
    static func select(decisions: [String: NFEditorialControllerDecision], candidates: [String: NFEditorialSelectionCandidate],
                       feasibleFamilyKeys: [String], pin: NFEditorialSessionPin, sessionID: String,
                       profileID: String, ordinal: UInt64, decisionID: String,
                       before: NFEditorialMixedState, outgoing: NFEditorialMixedPendingEvent?,
                       history: NFEditorialMixedHistory, explicitlySelectedFamily: String?) throws -> NFEditorialMixedDecision? {
        guard pin.isSupported, pin.isMixed, history.isSupported else { throw NFLocalSessionRepository.RepositoryError.unsupportedVersion }
        if pin.usesGoalRanking {
            guard let preferences = pin.goalPreferences, preferences.profileID.uuidString == profileID,
                  decisions.values.allSatisfy({ decision in
                    decision.isSupported && decision.goalSelection?.preferences == preferences
                        && decision.goalSelection?.preference == candidates[decision.selection.candidateID]?.goalRelevance
                  }) else { throw NFLocalSessionRepository.RepositoryError.corruptSnapshot }
        }
        let targetCoverage = min(4, feasibleFamilyKeys.count)
        let visited = Set(history.sessionFamilyCounts.keys)
        let ranked = decisions.compactMap { key, decision -> NFEditorialMixedRank? in
            guard let candidate = candidates[decision.selection.candidateID],
                  explicitlySelectedFamily == nil || explicitlySelectedFamily == key else { return nil }
            let coverageDeficit = visited.count < targetCoverage && !visited.contains(key) ? 1 : 0
            let repeated = history.previousFamilyKey == key && history.previousFamilyRunCount >= 2
            let tie = NFStableDeterminism.hash64([pin.controllerVersion, pin.catalogVersion, profileID, sessionID,
                String(ordinal), candidate.id, "question-selection"].map { "\($0.utf8.count):\($0)" }.joined())
            return .init(familyKey: key, candidateID: candidate.id,
                values: [-max(candidate.requiredCoverageDeficit, coverageDeficit), -candidate.dueRepairPriority,
                    repeated ? 1 : 0, history.recentFamilyCounts[key, default: 0],
                    history.recentStructureCounts[candidate.item.structureID, default: 0],
                    -candidate.goalRelevance, -candidate.observedWeakCriterionMatch], tieKey: tie)
        }.sorted { a, b in
            for (x, y) in zip(a.values, b.values) where x != y { return x < y }
            return a.tieKey == b.tieKey ? a.candidateID < b.candidateID : a.tieKey < b.tieKey
        }
        guard let first = ranked.first, let selected = decisions[first.familyKey] else { return nil }
        var after = try applying(outgoing, to: before)
        after.lastDecisionByFamily[first.familyKey] = decisionID
        after.pendingByFamily.removeValue(forKey: first.familyKey)
        var unmet: [String] = []
        if feasibleFamilyKeys.count < 4 { unmet.append("fewerThanFourCompatibleFamilies") }
        if feasibleFamilyKeys.count < pin.scopes.count { unmet.append("someFamilyChallengeUnavailable") }
        if history.previousFamilyKey == first.familyKey && history.previousFamilyRunCount >= 2 { unmet.append("familyRunAboveTwo") }
        // The window counts displayed slots, including skips, help and Replace.
        // In a partial window a 35% claim is not yet applicable.
        if history.recentCount == 99 && history.recentFamilyCounts[first.familyKey, default: 0] >= 35 { unmet.append("rollingFamilyShareAbove35Percent") }
        if explicitlySelectedFamily != nil && ranked.count < decisions.count { unmet.append("explicitFamilyChoiceLimitsVariety") }
        if visited.count < min(4, pin.scopes.count), visited.contains(first.familyKey),
           feasibleFamilyKeys.allSatisfy({ visited.contains($0) }) { unmet.append("unseenFamilyUnavailable") }
        return .init(policyVersion: pin.controllerVersion, globalDecisionOrdinal: ordinal,
            selectedScope: scope(of: selected), stateBefore: before, outgoingEvent: outgoing,
            stateAfter: after, history: history, rankedFamilies: ranked,
            feasibleFamilyKeys: feasibleFamilyKeys.sorted(), unmetVarietyPreferences: unmet)
    }
}


/// A new exact-bank catalog route. The old mechanic-filtered recipe is never
/// relabeled with this scope; only a newly admitted, explicitly chosen run gets it.
struct NFEditorialCatalogScope: Codable, Equatable, Sendable {
    var schemaVersion = 1
    let catalogVersion: Int
    let activityID: String
    let field: STEMField
    var isSupported: Bool {
        schemaVersion == 1 && catalogVersion == NFDefaultContentCatalog.version
            && NFDefaultContentCatalog.activity(id: activityID) != nil
    }
    func matches(_ exercise: NFExercise) -> Bool {
        guard isSupported, let activity = NFDefaultContentCatalog.activity(id: activityID) else { return false }
        guard exercise.lab == activity.lab, exercise.sourceContext.primaryField == field,
              exercise.templateFamily.hasPrefix("nf.fallback.\(activity.lab.rawValue).") else { return false }
        // Opt-in module recipes can intentionally rename a legacy template.
        // Their complete typed contract, not a substring or a mutable family
        // label alone, determines the corresponding catalog activity.
        if exercise.contractMetadata?.spatialAssembly != nil {return NFSpatialAssemblyContract.make(exercise:exercise)?.familyID == activityID}
        if exercise.contractMetadata?.coordinateReasoning != nil {
            return NFCoordinateReasoningContract.make(exercise:exercise)?.familyID == activityID
        }
        if exercise.contractMetadata?.netFolding != nil {
            return NFNetFoldingContract.make(exercise:exercise) != nil && activityID == NFNetFoldingContract.familyID
        }
        if exercise.contractMetadata?.solidSection != nil {
            return NFSolidSectionContract.make(exercise:exercise) != nil && activityID == NFSolidSectionContract.familyID
        }
        if exercise.contractMetadata?.coordinateTransform != nil {
            return NFCoordinateTransformContract.make(exercise: exercise)?.familyID == activityID
        }
        if exercise.contractMetadata?.spatialStructure != nil {
            return NFSpatialStructureContract.make(exercise: exercise)?.familyID == activityID
        }
        if exercise.contractMetadata?.retrievalAsset != nil {
            guard let asset = NFRetrievalAssetContract.make(exercise: exercise) else { return false }
            let expected: String
            switch asset.form {
            case .cloze: expected = "nf.default.retrieval.cloze"
            case .equation: expected = "nf.default.retrieval.equation"
            case .figure: expected = "nf.default.retrieval.figure"
            }
            return activityID == expected
        }
        if exercise.contractMetadata?.scienceStudy != nil {
            return NFScienceStudyContract.make(exercise: exercise) != nil && activityID == "nf.default.science.claim-evidence"
        }
        if exercise.contractMetadata?.transferRelationship != nil {
            return NFTransferRelationshipContract.make(exercise: exercise) != nil && activityID == "nf.default.transfer.rate"
        }
        if exercise.contractMetadata?.graphConstruction != nil {
            return NFGraphConstructionContract.make(exercise: exercise) != nil && activityID == NFGraphConstructionContract.activityID
        }
        if exercise.templateID == exercise.templateFamily + "." + activity.templateSlug { return true }
        // Existing v4 families with explicitly enumerated subvariants. This is
        // not a prefix match: a future recipe needs its own supported mapping.
        let legacySlugs: Set<String>
        switch activityID {
        case "nf.default.spatial.cross-section": legacySlugs = ["cross-section.cube", "cross-section.cylinder", "cross-section.sphere"]
        case "nf.default.quantitative.scaling": legacySlugs = ["scaling.direct", "scaling.inverse", "scaling.power-law"]
        case "nf.default.mental.representation-relay": legacySlugs = ["unit-conversion.metric"]
        default: legacySlugs = []
        }
        return exercise.generatorVersion == 4 && exercise.provenance.generatorID == "nf.exercise.fallback"
            && exercise.provenance.generatorVersion == 4
            && legacySlugs.contains(where: { exercise.templateID == exercise.templateFamily + "." + $0 })
    }
}
/// Stable launch context for a preference; ephemeral request IDs and the
/// explicitly adjustable count/timer are not part of this identity.
struct NFEditorialPrelaunchScope: Equatable, Sendable {
    let lab: TrainingLab
    var field: STEMField
    var contentLocale: String
    let profileID: UUID?
    let catalogScope: NFEditorialCatalogScope?
    let catalogVersion: String
    let catalogDigest: String
    init(request: SessionRequest, catalogScope: NFEditorialCatalogScope?, admissions: NFEditorialAdmissionContext) {
        lab = request.lab; field = request.field ?? .general; contentLocale = request.localeIdentifier
        profileID = request.ordinaryDelivery?.profileID; self.catalogScope = catalogScope
        catalogVersion = admissions.version; catalogDigest = admissions.fingerprint
    }
}
enum NFEditorialStartingUnavailableReason: String, Hashable, Sendable, CaseIterable {
    case bandNotReviewed, noUnusedQuestions, quarantined, prerequisites, timing, previouslyExposed, incompatible, scopeChanged, registryUnavailable, notVerified
    var explanationKey: String {
        switch self {
        case .bandNotReviewed: "This band has no reviewed question contract in this activity. Choose a supported band."
        case .noUnusedQuestions: "No unused reviewed questions remain at this challenge. Choose another challenge or activity."
        case .quarantined: "Questions at this challenge are awaiting a content check. Choose another reviewed challenge."
        case .prerequisites: "This challenge requires prerequisite evidence that is not available yet. Choose a supported challenge."
        case .timing: "The chosen timing condition is not supported at this challenge. Timing is separate from the question band."
        case .previouslyExposed: "The matching questions have already been shown. Choose another challenge for fresh practice."
        case .incompatible: "No reviewed question currently meets all the requirements for this challenge."
        case .scopeChanged: "Your selected challenge does not match the current activity, field, language, profile or reviewed catalog. Choose an alternative explicitly."
        case .registryUnavailable: "The reviewed catalog for your selection is unavailable. Your choice has been kept."
        case .notVerified: "Availability could not be checked. Your choice has been kept; retry before starting."
        }
    }
}

/// A preview refresh can update feasibility, not overwrite a person's selected
/// identity. Nil is an explicit mixed/legacy choice once choose(nil) is called.
struct NFEditorialPrelaunchSelection: Equatable, Sendable {
    private(set) var retainedChoice: NFEditorialStartingChoice?
    private(set) var isExplicit = false
    mutating func choose(_ choice: NFEditorialStartingChoice?) {
        retainedChoice = choice; isExplicit = true
    }
    mutating func refresh(_ preview: NFEditorialPrelaunchPreview, selectAutomatic: Bool) {
        if let choice = retainedChoice {
            if let refreshed = preview.choices.first(where: { $0.id == choice.id && $0.launchScope == choice.launchScope }) { retainedChoice = refreshed }
        } else if !isExplicit, selectAutomatic {
            retainedChoice = preview.choices.first { $0.isAutomatic }
        }
    }
    func resolved(in preview: NFEditorialPrelaunchPreview?, requestedCount: Int) -> NFEditorialStartingChoice? {
        guard let retainedChoice else { return nil }
        if let choice = preview?.choices.first(where: { $0.id == retainedChoice.id && $0.launchScope == retainedChoice.launchScope }) { return choice }
        var unavailable = retainedChoice
        unavailable.availableUniqueCount = 0; unavailable.requestedCount = requestedCount
        unavailable.isReviewedInCurrentScope = false; unavailable.availabilityKnown = false
        unavailable.unavailabilityReasons = [preview == nil ? .notVerified
            : preview?.state == .registryUnavailable ? .registryUnavailable : .scopeChanged]
        return unavailable
    }
}

/// Only non-answer-bearing aggregates leave the exact materialization worker.
/// Raw quantities, prompts, option labels, references and evaluator data are
/// deliberately absent from this presentation value.
struct NFEditorialTaskPreview: Equatable, Sendable {
    let activityID: String?
    let relevantGivens: ClosedRange<Int>
    let extraDetails: ClosedRange<Int>
    let missingGivens: ClosedRange<Int>
    let responseSeconds: NFExpectedDurationRange?

    static func make(activityID: String?, records: [NFEditorialDemandRecord]) -> Self? {
        guard !records.isEmpty, records.allSatisfy(\.hasRequiredIdentity) else { return nil }
        func bounds(_ values: [Int]) -> ClosedRange<Int> { values.min()!...values.max()! }
        let durations = records.compactMap(\.expectedDurationRange)
        let range: NFExpectedDurationRange?
        if durations.count == records.count, durations.allSatisfy({ $0.isValid
            && NFSessionDurationPolicy.isValid($0.minimumSeconds)
            && NFSessionDurationPolicy.isValid($0.maximumSeconds) }) {
            range = .init(minimumSeconds: durations.map(\.minimumSeconds).min()!,
                maximumSeconds: durations.map(\.maximumSeconds).max()!)
        } else { range = nil }
        let knownActivity = activityID.flatMap { NFActivityTaskExamples.exampleKey(activityID: $0) == nil ? nil : $0 }
        return .init(activityID: knownActivity, relevantGivens: bounds(records.map { $0.demandVector.relevantGivens }),
            extraDetails: bounds(records.map { $0.demandVector.irrelevantGivens }),
            missingGivens: bounds(records.map { $0.demandVector.missingGivens }), responseSeconds: range)
    }

    /// A planning range includes the same ordinary feedback/transition allowance
    /// as the shared workload policy. It is neither a deadline nor a forecast
    /// of this person's speed. Missing or unsafe values stay unavailable.
    func planningSeconds(questionCount: Int, timing: NFEditorialTimingMode) -> ClosedRange<Int>? {
        guard (1...50).contains(questionCount), let range = responseSeconds else { return nil }
        let overhead = (timing == .timedFluency ? NFEditorialWorkMode.timedFluency : .practice).overheadSeconds
        let minimum = (range.minimumSeconds + overhead) * Double(questionCount)
        let maximum = (range.maximumSeconds + overhead) * Double(questionCount)
        guard let lower = NFSessionDurationPolicy.wholeSeconds(minimum),
              let upper = NFSessionDurationPolicy.wholeSeconds(maximum), lower <= upper else { return nil }
        return lower...upper
    }
}

struct NFEditorialStartingChoice: Equatable, Sendable, Identifiable {
    let scope: NFEditorialFamilyScope
    var launchScope: NFEditorialPrelaunchScope
    let band: NFEditorialBand
    let exerciseTitle: String
    var minimumReasoningSteps: Int
    var maximumReasoningSteps: Int
    var availableUniqueCount: Int
    var requestedCount: Int
    var automaticReason: NFEditorialSelectionReason? = nil
    var taskPreview: NFEditorialTaskPreview? = nil
    var unavailabilityReasons: [NFEditorialStartingUnavailableReason] = []
    var isReviewedInCurrentScope = true
    var availabilityKnown = true
    var isAutomatic: Bool { automaticReason != nil }
    var requestedBand: NFEditorialBand? { isAutomatic ? nil : band }
    var id: String { scope.key + "." + (isAutomatic ? "automatic" : String(band.ordinal)) }
    var explanationKey: String {
        switch automaticReason {
        case .coldStartDefault: return "Finding a comfortable challenge. This starting question is not a level assessment."
        case .recentPracticeTarget: return "Continuing the challenge from your recent compatible practice."
        case .refreshProbe: return "This question refreshes your previous practice after a break. Your recorded level has not been lowered."
        default: return "You chose this challenge. Your recorded level has not changed."
        }
    }
    func canStart(count: Int) -> Bool {
        isReviewedInCurrentScope && availabilityKnown && unavailabilityReasons.isEmpty
            && count > 0 && count <= availableUniqueCount
    }
    var canStartRequestedCount: Bool { canStart(count: requestedCount) }
}
/// A bounded advisory projection of each family's actual initial policy
/// target. It is not a selected path, a level assessment or a full-count promise.
struct NFEditorialMixedStartingPreview: Equatable, Sendable {
    let targets: [NFEditorialStartingChoice]
    var availableFamilyCount: Int { targets.filter { $0.canStart(count: 1) }.count }
    var canStartNext: Bool { availableFamilyCount > 0 }
    var explanationKey: String {
        if !canStartNext {
            return "No reviewed next question is available at these starting targets. The targets have been kept; choose an alternative explicitly."
        }
        if availableFamilyCount < targets.count {
            return "Some starting targets are currently unavailable. Mixed practice can begin in another eligible family without lowering those targets."
        }
        return "Each family has a reviewed next question at its starting target. Later questions depend on your answers and the remaining eligible content."
    }
}

struct NFEditorialPrelaunchPreview: Equatable, Sendable {
    enum State: String, Sendable { case registryUnavailable, activityUnavailable, feasible, temporarilyUnavailable }
    let state: State
    let choices: [NFEditorialStartingChoice]
    let catalogScope: NFEditorialCatalogScope?
    let archiveRevision: UInt64
    var hasReviewedChoices: Bool { choices.contains(where: \.isReviewedInCurrentScope) }
    // A mixed controller accepts one item at a time. A per-family full-count
    // shortage cannot predict that run's later, response-dependent path.
    var mixedStartingPreview: NFEditorialMixedStartingPreview? {
        guard catalogScope == nil, state != .registryUnavailable, state != .activityUnavailable else { return nil }
        let targets = choices.filter(\.isAutomatic).sorted { $0.scope.key < $1.scope.key }
        guard (1...32).contains(targets.count) else { return nil }
        return .init(targets: targets)
    }
    var canStartAutomaticMixed: Bool {
        let targets = choices.filter(\.isAutomatic)
        return (1...32).contains(targets.count) && targets.contains { $0.canStart(count: 1) }
    }
    func unsupportedBands(in scope: NFEditorialFamilyScope) -> [NFEditorialBand] {
        let admitted = Set(choices.filter { $0.scope == scope && $0.isReviewedInCurrentScope }.map(\.band))
        return NFEditorialBand.allCases.filter { !admitted.contains($0) }
    }
    var explanationKey: String {
        switch state {
        case .registryUnavailable: return "Reviewed challenge choices are not available yet. Existing practice is available."
        case .activityUnavailable: return "No reviewed challenge currently matches this activity and field. Existing practice is available."
        case .temporarilyUnavailable: return "The full requested count is unavailable at the shown challenge. Review the reasons and choose an alternative."
        case .feasible: return "Choose the demands of your starting questions. This preference is not a measured level, and timing stays separate."
        }
    }
}
struct NFEditorialPrelaunchInput: Sendable {
    let request: SessionRequest
    let catalogScope: NFEditorialCatalogScope?
    let admissions: NFEditorialAdmissionContext
    let availableBankQuestionIDs: Set<String>
    let exposedSemanticIDs: Set<String>
    let quarantinedItemIDs: Set<String>
    let evidenceInput: NFEditorialLiveController.Input
    let archiveRevision: UInt64
}
enum NFEditorialPrelaunchPolicy {
    static func preview(_ input: NFEditorialPrelaunchInput, checkCancellation: () throws -> Void = {}) throws -> NFEditorialPrelaunchPreview {
        let request = input.request
        let launchScope = NFEditorialPrelaunchScope(request: request, catalogScope: input.catalogScope, admissions: input.admissions)
        guard !input.admissions.entries.isEmpty else {
            return .init(state: .registryUnavailable, choices: [], catalogScope: input.catalogScope, archiveRevision: input.archiveRevision)
        }
        guard request.mechanicID == nil, request.evidenceClass == .practice,
              request.timingCondition?.isSupported == true,
              input.catalogScope?.isSupported != false,
              input.admissions.entries.count <= 4_096 else { throw NFEditorialOverrideError.unsupported }
        let evidence = EditorialBandEvidenceV1.reduce(input.evidenceInput.observations,
            decisionDayOrdinal: input.evidenceInput.day.ordinal, validity: input.evidenceInput.validity)
        let demonstrated = Set(evidence.summaries.filter { $0.lastDemonstratedAt != nil }.map { $0.group.objectiveID })
        let count = min(50, max(1, request.requestedItemCount ?? 5))
        var context = NFEditorialSelectionContext(catalogVersion: input.admissions.version,
            profilePseudonymousID: request.ordinaryDelivery?.profileID.uuidString ?? "preview",
            remainingSittingSeconds: NFSessionDurationPolicy.maximumSeconds, initialTargetContracts: [])
        let entries = input.admissions.entries.filter { $0.isSupported && $0.lab == request.lab && $0.contentLocale == request.localeIdentifier }
        var examples: [String: NFExercise] = [:], demands: [String: [NFEditorialDemandRecord]] = [:]
        var usableDemandsByBankID: [String: NFEditorialDemandRecord] = [:]
        var activityByKey: [String: String] = [:]
        var available: [String: Set<String>] = [:], usableSemanticsByBankID: [String: String] = [:]
        var blocked: [String: Set<NFEditorialStartingUnavailableReason>] = [:]
        for id in Set(entries.map(\.bankQuestionID)).sorted() {
            try checkCancellation()
            guard let ordinal = NFOfflineQuestionBank.ordinal(forQuestionID: id, lab: request.lab) else { continue }
            // Keep a quarantined contract visible as unavailable. Passing its
            // delivery filter into materialization would erase the authenticated
            // row before we could explain why it cannot be selected.
            let exercise = NFDeterministicSessionExerciseFactory.makeExercise(request: request.launchOnly(offlineQuestionOrdinals: [ordinal],
                omittingQuarantineForCatalogInspection: true), index: 0, assessmentDescriptor: nil)
            guard let admission = input.admissions.entry(exercise: exercise), admission.bankQuestionID == id,
                  exercise.sourceContext.primaryField == (request.field ?? .general),
                  input.catalogScope?.matches(exercise) != false else { continue }
            context.initialTargetContracts?.append(.make(exercise: exercise, admission: admission))
            let demand = admission.demand
            let scope = NFEditorialFamilyScope(objectiveID: demand.objectiveID, familyID: demand.familyID)
            let key = scope.key + "." + String(demand.editorialBand.ordinal)
            if examples[key] == nil {
                examples[key] = exercise
                activityByKey[key] = input.catalogScope?.activityID ?? NFDefaultContentCatalog.activities.first { activity in
                    activity.lab == request.lab && NFEditorialCatalogScope(catalogVersion: NFDefaultContentCatalog.version,
                        activityID: activity.id, field: request.field ?? .general).matches(exercise)
                }?.id
            }
            demands[key, default: []].append(demand)
            var reasons: Set<NFEditorialStartingUnavailableReason> = []
            if !input.availableBankQuestionIDs.contains(id) { reasons.insert(.noUnusedQuestions) }
            if input.quarantinedItemIDs.union(request.quarantinedItemIDs).contains(exercise.id) { reasons.insert(.quarantined) }
            if request.timingCondition?.accepts(exercise, reviewedDemand: demand) == false { reasons.insert(.timing) }
            let prerequisitesMet = Set(demand.prerequisiteObjectiveIDs).isSubset(of: demonstrated)
            if !prerequisitesMet { reasons.insert(.prerequisites) }
            let exposed = input.exposedSemanticIDs.contains(demand.semanticFingerprint)
            if exposed { reasons.insert(.previouslyExposed) }
            let control = NFEditorialPracticePolicy.initialControl(sessionID: request.id.uuidString,
                objectiveID: scope.objectiveID, familyID: scope.familyID, explicitBand: demand.editorialBand).0
            let candidate = NFEditorialSelectionCandidate(id: id, item: demand,
                prerequisitesMet: prerequisitesMet, previouslyExposed: exposed)
            if reasons.isEmpty, NFEditorialPracticePolicy.feasibleCandidates([candidate], control: control,
                context: context, validity: input.evidenceInput.validity).isEmpty { reasons.insert(.incompatible) }
            if reasons.isEmpty {
                available[key, default: []].insert(demand.semanticFingerprint)
                usableSemanticsByBankID[id] = demand.semanticFingerprint
                usableDemandsByBankID[id] = demand
            }
            else { blocked[key, default: []].formUnion(reasons) }
        }
        var result = demands.keys.sorted().compactMap { key -> NFEditorialStartingChoice? in
            guard let exercise = examples[key], let records = demands[key], let first = records.first else { return nil }
            let unique = available[key]?.count ?? 0
            let usable = usableDemandsByBankID.values.filter { $0.objectiveID == first.objectiveID
                && $0.familyID == first.familyID && $0.editorialBand == first.editorialBand }
            let previewRecords = usable.isEmpty ? records : usable
            return .init(scope: .init(objectiveID: first.objectiveID, familyID: first.familyID), launchScope: launchScope, band: first.editorialBand,
                exerciseTitle: exercise.title, minimumReasoningSteps: previewRecords.map { $0.demandVector.reasoningSteps }.min() ?? 0,
                maximumReasoningSteps: previewRecords.map { $0.demandVector.reasoningSteps }.max() ?? 0,
                availableUniqueCount: unique, requestedCount: count,
                taskPreview: NFEditorialTaskPreview.make(activityID: activityByKey[key], records: previewRecords),
                unavailabilityReasons: unique == 0 ? (blocked[key] ?? [.incompatible]).sorted { $0.rawValue < $1.rawValue } : [])
        }
        // Initial demand is computed independently from remaining inventory.
        // An automatic target that cannot be delivered stays visibly unavailable.
        for scope in Set(result.map(\.scope)).sorted(by: { $0.key < $1.key }) {
            guard let pin = input.admissions.sessionPin(for: request, startingScope: scope, catalogScope: input.catalogScope),
                  let contracts = context.initialTargetContracts else { continue }
            let target = try NFEditorialInitialTargetPolicy.select(pin: pin, input: input.evidenceInput, contracts: contracts)
            var choice = result.first { $0.scope == scope && $0.band == target.band }
                ?? .init(scope: scope, launchScope: launchScope, band: target.band,
                    exerciseTitle: result.first(where: { $0.scope == scope })?.exerciseTitle ?? request.lab.rawValue,
                    minimumReasoningSteps: 0, maximumReasoningSteps: 0, availableUniqueCount: 0, requestedCount: count,
                    unavailabilityReasons: [.bandNotReviewed], isReviewedInCurrentScope: false)
            if let group = target.evidenceGroup {
                let matchingIDs = Set(contracts.filter { $0.matches(group) }.map(\.bankQuestionID))
                choice.availableUniqueCount = Set(matchingIDs.compactMap { usableSemanticsByBankID[$0] }).count
                let compatible = matchingIDs.compactMap { usableDemandsByBankID[$0] }
                if !compatible.isEmpty {
                    choice.minimumReasoningSteps = compatible.map { $0.demandVector.reasoningSteps }.min()!
                    choice.maximumReasoningSteps = compatible.map { $0.demandVector.reasoningSteps }.max()!
                    choice.taskPreview = NFEditorialTaskPreview.make(activityID: choice.taskPreview?.activityID, records: compatible)
                }
                if choice.availableUniqueCount == 0, choice.unavailabilityReasons.isEmpty {
                    choice.unavailabilityReasons = [.incompatible]
                }
            }
            choice.automaticReason = target.reason
            result.append(choice)
        }
        result.sort { a, b in
            if a.scope.key != b.scope.key { return a.scope.key < b.scope.key }
            if a.isAutomatic != b.isAutomatic { return a.isAutomatic }
            return a.band < b.band
        }
        // Automatic mixed accepts only its next item. Its per-family pools do
        // not need to supply the entire requested count by themselves. Focused
        // choices still use canStartRequestedCount at their explicit launch.
        let automaticTargets = result.filter(\.isAutomatic)
        let canStart = input.catalogScope == nil
            ? (1...32).contains(automaticTargets.count) && automaticTargets.contains { $0.canStart(count: 1) }
            : result.contains { $0.canStartRequestedCount }
        return .init(state: result.isEmpty ? .activityUnavailable
            : canStart ? .feasible : .temporarilyUnavailable,
            choices: result, catalogScope: input.catalogScope, archiveRevision: input.archiveRevision)
    }
}


/// A selection preference, not a misconception diagnosis or retention result.
struct NFEditorialCriterionMatch: Codable, Equatable, Sendable {
    let criterionID: String
    let observationIDs: [String]
}
struct NFEditorialCriterionSelection: Codable, Equatable, Sendable {
    let policyVersion: String
    let candidateID: String
    let exerciseDigest: String
    let group: NFEditorialEvidenceGroup
    let structureID: String
    let criterionIDs: [String]
    var coverageRaw = "scoredComponents"
    var matches: [NFEditorialCriterionMatch] = []
    var preference: Int { matches.isEmpty ? 0 : 1 }
    var supportingObservationIDs: Set<String> { Set(matches.flatMap(\.observationIDs)) }
    private var coverageIsConsistent: Bool {
        switch coverageRaw {
        case "scoredComponents": return (1...64).contains(criterionIDs.count)
        case "unavailable": return criterionIDs.isEmpty && matches.isEmpty
        default: return false
        }
    }
    var isSupported: Bool {
        policyVersion == NFEditorialCriterionRankingPolicy.version && !candidateID.isEmpty && !structureID.isEmpty
            && exerciseDigest.count == 64 && exerciseDigest.allSatisfy(\.isHexDigit)
            && group.lane == .practice && group.protocolScope == "practice.v1"
            && [group.objectiveID, group.familyID, group.bandContractVersion,
                group.scoringComparabilityID, group.stimulusComparabilityID].allSatisfy({ !$0.isEmpty && $0 != "unknown" })
            && NFEditorialTimingMode(rawValue: group.pacingConditionID) != nil
            && !group.toolConditionID.isEmpty && group.toolConditionID != "unknown"
            && !group.localeComparabilityID.isEmpty && group.localeComparabilityID != "unknown"
            && coverageIsConsistent && criterionIDs == Set(criterionIDs).sorted()
            && criterionIDs.allSatisfy({ !$0.isEmpty && $0.utf8.count <= 256 })
            && matches.map(\.criterionID) == Set(matches.map(\.criterionID)).sorted()
            && matches.allSatisfy({ criterionIDs.contains($0.criterionID) && (2...20).contains($0.observationIDs.count)
                && Set($0.observationIDs).count == $0.observationIDs.count && $0.observationIDs.allSatisfy({ !$0.isEmpty }) })
    }
}

enum NFEditorialCriterionRankingPolicy {
    static let version = "ObservedCriterionPreferenceV1"

    /// IDs come from the supported scorer's actual component contract. A generic
    /// response component remains neutral; x/y are not shared across structures.
    @inline(never)
    static func contract(exercise: NFExercise, admission: NFEditorialAdmissionEntry,
                         timing: NFEditorialTimingMode?) -> NFEditorialCriterionSelection? {
        guard let timing, admission.isSupported, NFEditorialNativeProtocol.supports(exercise),
              !exercise.assessmentProtected, exercise.evidenceClass == .practice,
              exercise.provenance.sourceDocumentIDs.isEmpty,
              admission.exerciseDigest == (try? NFLocalItemCheckpoint.digest(exercise)),
              admission.contentLocale == exercise.localeIdentifier, admission.lab == exercise.lab,
              admission.demand.semanticFingerprint == (exercise.contractMetadata?.semanticFingerprint
                ?? NFQuestionFingerprint.fingerprint(for: exercise)) else { return nil }
        let ids: [String]
        switch exercise.interaction {
        case .numeric, .singleChoice: ids = ["response"]
        case .logicState(let schema):
            if NFCoordinateTransformContract.make(exercise: exercise) != nil {
                ids = (Array(schema.expectedFinalState.keys) + (schema.expectedViolatedRuleID == nil ? [] : ["invariant"])).sorted()
            } else { ids = [] }
        default: ids = []
        // An independently admitted future native contract may remain selectable
        // with no criterion preference until its component mapping is supported.
        }
        let base = NFEditorialInitialTargetContract.make(exercise: exercise, admission: admission).group
        let group = NFEditorialEvidenceGroup(lane: .practice, objectiveID: base.objectiveID, familyID: base.familyID,
            band: base.band, bandContractVersion: base.bandContractVersion,
            scoringComparabilityID: base.scoringComparabilityID, stimulusComparabilityID: base.stimulusComparabilityID,
            toolConditionID: base.toolConditionID, localeComparabilityID: base.localeComparabilityID,
            pacingConditionID: timing.rawValue, protocolScope: base.protocolScope)
        var value = NFEditorialCriterionSelection(policyVersion: version, candidateID: admission.bankQuestionID,
            exerciseDigest: admission.exerciseDigest, group: group, structureID: admission.demand.structureID, criterionIDs: ids)
        if ids.isEmpty { value.coverageRaw = "unavailable" }
        return value.isSupported ? value : nil
    }

    private static func recentDay(_ day: Int, at current: Int) -> Bool {
        let delta = current.subtractingReportingOverflow(day)
        return !delta.overflow && (0..<60).contains(delta.partialValue)
    }

    /// Last 20 independent observations / 60 captured local days in the exact
    /// group. Two distinct semantic misses since a full component success are
    /// required. Confidence, speed and learner reflections never enter this rule.
    static func project(contracts: [String: NFEditorialCriterionSelection], observations: [NFEditorialObservation],
                        evidence: NFEditorialEvidenceState, validity: NFEditorialValidityProjection) -> [String: NFEditorialCriterionSelection] {
        guard evidence.policyVersion == EditorialBandEvidenceV1.policyVersion,
              evidence.validityRevision == validity.revision else { return [:] }
        let independent = Set(evidence.independentObservationIDs)
        var seen: Set<String> = []
        let accepted = observations.sorted(by: EditorialBandEvidenceV1.stableOrder).filter {
            independent.contains($0.id) && seen.insert($0.id).inserted && $0.lane == .practice
                && $0.sourceOrSetID == nil && EditorialBandEvidenceV1.group(for: $0) != nil
                && recentDay($0.canonicalDayOrdinal, at: evidence.decisionDayOrdinal)
        }
        let grouped = Dictionary(grouping: accepted) { EditorialBandEvidenceV1.group(for: $0)! }
        struct Support { let id: String; let semantic: String }
        var byGroup: [NFEditorialEvidenceGroup: [String: [String: [Support]]]] = [:]
        for (group, values) in grouped {
            var byStructure: [String: [String: [Support]]] = [:]
            for observation in values.suffix(20) {
                guard let item = observation.item else { continue }
                // A scalar correction cannot authorize old component values.
                // Treat it as an unknown barrier instead of inventing corrected
                // missing criteria or carrying an obsolete pattern through it.
                if validity.correctedScoreByObservationID[observation.id] != nil {
                    byStructure[item.structureID] = [:]; continue
                }
                for (criterion, credit) in observation.rubricCriterionCredits {
                    if credit == 1 { byStructure[item.structureID, default: [:]][criterion] = [] }
                    else if credit.isFinite, (0..<1).contains(credit), observation.missingCriterionIDs.contains(criterion) {
                        var supports = byStructure[item.structureID, default: [:]][criterion, default: []]
                        if !supports.contains(where: { $0.semantic == item.semanticFingerprint }) {
                            supports.append(.init(id: observation.id, semantic: item.semanticFingerprint))
                        }
                        byStructure[item.structureID, default: [:]][criterion] = supports
                    }
                }
            }
            byGroup[group] = byStructure
        }
        var result: [String: NFEditorialCriterionSelection] = [:]
        for (id, contract) in contracts where id == contract.candidateID && contract.isSupported {
            var selected = contract; selected.matches = []
            for criterion in contract.criterionIDs {
                let supports = byGroup[contract.group]?[contract.structureID]?[criterion] ?? []
                if supports.count >= 2 { selected.matches.append(.init(criterionID: criterion, observationIDs: supports.map(\.id))) }
            }
            result[id] = selected
        }
        return result
    }
}


/// Authored applicability, never a proficiency estimate or an inference from a
/// lab title. The reviewed admission manifest authenticates this exact mapping.
struct NFEditorialGoalAlignment: Codable, Equatable, Sendable {
    var schemaVersion = 1
    let objectiveID: String
    let goalIDsRaw: [String]
    var isSupported: Bool {
        schemaVersion == 1 && !objectiveID.isEmpty && objectiveID.utf8.count <= 256
            && !goalIDsRaw.isEmpty && goalIDsRaw.count <= TrainingGoal.allCases.count
            && goalIDsRaw == Array(Set(goalIDsRaw)).sorted()
            && goalIDsRaw.allSatisfy { TrainingGoal(rawValue: $0) != nil }
    }
}

/// A launch-time copy of explicit preferences. Empty known goals mean no goal
/// preference. Unknown fields/IDs never fall back to guessed goals.
struct NFEditorialGoalPreferences: Codable, Equatable, Sendable {
    var schemaVersion = 1
    let policyVersion: String
    let profileID: UUID
    let goalIDsRaw: [String]
    var isSupported: Bool {
        schemaVersion == 1 && policyVersion == NFEditorialGoalRankingPolicy.preferenceVersion
            && goalIDsRaw.count <= TrainingGoal.allCases.count
            && goalIDsRaw == Array(Set(goalIDsRaw)).sorted()
            && goalIDsRaw.allSatisfy { TrainingGoal(rawValue: $0) != nil }
    }
}

struct NFEditorialGoalSelection: Codable, Equatable, Sendable {
    var schemaVersion = 1
    let policyVersion: String
    let preferences: NFEditorialGoalPreferences
    let candidateID: String
    let exerciseDigest: String
    let objectiveID: String
    let alignment: NFEditorialGoalAlignment?
    let matchedGoalIDsRaw: [String]
    var preference: Int { matchedGoalIDsRaw.isEmpty ? 0 : 1 }
    var isSupported: Bool {
        guard schemaVersion == 1 && policyVersion == NFEditorialGoalRankingPolicy.version,
              preferences.isSupported, !candidateID.isEmpty, !objectiveID.isEmpty,
              exerciseDigest.count == 64 && exerciseDigest.allSatisfy(\.isHexDigit),
              alignment?.isSupported != false, alignment?.objectiveID == nil || alignment?.objectiveID == objectiveID else { return false }
        return matchedGoalIDsRaw == Set(preferences.goalIDsRaw).intersection(alignment?.goalIDsRaw ?? []).sorted()
    }
}

enum NFEditorialGoalRankingPolicy {
    static let version = "AuthoredGoalRankingV1"
    static let preferenceVersion = "ExplicitGoalPreferencesV1"

    static func selection(admission: NFEditorialAdmissionEntry,
                          preferences: NFEditorialGoalPreferences) -> NFEditorialGoalSelection? {
        guard admission.isSupported, preferences.isSupported else { return nil }
        let alignment = admission.demand.goalAlignment
        let value = NFEditorialGoalSelection(policyVersion: version, preferences: preferences,
            candidateID: admission.bankQuestionID, exerciseDigest: admission.exerciseDigest,
            objectiveID: admission.demand.objectiveID, alignment: alignment,
            matchedGoalIDsRaw: Set(preferences.goalIDsRaw).intersection(alignment?.goalIDsRaw ?? []).sorted())
        return value.isSupported ? value : nil
    }

    /// A reviewed objective has one mapping inside this exact manifest. Conflicts
    /// cannot make the row traversal order decide the learner's preference.
    static func consistentAlignments(_ entries: [NFEditorialAdmissionEntry]) -> Bool {
        for (objective, items) in Dictionary(grouping: entries, by: { $0.demand.objectiveID }) {
            let declared = items.compactMap { $0.demand.goalAlignment }
            guard let first = declared.first else { continue }
            guard first.isSupported, first.objectiveID == objective,
                  items.allSatisfy({ $0.demand.goalAlignment == first }) else { return false }
        }
        return true
    }
}

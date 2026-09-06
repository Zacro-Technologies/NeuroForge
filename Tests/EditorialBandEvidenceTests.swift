import Foundation
import XCTest
@testable import NeuroForge

final class EditorialBandEvidenceTests: XCTestCase {
    func testRuntimeWorkloadKeepsLegacyAdvisorySeparateFromReviewedDemand() throws {
        let legacy = try XCTUnwrap(NFEditorialWorkloadPolicy.runtimeEstimate(reviewedDemand: nil,
            legacyExpectedResponseSeconds: 55, mode: .practice))
        XCTAssertEqual(legacy.authority, .legacyAdvisory)
        XCTAssertEqual(legacy.totalSeconds, 63)
        let reviewed = try XCTUnwrap(NFEditorialWorkloadPolicy.runtimeEstimate(reviewedDemand: item(1),
            legacyExpectedResponseSeconds: 55, mode: .protectedCheck))
        XCTAssertEqual(reviewed.authority, .reviewedRange)
        XCTAssertEqual(reviewed.totalSeconds, 21)
        XCTAssertNil(NFEditorialWorkloadPolicy.runtimeEstimate(reviewedDemand: nil,
            legacyExpectedResponseSeconds: .nan, mode: .practice))
    }

    func testRuntimeWorkloadAdmitsOnlyTasksThatFitWithoutMinimumCountFloor() {
        let one = NFEditorialWorkloadEstimate(totalSeconds: 63, authority: .legacyAdvisory)
        XCTAssertEqual(NFEditorialWorkloadPolicy.admission(estimate: one, remainingSeconds: 60, protected: false), .shorterTaskNeeded)
        XCTAssertEqual(NFEditorialWorkloadPolicy.admission(estimate: one, remainingSeconds: 60, protected: true), .saveForLater)
        XCTAssertEqual(NFEditorialWorkloadPolicy.admission(estimate: one, remainingSeconds: 63, protected: true), .fits)
        XCTAssertEqual(NFEditorialWorkloadPolicy.plannedItemCount(estimates: [one, one, one], budgetSeconds: 125, mode: .practice), 1)
        XCTAssertEqual(NFEditorialWorkloadPolicy.plannedItemCount(estimates: [one], budgetSeconds: 60, mode: .practice), 0)
        XCTAssertEqual(NFEditorialWorkloadPolicy.plannedItemCount(estimates: Array(repeating: one, count: 20), budgetSeconds: 1_000, mode: .practice), 15)
    }

    private func fluencyObservation(_ id: Int, band: NFEditorialBand = .b1) throws -> NFEditorialObservation {
        let base = observation(id, band: band)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(base)) as? [String: Any])
        var demand = try XCTUnwrap(object["item"] as? [String: Any])
        demand["reviewedFluencyEligible"] = true; object["item"] = demand
        return try JSONDecoder().decode(NFEditorialObservation.self, from: JSONSerialization.data(withJSONObject: object))
    }

    func testReviewedFluencyGateRequiresExplicitContractsCompatibleBandAndTwoSessions() throws {
        let legacy = (0..<20).map { observation($0) }
        XCTAssertFalse(NFEditorialPracticePolicy.reviewedFluencyReadiness(observations: legacy, decisionDayOrdinal: 110).timingEligible)
        let qualified = try (0..<8).map { try fluencyObservation($0) }
        let ready = NFEditorialPracticePolicy.reviewedFluencyReadiness(observations: qualified, decisionDayOrdinal: 105)
        XCTAssertTrue(ready.timingEligible); XCTAssertEqual(ready.sampleCount, 8)
        XCTAssertEqual(ready.condition?.mode, .timedFluency)
        let split = try (0..<8).map { try fluencyObservation($0, band: $0 < 4 ? .b1 : .b2) }
        XCTAssertFalse(NFEditorialPracticePolicy.reviewedFluencyReadiness(observations: split, decisionDayOrdinal: 105).timingEligible)
        let oneSession = qualified.enumerated().map { replacingSession($0.element, id: "one-session", ordinal: $0.offset) }
        XCTAssertFalse(NFEditorialPracticePolicy.reviewedFluencyReadiness(observations: oneSession, decisionDayOrdinal: 105).timingEligible)
        XCTAssertFalse(NFEditorialPracticePolicy.reviewedFluencyReadiness(observations: qualified, decisionDayOrdinal: 165).timingEligible)
    }

    func testReviewedFluencyGateAppliesCorrectionsHelpAndUnresolvedCriteria() throws {
        let qualified = try (0..<8).map { try fluencyObservation($0) }
        var assisted = qualified; assisted[0].helpBeforeLock = true
        XCTAssertFalse(NFEditorialPracticePolicy.reviewedFluencyReadiness(observations: assisted, decisionDayOrdinal: 105).timingEligible)
        var validity = NFEditorialValidityProjection()
        validity.correctedScoreByObservationID[qualified[0].id] = .init(
            credit: 0.5, isFullCredit: false, isZeroCredit: false,
            correctionID: "QA.fluency-correction.v1",
            explanation: "Synthetic reviewed rubric correction removes one full-credit fluency observation.")
        XCTAssertFalse(NFEditorialPracticePolicy.reviewedFluencyReadiness(observations: qualified,
            decisionDayOrdinal: 105, validity: validity).timingEligible)
        var failing = try (8..<10).map { try fluencyObservation($0) }
        for index in failing.indices {
            failing[index].credit = 0; failing[index].isFullCredit = false; failing[index].isZeroCredit = true
            failing[index].missingCriterionIDs = ["place-value"]
        }
        let blocked = NFEditorialPracticePolicy.reviewedFluencyReadiness(observations: qualified + failing, decisionDayOrdinal: 105)
        XCTAssertEqual(blocked.reason, .unresolvedCriterion)
        XCTAssertFalse(blocked.timingEligible)
    }

    func testVersionedTimingConditionsPreserveUnknownModeAndRequireRealFluencyScope() throws {
        let elapsed = NFSessionTimingCondition(.elapsedOnly)
        XCTAssertTrue(elapsed.isSupported)
        XCTAssertFalse(NFSessionTimingCondition(.timedFluency).isSupported)
        var future = elapsed; future.schemaVersion = 999; future.modeRaw = "future-mode"
        let restored = try JSONDecoder().decode(NFSessionTimingCondition.self, from: JSONEncoder().encode(future))
        XCTAssertEqual(restored, future); XCTAssertFalse(restored.isSupported)
        XCTAssertNil(NFSessionDurationPolicy.wholeSeconds(1e300))
        XCTAssertNil(NFSessionDurationPolicy.wholeSeconds(-1))
        XCTAssertNil(NFSessionDurationPolicy.wholeSeconds(.infinity))
    }

    // QA.Catalog.v1 is an authored policy fixture: band changes encode the prescribed
    // one operation, composition, representation decision and constraint verification.
    private func item(_ id: Int, band: NFEditorialBand = .b1, structure: String? = nil,
                      family: String = "F.mul") -> NFEditorialDemandRecord {
        let steps = [1, 2, 3, 4][band.ordinal - 1]
        return NFEditorialDemandRecord(objectiveID: "O.mul", familyID: family,
            structureID: structure ?? "S.\(id % 2)", semanticFingerprint: "semantic.\(band.rawValue).\(family).\(id)",
            editorialBand: band, demandVector: NFDemandVector(reasoningSteps: steps,
                quantityDomain: ["integerFactors": "2...12", "answerContract": "exact-product"],
                representationMappings: band >= .b3 ? ["table-to-equation", "assumption-selection"] : ["equation"],
                misconceptionClasses: ["addition-instead-of-product"], abstraction: "concrete",
                relevantGivens: 2, irrelevantGivens: band >= .b3 ? 1 : 0, missingGivens: 0,
                scaffoldConditionID: "essential-only", prerequisiteConceptIDs: ["multiplication"]),
            bandContractVersion: "QA.Catalog.v1", calibrationStatus: .editorial, calibrationVersion: nil,
            independentEligible: true, protectedEligible: true, assistancePolicyID: "scratchpad-permitted.v1",
            answerContractVersion: "exact-product.v1", expectedDurationRange: .init(minimumSeconds: 10, maximumSeconds: 20),
            representationIDs: ["numeric"], prerequisiteObjectiveIDs: ["O.add"],
            stimulusComparabilityID: "QA.response-equivalence.v1", requiredDemonstrationFormatIDs: ["numeric", "choice"])
    }
    private func observation(_ id: Int, credit: Double = 1, day: Int? = nil, band: NFEditorialBand = .b1,
                             structure: String? = nil, lane: NFEditorialEvidenceLane = .practice) -> NFEditorialObservation {
        let d = day ?? (100 + id / 4)
        var value = NFEditorialObservation(id: "o.\(id)", sessionID: "session.\(id / 4)", sessionOrdinal: id % 4,
            eventOrder: Int64(id), canonicalDayOrdinal: d, canonicalDayKey: "day.\(d)", dayPolicyVersion: "trainingDay.v1",
            occurredAt: Date(timeIntervalSince1970: Double(id + d * 86400)), item: item(id, band: band, structure: structure),
            lane: lane, outcome: .scored, originalResponse: "authored response \(id)", credit: credit,
            isFullCredit: credit == 1, isZeroCredit: credit == 0)
        value.conditions = .init(toolConditionID: "scratchpad-permitted.v1", contentLocale: "en",
                                 timingMode: .untimed, stimulusResponseFormatID: id % 2 == 0 ? "numeric" : "choice")
        value.assistanceKnown = true
        return value
    }
    private func state(_ observations: [NFEditorialObservation], day: Int = 105,
                       validity: NFEditorialValidityProjection = .init()) -> NFEditorialEvidenceState {
        EditorialBandEvidenceV1.reduce(observations, decisionDayOrdinal: day, validity: validity)
    }
    private func selection(_ credits: [Double], band: NFEditorialBand = .b1, fixed: Bool = false,
                           hints: Set<Int> = [], nextBandCount: Int = 6) -> NFEditorialSelectionResult {
        var control = NFEditorialPracticePolicy.initialControl(sessionID: "session.test", objectiveID: "O.mul", familyID: "F.mul", explicitBand: band).0
        if fixed { control.challengeMode = .fixedBand(band) }
        var history: [NFEditorialObservation] = []
        var result: NFEditorialSelectionResult!
        for (id, credit) in credits.enumerated() {
            var o = observation(id, credit: credit, day: 100, band: control.currentTargetBand)
            o = replacingSession(o, id: "session.test", ordinal: id)
            o.helpBeforeLock = hints.contains(id)
            history.append(o)
            let pool = NFEditorialBand.allCases.flatMap { b in
                (0..<(b == band.higher ? nextBandCount : 12)).map { j in
                    NFEditorialSelectionCandidate(id: "candidate.\(b.rawValue).\(j)", item: item(100 + j, band: b))
                }
            }
            result = NFEditorialPracticePolicy.selectNext(control: control, observation: o, history: history,
                evidence: state(history), candidates: pool,
                context: .init(catalogVersion: "QA.Catalog.v1", profilePseudonymousID: "profile.fixed", remainingSittingSeconds: 500))
            control = result.control
        }
        return result
    }
    private func replacingSession(_ o: NFEditorialObservation, id: String, ordinal: Int) -> NFEditorialObservation {
        var data = try! JSONSerialization.jsonObject(with: JSONEncoder().encode(o)) as! [String: Any]
        data["sessionID"] = id; data["sessionOrdinal"] = ordinal
        return try! JSONDecoder().decode(NFEditorialObservation.self, from: JSONSerialization.data(withJSONObject: data))
    }

    func testADPF03ColdStart() {
        let (c, r) = NFEditorialPracticePolicy.initialControl(sessionID: "s", objectiveID: "O.mul", familyID: "F.mul")
        XCTAssertEqual(c.currentTargetBand, .b1); XCTAssertEqual(r, .coldStartDefault)
        XCTAssertTrue(state([]).summaries.isEmpty)
    }
    func testADPF04ExplicitHarderStart() {
        let (c, r) = NFEditorialPracticePolicy.initialControl(sessionID: "s", objectiveID: "O.mul", familyID: "F.mul", explicitBand: .b3)
        XCTAssertEqual(c.currentTargetBand, .b3); XCTAssertEqual(r, .userRequested)
    }
    func testADPF05StrongTrajectory() {
        let result = selection([1, 1, 1, 1])
        XCTAssertEqual(result.candidate?.item.editorialBand, .b2)
        XCTAssertEqual(result.candidate?.item.demandVector.reasoningSteps, 2)
        XCTAssertEqual(result.control.upwardChangesThisSession, 1)
        XCTAssertNil(state((0..<4).map { observation($0) }).summaries.first?.lastDemonstratedAt)
    }
    func testADPF06WeakTrajectory() { XCTAssertEqual(selection([0, 0, 0], band: .b3).candidate?.item.editorialBand, .b2) }
    func testADPF07MixedTrajectory() { XCTAssertEqual(selection([1, 0, 1, 0.5, 1], band: .b2).control.currentTargetBand, .b2) }
    func testADPF08PartialUpBoundary() { XCTAssertEqual(selection([1, 1, 1, 0.5], band: .b2).control.currentTargetBand, .b3) }
    func testADPF09PartialDownBoundary() { XCTAssertEqual(selection([0, 0, 0.5], band: .b3).control.currentTargetBand, .b2) }
    func testADPF10ZeroFlagsMatter() {
        XCTAssertEqual(selection([0, 1, 0], band: .b2).control.currentTargetBand, .b1)
        XCTAssertEqual(selection([0, 0.5, 0.5], band: .b2).control.currentTargetBand, .b2)
    }
    func testADPF11FixedBand() {
        XCTAssertEqual(selection(Array(repeating: 1, count: 8), band: .b2, fixed: true).control.currentTargetBand, .b2)
        XCTAssertEqual(selection(Array(repeating: 0, count: 8), band: .b2, fixed: true).control.currentTargetBand, .b2)
    }
    func testADPF12UpwardThrottle() {
        let result = selection(Array(repeating: 1, count: 8))
        XCTAssertEqual(result.control.currentTargetBand, .b2); XCTAssertEqual(result.control.upwardChangesThisSession, 1)
    }
    func testADPF13FoundationFloor() {
        let result = selection([0, 0, 0]); XCTAssertEqual(result.control.currentTargetBand, .b1); XCTAssertEqual(result.reason, .foundationSupport)
    }
    func testADPF14AssistedSequence() {
        let result = selection([1, 1, 1], band: .b2, hints: [0, 1])
        XCTAssertEqual(result.control.currentTargetBand, .b2); XCTAssertTrue(result.control.shouldOfferSupport)
        XCTAssertEqual(result.control.currentBandDecisionResponseIDs.count, 1)
    }
    func testADPF16SparseNextBand() {
        let result = selection([1, 1, 1, 1], nextBandCount: 2)
        XCTAssertEqual(result.control.currentTargetBand, .b1); XCTAssertEqual(result.reason, .nextBandUnavailable)
    }
    func testADPF17EmptyActivityAndADPF18StableTie() {
        let control = NFEditorialPracticePolicy.initialControl(sessionID: "s", objectiveID: "O.mul", familyID: "F.mul").0
        let context = NFEditorialSelectionContext(catalogVersion: "QA.Catalog.v1", profilePseudonymousID: "p", remainingSittingSeconds: 500)
        let pool = (0..<6).map { NFEditorialSelectionCandidate(id: "c.\($0)", item: item($0)) }
        func choose(_ pool: [NFEditorialSelectionCandidate]) -> NFEditorialSelectionResult {
            NFEditorialPracticePolicy.selectNext(control: control, observation: nil, history: [], evidence: state([]), candidates: pool, context: context)
        }
        XCTAssertEqual(choose(pool).candidate?.id, choose(pool.reversed()).candidate?.id)
        let wrong = [NFEditorialSelectionCandidate(id: "wrong", item: item(0, family: "different"))]
        XCTAssertNil(choose(wrong).candidate); XCTAssertFalse(choose(wrong).shortageOptions.isEmpty)
    }
    func testADPF20UserOverrideDoesNotResetLimits() {
        var c = selection([1, 1, 1, 1]).control
        c.override(to: .b3)
        XCTAssertEqual(c.currentTargetBand, .b3); XCTAssertEqual(c.upwardChangesThisSession, 1)
        XCTAssertTrue(c.currentBandDecisionResponseIDs.isEmpty); XCTAssertEqual(c.challengeMode, .adaptive)
    }
    func testEVDF01SupportedBand() {
        let summary = state((0..<8).map { observation($0, credit: $0 == 7 ? 0.5 : 1) }).summaries[0]
        XCTAssertEqual(summary.coverage, .recentlySupported); XCTAssertEqual(summary.recentMeanCredit, 0.9375)
        XCTAssertEqual(summary.qualifyingObservationIDs.count, 8); XCTAssertEqual(summary.fullCorrectCount, 7)
    }
    func testEVDF02OneStructureGaming() {
        let s = state((0..<20).map { observation($0, structure: "single") }).summaries[0]
        XCTAssertEqual(s.coverage, .limitedBreadth); XCTAssertNil(s.lastDemonstratedAt)
        XCTAssertEqual(s.qualifyingObservationIDs.count, 4)
    }
    func testEVDF03SameItemGaming() {
        let original = observation(0)
        let copies = (0..<20).map { index -> NFEditorialObservation in
            var data = try! JSONSerialization.jsonObject(with: JSONEncoder().encode(original)) as! [String: Any]
            data["id"] = "repeat.\(index)"; data["eventOrder"] = index; data["sessionOrdinal"] = index
            return try! JSONDecoder().decode(NFEditorialObservation.self, from: JSONSerialization.data(withJSONObject: data))
        }
        XCTAssertEqual(state(copies).independentObservationIDs.count, 1); XCTAssertEqual(state(copies).exclusions.count, 19)
    }
    func testEVDF04OneSessionStreak() {
        let observations = (0..<8).map { replacingSession(observation($0, day: 100), id: "same", ordinal: $0) }
        let s = state(observations).summaries[0]
        XCTAssertEqual(s.coverage, .earlyObservations); XCTAssertNil(s.lastDemonstratedAt)
    }
    func testEVDF05ConfidenceInvariance() {
        func values(_ probability: Double) -> [NFEditorialObservation] {
            (0..<8).map { id in var o = observation(id); o.confidence = .init(probability: probability, mappingVersion: "confidenceCategoricalV1", collectionPolicy: .optionalPractice, lockedBeforeOutcome: true); o.retentionScopeID = "relation"; return o }
        }
        let a = state(values(0.25)), b = state(values(0.92))
        XCTAssertEqual(a.summaries, b.summaries); XCTAssertEqual(a.retention, b.retention)
        XCTAssertEqual(a.independentObservationIDs, b.independentObservationIDs)
    }
    func testEVDF06InvitationReplay() {
        for group in 0..<20 {
            let invited = (group * 5..<(group + 1) * 5).filter { EditorialBandEvidenceV1.confidenceInvited(sessionID: "session", ordinaryPresentationOrdinal: $0) }
            XCTAssertEqual(invited.count, 1)
            XCTAssertTrue(EditorialBandEvidenceV1.confidenceInvited(sessionID: "session", ordinaryPresentationOrdinal: invited[0]))
        }
    }
    func testEVDF07CalibrationMinimumAndRetrospection() {
        func values(_ count: Int) -> [NFEditorialObservation] { (0..<count).map { id in
            var o = observation(id); o.confidence = .init(probability: 0.72, mappingVersion: "confidenceCategoricalV1", collectionPolicy: .optionalPractice, lockedBeforeOutcome: true); return o
        } }
        XCTAssertNil(state(values(11)).calibration[0].meanBias)
        XCTAssertNotNil(state(values(12)).calibration[0].meanBias)
        var retrospective = observation(20); retrospective.confidence = .init(probability: 0.92, mappingVersion: "confidenceCategoricalV1", collectionPolicy: .optionalPractice, lockedBeforeOutcome: false)
        XCTAssertTrue(state([retrospective]).calibration.isEmpty)
        var required = values(12); required[0].confidence = .init(probability: 0.72, mappingVersion: "confidenceCategoricalV1", collectionPolicy: .requiredCalibration, lockedBeforeOutcome: true)
        XCTAssertEqual(state(required).calibration.count, 2)
        XCTAssertTrue(state(required).calibration.allSatisfy { $0.meanBias == nil })
    }
    func testEVDF08PartialConfidenceUsesBinaryFullCredit() {
        let values = (0..<12).map { id -> NFEditorialObservation in
            var o = observation(id, credit: 0.5); o.confidence = .init(probability: 0.72, mappingVersion: "confidenceCategoricalV1", collectionPolicy: .optionalPractice, lockedBeforeOutcome: true); return o
        }
        XCTAssertEqual(state(values).calibration[0].meanBias!, 0.72, accuracy: 1e-12)
        XCTAssertEqual(state(values).summaries[0].recentMeanCredit, 0.5)
    }
    func testEVDF10And11ResumeTiming() {
        var o = observation(0); o.durationChunksSeconds = [20, 5]; o.durationComplete = true
        o.interruptionCount = 1; o.resumedAfterRelaunch = true
        XCTAssertEqual(o.knownActiveSeconds, 25); XCTAssertEqual(state([o]).independentObservationIDs, [o.id])
        XCTAssertTrue(state([o]).cleanSpeedObservationIDs.isEmpty)
        o.helpBeforeLock = true
        XCTAssertTrue(state([o]).independentObservationIDs.isEmpty)
    }
    func testEVDF12ClockDoesNotMeasureActiveTime() {
        var o = observation(0); o.durationChunksSeconds = [20, 5]
        XCTAssertEqual(o.knownActiveSeconds, 25)
        o.durationChunksSeconds = [20, -.infinity]; XCTAssertNil(o.knownActiveSeconds)
    }
    func testEVDF13DuplicateCommit() {
        var o = observation(0); o.retentionScopeID = "relation"
        XCTAssertEqual(state([o]), state([o, o, o]))
    }
    func testEVDF14QuarantineAndEVDF16Reinstatement() {
        let history = (0..<8).map { observation($0) }
        var validity = NFEditorialValidityProjection(); validity.dispositionByObservationID["o.0"] = .quarantined
        let corrected = state(history, validity: validity)
        XCTAssertEqual(corrected.independentObservationIDs.count, 7)
        XCTAssertEqual(corrected.summaries[0].coverage, .evidenceAffected)
        validity.dispositionByObservationID["o.0"] = .valid
        XCTAssertEqual(state(history, validity: validity).summaries, state(history).summaries)
    }
    func testEVDF15FaultySiblingFamily() {
        var validity = NFEditorialValidityProjection(); validity.dispositionByFamilyID["F.mul"] = .invalid
        XCTAssertTrue(state((0..<4).map { observation($0) }, validity: validity).independentObservationIDs.isEmpty)
        XCTAssertFalse(validity.canSelect(item(0)))
        XCTAssertTrue(validity.canSelect(item(0, family: "unrelated")))
    }
    func testEVDF17PersonalSource() {
        let values = (0..<20).map { id -> NFEditorialObservation in var o = observation(id, lane: .personalStudy); o.sourceOrSetID = "private-source"; return o }
        let s = state(values); XCTAssertEqual(s.personalStudyObservationIDs.count, 20)
        XCTAssertTrue(s.independentObservationIDs.isEmpty); XCTAssertTrue(s.calibration.isEmpty); XCTAssertTrue(s.retention.isEmpty)
    }
    func testEVDF18LegacyCannotBecomeBandEvidence() {
        let o = NFEditorialObservation(id: "legacy", sessionID: "legacy", sessionOrdinal: 0, eventOrder: 0,
            canonicalDayOrdinal: 100, canonicalDayKey: "day.100", dayPolicyVersion: "v1", occurredAt: .distantPast,
            item: nil, lane: .practice, outcome: .scored, originalResponse: "0.9 legacy difficulty", credit: 1, isFullCredit: true, isZeroCredit: false)
        XCTAssertEqual(state([o]).legacyObservationIDs, ["legacy"]); XCTAssertTrue(state([o]).summaries.isEmpty)
    }
    func testEVDF19ReplayCompleteStateEquality() throws {
        let history = (0..<12).map { id -> NFEditorialObservation in var o = observation(id, credit: id % 3 == 0 ? 0.5 : 1); o.retentionScopeID = "relation"; return o }
        let saved = try JSONEncoder().encode(history)
        let reloaded = try JSONDecoder().decode([NFEditorialObservation].self, from: saved)
        XCTAssertEqual(state(history), state(reloaded.reversed()))
    }
    func testEVDF20UnobservedStrategyRemainsUnknown() {
        let o = observation(0); XCTAssertNil(o.strategyIDObserved); XCTAssertNil(o.strategyCriterionSatisfied)
    }
    func testSCH01ProtectedLeakageRejected() {
        var o = observation(0, lane: .protectedCheck); o.dimensionID = "mentalArithmetic"
        o.formProtocolVersion = NFEditorialProtectedPolicy.protocolVersion; o.rootFormID = "form"
        XCTAssertTrue(state([o]).independentObservationIDs.isEmpty)
        o.protectedLeakageReviewPassed = true
        XCTAssertEqual(state([o]).independentObservationIDs, [o.id])
        o.protectedPreviouslyExposed = true
        XCTAssertTrue(state([o]).independentObservationIDs.isEmpty)
    }
    func testSCH02SittingBudgetAndSCH03NoAutowrong() {
        var form = protectedForm(); form.sittingActiveSeconds = 300
        XCTAssertEqual(NFEditorialProtectedPolicy.stopReason(form: form, effective: [], nextItemEstimate: 20, hasValidPool: true), .saveForLater)
        XCTAssertTrue(form.observedIDs.isEmpty); XCTAssertEqual(form.formID, "form")
    }
    func testSCH04CoverageCapAndLinkedSupplement() {
        var form = protectedForm(); form.presentedSemanticIDs = Set((0..<16).map { "presented.\($0)" })
        let seven = (0..<7).map { observation($0) }
        XCTAssertEqual(NFEditorialProtectedPolicy.stopReason(form: form, effective: seven, nextItemEstimate: 20, hasValidPool: true), .coverageIncomplete)
        let supplement = NFEditorialProtectedPolicy.acceptingSupplement(of: form)!
        XCTAssertEqual(supplement.rootFormID, form.rootFormID); XCTAssertNotEqual(supplement.formID, form.formID)
        XCTAssertEqual(supplement, NFEditorialProtectedPolicy.acceptingSupplement(of: form))
        XCTAssertTrue(supplement.presentedSemanticIDs.isEmpty)
    }
    func testProtectedPresentationCapIncludesUnansweredSlotsAndReplayIsIdempotent() {
        var form = protectedForm()
        for index in 0..<16 {
            form = NFEditorialProtectedPolicy.presenting(slotID: "slot.\(index)", semanticID: "same-disclosed-problem", in: form)
        }
        let replayed = NFEditorialProtectedPolicy.presenting(slotID: "slot.15", semanticID: "same-disclosed-problem", in: form)
        XCTAssertEqual(replayed, form)
        XCTAssertEqual(form.presentedSlotIDs?.count, 16)
        XCTAssertEqual(NFEditorialProtectedPolicy.stopReason(form: form, effective: [], nextItemEstimate: 10, hasValidPool: true), .coverageIncomplete)
    }
    func testProtectedRecommendationsUseCorrectedEffectiveFlagsWithoutChangingOriginals() {
        let form = protectedForm()
        let original = (0..<2).map { index -> NFEditorialObservation in
            var o = observation(index, band: .b2, lane: .protectedCheck)
            o.rootFormID = form.rootFormID
            o.formProtocolVersion = form.protocolVersion
            o.dimensionID = form.dimensionID
            o.protectedLeakageReviewPassed = true
            return o
        }
        var validity = NFEditorialValidityProjection()
        validity.correctedScoreByObservationID[original[0].id] = .init(credit: 0.5, isFullCredit: false, isZeroCredit: false,
            correctionID: "criterion-correction.v1", explanation: "A criterion was previously overcredited.")
        let projection = state(original, validity: validity)
        let effective = NFEditorialProtectedPolicy.effectiveObservations(form: form, history: original,
            evidence: projection, validity: validity)
        XCTAssertEqual(effective.count, 2)
        XCTAssertNil(NFEditorialProtectedPolicy.startingRecommendation(effective))
        XCTAssertTrue(original.allSatisfy(\.isFullCredit))
    }
    private func protectedForm() -> NFEditorialProtectedForm {
        .init(rootFormID: "form", formID: "form", protocolVersion: NFEditorialProtectedPolicy.protocolVersion,
              catalogVersion: "QA.Catalog.v1", dimensionID: "mentalArithmetic", requiredFormatIDs: ["numeric", "choice"], supplementOrdinal: 0)
    }
    func testSCH08IntervalAdvanceAndSCH09EarlyRepeat() {
        var first = observation(0, day: 100); first.retentionScopeID = "relation"
        var early = observation(1, day: 100, lane: .retention); early.retentionScopeID = "relation"
        var due = observation(2, day: 101, lane: .retention); due.retentionScopeID = "relation"
        XCTAssertEqual(state([first], day: 100).retention[0].dueDayOrdinal, 101)
        XCTAssertEqual(state([first, early], day: 100).retention[0].rung, 0)
        let s = state([first, early, due], day: 101).retention[0]
        XCTAssertEqual(s.rung, 1); XCTAssertEqual(s.dueDayOrdinal, 104); XCTAssertEqual(s.status, .retained)
    }
    func testSCH10FailureWaitsForIndependentRepairAndSCH11RepairLoop() {
        var wrong = observation(0, credit: 0, day: 100); wrong.retentionScopeID = "relation"
        var repair = observation(1, day: 100); repair.retentionScopeID = "relation"; repair.isIndependentRepair = true
        let needs = state([wrong], day: 100).retention[0]
        XCTAssertEqual(needs.status, .needsExplanation); XCTAssertNil(needs.dueDayOrdinal)
        XCTAssertEqual(NFEditorialRetentionPolicy.openingExplanation(needs, hasFreshSibling: true).status, .readyForRepair)
        let repaired = state([wrong, repair], day: 100).retention[0]
        XCTAssertEqual(repaired.status, .dueForDelayedCheck); XCTAssertEqual(repaired.dueDayOrdinal, 101)
        var due = observation(2, day: 101, lane: .retention); due.retentionScopeID = "relation"
        XCTAssertEqual(state([wrong, repair, due], day: 101).retention[0].status, .retained)
        repair.helpBeforeLock = true
        XCTAssertNil(state([wrong, repair], day: 100).retention[0].dueDayOrdinal)
    }
    func testSCH12ReviewBudget() {
        let entries = (0..<40).map { id -> NFEditorialRetentionEntry in
            var e = NFEditorialRetentionEntry(id: "e.\(id)", objectiveID: "O.mul", familyID: "F.mul", band: .b1,
                scopeID: "s", originalAttemptID: "o.\(id)", missingCriterionIDs: []); e.dueDayOrdinal = 100; return e
        }
        let selected = NFEditorialRetentionPolicy.dueEntries(entries, day: 101, sessionSeconds: 300,
            expectedSecondsByEntryID: Dictionary(uniqueKeysWithValues: entries.map { ($0.id, 25.0) }))
        XCTAssertEqual(selected.count, 3); XCTAssertEqual(entries.count, 40)
    }
    func testSCH13OneMinuteReflection() {
        XCTAssertEqual(NFEditorialWorkloadPolicy.countFitting(estimatedSeconds: [20, 20, 20], remainingSeconds: 60, mode: .reflection), 1)
        XCTAssertEqual(NFEditorialWorkloadPolicy.countFitting(estimatedSeconds: [61], remainingSeconds: 60, mode: .practice), 0)
    }
    func testSCH14And15MixedFamilyBalance() {
        var control = NFEditorialPracticePolicy.initialControl(sessionID: "mixed", objectiveID: "O.mul", familyID: "F.mul").0
        var context = NFEditorialSelectionContext(catalogVersion: "QA.Catalog.v1", profilePseudonymousID: "p", remainingSittingSeconds: 500, mixedPractice: true)
        let pool = ["a", "b", "c", "d"].flatMap { family in
            (0..<(family == "a" ? 990 : 12)).map { id in NFEditorialSelectionCandidate(id: "\(family).\(id)", item: item(id, family: family)) }
        }
        for _ in 0..<10 {
            let next = NFEditorialPracticePolicy.selectNext(control: control, observation: nil, history: [], evidence: state([]), candidates: pool.reversed(), context: context)
            let chosen = next.candidate!
            context.recentFamilyIDs.append(chosen.item.familyID); context.recentStructureIDs.append(chosen.item.structureID)
            control = next.control
        }
        XCTAssertEqual(Set(context.recentFamilyIDs).count, 4)
        for start in 0..<8 { XCTAssertGreaterThan(Set(context.recentFamilyIDs[start..<(start + 3)]).count, 1) }
    }
    func testSCH18SaveFailureDoesNotComplete() {
        let completion = NFEditorialBlockCompletion(blockID: "original", validAnsweredItemCount: 2,
            reason: .persistenceIssue, checkpointCommitted: false)
        XCTAssertFalse(completion.participationCompleted); XCTAssertFalse(completion.promisedWorkCompleted)
    }
    func testScorePayloadFailsClosedAndWindowBoundaries() {
        var malformed = observation(0); malformed.credit = .nan
        XCTAssertEqual(state([malformed]).exclusions[malformed.id], "invalidScorePayload")
        var contradictory = observation(1); contradictory.credit = 0.5
        XCTAssertEqual(state([contradictory]).exclusions[contradictory.id], "invalidScorePayload")
        let old = observation(0, day: 40), edge = observation(1, day: 41), future = observation(2, day: 101)
        let s = state([old, edge, future], day: 100)
        XCTAssertEqual(s.summaries[0].count, 1); XCTAssertEqual(s.exclusions[future.id], "futureObservation")
    }
    func testADPF02TimingConditionDoesNotAlterFrozenDemand() throws {
        var o = observation(0, band: .b2)
        let frozen = o.item
        o.conditions.timingMode = .elapsedOnly
        XCTAssertEqual(o.item?.editorialBand, .b2)
        o.conditions.timingMode = .untimed
        XCTAssertEqual(o.item, frozen)
        XCTAssertEqual(o.originalResponse, "authored response 0")
    }
    func testADPF15SkipsAreNotZeroCredit() throws {
        let original = observation(0, band: .b2)
        var data = try JSONSerialization.jsonObject(with: JSONEncoder().encode(original)) as! [String: Any]
        data["outcome"] = "skipped"
        let skipped = try JSONDecoder().decode(NFEditorialObservation.self, from: JSONSerialization.data(withJSONObject: data))
        XCTAssertTrue(state([skipped]).independentObservationIDs.isEmpty)
        XCTAssertEqual(state([skipped]).exclusions[skipped.id], "skipped")
    }
    func testADPF19SelectedPathSurvivesCodableResume() throws {
        let selected = selection([1, 0, 1]).control
        let restored = try JSONDecoder().decode(NFEditorialPracticeControl.self, from: JSONEncoder().encode(selected))
        XCTAssertEqual(restored, selected)
        XCTAssertEqual(Set(restored.selectedExercisePath.map(\.semanticFingerprint)).count, restored.selectedExercisePath.count)
        let context = NFEditorialSelectionContext(catalogVersion: "QA.Catalog.v1", profilePseudonymousID: "profile.fixed", remainingSittingSeconds: 500)
        let pool = (0..<12).map { NFEditorialSelectionCandidate(id: "candidate.B1.\($0)", item: item(100 + $0)) }
        let next = NFEditorialPracticePolicy.selectNext(control: restored, observation: nil, history: [], evidence: state([]), candidates: pool, context: context)
        XCTAssertFalse(restored.selectedExercisePath.contains { $0.semanticFingerprint == next.candidate?.item.semanticFingerprint })
    }
    func testEVDF09EquivalentResponsesHaveIdenticalEvidence() throws {
        let o = observation(0, credit: 0.5)
        var data = try JSONSerialization.jsonObject(with: JSONEncoder().encode(o)) as! [String: Any]
        data["originalResponse"] = "equivalent reviewed response"
        let equivalent = try JSONDecoder().decode(NFEditorialObservation.self, from: JSONSerialization.data(withJSONObject: data))
        XCTAssertEqual(state([o]), state([equivalent]))
    }
    func testSCH06AccessibleEquivalentHasNoAbilityPenaltyAndSCH07MissingForm() {
        let baseline = observation(0)
        var accessible = baseline; accessible.conditions.accommodationFacts = ["screen-reader"]
        XCTAssertEqual(state([baseline]).summaries, state([accessible]).summaries)
        var candidate = NFEditorialSelectionCandidate(id: "unavailable", item: item(1))
        candidate.accessibilityCompatible = false
        let c = NFEditorialPracticePolicy.initialControl(sessionID: "s", objectiveID: "O.mul", familyID: "F.mul").0
        let result = NFEditorialPracticePolicy.selectNext(control: c, observation: nil, history: [], evidence: state([]), candidates: [candidate],
            context: .init(catalogVersion: "QA.Catalog.v1", profilePseudonymousID: "p", remainingSittingSeconds: 500))
        XCTAssertNil(result.candidate); XCTAssertEqual(result.reason, .noCompatibleContent)
    }
    func testHistoricalPracticeRemainsVisibleWithoutManufacturingBandEvidence() {
        let values = (0..<3).map { id in NFHistoricalPracticeInput(id: "old.\(id)", labID: "math", originalCredit: id == 0 ? 0.5 : 1,
            submittedAt: Date(timeIntervalSince1970: Double(id)), responseFormatRaw: "numeric", sourceOrSetID: nil,
            isPersonalStudy: false, wasSkipped: false, editorialObservation: nil) }
        let result = NFHistoricalPracticeProjection.reduce(values)[0]
        XCTAssertEqual(result.legacyCount, 3); XCTAssertEqual(result.legacyMeanCredit!, 2.5 / 3, accuracy: 1e-12)
        XCTAssertTrue(result.editorialAttemptIDs.isEmpty)
    }
    func testHistoricalSelfCheckDispositionIsIdempotentAndPreservesOriginal() {
        let input = NFHistoricalPracticeInput(id: "old.selfcheck", labID: "retrieval", originalCredit: 1,
            submittedAt: .distantPast, responseFormatRaw: "selfCheck", sourceOrSetID: nil,
            isPersonalStudy: false, wasSkipped: false, editorialObservation: nil)
        XCTAssertEqual(NFHistoricalPracticeProjection.classify(input), .personalStudy)
        let disposition = NFHistoricalPracticeDispositionRecord(id: "d.1", attemptID: input.id, revision: 1,
            policyVersion: NFHistoricalPracticeProjection.policyVersion, occurredAt: .distantPast,
            disposition: .personalStudy, reason: "Legacy matched rating is self-report.", correctedDerivedCredit: nil,
            supersedesDispositionID: nil)
        let result = NFHistoricalPracticeProjection.reduce([input, input], dispositions: [disposition, disposition])[0]
        XCTAssertEqual(result.personalStudyAttemptIDs, [input.id]); XCTAssertEqual(result.appliedDispositionIDs, [disposition.id])
        XCTAssertEqual(input.originalCredit, 1); XCTAssertNil(result.legacyMeanCredit)
    }
    func testHistoricalSolutionRevealIsDistinctFromSkipAndCannotBecomeAccuracy() {
        let input = NFHistoricalPracticeInput(id: "revealed.1", labID: "math", originalCredit: 0,
            submittedAt: Date(timeIntervalSince1970: 100), responseFormatRaw: "revealed", sourceOrSetID: nil,
            isPersonalStudy: false, wasSkipped: true, editorialObservation: nil)
        XCTAssertEqual(NFHistoricalPracticeProjection.classify(input), .excludedRevealed)
        let history = NFHistoricalPracticeProjection.reduce([input])
        XCTAssertEqual(history.first?.legacyCount, 0)
        XCTAssertNil(history.first?.legacyMeanCredit)
        XCTAssertEqual(history.first?.excludedAttemptIDs, [input.id])
    }
    func testHistoricalCorrectionIsAppendOnlyAndRequiresValidSupersessionChain() {
        let input = NFHistoricalPracticeInput(id: "old", labID: "math", originalCredit: 0,
            submittedAt: .distantPast, responseFormatRaw: "numeric", sourceOrSetID: nil,
            isPersonalStudy: false, wasSkipped: false, editorialObservation: nil)
        let first = NFHistoricalPracticeDispositionRecord(id: "d.1", attemptID: input.id, revision: 1,
            policyVersion: NFHistoricalPracticeProjection.policyVersion, occurredAt: .distantPast,
            disposition: .excludedContentCorrection, reason: "Faulty answer contract.", correctedDerivedCredit: nil, supersedesDispositionID: nil)
        let second = NFHistoricalPracticeDispositionRecord(id: "d.2", attemptID: input.id, revision: 2,
            policyVersion: NFHistoricalPracticeProjection.policyVersion, occurredAt: .distantPast,
            disposition: .legacyPracticeHistory, reason: "Reviewed equivalent earns full credit.", correctedDerivedCredit: 1, supersedesDispositionID: first.id)
        XCTAssertEqual(NFHistoricalPracticeProjection.reduce([input], dispositions: [second, first])[0].legacyMeanCredit, 1)
        XCTAssertEqual(input.originalCredit, 0)
        XCTAssertEqual(NFHistoricalPracticeProjection.reduce([input], dispositions: [second])[0].legacyMeanCredit, 0)
    }

}


extension EditorialBandEvidenceTests {
    func testControllerBoundaryDoesNotReuseAnOldStreakAfterSkipOrDuplicateEvent() throws {
        let history = (0..<4).map { replacingSession(observation($0, day: 100), id: "QA.current", ordinal: $0) }
        var control = NFEditorialPracticePolicy.initialControl(sessionID: "QA.current", objectiveID: "O.mul", familyID: "F.mul").0
        control.currentBandDecisionResponseIDs = history.map(\.id)
        control.eligibleResponsesSinceLastAutomaticChange = 4
        control.processedObservationIDs = history.map(\.id)
        let pool = (0..<8).flatMap { id in [NFEditorialSelectionCandidate(id: "b1.\(id)", item: item(100 + id)),
            NFEditorialSelectionCandidate(id: "b2.\(id)", item: item(100 + id, band: .b2))] }
        let context = NFEditorialSelectionContext(catalogVersion: "QA.Catalog.v1", profilePseudonymousID: "p", remainingSittingSeconds: 500)
        let skippedBoundary = NFEditorialPracticePolicy.selectNext(control: control, observation: nil,
            history: history, evidence: state(history), candidates: pool, context: context)
        XCTAssertEqual(skippedBoundary.control.currentTargetBand, .b1)
        let duplicate = NFEditorialPracticePolicy.selectNext(control: control, observation: history.last,
            history: history, evidence: state(history), candidates: pool, context: context)
        XCTAssertEqual(duplicate.control.currentTargetBand, .b1)
        XCTAssertEqual(duplicate.control.eligibleResponsesSinceLastAutomaticChange, 4)
    }

    func testControllerSupportEventsAreIdempotentAndCorrectionsRefreshCurrentCounters() throws {
        var assisted = replacingSession(observation(0, day: 100), id: "QA.current", ordinal: 0)
        assisted.helpBeforeLock = true
        let control = NFEditorialPracticePolicy.initialControl(sessionID: "QA.current", objectiveID: "O.mul", familyID: "F.mul").0
        let pool = (0..<8).map { NFEditorialSelectionCandidate(id: "c.\($0)", item: item(100 + $0)) }
        let context = NFEditorialSelectionContext(catalogVersion: "QA.Catalog.v1", profilePseudonymousID: "p", remainingSittingSeconds: 500)
        let first = NFEditorialPracticePolicy.selectNext(control: control, observation: assisted,
            history: [assisted], evidence: state([assisted]), candidates: pool, context: context)
        let replay = NFEditorialPracticePolicy.selectNext(control: first.control, observation: assisted,
            history: [assisted], evidence: state([assisted]), candidates: pool, context: context)
        XCTAssertEqual(replay.control.presentedSupportEvents, [true])
        XCTAssertFalse(replay.control.shouldOfferSupport)
        var invalidated = replay.control
        invalidated.currentBandDecisionResponseIDs = ["no-longer-independent"]
        invalidated.eligibleResponsesSinceLastAutomaticChange = 9
        let refreshed = NFEditorialPracticePolicy.selectNext(control: invalidated, observation: nil,
            history: [assisted], evidence: state([assisted]), candidates: pool, context: context)
        XCTAssertTrue(refreshed.control.currentBandDecisionResponseIDs.isEmpty)
        XCTAssertEqual(refreshed.control.eligibleResponsesSinceLastAutomaticChange, 0)
    }
}

extension EditorialBandEvidenceTests {
    private func initialTarget(_ values: [NFEditorialObservation], day: Int = 105,
                               explicitBand: NFEditorialBand? = nil,
                               compatible: [NFEditorialObservation]? = nil,
                               validity: NFEditorialValidityProjection = .init()) throws -> NFEditorialInitialTargetDecision {
        let pin = NFEditorialSessionPin(catalogVersion: "QA.Catalog.v1", objectiveID: "O.mul", familyID: "F.mul",
            initialUserBand: explicitBand, catalogDigest: String(repeating: "a", count: 64))
        let contracts = (compatible ?? values).compactMap { value -> NFEditorialInitialTargetContract? in
            guard let group = EditorialBandEvidenceV1.group(for: value) else { return nil }
            return .init(bankQuestionID: value.id, group: .init(lane: group.lane, objectiveID: group.objectiveID,
                familyID: group.familyID, band: group.band, bandContractVersion: group.bandContractVersion,
                scoringComparabilityID: group.scoringComparabilityID, stimulusComparabilityID: group.stimulusComparabilityID,
                toolConditionID: group.toolConditionID, localeComparabilityID: group.localeComparabilityID,
                pacingConditionID: NFEditorialTimingMode.untimed.rawValue, protocolScope: group.protocolScope))
        }
        let captured = NFEditorialCapturedDay(policyVersion: "CanonicalTrainingDayV1", calendarIdentifier: "gregorian",
            timeZoneIdentifier: "UTC", utcOffsetSeconds: 0, dayBoundaryHour: 4,
            boundaryStart: Date(timeIntervalSince1970: Double(day) * 86_400),
            nextBoundary: Date(timeIntervalSince1970: Double(day + 1) * 86_400), ordinal: day, key: "QA.day.\(day)")
        return try NFEditorialInitialTargetPolicy.select(pin: pin,
            input: .init(observations: values, validity: validity, day: captured), contracts: contracts)
    }

    func testDemonstratedInitialTargetWinsOverLaterEasierPracticeSuccess() throws {
        let demonstrated = (0..<8).map { observation($0, band: .b3) }
        let lower = observation(8, day: 104, band: .b1)
        let selected = try initialTarget(demonstrated + [lower])
        XCTAssertEqual(selected.band, .b3); XCTAssertEqual(selected.basis, .demonstratedPractice)
        XCTAssertEqual(selected.reason, .recentPracticeTarget)
        XCTAssertEqual(Set(selected.supportingObservationIDs), Set(demonstrated.map(\.id)))
        XCTAssertTrue(selected.isSupported)
        XCTAssertEqual(try initialTarget(demonstrated + [lower], explicitBand: .b2).basis, .userPreference)
        XCTAssertEqual(try initialTarget(demonstrated + [lower], explicitBand: .b2).band, .b2)
    }

    func testInitialTargetUsesRecentSuccessOnlyWhenDemonstrationCoverageIsInsufficient() throws {
        let partial = (0..<7).map { observation($0, band: .b3) }
        let lower = observation(8, day: 104, band: .b1)
        let result = try initialTarget(partial + [lower])
        XCTAssertEqual(result.band, .b1); XCTAssertEqual(result.basis, .recentSuccess)
        XCTAssertEqual(result.supportingObservationIDs, [lower.id]); XCTAssertNil(result.lastDemonstratedAt)
        XCTAssertEqual(try initialTarget([]).reason, .coldStartDefault)
    }

    func testInitialTargetRefreshRetainsHistoricalDemonstrationWithoutInventingRecentCoverage() throws {
        let demonstrated = (0..<8).map { observation($0, band: .b3) }
        let selected = try initialTarget(demonstrated, day: 180)
        XCTAssertEqual(selected.band, .b3); XCTAssertEqual(selected.reason, .refreshProbe)
        XCTAssertEqual(selected.basis, .demonstratedPractice)
        XCTAssertEqual(selected.supportingObservationIDs.count, 8)
        XCTAssertEqual(selected.lastDemonstratedAt, demonstrated.last?.occurredAt)
        XCTAssertEqual(state(demonstrated, day: 180).summaries.first?.coverage, .needsRefresh)
        XCTAssertEqual(try initialTarget(demonstrated, day: 130).reason, .recentPracticeTarget)
        XCTAssertEqual(try initialTarget(demonstrated, day: 131).reason, .refreshProbe)
        let recentEasier = observation(8, day: 179, band: .b1)
        let stillNeedsProbe = try initialTarget(demonstrated + [recentEasier], day: 180)
        XCTAssertEqual(stillNeedsProbe.band, .b3); XCTAssertEqual(stillNeedsProbe.reason, .refreshProbe)
        XCTAssertEqual(stillNeedsProbe.lastRelevantPracticeDay, 101,
            "Recent easier practice cannot describe a stale higher band's demonstration as recent")
    }

    func testInitialTargetSeparatesIncompatibleLocaleContractAndProtectedGroups() throws {
        let demonstrated = (0..<8).map { observation($0, band: .b3) }
        var newLocale = demonstrated
        for i in newLocale.indices { newLocale[i].conditions.contentLocale = "ja" }
        XCTAssertEqual(try initialTarget(demonstrated, compatible: newLocale).reason, .coldStartDefault)
        let changedContract = try demonstrated.map { value -> NFEditorialObservation in
            var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(value)) as? [String: Any])
            var item = try XCTUnwrap(object["item"] as? [String: Any]); item["bandContractVersion"] = "QA.incompatible.v2"
            object["item"] = item
            return try JSONDecoder().decode(NFEditorialObservation.self, from: JSONSerialization.data(withJSONObject: object))
        }
        XCTAssertEqual(try initialTarget(demonstrated, compatible: changedContract).reason, .coldStartDefault)
        let protected = (0..<8).map { observation($0, band: .b3, lane: .protectedCheck) }
        XCTAssertEqual(try initialTarget(protected, compatible: demonstrated).reason, .coldStartDefault)
    }

    func testInitialTargetDoesNotPoolFourTimedAndFourUntimedOrReuseExcludedDemonstration() throws {
        var mixedPacing = (0..<8).map { observation($0, band: .b3) }
        for i in 4..<8 { mixedPacing[i].conditions.timingMode = .elapsedOnly }
        XCTAssertEqual(try initialTarget(mixedPacing).basis, .recentSuccess)
        let demonstrated = (0..<8).map { observation($0, band: .b3) }
        let lower = observation(8, day: 104, band: .b1)
        var validity = NFEditorialValidityProjection()
        validity.dispositionByObservationID[demonstrated[0].id] = .quarantined
        let excluded = try initialTarget(demonstrated + [lower], validity: validity)
        XCTAssertEqual(excluded.band, .b1); XCTAssertEqual(excluded.basis, .recentSuccess)
        XCTAssertFalse(excluded.supportingObservationIDs.contains(demonstrated[0].id))
    }
}


extension EditorialBandEvidenceTests {
    func testDemonstratedInitialProofFollowsEventOrderAcrossClockRollbackAndEqualTimestamps() throws {
        let demonstrated = (0..<8).map { observation($0, band: .b3) }
        func atWallTime(_ value: NFEditorialObservation, _ date: Date) throws -> NFEditorialObservation {
            var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(value)) as? [String: Any])
            object["occurredAt"] = date.timeIntervalSinceReferenceDate
            return try JSONDecoder().decode(NFEditorialObservation.self, from: JSONSerialization.data(withJSONObject: object))
        }
        // Later committed success on the second day has an earlier wall clock
        // than the four already committed successes on that same training day.
        let rolledBack = try atWallTime(observation(8, day: 101, band: .b3),
            Date(timeIntervalSince1970: 101 * 86_400 + 3))
        let rollback = try initialTarget(demonstrated + [rolledBack])
        XCTAssertEqual(rollback.basis, .demonstratedPractice); XCTAssertEqual(rollback.band, .b3)
        XCTAssertEqual(Set(rollback.supportingObservationIDs), Set((1...8).map { "o.\($0)" }))
        XCTAssertEqual(rollback.lastDemonstratedAt, rolledBack.occurredAt)
        // Tied wall times include a later nonsupporting prefix. The retained
        // proof must stop at the last qualifying event, not include every tie.
        let tiedDate = Date(timeIntervalSince1970: 101 * 86_400 + 20)
        var tied = try demonstrated.map { try atWallTime($0, $0.canonicalDayOrdinal == 101 ? tiedDate : $0.occurredAt) }
        tied.append(try atWallTime(observation(8, credit: 0, day: 101, band: .b3), tiedDate))
        tied.append(try atWallTime(observation(9, credit: 0, day: 101, band: .b3), tiedDate))
        let selected = try initialTarget(tied)
        XCTAssertEqual(selected.basis, .demonstratedPractice); XCTAssertEqual(selected.band, .b3)
        XCTAssertEqual(Set(selected.supportingObservationIDs), Set((1...8).map { "o.\($0)" }))
        XCTAssertFalse(selected.supportingObservationIDs.contains("o.9"))
        XCTAssertEqual(selected.lastDemonstratedAt, tiedDate)
    }
}

extension EditorialBandEvidenceTests {
    private func criterionObservation(_ id: Int, credit: Double = 0, structure: String = "QA.same-structure",
                                      day: Int = 100, band: NFEditorialBand = .b1,
                                      lane: NFEditorialEvidenceLane = .practice) -> NFEditorialObservation {
        var value = observation(id, credit: credit, day: day, band: band, structure: structure, lane: lane)
        value.conditions.stimulusResponseFormatID = "numeric"
        value.rubricCriterionCredits = ["response": credit]
        value.missingCriterionIDs = credit == 1 ? [] : ["response"]
        return value
    }
    private func criterionPreference(_ values: [NFEditorialObservation], contractFrom original: NFEditorialObservation,
                                     day: Int = 105, validity: NFEditorialValidityProjection = .init()) throws -> NFEditorialCriterionSelection {
        let contract = NFEditorialCriterionSelection(policyVersion: NFEditorialCriterionRankingPolicy.version,
            candidateID: "QA.fresh-sibling", exerciseDigest: String(repeating: "a", count: 64),
            group: try XCTUnwrap(EditorialBandEvidenceV1.group(for: original)), structureID: try XCTUnwrap(original.item?.structureID),
            criterionIDs: ["response"])
        return try XCTUnwrap(NFEditorialCriterionRankingPolicy.project(contracts: [contract.candidateID: contract], observations: values,
            evidence: state(values, day: day, validity: validity), validity: validity)[contract.candidateID])
    }

    func testObservedCriterionPreferenceNeedsTwoDistinctMissesAndFullSuccessResetsIt() throws {
        let first = criterionObservation(0), second = criterionObservation(1)
        XCTAssertEqual(try criterionPreference([first], contractFrom: first).preference, 0)
        let repeated = try criterionPreference([first, second], contractFrom: first)
        XCTAssertEqual(repeated.preference, 1)
        XCTAssertEqual(repeated.matches, [.init(criterionID: "response", observationIDs: [first.id, second.id])])
        XCTAssertEqual(try criterionPreference([first, second, criterionObservation(2, credit: 1), criterionObservation(3)], contractFrom: first).preference, 0)
        XCTAssertEqual(try criterionPreference([first, second, criterionObservation(2, credit: 1), criterionObservation(3), criterionObservation(4)], contractFrom: first).preference, 1)
        var duplicate = criterionObservation(1, day: 131)
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(duplicate)) as? [String: Any])
        var demand = try XCTUnwrap(json["item"] as? [String: Any]); demand["semanticFingerprint"] = try XCTUnwrap(first.item?.semanticFingerprint)
        json["item"] = demand
        duplicate = try JSONDecoder().decode(NFEditorialObservation.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertEqual(try criterionPreference([first, duplicate], contractFrom: first, day: 140).preference, 0)
    }

    func testObservedCriterionPreferenceExcludesDifferentStructureConditionsHelpProtectionAndCorrections() throws {
        let first = criterionObservation(0)
        var variants: [(String, NFEditorialObservation)] = [
            ("structure", criterionObservation(1, structure: "QA.other-structure")),
            ("band", criterionObservation(1, band: .b2)),
            ("personal", criterionObservation(1, lane: .personalStudy)),
            ("protected", criterionObservation(1, lane: .protectedCheck))]
        var helped = criterionObservation(1); helped.helpBeforeLock = true; variants.append(("help", helped))
        var revealed = criterionObservation(1); revealed.answerPreviouslyRevealed = true; variants.append(("reveal", revealed))
        var timed = criterionObservation(1); timed.conditions.timingMode = .timedFluency; variants.append(("timing", timed))
        var locale = criterionObservation(1); locale.conditions.contentLocale = "ja"; variants.append(("locale", locale))
        var tool = criterionObservation(1); tool.conditions.toolConditionID = "different-tool"; variants.append(("tool", tool))
        func withComparability(_ original: NFEditorialObservation, _ identifier: String?) throws -> NFEditorialObservation {
            var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(original)) as? [String: Any])
            var demand = try XCTUnwrap(json["item"] as? [String: Any])
            demand["stimulusComparabilityID"] = identifier
            json["item"] = demand
            return try JSONDecoder().decode(NFEditorialObservation.self, from: JSONSerialization.data(withJSONObject: json))
        }
        var incompatibleFormat = try withComparability(criterionObservation(1), "QA.different-reviewed-response-group.v1")
        incompatibleFormat.conditions.stimulusResponseFormatID = "choice"
        variants.append(("different reviewed response group", incompatibleFormat))
        var fabricatedCriterion = criterionObservation(1); fabricatedCriterion.missingCriterionIDs = ["invented"]
        variants.append(("unscored criterion", fabricatedCriterion))
        for (label, changed) in variants {
            XCTAssertEqual(try criterionPreference([first, changed], contractFrom: first).preference, 0, label)
        }
        // EVD-002 lets an explicit reviewed comparability group span substantive
        // formats. The same structure and actual neutral response component still
        // apply; changing the renderer alone cannot override that reviewed group.
        var reviewedChoice = criterionObservation(1)
        reviewedChoice.conditions.stimulusResponseFormatID = "choice"
        XCTAssertEqual(try criterionPreference([first, reviewedChoice], contractFrom: first).preference, 1)
        let exactNumeric = try withComparability(first, nil), exactChoice = try withComparability(reviewedChoice, nil)
        XCTAssertEqual(try criterionPreference([exactNumeric, exactChoice], contractFrom: exactNumeric).preference, 0)
        var exactNumericSibling = exactChoice
        exactNumericSibling.conditions.stimulusResponseFormatID = "numeric"
        XCTAssertEqual(try criterionPreference([exactNumeric, exactNumericSibling], contractFrom: exactNumeric).preference, 1)
        let second = criterionObservation(1)
        var validity = NFEditorialValidityProjection()
        validity.dispositionByObservationID[first.id] = .quarantined
        XCTAssertEqual(try criterionPreference([first, second], contractFrom: first, validity: validity).preference, 0)
        validity = .init()
        validity.correctedScoreByObservationID[second.id] = .init(credit: 1, isFullCredit: true, isZeroCredit: false,
            correctionID: "QA.scalar-only", explanation: "No component-level correction is authorized")
        XCTAssertEqual(try criterionPreference([first, second], contractFrom: first, validity: validity).preference, 0)
        var conflict = second
        conflict.credit = 0.5; conflict.isZeroCredit = false
        XCTAssertEqual(try criterionPreference([first, second, conflict], contractFrom: first).preference, 0)
    }

    func testObservedCriterionPreferenceUsesRecentWindowAndCannotChangeStaircaseOrDuePriority() throws {
        let first = criterionObservation(0), second = criterionObservation(1)
        XCTAssertEqual(try criterionPreference([first, second], contractFrom: first, day: 160).preference, 0)
        let later = (2..<22).map { criterionObservation($0, credit: 1, structure: "QA.another-structure", day: 101) }
        XCTAssertEqual(try criterionPreference([first, second] + later, contractFrom: first).preference, 0)
        let match = try criterionPreference([first, second], contractFrom: first)
        var unavailable = NFEditorialCriterionSelection(policyVersion: NFEditorialCriterionRankingPolicy.version,
            candidateID: "QA.unmapped-contract", exerciseDigest: String(repeating: "b", count: 64),
            group: match.group, structureID: match.structureID, criterionIDs: [], coverageRaw: "unavailable")
        XCTAssertTrue(unavailable.isSupported)
        let unmapped = NFEditorialCriterionRankingPolicy.project(contracts: [unavailable.candidateID: unavailable],
            observations: [first, second], evidence: state([first, second]), validity: .init())
        XCTAssertEqual(unmapped[unavailable.candidateID]?.preference, 0)
        unavailable.matches = match.matches
        XCTAssertFalse(unavailable.isSupported, "An unsupported component map cannot mint a match")
        var preferred = NFEditorialSelectionCandidate(id: "preferred", item: item(100, structure: "QA.same-structure"))
        preferred.observedWeakCriterionMatch = match.preference
        let other = NFEditorialSelectionCandidate(id: "other", item: item(101, structure: "QA.other-structure"))
        let control = NFEditorialPracticePolicy.initialControl(sessionID: "new", objectiveID: "O.mul", familyID: "F.mul").0
        let result = NFEditorialPracticePolicy.selectNext(control: control, observation: nil, history: [first, second],
            evidence: state([first, second]), candidates: [other, preferred],
            context: .init(catalogVersion: "QA", profilePseudonymousID: "QA", remainingSittingSeconds: 500))
        XCTAssertEqual(result.candidate?.id, preferred.id)
        XCTAssertEqual(result.control.currentTargetBand, .b1); XCTAssertEqual(result.control.totalAutomaticChangesThisSession, 0)
        XCTAssertEqual(result.candidate?.dueRepairPriority, 0)
        var invalidPreferred = preferred; invalidPreferred.prerequisitesMet = false
        let safe = NFEditorialPracticePolicy.selectNext(control: control, observation: nil, history: [first, second],
            evidence: state([first, second]), candidates: [invalidPreferred, other],
            context: .init(catalogVersion: "QA", profilePseudonymousID: "QA", remainingSittingSeconds: 500))
        XCTAssertEqual(safe.candidate?.id, other.id)
    }
}


extension EditorialBandEvidenceTests {
    private var reviewedRepairContract: NFEditorialReviewContract {
        .init(scopeID: "QA.scored-response-review.v1", criterionIDs: ["response"],
              siblingStructureIDs: ["QA.same-structure"], allowedRoles: [.delayedCheck, .probe, .repair])
    }
    private func reviewedRepairObservation(_ id: Int, credit: Double, day: Int,
        lane: NFEditorialEvidenceLane = .practice, repair: Bool = false) throws -> NFEditorialObservation {
        let original = criterionObservation(id, credit: credit, day: day, lane: lane)
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(original)) as? [String: Any])
        var item = try XCTUnwrap(json["item"] as? [String: Any])
        item["reviewContract"] = try JSONSerialization.jsonObject(with: JSONEncoder().encode(reviewedRepairContract))
        json["item"] = item
        json["id"] = String(format: "E0110000-0000-0000-0000-%012d", id)
        json["sessionID"] = String(format: "E0120000-0000-0000-0000-%012d", id / 4)
        json["retentionScopeID"] = reviewedRepairContract.scopeID
        json["isIndependentRepair"] = repair
        return try JSONDecoder().decode(NFEditorialObservation.self, from: JSONSerialization.data(withJSONObject: json))
    }
    private func reviewAssignment(_ observations: [NFEditorialObservation], at day: Int = 101,
        explanation: NFEditorialExplanationPresentation? = nil, repairOrigin: String? = nil,
        validity: NFEditorialValidityProjection = .init(), usedCount: Int = 0) throws -> NFEditorialReviewAssignment {
        let first = try XCTUnwrap(observations.first)
        let captured = NFEditorialCapturedDay(policyVersion: "CanonicalTrainingDayV1", calendarIdentifier: "gregorian",
            timeZoneIdentifier: "UTC", utcOffsetSeconds: 0, dayBoundaryHour: 0,
            boundaryStart: Date(timeIntervalSince1970: Double(day * 86_400)),
            nextBoundary: Date(timeIntervalSince1970: Double((day + 1) * 86_400)), ordinal: day, key: "QA.day.\(day)")
        let base = NFEditorialReviewAssignment(policyVersion: NFEditorialReviewSlotPolicy.version,
            candidateID: "QA.unseen-sibling", exerciseDigest: String(repeating: "a", count: 64),
            semanticFingerprint: "QA.new-semantic", contract: reviewedRepairContract,
            group: NFEditorialReviewSlotPolicy.normalizedGroup(try XCTUnwrap(EditorialBandEvidenceV1.group(for: first))),
            role: .probe, decisionDayOrdinal: day, expectedSeconds: 25)
        let input = NFEditorialLiveController.Input(observations: observations, validity: validity, day: captured)
        let selected = try NFEditorialReviewSlotPolicy.project(contracts: [base.candidateID: base], input: input,
            evidence: state(observations, day: day, validity: validity),
            explanations: explanation.map { [$0.attemptID.uuidString: $0] } ?? [:], repairOriginID: repairOrigin,
            intent: nil, budget: .init(totalSeconds: 300, usedSeconds: 0, usedCount: usedCount, explicitReview: false))
        return try XCTUnwrap(selected[base.candidateID])
    }

    func testDeclaredRepairRequiresDisplayedExplanationAndNeverBecomesImmediateRetention() throws {
        let failed = try reviewedRepairObservation(0, credit: 0, day: 100)
        XCTAssertEqual(try reviewAssignment([failed], at: 100, repairOrigin: failed.id).role, .probe)
        let explanation = NFEditorialExplanationPresentation(attemptID: try XCTUnwrap(UUID(uuidString: failed.id)),
            sessionID: try XCTUnwrap(UUID(uuidString: failed.sessionID)), slotID: UUID(), decisionID: "QA.displayed", ownerDeviceID: UUID(),
            exerciseDigest: String(repeating: "a", count: 64), feedbackDigest: String(repeating: "b", count: 64),
            occurredAt: failed.occurredAt.addingTimeInterval(1))
        let repair = try reviewAssignment([failed], at: 100, explanation: explanation, repairOrigin: failed.id)
        XCTAssertEqual(repair.role, .repair); XCTAssertEqual(repair.entry?.status, .readyForRepair)
        XCTAssertEqual(repair.originObservationID, failed.id); XCTAssertEqual(repair.entry?.rung, 0)
        let fixed = try reviewedRepairObservation(1, credit: 1, day: 100, repair: true)
        let repaired = try XCTUnwrap(state([failed, fixed], day: 100).retention.first)
        XCTAssertEqual(repaired.status, .dueForDelayedCheck); XCTAssertEqual(repaired.rung, 0)
        XCTAssertEqual(repaired.dueDayOrdinal, 101); XCTAssertTrue(repaired.missingCriterionIDs.isEmpty)
        XCTAssertEqual(try reviewAssignment([failed, fixed], at: 100).role, .probe)
        XCTAssertEqual(try reviewAssignment([failed, fixed], at: 101).role, .delayedCheck)
    }

    func testDeclaredReviewUsesOnlyCompatibleEffectiveOriginsAndBoundedDueSlots() throws {
        let full = try reviewedRepairObservation(0, credit: 1, day: 100)
        XCTAssertEqual(try reviewAssignment([full], at: 100).role, .probe)
        let delayed = try reviewAssignment([full], at: 101)
        XCTAssertEqual(delayed.role, .delayedCheck); XCTAssertEqual(delayed.originObservationID, full.id)
        XCTAssertEqual(try reviewAssignment([full], at: 101, usedCount: 5).role, .probe)
        var validity = NFEditorialValidityProjection(); validity.dispositionByObservationID[full.id] = .quarantined
        XCTAssertEqual(try reviewAssignment([full], validity: validity).role, .probe)
        validity = .init(); validity.correctedScoreByObservationID[full.id] = .init(credit: 1,
            isFullCredit: true, isZeroCredit: false, correctionID: "QA.scalar-only", explanation: "No corrected criterion authority")
        XCTAssertEqual(try reviewAssignment([full], validity: validity).role, .probe)
        var helped = full; helped.helpBeforeLock = true
        XCTAssertEqual(try reviewAssignment([helped]).role, .probe)
        var unknown = full; unknown.conditions.toolConditionID = nil
        XCTAssertEqual(try reviewAssignment([unknown]).role, .probe)
        let nextDay = try reviewedRepairObservation(1, credit: 1, day: 101, lane: .retention)
        let retained = try XCTUnwrap(state([full, nextDay], day: 101).retention.first)
        XCTAssertEqual(retained.rung, 1); XCTAssertEqual(retained.dueDayOrdinal, 104); XCTAssertEqual(retained.status, .retained)
    }
}

extension EditorialBandEvidenceTests {
    func testDeclaredReviewScopeRevisionCannotInheritAnotherContractRetentionRung() throws {
        let first = try reviewedRepairObservation(0, credit: 1, day: 100)
        let delayed = try reviewedRepairObservation(1, credit: 1, day: 101, lane: .retention)
        let previous = try XCTUnwrap(state([first, delayed], day: 101).retention.first)
        XCTAssertEqual(previous.rung, 1)
        let changed = NFEditorialReviewContract(scopeID: reviewedRepairContract.scopeID, criterionIDs: ["response"],
            siblingStructureIDs: ["QA.other-structure", "QA.same-structure"], allowedRoles: [.probe])
        XCTAssertTrue(changed.isSupported)
        XCTAssertFalse(changed.hasSameScope(as: reviewedRepairContract))
        XCTAssertNotEqual(changed.compatibilityID, reviewedRepairContract.compatibilityID)
        let probe = try reviewedRepairObservation(2, credit: 1, day: 104)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(probe)) as? [String: Any])
        var item = try XCTUnwrap(object["item"] as? [String: Any])
        item["reviewContract"] = try JSONSerialization.jsonObject(with: JSONEncoder().encode(changed))
        object["item"] = item
        let newScope = try JSONDecoder().decode(NFEditorialObservation.self, from: JSONSerialization.data(withJSONObject: object))
        let entries = state([first, delayed, newScope], day: 104).retention
        XCTAssertEqual(entries.count, 2)
        XCTAssertEqual(entries.first { $0.id == previous.id }, previous)
        let newEntry = try XCTUnwrap(entries.first { $0.id != previous.id })
        XCTAssertEqual(newEntry.rung, 0); XCTAssertEqual(newEntry.dueDayOrdinal, 105)
        XCTAssertEqual(newEntry.originalAttemptID, newScope.id)
        let roleOnly = NFEditorialReviewContract(scopeID: reviewedRepairContract.scopeID,
            criterionIDs: reviewedRepairContract.criterionIDs,
            siblingStructureIDs: reviewedRepairContract.siblingStructureIDs, allowedRoles: [.delayedCheck])
        XCTAssertEqual(roleOnly.compatibilityID, reviewedRepairContract.compatibilityID)
        XCTAssertTrue(roleOnly.hasSameScope(as: reviewedRepairContract))
    }
}


extension EditorialBandEvidenceTests {
    private func goalAdmission(_ id: String, goals: [String]?) throws -> NFEditorialAdmissionEntry {
        var raw = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(item(1))) as? [String: Any])
        raw["assistancePolicyID"] = NFEditorialNativeProtocol.toolConditionID
        var demand = try JSONDecoder().decode(NFEditorialDemandRecord.self, from: JSONSerialization.data(withJSONObject: raw))
        demand.goalAlignment = goals.map { .init(objectiveID: demand.objectiveID, goalIDsRaw: $0) }
        return .init(id: id, bankQuestionID: "question.\(id)", exerciseDigest: String(repeating: "a", count: 64),
            scorerVersion: NFExerciseScoringEngine.scoringVersion, lab: .mentalMath, contentLocale: "en", demand: demand)
    }

    func testAuthoredGoalRankingUsesKnownExplicitIntersectionWithoutProficiencyOrDuplicateWeights() throws {
        let goals = [TrainingGoal.mentalMath.rawValue, TrainingGoal.programming.rawValue].sorted()
        let admission = try goalAdmission("mapped", goals: goals)
        let preferences = NFEditorialGoalPreferences(policyVersion: NFEditorialGoalRankingPolicy.preferenceVersion,
            profileID: UUID(), goalIDsRaw: goals)
        let selected = try XCTUnwrap(NFEditorialGoalRankingPolicy.selection(admission: admission, preferences: preferences))
        XCTAssertTrue(selected.isSupported); XCTAssertEqual(selected.preference, 1)
        XCTAssertEqual(selected.matchedGoalIDsRaw, goals)
        XCTAssertEqual(selected.alignment, admission.demand.goalAlignment)
        XCTAssertEqual(admission.demand.editorialBand, .b1)
        let empty = NFEditorialGoalPreferences(policyVersion: preferences.policyVersion,
            profileID: preferences.profileID, goalIDsRaw: [])
        XCTAssertTrue(empty.isSupported)
        XCTAssertEqual(NFEditorialGoalRankingPolicy.selection(admission: admission, preferences: empty)?.preference, 0)
        XCTAssertEqual(try NFEditorialGoalRankingPolicy.selection(admission: goalAdmission("unmapped", goals: nil), preferences: preferences)?.preference, 0)
        for ids in [["future-goal"], [goals[0], goals[0]]] {
            XCTAssertFalse(NFEditorialGoalPreferences(policyVersion: preferences.policyVersion, profileID: preferences.profileID, goalIDsRaw: ids).isSupported)
        }
        XCTAssertFalse(NFEditorialGoalPreferences(policyVersion: "ExplicitGoalPreferencesV999",
            profileID: preferences.profileID, goalIDsRaw: goals).isSupported)
        var future = selected; future.schemaVersion = 999
        let decoded = try JSONDecoder().decode(NFEditorialGoalSelection.self, from: JSONEncoder().encode(future))
        XCTAssertEqual(decoded, future); XCTAssertFalse(decoded.isSupported)
    }

    func testAuthoredGoalManifestRejectsConflictingOrPartialObjectiveMappingsAndKeepsLegacyNilBytes() throws {
        let mapped = try goalAdmission("one", goals: [TrainingGoal.programming.rawValue])
        let same = try goalAdmission("two", goals: [TrainingGoal.programming.rawValue])
        let changed = try goalAdmission("three", goals: [TrainingGoal.mentalMath.rawValue])
        let legacy = try goalAdmission("legacy", goals: nil)
        XCTAssertTrue(NFEditorialGoalRankingPolicy.consistentAlignments([mapped, same]))
        XCTAssertFalse(NFEditorialGoalRankingPolicy.consistentAlignments([mapped, changed]))
        XCTAssertFalse(NFEditorialGoalRankingPolicy.consistentAlignments([mapped, legacy]))
        XCTAssertTrue(NFEditorialGoalRankingPolicy.consistentAlignments([legacy]))
        var wrongObjective = mapped.demand
        wrongObjective.goalAlignment = .init(objectiveID: "unrelated-objective", goalIDsRaw: [TrainingGoal.programming.rawValue])
        XCTAssertFalse(wrongObjective.hasRequiredIdentity)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let bytes = try encoder.encode(legacy)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: bytes) as? [String: Any])
        let demand = try XCTUnwrap(object["demand"] as? [String: Any])
        XCTAssertNil(demand["goalAlignment"])
        let decoded = try JSONDecoder().decode(NFEditorialAdmissionEntry.self, from: bytes)
        XCTAssertEqual(decoded, legacy)
        XCTAssertEqual(try NFEditorialCanonicalData.digest(decoded), try NFEditorialCanonicalData.digest(legacy))
        let old = NFEditorialSessionPin(catalogVersion: "QA.legacy", objectiveID: "O.mul", familyID: "F.mul",
            controllerVersion: NFEditorialLiveController.version, catalogDigest: String(repeating: "a", count: 64))
        XCTAssertTrue(old.isSupported); XCTAssertNil(old.goalPreferences)
        XCTAssertNil(try XCTUnwrap(JSONSerialization.jsonObject(with: encoder.encode(old)) as? [String: Any])["goalPreferences"])
    }
}

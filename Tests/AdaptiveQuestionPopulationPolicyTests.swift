import Foundation
import XCTest

@testable import NeuroForge

final class AdaptiveQuestionPopulationPolicyTests: XCTestCase {
    func testSnapshotEmitsOnlyBoundedDerivedAggregates() throws {
        let referenceDate = Date(timeIntervalSince1970: 1_700_100_000)
        let profileA = makeProfile(
            id: UUID(uuidString: "DEADBEEF-DEAD-BEEF-DEAD-BEEFDEADBEEF")!,
            fields: Set(STEMField.allCases),
            goals: Set(TrainingGoal.allCases)
        )
        let profileB = makeProfile(
            id: UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!,
            fields: Set(STEMField.allCases),
            goals: Set(TrainingGoal.allCases)
        )
        let first = makeAttempt(
            lab: .logicDebugging,
            credit: 0,
            confidence: .certain,
            submittedAt: referenceDate.addingTimeInterval(-3_600),
            canary: "RAW-ANSWER-ALPHA"
        )
        first.id = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!
        first.deviceID = UUID(uuidString: "66666666-7777-8888-9999-AAAAAAAAAAAA")!
        let second = makeAttempt(
            lab: .logicDebugging,
            credit: 0,
            confidence: .certain,
            submittedAt: referenceDate.addingTimeInterval(-3_600),
            canary: "RAW-ANSWER-BETA"
        )
        second.id = UUID(uuidString: "BBBBBBBB-CCCC-DDDD-EEEE-FFFFFFFFFFFF")!
        second.deviceID = UUID(uuidString: "01234567-89AB-CDEF-0123-456789ABCDEF")!

        let snapshotA = NFLocalPersonalizationSnapshotBuilder.makeSnapshot(
            profile: profileA,
            attempts: [first],
            referenceDate: referenceDate
        )
        let snapshotB = NFLocalPersonalizationSnapshotBuilder.makeSnapshot(
            profile: profileB,
            attempts: [second],
            referenceDate: referenceDate
        )

        XCTAssertEqual(snapshotA, snapshotB)
        XCTAssertEqual(snapshotA.schemaVersion, 1)
        XCTAssertEqual(snapshotA.preferredFields.count, 4)
        XCTAssertEqual(snapshotA.goals.count, 4)
        XCTAssertEqual(snapshotA.labs.count, TrainingLab.allCases.count)
        XCTAssertEqual(snapshotA.labs.map(\.lab), TrainingLab.allCases)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let encoded = try encoder.encode(snapshotA)
        let json = try XCTUnwrap(String(data: encoded, encoding: .utf8))
        let forbiddenValues = [
            "DEADBEEF-DEAD-BEEF-DEAD-BEEFDEADBEEF",
            "11111111-2222-3333-4444-555555555555",
            "66666666-7777-8888-9999-AAAAAAAAAAAA",
            "RAW-ANSWER-ALPHA",
            first.itemID,
            first.prompt,
            first.correctAnswerText
        ]
        for forbidden in forbiddenValues where !forbidden.isEmpty {
            XCTAssertFalse(
                json.localizedCaseInsensitiveContains(forbidden),
                "Personalization payload leaked: \(forbidden)"
            )
        }
        for forbiddenKey in ["\"id\"", "\"prompt\"", "\"response\"", "\"submittedAt\""] {
            XCTAssertFalse(json.contains(forbiddenKey), "Unexpected payload key \(forbiddenKey)")
        }
    }

    func testSnapshotDerivesCoarsePerformanceTrendCalibrationAndReviewBands() throws {
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        let attempts = (0..<6).map { index in
            makeAttempt(
                lab: .quantitative,
                credit: index < 3 ? 0 : 1,
                confidence: .certain,
                submittedAt: base.addingTimeInterval(Double(index)),
                canary: "private-\(index)"
            )
        }
        let snapshot = NFLocalPersonalizationSnapshotBuilder.makeSnapshot(
            profile: makeProfile(),
            attempts: attempts,
            referenceDate: base.addingTimeInterval(3_600)
        )
        let aggregate = try XCTUnwrap(snapshot.labs.first { $0.lab == .quantitative })

        XCTAssertEqual(aggregate.evidence, .developing)
        XCTAssertEqual(aggregate.performance, .developing)
        XCTAssertEqual(aggregate.trend, .improving)
        XCTAssertEqual(aggregate.calibration, .overconfident)
        XCTAssertEqual(aggregate.review, .current)
    }

    func testSnapshotIgnoresDocumentPracticeSkippedAndUnscoredAttempts() throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let eligible = makeAttempt(
            lab: .retrieval,
            credit: 0,
            confidence: .uncertain,
            submittedAt: now,
            canary: "eligible"
        )
        let documentPractice = makeAttempt(
            lab: .retrieval,
            credit: 1,
            confidence: .certain,
            submittedAt: now,
            evidenceClass: .documentPractice,
            canary: "document"
        )
        let skipped = makeAttempt(
            lab: .retrieval,
            credit: 1,
            confidence: .certain,
            submittedAt: now,
            skipped: true,
            canary: "skipped"
        )
        let unweighted = makeAttempt(
            lab: .retrieval,
            credit: 1,
            confidence: .certain,
            submittedAt: now,
            evidenceWeight: 0,
            canary: "unweighted"
        )
        let unknownEvidence = makeAttempt(
            lab: .retrieval,
            credit: 1,
            confidence: .certain,
            submittedAt: now,
            canary: "unknown"
        )
        unknownEvidence.evidenceClassRaw = "future-unrecognized-evidence"

        let snapshot = NFLocalPersonalizationSnapshotBuilder.makeSnapshot(
            profile: makeProfile(),
            attempts: [eligible, documentPractice, skipped, unweighted, unknownEvidence],
            referenceDate: now
        )
        let aggregate = try XCTUnwrap(snapshot.labs.first { $0.lab == .retrieval })
        XCTAssertEqual(aggregate.evidence, .sparse)
        XCTAssertEqual(aggregate.performance, .needsSupport)
        XCTAssertEqual(aggregate.trend, .unknown)
        XCTAssertEqual(aggregate.calibration, .unknown)
    }

    func testSnapshotUsesOnlyBoundedRecentWindowPerLab() throws {
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        var attempts = (0..<50).map { index in
            makeAttempt(
                lab: .mentalMath,
                credit: 0,
                confidence: .uncertain,
                submittedAt: base.addingTimeInterval(Double(index)),
                canary: "old-\(index)"
            )
        }
        attempts.append(contentsOf: (0..<NFLocalPersonalizationSnapshotBuilder.maximumAttemptsConsideredPerLab).map { index in
            makeAttempt(
                lab: .mentalMath,
                credit: 1,
                confidence: .certain,
                submittedAt: base.addingTimeInterval(Double(100 + index)),
                canary: "recent-\(index)"
            )
        })

        let snapshot = NFLocalPersonalizationSnapshotBuilder.makeSnapshot(
            profile: makeProfile(),
            attempts: attempts,
            referenceDate: base.addingTimeInterval(1_000)
        )
        let aggregate = try XCTUnwrap(snapshot.labs.first { $0.lab == .mentalMath })
        XCTAssertEqual(aggregate.evidence, .established)
        XCTAssertEqual(aggregate.performance, .secure)
        XCTAssertEqual(aggregate.trend, .steady)
        XCTAssertEqual(aggregate.calibration, .aligned)
    }

    func testSourceContextRequiresExplicitCurrentConsentAndEnforcesEveryBudget() throws {
        XCTAssertNil(NFExplicitSourceConsent.make(explicitlyGranted: false))
        XCTAssertNil(NFExplicitSourceConsent.make(explicitlyGranted: true, policyVersion: 0))
        let consent = try XCTUnwrap(NFExplicitSourceConsent.make(explicitlyGranted: true))

        XCTAssertEqual(NFAdaptiveSourceContext.sourceFree.mode, .sourceFree)
        XCTAssertEqual(NFAdaptiveSourceContext.sourceFree.excerpts, [])
        XCTAssertNil(NFAdaptiveSourceContext.sourceFree.consentPolicyVersion)

        let context = try NFAdaptiveSourceContext.explicitlyConsented(
            excerpts: ["  bounded textbook statement  ", "second selected statement"],
            consent: consent
        )
        XCTAssertEqual(context.mode, .explicitlyConsented)
        XCTAssertEqual(context.excerpts, ["bounded textbook statement", "second selected statement"])
        XCTAssertEqual(context.consentPolicyVersion, NFExplicitSourceConsent.currentPolicyVersion)

        assertSourceError(.noExcerpts, excerpts: [], consent: consent)
        assertSourceError(
            .tooManyExcerpts,
            excerpts: Array(repeating: "bounded", count: NFAdaptiveSourceContext.maximumExcerptCount + 1),
            consent: consent
        )
        assertSourceError(.emptyExcerpt, excerpts: ["  \n "], consent: consent)
        assertSourceError(
            .excerptTooLong,
            excerpts: [String(repeating: "a", count: NFAdaptiveSourceContext.maximumCharactersPerExcerpt + 1)],
            consent: consent
        )
        assertSourceError(
            .totalContextTooLong,
            excerpts: Array(repeating: String(repeating: "b", count: 1_300), count: 4),
            consent: consent
        )
        assertSourceError(
            .unsupportedControlCharacter,
            excerpts: ["visible\u{0000}hidden"],
            consent: consent
        )
    }

    func testPolicyFailsClosedUntilVerifiedUniqueFloorIsMetForEveryLab() throws {
        XCTAssertEqual(NFBundledQuestionFloorEvidence.requiredUniqueQuestionsPerLab, 1_000)
        var fingerprints = completeFingerprints()
        fingerprints[.transfer] = Array(repeating: "duplicate", count: 1_000)
        let duplicateInflated = NFBundledQuestionFloorEvidence(
            uniqueQuestionFingerprintsByLab: fingerprints,
            catalogIntegrityVerified: true
        )
        XCTAssertEqual(duplicateInflated.uniqueQuestionCount(for: .transfer), 1)
        XCTAssertFalse(duplicateInflated.satisfiesReleaseFloor)

        let blocked = NFAdaptiveQuestionPopulationPolicy.evaluate(
            destination: .onDevice,
            profile: makeProfile(),
            attempts: [],
            bundledFloor: duplicateInflated
        )
        XCTAssertFalse(blocked.isEligible)
        XCTAssertNil(blocked.payload)
        guard case let .bundledQuestionFloorNotMet(deficits)? = blocked.blockers.first else {
            return XCTFail("Expected a bundled-floor blocker")
        }
        XCTAssertEqual(deficits, [
            NFBundledQuestionFloorDeficit(
                lab: .transfer,
                availableUniqueQuestions: 1,
                requiredUniqueQuestions: 1_000
            )
        ])

        let unverified = NFBundledQuestionFloorEvidence(
            uniqueQuestionFingerprintsByLab: completeFingerprints(),
            catalogIntegrityVerified: false
        )
        let unverifiedDecision = NFAdaptiveQuestionPopulationPolicy.evaluate(
            destination: .onDevice,
            profile: makeProfile(),
            attempts: [],
            bundledFloor: unverified
        )
        XCTAssertEqual(unverifiedDecision.blockers, [.catalogIntegrityUnverified])
        XCTAssertNil(unverifiedDecision.payload)

        let allowed = NFAdaptiveQuestionPopulationPolicy.evaluate(
            destination: .onDevice,
            profile: makeProfile(),
            attempts: [],
            bundledFloor: verifiedCompleteFloor()
        )
        XCTAssertTrue(allowed.isEligible)
        XCTAssertEqual(allowed.payload?.sourceContext.mode, .sourceFree)
    }

    func testPolicyHonorsAIModeAndRequiresSeparateOffDeviceConsent() throws {
        let floor = verifiedCompleteFloor()
        let disabled = NFAdaptiveQuestionPopulationPolicy.evaluate(
            destination: .onDevice,
            profile: makeProfile(aiMode: .disabled),
            attempts: [],
            bundledFloor: floor
        )
        XCTAssertEqual(disabled.blockers, [.aiDisabled])

        let offlinePreference = NFAdaptiveQuestionPopulationPolicy.evaluate(
            destination: .privateCloud,
            profile: makeProfile(aiMode: .onDeviceOnly),
            attempts: [],
            bundledFloor: floor
        )
        XCTAssertTrue(offlinePreference.blockers.contains(.destinationDisallowedByPreference))
        XCTAssertTrue(offlinePreference.blockers.contains(.offDevicePersonalizationConsentRequired))

        let missingConsent = NFAdaptiveQuestionPopulationPolicy.evaluate(
            destination: .privateCloud,
            profile: makeProfile(aiMode: .automatic),
            attempts: [],
            bundledFloor: floor
        )
        XCTAssertEqual(missingConsent.blockers, [.offDevicePersonalizationConsentRequired])
        XCTAssertNil(NFOffDevicePersonalizationConsent.make(explicitlyGranted: false))
        let consent = try XCTUnwrap(
            NFOffDevicePersonalizationConsent.make(explicitlyGranted: true)
        )
        let allowed = NFAdaptiveQuestionPopulationPolicy.evaluate(
            destination: .privateCloud,
            profile: makeProfile(aiMode: .automatic),
            attempts: [],
            bundledFloor: floor,
            offDeviceConsent: consent
        )
        XCTAssertTrue(allowed.isEligible)
    }

    func testEligiblePayloadClearlyDistinguishesConsentedSourceFromSourceFree() throws {
        let sourceConsent = try XCTUnwrap(NFExplicitSourceConsent.make(explicitlyGranted: true))
        let offDeviceConsent = try XCTUnwrap(
            NFOffDevicePersonalizationConsent.make(explicitlyGranted: true)
        )
        let source = try NFAdaptiveSourceContext.explicitlyConsented(
            excerpts: ["Only this selected textbook excerpt may be used."],
            consent: sourceConsent
        )
        let decision = NFAdaptiveQuestionPopulationPolicy.evaluate(
            destination: .privateCloud,
            profile: makeProfile(aiMode: .automatic),
            attempts: [],
            bundledFloor: verifiedCompleteFloor(),
            sourceContext: source,
            offDeviceConsent: offDeviceConsent
        )

        let payload = try XCTUnwrap(decision.payload)
        XCTAssertEqual(payload.sourceContext.mode, .explicitlyConsented)
        XCTAssertEqual(payload.sourceContext.excerpts.count, 1)
        XCTAssertLessThanOrEqual(
            payload.sourceContext.excerpts.reduce(0) { $0 + $1.count },
            NFAdaptiveSourceContext.maximumTotalCharacters
        )
        let encoded = try JSONEncoder().encode(payload)
        let json = try XCTUnwrap(String(data: encoded, encoding: .utf8))
        XCTAssertTrue(json.contains("explicitlyConsented"))
        XCTAssertTrue(json.contains("Only this selected textbook excerpt may be used."))
    }

    private func makeProfile(
        id: UUID = UUID(),
        fields: Set<STEMField> = [.mathematics, .computing],
        goals: Set<TrainingGoal> = [.problemSolving, .programming],
        aiMode: AIMode = .automatic
    ) -> ProfileSnapshot {
        ProfileSnapshot(
            id: id,
            stage: .graduate,
            fields: fields,
            goals: goals,
            dailyDuration: 20,
            timingMode: .adaptive,
            aiMode: aiMode,
            iCloudEnabled: true
        )
    }

    private func makeAttempt(
        lab: TrainingLab,
        credit: Double,
        confidence: ConfidenceLevel?,
        submittedAt: Date,
        evidenceClass: EvidenceClass = .practice,
        skipped: Bool = false,
        evidenceWeight: Double = 1,
        canary: String
    ) -> AttemptRecord {
        let record = AttemptRecord(
            sessionID: UUID(),
            lab: lab,
            itemID: "item-\(canary)",
            prompt: "prompt-\(canary)",
            response: "response-\(canary)",
            correctAnswer: "answer-\(canary)",
            isCorrect: credit >= 1,
            confidence: confidence ?? .uncertain,
            evidenceClass: evidenceClass
        )
        record.templateID = "template-\(canary)"
        record.correctAnswerText = "correct-\(canary)"
        record.deterministicCredit = credit
        record.confidenceRaw = confidence?.rawValue
        record.shownAt = submittedAt.addingTimeInterval(-30)
        record.submittedAt = submittedAt
        record.evidenceWeight = evidenceWeight
        record.wasSkipped = skipped
        record.sourceChunkIDsRaw = "source-\(canary)"
        return record
    }

    private func completeFingerprints(count: Int = 1_000) -> [TrainingLab: [String]] {
        Dictionary(uniqueKeysWithValues: TrainingLab.allCases.map { lab in
            (
                lab,
                (0..<count).map { index in
                    "fingerprint-v1-\(lab.rawValue)-\(index)"
                }
            )
        })
    }

    private func verifiedCompleteFloor() -> NFBundledQuestionFloorEvidence {
        NFBundledQuestionFloorEvidence(
            uniqueQuestionFingerprintsByLab: completeFingerprints(),
            catalogIntegrityVerified: true
        )
    }

    private func assertSourceError(
        _ expected: NFAdaptiveSourceContextError,
        excerpts: [String],
        consent: NFExplicitSourceConsent,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertThrowsError(
            try NFAdaptiveSourceContext.explicitlyConsented(
                excerpts: excerpts,
                consent: consent
            ),
            file: file,
            line: line
        ) { error in
            XCTAssertEqual(error as? NFAdaptiveSourceContextError, expected, file: file, line: line)
        }
    }
}

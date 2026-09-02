import XCTest

@testable import NeuroForge

final class ProgressEvidenceTests: XCTestCase {
    func testUntimedAttemptsMakeSpeedExplicitlyUnavailable() {
        let attempts = (0..<8).map { index in
            makeAttempt(index: index, timed: false, seconds: 10 + Double(index))
        }
        let evidence = NFSpeedEvidenceEngine.estimate(for: .mentalMath, attempts: attempts)

        XCTAssertEqual(evidence.status, .unavailableUntimed)
        XCTAssertNil(evidence.medianActiveSeconds)
    }

    func testSpeedUsesOnlyCorrectUninterruptedTimedEvidence() throws {
        var attempts = [8.0, 10.0, 12.0, 14.0, 16.0].enumerated().map {
            makeAttempt(index: $0.offset, timed: true, seconds: $0.element)
        }
        let interrupted = makeAttempt(index: 20, timed: true, seconds: 1)
        interrupted.interruptionCount = 1
        attempts.append(interrupted)
        let incorrect = makeAttempt(index: 21, timed: true, seconds: 2)
        incorrect.isCorrect = false
        incorrect.deterministicCredit = 0
        attempts.append(incorrect)

        let evidence = NFSpeedEvidenceEngine.estimate(for: .mentalMath, attempts: attempts)

        XCTAssertEqual(evidence.status, .available)
        XCTAssertEqual(evidence.eligibleCount, 5)
        XCTAssertEqual(try XCTUnwrap(evidence.medianActiveSeconds), 12, accuracy: 0.0001)
        XCTAssertEqual(try XCTUnwrap(evidence.medianAbsoluteDeviationSeconds), 2, accuracy: 0.0001)
    }

    func testWeeklyTrendUsesWeightedCreditAndExcludesSkipAndZeroEvidenceAcrossWeekBoundary() throws {
        var calendar = Calendar(identifier: .iso8601)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let firstMonday = try XCTUnwrap(calendar.date(from: DateComponents(
            calendar: calendar,
            timeZone: calendar.timeZone,
            year: 2026,
            month: 1,
            day: 5,
            hour: 12
        )))
        let firstSunday = try XCTUnwrap(calendar.date(byAdding: .day, value: 6, to: firstMonday))
        let nextMonday = try XCTUnwrap(calendar.date(byAdding: .day, value: 7, to: firstMonday))

        let full = makeAttempt(index: 30, timed: true, seconds: 8)
        full.submittedAt = firstMonday
        full.deterministicCredit = 1
        full.evidenceWeight = 1

        let partial = makeAttempt(index: 31, timed: true, seconds: 9)
        partial.submittedAt = firstSunday
        partial.deterministicCredit = 0
        partial.evidenceWeight = 0.5

        let skipped = makeAttempt(index: 32, timed: true, seconds: 2)
        skipped.submittedAt = firstSunday
        skipped.wasSkipped = true
        skipped.deterministicCredit = 1
        skipped.evidenceWeight = 1

        let zeroEvidence = makeAttempt(index: 33, timed: true, seconds: 1)
        zeroEvidence.submittedAt = firstMonday
        zeroEvidence.evidenceWeight = 0

        let followingWeek = makeAttempt(index: 34, timed: true, seconds: 7)
        followingWeek.submittedAt = nextMonday
        followingWeek.deterministicCredit = 0.5
        followingWeek.evidenceWeight = 1

        let points = NFWeeklyProgressPoint.make(
            from: [full, partial, skipped, zeroEvidence, followingWeek],
            calendar: calendar
        )

        XCTAssertEqual(points.count, 2)
        XCTAssertEqual(points[0].count, 2)
        XCTAssertEqual(points[0].credit, 2.0 / 3.0, accuracy: 0.0001)
        XCTAssertEqual(points[1].count, 1)
        XCTAssertEqual(points[1].credit, 0.5, accuracy: 0.0001)
        XCTAssertNotEqual(points[0].week, points[1].week)
    }

    func testAbilitySnapshotUsesOneAttributedAttemptSetForHeadlineAndCoverage() throws {
        let direct = AttemptRecord(
            sessionID: UUID(),
            lab: .quantitative,
            itemID: "quant-direct",
            prompt: "Direct quantitative prompt",
            response: "correct",
            correctAnswer: "correct",
            isCorrect: true,
            confidence: .certain,
            evidenceClass: .practice
        )
        direct.deterministicCredit = 1
        direct.evidenceWeight = 1

        let crossModule = AttemptRecord(
            sessionID: UUID(),
            lab: .transfer,
            itemID: "transfer-with-quant-weight",
            prompt: "Transfer prompt",
            response: "incorrect",
            correctAnswer: "correct",
            isCorrect: false,
            confidence: .uncertain,
            evidenceClass: .appliedTransfer
        )
        crossModule.deterministicCredit = 0
        crossModule.evidenceWeight = 1
        crossModule.skillID = TrainingLab.transfer.skillID
        let encodedWeights = try JSONEncoder().encode([
            TrainingLab.quantitative.skillID: 0.7,
            TrainingLab.scientificReasoning.skillID: 0.3
        ])
        crossModule.skillWeightsRaw = try XCTUnwrap(String(data: encodedWeights, encoding: .utf8))

        let unrelated = AttemptRecord(
            sessionID: UUID(),
            lab: .retrieval,
            itemID: "unrelated",
            prompt: "Retrieval prompt",
            response: "correct",
            correctAnswer: "correct",
            isCorrect: true,
            confidence: .certain,
            evidenceClass: .retention
        )

        let snapshot = NFAbilityEvidenceSnapshot(
            lab: .quantitative,
            attempts: [direct, crossModule, unrelated]
        )
        let training = snapshot.metric(for: [.practice])
        let transfer = snapshot.metric(for: [.appliedTransfer])

        XCTAssertEqual(snapshot.evidenceCount, 2)
        XCTAssertEqual(training.count, 1)
        XCTAssertEqual(transfer.count, 1)
        XCTAssertEqual(training.count + transfer.count, snapshot.evidenceCount)
        XCTAssertEqual(try XCTUnwrap(snapshot.credit), 1 / 1.7, accuracy: 0.000_001)
    }

    func testReadOnlyHistoryPreservesExactTextAndRedactsPrivateSourceIdentifiers() {
        let documentID = UUID()
        let record = AttemptRecord(
            sessionID: UUID(),
            lab: .retrieval,
            itemID: "personal-review",
            prompt: "Exact saved prompt — do not regenerate",
            response: "{\"shortText\":\"Exact saved answer\"}",
            correctAnswer: "Exact saved key",
            isCorrect: false,
            confidence: .fairlyConfident,
            evidenceClass: .documentPractice,
            sourceDocumentIDs: [documentID]
        )

        let snapshot = NFReadOnlyAttemptSnapshot(attempt: record)

        XCTAssertEqual(snapshot.prompt, record.prompt)
        XCTAssertEqual(snapshot.response, record.response)
        XCTAssertEqual(snapshot.source, .personal)
        XCTAssertFalse(snapshot.privacyNote.contains(documentID.uuidString))
    }

    func testProtectedHistoryDoesNotExposeSavedAnswerKey() {
        let record = AttemptRecord(
            sessionID: UUID(),
            lab: .logicDebugging,
            itemID: "protected-review",
            prompt: "Protected prompt",
            response: "Learner response",
            correctAnswer: "SECRET HOLDOUT KEY",
            isCorrect: false,
            confidence: .uncertain,
            evidenceClass: .assessmentHoldout,
            source: .baseline
        )

        let snapshot = NFReadOnlyAttemptSnapshot(attempt: record)

        XCTAssertEqual(snapshot.source, .protectedAssessment)
        XCTAssertFalse(snapshot.explanation.contains("SECRET HOLDOUT KEY"))
        XCTAssertFalse(snapshot.privacyNote.isEmpty)
    }

    func testReadOnlyHistoryCarriesTemplateIdentityButPresentsOnlyItsSafeVersion() {
        let record = AttemptRecord(
            sessionID: UUID(),
            lab: .mentalMath,
            itemID: "versioned-review",
            prompt: "Saved prompt",
            response: "42",
            correctAnswer: "42",
            isCorrect: true,
            confidence: .certain
        )
        record.templateID = "nf.fallback.mental_math.practice.v3.private-internal-slug"
        record.scoringVersion = 7
        record.validationVersion = 8

        let snapshot = NFReadOnlyAttemptSnapshot(attempt: record)

        XCTAssertEqual(snapshot.templateID, record.templateID)
        XCTAssertEqual(
            NFReadOnlyAttemptSnapshot.promptVersionTitle(
                for: record.templateID,
                locale: NFAppLocalization.locale(identifier: "en")
            ),
            "Prompt template version 3"
        )
        XCTAssertTrue(snapshot.contentVersionTitle.contains("scorer 7"))
        XCTAssertTrue(snapshot.contentVersionTitle.contains("validator 8"))
        XCTAssertFalse(snapshot.contentVersionTitle.contains(record.templateID))
        XCTAssertFalse(snapshot.contentVersionTitle.contains("private-internal-slug"))
    }

    func testReadOnlyHistoryUsesGenericCopyForPrivateTemplateWithoutPublicVersion() {
        let privateTemplateID = "private_source_name_and_internal_identifier"
        let english = NFAppLocalization.locale(identifier: "en")
        let japanese = NFAppLocalization.locale(identifier: "ja")

        XCTAssertEqual(
            NFReadOnlyAttemptSnapshot.promptVersionTitle(for: privateTemplateID, locale: english),
            "Saved prompt copy"
        )
        let japaneseTitle = NFReadOnlyAttemptSnapshot.promptVersionTitle(
            for: privateTemplateID,
            locale: japanese
        )
        XCTAssertFalse(japaneseTitle.contains(privateTemplateID))
        XCTAssertFalse(japaneseTitle.contains("private_source"))
    }

    func testTodayXPSourceHasTypedLocalizedFallback() {
        let source = NFTodayXPSource.resolved(from: "missing.catalog.source")
        let label = source.localizedLabel(amount: NFForgeProgressEngine.xpPerEligibleCompletedSession)

        XCTAssertEqual(source, .activityFallback)
        XCTAssertTrue(label.contains("\(NFForgeProgressEngine.xpPerEligibleCompletedSession)"))
        XCTAssertFalse(label.contains("NFForgeProgressEngine"))
        XCTAssertFalse(label.contains("("))
    }

    func testReadinessImpactNamesExactLengthTimingAndNextChapterChanges() {
        let previous = NFTodayReadinessPlanSnapshot(
            remainingMinutes: 15,
            timedMinutes: 5,
            nextChapterTitle: "Logic practice",
            nextChapterMinutes: 5
        )
        let updated = NFTodayReadinessPlanSnapshot(
            remainingMinutes: 10,
            timedMinutes: 0,
            nextChapterTitle: "Data practice",
            nextChapterMinutes: 4
        )
        let impact = NFTodayReadinessImpact(
            previousReadiness: .normal,
            newReadiness: .low,
            previous: previous,
            new: updated,
            planWasAlreadyInProgress: false,
            reason: "Saved readiness explanation"
        )

        XCTAssertTrue(impact.changeSummary.contains("15"))
        XCTAssertTrue(impact.changeSummary.contains("10"))
        XCTAssertTrue(impact.changeSummary.contains("5"))
        XCTAssertTrue(impact.changeSummary.contains("0"))
        XCTAssertTrue(impact.changeSummary.contains("Logic practice"))
        XCTAssertTrue(impact.changeSummary.contains("Data practice"))
        XCTAssertTrue(updated.summary.contains("Data practice"))
    }

    func testWeeklyMissionSkillPresentationNeverLeaksPersistedIdentifiers() {
        let english = NFAppLocalization.locale(identifier: "en")
        for lab in TrainingLab.allCases {
            let title = NFTodaySkillPresentation.localizedTitle(
                for: lab.skillID,
                locale: english
            )
            XCTAssertFalse(title.contains("skill."), lab.skillID)
            XCTAssertFalse(title.contains(lab.skillID), lab.skillID)
        }
        for dimension in NFAssessmentDimension.allCases {
            let title = NFTodaySkillPresentation.localizedTitle(
                for: dimension.skillID,
                locale: english
            )
            XCTAssertFalse(title.contains("skill."), dimension.skillID)
            XCTAssertFalse(title.contains(dimension.skillID), dimension.skillID)
        }

        let unknown = NFTodaySkillPresentation.localizedTitle(
            for: "skill.private_future_taxonomy",
            locale: english
        )
        XCTAssertFalse(unknown.contains("skill."))
        XCTAssertFalse(unknown.contains("private_future_taxonomy"))
    }

    func testAdaptiveHistoryPresentationHidesRawIdentifiers() {
        let raw = "Changed target to skill.scientificReasoning"
        let safe = NFAdaptiveHistoryPresentation.safeText(raw)

        XCTAssertNotEqual(safe, raw)
        XCTAssertFalse(safe.contains("skill."))
        XCTAssertNil(NFUserFacingContentLinter.lint(safe))
    }

    func testMentalMathProgressAdapterRecoversCompositeEstimateAndExactReference() throws {
        let attempt = makeAttempt(index: 40, timed: false, seconds: 18)
        attempt.templateID = "nf.fallback.mental_math.practice.v3.estimate-first"
        let response = NFExerciseResponse.logicState(
            NFLogicStateSubmission(
                finalState: [
                    NFEstimateExactContract.estimateKey: "10,000",
                    NFEstimateExactContract.plausibilityKey: "plausible",
                    NFEstimateExactContract.exactKey: "9,702"
                ],
                violatedRuleID: nil
            )
        )
        attempt.response = try XCTUnwrap(String(
            data: JSONEncoder().encode(response),
            encoding: .utf8
        ))
        attempt.correctAnswerText = "1 · estimate=10000, 2 · plausibility=plausible, 3 · exact=9702"

        let observation = try XCTUnwrap(NFMentalMathProgressAdapter.observation(from: attempt))

        XCTAssertEqual(observation.estimate, try NFExactNumber(numerator: 10_000))
        XCTAssertEqual(observation.exactReference, try NFExactNumber(numerator: 9_702))
        XCTAssertTrue(observation.tags.contains("estimate-first"))
        XCTAssertNotNil(observation.strategyID)
    }

    func testMentalMathProgressAdapterUsesDurableUnitAndRapidRecallSignalsOnly() throws {
        let unitAttempt = makeAttempt(index: 41, timed: false, seconds: 20)
        unitAttempt.templateID = "nf.fallback.mental_math.practice.v3.unit-conversion"
        unitAttempt.correctAnswerText = "12 m"
        unitAttempt.response = try XCTUnwrap(String(
            data: JSONEncoder().encode(
                NFExerciseResponse.numeric(NFNumericSubmission(value: "12", unit: "m"))
            ),
            encoding: .utf8
        ))

        let unitObservation = try XCTUnwrap(NFMentalMathProgressAdapter.observation(from: unitAttempt))
        XCTAssertTrue(unitObservation.unitRequired)
        XCTAssertEqual(unitObservation.unitWasCorrect, true)
        XCTAssertTrue(unitObservation.tags.contains("unit-conversion"))

        let untimedRecall = makeAttempt(index: 42, timed: false, seconds: 3)
        untimedRecall.templateID = "nf.fallback.mental_math.practice.v3.rapid-recall"
        let recallObservation = try XCTUnwrap(NFMentalMathProgressAdapter.observation(from: untimedRecall))
        let result = try XCTUnwrap(
            NFMentalMathMetricReducer.reduce([recallObservation])[.retrievalFluency]
        )
        XCTAssertEqual(result.sampleCount, 0, "An untimed response must not become fluency evidence.")
        XCTAssertFalse(result.isAvailable)
    }

    func testForgeProgressRewardsUniqueEngagementAndEligibleCompletionOnly() throws {
        let now = Date(timeIntervalSince1970: 1_768_219_200)
        let sessionID = UUID(uuidString: "B18C3C09-E710-4B29-8E62-C81950EC91A8")!
        let correctTimed = makeForgeAttempt(
            id: UUID(uuidString: "AF778A76-075A-4548-981A-8078C8CA3581")!,
            sessionID: sessionID,
            lab: .mentalMath,
            date: now.addingTimeInterval(-30),
            correct: true,
            evidenceClass: .practice
        )
        correctTimed.wasTimed = true
        let incorrectUntimed = makeForgeAttempt(
            id: UUID(uuidString: "0B510FBD-8AB2-43DC-8195-608A5DA42C1C")!,
            sessionID: sessionID,
            lab: .logicDebugging,
            date: now.addingTimeInterval(-20),
            correct: false,
            evidenceClass: .practice
        )
        let personalDocument = makeForgeAttempt(
            id: UUID(uuidString: "19C282B8-0B2E-4F20-8996-EFA1986C9DA6")!,
            sessionID: sessionID,
            lab: .retrieval,
            date: now.addingTimeInterval(-10),
            correct: false,
            evidenceClass: .documentPractice
        )
        personalDocument.evidenceWeight = 0
        let skipped = makeForgeAttempt(
            id: UUID(uuidString: "8A7D636C-DFD5-41A2-9F98-6541F61DAF89")!,
            sessionID: sessionID,
            lab: .spatial,
            date: now,
            correct: true,
            evidenceClass: .practice
        )
        skipped.wasSkipped = true

        let completed = makeCheckpoint(
            sessionID: sessionID,
            lab: .mentalMath,
            updatedAt: now,
            isComplete: true
        )
        let duplicateCompletion = makeCheckpoint(
            sessionID: sessionID,
            lab: .mentalMath,
            updatedAt: now.addingTimeInterval(5),
            isComplete: true
        )
        let orphanCompletion = makeCheckpoint(
            sessionID: UUID(uuidString: "54051A29-3344-4940-BDEB-D22F85BB6319")!,
            lab: .quantitative,
            updatedAt: now,
            isComplete: true
        )

        let snapshot = NFForgeProgressEngine.makeSnapshot(
            at: now,
            attempts: [correctTimed, incorrectUntimed, personalDocument, skipped, correctTimed],
            checkpoints: [completed, duplicateCompletion, orphanCompletion],
            trainingDays: Set(1...7)
        )

        XCTAssertEqual(snapshot.policyVersion, 1)
        XCTAssertEqual(snapshot.eligibleAttemptCount, 3)
        XCTAssertEqual(snapshot.rewardedSessionCount, 1)
        XCTAssertEqual(snapshot.attemptXP, 30)
        XCTAssertEqual(snapshot.completionXP, 25)
        XCTAssertEqual(snapshot.totalXP, 55)
        XCTAssertEqual(snapshot.level, 1)
        XCTAssertEqual(snapshot.levelStartXP, 0)
        XCTAssertEqual(snapshot.nextLevelXP, 100)
        XCTAssertEqual(snapshot.xpIntoLevel, 55)
        XCTAssertEqual(snapshot.xpToNextLevel, 45)
        XCTAssertEqual(snapshot.levelProgress, 0.55, accuracy: 0.000_001)
        XCTAssertEqual(
            snapshot.milestones.map(\.code),
            [.firstAttempt, .firstCompletedSession]
        )
    }

    func testForgeProgressDerivesRestAwareMomentumWeeklyCoverageAndMilestones() throws {
        var calendar = Calendar(identifier: .iso8601)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let wednesday = try XCTUnwrap(calendar.date(from: DateComponents(
            calendar: calendar,
            timeZone: calendar.timeZone,
            year: 2026,
            month: 1,
            day: 7,
            hour: 12
        )))
        let monday = try XCTUnwrap(calendar.date(byAdding: .day, value: -2, to: wednesday))
        let accessibleLabs = Set(TrainingLab.allCases).subtracting([.spatial, .transfer])
        let orderedLabs = accessibleLabs.sorted { $0.rawValue < $1.rawValue }
        var attempts = orderedLabs.enumerated().map { index, lab in
            makeForgeAttempt(
                id: UUID(),
                sessionID: UUID(),
                lab: lab,
                date: index == 0 ? monday : wednesday.addingTimeInterval(Double(-index)),
                correct: index.isMultiple(of: 2),
                evidenceClass: .practice
            )
        }
        attempts.append(makeForgeAttempt(
            id: UUID(uuidString: "D939988E-B0A4-4DA2-AB2E-C49269913A8F")!,
            sessionID: UUID(uuidString: "47C34A11-46E3-4A30-BB6D-9D2DE8DA1397")!,
            lab: .transfer,
            date: wednesday.addingTimeInterval(-30),
            correct: false,
            evidenceClass: .appliedTransfer
        ))

        let snapshot = NFForgeProgressEngine.makeSnapshot(
            at: wednesday,
            attempts: Array(attempts.reversed()),
            checkpoints: [],
            trainingDays: [2, 4],
            trackingStartDate: monday,
            excludedLabs: [.spatial],
            calendar: calendar
        )

        XCTAssertEqual(snapshot.accessibleLabs, accessibleLabs)
        XCTAssertEqual(snapshot.currentWeekCoveredLabs, accessibleLabs)
        XCTAssertEqual(snapshot.currentWeekCoverage, 1, accuracy: 0.000_001)
        XCTAssertEqual(snapshot.momentum.currentActiveDayStreak, 2)
        XCTAssertEqual(
            snapshot.milestones.map(\.code),
            [.firstAttempt, .firstTransferAttempt, .accessibleLabCircuit]
        )
        XCTAssertEqual(
            snapshot.milestones.first(where: { $0.code == .accessibleLabCircuit })?.evidenceAttemptIDs.count,
            accessibleLabs.count
        )
    }

    private func makeAttempt(index: Int, timed: Bool, seconds: Double) -> AttemptRecord {
        let record = AttemptRecord(
            sessionID: UUID(),
            lab: .mentalMath,
            itemID: "speed-\(index)",
            prompt: "Prompt",
            response: "1",
            correctAnswer: "1",
            isCorrect: true,
            confidence: .certain
        )
        record.wasTimed = timed
        record.activeDurationSeconds = seconds
        record.deterministicCredit = 1
        record.evidenceWeight = 1
        return record
    }

    private func makeForgeAttempt(
        id: UUID,
        sessionID: UUID,
        lab: TrainingLab,
        date: Date,
        correct: Bool,
        evidenceClass: EvidenceClass
    ) -> AttemptRecord {
        let record = AttemptRecord(
            sessionID: sessionID,
            lab: lab,
            itemID: id.uuidString,
            prompt: "Prompt",
            response: correct ? "correct" : "incorrect",
            correctAnswer: "correct",
            isCorrect: correct,
            confidence: .fairlyConfident,
            evidenceClass: evidenceClass
        )
        record.id = id
        record.shownAt = date.addingTimeInterval(-5)
        record.submittedAt = date
        record.deterministicCredit = correct ? 1 : 0
        record.evidenceWeight = evidenceClass == .documentPractice ? 0 : 1
        return record
    }

    private func makeCheckpoint(
        sessionID: UUID,
        lab: TrainingLab,
        updatedAt: Date,
        isComplete: Bool
    ) -> SessionCheckpointRecord {
        let checkpoint = SessionCheckpointRecord(
            sessionID: sessionID,
            lab: lab,
            source: .focused,
            seed: 1,
            currentIndex: 0,
            itemCount: 1,
            response: "",
            scratchpad: "",
            results: [],
            evidenceClass: .practice,
            isComplete: isComplete
        )
        checkpoint.updatedAt = updatedAt
        return checkpoint
    }
}

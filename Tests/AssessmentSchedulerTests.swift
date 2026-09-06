import Foundation
import XCTest

@testable import NeuroForge

final class AssessmentSchedulerTests: XCTestCase {
    func testBaselineHasFourBoundedResumableBlocks() {
        let blocks = NFAssessmentCatalog.baselineBlocks

        XCTAssertEqual(blocks.map(\.kind), NFAssessmentBlockKind.allCases)
        XCTAssertEqual(blocks.count, 4)
        XCTAssertEqual(blocks.map(\.minimumScorableItems), [24, 8, 16, 16])
        XCTAssertTrue(blocks.allSatisfy { $0.targetDurationSeconds <= 480 })
        XCTAssertTrue(blocks.allSatisfy { $0.maximumDurationSeconds <= 480 })
        XCTAssertTrue(blocks.allSatisfy { $0.itemCap >= $0.minimumScorableItems })
    }

    func testCatalogAssignsEveryIndependentDimensionExactlyOnce() {
        let dimensions = NFAssessmentBlockKind.allCases.flatMap {
            NFAssessmentCatalog.dimensions(for: $0)
        }

        XCTAssertEqual(Set(dimensions), Set(NFAssessmentDimension.allCases))
        XCTAssertEqual(dimensions.count, NFAssessmentDimension.allCases.count)
        XCTAssertEqual(Set(NFAssessmentDimension.allCases.map(\.skillID)).count, 8)
        XCTAssertTrue(NFAssessmentBlockKind.allCases.allSatisfy { block in
            NFAssessmentCatalog.definition(for: block).minimumScorableItems
                == NFAssessmentCatalog.dimensions(for: block).count
                    * NFAssessmentCatalog.minimumBaselineItemsPerDimension
        })
    }

    func testDimensionReducerKeepsEightEstimatesIsolatedAndRequiresTwoFormats() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        var attempts: [AttemptDTO] = []
        for (dimensionOrdinal, dimension) in NFAssessmentDimension.allCases.enumerated() {
            for index in 0..<NFAssessmentCatalog.minimumBaselineItemsPerDimension {
                attempts.append(AttemptDTO(
                    id: UUID(),
                    itemID: "\(dimension.rawValue)-\(index)",
                    skillID: dimension.skillID,
                    skillWeights: [dimension.skillID: 1],
                    lab: dimension.lab,
                    correct: true,
                    credit: 1,
                    confidence: index.isMultiple(of: 2) ? .fairlyConfident : .certain,
                    submittedAt: now.addingTimeInterval(Double(dimensionOrdinal * 100 + index)),
                    evidenceClass: .assessmentHoldout,
                    evidenceWeight: 1,
                    assessmentFormat: index.isMultiple(of: 2) ? .numericEntry : .singleChoice
                ))
            }
        }

        let summaries = NFAssessmentDimensionReducer.reduce(attempts)
        XCTAssertEqual(summaries.map(\.id), NFAssessmentDimension.allCases.map(\.skillID))
        XCTAssertTrue(summaries.allSatisfy { $0.evidenceCount == 0 })
        XCTAssertTrue(summaries.allSatisfy { $0.status == .unassessed })
        XCTAssertTrue(summaries.allSatisfy { $0.uncertainty == 1 })

        let probabilityOnlyOneFormat = attempts.map { attempt in
            guard attempt.assessmentDimension == .probability else { return attempt }
            return AttemptDTO(
                id: attempt.id,
                itemID: attempt.itemID,
                skillID: attempt.skillID,
                skillWeights: attempt.skillWeights,
                lab: attempt.lab,
                correct: attempt.correct,
                credit: attempt.credit,
                confidence: attempt.confidence,
                submittedAt: attempt.submittedAt,
                evidenceClass: attempt.evidenceClass,
                evidenceWeight: attempt.evidenceWeight,
                assessmentFormat: .numericEntry
            )
        }
        let probability = try XCTUnwrap(
            NFAssessmentDimensionReducer.reduce(probabilityOnlyOneFormat).first {
                $0.id == NFAssessmentDimension.probability.skillID
            }
        )
        let estimation = try XCTUnwrap(
            NFAssessmentDimensionReducer.reduce(probabilityOnlyOneFormat).first {
                $0.id == NFAssessmentDimension.quantitativeEstimation.skillID
            }
        )
        XCTAssertEqual(probability.status, .unassessed)
        XCTAssertGreaterThanOrEqual(probability.uncertainty, 0.72)
        XCTAssertEqual(estimation.status, .unassessed)
    }

    func testAssessmentFormConstructionIsDeterministicAndUsesAlternateForms() {
        for block in NFAssessmentBlockKind.allCases {
            let first = NFAssessmentEngine.makeBlockSession(
                block: block,
                phase: .initialBaseline,
                profileSeed: 0xA11CE,
                selfReportedDifficulty: 0.62
            )
            let duplicate = NFAssessmentEngine.makeBlockSession(
                block: block,
                phase: .initialBaseline,
                profileSeed: 0xA11CE,
                selfReportedDifficulty: 0.62
            )
            let reassessmentOne = NFAssessmentEngine.makeBlockSession(
                block: block,
                phase: .reassessment(cycle: 1),
                profileSeed: 0xA11CE,
                selfReportedDifficulty: 0.62
            )
            let reassessmentTwo = NFAssessmentEngine.makeBlockSession(
                block: block,
                phase: .reassessment(cycle: 2),
                profileSeed: 0xA11CE,
                selfReportedDifficulty: 0.62
            )

            XCTAssertEqual(first, duplicate)
            XCTAssertEqual(first.items.count, first.definition.minimumScorableItems)
            XCTAssertTrue(first.items.allSatisfy { $0.role == .baseline })
            for dimension in NFAssessmentCatalog.dimensions(for: block) {
                let baselineItems = first.items.filter { $0.dimension == dimension }
                XCTAssertEqual(
                    baselineItems.count,
                    NFAssessmentCatalog.minimumBaselineItemsPerDimension,
                    "\(dimension.rawValue) must have eight scorable baseline items"
                )
                XCTAssertGreaterThanOrEqual(
                    Set(baselineItems.map(\.format)).count,
                    NFAssessmentCatalog.minimumFormatsPerDimension
                )

                let reassessmentItems = reassessmentOne.items.filter { $0.dimension == dimension }
                XCTAssertEqual(
                    reassessmentItems.count,
                    NFAssessmentCatalog.minimumItemsPerDimension(
                        for: .reassessmentHoldout,
                        block: block
                    )
                )
                XCTAssertGreaterThanOrEqual(
                    Set(reassessmentItems.map(\.format)).count,
                    NFAssessmentCatalog.minimumFormatsPerDimension
                )
                XCTAssertTrue(baselineItems.allSatisfy { $0.skillID == dimension.skillID })
            }
            XCTAssertTrue(reassessmentOne.items.allSatisfy { $0.role == .reassessmentHoldout })
            XCTAssertTrue(reassessmentOne.items.allSatisfy { $0.templateFamily.contains(".holdout.") })
            XCTAssertTrue(Set(reassessmentOne.items.map(\.seed)).isDisjoint(with: Set(reassessmentTwo.items.map(\.seed))))
            XCTAssertNotEqual(reassessmentOne.id, reassessmentTwo.id)
        }
    }

    func testReassessmentBecomesDueOnTwentyEighthDistinctActiveDay() throws {
        let calendar = utcCalendar()
        let anchor = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 1, day: 1, hour: 12)))
        let activeDates = (1...28).compactMap {
            calendar.date(byAdding: .day, value: $0, to: anchor)
        }
        let baselineEvidence: [NFAssessmentBlockKind: Date] = [
            .numericalFluency: anchor,
            .logicMetacognition: anchor.addingTimeInterval(60)
        ]

        let beforeDue = NFReassessmentScheduler.reconcile(
            state: NFReassessmentState(),
            baselineEvidenceDates: baselineEvidence,
            completedReassessmentDates: [:],
            activeDates: Array(activeDates.dropLast()) + [activeDates[0]],
            now: activeDates[26],
            calendar: calendar
        )
        XCTAssertEqual(beforeDue.status?.activeDaysCompleted, 27)
        XCTAssertNil(beforeDue.status?.dueAt)
        XCTAssertFalse(try XCTUnwrap(beforeDue.status).isDue)

        let due = NFReassessmentScheduler.reconcile(
            state: beforeDue.state,
            baselineEvidenceDates: baselineEvidence,
            completedReassessmentDates: [:],
            activeDates: activeDates,
            now: activeDates[27],
            calendar: calendar
        )
        let status = try XCTUnwrap(due.status)
        XCTAssertTrue(status.isDue)
        XCTAssertEqual(status.cycle, 1)
        XCTAssertEqual(status.block, .numericalFluency)
        XCTAssertEqual(status.activeDaysCompleted, 28)
        XCTAssertEqual(status.dueAt, calendar.startOfDay(for: activeDates[27]))
    }

    func testReassessmentDeferralIsExactlySevenDaysAndCompletionStartsNextCycle() throws {
        let calendar = utcCalendar()
        let dueAt = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 4, day: 3, hour: 9)))
        let dueState = NFReassessmentState(
            activeDayAnchor: dueAt.addingTimeInterval(-28 * 86_400),
            dueAt: dueAt,
            targetBlock: .numericalFluency
        )
        let deferred = try XCTUnwrap(NFReassessmentScheduler.deferring(dueState, at: dueAt))
        XCTAssertEqual(
            try XCTUnwrap(deferred.deferredUntil).timeIntervalSince(dueAt),
            NFReassessmentScheduler.deferralDuration,
            accuracy: 0.001
        )
        XCTAssertNil(NFReassessmentScheduler.deferring(deferred, at: dueAt.addingTimeInterval(60)))

        let whileDeferred = NFReassessmentScheduler.reconcile(
            state: deferred,
            baselineEvidenceDates: [.numericalFluency: dueState.activeDayAnchor!],
            completedReassessmentDates: [:],
            activeDates: [],
            now: dueAt.addingTimeInterval(NFReassessmentScheduler.deferralDuration - 1),
            calendar: calendar
        )
        XCTAssertTrue(try XCTUnwrap(whileDeferred.status).isDeferred)
        XCTAssertFalse(try XCTUnwrap(whileDeferred.status).isDue)

        let completedAt = dueAt.addingTimeInterval(NFReassessmentScheduler.deferralDuration)
        let completed = try XCTUnwrap(NFReassessmentScheduler.completing(
            deferred,
            cycle: 1,
            block: .numericalFluency,
            at: completedAt
        ))
        XCTAssertEqual(completed.completedCycle, 1)
        XCTAssertEqual(completed.activeDayAnchor, completedAt)
        XCTAssertNil(completed.dueAt)
        XCTAssertNil(completed.deferredUntil)
        XCTAssertNil(completed.targetBlock)

        let nextCycleDates = (1...28).compactMap {
            calendar.date(byAdding: .day, value: $0, to: completedAt)
        }
        let next = NFReassessmentScheduler.reconcile(
            state: completed,
            baselineEvidenceDates: [
                .numericalFluency: dueState.activeDayAnchor!,
                .logicMetacognition: dueState.activeDayAnchor!.addingTimeInterval(60)
            ],
            completedReassessmentDates: [.numericalFluency: completedAt],
            activeDates: nextCycleDates,
            now: nextCycleDates[27],
            calendar: calendar
        )
        XCTAssertEqual(next.status?.cycle, 2)
        XCTAssertEqual(next.status?.block, .logicMetacognition)
        XCTAssertTrue(try XCTUnwrap(next.status).isDue)
    }

    @MainActor
    func testUniversalRuntimeUsesProtectedReassessmentPhaseWithoutBaselinePractice() throws {
        let seed: UInt64 = 0x28AC_71E
        let request = SessionRequest(
            lab: .logicDebugging,
            source: .reassessment,
            seed: seed,
            requestedMinutes: 6,
            evidenceClass: .assessmentHoldout,
            targetDifficulty: 0.5,
            assessmentBlock: .logicMetacognition,
            reassessmentCycle: 2,
            isTimed: false
        )
        let runtime = NFUniversalSessionRuntime(request: request)
        let descriptor = try XCTUnwrap(runtime.assessmentDescriptor)
        let expectedSession = NFAssessmentEngine.makeBlockSession(
            block: .logicMetacognition,
            phase: .reassessment(cycle: 2),
            profileSeed: seed
        )

        XCTAssertFalse(runtime.isAssessmentPractice)
        XCTAssertEqual(descriptor.role, .reassessmentHoldout)
        XCTAssertTrue(descriptor.isProtectedAssessment)
        XCTAssertTrue(expectedSession.candidatePool.contains(descriptor))
        XCTAssertEqual(runtime.exercise.evidenceClass, .assessmentHoldout)
        XCTAssertTrue(runtime.exercise.assessmentProtected)
        XCTAssertEqual(expectedSession.targetDurationSeconds, 300)
        XCTAssertEqual(expectedSession.maximumDurationSeconds, 360)
        XCTAssertTrue(Set(expectedSession.items.map(\.seed)).isDisjoint(with: Set(
            NFAssessmentEngine.makeBlockSession(
                block: .logicMetacognition,
                phase: .initialBaseline,
                profileSeed: seed
            ).items.map(\.seed)
        )))
    }

    func testQuarantinedAssessmentDescriptorIsRemovedFromAdaptivePool() throws {
        let original = NFAssessmentEngine.makeBlockSession(
            block: .logicMetacognition,
            phase: .initialBaseline,
            profileSeed: 0xBAD_C0DE
        )
        let quarantined = try XCTUnwrap(original.items.first)
        let rebuilt = NFAssessmentEngine.makeBlockSession(
            block: .logicMetacognition,
            phase: .initialBaseline,
            profileSeed: 0xBAD_C0DE,
            excludedDescriptorIDs: [quarantined.id]
        )

        XCTAssertFalse(rebuilt.candidatePool.contains { $0.id == quarantined.id })
        XCTAssertFalse(rebuilt.items.contains { $0.id == quarantined.id })
        XCTAssertEqual(rebuilt.items.count, original.items.count)
        XCTAssertNotEqual(rebuilt.id, original.id)
    }

    func testHoldoutFamiliesCannotEnterPracticeSelectionAndPracticeWeightIsZero() throws {
        let practice = NFAssessmentEngine.makePracticeCandidates(
            block: .scientificDataReasoning,
            seed: 44
        )
        let baseline = NFAssessmentEngine.makeBlockSession(
            block: .scientificDataReasoning,
            phase: .initialBaseline,
            profileSeed: 44
        ).items
        let holdout = NFAssessmentEngine.makeBlockSession(
            block: .scientificDataReasoning,
            phase: .reassessment(cycle: 1),
            profileSeed: 44
        ).items
        let mixed = practice + baseline + holdout

        var excluded: Set<String> = []
        for selectionOrdinal in 0..<practice.count {
            let selected = try XCTUnwrap(
                NFPracticeItemSelector.select(
                    from: mixed,
                    seed: UInt64(selectionOrdinal),
                    excluding: excluded
                )
            )
            XCTAssertEqual(selected.role, .practice)
            XCTAssertFalse(selected.isProtectedAssessment)
            XCTAssertEqual(selected.assessmentWeight, 0)
            XCTAssertEqual(selected.evidenceClass, .practice)
            XCTAssertTrue(selected.templateFamily.contains(".practice."))
            excluded.insert(selected.id)
        }

        XCTAssertNil(NFPracticeItemSelector.select(from: baseline + holdout, seed: 9))
        XCTAssertTrue((baseline + holdout).allSatisfy { $0.assessmentWeight == 1 })
    }

    func testPresentedExposureIsExcludedButUnpresentedItemsRemainAvailable() throws {
        let form = NFAssessmentEngine.makeBlockSession(
            block: .spatialRepresentation,
            phase: .reassessment(cycle: 1),
            profileSeed: 71
        )
        let presented = try XCTUnwrap(form.items.first)
        let ledger = NFHoldoutExposureLedger().recordingPresentation(of: presented)
        let rebuilt = NFAssessmentEngine.makeBlockSession(
            block: .spatialRepresentation,
            phase: .reassessment(cycle: 1),
            profileSeed: 71,
            exposureLedger: ledger
        )

        XCTAssertFalse(rebuilt.items.contains(presented))
        XCTAssertEqual(rebuilt.items.count, form.items.count)
        XCTAssertTrue(form.items.dropFirst().contains { rebuilt.items.contains($0) })

        let practice = try XCTUnwrap(
            NFAssessmentEngine.makePracticeCandidates(block: .spatialRepresentation, seed: 71).first
        )
        XCTAssertEqual(ledger.recordingPresentation(of: practice), ledger)
    }

    func testPartialAssessmentResumesAtFirstUnansweredWithoutCountingInterruption() throws {
        let original = NFAssessmentEngine.makeBlockSession(
            block: .logicMetacognition,
            phase: .initialBaseline,
            profileSeed: 31337
        )
        var checkpoint = NFAssessmentCheckpoint(sessionID: original.id)
        for item in original.items.prefix(3) {
            checkpoint = checkpoint.recordingCompletion(itemID: item.id, activeSeconds: 17)
        }
        checkpoint = checkpoint.recordingInterruption(seconds: 240)

        let data = try JSONEncoder().encode(checkpoint)
        let restored = try JSONDecoder().decode(NFAssessmentCheckpoint.self, from: data)
        let reconstructed = NFAssessmentEngine.makeBlockSession(
            block: .logicMetacognition,
            phase: .initialBaseline,
            profileSeed: 31337
        )
        let next = try XCTUnwrap(reconstructed.nextUnanswered(using: restored))

        XCTAssertEqual(reconstructed, original)
        XCTAssertEqual(next.id, original.items[3].id)
        XCTAssertEqual(restored.completedItemIDs.count, 3)
        XCTAssertEqual(restored.activeElapsedSeconds, 51)
        XCTAssertEqual(restored.interruptedSeconds, 240)
        XCTAssertEqual(Set(original.items.map(\.id)).count, original.items.count)
    }

    func testLegacyResponseDoesNotInventCalibratedThetaFromNominalDifficulty() throws {
        let anchor = assessmentDescriptor(id: "anchor", difficulty: 0.5)
        let easy = assessmentDescriptor(id: "easy", difficulty: 0.25)
        let hard = assessmentDescriptor(id: "hard", difficulty: 0.75)
        let initial = NFAdaptiveAssessmentState().appending(anchor)
        let afterCorrect = initial.recordingResponse(to: anchor, isCorrect: true)
        let afterIncorrect = initial.recordingResponse(to: anchor, isCorrect: false)

        let correctNext = try XCTUnwrap(NFAssessmentSelectionEngine.selectNext(
            from: [easy, hard],
            block: .numericalFluency,
            role: .baseline,
            state: afterCorrect,
            exposureLedger: NFHoldoutExposureLedger(),
            tieBreakSeed: 19
        ))
        let incorrectNext = try XCTUnwrap(NFAssessmentSelectionEngine.selectNext(
            from: [easy, hard],
            block: .numericalFluency,
            role: .baseline,
            state: afterIncorrect,
            exposureLedger: NFHoldoutExposureLedger(),
            tieBreakSeed: 19
        ))

        XCTAssertEqual(afterCorrect.theta, 0)
        XCTAssertEqual(afterIncorrect.theta, 0)
        XCTAssertEqual(correctNext.id, incorrectNext.id, "Legacy floats do not support a calibrated response-based selector.")
        XCTAssertEqual(afterCorrect.uncertainty, initial.uncertainty)
        XCTAssertEqual(afterIncorrect.uncertainty, initial.uncertainty)
    }

    func testRecordingAssessmentResponseIsIdempotent() {
        let item = assessmentDescriptor(id: "once", difficulty: 0.5)
        let once = NFAdaptiveAssessmentState().appending(item).recordingResponse(to: item, credit: 0.75)
        let replayed = once.recordingResponse(to: item, credit: 0)

        XCTAssertEqual(replayed, once)
        XCTAssertEqual(once.completedScorableItems, 1)
        XCTAssertEqual(once.accumulatedInformation, 0, "Legacy difficulty values do not establish calibrated information.")
    }

    func testAssessmentNextStepEnforcesInformationDurationAndItemCapStops() throws {
        let session = NFAssessmentEngine.makeBlockSession(
            block: .logicMetacognition,
            phase: .initialBaseline,
            profileSeed: 991
        )
        var belowMinimum = NFAssessmentEngine.initialAdaptiveState()
        for (index, descriptor) in session.items.dropLast().enumerated() {
            belowMinimum = belowMinimum
                .appending(descriptor)
                .recordingResponse(to: descriptor, credit: index.isMultiple(of: 2) ? 1 : 0)
        }
        XCTAssertNotNil(NFAssessmentEngine.nextStep(
            in: session,
            state: belowMinimum,
            activeElapsedSeconds: 0
        ).item)

        var informationComplete = NFAssessmentEngine.initialAdaptiveState()
        for (index, descriptor) in session.items.enumerated() {
            informationComplete = informationComplete
                .appending(descriptor)
                .recordingResponse(to: descriptor, credit: index.isMultiple(of: 2) ? 1 : 0)
        }
        XCTAssertTrue(session.hasSufficientEvidence(in: informationComplete))
        XCTAssertEqual(informationComplete.accumulatedInformation, 0, "Coverage completion does not manufacture psychometric information.")
        XCTAssertEqual(
            NFAssessmentEngine.nextStep(
                in: session,
                state: informationComplete,
                activeElapsedSeconds: 0
            ).stopReason,
            .targetInformationReached
        )
        XCTAssertEqual(NFAssessmentEngine.nextStep(in: session, state: informationComplete,
            activeElapsedSeconds: session.maximumDurationSeconds + 1).stopReason, .targetInformationReached,
            "Completing a valid final response does not erase sufficient coverage when the learner crosses the sitting target.")

        XCTAssertEqual(
            NFAssessmentEngine.nextStep(
                in: session,
                state: NFAdaptiveAssessmentState(),
                activeElapsedSeconds: session.maximumDurationSeconds
            ).stopReason,
            .maximumActiveDurationReached
        )

        let atCap = NFAdaptiveAssessmentState(
            completedItemIDs: Set((0..<session.itemCap).map { "completed-\($0)" })
        )
        XCTAssertEqual(
            NFAssessmentEngine.nextStep(in: session, state: atCap, activeElapsedSeconds: 0).stopReason,
            .itemCapReached
        )
    }

    func testAssessmentDoesNotStartAnItemThatCannotFitRemainingActiveTime() {
        let session = NFAssessmentEngine.makeBlockSession(
            block: .numericalFluency,
            phase: .initialBaseline,
            profileSeed: 772
        )
        let shortest = session.candidatePool.map(\.estimatedDurationSeconds).min()!
        let step = NFAssessmentEngine.nextStep(
            in: session,
            state: NFAdaptiveAssessmentState(),
            activeElapsedSeconds: session.maximumDurationSeconds - shortest + 1
        )

        XCTAssertNil(step.item)
        XCTAssertEqual(step.stopReason, .maximumActiveDurationReached)
        let lacksConfidenceOverhead = NFAssessmentEngine.nextStep(in: session,
            state: NFAdaptiveAssessmentState(),
            activeElapsedSeconds: session.maximumDurationSeconds - shortest)
        XCTAssertNil(lacksConfidenceOverhead.item,
            "A protected item must reserve its response estimate plus six seconds for confidence interaction.")
    }

    func testAdaptiveReplayIsDeterministicForDurableOutcomes() {
        let session = NFAssessmentEngine.makeBlockSession(
            block: .scientificDataReasoning,
            phase: .initialBaseline,
            profileSeed: 4242
        )
        let outcomes = [true, true, false, true, false]
        let first = NFAssessmentEngine.replaying(outcomes: outcomes, in: session)
        let duplicate = NFAssessmentEngine.replaying(outcomes: outcomes, in: session)

        XCTAssertEqual(first, duplicate)
        XCTAssertEqual(first.completedScorableItems, outcomes.count)
        XCTAssertEqual(first.completedItemIDs, first.selectedItemIDs)
    }

    func testDescriptorPathReplayPreservesAdaptiveIdentityAndPartialCredit() throws {
        let session = NFAssessmentEngine.makeBlockSession(
            block: .scientificDataReasoning,
            phase: .initialBaseline,
            profileSeed: 8_181,
            selfReportedDifficulty: 0.58
        )
        let credits = [0.25, 1.0, 0.5, 0.0]
        var descriptorIDs: [String] = []
        var liveState = NFAssessmentEngine.initialAdaptiveState(selfReportedDifficulty: 0.58)

        for credit in credits {
            let descriptor = try XCTUnwrap(NFAssessmentEngine.nextStep(
                in: session,
                state: liveState,
                activeElapsedSeconds: 0
            ).item)
            descriptorIDs.append(descriptor.id)
            liveState = liveState
                .appending(descriptor)
                .recordingResponse(to: descriptor, credit: credit)
        }

        let restoredState = NFAssessmentEngine.replaying(
            credits: credits,
            descriptorIDs: descriptorIDs,
            in: session,
            selfReportedDifficulty: 0.58
        )
        let liveNext = try XCTUnwrap(NFAssessmentEngine.nextStep(
            in: session,
            state: liveState,
            activeElapsedSeconds: 0
        ).item)
        let restoredNext = try XCTUnwrap(NFAssessmentEngine.nextStep(
            in: session,
            state: restoredState,
            activeElapsedSeconds: 0
        ).item)

        XCTAssertEqual(restoredState, liveState)
        XCTAssertEqual(restoredNext, liveNext)
        XCTAssertEqual(restoredNext.templateFamily, liveNext.templateFamily)
        XCTAssertEqual(restoredNext.format, liveNext.format)
        XCTAssertEqual(restoredNext.mechanicID, liveNext.mechanicID)
        XCTAssertEqual(restoredNext.seed, liveNext.seed)
    }

    func testDailyPlanV5PreservesFrozenPreviousAndUnknownPoliciesUntilNextDay() throws {
        let now = Date(timeIntervalSince1970: 1_780_000_000)
        let profile = makeProfile(duration: 15, goals: [.spatialReasoning])
        let snapshot = NFDailySchedulingSnapshot(profile: profile, date: now)
        let fresh = NFDailyScheduler.canonicalPlan(for: snapshot, calendar: utcCalendar())
        XCTAssertEqual(fresh.policyVersion, 5)
        for version in [4, 999] {
            var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(fresh)) as? [String: Any])
            object["policyVersion"] = version
            object["id"] = "frozen-policy-\(version)"
            let frozen = try JSONDecoder().decode(NFCanonicalDailyPlan.self,
                from: JSONSerialization.data(withJSONObject: object))
            let changed = NFDailySchedulingSnapshot(profile: profile, date: now.addingTimeInterval(60), readiness: .low)
            XCTAssertEqual(NFDailyScheduler.canonicalPlan(for: changed, existingPlan: frozen, calendar: utcCalendar()), frozen)
            XCTAssertEqual(NFDailyScheduler.supportsFrozenPlanPolicy(version), version == 4)
            let tomorrow = NFDailyScheduler.canonicalPlan(
                for: NFDailySchedulingSnapshot(profile: profile, date: now.addingTimeInterval(86_400)),
                existingPlan: frozen, calendar: utcCalendar())
            XCTAssertEqual(tomorrow.policyVersion, 5)
            XCTAssertNotEqual(tomorrow.id, frozen.id)
            if version == 999 {
                XCTAssertThrowsError(try NFDailyScheduler.replacingBlock(in: frozen,
                    blockID: try XCTUnwrap(frozen.blocks.first?.id), reason: .needVariety, at: now)) {
                    XCTAssertEqual($0 as? NFPlanReplacementError, .unsupportedPolicy)
                }
            }
        }
        XCTAssertFalse(NFDailyScheduler.supportsFrozenPlanPolicy(3), "An unverified older contract must not be declared executable")
    }

    func testDailyPlanIsDeterministicAndExistingCanonicalPlanDoesNotRewrite() {
        let now = Date(timeIntervalSince1970: 1_780_000_000)
        let profile = makeProfile(duration: 15, goals: [.spatialReasoning])
        let initial = NFDailySchedulingSnapshot(profile: profile, date: now)

        let first = NFDailyScheduler.canonicalPlan(for: initial, calendar: utcCalendar())
        let duplicate = NFDailyScheduler.canonicalPlan(for: initial, calendar: utcCalendar())
        let changedHistory = NFDailySchedulingSnapshot(
            profile: profile,
            date: now.addingTimeInterval(1_800),
            attempts: (0..<20).map { index in
                makeAttempt(index: index, lab: .spatial, correct: index.isMultiple(of: 2), date: now)
            }
        )
        let preserved = NFDailyScheduler.canonicalPlan(
            for: changedHistory,
            existingPlan: first,
            calendar: utcCalendar()
        )

        XCTAssertEqual(first, duplicate)
        XCTAssertEqual(preserved, first)
        XCTAssertEqual(first.scheduledMinutes, 15)
        XCTAssertEqual(first.blocks.map(\.kind), [
            .retentionReview, .targetPractice, .targetPractice, .unseenTransfer, .confidenceReflection
        ])
        XCTAssertNoThrow(try NFDailyPlanValidator.validate(first, timingMode: profile.timingMode))
        XCTAssertEqual(first.domainPlan.id, first.id)
        XCTAssertEqual(first.domainPlan.minutes, first.scheduledMinutes)
    }

    func testDailyUnseenTransferSelectsAndPreservesAFoundationalSourceSkill() throws {
        let now = Date(timeIntervalSince1970: 1_780_000_000)
        let profile = makeProfile(duration: 15, goals: [.problemSolving])
        let transferPractice = (0..<3).map { index in
            makeAttempt(index: index, lab: .transfer, correct: true, date: now)
        }
        let plan = NFDailyScheduler.canonicalPlan(
            for: NFDailySchedulingSnapshot(
                profile: profile,
                date: now,
                attempts: transferPractice
            ),
            calendar: utcCalendar()
        )

        let canonicalTransfer = try XCTUnwrap(
            plan.blocks.first { $0.kind == .unseenTransfer }
        )
        let domainTransfer = try XCTUnwrap(
            plan.domainPlan.blocks.first { $0.id == canonicalTransfer.id }
        )

        XCTAssertNotEqual(canonicalTransfer.targetSkillID, TrainingLab.transfer.skillID)
        XCTAssertNotEqual(canonicalTransfer.priority?.lab, .transfer)
        XCTAssertEqual(domainTransfer.targetSkillID, canonicalTransfer.targetSkillID)
        XCTAssertFalse(plan.prioritySnapshot.contains { $0.lab == .transfer })
        XCTAssertFalse(
            plan.blocks
                .filter { $0.kind == .targetPractice || $0.kind == .retentionReview }
                .contains { $0.lab == .transfer || $0.targetSkillID == TrainingLab.transfer.skillID }
        )

        let replaced = try NFDailyScheduler.replacingBlock(
            in: plan,
            blockID: canonicalTransfer.id,
            reason: .needVariety,
            at: now.addingTimeInterval(60)
        )
        let replacement = try XCTUnwrap(replaced.blocks.first {
            $0.id == replaced.replacement?.replacementBlockID
        })
        XCTAssertNotEqual(replacement.targetSkillID, TrainingLab.transfer.skillID)
        XCTAssertNotEqual(replacement.priority?.lab, .transfer)
    }

    func testRollingBreadthCoversAccessibleFoundationsBeforeGoalBiasResumes() throws {
        let calendar = utcCalendar()
        let start = Date(timeIntervalSince1970: 1_780_000_000)
        let profile = makeProfile(duration: 10, goals: [.mentalMath])
        let accessibleLabs = Set(TrainingLab.allCases).subtracting([.spatial, .transfer])
        var attempts: [AttemptDTO] = []
        var selectedTargets: [TrainingLab] = []

        for activeDay in 0..<NFDailyScheduler.breadthActiveDayWindow {
            let date = try XCTUnwrap(calendar.date(byAdding: .day, value: activeDay, to: start))
            let plan = NFDailyScheduler.canonicalPlan(
                for: NFDailySchedulingSnapshot(
                    profile: profile,
                    date: date,
                    attempts: attempts,
                    accessibilityExcludedLabs: [.spatial]
                ),
                calendar: calendar
            )
            let target = try XCTUnwrap(plan.blocks.first { $0.kind == .targetPractice })

            XCTAssertEqual(plan.scheduledMinutes, 10)
            XCTAssertEqual(plan.blocks.reduce(0) { $0 + $1.minutes }, 10)
            XCTAssertTrue(accessibleLabs.contains(target.lab))
            selectedTargets.append(target.lab)
            attempts.append(makeAttempt(
                index: 100 + activeDay,
                lab: target.lab,
                correct: true,
                date: date
            ))
        }

        XCTAssertEqual(Set(selectedTargets), accessibleLabs)
        XCTAssertEqual(
            Set(selectedTargets.prefix(accessibleLabs.count)),
            accessibleLabs,
            "Coverage must complete before ordinary goal-weighted ranking resumes."
        )
        XCTAssertFalse(selectedTargets.contains(.spatial))
        XCTAssertFalse(selectedTargets.contains(.transfer))
        let goalLabFrequency = selectedTargets.filter { $0 == .mentalMath }.count
        for lab in accessibleLabs where lab != .mentalMath {
            XCTAssertGreaterThan(
                goalLabFrequency,
                selectedTargets.filter { $0 == lab }.count,
                "Goals should bias frequency after the breadth circuit is complete."
            )
        }
    }

    func testLegacyDomainPlanWithoutTargetSkillStillDecodes() throws {
        let profile = makeProfile(duration: 15, goals: [.spatialReasoning])
        let domainPlan = NFDailyScheduler.canonicalPlan(
            for: NFDailySchedulingSnapshot(
                profile: profile,
                date: Date(timeIntervalSince1970: 1_780_000_000)
            ),
            calendar: utcCalendar()
        ).domainPlan
        let encoded = try JSONEncoder().encode(domainPlan)
        var legacyObject = try XCTUnwrap(
            JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        )
        var legacyBlocks = try XCTUnwrap(legacyObject["blocks"] as? [[String: Any]])
        for index in legacyBlocks.indices {
            legacyBlocks[index].removeValue(forKey: "targetSkillID")
        }
        legacyObject["blocks"] = legacyBlocks

        let legacyData = try JSONSerialization.data(withJSONObject: legacyObject)
        let restored = try JSONDecoder().decode(DailyPlan.self, from: legacyData)

        XCTAssertEqual(restored.id, domainPlan.id)
        XCTAssertEqual(restored.blocks.map(\.id), domainPlan.blocks.map(\.id))
        XCTAssertTrue(restored.blocks.allSatisfy { $0.targetSkillID == nil })
    }

    func testExistingCanonicalPlanWinsAcrossReadinessWhileFreshLowPlanReducesLoad() {
        let now = Date(timeIntervalSince1970: 1_780_000_000)
        let profile = makeProfile(duration: 15, goals: [.mentalMath, .dataReasoning])
        let normalSnapshot = NFDailySchedulingSnapshot(
            profile: profile,
            date: now,
            readiness: .normal
        )
        let lowSnapshot = NFDailySchedulingSnapshot(
            profile: profile,
            date: now,
            readiness: .low
        )
        let normal = NFDailyScheduler.canonicalPlan(for: normalSnapshot, calendar: utcCalendar())
        let preserved = NFDailyScheduler.canonicalPlan(
            for: lowSnapshot,
            existingPlan: normal,
            calendar: utcCalendar()
        )
        let freshLow = NFDailyScheduler.canonicalPlan(
            for: lowSnapshot,
            calendar: utcCalendar()
        )

        XCTAssertEqual(normal.scheduledMinutes, 15)
        XCTAssertEqual(preserved, normal)
        XCTAssertEqual(freshLow.scheduledMinutes, 10)
        XCTAssertNotEqual(normal.id, freshLow.id)
        XCTAssertTrue(freshLow.blocks.allSatisfy { $0.reasons.contains(.userOverride) })
        XCTAssertTrue(normalSnapshot.attempts.isEmpty)
        XCTAssertTrue(lowSnapshot.attempts.isEmpty)
    }

    func testLowReadinessNeverSchedulesTimingAndMentalMathRequiresProgressionGate() {
        let now = Date(timeIntervalSince1970: 1_780_000_000)
        let speedProfile = makeProfile(
            duration: 15,
            goals: [.mentalMath],
            timingMode: .speedFocus
        )
        let low = NFDailyScheduler.canonicalPlan(
            for: NFDailySchedulingSnapshot(
                profile: speedProfile,
                date: now,
                readiness: .low,
                mentalMathTimingEligible: true
            ),
            calendar: utcCalendar()
        )
        XCTAssertTrue(low.blocks.allSatisfy { !$0.timed })

        let locked = NFDailyScheduler.canonicalPlan(
            for: NFDailySchedulingSnapshot(
                profile: speedProfile,
                date: now,
                mentalMathTimingEligible: false
            ),
            calendar: utcCalendar()
        )
        let eligible = NFDailyScheduler.canonicalPlan(
            for: NFDailySchedulingSnapshot(
                profile: speedProfile,
                date: now,
                mentalMathTimingEligible: true
            ),
            calendar: utcCalendar()
        )
        XCTAssertTrue(locked.blocks.filter { $0.priority?.lab == .mentalMath }.allSatisfy { !$0.timed })
        XCTAssertTrue(eligible.blocks.contains { $0.priority?.lab == .mentalMath && $0.timed })
    }

    func testDailyPlanAllowsExactlyOneReasonedDurationPreservingReplacement() throws {
        let profile = makeProfile(duration: 15, goals: [.mentalMath, .dataReasoning])
        let snapshot = NFDailySchedulingSnapshot(
            profile: profile,
            date: Date(timeIntervalSince1970: 1_780_000_000)
        )
        let plan = NFDailyScheduler.canonicalPlan(for: snapshot, calendar: utcCalendar())
        let original = try XCTUnwrap(plan.blocks.first { $0.kind == .targetPractice })
        let replaced = try NFDailyScheduler.replacingBlock(
            in: plan,
            blockID: original.id,
            reason: .needVariety,
            at: Date(timeIntervalSince1970: 1_780_000_100)
        )
        let replacement = try XCTUnwrap(
            replaced.blocks.first { $0.id == replaced.replacement?.replacementBlockID }
        )

        XCTAssertEqual(replaced.id, plan.id)
        XCTAssertEqual(replaced.scheduledMinutes, plan.scheduledMinutes)
        XCTAssertEqual(replaced.blocks.reduce(0) { $0 + $1.minutes }, plan.scheduledMinutes)
        XCTAssertEqual(replacement.minutes, original.minutes)
        XCTAssertNotEqual(replacement.targetSkillID, original.targetSkillID)
        XCTAssertEqual(replaced.replacement?.reason, .needVariety)
        XCTAssertFalse(replaced.blocks.contains { $0.id == original.id })
        XCTAssertTrue(replacement.reasons.contains(.userOverride))
        XCTAssertThrowsError(try NFDailyScheduler.replacingBlock(
            in: replaced,
            blockID: replacement.id,
            reason: .lowerEnergy
        )) { error in
            XCTAssertEqual(error as? NFPlanReplacementError, .alreadyUsed)
        }
        XCTAssertNoThrow(try NFDailyPlanValidator.validate(replaced, timingMode: profile.timingMode))
    }

    func testPriorityUsesGoalsRetentionWeaknessUncertaintyTransferGapAndLoad() throws {
        let now = Date(timeIntervalSince1970: 1_780_000_000)
        let profile = makeProfile(duration: 15, goals: [.spatialReasoning])
        let logicRetention = NFRetentionItemState(
            id: "logic.rule.1",
            templateFamily: "logic.state.v1",
            lab: .logicDebugging,
            lastReviewedAt: now.addingTimeInterval(-20 * 86_400),
            stabilityDays: 2,
            repetitions: 2
        )
        let attempts = [
            makeAttempt(index: 0, lab: .mentalMath, correct: true, date: now.addingTimeInterval(-100)),
            makeAttempt(index: 1, lab: .mentalMath, correct: true, date: now.addingTimeInterval(-200)),
            makeAttempt(index: 2, lab: .mentalMath, correct: true, date: now.addingTimeInterval(-300)),
            makeAttempt(index: 3, lab: .mentalMath, correct: false, evidenceClass: .appliedTransfer, date: now.addingTimeInterval(-400))
        ]
        let summaries = [
            makeSummary(lab: .spatial, uncertainty: 0.65, accuracy: 0.55, lastTrained: now.addingTimeInterval(-10 * 86_400)),
            makeSummary(lab: .logicDebugging, uncertainty: 0.20, accuracy: 0.80, lastTrained: now.addingTimeInterval(-20 * 86_400)),
            makeSummary(lab: .mentalMath, uncertainty: 0.30, accuracy: 0.75, lastTrained: now.addingTimeInterval(-100))
        ]
        let snapshot = NFDailySchedulingSnapshot(
            profile: profile,
            date: now,
            skillSummaries: summaries,
            attempts: attempts,
            retentionStates: [logicRetention]
        )

        let scores = NFDailyScheduler.priorityBreakdowns(for: snapshot, calendar: utcCalendar())
        let spatial = try XCTUnwrap(scores.first { $0.lab == .spatial })
        let logic = try XCTUnwrap(scores.first { $0.lab == .logicDebugging })
        let mental = try XCTUnwrap(scores.first { $0.lab == .mentalMath })
        let plan = NFDailyScheduler.canonicalPlan(for: snapshot, calendar: utcCalendar())
        let review = try XCTUnwrap(plan.blocks.first { $0.kind == .retentionReview })

        XCTAssertEqual(spatial.normalizedGoalWeight, 1, accuracy: 1e-12)
        XCTAssertGreaterThan(spatial.weaknessRelativeToGoal, 0)
        XCTAssertGreaterThan(spatial.estimateUncertainty, logic.estimateUncertainty)
        XCTAssertGreaterThan(logic.reviewUrgency, spatial.reviewUrgency)
        XCTAssertGreaterThan(mental.transferGap, 0)
        XCTAssertGreaterThan(mental.recentLoadPenalty, 0)
        XCTAssertEqual(review.targetSkillID, TrainingLab.logicDebugging.skillID)
        XCTAssertEqual(review.reasons, [.reviewDue])

        let recomputed = 0.28 * spatial.normalizedGoalWeight
            + 0.24 * spatial.reviewUrgency
            + 0.18 * spatial.weaknessRelativeToGoal
            + 0.12 * spatial.estimateUncertainty
            + 0.10 * spatial.transferGap
            + 0.08 * spatial.varietyNeed
            - spatial.recentLoadPenalty
            - spatial.accessibilityPenalty
        XCTAssertEqual(spatial.totalPriority, recomputed, accuracy: 1e-12)
    }

    func testAccessibilityExclusionRemovesLabFromScheduledTargets() {
        let profile = makeProfile(duration: 20, goals: [.spatialReasoning])
        let snapshot = NFDailySchedulingSnapshot(
            profile: profile,
            date: Date(timeIntervalSince1970: 1_780_000_000),
            accessibilityExcludedLabs: [.spatial]
        )
        let plan = NFDailyScheduler.canonicalPlan(for: snapshot, calendar: utcCalendar())

        XCTAssertFalse(
            plan.blocks
                .filter { $0.kind == .targetPractice || $0.kind == .retentionReview }
                .contains { $0.lab == .spatial }
        )
    }

    func testDailyReviewAssignmentsCapAtFiveAndRetainTheRemainingBacklog() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let states = (0..<20).map { ordinal in
            NFRetentionItemState(id: "backlog.\(ordinal)", templateFamily: "math.review", lab: .mentalMath,
                lastReviewedAt: now.addingTimeInterval(-3 * 86_400), stabilityDays: 1, repetitions: 1)
        }
        let snapshot = NFDailySchedulingSnapshot(profile: makeProfile(duration: 20, goals: [.mentalMath]),
            date: now, retentionStates: states)
        let plan = NFDailyScheduler.canonicalPlan(for: snapshot, calendar: utcCalendar())
        let review = try XCTUnwrap(plan.blocks.first { $0.kind == .retentionReview })
        XCTAssertEqual(review.retentionTargets.count, 5)
        XCTAssertEqual(snapshot.retentionStates, states)
        XCTAssertEqual(NFRetentionScheduler.schedule(states: states, at: now, maximumItems: 20,
            calendar: utcCalendar()).count, 20, "Explicit review choice retains access to the backlog")
        XCTAssertEqual(NFDailyScheduler.canonicalPlan(for: snapshot, calendar: utcCalendar()), plan)
    }

    func testCompatibilityRemindersNeverTurnRawCountsOrHelpIntoRetentionRungs() throws {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        func input(_ ordinal: Int, credit: Double = 1, hintCount: Int = 0,
                   weight: Double = 1, skipped: Bool = false, format: String = "numeric") -> NFCompatibilityReminderObservation {
            let attempt = AttemptDTO(id: UUID(), itemID: "legacy.\(ordinal)", skillID: "logic.trace",
                lab: .logicDebugging, correct: credit == 1, credit: credit, confidence: .certain,
                submittedAt: start.addingTimeInterval(Double(ordinal)), evidenceClass: .practice,
                evidenceWeight: weight, responseFormatRaw: format, wasSkipped: skipped, hintCount: hintCount)
            return .init(attempt: attempt, memoryItemID: "legacy-family", templateFamily: "legacy-family",
                seed: UInt64(ordinal), representationID: "numeric")
        }
        let repeatedSuccesses = (0..<8).map { input($0) }
        let state = try XCTUnwrap(NFCompatibilityReminderPolicy.reduce(repeatedSuccesses,
            at: start.addingTimeInterval(2 * 86_400), calendar: utcCalendar()).first)
        XCTAssertEqual(state.repetitions, 1)
        XCTAssertEqual(state.stabilityDays, 1)
        XCTAssertEqual(state.lastReviewedAt, start, "Early practice must not postpone the initial reminder")
        XCTAssertEqual(state.exposedSeeds.count, 8)
        XCTAssertEqual(NFRetentionScheduler.schedule(states: [state], at: start.addingTimeInterval(2 * 86_400),
            maximumItems: 1, calendar: utcCalendar()).count, 1)
        let unsupported = (0..<8).map { input($0, credit: 0) }
            + [input(9, hintCount: 1), input(10, weight: 0), input(11, skipped: true),
               input(12, format: "selfCheck"), input(13, format: "revealed"), input(14, credit: .nan)]
        XCTAssertTrue(NFCompatibilityReminderPolicy.reduce(unsupported,
            at: start.addingTimeInterval(2 * 86_400), calendar: utcCalendar()).isEmpty)
    }

    func testCompatibilityReminderDueRefreshStaysOneDayAndFamiliarOrEarlyWorkDoesNotPostpone() throws {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        func input(_ day: Double, semantic: String) -> NFCompatibilityReminderObservation {
            let attempt = AttemptDTO(id: UUID(), itemID: "item.\(day)", skillID: "logic.trace",
                lab: .logicDebugging, correct: true, confidence: nil,
                submittedAt: start.addingTimeInterval(day * 86_400), evidenceClass: .retention, evidenceWeight: 1)
            return .init(attempt: attempt, memoryItemID: "legacy-family", templateFamily: "legacy-family",
                seed: UInt64(day * 10), representationID: "numeric", semanticID: semantic)
        }
        let original = input(0, semantic: "original")
        let early = input(0.5, semantic: "early")
        let familiarDue = input(1, semantic: "original")
        let dueFresh = input(2, semantic: "fresh")
        let earlyAfterRefresh = input(2.5, semantic: "later")
        let now = start.addingTimeInterval(3 * 86_400)
        let before = try XCTUnwrap(NFCompatibilityReminderPolicy.reduce([familiarDue, early, original],
            at: now, calendar: utcCalendar()).first)
        XCTAssertEqual(before.lastReviewedAt, start)
        let inputs = [original, early, familiarDue, dueFresh, earlyAfterRefresh]
        let state = try XCTUnwrap(NFCompatibilityReminderPolicy.reduce(inputs,
            at: now, calendar: utcCalendar()).first)
        XCTAssertEqual(state.lastReviewedAt, dueFresh.submittedAt)
        XCTAssertEqual(state.repetitions, 1)
        XCTAssertEqual(NFRetentionScheduler.nextReviewDate(for: state, after: dueFresh.submittedAt,
            calendar: utcCalendar()), now)
        XCTAssertEqual(NFCompatibilityReminderPolicy.reduce(Array(inputs.reversed()) + [original],
            at: now, calendar: utcCalendar()), [state])
    }

    func testCompatibilityReminderRejectsFuturePersonalProtectedAndConflictingIdentityInputs() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let id = UUID()
        func input(_ lane: EvidenceClass, credit: Double = 1, date: Date? = nil) -> NFCompatibilityReminderObservation {
            .init(attempt: AttemptDTO(id: id, itemID: "legacy", skillID: "logic.trace", lab: .logicDebugging,
                correct: credit == 1, credit: credit, confidence: nil, submittedAt: date ?? now,
                evidenceClass: lane, evidenceWeight: 1), memoryItemID: "legacy-family",
                templateFamily: "legacy-family", seed: 3, representationID: nil)
        }
        XCTAssertTrue(NFCompatibilityReminderPolicy.reduce([input(.documentPractice), input(.assessmentHoldout)],
            at: now, calendar: utcCalendar()).isEmpty)
        XCTAssertTrue(NFCompatibilityReminderPolicy.reduce([input(.practice), input(.practice, credit: 0)],
            at: now, calendar: utcCalendar()).isEmpty)
        XCTAssertTrue(NFCompatibilityReminderPolicy.reduce([input(.practice, date: now.addingTimeInterval(1))],
            at: now, calendar: utcCalendar()).isEmpty)
    }

    func testRetentionScheduleUsesPredictedMemoryAndAlternateSeeds() throws {
        let now = Date(timeIntervalSince1970: 1_780_000_000)
        let older = NFRetentionItemState(
            id: "older",
            templateFamily: "math.percent.v1",
            lab: .mentalMath,
            lastReviewedAt: now.addingTimeInterval(-8 * 86_400),
            stabilityDays: 2,
            repetitions: 2,
            exposedSeeds: [100, 101],
            lastRepresentationID: "equation"
        )
        let newer = NFRetentionItemState(
            id: "newer",
            templateFamily: "science.claim.v1",
            lab: .scientificReasoning,
            lastReviewedAt: now.addingTimeInterval(-3 * 86_400),
            stabilityDays: 3,
            repetitions: 1,
            exposedSeeds: [200],
            lastRepresentationID: "table"
        )
        let stable = NFRetentionItemState(
            id: "stable",
            templateFamily: "logic.trace.v1",
            lab: .logicDebugging,
            lastReviewedAt: now.addingTimeInterval(-3_600),
            stabilityDays: 30,
            repetitions: 5
        )

        let first = NFRetentionScheduler.schedule(states: [stable, newer, older], at: now, maximumItems: 3, calendar: utcCalendar())
        let duplicate = NFRetentionScheduler.schedule(states: [older, stable, newer], at: now, maximumItems: 3, calendar: utcCalendar())

        XCTAssertEqual(first, duplicate)
        XCTAssertEqual(first.map(\.memoryItemID), ["older", "newer"])
        let olderAssignment = try XCTUnwrap(first.first)
        XCTAssertFalse(older.exposedSeeds.contains(olderAssignment.alternateSeed))
        XCTAssertFalse(olderAssignment.requiresRepresentationShift, "A cosmetic format change cannot establish comparable retention.")

        let success = NFRetentionScheduler.updatedState(
            older,
            after: NFRetentionReviewOutcome(
                reviewedAt: now,
                correct: true,
                confidence: .fairlyConfident,
                itemDifficulty: 0.6,
                seed: olderAssignment.alternateSeed,
                representationID: "graph"
            ),
            calendar: utcCalendar()
        )
        XCTAssertGreaterThan(success.stabilityDays, older.stabilityDays)
        XCTAssertTrue(success.exposedSeeds.contains(olderAssignment.alternateSeed))
        XCTAssertGreaterThan(NFRetentionScheduler.nextReviewDate(for: success, after: now, calendar: utcCalendar()), now)
    }

    func testRetentionCalendarIsExplicitAcrossDSTAndPropagatesIntoTheCanonicalPlanner() throws {
        let formatter = ISO8601DateFormatter()
        let reviewed = try XCTUnwrap(formatter.date(from: "2026-03-07T17:00:00Z"))
        let now = try XCTUnwrap(formatter.date(from: "2026-03-08T16:30:00Z"))
        var toronto = Calendar(identifier: .gregorian)
        toronto.timeZone = try XCTUnwrap(TimeZone(identifier: "America/Toronto"))
        let utc = utcCalendar()
        let state = NFRetentionItemState(id: "explicit-local-day", templateFamily: "math.percent.v1",
            lab: .mentalMath, lastReviewedAt: reviewed, stabilityDays: 1, repetitions: 1,
            exposedSeeds: [7], lastRepresentationID: "equation")
        // Noon-to-noon crosses the actual March DST transition:23 hours in
        // Toronto,24 hours in UTC. Both are intentional explicit policies.
        XCTAssertEqual(NFRetentionScheduler.nextReviewDate(for: state, after: reviewed, calendar: toronto),
            formatter.date(from: "2026-03-08T16:00:00Z"))
        XCTAssertEqual(NFRetentionScheduler.nextReviewDate(for: state, after: reviewed, calendar: utc),
            formatter.date(from: "2026-03-08T17:00:00Z"))
        XCTAssertEqual(NFRetentionScheduler.predictedRetention(for: state, at: now, calendar: toronto), 0)
        XCTAssertEqual(NFRetentionScheduler.predictedRetention(for: state, at: now, calendar: utc), 1)
        XCTAssertGreaterThan(NFRetentionScheduler.urgency(for: state, at: now, calendar: toronto), 1)
        XCTAssertEqual(NFRetentionScheduler.urgency(for: state, at: now, calendar: utc), 0)
        let due = NFRetentionScheduler.schedule(states: [state], at: now, maximumItems: 1, calendar: toronto)
        XCTAssertEqual(due.map(\.memoryItemID), [state.id])
        XCTAssertTrue(NFRetentionScheduler.schedule(states: [state], at: now, maximumItems: 1, calendar: utc).isEmpty)
        let outcome = NFRetentionReviewOutcome(reviewedAt: now, correct: true, confidence: .certain,
            itemDifficulty: 0.5, seed: 8, representationID: "equation")
        XCTAssertEqual(NFRetentionScheduler.updatedState(state, after: outcome, calendar: toronto).repetitions, 2)
        XCTAssertEqual(NFRetentionScheduler.updatedState(state, after: outcome, calendar: utc).repetitions, 1)
        let snapshot = NFDailySchedulingSnapshot(profile: makeProfile(duration: 15, goals: [.mentalMath]),
            date: now, retentionStates: [state])
        let localScores = NFDailyScheduler.priorityBreakdowns(for: snapshot, calendar: toronto)
        let utcScores = NFDailyScheduler.priorityBreakdowns(for: snapshot, calendar: utc)
        XCTAssertEqual(localScores.first { $0.lab == .mentalMath }?.reviewUrgency, 1)
        XCTAssertEqual(utcScores.first { $0.lab == .mentalMath }?.reviewUrgency, 0)
        let localPlan = NFDailyScheduler.canonicalPlan(for: snapshot, calendar: toronto)
        let utcPlan = NFDailyScheduler.canonicalPlan(for: snapshot, calendar: utc)
        XCTAssertEqual(localPlan.prioritySnapshot, localScores)
        XCTAssertEqual(utcPlan.prioritySnapshot, utcScores)
        XCTAssertEqual(localPlan.blocks.flatMap(\.retentionItemIDs), [state.id])
        XCTAssertTrue(utcPlan.blocks.flatMap(\.retentionItemIDs).isEmpty)
        XCTAssertEqual(NFDailyScheduler.canonicalPlan(for: snapshot, existingPlan: localPlan, calendar: toronto), localPlan)
    }

    func testCanonicalPlanCarriesRetentionTargetsAndDecodesLegacyItemIDs() throws {
        let now = Date(timeIntervalSince1970: 1_780_000_000)
        let profile = makeProfile(duration: 15, goals: [.programming])
        let state = NFRetentionItemState(
            id: "nf.fallback.logicDebugging.practice.v3.state-trace",
            templateFamily: "nf.fallback.logicDebugging.practice.v3",
            lab: .logicDebugging,
            lastReviewedAt: now.addingTimeInterval(-20 * 86_400),
            stabilityDays: 2,
            repetitions: 2,
            exposedSeeds: [19, 29],
            lastRepresentationID: NFAssessmentItemFormat.stateTrace.rawValue
        )
        let snapshot = NFDailySchedulingSnapshot(
            profile: profile,
            date: now,
            retentionStates: [state]
        )
        let plan = NFDailyScheduler.canonicalPlan(for: snapshot, calendar: utcCalendar())
        let review = try XCTUnwrap(plan.blocks.first { $0.kind == .retentionReview })
        let assignment = try XCTUnwrap(NFRetentionScheduler.schedule(
            states: [state],
            at: now,
            maximumItems: 7,
            calendar: utcCalendar()
        ).first)

        XCTAssertEqual(review.retentionTargets, [assignment.reviewTarget])
        XCTAssertEqual(review.retentionItemIDs, [assignment.memoryItemID])
        XCTAssertEqual(plan.domainPlan.id, plan.id)

        let encoded = try JSONEncoder().encode(plan)
        var legacyObject = try XCTUnwrap(
            JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        )
        var legacyBlocks = try XCTUnwrap(legacyObject["blocks"] as? [[String: Any]])
        for index in legacyBlocks.indices {
            legacyBlocks[index].removeValue(forKey: "retentionTargets")
        }
        legacyObject["blocks"] = legacyBlocks
        let legacyData = try JSONSerialization.data(withJSONObject: legacyObject)
        let restored = try JSONDecoder().decode(NFCanonicalDailyPlan.self, from: legacyData)
        let restoredReview = try XCTUnwrap(restored.blocks.first { $0.kind == .retentionReview })

        XCTAssertEqual(restored.id, plan.id, "Adding typed targets must not create a new canonical identity")
        XCTAssertEqual(restoredReview.retentionItemIDs, review.retentionItemIDs)
        XCTAssertEqual(restoredReview.retentionTargets.map(\.memoryItemID), review.retentionItemIDs)
        XCTAssertEqual(restored.domainPlan.id, plan.id)
    }

    func testRetentionFactoryUsesScheduledMechanicSeedAndRepresentationShift() throws {
        let sourceRequest = SessionRequest(
            lab: .mentalMath,
            source: .focused,
            seed: 0xA11C_E001,
            evidenceClass: .practice
        )
        let source = NFDeterministicSessionExerciseFactory.makeExercise(
            request: sourceRequest,
            index: 0,
            assessmentDescriptor: nil
        )
        let firstTarget = NFRetentionReviewTarget(
            memoryItemID: source.templateID,
            templateFamily: source.templateFamily,
            alternateSeed: 0xA11C_E002,
            requiresRepresentationShift: false,
            priorRepresentationID: NFRetentionRepresentation.identifier(for: source)
        )
        let firstRequest = SessionRequest(
            lab: source.lab,
            source: .today,
            seed: 17,
            evidenceClass: .retention,
            retentionTargets: [firstTarget]
        )
        let first = NFDeterministicSessionExerciseFactory.makeExercise(
            request: firstRequest,
            index: 0,
            assessmentDescriptor: nil
        )
        let duplicate = NFDeterministicSessionExerciseFactory.makeExercise(
            request: firstRequest,
            index: 0,
            assessmentDescriptor: nil
        )
        let alternateTarget = NFRetentionReviewTarget(
            memoryItemID: source.templateID,
            templateFamily: source.templateFamily,
            alternateSeed: 0xA11C_E003,
            requiresRepresentationShift: false,
            priorRepresentationID: NFRetentionRepresentation.identifier(for: source)
        )
        let alternate = NFDeterministicSessionExerciseFactory.makeExercise(
            request: SessionRequest(
                lab: source.lab,
                source: .today,
                seed: 17,
                evidenceClass: .retention,
                retentionTargets: [alternateTarget]
            ),
            index: 0,
            assessmentDescriptor: nil
        )

        XCTAssertEqual(first, duplicate)
        XCTAssertNil(first.availabilityReason)
        XCTAssertNotNil(retentionMechanicToken(source.templateID), "The oracle must recognize the actual shipped edition")
        XCTAssertEqual(retentionMechanicToken(first.templateID), retentionMechanicToken(source.templateID))
        XCTAssertNotEqual(first.id, alternate.id, "The scheduled alternate seed must affect generated identity")

        let shiftedTarget = NFRetentionReviewTarget(
            memoryItemID: source.templateID,
            templateFamily: source.templateFamily,
            alternateSeed: 0xA11C_E004,
            requiresRepresentationShift: true,
            priorRepresentationID: NFRetentionRepresentation.identifier(for: source)
        )
        let shifted = NFDeterministicSessionExerciseFactory.makeExercise(
            request: SessionRequest(
                lab: source.lab,
                source: .today,
                seed: 17,
                evidenceClass: .retention,
                retentionTargets: [shiftedTarget]
            ),
            index: 0,
            assessmentDescriptor: nil
        )
        XCTAssertNotEqual(
            NFRetentionRepresentation.identifier(for: shifted),
            shiftedTarget.priorRepresentationID
        )
        XCTAssertEqual(shifted.lab, source.lab)
        XCTAssertEqual(shifted.purpose, .retention)
    }

    func testRetentionFactoryHonorsKnownV3AndV4MechanicsAndRejectsUnknownTarget() throws {
        let source = try NFFallbackExerciseGenerator.generate(.init(seed: 20260905, index: 0,
            lab: .mentalMath, purpose: .practice, localeIdentifier: "en",
            preferredAssessmentMechanicID: "fixture.fallback-variant-1"))
        let slug = try XCTUnwrap(retentionMechanicToken(source.templateID))
        for edition in ["v3", "v4"] {
            let memoryID = "nf.fallback.mentalMath.practice.\(edition).\(slug)"
            for family in ["nf.fallback.mentalMath.practice.\(edition)", memoryID] {
                let target = NFRetentionReviewTarget(memoryItemID: memoryID, templateFamily: family,
                    alternateSeed: 20260906, requiresRepresentationShift: false, priorRepresentationID: "numeric")
                let request = SessionRequest(lab: .mentalMath, source: .focused, seed: 123,
                    evidenceClass: .retention, requestedItemCount: 1, retentionTargets: [target])
                let exercise = NFDeterministicSessionExerciseFactory.makeExercise(request: request, index: 0,
                    assessmentDescriptor: nil)
                XCTAssertNil(exercise.availabilityReason)
                XCTAssertEqual(retentionMechanicToken(exercise.templateID), slug)
                XCTAssertTrue(exercise.templateID.contains(".v4."), "This is a new review, not a reinterpreted saved snapshot")
                XCTAssertEqual(request.retentionTargets, [target])
            }
        }
        let unknown = NFRetentionReviewTarget(memoryItemID: "future.unavailable.objective",
            templateFamily: "future.unavailable.family", alternateSeed: 20260906,
            requiresRepresentationShift: false, priorRepresentationID: "numeric")
        let unavailable = NFDeterministicSessionExerciseFactory.makeExercise(request: SessionRequest(
            lab: .mentalMath, source: .focused, seed: 123, evidenceClass: .retention,
            requestedItemCount: 1, retentionTargets: [unknown]), index: 0, assessmentDescriptor: nil)
        XCTAssertNotNil(unavailable.availabilityReason)
        XCTAssertEqual(NFExerciseScoringEngine.score(.numeric(.init(value: "0", unit: nil)), for: unavailable).outcome, .invalidItem)
    }

    func testRetentionFiniteMechanicExhaustionCannotSubstituteAnotherLogicActivity() throws {
        let source = try NFFallbackExerciseGenerator.generate(.init(seed: 20260905, index: 0,
            lab: .logicDebugging, purpose: .practice, localeIdentifier: "en",
            preferredAssessmentMechanicID: "fixture.fallback-variant-1"))
        XCTAssertEqual(retentionMechanicToken(source.templateID), "conditions.divisibility")
        let target = NFRetentionReviewTarget(memoryItemID: source.templateID, templateFamily: source.templateFamily,
            alternateSeed: 20260906, requiresRepresentationShift: false, priorRepresentationID: "singleChoice")
        let request = SessionRequest(lab: .logicDebugging, source: .focused, seed: 123,
            evidenceClass: .retention, requestedItemCount: 1, retentionTargets: [target])
        let first = NFDeterministicSessionExerciseFactory.makeExercise(request: request, index: 0, assessmentDescriptor: nil)
        XCTAssertNil(first.availabilityReason)
        XCTAssertEqual(retentionMechanicToken(first.templateID), "conditions.divisibility")
        let exhausted = NFDeterministicSessionExerciseFactory.makeExercise(request: request, index: 0,
            assessmentDescriptor: nil, excludingContentFingerprints: [NFQuestionFingerprint.fingerprint(for: first)])
        XCTAssertNotNil(exhausted.availabilityReason)
        XCTAssertEqual(request.retentionTargets, [target], "Failure cannot change the accepted target")
    }

    func testFocusedSessionMechanicPinsRequestedSubskillVariant() {
        let request = SessionRequest(
            lab: .logicDebugging,
            source: .focused,
            seed: 0xF0C0_5001,
            evidenceClass: .practice,
            field: .computing,
            topic: "Edge cases",
            mechanicID: "focused.logicDebugging.fallback-variant-5"
        )

        let exercise = NFDeterministicSessionExerciseFactory.makeExercise(
            request: request,
            index: 0,
            assessmentDescriptor: nil
        )

        XCTAssertTrue(exercise.templateID.contains("debug.boundary-last-element"), exercise.templateID)
        XCTAssertEqual(exercise.sourceContext.topic, "Edge cases")
        XCTAssertEqual(exercise.lab, .logicDebugging)
        XCTAssertEqual(exercise.purpose, .practice)
    }

    func testWeeklyTransferMissionIsStableDeferrableAndCompletable() throws {
        let calendar = utcCalendar()
        let now = Date(timeIntervalSince1970: 1_780_000_000)
        let profileID = UUID(uuidString: "D505144C-1DA3-4EB6-A511-3E9F8F9CB321")!
        let candidates = [
            NFWeeklyTransferCandidate(lab: .quantitative, skillID: "skill.quantitative", priority: 0.8, transferGap: 0.6),
            NFWeeklyTransferCandidate(lab: .logicDebugging, skillID: "skill.logic", priority: 0.7, transferGap: 0.5),
            NFWeeklyTransferCandidate(lab: .spatial, skillID: "skill.spatial", priority: 0.9, transferGap: 0.2)
        ]
        let mission = try XCTUnwrap(
            NFWeeklyTransferScheduler.mission(
                profileID: profileID,
                date: now,
                activeDaysThisWeek: 2,
                candidates: candidates,
                calendar: calendar
            )
        )
        let duplicate = NFWeeklyTransferScheduler.mission(
            profileID: profileID,
            date: now.addingTimeInterval(3_600),
            activeDaysThisWeek: 3,
            candidates: candidates.reversed(),
            calendar: calendar
        )

        XCTAssertEqual(duplicate, mission)
        XCTAssertEqual(mission.labs, [.quantitative, .logicDebugging])
        XCTAssertEqual(Set(mission.labs).count, 2)
        XCTAssertEqual(mission.evidenceClass, .appliedTransfer)
        XCTAssertGreaterThanOrEqual(mission.requiredTransferDimensions.count, 3)
        XCTAssertEqual(mission.exerciseTransferBrief, NFExerciseTransferBrief(
            missionID: mission.id,
            seed: mission.seed,
            kind: mission.kind,
            labs: mission.labs,
            skillIDs: mission.skillIDs,
            requiredDimensions: mission.requiredTransferDimensions
        ))

        let changedCandidates = [
            NFWeeklyTransferCandidate(lab: .spatial, skillID: "skill.spatial", priority: 1, transferGap: 1),
            NFWeeklyTransferCandidate(lab: .scientificReasoning, skillID: "skill.science", priority: 0.9, transferGap: 0.9)
        ]
        let pinnedState = NFWeeklyTransferState().pinning(mission)
        XCTAssertEqual(
            NFWeeklyTransferScheduler.mission(
                profileID: profileID,
                date: now.addingTimeInterval(6 * 3_600),
                activeDaysThisWeek: 4,
                candidates: changedCandidates,
                state: pinnedState,
                calendar: calendar
            ),
            mission,
            "New evidence must not rewrite a materialized weekly mission."
        )

        let deferred = NFWeeklyTransferState().deferring(
            missionID: mission.id,
            until: now.addingTimeInterval(86_400)
        )
        XCTAssertNil(
            NFWeeklyTransferScheduler.mission(
                profileID: profileID,
                date: now,
                activeDaysThisWeek: 2,
                candidates: candidates,
                state: deferred,
                calendar: calendar
            )
        )
        let completed = NFWeeklyTransferState().completing(missionID: mission.id)
        XCTAssertNil(
            NFWeeklyTransferScheduler.mission(
                profileID: profileID,
                date: now,
                activeDaysThisWeek: 2,
                candidates: candidates,
                state: completed,
                calendar: calendar
            )
        )
    }

    private func makeProfile(
        duration: Int,
        goals: Set<TrainingGoal>,
        timingMode: TimingMode = .adaptive
    ) -> ProfileSnapshot {
        ProfileSnapshot(
            id: UUID(uuidString: "6C11256C-900E-46E6-A93A-8CE2B7F09259")!,
            stage: .undergraduate,
            fields: [.mathematics, .computing],
            goals: goals,
            dailyDuration: duration,
            timingMode: timingMode,
            aiMode: .disabled,
            iCloudEnabled: false
        )
    }

    private func makeAttempt(
        index: Int,
        lab: TrainingLab,
        correct: Bool,
        evidenceClass: EvidenceClass = .practice,
        date: Date
    ) -> AttemptDTO {
        AttemptDTO(
            id: UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", index + 1))!,
            skillID: lab.skillID,
            lab: lab,
            correct: correct,
            confidence: .fairlyConfident,
            submittedAt: date.addingTimeInterval(Double(index)),
            evidenceClass: evidenceClass,
            evidenceWeight: 1
        )
    }

    private func makeSummary(
        lab: TrainingLab,
        uncertainty: Double,
        accuracy: Double,
        lastTrained: Date
    ) -> SkillSummary {
        SkillSummary(
            id: lab.skillID,
            lab: lab,
            theta: 0,
            uncertainty: uncertainty,
            evidenceCount: 10,
            accuracy: accuracy,
            status: .developing,
            calibrationBias: nil,
            lastTrained: lastTrained
        )
    }

    private func assessmentDescriptor(
        id: String,
        difficulty: Double
    ) -> NFAssessmentItemDescriptor {
        NFAssessmentItemDescriptor(
            id: id,
            templateFamily: "nf.assessment.baseline.test",
            seed: NFStableDeterminism.hash64(id),
            block: .numericalFluency,
            role: .baseline,
            lab: .mentalMath,
            dimension: .mentalArithmetic,
            subskillID: "same-subskill",
            format: .numericEntry,
            mechanicID: "same-mechanic",
            difficulty: difficulty,
            expectedInformation: 1,
            estimatedDurationSeconds: 20
        )
    }

    private func retentionMechanicToken(_ templateID: String) -> String? {
        let components = templateID.split(separator: ".", omittingEmptySubsequences: false)
        guard let version = components.firstIndex(where: { $0 == "v3" || $0 == "v4" }),
              version + 1 < components.count else { return nil }
        return components.dropFirst(version + 1).joined(separator: ".")
    }

    private func utcCalendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        calendar.locale = Locale(identifier: "en_US_POSIX")
        return calendar
    }
}

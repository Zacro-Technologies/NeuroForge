import Foundation
import Darwin
import SwiftData
import XCTest

@testable import NeuroForge

final class FocusedQuizRotationIntegrationTests: XCTestCase {
    @MainActor
    func testAbandoningMixedQuizReservesDisjointQuestionsForRelaunch() throws {
        let rotationStore = FocusedQuizInMemoryRotationStore()
        let (store, container) = try makeStore(rotationStore: rotationStore)
        defer { _ = container }

        XCTAssertTrue(store.beginSession(
            lab: .spatial,
            source: .focused,
            requestedItemCount: 10,
            seedOverride: 42, reservationStrategy: .fixedBlock
        ))
        let first = try XCTUnwrap(store.activeSessionRequest)
        XCTAssertEqual(first.offlineQuestionOrdinals.count, 10)

        // Ending a focused quiz without saving an attempt must not put its
        // reservation back at the front of the lane.
        store.activeSessionRequest = nil
        XCTAssertTrue(store.beginSession(
            lab: .spatial,
            source: .focused,
            requestedItemCount: 10,
            seedOverride: 42, reservationStrategy: .fixedBlock
        ))
        let second = try XCTUnwrap(store.activeSessionRequest)

        XCTAssertEqual(second.offlineQuestionOrdinals.count, 10)
        XCTAssertTrue(
            Set(first.offlineQuestionOrdinals).isDisjoint(
                with: Set(second.offlineQuestionOrdinals)
            )
        )
        XCTAssertNotEqual(first.seed, second.seed)
        XCTAssertTrue(store.attempts.isEmpty)
    }

    @MainActor
    func testOneHundredTenQuestionLaunchesCoverFullLabBankBeforeAnyRepeat() throws {
        let rotationStore = FocusedQuizInMemoryRotationStore()
        let (store, container) = try makeStore(rotationStore: rotationStore)
        defer { _ = container }

        var seen: Set<Int> = []
        let launchCount = NFOfflineQuestionBank.questionsPerLab / 10
        XCTAssertEqual(launchCount, 100)
        for launchIndex in 0..<launchCount {
            XCTAssertTrue(store.beginSession(
                lab: .quantitative,
                source: .focused,
                requestedItemCount: 10,
                seedOverride: 7, reservationStrategy: .fixedBlock
            ))
            let request = try XCTUnwrap(store.activeSessionRequest)
            XCTAssertEqual(request.offlineQuestionOrdinals.count, 10)
            XCTAssertEqual(Set(request.offlineQuestionOrdinals).count, 10)

            for ordinal in request.offlineQuestionOrdinals {
                XCTAssertTrue(
                    seen.insert(ordinal).inserted,
                    "Launch \(launchIndex) repeated offline ordinal \(ordinal) before exhausting the bank"
                )
            }
            store.activeSessionRequest = nil
        }

        XCTAssertEqual(seen, Set(0..<NFOfflineQuestionBank.questionsPerLab))
        XCTAssertTrue(store.attempts.isEmpty)

        // The next launch starts a new epoch only after all 1,000 were reserved.
        XCTAssertTrue(store.beginSession(
            lab: .quantitative,
            source: .focused,
            requestedItemCount: 10,
            seedOverride: 7, reservationStrategy: .fixedBlock
        ))
        let nextEpoch = try XCTUnwrap(store.activeSessionRequest)
        XCTAssertTrue(Set(nextEpoch.offlineQuestionOrdinals).isSubset(of: seen))
    }

    @MainActor
    func testMixedTenAndTwentyQuestionRunsGenerateUniqueQuestionFingerprints() throws {
        let rotationStore = FocusedQuizInMemoryRotationStore()
        let (store, container) = try makeStore(rotationStore: rotationStore)
        defer { _ = container }

        for itemCount in [10, 20] {
            XCTAssertTrue(store.beginSession(
                lab: .logicDebugging,
                source: .focused,
                requestedItemCount: itemCount,
                seedOverride: 99, reservationStrategy: .fixedBlock
            ))
            let request = try XCTUnwrap(store.activeSessionRequest)
            XCTAssertEqual(request.offlineQuestionOrdinals.count, itemCount)

            var fingerprints: Set<String> = []
            for index in 0..<itemCount {
                let exercise = NFDeterministicSessionExerciseFactory.makeExercise(
                    request: request,
                    index: index,
                    assessmentDescriptor: nil,
                    excludingContentFingerprints: fingerprints
                )
                let fingerprint = NFQuestionFingerprint.fingerprint(for: exercise)
                XCTAssertTrue(
                    fingerprints.insert(fingerprint).inserted,
                    "The \(itemCount)-question run repeated content at index \(index)"
                )
            }
            XCTAssertEqual(fingerprints.count, itemCount)
            store.activeSessionRequest = nil
        }
    }

    @MainActor
    func testAbandoningSelectedActivityChangesLaunchSeed() throws {
        let rotationStore = FocusedQuizInMemoryRotationStore()
        let (store, container) = try makeStore(rotationStore: rotationStore)
        defer { _ = container }
        let activity = try XCTUnwrap(
            NFDefaultContentCatalog.activities(for: .mentalMath).first
        )

        XCTAssertTrue(store.beginSession(
            lab: activity.lab,
            source: .focused,
            requestedItemCount: 10,
            seedOverride: 123_456,
            mechanicID: activity.mechanicID, reservationStrategy: .fixedBlock
        ))
        let first = try XCTUnwrap(store.activeSessionRequest)
        XCTAssertEqual(first.mechanicID, activity.mechanicID)
        XCTAssertTrue(first.offlineQuestionOrdinals.isEmpty)

        store.activeSessionRequest = nil
        XCTAssertTrue(store.beginSession(
            lab: activity.lab,
            source: .focused,
            requestedItemCount: 10,
            seedOverride: 123_456,
            mechanicID: activity.mechanicID, reservationStrategy: .fixedBlock
        ))
        let second = try XCTUnwrap(store.activeSessionRequest)

        XCTAssertNotEqual(first.seed, second.seed)
        let firstExercise = NFDeterministicSessionExerciseFactory.makeExercise(
            request: first,
            index: 0,
            assessmentDescriptor: nil
        )
        let secondExercise = NFDeterministicSessionExerciseFactory.makeExercise(
            request: second,
            index: 0,
            assessmentDescriptor: nil
        )
        XCTAssertNotEqual(
            NFQuestionFingerprint.fingerprint(for: firstExercise),
            NFQuestionFingerprint.fingerprint(for: secondExercise),
            "Abandoning a selected activity must not replay its first question"
        )
        XCTAssertTrue(store.attempts.isEmpty)
    }

    @MainActor
    func testSelectedActivitiesStayInTheirFamilyAndStopBeforeRepeatingWhenFinitePoolExhausts() throws {
        let rotationStore = FocusedQuizInMemoryRotationStore()
        let (store, container) = try makeStore(rotationStore: rotationStore)
        defer { _ = container }

        for activity in NFDefaultContentCatalog.activities {
            XCTAssertTrue(store.beginSession(
                lab: activity.lab,
                source: .focused,
                requestedItemCount: 10,
                seedOverride: 987_654,
                mechanicID: activity.mechanicID, reservationStrategy: .fixedBlock
            ), activity.id)
            let first = try XCTUnwrap(store.activeSessionRequest, activity.id)
            let firstSequence = fingerprints(for: first, itemCount: 10)
            XCTAssertEqual(Set(firstSequence).count, firstSequence.count, activity.id)
            XCTAssertFalse(firstSequence.isEmpty, activity.id)

            store.activeSessionRequest = nil
            XCTAssertTrue(store.beginSession(
                lab: activity.lab,
                source: .focused,
                requestedItemCount: 10,
                seedOverride: 987_654,
                mechanicID: activity.mechanicID, reservationStrategy: .fixedBlock
            ), activity.id)
            let second = try XCTUnwrap(store.activeSessionRequest, activity.id)
            let secondSequence = fingerprints(for: second, itemCount: 10)
            XCTAssertEqual(Set(secondSequence).count, secondSequence.count, activity.id)
            XCTAssertFalse(secondSequence.isEmpty, activity.id)

            XCTAssertNotEqual(first.seed, second.seed, activity.id)
            // A finite family may contain one semantic item. The runtime must
            // report its shortage; it cannot invent nine items by substituting
            // a different family or reusing an already displayed item.
            store.activeSessionRequest = nil
        }
    }

    @MainActor
    func testCancellingMinuteOnlyChoiceDoesNotConsumeMixedOrActivityRotation() throws {
        let activity = try XCTUnwrap(NFDefaultContentCatalog.activities(for: .mentalMath).first)
        for mechanicID in [nil, activity.mechanicID] as [String?] {
            let rotationStore = FocusedQuizInMemoryRotationStore()
            let (store, container) = try makeStore(rotationStore: rotationStore)
            defer { _ = container }
            XCTAssertTrue(store.beginSession(lab: .mentalMath, source: .focused,
                requestedMinutes: 3, seedOverride: 73, mechanicID: mechanicID, reservationStrategy: .fixedBlock))
            let proposal = try XCTUnwrap(store.activeSessionRequest)
            XCTAssertNil(proposal.offlineRotationPlan)
            XCTAssertTrue(proposal.offlineQuestionOrdinals.isEmpty)
            let runtime = NFUniversalSessionRuntime(request: proposal)
            XCTAssertTrue(runtime.durationChoiceRequired)
            XCTAssertFalse(runtime.checkpointDraft(store: store))
            XCTAssertNil(try rotationStore.load())
            store.activeSessionRequest = nil // The duration-choice Close action.
            XCTAssertNil(try rotationStore.load())
            XCTAssertTrue(store.localSessions.archive.sessions.isEmpty)
            XCTAssertTrue(store.beginSession(lab: .mentalMath, source: .focused,
                requestedItemCount: 5, seedOverride: 73, mechanicID: mechanicID, reservationStrategy: .fixedBlock))
            let accepted = try XCTUnwrap(store.activeSessionRequest?.offlineRotationPlan)
            XCTAssertEqual(accepted.reservationOrdinal, 0)
            XCTAssertEqual(accepted.items.count, 5)
            XCTAssertEqual(store.localSessions.archive.offlineRotationLedger?.scopes.values.first?.cursor, 5)
            XCTAssertNil(try rotationStore.load(), "The legacy store becomes read-only")
        }
    }

    @MainActor
    func testAcceptedCountAlternativeUsesCanonicalFiveQuestionPlanAndRetainsLaunchContract() throws {
        let rotationStore = FocusedQuizInMemoryRotationStore()
        let (store, container) = try makeStore(rotationStore: rotationStore)
        defer { _ = container }
        XCTAssertTrue(store.beginSession(lab: .mentalMath, source: .focused, requestedMinutes: 24,
            field: .general, topic: "Preserved topic", recommendationRationale: "Preserved rationale",
            targetDifficulty: 0.4, seedOverride: 81, planID: "origin-plan", planBlockID: "origin-block",
            isTimed: false, launchLocaleIdentifier: "ja",
            additionalQuarantinedItemIDs: ["quarantined-original"],
            additionalQuarantinedAssessmentDescriptorIDs: ["quarantined-descriptor"], reservationStrategy: .fixedBlock))
        let originID = UUID()
        store.activeSessionRequest?.repairOriginAttemptID = originID
        store.activeSessionRequest?.repairSemanticExclusions = ["original-repair-semantic"]
        let proposal = try XCTUnwrap(store.activeSessionRequest)
        let runtime = NFUniversalSessionRuntime(request: proposal)
        XCTAssertTrue(runtime.durationChoiceRequired)
        XCTAssertNil(try rotationStore.load())
        runtime.startCountBasedAlternative(store: store)
        let accepted = try XCTUnwrap(store.activeSessionRequest)
        let plan = try XCTUnwrap(accepted.offlineRotationPlan)
        XCTAssertNotEqual(accepted.id, proposal.id)
        XCTAssertEqual(accepted.source, proposal.source)
        XCTAssertEqual(accepted.requestedItemCount, 5); XCTAssertNil(accepted.requestedMinutes)
        XCTAssertEqual(accepted.offlineQuestionOrdinals.count, 5)
        XCTAssertEqual(plan.items.count, 5); XCTAssertEqual(plan.reservationOrdinal, 0)
        XCTAssertEqual(accepted.offlineQuestionOrdinals, plan.items.compactMap {
            NFOfflineQuestionBank.ordinal(forQuestionID: $0.questionID, lab: .mentalMath)
        })
        XCTAssertEqual(accepted.localeIdentifier, "ja")
        XCTAssertEqual(accepted.field, proposal.field); XCTAssertEqual(accepted.topic, proposal.topic)
        XCTAssertEqual(accepted.recommendationRationale, proposal.recommendationRationale)
        XCTAssertEqual(accepted.targetDifficulty, proposal.targetDifficulty)
        XCTAssertEqual(accepted.planID, proposal.planID); XCTAssertEqual(accepted.planBlockID, proposal.planBlockID)
        XCTAssertEqual(accepted.repairOriginAttemptID, originID)
        XCTAssertEqual(accepted.repairSemanticExclusions, ["original-repair-semantic"])
        XCTAssertTrue(accepted.quarantinedItemIDs.contains("quarantined-original"))
        XCTAssertTrue(accepted.quarantinedAssessmentDescriptorIDs.contains("quarantined-descriptor"))
        XCTAssertFalse(NFUniversalSessionRuntime(request: accepted).durationChoiceRequired)
        XCTAssertEqual(store.localSessions.archive.offlineRotationLedger?.scopes.values.first?.cursor, 5)
            XCTAssertNil(try rotationStore.load(), "The legacy store becomes read-only")
    }

    @MainActor
    func testCountAlternativeBootstrapFailureKeepsOriginalChoiceAndRetriesOnce() throws {
        let rotationStore = FocusedQuizInMemoryRotationStore()
        let (store, container) = try makeStore(rotationStore: rotationStore)
        defer { _ = container }
        XCTAssertTrue(store.beginSession(lab: .spatial, source: .focused, requestedMinutes: 3, seedOverride: 91, reservationStrategy: .fixedBlock))
        let proposal = try XCTUnwrap(store.activeSessionRequest)
        let runtime = NFUniversalSessionRuntime(request: proposal)
        rotationStore.setFailsReads(true)
        runtime.startCountBasedAlternative(store: store)
        XCTAssertEqual(store.activeSessionRequest?.id, proposal.id)
        XCTAssertTrue(runtime.durationChoiceRequired)
        XCTAssertNotNil(runtime.saveError)
        XCTAssertThrowsError(try rotationStore.load())
        XCTAssertTrue(store.localSessions.archive.sessions.isEmpty)
        rotationStore.setFailsReads(false)
        runtime.startCountBasedAlternative(store: store)
        let plan = try XCTUnwrap(store.activeSessionRequest?.offlineRotationPlan)
        XCTAssertEqual(plan.reservationOrdinal, 0); XCTAssertEqual(plan.items.count, 5)
        XCTAssertEqual(store.localSessions.archive.offlineRotationLedger?.scopes.values.first?.cursor, 5)
            XCTAssertNil(try rotationStore.load(), "The legacy store becomes read-only")
    }

    @MainActor
    func testFiveQuestionAlternativeReportsFiniteFamilyExhaustionWithoutFakeCompletion() throws {
        let rotationStore = FocusedQuizInMemoryRotationStore()
        let (store, container) = try makeStore(rotationStore: rotationStore)
        defer { _ = container }
        let activity = try XCTUnwrap(NFDefaultContentCatalog.activities.first { $0.templateSlug == "proof.order-odd-sum" })
        XCTAssertTrue(store.beginSession(lab: activity.lab, source: .focused, requestedMinutes: 3,
            seedOverride: 101, mechanicID: activity.mechanicID, reservationStrategy: .fixedBlock))
        let proposalRuntime = NFUniversalSessionRuntime(request: try XCTUnwrap(store.activeSessionRequest))
        proposalRuntime.startCountBasedAlternative(store: store)
        let accepted = try XCTUnwrap(store.activeSessionRequest)
        XCTAssertEqual(accepted.requestedItemCount, 5)
        XCTAssertEqual(accepted.offlineRotationPlan?.items.count, 5)
        let runtime = NFUniversalSessionRuntime(request: accepted)
        XCTAssertTrue(runtime.checkpointDraft(store: store)); runtime.acknowledgePresented()
        guard case let .orderedSteps(schema) = runtime.exercise.interaction else { return XCTFail("Expected the selected proof family") }
        runtime.orderedStepIDs = schema.correctOrder
        runtime.submitInline(store: store)
        XCTAssertEqual(runtime.stage, .feedback)
        let originalExercise = runtime.exercise
        let original = try XCTUnwrap(store.localSessions.archive.sessions.first)
        let originalSlots = store.localSessions.archive.selectionLedger?.slots
        runtime.next(store: store)
        XCTAssertEqual(runtime.itemCount, 5)
        XCTAssertNotNil(runtime.nextUnavailableReason)
        XCTAssertNil(runtime.unavailableReason)
        XCTAssertNil(runtime.saveError)
        XCTAssertEqual(runtime.stage, .feedback)
        XCTAssertEqual(runtime.index, 0)
        XCTAssertTrue(runtime.isDurablyPrepared)
        XCTAssertFalse(runtime.hasCompletedRun)
        XCTAssertEqual(runtime.exercise, originalExercise)
        XCTAssertEqual(store.attempts.count, 1)
        let retained = try XCTUnwrap(store.localSessions.archive.sessions.first)
        XCTAssertEqual(retained.status, .suspended)
        XCTAssertEqual(retained.checkpoint.exerciseDigest, original.checkpoint.exerciseDigest)
        XCTAssertEqual(retained.checkpoint.slotID, original.checkpoint.slotID)
        XCTAssertEqual(retained.checkpoint.committedAttemptID, original.checkpoint.committedAttemptID)
        XCTAssertEqual(retained.request.offlineRotationPlan, original.request.offlineRotationPlan)
        XCTAssertEqual(store.localSessions.archive.selectionLedger?.slots, originalSlots)
        runtime.endSession(store: store)
        XCTAssertEqual(runtime.stage, .summary)
        XCTAssertTrue(runtime.endedEarly)
        XCTAssertFalse(runtime.hasCompletedRun)
        XCTAssertNil(runtime.saveError)
        XCTAssertEqual(store.localSessions.archive.sessions.first?.status, .endedEarly)
        XCTAssertEqual(store.localSessions.archive.sessions.first?.checkpoint.exerciseDigest, original.checkpoint.exerciseDigest)
        XCTAssertEqual(store.localSessions.archive.selectionLedger?.slots, originalSlots)
        XCTAssertEqual(store.attempts.count, 1)
    }

    @MainActor
    func testExcludedLaterFixedPlanSlotDoesNotSubstituteAnotherSeedOrReplaceFeedback() throws {
        for quarantine in [false, true] {
            let rotationStore = FocusedQuizInMemoryRotationStore()
            let (store, container) = try makeStore(rotationStore: rotationStore)
            defer { _ = container }
            let commandID = UUID()
            let rotation = NFOfflineQuestionRotation(store: rotationStore)
            let preview = try store.localSessions.prepareFixedLaunch(commandID: commandID, rotation: rotation,
                profileID: store.profileSnapshot.id, lab: .mentalMath, laneID: "mixed", itemCount: 5,
                bank: NFOfflineQuestionBank.rotationBank)
            let ordinals = preview.plan.items.compactMap { NFOfflineQuestionBank.ordinal(forQuestionID: $0.questionID, lab: .mentalMath) }
            let previewRequest = SessionRequest(lab: .mentalMath, source: .focused,
                seed: NFStableDeterminism.hash64("focused-launch|181|\(preview.plan.id)|mixed"),
                localeIdentifier: "en", field: .general, requestedItemCount: 5, offlineQuestionOrdinals: ordinals)
            let second = NFDeterministicSessionExerciseFactory.makeExercise(request: previewRequest, index: 1, assessmentDescriptor: nil)
            XCTAssertTrue(store.beginSession(lab: .mentalMath, source: .focused, field: .general,
                requestedItemCount: 5, seedOverride: 181, launchLocaleIdentifier: "en",
                launchCommandID: commandID, reservationStrategy: .fixedBlock))
            // A new exclusion after acceptance cannot amend the exact plan.
            // Preserve it in the durable run-wide exclusion projection before
            // continuing the already accepted first question.
            var constrained = try XCTUnwrap(store.activeSessionRequest)
            let actualSecond = NFDeterministicSessionExerciseFactory.makeExercise(request: constrained, index: 1, assessmentDescriptor: nil)
            var amended = try XCTUnwrap(store.localSessions.archive.sessions.first)
            amended.checkpoint.semanticExclusions.insert(NFQuestionFingerprint.fingerprint(for: actualSecond))
            amended.revision += 1
            try store.localSessions.save(amended)
            constrained.localCheckpoint = amended.checkpoint
            let frozenRequest = SessionRequest(lab: .mentalMath, source: .focused, seed: previewRequest.seed,
                localeIdentifier: "en", field: .general, requestedItemCount: 5, offlineQuestionOrdinals: ordinals,
                quarantinedItemIDs: quarantine ? [second.id] : [])
            let unavailable = NFDeterministicSessionExerciseFactory.makeExercise(request: frozenRequest, index: 1,
                assessmentDescriptor: nil, excludingContentFingerprints: quarantine ? [] : [NFQuestionFingerprint.fingerprint(for: second)])
            XCTAssertNotNil(unavailable.availabilityReason)
            let launch = constrained
            let runtime = NFUniversalSessionRuntime(request: constrained)
            XCTAssertTrue(runtime.checkpointDraft(store: store)); runtime.acknowledgePresented()
            let firstDigest = try NFLocalItemCheckpoint.digest(runtime.exercise)
            switch runtime.exercise.interaction {
            case let .numeric(schema): runtime.numericValue = String(schema.answer.value); runtime.numericUnit = schema.answer.canonicalUnit ?? ""
            case let .singleChoice(schema): runtime.singleChoiceID = schema.correctOptionID
            case let .multipleChoice(schema): runtime.multipleChoiceIDs = Set(schema.correctOptionIDs)
            case let .orderedSteps(schema): runtime.orderedStepIDs = schema.correctOrder
            case let .shortText(schema): runtime.shortText = schema.expectedAnswer
            case .selfCheck: return XCTFail("Mixed mathematics must have an authoritative response")
            case let .claimEvidence(schema): runtime.claimSelections = Dictionary(uniqueKeysWithValues: schema.correctPairs.map { ($0.claimID, Set($0.evidenceIDs)) })
            case let .logicState(schema): runtime.logicState = schema.expectedFinalState; runtime.violatedRuleID = schema.expectedViolatedRuleID
            }
            runtime.submitInline(store: store)
            XCTAssertEqual(runtime.stage, .feedback)
            let originalExercise = runtime.exercise
            let original = try XCTUnwrap(store.localSessions.archive.sessions.first)
            let originalSlots = store.localSessions.archive.selectionLedger?.slots
            runtime.next(store: store)
            XCTAssertNotNil(runtime.nextUnavailableReason)
            XCTAssertNil(runtime.unavailableReason)
            XCTAssertNil(runtime.saveError)
            XCTAssertEqual(runtime.stage, .feedback)
            XCTAssertEqual(runtime.index, 0)
            XCTAssertTrue(runtime.isDurablyPrepared)
            XCTAssertFalse(runtime.hasCompletedRun)
            XCTAssertEqual(runtime.itemCount, 5)
            XCTAssertEqual(runtime.exercise, originalExercise)
            let preserved = try XCTUnwrap(store.localSessions.archive.sessions.first)
            XCTAssertEqual(preserved.index, 0); XCTAssertEqual(preserved.phase, .feedback)
            XCTAssertEqual(preserved.status, .suspended)
            XCTAssertEqual(preserved.checkpoint.exerciseDigest, firstDigest)
            XCTAssertEqual(preserved.checkpoint.slotID, original.checkpoint.slotID)
            XCTAssertEqual(preserved.checkpoint.committedAttemptID, original.checkpoint.committedAttemptID)
            XCTAssertEqual(preserved.request.offlineRotationPlan, launch.offlineRotationPlan)
            XCTAssertEqual(store.localSessions.archive.selectionLedger?.slots.count, 1)
            XCTAssertEqual(store.localSessions.archive.selectionLedger?.slots, originalSlots)
            XCTAssertEqual(store.attempts.count, 1)
            runtime.endSession(store: store)
            XCTAssertEqual(runtime.stage, .summary)
            XCTAssertTrue(runtime.endedEarly)
            XCTAssertFalse(runtime.hasCompletedRun)
            XCTAssertNil(runtime.saveError)
            XCTAssertEqual(store.localSessions.archive.sessions.first?.status, .endedEarly)
            XCTAssertEqual(store.localSessions.archive.sessions.first?.checkpoint.exerciseDigest, firstDigest)
            XCTAssertEqual(store.localSessions.archive.selectionLedger?.slots, originalSlots)
            XCTAssertEqual(store.attempts.count, 1)
        }
    }

    @MainActor
    func testFixedLaunchAtomicallyPublishesExactRunAndLeavesLegacyStoreReadOnly() throws {
        let source = FocusedQuizInMemoryRotationStore()
        let (store, container) = try makeStore(rotationStore: source)
        defer { _ = container }
        XCTAssertTrue(store.beginSession(lab: .mentalMath, source: .focused, requestedItemCount: 5, seedOverride: 203, reservationStrategy: .fixedBlock))
        let request = try XCTUnwrap(store.activeSessionRequest)
        let run = try XCTUnwrap(store.localSessions.archive.sessions.first)
        XCTAssertEqual(request.localSessionID, run.id)
        XCTAssertEqual(request.localCheckpoint?.slotID, run.checkpoint.slotID)
        XCTAssertEqual(request.offlineRotationPlan, run.request.offlineRotationPlan)
        XCTAssertEqual(store.localSessions.archive.fixedLaunchReceipts?.count, 1)
        XCTAssertEqual(store.localSessions.archive.offlineRotationLedger?.scopes.values.first?.cursor, 5)
        XCTAssertNotNil(store.localSessions.archive.rotationMigration)
        XCTAssertNil(try source.load())
        let ledger = try XCTUnwrap(store.localSessions.archive.selectionLedger)
        XCTAssertEqual(ledger.slots.count, 1); XCTAssertEqual(ledger.snapshots.count, 1)
        XCTAssertTrue(ledger.exposures.isEmpty); XCTAssertTrue(ledger.outcomes.isEmpty)
        let runtime = NFUniversalSessionRuntime(request: request)
        XCTAssertFalse(runtime.isPaused); XCTAssertEqual(runtime.interruptionCount, 0)
        XCTAssertTrue(runtime.answerDurationComplete)
        XCTAssertTrue(runtime.checkpointDraft(store: store)); runtime.acknowledgePresented()
        XCTAssertEqual(store.localSessions.archive.selectionLedger?.slots.count, 1)
        XCTAssertEqual(store.localSessions.archive.selectionLedger?.exposures.count, 1)
    }

    @MainActor
    func testFixedLaunchCommandReplayKeepsOriginalRunAndRejectsChangedConfiguration() throws {
        let source = FocusedQuizInMemoryRotationStore()
        let (store, container) = try makeStore(rotationStore: source)
        defer { _ = container }
        let command = UUID()
        XCTAssertTrue(store.beginSession(lab: .spatial, source: .focused, requestedItemCount: 5,
            seedOverride: 211, launchCommandID: command, reservationStrategy: .fixedBlock))
        let first = try XCTUnwrap(store.activeSessionRequest)
        let revision = store.localSessions.archive.transactionRevision
        store.activeSessionRequest = nil
        XCTAssertTrue(store.beginSession(lab: .spatial, source: .focused, requestedItemCount: 5,
            seedOverride: 211, launchCommandID: command, reservationStrategy: .fixedBlock))
        let replay = try XCTUnwrap(store.activeSessionRequest)
        XCTAssertEqual(replay.localSessionID, first.localSessionID)
        XCTAssertEqual(replay.localCheckpoint?.exerciseDigest, first.localCheckpoint?.exerciseDigest)
        XCTAssertEqual(replay.localCheckpoint?.attemptID, first.localCheckpoint?.attemptID)
        XCTAssertEqual(store.localSessions.archive.transactionRevision, revision)
        XCTAssertEqual(store.localSessions.archive.sessions.count, 1)
        XCTAssertEqual(store.localSessions.archive.offlineRotationLedger?.scopes.values.first?.cursor, 5)
        store.activeSessionRequest = nil
        XCTAssertFalse(store.beginSession(lab: .spatial, source: .focused, requestedItemCount: 5,
            seedOverride: 999, launchCommandID: command, reservationStrategy: .fixedBlock))
        XCTAssertNil(store.activeSessionRequest)
        XCTAssertEqual(store.localSessions.archive.transactionRevision, revision)
    }

    @MainActor
    func testLegacyMigrationPreservesEpochBoundaryAndNeverConsultsLegacyAfterBootstrap() throws {
        let source = FocusedQuizInMemoryRotationStore()
        let (store, container) = try makeStore(rotationStore: source)
        defer { _ = container }
        let rotation = NFOfflineQuestionRotation(store: source)
        _ = try rotation.reserve(profileID: store.profileSnapshot.id, lab: .spatial,
            itemCount: 995, bank: NFOfflineQuestionBank.rotationBank)
        let original = try XCTUnwrap(source.load())
        let expected = try rotation.prepareReservation(profileID: store.profileSnapshot.id, lab: .spatial,
            itemCount: 10, bank: NFOfflineQuestionBank.rotationBank, loadedLedger: original)
        XCTAssertTrue(store.beginSession(lab: .spatial, source: .focused, requestedItemCount: 10, seedOverride: 223, reservationStrategy: .fixedBlock))
        XCTAssertEqual(store.activeSessionRequest?.offlineRotationPlan, expected.plan)
        XCTAssertEqual(store.localSessions.archive.offlineRotationLedger, expected.replacement)
        XCTAssertEqual(try source.load(), original)
        XCTAssertEqual(expected.plan.items.map(\.stableOrdinal), (995..<1005).map(UInt64.init))
        store.activeSessionRequest = nil
        source.setFailsReads(true)
        XCTAssertTrue(store.beginSession(lab: .spatial, source: .focused, requestedItemCount: 5, seedOverride: 223, reservationStrategy: .fixedBlock))
        XCTAssertEqual(store.activeSessionRequest?.offlineRotationPlan?.items.first?.stableOrdinal, 1005)
    }

    @MainActor
    func testStaleIndependentRepositoryCannotPublishDuplicateFixedPositions() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "NFAtomicLaunch-\(UUID())")
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appending(path: "sessions.json"), owner = UUID(), profile = UUID()
        let first = NFLocalSessionRepository(url: url, ownerDeviceID: owner)
        let second = NFLocalSessionRepository(url: url, ownerDeviceID: owner)
        let source = FocusedQuizInMemoryRotationStore(), rotation = NFOfflineQuestionRotation(store: source)
        let a = try preparation(first, rotation: rotation, profile: profile)
        let b = try preparation(second, rotation: rotation, profile: profile)
        _ = try first.acceptFixedLaunch(a, request: fixedRequest(a), rotation: rotation)
        XCTAssertThrowsError(try second.acceptFixedLaunch(b, request: fixedRequest(b), rotation: rotation))
        XCTAssertTrue(second.archive.sessions.isEmpty)
        let refreshed = try preparation(second, commandID: b.commandID, rotation: rotation, profile: profile)
        _ = try second.acceptFixedLaunch(refreshed, request: fixedRequest(refreshed), rotation: rotation)
        XCTAssertTrue(Set(a.plan.items.map(\.stableOrdinal)).isDisjoint(with: Set(refreshed.plan.items.map(\.stableOrdinal))))
        let reopened = NFLocalSessionRepository(url: url, ownerDeviceID: owner)
        XCTAssertNil(reopened.loadError)
        XCTAssertEqual(reopened.archive.sessions.count, 2)
        XCTAssertEqual(reopened.archive.fixedLaunchReceipts?.count, 2)
        XCTAssertEqual(reopened.archive.offlineRotationLedger?.scopes.values.first?.cursor, 10)
        XCTAssertNil(try source.load())
    }

    @MainActor
    func testCompetingFileLockFailsBeforePublicationAndSameCommandRetriesAfterRelease() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "NFBusyLaunch-\(UUID())")
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appending(path: "sessions.json")
        let repository = NFLocalSessionRepository(url: url)
        let source = FocusedQuizInMemoryRotationStore(), rotation = NFOfflineQuestionRotation(store: source)
        let profile = UUID()
        let first = try preparation(repository, rotation: rotation, profile: profile)
        _ = try repository.acceptFixedLaunch(first, request: fixedRequest(first), rotation: rotation)
        let proposal = try preparation(repository, rotation: rotation, profile: profile)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let predecessor = try encoder.encode(repository.archive)
        let diskPredecessor = try Data(contentsOf: url)
        let descriptor = Darwin.open(url.path + ".lock", O_RDWR)
        guard descriptor >= 0 else { return XCTFail("Could not open the actual publication lock") }
        guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else {
            Darwin.close(descriptor)
            return XCTFail("Could not acquire the competing descriptor lock")
        }
        let releaseRequested = DispatchSemaphore(value: 0)
        let lockReleased = DispatchSemaphore(value: 0)
        DispatchQueue.global().async {
            // A regression to blocking acquisition must fail the assertions,
            // rather than hang the whole test runner forever. This watchdog is
            // not a claimed latency benchmark or part of production recovery.
            _ = releaseRequested.wait(timeout: .now() + 5)
            flock(descriptor, LOCK_UN)
            lockReleased.signal()
        }
        var hasReleased = false
        defer {
            if !hasReleased {
                releaseRequested.signal()
                lockReleased.wait()
            }
            Darwin.close(descriptor)
        }
        XCTAssertThrowsError(try repository.acceptFixedLaunch(proposal, request: fixedRequest(proposal), rotation: rotation)) { error in
            guard case .busy? = error as? NFLocalSessionRepository.RepositoryError else {
                return XCTFail("Expected recoverable lock contention; received \(error)")
            }
            XCTAssertTrue(error.localizedDescription.contains("try again"))
        }
        XCTAssertThrowsError(try preparation(repository, commandID: proposal.commandID, rotation: rotation, profile: profile)) { error in
            guard case .busy? = error as? NFLocalSessionRepository.RepositoryError else {
                return XCTFail("Preparation must also return recoverable lock contention")
            }
        }
        XCTAssertEqual(try encoder.encode(repository.archive), predecessor)
        XCTAssertEqual(try Data(contentsOf: url), diskPredecessor)
        XCTAssertNil(repository.archive.fixedLaunchReceipts?[proposal.commandID.uuidString])
        XCTAssertNil(try source.load())
        releaseRequested.signal()
        lockReleased.wait()
        hasReleased = true
        let accepted = try repository.acceptFixedLaunch(proposal, request: fixedRequest(proposal), rotation: rotation)
        XCTAssertEqual(accepted.id, proposal.commandID)
        XCTAssertEqual(accepted.request.offlineRotationPlan, proposal.plan)
        XCTAssertEqual(repository.archive.sessions.count, 2)
        XCTAssertEqual(repository.archive.fixedLaunchReceipts?.count, 2)
        XCTAssertEqual(repository.archive.offlineRotationLedger, proposal.replacementRotationLedger)
        let revision = repository.archive.transactionRevision
        let duplicate = try repository.acceptFixedLaunch(proposal, request: fixedRequest(proposal), rotation: rotation)
        XCTAssertEqual(duplicate.id, accepted.id)
        XCTAssertEqual(repository.archive.transactionRevision, revision)
    }

    @MainActor
    func testFailedAtomicPublicationConsumesNothingAndSameProposalCanRetry() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "NFFailedLaunch-\(UUID())")
        defer { try? FileManager.default.removeItem(at: folder) }
        let repository = NFLocalSessionRepository(url: folder.appending(path: "sessions.json"))
        let source = FocusedQuizInMemoryRotationStore(), rotation = NFOfflineQuestionRotation(store: source)
        let proposal = try preparation(repository, rotation: rotation, profile: UUID())
        let first = NFDeterministicSessionExerciseFactory.makeExercise(request: fixedRequest(proposal), index: 0, assessmentDescriptor: nil)
        let constrained = fixedRequest(proposal, quarantinedItemIDs: [first.id])
        try FileManager.default.removeItem(at: folder)
        try Data("blocked directory".utf8).write(to: folder)
        XCTAssertThrowsError(try repository.acceptFixedLaunch(proposal, request: constrained, rotation: rotation))
        XCTAssertTrue(repository.archive.sessions.isEmpty); XCTAssertNil(repository.archive.offlineRotationLedger)
        XCTAssertNil(repository.archive.selectionLedger); XCTAssertNil(repository.archive.rotationMigration)
        XCTAssertNil(try source.load())
        try FileManager.default.removeItem(at: folder)
        let accepted = try repository.acceptFixedLaunch(proposal, request: constrained, rotation: rotation)
        XCTAssertEqual(accepted.id, proposal.commandID)
        XCTAssertEqual(repository.archive.offlineRotationLedger?.scopes.values.first?.cursor, 0)
        XCTAssertEqual(repository.archive.offlineRotationLedger?.scopes.values.first?.consumedEpochOrdinals, Set(1...5))
        XCTAssertEqual(repository.archive.sessions.count, 1)
    }

    @MainActor
    func testLegacySourceChangedDuringPreparationRejectsAtomicBootstrap() throws {
        let repository = NFLocalSessionRepository(), source = FocusedQuizInMemoryRotationStore()
        let rotation = NFOfflineQuestionRotation(store: source), profile = UUID()
        let proposal = try preparation(repository, rotation: rotation, profile: profile)
        _ = try rotation.reserve(profileID: profile, lab: .mentalMath, itemCount: 7, bank: NFOfflineQuestionBank.rotationBank)
        XCTAssertThrowsError(try repository.acceptFixedLaunch(proposal, request: fixedRequest(proposal), rotation: rotation))
        XCTAssertTrue(repository.archive.sessions.isEmpty); XCTAssertNil(repository.archive.rotationMigration)
        let refreshed = try preparation(repository, commandID: proposal.commandID, rotation: rotation, profile: profile)
        let accepted = try repository.acceptFixedLaunch(refreshed, request: fixedRequest(refreshed), rotation: rotation)
        XCTAssertEqual(accepted.request.offlineRotationPlan?.items.first?.stableOrdinal, 7)
        XCTAssertEqual(try source.load()?.scopes.values.first?.cursor, 7)
    }

    @MainActor
    func testExcludedFirstFixedDescriptorLeavesUnconsumedHoleAndReinstatementKeepsItsIdentity() throws {
        let source = FocusedQuizInMemoryRotationStore()
        let (store, container) = try makeStore(rotationStore: source)
        defer { _ = container }
        let rotation = NFOfflineQuestionRotation(store: source), command = UUID()
        let proposal = try preparation(store.localSessions, commandID: command, rotation: rotation, profile: store.profileSnapshot.id)
        let preview = fixedRequest(proposal, baseSeed: 239)
        let first = NFDeterministicSessionExerciseFactory.makeExercise(request: preview, index: 0, assessmentDescriptor: nil)
        XCTAssertTrue(store.beginSession(lab: .mentalMath, source: .focused, field: .general, requestedItemCount: 5,
            seedOverride: 239, launchLocaleIdentifier: "en", additionalQuarantinedItemIDs: [first.id], launchCommandID: command, reservationStrategy: .fixedBlock))
        let accepted = try XCTUnwrap(store.activeSessionRequest)
        let selected = try XCTUnwrap(accepted.offlineRotationPlan)
        XCTAssertFalse(selected.items.contains { $0.questionID == proposal.plan.items[0].questionID })
        XCTAssertEqual(selected.items.map(\.stableOrdinal), [1, 2, 3, 4, 5])
        let scope = try XCTUnwrap(store.localSessions.archive.offlineRotationLedger?.scopes.values.first)
        XCTAssertEqual(scope.epoch, 0); XCTAssertEqual(scope.cursor, 0)
        XCTAssertEqual(scope.consumedEpochOrdinals, Set(1...5))
        XCTAssertNil(try source.load())
        store.activeSessionRequest = nil
        XCTAssertTrue(store.beginSession(lab: .mentalMath, source: .focused, field: .general, requestedItemCount: 5,
            seedOverride: 239, launchLocaleIdentifier: "en", launchCommandID: UUID(), reservationStrategy: .fixedBlock))
        let restored = try XCTUnwrap(store.activeSessionRequest)
        XCTAssertEqual(restored.offlineRotationPlan?.items.first?.questionID, proposal.plan.items[0].questionID)
        XCTAssertEqual(restored.offlineRotationPlan?.items.first?.stableOrdinal, 0)
        XCTAssertEqual(restored.localCheckpoint?.exercise?.id, first.id)
        XCTAssertTrue(Set(restored.offlineRotationPlan?.items.map(\.stableOrdinal) ?? []).isDisjoint(with: Set(selected.items.map(\.stableOrdinal))))
        XCTAssertEqual(store.localSessions.archive.offlineRotationLedger?.scopes.values.first?.cursor, 10)
        XCTAssertNil(store.localSessions.archive.offlineRotationLedger?.scopes.values.first?.consumedEpochOrdinals)
    }

    @MainActor
    func testSparseFixedBlockPersistsExactEligibilityAndReplaysBothProvisionalAndCanonicalRequests() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "NFSparseLaunch-\(UUID())")
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appending(path: "sessions.json"), owner = UUID(), profile = UUID()
        let repository = NFLocalSessionRepository(url: url, ownerDeviceID: owner)
        let source = FocusedQuizInMemoryRotationStore(), rotation = NFOfflineQuestionRotation(store: source)
        let proposal = try preparation(repository, rotation: rotation, profile: profile)
        let initialRequest = fixedRequest(proposal)
        let first = NFDeterministicSessionExerciseFactory.makeExercise(request: initialRequest, index: 0, assessmentDescriptor: nil)
        let third = NFDeterministicSessionExerciseFactory.makeExercise(request: initialRequest, index: 2, assessmentDescriptor: nil)
        let semanticExclusions: Set<String> = [NFQuestionFingerprint.fingerprint(for: third)]
        let constrained = fixedRequest(proposal, quarantinedItemIDs: [first.id], semanticExclusions: semanticExclusions)
        let accepted = try repository.acceptFixedLaunch(proposal, request: constrained, rotation: rotation)
        XCTAssertEqual(accepted.request.offlineRotationPlan?.items.map(\.stableOrdinal), [1, 3, 4, 5, 6])
        var seen = semanticExclusions
        for index in 0..<5 {
            let exercise = NFDeterministicSessionExerciseFactory.makeExercise(request: accepted.request, index: index,
                assessmentDescriptor: nil, excludingContentFingerprints: seen)
            XCTAssertNil(exercise.availabilityReason); XCTAssertNotEqual(exercise.id, first.id)
            XCTAssertTrue(seen.insert(NFQuestionFingerprint.fingerprint(for: exercise)).inserted)
        }
        let revision = repository.archive.transactionRevision
        let directReplay = try repository.acceptFixedLaunch(proposal, request: constrained, rotation: rotation)
        XCTAssertEqual(directReplay.request.offlineRotationPlan, accepted.request.offlineRotationPlan)
        XCTAssertEqual(repository.archive.transactionRevision, revision)
        let reopened = NFLocalSessionRepository(url: url, ownerDeviceID: owner)
        XCTAssertNil(reopened.loadError)
        let replay = try preparation(reopened, commandID: proposal.commandID, rotation: rotation, profile: profile)
        let resumed = try reopened.acceptFixedLaunch(replay,
            request: fixedRequest(replay, quarantinedItemIDs: [first.id], semanticExclusions: semanticExclusions), rotation: rotation)
        XCTAssertEqual(resumed.checkpoint.exerciseDigest, accepted.checkpoint.exerciseDigest)
        XCTAssertEqual(resumed.checkpoint.attemptID, accepted.checkpoint.attemptID)
        XCTAssertEqual(reopened.archive.transactionRevision, revision)
        XCTAssertEqual(reopened.archive.offlineRotationLedger?.scopes.values.first?.consumedEpochOrdinals, Set([1, 3, 4, 5, 6]))
        XCTAssertEqual(reopened.archive.selectionLedger?.slots.count, 1)
        XCTAssertTrue(reopened.archive.selectionLedger?.exposures.isEmpty == true)
        XCTAssertNil(try source.load())
    }

    @MainActor
    func testFixedBlockShortageAtAnIneligibleEpochTailPublishesNoPartialLaunch() throws {
        let repository = NFLocalSessionRepository(), source = FocusedQuizInMemoryRotationStore()
        let rotation = NFOfflineQuestionRotation(store: source), profile = UUID()
        _ = try rotation.reserve(profileID: profile, lab: .mentalMath, itemCount: 995, bank: NFOfflineQuestionBank.rotationBank)
        let original = try XCTUnwrap(source.load())
        let proposal = try preparation(repository, rotation: rotation, profile: profile)
        let first = NFDeterministicSessionExerciseFactory.makeExercise(request: fixedRequest(proposal), index: 0, assessmentDescriptor: nil)
        XCTAssertThrowsError(try repository.acceptFixedLaunch(proposal,
            request: fixedRequest(proposal, quarantinedItemIDs: [first.id]), rotation: rotation)) { error in
            guard case NFLocalSessionRepository.RepositoryError.unavailableLaunch = error else { return XCTFail("Expected explicit shortage: \(error)") }
        }
        XCTAssertNil(repository.archive.offlineRotationLedger); XCTAssertNil(repository.archive.rotationMigration)
        XCTAssertNil(repository.archive.selectionLedger); XCTAssertNil(repository.archive.fixedLaunchReceipts)
        XCTAssertTrue(repository.archive.sessions.isEmpty)
        XCTAssertEqual(try source.load(), original)
    }

    @MainActor
    func testLaunchAuthorityIsNotPortableAndDeletionTombstonePreventsResurrection() throws {
        let repository = NFLocalSessionRepository(), source = FocusedQuizInMemoryRotationStore()
        let rotation = NFOfflineQuestionRotation(store: source), profile = UUID()
        let proposal = try preparation(repository, rotation: rotation, profile: profile)
        let accepted = try repository.acceptFixedLaunch(proposal, request: fixedRequest(proposal), rotation: rotation)
        let exported = repository.exportArchive
        XCTAssertNil(exported.offlineRotationLedger); XCTAssertNil(exported.rotationMigration)
        XCTAssertNil(exported.fixedLaunchReceipts); XCTAssertNil(exported.transactionRevision)
        try repository.removeReferences(attemptIDs: [accepted.checkpoint.attemptID])
        XCTAssertTrue(repository.archive.sessions.isEmpty)
        XCTAssertEqual(repository.archive.offlineRotationLedger?.scopes.values.first?.cursor, 5)
        XCTAssertTrue(repository.archive.deletedFixedLaunchCommandIDs?.contains(proposal.commandID.uuidString) == true)
        XCTAssertThrowsError(try preparation(repository, commandID: proposal.commandID, rotation: rotation, profile: profile))
    }

    @MainActor
    func testArchiveRefreshRejectsDuplicateRunsAndBoundsFilesThatGrowAfterInitialization() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "NFLaunchRefresh-\(UUID())")
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appending(path: "sessions.json")
        let repository = NFLocalSessionRepository(url: url)
        let source = FocusedQuizInMemoryRotationStore(), rotation = NFOfflineQuestionRotation(store: source), profile = UUID()
        let proposal = try preparation(repository, rotation: rotation, profile: profile)
        _ = try repository.acceptFixedLaunch(proposal, request: fixedRequest(proposal), rotation: rotation)
        let original = try Data(contentsOf: url)
        let revision = repository.archive.transactionRevision
        var duplicate = repository.archive
        duplicate.sessions.append(try XCTUnwrap(duplicate.sessions.first))
        try JSONEncoder().encode(duplicate).write(to: url)
        XCTAssertThrowsError(try preparation(repository, rotation: rotation, profile: profile))
        XCTAssertEqual(repository.archive.transactionRevision, revision)
        XCTAssertEqual(repository.archive.sessions.count, 1)
        try original.write(to: url) // Explicit restoration of the acknowledged fixture bytes.
        let next = try preparation(repository, rotation: rotation, profile: profile)
        let handle = try FileHandle(forWritingTo: url)
        try handle.truncate(atOffset: UInt64(NFLocalSessionRepository.maximumBytes + 1)); try handle.close()
        XCTAssertThrowsError(try repository.acceptFixedLaunch(next, request: fixedRequest(next), rotation: rotation)) { error in
            guard case NFLocalSessionRepository.RepositoryError.oversized = error else { return XCTFail("Expected bounded-read rejection: \(error)") }
        }
        XCTAssertEqual(repository.archive.transactionRevision, revision)
        XCTAssertEqual(repository.archive.offlineRotationLedger?.scopes.values.first?.cursor, 5)
    }

    @MainActor
    func testLoadRejectsBrokenLaunchReceiptReferenceWithoutOverwritingRecoveryFile() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "NFLaunchReceiptCorruption-\(UUID())")
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appending(path: "sessions.json"), owner = UUID()
        let repository = NFLocalSessionRepository(url: url, ownerDeviceID: owner)
        let source = FocusedQuizInMemoryRotationStore(), rotation = NFOfflineQuestionRotation(store: source)
        let proposal = try preparation(repository, rotation: rotation, profile: UUID())
        _ = try repository.acceptFixedLaunch(proposal, request: fixedRequest(proposal), rotation: rotation)
        var corrupt = repository.archive
        let receipt = try XCTUnwrap(corrupt.fixedLaunchReceipts?[proposal.commandID.uuidString])
        corrupt.fixedLaunchReceipts?[proposal.commandID.uuidString] = .init(commandID: receipt.commandID,
            sessionID: UUID(), configurationDigest: receipt.configurationDigest, plan: receipt.plan)
        let bytes = try JSONEncoder().encode(corrupt)
        try bytes.write(to: url)
        let reopened = NFLocalSessionRepository(url: url, ownerDeviceID: owner)
        XCTAssertNotNil(reopened.loadError)
        XCTAssertThrowsError(try preparation(reopened, rotation: rotation, profile: proposal.plan.profileID))
        XCTAssertEqual(try Data(contentsOf: url), bytes)
        let scopeKey = try XCTUnwrap(repository.archive.offlineRotationLedger?.scopes.keys.first)
        for invalidPositions in [Set([-1]), Set([5]), Set([1_000])] {
            var invalidConsumption = repository.archive
            invalidConsumption.offlineRotationLedger?.scopes[scopeKey]?.consumedEpochOrdinals = invalidPositions
            let invalidBytes = try JSONEncoder().encode(invalidConsumption)
            try invalidBytes.write(to: url)
            let rejected = NFLocalSessionRepository(url: url, ownerDeviceID: owner)
            XCTAssertNotNil(rejected.loadError)
            XCTAssertEqual(try Data(contentsOf: url), invalidBytes)
        }
    }

    @MainActor
    func testSameDeviceRestoredRunWithoutLaunchReceiptCannotBeAcceptedAsDuplicate() throws {
        let owner = UUID(), profile = UUID()
        let original = NFLocalSessionRepository(ownerDeviceID: owner)
        let source = FocusedQuizInMemoryRotationStore(), rotation = NFOfflineQuestionRotation(store: source)
        let proposal = try preparation(original, rotation: rotation, profile: profile)
        let first = try original.acceptFixedLaunch(proposal, request: fixedRequest(proposal), rotation: rotation)
        let restored = NFLocalSessionRepository(ownerDeviceID: owner)
        try restored.importArchive(original.exportArchive)
        XCTAssertNil(restored.archive.fixedLaunchReceipts)
        XCTAssertEqual(restored.archive.sessions.first?.id, first.id)
        let revision = restored.archive.transactionRevision
        let ambiguous = try preparation(restored, commandID: proposal.commandID, rotation: rotation, profile: profile)
        XCTAssertThrowsError(try restored.acceptFixedLaunch(ambiguous, request: fixedRequest(ambiguous), rotation: rotation))
        XCTAssertEqual(restored.archive.transactionRevision, revision)
        XCTAssertEqual(restored.archive.sessions.count, 1)
        XCTAssertEqual(restored.archive.sessions.first?.checkpoint.attemptID, first.checkpoint.attemptID)
        XCTAssertNil(restored.archive.offlineRotationLedger)
        XCTAssertTrue(restored.archive.selectionLedger?.exposures.isEmpty == true)
    }

    @MainActor
    func testDefaultMixedLaunchAcceptsOnlyOnePositionAndReplaysWithoutNewExposure() throws {
        let source = FocusedQuizInMemoryRotationStore()
        let (store, container) = try makeStore(rotationStore: source)
        defer { _ = container }
        let command = UUID()
        XCTAssertTrue(store.beginSession(lab: .mentalMath, source: .focused, requestedItemCount: 5,
            seedOverride: 811, launchLocaleIdentifier: "en", launchCommandID: command))
        let first = try XCTUnwrap(store.activeSessionRequest)
        XCTAssertEqual(first.ordinaryDelivery?.strategy, .adaptiveItem)
        XCTAssertNil(first.offlineRotationPlan); XCTAssertTrue(first.offlineQuestionOrdinals.isEmpty)
        XCTAssertEqual(first.requestedItemCount, 5)
        let original = try XCTUnwrap(first.localCheckpoint)
        let receipt = try XCTUnwrap(store.localSessions.archive.adaptiveItemReceipts?.values.first)
        let position = try XCTUnwrap(receipt.plan.items.first)
        let ordinal = try XCTUnwrap(NFOfflineQuestionBank.ordinal(forQuestionID: position.questionID, lab: first.lab))
        let descriptor = try XCTUnwrap(NFOfflineQuestionBank.descriptor(for: first.lab, ordinal: ordinal))
        XCTAssertNotEqual(original.exercise?.seed, descriptor.seed, "A bank input seed is transformed when the exact contract is materialized")
        XCTAssertEqual(original.exercise, NFDeterministicSessionExerciseFactory.makeExercise(
            request: first.launchOnly(offlineQuestionOrdinals: [ordinal]), index: 0, assessmentDescriptor: nil))
        XCTAssertEqual(store.localSessions.archive.offlineRotationLedger?.scopes.values.first?.cursor, 1)
        XCTAssertEqual(store.localSessions.archive.adaptiveItemReceipts?.count, 1)
        XCTAssertEqual(store.localSessions.archive.selectionLedger?.slots.count, 1)
        XCTAssertTrue(store.localSessions.archive.selectionLedger?.exposures.isEmpty == true)
        XCTAssertNil(try source.load(), "The legacy preference cursor becomes read-only after bootstrap")
        let revision = store.localSessions.archive.transactionRevision
        store.activeSessionRequest = nil
        XCTAssertTrue(store.beginSession(lab: .mentalMath, source: .focused, requestedItemCount: 5,
            seedOverride: 811, launchLocaleIdentifier: "en", launchCommandID: command))
        let replay = try XCTUnwrap(store.activeSessionRequest?.localCheckpoint)
        XCTAssertEqual(replay.slotID, original.slotID); XCTAssertEqual(replay.attemptID, original.attemptID)
        XCTAssertEqual(replay.exercise, original.exercise)
        XCTAssertEqual(store.localSessions.archive.transactionRevision, revision)
        XCTAssertTrue(store.localSessions.archive.selectionLedger?.exposures.isEmpty == true)
        try store.localSessions.acknowledgePresentation(sessionID: command, slotID: original.slotID, at: original.shownAt)
        try store.localSessions.acknowledgePresentation(sessionID: command, slotID: original.slotID, at: original.shownAt.addingTimeInterval(1))
        XCTAssertEqual(store.localSessions.archive.selectionLedger?.exposures.count, 1)
        XCTAssertEqual(store.localSessions.archive.offlineRotationLedger?.scopes.values.first?.cursor, 1)
        store.activeSessionRequest = nil
        XCTAssertFalse(store.beginSession(lab: .mentalMath, source: .focused, requestedItemCount: 4,
            seedOverride: 811, launchLocaleIdentifier: "en", launchCommandID: command))
        XCTAssertEqual(store.localSessions.archive.adaptiveItemReceipts?.count, 1)
    }

    @MainActor
    func testAdaptiveRuntimeNextRetainsPriorSlotAndColdResumesExactNextQuestion() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "NFAdaptiveResume-\(UUID())")
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appending(path: "sessions.json"), owner = UUID()
        let source = FocusedQuizInMemoryRotationStore()
        let repository = NFLocalSessionRepository(url: url, ownerDeviceID: owner)
        let (store, container) = try makeStore(rotationStore: source, repository: repository)
        defer { _ = container }
        XCTAssertTrue(store.beginSession(lab: .mentalMath, source: .focused, requestedItemCount: 5,
            seedOverride: 823, launchLocaleIdentifier: "en"))
        let request = try XCTUnwrap(store.activeSessionRequest)
        let first = try XCTUnwrap(request.localCheckpoint)
        let runtime = NFUniversalSessionRuntime(request: request)
        XCTAssertTrue(runtime.checkpointDraft(store: store)); runtime.acknowledgePresented()
        fillAuthoritativeResponse(runtime)
        runtime.submitInline(store: store)
        XCTAssertEqual(runtime.stage, .feedback)
        XCTAssertEqual(store.attempts.count, 1)
        XCTAssertEqual(repository.archive.offlineRotationLedger?.scopes.values.first?.cursor, 1)
        let receipt = try XCTUnwrap(repository.archive.adaptiveItemReceipts?[try XCTUnwrap(first.ordinaryReservationDecisionID)])
        let prior = try XCTUnwrap(repository.archive.sessions.first?.checkpoint)
        let proposedNext = try store.prepareAdaptiveItem(request: request, predecessor: prior,
            command: try runtime.sessionWriterCommand())
        var changedHistory = proposedNext.checkpoint
        changedHistory.scratchpad = prior.scratchpad
        changedHistory.correctness = prior.correctness.map { !$0 }; changedHistory.credits = prior.credits
        changedHistory.assessmentDescriptorIDs = prior.assessmentDescriptorIDs
        changedHistory.assessmentEvents = prior.assessmentEvents
        changedHistory.cumulativeActiveDuration = prior.cumulativeActiveDuration
        changedHistory.assessmentPracticeDuration = prior.assessmentPracticeDuration
        changedHistory.sittingActiveDuration = prior.sittingActiveDuration
        changedHistory.sittingOrdinal = prior.sittingOrdinal
        changedHistory.timingConditionOverride = prior.timingConditionOverride
        XCTAssertThrowsError(try store.acceptAdaptiveItem(proposedNext, checkpoint: changedHistory))
        XCTAssertEqual(repository.archive.sessions.first?.checkpoint, prior)
        XCTAssertEqual(repository.archive.offlineRotationLedger?.scopes.values.first?.cursor, 1)
        runtime.next(store: store)
        XCTAssertNil(runtime.saveError); XCTAssertNil(runtime.nextUnavailableReason)
        XCTAssertEqual(runtime.stage, .item); XCTAssertEqual(runtime.index, 1)
        XCTAssertEqual(runtime.itemCount, 5)
        let next = try XCTUnwrap(repository.archive.sessions.first)
        XCTAssertEqual(next.checkpoint.exercise, runtime.exercise)
        XCTAssertNotEqual(next.checkpoint.attemptID, first.attemptID)
        XCTAssertEqual(repository.archive.offlineRotationLedger?.scopes.values.first?.cursor, 2)
        XCTAssertEqual(repository.archive.adaptiveItemReceipts?.count, 2)
        XCTAssertEqual(repository.archive.adaptiveItemReceipts?[receipt.decisionID], receipt)
        XCTAssertEqual(repository.archive.selectionLedger?.slots[first.slotID.uuidString]?.status, .answered)
        XCTAssertEqual(repository.archive.selectionLedger?.slots[next.checkpoint.slotID.uuidString]?.status, .reserved)
        XCTAssertEqual(repository.archive.selectionLedger?.exposures.count, 1)
        runtime.releaseWriter()
        let restored = NFLocalSessionRepository(url: url, ownerDeviceID: owner)
        XCTAssertNil(restored.loadError)
        let retained = try XCTUnwrap(restored.archive.sessions.first)
        var resume = retained.request
        resume.localCheckpoint = retained.checkpoint; resume.localSessionID = retained.id
        let cold = NFUniversalSessionRuntime(request: resume)
        XCTAssertTrue(cold.isPaused); XCTAssertEqual(cold.index, 1)
        XCTAssertEqual(cold.exercise, runtime.exercise)
        XCTAssertEqual(cold.exercise, next.checkpoint.exercise)
        XCTAssertEqual(restored.archive.selectionLedger, repository.archive.selectionLedger)
        XCTAssertEqual(try NFLocalReservationBridge.configurationDigest(resume), receipt.configurationDigest)
        XCTAssertEqual(restored.archive.adaptiveItemReceipts?.count, 2)
    }

    @MainActor
    func testAdaptiveSpeculationCASAndRepreparationPreserveExactBankPermutation() throws {
        let source = FocusedQuizInMemoryRotationStore(), rotation = NFOfflineQuestionRotation(store: source)
        let repository = NFLocalSessionRepository(), profile = UUID()
        let a = adaptiveRequest(profile: profile), b = adaptiveRequest(profile: profile)
        let first = try repository.prepareAdaptiveItem(request: a, predecessor: nil, rotation: rotation,
            bank: NFOfflineQuestionBank.rotationBank, quarantinedItemIDs: [], at: Date())
        let stale = try repository.prepareAdaptiveItem(request: b, predecessor: nil, rotation: rotation,
            bank: NFOfflineQuestionBank.rotationBank, quarantinedItemIDs: [], at: Date())
        XCTAssertTrue(repository.archive.sessions.isEmpty); XCTAssertNil(repository.archive.offlineRotationLedger)
        XCTAssertEqual(first.receipt.plan.items, stale.receipt.plan.items)
        let accepted = try repository.acceptAdaptiveItem(first, checkpoint: first.checkpoint, rotation: rotation, quarantinedItemIDs: [])
        XCTAssertThrowsError(try repository.acceptAdaptiveItem(stale, checkpoint: stale.checkpoint, rotation: rotation, quarantinedItemIDs: []))
        let refreshed = try repository.prepareAdaptiveItem(request: b, predecessor: nil, rotation: rotation,
            bank: NFOfflineQuestionBank.rotationBank, quarantinedItemIDs: [], at: Date())
        XCTAssertEqual(refreshed.receipt.slotID, stale.receipt.slotID, "The logical decision retains its intended identity")
        XCTAssertNotEqual(refreshed.receipt.plan.items, stale.receipt.plan.items)
        _ = try repository.acceptAdaptiveItem(refreshed, checkpoint: refreshed.checkpoint, rotation: rotation, quarantinedItemIDs: [])
        let revision = repository.archive.transactionRevision
        XCTAssertEqual(try repository.acceptAdaptiveItem(first, checkpoint: first.checkpoint, rotation: rotation, quarantinedItemIDs: []).id, accepted.id)
        XCTAssertEqual(repository.archive.transactionRevision, revision)
        XCTAssertEqual(repository.archive.offlineRotationLedger?.scopes.values.first?.cursor, 2)
        XCTAssertTrue(repository.archive.selectionLedger?.exposures.isEmpty == true)
        XCTAssertNil(try source.load())
    }

    @MainActor
    func testAdaptiveFailedPublicationAndChangedEligibilityRetainUnconsumedPredecessor() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "NFAdaptiveFailure-\(UUID())")
        defer { try? FileManager.default.removeItem(at: folder) }
        let repository = NFLocalSessionRepository(url: folder.appending(path: "sessions.json"))
        let source = FocusedQuizInMemoryRotationStore(), rotation = NFOfflineQuestionRotation(store: source)
        let request = adaptiveRequest(profile: UUID())
        let prepared = try repository.prepareAdaptiveItem(request: request, predecessor: nil, rotation: rotation,
            bank: NFOfflineQuestionBank.rotationBank, quarantinedItemIDs: [], at: Date())
        let excludedID = try XCTUnwrap(prepared.checkpoint.exercise?.id)
        XCTAssertThrowsError(try repository.acceptAdaptiveItem(prepared, checkpoint: prepared.checkpoint,
            rotation: rotation, quarantinedItemIDs: [excludedID]))
        XCTAssertNil(repository.archive.offlineRotationLedger)
        try FileManager.default.removeItem(at: folder)
        try Data("blocked directory".utf8).write(to: folder)
        XCTAssertThrowsError(try repository.acceptAdaptiveItem(prepared, checkpoint: prepared.checkpoint,
            rotation: rotation, quarantinedItemIDs: []))
        XCTAssertTrue(repository.archive.sessions.isEmpty); XCTAssertNil(repository.archive.selectionLedger)
        XCTAssertNil(repository.archive.rotationMigration); XCTAssertNil(try source.load())
        try FileManager.default.removeItem(at: folder)
        let accepted = try repository.acceptAdaptiveItem(prepared, checkpoint: prepared.checkpoint, rotation: rotation, quarantinedItemIDs: [])
        XCTAssertEqual(accepted.checkpoint.slotID, prepared.receipt.slotID)
        XCTAssertEqual(repository.archive.offlineRotationLedger?.scopes.values.first?.cursor, 1)
    }

    @MainActor
    func testAdaptiveExclusionLeavesHoleAndAbandonmentDoesNotReturnAcceptedPosition() throws {
        let source = FocusedQuizInMemoryRotationStore(), rotation = NFOfflineQuestionRotation(store: source)
        let repository = NFLocalSessionRepository(), profile = UUID()
        let request = adaptiveRequest(profile: profile)
        let initial = try repository.prepareAdaptiveItem(request: request, predecessor: nil, rotation: rotation,
            bank: NFOfflineQuestionBank.rotationBank, quarantinedItemIDs: [], at: Date())
        let excluded = Set([try XCTUnwrap(initial.checkpoint.exercise?.id)])
        let eligible = try repository.prepareAdaptiveItem(request: request, predecessor: nil, rotation: rotation,
            bank: NFOfflineQuestionBank.rotationBank, quarantinedItemIDs: excluded, at: Date())
        XCTAssertEqual(eligible.receipt.plan.items.first?.stableOrdinal, 1)
        _ = try repository.acceptAdaptiveItem(eligible, checkpoint: eligible.checkpoint, rotation: rotation, quarantinedItemIDs: excluded)
        let scope = try XCTUnwrap(repository.archive.offlineRotationLedger?.scopes.values.first)
        XCTAssertEqual(scope.cursor, 0); XCTAssertEqual(scope.consumedEpochOrdinals, Set([1]))
        try repository.end(request.id)
        let reinstated = try repository.prepareAdaptiveItem(request: adaptiveRequest(profile: profile), predecessor: nil,
            rotation: rotation, bank: NFOfflineQuestionBank.rotationBank, quarantinedItemIDs: [], at: Date())
        XCTAssertEqual(reinstated.receipt.plan.items.first, initial.receipt.plan.items.first)
        _ = try repository.acceptAdaptiveItem(reinstated, checkpoint: reinstated.checkpoint, rotation: rotation, quarantinedItemIDs: [])
        XCTAssertEqual(repository.archive.offlineRotationLedger?.scopes.values.first?.cursor, 2)
        XCTAssertEqual(repository.archive.selectionLedger?.slots[eligible.receipt.slotID.uuidString]?.status, .abandoned)
        XCTAssertTrue(repository.archive.selectionLedger?.exposures.isEmpty == true)
    }

    @MainActor
    func testAdaptivePortableRecoveryCannotMintAuthorityAndDeletionRetainsConsumption() throws {
        let source = FocusedQuizInMemoryRotationStore(), rotation = NFOfflineQuestionRotation(store: source)
        let owner = UUID(), repository = NFLocalSessionRepository(ownerDeviceID: owner)
        let request = adaptiveRequest(profile: UUID())
        let prepared = try repository.prepareAdaptiveItem(request: request, predecessor: nil, rotation: rotation,
            bank: NFOfflineQuestionBank.rotationBank, quarantinedItemIDs: [], at: Date())
        let run = try repository.acceptAdaptiveItem(prepared, checkpoint: prepared.checkpoint, rotation: rotation, quarantinedItemIDs: [])
        let exported = repository.exportArchive
        XCTAssertNil(exported.adaptiveItemReceipts); XCTAssertNil(exported.offlineRotationLedger)
        let restored = NFLocalSessionRepository(ownerDeviceID: owner)
        try restored.importArchive(exported)
        XCTAssertEqual(restored.archive.sessions.first?.status, .migrationRecovery)
        XCTAssertThrowsError(try restored.prepareAdaptiveItem(request: request, predecessor: nil, rotation: rotation,
            bank: NFOfflineQuestionBank.rotationBank, quarantinedItemIDs: [], at: Date()))
        var forged = run
        forged.checkpoint.slotID = UUID(); forged.checkpoint.attemptID = UUID()
        XCTAssertThrowsError(try repository.save(forged))
        XCTAssertEqual(repository.archive.sessions.first?.checkpoint.slotID, run.checkpoint.slotID)
        try repository.removeReferences(attemptIDs: [run.checkpoint.attemptID])
        XCTAssertTrue(repository.archive.sessions.isEmpty)
        XCTAssertTrue(repository.archive.adaptiveItemReceipts?.isEmpty == true)
        XCTAssertTrue(repository.archive.deletedAdaptiveRunIDs?.contains(run.id) == true)
        XCTAssertEqual(repository.archive.offlineRotationLedger?.scopes.values.first?.cursor, 1)
        XCTAssertThrowsError(try repository.prepareAdaptiveItem(request: request, predecessor: nil, rotation: rotation,
            bank: NFOfflineQuestionBank.rotationBank, quarantinedItemIDs: [], at: Date()))
    }

    @MainActor
    func testAdaptiveAcceptanceAuthenticatesContractAndRejectsExtraConsumedPositions() throws {
        let source = FocusedQuizInMemoryRotationStore(), rotation = NFOfflineQuestionRotation(store: source)
        let repository = NFLocalSessionRepository(), request = adaptiveRequest(profile: UUID())
        let prepared = try repository.prepareAdaptiveItem(request: request, predecessor: nil, rotation: rotation,
            bank: NFOfflineQuestionBank.rotationBank, quarantinedItemIDs: [], at: Date())
        var body = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(prepared.checkpoint.exercise)) as? [String: Any])
        body["prompt"] = "A substituted prompt with the original descriptor seed"
        let forgedExercise = try JSONDecoder().decode(NFExercise.self, from: JSONSerialization.data(withJSONObject: body))
        XCTAssertEqual(forgedExercise.seed, prepared.checkpoint.exercise?.seed)
        var forgedCheckpoint = prepared.checkpoint
        forgedCheckpoint.exercise = forgedExercise; forgedCheckpoint.exerciseDigest = try NFLocalItemCheckpoint.digest(forgedExercise)
        forgedCheckpoint.semanticExclusions = [NFQuestionFingerprint.fingerprint(for: forgedExercise)]
        let old = prepared.receipt
        let forgedReceipt = NFLocalAdaptiveItemReceipt(decisionID: old.decisionID, sessionID: old.sessionID,
            ownerDeviceID: old.ownerDeviceID, configurationDigest: old.configurationDigest, questionIndex: old.questionIndex,
            predecessorSlotID: old.predecessorSlotID, slotID: old.slotID, attemptID: old.attemptID,
            exerciseDigest: forgedCheckpoint.exerciseDigest, plan: old.plan, eligibilityRevision: old.eligibilityRevision)
        let forged = NFLocalAdaptiveItemPreparation(expectedArchiveRevision: prepared.expectedArchiveRevision,
            expectedRunRevision: prepared.expectedRunRevision, request: prepared.request, receipt: forgedReceipt,
            checkpoint: forgedCheckpoint, replacementRotationLedger: prepared.replacementRotationLedger,
            importsLegacy: prepared.importsLegacy, legacySnapshot: prepared.legacySnapshot, replay: nil)
        XCTAssertThrowsError(try repository.acceptAdaptiveItem(forged, checkpoint: forgedCheckpoint, rotation: rotation, quarantinedItemIDs: []))
        XCTAssertTrue(repository.archive.sessions.isEmpty); XCTAssertNil(repository.archive.offlineRotationLedger)
        let extra = try rotation.prepareReservation(profileID: try XCTUnwrap(request.ordinaryDelivery?.profileID),
            lab: request.lab, itemCount: 2, bank: NFOfflineQuestionBank.rotationBank, loadedLedger: nil)
        let forgedDelta = NFLocalAdaptiveItemPreparation(expectedArchiveRevision: prepared.expectedArchiveRevision,
            expectedRunRevision: prepared.expectedRunRevision, request: prepared.request, receipt: prepared.receipt,
            checkpoint: prepared.checkpoint, replacementRotationLedger: extra.replacement,
            importsLegacy: prepared.importsLegacy, legacySnapshot: prepared.legacySnapshot, replay: nil)
        XCTAssertThrowsError(try repository.acceptAdaptiveItem(forgedDelta, checkpoint: prepared.checkpoint, rotation: rotation, quarantinedItemIDs: []))
        XCTAssertTrue(repository.archive.sessions.isEmpty); XCTAssertNil(repository.archive.selectionLedger)
        _ = try repository.acceptAdaptiveItem(prepared, checkpoint: prepared.checkpoint, rotation: rotation, quarantinedItemIDs: [])
        XCTAssertEqual(repository.archive.offlineRotationLedger?.scopes.values.first?.cursor, 1)
        XCTAssertEqual(repository.archive.sessions.first?.checkpoint.exercise, prepared.checkpoint.exercise)
    }

    @MainActor
    func testFutureOrdinaryDeliveryPinRemainsRetainedAndUnavailableAfterColdLoad() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "NFFutureAdaptivePin-\(UUID())")
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appending(path: "sessions.json"), owner = UUID()
        let source = FocusedQuizInMemoryRotationStore(), rotation = NFOfflineQuestionRotation(store: source)
        let repository = NFLocalSessionRepository(url: url, ownerDeviceID: owner)
        let request = adaptiveRequest(profile: UUID())
        let prepared = try repository.prepareAdaptiveItem(request: request, predecessor: nil, rotation: rotation,
            bank: NFOfflineQuestionBank.rotationBank, quarantinedItemIDs: [], at: Date())
        _ = try repository.acceptAdaptiveItem(prepared, checkpoint: prepared.checkpoint, rotation: rotation, quarantinedItemIDs: [])
        var future = repository.archive
        future.sessions[0].request.ordinaryDelivery?.schemaVersion = 999
        let bytes = try JSONEncoder().encode(future)
        try bytes.write(to: url)
        let restored = NFLocalSessionRepository(url: url, ownerDeviceID: owner)
        XCTAssertNil(restored.loadError)
        XCTAssertEqual(restored.archive.sessions.first?.status, .migrationRecovery)
        XCTAssertEqual(restored.archive.sessions.first?.request.ordinaryDelivery?.schemaVersion, 999)
        XCTAssertEqual(restored.archive.sessions.first?.checkpoint.exercise, prepared.checkpoint.exercise)
        XCTAssertEqual(restored.archive.adaptiveItemReceipts, repository.archive.adaptiveItemReceipts)
        XCTAssertThrowsError(try restored.prepareAdaptiveItem(request: try XCTUnwrap(restored.archive.sessions.first?.request),
            predecessor: nil, rotation: rotation, bank: NFOfflineQuestionBank.rotationBank, quarantinedItemIDs: [], at: Date()))
        XCTAssertEqual(try Data(contentsOf: url), bytes)
    }

    @MainActor
    func testAdaptiveSkipAndSolutionRevealRecordDistinctOutcomesBeforeNextAcceptance() throws {
        for reveal in [false, true] {
            let source = FocusedQuizInMemoryRotationStore()
            let (store, container) = try makeStore(rotationStore: source)
            defer { _ = container }
            XCTAssertTrue(store.beginSession(lab: .mentalMath, source: .focused, requestedItemCount: 2,
                seedOverride: 853, launchLocaleIdentifier: "en"))
            let request = try XCTUnwrap(store.activeSessionRequest)
            let original = try XCTUnwrap(request.localCheckpoint)
            let runtime = NFUniversalSessionRuntime(request: request)
            XCTAssertTrue(runtime.checkpointDraft(store: store)); runtime.acknowledgePresented()
            if reveal { runtime.revealSolution(store: store) }
            runtime.skip(store: store)
            XCTAssertNil(runtime.saveError); XCTAssertEqual(runtime.stage, .item); XCTAssertEqual(runtime.index, 1)
            XCTAssertEqual(store.attempts.count, 1)
            XCTAssertTrue(store.attempts.first?.wasSkipped == true)
            XCTAssertEqual(store.localSessions.archive.selectionLedger?.slots[original.slotID.uuidString]?.status, reveal ? .revealed : .skipped)
            XCTAssertEqual(store.localSessions.archive.adaptiveItemReceipts?.count, 2)
            XCTAssertEqual(store.localSessions.archive.offlineRotationLedger?.scopes.values.first?.cursor, 2)
            runtime.acknowledgePresented()
            runtime.skip(store: store)
            XCTAssertNil(runtime.saveError); XCTAssertEqual(runtime.stage, .summary)
            XCTAssertTrue(runtime.hasCompletedRun); XCTAssertFalse(runtime.hasSufficientAssessmentEvidence)
            XCTAssertTrue(runtime.correctness.isEmpty, "Ending a skip-only run does not create answered evidence or completion XP")
            XCTAssertEqual(store.attempts.count, 2)
            XCTAssertEqual(store.localSessions.archive.selectionLedger?.outcomes.count, 2)
            XCTAssertEqual(store.localSessions.archive.adaptiveItemReceipts?.count, 2)
            XCTAssertEqual(store.localSessions.archive.offlineRotationLedger?.scopes.values.first?.cursor, 2)
            runtime.releaseWriter()
        }
    }

    @MainActor
    func testAdaptiveDurationChoiceDoesNotConsumeUntilExactCountAlternativeIsAccepted() throws {
        let source = FocusedQuizInMemoryRotationStore()
        let (store, container) = try makeStore(rotationStore: source)
        defer { _ = container }
        XCTAssertTrue(store.beginSession(lab: .mentalMath, source: .focused, requestedMinutes: 3,
            field: .general, topic: "Retained count alternative", seedOverride: 857, launchLocaleIdentifier: "en"))
        let proposal = try XCTUnwrap(store.activeSessionRequest)
        XCTAssertEqual(proposal.ordinaryDelivery?.strategy, .adaptiveItem)
        XCTAssertNil(store.localSessions.archive.offlineRotationLedger)
        XCTAssertNil(store.localSessions.archive.adaptiveItemReceipts)
        let runtime = NFUniversalSessionRuntime(request: proposal)
        XCTAssertTrue(runtime.durationChoiceRequired)
        runtime.startCountBasedAlternative(store: store)
        let accepted = try XCTUnwrap(store.activeSessionRequest)
        XCTAssertEqual(accepted.requestedItemCount, 5); XCTAssertNil(accepted.requestedMinutes)
        XCTAssertEqual(accepted.ordinaryDelivery?.strategy, .adaptiveItem)
        XCTAssertEqual(accepted.topic, proposal.topic); XCTAssertEqual(accepted.localeIdentifier, proposal.localeIdentifier)
        XCTAssertEqual(accepted.timingCondition, proposal.timingCondition)
        XCTAssertEqual(accepted.localCheckpoint?.itemCount, 5)
        XCTAssertNil(accepted.offlineRotationPlan); XCTAssertTrue(accepted.offlineQuestionOrdinals.isEmpty)
        XCTAssertEqual(store.localSessions.archive.adaptiveItemReceipts?.count, 1)
        XCTAssertEqual(store.localSessions.archive.offlineRotationLedger?.scopes.values.first?.cursor, 1)
        XCTAssertTrue(store.localSessions.archive.selectionLedger?.exposures.isEmpty == true)
        XCTAssertNil(try source.load())
    }

    @MainActor
    func testAdaptiveReplaceRetainsUnsubmittedDraftAssistanceAndKnownTimeWithoutScoring() throws {
        let (store, container) = try makeStore(rotationStore: FocusedQuizInMemoryRotationStore())
        defer { _ = container }
        XCTAssertTrue(store.beginSession(lab: .mentalMath, source: .focused, requestedItemCount: 5,
            seedOverride: 823, launchLocaleIdentifier: "en"))
        let request = try XCTUnwrap(store.activeSessionRequest)
        var clock: TimeInterval = 0
        let runtime = NFUniversalSessionRuntime(request: request, monotonicNow: { clock })
        defer { runtime.releaseWriter() }
        XCTAssertTrue(runtime.checkpointDraft(store: store)); runtime.acknowledgePresented()
        let originalID = try XCTUnwrap(store.localSessions.archive.sessions.first?.checkpoint.slotID)
        let originalExercise = runtime.exercise
        runtime.scratchpad = "Keep my derivation: 37 × 4"
        clock = 12
        runtime.requestHint(store: store)
        XCTAssertEqual(runtime.hintCount, 1)
        fillAuthoritativeResponse(runtime)
        XCTAssertTrue(runtime.checkpointDraft(store: store))
        let draft = try XCTUnwrap(store.localSessions.archive.sessions.first?.checkpoint)
        let attemptsBefore = store.attempts.count
        clock = 17
        XCTAssertTrue(runtime.canReplaceCurrentItem)
        runtime.replaceCurrentItem(store: store)
        XCTAssertNil(runtime.saveError); XCTAssertNil(runtime.replacementUnavailableReason)
        XCTAssertEqual(runtime.stage, .item); XCTAssertEqual(runtime.index, 0); XCTAssertEqual(runtime.itemCount, 5)
        XCTAssertFalse(runtime.isPaused); XCTAssertTrue(runtime.isDurablyPrepared)
        let archive = store.localSessions.archive
        let current = try XCTUnwrap(archive.sessions.first?.checkpoint)
        let retired = try XCTUnwrap(archive.retiredOrdinaryDrafts?[originalID.uuidString])
        XCTAssertNotEqual(current.slotID, originalID); XCTAssertNotEqual(current.attemptID, draft.attemptID)
        XCTAssertEqual(retired.checkpoint.response, draft.response)
        XCTAssertEqual(retired.checkpoint.confidence, .certain)
        XCTAssertEqual(retired.checkpoint.scratchpad, draft.scratchpad)
        XCTAssertEqual(retired.checkpoint.hintCount, 1)
        XCTAssertEqual(retired.checkpoint.assistanceEvents, draft.assistanceEvents)
        XCTAssertEqual(retired.checkpoint.itemActiveDuration, 17, accuracy: 0.001)
        XCTAssertNil(retired.checkpoint.exercise)
        XCTAssertEqual(retired.eventKind, "itemReplacedByUser")
        let oldSlot = try XCTUnwrap(archive.selectionLedger?.slots[originalID.uuidString])
        let snapshot = try XCTUnwrap(NFSelectionReservationPolicy.snapshot(for: oldSlot, in: try XCTUnwrap(archive.selectionLedger)))
        XCTAssertEqual(try JSONDecoder().decode(NFExercise.self, from: snapshot.payload), originalExercise)
        XCTAssertEqual(oldSlot.status, .replaced)
        XCTAssertEqual(current.cumulativeActiveDuration, 17, accuracy: 0.001)
        XCTAssertEqual(current.itemActiveDuration, 0)
        XCTAssertEqual(current.sittingActiveDuration, 17)
        XCTAssertEqual(current.scratchpad, draft.scratchpad)
        XCTAssertEqual(current.hintCount, 0); XCTAssertNil(current.confidence)
        XCTAssertTrue(current.correctness.isEmpty); XCTAssertTrue(current.credits.isEmpty)
        XCTAssertEqual(current.interruptionCount, 0)
        XCTAssertEqual(store.attempts.count, attemptsBefore)
        XCTAssertEqual(archive.selectionLedger?.exposures.count, 1, "Preparing the replacement is not a presentation")
        XCTAssertEqual(archive.offlineRotationLedger?.scopes.values.first?.cursor, 2)
        clock = 100
        XCTAssertTrue(runtime.checkpointDraft(store: store))
        XCTAssertEqual(store.localSessions.archive.sessions.first?.checkpoint.itemActiveDuration, 0)
        XCTAssertEqual(runtime.sittingActiveElapsed(), 17, accuracy: 0.001)
        runtime.acknowledgePresented()
        clock = 103
        XCTAssertTrue(runtime.checkpointDraft(store: store))
        XCTAssertEqual(store.localSessions.archive.sessions.first?.checkpoint.itemActiveDuration, 3)
        XCTAssertEqual(runtime.sittingActiveElapsed(), 20, accuracy: 0.001)
        XCTAssertEqual(store.localSessions.archive.selectionLedger?.exposures.count, 2)
    }

    @MainActor
    func testAdaptiveRepeatedReplaceThenNextKeepsQuestionCountAndColdExactPath() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "NFReplacePath-\(UUID())")
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appending(path: "sessions.json"), owner = UUID()
        let repository = NFLocalSessionRepository(url: url, ownerDeviceID: owner)
        let (store, container) = try makeStore(rotationStore: FocusedQuizInMemoryRotationStore(), repository: repository)
        defer { _ = container }
        XCTAssertTrue(store.beginSession(lab: .mentalMath, source: .focused, requestedItemCount: 5,
            seedOverride: 827, launchLocaleIdentifier: "en"))
        let request = try XCTUnwrap(store.activeSessionRequest)
        let runtime = NFUniversalSessionRuntime(request: request)
        XCTAssertTrue(runtime.checkpointDraft(store: store)); runtime.acknowledgePresented()
        for _ in 0..<2 {
            runtime.replaceCurrentItem(store: store)
            XCTAssertNil(runtime.saveError); XCTAssertEqual(runtime.index, 0)
            runtime.acknowledgePresented()
        }
        fillAuthoritativeResponse(runtime); runtime.submitInline(store: store)
        XCTAssertEqual(runtime.stage, .feedback); XCTAssertFalse(runtime.canReplaceCurrentItem)
        runtime.next(store: store)
        XCTAssertNil(runtime.saveError); XCTAssertEqual(runtime.index, 1); XCTAssertEqual(runtime.itemCount, 5)
        XCTAssertEqual(store.attempts.count, 1)
        let ledger = try XCTUnwrap(repository.archive.selectionLedger)
        let run = try XCTUnwrap(ledger.runs[request.id.uuidString])
        XCTAssertEqual(run.slotIDs.count, 4); XCTAssertEqual(run.nextDecisionOrdinal, 4)
        XCTAssertEqual(run.slotIDs.compactMap { ledger.slots[$0]?.plannedQuestionOrdinal }, [0, 0, 0, 1])
        XCTAssertEqual(run.slotIDs.compactMap { ledger.slots[$0]?.status }, [.replaced, .replaced, .answered, .reserved])
        XCTAssertEqual(repository.archive.retiredOrdinaryDrafts?.count, 2)
        XCTAssertEqual(repository.archive.adaptiveItemReceipts?.count, 4)
        XCTAssertEqual(repository.archive.offlineRotationLedger?.scopes.values.first?.cursor, 4)
        let saved = try XCTUnwrap(repository.archive.sessions.first)
        runtime.releaseWriter()
        let reopened = NFLocalSessionRepository(url: url, ownerDeviceID: owner)
        XCTAssertNil(reopened.loadError)
        XCTAssertEqual(reopened.archive.sessions.first?.checkpoint, saved.checkpoint)
        XCTAssertEqual(reopened.archive.selectionLedger, ledger)
        XCTAssertEqual(reopened.archive.retiredOrdinaryDrafts, repository.archive.retiredOrdinaryDrafts)
        var resumed = saved.request; resumed.localCheckpoint = saved.checkpoint; resumed.localSessionID = saved.id
        let cold = NFUniversalSessionRuntime(request: resumed)
        XCTAssertEqual(cold.exercise, runtime.exercise); XCTAssertEqual(cold.index, 1); XCTAssertTrue(cold.isPaused)
    }

    @MainActor
    func testAdaptiveReplaceRetryIsIdempotentAndCannotRewriteRetiredOrCurrentDraft() throws {
        let repository = NFLocalSessionRepository(), request = adaptiveRequest(profile: UUID())
        let rotation = NFOfflineQuestionRotation(store: FocusedQuizInMemoryRotationStore())
        let launch = try repository.prepareAdaptiveItem(request: request, predecessor: nil, rotation: rotation,
            bank: NFOfflineQuestionBank.rotationBank, quarantinedItemIDs: [], at: Date())
        var original = try repository.acceptAdaptiveItem(launch, checkpoint: launch.checkpoint, rotation: rotation, quarantinedItemIDs: [])
        original.checkpoint.scratchpad = "Original unsubmitted derivation"
        original.checkpoint.itemActiveDuration = 9; original.checkpoint.sittingActiveDuration = 11
        original.revision += 1
        try repository.save(original)
        let writer = UUID()
        XCTAssertTrue(repository.claimWriter(writer, sessionID: request.id, checkpoint: { true }))
        defer { repository.releaseWriter(writer) }
        let writerCommand = try repository.sessionCommand(authority: repository.writerAuthority(for: writer, sessionID: request.id), sessionID: request.id)
        let prepared = try repository.prepareAdaptiveReplacement(request: request, predecessor: original.checkpoint,
            rotation: rotation, bank: NFOfflineQuestionBank.rotationBank, quarantinedItemIDs: [], at: Date(), command: writerCommand)
        var forged = prepared.checkpoint
        forged.correctness = [true]; forged.credits = [1]
        XCTAssertThrowsError(try repository.acceptAdaptiveItem(prepared, checkpoint: forged, rotation: rotation, quarantinedItemIDs: []))
        XCTAssertEqual(repository.archive.sessions.first?.checkpoint, original.checkpoint)
        XCTAssertNil(repository.archive.retiredOrdinaryDrafts)
        var accepted = try repository.acceptAdaptiveItem(prepared, checkpoint: prepared.checkpoint, rotation: rotation, quarantinedItemIDs: [])
        accepted.checkpoint.scratchpad = "Replacement edited after acknowledgement"
        accepted.revision += 1
        try repository.save(accepted)
        let revision = repository.archive.transactionRevision
        let replay = try repository.prepareAdaptiveReplacement(request: request, predecessor: original.checkpoint,
            rotation: rotation, bank: NFOfflineQuestionBank.rotationBank, quarantinedItemIDs: [], at: Date(), command: writerCommand)
        XCTAssertEqual(replay.receipt.decisionID, prepared.receipt.decisionID)
        XCTAssertEqual(replay.checkpoint, accepted.checkpoint)
        XCTAssertEqual(try repository.acceptAdaptiveItem(prepared, checkpoint: prepared.checkpoint,
            rotation: rotation, quarantinedItemIDs: []).checkpoint, accepted.checkpoint)
        XCTAssertEqual(repository.archive.transactionRevision, revision)
        XCTAssertEqual(repository.archive.retiredOrdinaryDrafts?.count, 1)
        XCTAssertEqual(repository.archive.offlineRotationLedger?.scopes.values.first?.cursor, 2)
        var changedOriginal = original.checkpoint; changedOriginal.scratchpad = "Different predecessor proposal"
        XCTAssertThrowsError(try repository.prepareAdaptiveReplacement(request: request, predecessor: changedOriginal,
            rotation: rotation, bank: NFOfflineQuestionBank.rotationBank, quarantinedItemIDs: [], at: Date(), command: writerCommand))
        XCTAssertThrowsError(try repository.save(original), "A stale writer cannot reactivate the retired slot")
        XCTAssertEqual(repository.archive.sessions.first?.checkpoint, accepted.checkpoint)
    }

    @MainActor
    func testAdaptiveReplaceBusyPublicationAndEligibilityChangePreserveOriginalAndSameRetry() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "NFReplaceFailure-\(UUID())")
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appending(path: "sessions.json")
        let repository = NFLocalSessionRepository(url: url), request = adaptiveRequest(profile: UUID())
        let rotation = NFOfflineQuestionRotation(store: FocusedQuizInMemoryRotationStore())
        let launch = try repository.prepareAdaptiveItem(request: request, predecessor: nil, rotation: rotation,
            bank: NFOfflineQuestionBank.rotationBank, quarantinedItemIDs: [], at: Date())
        let original = try repository.acceptAdaptiveItem(launch, checkpoint: launch.checkpoint, rotation: rotation, quarantinedItemIDs: [])
        let writer = UUID()
        XCTAssertTrue(repository.claimWriter(writer, sessionID: request.id, checkpoint: { true }))
        defer { repository.releaseWriter(writer) }
        let writerCommand = try repository.sessionCommand(authority: repository.writerAuthority(for: writer, sessionID: request.id), sessionID: request.id)
        let prepared = try repository.prepareAdaptiveReplacement(request: request, predecessor: original.checkpoint,
            rotation: rotation, bank: NFOfflineQuestionBank.rotationBank, quarantinedItemIDs: [], at: Date(), command: writerCommand)
        let bytes = try Data(contentsOf: url)
        let cursor = repository.archive.offlineRotationLedger
        let excluded = try XCTUnwrap(prepared.checkpoint.exercise?.id)
        XCTAssertThrowsError(try repository.acceptAdaptiveItem(prepared, checkpoint: prepared.checkpoint,
            rotation: rotation, quarantinedItemIDs: [excluded]))
        let fd = Darwin.open(url.path + ".lock", O_RDWR)
        guard fd >= 0 else { return XCTFail("Could not open the publication lock") }
        defer { Darwin.close(fd) }
        guard flock(fd, LOCK_EX | LOCK_NB) == 0 else { return XCTFail("Could not acquire the competing lock") }
        let releaseRequested = DispatchSemaphore(value: 0), released = DispatchSemaphore(value: 0)
        DispatchQueue.global().async {
            _ = releaseRequested.wait(timeout: .now() + 5)
            flock(fd, LOCK_UN); released.signal()
        }
        XCTAssertThrowsError(try repository.acceptAdaptiveItem(prepared, checkpoint: prepared.checkpoint,
            rotation: rotation, quarantinedItemIDs: [])) { error in
            guard case .busy? = error as? NFLocalSessionRepository.RepositoryError else { return XCTFail("Expected recoverable busy: \(error)") }
        }
        releaseRequested.signal(); released.wait()
        XCTAssertEqual(try Data(contentsOf: url), bytes)
        XCTAssertEqual(repository.archive.sessions.first?.checkpoint, original.checkpoint)
        XCTAssertEqual(repository.archive.offlineRotationLedger, cursor)
        XCTAssertNil(repository.archive.retiredOrdinaryDrafts)
        let accepted = try repository.acceptAdaptiveItem(prepared, checkpoint: prepared.checkpoint, rotation: rotation, quarantinedItemIDs: [])
        XCTAssertEqual(accepted.checkpoint.slotID, prepared.receipt.slotID)
        XCTAssertEqual(repository.archive.retiredOrdinaryDrafts?.count, 1)
        XCTAssertEqual(repository.archive.offlineRotationLedger?.scopes.values.first?.cursor, 2)
    }

    @MainActor
    func testAdaptiveSchemaOneReceiptCanReplaceWhileFutureOperationRemainsRecoveryOnly() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "NFReplaceVersions-\(UUID())")
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appending(path: "sessions.json"), owner = UUID()
        let original = NFLocalSessionRepository(url: url, ownerDeviceID: owner)
        let request = adaptiveRequest(profile: UUID()), rotation = NFOfflineQuestionRotation(store: FocusedQuizInMemoryRotationStore())
        let launch = try original.prepareAdaptiveItem(request: request, predecessor: nil, rotation: rotation,
            bank: NFOfflineQuestionBank.rotationBank, quarantinedItemIDs: [], at: Date())
        _ = try original.acceptAdaptiveItem(launch, checkpoint: launch.checkpoint, rotation: rotation, quarantinedItemIDs: [])
        var legacy = original.archive
        var oldReceipt = launch.receipt
        oldReceipt.schemaVersion = 1; oldReceipt.operationRaw = nil; oldReceipt.decisionOrdinal = nil
        oldReceipt.predecessorCheckpointDigest = nil
        legacy.adaptiveItemReceipts?[oldReceipt.decisionID] = oldReceipt
        try JSONEncoder().encode(legacy).write(to: url)
        let repository = NFLocalSessionRepository(url: url, ownerDeviceID: owner)
        XCTAssertNil(repository.loadError)
        let prior = try XCTUnwrap(repository.archive.sessions.first)
        let writer = UUID()
        XCTAssertTrue(repository.claimWriter(writer, sessionID: request.id, checkpoint: { true }))
        defer { repository.releaseWriter(writer) }
        let writerCommand = try repository.sessionCommand(authority: repository.writerAuthority(for: writer, sessionID: request.id), sessionID: request.id)
        let replacement = try repository.prepareAdaptiveReplacement(request: request, predecessor: prior.checkpoint,
            rotation: rotation, bank: NFOfflineQuestionBank.rotationBank, quarantinedItemIDs: [], at: Date(), command: writerCommand)
        _ = try repository.acceptAdaptiveItem(replacement, checkpoint: replacement.checkpoint, rotation: rotation, quarantinedItemIDs: [])
        XCTAssertEqual(repository.archive.adaptiveItemReceipts?[oldReceipt.decisionID], oldReceipt)
        XCTAssertEqual(replacement.receipt.schemaVersion, 2)
        XCTAssertEqual(replacement.receipt.operation, .replace)
        XCTAssertEqual(replacement.receipt.effectiveDecisionOrdinal, 1)
        XCTAssertEqual(replacement.receipt.questionIndex, 0)
        var future = repository.archive
        future.adaptiveItemReceipts?[replacement.receipt.decisionID]?.operationRaw = "future-replacement-policy"
        let futureBytes = try JSONEncoder().encode(future); try futureBytes.write(to: url)
        let recovery = NFLocalSessionRepository(url: url, ownerDeviceID: owner)
        XCTAssertNil(recovery.loadError)
        XCTAssertEqual(recovery.archive.sessions.first?.status, .migrationRecovery)
        let recoveryWriter = UUID()
        XCTAssertTrue(recovery.claimWriter(recoveryWriter, sessionID: request.id, checkpoint: { true }))
        defer { recovery.releaseWriter(recoveryWriter) }
        let recoveryCommand = try recovery.sessionCommand(authority: recovery.writerAuthority(for: recoveryWriter, sessionID: request.id), sessionID: request.id)
        XCTAssertThrowsError(try recovery.prepareAdaptiveReplacement(request: request,
            predecessor: try XCTUnwrap(recovery.archive.sessions.first?.checkpoint), rotation: rotation,
            bank: NFOfflineQuestionBank.rotationBank, quarantinedItemIDs: [], at: Date(), command: recoveryCommand))
        XCTAssertEqual(try Data(contentsOf: url), futureBytes)
        XCTAssertEqual(recovery.archive.retiredOrdinaryDrafts, repository.archive.retiredOrdinaryDrafts)
        var futureDraft = repository.archive
        futureDraft.retiredOrdinaryDrafts?[prior.checkpoint.slotID.uuidString]?.schemaVersion = 999
        let retainedBytes = try JSONEncoder().encode(futureDraft); try retainedBytes.write(to: url)
        let retainedRecovery = NFLocalSessionRepository(url: url, ownerDeviceID: owner)
        XCTAssertNil(retainedRecovery.loadError)
        XCTAssertEqual(retainedRecovery.archive.sessions.first?.status, .migrationRecovery)
        var forgedWritable = try XCTUnwrap(retainedRecovery.archive.sessions.first)
        forgedWritable.status = .suspended
        XCTAssertThrowsError(try retainedRecovery.save(forgedWritable))
        let retainedRecoveryWriter = UUID()
        XCTAssertTrue(retainedRecovery.claimWriter(retainedRecoveryWriter, sessionID: request.id, checkpoint: { true }))
        defer { retainedRecovery.releaseWriter(retainedRecoveryWriter) }
        let retainedCommand = try retainedRecovery.sessionCommand(authority: retainedRecovery.writerAuthority(for: retainedRecoveryWriter, sessionID: request.id), sessionID: request.id)
        XCTAssertThrowsError(try retainedRecovery.prepareAdaptiveReplacement(request: request,
            predecessor: forgedWritable.checkpoint, rotation: rotation,
            bank: NFOfflineQuestionBank.rotationBank, quarantinedItemIDs: [], at: Date(), command: retainedCommand))
        XCTAssertEqual(try Data(contentsOf: url), retainedBytes)
    }

    @MainActor
    func testAdaptiveRetiredDraftPortableRecoveryAndDeletionTraverseWholePath() throws {
        let owner = UUID(), repository = NFLocalSessionRepository(ownerDeviceID: UUID())
        let request = adaptiveRequest(profile: UUID()), rotation = NFOfflineQuestionRotation(store: FocusedQuizInMemoryRotationStore())
        let launch = try repository.prepareAdaptiveItem(request: request, predecessor: nil, rotation: rotation,
            bank: NFOfflineQuestionBank.rotationBank, quarantinedItemIDs: [], at: Date())
        let first = try repository.acceptAdaptiveItem(launch, checkpoint: launch.checkpoint, rotation: rotation, quarantinedItemIDs: [])
        let writer = UUID()
        XCTAssertTrue(repository.claimWriter(writer, sessionID: request.id, checkpoint: { true }))
        defer { repository.releaseWriter(writer) }
        let writerCommand = try repository.sessionCommand(authority: repository.writerAuthority(for: writer, sessionID: request.id), sessionID: request.id)
        let replacement = try repository.prepareAdaptiveReplacement(request: request, predecessor: first.checkpoint,
            rotation: rotation, bank: NFOfflineQuestionBank.rotationBank, quarantinedItemIDs: [], at: Date(), command: writerCommand)
        _ = try repository.acceptAdaptiveItem(replacement, checkpoint: replacement.checkpoint, rotation: rotation, quarantinedItemIDs: [])
        let exported = repository.exportArchive
        XCTAssertNil(exported.adaptiveItemReceipts); XCTAssertNil(exported.offlineRotationLedger)
        XCTAssertEqual(exported.retiredOrdinaryDrafts, repository.archive.retiredOrdinaryDrafts)
        let imported = NFLocalSessionRepository(ownerDeviceID: owner)
        try imported.importArchive(exported)
        try imported.importArchive(exported)
        XCTAssertEqual(imported.archive.sessions.count, 1)
        XCTAssertEqual(imported.archive.retiredOrdinaryDrafts?.count, 1)
        XCTAssertEqual(imported.archive.sessions.first?.status, .migrationRecovery)
        XCTAssertEqual(imported.archive.retiredOrdinaryDrafts, repository.archive.retiredOrdinaryDrafts)
        let importedWriter = UUID()
        XCTAssertTrue(imported.claimWriter(importedWriter, sessionID: request.id, checkpoint: { true }))
        defer { imported.releaseWriter(importedWriter) }
        let importedCommand = try imported.sessionCommand(authority: imported.writerAuthority(for: importedWriter, sessionID: request.id), sessionID: request.id)
        XCTAssertThrowsError(try imported.prepareAdaptiveReplacement(request: request,
            predecessor: try XCTUnwrap(imported.archive.sessions.first?.checkpoint), rotation: rotation,
            bank: NFOfflineQuestionBank.rotationBank, quarantinedItemIDs: [], at: Date(), command: importedCommand))
        let consumption = repository.archive.offlineRotationLedger
        for target in [repository, imported] {
            try target.removeReferences(attemptIDs: [first.checkpoint.attemptID])
            XCTAssertTrue(target.archive.sessions.isEmpty)
            XCTAssertTrue(target.archive.retiredOrdinaryDrafts?.isEmpty == true)
            XCTAssertTrue(target.archive.selectionLedger?.slots.isEmpty == true)
            XCTAssertTrue(target.archive.selectionLedger?.snapshots.isEmpty == true)
            XCTAssertTrue(target.archive.selectionLedger?.decisions.isEmpty == true)
            XCTAssertTrue(target.archive.adaptiveItemReceipts?.isEmpty != false)
        }
        XCTAssertEqual(repository.archive.offlineRotationLedger, consumption)
        XCTAssertTrue(repository.archive.deletedAdaptiveRunIDs?.contains(request.id) == true)
        XCTAssertThrowsError(try repository.prepareAdaptiveItem(request: request, predecessor: nil, rotation: rotation,
            bank: NFOfflineQuestionBank.rotationBank, quarantinedItemIDs: [], at: Date()))
    }

    @MainActor
    func testAdaptiveReplaceFiniteTailShortageRetainsDraftAndDoesNotRerollEpoch() throws {
        let source = FocusedQuizInMemoryRotationStore(), rotation = NFOfflineQuestionRotation(store: source)
        let profile = UUID(), repository = NFLocalSessionRepository()
        _ = try rotation.reserve(profileID: profile, lab: .mentalMath, itemCount: 998, bank: NFOfflineQuestionBank.rotationBank)
        let request = adaptiveRequest(profile: profile)
        let launch = try repository.prepareAdaptiveItem(request: request, predecessor: nil, rotation: rotation,
            bank: NFOfflineQuestionBank.rotationBank, quarantinedItemIDs: [], at: Date())
        var original = try repository.acceptAdaptiveItem(launch, checkpoint: launch.checkpoint, rotation: rotation, quarantinedItemIDs: [])
        original.checkpoint.scratchpad = "My current question remains available"
        original.revision += 1; try repository.save(original)
        let writer = UUID()
        XCTAssertTrue(repository.claimWriter(writer, sessionID: request.id, checkpoint: { true }))
        defer { repository.releaseWriter(writer) }
        let writerCommand = try repository.sessionCommand(authority: repository.writerAuthority(for: writer, sessionID: request.id), sessionID: request.id)
        let available = try repository.prepareAdaptiveReplacement(request: request, predecessor: original.checkpoint,
            rotation: rotation, bank: NFOfflineQuestionBank.rotationBank, quarantinedItemIDs: [], at: Date(), command: writerCommand)
        let lastID = try XCTUnwrap(available.checkpoint.exercise?.id)
        let revision = repository.archive.transactionRevision
        XCTAssertThrowsError(try repository.prepareAdaptiveReplacement(request: request, predecessor: original.checkpoint,
            rotation: rotation, bank: NFOfflineQuestionBank.rotationBank, quarantinedItemIDs: [lastID], at: Date(), command: writerCommand)) { error in
            guard case .unavailableLaunch? = error as? NFLocalSessionRepository.RepositoryError else {
                return XCTFail("Expected explicit finite shortage: \(error)")
            }
        }
        XCTAssertEqual(repository.archive.transactionRevision, revision)
        XCTAssertEqual(repository.archive.sessions.first?.checkpoint, original.checkpoint)
        XCTAssertEqual(repository.archive.offlineRotationLedger?.scopes.values.first?.cursor, 999)
        XCTAssertEqual(repository.archive.offlineRotationLedger?.scopes.values.first?.epoch, 0)
        XCTAssertNil(repository.archive.retiredOrdinaryDrafts)
        let accepted = try repository.acceptAdaptiveItem(available, checkpoint: available.checkpoint,
            rotation: rotation, quarantinedItemIDs: [])
        XCTAssertEqual(accepted.checkpoint.exercise, available.checkpoint.exercise)
        XCTAssertEqual(accepted.checkpoint.index, original.checkpoint.index)
        XCTAssertEqual(available.receipt.plan.items.first?.epoch, 0)
        XCTAssertEqual(available.receipt.plan.items.first?.epochOrdinal, 999)
        XCTAssertEqual(repository.archive.offlineRotationLedger?.scopes.values.first?.cursor, 0)
        XCTAssertEqual(repository.archive.offlineRotationLedger?.scopes.values.first?.epoch, 1)
        XCTAssertTrue(repository.archive.offlineRotationLedger?.scopes.values.first?.containsConsumed(epoch: 0, ordinal: 999) == true)
    }

    private func adaptiveRequest(profile: UUID, id: UUID = UUID()) -> SessionRequest {
        var request = SessionRequest(lab: .mentalMath, source: .focused, seed: 839,
            localeIdentifier: "en", field: .general, requestedItemCount: 5)
        request.id = id; request.localSessionID = id
        request.ordinaryDelivery = .init(strategy: .adaptiveItem, profileID: profile, bank: NFOfflineQuestionBank.rotationBank)
        return request
    }

    @MainActor
    private func fillAuthoritativeResponse(_ runtime: NFUniversalSessionRuntime) {
        switch runtime.exercise.interaction {
        case let .numeric(schema): runtime.numericValue = String(schema.answer.value); runtime.numericUnit = schema.answer.canonicalUnit ?? ""
        case let .singleChoice(schema): runtime.singleChoiceID = schema.correctOptionID
        case let .multipleChoice(schema): runtime.multipleChoiceIDs = Set(schema.correctOptionIDs)
        case let .orderedSteps(schema): runtime.orderedStepIDs = schema.correctOrder
        case let .shortText(schema): runtime.shortText = schema.expectedAnswer
        case .selfCheck: XCTFail("Exact-bank mixed mathematics must have an authoritative response")
        case let .claimEvidence(schema): runtime.claimSelections = Dictionary(uniqueKeysWithValues: schema.correctPairs.map { ($0.claimID, Set($0.evidenceIDs)) })
        case let .logicState(schema): runtime.logicState = schema.expectedFinalState; runtime.violatedRuleID = schema.expectedViolatedRuleID
        }
        runtime.chooseConfidence(.certain)
    }

    @MainActor
    private func preparation(_ repository: NFLocalSessionRepository, commandID: UUID = UUID(),
                             rotation: NFOfflineQuestionRotation, profile: UUID) throws -> NFLocalFixedLaunchPreparation {
        try repository.prepareFixedLaunch(commandID: commandID, rotation: rotation, profileID: profile,
            lab: .mentalMath, laneID: "mixed", itemCount: 5, bank: NFOfflineQuestionBank.rotationBank)
    }

    private func fixedRequest(_ preparation: NFLocalFixedLaunchPreparation, baseSeed: UInt64 = 227,
                              quarantinedItemIDs: Set<String> = [], semanticExclusions: Set<String>? = nil) -> SessionRequest {
        var request = SessionRequest(lab: .mentalMath, source: .focused,
            seed: NFStableDeterminism.hash64("focused-launch|\(baseSeed)|\(preparation.plan.id)|mixed"),
            localeIdentifier: "en", field: .general, requestedItemCount: preparation.plan.items.count,
            offlineQuestionOrdinals: preparation.plan.items.compactMap {
                NFOfflineQuestionBank.ordinal(forQuestionID: $0.questionID, lab: .mentalMath)
            }, quarantinedItemIDs: quarantinedItemIDs)
        request.id = preparation.commandID; request.localSessionID = preparation.commandID
        request.offlineRotationPlan = preparation.plan
        request.repairSemanticExclusions = semanticExclusions
        return request
    }

    private func fingerprints(
        for request: SessionRequest,
        itemCount: Int
    ) -> [String] {
        var seen: Set<String> = []
        var sequence: [String] = []
        for index in 0..<itemCount {
            let exercise = NFDeterministicSessionExerciseFactory.makeExercise(
                request: request,
                index: index,
                assessmentDescriptor: nil,
                excludingContentFingerprints: seen
            )
            if exercise.availabilityReason != nil {
                XCTAssertLessThan(sequence.count, itemCount)
                let rejected = NFExerciseScoringEngine.score(.shortText("unavailable"), for: exercise)
                XCTAssertEqual(rejected.outcome, .invalidItem)
                return sequence
            }
            if let selected = NFDefaultContentCatalog.activities.first(where: { $0.mechanicID == request.mechanicID }) {
                if exercise.contractMetadata?.netFolding != nil {
                    XCTAssertEqual(request.netFoldingPolicyVersion, 1)
                    XCTAssertNotNil(NFNetFoldingContract.make(exercise: exercise))
                    XCTAssertEqual(selected.id, NFNetFoldingContract.familyID)
                    XCTAssertEqual(exercise.contractMetadata?.familyID, selected.id)
                } else if exercise.contractMetadata?.solidSection != nil {
                    XCTAssertEqual(request.solidSectionPolicyVersion, 1)
                    XCTAssertNotNil(NFSolidSectionContract.make(exercise: exercise))
                    XCTAssertEqual(selected.id, NFSolidSectionContract.familyID)
                } else if exercise.contractMetadata?.coordinateTransform != nil {
                    XCTAssertEqual(request.coordinateTransformPolicyVersion, 1)
                    XCTAssertEqual(NFCoordinateTransformContract.make(exercise: exercise)?.familyID, selected.id)
                } else if exercise.contractMetadata?.spatialStructure != nil {
                    // Opt-in labeled-face/occupied-cell recipes have new slugs.
                    // Require the entire authenticated typed contract and the
                    // exact originally chosen activity, not a permissive prefix.
                    XCTAssertEqual(request.spatialStructurePolicyVersion, 1)
                    XCTAssertEqual(NFSpatialStructureContract.make(exercise: exercise)?.familyID, selected.id)
                } else {
                    XCTAssertTrue(exercise.templateID.contains(selected.templateSlug), "Unexpected family: \(exercise.templateID) for \(selected.id)")
                }
            }
            let fingerprint = NFQuestionFingerprint.fingerprint(for: exercise)
            XCTAssertTrue(seen.insert(fingerprint).inserted, "A repeated item was presented before reporting pool exhaustion")
            sequence.append(fingerprint)
        }
        XCTAssertEqual(sequence.count, itemCount)
        return sequence
    }

    @MainActor
    private func makeStore(
        rotationStore: FocusedQuizInMemoryRotationStore,
        repository: NFLocalSessionRepository? = nil
    ) throws -> (store: AppStore, container: ModelContainer) {
        let schema = Schema([
            UserProfileRecord.self,
            InputCalibrationRecord.self,
            ProgressAnnotationRecord.self,
            AttemptRecord.self,
            AttemptReflectionRecord.self,
            SourceDocumentRecord.self,
            SourceChunkRecord.self,
            AIGenerationRecord.self,
            WeeklyTransferStateRecord.self,
            ReassessmentStateRecord.self,
            SessionCheckpointRecord.self,
            DailyPlanRecord.self,
            ItemReportRecord.self
        ])
        let container = try ModelContainer(
            for: schema,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        return (
            AppStore(
                context: container.mainContext,
                localSessionRepository: repository,
                offlineQuestionRotation: NFOfflineQuestionRotation(store: rotationStore)
            ),
            container
        )
    }
}

private final class FocusedQuizInMemoryRotationStore:
    NFOfflineQuestionRotationStateStoring,
    @unchecked Sendable
{
    private let lock = NSLock()
    private var ledger: NFOfflineQuestionRotationLedger?
    private var failsReads = false

    func setFailsReads(_ value: Bool) { lock.withLock { failsReads = value } }

    func load() throws -> NFOfflineQuestionRotationLedger? {
        try lock.withLock {
            if failsReads { throw NFOfflineQuestionRotationError.corruptPersistedState }
            return ledger
        }
    }

    func compareAndSwap(
        expectedRevision: UInt64?,
        replacement: NFOfflineQuestionRotationLedger
    ) -> Bool {
        lock.withLock {
            guard ledger?.revision == expectedRevision else { return false }
            ledger = replacement
            return true
        }
    }
}

extension FocusedQuizRotationIntegrationTests {
    @MainActor
    func testAdaptiveNextAndReplacementRefuseExhaustedRevisionUnderValidWriterWithoutConsumption() throws {
        for replacing in [false, true] {
            let root = FileManager.default.temporaryDirectory.appending(path: "NFAdaptiveRevision-\(UUID())")
            defer { try? FileManager.default.removeItem(at: root) }
            let repository = NFLocalSessionRepository(url: root.appending(path: "sessions.json"))
            let (store, container) = try makeStore(rotationStore: FocusedQuizInMemoryRotationStore(), repository: repository)
            _ = container
            XCTAssertTrue(store.beginSession(lab: .mentalMath, source: .focused, requestedItemCount: 5,
                seedOverride: 823, launchLocaleIdentifier: "en"))
            let runtime = NFUniversalSessionRuntime(request: try XCTUnwrap(store.activeSessionRequest))
            XCTAssertTrue(runtime.checkpointDraft(store: store)); runtime.acknowledgePresented()
            if !replacing {
                fillAuthoritativeResponse(runtime)
                runtime.submitInline(store: store)
                XCTAssertEqual(runtime.stage, .feedback); XCTAssertEqual(store.attempts.count, 1)
            }
            var maximal = try XCTUnwrap(repository.archive.sessions.first)
            maximal.revision = Int.max
            try repository.save(maximal) // A retained/imported counter, without renewing this valid writer.
            let command = try runtime.sessionWriterCommand()
            let prepared = try replacing
                ? store.prepareAdaptiveReplacement(request: maximal.request, predecessor: maximal.checkpoint, command: command)
                : store.prepareAdaptiveItem(request: maximal.request, predecessor: maximal.checkpoint, command: command)
            XCTAssertEqual(prepared.expectedRunRevision, Int.max)
            var proposed = prepared.checkpoint
            if !replacing {
                let prior = maximal.checkpoint
                proposed.scratchpad = prior.scratchpad
                proposed.correctness = prior.correctness; proposed.credits = prior.credits
                proposed.assessmentDescriptorIDs = prior.assessmentDescriptorIDs
                proposed.assessmentEvents = prior.assessmentEvents
                proposed.cumulativeActiveDuration = prior.cumulativeActiveDuration
                proposed.assessmentPracticeDuration = prior.assessmentPracticeDuration
                proposed.sittingOrdinal = prior.sittingOrdinal
                proposed.sittingActiveDuration = prior.sittingActiveDuration
                proposed.timingConditionOverride = prior.timingConditionOverride
                proposed.semanticExclusions.formUnion(prior.semanticExclusions)
            }
            let original = try Data(contentsOf: root.appending(path: "sessions.json"))
            let cursor = repository.archive.offlineRotationLedger
            XCTAssertThrowsError(try store.acceptAdaptiveItem(prepared, checkpoint: proposed)) {
                guard case NFLocalSessionRepository.RepositoryError.unsupportedVersion = $0 else {
                    return XCTFail("Expected checked revision refusal after genuine preparation: \($0)")
                }
            }
            XCTAssertEqual(try Data(contentsOf: root.appending(path: "sessions.json")), original)
            XCTAssertEqual(repository.archive.offlineRotationLedger, cursor)
            XCTAssertEqual(repository.archive.sessions.first?.revision, Int.max)
            XCTAssertEqual(store.attempts.count, replacing ? 0 : 1)
            runtime.releaseWriter()
        }
    }
}

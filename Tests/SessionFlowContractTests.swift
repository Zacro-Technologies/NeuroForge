import SwiftData
import XCTest
@testable import NeuroForge

final class SessionFlowContractTests: XCTestCase {
    private enum CheckpointFailure: Error { case expected }

    func testScratchpadPayloadRoundTripsNotesAndDrawingAndReadsLegacyText() {
        let payload = NFScratchpadPayload(
            notes: "A typed derivation",
            drawingData: Data([0x01, 0x02, 0xFE, 0xFF])
        )
        let stored = payload.storedValue

        XCTAssertTrue(stored.hasPrefix(NFScratchpadPayload.prefix))
        XCTAssertEqual(NFScratchpadPayload.decode(stored), payload)
        XCTAssertTrue(NFScratchpadPayload.decode(stored).hasNotes)
        XCTAssertTrue(NFScratchpadPayload.decode(stored).hasDrawing)

        let legacy = NFScratchpadPayload.decode("legacy plain-text scratchpad")
        XCTAssertEqual(legacy.notes, "legacy plain-text scratchpad")
        XCTAssertTrue(legacy.drawingData.isEmpty)
        XCTAssertEqual(NFScratchpadPayload(notes: "", drawingData: Data()).storedValue, "")
    }

    @MainActor
    func testNonAssessmentRuntimeRequiresAnAnsweredResultForSufficientEvidence() {
        let baseRequest = SessionRequest(
            lab: .logicDebugging,
            source: .focused,
            seed: 0xC011_EC7,
            evidenceClass: .practice
        )
        let empty = NFUniversalSessionRuntime(request: baseRequest)
        let skipOnly = NFUniversalSessionRuntime(request: SessionRequest(
            lab: .logicDebugging,
            source: .focused,
            seed: 0xC011_EC7,
            evidenceClass: .practice,
            resumedAssessmentEvents: ["skipped:non-assessment-item"]
        ))
        let answeredIncorrectly = NFUniversalSessionRuntime(request: SessionRequest(
            lab: .logicDebugging,
            source: .focused,
            seed: 0xC011_EC7,
            evidenceClass: .practice,
            resumedResults: [false]
        ))

        XCTAssertFalse(empty.hasSufficientAssessmentEvidence)
        XCTAssertFalse(skipOnly.hasSufficientAssessmentEvidence)
        XCTAssertTrue(answeredIncorrectly.hasSufficientAssessmentEvidence)
    }

    @MainActor
    func testCheckpointFailureKeepsDraftOpenAndRetryable() {
        let runtime = NFUniversalSessionRuntime(request: SessionRequest(
            lab: .logicDebugging,
            source: .focused,
            seed: 0x5A4E,
            evidenceClass: .practice
        ))
        runtime.scratchpad = "work that must not be discarded"

        var failedWriteCount = 0
        let failed = runtime.checkpointDraft(using: {
            failedWriteCount += 1
            throw CheckpointFailure.expected
        })

        XCTAssertFalse(failed)
        XCTAssertEqual(failedWriteCount, 1)
        XCTAssertEqual(runtime.stage, .item)
        XCTAssertEqual(runtime.scratchpad, "work that must not be discarded")
        XCTAssertNotNil(runtime.saveError)

        var retryWriteCount = 0
        let retried = runtime.checkpointDraft(using: { retryWriteCount += 1 })
        XCTAssertTrue(retried)
        XCTAssertEqual(retryWriteCount, 1)
        XCTAssertNil(runtime.saveError)
    }

    @MainActor
    func testTerminalSummaryCountsEveryPresentedOutcomeAndCannotPause() {
        let runtime = NFUniversalSessionRuntime(request: SessionRequest(
            lab: .logicDebugging,
            source: .focused,
            seed: 0xC0A7,
            evidenceClass: .practice,
            requestedItemCount: 3,
            startingIndex: 3,
            resumedResults: [true, false],
            resumedCredits: [1, 0.4],
            resumedAssessmentEvents: ["answered:first", "skipped:second", "answered:third"],
            resumeCurrentItemWasCommitted: true
        ))

        XCTAssertEqual(runtime.stage, .summary)
        XCTAssertEqual(runtime.correctCount, 1)
        XCTAssertEqual(runtime.incorrectCount, 1)
        XCTAssertEqual(runtime.skippedCount, 1)
        XCTAssertEqual(runtime.presentedCount, 3)

        runtime.pause()
        XCTAssertFalse(runtime.isPaused)
    }

    @MainActor
    func testTodaySequenceCarriesCanonicalRetentionTargetIntoSessionRequest() throws {
        let (store, container) = try makeStore()
        let due = AttemptRecord(
            sessionID: UUID(),
            lab: .mentalMath,
            itemID: "due-mental-item",
            prompt: "Compute the reviewed quantity.",
            response: "12",
            correctAnswer: "12",
            isCorrect: true,
            confidence: .fairlyConfident,
            evidenceClass: .practice,
            source: .focused
        )
        due.templateID = "nf.fallback.mentalMath.practice.v3.percent-change"
        due.submittedAt = Date().addingTimeInterval(-30 * 86_400)
        due.deterministicCredit = 1
        container.mainContext.insert(due)
        try container.mainContext.save()
        store.reload()

        let plan = store.todayPlan
        let review = try XCTUnwrap(plan.blocks.first {
            $0.kindRaw == NFDailyPlanBlockKind.retentionReview.rawValue
                && !$0.retentionItemIDs.isEmpty
        })
        let canonical = try XCTUnwrap(store.dailyPlans.first { $0.id == plan.id }?.snapshot)
        let canonicalReview = try XCTUnwrap(canonical.blocks.first { $0.id == review.id })
        let sequence = NFTodaySessionSequence()

        XCTAssertTrue(sequence.start(plan: plan, blockIDs: [review.id], store: store))
        let request = try XCTUnwrap(store.activeSessionRequest)
        XCTAssertEqual(request.retentionTargets, canonicalReview.retentionTargets)
        XCTAssertEqual(request.retentionItemIDs, canonicalReview.retentionTargets.map(\.memoryItemID))
        XCTAssertEqual(request.retentionTargets.first?.templateFamily, canonicalReview.retentionTargets.first?.templateFamily)
        XCTAssertEqual(request.retentionTargets.first?.alternateSeed, canonicalReview.retentionTargets.first?.alternateSeed)
        sequence.clear()
    }

    @MainActor
    func testTodaySequenceCarriesDailyTransferSourceIntoExerciseEvidence() throws {
        let (store, container) = try makeStore()
        _ = container
        let plan = store.todayPlan
        let transferBlock = try XCTUnwrap(plan.blocks.first {
            $0.kindRaw == NFDailyPlanBlockKind.unseenTransfer.rawValue
        })
        let targetSkillID = try XCTUnwrap(transferBlock.targetSkillID)
        let sourceLab = try XCTUnwrap(TrainingLab.allCases.first {
            $0.skillID == targetSkillID
        })
        let sequence = NFTodaySessionSequence()

        XCTAssertNotEqual(targetSkillID, TrainingLab.transfer.skillID)
        XCTAssertNotEqual(sourceLab, .transfer)
        XCTAssertTrue(sequence.start(
            plan: plan,
            blockIDs: [transferBlock.id],
            store: store
        ))

        let request = try XCTUnwrap(store.activeSessionRequest)
        let brief = try XCTUnwrap(request.transferBrief)
        XCTAssertEqual(brief.missionID, transferBlock.id)
        XCTAssertEqual(brief.seed, plan.seed)
        XCTAssertEqual(brief.kind, .multiRepresentationTransform)
        XCTAssertEqual(brief.labs, [sourceLab])
        XCTAssertEqual(brief.skillIDs, [targetSkillID])
        XCTAssertEqual(brief.requiredDimensions, ["representation"])

        let exercise = NFDeterministicSessionExerciseFactory.makeExercise(
            request: request,
            index: 0,
            assessmentDescriptor: nil
        )
        XCTAssertEqual(exercise.sourceContext.transferBrief, brief)
        XCTAssertEqual(exercise.sourceContext.targetSkills, [targetSkillID])
        XCTAssertEqual(
            Set(exercise.skillWeights.keys),
            Set([TrainingLab.transfer.skillID, targetSkillID])
        )
        XCTAssertEqual(exercise.skillWeights[targetSkillID] ?? -1, 0.6, accuracy: 1e-12)
        XCTAssertEqual(
            exercise.skillWeights[TrainingLab.transfer.skillID] ?? -1,
            0.4,
            accuracy: 1e-12
        )
        sequence.clear()
    }

    @MainActor
    func testTodaySequenceAdvancesAcrossSelectedBlocksWithoutChangingCanonicalPlan() throws {
        let (store, container) = try makeStore()
        _ = container
        let plan = store.todayPlan
        XCTAssertGreaterThanOrEqual(plan.blocks.count, 3)
        let selected = Array(plan.blocks.prefix(2))
        let sequence = NFTodaySessionSequence()

        sequence.clear()
        XCTAssertTrue(sequence.start(
            plan: plan,
            blockIDs: selected.map(\.id),
            store: store
        ))
        let firstRequest = try XCTUnwrap(store.activeSessionRequest)
        XCTAssertEqual(firstRequest.planID, plan.id)
        XCTAssertEqual(firstRequest.planBlockID, selected[0].id)

        try markComplete(firstRequest, store: store)
        XCTAssertEqual(
            sequence.nextBlock(
                after: firstRequest.planBlockID,
                planID: firstRequest.planID,
                store: store
            )?.id,
            selected[1].id
        )
        XCTAssertTrue(sequence.advance(
            after: firstRequest.planBlockID,
            planID: firstRequest.planID,
            store: store
        ))

        let secondRequest = try XCTUnwrap(store.activeSessionRequest)
        XCTAssertEqual(secondRequest.planBlockID, selected[1].id)
        XCTAssertEqual(store.todayPlan.id, plan.id)
        XCTAssertEqual(store.todayPlan.blocks.map(\.id), plan.blocks.map(\.id))

        try markComplete(secondRequest, store: store)
        XCTAssertFalse(sequence.advance(
            after: secondRequest.planBlockID,
            planID: secondRequest.planID,
            store: store
        ))
        XCTAssertEqual(
            store.completedPlanBlockIDs(planID: plan.id),
            Set(selected.map(\.id))
        )
        XCTAssertLessThan(
            store.completedPlanBlockIDs(planID: plan.id).count,
            plan.blocks.count,
            "A shortened sequence must leave the unselected canonical blocks available."
        )
        sequence.clear()
    }

    @MainActor
    func testTodaySequenceExcludesAlreadyCompletedBlocks() throws {
        let (store, container) = try makeStore()
        _ = container
        let plan = store.todayPlan
        let first = try XCTUnwrap(plan.blocks.first)
        let sequence = NFTodaySessionSequence()
        let synthetic = SessionRequest(
            lab: first.lab,
            source: .today,
            seed: plan.seed,
            planID: plan.id,
            planBlockID: first.id
        )
        try markComplete(synthetic, store: store)

        sequence.clear()
        XCTAssertTrue(sequence.start(
            plan: plan,
            blockIDs: plan.blocks.map(\.id),
            store: store
        ))
        XCTAssertNotEqual(store.activeSessionRequest?.planBlockID, first.id)
        sequence.clear()
    }

    func testLearningTextParserPreservesMixedBlockOrder() throws {
        let source = """
        Start with **known values**.

        ```swift
        let voltage = current * resistance
        ```

        $$
        V = I \\times R
        $$

        Then compare.

        \\[
        I = V / R
        \\]
        """

        let blocks = NFLearningTextParser.parse(source)
        XCTAssertEqual(blocks.count, 5)
        guard case let .markdown(introduction) = blocks[0],
              case let .code(language, code) = blocks[1],
              case let .displayMath(firstEquation) = blocks[2],
              case let .markdown(transition) = blocks[3],
              case let .displayMath(secondEquation) = blocks[4] else {
            return XCTFail("Mixed learning text did not preserve block order: \(blocks)")
        }

        XCTAssertTrue(introduction.contains("**known values**"))
        XCTAssertEqual(language, "swift")
        XCTAssertEqual(code, "let voltage = current * resistance")
        XCTAssertEqual(firstEquation, #"V = I \times R"#)
        XCTAssertTrue(transition.contains("Then compare."))
        XCTAssertEqual(secondEquation, "I = V / R")
    }

    func testLearningTextParserLeavesUnclosedFenceAsMarkdown() {
        let source = "Keep this literal: ```swift\nlet value = 4"
        XCTAssertEqual(NFLearningTextParser.parse(source), [.markdown(source)])
    }

    func testLearningTextEquationAccessibilityLabelExpandsCommonOperators() {
        XCTAssertEqual(
            NFLearningTextParser.accessibilityLabel(
                forEquation: #"x^2 + \frac{1}{2} \times y = 3"#
            ),
            "x to the power of 2 plus 1 divided by 2 times y equals 3"
        )
    }

    func testLearningTextEquationDisplayUsesReadableMathGlyphs() {
        XCTAssertEqual(
            NFLearningTextParser.displayText(
                forEquation: #"x^2 + \frac{1}{2} \times \Delta_0 \rightarrow y"#
            ),
            "x² + (1)⁄(2) × Δ₀ → y"
        )
    }

    func testLearningTextSourceMetadataPreservesCodeAndTableLineBreaks() {
        XCTAssertEqual(
            NFLearningTextParser.parse(
                "let first = 1\nlet second = 2",
                sourceLanguage: "swift",
                contentTypeTags: ["source-code"]
            ),
            [.code(language: "swift", source: "let first = 1\nlet second = 2")]
        )
        XCTAssertEqual(
            NFLearningTextParser.parse(
                "name,value\nalpha,4\nbeta,9",
                sourceLanguage: nil,
                contentTypeTags: ["csv", "rows"]
            ),
            [.code(language: "table", source: "name,value\nalpha,4\nbeta,9")]
        )
    }

    func testLearningTextSourceMetadataRoutesLatexToMathRenderer() {
        XCTAssertEqual(
            NFLearningTextParser.parse(
                #"\[x^2 + y^2 = z^2\]"#,
                sourceLanguage: "latex",
                contentTypeTags: ["equation"]
            ),
            [.displayMath(source: "x^2 + y^2 = z^2")]
        )
    }

    func testLearningTextMarkdownNeverMakesImportedLinksActionable() throws {
        let attributed = try XCTUnwrap(
            NFLearningTextParser.safeMarkdown("[Open](customscheme://untrusted)")
        )
        XCTAssertFalse(attributed.runs.contains { $0.link != nil })
        XCTAssertEqual(String(attributed.characters), "Open")
    }

    @MainActor
    private func markComplete(_ request: SessionRequest, store: AppStore) throws {
        try store.upsertCheckpoint(
            sessionID: UUID(),
            request: request,
            currentIndex: 0,
            itemCount: 1,
            response: "",
            scratchpad: "",
            results: [true],
            credits: [1],
            hasCommittedCurrentItem: true,
            isComplete: true
        )
    }

    @MainActor
    private func makeStore() throws -> (AppStore, ModelContainer) {
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
        var draft = OnboardingDraft()
        draft.stage = .professional
        draft.fields = [.engineering, .mathematics]
        draft.goals = [.mentalMath, .dataReasoning]
        draft.dailyDuration = 15
        draft.aiMode = .disabled
        draft.ageBandAcknowledged16Plus = true
        draft.keyboardLatencyMilliseconds = 75
        container.mainContext.insert(UserProfileRecord(draft: draft))
        try container.mainContext.save()
        return (AppStore(context: container.mainContext), container)
    }
}

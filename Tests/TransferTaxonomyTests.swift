import Foundation
import SwiftData
import XCTest

@testable import NeuroForge

final class TransferTaxonomyTests: XCTestCase {
    @MainActor
    func testWeeklyTransferRequestGenerationPersistenceAndMasteryNeverBecomeRetrieval() throws {
        let (store, container) = try makeStore()
        defer { _ = container }
        let brief = NFExerciseTransferBrief(
            missionID: "nf.transfer.weekly.v1.2026-W35.fixture",
            seed: 8_831,
            kind: .causalStructureComparison,
            labs: [.scientificReasoning, .logicDebugging],
            skillIDs: [TrainingLab.scientificReasoning.skillID, TrainingLab.logicDebugging.skillID],
            requiredDimensions: ["field", "representation"]
        )
        XCTAssertTrue(store.beginSession(
            lab: .transfer,
            source: .weeklyMission,
            evidenceClass: .appliedTransfer,
            requestedItemCount: 1,
            seedOverride: brief.seed,
            planID: brief.missionID,
            planBlockID: brief.missionID,
            isTimed: false,
            transferBrief: brief
        ))
        let request = try XCTUnwrap(store.activeSessionRequest)
        let exercise = NFDeterministicSessionExerciseFactory.makeExercise(
            request: request,
            index: 0,
            assessmentDescriptor: nil
        )
        XCTAssertNoThrow(try NFTransferTaxonomy.validate(request: request, exercise: exercise))
        XCTAssertEqual(exercise.lab, .transfer)
        XCTAssertEqual(exercise.evidenceClass, .appliedTransfer)
        XCTAssertGreaterThan(exercise.skillWeights[TrainingLab.transfer.skillID] ?? 0, 0)
        XCTAssertEqual(exercise.skillWeights[TrainingLab.retrieval.skillID] ?? 0, 0)

        let response = correctResponse(for: exercise.interaction)
        let score = NFExerciseScoringEngine.score(response, for: exercise)
        try store.saveExerciseAttempt(
            attemptID: UUID(),
            sessionID: request.id,
            exercise: exercise,
            response: response,
            result: score,
            confidence: .fairlyConfident,
            shownAt: .now.addingTimeInterval(-20),
            activeDuration: 20,
            source: .weeklyMission,
            planID: brief.missionID,
            planBlockID: brief.missionID
        )

        let attempt = try XCTUnwrap(store.attempts.first)
        XCTAssertNoThrow(try NFTransferTaxonomy.validate(attempt: attempt))
        XCTAssertEqual(attempt.gameID, TrainingLab.transfer.rawValue)
        XCTAssertEqual(attempt.skillID, TrainingLab.transfer.skillID)
        XCTAssertNil(attempt.skillWeights[TrainingLab.retrieval.skillID])

        let summaries = AdaptiveEngine.reduce([attempt.dto])
        XCTAssertEqual(summaries.first(where: { $0.lab == .transfer })?.evidenceCount, 0)
        XCTAssertEqual(NFHistoricalPracticeProjection.reduce(attempts: [attempt.dto]).first?.legacyCount, 1)
        XCTAssertEqual(summaries.first(where: { $0.lab == .retrieval })?.evidenceCount, 0)
    }

    @MainActor
    func testLegacyRetrievalRecordMigratesOnlyWithExplicitTransferProvenance() throws {
        let schema = Schema(NFSchemaV1.models)
        let container = try ModelContainer(
            for: schema,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let brief = NFExerciseTransferBrief(
            missionID: "nf.transfer.weekly.v1.legacy",
            seed: 44,
            kind: .abstractReconstruction,
            labs: [.quantitative, .logicDebugging],
            skillIDs: [TrainingLab.quantitative.skillID, TrainingLab.logicDebugging.skillID],
            requiredDimensions: ["field"]
        )
        let legacy = AttemptRecord(
            sessionID: UUID(),
            lab: .retrieval,
            itemID: "legacy-transfer",
            prompt: "Apply the structure in another field.",
            response: "mapped",
            correctAnswer: "mapped",
            isCorrect: true,
            confidence: .certain,
            evidenceClass: .appliedTransfer,
            source: .weeklyMission
        )
        legacy.planID = brief.missionID
        legacy.transferBriefRaw = String(
            data: try JSONEncoder().encode(brief),
            encoding: .utf8
        ) ?? ""
        legacy.skillID = TrainingLab.retrieval.skillID
        legacy.skillWeightsRaw = "{\"skill.retrieval\":1}"
        container.mainContext.insert(legacy)
        try container.mainContext.save()

        let historyURL = FileManager.default.temporaryDirectory
            .appending(path: "NF-Transfer-Migration-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: historyURL) }
        let store = AppStore(
            context: container.mainContext,
            adaptivePlanHistoryRepository: NFAdaptivePlanHistoryRepository(fileURL: historyURL)
        )
        let migrated = try XCTUnwrap(store.attempts.first)
        XCTAssertEqual(migrated.gameID, TrainingLab.transfer.rawValue)
        XCTAssertEqual(migrated.evidenceClassRaw, EvidenceClass.appliedTransfer.rawValue)
        XCTAssertEqual(migrated.skillID, TrainingLab.transfer.skillID)
        XCTAssertGreaterThan(migrated.skillWeights[TrainingLab.transfer.skillID] ?? 0, 0)
        XCTAssertNil(migrated.skillWeights[TrainingLab.retrieval.skillID])
    }

    private func correctResponse(for interaction: NFExerciseInteraction) -> NFExerciseResponse {
        switch interaction {
        case let .numeric(schema):
            .numeric(NFNumericSubmission(value: String(schema.answer.value), unit: schema.answer.canonicalUnit))
        case let .singleChoice(schema):
            .singleChoice(optionID: schema.correctOptionID)
        case let .multipleChoice(schema):
            .multipleChoice(optionIDs: schema.correctOptionIDs)
        case let .orderedSteps(schema):
            .orderedSteps(stepIDs: schema.correctOrder)
        case let .shortText(schema):
            .shortText(schema.expectedAnswer)
        case let .selfCheck(schema):
            .selfCheck(NFSelfCheckSubmission(
                rating: .matched,
                reflection: schema.asksForReflection ? "Matched the reference." : nil
            ))
        case let .claimEvidence(schema):
            .claimEvidence(NFClaimEvidenceSubmission(pairs: schema.correctPairs))
        case let .logicState(schema):
            .logicState(NFLogicStateSubmission(
                finalState: schema.expectedFinalState,
                violatedRuleID: schema.expectedViolatedRuleID
            ))
        }
    }

    @MainActor
    private func makeStore() throws -> (AppStore, ModelContainer) {
        let schema = Schema(NFSchemaV1.models)
        let container = try ModelContainer(
            for: schema,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let historyURL = FileManager.default.temporaryDirectory
            .appending(path: "NF-Transfer-History-\(UUID().uuidString).json")
        return (
            AppStore(
                context: container.mainContext,
                adaptivePlanHistoryRepository: NFAdaptivePlanHistoryRepository(fileURL: historyURL)
            ),
            container
        )
    }
}

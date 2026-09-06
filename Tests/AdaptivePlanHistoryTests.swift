import Foundation
import SwiftData
import XCTest

@testable import NeuroForge

final class AdaptivePlanHistoryTests: XCTestCase {
    func testRepositoryPersistsNewestBoundedRecordsInDeterministicOrder() throws {
        let url = temporaryHistoryURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let repository = NFAdaptivePlanHistoryRepository(fileURL: url)
        let profileID = UUID()
        let start = Date(timeIntervalSince1970: 2_000_000_000)
        var records: [NFAdaptivePlanChangeRecord] = []

        for index in 0..<(NFAdaptivePlanHistoryRepository.maximumRecordCount + 12) {
            records = try repository.appending(
                NFAdaptivePlanChangeRecord(
                    profileID: profileID,
                    occurredAt: start.addingTimeInterval(TimeInterval(index)),
                    kind: .readinessChanged,
                    title: "Change \(index)",
                    newState: "State \(index)",
                    reason: "Reason \(index)"
                ),
                to: records
            )
        }

        let restored = try repository.load()
        XCTAssertEqual(restored.count, NFAdaptivePlanHistoryRepository.maximumRecordCount)
        XCTAssertEqual(restored.first?.title, "Change 139")
        XCTAssertEqual(restored.last?.title, "Change 12")
        XCTAssertEqual(Set(restored.map(\.id)).count, restored.count)
    }

    func testRepositoryRejectsDuplicateRecordIdentities() throws {
        let url = temporaryHistoryURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let repository = NFAdaptivePlanHistoryRepository(fileURL: url)
        let record = NFAdaptivePlanChangeRecord(
            profileID: UUID(),
            kind: .preferencesApplied,
            title: "Preferences",
            newState: "Updated",
            reason: "Requested"
        )

        XCTAssertThrowsError(try repository.replacingHistory(with: [record, record])) { error in
            XCTAssertEqual(error as? NFAdaptivePlanHistoryError, .duplicateIdentity)
        }
    }

    @MainActor
    func testReadinessChangeIsExplainedAndCanBeSafelyUndoneBeforeWorkStarts() throws {
        let (store, container, historyURL) = try makeStore()
        defer {
            _ = container
            try? FileManager.default.removeItem(at: historyURL)
        }
        XCTAssertTrue(store.completeOnboarding(OnboardingDraft()))
        let originalPlan = store.todayPlan
        let existingHistoryIDs = Set(store.adaptivePlanHistory.map(\.id))

        store.updateReadiness(.low)
        let change = try XCTUnwrap(store.adaptivePlanHistory.first {
            $0.kind == .readinessChanged && !existingHistoryIDs.contains($0.id)
        })
        XCTAssertEqual(change.previousState, Readiness.normal.title)
        XCTAssertEqual(change.newState, Readiness.low.title)
        XCTAssertFalse(change.reason.isEmpty)
        XCTAssertTrue(store.canUndoAdaptivePlanChange(change))

        XCTAssertTrue(store.undoAdaptivePlanChange(change.id))
        XCTAssertEqual(store.readiness, .normal)
        XCTAssertEqual(store.todayPlan.id, originalPlan.id)
        XCTAssertTrue(store.reversedAdaptivePlanChangeIDs.contains(change.id))
        XCTAssertFalse(store.canUndoAdaptivePlanChange(change))
    }

    @MainActor
    func testPlanReplacementHasReasonAndUndoRestoresExactPayload() throws {
        let (store, container, historyURL) = try makeStore()
        defer {
            _ = container
            try? FileManager.default.removeItem(at: historyURL)
        }
        XCTAssertTrue(store.completeOnboarding(OnboardingDraft()))
        let plan = store.todayPlan
        let record = try XCTUnwrap(store.dailyPlans.first { $0.id == plan.id })
        let originalPayload = record.payload
        let originalBlock = try XCTUnwrap(plan.blocks.first)

        XCTAssertNotNil(store.replaceTodayPlanBlock(originalBlock.id, reason: .needVariety))
        let change = try XCTUnwrap(store.adaptivePlanHistory.first { $0.kind == .planReplaced })
        XCTAssertTrue(change.reason.localizedCaseInsensitiveContains(NFPlanReplacementReason.needVariety.title))
        XCTAssertTrue(store.canUndoAdaptivePlanChange(change))
        XCTAssertNotEqual(try XCTUnwrap(store.dailyPlans.first { $0.id == plan.id }).payload, originalPayload)

        XCTAssertTrue(store.undoAdaptivePlanChange(change.id))
        XCTAssertEqual(try XCTUnwrap(store.dailyPlans.first { $0.id == plan.id }).payload, originalPayload)
    }

    @MainActor
    func testReplacementPreviewAndCancellationDoNotConsumeOrChangeTheSavedPlan() throws {
        let (store, container, historyURL) = try makeStore()
        defer { _ = container; try? FileManager.default.removeItem(at: historyURL) }
        XCTAssertTrue(store.completeOnboarding(OnboardingDraft()))
        let plan = store.todayPlan, block = try XCTUnwrap(store.todayPlan.blocks.first)
        let record = try XCTUnwrap(store.dailyPlans.first { $0.id == plan.id })
        let original = record.payload, history = store.adaptivePlanHistory.map(\.id)
        let preview = try store.previewTodayPlanBlockReplacement(block.id, reason: .tooHard)
        XCTAssertEqual(preview.originalPayload, original)
        XCTAssertNotEqual(preview.replacementBlock.id, block.id)
        XCTAssertEqual(preview.replacementBlock.minutes, block.minutes)
        XCTAssertEqual(preview.replacementBlock.evidenceClass, block.evidenceClass)
        XCTAssertEqual(record.payload, original)
        XCTAssertEqual(store.adaptivePlanHistory.map(\.id), history)
        XCTAssertTrue(store.canReplaceTodayPlanBlock(block.id))
        // Cancel simply drops the immutable preview. A real store reload keeps
        // the exact bytes, no replacement/audit record and all original blocks.
        let cold = AppStore(context: container.mainContext,
            adaptivePlanHistoryRepository: NFAdaptivePlanHistoryRepository(fileURL: historyURL))
        XCTAssertEqual(cold.dailyPlans.first { $0.id == plan.id }?.payload, original)
        XCTAssertEqual(cold.todayPlan.blocks.map(\.id), plan.blocks.map(\.id))
    }

    @MainActor
    func testReplacementAppliesExactlyThePreviewAndPreservesEveryOtherBlock() throws {
        let (store, container, historyURL) = try makeStore()
        defer { _ = container; try? FileManager.default.removeItem(at: historyURL) }
        XCTAssertTrue(store.completeOnboarding(OnboardingDraft()))
        let block = try XCTUnwrap(store.todayPlan.blocks.first)
        let preview = try store.previewTodayPlanBlockReplacement(block.id, reason: .alreadyFamiliar)
        let accepted = try XCTUnwrap(store.replaceTodayPlanBlock(block.id, reason: .alreadyFamiliar, preview: preview))
        XCTAssertEqual(accepted.id, preview.replacementBlock.id)
        XCTAssertEqual(store.dailyPlans.first { $0.id == preview.originalPlan.id }?.snapshot, preview.proposedPlan)
        XCTAssertEqual(preview.proposedPlan.blocks.filter { $0.id != accepted.id },
            preview.originalPlan.blocks.filter { $0.id != block.id })
        XCTAssertEqual(store.adaptivePlanHistory.filter { $0.kind == .planReplaced }.count, 1)
        XCTAssertNil(store.replaceTodayPlanBlock(block.id, reason: .alreadyFamiliar, preview: preview))
        XCTAssertEqual(store.adaptivePlanHistory.filter { $0.kind == .planReplaced }.count, 1)
    }

    @MainActor
    func testStaleReplacementPreviewCannotOverwriteAChangedPlan() throws {
        let (store, container, historyURL) = try makeStore()
        defer { _ = container; try? FileManager.default.removeItem(at: historyURL) }
        XCTAssertTrue(store.completeOnboarding(OnboardingDraft()))
        let block = try XCTUnwrap(store.todayPlan.blocks.first)
        let preview = try store.previewTodayPlanBlockReplacement(block.id, reason: .tooEasy)
        let record = try XCTUnwrap(store.dailyPlans.first { $0.id == preview.originalPlan.id })
        // Even an externally re-encoded payload invalidates the captured bytes;
        // applying an older preview may not quietly choose a new proposal.
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        record.payload = try encoder.encode(preview.originalPlan); try container.mainContext.save()
        let changed = record.payload
        XCTAssertNotEqual(changed, preview.originalPayload)
        XCTAssertNil(store.replaceTodayPlanBlock(block.id, reason: .tooEasy, preview: preview))
        XCTAssertEqual(record.payload, changed)
        XCTAssertTrue(store.adaptivePlanHistory.filter { $0.kind == .planReplaced }.isEmpty)
        XCTAssertTrue(store.canReplaceTodayPlanBlock(block.id))
    }

    @MainActor
    func testStartedBlockInvalidatesItsEarlierReplacementPreview() throws {
        let (store, container, historyURL) = try makeStore()
        defer { _ = container; try? FileManager.default.removeItem(at: historyURL) }
        XCTAssertTrue(store.completeOnboarding(OnboardingDraft()))
        let plan = store.todayPlan, block = try XCTUnwrap(store.todayPlan.blocks.first)
        let preview = try store.previewTodayPlanBlockReplacement(block.id, reason: .accessibilityIssue)
        let request = SessionRequest(lab: block.lab, source: .today, seed: 717, planID: plan.id, planBlockID: block.id)
        try store.upsertCheckpoint(sessionID: request.id, request: request, currentIndex: 0,
            itemCount: 5, response: "retained work", scratchpad: "", results: [])
        XCTAssertFalse(store.canReplaceTodayPlanBlock(block.id))
        XCTAssertNil(store.replaceTodayPlanBlock(block.id, reason: .accessibilityIssue, preview: preview))
        XCTAssertEqual(store.dailyPlans.first { $0.id == plan.id }?.payload, preview.originalPayload)
        XCTAssertEqual(store.sessionCheckpoints.first { $0.sessionID == request.id }?.response, "retained work")
    }

    @MainActor
    func testAcceptedLocalRunPreventsReplacementBeforeItsLegacyMirrorExists() throws {
        let (store, container, historyURL) = try makeStore()
        defer { _ = container; try? FileManager.default.removeItem(at: historyURL) }
        XCTAssertTrue(store.completeOnboarding(OnboardingDraft()))
        let plan = store.todayPlan
        let block = try XCTUnwrap(plan.blocks.first { $0.kindRaw == NFDailyPlanBlockKind.targetPractice.rawValue })
        let preview = try store.previewTodayPlanBlockReplacement(block.id, reason: .wantVariety)
        XCTAssertTrue(store.beginSession(lab: block.lab, source: .today, requestedItemCount: 5,
            planID: plan.id, planBlockID: block.id))
        XCTAssertTrue(store.localSessions.archive.sessions.contains { $0.request.planID == plan.id && $0.request.planBlockID == block.id })
        XCTAssertFalse(store.sessionCheckpoints.contains { $0.planID == plan.id && $0.planBlockID == block.id })
        let cold = AppStore(context: container.mainContext, localSessionRepository: store.localSessions,
            adaptivePlanHistoryRepository: NFAdaptivePlanHistoryRepository(fileURL: historyURL))
        XCTAssertNil(cold.activeSessionRequest)
        XCTAssertFalse(cold.canReplaceTodayPlanBlock(block.id))
        XCTAssertNil(cold.replaceTodayPlanBlock(block.id, reason: .wantVariety, preview: preview))
        XCTAssertEqual(cold.dailyPlans.first { $0.id == plan.id }?.payload, preview.originalPayload)
    }

    @MainActor
    func testPreviewUsesOneCapturedLearnerDayWithoutCreatingAFuturePlan() throws {
        let (store, container, historyURL) = try makeStore()
        defer { _ = container; try? FileManager.default.removeItem(at: historyURL) }
        XCTAssertTrue(store.completeOnboarding(OnboardingDraft()))
        let block = try XCTUnwrap(store.todayPlan.blocks.first), savedIDs = store.dailyPlans.map(\.id)
        let future = Date().addingTimeInterval(3 * 86_400)
        XCTAssertFalse(store.canReplaceTodayPlanBlock(block.id, at: future))
        XCTAssertThrowsError(try store.previewTodayPlanBlockReplacement(block.id, reason: .tooEasy, at: future))
        XCTAssertEqual(store.dailyPlans.map(\.id), savedIDs)
        XCTAssertTrue(store.adaptivePlanHistory.filter { $0.kind == .planReplaced }.isEmpty)
    }

    func testReplacementReasonChoicesAreCompleteWithoutReinterpretingHistoricalRawValues() throws {
        XCTAssertEqual(NFPlanReplacementReason.currentChoices, [.tooEasy, .tooHard, .alreadyFamiliar, .wantVariety, .accessibilityIssue])
        XCTAssertEqual(try JSONDecoder().decode(NFPlanReplacementReason.self, from: Data("\"lowerEnergy\"".utf8)), .lowerEnergy)
        XCTAssertEqual(try JSONDecoder().decode(NFPlanReplacementReason.self, from: Data("\"notRelevantToday\"".utf8)), .notRelevantToday)
    }

    private func temporaryHistoryURL() -> URL {
        FileManager.default.temporaryDirectory
            .appending(path: "NF-Adaptive-History-\(UUID().uuidString).json")
    }

    @MainActor
    private func makeStore() throws -> (AppStore, ModelContainer, URL) {
        let schema = Schema(NFSchemaV1.models)
        let container = try ModelContainer(
            for: schema,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let historyURL = temporaryHistoryURL()
        let store = AppStore(
            context: container.mainContext,
            adaptivePlanHistoryRepository: NFAdaptivePlanHistoryRepository(fileURL: historyURL)
        )
        return (store, container, historyURL)
    }
}

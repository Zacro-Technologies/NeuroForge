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

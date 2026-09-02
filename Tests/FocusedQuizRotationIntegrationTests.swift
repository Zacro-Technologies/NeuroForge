import Foundation
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
            seedOverride: 42
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
            seedOverride: 42
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
                seedOverride: 7
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
            seedOverride: 7
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
                seedOverride: 99
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
            mechanicID: activity.mechanicID
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
            mechanicID: activity.mechanicID
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
    func testEverySelectedCatalogActivityAvoidsInRunRepeatsAndChangesSequenceAfterAbandonment() throws {
        let rotationStore = FocusedQuizInMemoryRotationStore()
        let (store, container) = try makeStore(rotationStore: rotationStore)
        defer { _ = container }

        for activity in NFDefaultContentCatalog.activities {
            XCTAssertTrue(store.beginSession(
                lab: activity.lab,
                source: .focused,
                requestedItemCount: 10,
                seedOverride: 987_654,
                mechanicID: activity.mechanicID
            ), activity.id)
            let first = try XCTUnwrap(store.activeSessionRequest, activity.id)
            let firstSequence = fingerprints(for: first, itemCount: 10)
            XCTAssertEqual(Set(firstSequence).count, 10, activity.id)

            store.activeSessionRequest = nil
            XCTAssertTrue(store.beginSession(
                lab: activity.lab,
                source: .focused,
                requestedItemCount: 10,
                seedOverride: 987_654,
                mechanicID: activity.mechanicID
            ), activity.id)
            let second = try XCTUnwrap(store.activeSessionRequest, activity.id)
            let secondSequence = fingerprints(for: second, itemCount: 10)
            XCTAssertEqual(Set(secondSequence).count, 10, activity.id)

            XCTAssertNotEqual(
                firstSequence,
                secondSequence,
                activity.id
            )
            store.activeSessionRequest = nil
        }
    }

    private func fingerprints(
        for request: SessionRequest,
        itemCount: Int
    ) -> [String] {
        var seen: Set<String> = []
        return (0..<itemCount).map { index in
            let exercise = NFDeterministicSessionExerciseFactory.makeExercise(
                request: request,
                index: index,
                assessmentDescriptor: nil,
                excludingContentFingerprints: seen
            )
            let fingerprint = NFQuestionFingerprint.fingerprint(for: exercise)
            seen.insert(fingerprint)
            return fingerprint
        }
    }

    @MainActor
    private func makeStore(
        rotationStore: FocusedQuizInMemoryRotationStore
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

    func load() -> NFOfflineQuestionRotationLedger? {
        lock.withLock { ledger }
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

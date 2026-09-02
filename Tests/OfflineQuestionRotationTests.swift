import Foundation
import XCTest

@testable import NeuroForge

final class OfflineQuestionRotationTests: XCTestCase {
    func testBankRequiresOneThousandUniqueStableIDsForEveryLab() throws {
        XCTAssertEqual(NFVersionedOfflineQuestionBank.minimumQuestionsPerLab, 1_000)
        var IDs = makeQuestionIDs()
        IDs[.spatial] = Array((IDs[.spatial] ?? []).prefix(999))

        XCTAssertThrowsError(try NFVersionedOfflineQuestionBank(
            version: 1,
            questionIDsByLab: IDs
        )) { error in
            XCTAssertEqual(
                error as? NFOfflineQuestionRotationError,
                .insufficientQuestions(lab: .spatial, actual: 999, required: 1_000)
            )
        }

        IDs = makeQuestionIDs()
        var retrievalIDs = try XCTUnwrap(IDs[.retrieval])
        retrievalIDs[999] = retrievalIDs[0]
        IDs[.retrieval] = retrievalIDs
        XCTAssertThrowsError(try NFVersionedOfflineQuestionBank(
            version: 1,
            questionIDsByLab: IDs
        )) { error in
            XCTAssertEqual(
                error as? NFOfflineQuestionRotationError,
                .duplicateQuestionID(lab: .retrieval)
            )
        }

        XCTAssertThrowsError(try NFVersionedOfflineQuestionBank(
            version: 0,
            questionIDsByLab: makeQuestionIDs()
        )) { error in
            XCTAssertEqual(
                error as? NFOfflineQuestionRotationError,
                .invalidBankVersion(0)
            )
        }
    }

    func testReservationsExhaustAnEpochWithoutReplacementAndAdvanceAtLaunch() throws {
        let bank = try makeBank()
        let profileID = UUID(uuidString: "00000000-0000-0000-0000-000000000101")!
        let rotation = NFOfflineQuestionRotation(
            store: InMemoryOfflineQuestionRotationStore(),
            boundaryTailLength: 12
        )

        var questionIDs: [String] = []
        var stableOrdinals: [UInt64] = []
        for expectedReservation in 0..<100 {
            let plan = try rotation.reserve(
                profileID: profileID,
                lab: .mentalMath,
                itemCount: 10,
                bank: bank
            )
            XCTAssertEqual(plan.reservationOrdinal, UInt64(expectedReservation))
            XCTAssertEqual(plan.items.map(\.quizOrdinal), Array(0..<10))
            questionIDs.append(contentsOf: plan.items.map(\.questionID))
            stableOrdinals.append(contentsOf: plan.items.map(\.stableOrdinal))
        }

        XCTAssertEqual(Set(questionIDs).count, 1_000)
        XCTAssertEqual(stableOrdinals, (0..<1_000).map(UInt64.init))

        // A new quiz is reserved immediately. It rotates even though the caller
        // never reports whether any question in the previous quiz was answered.
        let next = try rotation.reserve(
            profileID: profileID,
            lab: .mentalMath,
            itemCount: 10,
            bank: bank
        )
        XCTAssertEqual(next.reservationOrdinal, 100)
        XCTAssertEqual(next.items.map(\.stableOrdinal), (1_000..<1_010).map(UInt64.init))
        XCTAssertTrue(
            Set(next.items.map(\.questionID)).isDisjoint(with: Set(questionIDs.suffix(12)))
        )
    }

    func testOneReservationCrossesEpochWithoutRepeatingContent() throws {
        let bank = try makeBank()
        let profileID = UUID(uuidString: "00000000-0000-0000-0000-000000000202")!
        let rotation = NFOfflineQuestionRotation(
            store: InMemoryOfflineQuestionRotationStore(),
            boundaryTailLength: 8
        )

        let first = try rotation.reserve(
            profileID: profileID,
            lab: .quantitative,
            itemCount: 995,
            bank: bank
        )
        let crossing = try rotation.reserve(
            profileID: profileID,
            lab: .quantitative,
            itemCount: 10,
            bank: bank
        )

        XCTAssertEqual(Set(first.items.map(\.questionID)).count, 995)
        XCTAssertEqual(Set(crossing.items.map(\.questionID)).count, 10)
        XCTAssertEqual(crossing.items.map(\.stableOrdinal), (995..<1_005).map(UInt64.init))
        XCTAssertEqual(crossing.items.prefix(5).map(\.epoch), Array(repeating: 0, count: 5))
        XCTAssertEqual(crossing.items.suffix(5).map(\.epoch), Array(repeating: 1, count: 5))
        XCTAssertTrue(
            Set(crossing.items.suffix(5).map(\.questionID)).isDisjoint(
                with: Set(crossing.items.prefix(5).map(\.questionID))
            )
        )
    }

    func testFreshStoresProduceTheSamePlanAndPersistedStoreContinuesIt() throws {
        let bank = try makeBank()
        let profileID = UUID(uuidString: "00000000-0000-0000-0000-000000000303")!
        let firstStore = InMemoryOfflineQuestionRotationStore()
        let duplicateStore = InMemoryOfflineQuestionRotationStore()

        let first = try NFOfflineQuestionRotation(store: firstStore).reserve(
            profileID: profileID,
            lab: .logicDebugging,
            itemCount: 17,
            bank: bank
        )
        let duplicate = try NFOfflineQuestionRotation(store: duplicateStore).reserve(
            profileID: profileID,
            lab: .logicDebugging,
            itemCount: 17,
            bank: bank
        )
        XCTAssertEqual(first, duplicate)

        let continued = try NFOfflineQuestionRotation(store: firstStore).reserve(
            profileID: profileID,
            lab: .logicDebugging,
            itemCount: 17,
            bank: bank
        )
        XCTAssertEqual(continued.reservationOrdinal, 1)
        XCTAssertEqual(continued.items.first?.stableOrdinal, 17)
        XCTAssertTrue(
            Set(first.items.map(\.questionID)).isDisjoint(
                with: Set(continued.items.map(\.questionID))
            )
        )
    }

    func testStableLanesRotateIndependentlyAndRejectEmptyIDs() throws {
        let bank = try makeBank()
        let profileID = UUID(uuidString: "00000000-0000-0000-0000-000000000808")!
        let rotation = NFOfflineQuestionRotation(store: InMemoryOfflineQuestionRotationStore())

        let mixed = try rotation.reserve(
            profileID: profileID,
            lab: .retrieval,
            itemCount: 10,
            bank: bank
        )
        let activity = try rotation.reserve(
            profileID: profileID,
            lab: .retrieval,
            laneID: "catalog.retrieval-flash",
            itemCount: 7,
            bank: bank
        )
        let continuedMixed = try rotation.reserve(
            profileID: profileID,
            lab: .retrieval,
            itemCount: 10,
            bank: bank
        )
        let continuedActivity = try rotation.reserve(
            profileID: profileID,
            lab: .retrieval,
            laneID: "catalog.retrieval-flash",
            itemCount: 7,
            bank: bank
        )

        XCTAssertEqual(mixed.laneID, "mixed")
        XCTAssertEqual(activity.laneID, "catalog.retrieval-flash")
        XCTAssertNotEqual(mixed.id, activity.id)
        XCTAssertEqual(mixed.reservationOrdinal, 0)
        XCTAssertEqual(activity.reservationOrdinal, 0)
        XCTAssertEqual(continuedMixed.reservationOrdinal, 1)
        XCTAssertEqual(continuedActivity.reservationOrdinal, 1)
        XCTAssertEqual(continuedMixed.items.first?.stableOrdinal, 10)
        XCTAssertEqual(continuedActivity.items.first?.stableOrdinal, 7)

        XCTAssertThrowsError(try rotation.reserve(
            profileID: profileID,
            lab: .retrieval,
            laneID: " \n ",
            itemCount: 1,
            bank: bank
        )) { error in
            XCTAssertEqual(error as? NFOfflineQuestionRotationError, .emptyLaneID)
        }
    }

    func testCompareAndSwapPreventsConcurrentLaunchesFromClaimingTheSameSlice() async throws {
        let bank = try makeBank()
        let profileID = UUID(uuidString: "00000000-0000-0000-0000-000000000404")!
        let sharedStore = InMemoryOfflineQuestionRotationStore()
        let firstRotation = NFOfflineQuestionRotation(store: sharedStore)
        let secondRotation = NFOfflineQuestionRotation(store: sharedStore)

        let plans = try await withThrowingTaskGroup(
            of: NFOfflineQuestionRotationPlan.self,
            returning: [NFOfflineQuestionRotationPlan].self
        ) { group in
            for index in 0..<20 {
                let rotation = index.isMultiple(of: 2) ? firstRotation : secondRotation
                group.addTask {
                    try rotation.reserve(
                        profileID: profileID,
                        lab: .scientificReasoning,
                        itemCount: 10,
                        bank: bank
                    )
                }
            }
            var result: [NFOfflineQuestionRotationPlan] = []
            for try await plan in group { result.append(plan) }
            return result
        }

        XCTAssertEqual(Set(plans.map(\.reservationOrdinal)), Set((0..<20).map(UInt64.init)))
        XCTAssertEqual(Set(plans.flatMap { $0.items.map(\.stableOrdinal) }).count, 200)
        XCTAssertEqual(Set(plans.flatMap { $0.items.map(\.questionID) }).count, 200)
    }

    func testUserDefaultsStoreSurvivesRotationRecreationAndDetectsCorruption() throws {
        let suiteName = "OfflineQuestionRotationTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let key = "rotation-ledger"
        let profileID = UUID(uuidString: "00000000-0000-0000-0000-000000000505")!
        let bank = try makeBank()
        let firstStore = NFUserDefaultsOfflineQuestionRotationStateStore(defaults: defaults, key: key)
        let first = try NFOfflineQuestionRotation(store: firstStore).reserve(
            profileID: profileID,
            lab: .spatial,
            itemCount: 9,
            bank: bank
        )

        let recreatedStore = NFUserDefaultsOfflineQuestionRotationStateStore(defaults: defaults, key: key)
        let second = try NFOfflineQuestionRotation(store: recreatedStore).reserve(
            profileID: profileID,
            lab: .spatial,
            itemCount: 9,
            bank: bank
        )
        XCTAssertEqual(first.reservationOrdinal, 0)
        XCTAssertEqual(second.reservationOrdinal, 1)
        XCTAssertEqual(second.items.first?.stableOrdinal, 9)
        XCTAssertTrue(
            Set(first.items.map(\.questionID)).isDisjoint(
                with: Set(second.items.map(\.questionID))
            )
        )

        defaults.set(Data("not-json".utf8), forKey: key)
        XCTAssertThrowsError(try recreatedStore.load()) { error in
            XCTAssertEqual(
                error as? NFOfflineQuestionRotationError,
                .corruptPersistedState
            )
        }
    }

    func testUserDefaultsRemoveAllClearsLedgerAndRestartsRotation() throws {
        let suiteName = "OfflineQuestionRotationTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let key = "rotation-ledger-to-delete"
        let profileID = UUID(uuidString: "00000000-0000-0000-0000-000000000707")!
        let bank = try makeBank()
        let store = NFUserDefaultsOfflineQuestionRotationStateStore(defaults: defaults, key: key)
        let first = try NFOfflineQuestionRotation(store: store).reserve(
            profileID: profileID,
            lab: .transfer,
            itemCount: 11,
            bank: bank
        )
        XCTAssertNotNil(defaults.object(forKey: key))

        try NFUserDefaultsOfflineQuestionRotationStateStore.removeAll(
            defaults: defaults,
            key: key
        )

        XCTAssertNil(defaults.object(forKey: key))
        XCTAssertNil(try store.load())
        let restarted = try NFOfflineQuestionRotation(store: store).reserve(
            profileID: profileID,
            lab: .transfer,
            itemCount: 11,
            bank: bank
        )
        XCTAssertEqual(restarted, first)
    }

    func testChangingIDsWithoutBumpingVersionIsRejectedAndNewVersionStartsFresh() throws {
        let profileID = UUID(uuidString: "00000000-0000-0000-0000-000000000606")!
        let store = InMemoryOfflineQuestionRotationStore()
        let rotation = NFOfflineQuestionRotation(store: store)
        let firstBank = try makeBank(version: 7)
        _ = try rotation.reserve(
            profileID: profileID,
            lab: .transfer,
            itemCount: 5,
            bank: firstBank
        )

        var changedIDs = makeQuestionIDs()
        changedIDs[.transfer]?[0] = "transfer.replacement"
        let changedWithoutVersion = try NFVersionedOfflineQuestionBank(
            version: 7,
            questionIDsByLab: changedIDs
        )
        do {
            _ = try rotation.reserve(
                profileID: profileID,
                lab: .transfer,
                itemCount: 5,
                bank: changedWithoutVersion
            )
            XCTFail("A bank identity change must require a version bump")
        } catch {
            XCTAssertEqual(
                error as? NFOfflineQuestionRotationError,
                .bankChangedWithoutVersion(lab: .transfer, version: 7)
            )
        }

        let bumped = try NFVersionedOfflineQuestionBank(
            version: 8,
            questionIDsByLab: changedIDs
        )
        let fresh = try rotation.reserve(
            profileID: profileID,
            lab: .transfer,
            itemCount: 5,
            bank: bumped
        )
        XCTAssertEqual(fresh.reservationOrdinal, 0)
        XCTAssertEqual(fresh.items.map(\.stableOrdinal), (0..<5).map(UInt64.init))
    }

    private func makeBank(version: Int = 1) throws -> NFVersionedOfflineQuestionBank {
        try NFVersionedOfflineQuestionBank(
            version: version,
            questionIDsByLab: makeQuestionIDs()
        )
    }

    private func makeQuestionIDs(count: Int = 1_000) -> [TrainingLab: [String]] {
        Dictionary(uniqueKeysWithValues: TrainingLab.allCases.map { lab in
            (
                lab,
                (0..<count).map { index in
                    "offline.\(lab.rawValue).\(String(format: "%03d", index))"
                }
            )
        })
    }
}

private final class InMemoryOfflineQuestionRotationStore:
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

import Foundation

/// The audited deterministic offline floor. A bank version is valid only when every lab can
/// supply this many distinct, stable question identifiers.
struct NFVersionedOfflineQuestionBank: Equatable, Sendable {
    static let minimumQuestionsPerLab = 1_000

    let version: Int
    private let questionIDsByLab: [TrainingLab: [String]]
    fileprivate let fingerprint: String
    var catalogFingerprint: String { fingerprint }

    init(version: Int, questionIDsByLab: [TrainingLab: [String]]) throws {
        guard version > 0 else {
            throw NFOfflineQuestionRotationError.invalidBankVersion(version)
        }

        var normalized: [TrainingLab: [String]] = [:]
        for lab in TrainingLab.allCases {
            let questionIDs = questionIDsByLab[lab] ?? []
            guard questionIDs.count >= Self.minimumQuestionsPerLab else {
                throw NFOfflineQuestionRotationError.insufficientQuestions(
                    lab: lab,
                    actual: questionIDs.count,
                    required: Self.minimumQuestionsPerLab
                )
            }
            guard questionIDs.allSatisfy({
                !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }) else {
                throw NFOfflineQuestionRotationError.emptyQuestionID(lab: lab)
            }
            guard Set(questionIDs).count == questionIDs.count else {
                throw NFOfflineQuestionRotationError.duplicateQuestionID(lab: lab)
            }
            // Authored source order is not an identity boundary. Sorting makes
            // the same version and IDs produce the same rotation after a build,
            // import, or harmless source-file reorder.
            normalized[lab] = questionIDs.sorted()
        }

        self.version = version
        self.questionIDsByLab = normalized
        fingerprint = Self.makeFingerprint(version: version, questionIDsByLab: normalized)
    }

    func questionIDs(for lab: TrainingLab) -> [String] {
        questionIDsByLab[lab] ?? []
    }

    private static func makeFingerprint(
        version: Int,
        questionIDsByLab: [TrainingLab: [String]]
    ) -> String {
        let payload = TrainingLab.allCases.map { lab in
            "\(lab.rawValue)=\((questionIDsByLab[lab] ?? []).joined(separator: ","))"
        }.joined(separator: "|")
        return String(NFOfflineQuestionRotation.stableHash("bank|\(version)|\(payload)"), radix: 16)
    }
}

struct NFOfflineQuestionRotationPlanItem: Codable, Equatable, Sendable {
    /// Stable content identity in the versioned offline bank.
    let questionID: String
    /// Zero-based position inside this quiz.
    let quizOrdinal: Int
    /// Epoch containing this occurrence of the question.
    let epoch: UInt64
    /// Zero-based position in the epoch's deterministic permutation.
    let epochOrdinal: Int
    /// Stable position in this profile/lab/lane/bank-version rotation. Delivery
    /// may return to an earlier unconsumed hole after eligibility changes.
    let stableOrdinal: UInt64
}

struct NFOfflineQuestionRotationPlan: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let profileID: UUID
    let lab: TrainingLab
    /// Stable caller-defined lane, such as an activity ID. Separate lanes
    /// rotate independently without consuming the default mixed-quiz cursor.
    let laneID: String
    let bankVersion: Int
    /// Monotonic launch number for this profile/lab/lane/bank-version scope.
    let reservationOrdinal: UInt64
    let items: [NFOfflineQuestionRotationPlanItem]
}

enum NFOfflineQuestionRotationError: Error, Equatable, Sendable {
    case invalidBankVersion(Int)
    case insufficientQuestions(lab: TrainingLab, actual: Int, required: Int)
    case emptyQuestionID(lab: TrainingLab)
    case duplicateQuestionID(lab: TrainingLab)
    case emptyLaneID
    case invalidReservationCount(actual: Int, maximum: Int)
    case bankChangedWithoutVersion(lab: TrainingLab, version: Int)
    case corruptPersistedState
    case persistenceVerificationFailed
    case concurrentReservationLimitExceeded
    case ordinalOverflow
    case rotationInvariantViolation
    case insufficientEligibleQuestions(actual: Int, required: Int)
}

/// Persistence is deliberately tiny and compare-and-swap based. The latter is
/// what makes reserving at quiz launch safe when two windows ask for a quiz at
/// nearly the same time: only one can claim a given cursor and launch ordinal.
protocol NFOfflineQuestionRotationStateStoring: Sendable {
    func load() throws -> NFOfflineQuestionRotationLedger?

    func compareAndSwap(
        expectedRevision: UInt64?,
        replacement: NFOfflineQuestionRotationLedger
    ) throws -> Bool

    func withSnapshot<Result>(_ operation: (NFOfflineQuestionRotationLedger?) throws -> Result) throws -> Result
}

extension NFOfflineQuestionRotationStateStoring {
    func withSnapshot<Result>(_ operation: (NFOfflineQuestionRotationLedger?) throws -> Result) throws -> Result {
        try operation(load())
    }
}

struct NFOfflineQuestionRotationProposal: Sendable {
    let expectedRevision: UInt64?
    let replacement: NFOfflineQuestionRotationLedger
    let plan: NFOfflineQuestionRotationPlan
}

struct NFOfflineQuestionRotationLedger: Codable, Equatable, Sendable {
    static let schemaVersion = 1

    var schemaVersion: Int = Self.schemaVersion
    var revision: UInt64
    var scopes: [String: NFOfflineQuestionRotationScopeState]
}

struct NFOfflineQuestionRotationScopeState: Codable, Equatable, Sendable {
    let bankFingerprint: String
    let bankQuestionCount: Int
    var epoch: UInt64
    var cursor: Int
    var nextReservationOrdinal: UInt64
    /// Tail of the prior epoch. The current permutation places these IDs after
    /// all other IDs, preventing an immediate boundary repeat.
    var boundaryExclusions: [String]
    /// Positions consumed beyond the first unconsumed cursor. Nil means the
    /// legacy contiguous prefix. Ineligible positions are never inserted here.
    var consumedEpochOrdinals: Set<Int>? = nil

    var hasValidConsumption: Bool {
        bankQuestionCount > 0 && cursor >= 0 && cursor < bankQuestionCount
            && (consumedEpochOrdinals ?? []).allSatisfy { $0 > cursor && $0 < bankQuestionCount }
    }

    func containsConsumed(epoch candidateEpoch: UInt64, ordinal: Int) -> Bool {
        ordinal >= 0 && ordinal < bankQuestionCount
            && (candidateEpoch < epoch || (candidateEpoch == epoch
                && (ordinal < cursor || consumedEpochOrdinals?.contains(ordinal) == true)))
    }
}

/// Disposable fixture authority. It never reads or writes UserDefaults.
final class NFMemoryOfflineQuestionRotationStateStore: NFOfflineQuestionRotationStateStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var ledger: NFOfflineQuestionRotationLedger?
    func load() -> NFOfflineQuestionRotationLedger? { lock.withLock { ledger } }
    func compareAndSwap(expectedRevision: UInt64?, replacement: NFOfflineQuestionRotationLedger) -> Bool {
        lock.withLock {
            guard ledger?.revision == expectedRevision else { return false }
            ledger = replacement
            return true
        }
    }
    func withSnapshot<Result>(_ operation: (NFOfflineQuestionRotationLedger?) throws -> Result) throws -> Result {
        try lock.withLock { try operation(ledger) }
    }
}

/// UserDefaults-backed ledger for the app singleton. Writes are verified and
/// compare-and-swap is guarded across instances in this process.
final class NFUserDefaultsOfflineQuestionRotationStateStore:
    NFOfflineQuestionRotationStateStoring,
    @unchecked Sendable
{
    static let defaultKey = "nf.offline-question-rotation.ledger.v1"

    private static let processLock = NSLock()

    private let defaults: UserDefaults
    private let key: String
    private let encoder: JSONEncoder
    private let decoder = JSONDecoder()

    init(
        defaults: UserDefaults = .standard,
        key: String = NFUserDefaultsOfflineQuestionRotationStateStore.defaultKey
    ) {
        self.defaults = defaults
        self.key = key
        encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
    }

    /// Removes the complete launch-reservation ledger. This is intentionally a
    /// type helper so privacy/data-deletion flows do not need to retain the
    /// store instance used by the session launcher.
    static func removeAll(
        defaults: UserDefaults = .standard,
        key: String = NFUserDefaultsOfflineQuestionRotationStateStore.defaultKey
    ) throws {
        try processLock.withLock {
            defaults.removeObject(forKey: key)
            guard defaults.object(forKey: key) == nil else {
                throw NFOfflineQuestionRotationError.persistenceVerificationFailed
            }
        }
    }

    func load() throws -> NFOfflineQuestionRotationLedger? {
        try Self.processLock.withLock {
            try decodePersistedLedger()
        }
    }

    func withSnapshot<Result>(_ operation: (NFOfflineQuestionRotationLedger?) throws -> Result) throws -> Result {
        try Self.processLock.withLock { try operation(decodePersistedLedger()) }
    }

    func compareAndSwap(
        expectedRevision: UInt64?,
        replacement: NFOfflineQuestionRotationLedger
    ) throws -> Bool {
        try Self.processLock.withLock {
            let current = try decodePersistedLedger()
            guard current?.revision == expectedRevision,
                  replacement.schemaVersion == NFOfflineQuestionRotationLedger.schemaVersion else {
                return false
            }

            let encoded = try encoder.encode(replacement)
            defaults.set(encoded, forKey: key)
            guard let persisted = try decodePersistedLedger(), persisted == replacement else {
                throw NFOfflineQuestionRotationError.persistenceVerificationFailed
            }
            return true
        }
    }

    private func decodePersistedLedger() throws -> NFOfflineQuestionRotationLedger? {
        guard let data = defaults.data(forKey: key) else { return nil }
        guard let ledger = try? decoder.decode(NFOfflineQuestionRotationLedger.self, from: data),
              ledger.schemaVersion == NFOfflineQuestionRotationLedger.schemaVersion else {
            throw NFOfflineQuestionRotationError.corruptPersistedState
        }
        return ledger
    }
}

/// Reserves deterministic, non-repeating question slices. Reservation happens
/// before the caller presents a quiz, so abandoning a quiz does not cause the
/// next launch to replay the same questions.
struct NFOfflineQuestionRotation: Sendable {
    static let algorithmVersion = 1
    static let defaultBoundaryTailLength = 32

    private let store: any NFOfflineQuestionRotationStateStoring
    private let boundaryTailLength: Int
    private let maximumCompareAndSwapAttempts: Int

    init(
        store: any NFOfflineQuestionRotationStateStoring,
        boundaryTailLength: Int = NFOfflineQuestionRotation.defaultBoundaryTailLength,
        maximumCompareAndSwapAttempts: Int = 32
    ) {
        self.store = store
        self.boundaryTailLength = max(1, boundaryTailLength)
        self.maximumCompareAndSwapAttempts = max(1, maximumCompareAndSwapAttempts)
    }

    /// Read-only compatibility source. New app launches persist the proposal
    /// with their run in NFLocalSessionRepository, never through this store.
    func legacySnapshot() throws -> NFOfflineQuestionRotationLedger? { try store.load() }
    func withLegacySnapshot<Result>(_ operation: (NFOfflineQuestionRotationLedger?) throws -> Result) throws -> Result {
        try store.withSnapshot(operation)
    }

    func prepareReservation(profileID: UUID, lab: TrainingLab, laneID: String = "mixed",
                            itemCount: Int, bank: NFVersionedOfflineQuestionBank,
                            loadedLedger: NFOfflineQuestionRotationLedger?,
                            isEligible: ((NFOfflineQuestionRotationPlanItem) -> Bool)? = nil) throws -> NFOfflineQuestionRotationProposal {
        guard !laneID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw NFOfflineQuestionRotationError.emptyLaneID
        }
        let bankIDs = bank.questionIDs(for: lab)
        guard (1...bankIDs.count).contains(itemCount) else {
            throw NFOfflineQuestionRotationError.invalidReservationCount(
                actual: itemCount,
                maximum: bankIDs.count
            )
        }

        let expectedRevision = loadedLedger?.revision
        var ledger = loadedLedger ?? NFOfflineQuestionRotationLedger(
            revision: 0,
            scopes: [:]
        )
        guard ledger.schemaVersion == NFOfflineQuestionRotationLedger.schemaVersion else {
            throw NFOfflineQuestionRotationError.corruptPersistedState
        }

        let scopeKey = Self.scopeKey(
            profileID: profileID,
            lab: lab,
            laneID: laneID,
            bankVersion: bank.version
        )
        var state = try resolvedState(
            ledger.scopes[scopeKey],
            bank: bank,
            lab: lab,
            bankQuestionCount: bankIDs.count
        )
        let reservationOrdinal = state.nextReservationOrdinal
        state.nextReservationOrdinal = try Self.incrementing(state.nextReservationOrdinal)

        var planItems: [NFOfflineQuestionRotationPlanItem] = []
        planItems.reserveCapacity(itemCount)

        while planItems.count < itemCount {
            let order = Self.epochOrder(
                bankIDs: bankIDs,
                profileID: profileID,
                lab: lab,
                laneID: laneID,
                bankVersion: bank.version,
                bankFingerprint: bank.fingerprint,
                epoch: state.epoch,
                boundaryExclusions: state.boundaryExclusions
            )
            guard order.count == bankIDs.count,
                  state.cursor >= 0,
                  state.cursor < order.count else {
                throw NFOfflineQuestionRotationError.rotationInvariantViolation
            }

            var consumed = state.consumedEpochOrdinals ?? []
            for epochOrdinal in state.cursor..<order.count {
                guard !consumed.contains(epochOrdinal) else { continue }
                let stableOrdinal = try Self.stableOrdinal(
                    epoch: state.epoch,
                    epochOrdinal: epochOrdinal,
                    bankQuestionCount: bankIDs.count
                )
                let candidate = NFOfflineQuestionRotationPlanItem(
                    questionID: order[epochOrdinal],
                    quizOrdinal: planItems.count,
                    epoch: state.epoch,
                    epochOrdinal: epochOrdinal,
                    stableOrdinal: stableOrdinal
                )
                guard !planItems.contains(where: { $0.questionID == candidate.questionID }),
                      isEligible?(candidate) ?? true else { continue }
                planItems.append(candidate)
                consumed.insert(epochOrdinal)
                if planItems.count == itemCount { break }
            }
            while consumed.remove(state.cursor) != nil { state.cursor += 1 }
            state.consumedEpochOrdinals = consumed.isEmpty ? nil : consumed

            if state.cursor == order.count {
                let quizTailCount = planItems.count < itemCount ? planItems.count : 0
                state = try advancingEpoch(
                    state,
                    completedOrder: order,
                    minimumExcludedTailCount: quizTailCount
                )
            } else if planItems.count < itemCount {
                // One finite pass has exhausted this epoch's feasible pool.
                // Holes prevent a new epoch; no proposal is published on failure.
                throw NFOfflineQuestionRotationError.insufficientEligibleQuestions(actual: planItems.count, required: itemCount)
            }
        }

        guard Set(planItems.map(\.questionID)).count == planItems.count else {
            throw NFOfflineQuestionRotationError.rotationInvariantViolation
        }

        ledger.scopes[scopeKey] = state
        ledger.revision = try Self.incrementing(ledger.revision)
        let plan = NFOfflineQuestionRotationPlan(
            id: Self.planID(
                profileID: profileID,
                lab: lab,
                laneID: laneID,
                bankVersion: bank.version,
                reservationOrdinal: reservationOrdinal
            ),
            profileID: profileID,
            lab: lab,
            laneID: laneID,
            bankVersion: bank.version,
            reservationOrdinal: reservationOrdinal,
            items: planItems
        )

        return .init(expectedRevision: expectedRevision, replacement: ledger, plan: plan)
    }

    /// Legacy/test adapter. Production AppStore launches use prepareReservation
    /// and the local repository's atomic acceptance boundary instead.
    func reserve(profileID: UUID, lab: TrainingLab, laneID: String = "mixed", itemCount: Int,
                 bank: NFVersionedOfflineQuestionBank) throws -> NFOfflineQuestionRotationPlan {
        for _ in 0..<maximumCompareAndSwapAttempts {
            let proposal = try prepareReservation(profileID: profileID, lab: lab, laneID: laneID,
                itemCount: itemCount, bank: bank, loadedLedger: store.load())
            if try store.compareAndSwap(expectedRevision: proposal.expectedRevision, replacement: proposal.replacement) {
                return proposal.plan
            }
        }
        throw NFOfflineQuestionRotationError.concurrentReservationLimitExceeded
    }

    private func resolvedState(
        _ persisted: NFOfflineQuestionRotationScopeState?,
        bank: NFVersionedOfflineQuestionBank,
        lab: TrainingLab,
        bankQuestionCount: Int
    ) throws -> NFOfflineQuestionRotationScopeState {
        guard let persisted else {
            return NFOfflineQuestionRotationScopeState(
                bankFingerprint: bank.fingerprint,
                bankQuestionCount: bankQuestionCount,
                epoch: 0,
                cursor: 0,
                nextReservationOrdinal: 0,
                boundaryExclusions: []
            )
        }
        guard persisted.bankFingerprint == bank.fingerprint,
              persisted.bankQuestionCount == bankQuestionCount else {
            throw NFOfflineQuestionRotationError.bankChangedWithoutVersion(
                lab: lab,
                version: bank.version
            )
        }
        guard persisted.hasValidConsumption,
              Set(persisted.boundaryExclusions).count == persisted.boundaryExclusions.count,
              Set(persisted.boundaryExclusions).isSubset(of: Set(bank.questionIDs(for: lab))) else {
            throw NFOfflineQuestionRotationError.corruptPersistedState
        }
        return persisted
    }

    private func advancingEpoch(
        _ state: NFOfflineQuestionRotationScopeState,
        completedOrder: [String],
        minimumExcludedTailCount: Int
    ) throws -> NFOfflineQuestionRotationScopeState {
        var next = state
        next.epoch = try Self.incrementing(state.epoch)
        next.cursor = 0
        next.consumedEpochOrdinals = nil
        let exclusionCount = min(
            completedOrder.count - 1,
            max(boundaryTailLength, minimumExcludedTailCount)
        )
        next.boundaryExclusions = Array(completedOrder.suffix(exclusionCount))
        return next
    }

    private static func epochOrder(
        bankIDs: [String],
        profileID: UUID,
        lab: TrainingLab,
        laneID: String,
        bankVersion: Int,
        bankFingerprint: String,
        epoch: UInt64,
        boundaryExclusions: [String]
    ) -> [String] {
        let seed = stableHash([
            "offline-question-rotation",
            "algorithm-\(algorithmVersion)",
            profileID.uuidString.lowercased(),
            lab.rawValue,
            "lane-\(identityComponent(laneID))",
            "bank-\(bankVersion)",
            bankFingerprint,
            "epoch-\(epoch)"
        ].joined(separator: "|"))
        var random = NFOfflineQuestionRotationRandom(seed: seed)
        var order = bankIDs
        random.shuffle(&order)

        guard !boundaryExclusions.isEmpty else { return order }
        let excluded = Set(boundaryExclusions)
        // Keep randomness within both partitions while delaying the prior tail
        // until every non-tail item has appeared in the new epoch.
        return order.filter { !excluded.contains($0) }
            + order.filter { excluded.contains($0) }
    }

    private static func stableOrdinal(
        epoch: UInt64,
        epochOrdinal: Int,
        bankQuestionCount: Int
    ) throws -> UInt64 {
        let (epochBase, multiplicationOverflow) = epoch.multipliedReportingOverflow(
            by: UInt64(bankQuestionCount)
        )
        let (ordinal, additionOverflow) = epochBase.addingReportingOverflow(UInt64(epochOrdinal))
        guard !multiplicationOverflow, !additionOverflow else {
            throw NFOfflineQuestionRotationError.ordinalOverflow
        }
        return ordinal
    }

    private static func incrementing(_ value: UInt64) throws -> UInt64 {
        let (next, overflow) = value.addingReportingOverflow(1)
        guard !overflow else { throw NFOfflineQuestionRotationError.ordinalOverflow }
        return next
    }

    fileprivate static func stableHash(_ value: String) -> UInt64 {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in value.utf8 {
            hash ^= UInt64(byte)
            hash &*= 0x0000_0100_0000_01B3
        }
        return hash
    }

    static func scopeKey(
        profileID: UUID,
        lab: TrainingLab,
        laneID: String,
        bankVersion: Int
    ) -> String {
        "\(profileID.uuidString.lowercased())|\(lab.rawValue)|lane:\(identityComponent(laneID))|v\(bankVersion)"
    }

    private static func planID(
        profileID: UUID,
        lab: TrainingLab,
        laneID: String,
        bankVersion: Int,
        reservationOrdinal: UInt64
    ) -> String {
        "offline-rotation.v\(algorithmVersion).bank-\(bankVersion).\(profileID.uuidString.lowercased()).\(lab.rawValue).lane-\(identityComponent(laneID)).reservation-\(reservationOrdinal)"
    }

    /// An injective, separator-safe representation for arbitrary UTF-8 lane IDs.
    private static func identityComponent(_ value: String) -> String {
        value.utf8.map { String(format: "%02x", $0) }.joined()
    }
}

private struct NFOfflineQuestionRotationRandom: Sendable {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed == 0 ? 0x9E37_79B9_7F4A_7C15 : seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var value = state
        value = (value ^ (value >> 30)) &* 0xBF58_476D_1CE4_E5B9
        value = (value ^ (value >> 27)) &* 0x94D0_49BB_1331_11EB
        return value ^ (value >> 31)
    }

    mutating func shuffle<Element>(_ values: inout [Element]) {
        guard values.count > 1 else { return }
        for index in stride(from: values.count - 1, through: 1, by: -1) {
            let other = Int(next() % UInt64(index + 1))
            if index != other { values.swapAt(index, other) }
        }
    }
}

extension NFOfflineQuestionRotation {
    /// Observe one finite epoch without accepting any candidate. This preserves
    /// the exact original permutation and every ineligible hole. No store read,
    /// cursor publication, speculative ownership or exposure occurs here.
    func availablePositions(profileID: UUID, lab: TrainingLab, laneID: String,
                            bank: NFVersionedOfflineQuestionBank,
                            loadedLedger: NFOfflineQuestionRotationLedger?) throws -> [NFOfflineQuestionRotationPlanItem] {
        var positions: [NFOfflineQuestionRotationPlanItem] = []
        do {
            _ = try prepareReservation(profileID: profileID, lab: lab, laneID: laneID, itemCount: 1,
                bank: bank, loadedLedger: loadedLedger) { position in
                    positions.append(position); return false
                }
        } catch NFOfflineQuestionRotationError.insufficientEligibleQuestions(actual: 0, required: 1) {
            return positions
        }
        throw NFOfflineQuestionRotationError.rotationInvariantViolation
    }
}

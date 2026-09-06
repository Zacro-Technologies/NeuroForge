import Foundation
import CryptoKit

/// Local, ordinary-practice reservation policy. It grants neither content
/// admission nor a band claim. The coordinator supplies currently eligible,
/// verified candidates and atomically publishes the returned state with the run.
struct NFReservationScope: Codable, Hashable, Sendable {
    let profileID: String
    let labID: String
    let contentEditionID: String
    let laneID: String
    let privacyScopeID: String
    let positionRecipeID: String
    var key: String { NFSelectionReservationPolicy.identity([profileID, labID, contentEditionID, laneID, privacyScopeID, positionRecipeID]) }
}
struct NFReservationPosition: Codable, Hashable, Sendable {
    let epoch: UInt64
    let ordinal: Int
}
struct NFReservationVersionPin: Codable, Equatable, Sendable {
    let catalogFingerprint: String
    let generatorVersion: String
    let selectionPolicyVersion: String
    let presentationVersion: String
    let scorerVersion: String
}
enum NFReservationStrategy: String, Codable, Sendable { case fixedBlock, adaptiveItem }
enum NFReservationOperation: String, Codable, Sendable { case launch, next, replace }
enum NFReservationSlotStatus: String, Codable, Sendable { case reserved, presented, answered, skipped, revealed, replaced, abandoned, invalidated }

struct NFReservationSnapshot: Codable, Equatable, Sendable {
    let id: String
    let digest: String
    let payload: Data
    let evaluationContractID: String
    let evaluationContractDigest: String
    static func digest(_ payload: Data) -> String {
        SHA256.hash(data: payload).map { String(format: "%02x", $0) }.joined()
    }
}
struct NFReservationCandidate: Codable, Equatable, Sendable {
    let candidateID: String
    let semanticID: String
    let position: NFReservationPosition
    let snapshot: NFReservationSnapshot
    /// Lexicographic rank and explicit tie key come from the versioned selector.
    let rank: [Int]
    let tieKey: UInt64
    let selectionReason: String
    let eligibilityRevision: String
    let eligible: Bool
    let protectedContent: Bool
}
struct NFReservationCommand: Codable, Equatable, Sendable {
    let decisionID: String
    let runID: String
    let ownerDeviceID: String
    let scope: NFReservationScope
    let versions: NFReservationVersionPin
    let configurationDigest: String
    let strategy: NFReservationStrategy
    let operation: NFReservationOperation
    let decisionOrdinal: UInt64
    let intendedPathOrdinal: Int
    let plannedQuestionOrdinal: Int
    let predecessorSlotID: String?
    /// Exact order for a predetermined launch. Never a list of advisory probes.
    let fixedPlannedPositions: [NFReservationPosition]
    var legacyReservationID: String? = nil
    var intendedSlotIDs: [String]? = nil
    var intendedAttemptIDs: [String]? = nil
    var launchQuestionOrdinal: Int = 0
}
struct NFVerifiedLegacyReservationPlan: Codable, Equatable, Sendable {
    let id: String
    let scope: NFReservationScope
    let catalogFingerprint: String
    let positions: [NFReservationPosition]
    let candidateIDs: [String]
    let sourceDigest: String
}
struct NFReservationSlot: Codable, Equatable, Sendable, Identifiable {
    let id: String
    let attemptID: String
    let decisionID: String
    let runID: String
    let pathOrdinal: Int
    let plannedQuestionOrdinal: Int
    let position: NFReservationPosition
    let candidateID: String
    let semanticID: String
    let snapshotID: String
    let snapshotDigest: String
    let selectionReason: String
    let eligibilityRevision: String
    let replacesSlotID: String?
    var status: NFReservationSlotStatus
}
struct NFReservationDecision: Codable, Equatable, Sendable {
    let command: NFReservationCommand
    let acceptedSlotIDs: [String]
}
struct NFReservationRun: Codable, Equatable, Sendable {
    let id: String
    let ownerDeviceID: String
    let scope: NFReservationScope
    let versions: NFReservationVersionPin
    let configurationDigest: String
    let strategy: NFReservationStrategy
    var nextDecisionOrdinal: UInt64 = 0
    var slotIDs: [String] = []
    var semanticExclusions: Set<String> = []
    var ended = false
}
struct NFReservationExposure: Codable, Equatable, Sendable {
    let eventID: String
    let runID: String
    let slotID: String
    let presentationOrdinal: Int
    let occurredAt: Date
}
struct NFReservationOutcome: Codable, Equatable, Sendable {
    let eventID: String
    let runID: String
    let slotID: String
    let status: NFReservationSlotStatus
}
struct NFLegacyReservationConsumption: Codable, Equatable, Sendable {
    let migrationID: String
    let sourceDigest: String
    let completedEpochsBefore: UInt64
    let currentEpochConsumedPrefix: Int
    let bankQuestionCount: Int
    func contains(_ position: NFReservationPosition) -> Bool {
        position.epoch < completedEpochsBefore ||
            (position.epoch == completedEpochsBefore && position.ordinal < currentEpochConsumedPrefix)
    }
}
struct NFReservationScopeState: Codable, Equatable, Sendable {
    let catalogFingerprint: String
    let authorityID: String
    let legacyConsumption: NFLegacyReservationConsumption?
    var consumedPositions: Set<NFReservationPosition> = []
    /// Retained launch receipt only; never an inferred global cursor history.
    var retainedPlanPositions: Set<NFReservationPosition> = []
    func contains(_ position: NFReservationPosition) -> Bool {
        consumedPositions.contains(position) || retainedPlanPositions.contains(position) || legacyConsumption?.contains(position) == true
    }
}
struct NFSelectionReservationLedger: Codable, Equatable, Sendable {
    var schemaVersion = 1
    var revision: UInt64 = 0
    var scopes: [String: NFReservationScopeState] = [:]
    var runs: [String: NFReservationRun] = [:]
    var slots: [String: NFReservationSlot] = [:]
    var snapshots: [String: NFReservationSnapshot] = [:]
    var decisions: [String: NFReservationDecision] = [:]
    var exposures: [String: NFReservationExposure] = [:]
    var outcomes: [String: NFReservationOutcome] = [:]
    var legacyReservationOwners: [String: String] = [:]
    var legacyPlans: [String: NFVerifiedLegacyReservationPlan] = [:]
}
struct NFReservationAcceptance: Equatable, Sendable {
    let expectedRevision: UInt64
    let state: NFSelectionReservationLedger
    let decision: NFReservationDecision
    let isReplay: Bool
    var slots: [NFReservationSlot] { decision.acceptedSlotIDs.compactMap { state.slots[$0] } }
}
enum NFReservationError: Error, Equatable, Sendable {
    case unsupportedVersion, malformedIdentity, unseededScope, catalogConflict, staleRevision
    case wrongOwner, conflictingDecision, invalidSequence, pendingUnpresentedSlot, insufficientCapacity
    case invalidSnapshot, conflictingSnapshot, protectedFormRequired, invalidTransition, ordinalOverflow
}

enum NFSelectionReservationPolicy {
    static let policyVersion = "OrdinaryReservationV1"
    static let maximumSnapshotBytes = 8 * 1_024 * 1_024

    static func identity(_ parts: [String]) -> String { parts.map { "\($0.utf8.count):\($0)" }.joined() }
    static func decisionID(runID: String, ordinal: UInt64) -> String {
        "selection." + NFReservationSnapshot.digest(Data(identity([policyVersion, runID, String(ordinal)]).utf8))
    }
    private static func uuid(_ parts: [String]) -> String {
        let hex = Array(NFReservationSnapshot.digest(Data(identity(parts).utf8)).prefix(32))
        return String(hex[0..<8]) + "-" + String(hex[8..<12]) + "-" + String(hex[12..<16]) + "-" + String(hex[16..<20]) + "-" + String(hex[20..<32])
    }
    private static func increment(_ value: UInt64) throws -> UInt64 {
        let (next, overflow) = value.addingReportingOverflow(1)
        guard !overflow else { throw NFReservationError.ordinalOverflow }
        return next
    }
    private static func snapshotKey(scope: NFReservationScope, id: String) -> String {
        identity([scope.profileID, scope.privacyScopeID, id])
    }

    /// Explicit bootstrap, only after the coordinator verified the old scope is
    /// empty. An absent new ledger is not proof that legacy consumption is empty.
    static func registerFreshScope(_ scope: NFReservationScope, catalogFingerprint: String,
                                   verifiedEmptySourceID: String, in original: NFSelectionReservationLedger) throws -> NFSelectionReservationLedger {
        try register(scope, fingerprint: catalogFingerprint, authorityID: verifiedEmptySourceID, legacy: nil, in: original)
    }
    static func seedLegacyScope(_ scope: NFReservationScope, catalogFingerprint: String, sourcePositionRecipeID: String,
                                migrationID: String, sourceDigest: String, epoch: UInt64, cursor: Int,
                                bankQuestionCount: Int, in original: NFSelectionReservationLedger) throws -> NFSelectionReservationLedger {
        guard scope.positionRecipeID == sourcePositionRecipeID, bankQuestionCount > 0,
              cursor >= 0, cursor < bankQuestionCount, !sourceDigest.isEmpty else { throw NFReservationError.catalogConflict }
        let legacy = NFLegacyReservationConsumption(migrationID: migrationID, sourceDigest: sourceDigest,
            completedEpochsBefore: epoch, currentEpochConsumedPrefix: cursor, bankQuestionCount: bankQuestionCount)
        return try register(scope, fingerprint: catalogFingerprint, authorityID: migrationID, legacy: legacy, in: original)
    }
    /// A run-scoped retained plan proves its own pre-reserved positions only.
    /// Full shared-bank authority still requires seedLegacyScope's actual cursor.
    static func registerRetainedPlan(_ plan: NFVerifiedLegacyReservationPlan,
                                     in original: NFSelectionReservationLedger) throws -> NFSelectionReservationLedger {
        guard plan.scope.positionRecipeID == "legacy-plan-occurrence.v1",
              !plan.positions.isEmpty, plan.positions.count == plan.candidateIDs.count,
              Set(plan.positions).count == plan.positions.count,
              plan.positions.allSatisfy({ $0.ordinal >= 0 }), !plan.sourceDigest.isEmpty else { throw NFReservationError.catalogConflict }
        var next = try register(plan.scope, fingerprint: plan.catalogFingerprint,
            authorityID: "retained-plan:" + plan.id, legacy: nil, in: original)
        let positions = Set(plan.positions)
        if let prior = original.scopes[plan.scope.key] {
            guard prior.retainedPlanPositions == positions else { throw NFReservationError.catalogConflict }
        } else {
            next.scopes[plan.scope.key]?.retainedPlanPositions = positions
        }
        return next
    }
    private static func register(_ scope: NFReservationScope, fingerprint: String, authorityID: String,
                                 legacy: NFLegacyReservationConsumption?, in original: NFSelectionReservationLedger) throws -> NFSelectionReservationLedger {
        guard original.schemaVersion == 1 else { throw NFReservationError.unsupportedVersion }
        guard !authorityID.isEmpty, !fingerprint.isEmpty,
              [scope.profileID, scope.labID, scope.contentEditionID, scope.laneID, scope.privacyScopeID, scope.positionRecipeID].allSatisfy({ !$0.isEmpty }) else { throw NFReservationError.malformedIdentity }
        let registration = NFReservationScopeState(catalogFingerprint: fingerprint, authorityID: authorityID, legacyConsumption: legacy)
        if let existing = original.scopes[scope.key] {
            guard existing.catalogFingerprint == fingerprint, existing.authorityID == authorityID,
                  existing.legacyConsumption == legacy else { throw NFReservationError.catalogConflict }
            return original
        }
        var next = original; next.scopes[scope.key] = registration; next.revision = try increment(next.revision)
        return next
    }

    static func prepareAcceptance(command: NFReservationCommand, candidates: [NFReservationCandidate],
                                  state original: NFSelectionReservationLedger, expectedRevision: UInt64,
                                  legacyPlan: NFVerifiedLegacyReservationPlan? = nil) throws -> NFReservationAcceptance {
        guard original.schemaVersion == 1 else { throw NFReservationError.unsupportedVersion }
        if let accepted = original.decisions[command.decisionID] {
            guard accepted.command == command else { throw NFReservationError.conflictingDecision }
            return .init(expectedRevision: original.revision, state: original, decision: accepted, isReplay: true)
        }
        guard original.revision == expectedRevision else { throw NFReservationError.staleRevision }
        guard !command.runID.isEmpty, !command.ownerDeviceID.isEmpty, !command.configurationDigest.isEmpty,
              command.decisionID == decisionID(runID: command.runID, ordinal: command.decisionOrdinal),
              command.intendedPathOrdinal >= 0, command.plannedQuestionOrdinal >= 0 else { throw NFReservationError.malformedIdentity }
        guard var scope = original.scopes[command.scope.key] else { throw NFReservationError.unseededScope }
        guard scope.catalogFingerprint == command.versions.catalogFingerprint else { throw NFReservationError.catalogConflict }
        var run = original.runs[command.runID] ?? NFReservationRun(id: command.runID,
            ownerDeviceID: command.ownerDeviceID, scope: command.scope, versions: command.versions,
            configurationDigest: command.configurationDigest, strategy: command.strategy)
        guard run.ownerDeviceID == command.ownerDeviceID else { throw NFReservationError.wrongOwner }
        guard !run.ended, run.scope == command.scope, run.versions == command.versions,
              run.configurationDigest == command.configurationDigest, run.strategy == command.strategy,
              run.nextDecisionOrdinal == command.decisionOrdinal, run.slotIDs.count == command.intendedPathOrdinal else { throw NFReservationError.invalidSequence }
        let runSlots = run.slotIDs.compactMap { original.slots[$0] }
        let replacing: NFReservationSlot?
        switch command.operation {
        case .launch:
            guard original.runs[command.runID] == nil, command.decisionOrdinal == 0,
                  command.intendedPathOrdinal == 0, command.launchQuestionOrdinal >= 0,
                  command.plannedQuestionOrdinal == command.launchQuestionOrdinal, command.predecessorSlotID == nil else { throw NFReservationError.invalidSequence }
            replacing = nil
        case .next:
            guard run.strategy == .adaptiveItem || command.legacyReservationID != nil, let prior = runSlots.last,
                  prior.id == command.predecessorSlotID, [.answered, .skipped, .revealed, .invalidated].contains(prior.status),
                  command.plannedQuestionOrdinal == prior.plannedQuestionOrdinal + 1 else { throw NFReservationError.invalidSequence }
            replacing = nil
        case .replace:
            guard let id = command.predecessorSlotID, let prior = original.slots[id], prior.runID == run.id,
                  [.reserved, .presented, .invalidated].contains(prior.status),
                  command.plannedQuestionOrdinal == prior.plannedQuestionOrdinal else { throw NFReservationError.invalidSequence }
            replacing = prior
        }
        if run.strategy == .adaptiveItem, runSlots.contains(where: { $0.status == .reserved && $0.id != replacing?.id }) {
            throw NFReservationError.pendingUnpresentedSlot
        }
        guard Set(candidates.map(\.position)).count == candidates.count,
              Set(candidates.map(\.candidateID)).count == candidates.count else { throw NFReservationError.conflictingDecision }
        let legacyPositions: Set<NFReservationPosition>
        if let legacyID = command.legacyReservationID {
            guard let plan = legacyPlan, plan.id == legacyID, plan.scope == command.scope,
                  plan.catalogFingerprint == command.versions.catalogFingerprint, !plan.sourceDigest.isEmpty,
                  command.strategy == .fixedBlock,
                  plan.positions.count == plan.candidateIDs.count, Set(plan.positions).count == plan.positions.count,
                  original.legacyReservationOwners[legacyID] == nil || original.legacyReservationOwners[legacyID] == run.id,
                  plan.positions.allSatisfy({ position in
                      position.ordinal >= 0 && (scope.retainedPlanPositions.contains(position) ||
                        (scope.legacyConsumption.map { $0.contains(position) && position.ordinal < $0.bankQuestionCount } ?? false))
                  }) else { throw NFReservationError.catalogConflict }
            if command.fixedPlannedPositions != plan.positions {
                guard plan.positions.indices.contains(command.plannedQuestionOrdinal),
                      command.fixedPlannedPositions == [plan.positions[command.plannedQuestionOrdinal]] else { throw NFReservationError.catalogConflict }
            }
            if let old = original.legacyPlans[legacyID], old != plan { throw NFReservationError.catalogConflict }
            let expectedIDs = Dictionary(uniqueKeysWithValues: zip(plan.positions, plan.candidateIDs))
            guard candidates.filter({ expectedIDs[$0.position] != nil }).allSatisfy({ expectedIDs[$0.position] == $0.candidateID }) else { throw NFReservationError.catalogConflict }
            legacyPositions = Set(plan.positions)
        } else {
            guard legacyPlan == nil else { throw NFReservationError.catalogConflict }
            legacyPositions = []
        }
        let feasible = candidates.filter {
            $0.eligible && !$0.protectedContent && $0.position.ordinal >= 0
                && !scope.consumedPositions.contains($0.position)
                && (!scope.contains($0.position) || legacyPositions.contains($0.position))
                && !run.semanticExclusions.contains($0.semanticID)
        }
        let selected: [NFReservationCandidate]
        if command.strategy == .fixedBlock && (command.operation == .launch || command.legacyReservationID != nil) {
            guard !command.fixedPlannedPositions.isEmpty,
                  Set(command.fixedPlannedPositions).count == command.fixedPlannedPositions.count else { throw NFReservationError.invalidSequence }
            let byPosition = Dictionary(uniqueKeysWithValues: feasible.map { ($0.position, $0) })
            selected = command.fixedPlannedPositions.compactMap { byPosition[$0] }
            guard selected.count == command.fixedPlannedPositions.count else { throw NFReservationError.insufficientCapacity }
        } else {
            guard command.fixedPlannedPositions.isEmpty else { throw NFReservationError.invalidSequence }
            guard let first = feasible.sorted(by: rankBefore).first else { throw NFReservationError.insufficientCapacity }
            selected = [first]
        }
        guard Set(selected.map(\.semanticID)).count == selected.count else { throw NFReservationError.insufficientCapacity }
        guard command.intendedSlotIDs.map({ $0.count == selected.count && Set($0).count == $0.count && $0.allSatisfy({ UUID(uuidString: $0) != nil }) }) ?? true,
              command.intendedAttemptIDs.map({ $0.count == selected.count && Set($0).count == $0.count && $0.allSatisfy({ UUID(uuidString: $0) != nil }) }) ?? true else { throw NFReservationError.malformedIdentity }
        var next = original
        if let replacing { next.slots[replacing.id]?.status = .replaced }
        var ids: [String] = []
        for (offset, candidate) in selected.enumerated() {
            let snapshot = candidate.snapshot
            guard !candidate.candidateID.isEmpty, !candidate.semanticID.isEmpty,
                  !snapshot.id.isEmpty, !snapshot.evaluationContractID.isEmpty, !snapshot.evaluationContractDigest.isEmpty,
                  !snapshot.payload.isEmpty, snapshot.payload.count <= maximumSnapshotBytes,
                  snapshot.digest == NFReservationSnapshot.digest(snapshot.payload) else { throw NFReservationError.invalidSnapshot }
            let key = snapshotKey(scope: command.scope, id: snapshot.id)
            if let old = next.snapshots[key], old != snapshot { throw NFReservationError.conflictingSnapshot }
            next.snapshots[key] = snapshot
            let id = command.intendedSlotIDs?[offset] ?? uuid([policyVersion, command.decisionID, String(offset), "slot"])
            let attemptID = command.intendedAttemptIDs?[offset] ?? uuid([policyVersion, id, "attempt"])
            guard next.slots[id] == nil, !next.slots.values.contains(where: { $0.attemptID == attemptID }) else { throw NFReservationError.conflictingDecision }
            let slot = NFReservationSlot(id: id, attemptID: attemptID, decisionID: command.decisionID,
                runID: run.id, pathOrdinal: command.intendedPathOrdinal + offset,
                plannedQuestionOrdinal: command.plannedQuestionOrdinal + offset, position: candidate.position,
                candidateID: candidate.candidateID, semanticID: candidate.semanticID, snapshotID: snapshot.id,
                snapshotDigest: snapshot.digest, selectionReason: candidate.selectionReason,
                eligibilityRevision: candidate.eligibilityRevision, replacesSlotID: replacing?.id, status: .reserved)
            next.slots[id] = slot; ids.append(id); run.slotIDs.append(id)
            run.semanticExclusions.insert(candidate.semanticID); scope.consumedPositions.insert(candidate.position)
        }
        let decision = NFReservationDecision(command: command, acceptedSlotIDs: ids)
        if let legacyID = command.legacyReservationID {
            next.legacyReservationOwners[legacyID] = run.id
            next.legacyPlans[legacyID] = legacyPlan
        }
        run.nextDecisionOrdinal = try increment(run.nextDecisionOrdinal)
        next.runs[run.id] = run; next.scopes[command.scope.key] = scope; next.decisions[command.decisionID] = decision
        next.revision = try increment(next.revision)
        return .init(expectedRevision: original.revision, state: next, decision: decision, isReplay: false)
    }

    /// Optimistic publication check. The physical repository must also write its
    /// matching run/checkpoint/snapshot in this same atomic replacement.
    static func applying(_ acceptance: NFReservationAcceptance, to current: NFSelectionReservationLedger) throws -> NFSelectionReservationLedger {
        if let existing = current.decisions[acceptance.decision.command.decisionID] {
            guard existing == acceptance.decision else { throw NFReservationError.conflictingDecision }
            return current
        }
        guard current.revision == acceptance.expectedRevision else { throw NFReservationError.staleRevision }
        return acceptance.state
    }

    static func acknowledgePresentation(eventID: String, runID: String, slotID: String, ownerDeviceID: String,
                                        presentationOrdinal: Int, occurredAt: Date,
                                        in original: NFSelectionReservationLedger) throws -> NFSelectionReservationLedger {
        guard let run = original.runs[runID], run.ownerDeviceID == ownerDeviceID else { throw NFReservationError.wrongOwner }
        if let existing = original.exposures[eventID] {
            guard existing.runID == runID, existing.slotID == slotID, existing.presentationOrdinal == presentationOrdinal else { throw NFReservationError.conflictingDecision }
            return original // Repeated rendering retains the original acknowledgement time.
        }
        guard !run.ended, !eventID.isEmpty, occurredAt.timeIntervalSince1970.isFinite,
              var slot = original.slots[slotID], slot.runID == runID, slot.status == .reserved,
              !original.exposures.values.contains(where: { $0.slotID == slotID }),
              presentationOrdinal == original.exposures.values.filter({ $0.runID == runID }).count else { throw NFReservationError.invalidTransition }
        let earlier = run.slotIDs.compactMap { original.slots[$0] }.filter { $0.plannedQuestionOrdinal < slot.plannedQuestionOrdinal }
        guard !earlier.contains(where: { $0.status == .reserved || $0.status == .presented }) else { throw NFReservationError.invalidSequence }
        var next = original; slot.status = .presented; next.slots[slotID] = slot
        next.exposures[eventID] = .init(eventID: eventID, runID: runID, slotID: slotID,
            presentationOrdinal: presentationOrdinal, occurredAt: occurredAt)
        next.revision = try increment(next.revision); return next
    }
    static func recordOutcome(_ outcome: NFReservationOutcome, ownerDeviceID: String, acknowledgedAttemptID: String? = nil,
                              in original: NFSelectionReservationLedger) throws -> NFSelectionReservationLedger {
        guard let run = original.runs[outcome.runID], run.ownerDeviceID == ownerDeviceID else { throw NFReservationError.wrongOwner }
        if let old = original.outcomes[outcome.eventID] {
            guard old == outcome else { throw NFReservationError.conflictingDecision }; return original
        }
        guard !run.ended, !outcome.eventID.isEmpty, var slot = original.slots[outcome.slotID], slot.runID == run.id,
              [.answered, .skipped, .revealed, .invalidated, .abandoned].contains(outcome.status),
              slot.status == .presented || (slot.status == .reserved &&
                ([.invalidated, .abandoned].contains(outcome.status) || acknowledgedAttemptID == slot.attemptID)) else { throw NFReservationError.invalidTransition }
        var next = original; slot.status = outcome.status; next.slots[slot.id] = slot
        next.outcomes[outcome.eventID] = outcome; next.revision = try increment(next.revision); return next
    }
    static func endRun(_ runID: String, ownerDeviceID: String, in original: NFSelectionReservationLedger) throws -> NFSelectionReservationLedger {
        guard var run = original.runs[runID], run.ownerDeviceID == ownerDeviceID else { throw NFReservationError.wrongOwner }
        if run.ended { return original }
        var next = original; run.ended = true; next.runs[runID] = run
        for id in run.slotIDs where [.reserved, .presented].contains(next.slots[id]?.status) { next.slots[id]?.status = .abandoned }
        next.revision = try increment(next.revision); return next
    }
    static func advisoryPrewarm(_ candidates: [NFReservationCandidate]) -> [NFReservationCandidate] {
        Array(candidates.filter { $0.eligible && !$0.protectedContent }.sorted(by: rankBefore).prefix(2))
    }
    static func snapshot(for slot: NFReservationSlot, in state: NFSelectionReservationLedger) -> NFReservationSnapshot? {
        guard let scope = state.runs[slot.runID]?.scope else { return nil }
        return state.snapshots[snapshotKey(scope: scope, id: slot.snapshotID)]
    }
    private static func rankBefore(_ a: NFReservationCandidate, _ b: NFReservationCandidate) -> Bool {
        if a.rank != b.rank { return a.rank.lexicographicallyPrecedes(b.rank) }
        return a.tieKey == b.tieKey ? a.candidateID < b.candidateID : a.tieKey < b.tieKey
    }
}

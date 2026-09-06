import Foundation

extension NFSelectionReservationPolicy {
    /// Import the real legacy cursor before enabling the new ledger for the SAME
    /// position recipe/catalog. No catalog ordinal is inferred to be a position.
    static func seedLegacyScope(_ scope: NFReservationScope, source: NFOfflineQuestionRotationScopeState,
                                sourcePositionRecipeID: String, migrationID: String, sourceDigest: String,
                                in state: NFSelectionReservationLedger) throws -> NFSelectionReservationLedger {
        guard source.hasValidConsumption else { throw NFReservationError.catalogConflict }
        var next = try seedLegacyScope(scope, catalogFingerprint: source.bankFingerprint,
            sourcePositionRecipeID: sourcePositionRecipeID, migrationID: migrationID, sourceDigest: sourceDigest,
            epoch: source.epoch, cursor: source.cursor, bankQuestionCount: source.bankQuestionCount, in: state)
        let sparse = Set((source.consumedEpochOrdinals ?? []).map { NFReservationPosition(epoch: source.epoch, ordinal: $0) })
        if let existing = state.scopes[scope.key] {
            guard sparse.isSubset(of: existing.consumedPositions) else { throw NFReservationError.catalogConflict }
        } else {
            next.scopes[scope.key]?.consumedPositions.formUnion(sparse)
        }
        return next
    }

    /// The coordinator obtains both values from the acknowledged legacy store,
    /// verifies ownership/scope, then supplies this explicit adoption authority.
    static func verifiedLegacyPlan(_ plan: NFOfflineQuestionRotationPlan, scope: NFReservationScope,
                                   source: NFOfflineQuestionRotationScopeState, sourceDigest: String) throws -> NFVerifiedLegacyReservationPlan {
        guard plan.profileID.uuidString.lowercased() == scope.profileID.lowercased(),
              plan.lab.rawValue == scope.labID, plan.laneID == scope.laneID,
              plan.reservationOrdinal < source.nextReservationOrdinal,
              Set(plan.items.map(\.quizOrdinal)).count == plan.items.count,
              plan.items.enumerated().allSatisfy({ $0.offset == $0.element.quizOrdinal }),
              !sourceDigest.isEmpty else { throw NFReservationError.catalogConflict }
        return NFVerifiedLegacyReservationPlan(id: plan.id, scope: scope,
            catalogFingerprint: source.bankFingerprint,
            positions: plan.items.map { .init(epoch: $0.epoch, ordinal: $0.epochOrdinal) },
            candidateIDs: plan.items.map(\.questionID), sourceDigest: sourceDigest)
    }
}

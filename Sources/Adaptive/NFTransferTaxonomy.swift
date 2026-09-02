import Foundation

enum NFTransferTaxonomyError: Error, Equatable, LocalizedError {
    case requestExerciseLabMismatch
    case transferBriefOutsideTransferLab
    case transferBriefUsesWrongEvidence
    case transferSkillMissing
    case retrievalSkillLeak

    var errorDescription: String? {
        switch self {
        case .requestExerciseLabMismatch:
            NFAppLocalization.localized(
                "The generated activity does not match the requested practice area.",
                locale: NFAppLocalization.preferredLocale,
                comment: "Transfer taxonomy validation error."
            )
        case .transferBriefOutsideTransferLab:
            NFAppLocalization.localized(
                "A transfer mission must stay in the Transfer lab.",
                locale: NFAppLocalization.preferredLocale,
                comment: "Transfer taxonomy validation error."
            )
        case .transferBriefUsesWrongEvidence:
            NFAppLocalization.localized(
                "A scheduled transfer mission must be recorded as applied transfer.",
                locale: NFAppLocalization.preferredLocale,
                comment: "Transfer taxonomy validation error."
            )
        case .transferSkillMissing:
            NFAppLocalization.localized(
                "The transfer activity is missing its Transfer skill attribution.",
                locale: NFAppLocalization.preferredLocale,
                comment: "Transfer taxonomy validation error."
            )
        case .retrievalSkillLeak:
            NFAppLocalization.localized(
                "Transfer evidence cannot be attributed to Retrieval.",
                locale: NFAppLocalization.preferredLocale,
                comment: "Transfer taxonomy validation error."
            )
        }
    }
}

/// One end-to-end contract for the Transfer lane. Retrieval remains recall of
/// source material; Transfer remains application across changed contexts or
/// representations. Evidence classes describe the strength of the task but do
/// not rewrite either lab's taxonomy.
enum NFTransferTaxonomy {
    static func validate(request: SessionRequest, exercise: NFExercise) throws {
        guard request.lab == exercise.lab else {
            throw NFTransferTaxonomyError.requestExerciseLabMismatch
        }
        guard request.evidenceClass == exercise.evidenceClass else {
            throw NFTransferTaxonomyError.transferBriefUsesWrongEvidence
        }
        if request.transferBrief != nil {
            guard request.lab == .transfer, exercise.lab == .transfer else {
                throw NFTransferTaxonomyError.transferBriefOutsideTransferLab
            }
            guard request.evidenceClass == .appliedTransfer,
                  exercise.evidenceClass == .appliedTransfer else {
                throw NFTransferTaxonomyError.transferBriefUsesWrongEvidence
            }
        }
        try validate(exercise: exercise)
    }

    static func validate(exercise: NFExercise) throws {
        guard exercise.lab == .transfer || exercise.sourceContext.transferBrief != nil else { return }
        guard exercise.lab == .transfer else {
            throw NFTransferTaxonomyError.transferBriefOutsideTransferLab
        }
        guard (exercise.skillWeights[TrainingLab.transfer.skillID] ?? 0) > 0 else {
            throw NFTransferTaxonomyError.transferSkillMissing
        }
        guard (exercise.skillWeights[TrainingLab.retrieval.skillID] ?? 0) == 0 else {
            throw NFTransferTaxonomyError.retrievalSkillLeak
        }
        if exercise.sourceContext.transferBrief != nil,
           exercise.evidenceClass != .appliedTransfer {
            throw NFTransferTaxonomyError.transferBriefUsesWrongEvidence
        }
    }

    static func validate(attempt: AttemptRecord) throws {
        guard attempt.gameID == TrainingLab.transfer.rawValue || attempt.transferBrief != nil else { return }
        guard attempt.gameID == TrainingLab.transfer.rawValue else {
            throw NFTransferTaxonomyError.transferBriefOutsideTransferLab
        }
        guard (attempt.skillWeights[TrainingLab.transfer.skillID] ?? 0) > 0 else {
            throw NFTransferTaxonomyError.transferSkillMissing
        }
        guard (attempt.skillWeights[TrainingLab.retrieval.skillID] ?? 0) == 0,
              attempt.skillID != TrainingLab.retrieval.skillID else {
            throw NFTransferTaxonomyError.retrievalSkillLeak
        }
        if attempt.transferBrief != nil,
           attempt.evidenceClassRaw != EvidenceClass.appliedTransfer.rawValue {
            throw NFTransferTaxonomyError.transferBriefUsesWrongEvidence
        }
    }

    /// Version-one builds could persist scheduled transfer work under the
    /// Retrieval lab. Repair only records with positive transfer provenance;
    /// ordinary retrieval attempts are never reclassified heuristically.
    @discardableResult
    static func migrateLegacyAttempts(_ attempts: [AttemptRecord]) -> Bool {
        var didChange = false
        for attempt in attempts where attempt.gameID == TrainingLab.retrieval.rawValue {
            let hasExplicitTransferProvenance = attempt.transferBrief != nil
                || attempt.planID?.hasPrefix("nf.transfer.weekly.") == true
            guard hasExplicitTransferProvenance else { continue }

            attempt.gameID = TrainingLab.transfer.rawValue
            if attempt.skillID == TrainingLab.retrieval.skillID {
                attempt.skillID = TrainingLab.transfer.skillID
            }
            var weights = attempt.skillWeights
            let leakedWeight = weights.removeValue(forKey: TrainingLab.retrieval.skillID) ?? 0
            weights[TrainingLab.transfer.skillID] = max(
                weights[TrainingLab.transfer.skillID] ?? 0,
                leakedWeight,
                0.7
            )
            let total = weights.values.reduce(0, +)
            if total > 0 {
                weights = weights.mapValues { $0 / total }
            }
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            if let data = try? encoder.encode(weights) {
                attempt.skillWeightsRaw = String(data: data, encoding: .utf8) ?? ""
            }
            attempt.evidenceClassRaw = EvidenceClass.appliedTransfer.rawValue
            didChange = true
        }
        return didChange
    }
}

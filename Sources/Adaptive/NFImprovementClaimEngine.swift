import Foundation

enum NFImprovementClaimCode: String, Codable, Sendable {
    case practiceImproved
    case nearTransferImproved
    case appliedTransferImproved
    case retentionImproved
    case protectedAssessmentImproved

    var title: String {
        switch self {
        case .practiceImproved: NFAppLocalization.localized("Improved on this practice family", locale: NFAppLocalization.preferredLocale, comment: "Evidence-bounded improvement claim for comparable practice items.")
        case .nearTransferImproved: NFAppLocalization.localized("Improved on unfamiliar near-transfer items", locale: NFAppLocalization.preferredLocale, comment: "Evidence-bounded improvement claim. Near transfer means a related but unfamiliar form.")
        case .appliedTransferImproved: NFAppLocalization.localized("Improved on applied transfer items", locale: NFAppLocalization.preferredLocale, comment: "Evidence-bounded improvement claim for use in a different applied context.")
        case .retentionImproved: NFAppLocalization.localized("Improved on delayed retention checks", locale: NFAppLocalization.preferredLocale, comment: "Evidence-bounded improvement claim for recall after a delay.")
        case .protectedAssessmentImproved: NFAppLocalization.localized("Improved on alternate protected forms", locale: NFAppLocalization.preferredLocale, comment: "Evidence-bounded improvement claim using unexposed alternate assessment forms.")
        }
    }
}

struct NFImprovementEvidenceBundle: Equatable, Sendable {
    let lab: TrainingLab
    let evidenceClass: EvidenceClass
    let earlierWindowStart: Date
    let earlierWindowEnd: Date
    let laterWindowStart: Date
    let laterWindowEnd: Date
    let earlierCount: Int
    let laterCount: Int
    let earlierCredit: Double
    let laterCredit: Double
    let requiredMargin: Double
    let earlierAlternateFormIDs: Set<String>
    let laterAlternateFormIDs: Set<String>
}

struct NFImprovementClaim: Equatable, Sendable, Identifiable {
    let code: NFImprovementClaimCode
    let evidence: NFImprovementEvidenceBundle

    var id: String { "\(evidence.lab.rawValue).\(code.rawValue).\(evidence.laterWindowEnd.timeIntervalSince1970)" }
    var creditChange: Double { evidence.laterCredit - evidence.earlierCredit }
}

enum NFImprovementClaimEngine {
    static let version = 2
    static let minimumWindowCount = 6
    static let minimumSeparationDays = 7

    static func strongestClaim(
        for lab: TrainingLab,
        attempts: [AttemptDTO]
    ) -> NFImprovementClaim? {
        let priority: [EvidenceClass] = [
            .appliedTransfer,
            .nearTransfer,
            .retention,
            .assessmentHoldout,
            .practice
        ]
        return priority.compactMap {
            claim(for: lab, evidenceClass: $0, attempts: attempts)
        }.max { lhs, rhs in
            if lhs.evidence.evidenceClass == rhs.evidence.evidenceClass {
                return lhs.creditChange < rhs.creditChange
            }
            return priority.firstIndex(of: lhs.evidence.evidenceClass) ?? priority.count
                > priority.firstIndex(of: rhs.evidence.evidenceClass) ?? priority.count
        }
    }

    static func claim(
        for lab: TrainingLab,
        evidenceClass: EvidenceClass,
        attempts: [AttemptDTO],
        minimumWindowCount: Int = minimumWindowCount,
        minimumSeparationDays: Int = minimumSeparationDays
    ) -> NFImprovementClaim? {
        // Formal improvement claims require a validated comparison protocol. Legacy
        // lab percentages and alternate seed namespaces cannot establish equivalence.
        // EditorialBandEvidenceV1 supplies factual compatible-band summaries instead.
        return nil
    }

    private static func stableAttemptOrder(_ lhs: AttemptDTO, _ rhs: AttemptDTO) -> Bool {
        if lhs.submittedAt == rhs.submittedAt { return lhs.id.uuidString < rhs.id.uuidString }
        return lhs.submittedAt < rhs.submittedAt
    }

    private static func weightedCredit(_ attempts: [AttemptDTO]) -> Double {
        let weight = attempts.reduce(0) { $0 + $1.evidenceWeight }
        guard weight > 0 else { return 0 }
        return attempts.reduce(0) { $0 + $1.credit * $1.evidenceWeight } / weight
    }

    private static func proportionUncertainty(credit: Double, weight: Double) -> Double {
        // The variance floor prevents perfect small samples from claiming
        // certainty. This is a conservative evidence gate, not a population norm.
        sqrt(max(0.0475, credit * (1 - credit)) / max(1, weight))
    }
}

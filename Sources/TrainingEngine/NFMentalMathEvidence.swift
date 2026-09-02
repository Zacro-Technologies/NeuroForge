import Foundation

enum NFMentalMathProgressionStage: String, Codable, CaseIterable, Sendable {
    case accuracy
    case flexibility
    case automaticity
    case transfer

    var title: String {
        switch self {
        case .accuracy: NFAppLocalization.localized("Accuracy", locale: NFAppLocalization.preferredLocale, comment: "Mental-math progression stage.")
        case .flexibility: NFAppLocalization.localized("Flexibility", locale: NFAppLocalization.preferredLocale, comment: "Mental-math progression stage requiring more than one valid strategy.")
        case .automaticity: NFAppLocalization.localized("Automaticity", locale: NFAppLocalization.preferredLocale, comment: "Mental-math progression stage for accurate, eligible timed work.")
        case .transfer: NFAppLocalization.localized("Transfer", locale: NFAppLocalization.preferredLocale, comment: "Mental-math progression stage for unfamiliar applications.")
        }
    }
}

struct NFMentalMathProgressionObservation: Codable, Equatable, Sendable {
    let submittedAt: Date
    let isCorrect: Bool
    let errorCode: String?
    let strategyID: String?
    let wasTimed: Bool
    let wasSkipped: Bool
    let evidenceWeight: Double

    init(
        submittedAt: Date,
        isCorrect: Bool,
        errorCode: String? = nil,
        strategyID: String? = nil,
        wasTimed: Bool = false,
        wasSkipped: Bool = false,
        evidenceWeight: Double = 1
    ) {
        self.submittedAt = submittedAt
        self.isCorrect = isCorrect
        self.errorCode = errorCode
        self.strategyID = strategyID
        self.wasTimed = wasTimed
        self.wasSkipped = wasSkipped
        self.evidenceWeight = evidenceWeight
    }
}

struct NFMentalMathProgressionStatus: Codable, Equatable, Sendable {
    let stage: NFMentalMathProgressionStage
    let recentSampleCount: Int
    let rollingAccuracy: Double?
    let distinctStrategyCount: Int
    let timedCorrectSampleCount: Int
    let repeatedMisconceptionCodes: [String]
    let timingEligible: Bool
    let transferEligible: Bool
    let nextGateDescription: String
}

enum NFMentalMathProgressionPolicy {
    static let rollingWindow = 20
    static let flexibilityMinimumSamples = 8
    static let flexibilityAccuracyThreshold = 0.80
    static let automaticityMinimumSamples = 20
    static let automaticityAccuracyThreshold = 0.90
    static let transferTimedMinimumSamples = 8

    static func status(
        for observations: [NFMentalMathProgressionObservation]
    ) -> NFMentalMathProgressionStatus {
        let eligible = observations
            .filter { !$0.wasSkipped && $0.evidenceWeight > 0 }
            .sorted {
                if $0.submittedAt != $1.submittedAt { return $0.submittedAt < $1.submittedAt }
                if $0.isCorrect != $1.isCorrect { return !$0.isCorrect }
                return ($0.strategyID ?? "") < ($1.strategyID ?? "")
            }
        let recent = Array(eligible.suffix(rollingWindow))
        let accuracy = recent.isEmpty
            ? nil
            : Double(recent.filter(\.isCorrect).count) / Double(recent.count)
        let strategyCount = Set(recent.compactMap(\.strategyID).filter { !$0.isEmpty }).count
        let lastTen = eligible.suffix(10)
        let misconceptionCounts = Dictionary(grouping: lastTen.compactMap(\.errorCode), by: { $0 })
        let repeatedCodes = misconceptionCounts
            .filter { $0.value.count >= 2 }
            .map(\.key)
            .sorted()
        let timedCorrectCount = recent.filter { $0.wasTimed && $0.isCorrect }.count

        let stage: NFMentalMathProgressionStage
        let nextGate: String
        if recent.count < flexibilityMinimumSamples
            || (accuracy ?? 0) < flexibilityAccuracyThreshold {
            stage = .accuracy
            nextGate = NFAppLocalization.localized("Reach at least 8 recent attempts with 80% accuracy; first exposure remains untimed.", locale: NFAppLocalization.preferredLocale, comment: "Mental-math progression requirement from accuracy to flexibility.")
        } else if recent.count < automaticityMinimumSamples
                    || (accuracy ?? 0) < automaticityAccuracyThreshold
                    || strategyCount < 2
                    || !repeatedCodes.isEmpty {
            stage = .flexibility
            nextGate = NFAppLocalization.localized("Reach 20 recent attempts at 90% accuracy, use at least two valid strategy families, and clear repeated misconception codes from the last 10 attempts.", locale: NFAppLocalization.preferredLocale, comment: "Mental-math progression requirement from flexibility to automaticity.")
        } else if timedCorrectCount < transferTimedMinimumSamples {
            stage = .automaticity
            nextGate = NFAppLocalization.localized("Build 8 correct, explicitly timed automaticity observations before transfer-focused timing is eligible.", locale: NFAppLocalization.preferredLocale, comment: "Mental-math progression requirement from automaticity to transfer.")
        } else {
            stage = .transfer
            nextGate = NFAppLocalization.localized("Automaticity gate met; keep accuracy, retention, and unfamiliar transfer evidence separate.", locale: NFAppLocalization.preferredLocale, comment: "Mental-math progression status after all timing gates are met.")
        }

        return NFMentalMathProgressionStatus(
            stage: stage,
            recentSampleCount: recent.count,
            rollingAccuracy: accuracy,
            distinctStrategyCount: strategyCount,
            timedCorrectSampleCount: timedCorrectCount,
            repeatedMisconceptionCodes: repeatedCodes,
            timingEligible: stage == .automaticity || stage == .transfer,
            transferEligible: stage == .transfer,
            nextGateDescription: nextGate
        )
    }
}

enum NFMentalMathMetricKind: String, Codable, CaseIterable, Sendable {
    case independentAccuracy
    case retrievalFluency
    case strategyFlexibility
    case estimationError
    case unitHandling
    case retention
    case transfer
}

enum NFMentalMathMetricUnit: String, Codable, Sendable {
    case proportion
    case seconds
    case relativeError
}

struct NFMentalMathMetricObservation: Codable, Equatable, Sendable {
    let submittedAt: Date
    let credit: Double
    let evidenceClass: EvidenceClass
    let evidenceWeight: Double
    let wasSkipped: Bool
    let hintCount: Int
    let interruptionCount: Int
    let wasTimed: Bool
    let activeDurationSeconds: Double?
    let tags: Set<String>
    let strategyID: String?
    let strategyWasValid: Bool?
    let estimate: NFExactNumber?
    let exactReference: NFExactNumber?
    let unitRequired: Bool
    let unitWasCorrect: Bool?

    init(
        submittedAt: Date,
        credit: Double,
        evidenceClass: EvidenceClass = .practice,
        evidenceWeight: Double = 1,
        wasSkipped: Bool = false,
        hintCount: Int = 0,
        interruptionCount: Int = 0,
        wasTimed: Bool = false,
        activeDurationSeconds: Double? = nil,
        tags: Set<String> = [],
        strategyID: String? = nil,
        strategyWasValid: Bool? = nil,
        estimate: NFExactNumber? = nil,
        exactReference: NFExactNumber? = nil,
        unitRequired: Bool = false,
        unitWasCorrect: Bool? = nil
    ) {
        self.submittedAt = submittedAt
        self.credit = min(1, max(0, credit))
        self.evidenceClass = evidenceClass
        self.evidenceWeight = max(0, evidenceWeight)
        self.wasSkipped = wasSkipped
        self.hintCount = max(0, hintCount)
        self.interruptionCount = max(0, interruptionCount)
        self.wasTimed = wasTimed
        self.activeDurationSeconds = activeDurationSeconds
        self.tags = tags
        self.strategyID = strategyID
        self.strategyWasValid = strategyWasValid
        self.estimate = estimate
        self.exactReference = exactReference
        self.unitRequired = unitRequired
        self.unitWasCorrect = unitWasCorrect
    }
}

struct NFMentalMathMetricResult: Codable, Equatable, Sendable {
    let kind: NFMentalMathMetricKind
    let value: Double?
    let sampleCount: Int
    let minimumSampleCount: Int
    let unit: NFMentalMathMetricUnit

    var isAvailable: Bool { value != nil && sampleCount >= minimumSampleCount }
}

enum NFMentalMathMetricReducer {
    static func reduce(
        _ observations: [NFMentalMathMetricObservation]
    ) -> [NFMentalMathMetricKind: NFMentalMathMetricResult] {
        let eligible = observations.filter {
            !$0.wasSkipped && $0.evidenceWeight > 0 && $0.evidenceClass != .documentPractice
        }
        let independent = eligible.filter { $0.hintCount == 0 }
        let retrieval = independent.filter {
            $0.tags.contains("rapid-recall")
                && $0.credit == 1
                && $0.wasTimed
                && $0.interruptionCount == 0
                && ($0.activeDurationSeconds ?? 0) > 0
        }
        let strategy = independent.filter { $0.strategyID != nil && $0.strategyWasValid != nil }
        let estimates = independent.compactMap { observation -> Double? in
            guard let estimate = observation.estimate,
                  let reference = observation.exactReference,
                  reference.numerator != 0 else { return nil }
            return abs(estimate.doubleValue - reference.doubleValue) / abs(reference.doubleValue)
        }
        let unitEvidence = independent.filter { $0.unitRequired && $0.unitWasCorrect != nil }
        let retention = independent.filter { $0.evidenceClass == .retention }
        let transfer = independent.filter {
            $0.evidenceClass == .nearTransfer || $0.evidenceClass == .appliedTransfer
        }

        return [
            .independentAccuracy: meanResult(
                .independentAccuracy,
                values: independent.map(\.credit),
                minimum: 5,
                unit: .proportion
            ),
            .retrievalFluency: medianResult(
                .retrievalFluency,
                values: retrieval.compactMap(\.activeDurationSeconds),
                minimum: 5,
                unit: .seconds
            ),
            .strategyFlexibility: meanResult(
                .strategyFlexibility,
                values: strategy.map { $0.strategyWasValid == true ? 1 : 0 },
                minimum: 5,
                unit: .proportion
            ),
            .estimationError: medianResult(
                .estimationError,
                values: estimates,
                minimum: 3,
                unit: .relativeError
            ),
            .unitHandling: meanResult(
                .unitHandling,
                values: unitEvidence.map { $0.unitWasCorrect == true ? 1 : 0 },
                minimum: 3,
                unit: .proportion
            ),
            .retention: meanResult(
                .retention,
                values: retention.map(\.credit),
                minimum: 3,
                unit: .proportion
            ),
            .transfer: meanResult(
                .transfer,
                values: transfer.map(\.credit),
                minimum: 3,
                unit: .proportion
            )
        ]
    }

    private static func meanResult(
        _ kind: NFMentalMathMetricKind,
        values: [Double],
        minimum: Int,
        unit: NFMentalMathMetricUnit
    ) -> NFMentalMathMetricResult {
        let value = values.count >= minimum
            ? values.reduce(0, +) / Double(values.count)
            : nil
        return NFMentalMathMetricResult(
            kind: kind,
            value: value,
            sampleCount: values.count,
            minimumSampleCount: minimum,
            unit: unit
        )
    }

    private static func medianResult(
        _ kind: NFMentalMathMetricKind,
        values: [Double],
        minimum: Int,
        unit: NFMentalMathMetricUnit
    ) -> NFMentalMathMetricResult {
        let sorted = values.filter(\.isFinite).sorted()
        let value: Double? = if sorted.count < minimum {
            nil
        } else if sorted.count.isMultiple(of: 2) {
            (sorted[sorted.count / 2 - 1] + sorted[sorted.count / 2]) / 2
        } else {
            sorted[sorted.count / 2]
        }
        return NFMentalMathMetricResult(
            kind: kind,
            value: value,
            sampleCount: sorted.count,
            minimumSampleCount: minimum,
            unit: unit
        )
    }
}

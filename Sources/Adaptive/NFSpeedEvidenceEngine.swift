import Foundation

enum NFSpeedEvidenceStatus: String, Codable, Equatable, Sendable {
    case available
    case unavailableUntimed
    case insufficientTimedEvidence

    var title: String {
        switch self {
        case .available: NFAppLocalization.localized("Timed speed evidence", locale: NFAppLocalization.preferredLocale, comment: "Status title for a separate, descriptive timing-evidence channel.")
        case .unavailableUntimed: NFAppLocalization.localized("Speed unavailable · untimed", locale: NFAppLocalization.preferredLocale, comment: "Status title when the user chose untimed work and no speed estimate is shown.")
        case .insufficientTimedEvidence: NFAppLocalization.localized("Speed evidence is still sparse", locale: NFAppLocalization.preferredLocale, comment: "Status title when too few eligible timed attempts exist.")
        }
    }
}

struct NFSpeedEvidence: Codable, Equatable, Sendable {
    let status: NFSpeedEvidenceStatus
    let eligibleCount: Int
    let medianActiveSeconds: Double?
    let medianAbsoluteDeviationSeconds: Double?

    var intervalDescription: String? {
        guard let medianActiveSeconds, let medianAbsoluteDeviationSeconds else { return nil }
        let lower = max(0, medianActiveSeconds - medianAbsoluteDeviationSeconds)
        let upper = medianActiveSeconds + medianAbsoluteDeviationSeconds
        return NFAppLocalization.formattedSecondRange(lower, upper, style: .compact)
    }
}

/// Speed is a separate descriptive channel. It never changes correctness,
/// ability, plan completion, or improvement claims. Only fully correct,
/// explicitly timed, uninterrupted scored attempts are eligible.
enum NFSpeedEvidenceEngine {
    static let version = 2
    static let minimumEligibleAttempts = 5

    static func estimate(for lab: TrainingLab, attempts: [AttemptRecord]) -> NFSpeedEvidence {
        let labAttempts = attempts.filter {
            TrainingLab(rawValue: $0.gameID) == lab
                && !$0.wasSkipped
                && $0.evidenceWeight > 0
        }
        // The shipped legacy record lacks complete timing, relaunch, tool and band
        // provenance. Preserve its duration in history; a clean-speed claim is unavailable.
        let eligibleDurations: [Double] = []

        if eligibleDurations.isEmpty,
           !labAttempts.isEmpty,
           labAttempts.allSatisfy({ !$0.wasTimed }) {
            return NFSpeedEvidence(
                status: .unavailableUntimed,
                eligibleCount: 0,
                medianActiveSeconds: nil,
                medianAbsoluteDeviationSeconds: nil
            )
        }
        guard eligibleDurations.count >= minimumEligibleAttempts else {
            return NFSpeedEvidence(
                status: .insufficientTimedEvidence,
                eligibleCount: eligibleDurations.count,
                medianActiveSeconds: nil,
                medianAbsoluteDeviationSeconds: nil
            )
        }
        let medianValue = median(of: eligibleDurations)
        let deviations = eligibleDurations.map { abs($0 - medianValue) }.sorted()
        return NFSpeedEvidence(
            status: .available,
            eligibleCount: eligibleDurations.count,
            medianActiveSeconds: medianValue,
            medianAbsoluteDeviationSeconds: median(of: deviations)
        )
    }

    private static func median(of sortedValues: [Double]) -> Double {
        guard !sortedValues.isEmpty else { return 0 }
        let middle = sortedValues.count / 2
        if sortedValues.count.isMultiple(of: 2) {
            return (sortedValues[middle - 1] + sortedValues[middle]) / 2
        }
        return sortedValues[middle]
    }
}

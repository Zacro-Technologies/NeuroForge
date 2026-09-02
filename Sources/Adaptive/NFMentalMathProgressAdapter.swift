import Foundation

/// Converts durable attempts into the deliberately independent mental-math
/// evidence channels. This adapter never manufactures timing, strategy, unit,
/// estimate, retention, or transfer evidence when the attempt did not capture
/// it explicitly.
enum NFMentalMathProgressAdapter {
    static func observations(
        from attempts: [AttemptRecord]
    ) -> [NFMentalMathMetricObservation] {
        attempts.compactMap(observation(from:))
    }

    static func observation(
        from attempt: AttemptRecord
    ) -> NFMentalMathMetricObservation? {
        guard attempt.gameID == TrainingLab.mentalMath.rawValue else { return nil }

        let evidenceClass = EvidenceClass(rawValue: attempt.evidenceClassRaw) ?? .practice
        let template = attempt.templateID.lowercased()
        let response = decodedResponse(attempt.response)
        let estimate = estimateValue(from: response)
        let exactReference = estimate == nil
            ? nil
            : exactReferenceValue(from: attempt.correctAnswerText)
        let unitRequired = inferredUnitRequirement(for: attempt, response: response)
        let strategyID = strategyIdentifier(from: template)

        return NFMentalMathMetricObservation(
            submittedAt: attempt.submittedAt,
            credit: attempt.deterministicCredit,
            evidenceClass: evidenceClass,
            evidenceWeight: attempt.evidenceWeight,
            wasSkipped: attempt.wasSkipped,
            hintCount: attempt.hintCount,
            interruptionCount: attempt.interruptionCount,
            wasTimed: attempt.wasTimed,
            activeDurationSeconds: attempt.activeDurationSeconds > 0
                ? attempt.activeDurationSeconds
                : nil,
            tags: evidenceTags(from: template),
            strategyID: strategyID,
            strategyWasValid: strategyID == nil ? nil : attempt.deterministicCredit > 0,
            estimate: estimate,
            exactReference: exactReference,
            unitRequired: unitRequired,
            unitWasCorrect: unitRequired
                ? attempt.errorCode != "unit_missing" && attempt.errorCode != "unit_mismatch"
                : nil
        )
    }

    private static func decodedResponse(_ response: String) -> NFExerciseResponse? {
        guard let data = response.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(NFExerciseResponse.self, from: data)
    }

    private static func estimateValue(from response: NFExerciseResponse?) -> NFExactNumber? {
        guard case let .logicState(submission) = response,
              let text = submission.finalState[NFEstimateExactContract.estimateKey] else {
            return nil
        }
        return exactNumberPrefix(in: text)
    }

    private static func exactReferenceValue(from summary: String) -> NFExactNumber? {
        let marker = "\(NFEstimateExactContract.exactKey)="
        guard let markerRange = summary.range(of: marker) else { return nil }
        return exactNumberPrefix(in: String(summary[markerRange.upperBound...]))
    }

    private static func exactNumberPrefix(in text: String) -> NFExactNumber? {
        let normalized = text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "−", with: "-")
            .replacingOccurrences(of: ",", with: "")
        let allowed = CharacterSet(charactersIn: "+-0123456789./eE")
        let token = String(normalized.unicodeScalars.prefix { allowed.contains($0) })
        return NFExactNumber(parsing: token)
    }

    private static func inferredUnitRequirement(
        for attempt: AttemptRecord,
        response: NFExerciseResponse?
    ) -> Bool {
        if attempt.errorCode == "unit_missing" || attempt.errorCode == "unit_mismatch" {
            return true
        }
        guard case .numeric = response else { return false }
        let answer = attempt.correctAnswerText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let finalToken = answer.split(whereSeparator: { $0.isWhitespace }).last else { return false }
        return finalToken.contains(where: { $0.isLetter || $0 == "%" || $0 == "°" })
    }

    private static func evidenceTags(from template: String) -> Set<String> {
        var tags: Set<String> = []
        if template.contains("rapid-recall") { tags.insert("rapid-recall") }
        if template.contains("estimate-first") { tags.insert("estimate-first") }
        if template.contains("unit-conversion") || template.contains("dimensional") {
            tags.insert("unit-conversion")
        }
        return tags
    }

    private static func strategyIdentifier(from template: String) -> String? {
        let supportedFamilies = ["decompose", "strategy-duel", "estimate-first"]
        return supportedFamilies.first(where: template.contains)
    }
}

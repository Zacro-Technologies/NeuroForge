import Foundation

/// Learner-facing history never falls back to a Codable envelope or internal ID.
/// Labels come only from the exact saved item, never a regenerated current item.
enum NFResponsePresentation {
    static func decode(_ raw: String) -> NFExerciseResponse? {
        guard let data = raw.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(NFExerciseResponse.self, from: data)
    }

    static func text(_ raw: String, exercise: NFExercise? = nil, requiresTypedEnvelope: Bool = false) -> String {
        guard let response = decode(raw) else {
            return requiresTypedEnvelope
                ? localized("Saved answer format unavailable. The original response is retained for recovery.") : raw
        }
        return text(response, exercise: exercise)
    }

    static func text(_ response: NFExerciseResponse, exercise: NFExercise? = nil) -> String {
        if let exercise, let contract = NFTransferRelationshipContract.make(exercise: exercise),
           let text = contract.responseText(response) { return text }
        let unavailable = localized("Saved label unavailable in this older answer")
        switch response {
        case .numeric(let value):
            return [value.value, value.unit].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " ")
        case .shortText(let text): return text
        case .singleChoice(let id):
            guard case .singleChoice(let schema) = exercise?.interaction else { return unavailable }
            return schema.options.first { $0.id == id }?.text ?? unavailable
        case .multipleChoice(let ids):
            guard case .multipleChoice(let schema) = exercise?.interaction else { return unavailable }
            let selected = schema.options.filter { ids.contains($0.id) }.map(\.text)
            return (selected + (selected.count < ids.count ? [unavailable] : [])).joined(separator: "\n")
        case .orderedSteps(let ids):
            guard case .orderedSteps(let schema) = exercise?.interaction else { return unavailable }
            return ids.enumerated().map { index, id in
                "\(index + 1). \(schema.steps.first { $0.id == id }?.text ?? unavailable)"
            }.joined(separator: "\n")
        case .selfCheck(let value):
            return [value.reflection, ratingTitle(value.rating)].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: "\n")
        case .claimEvidence(let value):
            guard case .claimEvidence(let schema) = exercise?.interaction else { return unavailable }
            return value.pairs.map { pair in
                let claim = schema.claims.first { $0.id == pair.claimID }?.text ?? unavailable
                let evidence = pair.evidenceIDs.map { id in schema.evidence.first { $0.id == id }?.text ?? unavailable }
                return "\(claim)\n\(evidence.map { "• \($0)" }.joined(separator: "\n"))"
            }.joined(separator: "\n\n")
        case .logicState(let value):
            if let exercise, let graph = NFGraphConstructionContract.make(exercise: exercise) {
                return graph.responseDescription(value)
            }
            if let exercise,exercise.contractMetadata?.coordinateReasoning != nil,
               let contract=NFCoordinateReasoningContract.make(exercise:exercise) {
                return value.finalState.keys.sorted().map { "\(contract.responseLabel($0)): \(value.finalState[$0] ?? "")" }.joined(separator:"\n")
            }
            var fields = value.finalState.keys.sorted().map { "\(NFEstimateExactContract.localizedResponseLabel(for: $0)): \(value.finalState[$0] ?? "")" }
            if let id = value.violatedRuleID {
                if case .logicState(let schema) = exercise?.interaction {
                    fields.append(schema.ruleOptions.first { $0.id == id }?.text ?? unavailable)
                } else { fields.append(unavailable) }
            }
            return fields.joined(separator: "\n")
        }
    }

    static func expectedAnswer(for exercise: NFExercise) -> String? {
        guard !exercise.assessmentProtected, exercise.hasSupportedSpatialAssembly, exercise.hasSupportedCoordinateReasoning, exercise.hasSupportedGraphConstruction else { return nil }
        let response: NFExerciseResponse
        switch exercise.interaction {
        case .numeric(let schema): response = .numeric(.init(
            value: schema.answer.value.formatted(.number.grouping(.never).locale(Locale(identifier: exercise.localeIdentifier))),
            unit: schema.answer.canonicalUnit))
        case .singleChoice(let schema): response = .singleChoice(optionID: schema.correctOptionID)
        case .multipleChoice(let schema): response = .multipleChoice(optionIDs: schema.correctOptionIDs)
        case .orderedSteps(let schema): response = .orderedSteps(stepIDs: schema.correctOrder)
        case .shortText(let schema): response = .shortText(schema.expectedAnswer)
        case .selfCheck(let schema): return schema.referenceAnswer
        case .claimEvidence(let schema): response = .claimEvidence(.init(pairs: schema.correctPairs))
        case .logicState(let schema): response = .logicState(.init(finalState: schema.expectedFinalState, violatedRuleID: schema.expectedViolatedRuleID))
        }
        return text(response, exercise: exercise)
    }

    static func ratingTitle(_ rating: NFSelfCheckRating) -> String {
        switch rating {
        case .matched: localized("Your self-check: matched")
        case .partiallyMatched: localized("Your self-check: partly matched")
        case .notYet: localized("Your self-check: not yet")
        }
    }

    private static func localized(_ value: String) -> String {
        NFAppLocalization.localizedCatalogValue(value, locale: NFAppLocalization.preferredLocale)
    }
}

import Foundation

/// Canonical content identity for novelty checks. Runtime UUIDs, generator
/// seeds, answer-option order, locale metadata, and difficulty labels are
/// deliberately absent: none of them makes a repeated question new.
enum NFQuestionFingerprint {
    static let version = 1

    static func fingerprint(for exercise: NFExercise) -> String {
        String(NFStableDeterminism.hash64(canonicalContract(for: exercise)), radix: 16)
    }

    static func canonicalContract(for exercise: NFExercise) -> String {
        if exercise.lab == .retrieval,
           let target = exercise.tags.first(where: { $0.hasPrefix("knowledge-target.") }) {
            // Retrieval uniqueness is counted by its bundled question contract,
            // not by asking that contract as cloze, recognition, or free recall.
            return "fingerprint-v\(version)|retrieval|\(normalized(target))"
        }
        return [
            "fingerprint-v\(version)",
            normalized(exercise.templateID),
            normalized(exercise.prompt),
            normalized(exercise.contextText ?? ""),
            authoritativeContract(for: exercise.interaction),
            spatialStimulusContract(for: exercise.representations)
        ].joined(separator: "|")
    }

    static func normalized(_ value: String) -> String {
        value
            .folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .unicodeScalars
            .map { CharacterSet.whitespacesAndNewlines.contains($0) ? " " : String($0) }
            .joined()
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func authoritativeContract(for interaction: NFExerciseInteraction) -> String {
        switch interaction {
        case let .numeric(schema):
            return "numeric|\(canonicalJSON(schema.answer))"
        case let .singleChoice(schema):
            let byID = Dictionary(uniqueKeysWithValues: schema.options.map { ($0.id, normalized($0.text)) })
            return [
                "single",
                byID[schema.correctOptionID] ?? schema.correctOptionID,
                schema.options.map { normalized($0.text) }.sorted().joined(separator: "~")
            ].joined(separator: "|")
        case let .multipleChoice(schema):
            let byID = Dictionary(uniqueKeysWithValues: schema.options.map { ($0.id, normalized($0.text)) })
            let correct = schema.correctOptionIDs.map { byID[$0] ?? $0 }.sorted()
            return [
                "multiple",
                correct.joined(separator: "~"),
                schema.options.map { normalized($0.text) }.sorted().joined(separator: "~"),
                "\(schema.minimumSelections)-\(schema.maximumSelections)"
            ].joined(separator: "|")
        case let .orderedSteps(schema):
            let byID = Dictionary(uniqueKeysWithValues: schema.steps.map { ($0.id, normalized($0.text)) })
            return "ordered|" + schema.correctOrder.map { byID[$0] ?? $0 }.joined(separator: "~")
        case let .shortText(schema):
            return "short|\(normalized(schema.expectedAnswer))|\(canonicalJSON(schema.scoringRule))"
        case let .selfCheck(schema):
            return "self-check|\(normalized(schema.referenceAnswer))|\(schema.criteria.map(normalized).sorted().joined(separator: "~"))"
        case let .claimEvidence(schema):
            let claims = Dictionary(uniqueKeysWithValues: schema.claims.map { ($0.id, normalized($0.text)) })
            let evidence = Dictionary(uniqueKeysWithValues: schema.evidence.map { ($0.id, normalized($0.text)) })
            let pairs = schema.correctPairs.map { pair in
                let claim = claims[pair.claimID] ?? pair.claimID
                let support = pair.evidenceIDs.map { evidence[$0] ?? $0 }.sorted().joined(separator: "&")
                return "\(claim)->\(support)"
            }.sorted()
            return "claim-evidence|" + pairs.joined(separator: "~")
        case let .logicState(schema):
            let rules = schema.ruleOptions.map { normalized($0.text) }.sorted().joined(separator: "~")
            return [
                "logic-state",
                canonicalJSON(schema.initialState),
                canonicalJSON(schema.expectedFinalState),
                schema.expectedViolatedRuleID ?? "none",
                rules
            ].joined(separator: "|")
        }
    }

    /// Most stimulus values are already present in prompt/context. Spatial
    /// diagrams are the exception (notably cube nets), so their reviewed
    /// geometry participates in identity while visual display skins do not.
    private static func spatialStimulusContract(
        for representations: [NFExerciseRepresentation]
    ) -> String {
        representations.compactMap { representation -> String? in
            guard case let .spatial(metadata) = representation else { return nil }
            return canonicalJSON(metadata)
        }.joined(separator: "~")
    }

    private static func canonicalJSON<T: Encodable>(_ value: T) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        guard let data = try? encoder.encode(value),
              let string = String(data: data, encoding: .utf8) else {
            return "encoding-failed"
        }
        return string
    }
}

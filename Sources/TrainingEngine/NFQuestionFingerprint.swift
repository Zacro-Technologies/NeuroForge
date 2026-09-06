import Foundation

/// Canonical content identity for novelty checks. Runtime UUIDs, generator
/// seeds, answer-option order, locale metadata, and difficulty labels are
/// deliberately absent: none of them makes a repeated question new.
enum NFQuestionFingerprint {
    static let version = 2

    static func fingerprint(for exercise: NFExercise) -> String {
        String(NFStableDeterminism.hash64(canonicalContract(for: exercise)), radix: 16)
    }

    static func spatialStructureFingerprint(identity: String) -> String {
        String(NFStableDeterminism.hash64("fingerprint-v2|spatial-structure|" + identity), radix: 16)
    }
    static func coordinateTransformFingerprint(identity: String) -> String {
        String(NFStableDeterminism.hash64("fingerprint-v2|coordinate-transform|"+identity),radix:16)
    }
    static func solidSectionFingerprint(identity:String)->String {
        String(NFStableDeterminism.hash64("fingerprint-v2|solid-section|"+identity),radix:16)
    }
    static func netFoldingFingerprint(identity:String)->String {
        String(NFStableDeterminism.hash64("fingerprint-v2|net-folding|"+identity),radix:16)
    }
    static func coordinateReasoningFingerprint(identity:String)->String {
        String(NFStableDeterminism.hash64("fingerprint-v2|coordinate-reasoning|"+identity),radix:16)
    }
    /// Each typed validation owns a separate frame. A background generator
    /// must not reserve all large contract temporaries at once, including those
    /// for absent contracts. Preserve original first-supported-contract order.
    @inline(never)
    static func canonicalContract(for exercise: NFExercise) -> String {
        if let value = spatialAssemblyContract(for: exercise) { return value }
        if let value = coordinateReasoningContract(for: exercise) { return value }
        if let value = netFoldingContract(for: exercise) { return value }
        if let value = solidSectionContract(for: exercise) { return value }
        if let value = coordinateTransformContract(for: exercise) { return value }
        if let value = spatialStructureContract(for: exercise) { return value }
        return generalContract(for: exercise)
    }

    static func spatialAssemblyFingerprint(identity:String)->String {
        String(NFStableDeterminism.hash64("fingerprint-v2|spatial-assembly|"+identity),radix:16)
    }
    @inline(never)
    private static func spatialAssemblyContract(for exercise:NFExercise)->String? {
        guard exercise.contractMetadata?.spatialAssembly != nil,let c=NFSpatialAssemblyContract.make(exercise:exercise) else{return nil}
        return "fingerprint-v2|spatial-assembly|"+c.task.identity
    }
    @inline(never)
    private static func coordinateReasoningContract(for exercise: NFExercise) -> String? {
        guard exercise.contractMetadata?.coordinateReasoning != nil,
              let contract = NFCoordinateReasoningContract.make(exercise: exercise) else { return nil }
        return "fingerprint-v2|coordinate-reasoning|" + contract.task.identity
    }

    @inline(never)
    private static func netFoldingContract(for exercise: NFExercise) -> String? {
        guard exercise.contractMetadata?.netFolding != nil,
              let contract = NFNetFoldingContract.make(exercise: exercise) else { return nil }
        return "fingerprint-v2|net-folding|" + contract.task.identity
    }

    @inline(never)
    private static func solidSectionContract(for exercise: NFExercise) -> String? {
        guard exercise.contractMetadata?.solidSection != nil,
              let contract = NFSolidSectionContract.make(exercise: exercise) else { return nil }
        return "fingerprint-v2|solid-section|" + contract.task.identity
    }

    @inline(never)
    private static func coordinateTransformContract(for exercise: NFExercise) -> String? {
        guard exercise.contractMetadata?.coordinateTransform != nil,
              let contract = NFCoordinateTransformContract.make(exercise: exercise) else { return nil }
        return "fingerprint-v2|coordinate-transform|" + contract.task.semanticIdentity
    }

    @inline(never)
    private static func spatialStructureContract(for exercise: NFExercise) -> String? {
        guard exercise.contractMetadata?.spatialStructure != nil,
              let contract = NFSpatialStructureContract.make(exercise: exercise) else { return nil }
        return "fingerprint-v2|spatial-structure|" + contract.structure.identity
    }

    @inline(never)
    private static func generalContract(for exercise: NFExercise) -> String {
        if exercise.lab == .retrieval,
           exercise.contractMetadata?.retrievalAuthorityPolicyVersion == 1 || exercise.generatorVersion == 9 {
            if exercise.tags.contains("learning-method-only"), NFContentCorrectionPolicy.knownWorkflowOnly(exercise) {
                return "fingerprint-v2|learning-method|" + (exercise.templateID.components(separatedBy: ".v4.").last ?? exercise.templateID)
            }
        }
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
                "\(schema.minimumSelections)-\(schema.maximumSelections)",
                canonicalJSON(schema.acceptedAlternativeSets)
            ].joined(separator: "|")
        case let .orderedSteps(schema):
            let byID = Dictionary(uniqueKeysWithValues: schema.steps.map { ($0.id, normalized($0.text)) })
            return "ordered|" + schema.correctOrder.map { byID[$0] ?? $0 }.joined(separator: "~") + "|" + canonicalJSON(schema.dependencies)
        case let .shortText(schema):
            return "short|\(normalized(schema.expectedAnswer))|\(canonicalJSON(schema.scoringRule))|\(canonicalJSON(schema.authority))"
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
            return "claim-evidence|" + pairs.joined(separator: "~") + "|" + canonicalJSON(schema.supportContracts)
        case let .logicState(schema):
            let rules = schema.ruleOptions.map { normalized($0.text) }.sorted().joined(separator: "~")
            return [
                "logic-state",
                canonicalJSON(schema.initialState),
                canonicalJSON(schema.expectedFinalState),
                canonicalJSON(schema.acceptedEquivalentStates),
                canonicalJSON(schema.fieldDomains),
                canonicalJSON(schema.plausibilityPolicy),
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

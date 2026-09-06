import Foundation

/// Explicit successor authorities for the audited retrieval families. This
/// adapter does not claim a general natural-language or mathematics verifier.
enum NFRetrievalResponseAuthority {
    static func authority(for fact: NFExerciseGroundingFact, policyVersion: Int? = nil) -> NFShortTextAuthority? {
        if policyVersion == 1, let successor = successorAuthority(for: fact) { return successor }
        let answers = [fact.expectedAnswer] + fact.acceptedAlternatives
        if fact.id.hasSuffix(".integral-derivative-link") {
            return .symbolic(NFSymbolicAnswerContract(acceptedExpressions: ["F(b)-F(a)"],
                variables: ["a", "b"], functions: ["F", "f"]))
        }
        if fact.id.hasSuffix(".square-derivative") || fact.id.contains(".monomial-derivative-") {
            return .symbolic(NFSymbolicAnswerContract(acceptedExpressions: [fact.id.hasSuffix(".square-derivative") ? "2*x" : fact.expectedAnswer], variables: ["x"]))
        }
        if fact.id.hasSuffix(".arithmetic-mean") {
            return .reviewedProse(acceptedAnswers: answers + [
                "Sum all observations then divide by their count",
                "Sum observations / number of observations",
                "Add all values and divide by how many values there are; this works because each observation contributes once",
                "Add all values and divide by how many values there are",
                "Add up the observations and divide the total by the number of observations",
                "Divide the sum of all values by the number of values",
                "Total divided by count", "Sum divided by count"
            ], rejectedAssertions: ["divide the count by the", "count divided by sum", "count divided by the sum",
                "do not divide by", "never divide by", "divide the number of observations by the sum"])
        }
        if let number = NFExactNumber(parsing: fact.expectedAnswer) {
            // Binary numeral reconstruction assesses a numeral, not its decimal value.
            if fact.id.contains("binary") { return .identifier(acceptedAnswers: answers) }
            return .exactQuantity(NFNumericResponseSchema(answer: NFNumericAnswer(
                authoritativeValue: number, authoritativeTolerance: .absolute(try! NFExactNumber(numerator: 0)),
                legacyTolerance: .absolute(0), canonicalUnit: nil, unitRequired: false),
                placeholder: "Answer", permitsScientificNotation: true, permitsThousandsSeparators: false))
        }
        // Trusted computed targets with an unambiguous scalar followed by a
        // fixed unit gain rational/decimal equivalence. Other domains retain
        // their existing explicit aliases pending their own reviewed module.
        if fact.id.hasPrefix("nf.retrieval."), let split = fact.expectedAnswer.firstIndex(of: " "),
           let number = NFExactNumber(parsing: String(fact.expectedAnswer[..<split])) {
            let unit = String(fact.expectedAnswer[fact.expectedAnswer.index(after: split)...])
            let knownUnits: Set<String> = ["m", "s", "kg", "g", "N", "J", "W", "V", "A", "ohms", "Hz", "Pa", "mol", "m/s", "m/s^2", "m^2", "m^3", "%", "litres", "L"]
            if knownUnits.contains(unit) {
                return .exactQuantity(NFNumericResponseSchema(answer: NFNumericAnswer(
                    authoritativeValue: number, authoritativeTolerance: .absolute(try! NFExactNumber(numerator: 0)),
                    legacyTolerance: .absolute(0), canonicalUnit: unit, acceptedUnits: [], unitRequired: false),
                    placeholder: "Answer in \(unit)", permitsScientificNotation: true, permitsThousandsSeparators: false))
            }
        }
        if fact.expectedAnswer.split(separator: " ").count >= 6 {
            return .reviewedProse(acceptedAnswers: answers, rejectedAssertions: [])
        }
        return nil
    }

    static func checklist(for fact: NFExerciseGroundingFact) -> [String] {
        if fact.id.hasSuffix(".median") || fact.id.contains("median-definition") {
            return ["Order the observations.", "For an odd count, identify the middle observation.",
                "For an even count, average the two middle observations."]
        }
        if fact.id.hasSuffix(".arithmetic-mean") {
            return ["Add every relevant observation once.", "Divide that sum by the number of observations."]
        }
        return ["Recall the answer to: \(fact.statement)", "Compare the relationship and its conditions with: \(fact.expectedAnswer)"]
    }
}

/// A numeral task accepts binary digits only. Leading zeros do not change an
/// unsigned value when the prompt specifies no fixed width; decimal arithmetic
/// and scientific notation are outside this contract rather than alternate keys.
struct NFUnsignedBinaryNumeralContract: Codable, Equatable, Sendable {
    let expectedDigits: String
    var policyVersion: Int = 1
    var isSupported: Bool {
        policyVersion == 1 && !expectedDigits.isEmpty && expectedDigits.utf8.count <= 64
            && expectedDigits.allSatisfy { $0 == "0" || $0 == "1" }
            && (expectedDigits == "0" || expectedDigits.first == "1")
    }
    func canonical(_ response: String) -> String? {
        let text = response.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isSupported, !text.isEmpty, text.utf8.count <= 280,
              text.allSatisfy({ $0 == "0" || $0 == "1" }) else { return nil }
        let digits = text.drop(while: { $0 == "0" })
        return digits.isEmpty ? "0" : String(digits)
    }
}

extension NFRetrievalResponseAuthority {
    /// Exact bundled content binding, not a suffix-based authority grant for
    /// arbitrary imported prose. Existing document facts retain their scope.
    static func bundledTarget(for fact: NFExerciseGroundingFact) -> NFRetrievalKnowledgeTarget? {
        guard let target = NFBundledRetrievalCatalog.target(id: fact.id),
              target.prompt == fact.statement, target.answer == fact.expectedAnswer,
              target.acceptedAnswers == fact.acceptedAlternatives else { return nil }
        return target
    }
    static func successorAuthority(for fact: NFExerciseGroundingFact) -> NFShortTextAuthority? {
        guard let target = bundledTarget(for: fact) else { return nil }
        if target.id.hasSuffix(".eigenvector-definition") {
            return .symbolic(NFMatrixEigenvectorEquationAuthority.contract)
        }
        if target.id.contains(".binary-to-decimal-"), let number = NFExactNumber(parsing: target.answer) {
            return .exactQuantity(NFNumericResponseSchema(answer: NFNumericAnswer(
                authoritativeValue: number, authoritativeTolerance: .absolute(try! NFExactNumber(numerator: 0)),
                legacyTolerance: .absolute(0), canonicalUnit: nil, unitRequired: false),
                placeholder: "Answer", permitsScientificNotation: true, permitsThousandsSeparators: false))
        }
        if target.id.contains(".decimal-to-binary-") {
            return .unsignedBinaryNumeral(.init(expectedDigits: target.answer))
        }
        return nil
    }
    static func target(in exercise: NFExercise) -> NFRetrievalKnowledgeTarget? {
        guard exercise.lab == .retrieval, exercise.provenance.generatorID == "nf.exercise.fallback",
              exercise.generatorVersion == exercise.provenance.generatorVersion,
              let tag = exercise.tags.first(where: { $0.hasPrefix("knowledge-target.") }),
              let target = NFBundledRetrievalCatalog.target(id: String(tag.dropFirst("knowledge-target.".count))),
              exercise.prompt.contains(target.prompt),
              case let .shortText(schema) = exercise.interaction,
              schema.expectedAnswer == target.answer,
              case let .normalizedExact(aliases) = schema.scoringRule,
              aliases == [target.answer] + target.acceptedAnswers else { return nil }
        return target
    }
    static func legacySuccessorTarget(in exercise: NFExercise) -> NFRetrievalKnowledgeTarget? {
        guard [1, 2].contains(exercise.schemaVersion), (1...4).contains(exercise.generatorVersion),
              exercise.contractMetadata?.retrievalAuthorityPolicyVersion == nil,
              let target = target(in: exercise),
              target.id.hasSuffix(".eigenvector-definition") || target.id.contains(".binary-to-decimal-") || target.id.contains(".decimal-to-binary-") else { return nil }
        return target
    }
    /// Named compatibility dispatch for the exactly identified defective old
    /// contract. The retained exercise bytes and any committed grade stay intact.
    /// This is deliberately narrower than changing all normalized text answers.
    static func auditedInteraction(for exercise: NFExercise) -> NFExerciseInteraction {
        guard let target = legacySuccessorTarget(in: exercise), case var .shortText(schema) = exercise.interaction else {
            return exercise.interaction
        }
        schema.authority = successorAuthority(for: .init(id: target.id, statement: target.prompt, expectedAnswer: target.answer,
            acceptedAlternatives: target.acceptedAnswers, citationIDs: []))
        return .shortText(schema)
    }
    static func requiresStrictDispatch(_ authority: NFShortTextAuthority) -> Bool {
        switch authority {
        case let .symbolic(contract): return contract.policyVersion == 2
        case .unsignedBinaryNumeral: return true
        default: return false
        }
    }
}

extension NFExercise {
    var hasSupportedRetrievalAuthorityRecipe: Bool {
        if contractMetadata?.retrievalAsset != nil { return NFRetrievalAssetContract.make(exercise: self) != nil }
        guard let policy = contractMetadata?.retrievalAuthorityPolicyVersion else { return schemaVersion != 6 && generatorVersion != 9 }
        guard policy == 1, schemaVersion == 6, generatorVersion == 9,
              lab == .retrieval, [.practice, .documentPractice].contains(purpose), !assessmentProtected,
              provenance.generatorID == "nf.exercise.fallback", provenance.generatorVersion == 9,
              contractMetadata?.generatorVersion == 9 else { return false }
        if tags.contains("learning-method-only") {
            return !tags.contains(where: { $0.hasPrefix("knowledge-target.") })
                && contractMetadata?.objectiveID == "learning-method." + (templateID.components(separatedBy: ".v4.").last ?? "")
                && NFContentCorrectionPolicy.knownWorkflowOnly(self)
        }
        guard tags.filter({ $0.hasPrefix("knowledge-target.") }).count == 1 else { return false }
        if case let .shortText(schema) = interaction,
           let tag = tags.first(where: { $0.hasPrefix("knowledge-target.") }),
           NFBundledRetrievalCatalog.target(id: String(tag.dropFirst("knowledge-target.".count))) != nil {
            guard let target = NFRetrievalResponseAuthority.target(in: self) else { return false }
            let fact = NFExerciseGroundingFact(id: target.id, statement: target.prompt, expectedAnswer: target.answer,
                acceptedAlternatives: target.acceptedAnswers, citationIDs: [])
            if let required = NFRetrievalResponseAuthority.successorAuthority(for: fact) { return schema.authority == required }
        }
        return true
    }
}

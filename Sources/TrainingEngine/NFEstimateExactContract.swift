import Foundation

/// Reuses the existing typed logic-state interaction to preserve an ordered,
/// separately addressable estimate/plausibility/exact response without adding a
/// ninth interaction type.
struct NFEstimateExactContract: Codable, Equatable, Sendable {
    static let contractMarker = "estimate-then-exact.v1"
    static let estimateKey = "1 · estimate"
    static let plausibilityKey = "2 · plausibility"
    static let exactKey = "3 · exact"

    let estimate: String
    let acceptedEstimateAlternatives: [String]
    let plausibility: String
    let acceptedPlausibilityAlternatives: [String]
    let exact: String
    let acceptedExactAlternatives: [String]

    var responseSchema: NFLogicStateResponseSchema {
        let estimateValues = [estimate] + acceptedEstimateAlternatives
        let plausibilityValues = [plausibility] + acceptedPlausibilityAlternatives
        let exactValues = [exact] + acceptedExactAlternatives
        let equivalentStates = estimateValues.flatMap { estimateValue in
            plausibilityValues.flatMap { plausibilityValue in
                exactValues.map { exactValue in
                    [
                        Self.estimateKey: estimateValue,
                        Self.plausibilityKey: plausibilityValue,
                        Self.exactKey: exactValue
                    ]
                }
            }
        }.filter {
            $0 != [
                Self.estimateKey: estimate,
                Self.plausibilityKey: plausibility,
                Self.exactKey: exact
            ]
        }
        return NFLogicStateResponseSchema(
            initialState: ["contract": Self.contractMarker, "responseOrder": "estimate,plausibility,exact"],
            expectedFinalState: [
                Self.estimateKey: estimate,
                Self.plausibilityKey: plausibility,
                Self.exactKey: exact
            ],
            acceptedEquivalentStates: equivalentStates,
            ruleOptions: [],
            expectedViolatedRuleID: nil,
            fieldDomains: NFStateValueAuthority.exactNumber(estimate) != nil && NFStateValueAuthority.exactNumber(exact) != nil
                ? [Self.estimateKey: .exactNumber, Self.exactKey: .exactNumber, Self.plausibilityKey: .reviewedLabel] : nil,
            plausibilityPolicy: NFStateValueAuthority.exactNumber(estimate) != nil && NFStateValueAuthority.exactNumber(exact) != nil
                ? NFEstimatePlausibilityPolicy(estimateKey: Self.estimateKey, exactKey: Self.exactKey,
                    judgmentKey: Self.plausibilityKey, plausibleLabels: [plausibility] + acceptedPlausibilityAlternatives,
                    implausibleLabels: ["not plausible", "implausible", "no"],
                    relativeTolerance: try! NFExactNumber(numerator: 1, denominator: 2)) : nil
        )
    }

    static func isComposite(_ schema: NFLogicStateResponseSchema) -> Bool {
        schema.initialState["contract"] == contractMarker
            && Set(schema.expectedFinalState.keys) == Set([estimateKey, plausibilityKey, exactKey])
    }

    static func orderedResponseKeys(for schema: NFLogicStateResponseSchema) -> [String] {
        isComposite(schema)
            ? [estimateKey, plausibilityKey, exactKey]
            : schema.expectedFinalState.keys.sorted()
    }

    /// Returns presentation copy without changing the stable dictionary key used
    /// by scoring, persistence, and progress evidence.
    static func localizedResponseLabel(
        for key: String,
        locale: Locale = NFAppLocalization.preferredLocale
    ) -> String {
        switch key {
        case estimateKey:
            NFAppLocalization.localized("1 · Estimate", locale: locale, comment: "Label for the first field in an estimate-then-exact response.")
        case plausibilityKey:
            NFAppLocalization.localized("2 · Plausibility", locale: locale, comment: "Label for the second field in an estimate-then-exact response.")
        case exactKey:
            NFAppLocalization.localized("3 · Exact result", locale: locale, comment: "Label for the third field in an estimate-then-exact response.")
        default:
            key
        }
    }
}

/// The judgment concerns the learner's own pair, independently of whether
/// either value matches its numeric key. Relative error at most50% is the
/// explicitly versioned instructional scale check for this narrow family.
struct NFEstimatePlausibilityPolicy: Codable, Equatable, Sendable {
    let estimateKey: String
    let exactKey: String
    let judgmentKey: String
    let plausibleLabels: [String]
    let implausibleLabels: [String]
    let relativeTolerance: NFExactNumber
    var version: Int = 1

    func accepts(_ state: [String: String]) -> Bool {
        guard let estimate = NFStateValueAuthority.exactNumber(state[estimateKey] ?? ""),
              let exact = NFStateValueAuthority.exactNumber(state[exactKey] ?? "") else { return false }
        let plausible = estimate.isWithinRelativeTolerance(of: exact, tolerance: relativeTolerance)
        let labels = plausible ? plausibleLabels : implausibleLabels
        let judgment = (state[judgmentKey] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return labels.contains { $0.lowercased() == judgment }
    }
}


/// A presentation/work record, separate from the authoritative response. Nil on
/// an old checkpoint means its original single-stage flow remains unchanged.
struct NFMathWorkDraft: Codable, Equatable, Sendable {
    var schemaVersion = 1
    let policyVersion: String
    let exerciseDigest: String
    let kindRaw: String
    let hintLadder: [String]
    var lockedEstimate: String? = nil
    var estimateLockedAtActiveSeconds: Double? = nil
    var workingExpanded = false
    var workingValues: [String]

    var kind: NFMathWorkPolicy.Kind? { NFMathWorkPolicy.Kind(rawValue: kindRaw) }
    var awaitsEstimate: Bool { kind == .estimateFirst && lockedEstimate == nil }
    var requiresCompensationSupport: Bool {
        kind == .compensation && (workingExpanded || workingValues.contains { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })
    }
    var isSupported: Bool {
        schemaVersion == 1 && policyVersion == NFMathWorkPolicy.version && kind != nil
            && exerciseDigest.count == 64 && exerciseDigest.allSatisfy(\.isHexDigit)
            && (kind != .compensation || hintLadder.count == 3)
            && hintLadder.count <= 8 && hintLadder.allSatisfy { !$0.isEmpty && $0.count <= 2_000 }
            && workingValues.count <= 20 && workingValues.allSatisfy { $0.count <= 500 }
            && (lockedEstimate?.count ?? 0) <= 500
            && ((lockedEstimate == nil && estimateLockedAtActiveSeconds == nil)
                || (kind == .estimateFirst && lockedEstimate.flatMap(NFStateValueAuthority.exactNumber) != nil
                    && estimateLockedAtActiveSeconds.map(NFSessionDurationPolicy.isValid) == true))
    }
    func isCompatible(with exercise: NFExercise, response: NFExerciseResponse? = nil) -> Bool {
        guard isSupported, !exercise.assessmentProtected,
              exerciseDigest == (try? NFLocalItemCheckpoint.digest(exercise)),
              kind == NFMathWorkPolicy.kind(for: exercise) else { return false }
        let count = NFMathWorkPolicy.workingContract(for: exercise)?.operations.count ?? 0
        guard workingValues.count == count else { return false }
        guard kind == .estimateFirst, let response else { return true }
        guard case .logicState(let state) = response else { return false }
        if let lockedEstimate { return state.finalState[NFEstimateExactContract.estimateKey] == lockedEstimate }
        return [NFEstimateExactContract.exactKey, NFEstimateExactContract.plausibilityKey].allSatisfy {
            (state.finalState[$0] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }
    func lockingEstimate(_ source: String, activeSeconds: Double) -> Self? {
        guard awaitsEstimate, isSupported, source.count <= 500,
              NFStateValueAuthority.exactNumber(source) != nil,
              NFSessionDurationPolicy.isValid(activeSeconds) else { return nil }
        var next = self; next.lockedEstimate = source; next.estimateLockedAtActiveSeconds = activeSeconds
        return next
    }
    static func initial(for exercise: NFExercise) -> Self? {
        guard !exercise.assessmentProtected, let kind = NFMathWorkPolicy.kind(for: exercise),
              let digest = try? NFLocalItemCheckpoint.digest(exercise) else { return nil }
        let count = NFMathWorkPolicy.workingContract(for: exercise)?.operations.count ?? 0
        return .init(policyVersion: NFMathWorkPolicy.version, exerciseDigest: digest, kindRaw: kind.rawValue,
            hintLadder: NFMathWorkPolicy.hints(for: exercise), workingValues: Array(repeating: "", count: count))
    }
}

enum NFMathWorkPolicy {
    static let version = "MentalMathWorkV1"
    enum Kind: String, Codable, Sendable { case estimateFirst, calculationChain, compensation }

    static func kind(for exercise: NFExercise) -> Kind? {
        guard exercise.lab == .mentalMath, !exercise.assessmentProtected else { return nil }
        if case let .logicState(schema) = exercise.interaction, NFEstimateExactContract.isComposite(schema),
           schema.fieldDomains?[NFEstimateExactContract.estimateKey] == .exactNumber,
           schema.fieldDomains?[NFEstimateExactContract.exactKey] == .exactNumber { return .estimateFirst }
        guard workingContract(for: exercise) != nil else { return nil }
        return exercise.tags.contains("calculation-chain") ? .calculationChain : .compensation
    }

    /// Accept an explicit exact chain, or the bounded compensation equation
    /// already retained by this named mechanic. Verify the reconstructed result
    /// against the exact numeric key before offering any working or explanation.
    /// No prose prompt parsing, guessed factors or new scoring authority.
    static func workingContract(for exercise: NFExercise) -> NFCalculationChainContract? {
        guard exercise.lab == .mentalMath, !exercise.assessmentProtected,
              case let .numeric(schema) = exercise.interaction else { return nil }
        let candidate: NFCalculationChainContract?
        if exercise.tags.contains("calculation-chain") {
            let contracts = exercise.representations.compactMap { value -> NFCalculationChainContract? in
                guard case let .logicState(metadata) = value else { return nil }
                return .init(representation: metadata)
            }
            guard contracts.count == 1 else { return nil }; candidate = contracts[0]
        } else if exercise.tags.contains("compensation") {
            let equations = exercise.representations.compactMap { value -> String? in
                guard case let .equation(latex, _) = value else { return nil }; return latex
            }
            guard equations.count == 1 else { return nil }
            let factors = equations[0].components(separatedBy: "\\times").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            guard factors.count == 2, let left = NFExactNumber(parsing: factors[0]),
                  let right = Int64(factors[1]), left.denominator == 1, (1...999).contains(left.numerator),
                  [9, 11, 19, 21].contains(right) else { return nil }
            let nearby = right == 9 || right == 19 ? right + 1 : right - 1
            guard let multiplier = try? NFExactNumber(numerator: nearby) else { return nil }
            candidate = .init(initialValue: left, operations: [.multiply(multiplier), right < nearby ? .subtract(left) : .add(left)])
        } else { return nil }
        guard let candidate, (1...20).contains(candidate.operations.count),
              let replay = NFCalculationChainEngine.replay(candidate),
              replay.last?.output == schema.answer.authoritativeValue else { return nil }
        return candidate
    }

    static func hints(for exercise: NFExercise) -> [String] {
        guard exercise.tags.contains("compensation"), let contract = workingContract(for: exercise),
              let first = NFCalculationChainEngine.replay(contract)?.first,
              case let .multiply(nearby) = contract.operations[0] else {
            return exercise.feedback.hintLadder
        }
        let locale = Locale(identifier: exercise.localeIdentifier)
        let factor = contract.initialValue.canonicalString
        let operation: String
        switch contract.operations[1] {
        case .subtract: operation = NFAppLocalization.localized("subtract", locale: locale, comment: "Signed compensation operation.")
        case .add: operation = NFAppLocalization.localized("add", locale: locale, comment: "Signed compensation operation.")
        default: return exercise.feedback.hintLadder
        }
        return [
            NFAppLocalization.localized("Use a nearby multiple of ten.", locale: locale, comment: "First compensation hint, without a result."),
            NFAppLocalization.localized("Calculate \(factor) × \(nearby.canonicalString), then \(operation) one group of \(factor).", locale: locale, comment: "Compensation strategy hint before the worked intermediate value."),
            NFAppLocalization.localized("\(factor) × \(nearby.canonicalString) = \(first.output.canonicalString). Finish the one-group adjustment.", locale: locale, comment: "Requested compensation hint exposing only the intermediate result.")
        ]
    }

    /// Removes only the exact legacy ordering sentence from the known estimate
    /// mechanic's display. Retained source/context bytes stay unchanged; other
    /// context (including arbitrary user-authored givens) is preserved verbatim.
    static func presentationContext(exercise: NFExercise, draft: NFMathWorkDraft?) -> String? {
        guard let context = exercise.independentContextText,
              draft?.kind == .estimateFirst, exercise.tags.contains("estimate-first") else { return exercise.independentContextText }
        let legacyOrder = NFAppLocalization.localized(" Estimate, plausibility judgment, and exact response are captured as separate fields in that order.", locale: Locale(identifier: exercise.localeIdentifier), comment: "Legacy estimate-family context ordering sentence.")
        guard context.hasSuffix(legacyOrder) else { return context }
        let remaining = String(context.dropLast(legacyOrder.count))
        return remaining.isEmpty ? nil : remaining
    }
    static func responseKeys(schema: NFLogicStateResponseSchema, draft: NFMathWorkDraft?) -> [String] {
        guard draft?.kind == .estimateFirst else { return NFEstimateExactContract.orderedResponseKeys(for: schema) }
        return draft?.awaitsEstimate == true ? [NFEstimateExactContract.estimateKey]
            : [NFEstimateExactContract.exactKey, NFEstimateExactContract.plausibilityKey]
    }
    static func recoveryText(_ draft: NFMathWorkDraft?, exercise: NFExercise) -> String? {
        guard let draft, draft.isCompatible(with: exercise), !exercise.assessmentProtected else { return nil }
        let lines = draft.workingValues.enumerated().compactMap { index, value -> String? in
            guard !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
            return NFAppLocalization.localized("Your value after step \(index + 1): \(value)", locale: NFAppLocalization.preferredLocale, comment: "Copyable original optional calculation work.")
        }
        return lines.isEmpty ? nil : lines.joined(separator: "\n")
    }
    static func responseLabel(for key: String, draft: NFMathWorkDraft?) -> String {
        guard draft?.kind == .estimateFirst else { return NFEstimateExactContract.localizedResponseLabel(for: key) }
        switch key {
        case NFEstimateExactContract.estimateKey: return NFAppLocalization.localized("Estimate", locale: NFAppLocalization.preferredLocale, comment: "First-stage estimate label.")
        case NFEstimateExactContract.exactKey: return NFAppLocalization.localized("Exact result", locale: NFAppLocalization.preferredLocale, comment: "Second-stage exact result label.")
        case NFEstimateExactContract.plausibilityKey: return NFAppLocalization.localized("Does your result fit your saved estimate?", locale: NFAppLocalization.preferredLocale, comment: "Judgment of the learner's own numeric pair.")
        default: return key
        }
    }
    static func finalState(_ state: [String: String], draft: NFMathWorkDraft?) -> [String: String] {
        guard let estimate = draft?.lockedEstimate, draft?.kind == .estimateFirst else { return state }
        var copy = state; copy[NFEstimateExactContract.estimateKey] = estimate; return copy
    }
    static func diagnosis(exercise: NFExercise, draft: NFMathWorkDraft?, submittedFinalValue: String) -> NFCalculationChainDiagnostic? {
        guard let contract = workingContract(for: exercise), draft?.isCompatible(with: exercise) == true else { return nil }
        return NFCalculationChainEngine.diagnose(contract: contract, submittedFinalValue: submittedFinalValue,
            learnerCheckpoints: draft?.workingValues ?? [])
    }
}

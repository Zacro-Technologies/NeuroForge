import Foundation

enum NFCalculationChainOperation: Codable, Equatable, Sendable {
    case add(NFExactNumber)
    case subtract(NFExactNumber)
    case multiply(NFExactNumber)
    case divide(NFExactNumber)

    var instruction: String {
        switch self {
        case let .add(value): NFAppLocalization.localized("Add \(value.canonicalString)", locale: NFAppLocalization.preferredLocale, comment: "Step in a mental calculation chain; the placeholder is an exact number.")
        case let .subtract(value): NFAppLocalization.localized("Subtract \(value.canonicalString)", locale: NFAppLocalization.preferredLocale, comment: "Step in a mental calculation chain; the placeholder is an exact number.")
        case let .multiply(value): NFAppLocalization.localized("Multiply by \(value.canonicalString)", locale: NFAppLocalization.preferredLocale, comment: "Step in a mental calculation chain; the placeholder is an exact number.")
        case let .divide(value): NFAppLocalization.localized("Divide by \(value.canonicalString)", locale: NFAppLocalization.preferredLocale, comment: "Step in a mental calculation chain; the placeholder is an exact number.")
        }
    }

    fileprivate var encodedMutation: String {
        switch self {
        case let .add(value): "add:\(value.canonicalString)"
        case let .subtract(value): "subtract:\(value.canonicalString)"
        case let .multiply(value): "multiply:\(value.canonicalString)"
        case let .divide(value): "divide:\(value.canonicalString)"
        }
    }

    fileprivate static func decodeMutation(_ source: String) -> Self? {
        guard let separator = source.firstIndex(of: ":"),
              let value = NFExactNumber(parsing: String(source[source.index(after: separator)...])) else {
            return nil
        }
        switch source[..<separator] {
        case "add": return .add(value)
        case "subtract": return .subtract(value)
        case "multiply": return .multiply(value)
        case "divide": return .divide(value)
        default: return nil
        }
    }

    fileprivate func applying(to input: NFExactNumber) -> NFExactNumber? {
        switch self {
        case let .add(value):
            return Self.make(
                Int128(input.numerator) * Int128(value.denominator)
                    + Int128(value.numerator) * Int128(input.denominator),
                Int128(input.denominator) * Int128(value.denominator)
            )
        case let .subtract(value):
            return Self.make(
                Int128(input.numerator) * Int128(value.denominator)
                    - Int128(value.numerator) * Int128(input.denominator),
                Int128(input.denominator) * Int128(value.denominator)
            )
        case let .multiply(value):
            return Self.make(
                Int128(input.numerator) * Int128(value.numerator),
                Int128(input.denominator) * Int128(value.denominator)
            )
        case let .divide(value):
            guard value.numerator != 0 else { return nil }
            return Self.make(
                Int128(input.numerator) * Int128(value.denominator),
                Int128(input.denominator) * Int128(value.numerator)
            )
        }
    }

    private static func make(_ numerator: Int128, _ denominator: Int128) -> NFExactNumber? {
        guard denominator != 0 else { return nil }
        var normalizedNumerator = denominator < 0 ? -numerator : numerator
        var normalizedDenominator = abs(denominator)
        var lhs = abs(normalizedNumerator)
        var rhs = normalizedDenominator
        while rhs != 0 { (lhs, rhs) = (rhs, lhs % rhs) }
        let divisor = max(1, lhs)
        normalizedNumerator /= divisor
        normalizedDenominator /= divisor
        guard let numerator64 = Int64(exactly: normalizedNumerator),
              let denominator64 = Int64(exactly: normalizedDenominator) else { return nil }
        return try? NFExactNumber(numerator: numerator64, denominator: denominator64)
    }
}

struct NFCalculationChainContract: Codable, Equatable, Sendable {
    static let contractVersion = 1

    let version: Int
    let initialValue: NFExactNumber
    let operations: [NFCalculationChainOperation]

    init(initialValue: NFExactNumber, operations: [NFCalculationChainOperation]) {
        version = Self.contractVersion
        self.initialValue = initialValue
        self.operations = operations
    }

    init?(representation: NFLogicRepresentationMetadata) {
        guard representation.invariants["contract"] == "calculation-chain.v1",
              let initial = representation.variables["initial"].flatMap(NFExactNumber.init(parsing:)),
              representation.transitions.count > 0 else { return nil }
        let operations = representation.transitions
            .sorted { $0.id < $1.id }
            .compactMap { NFCalculationChainOperation.decodeMutation($0.mutation) }
        guard operations.count == representation.transitions.count else { return nil }
        self.init(initialValue: initial, operations: operations)
    }

    var representation: NFLogicRepresentationMetadata {
        NFLogicRepresentationMetadata(
            variables: ["initial": initialValue.canonicalString],
            transitions: operations.enumerated().map { index, operation in
                NFLogicTransition(
                    id: String(format: "step.%03d", index),
                    condition: "After step \(index + 1)",
                    mutation: operation.encodedMutation
                )
            },
            invariants: ["contract": "calculation-chain.v1", "scoreAuthority": "final-answer-only"],
            traceLanguage: "nf.exact-rational.v1"
        )
    }
}

struct NFCalculationChainCheckpoint: Codable, Equatable, Sendable, Identifiable {
    let index: Int
    let operation: NFCalculationChainOperation
    let input: NFExactNumber
    let output: NFExactNumber

    var id: Int { index }
}

struct NFCalculationChainDiagnostic: Codable, Equatable, Sendable {
    let originalScoreIsCorrect: Bool
    let originalCredit: Double
    let expectedFinalValue: NFExactNumber?
    let submittedFinalValue: NFExactNumber?
    let checkpoints: [NFCalculationChainCheckpoint]
    let firstMismatchedCheckpoint: Int?
}

enum NFCalculationChainEngine {
    static func replay(_ contract: NFCalculationChainContract) -> [NFCalculationChainCheckpoint]? {
        var value = contract.initialValue
        var checkpoints: [NFCalculationChainCheckpoint] = []
        for (index, operation) in contract.operations.enumerated() {
            guard let output = operation.applying(to: value) else { return nil }
            checkpoints.append(
                NFCalculationChainCheckpoint(index: index, operation: operation, input: value, output: output)
            )
            value = output
        }
        return checkpoints
    }

    /// Diagnostic reconstruction is deliberately score-preserving: optional
    /// learner checkpoints identify the first divergence, but the original
    /// final-answer score and credit never change during replay.
    static func diagnose(
        contract: NFCalculationChainContract,
        submittedFinalValue: String,
        learnerCheckpoints: [String] = []
    ) -> NFCalculationChainDiagnostic {
        let checkpoints = replay(contract) ?? []
        let expectedFinal = checkpoints.last?.output ?? contract.initialValue
        let submitted = NFExactNumber(parsing: submittedFinalValue)
        let originalCorrect = submitted == expectedFinal
        let firstMismatch = learnerCheckpoints.enumerated().first { index, source in
            guard !source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
            guard checkpoints.indices.contains(index),
                  let learnerValue = NFStateValueAuthority.exactNumber(source) else { return true }
            return learnerValue != checkpoints[index].output
        }?.offset
        return NFCalculationChainDiagnostic(
            originalScoreIsCorrect: originalCorrect,
            originalCredit: originalCorrect ? 1 : 0,
            expectedFinalValue: expectedFinal,
            submittedFinalValue: submitted,
            checkpoints: checkpoints,
            firstMismatchedCheckpoint: firstMismatch
        )
    }
}

import Foundation

enum NFExactNumberError: Error, Equatable, Sendable {
    case zeroDenominator
    case outOfRange
}

/// A normalized rational used as scoring authority for deterministic numeric
/// items. Display values remain `Double` for source compatibility, but answer
/// comparison never depends on binary floating-point equality.
struct NFExactNumber: Codable, Equatable, Hashable, Sendable {
    let numerator: Int64
    let denominator: Int64

    init(numerator: Int64, denominator: Int64 = 1) throws {
        guard denominator != 0 else { throw NFExactNumberError.zeroDenominator }
        guard numerator != .min, denominator != .min else { throw NFExactNumberError.outOfRange }

        let sign: Int64 = denominator < 0 ? -1 : 1
        let signedNumerator = numerator * sign
        let positiveDenominator = denominator * sign
        let divisor = Self.greatestCommonDivisor(abs(signedNumerator), positiveDenominator)
        self.numerator = signedNumerator / divisor
        self.denominator = positiveDenominator / divisor
    }

    init?(parsing source: String) {
        let text = source
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "−", with: "-")
        guard !text.isEmpty else { return nil }

        let fractionParts = text.split(separator: "/", omittingEmptySubsequences: false)
        if fractionParts.count == 2 {
            guard let numerator = Int64(fractionParts[0].trimmingCharacters(in: .whitespaces)),
                  let denominator = Int64(fractionParts[1].trimmingCharacters(in: .whitespaces)),
                  let value = try? Self.init(numerator: numerator, denominator: denominator) else {
                return nil
            }
            self = value
            return
        }
        guard fractionParts.count == 1,
              let decimal = Self.parseDecimal(text) else { return nil }
        self = decimal
    }

    init?(legacyDouble value: Double) {
        guard value.isFinite else { return nil }
        self.init(parsing: String(value))
    }

    var doubleValue: Double {
        Double(numerator) / Double(denominator)
    }

    var canonicalString: String {
        denominator == 1 ? String(numerator) : "\(numerator)/\(denominator)"
    }

    func isWithinAbsoluteTolerance(
        of expected: NFExactNumber,
        tolerance: NFExactNumber
    ) -> Bool {
        guard tolerance.numerator >= 0 else { return false }
        let (differenceNumerator, differenceDenominator) = difference(from: expected)
        return Self.productIsLessThanOrEqual(
            [differenceNumerator, Int128(tolerance.denominator)],
            [Int128(tolerance.numerator), differenceDenominator]
        )
    }

    func isWithinRelativeTolerance(
        of expected: NFExactNumber,
        tolerance: NFExactNumber
    ) -> Bool {
        guard tolerance.numerator >= 0 else { return false }
        let (differenceNumerator, differenceDenominator) = difference(from: expected)
        return Self.productIsLessThanOrEqual(
            [differenceNumerator, Int128(expected.denominator), Int128(tolerance.denominator)],
            [abs(Int128(expected.numerator)), Int128(tolerance.numerator), differenceDenominator]
        )
    }

    private func difference(from expected: NFExactNumber) -> (Int128, Int128) {
        let commonDivisor = Self.greatestCommonDivisor(
            Int128(denominator),
            Int128(expected.denominator)
        )
        let leftMultiplier = Int128(expected.denominator) / commonDivisor
        let rightMultiplier = Int128(denominator) / commonDivisor
        return (
            abs(Int128(numerator) * leftMultiplier - Int128(expected.numerator) * rightMultiplier),
            Int128(denominator) * leftMultiplier
        )
    }

    private enum CodingKeys: String, CodingKey {
        case numerator
        case denominator
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self = try Self(
            numerator: container.decode(Int64.self, forKey: .numerator),
            denominator: container.decode(Int64.self, forKey: .denominator)
        )
    }

    private static func parseDecimal(_ source: String) -> NFExactNumber? {
        let exponentParts = source.split(
            omittingEmptySubsequences: false,
            whereSeparator: { $0 == "e" || $0 == "E" }
        )
        guard exponentParts.count <= 2 else { return nil }
        let exponent: Int
        if exponentParts.count == 2 {
            guard let parsedExponent = Int(exponentParts[1]), (-18...18).contains(parsedExponent) else {
                return nil
            }
            exponent = parsedExponent
        } else {
            exponent = 0
        }

        var significand = String(exponentParts[0])
        var isNegative = false
        if significand.hasPrefix("+") {
            significand.removeFirst()
        } else if significand.hasPrefix("-") {
            isNegative = true
            significand.removeFirst()
        }
        guard !significand.isEmpty else { return nil }

        let decimalParts = significand.split(separator: ".", omittingEmptySubsequences: false)
        guard decimalParts.count <= 2 else { return nil }
        let whole = String(decimalParts[0])
        let fractional = decimalParts.count == 2 ? String(decimalParts[1]) : ""
        guard (!whole.isEmpty || !fractional.isEmpty),
              whole.allSatisfy({ $0.isNumber }),
              fractional.allSatisfy({ $0.isNumber }) else { return nil }

        let combinedDigits = (whole + fractional).drop(while: { $0 == "0" })
        let unsignedText = combinedDigits.isEmpty ? "0" : String(combinedDigits)
        guard unsignedText.count <= 18,
              let unsignedValue = Int64(unsignedText) else { return nil }
        let signedValue = isNegative ? -unsignedValue : unsignedValue
        let scale: Int = fractional.count - exponent

        if scale <= 0 {
            guard let multiplier = powerOfTen(-scale) else { return nil }
            let product = signedValue.multipliedReportingOverflow(by: multiplier)
            guard !product.overflow else { return nil }
            return try? Self(numerator: product.partialValue)
        }
        guard let denominator = powerOfTen(scale) else { return nil }
        return try? Self(numerator: signedValue, denominator: denominator)
    }

    private static func powerOfTen(_ exponent: Int) -> Int64? {
        guard (0...18).contains(exponent) else { return nil }
        var value: Int64 = 1
        for _ in 0..<exponent {
            let result = value.multipliedReportingOverflow(by: 10)
            guard !result.overflow else { return nil }
            value = result.partialValue
        }
        return value
    }

    private static func greatestCommonDivisor(_ first: Int64, _ second: Int64) -> Int64 {
        var lhs = first
        var rhs = second
        while rhs != 0 { (lhs, rhs) = (rhs, lhs % rhs) }
        return max(1, lhs)
    }

    private static func greatestCommonDivisor(_ first: Int128, _ second: Int128) -> Int128 {
        var lhs = abs(first)
        var rhs = abs(second)
        while rhs != 0 { (lhs, rhs) = (rhs, lhs % rhs) }
        return max(1, lhs)
    }

    /// Compares two products exactly after cross-cancelling every factor.
    private static func productIsLessThanOrEqual(
        _ leftFactors: [Int128],
        _ rightFactors: [Int128]
    ) -> Bool {
        if leftFactors.contains(0) { return true }
        if rightFactors.contains(0) { return false }
        var left = leftFactors.map(abs)
        var right = rightFactors.map(abs)
        for leftIndex in left.indices {
            for rightIndex in right.indices {
                let divisor = greatestCommonDivisor(left[leftIndex], right[rightIndex])
                left[leftIndex] /= divisor
                right[rightIndex] /= divisor
            }
        }
        let leftProduct = left.reduce(BigUnsigned.one) { $0.multiplied(by: BigUnsigned($1)) }
        let rightProduct = right.reduce(BigUnsigned.one) { $0.multiplied(by: BigUnsigned($1)) }
        return leftProduct <= rightProduct
    }

    /// Minimal arbitrary-width unsigned arithmetic keeps tolerance comparison
    /// exact even when several individually valid Int64 ratios are cross-
    /// multiplied near their supported limits.
    private struct BigUnsigned: Comparable {
        private static let base: UInt64 = 1_000_000_000
        private var limbs: [UInt64]

        static let one = BigUnsigned(limbs: [1])

        init(_ value: Int128) {
            precondition(value >= 0)
            let text = String(value)
            var limbs: [UInt64] = []
            var end = text.endIndex
            while end > text.startIndex {
                let start = text.index(end, offsetBy: -min(9, text.distance(from: text.startIndex, to: end)))
                limbs.append(UInt64(text[start..<end]) ?? 0)
                end = start
            }
            self.init(limbs: limbs)
        }

        private init(limbs: [UInt64]) {
            var normalized = limbs
            while normalized.count > 1, normalized.last == 0 { normalized.removeLast() }
            self.limbs = normalized.isEmpty ? [0] : normalized
        }

        func multiplied(by other: BigUnsigned) -> BigUnsigned {
            var result = Array(repeating: UInt64(0), count: limbs.count + other.limbs.count)
            for leftIndex in limbs.indices {
                var carry: UInt64 = 0
                for rightIndex in other.limbs.indices {
                    let resultIndex = leftIndex + rightIndex
                    let total = result[resultIndex] + limbs[leftIndex] * other.limbs[rightIndex] + carry
                    result[resultIndex] = total % Self.base
                    carry = total / Self.base
                }
                var resultIndex = leftIndex + other.limbs.count
                while carry > 0 {
                    let total = result[resultIndex] + carry
                    result[resultIndex] = total % Self.base
                    carry = total / Self.base
                    resultIndex += 1
                    if resultIndex == result.count, carry > 0 { result.append(0) }
                }
            }
            return BigUnsigned(limbs: result)
        }

        static func < (lhs: BigUnsigned, rhs: BigUnsigned) -> Bool {
            if lhs.limbs.count != rhs.limbs.count { return lhs.limbs.count < rhs.limbs.count }
            for index in lhs.limbs.indices.reversed() where lhs.limbs[index] != rhs.limbs[index] {
                return lhs.limbs[index] < rhs.limbs[index]
            }
            return false
        }
    }
}

enum NFExactNumericTolerance: Codable, Equatable, Sendable {
    case absolute(NFExactNumber)
    case relative(NFExactNumber)
    case absoluteOrRelative(absolute: NFExactNumber, relative: NFExactNumber)

    init?(legacy tolerance: NFNumericTolerance) {
        switch tolerance {
        case let .absolute(value):
            guard let exact = NFExactNumber(legacyDouble: value) else { return nil }
            self = .absolute(exact)
        case let .relative(value):
            guard let exact = NFExactNumber(legacyDouble: value) else { return nil }
            self = .relative(exact)
        case let .absoluteOrRelative(absolute, relative):
            guard let exactAbsolute = NFExactNumber(legacyDouble: absolute),
                  let exactRelative = NFExactNumber(legacyDouble: relative) else { return nil }
            self = .absoluteOrRelative(absolute: exactAbsolute, relative: exactRelative)
        }
    }

    var isNonnegative: Bool {
        switch self {
        case let .absolute(value), let .relative(value): value.numerator >= 0
        case let .absoluteOrRelative(absolute, relative):
            absolute.numerator >= 0 && relative.numerator >= 0
        }
    }
}

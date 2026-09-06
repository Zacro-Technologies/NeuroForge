import Foundation

/// A deliberately bounded polynomial language. Functions are declared, opaque
/// atoms: F(b) is distinct from f(b), F*b, and F(a). No submitted code executes.
struct NFSymbolicAnswerContract: Codable, Equatable, Sendable {
    var acceptedExpressions: [String]
    var variables: [String]
    var functions: [String] = []
    var domainRestrictions: [String] = []
    var policyVersion: Int = 1
}

enum NFSymbolicComparison: Equatable, Sendable {
    case equivalent
    case different
    case unsupported
}

enum NFRestrictedSymbolicAuthority {
    static let maximumTokens = 256
    static let maximumDepth = 32
    static let maximumSymbols = 16
    static let maximumTerms = 2_048
    static let maximumExponent = 12

    static func compare(_ response: String, contract: NFSymbolicAnswerContract) -> NFSymbolicComparison {
        if contract.policyVersion == 2 { return NFMatrixEigenvectorEquationAuthority.compare(response, contract: contract) }
        guard contract.policyVersion == 1, contract.variables.count + contract.functions.count <= maximumSymbols,
              Set(contract.variables + contract.functions).count == contract.variables.count + contract.functions.count,
              !contract.acceptedExpressions.isEmpty else { return .unsupported }
        do {
            var parser = try Parser(response, contract: contract)
            let actual = try parser.parse()
            for expression in contract.acceptedExpressions {
                var reference = try Parser(expression, contract: contract)
                if actual == (try reference.parse()) { return .equivalent }
            }
            return .different
        } catch { return .unsupported }
    }

    private enum Failure: Error { case syntax, limit, arithmetic }
    private struct Polynomial: Equatable {
        var terms: [[String]: NFExactNumber]
        static let zero = Polynomial(terms: [:])
        static let one = Polynomial(terms: [[]: try! NFExactNumber(numerator: 1)])
        static func number(_ number: NFExactNumber) -> Self {
            number.numerator == 0 ? .zero : Self(terms: [[]: number])
        }
        static func atom(_ name: String) -> Self {
            Self(terms: [[name]: try! NFExactNumber(numerator: 1)])
        }
        var signature: String {
            terms.map { "\($0.key.joined(separator: "*")):\($0.value.canonicalString)" }.sorted().joined(separator: ";")
        }
        func adding(_ rhs: Self, sign: Int64 = 1) throws -> Self {
            var result = terms
            for (key, value) in rhs.terms {
                let current = result[key] ?? (try! NFExactNumber(numerator: 0))
                let numerator = Int128(current.numerator) * Int128(value.denominator)
                    + Int128(sign) * Int128(value.numerator) * Int128(current.denominator)
                let sum = try Self.rational(numerator, Int128(current.denominator) * Int128(value.denominator))
                result[key] = sum.numerator == 0 ? nil : sum
            }
            guard result.count <= maximumTerms else { throw Failure.limit }
            return Self(terms: result)
        }
        func multiplied(by rhs: Self) throws -> Self {
            guard terms.count * rhs.terms.count <= maximumTerms * 4 else { throw Failure.limit }
            var result = Self.zero
            for (leftKey, leftValue) in terms {
                for (rightKey, rightValue) in rhs.terms {
                    guard leftKey.count + rightKey.count <= maximumSymbols * maximumExponent else { throw Failure.limit }
                    let coefficient = try Self.rational(
                        Int128(leftValue.numerator) * Int128(rightValue.numerator),
                        Int128(leftValue.denominator) * Int128(rightValue.denominator)
                    )
                    result = try result.adding(Self(terms: [(leftKey + rightKey).sorted(): coefficient]))
                }
            }
            return result
        }
        func divided(by rhs: Self) throws -> Self {
            // Variable denominators need a reviewed rational-function domain
            // module. Reject them before cancellation can erase exclusions.
            guard rhs.terms.count == 1, let constant = rhs.terms[[]], constant.numerator != 0 else {
                throw Failure.syntax
            }
            return try multiplied(by: .number(Self.rational(Int128(constant.denominator), Int128(constant.numerator))))
        }
        func raised(to exponent: Int) throws -> Self {
            guard (-maximumExponent...maximumExponent).contains(exponent) else { throw Failure.limit }
            guard exponent > 0 || !terms.isEmpty else { throw Failure.syntax }
            if exponent < 0 { return try Self.one.divided(by: raised(to: -exponent)) }
            var result = Self.one
            for _ in 0..<exponent { result = try result.multiplied(by: self) }
            return result
        }
        static func rational(_ numerator: Int128, _ denominator: Int128) throws -> NFExactNumber {
            guard denominator != 0 else { throw Failure.arithmetic }
            var a = abs(numerator), b = abs(denominator)
            while b != 0 { (a, b) = (b, a % b) }
            let gcd = max(1, a)
            guard let n = Int64(exactly: numerator / gcd), let d = Int64(exactly: denominator / gcd) else {
                throw Failure.arithmetic
            }
            return try NFExactNumber(numerator: n, denominator: d)
        }
    }

    private struct Parser {
        var tokens: [String]
        var index = 0
        var depth = 0
        let contract: NFSymbolicAnswerContract
        init(_ source: String, contract: NFSymbolicAnswerContract) throws {
            self.contract = contract
            guard source.count <= 4_096 else { throw Failure.limit }
            let text = source.replacingOccurrences(of: "−", with: "-")
                .replacingOccurrences(of: "×", with: "*")
                .replacingOccurrences(of: "·", with: "*")
                .replacingOccurrences(of: "²", with: "^2")
                .replacingOccurrences(of: "³", with: "^3")
                .replacingOccurrences(of: "¹", with: "^1")
            let chars = Array(text)
            let names = (contract.variables + contract.functions).sorted { $0.count > $1.count }
            var result: [String] = [], i = 0
            while i < chars.count {
                let c = chars[i]
                if c.isWhitespace { i += 1; continue }
                if "+-*/^()".contains(c) { result.append(String(c)); i += 1 }
                else if c.isASCII && (c.isNumber || c == ".") {
                    let start = i
                    while i < chars.count && chars[i].isASCII && (chars[i].isNumber || chars[i] == ".") { i += 1 }
                    let number = String(chars[start..<i])
                    guard NFExactNumber(parsing: number) != nil else { throw Failure.syntax }
                    result.append(number)
                } else if let name = names.first(where: { Array(chars[i...]).starts(with: Array($0)) }) {
                    result.append(name); i += name.count
                } else { throw Failure.syntax }
                guard result.count <= maximumTokens else { throw Failure.limit }
            }
            tokens = result
        }
        mutating func parse() throws -> Polynomial {
            guard !tokens.isEmpty else { throw Failure.syntax }
            let result = try sum()
            guard index == tokens.count else { throw Failure.syntax }
            return result
        }
        var next: String? { index < tokens.count ? tokens[index] : nil }
        mutating func consume(_ token: String) -> Bool {
            guard next == token else { return false }; index += 1; return true
        }
        mutating func sum() throws -> Polynomial {
            var value = try product()
            while let op = next, op == "+" || op == "-" {
                index += 1
                value = try value.adding(product(), sign: op == "+" ? 1 : -1)
            }
            return value
        }
        mutating func product() throws -> Polynomial {
            var value = try unary()
            while let token = next {
                if token == "*" || token == "/" {
                    index += 1
                    let rhs = try unary()
                    value = try token == "*" ? value.multiplied(by: rhs) : value.divided(by: rhs)
                } else if token == "(" || contract.variables.contains(token) || contract.functions.contains(token) {
                    value = try value.multiplied(by: unary())
                } else { break }
            }
            return value
        }
        mutating func unary() throws -> Polynomial {
            if consume("+") { return try boundedUnary() }
            if consume("-") { return try Polynomial.zero.adding(boundedUnary(), sign: -1) }
            var value = try primary()
            if consume("^") {
                let negative = consume("-")
                _ = consume("+")
                guard let token = next, let exponent = Int(token) else { throw Failure.syntax }
                index += 1
                value = try value.raised(to: negative ? -exponent : exponent)
            }
            return value
        }
        mutating func boundedUnary() throws -> Polynomial {
            depth += 1; defer { depth -= 1 }
            guard depth <= maximumDepth else { throw Failure.limit }
            return try unary()
        }
        mutating func primary() throws -> Polynomial {
            guard let token = next else { throw Failure.syntax }
            if consume("(") {
                depth += 1; defer { depth -= 1 }
                guard depth <= maximumDepth else { throw Failure.limit }
                let value = try sum()
                guard consume(")") else { throw Failure.syntax }
                return value
            }
            index += 1
            if let number = NFExactNumber(parsing: token) { return .number(number) }
            if contract.functions.contains(token) {
                guard consume("(") else { throw Failure.syntax }
                depth += 1; defer { depth -= 1 }
                guard depth <= maximumDepth else { throw Failure.limit }
                let argument = try sum()
                guard consume(")") else { throw Failure.syntax }
                return .atom("\(token)(\(argument.signature))")
            }
            guard contract.variables.contains(token) else { throw Failure.syntax }
            return .atom(token)
        }
    }
}


/// This module preserves the order and roles in the stated eigenvector equation.
/// It does not interpret arbitrary matrix algebra or treat matrices as scalars.
enum NFMatrixEigenvectorEquationAuthority {
    static let contract = NFSymbolicAnswerContract(acceptedExpressions: ["A*v=lambda*v"],
        variables: ["A", "v", "lambda"], functions: [],
        domainRestrictions: ["A is a square matrix; v is a nonzero vector; lambda is a scalar"], policyVersion: 2)
    static func supports(_ candidate: NFSymbolicAnswerContract) -> Bool { candidate == contract }
    static func compare(_ response: String, contract candidate: NFSymbolicAnswerContract) -> NFSymbolicComparison {
        guard supports(candidate), response.utf8.count <= 2_048 else { return .unsupported }
        do {
            var parser = try Parser(response)
            let sides = try parser.equation()
            let matrix = ["A", "v"]
            let scalar = [["lambda", "v"], ["v", "lambda"]]
            return (sides.0 == matrix && scalar.contains(sides.1))
                || (sides.1 == matrix && scalar.contains(sides.0)) ? .equivalent : .different
        } catch { return .unsupported }
    }
    private enum Failure: Error { case unsupported }
    private struct Parser {
        let tokens: [String]
        var cursor = 0
        init(_ text: String) throws {
            let characters = Array(text), words = ["lambda", "equals", "times"]
            var cursor = 0, output: [String] = []
            while cursor < characters.count {
                let character = characters[cursor]
                if character.isWhitespace { cursor += 1; continue }
                if let word = words.first(where: { characters[cursor...].starts(with: Array($0)) }) {
                    output.append(word == "equals" ? "=" : word == "times" ? "*" : word)
                    cursor += word.count
                } else {
                    if character == "λ" { output.append("lambda") }
                    else if ["×", "·"].contains(character) { output.append("*") }
                    else if character.isASCII && (character.isLetter || "=()*".contains(character)) { output.append(String(character)) }
                    else { throw Failure.unsupported }
                    cursor += 1
                }
                guard output.count <= 128 else { throw Failure.unsupported }
            }
            guard !output.isEmpty else { throw Failure.unsupported }
            tokens = output
        }
        mutating func equation() throws -> ([String], [String]) {
            let left = try product(depth: 0)
            guard take("=") else { throw Failure.unsupported }
            let right = try product(depth: 0)
            guard cursor == tokens.count else { throw Failure.unsupported }
            return (left, right)
        }
        mutating func product(depth: Int) throws -> [String] {
            guard depth <= 8 else { throw Failure.unsupported }
            var factors = try factor(depth: depth)
            while cursor < tokens.count, tokens[cursor] != "=", tokens[cursor] != ")" {
                _ = take("*")
                factors += try factor(depth: depth)
                guard factors.count <= 16 else { throw Failure.unsupported }
            }
            return factors
        }
        mutating func factor(depth: Int) throws -> [String] {
            if take("(") {
                let factors = try product(depth: depth + 1)
                guard take(")") else { throw Failure.unsupported }
                return factors
            }
            guard cursor < tokens.count else { throw Failure.unsupported }
            let token = tokens[cursor]
            guard token == "lambda" || (["A", "a", "V", "v", "L"].contains(token)) else { throw Failure.unsupported }
            cursor += 1
            return [token]
        }
        mutating func take(_ token: String) -> Bool {
            guard cursor < tokens.count, tokens[cursor] == token else { return false }
            cursor += 1
            return true
        }
    }
}

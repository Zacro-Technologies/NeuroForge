import Foundation

enum NFStateFieldDomain: String, Codable, Equatable, Sendable {
    case exactNumber, boolean, identifier, reviewedLabel
}

enum NFStateValueAuthority {
    static func isParseable(_ source: String, domain: NFStateFieldDomain?) -> Bool {
        let value = source.trimmingCharacters(in: .whitespacesAndNewlines)
        switch domain {
        case .exactNumber: return exactNumber(value) != nil
        case .boolean: return ["true", "false"].contains(value.lowercased())
        case .identifier, .reviewedLabel, nil: return !value.isEmpty
        }
    }
    static func exactNumber(_ source: String) -> NFExactNumber? {
        let text = source.trimmingCharacters(in: .whitespacesAndNewlines)
        if let number = NFExactNumber(parsing: text) { return number }
        guard text.range(of: #"^[+\-]?[0-9]{1,3}(,[0-9]{3})+(\.[0-9]+)?([eE][+\-]?[0-9]+)?$"#, options: .regularExpression) != nil else { return nil }
        return NFExactNumber(parsing: text.replacingOccurrences(of: ",", with: ""))
    }
    static func equivalent(_ actual: String, _ expected: String, domain: NFStateFieldDomain?) -> Bool {
        let lhs = actual.trimmingCharacters(in: .whitespacesAndNewlines)
        let rhs = expected.trimmingCharacters(in: .whitespacesAndNewlines)
        switch domain {
        case .exactNumber:
            guard let a = exactNumber(lhs), let b = exactNumber(rhs) else { return false }
            return a == b
        case .boolean:
            let values = ["true": true, "false": false]
            guard let a = values[lhs.lowercased()], let b = values[rhs.lowercased()] else { return false }
            return a == b
        case .reviewedLabel: return lhs.lowercased() == rhs.lowercased()
        case .identifier, nil: return lhs == rhs
        }
    }
}

enum NFAnswerSemanticIdentity {
    static func canonical(_ text: String) -> String {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "−", with: "-")
        if let number = NFExactNumber(parsing: value) { return "number:\(number.canonicalString)" }
        if value.hasPrefix("("), value.hasSuffix(")") {
            let parts = value.dropFirst().dropLast().split(separator: ",", omittingEmptySubsequences: false)
            let numbers = parts.compactMap { NFExactNumber(parsing: String($0)) }
            if numbers.count == parts.count, parts.count >= 2 {
                return "tuple:" + numbers.map(\.canonicalString).joined(separator: ",")
            }
        }
        // Only prose display duplicates are folded here. Mathematical roles
        // are never inferred to be equivalent by removing their operators.
        return "text:" + value.folding(options: [.caseInsensitive, .widthInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }
    static func hasDistinctOptions(_ options: [NFChoiceOption]) -> Bool {
        Set(options.map { canonical($0.text) }).count == options.count
    }
}

enum NFOrderingAuthority {
    static func dependencies(for schema: NFOrderedStepsResponseSchema) -> [NFOrderingDependency] {
        schema.dependencies ?? zip(schema.correctOrder, schema.correctOrder.dropFirst()).map {
            NFOrderingDependency(before: $0.0, after: $0.1)
        }
    }
    static func isValid(_ schema: NFOrderedStepsResponseSchema) -> Bool {
        let ids = Set(schema.steps.map(\.id))
        let edges = dependencies(for: schema)
        guard edges.allSatisfy({ ids.contains($0.before) && ids.contains($0.after) && $0.before != $0.after }),
              Set(edges.map { "\($0.before)\u{0}\($0.after)" }).count == edges.count else { return false }
        var remaining = ids
        while !remaining.isEmpty {
            let available = remaining.filter { node in !edges.contains { $0.after == node && remaining.contains($0.before) } }
            if available.isEmpty { return false }
            remaining.subtract(available)
        }
        return true
    }
}

struct NFClosedInterval: Codable, Equatable, Sendable {
    let lower: Double
    let upper: Double
    init(lower: Double, upper: Double) throws {
        guard lower.isFinite, upper.isFinite, lower <= upper else { throw NFIntervalError.invalidEndpoints }
        self.lower = lower; self.upper = upper
    }
    private enum CodingKeys: String, CodingKey { case lower, upper }
    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(lower: c.decode(Double.self, forKey: .lower), upper: c.decode(Double.self, forKey: .upper))
    }
    enum Relationship: String, Codable, Equatable, Sendable { case disjoint, touching, overlapping }
    func relationship(to other: Self) -> Relationship {
        let lowerIntersection = max(lower, other.lower), upperIntersection = min(upper, other.upper)
        if lowerIntersection > upperIntersection { return .disjoint }
        return lowerIntersection == upperIntersection ? .touching : .overlapping
    }
    enum NFIntervalError: Error { case invalidEndpoints }
}

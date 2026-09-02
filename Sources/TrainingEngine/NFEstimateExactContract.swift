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
            expectedViolatedRuleID: nil
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

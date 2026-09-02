import Foundation

/// User-facing labels for stable deterministic scorer codes. The raw code stays
/// in exports and evidence identifiers; UI copy is localized independently.
enum NFScoringErrorCopy {
    static func title(
        for code: String,
        locale: Locale = NFAppLocalization.preferredLocale
    ) -> String {
        switch code {
        case "response_type_mismatch":
            NFAppLocalization.localized("Response format mismatch", locale: locale, comment: "Deterministic scoring-error label.")
        case "numeric_notation":
            NFAppLocalization.localized("Numeric notation issue", locale: locale, comment: "Deterministic scoring-error label.")
        case "numeric_input", "input_error":
            NFAppLocalization.localized("Invalid number", locale: locale, comment: "Deterministic scoring-error label.")
        case "numeric_value":
            NFAppLocalization.localized("Incorrect numeric value", locale: locale, comment: "Deterministic scoring-error label.")
        case "unit_missing":
            NFAppLocalization.localized("Required unit missing", locale: locale, comment: "Deterministic scoring-error label.")
        case "unit_mismatch":
            NFAppLocalization.localized("Unit mismatch", locale: locale, comment: "Deterministic scoring-error label.")
        case "unknown_choice":
            NFAppLocalization.localized("Unknown choice", locale: locale, comment: "Deterministic scoring-error label.")
        case "choice_selection", "multiple_choice_selection":
            NFAppLocalization.localized("Choice selection mismatch", locale: locale, comment: "Deterministic scoring-error label.")
        case "selection_bounds":
            NFAppLocalization.localized("Selection count out of range", locale: locale, comment: "Deterministic scoring-error label.")
        case "ordered_steps_membership":
            NFAppLocalization.localized("Step set mismatch", locale: locale, comment: "Deterministic scoring-error label.")
        case "ordered_steps_sequence":
            NFAppLocalization.localized("Step order mismatch", locale: locale, comment: "Deterministic scoring-error label.")
        case "text_missing":
            NFAppLocalization.localized("Answer missing", locale: locale, comment: "Deterministic scoring-error label.")
        case "text_too_long":
            NFAppLocalization.localized("Answer too long", locale: locale, comment: "Deterministic scoring-error label.")
        case "text_answer":
            NFAppLocalization.localized("Answer mismatch", locale: locale, comment: "Deterministic scoring-error label.")
        case "text_required_terms":
            NFAppLocalization.localized("Required terms missing", locale: locale, comment: "Deterministic scoring-error label.")
        case "self_check_partial":
            NFAppLocalization.localized("Partial self-check match", locale: locale, comment: "Deterministic self-check scoring label.")
        case "self_check_not_yet":
            NFAppLocalization.localized("Not yet recalled", locale: locale, comment: "Deterministic self-check scoring label.")
        case "claim_evidence_unknown":
            NFAppLocalization.localized("Unknown claim or evidence", locale: locale, comment: "Deterministic claim-and-evidence scoring label.")
        case "claim_evidence_support":
            NFAppLocalization.localized("Claim-evidence support mismatch", locale: locale, comment: "Deterministic claim-and-evidence scoring label.")
        case "logic_rule":
            NFAppLocalization.localized("Rule identification mismatch", locale: locale, comment: "Deterministic logic-state scoring label.")
        case "logic_state":
            NFAppLocalization.localized("Logic state mismatch", locale: locale, comment: "Deterministic logic-state scoring label.")
        default:
            NFAppLocalization.localized(
                "Other scored pattern",
                locale: locale,
                comment: "Safe learner-facing fallback for an unrecognized deterministic scoring-error code."
            )
        }
    }
}

import Foundation

enum NFTrainingDayBoundaryFormatter {
    static func title(for hour: Int, locale: Locale = NFAppLocalization.preferredLocale) -> String {
        let clamped = min(12, max(0, hour))
        let timeZone = TimeZone(secondsFromGMT: 0)!
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        guard let date = calendar.date(from: DateComponents(
            timeZone: timeZone,
            year: 2000,
            month: 1,
            day: 1,
            hour: clamped
        )) else { return "—" }

        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = timeZone
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        let time = formatter.string(from: date)
        guard clamped == 0 else { return time }
        return NFAppLocalization.localized(
            "\(time) (midnight)",
            locale: locale,
            comment: "Locale-formatted midnight training-day boundary."
        )
    }
}

enum Stage: String, Codable, CaseIterable, Identifiable, Sendable {
    case secondary
    case undergraduate
    case graduate
    case researcher
    case professional
    case other
    case undisclosed

    var id: String { rawValue }

    var title: String {
        switch self {
        case .secondary: NFAppLocalization.localized("Secondary student", locale: NFAppLocalization.preferredLocale, comment: "Education or career stage option during onboarding.")
        case .undergraduate: NFAppLocalization.localized("Undergraduate", locale: NFAppLocalization.preferredLocale, comment: "Education or career stage option during onboarding.")
        case .graduate: NFAppLocalization.localized("Graduate student", locale: NFAppLocalization.preferredLocale, comment: "Education or career stage option during onboarding.")
        case .researcher: NFAppLocalization.localized("Researcher", locale: NFAppLocalization.preferredLocale, comment: "Education or career stage option during onboarding.")
        case .professional: NFAppLocalization.localized("Professional", locale: NFAppLocalization.preferredLocale, comment: "Education or career stage option during onboarding.")
        case .other: NFAppLocalization.localized("Other", locale: NFAppLocalization.preferredLocale, comment: "Education or career stage option during onboarding.")
        case .undisclosed: NFAppLocalization.localized("Prefer not to say", locale: NFAppLocalization.preferredLocale, comment: "Privacy-preserving education or career stage option during onboarding.")
        }
    }
}

enum STEMField: String, Codable, CaseIterable, Identifiable, Sendable {
    case general
    case mathematics
    case physics
    case computing
    case engineering
    case lifeSciences
    case chemistry
    case dataScience

    var id: String { rawValue }

    var title: String { localizedTitle(locale: NFAppLocalization.preferredLocale) }

    func localizedTitle(locale: Locale) -> String {
        switch self {
        case .general: NFAppLocalization.localized("General STEM", locale: locale, comment: "Broad science, technology, engineering, and mathematics field option.")
        case .mathematics: NFAppLocalization.localized("Mathematics", locale: locale, comment: "STEM field option.")
        case .physics: NFAppLocalization.localized("Physics", locale: locale, comment: "STEM field option.")
        case .computing: NFAppLocalization.localized("Computing", locale: locale, comment: "STEM field option covering computer science and software.")
        case .engineering: NFAppLocalization.localized("Engineering", locale: locale, comment: "STEM field option.")
        case .lifeSciences: NFAppLocalization.localized("Life sciences", locale: locale, comment: "STEM field option.")
        case .chemistry: NFAppLocalization.localized("Chemistry", locale: locale, comment: "STEM field option.")
        case .dataScience: NFAppLocalization.localized("Data science", locale: locale, comment: "STEM field option.")
        }
    }
}

enum TrainingGoal: String, Codable, CaseIterable, Identifiable, Sendable {
    case mentalMath
    case problemSolving
    case researchReading
    case dataReasoning
    case experimentalDesign
    case programming
    case spatialReasoning

    var id: String { rawValue }

    var title: String {
        switch self {
        case .mentalMath: NFAppLocalization.localized("Mental math", locale: NFAppLocalization.preferredLocale, comment: "Training-goal option.")
        case .problemSolving: NFAppLocalization.localized("Problem solving", locale: NFAppLocalization.preferredLocale, comment: "Training-goal option.")
        case .researchReading: NFAppLocalization.localized("Research reading", locale: NFAppLocalization.preferredLocale, comment: "Training-goal option for reading scholarly material.")
        case .dataReasoning: NFAppLocalization.localized("Data reasoning", locale: NFAppLocalization.preferredLocale, comment: "Training-goal option.")
        case .experimentalDesign: NFAppLocalization.localized("Experimental design", locale: NFAppLocalization.preferredLocale, comment: "Training-goal option.")
        case .programming: NFAppLocalization.localized("Programming", locale: NFAppLocalization.preferredLocale, comment: "Training-goal option.")
        case .spatialReasoning: NFAppLocalization.localized("Spatial reasoning", locale: NFAppLocalization.preferredLocale, comment: "Training-goal option.")
        }
    }
}

enum TimingMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case untimed
    case adaptive
    case speedFocus

    var id: String { rawValue }

    var title: String {
        switch self {
        case .untimed: NFAppLocalization.localized("Untimed by default", locale: NFAppLocalization.preferredLocale, comment: "Training timing preference.")
        case .adaptive: NFAppLocalization.localized("Adaptive timing", locale: NFAppLocalization.preferredLocale, comment: "Training timing preference.")
        case .speedFocus: NFAppLocalization.localized("Speed focus", locale: NFAppLocalization.preferredLocale, comment: "Training timing preference; speed evidence remains separate from accuracy.")
        }
    }
}

enum AIMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case automatic
    case onDeviceOnly
    case disabled

    var id: String { rawValue }

    var title: String {
        switch self {
        case .automatic: NFAppLocalization.localized("Automatic", locale: NFAppLocalization.preferredLocale, comment: "AI service mode using a configured capable cloud or local model.")
        case .onDeviceOnly: NFAppLocalization.localized("On device", locale: NFAppLocalization.preferredLocale, comment: "AI service mode using a supported local model without cloud requests.")
        case .disabled: NFAppLocalization.localized("Off", locale: NFAppLocalization.preferredLocale, comment: "AI service mode with model features disabled; saved and authored learning remains available.")
        }
    }
}

enum NFPreferredAnswerMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case adaptive
    case keyboard
    case touch
    case pencil

    var id: String { rawValue }

    var title: String {
        switch self {
        case .adaptive: NFAppLocalization.localized("Use the best available input", locale: NFAppLocalization.preferredLocale, comment: "Preferred answer-input mode.")
        case .keyboard: NFAppLocalization.localized("Hardware keyboard", locale: NFAppLocalization.preferredLocale, comment: "Preferred answer-input mode.")
        case .touch: NFAppLocalization.localized("Touch or pointer", locale: NFAppLocalization.preferredLocale, comment: "Preferred answer-input mode.")
        case .pencil: NFAppLocalization.localized("Apple Pencil", locale: NFAppLocalization.preferredLocale, comment: "Preferred answer-input mode. Apple Pencil is a product name.")
        }
    }
}

/// The physical modality actually used to enter an answer. This is kept
/// separate from both the preferred calibration mode and the response schema.
enum NFInputModality: String, Codable, CaseIterable, Sendable {
    case keyboard
    case touch
    case pointer
    case pencil
    case unknown

    var title: String {
        switch self {
        case .keyboard: NFAppLocalization.localized("Keyboard", locale: NFAppLocalization.preferredLocale, comment: "Physical answer-input mode used for a recorded result.")
        case .touch: NFAppLocalization.localized("Touch", locale: NFAppLocalization.preferredLocale, comment: "Physical answer-input mode used for a recorded result.")
        case .pointer: NFAppLocalization.localized("Pointer", locale: NFAppLocalization.preferredLocale, comment: "Physical answer-input mode used for a recorded result, such as a mouse or trackpad.")
        case .pencil: NFAppLocalization.localized("Apple Pencil", locale: NFAppLocalization.preferredLocale, comment: "Physical answer-input mode used for a recorded result. Apple Pencil is a product name.")
        case .unknown: NFAppLocalization.localized("Other input", locale: NFAppLocalization.preferredLocale, comment: "Recorded result whose physical answer-input mode is unavailable.")
        }
    }

    static func title(forPersistedValue value: String) -> String {
        if value == "skipped" {
            return NFAppLocalization.localized("Skipped answer", locale: NFAppLocalization.preferredLocale, comment: "Input-mode label for a result the learner skipped.")
        }
        return NFInputModality(rawValue: value)?.title
            ?? NFAppLocalization.localized("Other input", locale: NFAppLocalization.preferredLocale, comment: "Recorded result whose physical answer-input mode is unavailable.")
    }
}

enum DocumentAIPolicy: String, Codable, CaseIterable, Identifiable, Sendable {
    /// The legacy raw value now denotes Automatic AI for this source. Native
    /// requests follow the selected provider mode; the external Shortcut keeps
    /// its separate per-run handoff confirmation.
    case privateCloudAllowed
    case onDeviceOnly
    case noAI

    var id: String { rawValue }
}

enum Readiness: String, Codable, CaseIterable, Identifiable, Sendable {
    case low
    case normal
    case high

    var id: String { rawValue }

    var title: String {
        switch self {
        case .low: NFAppLocalization.localized("Low", locale: NFAppLocalization.preferredLocale, comment: "Self-reported readiness level.")
        case .normal: NFAppLocalization.localized("Normal", locale: NFAppLocalization.preferredLocale, comment: "Self-reported readiness level.")
        case .high: NFAppLocalization.localized("High", locale: NFAppLocalization.preferredLocale, comment: "Self-reported readiness level.")
        }
    }
    var symbol: String {
        switch self {
        case .low: "battery.25percent"
        case .normal: "battery.75percent"
        case .high: "bolt.fill"
        }
    }
}

enum EvidenceClass: String, Codable, CaseIterable, Sendable {
    case practice
    case nearTransfer
    case appliedTransfer
    case retention
    case assessmentHoldout
    case documentPractice
}

enum EstimateStatus: String, Codable, Equatable, Sendable {
    case unassessed
    case emergingEvidence
    case developing
    case stable
    case incompatibleVersion

    var title: String {
        switch self {
        case .unassessed: NFAppLocalization.localized("Unassessed", locale: NFAppLocalization.preferredLocale, comment: "Status for a skill with no scorable evidence yet.")
        case .emergingEvidence: NFAppLocalization.localized("Emerging evidence", locale: NFAppLocalization.preferredLocale, comment: "Status for an early skill estimate with limited evidence.")
        case .developing: NFAppLocalization.localized("Developing estimate", locale: NFAppLocalization.preferredLocale, comment: "Status for a skill estimate that is not yet stable.")
        case .stable: NFAppLocalization.localized("Stable estimate", locale: NFAppLocalization.preferredLocale, comment: "Status for a skill estimate supported by sufficient app evidence.")
        case .incompatibleVersion: NFAppLocalization.localized("New estimate series", locale: NFAppLocalization.preferredLocale, comment: "Status shown when evidence belongs to a different scoring-model version.")
        }
    }
}

enum ConfidenceLevel: String, Codable, CaseIterable, Identifiable, Sendable {
    case guessing
    case uncertain
    case fairlyConfident
    case certain

    var id: String { rawValue }

    var title: String {
        switch self {
        case .guessing: NFAppLocalization.localized("Guessing", locale: NFAppLocalization.preferredLocale, comment: "Response-confidence option.")
        case .uncertain: NFAppLocalization.localized("Uncertain", locale: NFAppLocalization.preferredLocale, comment: "Response-confidence option.")
        case .fairlyConfident: NFAppLocalization.localized("Fairly confident", locale: NFAppLocalization.preferredLocale, comment: "Response-confidence option.")
        case .certain: NFAppLocalization.localized("Certain", locale: NFAppLocalization.preferredLocale, comment: "Response-confidence option.")
        }
    }

    var probability: Double {
        switch self {
        case .guessing: 0.25
        case .uncertain: 0.45
        case .fairlyConfident: 0.72
        case .certain: 0.92
        }
    }
}

enum NFErrorReflectionCode: String, Codable, CaseIterable, Identifiable, Sendable {
    case knowledgeMissing = "knowledge_missing"
    case misconception
    case misreadConstraint = "misread_constraint"
    case unitMismatch = "unit_mismatch"
    case signDirection = "sign_direction"
    case placeValue = "place_value"
    case operationSelection = "operation_selection"
    case exponent
    case percentageBase = "percentage_base"
    case rounding
    case invalidImplication = "invalid_implication"
    case confound
    case causalOverreach = "causal_overreach"
    case edgeCaseOmitted = "edge_case_omitted"
    case stateTracking = "state_tracking"
    case syntaxFamiliarity = "syntax_familiarity"
    case timePressure = "time_pressure"
    case inputError = "input_error"
    case unfamiliarContext = "unfamiliar_context"
    case other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .knowledgeMissing: NFAppLocalization.localized("Knowledge not yet available", locale: NFAppLocalization.preferredLocale, comment: "Learner-selectable item-level error reflection category.")
        case .misconception: NFAppLocalization.localized("Misconception", locale: NFAppLocalization.preferredLocale, comment: "Learner-selectable item-level error reflection category.")
        case .misreadConstraint: NFAppLocalization.localized("Misread a constraint", locale: NFAppLocalization.preferredLocale, comment: "Learner-selectable item-level error reflection category.")
        case .unitMismatch: NFAppLocalization.localized("Unit mismatch", locale: NFAppLocalization.preferredLocale, comment: "Learner-selectable item-level error reflection category.")
        case .signDirection: NFAppLocalization.localized("Sign or direction", locale: NFAppLocalization.preferredLocale, comment: "Learner-selectable item-level error reflection category.")
        case .placeValue: NFAppLocalization.localized("Place value", locale: NFAppLocalization.preferredLocale, comment: "Learner-selectable item-level error reflection category.")
        case .operationSelection: NFAppLocalization.localized("Operation or strategy selection", locale: NFAppLocalization.preferredLocale, comment: "Learner-selectable item-level error reflection category.")
        case .exponent: NFAppLocalization.localized("Exponent handling", locale: NFAppLocalization.preferredLocale, comment: "Learner-selectable item-level error reflection category.")
        case .percentageBase: NFAppLocalization.localized("Percentage base", locale: NFAppLocalization.preferredLocale, comment: "Learner-selectable item-level error reflection category.")
        case .rounding: NFAppLocalization.localized("Rounding", locale: NFAppLocalization.preferredLocale, comment: "Learner-selectable item-level error reflection category.")
        case .invalidImplication: NFAppLocalization.localized("Invalid implication", locale: NFAppLocalization.preferredLocale, comment: "Learner-selectable item-level error reflection category.")
        case .confound: NFAppLocalization.localized("Confound", locale: NFAppLocalization.preferredLocale, comment: "Learner-selectable item-level error reflection category.")
        case .causalOverreach: NFAppLocalization.localized("Causal overreach", locale: NFAppLocalization.preferredLocale, comment: "Learner-selectable item-level error reflection category.")
        case .edgeCaseOmitted: NFAppLocalization.localized("Edge case omitted", locale: NFAppLocalization.preferredLocale, comment: "Learner-selectable item-level error reflection category.")
        case .stateTracking: NFAppLocalization.localized("State tracking", locale: NFAppLocalization.preferredLocale, comment: "Learner-selectable item-level error reflection category.")
        case .syntaxFamiliarity: NFAppLocalization.localized("Syntax familiarity", locale: NFAppLocalization.preferredLocale, comment: "Learner-selectable item-level error reflection category.")
        case .timePressure: NFAppLocalization.localized("Time pressure", locale: NFAppLocalization.preferredLocale, comment: "Learner-selectable item-level error reflection category.")
        case .inputError: NFAppLocalization.localized("Input error", locale: NFAppLocalization.preferredLocale, comment: "Learner-selectable item-level error reflection category.")
        case .unfamiliarContext: NFAppLocalization.localized("Unfamiliar context", locale: NFAppLocalization.preferredLocale, comment: "Learner-selectable item-level error reflection category.")
        case .other: NFAppLocalization.localized("Something else", locale: NFAppLocalization.preferredLocale, comment: "Learner-selectable item-level error reflection category.")
        }
    }

    static func candidate(for deterministicCode: String?, lab: TrainingLab) -> Self {
        let code = deterministicCode?.lowercased() ?? ""
        if code.contains("unit") { return .unitMismatch }
        if code.contains("sign") || code.contains("direction") { return .signDirection }
        if code.contains("place") { return .placeValue }
        if code.contains("exponent") { return .exponent }
        if code.contains("percent") { return .percentageBase }
        if code.contains("round") { return .rounding }
        if code.contains("confound") { return .confound }
        if code.contains("causal") { return .causalOverreach }
        if code.contains("edge") { return .edgeCaseOmitted }
        if code.contains("logic") || code.contains("state") { return .stateTracking }
        if code.contains("syntax") { return .syntaxFamiliarity }
        if code.contains("input") || code.contains("notation") || code.contains("format") { return .inputError }
        if code.contains("selection") || code.contains("sequence") { return .operationSelection }
        if code.contains("constraint") || code.contains("bounds") || code.contains("membership") { return .misreadConstraint }
        if code.contains("missing") || code.contains("required_terms") || code.contains("not_yet") { return .knowledgeMissing }

        return switch lab {
        case .mentalMath: .operationSelection
        case .spatial: .misreadConstraint
        case .quantitative: .rounding
        case .scientificReasoning: .causalOverreach
        case .logicDebugging: .stateTracking
        case .retrieval: .knowledgeMissing
        case .transfer: .unfamiliarContext
        }
    }

    /// Keeps the first reflection decision small while preserving access to
    /// the complete taxonomy in grouped disclosure below it.
    static func conciseChoices(candidate: Self?, lab: TrainingLab) -> [Self] {
        let labRelevant: [Self] = switch lab {
        case .mentalMath:
            [.operationSelection, .placeValue, .unitMismatch, .signDirection, .rounding]
        case .spatial:
            [.misreadConstraint, .signDirection, .stateTracking, .unfamiliarContext]
        case .quantitative:
            [.rounding, .percentageBase, .operationSelection, .unitMismatch, .confound]
        case .scientificReasoning:
            [.confound, .causalOverreach, .invalidImplication, .misreadConstraint, .knowledgeMissing]
        case .logicDebugging:
            [.stateTracking, .edgeCaseOmitted, .syntaxFamiliarity, .invalidImplication, .misreadConstraint]
        case .retrieval:
            [.knowledgeMissing, .misconception, .unfamiliarContext, .timePressure]
        case .transfer:
            [.unfamiliarContext, .misreadConstraint, .operationSelection, .knowledgeMissing, .timePressure]
        }
        var seen: Set<Self> = []
        let focused = ([candidate].compactMap { $0 } + labRelevant + [.knowledgeMissing, .inputError])
            .filter { $0 != .other && seen.insert($0).inserted }
        return Array(focused.prefix(4)) + [.other]
    }
}

enum NFErrorReflectionGroup: String, CaseIterable, Identifiable, Sendable {
    case understanding
    case calculation
    case reasoning
    case conditions

    var id: String { rawValue }

    var title: String {
        switch self {
        case .understanding:
            NFAppLocalization.localized("Understanding and context", locale: NFAppLocalization.preferredLocale, comment: "Heading for grouped learner reflection reasons.")
        case .calculation:
            NFAppLocalization.localized("Calculation and representation", locale: NFAppLocalization.preferredLocale, comment: "Heading for grouped learner reflection reasons.")
        case .reasoning:
            NFAppLocalization.localized("Reasoning and process", locale: NFAppLocalization.preferredLocale, comment: "Heading for grouped learner reflection reasons.")
        case .conditions:
            NFAppLocalization.localized("Conditions and input", locale: NFAppLocalization.preferredLocale, comment: "Heading for grouped learner reflection reasons.")
        }
    }

    var choices: [NFErrorReflectionCode] {
        switch self {
        case .understanding:
            [.knowledgeMissing, .misconception, .misreadConstraint, .unfamiliarContext]
        case .calculation:
            [.unitMismatch, .signDirection, .placeValue, .operationSelection, .exponent, .percentageBase, .rounding]
        case .reasoning:
            [.invalidImplication, .confound, .causalOverreach, .edgeCaseOmitted, .stateTracking, .syntaxFamiliarity]
        case .conditions:
            [.timePressure, .inputError, .other]
        }
    }
}

enum NFAttemptReflectionTrigger: String, Codable, Sendable {
    case highConfidenceError = "high_confidence_error"
    case repeatedError = "repeated_error"
    case strategyMismatch = "strategy_mismatch"
    case weeklyTransfer = "weekly_transfer"

    var title: String {
        switch self {
        case .highConfidenceError: NFAppLocalization.localized("Confidence check", locale: NFAppLocalization.preferredLocale, comment: "Title for a reflection triggered by an incorrect high-confidence answer.")
        case .repeatedError: NFAppLocalization.localized("Pattern check", locale: NFAppLocalization.preferredLocale, comment: "Title for a reflection triggered by a repeated deterministic error code.")
        case .strategyMismatch: NFAppLocalization.localized("Strategy check", locale: NFAppLocalization.preferredLocale, comment: "Title for a reflection triggered by a strategy mismatch.")
        case .weeklyTransfer: NFAppLocalization.localized("Transfer reflection", locale: NFAppLocalization.preferredLocale, comment: "Title for a reflection after a weekly transfer mission.")
        }
    }
}

enum PrescriptionReason: String, Codable, CaseIterable, Sendable {
    case goalPriority = "goal_priority"
    case reviewDue = "review_due"
    case skillGap = "skill_gap"
    case estimateUncertain = "estimate_uncertain"
    case transferGap = "transfer_gap"
    case errorPattern = "error_pattern"
    case representationCoverage = "representation_coverage"
    case calibration
    case variety
    case userOverride = "user_override"

    var title: String {
        switch self {
        case .goalPriority: NFAppLocalization.localized("Aligned with your goals", locale: NFAppLocalization.preferredLocale, comment: "Reason a training block was selected.")
        case .reviewDue: NFAppLocalization.localized("Review is due", locale: NFAppLocalization.preferredLocale, comment: "Reason a retention-review block was selected.")
        case .skillGap: NFAppLocalization.localized("Targeted skill gap", locale: NFAppLocalization.preferredLocale, comment: "Reason a training block was selected based on app-specific evidence.")
        case .estimateUncertain: NFAppLocalization.localized("Builds clearer evidence", locale: NFAppLocalization.preferredLocale, comment: "Reason a training block was selected to reduce estimate uncertainty.")
        case .transferGap: NFAppLocalization.localized("Tests transfer", locale: NFAppLocalization.preferredLocale, comment: "Reason a training block was selected. Transfer means applying a skill in an unfamiliar context.")
        case .errorPattern: NFAppLocalization.localized("Revisits an error pattern", locale: NFAppLocalization.preferredLocale, comment: "Reason a training block was selected.")
        case .representationCoverage: NFAppLocalization.localized("Adds a new representation", locale: NFAppLocalization.preferredLocale, comment: "Reason a training block was selected.")
        case .calibration: NFAppLocalization.localized("Calibrates confidence", locale: NFAppLocalization.preferredLocale, comment: "Reason a training block was selected to compare confidence with correctness.")
        case .variety: NFAppLocalization.localized("Maintains variety", locale: NFAppLocalization.preferredLocale, comment: "Reason a training block was selected.")
        case .userOverride: NFAppLocalization.localized("Chosen by you", locale: NFAppLocalization.preferredLocale, comment: "Reason a replacement training block was selected.")
        }
    }
}

enum TrainingLab: String, Codable, CaseIterable, Identifiable, Sendable {
    case mentalMath
    case spatial
    case quantitative
    case scientificReasoning
    case logicDebugging
    case retrieval
    case transfer

    var id: String { rawValue }

    var title: String { localizedTitle(locale: NFAppLocalization.preferredLocale) }

    func localizedTitle(locale: Locale) -> String {
        switch self {
        case .mentalMath: NFAppLocalization.localized("Mental Mathematics", locale: locale, comment: "Name of a training lab.")
        case .spatial: NFAppLocalization.localized("Spatial Reasoning", locale: locale, comment: "Name of a training lab.")
        case .quantitative: NFAppLocalization.localized("Quantitative Intuition", locale: locale, comment: "Name of a training lab.")
        case .scientificReasoning: NFAppLocalization.localized("Scientific Reasoning", locale: locale, comment: "Name of a training lab.")
        case .logicDebugging: NFAppLocalization.localized("Logic & Debugging", locale: locale, comment: "Name of a training lab.")
        case .retrieval: NFAppLocalization.localized("Retrieval Practice", locale: locale, comment: "Name of a training lab. Retrieval means recalling learned material.")
        case .transfer: NFAppLocalization.localized("Transfer Lab", locale: locale, comment: "Name of a training lab. Transfer means applying a skill in an unfamiliar context.")
        }
    }

    var shortTitle: String { localizedShortTitle(locale: NFAppLocalization.preferredLocale) }

    func localizedShortTitle(locale: Locale) -> String {
        switch self {
        case .mentalMath: NFAppLocalization.localized("Mental Math", locale: locale, comment: "Short name of the Mental Mathematics lab.")
        case .scientificReasoning: NFAppLocalization.localized("Science & Data", locale: locale, comment: "Short name of the Scientific Reasoning lab.")
        case .logicDebugging: NFAppLocalization.localized("Logic", locale: locale, comment: "Short name of the Logic and Debugging lab.")
        case .quantitative: NFAppLocalization.localized("Quantitative", locale: locale, comment: "Short name of the Quantitative Intuition lab.")
        case .spatial: NFAppLocalization.localized("Spatial", locale: locale, comment: "Short name of the Spatial Reasoning lab.")
        case .retrieval: NFAppLocalization.localized("Retrieval", locale: locale, comment: "Short name of the Retrieval Practice lab.")
        case .transfer: NFAppLocalization.localized("Transfer", locale: locale, comment: "Short name of the Transfer Lab.")
        }
    }

    var subtitle: String { localizedSubtitle(locale: NFAppLocalization.preferredLocale) }

    func localizedSubtitle(locale: Locale) -> String {
        switch self {
        case .mentalMath: NFAppLocalization.localized("Fluency, estimation, and numerical control", locale: locale, comment: "Description of the Mental Mathematics lab.")
        case .spatial: NFAppLocalization.localized("Transformations across diagrams and 3D forms", locale: locale, comment: "Description of the Spatial Reasoning lab.")
        case .quantitative: NFAppLocalization.localized("Magnitude, uncertainty, and probability", locale: locale, comment: "Description of the Quantitative Intuition lab.")
        case .scientificReasoning: NFAppLocalization.localized("Experiments, figures, and causal claims", locale: locale, comment: "Description of the Scientific Reasoning lab.")
        case .logicDebugging: NFAppLocalization.localized("Assumptions, edge cases, and state tracking", locale: locale, comment: "Description of the Logic and Debugging lab.")
        case .retrieval: NFAppLocalization.localized("Durable recall from your own materials", locale: locale, comment: "Description of the Retrieval Practice lab.")
        case .transfer: NFAppLocalization.localized("Apply familiar structure in unfamiliar contexts", locale: locale, comment: "Description of the Transfer Lab.")
        }
    }

    var symbol: String {
        switch self {
        case .mentalMath: "function"
        case .spatial: "cube.transparent"
        case .quantitative: "chart.xyaxis.line"
        case .scientificReasoning: "flask.fill"
        case .logicDebugging: "point.3.connected.trianglepath.dotted"
        case .retrieval: "text.book.closed.fill"
        case .transfer: "arrow.triangle.swap"
        }
    }

    var colorToken: String {
        switch self {
        case .mentalMath: "indigo"
        case .spatial: "cyan"
        case .quantitative: "orange"
        case .scientificReasoning: "green"
        case .logicDebugging: "purple"
        case .retrieval: "blue"
        case .transfer: "pink"
        }
    }

    var skillID: String { "skill.\(rawValue)" }
}

enum NFClaimsPolicy {
    static let currentVersion = 1
}

struct OnboardingDraft: Codable, Equatable, Sendable {
    var stage: Stage = .undisclosed
    var fields: Set<STEMField> = [.general]
    var goals: Set<TrainingGoal> = [.mentalMath, .dataReasoning]
    var dailyDuration: Int = 5
    var timingMode: TimingMode = .untimed
    var aiMode: AIMode = .automatic
    var iCloudEnabled: Bool = false
    var reducedMotion: Bool = false
    var hideTimers: Bool = false
    var excludeVisualSpatial: Bool = false
    var preferredLanguageCode: String = Locale.current.language.languageCode?.identifier == "ja" ? "ja" : "en"
    var trainingDays: Set<Int> = Set(1...7)
    var dayBoundaryHour: Int = 4
    /// Optional so drafts saved by an earlier build still decode and fail closed.
    var claimsPolicyAcknowledgedVersion: Int?
    var ageBandAcknowledged16Plus: Bool = false
    var preferredAnswerMode: NFPreferredAnswerMode = .adaptive
    var keyboardLatencyMilliseconds: Double?
    var touchLatencyMilliseconds: Double?
    var pencilLatencyMilliseconds: Double?
    var reinforcementHapticsEnabled: Bool = false
    var reinforcementSoundEnabled: Bool = false
    var startBaselineImmediately: Bool = false

    var hasInputCalibrationSample: Bool {
        keyboardLatencyMilliseconds != nil
            || touchLatencyMilliseconds != nil
            || pencilLatencyMilliseconds != nil
    }

    var hasCurrentClaimsAcknowledgement: Bool {
        claimsPolicyAcknowledgedVersion == NFClaimsPolicy.currentVersion
    }
}

struct ProfileSnapshot: Sendable {
    let id: UUID
    let stage: Stage
    let fields: Set<STEMField>
    let goals: Set<TrainingGoal>
    let dailyDuration: Int
    let timingMode: TimingMode
    let aiMode: AIMode
    let iCloudEnabled: Bool
    let trainingDays: Set<Int>
    let dayBoundaryHour: Int

    init(
        id: UUID,
        stage: Stage,
        fields: Set<STEMField>,
        goals: Set<TrainingGoal>,
        dailyDuration: Int,
        timingMode: TimingMode,
        aiMode: AIMode,
        iCloudEnabled: Bool,
        trainingDays: Set<Int> = Set(1...7),
        dayBoundaryHour: Int = 4
    ) {
        self.id = id
        self.stage = stage
        self.fields = fields
        self.goals = goals
        self.dailyDuration = dailyDuration
        self.timingMode = timingMode
        self.aiMode = aiMode
        self.iCloudEnabled = iCloudEnabled
        self.trainingDays = trainingDays.isEmpty ? Set(1...7) : trainingDays
        self.dayBoundaryHour = min(12, max(0, dayBoundaryHour))
    }
}

struct PlanBlock: Identifiable, Codable, Hashable, Sendable {
    let id: String
    let lab: TrainingLab
    let title: String
    let detail: String
    let minutes: Int
    let reasons: [PrescriptionReason]
    let evidenceClass: EvidenceClass
    let offlineReady: Bool
    var kindRaw: String? = nil
    var mechanicID: String = ""
    var timed: Bool = false
    var retentionItemIDs: [String] = []
    /// The skill selected by the scheduler before a cross-cutting lab (such as
    /// Transfer) is chosen for presentation. Optional so plans encoded before
    /// this field was introduced remain decodable.
    var targetSkillID: String? = nil
}

struct DailyPlan: Codable, Sendable {
    let id: String
    let localDayKey: String
    let seed: UInt64
    let policyVersion: Int
    let minutes: Int
    let blocks: [PlanBlock]
}

struct AttemptDTO: Identifiable, Sendable {
    let responseFormatRaw: String?
    let wasSkipped: Bool
    let hintCount: Int
    let editorialObservation: NFEditorialObservation?
    let id: UUID
    let itemID: String
    let alternateFormID: String
    let skillID: String
    let skillWeights: [String: Double]
    let lab: TrainingLab
    let correct: Bool
    let credit: Double
    let confidence: ConfidenceLevel?
    let submittedAt: Date
    let evidenceClass: EvidenceClass
    let evidenceWeight: Double
    let interruptionCount: Int
    let accommodationFlags: Set<String>
    let wasTimed: Bool
    let spatialDifficultyParameters: NFSpatialDifficultyParameters?
    let assessmentFormat: NFAssessmentItemFormat?

    var assessmentDimension: NFAssessmentDimension? {
        NFAssessmentDimension.from(skillID: skillID)
    }

    init(
        id: UUID,
        itemID: String? = nil,
        alternateFormID: String? = nil,
        skillID: String,
        skillWeights: [String: Double]? = nil,
        lab: TrainingLab,
        correct: Bool,
        credit: Double? = nil,
        confidence: ConfidenceLevel?,
        submittedAt: Date,
        evidenceClass: EvidenceClass,
        evidenceWeight: Double,
        interruptionCount: Int = 0,
        accommodationFlags: Set<String> = [],
        wasTimed: Bool = false,
        spatialDifficultyParameters: NFSpatialDifficultyParameters? = nil,
        assessmentFormat: NFAssessmentItemFormat? = nil,
        editorialObservation: NFEditorialObservation? = nil,
        responseFormatRaw: String? = nil,
        wasSkipped: Bool = false,
        hintCount: Int = 0
    ) {
        self.responseFormatRaw = responseFormatRaw
        self.wasSkipped = wasSkipped
        self.hintCount = max(0, hintCount)
        self.editorialObservation = editorialObservation
        self.id = id
        self.itemID = itemID ?? id.uuidString
        self.alternateFormID = alternateFormID ?? itemID ?? id.uuidString
        self.skillID = skillID
        let suppliedWeights = skillWeights ?? [skillID: 1]
        let validWeights = suppliedWeights.filter { !$0.key.isEmpty && $0.value.isFinite && $0.value > 0 }
        let weightTotal = validWeights.values.reduce(0, +)
        self.skillWeights = weightTotal > 0
            ? validWeights.mapValues { $0 / weightTotal }
            : [skillID: 1]
        self.lab = lab
        self.correct = correct
        self.credit = credit ?? (correct ? 1 : 0)
        self.confidence = confidence
        self.submittedAt = submittedAt
        self.evidenceClass = evidenceClass
        self.evidenceWeight = max(0, evidenceWeight)
        self.interruptionCount = max(0, interruptionCount)
        self.accommodationFlags = accommodationFlags
        self.wasTimed = wasTimed
        self.spatialDifficultyParameters = spatialDifficultyParameters
        self.assessmentFormat = assessmentFormat
    }
}

struct SkillSummary: Identifiable, Sendable {
    let id: String
    let lab: TrainingLab
    let theta: Double
    let uncertainty: Double
    let evidenceCount: Int
    let accuracy: Double?
    let status: EstimateStatus
    let calibrationBias: Double?
    let lastTrained: Date?
}

enum MentalMathKind: String, Codable, Sendable {
    case multiplication
    case percentage
    case scientificNotation
    case estimation
}

struct MentalMathItem: Identifiable, Codable, Sendable {
    let id: String
    let templateID: String
    let seed: UInt64
    let kind: MentalMathKind
    let prompt: String
    let context: String
    let answer: Double
    let tolerance: Double
    let strategy: String
    let decisiveStep: String
    let difficulty: Double
    let evidenceClass: EvidenceClass
}

struct DeterministicScore: Sendable {
    let isCorrect: Bool
    let normalizedResponse: Double?
    let errorCode: String?
}

struct DeterministicFeedback: Sendable {
    let title: String
    let explanation: String
    let strategy: String
    let errorCode: String?
}

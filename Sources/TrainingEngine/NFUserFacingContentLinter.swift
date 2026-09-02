import Foundation

/// Release-gate lint for authored and generated learner-facing copy.
///
/// Stable identifiers are intentionally not inspected. Only strings rendered or
/// spoken to the learner are included, so content authors remain free to use
/// namespaced IDs internally while raw keys and unresolved templates fail closed
/// before an exercise reaches a plan.
enum NFUserFacingContentLinter {
    struct Violation: Equatable, Sendable, CustomStringConvertible {
        enum Rule: String, Equatable, Sendable {
            case unresolvedPlaceholder
            case rawIdentifier
            case repeatedWord
            case punctuationCollision
            case incorrectSingularGrammar
        }

        let field: String
        let rule: Rule
        let excerpt: String

        var description: String {
            "\(field):\(rule.rawValue):\(excerpt)"
        }
    }

    private struct Field {
        let name: String
        let value: String
    }

    static func firstViolation(in exercise: NFExercise) -> Violation? {
        lint(exercise).first
    }

    static func lint(_ exercise: NFExercise) -> [Violation] {
        fields(in: exercise).compactMap { lint($0.value, field: $0.name) }
    }

    static func lint(_ descriptor: NFReleaseContentDescriptor) -> [Violation] {
        [
            Field(name: "descriptor.title", value: descriptor.title),
            Field(name: "descriptor.content", value: descriptor.content)
        ].compactMap { lint($0.value, field: $0.name) }
    }

    static func lint(_ text: String, field: String = "text") -> Violation? {
        let normalized = text.precomposedStringWithCanonicalMapping
        guard !normalized.isEmpty else { return nil }

        let rules: [(Violation.Rule, NSRegularExpression)] = regexRules
        let fullRange = NSRange(normalized.startIndex..<normalized.endIndex, in: normalized)
        for (rule, regex) in rules {
            guard let match = regex.firstMatch(in: normalized, range: fullRange),
                  let range = Range(match.range, in: normalized) else { continue }
            return Violation(
                field: field,
                rule: rule,
                excerpt: String(normalized[range]).prefix(80).description
            )
        }
        return nil
    }

    private static let regexRules: [(Violation.Rule, NSRegularExpression)] = [
        (
            .unresolvedPlaceholder,
            try! NSRegularExpression(
                pattern: #"(?i)(?:\$\{[^}]+\}|\{\{[^}]+\}\}|%(?:\d+\$)?(?:@|lld|ld|d|f|s)|<\s*(?:target|source|skill|topic|field|value|name)[^>]*>|\b(?:the\s+)?(?:target|source)\s+skill\b)"#
            )
        ),
        (
            .rawIdentifier,
            try! NSRegularExpression(
                pattern: #"(?i)\b(?:(?:target|skill|claim|evidence|error|strategy)\.[a-z0-9_.:+-]+|[a-z][a-z0-9]+(?:_[a-z][a-z0-9]+)+)\b"#
            )
        ),
        (
            .repeatedWord,
            try! NSRegularExpression(
                pattern: #"(?i)\b((?!(?:had|that)\b)[\p{L}][\p{L}'’-]+)\s+\1\b"#
            )
        ),
        (
            .punctuationCollision,
            try! NSRegularExpression(pattern: #"(?:[.!?][,;:]|[,;:][.!?]|;;+)"#)
        ),
        (
            .incorrectSingularGrammar,
            try! NSRegularExpression(
                pattern: #"(?i)\b1\s+(?:answers|attempts|blocks|chapters|days|exercises|items|minutes|questions|seconds|skills|sources|weeks)\b"#
            )
        )
    ]

    private static func fields(in exercise: NFExercise) -> [Field] {
        var result = [
            Field(name: "title", value: exercise.title),
            Field(name: "prompt", value: exercise.prompt),
            Field(name: "instructions", value: exercise.instructions),
            Field(name: "feedback.correctTitle", value: exercise.feedback.correctTitle),
            Field(name: "feedback.correctExplanation", value: exercise.feedback.correctExplanation),
            Field(name: "feedback.retryTitle", value: exercise.feedback.retryTitle),
            Field(name: "feedback.retryExplanation", value: exercise.feedback.retryExplanation),
            Field(name: "feedback.decisiveStep", value: exercise.feedback.decisiveStep),
            Field(name: "accessibility.prompt", value: exercise.accessibility.promptAccessibilityLabel)
        ]
        if let context = exercise.contextText {
            result.append(Field(name: "context", value: context))
        }
        if let alternative = exercise.accessibility.visualAlternative {
            result.append(Field(name: "accessibility.visualAlternative", value: alternative))
        }

        for (index, strategy) in exercise.strategies.enumerated() {
            result.append(Field(name: "strategies[\(index)].title", value: strategy.title))
            result.append(Field(name: "strategies[\(index)].summary", value: strategy.summary))
            result.append(Field(name: "strategies[\(index)].whenToUse", value: strategy.whenToUse))
            for (stepIndex, step) in strategy.orderedSteps.enumerated() {
                result.append(Field(name: "strategies[\(index)].steps[\(stepIndex)]", value: step))
            }
        }
        for (index, criterion) in exercise.rubric.criteria.enumerated() {
            result.append(Field(name: "rubric.criteria[\(index)]", value: criterion.description))
        }
        for (index, hint) in exercise.feedback.hintLadder.enumerated() {
            result.append(Field(name: "feedback.hints[\(index)]", value: hint))
        }
        for (key, explanation) in exercise.feedback.errorExplanations {
            result.append(Field(name: "feedback.errors[\(key)]", value: explanation))
        }

        appendInteractionFields(exercise.interaction, to: &result)
        appendRepresentationFields(exercise.representations, to: &result)
        return result
    }

    private static func appendInteractionFields(_ interaction: NFExerciseInteraction, to fields: inout [Field]) {
        switch interaction {
        case let .numeric(schema):
            fields.append(Field(name: "interaction.numeric.placeholder", value: schema.placeholder))
        case let .singleChoice(schema):
            appendChoiceFields(schema.options, prefix: "interaction.singleChoice", to: &fields)
        case let .multipleChoice(schema):
            appendChoiceFields(schema.options, prefix: "interaction.multipleChoice", to: &fields)
        case let .orderedSteps(schema):
            for (index, step) in schema.steps.enumerated() {
                fields.append(Field(name: "interaction.steps[\(index)]", value: step.text))
            }
        case let .shortText(schema):
            fields.append(Field(name: "interaction.shortText.expectedAnswer", value: schema.expectedAnswer))
            appendShortTextRuleFields(schema.scoringRule, to: &fields)
        case let .selfCheck(schema):
            fields.append(Field(name: "interaction.selfCheck.referenceAnswer", value: schema.referenceAnswer))
            for (index, criterion) in schema.criteria.enumerated() {
                fields.append(Field(name: "interaction.selfCheck.criteria[\(index)]", value: criterion))
            }
        case let .claimEvidence(schema):
            for (index, claim) in schema.claims.enumerated() {
                fields.append(Field(name: "interaction.claims[\(index)]", value: claim.text))
            }
            for (index, evidence) in schema.evidence.enumerated() {
                fields.append(Field(name: "interaction.evidence[\(index)]", value: evidence.text))
            }
        case let .logicState(schema):
            appendChoiceFields(schema.ruleOptions, prefix: "interaction.logic.rules", to: &fields)
            for (key, value) in schema.initialState {
                fields.append(Field(name: "interaction.logic.initial[\(key)]", value: value))
            }
            for (key, value) in schema.expectedFinalState {
                fields.append(Field(name: "interaction.logic.expected[\(key)]", value: value))
            }
        }
    }

    private static func appendChoiceFields(_ options: [NFChoiceOption], prefix: String, to fields: inout [Field]) {
        for (index, option) in options.enumerated() {
            fields.append(Field(name: "\(prefix)[\(index)].text", value: option.text))
            if let label = option.accessibilityLabel {
                fields.append(Field(name: "\(prefix)[\(index)].accessibilityLabel", value: label))
            }
        }
    }

    private static func appendShortTextRuleFields(_ rule: NFShortTextScoringRule, to fields: inout [Field]) {
        switch rule {
        case let .normalizedExact(acceptedAnswers):
            for (index, answer) in acceptedAnswers.enumerated() {
                fields.append(Field(name: "interaction.shortText.accepted[\(index)]", value: answer))
            }
        case let .requiredTerms(terms, _):
            for (index, term) in terms.enumerated() {
                fields.append(Field(name: "interaction.shortText.term[\(index)]", value: term))
            }
        case let .constrainedConcepts(acceptedAnswers, requiredTerms, _, rejectedAssertions):
            for (index, answer) in acceptedAnswers.enumerated() {
                fields.append(Field(name: "interaction.shortText.accepted[\(index)]", value: answer))
            }
            for (index, term) in requiredTerms.enumerated() {
                fields.append(Field(name: "interaction.shortText.term[\(index)]", value: term))
            }
            for (index, assertion) in rejectedAssertions.enumerated() {
                fields.append(Field(name: "interaction.shortText.rejected[\(index)]", value: assertion))
            }
        }
    }

    private static func appendRepresentationFields(_ representations: [NFExerciseRepresentation], to fields: inout [Field]) {
        for (index, representation) in representations.enumerated() {
            switch representation {
            case let .spatial(metadata):
                fields.append(Field(name: "representations[\(index)].object", value: metadata.objectDescription))
                fields.append(Field(name: "representations[\(index)].accessibility", value: metadata.accessibilityDescription))
                for (labelIndex, label) in metadata.axisLabels.enumerated() {
                    fields.append(Field(name: "representations[\(index)].axes[\(labelIndex)]", value: label))
                }
            case let .logicState(metadata):
                fields.append(Field(name: "representations[\(index)].traceLanguage", value: metadata.traceLanguage))
                for (key, value) in metadata.variables {
                    fields.append(Field(name: "representations[\(index)].variables[\(key)]", value: value))
                }
                for (transitionIndex, transition) in metadata.transitions.enumerated() {
                    fields.append(Field(name: "representations[\(index)].transitions[\(transitionIndex)].condition", value: transition.condition))
                    fields.append(Field(name: "representations[\(index)].transitions[\(transitionIndex)].mutation", value: transition.mutation))
                }
                for (key, value) in metadata.invariants {
                    fields.append(Field(name: "representations[\(index)].invariants[\(key)]", value: value))
                }
            case let .equation(_, spokenDescription):
                fields.append(Field(name: "representations[\(index)].spokenEquation", value: spokenDescription))
            case let .table(headers, rows, accessibilitySummary):
                for (headerIndex, header) in headers.enumerated() {
                    fields.append(Field(name: "representations[\(index)].headers[\(headerIndex)]", value: header))
                }
                for (rowIndex, row) in rows.enumerated() {
                    for (columnIndex, value) in row.enumerated() {
                        fields.append(Field(name: "representations[\(index)].rows[\(rowIndex)][\(columnIndex)]", value: value))
                    }
                }
                fields.append(Field(name: "representations[\(index)].accessibility", value: accessibilitySummary))
            case let .code(_, _, accessibilitySummary):
                fields.append(Field(name: "representations[\(index)].accessibility", value: accessibilitySummary))
            case .prose:
                break
            }
        }
    }
}

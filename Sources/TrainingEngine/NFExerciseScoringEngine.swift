import Foundation

enum NFExerciseValidationError: Error, Equatable, Sendable {
    case missingField(String)
    case invalidVersion(String)
    case invalidDifficulty(String)
    case invalidSkillWeights
    case evidencePurposeMismatch
    case assessmentProtectionMismatch
    case holdoutNamespaceViolation
    case feedbackTimingMismatch
    case unsupportedScoringAuthority
    case sourceGroundingViolation(String)
    case invalidResponseSchema(String)
    case invalidUserFacingContent(String)
}

enum NFExerciseSchemaValidator {
    static let validatorVersion = 2
    // Authored sets use schema 1; static fallback uses 2; pinned linked science uses 3.
    // Enumerate known contracts rather than accepting arbitrary positive values.
    static let supportedExerciseSchemaVersions: Set<Int> = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14]
    static func supportsExerciseSchemaVersion(_ version: Int) -> Bool {
        supportedExerciseSchemaVersions.contains(version)
    }

    static func validate(_ exercise: NFExercise) throws {
        let requiredFields: [(String, String)] = [
            ("id", exercise.id),
            ("templateID", exercise.templateID),
            ("templateFamily", exercise.templateFamily),
            ("localeIdentifier", exercise.localeIdentifier),
            ("title", exercise.title),
            ("prompt", exercise.prompt),
            ("instructions", exercise.instructions),
            ("provenance.generatorID", exercise.provenance.generatorID),
            ("provenance.contentDigest", exercise.provenance.contentDigest)
        ]
        for (name, value) in requiredFields where value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw NFExerciseValidationError.missingField(name)
        }

        guard supportsExerciseSchemaVersion(exercise.schemaVersion),
              exercise.generatorVersion > 0,
              exercise.templateVersion > 0,
              exercise.provenance.generatorVersion > 0,
              exercise.provenance.validatorVersion == validatorVersion else {
            throw NFExerciseValidationError.invalidVersion("exercise or provenance")
        }

        let boundedDifficultyValues = [
            exercise.difficulty.overall,
            exercise.difficulty.abstraction,
            exercise.difficulty.representationShift,
            exercise.difficulty.priorKnowledge,
            exercise.difficulty.timePressure
        ]
        guard boundedDifficultyValues.allSatisfy({ $0.isFinite && (0...1).contains($0) }),
              exercise.difficulty.reasoningSteps > 0 else {
            throw NFExerciseValidationError.invalidDifficulty("values must be finite and bounded")
        }

        guard !exercise.skillWeights.isEmpty,
              exercise.skillWeights.values.allSatisfy({ $0.isFinite && $0 > 0 && $0 <= 1 }),
              abs(exercise.skillWeights.values.reduce(0, +) - 1) <= 0.000_001 else {
            throw NFExerciseValidationError.invalidSkillWeights
        }

        guard exercise.evidenceClass == exercise.purpose.evidenceClass else {
            throw NFExerciseValidationError.evidencePurposeMismatch
        }
        guard exercise.assessmentProtected == exercise.purpose.isProtectedAssessment else {
            throw NFExerciseValidationError.assessmentProtectionMismatch
        }
        if exercise.assessmentProtected {
            let requiredToken = exercise.purpose == .baseline ? ".baseline." : ".holdout."
            guard exercise.templateFamily.contains(requiredToken) else {
                throw NFExerciseValidationError.holdoutNamespaceViolation
            }
        }

        let expectedTiming: NFExerciseFeedbackTiming = exercise.purpose.delaysFeedback
            ? .afterAssessmentBlock
            : .immediate
        guard exercise.feedback.timing == expectedTiming else {
            throw NFExerciseValidationError.feedbackTimingMismatch
        }

        if let rubric = exercise.aiRubric {
            guard exercise.schemaVersion == 14, rubric.isValid, !exercise.assessmentProtected,
                  exercise.rubric.criteria == rubric.criteria,
                  exercise.rubric.permitsPartialCredit,
                  case .shortText = exercise.interaction else {
                throw NFExerciseValidationError.unsupportedScoringAuthority
            }
        } else if exercise.schemaVersion == 14 {
            throw NFExerciseValidationError.unsupportedScoringAuthority
        }
        guard exercise.provenance.contentTier != .freeFormAI || exercise.aiRubric != nil else {
            throw NFExerciseValidationError.unsupportedScoringAuthority
        }
        if exercise.provenance.contentTier == .sourceGroundedAI {
            guard exercise.evidenceClass == .documentPractice,
                  exercise.provenance.isSourceGrounded,
                  !exercise.citations.isEmpty else {
                throw NFExerciseValidationError.sourceGroundingViolation("source-grounded AI is personal practice only")
            }
        }
        if exercise.provenance.isSourceGrounded {
            guard exercise.evidenceClass == .documentPractice,
                  exercise.purpose == .documentPractice,
                  !exercise.assessmentProtected else {
                throw NFExerciseValidationError.sourceGroundingViolation("personal sources cannot become standardized evidence")
            }
            let documentIDs = Set(exercise.sourceContext.sourceDocumentIDs)
            let chunkIDs = Set(exercise.sourceContext.sourceChunkIDs)
            guard !documentIDs.isEmpty else {
                throw NFExerciseValidationError.sourceGroundingViolation("missing source document")
            }
            for citation in exercise.citations {
                guard documentIDs.contains(citation.documentID) else {
                    throw NFExerciseValidationError.sourceGroundingViolation("citation document is outside context")
                }
                if let sourceChunkID = citation.sourceChunkID, !chunkIDs.contains(sourceChunkID) {
                    throw NFExerciseValidationError.sourceGroundingViolation("citation chunk is outside context")
                }
            }
            guard Set(exercise.provenance.sourceDocumentIDs) == Set(exercise.citations.map(\.documentID)),
                  Set(exercise.provenance.sourceChunkIDs) == Set(exercise.citations.compactMap(\.sourceChunkID)) else {
                throw NFExerciseValidationError.sourceGroundingViolation("provenance does not match citations")
            }
        }

        guard exercise.expectedDurationSeconds > 0 else {
            throw NFExerciseValidationError.invalidResponseSchema("duration must be positive")
        }
        guard !exercise.rubric.criteria.isEmpty,
              exercise.rubric.criteria.allSatisfy({
                  !$0.id.isEmpty && !$0.description.isEmpty && $0.weight.isFinite && $0.weight > 0
              }),
              abs(exercise.rubric.criteria.map(\.weight).reduce(0, +) - 1) <= 0.000_001,
              exercise.rubric.fullCreditThreshold.isFinite,
              (0...1).contains(exercise.rubric.fullCreditThreshold) else {
            throw NFExerciseValidationError.invalidResponseSchema("invalid rubric")
        }
        guard !exercise.strategies.isEmpty else {
            throw NFExerciseValidationError.invalidResponseSchema("missing deterministic strategy")
        }
        if exercise.accessibility.requiresVisualSpatialProcessing,
           exercise.accessibility.visualAlternative?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false {
            throw NFExerciseValidationError.invalidResponseSchema("visual exercise requires an accessibility alternative")
        }
        for case let .spatial(metadata) in exercise.representations {
            let parameters = metadata.difficultyParameters
            guard NFSpatialRenderingSafety.permits(metadata),
                  !parameters.viewpoint.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  parameters.viewpoint == metadata.viewpoint,
                  parameters.rotationMagnitudeDegrees.isFinite,
                  (0...360).contains(parameters.rotationMagnitudeDegrees),
                  parameters.objectComplexity.isFinite,
                  (0...1).contains(parameters.objectComplexity),
                  parameters.distractorSimilarity.isFinite,
                  (0...1).contains(parameters.distractorSimilarity) else {
                throw NFExerciseValidationError.invalidDifficulty("invalid spatial difficulty parameter vector")
            }
        }
        guard exercise.hasSupportedSpatialAssembly, exercise.hasSupportedCoordinateReasoning, exercise.hasSupportedNetFolding, exercise.hasSupportedSolidSection, exercise.hasSupportedCoordinateTransform, exercise.hasSupportedSpatialStructure, exercise.hasSupportedRetrievalAsset, exercise.hasSupportedRetrievalAuthorityRecipe else {
            throw NFExerciseValidationError.invalidResponseSchema("unsupported retrieval authority recipe")
        }
        guard exercise.hasSupportedTransferRelationship else {
            throw NFExerciseValidationError.invalidResponseSchema("unsupported linked transfer contract")
        }
        guard exercise.hasSupportedGraphConstruction, exercise.hasSupportedScienceStudy else {
            throw NFExerciseValidationError.invalidResponseSchema("unsupported linked study contract")
        }
        guard exercise.hasSupportedTraceContract else {
            throw NFExerciseValidationError.invalidResponseSchema("unsupported state trace contract")
        }
        try validateInteraction(exercise.interaction)
        if let violation = NFUserFacingContentLinter.firstViolation(in: exercise) {
            throw NFExerciseValidationError.invalidUserFacingContent(violation.description)
        }
    }

    static func validateInteraction(_ interaction: NFExerciseInteraction) throws {
        switch interaction {
        case let .numeric(schema):
            guard schema.answer.value.isFinite,
                  schema.answer.displayPrecision >= 0,
                  validTolerance(schema.answer.tolerance),
                  schema.answer.authoritativeTolerance.isNonnegative else {
                throw NFExerciseValidationError.invalidResponseSchema("invalid numeric answer")
            }
            if schema.answer.unitRequired {
                guard let unit = schema.answer.canonicalUnit, !unit.isEmpty else {
                    throw NFExerciseValidationError.invalidResponseSchema("required unit has no canonical unit")
                }
            }

        case let .singleChoice(schema):
            let IDs = schema.options.map(\.id)
            guard schema.options.count >= 2,
                  Set(IDs).count == IDs.count,
                  IDs.contains(schema.correctOptionID),
                  NFAnswerSemanticIdentity.hasDistinctOptions(schema.options) else {
                throw NFExerciseValidationError.invalidResponseSchema("single-choice key or options")
            }

        case let .multipleChoice(schema):
            let IDs = schema.options.map(\.id)
            let correct = Set(schema.correctOptionIDs)
            guard schema.options.count >= 2,
                  Set(IDs).count == IDs.count,
                  !correct.isEmpty,
                  correct.isSubset(of: Set(IDs)),
                  schema.minimumSelections >= 1,
                  schema.maximumSelections >= schema.minimumSelections,
                  schema.maximumSelections <= schema.options.count,
                  (schema.acceptedAlternativeSets ?? []).allSatisfy({
                      !$0.isEmpty && Set($0).count == $0.count && Set($0).isSubset(of: Set(IDs))
                          && $0.count >= schema.minimumSelections && $0.count <= schema.maximumSelections
                  }) else {
                throw NFExerciseValidationError.invalidResponseSchema("multiple-choice key or bounds")
            }

        case let .orderedSteps(schema):
            let IDs = schema.steps.map(\.id)
            guard schema.steps.count >= 2,
                  Set(IDs).count == IDs.count,
                  Set(IDs) == Set(schema.correctOrder),
                  schema.correctOrder.count == IDs.count,
                  NFOrderingAuthority.isValid(schema) else {
                throw NFExerciseValidationError.invalidResponseSchema("ordered-step key")
            }

        case let .shortText(schema):
            guard !schema.expectedAnswer.isEmpty, schema.maximumCharacters > 0 else {
                throw NFExerciseValidationError.invalidResponseSchema("short-text answer")
            }
            if case let .symbolic(contract)? = schema.authority {
                guard NFRestrictedSymbolicAuthority.compare(contract.acceptedExpressions.first ?? "", contract: contract) == .equivalent else {
                    throw NFExerciseValidationError.invalidResponseSchema("unsupported symbolic authority")
                }
            }
            if case let .unsignedBinaryNumeral(contract)? = schema.authority, !contract.isSupported {
                throw NFExerciseValidationError.invalidResponseSchema("unsupported binary numeral authority")
            }
            switch schema.scoringRule {
            case let .normalizedExact(acceptedAnswers):
                guard !acceptedAnswers.isEmpty, acceptedAnswers.allSatisfy({ !$0.isEmpty }) else {
                    throw NFExerciseValidationError.invalidResponseSchema("accepted short-text answers")
                }
            case let .requiredTerms(terms, minimumMatches):
                guard !terms.isEmpty, minimumMatches > 0, minimumMatches <= terms.count else {
                    throw NFExerciseValidationError.invalidResponseSchema("required short-text terms")
                }
            case let .constrainedConcepts(acceptedAnswers, requiredTerms, minimumMatches, rejectedAssertions):
                guard !acceptedAnswers.isEmpty,
                      acceptedAnswers.allSatisfy({ !$0.isEmpty }),
                      !requiredTerms.isEmpty,
                      minimumMatches > 0,
                      minimumMatches <= requiredTerms.count,
                      rejectedAssertions.allSatisfy({ !$0.isEmpty }) else {
                    throw NFExerciseValidationError.invalidResponseSchema("constrained short-text concepts")
                }
            }

        case let .selfCheck(schema):
            guard !schema.referenceAnswer.isEmpty, !schema.criteria.isEmpty else {
                throw NFExerciseValidationError.invalidResponseSchema("self-check reference")
            }

        case let .claimEvidence(schema):
            let claimIDs = Set(schema.claims.map(\.id))
            let evidenceIDs = Set(schema.evidence.map(\.id))
            let keyedClaimIDs = schema.correctPairs.map(\.claimID)
            guard !claimIDs.isEmpty,
                  !evidenceIDs.isEmpty,
                  Set(schema.claims.map(\.id)).count == schema.claims.count,
                  Set(schema.evidence.map(\.id)).count == schema.evidence.count,
                  Set(keyedClaimIDs) == claimIDs,
                  keyedClaimIDs.count == claimIDs.count else {
                throw NFExerciseValidationError.invalidResponseSchema("claim-evidence options")
            }
            if let scopes = schema.selectionScopes {
                guard scopes.count == claimIDs.count, Set(scopes.map(\.claimID)) == claimIDs,
                      scopes.allSatisfy({ scope in
                          scope.schemaVersion == 1 && !scope.evidenceIDs.isEmpty
                            && Set(scope.evidenceIDs).count == scope.evidenceIDs.count
                            && Set(scope.evidenceIDs).isSubset(of: evidenceIDs)
                            && scope.minimumSelections >= 0 && scope.maximumSelections >= scope.minimumSelections
                            && scope.maximumSelections <= scope.evidenceIDs.count
                      }), schema.correctPairs.allSatisfy({ pair in
                          guard let scope = scopes.first(where: { $0.claimID == pair.claimID }) else { return false }
                          return Set(pair.evidenceIDs).isSubset(of: Set(scope.evidenceIDs))
                            && (scope.minimumSelections...scope.maximumSelections).contains(pair.evidenceIDs.count)
                      }) else { throw NFExerciseValidationError.invalidResponseSchema("claim evidence selection scope") }
            }
            if let contracts = schema.supportContracts {
                guard Set(contracts.map(\.claimID)) == claimIDs,
                      contracts.count == claimIDs.count,
                      contracts.allSatisfy({ contract in
                          !contract.sufficientBundles.isEmpty && contract.sufficientBundles.allSatisfy {
                              !$0.isEmpty && Set($0).count == $0.count && Set($0).isSubset(of: evidenceIDs)
                          }
                      }) else { throw NFExerciseValidationError.invalidResponseSchema("claim support bundles") }
            }
            if let scopes = schema.selectionScopes, let contracts = schema.supportContracts {
                guard contracts.allSatisfy({ contract in
                    guard let scope = scopes.first(where: { $0.claimID == contract.claimID }) else { return false }
                    return contract.sufficientBundles.allSatisfy { bundle in
                        Set(bundle).isSubset(of: Set(scope.evidenceIDs))
                            && (scope.minimumSelections...scope.maximumSelections).contains(bundle.count)
                    }
                }) else { throw NFExerciseValidationError.invalidResponseSchema("claim support bundle scope") }
            }
            for pair in schema.correctPairs {
                guard claimIDs.contains(pair.claimID),
                      !pair.evidenceIDs.isEmpty,
                      Set(pair.evidenceIDs).count == pair.evidenceIDs.count,
                      Set(pair.evidenceIDs).isSubset(of: evidenceIDs) else {
                    throw NFExerciseValidationError.invalidResponseSchema("claim-evidence key")
                }
            }

        case let .logicState(schema):
            guard !schema.initialState.isEmpty,
                  !schema.expectedFinalState.isEmpty,
                  Set(schema.ruleOptions.map(\.id)).count == schema.ruleOptions.count,
                  schema.acceptedEquivalentStates.allSatisfy({ Set($0.keys) == Set(schema.expectedFinalState.keys) }) else {
                throw NFExerciseValidationError.invalidResponseSchema("logic-state key")
            }
            if let domains = schema.fieldDomains {
                let states = [schema.expectedFinalState] + schema.acceptedEquivalentStates
                guard Set(domains.keys) == Set(schema.expectedFinalState.keys),
                      states.allSatisfy({ state in state.allSatisfy { NFStateValueAuthority.isParseable($0.value, domain: domains[$0.key]) } }) else {
                    throw NFExerciseValidationError.invalidResponseSchema("typed logic-state values")
                }
            }
            guard !hasContradictoryEstimateExactNumericAliases(schema) else {
                throw NFExerciseValidationError.invalidResponseSchema("contradictory estimate-exact numeric aliases")
            }
            if let expectedRule = schema.expectedViolatedRuleID {
                guard schema.ruleOptions.contains(where: { $0.id == expectedRule }) else {
                    throw NFExerciseValidationError.invalidResponseSchema("unknown violated rule")
                }
            }
        }
    }

    /// This explicit contract promises a single exact numeric result. A regional
    /// display such as "9.504" cannot alias 9504 under the canonical decimal
    /// grammar. Estimates may legitimately differ, judgments may use reviewed
    /// labels, and unrelated logic tasks may have distinct accepted outputs.
    static func hasContradictoryEstimateExactNumericAliases(_ schema: NFLogicStateResponseSchema) -> Bool {
        guard NFEstimateExactContract.isComposite(schema),
              let exact = schema.expectedFinalState[NFEstimateExactContract.exactKey],
              let canonical = NFStateValueAuthority.exactNumber(exact) else { return false }
        return schema.acceptedEquivalentStates.contains { state in
            NFStateValueAuthority.exactNumber(state[NFEstimateExactContract.exactKey] ?? "") != canonical
        }
    }

    private static func validTolerance(_ tolerance: NFNumericTolerance) -> Bool {
        switch tolerance {
        case let .absolute(value), let .relative(value):
            value.isFinite && value >= 0
        case let .absoluteOrRelative(absolute, relative):
            absolute.isFinite && relative.isFinite && absolute >= 0 && relative >= 0
        }
    }
}

enum NFExerciseResponseValidationIssue: Equatable, Sendable {
    case responseTypeMismatch
    case numericMissing
    case numericInvalid
    case numericAmbiguous
    case numericNotation
    case unitMissing
    case unknownChoice
    case selectionBounds(minimum: Int, maximum: Int, actual: Int)
    case orderedStepsMembership
    case textMissing
    case textTooLong(maximum: Int, actual: Int)
    case selfCheckReflectionMissing
    case claimEvidenceUnknown
    case claimEvidenceRelationships(claim: String, expected: Int, actual: Int)
    case logicStateIncomplete
    case logicStateSyntax
    case logicRuleMissing
    case logicRuleUnknown

    var errorCode: String {
        switch self {
        case .responseTypeMismatch: "response_type_mismatch"
        case .numericMissing: "numeric_missing"
        case .numericInvalid: "numeric_input"
        case .numericAmbiguous: "numeric_ambiguous"
        case .numericNotation: "numeric_notation"
        case .unitMissing: "unit_missing"
        case .unknownChoice: "unknown_choice"
        case .selectionBounds: "selection_bounds"
        case .orderedStepsMembership: "ordered_steps_membership"
        case .textMissing: "text_missing"
        case .textTooLong: "text_too_long"
        case .selfCheckReflectionMissing: "self_check_reflection_missing"
        case .claimEvidenceUnknown: "claim_evidence_unknown"
        case .claimEvidenceRelationships: "claim_evidence_relationships"
        case .logicStateIncomplete: "logic_state_incomplete"
        case .logicStateSyntax: "logic_state_syntax"
        case .logicRuleMissing: "logic_rule_missing"
        case .logicRuleUnknown: "logic_rule_unknown"
        }
    }

    var guidance: String {
        switch self {
        case .responseTypeMismatch:
            return NFAppLocalization.localized("This response does not match the question.", locale: NFAppLocalization.preferredLocale, comment: "Response validation guidance when the submitted response kind does not match the authored interaction.")
        case .numericMissing:
            return NFAppLocalization.localized("Enter a number.", locale: NFAppLocalization.preferredLocale, comment: "Response validation guidance for an empty numeric answer.")
        case .numericInvalid:
            return NFAppLocalization.localized("Enter a valid number, fraction, or permitted exponent.", locale: NFAppLocalization.preferredLocale, comment: "Response validation guidance for a numeric answer that cannot be parsed exactly.")
        case .numericAmbiguous:
            return NFAppLocalization.localized("Use the decimal separator for this question’s locale and standard three-digit grouping.", locale: NFAppLocalization.preferredLocale, comment: "Response validation guidance for ambiguous localized numeric punctuation.")
        case .numericNotation:
            return NFAppLocalization.localized("This number format is not permitted for this question.", locale: NFAppLocalization.preferredLocale, comment: "Response validation guidance for notation disabled by the numeric response schema.")
        case .unitMissing:
            return NFAppLocalization.localized("Enter the required unit.", locale: NFAppLocalization.preferredLocale, comment: "Response validation guidance for a missing required unit.")
        case .unknownChoice:
            return NFAppLocalization.localized("Choose one of the available answers.", locale: NFAppLocalization.preferredLocale, comment: "Response validation guidance for an unavailable choice identifier.")
        case let .selectionBounds(minimum, maximum, actual):
            if minimum == maximum {
                return NFAppLocalization.localized("Select exactly \(NFAppLocalization.formattedAnswerCount(minimum)); \(actual) selected.", locale: NFAppLocalization.preferredLocale, comment: "Multiple-choice validation guidance; placeholders are the localized exact required count and current selected count.")
            }
            return NFAppLocalization.localized("Select \(minimum)–\(maximum) answers; \(actual) selected.", locale: NFAppLocalization.preferredLocale, comment: "Multiple-choice validation guidance; placeholders are the minimum, maximum, and current selected counts.")
        case .orderedStepsMembership:
            return NFAppLocalization.localized("Include every step exactly once.", locale: NFAppLocalization.preferredLocale, comment: "Ordered-step response validation guidance.")
        case .textMissing:
            return NFAppLocalization.localized("Enter an answer.", locale: NFAppLocalization.preferredLocale, comment: "Short-text response validation guidance for an empty answer.")
        case let .textTooLong(maximum, actual):
            return NFAppLocalization.localized("Shorten the answer to \(maximum) characters; it currently has \(actual).", locale: NFAppLocalization.preferredLocale, comment: "Short-text validation guidance; placeholders are the maximum and current character counts.")
        case .selfCheckReflectionMissing:
            return NFAppLocalization.localized("Enter your comparison before saving the self-check.", locale: NFAppLocalization.preferredLocale, comment: "Self-check response validation guidance for a missing comparison.")
        case .claimEvidenceUnknown:
            return NFAppLocalization.localized("Use only the claims and evidence shown in this question.", locale: NFAppLocalization.preferredLocale, comment: "Claim-and-evidence validation guidance for unknown or duplicate identifiers.")
        case let .claimEvidenceRelationships(claim, expected, actual):
            return NFAppLocalization.localized(
                "Select exactly \(NFAppLocalization.formattedEvidenceItemCount(expected)) for \(claim); \(actual) selected.",
                locale: NFAppLocalization.preferredLocale,
                comment: "Claim-and-evidence validation guidance with a localized required evidence-item count, visible claim label, and current count."
            )
        case .logicStateSyntax:
            return NFAppLocalization.localized("Use a valid number or true/false in each typed state field.", locale: NFAppLocalization.preferredLocale, comment: "State response guidance when a numeric or Boolean field cannot be parsed; no answer is revealed.")
        case .logicStateIncomplete:
            return NFAppLocalization.localized("Complete every required final-state field.", locale: NFAppLocalization.preferredLocale, comment: "Logic-state response validation guidance for incomplete state fields.")
        case .logicRuleMissing:
            return NFAppLocalization.localized("Select the violated rule.", locale: NFAppLocalization.preferredLocale, comment: "Logic-state response validation guidance for a missing required rule.")
        case .logicRuleUnknown:
            return NFAppLocalization.localized("Choose one of the available rules.", locale: NFAppLocalization.preferredLocale, comment: "Logic-state response validation guidance for an unavailable rule identifier.")
        }
    }
}

struct NFValidatedNumericSubmission: Equatable, Sendable {
    let value: NFExactNumber
    let canonicalInput: String
    let submittedUnit: String?
}

struct NFExerciseResponseValidation: Equatable, Sendable {
    let issue: NFExerciseResponseValidationIssue?
    let numericSubmission: NFValidatedNumericSubmission?

    var isValid: Bool { issue == nil }

    static let valid = NFExerciseResponseValidation(issue: nil, numericSubmission: nil)
}

/// One validation authority shared by every exercise runtime and the scorer.
/// It validates response shape and completeness without checking correctness,
/// so controls never reveal an answer merely by becoming enabled or disabled.
enum NFExerciseResponseValidator {
    static func validate(
        _ response: NFExerciseResponse,
        for interaction: NFExerciseInteraction,
        localeIdentifier: String = "en_US_POSIX"
    ) -> NFExerciseResponseValidation {
        switch (interaction, response) {
        case let (.numeric(schema), .numeric(submission)):
            return validateNumeric(submission, schema: schema, localeIdentifier: localeIdentifier)

        case let (.singleChoice(schema), .singleChoice(optionID)):
            guard schema.options.contains(where: { $0.id == optionID }) else {
                return invalid(.unknownChoice)
            }
            return .valid

        case let (.multipleChoice(schema), .multipleChoice(optionIDs)):
            let selected = Set(optionIDs)
            let available = Set(schema.options.map(\.id))
            guard selected.count == optionIDs.count, selected.isSubset(of: available) else {
                return invalid(.unknownChoice)
            }
            guard selected.count >= schema.minimumSelections,
                  selected.count <= schema.maximumSelections else {
                return invalid(.selectionBounds(
                    minimum: schema.minimumSelections,
                    maximum: schema.maximumSelections,
                    actual: selected.count
                ))
            }
            return .valid

        case let (.orderedSteps(schema), .orderedSteps(stepIDs)):
            let expected = Set(schema.steps.map(\.id))
            guard stepIDs.count == expected.count, Set(stepIDs) == expected else {
                return invalid(.orderedStepsMembership)
            }
            return .valid

        case let (.shortText(schema), .shortText(text)):
            guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return invalid(.textMissing)
            }
            guard text.count <= schema.maximumCharacters else {
                return invalid(.textTooLong(maximum: schema.maximumCharacters, actual: text.count))
            }
            return .valid

        case let (.selfCheck(schema), .selfCheck(submission)):
            if schema.asksForReflection,
               submission.reflection?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false {
                return invalid(.selfCheckReflectionMissing)
            }
            return .valid

        case let (.claimEvidence(schema), .claimEvidence(submission)):
            let validClaimIDs = Set(schema.claims.map(\.id))
            let validEvidenceIDs = Set(schema.evidence.map(\.id))
            let submittedClaimIDs = submission.pairs.map(\.claimID)
            guard submittedClaimIDs.count == Set(submittedClaimIDs).count,
                  Set(submittedClaimIDs) == validClaimIDs,
                  submission.pairs.allSatisfy({ pair in
                      pair.evidenceIDs.count == Set(pair.evidenceIDs).count
                          && Set(pair.evidenceIDs).isSubset(of: validEvidenceIDs)
                  }) else {
                return invalid(.claimEvidenceUnknown)
            }
            for scope in schema.selectionScopes ?? [] {
                guard scope.schemaVersion == 1, scope.minimumSelections >= 0, scope.maximumSelections >= scope.minimumSelections,
                      scope.maximumSelections <= scope.evidenceIDs.count,
                      let pair = submission.pairs.first(where: { $0.claimID == scope.claimID }),
                      Set(pair.evidenceIDs).isSubset(of: Set(scope.evidenceIDs)) else { return invalid(.claimEvidenceUnknown) }
                if !(scope.minimumSelections...scope.maximumSelections).contains(pair.evidenceIDs.count) {
                    return invalid(.selectionBounds(minimum: scope.minimumSelections, maximum: scope.maximumSelections, actual: pair.evidenceIDs.count))
                }
            }
            return .valid

        case let (.logicState(schema), .logicState(submission)):
            let requiredKeys = Set(schema.expectedFinalState.keys)
            guard Set(submission.finalState.keys) == requiredKeys,
                  submission.finalState.values.allSatisfy({
                      !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                  }) else {
                return invalid(.logicStateIncomplete)
            }
            guard submission.finalState.allSatisfy({ NFStateValueAuthority.isParseable($0.value, domain: schema.fieldDomains?[$0.key]) }) else {
                return invalid(.logicStateSyntax)
            }
            let availableRules = Set(schema.ruleOptions.map(\.id))
            if schema.expectedViolatedRuleID != nil, submission.violatedRuleID == nil {
                return invalid(.logicRuleMissing)
            }
            if let ruleID = submission.violatedRuleID, !availableRules.contains(ruleID) {
                return invalid(.logicRuleUnknown)
            }
            return .valid

        default:
            return invalid(.responseTypeMismatch)
        }
    }

    static func validateNumeric(
        _ submission: NFNumericSubmission,
        schema: NFNumericResponseSchema,
        localeIdentifier: String = "en_US_POSIX"
    ) -> NFExerciseResponseValidation {
        var number = submission.value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "−", with: "-")
        guard !number.isEmpty else { return invalid(.numericMissing) }
        var inlineUnit: String?
        if let regex = try? NSRegularExpression(pattern: #"^(.+?)\s+([A-Za-zµμ%][^\s]*)$"#),
           let match = regex.firstMatch(in: number, range: NSRange(number.startIndex..., in: number)),
           let valueRange = Range(match.range(at: 1), in: number),
           let unitRange = Range(match.range(at: 2), in: number) {
            inlineUnit = normalizeUnit(String(number[unitRange]))
            number = String(number[valueRange])
        }

        let hasInlinePercent = number.hasSuffix("%")
        if hasInlinePercent {
            number.removeLast()
            number = number.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard !number.isEmpty else { return invalid(.numericMissing) }
        if !schema.permitsScientificNotation,
           number.localizedCaseInsensitiveContains("e") {
            return invalid(.numericNotation)
        }

        let normalized: String
        switch normalizeLocalizedNumber(
            number,
            localeIdentifier: localeIdentifier,
            permitsGrouping: schema.permitsThousandsSeparators
        ) {
        case let .success(value):
            normalized = value
        case let .failure(issue):
            return invalid(issue)
        }
        guard let value = NFExactNumber(parsing: normalized) else {
            return invalid(.numericInvalid)
        }

        let typedUnit = submission.unit
            .map(normalizeUnit)
            .flatMap { $0.isEmpty ? nil : $0 }
        if hasInlinePercent, let typedUnit, typedUnit != "%" {
            return invalid(.numericAmbiguous)
        }
        if let inlineUnit, let typedUnit, inlineUnit != typedUnit { return invalid(.numericAmbiguous) }
        let submittedUnit = hasInlinePercent ? "%" : (inlineUnit ?? typedUnit)
        if schema.answer.unitRequired, submittedUnit == nil {
            return invalid(.unitMissing)
        }
        return NFExerciseResponseValidation(
            issue: nil,
            numericSubmission: NFValidatedNumericSubmission(
                value: value,
                canonicalInput: normalized,
                submittedUnit: submittedUnit
            )
        )
    }

    static func normalizeUnit(_ unit: String) -> String {
        unit
            .folding(options: [.diacriticInsensitive, .widthInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "μ", with: "u")
            .replacingOccurrences(of: "µ", with: "u")
    }

    private enum LocalizedNumberResult {
        case success(String)
        case failure(NFExerciseResponseValidationIssue)
    }

    private static func normalizeLocalizedNumber(
        _ source: String,
        localeIdentifier: String,
        permitsGrouping: Bool
    ) -> LocalizedNumberResult {
        let fractionParts = source.split(separator: "/", omittingEmptySubsequences: false)
        guard fractionParts.count <= 2 else { return .failure(.numericInvalid) }
        if fractionParts.count == 2 {
            let numerator = normalizeLocalizedComponent(
                String(fractionParts[0]),
                localeIdentifier: localeIdentifier,
                permitsGrouping: permitsGrouping,
                permitsDecimal: false,
                permitsExponent: false
            )
            let denominator = normalizeLocalizedComponent(
                String(fractionParts[1]),
                localeIdentifier: localeIdentifier,
                permitsGrouping: permitsGrouping,
                permitsDecimal: false,
                permitsExponent: false
            )
            guard case let .success(normalizedNumerator) = numerator,
                  case let .success(normalizedDenominator) = denominator else {
                if case let .failure(issue) = numerator { return .failure(issue) }
                if case let .failure(issue) = denominator { return .failure(issue) }
                return .failure(.numericInvalid)
            }
            return .success("\(normalizedNumerator)/\(normalizedDenominator)")
        }
        return normalizeLocalizedComponent(
            source,
            localeIdentifier: localeIdentifier,
            permitsGrouping: permitsGrouping,
            permitsDecimal: true,
            permitsExponent: true
        )
    }

    private static func normalizeLocalizedComponent(
        _ source: String,
        localeIdentifier: String,
        permitsGrouping: Bool,
        permitsDecimal: Bool,
        permitsExponent: Bool
    ) -> LocalizedNumberResult {
        let trimmed = source.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .failure(.numericInvalid) }

        let exponentParts = trimmed.split(
            omittingEmptySubsequences: false,
            whereSeparator: { $0 == "e" || $0 == "E" }
        )
        guard exponentParts.count <= 2, permitsExponent || exponentParts.count == 1 else {
            return .failure(.numericNotation)
        }
        let exponent: String
        if exponentParts.count == 2 {
            exponent = String(exponentParts[1])
            var digits = exponent
            if digits.hasPrefix("+") || digits.hasPrefix("-") { digits.removeFirst() }
            guard !digits.isEmpty, digits.allSatisfy(\.isNumber) else {
                return .failure(.numericInvalid)
            }
        } else {
            exponent = ""
        }

        var significand = String(exponentParts[0])
        var sign = ""
        if significand.hasPrefix("+") || significand.hasPrefix("-") {
            sign = String(significand.removeFirst())
        }
        guard !significand.isEmpty else { return .failure(.numericInvalid) }

        let locale = Locale(identifier: localeIdentifier)
        let decimalSeparator = locale.decimalSeparator ?? "."
        let localeGrouping = locale.groupingSeparator ?? ","
        let normalizedGrouping = significand
            .replacingOccurrences(of: "\u{00A0}", with: localeGrouping)
            .replacingOccurrences(of: "\u{202F}", with: localeGrouping)
        significand = normalizedGrouping

        let decimalParts = significand.components(separatedBy: decimalSeparator)
        guard decimalParts.count <= 2 else { return .failure(.numericInvalid) }
        if !permitsDecimal, decimalParts.count == 2 { return .failure(.numericInvalid) }
        let integerPart = decimalParts[0]
        let fractionPart = decimalParts.count == 2 ? decimalParts[1] : nil
        if let fractionPart,
           fractionPart.contains(localeGrouping) || fractionPart.contains("_") {
            return .failure(.numericAmbiguous)
        }

        let integerResult = normalizeGroupedInteger(
            integerPart,
            localeGrouping: localeGrouping,
            permitsGrouping: permitsGrouping
        )
        guard case let .success(integer) = integerResult else {
            if case let .failure(issue) = integerResult { return .failure(issue) }
            return .failure(.numericInvalid)
        }
        if let fractionPart, !fractionPart.isEmpty, !fractionPart.allSatisfy(\.isNumber) {
            return .failure(.numericAmbiguous)
        }
        if fractionPart == nil,
           significand.contains(decimalSeparator == "." ? "," : ".") {
            return .failure(.numericAmbiguous)
        }
        let decimal = fractionPart.map { ".\($0)" } ?? ""
        let exponentSuffix = exponentParts.count == 2 ? "e\(exponent)" : ""
        return .success(sign + integer + decimal + exponentSuffix)
    }

    private static func normalizeGroupedInteger(
        _ source: String,
        localeGrouping: String,
        permitsGrouping: Bool
    ) -> LocalizedNumberResult {
        let containsLocaleGrouping = !localeGrouping.isEmpty && source.contains(localeGrouping)
        let containsUnderscore = source.contains("_")
        guard !(containsLocaleGrouping && containsUnderscore) else {
            return .failure(.numericAmbiguous)
        }
        let separator = containsUnderscore ? "_" : (containsLocaleGrouping ? localeGrouping : nil)
        guard let separator else {
            guard source.isEmpty || source.allSatisfy(\.isNumber) else {
                return .failure(.numericInvalid)
            }
            return .success(source)
        }
        guard permitsGrouping else { return .failure(.numericNotation) }
        let groups = source.components(separatedBy: separator)
        guard let first = groups.first,
              !first.isEmpty,
              first.count <= 3,
              first.allSatisfy(\.isNumber),
              groups.count > 1,
              groups.dropFirst().allSatisfy({
                  $0.count == 3 && $0.allSatisfy(\.isNumber)
              }) else {
            return .failure(.numericAmbiguous)
        }
        return .success(groups.joined())
    }

    private static func invalid(
        _ issue: NFExerciseResponseValidationIssue
    ) -> NFExerciseResponseValidation {
        NFExerciseResponseValidation(issue: issue, numericSubmission: nil)
    }
}

enum NFExerciseScoringEngine {
    static let scoringVersion = 8

    struct NumericAuthorityResult: Equatable, Sendable {
        let isCorrect: Bool
        let normalizedResponse: String?
        let errorCode: String?
    }

    /// UI-independent numeric validation entry point used by authoring checks,
    /// property tests, and import tooling. It shares the exact production path.
    static func validateNumeric(
        _ submission: NFNumericSubmission,
        schema: NFNumericResponseSchema,
        localeIdentifier: String = "en_US_POSIX"
    ) -> NumericAuthorityResult {
        let validation = NFExerciseResponseValidator.validateNumeric(
            submission,
            schema: schema,
            localeIdentifier: localeIdentifier
        )
        let result: RawScore
        if let issue = validation.issue {
            result = RawScore(
                isCorrect: false,
                credit: 0,
                normalizedResponse: nil,
                errorCode: issue.errorCode
            )
        } else if let numericSubmission = validation.numericSubmission {
            result = scoreNumeric(numericSubmission, schema: schema)
        } else {
            result = RawScore(
                isCorrect: false,
                credit: 0,
                normalizedResponse: nil,
                errorCode: "numeric_input"
            )
        }
        return NumericAuthorityResult(
            isCorrect: result.isCorrect,
            normalizedResponse: result.normalizedResponse,
            errorCode: result.errorCode
        )
    }

    /// Deterministic exact-answer authority shared by bundled retrieval
    /// content and the runtime scorer. The normalizer deliberately preserves
    /// signs, operators, grouping, decimal points, and units such as `%` so a
    /// cosmetically different formula can match without changing its meaning.
    static func validateNormalizedExact(
        _ submission: String,
        acceptedAnswers: [String]
    ) -> Bool {
        if acceptedAnswers.contains(where: { $0.contains("F(b)") && $0.contains("F(a)") }) {
            let text = submission.trimmingCharacters(in: .whitespacesAndNewlines)
            if acceptedAnswers.contains(text) { return true }
            let expression = text.replacingOccurrences(of: " minus ", with: "-")
            return NFRestrictedSymbolicAuthority.compare(expression,
                contract: NFSymbolicAnswerContract(acceptedExpressions: ["F(b)-F(a)"], variables: ["a", "b"], functions: ["F", "f"])) == .equivalent
        }
        let normalizedSubmission = NFBundledRetrievalCatalog.normalized(submission)
        guard !normalizedSubmission.isEmpty else { return false }
        return acceptedAnswers.contains {
            NFBundledRetrievalCatalog.normalized($0) == normalizedSubmission
        }
    }

    static func score(
        _ response: NFExerciseResponse,
        for exercise: NFExercise,
        revealDelayedFeedback: Bool = false
    ) -> NFExerciseScoringResult {
        if exercise.aiRubric != nil {
            // A synchronous exact scorer cannot substitute a keyword result or
            // zero for an unavailable semantic evaluator.
            return NFExerciseScoringResult(exerciseID: exercise.id, scoringVersion: scoringVersion,
                isCorrect: false, credit: 0, normalizedResponse: nil, errorCode: "ai_grading_required",
                expectedAnswerSummary: nil, feedback: NFExerciseFeedback(title: "Answer awaiting review",
                    explanation: "This response uses AI rubric grading. Save it for evaluation when a supported model is available.",
                    decisiveStep: nil, strategy: nil, errorCode: "ai_grading_required", isDelayed: false),
                outcome: .needsClarification)
        }
        guard NFExerciseSchemaValidator.supportsExerciseSchemaVersion(exercise.schemaVersion) else {
            return NFExerciseScoringResult(exerciseID: exercise.id, scoringVersion: scoringVersion,
                isCorrect: false, credit: 0, normalizedResponse: nil, errorCode: "unsupported_exercise_schema",
                expectedAnswerSummary: nil, feedback: NFExerciseFeedback(title: "Question unavailable",
                    explanation: "This saved work needs a compatible version of NeuroForge. Your original answers remain saved.",
                    decisiveStep: nil, strategy: nil, errorCode: "unsupported_exercise_schema", isDelayed: false),
                outcome: .invalidItem)
        }
        if let reason = exercise.availabilityReason {
            return NFExerciseScoringResult(exerciseID: exercise.id, scoringVersion: scoringVersion,
                isCorrect: false, credit: 0, normalizedResponse: nil, errorCode: "inventory_unavailable",
                expectedAnswerSummary: nil, feedback: NFExerciseFeedback(title: "Question unavailable",
                    explanation: reason, decisiveStep: nil, strategy: nil, errorCode: "inventory_unavailable", isDelayed: false),
                outcome: .invalidItem)
        }
        do {
            guard exercise.hasSupportedSpatialAssembly, exercise.hasSupportedCoordinateReasoning, exercise.hasSupportedNetFolding, exercise.hasSupportedSolidSection, exercise.hasSupportedCoordinateTransform, exercise.hasSupportedSpatialStructure, exercise.hasSupportedRetrievalAsset, exercise.hasSupportedRetrievalAuthorityRecipe, exercise.hasSupportedGraphConstruction, exercise.hasSupportedScienceStudy, exercise.hasSupportedTransferRelationship else {
                throw NFExerciseValidationError.invalidResponseSchema("unsupported linked study contract")
            }
            try NFExerciseSchemaValidator.validateInteraction(exercise.interaction)
        } catch {
            return NFExerciseScoringResult(
                exerciseID: exercise.id, scoringVersion: scoringVersion, isCorrect: false, credit: 0,
                normalizedResponse: nil, errorCode: "invalid_item", expectedAnswerSummary: nil,
                feedback: NFExerciseFeedback(title: "Question unavailable",
                    explanation: "This question has an invalid answer contract. It will not count against you.",
                    decisiveStep: nil, strategy: nil, errorCode: "invalid_item", isDelayed: false),
                outcome: .invalidItem
            )
        }
        let validation = NFExerciseResponseValidator.validate(
            response,
            for: exercise.interaction,
            localeIdentifier: exercise.localeIdentifier
        )
        var raw: RawScore
        if let issue = validation.issue {
            raw = RawScore(
                isCorrect: false,
                credit: 0,
                normalizedResponse: nil,
                errorCode: issue.errorCode
            )
        } else {
            raw = rawScore(
                response,
                interaction: NFRetrievalResponseAuthority.auditedInteraction(for: exercise),
                numericSubmission: validation.numericSubmission
            )
        }
        let isSelfReport: Bool = if case .selfCheck = exercise.interaction { true } else { false }
        let needsClarification = validation.issue != nil || ["symbolic_unsupported", "prose_review_required"].contains(raw.errorCode ?? "")
        if !raw.isCorrect && (!exercise.rubric.permitsPartialCredit || exercise.assessmentProtected) {
            raw = RawScore(isCorrect: false, credit: 0, normalizedResponse: raw.normalizedResponse, errorCode: raw.errorCode)
        }
        let outcome: NFScoringOutcome = needsClarification ? .needsClarification
            : (isSelfReport ? .selfReported : (raw.isCorrect ? .correct : (raw.credit > 0 ? .partial : .incorrect)))
        let components = componentResults(response, interaction: exercise.interaction, raw: raw, outcome: outcome)
        if needsClarification || isSelfReport {
            let explanation = validation.issue?.guidance ?? (isSelfReport
                ? "Your comparison is saved as a self-report. It does not establish independently verified correctness."
                : (raw.errorCode == "symbolic_unsupported"
                    ? "I could not interpret that formula. Use declared symbols, parentheses, and * for multiplication; variable denominators need separate review."
                    : "This wording is outside the reviewed answer coverage. Compare it with the reference or report a grading issue."))
            return NFExerciseScoringResult(
                exerciseID: exercise.id, scoringVersion: scoringVersion, isCorrect: false, credit: 0,
                normalizedResponse: raw.normalizedResponse, errorCode: raw.errorCode,
                expectedAnswerSummary: isSelfReport && !exercise.assessmentProtected ? expectedAnswerSummary(exercise.interaction) : nil,
                feedback: NFExerciseFeedback(title: isSelfReport ? "Self-check saved" : "Check your response",
                    explanation: explanation, decisiveStep: nil, strategy: nil, errorCode: raw.errorCode, isDelayed: false),
                outcome: outcome, components: components
            )
        }
        let feedbackIsDelayed = exercise.assessmentProtected
            || (exercise.feedback.timing == .afterAssessmentBlock && !revealDelayedFeedback)

        if feedbackIsDelayed {
            return NFExerciseScoringResult(
                exerciseID: exercise.id,
                scoringVersion: scoringVersion,
                isCorrect: raw.isCorrect,
                credit: raw.credit,
                normalizedResponse: raw.normalizedResponse,
                errorCode: raw.errorCode,
                expectedAnswerSummary: nil,
                feedback: NFExerciseFeedback(
                    title: "Answer saved",
                    explanation: "Skill guidance is available when this assessment block is complete.",
                    decisiveStep: nil,
                    strategy: nil,
                    errorCode: nil,
                    isDelayed: true
                ),
                outcome: outcome, components: []
            )
        }

        let feedback: NFExerciseFeedback
        if raw.isCorrect {
            feedback = NFExerciseFeedback(
                title: exercise.feedback.correctTitle,
                explanation: exercise.feedback.correctExplanation,
                decisiveStep: exercise.feedback.decisiveStep,
                strategy: exercise.strategies.first?.summary,
                errorCode: nil,
                isDelayed: false
            )
        } else {
            let explanation = raw.errorCode.flatMap { exercise.feedback.errorExplanations[$0] }
                ?? exercise.feedback.retryExplanation
            feedback = NFExerciseFeedback(
                title: exercise.feedback.retryTitle,
                explanation: explanation,
                decisiveStep: exercise.feedback.decisiveStep,
                strategy: exercise.strategies.first?.summary,
                errorCode: raw.errorCode,
                isDelayed: false
            )
        }

        return NFExerciseScoringResult(
            exerciseID: exercise.id,
            scoringVersion: scoringVersion,
            isCorrect: raw.isCorrect,
            credit: raw.credit,
            normalizedResponse: raw.normalizedResponse,
            errorCode: raw.errorCode,
            expectedAnswerSummary: exercise.contractMetadata?.solidSection?.exactAnswerSummary ?? NFTransferRelationshipContract.make(exercise: exercise).flatMap { $0.responseText($0.expectedResponse) } ?? expectedAnswerSummary(exercise.interaction),
            feedback: feedback, outcome: outcome, components: components
        )
    }

    private struct RawScore {
        let isCorrect: Bool
        let credit: Double
        let normalizedResponse: String?
        let errorCode: String?
    }

    private static func rawScore(
        _ response: NFExerciseResponse,
        interaction: NFExerciseInteraction,
        numericSubmission: NFValidatedNumericSubmission?
    ) -> RawScore {
        switch (interaction, response) {
        case let (.numeric(schema), .numeric):
            if let numericSubmission {
                scoreNumeric(numericSubmission, schema: schema)
            } else {
                RawScore(isCorrect: false, credit: 0, normalizedResponse: nil, errorCode: "numeric_input")
            }
        case let (.singleChoice(schema), .singleChoice(optionID)):
            scoreSingleChoice(optionID, schema: schema)
        case let (.multipleChoice(schema), .multipleChoice(optionIDs)):
            scoreMultipleChoice(optionIDs, schema: schema)
        case let (.orderedSteps(schema), .orderedSteps(stepIDs)):
            scoreOrderedSteps(stepIDs, schema: schema)
        case let (.shortText(schema), .shortText(responseText)):
            scoreShortText(responseText, schema: schema)
        case let (.selfCheck(_), .selfCheck(submission)):
            scoreSelfCheck(submission)
        case let (.claimEvidence(schema), .claimEvidence(submission)):
            scoreClaimEvidence(submission, schema: schema)
        case let (.logicState(schema), .logicState(submission)):
            scoreLogicState(submission, schema: schema)
        default:
            RawScore(
                isCorrect: false,
                credit: 0,
                normalizedResponse: nil,
                errorCode: "response_type_mismatch"
            )
        }
    }

    private static func scoreNumeric(
        _ submission: NFValidatedNumericSubmission,
        schema: NFNumericResponseSchema
    ) -> RawScore {
        let value = submission.value
        let submittedUnit = submission.submittedUnit
        let acceptedUnits = Set(
            ([schema.answer.canonicalUnit].compactMap { $0 } + schema.answer.acceptedUnits)
                .map(NFExerciseResponseValidator.normalizeUnit)
        )
        if let submittedUnit, !acceptedUnits.isEmpty, !acceptedUnits.contains(submittedUnit) {
            return RawScore(
                isCorrect: false,
                credit: 0,
                normalizedResponse: "\(value.canonicalString) \(submittedUnit)",
                errorCode: "unit_mismatch"
            )
        }

        let expected = schema.answer.authoritativeValue
        let correct: Bool
        switch schema.answer.authoritativeTolerance {
        case let .absolute(tolerance):
            correct = value.isWithinAbsoluteTolerance(of: expected, tolerance: tolerance)
        case let .relative(tolerance):
            correct = value.isWithinRelativeTolerance(of: expected, tolerance: tolerance)
        case let .absoluteOrRelative(absolute, relative):
            correct = value.isWithinAbsoluteTolerance(of: expected, tolerance: absolute)
                || value.isWithinRelativeTolerance(of: expected, tolerance: relative)
        }
        let canonicalUnit = schema.answer.canonicalUnit.map { " \($0)" } ?? ""
        return RawScore(
            isCorrect: correct,
            credit: correct ? 1 : 0,
            normalizedResponse: "\(value.canonicalString)\(canonicalUnit)",
            errorCode: correct ? nil : "numeric_value"
        )
    }

    private static func scoreSingleChoice(
        _ optionID: String,
        schema: NFSingleChoiceResponseSchema
    ) -> RawScore {
        guard schema.options.contains(where: { $0.id == optionID }) else {
            return RawScore(isCorrect: false, credit: 0, normalizedResponse: optionID, errorCode: "unknown_choice")
        }
        let correct = optionID == schema.correctOptionID
        let distractorCode = schema.options.first(where: { $0.id == optionID })?.distractorCode
        return RawScore(
            isCorrect: correct,
            credit: correct ? 1 : 0,
            normalizedResponse: optionID,
            errorCode: correct ? nil : distractorCode ?? "choice_selection"
        )
    }

    private static func scoreMultipleChoice(
        _ optionIDs: [String],
        schema: NFMultipleChoiceResponseSchema
    ) -> RawScore {
        let selected = Set(optionIDs)
        let valid = Set(schema.options.map(\.id))
        guard selected.isSubset(of: valid),
              selected.count >= schema.minimumSelections,
              selected.count <= schema.maximumSelections else {
            return RawScore(
                isCorrect: false,
                credit: 0,
                normalizedResponse: selected.sorted().joined(separator: ","),
                errorCode: "selection_bounds"
            )
        }
        let accepted = [Set(schema.correctOptionIDs)] + (schema.acceptedAlternativeSets ?? []).map(Set.init)
        let credit = accepted.map { expected in
            max(0, Double(selected.intersection(expected).count - selected.subtracting(expected).count) / Double(max(1, expected.count)))
        }.max() ?? 0
        let correct = accepted.contains(selected)
        return RawScore(
            isCorrect: correct,
            credit: credit,
            normalizedResponse: selected.sorted().joined(separator: ","),
            errorCode: correct ? nil : "multiple_choice_selection"
        )
    }

    private static func scoreOrderedSteps(
        _ stepIDs: [String],
        schema: NFOrderedStepsResponseSchema
    ) -> RawScore {
        let expected = schema.correctOrder
        guard stepIDs.count == expected.count, Set(stepIDs) == Set(expected) else {
            return RawScore(
                isCorrect: false,
                credit: 0,
                normalizedResponse: stepIDs.joined(separator: ">"),
                errorCode: "ordered_steps_membership"
            )
        }
        let edges = NFOrderingAuthority.dependencies(for: schema)
        let positions = Dictionary(uniqueKeysWithValues: stepIDs.enumerated().map { ($0.element, $0.offset) })
        let matched = edges.filter { (positions[$0.before] ?? Int.max) < (positions[$0.after] ?? Int.min) }.count
        let correct = matched == edges.count
        return RawScore(
            isCorrect: correct,
            credit: edges.isEmpty ? 1 : Double(matched) / Double(edges.count),
            normalizedResponse: stepIDs.joined(separator: ">"),
            errorCode: correct ? nil : "ordered_steps_sequence"
        )
    }

    private static func scoreShortText(
        _ response: String,
        schema: NFShortTextResponseSchema
    ) -> RawScore {
        let normalized = normalizeText(response)
        guard !response.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return RawScore(isCorrect: false, credit: 0, normalizedResponse: nil, errorCode: "text_missing")
        }
        guard response.count <= schema.maximumCharacters else {
            return RawScore(isCorrect: false, credit: 0, normalizedResponse: normalized, errorCode: "text_too_long")
        }

        if let authority = schema.authority {
            if !NFRetrievalResponseAuthority.requiresStrictDispatch(authority),
               case let .normalizedExact(acceptedAnswers) = schema.scoringRule,
               acceptedAnswers.contains(response.trimmingCharacters(in: .whitespacesAndNewlines)) {
                return RawScore(isCorrect: true, credit: 1, normalizedResponse: response, errorCode: nil)
            }
            return scoreTextAuthority(response, authority: authority)
        }
        switch schema.scoringRule {
        case let .normalizedExact(acceptedAnswers):
            let exactNormalized = NFBundledRetrievalCatalog.normalized(response)
            let correct = validateNormalizedExact(response, acceptedAnswers: acceptedAnswers)
            return RawScore(
                isCorrect: correct,
                credit: correct ? 1 : 0,
                normalizedResponse: exactNormalized.isEmpty ? nil : exactNormalized,
                errorCode: correct ? nil : "text_answer"
            )

        case let .requiredTerms(terms, minimumMatches):
            // The authored reference answer is always an authoritative correct
            // response. Concept matching broadens acceptance to ordinary
            // paraphrases; it must never invalidate the reference itself.
            if normalized == normalizeText(schema.expectedAnswer) {
                return RawScore(
                    isCorrect: true,
                    credit: 1,
                    normalizedResponse: normalized,
                    errorCode: nil
                )
            }
            // A vertical bar separates equivalent surface forms for one
            // required concept. This keeps open reasoning deterministic while
            // accepting ordinary paraphrases such as “randomize” versus
            // “random assignment”. Existing terms without alternatives retain
            // their original behavior.
            let matchCount = terms.filter { conceptGroupMatches($0, in: response) }.count
            let correct = matchCount >= minimumMatches
            return RawScore(
                isCorrect: correct,
                credit: correct ? 1 : 0,
                normalizedResponse: normalized,
                errorCode: correct ? nil : "text_required_terms"
            )

        case let .constrainedConcepts(acceptedAnswers, requiredTerms, minimumMatches, rejectedAssertions):
            let exactAnswers = Set(([schema.expectedAnswer] + acceptedAnswers).map(normalizeText))
            if exactAnswers.contains(normalized) {
                return RawScore(
                    isCorrect: true,
                    credit: 1,
                    normalizedResponse: normalized,
                    errorCode: nil
                )
            }
            if rejectedAssertions.contains(where: {
                rejectedConceptIsAsserted(
                    $0,
                    in: response,
                    requiredGroups: requiredTerms
                )
            }) {
                return RawScore(
                    isCorrect: false,
                    credit: 0,
                    normalizedResponse: normalized,
                    errorCode: "text_contradiction"
                )
            }
            let matchCount = requiredTerms.filter { conceptGroupMatches($0, in: response) }.count
            let correct = matchCount >= minimumMatches
            return RawScore(
                isCorrect: correct,
                credit: correct ? 1 : 0,
                normalizedResponse: normalized,
                errorCode: correct ? nil : "text_required_concepts"
            )
        }
    }

    private static func scoreTextAuthority(_ response: String, authority: NFShortTextAuthority) -> RawScore {
        func result(_ correct: Bool, _ code: String? = nil, parsed: String? = nil) -> RawScore {
            RawScore(isCorrect: correct, credit: correct ? 1 : 0,
                normalizedResponse: parsed ?? response.trimmingCharacters(in: .whitespacesAndNewlines),
                errorCode: correct ? nil : (code ?? "text_answer"))
        }
        switch authority {
        case let .symbolic(contract):
            switch NFRestrictedSymbolicAuthority.compare(response, contract: contract) {
            case .equivalent: return result(true)
            case .different: return result(false, "symbolic_value")
            case .unsupported: return result(false, "symbolic_unsupported")
            }
        case let .unsignedBinaryNumeral(contract):
            guard contract.isSupported, let canonical = contract.canonical(response) else { return result(false, "symbolic_unsupported") }
            return result(canonical == contract.expectedDigits, "text_answer", parsed: canonical)
        case let .identifier(acceptedAnswers):
            return result(acceptedAnswers.contains(response.trimmingCharacters(in: .whitespacesAndNewlines)))
        case let .reviewedProse(acceptedAnswers, rejectedAssertions):
            let normalized = normalizeText(response)
            if acceptedAnswers.map(normalizeText).contains(normalized) { return result(true, parsed: normalized) }
            if rejectedAssertions.contains(where: { normalized.contains(normalizeText($0)) }) {
                return result(false, "text_contradiction", parsed: normalized)
            }
            return result(false, "prose_review_required", parsed: normalized)
        case let .exactQuantity(schema):
            let text = response.trimmingCharacters(in: .whitespacesAndNewlines)
            let pattern = #"^([+\-−]?(?:[0-9]+(?:\.[0-9]*)?|\.[0-9]+)(?:[eE][+\-]?[0-9]+)?(?:\s*/\s*[+\-]?[0-9]+)?)(?:\s*([^0-9\s].*))?$"#
            guard let regex = try? NSRegularExpression(pattern: pattern),
                  let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
                  let valueRange = Range(match.range(at: 1), in: text) else { return result(false, "symbolic_unsupported") }
            let unit = Range(match.range(at: 2), in: text).map { String(text[$0]) }
            let validation = NFExerciseResponseValidator.validateNumeric(
                NFNumericSubmission(value: String(text[valueRange]), unit: unit), schema: schema)
            guard let parsed = validation.numericSubmission, validation.isValid else { return result(false, "symbolic_unsupported") }
            return scoreNumeric(parsed, schema: schema)
        }
    }

    private static func componentResults(
        _ response: NFExerciseResponse, interaction: NFExerciseInteraction,
        raw: RawScore, outcome: NFScoringOutcome
    ) -> [NFScoringComponentResult] {
        func component(_ id: String, _ submitted: String, _ parsed: String?, _ credit: Double,
                       _ maximum: Double, _ code: String? = nil) -> NFScoringComponentResult {
            let componentOutcome: NFScoringOutcome = outcome.objectiveCorrectness == nil ? outcome
                : (credit == maximum ? .correct : (credit > 0 ? .partial : .incorrect))
            return NFScoringComponentResult(id: id, submittedValue: submitted, parsedValue: parsed,
                ruleVersion: scoringVersion, outcome: componentOutcome, awardedCredit: credit,
                maximumCredit: maximum, misconceptionCode: code,
                explanation: componentOutcome == .correct ? "This part matches the answer contract."
                    : (componentOutcome.objectiveCorrectness == nil ? "This part has no objective score." : "Recheck this part of your response."))
        }
        if case let .logicState(schema) = interaction, case let .logicState(submission) = response {
            let keys = schema.expectedFinalState.keys.sorted()
            let accepted = ([schema.expectedFinalState] + schema.acceptedEquivalentStates).max { a, b in
                keys.filter { NFStateValueAuthority.equivalent(submission.finalState[$0] ?? "", a[$0] ?? "", domain: schema.fieldDomains?[$0]) }.count
                < keys.filter { NFStateValueAuthority.equivalent(submission.finalState[$0] ?? "", b[$0] ?? "", domain: schema.fieldDomains?[$0]) }.count
            } ?? schema.expectedFinalState
            let maximum = (schema.expectedViolatedRuleID == nil ? 1.0 : 0.8) / Double(max(1, keys.count))
            var parts = keys.map { key in
                let input = submission.finalState[key] ?? ""
                let correct: Bool = if let policy = schema.plausibilityPolicy, key == policy.judgmentKey {
                    policy.accepts(submission.finalState)
                } else {
                    NFStateValueAuthority.equivalent(input, accepted[key] ?? "", domain: schema.fieldDomains?[key])
                }
                return component(key, input, input.trimmingCharacters(in: .whitespacesAndNewlines), correct ? maximum : 0, maximum, correct ? nil : "logic_state")
            }
            if schema.expectedViolatedRuleID != nil {
                let correct = submission.violatedRuleID == schema.expectedViolatedRuleID
                parts.append(component("invariant", submission.violatedRuleID ?? "", submission.violatedRuleID, correct ? 0.2 : 0, 0.2, correct ? nil : "logic_rule"))
            }
            // Exact-set contracts may suppress component credit; preserve
            // inspection while ensuring the awarded amounts sum to the result.
            if raw.credit == 0 && parts.contains(where: { $0.awardedCredit > 0 }) {
                return [component("response", raw.normalizedResponse ?? "", raw.normalizedResponse, 0, 1, raw.errorCode)]
            }
            return parts
        }
        let submitted: String
        switch response {
        case let .numeric(value): submitted = value.value + (value.unit.map { " \($0)" } ?? "")
        case let .shortText(value): submitted = value
        case let .singleChoice(id): submitted = id
        case let .multipleChoice(ids), let .orderedSteps(ids): submitted = ids.joined(separator: ", ")
        case let .selfCheck(value): submitted = value.rating.rawValue
        case .claimEvidence, .logicState: submitted = raw.normalizedResponse ?? ""
        }
        return [component("response", submitted, raw.normalizedResponse, raw.credit, 1, raw.errorCode)]
    }

    private static func scoreSelfCheck(_ submission: NFSelfCheckSubmission) -> RawScore {
        RawScore(isCorrect: false, credit: 0, normalizedResponse: submission.rating.rawValue, errorCode: nil)
    }

    private static func scoreClaimEvidence(
        _ submission: NFClaimEvidenceSubmission,
        schema: NFClaimEvidenceResponseSchema
    ) -> RawScore {
        let validClaimIDs = Set(schema.claims.map(\.id))
        let validEvidenceIDs = Set(schema.evidence.map(\.id))
        let submittedMap = pairMap(submission.pairs)
        guard Set(submittedMap.keys).isSubset(of: validClaimIDs),
              submittedMap.values.allSatisfy({ $0.isSubset(of: validEvidenceIDs) }) else {
            return RawScore(isCorrect: false, credit: 0, normalizedResponse: nil, errorCode: "claim_evidence_unknown")
        }

        let contracts = schema.supportContracts ?? schema.correctPairs.map {
            NFClaimSupportContract(claimID: $0.claimID, sufficientBundles: [$0.evidenceIDs])
        }
        let scores = contracts.map { contract -> Double in
            let selected = submittedMap[contract.claimID] ?? []
            return contract.sufficientBundles.map { bundle in
                let expected = Set(bundle)
                return max(0, Double(selected.intersection(expected).count - selected.subtracting(expected).count)
                    / Double(max(1, expected.count)))
            }.max() ?? 0
        }
        let credit = scores.isEmpty ? 0 : scores.reduce(0, +) / Double(scores.count)
        let correct = contracts.allSatisfy { contract in
            contract.sufficientBundles.contains { Set($0) == (submittedMap[contract.claimID] ?? []) }
        }
        return RawScore(
            isCorrect: correct,
            credit: credit,
            normalizedResponse: normalizedPairs(submittedMap),
            errorCode: correct ? nil : "claim_evidence_support"
        )
    }

    private static func scoreLogicState(
        _ submission: NFLogicStateSubmission,
        schema: NFLogicStateResponseSchema
    ) -> RawScore {
        let acceptedStates = [schema.expectedFinalState] + schema.acceptedEquivalentStates
        let keys = Set(schema.expectedFinalState.keys)
        let matchingKeys = acceptedStates.map { accepted in
            keys.filter { key in
                if let policy = schema.plausibilityPolicy, key == policy.judgmentKey {
                    return policy.accepts(submission.finalState)
                }
                return NFStateValueAuthority.equivalent(submission.finalState[key] ?? "", accepted[key] ?? "",
                    domain: schema.fieldDomains?[key])
            }.count
        }.max() ?? 0
        let stateCorrect = matchingKeys == keys.count
        let stateCredit = keys.isEmpty ? 0 : Double(matchingKeys) / Double(keys.count)

        let ruleCorrect = submission.violatedRuleID == schema.expectedViolatedRuleID
        let hasRule = schema.expectedViolatedRuleID != nil
        let credit = hasRule ? (stateCredit * 0.8 + (ruleCorrect ? 0.2 : 0)) : stateCredit
        let correct = stateCorrect && ruleCorrect
        let normalizedState = submission.finalState
            .sorted(by: { $0.key < $1.key })
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: ",")
        let normalizedRule = submission.violatedRuleID.map { ";rule=\($0)" } ?? ""
        return RawScore(
            isCorrect: correct,
            credit: credit,
            normalizedResponse: normalizedState + normalizedRule,
            errorCode: correct ? nil : (stateCorrect ? "logic_rule" : "logic_state")
        )
    }

    private static func expectedAnswerSummary(_ interaction: NFExerciseInteraction) -> String {
        switch interaction {
        case let .numeric(schema):
            let formatted = schema.answer.value.formatted(
                .number.precision(.fractionLength(0...schema.answer.displayPrecision))
            )
            return formatted + (schema.answer.canonicalUnit.map { " \($0)" } ?? "")
        case let .singleChoice(schema):
            return schema.options.first(where: { $0.id == schema.correctOptionID })?.text ?? schema.correctOptionID
        case let .multipleChoice(schema):
            let expected = Set(schema.correctOptionIDs)
            return schema.options.filter { expected.contains($0.id) }.map(\.text).joined(separator: "; ")
        case let .orderedSteps(schema):
            let steps = Dictionary(uniqueKeysWithValues: schema.steps.map { ($0.id, $0.text) })
            return schema.correctOrder.compactMap { steps[$0] }.joined(separator: " → ")
        case let .shortText(schema):
            return schema.expectedAnswer
        case let .selfCheck(schema):
            return schema.referenceAnswer
        case let .claimEvidence(schema):
            let claimLabels = Dictionary(uniqueKeysWithValues: schema.claims.map { ($0.id, $0.text) })
            let evidenceLabels = Dictionary(uniqueKeysWithValues: schema.evidence.map { ($0.id, $0.text) })
            return schema.correctPairs
                .map { pair in
                    let claim = claimLabels[pair.claimID] ?? pair.claimID
                    let evidence = pair.evidenceIDs
                        .compactMap { evidenceLabels[$0] }
                        .joined(separator: "; ")
                    return "\(claim): \(evidence)"
                }
                .sorted()
                .joined(separator: "\n")
        case let .logicState(schema):
            let state = schema.expectedFinalState.sorted { $0.key < $1.key }
                .map { "\($0.key)=\($0.value)" }
                .joined(separator: ", ")
            let rule = schema.expectedViolatedRuleID.flatMap { expectedID in
                schema.ruleOptions.first(where: { $0.id == expectedID })?.text ?? expectedID
            }
            return state + (rule.map { "; rule \($0)" } ?? "")
        }
    }

    private static func pairMap(_ pairs: [NFClaimEvidencePair]) -> [String: Set<String>] {
        pairs.reduce(into: [:]) { result, pair in
            result[pair.claimID, default: []].formUnion(pair.evidenceIDs)
        }
    }

    private static func normalizedPairs(_ pairs: [String: Set<String>]) -> String {
        pairs.keys.sorted().map { claimID in
            "\(claimID):\((pairs[claimID] ?? []).sorted().joined(separator: "+"))"
        }.joined(separator: ";")
    }

    private static func normalizeText(_ value: String) -> String {
        value
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .trimmingCharacters(in: .punctuationCharacters.union(.whitespacesAndNewlines))
    }

    /// One concept group uses `|` for equivalent surface forms and a trailing
    /// `*` on a word for a prefix stem. Matching retains numeric signs and
    /// mathematical operators, so `-9` is not equivalent to `9`, `nA/2` is
    /// matchable, and `<` does not silently match `<=`.
    private static func conceptGroupMatches(_ group: String, in response: String) -> Bool {
        group
            .split(separator: "|")
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .contains { conceptAlternativeMatches($0, in: response) }
    }

    /// Rejected concepts remain a hard safety boundary, but mentioning the
    /// faulty expression is not the same as endorsing it. Debugging answers
    /// routinely say “change old to new” or “do not use old”. This matcher
    /// only discounts a rejected occurrence when deterministic token context
    /// proves it is the rejected/source side of a correction. Ambiguous
    /// mentions continue to fail closed.
    private static func rejectedConceptIsAsserted(
        _ group: String,
        in response: String,
        requiredGroups: [String]
    ) -> Bool {
        let responseTokens = conceptTokens(in: response, allowsStemWildcard: false)
        guard !responseTokens.isEmpty else { return false }

        let rejectedRanges = conceptMatchRanges(
            group,
            in: responseTokens,
            includesAssertionCores: true
        )
        if rejectedRanges.isEmpty {
            // Non-space-delimited scripts retain the existing substring
            // matcher. Without an unambiguous token range, do not weaken a
            // curated rejected assertion.
            return conceptGroupMatches(group, in: response)
        }
        let requiredRanges = requiredGroups.flatMap {
            conceptMatchRanges($0, in: responseTokens, includesAssertionCores: false)
        }
        return rejectedRanges.contains { rejectedRange in
            !rejectedMentionIsContextualized(
                rejectedRange,
                requiredRanges: requiredRanges,
                tokens: responseTokens
            )
        }
    }

    private static func conceptMatchRanges(
        _ group: String,
        in responseTokens: [String],
        includesAssertionCores: Bool
    ) -> [Range<Int>] {
        var result: [Range<Int>] = []
        let alternatives = group
            .split(separator: "|")
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        for alternative in alternatives {
            let tokens = conceptTokens(in: alternative, allowsStemWildcard: true)
            guard !tokens.isEmpty else { continue }
            var patterns = [tokens]
            if includesAssertionCores,
               let core = assertionCoreTokens(from: tokens),
               core != tokens {
                patterns.append(core)
            }

            for pattern in patterns where pattern.count <= responseTokens.count {
                for start in 0...(responseTokens.count - pattern.count) {
                    let range = start..<(start + pattern.count)
                    let candidate = responseTokens[range]
                    let matches = zip(pattern, candidate).allSatisfy { expected, value in
                        if expected.hasSuffix("*"), expected.count > 1 {
                            return value.hasPrefix(expected.dropLast())
                        }
                        return expected == value
                    }
                    guard matches else { continue }

                    // A positive numeric concept must not match the magnitude
                    // portion of a negative or explicitly signed value.
                    if NFExactNumber(parsing: alternative) != nil,
                       !["-", "+"].contains(pattern.first),
                       start > 0,
                       ["-", "+"].contains(responseTokens[start - 1]) {
                        continue
                    }
                    if !result.contains(range) { result.append(range) }
                }
            }
        }
        return result
    }

    private static func assertionCoreTokens(from tokens: [String]) -> [String]? {
        guard !tokens.isEmpty else { return nil }
        var core = tokens
        let leadingAssertionCues: Set<String> = [
            "use", "uses", "using", "keep", "keeps", "choose", "select",
            "apply", "write", "return", "retain", "should"
        ]
        if let first = core.first, leadingAssertionCues.contains(first) {
            core.removeFirst()
        }
        // Do not strip a positive predicate such as “is safe” or “is
        // correct”. The subject can be a required observation (“negative
        // edge”) while the predicate is precisely what makes the full phrase
        // a rejected assertion. Leading action cues are safe to strip because
        // their remaining object still names the action being endorsed.
        guard !core.isEmpty, core != tokens else { return nil }
        return core
    }

    private static func rejectedMentionIsContextualized(
        _ rejectedRange: Range<Int>,
        requiredRanges: [Range<Int>],
        tokens: [String]
    ) -> Bool {
        let beforeStart = max(0, rejectedRange.lowerBound - 7)
        let afterEnd = min(tokens.count, rejectedRange.upperBound + 7)
        let before = Array(tokens[beforeStart..<rejectedRange.lowerBound])
        let after = Array(tokens[rejectedRange.upperBound..<afterEnd])
        let localPrefix = Array((before + [tokens[rejectedRange.lowerBound]]).suffix(6))

        // Explicitly rejecting use of the matched expression is safe. “Do not
        // change X” deliberately is not in this list: that wording endorses X.
        let negatedUsePatterns = [
            ["do", "not", "use"], ["not", "use"], ["never", "use"],
            ["do", "not", "keep"], ["not", "keep"], ["never", "keep"],
            ["do", "not", "process"], ["not", "process"], ["never", "process"],
            ["prevent", "processing"], ["prevent", "reprocessing"],
            ["do", "not", "queue"], ["not", "queue"], ["never", "queue"],
            ["do", "not", "finalize"], ["not", "finalize"], ["never", "finalize"],
            ["do", "not", "return"], ["not", "return"], ["never", "return"],
            ["do", "not", "stop"], ["not", "stop"], ["never", "stop"],
            ["avoid"], ["reject"]
        ]
        if negatedUsePatterns.contains(where: { tokenSequence($0, occursIn: localPrefix) }) {
            return true
        }

        // An adjacent diagnostic labels the occurrence as the faulty premise,
        // while a separately matched required concept supplies the correction.
        let diagnosticPatterns = [
            ["is", "wrong"], ["is", "invalid"], ["is", "faulty"],
            ["is", "unsafe"], ["is", "the", "bug"], ["causes", "out", "of", "bounds"]
        ]
        if !requiredRanges.isEmpty,
           diagnosticPatterns.contains(where: { tokenSequence($0, occursIn: after) }) {
            return true
        }

        for requiredRange in requiredRanges {
            if rejectedRange.upperBound <= requiredRange.lowerBound {
                let gap = requiredRange.lowerBound - rejectedRange.upperBound
                guard gap <= 18 else { continue }
                let between = Array(tokens[rejectedRange.upperBound..<requiredRange.lowerBound])
                let repairVerbs: Set<String> = [
                    "change", "replace", "correct", "fix", "switch", "rewrite",
                    "update", "patch", "turn"
                ]
                if between.contains("->") { return true }
                if between.contains(where: { ["to", "with", "into"].contains($0) }),
                   before.contains(where: repairVerbs.contains) {
                    return true
                }

                // “The old expression is bad, but the correction should use
                // the required expression.” Both a diagnostic cue and a
                // correction cue are required to avoid broad contrast matches.
                let oldSideCues: Set<String> = ["old", "bad", "faulty", "incorrect", "bug"]
                let newSideCues: Set<String> = ["correct", "correction", "should", "instead", "use"]
                if (between.contains("but") || before.contains(where: oldSideCues.contains)),
                   between.contains(where: newSideCues.contains) {
                    return true
                }
            } else if requiredRange.upperBound <= rejectedRange.lowerBound {
                let gap = rejectedRange.lowerBound - requiredRange.upperBound
                guard gap <= 14 else { continue }
                let between = Array(tokens[requiredRange.upperBound..<rejectedRange.lowerBound])
                if tokenSequence(["instead", "of"], occursIn: between)
                    || tokenSequence(["rather", "than"], occursIn: between)
                    || between.suffix(3).contains("not") {
                    return true
                }
            }
        }
        return false
    }

    private static func tokenSequence(_ sequence: [String], occursIn tokens: [String]) -> Bool {
        guard !sequence.isEmpty, sequence.count <= tokens.count else { return false }
        for start in 0...(tokens.count - sequence.count) {
            if Array(tokens[start..<(start + sequence.count)]) == sequence { return true }
        }
        return false
    }

    private static func conceptAlternativeMatches(_ alternative: String, in response: String) -> Bool {
        if let expectedNumber = NFExactNumber(parsing: alternative) {
            return numericConcepts(in: response).contains(expectedNumber)
        }

        let patternTokens = conceptTokens(in: alternative, allowsStemWildcard: true)
        let responseTokens = conceptTokens(in: response, allowsStemWildcard: false)
        guard !patternTokens.isEmpty, patternTokens.count <= responseTokens.count else { return false }

        for start in 0...(responseTokens.count - patternTokens.count) {
            let candidate = responseTokens[start..<(start + patternTokens.count)]
            if zip(patternTokens, candidate).allSatisfy({ pattern, value in
                if pattern.hasSuffix("*"), pattern.count > 1 {
                    return value.hasPrefix(pattern.dropLast())
                }
                return pattern == value
            }) {
                return true
            }
        }

        // Preserve the long-standing ability for a phrase such as
        // “random assign” to accept “random assignment”. Symbolic and numeric
        // alternatives use the stricter token path above.
        let symbolicCharacters = CharacterSet(charactersIn: "+−-*/×÷<>=→")
        let containsNonASCII = alternative.unicodeScalars.contains { !$0.isASCII }
        guard alternative.rangeOfCharacter(from: symbolicCharacters) == nil,
              !alternative.contains("*"),
              alternative.contains(" ") || containsNonASCII else { return false }
        let foldedAlternative = alternative.folding(
            options: [.caseInsensitive, .diacriticInsensitive],
            locale: Locale(identifier: "en_US_POSIX")
        )
        let foldedResponse = response.folding(
            options: [.caseInsensitive, .diacriticInsensitive],
            locale: Locale(identifier: "en_US_POSIX")
        )
        return foldedResponse.contains(foldedAlternative)
    }

    private static func numericConcepts(in value: String) -> [NFExactNumber] {
        let pattern = #"(?<![\p{L}\p{N}_.])[-+−]?\d+(?:\.\d+)?(?:[eE][-+]?\d+)?(?![\p{L}\p{N}_.])"#
        guard let expression = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(value.startIndex..<value.endIndex, in: value)
        return expression.matches(in: value, range: range).compactMap { match in
            guard let tokenRange = Range(match.range, in: value) else { return nil }
            return NFExactNumber(parsing: String(value[tokenRange]))
        }
    }

    private static func conceptTokens(in value: String, allowsStemWildcard: Bool) -> [String] {
        let expandedContractions = normalizedMathCommands(in: value)
            .replacingOccurrences(of: "don’t", with: "do not", options: .caseInsensitive)
            .replacingOccurrences(of: "don't", with: "do not", options: .caseInsensitive)
            .replacingOccurrences(of: "doesn’t", with: "does not", options: .caseInsensitive)
            .replacingOccurrences(of: "doesn't", with: "does not", options: .caseInsensitive)
            .replacingOccurrences(of: "isn’t", with: "is not", options: .caseInsensitive)
            .replacingOccurrences(of: "isn't", with: "is not", options: .caseInsensitive)
            .replacingOccurrences(of: "can’t", with: "cannot", options: .caseInsensitive)
            .replacingOccurrences(of: "can't", with: "cannot", options: .caseInsensitive)
        let folded = expandedContractions.folding(
            options: [.caseInsensitive, .diacriticInsensitive],
            locale: Locale(identifier: "en_US_POSIX")
        )
        let characters = Array(folded)
        var result: [String] = []
        var word = ""

        func flushWord() {
            guard !word.isEmpty else { return }
            result.append(word)
            word.removeAll(keepingCapacity: true)
        }

        var index = 0
        while index < characters.count {
            let character = characters[index]
            if character.isLetter || character.isNumber || character == "_" {
                word.append(character)
                index += 1
                continue
            }
            if character == "*", allowsStemWildcard, !word.isEmpty {
                let nextIsWord = index + 1 < characters.count
                    && (characters[index + 1].isLetter || characters[index + 1].isNumber)
                if !nextIsWord {
                    word.append("*")
                    flushWord()
                    index += 1
                    continue
                }
            }
            flushWord()

            let mapped = switch character {
            case "−": "-"
            case "×": "*"
            case "÷": "/"
            case "≤": "<="
            case "≥": ">="
            case "→": "->"
            case "⇒", "⟹": "->"
            case "≠": "!="
            case "·", "⋅": "*"
            default: String(character)
            }
            if ["<", ">", "=", "!", "-"].contains(mapped), index + 1 < characters.count {
                let next = characters[index + 1]
                if next == "=" {
                    result.append(mapped + "=")
                    index += 2
                    continue
                }
                if mapped == "-", next == ">" {
                    result.append("->")
                    index += 2
                    continue
                }
            }
            if ["+", "-", "*", "/", "<", ">", "=", "==", "!=", "<=", ">=", "->"].contains(mapped) {
                result.append(mapped)
            }
            index += 1
        }
        flushWord()
        return result
    }

    /// Learners often type the LaTeX command that the formatted question
    /// shows. Convert only bounded, operator-level commands; arbitrary LaTeX
    /// is never interpreted or executed.
    private static func normalizedMathCommands(in value: String) -> String {
        let characters = Array(value)
        var result = ""
        var index = 0
        let operators: [String: String] = [
            "le": "<=", "leq": "<=", "leqslant": "<=", "lt": "<",
            "ge": ">=", "geq": ">=", "geqslant": ">=", "gt": ">",
            "ne": "!=", "neq": "!=", "times": "*", "cdot": "*",
            "div": "/", "to": "->", "rightarrow": "->"
        ]

        while index < characters.count {
            guard characters[index] == "\\", index + 1 < characters.count else {
                result.append(characters[index])
                index += 1
                continue
            }
            var commandEnd = index + 1
            while commandEnd < characters.count, characters[commandEnd].isLetter {
                commandEnd += 1
            }
            let command = String(characters[(index + 1)..<commandEnd]).lowercased()
            guard let symbol = operators[command] else {
                result.append(characters[index])
                index += 1
                continue
            }
            result.append(" ")
            result.append(symbol)
            result.append(" ")
            index = commandEnd
        }
        return result
    }

}

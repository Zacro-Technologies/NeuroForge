import Foundation
import CryptoKit

/// Reproducible predicates for append-only historical dispositions. The caller
/// owns persistence and replay; these functions never mutate an original score.
enum NFContentCorrectionReason: String, Codable, Equatable, Sendable {
    case duplicateSemanticAnswer
    case contradictoryIntervalGeometry
    case selfReportedAuthority
    case acceptedEquivalentReceivedPartialCredit
    case contradictoryEstimateExactNumericAlias
}

struct NFContentCorrectionFinding: Codable, Equatable, Sendable {
    let policyVersion: Int
    let originalExerciseID: String
    let originalScoringVersion: Int
    let reason: NFContentCorrectionReason
    let excludesVerifiedEvidence: Bool
    let correctedCredit: Double?
}

enum NFContentCorrectionPolicy {
    static let version = 1
    static func findings(exercise: NFExercise, response: NFExerciseResponse?, result: NFExerciseScoringResult) -> [NFContentCorrectionFinding] {
        var findings: [NFContentCorrectionFinding] = []
        func finding(_ reason: NFContentCorrectionReason, excludes: Bool, correctedCredit: Double? = nil) -> NFContentCorrectionFinding {
            NFContentCorrectionFinding(policyVersion: version, originalExerciseID: exercise.id,
                originalScoringVersion: result.scoringVersion, reason: reason,
                excludesVerifiedEvidence: excludes, correctedCredit: correctedCredit)
        }
        if hasContradictoryEstimateExactNumericAliases(exercise) {
            return [finding(.contradictoryEstimateExactNumericAlias, excludes: true)]
        }
        if case let .singleChoice(schema) = exercise.interaction, !NFAnswerSemanticIdentity.hasDistinctOptions(schema.options) {
            findings.append(finding(.duplicateSemanticAnswer, excludes: true))
        }
        if exercise.generatorVersion <= 3, exercise.templateID.contains("data-forensics.uncertainty"),
           exercise.prompt.localizedCaseInsensitiveContains("overlapping"),
           let intervals = intervalPair(in: exercise.representations),
           intervals.0.relationship(to: intervals.1) != .overlapping {
            findings.append(finding(.contradictoryIntervalGeometry, excludes: true))
        }
        if case .selfCheck = exercise.interaction {
            findings.append(finding(.selfReportedAuthority, excludes: true))
        }
        if result.scoringVersion < 8, result.isCorrect, result.credit < 1,
           case let .logicState(schema) = exercise.interaction,
           case let .logicState(submission)? = response,
           ([schema.expectedFinalState] + schema.acceptedEquivalentStates).contains(submission.finalState),
           submission.violatedRuleID == schema.expectedViolatedRuleID {
            findings.append(finding(.acceptedEquivalentReceivedPartialCredit, excludes: false, correctedCredit: 1))
        }
        return findings
    }

    /// Applies only to a retained supported estimate/exact numeric contract, not
    /// to every modern result or to distinct legitimate logic-state outputs.
    static func hasContradictoryEstimateExactNumericAliases(_ exercise: NFExercise) -> Bool {
        guard NFExerciseSchemaValidator.supportsExerciseSchemaVersion(exercise.schemaVersion),
              case let .logicState(schema) = exercise.interaction else { return false }
        return NFExerciseSchemaValidator.hasContradictoryEstimateExactNumericAliases(schema)
    }

    fileprivate static func intervalPair(in representations: [NFExerciseRepresentation]) -> (NFClosedInterval, NFClosedInterval)? {
        for case let .table(_, rows, _) in representations where rows.count >= 2 && rows[0].count >= 3 && rows[1].count >= 3 {
            let ranges = rows.prefix(2).compactMap { row -> NFClosedInterval? in
                let numbers = row[2].split(separator: "–").compactMap { Double($0) }
                guard numbers.count == 2 else { return nil }
                return try? NFClosedInterval(lower: numbers[0], upper: numbers[1])
            }
            if ranges.count == 2 { return (ranges[0], ranges[1]) }
        }
        return nil
    }
}

/// These are derived ledger recommendations, never replacement attempts. A
/// persistence adapter must preserve every original field and any earned XP.
enum NFHistoricalCorrectionDisposition: String, Codable, Equatable, Sendable {
    case correctedDeterministicResult, excludedInvalidItem, excludedUnverifiableContract
    case selfReported, legacyUncalibrated, timingProvenanceIncomplete
    case assistedEvidence, learningMethodOnly, withdrawnDisputedGrade, quarantineForReview
}

enum NFHistoricalCorrectionScope: String, Codable, Equatable, Sendable {
    case accuracy, proficiency, calibration, cleanSpeed, independentEvidence, bandEvidence, retention
}

enum NFHistoricalCorrectionUnresolved: String, Codable, Equatable, Sendable {
    case missingOriginalSnapshot, unverifiedSnapshot, snapshotIdentityMismatch
    case missingTypedResponse, malformedOriginalResult, unavailableOriginalInterval
    case unsupportedChoiceEquivalence, unsupportedSymbolicResponse, unreviewedProseEquivalence
    case unknownAssistanceOrTiming, reportIsNotInvalidation
}

struct NFHistoricalContentCorrectionInput: Codable, Equatable, Sendable {
    let attemptID: String
    let itemID: String
    let templateID: String
    let originalScoringVersion: Int
    let prompt: String
    let rawResponse: String
    let originalExpectedAnswer: String
    let originalIsCorrect: Bool
    let originalCredit: Double
    var generatorVersion: Int? = nil
    var responseFormatRaw: String? = nil
    var originalRecordedAt: Date? = nil
    var originalConfidenceRaw: String? = nil
    /// Supply the immutable original result bytes when retained. Otherwise the
    /// digest covers the immutable fields above, including exact response bytes.
    var originalResultPayload: Data? = nil
    var exactSnapshot: NFExercise? = nil
    /// True only for the captured original or an authenticated exact descriptor
    /// reproduction. A newly generated item with the same seed is insufficient.
    var snapshotVerifiedAsOriginal: Bool = false
    var confirmedTimingWasLostOnResume: Bool = false
    var confirmedAssistanceHistoryWasLostOnResume: Bool = false
    var confirmedSolutionWasVisibleBeforeResponse: Bool = false
    var hasUnresolvedContentReport: Bool = false
}

struct NFHistoricalContentCorrectionRecommendation: Codable, Equatable, Sendable, Identifiable {
    var id: String { idempotencyKey }
    let originalAttemptID: String
    let ruleID: String
    let policyVersion: String
    let disposition: NFHistoricalCorrectionDisposition
    let originalResultDigest: String
    let correctedCredit: Double?
    let correctedScorerVersion: Int?
    let correctedContractVersion: String?
    let excludedScopes: [NFHistoricalCorrectionScope]
    let rationale: String
    let idempotencyKey: String
    /// Present when a finding depends on an authenticated original contract.
    /// Optional so prior append-only recommendations remain decodable as saved.
    var originalContractDigest: String? = nil
}

struct NFHistoricalContentCorrectionAudit: Codable, Equatable, Sendable {
    let recommendations: [NFHistoricalContentCorrectionRecommendation]
    let unresolved: [NFHistoricalCorrectionUnresolved]
}

extension NFContentCorrectionPolicy {
    static let historicalPolicyVersion = "HistoricalContentCorrectionsV2"

    /// Pure, deterministic evaluation of immutable evidence. Missing evidence
    /// never becomes a counterfactual answer, a guessed hint, or a new B band.
    static func audit(_ input: NFHistoricalContentCorrectionInput) -> NFHistoricalContentCorrectionAudit {
        var recommendations: [NFHistoricalContentCorrectionRecommendation] = []
        var unresolved: [NFHistoricalCorrectionUnresolved] = []
        let digest = originalDigest(input)
        let allScopes: [NFHistoricalCorrectionScope] = [.accuracy, .proficiency, .calibration, .cleanSpeed, .independentEvidence, .bandEvidence, .retention]
        func unresolvedFinding(_ value: NFHistoricalCorrectionUnresolved) {
            if !unresolved.contains(value) { unresolved.append(value) }
        }
        func add(_ rule: String, _ disposition: NFHistoricalCorrectionDisposition,
                 scopes: [NFHistoricalCorrectionScope], credit: Double? = nil, rationale: String,
                 contractDigest: String? = nil) {
            let identity = "\(historicalPolicyVersion)\u{0}\(input.attemptID)\u{0}\(rule)\u{0}\(digest)"
                + (contractDigest.map { "\u{0}" + $0 } ?? "")
            recommendations.append(.init(originalAttemptID: input.attemptID, ruleID: rule,
                policyVersion: historicalPolicyVersion, disposition: disposition, originalResultDigest: digest,
                correctedCredit: credit, correctedScorerVersion: credit == nil ? nil : 8,
                correctedContractVersion: credit == nil ? nil : "\(rule).v1", excludedScopes: scopes,
                rationale: rationale, idempotencyKey: sha256(Data(identity.utf8)), originalContractDigest: contractDigest))
        }
        guard input.originalCredit.isFinite, (0...1).contains(input.originalCredit), !input.attemptID.isEmpty else {
            return .init(recommendations: [], unresolved: [.malformedOriginalResult])
        }
        var snapshot: NFExercise?
        if let candidate = input.exactSnapshot {
            if !input.snapshotVerifiedAsOriginal { unresolvedFinding(.unverifiedSnapshot) }
            else if candidate.id != input.itemID || candidate.templateID != input.templateID || candidate.prompt != input.prompt
                || input.generatorVersion.map({ $0 != candidate.generatorVersion }) == true {
                unresolvedFinding(.snapshotIdentityMismatch)
            } else { snapshot = candidate }
        }
        let response = input.rawResponse.data(using: .utf8).flatMap { try? JSONDecoder().decode(NFExerciseResponse.self, from: $0) }
        let typedText: String? = {
            if case let .shortText(value)? = response { return value }
            // Legacy formats saved the text directly. Never interpret undecoded
            // JSON as prose or infer a choice label from its stored option ID.
            if input.responseFormatRaw == "shortText", response == nil,
               !input.rawResponse.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("{") { return input.rawResponse }
            return nil
        }()
        let isLegacy = input.originalScoringVersion < 8
        let recordedGenerator = input.generatorVersion ?? snapshot?.generatorVersion
        // Shipped template IDs carry their edition even when AttemptRecord did
        // not retain a separate generatorVersion. Scorer age alone proves no
        // generator lineage and must never classify an arbitrary custom item.
        let knownOldTemplate = input.templateID.range(of: #"^nf\.fallback\.[^.]+\.[^.]+\.v[1-3]\."#, options: .regularExpression) != nil
        let oldGenerator = recordedGenerator.map { (1...3).contains($0) } ?? (isLegacy && knownOldTemplate)
        let selfCheck = input.responseFormatRaw == "selfCheck" || input.responseFormatRaw == "sourceSelfCheck"
            || { if case .selfCheck? = response { return true }; return false }()
            || { if case .selfCheck? = snapshot?.interaction { return true }; return false }()
        if selfCheck {
            add("self-check-authority", .selfReported, scopes: allScopes,
                rationale: "The retained interaction or response type is a personal self-check. Preserve its authentic rating and exclude objective result claims.")
        }
        if input.hasUnresolvedContentReport {
            add("unresolved-content-report", .quarantineForReview, scopes: [],
                rationale: "Quarantine future selection for local review. A report alone does not invalidate any historical result.")
            unresolvedFinding(.reportIsNotInvalidation)
        }
        if input.confirmedTimingWasLostOnResume || input.confirmedAssistanceHistoryWasLostOnResume {
            var scopes: [NFHistoricalCorrectionScope] = [.cleanSpeed]
            if input.confirmedAssistanceHistoryWasLostOnResume { scopes += [.independentEvidence, .proficiency, .bandEvidence] }
            add("lost-resume-provenance", .timingProvenanceIncomplete, scopes: scopes,
                rationale: "Recorded resume provenance confirms lost timing or assistance history. Preserve accuracy; do not reconstruct elapsed seconds or hint events.")
        }
        // Absence of reviewed metadata is not evidence of B1 or of invalid
        // historical practice. This classification never rewrites accuracy.
        if !selfCheck, snapshot?.contractMetadata?.editorialDemand == nil {
            add("legacy-demand-authority", .legacyUncalibrated, scopes: [.bandEvidence, .proficiency],
                rationale: "No exact reviewed editorial demand record is available. Keep valid historical practice accuracy; do not infer a band from a difficulty scalar.")
        }
        guard !selfCheck else { return .init(recommendations: recommendations, unresolved: unresolved) }

        if input.originalScoringVersion <= 8, let snapshot, hasContradictoryEstimateExactNumericAliases(snapshot) {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            if let originalContract = try? encoder.encode(snapshot) {
                add("contradictory-estimate-exact-alias", .excludedInvalidItem, scopes: allScopes,
                    rationale: "The authenticated original estimate/exact contract accepts an exact numeric alias that differs from its canonical result. Withdraw this invalid item's objective grade; retain the original question, answer, score, and earned activity without regrading the learner.",
                    contractDigest: sha256(originalContract))
            }
            // An invalid numeric alias cannot receive the legacy equivalence
            // repair merely because it appears in the original accepted set.
            return .init(recommendations: recommendations, unresolved: unresolved)
        }

        if oldGenerator, input.templateID.contains("data-forensics.uncertainty") {
            if let snapshot, let intervals = intervalPair(in: snapshot.representations) {
                if snapshot.prompt.localizedCaseInsensitiveContains("overlapping"), intervals.0.relationship(to: intervals.1) != .overlapping {
                    add("contradictory-interval", .excludedInvalidItem, scopes: allScopes,
                        rationale: "The original prompt asserts overlap but the original displayed intervals are touching or disjoint. Withdraw the invalid item without inventing an alternative response.")
                    return .init(recommendations: recommendations, unresolved: unresolved)
                }
            } else {
                unresolvedFinding(snapshot == nil ? .missingOriginalSnapshot : .unavailableOriginalInterval)
                add("unverifiable-interval", .excludedUnverifiableContract, scopes: allScopes,
                    rationale: "This affected legacy interval family cannot be audited without its exact original interval table. Exclusion is precautionary, not a finding that every old item was contradictory.")
            }
        }

        if let snapshot, case let .singleChoice(schema) = snapshot.interaction,
           hasReviewedDuplicate(schema.options) {
            var equivalentValidSelection = false
            if case let .singleChoice(optionID)? = response,
               let selected = schema.options.first(where: { $0.id == optionID }),
               let keyed = schema.options.first(where: { $0.id == schema.correctOptionID }) {
                let identity = NFAnswerSemanticIdentity.canonical(keyed.text)
                // Exact numeric/coordinate identities are reviewed. Casefolded
                // prose alone cannot prove mathematical or subject equivalence.
                equivalentValidSelection = (identity.hasPrefix("number:") || identity.hasPrefix("tuple:"))
                    && NFAnswerSemanticIdentity.canonical(selected.text) == identity
                if snapshot.templateID.contains("coordinate.rotate-ccw"),
                   let spatial = snapshot.representations.compactMap({ value -> NFSpatialRepresentationMetadata? in
                       if case let .spatial(data) = value { return data }; return nil
                   }).first, spatial.points.count == 1, let point = spatial.points.first {
                    // Independent active quarter-turn oracle: (x,y) -> (-y,x).
                    equivalentValidSelection = equivalentValidSelection && point.x.isFinite && point.y.isFinite
                        && identity == NFAnswerSemanticIdentity.canonical("(\(-point.y), \(point.x))")
                }
            }
            if equivalentValidSelection {
                add("duplicate-equivalent-choice", .correctedDeterministicResult,
                    scopes: [.cleanSpeed, .independentEvidence, .bandEvidence, .proficiency, .calibration, .retention], credit: 1,
                    rationale: "The saved selected option is exactly numerically equivalent to the saved valid keyed option. Credit the learner fully; the duplicate-choice item cannot establish independent difficulty or speed.")
            } else {
                unresolvedFinding(response == nil ? .missingTypedResponse : .unsupportedChoiceEquivalence)
                add("duplicate-choice-unresolved", .excludedInvalidItem, scopes: allScopes,
                    rationale: "Equivalent duplicate options invalidate the original single-choice contract, and the saved response does not prove selection of an equivalent valid answer.")
            }
        } else if oldGenerator, input.templateID.contains("coordinate.rotate-ccw"), snapshot == nil {
            unresolvedFinding(.missingOriginalSnapshot)
            add("unverifiable-spatial-choice", .excludedUnverifiableContract, scopes: allScopes,
                rationale: "The affected spatial family lacks its exact original choice set. An option ID or current generator output cannot establish which historical option was equivalent.")
        }

        if isLegacy, let snapshot, case let .logicState(schema) = snapshot.interaction {
            if case let .logicState(submission)? = response {
                if ([schema.expectedFinalState] + schema.acceptedEquivalentStates).contains(submission.finalState),
                   submission.violatedRuleID == schema.expectedViolatedRuleID, input.originalCredit < 1 {
                    add("accepted-state-equivalent", .correctedDeterministicResult, scopes: [], credit: 1,
                        rationale: "The exact original schema explicitly accepts the complete submitted state and rule. Restore full credit for its declared equivalence; no new aliases are inferred.")
                }
            } else { unresolvedFinding(.missingTypedResponse) }
        } else if isLegacy, input.responseFormatRaw == "logicState", snapshot == nil {
            unresolvedFinding(.missingOriginalSnapshot)
            if input.originalIsCorrect && input.originalCredit < 1 {
                add("unverifiable-state-equivalence", .excludedUnverifiableContract, scopes: allScopes,
                    rationale: "The old partial result was marked correct but the original accepted-state set is unavailable. Withdraw unverifiable grading rather than guess which alias was accepted.")
            }
        }

        if isLegacy, let text = typedText {
            auditKnownText(input, text: text, add: { rule, disposition, scopes, credit, rationale in
                add(rule, disposition, scopes: scopes, credit: credit, rationale: rationale)
            }, unresolved: unresolvedFinding)
        }
        if let snapshot, !snapshot.assessmentProtected, let target = NFRetrievalResponseAuthority.legacySuccessorTarget(in: snapshot) {
            let rule = target.id.hasSuffix(".eigenvector-definition") ? "eigenvector-matrix-role" : "retrieval-numeral-direction"
            if let text = typedText {
                let result = NFExerciseScoringEngine.score(.shortText(text), for: snapshot)
                if result.objectiveCorrectness == nil {
                    add(rule + "-unresolved", .withdrawnDisputedGrade, scopes: allScopes,
                        rationale: "The exact saved target has a bounded typed quantity, numeral, or matrix equation contract. Its submitted response is outside that grammar; the prior text-match grade is not reliable.")
                } else {
                    let credit = result.credit
                    if input.originalCredit != credit || input.originalIsCorrect != (credit == 1) {
                        add(rule, .correctedDeterministicResult, scopes: [], credit: credit,
                            rationale: "The exact original target has been evaluated with its explicit typed contract. Decimal quantities accept exact numeric equivalents; binary numeral tasks preserve digit meaning; matrix equations preserve multiplication order and symbol case.")
                    }
                }
            } else {
                unresolvedFinding(.missingTypedResponse)
                add(rule + "-missing", .excludedUnverifiableContract, scopes: allScopes,
                    rationale: "The original typed retrieval target is retained but its submitted response is unavailable. No corrected answer can be inferred.")
            }
        }
        if let snapshot {
            if knownWorkflowOnly(snapshot) {
                add("workflow-objective-only", .learningMethodOnly,
                    scopes: [.proficiency, .independentEvidence, .bandEvidence, .retention],
                    rationale: "The exact task assesses a generic source-filter or retrieval cycle. Retain learning-method practice credit; it does not demonstrate the named subject relationship or delayed retention.")
            }
            if input.confirmedSolutionWasVisibleBeforeResponse || (oldGenerator && knownVisibleSolution(snapshot)) {
                add("visible-solution-scaffold", .assistedEvidence,
                    scopes: [.cleanSpeed, .independentEvidence, .proficiency, .bandEvidence, .calibration, .retention],
                    rationale: "The original rendered content or recorded exposure confirms an answer-bearing scaffold before the response. Preserve the original work as assisted practice.")
            }
        } else if input.confirmedSolutionWasVisibleBeforeResponse {
            add("visible-solution-scaffold", .assistedEvidence,
                scopes: [.cleanSpeed, .independentEvidence, .proficiency, .bandEvidence, .calibration, .retention],
                rationale: "Explicit retained exposure provenance confirms a visible solution before response; accuracy remains historical assisted practice.")
        } else if oldGenerator, ["proof.first-invalid-division", "design.next-discriminating-experiment", "design.discriminating-sequence",
                                "counterexample.even-product", "proof.order-odd-sum", "decompose.compensation",
                                "reconstruction.ordered-cycle", "code-tracing.source-filter"].contains(where: input.templateID.contains) {
            unresolvedFinding(.missingOriginalSnapshot)
            unresolvedFinding(.unknownAssistanceOrTiming)
            add("unverifiable-original-scaffold", .excludedUnverifiableContract,
                scopes: [.cleanSpeed, .independentEvidence, .proficiency, .bandEvidence, .calibration, .retention],
                rationale: "This affected family has no exact original presentation. Preserve historical accuracy but exclude claims requiring verified independent performance or subject retention.")
        }
        return .init(recommendations: recommendations, unresolved: unresolved)
    }

    private static func auditKnownText(_ input: NFHistoricalContentCorrectionInput, text: String,
        add: (String, NFHistoricalCorrectionDisposition, [NFHistoricalCorrectionScope], Double?, String) -> Void,
        unresolved: (NFHistoricalCorrectionUnresolved) -> Void) {
        let integralPrompt = "If F prime equals f, what is the definite integral of f from a to b?"
        let meanPrompt = "How is the arithmetic mean of a finite set of numbers calculated?"
        func matches(_ anchor: String) -> Bool {
            // Known original prompt prefixes only. Do not infer a contract from
            // a substring inside an arbitrary user-supplied mathematical task.
            [anchor, "Answer from memory: " + anchor, "Cloze reconstruction—supply the supported answer for: " + anchor,
             "Complete the source-backed relationship for: " + anchor,
             "Interpret the source figure and state the supported answer for: " + anchor].contains(input.prompt)
        }
        if matches(integralPrompt), ["F(b) minus F(a)", "F(b)-F(a)", "F(b) - F(a)"].contains(input.originalExpectedAnswer) {
            let contract = NFSymbolicAnswerContract(acceptedExpressions: ["F(b)-F(a)"], variables: ["a", "b"], functions: ["F", "f"])
            let expression = text.replacingOccurrences(of: " minus ", with: "-")
            let comparison = NFRestrictedSymbolicAuthority.compare(expression, contract: contract)
            switch comparison {
            case .equivalent:
                if input.originalCredit != 1 || !input.originalIsCorrect {
                    add("integral-function-role", .correctedDeterministicResult, [], 1,
                        "The retained original prompt declares F as the antiderivative and f as its derivative. The bounded symbolic response equals F(b)−F(a).")
                }
            case .different:
                if input.originalCredit != 0 || input.originalIsCorrect {
                    add("integral-function-role", .correctedDeterministicResult, [], 0,
                        "The retained prompt and response establish a different expression under the declared F/f roles. Correct derived credit only; preserve original records and earned XP.")
                }
            case .unsupported:
                // The original catalog explicitly accepted this prose alias.
                if proseIdentity(text) == "the antiderivative at b minus the antiderivative at a" {
                    if input.originalCredit != 1 || !input.originalIsCorrect {
                        add("integral-function-role", .correctedDeterministicResult, [], 1,
                            "The original integral contract explicitly accepted this antiderivative endpoint prose alias. Preserve its full credit.")
                    }
                    return
                }
                unresolved(.unsupportedSymbolicResponse)
                add("integral-response-unresolved", .withdrawnDisputedGrade, [.accuracy, .proficiency, .calibration, .cleanSpeed, .independentEvidence, .bandEvidence, .retention], nil,
                    "The original roles are known but this response lies outside the bounded parser. Withdraw the unverifiable objective grade; do not infer an answer.")
            }
        } else if matches(meanPrompt), input.originalExpectedAnswer == "Add the values and divide by the number of values",
                  let target = NFBundledRetrievalCatalog.target(id: "nf.retrieval.v1.general.arithmetic-mean") {
            let fact = NFExerciseGroundingFact(id: target.id, statement: target.prompt, expectedAnswer: target.answer,
                acceptedAlternatives: target.acceptedAnswers, citationIDs: [])
            if case let .reviewedProse(accepted, _)? = NFRetrievalResponseAuthority.authority(for: fact),
               accepted.map(proseIdentity).contains(proseIdentity(text)) {
                if input.originalCredit < 1 || !input.originalIsCorrect {
                    add("arithmetic-mean-reviewed-equivalence", .correctedDeterministicResult, [], 1,
                        "The exact original arithmetic-mean contract and a reviewed explicit equivalent answer are retained. Restore full derived credit without model-generated grading.")
                }
            } else if !input.originalIsCorrect {
                unresolved(.unreviewedProseEquivalence)
                add("arithmetic-mean-response-unresolved", .withdrawnDisputedGrade, [.accuracy, .proficiency, .calibration, .cleanSpeed, .independentEvidence, .bandEvidence, .retention], nil,
                    "This rejected prose is outside the explicit reviewed equivalence list. Withdraw the disputed grade; retain the answer for self-check or newly authored practice.")
            }
        } else if input.hasUnresolvedContentReport, !input.originalIsCorrect {
            unresolved(.unreviewedProseEquivalence)
            // A report alone only quarantines future selection. Unknown prose
            // cannot justify correcting or invalidating its historical grade.
        }
    }

    static func knownWorkflowOnly(_ exercise: NFExercise) -> Bool {
        guard exercise.provenance.generatorID == "nf.exercise.fallback" else { return false }
        if exercise.templateID.contains("reconstruction.ordered-cycle"), case let .orderedSteps(schema) = exercise.interaction {
            let originalSteps = [
                "retrieve": "Attempt the answer before consulting the reference.",
                "compare": "Compare the recalled relationship with the cited answer.",
                "locate": "Locate the exact missing, reversed, or unsupported element.",
                "retry": "Close the reference and retrieve the corrected relationship once more."
            ]
            return schema.correctOrder == ["retrieve", "compare", "locate", "retry"] && schema.steps.count == 4
                && Set(schema.steps.map(\.id)).count == 4
                && schema.steps.allSatisfy { [originalSteps[$0.id], originalSteps[$0.id].map { NFAppLocalization.localizedCatalogValue($0, locale: Locale(identifier: "ja")) }].contains($0.text) }
        }
        if exercise.templateID.contains("code-tracing.source-filter") {
            return exercise.representations.contains { value in
                if case let .code(_, source, _) = value {
                    return source == "candidates = [supported, reversed, scope_expanded]\nfor candidate in candidates:\n    if source_supports(candidate):\n        return candidate\nreturn unsupported"
                }; return false
            }
        }
        return false
    }

    private static func knownVisibleSolution(_ exercise: NFExercise) -> Bool {
        let context = exercise.independentContextText ?? ""
        if exercise.templateID.contains("proof.first-invalid-division"), context.contains("Because a equals b, the proposed divisor is zero.") { return true }
        if exercise.templateID.contains("design.next-discriminating-experiment") || exercise.templateID.contains("design.discriminating-sequence"),
           context.contains("The useful experiment changes A independently and checks the outcome with a separate calibrated measurement.") { return true }
        return exercise.independentRepresentations.contains { value in
            guard case let .equation(latex, _) = value else { return false }
            if exercise.templateID.contains("counterexample.even-product"), latex == "2 \\times 3 = 6" { return true }
            if exercise.templateID.contains("proof.order-odd-sum"), latex == "(2m+1)+(2n+1)=2(m+n+1)" { return true }
            if exercise.templateID.contains("decompose.compensation"),
               latex.range(of: #"^\d+\(\d+ [-+] 1\)$"#, options: .regularExpression) != nil { return true }
            return false
        }
    }

    private static func proseIdentity(_ value: String) -> String {
        value.folding(options: [.caseInsensitive, .widthInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    private static func hasReviewedDuplicate(_ options: [NFChoiceOption]) -> Bool {
        let identities = options.map { option in
            let identity = NFAnswerSemanticIdentity.canonical(option.text)
            if identity.hasPrefix("number:") || identity.hasPrefix("tuple:") { return identity }
            // Case distinctions can carry function/variable meaning. Unknown
            // text requires literal identity, not a casefolded semantic guess.
            return "literal:" + option.text.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return Set(identities).count != identities.count
    }

    private static func originalDigest(_ input: NFHistoricalContentCorrectionInput) -> String {
        // A fixed ordered array avoids dictionary order and floating-point JSON
        // formatting changing across independent persistence adapters.
        let fields = [input.attemptID, input.itemID, input.templateID, String(input.originalScoringVersion), input.prompt,
            input.rawResponse, input.originalExpectedAnswer, String(input.originalIsCorrect), String(input.originalCredit),
            input.originalRecordedAt.map { String($0.timeIntervalSince1970) } ?? "", input.originalConfidenceRaw ?? "",
            input.originalResultPayload?.base64EncodedString() ?? ""]
        return sha256((try? JSONEncoder().encode(fields)) ?? Data())
    }
    private static func sha256(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
}

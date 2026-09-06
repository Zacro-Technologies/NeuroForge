import Foundation

/// Renderer policy is independent of the exercise's Codable schema, its
/// generator and its scorer. The two legacy pins were emitted by the first
/// captured-slot implementation; retaining them is an explicit compatibility
/// path for that same renderer, not an inference from a future content schema.
enum NFSessionPresentationPolicy {
    static let version = "UniversalPresentationV1"
    static let supportedVersions: Set<String> = [version, "1", "2"]
}

/// Confidence follows the semantic response, independent of dictionary order
/// and number formatting. This identity grants no scoring authority.
enum NFConfidenceResponseIdentity {
    static func value(_ response: NFExerciseResponse, exercise: NFExercise) -> String {
        let validation = NFExerciseResponseValidator.validate(response, for: exercise.interaction,
            localeIdentifier: exercise.localeIdentifier)
        if let numeric = validation.numericSubmission {
            return numeric.value.canonicalString + "|" + (numeric.submittedUnit ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let normalized: NFExerciseResponse
        switch response {
        case let .multipleChoice(ids): normalized = .multipleChoice(optionIDs: ids.sorted())
        case let .claimEvidence(submission):
            normalized = .claimEvidence(.init(pairs: submission.pairs.map {
                .init(claimID: $0.claimID, evidenceIDs: $0.evidenceIDs.sorted())
            }.sorted { $0.claimID < $1.claimID }))
        case let .shortText(text): normalized = .shortText(text.trimmingCharacters(in: .whitespacesAndNewlines))
        default: normalized = response
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return (try? encoder.encode(normalized).base64EncodedString()) ?? "unavailable"
    }
}

enum NFInstructionalRole: String, Codable, Equatable, Sendable {
    case essentialGiven, optionalPracticeHint, postResponseReference, workedExample
}

struct NFRoleTaggedRepresentation: Codable, Equatable, Sendable {
    let role: NFInstructionalRole
    let representation: NFExerciseRepresentation
}

struct NFExerciseContractMetadata: Codable, Equatable, Sendable {
    let contractSchemaVersion: Int
    let semanticProblemID: String
    let semanticFingerprint: String
    let contractRevision: Int
    let presentationRevision: Int
    let objectiveID: String
    let familyID: String
    let structureID: String
    let generatorVersion: Int
    let contentEditionID: String
    let canonicalParameters: [String: String]
    let contextRole: NFInstructionalRole
    let representationRoles: [NFInstructionalRole]
    let supplementaryRepresentations: [NFRoleTaggedRepresentation]
    /// nil means unreviewed against the new B1–B4 specification, not B1.
    var editorialDemand: NFEditorialDemandRecord? = nil
    var scienceStudy: NFScienceStudyContract? = nil
    var graphConstruction: NFGraphConstructionContract? = nil
    var transferRelationship: NFTransferRelationshipContract? = nil
    var retrievalAuthorityPolicyVersion: Int? = nil
    var retrievalAsset: NFRetrievalAssetContract? = nil
    var spatialStructure: NFSpatialStructureContract? = nil
    var coordinateTransform: NFCoordinateTransformContract? = nil
    var solidSection: NFSolidSectionContract? = nil
    var netFolding: NFNetFoldingContract? = nil
    var coordinateReasoning: NFCoordinateReasoningContract? = nil
    var spatialAssembly: NFSpatialAssemblyContract? = nil
    let reviewStatus: String
    let supersedesGeneratorVersion: Int?
}

extension NFExercise {
    var semanticProblemID: String { contractMetadata?.semanticProblemID ?? id }
    var contentFamilyID: String { contractMetadata?.familyID ?? templateFamily }
    var contentStructureID: String { contractMetadata?.structureID ?? templateID }
    var independentRepresentations: [NFExerciseRepresentation] {
        guard let roles = contractMetadata?.representationRoles, roles.count == representations.count else { return representations }
        return zip(representations, roles).compactMap { $0.1 == .essentialGiven ? $0.0 : nil }
    }
    var independentContextText: String? {
        contractMetadata?.contextRole == .optionalPracticeHint || contractMetadata?.contextRole == .postResponseReference
            || contractMetadata?.contextRole == .workedExample ? nil : contextText
    }
}


/// A local synthetic teaching study, not an imported source or reviewed band.
/// Its typed observations and competing design controls bind both visible stages.
struct NFScienceStudyContract: Codable, Equatable, Sendable {
    struct Group: Codable, Equatable, Sendable {
        let label: String
        let mean: Int
        let baselineMean: Int
    }
    struct Experiment: Codable, Equatable, Sendable, Identifiable {
        let id: String
        let text: String
        let randomizesWithinBaseline: Bool
        let commonCalibratedMeasurement: Bool
        let explanation: String
        let interventionPrediction: String
        let baselinePrediction: String
        var isolatesDeclaredEffect: Bool { randomizesWithinBaseline && commonCalibratedMeasurement }
    }
    var schemaVersion = 1
    let policyVersion: Int
    let studyID: String
    let sourceKind: String
    let title: String
    let contextID: String
    let designDescription: String
    let unit: String
    let baselineUnit: String
    let groupHeader: String
    let meanHeader: String
    let baselineHeader: String
    let groups: [Group]
    let evidenceClaims: [NFClaimOption]
    let observations: [NFEvidenceOption]
    let experimentClaim: NFClaimOption
    let experiments: [Experiment]
    let conclusion: String
    static let policyVersion = 1
    static let contextIDs = ["puzzle", "map", "vocabulary"]
    static let generatorVersion = 6

    var table: NFExerciseRepresentation {
        .table(headers: [groupHeader, meanHeader, baselineHeader],
            rows: groups.map { [$0.label, "\($0.mean) \(unit)", "\($0.baselineMean) \(baselineUnit)"] },
            accessibilitySummary: designDescription)
    }
    var evidenceSchema: NFClaimEvidenceResponseSchema {
        .init(claims: evidenceClaims, evidence: observations,
            correctPairs: [
                .init(claimID: evidenceClaims[0].id, evidenceIDs: [observations[0].id]),
                .init(claimID: evidenceClaims[1].id, evidenceIDs: [observations[1].id, observations[2].id])
            ], selectionScopes: evidenceClaims.map {
                .init(claimID: $0.id, evidenceIDs: observations.map(\.id), minimumSelections: 1, maximumSelections: observations.count)
            })
    }
    var responseSchema: NFClaimEvidenceResponseSchema {
        let first = evidenceSchema
        return .init(claims: evidenceClaims + [experimentClaim],
            evidence: observations + experiments.map { .init(id: $0.id, text: $0.text, citationID: nil) },
            correctPairs: first.correctPairs + [.init(claimID: experimentClaim.id,
                evidenceIDs: experiments.filter(\.isolatesDeclaredEffect).map(\.id))],
            selectionScopes: (first.selectionScopes ?? []) + [.init(claimID: experimentClaim.id,
                evidenceIDs: experiments.map(\.id), minimumSelections: 1, maximumSelections: 1)])
    }
    var isSupported: Bool {
        guard schemaVersion == 1, policyVersion == Self.policyVersion, Self.contextIDs.contains(contextID), sourceKind == "syntheticTeachingStudy",
              studyID.hasPrefix("nf.science-study.v1."), studyID.utf8.count <= 128,
              groups.count == 2, groups[0].mean != groups[1].mean,
              groups[0].baselineMean != groups[1].baselineMean,
              groups.allSatisfy({ (-10_000...10_000).contains($0.mean) && (0...100).contains($0.baselineMean) }),
              evidenceClaims.count == 2, observations.count == 3, experiments.count == 3,
              experiments.filter(\.isolatesDeclaredEffect).count == 1 else { return false }
        let ids = evidenceClaims.map(\.id) + [experimentClaim.id] + observations.map(\.id) + experiments.map(\.id)
        guard ids.allSatisfy({ !$0.isEmpty && $0.utf8.count <= 128 }), Set(ids).count == ids.count,
              observations.allSatisfy({ $0.citationID == nil }) else { return false }
        let text = [title, designDescription, unit, baselineUnit, groupHeader, meanHeader, baselineHeader, conclusion, experimentClaim.text]
            + groups.map(\.label) + evidenceClaims.map(\.text) + observations.map(\.text)
            + experiments.flatMap { [$0.text, $0.explanation, $0.interventionPrediction, $0.baselinePrediction] }
        return text.allSatisfy { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && $0.utf8.count <= 4_096 }
    }
    func isCompatible(with exercise: NFExercise) -> Bool {
        guard isSupported, !exercise.assessmentProtected,
              [.practice, .documentPractice].contains(exercise.purpose),
              exercise.evidenceClass == exercise.purpose.evidenceClass,
              exercise.schemaVersion == 3, exercise.lab == .scientificReasoning, exercise.generatorVersion == Self.generatorVersion,
              exercise.provenance.generatorID == "nf.exercise.fallback",
              exercise.provenance.generatorVersion == Self.generatorVersion,
              exercise.templateID.hasSuffix(".claim.evidence.bounds"),
              exercise.citations.isEmpty, exercise.provenance.sourceDocumentIDs.isEmpty,
              exercise.provenance.sourceChunkIDs.isEmpty,
              exercise.independentRepresentations == [table],
              case let .claimEvidence(schema) = exercise.interaction else { return false }
        return schema == responseSchema
    }
    static func make(exercise: NFExercise) -> Self? {
        guard let study = exercise.contractMetadata?.scienceStudy, study.isCompatible(with: exercise) else { return nil }
        return study
    }
}

/// Only the first completed evidence mapping is frozen here; ordinary editable
/// response bytes continue to own the final experiment selection.
struct NFScienceStudyDraft: Codable, Equatable, Sendable {
    var schemaVersion = 1
    let exerciseDigest: String
    var firstEvidence: NFClaimEvidenceSubmission? = nil
    var lockedAtActiveSeconds: Double? = nil
    var awaitsEvidence: Bool { firstEvidence == nil }
    static func initial(for exercise: NFExercise) -> Self? {
        guard NFScienceStudyContract.make(exercise: exercise) != nil,
              let digest = try? NFLocalItemCheckpoint.digest(exercise) else { return nil }
        return .init(exerciseDigest: digest)
    }
    func isCompatible(with exercise: NFExercise, response: NFExerciseResponse? = nil) -> Bool {
        guard schemaVersion == 1, exerciseDigest == (try? NFLocalItemCheckpoint.digest(exercise)),
              let study = NFScienceStudyContract.make(exercise: exercise),
              (firstEvidence == nil) == (lockedAtActiveSeconds == nil),
              lockedAtActiveSeconds.map(NFSessionDurationPolicy.isValid) ?? true else { return false }
        if let firstEvidence {
            guard NFExerciseResponseValidator.validate(.claimEvidence(firstEvidence), for: .claimEvidence(study.evidenceSchema),
                localeIdentifier: exercise.localeIdentifier).isValid else { return false }
        }
        guard let response else { return true }
        guard case let .claimEvidence(submission) = response,
              Set(submission.pairs.map(\.claimID)).count == submission.pairs.count,
              Set(submission.pairs.map(\.claimID)).isSubset(of: Set(study.responseSchema.claims.map(\.id))),
              submission.pairs.allSatisfy({ pair in
                  let scope = study.responseSchema.selectionScopes?.first { $0.claimID == pair.claimID }
                  return Set(pair.evidenceIDs).count == pair.evidenceIDs.count
                    && Set(pair.evidenceIDs).isSubset(of: Set(scope?.evidenceIDs ?? []))
                    && pair.evidenceIDs.count <= (scope?.maximumSelections ?? 0)
              }) else { return false }
        let map = Dictionary(uniqueKeysWithValues: submission.pairs.map { ($0.claimID, Set($0.evidenceIDs)) })
        if let firstEvidence {
            return firstEvidence.pairs.allSatisfy { map[$0.claimID, default: []] == Set($0.evidenceIDs) }
        }
        return map[study.experimentClaim.id, default: []].isEmpty
    }
    func evidenceValidation(_ response: NFExerciseResponse, exercise: NFExercise) -> NFExerciseResponseValidation {
        guard let study = NFScienceStudyContract.make(exercise: exercise), case let .claimEvidence(submission) = response else {
            return .init(issue: .responseTypeMismatch, numericSubmission: nil)
        }
        let ids = Set(study.evidenceClaims.map(\.id))
        let first = NFClaimEvidenceSubmission(pairs: submission.pairs.filter { ids.contains($0.claimID) })
        return NFExerciseResponseValidator.validate(.claimEvidence(first), for: .claimEvidence(study.evidenceSchema),
            localeIdentifier: exercise.localeIdentifier)
    }
    func locking(response: NFExerciseResponse, exercise: NFExercise, activeSeconds: Double) -> Self? {
        guard awaitsEvidence, isCompatible(with: exercise, response: response),
              NFSessionDurationPolicy.isValid(activeSeconds), evidenceValidation(response, exercise: exercise).isValid,
              let study = NFScienceStudyContract.make(exercise: exercise), case let .claimEvidence(submission) = response else { return nil }
        let ids = Set(study.evidenceClaims.map(\.id))
        var next = self
        next.firstEvidence = .init(pairs: submission.pairs.filter { ids.contains($0.claimID) }.map {
            .init(claimID: $0.claimID, evidenceIDs: $0.evidenceIDs.sorted())
        }.sorted { $0.claimID < $1.claimID })
        next.lockedAtActiveSeconds = activeSeconds
        return next
    }
    static func permits(_ draft: Self?, exercise: NFExercise, response: NFExerciseResponse? = nil, committing: Bool = false) -> Bool {
        guard exercise.hasSupportedScienceStudy else { return false }
        guard exercise.contractMetadata?.scienceStudy != nil else { return draft == nil }
        guard let draft, draft.isCompatible(with: exercise, response: response) else { return false }
        return !committing || !draft.awaitsEvidence
    }
    func recoveryText(exercise: NFExercise) -> String? {
        guard isCompatible(with: exercise), let firstEvidence else { return nil }
        return NFResponsePresentation.text(.claimEvidence(firstEvidence), exercise: exercise)
    }
}

extension NFExercise {
    var hasSupportedScienceStudy: Bool {
        guard let study = contractMetadata?.scienceStudy else { return schemaVersion != 3 }
        return study.isCompatible(with: self)
    }
}

struct NFScienceStudyHistoryProjection: Sendable {
    let exercise: NFExercise
    let draft: NFScienceStudyDraft
    static func make(exercise: NFExercise?, draft: NFScienceStudyDraft?, isProtected: Bool) -> Self? {
        guard !isProtected, let exercise, !exercise.assessmentProtected, let draft,
              draft.isCompatible(with: exercise) else { return nil }
        return .init(exercise: exercise, draft: draft)
    }
}


/// A declared, synthetic cross-context task. This is a practice contract, not
/// a measured transfer benefit or a protected near-transfer instrument.
struct NFTransferRelationshipContract: Codable, Equatable, Sendable {
    var schemaVersion = 1
    let policyVersion: Int
    let contextID: String
    let sourceTitle: String
    let targetTitle: String
    let sourceRate: Int
    let sourceMinutes: Int
    let targetRate: Int
    let targetSeconds: Int
    let sourceUnit: String
    let targetUnit: String
    let sourceDescription: String
    let targetDescription: String
    let tableHeaders: [String]
    let minuteUnit: String
    let secondUnit: String
    let unknownTotalLabel: String
    var tableRows: [[String]] {
        [[sourceTitle, "\(sourceRate) \(sourceUnit)/\(minuteUnit)", "\(sourceMinutes) \(minuteUnit)", "\(sourceRate * sourceMinutes) \(sourceUnit)"],
         [targetTitle, "\(targetRate) \(targetUnit)/\(minuteUnit)", "\(targetSeconds) \(secondUnit)", unknownTotalLabel]]
    }
    let tableSummary: String
    let relationships: [NFChoiceOption]
    let sharedStructure: String
    let changedConditions: String
    let requiredSkills: [String]
    static let generatorVersion = 8
    static let contextIDs = ["water-tank", "garden", "paint"]
    static let totalKey = "targetTotal"
    static let productID = "relationship.constant-accumulation"
    var targetTotal: Int { targetRate * targetSeconds / 60 }
    var table: NFExerciseRepresentation { .table(headers: tableHeaders, rows: tableRows, accessibilitySummary: tableSummary) }
    var responseSchema: NFLogicStateResponseSchema {
        .init(initialState: [Self.totalKey: "0"], expectedFinalState: [Self.totalKey: String(targetTotal)],
            acceptedEquivalentStates: [], ruleOptions: relationships, expectedViolatedRuleID: Self.productID,
            fieldDomains: [Self.totalKey: .exactNumber])
    }
    var expectedResponse: NFExerciseResponse { .logicState(.init(finalState: responseSchema.expectedFinalState, violatedRuleID: Self.productID)) }
    var isSupported: Bool {
        let ids = Set(relationships.map(\.id))
        let text = [sourceTitle, targetTitle, sourceUnit, targetUnit, sourceDescription, targetDescription,
            tableSummary, sharedStructure, changedConditions, minuteUnit, secondUnit, unknownTotalLabel] + tableHeaders + tableRows.flatMap { $0 } + relationships.map(\.text)
        return schemaVersion == 1 && policyVersion == 1 && Self.contextIDs.contains(contextID)
            && (2...12).contains(sourceRate) && (2...8).contains(sourceMinutes)
            && (4...40).contains(targetRate) && targetRate.isMultiple(of: 4)
            && (30...135).contains(targetSeconds) && targetSeconds.isMultiple(of: 15)
            && requiredSkills == ["skill.quantitative", "skill.mentalMath"]
            && relationships.count == 4 && ids == [Self.productID, "relationship.divide", "relationship.add", "relationship.copy"]
            && ids.allSatisfy { !$0.isEmpty && $0.utf8.count <= 128 }
            && tableHeaders.count == 4 && tableRows.count == 2 && tableRows.allSatisfy { $0.count == 4 }
            && text.allSatisfy { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && $0.utf8.count <= 4_096 }
    }
    func isCompatible(with exercise: NFExercise) -> Bool {
        guard isSupported, !exercise.assessmentProtected, [.practice, .documentPractice].contains(exercise.purpose),
              exercise.evidenceClass == exercise.purpose.evidenceClass,
              exercise.schemaVersion == 5, exercise.skillWeights == ["skill.transfer": 0.7, "skill.quantitative": 0.15, "skill.mentalMath": 0.15], exercise.lab == .transfer, exercise.generatorVersion == Self.generatorVersion,
              exercise.provenance.generatorID == "nf.exercise.fallback", exercise.provenance.generatorVersion == Self.generatorVersion,
              exercise.templateID.hasSuffix(".field-shift.rate-product"), exercise.citations.isEmpty,
              exercise.provenance.sourceDocumentIDs.isEmpty, exercise.provenance.sourceChunkIDs.isEmpty,
              exercise.independentRepresentations == [table], exercise.contextText == sourceDescription + "\n" + targetDescription,
              tableSummary == sourceDescription + "\n" + targetDescription, case let .logicState(schema) = exercise.interaction,
              schema == responseSchema else { return false }
        return true
    }
    static func make(exercise: NFExercise) -> Self? {
        guard let value = exercise.contractMetadata?.transferRelationship, value.isCompatible(with: exercise) else { return nil }
        return value
    }
    func responseText(_ response: NFExerciseResponse) -> String? {
        guard case let .logicState(value) = response, Set(value.finalState.keys) == [Self.totalKey],
              value.violatedRuleID.map({ id in relationships.contains { $0.id == id } }) ?? true else { return nil }
        let label = value.violatedRuleID.flatMap { id in relationships.first { $0.id == id }?.text }
        let amount = value.finalState[Self.totalKey].flatMap { $0.isEmpty ? nil : "\($0) \(targetUnit)" }
        return [label, amount].compactMap { $0 }.joined(separator: "\n")
    }
}

struct NFTransferRelationshipDraft: Codable, Equatable, Sendable {
    var schemaVersion = 1
    let exerciseDigest: String
    var firstRelationshipID: String? = nil
    var lockedAtActiveSeconds: Double? = nil
    var awaitsRelationship: Bool { firstRelationshipID == nil }
    static func initial(for exercise: NFExercise) -> Self? {
        guard NFTransferRelationshipContract.make(exercise: exercise) != nil,
              let digest = try? NFLocalItemCheckpoint.digest(exercise) else { return nil }
        return .init(exerciseDigest: digest)
    }
    func isCompatible(with exercise: NFExercise, response: NFExerciseResponse? = nil) -> Bool {
        guard schemaVersion == 1, exerciseDigest == (try? NFLocalItemCheckpoint.digest(exercise)),
              let contract = NFTransferRelationshipContract.make(exercise: exercise),
              (firstRelationshipID == nil) == (lockedAtActiveSeconds == nil),
              lockedAtActiveSeconds.map(NFSessionDurationPolicy.isValid) ?? true,
              firstRelationshipID.map({ id in contract.relationships.contains { $0.id == id } }) ?? true else { return false }
        guard let response else { return true }
        guard case let .logicState(value) = response,
              Set(value.finalState.keys) == [NFTransferRelationshipContract.totalKey],
              value.finalState.values.allSatisfy({ $0.count <= 500 && $0.utf8.count <= 2_000 }),
              value.violatedRuleID.map({ id in contract.relationships.contains { $0.id == id } }) ?? true else { return false }
        if let firstRelationshipID { return value.violatedRuleID == firstRelationshipID }
        return value.finalState.values.allSatisfy { $0.isEmpty }
    }
    func locking(response: NFExerciseResponse, exercise: NFExercise, activeSeconds: Double) -> Self? {
        guard awaitsRelationship, isCompatible(with: exercise, response: response),
              NFSessionDurationPolicy.isValid(activeSeconds), case let .logicState(value) = response,
              let id = value.violatedRuleID else { return nil }
        var next = self; next.firstRelationshipID = id; next.lockedAtActiveSeconds = activeSeconds
        return next
    }
    static func permits(_ draft: Self?, exercise: NFExercise, response: NFExerciseResponse? = nil, committing: Bool = false) -> Bool {
        guard exercise.hasSupportedTransferRelationship else { return false }
        guard exercise.contractMetadata?.transferRelationship != nil else { return draft == nil }
        guard let draft, draft.isCompatible(with: exercise, response: response) else { return false }
        return !committing || !draft.awaitsRelationship
    }
    func recoveryText(exercise: NFExercise) -> String? {
        guard isCompatible(with: exercise), let id = firstRelationshipID,
              let contract = NFTransferRelationshipContract.make(exercise: exercise) else { return nil }
        return contract.relationships.first { $0.id == id }?.text
    }
}

extension NFExercise {
    var hasSupportedTransferRelationship: Bool {
        guard let contract = contractMetadata?.transferRelationship else { return schemaVersion != 5 }
        return contract.isCompatible(with: self)
    }
}

struct NFTransferRelationshipHistoryProjection: Sendable {
    let exercise: NFExercise
    let draft: NFTransferRelationshipDraft
    static func make(exercise: NFExercise?, draft: NFTransferRelationshipDraft?, isProtected: Bool) -> Self? {
        guard !isProtected, let exercise, !exercise.assessmentProtected, let draft,
              draft.isCompatible(with: exercise) else { return nil }
        return .init(exercise: exercise, draft: draft)
    }
}


/// One ordinary, synthetic direct-proportion task with an exact integer grid.
/// Neither a curve inferred from prose nor a reviewed editorial-band claim.
struct NFGraphConstructionContract: Codable, Equatable, Sendable {
    struct Point: Codable, Equatable, Sendable {
        let x: Int
        let y: Int
        var response: NFExerciseResponse { .logicState(.init(finalState: ["x": String(x), "y": String(y)], violatedRuleID: nil)) }
    }
    var schemaVersion = 1
    let policyVersion: Int
    let sourceKind: String
    let xLabel: String
    let xUnit: String
    let yLabel: String
    let yUnit: String
    let sourceDescription: String
    let baseline: Point
    let targetX: Int
    let maximumX: Int
    let maximumY: Int
    static let policyVersion = 1
    static let generatorVersion = 7
    static let activityID = "nf.default.quantitative.scaling"
    static var mechanicID: String? { NFDefaultContentCatalog.activity(id: activityID)?.mechanicID }
    static func matchesMechanic(_ value: String?) -> Bool {
        guard let expected = mechanicID else { return false }
        return value == expected
    }
    var xTitle: String { "\(xLabel) (\(xUnit))" }
    var yTitle: String { "\(yLabel) (\(yUnit))" }
    var expectedPoint: Point? {
        guard baseline.x == 1, (1...8).contains(baseline.y), (2...5).contains(targetX) else { return nil }
        return .init(x: targetX, y: baseline.y * targetX)
    }
    var table: NFExerciseRepresentation {
        .table(headers: [xTitle, yTitle], rows: [[String(baseline.x), String(baseline.y)]], accessibilitySummary: sourceDescription)
    }
    var responseSchema: NFLogicStateResponseSchema? {
        guard let expectedPoint else { return nil }
        return .init(initialState: ["x": String(baseline.x), "y": String(baseline.y)], expectedFinalState: ["x": String(expectedPoint.x), "y": String(expectedPoint.y)],
            acceptedEquivalentStates: [], ruleOptions: [], expectedViolatedRuleID: nil,
            fieldDomains: ["x": .exactNumber, "y": .exactNumber])
    }
    var isSupported: Bool {
        schemaVersion == 1 && policyVersion == Self.policyVersion && sourceKind == "syntheticDirectProportion"
            && maximumX == 6 && maximumY == 50 && expectedPoint != nil
            && xUnit == "s" && yUnit == "m"
            && [xLabel, yLabel, sourceDescription].allSatisfy { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && $0.utf8.count <= 2_048 }
    }
    func isCompatible(with exercise: NFExercise) -> Bool {
        guard isSupported, !exercise.assessmentProtected, exercise.availabilityReason == nil,
              [.practice, .documentPractice].contains(exercise.purpose), exercise.evidenceClass == exercise.purpose.evidenceClass,
              exercise.schemaVersion == 4, exercise.lab == .quantitative, exercise.generatorVersion == Self.generatorVersion,
              exercise.provenance.generatorID == "nf.exercise.fallback", exercise.provenance.generatorVersion == Self.generatorVersion,
              exercise.contractMetadata?.generatorVersion == Self.generatorVersion,
              exercise.contractMetadata?.familyID == Self.activityID,
              exercise.templateID.hasSuffix(".scaling.construct-point"), exercise.citations.isEmpty,
              exercise.provenance.sourceDocumentIDs.isEmpty, exercise.provenance.sourceChunkIDs.isEmpty,
              exercise.sourceContext.sourceDocumentIDs.isEmpty, exercise.sourceContext.sourceChunkIDs.isEmpty,
              exercise.independentRepresentations == [table], !exercise.rubric.permitsPartialCredit,
              case let .logicState(schema) = exercise.interaction else { return false }
        return schema == responseSchema
    }
    static func make(exercise: NFExercise) -> Self? {
        guard let graph = exercise.contractMetadata?.graphConstruction, graph.isCompatible(with: exercise) else { return nil }
        return graph
    }
    func contains(_ point: Point) -> Bool {
        isSupported && (0...maximumX).contains(point.x) && (0...maximumY).contains(point.y)
    }
    func point(from response: NFExerciseResponse) -> Point? {
        guard isSupported, case let .logicState(value) = response, value.violatedRuleID == nil,
              Set(value.finalState.keys) == ["x", "y"],
              let x = NFStateValueAuthority.exactNumber(value.finalState["x"] ?? ""), x.denominator == 1,
              let y = NFStateValueAuthority.exactNumber(value.finalState["y"] ?? ""), y.denominator == 1,
              let intX = Int(exactly: x.numerator), let intY = Int(exactly: y.numerator) else { return nil }
        let point = Point(x: intX, y: intY)
        return contains(point) ? point : nil
    }
    func adjusted(_ point: Point?, axis: Axis, delta: Int) -> Point? {
        guard isSupported, delta == 1 || delta == -1, point.map(contains) ?? true else { return nil }
        let old = point ?? .init(x: 0, y: 0)
        return .init(x: axis == .x ? min(maximumX, max(0, old.x + delta)) : old.x,
            y: axis == .y ? min(maximumY, max(0, old.y + delta)) : old.y)
    }
    enum Axis: String, CaseIterable, Sendable { case x, y }
    /// Pointer coordinates are mapped to the declared unit grid, never to an
    /// interpolated answer. Nonfinite/malformed geometry cannot enter a response.
    func snapped(normalizedX: Double, normalizedY: Double) -> Point? {
        guard isSupported, normalizedX.isFinite, normalizedY.isFinite else { return nil }
        return .init(x: Int((min(1, max(0, normalizedX)) * Double(maximumX)).rounded()),
            y: Int((min(1, max(0, normalizedY)) * Double(maximumY)).rounded()))
    }
    func normalized(_ point: Point) -> (x: Double, y: Double)? {
        guard contains(point) else { return nil }
        return (Double(point.x) / Double(maximumX), Double(point.y) / Double(maximumY))
    }
    func responseDescription(_ value: NFLogicStateSubmission) -> String {
        "\(xTitle): \(value.finalState["x"] ?? "")\n\(yTitle): \(value.finalState["y"] ?? "")"
    }
}

extension NFExercise {
    var hasSupportedGraphConstruction: Bool {
        guard let graph = contractMetadata?.graphConstruction else { return schemaVersion != 4 }
        return graph.isCompatible(with: self)
    }
}

struct NFGraphConstructionHistoryProjection: Sendable {
    let graph: NFGraphConstructionContract
    let response: NFExerciseResponse
    let savedPoint: NFGraphConstructionContract.Point?
    static func make(exercise: NFExercise?, response: NFExerciseResponse?, isProtected: Bool) -> Self? {
        guard !isProtected, let exercise, !exercise.assessmentProtected,
              let graph = NFGraphConstructionContract.make(exercise: exercise), let response,
              case .logicState = response else { return nil }
        return .init(graph: graph, response: response, savedPoint: graph.point(from: response))
    }
}

/// Bounded editor-local undo retains the exact prior typed response. A restore,
/// owner change, or other edit invalidates history whose predecessor no longer matches.
struct NFGraphConstructionEditHistory {
    struct Edit { let previous: NFExerciseResponse; let next: NFExerciseResponse }
    private(set) var edits: [Edit] = []
    mutating func record(previous: NFExerciseResponse, next: NFExerciseResponse) {
        guard previous != next else { return }
        synchronize(current: previous)
        edits.append(.init(previous: previous, next: next))
        if edits.count > 50 { edits.removeFirst(edits.count - 50) }
    }
    mutating func synchronize(current: NFExerciseResponse) {
        if let last = edits.last, last.next != current { edits.removeAll() }
    }
    mutating func undo(current: NFExerciseResponse) -> NFExerciseResponse? {
        synchronize(current: current)
        return edits.popLast()?.previous
    }
}

/// A provisional, locally authored rendering of an existing knowledge target.
/// It carries actual givens and a typed evaluator; it grants no reviewed band.
struct NFRetrievalAssetContract: Codable, Equatable, Sendable {
    enum Form: String, Codable, CaseIterable, Equatable, Sendable {
        case cloze, equation, figure
        var variant: Int { switch self { case .cloze: 2; case .equation: 6; case .figure: 7 } }
        var templateSlug: String { switch self { case .cloze: "cloze.relationship"; case .equation: "equation-reconstruction"; case .figure: "figure-interpretation" } }
        init?(variant: Int) { guard let value = Self.allCases.first(where: { $0.variant == variant }) else { return nil }; self = value }
    }
    struct Figure: Codable, Equatable, Sendable {
        enum Kind: String, Codable, Equatable, Sendable { case observations, line, rectangle }
        struct Point: Codable, Equatable, Sendable, Identifiable {
            let id: Int
            let label: String
            let x: Int
            let y: Int
        }
        let kind: Kind
        let points: [Point]
        let labelTitle: String
        let xTitle: String
        let yTitle: String
        let summary: String
        var xBounds: ClosedRange<Double> { 0...Double(max(1, points.map(\.x).max() ?? 1)) }
        var yBounds: ClosedRange<Double> { 0...Double(max(1, points.map(\.y).max() ?? 1)) }
        var table: NFExerciseRepresentation {
            kind == .observations
                ? .table(headers: [xTitle, yTitle], rows: points.map { [String($0.x), String($0.y)] }, accessibilitySummary: summary)
                : .table(headers: [labelTitle, xTitle, yTitle], rows: points.map { [$0.label, String($0.x), String($0.y)] }, accessibilitySummary: summary)
        }
    }
    var policyVersion: Int = 1
    let targetID: String
    let form: Form
    let localeIdentifier: String
    let sourcePrompt: String
    let sourceAnswer: String
    let parameters: [Int]
    let prompt: String
    let instructions: String
    let interaction: NFExerciseInteraction
    let representations: [NFExerciseRepresentation]
    let figure: Figure?
    let explanation: String
    let correctiveAction: String

    var isSupported: Bool {
        policyVersion == 1 && self == NFRetrievalAssetCatalog.asset(targetID: targetID, form: form, locale: localeIdentifier)
    }
    static func make(exercise: NFExercise) -> Self? {
        guard !exercise.assessmentProtected, exercise.lab == .retrieval, exercise.evidenceClass == exercise.purpose.evidenceClass,
              [.practice, .documentPractice].contains(exercise.purpose),
              exercise.availabilityReason == nil, exercise.schemaVersion == 7, exercise.generatorVersion == 10,
              exercise.provenance.generatorID == "nf.exercise.fallback", exercise.provenance.generatorVersion == 10,
              exercise.contractMetadata?.generatorVersion == 10,
              exercise.contractMetadata?.retrievalAuthorityPolicyVersion == 1,
              let asset = exercise.contractMetadata?.retrievalAsset, asset.isSupported,
              asset.localeIdentifier == exercise.localeIdentifier,
              exercise.tags.contains("knowledge-target." + asset.targetID),
              exercise.templateID.hasSuffix(".v4." + asset.form.templateSlug),
              exercise.prompt == asset.prompt, exercise.instructions == asset.instructions,
              exercise.interaction == asset.interaction, exercise.representations == asset.representations,
              exercise.independentRepresentations == asset.representations else { return nil }
        return asset
    }
}

/// An explicit finite asset registry. Parameters come from declared canonical
/// recipes, never from parsing a question's prose or guessing a diagram key.
enum NFRetrievalAssetCatalog {
    private struct Recipe: Sendable {
        enum Kind: Equatable, Sendable { case concept, mean, slope, rectangle }
        let kind: Kind
        let target: NFRetrievalKnowledgeTarget
        let values: [Int]
        let english: String?
        let japanese: String?
        let japaneseAnswers: [String]
    }
    private static let recipes: [String: Recipe] = {
        let bySuffix = Dictionary(grouping: NFBundledRetrievalCatalog.targets, by: { $0.id.components(separatedBy: ".").last ?? $0.id })
            .compactMapValues { $0.count == 1 ? $0.first : nil }
        var result: [String: Recipe] = [:]
        func add(_ suffix: String, kind: Recipe.Kind, values: [Int] = [], en: String? = nil, ja: String? = nil, answers: [String] = []) {
            guard let target = bySuffix[suffix] else { return }
            result[target.id] = .init(kind: kind, target: target, values: values, english: en, japanese: ja, japaneseAnswers: answers)
        }
        add("si-time-unit", kind: .concept, en: "In the SI system, the base unit used to measure time is ____. Name the unit.", ja: "SIでは、時間を測る基本単位は ____ です。単位名を答えてください。", answers: ["秒", "秒（s）"])
        add("additive-identity", kind: .concept, en: "Adding ____ to any real number leaves that number unchanged. Fill the blank.", ja: "どの実数にも ____ を足しても、その値は変わりません。空欄を埋めてください。", answers: ["0", "ゼロ", "零"])
        add("force-si-unit", kind: .concept, en: "In the SI system, force is measured in ____. Name this derived unit.", ja: "SIでは、力の単位は ____ です。この組立単位の名前を答えてください。", answers: ["ニュートン", "N"])
        add("byte-size", kind: .concept, en: "One byte contains ____ bits. Fill in the count.", ja: "1バイトは ____ ビットです。個数を入れてください。", answers: ["8", "八", "8ビット"])
        add("static-force-equilibrium", kind: .concept, en: "For a body in static equilibrium, the vector sum of all external forces is ____. Fill the blank.", ja: "物体が静力学的なつり合いにあるとき、外力のベクトル和は ____ です。空欄を埋めてください。", answers: ["0", "ゼロ", "零", "ゼロベクトル"])
        add("enzyme-active-site", kind: .concept, en: "The region of an enzyme that binds the substrate and supports catalysis is called ____. Name the region.", ja: "酵素の基質が結合し、触媒作用に関わる領域を ____ と呼びます。領域名を答えてください。", answers: ["活性部位", "活性中心"])
        add("cation-charge", kind: .concept, en: "A cation has a net ____ electric charge. Fill in the sign.", ja: "陽イオンは全体として ____ の電荷を持ちます。符号を答えてください。", answers: ["正", "正の電荷", "プラス", "+"])
        add("feature-definition", kind: .concept, en: "In predictive modeling, a feature is ____. Describe its role in one short phrase.", ja: "予測モデルにおける特徴量とは ____ です。その役割を短く答えてください。", answers: ["予測に使う入力変数", "モデルの入力変数", "予測のための入力変数"])
        for step in 0..<10 {
            let first = step + 4
            add("three-value-mean-\(first)", kind: .mean, values: [first, first + 4, first + 8])
            let x1 = step, y1 = 2 * step + 1, x2 = step + 4, y2 = y1 + 4 * (step + 2)
            add("slope-\(x1)-\(y1)-\(x2)-\(y2)", kind: .slope, values: [x1, y1, x2, y2])
            add("rectangle-area-\(step + 3)-\(step + 2)", kind: .rectangle, values: [step + 3, step + 2])
        }
        return result
    }()
    static func compatibleRenderings(targetID: String) -> [NFRetrievalAssetContract.Form] {
        guard let recipe = recipes[targetID] else { return [] }
        return recipe.kind == .concept ? [.cloze] : [.cloze, .equation, .figure]
    }
    static func targets(form: NFRetrievalAssetContract.Form) -> [NFRetrievalKnowledgeTarget] {
        recipes.values.filter { form == .cloze || $0.kind != .concept }.map(\.target).sorted { $0.id < $1.id }
    }
    static func asset(targetID: String, form: NFRetrievalAssetContract.Form, locale: String) -> NFRetrievalAssetContract? {
        guard let recipe = recipes[targetID], form == .cloze || recipe.kind != .concept,
              locale.hasPrefix("en") || locale.hasPrefix("ja") else { return nil }
        let ja = locale.hasPrefix("ja"), target = recipe.target, p = recipe.values
        func text(_ en: String, _ jp: String) -> String { ja ? jp : en }
        var figure: NFRetrievalAssetContract.Figure?
        let prompt: String, instruction: String, explanation: String, corrective: String
        let interaction: NFExerciseInteraction
        var representations: [NFExerciseRepresentation] = []
        if recipe.kind == .concept {
            guard let en = recipe.english, let jp = recipe.japanese else { return nil }
            prompt = text(en, jp)
            instruction = text("Complete the omitted relationship before viewing the answer.", "答えを見る前に、欠けている関係を完成させてください。")
            let answers = target.allAcceptedAnswers + recipe.japaneseAnswers
            interaction = .shortText(.init(expectedAnswer: ja ? (recipe.japaneseAnswers.first ?? target.answer) : target.answer,
                scoringRule: .normalizedExact(acceptedAnswers: answers), maximumCharacters: 280,
                authority: .reviewedProse(acceptedAnswers: answers, rejectedAssertions: [])))
            explanation = text(target.explanation, "完成した文を読み、空欄の語と前後の関係を確認してください。")
            corrective = text("Read the completed statement, then cover it and retrieve the missing relationship again.", "完成した文を読んだら隠し、欠けていた関係をもう一度思い出してください。")
        } else {
            let answer: Int, unit: String?, equation: String, equationSpoken: String, cloze: String, figureQuestion: String
            switch recipe.kind {
            case .mean:
                answer = (p[0] + p[1] + p[2]) / 3; unit = nil
                let points = p.enumerated().map { NFRetrievalAssetContract.Figure.Point(id: $0.offset, label: String($0.offset + 1), x: $0.offset + 1, y: $0.element) }
                figure = .init(kind: .observations, points: points, labelTitle: text("Observation", "観測"), xTitle: text("Observation", "観測"), yTitle: text("Value (unitless)", "値（無次元）"), summary: text("Three equally weighted observations. Bar height gives each observation's value.", "重みが等しい3つの観測です。棒の高さは各観測の値を示します。"))
                equation = "\\bar{x} = \\frac{\(p[0])+\(p[1])+\(p[2])}{3} = \\square"
                equationSpoken = text("The mean equals (\(p[0]) plus \(p[1]) plus \(p[2])) divided by 3. All observations are unitless. The result is blank.", "平均は、\(p[0])、\(p[1])、\(p[2]) の合計を3で割った値です。観測値はすべて無次元です。結果は空欄です。")
                cloze = text("For observations \(p[0]), \(p[1]), and \(p[2]), the arithmetic mean is ____. Fill in the value.", "観測値 \(p[0])、\(p[1])、\(p[2]) の算術平均は ____ です。値を入れてください。")
                figureQuestion = text("What is the arithmetic mean of the three observations in the chart?", "グラフの3つの観測値の算術平均はいくつですか？")
                explanation = text("Add all three observations and divide the total by 3: the mean is \(answer).", "3つの観測値をすべて足し、合計を3で割ります。平均は \(answer) です。")
                corrective = text("Check that every observation contributes once to the total.", "合計にすべての観測値を1回ずつ含めたか確認してください。")
            case .slope:
                guard p[2] > p[0] else { return nil }
                answer = (p[3] - p[1]) / (p[2] - p[0]); unit = nil
                figure = .init(kind: .line, points: [.init(id: 0, label: "P", x: p[0], y: p[1]), .init(id: 1, label: "Q", x: p[2], y: p[3])], labelTitle: text("Point", "点"), xTitle: text("x (unitless)", "x（無次元）"), yTitle: text("y (unitless)", "y（無次元）"), summary: text("A straight line joins P and Q on linear coordinate axes.", "線形目盛りの座標軸上で、点Pと点Qを直線で結んでいます。"))
                equation = "m = \\frac{\(p[3])-\(p[1])}{\(p[2])-\(p[0])} = \\square"
                equationSpoken = text("Slope equals (\(p[3]) minus \(p[1])) divided by (\(p[2]) minus \(p[0])). Both coordinate axes are unitless. The result is blank.", "傾きは、\(p[3]) から \(p[1]) を引いた値を、\(p[2]) から \(p[0]) を引いた値で割った値です。両方の座標軸は無次元です。結果は空欄です。")
                cloze = text("On the straight line through (\(p[0]), \(p[1])) and (\(p[2]), \(p[3])), each increase of 1 in x gives an increase of ____ in y.", "点 (\(p[0]), \(p[1])) と (\(p[2]), \(p[3])) を通る直線では、xが1増えるとyは ____ 増えます。")
                figureQuestion = text("What is the slope of the straight line from P to Q?", "点Pから点Qへの直線の傾きはいくつですか？")
                explanation = text("Divide the vertical change by the nonzero horizontal change to obtain \(answer).", "縦の変化量を、0でない横の変化量で割ると \(answer) になります。")
                corrective = text("Use the same point order in both coordinate differences.", "2つの座標の差では、点の順番をそろえてください。")
            case .rectangle:
                answer = p[0] * p[1]; unit = "m^2"
                figure = .init(kind: .rectangle, points: [.init(id: 0, label: "A", x: 0, y: 0), .init(id: 1, label: "B", x: p[0], y: 0), .init(id: 2, label: "C", x: p[0], y: p[1]), .init(id: 3, label: "D", x: 0, y: p[1])], labelTitle: text("Vertex", "頂点"), xTitle: "x (m)", yTitle: "y (m)", summary: text("The rectangle's vertices are A, B, C and D. Both coordinate axes are measured in metres.", "長方形の頂点はA、B、C、Dです。両方の座標軸の単位はメートルです。"))
                equation = "A = \(p[0])\\,\\mathrm{m} \\times \(p[1])\\,\\mathrm{m} = \\square\\,\\mathrm{m}^{2}"
                equationSpoken = text("Area equals \(p[0]) metres times \(p[1]) metres. The result in square metres is blank.", "面積は \(p[0]) メートルと \(p[1]) メートルの積です。平方メートルで表す結果は空欄です。")
                cloze = text("A rectangle \(p[0]) metres long and \(p[1]) metres wide has area ____ square metres.", "長さ\(p[0])メートル、幅\(p[1])メートルの長方形の面積は ____ 平方メートルです。")
                figureQuestion = text("What is the area of the rectangle in square metres?", "図の長方形の面積は何平方メートルですか？")
                explanation = text("Multiply the two perpendicular side lengths: \(p[0]) × \(p[1]) = \(answer) square metres.", "直交する2辺の長さを掛けます。\(p[0]) × \(p[1]) = \(answer) 平方メートルです。")
                corrective = text("Read each side length from its coordinate difference before multiplying.", "掛ける前に、それぞれの辺の長さを座標の差から読み取ってください。")
            case .concept: return nil
            }
            let expected = recipe.kind == .rectangle ? "\(answer) square metres" : String(answer)
            guard target.answer == expected else { return nil }
            interaction = .numeric(.init(answer: .init(authoritativeValue: try! NFExactNumber(numerator: Int64(answer)),
                authoritativeTolerance: .absolute(try! NFExactNumber(numerator: 0)), legacyTolerance: .absolute(0),
                canonicalUnit: unit, unitRequired: false), placeholder: text("Missing value", "空欄の値"),
                permitsScientificNotation: true, permitsThousandsSeparators: false))
            switch form {
            case .cloze: prompt = cloze; figure = nil
            case .equation:
                prompt = text("Complete the missing value in the equation.", "式の空欄に入る値を求めてください。")
                representations = [.equation(latex: equation, spokenDescription: equationSpoken)]; figure = nil
            case .figure:
                prompt = figureQuestion
                guard let data = figure else { return nil }; representations = [data.table]
            }
            instruction = unit == nil ? text("Enter the missing numerical value.", "求める数値を入力してください。")
                : text("Enter the numerical area. The response unit is square metres.", "面積の数値を入力してください。回答の単位は平方メートルです。")
        }
        return .init(targetID: target.id, form: form, localeIdentifier: locale, sourcePrompt: target.prompt,
            sourceAnswer: target.answer, parameters: p, prompt: prompt, instructions: instruction,
            interaction: interaction, representations: representations, figure: figure,
            explanation: explanation, correctiveAction: corrective)
    }
}

extension NFExercise {
    /// Generator numbers belong to their producer. Authored authority version
    /// 10 is distinct from fallback retrieval reconstruction version 10.
    var requiresRetrievalAssetContract: Bool {
        contractMetadata?.retrievalAsset != nil || schemaVersion == 7
            || (generatorVersion == 10 && provenance.generatorID == "nf.exercise.fallback")
    }
    var hasSupportedRetrievalAsset: Bool {
        !requiresRetrievalAssetContract || NFRetrievalAssetContract.make(exercise: self) != nil
    }
}


/// Frozen authored geometry and query for ordinary practice. A supported
/// exercise must match the complete contract, including every valid option.
struct NFSpatialStructureContract: Codable, Equatable, Sendable {
    typealias Geometry = NFSpatialStructureGeometry
    var policyVersion: Int = 1
    let structure: Geometry.Structure
    let localeIdentifier: String
    var isSupported: Bool {
        policyVersion == 1 && (localeIdentifier.hasPrefix("en") || localeIdentifier.hasPrefix("ja"))
            && structure.isBounded && Geometry.structures.contains(structure)
    }
    var familyVariant: Int { structure.variant }
    var familyID: String { familyVariant == 1 ? "nf.default.spatial.object-rotation" : "nf.default.spatial.top-view" }
    var templateSlug: String {
        switch structure { case .faces: "rotation.labeled-faces"; case .top: "orthographic.occupied-footprint"; case .views: "orthographic.two-view-constraints" }
    }
    func text(_ en: String, _ ja: String) -> String { localeIdentifier.hasPrefix("ja") ? ja : en }
    var sourceDescription: String {
        switch structure {
        case .faces:
            return text("A cube is centered at the origin. Face A points along +x, B along −x, C along +y, D along −y, E along +z, and F along −z. Face labels remain attached to the cube.",
                "原点を中心とする立方体で、面Aは+x、Bは−x、Cは+y、Dは−y、Eは+z、Fは−zを向いています。面のラベルは立方体に固定されています。")
        case .top:
            return text("The object consists of connected unit cubes at the listed occupied cells. Each cell (x, y, z) fills the unit box beginning at that coordinate. The z-axis points up; all columns are supported from z = 0.",
                "この物体は、一覧の占有セルに置かれた連結した単位立方体でできています。セル (x, y, z) は、その座標から始まる単位の箱です。z軸は上向きで、すべての柱はz = 0から積まれています。")
        case .views:
            return text("Every proposed assembly occupies all four ground cells of a 2 by 2 base, with one to three unit cubes in each column and no gaps. The front view shows x versus z; the side view shows y versus z. A silhouette records whether each projected cell is occupied, not how many cubes lie behind it.",
                "すべての候補は2×2の底面の4セルを占め、各柱に1〜3個の単位立方体が隙間なく積まれています。正面図はxとz、側面図はyとzを示します。輪郭は投影された各セルが占有されるかを表し、その奥にある立方体の個数は表しません。")
        }
    }
    func rotationDescription(_ rotation: Geometry.Rotation) -> String {
        let axis = rotation.axis.rawValue, degrees = rotation.quarterTurns * 90
        return text("Rotate the object +\(degrees)° about the fixed +\(axis) axis, counterclockwise viewed from +\(axis) toward the origin.",
            "物体を固定された+\(axis)軸の周りに+\(degrees)°回します。+\(axis)から原点を見ると反時計回りです。")
    }
    var prompt: String {
        switch structure {
        case let .faces(value):
            let moves = value.rotations.enumerated().map { "\($0.offset+1). " + rotationDescription($0.element) }.joined(separator: "\n")
            return moves + "\n" + text("After these rotations in order, which face points along \(value.query.symbol)?", "この順番で回した後、\(value.query.symbol)を向く面はどれですか？")
        case .top: return text("Which proposed footprint is the object's top orthographic view, looking down the −z direction? Use x to the right and y upward on the footprint.", "−z方向を見下ろした上面図に一致する輪郭はどれですか？輪郭では右がx、上がyです。")
        case .views: return text("Select every proposed assembly that matches both supplied views. More than one proposal may be valid; judge all four.", "示された2つの図の両方に一致する候補をすべて選んでください。複数の候補が正しい場合があります。4つすべてを判断してください。")
        }
    }
    var instructions: String {
        switch structure {
        case .faces: text("Choose one face. Camera views show the original cube; a worked rotation copy opens after your answer is saved. Rotation axes remain fixed in the original coordinate system.", "面を1つ選んでください。カメラで見えるのは元の立方体です。回答を保存した後に回転の解説用コピーが開きます。回転軸は元の座標系に固定されています。")
        case .top: text("Choose one footprint. The independent object view is fixed; projected views open after saving your answer.", "輪郭を1つ選んでください。回答前の物体の視点は固定されています。回答を保存すると投影図が開きます。")
        case .views: text("Choose all matching proposals, not just the first match. Front and side directions and axis labels are part of the givens.", "最初に見つかった1つだけでなく、一致する候補をすべて選んでください。正面と側面の向き、および軸のラベルも条件に含まれます。")
        }
    }
    var interaction: NFExerciseInteraction {
        switch structure {
        case let .faces(value):
            let options = Geometry.FaceRotation.labels.map { label in
                NFChoiceOption(id:label,text:text("Face \(label)","面\(label)"),accessibilityLabel:nil,
                    distractorCode:label == value.correctFace ? nil : "face_destination_"+label)
            }
            return .singleChoice(.init(options:options,correctOptionID:value.correctFace ?? "unavailable"))
        case let .top(value):
            let options = value.choices.indices.map { index in
                NFChoiceOption(id:Self.choiceID(index),text:text("Footprint \(Self.choiceID(index))","輪郭\(Self.choiceID(index))"),accessibilityLabel:nil,
                    distractorCode:value.correctIndices.contains(index) ? nil : "footprint_mismatch_"+Self.choiceID(index))
            }
            return .singleChoice(.init(options:options,correctOptionID:Self.choiceID(value.correctIndices.first ?? -1)))
        case let .views(value):
            let options = value.candidates.indices.map { index in
                NFChoiceOption(id:Self.choiceID(index),text:text("Assembly \(Self.choiceID(index))","積み方\(Self.choiceID(index))"),accessibilityLabel:nil,
                    distractorCode:value.correctIndices.contains(index) ? nil : "view_mismatch_"+Self.choiceID(index))
            }
            return .multipleChoice(.init(options:options,correctOptionIDs:value.correctIndices.map(Self.choiceID),minimumSelections:1,maximumSelections:4))
        }
    }
    static func choiceID(_ index: Int) -> String { (0..<4).contains(index) ? ["A","B","C","D"][index] : "unavailable" }
    var explanation: String {
        switch structure {
        case let .faces(v): return Geometry.FaceRotation.labels.map { label in
            text("Face \(label) ends along \(v.finalDirection(face:label)?.symbol ?? "?").", "面\(label)は最後に\(v.finalDirection(face:label)?.symbol ?? "?")を向きます。")
        }.joined(separator:" ")
        case let .top(v): return text("Projecting along z keeps each distinct (x, y) position once. The matching footprint is \(Self.choiceID(v.correctIndices.first ?? -1)). Different heights above the same ground cell do not add a second footprint cell.", "z方向に投影すると、異なる (x, y) の位置が1回ずつ残ります。一致する輪郭は\(Self.choiceID(v.correctIndices.first ?? -1))です。同じ底面セルに高さが違う立方体があっても、輪郭のセルは増えません。")
        case let .views(v): return text("The valid proposals are \(v.correctIndices.map(Self.choiceID).joined(separator:", ")). For each x column, take the maximum height across y; for each y column, take the maximum height across x. More than one arrangement can satisfy these same silhouettes.", "正しい候補は\(v.correctIndices.map(Self.choiceID).joined(separator:"、"))です。各x列ではy方向の最大高さを取り、各y列ではx方向の最大高さを取ります。同じ2つの輪郭を満たす積み方が複数ある場合があります。")
        }
    }
    var hint: String {
        switch structure {
        case .faces: text("Track a face's outward normal through each fixed-axis turn. A face on the rotation axis stays on that axis.", "面の外向きの法線を、固定軸の回転ごとに追ってください。回転軸上の面はその軸上に残ります。")
        case .top: text("Consider which coordinate disappears when looking along z. Preserve the labeled x and y directions.", "z方向から見ると、どの座標が消えるかを考えてください。xとyの向きはラベルの通りに保ちます。")
        case .views: text("Test each proposal against both silhouettes. A match to only one view is insufficient.", "各候補を両方の輪郭と照合してください。片方だけの一致では不十分です。")
        }
    }
    var errorExplanations: [String:String] {
        switch structure {
        case let .faces(v): return Dictionary(uniqueKeysWithValues: Geometry.FaceRotation.labels.filter { $0 != v.correctFace }.map { label in
            ("face_destination_"+label,text("This face ends along \(v.finalDirection(face:label)?.symbol ?? "?"), rather than the requested \(v.query.symbol).", "この面の最終的な向きは\(v.finalDirection(face:label)?.symbol ?? "?")で、問われている\(v.query.symbol)ではありません。"))
        })
        case let .top(v): return Dictionary(uniqueKeysWithValues: v.choices.indices.filter { !v.correctIndices.contains($0) }.map { index in
            ("footprint_mismatch_"+Self.choiceID(index),text("This proposal changes an occupied ground position. Project the actual cells without reflecting, filling a gap, or counting heights as new positions.", "この候補は底面の占有位置を変えています。反転させたり隙間を埋めたり、高さを別の位置として数えたりせず、実際のセルを投影してください。"))
        })
        case let .views(v): return Dictionary(uniqueKeysWithValues: v.candidates.indices.filter { !v.correctIndices.contains($0) }.map { index in
            let front = Geometry.heights(v.candidates[index],axis:.x).map(String.init).joined(separator:", ")
            let side = Geometry.heights(v.candidates[index],axis:.y).map(String.init).joined(separator:", ")
            return ("view_mismatch_"+Self.choiceID(index),text("This proposal has front heights [\(front)] and side heights [\(side)]; compare both with the supplied views.", "この候補の正面の高さは[\(front)]、側面の高さは[\(side)]です。示された2つの図と比較してください。"))
        })
        }
    }
    var representation: NFSpatialRepresentationMetadata {
        .init(stimulusCategory:"structured-"+templateSlug,dimension:.threeDimensional,
            objectDescription:sourceDescription,viewpoint:text("Original labeled coordinate system","元のラベル付き座標系"),
            operations:[familyVariant == 1 ? .rotate : .project],points:[],axisLabels:["x","y","z"],
            accessibilityDescription:sourceDescription,assetName:nil,protectedGrammarID:nil,
            difficultyParameters:.init(stimulusCategory:"structured-"+templateSlug,viewpoint:text("Original labeled coordinate system","元のラベル付き座標系"),
                rotationMagnitudeDegrees:0,objectComplexity:0.6,distractorSimilarity:0.7,responseMode:familyVariant == 1 ? .singleChoice : .diagramMatch))
    }
    static func make(exercise: NFExercise) -> Self? {
        guard !exercise.assessmentProtected, exercise.lab == .spatial,
              [.practice,.documentPractice].contains(exercise.purpose),exercise.evidenceClass == exercise.purpose.evidenceClass,
              exercise.schemaVersion == 8,exercise.generatorVersion == 11,exercise.availabilityReason == nil,
              exercise.provenance.generatorID == "nf.exercise.fallback",exercise.provenance.generatorVersion == 11,
              exercise.provenance.contentTier == .deterministicGenerated,!exercise.provenance.isSourceGrounded,
              exercise.provenance.sourceDocumentIDs.isEmpty,exercise.provenance.sourceChunkIDs.isEmpty,
              exercise.sourceContext.sourceDocumentIDs.isEmpty,exercise.sourceContext.sourceChunkIDs.isEmpty,
              exercise.sourceContext.groundingFacts.isEmpty,exercise.citations.isEmpty,exercise.contextText == nil,
              exercise.contractMetadata?.generatorVersion == 11,
              let contract = exercise.contractMetadata?.spatialStructure,contract.isSupported,
              contract.localeIdentifier == exercise.localeIdentifier,
              exercise.templateID.hasSuffix(".v4."+contract.templateSlug),
              exercise.contractMetadata?.familyID == contract.familyID,
              exercise.contractMetadata?.structureID == contract.structure.identity,
              exercise.contractMetadata?.semanticFingerprint == NFQuestionFingerprint.spatialStructureFingerprint(identity:contract.structure.identity),
              exercise.prompt == contract.prompt,exercise.instructions == contract.instructions,
              exercise.accessibility.promptAccessibilityLabel == contract.prompt,
              exercise.accessibility.visualAlternative == contract.sourceDescription,
              exercise.feedback.correctExplanation == contract.explanation,exercise.feedback.retryExplanation == contract.hint,
              exercise.feedback.decisiveStep == contract.explanation,exercise.feedback.hintLadder == [contract.hint],
              exercise.feedback.errorExplanations == contract.errorExplanations,
              exercise.skillWeights == ["skill.spatial":0.8,"skill.quantitative":0.2],
              exercise.interaction == contract.interaction,
              exercise.representations == [.spatial(contract.representation)],
              exercise.independentRepresentations == exercise.representations else { return nil }
        return contract
    }
}

extension NFExercise {
    var hasSupportedSpatialStructure: Bool {
        contractMetadata?.spatialStructure == nil ? (schemaVersion != 8 && !(generatorVersion == 11 && provenance.generatorID == "nf.exercise.fallback"))
            : NFSpatialStructureContract.make(exercise:self) != nil
    }
}


/// Optional new recipe. The saved geometry is the authority; neither prompt
/// parsing nor the sign of a coordinate can choose or reinterpret its key.
struct NFCoordinateTransformContract: Codable, Equatable, Sendable {
    typealias Geometry = NFCoordinateTransformGeometry
    var policyVersion = 1
    let task: Geometry.Task
    let localeIdentifier: String
    var isSupported: Bool {
        policyVersion == 1 && (localeIdentifier.hasPrefix("en") || localeIdentifier.hasPrefix("ja"))
            && task.isBounded && Geometry.tasks.contains(task)
    }
    var familyVariant: Int { task.kind.variant }
    var familyID: String { familyVariant == 0 ? "nf.default.spatial.coordinate-rotation" : "nf.default.spatial.vector-reflection" }
    var templateSlug: String { familyVariant == 0 ? "coordinate.ordered-rotation" : "coordinate.ordered-reflection" }
    func text(_ en: String,_ ja: String) -> String { localeIdentifier.hasPrefix("ja") ? ja : en }
    func coordinate(_ p: Geometry.Point) -> String { "(\(p.x), \(p.y))" }
    func operationDescription(_ operation: Geometry.Operation) -> String {
        switch operation {
        case let .rotate(center,turns):
            let angle=abs(turns)*90
            return text("Rotate actively \(angle)° \(turns > 0 ? "counterclockwise" : "clockwise") about C = \(coordinate(center)), looking at the x-right, y-up plane.",
                "右がx、上がyの平面を見て、C = \(coordinate(center))の周りに点を\(turns > 0 ? "反時計回り" : "時計回り")に\(angle)°回します。")
        case let .translate(vector): return text("Translate by the vector \(coordinate(vector)): add its x and y components to the current point.", "ベクトル\(coordinate(vector))だけ平行移動します。現在の点に各x、y成分を加えます。")
        case let .reflect(line,offset): return text("Reflect the current point across the line \(lineDescription(line,offset:offset)).", "現在の点を直線\(lineDescription(line,offset:offset))に関して対称移動します。")
        }
    }
    func lineDescription(_ line: Geometry.Mirror,offset: Int) -> String {
        switch line { case .vertical: "x = \(offset)";case .horizontal: "y = \(offset)";case .risingDiagonal: "y = x";case .fallingDiagonal: "y = −x" }
    }
    var sourceDescription: String {
        text("Point P starts at \(coordinate(task.point)). Coordinates are measured in grid units. The x-axis points right and the y-axis points up; the axes stay fixed throughout. Lines and centers remain in this original coordinate system.",
            "点Pの初期座標は\(coordinate(task.point))です。座標の単位は格子単位です。x軸は右、y軸は上を向き、操作の間も固定されます。直線と中心は元の座標系で指定されています。")
    }
    var prompt: String {
        sourceDescription+"\n"+task.operations.enumerated().map { "\($0.offset+1). "+operationDescription($0.element) }.joined(separator:"\n")
            + "\n" + text("Enter the final x and y coordinates of P after these operations in the stated order.","指定された順番で操作した後の、点Pの最終的なx座標とy座標を入力してください。")
    }
    var instructions: String {
        text("Each exact coordinate earns half of the credit; full correctness requires both x and y in grid units. Fractions and equivalent exact numeric notation are accepted. The original diagram does not move while you answer. A separate worked copy opens after saving; no orientation classification is scored.",
            "各座標が正確なら半分ずつ得点し、完全な正解には格子単位でxとyの両方が必要です。分数など、等価な正確な数値表記も使用できます。回答中は元の図は動きません。保存後に解説用コピーが開きます。向きを保つかどうかの分類は採点しません。")
    }
    var rubric: NFExerciseRubric {
        .init(criteria:[
            .init(id:"x",description:text("Exact x coordinate in grid units","格子単位による正確なx座標"),weight:0.5),
            .init(id:"y",description:text("Exact y coordinate in grid units","格子単位による正確なy座標"),weight:0.5)],
            fullCreditThreshold:1,permitsPartialCredit:true)
    }
    var interaction: NFExerciseInteraction {
        let result=task.answer ?? .init(x:0,y:0)
        return .logicState(.init(initialState:["x":String(task.point.x),"y":String(task.point.y)],
            expectedFinalState:["x":String(result.x),"y":String(result.y)],acceptedEquivalentStates:[],
            ruleOptions:[],expectedViolatedRuleID:nil,fieldDomains:["x":.exactNumber,"y":.exactNumber]))
    }
    var hint: String {
        text("Keep the operation order and fixed axes. A rotation uses the displacement from its named center; a reflected point lies the same perpendicular distance on the other side of the named line. Check each intermediate coordinate.",
            "操作の順番と固定軸を保ってください。回転では指定された中心からの変位を使います。対称移動した点は、指定された直線の反対側に同じ垂直距離だけ離れています。途中の座標も確認してください。")
    }
    var explanation: String {
        let route=task.steps.enumerated().map { text($0.offset == 0 ? "Original P: " : "After operation \($0.offset): ",$0.offset == 0 ? "元のP：" : "操作\($0.offset)の後：")+coordinate($0.element) }.joined(separator:"; ")
        let orientation=(task.affine?.determinant ?? 1) == 1
        return route+". "+text(orientation ? "The complete transformation preserves the orientation of a labeled triangle." : "The complete transformation reverses the orientation of a labeled triangle.",orientation ? "全体の変換はラベル付き三角形の向きを保ちます。" : "全体の変換はラベル付き三角形の向きを反転させます。")
            + " " + text("This orientation explanation does not add another scored response.","この向きの説明によって、採点対象の回答が追加されることはありません。")
    }
    var referenceTriangle: [Geometry.Point] { [task.point,.init(x:task.point.x+1,y:task.point.y),.init(x:task.point.x,y:task.point.y+1)] }
    var representation: NFSpatialRepresentationMetadata {
        .init(stimulusCategory:"coordinate-contract-"+templateSlug,dimension:.twoDimensional,
            objectDescription:sourceDescription,viewpoint:text("Fixed x-right, y-up coordinate plane","右がx、上がyの固定座標平面"),
            operations:[.coordinateTransform],points:[.init(label:"P",x:Double(task.point.x),y:Double(task.point.y),z:nil)],
            axisLabels:[text("x (grid units)","x（格子単位）"),text("y (grid units)","y（格子単位）")],
            accessibilityDescription:sourceDescription,assetName:nil,protectedGrammarID:nil,
            difficultyParameters:.init(stimulusCategory:"coordinate-contract-"+templateSlug,viewpoint:text("Fixed x-right, y-up coordinate plane","右がx、上がyの固定座標平面"),
                rotationMagnitudeDegrees:0,objectComplexity:0.3,distractorSimilarity:0,responseMode:.coordinateEntry))
    }
    static func make(exercise: NFExercise) -> Self? {
        guard !exercise.assessmentProtected,exercise.lab == .spatial,
              [.practice,.documentPractice].contains(exercise.purpose),exercise.evidenceClass == exercise.purpose.evidenceClass,
              exercise.schemaVersion == 9,exercise.generatorVersion == 12,exercise.availabilityReason == nil,
              exercise.provenance.generatorID == "nf.exercise.fallback",exercise.provenance.generatorVersion == 12,
              exercise.provenance.contentTier == .deterministicGenerated,!exercise.provenance.isSourceGrounded,
              exercise.provenance.sourceDocumentIDs.isEmpty,exercise.provenance.sourceChunkIDs.isEmpty,
              exercise.sourceContext.sourceDocumentIDs.isEmpty,exercise.sourceContext.sourceChunkIDs.isEmpty,
              exercise.sourceContext.groundingFacts.isEmpty,exercise.citations.isEmpty,exercise.contextText == nil,
              exercise.contractMetadata?.generatorVersion == 12,
              let value=exercise.contractMetadata?.coordinateTransform,value.isSupported,
              value.localeIdentifier == exercise.localeIdentifier,
              exercise.templateID.hasSuffix(".v4."+value.templateSlug),
              exercise.contractMetadata?.familyID == value.familyID,
              exercise.contractMetadata?.structureID == value.task.semanticIdentity,
              exercise.contractMetadata?.semanticFingerprint == NFQuestionFingerprint.coordinateTransformFingerprint(identity:value.task.semanticIdentity),
              exercise.prompt == value.prompt,exercise.instructions == value.instructions,
              exercise.accessibility.promptAccessibilityLabel == value.prompt,
              exercise.accessibility.visualAlternative == value.sourceDescription,
              exercise.feedback.correctExplanation == value.explanation,exercise.feedback.retryExplanation == value.hint,
              exercise.feedback.decisiveStep == value.explanation,exercise.feedback.hintLadder == [value.hint],
              exercise.feedback.errorExplanations == ["logic_state":value.hint],
              exercise.skillWeights == ["skill.spatial":0.8,"skill.quantitative":0.2],
              exercise.rubric == value.rubric,exercise.interaction == value.interaction,exercise.representations == [.spatial(value.representation)],
              exercise.independentRepresentations == exercise.representations else { return nil }
        return value
    }
}
extension NFExercise {
    var hasSupportedCoordinateTransform: Bool {
        contractMetadata?.coordinateTransform == nil ? (schemaVersion != 9 && !(generatorVersion == 12 && provenance.generatorID == "nf.exercise.fallback"))
            : NFCoordinateTransformContract.make(exercise:self) != nil
    }
}


/// Opt-in ordinary recipe. The solid and plane, not their prose or a rendered
/// mesh, determine the complete intersection and the requested deliverable.
struct NFSolidSectionContract:Codable,Equatable,Sendable {
    typealias G=NFSolidSectionGeometry
    var policyVersion=1
    let task:G.Task
    let localeIdentifier:String
    static let familyID="nf.default.spatial.cross-section"
    var isSupported:Bool { policyVersion == 1 && (localeIdentifier.hasPrefix("en") || localeIdentifier.hasPrefix("ja"))
        && task.isBounded && G.supportedTasks.contains(task) && task.shape != nil }
    var templateSlug:String { "cross-section.retained-"+task.solid.rawValue }
    func text(_ en:String,_ ja:String)->String { localeIdentifier.hasPrefix("ja") ? ja:en }
    func number(_ value:Double)->String {
        guard value.isFinite,abs(value)<1_000 else { return "?" }
        if value.rounded() == value { return String(Int(value)) }
        return String(format:"%.4g",locale:Locale(identifier:"en_US_POSIX"),value)
    }
    func point(_ p:G.Point)->String { "("+p.vector.map(number).joined(separator:", ")+")" }
    var planeEquation:String { "\(task.plane.a)x + \(task.plane.b)y + \(task.plane.c)z = "+number(task.plane.offset) }
    var sourceDescription:String {
        let solid:String
        switch task.solid {
        case .cube:solid=text("The closed cube is −2 ≤ x ≤ 2, −2 ≤ y ≤ 2, −2 ≤ z ≤ 2.","立体は −2 ≤ x ≤ 2、−2 ≤ y ≤ 2、−2 ≤ z ≤ 2 の閉じた立方体です。")
        case .sphere:solid=text("The closed solid ball is x² + y² + z² ≤ 9, centered at O = (0, 0, 0), with radius 3.","立体は x² + y² + z² ≤ 9 の閉じた球体です。中心は O = (0, 0, 0)、半径は3です。")
        case .cylinder:solid=text("The closed right circular cylinder is x² + y² ≤ 4 and −3 ≤ z ≤ 3. Its axis is z, radius 2 and height 6; both end disks are included.","立体は x² + y² ≤ 4、−3 ≤ z ≤ 3 の閉じた直円柱です。軸はz、半径は2、高さは6で、両端の円板も含みます。")
        }
        return solid+" "+text("All coordinates use grid units. The plane is ","座標の単位は格子単位です。平面の式は ")+planeEquation+"."
    }
    func shapeTitle(_ shape:G.Shape)->String {
        switch shape {
        case .empty:text("No intersection","交わらない")
        case .point:text("One contact point","接する点1個")
        case .segment:text("A line segment only","線分のみ")
        case .triangle:text("Triangle","三角形")
        case .square:text("Square","正方形")
        case .rectangle:text("Rectangle, not a square","正方形ではない長方形")
        case .rhombus:text("Rhombus, not a square","正方形ではないひし形")
        case .quadrilateral:text("Other quadrilateral","その他の四角形")
        case .pentagon:text("Pentagon","五角形")
        case .hexagon:text("Hexagon","六角形")
        case .circle:text("Circle","円")
        case .ellipse:text("Ellipse, not a circle","円ではない楕円")
        case .clippedEllipse:text("Clipped ellipse with a curved boundary and a straight edge","曲線と直線の辺を持つ、切り取られた楕円")
        }
    }
    var prompt:String {
        switch task.query {
        case .classify:return sourceDescription+"\n"+text("What intersection does this plane make with the solid? For a two-dimensional section, classify its boundary using the exclusive categories below.","この平面と立体はどのように交わりますか。二次元の断面については、以下の重複しない分類で境界の形を答えてください。")
        case .sphereRadiusSquared:return sourceDescription+"\n"+text("The plane makes a circular section. What is the square of that section's radius, in square grid units? Enter an exact number or fraction.","平面は円形の断面を作ります。その断面の半径の2乗を、格子単位の2乗で求めてください。正確な数値または分数を入力してください。")
        case let .verify(shape,q):return sourceDescription+"\n"+text("A proposed slice must satisfy both conditions: its nondegenerate section has the shape ","提案された切断は、次の両方の条件を満たす必要があります。退化していない断面の形が ")+shapeTitle(shape)+text("; and the cutting plane passes through Q = "," であり、切断平面が Q = ")+point(q)+text(". Does this exact plane satisfy every condition?"," を通ることです。この平面はすべての条件を満たしますか。")
        }
    }
    var instructions:String {
        switch task.query {
        case .sphereRadiusSquared:text("Only the squared radius is scored. Use exact notation; the given unit is square grid units. A worked section opens after the answer is saved.","採点するのは半径の2乗のみです。正確な表記を使ってください。単位は格子単位の2乗です。解説用の断面は回答の保存後に開きます。")
        default:text("Classify the filled intersection by its boundary. Empty, point and segment cases are distinct from two-dimensional regions. Here “ellipse” excludes circles; non-square rectangles and non-square rhombi are separate. Camera changes do not move the solid or plane. The computed section opens after saving.","交わった領域の境界を分類します。交わらない場合、点、線分は二次元の領域と区別します。ここでは「楕円」に円を含めず、正方形でない長方形とひし形も区別します。カメラを変えても立体や平面は動きません。計算された断面は保存後に開きます。")
        }
    }
    var choiceShapes:[G.Shape] {
        guard let correct=task.shape else { return [] }
        let pool:[G.Shape]
        switch task.solid {
        case .sphere:pool=[.empty,.point,.circle,.ellipse]
        case .cylinder:pool=[.empty,.point,.segment,.rectangle,.circle,.ellipse,.clippedEllipse]
        case .cube:pool=[.empty,.point,.segment,.triangle,.square,.rectangle,.rhombus,.quadrilateral,.pentagon,.hexagon]
        }
        let index=pool.firstIndex(of:correct) ?? 0
        var values=[correct]
        for offset in 1...pool.count where values.count<4 { values.append(pool[(index+offset)%pool.count]) }
        let shift=Int(NFStableDeterminism.hash64(task.identity)%UInt64(values.count))
        return Array(values[shift...])+Array(values[..<shift])
    }
    var rubric:NFExerciseRubric {
        .init(criteria:[.init(id:"section",description:text("The complete stated section response","指定された断面の完全な回答"),weight:1)],fullCreditThreshold:1,permitsPartialCredit:false)
    }
    var interaction:NFExerciseInteraction {
        switch task.query {
        case .sphereRadiusSquared:
            let value=task.radiusSquared ?? (try! NFExactNumber(numerator:0))
            return .numeric(.init(answer:.init(authoritativeValue:value,
                authoritativeTolerance:.absolute(try! NFExactNumber(numerator:0)),legacyTolerance:.absolute(0),
                canonicalUnit:nil,acceptedUnits:[],unitRequired:false,displayPrecision:4),placeholder:text("Squared radius","半径の2乗"),
                permitsScientificNotation:true,permitsThousandsSeparators:false))
        case .classify:
            return .singleChoice(.init(options:choiceShapes.map { shape in
                .init(id:shape.rawValue,text:shapeTitle(shape),accessibilityLabel:shapeTitle(shape),distractorCode:shape == task.shape ? nil:"section."+shape.rawValue)
            },correctOptionID:task.shape?.rawValue ?? "unavailable"))
        case .verify:
            let yes=text("All stated conditions hold","すべての条件を満たす"),no=text("At least one stated condition fails","少なくとも1つの条件を満たさない")
            return .singleChoice(.init(options:[.init(id:"yes",text:yes,accessibilityLabel:yes,distractorCode:task.verifiesClaim == true ? nil:"section.constraints"),
                .init(id:"no",text:no,accessibilityLabel:no,distractorCode:task.verifiesClaim == false ? nil:"section.constraints")],correctOptionID:task.verifiesClaim == true ? "yes":"no"))
        }
    }
    var hint:String { text("Check whether the plane meets the closed solid before naming a shape. For a cube, intersect its edges and count distinct vertices. For a sphere, use the perpendicular center-to-plane distance. For a finite cylinder, check the end caps as well as the curved side. Test every stated constraint.","形の名前を答える前に、平面が閉じた立体と交わるか確認します。立方体では辺との交点を求め、異なる頂点を数えます。球体では中心から平面への垂直距離を使います。有限の円柱では曲面だけでなく両端も確認します。指定された条件をすべて確かめてください。") }
    var explanation:String {
        guard let shape=task.shape else { return hint }
        var detail=text("The intersection is: ","交わり方は ")+shapeTitle(shape)+". "
        switch task.solid {
        case .cube:detail += text("Distinct edge/plane intersection vertices: ","辺と平面の異なる交点：")+(task.cubeVertices.isEmpty ? "∅":task.cubeVertices.map(point).joined(separator:"; "))+". "
        case .sphere:detail += text("The squared radius is 9 − (plane offset)² / |normal|² = ","半径の2乗は 9 −（平面の定数項）² / |法線|² = ")+(task.radiusSquared?.canonicalString ?? "?")+text(". A negative value means no intersection; zero means a contact point, not a circle."," です。負なら交わらず、0なら円ではなく接する点です。")
        case .cylinder:
            if task.plane.a == 0 { detail += text("The plane is horizontal at z = ","水平な平面の高さは z = ")+number(task.plane.offset)+text("; compare it with the included end caps z = −3 and z = 3."," です。含まれる両端 z = −3 と z = 3 の範囲と比べます。") }
            else if task.plane.c == 0 { detail += text("The plane fixes x = ","平面上では x = ")+number(task.plane.offset)+text(". The side-circle condition is x² + y² ≤ 4 and the height runs from −3 to 3."," です。底面の条件は x² + y² ≤ 4 で、高さは−3から3までです。") }
            else { detail += text("In the plane, z = ","平面上では z = ")+number(task.plane.offset)+text(" − x. Combining −3 ≤ z ≤ 3 with −2 ≤ x ≤ 2 gives "," − x です。−3 ≤ z ≤ 3 と −2 ≤ x ≤ 2 を合わせると ")+number(max(-2,task.plane.offset-3))+" ≤ x ≤ "+number(min(2,task.plane.offset+3))+text(". Only a full uncut circular parameter domain gives a complete ellipse; an end-cap cut adds a straight boundary."," です。円のパラメータ領域が完全に残る場合だけ全楕円になります。端面で切り取られると直線の境界が加わります。") }
        }
        if case let .verify(proposed,q)=task.query {
            detail += " "+text("Required shape: ","必要な形：")+shapeTitle(proposed)+text(". Substituting Q into the plane gives ","。Qを平面の式に代入した左辺は ")+number(task.plane.normal.dot(q))+text("; the required right-hand side is ","、右辺は ")+number(task.plane.offset)+". "+text(task.verifiesClaim == true ? "Every condition holds.":"At least one condition fails.",task.verifiesClaim == true ? "すべての条件を満たします。":"少なくとも1つの条件を満たしません。")
        }
        return detail
    }
    var exactAnswerSummary:String? {
        guard isNumeric,let radius=task.radiusSquared else { return nil }
        return radius.canonicalString+text(" square grid units"," 格子単位の2乗")
    }
    var errors:[String:String] {
        switch task.query {
        case .sphereRadiusSquared:return ["numeric_value":hint]
        case .verify:return ["section.constraints":hint]
        case .classify:return Dictionary(uniqueKeysWithValues:choiceShapes.filter{$0 != task.shape}.map{ ("section."+$0.rawValue,text("The selected category ","選んだ分類 ")+shapeTitle($0)+text(" does not match these plane/solid constraints. "," はこの平面と立体の条件に一致しません。")+explanation) })
        }
    }
    var isNumeric:Bool { if case .sphereRadiusSquared=task.query { return true };return false }
    var representation:NFSpatialRepresentationMetadata {
        let view=text("Fixed original solid and cutting plane","元の立体と切断平面を固定")
        return .init(stimulusCategory:"solid-section-"+task.solid.rawValue,dimension:.threeDimensional,
            objectDescription:sourceDescription,viewpoint:view,operations:[.crossSection],points:[],axisLabels:["x","y","z"],
            accessibilityDescription:sourceDescription,assetName:nil,protectedGrammarID:nil,
            difficultyParameters:.init(stimulusCategory:"solid-section-"+task.solid.rawValue,viewpoint:view,
                rotationMagnitudeDegrees:0,objectComplexity:0.5,distractorSimilarity:0.5,responseMode:isNumeric ? .numericEntry:.singleChoice))
    }
    static func make(exercise:NFExercise)->Self? {
        guard !exercise.assessmentProtected,exercise.lab == .spatial,
            [.practice,.documentPractice].contains(exercise.purpose),exercise.evidenceClass == exercise.purpose.evidenceClass,
            exercise.schemaVersion == 10,exercise.generatorVersion == 13,exercise.availabilityReason == nil,
            exercise.provenance.generatorID == "nf.exercise.fallback",exercise.provenance.generatorVersion == 13,
            exercise.provenance.contentTier == .deterministicGenerated,!exercise.provenance.isSourceGrounded,
            exercise.provenance.sourceDocumentIDs.isEmpty,exercise.provenance.sourceChunkIDs.isEmpty,
            exercise.sourceContext.sourceDocumentIDs.isEmpty,exercise.sourceContext.sourceChunkIDs.isEmpty,
            exercise.sourceContext.groundingFacts.isEmpty,exercise.citations.isEmpty,exercise.contextText == nil,
            let value=exercise.contractMetadata?.solidSection,value.isSupported,value.localeIdentifier == exercise.localeIdentifier,
            exercise.contractMetadata?.generatorVersion == 13,exercise.contractMetadata?.familyID == Self.familyID,
            exercise.templateID.hasSuffix(".v4."+value.templateSlug),exercise.contractMetadata?.structureID == value.task.identity,
            exercise.contractMetadata?.semanticFingerprint == NFQuestionFingerprint.solidSectionFingerprint(identity:value.task.identity),
            exercise.prompt == value.prompt,exercise.instructions == value.instructions,
            exercise.accessibility.promptAccessibilityLabel == value.prompt,exercise.accessibility.visualAlternative == value.sourceDescription,
            exercise.feedback.correctExplanation == value.explanation,exercise.feedback.retryExplanation == value.hint,
            exercise.feedback.decisiveStep == value.explanation,exercise.feedback.hintLadder == [value.hint],exercise.feedback.errorExplanations == value.errors,
            exercise.skillWeights == ["skill.spatial":0.85,"skill.quantitative":0.15],exercise.rubric == value.rubric,exercise.interaction == value.interaction,
            exercise.representations == [.spatial(value.representation)],exercise.independentRepresentations == exercise.representations else { return nil }
        return value
    }
}
extension NFExercise {
    var hasSupportedSolidSection:Bool {
        contractMetadata?.solidSection == nil ? (schemaVersion != 10 && !(generatorVersion == 13 && provenance.generatorID == "nf.exercise.fallback"))
            : NFSolidSectionContract.make(exercise:self) != nil
    }
}


struct NFNetFoldingContract:Codable,Equatable,Sendable {
    typealias G=NFNetFoldingGeometry
    var policyVersion=1
    let task:G.Task
    let localeIdentifier:String
    static let familyID="nf.default.spatial.cube-net"
    var isSupported:Bool { policyVersion == 1 && (localeIdentifier.hasPrefix("en") || localeIdentifier.hasPrefix("ja"))
        && task.bounded && G.tasks.contains(task) && !task.acceptedIDs.isEmpty }
    func text(_ en:String,_ ja:String)->String { localeIdentifier.hasPrefix("ja") ? ja:en }
    var isValidity:Bool { if case .validity=task.query{return true};return false }
    var sourceDescription:String {
        let positions=task.layout.cells.map{"\($0.label): (\($0.x), \($0.y))"}.joined(separator:"; ")
        let anchor=task.layout.cells.first?.label ?? "A"
        var s=text("Six unit squares on a grid: ","格子上の単位正方形6枚：")+positions+". "+text("Columns increase right and rows increase up. Each printed arrow points up the original page. Orange dashed lines mark hinges along full shared edges; no cutting, stretching or overlap is allowed.","列は右、行は上へ増えます。各面の矢印は元の紙面の上向きです。オレンジの破線は共有する辺全体の折り目を示し、切断、引き伸ばし、面の重なりは禁止です。")
        if !isValidity {
            s += " "+text("Hold face ","面 ")+anchor+text(" fixed at the origin: its outward normal is +z, its printed arrow is +y, and its right edge points +x. Fold the other faces away from the viewer, behind this face, to form the closed cube."," を原点に固定します。外向き法線は+z、印刷された矢印は+y、右方向は+xです。他の面をこの面の後ろ側に、見る人から遠ざける方向へ折り、閉じた立方体を作ります。")
        } else { s += " "+text("This is a proposed pattern, not an assertion that it is a valid cube net.","これは提案された配置であり、有効な立方体の展開図だとは限りません。") }
        if let leaf=task.givenFoldedLeaf {
            s += " "+text("In the given partial fold, leaf face ","与えられた途中の状態では、端の面 ")+leaf+text(" is already folded 90° at its only shared edge; all other hinges are flat. Complete the same fold while keeping the anchor fixed."," は唯一の共有辺で既に90°折られています。他の折り目は平らです。固定面を動かさず、この折り方を完成させてください。")
        }
        return s
    }
    func constraint(_ c:G.Constraint)->String { switch c {
    case let .opposite(a,b):return text("faces ","面 ")+a+text(" and "," と ")+b+text(" are opposite"," が向かい合う")
    case let .adjacent(a,b):return text("faces ","面 ")+a+text(" and "," と ")+b+text(" share a cube edge"," が立方体の辺を共有する")
    case let .direction(a,c,d):return text("face ","面 ")+a+(c == .normal ? text(" has outward normal "," の外向き法線は "):text(" has its printed arrow pointing "," の矢印の向きは "))+d.symbol }
    }
    var prompt:String {
        let q:String
        switch task.query {
        case .validity:q=text("Can this exact pattern fold into a closed cube under the stated rules?","この配置は、指定された規則で閉じた立方体に折れますか。")
        case let .opposite(a):q=text("Which face becomes opposite face ","面 ")+a+text("?"," と向かい合う面はどれですか。")
        case let .adjacent(a):q=text("Select every face sharing an edge with face ","面 ")+a+text(" on the completed cube. Select all four; touching at a corner alone is not adjacency."," と完成した立方体の辺を共有する面をすべて選んでください。4面すべてを選びます。頂点だけで接することは隣接に含めません。")
        case let .direction(a,c):q=text("After completing the fold, which fixed-axis direction describes ","折りを完成させると、固定座標軸で ")+a+(c == .normal ? text("'s outward normal?"," の外向き法線はどの方向ですか。"):text("'s printed arrow?"," の印刷された矢印はどの方向ですか。"))
        case let .constraints(a,b):q=text("A proposed completed fold must satisfy BOTH conditions: ","提案された完成形には、次の両方の条件が必要です：")+constraint(a)+"; "+constraint(b)+text(". Does the exact net satisfy both with the anchor fixed?","。固定面を動かさず、この展開図は両方を満たしますか。")
        }
        return sourceDescription+"\n"+q
    }
    var instructions:String { text("The original crease pattern and any stated partial fold are givens. Camera controls change only the view. Computed folding and face-direction explanations open after your answer is saved; all independent answers use the original fixed anchor and axes.","元の折り目と明記された途中の折り状態は与えられた条件です。カメラ操作で変わるのは視点だけです。計算された折り方と面の方向の解説は、回答の保存後に開きます。回答には元の固定面と座標軸を使ってください。") }
    var options:[NFChoiceOption] {
        switch task.query {
        case .validity,.constraints:return [.init(id:"yes",text:text("Yes — every stated rule holds","はい — すべての規則を満たす"),accessibilityLabel:text("Yes — every stated rule holds","はい — すべての規則を満たす"),distractorCode:nil),.init(id:"no",text:text("No — at least one rule fails","いいえ — 少なくとも1つの規則を満たさない"),accessibilityLabel:text("No — at least one rule fails","いいえ — 少なくとも1つの規則を満たさない"),distractorCode:nil)]
        case .direction:return G.Direction.allCases.map{.init(id:$0.rawValue,text:$0.symbol,accessibilityLabel:directionName($0),distractorCode:nil)}
        case let .opposite(a),let .adjacent(a):return task.layout.cells.filter{$0.label != a}.map{.init(id:$0.label,text:text("Face ","面 ")+$0.label,accessibilityLabel:text("Face ","面 ")+$0.label,distractorCode:nil)}
        }
    }
    func directionName(_ d:G.Direction)->String { text(["positiveX":"positive x","negativeX":"negative x","positiveY":"positive y","negativeY":"negative y","positiveZ":"positive z","negativeZ":"negative z"][d.rawValue]!,["positiveX":"x軸の正方向","negativeX":"x軸の負方向","positiveY":"y軸の正方向","negativeY":"y軸の負方向","positiveZ":"z軸の正方向","negativeZ":"z軸の負方向"][d.rawValue]!) }
    var interaction:NFExerciseInteraction {
        if case .adjacent=task.query { return .multipleChoice(.init(options:options,correctOptionIDs:task.acceptedIDs.sorted(),minimumSelections:1,maximumSelections:4)) }
        return .singleChoice(.init(options:options,correctOptionID:task.acceptedIDs.sorted().first ?? "unavailable"))
    }
    var rubric:NFExerciseRubric { .init(criteria:[.init(id:"fold",description:text("All requested face constraints","指定された面の条件すべて"),weight:1)],fullCreditThreshold:1,permitsPartialCredit:false) }
    var hint:String { text("Follow shared edges from the fixed face. Each 90° hinge changes the child face normal and carries its printed arrow with it. A closed cube needs six distinct outward normals; check every requested relation, not just one.","固定面から共有辺をたどります。90°の折り目ごとに次の面の法線が変わり、印刷された矢印も一緒に動きます。閉じた立方体には異なる6方向の外向き法線が必要です。求められた関係を1つだけでなくすべて確認してください。") }
    var explanation:String {
        guard let frames=task.completedFrames else { return text("This proposed pattern cannot form a closed cube: propagating the shared-edge folds produces repeated face directions or inconsistent closure. It must not be treated as a valid net.","この配置は閉じた立方体を作れません。共有辺に沿って折ると、面の方向が重なるか、閉じる条件が矛盾します。有効な展開図として扱うことはできません。") }
        return text("The completed face frames are: ","完成した各面の座標方向：")+frames.map { f in
            f.label+text(" normal "," の法線 ")+f.normal.token+text(", arrow ","、矢印 ")+f.up.token
        }.joined(separator:"; ")+". "+text("Opposite faces have opposite normals; edge-adjacent faces have perpendicular normals. Both proposed conditions must hold in the fixed frame.","向かい合う面の法線は逆方向で、辺を共有する面の法線は直交します。提案された条件は固定座標系で両方を満たす必要があります。")
    }
    var representation:NFSpatialRepresentationMetadata {
        let category="cube-net-contract",view=text("Fixed grid, anchor face and printed arrows","固定した格子、基準面、印刷された矢印")
        return .init(stimulusCategory:category,dimension:.threeDimensional,objectDescription:sourceDescription,viewpoint:view,
            operations:[.diagramEquationMatch],points:[],axisLabels:["x","y","z"],accessibilityDescription:sourceDescription,
            assetName:nil,protectedGrammarID:nil,difficultyParameters:.init(stimulusCategory:category,viewpoint:view,rotationMagnitudeDegrees:90,objectComplexity:0.6,distractorSimilarity:0.5,responseMode:task.acceptedIDs.count>1 ? .multipleChoice:.singleChoice))
    }
    static func make(exercise:NFExercise)->Self? {
        guard !exercise.assessmentProtected,exercise.lab == .spatial,[.practice,.documentPractice].contains(exercise.purpose),exercise.evidenceClass == exercise.purpose.evidenceClass,
            exercise.schemaVersion == 11,exercise.generatorVersion == 14,exercise.availabilityReason == nil,
            exercise.provenance.generatorID == "nf.exercise.fallback",exercise.provenance.generatorVersion == 14,
            exercise.provenance.contentTier == .deterministicGenerated,!exercise.provenance.isSourceGrounded,
            exercise.sourceContext.sourceDocumentIDs.isEmpty,exercise.sourceContext.sourceChunkIDs.isEmpty,exercise.sourceContext.groundingFacts.isEmpty,
            exercise.provenance.sourceDocumentIDs.isEmpty,exercise.provenance.sourceChunkIDs.isEmpty,exercise.citations.isEmpty,exercise.contextText == nil,
            let value=exercise.contractMetadata?.netFolding,value.isSupported,value.localeIdentifier == exercise.localeIdentifier,
            exercise.contractMetadata?.generatorVersion == 14,exercise.contractMetadata?.familyID == Self.familyID,
            exercise.templateID.hasSuffix(".v4.folding.retained-net"),exercise.contractMetadata?.structureID == value.task.identity,
            exercise.contractMetadata?.semanticFingerprint == NFQuestionFingerprint.netFoldingFingerprint(identity:value.task.identity),
            exercise.prompt == value.prompt,exercise.instructions == value.instructions,exercise.interaction == value.interaction,exercise.rubric == value.rubric,
            exercise.feedback.correctExplanation == value.explanation,exercise.feedback.retryExplanation == value.hint,exercise.feedback.decisiveStep == value.explanation,
            exercise.feedback.hintLadder == [value.hint],exercise.feedback.errorExplanations.isEmpty,
            exercise.accessibility.promptAccessibilityLabel == value.prompt,exercise.accessibility.visualAlternative == value.sourceDescription,
            exercise.representations == [.spatial(value.representation)],exercise.independentRepresentations == exercise.representations,
            exercise.skillWeights == ["skill.spatial":1] else{return nil}
        return value
    }
}
extension NFExercise {
    var hasSupportedNetFolding:Bool {
        contractMetadata?.netFolding == nil ? schemaVersion != 11 && !(generatorVersion == 14 && provenance.generatorID == "nf.exercise.fallback") : NFNetFoldingContract.make(exercise:self) != nil
    }
}


struct NFCoordinateReasoningContract: Codable, Equatable, Sendable {
    typealias G = NFCoordinateReasoningGeometry
    var policyVersion = 1
    let task: G.Task
    let localeIdentifier: String
    var isSupported: Bool { policyVersion == 1 && (localeIdentifier.hasPrefix("en") || localeIdentifier.hasPrefix("ja")) && task.isBounded && G.tasks.contains(task) }
    var familyID: String { task.familyVariant == 0 ? "nf.default.spatial.coordinate-rotation":"nf.default.spatial.vector-reflection" }
    var templateSlug: String { "coordinate.reasoning." + task.query.rawValue + "." + String(task.familyVariant) }
    func text(_ en:String,_ ja:String)->String { localeIdentifier.hasPrefix("ja") ? ja:en }
    func coordinate(_ p:G.Point)->String { "(\(p.x), \(p.y))" }
    func operationDescription(_ operation:G.Operation)->String {
        switch operation {
        case let .rotate(c,q): return text("Rotate actively \(abs(q)*90)° \(q > 0 ? "counterclockwise":"clockwise") about \(coordinate(c)).", "\(coordinate(c))を中心に、点を\(q > 0 ? "反時計回り":"時計回り")に\(abs(q)*90)°回します。")
        case let .translate(v): return text("Translate by \(coordinate(v)).", "\(coordinate(v))だけ平行移動します。")
        case let .reflect(line,k):
            let value:String = switch line { case .vertical:"x = \(k)";case .horizontal:"y = \(k)";case .risingDiagonal:"y = x";case .fallingDiagonal:"y = −x" }
            return text("Reflect across \(value).", "\(value)に関して対称移動します。")
        }
    }
    var operationList:String { task.operations.enumerated().map{"\($0.offset+1). "+operationDescription($0.element)}.joined(separator:"\n") }
    var coordinateConvention:String { text("Coordinates use grid units. The x-axis points right and the y-axis points up. These fixed axes and all named centers/lines stay unchanged; transformations move the points, not the viewpoint.","座標は格子単位です。x軸は右、y軸は上を向きます。固定された軸と指定された中心・直線は変わりません。変換で動くのは点であり、視点ではありません。") }
    var sourceDescription:String {
        guard task.isBounded else { return text("Saved transformation unavailable","保存済みの変換を利用できません") }
        switch task.query {
        case .inverse: return coordinateConvention + "\n" + text("The final point is Q = ","最終的な点はQ = ") + coordinate(task.pairs[0].target) + ".\n" + operationList
        case .inferAffine:
            let rows=task.pairs.enumerated().map { "\(["A","B","C"][$0.offset]): \(coordinate($0.element.source)) → \(coordinate($0.element.target))" }.joined(separator:"\n")
            return coordinateConvention + "\n" + text("Three labeled correspondences belong to one affine map of the entire plane. Use x′ = a×x + b×y + tx and y′ = c×x + d×y + ty. The original three points are noncollinear; these givens determine a unique affine map. No claim about arbitrary nonlinear maps is made.","3つの対応は平面全体の1つのアフィン変換に属します。x′ = a×x + b×y + tx、y′ = c×x + d×y + tyを使います。元の3点は一直線上になく、これらの条件からアフィン変換が一意に定まります。任意の非線形変換まで特定できるという意味ではありません。") + "\n" + rows
        case .orientationFixed:
            return coordinateConvention + "\n" + text("The ordered triangle is ","頂点の順番を指定した三角形は") + task.originals.enumerated().map{"\(["A","B","C"][$0.offset]) = \(coordinate($0.element))"}.joined(separator:"; ") + ".\n" + operationList
        }
    }
    var prompt:String {
        let question:String = switch task.query {
        case .inverse: text("Recover the original point P before the listed operations. Enter both original coordinates.","指定された操作を行う前の元の点Pを求めてください。元のx座標とy座標を入力します。")
        case .inferAffine: text("Find the six coefficients a, b, c, d, tx, and ty of that unique affine map.","一意に定まるアフィン変換の6つの係数a、b、c、d、tx、tyを求めてください。")
        case .orientationFixed: text("Select exactly two statements: whether the complete map preserves or reverses the orientation of A→B→C, and the full set of points left fixed by that map. Fixed points refer to the entire plane, not only the three drawn vertices.","文をちょうど2つ選んでください。変換全体がA→B→Cの向きを保つか反転させるかと、その変換で動かない点全体の集合を選びます。不動点は図の3頂点だけでなく、平面全体を対象にします。")
        }
        return sourceDescription + "\n" + question
    }
    var instructions:String {
        task.query == .orientationFixed
        ? text("Full credit requires both the orientation statement and the complete fixed-point classification. Select exactly two. The original triangle stays still until your answer is saved.","向きの文と不動点全体の分類の両方が正しければ満点です。ちょうど2つ選んでください。回答が保存されるまで元の三角形は動きません。")
        : text("Each exact numeric field receives an equal share of credit. All fields must be correct for full correctness; equivalent fractions are accepted. No worked solution appears before saving.","正確な各数値欄に均等に得点を配分します。完全な正解には全欄が正しいことが必要で、等価な分数も使用できます。保存前には解答例を表示しません。")
    }
    func responseLabel(_ key:String)->String {
        if ["x","y","tx","ty"].contains(key) { return text("\(key) (grid units)","\(key)（格子単位）") }
        return text("\(key) (unitless coefficient)","\(key)（単位のない係数）")
    }
    var options:[NFChoiceOption] {
        [("orientation-preserved",text("The orientation of A→B→C is preserved.","A→B→Cの向きは保たれます。")),
         ("orientation-reversed",text("The orientation of A→B→C is reversed.","A→B→Cの向きは反転します。")),
         ("fixed-none",text("There are no fixed points in the plane.","平面上に不動点はありません。")),
         ("fixed-point",text("Exactly one point in the plane is fixed.","平面上のちょうど1点が不動点です。")),
         ("fixed-line",text("The fixed points form exactly one complete straight line.","不動点全体は、ちょうど1本の直線をなします。")),
         ("fixed-plane",text("Every point in the plane is fixed.","平面上のすべての点が不動点です。"))].map { .init(id:$0.0,text:$0.1,accessibilityLabel:$0.1,distractorCode:nil) }
    }
    var acceptedOptionIDs:[String] {
        guard task.isBounded,let locus=task.fixedLocus else { return [] }
        return [task.orientationPreserved ? "orientation-preserved":"orientation-reversed","fixed-"+locus.rawValue]
    }
    var interaction:NFExerciseInteraction {
        if task.query == .orientationFixed { return .multipleChoice(.init(options:options,correctOptionIDs:acceptedOptionIDs,minimumSelections:2,maximumSelections:2)) }
        let values=task.exactValues
        let givens=Dictionary(uniqueKeysWithValues:publicPoints.flatMap { point in
            [(point.label+".x",String(Int(point.x))),(point.label+".y",String(Int(point.y)))]
        })
        return .logicState(.init(initialState:givens,
            expectedFinalState:values,acceptedEquivalentStates:[],ruleOptions:[],expectedViolatedRuleID:nil,
            fieldDomains:Dictionary(uniqueKeysWithValues:values.keys.map{($0,.exactNumber)})))
    }
    var rubric:NFExerciseRubric {
        let criteria:[NFExerciseRubricCriterion]
        if task.query == .orientationFixed { criteria=[.init(id:"orientation-and-fixed-locus",description:instructions,weight:1)] }
        else { criteria=task.exactValues.keys.sorted().map{.init(id:$0,description:responseLabel($0),weight:1 / Double(task.exactValues.count))} }
        return .init(criteria:criteria,fullCreditThreshold:1,permitsPartialCredit:task.query != .orientationFixed)
    }
    var hint:String {
        switch task.query {
        case .inverse: text("Undo the last operation first, then continue in reverse order. Invert each translation or rotation; reflecting in the same line twice returns the point.","最後の操作から逆順に戻します。平行移動や回転をそれぞれ逆にし、対称移動は同じ直線についてもう一度行うと元に戻ります。")
        case .inferAffine: text("Use differences between two source points and their target differences to solve the linear coefficients. Then substitute any full correspondence to obtain the translation. Check all three rows.","2つの元の点の差と対応先の差を使い、線形部分の係数を求めます。次に1組の対応を代入して平行移動量を求め、3行すべてを確認します。")
        case .orientationFixed: text("Track the sign of the ordered triangle's area. For fixed points, solve T(x,y)=(x,y) for all points of the plane; a vertex check alone is insufficient.","順序付き三角形の面積の符号を追います。不動点については平面全体でT(x,y)=(x,y)を解きます。頂点を確認するだけでは不十分です。")
        }
    }
    var explanation:String {
        guard task.isBounded,let f=task.map else { return hint }
        let map=text("Complete map: x′ = \(f.a)x + \(f.b)y + \(f.tx); y′ = \(f.c)x + \(f.d)y + \(f.ty).", "全体の変換：x′ = \(f.a)x + \(f.b)y + \(f.tx)、y′ = \(f.c)x + \(f.d)y + \(f.ty)。")
        switch task.query {
        case .inverse: return text("The original P is \(coordinate(task.originals[0])). Forward substitution gives Q = \(coordinate(task.pairs[0].target)).", "元のPは\(coordinate(task.originals[0]))です。順方向に代入するとQ = \(coordinate(task.pairs[0].target))になります。") + " " + map
        case .inferAffine: return map + " " + text("Substitution matches all three retained correspondences. Their nonzero signed source area proves uniqueness within the stated affine class.","代入すると、保存された3つの対応すべてに一致します。元の3点の符号付き面積がゼロでないため、指定されたアフィン変換の範囲では一意です。")
        case .orientationFixed:
            let classification=options.filter{acceptedOptionIDs.contains($0.id)}.map(\.text).joined(separator:" ")
            return map + " " + classification + " " + text("The determinant is \(f.determinant). Fixed points satisfy \(f.a-1)x + \(f.b)y = \(-f.tx) and \(f.c)x + \(f.d-1)y = \(-f.ty). The rank and consistency of these equations give the full fixed set.","行列式は\(f.determinant)です。不動点は\(f.a-1)x + \(f.b)y = \(-f.tx)、\(f.c)x + \(f.d-1)y = \(-f.ty)を満たします。方程式の階数と整合性から、不動点全体の集合が求まります。")
        }
    }
    var publicPoints:[NFSpatialPoint] {
        guard task.isBounded else { return [] }
        switch task.query {
        case .inverse: let p=task.pairs[0].target; return [.init(label:"Q",x:Double(p.x),y:Double(p.y),z:nil)]
        case .inferAffine: return task.pairs.enumerated().flatMap{ i,p in
            [NFSpatialPoint(label:["A","B","C"][i],x:Double(p.source.x),y:Double(p.source.y),z:nil),
             .init(label:["A′","B′","C′"][i],x:Double(p.target.x),y:Double(p.target.y),z:nil)] }
        case .orientationFixed: return task.originals.enumerated().map{.init(label:["A","B","C"][$0.offset],x:Double($0.element.x),y:Double($0.element.y),z:nil)}
        }
    }
    var representation:NFSpatialRepresentationMetadata {
        let viewpoint=text("Fixed x-right, y-up coordinate plane","右がx、上がyの固定座標平面")
        return .init(stimulusCategory:"coordinate-reasoning-contract",dimension:.twoDimensional,objectDescription:sourceDescription,
            viewpoint:viewpoint,operations:[.coordinateTransform],points:publicPoints,
            axisLabels:[text("x (grid units)","x（格子単位）"),text("y (grid units)","y（格子単位）")],
            accessibilityDescription:sourceDescription,assetName:nil,protectedGrammarID:nil,
            difficultyParameters:.init(stimulusCategory:"coordinate-reasoning-contract",viewpoint:viewpoint,
                rotationMagnitudeDegrees:0,objectComplexity:0.5,distractorSimilarity:0,
                responseMode:task.query == .orientationFixed ? .multipleChoice:.coordinateEntry))
    }
    var errorExplanations:[String:String] { task.query == .orientationFixed ? [:]:["logic_state":hint] }
    @inline(never)
    static func make(exercise:NFExercise)->Self? {
        guard !exercise.assessmentProtected,exercise.lab == .spatial,[.practice,.documentPractice].contains(exercise.purpose),
              exercise.evidenceClass == exercise.purpose.evidenceClass,exercise.schemaVersion == 12,exercise.generatorVersion == 15,
              exercise.availabilityReason == nil,exercise.provenance.generatorID == "nf.exercise.fallback",exercise.provenance.generatorVersion == 15,
              exercise.provenance.contentTier == .deterministicGenerated,!exercise.provenance.isSourceGrounded,
              exercise.provenance.sourceDocumentIDs.isEmpty,exercise.provenance.sourceChunkIDs.isEmpty,
              exercise.sourceContext.sourceDocumentIDs.isEmpty,exercise.sourceContext.sourceChunkIDs.isEmpty,
              exercise.sourceContext.groundingFacts.isEmpty,exercise.citations.isEmpty,exercise.contextText == nil,
              exercise.contractMetadata?.generatorVersion == 15,let value=exercise.contractMetadata?.coordinateReasoning,value.isSupported,
              value.localeIdentifier == exercise.localeIdentifier,exercise.templateID.hasSuffix(".v4."+value.templateSlug),
              exercise.contractMetadata?.familyID == value.familyID,exercise.contractMetadata?.structureID == value.task.identity,
              exercise.contractMetadata?.semanticFingerprint == NFQuestionFingerprint.coordinateReasoningFingerprint(identity:value.task.identity),
              exercise.prompt == value.prompt,exercise.instructions == value.instructions,
              exercise.accessibility.promptAccessibilityLabel == value.prompt,exercise.accessibility.visualAlternative == value.sourceDescription,
              exercise.feedback.correctExplanation == value.explanation,exercise.feedback.retryExplanation == value.hint,
              exercise.feedback.decisiveStep == value.explanation,exercise.feedback.hintLadder == [value.hint],exercise.feedback.errorExplanations == value.errorExplanations,
              exercise.skillWeights == ["skill.spatial":0.8,"skill.quantitative":0.2],exercise.rubric == value.rubric,
              exercise.interaction == value.interaction,exercise.representations == [.spatial(value.representation)],
              exercise.independentRepresentations == exercise.representations else { return nil }
        return value
    }
}
extension NFExercise {
    var hasSupportedCoordinateReasoning:Bool {
        contractMetadata?.coordinateReasoning == nil ? schemaVersion != 12 && !(generatorVersion == 15 && provenance.generatorID == "nf.exercise.fallback") : NFCoordinateReasoningContract.make(exercise:self) != nil
    }
}

struct NFSpatialAssemblyContract: Codable, Equatable, Sendable {
    typealias G = NFSpatialAssemblyGeometry
    var policyVersion = 1
    let task: G.Task
    let localeIdentifier: String
    var isSupported: Bool { policyVersion == 1 && (localeIdentifier.hasPrefix("en") || localeIdentifier.hasPrefix("ja")) && task.isBounded && G.tasks.contains(task) }
    var familyID: String { task.variant == 1 ? "nf.default.spatial.object-rotation":"nf.default.spatial.top-view" }
    var templateSlug: String { task.variant == 1 ? "assembly.asymmetric-orientation":"assembly.complete-reconstruction" }
    func text(_ en:String,_ ja:String)->String { localeIdentifier.hasPrefix("ja") ? ja:en }
    static func choiceID(_ i:Int)->String { String(UnicodeScalar(65+i)!) }
    func cellsText(_ cells:[G.Cell])->String { cells.map{"(\($0.x), \($0.y), \($0.z))"}.joined(separator:"; ") }
    func squaresText(_ cells:[G.Square])->String { cells.map{"(\($0.x), \($0.y))"}.joined(separator:"; ") }
    func heightsText(_ h:[Int])->String { zip(["(0,0)","(1,0)","(0,1)","(1,1)"],h).map{"\($0): \($1)"}.joined(separator:"; ") }
    var sourceDescription:String {
        let axes=text("Each cube has unit side length. The fixed axes are x, y, z. Front means the x–z projection viewed from negative y; side means the y–z projection viewed from positive x, with y increasing to the right on its printed grid. Opaque cubes on the same viewing ray overlap; a filled square means at least one occupied cell on that ray.","立方体の一辺は1です。固定軸はx、y、zです。正面図は負のy側から見たx–z投影、側面図は正のx側から見たy–z投影で、表示格子の右方向がyの増える向きです。同じ視線上の不透明な立方体は重なります。塗られたマスは、その視線上に占有セルが少なくとも1つあることを表します。")
        switch task {
        case let .orientation(v):
            return axes+"\n"+text("The original is one rigid solid of five face-connected cubes. Its complete occupied-cell coordinates (x,y,z), measured at the lower corner of each cube, are: ","元の物体は、面でつながった5個の立方体からなる1つの剛体です。各立方体の下側の角で測った、全占有セルの座標(x,y,z)：")+cellsText(v.source)+".\n"+text("The original coordinates are complete givens. Candidate cards show only two supplied silhouettes; hidden candidate cell coordinates are not supplied. Translation of the whole object is irrelevant and each candidate is aligned to its minimum coordinate. Only proper rigid rotations are allowed: no reflection, bending, or disassembly.","元の座標は完全な条件です。候補カードには指定された2つのシルエットだけを示し、隠れた候補セルの座標は示しません。物体全体の平行移動は考慮せず、各候補は最小座標を基準にそろえています。許されるのは向きを保つ剛体回転だけで、鏡映、曲げ、分解はできません。")
        case let .reconstruction(v):
            let c=v.constraints
            return axes+"\n"+text("The complete allowed model is a 2×2 grid of vertical columns at (0,0), (1,0), (0,1), (1,1). Each column has 0, 1, 2, or 3 cubes. Cubes are supported from below with no gaps or overhangs. The nonempty assembly must be connected through whole cube faces.","許されるモデル全体は、(0,0)、(1,0)、(0,1)、(1,1)にある2×2格子の垂直な柱です。各柱の立方体の数は0、1、2、3のいずれかです。隙間や張り出しはなく、立方体は下から支えられます。空でない組立体は、立方体の面を介してつながる必要があります。")+"\n"+text("Top occupied columns: ","上から見た占有列：")+c.top.enumerated().filter{$0.element}.map{["(0,0)","(1,0)","(0,1)","(1,1)"][$0.offset]}.joined(separator:"; ")+".\n"+text("Front heights at x=0,1: ","x=0,1での正面の高さ：")+c.front.map(String.init).joined(separator:", ")+". "+text("Side heights at y=0,1: ","y=0,1での側面の高さ：")+c.side.map(String.init).joined(separator:", ")+". "+text("Total cubes: \(c.cubeCount).","立方体の総数：\(c.cubeCount)。")
        }
    }
    var prompt:String {
        sourceDescription+"\n"+(task.variant == 1
            ? text("Select every candidate pair of silhouettes that can come from a proper rotation of this original solid. Compare both supplied views of each candidate.","元の物体を向きを保って回転させた結果として可能なシルエットの組を、すべて選んでください。各候補の指定された2つの図を比較します。")
            : text("Select every feasible reconstruction satisfying every supplied constraint. Every feasible arrangement in the stated finite model is included among the candidates. If none exists, select only ‘No arrangement satisfies all constraints’.","指定された条件をすべて満たす再構成を、すべて選んでください。指定された有限モデルで可能な配置は、すべて候補に含まれています。存在しない場合は「全条件を満たす配置はない」だけを選びます。"))
    }
    var instructions:String { text("Select all and only the feasible candidates. Full credit requires the complete accepted set. A worked reconstruction is available after your answer is saved; the original givens stay fixed.","可能な候補だけを、すべて選んでください。満点には正しい候補の集合全体が必要です。回答の保存後に解説用の再構成を確認できます。元の条件は固定されたままです。") }
    var options:[NFChoiceOption] {
        var result=(0..<task.candidateCount).map { i in
            let id=Self.choiceID(i),label=text("Candidate \(id)","候補\(id)")
            return NFChoiceOption(id:id,text:label,accessibilityLabel:label,distractorCode:nil)
        }
        if task.variant == 3 { let label=text("No arrangement satisfies all constraints","全条件を満たす配置はない");result.append(.init(id:"none",text:label,accessibilityLabel:label,distractorCode:nil)) }
        return result
    }
    var acceptedOptionIDs:[String] { task.impossible ? ["none"]:task.acceptedIndices.map(Self.choiceID) }
    var interaction:NFExerciseInteraction { .multipleChoice(.init(options:options,correctOptionIDs:acceptedOptionIDs,minimumSelections:1,maximumSelections:options.count)) }
    var rubric:NFExerciseRubric { .init(criteria:[.init(id:"complete-feasible-set",description:instructions,weight:1)],fullCreditThreshold:1,permitsPartialCredit:false) }
    var hint:String { task.variant == 1
        ? text("Track the original rigid structure through both views. A proper rotation preserves handedness and adjacency. A hidden overlap can conceal a cube, so use both silhouettes; do not classify by one outline alone.","元の剛体構造を2つの図で追います。向きを保つ回転では左右の関係と隣接関係が保たれます。重なりで立方体が隠れるため、1つの輪郭だけで判断せず両方のシルエットを使います。")
        : text("Enumerate the four column heights from 0 to 3. Keep only connected supported arrangements with the correct top footprint, both height projections, and total cube count. More than one complete solution can be valid.","4本の柱の高さを0から3の範囲で列挙します。支えがあり連結していて、上面の占有形、両方の高さの投影、立方体の総数が合う配置だけを残します。完全な解が複数あっても構いません。") }
    var explanation:String {
        guard task.isBounded else{return hint}
        let accepted=acceptedOptionIDs.joined(separator:", ")
        switch task {
        case .orientation:
            return text("Feasible silhouette pairs: \(accepted). Each accepted pair matches at least one of the 24 proper orientations of the original five-cube solid. Each rejected mirrored pair is distinct in the supplied two-view signature from every proper orientation; an occluded difference alone is never used to mark it wrong.","可能なシルエットの組：\(accepted)。正しい各組は、元の5立方体の24通りの向きを保つ姿勢の少なくとも1つと一致します。除外された鏡映の組は、指定された2方向の見え方で、どの正しい回転姿勢とも異なります。隠れた違いだけを理由に誤りとはしません。")
        case let .reconstruction(v):
            let classification=v.feasible.isEmpty ? text("The constraints are inconsistent.","条件は両立しません。") : v.feasible.count == 1 ? text("The constraints determine one arrangement.","条件から配置が1つに定まります。") : text("The constraints are underdetermined: \(v.feasible.count) arrangements remain possible.","条件だけでは一意に決まりません。\(v.feasible.count)通りの配置が可能です。")
            return classification+" "+text("Accepted candidates: \(accepted). Exhaustive checking of all 256 four-column height assignments gives this complete set; no omitted arrangement in the stated model also satisfies the givens.","正しい候補：\(accepted)。4本の柱の高さの全256通りを確認すると、この完全な集合になります。指定されたモデルで、条件を満たすのに省かれた配置はありません。")
        }
    }
    var representation:NFSpatialRepresentationMetadata {
        let view=text("Fixed supplied front and side projections","指定された固定の正面図と側面図")
        return .init(stimulusCategory:"spatial-assembly-contract",dimension:.threeDimensional,objectDescription:sourceDescription,
            viewpoint:view,operations:[.project],points:[],axisLabels:["x","y","z"],accessibilityDescription:sourceDescription,
            assetName:nil,protectedGrammarID:nil,difficultyParameters:.init(stimulusCategory:"spatial-assembly-contract",viewpoint:view,
                rotationMagnitudeDegrees:0,objectComplexity:0.8,distractorSimilarity:0.5,responseMode:.multipleChoice))
    }
    @inline(never)
    static func make(exercise:NFExercise)->Self? {
        guard !exercise.assessmentProtected,exercise.lab == .spatial,[.practice,.documentPractice].contains(exercise.purpose),
              exercise.evidenceClass == exercise.purpose.evidenceClass,exercise.schemaVersion == 13,exercise.generatorVersion == 16,
              exercise.availabilityReason == nil,exercise.provenance.generatorID == "nf.exercise.fallback",exercise.provenance.generatorVersion == 16,
              exercise.provenance.contentTier == .deterministicGenerated,!exercise.provenance.isSourceGrounded,
              exercise.provenance.sourceDocumentIDs.isEmpty,exercise.provenance.sourceChunkIDs.isEmpty,
              exercise.sourceContext.sourceDocumentIDs.isEmpty,exercise.sourceContext.sourceChunkIDs.isEmpty,
              exercise.sourceContext.groundingFacts.isEmpty,exercise.citations.isEmpty,exercise.contextText == nil,
              exercise.contractMetadata?.generatorVersion == 16,let value=exercise.contractMetadata?.spatialAssembly,value.isSupported,
              value.localeIdentifier == exercise.localeIdentifier,exercise.templateID.hasSuffix(".v4."+value.templateSlug),
              exercise.contractMetadata?.familyID == value.familyID,exercise.contractMetadata?.structureID == value.task.identity,
              exercise.contractMetadata?.semanticFingerprint == NFQuestionFingerprint.spatialAssemblyFingerprint(identity:value.task.identity),
              exercise.prompt == value.prompt,exercise.instructions == value.instructions,
              exercise.accessibility.promptAccessibilityLabel == value.prompt,exercise.accessibility.visualAlternative == value.sourceDescription,
              exercise.feedback.correctExplanation == value.explanation,exercise.feedback.retryExplanation == value.hint,
              exercise.feedback.decisiveStep == value.explanation,exercise.feedback.hintLadder == [value.hint],exercise.feedback.errorExplanations.isEmpty,
              exercise.skillWeights == ["skill.spatial":1],exercise.rubric == value.rubric,exercise.interaction == value.interaction,
              exercise.representations == [.spatial(value.representation)],exercise.independentRepresentations == exercise.representations else {return nil}
        return value
    }
}
extension NFExercise {
    var hasSupportedSpatialAssembly:Bool { contractMetadata?.spatialAssembly == nil
        ? schemaVersion != 13 && !(generatorVersion == 16 && provenance.generatorID == "nf.exercise.fallback")
        : NFSpatialAssemblyContract.make(exercise:self) != nil }
}

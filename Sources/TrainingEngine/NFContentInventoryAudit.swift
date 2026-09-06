import Foundation

struct NFContentInventoryLabCensus: Codable, Equatable, Sendable {
    let labID: String
    let concreteContractCount: Int
    let uniqueSemanticCount: Int
    let familyCounts: [String: Int]
    let structureCounts: [String: Int]
    let objectiveCounts: [String: Int]
    let responseFormCounts: [String: Int]
    let targetCount: Int
    let editorialBandCounts: [String: Int]
    let invalidContractCount: Int
    let admission: NFContentAdmissionReport
}

struct NFContentInventoryCensus: Codable, Equatable, Sendable {
    let schemaVersion: Int
    let generatorVersion: Int
    let bankVersion: Int
    let scoringVersion: Int
    let signedCorrectiveInventoryCoverage: Bool
    let labs: [NFContentInventoryLabCensus]
}

enum NFContentInventoryAudit {
    /// Caller supplies the exact regenerated bank, not a mirror generator.
    /// This report contains public built-in metadata and counts, never answers
    /// or imported personal text. Review approval is deliberately fail-closed.
    static func census(_ items: [NFExercise]) -> NFContentInventoryCensus {
        let labs = TrainingLab.allCases.map { lab in
            let exercises = items.filter { $0.lab == lab }
            func counts(_ value: (NFExercise) -> String) -> [String: Int] {
                Dictionary(grouping: exercises, by: value).mapValues(\.count)
            }
            let candidates = exercises.map { exercise in
                NFContentAdmissionCandidate(semanticProblemID: exercise.semanticProblemID,
                    semanticFingerprint: NFQuestionFingerprint.fingerprint(for: exercise),
                    fieldID: exercise.sourceContext.primaryField.rawValue,
                    structureID: exercise.contentStructureID,
                    compatibleFamilyIDs: [exercise.contentFamilyID],
                    availableAssetIDs: [], requiredAssetIDs: [], supportedLocaleIDs: [exercise.localeIdentifier],
                    valid: exercise.contractMetadata?.editorialDemand != nil && (try? NFExerciseSchemaValidator.validate(exercise)) != nil)
            }
            return NFContentInventoryLabCensus(labID: lab.rawValue,
                concreteContractCount: exercises.count,
                uniqueSemanticCount: Set(exercises.map { NFQuestionFingerprint.fingerprint(for: $0) }).count,
                familyCounts: counts(\.contentFamilyID), structureCounts: counts(\.contentStructureID),
                objectiveCounts: counts { $0.contractMetadata?.objectiveID ?? "legacy-unspecified" },
                responseFormCounts: counts { exercise in
                    switch exercise.interaction {
                    case .numeric: "numeric"
                    case .singleChoice: "singleChoice"
                    case .multipleChoice: "multipleChoice"
                    case .orderedSteps: "orderedSteps"
                    case .shortText: "shortText"
                    case .selfCheck: "selfCheck"
                    case .claimEvidence: "claimEvidence"
                    case .logicState: "logicState"
                    }
                },
                targetCount: Set(exercises.compactMap { $0.tags.first { $0.hasPrefix("knowledge-target.") } }).count,
                editorialBandCounts: counts { $0.contractMetadata?.editorialDemand?.editorialBand.rawValue ?? "unreviewed" },
                invalidContractCount: exercises.filter { (try? NFExerciseSchemaValidator.validate($0)) == nil }.count,
                admission: NFContentAdmission.assign(candidates, policy: NFContentAdmission.proposedEditionPolicy(for: lab)))
        }
        return NFContentInventoryCensus(schemaVersion: 1, generatorVersion: NFFallbackExerciseGenerator.generatorVersion,
            bankVersion: NFOfflineQuestionBank.version, scoringVersion: NFExerciseScoringEngine.scoringVersion,
            signedCorrectiveInventoryCoverage: false, labs: labs)
    }
}

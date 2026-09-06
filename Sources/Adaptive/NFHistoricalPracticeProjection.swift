import Foundation

/// History authority is separate from a reviewed-band evidence claim. This
/// projection never changes original scores and never labels an exclusion as
/// learner regression. Self-ratings remain authentic personal-study history.
enum NFHistoricalPracticeDisposition: String, Codable, Equatable, Sendable {
    case editorialEvidence
    case legacyPracticeHistory
    case personalStudy
    case excludedSkipped
    case excludedRevealed
    case excludedInvalidScore
    case excludedContentCorrection
}
struct NFHistoricalPracticeInput: Codable, Equatable, Sendable, Identifiable {
    let id: String
    let labID: String
    let originalCredit: Double
    let submittedAt: Date
    let responseFormatRaw: String?
    let sourceOrSetID: String?
    let isPersonalStudy: Bool
    let wasSkipped: Bool
    let editorialObservation: NFEditorialObservation?
}
struct NFHistoricalPracticeDispositionRecord: Codable, Equatable, Sendable, Identifiable {
    let id: String
    let attemptID: String
    let revision: Int
    let policyVersion: String
    let occurredAt: Date
    let disposition: NFHistoricalPracticeDisposition
    let reason: String
    let correctedDerivedCredit: Double?
    let supersedesDispositionID: String?
}
struct NFHistoricalPracticeSummary: Codable, Equatable, Sendable {
    let labID: String
    let legacyAttemptIDs: [String]
    let legacyMeanCredit: Double?
    let legacyLastPracticedAt: Date?
    let personalStudyAttemptIDs: [String]
    let excludedAttemptIDs: [String]
    let editorialAttemptIDs: [String]
    let appliedDispositionIDs: [String]
    var legacyCount: Int { legacyAttemptIDs.count }
}
enum NFHistoricalPracticeProjection {
    static let policyVersion = "LegacyPracticeAuthorityV1"

    static func classify(_ input: NFHistoricalPracticeInput) -> NFHistoricalPracticeDisposition {
        let format = input.responseFormatRaw?.lowercased().filter { $0.isLetter || $0.isNumber }
        if input.isPersonalStudy || input.sourceOrSetID != nil || format == "selfcheck" || format == "sourceselfcheck" || format == "selfreported" {
            return .personalStudy
        }
        if format == "revealed" || format == "solutionrevealed" { return .excludedRevealed }
        if input.wasSkipped { return .excludedSkipped }
        guard input.originalCredit.isFinite, (0...1).contains(input.originalCredit) else { return .excludedInvalidScore }
        if input.editorialObservation != nil { return .editorialEvidence }
        return .legacyPracticeHistory
    }

    static func reduce(_ inputs: [NFHistoricalPracticeInput], dispositions: [NFHistoricalPracticeDispositionRecord] = []) -> [NFHistoricalPracticeSummary] {
        let acceptedDispositions = dispositions.filter { $0.policyVersion == policyVersion }.sorted {
            if $0.revision != $1.revision { return $0.revision < $1.revision }
            if $0.occurredAt != $1.occurredAt { return $0.occurredAt < $1.occurredAt }
            return $0.id < $1.id
        }
        var latest: [String: NFHistoricalPracticeDispositionRecord] = [:]
        var seenDispositionIDs: Set<String> = []
        for d in acceptedDispositions where seenDispositionIDs.insert(d.id).inserted {
            if let prior = latest[d.attemptID], d.supersedesDispositionID != prior.id { continue }
            if latest[d.attemptID] == nil && d.supersedesDispositionID != nil { continue }
            latest[d.attemptID] = d
        }
        var seen: Set<String> = []
        let ordered = inputs.sorted { $0.submittedAt == $1.submittedAt ? $0.id < $1.id : $0.submittedAt < $1.submittedAt }
            .filter { seen.insert($0.id).inserted }
        let grouped = Dictionary(grouping: ordered, by: \.labID)
        return grouped.keys.sorted().map { lab in
            var legacy: [NFHistoricalPracticeInput] = [], personal: [String] = [], excluded: [String] = [], editorial: [String] = [], applied: [String] = []
            var creditSum = 0.0
            for input in grouped[lab]! {
                let correction = latest[input.id]
                if let correction { applied.append(correction.id) }
                let disposition = correction?.disposition ?? classify(input)
                switch disposition {
                case .legacyPracticeHistory:
                    let credit = correction?.correctedDerivedCredit ?? input.originalCredit
                    guard credit.isFinite, (0...1).contains(credit) else { excluded.append(input.id); continue }
                    legacy.append(input); creditSum += credit
                case .personalStudy: personal.append(input.id)
                case .editorialEvidence: editorial.append(input.id)
                case .excludedSkipped, .excludedRevealed, .excludedInvalidScore, .excludedContentCorrection: excluded.append(input.id)
                }
            }
            return NFHistoricalPracticeSummary(labID: lab, legacyAttemptIDs: legacy.map(\.id),
                legacyMeanCredit: legacy.isEmpty ? nil : creditSum / Double(legacy.count),
                legacyLastPracticedAt: legacy.last?.submittedAt, personalStudyAttemptIDs: personal,
                excludedAttemptIDs: excluded, editorialAttemptIDs: editorial, appliedDispositionIDs: applied)
        }
    }
}

extension NFHistoricalPracticeProjection {
    static func reduce(attempts: [AttemptDTO], dispositions: [NFHistoricalPracticeDispositionRecord] = []) -> [NFHistoricalPracticeSummary] {
        reduce(attempts.map { attempt in
            NFHistoricalPracticeInput(id: attempt.id.uuidString, labID: attempt.lab.rawValue,
                originalCredit: attempt.credit, submittedAt: attempt.submittedAt,
                responseFormatRaw: attempt.responseFormatRaw, sourceOrSetID: nil,
                isPersonalStudy: attempt.evidenceClass == .documentPractice,
                wasSkipped: attempt.wasSkipped, editorialObservation: attempt.editorialObservation)
        }, dispositions: dispositions)
    }
}

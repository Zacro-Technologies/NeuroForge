import CryptoKit
import Foundation

/// Scoped observations from saved AI-evaluated practice. This projection makes
/// no mastery, transfer-effectiveness or standardized-ability inference.
enum NFAILearningProgress {
    enum ScopeKind: String, Sendable { case source, topic }

    struct Answer: Identifiable, Equatable, Sendable {
        let id: UUID
        let submittedAt: Date
        let prompt: String
        let originalCredit: Double
        let earnedCredit: Double
        let originalFeedback: String
        let effectiveFeedback: String
        let originalReceiptID: UUID
        let effectiveReceiptID: UUID
        let wasReviewed: Bool
        let wasAssisted: Bool
    }

    struct CriterionFocus: Equatable, Sendable {
        let attemptID: UUID
        let submittedAt: Date
        let criterionID: String
        let criterion: String
        let credit: Double
        let explanation: String
        let nextStep: String?
    }

    struct Scope: Identifiable, Equatable, Sendable {
        let id: String
        let kind: ScopeKind
        let title: String
        let topic: String?
        let answers: [Answer]
        let latestCriterionNeedingWork: CriterionFocus?

        var attemptIDs: [UUID] { answers.map(\.id) }
        var attemptCount: Int { answers.count }
        var earnedCredit: Double { answers.reduce(0) { $0 + $1.earnedCredit } }
        var possibleCredit: Double { Double(answers.count) }
        var latestSubmittedAt: Date { answers[0].submittedAt }
    }

    /// Inputs are immutable history copies plus retained authority. Callers may
    /// apply historical content corrections to those copies before projection.
    static func make(attempts: [NFReadOnlyAttemptSnapshot],
                     originalReceipts: [UUID: NFAIGradeReceipt],
                     reviewJobs: [NFAIGradingJob]) -> [Scope] {
        var groups: [String: [(ScopeDescriptor, Answer, CriterionFocus?)]] = [:]
        let copies = Dictionary(grouping: attempts, by: \.id)
        let reviews = Dictionary(grouping: reviewJobs, by: { $0.request.attemptID })
        for (id, rows) in copies {
            guard let row = rows.first, rows.dropFirst().allSatisfy({ sameAuthority($0, row) }),
                  row.source != .protectedAssessment, row.selfCheckRating == nil,
                  row.correction?.excludesAccuracy != true,
                  [.correct, .partial, .incorrect].contains(row.result),
                  row.submittedAt.timeIntervalSince1970.isFinite,
                  let original = originalReceipts[id], original.request.reviewOf == nil,
                  original.request.runID == row.sessionID,
                  original.request.attemptID == row.id,
                  original.request.exercise.prompt == row.prompt,
                  original.request.exercise.lab == row.lab,
                  original.request.exercise.templateID == row.templateID,
                  original.request.response == NFResponsePresentation.decode(row.rawResponse),
                  !original.request.exercise.assessmentProtected,
                  let originalScore = try? NFAIGradeValidator.score(original, for: original.request),
                  originalScore.scoringVersion == row.scoringVersion,
                  row.deterministicCredit.isFinite,
                  abs(originalScore.credit - row.deterministicCredit) <= 0.000_001 else { continue }
            let selected = row.applyingAIGrade(original, reviews: reviews[id] ?? [])
            guard let effective = selected.effectiveAIGrade,
                  let effectiveScore = try? NFAIGradeValidator.score(effective, for: effective.request),
                  selected.effectiveCredit.isFinite, (0...1).contains(selected.effectiveCredit),
                  let descriptor = scope(for: original.request.exercise) else { continue }
            let answer = Answer(id: id, submittedAt: row.submittedAt, prompt: row.prompt,
                originalCredit: originalScore.credit, earnedCredit: selected.effectiveCredit,
                originalFeedback: original.explanation, effectiveFeedback: effective.explanation,
                originalReceiptID: original.id, effectiveReceiptID: effective.id,
                wasReviewed: effective.id != original.id, wasAssisted: row.hintCount > 0)
            let focus: CriterionFocus?
            if selected.correction?.correctedCredit != nil {
                // A separately corrected total does not imply per-criterion
                // judgments that its correction receipt never supplied.
                focus = nil
            } else if effectiveScore.credit < 1,
                      let criterion = effective.criteria.filter({ $0.credit < 1 }).min(by: {
                          if $0.credit != $1.credit { return $0.credit < $1.credit }
                          return $0.criterionID < $1.criterionID
                      }),
                      let rubricCriterion = effective.request.exercise.aiRubric?.criteria.first(where: { $0.id == criterion.criterionID }) {
                focus = CriterionFocus(attemptID: id, submittedAt: row.submittedAt,
                    criterionID: criterion.criterionID, criterion: rubricCriterion.description,
                    credit: criterion.credit, explanation: criterion.explanation, nextStep: effective.nextStep)
            } else { focus = nil }
            groups[descriptor.id, default: []].append((descriptor, answer, focus))
        }
        return groups.values.compactMap { values -> Scope? in
            let sorted = values.sorted {
                if $0.1.submittedAt != $1.1.submittedAt { return $0.1.submittedAt > $1.1.submittedAt }
                return $0.1.id.uuidString < $1.1.id.uuidString
            }
            guard let latest = sorted.first else { return nil }
            return Scope(id: latest.0.id, kind: latest.0.kind, title: latest.0.title,
                topic: latest.0.topic, answers: sorted.map { $0.1 },
                latestCriterionNeedingWork: sorted.compactMap { $0.2 }.first)
        }.sorted {
            if $0.latestSubmittedAt != $1.latestSubmittedAt { return $0.latestSubmittedAt > $1.latestSubmittedAt }
            return $0.id < $1.id
        }
    }

    private struct ScopeDescriptor {
        let id: String
        let kind: ScopeKind
        let title: String
        let topic: String?
    }
    private struct ScopeIdentity: Encodable {
        let version = 1
        let lab: String
        let field: String
        let topic: String
        let sourceIDs: [String]
        let anonymousSourceChunks: [String]
    }

    private static func scope(for exercise: NFExercise) -> ScopeDescriptor? {
        let context = exercise.sourceContext
        let sourceIDs = Set((context.sourceDocumentIDs + exercise.provenance.sourceDocumentIDs).map {
            UUID(uuidString: $0)?.uuidString.lowercased() ?? $0
        }).sorted()
        let topic = nonblank(context.topic)
        let material = nonblank(context.materialTitle)
        let identityTopic = topic ?? (sourceIDs.isEmpty ? material ?? exercise.title : "")
        let anonymous = sourceIDs.isEmpty && !context.sourceChunkIDs.isEmpty
        let identity = ScopeIdentity(lab: exercise.lab.rawValue, field: context.primaryField.rawValue,
            topic: identityTopic.precomposedStringWithCanonicalMapping.lowercased(), sourceIDs: sourceIDs,
            anonymousSourceChunks: anonymous ? context.sourceChunkIDs.sorted() : [])
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(identity) else { return nil }
        let id = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        let isSource = !sourceIDs.isEmpty || anonymous
        let title = isSource ? material ?? topic ?? exercise.title : topic ?? material ?? exercise.title
        guard nonblank(title) != nil else { return nil }
        return ScopeDescriptor(id: id, kind: isSource ? .source : .topic,
            title: title, topic: topic == title ? nil : topic)
    }

    private static func nonblank(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func sameAuthority(_ a: NFReadOnlyAttemptSnapshot, _ b: NFReadOnlyAttemptSnapshot) -> Bool {
        a.id == b.id && a.sessionID == b.sessionID && a.submittedAt == b.submittedAt
            && a.prompt == b.prompt && a.rawResponse == b.rawResponse && a.lab == b.lab
            && a.templateID == b.templateID && a.scoringVersion == b.scoringVersion
            && a.result == b.result && a.deterministicCredit == b.deterministicCredit
            && a.source == b.source && a.selfCheckRating == b.selfCheckRating
            && a.hintCount == b.hintCount && a.correction == b.correction
    }
}

import Foundation

enum NFGeneratedPracticeCompatibility {
    static let presentationVersion = 1
    static let selectionPolicyVersion = 1
    static let unavailableMessage = "This saved work needs a compatible version of NeuroForge. Your original answers remain saved."

    static func unavailableReason(for result: NFAuthoringResult) -> String? {
        guard !result.questions.isEmpty,
              result.questions.allSatisfy({ NFAuthoredExerciseAuthority.validatesBinding($0) }) else {
            return unavailableMessage
        }
        return nil
    }

    /// Structural draft compatibility deliberately permits blank and wrong
    /// answers. It rejects mismatched response families and duplicate identities
    /// before UI restoration can build keyed collections from untrusted arrays.
    static func responseIsStructurallyCompatible(_ response: NFExerciseResponse, with interaction: NFExerciseInteraction) -> Bool {
        switch (response, interaction) {
        case (.numeric, .numeric), (.shortText, .shortText), (.selfCheck, .selfCheck): true
        case let (.singleChoice(id), .singleChoice(schema)):
            id.isEmpty || schema.options.contains { $0.id == id }
        case let (.multipleChoice(ids), .multipleChoice(schema)):
            Set(ids).count == ids.count && Set(ids).isSubset(of: Set(schema.options.map(\.id)))
        case let (.orderedSteps(ids), .orderedSteps(schema)):
            Set(ids).count == ids.count && (ids.isEmpty || Set(ids) == Set(schema.steps.map(\.id)))
        case let (.claimEvidence(submission), .claimEvidence(schema)):
            Set(submission.pairs.map(\.claimID)).count == submission.pairs.count
                && submission.pairs.allSatisfy { pair in
                    schema.claims.contains { $0.id == pair.claimID }
                        && Set(pair.evidenceIDs).count == pair.evidenceIDs.count
                        && Set(pair.evidenceIDs).isSubset(of: Set(schema.evidence.map(\.id)))
                }
        case let (.logicState(submission), .logicState(schema)):
            Set(submission.finalState.keys).isSubset(of: Set(schema.expectedFinalState.keys))
                && (submission.violatedRuleID == nil || schema.ruleOptions.contains { $0.id == submission.violatedRuleID })
        default: false
        }
    }
}

/// The entire accepted local set is pinned, so later edits or cache expiry cannot
/// replace a question underneath its saved response. No protected item is admitted.
struct NFGeneratedPracticeDraft: Codable, Identifiable, Sendable {
    var schemaVersion = 1
    // Optional only for decoding older payloads. A missing evaluator pin is
    // retained for recovery; it is never inferred from a generator version.
    var scorerVersion: Int? = NFExerciseScoringEngine.scoringVersion
    var presentationVersion: Int? = NFGeneratedPracticeCompatibility.presentationVersion
    var selectionPolicyVersion: Int? = NFGeneratedPracticeCompatibility.selectionPolicyVersion
    let id: UUID
    let ownerDeviceID: UUID
    var result: NFAuthoringResult
    var request: NFAuthoringRequest
    let index: Int
    var stage: Int
    let response: NFExerciseResponse
    let confidence: ConfidenceLevel?
    let referenceRevealed: Bool
    let hintRevealed: Bool
    var correctness: [Bool]
    let lastScore: NFExerciseScoringResult?
    var scoredResponse: NFExerciseResponse? = nil
    let pendingAttemptID: UUID?
    let shownAt: Date
    let activeDuration: TimeInterval
    /// Guidance for the exact saved editable response, never an attempt result.
    var clarificationMessage: String? = nil
    var hintExpanded: Bool? = nil
    var mathWork: NFMathWorkDraft? = nil
    var traceInspection: NFTraceInspectionDraft? = nil
    var dataInspection: NFDataInspectionDraft? = nil
    var scienceStudy: NFScienceStudyDraft? = nil
    var transferRelationship: NFTransferRelationshipDraft? = nil
    var runState: NFGeneratedRunState? = nil
    var terminalState: NFGeneratedTerminalState? = nil
    var terminalInventory: NFGeneratedTerminalInventory? = nil
    var pendingUnscored: NFGeneratedRunState.Outcome? = nil
    /// Pinned before transport; job status and receipts live in the repository namespace.
    var aiGradingRequest: NFAIGradeRequest? = nil
    var aiGradeReviews: [NFAIGradingJob]? = nil

    var unavailableReason: String? {
        guard [1, 2].contains(schemaVersion),
              scorerVersion == NFExerciseScoringEngine.scoringVersion,
              presentationVersion == NFGeneratedPracticeCompatibility.presentationVersion,
              selectionPolicyVersion == NFGeneratedPracticeCompatibility.selectionPolicyVersion,
              lastScore.map({ $0.scoringVersion == scorerVersion }) ?? true,
              result.questions.indices.contains(index), (0...4).contains(stage),
              activeDuration.isFinite, activeDuration >= 0 else {
            return NFGeneratedPracticeCompatibility.unavailableMessage
        }
        if let reason = NFGeneratedPracticeCompatibility.unavailableReason(for: result) { return reason }
        if terminalInventory?.valid(for: self) == false { return NFGeneratedPracticeCompatibility.unavailableMessage }
        if runState?.valid(for: self) == false { return NFGeneratedPracticeCompatibility.unavailableMessage }
        if let terminalState {
            guard stage == 3, (0...plannedQuestionCount).contains(terminalState.completedCount) else { return NFGeneratedPracticeCompatibility.unavailableMessage }
            if let runState, (terminalState.completedCount != runState.completedCount || terminalState.endedEarly != (runState.status == .endedEarly)) { return NFGeneratedPracticeCompatibility.unavailableMessage }
        }
        let unscored = runState?.pendingUnscored ?? pendingUnscored
        if unscored != nil && unscored != .skipped && unscored != .revealed { return NFGeneratedPracticeCompatibility.unavailableMessage }
        let exercise = result.questions[index].authoritativeExercise
        let containsAI = result.questions.contains { $0.authoritativeExercise.aiRubric != nil }
        guard schemaVersion == 2 || (!containsAI && aiGradingRequest == nil && aiGradeReviews == nil) else {
            return NFGeneratedPracticeCompatibility.unavailableMessage
        }
        if let grading = aiGradingRequest {
            guard schemaVersion == 2, grading.runID == id, grading.attemptID == pendingAttemptID,
                  grading.slotID == runState?.current.id.uuidString, grading.exercise == exercise,
                  grading.response == response, grading.reviewOf == nil,
                  (try? NFAIGradeValidator.validateRequest(grading)) != nil else {
                return NFGeneratedPracticeCompatibility.unavailableMessage
            }
        }
        if let score = lastScore, exercise.aiRubric != nil, unscored == nil {
            guard let grading = aiGradingRequest, score.aiGrade?.request == grading,
                  NFAIGradeValidator.validatesScore(score, exercise: exercise, response: response,
                    attemptID: pendingAttemptID) else { return NFGeneratedPracticeCompatibility.unavailableMessage }
        }
        if let reviews = aiGradeReviews {
            guard reviews.count <= 16, Set(reviews.map(\.id)).count == reviews.count,
                  reviews.allSatisfy({ review in
                      guard review.ownerDeviceID == ownerDeviceID, review.request.runID == id,
                            review.request.reviewOf != nil,
                            let slot = runState?.slots.first(where: { $0.attemptID == review.request.attemptID }),
                            slot.id.uuidString == review.request.slotID,
                            slot.exerciseDigest == (try? NFLocalItemCheckpoint.digest(review.request.exercise)),
                            (try? NFAIGradingJobStore.validate(review)) != nil else { return false }
                      if review.request.attemptID == pendingAttemptID {
                          return review.request.response == response && review.request.exercise == exercise
                            && review.request.reviewOf == lastScore?.aiGrade?.id
                      }
                      return slot.outcome == .scored
                  }) else { return NFGeneratedPracticeCompatibility.unavailableMessage }
        }
        guard NFTransferRelationshipDraft.permits(transferRelationship, exercise: exercise, response: response, committing: [1, 2].contains(stage) && unscored == nil), transferRelationship?.awaitsRelationship != true || !hintRevealed,
              NFScienceStudyDraft.permits(scienceStudy, exercise: exercise, response: response, committing: [1, 2].contains(stage) && unscored == nil),
              dataInspection?.isCompatible(with: exercise) != false,
              mathWork?.isCompatible(with: exercise, response: response) != false,
              !([1, 2].contains(stage) && unscored == nil && mathWork?.awaitsEstimate == true),
              traceInspection.map({ $0.isValid(for: exercise) }) ?? true,
              NFGeneratedPracticeCompatibility.responseIsStructurallyCompatible(response, with: exercise.interaction) else {
            return NFGeneratedPracticeCompatibility.unavailableMessage
        }
        if (stage == 1 || stage == 2), unscored != nil {
            guard pendingAttemptID != nil, scoredResponse == response, lastScore == nil else { return NFGeneratedPracticeCompatibility.unavailableMessage }
        } else if stage == 1 || stage == 2 {
            guard pendingAttemptID != nil, scoredResponse == response,
                  let lastScore, lastScore.exerciseID == exercise.id,
                  lastScore.credit.isFinite, (0...1).contains(lastScore.credit),
                  [.correct, .partial, .incorrect, .selfReported].contains(lastScore.outcome),
                  NFExerciseResponseValidator.validate(response, for: exercise.interaction,
                    localeIdentifier: exercise.localeIdentifier).isValid else {
                return NFGeneratedPracticeCompatibility.unavailableMessage
            }
            if case .selfCheck = exercise.interaction, !referenceRevealed {
                return NFGeneratedPracticeCompatibility.unavailableMessage
            }
        }
        if stage == 4 {
            guard case .selfCheck = exercise.interaction, referenceRevealed else {
                return NFGeneratedPracticeCompatibility.unavailableMessage
            }
        }
        return nil
    }

    var valid: Bool { unavailableReason == nil }
}

extension AppStore {
    var generatedPracticeDrafts: [NFGeneratedPracticeDraft] {
        _ = localSessionRevision
        return (localSessions.archive.privateStudyRuns ?? []).sorted { $0.updatedAt > $1.updatedAt }
            .compactMap { try? JSONDecoder().decode(NFGeneratedPracticeDraft.self, from: $0.payload) }
            // Keep decodable unavailable work discoverable. Hiding it would
            // make an incompatible saved run look like a new empty session.
            .filter { !$0.valid || $0.stage != 3 }
    }

    func generatedPracticeDraft(for generationID: UUID) -> NFGeneratedPracticeDraft? {
        generatedPracticeDrafts.first { $0.result.provenance.requestID == generationID }
    }

    func generatedPracticeRecoveryReason(for generationID: UUID) -> String? {
        for record in localSessions.archive.privateStudyRuns ?? []
            where record.generationID == generationID && record.id != NFPrivateStudyMetadata.recordID {
            guard let draft = try? JSONDecoder().decode(NFGeneratedPracticeDraft.self, from: record.payload),
                  draft.id == record.id, draft.result.provenance.requestID == record.generationID,
                  draft.valid else { return NFGeneratedPracticeCompatibility.unavailableMessage }
        }
        return nil
    }
}

struct NFGeneratedTerminalState: Codable, Equatable, Sendable {
    let endedEarly: Bool
    let completedCount: Int
}

/// Local authored-run authority. Nil on an older draft is deliberately not
/// reconstructed from generation-wide attempt history.
struct NFGeneratedRunState: Codable, Equatable, Sendable {
    enum Status: String, Codable, Sendable { case active, suspended, completed, endedEarly }
    enum StopReason: String, Codable, Sendable { case completedCount, learnerEnded }
    enum Outcome: String, Codable, Sendable { case scored, selfReported, skipped, revealed }
    struct Slot: Codable, Equatable, Sendable {
        let id: UUID
        let attemptID: UUID
        let index: Int
        let exerciseID: String
        let exerciseDigest: String
        var presentedAt: Date?
        var outcome: Outcome?
        var assistance: [NFLocalAssistanceEvent] = []
    }
    var version = 1
    var revision = 0
    var status: Status = .active
    var stopReason: StopReason?
    var slots: [Slot]
    var pendingUnscored: Outcome?
    var nextHintIndex = 0
    var interruptionCount = 0

    static func initial(exercise: NFExercise, index: Int = 0) throws -> Self {
        .init(slots: [.init(id: UUID(), attemptID: UUID(), index: index,
            exerciseID: exercise.id, exerciseDigest: try NFLocalItemCheckpoint.digest(exercise))])
    }
    var isTerminal: Bool { status == .completed || status == .endedEarly }
    var completedCount: Int { slots.filter { $0.outcome != nil }.count }
    var answeredCount: Int { slots.filter { $0.outcome == .scored || $0.outcome == .selfReported }.count }
    var current: Slot { slots[slots.count - 1] }

    func valid(for draft: NFGeneratedPracticeDraft) -> Bool {
        guard version == 1, revision >= 0, interruptionCount >= 0,
              !slots.isEmpty, slots.count <= draft.result.questions.count, slots.count <= 512,
              Set(slots.map(\.id)).count == slots.count,
              Set(slots.map(\.attemptID)).count == slots.count,
              nextHintIndex >= 0, nextHintIndex <= 64,
              current.index == draft.index, current.attemptID == draft.pendingAttemptID,
              pendingUnscored == draft.pendingUnscored,
              draft.correctness.count == slots.filter({ $0.outcome == .scored }).count,
              draft.hintRevealed == (nextHintIndex > 0),
              current.assistance.filter({ $0.kind == .hint }).count == nextHintIndex,
              pendingUnscored == nil || pendingUnscored == .skipped || pendingUnscored == .revealed,
              pendingUnscored == nil || draft.stage == 1 || draft.stage == 2 || draft.stage == 3,
              isTerminal == (draft.stage == 3),
              (status == .completed ? stopReason == .completedCount && completedCount == draft.plannedQuestionCount
                  : status == .endedEarly ? stopReason == .learnerEnded : stopReason == nil) else { return false }
        for (index, slot) in slots.enumerated() {
            guard slot.index == index, draft.result.questions.indices.contains(index),
                  slot.exerciseID == draft.result.questions[index].authoritativeExercise.id,
                  slot.exerciseDigest == (try? NFLocalItemCheckpoint.digest(draft.result.questions[index].authoritativeExercise)),
                  index == slots.count - 1 || slot.outcome != nil,
                  slot.assistance.count <= 128,
                  Set(slot.assistance.map(\.id)).count == slot.assistance.count,
                  slot.assistance.allSatisfy({ $0.activeOffset.isFinite && $0.activeOffset >= 0 && $0.stage >= 0
                    && $0.generatorVersion == draft.result.questions[index].authoritativeExercise.generatorVersion }),
                  slot.presentedAt.map({ $0.timeIntervalSinceReferenceDate.isFinite }) ?? true else { return false }
        }
        if draft.stage == 2 {
            if let pendingUnscored { return current.outcome == pendingUnscored }
            return current.outcome == (draft.lastScore?.outcome == .selfReported ? .selfReported : .scored)
        }
        if draft.stage == 0 || draft.stage == 4 { return current.outcome == nil }
        return true
    }
}

extension AppStore {
    var generatedPracticeRuns: [NFGeneratedPracticeDraft] {
        _ = localSessionRevision
        return (localSessions.archive.privateStudyRuns ?? []).compactMap {
            try? JSONDecoder().decode(NFGeneratedPracticeDraft.self, from: $0.payload)
        }
    }
    func generatedRunSummary(sessionID: UUID) -> String? {
        guard let draft = generatedPracticeRuns.first(where: { $0.id == sessionID }), draft.valid else { return nil }
        if let terminal = draft.terminalState, draft.runState == nil {
            return terminal.endedEarly
                ? NFAppLocalization.localized("Ended after \(terminal.completedCount) of \(draft.plannedQuestionCount) questions.", locale: NFAppLocalization.preferredLocale, comment: "Legacy saved run early ending.")
                : NFAppLocalization.localized("Completed \(terminal.completedCount) of \(draft.plannedQuestionCount) questions.", locale: NFAppLocalization.preferredLocale, comment: "Legacy saved run completion.")
        }
        guard let state = draft.runState, state.isTerminal else { return nil }
        return state.status == .completed
            ? NFAppLocalization.localized("Completed \(state.completedCount) of \(draft.plannedQuestionCount) questions.", locale: NFAppLocalization.preferredLocale, comment: "Saved authored run completion scope.")
            : NFAppLocalization.localized("Ended after \(state.completedCount) of \(draft.plannedQuestionCount) questions.", locale: NFAppLocalization.preferredLocale, comment: "Saved authored run early ending scope.")
    }
}

extension NFLocalSessionRepository {
    /// Compare the expected revision and immutable accepted prefix before any
    /// private archive replacement. Generic imported legacy bytes remain untouched.
    func saveGeneratedPracticeDraft(_ draft: NFGeneratedPracticeDraft, expectedRevision: Int?) throws {
        try requireArchiveWriteAvailability()
        try replaceGeneratedCandidate(Self.generatedCandidate(draft, expectedRevision: expectedRevision,
            in: archive, ownerDeviceID: ownerDeviceID, at: Date()))
    }

    nonisolated static func generatedCandidate(_ draft: NFGeneratedPracticeDraft, expectedRevision: Int?,
        in archive: Archive, ownerDeviceID: UUID, at: Date) throws -> Archive {
        guard draft.valid, draft.ownerDeviceID == ownerDeviceID, let state = draft.runState else {
            throw RepositoryError.corruptSnapshot
        }
        let previousRecord = archive.privateStudyRuns?.first { $0.id == draft.id }
        if let previousRecord {
            guard let previous = try? JSONDecoder().decode(NFGeneratedPracticeDraft.self, from: previousRecord.payload),
                  previous.valid, let old = previous.runState, old.revision == expectedRevision,
                  state.revision == (try NFSessionWriterRevision.next(after: old.revision)), previous.ownerDeviceID == draft.ownerDeviceID,
                  previous.result.provenance.requestID == draft.result.provenance.requestID,
                  try draft.preservesAcceptedInventory(from: previous),
                  state.slots.count >= old.slots.count, state.slots.count <= old.slots.count + 1 else {
                throw RepositoryError.staleRevision
            }
            if previous.index == draft.index, let frozen = previous.aiGradingRequest {
                guard draft.aiGradingRequest == frozen, previous.response == draft.response,
                      previous.confidence == draft.confidence else { throw RepositoryError.conflictingAttempt }
            }
            let oldReviews = previous.aiGradeReviews ?? []
            do {
                let newReviews = draft.aiGradeReviews ?? []
                guard newReviews.count >= oldReviews.count,
                      zip(oldReviews, newReviews).allSatisfy({ old, new in
                          old.request == new.request && old.ownerDeviceID == new.ownerDeviceID
                            && (old.receipt == nil || old.receipt == new.receipt)
                            && new.events.starts(with: old.events)
                      }) else { throw RepositoryError.conflictingAttempt }
            }
            if previous.index == draft.index, previous.stage == 1 || previous.stage == 2 {
                guard previous.response == draft.response, previous.scoredResponse == draft.scoredResponse,
                      previous.confidence == draft.confidence, previous.lastScore == draft.lastScore,
                      previous.mathWork == draft.mathWork, previous.traceInspection == draft.traceInspection,
                      previous.dataInspection == draft.dataInspection, previous.scienceStudy == draft.scienceStudy,
                      previous.transferRelationship == draft.transferRelationship,
                      previous.referenceRevealed == draft.referenceRevealed,
                      previous.pendingUnscored == draft.pendingUnscored else { throw RepositoryError.conflictingAttempt }
            }
            if old.isTerminal {
                guard old.status == state.status, old.stopReason == state.stopReason,
                      old.slots == state.slots else { throw RepositoryError.staleRevision }
            }
            for (index, slot) in old.slots.enumerated() {
                let replacement = state.slots[index]
                guard slot.id == replacement.id, slot.attemptID == replacement.attemptID,
                      slot.index == replacement.index, slot.exerciseDigest == replacement.exerciseDigest,
                      slot.presentedAt == nil || slot.presentedAt == replacement.presentedAt,
                      slot.outcome == nil || slot.outcome == replacement.outcome,
                      replacement.assistance.starts(with: slot.assistance) else { throw RepositoryError.staleRevision }
            }
        } else {
            guard expectedRevision == nil, state.revision == 1,
                  state.slots.count == 1, draft.index == 0, draft.terminalInventory == nil else { throw RepositoryError.staleRevision }
        }
        return try privateRunCandidate(id: draft.id, generationID: draft.result.provenance.requestID,
            payload: JSONEncoder().encode(draft), in: archive, at: at)
    }
}

/// Terminal-only inventory release. The original request/result identities stay
/// auditable without keeping unused source text or unpresented future questions.
struct NFGeneratedTerminalInventory: Codable, Equatable, Sendable {
    var version = 1
    let plannedQuestionCount: Int
    let originalResultDigest: String
    let originalRequestDigest: String

    func valid(for draft: NFGeneratedPracticeDraft) -> Bool {
        version == 1 && draft.stage == 3 && draft.terminalState != nil
            && (1...512).contains(plannedQuestionCount)
            && draft.result.questions.count == draft.index + 1
            && draft.result.questions.count <= plannedQuestionCount
            && [originalResultDigest, originalRequestDigest].allSatisfy {
                $0.count == 64 && $0.allSatisfy { "0123456789abcdef".contains($0) }
            }
    }
}

extension NFGeneratedPracticeDraft {
    var plannedQuestionCount: Int { terminalInventory?.plannedQuestionCount ?? result.questions.count }

    /// Unknown/ambiguous historical terminal states are never normalized. Every
    /// retained question, exact response and sidecar remains byte-equivalent.
    func releasingUnneededTerminalInventory() throws -> Self {
        guard stage == 3, terminalState != nil, valid else {
            throw NFLocalSessionRepository.RepositoryError.corruptSnapshot
        }
        if terminalInventory != nil { return self }
        let metadata = NFGeneratedTerminalInventory(plannedQuestionCount: result.questions.count,
            originalResultDigest: try NFEditorialCanonicalData.digest(result),
            originalRequestDigest: try NFEditorialCanonicalData.digest(request))
        var retained = self
        let questions = Array(result.questions.prefix(index + 1))
        retained.result = .init(questions: questions, provenance: result.provenance,
            routeCandidates: result.routeCandidates, validationStatus: result.validationStatus,
            validationNotes: result.validationNotes)
        var chunkIDs: Set<String> = []
        var documentsWithoutChunkIdentity: Set<UUID> = []
        var hasUnresolvedGroundingReference = false
        for question in questions {
            let exercise = question.authoritativeExercise
            let provenance = exercise.provenance
            let context = exercise.sourceContext
            var questionChunks = Set(question.citationChunkIDs + provenance.sourceChunkIDs + context.sourceChunkIDs)
            questionChunks.formUnion(exercise.citations.compactMap(\.sourceChunkID))
            questionChunks.formUnion(exercise.citations.compactMap { citation in
                if case .chunk(let id) = citation.locator { return id }
                return nil
            })
            let knownCitationIDs = Set(exercise.citations.map(\.id))
            for id in context.groundingFacts.flatMap(\.citationIDs) where !knownCitationIDs.contains(id) {
                if request.sourceChunks.contains(where: { $0.id == id }) { questionChunks.insert(id) }
                else { hasUnresolvedGroundingReference = true }
            }
            chunkIDs.formUnion(questionChunks)
            let rawDocuments = provenance.sourceDocumentIDs + context.sourceDocumentIDs + exercise.citations.map(\.documentID)
            let documents = Set(rawDocuments.compactMap(UUID.init(uuidString:)))
            if rawDocuments.contains(where: { UUID(uuidString: $0) == nil }) { hasUnresolvedGroundingReference = true }
            let resolvedDocuments = Set(request.sourceChunks.filter { questionChunks.contains($0.id) }.map(\.documentID))
            // A legacy source contract may name only the document. Retain its
            // input excerpts rather than guessing which passage it depended on.
            documentsWithoutChunkIdentity.formUnion(documents.subtracting(resolvedDocuments))
            documentsWithoutChunkIdentity.formUnion(exercise.citations.filter { $0.sourceChunkID == nil }.compactMap { UUID(uuidString: $0.documentID) })
        }
        let retainedChunks = request.sourceChunks.filter {
            hasUnresolvedGroundingReference || chunkIDs.contains($0.id)
                || documentsWithoutChunkIdentity.contains($0.documentID)
        }
        retained.request.sourceChunks = retainedChunks
        retained.terminalInventory = metadata
        guard retained.valid else { throw NFLocalSessionRepository.RepositoryError.corruptSnapshot }
        return retained
    }

    /// Verify exact immutable inventory, including the only permitted shrinking
    /// transform, against the prior acknowledged payload. Digests alone never
    /// authorize arbitrary truncation, changed questions or source replacement.
    func preservesAcceptedInventory(from previous: Self) throws -> Bool {
        if let old = previous.terminalInventory {
            return try terminalInventory == old
                && NFImmutableAttemptRecordSnapshot.encoded(previous.result) == NFImmutableAttemptRecordSnapshot.encoded(result)
                && NFImmutableAttemptRecordSnapshot.encoded(previous.request) == NFImmutableAttemptRecordSnapshot.encoded(request)
        }
        if terminalInventory != nil {
            guard stage == 3, terminalState != nil else { return false }
            var original = self
            original.result = previous.result
            original.request = previous.request
            original.terminalInventory = nil
            let expected = try original.releasingUnneededTerminalInventory()
            return try terminalInventory == expected.terminalInventory
                && NFImmutableAttemptRecordSnapshot.encoded(expected.result) == NFImmutableAttemptRecordSnapshot.encoded(result)
                && NFImmutableAttemptRecordSnapshot.encoded(expected.request) == NFImmutableAttemptRecordSnapshot.encoded(request)
        }
        return try NFImmutableAttemptRecordSnapshot.encoded(previous.result) == NFImmutableAttemptRecordSnapshot.encoded(result)
            && NFImmutableAttemptRecordSnapshot.encoded(previous.request) == NFImmutableAttemptRecordSnapshot.encoded(request)
    }
}


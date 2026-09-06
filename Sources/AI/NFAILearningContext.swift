import Foundation

extension AppStore {
    /// Resolve the original source versions before offering a follow-up. A
    /// replaced excerpt must not silently become the basis of an old answer.
    func learningContext(exercise: NFExercise, response: NFExerciseResponse,
                         feedback: String, savedSources: [NFSourceChunk] = [],
                         attemptID: UUID? = nil) -> NFAITutorContext? {
        guard !exercise.assessmentProtected,
              exercise.evidenceClass != .assessmentHoldout,
              exercise.evidenceClass != .nearTransfer else { return nil }
        let sourceIDs = Set(exercise.provenance.sourceDocumentIDs.compactMap(UUID.init(uuidString:)))
        let matchingDocuments = documents.filter { sourceIDs.contains($0.id) }
        let savedRunID = attempts.first { $0.id == attemptID }?.sessionID
        let savedRun = localSessions.archive.privateStudyRuns?.first { $0.id == savedRunID }
            .flatMap { try? JSONDecoder().decode(NFGeneratedPracticeDraft.self, from: $0.payload) }
        let policies = matchingDocuments.map { DocumentAIPolicy(rawValue: $0.aiPolicyRaw) ?? .noAI }
            + (matchingDocuments.count < sourceIDs.count ? savedRun?.request.documentPolicies ?? [] : [])
        let ceiling: AIMode = policies.contains(.noAI) ? .disabled
            : (policies.contains(.onDeviceOnly) || matchingDocuments.count < sourceIDs.count ? .onDeviceOnly : .automatic)
        let available = savedSources.isEmpty ? matchingDocuments.flatMap { chunks(for: $0) } : savedSources
        let cited = available.filter { chunk in
            exercise.citations.contains {
                $0.sourceChunkID == chunk.id && UUID(uuidString: $0.documentID) == chunk.documentID
                    && $0.excerptDigest == chunk.contentHash
            }
        }
        return NFAITutorContext(prompt: exercise.prompt,
            learnerResponse: NFResponsePresentation.text(response, exercise: exercise),
            referenceAnswer: NFResponsePresentation.expectedAnswer(for: exercise),
            feedback: feedback, sourceExcerpts: cited,
            localeIdentifier: exercise.localeIdentifier, aiMode: profileSnapshot.aiMode,
            itemID: attemptID?.uuidString ?? exercise.id, allowedMode: ceiling,
            frozenContextID: (try? NFLocalItemCheckpoint.digest(exercise)).map {
                "attempt-context-v2|\(attemptID?.uuidString ?? exercise.id)|\($0)"
            })
    }
}

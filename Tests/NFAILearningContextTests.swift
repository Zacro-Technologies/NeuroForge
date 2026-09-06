import CryptoKit
import Foundation
import SwiftData
import XCTest
@testable import NeuroForge

@MainActor
final class NFAILearningContextTests: XCTestCase {
    func testSavedAttemptResolvesLowercaseDocumentCitationsAndRejectsChangedExcerpts() throws {
        let fixture = try makeFixture()
        defer { fixture.removeFiles() }
        let original = try context(fixture)

        XCTAssertEqual(fixture.exercise.citations.first?.documentID, fixture.document.id.uuidString.lowercased())
        XCTAssertEqual(original.sourceExcerpts, [fixture.chunk])
        XCTAssertEqual(original.itemID, fixture.attemptID.uuidString)
        XCTAssertTrue(try XCTUnwrap(original.frozenContextID).hasPrefix("attempt-context-v2|"))
        XCTAssertEqual(fixture.store.exerciseSnapshot(for: fixture.attemptID), fixture.exercise)

        let replacement = try XCTUnwrap(fixture.store.sourceChunks.first)
        replacement.text = "A different passage from a later source revision."
        replacement.contentHash = digest(replacement.text)
        replacement.documentVersion += 1
        try fixture.container.mainContext.save()
        fixture.store.reload()

        let history = try context(fixture)
        XCTAssertTrue(history.sourceExcerpts.isEmpty, "A matching chunk identifier cannot substitute changed source text.")
        XCTAssertEqual(try original.storageKey(), try history.storageKey())
        let retained = try context(fixture, savedSources: [fixture.chunk, replacement.snapshot])
        XCTAssertEqual(retained.sourceExcerpts, [fixture.chunk])
    }

    func testLiveAndHistoryReopenSavedExplanationAfterReviewAndSourceDeletion() async throws {
        let fixture = try makeFixture()
        defer { fixture.removeFiles() }
        let live = try context(fixture, feedback: "The response addresses the question.", savedSources: [fixture.chunk])
        let key = try live.storageKey()
        let turn = NFAITutorTurn(requestID: UUID(), question: "Explain the decisive step.",
            answer: "Apply the stated operation to the values in the question.",
            providerIdentifier: "synthetic-provider", modelIdentifier: "fixture-model",
            route: .local, generatedAt: Date(timeIntervalSince1970: 1_800_000_000))
        let writer = NFAITutorTranscriptStore(artifactDirectoryURL: fixture.store.localSessions.aiArtifactDirectoryURL)
        try await writer.save(.init(contextKey: key, turns: [turn]))

        for chunk in fixture.store.sourceChunks { fixture.container.mainContext.delete(chunk) }
        fixture.container.mainContext.delete(fixture.document)
        try fixture.container.mainContext.save()
        fixture.store.reload()
        let history = try context(fixture, feedback: "The reviewed feedback includes another explanation.")
        XCTAssertTrue(history.sourceExcerpts.isEmpty)
        XCTAssertEqual(history.allowedMode, .onDeviceOnly)
        XCTAssertEqual(try history.storageKey(), key)

        let reopened = NFAITutorTranscriptStore(artifactDirectoryURL: fixture.store.localSessions.aiArtifactDirectoryURL)
        let recovered = try await reopened.load(contextKey: history.storageKey())
        XCTAssertEqual(recovered?.turns, [turn])
        XCTAssertEqual(fixture.store.attempts.count, 1)
        XCTAssertEqual(fixture.store.exerciseSnapshot(for: fixture.attemptID), fixture.exercise)
    }

    func testCurrentDocumentPreferenceControlsRoutingAndOverridesTheFrozenRequestWhilePresent() throws {
        let fixture = try makeFixture()
        defer { fixture.removeFiles() }
        try saveGeneratedRequest(fixture, frozenPolicies: [.onDeviceOnly])
        fixture.store.updateAIMode(.automatic)
        XCTAssertEqual(try context(fixture).allowedMode, .automatic,
            "An explicit current source preference supersedes the generation-time preference.")

        XCTAssertTrue(fixture.store.updateDocumentAIPolicy(fixture.document, policy: .onDeviceOnly))
        let local = try context(fixture)
        XCTAssertEqual(local.allowedMode, .onDeviceOnly)
        XCTAssertEqual(NFAITutorModePolicy.resolve(requested: local.aiMode, allowed: local.allowedMode), .onDeviceOnly)

        XCTAssertTrue(fixture.store.updateDocumentAIPolicy(fixture.document, policy: .noAI))
        let disabled = try context(fixture)
        XCTAssertEqual(disabled.allowedMode, .disabled)
        for mode in AIMode.allCases {
            fixture.store.updateAIMode(mode)
            let updated = try context(fixture)
            XCTAssertEqual(NFAITutorModePolicy.resolve(requested: updated.aiMode, allowed: updated.allowedMode), .disabled)
        }
        XCTAssertTrue(fixture.store.updateDocumentAIPolicy(fixture.document, policy: .privateCloudAllowed))
        fixture.store.updateAIMode(.automatic)
        XCTAssertEqual(try context(fixture).allowedMode, .automatic)
    }

    func testMissingSourceUsesLocalCeilingAndRetainsStricterFrozenPreference() throws {
        let fixture = try makeFixture()
        defer { fixture.removeFiles() }
        try saveGeneratedRequest(fixture, frozenPolicies: [.noAI])
        XCTAssertEqual(try context(fixture).allowedMode, .automatic)
        fixture.container.mainContext.delete(fixture.document)
        try fixture.container.mainContext.save()
        fixture.store.reload()

        let missing = try context(fixture, savedSources: [fixture.chunk])
        XCTAssertEqual(missing.allowedMode, .disabled)
        XCTAssertEqual(missing.sourceExcerpts, [fixture.chunk])

        try fixture.store.localSessions.removePrivateStudyRun(id: fixture.sessionID)
        let withoutSavedPolicy = try context(fixture, savedSources: [fixture.chunk])
        XCTAssertEqual(withoutSavedPolicy.allowedMode, .onDeviceOnly)
        XCTAssertEqual(try missing.storageKey(), try withoutSavedPolicy.storageKey())
    }

    func testChangingProfileFromOnDeviceToAutomaticKeepsTheSavedConversation() async throws {
        let fixture = try makeFixture()
        defer { fixture.removeFiles() }
        fixture.store.updateAIMode(.onDeviceOnly)
        let local = try context(fixture)
        XCTAssertEqual(local.aiMode, .onDeviceOnly)
        let transcriptStore = NFAITutorTranscriptStore(artifactDirectoryURL: fixture.store.localSessions.aiArtifactDirectoryURL)
        let turn = NFAITutorTurn(requestID: UUID(), question: "Why this operation?",
            answer: "It follows from the relationship stated in the question.",
            providerIdentifier: "synthetic-provider", modelIdentifier: "fixture-model", route: .local, generatedAt: Date())
        try await transcriptStore.save(.init(contextKey: local.storageKey(), turns: [turn]))

        fixture.store.updateAIMode(.automatic)
        let automatic = try context(fixture)
        XCTAssertEqual(automatic.aiMode, .automatic)
        XCTAssertEqual(automatic.allowedMode, .automatic)
        XCTAssertEqual(try local.storageKey(), try automatic.storageKey())
        let recovered = try await transcriptStore.load(contextKey: automatic.storageKey())
        XCTAssertEqual(recovered?.turns, [turn])
    }

    func testProtectedAndTransferAssessmentContextsAreExcluded() throws {
        let fixture = try makeFixture()
        defer { fixture.removeFiles() }
        let protected = try changed(fixture.exercise) { $0["assessmentProtected"] = true }
        XCTAssertNil(fixture.store.learningContext(exercise: protected, response: fixture.response, feedback: ""))
        for evidence in [EvidenceClass.assessmentHoldout, .nearTransfer] {
            let assessment = try changed(fixture.exercise) { $0["evidenceClass"] = evidence.rawValue }
            XCTAssertNil(fixture.store.learningContext(exercise: assessment, response: fixture.response, feedback: ""))
        }
        XCTAssertNotNil(fixture.store.learningContext(exercise: fixture.exercise, response: fixture.response, feedback: ""))
    }

    func testChangedOriginalExerciseCitationManifestAnswerAndAttemptCannotReuseSavedIdentity() throws {
        let fixture = try makeFixture()
        defer { fixture.removeFiles() }
        let key = try context(fixture).storageKey()
        let changedPrompt = try changed(fixture.exercise) { $0["prompt"] = "A revised problem with the same item identifier." }
        let changedCitation = try changed(fixture.exercise) { json in
            var citations = try XCTUnwrap(json["citations"] as? [[String: Any]])
            citations[0]["excerptDigest"] = String(repeating: "f", count: 64)
            json["citations"] = citations
        }
        for exercise in [changedPrompt, changedCitation] {
            let revised = try XCTUnwrap(fixture.store.learningContext(exercise: exercise,
                response: fixture.response, feedback: "", attemptID: fixture.attemptID))
            XCTAssertNotEqual(try revised.storageKey(), key)
        }
        let anotherAnswer = try XCTUnwrap(fixture.store.learningContext(exercise: fixture.exercise,
            response: .numeric(.init(value: "-987654321", unit: nil)), feedback: "", attemptID: fixture.attemptID))
        XCTAssertNotEqual(try anotherAnswer.storageKey(), key)
        let anotherAttempt = try XCTUnwrap(fixture.store.learningContext(exercise: fixture.exercise,
            response: fixture.response, feedback: "", attemptID: UUID()))
        XCTAssertNotEqual(try anotherAttempt.storageKey(), key)
    }

    private struct Fixture {
        let root: URL
        let container: ModelContainer
        let store: AppStore
        let document: SourceDocumentRecord
        let chunk: NFSourceChunk
        let exercise: NFExercise
        let response: NFExerciseResponse
        let attemptID: UUID
        let sessionID: UUID

        func removeFiles() { try? FileManager.default.removeItem(at: root) }
    }

    private func makeFixture() throws -> Fixture {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("NFAILearningContextTests-\(UUID().uuidString)")
        let container = try ModelContainer(for: Schema(NFSchemaV1.models), configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        container.mainContext.insert(UserProfileRecord(draft: OnboardingDraft()))
        let document = SourceDocumentRecord(filename: "Synthetic notes.txt", typeIdentifier: "public.plain-text", sizeBytes: 0,
            localPath: root.appendingPathComponent("Documents/notes.txt").path)
        document.aiPolicyRaw = DocumentAIPolicy.privateCloudAllowed.rawValue
        let text = "Use the stated numerical relationship to calculate the requested value."
        let chunk = NFSourceChunk(id: "synthetic-source-chunk", documentID: document.id, documentVersion: 1,
            sourceName: document.filename, locator: .init(page: nil, lineStart: 1, lineEnd: 1, section: nil),
            text: text, contentHash: digest(text), ordinal: 0)
        container.mainContext.insert(document)
        container.mainContext.insert(SourceChunkRecord(chunk: chunk))
        try container.mainContext.save()
        let repository = NFLocalSessionRepository(url: root.appendingPathComponent("LocalLearning/history.json"))
        let store = AppStore(context: container.mainContext, documentStorageRootURL: root.appendingPathComponent("Documents"),
            localSessionRepository: repository,
            adaptivePlanHistoryRepository: NFAdaptivePlanHistoryRepository(fileURL: root.appendingPathComponent("PlanHistory.json")),
            temporaryArtifactsRootURL: root.appendingPathComponent("Temporary"), allowsSharedWidgetPublishing: false)
        let base = try NFFallbackExerciseGenerator.generate(.init(seed: 991, index: 0, lab: .mentalMath,
            purpose: .practice, localeIdentifier: "en", preferredAssessmentMechanicID: "fixture.fallback-variant-0"))
        let exercise = try changed(base) { json in
            json["evidenceClass"] = EvidenceClass.documentPractice.rawValue
            var provenance = try XCTUnwrap(json["provenance"] as? [String: Any])
            provenance["sourceDocumentIDs"] = [document.id.uuidString.lowercased()]
            provenance["sourceChunkIDs"] = [chunk.id]
            provenance["isSourceGrounded"] = true
            json["provenance"] = provenance
            let citation = NFExerciseCitation(id: "synthetic-citation", documentID: document.id.uuidString.lowercased(),
                sourceChunkID: chunk.id, title: document.filename, locator: .lines(start: 1, end: 1),
                supportDescription: "States the relevant numerical relationship.", excerptDigest: chunk.contentHash)
            json["citations"] = try JSONSerialization.jsonObject(with: JSONEncoder().encode([citation]))
        }
        guard case let .numeric(schema) = exercise.interaction else { throw NFLocalSessionRepository.RepositoryError.corruptSnapshot }
        let response = NFExerciseResponse.numeric(.init(value: String(schema.answer.value), unit: schema.answer.canonicalUnit))
        let attemptID = UUID(), sessionID = UUID()
        try store.saveExerciseAttempt(attemptID: attemptID, sessionID: sessionID, exercise: exercise,
            response: response, result: NFExerciseScoringEngine.score(response, for: exercise), confidence: .certain,
            shownAt: Date(timeIntervalSince1970: 1_800_000_000), activeDuration: 7, source: .focused)
        return Fixture(root: root, container: container, store: store, document: document, chunk: chunk,
            exercise: exercise, response: response, attemptID: attemptID, sessionID: sessionID)
    }

    private func context(_ fixture: Fixture, feedback: String = "Saved feedback.", savedSources: [NFSourceChunk] = []) throws -> NFAITutorContext {
        let attempt = try XCTUnwrap(fixture.store.attempts.first { $0.id == fixture.attemptID })
        let exercise = try XCTUnwrap(fixture.store.exerciseSnapshot(for: attempt.id))
        let response = try XCTUnwrap(NFResponsePresentation.decode(attempt.response))
        return try XCTUnwrap(fixture.store.learningContext(exercise: exercise, response: response,
            feedback: feedback, savedSources: savedSources, attemptID: attempt.id))
    }

    private func saveGeneratedRequest(_ fixture: Fixture, frozenPolicies: [DocumentAIPolicy]) throws {
        let request = NFAuthoringRequest(id: fixture.sessionID, capability: .contextualize, lab: .mentalMath,
            field: .general, customTopic: "Synthetic numerical relationship", learningObjective: "Apply the relationship",
            style: .numerical, difficulty: 0.3, count: 1, localeIdentifier: "en", seed: 991,
            sourceChunks: [fixture.chunk], documentPolicies: frozenPolicies, aiMode: .automatic)
        let question = NFAuthoredQuestion(id: fixture.exercise.id, lab: .mentalMath, style: .numerical,
            prompt: fixture.exercise.prompt, context: "Synthetic source context", choices: [],
            correctAnswer: NFResponsePresentation.text(fixture.response, exercise: fixture.exercise), acceptedAnswers: [],
            explanation: "Apply the stated relationship.", hint: "Identify the relevant operation.", decisiveStep: "Calculate the value.",
            difficulty: 0.3, citationChunkIDs: [fixture.chunk.id], evidenceClass: .documentPractice, authoritativeExercise: fixture.exercise)
        let result = NFAuthoringResult(questions: [question], provenance: .init(requestID: fixture.sessionID,
            generatedAt: Date(), route: .deterministicFallback, routeReason: "Synthetic saved request fixture",
            promptVersion: NFAuthoringRequest.promptVersion, modelIdentifier: "synthetic.fixture",
            sourceChunkIDs: [fixture.chunk.id], sourceDocumentIDs: [fixture.document.id],
            validationVersion: NFAuthoringEngine.validationVersion, repairCount: 0, cacheKey: fixture.sessionID.uuidString, isFallback: true),
            routeCandidates: [], validationStatus: .init(level: .deterministicKey, sourceSupport: .notApplicable), validationNotes: [])
        let draft = NFGeneratedPracticeDraft(id: fixture.sessionID, ownerDeviceID: fixture.store.localSessions.ownerDeviceID,
            result: result, request: request, index: 0, stage: 0, response: fixture.response,
            confidence: nil, referenceRevealed: false, hintRevealed: false, correctness: [], lastScore: nil,
            pendingAttemptID: fixture.attemptID, shownAt: Date(), activeDuration: 7)
        try fixture.store.localSessions.savePrivateStudyRun(id: fixture.sessionID, generationID: fixture.sessionID,
            payload: JSONEncoder().encode(draft))
    }

    private func changed(_ exercise: NFExercise, mutate: (inout [String: Any]) throws -> Void) throws -> NFExercise {
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(exercise)) as? [String: Any])
        try mutate(&json)
        return try JSONDecoder().decode(NFExercise.self, from: JSONSerialization.data(withJSONObject: json))
    }

    private func digest(_ text: String) -> String {
        SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}

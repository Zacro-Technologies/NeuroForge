import Foundation
import XCTest
@testable import NeuroForge

@MainActor
final class NFAILearningAuthoringTests: XCTestCase {
    func testTopicGenerationPinsSemanticRubricBeforeAnswering() async throws {
        let author = NFRecordingNativeAuthor()
        let result = try await service(author).author(request(count: 2))
        XCTAssertEqual(result.questions.count, 2)
        XCTAssertEqual(Set(result.questions.map(\.id)).count, 2)
        XCTAssertEqual(result.provenance.route, .onDevice)
        XCTAssertEqual(result.validationStatus.level, .rubricModelOutput)
        XCTAssertEqual(result.validationStatus.sourceSupport, .notApplicable)
        XCTAssertFalse(result.validationStatus.establishesFactualTruth)
        XCTAssertFalse(result.provenance.isFallback)
        for question in result.questions {
            XCTAssertTrue(question.hasValidResponseSchema)
            let exercise = question.authoritativeExercise
            XCTAssertEqual(exercise.schemaVersion, 14)
            XCTAssertEqual(exercise.evidenceClass, .documentPractice)
            XCTAssertEqual(exercise.provenance.contentTier, .freeFormAI)
            XCTAssertFalse(exercise.provenance.isSourceGrounded)
            XCTAssertEqual(exercise.aiRubric?.referenceAnswer, question.correctAnswer)
            XCTAssertEqual(exercise.aiRubric?.criteria.count, 2)
            XCTAssertTrue(exercise.rubric.permitsPartialCredit)
            XCTAssertFalse(exercise.assessmentProtected)
            guard case .shortText = exercise.interaction else { return XCTFail("Native short answers need semantic text grading.") }
            try NFExerciseSchemaValidator.validate(exercise)
        }
    }

    func testOptionalObjectiveUsesTopicAndSkillWithoutBlockingOrdinaryStudioRequest() async throws {
        let author = NFRecordingNativeAuthor()
        _ = try await service(author).author(request(objective: ""))
        let calls = await author.calls
        let input = try input(XCTUnwrap(calls.first).0)
        let objective = try XCTUnwrap(input["overallObjective"] as? String)
        XCTAssertTrue(objective.contains("osmosis"))
        XCTAssertTrue(objective.contains("explain and apply"))
    }

    func testExplicitObjectiveDifficultyAndLocaleReachGenerationUnchanged() async throws {
        let author = NFRecordingNativeAuthor()
        let request = request(objective: "Explain the direction of water movement.", locale: "ja-JP", difficulty: 0.81)
        let result = try await service(author).author(request)
        let calls = await author.calls
        let completion = try XCTUnwrap(calls.first?.0)
        let input = try input(completion)
        XCTAssertEqual(input["overallObjective"] as? String, request.learningObjective)
        XCTAssertTrue((input["difficultyGuidance"] as? String)?.contains("Expert") == true)
        XCTAssertEqual(completion.localeIdentifier, "ja-JP")
        XCTAssertEqual(completion.task, .generation)
        XCTAssertEqual(result.questions[0].difficulty, 0.81)
        XCTAssertEqual(result.questions[0].authoritativeExercise.aiRubric?.localeIdentifier, "ja-JP")
    }

    func testSourceGenerationRetainsExactSelectedChunkAndDigest() async throws {
        let author = NFRecordingNativeAuthor()
        let chunk = source()
        let result = try await service(author).author(request(chunks: [chunk], policies: [.privateCloudAllowed]))
        let question = try XCTUnwrap(result.questions.first)
        let exercise = question.authoritativeExercise
        XCTAssertEqual(question.citationChunkIDs, [chunk.id])
        XCTAssertEqual(exercise.provenance.contentTier, .sourceGroundedAI)
        XCTAssertTrue(exercise.provenance.isSourceGrounded)
        XCTAssertEqual(exercise.citations.first?.excerptDigest, chunk.contentHash)
        XCTAssertEqual(result.provenance.sourceDocumentIDs, [chunk.documentID])
        XCTAssertEqual(result.validationStatus.sourceSupport, .citationIdentifiersOnly)
        let calls = await author.calls
        let input = try input(XCTUnwrap(calls.first).0)
        let excerpt = try XCTUnwrap((input["excerpts"] as? [[String: Any]])?.first)
        XCTAssertEqual(excerpt["id"] as? String, chunk.id)
        XCTAssertEqual(excerpt["text"] as? String, chunk.text)
    }

    func testNativeSourceGenerationNeedsNoShortcutConsentOrBankGate() async throws {
        let author = NFRecordingNativeAuthor()
        let request = request(chunks: [source()], policies: [.privateCloudAllowed])
        XCTAssertNil(request.externalSourceConsent)
        XCTAssertFalse(request.allowsShortcutAuthoring)
        let result = try await service(author).author(request)
        XCTAssertEqual(result.questions.count, 1)
    }

    func testSourceOfflinePolicyOverridesAutomaticCloudPreference() async throws {
        let author = NFRecordingNativeAuthor()
        _ = try await service(author).author(request(mode: .automatic, chunks: [source()], policies: [.onDeviceOnly]))
        let modes = await author.calls.map(\.1)
        XCTAssertEqual(modes, [.onDeviceOnly])
    }

    func testMissingSourcePoliciesCannotBypassExplicitSourceSettings() async throws {
        let author = NFRecordingNativeAuthor()
        do {
            _ = try await service(author).author(request(chunks: [source()], policies: []))
            XCTFail("Missing source settings must not permit dispatch.")
        } catch { XCTAssertEqual(error as? NFAILearningAuthoringError, .invalidRequest) }
        let calls = await author.calls
        XCTAssertTrue(calls.isEmpty)
    }

    func testDisabledAndNoAIPoliciesPreventGeneration() async throws {
        let author = NFRecordingNativeAuthor()
        for request in [request(mode: .disabled), request(chunks: [source()], policies: [.noAI])] {
            do {
                _ = try await service(author).author(request)
                XCTFail("A disabled request reached the model.")
            } catch { XCTAssertTrue(error is NFAILearningAuthoringError || error is NFAILearningError) }
        }
        let calls = await author.calls
        XCTAssertTrue(calls.isEmpty)
    }

    func testNumericAndChoiceStylesNeverBecomeProseDisguisedAsExactKeys() async throws {
        let author = NFRecordingNativeAuthor()
        for style in [NFQuestionStyle.numerical, .multipleChoice, .proofOrDerivation] {
            do {
                _ = try await service(author).author(request(style: style))
                XCTFail("An unsupported response surface was silently changed.")
            } catch { XCTAssertEqual(error as? NFAILearningAuthoringError, .unsupportedStyle) }
        }
        let calls = await author.calls
        XCTAssertTrue(calls.isEmpty)
    }

    func testUncitedAndInventedSourceReferencesRejectTheWholeSet() async throws {
        for behavior in [NFRecordingNativeAuthor.Behavior.uncited, .inventedCitation] {
            do {
                _ = try await service(.init(behavior: behavior)).author(request(chunks: [source()], policies: [.privateCloudAllowed]))
                XCTFail("An unbound citation passed.")
            } catch { XCTAssertEqual(error as? NFAILearningAuthoringError, .invalidQuestion) }
        }
    }

    func testGenericRubricAndAnswerRevealingHintAreRejected() async throws {
        for behavior in [NFRecordingNativeAuthor.Behavior.genericRubric, .revealingHint] {
            do {
                _ = try await service(.init(behavior: behavior)).author(request())
                XCTFail("A weak rubric or answer-revealing hint passed.")
            } catch { XCTAssertEqual(error as? NFAILearningAuthoringError, .invalidQuestion) }
        }
    }

    func testDuplicateObjectivesOrPromptsNeverReturnAPartialSet() async throws {
        for behavior in [NFRecordingNativeAuthor.Behavior.duplicateObjective, .duplicatePrompt] {
            do {
                _ = try await service(.init(behavior: behavior)).author(request(count: 2))
                XCTFail("A repeated set passed.")
            } catch { XCTAssertEqual(error as? NFAILearningAuthoringError, .duplicateQuestions) }
        }
    }

    func testExtraGeneratedItemsCannotChangeRequestedCount() async throws {
        do {
            _ = try await service(.init(behavior: .wrongCount)).author(request())
            XCTFail("The model changed the item count.")
        } catch { XCTAssertEqual(error as? NFAILearningAuthoringError, .wrongCount) }
    }

    func testChangedProviderAndMismatchedCompletionIdentityAreRejected() async throws {
        for (behavior, expected) in [(NFRecordingNativeAuthor.Behavior.changedProvider, NFAILearningAuthoringError.inconsistentProvider),
                                     (.mismatchedID, .invalidQuestion)] {
            do {
                _ = try await service(.init(behavior: behavior)).author(request(count: 2))
                XCTFail("The model receipt did not match one consistent run.")
            } catch { XCTAssertEqual(error as? NFAILearningAuthoringError, expected) }
        }
    }

    func testCloudGenerationRecordsNativeCloudRouteAndModel() async throws {
        let result = try await service(.init(route: .cloud)).author(request(mode: .automatic))
        XCTAssertEqual(result.provenance.route, .directCloud)
        XCTAssertEqual(result.provenance.modelIdentifier, "native-test-model")
        XCTAssertEqual(result.questions.first?.authoritativeExercise.provenance.modelIdentifier, "native-test-model")
    }

    func testProgressCountsOnlyValidatedItemsAndGuidesDistinctSubsequentObjectives() async throws {
        let author = NFRecordingNativeAuthor()
        let progress = NFNativeAuthorProgressRecorder()
        let result = try await service(author).author(request(count: 3), onProgress: { await progress.record($0) })
        let values = await progress.values
        XCTAssertEqual(values.map(\.completedCount), [0, 1, 2, 3])
        XCTAssertEqual(values.map(\.totalCount), [3, 3, 3, 3])
        XCTAssertEqual(result.questions.count, 3)
        let calls = await author.calls
        let last = try input(XCTUnwrap(calls.last).0)
        XCTAssertEqual((last["previousObjectives"] as? [String])?.count, 2)
    }

    func testCancellationStopsGenerationWithoutReturningAPartialSet() async throws {
        let author = NFRecordingNativeAuthor(delay: .seconds(10))
        let service = service(author)
        let request = request(count: 3)
        let task = Task { try await service.author(request) }
        while await author.calls.isEmpty { await Task.yield() }
        task.cancel()
        do {
            _ = try await task.value
            XCTFail("Cancelled generation returned a set.")
        } catch { XCTAssertTrue(error is CancellationError) }
        let calls = await author.calls
        XCTAssertEqual(calls.count, 1)
    }

    func testWholeSetDeadlineGivesFewerItemsRetry() async throws {
        let author = NFRecordingNativeAuthor(delay: .seconds(10))
        do {
            _ = try await service(author, deadline: .milliseconds(20)).author(request(count: 3))
            XCTFail("The generation deadline did not apply.")
        } catch { XCTAssertEqual(error as? NFAILearningAuthoringError, .timedOut) }
        let calls = await author.calls
        XCTAssertEqual(calls.count, 1)
    }

    func testNewGenerationRetainsExactFrozenIdentityOnReplay() async throws {
        let service = service(.init())
        let request = request()
        let first = try await service.author(request)
        let second = try await service.author(request)
        XCTAssertNotEqual(first.questions.first?.id, second.questions.first?.id)
        let restored = try JSONDecoder().decode(NFAuthoringResult.self, from: JSONEncoder().encode(first))
        XCTAssertEqual(restored.questions, first.questions)
        XCTAssertEqual(restored.questions.first?.authoritativeExercise.aiRubric, first.questions.first?.authoritativeExercise.aiRubric)
    }

    func testSavedNativeTopicAndSourceSetsRecoverWithRubricsAfterEightDays() async throws {
        for request in [request(), request(chunks: [source()], policies: [.privateCloudAllowed])] {
            let result = try await service(.init()).author(request)
            let record = try AIGenerationRecord(request: request, result: result)
            let later = result.provenance.generatedAt.addingTimeInterval(8 * 24 * 60 * 60)
            let restored = try XCTUnwrap(record.recoverableResult(at: later))
            XCTAssertEqual(restored.questions, result.questions)
            XCTAssertTrue(restored.questions.allSatisfy(\.hasValidResponseSchema))
            XCTAssertEqual(restored.validationStatus.level, .rubricModelOutput)
            XCTAssertEqual(restored.questions.map { $0.authoritativeExercise.aiRubric },
                           result.questions.map { $0.authoritativeExercise.aiRubric })
        }
    }

    private func service(_ author: NFRecordingNativeAuthor, deadline: Duration = .seconds(120)) -> NFAILearningAuthoringService {
        .init(complete: { try await author.complete($0, mode: $1) }, availability: { mode in
            .init(isAvailable: mode != .disabled, route: .local, status: "Ready offline", localAvailable: true, cloudConfigured: false)
        }, deadline: deadline)
    }

    private func request(
        count: Int = 1, objective: String = "Explain water movement across a membrane.", locale: String = "en",
        difficulty: Double = 0.5, mode: AIMode = .onDeviceOnly, style: NFQuestionStyle = .shortAnswer,
        chunks: [NFSourceChunk] = [], policies: [DocumentAIPolicy] = []
    ) -> NFAuthoringRequest {
        .init(capability: chunks.isEmpty ? .contextualize : .sourceGroundedPractice,
              lab: .scientificReasoning, field: .lifeSciences, customTopic: "osmosis",
              learningObjective: objective, style: style, difficulty: difficulty, count: count,
              localeIdentifier: locale, seed: 42, sourceChunks: chunks, documentPolicies: policies, aiMode: mode)
    }

    private func source() -> NFSourceChunk {
        .init(id: "source-osmosis", documentID: UUID(), documentVersion: 1, sourceName: "Biology notes",
              locator: .init(page: 1, lineStart: nil, lineEnd: nil, section: nil),
              text: "Water moves across a selectively permeable membrane from higher water potential to lower water potential. Dissolved solutes lower water potential.",
              contentHash: "retained-source-digest", ordinal: 0)
    }

    private func input(_ request: NFAICompletionRequest) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: Data(request.input.utf8)) as? [String: Any])
    }
}

private actor NFNativeAuthorProgressRecorder {
    private(set) var values: [NFAILearningAuthoringProgress] = []
    func record(_ value: NFAILearningAuthoringProgress) { values.append(value) }
}

private actor NFRecordingNativeAuthor {
    enum Behavior: Sendable {
        case valid, uncited, inventedCitation, genericRubric, revealingHint, duplicateObjective, duplicatePrompt
        case wrongCount, changedProvider, mismatchedID
    }
    let behavior: Behavior
    let route: NFAILearningRoute
    let delay: Duration?
    private(set) var calls: [(NFAICompletionRequest, AIMode)] = []

    init(behavior: Behavior = .valid, route: NFAILearningRoute = .local, delay: Duration? = nil) {
        self.behavior = behavior; self.route = route; self.delay = delay
    }

    func complete(_ request: NFAICompletionRequest, mode: AIMode) async throws -> NFAICompletionResult {
        calls.append((request, mode))
        if let delay { try await Task.sleep(for: delay) }
        let input = try JSONSerialization.jsonObject(with: Data(request.input.utf8)) as! [String: Any]
        let index = input["itemNumber"] as? Int ?? 1
        let excerpts = input["excerpts"] as? [[String: String]] ?? []
        let reference = "Water moves toward the solution with lower water potential because dissolved solutes reduce its water potential."
        let criterion = "Identify the side with lower water potential from the stated solute difference."
        let question: [String: Any] = [
            "objective": "Explain membrane water movement in scenario \(behavior == .duplicateObjective ? 1 : index)",
            "question": "In membrane scenario \(behavior == .duplicatePrompt ? 1 : index), why does water move toward the side with more dissolved solute?",
            "context": "A selectively permeable membrane separates two solutions. Only water can cross, and one solution has more dissolved solute.",
            "referenceAnswer": reference,
            "rubric": behavior == .genericRubric ? ["The answer is correct and clear.", "Demonstrates understanding of the material."] : [criterion, "Explain that water moves from higher to lower water potential across the membrane."],
            "hint": behavior == .revealingHint ? reference : "Compare the water potential on each side before choosing a direction.",
            "explanation": "The added solute reduces water potential on one side. The resulting gradient drives net movement of water toward that side.",
            "citationIDs": behavior == .uncited ? [] : behavior == .inventedCitation ? ["unselected-chunk"] : excerpts.compactMap { $0["id"] }
        ]
        let data = try JSONSerialization.data(withJSONObject: ["questions": behavior == .wrongCount ? [question, question] : [question]])
        return .init(requestID: behavior == .mismatchedID ? UUID() : request.id, text: String(decoding: data, as: UTF8.self),
            providerIdentifier: behavior == .changedProvider && index > 1 ? "changed-provider" : "native-test-provider",
            modelIdentifier: "native-test-model", route: route, generatedAt: Date())
    }
}

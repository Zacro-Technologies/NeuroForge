import Foundation
import SwiftData
import XCTest
@testable import NeuroForge

final class ExperienceImprovementTests: XCTestCase {
    func testSourceChooserPreservesSelectionAcrossSearchPaginationAndPolicyExclusion() {
        let rows = (0..<45).map { index in
            NFAIStudioSourceChoice(id: UUID(), filename: "Source \(index)",
                status: "Ready", route: "Created on this device", exclusion: nil)
        }
        var selected = Set([rows[0].id, rows[44].id])
        let firstPage = Array(NFAIStudioSourceChooserProjection.matching(rows, query: "",
            selectedOnly: false, selectedIDs: selected).prefix(NFAIStudioSourceChooserProjection.pageSize))
        XCTAssertEqual(firstPage.count, 20)
        XCTAssertFalse(firstPage.contains { $0.id == rows[44].id })
        let search = NFAIStudioSourceChooserProjection.matching(rows, query: "sOuRcE 44",
            selectedOnly: false, selectedIDs: selected)
        XCTAssertEqual(search.map(\.id), [rows[44].id])
        XCTAssertEqual(selected.count, 2, "Searching/paging must not discard offscreen selections")
        selected = NFAIStudioSourceChooserProjection.toggling(rows[22], selectedIDs: selected)
        XCTAssertEqual(selected, Set([rows[0].id, rows[22].id, rows[44].id]))
        let excluded = NFAIStudioSourceChoice(id: rows[44].id, filename: "Source 44",
            status: "Unavailable", route: "", exclusion: "Policy changed")
        let changedRows = Array(rows.dropLast()) + [excluded]
        let review = NFAIStudioSourceChooserProjection.matching(changedRows, query: "",
            selectedOnly: true, selectedIDs: selected)
        XCTAssertEqual(review.count, 3)
        XCTAssertEqual(review.last?.exclusion, "Policy changed", "An excluded selected source remains reviewable")
        selected = NFAIStudioSourceChooserProjection.toggling(excluded, selectedIDs: selected)
        XCTAssertFalse(selected.contains(excluded.id), "The learner can remove an unavailable selected source")
        XCTAssertEqual(NFAIStudioSourceChooserProjection.toggling(excluded, selectedIDs: selected), selected,
            "A disabled source cannot be added through the selection adapter")
        XCTAssertEqual(selected, Set([rows[0].id, rows[22].id]))
    }

    @MainActor
    func testMalformedCurrentTypedHistoryShowsRecoveryWithoutExposingEnvelopeOrHidingLegacyText() {
        let raw = "{\"claimEvidence\":{\"unexpected-private-field\":\"retained-original\"}}"
        let attempt = AttemptRecord(sessionID: UUID(), lab: .logicDebugging, itemID: "malformed-current-history",
            prompt: "Choose evidence.", response: raw, correctAnswer: "", isCorrect: false,
            confidence: .uncertain, responseFormat: "claimEvidence")
        attempt.scoringVersion = 8
        let current = NFReadOnlyAttemptSnapshot(attempt: attempt)
        XCTAssertEqual(current.rawResponse, raw)
        XCTAssertFalse(current.response.contains("unexpected-private-field"))
        XCTAssertFalse(current.readableResponse(exercise: nil).contains("retained-original"))
        XCTAssertTrue(current.response.contains("retained for recovery"))
        XCTAssertEqual(attempt.response, raw)
        attempt.scoringVersion = 1
        let legacy = NFReadOnlyAttemptSnapshot(attempt: attempt)
        XCTAssertEqual(legacy.response, raw, "Older raw learner text must not be guessed to be a broken envelope")
        XCTAssertEqual(legacy.readableResponse(exercise: nil), raw)
    }

    @MainActor
    func testGeneratedConfidenceTracksSemanticAnswerAndSurvivesExactColdDraft() throws {
        let container = try ModelContainer(for: Schema(NFSchemaV1.models), configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let store = AppStore(context: container.mainContext, localSessionRepository: NFLocalSessionRepository(), allowsSharedWidgetPublishing: false)
        let (request, result) = generatedInteractionFixture()
        let runtime = AIGeneratedPracticeRuntime(result: result, request: request)
        XCTAssertTrue(runtime.checkpoint(store: store))
        runtime.numericValue = "2"
        runtime.chooseConfidence(.certain)
        let rawFingerprint = runtime.draftFingerprint
        runtime.numericValue = "2.0"
        runtime.invalidateConfidenceAfterEdit()
        XCTAssertEqual(runtime.confidence, .certain, "Equivalent decimal formatting preserves confirmed confidence")
        XCTAssertNotEqual(runtime.draftFingerprint, rawFingerprint, "Exact formatting edits must still trigger draft persistence")
        XCTAssertTrue(runtime.checkpoint(store: store))
        let invited = runtime.confidenceInvitation
        let draft = try XCTUnwrap(store.generatedPracticeDrafts.first)
        XCTAssertEqual(draft.response, .numeric(.init(value: "2.0", unit: nil)))
        runtime.releaseWriter()
        let resumed = AIGeneratedPracticeRuntime(result: result, request: request, draft: draft)
        XCTAssertTrue(resumed.restoreCheckpoint(store: store)); resumed.resume()
        XCTAssertEqual(resumed.confidence, .certain)
        XCTAssertEqual(resumed.confidenceInvitation, invited)
        resumed.numericValue = "3"
        XCTAssertTrue(resumed.checkpoint(store: store))
        XCTAssertNil(resumed.confidence, "Checkpoint commands also invalidate material edits without relying on UI observation")
        resumed.chooseConfidence(.certain)
        resumed.numericValue = "2"
        resumed.submit(store: store)
        XCTAssertEqual(resumed.stage, 2)
        XCTAssertEqual(store.attempts.count, 1)
        XCTAssertNil(store.attempts.first?.confidenceRaw)
        XCTAssertEqual(store.attempts.first?.deterministicCredit, 1)
        resumed.releaseWriter()
    }

    @MainActor
    func testGeneratedHintMustSaveBeforeDisclosureAndCollapseRetainsAssistance() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "NFGeneratedHint-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appending(path: "archive.json")
        let lock = root.appending(path: "archive.json.lock")
        let repository = NFLocalSessionRepository(url: url)
        let container = try ModelContainer(for: Schema(NFSchemaV1.models), configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let store = AppStore(context: container.mainContext, localSessionRepository: repository, allowsSharedWidgetPublishing: false)
        let (request, result) = generatedInteractionFixture()
        let runtime = AIGeneratedPracticeRuntime(result: result, request: request)
        XCTAssertTrue(runtime.checkpoint(store: store))
        let predecessor = try Data(contentsOf: url)
        try FileManager.default.removeItem(at: lock)
        try FileManager.default.createDirectory(at: lock, withIntermediateDirectories: false)
        runtime.toggleCoaching(store: store)
        XCTAssertFalse(runtime.showsCoaching)
        XCTAssertEqual(runtime.coachingHintCount, 0)
        XCTAssertNotNil(runtime.saveError)
        XCTAssertEqual(try Data(contentsOf: url), predecessor)
        try FileManager.default.removeItem(at: lock)
        runtime.toggleCoaching(store: store)
        XCTAssertTrue(runtime.showsCoaching)
        XCTAssertEqual(runtime.coachingHintCount, 1)
        runtime.toggleCoaching(store: store)
        XCTAssertFalse(runtime.showsCoaching)
        XCTAssertEqual(runtime.coachingHintCount, 1)
        let draft = try XCTUnwrap(store.generatedPracticeDrafts.first)
        XCTAssertTrue(draft.hintRevealed)
        XCTAssertEqual(draft.hintExpanded, false)
        runtime.releaseWriter()
        let resumed = AIGeneratedPracticeRuntime(result: result, request: request, draft: draft)
        XCTAssertTrue(resumed.restoreCheckpoint(store: store)); resumed.resume()
        XCTAssertFalse(resumed.showsCoaching)
        XCTAssertEqual(resumed.coachingHintCount, 1)
        resumed.numericValue = "2"
        resumed.submit(store: store)
        XCTAssertEqual(resumed.stage, 2)
        XCTAssertEqual(store.attempts.first?.hintCount, 1)
        resumed.releaseWriter()
    }

    private func generatedInteractionFixture() -> (NFAuthoringRequest, NFAuthoringResult) {
        let id = UUID()
        let request = NFAuthoringRequest(id: id, capability: .contextualize, lab: .quantitative,
            field: .general, customTopic: "Synthetic addition", learningObjective: "Add two integers",
            style: .numerical, difficulty: 0.3, count: 1, localeIdentifier: "en", seed: 347811, aiMode: .disabled)
        let question = NFAuthoredQuestion(id: "synthetic.interaction.addition", lab: .quantitative, style: .numerical,
            prompt: "What is 1 + 1?", context: "Synthetic addition", choices: [], correctAnswer: "2",
            acceptedAnswers: [], explanation: "One plus one is two.", hint: "Count the two units.",
            decisiveStep: "Add the two units.", difficulty: 0.3, citationChunkIDs: [], evidenceClass: .documentPractice)
        let result = NFAuthoringResult(questions: [question], provenance: .init(requestID: id,
            generatedAt: Date(timeIntervalSince1970: 1_788_523_200), route: .deterministicFallback,
            routeReason: "Synthetic interaction fixture", promptVersion: 1, modelIdentifier: "synthetic.fixture",
            sourceChunkIDs: [], sourceDocumentIDs: [], validationVersion: 1, repairCount: 0,
            cacheKey: "synthetic.interaction", isFallback: true), routeCandidates: [],
            validationStatus: .init(level: .deterministicKey, sourceSupport: .notApplicable), validationNotes: [])
        return (request, result)
    }

    @MainActor
    func testSeededShortTextUIFixtureHasPinnedClarificationAuthority() throws {
        #if DEBUG
        let suiteName = "NeuroForge.ShortTextUIFixture.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let rotation = NFOfflineQuestionRotation(store: NFUserDefaultsOfflineQuestionRotationStateStore(defaults: defaults))
        let activity = try XCTUnwrap(NFDefaultContentCatalog.activity(id: "nf.default.retrieval.precision-recall"))
        let proposal = try rotation.prepareReservation(profileID: NFUITestLaunchConfiguration.fixtureProfileID,
            lab: .retrieval, laneID: activity.mechanicID, itemCount: 5,
            bank: NFOfflineQuestionBank.rotationBank, loadedLedger: nil)
        func request(seed: UInt64) -> SessionRequest {
            let resolvedSeed = NFStableDeterminism.hash64("focused-launch|\(seed)|\(proposal.plan.id)|\(activity.mechanicID)")
            return SessionRequest(
                lab: .retrieval, source: .focused, seed: resolvedSeed, localeIdentifier: "en",
                field: .general, requestedItemCount: 5, isTimed: false, mechanicID: activity.mechanicID)
        }
        func fixture(seed: UInt64) -> NFExercise {
            NFDeterministicSessionExerciseFactory.makeExercise(request: request(seed: seed), index: 0, assessmentDescriptor: nil)
        }
        let input = "I am unsure about the relationship."
        func hasClarificationAuthority(_ exercise: NFExercise) -> Bool {
            guard case let .shortText(schema) = exercise.interaction,
                  let authority = schema.authority,
                  case .reviewedProse = authority else { return false }
            return NFExerciseScoringEngine.score(.shortText(input), for: exercise).outcome == .needsClarification
        }
        let exercise = fixture(seed: NFUITestLaunchConfiguration.shortTextFixtureSeed)
        guard hasClarificationAuthority(exercise) else {
            let candidate = (0..<128).map { UInt64(20260904 + $0) }.first { hasClarificationAuthority(fixture(seed: $0)) }
            XCTFail("Pinned short-text UI seed changed authority; review candidate seed \(candidate.map { String($0) } ?? "unavailable"). Do not broaden the installed assertion.")
            return
        }
        XCTAssertFalse(exercise.assessmentProtected)
        XCTAssertNil(exercise.availabilityReason)
        XCTAssertEqual(NFExerciseScoringEngine.score(.shortText(input), for: exercise).outcome, .needsClarification)
        let container = try ModelContainer(for: Schema(NFSchemaV1.models), configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let store = AppStore(context: container.mainContext, localSessionRepository: NFLocalSessionRepository(), allowsSharedWidgetPublishing: false)
        let runtime = NFUniversalSessionRuntime(request: request(seed: NFUITestLaunchConfiguration.shortTextFixtureSeed))
        XCTAssertTrue(runtime.checkpointDraft(store: store))
        runtime.shortText = input
        runtime.submitInline(store: store)
        XCTAssertNil(runtime.saveError)
        XCTAssertEqual(runtime.stage, .item)
        XCTAssertTrue(runtime.canEditDraft)
        XCTAssertNotNil(runtime.clarificationMessage)
        XCTAssertNil(runtime.lastResult)
        XCTAssertTrue(store.attempts.isEmpty)
        let saved = try XCTUnwrap(store.localSessions.archive.sessions.first)
        XCTAssertEqual(saved.checkpoint.clarificationMessage, runtime.clarificationMessage)
        var replay = saved.request
        replay.localSessionID = saved.id
        replay.localCheckpoint = saved.checkpoint
        let restored = NFUniversalSessionRuntime(request: replay)
        XCTAssertEqual(restored.shortText, input)
        XCTAssertEqual(restored.clarificationMessage, runtime.clarificationMessage)
        runtime.releaseWriter()
        #endif
    }

    func testAllEightHistoryResponseFamiliesKeepTypedValuesAndSavedLabels() throws {
        let options = [
            NFChoiceOption(id: "internal-a", text: "First visible option", accessibilityLabel: nil, distractorCode: nil),
            NFChoiceOption(id: "internal-b", text: "Second visible option", accessibilityLabel: nil, distractorCode: nil)
        ]
        let choice = try fixture(.singleChoice(.init(options: options, correctOptionID: "internal-b")))
        XCTAssertEqual(NFResponsePresentation.text(.singleChoice(optionID: "internal-b"), exercise: choice), "Second visible option")
        let multi = try fixture(.multipleChoice(.init(options: options, correctOptionIDs: ["internal-a", "internal-b"], minimumSelections: 1, maximumSelections: 2)))
        XCTAssertEqual(NFResponsePresentation.text(.multipleChoice(optionIDs: ["internal-b", "internal-a"]), exercise: multi), "First visible option\nSecond visible option")
        let order = try fixture(.orderedSteps(.init(steps: [.init(id: "step-a", text: "Inspect"), .init(id: "step-b", text: "Compare")], correctOrder: ["step-a", "step-b"])))
        XCTAssertEqual(NFResponsePresentation.text(.orderedSteps(stepIDs: ["step-b", "step-a"]), exercise: order), "1. Compare\n2. Inspect")
        XCTAssertEqual(NFResponsePresentation.text(.numeric(.init(value: "1/2", unit: "cm"))), "1/2 cm")
        XCTAssertEqual(NFResponsePresentation.text(.shortText("Original\nexact prose")), "Original\nexact prose")
        let selfCheck = NFResponsePresentation.text(.selfCheck(.init(rating: .partiallyMatched, reflection: "Original recall")))
        XCTAssertTrue(selfCheck.contains("Original recall"))
        XCTAssertFalse(selfCheck.contains("100%"))
        let claims = try fixture(.claimEvidence(.init(claims: [.init(id: "claim-a", text: "Claim name")], evidence: [.init(id: "evidence-b", text: "Evidence label", citationID: nil)], correctPairs: [.init(claimID: "claim-a", evidenceIDs: ["evidence-b"])])))
        XCTAssertEqual(NFResponsePresentation.text(.claimEvidence(.init(pairs: [.init(claimID: "claim-a", evidenceIDs: ["evidence-b"])])), exercise: claims), "Claim name\n• Evidence label")
        let logic = try fixture(.logicState(.init(initialState: ["x": "1"], expectedFinalState: ["x": "2"], acceptedEquivalentStates: [], ruleOptions: options, expectedViolatedRuleID: "internal-a")))
        XCTAssertEqual(NFResponsePresentation.text(.logicState(.init(finalState: ["x": "2"], violatedRuleID: "internal-a")), exercise: logic), "x: 2\nFirst visible option")
    }

    func testLegacyHistoryDoesNotExposeInternalChoiceIdentifiersOrCodableEnvelope() throws {
        for response in [NFExerciseResponse.singleChoice(optionID: "internal-a"), .multipleChoice(optionIDs: ["internal-a"]), .orderedSteps(stepIDs: ["step-a"]), .claimEvidence(.init(pairs: [.init(claimID: "claim-a", evidenceIDs: ["evidence-a"])]))] {
            let encoded = String(decoding: try JSONEncoder().encode(response), as: UTF8.self)
            let shown = NFResponsePresentation.text(encoded)
            for secret in ["internal-a", "step-a", "claim-a", "evidence-a", "_0", "optionID"] { XCTAssertFalse(shown.contains(secret)) }
        }
    }

    @MainActor
    func testImportedProtectedReceiptWithLegacyPracticeClassIsUngradedAndWithholdsKey() throws {
        let record = AttemptRecord(sessionID: UUID(), lab: .mentalMath, itemID: "legacy-protected-receipt",
            prompt: "Saved prompt", response: "17", correctAnswer: "PRIVATE KEY", isCorrect: false,
            confidence: .uncertain, evidenceClass: .practice, source: .baseline)
        record.errorCode = "protected_evaluator_unavailable"
        record.evidenceWeight = 0
        let snapshot = NFReadOnlyAttemptSnapshot(attempt: record)
        XCTAssertEqual(snapshot.source, .protectedAssessment)
        XCTAssertEqual(snapshot.result, .all, "Protected receipts cannot be inferred through Correct/Wrong filters.")
        XCTAssertEqual(snapshot.correctAnswer, "")
        XCTAssertEqual(snapshot.resultTitle, NFAppLocalization.localizedCatalogValue("Answer saved", locale: NFAppLocalization.preferredLocale))
        XCTAssertEqual(snapshot.rawResponse, "17")
        XCTAssertEqual(record.evidenceClassRaw, EvidenceClass.practice.rawValue)
        XCTAssertEqual(record.correctAnswerText, "PRIVATE KEY", "History rendering never rewrites the original receipt.")
        record.errorCode = nil
        record.response = String(decoding: try JSONEncoder().encode(NFExerciseResponse.selfCheck(.init(rating: .matched, reflection: "My recall"))), as: UTF8.self)
        record.responseFormatRaw = "selfCheck"
        let protectedSelfReport = NFReadOnlyAttemptSnapshot(attempt: record)
        XCTAssertEqual(protectedSelfReport.source, .protectedAssessment)
        XCTAssertNil(protectedSelfReport.selfCheckRating, "A protected source marker still withholds per-answer outcomes.")
        record.sessionSourceRaw = SessionSource.focused.rawValue
        let selfReport = NFReadOnlyAttemptSnapshot(attempt: record)
        XCTAssertEqual(selfReport.selfCheckRating, .matched)
        XCTAssertEqual(selfReport.result, .all, "Self-reported matches are excluded from objective Correct/Wrong filters.")
    }

    @MainActor
    func testSolutionRevealIsDistinctFromSkipAndRetainsTheOriginalTypedDraft() throws {
        let draft = NFExerciseResponse.numeric(.init(value: "17", unit: "cm"))
        let encoded = String(decoding: try JSONEncoder().encode(draft), as: UTF8.self)
        let record = AttemptRecord(sessionID: UUID(), lab: .mentalMath, itemID: "revealed-practice",
            prompt: "Saved prompt", response: encoded, correctAnswer: "24 cm", isCorrect: false,
            confidence: .guessing, evidenceClass: .practice, source: .focused)
        record.confidenceRaw = nil
        record.responseFormatRaw = "revealed"
        record.errorCode = "solution_revealed"
        record.wasSkipped = true // Compatibility exclusion does not define the visible outcome.
        let snapshot = NFReadOnlyAttemptSnapshot(attempt: record)
        XCTAssertEqual(snapshot.result, .revealed)
        XCTAssertNotEqual(snapshot.result, .skipped)
        XCTAssertFalse(snapshot.hasObjectiveResult)
        XCTAssertTrue(snapshot.usedSupport)
        XCTAssertEqual(snapshot.response, "17 cm")
        XCTAssertEqual(snapshot.rawResponse, encoded)
        XCTAssertEqual(record.response, encoded)
    }

    @MainActor
    func testCalibrationDropsHistoricallyMisgradedSelfCheckWithoutChangingItsOriginalConfidence() throws {
        let container = try ModelContainer(for: Schema(NFSchemaV1.models), configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let store = AppStore(context: container.mainContext, localSessionRepository: NFLocalSessionRepository())
        let raw = String(decoding: try JSONEncoder().encode(NFExerciseResponse.selfCheck(.init(rating: .matched, reflection: "My original recall"))), as: UTF8.self)
        let record = AttemptRecord(sessionID: UUID(), lab: .retrieval, itemID: "historical-self-check",
            prompt: "Recall a concept", response: raw, correctAnswer: "Reference", isCorrect: true,
            confidence: .certain, evidenceClass: .practice, source: .focused)
        record.responseFormatRaw = "selfCheck"
        record.deterministicCredit = 1
        record.evidenceWeight = 1
        container.mainContext.insert(record)
        try container.mainContext.save()
        store.reload()
        let legacy = NFHistoryCalibrationSummary(attempts: [record.dto])
        XCTAssertEqual(legacy.eligibleCount, 1)
        XCTAssertEqual(legacy.matchingCount, 1)
        try store.reconcileHistoricalAuthority()
        let shown = NFHistoryCalibrationSummary(attempts: [store.effectiveAttemptDTO(record)])
        XCTAssertEqual(shown.eligibleCount, 0)
        XCTAssertNil(shown.fraction)
        XCTAssertEqual(record.confidenceRaw, ConfidenceLevel.certain.rawValue)
        XCTAssertTrue(record.isCorrect)
        XCTAssertEqual(record.deterministicCredit, 1)
        XCTAssertEqual(record.response, raw)
    }

    @MainActor
    func testDestinationPathsRemainIndependentAndReselectionOnlyPopsSelectedPath() throws {
        let navigation = NFNavigationState()
        let documentID = UUID(), attemptID = UUID()
        navigation.practice = [.lab(.quantitative), .activity("ratio")]
        navigation.sources = [.document(documentID, chunkID: "source-section")]
        navigation.progress = [.skill(.quantitative), .history(.quantitative), .attempt(attemptID)]
        navigation.returnToRoot(.library)
        XCTAssertTrue(navigation.sources.isEmpty)
        XCTAssertEqual(navigation.practice.count, 2)
        XCTAssertEqual(navigation.progress.count, 3)
        navigation.prune(documentIDs: [], attemptIDs: [])
        XCTAssertEqual(navigation.progress, [.skill(.quantitative), .history(.quantitative)])
        XCTAssertEqual(try JSONDecoder().decode([NFPracticeRoute].self, from: JSONEncoder().encode(navigation.practice)), navigation.practice)
        let cold = NFNavigationState()
        XCTAssertTrue(cold.today.isEmpty && cold.practice.isEmpty && cold.progress.isEmpty && cold.sources.isEmpty && cold.settings.isEmpty)
    }

    func testScratchpadRoundTripRetainsOpaqueDrawingAndExactNotes() throws {
        let drawing = Data([0, 1, 2, 255, 41, 19])
        let original = NFScratchpadPayload(notes: "Line one\nLine two 日本語", drawingData: drawing)
        var edited = NFScratchpadPayload.decode(original.storedValue)
        edited.notes += "\nA keyboard edit"
        let reopened = NFScratchpadPayload.decode(edited.storedValue)
        XCTAssertEqual(reopened.drawingData, drawing)
        XCTAssertEqual(reopened.notes, "Line one\nLine two 日本語\nA keyboard edit")
    }

    @MainActor
    func testPrivateOrganizationRoundTripsWithoutBecomingAStudyRunOrMutatingHistory() throws {
        let container = try ModelContainer(for: Schema(NFSchemaV1.models), configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let repository = NFLocalSessionRepository()
        let store = AppStore(context: container.mainContext, localSessionRepository: repository)
        let attemptID = UUID(), sourceID = UUID(), setID = UUID()
        var annotation = NFStudyAnnotation(id: attemptID)
        annotation.note = "My separate note 日本語"
        annotation.bookmarked = true
        try store.saveStudyAnnotation(annotation)
        var collection = NFStudyCollection(title: "Exam revision")
        collection.sourceIDs = [sourceID]
        collection.savedSetIDs = [setID]
        try store.saveStudyCollection(collection)
        annotation.bookmarked = false
        try store.saveStudyAnnotation(annotation)
        XCTAssertEqual(store.privateStudyMetadata.annotations, [annotation])
        XCTAssertEqual(store.privateStudyMetadata.collections, [collection])
        XCTAssertEqual(repository.archive.privateStudyRuns?.count, 1)
        XCTAssertTrue(store.generatedPracticeDrafts.isEmpty)
        XCTAssertTrue(store.attempts.isEmpty)
        let exported = try JSONEncoder().encode(repository.archive)
        let decoded = try JSONDecoder().decode(NFLocalSessionRepository.Archive.self, from: exported)
        let restored = try JSONDecoder().decode(NFPrivateStudyMetadata.self, from: XCTUnwrap(decoded.privateStudyRuns?.first).payload)
        XCTAssertEqual(restored, store.privateStudyMetadata)
        var changed = restored
        changed.collections[0].savedSetIDs.remove(setID)
        try store.savePrivateStudyMetadata(changed)
        XCTAssertEqual(store.privateStudyMetadata.collections[0].sourceIDs, [sourceID])
        XCTAssertEqual(store.privateStudyMetadata.annotations[0].note, annotation.note)
    }

    @MainActor
    func testNewerPrivateMetadataIsNeverOverwrittenByAnOlderEditor() throws {
        let container = try ModelContainer(for: Schema(NFSchemaV1.models), configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let repository = NFLocalSessionRepository()
        let store = AppStore(context: container.mainContext, localSessionRepository: repository)
        let unknown = Data("{\"schemaVersion\":200,\"privateNewField\":\"preserve me\"}".utf8)
        try repository.savePrivateStudyRun(id: NFPrivateStudyMetadata.recordID, generationID: NFPrivateStudyMetadata.recordID, payload: unknown)
        XCTAssertThrowsError(try store.saveStudyAnnotation(.init(id: UUID())))
        XCTAssertEqual(repository.archive.privateStudyRuns?.first?.payload, unknown)
    }

    @MainActor
    func testReportedSavedSetCannotCommitAndEndingReleasesOnlyItsRun() async throws {
        let container = try ModelContainer(for: Schema(NFSchemaV1.models), configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let store = AppStore(context: container.mainContext, localSessionRepository: NFLocalSessionRepository())
        let request = NFAuthoringRequest(capability: .contextualize, lab: .logicDebugging, field: .computing, customTopic: "trace", learningObjective: "trace state", style: .multipleChoice, difficulty: 0.5, count: 2, seed: 701, aiMode: .disabled)
        let result = try await NFAuthoringEngine.shared.author(request)
        let runtime = AIGeneratedPracticeRuntime(result: result, request: request)
        guard case .singleChoice(let schema) = runtime.exercise.interaction else { return XCTFail("Expected choice") }
        runtime.singleChoiceID = schema.correctOptionID
        XCTAssertTrue(runtime.checkpoint(store: store))
        try store.saveItemReport(question: runtime.question, result: result, reason: "Prompt is ambiguous", note: "")
        runtime.submit(store: store)
        XCTAssertNotNil(runtime.saveError)
        XCTAssertTrue(store.attempts.isEmpty)
        XCTAssertEqual(runtime.stage, 0)
        XCTAssertNotNil(store.generatedPracticeDraft(for: result.provenance.requestID))
        runtime.endSession(store: store)
        XCTAssertEqual(runtime.stage, 3)
        XCTAssertNil(store.generatedPracticeDraft(for: result.provenance.requestID))
        XCTAssertEqual(store.itemReports.count, 1)
    }

    @MainActor
    func testGeneratedDraftRestoresExactContentInputConfidenceAndReadOnlyOwnership() async throws {
        let container = try ModelContainer(for: Schema(NFSchemaV1.models), configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let repository = NFLocalSessionRepository()
        let store = AppStore(context: container.mainContext, localSessionRepository: repository)
        let request = NFAuthoringRequest(capability: .contextualize, lab: .logicDebugging, field: .computing, customTopic: "exact saved example", learningObjective: "trace a state", style: .multipleChoice, difficulty: 0.5, count: 2, seed: 723, aiMode: .disabled)
        let result = try await NFAuthoringEngine.shared.author(request)
        let runtime = AIGeneratedPracticeRuntime(result: result, request: request)
        guard case .singleChoice(let schema) = runtime.exercise.interaction else { return XCTFail("Expected the authored multiple-choice route") }
        runtime.singleChoiceID = schema.options.last?.id
        runtime.confidence = .uncertain
        XCTAssertTrue(runtime.checkpoint(store: store))
        let draft = try XCTUnwrap(store.generatedPracticeDraft(for: result.provenance.requestID))
        runtime.releaseWriter()
        let restored = AIGeneratedPracticeRuntime(result: result, request: request, draft: draft)
        XCTAssertTrue(restored.restoreCheckpoint(store: store)); restored.resume()
        XCTAssertEqual(restored.exercise, runtime.exercise)
        XCTAssertEqual(restored.singleChoiceID, runtime.singleChoiceID)
        XCTAssertEqual(restored.confidence, .uncertain)
        XCTAssertEqual(restored.stage, 0)
        restored.releaseWriter()
        let otherRepository = NFLocalSessionRepository(ownerDeviceID: UUID())
        let otherStore = AppStore(context: container.mainContext, localSessionRepository: otherRepository)
        let recovery = AIGeneratedPracticeRuntime(result: result, request: request, draft: draft)
        XCTAssertTrue(recovery.restoreCheckpoint(store: otherStore)); recovery.resume()
        XCTAssertTrue(recovery.isReadOnlyRecovery)
        recovery.submit(store: otherStore)
        XCTAssertTrue(otherStore.attempts.isEmpty)
        XCTAssertEqual(recovery.stage, 0)
    }

    @MainActor
    func testSourceReviewPinsExactPrivateExcerptAndNeutralAttemptAcrossReload() throws {
        let container = try ModelContainer(for: Schema(NFSchemaV1.models), configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let repository = NFLocalSessionRepository()
        let store = AppStore(context: container.mainContext, localSessionRepository: repository)
        let chunk = sourceFixture()
        let sessionID = UUID(), slotID = UUID(), attemptID = UUID()
        let request = try NFSourceReviewExactAdapter.makeRequest(chunk: chunk, localeIdentifier: "en",
            sessionID: sessionID, slotID: slotID, attemptID: attemptID)
        let exercise = try XCTUnwrap(request.localCheckpoint?.exercise)
        try NFExerciseSchemaValidator.validate(exercise)
        XCTAssertEqual(request.localCheckpoint?.slotID, slotID)
        XCTAssertEqual(request.localCheckpoint?.attemptID, attemptID)
        XCTAssertEqual(exercise.citations.first?.excerptDigest, chunk.contentHash)
        XCTAssertEqual(exercise.provenance.sourceDocumentIDs, [chunk.documentID.uuidString])
        XCTAssertFalse(exercise.prompt.contains(chunk.text))
        XCTAssertFalse(exercise.instructions.contains(chunk.text))
        XCTAssertFalse(exercise.independentContextText?.contains(chunk.text) == true)
        XCTAssertTrue(exercise.feedback.hintLadder.isEmpty)
        let runtime = NFUniversalSessionRuntime(request: request)
        XCTAssertTrue(runtime.checkpointDraft(store: store))
        runtime.selfCheckReflection = "My original recall before seeing the excerpt."
        XCTAssertTrue(runtime.checkpointDraft(store: store))
        XCTAssertTrue(store.sessionCheckpoints.isEmpty, "Private source drafts must not enter the SwiftData checkpoint path")
        let saved = try XCTUnwrap(repository.archive.sessions.first)
        runtime.releaseWriter()
        // The source can be reindexed or edited independently; replay accepts no
        // current chunk argument and must retain the original exact reference.
        let changed = sourceFixture(documentID: chunk.documentID, text: "Completely changed source.")
        let freshChanged = try NFSourceReviewExactAdapter.makeRequest(chunk: changed, localeIdentifier: "en")
        XCTAssertNotEqual(freshChanged.localCheckpoint?.exercise, exercise)
        let replay = try NFSourceReviewExactAdapter.resumeRequest(saved, ownerDeviceID: repository.ownerDeviceID)
        let restored = NFUniversalSessionRuntime(request: replay)
        XCTAssertEqual(restored.exercise, exercise)
        XCTAssertEqual(restored.selfCheckReflection, runtime.selfCheckReflection)
        XCTAssertTrue(restored.checkpointDraft(store: store))
        restored.resume()
        restored.submitInline(store: store)
        XCTAssertTrue(restored.selfCheckReferenceRevealed)
        XCTAssertEqual(restored.stage, .selfCheckComparison)
        guard case let .selfCheck(schema) = restored.exercise.interaction else { return XCTFail("Expected private self-check") }
        XCTAssertEqual(schema.referenceAnswer, chunk.text)
        restored.selfCheckRating = .notYet
        restored.saveSelfCheck(store: store)
        restored.saveSelfCheck(store: store)
        XCTAssertNil(restored.saveError)
        XCTAssertEqual(restored.stage, .feedback)
        XCTAssertEqual(store.attempts.count, 1)
        let attempt = try XCTUnwrap(store.attempts.first)
        XCTAssertEqual(attempt.id, attemptID)
        XCTAssertEqual(attempt.evidenceWeight, 0)
        XCTAssertNil(attempt.confidenceRaw)
        XCTAssertEqual(attempt.responseFormatRaw, "selfCheck")
        XCTAssertEqual(attempt.correctAnswerText, "", "The private reference belongs only in the local exact snapshot")
        XCTAssertEqual(attempt.sourceDocumentIDsRaw, chunk.documentID.uuidString)
        XCTAssertEqual(NFSourceReviewRotation.reviewedChunkIDs(from: store.attempts), [chunk.id])
        XCTAssertEqual(store.exerciseSnapshot(for: attemptID), exercise)
        XCTAssertTrue(store.sessionCheckpoints.isEmpty)
        restored.releaseWriter()
        try repository.removeReferences(attemptIDs: [attemptID], sourceID: chunk.documentID)
        XCTAssertTrue(repository.archive.sessions.isEmpty)
        XCTAssertTrue(repository.archive.snapshots.isEmpty)
    }

    @MainActor
    func testSourceReferenceRevealFailureRetainsHiddenReferenceAndOriginalDraft() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "NFSourceReveal-\(UUID())")
        let backup = folder.appendingPathExtension("backup")
        defer {
            try? FileManager.default.removeItem(at: folder)
            try? FileManager.default.removeItem(at: backup)
        }
        let repository = NFLocalSessionRepository(url: folder.appending(path: "session.json"))
        let container = try ModelContainer(for: Schema(NFSchemaV1.models), configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let store = AppStore(context: container.mainContext, localSessionRepository: repository)
        let request = try NFSourceReviewExactAdapter.makeRequest(chunk: sourceFixture(), localeIdentifier: "en")
        let runtime = NFUniversalSessionRuntime(request: request)
        XCTAssertTrue(runtime.checkpointDraft(store: store))
        runtime.selfCheckReflection = "A private unfinished answer."
        XCTAssertTrue(runtime.checkpointDraft(store: store))
        let original = try XCTUnwrap(repository.archive.sessions.first)
        // Block the actual local replacement after a successful durable draft.
        try FileManager.default.moveItem(at: folder, to: backup)
        try Data("not a directory".utf8).write(to: folder)
        runtime.submitInline(store: store)
        XCTAssertFalse(runtime.selfCheckReferenceRevealed)
        XCTAssertEqual(runtime.stage, .confidence)
        XCTAssertNotNil(runtime.saveError)
        XCTAssertEqual(runtime.selfCheckReflection, "A private unfinished answer.")
        XCTAssertTrue(store.attempts.isEmpty)
        let stillSaved = try XCTUnwrap(repository.archive.sessions.first)
        XCTAssertFalse(stillSaved.checkpoint.referenceRevealed)
        XCTAssertEqual(stillSaved.checkpoint.response, original.checkpoint.response)
        XCTAssertEqual(stillSaved.checkpoint.exercise, original.checkpoint.exercise)
        try FileManager.default.removeItem(at: folder)
        try FileManager.default.moveItem(at: backup, to: folder)
        runtime.retrySaving(store: store)
        XCTAssertTrue(runtime.selfCheckReferenceRevealed)
        XCTAssertEqual(runtime.stage, .selfCheckComparison)
        runtime.releaseWriter()
    }

    @MainActor
    func testSourceReplayRejectsForeignOwnerAndUnverifiedSnapshotWithoutChangingOriginal() throws {
        let request = try NFSourceReviewExactAdapter.makeRequest(chunk: sourceFixture(), localeIdentifier: "en")
        let checkpoint = try XCTUnwrap(request.localCheckpoint)
        let owner = UUID()
        var run = NFLocalSessionEnvelope(id: request.id, ownerDeviceID: owner, revision: 1,
            request: request.launchOnly(), checkpoint: checkpoint, status: .suspended, updatedAt: Date())
        XCTAssertThrowsError(try NFSourceReviewExactAdapter.resumeRequest(run, ownerDeviceID: UUID()))
        run.status = .migrationRecovery
        run.checkpoint.response = .selfCheck(.init(rating: .notYet, reflection: "Original migrated recall"))
        XCTAssertThrowsError(try NFSourceReviewExactAdapter.resumeRequest(run, ownerDeviceID: owner))
        XCTAssertEqual(NFSourceReviewExactAdapter.recoveryResponse(run.checkpoint.response), "Original migrated recall")
        run.status = .suspended
        run.checkpoint.exerciseDigest = "unverified"
        XCTAssertThrowsError(try NFSourceReviewExactAdapter.resumeRequest(run, ownerDeviceID: owner))
        XCTAssertEqual(run.checkpoint.exercise, checkpoint.exercise)
        run.checkpoint.exercise = nil
        XCTAssertThrowsError(try NFSourceReviewExactAdapter.resumeRequest(run, ownerDeviceID: owner))
        XCTAssertTrue(NFSourceReviewExactAdapter.legacyRecoveryReason.contains("did not save its original excerpt"))
    }

    private func sourceFixture(documentID: UUID = UUID(), text: String = "Photosynthesis stores light energy in chemical bonds.") -> NFSourceChunk {
        NFSourceChunk(id: "source-fixture-chunk", documentID: documentID, documentVersion: 1,
            sourceName: "Private study source.txt", locator: .init(page: nil, lineStart: 1, lineEnd: 1, section: nil),
            text: text, contentHash: "fixture-\(text)", ordinal: 0, language: "en")
    }

    private func fixture(_ interaction: NFExerciseInteraction) throws -> NFExercise {
        let exercise = try NFFallbackExerciseGenerator.generate(.init(seed: 700, index: 0, lab: .mentalMath, purpose: .practice))
        let encoder = JSONEncoder()
        var payload = try XCTUnwrap(JSONSerialization.jsonObject(with: encoder.encode(exercise)) as? [String: Any])
        payload["interaction"] = try JSONSerialization.jsonObject(with: encoder.encode(interaction))
        return try JSONDecoder().decode(NFExercise.self, from: JSONSerialization.data(withJSONObject: payload))
    }
}

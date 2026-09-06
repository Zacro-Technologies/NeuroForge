import Foundation
import SwiftData
import XCTest
#if os(iOS)
import PencilKit
import UIKit
#elseif os(macOS)
import AppKit
#endif
@testable import NeuroForge

@MainActor
final class LocalLearningLifecycleTests: XCTestCase {
    func testFirstPracticeIsExplicitAndUsesFiveUntimedQuestions() throws {
        let container = try ModelContainer(for: Schema(NFSchemaV1.models), configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let store = AppStore(context: container.mainContext, localSessionRepository: NFLocalSessionRepository())
        let draft = OnboardingDraft()
        XCTAssertEqual(draft.dailyDuration, 5)
        XCTAssertEqual(draft.timingMode, .untimed)
        XCTAssertTrue(store.completeOnboarding(draft, startPractice: true))
        let request = try XCTUnwrap(store.activeSessionRequest)
        XCTAssertEqual(request.requestedItemCount, 5)
        XCTAssertEqual(request.isTimed, false)
        XCTAssertEqual(request.evidenceClass, .practice)
        XCTAssertNil(request.assessmentBlock)
    }

    func testRemovingReusableSetRetainsAcceptedDraftAndRemovesCollectionMembership() async throws {
        let container = try ModelContainer(for: Schema(NFSchemaV1.models), configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let store = AppStore(context: container.mainContext, localSessionRepository: NFLocalSessionRepository())
        let request = NFAuthoringRequest(capability: .contextualize, lab: .logicDebugging,
            field: .computing, customTopic: "private test", learningObjective: "trace state",
            style: .multipleChoice, difficulty: 0.5, count: 2, seed: 724, aiMode: .disabled)
        let result = try await NFAuthoringEngine.shared.author(request)
        try store.saveAIGeneration(request: request, result: result)
        try store.localSessions.saveSet(result, at: Date())
        let runtime = AIGeneratedPracticeRuntime(result: result, request: request)
        defer { runtime.releaseWriter() }
        XCTAssertTrue(runtime.checkpoint(store: store))
        var collection = NFStudyCollection(title: "Private study")
        collection.savedSetIDs = [result.provenance.requestID]
        try store.saveStudyCollection(collection)
        try store.discardAIGenerationPayload(id: result.provenance.requestID)
        XCTAssertNil(store.recoverAIGeneration(id: result.provenance.requestID))
        XCTAssertNotNil(store.generatedPracticeDraft(for: result.provenance.requestID))
        XCTAssertTrue(store.privateStudyMetadata.collections[0].savedSetIDs.isEmpty)
        XCTAssertEqual(store.aiGenerations.count, 1, "Lightweight provenance survives reusable inventory deletion")
        XCTAssertTrue(store.attempts.isEmpty)
    }

    func testLinkedReferenceDeletionRemovesOnlySelectedAnnotationsAndSnapshots() throws {
        let container = try ModelContainer(for: Schema(NFSchemaV1.models), configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let store = AppStore(context: container.mainContext, localSessionRepository: NFLocalSessionRepository())
        let first = UUID(), retained = UUID(), source = UUID(), removedSet = UUID(), retainedSet = UUID()
        let exercise = try NFFallbackExerciseGenerator.generate(.init(seed: 700, index: 0, lab: .mentalMath, purpose: .practice))
        try store.localSessions.retainSnapshot(attemptID: first, exercise: exercise)
        try store.localSessions.retainSnapshot(attemptID: retained, exercise: exercise)
        try store.saveStudyAnnotation(NFStudyAnnotation(id: first, note: "remove", bookmarked: true))
        try store.saveStudyAnnotation(NFStudyAnnotation(id: retained, note: "keep", bookmarked: true))
        var collection = NFStudyCollection(title: "Keep collection")
        collection.sourceIDs = [source]
        collection.savedSetIDs = [removedSet, retainedSet]
        try store.saveStudyCollection(collection)
        try store.localSessions.removeReferences(attemptIDs: [first], generationIDs: [removedSet], sourceID: source)
        XCTAssertEqual(store.localSessions.archive.snapshots.map(\.attemptID), [retained])
        XCTAssertEqual(store.privateStudyMetadata.annotations.map(\.id), [retained])
        XCTAssertTrue(store.privateStudyMetadata.collections[0].sourceIDs.isEmpty)
        XCTAssertEqual(store.privateStudyMetadata.collections[0].savedSetIDs, [retainedSet])
        XCTAssertEqual(store.privateStudyMetadata.collections[0].title, "Keep collection")
    }

    func testUnrecognizedOrganizationSchemaPreventsDestructivePartialCleanup() throws {
        let repository = NFLocalSessionRepository()
        let bytes = Data(#"{"schemaVersion":999,"annotations":[],"collections":[],"favoriteActivities":[],"recentActivityIDs":[]}"#.utf8)
        try repository.savePrivateStudyRun(id: NFPrivateStudyMetadata.recordID,
            generationID: NFPrivateStudyMetadata.recordID, payload: bytes)
        XCTAssertThrowsError(try repository.unsaveSet(UUID()))
        XCTAssertEqual(repository.archive.privateStudyRuns?.first?.payload, bytes)
    }
}

/// Real local conflict durability, separate from the lifecycle's pure callbacks.
@MainActor
final class AttemptConflictJournalTests: XCTestCase {
    private func store(repository: NFLocalSessionRepository? = nil) throws -> (AppStore, ModelContainer) {
        let container = try ModelContainer(for: Schema(NFSchemaV1.models), configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        return (AppStore(context: container.mainContext, localSessionRepository: repository ?? NFLocalSessionRepository(), allowsSharedWidgetPublishing: false), container)
    }

    private func exercise() throws -> NFExercise {
        try NFFallbackExerciseGenerator.generate(.init(seed: 991, index: 0, lab: .mentalMath, purpose: .practice,
            localeIdentifier: "en", preferredAssessmentMechanicID: "fixture.fallback-variant-0"))
    }

    private func correctResponse(_ exercise: NFExercise) throws -> NFExerciseResponse {
        guard case let .numeric(schema) = exercise.interaction else { throw NFLocalSessionRepository.RepositoryError.corruptSnapshot }
        return .numeric(.init(value: String(schema.answer.value), unit: schema.answer.canonicalUnit))
    }

    private func save(_ store: AppStore, id: UUID, session: UUID, exercise: NFExercise,
                      response: NFExerciseResponse, hintCount: Int = 0) throws {
        try store.saveExerciseAttempt(attemptID: id, sessionID: session, exercise: exercise,
            response: response, result: NFExerciseScoringEngine.score(response, for: exercise), confidence: .certain,
            shownAt: Date(timeIntervalSince1970: 1_800_000_000), activeDuration: 7,
            source: .focused, hintCount: hintCount)
    }

    func testConflictingRawPayloadsSurviveReplayWithoutReplacingOriginalOrAwardingXP() throws {
        let (source, container) = try store()
        let item = try exercise(), id = UUID(), session = UUID()
        let correct = try correctResponse(item)
        try save(source, id: id, session: session, exercise: item, response: correct)
        let original = try XCTUnwrap(source.attempts.first)
        original.response = "\n" + original.response + "\n"
        try container.mainContext.save()
        let originalBytes = original.response, originalDate = original.submittedAt
        let xp = source.forgeProgress.totalXP
        let proposal = NFExerciseResponse.numeric(.init(value: "-987654321", unit: nil))
        for _ in 0..<3 { XCTAssertThrowsError(try save(source, id: id, session: session, exercise: item, response: proposal)) }
        let entry = try XCTUnwrap(source.localSessions.archive.attemptConflicts?.first)
        XCTAssertEqual(source.localSessions.archive.attemptConflicts?.count, 1)
        XCTAssertEqual(entry.original.response, originalBytes)
        XCTAssertEqual(NFResponsePresentation.decode(entry.proposed.response), proposal)
        XCTAssertEqual(entry.originalExercise, item)
        XCTAssertEqual(entry.proposedExercise, item)
        XCTAssertTrue(entry.originalSnapshotVerified)
        XCTAssertNoThrow(try entry.validate())
        XCTAssertEqual(source.attempts.count, 1)
        XCTAssertEqual(source.forgeProgress.totalXP, xp)
        XCTAssertEqual(original.response, originalBytes)
        XCTAssertEqual(original.submittedAt, originalDate)
        XCTAssertTrue(original.isCorrect)
        XCTAssertEqual(source.effectiveAttemptDTO(original).evidenceWeight, 0)
        XCTAssertNil(source.effectiveAttemptDTO(original).confidence)
        XCTAssertTrue(source.pendingAttemptRecords.isEmpty)
        XCTAssertTrue(source.pendingAttemptConflicts.isEmpty)
        // A matching retry still acknowledges only the original receipt.
        try save(source, id: id, session: session, exercise: item, response: correct)
        XCTAssertEqual(source.localSessions.archive.attemptConflicts?.count, 1)
        XCTAssertEqual(original.response, originalBytes)
        // A distinct coaching history is a second conflict, not an equal retry.
        XCTAssertThrowsError(try save(source, id: id, session: session, exercise: item, response: correct, hintCount: 1))
        XCTAssertEqual(source.localSessions.archive.attemptConflicts?.count, 2)
        XCTAssertEqual(original.hintCount, 0)
    }

    func testRejectedRetryCannotAttachItsQuestionAsMissingOriginalSnapshot() throws {
        let (source, container) = try store(); defer { _ = container }
        let item = try exercise(), id = UUID(), session = UUID()
        try save(source, id: id, session: session, exercise: item, response: correctResponse(item))
        var predecessor = source.localSessions.archive
        predecessor.snapshots = []
        try source.localSessions.restorePredecessor(predecessor)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(item)) as? [String: Any])
        object["prompt"] = "A competing proposed question with the same identity"
        let competing = try JSONDecoder().decode(NFExercise.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertThrowsError(try save(source, id: id, session: session, exercise: competing, response: correctResponse(competing)))
        XCTAssertTrue(source.localSessions.archive.snapshots.isEmpty)
        let entry = try XCTUnwrap(source.localSessions.archive.attemptConflicts?.first)
        XCTAssertNil(entry.originalExercise)
        XCTAssertNil(entry.originalExerciseDigest)
        XCTAssertFalse(entry.originalSnapshotVerified)
        XCTAssertEqual(entry.original.prompt, item.prompt)
        XCTAssertEqual(entry.proposedExercise, competing)
        XCTAssertEqual(source.attempts.first?.prompt, item.prompt)
    }

    func testFailedJournalWriteRetainsSeparateProposalAndRetriesWithoutAnotherAttempt() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "NFConflictFailure-\(UUID())")
        let backup = root.appendingPathExtension("original")
        defer { try? FileManager.default.removeItem(at: root); try? FileManager.default.removeItem(at: backup) }
        let repository = NFLocalSessionRepository(url: root.appending(path: "local.json"))
        let (source, container) = try store(repository: repository); defer { _ = container }
        let item = try exercise(), id = UUID(), session = UUID()
        try save(source, id: id, session: session, exercise: item, response: correctResponse(item))
        let original = try XCTUnwrap(source.attempts.first), bytes = original.response
        let xp = source.forgeProgress.totalXP
        try FileManager.default.moveItem(at: root, to: backup)
        try Data("blocked publication directory".utf8).write(to: root)
        let proposal = NFExerciseResponse.numeric(.init(value: "-987654321", unit: nil))
        XCTAssertThrowsError(try save(source, id: id, session: session, exercise: item, response: proposal))
        XCTAssertEqual(source.pendingAttemptConflicts.count, 1)
        XCTAssertEqual(NFResponsePresentation.decode(source.pendingAttemptConflicts[0].proposed.response), proposal)
        XCTAssertTrue(source.pendingAttemptRecords.isEmpty)
        XCTAssertEqual(source.unsavedAttemptCount, 1)
        XCTAssertEqual(source.effectiveAttemptDTO(original).evidenceWeight, 0)
        XCTAssertNil(repository.archive.attemptConflicts)
        XCTAssertEqual(original.response, bytes)
        try FileManager.default.removeItem(at: root)
        try FileManager.default.moveItem(at: backup, to: root)
        source.retryPendingWrites()
        XCTAssertTrue(source.pendingAttemptConflicts.isEmpty)
        XCTAssertEqual(repository.archive.attemptConflicts?.count, 1)
        XCTAssertEqual(source.attempts.count, 1)
        XCTAssertEqual(source.forgeProgress.totalXP, xp)
        let reopened = NFLocalSessionRepository(url: root.appending(path: "local.json"), ownerDeviceID: repository.ownerDeviceID)
        XCTAssertNil(reopened.loadError)
        XCTAssertEqual(reopened.archive.attemptConflicts, repository.archive.attemptConflicts)
        try reopened.removeReferences(attemptIDs: [id])
        XCTAssertTrue(reopened.archive.attemptConflicts?.isEmpty == true)
    }

    func testConflictImportChecksRawDigestsAndNeverMaterializesProposalAsAnAttempt() throws {
        let (source, container) = try store(); defer { _ = container }
        let item = try exercise(), id = UUID(), session = UUID()
        try save(source, id: id, session: session, exercise: item, response: correctResponse(item))
        let documentID = UUID()
        let rawSourceIDs = "legacy-personal-document, \(documentID.uuidString.lowercased()) "
        let original = try XCTUnwrap(source.attempts.first)
        original.sourceDocumentIDsRaw = rawSourceIDs
        try container.mainContext.save()
        XCTAssertThrowsError(try save(source, id: id, session: session, exercise: item,
            response: .numeric(.init(value: "-987654321", unit: nil))))
        let archive = source.localSessions.exportArchive
        let destination = NFLocalSessionRepository()
        try destination.importArchive(archive)
        try destination.importArchive(archive)
        XCTAssertEqual(destination.archive.attemptConflicts?.count, 1)
        let (importedStore, importedContainer) = try store(repository: destination); defer { _ = importedContainer }
        XCTAssertTrue(importedStore.attempts.isEmpty, "Recovery payloads must not be inserted as earned attempts")
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(archive)) as? [String: Any])
        var entries = try XCTUnwrap(object["attemptConflicts"] as? [[String: Any]])
        var proposed = try XCTUnwrap(entries[0]["proposed"] as? [String: Any])
        proposed["response"] = "a tampered raw proposal"
        entries[0]["proposed"] = proposed
        object["attemptConflicts"] = entries
        let tampered = try JSONDecoder().decode(NFLocalSessionRepository.Archive.self, from: JSONSerialization.data(withJSONObject: object))
        let retained = destination.archive.attemptConflicts
        XCTAssertThrowsError(try destination.importArchive(tampered))
        XCTAssertEqual(destination.archive.attemptConflicts, retained)
        entries[0]["schemaVersion"] = 999
        object["attemptConflicts"] = entries
        let future = try JSONDecoder().decode(NFLocalSessionRepository.Archive.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertThrowsError(try destination.importArchive(future))
        XCTAssertEqual(destination.archive.attemptConflicts, retained)
        XCTAssertEqual(destination.archive.attemptConflicts?.first?.original.sourceDocumentIDsRaw, rawSourceIDs)
        try destination.removeReferences(attemptIDs: [], sourceID: documentID)
        XCTAssertTrue(destination.archive.attemptConflicts?.isEmpty == true,
            "Imported lowercase UUID provenance matches by identity for deletion without rewriting raw evidence")
        XCTAssertEqual(original.sourceDocumentIDsRaw, rawSourceIDs)
    }

    func testProtectedConflictDiagnosticsStayLocalAndPortableExportContainsOnlyReference() throws {
        let (source, container) = try store()
        let id = UUID(), session = UUID()
        let original = AttemptRecord(sessionID: session, lab: .mentalMath, itemID: "protected-conflict-fixture",
            prompt: "Retained protected prompt", response: "original raw response", correctAnswer: "PRIVATE-CONFLICT-KEY-ORIGINAL",
            isCorrect: true, confidence: .certain, evidenceClass: .assessmentHoldout, source: .baseline)
        original.id = id
        let proposal = AttemptRecord(sessionID: session, lab: .mentalMath, itemID: original.itemID,
            prompt: original.prompt, response: "competing raw response", correctAnswer: "PRIVATE-CONFLICT-KEY-PROPOSED",
            isCorrect: false, confidence: .certain, evidenceClass: .assessmentHoldout, source: .baseline)
        proposal.id = id
        container.mainContext.insert(original)
        try container.mainContext.save()
        source.reload()
        let entry = try NFAttemptConflictJournalEntry(original: NFImmutableAttemptRecordSnapshot(original),
            proposed: NFImmutableAttemptRecordSnapshot(proposal), originalExercise: nil, proposedExercise: nil, proposedScore: nil)
        try source.localSessions.appendAttemptConflict(entry)
        XCTAssertEqual(source.localSessions.archive.attemptConflicts?.first?.proposed.correctAnswerText, "PRIVATE-CONFLICT-KEY-PROPOSED")
        let portable = source.localSessions.exportArchive
        XCTAssertTrue(portable.attemptConflicts?.isEmpty == true)
        XCTAssertEqual(portable.withheldProtectedConflictAttemptIDs, [id])
        XCTAssertThrowsError(try NFLocalSessionRepository().importArchive(source.localSessions.archive))
        let urls = try NFDataExportService.makeExports(from: source)
        defer { if let folder = urls.first?.deletingLastPathComponent() { try? FileManager.default.removeItem(at: folder) } }
        let exported = try String(contentsOf: XCTUnwrap(urls.first { $0.pathExtension == "json" && $0.lastPathComponent.contains("Full-Archive") }), encoding: .utf8)
        XCTAssertFalse(exported.contains("PRIVATE-CONFLICT-KEY-ORIGINAL"))
        XCTAssertFalse(exported.contains("PRIVATE-CONFLICT-KEY-PROPOSED"))
        XCTAssertTrue(exported.contains("withheldProtectedConflictAttemptIDs"))
        XCTAssertEqual(source.attempts.count, 1)
        XCTAssertEqual(source.effectiveAttemptDTO(original).evidenceWeight, 0)
    }
}


@MainActor
final class ScratchpadSafetyTests: XCTestCase {
    func testContextLayoutUsesAvailableWidthAndAccessibilityFallback() {
        for width: CGFloat in [320, 599, 600, 899] {
            XCTAssertFalse(NFScratchpadLayoutPolicy.usesSplitPane(availableWidth: width, accessibilityType: false, hasContext: true))
        }
        for width: CGFloat in [900, 1024, 1400] {
            XCTAssertTrue(NFScratchpadLayoutPolicy.usesSplitPane(availableWidth: width, accessibilityType: false, hasContext: true))
            XCTAssertFalse(NFScratchpadLayoutPolicy.usesSplitPane(availableWidth: width, accessibilityType: true, hasContext: true))
            XCTAssertFalse(NFScratchpadLayoutPolicy.usesSplitPane(availableWidth: width, accessibilityType: false, hasContext: false))
        }
        XCTAssertFalse(NFScratchpadLayoutPolicy.usesSplitPane(availableWidth: .infinity, accessibilityType: false, hasContext: true))
        XCTAssertFalse(NFScratchpadLayoutPolicy.usesSplitPane(availableWidth: .nan, accessibilityType: false, hasContext: true))
        XCTAssertEqual(NFScratchpadLayoutPolicy.expandedContextHeight(availableHeight: 600), 252)
        XCTAssertEqual(NFScratchpadLayoutPolicy.expandedContextHeight(availableHeight: 2000), 320)
        XCTAssertTrue(NFScratchpadLayoutPolicy.expandedContextHeight(availableHeight: .infinity).isFinite)
    }

    func testScratchpadContextIncludesOnlyExactIndependentGivensEvenForProtectedExercise() throws {
        let base = try NFFallbackExerciseGenerator.generate(.init(seed: 617, index: 0, lab: .logicDebugging,
            purpose: .practice, localeIdentifier: "en", preferredAssessmentMechanicID: "fixture.fallback-variant-0"))
        let given = NFExerciseRepresentation.table(headers: ["Input", "Output"], rows: [["2", "6"]], accessibilitySummary: "The original observations")
        let hint = NFExerciseRepresentation.code(language: "text", source: "SCRATCHPAD_HINT_CANARY", accessibilitySummary: "Hidden hint")
        let worked = NFExerciseRepresentation.equation(latex: "SCRATCHPAD_WORKED_CANARY", spokenDescription: "Hidden worked answer")
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoder.encode(base)) as? [String: Any])
        object["contextText"] = "SCRATCHPAD_REFERENCE_CANARY"
        object["assessmentProtected"] = true
        object["representations"] = try JSONSerialization.jsonObject(with: encoder.encode([given, hint, worked]))
        var metadata = try XCTUnwrap(object["contractMetadata"] as? [String: Any])
        metadata["contextRole"] = NFInstructionalRole.postResponseReference.rawValue
        metadata["representationRoles"] = [NFInstructionalRole.essentialGiven.rawValue,
            NFInstructionalRole.optionalPracticeHint.rawValue, NFInstructionalRole.workedExample.rawValue]
        object["contractMetadata"] = metadata
        let exercise = try JSONDecoder().decode(NFExercise.self, from: JSONSerialization.data(withJSONObject: object))
        let original = try encoder.encode(exercise)
        let context = NFScratchpadExerciseContext.make(exercise: exercise)
        XCTAssertEqual(context.prompt, exercise.prompt)
        XCTAssertEqual(context.instructions, exercise.instructions)
        XCTAssertEqual(context.representations, [given])
        XCTAssertNil(context.contextText)
        XCTAssertTrue(context.initialLogicState.isEmpty)
        for canary in ["SCRATCHPAD_HINT_CANARY", "SCRATCHPAD_WORKED_CANARY", "SCRATCHPAD_REFERENCE_CANARY"] {
            XCTAssertFalse(String(reflecting: context).contains(canary))
        }
        XCTAssertEqual(try encoder.encode(exercise), original)
        metadata["representationRoles"] = [NFInstructionalRole.essentialGiven.rawValue]
        object["contractMetadata"] = metadata
        let malformedRoles = try JSONDecoder().decode(NFExercise.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertTrue(NFScratchpadExerciseContext.make(exercise: malformedRoles).representations.isEmpty)
    }

    func testScratchpadContextPreservesInitialLogicStateAndNeverUsesSelfCheckReference() throws {
        let exercise = try NFFallbackExerciseGenerator.generate(.init(seed: 617, index: 0, lab: .logicDebugging,
            purpose: .practice, localeIdentifier: "en", preferredAssessmentMechanicID: "fixture.fallback-variant-0"))
        guard case .logicState(let schema) = exercise.interaction else { return XCTFail("Authentic logic fixture required") }
        let context = NFScratchpadExerciseContext.make(exercise: exercise)
        XCTAssertEqual(context.initialLogicState, schema.initialState)
        XCTAssertNotEqual(context.initialLogicState, schema.expectedFinalState)
        XCTAssertEqual(context.representations, exercise.independentRepresentations)
        let excerpt = "The unrevealed reference explains why the amber pendulum returns to its resting position."
        let chunk = NFSourceChunk(id: "scratchpad.source", documentID: UUID(), documentVersion: 2,
            sourceName: "Original notes", locator: .init(page: nil, lineStart: nil, lineEnd: nil, section: nil),
            text: excerpt, contentHash: String(AdaptiveEngine.fnv1a64(excerpt), radix: 16), ordinal: 0)
        let request = try NFSourceReviewExactAdapter.makeRequest(chunk: chunk, localeIdentifier: "en")
        let sourceExercise = try XCTUnwrap(request.localCheckpoint?.exercise)
        XCTAssertFalse(String(reflecting: NFScratchpadExerciseContext.make(exercise: sourceExercise)).contains(excerpt))
    }

    func testNativeNotesClearUndoAndRedoPreserveUninterpretedDrawingAndSavedWork() throws {
        let payload = NFScratchpadPayload(notes: "Original notes\n日本語", drawingData: Data([255, 0, 99, 17]))
        let originalStored = payload.storedValue
        let inspection = NFScratchpadInspection.inspect(originalStored)
        var stored = inspection.originalStoredValue
        let view = NFScratchpadNativeNotesView()
        #if os(iOS)
        view.text = payload.notes
        #elseif os(macOS)
        view.string = payload.notes
        view.allowsUndo = true
        #endif
        view.onTextChanged = { notes in
            stored = inspection.accepting(.init(notes: notes, drawingData: payload.drawingData)) ?? stored
        }
        let manager = try XCTUnwrap(view.undoManager)
        defer { manager.removeAllActions() }
        manager.groupsByEvent = false
        let controls = NFScratchpadEditingController()
        controls.attach(manager: manager, clear: { view.replaceAllUndoably(with: "") })
        XCTAssertFalse(controls.canUndo)
        manager.beginUndoGrouping(); controls.clear(); manager.endUndoGrouping(); controls.refresh()
        XCTAssertEqual(NFScratchpadInspection.inspect(stored).payload?.notes, "")
        XCTAssertTrue(controls.canUndo)
        controls.undo()
        XCTAssertEqual(NFScratchpadInspection.inspect(stored).payload, payload)
        XCTAssertTrue(controls.canRedo)
        controls.redo()
        XCTAssertEqual(NFScratchpadInspection.inspect(stored).payload?.notes, "")
        XCTAssertEqual(NFScratchpadInspection.inspect(stored).payload?.drawingData, payload.drawingData)
        controls.undo()
        XCTAssertEqual(NFScratchpadInspection.inspect(stored).payload, payload)
        XCTAssertEqual(inspection.originalStoredValue, originalStored)
    }

    func testLegacyAndSupportedScratchpadRemainEditableWithoutLosingDrawingBytes() throws {
        let legacy = "Carry 1.\n日本語 notes"
        let plain = NFScratchpadInspection.inspect(legacy)
        XCTAssertTrue(plain.canEdit)
        XCTAssertEqual(plain.payload?.notes, legacy)
        let payload = NFScratchpadPayload(notes: legacy, drawingData: Data([0, 1, 2, 255]))
        let originalStored = payload.storedValue
        let inspected = NFScratchpadInspection.inspect(originalStored)
        XCTAssertTrue(inspected.canEdit, "Envelope inspection does not guess whether platform drawing bytes are valid")
        XCTAssertEqual(inspected.payload, payload)
        var changed = try XCTUnwrap(inspected.payload)
        changed.notes += "\nCorrection"
        let saved = try XCTUnwrap(inspected.accepting(changed))
        XCTAssertEqual(NFScratchpadInspection.inspect(saved).payload?.drawingData, payload.drawingData)
        XCTAssertEqual(inspected.originalStoredValue, originalStored)
    }

    func testMalformedAndFutureEnvelopesRetainExactRawValueAndCannotAcceptEdits() throws {
        let values = [
            NFScratchpadPayload.prefix + "not base64!\n",
            NFScratchpadPayload.prefix + Data(#"{"notes":false,"drawingData":""}"#.utf8).base64EncodedString(),
            "neuroforge-scratchpad-v999:" + Data("future-private-original\n日本語".utf8).base64EncodedString()
        ]
        for raw in values {
            let inspected = NFScratchpadInspection.inspect(raw)
            XCTAssertFalse(inspected.canEdit)
            XCTAssertNotNil(inspected.unavailableReason)
            XCTAssertNil(inspected.payload)
            XCTAssertNil(inspected.accepting(.init(notes: "replacement", drawingData: Data())))
            XCTAssertEqual(inspected.originalStoredValue, raw)
        }
        XCTAssertEqual(NFScratchpadInspection.inspect(values[2]).unavailableReason, .unsupportedVersion)
    }

    func testEncodedAndDecodedSizeBoundariesRefuseBeforeDrawingInterpretation() throws {
        let payload = NFScratchpadPayload(notes: "A", drawingData: Data([1, 2, 3, 4]))
        let stored = payload.storedValue
        let decodedCount = try JSONEncoder().encode(payload).count
        let exact = NFScratchpadDecodeLimits(maximumDecodedBytes: decodedCount,
            maximumDrawingBytes: 4, maximumStoredBytes: stored.utf8.count)
        XCTAssertTrue(NFScratchpadInspection.inspect(stored, limits: exact).canEdit)
        var tooSmall = exact
        tooSmall.maximumStoredBytes -= 1
        XCTAssertEqual(NFScratchpadInspection.inspect(stored, limits: tooSmall).unavailableReason, .oversized)
        tooSmall = exact; tooSmall.maximumDecodedBytes -= 1
        XCTAssertEqual(NFScratchpadInspection.inspect(stored, limits: tooSmall).unavailableReason, .oversized)
        tooSmall = exact; tooSmall.maximumDrawingBytes -= 1
        let rejected = NFScratchpadInspection.inspect(stored, limits: tooSmall)
        XCTAssertEqual(rejected.unavailableReason, .oversized)
        XCTAssertEqual(rejected.originalStoredValue, stored)
        XCTAssertNil(rejected.payload)
        XCTAssertNil(rejected.accepting(.init(notes: "", drawingData: Data())))
        let previouslyValid = NFScratchpadInspection.inspect("A")
        XCTAssertNil(previouslyValid.accepting(payload, limits: tooSmall))
        XCTAssertEqual(previouslyValid.originalStoredValue, "A")
    }

    func testPreviewPlanCapsBothPixelDimensionsAndRefusesUnsafeGeometry() throws {
        let ordinary = try XCTUnwrap(NFScratchpadGeometryPolicy.previewPlan(for: CGRect(x: 10, y: 20, width: 200, height: 80)))
        XCTAssertEqual(ordinary.scale, 2)
        XCTAssertEqual(ordinary.rect, CGRect(x: -2, y: 8, width: 224, height: 104))
        let large = try XCTUnwrap(NFScratchpadGeometryPolicy.previewPlan(for: CGRect(x: 0, y: 0, width: 20_000, height: 10_000)))
        XCTAssertLessThanOrEqual(large.pixelWidth, 1_024)
        XCTAssertLessThanOrEqual(large.pixelHeight, 1_024)
        XCTAssertLessThanOrEqual(large.pixelWidth * large.pixelHeight, 1_024 * 1_024)
        for bounds in [CGRect.zero, CGRect.null, CGRect.infinite,
                       CGRect(x: CGFloat.nan, y: 0, width: 1, height: 1),
                       CGRect(x: 0, y: 0, width: CGFloat.infinity, height: 1),
                       CGRect(x: 0, y: 0, width: 1_000_000_000, height: 1),
                       CGRect(x: 1_000_001, y: 0, width: 1, height: 1)] {
            XCTAssertNil(NFScratchpadGeometryPolicy.previewPlan(for: bounds))
        }
    }

    func testRecoveryDocumentWritesExactUnsupportedBytesAndDoesNotNormalizeThem() throws {
        let raw = "neuroforge-scratchpad-v999:unknown\nprivate 日本語 \t"
        let document = NFScratchpadRecoveryDocument(originalStoredValue: raw)
        XCTAssertEqual(document.originalBytes, Data(raw.utf8))
        let wrapper = document.makeRecoveryFileWrapper()
        XCTAssertEqual(wrapper.regularFileContents, Data(raw.utf8))
        let folder = FileManager.default.temporaryDirectory.appending(path: "NFScratchpadRecovery-\(UUID())")
        defer { try? FileManager.default.removeItem(at: folder) }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appending(path: "original.txt")
        try wrapper.write(to: url, options: .atomic, originalContentsURL: nil)
        XCTAssertEqual(try Data(contentsOf: url), Data(raw.utf8))
        XCTAssertFalse(NFScratchpadInspection.inspect(raw).canEdit)
    }

    func testUnavailableScratchpadSurvivesExactSessionResumeAndPortableBackup() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "NFScratchpadCheckpoint-\(UUID())")
        defer { try? FileManager.default.removeItem(at: folder) }
        let repository = NFLocalSessionRepository(url: folder.appending(path: "session.json"))
        let container = try ModelContainer(for: Schema(NFSchemaV1.models), configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let store = AppStore(context: container.mainContext, localSessionRepository: repository, allowsSharedWidgetPublishing: false)
        let request = SessionRequest(lab: .mentalMath, source: .focused, seed: 90210,
            localeIdentifier: "en", requestedItemCount: 1, isTimed: false)
        let runtime = NFUniversalSessionRuntime(request: request)
        let raw = "neuroforge-scratchpad-v999:unchanged-private-original\n日本語"
        runtime.scratchpad = raw
        XCTAssertTrue(runtime.checkpointDraft(store: store))
        let original = try XCTUnwrap(repository.archive.sessions.first?.checkpoint.scratchpad)
        XCTAssertFalse(NFScratchpadInspection.inspect(original).canEdit)
        runtime.releaseWriter()
        let reopened = NFLocalSessionRepository(url: folder.appending(path: "session.json"), ownerDeviceID: repository.ownerDeviceID)
        XCTAssertNil(reopened.loadError)
        XCTAssertEqual(reopened.archive.sessions.first?.checkpoint.scratchpad, raw)
        let exports = try NFDataExportService.makeExports(from: store)
        defer { if let first = exports.first { try? FileManager.default.removeItem(at: first.deletingLastPathComponent()) } }
        let url = try XCTUnwrap(exports.first { $0.lastPathComponent == "NeuroForge-Full-Archive.json" })
        let archive = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        let local = try XCTUnwrap(archive["localLearning"] as? [String: Any])
        let sessions = try XCTUnwrap(local["sessions"] as? [[String: Any]])
        let checkpoint = try XCTUnwrap(sessions.first?["checkpoint"] as? [String: Any])
        XCTAssertEqual(checkpoint["scratchpad"] as? String, raw)
        XCTAssertEqual(repository.archive.sessions.first?.checkpoint.scratchpad, original)
        XCTAssertTrue(store.attempts.isEmpty)
    }

    #if os(iOS)
    func testNativeDrawingClearUndoAndRedoUseSameRetainedCanvas() throws {
        let points = [CGPoint.zero, CGPoint(x: 100, y: 100)].enumerated().map { index, location in
            PKStrokePoint(location: location, timeOffset: Double(index), size: CGSize(width: 2, height: 2),
                opacity: 1, force: 1, azimuth: 0, altitude: .pi / 2)
        }
        let path = PKStrokePath(controlPoints: points, creationDate: Date(timeIntervalSince1970: 1_800_000_000))
        let drawing = PKDrawing(strokes: [PKStroke(ink: PKInk(.pen, color: .black), path: path)])
        let canvas = NFScratchpadNativeCanvas()
        canvas.drawing = drawing
        var saved = drawing.dataRepresentation()
        canvas.onDrawingChanged = { saved = $0 }
        let manager = try XCTUnwrap(canvas.undoManager)
        manager.removeAllActions()
        defer { manager.removeAllActions() }
        manager.groupsByEvent = false
        let controls = NFScratchpadEditingController()
        controls.attach(manager: manager, clear: { canvas.replaceDrawingUndoably(with: PKDrawing()) })
        manager.beginUndoGrouping(); controls.clear(); manager.endUndoGrouping(); controls.refresh()
        XCTAssertTrue(saved.isEmpty)
        XCTAssertTrue(canvas.drawing.strokes.isEmpty)
        controls.undo()
        XCTAssertEqual(canvas.drawing.strokes.count, 1)
        XCTAssertEqual(try XCTUnwrap(NFScratchpadDrawingSafety.decode(saved)).bounds, drawing.bounds)
        XCTAssertEqual(canvas.drawing.dataRepresentation(), drawing.dataRepresentation())
        XCTAssertTrue(controls.canRedo)
        controls.redo()
        XCTAssertTrue(saved.isEmpty)
        XCTAssertTrue(canvas.drawing.strokes.isEmpty)
    }

    func testPencilKitRejectsCorruptAndHugeSpanDrawingsWithoutRenderingThem() throws {
        XCTAssertNil(NFScratchpadDrawingSafety.decode(Data("not a PencilKit drawing".utf8)))
        XCTAssertNotNil(NFScratchpadDrawingSafety.decode(Data()))
        func drawing(end: CGPoint) -> PKDrawing {
            func point(_ location: CGPoint, offset: TimeInterval) -> PKStrokePoint {
                PKStrokePoint(location: location, timeOffset: offset, size: CGSize(width: 2, height: 2),
                    opacity: 1, force: 1, azimuth: 0, altitude: .pi / 2)
            }
            let path = PKStrokePath(controlPoints: [point(.zero, offset: 0), point(end, offset: 1)],
                creationDate: Date(timeIntervalSince1970: 1_800_000_000))
            return PKDrawing(strokes: [PKStroke(ink: PKInk(.pen, color: .black), path: path)])
        }
        let normalBytes = drawing(end: CGPoint(x: 100, y: 100)).dataRepresentation()
        let normal = try XCTUnwrap(NFScratchpadDrawingSafety.decode(normalBytes))
        let plan = try XCTUnwrap(NFScratchpadGeometryPolicy.previewPlan(for: normal.bounds))
        let image = normal.image(from: plan.rect, scale: plan.scale)
        XCTAssertLessThanOrEqual(try XCTUnwrap(image.cgImage).width, 1_024)
        let unsafeBytes = drawing(end: CGPoint(x: 1_000_001, y: 1)).dataRepresentation()
        XCTAssertLessThan(unsafeBytes.count, 1_024 * 1_024)
        XCTAssertNil(NFScratchpadDrawingSafety.decode(unsafeBytes))
        let original = NFScratchpadPayload(notes: "Keep my work", drawingData: unsafeBytes).storedValue
        XCTAssertEqual(NFScratchpadRecoveryDocument(originalStoredValue: original).originalBytes, Data(original.utf8))
    }
    #endif
}


@MainActor
final class HistoricalReviewContextTests: XCTestCase {
    private func sourceFixture() throws -> (NFExercise, NFSourceChunk) {
        let text = "An invariant must remain true after every update. Check the final state against the original rule, rather than a value cached before the last update."
        let chunk = NFSourceChunk(id: "chunk.history-original", documentID: UUID(uuidString: "C0100000-0000-0000-0000-000000000001")!,
            documentVersion: 2, sourceName: "Original state notes", locator: .init(page: 3, lineStart: nil, lineEnd: nil, section: nil),
            text: text, contentHash: String(AdaptiveEngine.fnv1a64(text), radix: 16), ordinal: 0)
        let request = try NFSourceReviewExactAdapter.makeRequest(chunk: chunk, localeIdentifier: "en")
        return (try XCTUnwrap(request.localCheckpoint?.exercise), chunk)
    }

    private func mutate(_ exercise: NFExercise, _ change: (inout [String: Any]) -> Void) throws -> NFExercise {
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(exercise)) as? [String: Any])
        change(&object)
        return try JSONDecoder().decode(NFExercise.self, from: JSONSerialization.data(withJSONObject: object))
    }

    func testOriginalLogicStateAndOnlyRecordedHintPrefixComeFromSavedContract() throws {
        let exercise = try NFFallbackExerciseGenerator.generate(.init(seed: 617, index: 0, lab: .logicDebugging,
            purpose: .practice, localeIdentifier: "en", preferredAssessmentMechanicID: "fixture.fallback-variant-0"))
        guard case .logicState(let schema) = exercise.interaction else { return XCTFail("Expected authentic logic fixture") }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let original = try encoder.encode(exercise)
        let shown = NFHistoryContextProjection.make(exercise: exercise, hintCount: 1, isProtected: false)
        XCTAssertEqual(shown.initialLogicState, schema.initialState)
        XCTAssertNotEqual(shown.initialLogicState, schema.expectedFinalState)
        XCTAssertTrue(shown.representations.contains { if case .logicState = $0 { return true }; return false })
        XCTAssertEqual(shown.usedHints, Array(exercise.feedback.hintLadder.prefix(1)))
        XCTAssertFalse(NFHistoryContextProjection.make(exercise: exercise, hintCount: 0, isProtected: false).hasUnavailableHints)
        XCTAssertTrue(NFHistoryContextProjection.make(exercise: exercise, hintCount: 0, isProtected: false).usedHints.isEmpty)
        let missing = NFHistoryContextProjection.make(exercise: nil, hintCount: 2, isProtected: false)
        XCTAssertTrue(missing.hasUnavailableHints)
        XCTAssertTrue(missing.usedHints.isEmpty)
        let partial = NFHistoryContextProjection.make(exercise: exercise,
            hintCount: exercise.feedback.hintLadder.count + 1, isProtected: false)
        XCTAssertEqual(partial.usedHints, exercise.feedback.hintLadder)
        XCTAssertTrue(partial.hasUnavailableHints)
        XCTAssertEqual(try encoder.encode(exercise), original)
    }

    func testMatchingSourceRequiresExactIdentityRecomputedDigestAndCurrentVersion() throws {
        let (exercise, chunk) = try sourceFixture()
        let citationID = try XCTUnwrap(exercise.citations.first?.id)
        let documents = [NFHistorySourceDocument(id: chunk.documentID, extractionVersion: chunk.documentVersion)]
        let matched = NFHistoryCitationPolicy.resolve(exercise: exercise, citationID: citationID,
            documents: documents, chunks: [chunk], isProtected: false)
        XCTAssertEqual(matched.availability, .available)
        XCTAssertEqual(matched.currentExcerpt, chunk.text)
        XCTAssertEqual(matched.matchedExtractionVersion, 2)
        XCTAssertEqual(matched.citation?.sourceChunkID, chunk.id)
        let altered = NFSourceChunk(id: chunk.id, documentID: chunk.documentID,
            documentVersion: chunk.documentVersion, sourceName: chunk.sourceName, locator: chunk.locator,
            text: "A changed source must never replace the original reference.", contentHash: chunk.contentHash, ordinal: 0)
        let changed = NFHistoryCitationPolicy.resolve(exercise: exercise, citationID: citationID,
            documents: documents, chunks: [altered], isProtected: false)
        XCTAssertEqual(changed.availability, .changedSource)
        XCTAssertNil(changed.currentExcerpt)
        XCTAssertNil(changed.matchedExtractionVersion)
        XCTAssertEqual(changed.savedExcerpt, chunk.text)
        let versionMismatch = NFHistoryCitationPolicy.resolve(exercise: exercise, citationID: citationID,
            documents: [.init(id: chunk.documentID, extractionVersion: 3)], chunks: [chunk], isProtected: false)
        XCTAssertEqual(versionMismatch.availability, .changedSource)
        XCTAssertNil(versionMismatch.currentExcerpt)
        let wrongDocument = NFSourceChunk(id: chunk.id, documentID: UUID(), documentVersion: 2,
            sourceName: chunk.sourceName, locator: chunk.locator, text: chunk.text, contentHash: chunk.contentHash, ordinal: 0)
        XCTAssertEqual(NFHistoryCitationPolicy.resolve(exercise: exercise, citationID: citationID,
            documents: documents, chunks: [wrongDocument], isProtected: false).availability, .missingSource)
    }

    func testMissingSourceCanUseOnlyAnAuthenticatedExactSourceReviewReference() throws {
        let (exercise, chunk) = try sourceFixture()
        let citationID = try XCTUnwrap(exercise.citations.first?.id)
        let missing = NFHistoryCitationPolicy.resolve(exercise: exercise, citationID: citationID,
            documents: [], chunks: [], isProtected: false)
        XCTAssertEqual(missing.availability, .missingSource)
        XCTAssertEqual(missing.savedExcerpt, chunk.text)
        XCTAssertNil(missing.matchedExtractionVersion, "An old numeric source version is never invented")
        let differentAuthority = try mutate(exercise) { $0["templateFamily"] = "ai.studio.document-practice.shortAnswer" }
        let generatedReference = NFHistoryCitationPolicy.resolve(exercise: differentAuthority, citationID: citationID,
            documents: [], chunks: [], isProtected: false)
        XCTAssertNil(generatedReference.savedExcerpt, "A model answer is not an original source excerpt")
        let noDigest = try mutate(exercise) { object in
            var citations = object["citations"] as! [[String: Any]]
            citations[0].removeValue(forKey: "excerptDigest")
            object["citations"] = citations
        }
        let unverified = NFHistoryCitationPolicy.resolve(exercise: noDigest, citationID: citationID,
            documents: [.init(id: chunk.documentID, extractionVersion: 2)], chunks: [chunk], isProtected: false)
        XCTAssertEqual(unverified.availability, .unverifiedRevision)
        XCTAssertNil(unverified.currentExcerpt)
        XCTAssertNil(unverified.savedExcerpt)
        let unknownDigest = try mutate(exercise) { object in
            var citations = object["citations"] as! [[String: Any]]
            citations[0]["excerptDigest"] = "future-digest-algorithm:1234"
            object["citations"] = citations
        }
        XCTAssertEqual(NFHistoryCitationPolicy.resolve(exercise: unknownDigest, citationID: citationID,
            documents: [.init(id: chunk.documentID, extractionVersion: 2)], chunks: [chunk], isProtected: false).availability,
            .unverifiedRevision)
        let foreign = NFHistoryCitationPolicy.resolve(exercise: exercise, citationID: "citation.not-in-exact-snapshot",
            documents: [.init(id: chunk.documentID, extractionVersion: 2)], chunks: [chunk], isProtected: false)
        XCTAssertEqual(foreign.availability, .unavailableCitation)
        XCTAssertNil(foreign.citation)
        XCTAssertNil(foreign.savedExcerpt)
    }

    func testProtectedRestrictionPrecedesHintsLogicCitationAndSavedExcerptConstruction() throws {
        let (exercise, chunk) = try sourceFixture()
        let protectedExercise = try mutate(exercise) { $0["assessmentProtected"] = true }
        for (value, flag) in [(exercise, true), (protectedExercise, false)] {
            let context = NFHistoryContextProjection.make(exercise: value, hintCount: 10, isProtected: flag)
            XCTAssertNil(context.context)
            XCTAssertTrue(context.representations.isEmpty)
            XCTAssertTrue(context.initialLogicState.isEmpty)
            XCTAssertTrue(context.usedHints.isEmpty)
            XCTAssertTrue(context.citations.isEmpty)
            let citation = NFHistoryCitationPolicy.resolve(exercise: value, citationID: exercise.citations[0].id,
                documents: [.init(id: chunk.documentID, extractionVersion: 2)], chunks: [chunk], isProtected: flag)
            XCTAssertEqual(citation.availability, .protectedContent)
            XCTAssertNil(citation.citation)
            XCTAssertNil(citation.currentExcerpt)
            XCTAssertNil(citation.savedExcerpt)
        }
    }

    func testCitationRouteRequiresCommittedReceiptAndRespectsLaterProtectedMarker() throws {
        let (exercise, chunk) = try sourceFixture()
        let container = try ModelContainer(for: Schema(NFSchemaV1.models), configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let repository = NFLocalSessionRepository()
        let store = AppStore(context: container.mainContext, localSessionRepository: repository, allowsSharedWidgetPublishing: false)
        let attemptID = UUID(), citationID = exercise.citations[0].id
        let document = SourceDocumentRecord(filename: chunk.sourceName, typeIdentifier: "public.plain-text", sizeBytes: 100, localPath: "")
        document.id = chunk.documentID; document.extractionVersion = chunk.documentVersion
        container.mainContext.insert(document)
        container.mainContext.insert(SourceChunkRecord(chunk: chunk))
        try container.mainContext.save(); store.reload()
        try repository.retainSnapshot(attemptID: attemptID, exercise: exercise)
        let beforeCommit = store.historyCitationPresentation(attemptID: attemptID, citationID: citationID)
        XCTAssertEqual(beforeCommit.availability, .unavailableCitation)
        XCTAssertNil(beforeCommit.savedExcerpt)
        let response = NFExerciseResponse.selfCheck(.init(rating: .matched, reflection: "I recall that each update must preserve the invariant."))
        try store.saveExerciseAttempt(attemptID: attemptID, sessionID: UUID(), exercise: exercise,
            response: response, result: NFExerciseScoringEngine.score(response, for: exercise), confidence: nil,
            shownAt: Date(timeIntervalSince1970: 1_800_000_000), activeDuration: 12, source: .focused)
        let originalResponse = try XCTUnwrap(store.attempts.first?.response)
        XCTAssertEqual(store.historyCitationPresentation(attemptID: attemptID, citationID: citationID).currentExcerpt, chunk.text)
        var updated = repository.archive
        updated.withheldProtectedConflictAttemptIDs = [attemptID]
        try repository.restorePredecessor(updated)
        let protected = store.historyCitationPresentation(attemptID: attemptID, citationID: citationID)
        XCTAssertEqual(protected.availability, .protectedContent)
        XCTAssertNil(protected.citation)
        XCTAssertNil(protected.currentExcerpt)
        XCTAssertNil(protected.savedExcerpt)
        XCTAssertEqual(store.attempts.first?.response, originalResponse)
        XCTAssertEqual(store.attempts.count, 1)
    }
}

@MainActor
final class ReviewDeferralTests: XCTestCase {
    private let profileID = UUID(uuidString: "7C253B52-7F01-49D6-B3AB-3C782E33A500")!
    private let anchorID = UUID(uuidString: "7C253B52-7F01-49D6-B3AB-3C782E33A501")!
    private func date(_ value: String) -> Date { ISO8601DateFormatter().date(from: value)! }
    private func calendar(_ zone: String = "America/Toronto") -> Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(identifier: zone)!
        return value
    }
    private func origin() -> NFCompatibilityReminderOrigin {
        .init(state: .init(id: "synthetic.review.addition", templateFamily: "synthetic.review.addition",
            lab: .mentalMath, lastReviewedAt: date("2026-03-01T10:00:00Z"), repetitions: 1), anchorAttemptID: anchorID)
    }
    private func deferred() throws -> NFReviewDeferral {
        let entry = try XCTUnwrap(NFReviewDeferralPolicy.project(origins: [origin()], profileID: profileID,
            deferrals: [], calendar: calendar()).first)
        return try XCTUnwrap(NFReviewDeferralPolicy.make(entry: entry, profileID: profileID,
            at: date("2026-03-07T09:00:00Z"), dayBoundaryHour: 4, calendar: calendar()))
    }

    func testDeferralEndsAtConfiguredBoundaryAcrossDSTAndReturnsAtExactInstant() throws {
        let record = try deferred()
        XCTAssertEqual(record.deferredUntil, date("2026-03-08T08:00:00Z"))
        XCTAssertEqual(record.deferredUntil.timeIntervalSince(record.requestedAt), 23 * 3_600)
        let entry = try XCTUnwrap(NFReviewDeferralPolicy.project(origins: [origin()], profileID: profileID,
            deferrals: [record], calendar: calendar()).first)
        XCTAssertTrue(entry.isDeferred(at: record.deferredUntil.addingTimeInterval(-1)))
        XCTAssertFalse(entry.isDue(at: record.deferredUntil.addingTimeInterval(-1)))
        XCTAssertTrue(entry.isDue(at: record.deferredUntil))
        XCTAssertFalse(entry.isDeferred(at: record.deferredUntil))
        XCTAssertNil(NFReviewDeferralPolicy.make(entry: entry, profileID: profileID,
            at: record.requestedAt.addingTimeInterval(1), dayBoundaryHour: 4, calendar: calendar()),
            "Repeated taps cannot extend a currently deferred entry")
    }

    func testDurableDeferralAfterSpringClockChangeUsesNextLocalDayBoundary() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "NFDeferralSpringBoundary-\(UUID())")
        defer { try? FileManager.default.removeItem(at: folder) }
        let owner = UUID(), url = folder.appending(path: "local.json")
        let repository = NFLocalSessionRepository(url: url, ownerDeviceID: owner)
        let (store, container, attempt) = try fixture(repository: repository); defer { _ = container }
        let now = date("2026-03-08T08:30:00Z") // 04:30 EDT, after the new local day has begun.
        let expected = date("2026-03-09T08:00:00Z")
        let original = try NFImmutableAttemptRecordSnapshot.encoded(NFImmutableAttemptRecordSnapshot(attempt))
        let records = try store.deferReviews(memoryItemIDs: [origin().state.id], at: now, calendar: calendar())
        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records.first?.deferredUntil, expected)
        XCTAssertTrue(store.readyReviewEntries(at: expected.addingTimeInterval(-1), calendar: calendar()).isEmpty)
        XCTAssertEqual(store.readyReviewEntries(at: expected, calendar: calendar()).map(\.id), [origin().state.id])
        let cold = NFLocalSessionRepository(url: url, ownerDeviceID: owner)
        let payload = try XCTUnwrap(cold.archive.privateStudyRuns?.first { $0.id == NFPrivateStudyMetadata.recordID }?.payload)
        let restored = try JSONDecoder().decode(NFPrivateStudyMetadata.self, from: payload)
        XCTAssertTrue(restored.isSupported)
        XCTAssertEqual(restored.reviewDeferrals, records)
        XCTAssertEqual(try NFImmutableAttemptRecordSnapshot.encoded(NFImmutableAttemptRecordSnapshot(attempt)), original)
    }

    func testTravelUsesAcceptedReturnInstantAndNewSuccessDoesNotInheritOldDeferral() throws {
        let record = try deferred()
        let moved = try XCTUnwrap(NFReviewDeferralPolicy.project(origins: [origin()], profileID: profileID,
            deferrals: [record], calendar: calendar("Asia/Tokyo")).first)
        XCTAssertEqual(moved.dueAt, record.deferredUntil)
        let fresh = NFCompatibilityReminderOrigin(state: .init(id: origin().state.id,
            templateFamily: origin().state.templateFamily, lab: .mentalMath,
            lastReviewedAt: record.requestedAt.addingTimeInterval(60), repetitions: 1), anchorAttemptID: UUID())
        let refreshed = try XCTUnwrap(NFReviewDeferralPolicy.project(origins: [fresh], profileID: profileID,
            deferrals: [record], calendar: calendar()).first)
        XCTAssertNil(refreshed.deferral)
        XCTAssertEqual(refreshed.dueAt, refreshed.naturalDueAt)
        XCTAssertEqual(origin().state.repetitions, 1)
    }

    func testUnknownAndDuplicateDeferralsCannotSuppressNormalReminders() throws {
        var unknown = try deferred(); unknown.schemaVersion = 999
        XCTAssertFalse(NFReviewDeferralPolicy.supports([unknown]))
        XCTAssertFalse(NFReviewDeferralPolicy.supports([try deferred(), try deferred()]))
        let entry = try XCTUnwrap(NFReviewDeferralPolicy.project(origins: [origin()], profileID: profileID,
            deferrals: [unknown], calendar: calendar()).first)
        XCTAssertNil(entry.deferral)
        XCTAssertTrue(entry.isDue(at: unknown.requestedAt))
        let data = try JSONEncoder().encode(NFPrivateStudyMetadata())
        var legacy = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        legacy.removeValue(forKey: "reviewDeferrals")
        let decoded = try JSONDecoder().decode(NFPrivateStudyMetadata.self,
            from: JSONSerialization.data(withJSONObject: legacy))
        XCTAssertTrue(decoded.isSupported)
        XCTAssertNil(decoded.reviewDeferrals)
    }

    private func fixture(repository: NFLocalSessionRepository) throws -> (AppStore, ModelContainer, AttemptRecord) {
        let container = try ModelContainer(for: Schema(NFSchemaV1.models),
            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let profile = UserProfileRecord(draft: OnboardingDraft())
        profile.id = profileID; profile.dayBoundaryHour = 4
        container.mainContext.insert(profile)
        let attempt = AttemptRecord(sessionID: UUID(uuidString: "7C253B52-7F01-49D6-B3AB-3C782E33A502")!,
            lab: .mentalMath, itemID: "synthetic.review.addition.first", prompt: "What is one plus one?",
            response: String(decoding: try JSONEncoder().encode(NFExerciseResponse.numeric(.init(value: "2", unit: nil))), as: UTF8.self),
            correctAnswer: "2", isCorrect: true, confidence: .certain, evidenceClass: .practice, source: .focused)
        attempt.id = anchorID; attempt.templateID = origin().state.id
        attempt.scoringVersion = NFExerciseScoringEngine.scoringVersion
        attempt.responseFormatRaw = "numeric"; attempt.deterministicCredit = 1; attempt.evidenceWeight = 1
        attempt.submittedAt = try XCTUnwrap(origin().state.lastReviewedAt)
        container.mainContext.insert(attempt)
        try container.mainContext.save()
        let store = AppStore(context: container.mainContext, localSessionRepository: repository,
            allowsSharedWidgetPublishing: false)
        XCTAssertFalse(store.allowsSharedWidgetPublishing)
        return (store, container, attempt)
    }

    func testFailedDeferralWritePreservesQueueBytesAndRetrySurvivesColdRead() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "NFDeferralDraft-\(UUID())")
        let backup = folder.appendingPathExtension("backup")
        defer { try? FileManager.default.removeItem(at: folder); try? FileManager.default.removeItem(at: backup) }
        let owner = UUID(), url = folder.appending(path: "local.json")
        let repository = NFLocalSessionRepository(url: url, ownerDeviceID: owner)
        let (store, container, attempt) = try fixture(repository: repository); defer { _ = container }
        try store.saveStudyAnnotation(.init(id: attempt.id, note: "Keep this note", bookmarked: true))
        let original = try NFImmutableAttemptRecordSnapshot.encoded(NFImmutableAttemptRecordSnapshot(attempt))
        let bytes = try Data(contentsOf: url)
        let revision = store.localSessionRevision
        let now = date("2026-03-07T09:00:00Z")
        XCTAssertTrue(store.reviewDueEntries(at: now, calendar: calendar()).contains { $0.id == origin().state.id && $0.isDue(at: now) })
        try FileManager.default.moveItem(at: folder, to: backup)
        try Data("blocked directory".utf8).write(to: folder)
        XCTAssertThrowsError(try store.deferReviews(memoryItemIDs: [origin().state.id], at: now, calendar: calendar()))
        XCTAssertEqual(store.localSessionRevision, revision)
        XCTAssertNil(store.privateStudyMetadata.reviewDeferrals)
        XCTAssertEqual(try Data(contentsOf: backup.appending(path: "local.json")), bytes)
        try FileManager.default.removeItem(at: folder)
        try FileManager.default.moveItem(at: backup, to: folder)
        let written = try store.deferReviews(memoryItemIDs: [origin().state.id], at: now, calendar: calendar())
        XCTAssertEqual(written.count, 1)
        XCTAssertTrue(store.reviewDueEntries(at: now, calendar: calendar()).contains { $0.id == origin().state.id && $0.isDeferred(at: now) })
        XCTAssertEqual(store.privateStudyMetadata.annotations.first?.note, "Keep this note")
        XCTAssertEqual(try NFImmutableAttemptRecordSnapshot.encoded(NFImmutableAttemptRecordSnapshot(attempt)), original)
        let cold = NFLocalSessionRepository(url: url, ownerDeviceID: owner)
        let payload = try XCTUnwrap(cold.archive.privateStudyRuns?.first { $0.id == NFPrivateStudyMetadata.recordID }?.payload)
        XCTAssertEqual(try JSONDecoder().decode(NFPrivateStudyMetadata.self, from: payload).reviewDeferrals, written)
        let portable = try JSONDecoder().decode(NFLocalSessionRepository.Archive.self,
            from: JSONEncoder().encode(cold.exportArchive))
        let target = NFLocalSessionRepository(ownerDeviceID: owner)
        try target.importArchive(portable)
        let imported = try XCTUnwrap(target.archive.privateStudyRuns?.first { $0.id == NFPrivateStudyMetadata.recordID }?.payload)
        XCTAssertEqual(try JSONDecoder().decode(NFPrivateStudyMetadata.self, from: imported).reviewDeferrals, written)
        try target.removeReferences(attemptIDs: [attempt.id])
        let cleaned = try XCTUnwrap(target.archive.privateStudyRuns?.first { $0.id == NFPrivateStudyMetadata.recordID }?.payload)
        XCTAssertTrue(try XCTUnwrap(JSONDecoder().decode(NFPrivateStudyMetadata.self, from: cleaned).reviewDeferrals).isEmpty)
    }

    func testStaleMetadataWriteCannotOverwritePeerBookmarkOrAcquireDeferral() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "NFDeferralPeer-\(UUID())")
        defer { try? FileManager.default.removeItem(at: folder) }
        let owner = UUID(), url = folder.appending(path: "local.json")
        let first = NFLocalSessionRepository(url: url, ownerDeviceID: owner)
        let (store, container, attempt) = try fixture(repository: first); defer { _ = container }
        try store.saveStudyAnnotation(.init(id: attempt.id, note: "Original", bookmarked: true))
        let peer = NFLocalSessionRepository(url: url, ownerDeviceID: owner)
        var metadata = store.privateStudyMetadata
        metadata.annotations[0].note = "Peer note that must survive"
        try peer.savePrivateStudyRun(id: NFPrivateStudyMetadata.recordID, generationID: NFPrivateStudyMetadata.recordID,
            payload: JSONEncoder().encode(metadata))
        let peerBytes = try Data(contentsOf: url)
        XCTAssertThrowsError(try store.deferReviews(memoryItemIDs: [origin().state.id],
            at: date("2026-03-07T09:00:00Z"), calendar: calendar()))
        XCTAssertEqual(try Data(contentsOf: url), peerBytes)
        XCTAssertNil(store.privateStudyMetadata.reviewDeferrals)
    }

    func testFutureMetadataIsRetainedAndCannotHideTheNaturalReviewSchedule() throws {
        let repository = NFLocalSessionRepository()
        let (store, container, _) = try fixture(repository: repository); defer { _ = container }
        var record = try deferred(); record.schemaVersion = 999
        var metadata = NFPrivateStudyMetadata(); metadata.reviewDeferrals = [record]
        let payload = try JSONEncoder().encode(metadata)
        try repository.savePrivateStudyRun(id: NFPrivateStudyMetadata.recordID,
            generationID: NFPrivateStudyMetadata.recordID, payload: payload)
        let now = date("2026-03-07T09:00:00Z")
        XCTAssertNotNil(store.privateStudyMetadataUnavailableReason)
        XCTAssertTrue(store.reviewDueEntries(at: now, calendar: calendar()).contains { $0.id == origin().state.id && $0.isDue(at: now) })
        XCTAssertThrowsError(try store.deferReviews(memoryItemIDs: [origin().state.id], at: now, calendar: calendar()))
        XCTAssertEqual(repository.archive.privateStudyRuns?.first { $0.id == NFPrivateStudyMetadata.recordID }?.payload, payload)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(try deferred())) as? [String: Any])
        object["deferredUntil"] = date("2099-03-08T08:00:00Z").timeIntervalSinceReferenceDate
        let unbounded = try JSONDecoder().decode(NFReviewDeferral.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertFalse(unbounded.isSupported)
    }
    private func authenticFixture() throws -> (store: AppStore, container: ModelContainer, exercises: [NFExercise], attempts: [AttemptRecord], now: Date) {
        let now = date("2026-09-05T16:00:00Z")
        let container = try ModelContainer(for: Schema(NFSchemaV1.models),
            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        var draft = OnboardingDraft()
        draft.dailyDuration = 30; draft.aiMode = .disabled
        let profile = UserProfileRecord(draft: draft); profile.id = profileID; profile.dayBoundaryHour = 4
        container.mainContext.insert(profile)
        let repository = NFLocalSessionRepository()
        var exercises: [NFExercise] = [], attempts: [AttemptRecord] = []
        for variant in [0, 1, 2] {
            let exercise = try NFFallbackExerciseGenerator.generate(.init(seed: UInt64(20260905 + variant),
                index: 0, lab: .mentalMath, purpose: .practice, localeIdentifier: "en",
                preferredAssessmentMechanicID: "fixture.fallback-variant-\(variant)"))
            guard case .numeric(let schema) = exercise.interaction else {
                XCTFail("The pinned authored numeric fixture changed its response contract")
                throw CocoaError(.coderInvalidValue)
            }
            let response = NFExerciseResponse.numeric(.init(value: String(schema.answer.value), unit: schema.answer.canonicalUnit))
            let score = NFExerciseScoringEngine.score(response, for: exercise)
            XCTAssertTrue(score.isCorrect)
            let attempt = AttemptRecord(sessionID: UUID(), lab: exercise.lab, itemID: exercise.id,
                prompt: exercise.prompt, response: String(decoding: try JSONEncoder().encode(response), as: UTF8.self),
                correctAnswer: score.expectedAnswerSummary ?? "", isCorrect: true, confidence: .certain,
                evidenceClass: .practice, source: .focused)
            attempt.templateID = exercise.templateID; attempt.assessmentTemplateFamily = exercise.templateFamily
            attempt.seed = exercise.seed; attempt.responseFormatRaw = "numeric"
            attempt.scoringVersion = NFExerciseScoringEngine.scoringVersion
            attempt.deterministicCredit = 1; attempt.evidenceWeight = 1
            attempt.submittedAt = variant == 2 ? now.addingTimeInterval(-60) : date("2001-03-01T10:00:00Z").addingTimeInterval(Double(variant))
            container.mainContext.insert(attempt)
            try repository.retainSnapshot(attemptID: attempt.id, exercise: exercise)
            exercises.append(exercise); attempts.append(attempt)
        }
        try container.mainContext.save()
        let store = AppStore(context: container.mainContext, localSessionRepository: repository,
            allowsSharedWidgetPublishing: false)
        return (store, container, exercises, attempts, now)
    }

    func testDeferralProjectsCanonicalTodayWithoutChangingPinnedTargetsAndSequenceRevalidates() throws {
        let fixture = try authenticFixture(); let store = fixture.store; defer { _ = fixture.container }
        let plan = store.dailyPlan(at: fixture.now, calendar: calendar())
        let review = try XCTUnwrap(plan.blocks.first { $0.evidenceClass == .retention && $0.retentionItemIDs.count == 2 })
        let record = try XCTUnwrap(store.dailyPlans.first { $0.id == plan.id })
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let originalPlan = try encoder.encode(try XCTUnwrap(record.snapshot))
        let pinned = store.retentionReviewTargets(forPlanID: plan.id, blockID: review.id,
            fallbackItemIDs: review.retentionItemIDs, fallbackSeed: plan.seed)
        let delayedID = fixture.exercises[0].templateID
        XCTAssertEqual(Set(store.readyReviewEntries(at: fixture.now, calendar: calendar()).map(\.id)),
            Set(fixture.exercises.prefix(2).map(\.templateID)))
        try store.deferReviews(memoryItemIDs: [delayedID], at: fixture.now, calendar: calendar())
        let projected = store.reviewExecutionPlan(plan, at: fixture.now, calendar: calendar())
        let executable = try XCTUnwrap(projected.blocks.first { $0.id == review.id })
        XCTAssertEqual(executable.retentionItemIDs, [fixture.exercises[1].templateID])
        XCTAssertLessThan(executable.minutes, review.minutes)
        XCTAssertFalse(projected.blocks.flatMap(\.retentionItemIDs).contains(fixture.exercises[2].templateID))
        XCTAssertEqual(try encoder.encode(try XCTUnwrap(record.snapshot)), originalPlan)
        let sequence = NFTodaySessionSequence()
        XCTAssertTrue(sequence.start(plan: plan, blockIDs: [review.id], store: store,
            at: fixture.now, calendar: calendar()), store.lastErrorMessage ?? "")
        let request = try XCTUnwrap(store.activeSessionRequest)
        XCTAssertEqual(request.retentionTargets, pinned.filter { $0.memoryItemID != delayedID })
        XCTAssertEqual(request.requestedItemCount, 1)
        XCTAssertThrowsError(try store.deferReviews(memoryItemIDs: [fixture.exercises[1].templateID],
            at: fixture.now, calendar: calendar())) { XCTAssertEqual($0 as? NFReviewDeferralError, .acceptedReviewInProgress) }
        XCTAssertEqual(store.activeSessionRequest?.retentionTargets, request.retentionTargets)
        let runtime = NFUniversalSessionRuntime(request: request)
        runtime.numericValue = "17"
        XCTAssertTrue(runtime.checkpointDraft(store: store), runtime.saveError ?? "")
        let saved = try XCTUnwrap(store.localSessions.archive.sessions.first { $0.id == runtime.sessionID })
        let bytes = try JSONEncoder().encode(saved)
        runtime.releaseWriter(); store.activeSessionRequest = nil
        let cold = try JSONDecoder().decode(NFLocalSessionEnvelope.self, from: bytes)
        var restoredRequest = cold.request
        restoredRequest.localSessionID = cold.id; restoredRequest.localCheckpoint = cold.checkpoint
        let restored = NFUniversalSessionRuntime(request: restoredRequest)
        XCTAssertNil(restored.unavailableReason)
        XCTAssertEqual(restored.exercise, runtime.exercise)
        XCTAssertEqual(restored.numericValue, "17")
        XCTAssertEqual(restored.request.retentionTargets, request.retentionTargets)
        XCTAssertThrowsError(try store.deferReviews(memoryItemIDs: [fixture.exercises[1].templateID],
            at: fixture.now, calendar: calendar()), "A cold suspended exact review remains accepted")
        sequence.clear()
    }

    func testStandaloneReviewHasExactBoundedTargetsAndCompletionKeepsOriginalMemoryIdentity() throws {
        let fixture = try authenticFixture(); let store = fixture.store; defer { _ = fixture.container }
        let original = try NFImmutableAttemptRecordSnapshot.encoded(NFImmutableAttemptRecordSnapshot(fixture.attempts[0]))
        let expected = store.nextReviewBatch(at: fixture.now, calendar: calendar())
        XCTAssertEqual(expected.count, 2)
        XCTAssertTrue(store.requestReviewsDue(at: fixture.now, calendar: calendar()), store.lastErrorMessage ?? "")
        let request = try XCTUnwrap(store.activeSessionRequest)
        XCTAssertEqual(request.source, .focused); XCTAssertEqual(request.evidenceClass, .retention)
        XCTAssertNil(request.planID); XCTAssertNil(request.planBlockID)
        XCTAssertEqual(request.requestedItemCount, expected.count); XCTAssertEqual(request.retentionTargets, expected)
        let exercise = NFDeterministicSessionExerciseFactory.makeExercise(request: request, index: 0,
            assessmentDescriptor: nil, excludingContentFingerprints: request.repairSemanticExclusions ?? [])
        XCTAssertNil(exercise.availabilityReason)
        XCTAssertFalse(Set(fixture.exercises.map { NFQuestionFingerprint.fingerprint(for: $0) })
            .contains(NFQuestionFingerprint.fingerprint(for: exercise)))
        guard case .numeric(let schema) = exercise.interaction else { XCTFail("The pinned numeric mechanic was substituted"); return }
        let response = NFExerciseResponse.numeric(.init(value: String(schema.answer.value), unit: schema.answer.canonicalUnit))
        let score = NFExerciseScoringEngine.score(response, for: exercise)
        XCTAssertTrue(score.isCorrect)
        let id = UUID()
        try store.saveExerciseAttempt(attemptID: id, sessionID: request.id, exercise: exercise, response: response,
            result: score, confidence: nil, shownAt: fixture.now, activeDuration: 30, source: .focused)
        let saved = try XCTUnwrap(store.attempts.first { $0.id == id })
        XCTAssertEqual(saved.templateID, expected[0].memoryItemID)
        let refreshed = try XCTUnwrap(store.reviewDueEntries(at: saved.submittedAt.addingTimeInterval(1), calendar: calendar())
            .first { $0.id == expected[0].memoryItemID })
        XCTAssertEqual(refreshed.origin.anchorAttemptID, id)
        XCTAssertFalse(refreshed.isDue(at: saved.submittedAt.addingTimeInterval(1)))
        XCTAssertEqual(try NFImmutableAttemptRecordSnapshot.encoded(NFImmutableAttemptRecordSnapshot(fixture.attempts[0])), original)
    }

    func testAllDueDeferredMakesEmptyLaunchAndReturnsAtExactBoundaryWithoutRewritingHistory() throws {
        let fixture = try authenticFixture(); let store = fixture.store; defer { _ = fixture.container }
        let dueIDs = Set(fixture.exercises.prefix(2).map(\.templateID))
        let originalCount = store.attempts.count
        let written = try store.deferReviews(memoryItemIDs: dueIDs, at: fixture.now, calendar: calendar())
        let boundary = try XCTUnwrap(written.first?.deferredUntil)
        XCTAssertTrue(store.readyReviewEntries(at: fixture.now, calendar: calendar()).isEmpty)
        XCTAssertTrue(store.nextReviewBatch(at: fixture.now, calendar: calendar()).isEmpty)
        XCTAssertEqual(store.nextEffectiveReviewDate(at: fixture.now, calendar: calendar()), boundary)
        XCTAssertFalse(store.requestReviewsDue(at: fixture.now, calendar: calendar()))
        XCTAssertNil(store.activeSessionRequest); XCTAssertEqual(store.attempts.count, originalCount)
        XCTAssertEqual(Set(store.readyReviewEntries(at: boundary, calendar: calendar()).map(\.id)), dueIDs)
        XCTAssertEqual(store.nextReviewBatch(at: boundary, calendar: calendar()).count, dueIDs.count)
    }

    func testQuarantineAndProtectedMarkerFilterQueueAndRejectStaleLaunchTargets() throws {
        let fixture = try authenticFixture(); let store = fixture.store; defer { _ = fixture.container }
        let stale = store.nextReviewBatch(at: fixture.now, calendar: calendar())
        let report = ItemReportRecord(exercise: fixture.exercises[0], reason: "The item needs review", note: "")
        fixture.container.mainContext.insert(report)
        try fixture.container.mainContext.save(); store.reload()
        var archive = store.localSessions.archive
        archive.withheldProtectedConflictAttemptIDs = [fixture.attempts[1].id]
        try store.localSessions.restorePredecessor(archive)
        XCTAssertTrue(store.readyReviewEntries(at: fixture.now, calendar: calendar()).isEmpty)
        XCTAssertFalse(store.beginSession(lab: .mentalMath, source: .focused, evidenceClass: .retention,
            requestedItemCount: 2, retentionItemIDs: stale.map(\.memoryItemID), retentionTargets: stale,
            reviewSchedulingDate: fixture.now, reviewSchedulingCalendar: calendar()))
        XCTAssertNil(store.activeSessionRequest)
        let value = store.reviewQueueSavedPresentation(for: fixture.attempts[1])
        XCTAssertTrue(value.isProtected)
        XCTAssertFalse(value.title.contains(fixture.attempts[1].prompt))
        XCTAssertFalse(value.detail.contains(fixture.attempts[1].response))
        let original = try NFImmutableAttemptRecordSnapshot.encoded(NFImmutableAttemptRecordSnapshot(fixture.attempts[1]))
        var annotation = NFStudyAnnotation(id: fixture.attempts[1].id, note: "Keep my private note", bookmarked: true)
        try store.saveStudyAnnotation(annotation)
        annotation.bookmarked = false; try store.saveStudyAnnotation(annotation)
        XCTAssertEqual(store.privateStudyMetadata.annotations.first?.note, "Keep my private note")
        XCTAssertEqual(try NFImmutableAttemptRecordSnapshot.encoded(NFImmutableAttemptRecordSnapshot(fixture.attempts[1])), original)
    }

}

@MainActor
final class CommittedFeedbackCitationTests: XCTestCase {
    private struct Fixture {
        let store: AppStore
        let container: ModelContainer
        let chunk: NFSourceChunk
        let document: SourceDocumentRecord
        let chunkRecord: SourceChunkRecord
    }

    private func fixture(repository: NFLocalSessionRepository? = nil) throws -> Fixture {
        let container = try ModelContainer(for: Schema(NFSchemaV1.models),
            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let text = "The amber pendulum returns to its resting position when the restoring force opposes displacement."
        let chunk = NFSourceChunk(id: "chunk.feedback-citation.original",
            documentID: UUID(uuidString: "8CA70000-0000-0000-0000-000000000001")!,
            documentVersion: 2, sourceName: "Original pendulum notes",
            locator: .init(page: 3, lineStart: nil, lineEnd: nil, section: nil),
            text: text, contentHash: String(AdaptiveEngine.fnv1a64(text), radix: 16), ordinal: 0, language: "en")
        let document = SourceDocumentRecord(filename: chunk.sourceName,
            typeIdentifier: "public.plain-text", sizeBytes: Int64(text.utf8.count), localPath: "")
        document.id = chunk.documentID; document.extractionVersion = chunk.documentVersion
        let chunkRecord = SourceChunkRecord(chunk: chunk)
        container.mainContext.insert(document); container.mainContext.insert(chunkRecord)
        try container.mainContext.save()
        let store = AppStore(context: container.mainContext, localSessionRepository: repository,
            allowsSharedWidgetPublishing: false)
        XCTAssertFalse(store.allowsSharedWidgetPublishing)
        return .init(store: store, container: container, chunk: chunk, document: document, chunkRecord: chunkRecord)
    }

    private func sourceRuntime(_ fixture: Fixture) throws -> NFUniversalSessionRuntime {
        let request = try NFSourceReviewExactAdapter.makeRequest(chunk: fixture.chunk, localeIdentifier: "en")
        return NFUniversalSessionRuntime(request: request)
    }

    func testSourceCitationRequiresAcknowledgedCommitAndFixedRouteSurvivesEndAndSourceChanges() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "NFCommittedCitation-\(UUID())")
        let backup = folder.appendingPathExtension("backup")
        defer { try? FileManager.default.removeItem(at: folder); try? FileManager.default.removeItem(at: backup) }
        let repository = NFLocalSessionRepository(url: folder.appending(path: "local.json"))
        let f = try fixture(repository: repository); defer { _ = f.container }
        let runtime = try sourceRuntime(f)
        XCTAssertNil(runtime.committedCitationContext(store: f.store))
        runtime.selfCheckReflection = "The force opposes the displacement."
        XCTAssertTrue(runtime.checkpointDraft(store: f.store))
        XCTAssertNil(runtime.committedCitationContext(store: f.store))
        runtime.submitInline(store: f.store)
        XCTAssertEqual(runtime.stage, .selfCheckComparison)
        XCTAssertTrue(runtime.selfCheckReferenceRevealed)
        XCTAssertNil(runtime.committedCitationContext(store: f.store), "Revealing a comparison is not an acknowledged answer")
        runtime.selfCheckRating = .matched
        try FileManager.default.moveItem(at: folder, to: backup)
        try Data("blocked directory".utf8).write(to: folder)
        runtime.saveSelfCheck(store: f.store)
        XCTAssertTrue(runtime.hasPreparedCommit)
        XCTAssertTrue(f.store.attempts.isEmpty)
        XCTAssertNil(runtime.committedCitationContext(store: f.store))
        try FileManager.default.removeItem(at: folder)
        try FileManager.default.moveItem(at: backup, to: folder)
        runtime.retrySaving(store: f.store)
        XCTAssertEqual(runtime.stage, .feedback)
        let context = try XCTUnwrap(runtime.committedCitationContext(store: f.store))
        let citation = try XCTUnwrap(context.citations.first)
        let route = try XCTUnwrap(context.route(for: citation.id))
        XCTAssertEqual(route.attemptID, f.store.attempts.first?.id)
        XCTAssertNil(context.route(for: "citation.not-in-the-original-question"))
        XCTAssertEqual(f.store.historyCitationPresentation(route: route).currentExcerpt, f.chunk.text)
        let original = try NFImmutableAttemptRecordSnapshot.encoded(NFImmutableAttemptRecordSnapshot(try XCTUnwrap(f.store.attempts.first)))
        XCTAssertEqual(f.store.attempts.first?.evidenceWeight, 0)
        runtime.next(store: f.store)
        XCTAssertEqual(runtime.stage, .summary)
        XCTAssertNil(runtime.committedCitationContext(store: f.store))
        XCTAssertEqual(f.store.historyCitationPresentation(route: route).currentExcerpt, f.chunk.text)
        f.chunkRecord.text = "This changed source must not be substituted for the original citation."
        try f.container.mainContext.save(); f.store.reload()
        let changed = f.store.historyCitationPresentation(route: route)
        XCTAssertEqual(changed.availability, .changedSource)
        XCTAssertNil(changed.currentExcerpt); XCTAssertEqual(changed.savedExcerpt, f.chunk.text)
        f.container.mainContext.delete(f.document); f.container.mainContext.delete(f.chunkRecord)
        try f.container.mainContext.save(); f.store.reload()
        let missing = f.store.historyCitationPresentation(route: route)
        XCTAssertEqual(missing.availability, .missingSource)
        XCTAssertEqual(missing.savedExcerpt, f.chunk.text)
        XCTAssertEqual(try NFImmutableAttemptRecordSnapshot.encoded(NFImmutableAttemptRecordSnapshot(try XCTUnwrap(f.store.attempts.first))), original)
        runtime.releaseWriter()
    }

    func testAutomaticallyScoredCitedQuestionUsesAcknowledgedRouteAndRefusesUnpinnedExcerpt() throws {
        let f = try fixture(); defer { _ = f.container }
        let fact = NFExerciseGroundingFact(id: "fact.pendulum-restoring-force",
            statement: "Which direction does the restoring force act relative to displacement?",
            expectedAnswer: "The restoring force opposes displacement.", acceptedAlternatives: [], citationIDs: [f.chunk.id])
        let exercise = try NFFallbackExerciseGenerator.generate(.init(seed: 20260905, index: 0,
            lab: .retrieval, purpose: .documentPractice, localeIdentifier: "en",
            sourceContext: .init(materialTitle: f.chunk.sourceName,
                sourceDocumentIDs: [f.chunk.documentID.uuidString], sourceChunkIDs: [f.chunk.id], groundingFacts: [fact]),
            preferredAssessmentMechanicID: "fixture.fallback-variant-4"))
        XCTAssertFalse(exercise.citations.isEmpty)
        var request = SessionRequest(lab: .retrieval, source: .focused, seed: exercise.seed,
            localeIdentifier: "en", evidenceClass: .documentPractice, requestedItemCount: 1, isTimed: false)
        request.localSessionID = request.id
        request.localCheckpoint = try NFLocalItemCheckpoint.initial(request: request, exercise: exercise,
            slotID: UUID(), attemptID: UUID(), at: Date(timeIntervalSince1970: 1_700_000_000))
        let runtime = NFUniversalSessionRuntime(request: request)
        XCTAssertNil(runtime.unavailableReason)
        XCTAssertTrue(runtime.checkpointDraft(store: f.store))
        runtime.resume()
        runtime.acknowledgePresented()
        XCTAssertFalse(runtime.isPaused)
        XCTAssertNil(runtime.committedCitationContext(store: f.store))
        guard case .singleChoice(let schema) = exercise.interaction else { return XCTFail("Expected the authored source-recognition fixture") }
        runtime.singleChoiceID = schema.correctOptionID
        runtime.submitInline(store: f.store)
        XCTAssertEqual(runtime.stage, .feedback)
        let context = try XCTUnwrap(runtime.committedCitationContext(store: f.store))
        let route = try XCTUnwrap(context.route(for: try XCTUnwrap(context.citations.first?.id)))
        XCTAssertEqual(f.store.attempts.first?.id, route.attemptID)
        let source = f.store.historyCitationPresentation(route: route)
        XCTAssertEqual(source.availability, .unverifiedRevision, "Old generated citations do not pin a source digest")
        XCTAssertNil(source.currentExcerpt); XCTAssertNil(source.savedExcerpt)
        runtime.releaseWriter()
    }

    func testLaterProtectedMarkerRevokesLiveCitationTitlesAndAlreadySelectedSheetContent() throws {
        let f = try fixture(); defer { _ = f.container }
        let runtime = try sourceRuntime(f)
        runtime.selfCheckReflection = "The restoring force opposes the original displacement."
        XCTAssertTrue(runtime.checkpointDraft(store: f.store))
        runtime.submitInline(store: f.store); runtime.selfCheckRating = .partiallyMatched
        runtime.saveSelfCheck(store: f.store)
        let context = try XCTUnwrap(runtime.committedCitationContext(store: f.store))
        let route = try XCTUnwrap(context.route(for: try XCTUnwrap(context.citations.first?.id)))
        let original = try NFImmutableAttemptRecordSnapshot.encoded(NFImmutableAttemptRecordSnapshot(try XCTUnwrap(f.store.attempts.first)))
        var archive = f.store.localSessions.archive
        archive.withheldProtectedConflictAttemptIDs = [route.attemptID]
        try f.store.localSessions.restorePredecessor(archive)
        XCTAssertNil(runtime.committedCitationContext(store: f.store))
        let restricted = f.store.historyCitationPresentation(route: route)
        XCTAssertEqual(restricted.availability, .protectedContent)
        XCTAssertNil(restricted.citation); XCTAssertNil(restricted.currentExcerpt); XCTAssertNil(restricted.savedExcerpt)
        XCTAssertEqual(try NFImmutableAttemptRecordSnapshot.encoded(NFImmutableAttemptRecordSnapshot(try XCTUnwrap(f.store.attempts.first))), original)
        runtime.releaseWriter()
    }

    func testDeletedCitationRouteCannotAttachToDifferentImportedSnapshotWithReusedIDs() throws {
        let f = try fixture(); defer { _ = f.container }
        let first = try sourceRuntime(f)
        first.selfCheckReflection = "The original restoring force opposes displacement."
        XCTAssertTrue(first.checkpointDraft(store: f.store))
        first.submitInline(store: f.store); first.selfCheckRating = .matched
        first.saveSelfCheck(store: f.store)
        let firstContext = try XCTUnwrap(first.committedCitationContext(store: f.store))
        let firstRoute = try XCTUnwrap(firstContext.route(for: try XCTUnwrap(firstContext.citations.first?.id)))
        let savedHistoryRoute = NFCommittedCitationRoute.savedHistory(attemptID: firstRoute.attemptID,
            citationID: firstRoute.citationID, sessionID: firstRoute.sessionID, exercise: first.exercise)
        XCTAssertEqual(savedHistoryRoute, firstRoute, "History pins the original detail just as live feedback does")
        XCTAssertEqual(f.store.historyCitationPresentation(route: firstRoute).currentExcerpt, f.chunk.text)
        first.releaseWriter()
        let original = try XCTUnwrap(f.store.attempts.first { $0.id == firstRoute.attemptID })
        try f.store.localSessions.removeReferences(attemptIDs: [original.id])
        f.container.mainContext.delete(original)
        try f.container.mainContext.save(); f.store.reload()
        XCTAssertEqual(f.store.historyCitationPresentation(route: firstRoute).availability, .unavailableCitation)

        // A supported portable archive is allowed to contain this UUID again
        // after deletion. Its distinct retained source must not replace the
        // content of a sheet still carrying the first acknowledged route.
        let donor = try fixture(); defer { _ = donor.container }
        let replacementText = "The silver pendulum loses energy because damping converts its motion into heat."
        let changedChunk = NFSourceChunk(id: f.chunk.id, documentID: f.chunk.documentID,
            documentVersion: f.chunk.documentVersion, sourceName: "Replacement damping notes",
            locator: f.chunk.locator, text: replacementText,
            contentHash: String(AdaptiveEngine.fnv1a64(replacementText), radix: 16), ordinal: 0, language: "en")
        donor.document.filename = changedChunk.sourceName
        donor.chunkRecord.sourceName = changedChunk.sourceName
        donor.chunkRecord.text = replacementText; donor.chunkRecord.contentHash = changedChunk.contentHash
        try donor.container.mainContext.save(); donor.store.reload()
        let replacementRequest = try NFSourceReviewExactAdapter.makeRequest(chunk: changedChunk,
            localeIdentifier: "en", sessionID: UUID(), attemptID: firstRoute.attemptID)
        let replacement = NFUniversalSessionRuntime(request: replacementRequest)
        replacement.selfCheckReflection = "Damping turns motion into heat."
        XCTAssertTrue(replacement.checkpointDraft(store: donor.store))
        replacement.submitInline(store: donor.store); replacement.selfCheckRating = .matched
        replacement.saveSelfCheck(store: donor.store)
        let replacementContext = try XCTUnwrap(replacement.committedCitationContext(store: donor.store))
        let newRoute = try XCTUnwrap(replacementContext.route(for: firstRoute.citationID))
        XCTAssertEqual(newRoute.attemptID, firstRoute.attemptID)
        XCTAssertEqual(newRoute.citationID, firstRoute.citationID)
        XCTAssertNotEqual(newRoute.sessionID, firstRoute.sessionID)
        XCTAssertNotEqual(newRoute.exerciseDigest, firstRoute.exerciseDigest)
        replacement.releaseWriter()
        let exports = try NFDataExportService.makeExports(from: donor.store)
        defer { if let first = exports.first { try? FileManager.default.removeItem(at: first.deletingLastPathComponent()) } }
        let archive = try XCTUnwrap(exports.first { $0.lastPathComponent == "NeuroForge-Full-Archive.json" })
        _ = try NFDataArchiveRestoreService.restore(archiveAt: archive, into: f.store, policy: .replaceAll)
        XCTAssertEqual(f.store.attempts.count, 1)
        XCTAssertEqual(f.store.historyCitationPresentation(route: newRoute).currentExcerpt, replacementText)

        let oldDigestOnly = NFCommittedCitationRoute(attemptID: newRoute.attemptID, citationID: newRoute.citationID,
            sessionID: newRoute.sessionID, exerciseDigest: firstRoute.exerciseDigest)
        let oldSessionOnly = NFCommittedCitationRoute(attemptID: newRoute.attemptID, citationID: newRoute.citationID,
            sessionID: firstRoute.sessionID, exerciseDigest: newRoute.exerciseDigest)
        let missingDigest = NFCommittedCitationRoute(attemptID: newRoute.attemptID, citationID: newRoute.citationID,
            sessionID: newRoute.sessionID, exerciseDigest: "")
        for stale in [firstRoute, savedHistoryRoute, oldDigestOnly, oldSessionOnly, missingDigest] {
            let unavailable = f.store.historyCitationPresentation(route: stale)
            XCTAssertEqual(unavailable.availability, .unavailableCitation)
            XCTAssertNil(unavailable.citation); XCTAssertNil(unavailable.currentExcerpt); XCTAssertNil(unavailable.savedExcerpt)
        }
        var imported = f.store.localSessions.archive
        imported.withheldProtectedConflictAttemptIDs = [firstRoute.attemptID]
        try f.store.localSessions.restorePredecessor(imported)
        let protected = f.store.historyCitationPresentation(route: firstRoute)
        XCTAssertEqual(protected.availability, .protectedContent, "Protection must precede even a stale route identity failure")
        XCTAssertNil(protected.citation); XCTAssertNil(protected.currentExcerpt); XCTAssertNil(protected.savedExcerpt)
    }

    func testQueuePagesPreserveExactIDsAndProtectedRowsWithoutUnboundedInitialPresentation() throws {
        let f = try fixture(); defer { _ = f.container }
        var records: [AttemptRecord] = []
        for index in 0..<103 {
            let record = AttemptRecord(sessionID: UUID(), lab: .mentalMath, itemID: "synthetic.saved.\(index)",
                prompt: "Private saved prompt number \(index)", response: "An original saved response", correctAnswer: "A retained result",
                isCorrect: true, confidence: .certain, evidenceClass: .practice, source: .focused)
            record.id = UUID(uuidString: String(format: "8CA70000-0000-0000-0001-%012d", index))!
            f.container.mainContext.insert(record); records.append(record)
        }
        try f.container.mainContext.save(); f.store.reload()
        var archive = f.store.localSessions.archive
        archive.withheldProtectedConflictAttemptIDs = records.filter { $0.id == records[49].id || $0.id == records[99].id }.map(\.id)
        try f.store.localSessions.restorePredecessor(archive)
        var count = NFReviewQueuePagination.pageSize
        let first = NFReviewQueuePagination.visible(records, through: count)
        XCTAssertEqual(first.map(\.id), Array(records.prefix(50)).map(\.id))
        XCTAssertFalse(first.map { f.store.reviewQueueSavedPresentation(for: $0).title }.contains(records[49].prompt))
        count = NFReviewQueuePagination.nextCount(current: count, total: records.count)
        let second = NFReviewQueuePagination.visible(records, through: count)
        XCTAssertEqual(second.count, 100)
        XCTAssertEqual(second.prefix(first.count).map(\.id), first.map(\.id))
        XCTAssertFalse(second.map { f.store.reviewQueueSavedPresentation(for: $0).title }.contains(records[99].prompt))
        count = NFReviewQueuePagination.nextCount(current: count, total: records.count)
        XCTAssertEqual(NFReviewQueuePagination.visible(records, through: count).map(\.id), records.map(\.id))
        XCTAssertEqual(NFReviewQueuePagination.nextCount(current: count, total: records.count), 103)
        XCTAssertEqual(NFReviewQueuePagination.nextCount(current: Int.max, total: Int.max), Int.max)
        XCTAssertTrue(NFReviewQueuePagination.visible([UUID](), through: Int.min).isEmpty)
        XCTAssertEqual(Set(records.map(\.id)).count, 103)
        XCTAssertTrue(records.allSatisfy { $0.response == "An original saved response" })
        // Deferred memory IDs use the same bounded prefix and retain their own
        // identities; paging cannot turn a hidden target into a fresh question.
        let deferredIDs = (0..<103).map { "deferred.memory.\($0)" }
        XCTAssertEqual(Array(NFReviewQueuePagination.visible(deferredIDs, through: 50)), Array(deferredIDs.prefix(50)))
        XCTAssertEqual(Array(NFReviewQueuePagination.visible(deferredIDs, through: count)), deferredIDs)
    }
}


@MainActor
final class EditorialCommitCaptureTests: XCTestCase {
    private struct Fixture {
        let store: AppStore
        let container: ModelContainer
        let runtime: NFUniversalSessionRuntime
    }
    private func fixture(demandAttached: Bool = false) throws -> Fixture {
        let container = try ModelContainer(for: Schema(NFSchemaV1.models),
            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let profile = UserProfileRecord(draft: OnboardingDraft()); profile.dayBoundaryHour = 4
        container.mainContext.insert(profile); try container.mainContext.save()
        let store = AppStore(context: container.mainContext, localSessionRepository: NFLocalSessionRepository(),
            allowsSharedWidgetPublishing: false)
        var exercise = try NFFallbackExerciseGenerator.generate(.init(seed: 991, index: 0, lab: .mentalMath,
            purpose: .practice, localeIdentifier: "en", preferredAssessmentMechanicID: "fixture.fallback-variant-0"))
        if demandAttached {
            let metadata = try XCTUnwrap(exercise.contractMetadata)
            let demand = NFEditorialDemandRecord(objectiveID: metadata.objectiveID, familyID: metadata.familyID,
                structureID: metadata.structureID, semanticFingerprint: metadata.semanticFingerprint,
                editorialBand: .b1, demandVector: .init(reasoningSteps: 1, quantityDomain: ["fixture": "exact arithmetic"],
                    representationMappings: ["numeric"], misconceptionClasses: [], abstraction: "concrete",
                    relevantGivens: 2, irrelevantGivens: 0, missingGivens: 0,
                    scaffoldConditionID: "essential-only", prerequisiteConceptIDs: []),
                bandContractVersion: "synthetic-admission-test.v1", calibrationStatus: .editorial, calibrationVersion: nil,
                independentEligible: true, protectedEligible: false, assistancePolicyID: "scratchpad-permitted.v1",
                answerContractVersion: "synthetic-answer.v1", expectedDurationRange: nil,
                representationIDs: ["numeric"], prerequisiteObjectiveIDs: [])
            var raw = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(exercise)) as? [String: Any])
            var contract = try XCTUnwrap(raw["contractMetadata"] as? [String: Any])
            contract["editorialDemand"] = try JSONSerialization.jsonObject(with: JSONEncoder().encode(demand))
            contract["reviewStatus"] = "Reviewed" // A prose assertion is deliberately not an admission receipt.
            raw["contractMetadata"] = contract
            exercise = try JSONDecoder().decode(NFExercise.self, from: JSONSerialization.data(withJSONObject: raw))
        }
        var request = SessionRequest(lab: .mentalMath, source: .focused, seed: 991, localeIdentifier: "en",
            requestedItemCount: 1, isTimed: false, timingCondition: .init(.untimed))
        request.localCheckpoint = try .initial(request: request, exercise: exercise, slotID: UUID(), attemptID: UUID(),
            at: Date().addingTimeInterval(-5))
        request.localSessionID = request.id; request.freshlyAcceptedLaunch = true
        let runtime = NFUniversalSessionRuntime(request: request)
        XCTAssertTrue(runtime.checkpointDraft(store: store)); runtime.resume(); runtime.acknowledgePresented()
        guard case let .numeric(schema) = runtime.exercise.interaction else { throw NFLocalSessionRepository.RepositoryError.corruptSnapshot }
        runtime.numericValue = String(schema.answer.value); runtime.numericUnit = schema.answer.canonicalUnit ?? ""
        runtime.chooseConfidence(.fairlyConfident)
        runtime.submitInline(store: store)
        XCTAssertEqual(runtime.stage, .feedback); XCTAssertNil(runtime.saveError)
        XCTAssertEqual(store.attempts.count, 1)
        return .init(store: store, container: container, runtime: runtime)
    }

    func testNewActualCommitCapturesAcceptedIdentityScoreAndConditionsWithoutBandAuthority() throws {
        let f = try fixture(); defer { f.runtime.releaseWriter(); _ = f.container }
        let record = try XCTUnwrap(f.store.attempts.first)
        let snapshot = try XCTUnwrap(f.store.localSessions.archive.snapshots.first)
        let capture = try XCTUnwrap(snapshot.editorialCapture)
        let slot = try XCTUnwrap(f.store.localSessions.archive.selectionLedger?.slots[capture.slotID])
        XCTAssertTrue(capture.isSupported)
        XCTAssertEqual(capture.attemptID, record.id); XCTAssertEqual(capture.sessionID, record.sessionID)
        XCTAssertEqual(capture.originalRecordDeviceID, record.deviceID)
        XCTAssertEqual(capture.ownerDeviceID, f.store.localSessions.ownerDeviceID)
        XCTAssertEqual(capture.sessionOrdinal, slot.pathOrdinal)
        XCTAssertEqual(capture.exerciseDigest, try NFLocalItemCheckpoint.digest(f.runtime.exercise))
        XCTAssertEqual(capture.originalResponseDigest, NFReservationSnapshot.digest(Data(record.response.utf8)))
        XCTAssertEqual(capture.originalCredit, record.deterministicCredit)
        XCTAssertEqual(capture.originalOutcome, f.runtime.lastResult?.outcome)
        XCTAssertEqual(capture.rubricComponents, f.runtime.lastResult?.components)
        XCTAssertEqual(capture.conditions.contentLocale, "en"); XCTAssertEqual(capture.conditions.timingMode, .untimed)
        XCTAssertNil(capture.conditions.toolConditionID); XCTAssertNil(capture.conditions.inputEditorVersion)
        XCTAssertEqual(capture.confidenceProbability, ConfidenceLevel.fairlyConfident.probability)
        XCTAssertEqual(capture.confidenceMappingVersion, "confidenceCategoricalV1")
        XCTAssertEqual(capture.authorityAtCommit, NFEditorialObservationAdmissionRegistry.unavailable)
        XCTAssertNil(f.store.effectiveAttemptDTO(record).editorialObservation)
        XCTAssertNil(snapshot.exercise.contractMetadata?.editorialDemand)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let original = try encoder.encode(capture)
        f.runtime.next(store: f.store)
        XCTAssertEqual(try encoder.encode(try XCTUnwrap(f.store.localSessions.editorialSnapshot(for: record.id)?.editorialCapture)), original)
        XCTAssertEqual(NFEditorialCommitCapturePolicy.project(snapshot: snapshot, record: .init(record),
            effectiveCredit: 0.5, excluded: false).exclusionReason, NFEditorialObservationAdmissionRegistry.unavailable)
        XCTAssertEqual(record.deterministicCredit, 1, "A derived score input cannot edit the original receipt")
    }

    func testDemandAndForgedAdmissionStringsCannotTurnNewPracticeIntoReviewedEvidence() throws {
        let f = try fixture(demandAttached: true); defer { f.runtime.releaseWriter(); _ = f.container }
        let record = try XCTUnwrap(f.store.attempts.first)
        var snapshot = try XCTUnwrap(f.store.localSessions.archive.snapshots.first)
        XCTAssertTrue(try XCTUnwrap(snapshot.exercise.contractMetadata?.editorialDemand).hasRequiredIdentity)
        let capture = try XCTUnwrap(snapshot.editorialCapture)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(capture)) as? [String: Any])
        object["authorityAtCommit"] = "admitted"
        snapshot.editorialCapture = try JSONDecoder().decode(NFEditorialCommitCapture.self, from: JSONSerialization.data(withJSONObject: object))
        let result = NFEditorialCommitCapturePolicy.project(snapshot: snapshot, record: .init(record), effectiveCredit: 1, excluded: false)
        XCTAssertNil(result.observation); XCTAssertEqual(result.exclusionReason, NFEditorialObservationAdmissionRegistry.unavailable)
        XCTAssertNil(f.store.effectiveAttemptDTO(record).editorialObservation)
        object["schemaVersion"] = 999
        snapshot.editorialCapture = try JSONDecoder().decode(NFEditorialCommitCapture.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertEqual(NFEditorialCommitCapturePolicy.project(snapshot: snapshot, record: .init(record),
            effectiveCredit: 1, excluded: false).exclusionReason, "unverifiedCommitProvenance")
    }

    func testCapturedDaySurvivesTravelAndSpringBoundaryWithoutRelabeling() throws {
        var toronto = Calendar(identifier: .gregorian); toronto.timeZone = try XCTUnwrap(TimeZone(identifier: "America/Toronto"))
        let instant = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-03-08T08:30:00Z"))
        let day = try XCTUnwrap(NFEditorialCapturedDay.capture(at: instant, dayBoundaryHour: 4, calendar: toronto))
        XCTAssertEqual(day.key, "2026-03-08")
        XCTAssertEqual(day.boundaryStart, ISO8601DateFormatter().date(from: "2026-03-08T08:00:00Z"))
        XCTAssertEqual(day.nextBoundary, ISO8601DateFormatter().date(from: "2026-03-09T08:00:00Z"))
        var tokyo = Calendar(identifier: .gregorian); tokyo.timeZone = try XCTUnwrap(TimeZone(identifier: "Asia/Tokyo"))
        let later = try XCTUnwrap(NFEditorialCapturedDay.capture(at: instant.addingTimeInterval(43_200), dayBoundaryHour: 4, calendar: tokyo))
        XCTAssertNotEqual(day.timeZoneIdentifier, later.timeZoneIdentifier)
        XCTAssertEqual(try JSONDecoder().decode(NFEditorialCapturedDay.self, from: JSONEncoder().encode(day)), day)
        XCTAssertNil(NFEditorialCapturedDay.capture(at: .init(timeIntervalSince1970: .nan), dayBoundaryHour: 4, calendar: toronto))
    }

    func testLegacySnapshotsAndProtectedOrExcludedRecordsCannotAcquireObservation() throws {
        let f = try fixture(); defer { f.runtime.releaseWriter(); _ = f.container }
        let record = try XCTUnwrap(f.store.attempts.first)
        let captured = try XCTUnwrap(f.store.localSessions.archive.snapshots.first)
        let legacy = NFLocalAttemptSnapshot(attemptID: record.id, exercise: captured.exercise)
        let original = try NFImmutableAttemptRecordSnapshot.encoded(NFImmutableAttemptRecordSnapshot(record))
        XCTAssertEqual(NFEditorialCommitCapturePolicy.project(snapshot: legacy, record: .init(record),
            effectiveCredit: 1, excluded: false).exclusionReason, "missingCommitProvenance")
        XCTAssertEqual(NFEditorialCommitCapturePolicy.project(snapshot: captured, record: .init(record),
            effectiveCredit: 1, excluded: true).exclusionReason, "effectiveEvidenceExcluded")
        var archive = f.store.localSessions.archive
        archive.withheldProtectedConflictAttemptIDs = [record.id]
        try f.store.localSessions.restorePredecessor(archive)
        XCTAssertNil(f.store.effectiveAttemptDTO(record).editorialObservation)
        XCTAssertFalse(f.store.localSessions.exportArchive.snapshots.contains { $0.attemptID == record.id })
        XCTAssertNotNil(f.store.localSessions.editorialSnapshot(for: record.id)?.editorialCapture)
        XCTAssertEqual(try NFImmutableAttemptRecordSnapshot.encoded(NFImmutableAttemptRecordSnapshot(record)), original)
    }

    func testColdRetryAfterLocalCaptureRetainsOriginalSubmissionAndRawDeviceFields() throws {
        let f = try fixture(); defer { f.runtime.releaseWriter(); _ = f.container }
        let original = try XCTUnwrap(f.store.attempts.first)
        let capture = try XCTUnwrap(f.store.localSessions.editorialSnapshot(for: original.id)?.editorialCapture)
        let result = try XCTUnwrap(f.runtime.lastResult)
        let response = try JSONDecoder().decode(NFExerciseResponse.self, from: Data(original.response.utf8))
        // Model the actual two-store boundary: the acknowledged local bytes
        // survive reopening while the core store contains no attempt yet.
        let folder = FileManager.default.temporaryDirectory.appending(path: "NFEditorialColdRetry-\(UUID())")
        defer { try? FileManager.default.removeItem(at: folder) }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let file = folder.appending(path: "local.json")
        try JSONEncoder().encode(f.store.localSessions.archive).write(to: file)
        let repository = NFLocalSessionRepository(url: file, ownerDeviceID: capture.ownerDeviceID)
        XCTAssertNil(repository.loadError)
        let container = try ModelContainer(for: Schema(NFSchemaV1.models),
            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let store = AppStore(context: container.mainContext, localSessionRepository: repository,
            allowsSharedWidgetPublishing: false)
        XCTAssertTrue(store.attempts.isEmpty)
        try store.saveExerciseAttempt(attemptID: original.id, sessionID: original.sessionID,
            exercise: f.runtime.exercise, response: response, result: result,
            confidence: original.confidenceRaw.flatMap(ConfidenceLevel.init(rawValue:)),
            shownAt: original.shownAt, activeDuration: original.activeDurationSeconds,
            source: .focused, hintCount: original.hintCount, inputMode: original.inputModeRaw,
            interruptionCount: original.interruptionCount, revisionCount: original.revisionCount,
            accommodationFlags: original.accommodationFlagsRaw.split(separator: ",").map(String.init), wasTimed: original.wasTimed)
        let committed = try XCTUnwrap(store.attempts.first)
        XCTAssertEqual(committed.submittedAt, capture.submittedAt)
        XCTAssertEqual(committed.deviceID, capture.originalRecordDeviceID)
        XCTAssertEqual(try NFImmutableAttemptRecordSnapshot.encoded(NFImmutableAttemptRecordSnapshot(committed)),
            try NFImmutableAttemptRecordSnapshot.encoded(NFImmutableAttemptRecordSnapshot(original)))
        XCTAssertEqual(repository.editorialSnapshot(for: original.id)?.editorialCapture, capture)
        XCTAssertEqual(NFEditorialCommitCapturePolicy.project(snapshot: repository.editorialSnapshot(for: original.id),
            record: .init(committed), effectiveCredit: 1, excluded: false).exclusionReason,
            NFEditorialObservationAdmissionRegistry.unavailable)
    }

    func testCaptureAndExactSnapshotPublishAtomicallyAndImportCannotBackfillLegacyProvenance() throws {
        let f = try fixture(); defer { f.runtime.releaseWriter(); _ = f.container }
        let snapshot = try XCTUnwrap(f.store.localSessions.archive.snapshots.first)
        let capture = try XCTUnwrap(snapshot.editorialCapture)
        let folder = FileManager.default.temporaryDirectory.appending(path: "NFEditorialCapture-\(UUID())")
        defer { try? FileManager.default.removeItem(at: folder) }
        let repository = NFLocalSessionRepository(url: folder.appending(path: "local.json"))
        try Data("blocked parent".utf8).write(to: folder)
        XCTAssertThrowsError(try repository.retainSnapshot(attemptID: snapshot.attemptID, exercise: snapshot.exercise, editorialCapture: capture))
        XCTAssertTrue(repository.archive.snapshots.isEmpty)
        try FileManager.default.removeItem(at: folder)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try repository.retainSnapshot(attemptID: snapshot.attemptID, exercise: snapshot.exercise, editorialCapture: capture)
        let reopened = NFLocalSessionRepository(url: folder.appending(path: "local.json"))
        XCTAssertEqual(reopened.editorialSnapshot(for: snapshot.attemptID)?.editorialCapture, capture)
        let legacy = NFLocalSessionRepository()
        try legacy.retainSnapshot(attemptID: snapshot.attemptID, exercise: snapshot.exercise)
        var incoming = NFLocalSessionRepository.Archive(); incoming.snapshots = [snapshot]
        XCTAssertThrowsError(try legacy.importArchive(incoming))
        XCTAssertNil(legacy.archive.snapshots.first?.editorialCapture)
    }
}


@MainActor
final class EditorialLiveControllerPersistenceTests: XCTestCase {
    private let seed: UInt64 = 8840
    private let owner = UUID(uuidString: "E1477E0C-EF20-4BB4-BC90-C8297E387A00")!
    private let profileID = UUID(uuidString: "9BF814F1-40EC-4CBE-A4B4-F990FC36AFD5")!
    private func root() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appending(path: "NFEditorialController-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }
    private func template() -> SessionRequest {
        SessionRequest(lab: .mentalMath, source: .focused, seed: seed, localeIdentifier: "en",
            field: .general, targetDifficulty: 0.5, requestedItemCount: 8,
            isTimed: false, timingCondition: .init(.untimed))
    }
    /// These demands are synthetic policy fixtures, not approval of any shipped
    /// item. Exact physical exercises/keys remain the real bank materialization.
    private func catalog(requestOverride: SessionRequest? = nil, fluencyEligible: Bool = false, activityID: String? = nil) throws -> NFEditorialAdmissionContext {
        let request = requestOverride ?? template()
        var entries: [NFEditorialAdmissionEntry] = []
        var seen: Set<String> = []
        for questionID in NFOfflineQuestionBank.rotationBank.questionIDs(for: .mentalMath) {
            guard let ordinal = NFOfflineQuestionBank.ordinal(forQuestionID: questionID, lab: .mentalMath) else { continue }
            let exercise = NFDeterministicSessionExerciseFactory.makeExercise(
                request: request.launchOnly(offlineQuestionOrdinals: [ordinal]), index: 0, assessmentDescriptor: nil)
            guard exercise.availabilityReason == nil, case .numeric = exercise.interaction,
                  let metadata = exercise.contractMetadata, seen.insert(metadata.semanticFingerprint).inserted else { continue }
            if let activityID {
                guard NFEditorialCatalogScope(catalogVersion: NFDefaultContentCatalog.version,
                    activityID: activityID, field: .general).matches(exercise) else { continue }
            }
            let band: NFEditorialBand = entries.count < 12 ? .b1 : .b2
            var demand = NFEditorialDemandRecord(objectiveID: "QA.controller.arithmetic", familyID: "QA.controller.numeric",
                structureID: "QA.structure.\(entries.count % 2)", semanticFingerprint: metadata.semanticFingerprint,
                editorialBand: band, demandVector: .init(reasoningSteps: band.ordinal,
                    quantityDomain: ["source": "synthetic policy fixture over exact retained key"],
                    representationMappings: ["numeric"], misconceptionClasses: [], abstraction: "concrete",
                    relevantGivens: 2, irrelevantGivens: 0, missingGivens: 0,
                    scaffoldConditionID: "essential-only", prerequisiteConceptIDs: []),
                bandContractVersion: "QA.controller-band.v1", calibrationStatus: .editorial, calibrationVersion: nil,
                independentEligible: true, protectedEligible: false,
                assistancePolicyID: NFEditorialNativeProtocol.toolConditionID,
                answerContractVersion: "QA.exact-native.v1", expectedDurationRange: .init(minimumSeconds: 10, maximumSeconds: 40),
                representationIDs: ["numeric"], prerequisiteObjectiveIDs: [])
            demand.reviewedFluencyEligible = fluencyEligible
            entries.append(.init(id: "QA.entry.\(String(format: "%02d", entries.count))", bankQuestionID: questionID,
                exerciseDigest: try NFLocalItemCheckpoint.digest(exercise), scorerVersion: NFExerciseScoringEngine.scoringVersion,
                lab: .mentalMath, contentLocale: "en", demand: demand))
            if entries.count == 24 { break }
        }
        XCTAssertEqual(entries.count, 24)
        return .init(version: "QA.trusted-in-process-controller.v1", entries: entries)
    }
    private func container(_ root: URL, persistent: Bool = false) throws -> ModelContainer {
        let schema = Schema(NFSchemaV1.models)
        return try ModelContainer(for: schema, configurations: persistent
            ? ModelConfiguration("EditorialController", schema: schema, url: root.appending(path: "core.store"), cloudKitDatabase: .none)
            : ModelConfiguration(isStoredInMemoryOnly: true))
    }
    private func store(_ root: URL, context: ModelContext, admissions: NFEditorialAdmissionContext,
                       repositoryURL: URL? = nil) throws -> AppStore {
        if try context.fetch(FetchDescriptor<UserProfileRecord>()).isEmpty {
            let profile = UserProfileRecord(draft: OnboardingDraft()); profile.id = profileID
            context.insert(profile); try context.save()
        }
        let repository = NFLocalSessionRepository(url: repositoryURL ?? root.appending(path: "sessions-v1.json"),
            ownerDeviceID: owner, editorialAdmissions: admissions)
        return AppStore(context: context,
            nextDayEnhancementCache: NFNextDayEnhancementCache(rootURL: root.appending(path: "cache")),
            documentStorageRootURL: root.appending(path: "documents"), localSessionRepository: repository,
            adaptivePlanHistoryRepository: NFAdaptivePlanHistoryRepository(fileURL: root.appending(path: "history.json")),
            offlineQuestionRotation: NFOfflineQuestionRotation(store: NFMemoryOfflineQuestionRotationStateStore()),
            temporaryArtifactsRootURL: root, allowsSharedWidgetPublishing: false)
    }
    private func launch(_ store: AppStore, commandID: UUID = UUID()) throws -> NFUniversalSessionRuntime {
        XCTAssertTrue(store.beginSession(lab: .mentalMath, source: .focused, field: .general,
            targetDifficulty: 0.5, requestedItemCount: 8, seedOverride: seed,
            isTimed: false, timingCondition: .init(.untimed), launchLocaleIdentifier: "en", launchCommandID: commandID),
            store.lastErrorMessage ?? "launch failed")
        let request = try XCTUnwrap(store.activeSessionRequest)
        let runtime = NFUniversalSessionRuntime(request: request)
        XCTAssertTrue(runtime.checkpointDraft(store: store)); runtime.resume(); runtime.acknowledgePresented()
        return runtime
    }
    private func answer(_ runtime: NFUniversalSessionRuntime, store: AppStore, hint: Bool = false,
                        confidence: ConfidenceLevel = .fairlyConfident) throws {
        runtime.acknowledgePresented()
        guard case let .numeric(schema) = runtime.exercise.interaction else {
            throw NFLocalSessionRepository.RepositoryError.corruptSnapshot
        }
        if hint { runtime.requestHint(store: store) }
        runtime.numericValue = String(schema.answer.value)
        runtime.numericUnit = schema.answer.canonicalUnit ?? ""
        runtime.chooseConfidence(confidence); runtime.submitInline(store: store)
        XCTAssertEqual(runtime.stage, .feedback); XCTAssertNil(runtime.saveError)
    }
    private func receipt(_ store: AppStore) throws -> NFLocalAdaptiveItemReceipt {
        let run = try XCTUnwrap(store.localSessions.archive.sessions.first)
        return try XCTUnwrap(run.checkpoint.ordinaryReservationDecisionID.flatMap { store.localSessions.archive.adaptiveItemReceipts?[$0] })
    }

    func testReleasedEmptyRegistryKeepsActualBankLegacyAndCannotTrustSerializedPin() throws {
        let root = try root(); defer { try? FileManager.default.removeItem(at: root) }
        let container = try container(root); let store = try store(root, context: container.mainContext, admissions: .released)
        let runtime = try launch(store); defer { runtime.releaseWriter() }
        XCTAssertNil(runtime.request.ordinaryDelivery?.editorialPolicy)
        XCTAssertEqual(try receipt(store).schemaVersion, 2); XCTAssertNil(try receipt(store).editorialDecision)
        // The released bank includes several native mechanics. Exercise its
        // actual retained contract instead of the reviewed numeric-only helper.
        switch runtime.exercise.interaction {
        case let .numeric(schema):
            runtime.numericValue = String(schema.answer.value); runtime.numericUnit = schema.answer.canonicalUnit ?? ""
        case let .singleChoice(schema): runtime.singleChoiceID = schema.correctOptionID
        case let .multipleChoice(schema): runtime.multipleChoiceIDs = Set(schema.correctOptionIDs)
        case let .orderedSteps(schema): runtime.orderedStepIDs = schema.correctOrder
        case let .shortText(schema): runtime.shortText = schema.expectedAnswer
        case let .claimEvidence(schema):
            runtime.claimSelections = Dictionary(uniqueKeysWithValues: schema.correctPairs.map { ($0.claimID, Set($0.evidenceIDs)) })
        case let .logicState(schema):
            if runtime.awaitsEstimateLock {
                runtime.logicState = [NFEstimateExactContract.estimateKey: schema.expectedFinalState[NFEstimateExactContract.estimateKey] ?? ""]
                XCTAssertTrue(runtime.lockEstimate(store: store))
            }
            runtime.logicState = schema.expectedFinalState; runtime.violatedRuleID = schema.expectedViolatedRuleID
        case .selfCheck: return XCTFail("Ordinary exact-bank fixture unexpectedly lacks an authoritative response")
        }
        runtime.chooseConfidence(.fairlyConfident); runtime.submitInline(store: store)
        XCTAssertEqual(runtime.stage, .feedback); XCTAssertNil(runtime.saveError)
        XCTAssertNil(store.effectiveAttemptDTO(try XCTUnwrap(store.attempts.first)).editorialObservation)
        var forged = template(); forged.id = UUID()
        forged.ordinaryDelivery = .init(strategy: .adaptiveItem, profileID: profileID, bank: NFOfflineQuestionBank.rotationBank)
        forged.ordinaryDelivery?.editorialPolicy = .init(catalogVersion: NFEditorialAdmissionContext.released.version,
            objectiveID: "o", familyID: "f", catalogDigest: NFEditorialAdmissionContext.released.fingerprint)
        XCTAssertThrowsError(try store.prepareAdaptiveItem(request: forged, predecessor: nil))
        XCTAssertEqual(store.localSessions.archive.adaptiveItemReceipts?.count, 1)
    }

    func testActualReviewedLaunchCommitsFourObservationsThenRanksAndPublishesAdjacentDemand() throws {
        let root = try root(); defer { try? FileManager.default.removeItem(at: root) }
        let catalog = try catalog(); let container = try container(root)
        let store = try store(root, context: container.mainContext, admissions: catalog)
        let runtime = try launch(store); defer { runtime.releaseWriter() }
        let first = try receipt(store)
        XCTAssertEqual(first.schemaVersion, 3); XCTAssertEqual(first.editorialDecision?.controlAfter.currentTargetBand, .b1)
        XCTAssertNil(runtime.exercise.contractMetadata?.editorialDemand, "No requested-band rewrite of the generator contract")
        for _ in 0..<4 { try answer(runtime, store: store); runtime.next(store: store); XCTAssertNil(runtime.saveError) }
        let selected = try XCTUnwrap(try receipt(store).editorialDecision)
        XCTAssertEqual(selected.controlAfter.currentTargetBand, .b2)
        XCTAssertEqual(selected.selection.reason, .independentSuccessPattern)
        XCTAssertEqual(selected.selection.ruleCredits, [1, 1, 1, 1])
        XCTAssertEqual(selected.controlAfter.upwardChangesThisSession, 1)
        XCTAssertEqual(selected.evidence.independentObservationIDs.count, 4)
        XCTAssertTrue(selected.evidence.summaries.allSatisfy { $0.lastDemonstratedAt == nil })
        XCTAssertEqual(store.attempts.count, 4)
        XCTAssertEqual(store.localSessions.archive.selectionLedger?.slots.count, 5)
        XCTAssertEqual(try receipt(store).exerciseDigest, selected.admission.exerciseDigest)
        XCTAssertEqual(try receipt(store).plan.items.first?.questionID, selected.selection.candidateID)
        let observation = try XCTUnwrap(store.effectiveAttemptDTO(try XCTUnwrap(store.attempts.first)).editorialObservation)
        XCTAssertTrue(observation.assistanceKnown); XCTAssertNil(observation.confidence)
        XCTAssertNil(observation.conditions.latencyCalibrationVersion)
        XCTAssertTrue(selected.evidence.cleanSpeedObservationIDs.isEmpty)
    }

    func testKnownHelpAndConfidenceDoNotBecomeIndependentSuccessOrAutomaticChange() throws {
        let root = try root(); defer { try? FileManager.default.removeItem(at: root) }
        let container = try container(root); let store = try store(root, context: container.mainContext, admissions: catalog())
        let runtime = try launch(store); defer { runtime.releaseWriter() }
        for index in 0..<4 {
            try answer(runtime, store: store, hint: index < 2, confidence: .fairlyConfident)
            runtime.next(store: store)
        }
        let selected = try XCTUnwrap(try receipt(store).editorialDecision)
        XCTAssertEqual(selected.controlAfter.currentTargetBand, .b1)
        XCTAssertEqual(selected.evidence.independentObservationIDs.count, 2)
        XCTAssertEqual(selected.evidence.exclusions.values.filter { $0 == "assisted" }.count, 2)
        XCTAssertEqual(store.attempts.count, 4)
    }

    func testControllerAndChosenSnapshotSurviveDiskReopenWithoutResettingAllowance() throws {
        let root = try root(); defer { try? FileManager.default.removeItem(at: root) }
        let catalog = try catalog()
        var expected: NFLocalAdaptiveItemReceipt!
        var recordCount = 0
        do {
            let container = try container(root, persistent: true)
            let store = try store(root, context: container.mainContext, admissions: catalog)
            let runtime = try launch(store)
            for _ in 0..<4 { try answer(runtime, store: store); runtime.next(store: store) }
            runtime.pause(); XCTAssertTrue(runtime.checkpointDraft(store: store)); runtime.releaseWriter()
            expected = try receipt(store); recordCount = store.attempts.count
        }
        let container = try container(root, persistent: true)
        let store = try store(root, context: container.mainContext, admissions: catalog)
        XCTAssertNil(store.localSessions.loadError)
        XCTAssertEqual(try receipt(store), expected)
        XCTAssertEqual(store.attempts.count, recordCount)
        let saved = try XCTUnwrap(store.localSessions.archive.sessions.first)
        var request = saved.request; request.localCheckpoint = saved.checkpoint; request.localSessionID = saved.id
        let runtime = NFUniversalSessionRuntime(request: request); defer { runtime.releaseWriter() }
        XCTAssertTrue(runtime.checkpointDraft(store: store)); runtime.resume(); runtime.acknowledgePresented()
        XCTAssertEqual(try NFLocalItemCheckpoint.digest(runtime.exercise), expected.exerciseDigest)
        try answer(runtime, store: store); runtime.next(store: store)
        XCTAssertEqual(try receipt(store).editorialDecision?.controlAfter.upwardChangesThisSession, 1)
        XCTAssertEqual(try receipt(store).editorialDecision?.controlAfter.currentTargetBand, .b2)
    }

    func testCorrectionBetweenPrepareAndAcceptRejectsStaleChoiceThenRebuildsOnlyFutureControl() throws {
        let root = try root(); defer { try? FileManager.default.removeItem(at: root) }
        let container = try container(root); let store = try store(root, context: container.mainContext, admissions: catalog())
        let runtime = try launch(store); defer { runtime.releaseWriter() }
        for _ in 0..<3 { try answer(runtime, store: store); runtime.next(store: store) }
        try answer(runtime, store: store)
        let predecessor = try XCTUnwrap(store.localSessions.archive.sessions.first)
        let priorReceipt = try receipt(store)
        let before = store.localSessions.archive.offlineRotationLedger
        let prepared = try store.prepareAdaptiveItem(request: predecessor.request, predecessor: predecessor.checkpoint,
            command: try runtime.sessionWriterCommand())
        XCTAssertEqual(prepared.receipt.editorialDecision?.selection.deliveredBand, .b2)
        let original = try XCTUnwrap(store.attempts.first)
        let originalBytes = try NFImmutableAttemptRecordSnapshot.encoded(NFImmutableAttemptRecordSnapshot(original))
        try store.localSessions.appendDispositions([.init(id: "QA.corrected", attemptID: original.id.uuidString,
            revision: 1, policyVersion: NFHistoricalPracticeProjection.policyVersion, occurredAt: Date(),
            disposition: .excludedContentCorrection, reason: "Synthetic invalidation before acceptance",
            correctedDerivedCredit: nil, supersedesDispositionID: nil)])
        XCTAssertThrowsError(try store.acceptAdaptiveItem(prepared, checkpoint: prepared.checkpoint))
        XCTAssertEqual(store.localSessions.archive.offlineRotationLedger, before)
        XCTAssertEqual(try receipt(store), priorReceipt)
        XCTAssertEqual(try NFImmutableAttemptRecordSnapshot.encoded(NFImmutableAttemptRecordSnapshot(original)), originalBytes)
        let next = try store.prepareAdaptiveItem(request: predecessor.request, predecessor: predecessor.checkpoint,
            command: try runtime.sessionWriterCommand())
        XCTAssertEqual(next.receipt.editorialDecision?.selection.deliveredBand, .b1)
        XCTAssertEqual(next.receipt.editorialDecision?.evidence.independentObservationIDs.count, 3)
    }

    func testFailedPublicationLeavesNoControlOrConsumptionAndExactRetryReturnsAcceptedState() throws {
        let root = try root(); defer { try? FileManager.default.removeItem(at: root) }
        let blocked = root.appending(path: "blocked"); try Data("retain me".utf8).write(to: blocked)
        let container = try container(root); let store = try store(root, context: container.mainContext,
            admissions: catalog(), repositoryURL: blocked.appending(path: "sessions-v1.json"))
        let command = UUID()
        XCTAssertFalse(store.beginSession(lab: .mentalMath, source: .focused, field: .general,
            targetDifficulty: 0.5, requestedItemCount: 8, seedOverride: seed,
            isTimed: false, timingCondition: .init(.untimed), launchLocaleIdentifier: "en", launchCommandID: command))
        XCTAssertNil(store.localSessions.archive.offlineRotationLedger)
        XCTAssertNil(store.localSessions.archive.adaptiveItemReceipts)
        XCTAssertTrue(store.localSessions.archive.sessions.isEmpty)
        try FileManager.default.removeItem(at: blocked); try FileManager.default.createDirectory(at: blocked, withIntermediateDirectories: true)
        let runtime = try launch(store, commandID: command); defer { runtime.releaseWriter() }
        runtime.pause(); XCTAssertTrue(runtime.checkpointDraft(store: store)); runtime.releaseWriter()
        let run = try XCTUnwrap(store.localSessions.archive.sessions.first)
        let prepared = try store.prepareAdaptiveItem(request: run.request, predecessor: nil)
        let accepted = try store.acceptAdaptiveItem(prepared, checkpoint: prepared.checkpoint)
        XCTAssertEqual(accepted.checkpoint, run.checkpoint)
        XCTAssertEqual(store.localSessions.archive.adaptiveItemReceipts?.count, 1)
        XCTAssertEqual(try receipt(store).editorialDecision?.controlAfter.decisionOrdinal, 1)
    }

    func testPortableImportKeepsCapturedHistoryButCannotAcquireLocalEditorialAuthority() throws {
        let root = try root(); defer { try? FileManager.default.removeItem(at: root) }
        let catalog = try catalog(); let container = try container(root)
        let store = try store(root, context: container.mainContext, admissions: catalog)
        let runtime = try launch(store); defer { runtime.releaseWriter() }
        try answer(runtime, store: store)
        let snapshot = try XCTUnwrap(store.localSessions.archive.snapshots.first)
        let original = try XCTUnwrap(store.attempts.first)
        let foreign = NFLocalSessionRepository(ownerDeviceID: UUID(), editorialAdmissions: catalog)
        try foreign.importArchive(store.localSessions.exportArchive)
        XCTAssertNil(foreign.archive.adaptiveItemReceipts)
        let imported = try XCTUnwrap(foreign.editorialSnapshot(for: original.id))
        XCTAssertEqual(imported.editorialCapture, snapshot.editorialCapture)
        XCTAssertFalse(foreign.hasEditorialAuthority(for: try XCTUnwrap(imported.editorialCapture)))
        XCTAssertNil(NFEditorialCommitCapturePolicy.project(snapshot: imported, record: .init(original),
            effectiveCredit: 1, excluded: false, admissions: catalog,
            localAuthorityVerified: foreign.hasEditorialAuthority(for: try XCTUnwrap(imported.editorialCapture))).observation)
    }
}

extension EditorialLiveControllerPersistenceTests {
    func testControllerReceiptsDoNotDuplicateRawAnswersAndLinkedDeletionRetiresTheirRun() throws {
        let root = try root(); defer { try? FileManager.default.removeItem(at: root) }
        let container = try container(root); let store = try store(root, context: container.mainContext, admissions: catalog())
        let runtime = try launch(store)
        try answer(runtime, store: store); runtime.next(store: store); runtime.releaseWriter()
        let original = try XCTUnwrap(store.attempts.first)
        let all = try XCTUnwrap(store.localSessions.archive.adaptiveItemReceipts)
        let text = try String(decoding: JSONEncoder().encode(all), as: UTF8.self)
        XCTAssertFalse(text.contains("originalResponse"))
        XCTAssertFalse(text.contains("submittedValue"))
        let decision = try XCTUnwrap(try receipt(store).editorialDecision)
        XCTAssertNotNil(decision.observationDigests[original.id.uuidString])
        let rotation = store.localSessions.archive.offlineRotationLedger
        try store.localSessions.removeReferences(attemptIDs: [original.id])
        XCTAssertTrue(store.localSessions.archive.sessions.isEmpty)
        XCTAssertTrue(store.localSessions.archive.adaptiveItemReceipts?.isEmpty != false)
        XCTAssertTrue(store.localSessions.archive.snapshots.isEmpty)
        XCTAssertEqual(store.localSessions.archive.offlineRotationLedger, rotation)
    }

    func testUnknownControllerVersionAndChangedManifestCannotReinterpretSavedDecision() throws {
        let root = try root(); defer { try? FileManager.default.removeItem(at: root) }
        let catalog = try catalog(); let container = try container(root)
        let store = try store(root, context: container.mainContext, admissions: catalog)
        let runtime = try launch(store); runtime.releaseWriter()
        let original = try receipt(store)
        let bytes = try Data(contentsOf: root.appending(path: "sessions-v1.json"))
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: bytes) as? [String: Any])
        var sessions = try XCTUnwrap(object["sessions"] as? [[String: Any]])
        var request = try XCTUnwrap(sessions[0]["request"] as? [String: Any])
        var delivery = try XCTUnwrap(request["ordinaryDelivery"] as? [String: Any])
        var pin = try XCTUnwrap(delivery["editorialPolicy"] as? [String: Any])
        pin["controllerVersion"] = "future.controller.v99"; delivery["editorialPolicy"] = pin
        request["ordinaryDelivery"] = delivery; sessions[0]["request"] = request; object["sessions"] = sessions
        let futureFile = root.appending(path: "future.json")
        let futureBytes = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]); try futureBytes.write(to: futureFile)
        let future = NFLocalSessionRepository(url: futureFile, ownerDeviceID: owner, editorialAdmissions: catalog)
        XCTAssertEqual(future.archive.sessions.first?.status, .migrationRecovery)
        XCTAssertEqual(try Data(contentsOf: futureFile), futureBytes)
        XCTAssertEqual(future.archive.adaptiveItemReceipts?[original.decisionID], original)
        let changed = NFEditorialAdmissionContext(version: catalog.version, entries: Array(catalog.entries.dropLast()))
        let reopened = NFLocalSessionRepository(url: root.appending(path: "sessions-v1.json"), ownerDeviceID: owner, editorialAdmissions: changed)
        let saved = try XCTUnwrap(reopened.archive.sessions.first)
        let writer = UUID()
        XCTAssertTrue(reopened.claimWriter(writer, sessionID: saved.id, checkpoint: { true }))
        defer { reopened.releaseWriter(writer) }
        let writerCommand = try reopened.sessionCommand(authority: reopened.writerAuthority(for: writer, sessionID: saved.id), sessionID: saved.id)
        XCTAssertThrowsError(try reopened.prepareAdaptiveReplacement(request: saved.request, predecessor: saved.checkpoint,
            rotation: NFOfflineQuestionRotation(store: NFMemoryOfflineQuestionRotationStateStore()),
            bank: NFOfflineQuestionBank.rotationBank, quarantinedItemIDs: [], at: Date(),
            editorialDay: NFEditorialCapturedDay.capture(at: Date(), dayBoundaryHour: 4, calendar: .current), command: writerCommand))
        XCTAssertEqual(try Data(contentsOf: root.appending(path: "sessions-v1.json")), bytes)
    }
}


extension EditorialLiveControllerPersistenceTests {
    func testCurrentItemReportExcludesHistoricalCreditAndInvalidatesPreparedPromotion() throws {
        let root = try root(); defer { try? FileManager.default.removeItem(at: root) }
        let container = try container(root); let store = try store(root, context: container.mainContext, admissions: catalog())
        let runtime = try launch(store); defer { runtime.releaseWriter() }
        for _ in 0..<3 { try answer(runtime, store: store); runtime.next(store: store) }
        try answer(runtime, store: store)
        let previous = try XCTUnwrap(store.localSessions.archive.sessions.first)
        let prepared = try store.prepareAdaptiveItem(request: previous.request, predecessor: previous.checkpoint,
            command: try runtime.sessionWriterCommand())
        XCTAssertEqual(prepared.receipt.editorialDecision?.selection.deliveredBand, .b2)
        let record = try XCTUnwrap(store.attempts.first)
        let snapshot = try XCTUnwrap(store.localSessions.editorialSnapshot(for: record.id))
        let frozen = try receipt(store)
        let rotation = store.localSessions.archive.offlineRotationLedger
        try store.saveItemReport(exercise: snapshot.exercise, reason: "QA.quarantine", note: "Synthetic validity change")
        XCTAssertNil(store.effectiveAttemptDTO(record).editorialObservation)
        XCTAssertThrowsError(try store.acceptAdaptiveItem(prepared, checkpoint: prepared.checkpoint))
        XCTAssertEqual(store.localSessions.archive.offlineRotationLedger, rotation)
        XCTAssertEqual(try receipt(store), frozen)
        let refreshed = try store.prepareAdaptiveItem(request: previous.request, predecessor: previous.checkpoint,
            command: try runtime.sessionWriterCommand())
        XCTAssertEqual(refreshed.receipt.editorialDecision?.selection.deliveredBand, .b1)
        XCTAssertEqual(refreshed.receipt.editorialDecision?.evidence.exclusions[record.id.uuidString], "contentExcluded")
        XCTAssertEqual(record.deterministicCredit, 1)
    }
}


extension EditorialLiveControllerPersistenceTests {
    func testUnscoredPresentationsAdvanceSupportWindowWithoutCreatingAcademicObservations() throws {
        let root = try root(); defer { try? FileManager.default.removeItem(at: root) }
        let container = try container(root); let store = try store(root, context: container.mainContext, admissions: catalog())
        let runtime = try launch(store); defer { runtime.releaseWriter() }
        try answer(runtime, store: store, hint: true); runtime.next(store: store)
        for _ in 0..<2 { runtime.acknowledgePresented(); runtime.skip(store: store); XCTAssertNil(runtime.saveError) }
        try answer(runtime, store: store, hint: true); runtime.next(store: store)
        let afterSkips = try XCTUnwrap(try receipt(store).editorialDecision)
        XCTAssertEqual(afterSkips.controlAfter.presentedSupportEvents, [false, false, true])
        XCTAssertFalse(afterSkips.controlAfter.shouldOfferSupport)
        XCTAssertTrue(afterSkips.evidence.independentObservationIDs.isEmpty)
        for _ in 0..<2 {
            runtime.acknowledgePresented(); runtime.revealSolution(store: store); runtime.skip(store: store)
            XCTAssertNil(runtime.saveError)
        }
        let afterReveals = try XCTUnwrap(try receipt(store).editorialDecision)
        XCTAssertEqual(afterReveals.controlAfter.presentedSupportEvents, [true, true, true])
        XCTAssertTrue(afterReveals.controlAfter.shouldOfferSupport)
        XCTAssertTrue(afterReveals.evidence.independentObservationIDs.isEmpty)
        XCTAssertEqual(afterReveals.controlAfter.currentTargetBand, .b1)
    }
}


extension EditorialLiveControllerPersistenceTests {
    func testControllerSeesConflictingPhysicalRowsBeforeUIWinnerProjection() throws {
        let root = try root(); defer { try? FileManager.default.removeItem(at: root) }
        let container = try container(root); let store = try store(root, context: container.mainContext, admissions: catalog())
        let runtime = try launch(store); defer { runtime.releaseWriter() }
        for _ in 0..<3 { try answer(runtime, store: store); runtime.next(store: store) }
        try answer(runtime, store: store)
        let original = try XCTUnwrap(store.attempts.first)
        let duplicate = AttemptRecord(sessionID: original.sessionID, lab: .mentalMath,
            itemID: original.itemID, prompt: original.prompt, response: "conflicting raw response",
            correctAnswer: original.correctAnswerText, isCorrect: false, confidence: .fairlyConfident)
        duplicate.id = original.id; duplicate.submittedAt = original.submittedAt.addingTimeInterval(-60)
        container.mainContext.insert(duplicate); try container.mainContext.save(); store.reload()
        XCTAssertEqual(try container.mainContext.fetch(FetchDescriptor<AttemptRecord>()).count, 5)
        XCTAssertEqual(store.attempts.count, 4, "The existing UI winner projection is not full evidence input")
        XCTAssertTrue(store.conflictingPhysicalAttemptIDs.contains(original.id))
        XCTAssertNil(store.effectiveAttemptDTO(original).editorialObservation)
        XCTAssertEqual(store.effectiveAttemptDTO(original).evidenceWeight, 0)
        XCTAssertNil(store.effectiveAttemptDTO(original).confidence)
        XCTAssertFalse(store.effectiveAttemptDTO(original).wasTimed)
        XCTAssertEqual(store.attempts.compactMap { store.effectiveAttemptDTO($0).editorialObservation }.count, 3)
        XCTAssertFalse(store.historicalPracticeSummaries.flatMap(\.editorialAttemptIDs).contains(original.id.uuidString))
        XCTAssertTrue(store.mentalMathMetricObservations(from: [original]).isEmpty)
        XCTAssertEqual(store.mentalMathMetricObservations(from: store.attempts).count, 3)
        let previous = try XCTUnwrap(store.localSessions.archive.sessions.first)
        let next = try store.prepareAdaptiveItem(request: previous.request, predecessor: previous.checkpoint,
            command: try runtime.sessionWriterCommand())
        XCTAssertEqual(next.receipt.editorialDecision?.evidence.independentObservationIDs.count, 3)
        XCTAssertEqual(next.receipt.editorialDecision?.selection.deliveredBand, .b1)
        XCTAssertEqual(original.response, try XCTUnwrap(store.attempts.first { $0.id == original.id }).response)
        let reopened = try self.store(root, context: container.mainContext, admissions: catalog())
        XCTAssertTrue(reopened.conflictingPhysicalAttemptIDs.contains(original.id))
        XCTAssertNil(reopened.effectiveAttemptDTO(original).editorialObservation)
        container.mainContext.delete(duplicate); try container.mainContext.save(); store.reload()
        XCTAssertFalse(store.conflictingPhysicalAttemptIDs.contains(original.id))
        XCTAssertNotNil(store.effectiveAttemptDTO(original).editorialObservation)
        XCTAssertEqual(store.attempts.count, 4)
    }
}

@MainActor
extension EditorialLiveControllerPersistenceTests {
    private func chooseNext(_ action: NFEditorialOverrideAction, runtime: NFUniversalSessionRuntime,
                            store: AppStore, id: UUID = UUID()) throws -> NFEditorialOverrideCommand {
        // The user sees the newly accepted item before opening its controls.
        // The non-UI fixture must execute the same durable visible callback.
        runtime.acknowledgePresented()
        runtime.pause(); XCTAssertTrue(runtime.checkpointDraft(store: store))
        let saved = try XCTUnwrap(store.localSessions.archive.sessions.first { $0.id == runtime.sessionID })
        let command = try store.setEditorialNextQuestion(.init(id: id, action: action, writerAuthority: runtime.editorialWriterAuthority),
            request: saved.request, predecessor: saved.checkpoint)
        runtime.resume(); runtime.acknowledgePresented()
        return command
    }

    func testReviewedNextPreferenceRetainsCurrentDraftReceiptTimerAndConsumesOnlyAtNext() throws {
        let root = try root(); defer { try? FileManager.default.removeItem(at: root) }
        let container = try container(root); let store = try store(root, context: container.mainContext, admissions: catalog())
        let runtime = try launch(store); defer { runtime.releaseWriter() }
        runtime.numericValue = "unfinished 29"; runtime.scratchpad = "my retained reasoning"
        let original = try receipt(store), exercise = runtime.exercise, timing = runtime.request.timingCondition
        let rotation = store.localSessions.archive.offlineRotationLedger
        let command = try chooseNext(.harder, runtime: runtime, store: store)
        XCTAssertEqual(command.targetBand, .b2); XCTAssertEqual(command.boundary, .nextQuestion)
        XCTAssertEqual(try receipt(store), original)
        XCTAssertEqual(runtime.exercise, exercise); XCTAssertEqual(runtime.numericValue, "unfinished 29")
        XCTAssertEqual(runtime.scratchpad, "my retained reasoning"); XCTAssertEqual(runtime.request.timingCondition, timing)
        XCTAssertEqual(store.localSessions.archive.offlineRotationLedger, rotation)
        XCTAssertEqual(store.localSessions.archive.selectionLedger?.slots.count, 1)
        XCTAssertTrue(store.attempts.isEmpty)
        let shown = try XCTUnwrap(store.localSessions.editorialChallengePresentation(sessionID: runtime.sessionID))
        XCTAssertEqual(shown.deliveredBand, .b1); XCTAssertEqual(shown.pendingBand, .b2)
        XCTAssertEqual(shown.reasoningSteps, original.editorialDecision?.admission.demand.demandVector.reasoningSteps)
        try answer(runtime, store: store); runtime.next(store: store)
        let selected = try receipt(store)
        XCTAssertEqual(selected.schemaVersion, 4); XCTAssertEqual(selected.editorialDecision?.overrideCommand, command)
        XCTAssertEqual(selected.editorialDecision?.controlAfter.currentTargetBand, .b2)
        XCTAssertEqual(selected.editorialDecision?.selection.reason, .userRequested)
        XCTAssertEqual(selected.editorialDecision?.controlAfter.upwardChangesThisSession, 0)
        XCTAssertEqual(selected.editorialDecision?.controlAfter.totalAutomaticChangesThisSession, 0)
        XCTAssertEqual(selected.editorialDecision?.controlAfter.currentBandDecisionResponseIDs, [])
        XCTAssertEqual(store.localSessions.archive.selectionLedger?.slots.count, 2)
        XCTAssertEqual(store.attempts.count, 1)
        XCTAssertEqual(runtime.request.timingCondition, timing)
    }

    func testActualManualControlsPreserveAutomaticAllowanceAndKeepMeansDeliveredBand() throws {
        let root = try root(); defer { try? FileManager.default.removeItem(at: root) }
        let container = try container(root); let store = try store(root, context: container.mainContext, admissions: catalog())
        let runtime = try launch(store); defer { runtime.releaseWriter() }
        for _ in 0..<4 { try answer(runtime, store: store); runtime.next(store: store) }
        let before = try XCTUnwrap(try receipt(store).editorialDecision)
        XCTAssertEqual(before.controlAfter.upwardChangesThisSession, 1)
        _ = try chooseNext(.easier, runtime: runtime, store: store)
        try answer(runtime, store: store); runtime.next(store: store)
        let easier = try XCTUnwrap(try receipt(store).editorialDecision)
        XCTAssertEqual(easier.controlAfter.currentTargetBand, .b1)
        XCTAssertEqual(easier.controlAfter.challengeMode, .adaptive)
        XCTAssertEqual(easier.controlAfter.upwardChangesThisSession, 1)
        XCTAssertEqual(easier.controlAfter.totalAutomaticChangesThisSession, before.controlAfter.totalAutomaticChangesThisSession)
        XCTAssertEqual(easier.controlAfter.decisionOrdinal, before.controlAfter.decisionOrdinal + 1)
        _ = try chooseNext(.harder, runtime: runtime, store: store)
        // Keep this level uses the current DELIVERED Foundation question,
        // superseding the queued harder preference without delivering it.
        let keep = try chooseNext(.keepThisLevel, runtime: runtime, store: store)
        XCTAssertEqual(keep.targetBand, .b1)
        try answer(runtime, store: store); runtime.next(store: store)
        let kept = try XCTUnwrap(try receipt(store).editorialDecision)
        XCTAssertEqual(kept.controlAfter.challengeMode, .fixedBand(.b1))
        XCTAssertEqual(kept.controlAfter.upwardChangesThisSession, 1)
        XCTAssertEqual(kept.controlAfter.totalAutomaticChangesThisSession, before.controlAfter.totalAutomaticChangesThisSession)
        XCTAssertEqual(kept.selection.reason, .userFixedBand)
        XCTAssertEqual(store.localSessions.archive.editorialOverrideCommands?.count, 3)
    }

    func testPendingPreferenceAndSelectedFixedBandSurviveActualCoreAndLocalDiskReopen() throws {
        let root = try root(); defer { try? FileManager.default.removeItem(at: root) }
        let catalog = try catalog(); var sessionID = UUID(); var command: NFEditorialOverrideCommand!
        var original: NFLocalAdaptiveItemReceipt!
        do {
            let container = try container(root, persistent: true)
            let store = try store(root, context: container.mainContext, admissions: catalog)
            let runtime = try launch(store); sessionID = runtime.sessionID
            command = try chooseNext(.fixedBand(.b2), runtime: runtime, store: store)
            original = try receipt(store)
            runtime.pause(); XCTAssertTrue(runtime.checkpointDraft(store: store)); runtime.releaseWriter()
        }
        do {
            let container = try container(root, persistent: true)
            let store = try store(root, context: container.mainContext, admissions: catalog)
            XCTAssertNil(store.localSessions.loadError); XCTAssertEqual(try receipt(store), original)
            XCTAssertEqual(store.localSessions.archive.editorialOverrideCommands?[command.id.uuidString], command)
            XCTAssertEqual(store.localSessions.editorialChallengePresentation(sessionID: sessionID)?.pendingBand, .b2)
            let saved = try XCTUnwrap(store.localSessions.archive.sessions.first)
            var request = saved.request; request.localCheckpoint = saved.checkpoint; request.localSessionID = saved.id
            let runtime = NFUniversalSessionRuntime(request: request)
            XCTAssertTrue(runtime.checkpointDraft(store: store)); runtime.resume(); runtime.acknowledgePresented()
            try answer(runtime, store: store); runtime.next(store: store)
            XCTAssertEqual(try receipt(store).editorialDecision?.controlAfter.challengeMode, .fixedBand(.b2))
            runtime.pause(); XCTAssertTrue(runtime.checkpointDraft(store: store)); runtime.releaseWriter()
        }
        let container = try container(root, persistent: true)
        let store = try store(root, context: container.mainContext, admissions: catalog)
        XCTAssertNil(store.localSessions.loadError)
        XCTAssertEqual(try receipt(store).editorialDecision?.controlAfter.challengeMode, .fixedBand(.b2))
        XCTAssertEqual(try receipt(store).editorialDecision?.controlAfter.decisionOrdinal, 2)
        XCTAssertEqual(store.localSessions.archive.selectionLedger?.slots.count, 2)
    }

    func testActualReplacementOverrideRetainsOriginalDraftAndPublishesOneNewSlotIdempotently() throws {
        let root = try root(); defer { try? FileManager.default.removeItem(at: root) }
        let container = try container(root); let store = try store(root, context: container.mainContext, admissions: catalog())
        let runtime = try launch(store); defer { runtime.releaseWriter() }; runtime.numericValue = "original draft"; runtime.scratchpad = "original steps"
        runtime.pause(); XCTAssertTrue(runtime.checkpointDraft(store: store))
        let prior = try XCTUnwrap(store.localSessions.archive.sessions.first)
        let before = try receipt(store)
        let intent = NFEditorialOverrideIntent(id: UUID(), action: .harder, writerAuthority: runtime.editorialWriterAuthority)
        let prepared = try store.prepareAdaptiveReplacement(request: prior.request, predecessor: prior.checkpoint, overrideIntent: intent,
            command: try runtime.sessionWriterCommand())
        XCTAssertEqual(prepared.receipt.editorialDecision?.selection.deliveredBand, .b2)
        XCTAssertEqual(prepared.receipt.editorialDecision?.controlAfter.presentedSupportEvents, [false],
            "Explicitly replacing with a harder question is not evidence that help was required")
        XCTAssertEqual(store.localSessions.archive.selectionLedger?.slots.count, 1)
        XCTAssertNil(store.localSessions.archive.editorialOverrideCommands)
        let accepted = try store.acceptAdaptiveItem(prepared, checkpoint: prepared.checkpoint)
        XCTAssertEqual(accepted.checkpoint.index, prior.checkpoint.index)
        XCTAssertNotEqual(accepted.checkpoint.slotID, prior.checkpoint.slotID)
        XCTAssertEqual(store.localSessions.archive.adaptiveItemReceipts?[before.decisionID], before)
        let retired = try XCTUnwrap(store.localSessions.archive.retiredOrdinaryDrafts?[prior.checkpoint.slotID.uuidString])
        XCTAssertEqual(retired.checkpoint.response, prior.checkpoint.response)
        XCTAssertEqual(retired.checkpoint.scratchpad, "original steps")
        XCTAssertEqual(retired.checkpoint.itemActiveDuration, prior.checkpoint.itemActiveDuration)
        XCTAssertTrue(store.attempts.isEmpty)
        XCTAssertEqual(store.localSessions.archive.selectionLedger?.slots.count, 2)
        let retry = try store.prepareAdaptiveReplacement(request: prior.request, predecessor: prior.checkpoint, overrideIntent: intent,
            command: try runtime.sessionWriterCommand())
        let repeated = try store.acceptAdaptiveItem(retry, checkpoint: retry.checkpoint)
        XCTAssertEqual(repeated.checkpoint, accepted.checkpoint); XCTAssertEqual(repeated.revision, accepted.revision)
        XCTAssertEqual(store.localSessions.archive.editorialOverrideCommands?.count, 1)
        XCTAssertEqual(store.localSessions.archive.selectionLedger?.slots.count, 2)
    }

    func testChangedPendingCommandInvalidatesPreparedNextWithoutChangingItsPredecessor() throws {
        let root = try root(); defer { try? FileManager.default.removeItem(at: root) }
        let container = try container(root); let store = try store(root, context: container.mainContext, admissions: catalog())
        let runtime = try launch(store); defer { runtime.releaseWriter() }
        _ = try chooseNext(.harder, runtime: runtime, store: store)
        try answer(runtime, store: store)
        runtime.pause(); XCTAssertTrue(runtime.checkpointDraft(store: store))
        let prior = try XCTUnwrap(store.localSessions.archive.sessions.first)
        let prepared = try store.prepareAdaptiveItem(request: prior.request, predecessor: prior.checkpoint,
            command: try runtime.sessionWriterCommand())
        XCTAssertEqual(prepared.receipt.editorialDecision?.selection.deliveredBand, .b2)
        let cursor = store.localSessions.archive.offlineRotationLedger
        let keep = try store.setEditorialNextQuestion(.init(id: UUID(), action: .keepThisLevel, writerAuthority: runtime.editorialWriterAuthority), request: prior.request, predecessor: prior.checkpoint)
        XCTAssertThrowsError(try store.acceptAdaptiveItem(prepared, checkpoint: prepared.checkpoint))
        XCTAssertEqual(store.localSessions.archive.offlineRotationLedger, cursor)
        XCTAssertEqual(store.localSessions.archive.sessions.first?.checkpoint, prior.checkpoint)
        let rebuilt = try store.prepareAdaptiveItem(request: prior.request, predecessor: prior.checkpoint,
            command: try runtime.sessionWriterCommand())
        XCTAssertEqual(rebuilt.receipt.editorialDecision?.overrideCommand, keep)
        XCTAssertEqual(rebuilt.receipt.editorialDecision?.selection.deliveredBand, .b1)
    }

    func testUnavailableAdjacentBandNeverSilentlyJumpsAndFailureRetainsTheCompleteArchive() throws {
        let root = try root(); defer { try? FileManager.default.removeItem(at: root) }
        let source = try catalog()
        let entries = source.entries.filter { $0.demand.editorialBand == .b1 }
        let catalog = NFEditorialAdmissionContext(version: "QA.only-foundation.v1", entries: entries)
        let container = try container(root); let store = try store(root, context: container.mainContext, admissions: catalog)
        let runtime = try launch(store); defer { runtime.releaseWriter() }
        runtime.pause(); XCTAssertTrue(runtime.checkpointDraft(store: store))
        let prior = try XCTUnwrap(store.localSessions.archive.sessions.first)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let before = try encoder.encode(store.localSessions.archive)
        XCTAssertThrowsError(try store.setEditorialNextQuestion(.init(id: UUID(), action: .harder, writerAuthority: runtime.editorialWriterAuthority), request: prior.request, predecessor: prior.checkpoint)) {
            guard case NFEditorialOverrideError.unavailable(.b2, let bands) = $0 else { return XCTFail("Unexpected error: \($0)") }
            XCTAssertEqual(bands, [.b1])
        }
        XCTAssertEqual(try encoder.encode(store.localSessions.archive), before)
        XCTAssertThrowsError(try store.setEditorialNextQuestion(.init(id: UUID(), action: .easier, writerAuthority: runtime.editorialWriterAuthority), request: prior.request, predecessor: prior.checkpoint))
        XCTAssertEqual(store.localSessions.editorialChallengePresentation(sessionID: prior.id)?.reviewedCatalogBands, [.b1])
        XCTAssertEqual(try encoder.encode(store.localSessions.archive), before)
    }

    func testFailedPreferencePublicationKeepsOriginalThenSameCommandRetriesExactlyOnce() throws {
        let root = try root(); defer { try? FileManager.default.removeItem(at: root) }
        let container = try container(root); let store = try store(root, context: container.mainContext, admissions: catalog())
        let runtime = try launch(store); defer { runtime.releaseWriter() }
        runtime.pause(); XCTAssertTrue(runtime.checkpointDraft(store: store))
        let prior = try XCTUnwrap(store.localSessions.archive.sessions.first)
        let url = root.appending(path: "sessions-v1.json"), backup = root.appending(path: "retained.json")
        let before = store.localSessions.archive.offlineRotationLedger
        try FileManager.default.moveItem(at: url, to: backup)
        let intent = NFEditorialOverrideIntent(id: UUID(), action: .harder, writerAuthority: runtime.editorialWriterAuthority)
        XCTAssertThrowsError(try store.setEditorialNextQuestion(intent, request: prior.request, predecessor: prior.checkpoint))
        XCTAssertNil(store.localSessions.archive.editorialOverrideCommands)
        XCTAssertEqual(store.localSessions.archive.offlineRotationLedger, before)
        try FileManager.default.moveItem(at: backup, to: url)
        let command = try store.setEditorialNextQuestion(intent, request: prior.request, predecessor: prior.checkpoint)
        let firstBytes = try Data(contentsOf: url)
        XCTAssertEqual(try store.setEditorialNextQuestion(intent, request: prior.request, predecessor: prior.checkpoint), command)
        XCTAssertEqual(try Data(contentsOf: url), firstBytes)
        XCTAssertEqual(store.localSessions.archive.editorialOverrideCommands?.count, 1)
    }

    func testExplicitInitialBandAndSeparateFixedSessionNeverRewriteFrozenWork() throws {
        let root = try root(); defer { try? FileManager.default.removeItem(at: root) }
        let container = try container(root); var store = try store(root, context: container.mainContext, admissions: .released)
        XCTAssertTrue(store.beginSession(lab: .mentalMath, source: .focused, field: .general,
            targetDifficulty: 0.5, requestedItemCount: 8, seedOverride: seed,
            isTimed: false, timingCondition: .init(.untimed), launchLocaleIdentifier: "en", reservationStrategy: .fixedBlock))
        let fixedRequest = try XCTUnwrap(store.activeSessionRequest)
        let runtime = NFUniversalSessionRuntime(request: fixedRequest)
        XCTAssertTrue(runtime.checkpointDraft(store: store)); runtime.resume(); runtime.acknowledgePresented()
        runtime.numericValue = "retained fixed draft"; runtime.pause(); XCTAssertTrue(runtime.checkpointDraft(store: store)); runtime.releaseWriter()
        let old = try XCTUnwrap(store.localSessions.archive.sessions.first)
        let fixedReceipt = store.localSessions.archive.fixedLaunchReceipts
        let fixedPositions = try XCTUnwrap(old.request.offlineRotationPlan).items
        let newTemplate = SessionRequest(lab: .mentalMath, source: .focused, seed: fixedRequest.seed,
            localeIdentifier: "en", field: .general, targetDifficulty: 0.5, requestedItemCount: 8,
            isTimed: false, timingCondition: .init(.untimed))
        store = try self.store(root, context: container.mainContext, admissions: catalog(requestOverride: newTemplate))
        let fixedWriter = UUID()
        XCTAssertTrue(store.localSessions.claimWriter(fixedWriter, sessionID: fixedRequest.id, checkpoint: { true }))
        defer { store.localSessions.releaseWriter(fixedWriter) }
        let fixedAuthority = try XCTUnwrap(store.localSessions.writerAuthority(for: fixedWriter, sessionID: fixedRequest.id))
        XCTAssertTrue(store.beginSeparateReviewedActivity(from: fixedRequest, band: .b2, commandID: UUID(),
            writerAuthority: fixedAuthority), store.lastErrorMessage ?? "")
        let next = try XCTUnwrap(store.activeSessionRequest)
        XCTAssertNotEqual(next.id, old.id); XCTAssertNil(next.planID); XCTAssertNil(next.planBlockID)
        XCTAssertEqual(next.requestedItemCount, old.checkpoint.itemCount)
        let retained = try XCTUnwrap(store.localSessions.archive.sessions.first { $0.id == old.id })
        XCTAssertEqual(retained.checkpoint, old.checkpoint); XCTAssertEqual(retained.revision, old.revision)
        XCTAssertEqual(try NFLocalReservationBridge.configurationDigest(retained.request), try NFLocalReservationBridge.configurationDigest(old.request))
        XCTAssertEqual(store.localSessions.archive.fixedLaunchReceipts, fixedReceipt)
        XCTAssertEqual(store.localSessions.archive.sessions.first { $0.id == old.id }?.request.offlineRotationPlan?.items, fixedPositions)
        let selected = try XCTUnwrap(next.localCheckpoint?.ordinaryReservationDecisionID.flatMap { store.localSessions.archive.adaptiveItemReceipts?[$0] })
        XCTAssertEqual(selected.editorialDecision?.initialReason, .userRequested)
        XCTAssertEqual(selected.editorialDecision?.selection.deliveredBand, .b2)
        XCTAssertTrue(store.attempts.isEmpty)
    }

    func testEmptyAdmissionAndFutureOverrideCannotWriteOrReinterpretLegacyWork() throws {
        let root = try root(); defer { try? FileManager.default.removeItem(at: root) }
        let container = try container(root); let store = try store(root, context: container.mainContext, admissions: .released)
        let before = store.localSessions.archive.offlineRotationLedger
        XCTAssertFalse(store.beginSession(lab: .mentalMath, source: .focused, field: .general,
            targetDifficulty: 0.5, requestedItemCount: 8, seedOverride: seed,
            isTimed: false, timingCondition: .init(.untimed), launchLocaleIdentifier: "en", editorialStartingBand: .b2))
        XCTAssertEqual(store.localSessions.archive.offlineRotationLedger, before)
        XCTAssertNil(store.activeSessionRequest)
        let runtime = try launch(store); defer { runtime.releaseWriter() }
        XCTAssertNil(store.localSessions.editorialChallengePresentation(sessionID: runtime.sessionID))
        runtime.pause(); XCTAssertTrue(runtime.checkpointDraft(store: store))
        let saved = try XCTUnwrap(store.localSessions.archive.sessions.first)
        XCTAssertThrowsError(try store.setEditorialNextQuestion(.init(id: UUID(), action: .harder, writerAuthority: runtime.editorialWriterAuthority), request: saved.request, predecessor: saved.checkpoint))
        XCTAssertNil(store.localSessions.archive.editorialOverrideCommands)
    }

    func testOverrideCommandsAreLocalAuthorityAndLinkedDeletionRemovesAllCommands() throws {
        let root = try root(); defer { try? FileManager.default.removeItem(at: root) }
        let container = try container(root); let store = try store(root, context: container.mainContext, admissions: catalog())
        let runtime = try launch(store)
        let command = try chooseNext(.harder, runtime: runtime, store: store)
        XCTAssertNotNil(store.localSessions.archive.editorialOverrideCommands?[command.id.uuidString])
        XCTAssertNil(store.localSessions.exportArchive.editorialOverrideCommands)
        let attemptID = try XCTUnwrap(store.localSessions.archive.sessions.first?.checkpoint.attemptID)
        let consumption = store.localSessions.archive.offlineRotationLedger
        runtime.pause(); XCTAssertTrue(runtime.checkpointDraft(store: store)); runtime.releaseWriter()
        try store.localSessions.removeReferences(attemptIDs: [attemptID])
        XCTAssertTrue(store.localSessions.archive.editorialOverrideCommands?.isEmpty ?? true)
        XCTAssertTrue(store.localSessions.archive.sessions.isEmpty)
        XCTAssertEqual(store.localSessions.archive.offlineRotationLedger, consumption)
    }
}

@MainActor
extension EditorialLiveControllerPersistenceTests {
    func testMarkerProtectedCurrentRunCannotExposeOrApplyReviewedDifficultyControls() throws {
        let root = try root(); defer { try? FileManager.default.removeItem(at: root) }
        let container = try container(root); let store = try store(root, context: container.mainContext, admissions: catalog())
        let runtime = try launch(store); defer { runtime.releaseWriter() }
        runtime.pause(); XCTAssertTrue(runtime.checkpointDraft(store: store))
        let run = try XCTUnwrap(store.localSessions.archive.sessions.first)
        var marked = store.localSessions.archive
        marked.withheldProtectedConflictAttemptIDs = [run.checkpoint.attemptID]
        try store.localSessions.restorePredecessor(marked)
        XCTAssertNil(store.localSessions.editorialChallengePresentation(sessionID: run.id))
        let before = store.localSessions.archive.offlineRotationLedger
        XCTAssertThrowsError(try store.setEditorialNextQuestion(.init(id: UUID(), action: .harder, writerAuthority: runtime.editorialWriterAuthority), request: run.request, predecessor: run.checkpoint))
        XCTAssertThrowsError(try store.prepareAdaptiveReplacement(request: run.request, predecessor: run.checkpoint,
            overrideIntent: .init(id: UUID(), action: .harder, writerAuthority: runtime.editorialWriterAuthority),
            command: try runtime.sessionWriterCommand()))
        XCTAssertNil(store.localSessions.archive.editorialOverrideCommands)
        XCTAssertEqual(store.localSessions.archive.offlineRotationLedger, before)
        XCTAssertEqual(store.localSessions.archive.sessions.first?.checkpoint, run.checkpoint)
    }

    func testFuturePendingOverrideAndForeignOwnerRemainReadOnlyAndRetainOriginalBytes() throws {
        let root = try root(); defer { try? FileManager.default.removeItem(at: root) }
        let admissions = try catalog(); let container = try container(root)
        let store = try store(root, context: container.mainContext, admissions: admissions)
        let runtime = try launch(store)
        let command = try chooseNext(.harder, runtime: runtime, store: store)
        runtime.pause(); XCTAssertTrue(runtime.checkpointDraft(store: store)); runtime.releaseWriter()
        let run = try XCTUnwrap(store.localSessions.archive.sessions.first)
        let url = root.appending(path: "sessions-v1.json")
        let foreign = NFLocalSessionRepository(url: url, ownerDeviceID: UUID(), editorialAdmissions: admissions)
        XCTAssertNil(foreign.editorialChallengePresentation(sessionID: run.id))
        var raw = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        var commands = try XCTUnwrap(raw["editorialOverrideCommands"] as? [String: Any])
        var future = try XCTUnwrap(commands[command.id.uuidString] as? [String: Any])
        future["schemaVersion"] = 999; commands[command.id.uuidString] = future; raw["editorialOverrideCommands"] = commands
        let bytes = try JSONSerialization.data(withJSONObject: raw, options: [.sortedKeys])
        try bytes.write(to: url)
        let cold = NFLocalSessionRepository(url: url, ownerDeviceID: owner, editorialAdmissions: admissions)
        XCTAssertNil(cold.loadError)
        XCTAssertEqual(cold.archive.sessions.first?.status, .migrationRecovery)
        XCTAssertNil(cold.editorialChallengePresentation(sessionID: run.id))
        XCTAssertEqual(cold.archive.editorialOverrideCommands?[command.id.uuidString]?.schemaVersion, 999)
        XCTAssertEqual(try Data(contentsOf: url), bytes)
    }
}


@MainActor
extension EditorialLiveControllerPersistenceTests {
    func testUnpresentedNextSlotRefusesPreferenceUntilActualVisibleAcknowledgement() throws {
        let root = try root(); defer { try? FileManager.default.removeItem(at: root) }
        let container = try container(root); let store = try store(root, context: container.mainContext, admissions: catalog())
        let runtime = try launch(store); defer { runtime.releaseWriter() }
        try answer(runtime, store: store); runtime.next(store: store)
        runtime.pause(); XCTAssertTrue(runtime.checkpointDraft(store: store))
        let saved = try XCTUnwrap(store.localSessions.archive.sessions.first)
        let before = store.localSessions.archive.offlineRotationLedger
        XCTAssertFalse(store.localSessions.archive.selectionLedger?.exposures.values.contains {
            $0.slotID == saved.checkpoint.slotID.uuidString
        } ?? false)
        let intent = NFEditorialOverrideIntent(id: UUID(), action: .harder, writerAuthority: runtime.editorialWriterAuthority)
        XCTAssertThrowsError(try store.setEditorialNextQuestion(intent, request: saved.request, predecessor: saved.checkpoint))
        XCTAssertNil(store.localSessions.archive.editorialOverrideCommands)
        XCTAssertEqual(store.localSessions.archive.offlineRotationLedger, before)
        runtime.resume(); runtime.acknowledgePresented()
        let accepted = try chooseNext(.harder, runtime: runtime, store: store, id: intent.id)
        XCTAssertEqual(accepted.slotID, saved.checkpoint.slotID)
        XCTAssertEqual(accepted.targetBand, .b2)
        XCTAssertEqual(store.localSessions.archive.offlineRotationLedger, before)
        XCTAssertEqual(store.localSessions.archive.selectionLedger?.slots.count, 2)
    }
}

@MainActor
extension EditorialLiveControllerPersistenceTests {
    func testPreferenceCommandRequiresActualWriterCapabilityEvenForAnExactExposedCheckpoint() throws {
        let root = try root(); defer { try? FileManager.default.removeItem(at: root) }
        let container = try container(root); let store = try store(root, context: container.mainContext, admissions: catalog())
        let runtime = try launch(store); defer { runtime.releaseWriter() }
        runtime.pause(); XCTAssertTrue(runtime.checkpointDraft(store: store))
        let saved = try XCTUnwrap(store.localSessions.archive.sessions.first)
        let cursor = store.localSessions.archive.offlineRotationLedger
        let id = UUID()
        XCTAssertThrowsError(try store.setEditorialNextQuestion(.init(id: id, action: .harder), request: saved.request, predecessor: saved.checkpoint)) {
            guard case NFEditorialOverrideError.staleOwner = $0 else { return XCTFail("Unexpected error: \($0)") }
        }
        XCTAssertNil(store.localSessions.archive.editorialOverrideCommands)
        XCTAssertEqual(store.localSessions.archive.offlineRotationLedger, cursor)
        let authority = try XCTUnwrap(runtime.editorialWriterAuthority)
        let accepted = try store.setEditorialNextQuestion(.init(id: id, action: .harder, writerAuthority: authority), request: saved.request, predecessor: saved.checkpoint)
        let commandJSON = String(decoding: try JSONEncoder().encode(accepted), as: UTF8.self)
        XCTAssertFalse(commandJSON.contains("writerAuthority")); XCTAssertFalse(commandJSON.contains("repositoryIdentity"))
        XCTAssertEqual(store.localSessions.archive.offlineRotationLedger, cursor)
    }

    func testSameWriterUUIDCannotReviveACommandFromItsEarlierOwnershipGeneration() throws {
        let root = try root(); defer { try? FileManager.default.removeItem(at: root) }
        let container = try container(root); let store = try store(root, context: container.mainContext, admissions: catalog())
        let runtime = try launch(store)
        runtime.pause(); XCTAssertTrue(runtime.checkpointDraft(store: store)); runtime.releaseWriter()
        let saved = try XCTUnwrap(store.localSessions.archive.sessions.first)
        let writer = UUID()
        XCTAssertTrue(store.localSessions.claimWriter(writer, sessionID: saved.id, checkpoint: { true }))
        let old = try XCTUnwrap(store.localSessions.writerAuthority(for: writer, sessionID: saved.id))
        // Repeated checkpoint registration retains the current generation.
        XCTAssertTrue(store.localSessions.claimWriter(writer, sessionID: saved.id, checkpoint: { true }))
        XCTAssertEqual(store.localSessions.writerAuthority(for: writer, sessionID: saved.id), old)
        store.localSessions.releaseWriter(writer)
        XCTAssertTrue(store.localSessions.claimWriter(writer, sessionID: saved.id, checkpoint: { true }))
        defer { store.localSessions.releaseWriter(writer) }
        let current = try XCTUnwrap(store.localSessions.writerAuthority(for: writer, sessionID: saved.id))
        XCTAssertNotEqual(old, current)
        let id = UUID(); let before = try Data(contentsOf: root.appending(path: "sessions-v1.json"))
        XCTAssertThrowsError(try store.setEditorialNextQuestion(.init(id: id, action: .harder, writerAuthority: old), request: saved.request, predecessor: saved.checkpoint)) {
            guard case NFEditorialOverrideError.staleOwner = $0 else { return XCTFail("Unexpected error: \($0)") }
        }
        XCTAssertEqual(try Data(contentsOf: root.appending(path: "sessions-v1.json")), before)
        XCTAssertEqual(try store.setEditorialNextQuestion(.init(id: id, action: .harder, writerAuthority: current), request: saved.request, predecessor: saved.checkpoint).id, id)
    }

    func testTakeoverRejectsOldAcceptedPreferenceRetryBeforeAnyCommandMutation() throws {
        let root = try root(); defer { try? FileManager.default.removeItem(at: root) }
        let container = try container(root); let store = try store(root, context: container.mainContext, admissions: catalog())
        let runtime = try launch(store)
        runtime.pause(); XCTAssertTrue(runtime.checkpointDraft(store: store)); runtime.releaseWriter()
        let saved = try XCTUnwrap(store.localSessions.archive.sessions.first)
        let first = UUID(), second = UUID()
        XCTAssertTrue(store.localSessions.claimWriter(first, sessionID: saved.id, checkpoint: { true }))
        let authority = try XCTUnwrap(store.localSessions.writerAuthority(for: first, sessionID: saved.id))
        let intent = NFEditorialOverrideIntent(id: UUID(), action: .harder, writerAuthority: authority)
        let command = try store.setEditorialNextQuestion(intent, request: saved.request, predecessor: saved.checkpoint)
        XCTAssertTrue(store.localSessions.takeOver(second, sessionID: saved.id, checkpoint: { true }))
        defer { store.localSessions.releaseWriter(second) }
        let before = try Data(contentsOf: root.appending(path: "sessions-v1.json"))
        XCTAssertThrowsError(try store.setEditorialNextQuestion(intent, request: saved.request, predecessor: saved.checkpoint)) {
            guard case NFEditorialOverrideError.staleOwner = $0 else { return XCTFail("Unexpected error: \($0)") }
        }
        XCTAssertEqual(try Data(contentsOf: root.appending(path: "sessions-v1.json")), before)
        XCTAssertEqual(store.localSessions.archive.editorialOverrideCommands?[command.id.uuidString], command)
        let current = try XCTUnwrap(store.localSessions.writerAuthority(for: second, sessionID: saved.id))
        let replacement = try store.setEditorialNextQuestion(.init(id: UUID(), action: .keepThisLevel, writerAuthority: current), request: saved.request, predecessor: saved.checkpoint)
        XCTAssertEqual(replacement.predecessorCommandID, command.id)
    }

    func testPreparedReplacementCannotCommitAfterTakeoverEvenWithUnchangedArchiveRevision() throws {
        let root = try root(); defer { try? FileManager.default.removeItem(at: root) }
        let container = try container(root); let store = try store(root, context: container.mainContext, admissions: catalog())
        let runtime = try launch(store)
        runtime.pause(); XCTAssertTrue(runtime.checkpointDraft(store: store)); runtime.releaseWriter()
        let saved = try XCTUnwrap(store.localSessions.archive.sessions.first)
        let first = UUID(), second = UUID()
        XCTAssertTrue(store.localSessions.claimWriter(first, sessionID: saved.id, checkpoint: { true }))
        let firstAuthority = try XCTUnwrap(store.localSessions.writerAuthority(for: first, sessionID: saved.id))
        let prepared = try store.prepareAdaptiveReplacement(request: saved.request, predecessor: saved.checkpoint,
            overrideIntent: .init(id: UUID(), action: .harder, writerAuthority: firstAuthority),
            command: try store.localSessions.sessionCommand(authority: firstAuthority, sessionID: saved.id))
        let revision = store.localSessions.archive.transactionRevision, cursor = store.localSessions.archive.offlineRotationLedger
        XCTAssertTrue(store.localSessions.takeOver(second, sessionID: saved.id, checkpoint: { true }))
        defer { store.localSessions.releaseWriter(second) }
        XCTAssertEqual(store.localSessions.archive.transactionRevision, revision)
        XCTAssertThrowsError(try store.acceptAdaptiveItem(prepared, checkpoint: prepared.checkpoint)) {
            guard case NFLocalSessionRepository.RepositoryError.staleRevision = $0 else { return XCTFail("Unexpected error: \($0)") }
        }
        XCTAssertEqual(store.localSessions.archive.offlineRotationLedger, cursor)
        XCTAssertEqual(store.localSessions.archive.sessions.first?.checkpoint, saved.checkpoint)
        XCTAssertNil(store.localSessions.archive.editorialOverrideCommands)
        let current = try XCTUnwrap(store.localSessions.writerAuthority(for: second, sessionID: saved.id))
        let authorized = try store.prepareAdaptiveReplacement(request: saved.request, predecessor: saved.checkpoint,
            overrideIntent: .init(id: UUID(), action: .harder, writerAuthority: current),
            command: try store.localSessions.sessionCommand(authority: current, sessionID: saved.id))
        let accepted = try store.acceptAdaptiveItem(authorized, checkpoint: authorized.checkpoint)
        XCTAssertNotEqual(accepted.checkpoint.slotID, saved.checkpoint.slotID)
        XCTAssertEqual(store.localSessions.archive.selectionLedger?.slots.count, 2)
    }

    func testRepositoryReopenCannotReuseLiveAuthorityFromThePriorRepositoryInstance() throws {
        let root = try root(); defer { try? FileManager.default.removeItem(at: root) }
        let container = try container(root); let admissions = try catalog()
        let store = try store(root, context: container.mainContext, admissions: admissions)
        let runtime = try launch(store)
        runtime.pause(); XCTAssertTrue(runtime.checkpointDraft(store: store)); runtime.releaseWriter()
        let saved = try XCTUnwrap(store.localSessions.archive.sessions.first)
        let writer = UUID()
        XCTAssertTrue(store.localSessions.claimWriter(writer, sessionID: saved.id, checkpoint: { true }))
        defer { store.localSessions.releaseWriter(writer) }
        let old = try XCTUnwrap(store.localSessions.writerAuthority(for: writer, sessionID: saved.id))
        let reopened = try self.store(root, context: container.mainContext, admissions: admissions)
        XCTAssertTrue(reopened.localSessions.claimWriter(writer, sessionID: saved.id, checkpoint: { true }))
        defer { reopened.localSessions.releaseWriter(writer) }
        let current = try XCTUnwrap(reopened.localSessions.writerAuthority(for: writer, sessionID: saved.id))
        XCTAssertNotEqual(old, current)
        XCTAssertThrowsError(try reopened.setEditorialNextQuestion(.init(id: UUID(), action: .harder, writerAuthority: old), request: saved.request, predecessor: saved.checkpoint)) {
            guard case NFEditorialOverrideError.staleOwner = $0 else { return XCTFail("Unexpected error: \($0)") }
        }
        XCTAssertNil(reopened.localSessions.archive.editorialOverrideCommands)
        _ = try reopened.setEditorialNextQuestion(.init(id: UUID(), action: .harder, writerAuthority: current), request: saved.request, predecessor: saved.checkpoint)
        XCTAssertEqual(reopened.localSessions.archive.editorialOverrideCommands?.count, 1)
    }
}

@MainActor
extension EditorialLiveControllerPersistenceTests {
    func testVisibleReviewedChoiceWaitsForPresentationAndQueuesWithoutChangingTheQuestion() throws {
        let root = try root(); defer { try? FileManager.default.removeItem(at: root) }
        let container = try container(root), store = try store(root, context: container.mainContext, admissions: catalog())
        let runtime = try launch(store); defer { runtime.releaseWriter() }
        try answer(runtime, store: store); runtime.next(store: store)
        XCTAssertFalse(runtime.canChooseReviewedChallenge, "A durable reservation is not a visible presentation")
        runtime.chooseReviewedChallenge(.harder, store: store)
        XCTAssertNil(runtime.reviewedChoice)
        runtime.acknowledgePresented()
        runtime.numericValue = "29"; runtime.scratchpad = "keep my reasoning"
        let exercise = runtime.exercise, slot = runtime.reviewedSlotID
        let ledger = store.localSessions.archive.offlineRotationLedger
        runtime.chooseReviewedChallenge(.harder, store: store, expectedSlotID: slot)
        let commandID = try XCTUnwrap(runtime.reviewedChoice?.id)
        XCTAssertTrue(runtime.applyReviewedChoice(.nextQuestion, store: store), runtime.saveError ?? runtime.reviewedChallengeError ?? "")
        XCTAssertEqual(store.localSessions.archive.editorialOverrideCommands?[commandID.uuidString]?.boundary, .nextQuestion)
        XCTAssertEqual(runtime.reviewedChallengePresentation(store: store)?.pendingBand, .b2)
        XCTAssertEqual(runtime.exercise, exercise); XCTAssertEqual(runtime.reviewedSlotID, slot)
        XCTAssertEqual(runtime.numericValue, "29"); XCTAssertEqual(runtime.scratchpad, "keep my reasoning")
        XCTAssertEqual(store.localSessions.archive.offlineRotationLedger, ledger)
        XCTAssertEqual(store.attempts.count, 1)
    }

    func testReviewedChoiceRetryRetainsCommandIdentityAndNeverAcceptsBeforeDraftSave() throws {
        let root = try root(); defer { try? FileManager.default.removeItem(at: root) }
        let container = try container(root), store = try store(root, context: container.mainContext, admissions: catalog())
        let runtime = try launch(store); defer { runtime.releaseWriter() }
        runtime.numericValue = "retained draft"
        runtime.chooseReviewedChallenge(.harder, store: store)
        let id = try XCTUnwrap(runtime.reviewedChoice?.id)
        let url = root.appending(path: "sessions-v1.json"), backup = root.appending(path: "original-sessions.json")
        try FileManager.default.moveItem(at: url, to: backup)
        XCTAssertFalse(runtime.applyReviewedChoice(.nextQuestion, store: store))
        XCTAssertEqual(runtime.reviewedChoice?.id, id)
        XCTAssertNil(store.localSessions.archive.editorialOverrideCommands)
        XCTAssertEqual(runtime.numericValue, "retained draft")
        try FileManager.default.moveItem(at: backup, to: url)
        XCTAssertTrue(runtime.applyReviewedChoice(.nextQuestion, store: store), runtime.saveError ?? "")
        XCTAssertEqual(store.localSessions.archive.editorialOverrideCommands?.count, 1)
        XCTAssertNotNil(store.localSessions.archive.editorialOverrideCommands?[id.uuidString])
        XCTAssertFalse(runtime.applyReviewedChoice(.nextQuestion, store: store), "An already accepted UI action must not create a second command")
    }

    func testReviewedReplaceRetainsOriginalAndRejectsDelayedMenuFromPriorSlot() throws {
        let root = try root(); defer { try? FileManager.default.removeItem(at: root) }
        let container = try container(root), store = try store(root, context: container.mainContext, admissions: catalog())
        let runtime = try launch(store); defer { runtime.releaseWriter() }
        runtime.numericValue = "17"; runtime.scratchpad = "original reasoning"
        let prior = runtime.reviewedSlotID, index = runtime.index
        runtime.chooseReviewedChallenge(.harder, store: store, expectedSlotID: prior)
        XCTAssertTrue(runtime.applyReviewedChoice(.replaceCurrent, store: store), runtime.saveError ?? runtime.reviewedChallengeError ?? "")
        XCTAssertNotEqual(runtime.reviewedSlotID, prior); XCTAssertEqual(runtime.index, index)
        XCTAssertEqual(runtime.scratchpad, "original reasoning"); XCTAssertTrue(store.attempts.isEmpty)
        XCTAssertFalse(runtime.canChooseReviewedChallenge)
        runtime.acknowledgePresented()
        runtime.chooseReviewedChallenge(.easier, store: store, expectedSlotID: prior)
        XCTAssertNil(runtime.reviewedChoice)
        XCTAssertEqual(store.localSessions.archive.editorialOverrideCommands?.count, 1)
        XCTAssertEqual(runtime.reviewedChallengePresentation(store: store)?.deliveredBand, .b2)
    }

    func testReviewedFeedbackAllowsOnlyNextChoiceAndPauseBlocksAllChoiceCommands() throws {
        let root = try root(); defer { try? FileManager.default.removeItem(at: root) }
        let container = try container(root), store = try store(root, context: container.mainContext, admissions: catalog())
        let runtime = try launch(store); defer { runtime.releaseWriter() }
        try answer(runtime, store: store)
        XCTAssertEqual(runtime.stage, .feedback)
        runtime.chooseReviewedChallenge(.keepThisLevel, store: store)
        let id = try XCTUnwrap(runtime.reviewedChoice?.id)
        XCTAssertFalse(runtime.applyReviewedChoice(.replaceCurrent, store: store))
        runtime.pause()
        XCTAssertFalse(runtime.applyReviewedChoice(.nextQuestion, store: store))
        XCTAssertNil(store.localSessions.archive.editorialOverrideCommands)
        XCTAssertEqual(runtime.reviewedChoice?.id, id)
        runtime.resume()
        XCTAssertTrue(runtime.applyReviewedChoice(.nextQuestion, store: store), runtime.saveError ?? "")
        XCTAssertEqual(runtime.reviewedChallengePresentation(store: store)?.pendingChallengeMode, .fixedBand(.b1))
        XCTAssertEqual(store.attempts.count, 1)
    }

    func testReviewedUIHidesControlsForReleasedUnreviewedPractice() throws {
        let root = try root(); defer { try? FileManager.default.removeItem(at: root) }
        let container = try container(root), store = try store(root, context: container.mainContext, admissions: .released)
        let runtime = try launch(store); defer { runtime.releaseWriter() }
        XCTAssertNil(runtime.reviewedChallengePresentation(store: store))
        runtime.chooseReviewedChallenge(.harder, store: store)
        XCTAssertNil(runtime.reviewedChoice)
        XCTAssertTrue(runtime.separateReviewedBands(store: store).isEmpty)
        XCTAssertFalse(runtime.startSeparateReviewedActivity(.b2, store: store))
        XCTAssertNil(store.localSessions.archive.editorialOverrideCommands)
    }
    func testReviewedChoiceCannotApplyAfterAnotherWindowTakesOwnership() throws {
        let root = try root(); defer { try? FileManager.default.removeItem(at: root) }
        let container = try container(root), store = try store(root, context: container.mainContext, admissions: catalog())
        let runtime = try launch(store); defer { runtime.releaseWriter() }
        runtime.chooseReviewedChallenge(.harder, store: store)
        let original = try XCTUnwrap(runtime.reviewedChoice)
        let other = NFUniversalSessionRuntime(request: runtime.request)
        other.takeOver(store: store); defer { other.releaseWriter() }
        XCTAssertFalse(runtime.ownsWriter); XCTAssertTrue(other.ownsWriter)
        XCTAssertFalse(runtime.applyReviewedChoice(.nextQuestion, store: store))
        XCTAssertNil(store.localSessions.archive.editorialOverrideCommands)
        runtime.takeOver(store: store); runtime.resume(); runtime.acknowledgePresented()
        XCTAssertNil(runtime.reviewedChoice, "Taking ownership restores the last accepted snapshot, not an old unaccepted command")
        runtime.chooseReviewedChallenge(.harder, store: store)
        let renewed = try XCTUnwrap(runtime.reviewedChoice)
        XCTAssertNotEqual(renewed.id, original.id)
        XCTAssertNotEqual(renewed.writerAuthority, original.writerAuthority)
    }

    func testSeparateReviewedUIReleasesOnlyOldWriterAndKeepsItsExactFixedDraft() throws {
        let root = try root(); defer { try? FileManager.default.removeItem(at: root) }
        let container = try container(root)
        var store = try store(root, context: container.mainContext, admissions: .released)
        XCTAssertTrue(store.beginSession(lab: .mentalMath, source: .focused, field: .general,
            targetDifficulty: 0.5, requestedItemCount: 8, seedOverride: seed,
            isTimed: false, timingCondition: .init(.untimed), launchLocaleIdentifier: "en", reservationStrategy: .fixedBlock))
        let originalRequest = try XCTUnwrap(store.activeSessionRequest)
        let first = NFUniversalSessionRuntime(request: originalRequest)
        XCTAssertTrue(first.checkpointDraft(store: store)); first.resume(); first.acknowledgePresented()
        guard case .logicState = first.exercise.interaction else { return XCTFail("Expected the pinned estimate/exact fixed question") }
        first.logicState[NFEstimateExactContract.estimateKey] = "120"
        first.scratchpad = "retained fixed reasoning"
        let originalResponse = NFExerciseResponse.logicState(.init(finalState: first.logicState, violatedRuleID: nil))
        let originalMathWork = first.mathWork
        first.pause()
        XCTAssertTrue(first.checkpointDraft(store: store)); first.releaseWriter()
        let newTemplate = SessionRequest(lab: .mentalMath, source: .focused, seed: originalRequest.seed,
            localeIdentifier: "en", field: .general, targetDifficulty: 0.5, requestedItemCount: 8,
            isTimed: false, timingCondition: .init(.untimed))
        store = try self.store(root, context: container.mainContext, admissions: catalog(requestOverride: newTemplate))
        XCTAssertTrue(store.resumeSession(originalRequest.id))
        let resumed = NFUniversalSessionRuntime(request: try XCTUnwrap(store.activeSessionRequest))
        XCTAssertTrue(resumed.checkpointDraft(store: store)); resumed.resume(); resumed.acknowledgePresented()
        let fixed = store.localSessions.archive.fixedLaunchReceipts
        XCTAssertTrue(resumed.startSeparateReviewedActivity(.b2, store: store), resumed.reviewedChallengeError ?? resumed.saveError ?? "")
        XCTAssertNotEqual(store.activeSessionRequest?.id, originalRequest.id)
        XCTAssertEqual(store.localSessions.archive.fixedLaunchReceipts, fixed)
        let retained = try XCTUnwrap(store.localSessions.archive.sessions.first { $0.id == originalRequest.id })
        XCTAssertEqual(retained.checkpoint.response, originalResponse)
        XCTAssertEqual(retained.checkpoint.scratchpad, "retained fixed reasoning")
        XCTAssertEqual(retained.checkpoint.mathWork, originalMathWork)
        XCTAssertEqual(retained.status, .suspended)
        XCTAssertFalse(resumed.ownsWriter); XCTAssertFalse(resumed.canChooseReviewedChallenge)
        XCTAssertNil(store.activeSessionRequest?.planBlockID)
        XCTAssertTrue(store.attempts.isEmpty)
    }

}


@MainActor
extension EditorialLiveControllerPersistenceTests {
    private func mixedCatalog(baseCounts: [Int] = [12, 12, 12, 12], higherCount: Int = 5) throws -> NFEditorialAdmissionContext {
        let request = template()
        var demands: [(Int, NFEditorialBand, Int)] = []
        for (family, count) in baseCounts.enumerated() {
            for index in 0..<count { demands.append((family, .b1, index)) }
            for index in 0..<higherCount { demands.append((family, .b2, index)) }
        }
        var entries: [NFEditorialAdmissionEntry] = [], seen: Set<String> = []
        for questionID in NFOfflineQuestionBank.rotationBank.questionIDs(for: .mentalMath) {
            guard let ordinal = NFOfflineQuestionBank.ordinal(forQuestionID: questionID, lab: .mentalMath) else { continue }
            let exercise = NFDeterministicSessionExerciseFactory.makeExercise(request: request.launchOnly(offlineQuestionOrdinals: [ordinal]), index: 0, assessmentDescriptor: nil)
            guard exercise.availabilityReason == nil, case .numeric = exercise.interaction,
                  let metadata = exercise.contractMetadata, seen.insert(metadata.semanticFingerprint).inserted else { continue }
            let (family, band, offset) = demands[entries.count]
            let demand = NFEditorialDemandRecord(objectiveID: "QA.mixed.objective.\(family)", familyID: "QA.mixed.family.\(family)",
                structureID: "QA.mixed.structure.\(family).\(offset % 3)", semanticFingerprint: metadata.semanticFingerprint,
                editorialBand: band, demandVector: .init(reasoningSteps: band.ordinal,
                    quantityDomain: ["source": "synthetic family coordination fixture"], representationMappings: ["numeric"],
                    misconceptionClasses: [], abstraction: "concrete", relevantGivens: 2, irrelevantGivens: 0, missingGivens: 0,
                    scaffoldConditionID: "essential-only", prerequisiteConceptIDs: []),
                bandContractVersion: "QA.mixed.band.v1", calibrationStatus: .editorial, calibrationVersion: nil,
                independentEligible: true, protectedEligible: false, assistancePolicyID: NFEditorialNativeProtocol.toolConditionID,
                answerContractVersion: "QA.exact-native.v1", expectedDurationRange: .init(minimumSeconds: 10, maximumSeconds: 40),
                representationIDs: ["numeric"], prerequisiteObjectiveIDs: [])
            entries.append(.init(id: "QA.mixed.entry.\(entries.count)", bankQuestionID: questionID,
                exerciseDigest: try NFLocalItemCheckpoint.digest(exercise), scorerVersion: NFExerciseScoringEngine.scoringVersion,
                lab: .mentalMath, contentLocale: "en", demand: demand))
            if entries.count == demands.count { break }
        }
        XCTAssertEqual(entries.count, demands.count, "The trusted fixture must bind enough actual native questions")
        return .init(version: "QA.trusted-mixed.v1", entries: entries)
    }
    private func launchMixed(_ store: AppStore, count: Int = 10, commandID: UUID = UUID()) throws -> NFUniversalSessionRuntime {
        XCTAssertTrue(store.beginSession(lab: .mentalMath, source: .focused, field: .general,
            targetDifficulty: 0.5, requestedItemCount: count, seedOverride: seed,
            isTimed: false, timingCondition: .init(.untimed), launchLocaleIdentifier: "en", launchCommandID: commandID), store.lastErrorMessage ?? "")
        let request = try XCTUnwrap(store.activeSessionRequest)
        XCTAssertTrue(request.ordinaryDelivery?.editorialPolicy?.isMixed == true)
        let runtime = NFUniversalSessionRuntime(request: request)
        XCTAssertTrue(runtime.checkpointDraft(store: store)); runtime.resume(); runtime.acknowledgePresented()
        return runtime
    }

    func testActualMixedTenBalancesFourFamiliesAndRetainsOneSlotPerAcceptance() throws {
        let root = try root(); defer { try? FileManager.default.removeItem(at: root) }
        let container = try container(root), admissions = try mixedCatalog()
        let store = try store(root, context: container.mainContext, admissions: admissions)
        let runtime = try launchMixed(store); defer { runtime.releaseWriter() }
        var families: [String] = []
        for index in 0..<10 {
            let selected = try receipt(store), mixed = try XCTUnwrap(selected.mixedDecision)
            XCTAssertEqual(selected.schemaVersion, 5); XCTAssertEqual(mixed.globalDecisionOrdinal, UInt64(index))
            XCTAssertEqual(mixed.history.sessionCount, index)
            XCTAssertEqual(store.localSessions.archive.selectionLedger?.slots.count, index + 1)
            families.append(mixed.selectedScope.key)
            try answer(runtime, store: store); runtime.next(store: store); XCTAssertNil(runtime.saveError)
        }
        XCTAssertEqual(Set(families).count, 4)
        let counts = families.reduce(into: [String: Int]()) { $0[$1, default: 0] += 1 }
        XCTAssertLessThanOrEqual(counts.values.max() ?? 0, 3)
        for index in 2..<families.count { XCTAssertFalse(families[index] == families[index - 1] && families[index] == families[index - 2]) }
        XCTAssertEqual(store.attempts.count, 10)
        XCTAssertEqual(store.localSessions.archive.selectionLedger?.exposures.count, 10)
    }

    func testMixedFamilySelectionIsUnaffectedByPoolOrderOrOneLargeParameterFamily() throws {
        let leftRoot = try root(), rightRoot = try root()
        defer { try? FileManager.default.removeItem(at: leftRoot); try? FileManager.default.removeItem(at: rightRoot) }
        let admissions = try mixedCatalog(baseCounts: [30, 5, 5, 5], higherCount: 0)
        let reversed = NFEditorialAdmissionContext(version: admissions.version, entries: Array(admissions.entries.reversed()))
        XCTAssertEqual(reversed.fingerprint, admissions.fingerprint)
        let leftContainer = try container(leftRoot), rightContainer = try container(rightRoot), command = UUID()
        let left = try store(leftRoot, context: leftContainer.mainContext, admissions: admissions)
        let right = try store(rightRoot, context: rightContainer.mainContext, admissions: reversed)
        let a = try launchMixed(left, commandID: command), b = try launchMixed(right, commandID: command)
        defer { a.releaseWriter(); b.releaseWriter() }
        var families: [String] = []
        for _ in 0..<10 {
            XCTAssertEqual(try receipt(left).plan.items.first?.questionID, try receipt(right).plan.items.first?.questionID)
            families.append(try XCTUnwrap(try receipt(left).mixedDecision).selectedScope.familyID)
            try answer(a, store: left); try answer(b, store: right)
            a.next(store: left); b.next(store: right)
            XCTAssertNil(a.saveError); XCTAssertNil(b.saveError)
        }
        XCTAssertLessThanOrEqual(families.filter { $0 == "QA.mixed.family.0" }.count, 3)
        XCTAssertEqual(Set(families).count, 4)
    }

    func testMixedSparseCatalogReportsReducedScopeWithoutInventingFamilies() throws {
        let root = try root(); defer { try? FileManager.default.removeItem(at: root) }
        let container = try container(root), admissions = try mixedCatalog(baseCounts: [8, 8], higherCount: 0)
        let store = try store(root, context: container.mainContext, admissions: admissions)
        let runtime = try launchMixed(store); defer { runtime.releaseWriter() }
        for _ in 0..<4 {
            let mixed = try XCTUnwrap(try receipt(store).mixedDecision)
            XCTAssertEqual(mixed.feasibleFamilyKeys.count, 2)
            XCTAssertTrue(mixed.unmetVarietyPreferences.contains("fewerThanFourCompatibleFamilies"))
            XCTAssertEqual(store.localSessions.editorialChallengePresentation(sessionID: runtime.sessionID)?.mixedFeasibleFamilyCount, 2)
            try answer(runtime, store: store); runtime.next(store: store)
        }
        XCTAssertEqual(try receipt(store).mixedDecision?.stateAfter.lastDecisionByFamily.count, 2)
    }

    func testMixedManualHarderAppliesNextWithinCurrentFamilyWithoutRaisingOthers() throws {
        let root = try root(); defer { try? FileManager.default.removeItem(at: root) }
        let container = try container(root), admissions = try mixedCatalog()
        let store = try store(root, context: container.mainContext, admissions: admissions)
        let runtime = try launchMixed(store); defer { runtime.releaseWriter() }
        let original = try receipt(store), scope = try XCTUnwrap(original.mixedDecision).selectedScope
        let command = try chooseNext(.harder, runtime: runtime, store: store)
        XCTAssertEqual(command.familyID, scope.familyID)
        XCTAssertEqual(try receipt(store), original, "Preference cannot rewrite the delivered family or key")
        try answer(runtime, store: store); runtime.next(store: store)
        let harder = try receipt(store)
        XCTAssertEqual(harder.mixedDecision?.selectedScope, scope)
        XCTAssertEqual(harder.editorialDecision?.selection.deliveredBand, .b2)
        XCTAssertEqual(harder.editorialDecision?.controlAfter.totalAutomaticChangesThisSession, 0)
        XCTAssertEqual(harder.mixedDecision?.stateAfter.lastDecisionByFamily.count, 1)
        try answer(runtime, store: store); runtime.next(store: store)
        let other = try receipt(store)
        XCTAssertNotEqual(other.mixedDecision?.selectedScope, scope)
        XCTAssertEqual(other.editorialDecision?.selection.deliveredBand, .b1)
        XCTAssertEqual(other.editorialDecision?.controlAfter.decisionOrdinal, 1)
        XCTAssertEqual(other.mixedDecision?.stateAfter.lastDecisionByFamily[scope.key], harder.decisionID)
    }

    func testMixedSkipAndRevealAdvanceGlobalSupportWithoutAcademicEvidence() throws {
        let root = try root(); defer { try? FileManager.default.removeItem(at: root) }
        let container = try container(root), admissions = try mixedCatalog()
        let store = try store(root, context: container.mainContext, admissions: admissions)
        let runtime = try launchMixed(store); defer { runtime.releaseWriter() }
        try answer(runtime, store: store, hint: true); runtime.next(store: store)
        for _ in 0..<2 { runtime.acknowledgePresented(); runtime.skip(store: store); XCTAssertNil(runtime.saveError) }
        try answer(runtime, store: store, hint: true); runtime.next(store: store)
        let mixed = try XCTUnwrap(try receipt(store).mixedDecision)
        XCTAssertEqual(mixed.stateAfter.recentSupportPresentations.map(\.usedSupport), [false, false, true])
        XCTAssertFalse(store.localSessions.editorialChallengePresentation(sessionID: runtime.sessionID)?.shouldOfferSupport ?? true)
        for _ in 0..<2 { runtime.acknowledgePresented(); runtime.revealSolution(store: store); runtime.skip(store: store) }
        XCTAssertTrue(store.localSessions.editorialChallengePresentation(sessionID: runtime.sessionID)?.shouldOfferSupport == true)
        XCTAssertTrue(try receipt(store).editorialDecision?.evidence.independentObservationIDs.isEmpty == true)
        XCTAssertEqual(try receipt(store).mixedDecision?.history.sessionCount, 6)
    }

    func testMixedColdReplayRetainsDeferredOwnFamilyResponseAndControlLineage() throws {
        let root = try root(); defer { try? FileManager.default.removeItem(at: root) }
        let admissions = try mixedCatalog(); var expected: NFLocalAdaptiveItemReceipt!
        do {
            let container = try container(root, persistent: true)
            let store = try store(root, context: container.mainContext, admissions: admissions)
            let runtime = try launchMixed(store)
            for _ in 0..<3 { try answer(runtime, store: store); runtime.next(store: store) }
            runtime.pause(); XCTAssertTrue(runtime.checkpointDraft(store: store)); runtime.releaseWriter()
            expected = try receipt(store)
            XCTAssertEqual(expected.mixedDecision?.stateAfter.pendingByFamily.count, 3)
        }
        let container = try container(root, persistent: true)
        let store = try store(root, context: container.mainContext, admissions: admissions)
        XCTAssertNil(store.localSessions.loadError); XCTAssertEqual(try receipt(store), expected)
        let saved = try XCTUnwrap(store.localSessions.archive.sessions.first)
        var request = saved.request; request.localCheckpoint = saved.checkpoint; request.localSessionID = saved.id
        let runtime = NFUniversalSessionRuntime(request: request); defer { runtime.releaseWriter() }
        XCTAssertTrue(runtime.checkpointDraft(store: store)); runtime.resume(); runtime.acknowledgePresented()
        try answer(runtime, store: store); runtime.next(store: store)
        let next = try receipt(store), nextDecision = try XCTUnwrap(next.editorialDecision)
        let family = try XCTUnwrap(next.mixedDecision).selectedScope
        let priorID = try XCTUnwrap(expected.mixedDecision?.stateAfter.lastDecisionByFamily[family.key])
        XCTAssertEqual(nextDecision.controlBefore, store.localSessions.archive.adaptiveItemReceipts?[priorID]?.editorialDecision?.controlAfter)
        XCTAssertEqual(nextDecision.controlAfter.currentBandDecisionResponseIDs.count, 1)
        XCTAssertEqual(next.mixedDecision?.stateAfter.pendingByFamily.count, 3)
    }

    func testMixedCorrectionBetweenPrepareAndAcceptRejectsWholeChoiceAndRetainsPriorSlot() throws {
        let root = try root(); defer { try? FileManager.default.removeItem(at: root) }
        let container = try container(root), admissions = try mixedCatalog()
        let store = try store(root, context: container.mainContext, admissions: admissions)
        let runtime = try launchMixed(store); defer { runtime.releaseWriter() }
        try answer(runtime, store: store)
        let predecessor = try XCTUnwrap(store.localSessions.archive.sessions.first), original = try receipt(store)
        let prepared = try store.prepareAdaptiveItem(request: predecessor.request, predecessor: predecessor.checkpoint,
            command: try runtime.sessionWriterCommand())
        let cursor = store.localSessions.archive.offlineRotationLedger
        let attempt = try XCTUnwrap(store.attempts.first)
        try store.localSessions.appendDispositions([.init(id: "QA.mixed.corrected", attemptID: attempt.id.uuidString,
            revision: 1, policyVersion: NFHistoricalPracticeProjection.policyVersion, occurredAt: Date(),
            disposition: .excludedContentCorrection, reason: "Synthetic correction before mixed acceptance",
            correctedDerivedCredit: nil, supersedesDispositionID: nil)])
        XCTAssertThrowsError(try store.acceptAdaptiveItem(prepared, checkpoint: prepared.checkpoint))
        XCTAssertEqual(try receipt(store), original); XCTAssertEqual(store.localSessions.archive.offlineRotationLedger, cursor)
        let refreshed = try store.prepareAdaptiveItem(request: predecessor.request, predecessor: predecessor.checkpoint,
            command: try runtime.sessionWriterCommand())
        XCTAssertTrue(refreshed.receipt.editorialDecision?.evidence.independentObservationIDs.isEmpty == true)
        XCTAssertNotEqual(refreshed.receipt.editorialDecision?.evidenceDigest, prepared.receipt.editorialDecision?.evidenceDigest)
        runtime.next(store: store)
        XCTAssertNil(runtime.saveError)
        XCTAssertEqual(try receipt(store).slotID, refreshed.receipt.slotID)
    }

    func testMixedReplaceKeepsFamilyAndRetiredDraftWhileNextResumesVariety() throws {
        let root = try root(); defer { try? FileManager.default.removeItem(at: root) }
        let container = try container(root), admissions = try mixedCatalog()
        let store = try store(root, context: container.mainContext, admissions: admissions)
        let runtime = try launchMixed(store); defer { runtime.releaseWriter() }
        runtime.numericValue = "unfinished learner answer"; runtime.pause(); XCTAssertTrue(runtime.checkpointDraft(store: store))
        let previous = try XCTUnwrap(store.localSessions.archive.sessions.first), original = try receipt(store)
        let preparation = try store.prepareAdaptiveReplacement(request: previous.request, predecessor: previous.checkpoint,
            command: try runtime.sessionWriterCommand())
        let accepted = try store.acceptAdaptiveItem(preparation, checkpoint: preparation.checkpoint)
        XCTAssertEqual(preparation.receipt.mixedDecision?.selectedScope, original.mixedDecision?.selectedScope)
        XCTAssertEqual(accepted.checkpoint.index, previous.checkpoint.index)
        XCTAssertNotEqual(accepted.checkpoint.slotID, previous.checkpoint.slotID)
        XCTAssertEqual(store.localSessions.archive.retiredOrdinaryDrafts?[previous.checkpoint.slotID.uuidString]?.checkpoint.response, previous.checkpoint.response)
        XCTAssertEqual(store.localSessions.archive.selectionLedger?.slots.count, 2)
        XCTAssertEqual(try NFEditorialCanonicalData.digest(store.acceptAdaptiveItem(preparation, checkpoint: preparation.checkpoint)),
            try NFEditorialCanonicalData.digest(accepted))
    }

    func testUnknownMixedPolicyIsRetainedReadOnlyAndCannotBecomeSingleFamilyAuthority() throws {
        let root = try root(); defer { try? FileManager.default.removeItem(at: root) }
        let container = try container(root), admissions = try mixedCatalog()
        let store = try store(root, context: container.mainContext, admissions: admissions)
        let runtime = try launchMixed(store); runtime.pause(); XCTAssertTrue(runtime.checkpointDraft(store: store)); runtime.releaseWriter()
        let url = root.appending(path: "sessions-v1.json")
        var archive = try JSONDecoder().decode(NFLocalSessionRepository.Archive.self, from: Data(contentsOf: url))
        archive.sessions[0].request.ordinaryDelivery?.editorialPolicy?.controllerVersion = "EditorialMixedControllerV999"
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(archive).write(to: url, options: .atomic)
        let reopened = try self.store(root, context: container.mainContext, admissions: admissions)
        XCTAssertNil(reopened.localSessions.loadError)
        XCTAssertEqual(reopened.localSessions.archive.sessions.first?.status, .migrationRecovery)
        XCTAssertNil(reopened.localSessions.editorialChallengePresentation(sessionID: runtime.sessionID))
        XCTAssertEqual(reopened.localSessions.archive.sessions.first?.checkpoint.exercise, archive.sessions.first?.checkpoint.exercise)
        XCTAssertEqual(reopened.localSessions.archive.sessions.first?.checkpoint, archive.sessions.first?.checkpoint)
        XCTAssertEqual(reopened.localSessions.archive.adaptiveItemReceipts, archive.adaptiveItemReceipts)
        let retained = try Data(contentsOf: url)
        XCTAssertThrowsError(try reopened.prepareAdaptiveItem(request: archive.sessions[0].request,
            predecessor: archive.sessions[0].checkpoint))
        XCTAssertEqual(try Data(contentsOf: url), retained)
    }
}

@MainActor
extension EditorialLiveControllerPersistenceTests {
    func testMixedFailurePublishesNeitherFamilyStateNorCursorAndSameLaunchRetries() throws {
        let root = try root(); defer { try? FileManager.default.removeItem(at: root) }
        let blocked = root.appending(path: "blocked"); try Data("retain this predecessor".utf8).write(to: blocked)
        let container = try container(root), admissions = try mixedCatalog()
        let store = try store(root, context: container.mainContext, admissions: admissions, repositoryURL: blocked.appending(path: "sessions-v1.json"))
        let id = UUID()
        XCTAssertFalse(store.beginSession(lab: .mentalMath, source: .focused, field: .general,
            targetDifficulty: 0.5, requestedItemCount: 10, seedOverride: seed,
            isTimed: false, timingCondition: .init(.untimed), launchLocaleIdentifier: "en", launchCommandID: id))
        XCTAssertNil(store.localSessions.archive.offlineRotationLedger)
        XCTAssertNil(store.localSessions.archive.adaptiveItemReceipts)
        XCTAssertTrue(store.localSessions.archive.sessions.isEmpty)
        XCTAssertEqual(try Data(contentsOf: blocked), Data("retain this predecessor".utf8))
        try FileManager.default.removeItem(at: blocked); try FileManager.default.createDirectory(at: blocked, withIntermediateDirectories: true)
        let runtime = try launchMixed(store, commandID: id); defer { runtime.releaseWriter() }
        runtime.pause(); XCTAssertTrue(runtime.checkpointDraft(store: store))
        let before = try receipt(store), saved = try XCTUnwrap(store.localSessions.archive.sessions.first)
        let replay = try store.prepareAdaptiveItem(request: saved.request, predecessor: nil)
        XCTAssertEqual(try store.acceptAdaptiveItem(replay, checkpoint: replay.checkpoint).checkpoint, saved.checkpoint)
        XCTAssertEqual(try receipt(store), before)
        XCTAssertEqual(store.localSessions.archive.adaptiveItemReceipts?.count, 1)
        XCTAssertEqual(before.mixedDecision?.stateAfter.lastDecisionByFamily.count, 1)
    }

    func testMixedQuotaRankingUsesActualFamilyShareAndReportsExplicitInfeasibility() throws {
        let root = try root(); defer { try? FileManager.default.removeItem(at: root) }
        let container = try container(root), admissions = try mixedCatalog()
        let store = try store(root, context: container.mainContext, admissions: admissions)
        let runtime = try launchMixed(store); defer { runtime.releaseWriter() }
        let pin = try XCTUnwrap(runtime.request.ordinaryDelivery?.editorialPolicy)
        let current = try XCTUnwrap(try receipt(store).editorialDecision)
        let input = NFEditorialLiveController.Input(observations: [], validity: .init(), day: current.decisionDay)
        let candidates = admissions.entries.map { NFEditorialSelectionCandidate(id: $0.bankQuestionID, item: $0.demand) }
        let byID = Dictionary(uniqueKeysWithValues: admissions.entries.map { ($0.bankQuestionID, $0) })
        var contracts: [String: NFEditorialCriterionSelection] = [:]
        var initialContracts: [NFEditorialInitialTargetContract] = []
        for entry in admissions.entries {
            let ordinal = try XCTUnwrap(NFOfflineQuestionBank.ordinal(forQuestionID: entry.bankQuestionID, lab: runtime.request.lab))
            let exercise = NFDeterministicSessionExerciseFactory.makeExercise(
                request: runtime.request.launchOnly(offlineQuestionOrdinals: [ordinal]), index: 0, assessmentDescriptor: nil)
            XCTAssertEqual(admissions.entry(exercise: exercise, pin: pin), entry)
            let contract = try XCTUnwrap(NFEditorialCriterionRankingPolicy.contract(exercise: exercise, admission: entry, timing: .untimed))
            XCTAssertEqual(contract.preference, 0)
            contracts[entry.bankQuestionID] = contract
            initialContracts.append(.make(exercise: exercise, admission: entry))
        }
        let context = NFEditorialSelectionContext(catalogVersion: pin.catalogVersion, profilePseudonymousID: profileID.uuidString,
            remainingSittingSeconds: 1_000, initialTargetContracts: initialContracts, criterionSelections: contracts)
        var decisions: [String: NFEditorialControllerDecision] = [:]
        for scope in pin.scopes {
            decisions[scope.key] = try XCTUnwrap(NFEditorialLiveController.decide(pin: pin.singleFamily(scope), sessionID: runtime.sessionID.uuidString,
                previous: nil, committedID: nil, input: input, candidates: candidates, admissions: byID, context: context))
        }
        let keys = pin.scopes.map(\.key)
        // All four families were covered. The current 99 displayed slots are
        // 40/25/20/14, and the last two belong to the overrepresented family.
        let counts = [keys[0]: 40, keys[1]: 25, keys[2]: 20, keys[3]: 14]
        let history = NFEditorialMixedHistory(exposureDigest: String(repeating: "a", count: 64), recentCount: 99, recentSemanticCount: 99,
            recentFamilyCounts: counts, recentStructureCounts: ["QA.structure": 99], recentRepresentationCounts: ["numeric": 99],
            sessionCount: 8, sessionSemanticCount: 8, sessionFamilyCounts: [keys[0]: 2, keys[1]: 2, keys[2]: 2, keys[3]: 2],
            sessionStructureCounts: ["QA.structure": 8], sessionRepresentationCounts: ["numeric": 8], previousFamilyKey: keys[0], previousFamilyRunCount: 2)
        func choose(_ forced: String?) throws -> NFEditorialMixedDecision {
            try XCTUnwrap(NFEditorialMixedController.select(decisions: decisions,
                candidates: Dictionary(uniqueKeysWithValues: candidates.map { ($0.id, $0) }), feasibleFamilyKeys: keys,
                pin: pin, sessionID: runtime.sessionID.uuidString, profileID: profileID.uuidString, ordinal: 8, decisionID: "QA.next",
                before: .init(), outgoing: nil, history: history, explicitlySelectedFamily: forced))
        }
        let balanced = try choose(nil)
        XCTAssertEqual(balanced.selectedScope.key, keys[3])
        XCTAssertFalse(balanced.unmetVarietyPreferences.contains("familyRunAboveTwo"))
        XCTAssertFalse(balanced.unmetVarietyPreferences.contains("rollingFamilyShareAbove35Percent"))
        let explicit = try choose(keys[0])
        XCTAssertEqual(explicit.selectedScope.key, keys[0], "Variety cannot redirect an explicit same-family request")
        XCTAssertTrue(explicit.unmetVarietyPreferences.contains("familyRunAboveTwo"))
        XCTAssertTrue(explicit.unmetVarietyPreferences.contains("rollingFamilyShareAbove35Percent"))
        XCTAssertTrue(explicit.unmetVarietyPreferences.contains("explicitFamilyChoiceLimitsVariety"))
    }

    func testMixedDeferredResponseCannotBeReattachedToAnotherFamilyOnColdLoad() throws {
        let root = try root(); defer { try? FileManager.default.removeItem(at: root) }
        let container = try container(root), admissions = try mixedCatalog()
        let store = try store(root, context: container.mainContext, admissions: admissions)
        let runtime = try launchMixed(store)
        try answer(runtime, store: store); runtime.next(store: store)
        runtime.pause(); XCTAssertTrue(runtime.checkpointDraft(store: store)); runtime.releaseWriter()
        let url = root.appending(path: "sessions-v1.json")
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        var receipts = try XCTUnwrap(object["adaptiveItemReceipts"] as? [String: [String: Any]])
        let currentID = try receipt(store).decisionID
        var current = try XCTUnwrap(receipts[currentID]), mixed = try XCTUnwrap(current["mixedDecision"] as? [String: Any])
        var after = try XCTUnwrap(mixed["stateAfter"] as? [String: Any])
        var pending = try XCTUnwrap(after["pendingByFamily"] as? [String: [String: Any]])
        let key = try XCTUnwrap(pending.keys.first); var event = try XCTUnwrap(pending[key])
        event["scope"] = ["objectiveID": "QA.other", "familyID": "QA.other"]
        pending[key] = event; after["pendingByFamily"] = pending; mixed["stateAfter"] = after
        current["mixedDecision"] = mixed; receipts[currentID] = current; object["adaptiveItemReceipts"] = receipts
        try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]).write(to: url, options: .atomic)
        let reopened = try self.store(root, context: container.mainContext, admissions: admissions)
        // Unsupported/malformed mixed state remains recovery-only; no fallback
        // to the prior single-family protocol can publish another question.
        XCTAssertTrue(reopened.localSessions.loadError != nil || reopened.localSessions.archive.sessions.first?.status == .migrationRecovery)
        XCTAssertNil(reopened.localSessions.editorialChallengePresentation(sessionID: runtime.sessionID))
    }
}

@MainActor
extension EditorialLiveControllerPersistenceTests {
    func testOnlyTheMixedFamilyWithFourIndependentSuccessesUsesItsAutomaticAllowance() throws {
        let root = try root(); defer { try? FileManager.default.removeItem(at: root) }
        let container = try container(root), admissions = try mixedCatalog()
        let store = try store(root, context: container.mainContext, admissions: admissions)
        let runtime = try launchMixed(store, count: 20); defer { runtime.releaseWriter() }
        let target = try XCTUnwrap(try receipt(store).mixedDecision).selectedScope
        for _ in 0..<20 {
            let selected = try XCTUnwrap(try receipt(store).mixedDecision)
            if selected.selectedScope == target {
                try answer(runtime, store: store); runtime.next(store: store)
            } else {
                runtime.acknowledgePresented(); runtime.skip(store: store)
            }
            XCTAssertNil(runtime.saveError)
        }
        let state = try XCTUnwrap(try receipt(store).mixedDecision).stateAfter
        let ownID = try XCTUnwrap(state.lastDecisionByFamily[target.key])
        let own = try XCTUnwrap(store.localSessions.archive.adaptiveItemReceipts?[ownID]?.editorialDecision)
        XCTAssertEqual(own.selection.deliveredBand, .b2)
        XCTAssertEqual(own.controlAfter.upwardChangesThisSession, 1)
        XCTAssertEqual(own.controlAfter.totalAutomaticChangesThisSession, 1)
        for (key, id) in state.lastDecisionByFamily where key != target.key {
            let other = try XCTUnwrap(store.localSessions.archive.adaptiveItemReceipts?[id]?.editorialDecision)
            XCTAssertEqual(other.selection.deliveredBand, .b1)
            XCTAssertEqual(other.controlAfter.upwardChangesThisSession, 0)
            XCTAssertEqual(other.controlAfter.totalAutomaticChangesThisSession, 0)
            XCTAssertTrue(other.controlAfter.currentBandDecisionResponseIDs.isEmpty)
        }
    }

    func testMixedPortableHistoryCannotImportFamilyControlAuthorityAndDeletionRemovesItsReferences() throws {
        let root = try root(); defer { try? FileManager.default.removeItem(at: root) }
        let container = try container(root), admissions = try mixedCatalog()
        let store = try store(root, context: container.mainContext, admissions: admissions)
        let runtime = try launchMixed(store)
        for _ in 0..<3 { try answer(runtime, store: store); runtime.next(store: store) }
        runtime.pause(); XCTAssertTrue(runtime.checkpointDraft(store: store)); runtime.releaseWriter()
        let attempt = try XCTUnwrap(store.attempts.first), before = store.localSessions.archive.offlineRotationLedger
        let foreign = NFLocalSessionRepository(ownerDeviceID: UUID(), editorialAdmissions: admissions)
        try foreign.importArchive(store.localSessions.exportArchive)
        XCTAssertNil(foreign.archive.adaptiveItemReceipts)
        XCTAssertNil(foreign.editorialChallengePresentation(sessionID: runtime.sessionID))
        XCTAssertEqual(foreign.archive.sessions.first?.checkpoint.exercise, store.localSessions.archive.sessions.first?.checkpoint.exercise)
        try store.localSessions.removeReferences(attemptIDs: [attempt.id])
        XCTAssertTrue(store.localSessions.archive.sessions.isEmpty)
        XCTAssertTrue(store.localSessions.archive.adaptiveItemReceipts?.isEmpty != false)
        XCTAssertEqual(store.localSessions.archive.offlineRotationLedger, before)
        XCTAssertNil(store.localSessions.editorialChallengePresentation(sessionID: runtime.sessionID))
    }
}


@MainActor
extension EditorialLiveControllerPersistenceTests {
    private var fluencyFamily: NFEditorialFamilyScope {
        .init(objectiveID: "QA.controller.arithmetic", familyID: "QA.controller.numeric")
    }
    private func launchFluencyPractice(_ store: AppStore, count: Int,
                                       condition: NFSessionTimingCondition = .init(.untimed)) throws -> NFUniversalSessionRuntime {
        XCTAssertTrue(store.beginSession(lab: .mentalMath, source: .focused, field: .general,
            targetDifficulty: 0.5, requestedItemCount: count, seedOverride: seed,
            isTimed: condition.mode != .untimed, timingCondition: condition, launchLocaleIdentifier: "en",
            editorialStartingBand: .b1, editorialStartingFamilyScope: fluencyFamily), store.lastErrorMessage ?? "")
        let runtime = NFUniversalSessionRuntime(request: try XCTUnwrap(store.activeSessionRequest))
        XCTAssertFalse(runtime.isDurablyPrepared)
        if condition.mode == .timedFluency {
            XCTAssertFalse(runtime.usesTimedMode); XCTAssertFalse(runtime.showsTimer); XCTAssertFalse(runtime.isTimingPresentationReady)
            XCTAssertFalse(runtime.canEditDraft); XCTAssertFalse(runtime.canSubmit)
        }
        XCTAssertTrue(runtime.checkpointDraft(store: store), runtime.saveError ?? "")
        runtime.resume(); runtime.acknowledgePresented()
        return runtime
    }
    private func collectFluencyPractice(_ store: AppStore) throws {
        let profile = try XCTUnwrap(store.profile)
        profile.timingModeRaw = TimingMode.adaptive.rawValue
        try store.context.save(); store.reload()
        for _ in 0..<2 {
            let runtime = try launchFluencyPractice(store, count: 4)
            for _ in 0..<4 {
                XCTAssertFalse(runtime.usesTimedMode)
                XCTAssertNil(runtime.exercise.contractMetadata?.editorialDemand)
                try answer(runtime, store: store); runtime.next(store: store)
                XCTAssertNil(runtime.saveError)
            }
            XCTAssertEqual(runtime.stage, .summary)
            runtime.releaseWriter(); store.activeSessionRequest = nil
        }
        let captures = store.localSessions.archive.snapshots.compactMap(\.editorialCapture)
        XCTAssertEqual(captures.count, 8)
        XCTAssertTrue(captures.allSatisfy { $0.authorityAtCommit == "admitted" && $0.profileID == profile.id })
        XCTAssertEqual(store.attempts.compactMap { store.effectiveAttemptDTO($0).editorialObservation }.count, 8)
    }

    func testActualExternalAdmissionsUnlockTimedFluencyAfterTwoSessionsAndSurviveNextAndColdResume() throws {
        let root = try root(); defer { try? FileManager.default.removeItem(at: root) }
        let container = try container(root, persistent: true)
        let admissions = try catalog(fluencyEligible: true)
        let store = try store(root, context: container.mainContext, admissions: admissions)
        try collectFluencyPractice(store)
        let readiness = store.reviewedFluencyReadiness(lab: .mentalMath, familyScope: fluencyFamily, band: .b1)
        XCTAssertTrue(readiness.timingEligible); XCTAssertEqual(readiness.sampleCount, 8)
        let condition = try XCTUnwrap(readiness.condition)
        let runtime = try launchFluencyPractice(store, count: 3, condition: condition)
        XCTAssertTrue(runtime.usesTimedMode)
        XCTAssertEqual(runtime.currentTimingCondition, condition)
        try answer(runtime, store: store); runtime.next(store: store)
        XCTAssertEqual(runtime.index, 1); XCTAssertTrue(runtime.usesTimedMode); XCTAssertNil(runtime.saveError)
        XCTAssertEqual(store.attempts.filter(\.wasTimed).count, 1)
        runtime.numericValue = "17"; XCTAssertTrue(runtime.checkpointDraft(store: store))
        let saved = try XCTUnwrap(store.localSessions.archive.sessions.first { $0.id == runtime.sessionID })
        runtime.releaseWriter(); store.activeSessionRequest = nil
        let reopened = try self.store(root, context: container.mainContext, admissions: admissions)
        XCTAssertTrue(reopened.resumeSession(saved.id))
        let cold = NFUniversalSessionRuntime(request: try XCTUnwrap(reopened.activeSessionRequest)); defer { cold.releaseWriter() }
        XCTAssertFalse(cold.isDurablyPrepared); XCTAssertFalse(cold.canSubmit); XCTAssertFalse(cold.usesTimedMode)
        XCTAssertFalse(cold.showsTimer); XCTAssertFalse(cold.isTimingPresentationReady)
        XCTAssertEqual(cold.exercise, saved.checkpoint.exercise); XCTAssertEqual(cold.numericValue, "17")
        XCTAssertTrue(cold.checkpointDraft(store: reopened), cold.saveError ?? "")
        cold.resume(); cold.acknowledgePresented()
        XCTAssertTrue(cold.usesTimedMode); XCTAssertEqual(cold.currentTimingCondition, condition)
        try answer(cold, store: reopened); cold.next(store: reopened)
        XCTAssertEqual(cold.index, 2); XCTAssertTrue(cold.usesTimedMode); XCTAssertNil(cold.saveError)
        XCTAssertEqual(reopened.attempts.filter(\.wasTimed).count, 2)
        XCTAssertEqual(reopened.reviewedFluencyReadiness(lab: .mentalMath, familyScope: fluencyFamily, band: .b1).sampleCount, 8,
            "Timed responses do not add untimed prerequisite observations or synthesize clean-speed evidence")
    }

    func testFluencyReadinessRejectsWrongFamilyBandProfileAndMutatedOriginalCommit() throws {
        let root = try root(); defer { try? FileManager.default.removeItem(at: root) }
        let container = try container(root)
        let store = try store(root, context: container.mainContext, admissions: catalog(fluencyEligible: true))
        try collectFluencyPractice(store)
        XCTAssertFalse(store.reviewedFluencyReadiness(lab: .mentalMath, familyScope: fluencyFamily, band: .b2).timingEligible)
        XCTAssertFalse(store.reviewedFluencyReadiness(lab: .mentalMath,
            familyScope: .init(objectiveID: fluencyFamily.objectiveID, familyID: "QA.other")).timingEligible)
        let record = try XCTUnwrap(store.attempts.first), original = NFImmutableAttemptRecordSnapshot(try XCTUnwrap(store.attempts.first))
        record.response = "{\"numeric\":{\"_0\":{\"value\":\"999999\"}}}"
        try store.context.save(); store.reload()
        XCTAssertFalse(store.reviewedFluencyReadiness(lab: .mentalMath).timingEligible)
        XCTAssertEqual(store.reviewedFluencyReadiness(lab: .mentalMath).sampleCount, 7)
        record.response = original.response; try store.context.save(); store.reload()
        XCTAssertTrue(store.reviewedFluencyReadiness(lab: .mentalMath).timingEligible)
        let profile = try XCTUnwrap(store.profile), originalProfileID = profile.id
        profile.id = UUID(); try store.context.save(); store.reload()
        XCTAssertFalse(store.reviewedFluencyReadiness(lab: .mentalMath).timingEligible)
        profile.id = originalProfileID; try store.context.save(); store.reload()
        XCTAssertTrue(store.reviewedFluencyReadiness(lab: .mentalMath).timingEligible)
        XCTAssertEqual(NFImmutableAttemptRecordSnapshot(record), original)
    }

    func testTimedLaunchRejectsWrongScopeAndColdManifestDriftWithoutPublishingDraftOrClock() throws {
        let root = try root(); defer { try? FileManager.default.removeItem(at: root) }
        let container = try container(root), admissions = try catalog(fluencyEligible: true)
        let store = try store(root, context: container.mainContext, admissions: admissions)
        try collectFluencyPractice(store)
        let ready = store.reviewedFluencyReadiness(lab: .mentalMath), condition = try XCTUnwrap(ready.condition)
        var rawScope = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(try XCTUnwrap(ready.scope))) as? [String: Any])
        rawScope["band"] = NFEditorialBand.b2.rawValue
        let wrongScope = try JSONDecoder().decode(NFEditorialEvidenceGroup.self, from: JSONSerialization.data(withJSONObject: rawScope))
        let before = try Data(contentsOf: root.appending(path: "sessions-v1.json"))
        XCTAssertFalse(store.beginSession(lab: .mentalMath, source: .focused, field: .general,
            targetDifficulty: 0.5, requestedItemCount: 2, seedOverride: seed,
            isTimed: true, timingCondition: .init(.timedFluency, fluencyScope: wrongScope), launchLocaleIdentifier: "en",
            editorialStartingBand: .b2, editorialStartingFamilyScope: fluencyFamily))
        XCTAssertNil(store.activeSessionRequest)
        XCTAssertEqual(try Data(contentsOf: root.appending(path: "sessions-v1.json")), before)
        let runtime = try launchFluencyPractice(store, count: 2, condition: condition)
        runtime.numericValue = "23"; XCTAssertTrue(runtime.checkpointDraft(store: store))
        let saved = try XCTUnwrap(store.localSessions.archive.sessions.first { $0.id == runtime.sessionID })
        runtime.releaseWriter(); store.activeSessionRequest = nil
        let changed = NFEditorialAdmissionContext(version: "QA.changed-manifest", entries: admissions.entries)
        let reopened = try self.store(root, context: container.mainContext, admissions: changed)
        XCTAssertFalse(reopened.reviewedFluencyReadiness(lab: .mentalMath).timingEligible)
        XCTAssertTrue(reopened.resumeSession(saved.id))
        let cold = NFUniversalSessionRuntime(request: try XCTUnwrap(reopened.activeSessionRequest)); defer { cold.releaseWriter() }
        let unchanged = try Data(contentsOf: root.appending(path: "sessions-v1.json"))
        cold.resume(); cold.acknowledgePresented()
        XCTAssertFalse(cold.isDurablyPrepared); XCTAssertFalse(cold.canEditDraft); XCTAssertFalse(cold.canSubmit); XCTAssertFalse(cold.usesTimedMode)
        XCTAssertFalse(cold.showsTimer); XCTAssertFalse(cold.isTimingPresentationReady)
        XCTAssertEqual(cold.sittingActiveElapsed(), saved.checkpoint.sittingActiveDuration ?? 0)
        XCTAssertFalse(cold.checkpointDraft(store: reopened)); XCTAssertNotNil(cold.saveError)
        XCTAssertFalse(cold.isDurablyPrepared); XCTAssertEqual(cold.numericValue, "23")
        XCTAssertEqual(try Data(contentsOf: root.appending(path: "sessions-v1.json")), unchanged)
        let released = try self.store(root, context: container.mainContext, admissions: .released)
        XCTAssertFalse(released.reviewedFluencyReadiness(lab: .mentalMath).timingEligible)
    }
}

@MainActor
extension EditorialLiveControllerPersistenceTests {
    func testFluencyActivityGateUsesExactContractWhenLegacyMechanicLabelIsAbsent() throws {
        let root = try root(); defer { try? FileManager.default.removeItem(at: root) }
        let container = try container(root)
        let activity = try XCTUnwrap(NFDefaultContentCatalog.activity(id: "nf.default.mental.compensation"))
        let store = try store(root, context: container.mainContext,
            admissions: catalog(fluencyEligible: true, activityID: activity.id))
        try collectFluencyPractice(store)
        XCTAssertTrue(store.attempts.allSatisfy { $0.assessmentMechanicID == nil })
        XCTAssertTrue(store.reviewedFluencyReadiness(lab: .mentalMath, mechanicID: activity.mechanicID,
            familyScope: fluencyFamily, band: .b1).timingEligible)
        XCTAssertFalse(store.reviewedFluencyReadiness(lab: .mentalMath, mechanicID: "QA.unrelated.activity",
            familyScope: fluencyFamily, band: .b1).timingEligible)
    }
}

@MainActor
extension EditorialLiveControllerPersistenceTests {
    func testTimingMatcherRequiresExternalExactAdmissionAndNeverTrustsEmbeddedDemand() throws {
        let admissions = try catalog(fluencyEligible: true)
        let entry = try XCTUnwrap(admissions.entries.first)
        let ordinal = try XCTUnwrap(NFOfflineQuestionBank.ordinal(forQuestionID: entry.bankQuestionID, lab: .mentalMath))
        let exercise = NFDeterministicSessionExerciseFactory.makeExercise(request: template().launchOnly(offlineQuestionOrdinals: [ordinal]),
            index: 0, assessmentDescriptor: nil)
        let demand = entry.demand
        let scope = NFEditorialEvidenceGroup(lane: .practice, objectiveID: demand.objectiveID, familyID: demand.familyID,
            band: demand.editorialBand, bandContractVersion: demand.bandContractVersion,
            scoringComparabilityID: demand.scoringComparabilityID ?? demand.answerContractVersion,
            stimulusComparabilityID: demand.stimulusComparabilityID ?? NFRetentionRepresentation.identifier(for: exercise),
            toolConditionID: demand.assistancePolicyID, localeComparabilityID: demand.localeComparabilityID ?? exercise.localeIdentifier,
            pacingConditionID: NFEditorialTimingMode.untimed.rawValue, protocolScope: "practice.v1")
        let condition = NFSessionTimingCondition(.timedFluency, fluencyScope: scope)
        XCTAssertFalse(condition.accepts(exercise)); XCTAssertTrue(admissions.acceptsTiming(condition, exercise: exercise))
        XCTAssertFalse(NFEditorialAdmissionContext.released.acceptsTiming(condition, exercise: exercise))
        var embedded = exercise; embedded.contractMetadata?.editorialDemand = demand
        XCTAssertFalse(condition.accepts(embedded))
        XCTAssertFalse(admissions.acceptsTiming(condition, exercise: embedded), "Adding metadata changes the frozen digest and does not create admission")
        var alteredPayload = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(exercise)) as? [String: Any])
        alteredPayload["prompt"] = exercise.prompt + " changed"
        let altered = try JSONDecoder().decode(NFExercise.self, from: JSONSerialization.data(withJSONObject: alteredPayload))
        XCTAssertFalse(admissions.acceptsTiming(condition, exercise: altered))
        var wrongScorer = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(entry)) as? [String: Any])
        wrongScorer["scorerVersion"] = 999
        let unsupported = try JSONDecoder().decode(NFEditorialAdmissionEntry.self, from: JSONSerialization.data(withJSONObject: wrongScorer))
        XCTAssertFalse(NFEditorialAdmissionContext(version: admissions.version, entries: [unsupported]).acceptsTiming(condition, exercise: exercise))
        var wrongLocale = wrongScorer; wrongLocale["scorerVersion"] = NFExerciseScoringEngine.scoringVersion; wrongLocale["contentLocale"] = "ja"
        let mismatched = try JSONDecoder().decode(NFEditorialAdmissionEntry.self, from: JSONSerialization.data(withJSONObject: wrongLocale))
        XCTAssertFalse(NFEditorialAdmissionContext(version: admissions.version, entries: [mismatched]).acceptsTiming(condition, exercise: exercise))
        XCTAssertTrue(NFSessionTimingCondition(.untimed).accepts(exercise))
        XCTAssertTrue(NFSessionTimingCondition(.elapsedOnly).accepts(exercise))
    }
}


@MainActor
extension EditorialLiveControllerPersistenceTests {
    func testFluencyReadinessUsesCapturedGregorianDayWithNonGregorianDisplayCalendar() throws {
        let root = try root(); defer { try? FileManager.default.removeItem(at: root) }
        let container = try container(root)
        let store = try store(root, context: container.mainContext, admissions: catalog(fluencyEligible: true))
        try collectFluencyPractice(store)
        let observations = store.attempts.compactMap { store.effectiveAttemptDTO($0).editorialObservation }
        let last = try XCTUnwrap(observations.map(\.occurredAt).max())
        let now = last.addingTimeInterval(1)
        var displayCalendar = Calendar(identifier: .buddhist)
        displayCalendar.timeZone = TimeZone(identifier: "America/Toronto")!
        let capturedDay = try XCTUnwrap(NFEditorialCapturedDay.capture(at: now,
            dayBoundaryHour: store.profileSnapshot.dayBoundaryHour, calendar: displayCalendar))
        XCTAssertEqual(capturedDay.calendarIdentifier, "gregorian")
        XCTAssertTrue(observations.allSatisfy { abs(capturedDay.ordinal - $0.canonicalDayOrdinal) <= 1 })
        let pure = NFEditorialPracticePolicy.reviewedFluencyReadiness(observations: observations,
            decisionDayOrdinal: capturedDay.ordinal)
        XCTAssertTrue(pure.timingEligible); XCTAssertEqual(pure.sampleCount, 8)
        let actual = store.reviewedFluencyReadiness(lab: .mentalMath, familyScope: fluencyFamily, band: .b1,
            at: now, calendar: displayCalendar)
        XCTAssertEqual(actual, pure)
        let futureRejected = store.reviewedFluencyReadiness(lab: .mentalMath,
            at: observations.map(\.occurredAt).min()!.addingTimeInterval(-1), calendar: displayCalendar)
        XCTAssertFalse(futureRejected.timingEligible); XCTAssertEqual(futureRejected.sampleCount, 0)
    }
}

@MainActor
extension EditorialLiveControllerPersistenceTests {
    private func initialRequest(_ admissions: NFEditorialAdmissionContext, band: NFEditorialBand? = nil,
                                count: Int = 4, legacy: Bool = false, quarantined: Set<String> = []) throws -> SessionRequest {
        var request = SessionRequest(lab: .mentalMath, source: .focused, seed: seed, localeIdentifier: "en",
            field: .general, targetDifficulty: 0.5, requestedItemCount: count,
            isTimed: false, timingCondition: .init(.untimed), quarantinedItemIDs: quarantined)
        var delivery = NFOrdinaryDeliveryPin(strategy: .adaptiveItem, profileID: profileID, bank: NFOfflineQuestionBank.rotationBank)
        request.ordinaryDelivery = delivery
        var pin = try XCTUnwrap(admissions.sessionPin(for: request, initialUserBand: band, startingScope: fluencyFamily))
        if legacy { pin.controllerVersion = NFEditorialLiveController.legacyVersion }
        delivery.editorialPolicy = pin; request.ordinaryDelivery = delivery
        return request
    }

    /// Explicit-clock native commit fixture. It exercises real selection,
    /// presentation, prepared checkpoints and AppStore's frozen-capture retry
    /// boundary; no legacy row or already-written observation is backfilled.
    private func collectInitialHistory(_ store: AppStore, admissions: NFEditorialAdmissionContext,
                                       band: NFEditorialBand, at date: Date, count: Int = 4) throws {
        let request = try initialRequest(admissions, band: band, count: count)
        let first = try store.prepareAdaptiveItem(request: request, predecessor: nil, at: date)
        var run = try store.acceptAdaptiveItem(first, checkpoint: first.checkpoint)
        let writer = UUID()
        XCTAssertTrue(store.localSessions.claimWriter(writer, sessionID: request.id, checkpoint: { true }))
        defer { store.localSessions.releaseWriter(writer) }
        let command = try store.localSessions.sessionCommand(
            authority: store.localSessions.writerAuthority(for: writer, sessionID: request.id), sessionID: request.id)
        for index in 0..<count {
            let timestamp = date.addingTimeInterval(Double(index * 20 + 2))
            try store.localSessions.acknowledgeSessionPresentation(sessionID: run.id,
                slotID: run.checkpoint.slotID, at: timestamp.addingTimeInterval(-1), command: command)
            let exercise = try XCTUnwrap(run.checkpoint.exercise)
            guard case let .numeric(schema) = exercise.interaction else { throw NFLocalSessionRepository.RepositoryError.corruptSnapshot }
            let response = NFExerciseResponse.numeric(.init(value: String(schema.answer.value), unit: schema.answer.canonicalUnit))
            let score = NFExerciseScoringEngine.score(response, for: exercise)
            XCTAssertTrue(score.isCorrect)
            run.checkpoint.response = response; run.checkpoint.confidence = nil
            run.checkpoint.result = score; run.checkpoint.phase = .confidence; run.checkpoint.pendingOutcome = "answer"
            run.checkpoint.shownAt = timestamp.addingTimeInterval(-1)
            run.checkpoint.itemActiveDuration = 0; run.checkpoint.answerDurationComplete = false
            run.checkpoint.inputModality = .unknown
            let before = run.revision; run.revision += 1; run.updatedAt = timestamp
            try store.localSessions.saveSession(run, command: command, expectedRevision: before)
            let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
            let record = AttemptRecord(sessionID: run.id, lab: exercise.lab, itemID: exercise.id,
                prompt: exercise.prompt, response: String(decoding: try encoder.encode(response), as: UTF8.self),
                correctAnswer: score.expectedAnswerSummary ?? "", isCorrect: score.isCorrect,
                confidence: .uncertain, evidenceClass: .practice, source: .focused)
            record.id = run.checkpoint.attemptID; record.confidenceRaw = nil
            record.submittedAt = timestamp; record.shownAt = run.checkpoint.shownAt
            record.scoringVersion = score.scoringVersion; record.deterministicCredit = score.credit
            record.activeDurationSeconds = 0; record.inputModeRaw = NFInputModality.unknown.rawValue
            let capture = try XCTUnwrap(store.captureEditorialCommit(record: record, exercise: exercise, result: score))
            XCTAssertEqual(capture.authorityAtCommit, "admitted")
            try store.withSessionCommand(command, sessionID: run.id) {
                try store.localSessions.retainSnapshot(attemptID: record.id, exercise: exercise, editorialCapture: capture)
                try store.saveExerciseAttempt(attemptID: record.id, sessionID: run.id, exercise: exercise,
                    response: response, result: score, confidence: nil, shownAt: record.shownAt,
                    activeDuration: 0, source: .focused, inputMode: NFInputModality.unknown.rawValue)
            }
            XCTAssertEqual(store.attempts.first { $0.id == record.id }?.submittedAt, timestamp)
            run.checkpoint.committedAttemptID = record.id; run.checkpoint.phase = .feedback
            run.checkpoint.correctness.append(true); run.checkpoint.credits.append(1)
            let preparedRevision = run.revision; run.revision += 1
            try store.localSessions.saveSession(run, command: command, expectedRevision: preparedRevision)
            if index + 1 < count {
                let next = try store.prepareAdaptiveItem(request: request, predecessor: run.checkpoint,
                    at: timestamp.addingTimeInterval(2), command: command)
                // A proposal owns only the new item. The native coordinator
                // carries the acknowledged run history before atomic acceptance.
                // An empty proposal must never erase the first recorded answer.
                if index == 0 {
                    let beforeRefusal = try NFEditorialCanonicalData.encode(store.localSessions.archive)
                    XCTAssertThrowsError(try store.acceptAdaptiveItem(next, checkpoint: next.checkpoint))
                    XCTAssertEqual(try NFEditorialCanonicalData.encode(store.localSessions.archive), beforeRefusal)
                }
                var checkpoint = next.checkpoint
                checkpoint.scratchpad = run.checkpoint.scratchpad
                checkpoint.correctness = run.checkpoint.correctness
                checkpoint.credits = run.checkpoint.credits
                checkpoint.assessmentDescriptorIDs = run.checkpoint.assessmentDescriptorIDs
                checkpoint.assessmentEvents = run.checkpoint.assessmentEvents
                checkpoint.cumulativeActiveDuration = run.checkpoint.cumulativeActiveDuration
                checkpoint.assessmentPracticeDuration = run.checkpoint.assessmentPracticeDuration
                checkpoint.sittingOrdinal = run.checkpoint.sittingOrdinal
                checkpoint.sittingActiveDuration = run.checkpoint.sittingActiveDuration
                checkpoint.timingConditionOverride = run.checkpoint.timingConditionOverride
                run = try store.acceptAdaptiveItem(next, checkpoint: checkpoint)
                XCTAssertEqual(run.checkpoint.correctness.count, index + 1)
                XCTAssertEqual(run.checkpoint.credits.count, index + 1)
            }
        }
        let prior = run.revision; run.revision += 1
        run.status = .completed; run.checkpoint.phase = .summary
        try store.localSessions.saveSession(run, command: command, expectedRevision: prior)
        store.reload()
    }

    private func demonstratedHistory(_ store: AppStore, admissions: NFEditorialAdmissionContext) throws {
        let date = Date().addingTimeInterval(-3 * 86_400)
        try collectInitialHistory(store, admissions: admissions, band: .b2, at: date)
        try collectInitialHistory(store, admissions: admissions, band: .b2, at: date.addingTimeInterval(86_400))
        try collectInitialHistory(store, admissions: admissions, band: .b1, at: date.addingTimeInterval(2 * 86_400), count: 1)
        let observations = store.attempts.compactMap { store.effectiveAttemptDTO($0).editorialObservation }
        XCTAssertEqual(observations.count, 9)
        let day = try XCTUnwrap(NFEditorialCapturedDay.capture(at: Date(), dayBoundaryHour: 4, calendar: .current))
        let demonstrated = EditorialBandEvidenceV1.reduce(observations, decisionDayOrdinal: day.ordinal).summaries
            .first { $0.group.band == .b2 }
        XCTAssertEqual(demonstrated?.coverage, .recentlySupported)
        XCTAssertEqual(demonstrated?.qualifyingObservationIDs.count, 8)
    }

    func testActualDemonstratedInitialTargetPersistsAcrossLowerSuccessNextAndColdResume() throws {
        let root = try root(); defer { try? FileManager.default.removeItem(at: root) }
        let container = try container(root, persistent: true), admissions = try catalog()
        let store = try store(root, context: container.mainContext, admissions: admissions)
        try demonstratedHistory(store, admissions: admissions)
        XCTAssertTrue(store.beginSession(lab: .mentalMath, source: .focused, field: .general,
            targetDifficulty: 0.5, requestedItemCount: 2, seedOverride: seed, isTimed: false,
            timingCondition: .init(.untimed), launchLocaleIdentifier: "en", editorialStartingFamilyScope: fluencyFamily), store.lastErrorMessage ?? "")
        let runtime = NFUniversalSessionRuntime(request: try XCTUnwrap(store.activeSessionRequest))
        XCTAssertTrue(runtime.checkpointDraft(store: store)); runtime.resume(); runtime.acknowledgePresented()
        let first = try XCTUnwrap(store.localSessions.editorialChallengePresentation(sessionID: runtime.sessionID))
        XCTAssertEqual(first.deliveredBand, .b2)
        let initialReceipt = try XCTUnwrap(store.localSessions.archive.adaptiveItemReceipts?.values.first { $0.sessionID == runtime.sessionID })
        let basis = try XCTUnwrap(initialReceipt.editorialDecision?.initialTargetDecision)
        XCTAssertEqual(basis.band, .b2); XCTAssertEqual(basis.basis, .demonstratedPractice)
        XCTAssertEqual(basis.reason, .recentPracticeTarget); XCTAssertEqual(basis.supportingObservationIDs.count, 8)
        try answer(runtime, store: store); runtime.next(store: store)
        let saved = try XCTUnwrap(store.localSessions.archive.sessions.first { $0.id == runtime.sessionID })
        let next = try XCTUnwrap(saved.checkpoint.ordinaryReservationDecisionID.flatMap { store.localSessions.archive.adaptiveItemReceipts?[$0] })
        XCTAssertEqual(next.editorialDecision?.initialTargetDecision, basis)
        runtime.releaseWriter(); store.activeSessionRequest = nil
        let reopened = try self.store(root, context: container.mainContext, admissions: admissions)
        XCTAssertTrue(reopened.resumeSession(saved.id))
        let cold = NFUniversalSessionRuntime(request: try XCTUnwrap(reopened.activeSessionRequest)); defer { cold.releaseWriter() }
        XCTAssertEqual(cold.exercise, saved.checkpoint.exercise)
        XCTAssertTrue(cold.checkpointDraft(store: reopened)); cold.resume(); cold.acknowledgePresented()
        XCTAssertEqual(reopened.localSessions.archive.adaptiveItemReceipts?[next.decisionID]?.editorialDecision?.initialTargetDecision, basis)
    }

    func testDemonstratedInitialTargetAcceptanceRejectsChangedEvidenceWithoutCursorPublication() throws {
        let root = try root(); defer { try? FileManager.default.removeItem(at: root) }
        let container = try container(root), admissions = try catalog()
        let store = try store(root, context: container.mainContext, admissions: admissions)
        try demonstratedHistory(store, admissions: admissions)
        let proposal = try store.prepareAdaptiveItem(request: initialRequest(admissions), predecessor: nil)
        XCTAssertEqual(proposal.receipt.editorialDecision?.initialTargetDecision?.basis, .demonstratedPractice)
        let before = try Data(contentsOf: root.appending(path: "sessions-v1.json"))
        let record = try XCTUnwrap(store.attempts.first { store.effectiveAttemptDTO($0).editorialObservation?.item?.editorialBand == .b2 })
        let response = record.response; record.response += " changed"; try store.context.save(); store.reload()
        XCTAssertThrowsError(try store.acceptAdaptiveItem(proposal, checkpoint: proposal.checkpoint))
        XCTAssertEqual(try Data(contentsOf: root.appending(path: "sessions-v1.json")), before)
        record.response = response; try store.context.save(); store.reload()
        let accepted = try store.acceptAdaptiveItem(proposal, checkpoint: proposal.checkpoint)
        let decision = try XCTUnwrap(accepted.checkpoint.ordinaryReservationDecisionID.flatMap { store.localSessions.archive.adaptiveItemReceipts?[$0]?.editorialDecision })
        XCTAssertEqual(decision.initialTargetDecision?.basis, .demonstratedPractice)
    }

    func testLegacyInitialControllerKeepsFrozenRecentTargetAndFutureVersionCannotLaunch() throws {
        let root = try root(); defer { try? FileManager.default.removeItem(at: root) }
        let container = try container(root), admissions = try catalog()
        let store = try store(root, context: container.mainContext, admissions: admissions)
        try demonstratedHistory(store, admissions: admissions)
        let request = try initialRequest(admissions, count: 2, legacy: true)
        let proposed = try store.prepareAdaptiveItem(request: request, predecessor: nil)
        let accepted = try store.acceptAdaptiveItem(proposed, checkpoint: proposed.checkpoint)
        let decision = try XCTUnwrap(accepted.checkpoint.ordinaryReservationDecisionID.flatMap { store.localSessions.archive.adaptiveItemReceipts?[$0]?.editorialDecision })
        XCTAssertEqual(decision.controllerVersion, NFEditorialLiveController.legacyVersion)
        XCTAssertNil(decision.initialTargetDecision); XCTAssertEqual(decision.selection.deliveredBand, .b1)
        let reopened = try self.store(root, context: container.mainContext, admissions: admissions)
        XCTAssertNil(reopened.localSessions.loadError)
        XCTAssertEqual(reopened.localSessions.archive.adaptiveItemReceipts?[proposed.receipt.decisionID]?.editorialDecision, decision)
        var future = try initialRequest(admissions)
        future.ordinaryDelivery?.editorialPolicy?.controllerVersion = "EditorialLiveControllerV999"
        let bytes = try Data(contentsOf: root.appending(path: "sessions-v1.json"))
        XCTAssertThrowsError(try reopened.prepareAdaptiveItem(request: future, predecessor: nil))
        XCTAssertEqual(try Data(contentsOf: root.appending(path: "sessions-v1.json")), bytes)
    }
}

@MainActor
extension EditorialLiveControllerPersistenceTests {
    func testDemonstratedTargetShortageRefusesLaunchWithoutReplacingPriorBandOrConsumingInventory() throws {
        let root = try root(); defer { try? FileManager.default.removeItem(at: root) }
        let container = try container(root), admissions = try catalog()
        let store = try store(root, context: container.mainContext, admissions: admissions)
        try demonstratedHistory(store, admissions: admissions)
        let priorItems = Set(store.attempts.map(\.itemID))
        let unusedB2 = try Set(admissions.entries.filter { $0.demand.editorialBand == .b2 }.compactMap { entry -> String? in
            let ordinal = try XCTUnwrap(NFOfflineQuestionBank.ordinal(forQuestionID: entry.bankQuestionID, lab: .mentalMath))
            let exercise = NFDeterministicSessionExerciseFactory.makeExercise(
                request: template().launchOnly(offlineQuestionOrdinals: [ordinal]), index: 0, assessmentDescriptor: nil)
            return priorItems.contains(exercise.id) ? nil : exercise.id
        })
        XCTAssertEqual(unusedB2.count, 4)
        let before = try Data(contentsOf: root.appending(path: "sessions-v1.json"))
        XCTAssertFalse(store.beginSession(lab: .mentalMath, source: .focused, field: .general,
            targetDifficulty: 0.5, requestedItemCount: 2, seedOverride: seed, isTimed: false,
            timingCondition: .init(.untimed), launchLocaleIdentifier: "en", additionalQuarantinedItemIDs: unusedB2,
            editorialStartingFamilyScope: fluencyFamily))
        XCTAssertNil(store.activeSessionRequest); XCTAssertNotNil(store.lastErrorMessage)
        XCTAssertEqual(try Data(contentsOf: root.appending(path: "sessions-v1.json")), before)
        let fresh = try store.prepareAdaptiveItem(request: initialRequest(admissions), predecessor: nil)
        XCTAssertEqual(fresh.receipt.editorialDecision?.initialTargetDecision?.band, .b2)
        XCTAssertEqual(fresh.receipt.editorialDecision?.initialTargetDecision?.basis, .demonstratedPractice)
    }

    func testActualHistoricalDemonstrationRefreshPinsSameBandAndOriginalEvidenceAfterLongGap() throws {
        let root = try root(); defer { try? FileManager.default.removeItem(at: root) }
        let container = try container(root), admissions = try catalog()
        let store = try store(root, context: container.mainContext, admissions: admissions)
        try demonstratedHistory(store, admissions: admissions)
        let originals = try NFEditorialCanonicalData.encode(store.attempts.map { NFImmutableAttemptRecordSnapshot($0) })
        let proposal = try store.prepareAdaptiveItem(request: initialRequest(admissions), predecessor: nil,
            at: Date().addingTimeInterval(90 * 86_400))
        let target = try XCTUnwrap(proposal.receipt.editorialDecision?.initialTargetDecision)
        XCTAssertEqual(target.band, .b2); XCTAssertEqual(target.reason, .refreshProbe)
        XCTAssertEqual(target.basis, .demonstratedPractice); XCTAssertEqual(target.supportingObservationIDs.count, 8)
        XCTAssertEqual(try NFEditorialCanonicalData.encode(store.attempts.map { NFImmutableAttemptRecordSnapshot($0) }), originals)
        XCTAssertTrue(proposal.receipt.editorialDecision?.evidence.summaries.contains { $0.group.band == .b2 && $0.coverage == .needsRefresh } == true)
        let accepted = try store.acceptAdaptiveItem(proposal, checkpoint: proposal.checkpoint)
        let cold = try self.store(root, context: container.mainContext, admissions: admissions)
        XCTAssertNil(cold.localSessions.loadError)
        XCTAssertEqual(cold.localSessions.archive.sessions.first { $0.id == accepted.id }?.checkpoint.exercise, proposal.checkpoint.exercise)
        XCTAssertEqual(cold.localSessions.archive.adaptiveItemReceipts?[proposal.receipt.decisionID]?.editorialDecision?.initialTargetDecision, target)
    }
}

@MainActor
extension EditorialLiveControllerPersistenceTests {
    func testV2ContractProofIgnoresDeliveryQuarantineButNeverDowngradesIntoAvailableLowerBand() throws {
        let root = try root(); defer { try? FileManager.default.removeItem(at: root) }
        let container = try container(root, persistent: true), admissions = try catalog()
        let store = try store(root, context: container.mainContext, admissions: admissions)
        try demonstratedHistory(store, admissions: admissions)
        let historical = try NFEditorialCanonicalData.encode(store.attempts.map { NFImmutableAttemptRecordSnapshot($0) })
        let priorIDs = Set(store.attempts.map(\.itemID))
        let remainingB2 = try Set(admissions.entries.filter { $0.demand.editorialBand == .b2 }.compactMap { entry -> String? in
            let ordinal = try XCTUnwrap(NFOfflineQuestionBank.ordinal(forQuestionID: entry.bankQuestionID, lab: .mentalMath))
            let exercise = NFDeterministicSessionExerciseFactory.makeExercise(request: template().launchOnly(offlineQuestionOrdinals: [ordinal]), index: 0, assessmentDescriptor: nil)
            return priorIDs.contains(exercise.id) ? nil : exercise.id
        })
        XCTAssertEqual(remainingB2.count, 4); XCTAssertTrue(remainingB2.isDisjoint(with: priorIDs))
        let baseline = try store.prepareAdaptiveItem(request: initialRequest(admissions, count: 2), predecessor: nil)
        let originalTarget = try XCTUnwrap(baseline.receipt.editorialDecision?.initialTargetDecision)
        let oneUnavailable = Set([try XCTUnwrap(remainingB2.sorted().first)])
        let request = try initialRequest(admissions, count: 2, quarantined: oneUnavailable)
        let partial = try store.prepareAdaptiveItem(request: request, predecessor: nil)
        let target = try XCTUnwrap(partial.receipt.editorialDecision?.initialTargetDecision)
        XCTAssertEqual(target, originalTarget, "Catalog contract proof is independent of delivery quarantine")
        XCTAssertEqual(target.band, .b2); XCTAssertEqual(target.basis, .demonstratedPractice)
        XCTAssertFalse(oneUnavailable.contains(try XCTUnwrap(partial.checkpoint.exercise).id))
        let accepted = try store.acceptAdaptiveItem(partial, checkpoint: partial.checkpoint)
        let cold = try self.store(root, context: container.mainContext, admissions: admissions)
        XCTAssertNil(cold.localSessions.loadError)
        XCTAssertEqual(cold.localSessions.archive.adaptiveItemReceipts?[partial.receipt.decisionID]?.editorialDecision?.initialTargetDecision, target)
        let before = try Data(contentsOf: root.appending(path: "sessions-v1.json"))
        XCTAssertFalse(cold.beginSession(lab: .mentalMath, source: .focused, field: .general,
            targetDifficulty: 0.5, requestedItemCount: 2, seedOverride: seed, isTimed: false,
            timingCondition: .init(.untimed), launchLocaleIdentifier: "en", additionalQuarantinedItemIDs: remainingB2,
            editorialStartingFamilyScope: fluencyFamily))
        XCTAssertNil(cold.activeSessionRequest); XCTAssertNotNil(cold.lastErrorMessage)
        XCTAssertEqual(try Data(contentsOf: root.appending(path: "sessions-v1.json")), before)
        XCTAssertEqual(cold.localSessions.archive.sessions.first { $0.id == accepted.id }?.checkpoint, accepted.checkpoint)
        XCTAssertEqual(try NFEditorialCanonicalData.encode(cold.attempts.map { NFImmutableAttemptRecordSnapshot($0) }), historical)
        // A separate explicit lower-band activity remains possible; shortage
        // must never silently make that preference for the person.
        let lower = try cold.prepareAdaptiveItem(request: initialRequest(admissions, band: .b1, count: 2), predecessor: nil)
        XCTAssertEqual(lower.receipt.editorialDecision?.selection.deliveredBand, .b1)
    }
}

@MainActor
extension EditorialLiveControllerPersistenceTests {
    private func mixedCatalogWithoutFirstFamilyB1(baseCount: Int = 3, higherCount: Int = 3) throws -> NFEditorialAdmissionContext {
        let source = try mixedCatalog(baseCounts: [0, baseCount], higherCount: higherCount)
        XCTAssertFalse(source.entries.contains { $0.demand.familyID == "QA.mixed.family.0" && $0.demand.editorialBand == .b1 })
        return source
    }
    private func mixedPreviewRequest(_ store: AppStore, count: Int = 10) -> SessionRequest {
        // Explicit exact settings match the actual stored/native catalog; preview
        // may not derive authority from locale defaults or a synthesized attempt.
        var request = SessionRequest(lab: .mentalMath, source: .focused, seed: seed, localeIdentifier: "en",
            field: .general, targetDifficulty: 0.5, requestedItemCount: count,
            isTimed: false, timingCondition: .init(.untimed))
        request.ordinaryDelivery = .init(strategy: .adaptiveItem, profileID: store.profileSnapshot.id, bank: NFOfflineQuestionBank.rotationBank)
        return request
    }

    func testNewAutomaticScopePinIncludesHigherOnlyFamiliesWithoutChangingExplicitOrSavedPins() throws {
        let admissions = try mixedCatalogWithoutFirstFamilyB1()
        var request = template()
        request.ordinaryDelivery = .init(strategy: .adaptiveItem, profileID: profileID, bank: NFOfflineQuestionBank.rotationBank)
        let family0 = NFEditorialFamilyScope(objectiveID: "QA.mixed.objective.0", familyID: "QA.mixed.family.0")
        let family1 = NFEditorialFamilyScope(objectiveID: "QA.mixed.objective.1", familyID: "QA.mixed.family.1")
        let automatic = try XCTUnwrap(admissions.sessionPin(for: request))
        XCTAssertTrue(automatic.isMixed); XCTAssertEqual(automatic.scopes, [family0, family1])
        XCTAssertNil(automatic.initialUserBand)
        let explicit = try XCTUnwrap(admissions.sessionPin(for: request, initialUserBand: .b2, startingScope: family0))
        XCTAssertFalse(explicit.isMixed); XCTAssertEqual(explicit.scopes, [family0]); XCTAssertEqual(explicit.initialUserBand, .b2)
        let retained = NFEditorialSessionPin(catalogVersion: admissions.version, objectiveID: family1.objectiveID,
            familyID: family1.familyID, controllerVersion: NFEditorialLiveController.legacyVersion, catalogDigest: admissions.fingerprint)
        let original = try NFEditorialCanonicalData.encode(retained)
        let decoded = try JSONDecoder().decode(NFEditorialSessionPin.self, from: original)
        XCTAssertEqual(decoded, retained); XCTAssertEqual(decoded.scopes, [family1])
        XCTAssertEqual(try NFEditorialCanonicalData.encode(decoded), original, "Scope expansion applies only at new launch construction, never saved pins")
    }

    func testMixedPreviewShowsRecentHigherOnlyTargetAndColdFamilyWithExactAcceptedAndColdTargets() async throws {
        let root = try root(); defer { try? FileManager.default.removeItem(at: root) }
        let admissions = try mixedCatalogWithoutFirstFamilyB1()
        var expectedRun: NFLocalSessionEnvelope!
        var expectedDecisions: [String: NFEditorialControllerDecision] = [:]
        do {
            let container = try container(root, persistent: true)
            let store = try store(root, context: container.mainContext, admissions: admissions)
            let family0 = NFEditorialFamilyScope(objectiveID: "QA.mixed.objective.0", familyID: "QA.mixed.family.0")
            XCTAssertTrue(store.beginSession(lab: .mentalMath, source: .focused, field: .general, targetDifficulty: 0.5,
                requestedItemCount: 1, seedOverride: seed, isTimed: false, timingCondition: .init(.untimed),
                launchLocaleIdentifier: "en", editorialStartingBand: .b2, editorialStartingFamilyScope: family0), store.lastErrorMessage ?? "")
            let historical = NFUniversalSessionRuntime(request: try XCTUnwrap(store.activeSessionRequest))
            XCTAssertTrue(historical.checkpointDraft(store: store)); historical.resume(); historical.acknowledgePresented()
            try answer(historical, store: store); historical.next(store: store); historical.releaseWriter()
            XCTAssertEqual(historical.stage, .summary)
            let committed = try XCTUnwrap(store.attempts.first)
            XCTAssertEqual(store.effectiveAttemptDTO(committed).editorialObservation?.item?.editorialBand, .b2)
            XCTAssertEqual(store.localSessions.editorialSnapshot(for: committed.id)?.editorialCapture?.profileID, profileID)
            store.activeSessionRequest = nil
            let archiveBefore = try Data(contentsOf: root.appending(path: "sessions-v1.json"))
            let coreBefore = try NFDataArchiveRawSnapshot.canonicalEncode(NFDataArchiveRawCapture.capture(context: container.mainContext))
            let preview = try await store.reviewedStartingPreview(request: mixedPreviewRequest(store), catalogScope: nil)
            let mixed = try XCTUnwrap(preview.mixedStartingPreview)
            XCTAssertEqual(mixed.targets.count, 2); XCTAssertEqual(mixed.availableFamilyCount, 2)
            XCTAssertTrue(mixed.canStartNext); XCTAssertEqual(preview.state, .feasible)
            let a = try XCTUnwrap(mixed.targets.first { $0.scope == family0 })
            let b = try XCTUnwrap(mixed.targets.first { $0.scope != family0 })
            XCTAssertEqual(a.band, .b2); XCTAssertEqual(a.automaticReason, .recentPracticeTarget)
            XCTAssertEqual(b.band, .b1); XCTAssertEqual(b.automaticReason, .coldStartDefault)
            XCTAssertTrue(mixed.targets.allSatisfy { !$0.canStartRequestedCount && $0.canStart(count: 1) })
            XCTAssertEqual(try Data(contentsOf: root.appending(path: "sessions-v1.json")), archiveBefore)
            XCTAssertEqual(try NFDataArchiveRawSnapshot.canonicalEncode(NFDataArchiveRawCapture.capture(context: container.mainContext)), coreBefore)
            let runtime = try launchMixed(store, count: 10)
            for _ in 0..<2 {
                let currentRun = try XCTUnwrap(store.localSessions.archive.sessions.first { $0.id == runtime.request.id })
                let accepted = try XCTUnwrap(currentRun.checkpoint.ordinaryReservationDecisionID.flatMap { store.localSessions.archive.adaptiveItemReceipts?[$0] })
                let decision = try XCTUnwrap(accepted.editorialDecision)
                let scope = try XCTUnwrap(accepted.mixedDecision?.selectedScope)
                let displayed = try XCTUnwrap(mixed.targets.first { $0.scope == scope })
                XCTAssertEqual(decision.controlAfter.initialTargetBand, displayed.band)
                XCTAssertEqual(decision.initialReason, displayed.automaticReason)
                XCTAssertEqual(decision.selection.deliveredBand, displayed.band)
                expectedDecisions[scope.key] = decision
                try answer(runtime, store: store); runtime.next(store: store); XCTAssertNil(runtime.saveError)
            }
            XCTAssertEqual(expectedDecisions.count, 2, "Coverage may change order, not another family's initial target")
            runtime.pause(); XCTAssertTrue(runtime.checkpointDraft(store: store)); runtime.releaseWriter()
            expectedRun = try XCTUnwrap(store.localSessions.archive.sessions.first { $0.id == runtime.request.id })
        }
        let container = try container(root, persistent: true)
        let reopened = try store(root, context: container.mainContext, admissions: admissions)
        XCTAssertNil(reopened.localSessions.loadError)
        let saved = try XCTUnwrap(reopened.localSessions.archive.sessions.first { $0.id == expectedRun.id })
        XCTAssertEqual(saved.checkpoint, expectedRun.checkpoint)
        XCTAssertEqual(saved.request.ordinaryDelivery, expectedRun.request.ordinaryDelivery)
        for decision in expectedDecisions.values {
            XCTAssertTrue(reopened.localSessions.archive.adaptiveItemReceipts?.values.contains { $0.editorialDecision == decision } == true)
        }
        XCTAssertEqual(reopened.attempts.count, 3, "Preview and reopen must not create new observations")
    }

    func testMixedColdUnavailableFamilyKeepsB1AndSingleNextSupplyIsNotFullCountPromise() async throws {
        let root = try root(); defer { try? FileManager.default.removeItem(at: root) }
        let container = try container(root), admissions = try mixedCatalogWithoutFirstFamilyB1(baseCount: 1, higherCount: 2)
        let store = try store(root, context: container.mainContext, admissions: admissions)
        let archiveURL = root.appending(path: "sessions-v1.json")
        let before = FileManager.default.fileExists(atPath: archiveURL.path) ? try Data(contentsOf: archiveURL) : nil
        let preview = try await store.reviewedStartingPreview(request: mixedPreviewRequest(store), catalogScope: nil)
        let mixed = try XCTUnwrap(preview.mixedStartingPreview)
        XCTAssertEqual(mixed.targets.count, 2); XCTAssertEqual(mixed.availableFamilyCount, 1)
        XCTAssertEqual(preview.state, .feasible); XCTAssertTrue(preview.canStartAutomaticMixed)
        let unavailable = try XCTUnwrap(mixed.targets.first { !$0.canStart(count: 1) })
        XCTAssertEqual(unavailable.band, .b1); XCTAssertEqual(unavailable.automaticReason, .coldStartDefault)
        XCTAssertEqual(unavailable.unavailabilityReasons, [.bandNotReviewed])
        XCTAssertFalse(unavailable.isReviewedInCurrentScope)
        XCTAssertTrue(mixed.targets.allSatisfy { !$0.canStartRequestedCount })
        let after = FileManager.default.fileExists(atPath: archiveURL.path) ? try Data(contentsOf: archiveURL) : nil
        XCTAssertEqual(after, before)
        let runtime = try launchMixed(store, count: 10); defer { runtime.releaseWriter() }
        let accepted = try receipt(store)
        XCTAssertNotEqual(accepted.mixedDecision?.selectedScope, unavailable.scope)
        XCTAssertEqual(accepted.editorialDecision?.selection.deliveredBand, .b1)
        let original = runtime.exercise
        try answer(runtime, store: store); runtime.next(store: store)
        XCTAssertEqual(runtime.exercise, original); XCTAssertEqual(runtime.stage, .feedback)
        XCTAssertNotNil(runtime.nextUnavailableReason); XCTAssertNil(runtime.saveError)
        XCTAssertEqual(runtime.request.requestedItemCount, 10)
        XCTAssertEqual(store.localSessions.archive.selectionLedger?.slots.count, 1)
        XCTAssertEqual(store.attempts.count, 1)
        let exhausted = try await store.reviewedStartingPreview(request: mixedPreviewRequest(store), catalogScope: nil)
        XCTAssertEqual(exhausted.state, .temporarilyUnavailable)
        XCTAssertFalse(exhausted.canStartAutomaticMixed)
        XCTAssertEqual(exhausted.mixedStartingPreview?.targets.map(\.band), [.b1, .b1])
        XCTAssertFalse(exhausted.mixedStartingPreview?.canStartNext == true)
    }
}

/// Runs in both the macOS suite and the existing iOS native-input target.
/// The observer records execution only: every decode and write uses the real
/// repository worker and real private file, without replacing the transaction.
private final class NFTypedArchiveWorkerObservation: @unchecked Sendable {
    private let lock = NSLock()
    private var startupValues: [(String, Bool)] = []
    private var writeValues: [(String, Bool)] = []

    func startup(_ stage: NFLocalSessionRepository.StartupWorkStage) {
        lock.withLock { startupValues.append((String(describing: stage), Thread.isMainThread)) }
    }
    func write(_ stage: NFLocalArchiveWriteStage, isMainThread: Bool) {
        lock.withLock { writeValues.append((String(describing: stage), isMainThread)) }
    }
    var startupEvents: [(String, Bool)] { lock.withLock { startupValues } }
    var writeEvents: [(String, Bool)] { lock.withLock { writeValues } }
}

@MainActor
final class TypedGeometryArchiveWorkerTests: XCTestCase {
    private enum Kind: String, CaseIterable {
        case source, coordinate, cube, section, net, coordinateReasoning, reflectionReasoning, asymmetricAssembly, feasibleAssembly
        var activityID: String? {
            switch self {
            case .source: nil
            case .coordinate: "nf.default.spatial.coordinate-rotation"
            case .cube: "nf.default.spatial.object-rotation"
            case .section: "nf.default.spatial.cross-section"
            case .net: "nf.default.spatial.cube-net"
            case .coordinateReasoning: "nf.default.spatial.coordinate-rotation"
            case .reflectionReasoning: "nf.default.spatial.vector-reflection"
            case .asymmetricAssembly: "nf.default.spatial.object-rotation"
            case .feasibleAssembly: "nf.default.spatial.top-view"
            }
        }
        var schemaVersion: Int {
            switch self { case .source: 1; case .coordinate: 9; case .cube: 8; case .section: 10; case .net: 11; case .coordinateReasoning, .reflectionReasoning: 12; case .asymmetricAssembly, .feasibleAssembly: 13 }
        }
    }
    private struct SavedItem {
        let kind: Kind
        let sessionID: UUID
        let checkpoint: NFLocalItemCheckpoint
    }
    private let sourceText = "The synthetic silver observatory records six measurements at the same local hour."

    func testSourceExactDraftColdStartupAndAutosaveUseRealBackgroundWorkers() async throws {
        try await verifyWorkers(for: [.source])
    }
    func testCoordinateDraftColdStartupAndAutosaveUseRealBackgroundWorkers() async throws {
        try await verifyWorkers(for: [.coordinate])
    }
    func testLabeledCubeDraftColdStartupAndAutosaveUseRealBackgroundWorkers() async throws {
        try await verifyWorkers(for: [.cube])
    }
    func testSolidSectionDraftColdStartupAndAutosaveUseRealBackgroundWorkers() async throws {
        try await verifyWorkers(for: [.section])
    }
    func testCubeNetDraftColdStartupAndAutosaveUseRealBackgroundWorkers() async throws {
        try await verifyWorkers(for: [.net])
    }
    func testAdvancedCoordinateDraftsColdStartupAndAutosaveUseRealBackgroundWorkers() async throws {
        try await verifyWorkers(for: [.coordinateReasoning, .reflectionReasoning])
    }
    func testSpatialAssemblyDraftsColdStartupAndAutosaveUseRealBackgroundWorkers() async throws {
        try await verifyWorkers(for: [.asymmetricAssembly, .feasibleAssembly])
    }
    func testMixedTypedArchiveColdStartupAndAutosaveKeepEveryExactDraft() async throws {
        try await verifyWorkers(for: Kind.allCases)
    }

    @inline(never)
    private func verifyWorkers(for kinds: [Kind]) async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "NF-Typed-Archive-Worker-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let container = try ModelContainer(for: Schema(NFSchemaV1.models),
            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        defer { withExtendedLifetime(container) {} }
        var draft = OnboardingDraft(); draft.aiMode = .disabled
        container.mainContext.insert(UserProfileRecord(draft: draft))
        try container.mainContext.save()
        let url = root.appending(path: "sessions.json"), owner = UUID()
        let store = makeStore(root: root, context: container.mainContext,
            repository: NFLocalSessionRepository(url: url, ownerDeviceID: owner))
        XCTAssertFalse(store.allowsSharedWidgetPublishing)
        let writes = NFTypedArchiveWorkerObservation()
        store.localSessions.archiveWriteObserver = { stage, isMain in writes.write(stage, isMainThread: isMain) }
        var originals: [SavedItem] = []
        for kind in kinds { originals.append(try await saveFirstDraft(kind, store: store)) }
        assertWrites(writes, count: kinds.count)
        XCTAssertTrue(store.attempts.isEmpty)
        XCTAssertEqual(store.localSessions.archive.sessions.count, kinds.count)

        let originalBytes = try Data(contentsOf: url)
        let startup = NFTypedArchiveWorkerObservation()
        let prepared = try await NFLocalSessionRepository.prepareStartup(at: url, ownerDeviceID: owner,
            observe: { startup.startup($0) })
        defer { prepared.discard() }
        XCTAssertNil(prepared.loadError)
        XCTAssertEqual(prepared.sourceDigest, NFReservationSnapshot.digest(originalBytes))
        XCTAssertEqual(startup.startupEvents.map(\.0), ["acquiredInput", "decoding", "validated"])
        XCTAssertTrue(startup.startupEvents.allSatisfy { !$0.1 }, "Full typed validation must execute off MainActor on the native worker stack")
        let adopted = try NFLocalSessionRepository.adoptPreparedStartup(prepared, at: url, ownerDeviceID: owner)
        XCTAssertNil(adopted.loadError)
        XCTAssertEqual(try Data(contentsOf: url), originalBytes, "Read/adopt must not rewrite an authentic saved draft")
        for original in originals {
            let retained = try XCTUnwrap(adopted.archive.sessions.first { $0.id == original.sessionID })
            XCTAssertEqual(retained.checkpoint, original.checkpoint)
        }

        let coldStore = makeStore(root: root, context: container.mainContext, repository: adopted)
        XCTAssertFalse(coldStore.allowsSharedWidgetPublishing)
        let coldWrites = NFTypedArchiveWorkerObservation()
        adopted.archiveWriteObserver = { stage, isMain in coldWrites.write(stage, isMainThread: isMain) }
        var revised: [SavedItem] = []
        for original in originals { revised.append(try await saveColdDraft(original, store: coldStore)) }
        assertWrites(coldWrites, count: kinds.count)
        XCTAssertTrue(coldStore.attempts.isEmpty, "Autosaving editable work cannot mint an answer, credit, or XP event")

        // A second actual worker decode checks the actor's renamed bytes, not
        // merely its already-published in-memory archive projection.
        let revisedBytes = try Data(contentsOf: url)
        let finalStartup = NFTypedArchiveWorkerObservation()
        let finalPrepared = try await NFLocalSessionRepository.prepareStartup(at: url, ownerDeviceID: owner,
            observe: { finalStartup.startup($0) })
        defer { finalPrepared.discard() }
        XCTAssertNil(finalPrepared.loadError)
        let finalRepository = try NFLocalSessionRepository.adoptPreparedStartup(finalPrepared, at: url, ownerDeviceID: owner)
        XCTAssertEqual(try Data(contentsOf: url), revisedBytes)
        XCTAssertEqual(finalRepository.archive.sessions.count, kinds.count)
        XCTAssertEqual(finalStartup.startupEvents.map(\.0), ["acquiredInput", "decoding", "validated"])
        XCTAssertTrue(finalStartup.startupEvents.allSatisfy { !$0.1 })
        for expected in revised {
            let saved = try XCTUnwrap(finalRepository.archive.sessions.first { $0.id == expected.sessionID })
            XCTAssertEqual(saved.checkpoint, expected.checkpoint)
            XCTAssertTrue(saved.checkpoint.correctness.isEmpty)
            XCTAssertTrue(saved.checkpoint.credits.isEmpty)
            XCTAssertNil(saved.checkpoint.result)
            XCTAssertNil(saved.checkpoint.committedAttemptID)
        }
    }

    @inline(never)
    private func makeStore(root: URL, context: ModelContext, repository: NFLocalSessionRepository) -> AppStore {
        AppStore(context: context,
            nextDayEnhancementCache: NFNextDayEnhancementCache(rootURL: root.appending(path: "cache")),
            documentStorageRootURL: root.appending(path: "documents"),
            localSessionRepository: repository,
            adaptivePlanHistoryRepository: NFAdaptivePlanHistoryRepository(fileURL: root.appending(path: "history.json")),
            offlineQuestionRotation: NFOfflineQuestionRotation(store: NFMemoryOfflineQuestionRotationStateStore()),
            temporaryArtifactsRootURL: root.appending(path: "temporary"), allowsSharedWidgetPublishing: false)
    }

    @inline(never)
    private func saveFirstDraft(_ kind: Kind, store: AppStore) async throws -> SavedItem {
        let request: SessionRequest
        if let id = kind.activityID {
            let activity = try XCTUnwrap(NFDefaultContentCatalog.activity(id: id))
            XCTAssertTrue(store.beginDefaultCatalogSession(.init(activity: activity, field: .general),
                requestedItemCount: 2, timingCondition: .init(.untimed),
                coordinateReasoningPolicyVersion: [.coordinateReasoning, .reflectionReasoning].contains(kind) ? 1 : nil,
                spatialAssemblyPolicyVersion: [.asymmetricAssembly, .feasibleAssembly].contains(kind) ? 1 : nil), store.lastErrorMessage ?? "Expected actual catalog launch")
            request = try XCTUnwrap(store.activeSessionRequest)
        } else {
            let chunk = NFSourceChunk(id: "synthetic.archive.source", documentID: UUID(), documentVersion: 1,
                sourceName: "Synthetic observatory.txt", locator: .init(page: nil, lineStart: 1, lineEnd: 1, section: nil),
                text: sourceText, contentHash: NFReservationSnapshot.digest(Data(sourceText.utf8)), ordinal: 0, language: "en")
            request = try NFSourceReviewExactAdapter.makeRequest(chunk: chunk, localeIdentifier: "en_US")
        }
        let runtime = NFUniversalSessionRuntime(request: request)
        defer { runtime.releaseWriter(); store.activeSessionRequest = nil }
        XCTAssertTrue(runtime.checkpointDraft(store: store), runtime.saveError ?? "Expected first durable checkpoint")
        runtime.resume(); runtime.acknowledgePresented()
        XCTAssertNil(runtime.unavailableReason)
        assertContract(runtime.exercise, kind: kind)
        let entered = try enterDraft(runtime, kind: kind, revision: 1)
        let initial = try XCTUnwrap(store.localSessions.archive.sessions.first { $0.id == runtime.sessionID })
        XCTAssertNotEqual(initial.checkpoint.response, entered, "The actor must publish an actual response edit")
        let saved = await runtime.checkpointDraftAsync(store: store)
        XCTAssertTrue(saved, runtime.saveError ?? "Expected real asynchronous autosave")
        let envelope = try XCTUnwrap(store.localSessions.archive.sessions.first { $0.id == runtime.sessionID })
        XCTAssertEqual(envelope.checkpoint.response, entered)
        XCTAssertEqual(envelope.checkpoint.scratchpad, note(kind, revision: 1))
        XCTAssertEqual(envelope.checkpoint.exercise, runtime.exercise)
        XCTAssertEqual(envelope.checkpoint.exerciseDigest, try NFLocalItemCheckpoint.digest(runtime.exercise))
        XCTAssertEqual(envelope.checkpoint.slotID, initial.checkpoint.slotID)
        XCTAssertEqual(envelope.checkpoint.attemptID, initial.checkpoint.attemptID)
        XCTAssertGreaterThan(envelope.revision, initial.revision)
        return SavedItem(kind: kind, sessionID: runtime.sessionID, checkpoint: envelope.checkpoint)
    }

    @inline(never)
    private func saveColdDraft(_ original: SavedItem, store: AppStore) async throws -> SavedItem {
        let envelope = try XCTUnwrap(store.localSessions.archive.sessions.first { $0.id == original.sessionID })
        var request = original.kind == .source
            ? try NFSourceReviewExactAdapter.resumeRequest(envelope, ownerDeviceID: store.localSessions.ownerDeviceID)
            : envelope.request
        request.localSessionID = envelope.id; request.localCheckpoint = envelope.checkpoint
        let runtime = NFUniversalSessionRuntime(request: request)
        defer { runtime.releaseWriter() }
        XCTAssertEqual(runtime.exercise, original.checkpoint.exercise)
        XCTAssertEqual(runtime.scratchpad, original.checkpoint.scratchpad)
        XCTAssertTrue(runtime.isPaused, "Cold work resumes only after an explicit continuation")
        XCTAssertTrue(runtime.checkpointDraft(store: store), runtime.saveError ?? "Expected cold writer attachment")
        runtime.resume(); runtime.acknowledgePresented()
        XCTAssertNil(runtime.unavailableReason)
        assertContract(runtime.exercise, kind: original.kind)
        let before = try XCTUnwrap(store.localSessions.archive.sessions.first { $0.id == original.sessionID })
        XCTAssertEqual(before.checkpoint.response, original.checkpoint.response, "Attaching the cold writer must preserve the original typed response")
        XCTAssertEqual(before.checkpoint.scratchpad, original.checkpoint.scratchpad)
        XCTAssertEqual(before.checkpoint.index, original.checkpoint.index)
        XCTAssertEqual(before.checkpoint.itemCount, original.checkpoint.itemCount)
        let entered = try enterDraft(runtime, kind: original.kind, revision: 2)
        XCTAssertNotEqual(entered, original.checkpoint.response, "A second autosave must retain the new exact typed values")
        let saved = await runtime.checkpointDraftAsync(store: store)
        XCTAssertTrue(saved, runtime.saveError ?? "Expected cold asynchronous autosave")
        let after = try XCTUnwrap(store.localSessions.archive.sessions.first { $0.id == original.sessionID })
        XCTAssertEqual(after.checkpoint.response, entered)
        XCTAssertEqual(after.checkpoint.scratchpad, note(original.kind, revision: 2))
        XCTAssertEqual(after.checkpoint.exercise, original.checkpoint.exercise)
        XCTAssertEqual(after.checkpoint.exerciseDigest, original.checkpoint.exerciseDigest)
        XCTAssertEqual(after.checkpoint.slotID, original.checkpoint.slotID)
        XCTAssertEqual(after.checkpoint.attemptID, original.checkpoint.attemptID)
        XCTAssertGreaterThan(after.revision, before.revision)
        XCTAssertFalse(after.checkpoint.referenceRevealed)
        XCTAssertFalse(after.checkpoint.solutionRevealed)
        XCTAssertNil(after.checkpoint.selfCheckRating)
        return SavedItem(kind: original.kind, sessionID: original.sessionID, checkpoint: after.checkpoint)
    }

    private func note(_ kind: Kind, revision: Int) -> String { "Synthetic \(kind.rawValue) working, revision \(revision)." }

    @inline(never)
    private func enterDraft(_ runtime: NFUniversalSessionRuntime, kind: Kind, revision: Int) throws -> NFExerciseResponse {
        runtime.scratchpad = note(kind, revision: revision)
        switch runtime.exercise.interaction {
        case let .singleChoice(schema):
            let id = try XCTUnwrap(schema.options.dropFirst(revision - 1).first).id
            runtime.singleChoiceID = id
            return .singleChoice(optionID: id)
        case let .multipleChoice(schema):
            let selected = Array(schema.options.prefix(revision).map(\.id)).sorted()
            runtime.multipleChoiceIDs = Set(selected)
            return .multipleChoice(optionIDs: selected)
        case let .numeric(schema):
            // Deliberately retain typed edits rather than evaluating either one.
            let value = revision == 1 ? "7.25" : "9.125"
            runtime.numericValue = value; runtime.numericUnit = schema.answer.canonicalUnit ?? ""
            return .numeric(.init(value: value, unit: schema.answer.canonicalUnit))
        case let .logicState(schema):
            let state = Dictionary(uniqueKeysWithValues: schema.expectedFinalState.keys.sorted().enumerated().map {
                ($0.element, String(revision * 3 + $0.offset))
            })
            runtime.logicState = state; runtime.violatedRuleID = schema.expectedViolatedRuleID
            return .logicState(.init(finalState: state, violatedRuleID: schema.expectedViolatedRuleID))
        case .selfCheck:
            let text = "My original recall about the synthetic observatory, draft \(revision)."
            runtime.selfCheckReflection = text
            XCTAssertFalse(runtime.selfCheckReferenceRevealed)
            XCTAssertFalse(runtime.exercise.independentContextText?.contains(sourceText) == true)
            return .selfCheck(.init(rating: .notYet, reflection: text))
        default:
            XCTFail("Unexpected typed fixture interaction")
            return .shortText("Unsupported fixture")
        }
    }

    @inline(never)
    private func assertContract(_ exercise: NFExercise, kind: Kind) {
        XCTAssertEqual(exercise.schemaVersion, kind.schemaVersion)
        switch kind {
        case .source:
            XCTAssertEqual(exercise.templateID, NFSourceReviewExactAdapter.templateFamily)
            guard case let .selfCheck(schema) = exercise.interaction else { return XCTFail("Expected original source recall") }
            XCTAssertEqual(schema.referenceAnswer, sourceText)
        case .coordinate: XCTAssertNotNil(NFCoordinateTransformContract.make(exercise: exercise))
        case .cube: XCTAssertNotNil(NFSpatialStructureContract.make(exercise: exercise))
        case .section: XCTAssertNotNil(NFSolidSectionContract.make(exercise: exercise))
        case .net: XCTAssertNotNil(NFNetFoldingContract.make(exercise: exercise))
        case .coordinateReasoning, .reflectionReasoning: XCTAssertNotNil(NFCoordinateReasoningContract.make(exercise: exercise))
        case .asymmetricAssembly, .feasibleAssembly: XCTAssertNotNil(NFSpatialAssemblyContract.make(exercise: exercise))
        }
    }

    private func assertWrites(_ observation: NFTypedArchiveWorkerObservation, count: Int) {
        let values = observation.writeEvents
        let expected = Array(repeating: ["encoding", "inputVerified", "staged", "renamed", "committed"], count: count).flatMap { $0 }
        XCTAssertEqual(values.map(\.0), expected)
        XCTAssertTrue(values.allSatisfy { !$0.1 }, "Encoding, validation and atomic disk writes must execute off MainActor")
    }
}

@MainActor
extension EditorialLiveControllerPersistenceTests {
    private func collectCriterionRankingHistory(_ store: AppStore) throws -> [UUID] {
        let scope = NFEditorialFamilyScope(objectiveID: "QA.controller.arithmetic", familyID: "QA.controller.numeric")
        var misses: [UUID] = []
        var structures: [String: Int] = [:]
        for _ in 0..<4 {
            XCTAssertTrue(store.beginSession(lab: .mentalMath, source: .focused, field: .general,
                targetDifficulty: 0.5, requestedItemCount: 1, seedOverride: seed, isTimed: false,
                timingCondition: .init(.untimed), launchLocaleIdentifier: "en",
                editorialStartingBand: .b1, editorialStartingFamilyScope: scope), store.lastErrorMessage ?? "")
            let runtime = NFUniversalSessionRuntime(request: try XCTUnwrap(store.activeSessionRequest))
            XCTAssertTrue(runtime.checkpointDraft(store: store)); runtime.resume(); runtime.acknowledgePresented()
            let run = try XCTUnwrap(store.localSessions.archive.sessions.first { $0.id == runtime.request.id })
            let decision = try XCTUnwrap(run.checkpoint.ordinaryReservationDecisionID.flatMap {
                store.localSessions.archive.adaptiveItemReceipts?[$0]?.editorialDecision
            })
            let structure = decision.admission.demand.structureID
            structures[structure, default: 0] += 1
            let miss = structure == "QA.structure.0"
            guard case let .numeric(schema) = runtime.exercise.interaction else { throw NFLocalSessionRepository.RepositoryError.corruptSnapshot }
            runtime.numericValue = String(schema.answer.value + (miss ? max(1, abs(schema.answer.value)) : 0))
            runtime.numericUnit = schema.answer.canonicalUnit ?? ""
            runtime.chooseConfidence(.uncertain); runtime.submitInline(store: store)
            XCTAssertEqual(runtime.stage, .feedback); XCTAssertNil(runtime.saveError)
            let attempt = try XCTUnwrap(store.attempts.first { $0.sessionID == runtime.request.id })
            let observation = try XCTUnwrap(store.effectiveAttemptDTO(attempt).editorialObservation)
            XCTAssertEqual(observation.rubricCriterionCredits["response"], miss ? 0 : 1)
            XCTAssertEqual(observation.missingCriterionIDs, miss ? ["response"] : [])
            if miss { misses.append(attempt.id) }
            runtime.next(store: store); XCTAssertEqual(runtime.stage, .summary); runtime.releaseWriter()
            store.activeSessionRequest = nil
        }
        XCTAssertEqual(structures, ["QA.structure.0": 2, "QA.structure.1": 2],
            "The fixture balances higher-priority structure share before testing the lower-priority criterion tie")
        XCTAssertEqual(misses.count, 2)
        return misses
    }
    private func criterionRankingRequest(_ store: AppStore, oldPolicy: Bool = false) throws -> SessionRequest {
        var request = template()
        request.ordinaryDelivery = .init(strategy: .adaptiveItem, profileID: profileID, bank: NFOfflineQuestionBank.rotationBank)
        var pin = try XCTUnwrap(store.localSessions.editorialAdmissions.sessionPin(for: request, initialUserBand: .b1,
            startingScope: .init(objectiveID: "QA.controller.arithmetic", familyID: "QA.controller.numeric")))
        if oldPolicy { pin.controllerVersion = NFEditorialLiveController.demonstratedVersion }
        request.ordinaryDelivery?.editorialPolicy = pin
        return request
    }

    func testActualObservedCriterionTiePreferencePersistsExactSupportingIDsAndColdReplay() throws {
        let root = try root(); defer { try? FileManager.default.removeItem(at: root) }
        let admissions = try catalog()
        var expected: NFLocalSessionEnvelope!
        var expectedDecision: NFEditorialControllerDecision!
        do {
            let container = try container(root, persistent: true)
            let store = try store(root, context: container.mainContext, admissions: admissions)
            let misses = try collectCriterionRankingHistory(store)
            let originalRecords = try NFEditorialCanonicalData.encode(store.attempts.map(NFImmutableAttemptRecordSnapshot.init))
            let preparation = try store.prepareAdaptiveItem(request: criterionRankingRequest(store), predecessor: nil)
            let decision = try XCTUnwrap(preparation.receipt.editorialDecision)
            let selected = try XCTUnwrap(decision.criterionSelection)
            XCTAssertEqual(decision.controllerVersion, NFEditorialLiveController.version)
            XCTAssertEqual(selected.structureID, "QA.structure.0"); XCTAssertEqual(selected.preference, 1)
            XCTAssertEqual(selected.matches.map(\.criterionID), ["response"])
            XCTAssertEqual(selected.supportingObservationIDs, Set(misses.map(\.uuidString)))
            XCTAssertEqual(decision.selection.deliveredBand, .b1)
            XCTAssertEqual(decision.controlAfter.totalAutomaticChangesThisSession, 0)
            XCTAssertTrue(decision.evidence.retention.isEmpty, "Ordinary criterion preference is not a declared due review or completed repair")
            expected = try store.acceptAdaptiveItem(preparation, checkpoint: preparation.checkpoint)
            expectedDecision = decision
            XCTAssertEqual(try NFEditorialCanonicalData.encode(store.attempts.map(NFImmutableAttemptRecordSnapshot.init)), originalRecords)
        }
        let container = try container(root, persistent: true)
        let store = try store(root, context: container.mainContext, admissions: admissions)
        XCTAssertNil(store.localSessions.loadError)
        let saved = try XCTUnwrap(store.localSessions.archive.sessions.first { $0.id == expected.id })
        XCTAssertEqual(saved.checkpoint, expected.checkpoint)
        let receipt = try XCTUnwrap(saved.checkpoint.ordinaryReservationDecisionID.flatMap { store.localSessions.archive.adaptiveItemReceipts?[$0] })
        XCTAssertEqual(receipt.editorialDecision, expectedDecision)
        XCTAssertEqual(store.attempts.count, 4)
    }

    func testActualCriterionCorrectionRejectsPreparedSelectionAndDoesNotRewriteOriginalAnswers() throws {
        let root = try root(); defer { try? FileManager.default.removeItem(at: root) }
        let container = try container(root), store = try store(root, context: container.mainContext, admissions: catalog())
        let misses = try collectCriterionRankingHistory(store)
        let request = try criterionRankingRequest(store)
        let preparation = try store.prepareAdaptiveItem(request: request, predecessor: nil)
        XCTAssertEqual(preparation.receipt.editorialDecision?.criterionSelection?.preference, 1)
        let records = try NFEditorialCanonicalData.encode(store.attempts.map(NFImmutableAttemptRecordSnapshot.init))
        try store.localSessions.appendDispositions([.init(id: "QA.criterion.exclusion", attemptID: try XCTUnwrap(misses.first).uuidString,
            revision: 1, policyVersion: NFHistoricalPracticeProjection.policyVersion, occurredAt: Date(),
            disposition: .excludedContentCorrection, reason: "Synthetic criterion authority removed before publication",
            correctedDerivedCredit: nil, supersedesDispositionID: nil)])
        let afterCorrection = try Data(contentsOf: root.appending(path: "sessions-v1.json"))
        XCTAssertThrowsError(try store.acceptAdaptiveItem(preparation, checkpoint: preparation.checkpoint))
        XCTAssertEqual(try Data(contentsOf: root.appending(path: "sessions-v1.json")), afterCorrection)
        let refreshed = try store.prepareAdaptiveItem(request: request, predecessor: nil)
        XCTAssertEqual(refreshed.receipt.editorialDecision?.criterionSelection?.preference, 0)
        XCTAssertNotEqual(refreshed.receipt.editorialDecision?.evidenceDigest, preparation.receipt.editorialDecision?.evidenceDigest)
        _ = try store.acceptAdaptiveItem(refreshed, checkpoint: refreshed.checkpoint)
        XCTAssertEqual(try NFEditorialCanonicalData.encode(store.attempts.map(NFImmutableAttemptRecordSnapshot.init)), records)
    }

    func testAcceptedV2CriterionFreePolicyKeepsItsPinAndDecisionAfterNewRankingIsInstalled() throws {
        let root = try root(); defer { try? FileManager.default.removeItem(at: root) }
        let container = try container(root), admissions = try catalog()
        let store = try store(root, context: container.mainContext, admissions: admissions)
        _ = try collectCriterionRankingHistory(store)
        let request = try criterionRankingRequest(store, oldPolicy: true)
        let originalRequest = try NFEditorialCanonicalData.encode(request)
        let first = try store.prepareAdaptiveItem(request: request, predecessor: nil)
        let same = try store.prepareAdaptiveItem(request: request, predecessor: nil, at: first.checkpoint.shownAt)
        XCTAssertEqual(first.receipt, same.receipt)
        XCTAssertEqual(first.receipt.editorialDecision?.controllerVersion, NFEditorialLiveController.demonstratedVersion)
        XCTAssertNil(first.receipt.editorialDecision?.criterionSelection)
        let accepted = try store.acceptAdaptiveItem(first, checkpoint: first.checkpoint)
        XCTAssertEqual(try NFEditorialCanonicalData.encode(request), originalRequest)
        let reopened = NFLocalSessionRepository(url: root.appending(path: "sessions-v1.json"), ownerDeviceID: owner, editorialAdmissions: admissions)
        XCTAssertNil(reopened.loadError)
        XCTAssertEqual(reopened.archive.sessions.first { $0.id == accepted.id }?.checkpoint, accepted.checkpoint)
        XCTAssertEqual(reopened.archive.adaptiveItemReceipts?[first.receipt.decisionID], first.receipt)
        let oldMixed = NFEditorialSessionPin(schemaVersion: 2, catalogVersion: "QA", objectiveID: "A", familyID: "a",
            controllerVersion: NFEditorialMixedController.demonstratedVersion, catalogDigest: String(repeating: "b", count: 64),
            familyScopes: [.init(objectiveID: "A", familyID: "a"), .init(objectiveID: "B", familyID: "b")])
        XCTAssertEqual(oldMixed.familyControllerVersion, NFEditorialLiveController.demonstratedVersion)
        XCTAssertTrue(oldMixed.usesDemonstratedInitialTarget); XCTAssertFalse(oldMixed.usesObservedCriterionRanking)
    }
}

@MainActor
extension EditorialLiveControllerPersistenceTests {
    func testCriterionSelectionRetainsEachTimingConditionAfterTimedToDisplayOnlyNextAndColdResume() throws {
        for mode in [NFEditorialTimingMode.untimed, .elapsedOnly] {
            let root = try root(); defer { try? FileManager.default.removeItem(at: root) }
            let container = try container(root, persistent: true)
            defer { withExtendedLifetime(container) {} }
            let admissions = try catalog(fluencyEligible: true)
            let store = try store(root, context: container.mainContext, admissions: admissions)
            XCTAssertFalse(store.allowsSharedWidgetPublishing)
            try collectFluencyPractice(store)
            let condition = try XCTUnwrap(store.reviewedFluencyReadiness(lab: .mentalMath,
                familyScope: fluencyFamily, band: .b1).condition)
            let runtime = try launchFluencyPractice(store, count: 3, condition: condition)
            let launchRun = try XCTUnwrap(store.localSessions.archive.sessions.first { $0.id == runtime.sessionID })
            let firstReceipt = try XCTUnwrap(launchRun.checkpoint.ordinaryReservationDecisionID.flatMap {
                store.localSessions.archive.adaptiveItemReceipts?[$0]
            })
            XCTAssertEqual(firstReceipt.selectionTimingCondition, condition)
            try answer(runtime, store: store); runtime.next(store: store)
            XCTAssertNil(runtime.saveError); XCTAssertEqual(runtime.index, 1)
            let secondRun = try XCTUnwrap(store.localSessions.archive.sessions.first { $0.id == runtime.sessionID })
            let secondReceipt = try XCTUnwrap(secondRun.checkpoint.ordinaryReservationDecisionID.flatMap {
                store.localSessions.archive.adaptiveItemReceipts?[$0]
            })
            XCTAssertEqual(secondReceipt.selectionTimingCondition, condition)
            XCTAssertEqual(secondReceipt.editorialDecision?.criterionSelection?.group.pacingConditionID, "timedFluency")
            runtime.setDisplayTiming(mode, store: store)
            XCTAssertNil(runtime.saveError); XCTAssertEqual(runtime.currentTimingCondition, .init(mode))
            XCTAssertFalse(runtime.usesTimedMode)
            try answer(runtime, store: store); runtime.next(store: store)
            XCTAssertNil(runtime.saveError); XCTAssertEqual(runtime.index, 2)
            let saved = try XCTUnwrap(store.localSessions.archive.sessions.first { $0.id == runtime.sessionID })
            let lastReceipt = try XCTUnwrap(saved.checkpoint.ordinaryReservationDecisionID.flatMap {
                store.localSessions.archive.adaptiveItemReceipts?[$0]
            })
            XCTAssertEqual(lastReceipt.selectionTimingCondition, .init(mode))
            XCTAssertEqual(lastReceipt.editorialDecision?.criterionSelection?.group.pacingConditionID, mode.rawValue)
            XCTAssertEqual(saved.request.timingCondition, condition, "The accepted original timed request is immutable")
            XCTAssertEqual(store.localSessions.archive.adaptiveItemReceipts?[firstReceipt.decisionID], firstReceipt)
            XCTAssertEqual(store.localSessions.archive.adaptiveItemReceipts?[secondReceipt.decisionID], secondReceipt)
            let committed = store.attempts.filter { $0.sessionID == runtime.sessionID }
            XCTAssertEqual(committed.count, 2); XCTAssertEqual(committed.filter(\.wasTimed).count, 1)
            let originalRecords = try NFEditorialCanonicalData.encode(committed.map(NFImmutableAttemptRecordSnapshot.init))
            runtime.releaseWriter(); store.activeSessionRequest = nil
            let reopened = try self.store(root, context: container.mainContext, admissions: admissions)
            XCTAssertNil(reopened.localSessions.loadError)
            XCTAssertEqual(reopened.localSessions.archive.adaptiveItemReceipts?[firstReceipt.decisionID], firstReceipt)
            XCTAssertEqual(reopened.localSessions.archive.adaptiveItemReceipts?[secondReceipt.decisionID], secondReceipt)
            XCTAssertEqual(reopened.localSessions.archive.adaptiveItemReceipts?[lastReceipt.decisionID], lastReceipt)
            XCTAssertTrue(reopened.resumeSession(saved.id))
            let cold = NFUniversalSessionRuntime(request: try XCTUnwrap(reopened.activeSessionRequest))
            defer { cold.releaseWriter() }
            XCTAssertTrue(cold.checkpointDraft(store: reopened), cold.saveError ?? "")
            cold.resume(); cold.acknowledgePresented()
            XCTAssertEqual(cold.currentTimingCondition, .init(mode)); XCTAssertFalse(cold.usesTimedMode)
            XCTAssertEqual(cold.exercise, saved.checkpoint.exercise)
            XCTAssertEqual(try NFEditorialCanonicalData.encode(reopened.attempts.filter { $0.sessionID == runtime.sessionID }
                .map(NFImmutableAttemptRecordSnapshot.init)), originalRecords)
        }
    }

    func testCriterionTimingPinCannotBeRemovedOrChangedAtAtomicAcceptanceOrForgeColdTimedScope() throws {
        let root = try root(); defer { try? FileManager.default.removeItem(at: root) }
        let container = try container(root); defer { withExtendedLifetime(container) {} }
        let admissions = try catalog(fluencyEligible: true)
        let store = try store(root, context: container.mainContext, admissions: admissions)
        let request = try initialRequest(admissions, band: .b1, count: 2)
        let prepared = try store.prepareAdaptiveItem(request: request, predecessor: nil)
        XCTAssertEqual(prepared.receipt.selectionTimingCondition, .init(.untimed))
        let before = try NFEditorialCanonicalData.encode(store.localSessions.archive)
        var future = NFSessionTimingCondition(.untimed); future.schemaVersion = 999
        for condition in [Optional<NFSessionTimingCondition>.none, .some(.init(.elapsedOnly)), .some(future)] {
            var receipt = prepared.receipt; receipt.selectionTimingCondition = condition
            let forged = NFLocalAdaptiveItemPreparation(expectedArchiveRevision: prepared.expectedArchiveRevision,
                expectedRunRevision: prepared.expectedRunRevision, request: prepared.request, receipt: receipt,
                checkpoint: prepared.checkpoint, replacementRotationLedger: prepared.replacementRotationLedger,
                importsLegacy: prepared.importsLegacy, legacySnapshot: prepared.legacySnapshot, replay: prepared.replay,
                overrideWriterAuthority: prepared.overrideWriterAuthority, sessionWriterCommand: prepared.sessionWriterCommand)
            XCTAssertThrowsError(try store.acceptAdaptiveItem(forged, checkpoint: forged.checkpoint))
            XCTAssertEqual(try NFEditorialCanonicalData.encode(store.localSessions.archive), before)
        }
        let saved = try store.acceptAdaptiveItem(prepared, checkpoint: prepared.checkpoint)
        let sourceBytes = try Data(contentsOf: root.appending(path: "sessions-v1.json"))
        var archive = store.localSessions.archive
        var receipt = prepared.receipt
        let selected = try XCTUnwrap(receipt.editorialDecision?.criterionSelection)
        let scope = selected.group
        let timedGroup = NFEditorialEvidenceGroup(lane: scope.lane, objectiveID: scope.objectiveID, familyID: scope.familyID,
            band: scope.band, bandContractVersion: scope.bandContractVersion,
            scoringComparabilityID: scope.scoringComparabilityID, stimulusComparabilityID: scope.stimulusComparabilityID,
            toolConditionID: scope.toolConditionID, localeComparabilityID: scope.localeComparabilityID,
            pacingConditionID: "timedFluency", protocolScope: scope.protocolScope)
        receipt.editorialDecision?.criterionSelection = .init(policyVersion: selected.policyVersion,
            candidateID: selected.candidateID, exerciseDigest: selected.exerciseDigest, group: timedGroup,
            structureID: selected.structureID, criterionIDs: selected.criterionIDs,
            coverageRaw: selected.coverageRaw, matches: selected.matches)
        receipt.selectionTimingCondition = .init(.timedFluency, fluencyScope: scope)
        XCTAssertTrue(receipt.isSupported, "This is a structurally valid forged scope; cold validation must bind the accepted request")
        archive.adaptiveItemReceipts?[receipt.decisionID] = receipt
        let forgedURL = root.appending(path: "forged-timing.json")
        try JSONEncoder().encode(archive).write(to: forgedURL)
        let reopened = NFLocalSessionRepository(url: forgedURL, ownerDeviceID: owner, editorialAdmissions: admissions)
        XCTAssertTrue(reopened.loadError != nil || reopened.archive.sessions.first { $0.id == saved.id }?.status == .migrationRecovery,
            "A forged or unsupported timing pin cannot become writable timing authority")
        XCTAssertEqual(try Data(contentsOf: root.appending(path: "sessions-v1.json")), sourceBytes)
        // Known prior V3 receipts had no pin. Exact untimed legacy receipts still
        // decode without backfilling bytes or borrowing today's display setting.
        var legacy = store.localSessions.archive
        var legacyReceipt = prepared.receipt; legacyReceipt.selectionTimingCondition = nil
        legacy.adaptiveItemReceipts?[legacyReceipt.decisionID] = legacyReceipt
        let legacyURL = root.appending(path: "legacy-timing.json")
        try JSONEncoder().encode(legacy).write(to: legacyURL)
        let old = NFLocalSessionRepository(url: legacyURL, ownerDeviceID: owner, editorialAdmissions: admissions)
        XCTAssertNil(old.loadError)
        XCTAssertNil(old.archive.adaptiveItemReceipts?[legacyReceipt.decisionID]?.selectionTimingCondition)
    }
}

@MainActor
extension EditorialLiveControllerPersistenceTests {
    func testTimedRunCanRemoveTimingTargetAdvanceToB2AndResumeWithExactUntimedAdmission() throws {
        let root = try root(); defer { try? FileManager.default.removeItem(at: root) }
        let container = try container(root, persistent: true); defer { withExtendedLifetime(container) {} }
        // Leave enough B1 supply after eight genuine prerequisite commits to
        // exercise a four-response promotion without an inventory shortage.
        let original = try catalog(fluencyEligible: true)
        let entries = try original.entries.enumerated().map { index, entry in
            guard index < 20 else { return entry }
            var raw = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(entry)) as? [String: Any])
            var demand = try XCTUnwrap(raw["demand"] as? [String: Any])
            demand["editorialBand"] = NFEditorialBand.b1.rawValue
            raw["demand"] = demand
            return try JSONDecoder().decode(NFEditorialAdmissionEntry.self, from: JSONSerialization.data(withJSONObject: raw))
        }
        let admissions = NFEditorialAdmissionContext(version: "QA.timing-override-larger-B1.v1", entries: entries)
        let store = try store(root, context: container.mainContext, admissions: admissions)
        XCTAssertFalse(store.allowsSharedWidgetPublishing)
        try collectFluencyPractice(store)
        let condition = try XCTUnwrap(store.reviewedFluencyReadiness(lab: .mentalMath,
            familyScope: fluencyFamily, band: .b1).condition)
        let runtime = try launchFluencyPractice(store, count: 6, condition: condition)
        let originalRequest = try NFEditorialCanonicalData.encode(runtime.request.launchOnly())
        let firstRun = try XCTUnwrap(store.localSessions.archive.sessions.first { $0.id == runtime.sessionID })
        let firstReceipt = try XCTUnwrap(firstRun.checkpoint.ordinaryReservationDecisionID.flatMap {
            store.localSessions.archive.adaptiveItemReceipts?[$0]
        })
        XCTAssertEqual(firstReceipt.selectionTimingCondition, condition)
        runtime.setDisplayTiming(.untimed, store: store)
        XCTAssertNil(runtime.saveError)
        for index in 0..<4 {
            XCTAssertEqual(runtime.index, index); XCTAssertFalse(runtime.usesTimedMode)
            XCTAssertEqual(store.localSessions.editorialChallengePresentation(sessionID: runtime.sessionID)?.deliveredBand, .b1)
            try answer(runtime, store: store); runtime.next(store: store)
            XCTAssertNil(runtime.saveError); XCTAssertNil(runtime.nextUnavailableReason)
        }
        XCTAssertEqual(runtime.index, 4)
        XCTAssertEqual(store.localSessions.editorialChallengePresentation(sessionID: runtime.sessionID)?.deliveredBand, .b2)
        XCTAssertEqual(runtime.currentTimingCondition, .init(.untimed)); XCTAssertFalse(runtime.usesTimedMode)
        XCTAssertTrue(runtime.canEditDraft)
        let saved = try XCTUnwrap(store.localSessions.archive.sessions.first { $0.id == runtime.sessionID })
        let last = try XCTUnwrap(saved.checkpoint.ordinaryReservationDecisionID.flatMap {
            store.localSessions.archive.adaptiveItemReceipts?[$0]
        })
        XCTAssertEqual(last.selectionTimingCondition, .init(.untimed))
        XCTAssertEqual(last.editorialDecision?.criterionSelection?.group.pacingConditionID, "untimed")
        XCTAssertEqual(last.editorialDecision?.admission.demand.editorialBand, .b2)
        XCTAssertEqual(try NFEditorialCanonicalData.encode(saved.request.launchOnly()), originalRequest)
        XCTAssertEqual(store.localSessions.archive.adaptiveItemReceipts?[firstReceipt.decisionID], firstReceipt)
        runtime.numericValue = "17"; XCTAssertTrue(runtime.checkpointDraft(store: store), runtime.saveError ?? "")
        runtime.releaseWriter(); store.activeSessionRequest = nil
        let reopened = try self.store(root, context: container.mainContext, admissions: admissions)
        XCTAssertNil(reopened.localSessions.loadError); XCTAssertTrue(reopened.resumeSession(saved.id))
        let cold = NFUniversalSessionRuntime(request: try XCTUnwrap(reopened.activeSessionRequest))
        XCTAssertFalse(cold.canSubmit); XCTAssertFalse(cold.canEditDraft)
        XCTAssertTrue(cold.checkpointDraft(store: reopened), cold.saveError ?? "")
        cold.resume(); cold.acknowledgePresented()
        XCTAssertEqual(cold.currentTimingCondition, .init(.untimed)); XCTAssertTrue(cold.canSubmit)
        XCTAssertEqual(cold.numericValue, "17"); XCTAssertEqual(cold.exercise, saved.checkpoint.exercise)
        try answer(cold, store: reopened); cold.next(store: reopened)
        XCTAssertNil(cold.saveError); XCTAssertEqual(cold.index, 5)
        XCTAssertFalse(cold.usesTimedMode)
        let current = try XCTUnwrap(reopened.localSessions.archive.sessions.first { $0.id == saved.id })
        cold.releaseWriter(); reopened.activeSessionRequest = nil
        let records = try NFEditorialCanonicalData.encode(reopened.attempts.map(NFImmutableAttemptRecordSnapshot.init))
        let changedAdmissions = NFEditorialAdmissionContext(version: "QA.changed-timing-authority", entries: entries)
        let changed = try self.store(root, context: container.mainContext, admissions: changedAdmissions)
        XCTAssertTrue(changed.resumeSession(current.id))
        let untrusted = NFUniversalSessionRuntime(request: try XCTUnwrap(changed.activeSessionRequest))
        defer { untrusted.releaseWriter() }
        XCTAssertFalse(untrusted.checkpointDraft(store: changed))
        XCTAssertFalse(untrusted.canEditDraft); XCTAssertFalse(untrusted.canSubmit)
        XCTAssertFalse(untrusted.isTimingPresentationReady)
        XCTAssertEqual(try NFEditorialCanonicalData.encode(changed.attempts.map(NFImmutableAttemptRecordSnapshot.init)), records)
    }
}


@MainActor
extension EditorialLiveControllerPersistenceTests {
    private func reviewCatalog() throws -> NFEditorialAdmissionContext {
        let original = try catalog()
        let contract = NFEditorialReviewContract(scopeID: "QA.controller-response-review.v1", criterionIDs: ["response"],
            siblingStructureIDs: ["QA.structure.0", "QA.structure.1"], allowedRoles: [.delayedCheck, .probe, .repair])
        let entries = original.entries.map { entry -> NFEditorialAdmissionEntry in
            var demand = entry.demand; demand.reviewContract = contract
            return .init(id: entry.id, bankQuestionID: entry.bankQuestionID, exerciseDigest: entry.exerciseDigest,
                scorerVersion: entry.scorerVersion, lab: entry.lab, contentLocale: entry.contentLocale, demand: demand)
        }
        return .init(version: "QA.authored-review-slots.v1", entries: entries)
    }
    private func incorrectReviewAnswer(_ runtime: NFUniversalSessionRuntime, store: AppStore) throws {
        runtime.acknowledgePresented()
        guard case let .numeric(schema) = runtime.exercise.interaction else { throw NFLocalSessionRepository.RepositoryError.corruptSnapshot }
        runtime.numericValue = String(schema.answer.value + max(1, abs(schema.answer.value)))
        runtime.numericUnit = schema.answer.canonicalUnit ?? ""
        runtime.chooseConfidence(.fairlyConfident); runtime.submitInline(store: store)
        XCTAssertEqual(runtime.stage, .feedback); XCTAssertFalse(try XCTUnwrap(runtime.lastResult).isCorrect)
        XCTAssertNil(runtime.saveError)
    }

    func testActualReviewedRepairRequiresVisibleFeedbackThenPersistsDistinctRoleAndColdState() throws {
        let root = try root(); defer { try? FileManager.default.removeItem(at: root) }
        let admissions = try reviewCatalog(), container = try container(root, persistent: true)
        let store = try store(root, context: container.mainContext, admissions: admissions)
        let runtime = try launch(store); defer { runtime.releaseWriter() }
        XCTAssertEqual(runtime.request.ordinaryDelivery?.editorialPolicy?.controllerVersion, NFEditorialLiveController.reviewVersion)
        let first = try receipt(store)
        XCTAssertEqual(first.editorialDecision?.reviewAssignment?.role, .probe)
        try incorrectReviewAnswer(runtime, store: store)
        let original = try XCTUnwrap(store.attempts.first), originalBytes = try NFImmutableAttemptRecordSnapshot.encoded(NFImmutableAttemptRecordSnapshot(original))
        let observed = try XCTUnwrap(store.effectiveAttemptDTO(original).editorialObservation)
        XCTAssertEqual(observed.retentionScopeID, "QA.controller-response-review.v1")
        XCTAssertFalse(observed.isIndependentRepair)
        XCTAssertNil(store.localSessions.archive.editorialExplanationPresentations?[original.id.uuidString])
        runtime.acknowledgePresented()
        let presentation = try XCTUnwrap(store.localSessions.archive.editorialExplanationPresentations?[original.id.uuidString])
        XCTAssertEqual(presentation.feedbackDigest, store.localSessions.editorialSnapshot(for: original.id)?.editorialCapture?.reviewFeedbackDigest)
        runtime.next(store: store)
        XCTAssertEqual(runtime.index, 1); XCTAssertEqual(runtime.stage, .item); XCTAssertNil(runtime.saveError)
        let repairedSlot = try receipt(store)
        let assignment = try XCTUnwrap(repairedSlot.editorialDecision?.reviewAssignment)
        XCTAssertEqual(assignment.role, .repair); XCTAssertEqual(assignment.originObservationID, original.id.uuidString)
        XCTAssertEqual(assignment.explanation, presentation)
        XCTAssertNotEqual(assignment.semanticFingerprint, first.editorialDecision?.admission.demand.semanticFingerprint)
        XCTAssertEqual(assignment.entry?.status, .readyForRepair)
        try answer(runtime, store: store)
        let repairRecord = try XCTUnwrap(store.attempts.first { $0.id != original.id })
        let repaired = try XCTUnwrap(store.effectiveAttemptDTO(repairRecord).editorialObservation)
        XCTAssertTrue(repaired.isIndependentRepair); XCTAssertEqual(repaired.lane, .practice)
        let state = EditorialBandEvidenceV1.reduce([observed, repaired], decisionDayOrdinal: repaired.canonicalDayOrdinal)
        XCTAssertEqual(state.retention.first?.rung, 0)
        XCTAssertEqual(state.retention.first?.status, .dueForDelayedCheck)
        XCTAssertEqual(state.retention.first?.dueDayOrdinal, repaired.canonicalDayOrdinal + 1)
        XCTAssertEqual(try NFImmutableAttemptRecordSnapshot.encoded(NFImmutableAttemptRecordSnapshot(original)), originalBytes)
        runtime.pause(); XCTAssertTrue(runtime.checkpointDraft(store: store)); runtime.releaseWriter()
        let cold = try self.store(root, context: container.mainContext, admissions: admissions)
        XCTAssertNil(cold.localSessions.loadError)
        XCTAssertEqual(cold.localSessions.archive.adaptiveItemReceipts?[repairedSlot.decisionID], repairedSlot)
        XCTAssertEqual(cold.localSessions.archive.editorialExplanationPresentations?[original.id.uuidString], presentation)
        let exported = cold.localSessions.exportArchive
        XCTAssertNil(exported.editorialExplanationPresentations); XCTAssertNil(exported.adaptiveItemReceipts)
    }

    func testActualDeclaredDueSlotUsesPastNativeOriginAndAdvancesOneRungOnlyAfterCommit() throws {
        let root = try root(); defer { try? FileManager.default.removeItem(at: root) }
        let admissions = try reviewCatalog(), container = try container(root)
        let store = try store(root, context: container.mainContext, admissions: admissions)
        try collectInitialHistory(store, admissions: admissions, band: .b1, at: Date().addingTimeInterval(-2 * 86_400), count: 1)
        let original = try XCTUnwrap(store.attempts.first)
        let history = try XCTUnwrap(store.effectiveAttemptDTO(original).editorialObservation)
        XCTAssertNotNil(history.retentionScopeID)
        let runtime = try launch(store); defer { runtime.releaseWriter() }
        let run = try XCTUnwrap(store.localSessions.archive.sessions.first { $0.id == runtime.sessionID })
        let selected = try XCTUnwrap(run.checkpoint.ordinaryReservationDecisionID.flatMap { store.localSessions.archive.adaptiveItemReceipts?[$0] })
        let assignment = try XCTUnwrap(selected.editorialDecision?.reviewAssignment)
        XCTAssertEqual(assignment.role, .delayedCheck)
        XCTAssertEqual(assignment.originObservationID, original.id.uuidString)
        XCTAssertEqual(assignment.entry?.rung, 0)
        XCTAssertEqual(store.attempts.count, 1, "Selection is not a successful delayed check")
        try answer(runtime, store: store)
        let newRecord = try XCTUnwrap(store.attempts.first { $0.id != original.id })
        let delayed = try XCTUnwrap(store.effectiveAttemptDTO(newRecord).editorialObservation)
        XCTAssertEqual(delayed.lane, .retention); XCTAssertFalse(delayed.isIndependentRepair)
        let state = EditorialBandEvidenceV1.reduce([history, delayed], decisionDayOrdinal: delayed.canonicalDayOrdinal)
        XCTAssertEqual(state.retention.first?.rung, 1)
        XCTAssertEqual(state.retention.first?.dueDayOrdinal, delayed.canonicalDayOrdinal + 3)
        runtime.acknowledgePresented(); runtime.next(store: store)
        let nextRun = try XCTUnwrap(store.localSessions.archive.sessions.first { $0.id == runtime.sessionID })
        let nextReceipt = try XCTUnwrap(nextRun.checkpoint.ordinaryReservationDecisionID.flatMap { store.localSessions.archive.adaptiveItemReceipts?[$0] })
        XCTAssertEqual(nextReceipt.editorialDecision?.reviewAssignment?.role, .probe, "A later same-day question cannot consume tomorrow's review role")
    }

    func testActualExplicitRepairKeepsOriginWriterAndRefusesStaleCommandOrChangedEvidence() throws {
        let root = try root(); defer { try? FileManager.default.removeItem(at: root) }
        let admissions = try reviewCatalog(), container = try container(root)
        let store = try store(root, context: container.mainContext, admissions: admissions)
        let runtime = try launch(store); defer { runtime.releaseWriter() }
        try incorrectReviewAnswer(runtime, store: store)
        let original = try XCTUnwrap(store.attempts.first)
        let command = try runtime.sessionWriterCommand(), id = UUID()
        let noPresentation = try NFEditorialCanonicalData.encode(store.localSessions.archive)
        XCTAssertFalse(store.beginEditorialRepair(from: runtime.request, commandID: id, command: command))
        XCTAssertEqual(try NFEditorialCanonicalData.encode(store.localSessions.archive), noPresentation)
        runtime.acknowledgePresented()
        runtime.retrySimilar(store: store)
        let request = try XCTUnwrap(store.activeSessionRequest)
        XCTAssertNotEqual(request.id, runtime.request.id); XCTAssertEqual(request.requestedItemCount, 1)
        XCTAssertEqual(request.ordinaryDelivery?.editorialPolicy?.reviewIntent, .init(role: .repair, originObservationID: original.id.uuidString))
        let run = try XCTUnwrap(store.localSessions.archive.sessions.first { $0.id == request.id })
        XCTAssertEqual(run.checkpoint.correctness, [])
        let selected = try XCTUnwrap(run.checkpoint.ordinaryReservationDecisionID.flatMap { store.localSessions.archive.adaptiveItemReceipts?[$0] })
        XCTAssertEqual(selected.editorialDecision?.reviewAssignment?.role, .repair)
        let before = try NFEditorialCanonicalData.encode(store.localSessions.archive)
        XCTAssertFalse(store.beginEditorialRepair(from: runtime.request, commandID: UUID(), command: command))
        XCTAssertEqual(try NFEditorialCanonicalData.encode(store.localSessions.archive), before)
        try store.localSessions.removeReferences(attemptIDs: [original.id])
        let retained = try XCTUnwrap(store.localSessions.archive.sessions.first { $0.id == request.id })
        XCTAssertEqual(retained.checkpoint, run.checkpoint)
        XCTAssertEqual(retained.status, .migrationRecovery, "Deleting an origin removes continuation authority, not the successor's exact saved work")
        let reopened = try self.store(root, context: container.mainContext, admissions: admissions)
        XCTAssertNil(reopened.localSessions.loadError)
        XCTAssertNil(reopened.localSessions.archive.editorialExplanationPresentations?[original.id.uuidString])
    }
}

@MainActor
extension EditorialLiveControllerPersistenceTests {
    func testDeclaredDueAssignmentRejectsStaleEffectiveOriginAndLegacyPinDoesNotBackfillScope() throws {
        let root = try root(); defer { try? FileManager.default.removeItem(at: root) }
        let admissions = try reviewCatalog(), container = try container(root)
        let store = try store(root, context: container.mainContext, admissions: admissions)
        try collectInitialHistory(store, admissions: admissions, band: .b1, at: Date().addingTimeInterval(-2 * 86_400), count: 1)
        let origin = try XCTUnwrap(store.attempts.first)
        let request = try initialRequest(admissions, band: .b1, count: 8)
        let prepared = try store.prepareAdaptiveItem(request: request, predecessor: nil)
        XCTAssertEqual(prepared.receipt.editorialDecision?.reviewAssignment?.role, .delayedCheck)
        let raw = try NFImmutableAttemptRecordSnapshot.encoded(NFImmutableAttemptRecordSnapshot(origin))
        try store.localSessions.appendDispositions([.init(id: "QA.review-origin-excluded", attemptID: origin.id.uuidString,
            revision: 1, policyVersion: NFHistoricalPracticeProjection.policyVersion, occurredAt: Date(),
            disposition: .excludedContentCorrection, reason: "Synthetic reviewed origin invalidated",
            correctedDerivedCredit: nil, supersedesDispositionID: nil)])
        let before = try Data(contentsOf: root.appending(path: "sessions-v1.json"))
        XCTAssertThrowsError(try store.acceptAdaptiveItem(prepared, checkpoint: prepared.checkpoint))
        XCTAssertEqual(try Data(contentsOf: root.appending(path: "sessions-v1.json")), before)
        let changed = try store.prepareAdaptiveItem(request: request, predecessor: nil)
        XCTAssertEqual(changed.receipt.editorialDecision?.reviewAssignment?.role, .probe)
        XCTAssertNotEqual(changed.receipt.editorialDecision?.evidenceDigest, prepared.receipt.editorialDecision?.evidenceDigest)
        XCTAssertEqual(try NFImmutableAttemptRecordSnapshot.encoded(NFImmutableAttemptRecordSnapshot(origin)), raw)
        var oldRequest = try initialRequest(admissions, band: .b1, count: 1)
        // This branch enters the live runtime. Match canonical beginSession:
        // freeze its routing identity before the reservation digest is created.
        oldRequest.localSessionID = oldRequest.id
        oldRequest.ordinaryDelivery?.editorialPolicy?.controllerVersion = NFEditorialLiveController.version
        let legacy = try store.prepareAdaptiveItem(request: oldRequest, predecessor: nil)
        XCTAssertNil(legacy.receipt.editorialDecision?.reviewAssignment)
        XCTAssertEqual(legacy.receipt.editorialDecision?.controllerVersion, NFEditorialLiveController.version)
        let accepted = try store.acceptAdaptiveItem(legacy, checkpoint: legacy.checkpoint)
        var live = accepted.request; live.localCheckpoint = accepted.checkpoint; live.localSessionID = accepted.id
        XCTAssertEqual(try NFLocalReservationBridge.configurationDigest(live), legacy.receipt.configurationDigest)
        let runtime = NFUniversalSessionRuntime(request: live); defer { runtime.releaseWriter() }
        XCTAssertTrue(runtime.checkpointDraft(store: store), runtime.saveError ?? ""); runtime.resume(); runtime.acknowledgePresented()
        try answer(runtime, store: store)
        let scored = try XCTUnwrap(store.attempts.first { $0.sessionID == runtime.sessionID })
        let observation = try XCTUnwrap(store.effectiveAttemptDTO(scored).editorialObservation)
        XCTAssertNil(observation.retentionScopeID); XCTAssertFalse(observation.isIndependentRepair)
        XCTAssertNil(store.localSessions.archive.editorialExplanationPresentations?[scored.id.uuidString])
    }
}

@MainActor
extension EditorialLiveControllerPersistenceTests {
    func testDeletingAnotherAnswerInOriginRunRetainsDependentRepairAsRecoveryOnly() throws {
        let root = try root(); defer { try? FileManager.default.removeItem(at: root) }
        let admissions = try reviewCatalog(), container = try container(root)
        let store = try store(root, context: container.mainContext, admissions: admissions)
        let runtime = try launch(store); defer { runtime.releaseWriter() }
        try answer(runtime, store: store)
        let siblingID = try XCTUnwrap(store.localSessions.archive.sessions.first { $0.id == runtime.sessionID }?.checkpoint.committedAttemptID)
        runtime.acknowledgePresented(); runtime.next(store: store)
        try incorrectReviewAnswer(runtime, store: store)
        let originID = try XCTUnwrap(store.localSessions.archive.sessions.first { $0.id == runtime.sessionID }?.checkpoint.committedAttemptID)
        XCTAssertNotEqual(originID, siblingID)
        runtime.acknowledgePresented(); runtime.retrySimilar(store: store)
        let request = try XCTUnwrap(store.activeSessionRequest)
        XCTAssertNotEqual(request.id, runtime.sessionID)
        let before = try XCTUnwrap(store.localSessions.archive.sessions.first { $0.id == request.id })
        try store.localSessions.removeReferences(attemptIDs: [siblingID])
        XCTAssertNotNil(store.localSessions.archive.snapshots.first { $0.attemptID == originID })
        XCTAssertTrue(store.localSessions.archive.deletedAdaptiveRunIDs?.contains(runtime.sessionID) == true)
        let after = try XCTUnwrap(store.localSessions.archive.sessions.first { $0.id == request.id })
        XCTAssertEqual(after.checkpoint, before.checkpoint)
        XCTAssertEqual(after.status, .migrationRecovery)
        XCTAssertNil(store.localSessions.archive.editorialExplanationPresentations?[originID.uuidString])
        let cold = try self.store(root, context: container.mainContext, admissions: admissions)
        XCTAssertNil(cold.localSessions.loadError)
        XCTAssertEqual(cold.localSessions.archive.sessions.first { $0.id == request.id }?.checkpoint, before.checkpoint)
    }
}


@MainActor
extension EditorialLiveControllerPersistenceTests {
    private func goalCatalog() throws -> NFEditorialAdmissionContext {
        let original = try mixedCatalog()
        let entries = original.entries.map { entry -> NFEditorialAdmissionEntry in
            var demand = entry.demand
            demand.goalAlignment = .init(objectiveID: demand.objectiveID, goalIDsRaw:
                [demand.objectiveID == "QA.mixed.objective.0" ? TrainingGoal.programming.rawValue : TrainingGoal.mentalMath.rawValue])
            return .init(id: entry.id, bankQuestionID: entry.bankQuestionID, exerciseDigest: entry.exerciseDigest,
                scorerVersion: entry.scorerVersion, lab: entry.lab, contentLocale: entry.contentLocale, demand: demand)
        }
        return .init(version: "QA.authored-goal-ranking.v1", entries: entries)
    }
    private func setGoalPreferences(_ goals: Set<TrainingGoal>, store: AppStore) throws {
        var draft = OnboardingDraft(); draft.goals = goals; draft.preferredLanguageCode = "en"
        try store.updateProfile(from: draft)
        XCTAssertEqual(store.profile?.goalsRaw, goals.map(\.rawValue).sorted().joined(separator: ","))
    }
    private func currentGoal(_ store: AppStore) throws -> NFEditorialGoalSelection {
        try XCTUnwrap(try receipt(store).editorialDecision?.goalSelection)
    }

    func testActualAuthoredGoalPreferenceRanksOnlyAfterMixedCoverageAndNeverRaisesInitialBand() throws {
        let root = try root(); defer { try? FileManager.default.removeItem(at: root) }
        let container = try container(root), admissions = try goalCatalog()
        let store = try store(root, context: container.mainContext, admissions: admissions)
        try setGoalPreferences([.programming], store: store)
        let runtime = try launchMixed(store); defer { runtime.releaseWriter() }
        let first = try receipt(store), goal = try currentGoal(store)
        XCTAssertEqual(runtime.request.ordinaryDelivery?.editorialPolicy?.controllerVersion, NFEditorialMixedController.goalVersion)
        XCTAssertEqual(goal.preferences.profileID, profileID); XCTAssertEqual(goal.preferences.goalIDsRaw, [TrainingGoal.programming.rawValue])
        XCTAssertEqual(goal.objectiveID, "QA.mixed.objective.0"); XCTAssertEqual(goal.preference, 1)
        XCTAssertEqual(first.editorialDecision?.selection.deliveredBand, .b1)
        XCTAssertTrue(first.editorialDecision?.evidence.independentObservationIDs.isEmpty == true)
        XCTAssertEqual(goal.exerciseDigest, try NFLocalItemCheckpoint.digest(runtime.exercise))
        XCTAssertEqual(first.mixedDecision?.rankedFamilies.first?.values.suffix(2).first, -1)
        try answer(runtime, store: store); runtime.next(store: store)
        XCTAssertNil(runtime.saveError)
        let second = try receipt(store)
        XCTAssertNotEqual(second.mixedDecision?.selectedScope, first.mixedDecision?.selectedScope)
        XCTAssertEqual(try currentGoal(store).preference, 0, "Unvisited family coverage precedes the preferred objective")
        XCTAssertEqual(try currentGoal(store).preferences, goal.preferences)
        XCTAssertEqual(store.localSessions.archive.selectionLedger?.slots.count, 2)
        XCTAssertEqual(store.attempts.count, 1)
    }

    func testActualGoalPreferenceIsFrozenAcrossProfileEditReplaceNextAndPersistentColdReplay() throws {
        let root = try root(); defer { try? FileManager.default.removeItem(at: root) }
        let admissions = try goalCatalog()
        var frozen: NFEditorialGoalPreferences!, expected: NFLocalAdaptiveItemReceipt!
        do {
            let container = try container(root, persistent: true)
            let store = try store(root, context: container.mainContext, admissions: admissions)
            try setGoalPreferences([.programming], store: store)
            let runtime = try launchMixed(store)
            frozen = try currentGoal(store).preferences
            try setGoalPreferences([.mentalMath], store: store)
            let original = try receipt(store)
            runtime.replaceCurrentItem(store: store)
            XCTAssertNil(runtime.saveError); XCTAssertNil(runtime.replacementUnavailableReason)
            XCTAssertNotEqual(try receipt(store).slotID, original.slotID)
            XCTAssertEqual(try currentGoal(store).preferences, frozen)
            XCTAssertEqual(try currentGoal(store).preference, 1)
            runtime.acknowledgePresented(); try answer(runtime, store: store); runtime.next(store: store)
            XCTAssertNil(runtime.saveError); XCTAssertEqual(try currentGoal(store).preferences, frozen)
            runtime.pause(); XCTAssertTrue(runtime.checkpointDraft(store: store)); runtime.releaseWriter()
            expected = try receipt(store)
        }
        let container = try container(root, persistent: true)
        let store = try store(root, context: container.mainContext, admissions: admissions)
        XCTAssertNil(store.localSessions.loadError); XCTAssertEqual(try receipt(store), expected)
        XCTAssertEqual(store.profile?.goalsRaw, TrainingGoal.mentalMath.rawValue)
        let saved = try XCTUnwrap(store.localSessions.archive.sessions.first)
        var request = saved.request; request.localCheckpoint = saved.checkpoint; request.localSessionID = saved.id
        let runtime = NFUniversalSessionRuntime(request: request)
        XCTAssertTrue(runtime.checkpointDraft(store: store)); runtime.resume(); runtime.acknowledgePresented()
        try answer(runtime, store: store); runtime.next(store: store)
        XCTAssertNil(runtime.saveError); XCTAssertEqual(try currentGoal(store).preferences, frozen)
        runtime.pause(); XCTAssertTrue(runtime.checkpointDraft(store: store)); runtime.releaseWriter()
        store.activeSessionRequest = nil
        let nextRun = try launchMixed(store); defer { nextRun.releaseWriter() }
        let newReceipt = try XCTUnwrap(store.localSessions.archive.adaptiveItemReceipts?.values.first {
            $0.sessionID == nextRun.sessionID && $0.effectiveDecisionOrdinal == 0
        })
        XCTAssertEqual(newReceipt.editorialDecision?.goalSelection?.preferences.goalIDsRaw, [TrainingGoal.mentalMath.rawValue])
        XCTAssertNotEqual(newReceipt.editorialDecision?.goalSelection?.preferences, frozen)
    }

    func testActualGoalSelectionRejectsStalePublicationAndForgedTraceBeforeConsumingAnotherSlot() throws {
        let root = try root(); defer { try? FileManager.default.removeItem(at: root) }
        let container = try container(root), admissions = try goalCatalog()
        let store = try store(root, context: container.mainContext, admissions: admissions)
        try setGoalPreferences([.programming], store: store)
        let runtime = try launchMixed(store); defer { runtime.releaseWriter() }
        try answer(runtime, store: store)
        let previous = try XCTUnwrap(store.localSessions.archive.sessions.first)
        let prepared = try store.prepareAdaptiveItem(request: previous.request, predecessor: previous.checkpoint,
            command: try runtime.sessionWriterCommand())
        runtime.pause(); XCTAssertTrue(runtime.checkpointDraft(store: store))
        let before = try Data(contentsOf: root.appending(path: "sessions-v1.json")), cursor = store.localSessions.archive.offlineRotationLedger
        XCTAssertThrowsError(try store.acceptAdaptiveItem(prepared, checkpoint: prepared.checkpoint))
        XCTAssertEqual(try Data(contentsOf: root.appending(path: "sessions-v1.json")), before)
        let current = try XCTUnwrap(store.localSessions.archive.sessions.first)
        let fresh = try store.prepareAdaptiveItem(request: current.request, predecessor: current.checkpoint,
            command: try runtime.sessionWriterCommand())
        var raw = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(fresh.receipt)) as? [String: Any])
        var decision = try XCTUnwrap(raw["editorialDecision"] as? [String: Any])
        var goal = try XCTUnwrap(decision["goalSelection"] as? [String: Any])
        var preferences = try XCTUnwrap(goal["preferences"] as? [String: Any])
        preferences["goalIDsRaw"] = [TrainingGoal.mentalMath.rawValue]
        goal["preferences"] = preferences
        goal["matchedGoalIDsRaw"] = [TrainingGoal.mentalMath.rawValue]
        decision["goalSelection"] = goal; raw["editorialDecision"] = decision
        let forged = try JSONDecoder().decode(NFLocalAdaptiveItemReceipt.self, from: JSONSerialization.data(withJSONObject: raw))
        XCTAssertTrue(forged.editorialDecision?.goalSelection?.isSupported == true,
            "A self-consistent preference trace still cannot replace the frozen launch preference")
        let altered = NFLocalAdaptiveItemPreparation(expectedArchiveRevision: fresh.expectedArchiveRevision,
            expectedRunRevision: fresh.expectedRunRevision, request: fresh.request, receipt: forged, checkpoint: fresh.checkpoint,
            replacementRotationLedger: fresh.replacementRotationLedger, importsLegacy: fresh.importsLegacy,
            legacySnapshot: fresh.legacySnapshot, replay: fresh.replay,
            overrideWriterAuthority: fresh.overrideWriterAuthority, sessionWriterCommand: fresh.sessionWriterCommand)
        XCTAssertThrowsError(try store.acceptAdaptiveItem(altered, checkpoint: altered.checkpoint)) { error in
            XCTAssertEqual(error as? NFLocalSessionRepository.RepositoryError, .staleRevision,
                "The changed goal trace must fail selection replay before checkpoint history validation")
        }
        XCTAssertEqual(store.localSessions.archive.offlineRotationLedger, cursor)
        XCTAssertEqual(try Data(contentsOf: root.appending(path: "sessions-v1.json")), before)
        // The actual Next caller carries acknowledged history into the selected
        // blank proposal. A bare preparation is not a complete next checkpoint.
        runtime.resume(); runtime.next(store: store)
        XCTAssertNil(runtime.saveError); XCTAssertEqual(runtime.index, 1)
        let accepted = try XCTUnwrap(store.localSessions.archive.sessions.first { $0.id == runtime.sessionID })
        XCTAssertEqual(try receipt(store), fresh.receipt)
        XCTAssertEqual(accepted.checkpoint.slotID, fresh.receipt.slotID)
        XCTAssertEqual(accepted.checkpoint.correctness, current.checkpoint.correctness)
        XCTAssertEqual(accepted.checkpoint.credits, current.checkpoint.credits)
        XCTAssertEqual(try NFEditorialCanonicalData.digest(store.acceptAdaptiveItem(fresh, checkpoint: fresh.checkpoint)),
            try NFEditorialCanonicalData.digest(accepted))
    }

    func testActualEmptyKnownGoalsAreZeroPreferenceAndLegacyPinsDoNotAcquireGoals() throws {
        let root = try root(); defer { try? FileManager.default.removeItem(at: root) }
        let container = try container(root), admissions = try goalCatalog()
        let store = try store(root, context: container.mainContext, admissions: admissions)
        try setGoalPreferences([], store: store)
        let runtime = try launchMixed(store)
        XCTAssertTrue(try currentGoal(store).preferences.isSupported)
        XCTAssertEqual(try currentGoal(store).preferences.goalIDsRaw, [])
        XCTAssertEqual(try currentGoal(store).preference, 0)
        runtime.pause(); XCTAssertTrue(runtime.checkpointDraft(store: store)); runtime.releaseWriter()
        var oldRequest = template()
        oldRequest.ordinaryDelivery = .init(strategy: .adaptiveItem, profileID: profileID, bank: NFOfflineQuestionBank.rotationBank)
        let oldPin = try XCTUnwrap(admissions.sessionPin(for: oldRequest))
        oldRequest.ordinaryDelivery?.editorialPolicy = oldPin
        XCTAssertEqual(oldRequest.ordinaryDelivery?.editorialPolicy?.controllerVersion, NFEditorialMixedController.version)
        let prepared = try store.prepareAdaptiveItem(request: oldRequest, predecessor: nil)
        XCTAssertNil(prepared.receipt.editorialDecision?.goalSelection)
        XCTAssertTrue(prepared.receipt.mixedDecision?.rankedFamilies.allSatisfy { $0.values[5] == 0 } == true)
        let accepted = try store.acceptAdaptiveItem(prepared, checkpoint: prepared.checkpoint)
        XCTAssertNil(accepted.request.ordinaryDelivery?.editorialPolicy?.goalPreferences)
    }

    func testFutureGoalPreferencePinIsRetainedReadOnlyWithoutRewritingExactQuestion() throws {
        let root = try root(); defer { try? FileManager.default.removeItem(at: root) }
        let container = try container(root), admissions = try goalCatalog()
        let store = try store(root, context: container.mainContext, admissions: admissions)
        try setGoalPreferences([.programming], store: store)
        let runtime = try launchMixed(store); runtime.pause()
        XCTAssertTrue(runtime.checkpointDraft(store: store)); runtime.releaseWriter()
        let url = root.appending(path: "sessions-v1.json")
        var archive = try JSONDecoder().decode(NFLocalSessionRepository.Archive.self, from: Data(contentsOf: url))
        let oldCheckpoint = try XCTUnwrap(archive.sessions.first?.checkpoint)
        archive.sessions[0].request.ordinaryDelivery?.editorialPolicy?.goalPreferences = .init(
            policyVersion: "ExplicitGoalPreferencesV999", profileID: profileID, goalIDsRaw: ["future-goal"])
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(archive).write(to: url, options: .atomic)
        let reopened = try self.store(root, context: container.mainContext, admissions: admissions)
        XCTAssertNil(reopened.localSessions.loadError)
        XCTAssertEqual(reopened.localSessions.archive.sessions.first?.status, .migrationRecovery)
        XCTAssertEqual(reopened.localSessions.archive.sessions.first?.checkpoint, oldCheckpoint)
        XCTAssertEqual(reopened.localSessions.archive.adaptiveItemReceipts, archive.adaptiveItemReceipts)
        let retained = try Data(contentsOf: url)
        XCTAssertThrowsError(try reopened.prepareAdaptiveItem(request: archive.sessions[0].request,
            predecessor: oldCheckpoint))
        XCTAssertEqual(try Data(contentsOf: url), retained)
    }
}


@MainActor
extension EditorialLiveControllerPersistenceTests {
    func testChangedAuthoredGoalManifestCannotContinueAnAcceptedRunAndUnknownProfileGoalsCannotLaunch() throws {
        let root = try root(); defer { try? FileManager.default.removeItem(at: root) }
        let container = try container(root), admissions = try goalCatalog()
        let store = try store(root, context: container.mainContext, admissions: admissions)
        try setGoalPreferences([.programming], store: store)
        let runtime = try launchMixed(store); runtime.pause()
        XCTAssertTrue(runtime.checkpointDraft(store: store)); runtime.releaseWriter()
        let saved = try XCTUnwrap(store.localSessions.archive.sessions.first)
        let changedEntries = admissions.entries.map { entry -> NFEditorialAdmissionEntry in
            var demand = entry.demand
            demand.goalAlignment = .init(objectiveID: demand.objectiveID, goalIDsRaw: [TrainingGoal.dataReasoning.rawValue])
            return .init(id: entry.id, bankQuestionID: entry.bankQuestionID, exerciseDigest: entry.exerciseDigest,
                scorerVersion: entry.scorerVersion, lab: entry.lab, contentLocale: entry.contentLocale, demand: demand)
        }
        let changed = NFEditorialAdmissionContext(version: admissions.version, entries: changedEntries)
        XCTAssertNotEqual(changed.fingerprint, admissions.fingerprint)
        let reopened = try self.store(root, context: container.mainContext, admissions: changed)
        XCTAssertNil(reopened.localSessions.loadError)
        let bytes = try Data(contentsOf: root.appending(path: "sessions-v1.json"))
        let writer = UUID()
        XCTAssertTrue(reopened.localSessions.claimWriter(writer, sessionID: saved.id, checkpoint: { true }))
        defer { reopened.localSessions.releaseWriter(writer) }
        let command = try reopened.localSessions.sessionCommand(
            authority: reopened.localSessions.writerAuthority(for: writer, sessionID: saved.id), sessionID: saved.id)
        XCTAssertThrowsError(try reopened.prepareAdaptiveReplacement(request: saved.request, predecessor: saved.checkpoint,
            command: command))
        XCTAssertEqual(try Data(contentsOf: root.appending(path: "sessions-v1.json")), bytes)
        XCTAssertEqual(reopened.localSessions.archive.sessions.first?.checkpoint.exercise, saved.checkpoint.exercise)
        // A raw future preference is retained in the core profile; no fallback
        // to a known goal may manufacture a new V5 launch.
        reopened.profile?.goalsRaw = "future-training-goal"; try container.mainContext.save()
        let beforeLaunch = try Data(contentsOf: root.appending(path: "sessions-v1.json"))
        XCTAssertFalse(reopened.beginSession(lab: .mentalMath, source: .focused, field: .general,
            targetDifficulty: 0.5, requestedItemCount: 10, seedOverride: seed,
            isTimed: false, timingCondition: .init(.untimed), launchLocaleIdentifier: "en"))
        XCTAssertEqual(try Data(contentsOf: root.appending(path: "sessions-v1.json")), beforeLaunch)
        XCTAssertEqual(reopened.profile?.goalsRaw, "future-training-goal")
        XCTAssertEqual(reopened.localSessions.archive.adaptiveItemReceipts, store.localSessions.archive.adaptiveItemReceipts)
        XCTAssertFalse(bytes.isEmpty)
    }
}

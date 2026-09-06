import Foundation
import SwiftData
import XCTest

@testable import NeuroForge

final class PersistenceRuntimeTests: XCTestCase {
    private enum InjectedCheckpointFailure: Error { case expected }
    private enum InjectedDocumentPolicyFailure: Error { case expected }

    @MainActor
    func testRecommendationRationaleSurvivesLaunchCheckpointAndReload() throws {
        let (store, container) = try makeStore()
        defer { _ = container }
        let rationale = "A review is due soon because this skill needs another retrieval."

        XCTAssertTrue(store.beginSession(
            lab: .retrieval,
            source: .focused,
            requestedMinutes: 6,
            evidenceClass: .practice,
            recommendationRationale: rationale,
            requestedItemCount: 5,
            planID: "progress.practice-next.v1",
            planBlockID: "progress.practice-next.v1.retrieval.reviewUrgency"
        ))
        let request = try XCTUnwrap(store.activeSessionRequest)
        XCTAssertEqual(request.recommendationRationale, rationale)

        try store.upsertCheckpoint(
            sessionID: request.id,
            request: request,
            currentIndex: 0,
            itemCount: 5,
            response: "",
            scratchpad: "",
            results: []
        )
        XCTAssertEqual(store.sessionCheckpoints.first?.recommendationRationale, rationale)

        let restored = AppStore(context: container.mainContext)
        XCTAssertEqual(restored.sessionCheckpoints.first?.recommendationRationale, rationale)
    }

    @MainActor
    func testDirtyNavigationDefersAndCancelsOrCompletesExactSettingsSubroute() throws {
        let (store, container) = try makeStore()
        defer { _ = container }
        let editorID = UUID()
        store.updateDirtyEditor(id: editorID, title: "Draft editor", isDirty: true)

        store.requestSettingsSubroute(.export)
        XCTAssertEqual(store.selectedDestination, .today)
        XCTAssertEqual(store.pendingDestinationAfterDirtyEditor, .settings)
        XCTAssertEqual(store.pendingSettingsSubroute, .export)

        store.cancelPendingDestinationChange()
        XCTAssertEqual(store.selectedDestination, .today)
        XCTAssertNil(store.pendingDestinationAfterDirtyEditor)
        XCTAssertNil(store.pendingSettingsSubroute, "A cancelled command must not reopen later")

        store.requestSettingsSubroute(.methodology)
        store.discardDirtyEditorAndNavigate()
        XCTAssertEqual(store.selectedDestination, .settings)
        XCTAssertEqual(store.lastDiscardedDirtyEditorID, editorID)
        XCTAssertEqual(store.pendingSettingsSubroute, .methodology)
        XCTAssertTrue(store.dirtyEditorWasDiscarded(id: editorID))

        store.acknowledgeSettingsSubroute(.export)
        XCTAssertEqual(store.pendingSettingsSubroute, .methodology, "Only the matching receiver may consume the route")
        store.acknowledgeSettingsSubroute(.methodology)
        XCTAssertNil(store.pendingSettingsSubroute)
    }

    @MainActor
    func testDirtyNavigationDefersExactSourceRouteAtomicallyAtSameDestinationAndCancellationDropsIt() throws {
        let (store, container) = try makeStore()
        defer { _ = container }
        let editorID = UUID()
        let documentID = UUID()
        store.selectedDestination = .library
        store.updateDirtyEditor(id: editorID, title: "Source response", isDirty: true)

        let route = NFExternalRoute.source(NFSourceDeepLinkDestination(
            documentID: documentID,
            chunkID: "chunk.exact"
        ))
        NFExternalRouteRouter.apply(route, to: store)

        XCTAssertEqual(store.selectedDestination, .library)
        XCTAssertEqual(store.pendingDestinationAfterDirtyEditor, .library)
        XCTAssertEqual(store.pendingExternalRouteAfterDirtyEditor, route)
        XCTAssertFalse(store.shouldOpenSourceReviews)
        XCTAssertNil(store.requestedLibraryDocumentID)
        XCTAssertNil(store.requestedSourceChunkID)
        XCTAssertNil(store.requestedSourceReviewID)

        store.cancelPendingDestinationChange()

        XCTAssertEqual(store.selectedDestination, .library)
        XCTAssertNil(store.pendingDestinationAfterDirtyEditor)
        XCTAssertNil(store.pendingExternalRouteAfterDirtyEditor)
        XCTAssertFalse(store.shouldOpenSourceReviews)
        XCTAssertNil(store.requestedLibraryDocumentID)
        XCTAssertNil(store.requestedSourceChunkID)
        XCTAssertNil(store.requestedSourceReviewID)
        XCTAssertEqual(store.activeDirtyEditor?.id, editorID)
    }

    @MainActor
    func testDirtyNavigationCommitsExactSourceReviewOnlyAfterExplicitDiscard() throws {
        let (store, container) = try makeStore()
        defer { _ = container }
        let editorID = UUID()
        let documentID = UUID()
        let reviewID = UUID()
        let destination = try XCTUnwrap(NFSourceReviewDeepLinkDestination(
            documentID: documentID,
            chunkID: "chunk.review",
            reviewID: reviewID
        ))
        let route = NFExternalRoute.sourceReviews(destination)
        store.selectedDestination = .library
        store.updateDirtyEditor(id: editorID, title: "Source response", isDirty: true)

        NFExternalRouteRouter.apply(route, to: store)

        XCTAssertEqual(store.pendingExternalRouteAfterDirtyEditor, route)
        XCTAssertFalse(store.shouldOpenSourceReviews)
        XCTAssertNil(store.requestedLibraryDocumentID)

        store.discardDirtyEditorAndNavigate()

        XCTAssertNil(store.activeDirtyEditor)
        XCTAssertEqual(store.lastDiscardedDirtyEditorID, editorID)
        XCTAssertNil(store.pendingDestinationAfterDirtyEditor)
        XCTAssertNil(store.pendingExternalRouteAfterDirtyEditor)
        XCTAssertEqual(store.selectedDestination, .library)
        XCTAssertTrue(store.shouldOpenSourceReviews)
        XCTAssertEqual(store.requestedLibraryDocumentID, documentID)
        XCTAssertEqual(store.requestedSourceChunkID, "chunk.review")
        XCTAssertEqual(store.requestedSourceReviewID, reviewID)
    }

    @MainActor
    func testDirtyNavigationDefersTodayReviewPayloadUntilEditorSave() throws {
        let (store, container) = try makeStore()
        defer { _ = container }
        let editorID = UUID()
        store.updateDirtyEditor(id: editorID, title: "Draft editor", isDirty: true)

        NFExternalRouteRouter.apply(.completedTodayReview, to: store)

        XCTAssertEqual(store.selectedDestination, .today)
        XCTAssertEqual(store.pendingDestinationAfterDirtyEditor, .today)
        XCTAssertEqual(store.pendingExternalRouteAfterDirtyEditor, .completedTodayReview)
        XCTAssertFalse(store.shouldOpenTodayPlan)
        XCTAssertFalse(store.shouldOpenCompletedTodayReview)

        store.clearDirtyEditor(id: editorID)

        XCTAssertNil(store.activeDirtyEditor)
        XCTAssertNil(store.pendingExternalRouteAfterDirtyEditor)
        XCTAssertTrue(store.shouldOpenTodayPlan)
        XCTAssertTrue(store.shouldOpenCompletedTodayReview)
    }

    @MainActor
    func testDirtyInternalNavigationIntentsAreAtomicAndCancellationDropsEveryPayload() throws {
        let (store, container) = try makeStore()
        defer { _ = container }
        let editorID = UUID()
        store.updateDirtyEditor(id: editorID, title: "Draft editor", isDirty: true)

        store.requestTodayPlan()
        XCTAssertEqual(store.pendingAppIntentAfterDirtyEditor, .todayPlan)
        XCTAssertEqual(store.pendingDestinationAfterDirtyEditor, .today)
        XCTAssertFalse(store.shouldOpenTodayPlan)
        store.cancelPendingDestinationChange()
        XCTAssertNil(store.pendingAppIntentAfterDirtyEditor)
        XCTAssertFalse(store.shouldOpenTodayPlan)

        store.requestSourceReviews()
        XCTAssertEqual(store.pendingAppIntentAfterDirtyEditor, .sourceReviews)
        XCTAssertEqual(store.pendingDestinationAfterDirtyEditor, .library)
        XCTAssertFalse(store.shouldOpenSourceReviews)
        XCTAssertNil(store.requestedLibraryDocumentID)
        store.cancelPendingDestinationChange()
        XCTAssertNil(store.pendingAppIntentAfterDirtyEditor)
        XCTAssertFalse(store.shouldOpenSourceReviews)

        store.requestDocumentImport()
        XCTAssertEqual(store.pendingAppIntentAfterDirtyEditor, .documentImport)
        XCTAssertEqual(store.pendingDestinationAfterDirtyEditor, .library)
        XCTAssertFalse(store.shouldPresentDocumentImporter)
        store.cancelPendingDestinationChange()
        XCTAssertNil(store.pendingAppIntentAfterDirtyEditor)
        XCTAssertFalse(store.shouldPresentDocumentImporter)

        store.requestSourceReviewDocumentImport()
        XCTAssertEqual(store.pendingAppIntentAfterDirtyEditor, .sourceReviewDocumentImport)
        XCTAssertEqual(store.pendingDestinationAfterDirtyEditor, .library)
        XCTAssertFalse(store.shouldPresentDocumentImporter)
        XCTAssertFalse(store.shouldOpenSourceReviews)
        store.cancelPendingDestinationChange()
        XCTAssertNil(store.pendingAppIntentAfterDirtyEditor)
        XCTAssertFalse(store.shouldPresentDocumentImporter)
        XCTAssertFalse(store.shouldOpenSourceReviews)
        XCTAssertEqual(store.activeDirtyEditor?.id, editorID)
    }

    @MainActor
    func testDirtyInternalNavigationIntentCommitsAfterSaveOrExplicitDiscard() throws {
        let (savedStore, savedContainer) = try makeStore()
        defer { _ = savedContainer }
        let savedEditorID = UUID()
        savedStore.updateDirtyEditor(id: savedEditorID, title: "Saved draft", isDirty: true)
        savedStore.requestSourceReviews()

        XCTAssertFalse(savedStore.shouldOpenSourceReviews)
        savedStore.clearDirtyEditor(id: savedEditorID)
        XCTAssertNil(savedStore.pendingAppIntentAfterDirtyEditor)
        XCTAssertEqual(savedStore.selectedDestination, .library)
        XCTAssertTrue(savedStore.shouldOpenSourceReviews)

        let (discardedStore, discardedContainer) = try makeStore()
        defer { _ = discardedContainer }
        let discardedEditorID = UUID()
        discardedStore.updateDirtyEditor(id: discardedEditorID, title: "Discarded draft", isDirty: true)
        discardedStore.requestDocumentImport()

        XCTAssertFalse(discardedStore.shouldPresentDocumentImporter)
        discardedStore.discardDirtyEditorAndNavigate()
        XCTAssertNil(discardedStore.activeDirtyEditor)
        XCTAssertEqual(discardedStore.lastDiscardedDirtyEditorID, discardedEditorID)
        XCTAssertEqual(discardedStore.selectedDestination, .library)
        XCTAssertTrue(discardedStore.shouldPresentDocumentImporter)

        let (handoffStore, handoffContainer) = try makeStore()
        defer { _ = handoffContainer }
        let handoffEditorID = UUID()
        handoffStore.updateDirtyEditor(id: handoffEditorID, title: "Retrieval draft", isDirty: true)
        handoffStore.requestSourceReviewDocumentImport()

        XCTAssertFalse(handoffStore.shouldPresentDocumentImporter)
        XCTAssertFalse(handoffStore.shouldOpenSourceReviews)
        handoffStore.clearDirtyEditor(id: handoffEditorID)
        XCTAssertNil(handoffStore.pendingAppIntentAfterDirtyEditor)
        XCTAssertEqual(handoffStore.selectedDestination, .library)
        XCTAssertTrue(handoffStore.shouldPresentDocumentImporter)
        XCTAssertTrue(handoffStore.shouldOpenSourceReviews)
    }

    @MainActor
    func testDirtyMentalMathCommandAndQuestionWriterCallbackWaitForResolution() throws {
        let (commandStore, commandContainer) = try makeStore()
        defer { _ = commandContainer }
        let commandEditorID = UUID()
        commandStore.updateDirtyEditor(id: commandEditorID, title: "Command draft", isDirty: true)

        XCTAssertTrue(commandStore.requestFocusedMentalMathPractice(
            requestedMinutes: 7,
            preferredMentalMathKind: .scientificNotation
        ))
        XCTAssertNil(commandStore.activeSessionRequest)
        XCTAssertEqual(
            commandStore.pendingAppIntentAfterDirtyEditor,
            .mentalMathPractice(requestedMinutes: 7, preferredKind: .scientificNotation)
        )
        commandStore.cancelPendingDestinationChange()
        XCTAssertNil(commandStore.activeSessionRequest)
        XCTAssertNil(commandStore.pendingAppIntentAfterDirtyEditor)

        XCTAssertTrue(commandStore.requestFocusedMentalMathPractice(
            requestedMinutes: 7,
            preferredMentalMathKind: .scientificNotation
        ))
        commandStore.discardDirtyEditorAndNavigate()
        XCTAssertEqual(commandStore.activeSessionRequest?.lab, .mentalMath)
        XCTAssertEqual(commandStore.activeSessionRequest?.requestedMinutes, 7)
        XCTAssertEqual(commandStore.activeSessionRequest?.preferredMentalMathKind, .scientificNotation)

        let (callbackStore, callbackContainer) = try makeStore()
        defer { _ = callbackContainer }
        let callbackEditorID = UUID()
        callbackStore.updateDirtyEditor(id: callbackEditorID, title: "Callback draft", isDirty: true)
        callbackStore.requestAIStudioForPendingShortcutCallback()

        XCTAssertEqual(callbackStore.pendingAppIntentAfterDirtyEditor, .questionWriterCallback)
        XCTAssertFalse(callbackStore.shouldOpenAIStudio)
        callbackStore.clearDirtyEditor(id: callbackEditorID)
        XCTAssertEqual(callbackStore.selectedDestination, .train)
        XCTAssertTrue(callbackStore.shouldOpenAIStudio)
        XCTAssertNil(callbackStore.pendingAppIntentAfterDirtyEditor)
    }

    @MainActor
    func testDocumentPolicyFailureRollsBackUIAuthorityAndPreservesPriorConsent() throws {
        let (store, container) = try makeStore()
        let document = SourceDocumentRecord(
            filename: "policy.txt",
            typeIdentifier: "public.plain-text",
            sizeBytes: 12,
            localPath: "/tmp/policy.txt"
        )
        document.aiPolicyRaw = DocumentAIPolicy.privateCloudAllowed.rawValue
        document.pccExcerptConsentPolicyVersion = 3
        document.pccExcerptConsentDocumentIDRaw = document.id.uuidString
        document.pccExcerptConsentedAt = Date(timeIntervalSince1970: 1_788_000_000)
        document.syncPolicy = NFDocumentSyncPolicy.localOnly.rawValue
        container.mainContext.insert(document)
        try container.mainContext.save()
        store.reload()

        let aiCommitted = store.updateDocumentAIPolicy(
            try XCTUnwrap(store.documents.first { $0.id == document.id }),
            policy: .noAI,
            persist: { throw InjectedDocumentPolicyFailure.expected }
        )
        XCTAssertFalse(aiCommitted)
        let afterAIFailure = try XCTUnwrap(store.documents.first { $0.id == document.id })
        XCTAssertEqual(afterAIFailure.aiPolicyRaw, DocumentAIPolicy.privateCloudAllowed.rawValue)
        XCTAssertEqual(afterAIFailure.pccExcerptConsentPolicyVersion, 3)
        XCTAssertEqual(afterAIFailure.pccExcerptConsentDocumentIDRaw, document.id.uuidString)
        XCTAssertNotNil(afterAIFailure.pccExcerptConsentedAt)
        XCTAssertNotNil(store.lastErrorMessage)

        let syncCommitted = store.updateDocumentSyncPolicy(
            afterAIFailure,
            policy: .privateOriginal,
            persist: { throw InjectedDocumentPolicyFailure.expected }
        )
        XCTAssertFalse(syncCommitted)
        XCTAssertEqual(
            try XCTUnwrap(store.documents.first { $0.id == document.id }).syncPolicy,
            NFDocumentSyncPolicy.localOnly.rawValue
        )

        XCTAssertTrue(store.updateDocumentSyncPolicy(
            try XCTUnwrap(store.documents.first { $0.id == document.id }),
            policy: .privateOriginal
        ))
        XCTAssertEqual(
            try XCTUnwrap(store.documents.first { $0.id == document.id }).syncPolicy,
            NFDocumentSyncPolicy.privateOriginal.rawValue
        )
    }

    func testDocumentPolicyMutationGateRejectsOverlappingOrMismatchedMutations() throws {
        let idle = NFDocumentPolicyMutationGate()
        let savingPrivacy = try XCTUnwrap(idle.beginning(.questionPrivacy))
        XCTAssertNil(savingPrivacy.beginning(.questionPrivacy))
        XCTAssertNil(savingPrivacy.beginning(.iCloudSync))
        XCTAssertEqual(
            savingPrivacy.finishing(.iCloudSync).activeMutation,
            .questionPrivacy,
            "A stale completion must not release another mutation's lock"
        )
        XCTAssertNil(savingPrivacy.finishing(.questionPrivacy).activeMutation)

        let savingSync = try XCTUnwrap(
            savingPrivacy.finishing(.questionPrivacy).beginning(.iCloudSync)
        )
        XCTAssertEqual(savingSync.activeMutation, .iCloudSync)
        XCTAssertNil(savingSync.beginning(.questionPrivacy))
    }

    @MainActor
    func testCompletedCheckpointCannotBeReopenedByAStaleIncompleteUpsert() throws {
        let (store, container) = try makeStore()
        defer { _ = container }
        let sessionID = UUID()
        let planID = "monotonic-completion-plan"
        let blockID = "monotonic-completion-block"
        let request = SessionRequest(
            lab: .logicDebugging,
            source: .today,
            seed: 0xC0A1_1E7E,
            evidenceClass: .practice,
            planID: planID,
            planBlockID: blockID
        )

        try store.upsertCheckpoint(
            sessionID: sessionID,
            request: request,
            currentIndex: 1,
            itemCount: 1,
            response: "answered",
            scratchpad: "",
            results: [true],
            credits: [1],
            hasCommittedCurrentItem: true,
            isComplete: true
        )
        XCTAssertTrue(try XCTUnwrap(
            store.sessionCheckpoints.first { $0.sessionID == sessionID }
        ).isComplete)
        XCTAssertEqual(store.completedPlanBlockIDs(planID: planID), [blockID])

        try store.upsertCheckpoint(
            sessionID: sessionID,
            request: request,
            currentIndex: 0,
            itemCount: 1,
            response: "stale draft",
            scratchpad: "",
            results: [],
            isComplete: false
        )

        let checkpoint = try XCTUnwrap(
            store.sessionCheckpoints.first { $0.sessionID == sessionID }
        )
        XCTAssertTrue(checkpoint.isComplete)
        XCTAssertEqual(store.completedPlanBlockIDs(planID: planID), [blockID])

        let restored = AppStore(context: container.mainContext)
        XCTAssertTrue(try XCTUnwrap(
            restored.sessionCheckpoints.first { $0.sessionID == sessionID }
        ).isComplete)
        XCTAssertEqual(restored.completedPlanBlockIDs(planID: planID), [blockID])
    }

    @MainActor
    func testFinishingSessionPreservesScratchpadForCompletedChapterReview() throws {
        let (store, container) = try makeStore()
        defer { _ = container }
        let sessionID = UUID()
        let request = SessionRequest(
            lab: .logicDebugging,
            source: .today,
            seed: 0x5C2A_7C4,
            requestedItemCount: 1,
            startingIndex: 1,
            planID: "scratchpad-review-plan",
            planBlockID: "scratchpad-review-block",
            resumeSessionID: sessionID,
            resumedResults: [true],
            resumedCredits: [1],
            resumeCurrentItemWasCommitted: true
        )
        let runtime = NFUniversalSessionRuntime(request: request)
        runtime.scratchpad = "Keep this completed reasoning note."

        runtime.finish(store: store)

        let checkpoint = try XCTUnwrap(
            store.sessionCheckpoints.first { $0.sessionID == sessionID }
        )
        XCTAssertTrue(checkpoint.isComplete)
        XCTAssertEqual(checkpoint.scratchpad, "Keep this completed reasoning note.")
    }

    @MainActor
    func testScratchpadPayloadRemainsChapterScopedAcrossItemsAndCompletion() throws {
        let (store, container) = try makeStore()
        defer { _ = container }
        let payload = NFScratchpadPayload(
            notes: "Reasoning across both items",
            drawingData: Data([0xCA, 0xFE])
        ).storedValue
        let request = SessionRequest(
            lab: .logicDebugging,
            source: .today,
            seed: 0xC4A9_7E2,
            evidenceClass: .practice,
            requestedItemCount: 2,
            planID: "scratchpad-two-item-plan",
            planBlockID: "scratchpad-two-item-block"
        )
        let runtime = NFUniversalSessionRuntime(request: request)
        runtime.scratchpad = payload

        fillResponse(in: runtime)
        runtime.submitResponse()
        runtime.commit(confidence: .uncertain, store: store)
        finishSelfCheckComparisonIfNeeded(runtime, store: store)
        XCTAssertEqual(runtime.stage, .feedback)
        runtime.next(store: store)

        XCTAssertEqual(runtime.stage, .item)
        XCTAssertEqual(runtime.scratchpad, payload)
        runtime.skip(store: store)
        XCTAssertEqual(runtime.stage, .summary)
        XCTAssertTrue(runtime.finish(store: store))

        let checkpoint = try XCTUnwrap(
            store.sessionCheckpoints.first { $0.sessionID == runtime.sessionID }
        )
        XCTAssertTrue(checkpoint.isComplete)
        XCTAssertEqual(NFScratchpadPayload.decode(checkpoint.scratchpad), NFScratchpadPayload.decode(payload))
    }

    @MainActor
    func testOptionalReflectionDraftSurvivesExactCheckpointReloadAndClearsAfterSave() throws {
        let (store, container) = try makeStore()
        defer { _ = container }
        let planID = "reflection-recovery-plan"
        let blockID = "reflection-recovery-block"
        let itemCount = 2

        let runtime = try XCTUnwrap((0..<128).lazy.map { seed in
            NFUniversalSessionRuntime(request: SessionRequest(
                lab: .mentalMath,
                source: .today,
                seed: UInt64(seed),
                evidenceClass: .practice,
                requestedItemCount: itemCount,
                planID: planID,
                planBlockID: blockID
            ))
        }.first { runtime in
            if case .numeric = runtime.exercise.interaction { return true }
            return false
        })
        guard case let .numeric(schema) = runtime.exercise.interaction else {
            return XCTFail("Expected a numeric exercise selected by the test search")
        }
        runtime.numericValue = String(schema.answer.value + 1)
        runtime.numericUnit = schema.answer.canonicalUnit ?? ""
        XCTAssertTrue(runtime.canSubmit)
        runtime.submitResponse()
        runtime.commit(confidence: .certain, store: store)

        XCTAssertEqual(runtime.stage, .feedback)
        runtime.reflect()
        XCTAssertEqual(runtime.stage, .reflection)
        XCTAssertEqual(store.attempts.count, 1)
        runtime.selectedReflectionCode = .inputError
        runtime.reflectionNote = "I entered the adjacent value."
        XCTAssertTrue(runtime.checkpointDraft(store: store))

        let saved = try XCTUnwrap(store.sessionCheckpoints.first { $0.planBlockID == blockID })
        XCTAssertEqual(saved.pendingReflectionAttemptID, store.attempts.first?.id)
        XCTAssertEqual(saved.reflectionTriggerRaw, NFAttemptReflectionTrigger.highConfidenceError.rawValue)
        XCTAssertEqual(saved.selectedReflectionCodeRaw, NFErrorReflectionCode.inputError.rawValue)
        XCTAssertEqual(saved.reflectionNote, "I entered the adjacent value.")

        runtime.releaseWriter()
        let restoredStore = AppStore(context: container.mainContext, localSessionRepository: store.localSessions)
        XCTAssertTrue(restoredStore.resumeSession(runtime.sessionID))
        let resumedRequest = try XCTUnwrap(restoredStore.activeSessionRequest)
        XCTAssertEqual(resumedRequest.localCheckpoint?.index, 0)

        let resumed = NFUniversalSessionRuntime(request: resumedRequest)
        XCTAssertEqual(resumed.stage, .reflection)
        XCTAssertEqual(resumed.selectedReflectionCode, .inputError)
        XCTAssertEqual(resumed.reflectionNote, "I entered the adjacent value.")
        XCTAssertFalse(resumed.lastResult?.isCorrect ?? true)
        resumed.saveReflection(store: restoredStore)

        XCTAssertEqual(resumed.stage, .feedback)
        XCTAssertEqual(restoredStore.attemptReflections.count, 1)
        let cleared = try XCTUnwrap(
            restoredStore.sessionCheckpoints.first { $0.sessionID == resumed.sessionID }
        )
        XCTAssertNil(cleared.pendingReflectionAttemptID)
        XCTAssertNil(cleared.reflectionTriggerRaw)
        XCTAssertNil(cleared.selectedReflectionCodeRaw)
        XCTAssertNil(cleared.reflectionNote)
    }

    @MainActor
    func testInjectedCheckpointFailurePreservesEveryEditableSessionStage() throws {
        let (store, container) = try makeStore()
        defer { _ = container }

        let item = NFUniversalSessionRuntime(request: SessionRequest(
            lab: .logicDebugging,
            source: .focused,
            seed: 700,
            requestedItemCount: 1
        ))
        assertInjectedCheckpointFailure(item, expectedStage: .item)

        let confidence = NFUniversalSessionRuntime(request: SessionRequest(
            lab: .logicDebugging,
            source: .focused,
            seed: 701,
            requestedItemCount: 1
        ))
        fillResponse(in: confidence)
        confidence.submitResponse()
        assertInjectedCheckpointFailure(confidence, expectedStage: .confidence)

        let selfCheck = NFUniversalSessionRuntime(request: SessionRequest(
            lab: .retrieval,
            source: .focused,
            seed: 702,
            requestedItemCount: 1,
            mechanicID: "retrieval.fallback-variant-0"
        ))
        guard case let .selfCheck(schema) = selfCheck.exercise.interaction else {
            return XCTFail("Expected the forced self-check mechanic")
        }
        selfCheck.selfCheckReflection = schema.referenceAnswer
        selfCheck.submitResponse()
        selfCheck.commit(confidence: .uncertain, store: store)
        assertInjectedCheckpointFailure(selfCheck, expectedStage: .selfCheckComparison)

        let reflection = try XCTUnwrap((0..<128).lazy.map { seed in
            NFUniversalSessionRuntime(request: SessionRequest(
                lab: .mentalMath,
                source: .focused,
                seed: UInt64(800 + seed),
                requestedItemCount: 1
            ))
        }.first { runtime in
            if case .numeric = runtime.exercise.interaction { return true }
            return false
        })
        guard case let .numeric(schema) = reflection.exercise.interaction else {
            return XCTFail("Expected a numeric exercise selected by the test search")
        }
        reflection.numericValue = String(schema.answer.value + 1)
        reflection.numericUnit = schema.answer.canonicalUnit ?? ""
        reflection.submitResponse()
        reflection.commit(confidence: .certain, store: store)
        reflection.reflect()
        assertInjectedCheckpointFailure(reflection, expectedStage: .reflection)

        let feedback = NFUniversalSessionRuntime(request: SessionRequest(
            lab: .logicDebugging,
            source: .focused,
            seed: 703,
            requestedItemCount: 1
        ))
        fillResponse(in: feedback)
        feedback.submitResponse()
        feedback.commit(confidence: .uncertain, store: store)
        finishSelfCheckComparisonIfNeeded(feedback, store: store)
        XCTAssertEqual(feedback.stage, .feedback)
        assertInjectedCheckpointFailure(feedback, expectedStage: .feedback)
        feedback.next(store: store)
        assertInjectedCheckpointFailure(feedback, expectedStage: .summary)
    }

    @MainActor
    func testBaselineResultsExcludeLaterPracticeEvidence() throws {
        let (store, container) = try makeStore()
        defer { _ = container }
        let dimension = NFAssessmentDimension.quantitativeEstimation
        for index in 0..<NFAssessmentCatalog.minimumBaselineItemsPerDimension {
            let record = AttemptRecord(
                sessionID: UUID(),
                lab: dimension.lab,
                itemID: "baseline-isolated-\(index)",
                prompt: "Protected baseline item",
                response: "supported",
                correctAnswer: "supported",
                isCorrect: true,
                confidence: .fairlyConfident,
                evidenceClass: .assessmentHoldout,
                source: .baseline
            )
            record.skillID = dimension.skillID
            record.skillWeightsRaw = encodedSkillWeights([dimension.skillID: 1.0])
            record.assessmentBlockRaw = dimension.block.rawValue
            record.assessmentDescriptorID = "baseline-estimation-\(index)"
            record.assessmentFormatRaw = index.isMultiple(of: 2)
                ? NFAssessmentItemFormat.numericEntry.rawValue
                : NFAssessmentItemFormat.singleChoice.rawValue
            record.deterministicCredit = 1
            container.mainContext.insert(record)
        }
        try container.mainContext.save()
        store.reload()
        try store.saveLabAttempt(
            lab: .quantitative,
            itemID: "later-practice",
            prompt: "Later practice item",
            response: "incorrect",
            correctAnswer: "supported",
            isCorrect: false,
            confidence: .uncertain,
            evidenceClass: .practice,
            source: .focused
        )

        let baseline = try XCTUnwrap(store.baselineDimensionSummaries.first(where: {
            $0.id == dimension.skillID
        }))
        let ongoing = try XCTUnwrap(store.skillSummaries.first(where: { $0.lab == .quantitative }))
        XCTAssertEqual(baseline.evidenceCount, 0)
        XCTAssertNil(baseline.accuracy)
        XCTAssertEqual(baseline.status, .unassessed)
        XCTAssertEqual(ongoing.evidenceCount, 0)
        XCTAssertNil(ongoing.accuracy)
        let protectedHistory = try XCTUnwrap(NFHistoricalPracticeProjection.reduce(
            attempts: store.attempts.filter { $0.evidenceClassRaw == EvidenceClass.assessmentHoldout.rawValue }.map(\.dto)).first)
        XCTAssertEqual(protectedHistory.legacyCount, 8)
        XCTAssertEqual(protectedHistory.legacyMeanCredit, 1)
        let allHistory = try XCTUnwrap(NFHistoricalPracticeProjection.reduce(attempts: store.attempts.map(\.dto)).first)
        XCTAssertEqual(allHistory.legacyCount, 9)
        XCTAssertEqual(try XCTUnwrap(allHistory.legacyMeanCredit), 8.0 / 9.0, accuracy: 0.000_001)
    }

    @MainActor
    func testRuntimeOnlyReopensResponsesWhenExercisePolicyAllowsIt() throws {
        var locked: NFUniversalSessionRuntime?
        var editable: NFUniversalSessionRuntime?
        for seed in 0..<256 where locked == nil || editable == nil {
            let candidate = NFUniversalSessionRuntime(request: SessionRequest(
                lab: .logicDebugging,
                source: .focused,
                seed: UInt64(seed),
                evidenceClass: .practice
            ))
            switch candidate.exercise.responseEditPolicy {
            case .lockedAfterSubmit where locked == nil: locked = candidate
            case .editableBeforeCommit where editable == nil: editable = candidate
            default: break
            }
        }

        let fixed = try XCTUnwrap(locked)
        fillResponse(in: fixed)
        fixed.submitResponse()
        XCTAssertEqual(fixed.stage, .confidence)
        fixed.editResponse()
        XCTAssertEqual(fixed.stage, .confidence)
        XCTAssertEqual(fixed.revisionCount, 0)

        let revisable = try XCTUnwrap(editable)
        fillResponse(in: revisable)
        revisable.submitResponse()
        revisable.editResponse()
        XCTAssertEqual(revisable.stage, .item)
        XCTAssertEqual(revisable.revisionCount, 1)
    }

    @MainActor
    func testDueReassessmentDeferralRuntimeSelectiveEvidenceAndCompletionAreDurable() throws {
        let (initialStore, container) = try makeStore()
        defer { _ = initialStore }
        let calendar = Calendar(identifier: .gregorian)
        let now = Date()
        let anchor = calendar.startOfDay(for: now.addingTimeInterval(-45 * 86_400))

        let baselineSession = NFAssessmentEngine.makeBlockSession(
            block: .logicMetacognition,
            phase: .initialBaseline,
            profileSeed: 71
        )
        for (index, descriptor) in baselineSession.items.enumerated() {
            let attempt = AttemptRecord(
                sessionID: UUID(), lab: descriptor.lab, itemID: "baseline-logic-\(index)",
                prompt: "Protected baseline fixture", response: "correct", correctAnswer: "correct",
                isCorrect: true, confidence: .fairlyConfident,
                evidenceClass: .assessmentHoldout, source: .baseline
            )
            attempt.submittedAt = anchor
            attempt.assessmentBlockRaw = NFAssessmentBlockKind.logicMetacognition.rawValue
            attempt.assessmentDescriptorID = descriptor.id
            attempt.assessmentTemplateFamily = descriptor.templateFamily
            attempt.assessmentFormatRaw = descriptor.format.rawValue
            attempt.assessmentSubskillID = descriptor.subskillID
            attempt.skillID = descriptor.skillID
            attempt.skillWeightsRaw = encodedSkillWeights([descriptor.skillID: 1.0])
            attempt.deterministicCredit = 1
            container.mainContext.insert(attempt)
        }
        let baselineCheckpoint = SessionCheckpointRecord(
            sessionID: UUID(), lab: .logicDebugging, source: .baseline, seed: 71,
            currentIndex: baselineSession.minimumScorableItems - 1,
            itemCount: baselineSession.itemCap,
            response: "", scratchpad: "",
            results: Array(repeating: true, count: baselineSession.minimumScorableItems), evidenceClass: .assessmentHoldout,
            assessmentBlock: .logicMetacognition, hasCommittedCurrentItem: true, isComplete: true
        )
        baselineCheckpoint.updatedAt = anchor
        container.mainContext.insert(baselineCheckpoint)

        for day in 1...28 {
            let activeAttempt = AttemptRecord(
                sessionID: UUID(), lab: .mentalMath, itemID: "active-day-\(day)",
                prompt: "Ordinary daily practice", response: "1", correctAnswer: "1",
                isCorrect: true, confidence: .fairlyConfident, evidenceClass: .practice, source: .focused
            )
            activeAttempt.submittedAt = calendar.date(byAdding: .day, value: day, to: anchor)!
            activeAttempt.deterministicCredit = 1
            container.mainContext.insert(activeAttempt)
        }
        try container.mainContext.save()

        let store = AppStore(context: container.mainContext)
        let due = try XCTUnwrap(store.reassessmentStatus(at: now, calendar: calendar))
        XCTAssertTrue(due.isDue)
        XCTAssertEqual(due.cycle, 1)
        XCTAssertEqual(due.block, .logicMetacognition)
        XCTAssertEqual(due.activeDaysCompleted, 28)
        XCTAssertNotNil(store.reassessmentStateRecord?.dueAt)

        let attemptCount = store.attempts.count
        let checkpointCount = store.sessionCheckpoints.count
        let deferredAt = now.addingTimeInterval(-8 * 86_400)
        store.deferDueReassessment(at: deferredAt, calendar: calendar)
        let deferredUntil = try XCTUnwrap(store.reassessmentStateRecord?.deferredUntil)
        XCTAssertEqual(deferredUntil.timeIntervalSince(deferredAt), 7 * 86_400, accuracy: 0.001)
        XCTAssertEqual(store.attempts.count, attemptCount)
        XCTAssertEqual(store.sessionCheckpoints.count, checkpointCount)

        let reloaded = AppStore(context: container.mainContext)
        XCTAssertEqual(reloaded.reassessmentStateRecord?.deferredUntil, deferredUntil)
        let availableAgain = try XCTUnwrap(reloaded.reassessmentStatus(at: now, calendar: calendar))
        XCTAssertTrue(availableAgain.isDue)
        XCTAssertFalse(availableAgain.canDefer)
        XCTAssertTrue(reloaded.beginDueReassessment(at: now, calendar: calendar))
        let request = try XCTUnwrap(reloaded.activeSessionRequest)
        XCTAssertEqual(request.source, .reassessment)
        XCTAssertEqual(request.reassessmentCycle, 1)
        XCTAssertEqual(request.assessmentBlock, .logicMetacognition)
        XCTAssertEqual(request.requestedMinutes, 6)

        let mentalBefore = try XCTUnwrap(reloaded.skillSummaries.first { $0.lab == .mentalMath })
        let runtime = NFUniversalSessionRuntime(request: request)
        XCTAssertFalse(runtime.isAssessmentPractice)
        XCTAssertEqual(runtime.assessmentDescriptor?.role, .reassessmentHoldout)
        var safetyCounter = 0
        while runtime.stage != .summary, safetyCounter < 20 {
            XCTAssertEqual(runtime.stage, .item)
            fillResponse(in: runtime)
            runtime.chooseConfidence(.fairlyConfident)
            let priorCount = reloaded.attempts.count
            let descriptorBeforeSubmit = runtime.assessmentDescriptor?.id
            runtime.submitInline(store: reloaded)
            finishSelfCheckComparisonIfNeeded(runtime, store: reloaded)
            XCTAssertEqual(runtime.stage, .feedback,
                "descriptor=\(descriptorBeforeSubmit ?? "none") paused=\(runtime.isPaused) confidence=\(String(describing: runtime.selectedConfidence)) save=\(runtime.saveError ?? "none") unavailable=\(runtime.unavailableReason ?? "none")")
            XCTAssertEqual(reloaded.attempts.count, priorCount + 1, "One accepted answer must create one durable response.")
            XCTAssertEqual(runtime.assessmentDescriptor?.id, descriptorBeforeSubmit,
                "Submitting must retain the protected item until explicit Next.")
            runtime.next(store: reloaded)
            safetyCounter += 1
        }
        XCTAssertLessThan(safetyCounter, 20)
        XCTAssertTrue(runtime.hasSufficientAssessmentEvidence)

        let reassessmentAttempts = reloaded.attempts.filter {
            $0.sessionID == runtime.sessionID && $0.sessionSourceRaw == SessionSource.reassessment.rawValue
        }
        XCTAssertFalse(reassessmentAttempts.isEmpty)
        XCTAssertTrue(reassessmentAttempts.allSatisfy {
            $0.assessmentCycle == 1
                && NFAssessmentDimension.from(skillID: $0.skillID)?.block == .logicMetacognition
                && Set($0.skillWeights.keys) == Set([$0.skillID])
        })
        for dimension in NFAssessmentCatalog.dimensions(for: .logicMetacognition) {
            let dimensionAttempts = reassessmentAttempts.filter { $0.skillID == dimension.skillID }
            XCTAssertEqual(
                dimensionAttempts.count,
                NFAssessmentCatalog.minimumItemsPerDimension(
                    for: .reassessmentHoldout,
                    block: .logicMetacognition
                )
            )
            XCTAssertGreaterThanOrEqual(
                Set(dimensionAttempts.compactMap(\.assessmentFormatRaw)).count,
                NFAssessmentCatalog.minimumFormatsPerDimension
            )
        }
        let mentalAfter = try XCTUnwrap(reloaded.skillSummaries.first { $0.lab == .mentalMath })
        XCTAssertEqual(mentalAfter.theta, mentalBefore.theta, accuracy: 0.000_000_001)
        XCTAssertEqual(mentalAfter.evidenceCount, mentalBefore.evidenceCount)
        XCTAssertEqual(mentalAfter.accuracy, mentalBefore.accuracy)

        runtime.finish(store: reloaded)
        let completedStore = AppStore(context: container.mainContext)
        XCTAssertEqual(completedStore.reassessmentStateRecord?.completedCycle, 1)
        XCTAssertNil(completedStore.reassessmentStateRecord?.dueAt)
        XCTAssertNil(completedStore.reassessmentStateRecord?.deferredUntil)
        XCTAssertNil(completedStore.reassessmentStateRecord?.targetBlockRaw)
        XCTAssertEqual(completedStore.reassessmentStatus(at: now)?.cycle, 2)
        XCTAssertEqual(completedStore.reassessmentStatus(at: now)?.activeDaysCompleted, 0)
    }

    @MainActor
    func testTimingIneligibleDocumentItemPersistsActualUntimedExecution() throws {
        let (store, container) = try makeStore()
        defer { _ = container }
        let runtime = NFUniversalSessionRuntime(request: SessionRequest(
            lab: .retrieval,
            source: .focused,
            seed: 0xD0C0,
            requestedMinutes: 5,
            evidenceClass: .documentPractice,
            requestedItemCount: 1,
            isTimed: true
        ))

        XCTAssertFalse(runtime.exercise.timingEligible)
        XCTAssertFalse(runtime.usesTimedMode)
        fillResponse(in: runtime)
        runtime.noteTextResponseInput()
        runtime.advance(store: store)
        runtime.commit(confidence: .fairlyConfident, store: store)
        finishSelfCheckComparisonIfNeeded(runtime, store: store)

        XCTAssertEqual(store.attempts.count, 1)
        let attempt = try XCTUnwrap(store.attempts.first)
        XCTAssertFalse(attempt.wasTimed)
        XCTAssertEqual(attempt.inputModeRaw, NFInputModality.keyboard.rawValue)
        XCTAssertEqual(
            attempt.responseFormatRaw,
            NFAuthoredExerciseAuthority.responseFormat(for: runtime.exercise.interaction)
        )
        XCTAssertNotEqual(attempt.responseFormatRaw, attempt.inputModeRaw)
    }

    @MainActor
    func testBaselinePracticeIsDurableZeroWeightAndNeverMovesAssessmentState() throws {
        let (store, container) = try makeStore()
        defer { _ = container }
        let seed: UInt64 = 0xBACE_1001
        let request = SessionRequest(
            lab: .logicDebugging,
            source: .baseline,
            seed: seed,
            requestedMinutes: 7,
            evidenceClass: .assessmentHoldout,
            targetDifficulty: 0.5,
            assessmentBlock: .logicMetacognition,
            isTimed: true
        )
        let runtime = NFUniversalSessionRuntime(request: request)

        XCTAssertTrue(runtime.isAssessmentPractice)
        XCTAssertEqual(runtime.assessmentDescriptor?.role, .practice)
        XCTAssertEqual(runtime.assessmentDescriptor?.assessmentWeight, 0)
        XCTAssertFalse(runtime.exercise.assessmentProtected)
        XCTAssertEqual(runtime.exercise.evidenceClass, .practice)
        XCTAssertEqual(runtime.assessmentState.completedScorableItems, 0)
        XCTAssertTrue(runtime.hidesAssessmentTimer)
        XCTAssertFalse(runtime.usesTimedMode)
        XCTAssertFalse(runtime.canSkip)

        fillResponse(in: runtime)
        runtime.advance(store: store)
        finishSelfCheckComparisonIfNeeded(runtime, store: store)

        XCTAssertEqual(runtime.stage, .feedback)
        XCTAssertEqual(runtime.correctness, [])
        XCTAssertEqual(runtime.credits, [])
        XCTAssertEqual(runtime.assessmentState.completedScorableItems, 0)
        XCTAssertTrue(runtime.assessmentEvents.contains { $0.hasPrefix("practice:") })
        let practiceAttempt = try XCTUnwrap(store.attempts.first)
        XCTAssertEqual(practiceAttempt.evidenceClassRaw, EvidenceClass.practice.rawValue)
        XCTAssertEqual(practiceAttempt.evidenceWeight, 0)
        XCTAssertFalse(practiceAttempt.wasSkipped)
        XCTAssertFalse(practiceAttempt.wasTimed)

        runtime.advance(store: store)
        XCTAssertEqual(runtime.stage, .item)
        XCTAssertFalse(runtime.isAssessmentPractice)
        XCTAssertTrue(runtime.exercise.assessmentProtected)
        XCTAssertEqual(runtime.assessmentState.completedScorableItems, 0)
        XCTAssertTrue(runtime.hidesAssessmentTimer)
        XCTAssertFalse(runtime.usesTimedMode)

        let restoredStore = AppStore(context: container.mainContext)
        XCTAssertTrue(restoredStore.beginSession(
            lab: .logicDebugging,
            source: .baseline,
            requestedMinutes: 7,
            evidenceClass: .assessmentHoldout,
            targetDifficulty: 0.5,
            assessmentBlock: .logicMetacognition,
            seedOverride: seed,
            isTimed: true
        ))
        let restoredRequest = try XCTUnwrap(restoredStore.activeSessionRequest)
        XCTAssertTrue(restoredRequest.resumedAssessmentEvents.contains { $0.hasPrefix("practice:") })
        XCTAssertGreaterThanOrEqual(restoredRequest.resumedAssessmentPracticeDurationSeconds, 0)
        let restoredRuntime = NFUniversalSessionRuntime(request: restoredRequest)
        XCTAssertFalse(restoredRuntime.isAssessmentPractice)
        XCTAssertEqual(restoredRuntime.assessmentState.completedScorableItems, 0)
    }

    @MainActor
    func testInsufficientDurationAndPoolStopsRemainIncompleteAndRetryWithFreshForm() throws {
        for exhaustion in [NFAssessmentStopReason.maximumActiveDurationReached, .candidatePoolExhausted] {
            let (store, container) = try makeStore()
            defer { _ = container }
            let seed: UInt64 = exhaustion == .maximumActiveDurationReached ? 7_700 : 7_701
            let assessment = NFAssessmentEngine.makeBlockSession(
                block: .logicMetacognition,
                phase: .initialBaseline,
                profileSeed: seed
            )
            let events: [String]
            let elapsed: TimeInterval
            switch exhaustion {
            case .maximumActiveDurationReached:
                events = ["practice:completed"]
                elapsed = TimeInterval(assessment.maximumDurationSeconds)
            case .candidatePoolExhausted:
                events = ["practice:completed"] + assessment.candidatePool.map { "skipped:\($0.id)" }
                elapsed = 0
            default:
                XCTFail("Unexpected test stop reason")
                continue
            }
            let sessionID = UUID()
            let request = SessionRequest(
                lab: .logicDebugging,
                source: .baseline,
                seed: seed,
                evidenceClass: .assessmentHoldout,
                targetDifficulty: 0.5,
                assessmentBlock: .logicMetacognition,
                isTimed: true,
                resumeSessionID: sessionID,
                resumedAssessmentEvents: events,
                resumedActiveDurationSeconds: elapsed
            )
            let runtime = NFUniversalSessionRuntime(request: request)

            XCTAssertEqual(runtime.stage, .summary)
            XCTAssertEqual(runtime.assessmentStopReason, exhaustion)
            XCTAssertEqual(runtime.assessmentState.completedScorableItems, 0)
            XCTAssertFalse(runtime.hasSufficientAssessmentEvidence)
            runtime.finish(store: store)

            let terminal = try XCTUnwrap(store.sessionCheckpoints.first { $0.sessionID == sessionID })
            XCTAssertFalse(terminal.isComplete)
            XCTAssertEqual(terminal.assessmentStopReasonRaw, exhaustion.rawValue)
            XCTAssertFalse(store.baselineBlockIsEstablished(.logicMetacognition))
            XCTAssertTrue(store.baselineBlockNeedsRetry(.logicMetacognition))

            XCTAssertTrue(store.beginSession(
                lab: .logicDebugging,
                source: .baseline,
                evidenceClass: .assessmentHoldout,
                targetDifficulty: 0.5,
                assessmentBlock: .logicMetacognition,
                seedOverride: seed,
                isTimed: true
            ))
            let retry = try XCTUnwrap(store.activeSessionRequest)
            XCTAssertNotEqual(retry.seed, seed)
            XCTAssertTrue(retry.resumedAssessmentEvents.isEmpty)
            XCTAssertEqual(retry.resumedResults, [])
            XCTAssertTrue(NFUniversalSessionRuntime(request: retry).isAssessmentPractice)
        }
    }

    @MainActor
    func testCompletedCheckpointCannotPromoteSkippedOrPracticeAttemptsToBaselineEvidence() throws {
        let (store, container) = try makeStore()
        defer { _ = container }
        let seed: UInt64 = 8_008
        let assessment = NFAssessmentEngine.makeBlockSession(
            block: .scientificDataReasoning,
            phase: .initialBaseline,
            profileSeed: seed
        )
        let skipped = try XCTUnwrap(assessment.items.first)
        let sessionID = UUID()
        try store.saveSkippedExercise(
            attemptID: UUID(),
            sessionID: sessionID,
            exercise: makeAssessmentExercise(for: skipped, index: 0),
            shownAt: Date(),
            activeDuration: 4,
            source: .baseline,
            assessmentBlock: .scientificDataReasoning,
            assessmentDescriptor: skipped,
            wasTimed: true
        )
        let practiceDescriptor = try XCTUnwrap(NFPracticeItemSelector.select(
            from: NFAssessmentEngine.makePracticeCandidates(
                block: .scientificDataReasoning,
                seed: seed
            ),
            seed: seed
        ))
        let practiceExercise = try makeExercise(for: practiceDescriptor, purpose: .practice)
        try store.saveExerciseAttempt(
            attemptID: UUID(),
            sessionID: sessionID,
            exercise: practiceExercise,
            response: .shortText("practice response"),
            result: makeScoringResult(for: practiceExercise, credit: 1),
            confidence: .fairlyConfident,
            shownAt: Date(),
            activeDuration: 3,
            source: .baseline,
            assessmentBlock: .scientificDataReasoning,
            assessmentDescriptor: practiceDescriptor,
            wasTimed: true
        )
        let request = SessionRequest(
            lab: .scientificReasoning,
            source: .baseline,
            seed: seed,
            evidenceClass: .assessmentHoldout,
            assessmentBlock: .scientificDataReasoning,
            isTimed: true
        )
        try store.upsertCheckpoint(
            sessionID: sessionID,
            request: request,
            currentIndex: 0,
            itemCount: assessment.itemCap,
            response: "",
            scratchpad: "",
            results: [],
            assessmentEvents: ["practice:\(practiceDescriptor.id)", "skipped:\(skipped.id)"],
            activeDurationSeconds: 7,
            assessmentStopReason: .candidatePoolExhausted,
            hasCommittedCurrentItem: true,
            isComplete: true
        )

        XCTAssertEqual(store.baselineScorableAttemptCount(for: .scientificDataReasoning), 0)
        XCTAssertFalse(store.baselineBlockIsEstablished(.scientificDataReasoning))
        XCTAssertEqual(store.attempts.filter { !$0.wasSkipped }.map(\.evidenceWeight), [0])

        for (index, descriptor) in assessment.items.enumerated() {
            let record = AttemptRecord(
                sessionID: sessionID,
                lab: descriptor.lab,
                itemID: "scorable-\(index)",
                prompt: "Scorable protected prompt \(index)",
                response: "response",
                correctAnswer: "answer",
                isCorrect: true,
                confidence: .fairlyConfident,
                evidenceClass: .assessmentHoldout,
                source: .baseline
            )
            record.assessmentBlockRaw = NFAssessmentBlockKind.scientificDataReasoning.rawValue
            record.assessmentDescriptorID = descriptor.id
            record.assessmentTemplateFamily = descriptor.templateFamily
            record.assessmentFormatRaw = descriptor.format.rawValue
            record.assessmentSubskillID = descriptor.subskillID
            record.skillID = descriptor.skillID
            record.skillWeightsRaw = encodedSkillWeights([descriptor.skillID: 1.0])
            record.deterministicCredit = 1
            store.context.insert(record)
        }
        try store.context.save()
        store.reload()

        XCTAssertEqual(
            store.baselineScorableAttemptCount(for: .scientificDataReasoning),
            assessment.minimumScorableItems
        )
        XCTAssertTrue(store.baselineBlockIsEstablished(.scientificDataReasoning))
    }

    @MainActor
    func testBaselineHistoryReplayPreservesSkippedExposureTimeWithoutScoringIt() throws {
        let (store, container) = try makeStore()
        defer { _ = container }
        let profileSeed: UInt64 = 0xB451_1E
        let assessment = NFAssessmentEngine.makeBlockSession(
            block: .logicMetacognition,
            phase: .initialBaseline,
            profileSeed: profileSeed,
            selfReportedDifficulty: 0.5
        )
        var replayState = NFAssessmentEngine.initialAdaptiveState(selfReportedDifficulty: 0.5)
        let skippedDescriptor = try XCTUnwrap(
            NFAssessmentEngine.nextStep(
                in: assessment,
                state: replayState,
                activeElapsedSeconds: 0
            ).item
        )
        replayState = replayState.appending(skippedDescriptor)
        let answeredDescriptor = try XCTUnwrap(
            NFAssessmentEngine.nextStep(
                in: assessment,
                state: replayState,
                activeElapsedSeconds: 11
            ).item
        )
        let sessionID = UUID()
        let skippedAttemptID = UUID()
        let answeredAttemptID = UUID()
        let baseDate = Date(timeIntervalSince1970: 1_800_000_000)

        try store.saveSkippedExercise(
            attemptID: skippedAttemptID,
            sessionID: sessionID,
            exercise: makeAssessmentExercise(for: skippedDescriptor, index: 0),
            shownAt: baseDate.addingTimeInterval(-11),
            activeDuration: 11,
            source: .baseline,
            assessmentBlock: .logicMetacognition,
            assessmentDescriptor: skippedDescriptor,
            interruptionCount: 1,
            accommodationFlags: ["hide_timers"],
            wasTimed: false
        )
        let skippedRecord = try XCTUnwrap(store.attempts.first { $0.id == skippedAttemptID })
        skippedRecord.submittedAt = baseDate

        let answeredExercise = try makeAssessmentExercise(for: answeredDescriptor, index: 0)
        try store.saveExerciseAttempt(
            attemptID: answeredAttemptID,
            sessionID: sessionID,
            exercise: answeredExercise,
            response: .shortText("supported answer"),
            result: makeScoringResult(for: answeredExercise, credit: 0.75),
            confidence: .fairlyConfident,
            shownAt: baseDate.addingTimeInterval(-8),
            activeDuration: 19,
            source: .baseline,
            assessmentBlock: .logicMetacognition,
            assessmentDescriptor: answeredDescriptor,
            wasTimed: false
        )
        let answeredRecord = try XCTUnwrap(store.attempts.first { $0.id == answeredAttemptID })
        answeredRecord.submittedAt = baseDate.addingTimeInterval(20)
        try store.context.save()
        store.reload()

        let persistedSkip = try XCTUnwrap(store.attempts.first { $0.id == skippedAttemptID })
        XCTAssertTrue(persistedSkip.wasSkipped)
        XCTAssertEqual(persistedSkip.evidenceWeight, 0)
        XCTAssertEqual(persistedSkip.deterministicCredit, 0)
        XCTAssertFalse(persistedSkip.isCorrect)
        XCTAssertNil(persistedSkip.confidenceRaw)
        XCTAssertEqual(persistedSkip.assessmentDescriptorID, skippedDescriptor.id)
        XCTAssertEqual(persistedSkip.assessmentTemplateFamily, skippedDescriptor.templateFamily)
        XCTAssertEqual(persistedSkip.assessmentMechanicID, skippedDescriptor.mechanicID)
        XCTAssertEqual(persistedSkip.activeDurationSeconds, 11, accuracy: 1e-12)

        XCTAssertTrue(store.beginSession(
            lab: .logicDebugging,
            source: .baseline,
            targetDifficulty: 0.5,
            assessmentBlock: .logicMetacognition,
            seedOverride: profileSeed,
            isTimed: false
        ))
        let resumed = try XCTUnwrap(store.activeSessionRequest)
        XCTAssertEqual(resumed.resumeSessionID, sessionID)
        XCTAssertEqual(resumed.startingIndex, 1)
        XCTAssertEqual(resumed.resumedResults, [false])
        XCTAssertEqual(resumed.resumedCredits, [0.75])
        XCTAssertEqual(resumed.resumedAssessmentDescriptorIDs, [answeredDescriptor.id])
        XCTAssertEqual(resumed.resumedAssessmentEvents, [
            "skipped:\(skippedDescriptor.id)",
            "answered:\(answeredDescriptor.id)"
        ])
        XCTAssertEqual(resumed.resumedActiveDurationSeconds, 30, accuracy: 1e-12)
        XCTAssertTrue(resumed.resumeCurrentItemWasCommitted)

        let summary = try XCTUnwrap(
            store.baselineDimensionSummaries.first { $0.id == answeredDescriptor.skillID }
        )
        XCTAssertEqual(summary.evidenceCount, 0)
        XCTAssertNil(summary.accuracy)
        let history = try XCTUnwrap(NFHistoricalPracticeProjection.reduce(
            attempts: [answeredRecord.dto, persistedSkip.dto]).first)
        XCTAssertEqual(history.legacyCount, 1)
        XCTAssertEqual(try XCTUnwrap(history.legacyMeanCredit), 0.75, accuracy: 1e-12)
        XCTAssertEqual(history.excludedAttemptIDs, [skippedAttemptID.uuidString])
    }

    @MainActor
    func testAssessmentCheckpointEventsSurviveStoreReloadAndTakeReplayPrecedence() throws {
        let (store, container) = try makeStore()
        defer { _ = container }
        let profileSeed: UInt64 = 9_101
        let assessment = NFAssessmentEngine.makeBlockSession(
            block: .scientificDataReasoning,
            phase: .initialBaseline,
            profileSeed: profileSeed
        )
        let skipped = try XCTUnwrap(assessment.candidatePool.first)
        let answered = try XCTUnwrap(assessment.candidatePool.dropFirst().first)
        let events = ["skipped:\(skipped.id)", "answered:\(answered.id)"]
        let sessionID = UUID()
        let request = SessionRequest(
            lab: .scientificReasoning,
            source: .baseline,
            seed: profileSeed,
            evidenceClass: .assessmentHoldout,
            targetDifficulty: 0.5,
            assessmentBlock: .scientificDataReasoning,
            isTimed: true
        )

        try store.upsertCheckpoint(
            sessionID: sessionID,
            request: request,
            currentIndex: 1,
            itemCount: assessment.itemCap,
            response: "draft-response",
            scratchpad: "private scratchpad",
            results: [true],
            credits: [0.5],
            assessmentDescriptorIDs: [answered.id],
            assessmentEvents: events,
            activeDurationSeconds: 41,
            hasCommittedCurrentItem: false
        )

        let restored = AppStore(context: container.mainContext)
        XCTAssertTrue(restored.beginSession(
            lab: .scientificReasoning,
            source: .baseline,
            targetDifficulty: 0.5,
            assessmentBlock: .scientificDataReasoning,
            seedOverride: profileSeed,
            isTimed: true
        ))
        let resumed = try XCTUnwrap(restored.activeSessionRequest)
        XCTAssertEqual(resumed.resumeSessionID, sessionID)
        XCTAssertEqual(resumed.startingIndex, 1)
        XCTAssertEqual(resumed.resumedResults, [true])
        XCTAssertEqual(resumed.resumedCredits, [0.5])
        XCTAssertEqual(resumed.resumedAssessmentDescriptorIDs, [answered.id])
        XCTAssertEqual(resumed.resumedAssessmentEvents, events)
        XCTAssertEqual(resumed.resumedResponsePayload, "draft-response")
        XCTAssertEqual(resumed.resumedScratchpad, "private scratchpad")
        XCTAssertEqual(resumed.resumedActiveDurationSeconds, 41, accuracy: 1e-12)
        XCTAssertFalse(resumed.resumeCurrentItemWasCommitted)
    }

    @MainActor
    func testReportQuarantinePersistsIntoFutureSessionAndDiagnosticExport() throws {
        let (store, container) = try makeStore()
        defer { _ = container }
        let seed: UInt64 = 6_060
        let assessment = NFAssessmentEngine.makeBlockSession(
            block: .numericalFluency,
            phase: .initialBaseline,
            profileSeed: seed
        )
        let descriptor = try XCTUnwrap(assessment.candidatePool.first)
        let exercise = try makeAssessmentExercise(for: descriptor, index: 0)
        try store.saveItemReport(
            exercise: exercise,
            assessmentDescriptorID: descriptor.id,
            reason: "Answer key appears ambiguous",
            note: "Two options are equivalent under the stated assumptions."
        )

        let restored = AppStore(context: container.mainContext)
        XCTAssertEqual(restored.itemReports.count, 1)
        XCTAssertTrue(restored.beginSession(
            lab: descriptor.lab,
            source: .baseline,
            targetDifficulty: 0.5,
            assessmentBlock: .numericalFluency,
            seedOverride: seed,
            isTimed: false
        ))
        XCTAssertEqual(restored.activeSessionRequest?.quarantinedItemIDs, Set([exercise.id]))
        XCTAssertEqual(
            restored.activeSessionRequest?.quarantinedAssessmentDescriptorIDs,
            Set([descriptor.id])
        )

        let exportURLs = try NFDataExportService.makeExports(from: restored)
        defer { removeExportFolder(for: exportURLs) }
        let archive = try archiveObject(from: exportURLs)
        let reports = try XCTUnwrap(archive["quarantinedReports"] as? [[String: Any]])
        let report = try XCTUnwrap(reports.first)
        XCTAssertEqual(report["itemID"] as? String, exercise.id)
        XCTAssertEqual(report["templateID"] as? String, exercise.templateID)
        XCTAssertEqual(report["reason"] as? String, "Answer key appears ambiguous")
        XCTAssertEqual(report["note"] as? String, "Two options are equivalent under the stated assumptions.")
        XCTAssertEqual((report["generatorVersion"] as? NSNumber)?.intValue, exercise.generatorVersion)
        XCTAssertEqual(report["status"] as? String, "quarantined")
        XCTAssertEqual(report["provenanceSummary"] as? String, restored.itemReports[0].provenanceSummary)
        XCTAssertEqual(report["assessmentDescriptorID"] as? String, descriptor.id)
    }

    @MainActor
    func testSpatialDifficultyVectorPersistsForAnsweredAndSkippedAttemptsAndExports() throws {
        let (store, container) = try makeStore()
        defer { _ = container }
        let answeredExercise = try NFFallbackExerciseGenerator.generate(NFExerciseGenerationRequest(
            seed: 71_001,
            index: 0,
            lab: .spatial,
            purpose: .practice,
            preferredAssessmentMechanicID: "spatial.fallback-variant-1"
        ))
        let skippedExercise = try NFFallbackExerciseGenerator.generate(NFExerciseGenerationRequest(
            seed: 71_002,
            index: 1,
            lab: .spatial,
            purpose: .practice,
            preferredAssessmentMechanicID: "spatial.fallback-variant-2"
        ))

        try store.saveExerciseAttempt(
            attemptID: UUID(),
            sessionID: UUID(),
            exercise: answeredExercise,
            response: .singleChoice(optionID: "correct"),
            result: makeScoringResult(for: answeredExercise, credit: 1),
            confidence: .certain,
            shownAt: Date().addingTimeInterval(-8),
            activeDuration: 8,
            source: .focused,
            inputMode: NFInputModality.pointer.rawValue
        )
        try store.saveSkippedExercise(
            attemptID: UUID(),
            sessionID: UUID(),
            exercise: skippedExercise,
            shownAt: Date().addingTimeInterval(-3),
            activeDuration: 3,
            source: .focused
        )

        XCTAssertEqual(store.attempts.count, 2)
        for attempt in store.attempts {
            let expected = attempt.itemID == answeredExercise.id
                ? answeredExercise.spatialDifficultyParameters
                : skippedExercise.spatialDifficultyParameters
            XCTAssertEqual(attempt.spatialDifficultyParameters, expected)
            XCTAssertEqual(attempt.dto.spatialDifficultyParameters, expected)
            XCTAssertNotEqual(attempt.spatialDifficultyParameters?.stimulusCategory, "legacy-unspecified")
        }
        let answered = try XCTUnwrap(store.attempts.first { $0.itemID == answeredExercise.id })
        XCTAssertEqual(answered.responseFormatRaw, "singleChoice")
        XCTAssertEqual(answered.inputModeRaw, NFInputModality.pointer.rawValue)

        let exportURLs = try NFDataExportService.makeExports(from: store)
        defer { removeExportFolder(for: exportURLs) }
        let archive = try archiveObject(from: exportURLs)
        let attempts = try XCTUnwrap(archive["attempts"] as? [[String: Any]])
        XCTAssertEqual(attempts.count, 2)
        for attempt in attempts {
            let parameters = try XCTUnwrap(attempt["spatialDifficultyParameters"] as? [String: Any])
            XCTAssertFalse((parameters["viewpoint"] as? String ?? "").isEmpty)
            XCTAssertNotNil(parameters["rotationMagnitudeDegrees"] as? NSNumber)
            XCTAssertNotNil(parameters["objectComplexity"] as? NSNumber)
            XCTAssertNotNil(parameters["distractorSimilarity"] as? NSNumber)
            XCTAssertEqual(parameters["responseMode"] as? String, NFSpatialResponseMode.singleChoice.rawValue)
            XCTAssertFalse((parameters["stimulusCategory"] as? String ?? "").isEmpty)
        }
    }

    @MainActor
    func testPlanPolicyUpgradePreservesFrozenPayloadAcrossReadinessTravelAndRelaunch() throws {
        let createdAt = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-08-05T23:00:00Z"))
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = try XCTUnwrap(TimeZone(identifier: "UTC"))
        var tokyo = utc
        tokyo.timeZone = try XCTUnwrap(TimeZone(identifier: "Asia/Tokyo"))
        for version in [4, 999] {
            let (store, container) = try makeStore()
            defer { _ = container }
            let profile = store.profileSnapshot
            let fresh = NFDailyScheduler.canonicalPlan(for: .init(profile: profile, date: createdAt), calendar: utc)
            var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(fresh)) as? [String: Any])
            object["policyVersion"] = version
            object["id"] = "frozen-policy-\(version)"
            let frozen = try JSONDecoder().decode(NFCanonicalDailyPlan.self,
                from: JSONSerialization.data(withJSONObject: object))
            let record = try DailyPlanRecord(plan: frozen, boundaryContext: .make(
                at: createdAt, dayBoundaryHour: profile.dayBoundaryHour, calendar: utc))
            store.context.insert(record)
            try store.context.save()
            store.reload()
            let originalPayload = record.payload
            XCTAssertEqual(store.dailyPlan(at: createdAt, calendar: utc).id, frozen.id)
            store.updateReadiness(.low, at: createdAt, calendar: utc)
            XCTAssertEqual(record.payload, originalPayload)
            XCTAssertEqual(store.dailyPlan(at: createdAt, calendar: utc).id, frozen.id)
            let block = try XCTUnwrap(frozen.blocks.first)
            if version == 4 {
                let request = SessionRequest(lab: block.lab, source: .today, seed: frozen.seed,
                    requestedMinutes: block.minutes, requestedItemCount: 1,
                    planID: frozen.id, planBlockID: block.id)
                try store.upsertCheckpoint(sessionID: request.id, request: request, currentIndex: 0,
                    itemCount: 1, response: "saved draft", scratchpad: "retained scratchpad", results: [])
                store.updateReadiness(.high, at: createdAt, calendar: utc)
                XCTAssertEqual(record.payload, originalPayload)
            } else {
                let revision = store.localSessions.archive.transactionRevision
                XCTAssertFalse(store.beginSession(lab: block.lab, source: .today,
                    requestedItemCount: 5, planID: frozen.id, planBlockID: block.id))
                XCTAssertNil(store.activeSessionRequest)
                XCTAssertNotNil(store.lastErrorMessage)
                XCTAssertEqual(store.localSessions.archive.transactionRevision, revision)
                XCTAssertTrue(store.localSessions.archive.sessions.isEmpty)
            }
            let travelledAt = createdAt.addingTimeInterval(2 * 3_600)
            XCTAssertEqual(store.dailyPlan(at: travelledAt, calendar: tokyo).id, frozen.id)
            XCTAssertEqual(record.payload, originalPayload)
            XCTAssertEqual(store.dailyPlans.count, 1)
            let restored = AppStore(context: ModelContext(container))
            XCTAssertEqual(restored.dailyPlan(at: travelledAt, calendar: tokyo).id, frozen.id)
            XCTAssertEqual(restored.dailyPlans.first?.payload, originalPayload)
            let next = restored.dailyPlan(at: createdAt.addingTimeInterval(19 * 3_600), calendar: tokyo)
            XCTAssertEqual(next.policyVersion, 5)
            XCTAssertNotEqual(next.id, frozen.id)
            XCTAssertEqual(restored.dailyPlans.first(where: { $0.id == frozen.id })?.payload, originalPayload)
            XCTAssertEqual(restored.dailyPlans.count, 2)
        }
    }

    @MainActor
    func testReadinessRegenerationKeepsExactlyOneCanonicalPlanAndStartedPlanIsImmutable() throws {
        let (store, container) = try makeStore()
        defer { _ = container }

        let normal = store.todayPlan
        store.updateReadiness(.low)
        let low = store.todayPlan
        store.updateReadiness(.high)
        let high = store.todayPlan

        XCTAssertEqual(store.dailyPlans.count, 1)
        XCTAssertNotEqual(normal.id, low.id)
        XCTAssertNotEqual(normal.id, high.id)
        XCTAssertNotEqual(low.id, high.id)
        XCTAssertLessThan(low.minutes, normal.minutes)
        XCTAssertEqual(high.minutes, normal.minutes)
        XCTAssertTrue(low.blocks.allSatisfy { $0.reasons.contains(.userOverride) })
        XCTAssertTrue(high.blocks.allSatisfy { $0.reasons.contains(.userOverride) })

        let restored = AppStore(context: container.mainContext)
        assertSamePlan(restored.todayPlan, high)
        XCTAssertEqual(restored.dailyPlans.count, 1)

        let checkpointRequest = SessionRequest(
            lab: high.blocks[0].lab,
            source: .today,
            seed: high.seed,
            requestedMinutes: high.blocks[0].minutes,
            planID: high.id,
            planBlockID: high.blocks[0].id
        )
        try restored.upsertCheckpoint(
            sessionID: UUID(),
            request: checkpointRequest,
            currentIndex: 0,
            itemCount: 1,
            response: "",
            scratchpad: "",
            results: []
        )
        restored.updateReadiness(.low)
        assertSamePlan(restored.todayPlan, high)
        XCTAssertEqual(restored.dailyPlans.count, 1)
        XCTAssertEqual(restored.readiness, .low)
    }

    @MainActor
    func testReviewedTimingGateRejectsLegacyTemplateCountsButAllowsElapsedOnlyWithoutConsumingARejectedLaunch() throws {
        let (store, container) = try makeStore(); defer { _ = container }
        let now = Date()
        for index in 0..<20 {
            let record = AttemptRecord(sessionID: UUID(), lab: .mentalMath, itemID: "legacy.timing.\(index)",
                prompt: "1 + 1", response: "2", correctAnswer: "2", isCorrect: true,
                confidence: .certain, evidenceClass: .practice, source: .focused)
            record.templateID = "legacy-template-\(index % 2)"
            record.submittedAt = now.addingTimeInterval(Double(index - 100))
            record.wasTimed = true; record.hintCount = index < 2 ? 1 : 0
            container.mainContext.insert(record)
        }
        try container.mainContext.save(); store.reload()
        let gate = store.reviewedFluencyReadiness(lab: .mentalMath, at: now)
        XCTAssertFalse(gate.timingEligible); XCTAssertEqual(gate.reason, .reviewedPracticeUnavailable)
        let scope = NFEditorialEvidenceGroup(lane: .practice, objectiveID: "synthetic.add", familyID: "synthetic.add",
            band: .b1, bandContractVersion: "synthetic.v1", scoringComparabilityID: "exact.v1",
            stimulusComparabilityID: "numeric", toolConditionID: "none", localeComparabilityID: "en",
            pacingConditionID: "untimed", protocolScope: "practice.v1")
        XCTAssertFalse(store.beginSession(lab: .mentalMath, source: .focused, requestedItemCount: 1,
            timingCondition: .init(.timedFluency, fluencyScope: scope)))
        XCTAssertNil(store.activeSessionRequest)
        XCTAssertTrue(store.localSessions.archive.sessions.isEmpty)
        XCTAssertNil(store.localSessions.archive.offlineRotationLedger)
        XCTAssertTrue(store.beginSession(lab: .mentalMath, source: .focused, requestedItemCount: 1,
            timingCondition: .init(.elapsedOnly)))
        let request = try XCTUnwrap(store.activeSessionRequest)
        XCTAssertEqual(request.timingCondition?.mode, .elapsedOnly)
        let runtime = NFUniversalSessionRuntime(request: request)
        XCTAssertTrue(runtime.showsTimer); XCTAssertFalse(runtime.usesTimedMode)
        XCTAssertEqual(store.attempts.count, 20)
    }

    @MainActor
    func testDailyPlanReminderUsesEffectiveChronologyInsteadOfRawAttemptCount() throws {
        let (store, container) = try makeStore()
        defer { _ = container }
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        for index in 0..<8 {
            let attempt = AttemptRecord(sessionID: UUID(), lab: .logicDebugging, itemID: "legacy.\(index)",
                prompt: "Trace a transition.", response: "2", correctAnswer: "2", isCorrect: true,
                confidence: .certain, evidenceClass: .practice, source: .focused)
            attempt.templateID = "logic.compatibility-reminder"
            attempt.seed = UInt64(index)
            attempt.submittedAt = start.addingTimeInterval(Double(index))
            container.mainContext.insert(attempt)
        }
        try container.mainContext.save(); store.reload()
        let plan = store.dailyPlan(at: start.addingTimeInterval(2 * 86_400), calendar: calendar)
        let saved = try XCTUnwrap(store.dailyPlans.first { $0.id == plan.id }?.snapshot)
        XCTAssertTrue(saved.blocks.flatMap(\.retentionItemIDs).contains("logic.compatibility-reminder"),
            "Eight early legacy successes must not postpone a one-day reminder to the 30-day rung")
        XCTAssertEqual(store.attempts.count, 8)
        XCTAssertTrue(store.skillSummaries.allSatisfy { $0.status == .unassessed })
    }

    @MainActor
    func testDailyPlanReminderRebuildExcludesCorrectedAndConflictedHistoryWithoutRewritingCommittedPlan() throws {
        let (store, container) = try makeStore()
        defer { _ = container }
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        var records: [AttemptRecord] = []
        for name in ["corrected", "conflicted"] {
            let record = AttemptRecord(sessionID: UUID(), lab: .logicDebugging, itemID: name,
                prompt: "Trace a transition.", response: "2", correctAnswer: "2", isCorrect: true,
                confidence: .certain, evidenceClass: .practice, source: .focused)
            record.templateID = "logic.reminder.\(name)"; record.submittedAt = start
            container.mainContext.insert(record); records.append(record)
        }
        try container.mainContext.save(); store.reload()
        let before = store.dailyPlan(at: start.addingTimeInterval(2 * 86_400), calendar: calendar)
        let originalPlan = try XCTUnwrap(store.dailyPlans.first { $0.id == before.id }?.snapshot)
        XCTAssertFalse(originalPlan.blocks.flatMap(\.retentionItemIDs).isEmpty)
        let corrected = records[0], conflicted = records[1]
        try store.localSessions.appendDispositions([.init(id: "synthetic.reminder.correction", attemptID: corrected.id.uuidString,
            revision: 1, policyVersion: NFHistoricalPracticeProjection.policyVersion, occurredAt: start,
            disposition: .excludedContentCorrection, reason: "Synthetic invalid scoring contract",
            correctedDerivedCredit: nil, supersedesDispositionID: nil)])
        let proposed = AttemptRecord(sessionID: conflicted.sessionID, lab: .logicDebugging, itemID: conflicted.itemID,
            prompt: conflicted.prompt, response: "3", correctAnswer: "2", isCorrect: false,
            confidence: .certain, evidenceClass: .practice, source: .focused)
        proposed.id = conflicted.id; proposed.templateID = conflicted.templateID
        try store.localSessions.appendAttemptConflict(.init(original: .init(conflicted), proposed: .init(proposed),
            originalExercise: nil, proposedExercise: nil, proposedScore: nil))
        XCTAssertEqual(store.effectiveAttemptDTO(corrected).evidenceWeight, 0)
        XCTAssertEqual(store.effectiveAttemptDTO(conflicted).evidenceWeight, 0)
        let after = store.dailyPlan(at: start.addingTimeInterval(4 * 86_400), calendar: calendar)
        let nextPlan = try XCTUnwrap(store.dailyPlans.first { $0.id == after.id }?.snapshot)
        XCTAssertTrue(nextPlan.blocks.flatMap(\.retentionItemIDs).isEmpty,
            "Raw correct flags cannot put excluded conflict/correction payloads back into the queue")
        XCTAssertEqual(store.dailyPlans.first { $0.id == before.id }?.snapshot, originalPlan)
        XCTAssertTrue(records.allSatisfy(\.isCorrect)); XCTAssertEqual(store.attempts.count, 2)
        XCTAssertTrue(records.allSatisfy { $0.response == "2" })
    }

    @MainActor
    func testReviewsDueHandoffStartsOnlyARealRetentionAssignment() throws {
        let (store, container) = try makeStore()
        defer { _ = container }
        let now = Date()
        let source = try NFFallbackExerciseGenerator.generate(.init(seed: 20260905, index: 0,
            lab: .mentalMath, purpose: .practice, localeIdentifier: "en",
            preferredAssessmentMechanicID: "fixture.fallback-variant-1"))
        guard case .numeric(let sourceSchema) = source.interaction else { return XCTFail("Expected the pinned numeric source contract") }
        let sourceResponse = NFExerciseResponse.numeric(.init(value: String(sourceSchema.answer.value), unit: sourceSchema.answer.canonicalUnit))
        let sourceScore = NFExerciseScoringEngine.score(sourceResponse, for: source)
        XCTAssertTrue(sourceScore.isCorrect)
        let attempt = AttemptRecord(sessionID: UUID(), lab: source.lab, itemID: source.id,
            prompt: source.prompt, response: String(decoding: try JSONEncoder().encode(sourceResponse), as: UTF8.self),
            correctAnswer: sourceScore.expectedAnswerSummary ?? "", isCorrect: true,
            confidence: .fairlyConfident, evidenceClass: .practice, source: .focused)
        attempt.templateID = source.templateID; attempt.assessmentTemplateFamily = source.templateFamily
        attempt.seed = source.seed; attempt.scoringVersion = sourceScore.scoringVersion
        attempt.responseFormatRaw = sourceResponse.responseFormatRaw
        attempt.submittedAt = now.addingTimeInterval(-30 * 86_400)
        attempt.deterministicCredit = sourceScore.credit; attempt.evidenceWeight = 1
        container.mainContext.insert(attempt)
        try container.mainContext.save()
        try store.localSessions.retainSnapshot(attemptID: attempt.id, exercise: source)
        store.reload()
        let plan = store.todayPlan
        let originalPlan = try XCTUnwrap(store.dailyPlans.first { $0.id == plan.id }?.snapshot)
        let originalAttempt = try NFImmutableAttemptRecordSnapshot.encoded(NFImmutableAttemptRecordSnapshot(attempt))

        // Notification entry and direct Review use the same current effective
        // queue, even when the already frozen Today plan has no due target.
        NFExternalRouteRouter.apply(.dueTodayReview, to: store)
        XCTAssertEqual(store.selectedDestination, .progress)
        XCTAssertFalse(store.shouldOpenTodayPlan)
        let request = try XCTUnwrap(store.activeSessionRequest)
        XCTAssertEqual(request.evidenceClass, .retention)
        XCTAssertEqual(request.source, .focused)
        XCTAssertEqual(request.requestedItemCount, 1)
        XCTAssertEqual(request.retentionItemIDs, [attempt.templateID])
        let target = try XCTUnwrap(request.retentionTargets.first)
        XCTAssertEqual(target.memoryItemID, attempt.templateID)
        XCTAssertEqual(target.templateFamily, source.templateFamily)
        XCTAssertFalse(target.requiresRepresentationShift, "The compatibility reminder does not fabricate a reviewed representation-shift policy")
        XCTAssertEqual(target.priorRepresentationID, attempt.responseFormatRaw)
        XCTAssertNil(request.planID); XCTAssertNil(request.planBlockID)
        XCTAssertEqual(store.dailyPlans.first { $0.id == plan.id }?.snapshot, originalPlan)

        let exercise = NFDeterministicSessionExerciseFactory.makeExercise(request: request, index: 0,
            assessmentDescriptor: nil, excludingContentFingerprints: request.repairSemanticExclusions ?? [])
        XCTAssertNil(exercise.availabilityReason)
        XCTAssertEqual(exercise.purpose, .retention)
        XCTAssertNotEqual(NFQuestionFingerprint.fingerprint(for: exercise), NFQuestionFingerprint.fingerprint(for: source))
        guard case .numeric(let schema) = exercise.interaction else { return XCTFail("The selected numeric mechanic must remain numeric") }
        let response = NFExerciseResponse.numeric(.init(value: String(schema.answer.value), unit: schema.answer.canonicalUnit))
        let result = NFExerciseScoringEngine.score(response, for: exercise)
        XCTAssertTrue(result.isCorrect)
        let savedAttemptID = UUID()
        try store.saveExerciseAttempt(attemptID: savedAttemptID, sessionID: request.id, exercise: exercise,
            response: response, result: result, confidence: .certain, shownAt: now,
            activeDuration: 8, source: request.source)
        let persistedReview = try XCTUnwrap(store.attempts.first { $0.id == savedAttemptID })
        XCTAssertEqual(persistedReview.itemID, exercise.id, "Generated provenance identity remains immutable")
        XCTAssertEqual(persistedReview.templateID, target.memoryItemID)
        XCTAssertEqual(persistedReview.assessmentTemplateFamily, target.templateFamily)
        XCTAssertEqual(persistedReview.assessmentSeed, target.alternateSeed)
        XCTAssertEqual(persistedReview.assessmentFormatRaw, NFRetentionRepresentation.identifier(for: exercise))
        XCTAssertEqual(try NFImmutableAttemptRecordSnapshot.encoded(NFImmutableAttemptRecordSnapshot(attempt)), originalAttempt)
        XCTAssertEqual(store.dailyPlans.first { $0.id == plan.id }?.snapshot, originalPlan)

        let (emptyStore, emptyContainer) = try makeStore()
        defer { _ = emptyContainer }
        NFExternalRouteRouter.apply(.dueTodayReview, to: emptyStore)
        XCTAssertNil(emptyStore.activeSessionRequest)
        XCTAssertFalse(emptyStore.shouldOpenTodayPlan)
        XCTAssertEqual(emptyStore.selectedDestination, .progress)
        XCTAssertTrue(emptyStore.readyReviewEntries(at: now, calendar: .current).isEmpty)
    }

    @MainActor
    func testOnboardingCompletesWithoutCalibrationAndPreservesPreferredAnswerMode() throws {
        let (store, container) = try makeStore()
        var onboarding = OnboardingDraft()
        onboarding.claimsPolicyAcknowledgedVersion = NFClaimsPolicy.currentVersion
        onboarding.ageBandAcknowledged16Plus = true
        onboarding.preferredAnswerMode = .keyboard

        XCTAssertFalse(onboarding.hasInputCalibrationSample)
        store.completeOnboarding(onboarding)

        XCTAssertTrue(store.isOnboardingComplete)
        XCTAssertEqual(store.profile?.preferredAnswerModeRaw, NFPreferredAnswerMode.keyboard.rawValue)
        XCTAssertTrue(store.inputCalibrations.isEmpty)

        let restored = AppStore(context: container.mainContext)
        XCTAssertTrue(restored.isOnboardingComplete)
        XCTAssertEqual(restored.profile?.preferredAnswerModeRaw, NFPreferredAnswerMode.keyboard.rawValue)
        XCTAssertNil(restored.latestInputCalibration)
    }

    @MainActor
    func testGlobalUntimedPreservesPlanAndOverridesExplicitTimedSession() throws {
        let (store, container) = try makeStore()
        defer { _ = container }

        var onboarding = OnboardingDraft()
        onboarding.claimsPolicyAcknowledgedVersion = NFClaimsPolicy.currentVersion
        onboarding.ageBandAcknowledged16Plus = true
        onboarding.keyboardLatencyMilliseconds = 80
        onboarding.preferredAnswerMode = .keyboard
        store.completeOnboarding(onboarding)
        XCTAssertNotNil(store.profile)
        store.updateTimingMode(.speedFocus)
        let speedPlan = store.todayPlan
        XCTAssertFalse(speedPlan.blocks.isEmpty)
        XCTAssertFalse(store.dailyPlans.isEmpty)

        store.updateTimingMode(.untimed)
        XCTAssertEqual(store.dailyPlans.count, 1)
        let untimedPlan = store.todayPlan
        XCTAssertEqual(untimedPlan.id, speedPlan.id)

        XCTAssertTrue(store.beginSession(
            lab: .mentalMath,
            source: .today,
            requestedMinutes: 5,
            isTimed: true
        ))
        XCTAssertEqual(store.activeSessionRequest?.isTimed, false)
    }

    @MainActor
    func testWeeklyMissionDeferralAndCompletionSurviveStoreReload() throws {
        let (store, container) = try makeStore()
        defer { _ = container }
        try store.saveLabAttempt(
            lab: .logicDebugging,
            itemID: "weekly-unlock",
            prompt: "Find the invariant.",
            response: "Invariant",
            correctAnswer: "Invariant",
            isCorrect: true,
            confidence: .fairlyConfident,
            evidenceClass: .practice
        )
        let mission = try XCTUnwrap(store.weeklyTransferMission)

        store.deferWeeklyTransferMission(mission)
        XCTAssertNil(store.weeklyTransferMission)
        let deferredUntil = try XCTUnwrap(
            store.weeklyTransferStateRecord?.snapshot.deferredUntilByMissionID[mission.id]
        )
        XCTAssertGreaterThan(deferredUntil, Date())

        let restored = AppStore(context: container.mainContext)
        XCTAssertNil(restored.weeklyTransferMission)
        let stateRecord = try XCTUnwrap(restored.weeklyTransferStateRecord)
        stateRecord.apply(NFWeeklyTransferState())
        try restored.context.save()
        restored.reload()
        let offeredAgain = try XCTUnwrap(restored.weeklyTransferMission)
        XCTAssertEqual(offeredAgain, mission)

        let request = SessionRequest(
            lab: .transfer,
            source: .weeklyMission,
            seed: mission.seed,
            requestedMinutes: mission.estimatedMinutes,
            evidenceClass: mission.evidenceClass,
            requestedItemCount: 4,
            planID: mission.id,
            planBlockID: mission.id,
            isTimed: false
        )
        try restored.upsertCheckpoint(
            sessionID: UUID(),
            request: request,
            currentIndex: 3,
            itemCount: 4,
            response: "",
            scratchpad: "",
            results: [true, true, false, true],
            credits: [1, 1, 0, 1],
            activeDurationSeconds: 300,
            hasCommittedCurrentItem: true,
            isComplete: true
        )
        XCTAssertNil(restored.weeklyTransferMission)
        XCTAssertEqual(restored.completedPlanBlockIDs(planID: mission.id), Set([mission.id]))

        let reloadedAfterCompletion = AppStore(context: container.mainContext)
        XCTAssertNil(reloadedAfterCompletion.weeklyTransferMission)
        XCTAssertEqual(reloadedAfterCompletion.completedPlanBlockIDs(planID: mission.id), Set([mission.id]))
    }

    @MainActor
    func testWeeklyMissionBriefPersistsDomainAndWeightedSkillTelemetry() throws {
        let (store, container) = try makeStore()
        defer { _ = container }
        let brief = NFExerciseTransferBrief(
            missionID: "nf.transfer.weekly.telemetry",
            seed: 424_242,
            kind: .numericalSimulationDebug,
            labs: [.quantitative, .logicDebugging],
            skillIDs: [TrainingLab.quantitative.skillID, TrainingLab.logicDebugging.skillID],
            requiredDimensions: ["surface_context", "interacting_variables", "response_type"]
        )
        XCTAssertTrue(store.beginSession(
            lab: .transfer,
            source: .weeklyMission,
            evidenceClass: .appliedTransfer,
            field: .dataScience,
            requestedItemCount: 4,
            seedOverride: brief.seed,
            planID: brief.missionID,
            planBlockID: brief.missionID,
            isTimed: false,
            mechanicID: "weekly.\(brief.kind.rawValue)",
            transferBrief: brief
        ))
        XCTAssertEqual(store.activeSessionRequest?.seed, brief.seed)
        XCTAssertEqual(store.activeSessionRequest?.transferBrief, brief)

        let exercise = try NFFallbackExerciseGenerator.generate(NFExerciseGenerationRequest(
            seed: brief.seed,
            index: 0,
            lab: .transfer,
            purpose: .appliedTransfer,
            sourceContext: NFExerciseSourceContext(
                primaryField: .dataScience,
                targetSkills: brief.skillIDs,
                transferBrief: brief
            ),
            targetDifficulty: 0.7
        ))
        guard case let .singleChoice(schema) = exercise.interaction else {
            return XCTFail("Numerical simulation mission must be machine-scored single choice")
        }
        let response = NFExerciseResponse.singleChoice(optionID: schema.correctOptionID)
        let result = NFExerciseScoringEngine.score(response, for: exercise)
        XCTAssertTrue(result.isCorrect)

        let attemptID = UUID()
        try store.saveExerciseAttempt(
            attemptID: attemptID,
            sessionID: UUID(),
            exercise: exercise,
            response: response,
            result: result,
            confidence: .certain,
            shownAt: Date().addingTimeInterval(-30),
            activeDuration: 30,
            source: .weeklyMission,
            planID: brief.missionID,
            planBlockID: brief.missionID,
            wasTimed: false
        )
        store.reload()

        let persisted = try XCTUnwrap(store.attempts.first { $0.id == attemptID })
        XCTAssertEqual(persisted.domainContextRaw, STEMField.dataScience.rawValue)
        XCTAssertEqual(persisted.transferBrief, brief)
        XCTAssertEqual(persisted.skillWeights, exercise.skillWeights)
        XCTAssertEqual(persisted.skillWeights[TrainingLab.transfer.skillID] ?? -1, 0.4, accuracy: 1e-12)
        XCTAssertEqual(persisted.skillWeights[TrainingLab.quantitative.skillID] ?? -1, 0.3, accuracy: 1e-12)
        XCTAssertEqual(persisted.skillWeights[TrainingLab.logicDebugging.skillID] ?? -1, 0.3, accuracy: 1e-12)

        for lab in [TrainingLab.transfer, .quantitative, .logicDebugging] {
            let summary = try XCTUnwrap(store.skillSummaries.first { $0.lab == lab })
            XCTAssertEqual(summary.evidenceCount, 0)
            XCTAssertNil(summary.accuracy)
        }
        let history = NFHistoricalPracticeProjection.reduce(attempts: [persisted.dto])
        XCTAssertEqual(history.count, 1, "A transfer response remains one historical event, regardless of its descriptive skill tags.")
        XCTAssertEqual(history.first?.labID, TrainingLab.transfer.rawValue)
        XCTAssertEqual(history.first?.legacyCount, 1)
        XCTAssertEqual(history.first?.legacyMeanCredit, 1)

        let exportURLs = try NFDataExportService.makeExports(from: store)
        defer { removeExportFolder(for: exportURLs) }
        let archive = try archiveObject(from: exportURLs)
        let attempts = try XCTUnwrap(archive["attempts"] as? [[String: Any]])
        let exported = try XCTUnwrap(attempts.first { ($0["id"] as? String) == attemptID.uuidString })
        XCTAssertEqual(exported["domainContext"] as? String, STEMField.dataScience.rawValue)
        let exportedWeights = try XCTUnwrap(exported["skillWeights"] as? [String: NSNumber])
        XCTAssertEqual(exportedWeights[TrainingLab.quantitative.skillID]?.doubleValue ?? -1, 0.3, accuracy: 1e-12)
        let exportedBrief = try XCTUnwrap(exported["transferBrief"] as? [String: Any])
        XCTAssertEqual(exportedBrief["missionID"] as? String, brief.missionID)
        XCTAssertEqual(exportedBrief["kind"] as? String, brief.kind.rawValue)
        XCTAssertEqual(exportedBrief["labs"] as? [String], brief.labs.map(\.rawValue))
        XCTAssertEqual(exportedBrief["skillIDs"] as? [String], brief.skillIDs)
        XCTAssertEqual(exportedBrief["requiredDimensions"] as? [String], brief.requiredDimensions)
    }

    @MainActor
    func testProgressSummarySeparatesSkippedRowsFromScorableAccuracy() throws {
        let (store, container) = try makeStore()
        defer { _ = container }
        try store.saveLabAttempt(
            lab: .mentalMath,
            itemID: "answered-item",
            prompt: "2 + 2",
            response: "4",
            correctAnswer: "4",
            isCorrect: true,
            confidence: .certain,
            evidenceClass: .practice
        )
        let skippedExercise = try NFFallbackExerciseGenerator.generate(
            NFExerciseGenerationRequest(seed: 77, index: 0, lab: .mentalMath, purpose: .practice)
        )
        try store.saveSkippedExercise(
            attemptID: UUID(),
            sessionID: UUID(),
            exercise: skippedExercise,
            shownAt: Date().addingTimeInterval(-3),
            activeDuration: 3,
            source: .focused
        )

        let exportURLs = try NFDataExportService.makeExports(from: store)
        defer { removeExportFolder(for: exportURLs) }
        let summaryURL = try XCTUnwrap(exportURLs.first { $0.lastPathComponent.contains("Progress-Summary") })
        let summary = try String(contentsOf: summaryURL, encoding: .utf8)
        let rows = summary.split(whereSeparator: \.isNewline).map { $0.split(separator: ",").map(String.init) }
        XCTAssertEqual(rows.first, [
            "lab", "evidence_class", "scorable_attempts", "skipped",
            "fully_correct", "earned_credit_percent", "last_activity"
        ])
        let practiceRow = try XCTUnwrap(rows.first {
            $0.count == 7
                && $0[0] == TrainingLab.mentalMath.rawValue
                && $0[1] == EvidenceClass.practice.rawValue
        })
        XCTAssertEqual(practiceRow[2], "1")
        XCTAssertEqual(practiceRow[3], "1")
        XCTAssertEqual(practiceRow[4], "1")
        XCTAssertEqual(try XCTUnwrap(Double(practiceRow[5])), 100, accuracy: 1e-12)

        let archive = try archiveObject(from: exportURLs)
        let attempts = try XCTUnwrap(archive["attempts"] as? [[String: Any]])
        XCTAssertEqual(attempts.count, 2)
        XCTAssertEqual(attempts.filter { ($0["wasSkipped"] as? Bool) == true }.count, 1)
        XCTAssertEqual(attempts.filter { ($0["wasSkipped"] as? Bool) == false }.count, 1)
    }

    @MainActor
    func testFullArchiveIncludesPlansCheckpointEventsWeeklyStateAndReports() throws {
        let (store, container) = try makeStore()
        defer { _ = container }
        _ = store.todayPlan
        store.updateReadiness(.low)
        let low = store.todayPlan

        let missionID = "nf.transfer.weekly.test"
        let deferredDate = Date(timeIntervalSince1970: 1_900_000_000)
        let weeklyRecord = WeeklyTransferStateRecord(state: NFWeeklyTransferState(
            completedMissionIDs: [missionID],
            deferredUntilByMissionID: ["nf.transfer.weekly.next": deferredDate]
        ))
        let reassessmentRecord = ReassessmentStateRecord(state: NFReassessmentState(
            completedCycle: 2,
            activeDayAnchor: deferredDate.addingTimeInterval(-28 * 86_400),
            dueAt: deferredDate.addingTimeInterval(-7 * 86_400),
            deferredUntil: deferredDate,
            targetBlock: .logicMetacognition,
            lastCompletedAt: deferredDate.addingTimeInterval(-28 * 86_400),
            lastCompletedBlock: .numericalFluency
        ))
        store.context.insert(weeklyRecord)
        store.context.insert(reassessmentRecord)
        try store.context.save()
        store.reload()

        let assessment = NFAssessmentEngine.makeBlockSession(
            block: .numericalFluency,
            phase: .initialBaseline,
            profileSeed: 303
        )
        let descriptor = try XCTUnwrap(assessment.candidatePool.first)
        let request = SessionRequest(
            lab: .mentalMath,
            source: .reassessment,
            seed: 303,
            evidenceClass: .assessmentHoldout,
            assessmentBlock: .numericalFluency,
            reassessmentCycle: 3
        )
        try store.upsertCheckpoint(
            sessionID: UUID(),
            request: request,
            currentIndex: 0,
            itemCount: assessment.itemCap,
            response: "draft",
            scratchpad: "notes",
            results: [],
            credits: [],
            assessmentDescriptorIDs: [],
            assessmentEvents: ["skipped:\(descriptor.id)"],
            activeDurationSeconds: 12
        )

        let reportedExercise = try NFFallbackExerciseGenerator.generate(
            NFExerciseGenerationRequest(seed: 404, index: 0, lab: .spatial, purpose: .practice)
        )
        try store.saveItemReport(exercise: reportedExercise, reason: "Rendering issue", note: "Labels overlap.")

        let exportURLs = try NFDataExportService.makeExports(from: store)
        defer { removeExportFolder(for: exportURLs) }
        let archive = try archiveObject(from: exportURLs)
        XCTAssertEqual((archive["archiveVersion"] as? NSNumber)?.intValue, NFDataExportService.archiveVersion)

        let plans = try XCTUnwrap(archive["dailyPlans"] as? [[String: Any]])
        XCTAssertEqual(Set(plans.compactMap { $0["id"] as? String }), Set([low.id]))

        let checkpoints = try XCTUnwrap(archive["sessionCheckpoints"] as? [[String: Any]])
        let checkpoint = try XCTUnwrap(checkpoints.first)
        XCTAssertEqual(checkpoint["assessmentEvents"] as? [String], ["skipped:\(descriptor.id)"])
        XCTAssertEqual((checkpoint["assessmentCycle"] as? NSNumber)?.intValue, 3)
        XCTAssertEqual(
            try XCTUnwrap((checkpoint["activeDurationSeconds"] as? NSNumber)?.doubleValue),
            12,
            accuracy: 1e-12
        )

        let weeklyState = try XCTUnwrap(archive["weeklyTransferState"] as? [String: Any])
        XCTAssertEqual(Set(weeklyState["completedMissionIDs"] as? [String] ?? []), Set([missionID]))
        let deferrals = try XCTUnwrap(weeklyState["deferredUntilByMissionID"] as? [String: String])
        XCTAssertNotNil(deferrals["nf.transfer.weekly.next"])

        let reassessmentState = try XCTUnwrap(archive["reassessmentState"] as? [String: Any])
        XCTAssertEqual((reassessmentState["completedCycle"] as? NSNumber)?.intValue, 2)
        XCTAssertEqual(reassessmentState["targetBlock"] as? String, NFAssessmentBlockKind.logicMetacognition.rawValue)
        XCTAssertNotNil(reassessmentState["dueAt"] as? String)
        XCTAssertNotNil(reassessmentState["deferredUntil"] as? String)

        let reports = try XCTUnwrap(archive["quarantinedReports"] as? [[String: Any]])
        XCTAssertEqual(reports.count, 1)
        XCTAssertEqual(reports.first?["itemID"] as? String, reportedExercise.id)
    }

    @MainActor
    func testDocumentDeletionRemovesSourceGroundedAttemptsAndQuarantinedReports() async throws {
        let (store, container) = try makeStore()
        defer { _ = container }
        let sourceURL = FileManager.default.temporaryDirectory
            .appending(path: "neuroforge-linked-delete-\(UUID().uuidString).txt")
        try "The control group receives no intervention.".write(to: sourceURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: sourceURL) }
        try await store.importDocumentAsync(from: sourceURL) { _ in }
        let document = try XCTUnwrap(store.documents.first)
        let chunk = try XCTUnwrap(store.chunks(for: document).first)
        let managedPath = document.localPath
        let fact = NFExerciseGroundingFact(
            id: "control-group",
            statement: "What does the control group receive?",
            expectedAnswer: "No intervention",
            acceptedAlternatives: ["nothing"],
            citationIDs: [chunk.id]
        )
        let exercise = try NFFallbackExerciseGenerator.generate(NFExerciseGenerationRequest(
            seed: 8_080,
            index: 0,
            lab: .retrieval,
            purpose: .documentPractice,
            sourceContext: NFExerciseSourceContext(
                primaryField: .lifeSciences,
                materialTitle: document.filename,
                sourceDocumentIDs: [document.id.uuidString],
                sourceChunkIDs: [chunk.id],
                groundingFacts: [fact]
            )
        ))
        XCTAssertEqual(exercise.provenance.sourceDocumentIDs, [document.id.uuidString])
        try store.saveExerciseAttempt(
            attemptID: UUID(),
            sessionID: UUID(),
            exercise: exercise,
            response: .shortText("No intervention"),
            result: makeScoringResult(for: exercise, credit: 1),
            confidence: .certain,
            shownAt: Date().addingTimeInterval(-10),
            activeDuration: 10,
            source: .focused
        )
        try store.saveItemReport(exercise: exercise, reason: "Source mismatch", note: "Review the citation.")
        XCTAssertEqual(store.attempts.count, 1)
        XCTAssertEqual(store.itemReports.count, 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: managedPath))

        try store.deleteDocument(document)

        XCTAssertFalse(FileManager.default.fileExists(atPath: managedPath))
        XCTAssertTrue(store.documents.isEmpty)
        XCTAssertTrue(store.sourceChunks.isEmpty)
        XCTAssertTrue(store.attempts.isEmpty)
        XCTAssertTrue(store.itemReports.isEmpty)
    }

    @MainActor
    func testDeleteAllClearsRuntimePlansCheckpointsWeeklyStateAndReports() throws {
        let (store, container) = try makeStore()
        defer { _ = container }
        _ = store.todayPlan
        store.updateReadiness(.low)
        _ = store.todayPlan
        let weeklyRecord = WeeklyTransferStateRecord(state: NFWeeklyTransferState(
            completedMissionIDs: ["completed-mission"]
        ))
        store.context.insert(weeklyRecord)
        try store.context.save()
        store.reload()

        let request = SessionRequest(
            lab: .logicDebugging,
            source: .today,
            seed: 515,
            planID: "test-plan",
            planBlockID: "test-block"
        )
        try store.upsertCheckpoint(
            sessionID: UUID(),
            request: request,
            currentIndex: 0,
            itemCount: 4,
            response: "draft",
            scratchpad: "notes",
            results: []
        )
        let exercise = try NFFallbackExerciseGenerator.generate(
            NFExerciseGenerationRequest(seed: 515, index: 0, lab: .logicDebugging, purpose: .practice)
        )
        try store.saveItemReport(exercise: exercise, reason: "Ambiguous", note: "Local-only report")
        try store.saveLabAttempt(
            lab: .logicDebugging,
            itemID: "delete-all-attempt",
            prompt: "Trace state",
            response: "state",
            correctAnswer: "state",
            isCorrect: true,
            confidence: .certain
        )
        XCTAssertTrue(store.beginSession(lab: .mentalMath, source: .focused, seedOverride: 999))
        XCTAssertNotNil(store.activeSessionRequest)

        try store.deleteAllLocalData()

        XCTAssertNil(store.profile)
        XCTAssertTrue(store.attempts.isEmpty)
        XCTAssertTrue(store.documents.isEmpty)
        XCTAssertTrue(store.sourceChunks.isEmpty)
        XCTAssertTrue(store.aiGenerations.isEmpty)
        XCTAssertTrue(store.itemReports.isEmpty)
        XCTAssertTrue(store.sessionCheckpoints.isEmpty)
        XCTAssertTrue(store.dailyPlans.isEmpty)
        XCTAssertNil(store.weeklyTransferStateRecord)
        XCTAssertNil(store.reassessmentStateRecord)
        XCTAssertNil(store.activeSessionRequest)
        XCTAssertEqual(store.readiness, .normal)
        XCTAssertNil(store.notice, "Store-only deletion must not announce whole-system cleanup success")
    }

    @MainActor
    private func makeStore() throws -> (store: AppStore, container: ModelContainer) {
        let schema = Schema([
            UserProfileRecord.self,
            InputCalibrationRecord.self,
            ProgressAnnotationRecord.self,
            AttemptRecord.self,
            AttemptReflectionRecord.self,
            SourceDocumentRecord.self,
            SourceChunkRecord.self,
            AIGenerationRecord.self,
            WeeklyTransferStateRecord.self,
            ReassessmentStateRecord.self,
            SessionCheckpointRecord.self,
            DailyPlanRecord.self,
            ItemReportRecord.self
        ])
        let container = try ModelContainer(
            for: schema,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let documentRoot = FileManager.default.temporaryDirectory.appending(
            path: "NF-Persistence-Runtime-Documents-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        return (
            AppStore(
                context: container.mainContext,
                documentStorageRootURL: documentRoot
            ),
            container
        )
    }

    private func makeAssessmentExercise(
        for descriptor: NFAssessmentItemDescriptor,
        index: Int
    ) throws -> NFExercise {
        try NFFallbackExerciseGenerator.generate(NFExerciseGenerationRequest(
            seed: descriptor.seed,
            index: index,
            lab: descriptor.lab,
            purpose: .baseline,
            sourceContext: NFExerciseSourceContext(
                topic: descriptor.mechanicID,
                targetSkills: [descriptor.skillID]
            ),
            targetDifficulty: descriptor.difficulty,
            preferredAssessmentFormat: descriptor.format,
            preferredAssessmentMechanicID: descriptor.mechanicID
        ))
    }

    private func makeExercise(
        for descriptor: NFAssessmentItemDescriptor,
        purpose: NFExercisePurpose
    ) throws -> NFExercise {
        try NFFallbackExerciseGenerator.generate(NFExerciseGenerationRequest(
            seed: descriptor.seed,
            index: 0,
            lab: descriptor.lab,
            purpose: purpose,
            sourceContext: NFExerciseSourceContext(
                topic: descriptor.mechanicID,
                targetSkills: [descriptor.skillID]
            ),
            targetDifficulty: descriptor.difficulty,
            preferredAssessmentFormat: descriptor.format,
            preferredAssessmentMechanicID: descriptor.mechanicID
        ))
    }

    @MainActor
    private func fillResponse(in runtime: NFUniversalSessionRuntime) {
        switch runtime.exercise.interaction {
        case let .numeric(schema):
            runtime.numericValue = String(schema.answer.value)
            runtime.numericUnit = schema.answer.canonicalUnit ?? ""
        case let .singleChoice(schema):
            runtime.singleChoiceID = schema.correctOptionID
        case let .multipleChoice(schema):
            runtime.multipleChoiceIDs = Set(schema.correctOptionIDs)
        case let .orderedSteps(schema):
            runtime.orderedStepIDs = schema.correctOrder
        case let .shortText(schema):
            runtime.shortText = schema.expectedAnswer
        case let .selfCheck(schema):
            runtime.selfCheckReflection = schema.referenceAnswer
        case let .claimEvidence(schema):
            runtime.claimSelections = Dictionary(
                uniqueKeysWithValues: schema.correctPairs.map { ($0.claimID, Set($0.evidenceIDs)) }
            )
        case let .logicState(schema):
            runtime.logicState = schema.expectedFinalState
            runtime.violatedRuleID = schema.expectedViolatedRuleID
        }
        XCTAssertTrue(runtime.canSubmit)
    }

    @MainActor
    private func assertInjectedCheckpointFailure(
        _ runtime: NFUniversalSessionRuntime,
        expectedStage: NFSessionStage,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let scratchpadBefore = runtime.scratchpad
        XCTAssertEqual(runtime.stage, expectedStage, file: file, line: line)
        XCTAssertFalse(runtime.checkpointDraft(using: {
            throw InjectedCheckpointFailure.expected
        }), file: file, line: line)
        XCTAssertEqual(runtime.stage, expectedStage, file: file, line: line)
        XCTAssertEqual(runtime.scratchpad, scratchpadBefore, file: file, line: line)
        XCTAssertNotNil(runtime.saveError, file: file, line: line)
        XCTAssertTrue(runtime.checkpointDraft(using: {}), file: file, line: line)
        XCTAssertNil(runtime.saveError, file: file, line: line)
    }

    @MainActor
    private func finishSelfCheckComparisonIfNeeded(
        _ runtime: NFUniversalSessionRuntime,
        store: AppStore
    ) {
        guard runtime.stage == .selfCheckComparison else { return }
        XCTAssertTrue(runtime.selfCheckReferenceRevealed)
        runtime.selfCheckRating = .matched
        runtime.saveSelfCheck(store: store)
    }

    private func makeScoringResult(
        for exercise: NFExercise,
        credit: Double
    ) -> NFExerciseScoringResult {
        NFExerciseScoringResult(
            exerciseID: exercise.id,
            scoringVersion: 1,
            isCorrect: credit >= 0.999,
            credit: credit,
            normalizedResponse: "supported answer",
            errorCode: credit >= 0.999 ? nil : "partial_credit",
            expectedAnswerSummary: "Supported answer",
            feedback: NFExerciseFeedback(
                title: "Recorded",
                explanation: "Deterministic test result",
                decisiveStep: nil,
                strategy: nil,
                errorCode: credit >= 0.999 ? nil : "partial_credit",
                isDelayed: exercise.feedback.timing == .afterAssessmentBlock
            )
        )
    }

    private func assertSamePlan(
        _ actual: DailyPlan,
        _ expected: DailyPlan,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(actual.id, expected.id, file: file, line: line)
        XCTAssertEqual(actual.localDayKey, expected.localDayKey, file: file, line: line)
        XCTAssertEqual(actual.seed, expected.seed, file: file, line: line)
        XCTAssertEqual(actual.policyVersion, expected.policyVersion, file: file, line: line)
        XCTAssertEqual(actual.minutes, expected.minutes, file: file, line: line)
        XCTAssertEqual(actual.blocks, expected.blocks, file: file, line: line)
    }

    private func encodedSkillWeights(_ weights: [String: Double]) -> String {
        guard let data = try? JSONEncoder().encode(weights) else { return "" }
        return String(data: data, encoding: .utf8) ?? ""
    }

    private func archiveObject(from exportURLs: [URL]) throws -> [String: Any] {
        let archiveURL = try XCTUnwrap(exportURLs.first { $0.lastPathComponent.contains("Full-Archive") })
        let data = try Data(contentsOf: archiveURL)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private func removeExportFolder(for exportURLs: [URL]) {
        guard let folder = exportURLs.first?.deletingLastPathComponent() else { return }
        try? FileManager.default.removeItem(at: folder)
    }
}


@MainActor
final class BackgroundLocalSessionStartupTests: XCTestCase {
    private final class ThreadProbe: @unchecked Sendable {
        let lock = NSLock()
        private var values: [Bool] = []
        func record() { lock.withLock { values.append(Thread.isMainThread) } }
        var ranOnlyOffMain: Bool { lock.withLock { !values.isEmpty && !values.contains(true) } }
    }
    private func location() throws -> (URL, URL) {
        let folder = FileManager.default.temporaryDirectory.appending(path: "NFBackgroundStartup-\(UUID())")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return (folder, folder.appending(path: "sessions.json"))
    }
    private func history(count: Int = 1) throws -> (NFLocalSessionRepository.Archive, NFExercise) {
        let exercise = try NFFallbackExerciseGenerator.generate(.init(seed: 20260904, index: 0, lab: .mentalMath, purpose: .practice))
        var archive = NFLocalSessionRepository.Archive()
        archive.transactionRevision = 17
        archive.snapshots = (0..<count).map { _ in .init(attemptID: UUID(), exercise: exercise) }
        return (archive, exercise)
    }
    private func malformedHistory() throws -> (Data, UUID, UUID) {
        let (archive, _) = try history(count: 2)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(archive)) as? [String: Any])
        var snapshots = object["snapshots"] as! [[String: Any]], bad = snapshots[1]["exercise"] as! [String: Any]
        bad["interaction"] = ["futureUnknownResponse": ["privateOriginal": "STARTUP_RECOVERY_CANARY"]]
        snapshots[1]["exercise"] = bad; object["snapshots"] = snapshots
        return (Data("\n ".utf8) + (try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])) + Data(" \n".utf8), archive.snapshots[0].attemptID, archive.snapshots[1].attemptID)
    }

    func testLargeAuthenticHistoryPreparesOffMainAndPublishesSameBytesRevisionAndOwner() async throws {
        let (folder, url) = try location(); defer { try? FileManager.default.removeItem(at: folder) }
        let (archive, exercise) = try history(count: 2_000), owner = UUID()
        let bytes = try JSONEncoder().encode(archive)
        XCTAssertGreaterThan(bytes.count, 1_024 * 1_024); XCTAssertLessThan(bytes.count, NFLocalSessionRepository.maximumBytes)
        try bytes.write(to: url)
        let probe = ThreadProbe()
        let prepared = try await NFLocalSessionRepository.prepareStartup(at: url, ownerDeviceID: owner) { _ in probe.record() }
        XCTAssertTrue(probe.ranOnlyOffMain)
        XCTAssertEqual(prepared.sourceDigest, NFReservationSnapshot.digest(bytes)); XCTAssertEqual(prepared.archiveRevision, 17)
        XCTAssertNil(prepared.loadError)
        let repository = try NFLocalSessionRepository.adoptPreparedStartup(prepared, at: url, ownerDeviceID: owner)
        XCTAssertEqual(repository.ownerDeviceID, owner); XCTAssertEqual(repository.archive.transactionRevision, 17)
        XCTAssertEqual(repository.archive.snapshots.map(\.attemptID), archive.snapshots.map(\.attemptID))
        XCTAssertTrue(repository.archive.snapshots.allSatisfy { $0.exercise == exercise })
        XCTAssertEqual(try Data(contentsOf: url), bytes, "Startup is read-only for the authoritative archive.")
    }

    func testCancellationReleasesRealWriterLeaseAndKeepsMainActorResponsive() async throws {
        let (folder, url) = try location(); defer { try? FileManager.default.removeItem(at: folder) }
        let (archive, _) = try history(), owner = UUID(), bytes = try JSONEncoder().encode(archive)
        try bytes.write(to: url)
        let began = XCTestExpectation(description: "Detached decode began"), release = DispatchSemaphore(value: 0)
        let probe = ThreadProbe()
        let task = Task {
            try await NFLocalSessionRepository.prepareStartup(at: url, ownerDeviceID: owner) { stage in
                probe.record()
                if case .decoding = stage { began.fulfill(); _ = release.wait(timeout: .now() + 5) }
            }
        }
        let result = await XCTWaiter.fulfillment(of: [began], timeout: 5)
        XCTAssertEqual(result, .completed)
        // This code executes on MainActor while the worker is deliberately held.
        XCTAssertTrue(Thread.isMainThread); XCTAssertTrue(probe.ranOnlyOffMain)
        task.cancel(); release.signal()
        do { _ = try await task.value; XCTFail("A cancelled prepared state must never be published.") }
        catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertEqual(try Data(contentsOf: url), bytes)
        let repository = NFLocalSessionRepository(url: url, ownerDeviceID: owner)
        try repository.dismissCorrections(["synthetic-after-cancellation"])
        XCTAssertEqual(repository.archive.transactionRevision, 18, "Cancellation must release the same lock used by real writers.")
    }

    func testPreparedLeaseBlocksRealWriterUntilAcknowledgedPublication() async throws {
        let (folder, url) = try location(); defer { try? FileManager.default.removeItem(at: folder) }
        let (archive, _) = try history(), owner = UUID(), bytes = try JSONEncoder().encode(archive)
        try bytes.write(to: url)
        let original = NFLocalSessionRepository(url: url, ownerDeviceID: owner)
        let prepared = try await NFLocalSessionRepository.prepareStartup(at: url, ownerDeviceID: owner)
        XCTAssertThrowsError(try original.dismissCorrections(["synthetic-concurrent"])) {
            guard case NFLocalSessionRepository.RepositoryError.busy = $0 else { return XCTFail("Expected the actual repository writer lock: \($0)") }
        }
        XCTAssertEqual(original.archive.transactionRevision, 17); XCTAssertEqual(try Data(contentsOf: url), bytes)
        let adopted = try NFLocalSessionRepository.adoptPreparedStartup(prepared, at: url, ownerDeviceID: owner)
        try adopted.dismissCorrections(["synthetic-after-adoption"])
        XCTAssertEqual(adopted.archive.transactionRevision, 18)
        XCTAssertThrowsError(try NFLocalSessionRepository.adoptPreparedStartup(prepared, at: url, ownerDeviceID: owner), "A released receipt cannot be adopted twice.")
    }

    func testWrongOwnerStaleLaunchAndSameRevisionReplacedFileCannotPublish() async throws {
        let (folder, url) = try location(); defer { try? FileManager.default.removeItem(at: folder) }
        let (archive, _) = try history(), owner = UUID(), bytes = try JSONEncoder().encode(archive)
        try bytes.write(to: url)
        let wrongOwner = try await NFLocalSessionRepository.prepareStartup(at: url, ownerDeviceID: owner)
        XCTAssertThrowsError(try NFLocalSessionRepository.adoptPreparedStartup(wrongOwner, at: url, ownerDeviceID: UUID())) {
            guard case NFLocalSessionRepository.RepositoryError.wrongOwner = $0 else { return XCTFail("Wrong owner must be rejected.") }
        }
        let obsolete = try await NFLocalSessionRepository.prepareStartup(at: url, ownerDeviceID: owner)
        XCTAssertThrowsError(try NFLocalSessionRepository.adoptPreparedStartup(obsolete, at: url, ownerDeviceID: owner, isCurrentLaunch: { false })) {
            XCTAssertTrue($0 is CancellationError)
        }
        let stale = try await NFLocalSessionRepository.prepareStartup(at: url, ownerDeviceID: owner)
        var changed = archive; changed.dismissedCorrectionIDs = ["synthetic-uncoordinated-change"]
        let replacement = try JSONEncoder().encode(changed)
        try replacement.write(to: url, options: .atomic) // Simulates an external writer that ignores the advisory protocol.
        XCTAssertThrowsError(try NFLocalSessionRepository.adoptPreparedStartup(stale, at: url, ownerDeviceID: owner)) {
            guard case NFLocalSessionRepository.RepositoryError.staleRevision = $0 else { return XCTFail("Same revision with different original bytes must be stale.") }
        }
        XCTAssertEqual(try Data(contentsOf: url), replacement)
        let latest = try await NFLocalSessionRepository.prepareStartup(at: url, ownerDeviceID: owner)
        XCTAssertNotEqual(latest.sourceDigest, stale.sourceDigest)
        let repository = try NFLocalSessionRepository.adoptPreparedStartup(latest, at: url, ownerDeviceID: owner)
        XCTAssertEqual(repository.archive.dismissedCorrectionIDs, changed.dismissedCorrectionIDs)
    }

    func testGranularRecoveryBacksUpExactOriginalBeforeAdoptionAndFailedAdoptionPreservesIt() async throws {
        let (folder, url) = try location(); defer { try? FileManager.default.removeItem(at: folder) }
        let (bytes, good, bad) = try malformedHistory(), owner = UUID()
        try bytes.write(to: url)
        let prepared = try await NFLocalSessionRepository.prepareStartup(at: url, ownerDeviceID: owner)
        XCTAssertNil(prepared.loadError)
        let directory = url.appendingPathExtension("history-recovery")
        let backup = try XCTUnwrap(FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil).first)
        XCTAssertEqual(try Data(contentsOf: backup), bytes)
        XCTAssertThrowsError(try NFLocalSessionRepository.adoptPreparedStartup(prepared, at: url, ownerDeviceID: owner, isCurrentLaunch: { false }))
        XCTAssertEqual(try Data(contentsOf: backup), bytes); XCTAssertEqual(try Data(contentsOf: url), bytes)
        let retry = try await NFLocalSessionRepository.prepareStartup(at: url, ownerDeviceID: owner)
        let repository = try NFLocalSessionRepository.adoptPreparedStartup(retry, at: url, ownerDeviceID: owner)
        XCTAssertEqual(repository.archive.snapshots.map(\.attemptID), [good])
        XCTAssertEqual(repository.archive.unavailableHistorySnapshots?.map(\.attemptID), [bad])
        XCTAssertFalse(String(decoding: try JSONEncoder().encode(repository.exportArchive), as: UTF8.self).contains("STARTUP_RECOVERY_CANARY"))
        XCTAssertEqual(try Data(contentsOf: backup), bytes)
    }

    func testFailedOriginalBackupAndFutureArchiveRemainRecoveryOnlyWithoutRewritingBytes() async throws {
        let (folder, url) = try location(); defer { try? FileManager.default.removeItem(at: folder) }
        let (bytes, _, _) = try malformedHistory(), owner = UUID()
        try bytes.write(to: url)
        let blocked = url.appendingPathExtension("history-recovery")
        try Data("Do not replace this original fixture".utf8).write(to: blocked)
        let prepared = try await NFLocalSessionRepository.prepareStartup(at: url, ownerDeviceID: owner)
        XCTAssertNotNil(prepared.loadError)
        let repository = try NFLocalSessionRepository.adoptPreparedStartup(prepared, at: url, ownerDeviceID: owner)
        XCTAssertEqual(repository.archive.snapshots.count, 1); XCTAssertNotNil(repository.loadError)
        XCTAssertThrowsError(try repository.dismissCorrections(["must-not-write"]))
        XCTAssertEqual(try Data(contentsOf: url), bytes)
        var future = NFLocalSessionRepository.Archive(); future.schemaVersion = 999
        let futureBytes = try JSONEncoder().encode(future); try futureBytes.write(to: url, options: .atomic)
        let unknown = try await NFLocalSessionRepository.prepareStartup(at: url, ownerDeviceID: owner)
        XCTAssertNotNil(unknown.loadError)
        _ = try NFLocalSessionRepository.adoptPreparedStartup(unknown, at: url, ownerDeviceID: owner)
        XCTAssertEqual(try Data(contentsOf: url), futureBytes)
    }

    func testOversizedSymlinkAndFIFOInputsNeverDecodeOrReplaceOriginal() async throws {
        let (folder, url) = try location(); defer { try? FileManager.default.removeItem(at: folder) }
        FileManager.default.createFile(atPath: url.path, contents: nil)
        let file = try FileHandle(forWritingTo: url)
        try file.truncate(atOffset: UInt64(NFLocalSessionRepository.maximumBytes + 1)); try file.close()
        let prepared = try await NFLocalSessionRepository.prepareStartup(at: url, ownerDeviceID: UUID())
        XCTAssertNotNil(prepared.loadError); XCTAssertNil(prepared.sourceDigest); prepared.discard()
        XCTAssertEqual(try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber, NSNumber(value: NFLocalSessionRepository.maximumBytes + 1))
        try FileManager.default.removeItem(at: url)
        let target = folder.appending(path: "original.txt"), canary = Data("Original source stays unchanged".utf8)
        try canary.write(to: target); try FileManager.default.createSymbolicLink(at: url, withDestinationURL: target)
        do { _ = try await NFLocalSessionRepository.prepareStartup(at: url, ownerDeviceID: UUID()); XCTFail("Symlink must not be followed.") } catch {}
        XCTAssertEqual(try Data(contentsOf: target), canary)
        try FileManager.default.removeItem(at: url)
        XCTAssertEqual(mkfifo(url.path, S_IRUSR | S_IWUSR), 0)
        do { _ = try await NFLocalSessionRepository.prepareStartup(at: url, ownerDeviceID: UUID()); XCTFail("FIFO must not be opened for reading.") } catch {}
        var info = stat(); XCTAssertEqual(lstat(url.path, &info), 0); XCTAssertEqual(info.st_mode & S_IFMT, S_IFIFO)
    }

    func testMissingArchiveAndReplacedLockIdentityCannotBeMistakenForVerifiedInput() async throws {
        let (folder, url) = try location(); defer { try? FileManager.default.removeItem(at: folder) }
        let owner = UUID()
        let missing = try await NFLocalSessionRepository.prepareStartup(at: url, ownerDeviceID: owner)
        XCTAssertNil(missing.sourceDigest); XCTAssertNil(missing.archiveRevision); XCTAssertNil(missing.loadError)
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
        let bytes = try JSONEncoder().encode(NFLocalSessionRepository.Archive())
        try bytes.write(to: url)
        XCTAssertThrowsError(try NFLocalSessionRepository.adoptPreparedStartup(missing, at: url, ownerDeviceID: owner))
        XCTAssertEqual(try Data(contentsOf: url), bytes)
        let prepared = try await NFLocalSessionRepository.prepareStartup(at: url, ownerDeviceID: owner)
        let lock = URL(fileURLWithPath: url.path + ".lock")
        try FileManager.default.moveItem(at: lock, to: folder.appending(path: "original.lock"))
        try Data().write(to: lock)
        XCTAssertThrowsError(try NFLocalSessionRepository.adoptPreparedStartup(prepared, at: url, ownerDeviceID: owner)) {
            guard case NFLocalSessionRepository.RepositoryError.staleRevision = $0 else { return XCTFail("Adoption must use the same live lock identity as writers.") }
        }
        XCTAssertEqual(try Data(contentsOf: url), bytes)
        let fresh = try await NFLocalSessionRepository.prepareStartup(at: url, ownerDeviceID: owner)
        let repository = try NFLocalSessionRepository.adoptPreparedStartup(fresh, at: url, ownerDeviceID: owner)
        try repository.dismissCorrections(["fresh-lock-accepted"])
        XCTAssertEqual(repository.archive.transactionRevision, 1)
    }

    func testStartupSourceWiresAwaitedPreparationAfterColdReplayAndBeforeAppStore() throws {
        let sourceURL = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appending(path: "Sources/App/NeuroForgeApp.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)
        let production = try XCTUnwrap(source.range(of: "let recovery = try await NFRestoreColdCoordinator.recover"))
        let load = try XCTUnwrap(source.range(of: "localRepository = try await NFLocalSessionRepository.loadForDurableStore"))
        let appStore = try XCTUnwrap(source.range(of: "let appStore = AppStore(context: container.mainContext, localSessionRepository: localRepository)"))
        XCTAssertLessThan(production.lowerBound, load.lowerBound); XCTAssertLessThan(load.lowerBound, appStore.lowerBound)
        XCTAssertFalse(source[load.upperBound..<appStore.lowerBound].contains("forDurableStore(at:"))
    }
}

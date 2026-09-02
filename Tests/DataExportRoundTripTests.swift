import Foundation
import SwiftData
import XCTest

@testable import NeuroForge

final class DataExportRoundTripTests: XCTestCase {
    @MainActor
    func testFullArchiveRoundTripHarnessPreservesEveryRecordCountAndIdentity() async throws {
        let (store, container) = try makeStore()
        defer { _ = container }

        try store.saveLabAttempt(
            lab: .logicDebugging,
            itemID: "round-trip-attempt",
            prompt: "Find the first invalid state.",
            response: "state 3",
            correctAnswer: "state 3",
            isCorrect: true,
            confidence: .certain
        )
        let attempt = try XCTUnwrap(store.attempts.first)
        try store.saveAttemptReflection(
            attemptID: attempt.id,
            deterministicErrorCode: nil,
            selectedErrorCode: .other,
            trigger: .highConfidenceError,
            note: "Identity-preserving export fixture."
        )

        let stateDate = Date(timeIntervalSince1970: 1_800_000_000)
        try store.saveProgressAnnotation(
            startDate: stateDate,
            endDate: stateDate,
            note: "Included export fixture.",
            includeInExport: true
        )
        try store.saveProgressAnnotation(
            startDate: stateDate.addingTimeInterval(86_400),
            endDate: stateDate.addingTimeInterval(86_400),
            note: "Excluded export fixture.",
            includeInExport: false
        )
        try store.saveInputCalibration(
            preferredAnswerMode: .keyboard,
            keyboardLatencyMilliseconds: 145,
            touchLatencyMilliseconds: nil,
            pencilLatencyMilliseconds: nil
        )
        let authoringRequest = NFAuthoringRequest(
            capability: .contextualize,
            lab: .logicDebugging,
            field: .computing,
            customTopic: "finite state machines",
            learningObjective: "trace the first invalid transition",
            style: .debugging,
            difficulty: 0.65,
            count: 1,
            seed: 5151,
            aiMode: .disabled
        )
        let authoringResult = try await NFAuthoringEngine.shared.author(authoringRequest)
        try store.saveAIGeneration(request: authoringRequest, result: authoringResult)
        container.mainContext.insert(WeeklyTransferStateRecord(state: NFWeeklyTransferState(
            completedMissionIDs: ["mission.round-trip"],
            deferredUntilByMissionID: ["mission.deferred": stateDate]
        )))
        container.mainContext.insert(ReassessmentStateRecord(state: NFReassessmentState(
            completedCycle: 2,
            activeDayAnchor: stateDate,
            dueAt: stateDate.addingTimeInterval(86_400),
            deferredUntil: nil,
            targetBlock: .scientificDataReasoning,
            lastCompletedAt: stateDate,
            lastCompletedBlock: .numericalFluency
        )))
        container.mainContext.insert(SessionCheckpointRecord(
            sessionID: UUID(uuidString: "AAE5FF55-71DA-4A7A-9282-7C06413C2C35")!,
            lab: .logicDebugging,
            source: .focused,
            seed: 5152,
            currentIndex: 1,
            itemCount: 3,
            response: "state 3",
            scratchpad: "bounded fixture",
            results: [true],
            credits: [1],
            evidenceClass: .practice
        ))

        let document = SourceDocumentRecord(
            filename: "round-trip.md",
            typeIdentifier: "net.daringfireball.markdown",
            sizeBytes: 32,
            localPath: "/private/round-trip.md"
        )
        container.mainContext.insert(document)
        let chunk = SourceChunkRecord(chunk: NFSourceChunk(
            id: "chunk.round-trip",
            documentID: document.id,
            documentVersion: NFSourceExtractor.extractorVersion,
            sourceName: document.filename,
            locator: NFSourceLocator(page: nil, lineStart: 1, lineEnd: 2, section: "Methods"),
            text: "A bounded fixture preserves stable identities.",
            contentHash: "fixture-hash",
            ordinal: 0
        ))
        container.mainContext.insert(chunk)
        _ = store.todayPlan

        let exercise = try NFFallbackExerciseGenerator.generate(
            NFExerciseGenerationRequest(seed: 5150, index: 0, lab: .logicDebugging, purpose: .practice)
        )
        try store.saveItemReport(exercise: exercise, reason: "Round-trip fixture", note: "")
        try container.mainContext.save()
        store.reload()

        let exports = try NFDataExportService.makeExports(from: store)
        defer { try? FileManager.default.removeItem(at: exports[0].deletingLastPathComponent()) }
        let archiveURL = try XCTUnwrap(exports.first { $0.lastPathComponent == "NeuroForge-Full-Archive.json" })
        let restored = try NFDataExportRoundTripValidator.decodeArchive(at: archiveURL)

        XCTAssertEqual(restored.archiveVersion, NFDataExportService.archiveVersion)
        XCTAssertEqual(restored.profileID, store.profile?.id)
        XCTAssertEqual(restored.attemptIDs, Set(store.attemptRecordsForExport.map(\.id)))
        XCTAssertEqual(restored.attemptReflectionIDs, Set(store.attemptReflections.map(\.id)))
        XCTAssertEqual(restored.documentIDs, Set(store.documents.map(\.id)))
        XCTAssertEqual(restored.sourceChunkIDs, Set(store.sourceChunks.map(\.id)))
        XCTAssertEqual(restored.aiGenerationIDs, Set(store.aiGenerations.map(\.id)))
        XCTAssertEqual(restored.sessionCheckpointIDs, Set(store.sessionCheckpoints.map(\.id)))
        XCTAssertEqual(restored.dailyPlanIDs, Set(store.dailyPlans.map(\.id)))
        XCTAssertEqual(restored.inputCalibrationIDs, Set(store.inputCalibrations.map(\.id)))
        XCTAssertEqual(
            restored.progressAnnotationIDs,
            Set(store.progressAnnotations.filter(\.includeInExport).map(\.id))
        )
        XCTAssertEqual(
            restored.excludedPrivateAnnotationCount,
            store.progressAnnotations.filter { !$0.includeInExport }.count
        )
        XCTAssertEqual(restored.weeklyTransferState, store.weeklyTransferStateRecord?.snapshot)
        XCTAssertEqual(restored.reassessmentState, store.reassessmentStateRecord?.snapshot)
        XCTAssertEqual(restored.adaptivePlanChangeIDs, Set(store.adaptivePlanHistory.map(\.id)))
        XCTAssertEqual(restored.quarantinedReportIDs, Set(store.itemReports.map(\.id)))

        let archiveData = try Data(contentsOf: archiveURL)
        var archiveObject = try XCTUnwrap(
            JSONSerialization.jsonObject(with: archiveData) as? [String: Any]
        )
        archiveObject["archiveVersion"] = NFDataExportService.oldestRestorableArchiveVersion - 1
        let invalidVersionURL = archiveURL.deletingLastPathComponent()
            .appending(path: "NeuroForge-Invalid-Version.json")
        try JSONSerialization.data(withJSONObject: archiveObject).write(to: invalidVersionURL)
        XCTAssertThrowsError(try NFDataExportRoundTripValidator.decodeArchive(at: invalidVersionURL)) {
            XCTAssertEqual(
                $0 as? NFDataArchiveValidationError,
                .unsupportedArchiveVersion(NFDataExportService.oldestRestorableArchiveVersion - 1)
            )
        }

        archiveObject["archiveVersion"] = NFDataExportService.archiveVersion
        var duplicatedAttempts = try XCTUnwrap(archiveObject["attempts"] as? [[String: Any]])
        duplicatedAttempts.append(try XCTUnwrap(duplicatedAttempts.first))
        archiveObject["attempts"] = duplicatedAttempts
        let duplicateIdentityURL = archiveURL.deletingLastPathComponent()
            .appending(path: "NeuroForge-Duplicate-Identity.json")
        try JSONSerialization.data(withJSONObject: archiveObject).write(to: duplicateIdentityURL)
        XCTAssertThrowsError(try NFDataExportRoundTripValidator.decodeArchive(at: duplicateIdentityURL)) {
            XCTAssertEqual(
                $0 as? NFDataArchiveValidationError,
                .duplicateIdentity(category: "attempts")
            )
        }
    }

    @MainActor
    func testRestoreIsPreviewedConflictAwareAndDoesNotDuplicateRecords() async throws {
        let sourceHistoryURL = FileManager.default.temporaryDirectory
            .appending(path: "NF-Restore-Source-History-\(UUID().uuidString).json")
        let (source, sourceContainer) = try makeStore(historyURL: sourceHistoryURL)
        defer {
            _ = sourceContainer
            try? FileManager.default.removeItem(at: sourceHistoryURL)
        }
        XCTAssertTrue(source.completeOnboarding(OnboardingDraft()))
        try source.saveLabAttempt(
            lab: .transfer,
            itemID: "restore.transfer.fixture",
            prompt: "Map the invariant to a new representation.",
            response: "Map structure, then recheck constraints.",
            correctAnswer: "Map structure, then recheck constraints.",
            isCorrect: true,
            confidence: .fairlyConfident,
            evidenceClass: .appliedTransfer
        )
        _ = source.todayPlan
        let exports = try NFDataExportService.makeExports(from: source)
        defer { try? FileManager.default.removeItem(at: exports[0].deletingLastPathComponent()) }
        let archiveURL = try XCTUnwrap(exports.first { $0.lastPathComponent == "NeuroForge-Full-Archive.json" })

        let destinationHistoryURL = FileManager.default.temporaryDirectory
            .appending(path: "NF-Restore-Destination-History-\(UUID().uuidString).json")
        let (destination, destinationContainer) = try makeStore(historyURL: destinationHistoryURL)
        defer {
            _ = destinationContainer
            try? FileManager.default.removeItem(at: destinationHistoryURL)
        }

        let initialPreview = try NFDataArchiveRestoreService.preview(archiveAt: archiveURL, into: destination)
        XCTAssertFalse(initialPreview.hasConflicts)
        XCTAssertEqual(initialPreview.incoming[.attempts], 1)
        XCTAssertGreaterThanOrEqual(initialPreview.incoming[.adaptiveHistory], 1)

        let result = try NFDataArchiveRestoreService.restore(
            archiveAt: archiveURL,
            into: destination,
            policy: .abortOnConflict
        )
        XCTAssertEqual(result.restored[.attempts], 1)
        XCTAssertEqual(Set(destination.attempts.map(\.id)), Set(source.attempts.map(\.id)))
        XCTAssertEqual(Set(destination.dailyPlans.map(\.id)), Set(source.dailyPlans.map(\.id)))
        XCTAssertEqual(Set(destination.adaptivePlanHistory.map(\.id)), Set(source.adaptivePlanHistory.map(\.id)))

        let conflictingPreview = try NFDataArchiveRestoreService.preview(archiveAt: archiveURL, into: destination)
        XCTAssertTrue(conflictingPreview.hasConflicts)
        XCTAssertThrowsError(try NFDataArchiveRestoreService.restore(
            archiveAt: archiveURL,
            into: destination,
            policy: .abortOnConflict
        )) {
            guard case .conflictsRequireDecision = $0 as? NFDataArchiveRestoreError else {
                return XCTFail("Expected an explicit conflict decision, got \($0)")
            }
        }

        let kept = try NFDataArchiveRestoreService.restore(
            archiveAt: archiveURL,
            into: destination,
            policy: .keepExisting
        )
        XCTAssertEqual(kept.skipped[.attempts], 1)
        XCTAssertEqual(destination.attempts.count, 1)

        try destination.saveLabAttempt(
            lab: .logicDebugging,
            itemID: "destination-only",
            prompt: "Destination-only record",
            response: "A",
            correctAnswer: "A",
            isCorrect: true,
            confidence: .certain
        )
        XCTAssertEqual(destination.attempts.count, 2)
        _ = try NFDataArchiveRestoreService.restore(
            archiveAt: archiveURL,
            into: destination,
            policy: .replaceAll
        )
        XCTAssertEqual(Set(destination.attempts.map(\.id)), Set(source.attempts.map(\.id)))
    }

    @MainActor
    func testReplaceAllRejectsReferencesThatOnlyExistInDestination() throws {
        let (source, sourceContainer) = try makeStore()
        defer { _ = sourceContainer }
        XCTAssertTrue(source.completeOnboarding(OnboardingDraft()))
        try source.saveLabAttempt(
            lab: .logicDebugging,
            itemID: "reference-source",
            prompt: "Source attempt",
            response: "A",
            correctAnswer: "A",
            isCorrect: true,
            confidence: .certain
        )
        let sourceAttempt = try XCTUnwrap(source.attempts.first)
        try source.saveAttemptReflection(
            attemptID: sourceAttempt.id,
            deterministicErrorCode: nil,
            selectedErrorCode: .other,
            trigger: .highConfidenceError,
            note: "Reference policy fixture."
        )
        let exports = try NFDataExportService.makeExports(from: source)
        defer { try? FileManager.default.removeItem(at: exports[0].deletingLastPathComponent()) }
        let archiveURL = try XCTUnwrap(exports.first { $0.lastPathComponent == "NeuroForge-Full-Archive.json" })

        let (destination, destinationContainer) = try makeStore()
        defer { _ = destinationContainer }
        try destination.saveLabAttempt(
            lab: .mentalMath,
            itemID: "destination-only-attempt",
            prompt: "Destination attempt",
            response: "2",
            correctAnswer: "2",
            isCorrect: true,
            confidence: .certain
        )
        let destinationAttemptID = try XCTUnwrap(destination.attempts.first?.id)

        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(contentsOf: archiveURL)) as? [String: Any]
        )
        object["attempts"] = []
        var reflections = try XCTUnwrap(object["attemptReflections"] as? [[String: Any]])
        reflections[0]["attemptID"] = destinationAttemptID.uuidString
        object["attemptReflections"] = reflections
        let mutatedURL = archiveURL.deletingLastPathComponent().appending(path: "Destination-Reference.json")
        try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]).write(to: mutatedURL)

        // A preview (and a merge) may use a retained destination record.
        XCTAssertNoThrow(try NFDataArchiveRestoreService.preview(archiveAt: mutatedURL, into: destination))
        XCTAssertThrowsError(try NFDataArchiveRestoreService.restore(
            archiveAt: mutatedURL,
            into: destination,
            policy: .replaceAll
        )) { error in
            XCTAssertEqual(
                error as? NFDataArchiveRestoreError,
                .invalidArchive("a reflection references a missing attempt")
            )
        }
        XCTAssertEqual(destination.attempts.map(\.id), [destinationAttemptID])
        XCTAssertTrue(destination.attemptReflections.isEmpty)

        let merged = try NFDataArchiveRestoreService.restore(
            archiveAt: mutatedURL,
            into: destination,
            policy: .keepExisting
        )
        XCTAssertEqual(merged.restored[.reflections], 1)
        XCTAssertEqual(destination.attemptReflections.first?.attemptID, destinationAttemptID)
    }

    @MainActor
    func testReplaceMatchingRejectsEveryRetainedProfileChildThatWouldBeOrphaned() throws {
        enum RetainedProfileChild: CaseIterable {
            case dailyPlan
            case inputCalibration
            case adaptiveHistory
        }

        let sourceHistoryURL = FileManager.default.temporaryDirectory
            .appending(path: "NF-Restore-Profile-Source-\(UUID().uuidString).json")
        let (source, sourceContainer) = try makeStore(historyURL: sourceHistoryURL)
        defer {
            _ = sourceContainer
            try? FileManager.default.removeItem(at: sourceHistoryURL)
        }
        XCTAssertTrue(source.completeOnboarding(OnboardingDraft()))
        let incomingProfileID = try XCTUnwrap(source.profile?.id)
        let exports = try NFDataExportService.makeExports(from: source)
        defer { try? FileManager.default.removeItem(at: exports[0].deletingLastPathComponent()) }
        let archiveURL = try XCTUnwrap(exports.first { $0.lastPathComponent == "NeuroForge-Full-Archive.json" })

        for child in RetainedProfileChild.allCases {
            let historyURL = FileManager.default.temporaryDirectory
                .appending(path: "NF-Restore-Profile-Child-\(UUID().uuidString).json")
            let (destination, destinationContainer) = try makeStore(historyURL: historyURL)
            defer {
                _ = destinationContainer
                try? FileManager.default.removeItem(at: historyURL)
            }

            let destinationProfile = UserProfileRecord(draft: OnboardingDraft())
            destinationContainer.mainContext.insert(destinationProfile)
            try destinationContainer.mainContext.save()
            destination.reload()
            let originalProfileID = try XCTUnwrap(destination.profile?.id)
            XCTAssertNotEqual(originalProfileID, incomingProfileID)

            let expectedErrorReason: String
            switch child {
            case .dailyPlan:
                _ = destination.todayPlan
                // Isolate the SwiftData child from the history entry created
                // as a normal side effect of plan materialization.
                try destination.replaceAdaptivePlanHistoryForRestore([])
                expectedErrorReason = "the selected conflict policy would retain a daily plan whose profile is removed"
            case .inputCalibration:
                try destination.saveInputCalibration(
                    preferredAnswerMode: .keyboard,
                    keyboardLatencyMilliseconds: 120,
                    touchLatencyMilliseconds: nil,
                    pencilLatencyMilliseconds: nil
                )
                expectedErrorReason = "the selected conflict policy would retain an input calibration whose profile is removed"
            case .adaptiveHistory:
                try destination.replaceAdaptivePlanHistoryForRestore([
                    NFAdaptivePlanChangeRecord(
                        profileID: originalProfileID,
                        kind: .preferencesApplied,
                        title: "Retained history fixture",
                        newState: "Original profile",
                        reason: "Verifies final-state profile references."
                    )
                ])
                expectedErrorReason = "the selected conflict policy would retain adaptive history whose profile is removed"
            }

            let originalPlanIDs = Set(destination.dailyPlans.map(\.id))
            let originalCalibrationIDs = Set(destination.inputCalibrations.map(\.id))
            let originalHistory = destination.adaptivePlanHistory

            // Preview may describe either merge choice; replaceMatching must
            // validate the state that its concrete policy would leave behind.
            XCTAssertNoThrow(try NFDataArchiveRestoreService.preview(archiveAt: archiveURL, into: destination))
            XCTAssertThrowsError(try NFDataArchiveRestoreService.restore(
                archiveAt: archiveURL,
                into: destination,
                policy: .replaceMatching
            )) { error in
                XCTAssertEqual(
                    error as? NFDataArchiveRestoreError,
                    .invalidArchive(expectedErrorReason)
                )
            }
            XCTAssertEqual(destination.profile?.id, originalProfileID)
            XCTAssertEqual(Set(destination.dailyPlans.map(\.id)), originalPlanIDs)
            XCTAssertEqual(Set(destination.inputCalibrations.map(\.id)), originalCalibrationIDs)
            XCTAssertEqual(destination.adaptivePlanHistory, originalHistory)
            XCTAssertEqual(try NFAdaptivePlanHistoryRepository(fileURL: historyURL).load(), originalHistory)
        }
    }

    @MainActor
    func testReplaceAllClearsAdaptiveHistoryWhenArchiveHistoryIsEmpty() throws {
        let (source, sourceContainer) = try makeStore()
        defer { _ = sourceContainer }
        try source.saveLabAttempt(
            lab: .mentalMath,
            itemID: "history-empty-source",
            prompt: "1 + 1",
            response: "2",
            correctAnswer: "2",
            isCorrect: true,
            confidence: .certain
        )
        XCTAssertTrue(source.adaptivePlanHistory.isEmpty)
        let exports = try NFDataExportService.makeExports(from: source)
        defer { try? FileManager.default.removeItem(at: exports[0].deletingLastPathComponent()) }
        let archiveURL = try XCTUnwrap(exports.first { $0.lastPathComponent == "NeuroForge-Full-Archive.json" })

        let historyURL = FileManager.default.temporaryDirectory
            .appending(path: "NF-Restore-Empty-History-\(UUID().uuidString).json")
        let (destination, destinationContainer) = try makeStore(historyURL: historyURL)
        defer {
            _ = destinationContainer
            try? FileManager.default.removeItem(at: historyURL)
        }
        XCTAssertTrue(destination.completeOnboarding(OnboardingDraft()))
        _ = destination.todayPlan
        XCTAssertFalse(destination.adaptivePlanHistory.isEmpty)

        let result = try NFDataArchiveRestoreService.restore(
            archiveAt: archiveURL,
            into: destination,
            policy: .replaceAll
        )
        XCTAssertEqual(result.restored[.adaptiveHistory], 0)
        XCTAssertTrue(destination.adaptivePlanHistory.isEmpty)
        XCTAssertTrue(try NFAdaptivePlanHistoryRepository(fileURL: historyURL).load().isEmpty)
    }

    @MainActor
    func testHistoryWriteFailureHappensBeforeAnyCoreRecordIsCommitted() throws {
        let (source, sourceContainer) = try makeStore()
        defer { _ = sourceContainer }
        XCTAssertTrue(source.completeOnboarding(OnboardingDraft()))
        _ = source.todayPlan
        XCTAssertFalse(source.adaptivePlanHistory.isEmpty)
        let exports = try NFDataExportService.makeExports(from: source)
        defer { try? FileManager.default.removeItem(at: exports[0].deletingLastPathComponent()) }
        let archiveURL = try XCTUnwrap(exports.first { $0.lastPathComponent == "NeuroForge-Full-Archive.json" })

        let unwritableHistoryURL = FileManager.default.temporaryDirectory
            .appending(path: "NF-Restore-History-Is-Directory-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: unwritableHistoryURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: unwritableHistoryURL) }
        let (destination, destinationContainer) = try makeStore(historyURL: unwritableHistoryURL)
        defer { _ = destinationContainer }
        try destination.saveLabAttempt(
            lab: .logicDebugging,
            itemID: "must-survive-history-failure",
            prompt: "Keep me",
            response: "A",
            correctAnswer: "A",
            isCorrect: true,
            confidence: .certain
        )
        let originalAttemptIDs = destination.attempts.map(\.id)

        XCTAssertThrowsError(try NFDataArchiveRestoreService.restore(
            archiveAt: archiveURL,
            into: destination,
            policy: .replaceAll
        )) { error in
            XCTAssertEqual(error as? NFDataArchiveRestoreError, .persistenceFailed)
        }
        XCTAssertEqual(destination.attempts.map(\.id), originalAttemptIDs)
        XCTAssertNil(destination.profile)
    }

    @MainActor
    func testCorePersistenceFailureRollsBackModelsAndCompensatesAdaptiveHistory() throws {
        let (source, sourceContainer) = try makeStore()
        defer { _ = sourceContainer }
        XCTAssertTrue(source.completeOnboarding(OnboardingDraft()))
        _ = source.todayPlan
        try source.saveLabAttempt(
            lab: .transfer,
            itemID: "incoming-core-record",
            prompt: "Incoming",
            response: "A",
            correctAnswer: "A",
            isCorrect: true,
            confidence: .certain
        )
        let exports = try NFDataExportService.makeExports(from: source)
        defer { try? FileManager.default.removeItem(at: exports[0].deletingLastPathComponent()) }
        let archiveURL = try XCTUnwrap(exports.first { $0.lastPathComponent == "NeuroForge-Full-Archive.json" })

        let historyURL = FileManager.default.temporaryDirectory
            .appending(path: "NF-Restore-Compensated-History-\(UUID().uuidString).json")
        let (destination, destinationContainer) = try makeStore(historyURL: historyURL)
        defer {
            _ = destinationContainer
            try? FileManager.default.removeItem(at: historyURL)
        }
        XCTAssertTrue(destination.completeOnboarding(OnboardingDraft()))
        _ = destination.todayPlan
        try destination.saveLabAttempt(
            lab: .logicDebugging,
            itemID: "original-core-record",
            prompt: "Original",
            response: "B",
            correctAnswer: "B",
            isCorrect: true,
            confidence: .certain
        )
        let originalAttemptIDs = Set(destination.attempts.map(\.id))
        let originalHistory = destination.adaptivePlanHistory

        XCTAssertThrowsError(try NFDataArchiveRestoreService.restore(
            archiveAt: archiveURL,
            into: destination,
            policy: .replaceAll,
            corePersistence: { _ in throw InjectedCorePersistenceError() }
        )) { error in
            XCTAssertEqual(error as? NFDataArchiveRestoreError, .persistenceFailed)
        }
        XCTAssertEqual(Set(destination.attempts.map(\.id)), originalAttemptIDs)
        XCTAssertEqual(destination.adaptivePlanHistory, originalHistory)
        XCTAssertEqual(try NFAdaptivePlanHistoryRepository(fileURL: historyURL).load(), originalHistory)
    }

    @MainActor
    func testHistoricalArchiveMigrationsRestoreV14ThroughV16CheckpointFixtures() throws {
        let (source, sourceContainer) = try makeStore()
        defer { _ = sourceContainer }
        XCTAssertTrue(source.completeOnboarding(OnboardingDraft()))
        _ = source.todayPlan
        try source.saveLabAttempt(
            lab: .logicDebugging,
            itemID: "historical-attempt",
            prompt: "Historical attempt",
            response: "A",
            correctAnswer: "A",
            isCorrect: true,
            confidence: .certain
        )
        let attempt = try XCTUnwrap(source.attempts.first)
        try source.saveAttemptReflection(
            attemptID: attempt.id,
            deterministicErrorCode: nil,
            selectedErrorCode: .other,
            trigger: .highConfidenceError,
            note: "Introduced in archive v15."
        )
        let checkpointID = UUID()
        let checkpoint = SessionCheckpointRecord(
            sessionID: UUID(),
            lab: .logicDebugging,
            source: .focused,
            seed: 17,
            currentIndex: 1,
            itemCount: 3,
            response: "A",
            scratchpad: "Historical checkpoint",
            results: [true],
            evidenceClass: .practice,
            recommendationRationale: "Introduced in archive v17."
        )
        checkpoint.id = checkpointID
        sourceContainer.mainContext.insert(checkpoint)
        try sourceContainer.mainContext.save()
        source.reload()

        let exports = try NFDataExportService.makeExports(from: source)
        defer { try? FileManager.default.removeItem(at: exports[0].deletingLastPathComponent()) }
        let archiveURL = try XCTUnwrap(exports.first { $0.lastPathComponent == "NeuroForge-Full-Archive.json" })
        let baseObject = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(contentsOf: archiveURL)) as? [String: Any]
        )

        for version in 14...16 {
            var object = baseObject
            object["archiveVersion"] = version
            if version <= 14 {
                object.removeValue(forKey: "attemptReflections")
            }
            if version <= 15 {
                object.removeValue(forKey: "adaptivePlanHistory")
            }
            if version <= 16, var checkpoints = object["sessionCheckpoints"] as? [[String: Any]] {
                for index in checkpoints.indices {
                    checkpoints[index].removeValue(forKey: "recommendationRationale")
                }
                object["sessionCheckpoints"] = checkpoints
            }
            let historicalURL = archiveURL.deletingLastPathComponent()
                .appending(path: "NeuroForge-v\(version)-Fixture.json")
            try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]).write(to: historicalURL)

            let snapshot = try NFDataExportRoundTripValidator.decodeArchive(at: historicalURL)
            XCTAssertEqual(snapshot.archiveVersion, version)
            XCTAssertTrue(snapshot.sessionCheckpointIDs.contains(checkpointID))

            let historyURL = FileManager.default.temporaryDirectory
                .appending(path: "NF-Restore-v\(version)-History-\(UUID().uuidString).json")
            let (destination, destinationContainer) = try makeStore(historyURL: historyURL)
            defer {
                _ = destinationContainer
                try? FileManager.default.removeItem(at: historyURL)
            }
            let result = try NFDataArchiveRestoreService.restore(
                archiveAt: historicalURL,
                into: destination,
                policy: .replaceAll
            )
            XCTAssertEqual(result.preview.archiveVersion, version)
            XCTAssertEqual(result.restored[.checkpoints], 1)
            XCTAssertEqual(destination.sessionCheckpoints.first?.id, checkpointID)
            XCTAssertNil(destination.sessionCheckpoints.first?.recommendationRationale)
            XCTAssertEqual(destination.attemptReflections.count, version == 14 ? 0 : 1)
            XCTAssertEqual(destination.adaptivePlanHistory.isEmpty, version <= 15)
        }

        for unsupportedVersion in [13, 18] {
            var object = baseObject
            object["archiveVersion"] = unsupportedVersion
            let unsupportedURL = archiveURL.deletingLastPathComponent()
                .appending(path: "NeuroForge-v\(unsupportedVersion)-Unsupported.json")
            try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]).write(to: unsupportedURL)

            XCTAssertThrowsError(try NFDataExportRoundTripValidator.decodeArchive(at: unsupportedURL)) { error in
                XCTAssertEqual(
                    error as? NFDataArchiveValidationError,
                    .unsupportedArchiveVersion(unsupportedVersion)
                )
            }

            let (destination, destinationContainer) = try makeStore()
            defer { _ = destinationContainer }
            XCTAssertThrowsError(try NFDataArchiveRestoreService.restore(
                archiveAt: unsupportedURL,
                into: destination,
                policy: .replaceAll
            )) { error in
                XCTAssertEqual(
                    error as? NFDataArchiveRestoreError,
                    .unsupportedArchiveVersion(unsupportedVersion)
                )
            }
            XCTAssertTrue(destination.attempts.isEmpty)
            XCTAssertTrue(destination.sessionCheckpoints.isEmpty)
        }
    }

    @MainActor
    private func makeStore(
        historyURL: URL = FileManager.default.temporaryDirectory
            .appending(path: "NF-Data-Export-History-\(UUID().uuidString).json")
    ) throws -> (AppStore, ModelContainer) {
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
        return (
            AppStore(
                context: container.mainContext,
                adaptivePlanHistoryRepository: NFAdaptivePlanHistoryRepository(fileURL: historyURL)
            ),
            container
        )
    }

    private struct InjectedCorePersistenceError: Error {}
}

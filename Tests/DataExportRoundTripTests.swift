import Foundation
import CryptoKit
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

        for version in 14...17 {
            var object = baseObject
            object["archiveVersion"] = version
            object.removeValue(forKey: "localLearning")
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
            XCTAssertEqual(destination.sessionCheckpoints.first?.recommendationRationale,
                version <= 16 ? nil : "Introduced in archive v17.")
            XCTAssertEqual(destination.attemptReflections.count, version == 14 ? 0 : 1)
            XCTAssertEqual(destination.adaptivePlanHistory.isEmpty, version <= 15)
        }

        for unsupportedVersion in [13, NFDataExportService.archiveVersion + 1] {
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
    func testPreparedArchiveRestoresExactlyPreviewedBytesAfterExternalFileChanges() async throws {
        let (source, sourceContainer) = try makeStore()
        let (destination, destinationContainer) = try makeStore()
        defer { _ = sourceContainer; _ = destinationContainer }
        try source.saveLabAttempt(lab: .quantitative, itemID: "prepared.exact",
            prompt: "Preserve this original prompt.", response: "42", correctAnswer: "42",
            isCorrect: true, confidence: .fairlyConfident)
        let urls = try NFDataExportService.makeExports(from: source)
        let url = try XCTUnwrap(urls.first)
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let original = try Data(contentsOf: url)
        let prepared = try await NFDataArchiveRestoreService.prepare(archiveAt: url)
        XCTAssertEqual(prepared.sourceDigest, NFReservationSnapshot.digest(original))
        XCTAssertEqual(prepared.sourceByteCount, original.count)
        XCTAssertTrue(destination.attempts.isEmpty)
        let preview = try NFDataArchiveRestoreService.preview(prepared: prepared, into: destination)
        XCTAssertEqual(preview.incoming[.attempts], 1)
        try Data("external replacement".utf8).write(to: url, options: .atomic)
        XCTAssertThrowsError(try NFDataArchiveRestoreService.preview(archiveAt: url, into: destination))
        let restored = try NFDataArchiveRestoreService.restore(prepared: prepared, into: destination, policy: .abortOnConflict)
        XCTAssertEqual(restored.restored[.attempts], 1)
        XCTAssertEqual(destination.attempts.first?.id, source.attempts.first?.id)
        XCTAssertEqual(destination.attempts.first?.prompt, "Preserve this original prompt.")
        let retry = try NFDataArchiveRestoreService.restore(prepared: prepared, into: destination, policy: .keepExisting)
        XCTAssertEqual(retry.skipped[.attempts], 1)
        XCTAssertEqual(destination.attempts.count, 1)
    }

    @MainActor
    func testCancelledArchivePreparationDoesNotProduceAnAcceptedRestore() async throws {
        let (store, container) = try makeStore()
        defer { _ = container }
        let urls = try NFDataExportService.makeExports(from: store)
        let url = try XCTUnwrap(urls.first)
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let original = try Data(contentsOf: url)
        let pending = Task { try await NFDataArchiveRestoreService.prepare(archiveAt: url) }
        pending.cancel()
        do { _ = try await pending.value; XCTFail("Cancelled preparation must not publish an accepted input.") }
        catch is CancellationError { }
        catch { XCTFail("Expected cancellation, got \(error)") }
        XCTAssertTrue(store.attempts.isEmpty)
        XCTAssertEqual(try Data(contentsOf: url), original)
    }

    func testArchiveReadBoundaryRejectsOversizedFileBeforeDecode() throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "NF-Oversize-Archive-\(UUID()).json")
        FileManager.default.createFile(atPath: url.path, contents: Data())
        defer { try? FileManager.default.removeItem(at: url) }
        let handle = try FileHandle(forWritingTo: url)
        try handle.truncate(atOffset: UInt64(NFLocalSessionRepository.maximumBytes + 1))
        try handle.close()
        XCTAssertThrowsError(try NFDataArchiveReadBoundary.boundedData(at: url)) {
            XCTAssertEqual($0 as? NFDataArchiveRestoreError, .invalidArchive("archive size limit"))
        }
        XCTAssertEqual(try url.resourceValues(forKeys: [.fileSizeKey]).fileSize, NFLocalSessionRepository.maximumBytes + 1)
    }

    @MainActor
    func testRestorePreservesEveryHiddenDuplicateBeforeAnyStoreMutation() throws {
        let (source, sourceContainer) = try makeStore()
        defer { _ = sourceContainer }
        let exports = try NFDataExportService.makeExports(from: source)
        defer { try? FileManager.default.removeItem(at: exports[0].deletingLastPathComponent()) }
        let url = try XCTUnwrap(exports.first { $0.lastPathComponent == "NeuroForge-Full-Archive.json" })
        for kind in ["attempt", "reflection", "checkpoint", "profile"] {
            let (destination, container) = try makeStore()
            defer { _ = container }
            let attempt = restoreCensusAttempt(response: "First original")
            container.mainContext.insert(attempt)
            switch kind {
            case "attempt":
                let peer = restoreCensusAttempt(response: "Other original")
                peer.id = attempt.id
                container.mainContext.insert(peer)
            case "reflection":
                for note in ["First original", "Other original"] {
                    container.mainContext.insert(AttemptReflectionRecord(attemptID: attempt.id,
                        deterministicErrorCode: nil, selectedErrorCode: .other,
                        trigger: .highConfidenceError, note: note))
                }
            case "checkpoint":
                let run = UUID()
                for response in ["First original", "Other original"] {
                    container.mainContext.insert(SessionCheckpointRecord(sessionID: run,
                        lab: .logicDebugging, source: .focused, seed: 21, currentIndex: 0,
                        itemCount: 2, response: response, scratchpad: "Original notes", results: [], credits: [],
                        evidenceClass: .practice))
                }
            default:
                container.mainContext.insert(UserProfileRecord(draft: OnboardingDraft()))
                container.mainContext.insert(UserProfileRecord(draft: OnboardingDraft()))
            }
            try container.mainContext.save()
            destination.reload() // Deliberately creates the ordinary winner projection.
            let originalAttempts = try container.mainContext.fetch(FetchDescriptor<AttemptRecord>())
                .map { NFImmutableAttemptRecordSnapshot($0) }
            let originalReflections = try container.mainContext.fetch(FetchDescriptor<AttemptReflectionRecord>()).map(\.note).sorted()
            let originalCheckpoints = try container.mainContext.fetch(FetchDescriptor<SessionCheckpointRecord>()).map(\.response).sorted()
            let originalProfiles = try container.mainContext.fetch(FetchDescriptor<UserProfileRecord>()).map(\.id)
            let localBefore = try NFImmutableAttemptRecordSnapshot.encoded(destination.localSessions.archive)
            let historyBefore = destination.adaptivePlanHistory
            XCTAssertThrowsError(try NFDataArchiveRestoreService.preview(archiveAt: url, into: destination)) {
                XCTAssertEqual($0 as? NFDataArchiveRestoreError, .ambiguousDestinationRecords, kind)
            }
            for policy in NFDataArchiveRestorePolicy.allCases {
                XCTAssertThrowsError(try NFDataArchiveRestoreService.restore(archiveAt: url, into: destination, policy: policy)) {
                    XCTAssertEqual($0 as? NFDataArchiveRestoreError, .ambiguousDestinationRecords, kind)
                }
            }
            let retained = try container.mainContext.fetch(FetchDescriptor<AttemptRecord>()).map { NFImmutableAttemptRecordSnapshot($0) }
            XCTAssertEqual(Set(try retained.map { try NFImmutableAttemptRecordSnapshot.encoded($0) }),
                Set(try originalAttempts.map { try NFImmutableAttemptRecordSnapshot.encoded($0) }), kind)
            XCTAssertEqual(try container.mainContext.fetch(FetchDescriptor<AttemptReflectionRecord>()).map(\.note).sorted(), originalReflections, kind)
            XCTAssertEqual(try container.mainContext.fetch(FetchDescriptor<SessionCheckpointRecord>()).map(\.response).sorted(), originalCheckpoints, kind)
            XCTAssertEqual(Set(try container.mainContext.fetch(FetchDescriptor<UserProfileRecord>()).map(\.id)), Set(originalProfiles), kind)
            XCTAssertEqual(try NFImmutableAttemptRecordSnapshot.encoded(destination.localSessions.archive), localBefore, kind)
            XCTAssertEqual(destination.adaptivePlanHistory, historyBefore, kind)
        }
    }

    @MainActor
    func testRestoreConflictAndReplacementUseFreshRowsAbsentFromTheHistoryProjection() throws {
        let (source, sourceContainer) = try makeStore()
        defer { _ = sourceContainer }
        let incoming = restoreCensusAttempt(response: "Archive response")
        sourceContainer.mainContext.insert(incoming)
        try sourceContainer.mainContext.save()
        source.reload()
        let exports = try NFDataExportService.makeExports(from: source)
        defer { try? FileManager.default.removeItem(at: exports[0].deletingLastPathComponent()) }
        let url = try XCTUnwrap(exports.first { $0.lastPathComponent == "NeuroForge-Full-Archive.json" })
        for policy in NFDataArchiveRestorePolicy.allCases {
            let (destination, container) = try makeStore()
            defer { _ = container }
            let existing = restoreCensusAttempt(response: "Destination response")
            existing.id = incoming.id
            let additional = restoreCensusAttempt(response: "Unrelated saved response")
            container.mainContext.insert(existing)
            container.mainContext.insert(additional)
            try container.mainContext.save()
            XCTAssertTrue(destination.attempts.isEmpty, "The UI projection intentionally predates these saved rows")
            XCTAssertEqual(try NFDataArchiveRestoreService.preview(archiveAt: url, into: destination).conflicts[.attempts], 1)
            if policy == .abortOnConflict {
                XCTAssertThrowsError(try NFDataArchiveRestoreService.restore(archiveAt: url, into: destination, policy: policy)) {
                    XCTAssertEqual($0 as? NFDataArchiveRestoreError, .conflictsRequireDecision(1))
                }
            } else {
                let result = try NFDataArchiveRestoreService.restore(archiveAt: url, into: destination, policy: policy)
                XCTAssertEqual(result.restored[.attempts], policy == .keepExisting ? 0 : 1)
                XCTAssertEqual(result.skipped[.attempts], policy == .keepExisting ? 1 : 0)
            }
            let raw = try container.mainContext.fetch(FetchDescriptor<AttemptRecord>())
            XCTAssertEqual(raw.filter { $0.id == incoming.id }.count, 1, policy.rawValue)
            XCTAssertEqual(raw.first { $0.id == incoming.id }?.response,
                policy == .keepExisting || policy == .abortOnConflict ? "Destination response" : "Archive response")
            XCTAssertEqual(raw.contains { $0.id == additional.id }, policy != .replaceAll)
        }
    }

    @MainActor
    func testRestoreMatchesReflectionAndCheckpointDomainIdentitiesAcrossPeerRecordIDs() throws {
        let (source, sourceContainer) = try makeStore()
        defer { _ = sourceContainer }
        let attempt = restoreCensusAttempt(response: "Archive response")
        sourceContainer.mainContext.insert(attempt)
        let incomingReflection = AttemptReflectionRecord(attemptID: attempt.id, deterministicErrorCode: nil,
            selectedErrorCode: .other, trigger: .highConfidenceError, note: "Archive reflection")
        sourceContainer.mainContext.insert(incomingReflection)
        let runID = UUID()
        let incomingCheckpoint = SessionCheckpointRecord(sessionID: runID, lab: .logicDebugging,
            source: .focused, seed: 21, currentIndex: 0, itemCount: 2, response: "Archive draft",
            scratchpad: "Archive notes", results: [], credits: [], evidenceClass: .practice)
        sourceContainer.mainContext.insert(incomingCheckpoint)
        try sourceContainer.mainContext.save()
        source.reload()
        let exports = try NFDataExportService.makeExports(from: source)
        defer { try? FileManager.default.removeItem(at: exports[0].deletingLastPathComponent()) }
        let url = try XCTUnwrap(exports.first { $0.lastPathComponent == "NeuroForge-Full-Archive.json" })
        for policy in NFDataArchiveRestorePolicy.allCases {
            let (destination, container) = try makeStore()
            defer { _ = container }
            let existing = restoreCensusAttempt(response: "Destination response")
            existing.id = attempt.id
            container.mainContext.insert(existing)
            let reflection = AttemptReflectionRecord(attemptID: attempt.id, deterministicErrorCode: nil,
                selectedErrorCode: .other, trigger: .highConfidenceError, note: "Destination reflection")
            container.mainContext.insert(reflection)
            let checkpoint = SessionCheckpointRecord(sessionID: runID, lab: .logicDebugging,
                source: .focused, seed: 21, currentIndex: 0, itemCount: 2, response: "Destination draft",
                scratchpad: "Destination notes", results: [], credits: [], evidenceClass: .practice)
            container.mainContext.insert(checkpoint)
            try container.mainContext.save()
            XCTAssertNotEqual(reflection.id, incomingReflection.id)
            XCTAssertNotEqual(checkpoint.id, incomingCheckpoint.id)
            let preview = try NFDataArchiveRestoreService.preview(archiveAt: url, into: destination)
            XCTAssertEqual(preview.conflicts[.reflections], 1)
            XCTAssertEqual(preview.conflicts[.checkpoints], 1)
            if policy == .abortOnConflict {
                XCTAssertThrowsError(try NFDataArchiveRestoreService.restore(archiveAt: url, into: destination, policy: policy)) {
                    XCTAssertEqual($0 as? NFDataArchiveRestoreError, .conflictsRequireDecision(3))
                }
            } else {
                _ = try NFDataArchiveRestoreService.restore(archiveAt: url, into: destination, policy: policy)
            }
            let reflections = try container.mainContext.fetch(FetchDescriptor<AttemptReflectionRecord>())
            let checkpoints = try container.mainContext.fetch(FetchDescriptor<SessionCheckpointRecord>())
            let keepsExisting = policy == .keepExisting || policy == .abortOnConflict
            XCTAssertEqual(reflections.count, 1)
            XCTAssertEqual(reflections.first?.id, keepsExisting ? reflection.id : incomingReflection.id)
            XCTAssertEqual(reflections.first?.note, keepsExisting ? "Destination reflection" : "Archive reflection")
            XCTAssertEqual(checkpoints.count, 1)
            XCTAssertEqual(checkpoints.first?.id, keepsExisting ? checkpoint.id : incomingCheckpoint.id)
            XCTAssertEqual(checkpoints.first?.response, keepsExisting ? "Destination draft" : "Archive draft")
        }
    }

    @MainActor
    func testRestoreRejectsCrossedPhysicalAndDomainIdentitiesWithoutDeletingEitherOriginal() throws {
        for kind in ["reflection", "checkpoint"] {
            let (source, sourceContainer) = try makeStore()
            let (destination, container) = try makeStore()
            defer { _ = sourceContainer; _ = container }
            let domainA = UUID(), domainB = UUID(), recordA = UUID(), recordB = UUID()
            if kind == "reflection" {
                for domain in [domainA, domainB] {
                    let original = restoreCensusAttempt(response: "Original response")
                    original.id = domain
                    container.mainContext.insert(original)
                    let incoming = restoreCensusAttempt(response: "Archive response")
                    incoming.id = domain
                    sourceContainer.mainContext.insert(incoming)
                }
                for (recordID, domainID, note) in [(recordA, domainA, "First original"), (recordB, domainB, "Second original")] {
                    let record = AttemptReflectionRecord(attemptID: domainID, deterministicErrorCode: nil,
                        selectedErrorCode: .other, trigger: .highConfidenceError, note: note)
                    record.id = recordID
                    container.mainContext.insert(record)
                }
                let crossed = AttemptReflectionRecord(attemptID: domainB, deterministicErrorCode: nil,
                    selectedErrorCode: .other, trigger: .highConfidenceError, note: "Crossed incoming")
                crossed.id = recordA
                sourceContainer.mainContext.insert(crossed)
            } else {
                for (recordID, domainID, text) in [(recordA, domainA, "First original"), (recordB, domainB, "Second original")] {
                    let record = SessionCheckpointRecord(sessionID: domainID, lab: .logicDebugging,
                        source: .focused, seed: 21, currentIndex: 0, itemCount: 2, response: text,
                        scratchpad: "Original notes", results: [], credits: [], evidenceClass: .practice)
                    record.id = recordID
                    container.mainContext.insert(record)
                }
                let crossed = SessionCheckpointRecord(sessionID: domainB, lab: .logicDebugging,
                    source: .focused, seed: 21, currentIndex: 0, itemCount: 2, response: "Crossed incoming",
                    scratchpad: "Archive notes", results: [], credits: [], evidenceClass: .practice)
                crossed.id = recordA
                sourceContainer.mainContext.insert(crossed)
            }
            try sourceContainer.mainContext.save()
            try container.mainContext.save()
            source.reload()
            let exports = try NFDataExportService.makeExports(from: source)
            defer { try? FileManager.default.removeItem(at: exports[0].deletingLastPathComponent()) }
            let url = try XCTUnwrap(exports.first { $0.lastPathComponent == "NeuroForge-Full-Archive.json" })
            let localBefore = try NFImmutableAttemptRecordSnapshot.encoded(destination.localSessions.archive)
            let historyBefore = destination.adaptivePlanHistory
            XCTAssertThrowsError(try NFDataArchiveRestoreService.preview(archiveAt: url, into: destination)) {
                XCTAssertEqual($0 as? NFDataArchiveRestoreError, .ambiguousDestinationRecords, kind)
            }
            for policy in NFDataArchiveRestorePolicy.allCases {
                XCTAssertThrowsError(try NFDataArchiveRestoreService.restore(archiveAt: url, into: destination, policy: policy)) {
                    XCTAssertEqual($0 as? NFDataArchiveRestoreError, .ambiguousDestinationRecords, kind)
                }
            }
            if kind == "reflection" {
                let raw = try container.mainContext.fetch(FetchDescriptor<AttemptReflectionRecord>())
                XCTAssertEqual(raw.count, 2)
                XCTAssertEqual(raw.first { $0.id == recordA }?.attemptID, domainA)
                XCTAssertEqual(raw.first { $0.id == recordB }?.attemptID, domainB)
                XCTAssertEqual(Set(raw.map(\.note)), ["First original", "Second original"])
            } else {
                let raw = try container.mainContext.fetch(FetchDescriptor<SessionCheckpointRecord>())
                XCTAssertEqual(raw.count, 2)
                XCTAssertEqual(raw.first { $0.id == recordA }?.sessionID, domainA)
                XCTAssertEqual(raw.first { $0.id == recordB }?.sessionID, domainB)
                XCTAssertEqual(Set(raw.map(\.response)), ["First original", "Second original"])
            }
            XCTAssertEqual(try NFImmutableAttemptRecordSnapshot.encoded(destination.localSessions.archive), localBefore)
            XCTAssertEqual(destination.adaptivePlanHistory, historyBefore)
        }
    }

    @MainActor
    private func restoreCensusAttempt(response: String) -> AttemptRecord {
        AttemptRecord(sessionID: UUID(), lab: .logicDebugging, itemID: "raw-census-fixture",
            prompt: "Original question", response: response, correctAnswer: "Original key",
            isCorrect: false, confidence: .certain)
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

/// Committed JSON is synthetic and small. Every restore uses in-memory data,
/// private temporary roots, and shared widget publishing disabled.
final class GoldenArchiveFixtureTests: XCTestCase {
    private var fixtureFolder: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().appending(path: "Fixtures/ImprovementGolden_v1")
    }
    private let ownerID = UUID(uuidString: "0000d001-0000-4000-8000-000000000001")!

    @MainActor
    func testGoldenCommittedPackageHashesAndActualDecoderCounts() throws {
        let manifest = try object(fixtureFolder.appending(path: "manifest.json"))
        XCTAssertEqual(manifest["containsRealUserData"] as? Bool, false)
        XCTAssertEqual(manifest["shippedStoreSnapshot"] as? Bool, false)
        for entry in try XCTUnwrap(manifest["entries"] as? [[String: Any]]) {
            let path = try XCTUnwrap(entry["path"] as? String)
            let url = fixtureFolder.appending(path: path)
            let data = try Data(contentsOf: url)
            XCTAssertEqual(data.count, entry["bytes"] as? Int, path)
            XCTAssertEqual(SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined(), entry["sha256"] as? String, path)
            if entry["acceptedByRestore"] as? Bool == true {
                let decoded = try NFDataExportRoundTripValidator.decodeArchive(at: url)
                XCTAssertEqual(decoded.attemptIDs.count, entry["expectedAttemptCount"] as? Int, path)
                XCTAssertEqual(decoded.documentIDs.count, entry["expectedDocumentCount"] as? Int, path)
                XCTAssertEqual(decoded.sourceChunkIDs.count, entry["expectedChunkCount"] as? Int, path)
            }
        }
        for path in ["malformed-truncated.json", "future-v99.json", "invalid-duplicate-attempt-v18.json"] {
            XCTAssertThrowsError(try NFDataExportRoundTripValidator.decodeArchive(at: fixtureFolder.appending(path: path)), path)
        }
    }

    @MainActor
    func testGoldenFreshAndLegacyVersions14Through18RestoreExactOriginalPayloads() throws {
        let names = ["fresh-v18.json"] + (14...18).map { "legacy-v\($0).json" }
            + ["disputed-science-v18.json", "external-self-check-v18.json"]
        for name in names {
            let folder = temporaryFolder()
            defer { try? FileManager.default.removeItem(at: folder) }
            let (store, container) = try goldenStore(folder: folder)
            let url = fixtureFolder.appending(path: name)
            let original = try object(url)
            let rows = try XCTUnwrap(original["attempts"] as? [[String: Any]])
            let preview = try NFDataArchiveRestoreService.preview(archiveAt: url, into: store)
            XCTAssertEqual(preview.incoming[.attempts], rows.count, name)
            XCTAssertEqual(preview.archiveVersion, original["archiveVersion"] as? Int, name)
            let restored = try NFDataArchiveRestoreService.restore(archiveAt: url, into: store, policy: .replaceAll)
            XCTAssertEqual(restored.restored[.attempts], rows.count, name)
            XCTAssertEqual(restored.restored[.profile], 1, name)
            XCTAssertEqual(store.attempts.count, rows.count, name)
            for row in rows {
                let id = try XCTUnwrap((row["id"] as? String).flatMap(UUID.init(uuidString:)))
                let attempt = try XCTUnwrap(store.attempts.first { $0.id == id })
                XCTAssertEqual(attempt.response, row["response"] as? String, name)
                XCTAssertEqual(attempt.correctAnswerText, row["correctAnswer"] as? String, name)
                XCTAssertEqual(attempt.deterministicCredit, row["deterministicCredit"] as? Double, name)
                XCTAssertEqual(attempt.isCorrect, row["isCorrect"] as? Bool, name)
                if attempt.itemID == "golden.disputed-science" {
                    XCTAssertTrue(store.evidenceDispositions.contains { $0.attemptID == id.uuidString && $0.disposition == .excludedContentCorrection })
                    XCTAssertTrue(store.localSessions.archive.contentCorrections?.contains { $0.originalAttemptID == id.uuidString && $0.ruleID == "unverifiable-interval" } == true)
                }
                if attempt.itemID == "golden.external-self-check" {
                    XCTAssertTrue(store.evidenceDispositions.contains { $0.attemptID == id.uuidString && $0.disposition == .personalStudy })
                    XCTAssertEqual(NFResponsePresentation.decode(attempt.response), .selfCheck(.init(rating: .matched, reflection: "Synthetic recall only.\n日本語の記録")))
                    XCTAssertEqual(store.effectiveAttemptDTO(attempt).evidenceWeight, 0)
                }
            }
            _ = container
        }
    }

    @MainActor
    func testGoldenInvalidPayloadsCannotChangeAnExistingSyntheticStore() throws {
        let folder = temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let (store, container) = try goldenStore(folder: folder)
        let sentinel = AttemptRecord(sessionID: UUID(uuidString: "0000a120-0000-4000-8000-000000000099")!, lab: .mentalMath,
            itemID: "golden.existing-sentinel", prompt: "Synthetic sentinel", response: "  retained exactly  ",
            correctAnswer: "reference", isCorrect: false, confidence: .uncertain, evidenceClass: .practice, source: .focused)
        sentinel.id = UUID(uuidString: "0000a110-0000-4000-8000-000000000099")!
        container.mainContext.insert(sentinel)
        try container.mainContext.save()
        store.reload()
        for name in ["malformed-truncated.json", "future-v99.json", "invalid-duplicate-attempt-v18.json", "invalid-source-reference-v18.json"] {
            let url = fixtureFolder.appending(path: name)
            XCTAssertThrowsError(try NFDataArchiveRestoreService.preview(archiveAt: url, into: store), name)
            XCTAssertThrowsError(try NFDataArchiveRestoreService.restore(archiveAt: url, into: store, policy: .replaceAll), name)
            XCTAssertEqual(store.attempts.map(\.id), [sentinel.id], name)
            XCTAssertEqual(store.attempts.first?.response, "  retained exactly  ", name)
            XCTAssertTrue(store.documents.isEmpty, name)
            XCTAssertTrue(store.sourceChunks.isEmpty, name)
        }
    }

    @MainActor
    func testGoldenSourceDuplicatesAndDeletedHistoricalReferencesRemainDistinct() throws {
        let folder = temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let (store, container) = try goldenStore(folder: folder)
        let url = fixtureFolder.appending(path: "source-duplicates-deleted-reference-v18.json")
        let restored = try NFDataArchiveRestoreService.restore(archiveAt: url, into: store, policy: .replaceAll)
        XCTAssertEqual(restored.restored[.documents], 2)
        XCTAssertEqual(restored.restored[.sourceChunks], 2)
        XCTAssertEqual(Set(store.documents.map(\.id)).count, 2)
        XCTAssertEqual(Set(store.sourceChunks.map(\.contentHash)).count, 1)
        let attempt = try XCTUnwrap(store.attempts.first)
        let deletedDocumentID = try XCTUnwrap(UUID(uuidString: "0de1e7ed-0000-4000-8000-000000000001"))
        let referencedDocumentIDs = try attempt.sourceDocumentIDsRaw
            .split(separator: ",", omittingEmptySubsequences: false)
            .map { try XCTUnwrap(UUID(uuidString: String($0))) }
        // Restore may canonicalize UUID casing, but must retain the exact
        // historical identity without relinking it to an extant duplicate.
        XCTAssertEqual(referencedDocumentIDs.count, 1)
        XCTAssertEqual(Set(referencedDocumentIDs), Set([deletedDocumentID]))
        XCTAssertFalse(store.documents.contains { $0.id == deletedDocumentID })
        XCTAssertEqual(attempt.sourceChunkIDsRaw, "deleted.synthetic.chunk")
        XCTAssertFalse(store.sourceChunks.contains { $0.id == attempt.sourceChunkIDsRaw })
        XCTAssertEqual(store.sourceChunks.first?.text, "Synthetic source note alpha. No personal data.\nSecond line.")
        XCTAssertEqual(attempt.response, try XCTUnwrap((object(url)["attempts"] as? [[String: Any]])?.first?["response"] as? String))
        _ = container
    }

    #if os(macOS)
    @MainActor
    func testGoldenRegeneratorReproducesCommittedFilesAnd10000AttemptHistory() throws {
        try runGenerator(["--check"])
        let folder = temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        try runGenerator(["--output-dir", folder.path, "--large-count", "10000"])
        try runGenerator(["--output-dir", folder.path, "--large-count", "10000", "--check"])
        let url = folder.appending(path: "history-10000-v18.json")
        let decoded = try NFDataExportRoundTripValidator.decodeArchive(at: url)
        XCTAssertEqual(decoded.attemptIDs.count, 10_000)
        XCTAssertTrue(decoded.attemptIDs.contains(UUID(uuidString: "0000a110-0000-4000-8000-000000000001")!))
        XCTAssertTrue(decoded.attemptIDs.contains(UUID(uuidString: "0000a110-0000-4000-8000-000000002710")!))
        let (store, container) = try goldenStore(folder: folder.appending(path: "store"))
        XCTAssertEqual(try NFDataArchiveRestoreService.preview(archiveAt: url, into: store).incoming[.attempts], 10_000)
        let result = try NFDataArchiveRestoreService.restore(archiveAt: url, into: store, policy: .replaceAll)
        XCTAssertEqual(result.restored[.attempts], 10_000)
        XCTAssertEqual(store.attempts.count, 10_000)
        let expected = try XCTUnwrap(object(fixtureFolder.appending(path: "history-10000.recipe.json"))["rawResponse"] as? String)
        XCTAssertEqual(Set(store.attempts.map(\.response)), [expected])
        XCTAssertEqual(Set(store.attempts.map(\.deterministicCredit)), [1])
        _ = container
    }
    #endif

    @MainActor
    func testGoldenRuntimeCapturesPreserveThreePhasesAndInterruptedTiming() throws {
        let phases = ["item", "feedback", "selfCheckComparison", "interruptedTimedItem"]
        for (ordinal, name) in phases.enumerated() {
            let folder = temporaryFolder()
            defer { try? FileManager.default.removeItem(at: folder) }
            let (source, sourceContainer) = try goldenStore(folder: folder.appending(path: "source"))
            let isSelfCheck = name == "selfCheckComparison"
            let timed = name == "interruptedTimedItem"
            let request = SessionRequest(lab: isSelfCheck ? .retrieval : .mentalMath, source: .focused, seed: 347811,
                localeIdentifier: "en", requestedItemCount: 1, isTimed: timed,
                mechanicID: isSelfCheck ? "retrieval.fallback-variant-0" : NFDefaultContentCatalog.activities.first { $0.id == "nf.default.mental.rapid-recall" }?.mechanicID)
            var clock: TimeInterval = 100
            let sessionID = try XCTUnwrap(UUID(uuidString: String(format: "0000a120-0000-4000-8000-%012x", ordinal + 1)))
            let runtime = NFUniversalSessionRuntime(request: request, sessionID: sessionID, monotonicNow: { clock })
            XCTAssertTrue(runtime.checkpointDraft(store: source))
            runtime.resume()
            runtime.acknowledgePresented()
            runtime.scratchpad = "Synthetic golden notes\n日本語"
            if isSelfCheck {
                XCTAssertTrue(runtime.isSelfCheck)
                runtime.selfCheckReflection = "Synthetic recall before the reference"
                runtime.submitInline(store: source)
            } else {
                runtime.numericValue = "17"
                if name == "feedback" { runtime.submitInline(store: source) }
                if timed {
                    clock = 112
                    runtime.pause(at: Date(timeIntervalSince1970: 1_788_523_200))
                }
            }
            XCTAssertTrue(runtime.checkpointDraft(store: source))
            let captured = try XCTUnwrap(source.localSessions.archive.sessions.first { $0.id == sessionID })
            XCTAssertEqual(captured.phase.rawValue, timed ? "item" : name)
            if timed { XCTAssertEqual(captured.checkpoint.itemActiveDuration, 12, accuracy: 0.001) }
            runtime.releaseWriter()
            let exports = try NFDataExportService.makeExports(from: source)
            defer { try? FileManager.default.removeItem(at: exports[0].deletingLastPathComponent()) }
            let identities = try NFDataExportRoundTripValidator.decodeArchive(at: exports[0])
            XCTAssertEqual(identities.attemptIDs.count, name == "feedback" ? 1 : 0)
            let (destination, destinationContainer) = try goldenStore(folder: folder.appending(path: "destination"))
            _ = try NFDataArchiveRestoreService.restore(archiveAt: exports[0], into: destination, policy: .replaceAll)
            let recovered = try XCTUnwrap(destination.localSessions.archive.sessions.first { $0.id == sessionID })
            XCTAssertEqual(recovered.phase, captured.phase)
            XCTAssertEqual(recovered.checkpoint.exercise, captured.checkpoint.exercise)
            XCTAssertEqual(recovered.checkpoint.exerciseDigest, captured.checkpoint.exerciseDigest)
            XCTAssertEqual(recovered.checkpoint.response, captured.checkpoint.response)
            XCTAssertEqual(recovered.checkpoint.scratchpad, captured.checkpoint.scratchpad)
            XCTAssertEqual(recovered.checkpoint.itemActiveDuration, captured.checkpoint.itemActiveDuration)
            XCTAssertEqual(recovered.checkpoint.committedAttemptID, captured.checkpoint.committedAttemptID)
            XCTAssertEqual(destination.attempts.count, source.attempts.count)
            _ = sourceContainer; _ = destinationContainer
        }
    }

    private func object(_ url: URL) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
    }
    private func temporaryFolder() -> URL {
        FileManager.default.temporaryDirectory.appending(path: "NeuroForge-Synthetic-Golden-\(UUID().uuidString)")
    }
    @MainActor
    private func goldenStore(folder: URL) throws -> (AppStore, ModelContainer) {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let container = try ModelContainer(for: Schema(NFSchemaV1.models), configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let store = AppStore(context: container.mainContext,
            nextDayEnhancementCache: NFNextDayEnhancementCache(rootURL: folder.appending(path: "cache")),
            documentStorageRootURL: folder.appending(path: "documents"),
            localSessionRepository: NFLocalSessionRepository(ownerDeviceID: ownerID),
            adaptivePlanHistoryRepository: NFAdaptivePlanHistoryRepository(fileURL: folder.appending(path: "adaptive-history.json")),
            offlineQuestionRotation: NFOfflineQuestionRotation(store: GoldenRotationStore()))
        XCTAssertFalse(store.allowsSharedWidgetPublishing)
        guard !store.allowsSharedWidgetPublishing else {
            throw NSError(domain: "SyntheticGoldenFixtureIsolation", code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Golden fixtures cannot use shared widget storage."])
        }
        return (store, container)
    }
    #if os(macOS)
    private func runGenerator(_ arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        process.arguments = [fixtureFolder.appending(path: "regenerate.py").path] + arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        let output = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0, String(decoding: output, as: UTF8.self))
    }
    #endif
}

private final class GoldenRotationStore: NFOfflineQuestionRotationStateStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var value: NFOfflineQuestionRotationLedger?
    func load() throws -> NFOfflineQuestionRotationLedger? { lock.withLock { value } }
    func compareAndSwap(expectedRevision: UInt64?, replacement: NFOfflineQuestionRotationLedger) throws -> Bool {
        lock.withLock {
            guard value?.revision == expectedRevision else { return false }
            value = replacement
            return true
        }
    }
}

final class NFDataArchiveRawSnapshotTests: XCTestCase {
    func testScalarCodecPreservesEveryDoubleAndDateBitPatternWithoutJSONNumberCoercion() throws {
        let patterns: [UInt64] = [0, 0x8000_0000_0000_0000, 1, 0x000f_ffff_ffff_ffff,
            0x7fef_ffff_ffff_ffff, 0x7ff0_0000_0000_0000, 0xfff0_0000_0000_0000,
            0x7ff8_1234_5678_9abc, 0x7ff0_0000_0000_0001, 0xfff8_9876_5432_1001]
        for bits in patterns {
            let value = Double(bitPattern: bits)
            let encoded = try NFDataArchiveRawSnapshot.canonicalEncode(value.archiveRawValue)
            let raw = try JSONDecoder().decode(NFDataArchiveRawValue.self, from: encoded)
            XCTAssertEqual(try Double.fromArchiveRawValue(raw).bitPattern, bits)
            let date = Date(timeIntervalSinceReferenceDate: value)
            let dateBytes = try NFDataArchiveRawSnapshot.canonicalEncode(date.archiveRawValue)
            let dateRaw = try JSONDecoder().decode(NFDataArchiveRawValue.self, from: dateBytes)
            XCTAssertEqual(try Date.fromArchiveRawValue(dateRaw).timeIntervalSinceReferenceDate.bitPattern,
                date.timeIntervalSinceReferenceDate.bitPattern)
        }
        XCTAssertNotEqual(Double(0).archiveRawValue, Double(-0.0).archiveRawValue)
        XCTAssertNotEqual(Double(bitPattern: 0x7ff8_0000_0000_0001).archiveRawValue,
                          Double(bitPattern: 0x7ff8_0000_0000_0002).archiveRawValue)
        XCTAssertEqual(try UInt64.fromArchiveRawValue(UInt64.max.archiveRawValue), UInt64.max)
        XCTAssertEqual(try Int64.fromArchiveRawValue(Int64.min.archiveRawValue), Int64.min)
        XCTAssertEqual(try Int.fromArchiveRawValue(Int.min.archiveRawValue), Int.min)
        let composed = "\u{00e9}", decomposed = "e\u{0301}"
        XCTAssertEqual(composed, decomposed, "Swift text equality alone cannot authenticate original bytes")
        XCTAssertNotEqual(composed.archiveRawValue, decomposed.archiveRawValue)
        XCTAssertEqual(Data(try String.fromArchiveRawValue(decomposed.archiveRawValue).utf8), Data(decomposed.utf8))
        XCTAssertThrowsError(try String.fromArchiveRawValue(.textUTF8(Data([0xff, 0xc0, 0x80]))))
        XCTAssertThrowsError(try Double.fromArchiveRawValue(.doubleBits("7FF8000000000001")))
        XCTAssertThrowsError(try Double.fromArchiveRawValue(.signedBits("0000000000000000")))
        XCTAssertEqual((nil as Double?).archiveRawValue, .null)
        XCTAssertEqual(try Optional<Double>.fromArchiveRawValue(.null), nil)
    }

    @MainActor
    func testExplicitTypedCensusMatchesAllThirteenModelsAndAll219DeclaredColumns() throws {
        let census = NFDataArchiveRawCapture.columnCensus
        XCTAssertEqual(census, Self.expectedColumns)
        XCTAssertEqual(census.count, 13)
        XCTAssertEqual(census.values.reduce(0) { $0 + $1.count }, 219)
        XCTAssertEqual(Set(census.keys), Set(NFSchemaV1.models.map { String(describing: $0) }))
        let empty = NFDataArchiveRawCapture.emptySnapshot()
        XCTAssertEqual(Set(empty.tables.filter { $0.domain == .durable }.map(\.model)),
            Set(NFPersistentStoreLocation.durableModels.map { String(describing: $0) }))
        XCTAssertEqual(Set(empty.tables.filter { $0.domain == .localOnly }.map(\.model)),
            Set(NFPersistentStoreLocation.localOnlyModels.map { String(describing: $0) }))
        try NFDataArchiveRawCapture.validate(empty)
        try NFDataArchiveRawCapture.verifyHydration(adversarialSnapshot())
    }

    @MainActor
    func testTypedHydrationRetainsUnknownEnumsOpaqueBlobsNilVersusEmptyAndScalarBits() throws {
        var snapshot = adversarialSnapshot()
        let attemptIndex = try XCTUnwrap(snapshot.tables.firstIndex { $0.model == "AttemptRecord" })
        snapshot.tables[attemptIndex].rows[0].columns["correctAnswer"] = Double(bitPattern: 0x7ff8_1234_5678_9abc).archiveRawValue
        snapshot.tables[attemptIndex].rows[0].columns["activeDurationSeconds"] = Double(-0.0).archiveRawValue
        snapshot.tables[attemptIndex].rows[0].columns["evidenceWeight"] = Double.infinity.archiveRawValue
        snapshot.tables[attemptIndex].rows[0].columns["deterministicCredit"] = Double.leastNonzeroMagnitude.archiveRawValue
        snapshot.tables[attemptIndex].rows[0].columns["seed"] = UInt64.max.archiveRawValue
        let calibration = try XCTUnwrap(snapshot.tables.firstIndex { $0.model == "InputCalibrationRecord" })
        snapshot.tables[calibration].rows[0].columns["keyboardLatencyMilliseconds"] = Double(-0.0).archiveRawValue
        snapshot.tables[calibration].rows[0].columns["touchLatencyMilliseconds"] = Double.nan.archiveRawValue
        snapshot.tables[calibration].rows[1].columns["keyboardLatencyMilliseconds"] = .null
        try NFDataArchiveRawCapture.verifyHydration(snapshot)
        let bytes = try snapshot.encoded(maximumBytes: 4 * 1_024 * 1_024)
        let decoded = try NFDataArchiveRawSnapshot.decode(bytes, maximumBytes: 4 * 1_024 * 1_024)
        XCTAssertEqual(decoded, snapshot)
        XCTAssertEqual(try decoded.contentBytes(), try snapshot.contentBytes())
    }

    @MainActor
    func testRawDiskRoundTripKeepsDuplicateLogicalGroupsAndEveryColumnAcrossBothStoreDomains() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "NFRawSnapshot-\(UUID())")
        defer { try? FileManager.default.removeItem(at: folder) }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let container = try makeContainer(folder: folder)
        let context = ModelContext(container); context.autosaveEnabled = false
        var snapshot = adversarialSnapshot(includeEmbeddedNull: false)
        let attemptTable = try XCTUnwrap(snapshot.tables.firstIndex { $0.model == "AttemptRecord" })
        snapshot.tables[attemptTable].rows.append(snapshot.tables[attemptTable].rows[0])
        try NFDataArchiveRawCapture.materializeInEmptyContext(snapshot, context: context)
        XCTAssertTrue(context.hasChanges)
        XCTAssertThrowsError(try NFDataArchiveRawCapture.capture(context: context), "A dirty context is not a durable predecessor")
        try context.save()
        let fresh = ModelContext(container); fresh.autosaveEnabled = false
        let captured = try NFDataArchiveRawCapture.capture(context: fresh)
        let capturedBytes = try captured.contentBytes()
        let expectedBytes = try snapshot.contentBytes()
        if capturedBytes != expectedBytes {
            // Synthetic fixtures only: retain complete evidence of a backend
            // transformation without weakening the byte-for-byte contract.
            for (name, bytes) in [("expected-raw-columns", expectedBytes), ("persisted-raw-columns", capturedBytes)] {
                let attachment = XCTAttachment(data: bytes, uniformTypeIdentifier: "public.json")
                attachment.name = name
                attachment.lifetime = .keepAlways
                add(attachment)
            }
        }
        let mismatchDescription = try rawColumnMismatchDescription(expected: snapshot, actual: captured)
        XCTAssertEqual(capturedBytes, expectedBytes, mismatchDescription)
        XCTAssertEqual(captured.tables.reduce(0) { $0 + $1.rows.count }, 27)
        for table in captured.tables {
            let expectedCount = table.model == "AttemptRecord" ? 3 : 2
            XCTAssertEqual(table.rows.count, expectedCount)
            XCTAssertEqual(try table.groups(by: ["id"]).count, 1, "Duplicate domain IDs must remain separate rows")
            XCTAssertEqual(Set(table.rows.compactMap(\.capturedPersistentID)).count, expectedCount)
        }
        let refs = try XCTUnwrap(captured.tables.first { $0.model == "AttemptReflectionRecord" })
        XCTAssertEqual(try refs.groups(by: ["attemptID"]).values.first?.count, 2)
        let checkpoints = try XCTUnwrap(captured.tables.first { $0.model == "SessionCheckpointRecord" })
        XCTAssertEqual(try checkpoints.groups(by: ["sessionID"]).values.first?.count, 2)
        let encoded = try captured.encoded(maximumBytes: 4 * 1_024 * 1_024)
        XCTAssertEqual(try NFDataArchiveRawSnapshot.decode(encoded, maximumBytes: encoded.count), captured)
    }

    @MainActor
    func testBeforeAfterReplayKeepsUnchangedPhysicalRowsAndNeverDuplicatesAnAcknowledgedMutation() throws {
        let container = try ModelContainer(for: Schema(NFSchemaV1.models), configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = ModelContext(container); context.autosaveEnabled = false
        try NFDataArchiveRawCapture.materializeInEmptyContext(adversarialSnapshot(includeEmbeddedNull: false), context: context)
        try context.save()
        let before = try NFDataArchiveRawCapture.capture(context: context)
        var after = before
        let attempt = try XCTUnwrap(after.tables.firstIndex { $0.model == "AttemptRecord" })
        after.tables[attempt].rows[0].columns["response"] = "An explicitly accepted replacement response".archiveRawValue
        let transition = try NFDataArchiveRawTransition(before: before, after: after)
        XCTAssertEqual(try transition.disposition(current: before), .needsApplication)
        XCTAssertEqual(try NFDataArchiveRawCapture.stageAcceptedTransition(transition, context: context), .needsApplication)
        try context.save()
        let fresh = ModelContext(container); fresh.autosaveEnabled = false
        let applied = try NFDataArchiveRawCapture.capture(context: fresh)
        XCTAssertEqual(try applied.contentBytes(), try after.contentBytes())
        for table in before.tables where table.model != "AttemptRecord" {
            XCTAssertEqual(Set(table.rows.compactMap(\.capturedPersistentID)),
                Set(try XCTUnwrap(applied.tables.first { $0.model == table.model }).rows.compactMap(\.capturedPersistentID)))
        }
        let beforeIDs = Set(before.tables[attempt].rows.compactMap(\.capturedPersistentID))
        let afterIDs = Set(try XCTUnwrap(applied.tables.first { $0.model == "AttemptRecord" }).rows.compactMap(\.capturedPersistentID))
        XCTAssertEqual(beforeIDs.intersection(afterIDs).count, 1)
        XCTAssertEqual(try NFDataArchiveRawCapture.stageAcceptedTransition(transition, context: fresh), .alreadyApplied)
        XCTAssertFalse(fresh.hasChanges)
        XCTAssertEqual(try NFDataArchiveRawCapture.capture(context: fresh), applied)
        var unrelatedArrival = applied
        unrelatedArrival.tables[attempt].rows.append(unrelatedArrival.tables[attempt].rows[0])
        XCTAssertEqual(try transition.disposition(current: unrelatedArrival), .conflict)
        var anotherResponse = before
        anotherResponse.tables[attempt].rows[0].columns["response"] = "Concurrent answer".archiveRawValue
        XCTAssertEqual(try transition.disposition(current: anotherResponse), .conflict)
    }

    @MainActor
    func testEmbeddedNullOriginalsSurviveCodecButMaterializationRefusesBeforeAnyMutation() throws {
        let original = adversarialSnapshot()
        let encoded = try original.encoded(maximumBytes: 4 * 1_024 * 1_024)
        let decoded = try NFDataArchiveRawSnapshot.decode(encoded, maximumBytes: encoded.count)
        XCTAssertEqual(decoded, original)
        XCTAssertEqual(try decoded.contentBytes(), try original.contentBytes())
        try NFDataArchiveRawCapture.verifyHydration(decoded)
        let container = try ModelContainer(for: Schema(NFSchemaV1.models), configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = ModelContext(container); context.autosaveEnabled = false
        let empty = try NFDataArchiveRawCapture.capture(context: context)
        XCTAssertThrowsError(try NFDataArchiveRawCapture.materializeInEmptyContext(decoded, context: context)) { error in
            guard case NFDataArchiveRawSnapshotError.unrepresentableText = error else {
                return XCTFail("Expected explicit text representability failure, received \(error)")
            }
        }
        XCTAssertFalse(context.hasChanges)
        XCTAssertEqual(try NFDataArchiveRawCapture.capture(context: context), empty)

        try NFDataArchiveRawCapture.materializeInEmptyContext(adversarialSnapshot(includeEmbeddedNull: false), context: context)
        try context.save()
        let before = try NFDataArchiveRawCapture.capture(context: context)
        var after = before
        let attempt = try XCTUnwrap(after.tables.firstIndex { $0.model == "AttemptRecord" })
        after.tables[attempt].rows[0].columns["response"] = "Original answer\u{0000}retained suffix".archiveRawValue
        let transition = try NFDataArchiveRawTransition(before: before, after: after)
        XCTAssertThrowsError(try NFDataArchiveRawCapture.stageAcceptedTransition(transition, context: context)) { error in
            XCTAssertEqual(error as? NFDataArchiveRawSnapshotError, .unrepresentableText("AttemptRecord.response"))
        }
        XCTAssertFalse(context.hasChanges)
        XCTAssertEqual(try NFDataArchiveRawCapture.capture(context: context), before)
        XCTAssertEqual(try String.fromArchiveRawValue(XCTUnwrap(after.tables[attempt].rows[0].columns["response"])),
            "Original answer\u{0000}retained suffix")
    }

    @MainActor
    func testFutureOrMissingColumnsAndWrongScalarTagsFailBeforeAnyStagedMutation() throws {
        let container = try ModelContainer(for: Schema(NFSchemaV1.models), configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = ModelContext(container); context.autosaveEnabled = false
        let empty = try NFDataArchiveRawCapture.capture(context: context)
        let original = adversarialSnapshot()
        for variant in 0..<4 {
            var invalid = original
            switch variant {
            case 0: invalid.tables[0].rows[0].columns.removeValue(forKey: "id")
            case 1: invalid.tables[0].rows[0].columns["future-field"] = .blob(Data([1, 2, 3]))
            case 2: invalid.tables[0].rows[0].columns["id"] = .textUTF8(Data("UUID text under the wrong typed tag".utf8))
            default: invalid.tables.append(invalid.tables[0])
            }
            XCTAssertThrowsError(try NFDataArchiveRawCapture.materializeInEmptyContext(invalid, context: context))
            XCTAssertFalse(context.hasChanges)
            XCTAssertEqual(try NFDataArchiveRawCapture.capture(context: context), empty)
        }
        let bytes = try original.encoded(maximumBytes: 4 * 1_024 * 1_024)
        XCTAssertThrowsError(try original.encoded(maximumBytes: bytes.count - 1))
        XCTAssertThrowsError(try NFDataArchiveRawSnapshot.decode(bytes, maximumBytes: bytes.count - 1))
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: bytes) as? [String: Any])
        object["version"] = 999
        let future = try JSONSerialization.data(withJSONObject: object)
        XCTAssertThrowsError(try NFDataArchiveRawSnapshot.decode(future, maximumBytes: 4 * 1_024 * 1_024))
    }

    @MainActor
    private func adversarialSnapshot(includeEmbeddedNull: Bool = true) -> NFDataArchiveRawSnapshot {
        let null = includeEmbeddedNull ? "\u{0000}" : ""
        var snapshot = NFDataArchiveRawCapture.emptySnapshot()
        let id = UUID(uuidString: "a1234567-b123-c123-d123-e12345678901")!
        for index in snapshot.tables.indices {
            let table = snapshot.tables[index]
            var original: [String: NFDataArchiveRawValue] = [:]
            for column in table.columnManifest {
                let type = column.type.hasSuffix("?") ? String(column.type.dropLast()) : column.type
                switch type {
                case "UUID": original[column.name] = id.archiveRawValue
                case "String": original[column.name] = "  \nfuture.\(table.model).\(column.name)\(null) e\u{0301}  ".archiveRawValue
                case "Int": original[column.name] = Int(-9_123_456_789).archiveRawValue
                case "Int64": original[column.name] = Int64(-8_123_456_789).archiveRawValue
                case "UInt64": original[column.name] = UInt64(9_123_456_789).archiveRawValue
                case "Bool": original[column.name] = true.archiveRawValue
                case "Double": original[column.name] = Double(-1_234.125).archiveRawValue
                case "Date": original[column.name] = Date(timeIntervalSinceReferenceDate: 1_234_567.125).archiveRawValue
                case "Data": original[column.name] = Data([0, 0xff, 0xc0, 0x80, 0x0a, 0x7f]).archiveRawValue
                default: XCTFail("Unsupported test scalar census: \(type)")
                }
            }
            var second = original
            for column in table.columnManifest where column.type.hasSuffix("?") { second[column.name] = .null }
            // Two rows with identical IDs; other differences prevent a winner
            // projection or Set from silently hiding the second raw payload.
            if let note = table.columnManifest.first(where: { $0.type == "String" && $0.name != "id" }) {
                second[note.name] = "Distinct raw second row \(null)".archiveRawValue
            }
            snapshot.tables[index].rows = [
                .init(capturedPersistentID: nil, columns: original),
                .init(capturedPersistentID: nil, columns: second)
            ]
        }
        return snapshot
    }
    private func rawColumnMismatchDescription(expected: NFDataArchiveRawSnapshot, actual: NFDataArchiveRawSnapshot) throws -> String {
        var differences: [String] = []
        for table in expected.tables.sorted(by: { $0.model < $1.model }) {
            guard let persisted = actual.tables.first(where: { $0.model == table.model }) else {
                differences.append("Missing model \(table.model)")
                continue
            }
            if table.rows.count != persisted.rows.count {
                differences.append("\(table.model) multiplicity: expected \(table.rows.count), actual \(persisted.rows.count)")
            }
            for column in table.columnManifest {
                func values(_ rows: [NFDataArchiveRawRow]) throws -> [String] {
                    try rows.map { row in
                        let bytes = try NFDataArchiveRawSnapshot.canonicalEncode(row.columns[column.name])
                        return String(decoding: bytes, as: UTF8.self)
                    }.sorted()
                }
                let before = try values(table.rows)
                let after = try values(persisted.rows)
                if before != after {
                    differences.append("\(table.model).\(column.name) [\(column.type)] expected=\(before), actual=\(after)")
                }
            }
        }
        if differences.isEmpty { return "Raw row multiset differs despite matching individual column multisets." }
        return "Raw persisted-column differences (first 30 of \(differences.count)):\n" + differences.prefix(30).joined(separator: "\n")
    }

    @MainActor
    private func makeContainer(folder: URL) throws -> ModelContainer {
        try ModelContainer(for: Schema(NFSchemaV1.models), configurations: [
            ModelConfiguration("RawDurable", schema: Schema(NFPersistentStoreLocation.durableModels),
                url: folder.appending(path: "Durable.store"), cloudKitDatabase: .none),
            ModelConfiguration("RawLocal", schema: Schema(NFPersistentStoreLocation.localOnlyModels),
                url: folder.appending(path: "Local.store"), cloudKitDatabase: .none)
        ])
    }

    private static let expectedColumns: [String: [NFDataArchiveRawColumnManifest]] = [
        "UserProfileRecord": [
            .init(name: "id", type: "UUID"),
            .init(name: "createdAt", type: "Date"),
            .init(name: "modifiedAt", type: "Date"),
            .init(name: "stageRaw", type: "String"),
            .init(name: "fieldsRaw", type: "String"),
            .init(name: "goalsRaw", type: "String"),
            .init(name: "dailyDuration", type: "Int"),
            .init(name: "timingModeRaw", type: "String"),
            .init(name: "aiModeRaw", type: "String"),
            .init(name: "iCloudEnabled", type: "Bool"),
            .init(name: "reducedMotion", type: "Bool"),
            .init(name: "hideTimers", type: "Bool"),
            .init(name: "excludeVisualSpatial", type: "Bool"),
            .init(name: "onboardingVersion", type: "Int"),
            .init(name: "claimsPolicyAcknowledgedVersion", type: "Int"),
            .init(name: "pccConsentVersion", type: "Int"),
            .init(name: "pccConsentAt", type: "Date?"),
            .init(name: "preferredLanguageCode", type: "String"),
            .init(name: "trainingDaysRaw", type: "String"),
            .init(name: "dayBoundaryHour", type: "Int"),
            .init(name: "ageBandAcknowledged16Plus", type: "Bool"),
            .init(name: "preferredAnswerModeRaw", type: "String"),
            .init(name: "reinforcementHapticsEnabled", type: "Bool"),
            .init(name: "reinforcementSoundEnabled", type: "Bool")
        ],
        "InputCalibrationRecord": [
            .init(name: "id", type: "UUID"),
            .init(name: "profileID", type: "UUID"),
            .init(name: "completedAt", type: "Date"),
            .init(name: "preferredAnswerModeRaw", type: "String"),
            .init(name: "keyboardLatencyMilliseconds", type: "Double?"),
            .init(name: "touchLatencyMilliseconds", type: "Double?"),
            .init(name: "pencilLatencyMilliseconds", type: "Double?")
        ],
        "ProgressAnnotationRecord": [
            .init(name: "id", type: "UUID"),
            .init(name: "startDate", type: "Date"),
            .init(name: "endDate", type: "Date"),
            .init(name: "note", type: "String"),
            .init(name: "includeInExport", type: "Bool"),
            .init(name: "createdAt", type: "Date"),
            .init(name: "modifiedAt", type: "Date")
        ],
        "AttemptRecord": [
            .init(name: "id", type: "UUID"),
            .init(name: "sessionID", type: "UUID"),
            .init(name: "itemID", type: "String"),
            .init(name: "templateID", type: "String"),
            .init(name: "seed", type: "UInt64"),
            .init(name: "gameID", type: "String"),
            .init(name: "skillID", type: "String"),
            .init(name: "skillWeightsRaw", type: "String"),
            .init(name: "domainContextRaw", type: "String"),
            .init(name: "transferBriefRaw", type: "String"),
            .init(name: "spatialDifficultyParametersRaw", type: "String"),
            .init(name: "prompt", type: "String"),
            .init(name: "response", type: "String"),
            .init(name: "correctAnswer", type: "Double"),
            .init(name: "correctAnswerText", type: "String"),
            .init(name: "isCorrect", type: "Bool"),
            .init(name: "confidenceRaw", type: "String?"),
            .init(name: "shownAt", type: "Date"),
            .init(name: "submittedAt", type: "Date"),
            .init(name: "activeDurationSeconds", type: "Double"),
            .init(name: "evidenceClassRaw", type: "String"),
            .init(name: "sessionSourceRaw", type: "String"),
            .init(name: "evidenceWeight", type: "Double"),
            .init(name: "errorCode", type: "String?"),
            .init(name: "scoringVersion", type: "Int"),
            .init(name: "deviceID", type: "UUID"),
            .init(name: "generationID", type: "UUID?"),
            .init(name: "sourceDocumentIDsRaw", type: "String"),
            .init(name: "sourceChunkIDsRaw", type: "String"),
            .init(name: "responseFormatRaw", type: "String"),
            .init(name: "wasSkipped", type: "Bool"),
            .init(name: "validationVersion", type: "Int"),
            .init(name: "assessmentBlockRaw", type: "String?"),
            .init(name: "planID", type: "String?"),
            .init(name: "planBlockID", type: "String?"),
            .init(name: "deterministicCredit", type: "Double"),
            .init(name: "hintCount", type: "Int"),
            .init(name: "inputModeRaw", type: "String"),
            .init(name: "interruptionCount", type: "Int"),
            .init(name: "revisionCount", type: "Int"),
            .init(name: "accommodationFlagsRaw", type: "String"),
            .init(name: "wasTimed", type: "Bool"),
            .init(name: "assessmentDescriptorID", type: "String?"),
            .init(name: "assessmentTemplateFamily", type: "String?"),
            .init(name: "assessmentFormatRaw", type: "String?"),
            .init(name: "assessmentMechanicID", type: "String?"),
            .init(name: "assessmentSubskillID", type: "String?"),
            .init(name: "assessmentSeed", type: "UInt64?"),
            .init(name: "assessmentCycle", type: "Int?")
        ],
        "AttemptReflectionRecord": [
            .init(name: "id", type: "UUID"),
            .init(name: "attemptID", type: "UUID"),
            .init(name: "deterministicErrorCode", type: "String?"),
            .init(name: "selectedErrorCodeRaw", type: "String?"),
            .init(name: "triggerRaw", type: "String"),
            .init(name: "note", type: "String"),
            .init(name: "createdAt", type: "Date"),
            .init(name: "policyVersion", type: "Int")
        ],
        "ItemReportRecord": [
            .init(name: "id", type: "UUID"),
            .init(name: "itemID", type: "String"),
            .init(name: "templateID", type: "String"),
            .init(name: "prompt", type: "String"),
            .init(name: "reason", type: "String"),
            .init(name: "note", type: "String"),
            .init(name: "createdAt", type: "Date"),
            .init(name: "status", type: "String"),
            .init(name: "seed", type: "UInt64"),
            .init(name: "generatorVersion", type: "Int"),
            .init(name: "provenanceSummary", type: "String"),
            .init(name: "sourceIDsRaw", type: "String"),
            .init(name: "sourceChunkIDsRaw", type: "String"),
            .init(name: "assessmentDescriptorID", type: "String?"),
            .init(name: "diagnosticPayload", type: "Data"),
            .init(name: "diagnosticDigest", type: "String"),
            .init(name: "diagnosticPayloadState", type: "String")
        ],
        "SourceDocumentRecord": [
            .init(name: "id", type: "UUID"),
            .init(name: "filename", type: "String"),
            .init(name: "typeIdentifier", type: "String"),
            .init(name: "sizeBytes", type: "Int64"),
            .init(name: "importedAt", type: "Date"),
            .init(name: "indexState", type: "String"),
            .init(name: "aiPolicyRaw", type: "String"),
            .init(name: "pccExcerptConsentPolicyVersion", type: "Int"),
            .init(name: "pccExcerptConsentDocumentIDRaw", type: "String"),
            .init(name: "pccExcerptConsentedAt", type: "Date?"),
            .init(name: "syncPolicy", type: "String"),
            .init(name: "localPath", type: "String"),
            .init(name: "characterCount", type: "Int"),
            .init(name: "chunkCount", type: "Int"),
            .init(name: "extractionVersion", type: "Int"),
            .init(name: "csvSelectedColumnIDsRaw", type: "String"),
            .init(name: "indexError", type: "String?"),
            .init(name: "modifiedAt", type: "Date")
        ],
        "SourceChunkRecord": [
            .init(name: "id", type: "String"),
            .init(name: "documentID", type: "UUID"),
            .init(name: "documentVersion", type: "Int"),
            .init(name: "sourceName", type: "String"),
            .init(name: "page", type: "Int?"),
            .init(name: "lineStart", type: "Int?"),
            .init(name: "lineEnd", type: "Int?"),
            .init(name: "section", type: "String?"),
            .init(name: "characterStart", type: "Int?"),
            .init(name: "characterEnd", type: "Int?"),
            .init(name: "nearbyHeading", type: "String?"),
            .init(name: "language", type: "String?"),
            .init(name: "contentTypeTagsRaw", type: "String"),
            .init(name: "text", type: "String"),
            .init(name: "contentHash", type: "String"),
            .init(name: "ordinal", type: "Int"),
            .init(name: "createdAt", type: "Date")
        ],
        "AIGenerationRecord": [
            .init(name: "id", type: "UUID"),
            .init(name: "createdAt", type: "Date"),
            .init(name: "capabilityRaw", type: "String"),
            .init(name: "labRaw", type: "String"),
            .init(name: "fieldRaw", type: "String"),
            .init(name: "topic", type: "String"),
            .init(name: "routeRaw", type: "String"),
            .init(name: "routeReason", type: "String"),
            .init(name: "promptVersion", type: "Int"),
            .init(name: "validationVersion", type: "Int"),
            .init(name: "modelIdentifier", type: "String"),
            .init(name: "sourceDocumentIDsRaw", type: "String"),
            .init(name: "sourceChunkIDsRaw", type: "String"),
            .init(name: "repairCount", type: "Int"),
            .init(name: "cacheKey", type: "String"),
            .init(name: "isFallback", type: "Bool"),
            .init(name: "questionCount", type: "Int"),
            .init(name: "resultPayload", type: "Data"),
            .init(name: "payloadExpiresAt", type: "Date")
        ],
        "WeeklyTransferStateRecord": [
            .init(name: "id", type: "String"),
            .init(name: "completedMissionIDsRaw", type: "String"),
            .init(name: "deferredUntilPayload", type: "Data"),
            .init(name: "modifiedAt", type: "Date")
        ],
        "ReassessmentStateRecord": [
            .init(name: "id", type: "String"),
            .init(name: "completedCycle", type: "Int"),
            .init(name: "activeDayAnchor", type: "Date?"),
            .init(name: "dueAt", type: "Date?"),
            .init(name: "deferredUntil", type: "Date?"),
            .init(name: "targetBlockRaw", type: "String?"),
            .init(name: "lastCompletedAt", type: "Date?"),
            .init(name: "lastCompletedBlockRaw", type: "String?"),
            .init(name: "modifiedAt", type: "Date")
        ],
        "SessionCheckpointRecord": [
            .init(name: "id", type: "UUID"),
            .init(name: "sessionID", type: "UUID"),
            .init(name: "labRaw", type: "String"),
            .init(name: "sourceRaw", type: "String"),
            .init(name: "seed", type: "UInt64"),
            .init(name: "currentIndex", type: "Int"),
            .init(name: "itemCount", type: "Int"),
            .init(name: "response", type: "String"),
            .init(name: "scratchpad", type: "String"),
            .init(name: "resultsRaw", type: "String"),
            .init(name: "creditsRaw", type: "String"),
            .init(name: "assessmentDescriptorIDsRaw", type: "String"),
            .init(name: "assessmentEventsRaw", type: "String"),
            .init(name: "evidenceClassRaw", type: "String"),
            .init(name: "updatedAt", type: "Date"),
            .init(name: "isComplete", type: "Bool"),
            .init(name: "planID", type: "String?"),
            .init(name: "planBlockID", type: "String?"),
            .init(name: "recommendationRationale", type: "String?"),
            .init(name: "hasCommittedCurrentItem", type: "Bool"),
            .init(name: "assessmentBlockRaw", type: "String?"),
            .init(name: "assessmentCycle", type: "Int?"),
            .init(name: "activeDurationSeconds", type: "Double"),
            .init(name: "assessmentStopReasonRaw", type: "String?"),
            .init(name: "pendingReflectionAttemptID", type: "UUID?"),
            .init(name: "reflectionTriggerRaw", type: "String?"),
            .init(name: "selectedReflectionCodeRaw", type: "String?"),
            .init(name: "reflectionNote", type: "String?")
        ],
        "DailyPlanRecord": [
            .init(name: "id", type: "String"),
            .init(name: "profileID", type: "UUID"),
            .init(name: "localDayKey", type: "String"),
            .init(name: "policyVersion", type: "Int"),
            .init(name: "payload", type: "Data"),
            .init(name: "createdAt", type: "Date"),
            .init(name: "timeZoneIdentifier", type: "String"),
            .init(name: "utcOffsetSeconds", type: "Int"),
            .init(name: "dayBoundaryHour", type: "Int"),
            .init(name: "boundaryStart", type: "Date"),
            .init(name: "nextBoundaryAt", type: "Date"),
            .init(name: "travelPreservedUntil", type: "Date?")
        ]
    ]
}

import Darwin

final class NFDataArchiveRestoreJournalTests: XCTestCase {
    private enum Injected: Error { case stop }
    private let namespace = "journal-fixture-account"
    private let owner = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!

    @MainActor
    func testEveryAcceptanceWriteBoundaryRetainsExactPlanAndNeverPublishesHalfAcceptedState() async throws {
        let boundaries: [NFDataArchiveRestoreJournal.Boundary] = [.beforePlanWrite, .afterPlanWrite,
            .beforeDescriptorWrite, .afterDescriptorWrite, .beforeInitialProgressWrite, .afterInitialProgressWrite,
            .beforeAcceptancePublish, .afterAcceptancePublish]
        for boundary in boundaries {
            let root = temporaryRoot(); defer { try? FileManager.default.removeItem(at: root) }
            let plan = try makePlan()
            let journal = NFDataArchiveRestoreJournal(root: root, fault: { if $0 == boundary { throw Injected.stop } })
            do { _ = try await journal.accept(plan); XCTFail("Missing fault at \(boundary)") } catch Injected.stop { }
            let reopened = NFDataArchiveRestoreJournal(root: root)
            let inspection = try await reopened.inspect(namespace: namespace, installationOwnerID: owner)
            XCTAssertEqual(inspection.count, 1)
            XCTAssertEqual(inspection[0].isStaging, boundary != .afterAcceptancePublish)
            XCTAssertEqual(inspection[0].descriptor != nil, boundary == .afterAcceptancePublish)
            let accepted = try await reopened.accept(plan)
            XCTAssertEqual(accepted.plan, plan, "Retry must reuse every original byte and fixed policy")
            XCTAssertEqual(accepted.progress.revision, 0)
            let again = try await reopened.accept(plan)
            XCTAssertEqual(again.descriptor, accepted.descriptor)
            XCTAssertEqual(again.progress, accepted.progress)
            let final = try await reopened.inspect(namespace: namespace, installationOwnerID: owner)
            XCTAssertEqual(final.count, 1)
            XCTAssertFalse(final[0].isStaging)
        }
    }

    @MainActor
    func testLostProgressAcknowledgementIsReconciledIdempotentlyAndNeverRewindsRecovery() async throws {
        for boundary in [NFDataArchiveRestoreJournal.Boundary.beforeProgressPublish, .afterProgressPublish] {
            let root = temporaryRoot(); defer { try? FileManager.default.removeItem(at: root) }
            let plan = try makePlan()
            let seed = NFDataArchiveRestoreJournal(root: root)
            _ = try await seed.accept(plan)
            let failing = NFDataArchiveRestoreJournal(root: root, fault: { if $0 == boundary { throw Injected.stop } })
            do {
                _ = try await failing.mark(transactionID: plan.transactionID, namespace: namespace,
                    installationOwnerID: owner, expectedRevision: 0, phase: .mutationMayHaveStarted)
                XCTFail("Expected injected phase write fault")
            } catch Injected.stop { }
            let reopened = NFDataArchiveRestoreJournal(root: root)
            let observed = try await reopened.load(transactionID: plan.transactionID, namespace: namespace, installationOwnerID: owner)
            XCTAssertEqual(observed.progress.revision, boundary == .beforeProgressPublish ? 0 : 1)
            let acknowledged = try await reopened.mark(transactionID: plan.transactionID, namespace: namespace,
                installationOwnerID: owner, expectedRevision: 0, phase: .mutationMayHaveStarted)
            XCTAssertEqual(acknowledged.revision, 1)
            let recovery = try await reopened.mark(transactionID: plan.transactionID, namespace: namespace,
                installationOwnerID: owner, expectedRevision: 1, phase: .recoveryRequired)
            XCTAssertEqual(recovery.revision, 2)
            do {
                _ = try await reopened.mark(transactionID: plan.transactionID, namespace: namespace,
                    installationOwnerID: owner, expectedRevision: 2, phase: .mutationMayHaveStarted)
                XCTFail("A hint must not rewind recovery")
            } catch NFRestoreJournalError.recoveryConflict { }
            do {
                _ = try await reopened.mark(transactionID: plan.transactionID, namespace: namespace,
                    installationOwnerID: owner, expectedRevision: 0, phase: .recoveryRequired)
                XCTFail("An unrelated stale revision is not an idempotent retry")
            } catch NFRestoreJournalError.staleRevision { }
        }
    }

    @MainActor
    func testMixedDatabaseStateReconcilesEachFrozenDomainWithoutTreatingBothAsCommitted() async throws {
        let root = temporaryRoot(); defer { try? FileManager.default.removeItem(at: root) }
        let plan = try makePlan()
        let journal = NFDataArchiveRestoreJournal(root: root)
        let loaded = try await journal.accept(plan)
        var mixed = plan.raw.before
        for index in mixed.tables.indices where mixed.tables[index].domain == .durable {
            mixed.tables[index] = try XCTUnwrap(plan.raw.after.tables.first { $0.model == mixed.tables[index].model })
        }
        let partial = try NFRestoreJournalCodec.reconcile(loaded, current: mixed, files: ["source": plan.files[0].before])
        XCTAssertEqual(partial.durableDatabase, .alreadyApplied)
        XCTAssertEqual(partial.localDatabase, .needsApplication)
        XCTAssertEqual(partial.files["source"], .needsApplication)
        XCTAssertFalse(partial.isComplete)
        XCTAssertFalse(partial.hasConflict)
        do {
            _ = try await journal.verifyComplete(transactionID: plan.transactionID, namespace: namespace,
                installationOwnerID: owner, expectedRevision: 0, current: mixed, files: ["source": plan.files[0].after])
            XCTFail("Mixed database state cannot produce a completed receipt")
        } catch NFRestoreJournalError.recoveryConflict { }
        let stillAccepted = try await journal.load(transactionID: plan.transactionID, namespace: namespace, installationOwnerID: owner)
        XCTAssertEqual(stillAccepted.progress.phase, .accepted)
    }

    @MainActor
    func testThirdStateUnrelatedArrivalsAndMissingFileObservationsPreserveAcceptedMembership() async throws {
        let root = temporaryRoot(); defer { try? FileManager.default.removeItem(at: root) }
        let plan = try makePlan()
        let journal = NFDataArchiveRestoreJournal(root: root)
        let loaded = try await journal.accept(plan)
        var changed = plan.raw.after
        let annotation = try XCTUnwrap(changed.tables.firstIndex { $0.model == "ProgressAnnotationRecord" })
        changed.tables[annotation].rows.append(changed.tables[annotation].rows[0])
        let conflicting = try NFRestoreJournalCodec.reconcile(loaded, current: changed, files: ["source": Data("peer bytes".utf8)])
        XCTAssertEqual(conflicting.durableDatabase, .conflict)
        XCTAssertEqual(conflicting.files["source"], .conflict)
        XCTAssertTrue(conflicting.hasConflict)
        XCTAssertThrowsError(try NFRestoreJournalCodec.reconcile(loaded, current: plan.raw.after, files: [:]))
        let retained = try await journal.load(transactionID: plan.transactionID, namespace: namespace, installationOwnerID: owner)
        XCTAssertEqual(retained.plan, plan)
        XCTAssertEqual(retained.plan.acceptedCounts, ["annotations": 2, "calibrations": 1])
        XCTAssertEqual(changed.tables[annotation].rows.count, 3, "No reducer writes or expands deletion membership")
    }

    @MainActor
    func testVerifiedCompletionRequiresActualPostimagesSurvivesLostAcknowledgementAndCannotResurrectDeletion() async throws {
        let root = temporaryRoot(); defer { try? FileManager.default.removeItem(at: root) }
        let plan = try makePlan()
        let original = NFDataArchiveRestoreJournal(root: root)
        _ = try await original.accept(plan)
        let failing = NFDataArchiveRestoreJournal(root: root, fault: { if $0 == .afterProgressPublish { throw Injected.stop } })
        do {
            _ = try await failing.verifyComplete(transactionID: plan.transactionID, namespace: namespace,
                installationOwnerID: owner, expectedRevision: 0, current: plan.raw.after, files: ["source": plan.files[0].after])
            XCTFail("Expected completion acknowledgement failure")
        } catch Injected.stop { }
        let reopened = NFDataArchiveRestoreJournal(root: root)
        let loaded = try await reopened.load(transactionID: plan.transactionID, namespace: namespace, installationOwnerID: owner)
        XCTAssertEqual(loaded.progress.phase, .verifiedComplete)
        XCTAssertEqual(loaded.progress.completion?.acceptedCounts, plan.acceptedCounts)
        let retry = try await reopened.verifyComplete(transactionID: plan.transactionID, namespace: namespace,
            installationOwnerID: owner, expectedRevision: 0, current: plan.raw.after, files: ["source": plan.files[0].after])
        XCTAssertEqual(retry, loaded.progress)
        XCTAssertThrowsError(try NFRestoreJournalCodec.reconcile(loaded, current: plan.raw.before,
            files: ["source": plan.files[0].before]), "Completed restore cannot resurrect subsequently deleted data")
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent(plan.transactionID.uuidString.lowercased())
            .appendingPathComponent("plan.json").path), "Completion retains original private recovery bytes")
    }

    @MainActor
    func testCodecRejectsFutureUnknownAndCorruptFieldsWithoutRewritingOriginalBytes() async throws {
        let root = temporaryRoot(); defer { try? FileManager.default.removeItem(at: root) }
        let plan = try makePlan()
        let journal = NFDataArchiveRestoreJournal(root: root)
        _ = try await journal.accept(plan)
        let directory = root.appendingPathComponent(plan.transactionID.uuidString.lowercased())
        let url = directory.appendingPathComponent("accepted.json")
        let original = try Data(contentsOf: url)
        for variant in 0..<3 {
            var object = try XCTUnwrap(JSONSerialization.jsonObject(with: original) as? [String: Any])
            switch variant {
            case 0: object["version"] = 999
            case 1: object["unknownFutureAuthority"] = "must not be discarded"
            default: object["planDigest"] = String(repeating: "0", count: 64)
            }
            let altered = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .withoutEscapingSlashes])
            try altered.write(to: url)
            let reopened = NFDataArchiveRestoreJournal(root: root)
            do {
                _ = try await reopened.load(transactionID: plan.transactionID, namespace: namespace, installationOwnerID: owner)
                XCTFail("Corrupt or future artifact must block recovery")
            } catch { }
            XCTAssertEqual(try Data(contentsOf: url), altered)
        }
        try original.write(to: url)
        let planURL = directory.appendingPathComponent("plan.json")
        var bytes = try Data(contentsOf: planURL); bytes.append(0)
        try bytes.write(to: planURL)
        do {
            _ = try await journal.load(transactionID: plan.transactionID, namespace: namespace, installationOwnerID: owner)
            XCTFail("Plan byte mismatch must be retained")
        } catch NFRestoreJournalError.digestMismatch { }
        XCTAssertEqual(try Data(contentsOf: planURL), bytes)
    }

    @MainActor
    func testWrongOwnerNamespaceChangedPlanUnsafePathsAndBoundsNeverAcceptNewAuthority() async throws {
        let root = temporaryRoot(); defer { try? FileManager.default.removeItem(at: root) }
        let plan = try makePlan()
        let journal = NFDataArchiveRestoreJournal(root: root)
        let accepted = try await journal.accept(plan)
        for pair in [("other-account", owner), (namespace, UUID())] {
            do {
                _ = try await journal.inspect(namespace: pair.0, installationOwnerID: pair.1)
                XCTFail("Discovery must block wrong-account access to shared surfaces")
            } catch NFRestoreJournalError.wrongOwner { }
        }
        let changed = NFRestoreJournalPlan(transactionID: plan.transactionID, namespace: namespace, installationOwnerID: owner,
            sourceDigest: plan.sourceDigest, permittedPayload: Data("different accepted value".utf8), policy: .keepExisting,
            acceptedCounts: plan.acceptedCounts, raw: plan.raw, files: plan.files)
        do { _ = try await journal.accept(changed); XCTFail("Same command must not rebuild its plan") }
        catch NFRestoreJournalError.conflictingPlan { }
        for path in ["../live", "/live", "a//b", "a/./b", "a\\b", "a\u{0000}b"] {
            let unsafe = NFRestoreJournalPlan(transactionID: UUID(), namespace: namespace, installationOwnerID: owner,
                sourceDigest: plan.sourceDigest, permittedPayload: plan.permittedPayload, policy: .replaceAll,
                acceptedCounts: plan.acceptedCounts, raw: plan.raw,
                files: [.init(id: "x", domain: .sourceFile, relativePath: path, before: nil, after: Data())])
            XCTAssertThrowsError(try NFRestoreJournalCodec.validate(unsafe))
        }
        let small = NFDataArchiveRestoreJournal(root: root, maximumPlanBytes: 16)
        do {
            _ = try await small.load(transactionID: plan.transactionID, namespace: namespace, installationOwnerID: owner)
            XCTFail("File bounds apply after restart too")
        } catch NFRestoreJournalError.oversized { }
        let retained = try await journal.load(transactionID: plan.transactionID, namespace: namespace, installationOwnerID: owner)
        XCTAssertEqual(retained.descriptor, accepted.descriptor)
        XCTAssertEqual(retained.plan, plan)
    }

    @MainActor
    func testInvalidationSurvivesFailedCleanupAndRemovesReplayAuthorityBeforeRawArtifacts() async throws {
        for boundary in [NFDataArchiveRestoreJournal.Boundary.afterInvalidationPublish, .beforeCleanup, .beforeCleanupReceipt, .afterCleanup] {
            let root = temporaryRoot(); defer { try? FileManager.default.removeItem(at: root) }
            let plan = try makePlan()
            let journal = NFDataArchiveRestoreJournal(root: root)
            _ = try await journal.accept(plan)
            let interruptedCopy = root.appendingPathComponent(plan.transactionID.uuidString.lowercased()).appendingPathComponent(".write-crashed")
            try Data("PRIVATE-INTERRUPTED-BEFORE-IMAGE".utf8).write(to: interruptedCopy)
            let failing = NFDataArchiveRestoreJournal(root: root, fault: { if $0 == boundary { throw Injected.stop } })
            do {
                _ = try await failing.invalidate(transactionID: plan.transactionID, namespace: namespace,
                    installationOwnerID: owner, expectedRevision: 0)
                try await failing.removeInvalidated(transactionID: plan.transactionID, namespace: namespace, installationOwnerID: owner)
                XCTFail("Expected cleanup boundary fault")
            } catch Injected.stop { }
            let reopened = NFDataArchiveRestoreJournal(root: root)
            let inspection = try await reopened.inspect(namespace: namespace, installationOwnerID: owner)
            if boundary == .afterCleanup { XCTAssertEqual(inspection.first?.progress?.phase, .cleaned) }
            else {
                XCTAssertEqual(inspection.first?.progress?.phase, .invalidated)
                if boundary != .beforeCleanupReceipt {
                    let retained = try await reopened.load(transactionID: plan.transactionID, namespace: namespace, installationOwnerID: owner)
                    XCTAssertThrowsError(try NFRestoreJournalCodec.reconcile(retained, current: plan.raw.before,
                        files: ["source": plan.files[0].before]))
                }
                do { _ = try await reopened.accept(plan); XCTFail("Invalidated ID is not fresh restore authority") }
                catch NFRestoreJournalError.invalidated { }
            }
            try await reopened.removeInvalidated(transactionID: plan.transactionID, namespace: namespace, installationOwnerID: owner)
            let cleaned = try await reopened.inspect(namespace: namespace, installationOwnerID: owner)
            XCTAssertEqual(cleaned.first?.progress?.phase, .cleaned)
            XCTAssertFalse(FileManager.default.fileExists(atPath: interruptedCopy.path))
            XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent(plan.transactionID.uuidString.lowercased())
                .appendingPathComponent("plan.json").path))
            do { _ = try await reopened.accept(plan); XCTFail("Cleaned command tombstone must prevent resurrection") }
            catch NFRestoreJournalError.invalidated { }
        }
    }

    @MainActor
    func testMissingMarkersSymlinkedPayloadAndPostInitializationGrowthStayBlockedAndUntouched() async throws {
        let root = temporaryRoot(); defer { try? FileManager.default.removeItem(at: root) }
        let plan = try makePlan()
        let journal = NFDataArchiveRestoreJournal(root: root)
        let loaded = try await journal.accept(plan)
        let folder = root.appendingPathComponent(plan.transactionID.uuidString.lowercased())
        let payload = folder.appendingPathComponent("plan.json")
        let original = try Data(contentsOf: payload)
        let bounded = NFDataArchiveRestoreJournal(root: root, maximumPlanBytes: loaded.descriptor.planByteCount)
        _ = try await bounded.load(transactionID: plan.transactionID, namespace: namespace, installationOwnerID: owner)
        var grown = original; grown.append(0)
        try grown.write(to: payload)
        do {
            _ = try await bounded.load(transactionID: plan.transactionID, namespace: namespace, installationOwnerID: owner)
            XCTFail("A file grown after initialization must still be bounded before allocation")
        } catch NFRestoreJournalError.oversized { }
        XCTAssertEqual(try Data(contentsOf: payload), grown)
        let external = temporaryRoot(); defer { try? FileManager.default.removeItem(at: external) }
        try Data("UNRELATED-PRIVATE-FILE".utf8).write(to: external)
        try FileManager.default.removeItem(at: payload)
        try FileManager.default.createSymbolicLink(at: payload, withDestinationURL: external)
        do {
            _ = try await journal.load(transactionID: plan.transactionID, namespace: namespace, installationOwnerID: owner)
            XCTFail("Payload symlinks must never be read as an accepted plan")
        } catch { }
        XCTAssertEqual(try Data(contentsOf: external), Data("UNRELATED-PRIVATE-FILE".utf8))
        try FileManager.default.removeItem(at: payload)
        try original.write(to: payload)
        let progressURL = folder.appendingPathComponent("progress.json")
        try FileManager.default.removeItem(at: progressURL)
        do {
            _ = try await journal.inspect(namespace: namespace, installationOwnerID: owner)
            XCTFail("Missing accepted metadata is a recovery block, not no pending restore")
        } catch NFRestoreJournalError.ioFailure { }
        XCTAssertEqual(try Data(contentsOf: payload), original)
    }

    @MainActor
    func testNamedPipePayloadIsRejectedWithoutWaitingForAWriter() async throws {
        let root = temporaryRoot(); defer { try? FileManager.default.removeItem(at: root) }
        let plan = try makePlan()
        let journal = NFDataArchiveRestoreJournal(root: root)
        _ = try await journal.accept(plan)
        let payload = root.appendingPathComponent(plan.transactionID.uuidString.lowercased()).appendingPathComponent("plan.json")
        try FileManager.default.removeItem(at: payload)
        XCTAssertEqual(mkfifo(payload.path, 0o600), 0)
        do {
            _ = try await journal.load(transactionID: plan.transactionID, namespace: namespace, installationOwnerID: owner)
            XCTFail("A pipe must never be accepted as recovery authority")
        } catch NFRestoreJournalError.unsafePath { }
        var metadata = stat()
        XCTAssertEqual(lstat(payload.path, &metadata), 0)
        XCTAssertEqual(metadata.st_mode & S_IFMT, S_IFIFO)
    }

    @MainActor
    func testCompetingFileDescriptorReturnsBusyWithoutSleepingOrPublishingPlan() async throws {
        let root = temporaryRoot(); defer { try? FileManager.default.removeItem(at: root) }
        let journal = NFDataArchiveRestoreJournal(root: root)
        let initial = try await journal.inspect(namespace: namespace, installationOwnerID: owner)
        XCTAssertTrue(initial.isEmpty)
        let fd = Darwin.open(root.appendingPathComponent("journal.lock").path, O_RDWR)
        XCTAssertGreaterThanOrEqual(fd, 0)
        guard fd >= 0 else { return }
        defer { flock(fd, LOCK_UN); Darwin.close(fd) }
        XCTAssertEqual(flock(fd, LOCK_EX | LOCK_NB), 0)
        do { _ = try await journal.accept(makePlan()); XCTFail("Competing FD must not enter publication") }
        catch NFRestoreJournalError.busy { }
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: root.path), ["journal.lock"])
    }

    @MainActor
    func testJournalPermissionsAndInspectionKeepProtectedRawCanariesPrivate() async throws {
        let root = temporaryRoot(); defer { try? FileManager.default.removeItem(at: root) }
        let plan = try makePlan()
        let journal = NFDataArchiveRestoreJournal(root: root)
        let loaded = try await journal.accept(plan)
        let directory = root.appendingPathComponent(plan.transactionID.uuidString.lowercased())
        for url in [root, directory, directory.appendingPathComponent("plan.json"),
                    directory.appendingPathComponent("accepted.json"), directory.appendingPathComponent("progress.json")] {
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            let permissions = try XCTUnwrap(attributes[.posixPermissions] as? NSNumber).intValue
            XCTAssertEqual(permissions & 0o077, 0)
        }
        XCTAssertEqual(loaded.plan.files[0].before, Data("PROTECTED-KEY-AND-PRIVATE-SOURCE".utf8))
        let status = try await journal.inspect(namespace: namespace, installationOwnerID: owner)
        XCTAssertFalse(String(describing: status).contains("PROTECTED-KEY"))
        XCTAssertNotEqual(NFRestoreJournalCodec.fileStateDigest(nil), NFRestoreJournalCodec.fileStateDigest(Data()))
        let observedAbsence: [String: Data?] = ["source": nil]
        let result = try NFRestoreJournalCodec.reconcile(loaded, current: plan.raw.after, files: observedAbsence)
        XCTAssertEqual(result.files["source"], .conflict, "Absence is different from a present empty file")
    }

    @MainActor
    func testCompletedOtherAccountJournalDoesNotAuthorizeItsPayloadOrBlockAFreshPlan() async throws {
        let root = temporaryRoot(); defer { try? FileManager.default.removeItem(at: root) }
        let journal = NFDataArchiveRestoreJournal(root: root)
        let first = try makePlan()
        _ = try await journal.accept(first)
        _ = try await journal.verifyComplete(transactionID: first.transactionID, namespace: namespace,
            installationOwnerID: owner, expectedRevision: 0, current: first.raw.after, files: ["source": first.files[0].after])
        let otherOwner = UUID()
        let second = NFRestoreJournalPlan(transactionID: UUID(), namespace: "different-account",
            installationOwnerID: otherOwner, sourceDigest: first.sourceDigest, permittedPayload: first.permittedPayload,
            policy: .keepExisting, acceptedCounts: first.acceptedCounts, raw: first.raw, files: first.files)
        let accepted = try await journal.accept(second)
        XCTAssertEqual(accepted.plan, second)
        do {
            _ = try await journal.load(transactionID: first.transactionID, namespace: second.namespace, installationOwnerID: otherOwner)
            XCTFail("A fresh plan must not authorize reading an earlier account's private before-images")
        } catch NFRestoreJournalError.wrongOwner { }
        let retained = try await journal.load(transactionID: first.transactionID, namespace: namespace, installationOwnerID: owner)
        XCTAssertEqual(retained.plan, first)
    }

    @MainActor
    func testApplicationStoreLeaseRejectsASecondOwnerAndReleasesForTheNextLaunch() throws {
        let support = temporaryRoot(); defer { try? FileManager.default.removeItem(at: support) }
        var first: NFApplicationStoreLease? = try .init(applicationSupportURL: support)
        try withExtendedLifetime(first) {
            XCTAssertThrowsError(try NFApplicationStoreLease(applicationSupportURL: support)) { error in
                guard case NFApplicationStoreLease.Failure.busy = error else { return XCTFail("Wrong lease failure") }
            }
            let lock = support.appendingPathComponent("NeuroForgeStoreAccess.lock")
            XCTAssertEqual(try Data(contentsOf: lock), Data(), "The process lock must contain no private payload")
        }
        first = nil
        let next = try NFApplicationStoreLease(applicationSupportURL: support)
        withExtendedLifetime(next) { XCTAssertNotNil(next) }
    }

    @MainActor
    func testApplicationLeaseRejectsSymlinkAndHardLinkWithoutEditingTheTarget() throws {
        let support = temporaryRoot(); defer { try? FileManager.default.removeItem(at: support) }
        try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        let unrelated = support.appendingPathComponent("unrelated-private.txt")
        let original = Data("UNCHANGED-PRIVATE-ORIGINAL".utf8)
        try original.write(to: unrelated)
        let lock = support.appendingPathComponent("NeuroForgeStoreAccess.lock")
        try FileManager.default.createSymbolicLink(at: lock, withDestinationURL: unrelated)
        XCTAssertThrowsError(try NFApplicationStoreLease(applicationSupportURL: support))
        XCTAssertEqual(try Data(contentsOf: unrelated), original)
        try FileManager.default.removeItem(at: lock)
        try FileManager.default.linkItem(at: unrelated, to: lock)
        XCTAssertThrowsError(try NFApplicationStoreLease(applicationSupportURL: support))
        XCTAssertEqual(try Data(contentsOf: unrelated), original)
    }

    @MainActor
    func testPrivateArtifactCleanupDoesNotReleaseTheOpenProcessStoreLease() throws {
        let support = temporaryRoot(); defer { try? FileManager.default.removeItem(at: support) }
        let lease = try NFApplicationStoreLease(applicationSupportURL: support)
        let root = try NFRestoreJournalLocation.root(applicationSupportURL: support)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data("PRIVATE".utf8).write(to: root.appendingPathComponent("unknown"))
        try NFRestoreJournalLocation.purgeAllApplicationState(applicationSupportURL: support)
        try withExtendedLifetime(lease) {
            XCTAssertThrowsError(try NFApplicationStoreLease(applicationSupportURL: support))
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.path))
    }

    @MainActor
    func testStartupDiscoveryBlocksAcceptedAndOtherAccountArtifactsBeforeOpeningAnyStore() async throws {
        let support = temporaryRoot(); defer { try? FileManager.default.removeItem(at: support) }
        let empty = await NFRestoreStartupGate.inspect(applicationSupportURL: support)
        XCTAssertTrue(empty.permitsModelContainerOpen)
        XCTAssertFalse(FileManager.default.fileExists(atPath: support.path), "Read-only absence check must not create storage")
        let journal = NFDataArchiveRestoreJournal(root: try NFRestoreJournalLocation.root(applicationSupportURL: support))
        let plan = try makePlan()
        _ = try await journal.accept(plan)
        let blocked = await NFRestoreStartupGate.inspect(applicationSupportURL: support)
        XCTAssertEqual(blocked, .blocked(.init(reason: .unfinished)))
        XCTAssertFalse(blocked.permitsModelContainerOpen)
        let all = try await journal.inspectAllNamespaces()
        XCTAssertEqual(all.first?.descriptor?.namespace, namespace)
        do {
            _ = try await journal.load(transactionID: plan.transactionID, namespace: "different-account", installationOwnerID: owner)
            XCTFail("Shared discovery is not another account's payload authority")
        } catch NFRestoreJournalError.wrongOwner { }
        XCTAssertFalse(String(describing: blocked).contains("PROTECTED-KEY"))
    }

    @MainActor
    func testStartupCompletionRequiresIntactAcceptedArtifactsAndCleanupReceipt() async throws {
        let support = temporaryRoot(); defer { try? FileManager.default.removeItem(at: support) }
        let root = try NFRestoreJournalLocation.root(applicationSupportURL: support)
        let journal = NFDataArchiveRestoreJournal(root: root)
        let plan = try makePlan()
        _ = try await journal.accept(plan)
        _ = try await journal.verifyComplete(transactionID: plan.transactionID, namespace: namespace,
            installationOwnerID: owner, expectedRevision: 0, current: plan.raw.after, files: ["source": plan.files[0].after])
        let complete = await NFRestoreStartupGate.inspect(applicationSupportURL: support)
        XCTAssertTrue(complete.permitsModelContainerOpen)
        let payload = root.appendingPathComponent(plan.transactionID.uuidString.lowercased()).appendingPathComponent("plan.json")
        let original = try Data(contentsOf: payload)
        try Data("CORRUPTED-RECOVERY-BYTES".utf8).write(to: payload)
        let corrupted = await NFRestoreStartupGate.inspect(applicationSupportURL: support)
        XCTAssertEqual(corrupted, .blocked(.init(reason: .unverified)))
        XCTAssertEqual(try Data(contentsOf: payload), Data("CORRUPTED-RECOVERY-BYTES".utf8))
        try original.write(to: payload)
        _ = try await journal.invalidate(transactionID: plan.transactionID, namespace: namespace,
            installationOwnerID: owner, expectedRevision: 1)
        let invalidated = await NFRestoreStartupGate.inspect(applicationSupportURL: support)
        XCTAssertEqual(invalidated, .blocked(.init(reason: .cleanupRequired)))
        try await journal.removeInvalidated(transactionID: plan.transactionID, namespace: namespace, installationOwnerID: owner)
        let cleaned = await NFRestoreStartupGate.inspect(applicationSupportURL: support)
        XCTAssertTrue(cleaned.permitsModelContainerOpen)
    }

    @MainActor
    func testWholeDeviceDeletionRemovesUnknownRestoreArtifactsWithoutTouchingOtherSupportFiles() async throws {
        let support = temporaryRoot(); defer { try? FileManager.default.removeItem(at: support) }
        let root = try NFRestoreJournalLocation.root(applicationSupportURL: support)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data("PRIVATE-FUTURE-RECOVERY-PAYLOAD".utf8).write(to: root.appendingPathComponent("unknown-future-format"))
        let unrelated = support.appendingPathComponent("unrelated.txt")
        try Data("preserve".utf8).write(to: unrelated)
        let blocked = await NFRestoreStartupGate.inspect(applicationSupportURL: support)
        XCTAssertFalse(blocked.permitsModelContainerOpen)
        try NFRestoreJournalLocation.purgeAllApplicationState(applicationSupportURL: support)
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.path))
        XCTAssertEqual(try Data(contentsOf: unrelated), Data("preserve".utf8))
        let cleared = await NFRestoreStartupGate.inspect(applicationSupportURL: support)
        XCTAssertTrue(cleared.permitsModelContainerOpen)
    }

    @MainActor
    private func makePlan() throws -> NFRestoreJournalPlan {
        let before = NFDataArchiveRawCapture.emptySnapshot()
        var after = before
        for model in ["ProgressAnnotationRecord", "InputCalibrationRecord"] {
            let index = try XCTUnwrap(after.tables.firstIndex { $0.model == model })
            var columns: [String: NFDataArchiveRawValue] = [:]
            for column in after.tables[index].columnManifest {
                switch column.type {
                case "UUID": columns[column.name] = owner.archiveRawValue
                case "Date": columns[column.name] = Date(timeIntervalSinceReferenceDate: 1_234_567.125).archiveRawValue
                case "String": columns[column.name] = "exact-frozen-\(column.name)".archiveRawValue
                case "Bool": columns[column.name] = false.archiveRawValue
                case "Double?": columns[column.name] = .null
                default: XCTFail("Missing fixture type \(column.type)")
                }
            }
            let row = NFDataArchiveRawRow(capturedPersistentID: nil, columns: columns)
            after.tables[index].rows = model == "ProgressAnnotationRecord" ? [row, row] : [row]
        }
        return NFRestoreJournalPlan(transactionID: UUID(), namespace: namespace, installationOwnerID: owner,
            sourceDigest: NFRestoreJournalCodec.digest(Data("original external file bytes".utf8)),
            permittedPayload: Data("canonical permitted prepared value".utf8), policy: .replaceAll,
            acceptedCounts: ["annotations": 2, "calibrations": 1], raw: try .init(before: before, after: after),
            files: [.init(id: "source", domain: .sourceFile, relativePath: "Documents/source.txt",
                before: Data("PROTECTED-KEY-AND-PRIVATE-SOURCE".utf8), after: Data())])
    }
    private func temporaryRoot() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("NFRestoreJournalTests-" + UUID().uuidString)
    }
}

@MainActor
final class NFRestorePlanCompilerAndDomainTests: XCTestCase {
    private let date = Date(timeIntervalSince1970: 1_780_000_000)
    private let owner = UUID(uuidString: "D34A7AE8-CBD0-462F-BC72-3D3D86D8DADA")!
    private enum Injected: Error { case stop }

    func testPermittedPayloadRehydrationUsesFrozenBytesAndRejectsFutureArchive() throws {
        let prepared = try preparedArchive()
        let bytes = try NFRestorePlanCompiler.permittedPayload(prepared: prepared)
        let restored = try NFRestorePlanCompiler.preparedFromPermittedPayload(bytes,
            sourceDigest: prepared.sourceDigest, sourceByteCount: prepared.sourceByteCount, sourceFilename: "same.json")
        XCTAssertEqual(try NFRestorePlanCompiler.permittedPayload(prepared: restored), bytes)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: bytes) as? [String: Any])
        object["archiveVersion"] = 999
        XCTAssertThrowsError(try NFRestorePlanCompiler.preparedFromPermittedPayload(JSONSerialization.data(withJSONObject: object),
            sourceDigest: prepared.sourceDigest, sourceByteCount: bytes.count, sourceFilename: "future.json"))
    }

    func testCompilePreservesExactRestartPayloadBytesInsteadOfReencodingSetsOrFormatting() throws {
        let prepared = try preparedArchive()
        let approved = try NFRestorePlanCompiler.permittedPayload(prepared: prepared)
        // Guaranteed byte difference without relying on Set iteration or encoder formatting.
        let frozenBytes = Data(" \n\t".utf8) + approved + Data("\n ".utf8)
        XCTAssertNotEqual(frozenBytes, approved)
        let rehydrated = try NFRestorePlanCompiler.preparedFromPermittedPayload(frozenBytes,
            sourceDigest: prepared.sourceDigest, sourceByteCount: prepared.sourceByteCount, sourceFilename: "approved.json")
        let destination = NFRestoreDestinationSnapshot(raw: NFDataArchiveRawCapture.emptySnapshot(), localLearningBytes: nil, adaptiveHistoryBytes: nil)
        let plan = try NFRestorePlanCompiler.compile(prepared: rehydrated, policy: .keepExisting,
            expectedReviewDigest: destination.reviewDigest, destination: destination,
            transactionID: UUID(), namespace: "synthetic-owner", ownerDeviceID: owner,
            compiledAt: date, locale: Locale(identifier: "en_US_POSIX"), frozenPermittedPayload: frozenBytes)
        XCTAssertEqual(plan.permittedPayload, frozenBytes)
        XCTAssertEqual(plan.permittedPayloadDigest, NFRestoreJournalCodec.digest(frozenBytes))
        XCTAssertThrowsError(try NFRestorePlanCompiler.compile(prepared: rehydrated, policy: .keepExisting,
            expectedReviewDigest: destination.reviewDigest, destination: destination,
            transactionID: UUID(), namespace: "synthetic-owner", ownerDeviceID: owner,
            compiledAt: date, locale: Locale(identifier: "en_US_POSIX"), frozenPermittedPayload: Data("malformed".utf8)))
    }

    func testFrozenOverrideRejectsMarkerOnlyEvaluatorPayloadInsteadOfKeepingItInPlan() throws {
        let prepared = try preparedArchive()
        let permitted = try NFRestorePlanCompiler.permittedPayload(prepared: prepared)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: permitted) as? [String: Any])
        let exercise = try NFFallbackExerciseGenerator.generate(.init(seed: 893, index: 0, lab: .mentalMath, purpose: .practice))
        var rawExercise = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(exercise)) as? [String: Any])
        var feedback = try XCTUnwrap(rawExercise["feedback"] as? [String: Any])
        feedback["hintLadder"] = ["PROTECTED-FROZEN-PAYLOAD-CANARY-5179"]
        rawExercise["feedback"] = feedback
        let attemptID = UUID()
        object["localLearning"] = ["schemaVersion": 1, "sessions": [],
            "snapshots": [["attemptID": attemptID.uuidString, "exercise": rawExercise]],
            "withheldProtectedConflictAttemptIDs": [attemptID.uuidString]]
        let unsafe = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        XCTAssertTrue(String(decoding: unsafe, as: UTF8.self).contains("PROTECTED-FROZEN-PAYLOAD-CANARY-5179"))
        let redacted = try NFRestorePlanCompiler.preparedFromPermittedPayload(unsafe,
            sourceDigest: prepared.sourceDigest, sourceByteCount: unsafe.count, sourceFilename: "marker.json")
        let destination = NFRestoreDestinationSnapshot(raw: NFDataArchiveRawCapture.emptySnapshot(), localLearningBytes: nil, adaptiveHistoryBytes: nil)
        XCTAssertThrowsError(try NFRestorePlanCompiler.compile(prepared: redacted, policy: .keepExisting,
            expectedReviewDigest: destination.reviewDigest, destination: destination,
            transactionID: UUID(), namespace: "synthetic-owner", ownerDeviceID: owner,
            compiledAt: date, locale: Locale(identifier: "en_US_POSIX"), frozenPermittedPayload: unsafe))
        XCTAssertEqual(try NFDataArchiveRawCapture.emptySnapshot().contentBytes(), try destination.raw.contentBytes())
    }

    func testReviewDigestPinsExactSideBytesAndAbsentIsDifferentFromEmpty() throws {
        let container = try memoryContainer()
        let context = ModelContext(container); context.autosaveEnabled = false
        let absent = try NFRestorePlanCompiler.captureDestination(context: context, localLearningBytes: nil, adaptiveHistoryBytes: nil)
        let empty = try NFRestorePlanCompiler.captureDestination(context: context, localLearningBytes: Data(), adaptiveHistoryBytes: nil)
        XCTAssertNotEqual(try absent.reviewDigest, try empty.reviewDigest)
        XCTAssertThrowsError(try compile(preparedArchive(), destination: empty, expected: absent.reviewDigest))
        XCTAssertTrue(try NFDataArchiveRawCapture.capture(context: context).tables.allSatisfy { $0.rows.isEmpty })
    }

    func testCompilerFreezesEachPolicyAndPreservesEveryUntouchedRawColumn() throws {
        let id = UUID(), unrelated = UUID()
        let container = try memoryContainer()
        let context = ModelContext(container); context.autosaveEnabled = false
        let original = ProgressAnnotationRecord(id: id, startDate: date, endDate: date, note: "Original e\u{301}\n", includeInExport: false)
        original.createdAt = date; original.modifiedAt = date
        let retained = ProgressAnnotationRecord(id: unrelated, startDate: date, endDate: date, note: "Unrelated", includeInExport: false)
        context.insert(original); context.insert(retained); try context.save()
        let before = try NFRestorePlanCompiler.captureDestination(context: context, localLearningBytes: nil, adaptiveHistoryBytes: nil)
        let prepared = try preparedArchive(annotationID: id, note: "Incoming")
        XCTAssertThrowsError(try compile(prepared, destination: before, policy: .abortOnConflict))
        let keep = try compile(prepared, destination: before, policy: .keepExisting)
        XCTAssertEqual(try keep.raw.before.contentBytes(), try keep.raw.after.contentBytes())
        XCTAssertEqual(try NFRestoreCompiledCounts(plan: keep).skipped["annotations"], 1)
        let matching = try compile(prepared, destination: before, policy: .replaceMatching)
        let priorTable = try XCTUnwrap(before.raw.tables.first { $0.model == "ProgressAnnotationRecord" })
        let result = try XCTUnwrap(matching.raw.after.tables.first { $0.model == "ProgressAnnotationRecord" })
        let priorUnrelated = try XCTUnwrap(priorTable.rows.first { $0.columns["id"] == unrelated.archiveRawValue })
        let nextUnrelated = try XCTUnwrap(result.rows.first { $0.columns["id"] == unrelated.archiveRawValue })
        XCTAssertEqual(try priorUnrelated.contentBytes(), try nextUnrelated.contentBytes())
        XCTAssertEqual(result.rows.count, 2)
        let all = try compile(prepared, destination: before, policy: .replaceAll)
        XCTAssertEqual(all.raw.after.tables.first { $0.model == "ProgressAnnotationRecord" }?.rows.count, 1)
        XCTAssertEqual(try NFDataArchiveRawCapture.capture(context: context).contentBytes(), try before.raw.contentBytes())
    }

    func testCompilerRejectsDuplicateDestinationAndNulIncomingBeforeMutation() throws {
        let container = try memoryContainer()
        let context = ModelContext(container); context.autosaveEnabled = false
        let id = UUID()
        for text in ["first", "second"] {
            context.insert(ProgressAnnotationRecord(id: id, startDate: date, endDate: date, note: text, includeInExport: true))
        }
        try context.save()
        let before = try NFRestorePlanCompiler.captureDestination(context: context, localLearningBytes: nil, adaptiveHistoryBytes: nil)
        XCTAssertThrowsError(try compile(preparedArchive(), destination: before))
        XCTAssertEqual(try NFDataArchiveRawCapture.capture(context: context).contentBytes(), try before.raw.contentBytes())
        let empty = NFRestoreDestinationSnapshot(raw: NFDataArchiveRawCapture.emptySnapshot(), localLearningBytes: nil, adaptiveHistoryBytes: nil)
        XCTAssertThrowsError(try compile(preparedArchive(annotationID: UUID(), note: "must\u{0}not truncate"), destination: empty)) { error in
            guard case NFDataArchiveRawSnapshotError.unrepresentableText = error else { return XCTFail("\(error)") }
        }
    }

    func testLocalContentPoliciesPreserveConsumptionAndTombstonesWithoutImportingWriterAuthority() throws {
        var oldMetadata = NFPrivateStudyMetadata(); oldMetadata.favoriteActivities = ["original"]
        var newMetadata = NFPrivateStudyMetadata(); newMetadata.favoriteActivities = ["incoming"]
        func run(_ metadata: NFPrivateStudyMetadata) throws -> NFLocalPrivateStudyRun {
            .init(id: NFPrivateStudyMetadata.recordID, generationID: NFPrivateStudyMetadata.recordID,
                payload: try JSONEncoder().encode(metadata), updatedAt: date)
        }
        var old = NFLocalSessionRepository.Archive()
        old.privateStudyRuns = [try run(oldMetadata)]
        let tombstone = UUID(); old.deletedAdaptiveRunIDs = [tombstone]
        old.deletedFixedLaunchCommandIDs = [UUID().uuidString]
        var ledger = NFSelectionReservationLedger()
        ledger.scopes["synthetic-scope"] = .init(catalogFingerprint: "fixture", authorityID: "fixture", legacyConsumption: nil,
            consumedPositions: [.init(epoch: 0, ordinal: 3)], retainedPlanPositions: [])
        old.selectionLedger = ledger
        var incoming = NFLocalSessionRepository.Archive(); incoming.privateStudyRuns = [try run(newMetadata)]
        let beforeBytes = try JSONEncoder().encode(old)
        let before = NFRestoreDestinationSnapshot(raw: NFDataArchiveRawCapture.emptySnapshot(), localLearningBytes: beforeBytes, adaptiveHistoryBytes: nil)
        for policy in [NFDataArchiveRestorePolicy.keepExisting, .replaceMatching, .replaceAll] {
            let plan = try compile(preparedArchive(local: incoming), destination: before, policy: policy)
            let bytes = try XCTUnwrap(plan.files.first { $0.domain == .localLearning }?.after)
            let result = try JSONDecoder().decode(NFLocalSessionRepository.Archive.self, from: bytes)
            let payload = try XCTUnwrap(result.privateStudyRuns?.first?.payload)
            let metadata = try JSONDecoder().decode(NFPrivateStudyMetadata.self, from: payload)
            XCTAssertEqual(metadata.favoriteActivities, policy == .keepExisting ? ["original"] : ["incoming"])
            XCTAssertEqual(result.selectionLedger?.scopes, old.selectionLedger?.scopes)
            XCTAssertEqual(result.deletedAdaptiveRunIDs, [tombstone])
            XCTAssertEqual(result.deletedFixedLaunchCommandIDs, old.deletedFixedLaunchCommandIDs)
            XCTAssertEqual(plan.files.first { $0.domain == .localLearning }?.before, beforeBytes)
        }
        let cleared = try compile(preparedArchive(), destination: before, policy: .replaceAll)
        let after = try JSONDecoder().decode(NFLocalSessionRepository.Archive.self,
            from: XCTUnwrap(cleared.files.first { $0.domain == .localLearning }?.after))
        XCTAssertTrue(after.privateStudyRuns?.isEmpty ?? true)
        XCTAssertEqual(after.selectionLedger?.scopes, old.selectionLedger?.scopes)
    }

    func testUnknownSideSchemasRefuseWithoutDiscardingOriginalBytes() throws {
        let future = Data("{\"schemaVersion\":999,\"sessions\":[],\"snapshots\":[],\"future\":\"original\"}".utf8)
        let before = NFRestoreDestinationSnapshot(raw: NFDataArchiveRawCapture.emptySnapshot(), localLearningBytes: future, adaptiveHistoryBytes: nil)
        XCTAssertThrowsError(try compile(preparedArchive(), destination: before))
        XCTAssertEqual(before.localLearningBytes, future)
        let futureHistory = Data("{\"version\":999,\"records\":[]}".utf8)
        let history = NFRestoreDestinationSnapshot(raw: before.raw, localLearningBytes: nil, adaptiveHistoryBytes: futureHistory)
        XCTAssertThrowsError(try compile(preparedArchive(), destination: history))
        XCTAssertEqual(history.adaptiveHistoryBytes, futureHistory)
    }

    func testPersistentDomainsResumeAfterSaveSucceededThenCallbackFailedWithoutDuplicateRows() throws {
        let root = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let plan: NFRestoreJournalPlan
        do {
            let container = try diskContainer(root)
            let context = ModelContext(container); context.autosaveEnabled = false
            let before = try NFRestorePlanCompiler.captureDestination(context: context, localLearningBytes: nil, adaptiveHistoryBytes: nil)
            plan = try compile(preparedArchive(annotationID: UUID(), documentID: UUID()), destination: before)
            XCTAssertThrowsError(try NFRestoreDomainApplier.applyDatabaseDomain(plan: plan, domain: .durable, container: container) { context in
                try context.save(); throw Injected.stop
            })
            let current = try NFDataArchiveRawCapture.capture(context: ModelContext(container))
            XCTAssertEqual(try NFRestoreDomainApplier.domainDisposition(plan: plan, domain: .durable, current: current), .alreadyApplied)
            XCTAssertEqual(try NFRestoreDomainApplier.domainDisposition(plan: plan, domain: .localOnly, current: current), .needsApplication)
        }
        do {
            let reopened = try diskContainer(root)
            XCTAssertEqual(try NFRestoreDomainApplier.applyDatabaseDomain(plan: plan, domain: .durable, container: reopened), .alreadyApplied)
            XCTAssertEqual(try NFRestoreDomainApplier.applyDatabaseDomain(plan: plan, domain: .localOnly, container: reopened), .needsApplication)
            XCTAssertEqual(try NFRestoreDomainApplier.applyDatabaseDomain(plan: plan, domain: .localOnly, container: reopened), .alreadyApplied)
            let current = try NFDataArchiveRawCapture.capture(context: ModelContext(reopened))
            XCTAssertEqual(try current.contentBytes(), try plan.raw.after.contentBytes())
            XCTAssertEqual(try ModelContext(reopened).fetch(FetchDescriptor<ProgressAnnotationRecord>()).count, 1)
            XCTAssertEqual(try ModelContext(reopened).fetch(FetchDescriptor<SourceDocumentRecord>()).count, 1)
            XCTAssertEqual(try ModelContext(reopened).fetch(FetchDescriptor<SourceDocumentRecord>()).first?.localPath, "")
        }
    }

    func testBeforeSaveFailureRollsBackOnlyUnsavedContextAndThirdStatePreservesArrivals() throws {
        let container = try memoryContainer()
        let context = ModelContext(container); context.autosaveEnabled = false
        let before = try NFRestorePlanCompiler.captureDestination(context: context, localLearningBytes: nil, adaptiveHistoryBytes: nil)
        let plan = try compile(preparedArchive(annotationID: UUID(), documentID: UUID()), destination: before)
        XCTAssertThrowsError(try NFRestoreDomainApplier.applyDatabaseDomain(plan: plan, domain: .durable, container: container) { _ in throw Injected.stop })
        XCTAssertEqual(try NFDataArchiveRawCapture.capture(context: ModelContext(container)).contentBytes(), try before.raw.contentBytes())
        let peer = SourceDocumentRecord(filename: "Arrived later", typeIdentifier: "public.text", sizeBytes: 1, localPath: "/kept")
        context.insert(peer); try context.save()
        let third = try NFDataArchiveRawCapture.capture(context: ModelContext(container))
        XCTAssertThrowsError(try NFRestoreDomainApplier.applyDatabaseDomain(plan: plan, domain: .durable, container: container))
        XCTAssertEqual(try NFDataArchiveRawCapture.capture(context: ModelContext(container)).contentBytes(), try third.contentBytes())
        XCTAssertEqual(try context.fetch(FetchDescriptor<SourceDocumentRecord>()).first?.id, peer.id)
    }

    func testFileFaultsReconcileBeforeAndAfterAndNeverInstallPredecessor() async throws {
        for boundary in [NFRestoreFileApplier.Boundary.beforeTemporaryWrite, .afterTemporaryWrite, .beforePublish, .afterPublish, .afterReadback] {
            let root = try temporaryRoot()
            defer { try? FileManager.default.removeItem(at: root) }
            let lease = try NFApplicationStoreLease(applicationSupportURL: root)
            let initial = Data("before-private".utf8), after = Data("after-private".utf8)
            let url = root.appendingPathComponent("sessions-v1.json")
            try initial.write(to: url)
            let operation = NFRestoreJournalFileOperation(id: "local-learning", domain: .localLearning, relativePath: "sessions-v1.json", before: initial, after: after)
            let transaction = UUID()
            let failing = NFRestoreFileApplier(roots: [.localLearning: root], lease: lease, fault: { if $0 == boundary { throw Injected.stop } })
            do { _ = try await failing.apply(operation, transactionID: transaction); XCTFail("Expected boundary") }
            catch Injected.stop { }
            let actual = try Data(contentsOf: url)
            XCTAssertTrue(actual == initial || actual == after)
            let fresh = NFRestoreFileApplier(roots: [.localLearning: root], lease: lease)
            _ = try await fresh.apply(operation, transactionID: transaction)
            XCTAssertEqual(try Data(contentsOf: url), after)
            let replay = try await fresh.apply(operation, transactionID: transaction)
            XCTAssertEqual(replay, .alreadyApplied)
            XCTAssertEqual(try Data(contentsOf: url), after)
        }
    }

    func testFileThirdStateAndSpecialFilesAreNotReplaced() async throws {
        let root = try temporaryRoot(); defer { try? FileManager.default.removeItem(at: root) }
        let lease = try NFApplicationStoreLease(applicationSupportURL: root)
        let url = root.appendingPathComponent("sessions-v1.json")
        let operation = NFRestoreJournalFileOperation(id: "local-learning", domain: .localLearning, relativePath: "sessions-v1.json",
            before: Data("before".utf8), after: Data("after".utf8))
        let applier = NFRestoreFileApplier(roots: [.localLearning: root], lease: lease)
        try Data("third".utf8).write(to: url)
        do { _ = try await applier.apply(operation, transactionID: UUID()); XCTFail("Expected conflict") }
        catch NFRestoreJournalError.recoveryConflict { }
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), "third")
        try FileManager.default.removeItem(at: url)
        XCTAssertEqual(mkfifo(url.path, 0o600), 0)
        do { _ = try await applier.apply(operation, transactionID: UUID()); XCTFail("Expected special-file refusal") }
        catch NFRestoreJournalError.unsafePath { }
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
    }

    func testAcceptedJournalCompletesOnlyAfterBothDomainsAndEveryExactFile() async throws {
        let root = try temporaryRoot(); defer { try? FileManager.default.removeItem(at: root) }
        let lease = try NFApplicationStoreLease(applicationSupportURL: root)
        let fileWriter = NFRestoreFileApplier(roots: [.localLearning: root, .adaptiveHistory: root], lease: lease)
        let journal = NFDataArchiveRestoreJournal(root: root.appending(path: "Journal"))
        let container = try diskContainer(root)
        let context = ModelContext(container); context.autosaveEnabled = false
        var metadata = NFPrivateStudyMetadata(); metadata.favoriteActivities = ["accepted"]
        var local = NFLocalSessionRepository.Archive()
        local.privateStudyRuns = [.init(id: NFPrivateStudyMetadata.recordID, generationID: NFPrivateStudyMetadata.recordID,
            payload: try JSONEncoder().encode(metadata), updatedAt: date)]
        let before = try NFRestorePlanCompiler.captureDestination(context: context, localLearningBytes: nil, adaptiveHistoryBytes: nil)
        let plan = try compile(preparedArchive(annotationID: UUID(), documentID: UUID(), local: local), destination: before)
        let accepted = try await journal.accept(plan)
        let phase = try await journal.mark(transactionID: plan.transactionID, namespace: plan.namespace,
            installationOwnerID: owner, expectedRevision: accepted.progress.revision, phase: .mutationMayHaveStarted)
        _ = try NFRestoreDomainApplier.applyDatabaseDomain(plan: plan, domain: .durable, container: container)
        let partialFiles = try await fileWriter.captureFiles()
        let partial = try NFRestoreJournalCodec.reconcile(accepted,
            current: NFDataArchiveRawCapture.capture(context: ModelContext(container)), files: partialFiles)
        XCTAssertFalse(partial.isComplete)
        XCTAssertFalse(partial.hasConflict)
        _ = try NFRestoreDomainApplier.applyDatabaseDomain(plan: plan, domain: .localOnly, container: container)
        for operation in plan.files { _ = try await fileWriter.apply(operation, transactionID: plan.transactionID) }
        let files = try await fileWriter.captureFiles()
        let actual = try NFDataArchiveRawCapture.capture(context: ModelContext(container))
        let completed = try await journal.verifyComplete(transactionID: plan.transactionID, namespace: plan.namespace,
            installationOwnerID: owner, expectedRevision: phase.revision, current: actual, files: files)
        XCTAssertEqual(completed.phase, .verifiedComplete)
        XCTAssertEqual(completed.completion?.acceptedCounts, plan.acceptedCounts)
        let loaded = try await journal.load(transactionID: plan.transactionID, namespace: plan.namespace, installationOwnerID: owner)
        XCTAssertTrue(try NFRestoreJournalCodec.reconcile(loaded, current: actual, files: files).isComplete)
        let repeated = try await journal.verifyComplete(transactionID: plan.transactionID, namespace: plan.namespace,
            installationOwnerID: owner, expectedRevision: phase.revision, current: actual, files: files)
        XCTAssertEqual(repeated, completed)
    }

    func testRetainedLocalCrossReferencesBlockDestructivePlanBeforeAcceptance() throws {
        let missing = UUID()
        var metadata = NFPrivateStudyMetadata()
        metadata.annotations = [NFStudyAnnotation(id: missing)]
        var local = NFLocalSessionRepository.Archive()
        local.privateStudyRuns = [.init(id: NFPrivateStudyMetadata.recordID, generationID: NFPrivateStudyMetadata.recordID,
            payload: try JSONEncoder().encode(metadata), updatedAt: date)]
        let bytes = try JSONEncoder().encode(local)
        let before = NFRestoreDestinationSnapshot(raw: NFDataArchiveRawCapture.emptySnapshot(), localLearningBytes: bytes, adaptiveHistoryBytes: nil)
        XCTAssertThrowsError(try compile(preparedArchive(), destination: before, policy: .keepExisting))
        XCTAssertEqual(before.localLearningBytes, bytes)
        // An explicitly selected Replace All removes the known local content
        // collection while the exact predecessor remains in the plan.
        let replacement = try compile(preparedArchive(), destination: before, policy: .replaceAll)
        XCTAssertEqual(replacement.files.first { $0.domain == .localLearning }?.before, bytes)
    }

    func testColdPreviewIncludesLocalIdentityConflictsWithoutConstructingAppStore() throws {
        var metadata = NFPrivateStudyMetadata(); metadata.favoriteActivities = ["retained"]
        var local = NFLocalSessionRepository.Archive()
        local.privateStudyRuns = [.init(id: NFPrivateStudyMetadata.recordID, generationID: NFPrivateStudyMetadata.recordID,
            payload: try JSONEncoder().encode(metadata), updatedAt: date)]
        let before = NFRestoreDestinationSnapshot(raw: NFDataArchiveRawCapture.emptySnapshot(),
            localLearningBytes: try JSONEncoder().encode(local), adaptiveHistoryBytes: nil)
        let preview = try NFRestorePlanCompiler.preview(prepared: preparedArchive(annotationID: UUID(), local: local),
            destination: before, locale: Locale(identifier: "en_US_POSIX"))
        XCTAssertEqual(preview.incoming[.annotations], 1)
        XCTAssertEqual(preview.localIncoming["privateStudyRuns"], 1)
        XCTAssertEqual(preview.localConflicts["privateStudyRuns"], 1)
        XCTAssertTrue(preview.hasConflicts)
        XCTAssertEqual(try JSONDecoder().decode(NFLocalSessionRepository.Archive.self,
            from: XCTUnwrap(before.localLearningBytes)).privateStudyRuns?.first?.payload, local.privateStudyRuns?.first?.payload)
    }

    func testUnacceptedCandidateIsExactAndNeverConfusedWithAcceptedAuthority() async throws {
        let root = try temporaryRoot(); defer { try? FileManager.default.removeItem(at: root) }
        let before = NFRestoreDestinationSnapshot(raw: NFDataArchiveRawCapture.emptySnapshot(), localLearningBytes: nil, adaptiveHistoryBytes: nil)
        let plan = try compile(preparedArchive(annotationID: UUID()), destination: before)
        let failing = NFDataArchiveRestoreJournal(root: root, fault: { if $0 == .afterPlanWrite { throw Injected.stop } })
        do { _ = try await failing.accept(plan); XCTFail("Expected preservation boundary") } catch Injected.stop { }
        let fresh = NFDataArchiveRestoreJournal(root: root)
        let candidate = try await fresh.loadUnacceptedCandidate(transactionID: plan.transactionID,
            namespace: plan.namespace, installationOwnerID: owner)
        let recovered = try XCTUnwrap(candidate)
        XCTAssertEqual(try NFRestoreJournalCodec.encode(recovered, maximumBytes: 64 * 1_024 * 1_024),
                       try NFRestoreJournalCodec.encode(plan, maximumBytes: 64 * 1_024 * 1_024))
        let entries = try await fresh.inspectAllNamespaces()
        XCTAssertTrue(try XCTUnwrap(entries.first).isStaging)
        do { _ = try await fresh.loadUnacceptedCandidate(transactionID: plan.transactionID,
            namespace: "foreign", installationOwnerID: owner); XCTFail("Expected owner refusal") }
        catch NFRestoreJournalError.wrongOwner { }
        // Simulate the coordinator's request and fresh-predecessor check.
        XCTAssertEqual(recovered.sourceDigest, plan.sourceDigest)
        XCTAssertEqual(recovered.permittedPayload, plan.permittedPayload)
        XCTAssertEqual(try recovered.raw.before.contentBytes(), try before.raw.contentBytes())
        _ = try await fresh.accept(recovered)
        do { _ = try await fresh.loadUnacceptedCandidate(transactionID: plan.transactionID,
            namespace: plan.namespace, installationOwnerID: owner); XCTFail("Accepted directory is not an unaccepted candidate") }
        catch NFRestoreJournalError.conflictingPlan { }
    }

    func testCorruptUnacceptedPlanAndUnknownCountVersionStayRetainedAndBlocked() async throws {
        let root = try temporaryRoot(); defer { try? FileManager.default.removeItem(at: root) }
        let before = NFRestoreDestinationSnapshot(raw: NFDataArchiveRawCapture.emptySnapshot(), localLearningBytes: nil, adaptiveHistoryBytes: nil)
        let plan = try compile(preparedArchive(), destination: before)
        let failing = NFDataArchiveRestoreJournal(root: root, fault: { if $0 == .afterPlanWrite { throw Injected.stop } })
        do { _ = try await failing.accept(plan); XCTFail("Expected boundary") } catch Injected.stop { }
        let path = root.appending(path: ".staging-\(plan.transactionID.uuidString.lowercased())/plan.json")
        let malformed = Data("{not a recoverable plan}".utf8)
        try malformed.write(to: path)
        let fresh = NFDataArchiveRestoreJournal(root: root)
        do { _ = try await fresh.loadUnacceptedCandidate(transactionID: plan.transactionID,
            namespace: plan.namespace, installationOwnerID: owner); XCTFail("Expected refusal") } catch { }
        XCTAssertEqual(try Data(contentsOf: path), malformed)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: NFRestoreJournalCodec.encode(plan, maximumBytes: 64 * 1_024 * 1_024)) as? [String: Any])
        object["resultCountsVersion"] = 999
        let future = try JSONDecoder().decode(NFRestoreJournalPlan.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertThrowsError(try NFRestoreJournalCodec.validate(future))
        let legacy = NFRestoreJournalPlan(transactionID: UUID(), namespace: plan.namespace, installationOwnerID: owner,
            sourceDigest: plan.sourceDigest, permittedPayload: plan.permittedPayload, policy: .keepExisting,
            acceptedCounts: ["attempts": 2], raw: plan.raw)
        try NFRestoreJournalCodec.validate(legacy)
        let legacyObject = try XCTUnwrap(JSONSerialization.jsonObject(with: NFRestoreJournalCodec.encode(legacy, maximumBytes: 64 * 1_024 * 1_024)) as? [String: Any])
        XCTAssertNil(legacyObject["resultCountsVersion"])
        XCTAssertEqual(try NFRestoreCompiledCounts(plan: legacy).restored["attempts"], 2)
    }

    private func compile(_ prepared: NFPreparedDataArchive, destination: NFRestoreDestinationSnapshot,
        policy: NFDataArchiveRestorePolicy = .replaceMatching, expected: String? = nil) throws -> NFRestoreJournalPlan {
        try NFRestorePlanCompiler.compile(prepared: prepared, policy: policy,
            expectedReviewDigest: expected ?? destination.reviewDigest, destination: destination,
            transactionID: UUID(), namespace: "synthetic-owner", ownerDeviceID: owner,
            compiledAt: date, locale: Locale(identifier: "en_US_POSIX"))
    }

    private func preparedArchive(annotationID: UUID? = nil, note: String = "Accepted annotation", documentID: UUID? = nil,
        local: NFLocalSessionRepository.Archive? = nil) throws -> NFPreparedDataArchive {
        let annotations: [NFDataExportService.ProgressAnnotation] = annotationID.map { [
            .init(id: $0, startDate: date, endDate: date, note: note, createdAt: date, modifiedAt: date)
        ] } ?? []
        let documents: [NFDataExportService.Document] = documentID.map { [
            .init(id: $0, filename: "Accepted source.txt", typeIdentifier: "public.text", sizeBytes: 4, importedAt: date,
                indexState: "ready", aiPolicy: DocumentAIPolicy.onDeviceOnly.rawValue, syncPolicy: "localOnly",
                pccExcerptConsentPolicyVersion: 0, pccExcerptConsentDocumentID: "", pccExcerptConsentedAt: nil,
                characterCount: 0, chunkCount: 0, extractionVersion: 0, csvSelectedColumnIDs: [], indexError: nil)
        ] } ?? []
        let archive = NFDataExportService.Archive(archiveVersion: NFDataExportService.archiveVersion, exportedAt: date,
            appVersion: "synthetic", profile: nil, attempts: [], attemptReflections: [], documents: documents,
            sourceChunks: [], aiGenerations: [], sessionCheckpoints: [], dailyPlans: [], inputCalibrations: [],
            progressAnnotations: annotations, excludedPrivateAnnotationCount: 0, weeklyTransferState: nil,
            reassessmentState: nil, adaptivePlanHistory: [], quarantinedReports: [], localLearning: local)
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601; encoder.outputFormatting = [.sortedKeys]
        let bytes = try encoder.encode(archive)
        return try NFRestorePlanCompiler.preparedFromPermittedPayload(bytes,
            sourceDigest: NFRestoreJournalCodec.digest(bytes), sourceByteCount: bytes.count, sourceFilename: "accepted.json")
    }

    private func memoryContainer() throws -> ModelContainer {
        let schema = Schema(NFSchemaV1.models)
        return try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema,
            isStoredInMemoryOnly: true, cloudKitDatabase: .none)])
    }
    private func diskContainer(_ folder: URL) throws -> ModelContainer {
        try ModelContainer(for: Schema(NFSchemaV1.models), configurations: [
            ModelConfiguration("CompilerDurable", schema: Schema(NFPersistentStoreLocation.durableModels), url: folder.appending(path: "Durable.store"), cloudKitDatabase: .none),
            ModelConfiguration("CompilerLocal", schema: Schema(NFPersistentStoreLocation.localOnlyModels), url: folder.appending(path: "Local.store"), cloudKitDatabase: .none)
        ])
    }
    private func temporaryRoot() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: "NF-Restore-Domain-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        return url
    }
}

extension NFRestorePlanCompilerAndDomainTests {
    func testColdCoordinatorAppliesBothPersistentStoresAndCreatesMissingSideRoots() async throws {
        let root = try temporaryRoot(); defer { try? FileManager.default.removeItem(at: root) }
        let lease = try NFApplicationStoreLease(applicationSupportURL: root)
        let annotationID = UUID(), documentID = UUID()
        var metadata = NFPrivateStudyMetadata(); metadata.favoriteActivities = ["cold accepted"]
        var local = NFLocalSessionRepository.Archive()
        local.privateStudyRuns = [.init(id: NFPrivateStudyMetadata.recordID, generationID: NFPrivateStudyMetadata.recordID,
            payload: try JSONEncoder().encode(metadata), updatedAt: date)]
        let prepared = try preparedArchive(annotationID: annotationID, documentID: documentID, local: local)
        let before = try coldDestination(root)
        let request = try coldRequest(prepared, destination: before, root: root)
        let requests = NFRestoreRequestStore(root: NFRestoreRequestStore.root(applicationSupportURL: root), lease: lease)
        try await requests.stage(request)
        let sideRoots = NFRestoreColdCoordinator.sideFileRoots(applicationSupportURL: root, namespace: request.namespace)
        XCTAssertFalse(FileManager.default.fileExists(atPath: try XCTUnwrap(sideRoots[.localLearning]).path))
        var opened = 0
        var outcome: NFRestoreColdCoordinator.Outcome? = try await NFRestoreColdCoordinator.recover(
            selection: coldSelection(root), applicationSupportURL: root, lease: lease,
            installationOwnerID: owner, hasOpenedRuntime: false, isCurrentLaunch: { true },
            makeContainer: { opened += 1; return try self.diskContainer(root) })
        XCTAssertEqual(opened, 1)
        XCTAssertNotNil(outcome?.container)
        let receipt = try XCTUnwrap(outcome?.completion)
        XCTAssertEqual(receipt.resolution, .completed)
        XCTAssertEqual(receipt.counts["restored.annotations"], 1)
        XCTAssertEqual(receipt.counts["restored.documents"], 1)
        let journal = NFDataArchiveRestoreJournal(root: try NFRestoreJournalLocation.root(applicationSupportURL: root))
        let accepted = try await journal.load(transactionID: request.transactionID, namespace: request.namespace, installationOwnerID: owner)
        XCTAssertEqual(accepted.progress.phase, .verifiedComplete)
        XCTAssertEqual(accepted.plan.permittedPayload, request.permittedPayload)
        outcome = nil
        // Reopen genuine SQLite files; no AppStore initializer has run on the destination.
        let reopened = try diskContainer(root)
        let context = ModelContext(reopened); context.autosaveEnabled = false
        XCTAssertEqual(try context.fetch(FetchDescriptor<ProgressAnnotationRecord>()).map(\.id), [annotationID])
        let document = try XCTUnwrap(context.fetch(FetchDescriptor<SourceDocumentRecord>()).first)
        XCTAssertEqual(document.id, documentID)
        XCTAssertEqual(document.localPath, "", "Portable metadata must not invent an available original file")
        XCTAssertEqual(try NFDataArchiveRawCapture.capture(context: context).contentBytes(), try accepted.plan.raw.after.contentBytes())
        for filename in ["Durable.store", "Local.store"] {
            XCTAssertEqual(try Data(contentsOf: root.appending(path: filename)).prefix(16), Data("SQLite format 3\0".utf8))
        }
        let files = try await NFRestoreFileApplier(roots: sideRoots, lease: lease).captureFiles()
        for operation in accepted.plan.files { XCTAssertEqual(files[operation.id]!, operation.after) }
        let retained = try await requests.inspectAll()
        XCTAssertEqual(retained.first?.receipt, receipt)
        XCTAssertEqual(retained.first?.cleanupRequired, false)
        XCTAssertEqual(retained.first?.completionAcknowledged, false)
    }

    func testColdCoordinatorResumesRecoveryRequiredAfterDurableSaveWithoutPhaseRewind() async throws {
        let root = try temporaryRoot(); defer { try? FileManager.default.removeItem(at: root) }
        let lease = try NFApplicationStoreLease(applicationSupportURL: root)
        let annotationID = UUID(), documentID = UUID()
        let before = try coldDestination(root)
        let request = try coldRequest(preparedArchive(annotationID: annotationID, documentID: documentID), destination: before, root: root)
        let requests = NFRestoreRequestStore(root: NFRestoreRequestStore.root(applicationSupportURL: root), lease: lease)
        try await requests.stage(request)
        let journal = NFDataArchiveRestoreJournal(root: try NFRestoreJournalLocation.root(applicationSupportURL: root))
        let plan = try coldPlan(request, destination: before)
        let accepted = try await journal.accept(plan)
        let started = try await journal.mark(transactionID: request.transactionID, namespace: request.namespace,
            installationOwnerID: owner, expectedRevision: accepted.progress.revision, phase: .mutationMayHaveStarted)
        try autoreleasepool {
            let container = try diskContainer(root)
            _ = try NFRestoreDomainApplier.applyDatabaseDomain(plan: plan, domain: .durable, container: container)
            let context = ModelContext(container); context.autosaveEnabled = false
            XCTAssertEqual(try context.fetchCount(FetchDescriptor<ProgressAnnotationRecord>()), 1)
            XCTAssertEqual(try context.fetchCount(FetchDescriptor<SourceDocumentRecord>()), 0)
        }
        let recovery = try await journal.mark(transactionID: request.transactionID, namespace: request.namespace,
            installationOwnerID: owner, expectedRevision: started.revision, phase: .recoveryRequired)
        let frozenPlanBytes = try NFRestoreJournalCodec.encode(plan, maximumBytes: 64 * 1_024 * 1_024)
        var opened = 0
        let outcome = try await NFRestoreColdCoordinator.recover(selection: coldSelection(root), applicationSupportURL: root,
            lease: lease, installationOwnerID: owner, hasOpenedRuntime: false, isCurrentLaunch: { true },
            makeContainer: { opened += 1; return try self.diskContainer(root) })
        XCTAssertEqual(opened, 1)
        XCTAssertNotNil(outcome.completion)
        let completed = try await journal.load(transactionID: request.transactionID, namespace: request.namespace, installationOwnerID: owner)
        XCTAssertEqual(completed.progress.phase, .verifiedComplete)
        XCTAssertEqual(completed.progress.revision, recovery.revision + 1, "Recovery must complete directly without rewinding its phase")
        XCTAssertEqual(try NFRestoreJournalCodec.encode(completed.plan, maximumBytes: 64 * 1_024 * 1_024), frozenPlanBytes)
        let context = ModelContext(try XCTUnwrap(outcome.container)); context.autosaveEnabled = false
        XCTAssertEqual(try context.fetch(FetchDescriptor<ProgressAnnotationRecord>()).map(\.id), [annotationID])
        XCTAssertEqual(try context.fetch(FetchDescriptor<SourceDocumentRecord>()).map(\.id), [documentID])
        XCTAssertEqual(try NFDataArchiveRawCapture.capture(context: context).contentBytes(), try plan.raw.after.contentBytes())
    }

    func testColdCoordinatorReviewDriftRetainsRawAndSideArrivalsWithoutAcceptingAPlan() async throws {
        for sideFileDrift in [false, true] {
            let root = try temporaryRoot(); defer { try? FileManager.default.removeItem(at: root) }
            let lease = try NFApplicationStoreLease(applicationSupportURL: root)
            let before = try coldDestination(root)
            let request = try coldRequest(preparedArchive(annotationID: UUID()), destination: before, root: root)
            let requests = NFRestoreRequestStore(root: NFRestoreRequestStore.root(applicationSupportURL: root), lease: lease)
            try await requests.stage(request)
            let roots = try NFRestoreColdCoordinator.prepareSideFileRoots(applicationSupportURL: root, namespace: request.namespace)
            if sideFileDrift {
                try JSONEncoder().encode(NFLocalSessionRepository.Archive()).write(
                    to: try XCTUnwrap(roots[.localLearning]).appending(path: NFRestorePlanCompiler.localLearningFilename))
            } else {
                try autoreleasepool {
                    let container = try diskContainer(root)
                    let context = ModelContext(container); context.autosaveEnabled = false
                    context.insert(ProgressAnnotationRecord(id: UUID(), startDate: date, endDate: date,
                        note: "Legitimate arrival after review", includeInExport: false))
                    try context.save()
                }
            }
            let filesBefore = try await NFRestoreFileApplier(roots: roots, lease: lease).captureFiles()
            let rawBefore = try coldDestination(root).raw.contentBytes()
            do {
                _ = try await NFRestoreColdCoordinator.recover(selection: coldSelection(root), applicationSupportURL: root,
                    lease: lease, installationOwnerID: owner, hasOpenedRuntime: false, isCurrentLaunch: { true },
                    makeContainer: { try self.diskContainer(root) })
                XCTFail("Changed reviewed input requires a new preview before plan acceptance")
            } catch NFRestoreColdCoordinator.Failure.renewedReviewRequired { }
            XCTAssertEqual(try coldDestination(root).raw.contentBytes(), rawBefore)
            let filesAfter = try await NFRestoreFileApplier(roots: roots, lease: lease).captureFiles()
            XCTAssertEqual(filesAfter, filesBefore)
            let retained = try await requests.load(transactionID: request.transactionID, namespace: request.namespace, owner: owner)
            XCTAssertEqual(retained, request)
            let journal = NFDataArchiveRestoreJournal(root: try NFRestoreJournalLocation.root(applicationSupportURL: root))
            let entries = try await journal.inspectAllNamespaces()
            XCTAssertTrue(entries.isEmpty)
        }
    }

    func testColdCoordinatorRejectsForeignOwnerAndLiveOrStaleLaunchBeforeContainerCreation() async throws {
        let root = try temporaryRoot(); defer { try? FileManager.default.removeItem(at: root) }
        let lease = try NFApplicationStoreLease(applicationSupportURL: root)
        let request = try coldRequest(preparedArchive(annotationID: UUID()), destination: coldDestination(root), root: root)
        let requests = NFRestoreRequestStore(root: NFRestoreRequestStore.root(applicationSupportURL: root), lease: lease)
        try await requests.stage(request)
        var opened = 0
        for (suppliedOwner, alreadyOpened, current) in [(UUID?.some(UUID()), false, true), (nil, false, true),
            (UUID?.some(owner), true, true), (UUID?.some(owner), false, false)] {
            do {
                _ = try await NFRestoreColdCoordinator.recover(selection: coldSelection(root), applicationSupportURL: root,
                    lease: lease, installationOwnerID: suppliedOwner, hasOpenedRuntime: alreadyOpened, isCurrentLaunch: { current },
                    makeContainer: { opened += 1; return try self.diskContainer(root) })
                XCTFail("No destination may open through a foreign owner or an already active/stale launch")
            } catch NFRestoreColdCoordinator.Failure.ownershipUnavailable {
                XCTAssertFalse(alreadyOpened || !current)
            } catch NFRestoreColdCoordinator.Failure.fullRestartRequired {
                XCTAssertTrue(alreadyOpened || !current)
            }
        }
        XCTAssertEqual(opened, 0)
        XCTAssertEqual(try coldDestination(root).raw.tables.flatMap(\.rows).count, 0)
        let retained = try await requests.load(transactionID: request.transactionID, namespace: request.namespace, owner: owner)
        XCTAssertEqual(retained, request)
    }

    func testColdCoordinatorCompletesMissingRequestReceiptWithoutReplayingLaterDeletion() async throws {
        let root = try temporaryRoot(); defer { try? FileManager.default.removeItem(at: root) }
        let lease = try NFApplicationStoreLease(applicationSupportURL: root)
        let annotationID = UUID()
        let before = try coldDestination(root)
        let request = try coldRequest(preparedArchive(annotationID: annotationID, documentID: UUID()), destination: before, root: root)
        let requests = NFRestoreRequestStore(root: NFRestoreRequestStore.root(applicationSupportURL: root), lease: lease)
        try await requests.stage(request)
        let loaded = try await coldCompleteJournal(request, destination: before, root: root, lease: lease)
        XCTAssertEqual(loaded.progress.phase, .verifiedComplete)
        try coldDeleteAnnotation(annotationID, root: root)
        let laterBytes = try coldDestination(root).raw.contentBytes()
        var opened = 0
        let outcome = try await NFRestoreColdCoordinator.recover(selection: coldSelection(root), applicationSupportURL: root,
            lease: lease, installationOwnerID: owner, hasOpenedRuntime: false, isCurrentLaunch: { true },
            makeContainer: { opened += 1; return try self.diskContainer(root) })
        XCTAssertEqual(opened, 0)
        XCTAssertNil(outcome.container)
        let completion = try XCTUnwrap(outcome.completion)
        XCTAssertEqual(completion.acceptedPlanDigest, loaded.descriptor.planDigest)
        XCTAssertEqual(completion.counts, loaded.plan.acceptedCounts)
        XCTAssertEqual(try coldDestination(root).raw.contentBytes(), laterBytes)
        let entries = try await requests.inspectAll()
        XCTAssertEqual(entries.first?.receipt, completion)
        XCTAssertEqual(entries.first?.cleanupRequired, false)
    }

    func testColdCoordinatorFinishesReceiptCleanupAndShowsCompletionUntilDurableAcknowledgementWithoutReplay() async throws {
        let root = try temporaryRoot(); defer { try? FileManager.default.removeItem(at: root) }
        let lease = try NFApplicationStoreLease(applicationSupportURL: root)
        let annotationID = UUID()
        let before = try coldDestination(root)
        let request = try coldRequest(preparedArchive(annotationID: annotationID), destination: before, root: root)
        let requests = NFRestoreRequestStore(root: NFRestoreRequestStore.root(applicationSupportURL: root), lease: lease)
        try await requests.stage(request)
        let loaded = try await coldCompleteJournal(request, destination: before, root: root, lease: lease)
        let interrupted = NFRestoreRequestStore(root: NFRestoreRequestStore.root(applicationSupportURL: root), lease: lease,
            fault: { if $0 == .afterReceiptPublish { throw Injected.stop } })
        do {
            _ = try await interrupted.resolve(request, resolution: .completed,
                acceptedPlanDigest: loaded.descriptor.planDigest, counts: loaded.plan.acceptedCounts)
            XCTFail("Expected the durable-receipt/before-cleanup interruption")
        } catch Injected.stop { }
        let pending = try await requests.inspectAll()
        let receipt = try XCTUnwrap(pending.first?.receipt)
        XCTAssertEqual(pending.first?.cleanupRequired, true)
        XCTAssertEqual(pending.first?.completionAcknowledged, false)
        try coldDeleteAnnotation(annotationID, root: root)
        let laterBytes = try coldDestination(root).raw.contentBytes()
        var opened = 0
        for _ in 0..<2 {
            let outcome = try await NFRestoreColdCoordinator.recover(selection: coldSelection(root), applicationSupportURL: root,
                lease: lease, installationOwnerID: owner, hasOpenedRuntime: false, isCurrentLaunch: { true },
                makeContainer: { opened += 1; return try self.diskContainer(root) })
            XCTAssertNil(outcome.container)
            XCTAssertEqual(outcome.completion, receipt)
        }
        let cleaned = try await requests.inspectAll()
        XCTAssertEqual(cleaned.first?.cleanupRequired, false)
        try await requests.acknowledgeCompletion(receipt)
        try await requests.acknowledgeCompletion(receipt)
        let acknowledged = try await requests.inspectAll()
        XCTAssertEqual(acknowledged.first?.completionAcknowledged, true)
        let final = try await NFRestoreColdCoordinator.recover(selection: coldSelection(root), applicationSupportURL: root,
            lease: lease, installationOwnerID: owner, hasOpenedRuntime: false, isCurrentLaunch: { true },
            makeContainer: { opened += 1; return try self.diskContainer(root) })
        XCTAssertNil(final.completion)
        XCTAssertNil(final.container)
        XCTAssertEqual(opened, 0)
        XCTAssertEqual(try coldDestination(root).raw.contentBytes(), laterBytes)
        let retained = try await NFDataArchiveRestoreJournal(root: NFRestoreJournalLocation.root(applicationSupportURL: root))
            .load(transactionID: request.transactionID, namespace: request.namespace, installationOwnerID: owner)
        XCTAssertEqual(retained.progress, loaded.progress)
    }

    func testColdCoordinatorReusesExactUnacceptedCandidateAfterPlanWriteInterruption() async throws {
        let root = try temporaryRoot(); defer { try? FileManager.default.removeItem(at: root) }
        let lease = try NFApplicationStoreLease(applicationSupportURL: root)
        let before = try coldDestination(root)
        let request = try coldRequest(preparedArchive(annotationID: UUID(), documentID: UUID()), destination: before, root: root)
        let requests = NFRestoreRequestStore(root: NFRestoreRequestStore.root(applicationSupportURL: root), lease: lease)
        try await requests.stage(request)
        let plan = try coldPlan(request, destination: before)
        let original = try NFRestoreJournalCodec.encode(plan, maximumBytes: 64 * 1_024 * 1_024)
        let interrupted = NFDataArchiveRestoreJournal(root: try NFRestoreJournalLocation.root(applicationSupportURL: root),
            fault: { if $0 == .afterPlanWrite { throw Injected.stop } })
        do { _ = try await interrupted.accept(plan); XCTFail("Expected unaccepted plan interruption") } catch Injected.stop { }
        XCTAssertEqual(try coldDestination(root).raw.contentBytes(), try before.raw.contentBytes())
        let outcome = try await NFRestoreColdCoordinator.recover(selection: coldSelection(root), applicationSupportURL: root,
            lease: lease, installationOwnerID: owner, hasOpenedRuntime: false, isCurrentLaunch: { true },
            makeContainer: { try self.diskContainer(root) })
        XCTAssertNotNil(outcome.completion)
        let accepted = try await NFDataArchiveRestoreJournal(root: NFRestoreJournalLocation.root(applicationSupportURL: root))
            .load(transactionID: request.transactionID, namespace: request.namespace, installationOwnerID: owner)
        XCTAssertEqual(accepted.progress.phase, .verifiedComplete)
        XCTAssertEqual(try NFRestoreJournalCodec.encode(accepted.plan, maximumBytes: 64 * 1_024 * 1_024), original)
        XCTAssertEqual(accepted.plan.permittedPayload, request.permittedPayload)
        XCTAssertEqual(try coldDestination(root).raw.contentBytes(), try plan.raw.after.contentBytes())
    }

    private func coldSelection(_ root: URL) -> NFPrivateCloudStoreSelection {
        .init(durableStoreURL: root.appending(path: "Durable.store"), privateCloudConfiguration: nil,
            transition: .none, claimedLegacyArtifacts: false)
    }

    private func coldDestination(_ root: URL) throws -> NFRestoreDestinationSnapshot {
        try autoreleasepool {
            let container = try diskContainer(root)
            let context = ModelContext(container); context.autosaveEnabled = false
            return try NFRestorePlanCompiler.captureDestination(context: context, localLearningBytes: nil, adaptiveHistoryBytes: nil)
        }
    }

    private func coldRequest(_ prepared: NFPreparedDataArchive, destination: NFRestoreDestinationSnapshot,
        root: URL) throws -> NFRestoreRestartRequest {
        // Deliberately noncanonical JSON whitespace must survive the live cold path.
        let payload = Data(" \n\t".utf8) + (try NFRestorePlanCompiler.permittedPayload(prepared: prepared)) + Data("\n ".utf8)
        return .init(version: 1, transactionID: UUID(), namespace: NFRestoreColdCoordinator.namespace(for: coldSelection(root).durableStoreURL),
            installationOwnerID: owner, sourceDigest: prepared.sourceDigest, sourceByteCount: prepared.sourceByteCount,
            sourceFilename: prepared.sourceFilename, permittedPayload: payload,
            permittedPayloadDigest: NFRestoreJournalCodec.digest(payload), reviewedDestinationDigest: try destination.reviewDigest,
            policyRaw: NFDataArchiveRestorePolicy.replaceMatching.rawValue, localeIdentifier: "en_US_POSIX",
            compiledAtReferenceSeconds: date.timeIntervalSinceReferenceDate)
    }

    private func coldPlan(_ request: NFRestoreRestartRequest, destination: NFRestoreDestinationSnapshot) throws -> NFRestoreJournalPlan {
        let prepared = try NFRestorePlanCompiler.preparedFromPermittedPayload(request.permittedPayload,
            sourceDigest: request.sourceDigest, sourceByteCount: request.sourceByteCount, sourceFilename: request.sourceFilename)
        return try NFRestorePlanCompiler.compile(prepared: prepared, policy: .replaceMatching,
            expectedReviewDigest: request.reviewedDestinationDigest, destination: destination,
            transactionID: request.transactionID, namespace: request.namespace, ownerDeviceID: owner,
            compiledAt: date, locale: Locale(identifier: request.localeIdentifier), frozenPermittedPayload: request.permittedPayload)
    }

    private func coldCompleteJournal(_ request: NFRestoreRestartRequest, destination: NFRestoreDestinationSnapshot,
        root: URL, lease: NFApplicationStoreLease) async throws -> NFRestoreJournalLoaded {
        let plan = try coldPlan(request, destination: destination)
        let journal = NFDataArchiveRestoreJournal(root: try NFRestoreJournalLocation.root(applicationSupportURL: root))
        let accepted = try await journal.accept(plan)
        let phase = try await journal.mark(transactionID: request.transactionID, namespace: request.namespace,
            installationOwnerID: owner, expectedRevision: accepted.progress.revision, phase: .mutationMayHaveStarted)
        let container = try diskContainer(root)
        for domain in [NFDataArchiveRawDatabaseDomain.durable, .localOnly] {
            _ = try NFRestoreDomainApplier.applyDatabaseDomain(plan: plan, domain: domain, container: container)
        }
        let files = NFRestoreFileApplier(roots: try NFRestoreColdCoordinator.prepareSideFileRoots(
            applicationSupportURL: root, namespace: request.namespace), lease: lease)
        for operation in plan.files { _ = try await files.apply(operation, transactionID: request.transactionID) }
        let currentFiles = try await files.captureFiles()
        let context = ModelContext(container); context.autosaveEnabled = false
        _ = try await journal.verifyComplete(transactionID: request.transactionID, namespace: request.namespace,
            installationOwnerID: owner, expectedRevision: phase.revision,
            current: NFDataArchiveRawCapture.capture(context: context), files: currentFiles)
        return try await journal.load(transactionID: request.transactionID, namespace: request.namespace, installationOwnerID: owner)
    }

    private func coldDeleteAnnotation(_ id: UUID, root: URL) throws {
        try autoreleasepool {
            let container = try diskContainer(root)
            let context = ModelContext(container); context.autosaveEnabled = false
            let matches = try context.fetch(FetchDescriptor<ProgressAnnotationRecord>()).filter { $0.id == id }
            XCTAssertEqual(matches.count, 1)
            for record in matches { context.delete(record) }
            try context.save()
        }
    }
}

extension NFRestorePlanCompilerAndDomainTests {
    func testRuntimeReviewStagesExactFrozenRequestWithoutChangingEitherDatabaseOrSideFiles() async throws {
        let root = try temporaryRoot(); defer { try? FileManager.default.removeItem(at: root) }
        let lease = try NFApplicationStoreLease(applicationSupportURL: root)
        let container = try diskContainer(root)
        let store = AppStore(context: container.mainContext, localSessionRepository: NFLocalSessionRepository(),
            allowsSharedWidgetPublishing: false)
        let controller = try NFRestoreRuntimeController(applicationSupportURL: root,
            durableStoreURL: coldSelection(root).durableStoreURL, owner: owner, lease: lease)
        let prepared = try preparedArchive(annotationID: UUID(), documentID: UUID())
        let review = try await controller.prepareReview(prepared, store: store)
        let before = try NFDataArchiveRawCapture.capture(context: store.context).contentBytes()
        let files = NFRestoreFileApplier(roots: NFRestoreColdCoordinator.sideFileRoots(applicationSupportURL: root,
            namespace: NFRestoreColdCoordinator.namespace(for: coldSelection(root).durableStoreURL)), lease: lease)
        let beforeFiles = try await files.captureFiles()
        let suite = "NFRestoreRuntimeTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite)); defer { defaults.removePersistentDomain(forName: suite) }
        let integrations = NFSystemIntegrationCoordinator(defaults: defaults)
        try await controller.stage(review, policy: .replaceMatching, store: store, integrations: integrations)
        XCTAssertTrue(controller.requiresRestart); XCTAssertFalse(controller.isStaging)
        let requests = NFRestoreRequestStore(root: NFRestoreRequestStore.root(applicationSupportURL: root), lease: lease)
        let entries = try await requests.inspectAll()
        XCTAssertEqual(entries.count, 1)
        let entry = try XCTUnwrap(entries.first)
        let request = try await requests.load(transactionID: entry.transactionID, namespace: entry.namespace, owner: owner)
        XCTAssertEqual(request.permittedPayload, review.permittedPayload)
        XCTAssertEqual(request.reviewedDestinationDigest, review.destinationDigest)
        XCTAssertEqual(request.policyRaw, NFDataArchiveRestorePolicy.replaceMatching.rawValue)
        XCTAssertNil(entry.receipt)
        XCTAssertEqual(try NFDataArchiveRawCapture.capture(context: store.context).contentBytes(), before)
        let afterFiles = try await files.captureFiles(); XCTAssertEqual(afterFiles, beforeFiles)
        do { try await controller.stage(review, policy: .replaceMatching, store: store, integrations: integrations)
            XCTFail("Restart-required state must not publish another command") } catch { }
        let retained = try await requests.inspectAll(); XCTAssertEqual(retained.count, 1)
    }

    func testRuntimeChangedReviewAndSealedProducerCannotPublishRestoreRequest() async throws {
        let root = try temporaryRoot(); defer { try? FileManager.default.removeItem(at: root) }
        let lease = try NFApplicationStoreLease(applicationSupportURL: root)
        let container = try diskContainer(root)
        let store = AppStore(context: container.mainContext, localSessionRepository: NFLocalSessionRepository(),
            allowsSharedWidgetPublishing: false)
        let controller = try NFRestoreRuntimeController(applicationSupportURL: root,
            durableStoreURL: coldSelection(root).durableStoreURL, owner: owner, lease: lease)
        let prepared = try preparedArchive(annotationID: UUID())
        let review = try await controller.prepareReview(prepared, store: store)
        let arrival = ProgressAnnotationRecord(id: UUID(), startDate: date, endDate: date,
            note: "Arrived after the displayed review", includeInExport: true)
        store.context.insert(arrival); try store.context.save()
        let afterArrival = try NFDataArchiveRawCapture.capture(context: store.context).contentBytes()
        let suite = "NFRestoreRuntimeTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite)); defer { defaults.removePersistentDomain(forName: suite) }
        let integrations = NFSystemIntegrationCoordinator(defaults: defaults)
        do { try await controller.stage(review, policy: .replaceAll, store: store, integrations: integrations)
            XCTFail("Changed data requires a newly displayed review") }
        catch NFRestoreColdCoordinator.Failure.renewedReviewRequired { }
        XCTAssertFalse(controller.requiresRestart); XCTAssertFalse(controller.isStaging)
        let renewed = try await controller.prepareReview(prepared, store: store)
        XCTAssertNotEqual(renewed.destinationDigest, review.destinationDigest)
        await controller.seal()
        do { try await controller.stage(renewed, policy: .replaceAll, store: store, integrations: integrations)
            XCTFail("An old account producer must remain sealed") } catch { }
        let entries = try await NFRestoreRequestStore(root: NFRestoreRequestStore.root(applicationSupportURL: root), lease: lease).inspectAll()
        XCTAssertTrue(entries.isEmpty)
        XCTAssertEqual(try NFDataArchiveRawCapture.capture(context: store.context).contentBytes(), afterArrival)
    }

    func testColdCancellationRemovesOnlyUnacceptedCandidateAndNeverOpensStudyStores() async throws {
        for hasCandidate in [false, true] {
            let root = try temporaryRoot(); defer { try? FileManager.default.removeItem(at: root) }
            let lease = try NFApplicationStoreLease(applicationSupportURL: root)
            let before = try coldDestination(root)
            let request = try coldRequest(preparedArchive(annotationID: UUID()), destination: before, root: root)
            let requests = NFRestoreRequestStore(root: NFRestoreRequestStore.root(applicationSupportURL: root), lease: lease)
            try await requests.stage(request)
            if hasCandidate {
                let journal = NFDataArchiveRestoreJournal(root: try NFRestoreJournalLocation.root(applicationSupportURL: root),
                    fault: { if $0 == .afterPlanWrite { throw Injected.stop } })
                do { _ = try await journal.accept(coldPlan(request, destination: before)); XCTFail("Expected pre-acceptance interruption") }
                catch Injected.stop { }
            }
            let pending = try await NFRestoreColdCoordinator.pendingUnacceptedRequest(selection: coldSelection(root),
                applicationSupportURL: root, lease: lease, installationOwnerID: owner)
            XCTAssertEqual(pending, request)
            try await NFRestoreColdCoordinator.cancelUnacceptedRequest(selection: coldSelection(root), applicationSupportURL: root,
                lease: lease, installationOwnerID: owner, isCurrentLaunch: { true })
            let entries = try await requests.inspectAll()
            XCTAssertEqual(entries.first?.receipt?.resolution, .cancelled)
            XCTAssertEqual(entries.first?.cleanupRequired, false)
            let outcome = try await NFRestoreColdCoordinator.recover(selection: coldSelection(root), applicationSupportURL: root,
                lease: lease, installationOwnerID: owner, hasOpenedRuntime: false, isCurrentLaunch: { true },
                makeContainer: { XCTFail("Cancellation must not open or restore study stores"); throw Injected.stop })
            XCTAssertNil(outcome.container); XCTAssertNil(outcome.completion)
            XCTAssertEqual(try coldDestination(root).raw.contentBytes(), try before.raw.contentBytes())
            do { try await requests.stage(request); XCTFail("Cancelled command cannot be republished") }
            catch { XCTAssertEqual(error as? NFRestoreJournalError, .invalidated) }
        }
    }

    func testAcceptedRestoreCannotBeCancelledAndKeepsItsExactRecoveryAuthority() async throws {
        let root = try temporaryRoot(); defer { try? FileManager.default.removeItem(at: root) }
        let lease = try NFApplicationStoreLease(applicationSupportURL: root)
        let before = try coldDestination(root)
        let request = try coldRequest(preparedArchive(annotationID: UUID()), destination: before, root: root)
        let requests = NFRestoreRequestStore(root: NFRestoreRequestStore.root(applicationSupportURL: root), lease: lease)
        try await requests.stage(request)
        let journal = NFDataArchiveRestoreJournal(root: try NFRestoreJournalLocation.root(applicationSupportURL: root))
        let plan = try coldPlan(request, destination: before)
        let accepted = try await journal.accept(plan)
        let pending = try await NFRestoreColdCoordinator.pendingUnacceptedRequest(selection: coldSelection(root),
            applicationSupportURL: root, lease: lease, installationOwnerID: owner)
        XCTAssertNil(pending)
        do { try await NFRestoreColdCoordinator.cancelUnacceptedRequest(selection: coldSelection(root), applicationSupportURL: root,
            lease: lease, installationOwnerID: owner, isCurrentLaunch: { true }); XCTFail("Accepted authority requires forward recovery") }
        catch NFRestoreColdCoordinator.Failure.unresolvedArtifacts { }
        let retained = try await journal.load(transactionID: request.transactionID, namespace: request.namespace, installationOwnerID: owner)
        XCTAssertEqual(retained.plan, plan); XCTAssertEqual(retained.progress, accepted.progress)
        let entries = try await requests.inspectAll(); XCTAssertNil(entries.first?.receipt)
        XCTAssertEqual(try coldDestination(root).raw.contentBytes(), try before.raw.contentBytes())
    }
}

extension NFRestorePlanCompilerAndDomainTests {
    func testExplicitDeletionRetiresCompletedRawPayloadsBeforeDeletingRecordsAndRetainsUnacknowledgedCounts() async throws {
        let root = try temporaryRoot(); defer { try? FileManager.default.removeItem(at: root) }
        let lease = try NFApplicationStoreLease(applicationSupportURL: root)
        let id = UUID()
        let before = try coldDestination(root)
        let request = try coldRequest(preparedArchive(annotationID: id, note: "PRIVATE-DELETION-CANARY-019"), destination: before, root: root)
        let requests = NFRestoreRequestStore(root: NFRestoreRequestStore.root(applicationSupportURL: root), lease: lease)
        try await requests.stage(request)
        let loaded = try await coldCompleteJournal(request, destination: before, root: root, lease: lease)
        let receipt = try await requests.resolve(request, resolution: .completed,
            acceptedPlanDigest: loaded.descriptor.planDigest, counts: loaded.plan.acceptedCounts)
        let controller = try NFRestoreRuntimeController(applicationSupportURL: root, durableStoreURL: coldSelection(root).durableStoreURL,
            owner: owner, lease: lease, requestStore: requests)
        var deleted = 0
        try await controller.performLinkedDeletion {
            XCTAssertTrue(controller.isPerformingLinkedDeletion)
            XCTAssertFalse(controller.canPrepareRestore)
            XCTAssertFalse(FileManager.default.fileExists(atPath: try cleanupPlanURL(root, request).path))
            try coldDeleteAnnotation(id, root: root)
            deleted += 1
        }
        XCTAssertEqual(deleted, 1)
        XCTAssertFalse(controller.isPerformingLinkedDeletion)
        XCTAssertFalse(controller.isCleaningRestoreArtifacts)
        XCTAssertFalse(controller.restoreArtifactCleanupRequired)
        XCTAssertTrue(controller.canPrepareRestore, "An ordinary deletion must not permanently seal restore availability")
        let journal = NFDataArchiveRestoreJournal(root: try NFRestoreJournalLocation.root(applicationSupportURL: root))
        let entries = try await journal.inspectAllNamespaces()
        XCTAssertEqual(entries.first?.progress?.phase, .cleaned)
        let remaining = try await requests.inspectAll()
        XCTAssertEqual(remaining.first?.receipt, receipt)
        XCTAssertEqual(remaining.first?.completionAcknowledged, false)
        XCTAssertEqual(remaining.first?.cleanupRequired, false)
        XCTAssertEqual(remaining.first?.receipt?.counts, loaded.plan.acceptedCounts)
        let folder = try cleanupPlanURL(root, request).deletingLastPathComponent()
        XCTAssertEqual(Set(try FileManager.default.contentsOfDirectory(atPath: folder.path)), ["accepted.json", "progress.json"])
        do { _ = try await journal.accept(loaded.plan); XCTFail("A cleaned command cannot reaccept deleted private payloads") }
        catch NFRestoreJournalError.invalidated { }
        do { try await requests.stage(request); XCTFail("The prior producer remains sealed even after a fresh producer is available") }
        catch NFRestoreJournalError.invalidated { }
        XCTAssertTrue(try coldDestination(root).raw.tables.first { $0.model == "ProgressAnnotationRecord" }!.rows.isEmpty)
    }

    func testExplicitDeletionCleanupFailureDoesNotInvokePrimaryDeletionAndSameControllerCanRetry() async throws {
        let root = try temporaryRoot(); defer { try? FileManager.default.removeItem(at: root) }
        let lease = try NFApplicationStoreLease(applicationSupportURL: root)
        let id = UUID()
        let before = try coldDestination(root)
        let request = try coldRequest(preparedArchive(annotationID: id), destination: before, root: root)
        let loaded = try await coldCompleteJournal(request, destination: before, root: root, lease: lease)
        let fault = RestoreCleanupFaultSwitch()
        let journal = NFDataArchiveRestoreJournal(root: try NFRestoreJournalLocation.root(applicationSupportURL: root),
            fault: { if $0 == .beforeInvalidationPublish, fault.isEnabled { throw Injected.stop } })
        let controller = try NFRestoreRuntimeController(applicationSupportURL: root, durableStoreURL: coldSelection(root).durableStoreURL,
            owner: owner, lease: lease, journal: journal)
        let original = try Data(contentsOf: cleanupPlanURL(root, request))
        var deleted = 0
        do {
            try await controller.performLinkedDeletion { deleted += 1; try coldDeleteAnnotation(id, root: root) }
            XCTFail("Expected failure before durable invalidation")
        } catch Injected.stop { }
        XCTAssertEqual(deleted, 0)
        XCTAssertTrue(controller.restoreArtifactCleanupRequired)
        XCTAssertEqual(controller.restoreArtifactCleanupComponent, .recoveryBackups)
        XCTAssertFalse(controller.canPrepareRestore)
        XCTAssertFalse(controller.isCleaningRestoreArtifacts)
        XCTAssertEqual(try Data(contentsOf: cleanupPlanURL(root, request)), original)
        XCTAssertEqual(try coldDestination(root).raw.contentBytes(), try loaded.plan.raw.after.contentBytes())
        fault.disable()
        try await controller.performLinkedDeletion { deleted += 1; try coldDeleteAnnotation(id, root: root) }
        XCTAssertEqual(deleted, 1)
        XCTAssertFalse(controller.restoreArtifactCleanupRequired)
        XCTAssertTrue(controller.canPrepareRestore)
        XCTAssertFalse(FileManager.default.fileExists(atPath: try cleanupPlanURL(root, request).path))
    }

    func testExplicitDeletionRetryUsesInvalidatedReceiptAfterLostInvalidationOrPayloadRemovalAcknowledgement() async throws {
        for boundary in [NFDataArchiveRestoreJournal.Boundary.afterInvalidationPublish, .beforeCleanupReceipt] {
            let root = try temporaryRoot(); defer { try? FileManager.default.removeItem(at: root) }
            let lease = try NFApplicationStoreLease(applicationSupportURL: root)
            let id = UUID()
            let before = try coldDestination(root)
            let request = try coldRequest(preparedArchive(annotationID: id), destination: before, root: root)
            let loaded = try await coldCompleteJournal(request, destination: before, root: root, lease: lease)
            let journal = NFDataArchiveRestoreJournal(root: try NFRestoreJournalLocation.root(applicationSupportURL: root),
                fault: { if $0 == boundary { throw Injected.stop } })
            let first = try NFRestoreRuntimeController(applicationSupportURL: root, durableStoreURL: coldSelection(root).durableStoreURL,
                owner: owner, lease: lease, journal: journal)
            var deleted = 0
            do { try await first.performLinkedDeletion { deleted += 1 }; XCTFail("Expected interrupted cleanup") }
            catch Injected.stop { }
            XCTAssertEqual(deleted, 0)
            XCTAssertEqual(try coldDestination(root).raw.contentBytes(), try loaded.plan.raw.after.contentBytes())
            let state = try await journal.inspectAllNamespaces()
            XCTAssertEqual(state.first?.progress?.phase, .invalidated)
            XCTAssertEqual(FileManager.default.fileExists(atPath: try cleanupPlanURL(root, request).path), boundary != .beforeCleanupReceipt)
            // A fresh owner recovers authenticated invalidation even after the
            // raw plan has already been removed. It never replays the plan.
            let retry = try NFRestoreRuntimeController(applicationSupportURL: root, durableStoreURL: coldSelection(root).durableStoreURL,
                owner: owner, lease: lease)
            try await retry.performLinkedDeletion { deleted += 1; try coldDeleteAnnotation(id, root: root) }
            XCTAssertEqual(deleted, 1)
            let finished = try await journal.inspectAllNamespaces()
            XCTAssertEqual(finished.first?.progress?.phase, .cleaned)
        }
    }

    func testExplicitDeletionRejectsUnknownArtifactsForeignOwnershipAndUnfinishedRecoveryBeforeAnyInvalidation() async throws {
        for variant in 0..<4 {
            let root = try temporaryRoot(); defer { try? FileManager.default.removeItem(at: root) }
            let lease = try NFApplicationStoreLease(applicationSupportURL: root)
            let before = try coldDestination(root)
            let request = try coldRequest(preparedArchive(annotationID: UUID()), destination: before, root: root)
            let loaded = try await coldCompleteJournal(request, destination: before, root: root, lease: lease)
            let journalRoot = try NFRestoreJournalLocation.root(applicationSupportURL: root)
            let journal = NFDataArchiveRestoreJournal(root: journalRoot)
            var protectedFile = try cleanupPlanURL(root, request)
            if variant == 0 {
                protectedFile = protectedFile.deletingLastPathComponent().appending(path: "unknown-private-attachment")
                try Data("UNKNOWN-PRIVATE-ARTIFACT".utf8).write(to: protectedFile)
            } else if variant == 1 {
                try Data("{corrupt but private}".utf8).write(to: protectedFile)
            } else if variant == 2 {
                let foreign = NFRestoreJournalPlan(transactionID: UUID(), namespace: request.namespace,
                    installationOwnerID: UUID(), sourceDigest: loaded.plan.sourceDigest,
                    permittedPayload: loaded.plan.permittedPayload, policy: .keepExisting,
                    acceptedCounts: [:], raw: try .init(before: before.raw, after: before.raw))
                _ = try await journal.accept(foreign)
                _ = try await journal.verifyComplete(transactionID: foreign.transactionID, namespace: foreign.namespace,
                    installationOwnerID: foreign.installationOwnerID, expectedRevision: 0, current: before.raw, files: [:])
            } else {
                let pending = NFRestoreJournalPlan(transactionID: UUID(), namespace: request.namespace,
                    installationOwnerID: owner, sourceDigest: loaded.plan.sourceDigest,
                    permittedPayload: loaded.plan.permittedPayload, policy: .keepExisting,
                    acceptedCounts: [:], raw: try .init(before: loaded.plan.raw.after, after: loaded.plan.raw.after))
                _ = try await journal.accept(pending)
            }
            let original = try Data(contentsOf: protectedFile)
            let controller = try NFRestoreRuntimeController(applicationSupportURL: root, durableStoreURL: coldSelection(root).durableStoreURL,
                owner: owner, lease: lease)
            var deleted = false
            do { try await controller.performLinkedDeletion { deleted = true }; XCTFail("Unsafe recovery artifacts must remain blocked") }
            catch { }
            XCTAssertFalse(deleted)
            XCTAssertTrue(controller.restoreArtifactCleanupRequired)
            XCTAssertEqual(try Data(contentsOf: protectedFile), original)
            let retained = try await journal.inspectAllNamespaces()
            XCTAssertEqual(retained.first { $0.transactionID == request.transactionID }?.progress?.phase, .verifiedComplete)
            XCTAssertEqual(try coldDestination(root).raw.contentBytes(), try loaded.plan.raw.after.contentBytes())
        }
    }

    func testExplicitDeletionPreservesPendingRequestUntilCancellationAndThenRestoresAvailability() async throws {
        let root = try temporaryRoot(); defer { try? FileManager.default.removeItem(at: root) }
        let lease = try NFApplicationStoreLease(applicationSupportURL: root)
        let before = try coldDestination(root)
        let request = try coldRequest(preparedArchive(annotationID: UUID()), destination: before, root: root)
        let requests = NFRestoreRequestStore(root: NFRestoreRequestStore.root(applicationSupportURL: root), lease: lease)
        try await requests.stage(request)
        let controller = try NFRestoreRuntimeController(applicationSupportURL: root, durableStoreURL: coldSelection(root).durableStoreURL,
            owner: owner, lease: lease, requestStore: requests)
        var called = 0
        do { try await controller.performLinkedDeletion { called += 1 }; XCTFail("A pending request requires cancellation before ordinary deletion") }
        catch NFRestoreJournalError.recoveryConflict { }
        XCTAssertEqual(called, 0)
        let retained = try await requests.load(transactionID: request.transactionID, namespace: request.namespace, owner: owner)
        XCTAssertEqual(retained, request)
        // Models remain untouched; the existing cancellation flow may now retire
        // the unaccepted request. Its command tombstone prevents delayed staging.
        let receipt = try await requests.resolve(request, resolution: .cancelled)
        try await controller.performLinkedDeletion { called += 1 }
        XCTAssertEqual(called, 1)
        XCTAssertTrue(controller.canPrepareRestore)
        let entries = try await requests.inspectAll()
        XCTAssertEqual(entries.first?.receipt, receipt)
        do { try await requests.stage(request); XCTFail("A delayed old producer must stay sealed") }
        catch NFRestoreJournalError.invalidated { }
    }

    func testExplicitDeletionWaitsForPrivateRequestCleanupAndDoesNotUndoRetirementWhenPrimarySaveFails() async throws {
        let root = try temporaryRoot(); defer { try? FileManager.default.removeItem(at: root) }
        let lease = try NFApplicationStoreLease(applicationSupportURL: root)
        let id = UUID()
        let before = try coldDestination(root)
        let request = try coldRequest(preparedArchive(annotationID: id), destination: before, root: root)
        let requests = NFRestoreRequestStore(root: NFRestoreRequestStore.root(applicationSupportURL: root), lease: lease)
        try await requests.stage(request)
        let loaded = try await coldCompleteJournal(request, destination: before, root: root, lease: lease)
        let interrupted = NFRestoreRequestStore(root: NFRestoreRequestStore.root(applicationSupportURL: root), lease: lease,
            fault: { if $0 == .beforePayloadCleanup { throw Injected.stop } })
        do {
            _ = try await interrupted.resolve(request, resolution: .completed,
                acceptedPlanDigest: loaded.descriptor.planDigest, counts: loaded.plan.acceptedCounts)
            XCTFail("Expected a retained request payload after its completion receipt")
        } catch Injected.stop { }
        let first = try NFRestoreRuntimeController(applicationSupportURL: root, durableStoreURL: coldSelection(root).durableStoreURL,
            owner: owner, lease: lease, requestStore: interrupted)
        var called = 0
        do { try await first.performLinkedDeletion { called += 1 }; XCTFail("The primary deletion must wait for request-byte cleanup") }
        catch Injected.stop { }
        XCTAssertEqual(called, 0)
        XCTAssertTrue(first.restoreArtifactCleanupRequired)
        XCTAssertEqual(first.restoreArtifactCleanupComponent, .requests)
        let pending = try await requests.inspectAll()
        XCTAssertEqual(pending.first?.cleanupRequired, true)
        XCTAssertEqual(try coldDestination(root).raw.contentBytes(), try loaded.plan.raw.after.contentBytes())
        let retry = try NFRestoreRuntimeController(applicationSupportURL: root, durableStoreURL: coldSelection(root).durableStoreURL,
            owner: owner, lease: lease)
        do {
            try await retry.performLinkedDeletion { called += 1; throw Injected.stop }
            XCTFail("Expected independent primary save failure")
        } catch Injected.stop { }
        XCTAssertEqual(called, 1)
        XCTAssertTrue(retry.canPrepareRestore)
        XCTAssertFalse(retry.restoreArtifactCleanupRequired)
        XCTAssertFalse(FileManager.default.fileExists(atPath: try cleanupPlanURL(root, request).path))
        let final = try await requests.inspectAll()
        XCTAssertEqual(final.first?.cleanupRequired, false)
        XCTAssertEqual(final.first?.receipt?.counts, loaded.plan.acceptedCounts)
        XCTAssertEqual(try coldDestination(root).raw.contentBytes(), try loaded.plan.raw.after.contentBytes())
    }

    func testExplicitDeletionRetiresSameInstallationCompletedBackupsAcrossPriorAccountNamespaces() async throws {
        let root = try temporaryRoot(); defer { try? FileManager.default.removeItem(at: root) }
        let lease = try NFApplicationStoreLease(applicationSupportURL: root)
        let before = try coldDestination(root)
        let request = try coldRequest(preparedArchive(annotationID: UUID(), documentID: UUID()), destination: before, root: root)
        let first = try await coldCompleteJournal(request, destination: before, root: root, lease: lease)
        let journalRoot = try NFRestoreJournalLocation.root(applicationSupportURL: root)
        let journal = NFDataArchiveRestoreJournal(root: journalRoot)
        let second = NFRestoreJournalPlan(transactionID: UUID(), namespace: NFRestoreJournalCodec.digest(Data("prior account".utf8)),
            installationOwnerID: owner, sourceDigest: first.plan.sourceDigest, permittedPayload: first.plan.permittedPayload,
            policy: .keepExisting, acceptedCounts: [:], raw: try .init(before: first.plan.raw.after, after: first.plan.raw.after))
        _ = try await journal.accept(second)
        _ = try await journal.verifyComplete(transactionID: second.transactionID, namespace: second.namespace,
            installationOwnerID: owner, expectedRevision: 0, current: second.raw.after, files: [:])
        let controller = try NFRestoreRuntimeController(applicationSupportURL: root, durableStoreURL: coldSelection(root).durableStoreURL,
            owner: owner, lease: lease)
        try await controller.performLinkedDeletion {
            for id in [request.transactionID, second.transactionID] {
                XCTAssertFalse(FileManager.default.fileExists(atPath: journalRoot.appending(path: id.uuidString.lowercased() + "/plan.json").path))
            }
        }
        let entries = try await journal.inspectAllNamespaces()
        XCTAssertEqual(entries.count, 2)
        XCTAssertTrue(entries.allSatisfy { $0.progress?.phase == .cleaned })
        XCTAssertEqual(Set(entries.compactMap { $0.descriptor?.namespace }), [request.namespace, second.namespace])
        XCTAssertEqual(try coldDestination(root).raw.contentBytes(), try first.plan.raw.after.contentBytes(),
            "Retiring restore backups never deletes another namespace's ordinary records")
    }

    private func cleanupPlanURL(_ root: URL, _ request: NFRestoreRestartRequest) throws -> URL {
        try NFRestoreJournalLocation.root(applicationSupportURL: root)
            .appending(path: request.transactionID.uuidString.lowercased() + "/plan.json")
    }
}

private final class RestoreCleanupFaultSwitch: @unchecked Sendable {
    private let lock = NSLock()
    private var enabled = true
    var isEnabled: Bool { lock.lock(); defer { lock.unlock() }; return enabled }
    func disable() { lock.lock(); defer { lock.unlock() }; enabled = false }
}

extension NFRestorePlanCompilerAndDomainTests {
    func testDurableAppStoreDeletionRequiresAvailableExecutingRestoreGateBeforeAnyMutation() async throws {
        let root = try temporaryRoot(); defer { try? FileManager.default.removeItem(at: root) }
        let container = try diskContainer(root)
        let store = cleanupAppStore(container: container, root: root, policy: .automatic)
        let annotation = ProgressAnnotationRecord(id: UUID(), startDate: date, endDate: date, note: "PRIVATE-ANNOTATION", includeInExport: false)
        let folder = root.appending(path: "Documents", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appending(path: "private.txt")
        let bytes = Data("PRIVATE-SOURCE-BYTES".utf8); try bytes.write(to: url)
        let document = SourceDocumentRecord(filename: "private.txt", typeIdentifier: "public.text", sizeBytes: Int64(bytes.count), localPath: url.path)
        let generationID = UUID()
        let attempt = AttemptRecord(sessionID: UUID(), lab: .mentalMath, itemID: "private-attempt",
            prompt: "Question", response: "PRIVATE-ANSWER", correctAnswer: "Key", isCorrect: false, confidence: .certain)
        attempt.generationID = generationID
        store.context.insert(annotation); store.context.insert(document); store.context.insert(attempt)
        try store.context.save(); store.reload()
        let before = try NFDataArchiveRawCapture.capture(context: store.context).contentBytes()
        XCTAssertTrue(store.requiresRestoreArtifactDeletionGate)
        store.bindRestoreArtifactDeletionController(nil)
        for mutation: () throws -> Void in [
            { try store.deleteProgressAnnotation(annotation) },
            { try store.deleteDocument(document) },
            { _ = try store.deleteAIGenerationAttempts(id: generationID) },
            { try store.discardAIGenerationPayload(id: generationID) }
        ] {
            XCTAssertThrowsError(try mutation()) { error in
                guard case NFRestoreLinkedDeletionError.unavailable = error else { return XCTFail("Wrong refusal: \(error)") }
            }
        }
        do {
            try await store.withLinkedRestoreArtifactDeletion { try store.deleteDocument(document) }
            XCTFail("A nil production controller is not a no-artifacts exemption")
        } catch NFRestoreLinkedDeletionError.unavailable { }
        XCTAssertEqual(try Data(contentsOf: url), bytes)
        XCTAssertEqual(try NFDataArchiveRawCapture.capture(context: store.context).contentBytes(), before)
        XCTAssertFalse(store.context.hasChanges)
        let lease = try NFApplicationStoreLease(applicationSupportURL: root)
        let controller = try NFRestoreRuntimeController(applicationSupportURL: root, durableStoreURL: coldSelection(root).durableStoreURL,
            owner: owner, lease: lease)
        store.bindRestoreArtifactDeletionController(controller)
        XCTAssertThrowsError(try store.deleteProgressAnnotation(annotation), "Binding alone must not authorize an unwrapped deletion")
        XCTAssertEqual(try NFDataArchiveRawCapture.capture(context: store.context).contentBytes(), before)
        let wrongNamespace = try NFRestoreRuntimeController(applicationSupportURL: root,
            durableStoreURL: root.appending(path: "Another-account.store"), owner: owner, lease: lease)
        store.bindRestoreArtifactDeletionController(wrongNamespace)
        do {
            try await store.withLinkedRestoreArtifactDeletion { try store.deleteDocument(document) }
            XCTFail("Cleaning a different store namespace cannot authorize this deletion")
        } catch NFRestoreLinkedDeletionError.unavailable { }
        XCTAssertEqual(try Data(contentsOf: url), bytes)
        XCTAssertEqual(try NFDataArchiveRawCapture.capture(context: store.context).contentBytes(), before)
    }

    func testAppStoreWrappedSourceDeletionRemovesJournalPayloadBeforeManagedSourceAndLinkedHistory() async throws {
        let root = try temporaryRoot(); defer { try? FileManager.default.removeItem(at: root) }
        let lease = try NFApplicationStoreLease(applicationSupportURL: root)
        let container = try diskContainer(root)
        let store = cleanupAppStore(container: container, root: root, policy: .required)
        let folder = root.appending(path: "Documents", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appending(path: "private-source.txt")
        let bytes = Data("LINKED-DELETE-SOURCE-CANARY-310".utf8); try bytes.write(to: url)
        let document = SourceDocumentRecord(filename: "private-source.txt", typeIdentifier: "public.text", sizeBytes: Int64(bytes.count), localPath: url.path)
        let attempt = AttemptRecord(sessionID: UUID(), lab: .mentalMath, itemID: "linked-delete-attempt",
            prompt: "Question", response: "LINKED-DELETE-ANSWER-CANARY-311", correctAnswer: "Key", isCorrect: false, confidence: .certain)
        attempt.sourceDocumentIDsRaw = document.id.uuidString
        let attemptID = attempt.id
        store.context.insert(document); store.context.insert(attempt); try store.context.save(); store.reload()
        let before = try coldDestination(root)
        let request = try coldRequest(preparedArchive(), destination: before, root: root)
        let completed = try await coldCompleteJournal(request, destination: before, root: root, lease: lease)
        let originalPlan = try Data(contentsOf: cleanupPlanURL(root, request))
        XCTAssertFalse(originalPlan.isEmpty)
        let controller = try NFRestoreRuntimeController(applicationSupportURL: root, durableStoreURL: coldSelection(root).durableStoreURL,
            owner: owner, lease: lease)
        store.bindRestoreArtifactDeletionController(controller)
        try await store.withLinkedRestoreArtifactDeletion {
            XCTAssertFalse(FileManager.default.fileExists(atPath: try cleanupPlanURL(root, request).path))
            XCTAssertEqual(try Data(contentsOf: url), bytes, "Managed source removal must follow verified journal cleanup")
            try store.deleteDocument(document)
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
        XCTAssertTrue(store.documents.isEmpty)
        XCTAssertFalse(store.attempts.contains { $0.id == attemptID })
        let journal = NFDataArchiveRestoreJournal(root: try NFRestoreJournalLocation.root(applicationSupportURL: root))
        let entries = try await journal.inspectAllNamespaces()
        XCTAssertEqual(entries.first?.progress?.phase, .cleaned)
        do { _ = try await journal.accept(completed.plan); XCTFail("Deleted source/answer cannot return through the old command") }
        catch NFRestoreJournalError.invalidated { }
    }

    func testAppStoreArtifactFailurePreservesSourceAndPrimaryAttemptUntilRetry() async throws {
        let root = try temporaryRoot(); defer { try? FileManager.default.removeItem(at: root) }
        let lease = try NFApplicationStoreLease(applicationSupportURL: root)
        let container = try diskContainer(root)
        let store = cleanupAppStore(container: container, root: root, policy: .required)
        let folder = root.appending(path: "Documents", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appending(path: "keep.txt")
        let bytes = Data("PRESERVE-WHEN-CLEANUP-FAILS".utf8); try bytes.write(to: url)
        let document = SourceDocumentRecord(filename: "keep.txt", typeIdentifier: "public.text", sizeBytes: Int64(bytes.count), localPath: url.path)
        store.context.insert(document); try store.context.save(); store.reload()
        let before = try coldDestination(root)
        let request = try coldRequest(preparedArchive(), destination: before, root: root)
        _ = try await coldCompleteJournal(request, destination: before, root: root, lease: lease)
        let fault = RestoreCleanupFaultSwitch()
        let journal = NFDataArchiveRestoreJournal(root: try NFRestoreJournalLocation.root(applicationSupportURL: root),
            fault: { if $0 == .beforeCleanup, fault.isEnabled { throw Injected.stop } })
        let controller = try NFRestoreRuntimeController(applicationSupportURL: root, durableStoreURL: coldSelection(root).durableStoreURL,
            owner: owner, lease: lease, journal: journal)
        store.bindRestoreArtifactDeletionController(controller)
        let raw = try NFDataArchiveRawCapture.capture(context: store.context).contentBytes()
        do {
            try await store.withLinkedRestoreArtifactDeletion { try store.deleteDocument(document) }
            XCTFail("Expected an identified incomplete recovery-file cleanup")
        } catch NFRestoreLinkedDeletionError.unfinished(.recoveryBackups) { }
        XCTAssertEqual(try Data(contentsOf: url), bytes)
        XCTAssertEqual(try NFDataArchiveRawCapture.capture(context: store.context).contentBytes(), raw)
        XCTAssertFalse(store.context.hasChanges)
        XCTAssertTrue(controller.restoreArtifactCleanupRequired)
        fault.disable()
        try await store.withLinkedRestoreArtifactDeletion { try store.deleteDocument(document) }
        XCTAssertTrue(store.documents.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
        XCTAssertTrue(controller.canPrepareRestore)
    }

    func testExplicitSyntheticDeletionPolicyRequiresIsolatedDependenciesAndDoesNotVisitRestoreRoots() async throws {
        let root = try temporaryRoot(); defer { try? FileManager.default.removeItem(at: root) }
        let container = try diskContainer(root)
        let store = cleanupAppStore(container: container, root: root, policy: .isolatedNoRestoreArtifacts)
        XCTAssertFalse(store.requiresRestoreArtifactDeletionGate)
        let annotation = ProgressAnnotationRecord(id: UUID(), startDate: date, endDate: date, note: "Synthetic only", includeInExport: false)
        store.context.insert(annotation); try store.context.save(); store.reload()
        try await store.withLinkedRestoreArtifactDeletion { try store.deleteProgressAnnotation(annotation) }
        XCTAssertTrue(store.progressAnnotations.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: try NFRestoreJournalLocation.root(applicationSupportURL: root).path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: NFRestoreRequestStore.root(applicationSupportURL: root).path))
        // Removing the required artifact-root isolation makes the same explicit
        // opt-out fail closed for a durable store, rather than trusting the flag.
        let guarded = AppStore(context: container.mainContext,
            nextDayEnhancementCache: NFNextDayEnhancementCache(rootURL: root.appending(path: "Cache")),
            documentStorageRootURL: root.appending(path: "Documents"),
            localSessionRepository: NFLocalSessionRepository(ownerDeviceID: owner),
            adaptivePlanHistoryRepository: NFAdaptivePlanHistoryRepository(fileURL: root.appending(path: "History.json")),
            offlineQuestionRotation: NFOfflineQuestionRotation(store: NFMemoryOfflineQuestionRotationStateStore()),
            restoreArtifactDeletionPolicy: .isolatedNoRestoreArtifacts, allowsSharedWidgetPublishing: false)
        XCTAssertTrue(guarded.requiresRestoreArtifactDeletionGate)
        XCTAssertThrowsError(try guarded.discardAIGenerationPayload(id: UUID()))
    }

    func testColdCleanupRetryFinishesOnlyInvalidatedArtifactsAndNeverOpensOrDeletesStudyData() async throws {
        let root = try temporaryRoot(); defer { try? FileManager.default.removeItem(at: root) }
        let lease = try NFApplicationStoreLease(applicationSupportURL: root)
        let before = try coldDestination(root)
        let request = try coldRequest(preparedArchive(annotationID: UUID(), documentID: UUID()), destination: before, root: root)
        let first = try await coldCompleteJournal(request, destination: before, root: root, lease: lease)
        let journalRoot = try NFRestoreJournalLocation.root(applicationSupportURL: root)
        let journal = NFDataArchiveRestoreJournal(root: journalRoot)
        let unrelated = NFRestoreJournalPlan(transactionID: UUID(), namespace: request.namespace, installationOwnerID: owner,
            sourceDigest: first.plan.sourceDigest, permittedPayload: first.plan.permittedPayload, policy: .keepExisting,
            acceptedCounts: [:], raw: try .init(before: first.plan.raw.after, after: first.plan.raw.after))
        _ = try await journal.accept(unrelated)
        _ = try await journal.verifyComplete(transactionID: unrelated.transactionID, namespace: unrelated.namespace,
            installationOwnerID: owner, expectedRevision: 0, current: unrelated.raw.after, files: [:])
        _ = try await journal.invalidate(transactionID: request.transactionID, namespace: request.namespace,
            installationOwnerID: owner, expectedRevision: first.progress.revision)
        let faulting = NFDataArchiveRestoreJournal(root: journalRoot,
            fault: { if $0 == .beforeCleanupReceipt { throw Injected.stop } })
        do {
            try await faulting.removeInvalidated(transactionID: request.transactionID, namespace: request.namespace, installationOwnerID: owner)
            XCTFail("Expected interrupted cleanup with plan.json already absent")
        } catch Injected.stop { }
        XCTAssertFalse(FileManager.default.fileExists(atPath: try cleanupPlanURL(root, request).path))
        let unrelatedURL = journalRoot.appending(path: unrelated.transactionID.uuidString.lowercased() + "/plan.json")
        let unrelatedBytes = try Data(contentsOf: unrelatedURL)
        let rawBefore = try coldDestination(root).raw.contentBytes()
        let blocked = await NFRestoreStartupGate.inspect(applicationSupportURL: root)
        XCTAssertEqual(blocked.block?.reason, .cleanupRequired)
        try await NFRestoreColdCoordinator.retryInvalidatedCleanup(applicationSupportURL: root, lease: lease,
            installationOwnerID: owner, hasOpenedRuntime: false, isCurrentLaunch: { true })
        let entries = try await journal.inspectAllNamespaces()
        XCTAssertEqual(entries.first { $0.transactionID == request.transactionID }?.progress?.phase, .cleaned)
        XCTAssertEqual(entries.first { $0.transactionID == unrelated.transactionID }?.progress?.phase, .verifiedComplete)
        XCTAssertEqual(try Data(contentsOf: unrelatedURL), unrelatedBytes)
        XCTAssertEqual(try coldDestination(root).raw.contentBytes(), rawBefore)
        let cleared = await NFRestoreStartupGate.inspect(applicationSupportURL: root)
        XCTAssertTrue(cleared.permitsModelContainerOpen)
    }

    func testColdCleanupRetryRejectsMissingForeignOwnerAndLiveOrStaleLaunchWithoutRemovingPayload() async throws {
        let root = try temporaryRoot(); defer { try? FileManager.default.removeItem(at: root) }
        let lease = try NFApplicationStoreLease(applicationSupportURL: root)
        let before = try coldDestination(root)
        let request = try coldRequest(preparedArchive(annotationID: UUID()), destination: before, root: root)
        let loaded = try await coldCompleteJournal(request, destination: before, root: root, lease: lease)
        let journal = NFDataArchiveRestoreJournal(root: try NFRestoreJournalLocation.root(applicationSupportURL: root))
        _ = try await journal.invalidate(transactionID: request.transactionID, namespace: request.namespace,
            installationOwnerID: owner, expectedRevision: loaded.progress.revision)
        let original = try Data(contentsOf: cleanupPlanURL(root, request))
        for (suppliedOwner, opened, current) in [(UUID?.none, false, true), (.some(UUID()), false, true),
            (.some(owner), true, true), (.some(owner), false, false)] {
            do {
                try await NFRestoreColdCoordinator.retryInvalidatedCleanup(applicationSupportURL: root, lease: lease,
                    installationOwnerID: suppliedOwner, hasOpenedRuntime: opened, isCurrentLaunch: { current })
                XCTFail("Cleanup cannot bypass installation and cold-launch authority")
            } catch { }
            XCTAssertEqual(try Data(contentsOf: cleanupPlanURL(root, request)), original)
        }
        XCTAssertEqual(try coldDestination(root).raw.contentBytes(), try loaded.plan.raw.after.contentBytes())
    }

    private func cleanupAppStore(container: ModelContainer, root: URL,
        policy: NFRestoreArtifactDeletionPolicy) -> AppStore {
        AppStore(context: container.mainContext,
            nextDayEnhancementCache: NFNextDayEnhancementCache(rootURL: root.appending(path: "Cache")),
            documentStorageRootURL: root.appending(path: "Documents"),
            localSessionRepository: NFLocalSessionRepository(ownerDeviceID: owner),
            adaptivePlanHistoryRepository: NFAdaptivePlanHistoryRepository(fileURL: root.appending(path: "History.json")),
            offlineQuestionRotation: NFOfflineQuestionRotation(store: NFMemoryOfflineQuestionRotationStateStore()),
            temporaryArtifactsRootURL: root.appending(path: "Exports"), restoreArtifactDeletionPolicy: policy,
            allowsSharedWidgetPublishing: false)
    }
}

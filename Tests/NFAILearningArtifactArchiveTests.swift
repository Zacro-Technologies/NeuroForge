import Foundation
import SwiftData
import XCTest
@testable import NeuroForge

@MainActor
final class NFAILearningArtifactArchiveTests: XCTestCase {
    private enum Injected: Error { case stop }

    func testCapturePreservesExactTutorAndGradingDataWithoutLockFiles() async throws {
        let root = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let artifacts = root.appendingPathComponent("AILearning")
        let tutor = try tutorFile(answer: "Both dimensions scale with the radius.")
        try write(tutor, beneath: artifacts)
        let request = try gradingRequest()
        let jobs = NFAIGradingJobStore(directoryURL: artifacts)
        let savedJob = try await jobs.create(request, ownerDeviceID: UUID())
        let captured = try NFAILearningArtifactArchive.capture(at: artifacts)

        XCTAssertEqual(captured.count, 2)
        XCTAssertEqual(captured.first { $0.relativePath == tutor.relativePath }?.bytes, tutor.bytes)
        let grade = try XCTUnwrap(captured.first { $0.relativePath.hasPrefix("Grading/") })
        XCTAssertEqual(try JSONDecoder().decode(NFAIGradingJob.self, from: grade.bytes), savedJob)
        XCTAssertFalse(captured.contains { $0.relativePath.hasSuffix(".lock") })
        XCTAssertEqual(grade.digest, NFAILearningArtifactArchive.digest(grade.bytes))
    }

    func testVersion19RoundTripPreservesArtifactBytesAndLegacy18RemainsReadable() throws {
        let file = try tutorFile(answer: "Both dimensions scale with the radius.")
        var object = minimalArchive(version: 19)
        object["aiLearningArtifacts"] = try JSONSerialization.jsonObject(with: JSONEncoder().encode([file]))
        let original = try JSONSerialization.data(withJSONObject: object)
        let portable = try NFDataExportService.protectedPortableData(original, forRestore: true)
        let result = try NFDataExportRoundTripValidator.decodeArchive(data: portable)
        XCTAssertEqual(result.aiLearningArtifactPaths, [file.relativePath])
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        let archive = try decoder.decode(NFDataExportService.Archive.self, from: portable)
        XCTAssertEqual(archive.aiLearningArtifacts, [file])

        object["archiveVersion"] = 18
        XCTAssertThrowsError(try NFDataExportRoundTripValidator.decodeArchive(data: JSONSerialization.data(withJSONObject: object)))
        object.removeValue(forKey: "aiLearningArtifacts")
        XCTAssertEqual(try NFDataExportRoundTripValidator.decodeArchive(data: JSONSerialization.data(withJSONObject: object)).archiveVersion, 18)
        object["localLearning"] = ["snapshots": [["aiGrade": ["requestID": UUID().uuidString]]]]
        XCTAssertThrowsError(try NFAILearningArtifactArchive.validateArchiveVersion(object))
    }

    func testDigestUnknownFieldsAndUnsafePathsAreRejectedWithoutChangingOriginalBytes() throws {
        let file = try tutorFile(answer: "Both dimensions scale with the radius.")
        var payload = try XCTUnwrap(JSONSerialization.jsonObject(with: file.bytes) as? [String: Any])
        payload["futureAuthoritativeFeedback"] = ["answer": "Different feedback."]
        let future = NFAILearningArtifactFile(relativePath: file.relativePath, bytes: try JSONSerialization.data(withJSONObject: payload))
        XCTAssertThrowsError(try NFAILearningArtifactArchive.validate(future))
        XCTAssertThrowsError(try NFAILearningArtifactArchive.location(for: "Tutor/../../outside.json"))

        var encoded = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(file)) as? [String: Any])
        encoded["digest"] = String(repeating: "0", count: 64)
        let mismatched = try JSONDecoder().decode(NFAILearningArtifactFile.self, from: JSONSerialization.data(withJSONObject: encoded))
        XCTAssertThrowsError(try NFAILearningArtifactArchive.validate(mismatched))
        XCTAssertNoThrow(try NFAILearningArtifactArchive.validate(file))
    }

    func testConflictPoliciesAndReplaceAllDeletionKeepExactBeforeAndAfterBytes() throws {
        let old = try tutorFile(answer: "Both dimensions scale with the radius.")
        let replacement = try tutorFile(answer: "Tripling the radius multiplies the area by nine.")
        let kept = try NFAILearningArtifactArchive.operations(existing: [old], incoming: [replacement], policy: .keepExisting)
        XCTAssertEqual(kept.operations.first?.before, old.bytes)
        XCTAssertEqual(kept.operations.first?.after, old.bytes)
        XCTAssertEqual(kept.skipped, 1)
        let replaced = try NFAILearningArtifactArchive.operations(existing: [old], incoming: [replacement], policy: .replaceMatching)
        XCTAssertEqual(replaced.operations.first?.before, old.bytes)
        XCTAssertEqual(replaced.operations.first?.after, replacement.bytes)
        XCTAssertThrowsError(try NFAILearningArtifactArchive.operations(existing: [old], incoming: [replacement], policy: .abortOnConflict))
        let erased = try NFAILearningArtifactArchive.operations(existing: [old], incoming: [], policy: .replaceAll)
        XCTAssertEqual(erased.operations.first?.before, old.bytes)
        XCTAssertNil(erased.operations.first?.after)
    }

    func testRestorePublicationFaultsRecoverTheSameAcceptedArtifact() async throws {
        for boundary in [NFRestoreFileApplier.Boundary.beforeTemporaryWrite, .afterTemporaryWrite, .beforePublish, .afterPublish, .afterReadback] {
            let root = try temporaryRoot()
            defer { try? FileManager.default.removeItem(at: root) }
            let lease = try NFApplicationStoreLease(applicationSupportURL: root)
            let before = try tutorFile(answer: "Both dimensions scale with the radius.")
            let after = try tutorFile(answer: "Tripling the radius multiplies the area by nine.")
            let location = try NFAILearningArtifactArchive.location(for: before.relativePath)
            let folder = root.appendingPathComponent("Tutor")
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let file = folder.appendingPathComponent(location.filename)
            try before.bytes.write(to: file)
            let operation = try XCTUnwrap(NFAILearningArtifactArchive.operations(existing: [before], incoming: [after], policy: .replaceMatching).operations.first)
            let id = UUID()
            let interrupted = NFRestoreFileApplier(roots: [.aiTutor: folder], lease: lease, fault: { if $0 == boundary { throw Injected.stop } })
            do { _ = try await interrupted.apply(operation, transactionID: id); XCTFail("Expected the synthetic interruption.") }
            catch Injected.stop {}
            let actual = try Data(contentsOf: file)
            XCTAssertTrue(actual == before.bytes || actual == after.bytes)
            let recovered = NFRestoreFileApplier(roots: [.aiTutor: folder], lease: lease)
            _ = try await recovered.apply(operation, transactionID: id)
            XCTAssertEqual(try Data(contentsOf: file), after.bytes)
            let replay = try await recovered.apply(operation, transactionID: id)
            XCTAssertEqual(replay, .alreadyApplied)
            XCTAssertEqual(operation.before, before.bytes)
        }
    }

    func testDestinationDigestAndCompiledJournalBindArtifactChanges() throws {
        let schema = Schema(NFSchemaV1.models)
        let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
        let old = try tutorFile(answer: "Both dimensions scale with the radius.")
        let next = try tutorFile(answer: "Tripling the radius multiplies the area by nine.")
        let destination = try NFRestorePlanCompiler.captureDestination(context: container.mainContext,
            localLearningBytes: nil, adaptiveHistoryBytes: nil, aiLearningArtifacts: [old])
        let changed = NFRestoreDestinationSnapshot(raw: destination.raw, localLearningBytes: nil,
            adaptiveHistoryBytes: nil, aiLearningArtifacts: [next])
        XCTAssertNotEqual(try destination.reviewDigest, try changed.reviewDigest)

        var object = minimalArchive(version: 19)
        object["aiLearningArtifacts"] = try JSONSerialization.jsonObject(with: JSONEncoder().encode([next]))
        let bytes = try JSONSerialization.data(withJSONObject: object)
        let prepared = try NFRestorePlanCompiler.preparedFromPermittedPayload(bytes,
            sourceDigest: NFAILearningArtifactArchive.digest(bytes), sourceByteCount: bytes.count, sourceFilename: "AI backup.json")
        let plan = try NFRestorePlanCompiler.compile(prepared: prepared, policy: .replaceMatching,
            expectedReviewDigest: destination.reviewDigest, destination: destination,
            transactionID: UUID(), namespace: String(repeating: "a", count: 64), ownerDeviceID: UUID(), compiledAt: Date(), locale: Locale(identifier: "en"))
        XCTAssertEqual(try NFAILearningArtifactArchive.files(from: plan.files, before: true), [old])
        XCTAssertEqual(try NFAILearningArtifactArchive.files(from: plan.files, before: false), [next])
        XCTAssertEqual(plan.acceptedCounts["restored.local.aiArtifacts"], 1)
        XCTAssertNoThrow(try NFRestoreJournalCodec.validate(plan))
    }

    func testExplicitEraseRemovesBrokenAndKnownArtifactsOnlyInTheSelectedRoot() throws {
        let root = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let artifacts = root.appendingPathComponent("AILearning")
        try write(tutorFile(answer: "Both dimensions scale with the radius."), beneath: artifacts)
        try Data("broken retained job".utf8).write(to: artifacts.appendingPathComponent("unreadable.json"))
        let sibling = root.appendingPathComponent("source.txt")
        try Data("retained sibling".utf8).write(to: sibling)
        try NFAILearningArtifactArchive.removeAll(at: artifacts)
        XCTAssertFalse(FileManager.default.fileExists(atPath: artifacts.path))
        XCTAssertEqual(try String(contentsOf: sibling, encoding: .utf8), "retained sibling")
        XCTAssertNoThrow(try NFAILearningArtifactArchive.removeAll(at: artifacts))
    }

    func testNativeRestoreRejectsDamagedEnvelopeBeforeAdmittingItsQuestions() async throws {
        let schema = Schema(NFSchemaV1.models)
        let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
        let destination = try NFRestorePlanCompiler.captureDestination(context: container.mainContext,
            localLearningBytes: nil, adaptiveHistoryBytes: nil)
        let original = try await nativeGenerationObject()
        func preview(_ generation: [String: Any]) throws -> NFDataArchiveRestorePreview {
            var object = minimalArchive(version: 19); object["aiGenerations"] = [generation]
            let bytes = try JSONSerialization.data(withJSONObject: object)
            let prepared = try NFRestorePlanCompiler.preparedFromPermittedPayload(bytes,
                sourceDigest: NFAILearningArtifactArchive.digest(bytes), sourceByteCount: bytes.count, sourceFilename: "Native questions.json")
            return try NFRestorePlanCompiler.preview(prepared: prepared, destination: destination, locale: Locale(identifier: "en"))
        }
        XCTAssertNoThrow(try preview(original))
        for field in ["cacheKey", "modelIdentifier", "route"] {
            var damaged = original
            damaged[field] = field == "route" ? NFAIRoute.externalShortcut.rawValue : "changed-\(field)"
            XCTAssertThrowsError(try preview(damaged), "Invalid native \(field) must fail before restore admission.")
        }
        var invalidStatus = original
        let status = NFAuthoringValidationStatus(level: .deterministicKey, sourceSupport: .notApplicable)
        invalidStatus["validationStatus"] = try JSONSerialization.jsonObject(with: JSONEncoder().encode(status))
        XCTAssertThrowsError(try preview(invalidStatus))
        var expiring = original; expiring["payloadExpiresAt"] = "2026-09-12T12:00:00Z"
        XCTAssertThrowsError(try preview(expiring))
        XCTAssertTrue(try container.mainContext.fetch(FetchDescriptor<AIGenerationRecord>()).isEmpty)
    }

    private func temporaryRoot() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("NF-AI-Archive-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func tutorFile(answer: String) throws -> NFAILearningArtifactFile {
        let key = try NFAITutorContext(prompt: "How does radius affect area?", learnerResponse: "Area scales with the square of the radius.", itemID: "archive-attempt").storageKey()
        let turn = NFAITutorTurn(requestID: UUID(), question: "Why squared?", answer: answer,
            providerIdentifier: "fixture-provider", modelIdentifier: "fixture-model", route: .local,
            generatedAt: Date(timeIntervalSince1970: 1_000))
        return .init(relativePath: "Tutor/\(key).json", bytes: try JSONEncoder().encode(NFAITutorTranscript(contextKey: key, turns: [turn])))
    }

    private func write(_ file: NFAILearningArtifactFile, beneath root: URL) throws {
        let url = root.appendingPathComponent(file.relativePath)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try file.bytes.write(to: url)
    }

    private func minimalArchive(version: Int) -> [String: Any] {
        ["archiveVersion": version, "exportedAt": "2026-09-05T12:00:00Z", "appVersion": "test",
         "attempts": [], "attemptReflections": [], "documents": [], "sourceChunks": [], "aiGenerations": [],
         "sessionCheckpoints": [], "dailyPlans": [], "inputCalibrations": [], "progressAnnotations": [],
         "excludedPrivateAnnotationCount": 0, "adaptivePlanHistory": [], "quarantinedReports": []]
    }

    private func gradingRequest() throws -> NFAIGradeRequest {
        let base = NFAuthoredExerciseAuthority.make(id: "mean-explanation", lab: .mentalMath, style: .shortAnswer,
            prompt: "How do you calculate the arithmetic mean?", context: "Arithmetic mean", choices: [],
            correctAnswer: "Divide the sum of observations by their count.", acceptedAnswers: [],
            explanation: "The sum divided by the count gives the mean.", hint: "Start with the total.",
            decisiveStep: "Explain the calculation.", difficulty: 0.4, citationChunkIDs: [], evidenceClass: .documentPractice)
        let exercise = try NFAIExerciseFactory.shortResponse(from: base, reference: "Divide the sum of observations by their count.")
        return .init(attemptID: UUID(), runID: UUID(), exercise: exercise, response: .shortText("Add the values and divide by how many there are."))
    }

    private func nativeGenerationObject() async throws -> [String: Any] {
        let question: [String: Any] = [
            "objective": "Explain membrane water movement from the solute difference",
            "question": "Why does water move toward the side with more dissolved solute across this membrane?",
            "context": "A selectively permeable membrane separates two solutions. Only water can cross, and one solution has more dissolved solute.",
            "referenceAnswer": "Water moves toward the solution with lower water potential because dissolved solutes reduce its water potential.",
            "rubric": ["Identify the side with lower water potential from the stated solute difference.", "Explain that water moves from higher to lower water potential across the membrane."],
            "hint": "Compare the water potential on each side before choosing a direction.",
            "explanation": "The added solute reduces water potential on one side. The resulting gradient drives net movement of water toward that side.",
            "citationIDs": []
        ]
        let response = String(decoding: try JSONSerialization.data(withJSONObject: ["questions": [question]]), as: UTF8.self)
        let service = NFAILearningAuthoringService(complete: { request, _ in
            .init(requestID: request.id, text: response, providerIdentifier: "archive-fixture",
                  modelIdentifier: "archive-fixture-model", route: .local, generatedAt: Date(timeIntervalSince1970: 1_800_000_000))
        }, availability: { _ in
            .init(isAvailable: true, route: .local, status: "Available", localAvailable: true, cloudConfigured: false)
        })
        let request = NFAuthoringRequest(capability: .contextualize, lab: .scientificReasoning, field: .lifeSciences,
            customTopic: "osmosis", learningObjective: "Explain water movement across a membrane.", style: .shortAnswer,
            difficulty: 0.5, count: 1, seed: 123, aiMode: .automatic)
        let result = try await service.author(request)
        let p = result.provenance
        let generation = NFDataExportService.Generation(id: p.requestID, createdAt: p.generatedAt,
            capability: request.capability.rawValue, lab: request.lab.rawValue, field: request.field.rawValue, topic: request.customTopic,
            route: p.route.rawValue, routeReason: p.routeReason, promptVersion: p.promptVersion,
            validationVersion: p.validationVersion, modelIdentifier: p.modelIdentifier,
            sourceDocumentIDs: p.sourceDocumentIDs.map(\.uuidString), sourceChunkIDs: p.sourceChunkIDs,
            repairCount: p.repairCount, cacheKey: p.cacheKey, isFallback: p.isFallback,
            questionCount: result.questions.count, payloadExpiresAt: .distantFuture, questions: result.questions,
            routeCandidates: result.routeCandidates, validationStatus: result.validationStatus, validationNotes: result.validationNotes)
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        return try XCTUnwrap(JSONSerialization.jsonObject(with: encoder.encode(generation)) as? [String: Any])
    }
}

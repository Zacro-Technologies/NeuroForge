import Foundation
import SwiftData
import XCTest
@testable import NeuroForge

final class ProtectedPortableArchiveTests: XCTestCase {
    @MainActor
    func testActualExportOmitsProtectedEvaluatorFieldsAndRestoresOpaqueRecoveryWithoutMutatingOriginals() throws {
        let (source, container) = try makeStore()
        let originalResponse = "{ \"logicState\" : { \"_0\" : { \"violatedRuleID\":\"rule\", \"finalState\":{\"b\":\"2\",\"a\":\"1\"} } } }"
        let attempt = AttemptRecord(sessionID: UUID(), lab: .logicDebugging, itemID: "protected.fixture", prompt: "Choose a state.",
            response: originalResponse, correctAnswer: "protected-key-canary", isCorrect: true, confidence: .certain,
            evidenceClass: .assessmentHoldout, source: .baseline)
        attempt.deterministicCredit = 0.75
        attempt.errorCode = "protected-error-canary"
        attempt.assessmentDescriptorID = "verified-evaluator-reference"
        container.mainContext.insert(attempt)
        let checkpoint = SessionCheckpointRecord(sessionID: attempt.sessionID, lab: .logicDebugging, source: .baseline,
            seed: 4, currentIndex: 1, itemCount: 8, response: "learner-draft", scratchpad: "authentic notes", results: [true], credits: [0.75], evidenceClass: .assessmentHoldout)
        container.mainContext.insert(checkpoint)
        let reflection = AttemptReflectionRecord(attemptID: attempt.id, deterministicErrorCode: "protected-error-canary", selectedErrorCode: .other,
            trigger: .highConfidenceError, note: "Learner note")
        container.mainContext.insert(reflection)
        try container.mainContext.save(); source.reload()
        let files = try NFDataExportService.makeExports(from: source)
        defer { try? FileManager.default.removeItem(at: files[0].deletingLastPathComponent()) }
        let data = try Data(contentsOf: files[0])
        let text = try XCTUnwrap(String(data: data, encoding: .utf8))
        XCTAssertFalse(text.contains("protected-key-canary"))
        XCTAssertFalse(text.contains("protected-error-canary"))
        let root = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let row = try XCTUnwrap((root["attempts"] as? [[String: Any]])?.first)
        for key in ["correctAnswer", "isCorrect", "deterministicCredit", "errorCode", "evidenceWeight"] { XCTAssertNil(row[key], key) }
        XCTAssertEqual(row["response"] as? String, originalResponse)
        XCTAssertNotNil(row["protectedReceipt"])
        let saved = try XCTUnwrap((root["sessionCheckpoints"] as? [[String: Any]])?.first)
        XCTAssertNil(saved["results"]); XCTAssertNil(saved["credits"])
        XCTAssertEqual(saved["scratchpad"] as? String, "authentic notes")
        XCTAssertEqual(try NFDataExportRoundTripValidator.decodeArchive(at: files[0]).attemptIDs, [attempt.id])
        XCTAssertEqual(attempt.correctAnswerText, "protected-key-canary")
        XCTAssertTrue(attempt.isCorrect); XCTAssertEqual(attempt.deterministicCredit, 0.75)
        XCTAssertEqual(checkpoint.creditsRaw, "0.75")
        let (destination, destinationContainer) = try makeStore()
        _ = try NFDataArchiveRestoreService.restore(archiveAt: files[0], into: destination, policy: .abortOnConflict)
        let restored = try XCTUnwrap(destination.attempts.first)
        XCTAssertEqual(restored.id, attempt.id); XCTAssertEqual(restored.response, originalResponse)
        XCTAssertEqual(restored.errorCode, "protected_evaluator_unavailable")
        XCTAssertEqual(restored.evidenceWeight, 0); XCTAssertTrue(restored.correctAnswerText.isEmpty)
        XCTAssertTrue(destination.evidenceDispositions.contains {
            $0.attemptID == restored.id.uuidString && $0.disposition == .excludedContentCorrection
        }, "A portable placeholder must not appear as an incorrect historical answer")
        XCTAssertEqual(destination.sessionCheckpoints.first?.assessmentStopReasonRaw, "protected_evaluator_unavailable")
        XCTAssertEqual(destination.sessionCheckpoints.first?.scratchpad, "authentic notes")
        XCTAssertEqual(destination.attemptReflections.first?.triggerRaw, "protectedReceipt")
        _ = destinationContainer
    }

    @MainActor
    func testLegacyV14ThroughV18ProtectedPayloadsCannotReviveAnOracle() throws {
        let (source, container) = try makeStore()
        let attempt = AttemptRecord(sessionID: UUID(), lab: .mentalMath, itemID: "legacy.protected", prompt: "Compute.", response: "42",
            correctAnswer: "legacy-hidden-key", isCorrect: true, confidence: .certain, evidenceClass: .assessmentHoldout, source: .baseline)
        container.mainContext.insert(attempt); try container.mainContext.save(); source.reload()
        let files = try NFDataExportService.makeExports(from: source)
        defer { try? FileManager.default.removeItem(at: files[0].deletingLastPathComponent()) }
        let original = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: files[0])) as? [String: Any])
        for version in 14...18 {
            var object = original; object["archiveVersion"] = version
            var attempts = try XCTUnwrap(object["attempts"] as? [[String: Any]])
            attempts[0].removeValue(forKey: "protectedReceipt")
            attempts[0]["correctAnswer"] = "legacy-hidden-key"; attempts[0]["isCorrect"] = true
            attempts[0]["deterministicCredit"] = 1; attempts[0]["evidenceWeight"] = 1; attempts[0]["errorCode"] = "hidden-inference"
            object["attempts"] = attempts
            if version < 15 { object.removeValue(forKey: "attemptReflections") }
            if version < 16 { object.removeValue(forKey: "adaptivePlanHistory") }
            let url = files[0].deletingLastPathComponent().appending(path: "legacy-\(version).json")
            try JSONSerialization.data(withJSONObject: object).write(to: url)
            let (destination, destinationContainer) = try makeStore()
            let preview = try NFDataArchiveRestoreService.preview(archiveAt: url, into: destination)
            XCTAssertEqual(preview.archiveVersion, version)
            XCTAssertTrue(preview.warnings.contains { $0.contains("verified evaluator") })
            _ = try NFDataArchiveRestoreService.restore(archiveAt: url, into: destination, policy: .abortOnConflict)
            let restored = try XCTUnwrap(destination.attempts.first)
            XCTAssertEqual(restored.response, "42"); XCTAssertEqual(restored.evidenceWeight, 0)
            XCTAssertEqual(restored.errorCode, "protected_evaluator_unavailable"); XCTAssertTrue(restored.correctAnswerText.isEmpty)
            _ = destinationContainer
        }
    }

    @MainActor
    func testNestedProtectedCheckpointsAndReportsCannotCarryEvaluatorCanaries() throws {
        let canary: [String: Any] = ["expectedAnswerSummary": "nested-key-canary", "isCorrect": true, "credit": 1, "decisiveStep": "nested-step-canary"]
        let object: [String: Any] = ["attempts": [], "sessionCheckpoints": [], "attemptReflections": [],
            "quarantinedReports": [["id": "report", "assessmentDescriptorID": "descriptor", "authoredDiagnostic": canary, "diagnosticDigest": "key-digest"]],
            "localLearning": ["sessions": [["id": "run", "request": ["source": "baseline", "resumedResults": [true], "resumedCredits": [1], "localCheckpoint": canary, "presentationEnhancements": ["item": canary]],
                "checkpoint": ["descriptor": ["role": "baseline"], "exercise": ["assessmentProtected": true, "rubric": canary], "result": canary, "correctness": [true], "credits": [1], "scratchpad": "drawing-bytes-retained", "response": ["shortText": ["_0": "my answer"]]]]]]]
        let safe = try NFDataExportService.protectedPortableData(JSONSerialization.data(withJSONObject: object))
        let text = try XCTUnwrap(String(data: safe, encoding: .utf8))
        for fragment in ["nested-key-canary", "nested-step-canary", "expectedAnswerSummary", "isCorrect", "decisiveStep", "key-digest"] { XCTAssertFalse(text.contains(fragment), fragment) }
        XCTAssertTrue(text.contains("drawing-bytes-retained")); XCTAssertTrue(text.contains("my answer"))
        XCTAssertTrue(text.contains("migrationRecovery"))
    }

    @MainActor
    func testOpaquePrivatePayloadsAreRejectedOrCanonicalizedBeforePortableExport() throws {
        let repository = NFLocalSessionRepository()
        let raw = Data("{\"unknownEvaluator\":{\"assessmentProtected\":true,\"correctAnswer\":\"base64-key-canary\"}}".utf8)
        let id = UUID(), generation = UUID()
        // Simulate a pre-correction local opaque record: retain its original
        // bytes locally, but never copy them into a portable archive.
        try repository.savePrivateStudyRun(id: id, generationID: generation, payload: raw)
        let exported = repository.exportArchive
        XCTAssertEqual(exported.privateStudyRuns?.count, 0)
        XCTAssertEqual(exported.unavailablePrivateRunIDs, [id])
        XCTAssertEqual(repository.archive.privateStudyRuns?.first?.payload, raw)
        var incoming = NFLocalSessionRepository.Archive()
        incoming.privateStudyRuns = [.init(id: id, generationID: generation, payload: raw, updatedAt: Date())]
        XCTAssertThrowsError(try NFLocalSessionRepository().importArchive(incoming))
        let metadata = Data("{\"schemaVersion\":1,\"annotations\":[],\"collections\":[],\"favoriteActivities\":[],\"recentActivityIDs\":[],\"unknownEvaluator\":{\"correctAnswer\":\"base64-key-canary\"}}".utf8)
        let known = NFLocalPrivateStudyRun(id: NFPrivateStudyMetadata.recordID, generationID: NFPrivateStudyMetadata.recordID, payload: metadata, updatedAt: Date())
        let canonical = try repository.canonicalPrivateStudyPayload(known)
        XCTAssertFalse(String(decoding: canonical, as: UTF8.self).contains("base64-key-canary"))
        XCTAssertEqual(try JSONDecoder().decode(NFPrivateStudyMetadata.self, from: canonical).schemaVersion, 1)
    }

    @MainActor
    func testMixedCommittedMarkersRemoveEvaluatorGraphAndCorrectionsButKeepUnrelatedRunAndConsumedPositions() throws {
        for unavailableMarker in [false, true] {
            let fixture = try makeMixedFixture()
            let source = fixture.store
            let originalAnswer = fixture.attempt.correctAnswerText
            let originalScore = fixture.attempt.deterministicCredit
            var marked = source.localSessions.archive
            if unavailableMarker {
                marked.snapshots.removeAll { $0.attemptID == fixture.attempt.id }
                marked.unavailableHistorySnapshots = [.init(attemptID: fixture.attempt.id,
                    digest: try NFLocalItemCheckpoint.digest(fixture.protectedExercise), reason: .protectedContent)]
            } else { marked.withheldProtectedConflictAttemptIDs = [fixture.attempt.id] }
            marked.contentCorrections = [.init(originalAttemptID: fixture.attempt.id.uuidString,
                ruleID: "protected-correction", policyVersion: "fixture.v1", disposition: .excludedInvalidItem,
                originalResultDigest: String(repeating: "a", count: 64), correctedCredit: 0.75,
                correctedScorerVersion: 8, correctedContractVersion: "protected-correction-contract-canary",
                excludedScopes: [.accuracy], rationale: "protected-correction-key-canary", idempotencyKey: "protected-correction-id")]
            marked.activeContentCorrectionIDs = [fixture.attempt.id.uuidString: ["protected-correction-id"]]
            try source.localSessions.restorePredecessor(marked)
            let predecessor = source.localSessions.archive
            let local = source.localSessions.exportArchive
            let safeLedger = try XCTUnwrap(local.selectionLedger)
            XCTAssertNil(safeLedger.runs[fixture.protectedRun.uuidString])
            XCTAssertNotNil(safeLedger.runs[fixture.ordinaryRun.uuidString])
            XCTAssertEqual(safeLedger.scopes, predecessor.selectionLedger?.scopes)
            XCTAssertTrue(safeLedger.slots.values.allSatisfy { $0.runID != fixture.protectedRun.uuidString })
            XCTAssertTrue(safeLedger.decisions.values.allSatisfy { $0.command.runID != fixture.protectedRun.uuidString })
            XCTAssertTrue(safeLedger.exposures.values.allSatisfy { $0.runID != fixture.protectedRun.uuidString })
            XCTAssertTrue(safeLedger.outcomes.values.allSatisfy { $0.runID != fixture.protectedRun.uuidString })
            XCTAssertFalse(local.retiredOrdinaryDrafts?.values.contains { $0.sessionID == fixture.protectedRun } == true)
            XCTAssertFalse(local.snapshots.contains { $0.attemptID == fixture.attempt.id })
            let protectedRun = try XCTUnwrap(local.sessions.first { $0.id == fixture.protectedRun })
            XCTAssertNil(protectedRun.checkpoint.exercise); XCTAssertNil(protectedRun.checkpoint.result)
            XCTAssertTrue(protectedRun.checkpoint.correctness.isEmpty); XCTAssertTrue(protectedRun.checkpoint.credits.isEmpty)
            XCTAssertEqual(protectedRun.status, .migrationRecovery)
            XCTAssertEqual(protectedRun.checkpoint.response, predecessor.sessions.first { $0.id == fixture.protectedRun }?.checkpoint.response)
            XCTAssertEqual(local.sessions.first { $0.id == fixture.ordinaryRun }?.checkpoint.exercise, fixture.ordinaryExercise)
            XCTAssertTrue(local.contentCorrections?.isEmpty == true)
            XCTAssertNil(local.activeContentCorrectionIDs?[fixture.attempt.id.uuidString])

            let exports = try NFDataExportService.makeExports(from: source)
            defer { try? FileManager.default.removeItem(at: exports[0].deletingLastPathComponent()) }
            let data = try Data(contentsOf: exports[0])
            let root = try JSONSerialization.jsonObject(with: data)
            XCTAssertFalse(containsEvaluator(root, exerciseID: fixture.protectedExercise.id))
            XCTAssertTrue(containsEvaluator(root, exerciseID: fixture.ordinaryExercise.id))
            XCTAssertFalse(String(decoding: data, as: UTF8.self).contains("protected-correction-key-canary"))
            XCTAssertFalse(String(decoding: data, as: UTF8.self).contains("protected-correction-contract-canary"))
            let (destination, destinationContainer) = try makeStore()
            _ = try NFDataArchiveRestoreService.restore(archiveAt: exports[0], into: destination, policy: .abortOnConflict)
            let restored = try XCTUnwrap(destination.attempts.first { $0.id == fixture.attempt.id })
            XCTAssertEqual(restored.response, fixture.attempt.response)
            XCTAssertEqual(restored.errorCode, "protected_evaluator_unavailable")
            XCTAssertTrue(restored.correctAnswerText.isEmpty); XCTAssertEqual(restored.evidenceWeight, 0)
            XCTAssertEqual(destination.localSessions.archive.sessions.first { $0.id == fixture.protectedRun }?.status, .migrationRecovery)
            XCTAssertNil(destination.localSessions.archive.sessions.first { $0.id == fixture.protectedRun }?.checkpoint.exercise)
            XCTAssertEqual(destination.localSessions.archive.sessions.first { $0.id == fixture.ordinaryRun }?.checkpoint.exercise, fixture.ordinaryExercise)
            XCTAssertEqual(destination.localSessions.archive.selectionLedger?.scopes, safeLedger.scopes)
            XCTAssertEqual(source.localSessions.archive.selectionLedger, predecessor.selectionLedger)
            XCTAssertEqual(source.localSessions.archive.sessions.first { $0.id == fixture.protectedRun }?.checkpoint,
                predecessor.sessions.first { $0.id == fixture.protectedRun }?.checkpoint)
            XCTAssertEqual(source.localSessions.archive.contentCorrections, predecessor.contentCorrections)
            XCTAssertEqual(fixture.attempt.correctAnswerText, originalAnswer)
            XCTAssertEqual(fixture.attempt.deterministicCredit, originalScore)
            _ = fixture.container; _ = destinationContainer
        }
    }

    @MainActor
    func testRawPortableBoundaryRemovesSharedSnapshotAliasesAndRestoresOnlyOpaqueProtectedRuns() throws {
        let fixture = try makeMixedFixture()
        let exports = try NFDataExportService.makeExports(from: fixture.store)
        defer { try? FileManager.default.removeItem(at: exports[0].deletingLastPathComponent()) }
        var root = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: exports[0])) as? [String: Any])
        var local = try XCTUnwrap(root["localLearning"] as? [String: Any])
        local["withheldProtectedConflictAttemptIDs"] = [fixture.attempt.id.uuidString.lowercased()]
        var ledger = try XCTUnwrap(local["selectionLedger"] as? [String: Any])
        var snapshots = try XCTUnwrap(ledger["snapshots"] as? [String: [String: Any]])
        var slots = try XCTUnwrap(ledger["slots"] as? [String: [String: Any]])
        let firstSlot = try XCTUnwrap(slots.values.first { ($0["attemptID"] as? String)?.lowercased() == fixture.attempt.id.uuidString.lowercased() })
        let firstSnapshot = try XCTUnwrap(snapshots.values.first { $0["digest"] as? String == firstSlot["snapshotDigest"] as? String })
        let secondKey = try XCTUnwrap(slots.first { $0.value["runID"] as? String == fixture.ordinaryRun.uuidString }?.key)
        let secondSlot = try XCTUnwrap(slots[secondKey])
        let snapshotKey = try XCTUnwrap(snapshots.first { $0.value["digest"] as? String == secondSlot["snapshotDigest"] as? String }?.key)
        // An external archive can relabel identical private bytes under another
        // snapshot/slot identity. Restrictions must follow the payload too.
        snapshots[snapshotKey]?["payload"] = firstSnapshot["payload"]
        snapshots[snapshotKey]?["digest"] = firstSnapshot["digest"]
        slots[secondKey]?["snapshotDigest"] = firstSnapshot["digest"]
        snapshots["unreferenced-protected-alias"] = firstSnapshot
        ledger["snapshots"] = snapshots; ledger["slots"] = slots
        local["selectionLedger"] = ledger; root["localLearning"] = local
        let safe = try NFDataExportService.protectedPortableData(JSONSerialization.data(withJSONObject: root))
        let object = try JSONSerialization.jsonObject(with: safe)
        XCTAssertFalse(containsEvaluator(object, exerciseID: fixture.protectedExercise.id))
        XCTAssertFalse(containsEvaluator(object, exerciseID: fixture.ordinaryExercise.id))
        let safeRoot = try XCTUnwrap(object as? [String: Any])
        let safeLocal = try XCTUnwrap(safeRoot["localLearning"] as? [String: Any])
        let safeLedger = try XCTUnwrap(safeLocal["selectionLedger"] as? [String: Any])
        for key in ["runs", "slots", "decisions", "outcomes", "exposures", "snapshots"] {
            XCTAssertTrue((safeLedger[key] as? [String: Any])?.isEmpty == true, key)
        }
        XCTAssertFalse((safeLedger["scopes"] as? [String: Any])?.isEmpty == true)
        let url = exports[0].deletingLastPathComponent().appendingPathComponent("shared-protected-alias.json")
        try safe.write(to: url)
        let (destination, container) = try makeStore()
        _ = try NFDataArchiveRestoreService.restore(archiveAt: url, into: destination, policy: .abortOnConflict)
        XCTAssertEqual(destination.localSessions.archive.sessions.count, 2)
        XCTAssertTrue(destination.localSessions.archive.sessions.allSatisfy { $0.status == .migrationRecovery && $0.checkpoint.exercise == nil && $0.checkpoint.result == nil })
        XCTAssertEqual(fixture.store.localSessions.archive.selectionLedger?.runs.count, 2)
        _ = fixture.container; _ = container
    }

    @MainActor
    func testFutureAndMalformedLedgerPayloadsCannotBypassRawProtectionWithBase64() throws {
        let fixture = try makeMixedFixture()
        let exports = try NFDataExportService.makeExports(from: fixture.store)
        defer { try? FileManager.default.removeItem(at: exports[0].deletingLastPathComponent()) }
        let original = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: exports[0])) as? [String: Any])
        for variant in 0..<3 {
            var root = original
            var local = try XCTUnwrap(root["localLearning"] as? [String: Any])
            var ledger = try XCTUnwrap(local["selectionLedger"] as? [String: Any])
            var snapshots = try XCTUnwrap(ledger["snapshots"] as? [String: [String: Any]])
            let key = try XCTUnwrap(snapshots.keys.first)
            let canary = Data("{\"futureEvaluator\":\"base64-protected-evaluator-canary\",\"assessmentProtected\":true}".utf8)
            if variant == 0 {
                ledger["schemaVersion"] = 999
                snapshots[key]?["futureOpaqueEvaluator"] = canary.base64EncodedString()
            } else if variant == 1 {
                snapshots[key]?["payload"] = "not-valid-base64!?"
                snapshots[key]?["futureOpaqueEvaluator"] = canary.base64EncodedString()
            } else {
                snapshots[key]?["payload"] = canary.base64EncodedString()
                snapshots[key]?["digest"] = NFReservationSnapshot.digest(canary)
            }
            ledger["snapshots"] = snapshots; local["selectionLedger"] = ledger
            root["localLearning"] = local
            let safe = try NFDataExportService.protectedPortableData(JSONSerialization.data(withJSONObject: root))
            let object = try JSONSerialization.jsonObject(with: safe)
            XCTAssertFalse(recursiveStrings(object).contains { $0.contains("base64-protected-evaluator-canary") })
            let safeRoot = try XCTUnwrap(object as? [String: Any])
            let safeLocal = try XCTUnwrap(safeRoot["localLearning"] as? [String: Any])
            let ledgerObject = safeLocal["selectionLedger"] as? [String: Any]
            XCTAssertFalse(String(describing: ledgerObject).contains("futureOpaqueEvaluator"))
        }
        _ = fixture.container
    }

    @MainActor
    func testProtectedItemIdentityCannotReappearThroughSavedGeneratedOrPrivateDraftExports() throws {
        let fixture = try makeMixedFixture(), source = fixture.store
        let request = NFAuthoringRequest(id: UUID(), capability: .contextualize, lab: .mentalMath,
            field: .general, customTopic: "Portable alias fixture", learningObjective: "Preserve a saved reference",
            style: .shortAnswer, difficulty: 0.3, count: 1, localeIdentifier: "en", seed: 929, aiMode: .disabled)
        // A supported saved personal set may reuse an older item identity while
        // retaining the same reference answer. Its ordinary label is no escape
        // from a protection marker subsequently attached to that item identity.
        let question = NFAuthoredQuestion(id: fixture.protectedExercise.id, lab: .mentalMath, style: .shortAnswer,
            prompt: fixture.protectedExercise.prompt, context: "Portable alias fixture", choices: [],
            correctAnswer: fixture.attempt.correctAnswerText, acceptedAnswers: [fixture.attempt.correctAnswerText],
            explanation: "protected-alias-explanation-canary", hint: "protected-alias-hint-canary",
            decisiveStep: "protected-alias-step-canary", difficulty: 0.3, citationChunkIDs: [], evidenceClass: .documentPractice)
        XCTAssertTrue(NFAuthoredExerciseAuthority.validatesBinding(question))
        let result = NFAuthoringResult(questions: [question], provenance: .init(requestID: request.id,
            generatedAt: Date(), route: .deterministicFallback, routeReason: "Portable alias fixture",
            promptVersion: NFAuthoringRequest.promptVersion, modelIdentifier: "portable.alias.fixture",
            sourceChunkIDs: [], sourceDocumentIDs: [], validationVersion: NFAuthoringEngine.validationVersion,
            repairCount: 0, cacheKey: "portable.alias.fixture", isFallback: true), routeCandidates: [],
            validationStatus: .init(level: .deterministicKey, sourceSupport: .notApplicable), validationNotes: [])
        let record = try AIGenerationRecord(request: request, result: result)
        fixture.container.mainContext.insert(record); try fixture.container.mainContext.save(); source.reload()
        XCTAssertNotNil(record.recoverableResult())
        try source.localSessions.saveSet(result, at: Date())
        let draft = NFGeneratedPracticeDraft(id: UUID(), ownerDeviceID: source.localSessions.ownerDeviceID,
            result: result, request: request, index: 0, stage: 0,
            response: .selfCheck(.init(rating: .notYet, reflection: "Learner's original draft")), confidence: nil,
            referenceRevealed: false, hintRevealed: false, correctness: [], lastScore: nil, pendingAttemptID: nil,
            shownAt: Date(), activeDuration: 0)
        XCTAssertTrue(draft.valid)
        let originalPayload = try JSONEncoder().encode(draft)
        try source.localSessions.savePrivateStudyRun(id: draft.id, generationID: request.id, payload: originalPayload)
        var marked = source.localSessions.archive
        marked.withheldProtectedConflictAttemptIDs = [fixture.attempt.id]
        try source.localSessions.restorePredecessor(marked)
        let exported = source.localSessions.exportArchive
        XCTAssertFalse(exported.savedSets?.contains { $0.id == request.id } == true)
        XCTAssertFalse(exported.privateStudyRuns?.contains { $0.id == draft.id } == true)
        XCTAssertTrue(exported.unavailablePrivateRunIDs?.contains(draft.id) == true)
        let files = try NFDataExportService.makeExports(from: source)
        defer { try? FileManager.default.removeItem(at: files[0].deletingLastPathComponent()) }
        for file in files {
            let data = try Data(contentsOf: file)
            let strings: [String]
            if let object = try? JSONSerialization.jsonObject(with: data) {
                strings = recursiveStrings(object)
                XCTAssertFalse(containsEvaluator(object, exerciseID: fixture.protectedExercise.id), file.lastPathComponent)
            } else { strings = [String(decoding: data, as: UTF8.self)] }
            for canary in ["protected-alias-explanation-canary", "protected-alias-hint-canary", "protected-alias-step-canary"] {
                XCTAssertFalse(strings.contains { $0.contains(canary) }, file.lastPathComponent + ": " + canary)
            }
        }
        let (destination, container) = try makeStore()
        _ = try NFDataArchiveRestoreService.restore(archiveAt: files[0], into: destination, policy: .abortOnConflict)
        XCTAssertTrue(destination.localSessions.archive.unavailablePrivateRunIDs?.contains(draft.id) == true)
        XCTAssertFalse(destination.localSessions.archive.savedSets?.contains { $0.id == request.id } == true)
        XCTAssertEqual(source.localSessions.archive.privateStudyRuns?.first { $0.id == draft.id }?.payload, originalPayload)
        XCTAssertEqual(source.localSessions.archive.savedSets?.first { $0.id == request.id }?.result.questions, [question])
        XCTAssertEqual(record.recoverableResult()?.questions, [question])
        _ = container
    }

    @MainActor
    private struct MixedFixture {
        let store: AppStore
        let container: ModelContainer
        let attempt: AttemptRecord
        let protectedRun: UUID
        let protectedExercise: NFExercise
        let ordinaryRun: UUID
        let ordinaryExercise: NFExercise
    }

    @MainActor
    private func makeMixedFixture() throws -> MixedFixture {
        let (store, container) = try makeStore()
        XCTAssertTrue(store.beginSession(lab: .mentalMath, source: .focused, requestedItemCount: 2,
            seedOverride: 917, launchLocaleIdentifier: "en"))
        let request = try XCTUnwrap(store.activeSessionRequest)
        let runtime = NFUniversalSessionRuntime(request: request)
        XCTAssertTrue(runtime.checkpointDraft(store: store)); runtime.acknowledgePresented()
        runtime.replaceCurrentItem(store: store)
        XCTAssertNil(runtime.saveError); runtime.acknowledgePresented()
        let exercise = runtime.exercise
        fillResponse(runtime)
        runtime.submitInline(store: store)
        XCTAssertEqual(runtime.stage, .feedback)
        XCTAssertNil(runtime.saveError)
        let attempt = try XCTUnwrap(store.attempts.first { $0.sessionID == request.id })
        XCTAssertTrue(runtime.prepareToClose(store: store).permitsClose)
        runtime.finishClosing(); store.activeSessionRequest = nil
        XCTAssertTrue(store.beginSession(lab: .mentalMath, source: .focused, requestedItemCount: 2,
            seedOverride: 919, launchLocaleIdentifier: "en"))
        let ordinary = try XCTUnwrap(store.activeSessionRequest)
        let second = NFUniversalSessionRuntime(request: ordinary)
        XCTAssertTrue(second.checkpointDraft(store: store)); second.acknowledgePresented()
        let ordinaryExercise = second.exercise
        XCTAssertNotEqual(ordinaryExercise.id, exercise.id)
        XCTAssertTrue(second.prepareToClose(store: store).permitsClose)
        second.finishClosing(); store.activeSessionRequest = nil
        return .init(store: store, container: container, attempt: attempt, protectedRun: request.id,
            protectedExercise: exercise, ordinaryRun: ordinary.id, ordinaryExercise: ordinaryExercise)
    }

    @MainActor
    private func fillResponse(_ runtime: NFUniversalSessionRuntime) {
        switch runtime.exercise.interaction {
        case let .numeric(schema): runtime.numericValue = String(schema.answer.value); runtime.numericUnit = schema.answer.canonicalUnit ?? ""
        case let .singleChoice(schema): runtime.singleChoiceID = schema.correctOptionID
        case let .multipleChoice(schema): runtime.multipleChoiceIDs = Set(schema.correctOptionIDs)
        case let .orderedSteps(schema): runtime.orderedStepIDs = schema.correctOrder
        case let .shortText(schema): runtime.shortText = schema.expectedAnswer
        case let .claimEvidence(schema): runtime.claimSelections = Dictionary(uniqueKeysWithValues: schema.correctPairs.map { ($0.claimID, Set($0.evidenceIDs)) })
        case let .logicState(schema): runtime.logicState = schema.expectedFinalState; runtime.violatedRuleID = schema.expectedViolatedRuleID
        case .selfCheck: XCTFail("Mixed built-in fixture must be scored practice")
        }
        runtime.chooseConfidence(.certain)
    }

    private func containsEvaluator(_ value: Any, exerciseID: String, depth: Int = 0) -> Bool {
        guard depth < 20 else { return false }
        if let row = value as? [String: Any] {
            if row["id"] as? String == exerciseID, row["interaction"] != nil { return true }
            if row["exerciseID"] as? String == exerciseID, row["expectedAnswerSummary"] != nil { return true }
            return row.values.contains { containsEvaluator($0, exerciseID: exerciseID, depth: depth + 1) }
        }
        if let array = value as? [Any] { return array.contains { containsEvaluator($0, exerciseID: exerciseID, depth: depth + 1) } }
        if let text = value as? String, text.utf8.count <= 8 * 1_024 * 1_024,
           let data = Data(base64Encoded: text), let decoded = try? JSONSerialization.jsonObject(with: data) {
            return containsEvaluator(decoded, exerciseID: exerciseID, depth: depth + 1)
        }
        return false
    }

    private func recursiveStrings(_ value: Any, depth: Int = 0) -> [String] {
        guard depth < 20 else { return [] }
        if let row = value as? [String: Any] { return row.values.flatMap { recursiveStrings($0, depth: depth + 1) } }
        if let array = value as? [Any] { return array.flatMap { recursiveStrings($0, depth: depth + 1) } }
        guard let text = value as? String else { return [] }
        if text.utf8.count <= 8 * 1_024 * 1_024, let data = Data(base64Encoded: text),
           let decoded = try? JSONSerialization.jsonObject(with: data) {
            return [text] + recursiveStrings(decoded, depth: depth + 1)
        }
        return [text]
    }

    @MainActor
    private func makeStore() throws -> (AppStore, ModelContainer) {
        let schema = Schema([UserProfileRecord.self, InputCalibrationRecord.self, ProgressAnnotationRecord.self, AttemptRecord.self,
            AttemptReflectionRecord.self, SourceDocumentRecord.self, SourceChunkRecord.self, AIGenerationRecord.self,
            WeeklyTransferStateRecord.self, ReassessmentStateRecord.self, SessionCheckpointRecord.self, DailyPlanRecord.self, ItemReportRecord.self])
        let container = try ModelContainer(for: schema, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        return (AppStore(context: container.mainContext, adaptivePlanHistoryRepository: NFAdaptivePlanHistoryRepository(fileURL:
            FileManager.default.temporaryDirectory.appending(path: "NF-Protected-Export-\(UUID().uuidString).json"))), container)
    }
}

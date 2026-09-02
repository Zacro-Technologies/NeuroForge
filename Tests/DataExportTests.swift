import Foundation
import SwiftData
import XCTest

@testable import NeuroForge

final class DataExportTests: XCTestCase {
    @MainActor
    func testGeneratedQuestionsAndPersonalReviewArtifactsMatchVersionedSchemas() throws {
        let (store, container) = try makeStore()
        defer { _ = container }

        let generationID = UUID(uuidString: "5E4E3A4B-2C7D-4854-B16D-0E5AB6393A20")!
        let answeredReviewID = UUID(uuidString: "4A60D9F7-5438-4CF6-B226-C271FBAD58AC")!
        let skippedReviewID = UUID(uuidString: "54B5FAE9-475C-4184-8C1E-018B46AAC518")!
        let documentID = UUID(uuidString: "E699674D-C6F0-4A6E-A15D-89298219AEF0")!
        let chunkID = "chunk.stable.reference"
        let generatedAt = Date().addingTimeInterval(-60)
        let prompt = "Prompt, with \"quoted text\"\nand another line\rreturn"
        let response = "Response, with \"evidence\"\nand a second line\rreturn"
        let reference = "Reference, \"exact\""
        let chunk = NFSourceChunk(
            id: chunkID,
            documentID: documentID,
            documentVersion: 1,
            sourceName: "study-notes.md",
            locator: NFSourceLocator(page: nil, lineStart: 12, lineEnd: 14, section: "Methods"),
            text: "A controlled comparison isolates the intervention from a competing explanation.",
            contentHash: "content-hash",
            ordinal: 0,
            characterStart: 240,
            characterEnd: 326,
            nearbyHeading: "Methods",
            language: "markdown",
            contentTypeTags: ["markdown", "prose", "section"]
        )
        store.context.insert(SourceChunkRecord(chunk: chunk))
        try store.context.save()
        store.reload()
        let request = NFAuthoringRequest(
            id: generationID,
            capability: .sourceGroundedPractice,
            lab: .scientificReasoning,
            field: .dataScience,
            customTopic: "controlled comparison",
            learningObjective: "identify the supported inference",
            style: .shortAnswer,
            difficulty: 0.6,
            count: 1,
            seed: 73,
            sourceChunks: [chunk],
            documentPolicies: [.onDeviceOnly],
            aiMode: .disabled
        )
        let question = NFAuthoredQuestion(
            id: "question.stable",
            lab: .scientificReasoning,
            style: .shortAnswer,
            prompt: prompt,
            context: "Use only the cited personal material.",
            choices: [],
            correctAnswer: reference,
            acceptedAnswers: [reference],
            explanation: "The reference follows the controlled comparison.",
            hint: "Separate the intervention from the competing explanation.",
            decisiveStep: "Use the cited control.",
            difficulty: 0.6,
            citationChunkIDs: [chunkID],
            evidenceClass: .documentPractice
        )
        let result = NFAuthoringResult(
            questions: [question],
            provenance: NFAIGenerationProvenance(
                requestID: generationID,
                generatedAt: generatedAt,
                route: .deterministicFallback,
                routeReason: "On-device policy, with \"fallback\"\nvalidation",
                promptVersion: NFAuthoringRequest.promptVersion,
                modelIdentifier: "neuroforge-deterministic-v1",
                sourceChunkIDs: [chunkID],
                sourceDocumentIDs: [documentID],
                validationVersion: NFAuthoringEngine.validationVersion,
                repairCount: 1,
                cacheKey: "stable-cache-key",
                isFallback: true
            ),
            routeCandidates: [
                NFAIRouteSnapshot(route: .deterministicFallback, state: .fallback, reason: "Policy fallback")
            ],
            validationStatus: NFAuthoringValidationStatus(
                level: .deterministicKey,
                sourceSupport: .deterministicSourceTransformation
            ),
            validationNotes: ["Citation and response schema validated."]
        )
        try store.saveAIGeneration(request: request, result: result)
        try store.saveItemReport(
            question: question,
            result: result,
            reason: "Reference answer needs review",
            note: "The cited control may support a narrower conclusion."
        )
        try store.saveAuthoredAttempt(
            generationID: generationID,
            question: question,
            response: response,
            isCorrect: true,
            confidence: .certain,
            sourceDocumentIDs: [documentID]
        )
        let answered = try XCTUnwrap(store.attempts.first)
        answered.id = answeredReviewID
        answered.shownAt = generatedAt.addingTimeInterval(5)
        answered.submittedAt = generatedAt.addingTimeInterval(25)

        let skipped = AttemptRecord(
            sessionID: generationID,
            lab: .scientificReasoning,
            itemID: "question.skipped",
            prompt: "Skipped prompt",
            response: "",
            correctAnswer: "Not evaluated",
            isCorrect: false,
            confidence: .guessing,
            evidenceClass: .documentPractice,
            source: .focused,
            sourceDocumentIDs: [documentID],
            sourceChunkIDs: [chunkID],
            responseFormat: NFQuestionStyle.shortAnswer.rawValue
        )
        skipped.id = skippedReviewID
        skipped.generationID = generationID
        skipped.wasSkipped = true
        skipped.confidenceRaw = nil
        skipped.evidenceWeight = 0
        skipped.deterministicCredit = 0
        skipped.validationVersion = NFAuthoringEngine.validationVersion
        skipped.shownAt = generatedAt.addingTimeInterval(30)
        skipped.submittedAt = generatedAt.addingTimeInterval(35)
        store.context.insert(skipped)

        let ordinary = AttemptRecord(
            sessionID: UUID(),
            lab: .mentalMath,
            itemID: "ordinary-practice",
            prompt: "2 + 2",
            response: "3",
            correctAnswer: "4",
            isCorrect: false,
            confidence: .certain
        )
        ordinary.id = UUID(uuidString: "48BC9515-164E-49AE-B9A1-218C981A51EE")!
        store.context.insert(ordinary)
        try store.context.save()
        store.reload()
        try store.saveAttemptReflection(
            attemptID: ordinary.id,
            deterministicErrorCode: ordinary.errorCode,
            selectedErrorCode: .inputError,
            trigger: .highConfidenceError,
            note: "I tapped the neighboring key."
        )

        let exportURLs = try NFDataExportService.makeExports(from: store)
        defer { removeExportFolder(for: exportURLs) }
        XCTAssertEqual(exportURLs.count, 4)

        let generatedURL = try XCTUnwrap(exportURLs.first {
            $0.lastPathComponent == "NeuroForge-Generated-Questions-v1.json"
        })
        let generatedObject = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(contentsOf: generatedURL)) as? [String: Any]
        )
        XCTAssertEqual(
            (generatedObject["schemaVersion"] as? NSNumber)?.intValue,
            NFDataExportService.generatedQuestionsSchemaVersion
        )
        XCTAssertEqual(generatedObject["artifact"] as? String, "com.zacrotech.neuroforge.generated-questions")
        let schema = try XCTUnwrap(generatedObject["schema"] as? [String: Any])
        XCTAssertFalse((schema["contract"] as? String ?? "").isEmpty)
        XCTAssertEqual(schema["timestampEncoding"] as? String, "RFC 3339 / ISO 8601 UTC timestamp")

        let generations = try XCTUnwrap(generatedObject["generations"] as? [[String: Any]])
        let generation = try XCTUnwrap(generations.first)
        XCTAssertEqual(generation["generationID"] as? String, generationID.uuidString.uppercased())
        XCTAssertEqual(generation["payloadState"] as? String, "available")
        XCTAssertEqual((generation["recordedQuestionCount"] as? NSNumber)?.intValue, 1)
        XCTAssertEqual((generation["exportedQuestionCount"] as? NSNumber)?.intValue, 1)
        XCTAssertEqual(generation["sourceDocumentIDs"] as? [String], [documentID.uuidString])
        XCTAssertEqual(generation["sourceChunkIDs"] as? [String], [chunkID])

        let documentedGenerationFields = Set(schema["requiredGenerationFields"] as? [String] ?? [])
        XCTAssertTrue(documentedGenerationFields.isSubset(of: Set(generation.keys)))
        let questions = try XCTUnwrap(generation["questions"] as? [[String: Any]])
        let exportedQuestion = try XCTUnwrap(questions.first)
        XCTAssertEqual(
            exportedQuestion["stableQuestionID"] as? String,
            "\(generationID.uuidString.lowercased()):\(question.id)"
        )
        XCTAssertEqual(exportedQuestion["prompt"] as? String, prompt)
        XCTAssertEqual(exportedQuestion["correctAnswer"] as? String, reference)
        XCTAssertEqual(exportedQuestion["citationChunkIDs"] as? [String], [chunkID])
        let documentedQuestionFields = Set(schema["requiredQuestionFields"] as? [String] ?? [])
        XCTAssertTrue(documentedQuestionFields.isSubset(of: Set(exportedQuestion.keys)))

        let historyURL = try XCTUnwrap(exportURLs.first {
            $0.lastPathComponent == "NeuroForge-Document-AI-Review-History-v1.csv"
        })
        let rows = try parseCSV(String(contentsOf: historyURL, encoding: .utf8))
        XCTAssertEqual(rows.count, 3)
        let header = rows[0]
        let answerRow = try rowDictionary(header: header, values: rows[1...].first {
            $0[safe: header.firstIndex(of: "review_id")] == answeredReviewID.uuidString.lowercased()
        })
        XCTAssertEqual(answerRow["schema_version"], String(NFDataExportService.reviewHistorySchemaVersion))
        XCTAssertEqual(answerRow["generation_id"], generationID.uuidString.lowercased())
        XCTAssertEqual(answerRow["field"], STEMField.dataScience.rawValue)
        XCTAssertEqual(answerRow["lab"], TrainingLab.scientificReasoning.rawValue)
        XCTAssertEqual(answerRow["prompt"], prompt)
        XCTAssertEqual(answerRow["response"], response)
        XCTAssertEqual(answerRow["reference_answer"], reference)
        XCTAssertEqual(answerRow["confidence"], ConfidenceLevel.certain.rawValue)
        XCTAssertEqual(answerRow["review_outcome"], "evaluated_personal_review_no_standardized_evidence")
        XCTAssertEqual(answerRow["is_correct"], "true")
        XCTAssertEqual(answerRow["deterministic_credit"], "1.0")
        XCTAssertEqual(answerRow["evidence_weight"], "0.0")
        XCTAssertEqual(answerRow["counts_as_standardized_evidence"], "false")
        XCTAssertEqual(answerRow["source_document_ids"], "[\"\(documentID.uuidString)\"]")
        XCTAssertEqual(answerRow["source_chunk_ids"], "[\"\(chunkID)\"]")
        XCTAssertEqual(answerRow["generation_route"], NFAIRoute.deterministicFallback.rawValue)
        XCTAssertEqual(answerRow["generation_model_identifier"], "neuroforge-deterministic-v1")
        XCTAssertEqual(answerRow["generation_cache_key"], "stable-cache-key")

        let skipRow = try rowDictionary(header: header, values: rows[1...].first {
            $0[safe: header.firstIndex(of: "review_id")] == skippedReviewID.uuidString.lowercased()
        })
        XCTAssertEqual(skipRow["review_outcome"], "skipped_no_evidence")
        XCTAssertEqual(skipRow["response"], "")
        XCTAssertEqual(skipRow["reference_answer"], "")
        XCTAssertEqual(skipRow["confidence"], "")
        XCTAssertEqual(skipRow["is_correct"], "")
        XCTAssertEqual(skipRow["deterministic_credit"], "")
        XCTAssertEqual(skipRow["evidence_weight"], "0.0")
        XCTAssertEqual(skipRow["counts_as_standardized_evidence"], "false")
        XCTAssertFalse(rows.dropFirst().contains { row in
            row[safe: header.firstIndex(of: "review_id")] == ordinary.id.uuidString.lowercased()
        })

        let purged = try store.purgeExpiredAIGenerationPayloads(
            at: generatedAt.addingTimeInterval(AIGenerationRecord.defaultPayloadTTL + 1)
        )
        XCTAssertEqual(purged, 1)
        XCTAssertNil(store.recoverAIGeneration(id: generationID))

        let postExpiryURLs = try NFDataExportService.makeExports(from: store)
        defer { removeExportFolder(for: postExpiryURLs) }
        let archiveURL = try XCTUnwrap(postExpiryURLs.first {
            $0.lastPathComponent == "NeuroForge-Full-Archive.json"
        })
        let archive = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(contentsOf: archiveURL)) as? [String: Any]
        )
        XCTAssertEqual(
            (archive["archiveVersion"] as? NSNumber)?.intValue,
            NFDataExportService.archiveVersion
        )
        let reports = try XCTUnwrap(archive["quarantinedReports"] as? [[String: Any]])
        let sourceChunks = try XCTUnwrap(archive["sourceChunks"] as? [[String: Any]])
        let exportedChunk = try XCTUnwrap(sourceChunks.first { $0["id"] as? String == chunkID })
        XCTAssertEqual((exportedChunk["characterStart"] as? NSNumber)?.intValue, 240)
        XCTAssertEqual((exportedChunk["characterEnd"] as? NSNumber)?.intValue, 326)
        XCTAssertEqual(exportedChunk["nearbyHeading"] as? String, "Methods")
        XCTAssertEqual(exportedChunk["language"] as? String, "markdown")
        XCTAssertEqual(exportedChunk["contentTypeTags"] as? [String], ["markdown", "prose", "section"])
        let reflections = try XCTUnwrap(archive["attemptReflections"] as? [[String: Any]])
        let reflection = try XCTUnwrap(reflections.first)
        XCTAssertEqual(reflection["attemptID"] as? String, ordinary.id.uuidString.uppercased())
        XCTAssertEqual(reflection["deterministicErrorCode"] as? String, ordinary.errorCode)
        XCTAssertEqual(reflection["selectedErrorCode"] as? String, NFErrorReflectionCode.inputError.rawValue)
        XCTAssertEqual(reflection["trigger"] as? String, NFAttemptReflectionTrigger.highConfidenceError.rawValue)
        XCTAssertEqual(reflection["note"] as? String, "I tapped the neighboring key.")
        let report = try XCTUnwrap(reports.first)
        XCTAssertEqual(report["diagnosticPayloadState"] as? String, "available")
        XCTAssertFalse((report["diagnosticDigest"] as? String ?? "").isEmpty)
        XCTAssertEqual(report["sourceChunkIDs"] as? [String], [chunkID])
        XCTAssertLessThanOrEqual(
            (report["diagnosticPayloadBytes"] as? NSNumber)?.intValue ?? .max,
            ItemReportRecord.maximumAuthoredDiagnosticPayloadBytes
        )
        let diagnostic = try XCTUnwrap(report["authoredDiagnostic"] as? [String: Any])
        XCTAssertEqual(diagnostic["prompt"] as? String, prompt)
        XCTAssertEqual(diagnostic["choices"] as? [String], [])
        XCTAssertEqual(diagnostic["correctAnswer"] as? String, reference)
        XCTAssertEqual(
            diagnostic["explanation"] as? String,
            "The reference follows the controlled comparison."
        )
        XCTAssertEqual(diagnostic["citationChunkIDs"] as? [String], [chunkID])
        XCTAssertEqual(diagnostic["generationSourceChunkIDs"] as? [String], [chunkID])
        XCTAssertEqual(diagnostic["sourceDocumentIDs"] as? [String], [documentID.uuidString])
        XCTAssertEqual(diagnostic["requestID"] as? String, generationID.uuidString)
        XCTAssertEqual(diagnostic["cacheKey"] as? String, "stable-cache-key")
        XCTAssertEqual(diagnostic["modelIdentifier"] as? String, "neuroforge-deterministic-v1")
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
        return (AppStore(context: container.mainContext), container)
    }

    private func rowDictionary(header: [String], values: [String]?) throws -> [String: String] {
        let values = try XCTUnwrap(values)
        XCTAssertEqual(values.count, header.count)
        return Dictionary(uniqueKeysWithValues: zip(header, values))
    }

    private func parseCSV(_ csv: String) throws -> [[String]] {
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var isQuoted = false
        var index = csv.startIndex

        while index < csv.endIndex {
            let character = csv[index]
            let next = csv.index(after: index)
            if isQuoted {
                if character == "\"" {
                    if next < csv.endIndex, csv[next] == "\"" {
                        field.append("\"")
                        index = csv.index(after: next)
                        continue
                    }
                    isQuoted = false
                } else {
                    field.append(character)
                }
            } else {
                switch character {
                case "\"":
                    isQuoted = true
                case ",":
                    row.append(field)
                    field = ""
                case "\n":
                    row.append(field)
                    rows.append(row)
                    row = []
                    field = ""
                case "\r":
                    if next < csv.endIndex, csv[next] == "\n" {
                        index = next
                    }
                    row.append(field)
                    rows.append(row)
                    row = []
                    field = ""
                default:
                    field.append(character)
                }
            }
            index = csv.index(after: index)
        }

        XCTAssertFalse(isQuoted)
        if !field.isEmpty || !row.isEmpty {
            row.append(field)
            rows.append(row)
        }
        return rows
    }

    private func removeExportFolder(for exportURLs: [URL]) {
        guard let folder = exportURLs.first?.deletingLastPathComponent() else { return }
        try? FileManager.default.removeItem(at: folder)
    }
}

private extension Array {
    subscript(safe index: Int?) -> Element? {
        guard let index, indices.contains(index) else { return nil }
        return self[index]
    }
}

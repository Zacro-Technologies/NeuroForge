import Foundation

enum NFDataExportError: Error, LocalizedError {
    case couldNotCreateFolder
    case couldNotRemovePreparedExports

    var errorDescription: String? {
        switch self {
        case .couldNotCreateFolder:
            NFAppLocalization.localized("NeuroForge could not prepare a private export folder.", locale: NFAppLocalization.preferredLocale, comment: "Private local data-export error.")
        case .couldNotRemovePreparedExports:
            NFAppLocalization.localized("NeuroForge could not verify removal of every prepared export folder.", locale: NFAppLocalization.preferredLocale, comment: "Private local data-export cleanup error.")
        }
    }
}

@MainActor
enum NFDataExportService {
    static let archiveVersion = 17
    static let oldestRestorableArchiveVersion = 14
    static let generatedQuestionsSchemaVersion = 1
    static let reviewHistorySchemaVersion = 1
    private static let exportFolderPrefix = "NeuroForge-Export-"

    static func makeExports(from store: AppStore) throws -> [URL] {
        try removePreparedExports(olderThan: Date().addingTimeInterval(-86_400))
        let folder = FileManager.default.temporaryDirectory
            .appending(path: "\(exportFolderPrefix)\(UUID().uuidString)", directoryHint: .isDirectory)
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        } catch {
            throw NFDataExportError.couldNotCreateFolder
        }

        let archiveURL = folder.appending(path: "NeuroForge-Full-Archive.json")
        let summaryURL = folder.appending(path: "NeuroForge-Progress-Summary.csv")
        let generatedQuestionsURL = folder.appending(
            path: "NeuroForge-Generated-Questions-v\(generatedQuestionsSchemaVersion).json"
        )
        let reviewHistoryURL = folder.appending(
            path: "NeuroForge-Document-AI-Review-History-v\(reviewHistorySchemaVersion).csv"
        )
        let archive = makeArchive(store)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(archive).write(to: archiveURL, options: secureWritingOptions)
        try Data(makeSummaryCSV(store).utf8).write(to: summaryURL, options: secureWritingOptions)
        try encoder.encode(makeGeneratedQuestionsExport(store)).write(
            to: generatedQuestionsURL,
            options: secureWritingOptions
        )
        try Data(makeReviewHistoryCSV(store).utf8).write(
            to: reviewHistoryURL,
            options: secureWritingOptions
        )
        return [archiveURL, summaryURL, generatedQuestionsURL, reviewHistoryURL]
    }

    static func removePreparedExports(
        olderThan cutoff: Date? = nil,
        fileManager: FileManager = .default,
        temporaryDirectory: URL? = nil
    ) throws {
        let temporaryDirectory = temporaryDirectory ?? fileManager.temporaryDirectory
        let children: [URL]
        do {
            children = try fileManager.contentsOfDirectory(
                at: temporaryDirectory,
                includingPropertiesForKeys: [.contentModificationDateKey],
                options: [.skipsHiddenFiles]
            )
        } catch {
            throw NFDataExportError.couldNotRemovePreparedExports
        }

        var removalFailed = false
        for child in children where child.lastPathComponent.hasPrefix(exportFolderPrefix) {
            if let cutoff {
                let modified = try? child.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
                guard let modified, modified < cutoff else { continue }
            }
            do {
                try fileManager.removeItem(at: child)
            } catch {
                removalFailed = true
            }
        }

        guard !removalFailed else {
            throw NFDataExportError.couldNotRemovePreparedExports
        }

        let remaining: [URL]
        do {
            remaining = try fileManager.contentsOfDirectory(
            at: temporaryDirectory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
            )
        } catch {
            throw NFDataExportError.couldNotRemovePreparedExports
        }
        for child in remaining where child.lastPathComponent.hasPrefix(exportFolderPrefix) {
            if let cutoff {
                let modified = try? child.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
                guard let modified, modified < cutoff else { continue }
            }
            throw NFDataExportError.couldNotRemovePreparedExports
        }
    }

    private static var secureWritingOptions: Data.WritingOptions {
        #if os(iOS) || os(tvOS) || os(watchOS) || os(visionOS)
        [.atomic, .completeFileProtection]
        #else
        // Complete-file protection is an iOS-family data-protection class. The
        // macOS app still uses an atomic write inside its private container.
        [.atomic]
        #endif
    }

    private static func makeArchive(_ store: AppStore) -> Archive {
        let profile = store.profile.map {
            Profile(
                id: $0.id,
                createdAt: $0.createdAt,
                modifiedAt: $0.modifiedAt,
                stage: $0.stageRaw,
                fields: split($0.fieldsRaw),
                goals: split($0.goalsRaw),
                dailyDuration: $0.dailyDuration,
                timingMode: $0.timingModeRaw,
                aiMode: $0.aiModeRaw,
                iCloudEnabled: $0.iCloudEnabled,
                reducedMotion: $0.reducedMotion,
                hideTimers: $0.hideTimers,
                excludeVisualSpatial: $0.excludeVisualSpatial,
                onboardingVersion: $0.onboardingVersion,
                claimsPolicyAcknowledgedVersion: $0.claimsPolicyAcknowledgedVersion,
                pccConsentVersion: $0.pccConsentVersion,
                pccConsentAt: $0.pccConsentAt,
                preferredLanguageCode: $0.preferredLanguageCode,
                trainingDays: split($0.trainingDaysRaw),
                dayBoundaryHour: $0.dayBoundaryHour,
                ageBandAcknowledged16Plus: $0.ageBandAcknowledged16Plus,
                preferredAnswerMode: $0.preferredAnswerModeRaw,
                reinforcementHapticsEnabled: $0.reinforcementHapticsEnabled,
                reinforcementSoundEnabled: $0.reinforcementSoundEnabled
            )
        }

        return Archive(
            archiveVersion: archiveVersion,
            exportedAt: Date(),
            appVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0",
            profile: profile,
            attempts: store.attemptRecordsForExport.map {
                Attempt(
                    id: $0.id, sessionID: $0.sessionID, itemID: $0.itemID, templateID: $0.templateID,
                    seed: $0.seed, lab: $0.gameID, skillID: $0.skillID,
                    skillWeights: $0.skillWeights, domainContext: $0.domainContextRaw,
                    transferBrief: $0.transferBrief,
                    spatialDifficultyParameters: $0.spatialDifficultyParameters,
                    prompt: $0.prompt,
                    response: $0.response, correctAnswer: $0.correctAnswerText, isCorrect: $0.isCorrect,
                    confidence: $0.confidenceRaw, shownAt: $0.shownAt, submittedAt: $0.submittedAt,
                    activeDurationSeconds: $0.activeDurationSeconds, evidenceClass: $0.evidenceClassRaw,
                    sessionSource: $0.sessionSourceRaw, evidenceWeight: $0.evidenceWeight,
                    errorCode: $0.errorCode, scoringVersion: $0.scoringVersion, deviceID: $0.deviceID,
                    generationID: $0.generationID, sourceDocumentIDs: split($0.sourceDocumentIDsRaw),
                    sourceChunkIDs: split($0.sourceChunkIDsRaw), responseFormat: $0.responseFormatRaw,
                    wasSkipped: $0.wasSkipped, validationVersion: $0.validationVersion,
                    assessmentBlock: $0.assessmentBlockRaw, planID: $0.planID,
                    planBlockID: $0.planBlockID, deterministicCredit: $0.deterministicCredit,
                    hintCount: $0.hintCount, inputMode: $0.inputModeRaw,
                    interruptionCount: $0.interruptionCount, revisionCount: $0.revisionCount,
                    accommodationFlags: split($0.accommodationFlagsRaw), wasTimed: $0.wasTimed,
                    assessmentDescriptorID: $0.assessmentDescriptorID,
                    assessmentTemplateFamily: $0.assessmentTemplateFamily,
                    assessmentFormat: $0.assessmentFormatRaw,
                    assessmentMechanicID: $0.assessmentMechanicID,
                    assessmentSubskillID: $0.assessmentSubskillID,
                    assessmentSeed: $0.assessmentSeed,
                    assessmentCycle: $0.assessmentCycle
                )
            },
            attemptReflections: store.attemptReflections.map {
                AttemptReflection(
                    id: $0.id,
                    attemptID: $0.attemptID,
                    deterministicErrorCode: $0.deterministicErrorCode,
                    selectedErrorCode: $0.selectedErrorCodeRaw,
                    trigger: $0.triggerRaw,
                    note: $0.note,
                    createdAt: $0.createdAt,
                    policyVersion: $0.policyVersion
                )
            },
            documents: store.documents.map {
                Document(
                    id: $0.id, filename: $0.filename, typeIdentifier: $0.typeIdentifier,
                    sizeBytes: $0.sizeBytes, importedAt: $0.importedAt, indexState: $0.indexState,
                    aiPolicy: $0.aiPolicyRaw, syncPolicy: $0.syncPolicy,
                    pccExcerptConsentPolicyVersion: $0.pccExcerptConsentPolicyVersion,
                    pccExcerptConsentDocumentID: $0.pccExcerptConsentDocumentIDRaw,
                    pccExcerptConsentedAt: $0.pccExcerptConsentedAt,
                    characterCount: $0.characterCount, chunkCount: $0.chunkCount,
                    extractionVersion: $0.extractionVersion,
                    csvSelectedColumnIDs: $0.csvSelectedColumnIDs,
                    indexError: NFDiagnosticRedactor.sanitizedPersistedMessage(
                        $0.indexError,
                        context: $0.indexError?.hasPrefix("document.ocr.") == true ? .localOCR : .documentExtraction
                    )
                )
            },
            sourceChunks: store.sourceChunks.map {
                Chunk(
                    id: $0.id, documentID: $0.documentID, documentVersion: $0.documentVersion,
                    sourceName: $0.sourceName, page: $0.page, lineStart: $0.lineStart,
                    lineEnd: $0.lineEnd, section: $0.section, text: $0.text,
                    contentHash: $0.contentHash, ordinal: $0.ordinal,
                    characterStart: $0.characterStart, characterEnd: $0.characterEnd,
                    nearbyHeading: $0.nearbyHeading, language: $0.language,
                    contentTypeTags: $0.contentTypeTags
                )
            },
            aiGenerations: store.aiGenerations.map {
                Generation(
                    id: $0.id, createdAt: $0.createdAt, capability: $0.capabilityRaw,
                    lab: $0.labRaw, field: $0.fieldRaw, topic: $0.topic, route: $0.routeRaw,
                    routeReason: $0.routeReason, promptVersion: $0.promptVersion,
                    validationVersion: $0.validationVersion, modelIdentifier: $0.modelIdentifier,
                    sourceDocumentIDs: split($0.sourceDocumentIDsRaw), sourceChunkIDs: split($0.sourceChunkIDsRaw),
                    repairCount: $0.repairCount, cacheKey: $0.cacheKey,
                    isFallback: $0.isFallback, questionCount: $0.questionCount,
                    payloadExpiresAt: $0.payloadExpiresAt,
                    questions: $0.recoverableResult()?.questions ?? [],
                    routeCandidates: $0.recoverableResult()?.routeCandidates,
                    validationStatus: $0.recoverableResult()?.validationStatus,
                    validationNotes: $0.recoverableResult()?.validationNotes
                )
            },
            sessionCheckpoints: store.sessionCheckpoints.map {
                Checkpoint(
                    id: $0.id, sessionID: $0.sessionID, lab: $0.labRaw, source: $0.sourceRaw,
                    seed: $0.seed, currentIndex: $0.currentIndex, itemCount: $0.itemCount,
                    response: $0.response, scratchpad: $0.scratchpad,
                    results: split($0.resultsRaw), evidenceClass: $0.evidenceClassRaw,
                    updatedAt: $0.updatedAt, isComplete: $0.isComplete,
                    credits: split($0.creditsRaw),
                    assessmentDescriptorIDs: split($0.assessmentDescriptorIDsRaw),
                    assessmentEvents: split($0.assessmentEventsRaw),
                    planID: $0.planID, planBlockID: $0.planBlockID,
                    recommendationRationale: $0.recommendationRationale,
                    hasCommittedCurrentItem: $0.hasCommittedCurrentItem,
                    assessmentBlock: $0.assessmentBlockRaw,
                    assessmentCycle: $0.assessmentCycle,
                    activeDurationSeconds: $0.activeDurationSeconds,
                    assessmentStopReason: $0.assessmentStopReasonRaw,
                    pendingReflectionAttemptID: $0.pendingReflectionAttemptID,
                    reflectionTrigger: $0.reflectionTriggerRaw,
                    selectedReflectionCode: $0.selectedReflectionCodeRaw,
                    reflectionNote: $0.reflectionNote
                )
            },
            dailyPlans: store.dailyPlans.map {
                DailyPlan(
                    id: $0.id, profileID: $0.profileID, localDayKey: $0.localDayKey,
                    policyVersion: $0.policyVersion,
                    canonicalPayloadBase64: $0.payload.base64EncodedString(),
                    createdAt: $0.createdAt, timeZoneIdentifier: $0.timeZoneIdentifier,
                    utcOffsetSeconds: $0.utcOffsetSeconds, dayBoundaryHour: $0.dayBoundaryHour,
                    boundaryStart: $0.boundaryStart, nextBoundaryAt: $0.nextBoundaryAt,
                    travelPreservedUntil: $0.travelPreservedUntil
                )
            },
            inputCalibrations: store.inputCalibrations.map {
                InputCalibration(
                    id: $0.id, profileID: $0.profileID, completedAt: $0.completedAt,
                    preferredAnswerMode: $0.preferredAnswerModeRaw,
                    keyboardLatencyMilliseconds: $0.keyboardLatencyMilliseconds,
                    touchLatencyMilliseconds: $0.touchLatencyMilliseconds,
                    pencilLatencyMilliseconds: $0.pencilLatencyMilliseconds
                )
            },
            progressAnnotations: store.progressAnnotations.filter(\.includeInExport).map {
                ProgressAnnotation(
                    id: $0.id, startDate: $0.startDate, endDate: $0.endDate,
                    note: $0.note, createdAt: $0.createdAt, modifiedAt: $0.modifiedAt
                )
            },
            excludedPrivateAnnotationCount: store.progressAnnotations.filter { !$0.includeInExport }.count,
            weeklyTransferState: store.weeklyTransferStateRecord?.snapshot,
            reassessmentState: store.reassessmentStateRecord?.snapshot,
            adaptivePlanHistory: store.adaptivePlanHistory,
            quarantinedReports: store.itemReports.map {
                Report(
                    id: $0.id, itemID: $0.itemID, templateID: $0.templateID,
                    prompt: $0.prompt, reason: $0.reason, note: $0.note,
                    createdAt: $0.createdAt, status: $0.status, seed: $0.seed,
                    generatorVersion: $0.generatorVersion,
                    provenanceSummary: $0.provenanceSummary,
                    sourceIDs: split($0.sourceIDsRaw),
                    sourceChunkIDs: split($0.sourceChunkIDsRaw),
                    assessmentDescriptorID: $0.assessmentDescriptorID,
                    diagnosticPayloadState: $0.diagnosticPayloadState,
                    diagnosticDigest: $0.diagnosticDigest,
                    diagnosticPayloadBytes: $0.diagnosticPayload.count,
                    authoredDiagnostic: $0.authoredDiagnostic
                )
            }
        )
    }

    private static func makeSummaryCSV(_ store: AppStore) -> String {
        var lines = ["lab,evidence_class,scorable_attempts,skipped,fully_correct,earned_credit_percent,last_activity"]
        for lab in TrainingLab.allCases {
            for evidence in EvidenceClass.allCases {
                let attempts = store.attempts.filter { $0.gameID == lab.rawValue && $0.evidenceClassRaw == evidence.rawValue }
                guard !attempts.isEmpty else { continue }
                let scorable = attempts.filter { !$0.wasSkipped && $0.evidenceWeight > 0 }
                let skipped = attempts.filter(\.wasSkipped).count
                let correct = scorable.filter(\.isCorrect).count
                let availableEvidence = scorable.reduce(0) { $0 + max(0, $1.evidenceWeight) }
                let earnedCredit = scorable.reduce(0) {
                    $0 + min(1, max(0, $1.deterministicCredit)) * max(0, $1.evidenceWeight)
                }
                let accuracy = availableEvidence > 0 ? 100 * earnedCredit / availableEvidence : 0
                let last = attempts.map(\.submittedAt).max()?.ISO8601Format() ?? ""
                lines.append([
                    lab.rawValue,
                    evidence.rawValue,
                    String(scorable.count),
                    String(skipped),
                    String(correct),
                    accuracy.formatted(.number.precision(.fractionLength(2))),
                    last
                ].map(csvEscape).joined(separator: ","))
            }
        }
        return lines.joined(separator: "\n") + "\n"
    }

    private static func makeGeneratedQuestionsExport(_ store: AppStore) -> GeneratedQuestionsExport {
        let exportedAt = Date()
        let generations = store.aiGenerations
            .sorted {
                if $0.createdAt == $1.createdAt { return $0.id.uuidString < $1.id.uuidString }
                return $0.createdAt < $1.createdAt
            }
            .map { record in
                let result = record.recoverableResult(at: exportedAt)
                let payloadState: String
                if result != nil {
                    payloadState = "available"
                } else if record.resultPayload.isEmpty {
                    payloadState = "purged"
                } else if record.payloadExpiresAt <= exportedAt {
                    payloadState = "expired"
                } else {
                    payloadState = "invalid"
                }
                return GeneratedQuestionGeneration(
                    generationID: record.id,
                    generatedAt: record.createdAt,
                    capability: record.capabilityRaw,
                    field: record.fieldRaw,
                    lab: record.labRaw,
                    topic: record.topic,
                    route: record.routeRaw,
                    routeReason: record.routeReason,
                    promptVersion: record.promptVersion,
                    validationVersion: record.validationVersion,
                    modelIdentifier: record.modelIdentifier,
                    sourceDocumentIDs: split(record.sourceDocumentIDsRaw),
                    sourceChunkIDs: split(record.sourceChunkIDsRaw),
                    repairCount: record.repairCount,
                    cacheKey: record.cacheKey,
                    isFallback: record.isFallback,
                    payloadState: payloadState,
                    payloadExpiresAt: record.payloadExpiresAt,
                    recordedQuestionCount: record.questionCount,
                    exportedQuestionCount: result?.questions.count ?? 0,
                    routeCandidates: result?.routeCandidates ?? [],
                    validationStatus: result?.validationStatus,
                    validationNotes: result?.validationNotes ?? [],
                    questions: result?.questions.map {
                        GeneratedQuestion(
                            stableQuestionID: "\(record.id.uuidString.lowercased()):\($0.id)",
                            questionID: $0.id,
                            lab: $0.lab.rawValue,
                            style: $0.style.rawValue,
                            prompt: $0.prompt,
                            context: $0.context,
                            choices: $0.choices,
                            correctAnswer: $0.correctAnswer,
                            acceptedAnswers: $0.acceptedAnswers,
                            explanation: $0.explanation,
                            hint: $0.hint,
                            decisiveStep: $0.decisiveStep,
                            difficulty: $0.difficulty,
                            citationChunkIDs: $0.citationChunkIDs,
                            evidenceClass: $0.evidenceClass.rawValue
                        )
                    } ?? []
                )
            }

        return GeneratedQuestionsExport(
            artifact: "com.zacrotech.neuroforge.generated-questions",
            schemaVersion: generatedQuestionsSchemaVersion,
            exportedAt: exportedAt,
            schema: GeneratedQuestionsSchemaDocumentation.current,
            generations: generations
        )
    }

    private static func makeReviewHistoryCSV(_ store: AppStore) -> String {
        let header = [
            "schema_version", "review_id", "session_id", "item_id", "template_id",
            "generation_id", "generated_at", "shown_at", "submitted_at", "field", "lab",
            "prompt", "response", "reference_answer", "confidence", "review_outcome",
            "is_correct", "deterministic_credit", "evidence_weight",
            "counts_as_standardized_evidence", "evidence_class", "session_source",
            "response_format", "source_document_ids", "source_chunk_ids",
            "attempt_validation_version", "generation_validation_version",
            "generation_prompt_version", "generation_route", "generation_route_reason",
            "generation_model_identifier", "generation_repair_count", "generation_cache_key",
            "generation_is_fallback"
        ]
        let generationByID = store.aiGenerations.reduce(into: [UUID: AIGenerationRecord]()) {
            $0[$1.id] = $1
        }
        let personalReviews = store.attemptRecordsForExport
            .filter {
                $0.generationID != nil
                    || $0.evidenceClassRaw == EvidenceClass.documentPractice.rawValue
                    || !split($0.sourceDocumentIDsRaw).isEmpty
                    || !split($0.sourceChunkIDsRaw).isEmpty
            }
            .sorted {
                if $0.submittedAt == $1.submittedAt { return $0.id.uuidString < $1.id.uuidString }
                return $0.submittedAt < $1.submittedAt
            }

        var lines = [header.joined(separator: ",")]
        for attempt in personalReviews {
            let generation = attempt.generationID.flatMap { generationByID[$0] }
            let wasEvaluated = !attempt.wasSkipped
            let countsAsEvidence = wasEvaluated && attempt.evidenceWeight > 0
            let outcome: String
            if attempt.wasSkipped {
                outcome = "skipped_no_evidence"
            } else if attempt.evidenceWeight <= 0 {
                outcome = "evaluated_personal_review_no_standardized_evidence"
            } else {
                outcome = "evaluated_scorable"
            }
            let row: [String] = [
                String(reviewHistorySchemaVersion),
                attempt.id.uuidString.lowercased(),
                attempt.sessionID.uuidString.lowercased(),
                attempt.itemID,
                attempt.templateID,
                attempt.generationID?.uuidString.lowercased() ?? "",
                generation?.createdAt.ISO8601Format() ?? "",
                attempt.shownAt.ISO8601Format(),
                attempt.submittedAt.ISO8601Format(),
                attempt.domainContextRaw,
                attempt.gameID,
                attempt.prompt,
                wasEvaluated ? attempt.response : "",
                wasEvaluated ? attempt.correctAnswerText : "",
                wasEvaluated ? attempt.confidenceRaw ?? "" : "",
                outcome,
                wasEvaluated ? String(attempt.isCorrect) : "",
                wasEvaluated ? String(attempt.deterministicCredit) : "",
                String(max(0, attempt.evidenceWeight)),
                String(countsAsEvidence),
                attempt.evidenceClassRaw,
                attempt.sessionSourceRaw,
                attempt.responseFormatRaw,
                jsonArray(split(attempt.sourceDocumentIDsRaw)),
                jsonArray(split(attempt.sourceChunkIDsRaw)),
                String(attempt.validationVersion),
                generation.map { String($0.validationVersion) } ?? "",
                generation.map { String($0.promptVersion) } ?? "",
                generation?.routeRaw ?? "",
                generation?.routeReason ?? "",
                generation?.modelIdentifier ?? "",
                generation.map { String($0.repairCount) } ?? "",
                generation?.cacheKey ?? "",
                generation.map { String($0.isFallback) } ?? ""
            ]
            lines.append(row.map(csvEscape).joined(separator: ","))
        }
        return lines.joined(separator: "\n") + "\n"
    }

    private static func split(_ value: String) -> [String] {
        value.split(separator: ",").map(String.init).filter { !$0.isEmpty }
    }

    private static func jsonArray(_ values: [String]) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        guard let data = try? encoder.encode(values),
              let value = String(data: data, encoding: .utf8) else { return "[]" }
        return value
    }

    private static func csvEscape(_ value: String) -> String {
        guard value.contains(where: { $0 == "," || $0 == "\"" || $0 == "\n" || $0 == "\r" }) else {
            return value
        }
        return "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
    }

    private struct GeneratedQuestionsExport: Codable, Sendable {
        let artifact: String
        let schemaVersion: Int
        let exportedAt: Date
        let schema: GeneratedQuestionsSchemaDocumentation
        let generations: [GeneratedQuestionGeneration]
    }

    private struct GeneratedQuestionsSchemaDocumentation: Codable, Sendable {
        let contract: String
        let timestampEncoding: String
        let stableIdentityRules: [String]
        let payloadStateDefinitions: [String: String]
        let requiredGenerationFields: [String]
        let requiredQuestionFields: [String]

        static let current = GeneratedQuestionsSchemaDocumentation(
            contract: "Each generation record is retained even when its bounded question payload has expired or been purged. Questions are present only when payloadState is available.",
            timestampEncoding: "RFC 3339 / ISO 8601 UTC timestamp",
            stableIdentityRules: [
                "generationID is the durable authoring request/provenance UUID.",
                "stableQuestionID is generationID in lowercase UUID form, a colon, then the generator-provided questionID.",
                "sourceDocumentIDs are UUID strings; sourceChunkIDs are stable content-and-locator identifiers."
            ],
            payloadStateDefinitions: [
                "available": "The validated persisted payload was decoded and its questions are included.",
                "expired": "The bounded payload passed its retention deadline; provenance remains but questions are omitted.",
                "purged": "The bounded payload was removed by cleanup or cache limits; provenance remains but questions are omitted.",
                "invalid": "The payload failed current identity, schema, citation, or validation checks and questions are omitted."
            ],
            requiredGenerationFields: [
                "generationID", "generatedAt", "field", "lab", "route", "promptVersion",
                "validationVersion", "sourceDocumentIDs", "sourceChunkIDs", "payloadState",
                "recordedQuestionCount", "exportedQuestionCount", "questions"
            ],
            requiredQuestionFields: [
                "stableQuestionID", "questionID", "lab", "style", "prompt", "correctAnswer",
                "explanation", "difficulty", "citationChunkIDs", "evidenceClass"
            ]
        )
    }

    private struct GeneratedQuestionGeneration: Codable, Sendable {
        let generationID: UUID
        let generatedAt: Date
        let capability: String
        let field: String
        let lab: String
        let topic: String
        let route: String
        let routeReason: String
        let promptVersion: Int
        let validationVersion: Int
        let modelIdentifier: String
        let sourceDocumentIDs: [String]
        let sourceChunkIDs: [String]
        let repairCount: Int
        let cacheKey: String
        let isFallback: Bool
        let payloadState: String
        let payloadExpiresAt: Date
        let recordedQuestionCount: Int
        let exportedQuestionCount: Int
        let routeCandidates: [NFAIRouteSnapshot]
        let validationStatus: NFAuthoringValidationStatus?
        let validationNotes: [String]
        let questions: [GeneratedQuestion]
    }

    private struct GeneratedQuestion: Codable, Sendable {
        let stableQuestionID: String
        let questionID: String
        let lab: String
        let style: String
        let prompt: String
        let context: String
        let choices: [String]
        let correctAnswer: String
        let acceptedAnswers: [String]
        let explanation: String
        let hint: String
        let decisiveStep: String
        let difficulty: Double
        let citationChunkIDs: [String]
        let evidenceClass: String
    }

    struct Archive: Codable {
        let archiveVersion: Int
        let exportedAt: Date
        let appVersion: String
        let profile: Profile?
        let attempts: [Attempt]
        let attemptReflections: [AttemptReflection]
        let documents: [Document]
        let sourceChunks: [Chunk]
        let aiGenerations: [Generation]
        let sessionCheckpoints: [Checkpoint]
        let dailyPlans: [DailyPlan]
        let inputCalibrations: [InputCalibration]
        let progressAnnotations: [ProgressAnnotation]
        let excludedPrivateAnnotationCount: Int
        let weeklyTransferState: NFWeeklyTransferState?
        let reassessmentState: NFReassessmentState?
        let adaptivePlanHistory: [NFAdaptivePlanChangeRecord]?
        let quarantinedReports: [Report]
    }
    struct Profile: Codable {
        let id: UUID; let createdAt: Date; let modifiedAt: Date; let stage: String; let fields: [String]; let goals: [String]
        let dailyDuration: Int; let timingMode: String; let aiMode: String; let iCloudEnabled: Bool; let reducedMotion: Bool
        let hideTimers: Bool; let excludeVisualSpatial: Bool; let onboardingVersion: Int
        let claimsPolicyAcknowledgedVersion: Int; let pccConsentVersion: Int
        let pccConsentAt: Date?; let preferredLanguageCode: String; let trainingDays: [String]
        let dayBoundaryHour: Int; let ageBandAcknowledged16Plus: Bool; let preferredAnswerMode: String
        let reinforcementHapticsEnabled: Bool; let reinforcementSoundEnabled: Bool
    }
    struct Attempt: Codable {
        let id: UUID; let sessionID: UUID; let itemID: String; let templateID: String; let seed: UInt64; let lab: String
        let skillID: String; let skillWeights: [String: Double]; let domainContext: String
        let transferBrief: NFExerciseTransferBrief?; let spatialDifficultyParameters: NFSpatialDifficultyParameters?
        let prompt: String; let response: String; let correctAnswer: String; let isCorrect: Bool
        let confidence: String?; let shownAt: Date; let submittedAt: Date; let activeDurationSeconds: Double
        let evidenceClass: String; let sessionSource: String; let evidenceWeight: Double; let errorCode: String?
        let scoringVersion: Int; let deviceID: UUID; let generationID: UUID?; let sourceDocumentIDs: [String]
        let sourceChunkIDs: [String]; let responseFormat: String; let wasSkipped: Bool; let validationVersion: Int
        let assessmentBlock: String?; let planID: String?; let planBlockID: String?; let deterministicCredit: Double
        let hintCount: Int; let inputMode: String; let interruptionCount: Int; let revisionCount: Int
        let accommodationFlags: [String]; let wasTimed: Bool; let assessmentDescriptorID: String?
        let assessmentTemplateFamily: String?; let assessmentFormat: String?; let assessmentMechanicID: String?
        let assessmentSubskillID: String?; let assessmentSeed: UInt64?; let assessmentCycle: Int?
    }
    struct AttemptReflection: Codable {
        let id: UUID; let attemptID: UUID; let deterministicErrorCode: String?; let selectedErrorCode: String?
        let trigger: String; let note: String; let createdAt: Date; let policyVersion: Int
    }
    struct Document: Codable {
        let id: UUID; let filename: String; let typeIdentifier: String; let sizeBytes: Int64; let importedAt: Date
        let indexState: String; let aiPolicy: String; let syncPolicy: String
        let pccExcerptConsentPolicyVersion: Int; let pccExcerptConsentDocumentID: String; let pccExcerptConsentedAt: Date?
        let characterCount: Int; let chunkCount: Int
        let extractionVersion: Int; let csvSelectedColumnIDs: [String]; let indexError: String?
    }
    struct Chunk: Codable {
        let id: String; let documentID: UUID; let documentVersion: Int; let sourceName: String; let page: Int?
        let lineStart: Int?; let lineEnd: Int?; let section: String?; let text: String; let contentHash: String; let ordinal: Int
        let characterStart: Int?; let characterEnd: Int?; let nearbyHeading: String?; let language: String?
        let contentTypeTags: [String]
    }
    struct Generation: Codable {
        let id: UUID; let createdAt: Date; let capability: String; let lab: String; let field: String; let topic: String
        let route: String; let routeReason: String; let promptVersion: Int; let validationVersion: Int; let modelIdentifier: String
        let sourceDocumentIDs: [String]; let sourceChunkIDs: [String]; let repairCount: Int; let cacheKey: String
        let isFallback: Bool; let questionCount: Int; let payloadExpiresAt: Date; let questions: [NFAuthoredQuestion]
        let routeCandidates: [NFAIRouteSnapshot]?
        let validationStatus: NFAuthoringValidationStatus?
        let validationNotes: [String]?
    }
    struct Checkpoint: Codable {
        let id: UUID; let sessionID: UUID; let lab: String; let source: String; let seed: UInt64
        let currentIndex: Int; let itemCount: Int; let response: String; let scratchpad: String
        let results: [String]; let evidenceClass: String; let updatedAt: Date; let isComplete: Bool
        let credits: [String]; let assessmentDescriptorIDs: [String]; let assessmentEvents: [String]
        let planID: String?; let planBlockID: String?; let recommendationRationale: String?
        let hasCommittedCurrentItem: Bool
        let assessmentBlock: String?; let assessmentCycle: Int?; let activeDurationSeconds: Double; let assessmentStopReason: String?
        let pendingReflectionAttemptID: UUID?; let reflectionTrigger: String?; let selectedReflectionCode: String?; let reflectionNote: String?
    }
    struct DailyPlan: Codable {
        let id: String; let profileID: UUID; let localDayKey: String; let policyVersion: Int
        let canonicalPayloadBase64: String; let createdAt: Date; let timeZoneIdentifier: String
        let utcOffsetSeconds: Int; let dayBoundaryHour: Int; let boundaryStart: Date; let nextBoundaryAt: Date
        let travelPreservedUntil: Date?
    }
    struct InputCalibration: Codable {
        let id: UUID; let profileID: UUID; let completedAt: Date; let preferredAnswerMode: String
        let keyboardLatencyMilliseconds: Double?; let touchLatencyMilliseconds: Double?; let pencilLatencyMilliseconds: Double?
    }
    struct ProgressAnnotation: Codable {
        let id: UUID; let startDate: Date; let endDate: Date; let note: String; let createdAt: Date; let modifiedAt: Date
    }
    struct Report: Codable {
        let id: UUID; let itemID: String; let templateID: String; let prompt: String; let reason: String
        let note: String; let createdAt: Date; let status: String; let seed: UInt64
        let generatorVersion: Int; let provenanceSummary: String; let sourceIDs: [String]
        let sourceChunkIDs: [String]; let assessmentDescriptorID: String?
        let diagnosticPayloadState: String; let diagnosticDigest: String; let diagnosticPayloadBytes: Int
        let authoredDiagnostic: NFAuthoredReportDiagnostic?
    }
}

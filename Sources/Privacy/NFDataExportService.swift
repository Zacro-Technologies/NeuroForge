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
    nonisolated static let archiveVersion = 19
    nonisolated static let oldestRestorableArchiveVersion = 14
    static let generatedQuestionsSchemaVersion = 1
    static let reviewHistorySchemaVersion = 1
    private static let exportFolderPrefix = "NeuroForge-Export-"

    static func makeExports(from store: AppStore) throws -> [URL] {
        let temporaryDirectory = store.temporaryArtifactsRootURL ?? FileManager.default.temporaryDirectory
        do {
            try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        } catch { throw NFDataExportError.couldNotCreateFolder }
        try removePreparedExports(olderThan: Date().addingTimeInterval(-86_400), temporaryDirectory: temporaryDirectory)
        let folder = temporaryDirectory
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
        var archive = makeArchive(store)
        archive.aiLearningArtifacts = try NFAILearningArtifactArchive.capture(at: store.localSessions.aiArtifactDirectoryURL)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        let archiveData = try protectedPortableData(encoder.encode(archive))
        guard archiveData.count <= NFLocalSessionRepository.maximumBytes else { throw NFAILearningArtifactArchive.Failure.oversized }
        try archiveData.write(to: archiveURL, options: secureWritingOptions)
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

    struct ProtectedReceipt: Codable, Equatable, Sendable {
        var schemaVersion = 1
        let evaluatorReference: String
        let recoveryState: String
    }

    /// Portable archives expose an opaque protected receipt, never the local
    /// evaluator's per-item inputs. The same allowlists run on legacy imports
    /// before their permissive Codable adapters can revive hidden fields.
    nonisolated static func protectedPortableData(_ data: Data, forRestore: Bool = false) throws -> Data {
        guard var archive = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { return data }
        try NFAILearningArtifactArchive.validateArchiveVersion(archive)
        if let artifacts = archive["aiLearningArtifacts"], !(artifacts is NSNull) {
            guard JSONSerialization.isValidJSONObject(artifacts) else { throw NFAILearningArtifactArchive.Failure.unsupported }
            let values = try NFAILearningArtifactArchive.decodeEntries(artifacts)
            guard values.isEmpty || archive["archiveVersion"] as? Int == 19 else { throw NFAILearningArtifactArchive.Failure.unsupported }
        }
        func rows(_ key: String) -> [[String: Any]] { archive[key] as? [[String: Any]] ?? [] }
        func protected(_ row: [String: Any]) -> Bool { portableProtectedRow(row) }
        func identity(_ value: Any?) -> String { (value as? String ?? "").lowercased() }
        func allow(_ row: [String: Any], _ keys: String) -> [String: Any] {
            let allowed = Set(keys.split(separator: " ").map(String.init))
            return row.filter { allowed.contains($0.key) }
        }
        func receipt(_ row: [String: Any]) -> [String: Any] {
            ["schemaVersion": 1, "evaluatorReference": row["assessmentDescriptorID"] as? String ?? row["itemID"] as? String ?? row["sessionID"] as? String ?? "unavailable",
             "recoveryState": "evaluatorUnavailable"]
        }
        let graph = portableLearningGraph(archive["localLearning"] as? [String: Any] ?? [:],
            attempts: rows("attempts"), checkpoints: rows("sessionCheckpoints"))
        let sessions = graph.sessions, protectedAttempts = graph.attempts, protectedItemIDs = graph.items
        func protectedQuestion(_ row: [String: Any]) -> Bool {
            let exercise = row["authoritativeExercise"] as? [String: Any] ?? [:]
            return protected(row) || protected(exercise)
                || protectedItemIDs.contains(row["id"] as? String ?? "")
                || protectedItemIDs.contains(exercise["id"] as? String ?? "")
        }
        if archive["localLearning"] != nil { archive["localLearning"] = graph.local }
        archive["attempts"] = rows("attempts").map { row in
            guard protectedAttempts.contains(identity(row["id"])) else { return row }
            var safe = allow(row, "id sessionID itemID templateID seed lab skillID skillWeights domainContext transferBrief spatialDifficultyParameters prompt response confidence shownAt submittedAt activeDurationSeconds evidenceClass sessionSource scoringVersion deviceID generationID sourceDocumentIDs sourceChunkIDs responseFormat wasSkipped validationVersion assessmentBlock planID planBlockID hintCount inputMode interruptionCount revisionCount accommodationFlags wasTimed assessmentDescriptorID assessmentTemplateFamily assessmentFormat assessmentMechanicID assessmentSubskillID assessmentSeed assessmentCycle")
            safe["protectedReceipt"] = receipt(row)
            if forRestore {
                // Legacy storage has mandatory scalar fields. These neutral
                // placeholders have no authority and never count as incorrect.
                safe["correctAnswer"] = ""; safe["isCorrect"] = false
                safe["deterministicCredit"] = 0; safe["evidenceWeight"] = 0
                safe["errorCode"] = "protected_evaluator_unavailable"
            }
            return safe
        }
        archive["sessionCheckpoints"] = rows("sessionCheckpoints").map { row in
            guard protected(row) || sessions.contains(identity(row["sessionID"])) else { return row }
            var safe = allow(row, "id sessionID lab source seed currentIndex itemCount response scratchpad evidenceClass updatedAt isComplete assessmentDescriptorIDs assessmentEvents planID planBlockID recommendationRationale hasCommittedCurrentItem assessmentBlock assessmentCycle activeDurationSeconds assessmentStopReason")
            safe["protectedReceipt"] = receipt(row)
            if forRestore { safe["results"] = [String](); safe["credits"] = [String]() }
            return safe
        }
        archive["attemptReflections"] = rows("attemptReflections").map { row in
            guard protectedAttempts.contains(identity(row["attemptID"])) else { return row }
            var safe = allow(row, "id attemptID note createdAt policyVersion")
            safe["trigger"] = "protectedReceipt"
            return safe
        }
        archive["quarantinedReports"] = rows("quarantinedReports").map { row in
            let diagnostic = row["authoredDiagnostic"] as? [String: Any]
            let exercise = diagnostic?["authoritativeExercise"] as? [String: Any] ?? [:]
            guard row["assessmentDescriptorID"] is String || protectedItemIDs.contains(row["itemID"] as? String ?? "") || protected(exercise) else { return row }
            var safe = allow(row, "id itemID templateID prompt reason note createdAt status seed generatorVersion provenanceSummary sourceIDs sourceChunkIDs assessmentDescriptorID")
            safe["diagnosticPayloadState"] = "protectedReceipt"
            safe["diagnosticDigest"] = ""; safe["diagnosticPayloadBytes"] = 0
            return safe
        }
        archive["aiGenerations"] = rows("aiGenerations").map { generation in
            var safe = generation
            let questions = generation["questions"] as? [[String: Any]] ?? []
            let withheld = questions.filter(protectedQuestion)
            safe["questions"] = questions.filter { !protectedQuestion($0) }
            if !withheld.isEmpty {
                safe["protectedQuestionReferences"] = withheld.map { receipt(["itemID": $0["id"] as? String ?? "unavailable"]) }
            }
            return safe
        }
        if var local = archive["localLearning"] as? [String: Any] {
            local["sessions"] = (local["sessions"] as? [[String: Any]] ?? []).map { run in
                var safe = run
                var checkpoint = run["checkpoint"] as? [String: Any] ?? [:]
                var request = run["request"] as? [String: Any] ?? [:]
                let descriptor = checkpoint["descriptor"] as? [String: Any] ?? [:]
                let exercise = checkpoint["exercise"] as? [String: Any] ?? [:]
                let isProtected = sessions.contains(identity(run["id"]))
                    || protectedAttempts.contains(identity(checkpoint["attemptID"]))
                    || protectedAttempts.contains(identity(checkpoint["committedAttemptID"]))
                    || protected(request) || protected(exercise) || (descriptor["role"] as? String).map { $0 != "practice" } == true || checkpoint["exercise"] == nil || checkpoint["exercise"] is NSNull
                guard isProtected else { return run }
                checkpoint = allow(checkpoint, "schemaVersion slotID attemptID index itemCount phase exerciseDigest descriptor response confidence scratchpad hintCount solutionRevealed referenceRevealed selfCheckRating committedAttemptID assessmentDescriptorIDs assessmentEvents cumulativeActiveDuration itemActiveDuration assessmentPracticeDuration interruptionCount revisionCount inputModality semanticExclusions shownAt endedEarly scorerVersion")
                // Required empty containers carry no evaluator input and keep
                // old local-envelope decoding compatible without loosening it.
                checkpoint["correctness"] = [Bool](); checkpoint["credits"] = [Double](); checkpoint["reflectionNote"] = ""
                request = allow(request, "id lab source seed localeIdentifier requestedMinutes preferredMentalMathKind evidenceClass field topic recommendationRationale targetDifficulty requestedItemCount offlineQuestionOrdinals startingIndex assessmentBlock reassessmentCycle planID planBlockID isTimed timingCondition resumeSessionID resumedAssessmentDescriptorIDs resumedAssessmentEvents resumedResponsePayload resumedScratchpad resumeCurrentItemWasCommitted resumedActiveDurationSeconds resumedAssessmentPracticeDurationSeconds mechanicID retentionItemIDs retentionTargets transferBrief quarantinedItemIDs quarantinedAssessmentDescriptorIDs localSessionID ordinaryDelivery repairOriginAttemptID repairSemanticExclusions")
                request.removeValue(forKey: "localCheckpoint")
                request["resumedResults"] = [Bool](); request["resumedCredits"] = [Double]()
                request.removeValue(forKey: "resumedPendingReflectionAttemptID")
                request.removeValue(forKey: "resumedReflectionTrigger")
                request.removeValue(forKey: "resumedSelectedReflectionCode")
                request["resumedReflectionNote"] = ""
                // Presentation embellishments can contain decisive steps.
                request["presentationEnhancements"] = [String: Any]()
                request["retentionTargets"] = [Any]()
                safe["request"] = request; safe["checkpoint"] = checkpoint; safe["status"] = "migrationRecovery"
                return safe
            }
            local["snapshots"] = (local["snapshots"] as? [[String: Any]] ?? []).filter {
                !protectedAttempts.contains(identity($0["attemptID"])) && !protected($0["exercise"] as? [String: Any] ?? [:])
            }
            local["savedSets"] = (local["savedSets"] as? [[String: Any]] ?? []).compactMap { set -> [String: Any]? in
                var safe = set
                if var result = set["result"] as? [String: Any] {
                    let original = result["questions"] as? [[String: Any]] ?? []
                    let questions = original.filter { !protectedQuestion($0) }
                    // An empty typed saved set is not a writable recovery set.
                    if !original.isEmpty && questions.isEmpty { return nil }
                    result["questions"] = questions
                    safe["result"] = result
                }
                return safe
            }
            let privateRuns = portablePrivateRuns(local["privateStudyRuns"] as? [[String: Any]] ?? [], protectedItems: protectedItemIDs)
            local["privateStudyRuns"] = privateRuns.rows
            local["unavailablePrivateRunIDs"] = Array(Set((local["unavailablePrivateRunIDs"] as? [String] ?? []) + privateRuns.unavailable)).sorted()
            local["evidenceDispositions"] = (local["evidenceDispositions"] as? [[String: Any]] ?? []).map { row in
                guard protectedAttempts.contains(identity(row["attemptID"])) else { return row }
                var safe = allow(row, "id attemptID revision policyVersion occurredAt disposition supersedesDispositionID")
                safe["reason"] = "Protected response retained; evaluator unavailable."
                return safe
            }
            archive["localLearning"] = local
        }
        return try JSONSerialization.data(withJSONObject: archive, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
    }

    nonisolated private static func portableProtectedRow(_ row: [String: Any]) -> Bool {
        (row["protectedReceipt"] != nil && !(row["protectedReceipt"] is NSNull))
            || row["assessmentProtected"] as? Bool == true
            || ["baseline", "assessmentHoldout"].contains(row["purpose"] as? String ?? "")
            || ["assessmentHoldout", "nearTransfer"].contains(row["evidenceClass"] as? String ?? row["evidenceClassRaw"] as? String ?? "")
            || ["baseline", "reassessment"].contains(row["sessionSource"] as? String ?? row["sessionSourceRaw"] as? String ?? row["source"] as? String ?? "")
            || row["errorCode"] as? String == "protected_evaluator_unavailable"
            || (row["assessmentBlock"] != nil && !(row["assessmentBlock"] is NSNull))
            || (row["assessmentBlockRaw"] != nil && !(row["assessmentBlockRaw"] is NSNull))
    }

    /// Preserve only anonymous reservation positions after removing a protected
    /// run. Snapshot aliases propagate restriction to every referring run: a
    /// second ordinary label never makes the same evaluator payload portable.
    nonisolated private static func portableLearningGraph(_ original: [String: Any],
        attempts: [[String: Any]], checkpoints: [[String: Any]]) ->
        (local: [String: Any], attempts: Set<String>, sessions: Set<String>, items: Set<String>) {
        func id(_ value: Any?) -> String { (value as? String ?? "").lowercased() }
        func object(_ value: Any?) -> [String: Any] { value as? [String: Any] ?? [:] }
        func rows(_ value: Any?) -> [[String: Any]] { value as? [[String: Any]] ?? [] }
        let supportedKeys = Set("schemaVersion sessions snapshots savedSets privateStudyRuns evidenceDispositions contentCorrections attemptConflicts withheldProtectedConflictAttemptIDs activeContentCorrectionIDs selectionLedger transactionRevision offlineRotationLedger rotationMigration fixedLaunchReceipts adaptiveItemReceipts editorialOverrideCommands retiredOrdinaryDrafts deletedAdaptiveRunIDs deletedFixedLaunchCommandIDs dismissedCorrectionIDs unavailablePrivateRunIDs unavailableHistorySnapshots".split(separator: " ").map(String.init))
        var local = original.filter { supportedKeys.contains($0.key) }
        var protectedAttempts = Set((original["withheldProtectedConflictAttemptIDs"] as? [String] ?? []).map { $0.lowercased() })
        protectedAttempts.formUnion(rows(original["unavailableHistorySnapshots"]).filter {
            $0["reason"] as? String == "protectedContent"
        }.map { id($0["attemptID"]) })
        var protectedSessions = Set((attempts + checkpoints).filter(portableProtectedRow).map { id($0["sessionID"]) })
        var protectedItems = Set<String>()
        for snapshot in rows(original["snapshots"]) where portableProtectedRow(object(snapshot["exercise"])) {
            protectedAttempts.insert(id(snapshot["attemptID"]))
            protectedItems.insert(object(snapshot["exercise"])["id"] as? String ?? "")
        }
        for conflict in rows(original["attemptConflicts"]) {
            let left = object(conflict["original"]), right = object(conflict["proposed"])
            if portableProtectedRow(left) || portableProtectedRow(right)
                || portableProtectedRow(object(conflict["originalExercise"])) || portableProtectedRow(object(conflict["proposedExercise"])) {
                protectedAttempts.insert(id(conflict["attemptID"]))
                protectedSessions.formUnion([id(left["sessionID"]), id(right["sessionID"])])
                for exercise in [object(conflict["originalExercise"]), object(conflict["proposedExercise"])] {
                    if let item = exercise["id"] as? String, !item.isEmpty { protectedItems.insert(item) }
                }
            }
        }
        let runs = rows(original["sessions"])
        let retired = object(original["retiredOrdinaryDrafts"])
        for run in runs {
            let checkpoint = object(run["checkpoint"]), descriptor = object(checkpoint["descriptor"])
            if portableProtectedRow(object(run["request"])) || portableProtectedRow(object(checkpoint["exercise"]))
                || (descriptor["role"] as? String).map({ $0 != "practice" }) == true {
                protectedSessions.insert(id(run["id"]))
            }
        }
        for row in attempts where portableProtectedRow(row) { protectedAttempts.insert(id(row["id"])) }
        let rawLedger = object(original["selectionLedger"])
        var ledger: NFSelectionReservationLedger?
        if rawLedger["schemaVersion"] as? Int == 1 {
            ledger = portableDecode(NFSelectionReservationLedger.self, object: rawLedger)
        }
        var fingerprintRuns: [String: Set<String>] = [:]
        var runFingerprints: [String: Set<String>] = [:]
        var runAttempts: [String: Set<String>] = [:]
        var blockedFingerprints = Set<String>()
        var fingerprintItems: [String: String] = [:]
        if let ledger {
            for snapshot in ledger.snapshots.values {
                let digest = NFReservationSnapshot.digest(snapshot.payload)
                guard snapshot.payload.count <= NFSelectionReservationPolicy.maximumSnapshotBytes,
                      snapshot.digest == digest,
                      let payload = try? JSONSerialization.jsonObject(with: snapshot.payload),
                      let exercise = portableDecode(NFExercise.self, object: payload),
                      NFExerciseSchemaValidator.supportsExerciseSchemaVersion(exercise.schemaVersion),
                      let canonical = portableObject(exercise), portableKnownKeys(payload, canonical),
                      !portableProtectedRow(object(payload)) else {
                    blockedFingerprints.formUnion([snapshot.digest, digest])
                    continue
                }
                fingerprintItems[snapshot.digest] = exercise.id; fingerprintItems[digest] = exercise.id
                if protectedItems.contains(exercise.id) { blockedFingerprints.formUnion([snapshot.digest, digest]) }
            }
            for (key, slot) in ledger.slots {
                let run = id(slot.runID)
                runAttempts[run, default: []].insert(id(slot.attemptID))
                guard key == slot.id, let owner = ledger.runs[slot.runID], owner.id == slot.runID,
                      owner.slotIDs.contains(slot.id), let snapshot = NFSelectionReservationPolicy.snapshot(for: slot, in: ledger),
                      slot.snapshotDigest == snapshot.digest else { protectedSessions.insert(run); continue }
                let fingerprints: Set<String> = [snapshot.digest, NFReservationSnapshot.digest(snapshot.payload)]
                runFingerprints[run, default: []].formUnion(fingerprints)
                for fingerprint in fingerprints { fingerprintRuns[fingerprint, default: []].insert(run) }
            }
        } else if original["selectionLedger"] != nil && !(original["selectionLedger"] is NSNull) {
            // Unknown or malformed payload graphs cannot be copied as opaque
            // base64. Keep supported anonymous scope state only, never runs.
            protectedSessions.formUnion(runs.map { id($0["id"]) })
            protectedSessions.formUnion(object(rawLedger["runs"]).keys.map { $0.lowercased() })
            for slot in object(rawLedger["slots"]).values.map(object) {
                protectedAttempts.insert(id(slot["attemptID"]))
                protectedSessions.insert(id(slot["runID"]))
            }
            if rawLedger["schemaVersion"] as? Int == 1 {
                var anonymous = NFSelectionReservationLedger()
                for (key, value) in object(rawLedger["scopes"]) {
                    if let scope = portableDecode(NFReservationScopeState.self, object: value) { anonymous.scopes[key] = scope }
                }
                ledger = anonymous
            }
        }
        // Close both attempt/session links and shared snapshot aliases. Every
        // iteration adds an identity; imported case differences cannot evade it.
        protectedAttempts.remove(""); protectedSessions.remove("")
        var changed = true
        while changed {
            let before = (protectedAttempts.count, protectedSessions.count, blockedFingerprints.count, protectedItems.count)
            for snapshot in rows(original["snapshots"]) {
                let exercise = object(snapshot["exercise"]), itemID = exercise["id"] as? String ?? ""
                if protectedAttempts.contains(id(snapshot["attemptID"])), !itemID.isEmpty { protectedItems.insert(itemID) }
                if protectedItems.contains(itemID), !id(snapshot["attemptID"]).isEmpty { protectedAttempts.insert(id(snapshot["attemptID"])) }
            }
            for run in runs {
                let checkpoint = object(run["checkpoint"])
                if protectedItems.contains(object(checkpoint["exercise"])["id"] as? String ?? "") { protectedSessions.insert(id(run["id"])) }
                if (!id(checkpoint["attemptID"]).isEmpty && protectedAttempts.contains(id(checkpoint["attemptID"])))
                    || (!id(checkpoint["committedAttemptID"]).isEmpty && protectedAttempts.contains(id(checkpoint["committedAttemptID"]))) {
                    protectedSessions.insert(id(run["id"]))
                }
                if protectedSessions.contains(id(run["id"])) {
                    let item = object(checkpoint["exercise"])["id"] as? String ?? ""
                    if !item.isEmpty { protectedItems.insert(item) }
                    protectedAttempts.formUnion([id(checkpoint["attemptID"]), id(checkpoint["committedAttemptID"])].filter { !$0.isEmpty })
                }
            }
            for value in retired.values.map(object) {
                let checkpoint = object(value["checkpoint"])
                if protectedAttempts.contains(id(checkpoint["attemptID"])) { protectedSessions.insert(id(value["sessionID"])) }
                if protectedSessions.contains(id(value["sessionID"])), !id(checkpoint["attemptID"]).isEmpty { protectedAttempts.insert(id(checkpoint["attemptID"])) }
            }
            for row in attempts {
                if protectedAttempts.contains(id(row["id"])) { protectedSessions.insert(id(row["sessionID"])) }
                if protectedSessions.contains(id(row["sessionID"])), !id(row["id"]).isEmpty { protectedAttempts.insert(id(row["id"])) }
            }
            for (run, ids) in runAttempts {
                if !ids.isDisjoint(with: protectedAttempts) { protectedSessions.insert(run) }
                if protectedSessions.contains(run) { protectedAttempts.formUnion(ids) }
            }
            for run in protectedSessions { blockedFingerprints.formUnion(runFingerprints[run] ?? []) }
            for fingerprint in blockedFingerprints {
                protectedSessions.formUnion(fingerprintRuns[fingerprint] ?? [])
                if let item = fingerprintItems[fingerprint] { protectedItems.insert(item) }
            }
            changed = before != (protectedAttempts.count, protectedSessions.count, blockedFingerprints.count, protectedItems.count)
        }
        protectedAttempts.remove(""); protectedSessions.remove(""); protectedItems.remove("")
        for row in attempts where protectedAttempts.contains(id(row["id"])) { protectedItems.insert(row["itemID"] as? String ?? "") }
        if var safe = ledger {
            let removedRuns = Set(safe.runs.keys.filter { protectedSessions.contains(id($0)) })
            let retainedSlotIDs = Set(safe.slots.values.filter { !protectedSessions.contains(id($0.runID)) }.map(\.id))
            safe.runs = safe.runs.filter { !removedRuns.contains($0.key) }
            safe.slots = safe.slots.filter { retainedSlotIDs.contains($0.key) }
            safe.decisions = safe.decisions.filter { !protectedSessions.contains(id($0.value.command.runID))
                && $0.value.acceptedSlotIDs.allSatisfy(retainedSlotIDs.contains) }
            safe.exposures = safe.exposures.filter { retainedSlotIDs.contains($0.value.slotID) && !protectedSessions.contains(id($0.value.runID)) }
            safe.outcomes = safe.outcomes.filter { retainedSlotIDs.contains($0.value.slotID) && !protectedSessions.contains(id($0.value.runID)) }
            let retainedSnapshots = safe.slots.values.compactMap { NFSelectionReservationPolicy.snapshot(for: $0, in: safe) }
            safe.snapshots = safe.snapshots.filter { retainedSnapshots.contains($0.value) && !blockedFingerprints.contains($0.value.digest) }
            safe.legacyReservationOwners = safe.legacyReservationOwners.filter { !protectedSessions.contains(id($0.value)) }
            safe.legacyPlans = safe.legacyPlans.filter { safe.legacyReservationOwners[$0.key] != nil }
            if var encoded = portableObject(safe) as? [String: Any] {
                var exposures = encoded["exposures"] as? [String: [String: Any]] ?? [:]
                let originals = rawLedger["exposures"] as? [String: [String: Any]] ?? [:]
                for key in exposures.keys {
                    // Final archives use ISO dates; local typed projections use
                    // exact numeric dates. Preserve the caller's representation.
                    if let date = originals[key]?["occurredAt"] { exposures[key]?["occurredAt"] = date }
                }
                encoded["exposures"] = exposures
                local["selectionLedger"] = encoded
            } else { local.removeValue(forKey: "selectionLedger") }
        } else { local.removeValue(forKey: "selectionLedger") }
        local["withheldProtectedConflictAttemptIDs"] = protectedAttempts.sorted()
        local["retiredOrdinaryDrafts"] = retired.filter { !protectedSessions.contains(id(object($0.value)["sessionID"])) }
        local["attemptConflicts"] = rows(original["attemptConflicts"]).filter { !protectedAttempts.contains(id($0["attemptID"])) }
        let corrections = rows(original["contentCorrections"])
        let removedCorrections = Set(corrections.filter { protectedAttempts.contains(id($0["originalAttemptID"])) }
            .compactMap { $0["idempotencyKey"] as? String })
        local["contentCorrections"] = corrections.filter { !protectedAttempts.contains(id($0["originalAttemptID"])) }
        local["activeContentCorrectionIDs"] = object(original["activeContentCorrectionIDs"]).filter {
            !protectedAttempts.contains(id($0.key))
        }.mapValues { ($0 as? [String] ?? []).filter { !removedCorrections.contains($0) } }
        // Imported launch receipts may retain future evaluator payload fields.
        // Device-local continuation authority is never portable.
        for key in ["offlineRotationLedger", "rotationMigration", "fixedLaunchReceipts", "deletedFixedLaunchCommandIDs",
                    "adaptiveItemReceipts", "editorialOverrideCommands", "deletedAdaptiveRunIDs", "transactionRevision"] { local.removeValue(forKey: key) }
        return (local, protectedAttempts, protectedSessions, protectedItems)
    }

    nonisolated private static func portablePrivateRuns(_ rows: [[String: Any]], protectedItems: Set<String>) ->
        (rows: [[String: Any]], unavailable: [String]) {
        var safe: [[String: Any]] = [], unavailable: [String] = []
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        for row in rows {
            let identity = row["id"] as? String ?? ""
            guard let id = UUID(uuidString: identity), let generation = (row["generationID"] as? String).flatMap(UUID.init(uuidString:)),
                  let base64 = row["payload"] as? String, base64.utf8.count <= 12 * 1_024 * 1_024,
                  let data = Data(base64Encoded: base64), data.count <= 8 * 1_024 * 1_024 else {
                if UUID(uuidString: identity) != nil { unavailable.append(identity) }; continue
            }
            let canonical: Data?
            if id == NFPrivateStudyMetadata.recordID {
                if let metadata = try? JSONDecoder().decode(NFPrivateStudyMetadata.self, from: data), metadata.isSupported, generation == id {
                    canonical = try? encoder.encode(metadata)
                } else { canonical = nil }
            } else if let draft = try? JSONDecoder().decode(NFGeneratedPracticeDraft.self, from: data),
                      draft.valid, draft.id == id, draft.result.provenance.requestID == generation,
                      !draft.result.questions.contains(where: { question in
                          protectedItems.contains(question.id) || protectedItems.contains(question.authoritativeExercise.id)
                              || question.authoritativeExercise.assessmentProtected
                              || [.assessmentHoldout, .nearTransfer].contains(question.authoritativeExercise.evidenceClass)
                      }), !protectedItems.contains(draft.lastScore?.exerciseID ?? "") {
                canonical = try? encoder.encode(draft)
            } else { canonical = nil }
            guard let canonical,
                  let originalObject = try? JSONSerialization.jsonObject(with: data),
                  let canonicalObject = try? JSONSerialization.jsonObject(with: canonical),
                  portableKnownKeys(originalObject, canonicalObject) else { unavailable.append(identity); continue }
            var retained = row.filter { ["id", "generationID", "payload", "updatedAt"].contains($0.key) }
            retained["payload"] = canonical.base64EncodedString()
            safe.append(retained)
        }
        return (safe, unavailable)
    }

    nonisolated private static func portableDecode<T: Decodable>(_ type: T.Type, object: Any) -> T? {
        guard JSONSerialization.isValidJSONObject(object), let bytes = try? JSONSerialization.data(withJSONObject: object) else { return nil }
        let decoder = JSONDecoder()
        if let value = try? decoder.decode(type, from: bytes) { return value }
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(type, from: bytes)
    }
    nonisolated private static func portableObject<T: Encodable>(_ value: T) -> Any? {
        let encoder = JSONEncoder()
        guard let data = try? encoder.encode(value) else { return nil }
        return try? JSONSerialization.jsonObject(with: data)
    }
    nonisolated private static func portableKnownKeys(_ original: Any, _ canonical: Any) -> Bool {
        if let object = original as? [String: Any] {
            guard let known = canonical as? [String: Any] else { return false }
            return object.allSatisfy { key, value in
                if value is NSNull { return true }
                guard let expected = known[key] else { return false }
                return portableKnownKeys(value, expected)
            }
        }
        if let values = original as? [Any] {
            guard let known = canonical as? [Any], values.count == known.count else { return false }
            return zip(values, known).allSatisfy { portableKnownKeys($0.0, $0.1) }
        }
        return true
    }

    /// Apply the same defense at the local portable boundary and at the final
    /// raw JSON import/export boundary. Neither projection edits local originals.
    static func protectedLocalLearningArchive(_ archive: NFLocalSessionRepository.Archive) -> NFLocalSessionRepository.Archive {
        guard let local = portableObject(archive),
              let bytes = try? JSONSerialization.data(withJSONObject: ["localLearning": local]),
              let redacted = try? protectedPortableData(bytes),
              let root = try? JSONSerialization.jsonObject(with: redacted) as? [String: Any],
              let safe = root["localLearning"],
              let value = portableDecode(NFLocalSessionRepository.Archive.self, object: safe) else {
            // An unencodable local recovery value cannot safely become portable.
            var unavailable = NFLocalSessionRepository.Archive()
            unavailable.withheldProtectedConflictAttemptIDs = archive.withheldProtectedConflictAttemptIDs
            unavailable.unavailableHistorySnapshots = archive.unavailableHistorySnapshots
            return unavailable
        }
        return value
    }

    private static func isProtected(_ attempt: AttemptRecord) -> Bool {
        attempt.evidenceClassRaw == EvidenceClass.assessmentHoldout.rawValue
            || attempt.sessionSourceRaw == SessionSource.baseline.rawValue
            || attempt.sessionSourceRaw == SessionSource.reassessment.rawValue
            || attempt.errorCode == "protected_evaluator_unavailable"
    }

    private static func isProtected(_ attempt: AttemptRecord, store: AppStore) -> Bool {
        isProtected(attempt)
            || store.localSessions.archive.snapshots.first { $0.attemptID == attempt.id }?.exercise.assessmentProtected == true
            || store.localSessions.archive.unavailableHistorySnapshots?.contains {
                $0.attemptID == attempt.id && $0.reason == .protectedContent
            } == true || store.localSessions.archive.withheldProtectedConflictAttemptIDs?.contains(attempt.id) == true
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
            },
            localLearning: store.localSessions.exportArchive
        )
    }

    private static func portableProtectedIdentities(_ store: AppStore) -> (attempts: Set<String>, items: Set<String>) {
        let rows: [[String: Any]] = store.attempts.map { attempt in
            var row: [String: Any] = ["id": attempt.id.uuidString, "sessionID": attempt.sessionID.uuidString,
                "itemID": attempt.itemID, "evidenceClassRaw": attempt.evidenceClassRaw,
                "sessionSourceRaw": attempt.sessionSourceRaw]
            if let errorCode = attempt.errorCode { row["errorCode"] = errorCode }
            if let block = attempt.assessmentBlockRaw { row["assessmentBlockRaw"] = block }
            return row
        }
        let local = portableObject(store.localSessions.archive) as? [String: Any] ?? [:]
        let graph = portableLearningGraph(local, attempts: rows, checkpoints: [])
        return (graph.attempts, graph.items)
    }

    private static func makeSummaryCSV(_ store: AppStore) -> String {
        let protectedIDs = portableProtectedIdentities(store).attempts
        var lines = ["lab,evidence_class,scorable_attempts,skipped,fully_correct,earned_credit_percent,last_activity"]
        for lab in TrainingLab.allCases {
            for evidence in EvidenceClass.allCases {
                let attempts = store.attempts.filter { $0.gameID == lab.rawValue && $0.evidenceClassRaw == evidence.rawValue }
                guard !attempts.isEmpty else { continue }
                let scorable = attempts.filter { !$0.wasSkipped && $0.evidenceWeight > 0 }
                let skipped = attempts.filter(\.wasSkipped).count
                let protected = attempts.contains { protectedIDs.contains($0.id.uuidString.lowercased()) || isProtected($0, store: store) }
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
                    protected ? "" : String(scorable.count),
                    String(skipped),
                    protected ? "" : String(correct),
                    protected ? "" : accuracy.formatted(.number.precision(.fractionLength(2))),
                    last
                ].map(csvEscape).joined(separator: ","))
            }
        }
        return lines.joined(separator: "\n") + "\n"
    }

    private static func makeGeneratedQuestionsExport(_ store: AppStore) -> GeneratedQuestionsExport {
        let protectedItems = portableProtectedIdentities(store).items
        let exportedAt = Date()
        let generations = store.aiGenerations
            .sorted {
                if $0.createdAt == $1.createdAt { return $0.id.uuidString < $1.id.uuidString }
                return $0.createdAt < $1.createdAt
            }
            .map { record in
                let result = record.recoverableResult(at: exportedAt)
                let permittedQuestions = result?.questions.filter {
                    !$0.authoritativeExercise.assessmentProtected && ![.assessmentHoldout, .nearTransfer].contains($0.evidenceClass)
                        && !protectedItems.contains($0.id) && !protectedItems.contains($0.authoritativeExercise.id)
                } ?? []
                let payloadState: String
                if permittedQuestions.count != (result?.questions.count ?? 0) {
                    payloadState = "protected_receipts_only"
                } else if result != nil {
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
                    exportedQuestionCount: permittedQuestions.count,
                    routeCandidates: result?.routeCandidates ?? [],
                    validationStatus: result?.validationStatus,
                    validationNotes: result?.validationNotes ?? [],
                    questions: permittedQuestions.map {
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
                    }
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
        let protectedIDs = portableProtectedIdentities(store).attempts
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
            let protected = protectedIDs.contains(attempt.id.uuidString.lowercased()) || isProtected(attempt, store: store)
            let wasEvaluated = !attempt.wasSkipped && !protected && !["selfCheck", "sourceSelfCheck"].contains(attempt.responseFormatRaw)
            let countsAsEvidence = wasEvaluated && attempt.evidenceWeight > 0
            let outcome: String
            if protected {
                outcome = "protected_response_saved"
            } else if ["selfCheck", "sourceSelfCheck"].contains(attempt.responseFormatRaw) {
                outcome = "self_reported_personal_study"
            } else if attempt.wasSkipped {
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
                !attempt.wasSkipped ? attempt.response : "",
                !attempt.wasSkipped && !protected ? attempt.correctAnswerText : "",
                !attempt.wasSkipped ? attempt.confidenceRaw ?? "" : "",
                outcome,
                wasEvaluated ? String(attempt.isCorrect) : "",
                wasEvaluated ? String(attempt.deterministicCredit) : "",
                protected ? "" : String(max(0, attempt.evidenceWeight)),
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

    struct Archive: Codable, Sendable {
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
        var localLearning: NFLocalSessionRepository.Archive? = nil
        var aiLearningArtifacts: [NFAILearningArtifactFile]? = nil
    }
    struct Profile: Codable, Sendable {
        let id: UUID; let createdAt: Date; let modifiedAt: Date; let stage: String; let fields: [String]; let goals: [String]
        let dailyDuration: Int; let timingMode: String; let aiMode: String; let iCloudEnabled: Bool; let reducedMotion: Bool
        let hideTimers: Bool; let excludeVisualSpatial: Bool; let onboardingVersion: Int
        let claimsPolicyAcknowledgedVersion: Int; let pccConsentVersion: Int
        let pccConsentAt: Date?; let preferredLanguageCode: String; let trainingDays: [String]
        let dayBoundaryHour: Int; let ageBandAcknowledged16Plus: Bool; let preferredAnswerMode: String
        let reinforcementHapticsEnabled: Bool; let reinforcementSoundEnabled: Bool
    }
    struct Attempt: Codable, Sendable {
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
        var protectedReceipt: ProtectedReceipt? = nil
    }
    struct AttemptReflection: Codable, Sendable {
        let id: UUID; let attemptID: UUID; let deterministicErrorCode: String?; let selectedErrorCode: String?
        let trigger: String; let note: String; let createdAt: Date; let policyVersion: Int
    }
    struct Document: Codable, Sendable {
        let id: UUID; let filename: String; let typeIdentifier: String; let sizeBytes: Int64; let importedAt: Date
        let indexState: String; let aiPolicy: String; let syncPolicy: String
        let pccExcerptConsentPolicyVersion: Int; let pccExcerptConsentDocumentID: String; let pccExcerptConsentedAt: Date?
        let characterCount: Int; let chunkCount: Int
        let extractionVersion: Int; let csvSelectedColumnIDs: [String]; let indexError: String?
    }
    struct Chunk: Codable, Sendable {
        let id: String; let documentID: UUID; let documentVersion: Int; let sourceName: String; let page: Int?
        let lineStart: Int?; let lineEnd: Int?; let section: String?; let text: String; let contentHash: String; let ordinal: Int
        let characterStart: Int?; let characterEnd: Int?; let nearbyHeading: String?; let language: String?
        let contentTypeTags: [String]
    }
    struct Generation: Codable, Sendable {
        let id: UUID; let createdAt: Date; let capability: String; let lab: String; let field: String; let topic: String
        let route: String; let routeReason: String; let promptVersion: Int; let validationVersion: Int; let modelIdentifier: String
        let sourceDocumentIDs: [String]; let sourceChunkIDs: [String]; let repairCount: Int; let cacheKey: String
        let isFallback: Bool; let questionCount: Int; let payloadExpiresAt: Date; let questions: [NFAuthoredQuestion]
        let routeCandidates: [NFAIRouteSnapshot]?
        let validationStatus: NFAuthoringValidationStatus?
        let validationNotes: [String]?
    }
    struct Checkpoint: Codable, Sendable {
        let id: UUID; let sessionID: UUID; let lab: String; let source: String; let seed: UInt64
        let currentIndex: Int; let itemCount: Int; let response: String; let scratchpad: String
        let results: [String]; let evidenceClass: String; let updatedAt: Date; let isComplete: Bool
        let credits: [String]; let assessmentDescriptorIDs: [String]; let assessmentEvents: [String]
        let planID: String?; let planBlockID: String?; let recommendationRationale: String?
        let hasCommittedCurrentItem: Bool
        let assessmentBlock: String?; let assessmentCycle: Int?; let activeDurationSeconds: Double; let assessmentStopReason: String?
        let pendingReflectionAttemptID: UUID?; let reflectionTrigger: String?; let selectedReflectionCode: String?; let reflectionNote: String?
        var protectedReceipt: ProtectedReceipt? = nil
    }
    struct DailyPlan: Codable, Sendable {
        let id: String; let profileID: UUID; let localDayKey: String; let policyVersion: Int
        let canonicalPayloadBase64: String; let createdAt: Date; let timeZoneIdentifier: String
        let utcOffsetSeconds: Int; let dayBoundaryHour: Int; let boundaryStart: Date; let nextBoundaryAt: Date
        let travelPreservedUntil: Date?
    }
    struct InputCalibration: Codable, Sendable {
        let id: UUID; let profileID: UUID; let completedAt: Date; let preferredAnswerMode: String
        let keyboardLatencyMilliseconds: Double?; let touchLatencyMilliseconds: Double?; let pencilLatencyMilliseconds: Double?
    }
    struct ProgressAnnotation: Codable, Sendable {
        let id: UUID; let startDate: Date; let endDate: Date; let note: String; let createdAt: Date; let modifiedAt: Date
    }
    struct Report: Codable, Sendable {
        let id: UUID; let itemID: String; let templateID: String; let prompt: String; let reason: String
        let note: String; let createdAt: Date; let status: String; let seed: UInt64
        let generatorVersion: Int; let provenanceSummary: String; let sourceIDs: [String]
        let sourceChunkIDs: [String]; let assessmentDescriptorID: String?
        let diagnosticPayloadState: String; let diagnosticDigest: String; let diagnosticPayloadBytes: Int
        let authoredDiagnostic: NFAuthoredReportDiagnostic?
    }
}

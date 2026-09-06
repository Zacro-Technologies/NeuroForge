import Foundation

/// Bridges acknowledged local checkpoints to ordinary-practice receipts. This
/// records actual captured slots. The repository owns fixed-launch authority;
/// this bridge never manufactures exposure for old resumed drafts.
enum NFLocalReservationBridge {
    static func accepting(envelope: NFLocalSessionEnvelope, previous: NFLocalSessionEnvelope? = nil,
                          ledger original: NFSelectionReservationLedger,
                          adaptiveReceipt: NFLocalAdaptiveItemReceipt? = nil) throws -> NFSelectionReservationLedger {
        if let pin = envelope.request.ordinaryDelivery {
            guard pin.isSupported else { throw NFLocalSessionRepository.RepositoryError.unsupportedVersion }
            if pin.strategy == .adaptiveItem {
                guard let adaptiveReceipt else { throw NFReservationError.conflictingDecision }
                return try acceptingAdaptive(envelope: envelope, previous: previous, receipt: adaptiveReceipt, ledger: original)
            }
        }
        guard let exercise = ordinaryExercise(in: envelope) else { return original }
        guard envelope.checkpoint.index >= 0,
              envelope.checkpoint.exerciseDigest == (try NFLocalItemCheckpoint.digest(exercise)) else { throw NFReservationError.invalidSnapshot }
        if let previous {
            guard previous.id == envelope.id, previous.ownerDeviceID == envelope.ownerDeviceID else { throw NFReservationError.wrongOwner }
        }
        var state = original
        let runID = envelope.id.uuidString
        let ownerID = envelope.ownerDeviceID.uuidString
        let current = envelope.checkpoint
        if let pin = state.runs[runID]?.versions.presentationVersion {
            guard NFSessionPresentationPolicy.supportedVersions.contains(pin) else {
                throw NFLocalSessionRepository.RepositoryError.unsupportedVersion
            }
        }
        // A prepared skip is only intent. Advancement (or the terminal event on
        // the same last slot) follows the existing attempt-store acknowledgement.
        if let prior = previous?.checkpoint, state.slots[prior.slotID.uuidString] != nil {
            let advanced = current.index == prior.index + 1 && current.slotID != prior.slotID
            let terminalSkip = current.phase == .summary && current.slotID == prior.slotID
                && current.pendingOutcome == nil && current.assessmentEvents.contains {
                    $0 == "skipped:\(prior.exercise?.id ?? "")" || $0 == "revealed:\(prior.exercise?.id ?? "")"
                }
            if let attempt = prior.committedAttemptID {
                state = try outcome(.answered, slotID: prior.slotID.uuidString, attemptID: attempt.uuidString,
                    runID: runID, ownerID: ownerID, ledger: state)
            } else if (advanced || terminalSkip), ["skip", "reveal"].contains(prior.pendingOutcome ?? "") {
                state = try outcome(prior.pendingOutcome == "reveal" ? .revealed : .skipped,
                    slotID: prior.slotID.uuidString, attemptID: prior.attemptID.uuidString,
                    runID: runID, ownerID: ownerID, ledger: state)
            }
        }

        if let slot = state.slots[current.slotID.uuidString] {
            guard slot.runID == runID, slot.attemptID == current.attemptID.uuidString,
                  slot.plannedQuestionOrdinal == current.index, slot.snapshotDigest == current.exerciseDigest,
                  state.runs[runID]?.ownerDeviceID == ownerID,
                  state.runs[runID]?.configurationDigest == (try configurationDigest(envelope.request)) else { throw NFReservationError.conflictingDecision }
        } else {
            let plan = usablePlan(in: envelope)
            let scope = makeScope(envelope: envelope, exercise: exercise, plan: plan)
            let fingerprint = try plan.map { try digest($0) }
                ?? NFReservationSnapshot.digest(Data(NFSelectionReservationPolicy.identity([scope.key, "captured-slot-catalog.v1"]).utf8))
            let legacyPlan = plan.map {
                NFVerifiedLegacyReservationPlan(id: $0.id, scope: scope, catalogFingerprint: fingerprint,
                    positions: $0.items.map { .init(epoch: $0.epoch, ordinal: $0.epochOrdinal) },
                    candidateIDs: $0.items.map(\.questionID), sourceDigest: fingerprint)
            }
            if let legacyPlan {
                state = try NFSelectionReservationPolicy.registerRetainedPlan(legacyPlan, in: state)
            } else {
                state = try NFSelectionReservationPolicy.registerFreshScope(scope, catalogFingerprint: fingerprint,
                    verifiedEmptySourceID: "new-run-snapshot-recipe:\(runID)", in: state)
            }
            let payload = try encoded(exercise)
            let snapshot = NFReservationSnapshot(id: "snapshot." + current.exerciseDigest,
                digest: current.exerciseDigest, payload: payload,
                evaluationContractID: "exercise-evaluation.v\(current.scorerVersion ?? NFExerciseScoringEngine.scoringVersion)",
                evaluationContractDigest: current.exerciseDigest)
            let priorRun = state.runs[runID]
            let position = legacyPlan?.positions[current.index] ?? .init(epoch: 0, ordinal: current.index)
            let versions = NFReservationVersionPin(catalogFingerprint: fingerprint,
                generatorVersion: String(exercise.generatorVersion),
                selectionPolicyVersion: NFSelectionReservationPolicy.policyVersion,
                presentationVersion: priorRun?.versions.presentationVersion ?? NFSessionPresentationPolicy.version,
                scorerVersion: String(current.scorerVersion ?? NFExerciseScoringEngine.scoringVersion))
            let ordinal = priorRun?.nextDecisionOrdinal ?? 0
            let command = NFReservationCommand(decisionID: NFSelectionReservationPolicy.decisionID(runID: runID, ordinal: ordinal),
                runID: runID, ownerDeviceID: ownerID, scope: scope, versions: versions,
                configurationDigest: try configurationDigest(envelope.request),
                strategy: legacyPlan == nil ? .adaptiveItem : .fixedBlock,
                operation: priorRun == nil ? .launch : .next, decisionOrdinal: ordinal,
                intendedPathOrdinal: priorRun?.slotIDs.count ?? 0, plannedQuestionOrdinal: current.index,
                predecessorSlotID: priorRun?.slotIDs.last, fixedPlannedPositions: legacyPlan == nil ? [] : [position],
                legacyReservationID: legacyPlan?.id, intendedSlotIDs: [current.slotID.uuidString],
                intendedAttemptIDs: [current.attemptID.uuidString], launchQuestionOrdinal: current.index)
            let candidate = NFReservationCandidate(candidateID: legacyPlan?.candidateIDs[current.index] ?? exercise.id,
                semanticID: exercise.contractMetadata?.semanticFingerprint ?? NFQuestionFingerprint.fingerprint(for: exercise),
                position: position, snapshot: snapshot, rank: [0], tieKey: 0,
                selectionReason: legacyPlan == nil ? "captured-runtime-slot; no global novelty claim" : "retained-legacy-plan-position; legacy pre-reservation remains separate",
                eligibilityRevision: "ordinary-local-snapshot.v1", eligible: true, protectedContent: false)
            let acceptance = try NFSelectionReservationPolicy.prepareAcceptance(command: command, candidates: [candidate],
                state: state, expectedRevision: state.revision, legacyPlan: legacyPlan)
            state = try NFSelectionReservationPolicy.applying(acceptance, to: state)
        }
        if let attempt = current.committedAttemptID {
            guard attempt == current.attemptID else { throw NFReservationError.conflictingDecision }
            state = try outcome(.answered, slotID: current.slotID.uuidString, attemptID: attempt.uuidString,
                runID: runID, ownerID: ownerID, ledger: state)
        }
        if envelope.status == .completed || envelope.status == .endedEarly {
            state = try NFSelectionReservationPolicy.endRun(runID, ownerDeviceID: ownerID, in: state)
        }
        return state
    }

    private static func acceptingAdaptive(envelope: NFLocalSessionEnvelope, previous: NFLocalSessionEnvelope?,
                                          receipt: NFLocalAdaptiveItemReceipt, ledger original: NFSelectionReservationLedger) throws -> NFSelectionReservationLedger {
        let current = envelope.checkpoint
        guard let pin = envelope.request.ordinaryDelivery, pin.isSupported, pin.strategy == .adaptiveItem,
              let exercise = ordinaryExercise(in: envelope), current.index >= 0,
              receipt.isSupported, let operation = receipt.operation, let decisionOrdinal = receipt.effectiveDecisionOrdinal,
              receipt.sessionID == envelope.id, receipt.ownerDeviceID == envelope.ownerDeviceID,
              receipt.questionIndex == current.index, receipt.slotID == current.slotID, receipt.attemptID == current.attemptID,
              receipt.decisionID == current.ordinaryReservationDecisionID,
              receipt.configurationDigest == (try configurationDigest(envelope.request)),
              receipt.exerciseDigest == current.exerciseDigest, current.exerciseDigest == (try NFLocalItemCheckpoint.digest(exercise)),
              receipt.plan.profileID == pin.profileID, receipt.plan.bankVersion == pin.bankVersion,
              receipt.plan.lab == envelope.request.lab, receipt.plan.laneID == pin.laneID, receipt.plan.items.count == 1,
              let item = receipt.plan.items.first, item.quizOrdinal == 0,
              let ordinal = NFOfflineQuestionBank.ordinal(forQuestionID: item.questionID, lab: receipt.plan.lab) else {
            throw NFReservationError.conflictingDecision
        }
        if let slot = original.slots[current.slotID.uuidString] {
            // A previously accepted item is authenticated from its retained
            // contract. A newer generator must not re-create its old key.
            guard slot.candidateID == item.questionID,
                  let retained = NFSelectionReservationPolicy.snapshot(for: slot, in: original),
                  let originalExercise = try? JSONDecoder().decode(NFExercise.self, from: retained.payload),
                  originalExercise == exercise else { throw NFReservationError.conflictingDecision }
        } else {
            // A descriptor seed is the generator INPUT; NFExercise.seed is the
            // materialized, mixed seed. Authenticate the complete output via
            // the same canonical factory instead of equating unrelated seeds.
            let expected = NFDeterministicSessionExerciseFactory.makeExercise(
                request: envelope.request.launchOnly(offlineQuestionOrdinals: [ordinal]),
                index: 0, assessmentDescriptor: nil)
            guard expected.availabilityReason == nil, expected == exercise else { throw NFReservationError.conflictingDecision }
        }
        if let previous {
            guard previous.id == envelope.id, previous.ownerDeviceID == envelope.ownerDeviceID else { throw NFReservationError.wrongOwner }
        }
        let runID = envelope.id.uuidString, ownerID = envelope.ownerDeviceID.uuidString
        var state = original
        if let version = state.runs[runID]?.versions.presentationVersion,
           !NFSessionPresentationPolicy.supportedVersions.contains(version) { throw NFReservationError.unsupportedVersion }
        if let prior = previous?.checkpoint, state.slots[prior.slotID.uuidString] != nil {
            if let committed = prior.committedAttemptID {
                state = try outcome(.answered, slotID: prior.slotID.uuidString, attemptID: committed.uuidString,
                    runID: runID, ownerID: ownerID, ledger: state)
            } else if (current.index == prior.index + 1 || current.phase == .summary),
                      ["skip", "reveal"].contains(prior.pendingOutcome ?? ""),
                      current.assessmentEvents.contains("\(prior.pendingOutcome == "reveal" ? "revealed" : "skipped"):\(prior.exercise?.id ?? "")") {
                state = try outcome(prior.pendingOutcome == "reveal" ? .revealed : .skipped,
                    slotID: prior.slotID.uuidString, attemptID: prior.attemptID.uuidString,
                    runID: runID, ownerID: ownerID, ledger: state)
            }
        }
        if let existing = state.slots[current.slotID.uuidString] {
            guard existing.runID == runID, existing.attemptID == current.attemptID.uuidString,
                  existing.snapshotDigest == current.exerciseDigest, existing.decisionID == receipt.decisionID,
                  existing.plannedQuestionOrdinal == current.index,
                  state.runs[runID]?.configurationDigest == receipt.configurationDigest else { throw NFReservationError.conflictingDecision }
        } else {
            if operation == .replace {
                guard let prior = previous?.checkpoint, prior.phase == .item,
                      prior.committedAttemptID == nil, prior.result == nil, prior.pendingOutcome == nil,
                      prior.slotID == receipt.predecessorSlotID, prior.index == current.index,
                      state.runs[runID]?.slotIDs.last == prior.slotID.uuidString,
                      receipt.predecessorCheckpointDigest == (try NFLocalRetiredOrdinaryDraft.digest(prior)) else {
                    throw NFReservationError.conflictingDecision
                }
            }
            // This scope records this run's exact receipts. Shared consumption
            // belongs to the repository's atomically updated rotation ledger.
            let scope = NFReservationScope(profileID: pin.profileID.uuidString, labID: exercise.lab.rawValue,
                contentEditionID: "legacy-bank.\(pin.bankVersion)", laneID: "run:\(runID):\(pin.laneID)",
                privacyScopeID: "builtin-local", positionRecipeID: "adaptive-bank-occurrence.v1")
            state = try NFSelectionReservationPolicy.registerFreshScope(scope, catalogFingerprint: pin.bankFingerprint,
                verifiedEmptySourceID: "new-atomic-bank-run:\(runID)", in: state)
            let priorRun = state.runs[runID]
            if let pins = priorRun?.versions {
                guard pins.generatorVersion == String(exercise.generatorVersion),
                      pins.scorerVersion == String(current.scorerVersion ?? NFExerciseScoringEngine.scoringVersion) else {
                    throw NFLocalSessionRepository.RepositoryError.unsupportedVersion
                }
            }
            let versions = priorRun?.versions ?? NFReservationVersionPin(catalogFingerprint: pin.bankFingerprint,
                generatorVersion: String(exercise.generatorVersion), selectionPolicyVersion: NFSelectionReservationPolicy.policyVersion,
                presentationVersion: NFSessionPresentationPolicy.version,
                scorerVersion: String(current.scorerVersion ?? NFExerciseScoringEngine.scoringVersion))
            let command = NFReservationCommand(decisionID: receipt.decisionID, runID: runID, ownerDeviceID: ownerID,
                scope: scope, versions: versions, configurationDigest: receipt.configurationDigest,
                strategy: .adaptiveItem, operation: operation,
                decisionOrdinal: decisionOrdinal, intendedPathOrdinal: priorRun?.slotIDs.count ?? 0,
                plannedQuestionOrdinal: current.index, predecessorSlotID: receipt.predecessorSlotID?.uuidString,
                fixedPlannedPositions: [], intendedSlotIDs: [current.slotID.uuidString], intendedAttemptIDs: [current.attemptID.uuidString])
            let snapshot = NFReservationSnapshot(id: "snapshot." + current.exerciseDigest, digest: current.exerciseDigest,
                payload: try encoded(exercise), evaluationContractID: "exercise-evaluation.v\(current.scorerVersion ?? NFExerciseScoringEngine.scoringVersion)",
                evaluationContractDigest: current.exerciseDigest)
            let candidate = NFReservationCandidate(candidateID: item.questionID,
                semanticID: exercise.contractMetadata?.semanticFingerprint ?? NFQuestionFingerprint.fingerprint(for: exercise),
                position: .init(epoch: item.epoch, ordinal: item.epochOrdinal), snapshot: snapshot, rank: receipt.mixedDecision?.rankedFamilies.first?.values ?? [0],
                tieKey: receipt.mixedDecision?.rankedFamilies.first?.tieKey ?? receipt.editorialDecision?.selection.tieKey ?? item.stableOrdinal,
                selectionReason: receipt.editorialDecision?.selection.reason.rawValue
                    ?? "eligible-exact-bank-position; one-item-delivery; no reviewed-band claim",
                eligibilityRevision: receipt.eligibilityRevision, eligible: true, protectedContent: false)
            let accepted = try NFSelectionReservationPolicy.prepareAcceptance(command: command, candidates: [candidate],
                state: state, expectedRevision: state.revision)
            state = try NFSelectionReservationPolicy.applying(accepted, to: state)
        }
        if let committed = current.committedAttemptID {
            guard committed == current.attemptID else { throw NFReservationError.conflictingDecision }
            state = try outcome(.answered, slotID: current.slotID.uuidString, attemptID: committed.uuidString,
                runID: runID, ownerID: ownerID, ledger: state)
        }
        if envelope.status == .completed || envelope.status == .endedEarly {
            state = try NFSelectionReservationPolicy.endRun(runID, ownerDeviceID: ownerID, in: state)
        }
        return state
    }

    /// Called only after the visible item has acknowledged presentation. Saving
    /// or prewarming a snapshot never calls this API. Repeated render retains the
    /// first timestamp and event; migrated feedback does not invent an exposure.
    static func acknowledge(envelope: NFLocalSessionEnvelope, ledger: NFSelectionReservationLedger,
                            at date: Date) throws -> NFSelectionReservationLedger {
        guard ordinaryExercise(in: envelope) != nil, [.item, .confidence].contains(envelope.phase),
              let slot = ledger.slots[envelope.checkpoint.slotID.uuidString] else { return ledger }
        let eventID = "presentation." + slot.id
        let existing = ledger.exposures[eventID]
        guard existing != nil || slot.status == .reserved else { return ledger }
        guard slot.runID == envelope.id.uuidString, slot.snapshotDigest == envelope.checkpoint.exerciseDigest else { throw NFReservationError.conflictingDecision }
        return try NFSelectionReservationPolicy.acknowledgePresentation(eventID: eventID,
            runID: envelope.id.uuidString, slotID: slot.id, ownerDeviceID: envelope.ownerDeviceID.uuidString,
            presentationOrdinal: existing?.presentationOrdinal ?? ledger.exposures.values.filter { $0.runID == slot.runID }.count,
            occurredAt: date, in: ledger)
    }

    private static func outcome(_ status: NFReservationSlotStatus, slotID: String, attemptID: String,
                                runID: String, ownerID: String, ledger: NFSelectionReservationLedger) throws -> NFSelectionReservationLedger {
        guard let slot = ledger.slots[slotID], slot.attemptID == attemptID else { throw NFReservationError.conflictingDecision }
        let record = NFReservationOutcome(eventID: "outcome." + slotID, runID: runID, slotID: slotID, status: status)
        return try NFSelectionReservationPolicy.recordOutcome(record, ownerDeviceID: ownerID,
            acknowledgedAttemptID: attemptID, in: ledger)
    }
    private static func ordinaryExercise(in envelope: NFLocalSessionEnvelope) -> NFExercise? {
        guard let exercise = envelope.checkpoint.exercise, !exercise.assessmentProtected,
              exercise.evidenceClass != .documentPractice, envelope.request.evidenceClass != .documentPractice,
              envelope.request.assessmentBlock == nil, exercise.availabilityReason == nil else { return nil }
        if case .selfCheck = exercise.interaction { return nil }
        return exercise
    }
    private static func usablePlan(in envelope: NFLocalSessionEnvelope) -> NFOfflineQuestionRotationPlan? {
        guard envelope.request.mechanicID == nil, envelope.request.evidenceClass == .practice,
              envelope.request.transferBrief == nil, envelope.request.retentionTargets.isEmpty, let plan = envelope.request.offlineRotationPlan,
              plan.lab == envelope.request.lab, plan.items.indices.contains(envelope.index),
              envelope.request.offlineQuestionOrdinals.count == plan.items.count,
              plan.items.enumerated().allSatisfy({ $0.offset == $0.element.quizOrdinal &&
                  NFOfflineQuestionBank.ordinal(forQuestionID: $0.element.questionID, lab: plan.lab) == envelope.request.offlineQuestionOrdinals[$0.offset] }),
              let descriptor = NFOfflineQuestionBank.descriptor(for: plan.lab, ordinal: envelope.request.offlineQuestionOrdinals[envelope.index]),
              descriptor.seed == envelope.checkpoint.exercise?.seed,
              Set(plan.items.map { NFReservationPosition(epoch: $0.epoch, ordinal: $0.epochOrdinal) }).count == plan.items.count else { return nil }
        return plan
    }
    private static func makeScope(envelope: NFLocalSessionEnvelope, exercise: NFExercise,
                                  plan: NFOfflineQuestionRotationPlan?) -> NFReservationScope {
        .init(profileID: plan?.profileID.uuidString ?? "local-device:\(envelope.ownerDeviceID.uuidString)",
            labID: exercise.lab.rawValue,
            contentEditionID: plan.map { "legacy-bank.\($0.bankVersion)" } ?? exercise.contractMetadata?.contentEditionID ?? "legacy-generator.\(exercise.generatorVersion)",
            laneID: "run:\(envelope.id.uuidString):\(plan?.laneID ?? envelope.request.mechanicID ?? "mixed")",
            privacyScopeID: "builtin-local", positionRecipeID: plan == nil ? "snapshot-slot.v1" : "legacy-plan-occurrence.v1")
    }
    private static func encoded<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(value)
    }
    private static func digest<T: Encodable>(_ value: T) throws -> String { NFReservationSnapshot.digest(try encoded(value)) }
    static func configurationDigest(_ request: SessionRequest) throws -> String {
        // Codable Set order is unspecified. Canonicalize only the known set
        // fields; presentation order in every other array remains significant.
        let data = try encoded(request.launchOnly())
        guard var object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw NFReservationError.malformedIdentity }
        for key in ["repairSemanticExclusions", "quarantinedItemIDs", "quarantinedAssessmentDescriptorIDs"] {
            if let values = object[key] as? [String] { object[key] = values.sorted() }
        }
        return NFReservationSnapshot.digest(try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]))
    }
}

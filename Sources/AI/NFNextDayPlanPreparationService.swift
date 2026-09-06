import Foundation

enum NFPlanFieldAssignment {
    static func field(
        forBlockID blockID: String,
        in plan: DailyPlan,
        profile: ProfileSnapshot
    ) -> STEMField {
        let fields = profile.fields.sorted { $0.rawValue < $1.rawValue }
        guard !fields.isEmpty,
              let blockIndex = plan.blocks.firstIndex(where: { $0.id == blockID }) else {
            return fields.first ?? .general
        }
        let offset = Int(plan.seed % UInt64(fields.count))
        return fields[(blockIndex + offset) % fields.count]
    }
}

/// Shared identity boundary for foreground sessions and background preparation.
/// Both paths must derive the exact same deterministic exercise before optional
/// presentation text can be attached to its ID.
enum NFDeterministicSessionExerciseFactory {
    static func makeExercise(
        request: SessionRequest,
        index: Int,
        assessmentDescriptor: NFAssessmentItemDescriptor?,
        excludingContentFingerprints: Set<String> = []
    ) -> NFExercise {
        var unavailableLab = request.lab
        if let exercise = materializeExercise(request: request, index: index,
            assessmentDescriptor: assessmentDescriptor,
            excludingContentFingerprints: excludingContentFingerprints, unavailableLab: &unavailableLab) {
            return exercise
        }
        // Exhaustion and invalid requests need the same bounded placeholder,
        // but only after all candidate-construction frames have unwound. This
        // also keeps locale formatting within the cooperative worker's stack.
        return unavailableExercise(lab: unavailableLab, localeIdentifier: request.localeIdentifier)
    }

    @inline(never)
    private static func materializeExercise(
        request: SessionRequest,
        index: Int,
        assessmentDescriptor: NFAssessmentItemDescriptor?,
        excludingContentFingerprints: Set<String>,
        unavailableLab: inout TrainingLab
    ) -> NFExercise? {
        guard request.hasSupportedSpatialAssemblyPolicy else { return nil }
        guard request.hasSupportedCoordinateReasoningPolicy else { return nil }
        guard request.hasSupportedNetFoldingPolicy else { return nil }
        guard request.hasSupportedSolidSectionPolicy else { return nil }
        guard request.hasSupportedCoordinateTransformPolicy else { return nil }
        guard request.hasSupportedSpatialStructurePolicy else { return nil }
        guard request.hasSupportedRetrievalAssetPolicy else { return nil }
        guard request.hasSupportedRetrievalAuthorityPolicy else { return nil }
        guard request.hasSupportedTransferPolicy else { return nil }
        guard request.hasSupportedGraphConstructionPolicy else {
            return nil
        }
        guard request.scienceStudyPolicyVersion == nil || request.scienceStudyPolicyVersion == 1,
              request.scienceStudyExcludedContextID.map({ NFScienceStudyContract.contextIDs.contains($0) && request.scienceStudyPolicyVersion == 1 }) ?? true else {
            return nil
        }
        guard request.tracePolicyVersion == nil || request.tracePolicyVersion == 1 else {
            return nil
        }
        let purpose: NFExercisePurpose = if assessmentDescriptor?.role == .practice {
            .practice
        } else {
            switch request.evidenceClass {
            case .practice: .practice
            case .nearTransfer: .nearTransfer
            case .appliedTransfer: .appliedTransfer
            case .retention: .retention
            case .assessmentHoldout: request.source == .baseline ? .baseline : .assessmentHoldout
            case .documentPractice: .documentPractice
            }
        }
        let selectedLab = assessmentDescriptor?.lab ?? request.lab
        unavailableLab = selectedLab
        let transferBrief = assessmentDescriptor == nil ? request.transferBrief : nil
        let retentionTarget = assessmentDescriptor == nil && purpose == .retention
            ? request.retentionTarget(at: index)
            : nil
        let context = NFExerciseSourceContext(
            primaryField: request.field ?? .general,
            secondaryFields: [],
            topic: assessmentDescriptor?.mechanicID
                ?? request.assessmentBlock?.rawValue
                ?? request.topic
                ?? request.mechanicID,
            targetSkills: transferBrief?.skillIDs
                ?? [assessmentDescriptor?.skillID ?? request.lab.skillID],
            transferBrief: transferBrief
        )
        let baseSeed = assessmentDescriptor?.seed ?? retentionTarget?.alternateSeed ?? request.seed
        let preferredFormat = assessmentDescriptor?.format ?? retentionTarget.flatMap { target in
            guard target.requiresRepresentationShift else { return nil }
            return NFRetentionRepresentation.alternateFormat(
                for: selectedLab,
                priorRepresentationID: target.priorRepresentationID
            )
        }
        let preferredMechanicID = assessmentDescriptor?.mechanicID
            ?? retentionTarget?.templateFamily
            ?? request.mechanicID
        let offlineDescriptor: NFOfflineQuestionDescriptor? = if assessmentDescriptor == nil,
            retentionTarget == nil,
            transferBrief == nil,
            request.evidenceClass == .practice,
            request.mechanicID == nil,
            request.offlineQuestionOrdinals.indices.contains(index) {
            NFOfflineQuestionBank.descriptor(
                for: selectedLab,
                ordinal: request.offlineQuestionOrdinals[index]
            )
        } else {
            nil
        }
        let resolvedBaseSeed = offlineDescriptor?.seed ?? baseSeed
        let generationIndex = offlineDescriptor == nil ? index : 0
        let probeCount = offlineDescriptor == nil
            ? (assessmentDescriptor == nil ? (retentionTarget == nil ? 32 : 96) : 1)
            : 1
        var exactMechanicCandidate: NFExercise?
        var familyCandidate: NFExercise?
        var shiftedFamilyCandidate: NFExercise?
        for probe in 0..<probeCount {
            let seed = resolvedBaseSeed &+ UInt64(probe) &* 0x9E37_79B9_7F4A_7C15
            let candidate = try? NFFallbackExerciseGenerator.generate(NFExerciseGenerationRequest(
                seed: seed,
                index: generationIndex,
                lab: selectedLab,
                purpose: purpose,
                localeIdentifier: request.localeIdentifier,
                sourceContext: context,
                targetDifficulty: assessmentDescriptor?.difficulty ?? request.targetDifficulty,
                preferredAssessmentFormat: preferredFormat,
                preferredAssessmentMechanicID: preferredMechanicID,
                tracePolicyVersion: assessmentDescriptor == nil ? request.tracePolicyVersion : nil,
                scienceStudyPolicyVersion: assessmentDescriptor == nil ? request.scienceStudyPolicyVersion : nil,
                scienceStudyExcludedContextID: assessmentDescriptor == nil ? request.scienceStudyExcludedContextID : nil,
                transferPolicyVersion: assessmentDescriptor == nil ? request.transferPolicyVersion : nil,
                transferExcludedContextID: assessmentDescriptor == nil ? request.transferExcludedContextID : nil,
                graphConstructionPolicyVersion: assessmentDescriptor == nil ? request.graphConstructionPolicyVersion : nil,
                retrievalAuthorityPolicyVersion: assessmentDescriptor == nil ? request.retrievalAuthorityPolicyVersion : nil,
                retrievalAssetPolicyVersion: assessmentDescriptor == nil ? request.retrievalAssetPolicyVersion : nil,
                spatialStructurePolicyVersion: assessmentDescriptor == nil ? request.spatialStructurePolicyVersion : nil,
                coordinateTransformPolicyVersion: assessmentDescriptor == nil ? request.coordinateTransformPolicyVersion : nil,
                solidSectionPolicyVersion: assessmentDescriptor == nil ? request.solidSectionPolicyVersion : nil,
                netFoldingPolicyVersion: assessmentDescriptor == nil ? request.netFoldingPolicyVersion : nil,
                coordinateReasoningPolicyVersion: assessmentDescriptor == nil ? request.coordinateReasoningPolicyVersion : nil,
                spatialAssemblyPolicyVersion: assessmentDescriptor == nil ? request.spatialAssemblyPolicyVersion : nil
            ))
            if let candidate,
               (assessmentDescriptor != nil || !request.quarantinedItemIDs.contains(candidate.id)),
               (assessmentDescriptor != nil
                    || !excludingContentFingerprints.contains(
                        NFQuestionFingerprint.fingerprint(for: candidate)
                    )) {
                guard let retentionTarget else { return candidate }
                let candidateMechanic = retentionMechanicToken(candidate.templateID)
                let targetMechanic = retentionMechanicToken(retentionTarget.memoryItemID)
                let exactMechanic = targetMechanic != nil && candidateMechanic == targetMechanic
                let sameFamily = normalizedRetentionFamily(candidate.templateFamily)
                    == normalizedRetentionFamily(retentionTarget.templateFamily)
                let shifted = NFRetentionRepresentation.identifier(for: candidate)
                    != retentionTarget.priorRepresentationID

                if exactMechanic && (!retentionTarget.requiresRepresentationShift || shifted) {
                    return candidate
                }
                if exactMechanic, case .none = exactMechanicCandidate { exactMechanicCandidate = candidate }
                if sameFamily, case .none = familyCandidate { familyCandidate = candidate }
                if sameFamily && shifted, case .none = shiftedFamilyCandidate {
                    shiftedFamilyCandidate = candidate
                }
            }
        }
        if let retentionTarget {
            if retentionTarget.requiresRepresentationShift,
               let shiftedFamilyCandidate {
                return shiftedFamilyCandidate
            }
            if let exactMechanicCandidate { return exactMechanicCandidate }
            // A known scheduled mechanic cannot be replaced by another
            // question from the same broad lab when its finite pool is spent.
            if retentionMechanicToken(retentionTarget.memoryItemID) == nil,
               let familyCandidate { return familyCandidate }
            return nil
        }
        // Only generated selection can seek another eligible candidate. An
        // exact fixed-plan descriptor must become explicitly unavailable when
        // excluded; substituting a different seed would amend the saved plan.
        if assessmentDescriptor == nil,
           retentionTarget == nil,
           offlineDescriptor == nil,
           request.mechanicID == nil,
           !excludingContentFingerprints.isEmpty {
            return materializeAlternativeExercise(request: request, selectedLab: selectedLab,
                purpose: purpose, context: context, resolvedBaseSeed: resolvedBaseSeed,
                generationIndex: generationIndex, probeCount: probeCount,
                preferredFormat: preferredFormat, excludingContentFingerprints: excludingContentFingerprints)
        }
        return nil
    }

    /// Fixed/retention selection returns before these unrelated fallback search
    /// temporaries are allocated. Probe order, seeds, and exclusions are unchanged.
    @inline(never)
    private static func materializeAlternativeExercise(
        request: SessionRequest, selectedLab: TrainingLab, purpose: NFExercisePurpose,
        context: NFExerciseSourceContext, resolvedBaseSeed: UInt64, generationIndex: Int,
        probeCount: Int, preferredFormat: NFAssessmentItemFormat?, excludingContentFingerprints: Set<String>
    ) -> NFExercise? {
        for probe in 0..<256 {
            let seed = resolvedBaseSeed
                &+ UInt64(probeCount + probe) &* 0x9E37_79B9_7F4A_7C15
            guard let candidate = try? NFFallbackExerciseGenerator.generate(
                NFExerciseGenerationRequest(
                    seed: seed,
                    index: generationIndex,
                    lab: selectedLab,
                    purpose: purpose,
                    localeIdentifier: request.localeIdentifier,
                    sourceContext: context,
                    targetDifficulty: request.targetDifficulty,
                    preferredAssessmentFormat: preferredFormat,
                    preferredAssessmentMechanicID: nil,
                    tracePolicyVersion: request.tracePolicyVersion,
                    scienceStudyPolicyVersion: request.scienceStudyPolicyVersion,
                    scienceStudyExcludedContextID: request.scienceStudyExcludedContextID,
                    transferPolicyVersion: request.transferPolicyVersion, transferExcludedContextID: request.transferExcludedContextID,
                    graphConstructionPolicyVersion: request.graphConstructionPolicyVersion,
                    retrievalAuthorityPolicyVersion: request.retrievalAuthorityPolicyVersion,
                    retrievalAssetPolicyVersion: request.retrievalAssetPolicyVersion,
                    spatialStructurePolicyVersion: request.spatialStructurePolicyVersion,
                    coordinateTransformPolicyVersion: request.coordinateTransformPolicyVersion,
                        solidSectionPolicyVersion: request.solidSectionPolicyVersion,
                        netFoldingPolicyVersion: request.netFoldingPolicyVersion,
                        coordinateReasoningPolicyVersion: request.coordinateReasoningPolicyVersion,
                        spatialAssemblyPolicyVersion: request.spatialAssemblyPolicyVersion
                )
            ),
            !request.quarantinedItemIDs.contains(candidate.id),
            !excludingContentFingerprints.contains(
                NFQuestionFingerprint.fingerprint(for: candidate)
            ) else { continue }
            return candidate
        }

        // The compiled bank is the final no-repeat authority for ordinary
        // practice. This path is rarely needed (the probes above normally
        // find a different mechanic immediately), but it prevents a narrow
        // selected activity from silently replaying its first item.
        for ordinal in 0..<NFOfflineQuestionBank.questionsPerLab {
            guard let descriptor = NFOfflineQuestionBank.descriptor(
                for: selectedLab,
                ordinal: ordinal
            ),
            let candidate = try? NFFallbackExerciseGenerator.generate(
                NFExerciseGenerationRequest(
                    seed: descriptor.seed,
                    index: 0,
                    lab: selectedLab,
                    purpose: purpose,
                    localeIdentifier: request.localeIdentifier,
                    sourceContext: context,
                    targetDifficulty: request.targetDifficulty,
                    tracePolicyVersion: request.tracePolicyVersion,
                    scienceStudyPolicyVersion: request.scienceStudyPolicyVersion,
                    scienceStudyExcludedContextID: request.scienceStudyExcludedContextID,
                    transferPolicyVersion: request.transferPolicyVersion, transferExcludedContextID: request.transferExcludedContextID,
                    graphConstructionPolicyVersion: request.graphConstructionPolicyVersion,
                    retrievalAuthorityPolicyVersion: request.retrievalAuthorityPolicyVersion,
                    retrievalAssetPolicyVersion: request.retrievalAssetPolicyVersion,
                    spatialStructurePolicyVersion: request.spatialStructurePolicyVersion,
                    coordinateTransformPolicyVersion: request.coordinateTransformPolicyVersion,
                        solidSectionPolicyVersion: request.solidSectionPolicyVersion,
                        netFoldingPolicyVersion: request.netFoldingPolicyVersion,
                        coordinateReasoningPolicyVersion: request.coordinateReasoningPolicyVersion,
                        spatialAssemblyPolicyVersion: request.spatialAssemblyPolicyVersion
                )
            ),
            !request.quarantinedItemIDs.contains(candidate.id),
            !excludingContentFingerprints.contains(
                NFQuestionFingerprint.fingerprint(for: candidate)
            ) else { continue }
            return candidate
        }

        return nil
    }

    private static func unavailableExercise(lab: TrainingLab, localeIdentifier: String) -> NFExercise {
        // The placeholder is never presented as a question or admitted to a
        // scorer. The known bounded factory inputs only construct its shape.
        var placeholder = try! NFFallbackExerciseGenerator.generate(NFExerciseGenerationRequest(
            seed: 1, index: 0, lab: lab, purpose: .practice, localeIdentifier: localeIdentifier))
        placeholder.availabilityReason = "No fresh question is available for this activity. Your completed answers are saved. Choose another activity or return later."
        return placeholder
    }

    private static func retentionMechanicToken(_ identity: String) -> String? {
        // These are explicit shipped template editions, not an arbitrary
        // future-version parser. This applies only to a fresh review target;
        // accepted snapshots retain their exact original exercise.
        for edition in ["v3", "v4"] {
            if let marker = identity.range(of: ".\(edition).", options: .backwards) {
                let token = identity[marker.upperBound...]
                return token.isEmpty ? nil : String(token)
            }
        }
        return nil
    }

    private static func normalizedRetentionFamily(_ identity: String) -> String {
        var normalized = identity
        for purpose in ["baseline", "practice", "near", "applied", "retention", "holdout", "document"] {
            normalized = normalized.replacingOccurrences(of: ".\(purpose).", with: ".")
        }
        for edition in ["v3", "v4"] {
            if normalized.hasSuffix("." + edition) {
                return String(normalized.dropLast(edition.count + 1))
            }
        }
        return normalized
    }
}

enum NFNextDayPreparationOutcome: Equatable, Sendable {
    case contentUnavailable
    case policyForbidden
    case modelUnavailable
    case alreadyPrepared
    case prepared
}

struct NFNextDayPreparationReceipt: Equatable, Sendable {
    let outcome: NFNextDayPreparationOutcome
    let planID: String?
    let deterministicExerciseCount: Int
    let enhancementCount: Int
}

enum NFNextDayPlanPreparationService {
    /// Test seam for validating presentation-only overlays from an explicitly
    /// supplied generator. The shipping app has no model generator and never
    /// calls this service. No AttemptRecord, SessionCheckpointRecord, or
    /// progress reducer input is created here.
    @MainActor
    static func prepare(
        store: AppStore,
        now: Date = Date(),
        calendar: Calendar = .current,
        generator: any NFPresentationEnhancementGenerating
    ) async throws -> NFNextDayPreparationReceipt {
        try Task.checkCancellation()
        guard (try? NFReleaseContentGate.requireVerified()) != nil else {
            store.nextDayEnhancementCache.removeAll()
            return NFNextDayPreparationReceipt(
                outcome: .contentUnavailable,
                planID: nil,
                deterministicExerciseCount: 0,
                enhancementCount: 0
            )
        }
        guard store.isOnboardingComplete,
              store.profileSnapshot.aiMode != .disabled else {
            store.nextDayEnhancementCache.removeAll()
            return NFNextDayPreparationReceipt(
                outcome: .policyForbidden,
                planID: nil,
                deterministicExerciseCount: 0,
                enhancementCount: 0
            )
        }

        let nextDate = calendar.date(byAdding: .day, value: 1, to: now)
            ?? now.addingTimeInterval(86_400)
        let plan = store.dailyPlan(at: nextDate, calendar: calendar)
        try Task.checkCancellation()
        let compatibility = store.nextDayEnhancementCompatibility(for: plan)
        let seeds = store.presentationEnhancementSeeds(for: plan)
        guard !seeds.isEmpty else {
            return NFNextDayPreparationReceipt(
                outcome: .modelUnavailable,
                planID: plan.id,
                deterministicExerciseCount: 0,
                enhancementCount: 0
            )
        }

        if let payload = store.nextDayEnhancementCache.preparedPayload(
            expected: compatibility,
            at: now
        ) {
            let request = NFPresentationEnhancementGenerationRequest(
                compatibilityFingerprint: compatibility.fingerprint,
                localeIdentifier: compatibility.localeIdentifier,
                aiMode: store.profileSnapshot.aiMode,
                seeds: seeds
            )
            if let validated = try? NFPresentationEnhancementValidator.validate(
                payload.enhancements,
                for: request
            ) {
                return NFNextDayPreparationReceipt(
                    outcome: .alreadyPrepared,
                    planID: plan.id,
                    deterministicExerciseCount: seeds.count,
                    enhancementCount: validated.count
                )
            }
            store.nextDayEnhancementCache.removeAll()
        }

        guard await generator.isAvailable(localeIdentifier: compatibility.localeIdentifier) else {
            return NFNextDayPreparationReceipt(
                outcome: .modelUnavailable,
                planID: plan.id,
                deterministicExerciseCount: seeds.count,
                enhancementCount: 0
            )
        }
        try Task.checkCancellation()
        let request = NFPresentationEnhancementGenerationRequest(
            compatibilityFingerprint: compatibility.fingerprint,
            localeIdentifier: compatibility.localeIdentifier,
            aiMode: store.profileSnapshot.aiMode,
            seeds: seeds
        )
        let generated = try await generator.generate(request)
        try Task.checkCancellation()
        let validated = try NFPresentationEnhancementValidator.validate(generated, for: request)
        let boundary = NFPlanBoundaryContext.make(
            at: nextDate,
            dayBoundaryHour: store.profileSnapshot.dayBoundaryHour,
            calendar: calendar
        )
        let payload = NFNextDayEnhancementPayload(
            compatibility: compatibility,
            compatibilityFingerprint: compatibility.fingerprint,
            validFrom: boundary.boundaryStart,
            expiresAt: boundary.nextBoundary,
            enhancements: validated
        )
        try Task.checkCancellation()
        try store.nextDayEnhancementCache.persist(payload, validating: request)
        return NFNextDayPreparationReceipt(
            outcome: .prepared,
            planID: plan.id,
            deterministicExerciseCount: seeds.count,
            enhancementCount: validated.count
        )
    }
}

@MainActor
extension AppStore {
    func nextDayEnhancementCompatibility(for plan: DailyPlan) -> NFNextDayEnhancementCompatibility {
        NFNextDayEnhancementCompatibility.make(
            profile: profileSnapshot,
            plan: plan,
            readiness: readiness,
            localeIdentifier: profile?.preferredLanguageCode ?? Locale.current.identifier,
            quarantinedItemIDs: Set(itemReports.filter { $0.status == "quarantined" }.map(\.itemID))
        )
    }

    func presentationEnhancementSeeds(for plan: DailyPlan) -> [NFPresentationEnhancementSeed] {
        let localeIdentifier = profile?.preferredLanguageCode ?? Locale.current.identifier
        let quarantinedIDs = Set(itemReports.filter { $0.status == "quarantined" }.map(\.itemID))
        var seenIDs: Set<String> = []
        var seeds: [NFPresentationEnhancementSeed] = []
        for block in plan.blocks {
            let field = NFPlanFieldAssignment.field(
                forBlockID: block.id,
                in: plan,
                profile: profileSnapshot
            )
            let itemCount = max(3, min(12, block.minutes / 2))
            let request = SessionRequest(
                lab: block.lab,
                source: .today,
                seed: plan.seed,
                localeIdentifier: localeIdentifier,
                requestedMinutes: block.minutes,
                evidenceClass: block.evidenceClass,
                field: field,
                topic: block.mechanicID,
                planID: plan.id,
                planBlockID: block.id,
                isTimed: profileSnapshot.timingMode == .untimed ? false : block.timed,
                mechanicID: block.mechanicID,
                retentionItemIDs: block.retentionItemIDs,
                retentionTargets: retentionReviewTargets(
                    forPlanID: plan.id,
                    blockID: block.id,
                    fallbackItemIDs: block.retentionItemIDs,
                    fallbackSeed: plan.seed
                ),
                quarantinedItemIDs: quarantinedIDs
            )
            for index in 0..<itemCount {
                let exercise = NFDeterministicSessionExerciseFactory.makeExercise(
                    request: request,
                    index: index,
                    assessmentDescriptor: nil
                )
                guard seenIDs.insert(exercise.id).inserted else { continue }
                seeds.append(NFPresentationEnhancementSeed(exercise: exercise, field: field))
            }
        }
        return seeds
    }

    func assignedField(forPlanID planID: String?, blockID: String?) -> STEMField? {
        guard let planID,
              let blockID,
              let plan = dailyPlans.first(where: { $0.id == planID })?.snapshot?.domainPlan else {
            return nil
        }
        return NFPlanFieldAssignment.field(
            forBlockID: blockID,
            in: plan,
            profile: profileSnapshot
        )
    }

    func compatiblePresentationEnhancements(
        forPlanID planID: String?,
        at date: Date = Date()
    ) -> [String: NFExercisePresentationEnhancement] {
        guard let planID,
              profileSnapshot.aiMode != .disabled,
              let canonical = dailyPlans.first(where: { $0.id == planID })?.snapshot else {
            return [:]
        }
        let plan = canonical.domainPlan
        let compatibility = nextDayEnhancementCompatibility(for: plan)
        guard let payload = nextDayEnhancementCache.load(expected: compatibility, at: date) else { return [:] }
        let seeds = presentationEnhancementSeeds(for: plan)
        let request = NFPresentationEnhancementGenerationRequest(
            compatibilityFingerprint: compatibility.fingerprint,
            localeIdentifier: compatibility.localeIdentifier,
            aiMode: profileSnapshot.aiMode,
            seeds: seeds
        )
        guard let validated = try? NFPresentationEnhancementValidator.validate(
            payload.enhancements,
            for: request
        ) else {
            nextDayEnhancementCache.removeAll()
            return [:]
        }
        return Dictionary(uniqueKeysWithValues: validated.map { ($0.deterministicExerciseID, $0) })
    }

    func purgeExpiredPreparedEnhancements(at date: Date = Date()) {
        _ = nextDayEnhancementCache.purgeExpiredOrInvalid(at: date)
    }

    var preparedEnhancementCacheBytes: Int64 {
        nextDayEnhancementCache.payloadByteCount()
    }

    func expiredPreparedEnhancementCacheCount(at date: Date = Date()) -> Int {
        nextDayEnhancementCache.expiredOrInvalidCount(at: date)
    }
}

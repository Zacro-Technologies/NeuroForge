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
        var firstCandidate: NFExercise?
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
                preferredAssessmentMechanicID: preferredMechanicID
            ))
            if let candidate,
               (assessmentDescriptor != nil || !request.quarantinedItemIDs.contains(candidate.id)),
               (assessmentDescriptor != nil
                    || !excludingContentFingerprints.contains(
                        NFQuestionFingerprint.fingerprint(for: candidate)
                    )) {
                guard let retentionTarget else { return candidate }
                firstCandidate = firstCandidate ?? candidate
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
                if exactMechanic { exactMechanicCandidate = exactMechanicCandidate ?? candidate }
                if sameFamily { familyCandidate = familyCandidate ?? candidate }
                if sameFamily && shifted {
                    shiftedFamilyCandidate = shiftedFamilyCandidate ?? candidate
                }
            }
        }
        if let retentionTarget {
            if retentionTarget.requiresRepresentationShift,
               let shiftedFamilyCandidate {
                return shiftedFamilyCandidate
            }
            if let exactMechanicCandidate { return exactMechanicCandidate }
            if let familyCandidate { return familyCandidate }
            if let firstCandidate { return firstCandidate }
        }
        // Some narrowly selected activities intentionally have a single
        // reviewed contract. Once that contract has appeared in this run,
        // broaden to the remaining reviewed families in the same lab rather
        // than showing the identical question again.
        if assessmentDescriptor == nil,
           retentionTarget == nil,
           !excludingContentFingerprints.isEmpty {
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
                        preferredAssessmentMechanicID: nil
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
                        targetDifficulty: request.targetDifficulty
                    )
                ),
                !request.quarantinedItemIDs.contains(candidate.id),
                !excludingContentFingerprints.contains(
                    NFQuestionFingerprint.fingerprint(for: candidate)
                ) else { continue }
                return candidate
            }

            preconditionFailure(
                "Verified offline bank could not provide a unique \(selectedLab.rawValue) practice question"
            )
        }
        return try! NFFallbackExerciseGenerator.generate(NFExerciseGenerationRequest(
            seed: retentionTarget?.alternateSeed ?? 1,
            index: max(0, index),
            lab: selectedLab,
            purpose: purpose,
            localeIdentifier: request.localeIdentifier,
            sourceContext: context,
            targetDifficulty: nil,
            preferredAssessmentFormat: preferredFormat,
            preferredAssessmentMechanicID: preferredMechanicID
        ))
    }

    private static func retentionMechanicToken(_ identity: String) -> String? {
        guard let marker = identity.range(of: ".v3.", options: .backwards) else { return nil }
        let token = identity[marker.upperBound...]
        return token.isEmpty ? nil : String(token)
    }

    private static func normalizedRetentionFamily(_ identity: String) -> String {
        var normalized = identity
        for purpose in ["baseline", "practice", "near", "applied", "retention", "holdout", "document"] {
            normalized = normalized.replacingOccurrences(of: ".\(purpose).", with: ".")
        }
        if let version = normalized.range(of: ".v3", options: .backwards) {
            return String(normalized[..<version.upperBound])
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

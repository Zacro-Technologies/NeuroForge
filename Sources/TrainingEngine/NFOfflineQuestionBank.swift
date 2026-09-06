import Foundation

struct NFOfflineQuestionDescriptor: Equatable, Hashable, Sendable {
    let id: String
    let lab: TrainingLab
    let ordinal: Int
    let candidateIndex: Int
    let seed: UInt64
    let semanticFingerprint: String
}

/// The non-AI floor for every top-level training section. A descriptor is
/// admitted only when its normalized prompt, stimulus, and authoritative
/// answer contract have not appeared earlier in that lab's bank.
enum NFOfflineQuestionBank {
    // Version 2 expands the audited deterministic offline floor from 200 to 1,000
    // canonical contracts per top-level lab. The version bump prevents an
    // installed v1 rotation cursor from being mistaken for the expanded bank.
    static let version = 3
    static let questionsPerLab = 1_000
    // Current v2 banks complete by candidate 12,449 or earlier. Keeping a
    // generous deterministic scan ceiling gives future copy-neutral generator
    // maintenance room while the release audit still fails closed at 1,000.
    private static let candidateLimit = 50_000

    /// Set by the offline release authority only after this bank's identities
    /// and retrieval targets are added to a newly signed manifest. `nil` keeps
    /// adaptive model population fail-closed while the current signed inventory
    /// predates the 7,000-question mapping.
    private static let signedInventoryContentVersion: String? = nil

    static func descriptors(for lab: TrainingLab) -> [NFOfflineQuestionDescriptor] {
        switch lab {
        case .mentalMath: mentalMathDescriptors
        case .spatial: spatialDescriptors
        case .quantitative: quantitativeDescriptors
        case .scientificReasoning: scientificReasoningDescriptors
        case .logicDebugging: logicDebuggingDescriptors
        case .retrieval: retrievalDescriptors
        case .transfer: transferDescriptors
        }
    }

    static func descriptor(for lab: TrainingLab, ordinal: Int) -> NFOfflineQuestionDescriptor? {
        let bank = descriptors(for: lab)
        guard bank.indices.contains(ordinal) else { return nil }
        return bank[ordinal]
    }

    static func ordinal(forQuestionID questionID: String, lab: TrainingLab) -> Int? {
        let prefix = "nf.offline.v\(version).\(lab.rawValue)."
        guard questionID.hasPrefix(prefix),
              let ordinal = Int(questionID.dropFirst(prefix.count)),
              (0..<questionsPerLab).contains(ordinal) else { return nil }
        return ordinal
    }

    static let rotationBank: NFVersionedOfflineQuestionBank = {
        let identifiers = Dictionary(uniqueKeysWithValues: TrainingLab.allCases.map { lab in
            (
                lab,
                (0..<questionsPerLab).map { stableQuestionID(lab: lab, ordinal: $0) }
            )
        })
        // A failed construction is a compiled-content defect caught by the
        // release audit and tests, not recoverable learner data.
        return try! NFVersionedOfflineQuestionBank(
            version: version,
            questionIDsByLab: identifiers
        )
    }()

    static func audit() -> [String] {
        TrainingLab.allCases.flatMap { lab -> [String] in
            let bank = descriptors(for: lab)
            var errors: [String] = []
            if bank.count != questionsPerLab {
                errors.append("\(lab.rawValue): expected \(questionsPerLab), found \(bank.count)")
            }
            if Set(bank.map(\.id)).count != bank.count {
                errors.append("\(lab.rawValue): duplicate stable IDs")
            }
            if Set(bank.map(\.semanticFingerprint)).count != bank.count {
                errors.append("\(lab.rawValue): duplicate semantic contracts")
            }
            if bank.map(\.ordinal) != Array(0..<bank.count) {
                errors.append("\(lab.rawValue): non-contiguous ordinals")
            }
            return errors
        }
    }

    /// Privacy-safe evidence consumed by the adaptive population policy. The
    /// future model route receives counts/fingerprints only through this local
    /// gate; the 7,000 bundled contracts themselves remain offline authority.
    static var adaptivePopulationFloorEvidence: NFBundledQuestionFloorEvidence {
        let fingerprints = Dictionary(uniqueKeysWithValues: TrainingLab.allCases.map { lab in
            (lab, descriptors(for: lab).map(\.semanticFingerprint))
        })
        let signedManifest = try? NFReleaseContentGate.requireVerified()
        let signedInventoryCoversThisBank = signedInventoryContentVersion.map {
            signedManifest?.contentVersion == $0
        } ?? false
        return NFBundledQuestionFloorEvidence(
            uniqueQuestionFingerprintsByLab: fingerprints,
            catalogIntegrityVerified: signedInventoryCoversThisBank && audit().isEmpty
        )
    }

    private static let mentalMathDescriptors = buildDescriptors(for: .mentalMath)
    private static let spatialDescriptors = buildDescriptors(for: .spatial)
    private static let quantitativeDescriptors = buildDescriptors(for: .quantitative)
    private static let scientificReasoningDescriptors = buildDescriptors(for: .scientificReasoning)
    private static let logicDebuggingDescriptors = buildDescriptors(for: .logicDebugging)
    private static let retrievalDescriptors = buildDescriptors(for: .retrieval)
    private static let transferDescriptors = buildDescriptors(for: .transfer)

    private static func buildDescriptors(for lab: TrainingLab) -> [NFOfflineQuestionDescriptor] {
        var result: [NFOfflineQuestionDescriptor] = []
        var canonicalContracts: Set<String> = []
        for candidateIndex in 0..<candidateLimit where result.count < questionsPerLab {
            let seed = candidateSeed(lab: lab, candidateIndex: candidateIndex)
            let request = NFExerciseGenerationRequest(
                seed: seed,
                index: 0,
                lab: lab,
                purpose: .practice,
                localeIdentifier: "en",
                sourceContext: NFExerciseSourceContext(primaryField: .general)
            )
            guard let exercise = try? NFFallbackExerciseGenerator.generate(request) else { continue }
            let contract = NFQuestionFingerprint.canonicalContract(for: exercise)
            guard canonicalContracts.insert(contract).inserted else { continue }
            let ordinal = result.count
            result.append(NFOfflineQuestionDescriptor(
                id: stableQuestionID(lab: lab, ordinal: ordinal),
                lab: lab,
                ordinal: ordinal,
                candidateIndex: candidateIndex,
                seed: seed,
                semanticFingerprint: NFQuestionFingerprint.fingerprint(for: exercise)
            ))
        }
        precondition(
            result.count == questionsPerLab,
            "Bundled question bank for \(lab.rawValue) has only \(result.count) unique contracts"
        )
        return result
    }

    private static func candidateSeed(lab: TrainingLab, candidateIndex: Int) -> UInt64 {
        NFStableDeterminism.hash64(
            "offline-question-bank|v\(version)|\(lab.rawValue)|candidate-\(candidateIndex)"
        )
    }

    private static func stableQuestionID(lab: TrainingLab, ordinal: Int) -> String {
        "nf.offline.v\(version).\(lab.rawValue).\(ordinal)"
    }
}

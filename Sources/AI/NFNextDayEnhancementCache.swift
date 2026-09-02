import Foundation

/// Optional copy that can make a deterministic exercise feel more relevant to
/// the learner's field. It never replaces the prompt, interaction, answer key,
/// rubric, or score.
struct NFExercisePresentationEnhancement: Codable, Equatable, Hashable, Sendable, Identifiable {
    let deterministicExerciseID: String
    let contextLabel: String
    let coachingHint: String
    let transferLens: String
    let generatedAt: Date
    let route: NFAIRoute
    let modelIdentifier: String
    let scaffoldingLevel: String?
    let sourceChunkIDs: [String]

    var id: String { deterministicExerciseID }

    init(
        deterministicExerciseID: String,
        contextLabel: String,
        coachingHint: String,
        transferLens: String,
        generatedAt: Date,
        route: NFAIRoute,
        modelIdentifier: String,
        scaffoldingLevel: String? = nil,
        sourceChunkIDs: [String] = []
    ) {
        self.deterministicExerciseID = deterministicExerciseID
        self.contextLabel = contextLabel
        self.coachingHint = coachingHint
        self.transferLens = transferLens
        self.generatedAt = generatedAt
        self.route = route
        self.modelIdentifier = modelIdentifier
        self.scaffoldingLevel = scaffoldingLevel
        self.sourceChunkIDs = sourceChunkIDs
    }

    private enum CodingKeys: String, CodingKey {
        case deterministicExerciseID
        case contextLabel
        case coachingHint
        case transferLens
        case generatedAt
        case route
        case modelIdentifier
        case scaffoldingLevel
        case sourceChunkIDs
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        deterministicExerciseID = try container.decode(String.self, forKey: .deterministicExerciseID)
        contextLabel = try container.decode(String.self, forKey: .contextLabel)
        coachingHint = try container.decode(String.self, forKey: .coachingHint)
        transferLens = try container.decode(String.self, forKey: .transferLens)
        generatedAt = try container.decode(Date.self, forKey: .generatedAt)
        route = try container.decode(NFAIRoute.self, forKey: .route)
        modelIdentifier = try container.decode(String.self, forKey: .modelIdentifier)
        scaffoldingLevel = try container.decodeIfPresent(String.self, forKey: .scaffoldingLevel)
        sourceChunkIDs = try container.decodeIfPresent([String].self, forKey: .sourceChunkIDs) ?? []
    }
}

/// Every input that can make a prepared presentation incompatible with the
/// deterministic plan. Storing the expanded compatibility record as well as a
/// fingerprint makes collision or stale-cache behavior fail closed.
struct NFNextDayEnhancementCompatibility: Codable, Equatable, Sendable {
    static let cacheSchemaVersion = 1
    static let presentationPromptVersion = 1

    let profileID: UUID
    let profileSignature: String
    let planID: String
    let localDayKey: String
    let planPolicyVersion: Int
    let planSignature: String
    let readinessRaw: String
    let localeIdentifier: String
    let aiModeRaw: String
    let blockStateSignature: String
    let exerciseSchemaVersion: Int
    let exerciseGeneratorVersion: Int
    let exerciseValidatorVersion: Int
    let presentationPromptVersion: Int
    let cacheSchemaVersion: Int

    var fingerprint: String {
        let components = [
            profileID.uuidString,
            profileSignature,
            planID,
            localDayKey,
            String(planPolicyVersion),
            planSignature,
            readinessRaw,
            localeIdentifier,
            aiModeRaw,
            blockStateSignature,
            String(exerciseSchemaVersion),
            String(exerciseGeneratorVersion),
            String(exerciseValidatorVersion),
            String(presentationPromptVersion),
            String(cacheSchemaVersion)
        ]
        return String(AdaptiveEngine.fnv1a64(components.joined(separator: "␟")), radix: 16)
    }

    static func make(
        profile: ProfileSnapshot,
        plan: DailyPlan,
        readiness: Readiness,
        localeIdentifier: String,
        quarantinedItemIDs: Set<String>
    ) -> NFNextDayEnhancementCompatibility {
        let profileSignature = [
            profile.stage.rawValue,
            profile.fields.map(\.rawValue).sorted().joined(separator: ","),
            profile.goals.map(\.rawValue).sorted().joined(separator: ","),
            String(profile.dailyDuration),
            profile.timingMode.rawValue,
            profile.aiMode.rawValue,
            profile.trainingDays.sorted().map(String.init).joined(separator: ","),
            String(profile.dayBoundaryHour)
        ].joined(separator: "|")
        let planSignature = plan.blocks.map { block in
            [
                block.id,
                block.lab.rawValue,
                block.kindRaw ?? "",
                block.mechanicID,
                String(block.minutes),
                block.evidenceClass.rawValue,
                block.timed ? "timed" : "untimed",
                block.retentionItemIDs.sorted().joined(separator: ",")
            ].joined(separator: ":")
        }.joined(separator: "|")
        let blockStateSignature = [
            // Completion is deliberately absent: finishing block one cannot
            // invalidate presentation prepared for the remaining blocks.
            // Block replacements/mechanics live in planSignature, while a new
            // quarantine invalidates any overlay bound to a rejected item.
            "immutable-plan-blocks",
            quarantinedItemIDs.sorted().joined(separator: ",")
        ].joined(separator: "|")
        return NFNextDayEnhancementCompatibility(
            profileID: profile.id,
            profileSignature: profileSignature,
            planID: plan.id,
            localDayKey: plan.localDayKey,
            planPolicyVersion: plan.policyVersion,
            planSignature: planSignature,
            readinessRaw: readiness.rawValue,
            localeIdentifier: localeIdentifier,
            aiModeRaw: profile.aiMode.rawValue,
            blockStateSignature: blockStateSignature,
            exerciseSchemaVersion: NFFallbackExerciseGenerator.schemaVersion,
            exerciseGeneratorVersion: NFFallbackExerciseGenerator.generatorVersion,
            exerciseValidatorVersion: NFExerciseSchemaValidator.validatorVersion,
            presentationPromptVersion: presentationPromptVersion,
            cacheSchemaVersion: cacheSchemaVersion
        )
    }
}

struct NFNextDayEnhancementPayload: Codable, Equatable, Sendable {
    let compatibility: NFNextDayEnhancementCompatibility
    let compatibilityFingerprint: String
    let validFrom: Date
    let expiresAt: Date
    let enhancements: [NFExercisePresentationEnhancement]
}

enum NFNextDayEnhancementValidationError: Error, Equatable, Sendable {
    case policyForbidden
    case invalidCompatibility
    case invalidValidityWindow
    case missingOrDuplicateExerciseIDs
    case invalidPresentationField(String)
    case answerDisclosure(String)
    case invalidRoute
}

private enum NFDisclosureKind: Sendable {
    case phrase
    case numeric
}

private struct NFDisclosureToken: Sendable {
    let value: String
    let kind: NFDisclosureKind
}

struct NFPresentationEnhancementSeed: Sendable {
    let deterministicExerciseID: String
    let lab: TrainingLab
    let field: STEMField
    let title: String
    let prompt: String
    let instructions: String
    fileprivate let disclosureTokens: [NFDisclosureToken]

    init(exercise: NFExercise, field: STEMField) {
        deterministicExerciseID = exercise.id
        lab = exercise.lab
        self.field = field
        title = exercise.title
        prompt = exercise.prompt
        instructions = exercise.instructions
        disclosureTokens = Self.answerDisclosureTokens(for: exercise.interaction)
    }

    init(
        deterministicExerciseID: String,
        lab: TrainingLab,
        field: STEMField,
        title: String,
        prompt: String,
        instructions: String,
        forbiddenAnswerStrings: [String] = []
    ) {
        self.deterministicExerciseID = deterministicExerciseID
        self.lab = lab
        self.field = field
        self.title = title
        self.prompt = prompt
        self.instructions = instructions
        disclosureTokens = forbiddenAnswerStrings.map {
            NFDisclosureToken(value: $0, kind: NFExactNumber(parsing: $0) == nil ? .phrase : .numeric)
        }
    }

    private static func answerDisclosureTokens(for interaction: NFExerciseInteraction) -> [NFDisclosureToken] {
        switch interaction {
        case let .numeric(schema):
            let exact = schema.answer.authoritativeValue.canonicalString
            return [
                NFDisclosureToken(value: exact, kind: .numeric),
                NFDisclosureToken(value: String(format: "%.12g", schema.answer.value), kind: .numeric)
            ]
        case let .singleChoice(schema):
            return schema.options
                .filter { $0.id == schema.correctOptionID }
                .map { NFDisclosureToken(value: $0.text, kind: .phrase) }
        case let .multipleChoice(schema):
            let correctIDs = Set(schema.correctOptionIDs)
            return schema.options
                .filter { correctIDs.contains($0.id) }
                .map { NFDisclosureToken(value: $0.text, kind: .phrase) }
        case let .orderedSteps(schema):
            let steps = Dictionary(uniqueKeysWithValues: schema.steps.map { ($0.id, $0.text) })
            let ordered = schema.correctOrder.compactMap { steps[$0] }.joined(separator: " then ")
            return [NFDisclosureToken(value: ordered, kind: .phrase)]
        case let .shortText(schema):
            var values = [schema.expectedAnswer]
            switch schema.scoringRule {
            case let .normalizedExact(acceptedAnswers): values.append(contentsOf: acceptedAnswers)
            case .requiredTerms: break
            case let .constrainedConcepts(acceptedAnswers, _, _, _):
                values.append(contentsOf: acceptedAnswers)
            }
            return values.map { NFDisclosureToken(value: $0, kind: .phrase) }
        case let .selfCheck(schema):
            return [NFDisclosureToken(value: schema.referenceAnswer, kind: .phrase)]
        case let .claimEvidence(schema):
            let claims = Dictionary(uniqueKeysWithValues: schema.claims.map { ($0.id, $0.text) })
            let evidence = Dictionary(uniqueKeysWithValues: schema.evidence.map { ($0.id, $0.text) })
            return schema.correctPairs.compactMap { pair in
                guard let claim = claims[pair.claimID] else { return nil }
                let support = pair.evidenceIDs.compactMap { evidence[$0] }.joined(separator: "; ")
                return NFDisclosureToken(value: "\(claim) \(support)", kind: .phrase)
            }
        case let .logicState(schema):
            var values = schema.expectedFinalState.values.map {
                NFDisclosureToken(value: $0, kind: .phrase)
            }
            if let expectedID = schema.expectedViolatedRuleID,
               let rule = schema.ruleOptions.first(where: { $0.id == expectedID }) {
                values.append(NFDisclosureToken(value: rule.text, kind: .phrase))
            }
            return values
        }
    }
}

struct NFPresentationEnhancementGenerationRequest: Sendable {
    let compatibilityFingerprint: String
    let localeIdentifier: String
    let aiMode: AIMode
    let seeds: [NFPresentationEnhancementSeed]
}

enum NFPresentationEnhancementValidator {
    private static let prohibitedCues = [
        "the answer is", "correct answer", "choose option", "select option",
        "the correct choice", "final answer", "answer:"
    ]

    static func validate(
        _ enhancements: [NFExercisePresentationEnhancement],
        for request: NFPresentationEnhancementGenerationRequest
    ) throws -> [NFExercisePresentationEnhancement] {
        guard request.aiMode != .disabled else {
            throw NFNextDayEnhancementValidationError.policyForbidden
        }
        let expectedIDs = Set(request.seeds.map(\.deterministicExerciseID))
        let actualIDs = Set(enhancements.map(\.deterministicExerciseID))
        guard expectedIDs.count == request.seeds.count,
              actualIDs.count == enhancements.count,
              actualIDs == expectedIDs else {
            throw NFNextDayEnhancementValidationError.missingOrDuplicateExerciseIDs
        }
        let seedByID = Dictionary(uniqueKeysWithValues: request.seeds.map { ($0.deterministicExerciseID, $0) })
        for enhancement in enhancements {
            guard enhancement.route == .onDevice else {
                throw NFNextDayEnhancementValidationError.invalidRoute
            }
            let fields = [
                ("contextLabel", enhancement.contextLabel, 3, 220),
                ("coachingHint", enhancement.coachingHint, 12, 420),
                ("transferLens", enhancement.transferLens, 12, 520),
                ("modelIdentifier", enhancement.modelIdentifier, 3, 200)
            ]
            for (name, value, minimum, maximum) in fields {
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                guard trimmed == value, (minimum...maximum).contains(trimmed.count) else {
                    throw NFNextDayEnhancementValidationError.invalidPresentationField(name)
                }
            }
            let combined = canonical("\(enhancement.contextLabel) \(enhancement.coachingHint) \(enhancement.transferLens)")
            if prohibitedCues.contains(where: { combined.contains($0) }) {
                throw NFNextDayEnhancementValidationError.answerDisclosure(enhancement.deterministicExerciseID)
            }
            guard let seed = seedByID[enhancement.deterministicExerciseID] else {
                throw NFNextDayEnhancementValidationError.missingOrDuplicateExerciseIDs
            }
            for token in seed.disclosureTokens where discloses(token, in: combined) {
                throw NFNextDayEnhancementValidationError.answerDisclosure(enhancement.deterministicExerciseID)
            }
        }
        return enhancements.sorted { $0.deterministicExerciseID < $1.deterministicExerciseID }
    }

    static func validatePayload(_ payload: NFNextDayEnhancementPayload) throws {
        guard payload.compatibility.aiModeRaw != AIMode.disabled.rawValue else {
            throw NFNextDayEnhancementValidationError.policyForbidden
        }
        guard payload.compatibility.cacheSchemaVersion == NFNextDayEnhancementCompatibility.cacheSchemaVersion,
              payload.compatibility.presentationPromptVersion == NFNextDayEnhancementCompatibility.presentationPromptVersion,
              payload.compatibilityFingerprint == payload.compatibility.fingerprint else {
            throw NFNextDayEnhancementValidationError.invalidCompatibility
        }
        let duration = payload.expiresAt.timeIntervalSince(payload.validFrom)
        guard payload.validFrom < payload.expiresAt,
              duration >= 20 * 60 * 60,
              duration <= 27 * 60 * 60 else {
            throw NFNextDayEnhancementValidationError.invalidValidityWindow
        }
        guard !payload.enhancements.isEmpty,
              Set(payload.enhancements.map(\.deterministicExerciseID)).count == payload.enhancements.count else {
            throw NFNextDayEnhancementValidationError.missingOrDuplicateExerciseIDs
        }
        guard payload.enhancements.allSatisfy({
            $0.route == .onDevice
                && $0.generatedAt < payload.expiresAt
                && !$0.deterministicExerciseID.isEmpty
        }) else {
            throw NFNextDayEnhancementValidationError.invalidRoute
        }
    }

    private static func discloses(_ token: NFDisclosureToken, in combined: String) -> Bool {
        let value = canonical(token.value)
        guard !value.isEmpty else { return false }
        switch token.kind {
        case .phrase:
            guard value.count >= 2 else { return false }
            if value.count <= 7 {
                let escaped = NSRegularExpression.escapedPattern(for: value)
                return combined.range(
                    of: "(?<![\\p{L}\\p{N}])\(escaped)(?![\\p{L}\\p{N}])",
                    options: .regularExpression
                ) != nil
            }
            return combined.contains(value)
        case .numeric:
            let escaped = NSRegularExpression.escapedPattern(for: value)
            return combined.range(of: "(?<![0-9.])\(escaped)(?![0-9.])", options: .regularExpression) != nil
        }
    }

    private static func canonical(_ value: String) -> String {
        value
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
    }
}

@MainActor
final class NFNextDayEnhancementCache {
    static let shared = NFNextDayEnhancementCache()
    static let folderName = "AI-Presentation-Cache"
    static let fileName = "next-day-enhancements-v1.json"

    private let fileManager: FileManager
    private let suppliedRootURL: URL?

    init(rootURL: URL? = nil, fileManager: FileManager = .default) {
        suppliedRootURL = rootURL
        self.fileManager = fileManager
    }

    func persist(
        _ payload: NFNextDayEnhancementPayload,
        validating request: NFPresentationEnhancementGenerationRequest
    ) throws {
        guard request.compatibilityFingerprint == payload.compatibilityFingerprint else {
            throw NFNextDayEnhancementValidationError.invalidCompatibility
        }
        let validated = try NFPresentationEnhancementValidator.validate(
            payload.enhancements,
            for: request
        )
        let canonicalPayload = NFNextDayEnhancementPayload(
            compatibility: payload.compatibility,
            compatibilityFingerprint: payload.compatibilityFingerprint,
            validFrom: payload.validFrom,
            expiresAt: payload.expiresAt,
            enhancements: validated
        )
        try NFPresentationEnhancementValidator.validatePayload(canonicalPayload)
        let directory = try rootURL()
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        protectDirectory(directory)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(canonicalPayload)
        try data.write(to: cacheFileURL(in: directory), options: secureWritingOptions)
        protectFile(cacheFileURL(in: directory))
    }

    func load(
        expected compatibility: NFNextDayEnhancementCompatibility,
        at date: Date = Date()
    ) -> NFNextDayEnhancementPayload? {
        guard let url = try? cacheFileURL(),
              let data = try? Data(contentsOf: url),
              let payload = try? JSONDecoder().decode(NFNextDayEnhancementPayload.self, from: data) else {
            return nil
        }
        guard (try? NFPresentationEnhancementValidator.validatePayload(payload)) != nil else {
            try? fileManager.removeItem(at: url)
            return nil
        }
        guard payload.expiresAt > date else {
            try? fileManager.removeItem(at: url)
            return nil
        }
        guard payload.compatibility == compatibility,
              payload.compatibilityFingerprint == compatibility.fingerprint else {
            // A foreground lookup for today's plan must not destroy a valid
            // cache prepared for tomorrow. Drift within the same logical day
            // (profile, replacement, locale, mode, quarantine, or versions)
            // is incompatible and is removed immediately.
            if payload.compatibility.localDayKey == compatibility.localDayKey {
                try? fileManager.removeItem(at: url)
            }
            return nil
        }
        // A valid future cache remains on disk but cannot be consumed early.
        guard payload.validFrom <= date else { return nil }
        return payload
    }

    func preparedPayload(
        expected compatibility: NFNextDayEnhancementCompatibility,
        at date: Date = Date()
    ) -> NFNextDayEnhancementPayload? {
        guard let url = try? cacheFileURL(),
              let data = try? Data(contentsOf: url),
              let payload = try? JSONDecoder().decode(NFNextDayEnhancementPayload.self, from: data) else {
            return nil
        }
        guard (try? NFPresentationEnhancementValidator.validatePayload(payload)) != nil,
              payload.expiresAt > date else {
            try? fileManager.removeItem(at: url)
            return nil
        }
        guard payload.compatibility == compatibility,
              payload.compatibilityFingerprint == compatibility.fingerprint else {
            if payload.compatibility.localDayKey == compatibility.localDayKey {
                try? fileManager.removeItem(at: url)
            }
            return nil
        }
        return payload
    }

    @discardableResult
    func purgeExpiredOrInvalid(at date: Date = Date()) -> Bool {
        guard let url = try? cacheFileURL(), fileManager.fileExists(atPath: url.path) else { return false }
        guard let data = try? Data(contentsOf: url),
              let payload = try? JSONDecoder().decode(NFNextDayEnhancementPayload.self, from: data),
              (try? NFPresentationEnhancementValidator.validatePayload(payload)) != nil,
              payload.expiresAt > date else {
            try? fileManager.removeItem(at: url)
            return true
        }
        return false
    }

    func removeAll() {
        guard let url = try? cacheFileURL() else { return }
        try? fileManager.removeItem(at: url)
    }

    func removeAllVerifying() throws {
        let url = try cacheFileURL()
        if fileManager.fileExists(atPath: url.path) {
            try fileManager.removeItem(at: url)
        }
        guard !fileManager.fileExists(atPath: url.path) else {
            throw CocoaError(.fileWriteUnknown)
        }
    }

    func payloadByteCount() -> Int64 {
        guard let url = try? cacheFileURL(),
              let attributes = try? fileManager.attributesOfItem(atPath: url.path) else { return 0 }
        return (attributes[.size] as? NSNumber)?.int64Value ?? 0
    }

    func expiredOrInvalidCount(at date: Date = Date()) -> Int {
        guard let url = try? cacheFileURL(), fileManager.fileExists(atPath: url.path) else { return 0 }
        guard let data = try? Data(contentsOf: url),
              let payload = try? JSONDecoder().decode(NFNextDayEnhancementPayload.self, from: data),
              (try? NFPresentationEnhancementValidator.validatePayload(payload)) != nil,
              payload.expiresAt > date else { return 1 }
        return 0
    }

    func cacheFileURL() throws -> URL {
        cacheFileURL(in: try rootURL())
    }

    private func rootURL() throws -> URL {
        if let suppliedRootURL { return suppliedRootURL }
        let support = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        return support.appending(path: Self.folderName, directoryHint: .isDirectory)
    }

    private func cacheFileURL(in directory: URL) -> URL {
        directory.appending(path: Self.fileName, directoryHint: .notDirectory)
    }

    private var secureWritingOptions: Data.WritingOptions {
        #if os(iOS) || os(tvOS) || os(watchOS) || os(visionOS)
        [.atomic, .completeFileProtection]
        #else
        [.atomic]
        #endif
    }

    private func protectDirectory(_ url: URL) {
        var attributes: [FileAttributeKey: Any] = [.posixPermissions: 0o700]
        #if os(iOS) || os(tvOS) || os(watchOS) || os(visionOS)
        attributes[.protectionKey] = FileProtectionType.complete
        #endif
        try? fileManager.setAttributes(attributes, ofItemAtPath: url.path)
    }

    private func protectFile(_ url: URL) {
        var attributes: [FileAttributeKey: Any] = [.posixPermissions: 0o600]
        #if os(iOS) || os(tvOS) || os(watchOS) || os(visionOS)
        attributes[.protectionKey] = FileProtectionType.complete
        #endif
        try? fileManager.setAttributes(attributes, ofItemAtPath: url.path)
    }
}

protocol NFPresentationEnhancementGenerating: Sendable {
    func isAvailable(localeIdentifier: String) async -> Bool
    func generate(
        _ request: NFPresentationEnhancementGenerationRequest
    ) async throws -> [NFExercisePresentationEnhancement]
}

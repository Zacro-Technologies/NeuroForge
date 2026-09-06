import Foundation

struct NFAuthoringPresentationRequest: Sendable {
    let authoringRequest: NFAuthoringRequest
    let anchorQuestions: [NFAuthoredQuestion]
    let repairNotes: [String]

    var scaffoldingLevel: NFAuthoringScaffoldingLevel {
        NFAuthoringScaffoldingLevel(difficulty: authoringRequest.difficulty)
    }
}

typealias NFAuthoringPresentationGenerator = @Sendable (
    NFAuthoringPresentationRequest
) async throws -> [NFExercisePresentationEnhancement]

typealias NFAuthoringOnDeviceRouteResolver = @Sendable (
    NFAuthoringRequest
) async -> NFAIRouteSnapshot

enum NFAuthoringPresentationValidationError: Error, Equatable, Sendable {
    case missingRequestAnchor(String)
    case invalidScaffolding(String)
    case invalidSourceBinding(String)
    case unsafePresentation(String)
}

enum NFAuthoringPresentationValidator {
    static func validate(
        _ enhancements: [NFExercisePresentationEnhancement],
        for request: NFAuthoringPresentationRequest
    ) throws -> [NFExercisePresentationEnhancement] {
        let authoring = request.authoringRequest
        let seeds = request.anchorQuestions.map { question in
            NFPresentationEnhancementSeed(
                deterministicExerciseID: question.id,
                lab: question.lab,
                field: authoring.field,
                title: question.style.title,
                prompt: question.prompt,
                instructions: question.context,
                forbiddenAnswerStrings: [question.correctAnswer] + question.acceptedAnswers
            )
        }
        let bounded = try NFPresentationEnhancementValidator.validate(
            enhancements,
            for: NFPresentationEnhancementGenerationRequest(
                compatibilityFingerprint: "ai-studio.\(authoring.id.uuidString)",
                localeIdentifier: authoring.localeIdentifier,
                aiMode: authoring.aiMode,
                seeds: seeds
            )
        )
        let questions = Dictionary(uniqueKeysWithValues: request.anchorQuestions.map { ($0.id, $0) })
        let expectedScaffolding = request.scaffoldingLevel.rawValue
        let topic = authoring.customTopic.trimmingCharacters(in: .whitespacesAndNewlines)
        let objective = authoring.learningObjective.trimmingCharacters(in: .whitespacesAndNewlines)
        let requiredAnchors = [
            authoring.field.title,
            topic.isEmpty ? authoring.field.title : topic,
            objective.isEmpty ? authoring.lab.subtitle : objective
        ]
        let prohibited = [
            "chain of thought", "hidden reasoning", "system prompt", "developer message",
            "ignore previous instructions", "ignore all instructions", "reveal the prompt",
            "<script", "javascript:"
        ]

        for enhancement in bounded {
            guard let question = questions[enhancement.deterministicExerciseID] else {
                throw NFAuthoringPresentationValidationError.missingRequestAnchor(
                    enhancement.deterministicExerciseID
                )
            }
            guard enhancement.scaffoldingLevel == expectedScaffolding else {
                throw NFAuthoringPresentationValidationError.invalidScaffolding(question.id)
            }
            let expectedCitations = question.citationChunkIDs
            guard enhancement.sourceChunkIDs == expectedCitations else {
                throw NFAuthoringPresentationValidationError.invalidSourceBinding(question.id)
            }
            let combined = [
                enhancement.contextLabel,
                enhancement.coachingHint,
                enhancement.transferLens
            ].joined(separator: " ")
            guard requiredAnchors.allSatisfy({ containsRequestAnchor($0, in: combined) }) else {
                throw NFAuthoringPresentationValidationError.missingRequestAnchor(question.id)
            }
            if prohibited.contains(where: { combined.localizedCaseInsensitiveContains($0) }) {
                throw NFAuthoringPresentationValidationError.unsafePresentation(question.id)
            }
            if !expectedCitations.isEmpty {
                let support = NFSourceSupportValidator.evaluate(
                    answer: enhancement.contextLabel,
                    acceptedAnswers: [],
                    explanation: enhancement.transferLens,
                    decisiveStep: enhancement.coachingHint,
                    citationChunkIDs: enhancement.sourceChunkIDs,
                    sourceChunks: authoring.sourceChunks
                )
                guard support != .citationIdentifiersOnly else {
                    throw NFAuthoringPresentationValidationError.invalidSourceBinding(question.id)
                }
            }
        }
        return bounded
    }

    private static func containsRequestAnchor(_ anchor: String, in value: String) -> Bool {
        let canonicalValue = canonical(value)
        let canonicalAnchor = canonical(anchor)
        guard !canonicalAnchor.isEmpty else { return true }
        if canonicalValue.contains(canonicalAnchor) { return true }
        let tokens = canonicalAnchor
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count >= 3 }
        return !tokens.isEmpty && tokens.contains(where: canonicalValue.contains)
    }

    private static func canonical(_ value: String) -> String {
        value.folding(
            options: [.caseInsensitive, .diacriticInsensitive],
            locale: Locale(identifier: "en_US_POSIX")
        )
    }
}

enum NFSourceSupportValidator {
    static func evaluate(
        answer: String,
        acceptedAnswers: [String],
        explanation: String,
        decisiveStep: String,
        citationChunkIDs: [String],
        sourceChunks: [NFSourceChunk]
    ) -> NFSourceSupportLevel {
        guard !sourceChunks.isEmpty else { return .notApplicable }

        let citedIDs = Set(citationChunkIDs)
        let citedChunks = sourceChunks.filter { citedIDs.contains($0.id) }
        guard !citedChunks.isEmpty else { return .citationIdentifiersOnly }

        let citedText = citedChunks.map(\.text).joined(separator: "\n")
        let normalizedSource = normalizedText(citedText)
        let proposedAnswers = ([answer] + acceptedAnswers)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        if proposedAnswers.contains(where: { candidate in
            let normalizedCandidate = normalizedText(candidate)
            let candidateTokens = substantiveTokens(candidate)
            return normalizedCandidate.count >= 8
                && !candidateTokens.isEmpty
                && normalizedSource.contains(normalizedCandidate)
        }) {
            return .exactAnswerText
        }

        let sourceTokens = Set(substantiveTokens(citedText))
        guard !sourceTokens.isEmpty else { return .citationIdentifiersOnly }

        for candidate in proposedAnswers {
            let answerTokens = Set(substantiveTokens(candidate))
            let overlap = answerTokens.intersection(sourceTokens).count
            if answerTokens.count == 1,
               let onlyToken = answerTokens.first,
               onlyToken.count >= 5,
               overlap == 1 {
                return .lexicalOverlap
            }
            if answerTokens.count >= 2,
               overlap >= 2,
               Double(overlap) / Double(answerTokens.count) >= 0.5 {
                return .lexicalOverlap
            }
        }

        let rationaleTokens = Set(substantiveTokens(explanation + " " + decisiveStep))
        let rationaleOverlap = rationaleTokens.intersection(sourceTokens).count
        let requiredRationaleOverlap = min(3, max(2, Int(ceil(Double(rationaleTokens.count) * 0.10))))
        if rationaleTokens.count >= 2, rationaleOverlap >= requiredRationaleOverlap {
            return .lexicalOverlap
        }

        return .citationIdentifiersOnly
    }

    static func rank(_ level: NFSourceSupportLevel) -> Int {
        switch level {
        case .notApplicable: 0
        case .citationIdentifiersOnly: 1
        case .lexicalOverlap: 2
        case .deterministicSourceTransformation: 3
        case .exactAnswerText: 4
        }
    }

    private static func normalizedText(_ value: String) -> String {
        value
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    private static func substantiveTokens(_ value: String) -> [String] {
        normalizedText(value)
            .split(separator: " ")
            .map(String.init)
            .filter { token in
                (token.count >= 3 || token.allSatisfy(\.isNumber)) && !stopwords.contains(token)
            }
    }

    private static let stopwords: Set<String> = [
        "about", "after", "also", "answer", "because", "before", "being", "between", "could",
        "does", "each", "every", "from", "have", "into", "most", "only", "other", "should",
        "source", "than", "that", "their", "there", "these", "they", "this", "through", "under",
        "using", "which", "while", "with", "would"
    ]
}

/// Fail-closed authority gate for model-authored answer keys. Schema agreement,
/// lexical overlap, and a model explanation are never treated as proof. The only
/// accepted model form is a fixed exact-restatement contract whose answer can be
/// matched independently against one cited excerpt.
enum NFModelAnswerAuthorityPolicy {
    static func exactRestatementPrompt(
        for style: NFQuestionStyle,
        localeIdentifier: String
    ) -> String? {
        let locale = NFAppLocalization.locale(identifier: localeIdentifier)
        return switch style {
        case .multipleChoice:
            NFAppLocalization.localized(
                "Which statement is stated verbatim in the cited excerpt?",
                locale: locale,
                comment: "Fixed independently validated prompt for a source-grounded multiple-choice question. The answer must be one exact contiguous statement from the cited excerpt."
            )
        case .shortAnswer:
            NFAppLocalization.localized(
                "Restate the decisive supported claim from the cited excerpt, preserving every qualifier.",
                locale: locale,
                comment: "Fixed independently validated prompt for a source-grounded short-answer question. The answer must preserve every qualifier from one exact contiguous cited statement."
            )
        default:
            nil
        }
    }

    static func requestIneligibilityReason(_ request: NFAuthoringRequest) -> String? {
        let locale = NFAppLocalization.locale(identifier: request.localeIdentifier)
        guard request.usesSourceMaterial else {
            return NFAppLocalization.localized("Independent answer authority is unavailable without cited source material; used deterministic authoring.", locale: locale, comment: "AI routing explanation when a model cannot provide an independently checked answer key.")
        }
        switch request.style {
        case .multipleChoice, .shortAnswer:
            return nil
        case .numerical:
            return NFAppLocalization.localized("Numerical model output has no independently validated operand-and-unit contract; used deterministic calculation authoring.", locale: locale, comment: "AI routing explanation for numerical questions that require deterministic answer authority.")
        case .proofOrDerivation, .debugging, .experimentalDesign, .dataInterpretation, .spatialTransformation:
            return NFAppLocalization.localized("This reasoning form cannot establish its answer key from model self-consistency; used the independently computed deterministic transformation.", locale: locale, comment: "AI routing explanation for reasoning questions that require deterministic answer authority.")
        }
    }

    static func violations(
        style: NFQuestionStyle,
        prompt: String,
        answer: String,
        acceptedAnswers: [String],
        choices: [String],
        citationChunkIDs: [String],
        sourceChunks: [NFSourceChunk],
        localeIdentifier: String = "en"
    ) -> [String] {
        guard requestStyleIsEligible(style) else {
            return ["The model response form has no independent answer-authority contract."]
        }
        guard citationChunkIDs.count == 1,
              let citationID = citationChunkIDs.first,
              let citedChunk = sourceChunks.first(where: { $0.id == citationID }) else {
            return ["The model key must cite exactly one supplied excerpt under the exact-restatement contract."]
        }

        var notes: [String] = []
        guard let expectedPrompt = exactRestatementPrompt(
            for: style,
            localeIdentifier: localeIdentifier
        ) else {
            return ["The model response form has no localized independent answer-authority contract."]
        }
        if canonicalWhitespace(prompt) != canonicalWhitespace(expectedPrompt) {
            notes.append("The model changed the fixed exact-restatement question contract.")
        }
        if !acceptedAnswers.isEmpty {
            notes.append("Model-proposed alternate answers are not independently authoritative.")
        }

        let canonicalAnswer = canonicalWhitespace(answer)
        let canonicalSource = canonicalWhitespace(citedChunk.text)
        let answerTokenCount = canonicalAnswer.split(separator: " ").count
        let hasStatementTerminator = canonicalAnswer.last.map { ".!?。！？".contains($0) } == true
        if canonicalAnswer.count < 20
            || answerTokenCount < 4
            || !hasStatementTerminator
            || !canonicalSource.contains(canonicalAnswer) {
            notes.append("The proposed key is not an exact contiguous restatement from its cited excerpt.")
        }

        if style == .multipleChoice {
            let exactSourceChoices = choices.filter {
                let candidate = canonicalWhitespace($0)
                return candidate.count >= 20
                    && candidate.split(separator: " ").count >= 4
                    && canonicalSource.contains(candidate)
            }
            if exactSourceChoices.count != 1 || canonicalWhitespace(exactSourceChoices[0]) != canonicalAnswer {
                notes.append("Multiple choice must have exactly one verbatim source-supported option, and it must be the key.")
            }
        } else if !choices.isEmpty {
            notes.append("The fixed short-answer authority contract cannot include choices.")
        }
        return notes
    }

    private static func requestStyleIsEligible(_ style: NFQuestionStyle) -> Bool {
        style == .multipleChoice || style == .shortAnswer
    }

    private static func canonicalWhitespace(_ value: String) -> String {
        value
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
    }
}

actor NFAuthoringEngine: NFQuestionAuthoring {
    static let shared = NFAuthoringEngine()
    /// Version 14 adds source-linked validation for the bounded external
    /// Question Writer route while retaining self-check-only answer authority.
    static let validationVersion = 14
    static let defaultCacheCapacity = 64
    static let defaultCacheTTL: TimeInterval = 60 * 60

    private struct CacheEntry: Sendable {
        let result: NFAuthoringResult
        let expiresAt: Date
        var accessSequence: UInt64
    }

    private var cache: [String: CacheEntry] = [:]
    private let cacheCapacity: Int
    private let cacheTTL: TimeInterval
    private let now: @Sendable () -> Date
    private let onDeviceRouteResolver: NFAuthoringOnDeviceRouteResolver?
    private let presentationGenerator: NFAuthoringPresentationGenerator?
    private var accessSequence: UInt64 = 0

    init(
        cacheCapacity: Int = NFAuthoringEngine.defaultCacheCapacity,
        cacheTTL: TimeInterval = NFAuthoringEngine.defaultCacheTTL,
        now: @escaping @Sendable () -> Date = { Date() },
        onDeviceRouteResolver: NFAuthoringOnDeviceRouteResolver? = nil,
        presentationGenerator: NFAuthoringPresentationGenerator? = nil
    ) {
        self.cacheCapacity = max(1, cacheCapacity)
        self.cacheTTL = max(0, cacheTTL)
        self.now = now
        self.onDeviceRouteResolver = onDeviceRouteResolver
        self.presentationGenerator = presentationGenerator
    }

    func routeStatus(for request: NFAuthoringRequest) async -> [NFAIRouteSnapshot] {
        let locale = NFAppLocalization.locale(identifier: request.localeIdentifier)
        let policyForbidsAI = request.documentPolicies.contains(.noAI)

        let onDevice: NFAIRouteSnapshot
        if let onDeviceRouteResolver {
            onDevice = await onDeviceRouteResolver(request)
        } else if request.aiMode == .disabled || policyForbidsAI {
            onDevice = NFAIRouteSnapshot(
                route: .onDevice,
                state: .forbidden,
                reason: request.aiMode == .disabled
                    ? NFAppLocalization.localized("AI is disabled.", locale: locale, comment: "On-device AI route policy explanation.")
                    : NFAppLocalization.localized("A selected document has a No AI policy.", locale: locale, comment: "On-device AI route policy explanation.")
            )
        } else {
            onDevice = NFAIRouteSnapshot(
                route: .onDevice,
                state: .unavailable,
                reason: NFAppLocalization.localized("Practice Studio creates question sets offline.", locale: locale, comment: "Production authoring route explanation when no injected test model route is configured.")
            )
        }

        return [
            onDevice,
            NFAIRouteSnapshot(
                route: .deterministicFallback,
                state: .fallback,
                reason: NFAppLocalization.localized("A deterministic, offline exercise is always available.", locale: locale, comment: "Deterministic AI-fallback route explanation.")
            )
        ]
    }

    func author(_ request: NFAuthoringRequest) async throws -> NFAuthoringResult {
        try Task.checkCancellation()
        guard !request.usesSourceMaterial || request.style == .shortAnswer else {
            throw NFAIError.invalidOutput([
                "Selected-source practice currently supports cited prose short-answer recall only."
            ])
        }
        let cacheKey = makeCacheKey(request)
        let lookupDate = now()
        purgeExpiredCache(at: lookupDate)
        if var cached = cache[cacheKey] {
            if isValidCacheEntry(cached, request: request, cacheKey: cacheKey) {
                try Task.checkCancellation()
                accessSequence &+= 1
                cached.accessSequence = accessSequence
                cache[cacheKey] = cached
                return rebound(cached.result, for: request)
            }
            cache.removeValue(forKey: cacheKey)
        }

        let routes = await routeStatus(for: request)
        try Task.checkCancellation()
        let onDeviceReady = routes.first { $0.route == .onDevice }?.state == .ready
        let policyForbidsAI = request.documentPolicies.contains(.noAI)
        let authorityQuestions = NFDeterministicAuthoringFallback.generate(request)
        guard !authorityQuestions.isEmpty else {
            throw NFAIError.invalidOutput([
                "The selected material does not contain a complete, distinct proposition that supports this question style."
            ])
        }
        guard authorityQuestions.allSatisfy(\.hasValidResponseSchema) else {
            throw NFAIError.invalidOutput(["The generated questions did not pass the response and content checks."])
        }
        var validationNotes: [String] = []
        var repairCount = 0
        // The Studio owns the localized partial-source notice because it can
        // place that guidance beside the imported-material control. Do not
        // leak a second, raw-English route note from the authoring contract.

        if request.aiMode != .disabled, !policyForbidsAI, onDeviceReady {
            let initialRequest = NFAuthoringPresentationRequest(
                authoringRequest: request,
                anchorQuestions: authorityQuestions,
                repairNotes: []
            )
            do {
                let generated = try await generatePresentation(initialRequest)
                try Task.checkCancellation()
                let validated = try NFAuthoringPresentationValidator.validate(
                    generated,
                    for: initialRequest
                )
                return try finishContextualizedResult(
                    enhancements: validated,
                    authorityQuestions: authorityQuestions,
                    request: request,
                    routes: routes,
                    repairCount: 0,
                    cacheKey: cacheKey,
                    validationNotes: []
                )
            } catch is CancellationError {
                throw CancellationError()
            } catch where Task.isCancelled {
                throw CancellationError()
            } catch {
                let locale = NFAppLocalization.locale(identifier: request.localeIdentifier)
                if presentationFailureCanBeRepaired(error) {
                    repairCount = 1
                    validationNotes.append(NFAppLocalization.localized("The first optional presentation draft failed bounded checks; one repair was attempted.", locale: locale, comment: "AI Practice Studio validation note before its single bounded repair attempt."))
                    do {
                        let repairRequest = NFAuthoringPresentationRequest(
                            authoringRequest: request,
                            anchorQuestions: authorityQuestions,
                            repairNotes: [String(describing: error)]
                        )
                        let repaired = try await generatePresentation(repairRequest)
                        try Task.checkCancellation()
                        let validated = try NFAuthoringPresentationValidator.validate(
                            repaired,
                            for: repairRequest
                        )
                        return try finishContextualizedResult(
                            enhancements: validated,
                            authorityQuestions: authorityQuestions,
                            request: request,
                            routes: routes,
                            repairCount: repairCount,
                            cacheKey: cacheKey,
                            validationNotes: validationNotes
                        )
                    } catch is CancellationError {
                        throw CancellationError()
                    } catch where Task.isCancelled {
                        throw CancellationError()
                    } catch {
                        validationNotes.append(NFAppLocalization.localized("The repaired context still failed bounded checks; the unchanged deterministic exercise set was used.", locale: locale, comment: "AI Practice Studio validation note after its single repair attempt falls back."))
                    }
                } else {
                    validationNotes.append(NFAppLocalization.localized("The optional presentation service became unavailable or did not finish; the unchanged deterministic exercise set was used without a repair attempt.", locale: locale, comment: "AI Practice Studio fallback note when optional presentation fails for a non-repairable availability or runtime reason."))
                }
            }
        } else if request.aiMode == .disabled {
            validationNotes.append(NFAppLocalization.localized("AI is disabled; used offline deterministic authoring.", locale: NFAppLocalization.locale(identifier: request.localeIdentifier), comment: "AI generation fallback explanation."))
        } else if policyForbidsAI {
            validationNotes.append(NFAppLocalization.localized("A selected document forbids AI; used offline deterministic authoring.", locale: NFAppLocalization.locale(identifier: request.localeIdentifier), comment: "AI generation fallback explanation caused by a per-document policy."))
        } else {
            validationNotes.append(NFAppLocalization.localized("Optional presentation is unavailable; the unchanged deterministic exercise set was used.", locale: NFAppLocalization.locale(identifier: request.localeIdentifier), comment: "AI Practice Studio fallback explanation when optional presentation context is unavailable."))
        }

        try Task.checkCancellation()
        let result = makeResult(
            questions: authorityQuestions,
            request: request,
            route: .deterministicFallback,
            reason: validationNotes.last ?? NFAppLocalization.localized("Deterministic fallback selected.", locale: NFAppLocalization.locale(identifier: request.localeIdentifier), comment: "AI generation provenance fallback explanation."),
            modelIdentifier: "neuroforge.deterministic-author.v12",
            routes: routes,
            repairCount: repairCount,
            cacheKey: cacheKey,
            validationStatus: NFDeterministicAuthoringFallback.validationStatus(
                for: request,
                questions: authorityQuestions
            ),
            validationNotes: validationNotes
        )
        try Task.checkCancellation()
        storeInCache(result, key: cacheKey)
        return result
    }

    private func presentationFailureCanBeRepaired(_ error: any Error) -> Bool {
        if error is NFAuthoringPresentationValidationError
            || error is NFNextDayEnhancementValidationError {
            return true
        }
        guard let aiError = error as? NFAIError else {
            // Legacy presentation seams may report generated-schema failures
            // using their own error types, so one bounded repair remains appropriate.
            return true
        }
        return switch aiError {
        case .invalidOutput: true
        case .disabled, .sourcePolicyForbidsAI, .modelUnavailable,
             .unsupportedLocale, .timedOut, .generationFailed: false
        }
    }

    private func finishContextualizedResult(
        enhancements: [NFExercisePresentationEnhancement],
        authorityQuestions: [NFAuthoredQuestion],
        request: NFAuthoringRequest,
        routes: [NFAIRouteSnapshot],
        repairCount: Int,
        cacheKey: String,
        validationNotes: [String]
    ) throws -> NFAuthoringResult {
        let byID = Dictionary(uniqueKeysWithValues: enhancements.map { ($0.deterministicExerciseID, $0) })
        let questions = authorityQuestions.map { question in
            NFAuthoredQuestion(
                id: question.id,
                lab: question.lab,
                style: question.style,
                prompt: question.prompt,
                context: question.context,
                choices: question.choices,
                correctAnswer: question.correctAnswer,
                acceptedAnswers: question.acceptedAnswers,
                explanation: question.explanation,
                hint: question.hint,
                decisiveStep: question.decisiveStep,
                difficulty: question.difficulty,
                citationChunkIDs: question.citationChunkIDs,
                evidenceClass: .documentPractice,
                authoritativeExercise: question.authoritativeExercise,
                presentationEnhancement: byID[question.id]
            )
        }
        guard questions.allSatisfy({ $0.presentationEnhancement != nil }) else {
            throw NFAuthoringPresentationValidationError.missingRequestAnchor("result")
        }
        let authority = NFDeterministicAuthoringFallback.validationStatus(
            for: request,
            questions: authorityQuestions
        )
        let locale = NFAppLocalization.locale(identifier: request.localeIdentifier)
        let result = makeResult(
            questions: questions,
            request: request,
            route: .onDevice,
            reason: repairCount == 0
                ? NFAppLocalization.localized("Optional presentation added bounded field context and coaching around an unchanged deterministic exercise contract.", locale: locale, comment: "AI Practice Studio provenance for successful optional contextualization.")
                : NFAppLocalization.localized("Optional presentation added bounded field context after one schema repair; the deterministic exercise contract remained unchanged.", locale: locale, comment: "AI Practice Studio provenance for successful optional contextualization after one repair."),
            modelIdentifier: enhancements.first?.modelIdentifier
                ?? "legacy.optional-presentation",
            routes: routes,
            repairCount: repairCount,
            cacheKey: cacheKey,
            validationStatus: NFAuthoringValidationStatus(
                level: .deterministicKeyWithModelContext,
                sourceSupport: authority.sourceSupport
            ),
            validationNotes: validationNotes
        )
        try Task.checkCancellation()
        storeInCache(result, key: cacheKey)
        return result
    }

    func cachedResultCount() -> Int {
        purgeExpiredCache(at: now())
        return cache.count
    }

    func removeAllCachedResults() {
        cache.removeAll(keepingCapacity: false)
    }

    private func storeInCache(_ result: NFAuthoringResult, key: String) {
        guard result.provenance.validationVersion == Self.validationVersion,
              !result.questions.isEmpty,
              result.questions.allSatisfy(\.hasValidResponseSchema) else {
            return
        }
        let insertionDate = now()
        purgeExpiredCache(at: insertionDate)
        accessSequence &+= 1
        cache[key] = CacheEntry(
            result: result,
            expiresAt: insertionDate.addingTimeInterval(cacheTTL),
            accessSequence: accessSequence
        )
        while cache.count > cacheCapacity,
              let leastRecentKey = cache.min(by: { lhs, rhs in
                  if lhs.value.accessSequence == rhs.value.accessSequence {
                      return lhs.key < rhs.key
                  }
                  return lhs.value.accessSequence < rhs.value.accessSequence
              })?.key {
            cache.removeValue(forKey: leastRecentKey)
        }
    }

    private func purgeExpiredCache(at date: Date) {
        cache = cache.filter { $0.value.expiresAt > date }
    }

    private func isValidCacheEntry(
        _ entry: CacheEntry,
        request: NFAuthoringRequest,
        cacheKey: String
    ) -> Bool {
        let result = entry.result
        let allowedCitations = Set(request.sourceChunks.map(\.id))
        let expectedDocumentIDs = Set(request.sourceChunks.map(\.documentID))
        return result.provenance.cacheKey == cacheKey
            && result.provenance.promptVersion == NFAuthoringRequest.promptVersion
            && result.provenance.validationVersion == Self.validationVersion
            && result.provenance.sourceChunkIDs == request.sourceChunks.map(\.id)
            && Set(result.provenance.sourceDocumentIDs) == expectedDocumentIDs
            && (result.questions.count == request.count
                || (request.usesSourceMaterial
                    && request.style == .shortAnswer
                    && !result.questions.isEmpty
                    && result.questions.count < request.count))
            && (result.provenance.route != .onDevice
                || isValidContextualizedResult(result, request: request))
            && result.questions.allSatisfy { question in
                question.lab == request.lab
                    && (question.style == request.style
                        || NFDeterministicAuthoringFallback.isSupportedStyleOverride(
                            from: request.style,
                            to: question.style
                        ))
                    && question.hasValidResponseSchema
                    && (!request.usesSourceMaterial || (
                        !Set(question.authoritativeExercise.provenance.sourceDocumentIDs).isEmpty
                            && Set(question.authoritativeExercise.provenance.sourceDocumentIDs)
                                .isSubset(of: Set(expectedDocumentIDs.map(\.uuidString)))
                    ))
                    && question.authoritativeExercise.provenance.sourceChunkIDs
                        == question.citationChunkIDs
                    && Set(question.citationChunkIDs).isSubset(of: allowedCitations)
                    && (!request.usesSourceMaterial || !question.citationChunkIDs.isEmpty)
            }
    }

    private func isValidContextualizedResult(
        _ result: NFAuthoringResult,
        request: NFAuthoringRequest
    ) -> Bool {
        guard result.validationStatus.level == .deterministicKeyWithModelContext else {
            return false
        }
        let enhancements = result.questions.compactMap(\.presentationEnhancement)
        guard enhancements.count == result.questions.count else { return false }
        let presentationRequest = NFAuthoringPresentationRequest(
            authoringRequest: request,
            anchorQuestions: result.questions,
            repairNotes: []
        )
        return (try? NFAuthoringPresentationValidator.validate(
            enhancements,
            for: presentationRequest
        )) != nil
    }

    private func rebound(
        _ result: NFAuthoringResult,
        for request: NFAuthoringRequest
    ) -> NFAuthoringResult {
        guard result.provenance.requestID != request.id else { return result }
        let questions = result.questions.map { question in
            NFAuthoredQuestion(
                id: question.id,
                lab: question.lab,
                style: question.style,
                prompt: question.prompt,
                context: question.context,
                choices: question.choices,
                correctAnswer: question.correctAnswer,
                acceptedAnswers: question.acceptedAnswers,
                explanation: question.explanation,
                hint: question.hint,
                decisiveStep: question.decisiveStep,
                difficulty: question.difficulty,
                citationChunkIDs: question.citationChunkIDs,
                evidenceClass: question.evidenceClass,
                authoritativeExercise: question.authoritativeExercise,
                presentationEnhancement: question.presentationEnhancement
            )
        }
        let provenance = result.provenance
        return NFAuthoringResult(
            questions: questions,
            provenance: NFAIGenerationProvenance(
                requestID: request.id,
                generatedAt: provenance.generatedAt,
                route: provenance.route,
                routeReason: provenance.routeReason,
                promptVersion: provenance.promptVersion,
                modelIdentifier: provenance.modelIdentifier,
                sourceChunkIDs: provenance.sourceChunkIDs,
                sourceDocumentIDs: provenance.sourceDocumentIDs,
                validationVersion: provenance.validationVersion,
                repairCount: provenance.repairCount,
                cacheKey: provenance.cacheKey,
                isFallback: provenance.isFallback
            ),
            routeCandidates: result.routeCandidates,
            validationStatus: result.validationStatus,
            validationNotes: result.validationNotes
        )
    }

    private func makeResult(
        questions: [NFAuthoredQuestion],
        request: NFAuthoringRequest,
        route: NFAIRoute,
        reason: String,
        modelIdentifier: String,
        routes: [NFAIRouteSnapshot],
        repairCount: Int,
        cacheKey: String,
        validationStatus: NFAuthoringValidationStatus,
        validationNotes: [String]
    ) -> NFAuthoringResult {
        let sourceDocumentIDs = Array(Set(request.sourceChunks.map(\.documentID))).sorted { $0.uuidString < $1.uuidString }
        return NFAuthoringResult(
            questions: questions,
            provenance: NFAIGenerationProvenance(
                requestID: request.id,
                generatedAt: now(),
                route: route,
                routeReason: reason,
                promptVersion: NFAuthoringRequest.promptVersion,
                modelIdentifier: modelIdentifier,
                sourceChunkIDs: request.sourceChunks.map(\.id),
                sourceDocumentIDs: sourceDocumentIDs,
                validationVersion: Self.validationVersion,
                repairCount: repairCount,
                cacheKey: cacheKey,
                isFallback: route == .deterministicFallback
            ),
            routeCandidates: routes,
            validationStatus: validationStatus,
            validationNotes: validationNotes
        )
    }

    private func modelValidationStatus(
        request _: NFAuthoringRequest,
        sourceSupport: NFSourceSupportLevel
    ) -> NFAuthoringValidationStatus {
        NFAuthoringValidationStatus(
            level: .independentlyCheckedModelKey,
            sourceSupport: sourceSupport
        )
    }

    private func makeCacheKey(_ request: NFAuthoringRequest) -> String {
        let sourceKey = request.sourceChunks.map { "\($0.id):\($0.contentHash)" }.joined(separator: "|")
        let policyKey = request.documentPolicies.map(\.rawValue).sorted().joined(separator: "|")
        let raw = [
            String(NFAuthoringRequest.promptVersion), String(Self.validationVersion),
            request.capability.rawValue, request.lab.rawValue,
            request.field.rawValue, request.customTopic, request.learningObjective, request.style.rawValue,
            String(request.difficulty), request.reasoningLevel.rawValue,
            String(request.count), request.localeIdentifier, String(request.seed),
            request.aiMode.rawValue, policyKey, sourceKey
        ].joined(separator: "¦")
        return String(AdaptiveEngine.fnv1a64(raw), radix: 16)
    }

    private struct ValidationResult {
        let questions: [NFAuthoredQuestion]
        let notes: [String]
        let sourceSupport: NFSourceSupportLevel
    }

    private func validate(drafts: [NFQuestionDraft], request: NFAuthoringRequest) -> ValidationResult {
        var questions: [NFAuthoredQuestion] = []
        var notes: [String] = []
        var sourceSupportLevels: [NFSourceSupportLevel] = []
        let allowedCitations = Set(request.sourceChunks.map(\.id))

        if !request.difficulty.isFinite || !(0...1).contains(request.difficulty) {
            notes.append("The requested difficulty is outside the supported 0-to-1 bounds.")
        }
        if drafts.isEmpty { notes.append("No questions were returned.") }
        if drafts.count != request.count {
            notes.append(NFAppLocalization.formattedReturnedQuestionCount(
                actual: drafts.count,
                requested: request.count,
                locale: NFAppLocalization.locale(identifier: request.localeIdentifier)
            ))
        }

        for (index, draft) in drafts.prefix(request.count).enumerated() {
            let prompt = draft.prompt.trimmingCharacters(in: .whitespacesAndNewlines)
            let answer = draft.correctAnswer.trimmingCharacters(in: .whitespacesAndNewlines)
            let uniqueChoices = Array(NSOrderedSet(array: draft.choices.map {
                $0.trimmingCharacters(in: .whitespacesAndNewlines)
            })).compactMap { $0 as? String }.filter { !$0.isEmpty }

            if prompt.count < 12 || prompt.count > 1_600 { notes.append("Question \(index + 1) has an invalid prompt length.") }
            if answer.isEmpty { notes.append("Question \(index + 1) is missing an answer.") }
            if draft.explanation.trimmingCharacters(in: .whitespacesAndNewlines).count < 8 {
                notes.append("Question \(index + 1) is missing a usable explanation.")
            }
            if request.style == .multipleChoice {
                if uniqueChoices.count != 4 { notes.append("Question \(index + 1) does not have four unique choices.") }
                if !uniqueChoices.contains(answer) { notes.append("Question \(index + 1) answer does not exactly match a choice.") }
            } else if !uniqueChoices.isEmpty {
                notes.append("Question \(index + 1) returned choices for a free-response form.")
            }
            if request.style == .numerical,
               Double(answer.replacingOccurrences(of: ",", with: "")) == nil {
                notes.append("Question \(index + 1) does not have a machine-checkable numerical answer.")
            }
            if request.style == .proofOrDerivation || request.style == .experimentalDesign,
               draft.acceptedAnswers.allSatisfy({ $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
                notes.append("Question \(index + 1) is missing an observable response rubric.")
            }
            if answer.count > 800
                || draft.context.count > 600
                || draft.hint.count > 800
                || draft.decisiveStep.count > 800
                || draft.explanation.count > 2_400
                || uniqueChoices.contains(where: { $0.count > 800 })
                || draft.acceptedAnswers.count > 8
                || draft.acceptedAnswers.contains(where: { $0.count > 800 }) {
                notes.append("Question \(index + 1) exceeds a bounded response field limit.")
            }
            if request.usesSourceMaterial {
                if draft.citationChunkIDs.isEmpty { notes.append("Question \(index + 1) has no source citation.") }
                if !Set(draft.citationChunkIDs).isSubset(of: allowedCitations) {
                    notes.append("Question \(index + 1) cites an unknown source chunk.")
                }
                let sourceSupport = NFSourceSupportValidator.evaluate(
                    answer: answer,
                    acceptedAnswers: draft.acceptedAnswers,
                    explanation: draft.explanation,
                    decisiveStep: draft.decisiveStep,
                    citationChunkIDs: draft.citationChunkIDs,
                    sourceChunks: request.sourceChunks
                )
                sourceSupportLevels.append(sourceSupport)
                if sourceSupport == .citationIdentifiersOnly {
                    notes.append(
                        "Question \(index + 1) cites a known excerpt but has no deterministic lexical support for its proposed answer or explanation. Citation IDs alone do not establish support."
                    )
                }
            } else if !draft.citationChunkIDs.isEmpty {
                notes.append("Question \(index + 1) invented a citation without source material.")
            }
            let safetySurface = ([
                draft.prompt,
                draft.context,
                draft.correctAnswer,
                draft.explanation,
                draft.hint,
                draft.decisiveStep
            ] + draft.choices + draft.acceptedAnswers).joined(separator: " ")
            let prohibited = [
                "chain of thought", "hidden reasoning", "system prompt", "developer message",
                "ignore previous instructions", "ignore all instructions", "reveal the prompt",
                "<script", "javascript:"
            ]
            if prohibited.contains(where: { safetySurface.localizedCaseInsensitiveContains($0) }) {
                notes.append("Question \(index + 1) exposes or follows prohibited instruction text.")
            }
            let authorityViolations = NFModelAnswerAuthorityPolicy.violations(
                style: request.style,
                prompt: prompt,
                answer: answer,
                acceptedAnswers: draft.acceptedAnswers.map {
                    $0.trimmingCharacters(in: .whitespacesAndNewlines)
                }.filter { !$0.isEmpty },
                choices: uniqueChoices,
                citationChunkIDs: draft.citationChunkIDs,
                sourceChunks: request.sourceChunks,
                localeIdentifier: request.localeIdentifier
            )
            notes.append(contentsOf: authorityViolations.map {
                "Question \(index + 1): \($0)"
            })

            let questionID = "ai.\(request.id.uuidString).\(index)"
            let normalizedAcceptedAnswers = draft.acceptedAnswers.map {
                $0.trimmingCharacters(in: .whitespacesAndNewlines)
            }.filter { !$0.isEmpty }
            let normalizedContext = draft.context.trimmingCharacters(in: .whitespacesAndNewlines)
            let normalizedExplanation = draft.explanation.trimmingCharacters(in: .whitespacesAndNewlines)
            let normalizedHint = draft.hint.trimmingCharacters(in: .whitespacesAndNewlines)
            let normalizedDecisiveStep = draft.decisiveStep.trimmingCharacters(in: .whitespacesAndNewlines)
            let authority = NFAuthoredExerciseAuthority.make(
                id: questionID,
                lab: request.lab,
                style: request.style,
                prompt: prompt,
                context: normalizedContext,
                choices: uniqueChoices,
                correctAnswer: answer,
                acceptedAnswers: normalizedAcceptedAnswers,
                explanation: normalizedExplanation,
                hint: normalizedHint,
                decisiveStep: normalizedDecisiveStep,
                difficulty: request.difficulty,
                citationChunkIDs: draft.citationChunkIDs,
                evidenceClass: .documentPractice,
                request: request
            )
            questions.append(NFAuthoredQuestion(
                id: questionID,
                lab: request.lab,
                style: request.style,
                prompt: prompt,
                context: normalizedContext,
                choices: uniqueChoices,
                correctAnswer: answer,
                acceptedAnswers: normalizedAcceptedAnswers,
                explanation: normalizedExplanation,
                hint: normalizedHint,
                decisiveStep: normalizedDecisiveStep,
                difficulty: request.difficulty,
                citationChunkIDs: draft.citationChunkIDs,
                evidenceClass: .documentPractice,
                authoritativeExercise: authority
            ))
        }
        let sourceSupport = sourceSupportLevels.min {
            NFSourceSupportValidator.rank($0) < NFSourceSupportValidator.rank($1)
        } ?? .notApplicable
        return ValidationResult(questions: questions, notes: notes, sourceSupport: sourceSupport)
    }

    private struct NFQuestionDraft: Sendable {
        let prompt: String
        let context: String
        let choices: [String]
        let correctAnswer: String
        let acceptedAnswers: [String]
        let explanation: String
        let hint: String
        let decisiveStep: String
        let citationChunkIDs: [String]
    }

    private func generatePresentation(
        _ request: NFAuthoringPresentationRequest
    ) async throws -> [NFExercisePresentationEnhancement] {
        if let presentationGenerator {
            return try await presentationGenerator(request)
        }
        throw NFAIError.modelUnavailable("No presentation generator is configured.")
    }

}

private enum NFDeterministicAuthoringFallback {
    private static func locale(for request: NFAuthoringRequest) -> Locale {
        NFAppLocalization.locale(identifier: request.localeIdentifier)
    }

    private static func localized(
        _ value: String.LocalizationValue,
        request: NFAuthoringRequest
    ) -> String {
        NFAppLocalization.localized(value, locale: locale(for: request))
    }

    /// The prompt template contributes its own learner-facing noun. Remove the
    /// same terminal noun from a supplied topic so reviewed copy such as
    /// “merge sort implementation” cannot become “implementation implementation”.
    private static func topicWithoutTrailingQualifier(
        _ topic: String,
        qualifier: String
    ) -> String {
        let trimmed = topic.trimmingCharacters(in: .whitespacesAndNewlines)
        let suffix = " \(qualifier)"
        guard trimmed.range(of: suffix, options: [.caseInsensitive, .anchored, .backwards]) != nil else {
            return trimmed
        }
        let result = String(trimmed.dropLast(suffix.count))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return result.isEmpty ? trimmed : result
    }

    static func isSupportedStyleOverride(
        from requestedStyle: NFQuestionStyle,
        to questionStyle: NFQuestionStyle
    ) -> Bool {
        switch requestedStyle {
        case .numerical:
            [.shortAnswer, .proofOrDerivation, .debugging].contains(questionStyle)
        case .spatialTransformation:
            questionStyle == .shortAnswer
        default:
            false
        }
    }

    static func generate(_ request: NFAuthoringRequest) -> [NFAuthoredQuestion] {
        guard !request.usesSourceMaterial || request.style == .shortAnswer else {
            return []
        }
        let generatedCount: Int
        if request.usesSourceMaterial {
            generatedCount = min(request.count, sourcePropositionCandidates(request).count)
        } else {
            generatedCount = request.count
        }
        return (0..<generatedCount).map { index in
            question(request, index: index)
        }
    }

    static func validationStatus(
        for request: NFAuthoringRequest,
        questions: [NFAuthoredQuestion]
    ) -> NFAuthoringValidationStatus {
        guard request.usesSourceMaterial else {
            return NFAuthoringValidationStatus(level: .deterministicKey, sourceSupport: .notApplicable)
        }
        let chunksByID = Dictionary(uniqueKeysWithValues: request.sourceChunks.map { ($0.id, $0) })
        let everyAnswerIsExactCitedText = !questions.isEmpty && questions.allSatisfy { question in
            guard question.citationChunkIDs.count == 1,
                  let chunkID = question.citationChunkIDs.first,
                  let chunk = chunksByID[chunkID] else { return false }
            let source = chunk.text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
            let answer = question.correctAnswer.split(whereSeparator: \.isWhitespace).joined(separator: " ")
            return !answer.isEmpty && source.contains(answer)
        }
        if request.style == .shortAnswer,
           everyAnswerIsExactCitedText {
            return NFAuthoringValidationStatus(level: .exactSourceRestatement, sourceSupport: .exactAnswerText)
        }
        return NFAuthoringValidationStatus(
            level: .deterministicKey,
            sourceSupport: .deterministicSourceTransformation
        )
    }

    private struct Basis {
        let id: String
        let semanticVariant: Int
        /// Six independent reasoning slots are enough to keep the default
        /// six-question starter sets from cycling back to the same mechanic.
        /// This is deliberately separate from `semanticVariant`, whose five
        /// slots are part of older source-grounded transformations.
        let reasoningVariant: Int
        let topic: String
        let context: String
        let sourceSentence: String?
        let sourceText: String?
        let sourceContentTypeTags: [String]
        let sourceLanguage: String?
        let citationChunkIDs: [String]
        let a: Int
        let b: Int
        let wordCount: Int
        let numericValues: [Double]
    }

    private enum SourceKind: Int, CaseIterable {
        case executableCode
        case diagram
        case structuredCode
        case table
        case equation
        case prose
        case other
    }

    /// A conservative semantic router for the deterministic author. It only
    /// selects a topic-native template when the learner's topic or objective
    /// contains a strong domain signal; otherwise the existing field-level
    /// fallback remains authoritative. This keeps offline content useful
    /// without pretending that keyword matching is factual source grounding.
    private enum SemanticTopic: Equatable {
        case causalInference
        case fermiEstimation
        case logicalImplication
        case dataLiteracy
        case transferReasoning
        case sourceStudy
        case spatialModels
        case dijkstraShortestPaths
        case graphTraversal
        case binarySearch
        case dynamicProgramming
        case sorting
        case algorithmAnalysis
        case programBoundaries
        case concurrency
        case dataStructures
        case mathematicalInduction
        case calculus
        case linearAlgebra
        case probability
        case mathematicalModeling
        case classicalMechanics
        case electricityCircuits
        case wavesOscillations
        case thermodynamics
        case measurementUncertainty
        case engineeringStatics
        case controlSystems
        case signalsSampling
        case materialsFailure
        case unitsAndTolerances
        case stoichiometry
        case reactionKinetics
        case chemicalEquilibrium
        case thermochemistry
        case solutions
        case genetics
        case biologicalExperiments
        case cellRegulation
        case epidemiology
        case ecology
        case classifierEvaluation
        case statisticalInference
        case validationLeakage
        case regression
        case dataPipelines
        case generic
    }

    private static func semanticTopic(
        _ request: NFAuthoringRequest,
        basis: Basis
    ) -> SemanticTopic {
        let normalized = [basis.topic, request.learningObjective]
            .joined(separator: " ")
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: locale(for: request))
            .lowercased()

        func mentions(_ signals: [String]) -> Bool {
            signals.contains { normalized.contains($0) }
        }

        switch request.field {
        case .computing:
            if mentions([
                "dijkstra", "nonnegative shortest path", "non-negative shortest path",
                "priority queue shortest path", "ダイクストラ", "非負辺最短路"
            ]) { return .dijkstraShortestPaths }
            if mentions([
                "breadth-first", "breadth first", "depth-first", "depth first",
                "bfs", "dfs", "graph traversal", "グラフ探索", "幅優先", "深さ優先"
            ]) { return .graphTraversal }
            if mentions(["binary search", "二分探索"]) { return .binarySearch }
            if mentions([
                "dynamic programming", "memoization", "tabulation", "動的計画", "メモ化"
            ]) { return .dynamicProgramming }
            if mentions([
                "merge sort", "quicksort", "quick sort", "sorting algorithm",
                "ソート", "整列アルゴリズム"
            ]) { return .sorting }
            if mentions(["concurrency", "race condition", "distributed", "idempotency", "並行", "競合", "分散"]) {
                return .concurrency
            }
            if mentions(["tree", "heap", "hash table", "queue", "data structure", "データ構造", "ヒープ", "ハッシュ"]) {
                return .dataStructures
            }
            if mentions(["algorithm", "complexity", "big o", "asymptotic", "計算量", "アルゴリズム"]) {
                return .algorithmAnalysis
            }
            if mentions(["array", "loop", "boundary", "edge case", "program state", "配列", "ループ", "境界値"]) {
                return .programBoundaries
            }

        case .mathematics:
            if mentions([
                "mathematical induction", "induction proof", "proof by induction",
                "finite series", "inductive step", "数学的帰納", "帰納法"
            ]) { return .mathematicalInduction }
            if mentions([
                "derivative", "differentiation", "integral", "limit", "calculus",
                "微分", "積分", "極限", "解析学"
            ]) { return .calculus }
            if mentions([
                "matrix", "eigenvalue", "vector space", "linear algebra",
                "行列", "固有値", "ベクトル空間", "線形代数"
            ]) { return .linearAlgebra }
            if mentions(["probability", "bayes", "conditional", "base rate", "確率", "ベイズ", "条件付き"]) {
                return .probability
            }
            if mentions(["model", "optimization", "constraint", "sensitivity", "モデル", "最適化", "制約"]) {
                return .mathematicalModeling
            }

        case .physics:
            if mentions([
                "mechanics", "kinematics", "newton", "projectile", "momentum",
                "力学", "運動学", "ニュートン", "運動量"
            ]) { return .classicalMechanics }
            if mentions(["electric", "circuit", "current", "voltage", "potential", "電気", "回路", "電流", "電圧"]) {
                return .electricityCircuits
            }
            if mentions(["wave", "oscillation", "frequency", "phase", "波", "振動", "周波数", "位相"]) {
                return .wavesOscillations
            }
            if mentions(["thermodynamic", "heat", "entropy", "state function", "熱力学", "熱", "エントロピー"]) {
                return .thermodynamics
            }
            if mentions(["measurement", "uncertainty", "dimensional", "precision", "accuracy", "測定", "不確かさ", "次元"]) {
                return .measurementUncertainty
            }

        case .chemistry:
            if mentions(["stoich", "limiting reagent", "reaction yield", "mole ratio", "化学量論", "限界試薬", "収率"]) {
                return .stoichiometry
            }
            if mentions([
                "reaction rate", "rate law", "kinetics", "activation energy",
                "反応速度", "速度則", "活性化エネルギー"
            ]) { return .reactionKinetics }
            if mentions(["equilibrium", "acid", "base", "buffer", "ph", "平衡", "酸", "塩基", "緩衝"]) {
                return .chemicalEquilibrium
            }
            if mentions(["thermochem", "enthalpy", "gibbs", "spontane", "熱化学", "エンタルピー", "ギブズ", "自発"]) {
                return .thermochemistry
            }
            if mentions(["solution", "concentration", "dilution", "molarity", "溶液", "濃度", "希釈", "モル濃度"]) {
                return .solutions
            }

        case .lifeSciences:
            if mentions([
                "genetic", "inheritance", "allele", "genotype", "遺伝", "対立遺伝子"
            ]) { return .genetics }
            if mentions(["experimental design", "biological experiment", "control", "batch effect", "実験計画", "対照", "バッチ"]) {
                return .biologicalExperiments
            }
            if mentions(["cell signaling", "gene regulation", "pathway", "feedback", "細胞シグナル", "遺伝子調節", "経路"]) {
                return .cellRegulation
            }
            if mentions(["epidemiology", "diagnostic", "sensitivity", "specificity", "risk", "疫学", "診断", "感度", "特異度"]) {
                return .epidemiology
            }
            if mentions(["ecology", "population", "species interaction", "sampling", "生態", "個体群", "種間", "サンプリング"]) {
                return .ecology
            }

        case .dataScience:
            if mentions([
                "classifier", "classification", "precision", "recall", "confusion matrix",
                "分類器", "適合率", "再現率", "混同行列"
            ]) { return .classifierEvaluation }
            if mentions(["confidence interval", "hypothesis test", "statistical inference", "effect size", "信頼区間", "仮説検定", "統計的推論"]) {
                return .statisticalInference
            }
            if mentions(["validation", "leakage", "held-out", "test set", "generalization", "検証", "リーケージ", "テストセット", "汎化"]) {
                return .validationLeakage
            }
            if mentions(["regression", "residual", "coefficient", "confounding", "回帰", "残差", "係数", "交絡"]) {
                return .regression
            }
            if mentions(["pipeline", "reproducib", "row transformation", "feature transformation", "パイプライン", "再現性", "変換"]) {
                return .dataPipelines
            }

        case .engineering:
            if mentions(["statics", "load", "factor of safety", "free-body", "静力学", "荷重", "安全率"]) { return .engineeringStatics }
            if mentions(["control", "feedback", "stability", "steady-state", "制御", "フィードバック", "安定"]) { return .controlSystems }
            if mentions(["signal", "sampling", "filter", "aliasing", "信号", "サンプリング", "フィルタ", "エイリアシング"]) { return .signalsSampling }
            if mentions(["material", "stress", "strain", "fatigue", "failure", "材料", "応力", "ひずみ", "疲労"]) { return .materialsFailure }
            if mentions(["unit", "tolerance", "dimension", "plausibility", "単位", "公差", "次元"]) { return .unitsAndTolerances }

        case .general:
            if mentions(["causal", "association", "confound", "study design", "因果", "相関", "交絡"]) { return .causalInference }
            if mentions(["fermi", "estimat", "order of magnitude", "概算", "オーダー"]) { return .fermiEstimation }
            if mentions(["logical implication", "implication", "counterexample", "necessary", "sufficient", "論理", "対偶", "必要", "十分"]) { return .logicalImplication }
            if mentions(["table", "chart", "uncertainty", "data literacy", "表", "チャート", "不確かさ"]) { return .dataLiteracy }
            if mentions(["cross-domain", "transfer", "analogy", "invariant structure", "転移", "類推"]) { return .transferReasoning }
            if mentions(["selected material", "source", "chapter", "active recall", "資料", "出典", "想起"]) { return .sourceStudy }
            if mentions(["spatial", "rotation", "projection", "coordinate", "diagram", "空間", "回転", "座標", "図"]) { return .spatialModels }
        }
        return .generic
    }

    private static func question(_ request: NFAuthoringRequest, index: Int) -> NFAuthoredQuestion {
        let basis = makeBasis(request, index: index)
        if basis.sourceText == nil,
           let concrete = concreteTopicQuestion(request, basis: basis, index: index) {
            return concrete
        }
        switch request.style {
        case .multipleChoice:
            return multipleChoice(request, basis: basis, index: index)
        case .shortAnswer:
            return shortAnswer(request, basis: basis)
        case .numerical:
            return numerical(request, basis: basis, index: index)
        case .proofOrDerivation:
            return proof(request, basis: basis)
        case .debugging:
            return debugging(request, basis: basis)
        case .experimentalDesign:
            return experimentalDesign(request, basis: basis)
        case .dataInterpretation:
            return dataInterpretation(request, basis: basis)
        case .spatialTransformation:
            return spatialTransformation(request, basis: basis)
        }
    }

    /// Starter shelves must teach the learner's subject, not ask them to
    /// describe a generic reasoning role with the topic pasted into the
    /// sentence. These concrete routes are intentionally limited to reviewed
    /// semantic topics and the style used by that topic's starter set. Custom
    /// topics and source-grounded requests continue through the general and
    /// source-derived authoring paths below.
    private static func concreteTopicQuestion(
        _ request: NFAuthoringRequest,
        basis: Basis,
        index: Int
    ) -> NFAuthoredQuestion? {
        switch request.style {
        case .numerical:
            semanticNumerical(request, basis: basis)
        case .dataInterpretation:
            semanticDataProblem(request, basis: basis)
        case .proofOrDerivation:
            semanticStarterProof(request, basis: basis)
        case .debugging:
            semanticStarterDebugging(request, basis: basis)
        case .multipleChoice:
            semanticStarterMultipleChoice(request, basis: basis, index: index)
        case .shortAnswer:
            semanticStarterShortAnswer(request, basis: basis)
        case .experimentalDesign:
            semanticStarterExperiment(request, basis: basis)
        case .spatialTransformation:
            semanticTopic(request, basis: basis) == .spatialModels
                ? concreteSpatialTransformation(request, basis: basis)
                : nil
        }
    }

    private static func makeBasis(_ request: NFAuthoringRequest, index: Int) -> Basis {
        let seed = request.seed &+ UInt64(index &* 7_919)
        let difficultyOffset = Int((request.difficulty * 4).rounded(.down))
        let a = Int(seed % 8) + 3 + difficultyOffset * 2
        let b = Int((seed / 11) % 7) + 2 + difficultyOffset
        let locale = locale(for: request)
        let fieldTitle = request.field.localizedTitle(locale: locale)
        let topic = request.customTopic.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? fieldTitle
            : request.customTopic.trimmingCharacters(in: .whitespacesAndNewlines)
        let requestedObjective = request.learningObjective.trimmingCharacters(in: .whitespacesAndNewlines)
        var contextParts = [fieldTitle]
        if topic.localizedCaseInsensitiveCompare(fieldTitle) != .orderedSame {
            contextParts.append(topic)
        }
        if !requestedObjective.isEmpty {
            contextParts.append(requestedObjective)
        }
        let requestContext = contextParts.joined(separator: " · ")
        if !request.sourceChunks.isEmpty {
            let rankedChunks = diversifiedSourceChunks(request.sourceChunks, for: request.style)
            let propositionCandidates: [(chunk: NFSourceChunk, proposition: String)] =
                request.style == .shortAnswer ? sourcePropositionCandidates(request) : []
            let selectedProposition = propositionCandidates.isEmpty
                ? nil
                : propositionCandidates[index % propositionCandidates.count]
            let chunk = selectedProposition?.chunk ?? rankedChunks[index % rankedChunks.count]
            let kind = sourceKind(of: chunk)
            let sentence = selectedProposition?.proposition
                ?? ((kind == .prose || kind == .other)
                    ? firstCompleteProposition(in: chunk.text)
                    : nil)
            return Basis(
                id: "fallback.source.\(request.style.rawValue).\(request.seed).\(index)",
                semanticVariant: (Int(request.seed % 5) + index) % 5,
                reasoningVariant: (Int(request.seed % 6) + index) % 6,
                topic: topic,
                context: "\(requestContext) · \(chunk.citationLabel)",
                sourceSentence: sentence,
                sourceText: chunk.text,
                sourceContentTypeTags: chunk.contentTypeTags,
                sourceLanguage: chunk.language,
                citationChunkIDs: [chunk.id],
                a: a,
                b: b,
                wordCount: max(1, sentence.map { words(in: $0).count } ?? words(in: chunk.text).count),
                numericValues: numericValues(in: chunk.text)
            )
        }
        return Basis(
            id: "fallback.\(request.lab.rawValue).\(request.style.rawValue).\(request.seed).\(index)",
            semanticVariant: (Int(request.seed % 5) + index) % 5,
            reasoningVariant: (Int(request.seed % 6) + index) % 6,
            topic: topic,
            context: requestContext,
            sourceSentence: nil,
            sourceText: nil,
            sourceContentTypeTags: [],
            sourceLanguage: nil,
            citationChunkIDs: [],
            a: a,
            b: b,
            wordCount: a + b,
            numericValues: []
        )
    }

    private static func sourceCompatibilityScore(
        _ chunk: NFSourceChunk,
        for style: NFQuestionStyle
    ) -> Int {
        let tags = Set(chunk.contentTypeTags.map { $0.lowercased() })
        let kind = sourceKind(of: chunk)

        return switch style {
        case .debugging:
            switch kind {
            case .executableCode: 6
            case .diagram: 5
            case .structuredCode: 4
            case .equation, .table: 3
            case .prose: 2
            case .other: 1
            }
        case .numerical: kind == .table ? 4 : (kind == .equation ? 3 : 1)
        case .dataInterpretation: kind == .table ? 4 : 1
        case .proofOrDerivation: kind == .equation ? 4 : 2
        case .experimentalDesign: tags.contains("prose") ? 3 : 1
        case .multipleChoice, .shortAnswer, .spatialTransformation: 1
        }
    }

    /// Ranks for task compatibility but then interleaves representation kinds.
    /// A mixed document should not yield five near-identical code-token items
    /// merely because fenced blocks all receive a slightly higher raw score.
    private static func diversifiedSourceChunks(
        _ chunks: [NFSourceChunk],
        for style: NFQuestionStyle
    ) -> [NFSourceChunk] {
        let grouped = Dictionary(grouping: chunks, by: sourceKind)
        let kinds = grouped.keys.sorted { lhs, rhs in
            let left = grouped[lhs]?.map { sourceCompatibilityScore($0, for: style) }.max() ?? 0
            let right = grouped[rhs]?.map { sourceCompatibilityScore($0, for: style) }.max() ?? 0
            if left != right { return left > right }
            return lhs.rawValue < rhs.rawValue
        }
        let sortedGroups = Dictionary(uniqueKeysWithValues: kinds.map { kind in
            (kind, (grouped[kind] ?? []).sorted {
                if $0.ordinal != $1.ordinal { return $0.ordinal < $1.ordinal }
                return $0.id < $1.id
            })
        })
        let maximumDepth = sortedGroups.values.map(\.count).max() ?? 0
        var result: [NFSourceChunk] = []
        for depth in 0..<maximumDepth {
            for kind in kinds {
                guard let group = sortedGroups[kind], depth < group.count else { continue }
                result.append(group[depth])
            }
        }
        return result
    }

    private static func sourceKind(of chunk: NFSourceChunk) -> SourceKind {
        let tags = Set(chunk.contentTypeTags.map { $0.lowercased() })
        let language = chunk.language?.lowercased()
        let diagramLanguages: Set<String> = ["mermaid", "dot", "graphviz", "plantuml"]
        if language.map(diagramLanguages.contains) == true
            || !tags.isDisjoint(with: ["mermaid", "diagram", "flowchart", "graphviz"]) {
            return .diagram
        }
        if (tags.contains("table") || tags.contains("csv")) && !tags.contains("schema-summary") {
            return .table
        }
        if tags.contains("equation") || tags.contains("math") || language == "latex" {
            return .equation
        }
        let executableLanguages: Set<String> = [
            "swift", "python", "py", "javascript", "js", "typescript", "ts",
            "java", "kotlin", "c", "cpp", "c++", "csharp", "cs", "go",
            "rust", "ruby", "php", "scala", "sql", "r", "shell", "bash"
        ]
        if language.map(executableLanguages.contains) == true { return .executableCode }
        if tags.contains("code") || tags.contains("source-code") { return .structuredCode }
        if tags.contains("prose") { return .prose }
        return .other
    }

    private struct TopicConceptProfile {
        /// Ordered as invariant, prerequisite, boundary test, diagnostic,
        /// interpretation, and transfer check. Keeping those roles explicit
        /// lets one starter set exercise six different reasoning operations
        /// without pretending that a changed number is a new question.
        let facets: [String]
    }

    private static func topicConceptProfile(
        _ request: NFAuthoringRequest,
        basis: Basis
    ) -> TopicConceptProfile {
        func profile(_ values: String.LocalizationValue...) -> TopicConceptProfile {
            TopicConceptProfile(facets: values.map { localized($0, request: request) })
        }

        switch semanticTopic(request, basis: basis) {
        case .causalInference:
            return profile(
                "A causal contrast must compare outcomes under alternative exposures for otherwise comparable units.",
                "Treatment assignment or a defensible adjustment strategy must block common causes of exposure and outcome.",
                "Check whether the claimed effect survives when the groups are compared at the same baseline risk.",
                "A large pre-treatment group difference is evidence that selection, not only treatment, can explain the outcome gap.",
                "An observational association can support prediction without, by itself, identifying an intervention effect.",
                "Transfer the design by naming the exposure, outcome, assignment mechanism, and main confounder in the new setting."
            )
        case .logicalImplication:
            return profile(
                "From P and P → Q, Q follows; Q alone does not establish P.",
                "The direction and quantifiers of the stated implication must be preserved.",
                "Try a case where Q is true for a reason other than P to test the converse.",
                "Concluding P from Q is affirming the consequent unless Q → P is also given.",
                "One counterexample is enough to refute a universal implication, but examples cannot prove it universally.",
                "Map the original premise and conclusion separately before reusing the inference in a new domain."
            )
        case .transferReasoning, .sourceStudy:
            return profile(
                "A valid transfer preserves the underlying relation or constraint while the surface objects may change.",
                "The assumptions that made the original solution valid must also hold in the target problem.",
                "Test the mapping on an edge case where one original constraint becomes active.",
                "A copied formula with unmatched variables or units signals a surface analogy rather than structural transfer.",
                "Successful transfer is shown by solving a novel case and checking the result against the target constraints.",
                "State an explicit correspondence between each source quantity, operation, and target quantity."
            )
        case .calculus:
            return profile(
                "A derivative is the limit of a difference quotient, not the quotient obtained by setting the increment to zero.",
                "The relevant limit must exist at the point before a two-sided derivative can be asserted.",
                "Compare left- and right-hand difference quotients at a corner or cusp.",
                "Substituting h = 0 before simplifying creates the indeterminate form 0/0 and skips the limiting argument.",
                "The sign of f′ describes local change; it does not by itself determine the function’s absolute value.",
                "Translate a symbolic derivative into units of output change per unit input in the new context."
            )
        case .mathematicalModeling:
            return profile(
                "A model is defined by its variables, objective or outcome relation, constraints, and declared assumptions.",
                "Every model quantity needs a consistent meaning, domain, and unit before algebraic optimization begins.",
                "Evaluate the model at zero, at a binding constraint, and just outside the feasible region.",
                "A dimensionally inconsistent term or violated constraint invalidates a numerically plausible optimum.",
                "Sensitivity to one assumption describes model dependence, not measurement uncertainty from every source.",
                "Reuse the model only after remapping variables and verifying that the target constraints have the same structure."
            )
        case .thermodynamics:
            return profile(
                "With work defined as done by the system, the first law is ΔU = Q − W.",
                "A heat or work calculation requires a declared system boundary and sign convention.",
                "Check an adiabatic or cyclic limit: Q = 0 for the former and ΔU = 0 for the latter.",
                "Treating heat as a state function makes path-dependent energy transfer look like stored energy.",
                "A negative ΔG under stated temperature and pressure conditions indicates thermodynamic favorability, not reaction speed.",
                "Transfer an energy balance by preserving the same system boundary and the direction of every transfer."
            )
        case .electricityCircuits:
            return profile(
                "Kirchhoff’s current law conserves charge at a node, while the loop law conserves energy around a closed path.",
                "Current directions and voltage polarities must be declared consistently before writing circuit equations.",
                "Check open-circuit and short-circuit limits to expose impossible current or voltage predictions.",
                "A failed unit check distinguishes resistance V/A from conductance A/V and catches an inverted Ohm’s-law ratio.",
                "Equal voltage across parallel branches does not imply equal current unless their resistances are equal.",
                "When redrawing a circuit, preserve node connectivity rather than the picture’s geometric layout."
            )
        case .algorithmAnalysis:
            return profile(
                "A correctness argument needs an invariant that is true initially, preserved by each step, and sufficient at termination.",
                "Complexity must name the input-size measure and count the operation that dominates growth.",
                "Empty, one-element, and maximum-size inputs expose different boundary and resource failures.",
                "A loop whose state does not progress toward its termination condition can be locally correct yet never finish.",
                "Big-O is an asymptotic upper bound; it does not say two implementations have equal running time for a given input.",
                "Transfer an algorithm only after checking that the new data obey its ordering and representation preconditions."
            )
        case .programBoundaries:
            return profile(
                "For an array of count elements indexed from zero, valid indices are 0 through count − 1.",
                "Choose either a closed interval with high = count − 1 or a half-open interval ending at count, then keep it consistent.",
                "Trace empty and one-element inputs before relying on a typical multi-element example.",
                "An inclusive comparison against count causes a one-past-the-end access in a zero-based array.",
                "A passing interior case does not validate initialization, termination, or the final state transition.",
                "When porting the loop, remap both the collection’s index convention and the interval convention."
            )
        case .dataStructures:
            return profile(
                "Choose a data structure from the operations and invariants the workload requires, not from its name alone.",
                "A claimed operation cost must state assumptions such as balanced height, hash quality, or amortization.",
                "Test an empty structure, a duplicate key, and a structural update at the root or capacity boundary.",
                "A heap-order check cannot establish binary-search-tree order, because the two structures preserve different relations.",
                "Expected constant-time hash lookup is not a worst-case guarantee under unrestricted collisions.",
                "Transfer the representation by matching required insert, remove, lookup, ordering, and memory costs."
            )
        case .unitsAndTolerances:
            return profile(
                "Every additive term must have the same physical dimension, and every conversion factor must equal one.",
                "Tolerance combination must state whether the task requires a worst-case bound or a statistical estimate.",
                "Check zero offset, maximum tolerance, and a unit change such as millimetres to metres.",
                "A plausible magnitude with leftover or cancelled-away units reveals a dimensionally invalid calculation.",
                "Precision records repeatability; it does not guarantee accuracy relative to the true value.",
                "Transfer a design check by carrying units and tolerance assumptions with every mapped quantity."
            )
        case .controlSystems:
            return profile(
                "Negative feedback subtracts the measured output from the reference and acts on the resulting error.",
                "A stability claim needs a stated model and operating point; a bounded-looking trace alone is not a proof.",
                "Check the zero-gain, high-gain, step-input, and disturbance limits.",
                "Reversing the summing-junction sign turns corrective negative feedback into reinforcing positive feedback.",
                "Small steady-state error does not imply a fast transient or adequate stability margin.",
                "When moving between a block diagram and equations, preserve signal direction, summing signs, and loop closure."
            )
        case .genetics:
            return profile(
                "Inheritance probabilities follow from the stated parental genotypes, segregation model, and linkage assumptions.",
                "Independent assortment cannot be assumed for loci whose linkage is under investigation.",
                "Test reciprocal crosses or informative recombinants to separate linkage from a simple independent model.",
                "Using phenotype counts as genotype counts without accounting for dominance creates a hidden-state error.",
                "A Mendelian ratio describes a probability model; finite offspring counts need not equal it exactly.",
                "Transfer the calculation by rebuilding the gamete probabilities for the new cross rather than copying the old ratio."
            )
        case .biologicalExperiments:
            return profile(
                "A valid biological comparison isolates the treatment while holding handling and measurement procedures comparable.",
                "Positive, negative, and procedural controls answer different failure questions and should be chosen explicitly.",
                "Repeat the comparison across batches or blocks to reveal a treatment-by-batch dependence.",
                "Assigning every treatment sample to one batch and every control to another confounds treatment with batch.",
                "A treatment-control difference supports the treatment contrast only within the populations and procedures actually sampled.",
                "Transfer the experiment by remapping treatment, outcome, nuisance variables, controls, and replication unit."
            )
        case .stoichiometry:
            return profile(
                "Reaction extent is limited by the smallest coefficient-adjusted reactant amount.",
                "The chemical equation must be balanced before mole ratios can be used.",
                "Check cases where each reactant in turn is limiting and where the ratio is exactly stoichiometric.",
                "Choosing the largest available mole amount without dividing by its coefficient overstates feasible yield.",
                "Percent yield compares actual with theoretical product; it does not change the limiting reagent calculation.",
                "For a new reaction, rebuild every mole ratio from its balanced coefficients."
            )
        case .chemicalEquilibrium:
            return profile(
                "The reaction quotient Q has the same form as K and predicts direction by comparison with K.",
                "Only species included by the equilibrium expression and the stated standard-state assumptions belong in Q.",
                "Check Q < K, Q = K, and Q > K rather than memorizing one perturbation story.",
                "Reversing Q/K or including pure solids can predict the wrong shift.",
                "A system at equilibrium has equal forward and reverse rates, not zero molecular activity.",
                "Transfer the method by first writing the balanced reaction and its new equilibrium expression."
            )
        case .reactionKinetics:
            return profile(
                "Reaction order is inferred from how rate changes when one concentration changes while others are controlled.",
                "An initial-rate comparison must hold the other reactant concentrations and relevant conditions fixed.",
                "Check a concentration ratio of one and an order of zero to expose an invalid log-ratio step.",
                "Attributing a rate change to one reactant when temperature also changed confounds the order estimate.",
                "A fitted rate law summarizes observed dependence; it does not by itself prove an elementary mechanism.",
                "Transfer the inference by matching controlled row pairs before calculating any exponent."
            )
        case .classifierEvaluation:
            return profile(
                "Precision uses predicted positives in its denominator, whereas recall uses actual positives.",
                "A threshold comparison must declare which class is positive and which error is more costly.",
                "Check an all-negative predictor and a rare-positive population before trusting accuracy.",
                "Computing precision with TP + FN in the denominator silently turns it into recall.",
                "Changing a threshold trades false positives against false negatives; it does not improve every metric simultaneously.",
                "Transfer a threshold by rechecking prevalence, costs, and calibration in the target population."
            )
        case .validationLeakage:
            return profile(
                "Every learned preprocessing or feature-construction step must be fit without information from the held-out evaluation rows.",
                "The split unit must match the intended generalization unit, such as person, site, or future time.",
                "Test duplicate entities and future-derived features to reveal leakage that a random row split can hide.",
                "Scaling all rows before the split leaks test-distribution information into training.",
                "A held-out score estimates performance only for data generated like the held-out sample and pipeline.",
                "Transfer the pipeline by reproducing split, fit, transform, and evaluation order without refitting on test data."
            )
        default:
            switch request.field {
            case .general:
                return profile(
                    "A sound STEM solution states the relation that connects the requested quantity to the given evidence.",
                    "Units, scope, and assumptions must be explicit before the relation is applied.",
                    "Check a zero case, a limiting case, and an independent estimate of scale.",
                    "A correct-looking number with incompatible units reveals a broken representation.",
                    "The evidence supports only the claim actually measured, not a broader causal or universal conclusion.",
                    "Transfer the method by mapping quantities, constraints, and checks into the new problem."
                )
            case .mathematics:
                return profile(
                    "A mathematical conclusion must follow from definitions, stated assumptions, and valid transformations.",
                    "The domain and quantifiers must be fixed before manipulating a formula or theorem.",
                    "Test endpoints, zero, and the smallest admissible instance.",
                    "A single confirming example cannot prove a universally quantified statement.",
                    "Equivalent algebraic forms preserve the solution set only when each transformation is reversible or justified.",
                    "Transfer the result by checking that the new objects satisfy the same hypotheses."
                )
            case .physics:
                return profile(
                    "A physical model must conserve the relevant quantity and remain dimensionally consistent.",
                    "Choose the system boundary, coordinate direction, and sign convention before writing equations.",
                    "Check zero-input, equilibrium, and large- or small-parameter limits.",
                    "A sign or unit mismatch usually identifies the first invalid physical step.",
                    "A model prediction is conditional on its idealizations and does not automatically establish a cause.",
                    "Transfer the calculation by preserving the system boundary and meaning of each term."
                )
            case .computing:
                return profile(
                    "Correct software preserves its state invariant from initialization through termination.",
                    "Input representation, ordering, and boundary conventions are algorithm preconditions.",
                    "Test empty, singleton, duplicate, and maximum-size inputs.",
                    "The first state that violates the invariant locates the bug more precisely than the final symptom.",
                    "A passing sample demonstrates one execution, not correctness for every allowed input.",
                    "Transfer the implementation only after remapping its data and complexity assumptions."
                )
            case .engineering:
                return profile(
                    "An engineering result must satisfy equilibrium or conservation, units, constraints, and a declared design margin.",
                    "Loads, boundary conditions, material assumptions, and failure criterion must be stated.",
                    "Check zero load, rated load, and the governing worst-case tolerance.",
                    "An inverted safety or gain ratio can look smooth while reversing the design meaning.",
                    "A calculated margin is conditional on the chosen failure model and load case.",
                    "Transfer the design by rebuilding its load path, constraints, and verification checks."
                )
            case .lifeSciences:
                return profile(
                    "A biological claim must connect a defined intervention or state to a measured outcome through an explicit comparison.",
                    "Controls, replication unit, sampling frame, and nuisance variables must be declared.",
                    "Check negative, positive, and procedural controls across independent batches.",
                    "Confounding a treatment with batch or handling prevents the outcome difference from isolating treatment.",
                    "The conclusion is limited to the organisms, conditions, and measurement procedure studied.",
                    "Transfer the design by remapping treatment, mechanism, outcome, controls, and replication."
                )
            case .chemistry:
                return profile(
                    "A chemical calculation must preserve atoms, charge, amount, and the stated thermodynamic or kinetic relation.",
                    "Balance the equation and declare phases, units, and applicable approximations before substituting values.",
                    "Check zero concentration, stoichiometric balance, and a limiting-reagent or equilibrium boundary.",
                    "An inverted ratio or inconsistent mole coefficient is a common first failing step.",
                    "A calculated state or rate follows from the model conditions and does not alone establish a mechanism.",
                    "Transfer the method by rebuilding relations from the new balanced equation and conditions."
                )
            case .dataScience:
                return profile(
                    "A valid model claim keeps training, tuning, and final evaluation evidence separated.",
                    "The target, prediction unit, data-generating population, and metric must be declared.",
                    "Check a naive baseline, rare class, duplicated entity, and future-time split.",
                    "Leakage or a denominator error can inflate a plausible-looking metric.",
                    "Predictive performance does not by itself identify a causal effect or guarantee transport to a new population.",
                    "Transfer the pipeline by reproducing split and transformation order and then revalidating calibration."
                )
            }
        }
    }

    private static func conceptMultipleChoice(
        _ request: NFAuthoringRequest,
        basis: Basis,
        index: Int
    ) -> NFAuthoredQuestion {
        let profile = topicConceptProfile(request, basis: basis)
        let variant = basis.reasoningVariant
        let prompts: [String.LocalizationValue] = [
            "Which option states the governing relation or invariant for \(basis.topic.lowercased())?",
            "Before applying the main method in \(basis.topic.lowercased()), which prerequisite must be checked?",
            "Which option is the most informative boundary or falsification test for \(basis.topic.lowercased())?",
            "A result in \(basis.topic.lowercased()) looks plausible but is wrong. Which option identifies the characteristic diagnostic?",
            "Which interpretation of \(basis.topic.lowercased()) is warranted without overclaiming?",
            "Which option best demonstrates transfer of \(basis.topic.lowercased()) reasoning to a new case?"
        ]
        let roleNames: [String.LocalizationValue] = [
            "governing invariant", "required precondition", "boundary test",
            "diagnostic", "bounded interpretation", "transfer check"
        ]
        let correct = profile.facets[variant]
        let roleName = localized(roleNames[variant], request: request)
        let decisiveStep = localized("Select the \(roleName) that is native to this topic.", request: request)
        let distractors = (1...3).map { profile.facets[(variant + $0) % profile.facets.count] }
        return makeQuestion(
            request: request,
            basis: basis,
            prompt: localized(prompts[variant], request: request),
            choices: sourceChoices(
                correct: correct,
                distractors: distractors,
                rotation: index,
                request: request
            ),
            correctAnswer: correct,
            explanation: localized("The question asks for the \(roleName); the selected statement answers that role directly while the other statements address different checks in the same topic.", request: request),
            hint: localized("Name the requested reasoning role before comparing the options.", request: request),
            decisiveStep: decisiveStep
        )
    }

    private struct ConcreteChoiceProblem {
        let prompt: String.LocalizationValue
        let correct: String.LocalizationValue
        let distractors: [String.LocalizationValue]
        let explanation: String.LocalizationValue
        let hint: String.LocalizationValue
        let decisiveStep: String.LocalizationValue
    }

    private static func semanticStarterMultipleChoice(
        _ request: NFAuthoringRequest,
        basis: Basis,
        index: Int
    ) -> NFAuthoredQuestion? {
        let problems: [ConcreteChoiceProblem]
        switch semanticTopic(request, basis: basis) {
        case .logicalImplication:
            problems = [
                ConcreteChoiceProblem(
                    prompt: "Premises: ‘If a sample is sterile, then its culture shows no growth’ and ‘this sample is sterile.’ Which conclusion follows deductively?",
                    correct: "This sample’s culture shows no growth.",
                    distractors: [
                        "Every culture with no growth came from a sterile sample.",
                        "This sample’s culture must show growth.",
                        "Nothing follows unless every sample is sterile."
                    ],
                    explanation: "Modus ponens applies to sterile → no growth and sterile. The nearest distractor reverses the implication; no-growth → sterile was never given.",
                    hint: "Match the affirmed premise to the left side of the implication.",
                    decisiveStep: "Apply modus ponens without reversing the arrow."
                ),
                ConcreteChoiceProblem(
                    prompt: "Premise: ‘If an integer is divisible by 4, then it is even.’ You learn that n is not even. What follows?",
                    correct: "n is not divisible by 4.",
                    distractors: [
                        "n is divisible by 4.",
                        "n must be odd and prime.",
                        "No conclusion follows because contraposition is invalid."
                    ],
                    explanation: "The valid contrapositive is not-even → not-divisible-by-4. Being odd and prime adds an unsupported property: odd composite values also satisfy the premise.",
                    hint: "Form the contrapositive by negating and reversing both parts.",
                    decisiveStep: "Use the contrapositive of divisible-by-4 → even."
                ),
                ConcreteChoiceProblem(
                    prompt: "Claim: ‘For every real x, if x² = 4 then x = 2.’ Which value is a decisive counterexample?",
                    correct: "x = −2",
                    distractors: ["x = 0", "x = 2", "x = 4"],
                    explanation: "At x=−2 the premise x²=4 is true while the conclusion x=2 is false. The tempting x=2 confirms the claim instead of refuting it.",
                    hint: "A counterexample must make the premise true and conclusion false.",
                    decisiveStep: "Test x=−2 against both sides of the implication."
                ),
                ConcreteChoiceProblem(
                    prompt: "Premise: ‘If the alarm is armed and a door opens, then the siren sounds.’ The siren sounds. Which inference is valid?",
                    correct: "The premises do not identify why the siren sounded.",
                    distractors: [
                        "The alarm was armed and a door definitely opened.",
                        "No door opened.",
                        "The siren cannot sound for any other reason."
                    ],
                    explanation: "Affirming the consequent is invalid because smoke, a test button, or another rule could cause the siren. The nearest distractor assumes the converse without evidence.",
                    hint: "Ask whether the conclusion could be true through another cause.",
                    decisiveStep: "Reject affirmation of the consequent."
                ),
                ConcreteChoiceProblem(
                    prompt: "Premises: ‘Some measured alloys are brittle’ and ‘Every brittle alloy failed test T.’ Which conclusion is guaranteed?",
                    correct: "Some measured alloy failed test T.",
                    distractors: [
                        "Every measured alloy failed test T.",
                        "No measured alloy passed test T.",
                        "Every alloy is brittle."
                    ],
                    explanation: "The existential witness that is brittle must also fail T. The nearest distractor changes ‘some’ to ‘every,’ which the quantifiers do not permit.",
                    hint: "Carry the same existential witness through the universal rule.",
                    decisiveStep: "Preserve ‘some’ rather than upgrading it to ‘all.’"
                ),
                ConcreteChoiceProblem(
                    prompt: "A policy’s complete grant rule says access is granted if and only if both identity I and authorization A are verified. Which Boolean expression computes the grant decision?",
                    correct: "I ∧ A",
                    distractors: ["I ∨ A", "¬I ∧ A", "I → A"],
                    explanation: "‘Both’ requires conjunction, so each verification must be true. The nearest distractor I∨A would grant access after only one check.",
                    hint: "Translate the word ‘both’ before evaluating cases.",
                    decisiveStep: "Map both required conditions to conjunction."
                )
            ]

        case .dataStructures:
            problems = [
                ConcreteChoiceProblem(
                    prompt: "A scheduler must always remove the job with the smallest numeric priority while supporting new insertions. Which data structure best matches those operations?",
                    correct: "A min-heap priority queue",
                    distractors: ["A FIFO queue", "An unsorted linked list with removal from the front", "A stack"],
                    explanation: "A min-heap exposes the smallest key and supports logarithmic insertion. A FIFO queue is the nearest distractor but orders by arrival, not numeric priority.",
                    hint: "Identify which value must be available at every removal.",
                    decisiveStep: "Match repeated extract-min to a min-heap."
                ),
                ConcreteChoiceProblem(
                    prompt: "Keys 8, 3, and 10 are inserted into an empty binary search tree in that order. Where is key 3 stored?",
                    correct: "As the left child of 8",
                    distractors: ["As the right child of 8", "As the left child of 10", "At the root in place of 8"],
                    explanation: "BST order sends values smaller than 8 left, so 3 becomes 8’s left child. The nearest distractor reverses the ordering invariant.",
                    hint: "Compare 3 with the root key 8.",
                    decisiveStep: "Follow the BST less-than branch."
                ),
                ConcreteChoiceProblem(
                    prompt: "A breadth-first search needs to process vertices in the same order they are discovered. Which structure should hold the frontier?",
                    correct: "A FIFO queue",
                    distractors: ["A LIFO stack", "A max-heap keyed by vertex label", "An unordered set with arbitrary removal"],
                    explanation: "FIFO preserves discovery order and therefore explores one distance layer at a time. A stack instead produces depth-first behavior.",
                    hint: "Breadth-first traversal finishes the current layer before the next.",
                    decisiveStep: "Use FIFO order for the discovered frontier."
                ),
                ConcreteChoiceProblem(
                    prompt: "A hash table has 100 buckets and stores 75 keys. What quantity is 0.75?",
                    correct: "The load factor",
                    distractors: ["The worst-case lookup time", "The hash value of every key", "The number of collisions"],
                    explanation: "Load factor is entries divided by buckets: 75/100=0.75. It does not determine an exact collision count or worst-case time.",
                    hint: "Divide stored entries by bucket count.",
                    decisiveStep: "Identify 75/100 as the load factor."
                ),
                ConcreteChoiceProblem(
                    prompt: "In a max-heap with root 20 and children 15 and 18, which replacement preserves heap order after removing 20 if the remaining candidates are 15 and 18?",
                    correct: "Promote 18 above 15",
                    distractors: ["Promote 15 above 18", "Keep an empty root", "Sort both values in ascending order from the root"],
                    explanation: "A max-heap requires every parent to be at least its children, so the larger remaining key 18 belongs above 15. Promoting 15 violates that invariant.",
                    hint: "The root of a max-heap must be the largest remaining key.",
                    decisiveStep: "Restore parent ≥ child after removal."
                ),
                ConcreteChoiceProblem(
                    prompt: "An undo feature must remove the most recently recorded action first. Which data structure directly implements this policy?",
                    correct: "A stack",
                    distractors: ["A FIFO queue", "A min-heap", "A binary search tree ordered by action text"],
                    explanation: "Undo is last-in, first-out, exactly the stack discipline. A queue is tempting for ordered records but removes the oldest action first.",
                    hint: "Compare the order actions arrive with the order they must be undone.",
                    decisiveStep: "Map last-in, first-out behavior to a stack."
                )
            ]

        case .chemicalEquilibrium:
            problems = [
                ConcreteChoiceProblem(
                    prompt: "For N₂O₄(g) ⇌ 2NO₂(g), a mixture has Qc = 0.20 while Kc = 0.80. Which direction is favored as equilibrium is approached?",
                    correct: "Toward NO₂ products",
                    distractors: ["Toward N₂O₄ reactant", "No net change because Q and K are both positive", "The direction cannot be inferred from Q and K"],
                    explanation: "Because Q<K, the reaction must increase the product-to-reactant ratio, so it proceeds right. The nearest distractor uses the Q>K direction backward.",
                    hint: "Ask how Q must change to reach K.",
                    decisiveStep: "Compare Qc with Kc before choosing direction."
                ),
                ConcreteChoiceProblem(
                    prompt: "For CaCO₃(s) ⇌ CaO(s) + CO₂(g), which equilibrium expression is correct?",
                    correct: "Kp = P_CO₂",
                    distractors: ["Kp = P_CO₂·[CaO]/[CaCO₃]", "Kp = 1/P_CO₂", "Kp = [CaCO₃]/[CaO]"],
                    explanation: "Pure solids have unit activity and are omitted, leaving only CO₂ pressure. The nearest distractor incorrectly includes solid amounts.",
                    hint: "Identify which species has variable activity in this heterogeneous equilibrium.",
                    decisiveStep: "Omit pure solids from the equilibrium expression."
                ),
                ConcreteChoiceProblem(
                    prompt: "In a dilute aqueous classroom model at 25 °C, a buffer has pKa=4.76 and [A⁻]/[HA]=10. Using pH=pKa+log₁₀([A⁻]/[HA]), which pH is calculated correctly and lies inside the model’s conventional 0–14 check range?",
                    correct: "pH = 5.76",
                    distractors: ["pH = 3.76", "pH = 47.6", "pH = 14.76"],
                    explanation: "log₁₀(10)=1, so pH=4.76+1=5.76. It lies in the prompt’s conventional dilute-solution check range; that classroom range is not a universal physical bound for every concentrated aqueous solution.",
                    hint: "Evaluate log₁₀(10), then check the stated aqueous range.",
                    decisiveStep: "Add one pH unit to pKa and apply the 0–14 boundary check."
                ),
                ConcreteChoiceProblem(
                    prompt: "At equilibrium for a reversible reaction, which statement is correct?",
                    correct: "Forward and reverse reaction rates are equal.",
                    distractors: ["Both reaction rates are zero.", "Reactant and product concentrations must be equal.", "The equilibrium constant becomes zero."],
                    explanation: "Equilibrium is dynamic: molecular events continue at equal opposing rates. The nearest distractor confuses no net change with no reaction.",
                    hint: "Distinguish microscopic reaction from macroscopic concentration change.",
                    decisiveStep: "Identify equality of rates, not absence of reaction."
                ),
                ConcreteChoiceProblem(
                    prompt: "For a reaction whose forward direction is exothermic, what happens to the equilibrium composition when temperature is increased?",
                    correct: "Equilibrium shifts toward reactants.",
                    distractors: ["Equilibrium shifts toward products.", "K is unchanged and no shift occurs.", "All reactant is consumed."],
                    explanation: "Raising temperature changes K and favors the endothermic reverse direction, so the equilibrium composition shifts toward reactants. The nearest distractor reverses this temperature response.",
                    hint: "Identify which reaction direction absorbs thermal energy.",
                    decisiveStep: "Relate a temperature increase to the endothermic reaction direction."
                ),
                ConcreteChoiceProblem(
                    prompt: "For two acids measured in water at the same temperature, acid A has Ka=1.0×10⁻⁵ and acid B has Ka=1.0×10⁻². Which statement correctly compares their conjugate bases?",
                    correct: "The conjugate base of acid A is stronger than the conjugate base of acid B.",
                    distractors: ["The conjugate base of acid A is weaker than the conjugate base of acid B.", "The two conjugate bases have identical strength.", "The Ka values give no information about conjugate-base strength under these common conditions."],
                    explanation: "Under the stated common solvent and temperature, the weaker acid has smaller Ka and therefore the stronger conjugate base through KaKb=Kw. The nearest distractor incorrectly makes acid and conjugate-base strengths vary together.",
                    hint: "Acid strength and conjugate-base strength vary inversely.",
                    decisiveStep: "Compare Ka values, then invert the strength ordering for conjugate bases."
                )
            ]

        case .genetics:
            problems = [
                ConcreteChoiceProblem(
                    prompt: "In a monohybrid cross Aa × Aa with complete dominance, what is the probability of offspring genotype aa?",
                    correct: "1/4",
                    distractors: ["1/2", "3/4", "1"],
                    explanation: "Each parent contributes a with probability 1/2, so P(aa)=1/2×1/2=1/4. The 3/4 distractor is the dominant-phenotype probability, not genotype aa.",
                    hint: "List the four equally likely gamete combinations.",
                    decisiveStep: "Multiply the two independent a-gamete probabilities."
                ),
                ConcreteChoiceProblem(
                    prompt: "A testcross Aa × aa produces 52 dominant-phenotype and 48 recessive-phenotype offspring. Which model best fits these counts?",
                    correct: "A 1:1 segregation ratio",
                    distractors: ["A 3:1 segregation ratio", "All offspring are Aa", "The recessive allele is lethal"],
                    explanation: "The observed counts are close to equal, as Aa×aa predicts. A 3:1 ratio is expected from Aa×Aa, the nearest common cross confusion.",
                    hint: "Write the gametes produced by each parent.",
                    decisiveStep: "Match the observed near-equal counts to Aa×aa."
                ),
                ConcreteChoiceProblem(
                    prompt: "Two genes show 12 recombinant offspring among 100 total offspring. What estimated map distance and linkage interpretation best fit this result?",
                    correct: "About 12 centimorgans; the frequency below 50% supports linkage",
                    distractors: ["About 6 centimorgans; each crossover contributes two recombinant chromatids", "About 12 centimorgans; this provides no evidence against independent assortment", "About 50 centimorgans; the loci assort independently"],
                    explanation: "Recombination frequency is 12/100=12%, approximating 12 cM at this low frequency. A value well below the 50% independent-assortment limit is evidence that the loci are linked; the 6 cM distractor incorrectly halves the rate.",
                    hint: "Use recombinant count divided by total count.",
                    decisiveStep: "Convert 12% to about 12 cM and compare it with the 50% independence benchmark."
                ),
                ConcreteChoiceProblem(
                    prompt: "An X-linked recessive trait is carried by a heterozygous mother and the father is unaffected. What fraction of sons is expected to be affected?",
                    correct: "1/2 of sons",
                    distractors: ["1/4 of sons", "All sons", "No sons"],
                    explanation: "Each son receives Y from the father and one maternal X; half receive the recessive maternal X. One quarter is the fraction of all children under equal sex ratio, not of sons.",
                    hint: "Condition on the child already being a son.",
                    decisiveStep: "Use the mother’s 1/2 carrier-allele transmission among sons."
                ),
                ConcreteChoiceProblem(
                    prompt: "Two unaffected parents have a child with a rare autosomal recessive disorder. Under the simple Mendelian model, what parental genotypes are most consistent?",
                    correct: "Both parents are heterozygous carriers.",
                    distractors: ["Both parents are homozygous dominant.", "Exactly one parent must be homozygous recessive.", "The disorder must be dominant."],
                    explanation: "An affected child is aa and must receive a from each unaffected parent, making both most consistent with Aa. Homozygous-dominant parents cannot transmit a.",
                    hint: "Trace one recessive allele back to each parent.",
                    decisiveStep: "Require each unaffected parent to carry one recessive allele."
                ),
                ConcreteChoiceProblem(
                    prompt: "A researcher wants to use Hardy–Weinberg genotype proportions to predict the next generation from current allele frequencies. Which observation most directly invalidates a required assumption of that prediction?",
                    correct: "Individuals with one genotype leave twice as many offspring as the others.",
                    distractors: ["The sample contains both homozygotes and heterozygotes.", "Allele frequencies sum to one.", "Mating pairs are formed randomly with respect to the locus."],
                    explanation: "Genotype-dependent reproductive success is selection, so the no-selection assumption fails and current allele frequencies need not produce Hardy–Weinberg proportions unchanged. Random mating is required rather than a violation.",
                    hint: "Audit random mating, selection, migration, mutation, and finite-population effects.",
                    decisiveStep: "Identify genotype-dependent reproductive success as a violation of the no-selection assumption."
                )
            ]

        default:
            return nil
        }

        let problem = problems[basis.reasoningVariant]
        let correct = localized(problem.correct, request: request)
        return makeQuestion(
            request: request,
            basis: basis,
            prompt: localized(problem.prompt, request: request),
            choices: sourceChoices(
                correct: correct,
                distractors: problem.distractors.map { localized($0, request: request) },
                rotation: index,
                request: request
            ),
            correctAnswer: correct,
            explanation: localized(problem.explanation, request: request),
            hint: localized(problem.hint, request: request),
            decisiveStep: localized(problem.decisiveStep, request: request)
        )
    }

    private static func conceptShortAnswer(
        _ request: NFAuthoringRequest,
        basis: Basis
    ) -> NFAuthoredQuestion {
        let profile = topicConceptProfile(request, basis: basis)
        let variant = basis.reasoningVariant
        let prompts: [String.LocalizationValue] = [
            "State the governing relation or invariant for \(basis.topic.lowercased()) in one precise sentence.",
            "State one prerequisite that must be checked before applying the main method in \(basis.topic.lowercased()).",
            "Name a boundary or falsification test that directly challenges a \(basis.topic.lowercased()) solution.",
            "Name the characteristic diagnostic that exposes a plausible-looking error in \(basis.topic.lowercased()).",
            "Give the strongest interpretation warranted in \(basis.topic.lowercased()) without adding a broader claim.",
            "State the mapping check required before transferring \(basis.topic.lowercased()) reasoning to a new case."
        ]
        let answer = profile.facets[variant]
        let roleNames: [String.LocalizationValue] = [
            "governing invariant", "required prerequisite", "boundary test",
            "diagnostic", "bounded interpretation", "transfer mapping"
        ]
        let roleName = localized(roleNames[variant], request: request)
        return makeQuestion(
            request: request,
            basis: basis,
            prompt: localized(prompts[variant], request: request),
            correctAnswer: answer,
            explanation: answer,
            hint: localized("Answer only the requested reasoning role; do not substitute a neighboring fact from the topic.", request: request),
            decisiveStep: localized("State the topic-native \(roleName).", request: request)
        )
    }

    private static func semanticStarterShortAnswer(
        _ request: NFAuthoringRequest,
        basis: Basis
    ) -> NFAuthoredQuestion? {
        let problems: [ConcreteOpenProblem]
        switch semanticTopic(request, basis: basis) {
        case .fermiEstimation:
            problems = [
                ConcreteOpenProblem(
                    prompt: "Estimate full-time piano tuners for a city of 1.2 million people. Assume one piano per 30 residents, one service per piano per year, and 900 services per tuner-year. Show the factorization, round workers appropriately, and name one demand-driving assumption.",
                    correctAnswer: "Pianos ≈1,200,000/30=40,000; services/year ≈40,000; tuner-equivalents ≈40,000/900=44.4, so about 45 full-time tuners. Piano ownership or annual service frequency directly scales demand.",
                    acceptedAnswer: "About 45 tuners; population ÷ residents per piano × services per piano ÷ services per tuner.",
                    explanation: "The decomposition converts population to the installed piano stock, stock to annual service calls, and calls to worker capacity. Rounding up is appropriate because 44 workers cannot cover the estimated workload.",
                    hint: "Move through stock, annual demand, and annual capacity as separate factors.",
                    decisiveStep: "Build and audit population ÷ ownership ratio × service frequency ÷ worker capacity."
                ),
                ConcreteOpenProblem(
                    prompt: "Bound the number of breaths one person takes in a day if a plausible resting rate is 12–20 breaths/minute. Give the numerical interval and its order of magnitude, and state what the bound omits.",
                    correctAnswer: "A day has 1,440 minutes, so the bound is 12×1,440=17,280 to 20×1,440=28,800 breaths; both values have normalized scientific-notation exponent 4. Activity, sleep, illness, and individual variation are omitted.",
                    acceptedAnswer: "About 17,000–29,000 breaths/day; both have normalized scientific-notation exponent 4 under a constant-rate assumption.",
                    explanation: "A range communicates assumption uncertainty better than a false point estimate. Both endpoints are written as a coefficient times 10⁴, so the stated scientific-notation exponent is stable without invoking a different nearest-power convention.",
                    hint: "Convert one day to minutes, then propagate both rate endpoints.",
                    decisiveStep: "Propagate a plausible assumption interval and check whether its endpoints change the power of ten."
                ),
                ConcreteOpenProblem(
                    prompt: "A crowded rectangular platform is about 120 m by 8 m. Using a defensible crowd-density range of 2–4 people/m², estimate a capacity range and identify the geometric assumption behind it.",
                    correctAnswer: "Area≈120×8=960 m², so capacity≈960×(2–4)=1,920–3,840 people. This treats the usable platform as the full rectangle; barriers, safety setbacks, and circulation space would reduce usable area.",
                    acceptedAnswer: "Roughly 1,900–3,800 people; rectangular full-area occupancy is the simplifying assumption.",
                    explanation: "The estimate separates geometry from density, making it clear which measurement or assumption should be refined first. It also exposes why multiplying a linear dimension by density would be dimensionally wrong.",
                    hint: "Estimate area before applying people per square metre.",
                    decisiveStep: "Decompose capacity into usable area × plausible occupancy density."
                ),
                ConcreteOpenProblem(
                    prompt: "Estimate daily cups of coffee consumed in a city of 500,000 people. Assume 75% are coffee-drinking adults and those adults average 1.5 cups/day. Compute the estimate and give one sensitivity statement.",
                    correctAnswer: "500,000×0.75×1.5=562,500 cups/day, about 5.6×10⁵. A 10% relative change in either the drinker fraction or cups per drinker changes the total by 10% when the other factors stay fixed.",
                    acceptedAnswer: "About 562,500 cups/day; the estimate scales linearly with either behavioral assumption.",
                    explanation: "Population, participation fraction, and use per participant are distinct factors. Writing them separately makes double-counting visible and makes sensitivity proportional to each factor.",
                    hint: "First estimate coffee drinkers, then cups per drinker.",
                    decisiveStep: "Factor total demand into population × participation × per-participant use."
                ),
                ConcreteOpenProblem(
                    prompt: "A claim says a 20 m × 10 m × 5 m warehouse can hold 10 million boxes, each about 0.03 m³. Ignore aisles and packing loss to compute the absolute volume upper bound, then judge the claim’s scale.",
                    correctAnswer: "Warehouse volume=1,000 m³; even perfect packing gives 1,000/0.03≈33,333 boxes. Ten million exceeds that upper bound by about 300× (more than two orders of magnitude), so the claim is impossible under the stated dimensions.",
                    acceptedAnswer: "At most about 33,000 boxes before packing losses; 10 million is roughly 300 times too large.",
                    explanation: "An optimistic physical upper bound is a strong sanity check: real aisles and unused space can only lower capacity, so no detailed packing model can rescue the claim.",
                    hint: "Compare total warehouse volume with volume per box before considering efficiency.",
                    decisiveStep: "Use a physical upper bound to reject an estimate that is orders of magnitude too large."
                ),
                ConcreteOpenProblem(
                    prompt: "Estimate annual passenger-kilometres for 100,000 commuters traveling about 10 km per workday over 250 workdays. Give the value in normalized scientific notation, then explain how doubling distance changes its coefficient and exponent.",
                    correctAnswer: "100,000×10×250=250,000,000 passenger-km=2.5×10⁸. Doubling distance gives 5×10⁸: the coefficient doubles from 2.5 to 5 while the normalized scientific-notation exponent remains 8.",
                    acceptedAnswer: "About 2.5×10^8 passenger-km/year; doubling gives 5×10^8, with the same normalized exponent 8.",
                    explanation: "The estimate combines population scale, daily exposure, and annual frequency. Reporting the coefficient and exponent explicitly avoids ambiguity between scientific-notation exponent and a nearest-power-of-ten convention.",
                    hint: "Keep units on all three factors, then write the result in scientific notation.",
                    decisiveStep: "Compute the factor product and distinguish coefficient sensitivity from the normalized exponent."
                )
            ]

        case .transferReasoning:
            problems = [
                ConcreteOpenProblem(
                    prompt: "A bakery recipe makes 12 rolls from 750 g flour. A cafeteria needs 30 rolls. What flour amount should be transferred to the larger batch, and which invariant makes the transfer valid?",
                    correctAnswer: "Use 30/12=2.5 times the recipe, so flour is 750×2.5=1,875 g. The ingredient-per-roll ratio must remain constant.",
                    acceptedAnswer: "1,875 g; preserve the flour-per-roll ratio.",
                    explanation: "The surface setting changes from one batch size to another, but proportional scaling preserves each ingredient ratio. Scaling only flour would break the recipe constraint.",
                    hint: "Find the target-to-source roll ratio first.",
                    decisiveStep: "Map batch size to a common scale factor of 2.5."
                ),
                ConcreteOpenProblem(
                    prompt: "A medicine dose is transferred from adults to children by multiplying only by body-mass ratio. The adult rule assumes clearance is proportional to mass, but pediatric clearance also changes with age. State why the transfer is invalid and the smallest repair.",
                    correctAnswer: "The mapping preserves mass scale but not the clearance assumption, so mass-only dosing can misestimate exposure. Use an age-validated pediatric pharmacokinetic model or pediatric dosing evidence that maps both size and maturation before calculating a dose.",
                    acceptedAnswer: "Mass-only scaling fails because clearance is not proportional to mass across ages; use an age-validated pediatric model.",
                    explanation: "A sound transfer carries the relation and its domain assumptions, not just a convenient ratio. The changed maturation-to-clearance relation blocks direct reuse even though kilograms exist in both settings.",
                    hint: "Ask whether the quantity being scaled follows the same law in both populations.",
                    decisiveStep: "Reject surface unit matching when the target violates the source proportional-clearance assumption."
                ),
                ConcreteOpenProblem(
                    prompt: "A water-tank balance uses inflow − outflow = storage change. Map that structure to a bank account receiving 900 and spending 640 in one month, then compute the balance change.",
                    correctAnswer: "Map inflow to deposits, outflow to spending, and storage to account balance. The change is 900−640=260.",
                    acceptedAnswer: "Deposits − spending = balance change = 260.",
                    explanation: "The conserved stock-flow relation survives the domain change because both systems accumulate inputs and lose outputs over the same interval.",
                    hint: "Identify stock, inflow, and outflow in the target setting.",
                    decisiveStep: "Preserve the signed stock-flow balance."
                ),
                ConcreteOpenProblem(
                    prompt: "A bridge model is built at 1:50 linear scale. If the real span is 40 m, what model span in metres preserves geometry, and why would copying the real area by 1:50 be wrong?",
                    correctAnswer: "The model span is 40/50=0.8 m. Length scales by 1/50, but area scales by (1/50)², so using 1/50 for area would not preserve similarity.",
                    acceptedAnswer: "0.8 m; linear scale is 1/50 while area scale is 1/2,500.",
                    explanation: "Transfer between similar geometries requires each dimensional quantity to use the power of the linear scale matching its dimension.",
                    hint: "Distinguish a length from an area.",
                    decisiveStep: "Apply the scale factor with the correct dimensional exponent."
                ),
                ConcreteOpenProblem(
                    prompt: "A queueing analogy maps customers to data packets and cashiers to servers. Name one structural check required before using a single-cashier waiting-time result for a two-server packet system.",
                    correctAnswer: "The server-count assumption must be remapped: a single-cashier result cannot be copied to two parallel servers without a two-server service model and routing rule.",
                    acceptedAnswer: "Check and revise the one-server assumption for two parallel packet servers.",
                    explanation: "The entities can be renamed cleanly while the service topology changes. That changed relation, not vocabulary, determines the waiting-time behavior.",
                    hint: "Compare how many jobs can be served simultaneously.",
                    decisiveStep: "Map the service topology, not only customers and packets."
                ),
                ConcreteOpenProblem(
                    prompt: "A linear calibration maps sensor voltage V to temperature T by T=20V−5 for V in [0,5]. For V=3, compute T and state the boundary check needed before transferring the formula to V=6.",
                    correctAnswer: "At V=3, T=20×3−5=55. V=6 lies outside the calibrated [0,5] range, so the formula cannot be transferred without validating extrapolation.",
                    acceptedAnswer: "55; V=6 is outside the calibration range and needs new validation.",
                    explanation: "The algebraic mapping solves the in-range case, while the declared domain is a separate assumption that blocks unsupported extrapolation.",
                    hint: "Calculate first, then compare each input with the calibration interval.",
                    decisiveStep: "Preserve both the formula and its valid input range."
                )
            ]

        case .sourceStudy:
            problems = [
                ConcreteOpenProblem(
                    prompt: "No source material is attached. What must you add before a source-grounded question can ask for the author’s central claim?",
                    correctAnswer: "Attach or select the relevant passage, chapter, note, or paper so the claim can be cited and checked against its exact wording.",
                    acceptedAnswer: "Attach the source passage before asking for its central claim.",
                    explanation: "A source-specific claim cannot be reconstructed from a topic label alone. The actual material supplies the proposition, qualifiers, and citation needed for an answerable task.",
                    hint: "Ask what evidence would let another reader verify the answer.",
                    decisiveStep: "Require the source before authoring a source-grounded claim question."
                ),
                ConcreteOpenProblem(
                    prompt: "No table or figure is attached. What source information is required before asking the learner to calculate the paper’s reported effect size?",
                    correctAnswer: "Attach the labeled table, figure, or results excerpt containing the compared values, units, groups, and stated effect definition.",
                    acceptedAnswer: "Provide the labeled values, units, comparison groups, and effect definition from the source.",
                    explanation: "Numbers found elsewhere in a document are not automatically comparable. Labels and the paper’s defined contrast are necessary to avoid inventing a calculation.",
                    hint: "List the operands and labels a reproducible calculation needs.",
                    decisiveStep: "Require labeled source operands and the specified comparison."
                ),
                ConcreteOpenProblem(
                    prompt: "A learner wants a proof question ‘using the theorem from my chapter,’ but no theorem statement is selected. What exact source span should be attached?",
                    correctAnswer: "Attach the theorem statement together with its hypotheses, definitions used by the statement, and enough surrounding text to identify its scope.",
                    acceptedAnswer: "Select the theorem, its hypotheses, relevant definitions, and scope qualifiers.",
                    explanation: "A proof task is answerable only when the permitted claim and prerequisites are explicit; the theorem name alone may hide variant assumptions.",
                    hint: "A proof needs both a conclusion and the conditions under which it holds.",
                    decisiveStep: "Require the complete theorem contract, not merely its name."
                ),
                ConcreteOpenProblem(
                    prompt: "A code-debugging set should use the learner’s implementation, but no code is attached. What must the learner select so a deterministic bug question can be grounded?",
                    correctAnswer: "Attach the complete relevant function or code block, its input contract, and the expected behavior or failing example.",
                    acceptedAnswer: "Provide the relevant code, input assumptions, and expected or failing behavior.",
                    explanation: "Without executable structure or an explicit contract, a generator can only invent a generic bug. The selected code identifies real state transitions and boundaries.",
                    hint: "Include both what runs and what it is supposed to do.",
                    decisiveStep: "Require code plus a behavioral contract."
                ),
                ConcreteOpenProblem(
                    prompt: "A learner selects one sentence from a paper: ‘The treatment may improve recovery in this sample.’ Which two textual features must a recall answer preserve exactly?",
                    correctAnswer: "It must preserve the qualifier ‘may’ and the scope ‘in this sample’; omitting either would strengthen the source beyond what it states.",
                    acceptedAnswer: "Keep both ‘may’ and ‘in this sample.’",
                    explanation: "Modality limits certainty and the sample phrase limits population scope. Active recall should reconstruct those constraints, not just the treatment-outcome nouns.",
                    hint: "Look for a certainty word and a population boundary.",
                    decisiveStep: "Recover both modality and scope from the selected sentence."
                ),
                ConcreteOpenProblem(
                    prompt: "A selected methods excerpt states: ‘Samples were heated to 80 °C for 10 minutes before measurement.’ What two procedural details must a faithful short answer recover?",
                    correctAnswer: "The samples were heated to 80 °C and held there for 10 minutes before measurement.",
                    acceptedAnswer: "80 °C for 10 minutes before measurement.",
                    explanation: "Temperature and duration jointly define the preparation step; recovering only one would not reproduce the cited procedure or its order.",
                    hint: "Identify the condition, duration, and sequence marker.",
                    decisiveStep: "Preserve both numeric conditions and the before-measurement order."
                )
            ]

        default:
            return nil
        }
        return openProblem(request, basis: basis, problems[basis.reasoningVariant])
    }

    private static func multipleChoice(
        _ request: NFAuthoringRequest,
        basis: Basis,
        index: Int
    ) -> NFAuthoredQuestion {
        if let sourceSentence = basis.sourceSentence {
            return makeQuestion(
                request: request,
                basis: basis,
                prompt: sourceMultipleChoicePrompt(request, topic: basis.topic),
                choices: sourceChoices(
                    correct: sourceSentence,
                    distractors: [
                        localized("The excerpt proves the exact opposite in every case.", request: request),
                        localized("The excerpt establishes a universal causal law without qualifications.", request: request),
                        localized("No conclusion of any kind can be drawn from the excerpt.", request: request)
                    ],
                    rotation: index,
                    request: request
                ),
                correctAnswer: sourceSentence,
                explanation: localized("The supported answer restates the cited sentence without strengthening, reversing, or universalizing it.", request: request),
                hint: localized("Watch qualifiers such as may, under, if, and in this sample.", request: request),
                decisiveStep: sourceDecisiveStep(request)
            )
        }

        if basis.sourceText == nil {
            return conceptMultipleChoice(request, basis: basis, index: index)
        }

        switch semanticTopic(request, basis: basis) {
        case .dijkstraShortestPaths:
            let correct = localized("When a non-stale minimum-key vertex is removed, its tentative distance equals its shortest-path distance.", request: request)
            return makeQuestion(
                request: request,
                basis: basis,
                prompt: localized("For Dijkstra’s algorithm with nonnegative edge weights, which invariant justifies finalizing vertex u after removing its current minimum-key entry from the priority queue?", request: request),
                choices: [
                    correct,
                    localized("Every discovered vertex already has its final distance.", request: request),
                    localized("The priority queue contains each vertex exactly once.", request: request),
                    localized("The most recently relaxed edge must belong to every shortest path.", request: request)
                ],
                correctAnswer: correct,
                explanation: localized("Any hypothetical shorter path to u would have to cross from the finalized set through a vertex whose tentative key is smaller than u’s. That contradicts removing u as the current minimum; nonnegative edges are essential to this argument.", request: request),
                hint: localized("State what is known at the exact moment a current minimum key is removed.", request: request),
                decisiveStep: localized("Use the minimum-frontier invariant together with nonnegative edge weights.", request: request)
            )

        case .mathematicalInduction:
            let correct = localized("Assume the statement for k, then use that assumption to establish the statement for k + 1.", request: request)
            return makeQuestion(
                request: request,
                basis: basis,
                prompt: localized("Which step supplies the logical bridge in a proof by mathematical induction?", request: request),
                choices: [
                    correct,
                    localized("Check one large numerical example and treat it as universal.", request: request),
                    localized("Assume the statement for every integer without proving a base case.", request: request),
                    localized("Prove the statement for k + 1 without using the induction hypothesis.", request: request)
                ],
                correctAnswer: correct,
                explanation: localized("The base case starts the chain. The induction step proves P(k) → P(k + 1), allowing the established case to propagate to every later integer in the stated domain.", request: request),
                hint: localized("Identify the implication that links one integer to its successor.", request: request),
                decisiveStep: localized("Establish P(k) → P(k + 1) under the induction hypothesis.", request: request)
            )

        default:
            break
        }

        switch request.lab {
        case .mentalMath:
            let answer = basis.a * basis.b * 10
            return makeQuestion(request: request, basis: basis,
                prompt: localized("A \(basis.topic.lowercased()) workflow processes \(basis.a * 10) observations in each of \(basis.b) batches. How many observations are processed?", request: request),
                choices: ["\(answer)", "\(basis.a * basis.b)", "\(answer + 10)", "\(basis.a * (basis.b + 10))"], correctAnswer: "\(answer)",
                explanation: localized("Multiply the per-batch count by the number of batches: \(basis.a * 10) × \(basis.b) = \(answer).", request: request),
                hint: localized("Separate the tens factor before multiplying.", request: request),
                decisiveStep: localized("Multiply batch size by batch count.", request: request))
        case .spatial:
            let x = basis.a - 5
            let y = basis.b - 4
            let answer = "(\(-y), \(x))"
            return makeQuestion(request: request, basis: basis,
                prompt: localized("In a \(basis.topic.lowercased()) coordinate model, rotate (\(x), \(y)) by 90° counterclockwise about the origin.", request: request),
                choices: [
                    answer,
                    localized("(\(y), \(-x)) · clockwise", request: request),
                    localized("(\(-x), \(-y)) · half-turn", request: request),
                    localized("(\(x), \(-y)) · reflection", request: request)
                ],
                correctAnswer: answer,
                explanation: localized("A 90° counterclockwise rotation maps (x, y) to (−y, x).", request: request),
                hint: localized("Track where the positive x-axis moves.", request: request),
                decisiveStep: localized("Apply (x, y) → (−y, x).", request: request))
        case .quantitative:
            let population = basis.a * 100
            let rate = basis.b
            let answer = "\(population * rate / 100)"
            return makeQuestion(request: request, basis: basis,
                prompt: localized("A \(basis.topic.lowercased()) sample contains \(population) cases and \(rate)% meet a criterion. What is the expected count?", request: request),
                choices: [answer, "\(population * rate)", "\(population / rate)", "\(population - rate)"], correctAnswer: answer,
                explanation: localized("Convert \(rate)% to \(rate)/100, then multiply by \(population).", request: request),
                hint: localized("A percentage is a rate per hundred.", request: request),
                decisiveStep: localized("Multiply the total by the decimal rate.", request: request))
        case .scientificReasoning:
            let correct = localized("Self-selection can create baseline differences", request: request)
            return makeQuestion(request: request, basis: basis,
                prompt: localized("Two \(basis.topic.lowercased()) groups choose their own treatment, and their outcomes differ. What most directly blocks a causal conclusion?", request: request),
                choices: [
                    correct,
                    localized("The outcome is numerical", request: request),
                    localized("There are two groups", request: request),
                    localized("A mean can be calculated", request: request)
                ],
                correctAnswer: correct,
                explanation: localized("Without random assignment or adequate adjustment, pre-existing differences can explain the outcome gap.", request: request),
                hint: localized("Ask what differed before treatment began.", request: request),
                decisiveStep: localized("Identify selection as a confounding path.", request: request))
        case .logicDebugging:
            let correct = localized("Verification cannot be concluded from publication alone", request: request)
            return makeQuestion(request: request, basis: basis,
                prompt: localized("A \(basis.topic.lowercased()) rule says: if a record is verified, it may be published. The record was published. What follows logically?", request: request),
                choices: [
                    correct,
                    localized("The record was definitely verified", request: request),
                    localized("The rule is false", request: request),
                    localized("No records can be verified", request: request)
                ],
                correctAnswer: correct,
                explanation: localized("The rule gives verified → publishable. Inferring verified from published reverses the implication.", request: request),
                hint: localized("Do not assume the converse of an if-then rule.", request: request),
                decisiveStep: localized("Preserve the direction of implication.", request: request))
        case .retrieval:
            let correct = localized("Recall it now, then again after increasing delays", request: request)
            return makeQuestion(request: request, basis: basis,
                prompt: localized("Which retrieval schedule is most likely to test durable recall of a \(basis.topic.lowercased()) concept?", request: request),
                choices: [
                    correct,
                    localized("Reread it five times immediately", request: request),
                    localized("Copy it while looking at the source", request: request),
                    localized("Highlight every sentence once", request: request)
                ],
                correctAnswer: correct,
                explanation: localized("Repeated retrieval separated by delay tests and strengthens access over time.", request: request),
                hint: localized("Choose the option that requires recall after forgetting can begin.", request: request),
                decisiveStep: localized("Combine retrieval with expanding delay.", request: request))
        case .transfer:
            let correct = localized("Compare unfamiliar systems using the same ratio structure", request: request)
            return makeQuestion(request: request, basis: basis,
                prompt: localized("You learned to compare \(basis.topic.lowercased()) systems using output per unit input. Which new task best tests transfer?", request: request),
                choices: [
                    correct,
                    localized("Repeat the original examples verbatim", request: request),
                    localized("Memorize the definition of ratio", request: request),
                    localized("Copy the worked solution", request: request)
                ],
                correctAnswer: correct,
                explanation: localized("Transfer preserves the underlying relation while changing surface context and examples.", request: request),
                hint: localized("Look for a new setting with the same mathematical structure.", request: request),
                decisiveStep: localized("Map the learned ratio structure into a novel context.", request: request))
        }
    }

    private static func shortAnswer(_ request: NFAuthoringRequest, basis: Basis) -> NFAuthoredQuestion {
        if let sourceSentence = basis.sourceSentence {
            let variant = basis.reasoningVariant
            let prompts: [String.LocalizationValue] = [
                "Reconstruct the cited claim in one sentence while preserving every qualifier. Use only the cited excerpt.",
                "Recall the complete proposition in the cited excerpt. Preserve its condition, scope, and direction without adding a stronger claim.",
                "Restate what the cited source actually asserts. Keep any modality, numerical value, comparison, or population boundary intact.",
                "Write a faithful one-sentence paraphrase of the cited proposition, then compare it with the reference wording.",
                "Recover the source statement without reversing its relation, dropping its limitation, or turning it into a causal or universal claim.",
                "From memory, state the cited proposition precisely enough that another reader can verify every substantive part against the excerpt."
            ]
            let explanations: [String.LocalizationValue] = [
                "The reference retains the source proposition and all words that limit certainty, conditions, or scope.",
                "A faithful recall preserves both the relation being asserted and the boundaries under which the source asserts it.",
                "Numbers, comparison direction, modality, and population scope can change a claim’s meaning, so each must survive recall when present.",
                "Paraphrase may change surface wording, but it must remain entailed by the cited proposition and must not strengthen it.",
                "Reversal, qualifier deletion, causal upgrade, and universalization are distinct meaning changes that the reference avoids.",
                "The cited sentence is the checkable authority; the comparison should focus on its substantive relation and constraints rather than punctuation."
            ]
            let hints: [String.LocalizationValue] = [
                "Preserve words that limit scope or certainty.",
                "Identify the subject, relation, condition, and boundary before answering.",
                "Check numbers, direction words, and qualifiers separately.",
                "Change wording only after identifying what cannot change in meaning.",
                "Look specifically for converse, causation, and all-versus-some errors.",
                "Use the citation to compare meaning after you attempt recall."
            ]
            let steps: [String.LocalizationValue] = [
                "Recover the exact claim and its qualifiers.",
                "Preserve condition, scope, and direction.",
                "Retain every meaning-bearing value and boundary.",
                "Paraphrase without strengthening the cited proposition.",
                "Reject reversal, qualifier loss, and causal or universal upgrade.",
                "Compare recalled meaning with the complete cited proposition."
            ]
            return makeQuestion(
                request: request,
                basis: basis,
                prompt: localized(prompts[variant], request: request),
                correctAnswer: sourceSentence,
                explanation: localized(explanations[variant], request: request),
                hint: localized(hints[variant], request: request),
                decisiveStep: localized(steps[variant], request: request)
            )
        }


        if basis.sourceText == nil {
            return conceptShortAnswer(request, basis: basis)
        }

        if semanticTopic(request, basis: basis) == .dijkstraShortestPaths {
            let correct = localized("Dijkstra’s finalization proof requires nonnegative edge weights; reject the graph or use an algorithm such as Bellman–Ford when negative edges are present.", request: request)
            return makeQuestion(
                request: request,
                basis: basis,
                prompt: localized("A graph for Dijkstra’s algorithm contains a negative-weight edge. State why the usual finalized-distance invariant is no longer justified and give one sound correction.", request: request),
                correctAnswer: correct,
                acceptedAnswers: [
                    localized("Negative edges invalidate Dijkstra’s greedy finalization; use Bellman–Ford.", request: request),
                    localized("Reject negative weights before running Dijkstra.", request: request)
                ],
                explanation: localized("A later path can use a negative edge to reduce the distance of a vertex that the greedy step already finalized. Enforcing nonnegative weights restores the precondition; Bellman–Ford is a standard alternative when negative edges must be supported.", request: request),
                hint: localized("Ask whether a later edge can make an already-finalized distance smaller.", request: request),
                decisiveStep: localized("Connect nonnegative weights to the safety of greedy finalization.", request: request),
                requiredTermGroups: [
                    "negative edge|negative weight|nonnegative|non-negative|負の辺|非負",
                    "bellman-ford|bellman ford|reject|validate|different algorithm|ベルマン|拒否|検証",
                    "finalized|finalization|greedy invariant|確定|貪欲"
                ],
                minimumRequiredTermMatches: 2,
                rejectedAssertionGroups: [
                    "dijkstra supports negative weights|negative edges are safe|no correction is needed|負の辺でも安全"
                ]
            )
        }

        if semanticTopic(request, basis: basis) == .mathematicalInduction {
            let correct = localized("The base case starts the implication chain; the induction step proves P(k) → P(k + 1), so neither part can replace the other.", request: request)
            return makeQuestion(
                request: request,
                basis: basis,
                prompt: localized("In one sentence, distinguish the roles of the base case and the induction step in a proof by induction.", request: request),
                correctAnswer: correct,
                acceptedAnswers: [
                    localized("The base case starts the proof, and the induction step carries truth from k to k + 1.", request: request)
                ],
                explanation: localized("An implication step without a verified starting case proves no instance, while isolated base cases do not establish the infinite chain.", request: request),
                hint: localized("Think of a starting point and a rule for reaching the next point.", request: request),
                decisiveStep: localized("Separate initiation from propagation.", request: request),
                requiredTermGroups: [
                    "base case|starting case|initiation|基底|出発",
                    "k + 1|k+1|induction step|propagat|帰納段階|次"
                ],
                minimumRequiredTermMatches: 2
            )
        }
        let correct = localized("No; publishable does not imply verified.", request: request)
        return makeQuestion(
            request: request,
            basis: basis,
            prompt: localized("In a \(basis.topic.lowercased()) rule, verified → publishable. A record is publishable. Can verification be concluded? Answer in one sentence.", request: request),
            correctAnswer: correct,
            acceptedAnswers: [
                localized("No, the converse does not follow.", request: request),
                localized("No", request: request)
            ],
            explanation: localized("The supplied implication only runs from verified to publishable; its converse was not given.", request: request),
            hint: localized("Check the direction of the arrow.", request: request),
            decisiveStep: localized("Reject the unsupported converse.", request: request)
        )
    }

    private struct QuantitativeTopicProfile {
        let observation: String
        let unit: String
        let interval: String
    }

    private static func quantitativeTopicProfile(
        _ request: NFAuthoringRequest,
        basis: Basis
    ) -> QuantitativeTopicProfile {
        func values(_ observation: String.LocalizationValue, _ unit: String.LocalizationValue, _ interval: String.LocalizationValue) -> QuantitativeTopicProfile {
            QuantitativeTopicProfile(
                observation: localized(observation, request: request),
                unit: localized(unit, request: request),
                interval: localized(interval, request: request)
            )
        }

        switch semanticTopic(request, basis: basis) {
        case .fermiEstimation: return values("estimated events", "events", "day")
        case .probability: return values("favorable outcomes", "outcomes", "trial block")
        case .mathematicalModeling: return values("feasible output", "output units", "resource period")
        case .calculus: return values("accumulated change", "output units", "input unit")
        case .linearAlgebra: return values("vector operations", "operations", "matrix block")
        case .classicalMechanics: return values("displacement", "metres", "second")
        case .electricityCircuits: return values("transferred charge", "coulombs", "second")
        case .wavesOscillations: return values("completed cycles", "cycles", "second")
        case .thermodynamics: return values("energy transfer", "joules", "kilogram")
        case .measurementUncertainty: return values("measured length", "millimetres", "measurement run")
        case .algorithmAnalysis, .programBoundaries, .dataStructures, .graphTraversal,
             .dijkstraShortestPaths, .binarySearch, .dynamicProgramming, .sorting, .concurrency:
            return values("counted operations", "operations", "input element")
        case .engineeringStatics: return values("supported load", "kilonewtons", "support")
        case .controlSystems: return values("response error", "error units", "second")
        case .signalsSampling: return values("captured samples", "samples", "second")
        case .materialsFailure: return values("applied stress", "megapascals", "load step")
        case .unitsAndTolerances: return values("component length", "millimetres", "component")
        case .stoichiometry: return values("product amount", "moles", "reaction batch")
        case .reactionKinetics: return values("product formed", "millimoles", "minute")
        case .chemicalEquilibrium: return values("equilibrium concentration", "millimoles per litre", "sample")
        case .thermochemistry: return values("enthalpy change", "kilojoules", "mole")
        case .solutions: return values("solute amount", "millimoles", "litre")
        case .genetics: return values("offspring with the focal phenotype", "offspring", "cross")
        case .biologicalExperiments: return values("measured responses", "responses", "experimental batch")
        case .cellRegulation: return values("activated cells", "cells", "assay interval")
        case .epidemiology: return values("new cases", "cases", "person-year")
        case .ecology: return values("observed organisms", "organisms", "quadrat")
        case .classifierEvaluation: return values("correct positive predictions", "predictions", "evaluation fold")
        case .statisticalInference: return values("observed responses", "responses", "sample group")
        case .validationLeakage: return values("held-out records", "records", "evaluation fold")
        case .regression: return values("predicted outcome change", "outcome units", "predictor unit")
        case .dataPipelines: return values("validated rows", "rows", "pipeline batch")
        default:
            switch request.field {
            case .general: return values("observations", "observations", "time period")
            case .mathematics: return values("counted cases", "cases", "group")
            case .physics: return values("measured quantity", "measurement units", "second")
            case .computing: return values("counted operations", "operations", "input element")
            case .engineering: return values("measured output", "engineering units", "test interval")
            case .lifeSciences: return values("biological responses", "responses", "sample")
            case .chemistry: return values("chemical amount", "moles", "batch")
            case .dataScience: return values("evaluated records", "records", "data split")
            }
        }
    }

    private struct ConcreteNumericProblem {
        let prompt: String.LocalizationValue
        let answer: Double
        let explanation: String.LocalizationValue
        let hint: String.LocalizationValue
        let decisiveStep: String.LocalizationValue
        var displayPrecision: Int? = nil
        var absoluteTolerance: Double? = nil
    }

    private static func numericProblem(
        _ request: NFAuthoringRequest,
        basis: Basis,
        _ problem: ConcreteNumericProblem
    ) -> NFAuthoredQuestion {
        makeQuestion(
            request: request,
            basis: basis,
            prompt: localized(problem.prompt, request: request),
            correctAnswer: number(problem.answer),
            explanation: localized(problem.explanation, request: request),
            hint: localized(problem.hint, request: request),
            decisiveStep: localized(problem.decisiveStep, request: request),
            numericDisplayPrecision: problem.displayPrecision,
            numericAbsoluteTolerance: problem.absoluteTolerance ?? 1e-9
        )
    }

    /// A numerical starter may include one reasoning-first item when its card
    /// explicitly promises formulation, diagnosis, or an audit that a numeric
    /// field cannot observe. The individual question carries the truthful open
    /// style and self-check contract while the set retains a quantitative focus.
    private static func numericalReasoningProblem(
        _ request: NFAuthoringRequest,
        basis: Basis
    ) -> NFAuthoredQuestion? {
        let problem: ConcreteOpenProblem
        let style: NFQuestionStyle
        switch (semanticTopic(request, basis: basis), basis.reasoningVariant) {
        case (.mathematicalModeling, 2):
            style = .shortAnswer
            problem = ConcreteOpenProblem(
                prompt: "A meal service chooses whole numbers x of standard trays and y of protein trays. A standard tray earns 30, uses 1 prep-hour and 2 kg of ingredients; a protein tray earns 50, uses 2 prep-hours and 3 kg. At most 8 prep-hours and 18 kg are available. Formulate the decision variables, profit objective, resource constraints, and domain; do not solve the model.",
                correctAnswer: "Let x and y be the nonnegative integer counts of standard and protein trays. Maximize 30x+50y subject to x+2y≤8, 2x+3y≤18, and x,y∈{0,1,2,…}.",
                acceptedAnswer: "Maximize 30x+50y with x+2y≤8, 2x+3y≤18, and nonnegative integer tray counts.",
                explanation: "Each resource statement becomes one inequality with coefficients tied to the tray that consumes it. Whole trays make integrality part of the model rather than a rounding step after optimization.",
                hint: "Name both tray-count variables, then write one inequality per limited resource.",
                decisiveStep: "Translate the scenario into variables, an objective, two resource constraints, and a nonnegative-integer domain."
            )

        case (.classicalMechanics, 3):
            style = .proofOrDerivation
            problem = ConcreteOpenProblem(
                prompt: "A cart starts from rest under a constant net force F for time t. Choose the governing law, derive its speed in terms of F, mass m, and t, then check the t=0 limit and dimensions.",
                correctAnswer: "Use Newton’s second law F=ma, so a=F/m. Constant acceleration from rest gives v=at=Ft/m. At t=0, v=0; and (N·s)/kg=(kg·m/s²·s)/kg=m/s.",
                acceptedAnswer: "From F=ma and v=at, v=Ft/m; it vanishes at t=0 and has units m/s.",
                explanation: "The force law supplies acceleration and the constant-acceleration relation accumulates it over time. The boundary and dimensional checks test the derived expression rather than adding unscored instructions.",
                hint: "Convert force to acceleration before using the initial condition.",
                decisiveStep: "Select F=ma, derive v=Ft/m, and verify both the zero-time limit and speed dimension."
            )

        case (.electricityCircuits, 4):
            style = .debugging
            problem = ConcreteOpenProblem(
                prompt: "A student writes I=QΔt and reports coulomb-seconds for current. Diagnose the unit inconsistency, give the dimensionally consistent equation, and calculate the current when 10 C passes in 2 s.",
                correctAnswer: "Current is charge per time, so I=Q/Δt, not QΔt. The unit is C/s=A, and 10 C/2 s=5 A.",
                acceptedAnswer: "Replace multiplication with division: I=Q/Δt=5 A because amperes are C/s.",
                explanation: "Multiplying produces C·s, which is dimensionally inconsistent with current. The unit audit identifies division before any numbers are substituted.",
                hint: "Write one ampere in base charge-and-time units.",
                decisiveStep: "Reject the C·s product, restore I=Q/Δt, and obtain 5 A."
            )

        case (.thermodynamics, 4):
            style = .proofOrDerivation
            problem = ConcreteOpenProblem(
                prompt: "A heat engine receives 800 J and delivers 240 J of work. Calculate its efficiency, apply the physical-range boundary check 0≤η≤1, and explain what an answer of 1.30 would imply.",
                correctAnswer: "η=Wout/Qin=240/800=0.30, which lies in [0,1]. An efficiency of 1.30 would claim 1.30 J of work per joule received and violate energy conservation for a heat engine.",
                acceptedAnswer: "Efficiency is 0.30; 1.30 is outside the physical range and would output more work than input energy.",
                explanation: "The ratio is not just arithmetic: the 0≤η≤1 boundary check follows because useful work cannot exceed the supplied energy in this model.",
                hint: "Form output divided by input, then interpret the result as a fraction of supplied energy.",
                decisiveStep: "Compute η=0.30 and use the physical range from conservation to reject η>1."
            )

        case (.engineeringStatics, 1):
            style = .proofOrDerivation
            problem = ConcreteOpenProblem(
                prompt: "Construct the free-body model for a simply supported beam with a pin and roller under a centered 20 kN downward point load. State the assumption that makes the two vertical reactions equal, solve them, and explain what changes if the load moves off center.",
                correctAnswer: "The free body has the 20 kN downward load plus upward reactions RA and RB. Centered geometry and symmetric supports give RA=RB; vertical equilibrium RA+RB−20=0 then gives RA=RB=10 kN. Off center, the reactions are unequal and moments must determine them.",
                acceptedAnswer: "With centered symmetric loading, RA=RB and ΣFy=0 gives 10 kN each; an off-center load requires moment equilibrium and unequal reactions.",
                explanation: "Equilibrium alone fixes only the reaction sum. Symmetry supplies equality; changing the load location removes that assumption and makes the moment equation decisive.",
                hint: "Separate what follows from ΣFy=0 from what follows from symmetry.",
                decisiveStep: "Draw the free body, declare the symmetry assumption, solve 2R=20, and state its boundary."
            )

        case (.unitsAndTolerances, 2):
            style = .debugging
            problem = ConcreteOpenProblem(
                prompt: "Two stacked parts are 20.0±0.2 mm and 35.0±0.3 mm. A student reports [54.8,55.2] mm by keeping only the larger tolerance. Diagnose the error and give the complete worst-case interval.",
                correctAnswer: "Worst-case tolerances add, so the nominal stack is 55.0 mm with ±(0.2+0.3)=±0.5 mm. The complete interval is [54.5,55.5] mm; [54.8,55.2] drops one component’s possible deviation.",
                acceptedAnswer: "Add both tolerances: 55.0±0.5 mm, or [54.5,55.5] mm.",
                explanation: "For an adversarial worst-case bound, both parts can simultaneously sit at their lower limits or at their upper limits. Keeping one tolerance understates both endpoints.",
                hint: "Compute lower+lower and upper+upper, not only the nominal total.",
                decisiveStep: "Combine both component tolerances and report the full interval [54.5,55.5] mm."
            )

        case (.stoichiometry, 4):
            style = .debugging
            problem = ConcreteOpenProblem(
                prompt: "For N₂+3H₂→2NH₃, a student predicts that 4 mol N₂ needs 4/3 mol H₂. Diagnose the conversion-factor direction, write a factor whose units cancel, and calculate the required H₂.",
                correctAnswer: "The student inverted the coefficients. Multiply 4 mol N₂ by (3 mol H₂)/(1 mol N₂), which cancels mol N₂ and gives 12 mol H₂.",
                acceptedAnswer: "Use 3 mol H₂ per 1 mol N₂, not its reciprocal; 4×3=12 mol H₂.",
                explanation: "A balanced-equation ratio is directional. Writing units on the factor makes the incorrect reciprocal visible before arithmetic.",
                hint: "Place mol N₂ in the factor denominator so it cancels the given unit.",
                decisiveStep: "Reject the inverted mole ratio and calculate 12 mol H₂ with explicit unit cancellation."
            )

        case (.solutions, 1):
            style = .debugging
            problem = ConcreteOpenProblem(
                prompt: "To dilute 50 mL of 2.0 M stock to 0.50 M, a student rearranges solute conservation as V₂=C₂V₁/C₁ and obtains 12.5 mL. Diagnose the inverted concentration ratio, derive the correct expression for V₂, and calculate the physically consistent final volume.",
                correctAnswer: "Solute conservation gives C₁V₁=C₂V₂, so V₂=C₁V₁/C₂=(2.0 M)(50 mL)/(0.50 M)=200 mL. The student inverted C₁/C₂; a dilution to lower concentration must increase, not decrease, the final volume.",
                acceptedAnswer: "The ratio is inverted: V₂=C₁V₁/C₂=200 mL, not 12.5 mL.",
                explanation: "The amount of solute is unchanged, so concentration times volume must match before and after dilution. Dividing by the smaller final concentration makes V₂ larger than V₁, which also supplies a boundary check on the algebra.",
                hint: "Begin with C₁V₁=C₂V₂ and isolate V₂ before inserting values.",
                decisiveStep: "Preserve solute amount, reject the inverted C₂/C₁ ratio, and derive V₂=C₁V₁/C₂=200 mL."
            )

        default:
            return nil
        }
        return openProblem(request, basis: basis, problem, styleOverride: style)
    }

    /// Six reviewed, worked calculations for every numerical starter topic.
    /// Values are fixed on purpose: deterministic variation comes from the
    /// rotated mechanic, while the worked key can remain exact and auditable.
    private static func semanticNumerical(
        _ request: NFAuthoringRequest,
        basis: Basis
    ) -> NFAuthoredQuestion? {
        if let reasoning = numericalReasoningProblem(request, basis: basis) {
            return reasoning
        }
        let problems: [ConcreteNumericProblem]
        switch semanticTopic(request, basis: basis) {
        case .fermiEstimation:
            problems = [
                ConcreteNumericProblem(
                    prompt: "Estimate the number of breaths taken in one day at 15 breaths per minute. Use 60 minutes per hour and 24 hours per day; return only the number.",
                    answer: 21_600,
                    explanation: "A day contains 60 × 24 = 1,440 minutes, so 15 × 1,440 = 21,600 breaths.",
                    hint: "Convert one day to minutes before multiplying by the breathing rate.",
                    decisiveStep: "Compute 15 × 60 × 24."
                ),
                ConcreteNumericProblem(
                    prompt: "A shelf has 4 usable metres of width and an average book is 2.5 centimetres thick. Ignoring gaps, estimate how many books fit. Return only the number.",
                    answer: 160,
                    explanation: "Convert 4 m to 400 cm, then divide by 2.5 cm per book: 400 ÷ 2.5 = 160.",
                    hint: "Put shelf width and book thickness in the same unit.",
                    decisiveStep: "Convert metres to centimetres, then divide width by thickness."
                ),
                ConcreteNumericProblem(
                    prompt: "A town has 24,000 households and each household uses an estimated 2.5 litres of drinking water per day. Estimate the town’s daily total in litres; return only the number.",
                    answer: 60_000,
                    explanation: "Daily total = households × litres per household = 24,000 × 2.5 = 60,000 litres.",
                    hint: "Treat the households as equal estimated groups.",
                    decisiveStep: "Multiply 24,000 households by 2.5 litres per household."
                ),
                ConcreteNumericProblem(
                    prompt: "A commuter travels 18 kilometres each way on 220 workdays. Estimate the annual round-trip distance in kilometres; return only the number.",
                    answer: 7_920,
                    explanation: "Each workday contributes 2 × 18 = 36 km, and 36 × 220 = 7,920 km per year.",
                    hint: "Include both directions before multiplying by workdays.",
                    decisiveStep: "Compute 18 × 2 × 220."
                ),
                ConcreteNumericProblem(
                    prompt: "A stadium has 40 rows per block, 25 seats per row, and 4 comparable blocks. Estimate its seating capacity; return only the number.",
                    answer: 4_000,
                    explanation: "One block has 40 × 25 = 1,000 seats; four blocks therefore have about 4,000 seats.",
                    hint: "Estimate one block first, then scale to four blocks.",
                    decisiveStep: "Multiply rows × seats per row × blocks."
                ),
                ConcreteNumericProblem(
                    prompt: "A city of 1,200,000 people has about one piano per 30 residents. One tuner can service 900 pianos per year. Estimate how many full-time tuners are needed; return only the number.",
                    answer: 45,
                    explanation: "Estimated pianos = 1,200,000 ÷ 30 = 40,000; 40,000 ÷ 900 ≈ 44.44 tuner-equivalents, so covering every piano requires rounding up to 45 full-time tuners.",
                    hint: "Estimate the piano stock before dividing by annual tuner capacity.",
                    decisiveStep: "Compute tuner-equivalents, then round up to a whole worker."
                )
            ]

        case .probability:
            problems = [
                ConcreteNumericProblem(
                    prompt: "A fair six-sided die is rolled once. What is the probability of an even result? Return the probability as a decimal.",
                    answer: 0.5,
                    explanation: "The favorable outcomes are {2, 4, 6}, so 3 of 6 equally likely outcomes give 3/6 = 0.5.",
                    hint: "List the even faces and divide by all faces.",
                    decisiveStep: "Count 3 favorable outcomes out of 6."
                ),
                ConcreteNumericProblem(
                    prompt: "A bag contains 5 red and 3 blue tokens. Two tokens are drawn without replacement. What is the probability both are red? Round to four decimal places.",
                    answer: 0.357_142_857_1,
                    explanation: "Without replacement, P(red then red) = 5/8 × 4/7 = 20/56 ≈ 0.3571428571.",
                    hint: "Reduce both the red count and total count after the first draw.",
                    decisiveStep: "Multiply 5/8 by 4/7.",
                    displayPrecision: 4,
                    absoluteTolerance: 0.00005
                ),
                ConcreteNumericProblem(
                    prompt: "Events A and B are independent with P(A) = 0.30 and P(B) = 0.40. What is P(A and B)? Return a decimal.",
                    answer: 0.12,
                    explanation: "Independence gives P(A ∩ B) = P(A)P(B) = 0.30 × 0.40 = 0.12.",
                    hint: "Use the product rule for independent events.",
                    decisiveStep: "Multiply the two independent probabilities."
                ),
                ConcreteNumericProblem(
                    prompt: "Use natural frequencies for 10,000 people: disease prevalence is 1%, sensitivity is 90%, and the false-positive rate is 5%. What fraction of all positive tests are true positives? Round to four decimal places.",
                    answer: 0.153_846_153_8,
                    explanation: "The 1% base rate gives 100 diseased and 9,900 non-diseased people. The test produces 90 true positives and 495 false positives, so 90/(90+495)=0.1538461538.",
                    hint: "Turn the base rate into counts before forming the positive-test denominator.",
                    decisiveStep: "Compare 90 true positives with all 585 positive tests.",
                    displayPrecision: 4,
                    absoluteTolerance: 0.00005
                ),
                ConcreteNumericProblem(
                    prompt: "A game pays 12 points with probability 0.25 and loses 2 points with probability 0.75. What is the expected point change? Return only the number.",
                    answer: 1.5,
                    explanation: "Expected change = 0.25×12 + 0.75×(−2) = 3 − 1.5 = 1.5 points.",
                    hint: "Weight every payoff, including the loss, by its probability.",
                    decisiveStep: "Compute 0.25×12 + 0.75×(−2)."
                ),
                ConcreteNumericProblem(
                    prompt: "In 200 independent trials with success probability 0.35, what is the expected number of successes? Return only the number.",
                    answer: 70,
                    explanation: "For a binomial count, E[X] = np = 200 × 0.35 = 70 successes.",
                    hint: "Use the binomial expectation np.",
                    decisiveStep: "Multiply trial count by success probability."
                )
            ]

        case .mathematicalModeling:
            problems = [
                ConcreteNumericProblem(
                    prompt: "A workshop makes x basic units and y premium units. Profit is 30x + 50y, with x + y ≤ 8 and 2x + 4y ≤ 24. Among corner points (0,0), (8,0), (4,4), and (0,6), what is the maximum profit? Return only the number.",
                    answer: 320,
                    explanation: "All four listed corners are feasible. Their profits are 0, 240, 320, and 300, so (4,4) gives the maximum profit of 320.",
                    hint: "Evaluate the objective at each listed feasible corner.",
                    decisiveStep: "Compare 30x + 50y at all four corner points."
                ),
                ConcreteNumericProblem(
                    prompt: "A service has fixed cost 1,200 and earns 30 per subscription after variable cost. How many subscriptions are needed to break even? Return only the number.",
                    answer: 40,
                    explanation: "Break-even sets contribution equal to fixed cost: 30n = 1,200, so n = 40.",
                    hint: "Set total contribution margin equal to fixed cost.",
                    decisiveStep: "Solve 30n = 1,200."
                ),
                ConcreteNumericProblem(
                    prompt: "A delivery model predicts T=12 min+(0.8 min/km)d for distance d in kilometres. Check the term units, then find T at d=15 km. Return only the numerical minute value.",
                    answer: 24,
                    explanation: "The slope term has units (min/km)(km)=min, so it can be added to the 12 min intercept. Substitution gives T=12+0.8×15=24 minutes.",
                    hint: "Verify both additive terms are minutes before substituting.",
                    decisiveStep: "Audit the model units, then evaluate 12+0.8×15."
                ),
                ConcreteNumericProblem(
                    prompt: "A feasible production plan uses 7 machine-hours per batch, and 52 machine-hours are available. What is the greatest whole number of batches allowed by this constraint? Return only the number.",
                    answer: 7,
                    explanation: "52 ÷ 7 = 7 remainder 3, so the capacity constraint permits at most 7 complete batches.",
                    hint: "The decision variable must be a whole number and cannot exceed capacity.",
                    decisiveStep: "Take the floor of 52 ÷ 7."
                ),
                ConcreteNumericProblem(
                    prompt: "A quadratic cost model is C(x) = (x − 6)² + 20. At what x is cost minimized? Return only the number.",
                    answer: 6,
                    explanation: "The squared term is smallest at zero, which occurs when x − 6 = 0; therefore the minimum is at x = 6.",
                    hint: "A square cannot be negative.",
                    decisiveStep: "Set x − 6 = 0."
                ),
                ConcreteNumericProblem(
                    prompt: "An objective value is 480 when a resource limit is 100 and 510 when the limit is 110. Assuming this local sensitivity is linear, what is the objective gain per additional resource unit? Return only the number.",
                    answer: 3,
                    explanation: "Local sensitivity = (510 − 480)/(110 − 100) = 30/10 = 3 objective units per resource unit.",
                    hint: "Use change in objective divided by change in the resource bound.",
                    decisiveStep: "Compute Δobjective/Δresource."
                )
            ]

        case .classicalMechanics:
            problems = [
                ConcreteNumericProblem(
                    prompt: "A 6 kg cart experiences a net force of 18 N. Using F = ma, what is its acceleration in m/s²? Return only the number.",
                    answer: 3,
                    explanation: "Solve F = ma for acceleration: a = F/m = 18/6 = 3 m/s².",
                    hint: "Mass belongs in the denominator when solving for acceleration.",
                    decisiveStep: "Divide net force by mass."
                ),
                ConcreteNumericProblem(
                    prompt: "A 2 kg cart moving at 6 m/s sticks to a stationary 1 kg cart on a level low-friction track. Using momentum conservation, what common speed in m/s follows? Return only the number.",
                    answer: 4,
                    explanation: "Initial momentum is 2×6+1×0=12 kg·m/s. After sticking, total mass is 3 kg, so v=12/3=4 m/s.",
                    hint: "Conserve total momentum, then use the combined mass.",
                    decisiveStep: "Set initial momentum equal to (2+1)v."
                ),
                ConcreteNumericProblem(
                    prompt: "An object is released from rest 5 m above a reference level. Neglect air resistance and use g=10 m/s². From mechanical-energy conservation, what speed in m/s does it have at the reference level? Return only the number.",
                    answer: 10,
                    explanation: "Mass cancels from mgh=½mv². Thus v=√(2gh)=√(2×10×5)=10 m/s, which also has the correct √(length²/time²) dimension.",
                    hint: "Equate lost gravitational potential energy with gained kinetic energy.",
                    decisiveStep: "Solve mgh=½mv² and check the speed dimension."
                ),
                ConcreteNumericProblem(
                    prompt: "Starting from rest, an object accelerates uniformly at 2 m/s² for 6 s. First check that v=v₀+at returns zero when t=0, then find the final speed in m/s. Return only the final number.",
                    answer: 12,
                    explanation: "The limiting check t=0 gives v=v₀=0 as required. At t=6 s, v=0+2×6=12 m/s.",
                    hint: "Check the zero-time boundary before substituting 6 s.",
                    decisiveStep: "Verify the t=0 limit, then compute at from rest."
                ),
                ConcreteNumericProblem(
                    prompt: "A 3 kg sled starts at 2 m/s and a constant 9 N forward force acts through 4 m on level ice. Friction does −6 J of work. Using the work–energy relation, return only the final speed in m/s, rounded to three decimal places.",
                    answer: 4.899,
                    explanation: "Initial kinetic energy is ½×3×2²=6 J. Applied work is 9×4=36 J and friction contributes −6 J, so final kinetic energy is 36 J. Solving ½×3×v²=36 gives v=√24≈4.899 m/s.",
                    hint: "Add signed work to the initial kinetic energy before solving for speed.",
                    decisiveStep: "Use net work to update kinetic energy, including the negative friction work.",
                    displayPrecision: 3,
                    absoluteTolerance: 0.0005
                ),
                ConcreteNumericProblem(
                    prompt: "A 0.5 kg ball reverses direction from −4 m/s to +6 m/s. What signed impulse Δp in N·s acts on it? Return only the number.",
                    answer: 5,
                    explanation: "Impulse is Δp=m(v_f−v_i)=0.5[6−(−4)]=0.5×10=+5 N·s. The positive sign follows the stated axis.",
                    hint: "Use final velocity minus initial velocity, including both signs.",
                    decisiveStep: "Compute m(v_f−v_i) with the declared direction."
                )
            ]

        case .electricityCircuits:
            problems = [
                ConcreteNumericProblem(
                    prompt: "A 12 V source is connected across a 4 Ω resistor. What current flows in amperes? Return only the number.",
                    answer: 3,
                    explanation: "Ohm’s law gives I = V/R = 12/4 = 3 A.",
                    hint: "Solve V = IR for current.",
                    decisiveStep: "Divide voltage by resistance."
                ),
                ConcreteNumericProblem(
                    prompt: "Resistors of 3 Ω and 7 Ω are in series across 10 V. What voltage in volts appears across the 7 Ω resistor? Return only the number.",
                    answer: 7,
                    explanation: "The series resistance is 10 Ω, so current is 10/10=1 A. The 7 Ω drop is IR=1×7=7 V; the two drops sum to the source voltage.",
                    hint: "Find the common series current before one resistor’s voltage drop.",
                    decisiveStep: "Use total resistance for current, then apply V=IR to 7 Ω."
                ),
                ConcreteNumericProblem(
                    prompt: "Two 6 Ω resistors are connected in parallel across 12 V. What total source current in amperes follows from branch-current conservation? Return only the number.",
                    answer: 4,
                    explanation: "Each branch current is 12/6=2 A. Kirchhoff’s current law gives total current 2+2=4 A (equivalently R_eq=3 Ω and 12/3=4 A).",
                    hint: "The same voltage appears across both branches; add their currents.",
                    decisiveStep: "Compute both branch currents and apply current conservation."
                ),
                ConcreteNumericProblem(
                    prompt: "A device draws 2 A from a 9 V supply for 30 s. How much electrical energy in joules does it receive? Return only the number.",
                    answer: 540,
                    explanation: "Power is P=VI=9×2=18 W, then energy is E=Pt=18×30=540 J. Watts times seconds reduce to joules.",
                    hint: "Compute power first, then multiply by duration.",
                    decisiveStep: "Chain E=VIt and verify W·s=J."
                ),
                ConcreteNumericProblem(
                    prompt: "A student writes I=QΔt and reports coulomb-seconds for current. Diagnose the unit inconsistency, then use the correct relation for 10 C passing in 2 s. Return only the current in amperes.",
                    answer: 5,
                    explanation: "Current has units C/s, so the consistent relation is I=Q/Δt, not QΔt. Therefore I=10/2=5 A.",
                    hint: "One ampere is one coulomb per second.",
                    decisiveStep: "Reject the dimensionally inconsistent product and divide charge by time."
                ),
                ConcreteNumericProblem(
                    prompt: "A +3 C charge moves through a final-minus-initial potential change ΔV=+5 V. What is ΔU=qΔV in joules? Return only the number.",
                    answer: 15,
                    explanation: "ΔU = qΔV = 3 × 5 = 15 J.",
                    hint: "One volt is one joule per coulomb.",
                    decisiveStep: "Multiply charge by potential difference."
                )
            ]

        case .thermodynamics:
            problems = [
                ConcreteNumericProblem(
                    prompt: "How much heat in joules raises 2 kg of water by 3 °C if c = 4,200 J/(kg·°C)? Return only the number.",
                    answer: 25_200,
                    explanation: "Q = mcΔT = 2 × 4,200 × 3 = 25,200 J.",
                    hint: "Use the sensible-heat relation Q = mcΔT.",
                    decisiveStep: "Multiply mass, specific heat, and temperature change."
                ),
                ConcreteNumericProblem(
                    prompt: "A gas expands by 0.020 m³ against a constant pressure of 100,000 Pa. What work does the gas do in joules? Return only the number.",
                    answer: 2_000,
                    explanation: "At constant pressure, W = PΔV = 100,000 × 0.020 = 2,000 J.",
                    hint: "Use pressure times volume change.",
                    decisiveStep: "Evaluate PΔV."
                ),
                ConcreteNumericProblem(
                    prompt: "A system absorbs 500 J of heat and does 180 J of work on its surroundings. Using ΔU = Q − W, what is ΔU in joules? Return only the number.",
                    answer: 320,
                    explanation: "With work done by the system positive, ΔU = 500 − 180 = 320 J.",
                    hint: "Use the sign convention stated in the formula.",
                    decisiveStep: "Subtract work done by the system from absorbed heat."
                ),
                ConcreteNumericProblem(
                    prompt: "A system goes from state A to state B by path 1 with Q=500 J and W_by=180 J, so ΔU=320 J. Path 2 reaches the same states with Q=650 J. Because internal energy is a state function, what work W_by in joules must path 2 perform? Return only the number.",
                    answer: 330,
                    explanation: "The same endpoints require the same ΔU=320 J even though heat and work are path quantities. From ΔU=Q−W_by, W_by=650−320=330 J.",
                    hint: "Keep ΔU fixed across paths, not Q or W separately.",
                    decisiveStep: "Distinguish the state-function change from path heat and solve 320=650−W."
                ),
                ConcreteNumericProblem(
                    prompt: "A heat engine receives 800 J and delivers 240 J of work. Compute its efficiency as a decimal and check that it lies in the physical range 0≤η≤1. Return only the number.",
                    answer: 0.3,
                    explanation: "Efficiency η=W_out/Q_in=240/800=0.30. The value is between zero and one, so it passes the basic energy-scale boundary check.",
                    hint: "Useful work is the numerator, then compare the result with one.",
                    decisiveStep: "Compute W_out/Q_in and audit its physical range."
                ),
                ConcreteNumericProblem(
                    prompt: "A system reversibly absorbs 600 J of heat at 300 K. What entropy change ΔS=Q_rev/T occurs in J/K? Return only the number.",
                    answer: 2,
                    explanation: "ΔS = Q_rev/T = 600/300 = 2 J/K.",
                    hint: "Use absolute temperature in the denominator.",
                    decisiveStep: "Divide reversible heat by temperature."
                )
            ]

        case .engineeringStatics:
            problems = [
                ConcreteNumericProblem(
                    prompt: "A 12 kN downward load has a 2 m perpendicular horizontal lever arm from a pin. What is its moment magnitude about the pin in kN·m? Return only the number.",
                    answer: 24,
                    explanation: "Moment magnitude is force times perpendicular distance: 12 × 2 = 24 kN·m.",
                    hint: "Use the perpendicular lever arm.",
                    decisiveStep: "Multiply load by moment arm."
                ),
                ConcreteNumericProblem(
                    prompt: "Draw the free-body model for a simply supported beam with a pin and roller, then use the stated symmetry assumption for a centered 20 kN downward point load. What upward reaction acts at each support in kN? Return only the number.",
                    answer: 10,
                    explanation: "The free-body diagram contains the 20 kN load and two vertical support reactions. Centered geometry makes the reactions equal; vertical equilibrium ΣF_y=0 gives 2R−20=0, so R=10 kN.",
                    hint: "Show both support reactions before applying symmetry and vertical equilibrium.",
                    decisiveStep: "Construct the free-body diagram, declare symmetry, and solve the equilibrium equation 2R=20."
                ),
                ConcreteNumericProblem(
                    prompt: "A member has failure capacity 90 kN and design load 30 kN. What is its safety factor (factor of safety)? Return only the number.",
                    answer: 3,
                    explanation: "Safety factor (factor of safety)=capacity/design load=90/30=3.",
                    hint: "Capacity belongs in the numerator.",
                    decisiveStep: "Divide failure capacity by design load."
                ),
                ConcreteNumericProblem(
                    prompt: "Two collinear horizontal forces, +18 kN and −7 kN, act on a joint. What is the signed resultant in kN? Return only the number.",
                    answer: 11,
                    explanation: "With the stated sign convention, resultant = 18 + (−7) = +11 kN.",
                    hint: "Preserve the force directions as signs.",
                    decisiveStep: "Add the signed forces."
                ),
                ConcreteNumericProblem(
                    prompt: "A uniform load of 4 kN/m spans 5 m. The equivalent concentrated load acts at the load diagram’s centroid, the span midpoint. What is its magnitude in kN? Return only the number.",
                    answer: 20,
                    explanation: "The resultant magnitude is the area under the uniform load diagram: 4×5=20 kN, applied at the rectangle’s centroid at midspan.",
                    hint: "Use the area under the load diagram.",
                    decisiveStep: "Multiply load intensity by span."
                ),
                ConcreteNumericProblem(
                    prompt: "A symmetric joint supports a 10 kN downward load with two identical cables, each 30° above horizontal. Horizontal components cancel. What tension in kN acts in each cable? Return only the number.",
                    answer: 10,
                    explanation: "Vertical equilibrium gives 2T sin30°=10 kN. Because sin30°=0.5, the left side is T, so each cable carries 10 kN; the equal horizontal components cancel by symmetry.",
                    hint: "Resolve each cable tension into its vertical component.",
                    decisiveStep: "Apply vertical equilibrium 2T sin30°=10."
                )
            ]

        case .unitsAndTolerances:
            problems = [
                ConcreteNumericProblem(
                    prompt: "Convert 2.75 metres to millimetres. Return only the number.",
                    answer: 2_750,
                    explanation: "One metre is 1,000 mm, so 2.75 × 1,000 = 2,750 mm.",
                    hint: "Multiply metres by 1,000.",
                    decisiveStep: "Apply the exact metre-to-millimetre conversion."
                ),
                ConcreteNumericProblem(
                    prompt: "Convert an area of 0.006 m² to mm². Return only the number.",
                    answer: 6_000,
                    explanation: "Because 1 m = 1,000 mm, 1 m² = 1,000² mm²; therefore 0.006 × 1,000,000 = 6,000 mm².",
                    hint: "Square the linear conversion factor for area.",
                    decisiveStep: "Multiply by 1,000², not merely 1,000."
                ),
                ConcreteNumericProblem(
                    prompt: "Two stacked parts are 20.0 ± 0.2 mm and 35.0 ± 0.3 mm. Under worst-case tolerance addition, what is the maximum stack length in mm? Return only the number.",
                    answer: 55.5,
                    explanation: "Worst-case maximum = 20.0 + 0.2 + 35.0 + 0.3 = 55.5 mm.",
                    hint: "For the maximum, add both positive tolerances.",
                    decisiveStep: "Add nominal lengths and upper tolerance limits."
                ),
                ConcreteNumericProblem(
                    prompt: "A shaft is specified as 10.00 ± 0.05 mm. What is the full tolerance-band width in mm? Return only the number.",
                    answer: 0.1,
                    explanation: "The limits are 9.95 and 10.05 mm, so band width = 10.05 − 9.95 = 0.10 mm.",
                    hint: "The ± value is half the full band width.",
                    decisiveStep: "Subtract lower limit from upper limit."
                ),
                ConcreteNumericProblem(
                    prompt: "An audit compares L=vt with L=v+t, where L is length, v is length/time, and t is time. How many of these two equations are dimensionally consistent? Return only the number.",
                    answer: 1,
                    explanation: "vt has dimension (length/time)×time=length, so L=vt is consistent. v+t adds unlike dimensions and cannot equal a length, so exactly one equation passes the dimensional audit.",
                    hint: "Reduce the units on each right-hand side before comparing with length.",
                    decisiveStep: "Reject addition of quantities with different dimensions."
                ),
                ConcreteNumericProblem(
                    prompt: "A design capacity is 72 N and the required load is 48 N. What percentage margin relative to required load is available? Return only the number.",
                    answer: 50,
                    explanation: "Margin percentage = (72 − 48)/48 × 100 = 24/48 × 100 = 50%.",
                    hint: "Use required load, not capacity, as the reference denominator.",
                    decisiveStep: "Compute excess capacity divided by required load."
                )
            ]

        case .stoichiometry:
            problems = [
                ConcreteNumericProblem(
                    prompt: "For 2H₂ + O₂ → 2H₂O, how many moles of H₂O form from 5 mol H₂ with excess O₂? Return only the number.",
                    answer: 5,
                    explanation: "The coefficients of H₂ and H₂O are both 2, so the mole ratio is 1:1 and 5 mol H₂ yields 5 mol H₂O.",
                    hint: "Read the H₂:H₂O coefficient ratio from the balanced equation.",
                    decisiveStep: "Multiply by 2 mol H₂O / 2 mol H₂."
                ),
                ConcreteNumericProblem(
                    prompt: "For 2A + B → 2C, 8 mol A and 3 mol B are available. What is the maximum amount of C in moles? Return only the number.",
                    answer: 6,
                    explanation: "A supports extent 8/2=4, while B supports extent 3/1=3; B is the limiting reagent, so the reaction forms 2×3=6 mol C.",
                    hint: "Compare coefficient-adjusted extents to identify the limiting reagent.",
                    decisiveStep: "Use the smaller extent, 3 from limiting reagent B."
                ),
                ConcreteNumericProblem(
                    prompt: "A reaction has theoretical yield 40 g and actual yield 30 g. What is the percent yield? Return only the number.",
                    answer: 75,
                    explanation: "Percent yield = actual/theoretical × 100 = 30/40 × 100 = 75%.",
                    hint: "Actual yield belongs in the numerator.",
                    decisiveStep: "Divide 30 g by 40 g and multiply by 100."
                ),
                ConcreteNumericProblem(
                    prompt: "How many moles are in 36 g of H₂O if its molar mass is 18 g/mol? Return only the number.",
                    answer: 2,
                    explanation: "Amount = mass/molar mass = 36/18 = 2 mol.",
                    hint: "Grams cancel when dividing by grams per mole.",
                    decisiveStep: "Divide mass by molar mass."
                ),
                ConcreteNumericProblem(
                    prompt: "For N₂ + 3H₂ → 2NH₃, a student inverts the H₂:N₂ mole ratio and predicts 4/3 mol H₂ for 4 mol N₂. Diagnose that coefficient-ratio error and return only the correct number of moles of H₂.",
                    answer: 12,
                    explanation: "The balanced equation requires 3 mol H₂ for every 1 mol N₂, not its reciprocal. Therefore 4×3=12 mol H₂; 4/3 uses the mole ratio in the wrong direction.",
                    hint: "Write units on the conversion factor so mol N₂ cancels.",
                    decisiveStep: "Diagnose the inverted mole ratio and multiply by 3 mol H₂/mol N₂."
                ),
                ConcreteNumericProblem(
                    prompt: "A 0.50 mol sample reacts according to A → 2B. If conversion is 80%, how many moles of B form? Return only the number.",
                    answer: 0.8,
                    explanation: "Reacted A = 0.50×0.80 = 0.40 mol; the 1:2 ratio gives B = 2×0.40 = 0.80 mol.",
                    hint: "Apply conversion before the stoichiometric coefficient.",
                    decisiveStep: "Compute 0.50×0.80×2."
                )
            ]

        case .solutions:
            problems = [
                ConcreteNumericProblem(
                    prompt: "A solution contains 0.50 mol solute in 2.0 L. What is its molarity in mol/L? Return only the number.",
                    answer: 0.25,
                    explanation: "Molarity M = n/V = 0.50/2.0 = 0.25 mol/L.",
                    hint: "Divide solute amount by total solution volume.",
                    decisiveStep: "Evaluate n/V."
                ),
                ConcreteNumericProblem(
                    prompt: "What final volume in mL is needed to dilute 50 mL of 2.0 M stock to 0.50 M? Return only the number.",
                    answer: 200,
                    explanation: "C₁V₁ = C₂V₂ gives V₂ = 2.0×50/0.50 = 200 mL.",
                    hint: "Conserve solute amount during dilution.",
                    decisiveStep: "Solve C₁V₁ = C₂V₂ for V₂."
                ),
                ConcreteNumericProblem(
                    prompt: "How many moles of solute are present in 0.40 L of a 1.5 M solution? Return only the number.",
                    answer: 0.6,
                    explanation: "n = MV = 1.5 mol/L × 0.40 L = 0.60 mol.",
                    hint: "Multiply molarity by volume in litres.",
                    decisiveStep: "Evaluate M×V."
                ),
                ConcreteNumericProblem(
                    prompt: "A mixture contains 10 g solute and 90 g solvent. What is the solute mass percentage? Return only the number.",
                    answer: 10,
                    explanation: "Total solution mass is 100 g, so mass percent = 10/100 × 100 = 10%.",
                    hint: "Use total solution mass in the denominator.",
                    decisiveStep: "Divide solute mass by solute plus solvent mass."
                ),
                ConcreteNumericProblem(
                    prompt: "Mix 100 mL of 1.0 M solution with 100 mL of 3.0 M solution containing the same nonreacting solute, assuming additive volumes. What is the final molarity? Return only the number.",
                    answer: 2,
                    explanation: "Because the solute is the same and does not react, total solute is 0.100×1.0 + 0.100×3.0 = 0.400 mol in 0.200 L, so M = 2.0.",
                    hint: "Add moles of the same solute first, then divide by total volume.",
                    decisiveStep: "Compute conserved same-solute moles over 0.200 L."
                ),
                ConcreteNumericProblem(
                    prompt: "A 0.20 M solute dissociates ideally into three ions per formula unit. What total particle concentration in mol/L is predicted? Return only the number.",
                    answer: 0.6,
                    explanation: "Ideal complete dissociation gives particle concentration iC=3×0.20=0.60 mol/L. This counts dissolved particles rather than formula units.",
                    hint: "Multiply formula-unit concentration by the stated particle count.",
                    decisiveStep: "Apply the van ’t Hoff particle factor of 3."
                )
            ]

        default:
            return nil
        }

        return numericProblem(request, basis: basis, problems[basis.reasoningVariant])
    }

    private static func diversifiedNumerical(
        _ request: NFAuthoringRequest,
        basis: Basis
    ) -> NFAuthoredQuestion {
        let profile = quantitativeTopicProfile(request, basis: basis)
        let variant = basis.reasoningVariant
        let prompt: String
        let answer: Double
        let explanation: String
        let hint: String
        let decisiveStep: String

        switch variant {
        case 0:
            let groups = Double(basis.a)
            let perGroup = Double(basis.b)
            answer = groups * perGroup
            prompt = localized("In a \(basis.topic.lowercased()) audit, each of \(number(groups)) groups contains \(number(perGroup)) \(profile.observation). How many \(profile.unit) are recorded in total? Return only the number.", request: request)
            explanation = localized("Equal groups give total = group count × amount per group = \(number(groups)) × \(number(perGroup)) = \(number(answer)).", request: request)
            hint = localized("Treat the observations as repeated equal groups.", request: request)
            decisiveStep = localized("Multiply group count by the per-group amount.", request: request)
        case 1:
            let intervals = Double(max(2, basis.b))
            let total = Double(basis.a) * intervals
            answer = total / intervals
            prompt = localized("A \(basis.topic.lowercased()) record reports \(number(total)) \(profile.unit) across \(number(intervals)) \(profile.interval)s. What is the mean rate in \(profile.unit) per \(profile.interval)? Return only the number.", request: request)
            explanation = localized("Mean rate is total amount divided by total interval: \(number(total)) ÷ \(number(intervals)) = \(number(answer)).", request: request)
            hint = localized("Put the interval count in the denominator.", request: request)
            decisiveStep = localized("Divide total amount by total interval.", request: request)
        case 2:
            let total = Double(basis.a * 20)
            let percent = Double(max(5, basis.b * 5))
            answer = total * percent / 100
            prompt = localized("In a \(basis.topic.lowercased()) sample of \(number(total)) \(profile.unit), \(number(percent))% meet the stated criterion. How many meet it? Return only the number.", request: request)
            explanation = localized("Convert the percentage to a fraction and multiply: \(number(total)) × \(number(percent))/100 = \(number(answer)).", request: request)
            hint = localized("A percentage is a rate per hundred.", request: request)
            decisiveStep = localized("Multiply the total by the decimal percentage.", request: request)
        case 3:
            let firstValue = Double(basis.a)
            let secondValue = Double(basis.a + basis.b)
            let firstCount = 2.0
            let secondCount = 3.0
            answer = (firstCount * firstValue + secondCount * secondValue) / (firstCount + secondCount)
            prompt = localized("For \(basis.topic.lowercased()), two runs average \(number(firstValue)) \(profile.unit) and three runs average \(number(secondValue)) \(profile.unit). What is the combined mean across all five runs? Return only the number.", request: request)
            explanation = localized("Weight each mean by its run count: [2 × \(number(firstValue)) + 3 × \(number(secondValue))] ÷ 5 = \(number(answer)).", request: request)
            hint = localized("Do not average the two means equally; their run counts differ.", request: request)
            decisiveStep = localized("Compute a run-count-weighted mean.", request: request)
        case 4:
            let initial = Double(basis.a)
            let final = initial - Double(basis.b)
            answer = final - initial
            prompt = localized("A \(basis.topic.lowercased()) measurement changes from \(number(initial)) to \(number(final)) \(profile.unit). Compute the signed change final − initial. Return only the number.", request: request)
            explanation = localized("Keep the requested order: \(number(final)) − \(number(initial)) = \(number(answer)). The negative sign records a decrease.", request: request)
            hint = localized("Subtract in the displayed order and retain the sign.", request: request)
            decisiveStep = localized("Compute final minus initial.", request: request)
        default:
            let lowInput = 2.0
            let highInput = 6.0
            let lowOutput = Double(basis.a)
            let highOutput = lowOutput + Double(basis.b * 2)
            let targetInput = 3.0
            answer = lowOutput + (targetInput - lowInput) * (highOutput - lowOutput) / (highInput - lowInput)
            prompt = localized("A stated linear \(basis.topic.lowercased()) calibration maps input \(number(lowInput)) to \(number(lowOutput)) \(profile.unit) and input \(number(highInput)) to \(number(highOutput)) \(profile.unit). What output corresponds to input \(number(targetInput))? Return only the number.", request: request)
            explanation = localized("The target lies one quarter of the way from input 2 to 6, so add one quarter of the output change: \(number(lowOutput)) + [\(number(highOutput)) − \(number(lowOutput))]/4 = \(number(answer)).", request: request)
            hint = localized("Find the target input’s fractional position between the two calibration inputs.", request: request)
            decisiveStep = localized("Use linear interpolation between the stated calibration points.", request: request)
        }

        return makeQuestion(
            request: request,
            basis: basis,
            prompt: prompt,
            correctAnswer: number(answer),
            explanation: explanation,
            hint: hint,
            decisiveStep: decisiveStep
        )
    }

    private static func numerical(
        _ request: NFAuthoringRequest,
        basis: Basis,
        index: Int
    ) -> NFAuthoredQuestion {
        if let pair = sourceNumericPair(in: basis) {
            let answer = pair.second - pair.first
            let measure = pair.measureLabel.map { " (\($0))" } ?? ""
            return makeQuestion(
                request: request,
                basis: basis,
                prompt: localized("In the cited table, \(pair.firstLabel)\(measure) is \(number(pair.first)) and \(pair.secondLabel)\(measure) is \(number(pair.second)). Compute the signed change from the first labeled observation to the second (second − first). Return only the number.", request: request),
                correctAnswer: number(answer),
                explanation: localized("Use the displayed order and subtract the first value from the second: \(number(pair.second)) − \(number(pair.first)) = \(number(answer)). This checks the calculation without inventing labels or units that the excerpt does not provide.", request: request),
                hint: localized("Keep the order: second value minus first value.", request: request),
                decisiveStep: localized("Compute the signed change using only the cited values.", request: request)
            )
        }
        if let expression = sourceArithmeticExpression(in: basis) {
            return makeQuestion(
                request: request,
                basis: basis,
                prompt: localized("Evaluate the explicit arithmetic subexpression \(expression.expression) from the cited equation. Return only the number.", request: request),
                correctAnswer: number(expression.answer),
                explanation: localized("The answer evaluates only the cited arithmetic subexpression; no unstated source relationship is inferred.", request: request),
                hint: localized("Use the operation exactly as written in the cited equation.", request: request),
                decisiveStep: localized("Evaluate the cited subexpression directly.", request: request)
            )
        }
        if basis.sourceText != nil {
            let count = basis.numericValues.count
            return makeQuestion(
                request: request,
                basis: basis,
                prompt: localized("This excerpt does not define a labeled numerical relationship. How many explicit numeric values does the cited excerpt contain? Return only the number.", request: request),
                correctAnswer: "\(count)",
                explanation: localized("The safe deterministic task counts the \(count) explicit numeric values instead of inventing a subtraction or ratio between unrelated quantities.", request: request),
                hint: localized("Count explicit numbers without assuming they are comparable.", request: request),
                decisiveStep: localized("Do not infer a numerical relationship the source does not state.", request: request)
            )
        }
        if basis.sourceText == nil {
            return diversifiedNumerical(request, basis: basis)
        }
        let first = basis.sourceSentence == nil ? basis.a * 10 : basis.wordCount
        let second = basis.b
        let answer = first * second
        let origin = basis.sourceSentence == nil
            ? localized("A \(basis.topic.lowercased()) workflow has \(first) units in each batch.", request: request)
            : localized("The cited sentence contains \(first) word tokens under the displayed whitespace-counting rule.", request: request)
        return makeQuestion(
            request: request,
            basis: basis,
            prompt: localized("\(origin) A verification pass checks each unit \(second) times. How many checks occur? Return only the number.", request: request),
            correctAnswer: "\(answer)",
            explanation: localized("Multiply the explicit unit count by the number of passes: \(first) × \(second) = \(answer).", request: request),
            hint: localized("This is repeated equal-group counting.", request: request),
            decisiveStep: localized("Multiply units by checks per unit.", request: request)
        )
    }

    private static func conceptProof(
        _ request: NFAuthoringRequest,
        basis: Basis
    ) -> NFAuthoredQuestion {
        let profile = topicConceptProfile(request, basis: basis)
        let variant = basis.reasoningVariant
        let prompts: [String.LocalizationValue] = [
            "Build a correctness argument for the governing invariant in \(basis.topic.lowercased()). State what must hold initially, what must be preserved, and why that is enough at the end.",
            "Give a necessity argument for a key prerequisite in \(basis.topic.lowercased()): explain the failure that becomes possible when the prerequisite is removed.",
            "Construct a decisive boundary case or counterexample for \(basis.topic.lowercased()), and state exactly which overbroad claim it tests.",
            "A \(basis.topic.lowercased()) solution reaches a plausible result after an invalid step. Identify the diagnostic that locates the first unsupported step and justify the smallest repair.",
            "Derive the strongest conclusion warranted in \(basis.topic.lowercased()) and explain why the evidence does not support a broader conclusion.",
            "Justify transferring a \(basis.topic.lowercased()) method to a new setting by stating the structural mapping and the assumptions that must remain true."
        ]
        let proofRoles: [String.LocalizationValue] = [
            "Use initialization, preservation, and termination rather than checking examples alone.",
            "Show how removing the prerequisite permits a concrete failure.",
            "Use one admissible boundary case that makes the overbroad statement false.",
            "Locate the first invariant, unit, direction, or scope violation before repairing later symptoms.",
            "Separate the supported conclusion from its converse, causal upgrade, or universal generalization.",
            "Map objects, relations, constraints, and checks—not just vocabulary."
        ]
        let answer = profile.facets[variant] + " " + localized(proofRoles[variant], request: request)
        return makeQuestion(
            request: request,
            basis: basis,
            prompt: localized(prompts[variant], request: request),
            correctAnswer: answer,
            acceptedAnswers: [profile.facets[variant]],
            explanation: answer,
            hint: localized("Organize the response around the requested proof role before adding topic details.", request: request),
            decisiveStep: localized(proofRoles[variant], request: request)
        )
    }

    private struct ConcreteOpenProblem {
        let prompt: String.LocalizationValue
        let correctAnswer: String.LocalizationValue
        let acceptedAnswer: String.LocalizationValue
        let explanation: String.LocalizationValue
        let hint: String.LocalizationValue
        let decisiveStep: String.LocalizationValue
    }

    private static func openProblem(
        _ request: NFAuthoringRequest,
        basis: Basis,
        _ problem: ConcreteOpenProblem,
        styleOverride: NFQuestionStyle? = nil
    ) -> NFAuthoredQuestion {
        makeQuestion(
            request: request,
            basis: basis,
            styleOverride: styleOverride,
            prompt: localized(problem.prompt, request: request),
            correctAnswer: localized(problem.correctAnswer, request: request),
            acceptedAnswers: [localized(problem.acceptedAnswer, request: request)],
            explanation: localized(problem.explanation, request: request),
            hint: localized(problem.hint, request: request),
            decisiveStep: localized(problem.decisiveStep, request: request)
        )
    }

    private static func semanticStarterProof(
        _ request: NFAuthoringRequest,
        basis: Basis
    ) -> NFAuthoredQuestion? {
        let problems: [ConcreteOpenProblem]
        switch semanticTopic(request, basis: basis) {
        case .calculus:
            problems = [
                ConcreteOpenProblem(
                    prompt: "Using the limit definition $$f'(x)=\\lim_{h\\to0}\\frac{f(x+h)-f(x)}{h},$$ derive the derivative of $$f(x)=x^2$$ and show the cancellation.",
                    correctAnswer: "For h ≠ 0, [(x+h)²−x²]/h = (2xh+h²)/h = 2x+h. Taking h → 0 gives f′(x)=2x.",
                    acceptedAnswer: "Expand (x+h)²−x², cancel h, and take the limit to obtain 2x.",
                    explanation: "Expansion exposes the factor h that may be cancelled before the limit is evaluated; direct substitution before simplification would only produce 0/0.",
                    hint: "Expand (x+h)² before dividing by h.",
                    decisiveStep: "Factor h from 2xh+h² before taking h → 0."
                ),
                ConcreteOpenProblem(
                    prompt: "For $$f(x)=|x|,$$ compute the left- and right-hand difference quotients at x = 0 and determine whether f′(0) exists.",
                    correctAnswer: "For h<0, |h|/h = −1; for h>0, |h|/h = 1. The one-sided limits differ, so f′(0) does not exist.",
                    acceptedAnswer: "Left derivative −1 and right derivative 1; therefore |x| is not differentiable at 0.",
                    explanation: "A two-sided derivative exists only when both one-sided difference-quotient limits agree. The cusp makes those limits −1 and 1.",
                    hint: "Evaluate |h|/h separately for negative and positive h.",
                    decisiveStep: "Compare the two one-sided limits."
                ),
                ConcreteOpenProblem(
                    prompt: "Starting from the difference quotient, derive the product rule for differentiable functions f and g by adding and subtracting $$f(x+h)g(x).$$",
                    correctAnswer: "Add and subtract f(x+h)g(x): [(fg)(x+h)−(fg)(x)]/h = f(x+h)[g(x+h)−g(x)]/h + g(x)[f(x+h)−f(x)]/h. Taking h→0 gives (fg)′=fg′+gf′.",
                    acceptedAnswer: "Split the quotient with f(x+h)g(x), then take limits to obtain (fg)'=f g'+g f'.",
                    explanation: "The inserted term separates one product difference into two ordinary difference quotients. Continuity of differentiable f supplies f(x+h)→f(x) in the limit.",
                    hint: "Group one difference in g and one difference in f.",
                    decisiveStep: "Insert f(x+h)g(x) to expose two derivative limits."
                ),
                ConcreteOpenProblem(
                    prompt: "Let x and t be measured in seconds, and let the flow rate be $$r(t)=(1\u{00A0}\\mathrm{L}/\\mathrm{s}^3)t^2.$$ Define $$A(x)=\\int_0^x r(t)\\,dt.$$ Use the Fundamental Theorem of Calculus to derive A′(x), then compute A′(2) and distinguish its units from the accumulated total A(2).",
                    correctAnswer: "The Fundamental Theorem gives A′(x)=r(x). Thus A′(2)=4 L/s, whereas A(2)=∫₀²(1 L/s³)t²dt=8/3 L.",
                    acceptedAnswer: "A'(x)=x²; A'(2)=4 L/s, while A(2)=8/3 L.",
                    explanation: "The coefficient supplies L/s³ and t² supplies s², so r has units L/s. Differentiating accumulation recovers that boundary rate; integrating once over seconds gives the total in litres.",
                    hint: "Distinguish the derivative of the accumulation function from its total value.",
                    decisiveStep: "Check (L/s³)(s²)=L/s, apply d/dx ∫₀ˣr(t)dt=r(x), and distinguish rate from total."
                ),
                ConcreteOpenProblem(
                    prompt: "Apply the Mean Value Theorem to $$f(x)=x^2$$ on [1,3]. Find a value c in (1,3) where f′(c) equals the secant slope, and justify that the theorem applies.",
                    correctAnswer: "The secant slope is (9−1)/(3−1)=4. Since f′(x)=2x, 2c=4 gives c=2. Polynomials are continuous on [1,3] and differentiable on (1,3).",
                    acceptedAnswer: "c=2; x² is continuous on [1,3] and differentiable on (1,3).",
                    explanation: "The theorem’s hypotheses are satisfied, and solving f′(c)=4 locates the interior point whose tangent is parallel to the secant.",
                    hint: "Compute the secant slope before solving f′(c) equal to it.",
                    decisiveStep: "Set 2c = (9−1)/(3−1)."
                ),
                ConcreteOpenProblem(
                    prompt: "Use the Fundamental Theorem of Calculus to evaluate $$\\int_0^2 3x^2\\,dx.$$ State an antiderivative and apply the limits.",
                    correctAnswer: "An antiderivative of 3x² is x³. Therefore ∫₀²3x² dx = [x³]₀² = 8−0 = 8.",
                    acceptedAnswer: "[x³]₀² = 8.",
                    explanation: "The Fundamental Theorem converts the definite integral into the difference of antiderivative values at the upper and lower bounds.",
                    hint: "Differentiate x³ to check the antiderivative.",
                    decisiveStep: "Evaluate x³ at 2 and 0, then subtract."
                )
            ]

        case .linearAlgebra:
            problems = [
                ConcreteOpenProblem(
                    prompt: "Let A be an invertible square matrix. Prove that the only solution of $$Ax=0$$ is x=0, and state the resulting null space.",
                    correctAnswer: "Left-multiply Ax=0 by A⁻¹: A⁻¹Ax=A⁻¹0, so Ix=0 and x=0. Hence null(A)={0}.",
                    acceptedAnswer: "Apply A⁻¹ to obtain x=0, so the null space is trivial.",
                    explanation: "Invertibility supplies an inverse that preserves equality and reduces A⁻¹A to the identity, ruling out every nonzero null vector.",
                    hint: "Use the operation guaranteed by invertibility.",
                    decisiveStep: "Left-multiply both sides by A⁻¹."
                ),
                ConcreteOpenProblem(
                    prompt: "A matrix A has shape 2×3. A student tries to compute Ax with x∈ℝ². Diagnose the dimension error, state the required dimension of x, and state the dimension of Ax.",
                    correctAnswer: "A 2×3 matrix multiplies a 3-component vector, so x must lie in ℝ³; then Ax lies in ℝ². Ax is undefined for x∈ℝ² because the inner dimensions 3 and 2 do not match.",
                    acceptedAnswer: "The product needs x∈R³ and returns a vector in R²; a 2×3 matrix cannot multiply an R² vector.",
                    explanation: "For an m×n matrix, the input has n coordinates and the output has m. Checking dimensions before arithmetic prevents a formally meaningless system from being manipulated.",
                    hint: "Match the matrix’s column count to the vector length.",
                    decisiveStep: "Use the 2×3 map ℝ³→ℝ² to reject the incompatible input."
                ),
                ConcreteOpenProblem(
                    prompt: "For $$A=\\begin{bmatrix}1&2\\\\2&4\\end{bmatrix},$$ show that A is singular by two independent checks: compute det(A) and exhibit a nonzero vector x with Ax=0.",
                    correctAnswer: "det(A)=1·4−2·2=0. Also A(−2,1)ᵀ=(0,0)ᵀ, so A has a nontrivial null vector and is singular.",
                    acceptedAnswer: "det(A)=0 and x=(−2,1) lies in null(A).",
                    explanation: "A zero determinant and a nontrivial null space are equivalent signatures of noninvertibility; here both follow from the dependent rows.",
                    hint: "The second row is twice the first.",
                    decisiveStep: "Pair det(A)=0 with an explicit nonzero null vector."
                ),
                ConcreteOpenProblem(
                    prompt: "A student swaps the two rows of $$A=\\begin{bmatrix}1&2\\\\3&4\\end{bmatrix}$$ but claims the determinant is unchanged. Identify the error and compute both determinants.",
                    correctAnswer: "det(A)=1·4−2·3=−2. One row swap reverses the determinant’s sign, so the swapped matrix has determinant 2, not −2.",
                    acceptedAnswer: "A row swap multiplies the determinant by −1; the values are −2 and 2.",
                    explanation: "Row swapping preserves the solution set of a linear system but does not preserve determinant value; it changes orientation and therefore flips the sign.",
                    hint: "Distinguish row-equivalence from determinant invariance.",
                    decisiveStep: "Apply the determinant sign-change rule for one row swap."
                ),
                ConcreteOpenProblem(
                    prompt: "For $$A=\\begin{bmatrix}2&0\\\\0&3\\end{bmatrix}$$ and v=(1,0)ᵀ, verify directly that v is an eigenvector, find its eigenvalue, and give the geometric meaning of Av=λv.",
                    correctAnswer: "Av=(2,0)ᵀ=2(1,0)ᵀ, so v is an eigenvector with λ=2. Geometrically, A preserves this direction and stretches vectors on it by a factor of 2.",
                    acceptedAnswer: "Av=2v, hence λ=2; the line through v is an invariant direction scaled by 2.",
                    explanation: "An eigenvector identifies a direction that the linear map does not rotate away from itself. Here the x-axis is invariant and its vectors are doubled.",
                    hint: "Multiply A by v and compare componentwise with λv.",
                    decisiveStep: "Show Av=2v and interpret the invariant direction geometrically."
                ),
                ConcreteOpenProblem(
                    prompt: "Find a basis for the null space of $$A=\\begin{bmatrix}1&2&1\\\\0&1&1\\end{bmatrix}$$ and verify your vector by multiplication.",
                    correctAnswer: "From y+z=0, y=−z; then x+2y+z=0 gives x=z. Thus x=z(1,−1,1), so a null-space basis is {(1,−1,1)}; multiplication gives (0,0).",
                    acceptedAnswer: "null(A)=span{(1,−1,1)}.",
                    explanation: "There are two pivot variables and one free variable. Expressing the pivots in terms of z produces one independent null direction.",
                    hint: "Let z be the free variable and solve upward.",
                    decisiveStep: "Parameterize x and y in terms of z."
                )
            ]

        case .mathematicalInduction:
            problems = [
                ConcreteOpenProblem(
                    prompt: "Prove by induction that $$1+2+\\cdots+n=\\frac{n(n+1)}2$$ for every integer n≥1. Show the base case, induction hypothesis, and k→k+1 algebra.",
                    correctAnswer: "At n=1 both sides equal 1. Using the induction hypothesis Sₖ=k(k+1)/2, Sₖ₊₁=Sₖ+(k+1)=k(k+1)/2+(k+1)=(k+1)(k+2)/2.",
                    acceptedAnswer: "Verify n=1; assume the formula for k; add k+1 and factor to obtain (k+1)(k+2)/2.",
                    explanation: "The base case starts the implication chain, and the inductive algebra produces exactly the claimed formula with n replaced by k+1.",
                    hint: "Factor k+1 after applying the induction hypothesis.",
                    decisiveStep: "Rewrite Sₖ₊₁ as Sₖ+(k+1)."
                ),
                ConcreteOpenProblem(
                    prompt: "An 8×8 chessboard has opposite corner squares removed. Prove that the remaining 62 squares cannot be tiled by 31 dominoes, each covering two edge-adjacent squares.",
                    correctAnswer: "Color the board like a chessboard. Every domino covers one black and one white square, but opposite corners have the same color, so removing them leaves 30 squares of that color and 32 of the other. A 31-domino tiling would require 31 of each, impossible.",
                    acceptedAnswer: "A checkerboard-coloring invariant gives unequal color counts, while every domino preserves equal black/white coverage.",
                    explanation: "The coloring is an invariant of every legal domino placement. The global color imbalance rules out all tilings at once, not just attempted arrangements.",
                    hint: "Track a quantity every domino changes in exactly the same way.",
                    decisiveStep: "Use the black–white coverage invariant to contradict the remaining color counts."
                ),
                ConcreteOpenProblem(
                    prompt: "Prove by contradiction that $$\\sqrt{2}$$ is irrational. Begin with √2=a/b in lowest terms and make the parity contradiction explicit.",
                    correctAnswer: "Assume √2=a/b with coprime integers a,b. Then a²=2b², so a is even: a=2k. Substitution gives b²=2k², so b is also even, contradicting that a/b was in lowest terms.",
                    acceptedAnswer: "The assumption forces both numerator and denominator even, contradicting coprimality.",
                    explanation: "Evenness of a² implies evenness of a. Repeating the argument for b creates a common factor 2, which directly negates the reduced-fraction assumption.",
                    hint: "Use the lemma that an integer with an even square is even.",
                    decisiveStep: "Derive that both a and b are even and contradict lowest terms."
                ),
                ConcreteOpenProblem(
                    prompt: "Prove that n² and n have the same parity for every integer n by considering the two cases n=2k and n=2k+1.",
                    correctAnswer: "If n=2k, then n²=4k² is even. If n=2k+1, then n²=4k²+4k+1=2(2k²+2k)+1 is odd. Thus n² has the same parity as n.",
                    acceptedAnswer: "Square the even and odd forms; the first remains even and the second remains odd.",
                    explanation: "Every integer is exactly even or odd, so the two algebraic cases exhaust the domain and establish the claim universally.",
                    hint: "Expand (2k+1)² and factor out 2 from all but the final 1.",
                    decisiveStep: "Use the exhaustive representations 2k and 2k+1."
                ),
                ConcreteOpenProblem(
                    prompt: "A flawed induction ‘proves’ all integers n≥1 satisfy n≥2: it establishes the step k≥2 ⇒ k+1≥2 but never proves n=1. Identify why the proof fails.",
                    correctAnswer: "The base case n=1 is false because 1≥2 is false. A valid inductive step cannot start a chain when the required first statement is not established.",
                    acceptedAnswer: "The induction has no true base case at n=1, so the implication chain never begins.",
                    explanation: "Induction requires both a base proposition and a step from each established case. The step alone proves only a conditional, not any actual instance.",
                    hint: "Evaluate the claimed statement at the first value in its domain.",
                    decisiveStep: "Test and reject the missing base case n=1."
                ),
                ConcreteOpenProblem(
                    prompt: "Seven integers are chosen from {1,2,…,12}. Prove that two chosen integers differ by at most 1.",
                    correctAnswer: "Partition the set into six boxes {1,2},{3,4},…,{11,12}. Placing seven chosen integers into six boxes forces two into the same box by the pigeonhole principle, and those two differ by 1.",
                    acceptedAnswer: "Pair consecutive integers into six boxes; seven choices force one pair to contain two selections.",
                    explanation: "The partition is designed so sharing a box is exactly the desired conclusion. Seven selected objects cannot occupy six boxes with at most one object per box.",
                    hint: "Create six groups whose within-group difference is one.",
                    decisiveStep: "Apply the pigeonhole principle to six consecutive-integer pairs."
                )
            ]

        default:
            return nil
        }
        return openProblem(request, basis: basis, problems[basis.reasoningVariant])
    }

    private static func proof(_ request: NFAuthoringRequest, basis: Basis) -> NFAuthoredQuestion {
        if let equation = sourceEquation(in: basis) {
            let correct = localized("Subtract the right-hand side from both sides to obtain \(equation.zeroForm); applying the same operation to both sides preserves equality.", request: request)
            return makeQuestion(
                request: request,
                basis: basis,
                prompt: localized("The cited equation is\n\n$$\(equation.display)$$\n\nDerive an equivalent zero-form equation by moving the complete right-hand side to the left, and name why the transformation preserves equality.", request: request),
                correctAnswer: correct,
                acceptedAnswers: [
                    localized("\(equation.zeroForm); subtract the right-hand side from both sides", request: request)
                ],
                explanation: localized("Subtracting the same expression from both sides preserves the solution set and yields\n\n$$\(equation.zeroForm)$$", request: request),
                hint: localized("Apply one operation to both sides of the cited equality.", request: request),
                decisiveStep: localized("Subtract the complete right-hand side from both sides.", request: request),
                requiredTermGroups: [
                    "subtract from both sides|same operation to both sides|move the right hand side to the left|両辺から引く|両辺に同じ操作",
                    "= 0|equals zero|zero form|ゼロに等しい|0 の形"
                ],
                minimumRequiredTermMatches: 2,
                rejectedAssertionGroups: [
                    "change one side only|subtract from the left side only|equality need not be preserved|片側だけ"
                ]
            )
        }
        if basis.sourceText == nil {
            if basis.reasoningVariant == 0,
               let semanticQuestion = semanticProof(request, basis: basis) {
                return semanticQuestion
            }
            if basis.reasoningVariant == 0,
               semanticTopic(request, basis: basis) == .logicalImplication {
                // Preserve one explicit formal-inference slot in a logical
                // proof set; the other five slots exercise distinct proof
                // roles through the concept profile below.
            } else {
                return conceptProof(request, basis: basis)
            }
        }
        if basis.sourceSentence == nil,
           request.field == .chemistry,
           topicSuggestsStoichiometry(basis.topic) {
            let aMoles = basis.a * 2
            let bMoles = basis.b
            let extent = min(aMoles / 2, bMoles)
            let correct = localized("The reaction extent is min(nA/2, nB), so product C is 2 × min(nA/2, nB) = \(extent * 2) mol.", request: request)
            return makeQuestion(
                request: request,
                basis: basis,
                prompt: localized("For\n\n$$2A + B \\rightarrow 2C$$\n\nwith \(aMoles) mol A and \(bMoles) mol B, derive the maximum amount of C. Compare both stoichiometric extents before choosing the limiting reagent.", request: request),
                correctAnswer: correct,
                acceptedAnswers: [
                    localized("min(nA/2, nB) = \(extent); C = \(extent * 2) mol", request: request)
                ],
                explanation: localized("Each possible reaction extent is available moles divided by its coefficient. The smaller extent is feasible for both reactants and therefore determines product yield.", request: request),
                hint: localized("Compare\n\n$$\\frac{n_A}{2} \\quad \\text{and} \\quad \\frac{n_B}{1}$$\n\nbefore calculating product.", request: request),
                decisiveStep: localized("Use the smaller coefficient-adjusted reactant extent.", request: request),
                requiredTermGroups: [
                    "min|smaller|minimum|limiting|最小|少ない|限界",
                    "nA/2|a/2|coefficient|係数",
                    "\(extent * 2)|product|c =|生成物"
                ],
                minimumRequiredTermMatches: 3,
                rejectedAssertionGroups: [
                    "use the maximum extent|choose the larger extent|max determines yield|最大を使う|大きい方を選ぶ"
                ]
            )
        }
        if let semanticQuestion = semanticProof(request, basis: basis) {
            return semanticQuestion
        }
        let premise = basis.sourceSentence.map {
            localized("Let P mean: “\($0)”", request: request)
        } ?? localized("Let P mean that the \(basis.topic.lowercased()) input passed validation.", request: request)
        let correct = localized("R follows by modus ponens.", request: request)
        return makeQuestion(
            request: request,
            basis: basis,
            prompt: localized("\(premise) You are also given P → R, where R means the item enters the review set, and P is true. Derive whether R follows and name the inference rule.", request: request),
            correctAnswer: correct,
            acceptedAnswers: [
                localized("R; modus ponens", request: request),
                localized("R follows because P and P → R are given.", request: request)
            ],
            explanation: localized("The two explicit premises are P and P → R, so R follows by modus ponens. No converse or source-truth claim is needed.", request: request),
            hint: localized("Match the premises to a standard implication-elimination rule.", request: request),
            decisiveStep: localized("Apply modus ponens to P and P → R.", request: request),
            requiredTermGroups: [
                "modus ponens|mp|前件肯定",
                "r follows|derive r|therefore r|r is true|r が導か|r は真"
            ],
            minimumRequiredTermMatches: 2,
            rejectedAssertionGroups: [
                "r does not follow|cannot derive r|modus ponens does not apply|r は導かれない"
            ]
        )
    }

    private static func semanticProof(
        _ request: NFAuthoringRequest,
        basis: Basis
    ) -> NFAuthoredQuestion? {
        guard basis.sourceSentence == nil else { return nil }

        switch semanticTopic(request, basis: basis) {
        case .dijkstraShortestPaths:
            let correct = localized("Let u be the non-stale minimum-key unfinalized vertex. If a shorter source-to-u path existed, its first edge leaving the finalized set would reach a frontier vertex with a key smaller than distance[u], because all remaining edge weights are nonnegative. That contradicts u being the minimum, so distance[u] is final.", request: request)
            return makeQuestion(
                request: request,
                basis: basis,
                prompt: localized("Prove Dijkstra’s finalization step. Assume every edge weight is nonnegative and u is removed from the priority queue with its current minimum tentative distance. Show that no shorter source-to-u path can exist.", request: request),
                correctAnswer: correct,
                acceptedAnswers: [
                    localized("A shorter path would cross the finalized frontier at a vertex with a smaller tentative key, contradicting the minimum choice of u; nonnegative weights preserve the bound.", request: request)
                ],
                explanation: localized("The decisive invariant is that every finalized distance is exact and every tentative key is the best discovered frontier path. On a hypothetical shorter path to u, the first unfinalized vertex would already have a key no greater than that path’s length, hence smaller than u’s key—a contradiction.", request: request),
                hint: localized("Take the first unfinalized vertex on a hypothetical shorter path to u.", request: request),
                decisiveStep: localized("Contradict the minimum-key choice at the finalized frontier.", request: request),
                requiredTermGroups: [
                    "minimum key|minimum tentative|smallest key|priority queue|最小キー|優先度付きキュー",
                    "first unfinalized|frontier|leaving the finalized|未確定|境界",
                    "nonnegative|non-negative|negative weights are excluded|非負",
                    "contradict|contradiction|cannot be shorter|矛盾"
                ],
                minimumRequiredTermMatches: 3,
                rejectedAssertionGroups: [
                    "negative edges are allowed|minimum choice is unnecessary|finalized distance can later decrease|負の辺を許す"
                ]
            )

        case .mathematicalInduction:
            let correct = localized("Base case: S₁ = 1 = 1(1 + 1)/2. Assume Sₖ = k(k + 1)/2. Then Sₖ₊₁ = Sₖ + (k + 1) = k(k + 1)/2 + (k + 1) = (k + 1)(k + 2)/2, which is the claimed formula with k replaced by k + 1.", request: request)
            return makeQuestion(
                request: request,
                basis: basis,
                prompt: localized("Prove by mathematical induction that\n\n$$1 + 2 + \\cdots + n = \\frac{n(n + 1)}{2}$$\n\nfor every integer n ≥ 1. State the base case, induction hypothesis, and algebraic step for k + 1.", request: request),
                correctAnswer: correct,
                acceptedAnswers: [
                    localized("Verify n = 1; assume the formula for k; add k + 1 and factor to obtain (k + 1)(k + 2)/2.", request: request)
                ],
                explanation: localized("The base case initiates the chain. The induction hypothesis substitutes a known expression for Sₖ, and factoring after adding k + 1 produces exactly the target expression for Sₖ₊₁.", request: request),
                hint: localized("After applying the induction hypothesis, factor out k + 1.", request: request),
                decisiveStep: localized("Rewrite Sₖ₊₁ as Sₖ + (k + 1), substitute the hypothesis, and factor.", request: request),
                requiredTermGroups: [
                    "base case|n = 1|n=1|基底",
                    "assume|induction hypothesis|sₖ|sk|仮定|帰納法の仮定",
                    "add k + 1|sₖ₊₁|sk+1|k+1 を加",
                    "(k + 1)(k + 2)/2|(k+1)(k+2)/2|factor|因数分解"
                ],
                minimumRequiredTermMatches: 3
            )

        case .calculus:
            let correct = localized("For h ≠ 0, [f(x + h) − f(x)]/h = [(x + h)² − x²]/h = (2xh + h²)/h = 2x + h. Taking h → 0 gives f′(x) = 2x.", request: request)
            return makeQuestion(
                request: request,
                basis: basis,
                prompt: localized("Using only the limit definition\n\n$$f'(x)=\\lim_{h\\to0}\\frac{f(x+h)-f(x)}{h},$$\n\nderive the derivative of $$f(x)=x^2$$. Show the cancellation that makes the limit finite.", request: request),
                correctAnswer: correct,
                acceptedAnswers: [
                    localized("Expand (x + h)² − x² = 2xh + h², divide by h, then take the limit to obtain 2x.", request: request)
                ],
                explanation: localized("Expanding first exposes a common factor h. Cancelling that factor is valid for h ≠ 0 in the difference quotient, after which the limit of 2x + h is 2x.", request: request),
                hint: localized("Expand (x + h)² before taking the limit.", request: request),
                decisiveStep: localized("Factor and cancel h before evaluating h → 0.", request: request),
                requiredTermGroups: [
                    "2xh + h²|2xh+h²|expand|展開",
                    "cancel h|divide by h|h ≠ 0|h を約分|h で割",
                    "2x + h|2x+h",
                    "2x|h → 0|limit|極限"
                ],
                minimumRequiredTermMatches: 3
            )

        case .linearAlgebra:
            let correct = localized("Because A is invertible, multiply Ax = 0 by A⁻¹ on the left: A⁻¹Ax = A⁻¹0, hence Ix = 0 and x = 0. Therefore the null space is trivial.", request: request)
            return makeQuestion(
                request: request,
                basis: basis,
                prompt: localized("Let A be an invertible square matrix. Prove that the only solution of\n\n$$Ax=0$$\n\nis x = 0, and identify the resulting statement about the null space of A.", request: request),
                correctAnswer: correct,
                acceptedAnswers: [
                    localized("Left-multiply by A⁻¹ to get x = 0, so null(A) = {0}.", request: request)
                ],
                explanation: localized("Invertibility provides a two-sided inverse. Applying the inverse preserves equality and reduces A⁻¹A to the identity matrix.", request: request),
                hint: localized("Use the operation guaranteed by invertibility.", request: request),
                decisiveStep: localized("Left-multiply both sides by A⁻¹.", request: request),
                requiredTermGroups: [
                    "a⁻¹|inverse|invertible|逆行列",
                    "left multiply|multiply both sides|両辺|左から掛",
                    "x = 0|x=0|null space is trivial|null(a) = {0}|零空間"
                ],
                minimumRequiredTermMatches: 3
            )

        case .classicalMechanics:
            let correct = localized("From v = v₀ + at, write t = (v − v₀)/a. Substitute into Δx = (v + v₀)t/2 to obtain Δx = (v² − v₀²)/(2a), hence v² = v₀² + 2aΔx.", request: request)
            return makeQuestion(
                request: request,
                basis: basis,
                prompt: localized("For one-dimensional motion with constant acceleration, derive\n\n$$v^2=v_0^2+2a\\Delta x$$\n\nfrom $$v=v_0+at$$ and $$\\Delta x=\\frac{v+v_0}{2}t$$ by eliminating time.", request: request),
                correctAnswer: correct,
                acceptedAnswers: [
                    localized("Use t = (v − v₀)/a in the average-velocity displacement equation, then rearrange to v² = v₀² + 2aΔx.", request: request)
                ],
                explanation: localized("Solving the velocity relation for time and substituting into displacement gives a difference of squares, (v − v₀)(v + v₀) = v² − v₀².", request: request),
                hint: localized("First isolate t in the velocity equation.", request: request),
                decisiveStep: localized("Substitute t = (v − v₀)/a and use the difference of squares.", request: request),
                requiredTermGroups: [
                    "t = (v − v₀)/a|t = (v-v0)/a|isolate time|時間を消去",
                    "substitut|代入",
                    "difference of squares|v² − v₀²|v^2 - v0^2|平方差",
                    "v² = v₀² + 2aδx|v^2 = v0^2 + 2a|2aδx"
                ],
                minimumRequiredTermMatches: 3
            )

        default:
            return nil
        }
    }

    private static func conceptDebugging(
        _ request: NFAuthoringRequest,
        basis: Basis
    ) -> NFAuthoredQuestion {
        let profile = topicConceptProfile(request, basis: basis)
        let variant = basis.reasoningVariant
        let faultyMoves: [String.LocalizationValue] = [
            "The work reports a final result but never states or checks the governing invariant.",
            "The main rule is applied before its prerequisite is verified.",
            "Only a typical interior example is tested, and the result is declared universally correct.",
            "A plausible output is accepted even though the topic’s characteristic diagnostic fails.",
            "A limited comparison is rewritten as a universal or causal conclusion.",
            "A method is copied into a new setting by renaming objects, without mapping its relations or assumptions."
        ]
        let requestedRepairs: [String.LocalizationValue] = [
            "Restore the invariant and state where it must be checked.",
            "Insert the missing precondition check before the rule is used.",
            "Add the boundary or falsification test that can expose the failure.",
            "Use the diagnostic to identify the first invalid step, not merely the final symptom.",
            "Narrow the conclusion to what the evidence supports.",
            "Require an explicit structural mapping before transfer."
        ]
        let faultyMove = localized(faultyMoves[variant], request: request)
        let answer = profile.facets[variant] + " " + localized(requestedRepairs[variant], request: request)
        return makeQuestion(
            request: request,
            basis: basis,
            prompt: localized("Debug this \(topicWithoutTrailingQualifier(basis.topic.lowercased(), qualifier: "reasoning")) reasoning:\n\n“\(faultyMove)”\n\nIdentify the first unsupported move and give the smallest topic-valid repair.", request: request),
            correctAnswer: answer,
            acceptedAnswers: [profile.facets[variant]],
            explanation: answer,
            hint: localized("Classify the failure as invariant, prerequisite, boundary, diagnostic, interpretation, or transfer before repairing it.", request: request),
            decisiveStep: localized(requestedRepairs[variant], request: request)
        )
    }

    private struct ConcreteDebugProblem {
        let code: String.LocalizationValue
        let expected: String.LocalizationValue
        let correctAnswer: String.LocalizationValue
        let acceptedAnswer: String.LocalizationValue
        let explanation: String.LocalizationValue
        let hint: String.LocalizationValue
        let decisiveStep: String.LocalizationValue
    }

    private static func semanticStarterDebugging(
        _ request: NFAuthoringRequest,
        basis: Basis
    ) -> NFAuthoredQuestion? {
        func d(
            _ code: String.LocalizationValue,
            _ expected: String.LocalizationValue,
            _ answer: String.LocalizationValue,
            _ accepted: String.LocalizationValue,
            _ explanation: String.LocalizationValue,
            _ hint: String.LocalizationValue,
            _ step: String.LocalizationValue
        ) -> ConcreteDebugProblem {
            ConcreteDebugProblem(
                code: code,
                expected: expected,
                correctAnswer: answer,
                acceptedAnswer: accepted,
                explanation: explanation,
                hint: hint,
                decisiveStep: step
            )
        }

        if semanticTopic(request, basis: basis) == .dijkstraShortestPaths {
            let sixthSlot = (Int(request.seed % 6) + 5) % 6
            guard basis.reasoningVariant == sixthSlot else { return nil }
            let problem = d(
                "func visit(_ u: Vertex) {\n  for v in neighbors[u] {\n    visit(v)\n  }\n  visited.insert(u)\n}\n// directed edges: a→b, b→c, c→a",
                "Traverse the cyclic graph and terminate after processing each vertex once.",
                "Mark u visited before recursing and skip any neighbor already visited; otherwise a→b→c→a recurses forever before any vertex is recorded.",
                "Record a vertex on entry, then recurse only to unvisited neighbors.",
                "The back edge c→a is reached while a is still absent from visited because insertion occurs after recursion. Entry-time marking establishes the cycle-handling invariant that each vertex is scheduled once.",
                "Trace when a first becomes marked along a→b→c→a.",
                "Move visited insertion before neighbor recursion and guard already-visited vertices."
            )
            return makeQuestion(
                request: request,
                basis: basis,
                prompt: localized("Debug this case involving \(basis.topic.lowercased()):\n```\n\(localized(problem.code, request: request))\n```\nRequired behavior: \(localized(problem.expected, request: request)) Identify the first faulty operation and give the smallest correction.", request: request),
                correctAnswer: localized(problem.correctAnswer, request: request),
                acceptedAnswers: [localized(problem.acceptedAnswer, request: request)],
                explanation: localized(problem.explanation, request: request),
                hint: localized(problem.hint, request: request),
                decisiveStep: localized(problem.decisiveStep, request: request)
            )
        }

        let problems: [ConcreteDebugProblem]
        switch semanticTopic(request, basis: basis) {
        case .algorithmAnalysis:
            problems = [
                d("func sum(_ values: [Int]) -> Int { var total = 0; for v in values { total += v }; return total }\n// Claim: O(1)", "Time grows linearly with values.count.", "Change the complexity claim to O(n); the loop visits every one of n elements once.", "O(n), not O(1).", "The accumulator uses constant extra space, but runtime counts loop iterations. Conflating space with time creates the incorrect O(1) claim.", "Count how many times the loop body executes.", "Distinguish O(n) time from O(1) auxiliary space."),
                d("for i in 0..<n { for j in 0..<n { work(i,j) } }\n// Claim: O(n)", "The work call executes n² times.", "Change the time bound to O(n²); each of n outer iterations performs n inner iterations.", "O(n²).", "Independent nested loops multiply their iteration counts, giving n×n operations rather than adding to n.", "Evaluate the number of (i,j) pairs.", "Multiply the nested loop bounds."),
                d("var k = 1\nwhile k < n { k *= 2 }\n// Claim: O(n)", "The loop stops after doubling k about log₂n times.", "Change the time bound to O(log n); multiplicative growth reaches n after about log₂n doublings.", "O(log n).", "A loop counter multiplied by a constant does not visit every integer. After t iterations k=2ᵗ, so t≈log₂n.", "Write k after t iterations.", "Solve 2ᵗ≥n."),
                d("func f(_ n:Int)->Int { if n<=1{return 1}; return f(n-1)+f(n-1) }\n// Claim: O(n)", "The recursion tree doubles at each level.", "The naive recurrence is exponential, O(2ⁿ), because every non-base call makes two calls of size n−1.", "O(2ⁿ), not O(n).", "The two identical recursive calls are recomputed rather than shared. A depth-n binary recursion tree has exponentially many nodes.", "Draw the first three recursion levels.", "Count branching factor two across depth n."),
                d("func contains(_ values:[Int], _ target:Int)->Bool { for v in values { if v==target{return true} }; return false }\n// Benchmark only places target first.", "Measure worst-case and absent-target behavior too.", "Add target-last and target-absent cases; the first-position benchmark exercises one comparison and cannot support the general runtime claim.", "Benchmark target last and absent.", "Linear search can exit immediately for the chosen case but may inspect all n elements. Input placement is part of the complexity scenario.", "Move the target to the opposite boundary.", "Test the n-comparison path, not only the one-comparison path."),
                d("// Array indices satisfy 0 <= low <= high <= Int.max\nlet mid = (low + high) / 2", "Compute a midpoint without overflowing nonnegative array-index bounds.", "Under the stated nonnegative-index invariant, use low + (high−low)/2; low+high can overflow even when both indices are valid.", "Replace (low+high)/2 with low+(high-low)/2 for these nonnegative bounds.", "With 0≤low≤high, high−low is representable and adding at most that span back to low stays at or below high; low+high can overflow before division.", "Use the stated ordered nonnegative-index invariant.", "Reassociate the midpoint calculation under 0≤low≤high.")
            ]

        case .programBoundaries:
            problems = [
                d("let count = values.count\nvar index = 0\nwhile index <= count { visit(values[index]); index += 1 }", "Visit each of count elements without indexing past the end.", "Change index <= count to index < count; valid zero-based indices end at count−1.", "Use index < count.", "When index equals count, the condition still passes but values[count] is one past the final element. The explicit count declaration makes the failing boundary testable.", "Write the valid index interval [0,count).", "Exclude index==count from the loop."),
                d("func first(_ values:[Int])->Int { values[0] }", "Handle an empty array without trapping.", "Check values.isEmpty before reading index 0 and return an optional or declared empty-case result.", "Guard !values.isEmpty before values[0].", "Index 0 exists only when count≥1. The function contract currently permits an input for which its first operation is invalid.", "Test values=[] before a typical array.", "Establish a nonempty precondition or represent absence."),
                d("for i in values.indices { if values[i] < 0 { values.remove(at: i) } }", "Remove every negative value without invalidating an index that the loop will later reuse.", "Do not mutate indexed storage while iterating its original indices; filter into a new array or traverse valid removal indices in reverse.", "Use values = values.filter { $0 >= 0 } or remove in reverse index order.", "Removing an element shifts later indices left while the loop still follows the old index sequence, so it can skip values or access an index that no longer exists.", "Trace the indices after removing the first element.", "Separate traversal from mutation or traverse removal indices in reverse."),
                d("var i = 0\nwhile i < values.count { if values[i] < 0 { continue }; total += values[i]; i += 1 }", "Advance past negative values and terminate.", "Increment i before continue, or use a for loop; the negative branch repeats the same index forever.", "Advance i on every path.", "continue skips the only increment. A negative element therefore preserves the loop state and violates progress toward termination.", "Trace i when values[0] is negative.", "Preserve the loop progress invariant on the continue branch."),
                d("func clamp(_ x:Int, low:Int, high:Int)->Int { min(low, max(high, x)) }", "Return low for x<low, high for x>high, and x inside [low,high].", "Use min(high, max(low, x)); the current low/high positions are reversed.", "Return min(high,max(low,x)).", "The inner max must raise values to the lower bound; the outer min must lower them to the upper bound. Reversing them collapses results incorrectly.", "Test x midway between low and high.", "Apply lower bound first and upper bound second."),
                d("let score = scores[id]!", "Represent a missing dictionary key without trapping.", "Use guard let score = scores[id] else { handleMissingID() } or a documented default; forced unwrap assumes every requested key exists.", "Use optional binding for scores[id].", "Dictionary lookup returns an optional because a syntactically valid ID can still be absent. Force-unwrapping turns that normal boundary state into a crash.", "Test an ID not present in scores.", "Make the missing-key branch explicit in the function contract." )
            ]

        case .concurrency:
            problems = [
                d("// shared counter starts at 0\nparallelRepeat(1000) { counter = counter + 1 }", "Finish with counter=1000 under every interleaving.", "Protect the read-modify-write with a lock/atomic increment or isolate counter on one executor; the current increments race and lose updates.", "Use an atomic increment or lock.", "Two tasks can read the same old value and both write the same successor, so completed operations do not correspond one-to-one with counter changes.", "Expand counter=counter+1 into read, add, and write.", "Make the complete read-modify-write atomic."),
                d("lockA.lock(); lockB.lock(); work(); lockB.unlock(); lockA.unlock()\n// another task locks B then A", "Prevent circular wait between the two tasks.", "Use one global lock order, such as always acquiring A before B, or combine the protected state under one lock.", "Acquire locks in the same order everywhere.", "Opposite acquisition orders allow each task to hold one lock while waiting forever for the other, satisfying circular wait.", "Trace the interleaving where each task acquires its first lock.", "Eliminate the inconsistent lock-order cycle."),
                d("if !processed.contains(id) { chargeCard(idempotencyKey: id); processed.insert(id) }\n// duplicate delivery and crash/retry are possible", "Apply one durable logical charge despite concurrency and a crash between local state changes.", "Use the same provider idempotency key for the charge and a durable outbox/state record committed transactionally; retry delivery until the provider confirms that key exactly once.", "Use a provider idempotency key plus a durable outbox.", "A local claim before the external call can lose a charge after a crash, while recording only afterward can duplicate it. A durable outbox plus provider deduplication closes both windows.", "Trace crashes immediately before and after the provider call.", "Combine durable intent with external idempotency for crash-safe retry."),
                d("taskA { state.user = loadUser() }\ntaskB { state.user = nil }", "Produce a declared deterministic final state in which the load completes before the reset.", "Create an explicit happens-before order: await the load task, then perform the reset on the state owner. Actor isolation alone serializes access but does not choose which write happens last.", "Await taskA, then reset state.user on its actor.", "With no ordering edge, either assignment may be last even if an actor removes the data race. The contract requires sequencing, not merely mutual exclusion.", "Ask which operation is declared to happen last.", "Establish load-before-reset ordering on the state owner."),
                d("producer { queue.append(item) }\nconsumer { item = queue.removeFirst() }\n// plain mutable array", "Transfer items safely between concurrent producer and consumer.", "Use a synchronized channel/queue or protect all array access and handle the empty state; plain concurrent mutation is unsafe.", "Use a thread-safe channel.", "append and removeFirst mutate shared array storage, and the consumer can also run before an item exists. Both memory safety and protocol state need synchronization.", "Consider consumer-first and simultaneous mutation schedules.", "Replace shared mutable array access with a synchronized handoff."),
                d("update balance set amount = amount - 10 where account = 7\n// retry after timeout", "A network retry must not subtract twice for one logical request.", "Attach a unique operation ID and commit the balance change with an idempotency record in one transaction.", "Use a transactional idempotency key.", "A timeout does not tell the client whether the first write committed. Blind retry repeats the non-idempotent subtraction.", "Distinguish no response from no commit.", "Deduplicate the logical operation at the storage boundary." )
            ]

        case .thermochemistry:
            problems = [
                d("deltaH = productsH + reactantsH", "Compute reaction enthalpy as products minus reactants.", "Replace addition with ΔH=ΣH_products−ΣH_reactants.", "Use products minus reactants.", "Reaction enthalpy is a final-minus-initial state-function difference. Addition loses direction and cannot distinguish exothermic from endothermic change.", "Label final and initial enthalpy states.", "Preserve the products-minus-reactants sign."),
                d("q = mass * heatCapacity / deltaT", "For constant specific heat, q=mcΔT.", "Multiply by ΔT rather than divide: q=mass×heatCapacity×deltaT.", "Use q=mcΔT.", "Specific heat has units J/(mass·temperature); multiplying by mass and temperature change leaves joules, while division leaves incompatible units.", "Audit the units of heat capacity.", "Use dimensional consistency to place ΔT in the numerator."),
                d("deltaG = deltaH + temperature * deltaS", "Use ΔG=ΔH−TΔS with consistent units.", "Change plus to minus and convert entropy units if needed: ΔG=ΔH−TΔS.", "Use ΔH−TΔS.", "The entropy contribution is subtracted in Gibbs energy. A sign error can reverse the predicted spontaneity.", "Write the defining Gibbs relation before substitution.", "Restore the minus sign on TΔS."),
                d("deltaHInKJ = -40\ntemperatureInK = 300\ndeltaSInJPerK = -100\ndeltaGInKJ = deltaHInKJ - temperatureInK * deltaSInJPerK", "Compute ΔG in kJ with both additive terms in the same unit.", "Convert ΔS to −0.100 kJ/K, then compute ΔG=−40−300(−0.100)=−10 kJ.", "Convert ΔS to kJ/K; ΔG is −10 kJ.", "Without conversion, TΔS is −30,000 J while ΔH is −40 kJ. Converting first gives the dimensionally consistent result −10 kJ.", "Convert −100 J/K to kJ/K before substitution.", "Evaluate ΔG only after converting ΔS to kJ/K."),
                d("// Hess paths\nA_to_B = 40\nB_to_C = -15\nA_to_C = A_to_B - B_to_C", "State-function path A→C should equal the signed sum of steps.", "Use A_to_C=A_to_B+B_to_C=25, not 40−(−15)=55.", "Add signed step enthalpies to get 25.", "The −15 already carries its direction. Subtracting it a second time reverses that step and breaks path independence.", "Treat each listed ΔH as a signed quantity.", "Sum the signed Hess-law steps once."),
                d("if deltaH < 0 { spontaneous = true }", "Determine spontaneity from ΔG at the stated temperature, not from exothermicity alone.", "Compute ΔG=ΔH−TΔS and require ΔG<0; a negative ΔH alone is insufficient because the entropy term and temperature can reverse the sign.", "Use ΔG<0 after evaluating ΔH−TΔS.", "Exothermic describes enthalpy direction, whereas spontaneity at fixed temperature and pressure is governed by Gibbs energy. Conflating them discards TΔS.", "Ask which thermodynamic potential supplies the spontaneity criterion.", "Reject exothermic⇒spontaneous and evaluate the full Gibbs relation." )
            ]

        case .cellRegulation:
            problems = [
                d("receptorActive = ligandPresent || receptorBlocked", "A blocked receptor must not activate from ligand binding.", "Use ligandPresent && !receptorBlocked; the OR expression treats blockade as an activation signal.", "Require ligand and no blockade.", "Activation needs the ligand prerequisite and an available receptor. OR makes either condition sufficient, reversing the inhibitor’s role.", "Evaluate ligand=false, blocked=true.", "Represent blockade as a negated prerequisite."),
                d("if signalHigh { inhibitor = 0 }", "Negative feedback should increase inhibition when signal is high.", "Increase or activate the inhibitor when signalHigh; setting it to zero removes negative feedback.", "High signal should activate its inhibitor.", "Negative feedback opposes the initiating change. Removing inhibition at high signal instead creates reinforcing positive feedback.", "Ask whether the response opposes or amplifies high signal.", "Restore the inhibitory response to high signal."),
                d("mrna = transcriptionRate * degradationRate", "At steady state for production−degradation×mRNA=0, mRNA=production/degradation.", "Divide transcriptionRate by degradationRate; multiplying predicts more mRNA when degradation becomes faster.", "Use production/degradation.", "The steady-state balance is production=degradationRate×mRNA. Solving for the stock places degradation in the denominator.", "Write the production-loss balance first.", "Solve the steady-state equation for mRNA."),
                d("geneOn = activatorPresent && repressorPresent", "A simple repressor blocks expression when present.", "Use activatorPresent && !repressorPresent.", "Require activator and absence of repressor.", "The code gives the repressor the same polarity as an activator. Testing activator=true, repressor=true exposes the wrong state.", "Translate each regulator’s sign separately.", "Negate the repressor condition."),
                d("response = dose / (EC50 - dose)", "A bounded Hill-1 response is dose/(EC50+dose).", "Replace the minus with plus; the current denominator reaches zero at dose=EC50 and becomes negative above it.", "Use dose/(EC50+dose).", "The intended saturation curve stays between zero and one. A subtractive denominator creates a singularity and nonphysical negative responses.", "Test dose=EC50 and very large dose.", "Use boundary behavior to restore the saturating denominator."),
                d("protein = mrna\n// reported after translation inhibitor", "Distinguish transcript abundance from protein production.", "Do not equate mRNA with protein; model translation rate and degradation, especially when translation is inhibited.", "Track mRNA and protein as separate state variables.", "A translation inhibitor can leave mRNA unchanged while reducing protein. Copying one measurement into the other skips the causal step being perturbed.", "Name the process between transcript and protein.", "Preserve the translation relation between distinct quantities." )
            ]

        case .validationLeakage:
            problems = [
                d("scaled = scaler.fitTransform(allRows)\ntrain,test = split(scaled)", "Keep test rows untouched by learned preprocessing.", "Split first, fit the scaler on training rows only, and transform test rows with those training parameters.", "Fit preprocessing after the split on train only.", "The all-row mean and variance encode the held-out distribution in model inputs, so evaluation is no longer independent.", "Ask which rows determine scaler parameters.", "Learn every transform without test information."),
                d("trainRows = randomRows(events)\ntestRows = remainingRows(events)\n// same patient appears repeatedly", "Estimate performance on new patients.", "Split by patient ID, not by event row, so one person cannot appear in both train and test.", "Group the split by patient.", "Repeated rows from one patient share stable signals; row splitting lets the model recognize entities rather than generalize to unseen patients.", "Match the split unit to the deployment unit.", "Keep each patient wholly in one partition."),
                d("features.include(outcomeRecordedAt + 1day)", "Use only information available at prediction time.", "Remove the post-outcome feature or shift the prediction timestamp; it leaks future target information.", "Remove features recorded after the target event.", "A highly predictive future-derived value is unavailable when a real prediction must be made and therefore creates target leakage.", "Draw a timeline for feature and outcome timestamps.", "Enforce temporal availability at inference time."),
                d("for config in 1...200 { score = evaluate(config,test); keepBest(score) }", "Reserve an untouched final test after model selection.", "Use validation data for configuration choice and evaluate once on a separate test set.", "Do not tune on the test set.", "Repeated selection chooses configurations partly for test-set noise, turning the test into training feedback and biasing the reported maximum.", "Ask whether test results change the model.", "Separate tuning evidence from final evaluation."),
                d("train = records before 2025 shuffled with records after 2025\ntest = random 20%", "Estimate future-time performance.", "Use a chronological split: train on earlier records and test on later records.", "Hold out future records by time.", "A random split allows future patterns and entities into training, which does not match the prospective deployment question.", "Match evaluation order to the prediction timeline.", "Preserve temporal separation."),
                d("trainSites = [hospitalA, hospitalB]\ntest = randomRows(trainSites)\n// deployment will be hospitalC with different devices and referral mix", "Estimate generalization to an unseen hospital rather than another row from the development sites.", "Reserve hospitalC or another external site as a site-level test cohort, and report calibration plus performance by site; a random row split cannot measure cross-site shift.", "Evaluate on an untouched external hospital cohort.", "Rows within the same hospitals share device, workflow, and referral patterns. Random row holdout preserves those shortcuts, while site-level holdout tests the stated deployment boundary.", "Match the split unit to the new-site deployment claim.", "Use external/site-held-out validation and audit calibration under distribution shift." )
            ]

        case .dataPipelines:
            problems = [
                d("rows = parse(file)\nrows = rows.filter(valid)\nreportCount = parse(file).count", "Report the count of validated rows used downstream.", "Use rows.count after filtering; reparsing the raw file counts invalid rows again.", "Report the transformed row count.", "The variable rows holds the actual pipeline state. Reading raw input again bypasses the validation transformation and makes the metric irreproducible.", "Trace which collection enters the next stage.", "Measure the post-filter state, not the raw source."),
                d("features = oneHotEncode(allData.category)\ntrain,test = split(features)", "Prevent test-only categories from shaping the training feature schema.", "Split first, fit the encoder vocabulary on training data, then transform test data with an unknown-category policy.", "Fit encoding on training rows only.", "The all-data category vocabulary is learned from held-out rows. It leaks schema information and can make evaluation-time feature space unrealistically complete.", "Ask which data determines feature columns.", "Learn the feature schema inside the training partition."),
                d("join users on email\n// email is not unique", "Produce at most one user match per event.", "Join on a stable unique user ID or deduplicate with an explicit rule; email can duplicate rows in a many-to-many join.", "Use a unique join key.", "A nonunique key multiplies records and silently changes counts and weights downstream, even if every field value looks valid.", "Compare row counts before and after the join.", "Enforce join cardinality with a unique key."),
                d("seed = currentTime()\nshuffle(rows,seed)\nsave(metrics)", "Reproduce the same split and metric later.", "Use and record a fixed/configured seed together with code, data version, and split assignment.", "Persist the random seed and split.", "A time-derived seed changes row allocation on each run. Saving only final metrics omits the state required to reproduce them.", "List every random choice that affects the result.", "Persist the randomness contract, not just output."),
                d("schema.age = String\nmodelInput.age = toNumber(age) // failures become 0", "Distinguish invalid ages from real zero ages.", "Validate/parse age explicitly and quarantine or represent failures as missing; silently converting failure to 0 corrupts the feature.", "Do not map parse failure to a valid zero.", "Zero is a meaningful value, so using it as an error sentinel merges two different states and hides data-quality failures.", "Ask whether the fallback value is valid domain data.", "Represent parse failure separately from numeric zero."),
                d("daily = events.groupBy(localCalendarDay)\n// deployment compares UTC days", "Produce the same daily boundaries in training and deployment.", "Declare and use one timezone/day-boundary rule end-to-end, such as UTC, and test events around midnight.", "Use a consistent explicit timezone.", "Different day boundaries assign the same event to different feature windows, creating train/serve skew that appears only near boundary times.", "Test timestamps just before and after midnight in both zones.", "Make temporal bucketing semantics identical across pipeline stages." )
            ]

        default:
            return nil
        }

        let problem = problems[basis.reasoningVariant]
        return makeQuestion(
            request: request,
            basis: basis,
            prompt: localized("Debug this case involving \(basis.topic.lowercased()):\n```\n\(localized(problem.code, request: request))\n```\nRequired behavior: \(localized(problem.expected, request: request)) Identify the first faulty operation and give the smallest correction.", request: request),
            correctAnswer: localized(problem.correctAnswer, request: request),
            acceptedAnswers: [localized(problem.acceptedAnswer, request: request)],
            explanation: localized(problem.explanation, request: request),
            hint: localized(problem.hint, request: request),
            decisiveStep: localized(problem.decisiveStep, request: request)
        )
    }

    private static func debugging(_ request: NFAuthoringRequest, basis: Basis) -> NFAuthoredQuestion {
        if let sourceQuestion = sourceDebuggingQuestion(request, basis: basis) {
            return sourceQuestion
        }
        if let sourceSentence = basis.sourceSentence {
            let correct = localized("The conclusion negates and overgeneralizes the premise; retain the cited claim with its original qualifiers.", request: request)
            return makeQuestion(
                request: request,
                basis: basis,
                prompt: localized("A reviewer starts from the cited claim “\(sourceSentence)” and concludes, ‘Therefore the opposite is true in every case.’ Identify the first invalid reasoning step and state the smallest sound correction.", request: request),
                correctAnswer: correct,
                acceptedAnswers: [
                    localized("Unsupported negation and universalization", request: request),
                    localized("Keep the source claim and its qualifiers", request: request)
                ],
                explanation: localized("Neither negation nor universal scope follows from the cited sentence. The smallest correction is to preserve the original direction and qualifiers.", request: request),
                hint: localized("Compare polarity and scope between the premise and conclusion.", request: request),
                decisiveStep: localized("Reject the unsupported negation and universalization.", request: request),
                requiredTermGroups: [
                    "unsupported negation|cannot negate|opposite does not follow|reject the opposite|否定は導けない|反対は導けない",
                    "unsupported universal|every case does not follow|cannot generalize|overgeneralization is invalid|一般化できない|すべてとは言えない",
                    "retain qualifier|preserve scope|keep the original claim|限定を保つ|範囲を保つ|元の主張を保つ"
                ],
                minimumRequiredTermMatches: 2,
                rejectedAssertionGroups: [
                    "opposite is true|conclusion is valid|every case follows|反対が正しい|結論は妥当"
                ]
            )
        }
        if basis.sourceText == nil {
            let topic = semanticTopic(request, basis: basis)
            switch topic {
            case .dijkstraShortestPaths:
                let sixthSlot = (Int(request.seed % 6) + 5) % 6
                if request.count > 5, basis.reasoningVariant == sixthSlot {
                    return conceptDebugging(request, basis: basis)
                }
            case .graphTraversal, .binarySearch, .dynamicProgramming, .sorting,
                 .stoichiometry, .classicalMechanics, .programBoundaries:
                if basis.reasoningVariant != 0 {
                    return conceptDebugging(request, basis: basis)
                }
            default:
                return conceptDebugging(request, basis: basis)
            }
        }
        let scenario = domainDebuggingScenario(request, basis: basis)
        let usesSelfCheck = semanticTopic(request, basis: basis) == .dijkstraShortestPaths
        let topic = basis.topic.lowercased()
        let prompt = request.field == .computing
            ? localized("Debug this \(topicWithoutTrailingQualifier(topic, qualifier: "implementation")) implementation:\n```\n\(scenario.code)\n```\nExpected result or invariant: \(scenario.expected). Identify the first faulty operation and give the smallest correction.", request: request)
            : localized("Debug this \(topicWithoutTrailingQualifier(topic, qualifier: "calculation")) calculation:\n```\n\(scenario.code)\n```\nExpected result or invariant: \(scenario.expected). Identify the first faulty operation and give the smallest correction.", request: request)
        return makeQuestion(
            request: request,
            basis: basis,
            prompt: prompt,
            correctAnswer: scenario.correctAnswer,
            acceptedAnswers: scenario.acceptedAnswers,
            explanation: scenario.explanation,
            hint: scenario.hint,
            decisiveStep: scenario.decisiveStep,
            requiredTermGroups: usesSelfCheck ? [] : scenario.requiredTermGroups,
            minimumRequiredTermMatches: usesSelfCheck ? nil : scenario.minimumRequiredTermMatches,
            rejectedAssertionGroups: usesSelfCheck ? [] : scenario.rejectedAssertionGroups
        )
    }

    /// Builds questions from the source representation itself. Each branch
    /// tests a different reasoning operation (relation tracing, coefficient
    /// contribution, interval width, dependency analysis, boundary behavior,
    /// or a bounded transcription audit). Token mutation is deliberately
    /// limited to one semantic slot in a multi-item set.
    private static func sourceDebuggingQuestion(
        _ request: NFAuthoringRequest,
        basis: Basis
    ) -> NFAuthoredQuestion? {
        guard basis.sourceText != nil else { return nil }

        if let relation = sourceDiagramRelation(in: basis) {
            let correct = localized("The cited diagram contains the directed relation \(relation.from) → \(relation.to); preserve that direction when tracing the flow.", request: request)
            return makeQuestion(
                request: request,
                basis: basis,
                prompt: localized("Trace this complete relation from the cited diagram:\n```mermaid\n\(relation.sourceLine)\n```\nWhich node is immediately downstream of \(relation.from), and what direction must an implementation preserve?", request: request),
                correctAnswer: correct,
                acceptedAnswers: [
                    localized("\(relation.to); \(relation.from) points to \(relation.to).", request: request)
                ],
                explanation: localized("The arrowhead terminates at \(relation.to), so the cited edge runs from \(relation.from) to \(relation.to). Reversing it would change the documented flow.", request: request),
                hint: localized("Follow the arrowhead, not the left-to-right reading order alone.", request: request),
                decisiveStep: localized("Read the edge as \(relation.from) → \(relation.to).", request: request),
                requiredTermGroups: [
                    relation.to,
                    "from \(relation.from) to \(relation.to)|\(relation.from) points to \(relation.to)|\(relation.from) → \(relation.to)|\(relation.from) -> \(relation.to)"
                ],
                minimumRequiredTermMatches: 2,
                rejectedAssertionGroups: [
                    "\(relation.to) points to \(relation.from)|from \(relation.to) to \(relation.from)|\(relation.to) → \(relation.from)|\(relation.to) -> \(relation.from)"
                ]
            )
        }

        if let term = sourceWeightedTerm(in: basis) {
            let coefficient = formatSourceNumber(term.coefficient)
            let correct = localized("The contribution is \(coefficient), because setting \(term.variable) = 1 leaves its coefficient unchanged.", request: request)
            return makeQuestion(
                request: request,
                basis: basis,
                prompt: localized("Audit the cited scoring term `\(term.display)`. If \(term.variable) = 1 and every other additive term is held at zero, what contribution does this term make? Explain why changing multiplication to division would violate the stated linear weighting.", request: request),
                correctAnswer: correct,
                acceptedAnswers: [
                    localized("\(coefficient); the coefficient multiplies \(term.variable).", request: request)
                ],
                explanation: localized("A linear term c × x contributes c when x = 1. Division by c would instead rescale x by the reciprocal and would not implement the cited weight.", request: request),
                hint: localized("Substitute 1 for the named variable in the displayed term.", request: request),
                decisiveStep: localized("Evaluate \(term.display) at \(term.variable) = 1.", request: request),
                requiredTermGroups: [coefficient, term.variable, "coefficient|weight|multipl|係数|重み|掛け"],
                minimumRequiredTermMatches: 3,
                rejectedAssertionGroups: ["divide by \(coefficient)|reciprocal weight|\(formatSourceNumber(1 / term.coefficient))"]
            )
        }

        if let interval = sourceInterval(in: basis) {
            let lower = formatSourceNumber(interval.lower)
            let upper = formatSourceNumber(interval.upper)
            let width = formatSourceNumber(interval.upper - interval.lower)
            let correct = localized("The stated interval runs from \(lower) to \(upper), so its width is \(width).", request: request)
            return makeQuestion(
                request: request,
                basis: basis,
                prompt: localized("The cited specification states `\(interval.display)`. Identify both boundaries and calculate the interval width. Which invariant would reject a candidate lower bound that exceeds the upper bound?", request: request),
                correctAnswer: correct,
                acceptedAnswers: [
                    localized("Lower \(lower), upper \(upper), width \(width); require lower ≤ upper.", request: request)
                ],
                explanation: localized("Interval width is upper minus lower. A valid closed range must preserve lower ≤ upper, so a reversed or overshooting lower boundary is invalid.", request: request),
                hint: localized("Subtract the lower boundary from the upper boundary.", request: request),
                decisiveStep: localized("Compute \(upper) − \(lower) and check lower ≤ upper.", request: request),
                requiredTermGroups: [lower, upper, width, "lower ≤ upper|lower <= upper|lower bound.*upper bound|下限.*上限"],
                minimumRequiredTermMatches: 4,
                rejectedAssertionGroups: ["lower > upper|lower bound exceeds|下限が上限を超える"]
            )
        }

        if let assignment = sourceAssignment(in: basis), assignment.dependencies.count >= 2 {
            let dependencies = assignment.dependencies.joined(separator: ", ")
            let correct = localized("The explicit inputs to \(assignment.target) are \(dependencies); each must be available before the assignment is evaluated.", request: request)
            return makeQuestion(
                request: request,
                basis: basis,
                prompt: localized("Read the cited assignment:\n```\n\(assignment.display)\n```\nList its explicit input variables and state the dependency invariant an implementation must preserve before computing \(assignment.target).", request: request),
                correctAnswer: correct,
                acceptedAnswers: [
                    localized("\(dependencies); compute them before \(assignment.target).", request: request)
                ],
                explanation: localized("The right-hand side names the values consumed by the assignment. Evaluating the target before those inputs are defined would use missing or stale state.", request: request),
                hint: localized("Inspect identifiers on the right-hand side, not the assignment target.", request: request),
                decisiveStep: localized("Separate \(assignment.target) from its right-hand-side dependencies.", request: request),
                requiredTermGroups: assignment.dependencies + ["before|available|defined|dependency|先に|定義|依存"],
                minimumRequiredTermMatches: min(assignment.dependencies.count + 1, 4),
                rejectedAssertionGroups: ["no dependencies|independent of every input|依存しない"]
            )
        }

        let allowsMutation = request.count == 1 || basis.semanticVariant == 0
        if allowsMutation, let mutation = sourceCodeMutation(in: basis) {
            let correct = localized("Replace \(mutation.faultyToken) with \(mutation.originalToken) so the transcription matches the cited source line.", request: request)
            return makeQuestion(
                request: request,
                basis: basis,
                prompt: localized("Compare the cited source line with the faulty transcription below. Identify the changed operator or literal and restore the cited behavior.\nCited line:\n```\n\(mutation.originalLine)\n```\nFaulty transcription:\n```\n\(mutation.faultyLine)\n```", request: request),
                correctAnswer: correct,
                acceptedAnswers: [localized("Restore \(mutation.originalToken) in place of \(mutation.faultyToken).", request: request)],
                explanation: localized("The deterministic fault is the single displayed substitution; restoring the cited token reproduces the source line without executing imported code.", request: request),
                hint: localized("Compare the two lines token by token.", request: request),
                decisiveStep: localized("Restore the one token that differs from the cited line.", request: request),
                requiredTermGroups: [
                    "restore|replace|change back|put back|元に戻す|置き換える",
                    "cited|original|source line|matches the source|引用|元の行|ソース"
                ],
                minimumRequiredTermMatches: 2,
                rejectedAssertionGroups: ["faulty line is correct|no change is needed|keep the faulty|誤った行が正しい|変更不要"]
            )
        }

        if let comparison = sourceComparison(in: basis) {
            let boundaryIsAccepted = comparison.operatorToken.contains("=")
            let threshold = formatSourceNumber(comparison.threshold)
            let boundaryResult = boundaryIsAccepted ? "true" : "false"
            let correct = localized("At \(comparison.variable) = \(threshold), the condition is \(boundaryResult) because `\(comparison.operatorToken)` is \(boundaryIsAccepted ? "inclusive" : "strict").", request: request)
            return makeQuestion(
                request: request,
                basis: basis,
                prompt: localized("Boundary audit for the cited condition `\(comparison.display)`: evaluate it when \(comparison.variable) equals \(threshold), then explain whether the threshold itself is included.", request: request),
                correctAnswer: correct,
                acceptedAnswers: [localized("\(boundaryResult); `\(comparison.operatorToken)` \(boundaryIsAccepted ? "includes" : "excludes") equality.", request: request)],
                explanation: localized("Strict inequalities exclude equality; inequalities containing `=` include it. Testing the exact boundary exposes off-by-one and threshold errors.", request: request),
                hint: localized("Substitute the threshold itself and inspect whether the operator contains equality.", request: request),
                decisiveStep: localized("Evaluate \(threshold) \(comparison.operatorToken) \(threshold).", request: request),
                requiredTermGroups: [boundaryResult, boundaryIsAccepted ? "inclusive|includes equality|含む" : "strict|excludes equality|含まない", threshold],
                minimumRequiredTermMatches: 3,
                rejectedAssertionGroups: [boundaryIsAccepted ? "excludes equality|strict" : "includes equality|inclusive"]
            )
        }

        return nil
    }

    private struct DomainDebuggingScenario {
        let code: String
        let expected: String
        let correctAnswer: String
        let acceptedAnswers: [String]
        let explanation: String
        let hint: String
        let decisiveStep: String
        let requiredTermGroups: [String]
        let minimumRequiredTermMatches: Int
        let rejectedAssertionGroups: [String]

        init(
            code: String,
            expected: String,
            correctAnswer: String,
            acceptedAnswers: [String],
            explanation: String,
            hint: String,
            decisiveStep: String,
            requiredTermGroups: [String],
            minimumRequiredTermMatches: Int,
            rejectedAssertionGroups: [String] = []
        ) {
            self.code = code
            self.expected = expected
            self.correctAnswer = correctAnswer
            self.acceptedAnswers = acceptedAnswers
            self.explanation = explanation
            self.hint = hint
            self.decisiveStep = decisiveStep
            self.requiredTermGroups = requiredTermGroups
            self.minimumRequiredTermMatches = minimumRequiredTermMatches
            self.rejectedAssertionGroups = rejectedAssertionGroups
        }
    }

    private static func domainDebuggingScenario(
        _ request: NFAuthoringRequest,
        basis: Basis
    ) -> DomainDebuggingScenario {
        if let computingScenario = semanticComputingDebuggingScenario(request, basis: basis) {
            return computingScenario
        }

        switch request.field {
        case .chemistry where topicSuggestsStoichiometry(basis.topic):
            let aMoles = basis.a * 2
            let bMoles = basis.b
            let product = 2 * min(aMoles / 2, bMoles)
            let answer = localized("Replace max with min when choosing the coefficient-adjusted reaction extent; the limiting reagent determines yield.", request: request)
            return DomainDebuggingScenario(
                code: "aMoles = \(aMoles)\nbMoles = \(bMoles)\nextent = max(aMoles / 2, bMoles)\nproductMoles = 2 * extent",
                expected: localized("\(product) mol product from 2A + B → 2C", request: request),
                correctAnswer: answer,
                acceptedAnswers: [
                    localized("Use min(aMoles / 2, bMoles), not max", request: request),
                    localized("Choose the limiting reagent extent", request: request)
                ],
                explanation: localized("A feasible reaction extent cannot exceed either reactant’s coefficient-adjusted supply. Using max selects the excess reactant and overstates product yield.", request: request),
                hint: localized("Compare how much reaction each reactant can support.", request: request),
                decisiveStep: answer,
                requiredTermGroups: [
                    "use min|use the minimum|minimum stoichiometric extent|replace max with min|choose the minimum|choose the smaller|最小を使う|小さい方を選ぶ",
                    "limiting reagent|limiting extent|feasible extent|限界試薬|限界となる反応進行"
                ],
                minimumRequiredTermMatches: 2,
                rejectedAssertionGroups: [
                    "use max|choose the maximum|choose the larger extent|max is correct|最大を使う|大きい方を選ぶ"
                ]
            )

        case .chemistry, .lifeSciences:
            let initial = basis.a * 10
            let stockVolume = basis.b
            let finalVolume = stockVolume * 5
            let finalConcentration = initial * stockVolume / finalVolume
            let answer = localized("Divide by finalVolume rather than stockVolume; dilution uses C₂ = C₁V₁/V₂.", request: request)
            return DomainDebuggingScenario(
                code: "initialConcentration = \(initial)\nstockVolume = \(stockVolume)\nfinalVolume = \(finalVolume)\nfinalConcentration = initialConcentration * finalVolume / stockVolume",
                expected: localized("\(finalConcentration) concentration units", request: request),
                correctAnswer: answer,
                acceptedAnswers: [
                    localized("Use initialConcentration * stockVolume / finalVolume", request: request),
                    localized("The dilution ratio is inverted", request: request)
                ],
                explanation: localized("The transferred amount is conserved. Multiplying by finalVolume/stockVolume reverses the dilution and makes concentration increase.", request: request),
                hint: localized("A dilution should not increase concentration.", request: request),
                decisiveStep: answer,
                requiredTermGroups: [
                    "stockvolume / finalvolume|v1/v2|stock volume over final|原液量|最終体積",
                    "ratio is inverted|reverse the ratio|divide by final|inversion is the bug|比が逆|最終体積で割"
                ],
                minimumRequiredTermMatches: 1,
                rejectedAssertionGroups: [
                    "keep finalvolume / stockvolume|multiply by final volume over stock|ratio is not inverted|現在の比を使う"
                ]
            )

        case .physics:
            let force = basis.a * basis.b
            let mass = basis.b
            let acceleration = basis.a
            let answer = localized("Divide netForce by mass; the code multiplies even though F = ma implies a = F/m.", request: request)
            return DomainDebuggingScenario(
                code: "netForce = \(force)\nmass = \(mass)\nacceleration = netForce * mass",
                expected: localized("\(acceleration) m/s²", request: request),
                correctAnswer: answer,
                acceptedAnswers: [localized("Use acceleration = netForce / mass", request: request)],
                explanation: localized("Solving F = ma for acceleration requires division by mass. The faulty multiplication also produces incompatible units.", request: request),
                hint: localized("Check both algebra and units.", request: request),
                decisiveStep: answer,
                requiredTermGroups: [
                    "divide by mass|divide netforce by mass|netforce / mass|f/m|mass in the denominator|質量で割る"
                ],
                minimumRequiredTermMatches: 1,
                rejectedAssertionGroups: [
                    "use multiplication by mass|should multiply by mass|acceleration = netforce * mass|multiply netforce by mass|質量を掛けるべき"
                ]
            )

        case .engineering:
            let load = basis.b * 10
            let capacity = load * max(2, basis.a / 3)
            let factor = Double(capacity) / Double(load)
            let answer = localized("Compute capacity / operatingLoad; the implemented ratio is inverted.", request: request)
            return DomainDebuggingScenario(
                code: "capacity = \(capacity)\noperatingLoad = \(load)\nfactorOfSafety = operatingLoad / capacity",
                expected: localized("factor of safety \(number(factor))", request: request),
                correctAnswer: answer,
                acceptedAnswers: [localized("Swap the numerator and denominator", request: request)],
                explanation: localized("Factor of safety compares failure capacity with expected load. The inverse incorrectly shrinks safer designs below one.", request: request),
                hint: localized("A capacity above the load should produce a factor above one.", request: request),
                decisiveStep: answer,
                requiredTermGroups: [
                    "capacity / operatingload|capacity over load|capacity divided by load|swap numerator and denominator|ratio is inverted|耐力を荷重で割る|分子と分母を入れ替える"
                ],
                minimumRequiredTermMatches: 1,
                rejectedAssertionGroups: [
                    "operatingload / capacity is correct|keep load over capacity|do not swap the ratio|荷重を耐力で割る"
                ]
            )

        case .computing:
            let count = max(3, basis.a)
            let answer = localized("Change index <= count to index < count; count is one past the final valid zero-based index.", request: request)
            return DomainDebuggingScenario(
                code: "index = 0\nwhile index <= \(count) {\n    visit(values[index])\n    index += 1\n}",
                expected: localized("visit exactly \(count) elements without an out-of-bounds access", request: request),
                correctAnswer: answer,
                acceptedAnswers: [
                    localized("Use index < count", request: request),
                    localized("Stop before index equals count", request: request)
                ],
                explanation: localized("For count elements, valid indices are 0 through count − 1. The inclusive condition attempts one extra access.", request: request),
                hint: localized("Write the last valid zero-based index.", request: request),
                decisiveStep: answer,
                requiredTermGroups: [
                    "index <|less than count|stop before index equals count|未満"
                ],
                minimumRequiredTermMatches: 1,
                rejectedAssertionGroups: [
                    "use index <=|keep the inclusive bound|index <= count is correct|以下を使う"
                ]
            )

        case .dataScience:
            let answer = localized("Split first, then fit the scaler on training data only; fitting before the split leaks test-set information.", request: request)
            return DomainDebuggingScenario(
                code: "scaled = scaler.fitTransform(allRows)\ntrain, test = split(scaled)\nmodel.fit(train)",
                expected: localized("an untouched test set for honest generalization measurement", request: request),
                correctAnswer: answer,
                acceptedAnswers: [
                    localized("Fit preprocessing on the training split only", request: request),
                    localized("Prevent test data leakage", request: request)
                ],
                explanation: localized("Preprocessing parameters fitted on all rows encode information from the test set. The split must happen before learning any transform parameters.", request: request),
                hint: localized("Ask which step learns from the held-out rows.", request: request),
                decisiveStep: answer,
                requiredTermGroups: [
                    "split first|training split|train only|先に分割|訓練データのみ",
                    "leak*|test information|held out|漏洩|テスト情報"
                ],
                minimumRequiredTermMatches: 2,
                rejectedAssertionGroups: [
                    "fit on all rows is correct|split after scaling|test leakage is harmless|全データで学習する"
                ]
            )

        case .mathematics:
            let n = max(3, basis.a)
            let expected = n * (n + 1) / 2
            let answer = localized("Include n by changing k < n to k <= n; the current bound omits the final term.", request: request)
            return DomainDebuggingScenario(
                code: "sum = 0\nk = 1\nwhile k < \(n) { sum += k; k += 1 }",
                expected: localized("sum 1 through \(n) = \(expected)", request: request),
                correctAnswer: answer,
                acceptedAnswers: [
                    localized("Use k <= n", request: request),
                    localized("The loop omits n", request: request)
                ],
                explanation: localized("The strict upper bound stops after n − 1, so the requested final term never enters the sum.", request: request),
                hint: localized("Trace the largest value of k that enters the loop.", request: request),
                decisiveStep: answer,
                requiredTermGroups: [
                    "k <= n|use <=|include n|through n|以下|n を含"
                ],
                minimumRequiredTermMatches: 1,
                rejectedAssertionGroups: [
                    "keep k < n|use k < n|n should be omitted|n を含めない"
                ]
            )

        case .general:
            let expected = basis.a * basis.b
            let answer = localized("Return total; remove the duplicate final addition.", request: request)
            return DomainDebuggingScenario(
                code: "total = 0\nrepeat \(basis.a) times { total += \(basis.b) }\nreturn total + \(basis.b)",
                expected: "\(expected)",
                correctAnswer: answer,
                acceptedAnswers: ["return total", localized("Remove the final addition", request: request)],
                explanation: localized("The loop already produces the expected total. The return statement adds one unwanted extra term.", request: request),
                hint: localized("Trace the accumulator immediately before return.", request: request),
                decisiveStep: answer,
                requiredTermGroups: [
                    "return total|remove final addition|remove extra addition|total を返|最後の加算を削除"
                ],
                minimumRequiredTermMatches: 1,
                rejectedAssertionGroups: [
                    "keep total +|return total +|extra addition is required|最後の加算を残す"
                ]
            )
        }
    }

    private static func semanticComputingDebuggingScenario(
        _ request: NFAuthoringRequest,
        basis: Basis
    ) -> DomainDebuggingScenario? {
        guard request.field == .computing else { return nil }

        switch semanticTopic(request, basis: basis) {
        case .dijkstraShortestPaths:
            switch basis.semanticVariant {
            case 0:
                let answer = localized("Skip u when it is already finalized, and discard entries whose key differs from distance[u]; otherwise duplicate heap entries repeat outgoing-edge work.", request: request)
                return DomainDebuggingScenario(
                    code: "while !priorityQueue.isEmpty {\n    let (key, u) = popMin()\n    if key != distance[u] { continue }\n    finalized.insert(u)\n    relaxOutgoingEdges(from: u)\n    // duplicate entries with the same current key may remain\n}",
                    expected: localized("process each finalized vertex’s outgoing edges once despite duplicate priority-queue entries", request: request),
                    correctAnswer: answer,
                    acceptedAnswers: [
                        localized("Continue if u is already finalized, and continue on a stale key.", request: request),
                        localized("Guard !finalized.contains(u) before relaxing outgoing edges.", request: request)
                    ],
                    explanation: localized("For nonnegative edges, the current smaller key pops before an older stale one, so stale order is not itself a correctness bug. A same-key duplicate can still pass the key check and repeat edge scans; an already-finalized guard prevents that wasted work.", request: request),
                    hint: localized("Trace two identical current-key entries for the same vertex.", request: request),
                    decisiveStep: answer,
                    requiredTermGroups: [
                        "already finalized|finalized.contains|skip finalized|process once|確定済み",
                        "duplicate|repeat|same key|重複",
                        "stale|key != distance|current key|古い"
                    ],
                    minimumRequiredTermMatches: 2,
                    rejectedAssertionGroups: [
                        "process duplicate entries again|repeat outgoing edges|重複を再処理"
                    ]
                )

            case 1:
                let answer = localized("Reject negative edge weights before running Dijkstra, or switch to Bellman–Ford; the greedy finalization invariant requires nonnegative weights.", request: request)
                return DomainDebuggingScenario(
                    code: "// Directed graph with exactly these edges:\nedges = [(s, a, 2), (s, b, 5), (b, a, -10)]\ndistance = dijkstra(edges, source: s)",
                    expected: localized("support the true shortest distance to a, which is −5, without unsafely finalizing a at distance 2", request: request),
                    correctAnswer: answer,
                    acceptedAnswers: [
                        localized("Use Bellman–Ford because the graph has a negative edge.", request: request),
                        localized("Validate that every edge weight is nonnegative before Dijkstra runs.", request: request)
                    ],
                    explanation: localized("In the stated directed graph with exactly these edges, after a is finalized at 2, the later path s → b → a has length −5. A negative edge can therefore improve an already-finalized vertex, invalidating Dijkstra’s greedy proof.", request: request),
                    hint: localized("Trace the path through b after a has already been removed from the queue.", request: request),
                    decisiveStep: answer,
                    requiredTermGroups: [
                        "negative edge|negative weight|-10|負の辺|負の重み",
                        "bellman-ford|bellman ford|reject|validate|ベルマン|拒否|検証",
                        "nonnegative|finalization invariant|already finalized|非負|確定"
                    ],
                    minimumRequiredTermMatches: 2,
                    rejectedAssertionGroups: [
                        "dijkstra is correct with negative|negative edge is safe|keep dijkstra unchanged|負の辺でも正しい"
                    ]
                )

            case 2:
                let answer = localized("Push candidateDistance as v’s priority, not the single edge weight; Dijkstra’s queue key is the complete tentative source-to-v distance.", request: request)
                return DomainDebuggingScenario(
                    code: "candidateDistance = distance[u] + edge.weight\nif candidateDistance < distance[v] {\n    distance[v] = candidateDistance\n    priorityQueue.push(v, priority: edge.weight)\n}",
                    expected: localized("remove the vertex with the smallest complete tentative distance from the source", request: request),
                    correctAnswer: answer,
                    acceptedAnswers: [
                        localized("Use priority: candidateDistance.", request: request),
                        localized("Queue by the cumulative path distance, not edge.weight.", request: request)
                    ],
                    explanation: localized("An edge can be light while the path used to reach its tail is expensive. Ordering only by edge.weight loses the greedy minimum-distance property that Dijkstra’s proof needs.", request: request),
                    hint: localized("Distinguish a local edge cost from a complete source-to-vertex path cost.", request: request),
                    decisiveStep: answer,
                    requiredTermGroups: [
                        "candidatedistance|candidate distance|distance[u] +|cumulative distance|tentative distance|source-to-v distance|累積距離|候補距離",
                        "priority|queue key|heap key|queue v|enqueue v|priority queue|優先度|キー",
                        "not edge.weight|not edge weight|not local edge|not by the local edge|complete path|complete tentative|cumulative path|path cost|source distance|single edge|辺の重みではない|経路全体"
                    ],
                    minimumRequiredTermMatches: 2,
                    rejectedAssertionGroups: [
                        "priority: edge.weight is correct|queue by edge weight|edge.weight should be priority|local edge weight is the key|辺の重みだけを使う"
                    ]
                )

            case 3:
                let answer = localized("Compute candidateDistance and update v only when it is smaller; never finalize on discovery—finalize only when v’s current minimum key is popped.", request: request)
                return DomainDebuggingScenario(
                    code: "for (v, weight) in edges[u] {\n    if !finalized.contains(v) {\n        distance[v] = distance[u] + weight\n        finalized.insert(v)\n        priorityQueue.push(v, priority: distance[v])\n    }\n}",
                    expected: localized("preserve the best tentative distance and allow later improvements until minimum-key removal", request: request),
                    correctAnswer: answer,
                    acceptedAnswers: [
                        localized("Use if candidateDistance < distance[v], and remove finalized.insert(v) from relaxation.", request: request),
                        localized("Condition relaxation on improvement and finalize only on pop-min.", request: request)
                    ],
                    explanation: localized("The current code both overwrites a better tentative value without comparison and closes v after its first path. Correct relaxation preserves min(old,candidate), while only current global-minimum removal proves finality.", request: request),
                    hint: localized("Audit both the update condition and the line that declares finality.", request: request),
                    decisiveStep: answer,
                    requiredTermGroups: [
                        "candidate < distance|candidateDistance <|only if smaller|minimum of|改善時のみ",
                        "not on insertion|not when discovered|remove finalized.insert|do not close v|発見時ではない",
                        "pop*|pop-min|min-key removal|remove minimum|current-minimum removal|queue entry is popped|取り出す|最小キー",
                        "finaliz*|tentative|later relaxation|確定"
                    ],
                    minimumRequiredTermMatches: 3,
                    rejectedAssertionGroups: [
                        "finalize on discovery|finalize on insertion|first path is always shortest|発見時に確定"
                    ]
                )

            default:
                let answer = localized("Return only when target is popped with its current minimum key; the first queued path to target is not necessarily the shortest.", request: request)
                return DomainDebuggingScenario(
                    code: "candidateDistance = distance[u] + weight\nif candidateDistance < distance[v] {\n    distance[v] = candidateDistance\n    priorityQueue.push(v, priority: candidateDistance)\n    if v == target { return candidateDistance }\n}",
                    expected: localized("stop only after the target’s shortest distance is finalized", request: request),
                    correctAnswer: answer,
                    acceptedAnswers: [
                        localized("Move target termination to the non-stale pop-min step.", request: request),
                        localized("Do not stop when the target is first enqueued.", request: request)
                    ],
                    explanation: localized("Enqueueing proves only that one path to target has been found. The priority queue may still contain a different frontier route that later lowers target’s distance; the greedy invariant becomes decisive only at current minimum-key removal.", request: request),
                    hint: localized("Ask when Dijkstra’s algorithm proves a tentative distance is final.", request: request),
                    decisiveStep: answer,
                    requiredTermGroups: [
                        "not first enqueued|do not stop when enqueued|do not stop at enqueue|first queued path is not|keep target in the priority queue|keep the target in the priority queue|finding target is tentative|discovery is tentative|defer termination|エンキュー時に終了しない|最初の発見で終了しない",
                        "pop*|pop-min|min-key removal|popped with its current minimum|popped at the current minimum|popped with its current smallest|popped with the current smallest|return only when it is popped|取り出す|最小キー",
                        "target|shortest|finaliz*|目的地|最短|確定"
                    ],
                    minimumRequiredTermMatches: 2,
                    rejectedAssertionGroups: [
                        "return when first enqueued|return immediately when target is discovered|first discovered path is shortest|discovery return is correct|最初の発見で返す"
                    ]
                )
            }

        case .graphTraversal:
            let answer = localized("Mark u visited before recursing into its neighbors; marking it afterward allows a cycle to re-enter u indefinitely.", request: request)
            return DomainDebuggingScenario(
                code: "func dfs(u) {\n    for v in neighbors[u] where !visited.contains(v) { dfs(v) }\n    visited.insert(u)\n}",
                expected: localized("visit every reachable vertex once even when the graph contains a cycle", request: request),
                correctAnswer: answer,
                acceptedAnswers: [localized("Move visited.insert(u) before the neighbor loop.", request: request)],
                explanation: localized("In a cycle, a descendant can reach u again before the original call returns. Recording entry before recursion closes that re-entry path.", request: request),
                hint: localized("Trace two vertices with edges in both directions.", request: request),
                decisiveStep: answer,
                requiredTermGroups: [
                    "mark u visited before|visited before recursion|move visited|先に訪問済み",
                    "cycle|re-enter|infinite recursion|循環|再帰"
                ],
                minimumRequiredTermMatches: 2
            )

        case .binarySearch:
            let answer = localized("Initialize high to values.count − 1, or use a half-open loop; values.count is not a valid array index.", request: request)
            return DomainDebuggingScenario(
                code: "low = 0\nhigh = values.count\nwhile low <= high {\n    mid = (low + high) / 2\n    compare(values[mid], target)\n}",
                expected: localized("search without reading one past the final zero-based index", request: request),
                correctAnswer: answer,
                acceptedAnswers: [localized("Use high = values.count - 1.", request: request)],
                explanation: localized("A closed interval [low, high] must end at the last valid index. Setting high to count can produce mid == count and an out-of-bounds access.", request: request),
                hint: localized("Write the final valid index for count elements.", request: request),
                decisiveStep: answer,
                requiredTermGroups: [
                    "count - 1|count−1|half-open|未満",
                    "out of bounds|invalid index|one past|範囲外"
                ],
                minimumRequiredTermMatches: 1
            )

        case .dynamicProgramming:
            let answer = localized("Compute states in increasing order so dp[i − 1] and dp[i − 2] are already available; the descending loop reads uncomputed states.", request: request)
            return DomainDebuggingScenario(
                code: "dp[0] = 0\ndp[1] = 1\nfor i in stride(from: n, through: 2, by: -1) {\n    dp[i] = dp[i - 1] + dp[i - 2]\n}",
                expected: localized("fill every Fibonacci state from previously solved dependencies", request: request),
                correctAnswer: answer,
                acceptedAnswers: [localized("Iterate i from 2 through n.", request: request)],
                explanation: localized("A bottom-up dynamic program needs a topological order over state dependencies. Each Fibonacci state depends on two smaller indices, so those indices must be filled first.", request: request),
                hint: localized("Draw an arrow from each state to the states it reads.", request: request),
                decisiveStep: answer,
                requiredTermGroups: [
                    "increasing|2 through n|ascending|昇順",
                    "dependenc|already computed|uncomputed|依存|計算済み"
                ],
                minimumRequiredTermMatches: 2
            )

        case .sorting:
            let answer = localized("After the main merge loop, append the unconsumed suffix from each input; otherwise the longer side is silently dropped.", request: request)
            return DomainDebuggingScenario(
                code: "while i < left.count && j < right.count {\n    appendSmaller(left[i], right[j])\n}\nreturn merged",
                expected: localized("return every element from both sorted halves in nondecreasing order", request: request),
                correctAnswer: answer,
                acceptedAnswers: [localized("Append the remaining left and right tails before returning.", request: request)],
                explanation: localized("The paired comparison loop stops as soon as either side is exhausted. Every element remaining on the other sorted side is already in final order but still must be copied.", request: request),
                hint: localized("Trace a merge where the left half has two elements after the right half ends.", request: request),
                decisiveStep: answer,
                requiredTermGroups: [
                    "append the remaining|append remaining|append the suffix|copy the tail|copy remaining|残りを追加|末尾を追加",
                    "left and right|either side|both halves|両方|片側"
                ],
                minimumRequiredTermMatches: 1
            )

        default:
            return nil
        }
    }

    private static func topicSuggestsStoichiometry(_ topic: String) -> Bool {
        let normalized = topic.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        return [
            "stoich", "limiting", "reagent", "reaction yield", "mole ratio",
            "化学量論", "限界試薬", "反応物", "収率", "モル比"
        ].contains { normalized.localizedCaseInsensitiveContains($0) }
    }

    private struct DesignTopicProfile {
        let scenarios: [String]
        let repairs: [String]
        let threats: [String]
    }

    private static func designTopicProfile(
        _ request: NFAuthoringRequest,
        basis: Basis
    ) -> DesignTopicProfile {
        func profile(
            scenarios: [String.LocalizationValue],
            repairs: [String.LocalizationValue],
            threats: [String.LocalizationValue]
        ) -> DesignTopicProfile {
            DesignTopicProfile(
                scenarios: scenarios.map { localized($0, request: request) },
                repairs: repairs.map { localized($0, request: request) },
                threats: threats.map { localized($0, request: request) }
            )
        }

        switch request.field {
        case .mathematics:
            return profile(
                scenarios: [
                    "A conjecture has been checked for the first 100 integers.",
                    "A numerical optimizer succeeds from one interior starting point.",
                    "A symbolic derivation and a numerical approximation disagree.",
                    "A model’s conclusion was computed under one fixed parameter choice.",
                    "Two candidate models fit every point used to construct them.",
                    "A simulation result changes when arithmetic precision changes."
                ],
                repairs: [
                    "Search systematically for a counterexample, then supply a proof if the universal claim is retained.",
                    "Test boundary points, multiple starts, and the active constraints.",
                    "Evaluate both methods on a case with an independently known exact result.",
                    "Vary the assumption across a declared range and report conclusion sensitivity.",
                    "Reserve new points not used during construction and compare out-of-sample predictions.",
                    "Repeat at increasing precision and check convergence against an analytic bound."
                ],
                threats: [
                    "finite confirmation cannot prove a universal statement",
                    "boundary or local-optimum failure",
                    "an undetected algebraic or implementation error",
                    "unreported dependence on an assumption",
                    "in-sample agreement without discrimination",
                    "numerical instability or rounding error"
                ]
            )
        case .computing:
            return profile(
                scenarios: [
                    "Two implementations are timed once on already sorted input.",
                    "A routine passes a typical multi-element example.",
                    "A stateful algorithm returns the expected final value on one trace.",
                    "A pipeline improves after three components are added together.",
                    "A concurrent routine passes under the default scheduler.",
                    "A reported benchmark cannot be reproduced on a clean environment."
                ],
                repairs: [
                    "Use representative input families, warmups, repeated runs, and randomized implementation order.",
                    "Add empty, singleton, duplicate, adversarial, and maximum-size cases.",
                    "Use property-based tests that check the invariant after every state transition.",
                    "Run an ablation that removes one component at a time while keeping evaluation fixed.",
                    "Stress controlled interleavings and assert the synchronization or idempotency invariant.",
                    "Pin code, data, dependencies, seeds, and the benchmark command in a clean rerun."
                ],
                threats: [
                    "input-order, warmup, and timing noise",
                    "unexercised boundary failures",
                    "a hidden intermediate-state violation",
                    "confounded component attribution",
                    "schedule-dependent race conditions",
                    "environment or dependency drift"
                ]
            )
        case .dataScience:
            return profile(
                scenarios: [
                    "Preprocessing is fit on all rows before model evaluation.",
                    "Random rows from the same people and dates appear in train and test.",
                    "A complex pipeline beats a baseline after many pieces change together.",
                    "Aggregate accuracy looks strong despite a rare positive class.",
                    "A feature recorded after the target event is highly predictive.",
                    "One favorable split and random seed are reported."
                ],
                repairs: [
                    "Split first and fit every learned transform on training data only.",
                    "Split by the intended generalization unit, such as person, site, or future time.",
                    "Hold evaluation fixed and remove one pipeline component at a time.",
                    "Report the confusion matrix, class-specific metrics, and threshold tradeoff.",
                    "Remove the post-outcome feature and add a negative-control or temporal-availability audit.",
                    "Predeclare the metric and summarize repeated seeds or resamples with uncertainty."
                ],
                threats: [
                    "test-information leakage",
                    "entity or temporal dependence across splits",
                    "confounded ablation evidence",
                    "base-rate-hidden failure",
                    "target leakage",
                    "seed selection and evaluation variance"
                ]
            )
        case .physics, .engineering, .chemistry:
            return profile(
                scenarios: [
                    "Several physical factors change between the reference and treatment runs.",
                    "All reference runs occur before all treatment runs while the apparatus drifts.",
                    "The instrument has not been checked against a known reference.",
                    "The operator knows each condition while choosing an ambiguous endpoint.",
                    "Many repeated readings come from one specimen or batch.",
                    "The proposed relation is tested only near one comfortable operating point."
                ],
                repairs: [
                    "Change one target factor while holding boundary conditions and measurement procedure fixed.",
                    "Randomize or interleave run order and record the drift variable.",
                    "Calibrate with a known reference and include a blank or zero condition.",
                    "Blind the condition label during endpoint measurement or use a prespecified automated rule.",
                    "Repeat across independently prepared specimens or batches, not only repeated readings.",
                    "Measure across zero, boundary, and predicted nonlinear or failure regimes."
                ],
                threats: [
                    "confounding by simultaneous physical changes",
                    "time-order and instrument drift",
                    "scale offset or calibration error",
                    "observer-dependent measurement bias",
                    "pseudoreplication",
                    "untested boundary behavior"
                ]
            )
        case .lifeSciences:
            return profile(
                scenarios: [
                    "Samples choose or receive treatment through a process tied to baseline state.",
                    "Every treated sample is processed in one batch and every control in another.",
                    "The treatment and control receive different handling steps.",
                    "The scorer knows the condition while judging a subjective phenotype.",
                    "Many cells from one organism are analyzed as independent organisms.",
                    "A pathway claim is tested at one dose and one time point."
                ],
                repairs: [
                    "Randomize treatment when feasible or use a defensible matched or adjusted assignment design.",
                    "Block and randomize treatment within each processing batch.",
                    "Add a procedural or vehicle control that receives every step except the active treatment.",
                    "Blind condition labels during measurement or use a prespecified automated endpoint.",
                    "Replicate at the biological unit and treat within-unit measurements as nested.",
                    "Measure a dose-response and time course with positive and negative controls."
                ],
                threats: [
                    "baseline selection confounding",
                    "treatment-batch confounding",
                    "handling or vehicle effects",
                    "observer bias",
                    "pseudoreplication",
                    "missed dynamics or nonmonotonic response"
                ]
            )
        case .general:
            return profile(
                scenarios: [
                    "Participants choose exposure or control before the outcome is measured.",
                    "The groups begin with visibly different baseline outcome values.",
                    "The assessor knows each participant’s exposure while scoring an ambiguous outcome.",
                    "Many outcomes are examined and only the largest difference is reported.",
                    "Repeated measurements from the same unit are counted as independent units.",
                    "The claim is tested in one narrow setting and generalized to every setting."
                ],
                repairs: [
                    "Randomly assign exposure when ethical and feasible, or justify a design that addresses assignment confounding.",
                    "Measure baseline and block, match, or adjust using a prespecified comparison.",
                    "Blind the assessor or use a prespecified objective measurement rule.",
                    "Predeclare the primary outcome and account for the planned family of comparisons.",
                    "Randomize and analyze at the actual independent assignment unit.",
                    "Replicate in a deliberately different population or setting and test the boundary condition."
                ],
                threats: [
                    "self-selection confounding",
                    "baseline imbalance",
                    "measurement bias",
                    "selective outcome reporting",
                    "pseudoreplication",
                    "unsupported transport or generalization"
                ]
            )
        }
    }

    private static func diversifiedExperimentalDesign(
        _ request: NFAuthoringRequest,
        basis: Basis
    ) -> NFAuthoredQuestion {
        let profile = designTopicProfile(request, basis: basis)
        let variant = basis.reasoningVariant
        let repair = profile.repairs[variant]
        let threat = profile.threats[variant]
        let conciseRepair = repair.trimmingCharacters(
            in: .whitespacesAndNewlines.union(.punctuationCharacters)
        )
        let correct = localized("\(repair) This directly addresses \(threat).", request: request)
        let decisiveStep = localized("\(repair) Target threat: \(threat).", request: request)
        return makeQuestion(
            request: request,
            basis: basis,
            prompt: localized("Design a stronger \(basis.topic.lowercased()) test. \(profile.scenarios[variant]) State the smallest design change and the specific threat it addresses.", request: request),
            correctAnswer: correct,
            acceptedAnswers: [localized("\(conciseRepair); \(threat)", request: request)],
            explanation: correct,
            hint: localized("Change the source of ambiguity, not only the sample size or measurement precision.", request: request),
            decisiveStep: decisiveStep,
            requiredTermGroups: [
                repairScoringTerms(for: variant, request: request),
                threatScoringTerms(for: variant, request: request)
            ],
            minimumRequiredTermMatches: 2
        )
    }

    private static func semanticStarterExperiment(
        _ request: NFAuthoringRequest,
        basis: Basis
    ) -> NFAuthoredQuestion? {
        let problem: ConcreteOpenProblem
        switch (semanticTopic(request, basis: basis), basis.reasoningVariant) {
        case (.causalInference, 0):
            problem = ConcreteOpenProblem(
                prompt: "A school wants to test whether a new 20-minute practice routine improves algebra scores. Volunteers choose routine or usual study, then take the same test. Give the smallest design change that targets self-selection and name the threat.",
                correctAnswer: "Randomly assign consenting students to the new routine or usual study, ideally stratified by baseline score. This targets baseline self-selection confounding.",
                acceptedAnswer: "Random assignment; self-selection or baseline confounding.",
                explanation: "Choice of study routine can be associated with motivation or prior skill before treatment. Random allocation breaks that systematic assignment path in expectation.",
                hint: "Change how students enter the two groups.",
                decisiveStep: "Randomize treatment assignment before measuring the outcome."
            )
        case (.causalInference, 1):
            problem = ConcreteOpenProblem(
                prompt: "A randomized smoking-cessation trial loses 5% of control participants but 35% of treatment participants, mostly people who did not quit. Can the complete-case comparison retain the original causal guarantee, and what repair should be planned?",
                correctAnswer: "No. Outcome-related differential attrition can break the comparability created by randomization. Track outcomes aggressively, report attrition by arm and reason, and use a prespecified intention-to-treat analysis with defensible missing-data sensitivity bounds.",
                acceptedAnswer: "Differential attrition threatens the randomized comparison; use intention-to-treat follow-up and missing-data sensitivity analysis.",
                explanation: "Analyzing only observed completers selects treatment participants partly by success, so the remaining arms need not represent the randomized groups. Sensitivity analysis shows how conclusions depend on the missing outcomes.",
                hint: "Ask whether remaining observed participants still reflect everyone originally assigned.",
                decisiveStep: "Diagnose outcome-related differential attrition and preserve assignment with intention-to-treat sensitivity analysis."
            )
        case (.causalInference, 2):
            problem = ConcreteOpenProblem(
                prompt: "A model predicts which patients will be readmitted with high accuracy from pre-discharge records. A team claims that forcing the model’s top predictor to a lower value would prevent readmission. What does predictive success establish, what causal claim remains unsupported, and what study would test it?",
                correctAnswer: "Accuracy establishes predictive association in the evaluated population, not that intervening on the predictor changes readmission. Test the causal claim with an ethical randomized intervention on a manipulable exposure, or a defensible quasi-experiment that blocks confounding.",
                acceptedAnswer: "Prediction is not intervention causation; use randomized or credible quasi-experimental evidence.",
                explanation: "A variable can predict because it is a proxy, consequence, or common-effect signal. Deployment accuracy does not identify the counterfactual outcome under an intervention on that variable.",
                hint: "Separate forecasting Y from estimating Y under do(X=x).",
                decisiveStep: "Distinguish predictive association from an intervention effect and propose an identifying design."
            )
        case (.causalInference, 3):
            problem = ConcreteOpenProblem(
                prompt: "Researchers measure 30 outcomes and publish only the one with p=0.03. What design/reporting change is needed, and what threat does it address?",
                correctAnswer: "Preregister a primary outcome and analysis, disclose all planned outcomes, and account for multiple comparisons. This addresses selective reporting and false-positive inflation.",
                acceptedAnswer: "Preregister the primary outcome and correct for multiplicity; selective outcome reporting.",
                explanation: "With many comparisons, at least one small p-value can arise by chance. Prespecification separates confirmatory evidence from exploratory selection.",
                hint: "The choice of outcome occurred after seeing results.",
                decisiveStep: "Fix and disclose the outcome family before analysis."
            )
        case (.causalInference, 4):
            problem = ConcreteOpenProblem(
                prompt: "An intervention is assigned and delivered at classroom level in only 3 classrooms, producing 60 student measurements that are analyzed as independent. What is the independent assignment unit and the necessary repair?",
                correctAnswer: "The classroom is the independent assignment/cluster unit. Replicate across more classrooms and use a clustered or multilevel analysis rather than treating 60 observations as independent.",
                acceptedAnswer: "Classroom is the independent unit; add classroom replication and cluster-aware analysis.",
                explanation: "Students within one classroom share treatment delivery and environment. Counting them as independent exaggerates the effective sample size and precision.",
                hint: "Ask at which level treatment was assigned independently.",
                decisiveStep: "Align replication and analysis with the classroom assignment unit."
            )
        case (.causalInference, _):
            problem = ConcreteOpenProblem(
                prompt: "A crop treatment is tested in one greenhouse at 22 °C, then claimed to improve yield in every climate. Design the smallest follow-up that tests this generalization and name the threat.",
                correctAnswer: "Replicate the randomized treatment comparison across prespecified temperature or field environments and test treatment-by-environment interaction. This addresses unsupported transport/generalization.",
                acceptedAnswer: "Replicate across climates and test interaction; unsupported generalization.",
                explanation: "The original experiment can estimate an effect under its greenhouse conditions, but it contains no evidence that the effect is stable across environments.",
                hint: "Vary the setting that the universal claim crosses.",
                decisiveStep: "Test the effect across deliberately different environments."
            )

        case (.biologicalExperiments, 0):
            problem = ConcreteOpenProblem(
                prompt: "To test a growth factor, cells with high baseline growth are preferentially assigned treatment while low-growth cells enter control. Give the smallest assignment repair and name the threat.",
                correctAnswer: "Measure baseline growth and randomize treatment within baseline-growth blocks. This targets baseline selection confounding.",
                acceptedAnswer: "Block by baseline growth and randomize; selection confounding.",
                explanation: "Preferential assignment makes treatment status encode pre-existing growth potential. Blocking plus randomization separates that potential from the intervention.",
                hint: "Treatment assignment currently depends on the outcome’s baseline predictor.",
                decisiveStep: "Randomize within comparable baseline-growth strata."
            )
        case (.biologicalExperiments, 1):
            problem = ConcreteOpenProblem(
                prompt: "All treated samples are processed Monday and all controls Friday. How should processing be redesigned, and what threat does the original layout create?",
                correctAnswer: "Process treated and control samples in every batch with randomized order or blocking by day. The original design confounds treatment with batch/day.",
                acceptedAnswer: "Mix conditions within each batch; treatment-batch confounding.",
                explanation: "Any reagent, temperature, or operator difference between Monday and Friday is perfectly aligned with treatment and cannot be separated afterward.",
                hint: "Each batch currently contains only one condition.",
                decisiveStep: "Represent every treatment condition within every batch."
            )
        case (.biologicalExperiments, 2):
            problem = ConcreteOpenProblem(
                prompt: "A new fluorescent receptor assay tests an unknown compound dissolved in 1% solvent. Design three concrete controls: a negative/vehicle control, a known-active positive control, and a procedural control. State the distinct failure each control detects.",
                correctAnswer: "Use 1% solvent without compound as the negative/vehicle control to detect solvent effects; use a validated receptor agonist as the known-active positive control to show the assay can produce signal; and process a mock sample through staining and imaging as the procedural control to reveal handling or measurement artifacts.",
                acceptedAnswer: "Vehicle-only negative, validated agonist positive, and mock-handled procedural controls, each tied to its distinct failure mode.",
                explanation: "The vehicle control isolates the candidate compound, the known-active agonist tests assay sensitivity, and the mock-handled sample tests whether the procedure itself creates fluorescence. None can substitute for the other roles.",
                hint: "Ask what result would expose solvent response, assay failure, or processing artifact separately.",
                decisiveStep: "Match a concrete negative, known-active positive, and procedural control to three distinct failure questions."
            )
        case (.biologicalExperiments, 3):
            problem = ConcreteOpenProblem(
                prompt: "A microscopist knows treatment labels while classifying cells as ‘damaged’ or ‘healthy.’ State a measurement repair and its target bias.",
                correctAnswer: "Blind or mask image labels and use a prespecified classification rubric or automated threshold. This targets observer bias.",
                acceptedAnswer: "Blind image scoring; observer bias.",
                explanation: "Ambiguous morphology leaves room for expectations to affect labels. Masking condition prevents treatment knowledge from entering the measurement.",
                hint: "Change what the scorer can see besides the image.",
                decisiveStep: "Score de-identified images under a fixed rule."
            )
        case (.biologicalExperiments, 4):
            problem = ConcreteOpenProblem(
                prompt: "A study measures 500 cells from one treated mouse and 500 cells from one control mouse, then reports n=500 per group. What is the true biological n, and how should the study be repaired?",
                correctAnswer: "The biological n is one mouse per group. Add independently treated mice and analyze cells as nested measurements within mouse.",
                acceptedAnswer: "n=1 mouse per group; replicate animals and use nested analysis.",
                explanation: "Cells from one mouse share genotype, exposure, and handling. More cells improve within-mouse measurement but do not create independent treatment replications.",
                hint: "Identify the unit that independently received treatment.",
                decisiveStep: "Replicate the biological unit and nest cell measurements."
            )
        case (.biologicalExperiments, _):
            problem = ConcreteOpenProblem(
                prompt: "A signaling inhibitor is tested only at 10 µM and 30 minutes. Design a compact follow-up that distinguishes dose dependence from transient timing.",
                correctAnswer: "Use multiple doses including zero across multiple time points, with vehicle and positive controls, and test dose-by-time response rather than one endpoint.",
                acceptedAnswer: "A dose-response × time-course with vehicle and positive controls.",
                explanation: "One dose-time pair cannot reveal a threshold, toxicity reversal, delay, or transient response. Crossing dose and time separates these patterns.",
                hint: "Vary both axes currently fixed by the single observation.",
                decisiveStep: "Cross multiple doses with multiple time points."
            )
        default:
            return nil
        }

        return openProblem(request, basis: basis, problem)
    }

    private static func repairScoringTerms(
        for variant: Int,
        request: NFAuthoringRequest
    ) -> String {
        switch variant {
        case 0: "random assign|random allocation|counterexample|representative input|change one target factor|treatment"
        case 1: "baseline|block|match|interleave|multiple start|split by|batch"
        case 2: "blind|objective|known exact|property based|calibrat|confusion matrix|procedural control"
        case 3: "predeclare|sensitivity|ablation|stress interleaving|automated|primary outcome"
        case 4: "replicat|reserve new|class metric|remove feature|independent specimen|biological unit"
        default: "different population|increasing precision|reproduc|boundary|dose response|time course"
        }
    }

    private static func threatScoringTerms(
        for variant: Int,
        request: NFAuthoringRequest
    ) -> String {
        switch variant {
        case 0: "selection|confound|universal|input order|information leakage|simultaneous"
        case 1: "baseline|boundary|local optimum|dependence|temporal|batch|drift"
        case 2: "observer|algebraic|intermediate state|base rate|calibration|handling"
        case 3: "reporting|assumption|component attribution|race|measurement bias"
        case 4: "pseudoreplication|in sample|rare|target leakage|independent"
        default: "generaliz|transport|instability|environment drift|boundary behavior|dynamic"
        }
    }

    private static func experimentalDesign(_ request: NFAuthoringRequest, basis: Basis) -> NFAuthoredQuestion {
        if basis.sourceText == nil {
            return diversifiedExperimentalDesign(request, basis: basis)
        }
        let hypothesis = basis.sourceSentence.map {
            localized("Treat the cited claim “\($0)” as the hypothesis under study.", request: request)
        } ?? localized("A team wants to test a claim about \(basis.topic.lowercased()).", request: request)
        let correct = localized("Randomly assign exposure when ethical and feasible; this addresses baseline selection confounding.", request: request)
        return makeQuestion(
            request: request,
            basis: basis,
            prompt: localized("\(hypothesis) Participants currently choose exposure or control, and the same outcome is measured afterward. State the smallest design change that directly addresses baseline self-selection, plus the threat it addresses.", request: request),
            correctAnswer: correct,
            acceptedAnswers: [
                localized("Random assignment; selection confounding", request: request),
                localized("Randomize treatment allocation to reduce baseline confounding", request: request)
            ],
            explanation: localized("Self-selection can make the groups differ before exposure. Random allocation targets that path; it does not guarantee that every other bias disappears.", request: request),
            hint: localized("Change how participants enter groups, not merely how precisely the outcome is measured.", request: request),
            decisiveStep: localized("Use random allocation to block the selection path.", request: request),
            requiredTermGroups: [
                "random assign|random allocation|randomiz*|無作為|ランダム",
                "self selection|selection bias|selection confound|baseline confound|自己選択|選択バイアス|交絡"
            ],
            minimumRequiredTermMatches: 2,
            rejectedAssertionGroups: [
                "do not randomize|random assignment is invalid|keep self selection|selection is not a threat|無作為化しない"
            ]
        )
    }

    private static func diversifiedDataInterpretation(
        _ request: NFAuthoringRequest,
        basis: Basis
    ) -> NFAuthoredQuestion {
        let profile = quantitativeTopicProfile(request, basis: basis)
        let variant = basis.reasoningVariant
        let prompt: String
        let correct: String
        let explanation: String
        let decisiveStep: String
        let requiredTermGroups: [String]
        let rejectedAssertionGroups: [String]

        switch variant {
        case 0:
            let first = Double(basis.a)
            let second = first + Double(basis.b)
            let change = second - first
            prompt = localized("A \(basis.topic.lowercased()) table reports \(number(first)) then \(number(second)) \(profile.unit). Compute the signed change second − first and state what that contrast alone cannot establish.", request: request)
            correct = localized("\(number(change)); the contrast alone does not establish causation.", request: request)
            explanation = localized("The signed change is \(number(second)) − \(number(first)) = \(number(change)). A two-value contrast has no assignment or counterfactual evidence by itself.", request: request)
            decisiveStep = localized("Compute the signed difference and keep it separate from a causal claim.", request: request)
            requiredTermGroups = [
                number(change),
                "does not establish causation|does not prove causation|cannot establish a causal effect|causation is not established|no causal effect|因果関係を証明しない"
            ]
            rejectedAssertionGroups = ["proves causation|establishes causation|causation is proven|因果関係を証明する"]
        case 1:
            let first = Double(max(2, basis.a))
            let second = first + Double(basis.b)
            let percent = 100 * (second - first) / first
            prompt = localized("A \(basis.topic.lowercased()) measure rises from \(number(first)) to \(number(second)) \(profile.unit). Compute the percentage change relative to the first value, and name the denominator.", request: request)
            correct = localized("\(number(percent))%; the denominator is the first value, \(number(first)).", request: request)
            explanation = localized("Relative change is (second − first) ÷ first × 100 = \(number(percent))%.", request: request)
            decisiveStep = localized("Use the first value as the percentage-change denominator.", request: request)
            requiredTermGroups = [number(percent), "first value|baseline|denominator|最初の値|分母"]
            rejectedAssertionGroups = []
        case 2:
            let intervals = Double(max(2, basis.b))
            let count = Double(basis.a) * intervals
            let rate = count / intervals
            prompt = localized("A \(basis.topic.lowercased()) table records \(number(count)) \(profile.unit) over \(number(intervals)) \(profile.interval)s. Compute the mean rate and state its denominator.", request: request)
            correct = localized("\(number(rate)) \(profile.unit) per \(profile.interval); the denominator is \(number(intervals)) \(profile.interval)s.", request: request)
            explanation = localized("Rate keeps the exposure interval in the denominator: \(number(count)) ÷ \(number(intervals)) = \(number(rate)).", request: request)
            decisiveStep = localized("Divide the count by its stated exposure interval.", request: request)
            requiredTermGroups = [number(rate), "per \(profile.interval)|denominator|interval|あたり|分母"]
            rejectedAssertionGroups = []
        case 3:
            let numerator = Double(basis.a * basis.b)
            let denominator = Double(basis.b)
            let ratio = numerator / denominator
            prompt = localized("Two \(basis.topic.lowercased()) categories contain \(number(numerator)) and \(number(denominator)) \(profile.unit). Compute the first-to-second ratio and explain what is held in the denominator.", request: request)
            correct = localized("\(number(ratio)) to 1; the second category is the denominator.", request: request)
            explanation = localized("The requested order is first ÷ second: \(number(numerator)) ÷ \(number(denominator)) = \(number(ratio)).", request: request)
            decisiveStep = localized("Preserve the requested first-to-second ratio order.", request: request)
            requiredTermGroups = [number(ratio), "second category|denominator|first to second|分母|第2"]
            rejectedAssertionGroups = []
        case 4:
            let first = Double(basis.a)
            let second = Double(basis.a + basis.b)
            let mean = (2 * first + 3 * second) / 5
            prompt = localized("For \(basis.topic.lowercased()), two runs average \(number(first)) and three runs average \(number(second)) \(profile.unit). Compute the pooled mean and explain why an unweighted mean of the two displayed means is wrong.", request: request)
            correct = localized("\(number(mean)); weight each mean by its run count.", request: request)
            explanation = localized("The pooled mean is [2 × \(number(first)) + 3 × \(number(second))] ÷ 5 = \(number(mean)); the groups have unequal sizes.", request: request)
            decisiveStep = localized("Weight each displayed mean by its run count.", request: request)
            requiredTermGroups = [number(mean), "weight|run count|unequal size|加重|回数"]
            rejectedAssertionGroups = []
        default:
            let estimate = Double(basis.a)
            let margin = Double(max(1, basis.b / 2))
            let low = estimate - margin
            let high = estimate + margin
            prompt = localized("A \(basis.topic.lowercased()) estimate is \(number(estimate)) \(profile.unit) with uncertainty interval [\(number(low)), \(number(high))]. State the interval width and whether the interval means every value inside is equally likely.", request: request)
            correct = localized("Width \(number(high - low)); no, an interval does not state equal likelihood for every included value.", request: request)
            explanation = localized("Width is upper − lower = \(number(high)) − \(number(low)) = \(number(high - low)). The interval endpoints alone do not define a probability distribution within the range.", request: request)
            decisiveStep = localized("Subtract interval endpoints and do not invent a within-interval distribution.", request: request)
            requiredTermGroups = [number(high - low), "not equally likely|does not state equal|no probability distribution|等確率ではない|分布を示さない"]
            rejectedAssertionGroups = ["every value is equally likely|uniformly distributed|すべて等確率"]
        }

        return makeQuestion(
            request: request,
            basis: basis,
            prompt: prompt,
            correctAnswer: correct,
            explanation: explanation,
            hint: localized("Write the requested numerator and denominator or endpoints before calculating.", request: request),
            decisiveStep: decisiveStep,
            requiredTermGroups: requiredTermGroups,
            minimumRequiredTermMatches: 2,
            rejectedAssertionGroups: rejectedAssertionGroups
        )
    }

    private static func dataInterpretation(_ request: NFAuthoringRequest, basis: Basis) -> NFAuthoredQuestion {
        if let pair = sourceNumericPair(in: basis) {
            let change = pair.second - pair.first
            let measure = pair.measureLabel.map { " (\($0))" } ?? ""
            let correct = localized("The signed change is \(number(change)); this two-observation contrast alone does not establish causation.", request: request)
            return makeQuestion(
                request: request,
                basis: basis,
                prompt: localized("In the cited table, \(pair.firstLabel)\(measure) is \(number(pair.first)) and \(pair.secondLabel)\(measure) is \(number(pair.second)). Compute second − first, then state whether this two-observation contrast alone establishes causation.", request: request),
                correctAnswer: correct,
                acceptedAnswers: [
                    localized("\(number(change)); causation is not established", request: request),
                    localized("\(number(change)); the table does not prove a causal effect", request: request)
                ],
                explanation: localized("The signed difference is \(number(pair.second)) − \(number(pair.first)) = \(number(change)). The labels support that arithmetic comparison, but two observations alone do not identify a causal effect.", request: request),
                hint: localized("Compute in the labeled order, then separate numerical contrast from causal evidence.", request: request),
                decisiveStep: localized("Calculate the labeled contrast without upgrading it to a causal claim.", request: request),
                requiredTermGroups: [
                    number(change),
                    "does not establish causation|does not prove causation|cannot establish a causal effect|causation is not established|no causal effect|association only|因果関係を証明しない|因果は確立されない"
                ],
                minimumRequiredTermMatches: 2,
                rejectedAssertionGroups: [
                    "proves causation|establishes causation|demonstrates a causal effect|causation is proven|因果関係を証明する"
                ]
            )
        }
        if basis.sourceText != nil {
            let correct = localized("No signed change is defined because the excerpt does not label the values as comparable observations of one measure.", request: request)
            return makeQuestion(
                request: request,
                basis: basis,
                prompt: localized("The cited excerpt does not contain a labeled row, column, or repeated measure. Explain why subtracting its first two numeric tokens would not be a defensible data interpretation.", request: request),
                correctAnswer: correct,
                acceptedAnswers: [
                    localized("The values are not labeled as comparable, so a signed change is not defined.", request: request)
                ],
                explanation: localized("Numbers that refer to different quantities cannot be turned into a change score merely because they appear in sequence.", request: request),
                hint: localized("Ask whether both values measure the same thing on a stated comparison axis.", request: request),
                decisiveStep: localized("Require a labeled comparison before computing a change.", request: request),
                requiredTermGroups: [
                    "not comparable|different quantities|no labeled comparison|not the same measure|比較できない|異なる量|ラベルがない",
                    "signed change is not defined|cannot subtract|do not subtract|change score is undefined|差は定義できない|引けない"
                ],
                minimumRequiredTermMatches: 2,
                rejectedAssertionGroups: [
                    "subtract the first two|first number minus the second|second minus first is valid|最初の2つを引く"
                ]
            )
        }
        return diversifiedDataInterpretation(request, basis: basis)
    }

    private struct ConcreteDataProblem {
        let prompt: String.LocalizationValue
        let correctAnswer: String.LocalizationValue
        let explanation: String.LocalizationValue
        let hint: String.LocalizationValue
        let decisiveStep: String.LocalizationValue
    }

    private static func semanticDataProblem(
        _ request: NFAuthoringRequest,
        basis: Basis
    ) -> NFAuthoredQuestion? {
        func p(
            _ prompt: String.LocalizationValue,
            _ answer: String.LocalizationValue,
            _ explanation: String.LocalizationValue,
            _ hint: String.LocalizationValue,
            _ step: String.LocalizationValue
        ) -> ConcreteDataProblem {
            ConcreteDataProblem(
                prompt: prompt,
                correctAnswer: answer,
                explanation: explanation,
                hint: hint,
                decisiveStep: step
            )
        }

        let problems: [ConcreteDataProblem]
        switch semanticTopic(request, basis: basis) {
        case .dataLiteracy:
            problems = [
                p("A table reports 42 responses in group A and 30 in group B. Compute A−B and state whether this count difference alone establishes causation.", "12; no, the count difference alone does not establish causation.", "The signed contrast is 42−30=12. Without assignment or a counterfactual design, the table supplies association rather than a causal effect.", "Keep the arithmetic contrast separate from the study-design claim.", "Subtract B from A, then bound the interpretation."),
                p("A bar chart’s vertical axis spans 90 to 99, and the two bars end at 96 and 99. Compute the actual value difference and explain why the cropped axis can exaggerate it visually.", "The difference is 3; on the stated 90-to-99 display, that 3-unit gap occupies one third of the full plotted height.", "Reading endpoints gives 99−96=3. The plotted range is only 9 units, so truncating the baseline makes this small absolute contrast consume 3/9 of the display.", "Read both axis limits and the bar endpoints.", "Compute from labeled endpoints and compare the gap with the stated plotted range."),
                p("A survey proportion is 0.62 with a 95% interval [0.56, 0.68]. State the interval width and whether 0.50 is included.", "Width 0.12; 0.50 is not included.", "Interval width is 0.68−0.56=0.12. Because 0.50 lies below the lower endpoint, it is outside the reported interval.", "Compare the reference value with both endpoints.", "Subtract endpoints and locate 0.50 relative to the interval."),
                p("Two groups have means 10 (n=20) and 16 (n=10). Compute the pooled mean across all 30 observations.", "12", "The total is 20×10+10×16=360; dividing by 30 gives 12. Averaging 10 and 16 equally would ignore unequal group sizes.", "Weight each mean by its sample size.", "Compute the sample-size-weighted mean."),
                p("A rate rises from 8 per 100 to 12 per 100. Report both the absolute percentage-point change and the relative percent increase.", "4 percentage points and 50% relative increase.", "Absolute change is 12−8=4 percentage points. Relative increase uses the baseline denominator: 4/8×100=50%.", "Do not confuse percentage points with percent change.", "Compute the same numerator with two different reporting scales."),
                p("A scatterplot shows correlation r=−0.80 between outdoor temperature and heating use. State the direction/strength and one conclusion the correlation cannot establish.", "A strong negative linear association; it cannot by itself establish that changing temperature causes the observed heating-use change.", "The sign gives direction and |r|=0.80 indicates a strong linear pattern. Correlation alone does not eliminate confounding or identify an intervention effect.", "Interpret the coefficient before making a causal claim.", "Separate linear association from causation.")
            ]

        case .wavesOscillations:
            problems = [
                p("A wave completes 24 cycles in 6 s. Compute its frequency and period.", "Frequency 4 Hz; period 0.25 s.", "Frequency is cycles/time=24/6=4 Hz, and period is its reciprocal T=1/4=0.25 s.", "Frequency and period are reciprocals.", "Compute f=N/t, then T=1/f."),
                p("A wave travels at 12 m/s with frequency 3 Hz. Compute its wavelength.", "4 m", "The wave relation v=fλ gives λ=v/f=12/3=4 m.", "Solve v=fλ for wavelength.", "Divide speed by frequency."),
                p("At x=0, two equal-frequency signals reach maxima at t=0 and t=0.25 s; their period is 1.0 s. Compute the smaller phase separation in degrees.", "90°", "A quarter-period separation corresponds to 0.25/1.0×360°=90°.", "Express the time offset as a fraction of one period.", "Convert |Δt|/T to a phase-separation magnitude."),
                p("An oscillator’s amplitude falls from 10 mm to 6 mm over 2 s. Compute the signed amplitude change and mean change per second.", "−4 mm; −2 mm/s.", "Signed change is 6−10=−4 mm. Dividing by 2 s gives −2 mm/s over this interval.", "Preserve the final-minus-initial sign.", "Compute ΔA and then ΔA/Δt."),
                p("A standing wave on a 1.2 m string has consecutive nodes at 0, 0.6, and 1.2 m, with no other nodes between them. What wavelength does this pattern represent?", "1.2 m", "Adjacent nodes are separated by λ/2. Their 0.6 m spacing gives λ=2×0.6=1.2 m.", "Use the spacing between consecutive nodes.", "Double the adjacent-node spacing."),
                p("A wave is $$y(x,t)=A\\cos(kx-\\omega t+\\phi).$$ At t=0, increasing φ by π/2 shifts the graph horizontally. State the shift as a fraction of wavelength and name one feature that remains invariant.", "The graph shifts left by λ/4 because Δx=−(π/2)/k=−λ/4; amplitude A and wavelength λ remain unchanged.", "A phase change alters where peaks appear in the chosen coordinate view but does not change the oscillation’s amplitude or spatial period. Substituting k=2π/λ gives the quarter-wavelength translation.", "Hold the cosine argument constant while φ changes.", "Translate equation phase into graph displacement and preserve amplitude and wavelength.")
            ]

        case .measurementUncertainty:
            problems = [
                p("Five length measurements are 10.1, 10.2, 10.0, 10.1, and 10.1 cm. Compute the mean.", "10.1 cm", "The sum is 50.5 cm; dividing by five gives a mean of 10.1 cm.", "Add all measurements before dividing by count.", "Compute the arithmetic mean."),
                p("A proposed formula for speed is v=d+t, where d is distance and t is time. Is it dimensionally valid, and what familiar relation has the correct dimensions?", "No. Length and time cannot be added; v=d/t has dimension length/time.", "Dimensional addition requires identical dimensions. Dividing distance by time produces the required speed dimension, whereas d+t is invalid before any numbers are substituted.", "Compare dimensions on both sides, not just numerical magnitudes.", "Reject d+t and restore the length-per-time relation d/t."),
                p("A result is reported as 12.0 ± 0.3 mm. State the implied interval and its full width.", "[11.7, 12.3] mm; width 0.6 mm.", "Subtract and add 0.3 to obtain endpoints; the full span is 12.3−11.7=0.6 mm.", "The ± value is half the total width.", "Construct both endpoints before computing width."),
                p("Independent standard uncertainties are 3 N and 4 N. Combine them by root-sum-square.", "5 N", "For independent components, u=√(3²+4²)=√25=5 N.", "Square components before adding.", "Use root-sum-square, not ordinary addition."),
                p("A speed is calculated as 20.0 m / 4.0 s. Compute the speed and state its physical unit.", "5.0 m/s", "Dividing distance by time gives 20.0/4.0=5.0, and dimensional division gives metres per second.", "Carry units through the quotient.", "Divide both values and dimensions."),
                p("Two instruments repeatedly read 9.99, 10.00, 10.01 and 9.50, 10.00, 10.50 for a 10.00 reference. Which is more precise, and why?", "The first instrument is more precise because its readings have much smaller spread.", "Precision concerns repeatability, not just mean accuracy. Both center near 10.00, but the first cluster spans only 0.02 versus 1.00.", "Compare spread rather than only average.", "Use repeated-reading dispersion to judge precision.")
            ]

        case .controlSystems:
            problems = [
                p("After a small positive output disturbance, controller A changes its command downward while controller B changes its command upward. Which controller implements negative feedback, and what would B’s sign tend to do?", "Controller A implements negative feedback; controller B reinforces the disturbance and tends toward positive-feedback growth or instability.", "Negative feedback drives against an output deviation, whereas positive feedback acts in the same direction and amplifies it. Tracing the perturbation sign distinguishes the loops without relying on a nominal setpoint subtraction.", "Follow the sign of the corrective command after a positive disturbance.", "Identify the loop that opposes the perturbation and diagnose the reinforcing sign."),
                p("A first-order step response reaches 63% of its final change at t=2 s. Estimate its time constant.", "2 s", "For a first-order system, the response reaches about 63.2% after one time constant, so τ≈2 s.", "Recall the one-time-constant benchmark.", "Map 63% response time to τ."),
                p("A response peaks at 12 for a final value of 10. Compute percent overshoot.", "20%", "Percent overshoot=(12−10)/10×100=20%.", "Use the final value as baseline.", "Divide peak excess by final value."),
                p("A proportional controller has gain Kp=4 and error e=1.5. Compute controller output u=Kp e.", "6", "The proportional law gives u=4×1.5=6.", "Multiply gain by error.", "Evaluate the proportional control law."),
                p("A unit-step command produces steady output 0.92. Compute steady-state error using e_ss=1−y_ss.", "0.08", "The remaining offset is 1−0.92=0.08.", "Compare final output with the unit reference.", "Subtract steady output from reference."),
                p("A block diagram has plant P(s)=1/(s+1), unity negative feedback, and controller gain K=3. Form the closed-loop transfer function T(s)=KP/(1+KP) and identify its steady-state gain.", "T(s)=3/(s+4), with steady-state gain T(0)=3/4=0.75.", "Substituting P into the negative-feedback closure gives [3/(s+1)]/[1+3/(s+1)]=3/(s+4). Evaluating at s=0 connects the block diagram to its final-value scale.", "Use the negative-feedback denominator 1+KP before simplifying.", "Map the block diagram to T=KP/(1+KP), simplify, and evaluate T(0).")
            ]

        case .signalsSampling:
            problems = [
                p("Using the stated ideal lower-bound rule fs≥2fmax, a signal contains a highest frequency of 40 Hz. What minimum sampling rate does the rule give?", "80 Hz", "The stated lower bound is 2×40=80 Hz. Practical reconstruction may require margin above this ideal boundary.", "Double the maximum frequency under the stated rule.", "Apply the supplied lower-bound formula fs≥2fmax."),
                p("A 90 Hz sinusoid is sampled at 120 samples/s. What first-zone alias frequency appears?", "30 Hz", "The Nyquist limit is 60 Hz, and |90−120|=30 Hz is the folded frequency.", "Fold around the sampling rate into [0,60].", "Compute |f−fs|."),
                p("Samples are taken every 0.002 s. Compute the sampling frequency.", "500 Hz", "Sampling frequency is the reciprocal interval: 1/0.002=500 Hz.", "Convert a time interval into a rate.", "Take the reciprocal of sample spacing."),
                p("A filter changes amplitude from 2.0 V to 0.5 V at one frequency. Compute the linear gain.", "0.25", "Gain magnitude is output/input=0.5/2.0=0.25.", "Output belongs in the numerator.", "Divide output amplitude by input amplitude."),
                p("A four-second acquisition window records at 250 samples/s and contains 1,000 sample bins. Verify the window duration by count/rate, not the first-to-last timestamp span.", "4 s", "Under the stated acquisition-window/sample-bin convention, duration=sample count/sampling rate=1000/250=4 s. The first and last timestamps span one sample interval less, which is a different convention.", "Use the acquisition-window convention stated in the prompt.", "Divide 1,000 sample bins by 250 samples/s."),
                p("A measured signal contains a desired 10 Hz component and additive 200 Hz noise. A proposed low-pass filter has a 50 Hz cutoff. Which component should it preserve, which should it attenuate, and what misuse would occur if the cutoff were set to 5 Hz?", "The 50 Hz low-pass should preserve the 10 Hz signal and attenuate the 200 Hz noise. A 5 Hz cutoff would also suppress the desired 10 Hz component.", "A low-pass filter separates components by frequency, not by whether we call them signal or noise. Its cutoff must remain above the desired band and below the unwanted high-frequency component.", "Place both component frequencies relative to the cutoff.", "Check passband and stopband against both desired signal and noise.")
            ]

        case .materialsFailure:
            problems = [
                p("A 20 kN tensile load acts on a 400 mm² specimen. Compute engineering stress in MPa.", "50 MPa", "20 kN=20,000 N; σ=F/A=20,000/400=50 N/mm²=50 MPa.", "Convert kilonewtons to newtons.", "Divide force by original area."),
                p("A 100 mm gauge length extends to 100.8 mm. Compute engineering strain.", "0.008", "Strain=(100.8−100)/100=0.8/100=0.008.", "Use original length in the denominator.", "Compute ΔL/L₀."),
                p("In the linear region, stress rises from 0 to 200 MPa as strain rises from 0 to 0.001. Estimate Young’s modulus in GPa.", "200 GPa", "E=σ/ε=200 MPa/0.001=200,000 MPa=200 GPa.", "Convert MPa to GPa after dividing.", "Use the elastic stress-strain slope."),
                p("A crack grows from 2.0 mm to 2.6 mm over 3,000 cycles. Compute mean crack-growth rate in mm/cycle.", "0.0002 mm/cycle", "Growth is 0.6 mm; 0.6/3000=0.0002 mm per cycle.", "Use crack extension, not final length.", "Divide Δa by cycle count."),
                p("Failed shafts show either cracks starting at surface notches or void-driven cracks starting in the bulk. Design a test that discriminates these competing failure mechanisms.", "Use matched shafts with notch severity varied independently of bulk porosity, fatigue-test randomized replicates at the same stress, and use sectioning/fractography to record crack-initiation location. A notch effect with surface origins supports stress concentration; a porosity effect with internal origins supports the void mechanism.", "Changing one candidate cause at a time while holding stress and material batch fixed separates their effects. Origin imaging supplies mechanism-specific evidence rather than only another lifetime comparison.", "Vary notch and porosity independently and observe where each crack begins.", "Use a controlled factorial comparison plus fractography to discriminate surface and bulk initiation."),
                p("Specimen A survives 10⁶ cycles at 180 MPa; specimen B survives 10⁵ cycles at 220 MPa. Can these two observations alone establish that A has better fatigue resistance?", "No. The stress amplitudes differ, so compare specimens at the same stress or compare controlled S–N curves.", "Cycle life depends strongly on stress amplitude. Because material identity and applied stress both change, the two observations cannot isolate material fatigue resistance.", "Ask whether stress amplitude was held fixed.", "Reject the confounded material comparison and require a controlled S–N comparison." )
            ]

        case .reactionKinetics:
            problems = [
                p("When [A] doubles from 0.10 M to 0.20 M at fixed conditions, rate rises from 2.0 to 8.0 mM/s. Determine the order in A.", "Second order", "Rate ratio 8/2=4 while concentration ratio is 2; because 2ⁿ=4, n=2.", "Compare rate and concentration ratios.", "Solve 2ⁿ=4."),
                p("A first-order reaction has k=0.20 min⁻¹ and [A]=0.50 M. Compute the instantaneous rate k[A].", "0.10 M/min", "For first order, rate=0.20×0.50=0.10 M/min.", "Multiply rate constant by concentration.", "Apply rate=k[A]."),
                p("A first-order process has k=0.35 min⁻¹. Compute its half-life using t₁/₂=0.693/k.", "1.98 min", "t₁/₂=0.693/0.35=1.98 min.", "Put k in the denominator.", "Evaluate 0.693/k."),
                p("At 300 K a rate is 1.2 units; at 320 K it is 2.4 units under otherwise identical conditions. Compute the rate ratio and state the observed temperature effect.", "Ratio 2; the rate doubles over this interval.", "2.4/1.2=2. This is an empirical interval comparison, not by itself a complete Arrhenius parameter estimate.", "Divide the higher-temperature rate by the lower.", "Compute the rate ratio and bound the interpretation."),
                p("Initial-rate trials differ in both [A] and temperature. Can their rate ratio identify reaction order in A?", "No; temperature is a confounder, so compare trials where temperature and other reactants are fixed.", "Reaction-order inference requires isolating one concentration change. A simultaneous temperature change can alter k and therefore the observed rate ratio.", "Look for variables besides [A] that changed.", "Require a controlled row pair before solving an exponent."),
                p("Initial-rate data at fixed temperature fit rate=k[A]². State the empirical order in A and whether that exponent alone proves a single elementary collision of two A molecules.", "Second order in A; no, an empirical rate law alone does not establish the elementary mechanism.", "The exponent 2 describes how the observed rate changes with concentration under the tested conditions. Multiple-step mechanisms can produce the same rate law, so molecularity requires independent mechanistic evidence.", "Separate an observed rate-law exponent from an elementary-step claim.", "Identify the second-order law while rejecting the unsupported mechanism inference." )
            ]

        case .epidemiology:
            problems = [
                p("Among 200 exposed people, 30 develop disease; among 300 unexposed, 15 develop disease. Compute the risk ratio.", "3", "Exposed risk=30/200=0.15; unexposed risk=15/300=0.05; ratio=0.15/0.05=3.", "Compute each group risk before dividing.", "Divide exposed risk by unexposed risk."),
                p("A diagnostic test finds 90 positives among 100 diseased people. Compute sensitivity.", "0.90", "Sensitivity=TP/(TP+FN)=90/100=0.90.", "Condition on people who truly have disease.", "Use actual diseased cases as the denominator."),
                p("A test is negative for 180 of 200 people without disease. Compute specificity.", "0.90", "Specificity=TN/(TN+FP)=180/200=0.90.", "Condition on people who truly do not have disease.", "Use actual non-diseased cases as the denominator."),
                p("In 1,000 people, prevalence is 10%, sensitivity is 80%, and specificity is 90%. Convert these rates to expected true-positive and false-positive natural frequencies.", "80 true positives and 90 false positives.", "There are 100 diseased people, giving 0.80×100=80 true positives. Among 900 without disease, the 10% false-positive rate gives 90 false positives.", "Split the population by disease status before applying test rates.", "Translate prevalence, sensitivity, and specificity into natural-frequency counts."),
                p("An online health survey is advertised only in a disease-support forum, and 30% of respondents report the disease. Can that percentage estimate population prevalence? Name the main threat and a repair.", "No. Voluntary recruitment from a disease-support forum creates selection bias; sample from a defined population frame with probability-based recruitment or calibrated weighting.", "People who see and choose this survey are unusually connected to the disease, so the respondent denominator is not representative of the target population. A larger convenience sample would not remove that selection path.", "Ask who had a chance to enter the respondent denominator.", "Diagnose selection bias before interpreting the sample proportion as prevalence."),
                p("A screening test keeps sensitivity and specificity fixed, but disease prevalence drops sharply. What generally happens to positive predictive value?", "It decreases.", "With lower prevalence, true positives become rarer relative to false positives, so a smaller fraction of positive results are true disease.", "Think about the composition of the positive-test denominator.", "Relate PPV to the base rate." )
            ]

        case .ecology:
            problems = [
                p("Five equal quadrats contain 4, 6, 5, 7, and 3 plants. Compute mean abundance per quadrat.", "5 plants per quadrat", "Total abundance is 25; 25/5=5 plants per quadrat.", "Add counts across all equal-area quadrats.", "Compute total count divided by quadrat count."),
                p("A population follows Nₜ₊₁=Nₜ+0.50Nₜ(1−Nₜ/200). Starting at Nₜ=100, compute Nₜ₊₁ and explain why growth must slow as N approaches 200.", "Nₜ₊₁=125. The increment is 0.50×100×(1−100/200)=25; as N approaches carrying capacity 200, the factor (1−N/200) approaches zero, so growth slows.", "This discrete logistic update combines current abundance with density dependence. Checking N=200 gives zero increment, which establishes the stated boundary behavior.", "Evaluate the density-dependent factor before adding the increment.", "Compute the discrete update and verify the carrying-capacity boundary."),
                p("A mark-recapture study marks 40 animals. A later sample catches 50, including 10 marked. Estimate population size using N≈MC/R.", "200", "N≈40×50/10=200 animals.", "Marked recaptures belong in the denominator.", "Evaluate MC/R."),
                p("Across six monthly surveys, rainfall is [20, 80, 25, 85, 30, 90] mm and algal biomass is [5, 6, 18, 7, 20, 8] g/m². What lag pattern is visible, and what can this time series not establish by itself?", "High algal biomass follows the high-rainfall months by about one month: peaks at months 3 and 5 follow rainfall peaks at months 2 and 4. This lagged association suggests a delayed forcing hypothesis but cannot establish rainfall causation without ruling out seasonal or interacting drivers.", "Using all time points reveals a repeated one-month lag that two endpoints would hide. Temporal order is useful evidence, but the observational sequence alone does not isolate the mechanism.", "Compare each biomass peak with rainfall in the preceding month.", "Identify the repeated lag while separating pattern from a causal conclusion."),
                p("A population follows the discrete model Nₜ₊₁=Nₜ+0.50Nₜ(1−Nₜ/200). If Nₜ=240, compute the next value and explain what the sign of the increment means.", "Nₜ₊₁=216. The increment is 0.50×240×(1−240/200)=−24, so abundance declines toward the carrying capacity rather than growing without bound.", "Above K=200, the density factor is negative. This boundary check tests the model’s feedback direction outside the usual below-capacity example.", "Evaluate 1−240/200 before interpreting the increment.", "Use the above-capacity boundary to interpret negative density-dependent growth."),
                p("A population declines during drought while a competitor expands. Design a compact field experiment that distinguishes direct environmental forcing from a competitor interaction.", "Use a crossed factorial design with drought versus normal moisture and competitor present versus removed across randomized replicated plots; a drought main effect supports forcing, while a drought-by-competitor interaction shows that competition changes the drought response.", "Varying both candidate causes independently prevents either from being a proxy for the other. The interaction term directly tests whether the competitor modifies sensitivity to environmental forcing.", "Cross the environmental condition with competitor presence.", "Use randomized replicated drought × competitor plots and interpret the interaction." )
            ]

        case .classifierEvaluation:
            problems = [
                p("A classifier has TP=40 and FP=10. Compute precision.", "0.80", "Precision=TP/(TP+FP)=40/50=0.80.", "Condition on predicted positives.", "Use TP+FP in the denominator."),
                p("A classifier has TP=40 and FN=20. Compute recall.", "0.667", "Recall=TP/(TP+FN)=40/60≈0.667.", "Condition on actual positives.", "Use TP+FN in the denominator."),
                p("Precision is 0.80 and recall is 0.50. Compute F1=2PR/(P+R).", "0.615", "F1=2×0.80×0.50/(0.80+0.50)=0.80/1.30≈0.615.", "Use the harmonic mean formula.", "Evaluate 2PR/(P+R)."),
                p("A dataset has 990 negatives and 10 positives. A model predicts every case negative. Compute accuracy and recall for the positive class.", "Accuracy 0.99; recall 0.", "The model gets 990/1000 correct but finds 0/10 positives. High accuracy therefore hides total positive-class failure.", "Compute the two denominators separately.", "Contrast aggregate accuracy with positive recall."),
                p("On the same labeled dataset, lowering a classification threshold changes TP from 50 to 70 and FP from 10 to 30; the actual-positive count is fixed. State the changes in recall direction and false positives.", "Recall increases, and false positives increase by 20.", "With the actual-positive denominator fixed, more true positives mean higher recall; FP rises from 10 to 30, an increase of 20.", "Track the fixed actual-positive denominator and FP separately.", "Interpret the threshold tradeoff on the same labeled cases."),
                p("A model has TPR=0.80 and FPR=0.20 at one threshold. Compute Youden’s J=TPR−FPR.", "0.60", "J=0.80−0.20=0.60.", "Keep rates in the displayed order.", "Subtract false-positive rate from true-positive rate." )
            ]

        case .statisticalInference:
            problems = [
                p("A sample mean is 50 with standard error 2. Using estimate ±1.96SE, compute the 95% confidence interval.", "[46.08, 53.92]", "Margin=1.96×2=3.92, so endpoints are 50−3.92 and 50+3.92.", "Compute the margin before endpoints.", "Apply estimate ±1.96SE."),
                p("A 95% confidence interval for a mean difference is [1.2,4.8]. Using the corresponding two-sided 5% test under the same model and method, does the interval include 0 and what conclusion follows?", "It excludes 0; the matching two-sided procedure rejects the zero-difference null at the 5% level.", "Every value in the interval is positive, so zero is not among parameter values compatible with this interval procedure. The test conclusion follows because the prompt explicitly pairs corresponding interval and test methods.", "Locate the null value relative to both endpoints.", "Use interval exclusion only for the stated matching test procedure."),
                p("A test reports p=0.03. Under α=0.05, what is the decision, and what does p=0.03 not mean?", "Reject the null; p=0.03 does not mean the null has a 3% probability of being true.", "The p-value is below the prespecified threshold and describes data extremity under the null, not a posterior probability of the null.", "Compare p with α before interpreting its definition.", "Make the decision without converting p into P(null)."),
                p("The same 30 patients are measured before and after treatment, but an analyst applies an independent-groups test to the 60 measurements. Which assumption is violated, and what analysis matches the design?", "The independence assumption is violated because each before/after pair comes from one patient; analyze within-patient differences with a paired method.", "Repeated measurements on one patient share patient-level variation and are not independent observations. Pairing models that dependence and tests the change within each patient.", "Identify the unit observed twice.", "Match the analysis to paired observations rather than pretending there are 60 independent units."),
                p("A huge study estimates a mean difference of 0.10 units with 95% CI [0.08,0.12] and p<0.001. What is statistically established, and what remains a separate judgment?", "The data establish a precisely estimated nonzero effect under the model, but whether a 0.10-unit effect is practically important remains a domain judgment.", "Large samples can make small effects statistically distinguishable from zero. The confidence interval quantifies effect size and precision; the p-value alone does not make that magnitude useful or important.", "Separate evidence against zero from the value of the effect’s magnitude.", "Interpret effect size and statistical significance as different questions."),
                p("A study tests 20 independent hypotheses at α=0.05 with no multiplicity correction, and all 20 null hypotheses are true. What is the expected number of false positives?", "1", "With every null true, each test has false-positive probability 0.05, so the expected count is mα=20×0.05=1.", "Multiply the true-null test count by its per-test false-positive rate.", "Compute mα under the stated all-null-true condition." )
            ]

        case .regression:
            problems = [
                p("A regression coefficient for hours studied is 2.5 score points/hour, holding prior score fixed. Interpret a 3-hour difference.", "The model predicts 7.5 more score points for a 3-hour increase, conditional on the same prior score.", "Multiply 2.5×3=7.5 and preserve the holding-prior-score-fixed condition; the coefficient is not automatically causal.", "Carry both units and conditioning into the interpretation.", "Scale the conditional coefficient by 3 hours."),
                p("Observed outcomes are 10, 14, 13 and predictions are 9, 15, 11. Compute residuals observed−predicted.", "[1, −1, 2]", "Residuals are 10−9=1, 14−15=−1, and 13−11=2.", "Use observed minus predicted for every row.", "Subtract predictions in row order."),
                p("A fitted model predicts energy use in kWh/day as y=4+2x, where x is occupied hours/day, for otherwise comparable buildings in the training range. Interpret the slope with units and predict y at x=5 without making a causal claim.", "The slope predicts 2 additional kWh/day per additional occupied hour/day among otherwise comparable in-range buildings; at x=5, y=14 kWh/day. The observational coefficient alone is not causal.", "Substitution gives 4+2×5=14 kWh/day, but a useful interpretation also preserves the conditioning, units, range, and noncausal status of the fitted association.", "State what one x-unit means before substituting.", "Carry slope units and conditioning into the 14 kWh/day prediction."),
                p("A model is y=1+2x+3z+4xz. What is the marginal effect of x when z=2?", "10", "The x effect is ∂y/∂x=2+4z; at z=2 it is 2+8=10.", "Include the interaction contribution.", "Evaluate βx+βxz z."),
                p("Residuals grow in spread as fitted values increase. Name the pattern and one appropriate response.", "Heteroskedasticity; use heteroskedasticity-robust standard errors or model the variance.", "A fan-shaped residual plot violates constant error variance. Robust inference or an explicit variance model addresses uncertainty, not the coefficient fit by itself.", "Focus on changing spread, not mean trend.", "Diagnose nonconstant variance from the residual fan."),
                p("An observational regression links umbrella sales with traffic crashes. Rainfall affects both. What role does rainfall play, and why is the sales coefficient not causal by itself?", "Rainfall is a confounder; without controlling or designing around it, the umbrella-sales coefficient mixes rainfall’s common influence with any direct relation.", "A common cause creates association even if umbrella purchases do not cause crashes. Predictive fit cannot identify the intervention effect.", "Draw arrows from rainfall to both variables.", "Identify the shared cause before interpreting the coefficient." )
            ]

        default:
            return nil
        }

        let problem = problems[basis.reasoningVariant]
        return makeQuestion(
            request: request,
            basis: basis,
            prompt: localized(problem.prompt, request: request),
            correctAnswer: localized(problem.correctAnswer, request: request),
            explanation: localized(problem.explanation, request: request),
            hint: localized(problem.hint, request: request),
            decisiveStep: localized(problem.decisiveStep, request: request)
        )
    }

    private static func spatialTransformation(_ request: NFAuthoringRequest, basis: Basis) -> NFAuthoredQuestion {
        let x = basis.sourceSentence == nil ? basis.a - 5 : (basis.wordCount % 7) + 1
        let y = basis.b - 4
        if basis.sourceText == nil {
            let representation: String = switch request.field {
            case .general: localized("diagram anchor", request: request)
            case .mathematics: localized("vector", request: request)
            case .physics: localized("phase-space point", request: request)
            case .computing: localized("grid state", request: request)
            case .engineering: localized("model coordinate", request: request)
            case .lifeSciences: localized("pathway-layout node", request: request)
            case .chemistry: localized("state-space coordinate", request: request)
            case .dataScience: localized("embedding point", request: request)
            }
            let topic = basis.topic.lowercased()
            let leadingRepresentationWord = String(
                representation.prefix { $0.isLetter || $0.isNumber }
            )
            let displayTopic = leadingRepresentationWord.isEmpty
                ? topic
                : topicWithoutTrailingQualifier(topic, qualifier: leadingRepresentationWord)
            let answer: String
            let operation: String
            let rule: String
            switch basis.reasoningVariant {
            case 0:
                answer = "(\(-y), \(x))"
                operation = localized("rotate it 90° counterclockwise about the origin", request: request)
                rule = localized("(x, y) → (−y, x)", request: request)
            case 1:
                answer = "(\(-x), \(y))"
                operation = localized("reflect it across the y-axis", request: request)
                rule = localized("(x, y) → (−x, y)", request: request)
            case 2:
                let dx = 2
                let dy = -3
                answer = "(\(x + dx), \(y + dy))"
                operation = localized("translate it by vector (2, −3)", request: request)
                rule = localized("(x, y) → (x + 2, y − 3)", request: request)
            case 3:
                answer = "(\(-x), \(-y))"
                operation = localized("rotate it 180° about the origin", request: request)
                rule = localized("(x, y) → (−x, −y)", request: request)
            case 4:
                answer = "(\(2 * x), \(y))"
                operation = localized("apply a horizontal scale factor of 2 while leaving the vertical coordinate unchanged", request: request)
                rule = localized("(x, y) → (2x, y)", request: request)
            default:
                answer = "(\(y), \(x))"
                operation = localized("reflect it across the line y = x", request: request)
                rule = localized("(x, y) → (y, x)", request: request)
            }
            return makeQuestion(
                request: request,
                basis: basis,
                prompt: localized("Represent the \(displayTopic) \(representation) at (\(x), \(y)); \(operation), then return the transformed coordinate.", request: request),
                correctAnswer: answer,
                acceptedAnswers: [answer.replacingOccurrences(of: " ", with: "")],
                explanation: localized("Apply \(rule) to obtain \(answer).", request: request),
                hint: localized("Write the coordinate rule before substituting the point.", request: request),
                decisiveStep: localized("Apply \(rule).", request: request)
            )
        }
        let answer = "(\(-y), \(x))"
        let sourceLead = basis.sourceSentence == nil
            ? localized("Represent the \(basis.topic.lowercased()) state at (\(x), \(y)).", request: request)
            : localized("Use the cited sentence’s \(basis.wordCount)-word count to set x = \(x), and set y = \(y) from the displayed exercise seed.", request: request)
        return makeQuestion(
            request: request,
            basis: basis,
            prompt: localized("\(sourceLead) Rotate the point 90° counterclockwise about the origin and return the transformed coordinate.", request: request),
            correctAnswer: answer,
            acceptedAnswers: ["\(-y),\(x)", "x' = \(-y), y' = \(x)"],
            explanation: localized("A 90° counterclockwise rotation applies (x, y) → (−y, x), giving \(answer).", request: request),
            hint: localized("The old y-coordinate becomes the negated new x-coordinate.", request: request),
            decisiveStep: localized("Apply (x, y) → (−y, x).", request: request)
        )
    }

    private static func concreteSpatialTransformation(
        _ request: NFAuthoringRequest,
        basis: Basis
    ) -> NFAuthoredQuestion {
        let problem: ConcreteOpenProblem
        switch basis.reasoningVariant {
        case 0:
            problem = ConcreteOpenProblem(
                prompt: "Point A=(3,−2) is rotated 90° counterclockwise about the origin. Return the transformed coordinate.",
                correctAnswer: "(2, 3)",
                acceptedAnswer: "(2,3)",
                explanation: "A 90° counterclockwise rotation applies (x,y)→(−y,x). Substituting (3,−2) gives (−(−2),3)=(2,3), preserving distance from the origin.",
                hint: "The old y-coordinate becomes the negated new x-coordinate.",
                decisiveStep: "Apply (x,y)→(−y,x)."
            )
        case 1:
            problem = ConcreteOpenProblem(
                prompt: "A transparent coordinate sheet is folded along the y-axis, which acts as a reflection. Ink point B=(4,1) transfers to the opposite side. Return the image coordinate B′.",
                correctAnswer: "(−4, 1)",
                acceptedAnswer: "(-4,1)",
                explanation: "Folding across the y-axis is the reflection (x,y)→(−x,y). Thus B=(4,1) maps to B′=(−4,1), at the same perpendicular distance from the fold line.",
                hint: "A fold across the y-axis keeps vertical position and perpendicular distance unchanged.",
                decisiveStep: "Model the fold as a y-axis reflection: negate x and preserve y."
            )
        case 2:
            problem = ConcreteOpenProblem(
                prompt: "A grid robot is at (−2,5). Translate it by vector (4,−3) and return the new coordinate.",
                correctAnswer: "(2, 2)",
                acceptedAnswer: "(2,2)",
                explanation: "Translation adds the vector componentwise: (−2+4,5−3)=(2,2). Direction and length of every displacement in the grid are preserved.",
                hint: "Add horizontal and vertical components separately.",
                decisiveStep: "Compute (x+4,y−3)."
            )
        case 3:
            problem = ConcreteOpenProblem(
                prompt: "Vector v=(−3,4) is rotated 180° about the origin. Return v′.",
                correctAnswer: "(3, −4)",
                acceptedAnswer: "(3,-4)",
                explanation: "A half-turn negates both coordinates: (x,y)→(−x,−y). Therefore (−3,4) maps to (3,−4), with vector magnitude unchanged.",
                hint: "A 180° rotation reverses the vector direction.",
                decisiveStep: "Negate both coordinate components."
            )
        case 4:
            return openProblem(
                request,
                basis: basis,
                ConcreteOpenProblem(
                    prompt: "A 3D model point P=(2,−1,5) is viewed by orthographic projection along the z-axis onto the xy-plane. Return its 2D screen coordinate, state which coordinate the viewpoint discards, and name one consequence for points in this view.",
                    correctAnswer: "The screen coordinate is (2,−1); the projection discards z-depth. Therefore points with the same x and y but different z values overlap in this view.",
                    acceptedAnswer: "(2,-1); z or depth is discarded, so distinct depths can project to the same screen point.",
                    explanation: "Orthographic projection along the z-axis maps (x,y,z)→(x,y). It preserves the displayed x and y coordinates but loses depth, making this viewpoint many-to-one.",
                    hint: "The viewing direction is the coordinate removed from the screen representation.",
                    decisiveStep: "Project (x,y,z) to (x,y) and explain the lost z-depth/view ambiguity."
                ),
                styleOverride: .shortAnswer
            )
        default:
            return openProblem(
                request,
                basis: basis,
                ConcreteOpenProblem(
                    prompt: "Triangle A=(0,0), B=(3,0), C=(0,2) is reflected across the y-axis. State the three image coordinates, whether clockwise/counterclockwise orientation changes, and which distance or adjacency properties are preserved.",
                    correctAnswer: "A′=(0,0), B′=(−3,0), and C′=(0,2). Reflection reverses orientation. All pairwise distances, angles, and vertex adjacency are preserved.",
                    acceptedAnswer: "(0,0), (−3,0), (0,2); orientation reverses while distances and adjacency remain unchanged.",
                    explanation: "The rule (x,y)→(−x,y) fixes points on the y-axis and moves B across it. A reflection is a rigid but orientation-reversing transformation, so it preserves the triangle’s metric and adjacency structure.",
                    hint: "Transform each vertex, then distinguish rigid properties from handedness.",
                    decisiveStep: "Use coordinates to verify the reflected view, reversed orientation, and preserved distances/adjacency."
                ),
                styleOverride: .shortAnswer
            )
        }
        let answer = localized(problem.correctAnswer, request: request)
        let compact = answer.replacingOccurrences(of: " ", with: "")
        let asciiMinus = answer.replacingOccurrences(of: "−", with: "-")
        let unwrapped = asciiMinus
            .trimmingCharacters(in: CharacterSet(charactersIn: "()"))
        return makeQuestion(
            request: request,
            basis: basis,
            prompt: localized(problem.prompt, request: request),
            correctAnswer: answer,
            acceptedAnswers: [
                localized(problem.acceptedAnswer, request: request),
                compact,
                asciiMinus,
                asciiMinus.replacingOccurrences(of: " ", with: ""),
                unwrapped,
                unwrapped.replacingOccurrences(of: " ", with: "")
            ],
            explanation: localized(problem.explanation, request: request),
            hint: localized(problem.hint, request: request),
            decisiveStep: localized(problem.decisiveStep, request: request)
        )
    }

    private static func makeQuestion(
        request: NFAuthoringRequest,
        basis: Basis,
        styleOverride: NFQuestionStyle? = nil,
        prompt: String,
        choices: [String] = [],
        correctAnswer: String,
        acceptedAnswers: [String] = [],
        explanation: String,
        hint: String,
        decisiveStep: String,
        requiredTermGroups: [String] = [],
        minimumRequiredTermMatches: Int? = nil,
        rejectedAssertionGroups: [String] = [],
        numericDisplayPrecision: Int? = nil,
        numericAbsoluteTolerance: Double? = nil
    ) -> NFAuthoredQuestion {
        let questionStyle = styleOverride ?? request.style
        precondition(
            styleOverride == nil || isSupportedStyleOverride(from: request.style, to: questionStyle),
            "Unsupported deterministic question-style override"
        )
        let authority = NFAuthoredExerciseAuthority.make(
            id: basis.id,
            lab: request.lab,
            style: questionStyle,
            prompt: prompt,
            context: basis.context,
            choices: choices,
            correctAnswer: correctAnswer,
            acceptedAnswers: acceptedAnswers,
            explanation: explanation,
            hint: hint,
            decisiveStep: decisiveStep,
            difficulty: request.difficulty,
            citationChunkIDs: basis.citationChunkIDs,
            evidenceClass: .documentPractice,
            requiredTermGroups: requiredTermGroups,
            minimumRequiredTermMatches: minimumRequiredTermMatches,
            rejectedAssertionGroups: rejectedAssertionGroups,
            numericDisplayPrecision: numericDisplayPrecision,
            numericAbsoluteTolerance: numericAbsoluteTolerance,
            request: request
        )
        return NFAuthoredQuestion(
            id: basis.id,
            lab: request.lab,
            style: questionStyle,
            prompt: prompt,
            context: basis.context,
            choices: choices,
            correctAnswer: correctAnswer,
            acceptedAnswers: acceptedAnswers,
            explanation: explanation,
            hint: hint,
            decisiveStep: decisiveStep,
            difficulty: request.difficulty,
            citationChunkIDs: basis.citationChunkIDs,
            evidenceClass: .documentPractice,
            authoritativeExercise: authority
        )
    }

    private static func sourceMultipleChoicePrompt(_ request: NFAuthoringRequest, topic: String) -> String {
        switch request.lab {
        case .mentalMath, .quantitative:
            localized("Treat the cited statement as the available evidence for \(topic). Which option is directly supported without adding an unstated numerical assumption?", request: request)
        case .spatial:
            localized("Which option preserves every relation in the cited statement without introducing an orientation or scale assumption?", request: request)
        case .scientificReasoning:
            localized("Which claim is warranted by the cited evidence alone, without turning association into causation or adding an unreported control?", request: request)
        case .logicDebugging:
            localized("Which conclusion preserves the cited statement without reversing, negating, or universalizing it?", request: request)
        case .retrieval:
            localized("Which statement most faithfully reconstructs the cited source?", request: request)
        case .transfer:
            localized("Which option retains the cited source’s exact constraint before any transfer is attempted?", request: request)
        }
    }

    private static func sourceDecisiveStep(_ request: NFAuthoringRequest) -> String {
        switch request.lab {
        case .mentalMath, .quantitative: localized("Separate stated quantities from inferred quantities.", request: request)
        case .spatial: localized("Preserve every stated relation.", request: request)
        case .scientificReasoning: localized("Match claim strength to stated evidence.", request: request)
        case .logicDebugging: localized("Preserve direction, polarity, and scope.", request: request)
        case .retrieval: localized("Recover the claim with its qualifiers.", request: request)
        case .transfer: localized("Identify the constraint before changing context.", request: request)
        }
    }

    private struct SourceNumericPair {
        let first: Double
        let second: Double
        let firstLabel: String
        let secondLabel: String
        let measureLabel: String?
    }

    private struct SourceArithmeticExpression {
        let expression: String
        let answer: Double
    }

    private struct SourceEquation {
        let display: String
        let left: String
        let right: String
        var zeroForm: String { "\(left) - (\(right)) = 0" }
    }

    private struct SourceCodeMutation {
        let originalLine: String
        let faultyLine: String
        let originalToken: String
        let faultyToken: String
    }

    private struct SourceDiagramRelation {
        let from: String
        let to: String
        let sourceLine: String
    }

    private struct SourceWeightedTerm {
        let coefficient: Double
        let variable: String
        let display: String
    }

    private struct SourceInterval {
        let lower: Double
        let upper: Double
        let display: String
    }

    private struct SourceAssignment {
        let target: String
        let dependencies: [String]
        let display: String
    }

    private struct SourceComparison {
        let variable: String
        let operatorToken: String
        let threshold: Double
        let display: String
    }

    private static func sourceDiagramRelation(in basis: Basis) -> SourceDiagramRelation? {
        guard sourceKind(in: basis) == .diagram, let text = basis.sourceText else { return nil }
        let segments = text
            .split(whereSeparator: { $0 == "\n" || $0 == ";" })
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
        let arrows = ["-->", "-.->", "==>"]
        var relations: [SourceDiagramRelation] = []
        for segment in segments where !segment.isEmpty {
            guard let arrow = arrows.first(where: segment.contains),
                  let range = segment.range(of: arrow) else { continue }
            let rawFrom = String(segment[..<range.lowerBound])
            var rawTo = String(segment[range.upperBound...])
            if let nextArrow = arrows.compactMap({ rawTo.range(of: $0)?.lowerBound }).min() {
                rawTo = String(rawTo[..<nextArrow])
            }
            guard let from = diagramNodeLabel(rawFrom),
                  let to = diagramNodeLabel(rawTo),
                  from.localizedCaseInsensitiveCompare(to) != .orderedSame else { continue }
            relations.append(SourceDiagramRelation(
                from: from,
                to: to,
                sourceLine: "\(rawFrom.trimmingCharacters(in: .whitespaces)) \(arrow) \(rawTo.trimmingCharacters(in: .whitespaces))"
            ))
        }
        guard !relations.isEmpty else { return nil }
        return relations[basis.semanticVariant % relations.count]
    }

    private static func diagramNodeLabel(_ rawValue: String) -> String? {
        var value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        for prefix in ["flowchart LR", "flowchart TD", "flowchart TB", "flowchart RL", "graph LR", "graph TD"] {
            if value.hasPrefix(prefix) {
                value.removeFirst(prefix.count)
                value = value.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        guard !value.isEmpty else { return nil }
        for delimiters in [("[", "]"), ("(", ")"), ("{", "}")] {
            if let start = value.firstIndex(of: Character(delimiters.0)),
               let end = value.lastIndex(of: Character(delimiters.1)), start < end {
                let label = String(value[value.index(after: start)..<end])
                    .replacingOccurrences(of: "<br/>", with: " ")
                    .replacingOccurrences(of: "<br>", with: " ")
                    .trimmingCharacters(in: CharacterSet(charactersIn: "\"' "))
                if !label.isEmpty { return String(label.prefix(180)) }
            }
        }
        let identifier = value.split { !$0.isLetter && !$0.isNumber && $0 != "_" }.first.map(String.init)
        return identifier.flatMap { $0.isEmpty ? nil : $0 }
    }

    private static func sourceWeightedTerm(in basis: Basis) -> SourceWeightedTerm? {
        guard let text = basis.sourceText else { return nil }
        let pattern = #"(?<![\p{L}\p{N}_.])(-?\d+(?:\.\d+)?)\s*[*×]\s*([A-Za-z_][A-Za-z0-9_.]*)"#
        guard let expression = try? NSRegularExpression(pattern: pattern),
              let match = expression.firstMatch(
                in: text,
                range: NSRange(text.startIndex..<text.endIndex, in: text)
              ),
              let wholeRange = Range(match.range(at: 0), in: text),
              let coefficientRange = Range(match.range(at: 1), in: text),
              let variableRange = Range(match.range(at: 2), in: text),
              let coefficient = Double(text[coefficientRange]),
              coefficient.isFinite, coefficient != 0 else { return nil }
        return SourceWeightedTerm(
            coefficient: coefficient,
            variable: String(text[variableRange]),
            display: String(text[wholeRange])
        )
    }

    private static func sourceInterval(in basis: Basis) -> SourceInterval? {
        guard let text = basis.sourceText else { return nil }
        let contextSignals = ["range", "interval", "between", "bonus", "minimum", "maximum", "bounds", "boundary", "範囲", "区間"]
        let pattern = #"(-?\d+(?:\.\d+)?)\s*(?:\.\.|…|–|—|-)\s*(-?\d+(?:\.\d+)?)"#
        guard let expression = try? NSRegularExpression(pattern: pattern) else { return nil }
        for rawLine in text.split(separator: "\n", omittingEmptySubsequences: true) {
            let line = String(rawLine).trimmingCharacters(in: .whitespacesAndNewlines)
            let normalized = line.lowercased()
            guard contextSignals.contains(where: normalized.contains) else { continue }
            let range = NSRange(line.startIndex..<line.endIndex, in: line)
            guard let match = expression.firstMatch(in: line, range: range),
                  let lowerRange = Range(match.range(at: 1), in: line),
                  let upperRange = Range(match.range(at: 2), in: line),
                  let wholeRange = Range(match.range(at: 0), in: line),
                  let lower = Double(line[lowerRange]),
                  let upper = Double(line[upperRange]),
                  lower.isFinite, upper.isFinite, lower <= upper else { continue }
            return SourceInterval(lower: lower, upper: upper, display: String(line[wholeRange]))
        }
        return nil
    }

    private static func sourceAssignment(in basis: Basis) -> SourceAssignment? {
        guard let text = basis.sourceText,
              sourceKind(in: basis) == .executableCode || sourceKind(in: basis) == .structuredCode else {
            return nil
        }
        let assignmentPattern = #"^\s*(?:(?:let|var|const)\s+)?([A-Za-z_][A-Za-z0-9_]*)\s*=\s*([^=].*)$"#
        let identifierPattern = #"[A-Za-z_][A-Za-z0-9_.]*"#
        guard let assignmentRegex = try? NSRegularExpression(pattern: assignmentPattern),
              let identifierRegex = try? NSRegularExpression(pattern: identifierPattern) else { return nil }
        let ignored: Set<String> = [
            "true", "false", "nil", "null", "if", "else", "return", "let", "var", "const",
            "min", "max", "clamp", "abs", "round", "floor", "ceil", "sqrt", "pow"
        ]
        for rawLine in text.split(separator: "\n", omittingEmptySubsequences: true) {
            let line = String(rawLine).trimmingCharacters(in: .whitespacesAndNewlines)
            let range = NSRange(line.startIndex..<line.endIndex, in: line)
            guard let match = assignmentRegex.firstMatch(in: line, range: range),
                  let targetRange = Range(match.range(at: 1), in: line),
                  let rhsRange = Range(match.range(at: 2), in: line) else { continue }
            let target = String(line[targetRange])
            let rhs = String(line[rhsRange])
            let rhsNSRange = NSRange(rhs.startIndex..<rhs.endIndex, in: rhs)
            var seen = Set<String>()
            let dependencies = identifierRegex.matches(in: rhs, range: rhsNSRange).compactMap { match -> String? in
                guard let range = Range(match.range, in: rhs) else { return nil }
                let identifier = String(rhs[range])
                let root = identifier.split(separator: ".").first.map(String.init) ?? identifier
                guard root != target, !ignored.contains(root.lowercased()), seen.insert(identifier).inserted else {
                    return nil
                }
                return identifier
            }
            if dependencies.count >= 2 {
                return SourceAssignment(target: target, dependencies: Array(dependencies.prefix(6)), display: line)
            }
        }
        return nil
    }

    private static func sourceComparison(in basis: Basis) -> SourceComparison? {
        guard let text = basis.sourceText else { return nil }
        let pattern = #"([A-Za-z_][A-Za-z0-9_.]*)\s*(<=|>=|<|>)\s*(-?\d+(?:\.\d+)?)"#
        guard let expression = try? NSRegularExpression(pattern: pattern),
              let match = expression.firstMatch(
                in: text,
                range: NSRange(text.startIndex..<text.endIndex, in: text)
              ),
              let wholeRange = Range(match.range(at: 0), in: text),
              let variableRange = Range(match.range(at: 1), in: text),
              let operatorRange = Range(match.range(at: 2), in: text),
              let thresholdRange = Range(match.range(at: 3), in: text),
              let threshold = Double(text[thresholdRange]), threshold.isFinite else { return nil }
        return SourceComparison(
            variable: String(text[variableRange]),
            operatorToken: String(text[operatorRange]),
            threshold: threshold,
            display: String(text[wholeRange])
        )
    }

    private static func sourceKind(in basis: Basis) -> SourceKind {
        let tags = Set(basis.sourceContentTypeTags.map { $0.lowercased() })
        let language = basis.sourceLanguage?.lowercased()
        if ["mermaid", "dot", "graphviz", "plantuml"].contains(language ?? "")
            || !tags.isDisjoint(with: ["mermaid", "diagram", "flowchart", "graphviz"]) {
            return .diagram
        }
        if (tags.contains("table") || tags.contains("csv")) && !tags.contains("schema-summary") {
            return .table
        }
        if tags.contains("equation") || tags.contains("math") || language == "latex" { return .equation }
        let executableLanguages: Set<String> = [
            "swift", "python", "py", "javascript", "js", "typescript", "ts", "java", "kotlin",
            "c", "cpp", "c++", "csharp", "cs", "go", "rust", "ruby", "php", "scala", "sql", "r", "shell", "bash"
        ]
        if language.map(executableLanguages.contains) == true { return .executableCode }
        if tags.contains("code") || tags.contains("source-code") { return .structuredCode }
        if tags.contains("prose") { return .prose }
        return .other
    }

    private static func formatSourceNumber(_ value: Double) -> String {
        number(value)
    }

    private static func sourceNumericPair(in basis: Basis) -> SourceNumericPair? {
        guard let text = basis.sourceText else { return nil }
        let tags = Set(basis.sourceContentTypeTags.map { $0.lowercased() })
        guard (tags.contains("table") || tags.contains("csv")),
              !tags.contains("schema-summary") else { return nil }

        let rows = text
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map { delimitedCells(in: String($0)) }
            .filter { cells in
                !cells.isEmpty && !cells.allSatisfy { cell in
                    let stripped = cell.replacingOccurrences(of: "-", with: "")
                        .replacingOccurrences(of: ":", with: "")
                        .trimmingCharacters(in: .whitespaces)
                    return stripped.isEmpty
                }
            }
        guard rows.count >= 2 else { return nil }

        let header = rows[0]
        let dataRows = Array(rows.dropFirst()).filter { $0.count == header.count }
        guard !dataRows.isEmpty else { return nil }

        // Prefer two observations from one labeled measure. This prevents two
        // unrelated values in prose from being treated as a time series.
        for column in header.indices where numericCell(header[column]) == nil {
            let observations = dataRows.compactMap { row -> (label: String, value: Double)? in
                guard let value = numericCell(row[column]) else { return nil }
                let rowLabel = row.enumerated().first { index, cell in
                    index != column && numericCell(cell) == nil && !cell.isEmpty
                }?.element
                guard let rowLabel, !rowLabel.isEmpty else { return nil }
                return (rowLabel, value)
            }
            if observations.count >= 2, observations[0].label != observations[1].label {
                return SourceNumericPair(
                    first: observations[0].value,
                    second: observations[1].value,
                    firstLabel: observations[0].label,
                    secondLabel: observations[1].label,
                    measureLabel: header[column]
                )
            }
        }

        // A single labeled row with two numeric columns is also a defensible
        // comparison because both values retain their source column labels.
        for row in dataRows {
            let numericColumns = row.indices.filter { numericCell(row[$0]) != nil }
            guard numericColumns.count >= 2 else { continue }
            let firstColumn = numericColumns[0]
            let secondColumn = numericColumns[1]
            guard !header[firstColumn].isEmpty,
                  !header[secondColumn].isEmpty,
                  header[firstColumn] != header[secondColumn],
                  let first = numericCell(row[firstColumn]),
                  let second = numericCell(row[secondColumn]) else { continue }
            let rowLabel = row.enumerated().first { index, cell in
                index != firstColumn && index != secondColumn
                    && numericCell(cell) == nil && !cell.isEmpty
            }?.element
            return SourceNumericPair(
                first: first,
                second: second,
                firstLabel: [rowLabel, header[firstColumn]].compactMap { $0 }.joined(separator: " · "),
                secondLabel: [rowLabel, header[secondColumn]].compactMap { $0 }.joined(separator: " · "),
                measureLabel: nil
            )
        }
        return nil
    }

    private static func delimitedCells(in line: String) -> [String] {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        let delimiter: Character
        if trimmed.contains("\t") { delimiter = "\t" }
        else if trimmed.contains("|") { delimiter = "|" }
        else if trimmed.contains(",") { delimiter = "," }
        else { return [] }

        var cells: [String] = []
        var cell = ""
        var insideQuotes = false
        for character in trimmed {
            if character == "\"" {
                insideQuotes.toggle()
            } else if character == delimiter, !insideQuotes {
                cells.append(cell.trimmingCharacters(in: .whitespacesAndNewlines))
                cell.removeAll(keepingCapacity: true)
            } else {
                cell.append(character)
            }
        }
        cells.append(cell.trimmingCharacters(in: .whitespacesAndNewlines))
        if delimiter == "|" {
            while cells.first?.isEmpty == true { cells.removeFirst() }
            while cells.last?.isEmpty == true { cells.removeLast() }
        }
        return cells
    }

    private static func numericCell(_ cell: String) -> Double? {
        let normalized = cell
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "−", with: "-")
            .replacingOccurrences(of: "%", with: "")
        guard let value = Double(normalized), value.isFinite, abs(value) <= 1_000_000_000 else {
            return nil
        }
        return value
    }

    private static func sourceArithmeticExpression(in basis: Basis) -> SourceArithmeticExpression? {
        guard let text = basis.sourceText else { return nil }
        let tags = Set(basis.sourceContentTypeTags.map { $0.lowercased() })
        guard tags.contains("equation")
                || tags.contains("math")
                || basis.sourceLanguage?.lowercased() == "latex" else { return nil }
        let pattern = #"(?<![\p{L}\p{N}_.])(-?\d+(?:\.\d+)?)\s*([+\-*/×÷])\s*(-?\d+(?:\.\d+)?)(?![\p{L}\p{N}_.])"#
        guard let expression = try? NSRegularExpression(pattern: pattern),
              let match = expression.firstMatch(
                in: text,
                range: NSRange(text.startIndex..<text.endIndex, in: text)
              ),
              let wholeRange = Range(match.range(at: 0), in: text),
              let firstRange = Range(match.range(at: 1), in: text),
              let operatorRange = Range(match.range(at: 2), in: text),
              let secondRange = Range(match.range(at: 3), in: text),
              let first = Double(text[firstRange]),
              let second = Double(text[secondRange]) else { return nil }
        let operation = String(text[operatorRange])
        let answer: Double
        switch operation {
        case "+": answer = first + second
        case "-": answer = first - second
        case "*", "×": answer = first * second
        case "/", "÷":
            guard second != 0 else { return nil }
            answer = first / second
        default: return nil
        }
        guard answer.isFinite else { return nil }
        return SourceArithmeticExpression(expression: String(text[wholeRange]), answer: answer)
    }

    private static func sourceEquation(in basis: Basis) -> SourceEquation? {
        guard let text = basis.sourceText else { return nil }
        let tags = Set(basis.sourceContentTypeTags.map { $0.lowercased() })
        guard tags.contains("equation")
                || tags.contains("math")
                || basis.sourceLanguage?.lowercased() == "latex" else { return nil }
        for rawLine in text.split(separator: "\n", omittingEmptySubsequences: true) {
            let line = String(rawLine)
                .replacingOccurrences(of: "$$", with: "")
                .replacingOccurrences(of: "\\[", with: "")
                .replacingOccurrences(of: "\\]", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.contains("=="), !line.contains("!="),
                  let equality = line.firstIndex(of: "=") else { continue }
            let left = String(line[..<equality]).trimmingCharacters(in: .whitespaces)
            let right = String(line[line.index(after: equality)...]).trimmingCharacters(in: .whitespaces)
            guard !left.isEmpty, !right.isEmpty, left.count <= 160, right.count <= 160 else { continue }
            return SourceEquation(display: line, left: left, right: right)
        }
        return nil
    }

    private static func sourceCodeMutation(in basis: Basis) -> SourceCodeMutation? {
        guard let text = basis.sourceText else { return nil }
        let kind = sourceKind(in: basis)
        guard kind == .executableCode || kind == .structuredCode else { return nil }

        let replacements: [(String, String)] = [
            ("<=", "<"), (">=", ">"), ("==", "!="), ("!=", "=="),
            ("&&", "||"), ("||", "&&"), (" + ", " - "),
            (" * ", " / "), (" < ", " <= "), (" > ", " >= "),
            ("true", "false"), ("false", "true")
        ]
        let lines = text.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, !trimmed.hasPrefix("```"),
                  !trimmed.contains("-->"), !trimmed.contains("-.->"), !trimmed.contains("==>") else {
                continue
            }
            for (original, faulty) in replacements where trimmed.contains(original) {
                guard let range = trimmed.range(of: original) else { continue }
                return SourceCodeMutation(
                    originalLine: trimmed,
                    faultyLine: trimmed.replacingCharacters(in: range, with: faulty),
                    originalToken: original.trimmingCharacters(in: .whitespaces),
                    faultyToken: faulty.trimmingCharacters(in: .whitespaces)
                )
            }
        }

        let numberPattern = #"(?<![\p{L}\p{N}_])\d+(?![\p{L}\p{N}_])"#
        guard let expression = try? NSRegularExpression(pattern: numberPattern) else { return nil }
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, !trimmed.hasPrefix("```"),
                  !trimmed.contains("-->"), !trimmed.contains("-.->"), !trimmed.contains("==>") else {
                continue
            }
            let fullRange = NSRange(trimmed.startIndex..<trimmed.endIndex, in: trimmed)
            guard let match = expression.firstMatch(in: trimmed, range: fullRange),
                  let range = Range(match.range, in: trimmed),
                  let value = Int(trimmed[range]), value < Int.max else { continue }
            let faulty = String(value + 1)
            return SourceCodeMutation(
                originalLine: trimmed,
                faultyLine: trimmed.replacingCharacters(in: range, with: faulty),
                originalToken: String(value),
                faultyToken: faulty
            )
        }
        return nil
    }

    /// Returns complete, distinct natural-language propositions in source
    /// order. Source blocks such as Mermaid, pseudocode, and formulas must be
    /// handled by their own structural templates; flattening or truncating
    /// those blocks produces fragments that cannot support recall practice.
    private static func sourcePropositionCandidates(
        _ request: NFAuthoringRequest
    ) -> [(chunk: NFSourceChunk, proposition: String)] {
        let rankedChunks = diversifiedSourceChunks(request.sourceChunks, for: request.style)
        let propositionsByChunk = rankedChunks.map { chunk -> [(chunk: NFSourceChunk, proposition: String)] in
            let kind = sourceKind(of: chunk)
            guard kind == .prose || kind == .other else { return [] }
            let startsInsideEarlierChunk = rankedChunks.contains { earlier in
                guard earlier.documentID == chunk.documentID,
                      earlier.documentVersion == chunk.documentVersion,
                      let start = chunk.characterStart,
                      let earlierStart = earlier.characterStart,
                      let earlierEnd = earlier.characterEnd else { return false }
                return earlierStart < start && start < earlierEnd
            }
            return completePropositions(
                in: chunk.text,
                dropsLeadingPartial: startsInsideEarlierChunk
            ).map { (chunk, $0) }
        }
        var seen = Set<String>()
        var candidates: [(chunk: NFSourceChunk, proposition: String)] = []
        let maximumDepth = propositionsByChunk.map(\.count).max() ?? 0
        for depth in 0..<maximumDepth {
            for chunkCandidates in propositionsByChunk where depth < chunkCandidates.count {
                let candidate = chunkCandidates[depth]
                let proposition = candidate.proposition
                let key = proposition
                    .split(whereSeparator: \.isWhitespace)
                    .joined(separator: " ")
                    .folding(
                        options: [.caseInsensitive, .diacriticInsensitive],
                        locale: Locale(identifier: "en_US_POSIX")
                    )
                guard seen.insert(key).inserted else { continue }
                candidates.append(candidate)
            }
        }
        return candidates
    }

    private static func completePropositions(
        in text: String,
        dropsLeadingPartial: Bool = false
    ) -> [String] {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: true)
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
        let normalized = lines.enumerated()
            .filter { entry in
                let index = entry.offset
                let line = entry.element
                return !line.isEmpty
                    && !isMarkdownHeading(line)
                    && !(index + 1 < lines.count && isMarkdownSetextUnderline(lines[index + 1]))
                    && !line.hasPrefix("```")
                    && !line.hasPrefix("flowchart ")
                    && !line.hasPrefix("graph ")
                    && !line.hasPrefix("sequenceDiagram")
                    && !line.contains("-->")
                    && !line.contains("-.->")
                    && !line.contains("==>")
            }.map(\.element)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return [] }

        let characters = Array(normalized.prefix(8_000))
        var sentenceStart = characters.startIndex
        var seen = Set<String>()
        var propositions: [String] = []
        var candidateIndex = 0
        for index in characters.indices where ".!?。！？".contains(characters[index]) {
            let rawNextIndex = characters.index(after: index)
            let hasRawNext = rawNextIndex < characters.endIndex
            let isDecimalPoint = characters[index] == "."
                && index > characters.startIndex
                && hasRawNext
                && characters[characters.index(before: index)].isNumber
                && characters[rawNextIndex].isNumber
            let prefix = String(characters[sentenceStart...index]).lowercased()
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let abbreviationTokens: Set<String> = [
                // Titles, names, and initialisms.
                "dr.", "mr.", "mrs.", "ms.", "prof.", "ph.d.",
                "jr.", "sr.", "st.", "rev.", "hon.",
                // Scholarly cross-references and editorial shorthand.
                "fig.", "eq.", "ref.", "refs.", "vol.", "pp.", "p.",
                "ch.", "ed.", "eds.", "e.g.", "i.e.",
                "approx.", "cf.", "no.", "vs.",
                // Calendar and compact measurement abbreviations commonly
                // followed by a value or qualifier rather than a new claim.
                "jan.", "feb.", "mar.", "apr.", "jun.", "jul.", "aug.",
                "sep.", "sept.", "oct.", "nov.", "dec.",
                "kg.", "mg.", "g.", "ml.", "cm.", "mm.", "km.",
                "min.", "sec.", "hr.",
                // These are also recognized by the repeated-initialism rule,
                // but keeping them explicit documents the source contract.
                "u.s.", "u.k."
            ]
            let rawFinalToken = prefix.split(whereSeparator: \.isWhitespace).last.map(String.init) ?? ""
            let finalToken = rawFinalToken.trimmingCharacters(
                in: CharacterSet(charactersIn: "([{\"'\u{201C}\u{2018}\u{00AB}")
            )
            let initialismSegments = finalToken.split(separator: ".", omittingEmptySubsequences: false)
            let isRepeatedLetterInitialism = initialismSegments.count >= 3
                && initialismSegments.last?.isEmpty == true
                && initialismSegments.dropLast().allSatisfy { segment in
                    segment.count == 1 && segment.first?.isLetter == true
                }
            let isPersonalInitial = finalToken.count == 2
                && finalToken.last == "."
                && finalToken.first?.isLetter == true
            let isAbbreviation = isRepeatedLetterInitialism
                || isPersonalInitial
                || abbreviationTokens.contains(finalToken)
                || prefix.hasSuffix("et al.")
            // Keep closing punctuation in the cited proposition, but inspect
            // what follows it when deciding whether this is a sentence end.
            // Japanese prose normally has no whitespace between `。」` and
            // the next sentence; ASCII brackets appear in imported papers too.
            let closingDelimiters = "\"'\u{201D}\u{2019}\u{00BB})]}\u{300D}\u{300F}\u{3011}\u{FF09}\u{FF3D}\u{FF5D}\u{3009}\u{300B}\u{3019}\u{3017}\u{3015}\u{301B}"
            var boundaryIndex = rawNextIndex
            while boundaryIndex < characters.endIndex,
                  closingDelimiters.contains(characters[boundaryIndex]) {
                boundaryIndex = characters.index(after: boundaryIndex)
            }
            let hasFollowingContent = boundaryIndex < characters.endIndex
            let permitsUnspacedFollowingSentence = "。！？".contains(characters[index])
            guard !isDecimalPoint,
                  !isAbbreviation,
                  !hasFollowingContent
                    || permitsUnspacedFollowingSentence
                    || characters[boundaryIndex].isWhitespace else { continue }
            let candidateEnd = boundaryIndex > rawNextIndex
                ? characters.index(before: boundaryIndex)
                : index
            let candidate = String(characters[sentenceStart...candidateEnd])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let isLeadingPartial = dropsLeadingPartial && candidateIndex == 0
            if !isLeadingPartial,
               isUsableSourceProposition(candidate),
               seen.insert(candidate).inserted {
                propositions.append(candidate)
            }
            candidateIndex += 1
            sentenceStart = boundaryIndex
        }
        return propositions
    }

    private static func isMarkdownHeading(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("#") {
            let markerCount = trimmed.prefix(while: { $0 == "#" }).count
            if (1...6).contains(markerCount) {
                let remainder = trimmed.dropFirst(markerCount)
                if remainder.isEmpty || remainder.first?.isWhitespace == true { return true }
            }
        }
        let compact = trimmed.replacingOccurrences(of: " ", with: "")
        return compact.count >= 3
            && (compact.allSatisfy { $0 == "=" }
                || compact.allSatisfy { $0 == "-" }
                || compact.allSatisfy { $0 == "*" })
    }

    private static func isMarkdownSetextUnderline(_ line: String) -> Bool {
        let compact = line.replacingOccurrences(of: " ", with: "")
        return compact.count >= 3
            && (compact.allSatisfy { $0 == "=" } || compact.allSatisfy { $0 == "-" })
    }

    private static func firstCompleteProposition(in text: String) -> String? {
        completePropositions(in: text).first
    }

    private static func isUsableSourceProposition(_ value: String) -> Bool {
        let tokens = words(in: value)
        let cjkSubstantiveCount = value.unicodeScalars.reduce(into: 0) { count, scalar in
            let codePoint = scalar.value
            let isCJKLetter = (0x3040...0x30FF).contains(codePoint) // Hiragana and Katakana
                || (0x31F0...0x31FF).contains(codePoint) // Katakana extensions
                || (0x3400...0x4DBF).contains(codePoint) // CJK Extension A
                || (0x4E00...0x9FFF).contains(codePoint) // Unified ideographs
                || (0xF900...0xFAFF).contains(codePoint) // Compatibility ideographs
                || (0xFF66...0xFF9D).contains(codePoint) // Half-width Katakana
                || (0x1100...0x11FF).contains(codePoint) // Hangul Jamo
                || (0x3130...0x318F).contains(codePoint) // Hangul compatibility Jamo
                || (0xAC00...0xD7AF).contains(codePoint) // Hangul syllables
                || (0x20000...0x2FA1F).contains(codePoint) // Supplementary CJK ideographs
            if isCJKLetter { count += 1 }
        }
        guard value.count <= 600,
              tokens.count >= 6 || cjkSubstantiveCount >= 12 else { return false }
        let codeSignals = ["-->", "-.->", "==>", "```", "{", "};", " = clamp(", " += ", " *= "]
        guard !codeSignals.contains(where: value.contains) else { return false }
        return value.unicodeScalars.contains(where: CharacterSet.letters.contains)
    }

    private static func sourceChoices(
        correct: String,
        distractors: [String],
        rotation: Int,
        request: NFAuthoringRequest
    ) -> [String] {
        var used = Set([correct])
        let uniqueDistractors = distractors.enumerated().map { index, candidate in
            var value = candidate
            while used.contains(value) {
                value += localized(" [unsupported \(index + 1)]", request: request)
            }
            used.insert(value)
            return value
        }
        // Within a set, `rotation` distributes the key across positions. A
        // topic-derived affine permutation changes both phase and direction so
        // different starter sets do not expose one reusable six-key pattern.
        let positionCount = uniqueDistractors.count + 1
        if request.sourceChunks.isEmpty,
           positionCount == 4,
           let position = starterMultipleChoiceCorrectPosition(
               request: request,
               questionIndex: rotation
           ) {
            var choices = uniqueDistractors
            choices.insert(correct, at: position)
            return choices
        }
        let topicHash = AdaptiveEngine.fnv1a64(request.customTopic)
        let stride = topicHash.isMultiple(of: 2) ? 1 : max(1, positionCount - 1)
        let offset = Int((topicHash >> 18) % UInt64(positionCount))
        return ([correct] + uniqueDistractors).rotated(
            by: rotation * stride + offset
        )
    }

    /// Reviewed key layouts prevent a learner from reusing one answer-position
    /// rhythm across the four built-in multiple-choice sets. The layouts are
    /// not cyclic shifts of one another, yet their aggregate 24 answers place
    /// the key exactly six times in every position.
    private static func starterMultipleChoiceCorrectPosition(
        request: NFAuthoringRequest,
        questionIndex: Int
    ) -> Int? {
        let topic = request.customTopic.lowercased()
        let pattern: [Int]
        if topic.contains("logical implication") {
            pattern = [0, 1, 2, 3, 0, 1]
        } else if topic.contains("data structures") {
            pattern = [1, 3, 0, 2, 1, 2]
        } else if topic.contains("chemical equilibrium") || topic.contains("acid base") {
            pattern = [2, 0, 3, 1, 2, 3]
        } else if topic.contains("genetics") || topic.contains("inheritance") {
            pattern = [3, 2, 0, 3, 1, 0]
        } else {
            return nil
        }
        return pattern[((questionIndex % pattern.count) + pattern.count) % pattern.count]
    }

    private static func words(in text: String) -> [Substring] {
        text.split { !$0.isLetter && !$0.isNumber }
    }

    private static func numericValues(in text: String) -> [Double] {
        text
            .split { character in
                !(character.isNumber || character == "." || character == "-" || character == "+")
            }
            .compactMap { Double($0) }
            .filter { $0.isFinite && abs($0) <= 1_000_000_000 }
    }

    private static func number(_ value: Double) -> String {
        if value.isFinite, value.rounded() == value {
            return String(format: "%.0f", value)
        }
        return String(format: "%.4g", value)
    }
}

private extension Array {
    func rotated(by offset: Int) -> [Element] {
        guard !isEmpty else { return [] }
        let amount = ((offset % count) + count) % count
        return Array(self[amount...]) + Array(self[..<amount])
    }
}

import Foundation

/// Model-authored question payload shared by the user-owned Shortcut bridge
/// and its local validator.
struct NFShortcutQuestionDraft: Equatable, Sendable {
    let prompt: String
    let context: String
    let choices: [String]
    let correctAnswer: String
    let acceptedAnswers: [String]
    let explanation: String
    let hint: String
    let decisiveStep: String
    let citationChunkIDs: [String]
    /// Each entry is one required concept. `term|synonym` expresses accepted
    /// lexical alternatives under the personal-practice scorer.
    let requiredConcepts: [String]
    let rejectedAssertions: [String]
    /// Compatibility field in the frozen Shortcut JSON schema. V1 requires it
    /// to be empty because model-supplied arithmetic is not an independent
    /// answer authority.
    let verificationExpression: String
}

struct NFValidatedShortcutAuthoring: Sendable {
    let questions: [NFAuthoredQuestion]
    let sourceSupport: NFSourceSupportLevel
}

enum NFShortcutAuthoringValidationError: Error, Equatable, Sendable {
    case violations([String])
}

/// Question Writer is reserved for open-response practice whose model answer
/// the learner reveals and evaluates. Forms that imply an app-verified key are
/// produced by NeuroForge's deterministic catalog instead.
enum NFQuestionWriterAuthoringPolicy {
    static let supportedStyles = Set(NFQuestionStyle.allCases.filter { $0 != .multipleChoice })

    static func supports(_ style: NFQuestionStyle) -> Bool {
        supportedStyles.contains(style)
    }
}

enum NFShortcutAuthoringValidator {
    static func validate(
        _ drafts: [NFShortcutQuestionDraft],
        for request: NFAuthoringRequest,
        modelIdentifier: String
    ) throws -> NFValidatedShortcutAuthoring {
        var violations: [String] = []
        var questions: [NFAuthoredQuestion] = []
        var sourceSupportLevels: [NFSourceSupportLevel] = []
        var canonicalPrompts: Set<String> = []
        var canonicalDecisiveSteps: Set<String> = []
        var priorPromptTokens: [[String]] = []
        var priorDecisiveStepTokens: [[String]] = []
        let allowedCitations = Set(request.sourceChunks.map(\.id))

        guard NFQuestionWriterAuthoringPolicy.supports(request.style) else {
            throw NFShortcutAuthoringValidationError.violations([
                "Question Writer supports open-response self-check sets only."
            ])
        }

        guard drafts.count == request.count else {
            throw NFShortcutAuthoringValidationError.violations([
                NFAppLocalization.formattedReturnedQuestionCount(
                    actual: drafts.count,
                    requested: request.count
                )
            ])
        }

        for (index, draft) in drafts.enumerated() {
            let number = index + 1
            let prompt = bounded(draft.prompt)
            let context = bounded(draft.context)
            let answer = bounded(draft.correctAnswer)
            let explanation = bounded(draft.explanation)
            let hint = bounded(draft.hint)
            let decisiveStep = bounded(draft.decisiveStep)
            let choices = uniqueBounded(draft.choices)
            let acceptedAnswers = uniqueBounded(draft.acceptedAnswers)
            let citationIDs = uniqueBounded(draft.citationChunkIDs)
            let requiredConceptCandidates: [String] = uniqueBounded(draft.requiredConcepts)
                .filter { $0.count <= 160 }
            let requiredConcepts = Array(requiredConceptCandidates.prefix(
                upTo: min(6, requiredConceptCandidates.count)
            ))
            let rejectedAssertionCandidates: [String] = uniqueBounded(draft.rejectedAssertions)
                .filter { $0.count <= 220 }
            let rejectedAssertions = Array(rejectedAssertionCandidates.prefix(
                upTo: min(6, rejectedAssertionCandidates.count)
            ))

            if !(18...2_400).contains(prompt.count) {
                violations.append("Question \(number) has an invalid prompt length.")
            }
            if answer.isEmpty || answer.count > 1_200 {
                violations.append("Question \(number) has an invalid reference answer.")
            }
            if explanation.count < 24 || explanation.count > 3_600 {
                violations.append("Question \(number) needs a bounded, usable solution explanation.")
            }
            if context.count > 1_200 || hint.count > 1_000 || decisiveStep.count > 1_000 {
                violations.append("Question \(number) exceeds a bounded presentation field.")
            }
            if choices.contains(where: { $0.count > 1_200 })
                || acceptedAnswers.count > 8
                || acceptedAnswers.contains(where: { $0.count > 1_200 }) {
                violations.append("Question \(number) exceeds a bounded answer field.")
            }
            if draft.requiredConcepts.count > 6 || draft.rejectedAssertions.count > 6 {
                violations.append("Question \(number) exceeds the bounded reasoning rubric.")
            }
            let formattedSurfaces = [
                prompt, context, answer, explanation, hint, decisiveStep
            ] + choices + acceptedAnswers
            if formattedSurfaces.contains(where: hasInvalidMathFormatting) {
                violations.append("Question \(number) must use complete Markdown fences and $$...$$ display blocks for mathematics, with no single-dollar inline delimiters.")
            }
            if exposesReferenceAnswer(
                answer,
                in: [prompt, context, hint],
                style: request.style
            ) {
                violations.append("Question \(number) exposes its reference answer in the learner-visible task.")
            }

            let canonicalPrompt = canonical(prompt)
            if !canonicalPrompt.isEmpty, !canonicalPrompts.insert(canonicalPrompt).inserted {
                violations.append("Question \(number) duplicates another prompt.")
            }
            let promptTokens = substantiveTokens(prompt)
            if priorPromptTokens.contains(where: { tokenSimilarity($0, promptTokens) >= 0.82 }) {
                violations.append("Question \(number) repeats another question's task with superficial wording changes.")
            }
            priorPromptTokens.append(promptTokens)
            let canonicalDecisiveStep = canonical(decisiveStep)
            if canonicalDecisiveStep.count < 12 {
                violations.append("Question \(number) needs a specific comparison step.")
            } else if !canonicalDecisiveSteps.insert(canonicalDecisiveStep).inserted {
                violations.append("Question \(number) repeats another question's comparison step.")
            }
            let decisiveStepTokens = substantiveTokens(decisiveStep)
            if priorDecisiveStepTokens.contains(where: {
                tokenSimilarity($0, decisiveStepTokens) >= 0.78
            }) {
                violations.append("Question \(number) repeats another question's reasoning mechanic.")
            }
            priorDecisiveStepTokens.append(decisiveStepTokens)
            if explanationRestatesAnswer(explanation: explanation, answer: answer) {
                violations.append("Question \(number) needs a worked explanation rather than a restated reference answer.")
            }
            if isGenericQuestionSurface(
                prompt: prompt,
                context: context,
                answer: answer,
                explanation: explanation,
                hint: hint,
                decisiveStep: decisiveStep,
                request: request
            ) {
                violations.append("Question \(number) is generic filler rather than a concrete domain task.")
            }

            switch request.style {
            case .multipleChoice:
                violations.append("Question \(number) uses a form that Question Writer does not author.")
            case .shortAnswer, .numerical, .proofOrDerivation, .debugging,
                 .experimentalDesign, .dataInterpretation, .spatialTransformation:
                if !choices.isEmpty {
                    violations.append("Question \(number) returned choices for an open response.")
                }
                if !acceptedAnswers.isEmpty
                    || !requiredConcepts.isEmpty
                    || !rejectedAssertions.isEmpty
                    || !draft.verificationExpression.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    violations.append("Question \(number) returned automatic-scoring metadata for a self-check response.")
                }
            }

            let safetySurface = ([
                prompt, context, answer, explanation, hint, decisiveStep,
                draft.verificationExpression
            ] + choices + acceptedAnswers + requiredConcepts + rejectedAssertions)
                .joined(separator: " ")
            if prohibitedPhrases.contains(where: {
                safetySurface.localizedCaseInsensitiveContains($0)
            }) {
                violations.append("Question \(number) contains prohibited instruction or hidden-reasoning text.")
            }

            if request.usesSourceMaterial {
                if citationIDs.isEmpty || !Set(citationIDs).isSubset(of: allowedCitations) {
                    violations.append("Question \(number) must cite only supplied source excerpts.")
                } else {
                    let support = NFSourceSupportValidator.evaluate(
                        answer: answer,
                        acceptedAnswers: acceptedAnswers,
                        explanation: explanation + " " + context,
                        decisiveStep: decisiveStep + " " + prompt,
                        citationChunkIDs: citationIDs,
                        sourceChunks: request.sourceChunks
                    )
                    sourceSupportLevels.append(support)
                    if support == .citationIdentifiersOnly {
                        violations.append("Question \(number) names a citation but does not connect its task or solution to the excerpt.")
                    }
                }
            } else {
                if !citationIDs.isEmpty {
                    violations.append("Question \(number) invented a citation without source material.")
                }
                if !containsRequestedAnchor(
                    learnerTask: prompt,
                    solution: [answer, explanation, decisiveStep].joined(separator: " "),
                    request: request
                ) {
                    violations.append("Question \(number) is not substantively anchored to the requested topic or field.")
                }
            }

            let questionID = "shortcut-ai.\(request.id.uuidString).\(index)"
            let contentTier: NFExerciseContentTier = request.usesSourceMaterial
                ? .sourceGroundedAI
                : .aiContextualized
            let authority = NFAuthoredExerciseAuthority.make(
                id: questionID,
                lab: request.lab,
                style: request.style,
                prompt: prompt,
                context: context,
                choices: choices,
                correctAnswer: answer,
                acceptedAnswers: acceptedAnswers,
                explanation: explanation,
                hint: hint,
                decisiveStep: decisiveStep,
                difficulty: request.difficulty,
                citationChunkIDs: citationIDs,
                evidenceClass: .documentPractice,
                requiredTermGroups: requiredConcepts,
                minimumRequiredTermMatches: requiredConcepts.isEmpty
                    ? nil
                    : min(requiredConcepts.count, max(2, Int(ceil(Double(requiredConcepts.count) * 0.6)))),
                rejectedAssertionGroups: rejectedAssertions,
                contentTier: contentTier,
                modelIdentifier: modelIdentifier,
                promptVersion: NFAuthoringRequest.promptVersion,
                request: request
            )
            let question = NFAuthoredQuestion(
                id: questionID,
                lab: request.lab,
                style: request.style,
                prompt: prompt,
                context: context,
                choices: choices,
                correctAnswer: answer,
                acceptedAnswers: acceptedAnswers,
                explanation: explanation,
                hint: hint,
                decisiveStep: decisiveStep,
                difficulty: request.difficulty,
                citationChunkIDs: citationIDs,
                evidenceClass: .documentPractice,
                authoritativeExercise: authority
            )
            if !question.hasValidResponseSchema {
                violations.append("Question \(number) could not produce a valid personal-practice response schema.")
            }
            questions.append(question)
        }

        guard violations.isEmpty else {
            throw NFShortcutAuthoringValidationError.violations(violations)
        }
        let sourceSupport = sourceSupportLevels.min {
            NFSourceSupportValidator.rank($0) < NFSourceSupportValidator.rank($1)
        } ?? .notApplicable
        return NFValidatedShortcutAuthoring(questions: questions, sourceSupport: sourceSupport)
    }

    private static func containsRequestedAnchor(
        learnerTask: String,
        solution: String,
        request: NFAuthoringRequest
    ) -> Bool {
        let topic = request.customTopic.trimmingCharacters(in: .whitespacesAndNewlines)
        let anchor = topic.isEmpty ? request.field.title : topic
        if isJapaneseLocale(request.localeIdentifier) {
            let requestedSurface = [anchor, request.learningObjective].joined(separator: " ")
            let requestedAnchors = japaneseAnchorTerms(requestedSurface)
            guard !requestedAnchors.isEmpty else { return false }
            let learnerTerms = japaneseAnchorTerms(learnerTask)
            let learnerHasDirectAnchor = requestedAnchors.contains(where: { requested in
                learnerTerms.contains(where: { japaneseTermsOverlap(requested, $0) })
            })
            let requestedNGrams = japaneseAnchorNGrams(requestedSurface)
            let learnerNGrams = japaneseAnchorNGrams(learnerTask)
            guard learnerHasDirectAnchor
                    || requestedNGrams.intersection(learnerNGrams).count >= 2 else {
                return false
            }

            let solutionTerms = japaneseAnchorTerms(solution)
            let solutionHasDirectAnchor = requestedAnchors.contains(where: { requested in
                solutionTerms.contains(where: { japaneseTermsOverlap(requested, $0) })
            })
            let solutionNGrams = japaneseAnchorNGrams(solution)
            return solutionHasDirectAnchor
                || requestedNGrams.intersection(solutionNGrams).count >= 2
                || learnerTerms.contains(where: { learner in
                solutionTerms.contains(where: { japaneseTermsOverlap(learner, $0) })
                })
                || learnerNGrams.intersection(solutionNGrams).count >= 2
        }
        let anchorTokens = substantiveTokens(
            [anchor, request.learningObjective].joined(separator: " ")
        ).filter { token in
            !genericReasoningTokenPrefixes.contains(where: token.hasPrefix)
        }
        let learnerTokens = Set(substantiveTokens(learnerTask))
        let solutionTokens = Set(substantiveTokens(solution))
        guard !anchorTokens.isEmpty else { return false }
        let learnerMatches = anchorTokens.filter { anchor in
            learnerTokens.contains(where: { sharesAnchorStem(anchor, $0) })
        }
        let solutionMatches = anchorTokens.filter { anchor in
            solutionTokens.contains(where: { sharesAnchorStem(anchor, $0) })
        }
        guard !learnerMatches.isEmpty else {
            return false
        }
        if !solutionMatches.isEmpty { return true }

        // A worked solution may use the concrete entities from the prompt
        // instead of repeating its topic label (for example, “vertex/queue”
        // rather than “graph traversal”). Require at least one such shared
        // domain token so an unrelated solution cannot borrow a context label.
        let requestTokenSet = Set(anchorTokens)
        let learnerDomain = domainMechanicTokens(
            learnerTokens,
            excluding: requestTokenSet
        )
        let solutionDomain = domainMechanicTokens(
            solutionTokens,
            excluding: requestTokenSet
        )
        if learnerDomain.contains(where: { learner in
            solutionDomain.contains(where: { sharesAnchorStem(learner, $0) })
        }) {
            return true
        }

        // In symbolic algebra/proof, the prompt's equation may carry the
        // concrete subject while the worked response naturally speaks only of
        // coefficients, sides, factors, or an unknown. Accept that ordinary
        // wording only after the learner task itself matched the request.
        let hasExplicitMathRelation = learnerTask.contains("$$")
            && ["=", "≤", "≥", "=>", "→"].contains(where: learnerTask.contains)
        return (request.style == .numerical || request.style == .proofOrDerivation)
            && hasExplicitMathRelation
            && solutionDomain.count >= 2
    }

    private static func sharesAnchorStem(_ lhs: String, _ rhs: String) -> Bool {
        if lhs == rhs { return true }
        guard lhs.count >= 4, rhs.count >= 4 else { return false }
        let prefixLength = min(6, min(lhs.count, rhs.count))
        return lhs.prefix(prefixLength) == rhs.prefix(prefixLength)
    }

    private static func bounded(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func uniqueBounded(_ values: [String]) -> [String] {
        Array(NSOrderedSet(array: values.map(bounded).filter { !$0.isEmpty }))
            .compactMap { $0 as? String }
    }

    private static func canonical(_ value: String) -> String {
        substantiveTokens(value).joined(separator: " ")
    }

    private static func tokenSimilarity(_ lhs: [String], _ rhs: [String]) -> Double {
        let left = Set(lhs)
        let right = Set(rhs)
        guard !left.isEmpty, !right.isEmpty else { return 0 }
        return Double(left.intersection(right).count) / Double(left.union(right).count)
    }

    private static func explanationRestatesAnswer(explanation: String, answer: String) -> Bool {
        let explanationTokens = substantiveTokens(explanation)
        let answerTokens = substantiveTokens(answer)
        guard answerTokens.count >= 3 else { return false }
        if explanationTokens == answerTokens { return true }
        return explanationTokens.count <= answerTokens.count + 3
            && tokenSimilarity(explanationTokens, answerTokens) >= 0.9
    }

    private static func isGenericQuestionSurface(
        prompt: String,
        context: String,
        answer: String,
        explanation: String,
        hint: String,
        decisiveStep: String,
        request: NFAuthoringRequest
    ) -> Bool {
        let surface = [prompt, answer, explanation, hint, decisiveStep]
            .joined(separator: " ")
            .folding(
                options: [.caseInsensitive, .diacriticInsensitive],
                locale: Locale(identifier: "en_US_POSIX")
            )
        let genericFragments = [
            "one important consideration",
            "relevant information",
            "available evidence",
            "supports the conclusion",
            "resulting conclusion",
            "most relevant detail",
            "key information",
            "explain why the conclusion follows",
            "describe one important",
            "analyzing this topic"
        ]
        if genericFragments.filter(surface.contains).count >= 2 {
            return true
        }
        if isJapaneseLocale(request.localeIdentifier) {
            guard hasConcreteJapaneseLearnerTask(learnerSurface: [prompt, context].joined(separator: " "), request: request) else {
                return true
            }
            return isGenericJapaneseSolution(
                [answer, explanation, decisiveStep].joined(separator: " ")
            )
        }
        let requestTokens = Set(substantiveTokens(
            [request.customTopic, request.learningObjective, request.field.title, request.lab.title]
                .joined(separator: " ")
        ))
        let learnerSurface = [prompt, context].joined(separator: " ")
        let learnerTokens = Set(substantiveTokens(learnerSurface))
        let learnerMechanics = domainMechanicTokens(
            learnerTokens,
            excluding: requestTokens
        )
        let solutionTokens = Set(substantiveTokens(
            [answer, explanation, decisiveStep].joined(separator: " ")
        ))
        let solutionMechanics = domainMechanicTokens(
            solutionTokens,
            excluding: requestTokens
        )

        // The learner must receive a standalone task before revealing the
        // model's reference answer. Hidden answer/explanation text therefore
        // cannot supply missing operands, observations, constraints, or data.
        guard hasConcreteLearnerTask(
            learnerSurface,
            mechanicTokens: learnerMechanics,
            request: request
        ) else { return true }

        // Also reject polished meta-rubrics whose answer merely tells the
        // learner to organize, derive, interpret, or verify something without
        // naming a domain operation beyond the words echoed from the request.
        return solutionMechanics.count < 2
    }

    private static func hasConcreteJapaneseLearnerTask(
        learnerSurface: String,
        request: NFAuthoringRequest
    ) -> Bool {
        let compact = learnerSurface.trimmingCharacters(in: .whitespacesAndNewlines)
        let numbers = numericValues(in: compact)
        let hasMath = compact.contains("$$") || ["=", "≤", "≥", "→", "=>"].contains(where: compact.contains)
        let hasCode = compact.components(separatedBy: "```").count >= 3
        let asksQuestion = ["？", "?", "求め", "計算", "説明", "述べ", "示し", "証明", "設計", "解釈", "特定", "修正", "変換", "回転", "反転", "移動", "デバッグ"].contains(where: compact.contains)
        let unresolved = [
            "この場合", "このケース", "このシナリオ", "上記", "以下の情報",
            "与えられた情報", "要求された結果", "要求された主張", "このトピック"
        ]
        guard !unresolved.contains(where: compact.contains) else { return false }

        switch request.style {
        case .multipleChoice:
            return false
        case .shortAnswer:
            return asksQuestion && japaneseSubstantiveCharacterCount(compact) >= 18
        case .numerical:
            let hasQuantityRole = [
                "長さ", "質量", "時間", "速度", "加速度", "力", "温度", "圧力",
                "体積", "面積", "距離", "確率", "割合", "比率", "個", "メートル",
                "センチ", "ミリ", "キロ", "グラム", "秒", "分", "時", "単位"
            ].contains(where: compact.contains)
            let hasRelation = [
                "加え", "足し", "引き", "差", "掛け", "乗じ", "割り", "除し",
                "変換", "換算", "あたり", "等し", "増加", "減少", "求め", "計算"
            ].contains(where: compact.contains)
            return hasMath || (!numbers.isEmpty && hasQuantityRole && hasRelation)
        case .dataInterpretation:
            let hasDataRole = [
                "表", "行", "列", "群", "標本", "平均", "中央値", "割合", "率",
                "分布", "区間", "傾向", "ベースライン", "測定", "対照", "処置"
            ].contains(where: compact.contains)
            let hasBoundValues = numbers.count >= 2 && japaneseLabeledQuantityCount(in: compact) >= 2
            let hasQualitativeContrast = [
                "増加", "減少", "高い", "低い", "横ばい", "差", "一方",
                "対して", "より", "相関", "上昇", "下降"
            ].contains(where: compact.contains)
            return hasBoundValues || hasCode
                || (hasDataRole && hasQualitativeContrast && asksQuestion
                    && japaneseSubstantiveCharacterCount(compact) >= 28)
        case .spatialTransformation:
            let tuplePattern = #"[\(（\[]\s*[-+]?\d+(?:\.\d+)?\s*[,，]\s*[-+]?\d+(?:\.\d+)?(?:\s*[,，]\s*[-+]?\d+(?:\.\d+)?)?\s*[\)）\]]"#
            let hasTuple = compact.range(of: tuplePattern, options: .regularExpression) != nil
            if compact.contains("回転") {
                return hasTuple && numbers.count >= 3
                    && ["時計回り", "反時計回り", "度"].contains(where: compact.contains)
            }
            if compact.contains("反射") || compact.contains("対称移動") {
                return hasTuple && ["軸", "直線", "平面"].contains(where: compact.contains)
            }
            if compact.contains("平行移動") || compact.contains("移動") {
                return hasTuple && numbers.count >= 4
            }
            if compact.contains("射影") || compact.contains("投影") {
                return hasTuple && ["平面", "軸", "視点"].contains(where: compact.contains)
            }
            if compact.contains("行列") {
                return numbers.count >= 6 && (compact.contains("[") || compact.contains("行列"))
            }
            return false
        case .debugging:
            let hasFault = [
                "バグ", "誤り", "エラー", "失敗", "不正", "重複", "クラッシュ",
                "期待", "実際", "不変条件", "古い", "正しく"
            ].contains(where: compact.contains)
            let hasBehavior = [
                "前", "後", "とき", "場合", "しかし", "代わり", "返す", "生成",
                "二回", "一致しない"
            ].contains(where: compact.contains)
            return hasFault && (hasCode || (hasBehavior && japaneseSubstantiveCharacterCount(compact) >= 28))
        case .proofOrDerivation:
            let hasProofRequest = ["証明", "示し", "導出", "導け"].contains(where: compact.contains)
            let hasExplicitClaim = ["ならば", "であること", "等しいこと", "成り立つこと", "以下を"].contains(where: compact.contains)
            return hasProofRequest && (hasMath || hasExplicitClaim)
                && japaneseSubstantiveCharacterCount(compact) >= 20
        case .experimentalDesign:
            let hasIntervention = [
                "薬", "治療", "介入", "投与", "用量", "ワクチン", "曝露", "条件"
            ].contains(where: compact.contains)
            let hasComparison = ["対照", "プラセボ", "標準治療", "未処置"].contains(where: compact.contains)
                || compact.range(of: #"(?:群|条件|薬|治療).{0,12}(?:と|に対して).{0,12}比較"#, options: .regularExpression) != nil
            let hasOutcome = [
                "結果", "評価項目", "測定", "変化", "率", "スコア", "血圧", "回復",
                "生存", "精度", "症状", "成長", "損傷"
            ].contains(where: compact.contains)
            return hasIntervention && hasComparison && hasOutcome
                && (asksQuestion || compact.contains("無作為"))
        }
    }

    private static func isGenericJapaneseSolution(_ value: String) -> Bool {
        let genericOnly = [
            "重要な情報を特定", "関連する情報を選", "利用可能な証拠を比較",
            "結論を説明", "一貫性を確認", "適切な値を使用", "慎重に検討"
        ]
        return genericOnly.filter(value.contains).count >= 2
            || japaneseSubstantiveCharacterCount(value) < 24
    }

    private static func domainMechanicTokens(
        _ tokens: Set<String>,
        excluding requestTokens: Set<String>
    ) -> Set<String> {
        Set(tokens.filter { token in
            !requestTokens.contains(token)
                && !genericReasoningTokenPrefixes.contains(where: token.hasPrefix)
        })
    }

    private static func hasConcreteLearnerTask(
        _ learnerSurface: String,
        mechanicTokens: Set<String>,
        request: NFAuthoringRequest
    ) -> Bool {
        let folded = learnerSurface.folding(
            options: [.caseInsensitive, .diacriticInsensitive],
            locale: Locale(identifier: "en_US_POSIX")
        )
        let padded = " \(folded) "
        let learnerTokens = Set(substantiveTokens(folded))
        let numbers = numericValues(in: folded)
        let hasMathematicalArtifact = folded.contains("$$")
            || folded.contains("```")
            || folded.contains("→")
            || folded.contains("=>")
            || folded.contains("<=")
            || folded.contains(">=")
            || folded.contains("=")
        let caseMarkers = [
            " given ", " suppose ", " when ", " if ", " while ",
            " observed ", " reports ", " contains ", " has ", " where ",
            " whose ", " compared with ", " compared to ", " versus ",
            " input ", " output ", " claim ", " case ", " scenario "
        ]
        let hasCaseRelation = caseMarkers.contains(where: padded.contains)
        let requestTokens = Set(substantiveTokens(
            [request.customTopic, request.learningObjective, request.field.title, request.lab.title]
                .joined(separator: " ")
        ))
        let taskSpecificTokens = learnerTokens.subtracting(requestTokens)
        let quantitativeRolePrefixes = [
            "amount", "area", "baseline", "count", "current", "distance",
            "duration", "energy", "force", "frequency", "height", "input",
            "length", "mass", "maximum", "minimum", "output", "pressure",
            "probab", "rate", "ratio", "sample", "speed", "temperature",
            "time", "total", "unit", "velocity", "volume", "weight",
            "meter", "metre", "millimeter", "millimetre", "centimeter",
            "centimetre", "kilometer", "kilometre", "gram", "kilogram",
            "second", "minute", "hour", "liter", "litre", "radius",
            "diameter", "true", "false", "positive", "negative"
        ]
        let relationPrefixes = [
            "add", "averag", "chang", "convert", "decreas", "differ",
            "divid", "equal", "exceed", "from", "increas", "less", "minus",
            "multip", "per", "subtract", "than", "to", "versus"
        ]
        let quantitativeRoles = quantitativeRolePrefixes.filter { prefix in
            taskSpecificTokens.contains(where: { $0.hasPrefix(prefix) })
        }.count
        let hasQuantitativeRelation = containsTokenPrefix(
            relationPrefixes,
            in: taskSpecificTokens
        )
            || hasMathematicalArtifact
        let hasConcreteCase = hasMathematicalArtifact
            || !numbers.isEmpty
            || (hasCaseRelation && mechanicTokens.count >= 3)

        switch request.style {
        case .multipleChoice:
            return false
        case .numerical:
            // A numerical task needs its operands or equation before the
            // reference is revealed. A number appearing only in the answer is
            // not a learner-facing given.
            return hasMathematicalArtifact
                || (!numbers.isEmpty
                    && quantitativeRoles >= 1
                    && hasQuantitativeRelation)
        case .dataInterpretation:
            let dataSignalPrefixes = [
                "table", "row", "column", "sample", "group", "rate",
                "percent", "measur", "increas", "decreas", "distribut",
                "interval", "median", "mean", "trend", "baseline"
            ]
            return (numbers.count >= 2
                    && labeledDataQuantityCount(in: folded) >= 2)
                || folded.contains("```")
                || hasStructuredDataTable(folded)
                || (numbers.isEmpty
                    && containsTokenPrefix(dataSignalPrefixes, in: learnerTokens)
                    && hasCaseRelation && mechanicTokens.count >= 3)
        case .spatialTransformation:
            return hasCompleteSpatialTask(folded)
        case .debugging:
            return hasCompleteDebuggingTask(
                folded,
                mechanicTokens: mechanicTokens
            )
        case .proofOrDerivation:
            return hasCompleteProofTask(
                folded,
                mechanicTokens: mechanicTokens
            )
        case .experimentalDesign:
            let interventionPrefixes = [
                "drug", "dose", "treat", "therap", "intervention", "exposure",
                "program", "condition", "diet", "vaccine", "procedure"
            ]
            let comparisonPrefixes = [
                "control", "placebo", "comparison", "standard", "untreated",
                "unexposed", "baseline", "usual"
            ]
            let outcomePrefixes = [
                "outcome", "endpoint", "measure", "change", "rate", "score",
                "pressure", "enzyme", "recovery", "survival", "accuracy",
                "growth", "response", "injury", "symptom"
            ]
            let objectiveDomainTokens = Set(substantiveTokens(request.learningObjective))
                .filter { token in
                    !genericReasoningTokenPrefixes.contains(where: token.hasPrefix)
                }
            let namesIntervention = containsTokenPrefix(interventionPrefixes, in: learnerTokens)
            let namesComparison = containsTokenPrefix(comparisonPrefixes, in: learnerTokens)
            let namesOutcome = containsTokenPrefix(outcomePrefixes, in: learnerTokens)
                && objectiveDomainTokens.contains { objective in
                    learnerTokens.contains(where: { sharesAnchorStem(objective, $0) })
                }
            return namesIntervention && namesComparison && namesOutcome && hasConcreteCase
        case .shortAnswer:
            let interrogativePrefixes = [
                "what", "which", "why", "how", "when", "where", "who"
            ]
            let asksConcreteQuestion = containsTokenPrefix(
                interrogativePrefixes,
                in: learnerTokens
            )
            let unresolvedReferences = [
                " this case ", " this scenario ", " the claim ",
                " requested claim ", " requested result ", " the topic ",
                " information above ", " following information ",
                " given information "
            ]
            guard !unresolvedReferences.contains(where: padded.contains) else {
                return false
            }
            return mechanicTokens.count >= 3
                && (hasConcreteCase || asksConcreteQuestion)
        }
    }

    private static func containsTokenPrefix(
        _ prefixes: [String],
        in tokens: Set<String>
    ) -> Bool {
        prefixes.contains { prefix in
            tokens.contains(where: { $0.hasPrefix(prefix) })
        }
    }

    private static func labeledDataQuantityCount(in value: String) -> Int {
        let number = #"[-+]?(?:\d+(?:\.\d+)?|\.\d+)"#
        let role = #"(?:tp|fp|tn|fn|true\s+positives?|false\s+positives?|true\s+negatives?|false\s+negatives?|predicted\s+positives?|actual\s+positives?|treatment(?:\s+group)?|control(?:\s+group)?|baseline|follow[- ]?up|group\s+[a-z0-9]+|sample\s+[a-z0-9]+|mean|median|rate|count|probability|accuracy|precision|recall|sensitivity|specificity|temperature|score|time|distance|successes?|failures?|events?|exposed|unexposed|cases?|values?)"#
        let connector = #"(?:\s*(?:=|:)\s*|\s+(?:is|are|was|were|as|of|at|has|had)\s+|\s+)"#
        let patterns = [
            "\\b\(number)\(connector)\(role)\\b",
            "\\b\(role)\(connector)\(number)\\b"
        ]
        return patterns.reduce(0) { total, pattern in
            guard let regex = try? NSRegularExpression(
                pattern: pattern,
                options: [.caseInsensitive]
            ) else { return total }
            let range = NSRange(value.startIndex..<value.endIndex, in: value)
            return total + regex.numberOfMatches(in: value, range: range)
        }
    }

    private static func hasStructuredDataTable(_ value: String) -> Bool {
        let rows = value.split(separator: "\n").filter { $0.contains("|") }
        guard rows.count >= 2 else { return false }
        let header = String(rows[0])
        let body = rows.dropFirst().joined(separator: " ")
        return substantiveTokens(header).count >= 2
            && numericValues(in: body).count >= 2
    }

    private static func hasCompleteSpatialTask(_ value: String) -> Bool {
        let tuplePattern = #"[\(\[]\s*[-+]?\d+(?:\.\d+)?\s*,\s*[-+]?\d+(?:\.\d+)?(?:\s*,\s*[-+]?\d+(?:\.\d+)?)?\s*[\)\]]"#
        let hasTuple = value.range(
            of: tuplePattern,
            options: [.regularExpression, .caseInsensitive]
        ) != nil
        let tokens = Set(substantiveTokens(value))
        let numbers = numericValues(in: value)

        if tokens.contains(where: { $0.hasPrefix("rotat") }) {
            let directionIsSpecified = tokens.contains(where: {
                $0.hasPrefix("clockwise") || $0.hasPrefix("counterclockwise")
            }) || numbers.contains(where: { abs(abs($0).truncatingRemainder(dividingBy: 360) - 180) < 0.000_001 })
            return hasTuple && numbers.count >= 3 && directionIsSpecified
        }
        if tokens.contains(where: { $0.hasPrefix("reflect") }) {
            let axisIsSpecified = value.contains("x-axis")
                || value.contains("y-axis")
                || value.contains("line ")
                || value.contains("axis ")
            return hasTuple && axisIsSpecified
        }
        if tokens.contains(where: { $0.hasPrefix("translat") }) {
            return hasTuple && numbers.count >= 4
        }
        if tokens.contains(where: { $0.hasPrefix("project") }) {
            let targetIsSpecified = value.contains("plane")
                || value.contains("axis")
                || value.contains("view")
            return hasTuple && targetIsSpecified
        }
        if tokens.contains(where: { $0.hasPrefix("matrix") }) {
            return value.contains("[") && numbers.count >= 6
        }
        return false
    }

    private static func hasCompleteDebuggingTask(
        _ value: String,
        mechanicTokens: Set<String>
    ) -> Bool {
        let tokens = Set(substantiveTokens(value))
        let debuggingSignals = [
            "error", "fail", "bug", "expect", "actual", "invariant",
            "queue", "loop", "branch", "state", "record", "frontier",
            "duplicate", "stale", "crash", "incorrect", "wrong"
        ]
        guard containsTokenPrefix(debuggingSignals, in: tokens) else {
            return false
        }
        let relationMarkers = [
            " before ", " after ", " when ", " while ", " but ",
            " instead ", " expected ", " actual ", " produces ",
            " returns ", " fails ", " twice ", " duplicate "
        ]
        let padded = " \(value) "
        let hasBehavior = relationMarkers.contains(where: padded.contains)
            && mechanicTokens.count >= 3

        guard let opening = value.range(of: "```") else { return hasBehavior }
        let remainder = value[opening.upperBound...]
        guard let closing = remainder.range(of: "```") else { return false }
        let code = String(remainder[..<closing.lowerBound])
        let codeTokens = Set(substantiveTokens(code))
        let prose = value.replacingOccurrences(of: code, with: " ")
        let proseTokens = Set(substantiveTokens(prose))
        let shared = codeTokens.filter { codeToken in
            proseTokens.contains(where: { sharesAnchorStem(codeToken, $0) })
        }
        return shared.count >= 2 && (hasBehavior || codeTokens.count >= 4)
    }

    private static func hasCompleteProofTask(
        _ value: String,
        mechanicTokens: Set<String>
    ) -> Bool {
        let padded = " \(value) "
        let claimMarkers = [" prove that ", " show that ", " demonstrate that "]
        if let marker = claimMarkers.first(where: padded.contains),
           let markerRange = padded.range(of: marker) {
            let claim = String(padded[markerRange.upperBound...])
            let claimTokens = domainMechanicTokens(
                Set(substantiveTokens(claim)),
                excluding: []
            )
            let placeholderOnly = [
                "requested", "following", "above", "stated", "given",
                "identity", "result", "claim"
            ].contains { placeholder in
                claimTokens.contains(placeholder)
            } && claimTokens.count < 5
            if !placeholderOnly && claimTokens.count >= 3 { return true }
        }

        let relationMarkers = ["=", "≤", "≥", "=>", "→", " iff ", " implies "]
        let hasExplicitRelation = relationMarkers.contains(where: value.contains)
        let proofSignals = [
            "derive", "prove", "show", "theorem", "assumption", "induction",
            "contradiction", "bound", "identity"
        ]
        return hasExplicitRelation
            && containsTokenPrefix(proofSignals, in: Set(substantiveTokens(value)))
            && mechanicTokens.count >= 3
    }

    private static func hasInvalidMathFormatting(_ value: String) -> Bool {
        let fencedSegments = value.components(separatedBy: "```")
        // A balanced sequence of fenced-code delimiters produces an odd
        // number of alternating prose and code segments. Reject an unmatched
        // opening fence instead of silently dropping the remainder.
        if fencedSegments.count.isMultiple(of: 2) {
            return true
        }
        let prose = fencedSegments.enumerated()
            .filter { $0.offset.isMultiple(of: 2) }
            .map { $0.element }
            .joined(separator: "\n")
        let displaySegments = prose.components(separatedBy: "$$")
        // A complete display block produces an odd number of alternating prose
        // and mathematics segments. Empty mathematics also renders as a broken
        // learner-facing block and must be repaired before practice begins.
        if displaySegments.count.isMultiple(of: 2) {
            return true
        }
        for index in displaySegments.indices where index % 2 == 1 {
            let equation = displaySegments[index].trimmingCharacters(in: .whitespacesAndNewlines)
            guard !equation.isEmpty, equation.count <= 2_000 else { return true }
            let openingDelimiter = displaySegments[index - 1]
            let closingDelimiter = displaySegments[index + 1]
            guard openingDelimiter.isEmpty || openingDelimiter.last == "\n",
                  closingDelimiter.isEmpty || closingDelimiter.first == "\n" else {
                return true
            }
            var braceDepth = 0
            for character in equation {
                if character == "{" { braceDepth += 1 }
                if character == "}" { braceDepth -= 1 }
                if braceDepth < 0 || braceDepth > 32 { return true }
            }
            if braceDepth != 0 { return true }
        }
        // Splitting removes every valid `$$` delimiter. Any dollar sign left
        // behind is therefore an unsupported single-dollar delimiter,
        // whether paired or unmatched.
        return displaySegments.contains { $0.contains("$") }
    }

    private static func exposesReferenceAnswer(
        _ answer: String,
        in learnerSurfaces: [String],
        style: NFQuestionStyle
    ) -> Bool {
        let surface = learnerSurfaces.joined(separator: " ")
        if style == .numerical {
            let proposedValues = numericValues(in: answer)
            let normalizedSurface = surface.folding(
                options: [.caseInsensitive, .diacriticInsensitive],
                locale: Locale(identifier: "en_US_POSIX")
            )
            if proposedValues.contains(where: { proposed in
                numericAnswerIsExplicitlyMarked(proposed, in: normalizedSurface)
            }) {
                return true
            }
        }

        let normalizedAnswer = answer
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        let normalizedSurface = surface
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        if normalizedAnswer.count >= 4 {
            return " \(normalizedSurface) ".contains(" \(normalizedAnswer) ")
        }
        guard style == .multipleChoice, !normalizedAnswer.isEmpty else { return false }
        let explicitMarkers = [
            "answer is \(normalizedAnswer)", "correct answer is \(normalizedAnswer)",
            "option \(normalizedAnswer)", "choice \(normalizedAnswer)",
            "\(normalizedAnswer) is correct"
        ]
        return explicitMarkers.contains { normalizedSurface.contains($0) }
    }

    private static func numericAnswerIsExplicitlyMarked(
        _ answer: Double,
        in surface: String
    ) -> Bool {
        let values = numericValues(in: surface)
        guard values.contains(where: { nearlyEqual($0, answer) }) else {
            return false
        }
        let normalizedAnswer = canonicalNumericString(answer)
        let answerMarkers = [
            "answer is \(normalizedAnswer)",
            "result is \(normalizedAnswer)",
            "value is \(normalizedAnswer)",
            "equals \(normalizedAnswer)",
            "= \(normalizedAnswer)",
            "exact value \(normalizedAnswer)",
            "corresponds to \(normalizedAnswer)",
            "gives \(normalizedAnswer)"
        ]
        if answerMarkers.contains(where: surface.contains) { return true }

        // A number at the very end of a direct request such as “return 2750”
        // also reveals the response even without an explicit equals marker.
        let requestMarkers = ["report", "return", "enter", "submit"]
        return requestMarkers.contains(where: surface.contains)
            && surface.trimmingCharacters(in: .whitespacesAndNewlines)
                .hasSuffix(normalizedAnswer)
    }

    private static func canonicalNumericString(_ value: Double) -> String {
        if value.rounded() == value,
           value >= Double(Int64.min), value <= Double(Int64.max) {
            return String(Int64(value))
        }
        return String(value)
    }

    private static func substantiveTokens(_ value: String) -> [String] {
        value
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count >= 3 && !anchorStopwords.contains($0) }
    }

    private static func isJapaneseLocale(_ identifier: String) -> Bool {
        identifier.lowercased().replacingOccurrences(of: "_", with: "-").hasPrefix("ja")
    }

    /// Japanese does not put spaces between ordinary content words. Preserve
    /// bounded topic/objective phrases and their script runs instead of asking
    /// the English whitespace tokenizer to invent word boundaries.
    private static func japaneseAnchorTerms(_ value: String) -> [String] {
        let normalized = value
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "ja"))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return [] }
        let separators = CharacterSet.whitespacesAndNewlines.union(
            CharacterSet(charactersIn: "、。！？,.!?・:：;；()（）[]［］{}「」『』\"'／/\\")
        )
        let runs = normalized.components(separatedBy: separators).filter {
            japaneseSubstantiveCharacterCount($0) >= 2 || $0.count >= 3
        }
        return Array(Set(runs + runs.flatMap(japaneseMeaningfulFragments))).sorted()
    }

    private static func japaneseMeaningfulFragments(_ value: String) -> [String] {
        let suffixes = [
            "について", "における", "に関する", "を用いた", "を使った", "のための",
            "を検証する", "を説明する", "を求める", "を計算する", "を設計する",
            "する", "した", "して", "である", "です", "ます"
        ]
        var terms = [value]
        for suffix in suffixes where value.hasSuffix(suffix) {
            let stem = String(value.dropLast(suffix.count))
            if japaneseSubstantiveCharacterCount(stem) >= 2 { terms.append(stem) }
        }
        return terms
    }

    private static func japaneseTermsOverlap(_ lhs: String, _ rhs: String) -> Bool {
        guard !lhs.isEmpty, !rhs.isEmpty else { return false }
        guard min(lhs.count, rhs.count) >= 3 else { return lhs == rhs }
        return lhs == rhs || lhs.contains(rhs) || rhs.contains(lhs)
    }

    private static func japaneseAnchorNGrams(_ value: String) -> Set<String> {
        let normalized = value
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "ja"))
        let runs = normalized.split { character in
            !character.unicodeScalars.allSatisfy(isJapaneseScalar)
        }
        var grams: Set<String> = []
        for run in runs {
            let characters = Array(run)
            guard characters.count >= 3 else { continue }
            for index in 0...(characters.count - 3) {
                let gram = String(characters[index..<(index + 3)])
                if !japaneseAnchorNGramStoplist.contains(gram) { grams.insert(gram) }
            }
        }
        return grams
    }

    private static func japaneseSubstantiveCharacterCount(_ value: String) -> Int {
        value.unicodeScalars.reduce(into: 0) { count, scalar in
            if isJapaneseScalar(scalar) { count += 1 }
        }
    }

    private static func isJapaneseScalar(_ scalar: Unicode.Scalar) -> Bool {
        let codePoint = scalar.value
        return (0x3040...0x30FF).contains(codePoint)
            || (0x31F0...0x31FF).contains(codePoint)
            || (0x3400...0x4DBF).contains(codePoint)
            || (0x4E00...0x9FFF).contains(codePoint)
            || (0xF900...0xFAFF).contains(codePoint)
            || (0xFF66...0xFF9D).contains(codePoint)
            || (0x20000...0x2FA1F).contains(codePoint)
    }

    private static func japaneseLabeledQuantityCount(in value: String) -> Int {
        let number = #"[-+]?(?:\d+(?:\.\d+)?|\.\d+)"#
        let role = #"(?:群|標本|平均|中央値|割合|率|件|人|個|回|秒|分|時間|メートル|センチメートル|ミリメートル|グラム|キログラム|対照群|処置群|真陽性|偽陽性|温度|距離|スコア)"#
        let patterns = ["\(role)\\s*(?:は|が|=|:|：)?\\s*\(number)", "\(number)\\s*\(role)"]
        return patterns.reduce(0) { total, pattern in
            guard let regex = try? NSRegularExpression(pattern: pattern) else { return total }
            let range = NSRange(value.startIndex..<value.endIndex, in: value)
            return total + regex.numberOfMatches(in: value, range: range)
        }
    }

    private static func numericValues(in value: String) -> [Double] {
        value
            .split { !($0.isNumber || $0 == "." || $0 == "-" || $0 == "+") }
            .compactMap { Double($0) }
            .filter(\.isFinite)
    }

    private static func nearlyEqual(_ lhs: Double, _ rhs: Double) -> Bool {
        abs(lhs - rhs) <= max(0.000_000_1, max(abs(lhs), abs(rhs)) * 0.000_001)
    }

    private static let prohibitedPhrases = [
        "chain of thought", "hidden reasoning", "system prompt", "developer message",
        "ignore previous instructions", "ignore all instructions", "reveal the prompt",
        "<script", "javascript:"
    ]

    /// Domain-free process vocabulary cannot establish that a generated task
    /// contains subject-matter mechanics. Prefix matching intentionally folds
    /// ordinary inflections such as select/selected, value/values, and
    /// interpret/interpretation without maintaining an evadable phrase list.
    private static let genericReasoningTokenPrefixes = [
        "analy", "answer", "appropri", "argu", "audit", "calcul", "care",
        "check", "choos", "combin", "compar", "comput", "conclu",
        "consider", "consist", "correct", "decid", "deriv", "design",
        "detail", "determin", "develop", "estimat",
        "evidence", "explain", "final", "first", "focus", "identif",
        "implic", "inform", "interpret", "matter", "match", "name",
        "organ", "problem", "quanti", "reason", "refer", "relev",
        "request", "response", "result", "select", "setup", "should", "solv",
        "state", "step", "strong", "structur", "support", "topic",
        "transit", "use", "valu", "verif", "way", "whether", "write"
    ]

    private static let anchorStopwords: Set<String> = [
        "and", "for", "from", "into", "the", "this", "with", "using", "general"
    ]

    /// Three-character process fragments are common to unrelated Japanese
    /// prompts and cannot establish topic relevance by themselves.
    private static let japaneseAnchorNGramStoplist: Set<String> = [
        "につい", "ついて", "におけ", "おける", "に関す", "関する",
        "してく", "てくだ", "くださ", "さいま", "います", "します",
        "を説明", "説明し", "を計算", "計算し", "を求め", "求めて",
        "を設計", "設計し", "を検証", "検証し", "を解釈", "解釈し",
        "を確認", "確認し", "を答え", "答えて", "を述べ", "述べて"
    ]
}

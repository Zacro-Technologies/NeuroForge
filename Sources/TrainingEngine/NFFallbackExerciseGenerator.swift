import Foundation

struct NFExerciseGenerationRequest: Codable, Equatable, Sendable {
    let seed: UInt64
    let index: Int
    let lab: TrainingLab
    let purpose: NFExercisePurpose
    let localeIdentifier: String
    let sourceContext: NFExerciseSourceContext
    let targetDifficulty: Double?
    let preferredAssessmentFormat: NFAssessmentItemFormat?
    let preferredAssessmentMechanicID: String?

    init(
        seed: UInt64,
        index: Int,
        lab: TrainingLab,
        purpose: NFExercisePurpose,
        localeIdentifier: String = "en",
        sourceContext: NFExerciseSourceContext = NFExerciseSourceContext(),
        targetDifficulty: Double? = nil,
        preferredAssessmentFormat: NFAssessmentItemFormat? = nil,
        preferredAssessmentMechanicID: String? = nil
    ) {
        self.seed = seed
        self.index = index
        self.lab = lab
        self.purpose = purpose
        self.localeIdentifier = localeIdentifier
        self.sourceContext = sourceContext
        self.targetDifficulty = targetDifficulty
        self.preferredAssessmentFormat = preferredAssessmentFormat
        self.preferredAssessmentMechanicID = preferredAssessmentMechanicID
    }
}

enum NFExerciseGenerationError: Error, Equatable, Sendable {
    case invalidIndex
    case invalidTargetDifficulty
}

/// Versioned, offline generator used whenever authored packs or AI are unavailable.
/// Its answer keys and feedback are fully deterministic; source/field context may
/// change nouns and framing but never authoritative quantities.
enum NFFallbackExerciseGenerator {
    static let schemaVersion = 2
    static let generatorVersion = 3
    static let templateVersion = 3
    static let generatorID = "nf.exercise.fallback"

    /// The authoritative number of deterministic families implemented by each
    /// lab. Catalog coverage and generator selection share this registry so a
    /// new family cannot be added to one side without failing the other side's
    /// audit.
    static func variantCount(for lab: TrainingLab) -> Int {
        switch lab {
        case .mentalMath: 10
        case .spatial: 6
        case .quantitative: 8
        case .scientificReasoning: 9
        case .logicDebugging: 9
        case .retrieval: 9
        case .transfer: 7
        }
    }

    static func generate(_ request: NFExerciseGenerationRequest) throws -> NFExercise {
        guard request.index >= 0 else { throw NFExerciseGenerationError.invalidIndex }
        if let target = request.targetDifficulty,
           !target.isFinite || !(0...1).contains(target) {
            throw NFExerciseGenerationError.invalidTargetDifficulty
        }
        try NFReleaseContentGate.requireVerified()

        let effectiveSeed = mixedSeed(for: request)
        var random = NFFallbackRandom(seed: effectiveSeed)
        let draft: Draft
        switch request.lab {
        case .mentalMath:
            draft = mentalMathDraft(request: request, random: &random)
        case .spatial:
            draft = spatialDraft(request: request, random: &random)
        case .quantitative:
            draft = quantitativeDraft(request: request, random: &random)
        case .scientificReasoning:
            draft = scientificReasoningDraft(request: request, random: &random)
        case .logicDebugging:
            draft = logicDebuggingDraft(request: request, random: &random)
        case .retrieval:
            draft = retrievalDraft(request: request, random: &random)
        case .transfer:
            draft = transferDraft(request: request, random: &random)
        }

        let poolToken = templatePoolToken(for: request.purpose)
        let templateFamily = "nf.fallback.\(request.lab.rawValue).\(poolToken).v3"
        let templateID = "\(templateFamily).\(draft.templateSlug)"
        let itemID = "\(templateID).\(String(effectiveSeed, radix: 16)).\(request.index)"
        let digest = stableDigest(
            [
                itemID,
                draft.prompt,
                canonicalEncoding(draft.interaction),
                canonicalEncoding(draft.representations),
                canonicalEncoding(draft.citations),
                canonicalEncoding(request.sourceContext),
                request.localeIdentifier,
                request.purpose.rawValue
            ].joined(separator: "|")
        )
        let groundedDocumentIDs = Array(Set(draft.citations.map(\.documentID))).sorted()
        let groundedChunkIDs = Array(Set(draft.citations.compactMap(\.sourceChunkID))).sorted()
        let provenance = NFExerciseProvenance(
            contentTier: .deterministicGenerated,
            generatorID: generatorID,
            generatorVersion: generatorVersion,
            modelIdentifier: nil,
            promptVersion: nil,
            sourceDocumentIDs: groundedDocumentIDs,
            sourceChunkIDs: groundedChunkIDs,
            contentDigest: digest,
            validatorVersion: NFExerciseSchemaValidator.validatorVersion,
            isSourceGrounded: !draft.citations.isEmpty
        )
        let feedbackTiming: NFExerciseFeedbackTiming = request.purpose.delaysFeedback
            ? .afterAssessmentBlock
            : .immediate
        let domainPackTags: [String] = if request.lab == .mentalMath,
            let pack = NFMentalMathDomainPackCatalog.pack(
                matching: request.sourceContext.primaryField,
                localeIdentifier: request.localeIdentifier
            ) {
            ["domain-pack.\(pack.id.rawValue)"]
        } else {
            []
        }
        let exercise = NFExercise(
            id: itemID,
            schemaVersion: schemaVersion,
            generatorVersion: generatorVersion,
            templateID: templateID,
            templateFamily: templateFamily,
            templateVersion: templateVersion,
            seed: effectiveSeed,
            lab: request.lab,
            purpose: request.purpose,
            evidenceClass: request.purpose.evidenceClass,
            localeIdentifier: request.localeIdentifier,
            title: draft.title,
            prompt: draft.prompt,
            contextText: draft.contextText,
            instructions: draft.instructions,
            sourceContext: request.sourceContext,
            interaction: draft.interaction,
            difficulty: adjustedDifficulty(draft.difficulty, request: request),
            skillWeights: draft.skillWeights,
            strategies: draft.strategies,
            representations: draft.representations,
            citations: draft.citations,
            provenance: provenance,
            rubric: draft.rubric,
            feedback: NFExerciseFeedbackSpec(
                timing: feedbackTiming,
                correctTitle: localized("Supported", request: request),
                correctExplanation: draft.correctExplanation,
                retryTitle: localized("Revisit the decisive step", request: request),
                retryExplanation: draft.retryExplanation,
                decisiveStep: draft.decisiveStep,
                hintLadder: request.purpose.isProtectedAssessment ? [] : draft.hints,
                errorExplanations: draft.errorExplanations
            ),
            accessibility: draft.accessibility,
            assessmentProtected: request.purpose.isProtectedAssessment,
            expectedDurationSeconds: draft.expectedDurationSeconds,
            timingEligible: request.purpose != .documentPractice,
            responseEditPolicy: responseEditPolicy(
                for: draft.interaction,
                isProtected: request.purpose.isProtectedAssessment
            ),
            tags: [request.lab.rawValue, request.purpose.rawValue, request.sourceContext.primaryField.rawValue]
                + domainPackTags
                + draft.tags
        )
        try NFExerciseSchemaValidator.validate(exercise)
        try NFTransferTaxonomy.validate(exercise: exercise)
        return exercise
    }

    private static func responseEditPolicy(
        for interaction: NFExerciseInteraction,
        isProtected: Bool
    ) -> NFResponseEditPolicy {
        guard !isProtected else { return .lockedAfterSubmit }
        return switch interaction {
        case .orderedSteps, .shortText, .claimEvidence, .logicState:
            .editableBeforeCommit
        case .numeric, .singleChoice, .multipleChoice, .selfCheck:
            .lockedAfterSubmit
        }
    }

    // MARK: - Lab families

    private static func mentalMathDraft(
        request: NFExerciseGenerationRequest,
        random: inout NFFallbackRandom
    ) -> Draft {
        let profile = fieldProfile(request.sourceContext.primaryField, request: request)
        let variant = selectedVariant(
            request: request,
            defaultUpperBound: variantCount(for: .mentalMath),
            compatibleVariants: [
                .numericEntry: [0, 1, 2, 4, 6],
                .singleChoice: [3, 5, 7, 8, 9]
            ],
            random: &random
        )
        let strategy: NFExerciseStrategy
        let interaction: NFExerciseInteraction
        let prompt: String
        let context: String
        let decisiveStep: String
        let instructions: String
        let representations: [NFExerciseRepresentation]
        let tags: [String]
        let errorExplanations: [String: String]

        switch variant {
        case 0:
            let left = 6 + random.int(upperBound: 7)
            let right = 7 + random.int(upperBound: 6)
            prompt = localized("Rapid recall: what is \(left) × \(right)?", request: request)
            context = contextualLead(request) + localized(" Accuracy is authoritative; speed is recorded separately.", request: request)
            decisiveStep = localized("Retrieve or reconstruct the multiplication fact \(left) × \(right).", request: request)
            strategy = NFExerciseStrategy(
                id: "strategy.fact.reconstruct",
                title: localized("Retrieve, then reconstruct", request: request),
                summary: localized("Recall the fact directly; if it is not ready, split one factor and recombine exactly.", request: request),
                orderedSteps: [localized("Attempt retrieval", request: request), localized("Split one factor if needed", request: request), localized("Check the product", request: request)],
                whenToUse: localized("Common arithmetic facts", request: request)
            )
            interaction = numericInteraction(answer: Double(left * right), tolerance: .absolute(0), unit: nil)
            instructions = localized("Enter the exact integer.", request: request)
            representations = [.equation(latex: "\(left) \\times \(right)", spokenDescription: localized("\(left) times \(right)", request: request))]
            tags = ["rapid-recall", "basic-fluency"]
            errorExplanations = ["numeric_value": localized("The product is not exact; reconstruct it from a nearby known fact.", request: request)]

        case 1:
            let left = 32 + random.int(upperBound: 36)
            let nearbyFactors = [9, 11, 19, 21]
            let right = nearbyFactors[random.int(upperBound: nearbyFactors.count)]
            let nearby = right == 9 || right == 19 ? right + 1 : right - 1
            prompt = localized("Compute \(left) × \(right) mentally.", request: request)
            context = contextualLead(request) + localized(" Use the visible number structure instead of long multiplication.", request: request)
            decisiveStep = localized("Use \(right) = \(nearby) \(right < nearby ? "−" : "+") 1 and compensate once.", request: request)
            strategy = NFExerciseStrategy(
                id: "strategy.multiply.compensation",
                title: localized("Compensate from a nearby product", request: request),
                summary: localized("Multiply by a nearby round factor, then add or subtract one group.", request: request),
                orderedSteps: [localized("Choose the nearby factor", request: request), localized("Compute the easy product", request: request), localized("Compensate by one group", request: request)],
                whenToUse: localized("A multiplier is one away from a round number", request: request)
            )
            interaction = numericInteraction(answer: Double(left * right), tolerance: .absolute(0), unit: nil)
            instructions = localized("Enter the exact result.", request: request)
            representations = [.equation(latex: "\(left)(\(nearby) \(right < nearby ? "-" : "+") 1)", spokenDescription: localized("Compensate from the nearby factor", request: request))]
            tags = ["decompose", "flexible-calculation", "compensation"]
            errorExplanations = ["numeric_value": localized("Recheck whether the one-group compensation should be added or subtracted.", request: request)]

        case 2:
            let makesUnitConversion = request.preferredAssessmentMechanicID == nil
                && random.int(upperBound: 2) == 0
            if makesUnitConversion {
                let milligrams = [1_250, 2_500, 3_750, 6_250][random.int(upperBound: 4)]
                let grams = Double(milligrams) / 1_000
                prompt = localized("Representation relay: convert \(milligrams) milligrams to grams.", request: request)
                context = contextualLead(request) + localized(" Preserve the mass dimension while changing the metric scale.", request: request)
                decisiveStep = localized("Use 1 gram = 1,000 milligrams, so divide the numeric value by 1,000 and retain mass units.", request: request)
                strategy = NFExerciseStrategy(
                    id: "strategy.units.metric-scale",
                    title: localized("Scale while preserving dimension", request: request),
                    summary: localized("Use a conversion ratio equal to one, cancel the original unit, and check the direction of scale change.", request: request),
                    orderedSteps: [localized("Name the physical dimension", request: request), localized("Write the conversion ratio", request: request), localized("Cancel milligrams", request: request), localized("Check that grams are numerically smaller", request: request)],
                    whenToUse: localized("Exact metric unit conversion", request: request)
                )
                interaction = numericInteraction(
                    answer: grams,
                    tolerance: .absolute(0),
                    unit: "g",
                    acceptedUnits: ["gram", "grams"],
                    precision: 3,
                    authoritativeValue: try! NFExactNumber(
                        numerator: Int64(milligrams),
                        denominator: 1_000
                    )
                )
                instructions = localized("Enter the exact value and its gram unit.", request: request)
                representations = [.equation(
                    latex: "\(milligrams)\\,\\mathrm{mg} \\times \\frac{1\\,\\mathrm{g}}{1000\\,\\mathrm{mg}}",
                    spokenDescription: localized("\(milligrams) milligrams times one gram per one thousand milligrams", request: request)
                )]
                tags = ["representation-relay", "unit-conversion", "unit-handling", "metric-prefixes"]
                errorExplanations = [
                    "numeric_value": localized("The metric scale changed in the wrong direction or by the wrong power of ten.", request: request),
                    "unit_missing": localized("An exact quantity needs its destination gram unit.", request: request),
                    "unit_mismatch": localized("Report the converted mass in grams.", request: request)
                ]
            } else {
                let numerator = [1, 2, 3, 5, 7][random.int(upperBound: 5)]
                let denominator = [4, 5, 8, 10][random.int(upperBound: 4)]
                let percentage = 100 * Double(numerator) / Double(denominator)
                let exactPercentage = try! NFExactNumber(
                    numerator: Int64(100 * numerator),
                    denominator: Int64(denominator)
                )
                prompt = localized("Which percentage is equivalent to \(numerator)/\(denominator)?", request: request)
                context = contextualLead(request) + localized(" Convert the rational value without changing its scale.", request: request)
                decisiveStep = localized("Compute numerator ÷ denominator, then multiply by 100.", request: request)
                strategy = NFExerciseStrategy(
                    id: "strategy.representation.rational",
                    title: localized("Use one invariant value", request: request),
                    summary: localized("A fraction, decimal, and percentage name the same ratio at different scales.", request: request),
                    orderedSteps: [localized("Divide numerator by denominator", request: request), localized("Scale by 100", request: request), localized("Check against one-half or one whole", request: request)],
                    whenToUse: localized("Fraction–decimal–percentage conversion", request: request)
                )
                interaction = numericInteraction(
                    answer: percentage,
                    tolerance: .absolute(0.001),
                    unit: "%",
                    acceptedUnits: ["percent"],
                    authoritativeValue: exactPercentage
                )
                instructions = localized("Enter the percentage and its unit.", request: request)
                representations = [.equation(latex: "\\frac{\(numerator)}{\(denominator)} = ?\\%", spokenDescription: localized("\(numerator) over \(denominator) as a percentage", request: request))]
                tags = ["representation-relay", "fractions", "percentages"]
                errorExplanations = [
                    "numeric_value": localized("The fraction-to-decimal or decimal-to-percent scale is incorrect.", request: request),
                    "unit_missing": localized("Label the converted value as a percentage.", request: request),
                    "unit_mismatch": localized("This relay asks for a percentage representation.", request: request)
                ]
            }

        case 3:
            let coefficient = [12, 25, 36, 48][random.int(upperBound: 4)]
            let exponent = 2 + random.int(upperBound: 5)
            var options = [
                NFChoiceOption(id: "correct", text: localized("\(format(Double(coefficient) / 10)) × 10^\(exponent + 1)", request: request), accessibilityLabel: nil, distractorCode: nil),
                NFChoiceOption(id: "coefficient", text: localized("\(coefficient) × 10^\(exponent)", request: request), accessibilityLabel: nil, distractorCode: "coefficient_not_normalized"),
                NFChoiceOption(id: "exponent", text: localized("\(format(Double(coefficient) / 10)) × 10^\(exponent)", request: request), accessibilityLabel: nil, distractorCode: "exponent"),
                NFChoiceOption(id: "direction", text: localized("\(format(Double(coefficient) / 10)) × 10^\(exponent - 1)", request: request), accessibilityLabel: nil, distractorCode: "place_value")
            ]
            random.shuffle(&options)
            prompt = localized("Normalize \(coefficient) × 10^\(exponent) into scientific notation.", request: request)
            context = contextualLead(request) + localized(" The coefficient must be at least 1 and less than 10.", request: request)
            decisiveStep = localized("Moving the decimal one place left increases the exponent by one.", request: request)
            strategy = NFExerciseStrategy(
                id: "strategy.scientific-notation.normalize",
                title: localized("Balance coefficient and exponent", request: request),
                summary: localized("Every decimal shift in the coefficient requires the opposite power-of-ten adjustment.", request: request),
                orderedSteps: [localized("Normalize the coefficient", request: request), localized("Count the decimal shift", request: request), localized("Compensate in the exponent", request: request)],
                whenToUse: localized("Scientific-notation repair and comparison", request: request)
            )
            interaction = .singleChoice(NFSingleChoiceResponseSchema(options: options, correctOptionID: "correct"))
            instructions = localized("Choose the normalized equivalent.", request: request)
            representations = [.equation(latex: "\(coefficient) \\times 10^{\(exponent)}", spokenDescription: localized("\(coefficient) times ten to the \(exponent)", request: request))]
            tags = ["scientific-notation-shift", "exponents", "stem-numeracy"]
            errorExplanations = [
                "coefficient_not_normalized": localized("The value is equivalent, but the coefficient is not normalized.", request: request),
                "exponent": localized("The exponent must compensate for the decimal shift.", request: request),
                "place_value": localized("The decimal and exponent moved in the same direction, changing the value.", request: request)
            ]

        case 4:
            let multiplier = 4 + random.int(upperBound: 8)
            let missing = 6 + random.int(upperBound: 15)
            let product = multiplier * missing
            prompt = localized("Find the unique missing value: □ × \(multiplier) = \(product).", request: request)
            context = contextualLead(request) + localized(" Solve by the inverse operation, then verify forward.", request: request)
            decisiveStep = localized("Divide \(product) by \(multiplier), then multiply back to verify.", request: request)
            strategy = NFExerciseStrategy(
                id: "strategy.inverse.operation",
                title: localized("Undo with the inverse", request: request),
                summary: localized("Isolate the unknown by reversing the stated operation.", request: request),
                orderedSteps: [localized("Identify the applied operation", request: request), localized("Apply its inverse", request: request), localized("Verify in the original relation", request: request)],
                whenToUse: localized("Missing-number and inverse-relation problems", request: request)
            )
            interaction = numericInteraction(answer: Double(missing), tolerance: .absolute(0), unit: nil)
            instructions = localized("Enter the exact missing integer.", request: request)
            representations = [.equation(latex: "x \\times \(multiplier) = \(product)", spokenDescription: localized("x times \(multiplier) equals \(product)", request: request))]
            tags = ["missing-number", "inverse-operation"]
            errorExplanations = ["numeric_value": localized("The value does not reproduce the original product when multiplied forward.", request: request)]

        case 5:
            let base = [80, 120, 160, 240][random.int(upperBound: 4)]
            let percent = [20, 25, 40][random.int(upperBound: 3)]
            let correct = base * percent / 100
            var options = [
                NFChoiceOption(id: "correct", text: localized("Step 1: convert \(percent)% to \(Double(percent) / 100); step 2: multiply by \(base) to get \(correct).", request: request), accessibilityLabel: nil, distractorCode: nil),
                NFChoiceOption(id: "base", text: localized("Step 1: divide \(percent) by \(base); step 2: multiply by 100.", request: request), accessibilityLabel: nil, distractorCode: "percentage_base"),
                NFChoiceOption(id: "place", text: localized("Step 1: use \(percent) as the decimal; step 2: multiply by \(base).", request: request), accessibilityLabel: nil, distractorCode: "place_value"),
                NFChoiceOption(id: "operation", text: localized("Step 1: add \(percent) to \(base); step 2: divide by 100.", request: request), accessibilityLabel: nil, distractorCode: "operation_selection")
            ]
            random.shuffle(&options)
            prompt = localized("Error detective: which trace correctly computes \(percent)% of \(base)?", request: request)
            context = contextualLead(request) + localized(" Identify the first operation that controls plausibility.", request: request)
            decisiveStep = localized("The percentage is a multiplier with \(base) as the whole.", request: request)
            strategy = NFExerciseStrategy(
                id: "strategy.error.first-step",
                title: localized("Audit the first decisive step", request: request),
                summary: localized("Check the percentage base and scale before inspecting later arithmetic.", request: request),
                orderedSteps: [localized("Name the whole", request: request), localized("Normalize the percent", request: request), localized("Verify the result is plausible", request: request)],
                whenToUse: localized("Calculation and spreadsheet-like audits", request: request)
            )
            interaction = .singleChoice(NFSingleChoiceResponseSchema(options: options, correctOptionID: "correct"))
            instructions = localized("Choose the valid trace.", request: request)
            representations = [.equation(latex: "\(percent)\\% \\text{ of } \(base)", spokenDescription: localized("\(percent) percent of \(base)", request: request))]
            tags = ["error-detective", "percentage-base", "plausibility"]
            errorExplanations = [
                "percentage_base": localized("The trace uses the wrong whole as its percentage base.", request: request),
                "place_value": localized("A percentage must be divided by 100 before multiplication.", request: request),
                "operation_selection": localized("Adding the percentage label does not compute a share of the whole.", request: request)
            ]

        case 6:
            let start = 20 + random.int(upperBound: 21)
            let add = 4 + random.int(upperBound: 7)
            let multiplier = [2, 3][random.int(upperBound: 2)]
            let subtract = 3 + random.int(upperBound: 8)
            let answer = (start + add) * multiplier - subtract
            let chain = NFCalculationChainContract(
                initialValue: try! NFExactNumber(numerator: Int64(start)),
                operations: [
                    .add(try! NFExactNumber(numerator: Int64(add))),
                    .multiply(try! NFExactNumber(numerator: Int64(multiplier))),
                    .subtract(try! NFExactNumber(numerator: Int64(subtract)))
                ]
            )
            prompt = localized("Calculation chain: start at \(start), add \(add), multiply by \(multiplier), then subtract \(subtract). What is the final value?", request: request)
            context = contextualLead(request) + localized(" Preserve operation order and intermediate state.", request: request)
            decisiveStep = localized("Apply each transformation to the previous result: (\(start) + \(add)) × \(multiplier) − \(subtract).", request: request)
            strategy = NFExerciseStrategy(
                id: "strategy.chain.checkpoints",
                title: localized("Keep compact checkpoints", request: request),
                summary: localized("Retain one exact intermediate value after every transformation.", request: request),
                orderedSteps: [localized("Apply the addition", request: request), localized("Multiply the new state", request: request), localized("Subtract from that result", request: request)],
                whenToUse: localized("Sequential mental calculations", request: request)
            )
            interaction = numericInteraction(answer: Double(answer), tolerance: .absolute(0), unit: nil)
            instructions = localized("Enter the exact final value.", request: request)
            representations = [
                .equation(latex: "(\(start)+\(add))\\times\(multiplier)-\(subtract)", spokenDescription: localized("Add, multiply, then subtract", request: request)),
                .logicState(chain.representation)
            ]
            tags = ["calculation-chain", "multi-step-control"]
            errorExplanations = ["numeric_value": localized("Replay the chain one transition at a time; do not apply all operations to the starting value.", request: request)]

        case 7:
            let count = 198 + random.int(upperBound: 5)
            let rate = 48 + random.int(upperBound: 6)
            let exact = count * rate
            let closest = Int(pow(10.0, round(log10(Double(exact)))))
            var magnitudes = Set([closest, max(1, closest / 10), closest * 10, count + rate])
            while magnitudes.count < 4 { magnitudes.insert(closest + magnitudes.count * 1_000) }
            var options = magnitudes.sorted().map { value in
                NFChoiceOption(
                    id: value == closest ? "correct" : "magnitude.\(value)",
                    text: value.formatted(),
                    accessibilityLabel: nil,
                    distractorCode: value == closest ? nil : "place_value"
                )
            }
            random.shuffle(&options)
            prompt = localized("Estimate \(count) × \(rate) first, record whether that estimate makes the exact result plausible, then calculate the exact product.", request: request)
            context = contextualLead(request) + localized(" Estimate, plausibility judgment, and exact response are captured as separate fields in that order.", request: request)
            decisiveStep = localized("Round to about 200 × 50, then identify the nearest power-of-ten scale.", request: request)
            strategy = NFExerciseStrategy(
                id: "strategy.estimate.bounds",
                title: localized("Round structurally", request: request),
                summary: localized("Round each factor to one useful digit and preserve the operation.", request: request),
                orderedSteps: [localized("Round each factor", request: request), localized("Compute the approximate product", request: request), localized("Check the power of ten", request: request)],
                whenToUse: localized("Plausibility checks before exact work", request: request)
            )
            if request.purpose.isProtectedAssessment || request.preferredAssessmentFormat == .singleChoice {
                interaction = .singleChoice(NFSingleChoiceResponseSchema(options: options, correctOptionID: "correct"))
                instructions = localized("Choose the closest magnitude.", request: request)
            } else {
                let contract = NFEstimateExactContract(
                    estimate: String(closest),
                    acceptedEstimateAlternatives: [closest.formatted()],
                    plausibility: localized("plausible", request: request),
                    acceptedPlausibilityAlternatives: [localized("yes", request: request)],
                    exact: String(exact),
                    acceptedExactAlternatives: [exact.formatted()]
                )
                interaction = .logicState(contract.responseSchema)
                instructions = localized("Enter the estimate first, make a plausibility judgment second, and enter the exact result third.", request: request)
            }
            representations = [.equation(latex: "\(count) \\times \(rate) \\approx ?", spokenDescription: localized("Estimate the product", request: request))]
            tags = ["estimate-first", "order-of-magnitude"]
            errorExplanations = [
                "place_value": localized("The estimate is on the wrong power-of-ten scale.", request: request),
                "logic_state": localized("Keep the estimate, plausibility judgment, and exact result separate; use the estimate to audit the exact magnitude.", request: request)
            ]

        case 8:
            var options = [
                NFChoiceOption(id: "correct", text: localized("Use code or a spreadsheet with an auditable formula and spot-checks.", request: request), accessibilityLabel: nil, distractorCode: nil),
                NFChoiceOption(id: "mental", text: localized("Do every calculation mentally to maximize difficulty.", request: request), accessibilityLabel: nil, distractorCode: "tool_judgment"),
                NFChoiceOption(id: "calculator", text: localized("Use a calculator once without preserving inputs or method.", request: request), accessibilityLabel: nil, distractorCode: "auditability"),
                NFChoiceOption(id: "estimate", text: localized("Use only a rough estimate even though exact reproducible values are required.", request: request), accessibilityLabel: nil, distractorCode: "precision_requirement")
            ]
            random.shuffle(&options)
            prompt = localized("A \(profile.entity) workflow must repeat the same conversion for 12,000 records and preserve an audit trail. Which tool choice is most appropriate?", request: request)
            context = contextualLead(request) + localized(" Tool judgment is scored, not maximal mental effort.", request: request)
            decisiveStep = localized("Repeated exact work with an audit requirement favors a reproducible scripted or spreadsheet method.", request: request)
            strategy = NFExerciseStrategy(
                id: "strategy.tool.cost-model",
                title: localized("Match tool to risk and repetition", request: request),
                summary: localized("Choose based on precision, repeat count, consequence of error, and auditability.", request: request),
                orderedSteps: [localized("Assess precision", request: request), localized("Assess repetition", request: request), localized("Assess audit needs", request: request), localized("Choose the lightest adequate tool", request: request)],
                whenToUse: localized("Mental-or-machine decisions", request: request)
            )
            interaction = .singleChoice(NFSingleChoiceResponseSchema(options: options, correctOptionID: "correct"))
            instructions = localized("Choose the defensible tool.", request: request)
            representations = [.prose]
            tags = ["mental-or-machine", "tool-judgment", "auditability"]
            errorExplanations = [
                "tool_judgment": localized("Mental work is not the appropriate default for high-volume exact repetition.", request: request),
                "auditability": localized("A one-off answer without preserved inputs is difficult to audit.", request: request),
                "precision_requirement": localized("A rough estimate cannot replace the required exact reproducible output.", request: request)
            ]

        default:
            let left = 46 + random.int(upperBound: 13)
            let right = [19, 21, 25][random.int(upperBound: 3)]
            var options = [
                NFChoiceOption(
                    id: "correct",
                    text: right == 25
                        ? localized("Divide by 4, then multiply by 100.", request: request)
                        : localized("Use a nearby round multiplier and compensate once.", request: request),
                    accessibilityLabel: nil,
                    distractorCode: nil
                ),
                NFChoiceOption(id: "repeat", text: localized("Add \(left) repeatedly \(right) times.", request: request), accessibilityLabel: nil, distractorCode: "strategy_cost"),
                NFChoiceOption(id: "long", text: localized("Use the standard written multiplication algorithm mentally digit by digit.", request: request), accessibilityLabel: nil, distractorCode: "strategy_cost"),
                NFChoiceOption(id: "guess", text: localized("Round both factors and stop without compensating.", request: request), accessibilityLabel: nil, distractorCode: "rounding")
            ]
            random.shuffle(&options)
            prompt = localized("Strategy duel: which method most efficiently computes \(left) × \(right) exactly?", request: request)
            context = contextualLead(request) + localized(" Choose efficiency for this number structure, not a universally preferred method.", request: request)
            decisiveStep = right == 25 ? localized("Multiplication by 25 is multiplication by 100 followed by division by 4.", request: request) : localized("The multiplier is one away from a round number.", request: request)
            strategy = NFExerciseStrategy(
                id: "strategy.duel.structure",
                title: localized("Let the numbers choose the method", request: request),
                summary: localized("Prefer a valid shortcut whose compensation cost is smallest for the visible structure.", request: request),
                orderedSteps: [localized("Inspect the factors", request: request), localized("Compare valid method costs", request: request), localized("Choose and verify", request: request)],
                whenToUse: localized("Strategy comparison", request: request)
            )
            interaction = .singleChoice(NFSingleChoiceResponseSchema(options: options, correctOptionID: "correct"))
            instructions = localized("Choose the most efficient exact strategy.", request: request)
            representations = [.equation(latex: "\(left) \\times \(right)", spokenDescription: localized("\(left) times \(right)", request: request))]
            tags = ["strategy-duel", "strategy-flexibility"]
            errorExplanations = [
                "strategy_cost": localized("The method is valid in principle but needlessly expensive for this number structure.", request: request),
                "rounding": localized("An estimate is not an exact strategy unless the rounding is compensated.", request: request)
            ]
        }

        let correctExplanation = switch variant {
        case 0:
            localized("The exact product is the stated multiplication fact; reconstructing it by decomposition must give the same integer.", request: request)
        case 1:
            localized("The nearby round-factor product is adjusted by exactly one group, so the compensation preserves the original multiplication.", request: request)
        case 2 where tags.contains("unit-conversion"):
            localized("The conversion ratio equals one: milligrams cancel, grams remain, and dividing by 1,000 changes only the metric scale.", request: request)
        case 2:
            localized("The fraction, decimal, and percentage represent the same ratio; multiplying the decimal by 100 gives the requested percentage scale.", request: request)
        case 3:
            localized("Scientific notation preserves value by pairing each leftward decimal shift with an increase of one in the power-of-ten exponent.", request: request)
        case 4:
            localized("Division undoes the stated multiplication, and substituting the result back reproduces the original product.", request: request)
        case 5:
            localized("The whole is the percentage base; converting the percent to a decimal multiplier before applying it produces the supported share.", request: request)
        case 6:
            localized("Each operation acts on the previous checkpoint, so preserving the stated order yields the final chain value.", request: request)
        case 7:
            localized("Rounding the factors establishes the expected magnitude; the exact product is plausible only when it stays on that audited scale.", request: request)
        case 8:
            localized("High-volume exact repetition plus an audit trail favors reproducible code or a spreadsheet with preserved formulas and spot-checks.", request: request)
        default:
            localized("The selected strategy exploits the visible factor structure while preserving an exact result with the least unnecessary work.", request: request)
        }

        return Draft(
            templateSlug: variant == 2 && tags.contains("unit-conversion") ? "unit-conversion.metric" : [
                "rapid-recall", "decompose.compensation", "representation-relay", "scientific-notation",
                "missing-number", "error-detective", "calculation-chain", "estimate-first",
                "mental-or-machine", "strategy-duel"
            ][variant],
            title: localized("Numerical control", request: request),
            prompt: prompt,
            contextText: context,
            instructions: instructions,
            interaction: interaction,
            difficulty: difficulty(base: 0.3 + Double(variant % 5) * 0.055, steps: 2 + variant / 4, shift: variant == 2 || variant == 3 ? 0.45 : 0.15),
            skillWeights: ["skill.mentalMath": 0.75, "skill.quantitative": 0.25],
            strategies: [strategy],
            representations: representations,
            citations: [],
            rubric: exactRubric(localized("Correct deterministic response", request: request)),
            correctExplanation: correctExplanation,
            retryExplanation: localized("Set up the operation before doing the arithmetic, then verify the order of magnitude.", request: request),
            decisiveStep: decisiveStep,
            hints: [localized("Name the operation before calculating.", request: request), decisiveStep],
            errorExplanations: errorExplanations,
            accessibility: standardAccessibility(label: prompt),
            expectedDurationSeconds: 55,
            tags: ["arithmetic"] + tags
        )
    }

    private static func spatialDraft(
        request: NFExerciseGenerationRequest,
        random: inout NFFallbackRandom
    ) -> Draft {
        let variant = selectedVariant(
            request: request,
            defaultUpperBound: variantCount(for: .spatial),
            compatibleVariants: [
                .singleChoice: Array(0..<6),
                .diagramMatch: Array(0..<6)
            ],
            random: &random
        )
        let templateSlug: String
        let operation: NFSpatialOperation
        let stimulusCategory: String
        let dimension: NFSpatialDimension
        let objectDescription: String
        let viewpoint: String
        let points: [NFSpatialPoint]
        let axisLabels: [String]
        let prompt: String
        let correctText: String
        let distractors: [(text: String, code: String)]
        let accessibilityDescription: String
        let tags: [String]
        let rotationMagnitudeDegrees: Double
        let objectComplexity: Double
        let distractorSimilarity: Double

        switch variant {
        case 0:
            // Keep a broad authored parameter space so the bundled spatial
            // bank can rotate without reusing the same coordinate contract.
            // Values stay small enough for the transformation—not arithmetic—
            // to remain the task's primary demand.
            let x = 2 + random.int(upperBound: 40)
            let y = 1 + random.int(upperBound: 40)
            let correct = (-y, x)
            templateSlug = "coordinate.rotate-ccw"
            operation = .coordinateTransform
            stimulusCategory = "coordinate-geometry"
            dimension = .twoDimensional
            objectDescription = localized("A labeled point on a Cartesian coordinate plane", request: request)
            viewpoint = localized("Front orthographic view", request: request)
            points = [NFSpatialPoint(label: localized("P", request: request), x: Double(x), y: Double(y), z: nil)]
            axisLabels = [localized("x", request: request), localized("y", request: request)]
            prompt = localized("Point P is at (\(x), \(y)). Where is P after a 90° counterclockwise rotation about the origin?", request: request)
            correctText = localized("(\(correct.0), \(correct.1))", request: request)
            distractors = [
                (localized("(\(y), \(x))", request: request), "axis_swap"),
                (localized("(\(x), \(-y))", request: request), "sign_direction"),
                (localized("(\(-x), \(y))", request: request), "wrong_transform")
            ]
            accessibilityDescription = localized("Point P begins at x \(x), y \(y); rotate its coordinate pair counterclockwise by ninety degrees.", request: request)
            tags = ["coordinate-transformation", "2d-rotation", "coordinate-geometry"]
            rotationMagnitudeDegrees = 90
            objectComplexity = 0.28
            distractorSimilarity = 0.68

        case 1:
            let x = 1 + random.int(upperBound: 24)
            let y = 1 + random.int(upperBound: 24)
            let z = 1 + random.int(upperBound: 12)
            let correct = (-y, x, z)
            templateSlug = "rotation.3d-z-axis"
            operation = .rotate
            stimulusCategory = "molecular-structure"
            dimension = .threeDimensional
            objectDescription = localized("A three-dimensional labeled atom position represented as a vector", request: request)
            viewpoint = localized("Positive z-axis remains fixed", request: request)
            points = [NFSpatialPoint(label: localized("A", request: request), x: Double(x), y: Double(y), z: Double(z))]
            axisLabels = [localized("x", request: request), localized("y", request: request), localized("z", request: request)]
            prompt = localized("A molecular point A is at (\(x), \(y), \(z)). Rotate it 90° counterclockwise about the z-axis. Which coordinate is correct?", request: request)
            correctText = localized("(\(correct.0), \(correct.1), \(correct.2))", request: request)
            distractors = [
                (localized("(\(y), \(-x), \(z))", request: request), "rotation_direction"),
                (localized("(\(-y), \(x), \(-z))", request: request), "fixed_axis"),
                (localized("(\(x), \(z), \(y))", request: request), "axis_swap")
            ]
            accessibilityDescription = localized("Point A has x \(x), y \(y), z \(z). A quarter-turn about z maps x and y while leaving z fixed.", request: request)
            tags = ["3d-rotation", "molecular-structure", "procedural-object"]
            rotationMagnitudeDegrees = 90
            objectComplexity = 0.56
            distractorSimilarity = 0.76

        case 2:
            let solidIndex = random.int(upperBound: 3)
            let solid = [localized("cube", request: request), localized("right circular cylinder", request: request), localized("sphere", request: request)][solidIndex]
            let section = [localized("square", request: request), localized("circle", request: request), localized("circle", request: request)][solidIndex]
            templateSlug = "cross-section.\(["cube", "cylinder", "sphere"][solidIndex])"
            operation = .crossSection
            stimulusCategory = "mechanical-object"
            dimension = .threeDimensional
            objectDescription = localized("A \(solid) intersected by a specified plane", request: request)
            viewpoint = localized("Section plane shown orthographically", request: request)
            points = []
            axisLabels = []
            let plane = solidIndex == 2 ? localized("through its center", request: request) : localized("parallel to a flat end face", request: request)
            prompt = localized("A plane cuts a \(solid) \(plane). What is the cross-section shape?", request: request)
            correctText = section
            distractors = section == localized("square", request: request)
                ? [
                    (localized("triangle", request: request), "cross_section_topology"),
                    (localized("circle", request: request), "surface_confusion"),
                    (localized("hexagon", request: request), "cross_section_complexity")
                ]
                : [
                    (localized("ellipse only", request: request), "section_orientation"),
                    (localized("rectangle", request: request), "surface_confusion"),
                    (localized("triangle", request: request), "cross_section_topology")
                ]
            accessibilityDescription = localized("Imagine the intersection boundary made where the stated plane passes through the \(solid).", request: request)
            tags = ["cross-section", "mechanical-object", "3d-geometry"]
            rotationMagnitudeDegrees = 0
            objectComplexity = [0.48, 0.54, 0.42][solidIndex]
            distractorSimilarity = 0.62

        case 3:
            let length = 6 + random.int(upperBound: 4)
            let width = 3 + random.int(upperBound: 3)
            let height = 1 + random.int(upperBound: 2)
            templateSlug = "orthographic.top-view"
            operation = .project
            stimulusCategory = "abstract-block"
            dimension = .threeDimensional
            objectDescription = localized("A rectangular block with length \(length), width \(width), and height \(height)", request: request)
            viewpoint = localized("Top orthographic projection", request: request)
            points = []
            axisLabels = [localized("length", request: request), localized("width", request: request), localized("height", request: request)]
            prompt = localized("A rectangular block measures \(length) by \(width) by \(height). Which dimensions appear in its top orthographic view?", request: request)
            correctText = localized("\(length) by \(width)", request: request)
            distractors = [
                (localized("\(length) by \(height)", request: request), "projection_front"),
                (localized("\(width) by \(height)", request: request), "projection_side"),
                (localized("\(length) by \(width) by \(height)", request: request), "projection_dimension")
            ]
            accessibilityDescription = localized("Looking straight down removes height; the visible rectangle retains length and width.", request: request)
            tags = ["orthographic-projection", "abstract-block", "view-matching"]
            rotationMagnitudeDegrees = 0
            objectComplexity = 0.46
            distractorSimilarity = 0.72

        case 4:
            let net = NFCubeNetEngine.deterministicLayout(seed: random.next())
            let queriedFace = "A"
            let oppositeFace = NFCubeNetEngine.oppositeFace(to: queriedFace, in: net) ?? "F"
            let adjacentDistractors = net.cells
                .map(\.label)
                .filter { $0 != queriedFace && $0 != oppositeFace }
                .sorted()
                .prefix(3)
            templateSlug = "folding.cube-net"
            operation = .diagramEquationMatch
            stimulusCategory = "diagram"
            dimension = .threeDimensional
            objectDescription = net.encodedDescription
            viewpoint = localized("Unfolded planar net", request: request)
            points = []
            axisLabels = []
            prompt = localized("In the procedurally checked cube net, which face becomes opposite face \(queriedFace) after folding?", request: request)
            correctText = oppositeFace
            distractors = adjacentDistractors.map { ($0, "adjacent_face") }
            accessibilityDescription = NFCubeNetEngine.accessibilityDescription(for: net)
                + localized(" Determine the face whose folded normal points opposite \(queriedFace).", request: request)
            tags = ["folding-net", "cube-net", "diagram", "algorithmically-validated-net"]
            rotationMagnitudeDegrees = 90
            objectComplexity = 0.82
            distractorSimilarity = 0.78

        default:
            let x = 2 + random.int(upperBound: 5)
            let y = 1 + random.int(upperBound: 5)
            templateSlug = "vector.reflect-y-axis"
            operation = .coordinateTransform
            stimulusCategory = "vector-field-diagram"
            dimension = .twoDimensional
            objectDescription = localized("A vector represented by its x and y components", request: request)
            viewpoint = localized("Cartesian component view", request: request)
            points = [NFSpatialPoint(label: localized("v", request: request), x: Double(x), y: Double(y), z: nil)]
            axisLabels = [localized("x", request: request), localized("y", request: request)]
            prompt = localized("Vector v = (\(x), \(y)) is reflected across the y-axis. Which component form matches the reflected diagram?", request: request)
            correctText = localized("(\(-x), \(y))", request: request)
            distractors = [
                (localized("(\(x), \(-y))", request: request), "wrong_axis"),
                (localized("(\(y), \(x))", request: request), "axis_swap"),
                (localized("(\(-x), \(-y))", request: request), "rotation_instead")
            ]
            accessibilityDescription = localized("Reflection across the y-axis reverses the x component and preserves the y component.", request: request)
            tags = ["vector-transformation", "representation-translation", "vector-field-diagram"]
            rotationMagnitudeDegrees = 0
            objectComplexity = 0.32
            distractorSimilarity = 0.66
        }

        var options = [
            NFChoiceOption(
                id: "correct",
                text: correctText,
                accessibilityLabel: correctText,
                distractorCode: nil
            )
        ]
        options += distractors.enumerated().map { index, distractor in
            NFChoiceOption(
                id: "distractor.\(index)",
                text: distractor.text,
                accessibilityLabel: distractor.text,
                distractorCode: distractor.code
            )
        }
        random.shuffle(&options)
        let spatial = NFSpatialRepresentationMetadata(
            stimulusCategory: stimulusCategory,
            dimension: dimension,
            objectDescription: objectDescription,
            viewpoint: viewpoint,
            operations: [operation],
            points: points,
            axisLabels: axisLabels,
            accessibilityDescription: accessibilityDescription,
            assetName: nil,
            protectedGrammarID: request.purpose.isProtectedAssessment ? "spatial.protected.\(templateSlug).v2" : nil,
            difficultyParameters: NFSpatialDifficultyParameters(
                stimulusCategory: stimulusCategory,
                viewpoint: viewpoint,
                rotationMagnitudeDegrees: rotationMagnitudeDegrees,
                objectComplexity: objectComplexity,
                distractorSimilarity: distractorSimilarity,
                responseMode: request.preferredAssessmentFormat == .diagramMatch ? .diagramMatch : .singleChoice
            )
        )
        return Draft(
            templateSlug: templateSlug,
            title: localized("Spatial transformation", request: request),
            prompt: prompt,
            contextText: contextualLead(request),
            instructions: localized("Choose the result implied by the same deterministic geometry.", request: request),
            interaction: .singleChoice(NFSingleChoiceResponseSchema(options: options, correctOptionID: "correct")),
            difficulty: difficulty(base: 0.4 + Double(variant) * 0.035, steps: 2 + variant / 2, shift: 0.5 + Double(variant % 2) * 0.15),
            skillWeights: ["skill.spatial": 0.8, "skill.quantitative": 0.2],
            strategies: [
                NFExerciseStrategy(
                    id: "strategy.spatial.invariants",
                    title: localized("Track spatial invariants", request: request),
                    summary: localized("Name what the operation changes and what it must preserve before choosing a view or orientation.", request: request),
                    orderedSteps: [localized("Identify the operation", request: request), localized("Mark preserved features", request: request), localized("Transform the changing features", request: request), localized("Check the result", request: request)],
                    whenToUse: localized("Rotation, projection, cross-section, folding, and coordinate tasks", request: request)
                )
            ],
            representations: [.spatial(spatial)],
            citations: [],
            rubric: exactRubric(localized("Correct transformed coordinate", request: request)),
            correctExplanation: localized("The selected result preserves the relevant geometry while applying the stated transformation or viewpoint.", request: request),
            retryExplanation: localized("Separate features that remain fixed from features changed by the operation.", request: request),
            decisiveStep: accessibilityDescription,
            hints: [localized("Name the viewpoint or axis first.", request: request), localized("Check which dimensions, faces, or components remain invariant.", request: request)],
            errorExplanations: Dictionary(
                distractors.map {
                    ($0.code, localized("This option applies a common but incompatible spatial transformation.", request: request))
                },
                uniquingKeysWith: { first, _ in first }
            ),
            accessibility: NFExerciseAccessibility(
                promptAccessibilityLabel: prompt,
                visualAlternative: spatial.accessibilityDescription,
                requiresVisualSpatialProcessing: true,
                supportsVoiceOver: true,
                supportsKeyboardOnly: true,
                usesMotion: false
            ),
            expectedDurationSeconds: 65,
            tags: tags + [operation.rawValue]
        )
    }

    private static func quantitativeDraft(
        request: NFExerciseGenerationRequest,
        random: inout NFFallbackRandom
    ) -> Draft {
        let profile = fieldProfile(request.sourceContext.primaryField, request: request)
        let variant = selectedVariant(
            request: request,
            defaultUpperBound: variantCount(for: .quantitative),
            compatibleVariants: [
                .numericEntry: [0, 1, 2, 3, 4, 5],
                .singleChoice: [4, 5, 6, 7]
            ],
            random: &random
        )
        let templateSlug: String
        let prompt: String
        let context: String
        let instructions: String
        let interaction: NFExerciseInteraction
        let representations: [NFExerciseRepresentation]
        let strategy: NFExerciseStrategy
        let correctExplanation: String
        let decisiveStep: String
        let tags: [String]
        let errorExplanations: [String: String]

        switch variant {
        case 0:
            let successes = 18 + random.int(upperBound: 33)
            let total = successes + 20 + random.int(upperBound: 31)
            let expected = 100 * Double(successes) / Double(total)
            let exactExpected = try! NFExactNumber(
                numerator: Int64(100 * successes),
                denominator: Int64(total)
            )
            templateSlug = "observed.proportion"
            prompt = localized("In a \(profile.entity) study, \(successes) of \(total) observations meet the criterion. Estimate the observed proportion as a percentage.", request: request)
            context = contextualLead(request) + localized(" Report one decimal place; small rounding differences are accepted.", request: request)
            instructions = localized("Enter the percentage and the % unit.", request: request)
            interaction = numericInteraction(
                answer: expected,
                tolerance: .absolute(0.15),
                unit: "%",
                acceptedUnits: ["percent"],
                precision: 1,
                authoritativeValue: exactExpected
            )
            representations = [
                .table(
                    headers: [localized("Outcome", request: request), localized("Count", request: request)],
                    rows: [[localized("Meets criterion", request: request), localized("\(successes)", request: request)], [localized("Does not meet", request: request), localized("\(total - successes)", request: request)]],
                    accessibilitySummary: localized("\(successes) observations meet the criterion and \(total - successes) do not.", request: request)
                ),
                .equation(latex: "100 \\times \\frac{k}{n}", spokenDescription: localized("One hundred times the count divided by the total", request: request))
            ]
            strategy = NFExerciseStrategy(
                id: "strategy.proportion.reference",
                title: localized("Anchor the proportion", request: request),
                summary: localized("Divide the part by the whole, then compare with familiar fractions before converting to percent.", request: request),
                orderedSteps: [localized("Identify part and whole", request: request), localized("Compute part divided by whole", request: request), localized("Multiply by 100 and check the range", request: request)],
                whenToUse: localized("Observed rates and proportions", request: request)
            )
            correctExplanation = localized("The observed percentage is the qualifying count divided by the total, multiplied by 100.", request: request)
            decisiveStep = localized("Use the complete sample as the denominator.", request: request)
            tags = ["proportional-reasoning", "observed-proportion"]
            errorExplanations = [
                "numeric_value": localized("The result does not match part divided by whole times 100.", request: request),
                "unit_missing": localized("Report the result as a percentage.", request: request),
                "unit_mismatch": localized("Use a percentage unit for this response.", request: request)
            ]

        case 1:
            let floors = [8, 12, 20][random.int(upperBound: 3)]
            let rooms = [20, 25, 30][random.int(upperBound: 3)]
            let lamps = [3, 4, 5][random.int(upperBound: 3)]
            let hours = [8, 10, 12][random.int(upperBound: 3)]
            let reference = Double(floors * rooms * lamps * hours)
            templateSlug = "fermi.decomposition"
            prompt = localized("Fermi estimate: a building has about \(floors) floors, \(rooms) rooms per floor, \(lamps) active lamps per room, and \(hours) operating hours. Estimate daily lamp-hours.", request: request)
            context = contextualLead(request) + localized(" A reasonable range is accepted; focus on the assumptions and order of magnitude.", request: request)
            instructions = localized("Enter a magnitude estimate in lamp-hours.", request: request)
            interaction = numericInteraction(
                answer: reference,
                tolerance: .relative(0.5),
                unit: localized("lamp-hours", request: request),
                acceptedUnits: [localized("lamp hours", request: request)],
                precision: 0
            )
            representations = [.equation(latex: "F \\times R \\times L \\times H", spokenDescription: localized("Floors times rooms per floor times lamps per room times hours", request: request))]
            strategy = NFExerciseStrategy(
                id: "strategy.fermi.decompose",
                title: localized("Decompose into countable factors", request: request),
                summary: localized("Express the unknown total as a product of explicit, auditable assumptions.", request: request),
                orderedSteps: [localized("Name the target unit", request: request), localized("Choose factor estimates", request: request), localized("Multiply magnitudes", request: request), localized("Inspect the accepted range", request: request)],
                whenToUse: localized("Order-of-magnitude and Fermi estimation", request: request)
            )
            correctExplanation = localized("Multiplying the four stated factors gives a reference estimate; nearby values are accepted within the stated range.", request: request)
            decisiveStep = localized("Preserve the units while multiplying all four factors.", request: request)
            tags = ["fermi-estimation", "order-of-magnitude", "assumption-decomposition"]
            errorExplanations = [
                "numeric_value": localized("The estimate is outside the accepted range; check for a missing or repeated factor.", request: request),
                "unit_missing": localized("State the estimate in lamp-hours.", request: request),
                "unit_mismatch": localized("The requested quantity is accumulated lamp-hours.", request: request)
            ]

        case 2:
            let millimeters = [1_250, 2_500, 3_750, 5_000][random.int(upperBound: 4)]
            let meters = Double(millimeters) / 1_000
            templateSlug = "units.metric-conversion"
            if request.purpose.isProtectedAssessment || request.preferredAssessmentFormat == .numericEntry {
                prompt = localized("Convert \(millimeters) millimeters to meters.", request: request)
                context = contextualLead(request) + localized(" The physical dimension remains length; only the scale changes.", request: request)
                instructions = localized("Enter the value and unit in meters.", request: request)
                interaction = numericInteraction(
                    answer: meters,
                    tolerance: .absolute(0.000_001),
                    unit: "m",
                    acceptedUnits: ["meter", "meters"],
                    precision: 3,
                    authoritativeValue: try! NFExactNumber(
                        numerator: Int64(millimeters),
                        denominator: 1_000
                    )
                )
            } else {
                let roundedEstimate = Int(meters.rounded())
                let contract = NFEstimateExactContract(
                    estimate: localized("about \(roundedEstimate) m", request: request),
                    acceptedEstimateAlternatives: [localized("\(roundedEstimate) m", request: request)],
                    plausibility: localized("smaller numeric value", request: request),
                    acceptedPlausibilityAlternatives: [localized("smaller", request: request)],
                    exact: "\(String(meters)) m",
                    acceptedExactAlternatives: [
                        "\((try! NFExactNumber(numerator: Int64(millimeters), denominator: 1_000)).canonicalString) m"
                    ]
                )
                prompt = localized("Estimate \(millimeters) millimeters in meters, state whether the converted numeric value should be smaller or larger, then calculate the exact conversion.", request: request)
                context = contextualLead(request) + localized(" Plausibility and exact unit conversion are stored as separate response fields.", request: request)
                instructions = localized("Enter the estimate first, the scale-direction plausibility judgment second, and the exact value with unit third.", request: request)
                interaction = .logicState(contract.responseSchema)
            }
            representations = [.equation(latex: "\(millimeters)\\,\\mathrm{mm} \\times \\frac{1\\,\\mathrm{m}}{1000\\,\\mathrm{mm}}", spokenDescription: localized("\(millimeters) millimeters times one meter per one thousand millimeters", request: request))]
            strategy = NFExerciseStrategy(
                id: "strategy.units.cancel",
                title: localized("Convert by unit cancellation", request: request),
                summary: localized("Multiply by a conversion ratio equal to one and cancel the original unit.", request: request),
                orderedSteps: [localized("Write the starting unit", request: request), localized("Choose a dimension-safe ratio", request: request), localized("Cancel units", request: request), localized("Check scale", request: request)],
                whenToUse: localized("Dimensional analysis and unit conversion", request: request)
            )
            correctExplanation = localized("One meter is one thousand millimeters, so the numeric value is divided by one thousand.", request: request)
            decisiveStep = localized("Arrange the conversion factor so millimeters cancel and meters remain.", request: request)
            tags = ["dimensional-analysis", "unit-conversion", "si-prefixes"]
            errorExplanations = [
                "numeric_value": localized("The conversion factor was applied in the wrong direction or at the wrong scale.", request: request),
                "unit_missing": localized("A converted quantity requires the destination unit.", request: request),
                "unit_mismatch": localized("Report the requested length in meters.", request: request),
                "logic_state": localized("Keep the magnitude estimate, scale-direction check, and exact unit conversion separate.", request: request)
            ]

        case 3:
            let baseline = 4 + random.int(upperBound: 7)
            let factor = 2 + random.int(upperBound: 2)
            let law = random.int(upperBound: 3)
            let relationship: String
            let answer: Double
            let authoritativeAnswer: NFExactNumber
            switch law {
            case 0:
                relationship = localized("directly proportional", request: request)
                answer = Double(baseline * factor)
                authoritativeAnswer = try! NFExactNumber(numerator: Int64(baseline * factor))
            case 1:
                relationship = localized("inversely proportional", request: request)
                answer = Double(baseline) / Double(factor)
                authoritativeAnswer = try! NFExactNumber(
                    numerator: Int64(baseline),
                    denominator: Int64(factor)
                )
            default:
                relationship = localized("proportional to the square of the input", request: request)
                answer = Double(baseline * factor * factor)
                authoritativeAnswer = try! NFExactNumber(numerator: Int64(baseline * factor * factor))
            }
            templateSlug = ["scaling.direct", "scaling.inverse", "scaling.power-law"][law]
            prompt = localized("An output is \(baseline) units at the current input and is \(relationship). If the input is multiplied by \(factor), what is the new output?", request: request)
            context = contextualLead(request) + localized(" Apply the stated functional relationship, not a surface-word heuristic.", request: request)
            instructions = localized("Enter the resulting value in units.", request: request)
            interaction = numericInteraction(
                answer: answer,
                tolerance: .absolute(0.000_001),
                unit: localized("units", request: request),
                authoritativeValue: authoritativeAnswer
            )
            representations = [.equation(latex: law == 0 ? "y \\propto x" : law == 1 ? "y \\propto x^{-1}" : "y \\propto x^2", spokenDescription: relationship)]
            strategy = NFExerciseStrategy(
                id: "strategy.scaling.factor",
                title: localized("Transform the scale factor", request: request),
                summary: localized("Apply the input multiplier through the direct, inverse, or power-law relationship before changing the output.", request: request),
                orderedSteps: [localized("Name the relationship", request: request), localized("Transform the input factor", request: request), localized("Apply it to the output", request: request), localized("Check direction", request: request)],
                whenToUse: localized("Direct, inverse, and power-law scaling", request: request)
            )
            correctExplanation = localized("The output multiplier follows directly from the stated scaling law.", request: request)
            decisiveStep = localized("Transform the factor \(factor) according to the relationship before applying it.", request: request)
            tags = ["scaling-law", ["direct", "inverse", "power-law"][law]]
            errorExplanations = [
                "numeric_value": localized("The input factor was not transformed according to the stated scaling law.", request: request),
                "unit_missing": localized("Keep the output unit attached.", request: request),
                "unit_mismatch": localized("Use the generic output unit stated in the problem.", request: request)
            ]

        case 4:
            let prevalence = [10, 20][random.int(upperBound: 2)]
            let sensitivity = [80, 90][random.int(upperBound: 2)]
            let falsePositiveRate = [5, 10][random.int(upperBound: 2)]
            let truePositive = prevalence * sensitivity / 100
            let nonCases = 100 - prevalence
            let falsePositive = nonCases * falsePositiveRate / 100
            let posterior = 100 * Double(truePositive) / Double(truePositive + falsePositive)
            let exactPosterior = try! NFExactNumber(
                numerator: Int64(100 * truePositive),
                denominator: Int64(truePositive + falsePositive)
            )
            templateSlug = "probability.bayes-natural-frequency"
            prompt = localized("Out of 100 cases, \(prevalence) truly have a condition. A check detects \(sensitivity)% of true cases and flags \(falsePositiveRate)% of non-cases. Among all positive flags, what percentage are true cases?", request: request)
            context = contextualLead(request) + localized(" Use natural frequencies to keep the base rate visible.", request: request)
            if request.preferredAssessmentFormat == .singleChoice {
                let roundedPosterior = (posterior * 10).rounded() / 10
                var values = [roundedPosterior]
                for offset in [10.0, -10.0, 20.0, -20.0] where values.count < 4 {
                    let candidate = min(99.9, max(0.1, roundedPosterior + offset))
                    if !values.contains(candidate) { values.append(candidate) }
                }
                var options = values.enumerated().map { index, value in
                    NFChoiceOption(
                        id: index == 0 ? "correct" : "posterior.\(index)",
                        text: "\(format(value))%",
                        accessibilityLabel: nil,
                        distractorCode: index == 0 ? nil : "numeric_value"
                    )
                }
                random.shuffle(&options)
                interaction = .singleChoice(
                    NFSingleChoiceResponseSchema(options: options, correctOptionID: "correct")
                )
                instructions = localized("Choose the defensible interpretation.", request: request)
            } else {
                instructions = localized("Enter the conditional percentage and % unit.", request: request)
                interaction = numericInteraction(
                    answer: posterior,
                    tolerance: .absolute(0.15),
                    unit: "%",
                    acceptedUnits: ["percent"],
                    precision: 1,
                    authoritativeValue: exactPosterior
                )
            }
            representations = [.table(
                headers: [localized("Group", request: request), localized("Positive flags", request: request)],
                rows: [[localized("True cases", request: request), localized("\(truePositive)", request: request)], [localized("Non-cases", request: request), localized("\(falsePositive)", request: request)]],
                accessibilitySummary: localized("There are \(truePositive) true-positive flags and \(falsePositive) false-positive flags.", request: request)
            )]
            strategy = NFExerciseStrategy(
                id: "strategy.bayes.frequencies",
                title: localized("Count the positive pool", request: request),
                summary: localized("Convert rates to counts, then divide true positives by every positive result.", request: request),
                orderedSteps: [localized("Apply the base rate", request: request), localized("Count true positives", request: request), localized("Count false positives", request: request), localized("Divide by all positives", request: request)],
                whenToUse: localized("Base-rate and conditional-probability questions", request: request)
            )
            correctExplanation = localized("The relevant denominator is every positive flag, including false positives.", request: request)
            decisiveStep = localized("Compute true positives divided by true positives plus false positives.", request: request)
            tags = ["conditional-probability", "bayesian-updating", "base-rate", "natural-frequencies"]
            errorExplanations = [
                "numeric_value": localized("The denominator should contain all positive flags, not the full population or only true cases.", request: request),
                "unit_missing": localized("Report the posterior as a percentage.", request: request),
                "unit_mismatch": localized("This conditional result is requested as a percentage.", request: request)
            ]

        case 5:
            let win = [10, 15, 20][random.int(upperBound: 3)]
            let loss = [2, 4, 5][random.int(upperBound: 3)]
            let winPercent = [25, 40, 60][random.int(upperBound: 3)]
            let probability = Double(winPercent) / 100
            let expected = probability * Double(win) - (1 - probability) * Double(loss)
            let exactExpected = try! NFExactNumber(
                numerator: Int64(winPercent * win - (100 - winPercent) * loss),
                denominator: 100
            )
            templateSlug = "probability.expected-value"
            prompt = localized("An option gains \(win) points with probability \(winPercent)% and loses \(loss) points otherwise. What is its expected value per trial?", request: request)
            context = contextualLead(request) + localized(" Expected value is a long-run weighted average, not the most likely single outcome.", request: request)
            if request.preferredAssessmentFormat == .singleChoice {
                var values = [expected]
                for offset in [Double(loss), -Double(loss), Double(win), -Double(win)] where values.count < 4 {
                    let candidate = expected + offset
                    if !values.contains(candidate) { values.append(candidate) }
                }
                var options = values.enumerated().map { index, value in
                    NFChoiceOption(
                        id: index == 0 ? "correct" : "expected.\(index)",
                        text: format(value),
                        accessibilityLabel: nil,
                        distractorCode: index == 0 ? nil : "numeric_value"
                    )
                }
                random.shuffle(&options)
                interaction = .singleChoice(
                    NFSingleChoiceResponseSchema(options: options, correctOptionID: "correct")
                )
                instructions = localized("Choose the defensible interpretation.", request: request)
            } else {
                instructions = localized("Enter the signed expected value in points.", request: request)
                interaction = numericInteraction(
                    answer: expected,
                    tolerance: .absolute(0.000_001),
                    unit: localized("points", request: request),
                    authoritativeValue: exactExpected
                )
            }
            representations = [.equation(latex: "p(\(win)) + (1-p)(-\(loss))", spokenDescription: localized("Probability-weighted gain plus probability-weighted loss", request: request))]
            strategy = NFExerciseStrategy(
                id: "strategy.expected-value.weight",
                title: localized("Weight every outcome", request: request),
                summary: localized("Multiply each signed outcome by its probability and add the contributions.", request: request),
                orderedSteps: [localized("List signed outcomes", request: request), localized("Attach probabilities", request: request), localized("Multiply", request: request), localized("Sum", request: request)],
                whenToUse: localized("Expected-value comparisons", request: request)
            )
            correctExplanation = localized("The expected value combines both possible signed outcomes using probabilities that sum to one.", request: request)
            decisiveStep = localized("Treat the loss as negative before taking the weighted sum.", request: request)
            tags = ["expected-value", "probability", "uncertainty"]
            errorExplanations = [
                "numeric_value": localized("Recheck the loss sign and the complementary probability.", request: request),
                "unit_missing": localized("Expected value retains the outcome unit.", request: request),
                "unit_mismatch": localized("Report the expected outcome in points.", request: request)
            ]

        case 6:
            let first = 92 + random.int(upperBound: 7)
            let second = 72 + random.int(upperBound: 7)
            var options = [
                NFChoiceOption(id: "correct", text: localized("The first result may include random positive noise; repeat measurements before inferring a stable decline.", request: request), accessibilityLabel: nil, distractorCode: nil),
                NFChoiceOption(id: "cause", text: localized("The lower second result proves the intervention caused harm.", request: request), accessibilityLabel: nil, distractorCode: "causal_overreach"),
                NFChoiceOption(id: "permanent", text: localized("The first extreme result is the subject’s exact permanent level.", request: request), accessibilityLabel: nil, distractorCode: "sampling_variability"),
                NFChoiceOption(id: "discard", text: localized("Discard the second result because it is closer to the group mean.", request: request), accessibilityLabel: nil, distractorCode: "selection_bias")
            ]
            random.shuffle(&options)
            templateSlug = "sampling.regression-to-mean"
            prompt = localized("A subject selected after an unusually high score of \(first) later scores \(second), closer to the population mean. Which interpretation is most defensible?", request: request)
            context = contextualLead(request) + localized(" Separate within-subject noise from a causal change.", request: request)
            instructions = localized("Choose the interpretation supported by the two measurements.", request: request)
            interaction = .singleChoice(NFSingleChoiceResponseSchema(options: options, correctOptionID: "correct"))
            representations = [.table(
                headers: [localized("Measurement", request: request), localized("Score", request: request)],
                rows: [[localized("Selected extreme", request: request), localized("\(first)", request: request)], [localized("Follow-up", request: request), localized("\(second)", request: request)]],
                accessibilitySummary: localized("The selected first score is unusually high; the follow-up is closer to the population mean.", request: request)
            )]
            strategy = NFExerciseStrategy(
                id: "strategy.variability.repeat",
                title: localized("Separate signal from selection noise", request: request),
                summary: localized("Extreme observations tend to be followed by less extreme observations when measurement contains noise.", request: request),
                orderedSteps: [localized("Notice selection on an extreme", request: request), localized("Consider measurement noise", request: request), localized("Seek repeated evidence", request: request), localized("Avoid causal overreach", request: request)],
                whenToUse: localized("Sampling variability and regression-to-the-mean scenarios", request: request)
            )
            correctExplanation = localized("Selection on an extreme plus noise can produce a less extreme follow-up without any causal change.", request: request)
            decisiveStep = localized("Ask how the subject entered the sample and whether repeated measures establish a stable change.", request: request)
            tags = ["sampling-variability", "regression-to-mean", "signal-noise"]
            errorExplanations = [
                "causal_overreach": localized("Two observations after extreme selection do not establish a causal effect.", request: request),
                "sampling_variability": localized("A single extreme observation can contain transient noise.", request: request),
                "selection_bias": localized("Keeping only the extreme result would preserve the selection distortion.", request: request)
            ]

        default:
            var options = [
                NFChoiceOption(id: "correct", text: localized("The interval describes uncertainty in the estimated quantity under the stated procedure; it is not a guarantee about each observation.", request: request), accessibilityLabel: nil, distractorCode: nil),
                NFChoiceOption(id: "all", text: localized("Exactly 95% of individual observations must fall inside this interval.", request: request), accessibilityLabel: nil, distractorCode: "interval_scope"),
                NFChoiceOption(id: "truth", text: localized("There is no uncertainty because the interval endpoints are numerical.", request: request), accessibilityLabel: nil, distractorCode: "uncertainty_ignored"),
                NFChoiceOption(id: "cause", text: localized("The interval proves the measured relationship is causal.", request: request), accessibilityLabel: nil, distractorCode: "causal_overreach")
            ]
            random.shuffle(&options)
            templateSlug = "uncertainty.interval-interpretation"
            prompt = localized("A report gives an estimate with a 95% uncertainty interval. Which statement preserves the interval’s scope?", request: request)
            context = contextualLead(request) + localized(" Interpret uncertainty without turning it into certainty or causation.", request: request)
            instructions = localized("Choose the defensible interpretation.", request: request)
            interaction = .singleChoice(NFSingleChoiceResponseSchema(options: options, correctOptionID: "correct"))
            representations = [.prose]
            strategy = NFExerciseStrategy(
                id: "strategy.interval.scope",
                title: localized("Name what is uncertain", request: request),
                summary: localized("Identify the estimated quantity and the repeated-sampling or modeled procedure before interpreting an interval.", request: request),
                orderedSteps: [localized("Name the target quantity", request: request), localized("Name the procedure", request: request), localized("Preserve uncertainty", request: request), localized("Avoid unsupported causal claims", request: request)],
                whenToUse: localized("Confidence or credible interval interpretation", request: request)
            )
            correctExplanation = localized("An uncertainty interval qualifies an estimate under a procedure; it does not by itself describe every observation or prove causality.", request: request)
            decisiveStep = localized("Keep the interval attached to the estimated quantity and its assumptions.", request: request)
            tags = ["uncertainty-interval", "claim-scope", "signal-noise"]
            errorExplanations = [
                "interval_scope": localized("An interval for an estimate is not automatically a coverage claim for individual observations.", request: request),
                "uncertainty_ignored": localized("Numerical endpoints do not eliminate estimation uncertainty.", request: request),
                "causal_overreach": localized("An interval does not establish causal identification.", request: request)
            ]
        }

        return Draft(
            templateSlug: templateSlug,
            title: localized("Quantitative intuition", request: request),
            prompt: prompt,
            contextText: context,
            instructions: instructions,
            interaction: interaction,
            difficulty: difficulty(base: 0.43 + Double(variant % 4) * 0.045, steps: 2 + variant / 2, shift: 0.3 + Double(variant % 3) * 0.15),
            skillWeights: ["skill.quantitative": 0.8, "skill.mentalMath": 0.2],
            strategies: [strategy],
            representations: representations,
            citations: [],
            rubric: exactRubric(localized("Correct quantitative result or inference", request: request)),
            correctExplanation: correctExplanation,
            retryExplanation: localized("Rebuild the relationship from quantities, units, probability conditions, or uncertainty scope before calculating.", request: request),
            decisiveStep: decisiveStep,
            hints: [localized("Name the target quantity and denominator.", request: request), decisiveStep],
            errorExplanations: errorExplanations,
            accessibility: standardAccessibility(label: prompt),
            expectedDurationSeconds: 75 + variant * 5,
            tags: tags + ["quantitative-intuition"]
        )
    }

    private static func scientificReasoningDraft(
        request: NFExerciseGenerationRequest,
        random: inout NFFallbackRandom
    ) -> Draft {
        let profile = fieldProfile(request.sourceContext.primaryField, request: request)
        let variant = selectedVariant(
            request: request,
            defaultUpperBound: variantCount(for: .scientificReasoning),
            compatibleVariants: [
                .claimEvidence: [0],
                .singleChoice: [1, 2, 3, 5],
                .orderedSteps: [7]
            ],
            random: &random
        )
        let templateSlug: String
        let prompt: String
        let context: String
        let instructions: String
        let interaction: NFExerciseInteraction
        let representations: [NFExerciseRepresentation]
        let strategy: NFExerciseStrategy
        let correctExplanation: String
        let decisiveStep: String
        let tags: [String]
        let errorExplanations: [String: String]

        switch variant {
        case 0:
            let treatment = 40 + random.int(upperBound: 100)
            let control = treatment - (2 + random.int(upperBound: 30))
            let claims = [
                NFClaimOption(id: "claim.difference", text: localized("The treatment group had a higher observed mean than the control group.", request: request)),
                NFClaimOption(id: "claim.limits", text: localized("The observations do not establish a universal causal effect.", request: request))
            ]
            let evidence = [
                NFEvidenceOption(id: "evidence.means", text: localized("Treatment mean: \(treatment); control mean: \(control).", request: request), citationID: nil),
                NFEvidenceOption(id: "evidence.assignment", text: localized("Participants were assigned by convenience rather than randomly.", request: request), citationID: nil),
                NFEvidenceOption(id: "evidence.universal", text: localized("No observation establishes a universal effect beyond the sampled setting.", request: request), citationID: nil)
            ]
            templateSlug = "claim.evidence.bounds"
            prompt = localized("A \(profile.entity) experiment observed a treatment mean of \(treatment) and a control mean of \(control). Match each defensible claim to the observation that supports it.", request: request)
            context = contextualLead(request) + localized(" Distinguish an observed contrast from a causal or universal conclusion.", request: request)
            instructions = localized("Attach all and only the evidence relevant to each claim.", request: request)
            interaction = .claimEvidence(
                NFClaimEvidenceResponseSchema(
                    claims: claims,
                    evidence: evidence,
                    correctPairs: [
                        NFClaimEvidencePair(claimID: "claim.difference", evidenceIDs: ["evidence.means"]),
                        NFClaimEvidencePair(claimID: "claim.limits", evidenceIDs: ["evidence.assignment", "evidence.universal"])
                    ]
                )
            )
            representations = [.table(
                headers: [localized("Group", request: request), localized("Observed mean", request: request)],
                rows: [[localized("Treatment", request: request), localized("\(treatment)", request: request)], [localized("Control", request: request), localized("\(control)", request: request)]],
                accessibilitySummary: localized("The treatment mean is \(treatment), higher than the control mean of \(control).", request: request)
            )]
            strategy = claimScopeStrategy(request: request)
            correctExplanation = localized("The means support a sample-level contrast; assignment and sampling limits constrain causal and universal conclusions.", request: request)
            decisiveStep = localized("A numerical contrast supports a description; causal scope also depends on design and assignment.", request: request)
            tags = ["figure-to-claim", "claim-evidence", "causal-scope"]
            errorExplanations = ["claim_evidence_support": localized("At least one claim is paired with evidence of the wrong scope.", request: request)]

        case 1:
            var options = [
                NFChoiceOption(id: "correct", text: localized("Baseline ability", request: request), accessibilityLabel: nil, distractorCode: nil),
                NFChoiceOption(id: "treatment", text: localized("The treatment label itself", request: request), accessibilityLabel: nil, distractorCode: "variable_role"),
                NFChoiceOption(id: "outcome", text: localized("The measured outcome", request: request), accessibilityLabel: nil, distractorCode: "variable_role"),
                NFChoiceOption(id: "size", text: localized("The numeric sample-size label", request: request), accessibilityLabel: nil, distractorCode: "confound")
            ]
            random.shuffle(&options)
            templateSlug = "design.identify-confound"
            prompt = localized("Participants with higher baseline ability were more likely to choose the treatment, and baseline ability also predicts the outcome. Which variable is the confound?", request: request)
            context = contextualLead(request) + localized(" The structured scenario has edges baseline ability → treatment and baseline ability → outcome.", request: request)
            instructions = localized("Choose the common cause that opens the backdoor path.", request: request)
            interaction = .singleChoice(NFSingleChoiceResponseSchema(options: options, correctOptionID: "correct"))
            representations = [.table(
                headers: [localized("Variable", request: request), localized("Observed role", request: request)],
                rows: [[localized("Baseline ability", request: request), localized("Predicts treatment and outcome", request: request)], [localized("Treatment", request: request), localized("Exposure", request: request)], [localized("Outcome", request: request), localized("Measured response", request: request)]],
                accessibilitySummary: localized("Baseline ability predicts both treatment choice and the measured outcome.", request: request)
            )]
            strategy = NFExerciseStrategy(
                id: "strategy.design.backdoor",
                title: localized("Look for a common cause", request: request),
                summary: localized("A confound predicts both exposure assignment and the outcome through paths outside the intended effect.", request: request),
                orderedSteps: [localized("Name exposure and outcome", request: request), localized("List common causes", request: request), localized("Check assignment", request: request), localized("Identify the open backdoor path", request: request)],
                whenToUse: localized("Confound identification", request: request)
            )
            correctExplanation = localized("Baseline ability influences both treatment selection and outcome, so the observed contrast mixes treatment with baseline differences.", request: request)
            decisiveStep = localized("Find the variable with arrows into both treatment and outcome.", request: request)
            tags = ["experimental-design", "confound", "causal-graph"]
            errorExplanations = [
                "variable_role": localized("Exposure and outcome labels are not themselves the shared upstream cause in this graph.", request: request),
                "confound": localized("A label is not a confound unless it predicts both assignment and outcome.", request: request)
            ]

        case 2:
            var options = [
                NFChoiceOption(id: "correct", text: localized("Randomize the candidate cause while using a calibrated independent outcome measurement.", request: request), accessibilityLabel: nil, distractorCode: nil),
                NFChoiceOption(id: "repeat", text: localized("Repeat the same observational comparison with more convenience-selected cases.", request: request), accessibilityLabel: nil, distractorCode: "confound"),
                NFChoiceOption(id: "both", text: localized("Change both candidate causes together and record the outcome once.", request: request), accessibilityLabel: nil, distractorCode: "hypothesis_discrimination"),
                NFChoiceOption(id: "select", text: localized("Keep only cases whose outcome agrees with the preferred hypothesis.", request: request), accessibilityLabel: nil, distractorCode: "selection_bias")
            ]
            random.shuffle(&options)
            templateSlug = "design.next-discriminating-experiment"
            prompt = localized("An increased output could be caused by intervention A or by measurement drift. Which next experiment best discriminates the hypotheses?", request: request)
            context = contextualLead(request) + localized(" The useful experiment changes A independently and checks the outcome with a separate calibrated measurement.", request: request)
            instructions = localized("Choose the experiment with the clearest contrasting predictions.", request: request)
            interaction = .singleChoice(NFSingleChoiceResponseSchema(options: options, correctOptionID: "correct"))
            representations = [.table(
                headers: [localized("Hypothesis", request: request), localized("Distinct prediction", request: request)],
                rows: [[localized("A causes output", request: request), localized("Randomized A changes independent measure", request: request)], [localized("Measurement drift", request: request), localized("Independent measure does not follow the drift", request: request)]],
                accessibilitySummary: localized("The hypotheses differ when A is randomized and outcome is checked independently.", request: request)
            )]
            strategy = NFExerciseStrategy(
                id: "strategy.experiment.discriminate",
                title: localized("Maximize contrasting predictions", request: request),
                summary: localized("Choose a manipulation and measurement for which the hypotheses predict different observations.", request: request),
                orderedSteps: [localized("List hypotheses", request: request), localized("Write predictions", request: request), localized("Hold alternatives fixed", request: request), localized("Choose the largest prediction contrast", request: request)],
                whenToUse: localized("Choose-the-next-experiment tasks", request: request)
            )
            correctExplanation = localized("Independent manipulation and measurement separate a real effect of A from drift in the original measurement process.", request: request)
            decisiveStep = localized("Choose the test on which the two hypotheses make different predictions.", request: request)
            tags = ["next-experiment", "information-gain", "competing-hypotheses"]
            errorExplanations = [
                "confound": localized("Repeating the same confounded design adds precision without identification.", request: request),
                "hypothesis_discrimination": localized("Changing both causes together cannot separate their predictions.", request: request),
                "selection_bias": localized("Selecting agreement after observing outcomes destroys the comparison.", request: request)
            ]

        case 3:
            let low = 15 + random.int(upperBound: 50)
            let high = low + 3 + random.int(upperBound: 20)
            let offsets = [-4, -2, -1, 0, 0, 1, 2, 4]
            let rawRows = offsets.enumerated().flatMap { index, offset in
                [
                    [localized("A", request: request), "\(index + 1)", "\(low + offset)"],
                    [localized("B", request: request), "\(index + 1)", "\(high + offsets[offsets.count - index - 1])"]
                ]
            }
            var options = [
                NFChoiceOption(id: "correct", text: localized("Group B has the higher observed mean, but overlapping uncertainty prevents a definitive effect claim from this figure alone.", request: request), accessibilityLabel: nil, distractorCode: nil),
                NFChoiceOption(id: "cause", text: localized("The figure proves assignment to B causes every outcome to increase.", request: request), accessibilityLabel: nil, distractorCode: "causal_overreach"),
                NFChoiceOption(id: "none", text: localized("Overlapping intervals prove the groups are exactly identical.", request: request), accessibilityLabel: nil, distractorCode: "uncertainty_overreach"),
                NFChoiceOption(id: "universal", text: localized("Every future B observation will exceed every future A observation.", request: request), accessibilityLabel: nil, distractorCode: "universal_overreach")
            ]
            random.shuffle(&options)
            templateSlug = "data-forensics.uncertainty"
            prompt = localized("A synthetic figure shows group A mean \(low) and group B mean \(high) with overlapping uncertainty intervals. Which claim is strongest?", request: request)
            context = contextualLead(request) + localized(" The seeded figure encodes means and intervals separately.", request: request)
            instructions = localized("Choose the claim supported by the displayed data and no more.", request: request)
            interaction = .singleChoice(NFSingleChoiceResponseSchema(options: options, correctOptionID: "correct"))
            representations = [
                .table(
                    headers: [localized("Group", request: request), localized("Mean", request: request), localized("Interval", request: request)],
                    rows: [[localized("A", request: request), localized("\(low)", request: request), localized("\(low - 3)–\(low + 5)", request: request)], [localized("B", request: request), localized("\(high)", request: request), localized("\(high - 5)–\(high + 3)", request: request)]],
                    accessibilitySummary: localized("B has a higher mean, and the two uncertainty intervals overlap.", request: request)
                ),
                .table(
                    headers: [localized("Group", request: request), localized("Observation", request: request), localized("Value", request: request)],
                    rows: rawRows,
                    accessibilitySummary: localized("Raw values", request: request)
                )
            ]
            strategy = claimScopeStrategy(request: request)
            correctExplanation = localized("The observed mean difference is descriptive; overlapping uncertainty and unknown design details limit stronger conclusions.", request: request)
            decisiveStep = localized("Report the visible contrast while preserving uncertainty and design limits.", request: request)
            tags = ["data-forensics", "synthetic-figure", "seeded-dataset", "uncertainty", "figure-to-claim"]
            errorExplanations = [
                "causal_overreach": localized("A plotted contrast does not establish causal assignment.", request: request),
                "uncertainty_overreach": localized("Overlap is not proof of exact equality.", request: request),
                "universal_overreach": localized("Group summaries do not order every individual or future observation.", request: request)
            ]

        case 4:
            var options = [
                NFChoiceOption(id: "randomize", text: localized("Randomize treatment assignment where ethical and feasible.", request: request), accessibilityLabel: nil, distractorCode: nil),
                NFChoiceOption(id: "blind", text: localized("Blind outcome assessment to group assignment.", request: request), accessibilityLabel: nil, distractorCode: nil),
                NFChoiceOption(id: "replicate", text: localized("Predefine the outcome and replicate with an independent sample.", request: request), accessibilityLabel: nil, distractorCode: nil),
                NFChoiceOption(id: "exclude", text: localized("Exclude inconvenient outcomes after viewing the results.", request: request), accessibilityLabel: nil, distractorCode: "selection_bias")
            ]
            random.shuffle(&options)
            templateSlug = "design.repair-bias"
            prompt = localized("Which changes strengthen a \(profile.entity) comparison against assignment bias, observer bias, and one-sample instability?", request: request)
            context = contextualLead(request) + localized(" Multiple design safeguards may be required.", request: request)
            instructions = localized("Select every defensible design improvement.", request: request)
            interaction = .multipleChoice(
                NFMultipleChoiceResponseSchema(
                    options: options,
                    correctOptionIDs: ["randomize", "blind", "replicate"],
                    minimumSelections: 1,
                    maximumSelections: 4
                )
            )
            representations = [.prose]
            strategy = NFExerciseStrategy(
                id: "strategy.design.threat-map",
                title: localized("Match safeguards to threats", request: request),
                summary: localized("Use assignment, measurement, and replication safeguards for different validity threats.", request: request),
                orderedSteps: [localized("Name the bias threat", request: request), localized("Choose a matching safeguard", request: request), localized("Prespecify analysis", request: request), localized("Plan replication", request: request)],
                whenToUse: localized("Experimental-design repair", request: request)
            )
            correctExplanation = localized("Randomization, blinded assessment, and predefined independent replication address distinct design threats; post-hoc exclusion introduces bias.", request: request)
            decisiveStep = localized("Each safeguard should block a named path from design choices to a misleading result.", request: request)
            tags = ["experimental-design", "randomization", "blinding", "replication", "bias"]
            errorExplanations = ["multiple_choice_selection": localized("The selected set misses a design threat or introduces post-outcome selection.", request: request)]

        case 5:
            var options = [
                NFChoiceOption(id: "correct", text: localized("Measure the outcome before and after the proposed mechanism while holding the rival mechanism fixed.", request: request), accessibilityLabel: nil, distractorCode: nil),
                NFChoiceOption(id: "confirm", text: localized("Collect only observations already predicted by the favored hypothesis.", request: request), accessibilityLabel: nil, distractorCode: "confirmation_bias"),
                NFChoiceOption(id: "vague", text: localized("Ask whether either hypothesis could explain some result after the fact.", request: request), accessibilityLabel: nil, distractorCode: "hypothesis_discrimination"),
                NFChoiceOption(id: "merge", text: localized("Treat the hypotheses as identical without testing their distinct predictions.", request: request), accessibilityLabel: nil, distractorCode: "hypothesis_discrimination")
            ]
            random.shuffle(&options)
            templateSlug = "competing-hypotheses.prediction"
            prompt = localized("Two mechanisms explain the same observation. Which evidence plan most clearly updates confidence between them?", request: request)
            context = contextualLead(request) + localized(" The hypotheses are deterministic state labels; the answer depends on their contrasting predictions.", request: request)
            instructions = localized("Choose the plan that isolates a prediction unique to one mechanism.", request: request)
            interaction = .singleChoice(NFSingleChoiceResponseSchema(options: options, correctOptionID: "correct"))
            representations = [.prose]
            strategy = NFExerciseStrategy(
                id: "strategy.hypotheses.contrast",
                title: localized("Seek risky contrasting predictions", request: request),
                summary: localized("Prefer evidence that one hypothesis expects and the rival does not.", request: request),
                orderedSteps: [localized("State each mechanism", request: request), localized("Derive distinct predictions", request: request), localized("Control the rival", request: request), localized("Update from the observation", request: request)],
                whenToUse: localized("Competing-hypothesis reasoning", request: request)
            )
            correctExplanation = localized("Holding the rival fixed while manipulating or observing the proposed mechanism creates contrasting predictions.", request: request)
            decisiveStep = localized("Do not ask whether evidence fits; ask how differently each hypothesis predicts it.", request: request)
            tags = ["competing-hypotheses", "researcher-track", "hypothesis-update"]
            errorExplanations = [
                "confirmation_bias": localized("Sampling only confirming cases cannot compare the rival explanation.", request: request),
                "hypothesis_discrimination": localized("A plan that permits either explanation after the fact has little discriminating value.", request: request)
            ]

        case 6:
            var options = [
                NFChoiceOption(id: "assignment", text: localized("Convenience assignment differs systematically between groups.", request: request), accessibilityLabel: nil, distractorCode: nil),
                NFChoiceOption(id: "axis", text: localized("A truncated vertical axis visually exaggerates a small difference.", request: request), accessibilityLabel: nil, distractorCode: nil),
                NFChoiceOption(id: "replication", text: localized("The method reports an independent replication.", request: request), accessibilityLabel: nil, distractorCode: "not_a_flaw"),
                NFChoiceOption(id: "raw", text: localized("The report provides the raw synthetic values used in the plot.", request: request), accessibilityLabel: nil, distractorCode: "not_a_flaw")
            ]
            random.shuffle(&options)
            templateSlug = "reviewer-mode.method-figure"
            prompt = localized("Reviewer mode: a fictional report uses convenience assignment and a graph whose y-axis starts just below both group means. Which are validity or presentation concerns?", request: request)
            context = contextualLead(request) + localized(" This is an educational review of a seeded fictional report, not real research advice.", request: request)
            instructions = localized("Select every documented concern.", request: request)
            interaction = .multipleChoice(
                NFMultipleChoiceResponseSchema(
                    options: options,
                    correctOptionIDs: ["assignment", "axis"],
                    minimumSelections: 1,
                    maximumSelections: 4
                )
            )
            representations = [.table(
                headers: [localized("Report feature", request: request), localized("Recorded state", request: request)],
                rows: [[localized("Assignment", request: request), localized("Convenience", request: request)], [localized("Axis minimum", request: request), localized("Near both means", request: request)], [localized("Raw values", request: request), localized("Provided", request: request)], [localized("Replication", request: request), localized("Reported", request: request)]],
                accessibilitySummary: localized("The report has convenience assignment and a truncated axis, while raw values and replication are provided.", request: request)
            )]
            strategy = NFExerciseStrategy(
                id: "strategy.reviewer.threats",
                title: localized("Separate flaws from strengths", request: request),
                summary: localized("Audit assignment, measurement, analysis, presentation, and reproducibility as distinct dimensions.", request: request),
                orderedSteps: [localized("Inspect assignment", request: request), localized("Inspect measurement", request: request), localized("Inspect visualization", request: request), localized("Inspect reproducibility", request: request)],
                whenToUse: localized("Reviewer mode and data forensics", request: request)
            )
            correctExplanation = localized("Convenience assignment limits causal comparability, and the truncated axis can exaggerate the visual effect; raw data and replication are strengths.", request: request)
            decisiveStep = localized("Classify each report feature by the threat it creates rather than marking every unusual detail as a flaw.", request: request)
            tags = ["reviewer-mode", "researcher-track", "data-forensics", "bias"]
            errorExplanations = ["multiple_choice_selection": localized("The concern set should include documented assignment and axis threats without treating transparency as a flaw.", request: request)]

        case 7:
            var steps = [
                NFOrderedStep(id: "hypotheses", text: localized("List hypotheses", request: request)),
                NFOrderedStep(id: "predictions", text: localized("Write predictions", request: request)),
                NFOrderedStep(id: "control", text: localized("Hold alternatives fixed", request: request)),
                NFOrderedStep(id: "contrast", text: localized("Choose the largest prediction contrast", request: request))
            ]
            random.shuffle(&steps)
            templateSlug = "design.discriminating-sequence"
            prompt = localized("An increased output could be caused by intervention A or by measurement drift. Which next experiment best discriminates the hypotheses?", request: request)
            context = contextualLead(request) + localized(" The useful experiment changes A independently and checks the outcome with a separate calibrated measurement.", request: request)
            instructions = localized("Order the extraction steps.", request: request)
            interaction = .orderedSteps(
                NFOrderedStepsResponseSchema(
                    steps: steps,
                    correctOrder: ["hypotheses", "predictions", "control", "contrast"]
                )
            )
            representations = [.prose]
            strategy = NFExerciseStrategy(
                id: "strategy.experiment.discriminate",
                title: localized("Maximize contrasting predictions", request: request),
                summary: localized("Choose a manipulation and measurement for which the hypotheses predict different observations.", request: request),
                orderedSteps: [localized("List hypotheses", request: request), localized("Write predictions", request: request), localized("Hold alternatives fixed", request: request), localized("Choose the largest prediction contrast", request: request)],
                whenToUse: localized("Choose-the-next-experiment tasks", request: request)
            )
            correctExplanation = localized("Independent manipulation and measurement separate a real effect of A from drift in the original measurement process.", request: request)
            decisiveStep = localized("Choose the test on which the two hypotheses make different predictions.", request: request)
            tags = ["experimental-design", "ordered-design", "competing-hypotheses"]
            errorExplanations = ["ordered_steps_sequence": localized("Choose the test on which the two hypotheses make different predictions.", request: request)]

        default:
            var steps = [
                NFOrderedStep(id: "question", text: localized("Identify the research question and stated hypothesis.", request: request)),
                NFOrderedStep(id: "method", text: localized("Identify variables, comparison, and measurement method.", request: request)),
                NFOrderedStep(id: "result", text: localized("Extract the reported result with its uncertainty.", request: request)),
                NFOrderedStep(id: "limit", text: localized("Separate the conclusion from remaining limitations.", request: request))
            ]
            random.shuffle(&steps)
            templateSlug = "paper-sprint.structure"
            prompt = localized("Paper Sprint: arrange a fast, defensible reading sequence for an unfamiliar abstract.", request: request)
            context = contextualLead(request) + localized(" The sequence preserves question, method, result, and limitation as separate evidence fields.", request: request)
            instructions = localized("Order the extraction steps.", request: request)
            interaction = .orderedSteps(
                NFOrderedStepsResponseSchema(
                    steps: steps,
                    correctOrder: ["question", "method", "result", "limit"]
                )
            )
            representations = [.prose]
            strategy = NFExerciseStrategy(
                id: "strategy.paper-sprint.schema",
                title: localized("Read into an evidence schema", request: request),
                summary: localized("Extract the question, method, result, and limitations before accepting the conclusion.", request: request),
                orderedSteps: [localized("Question", request: request), localized("Method", request: request), localized("Result", request: request), localized("Limit", request: request)],
                whenToUse: localized("Paper Sprint and unfamiliar abstracts", request: request)
            )
            correctExplanation = localized("The ordered schema prevents a conclusion from being evaluated before its design and evidence are identified.", request: request)
            decisiveStep = localized("Keep the measured result separate from the authors’ broader conclusion.", request: request)
            tags = ["paper-sprint", "researcher-track", "evidence-extraction"]
            errorExplanations = ["ordered_steps_sequence": localized("Identify the question and method before interpreting results and limitations.", request: request)]
        }

        return Draft(
            templateSlug: templateSlug,
            title: localized("Scientific reasoning", request: request),
            prompt: prompt,
            contextText: context,
            instructions: instructions,
            interaction: interaction,
            difficulty: difficulty(base: 0.52 + Double(variant % 4) * 0.045, steps: 3 + variant / 3, shift: 0.4 + Double(variant % 3) * 0.15),
            skillWeights: ["skill.scientificReasoning": 0.8, "skill.quantitative": 0.2],
            strategies: [strategy],
            representations: representations,
            citations: [],
            rubric: exactRubric(localized("Correct design or evidence inference", request: request)),
            correctExplanation: correctExplanation,
            retryExplanation: localized("Separate observation, design, competing explanations, and claim scope before choosing.", request: request),
            decisiveStep: decisiveStep,
            hints: [localized("Name the design feature or evidence type first.", request: request), decisiveStep],
            errorExplanations: errorExplanations,
            accessibility: standardAccessibility(label: prompt),
            expectedDurationSeconds: 95 + variant * 5,
            tags: tags + ["educational-synthetic-scenario"]
        )
    }

    private static func claimScopeStrategy(
        request: NFExerciseGenerationRequest
    ) -> NFExerciseStrategy {
        NFExerciseStrategy(
            id: "strategy.claim-scope",
            title: localized("Match evidence to claim scope", request: request),
            summary: localized("Check whether the design and observation support descriptive, causal, or universal language.", request: request),
            orderedSteps: [localized("Classify the claim", request: request), localized("Inspect the design", request: request), localized("Preserve uncertainty", request: request), localized("State only the supported scope", request: request)],
            whenToUse: localized("Experimental claims and figure interpretation", request: request)
        )
    }

    private static func stateTableStrategy(
        request: NFExerciseGenerationRequest
    ) -> NFExerciseStrategy {
        NFExerciseStrategy(
            id: "strategy.state-table",
            title: localized("Trace one transition at a time", request: request),
            summary: localized("Write the complete state after each mutation and recheck derived values and invariants.", request: request),
            orderedSteps: [localized("Copy the initial state", request: request), localized("Apply one transition", request: request), localized("Record every variable", request: request), localized("Check invariants", request: request)],
            whenToUse: localized("Mutable state, loops, and event sequences", request: request)
        )
    }

    private static func logicDebuggingDraft(
        request: NFExerciseGenerationRequest,
        random: inout NFFallbackRandom
    ) -> Draft {
        let variant = selectedVariant(
            request: request,
            defaultUpperBound: variantCount(for: .logicDebugging),
            compatibleVariants: [
                .stateTrace: [0],
                .singleChoice: [1, 2, 4, 5, 6, 7, 8],
                .orderedSteps: [3, 8]
            ],
            random: &random
        )
        let templateSlug: String
        let prompt: String
        let context: String
        let instructions: String
        let interaction: NFExerciseInteraction
        let representations: [NFExerciseRepresentation]
        let strategy: NFExerciseStrategy
        let correctExplanation: String
        let decisiveStep: String
        let tags: [String]
        let errorExplanations: [String: String]
        let rubric: NFExerciseRubric

        switch variant {
        case 0:
            let start = 20 + random.int(upperBound: 60)
            let decrement = 2 + random.int(upperBound: 18)
            let adjustment = 1 + random.int(upperBound: 18)
            let afterDecrement = start - decrement
            let threshold = afterDecrement
            let program: [NFPseudocodeStatement] = [
                .assign(name: "count", expression: .subtract(.variable("count"), .value(.integer(decrement)))),
                .ifThen(
                    condition: .lessThanOrEqual(.variable("count"), .value(.integer(threshold))),
                    body: [.assign(name: "ready", expression: .value(.boolean(true)))]
                ),
                .assign(name: "count", expression: .add(.variable("count"), .value(.integer(adjustment))))
            ]
            let execution = try? NFRestrictedPseudocodeInterpreter.execute(
                program,
                initialVariables: ["count": .integer(start), "ready": .boolean(false)]
            )
            let finalCount = execution?.integer(named: "count") ?? (afterDecrement + adjustment)
            let finalReady = execution?.boolean(named: "ready") ?? true
            let skinIndex = random.int(upperBound: NFPseudocodeDisplaySkin.allCases.count)
            let displaySkin = NFPseudocodeDisplaySkin.allCases[skinIndex]
            let skinTag = displaySkin.rawValue
            let skin = [
                localized("Language-neutral", request: request),
                localized("Python-like", request: request),
                localized("JavaScript-like", request: request),
                localized("Swift-like", request: request)
            ][skinIndex]
            let transitions = [
                NFLogicTransition(id: "t1", condition: localized("always", request: request), mutation: "count = count - \(decrement)"),
                NFLogicTransition(id: "t2", condition: "count <= \(threshold)", mutation: "ready = true"),
                NFLogicTransition(
                    id: "t3",
                    condition: localized("always", request: request),
                    mutation: "count = count + \(adjustment); \(localized("ready is not recomputed", request: request))"
                )
            ]
            let representation = NFLogicRepresentationMetadata(
                variables: [
                    "count": localized("integer", request: request),
                    "ready": localized("Boolean", request: request)
                ],
                transitions: transitions,
                invariants: [
                    "rule.readiness": localized("ready must equal (count <= \(threshold))", request: request),
                    "rule.nonnegative": localized("count must remain nonnegative", request: request)
                ],
                traceLanguage: skin
            )
            templateSlug = "trace.stale-derived-state"
            prompt = localized("Trace the state and identify the invariant first violated after the final transition.", request: request)
            context = localized("Initial state: count = \(start), ready = false. ", request: request) + contextualLead(request)
            instructions = localized("Enter the final state and select the first violated invariant.", request: request)
            interaction = .logicState(
                NFLogicStateResponseSchema(
                    initialState: ["count": "\(start)", "ready": "false"],
                    expectedFinalState: ["count": "\(finalCount)", "ready": "\(finalReady)"],
                    acceptedEquivalentStates: [],
                    ruleOptions: [
                        NFChoiceOption(id: "rule.readiness", text: localized("ready must equal (count <= \(threshold))", request: request), accessibilityLabel: nil, distractorCode: nil),
                        NFChoiceOption(id: "rule.nonnegative", text: localized("count must remain nonnegative", request: request), accessibilityLabel: nil, distractorCode: nil)
                    ],
                    expectedViolatedRuleID: "rule.readiness"
                )
            )
            representations = [
                .logicState(representation),
                .code(
                    language: skin,
                    source: NFPseudocodeRenderer.render(program, skin: displaySkin),
                    accessibilitySummary: localized("Three state transitions update count, derive ready, then update count without recomputing ready.", request: request)
                )
            ]
            strategy = stateTableStrategy(request: request)
            correctExplanation = localized("The count changes after ready is derived, leaving ready stale and inconsistent with its invariant.", request: request)
            decisiveStep = localized("After the last count mutation, compare the stored ready value with count less than or equal to the threshold.", request: request)
            tags = ["state-tracing", "invariant", "ast-family", skinTag]
            errorExplanations = [
                "logic_state": localized("The final state does not follow each mutation in sequence.", request: request),
                "logic_rule": localized("The final state is right, but the selected invariant is not the one it violates.", request: request)
            ]
            rubric = weightedRubric([
                ("state", localized("Correct final state", request: request), 0.8),
                ("invariant", localized("Correct violated invariant", request: request), 0.2)
            ])

        case 1:
            var options = [
                NFChoiceOption(id: "correct", text: localized("Sufficient but not necessary", request: request), accessibilityLabel: nil, distractorCode: nil),
                NFChoiceOption(id: "necessary", text: localized("Necessary but not sufficient", request: request), accessibilityLabel: nil, distractorCode: "condition_direction"),
                NFChoiceOption(id: "both", text: localized("Necessary and sufficient", request: request), accessibilityLabel: nil, distractorCode: "converse_assumed"),
                NFChoiceOption(id: "neither", text: localized("Neither necessary nor sufficient", request: request), accessibilityLabel: nil, distractorCode: "implication_ignored")
            ]
            random.shuffle(&options)
            templateSlug = "conditions.divisibility"
            prompt = localized("For integers, divisibility by 4 guarantees evenness. Relative to being even, being divisible by 4 is what kind of condition?", request: request)
            context = contextualLead(request) + localized(" Multiples of 4 are even, but 2 and 6 are even without being divisible by 4.", request: request)
            instructions = localized("Choose the exact logical relationship.", request: request)
            interaction = .singleChoice(NFSingleChoiceResponseSchema(options: options, correctOptionID: "correct"))
            representations = [.equation(latex: "4 \\mid n \\Rightarrow 2 \\mid n", spokenDescription: localized("If four divides n, then two divides n", request: request))]
            strategy = NFExerciseStrategy(
                id: "strategy.conditions.counterexample",
                title: localized("Test both directions", request: request),
                summary: localized("Check the stated implication, then seek one counterexample to its converse.", request: request),
                orderedSteps: [localized("Write A implies B", request: request), localized("Test A to B", request: request), localized("Test B to A", request: request), localized("Classify necessity and sufficiency", request: request)],
                whenToUse: localized("Necessary and sufficient conditions", request: request)
            )
            correctExplanation = localized("Divisibility by 4 is enough for evenness, but evenness does not require divisibility by 4.", request: request)
            decisiveStep = localized("The even integer 2 refutes the converse.", request: request)
            tags = ["necessary-sufficient", "conditional-logic", "counterexample"]
            errorExplanations = [
                "condition_direction": localized("The direction of necessity and sufficiency has been reversed.", request: request),
                "converse_assumed": localized("The converse fails for even integers such as 2.", request: request),
                "implication_ignored": localized("The given implication establishes sufficiency.", request: request)
            ]
            rubric = exactRubric(localized("Correct condition classification", request: request))

        case 2:
            var options = [
                NFChoiceOption(id: "correct", text: localized("a = 2 and b = 3", request: request), accessibilityLabel: nil, distractorCode: nil),
                NFChoiceOption(id: "both", text: localized("a = 2 and b = 4", request: request), accessibilityLabel: nil, distractorCode: "not_counterexample"),
                NFChoiceOption(id: "odd", text: localized("a = 3 and b = 5", request: request), accessibilityLabel: nil, distractorCode: "premise_false"),
                NFChoiceOption(id: "zero", text: localized("a = 0 and b = 2", request: request), accessibilityLabel: nil, distractorCode: "not_counterexample")
            ]
            random.shuffle(&options)
            templateSlug = "counterexample.even-product"
            prompt = localized("Select a counterexample to the claim: if integer product a×b is even, then both a and b are even.", request: request)
            context = contextualLead(request) + localized(" A counterexample must satisfy the premise and falsify the conclusion.", request: request)
            instructions = localized("Choose one valid counterexample.", request: request)
            interaction = .singleChoice(NFSingleChoiceResponseSchema(options: options, correctOptionID: "correct"))
            representations = [.equation(latex: "2 \\times 3 = 6", spokenDescription: localized("Two times three equals six", request: request))]
            strategy = NFExerciseStrategy(
                id: "strategy.counterexample.constraints",
                title: localized("Satisfy premise, break conclusion", request: request),
                summary: localized("A valid counterexample must make the hypothesis true and the claimed consequence false.", request: request),
                orderedSteps: [localized("Parse the premise", request: request), localized("Parse the conclusion", request: request), localized("Satisfy the premise", request: request), localized("Falsify the conclusion", request: request)],
                whenToUse: localized("Universal claims and hidden assumptions", request: request)
            )
            correctExplanation = localized("Two times three is even, while three is odd, so the claim that both factors must be even is false.", request: request)
            decisiveStep = localized("Check the premise and conclusion independently for the same candidate.", request: request)
            tags = ["counterexample", "hidden-assumption", "invalid-implication"]
            errorExplanations = [
                "not_counterexample": localized("The candidate also satisfies the conclusion, so it does not refute the claim.", request: request),
                "premise_false": localized("A case with an odd product does not satisfy the claim’s premise.", request: request)
            ]
            rubric = exactRubric(localized("Valid counterexample", request: request))

        case 3:
            var steps = [
                NFOrderedStep(id: "define", text: localized("Write the odd integers as 2m + 1 and 2n + 1.", request: request)),
                NFOrderedStep(id: "add", text: localized("Add to obtain 2m + 2n + 2.", request: request)),
                NFOrderedStep(id: "factor", text: localized("Factor the sum as 2(m + n + 1).", request: request)),
                NFOrderedStep(id: "conclude", text: localized("Conclude the sum is even because it is twice an integer.", request: request))
            ]
            random.shuffle(&steps)
            templateSlug = "proof.order-odd-sum"
            prompt = localized("Arrange the proof that the sum of two odd integers is even.", request: request)
            context = contextualLead(request) + localized(" The deterministic key follows dependency order, not stylistic preference.", request: request)
            instructions = localized("Order every proof step.", request: request)
            interaction = .orderedSteps(NFOrderedStepsResponseSchema(steps: steps, correctOrder: ["define", "add", "factor", "conclude"]))
            representations = [.equation(latex: "(2m+1)+(2n+1)=2(m+n+1)", spokenDescription: localized("The sum factors as two times an integer", request: request))]
            strategy = NFExerciseStrategy(
                id: "strategy.proof.dependencies",
                title: localized("Order by logical dependency", request: request),
                summary: localized("Each proof line must use only definitions or results already established.", request: request),
                orderedSteps: [localized("Define objects", request: request), localized("Transform", request: request), localized("Expose the target form", request: request), localized("State the conclusion", request: request)],
                whenToUse: localized("Proof-step ordering", request: request)
            )
            correctExplanation = localized("The definitions permit the sum, factoring exposes a multiple of two, and only then does the evenness conclusion follow.", request: request)
            decisiveStep = localized("Expose the expression as two times an integer before concluding it is even.", request: request)
            tags = ["proof-step-ordering", "direct-proof", "dependency-order"]
            errorExplanations = ["ordered_steps_sequence": localized("A proof step appears before the definition or algebra it depends on.", request: request)]
            rubric = exactRubric(localized("Dependency-valid proof order", request: request))

        case 4:
            var options = [
                NFChoiceOption(id: "correct", text: localized("Divide both sides by a − b", request: request), accessibilityLabel: nil, distractorCode: nil),
                NFChoiceOption(id: "assume", text: localized("Assume a = b with a nonzero", request: request), accessibilityLabel: nil, distractorCode: "valid_step"),
                NFChoiceOption(id: "multiply", text: localized("Multiply a = b by a", request: request), accessibilityLabel: nil, distractorCode: "valid_step"),
                NFChoiceOption(id: "subtract", text: localized("Subtract b² from both sides", request: request), accessibilityLabel: nil, distractorCode: "valid_step")
            ]
            random.shuffle(&options)
            templateSlug = "proof.first-invalid-division"
            prompt = localized("A false proof starts with nonzero a = b, obtains a² − b² = ab − b², factors, then divides by a − b. What is the first invalid step?", request: request)
            context = contextualLead(request) + localized(" Because a equals b, the proposed divisor is zero.", request: request)
            instructions = localized("Choose the first invalid step.", request: request)
            interaction = .singleChoice(NFSingleChoiceResponseSchema(options: options, correctOptionID: "correct"))
            representations = [.equation(latex: "(a-b)(a+b)=b(a-b)", spokenDescription: localized("Both sides contain the factor a minus b", request: request))]
            strategy = NFExerciseStrategy(
                id: "strategy.proof.preconditions",
                title: localized("Audit operation preconditions", request: request),
                summary: localized("At every transformation, check domain restrictions such as nonzero divisors.", request: request),
                orderedSteps: [localized("Verify prior equality", request: request), localized("Name the operation", request: request), localized("Check its preconditions", request: request), localized("Locate the first failure", request: request)],
                whenToUse: localized("Invalid-step localization", request: request)
            )
            correctExplanation = localized("Since a equals b, a minus b equals zero; division by that factor is undefined.", request: request)
            decisiveStep = localized("Evaluate the divisor under the original assumption before canceling it.", request: request)
            tags = ["first-invalid-step", "proof-audit", "division-by-zero"]
            errorExplanations = ["valid_step": localized("This earlier algebraic step is valid; the failure occurs when a zero factor is canceled.", request: request)]
            rubric = exactRubric(localized("First invalid proof step", request: request))

        case 5:
            let smallestFailingCount = (1...4).first { count in
                let program: [NFPseudocodeStatement] = [
                    .assign(name: "index", expression: .value(.integer(0))),
                    .whileLoop(
                        condition: .lessThan(
                            .variable("index"),
                            .subtract(.inputCount, .value(.integer(1)))
                        ),
                        iterationLimit: 16,
                        body: [
                            .visitInput(index: .variable("index")),
                            .assign(name: "index", expression: .add(.variable("index"), .value(.integer(1))))
                        ]
                    )
                ]
                let execution = try? NFRestrictedPseudocodeInterpreter.execute(program, inputCount: count)
                return execution?.visitedInputIndices != Array(0..<count)
            } ?? 1
            var options = [
                NFChoiceOption(id: "correct", text: localized("A \(smallestFailingCount)-element list", request: request), accessibilityLabel: nil, distractorCode: nil),
                NFChoiceOption(id: "empty", text: localized("An empty list only", request: request), accessibilityLabel: nil, distractorCode: "edge_case_missed"),
                NFChoiceOption(id: "two", text: localized("A two-element list only", request: request), accessibilityLabel: nil, distractorCode: "not_minimal"),
                NFChoiceOption(id: "large", text: localized("Only a very large list", request: request), accessibilityLabel: nil, distractorCode: "not_minimal")
            ]
            random.shuffle(&options)
            templateSlug = "debug.boundary-last-element"
            prompt = localized("A sum loop runs while index < count − 1, so it never visits the final element. What is the smallest nonempty failing input?", request: request)
            context = contextualLead(request) + localized(" The bounded internal AST is interpreted; user text and imported code are never executed.", request: request)
            instructions = localized("Choose the minimal boundary case.", request: request)
            interaction = .singleChoice(NFSingleChoiceResponseSchema(options: options, correctOptionID: "correct"))
            representations = [.code(language: "language-neutral", source: "index = 0\nwhile index < count - 1:\n    total += values[index]\n    index += 1", accessibilitySummary: localized("The loop condition stops before the final valid index.", request: request))]
            strategy = NFExerciseStrategy(
                id: "strategy.boundary.smallest",
                title: localized("Shrink to the first failing boundary", request: request),
                summary: localized("Test empty, one-element, and just-over-boundary inputs before large examples.", request: request),
                orderedSteps: [localized("Identify valid index range", request: request), localized("Evaluate the loop condition", request: request), localized("Try the smallest nonempty input", request: request), localized("Confirm the missed state", request: request)],
                whenToUse: localized("Boundary and edge-case debugging", request: request)
            )
            correctExplanation = localized("For count one, index zero fails zero < zero, so the sole element is immediately skipped.", request: request)
            decisiveStep = localized("Substitute count = 1 into the loop condition.", request: request)
            tags = ["boundary-case", "edge-case", "off-by-one", "ast-family"]
            errorExplanations = [
                "edge_case_missed": localized("The question asks for the smallest nonempty failing input.", request: request),
                "not_minimal": localized("This may fail, but a smaller nonempty case already exposes the defect.", request: request)
            ]
            rubric = exactRubric(localized("Minimal failing input", request: request))

        case 6:
            var options = [
                NFChoiceOption(id: "correct", text: localized("The single-pass algorithm grows linearly; the nested-pair algorithm grows quadratically.", request: request), accessibilityLabel: nil, distractorCode: nil),
                NFChoiceOption(id: "same", text: localized("Both have the same growth because both return one result.", request: request), accessibilityLabel: nil, distractorCode: "complexity_output"),
                NFChoiceOption(id: "reverse", text: localized("The nested-pair algorithm is linear and the single pass is quadratic.", request: request), accessibilityLabel: nil, distractorCode: "complexity_reversed"),
                NFChoiceOption(id: "constant", text: localized("Both are constant time because n is fixed for one run.", request: request), accessibilityLabel: nil, distractorCode: "complexity_parameter")
            ]
            random.shuffle(&options)
            templateSlug = "debug.complexity-comparison"
            prompt = localized("One algorithm scans n records once; another compares every ordered pair of records. Which growth comparison is correct?", request: request)
            context = contextualLead(request) + localized(" Compare operation-count functions as input size varies.", request: request)
            instructions = localized("Choose the asymptotic comparison.", request: request)
            interaction = .singleChoice(NFSingleChoiceResponseSchema(options: options, correctOptionID: "correct"))
            representations = [.equation(latex: "T_1(n)=n,\\quad T_2(n)=n(n-1)", spokenDescription: localized("One cost is n; the other is n times n minus one", request: request))]
            strategy = NFExerciseStrategy(
                id: "strategy.complexity.count",
                title: localized("Count repeated work", request: request),
                summary: localized("Write the dominant operation count as a function of input size.", request: request),
                orderedSteps: [localized("Name input size", request: request), localized("Count loop repetitions", request: request), localized("Form the cost expression", request: request), localized("Compare growth", request: request)],
                whenToUse: localized("Restricted algorithm complexity comparison", request: request)
            )
            correctExplanation = localized("A single scan performs work proportional to n; comparing ordered pairs performs work proportional to n squared.", request: request)
            decisiveStep = localized("Count how many inner operations occur for each of the n outer items.", request: request)
            tags = ["complexity-comparison", "algorithm-analysis", "ast-family"]
            errorExplanations = [
                "complexity_output": localized("Output size does not determine computation cost.", request: request),
                "complexity_reversed": localized("Nested pair enumeration repeats work for each outer item.", request: request),
                "complexity_parameter": localized("Complexity describes how work changes across possible n.", request: request)
            ]
            rubric = exactRubric(localized("Correct growth comparison", request: request))

        case 7:
            var options = [
                NFChoiceOption(id: "correct", text: localized("Change the condition to index < count.", request: request), accessibilityLabel: nil, distractorCode: nil),
                NFChoiceOption(id: "plus", text: localized("Change the condition to index <= count.", request: request), accessibilityLabel: nil, distractorCode: "out_of_bounds"),
                NFChoiceOption(id: "start", text: localized("Start index at 1 and keep index < count − 1.", request: request), accessibilityLabel: nil, distractorCode: "elements_skipped"),
                NFChoiceOption(id: "double", text: localized("Increment index by 2.", request: request), accessibilityLabel: nil, distractorCode: "elements_skipped")
            ]
            random.shuffle(&options)
            templateSlug = "debug.repair-loop-bound"
            prompt = localized("Choose the prevalidated repair for a zero-based loop that must visit every element exactly once.", request: request)
            context = contextualLead(request) + localized(" Candidate patches were checked against empty, singleton, and multi-element arrays.", request: request)
            instructions = localized("Choose the repair that passes all boundary tests.", request: request)
            interaction = .singleChoice(NFSingleChoiceResponseSchema(options: options, correctOptionID: "correct"))
            representations = [.code(language: "language-neutral", source: "index = 0\nwhile index < count - 1:\n    visit(values[index])\n    index += 1", accessibilitySummary: localized("The original loop stops one position before the array count.", request: request))]
            strategy = NFExerciseStrategy(
                id: "strategy.patch.tests",
                title: localized("Validate patches against boundary tests", request: request),
                summary: localized("A repair must satisfy the full iteration invariant for empty, singleton, and typical inputs.", request: request),
                orderedSteps: [localized("State the intended index range", request: request), localized("Evaluate each patch", request: request), localized("Check boundary inputs", request: request), localized("Reject new failures", request: request)],
                whenToUse: localized("Pseudocode repair", request: request)
            )
            correctExplanation = localized("Valid zero-based indices are zero through count minus one, exactly captured by index less than count.", request: request)
            decisiveStep = localized("The loop condition should admit the last valid index and reject index equal to count.", request: request)
            tags = ["repair-pseudocode", "boundary-case", "ast-family"]
            errorExplanations = [
                "out_of_bounds": localized("Less-than-or-equal admits index equal to count, which is outside the array.", request: request),
                "elements_skipped": localized("The patch skips valid elements and does not meet the visit-every-element invariant.", request: request)
            ]
            rubric = exactRubric(localized("Prevalidated pseudocode repair", request: request))

        default:
            let observedCorrect = 7 + random.int(upperBound: 3)
            var calibrationSteps = [
                NFOrderedStep(id: "family", text: localized("Define the comparable item family", request: request)),
                NFOrderedStep(id: "rate", text: localized("Compute the observed rate", request: request)),
                NFOrderedStep(id: "uncertainty", text: localized("Retain sampling uncertainty", request: request))
            ]
            random.shuffle(&calibrationSteps)
            var options = [
                NFChoiceOption(
                    id: "correct",
                    text: localized("Use about \(observedCorrect * 10)% as the current estimate and keep uncertainty because the sample is small.", request: request),
                    accessibilityLabel: nil,
                    distractorCode: nil
                ),
                NFChoiceOption(
                    id: "perfect",
                    text: localized("Declare 100% certainty because most responses were correct.", request: request),
                    accessibilityLabel: nil,
                    distractorCode: "calibration_overconfidence"
                ),
                NFChoiceOption(
                    id: "half",
                    text: localized("Always report 50% confidence so calibration can never look overconfident.", request: request),
                    accessibilityLabel: nil,
                    distractorCode: "calibration_avoidance"
                ),
                NFChoiceOption(
                    id: "ignore",
                    text: localized("Ignore the observed results and use the confidence felt before the task.", request: request),
                    accessibilityLabel: nil,
                    distractorCode: "evidence_ignored"
                )
            ]
            random.shuffle(&options)
            templateSlug = "calibration.observed-frequency"
            prompt = localized("You answered \(observedCorrect) of 10 comparable items correctly. Which confidence update is best calibrated to this evidence?", request: request)
            context = contextualLead(request) + localized(" Calibration compares stated confidence with outcomes on a defined item family.", request: request)
            if request.preferredAssessmentFormat == .orderedSteps {
                instructions = localized("Order the extraction steps.", request: request)
                interaction = .orderedSteps(
                    NFOrderedStepsResponseSchema(
                        steps: calibrationSteps,
                        correctOrder: ["family", "rate", "uncertainty"]
                    )
                )
            } else {
                instructions = localized("Choose the evidence-bounded confidence update.", request: request)
                interaction = .singleChoice(NFSingleChoiceResponseSchema(options: options, correctOptionID: "correct"))
            }
            representations = [.table(
                headers: [localized("Comparable items", request: request), localized("Fully correct", request: request)],
                rows: [["10", localized("\(observedCorrect)", request: request)]],
                accessibilitySummary: localized("\(observedCorrect) of 10 comparable responses were fully correct.", request: request)
            )]
            strategy = NFExerciseStrategy(
                id: "strategy.calibration.frequency",
                title: localized("Anchor confidence to comparable outcomes", request: request),
                summary: localized("Use the observed hit rate as an estimate while preserving uncertainty from a small sample.", request: request),
                orderedSteps: [localized("Define the comparable item family", request: request), localized("Compute the observed rate", request: request), localized("Retain sampling uncertainty", request: request)],
                whenToUse: localized("Updating confidence after a bounded set of comparable tasks", request: request)
            )
            correctExplanation = localized("The observed rate is relevant evidence for this item family, but ten responses do not justify certainty.", request: request)
            decisiveStep = localized("Separate the current estimate from the uncertainty around that estimate.", request: request)
            tags = ["calibration", "metacognition", "observed-frequency"]
            errorExplanations = [
                "calibration_overconfidence": localized("A high observed rate is not the same as certainty.", request: request),
                "calibration_avoidance": localized("Always choosing 50% avoids using relevant evidence.", request: request),
                "evidence_ignored": localized("Calibration requires comparing confidence with outcomes on comparable tasks.", request: request)
            ]
            rubric = exactRubric(localized("Evidence-bounded calibration update", request: request))
        }

        return Draft(
            templateSlug: templateSlug,
            title: localized("Logic, proof, and debugging", request: request),
            prompt: prompt,
            contextText: context,
            instructions: instructions,
            interaction: interaction,
            difficulty: difficulty(base: 0.5 + Double(variant % 4) * 0.05, steps: 3 + variant / 3, shift: 0.3 + Double(variant % 3) * 0.15),
            skillWeights: ["skill.logicDebugging": 0.85, "skill.quantitative": 0.15],
            strategies: [strategy],
            representations: representations,
            citations: [],
            rubric: rubric,
            correctExplanation: correctExplanation,
            retryExplanation: localized("Translate the claim or pseudocode into explicit states, conditions, and operation preconditions.", request: request),
            decisiveStep: decisiveStep,
            hints: [localized("Write the relevant state or implication explicitly.", request: request), decisiveStep],
            errorExplanations: errorExplanations,
            accessibility: standardAccessibility(label: prompt),
            expectedDurationSeconds: 90 + variant * 5,
            tags: tags + ["logic-debugging"]
        )
    }

    private static func retrievalDraft(
        request: NFExerciseGenerationRequest,
        random: inout NFFallbackRandom
    ) -> Draft {
        // User-material facts are never assessment authority. Only the explicit
        // document-practice purpose can consume them; every standardized purpose
        // falls back to a bundled, locally verified retrieval contract.
        let suppliedCandidate = request.purpose == .documentPractice
            ? request.sourceContext.groundingFacts.first
            : nil
        let suppliedCitation = suppliedCandidate.flatMap {
            citation(for: $0, context: request.sourceContext, request: request)
        }
        // A document-derived key needs both a document and a stable chunk. If the
        // bounded context is incomplete, use a bundled, locally verified
        // retrieval contract instead of silently presenting uncited material as
        // authoritative.
        let suppliedFact = suppliedCitation?.sourceChunkID == nil ? nil : suppliedCandidate
        let fallbackFact: NFExerciseGroundingFact
        if suppliedFact == nil {
            let target = bundledRetrievalTarget(for: request.sourceContext.primaryField, random: &random)
            fallbackFact = NFExerciseGroundingFact(
                id: target.id,
                statement: target.prompt,
                expectedAnswer: target.answer,
                acceptedAlternatives: target.acceptedAnswers,
                citationIDs: []
            )
        } else {
            // Unused when a complete cited fact is present; retaining the
            // field fallback keeps this branch total if a future policy changes
            // source selection after validation.
            fallbackFact = genericFact(for: request.sourceContext.primaryField, request: request)
        }
        let fact = suppliedFact ?? fallbackFact
        let citations = suppliedFact == nil ? [] : suppliedCitation.map { [$0] } ?? []
        let variant = selectedVariant(
            request: request,
            defaultUpperBound: variantCount(for: .retrieval),
            compatibleVariants: [
                .singleChoice: [4, 8],
                .orderedSteps: [5]
            ],
            random: &random
        )
        let interaction: NFExerciseInteraction
        let instructions: String
        let templateSlug: String
        let promptLead: String
        let tags: [String]
        var representations: [NFExerciseRepresentation] = [.prose]

        switch variant {
        case 0 where !request.purpose.isProtectedAssessment:
            interaction = .selfCheck(
                NFSelfCheckResponseSchema(
                    referenceAnswer: fact.expectedAnswer,
                    criteria: [localized("Names the central idea", request: request), localized("Preserves the causal or mathematical relationship", request: request), localized("Does not add unsupported detail", request: request)],
                    asksForReflection: true
                )
            )
            instructions = localized("Recall aloud or in writing, reveal the reference, then self-check honestly.", request: request)
            templateSlug = "free-recall.self-check"
            promptLead = localized("Without looking, freely recall", request: request)
            tags = ["free-recall", "explain-a-concept"]

        case 1:
            interaction = .shortText(
                NFShortTextResponseSchema(
                    expectedAnswer: fact.expectedAnswer,
                    scoringRule: .normalizedExact(acceptedAnswers: [fact.expectedAnswer] + fact.acceptedAlternatives),
                    maximumCharacters: 280
                )
            )
            instructions = localized("Enter a short answer before viewing the reference.", request: request)
            templateSlug = "short-answer"
            promptLead = localized("Answer from memory", request: request)
            tags = ["short-answer", "active-recall"]

        case 2:
            interaction = .shortText(
                NFShortTextResponseSchema(
                    expectedAnswer: fact.expectedAnswer,
                    scoringRule: .normalizedExact(acceptedAnswers: [fact.expectedAnswer] + fact.acceptedAlternatives),
                    maximumCharacters: 280
                )
            )
            instructions = localized("Complete the missing supported relationship; normalized reviewed alternatives are accepted.", request: request)
            templateSlug = "cloze.relationship"
            promptLead = localized("Cloze reconstruction—supply the supported answer for", request: request)
            tags = ["cloze", "relationship-reconstruction"]

        case 3 where !request.purpose.isProtectedAssessment:
            interaction = .selfCheck(
                NFSelfCheckResponseSchema(
                    referenceAnswer: fact.expectedAnswer,
                    criteria: [localized("Defines the central entities", request: request), localized("Explains the supported relationship", request: request), localized("Marks any remaining uncertainty", request: request)],
                    asksForReflection: true
                )
            )
            instructions = localized("Explain the idea in your own words, reveal the supported reference, then rate the match.", request: request)
            templateSlug = "explain-concept.self-check"
            promptLead = localized("Explain the concept behind", request: request)
            tags = ["explain-a-concept", "self-explanation"]

        case 4:
            var options = [
                NFChoiceOption(id: "correct", text: fact.expectedAnswer, accessibilityLabel: nil, distractorCode: nil),
                NFChoiceOption(id: "reverse", text: localized("The reverse relationship always holds without additional conditions.", request: request), accessibilityLabel: nil, distractorCode: "relationship_reversed"),
                NFChoiceOption(id: "none", text: localized("The material defines no relationship between the named ideas.", request: request), accessibilityLabel: nil, distractorCode: "relationship_omitted"),
                NFChoiceOption(id: "scope", text: localized("The statement applies universally beyond every condition in the material.", request: request), accessibilityLabel: nil, distractorCode: "scope_added")
            ]
            random.shuffle(&options)
            interaction = .singleChoice(NFSingleChoiceResponseSchema(options: options, correctOptionID: "correct"))
            instructions = localized("Choose the reconstruction supported by the bounded reference.", request: request)
            templateSlug = "source-supported.recognition"
            promptLead = localized("Which answer is supported for", request: request)
            tags = ["source-supported", "recognition-check"]

        case 5:
            var steps = [
                NFOrderedStep(id: "retrieve", text: localized("Attempt the answer before consulting the reference.", request: request)),
                NFOrderedStep(id: "compare", text: localized("Compare the recalled relationship with the cited answer.", request: request)),
                NFOrderedStep(id: "locate", text: localized("Locate the exact missing, reversed, or unsupported element.", request: request)),
                NFOrderedStep(id: "retry", text: localized("Close the reference and retrieve the corrected relationship once more.", request: request))
            ]
            random.shuffle(&steps)
            interaction = .orderedSteps(
                NFOrderedStepsResponseSchema(
                    steps: steps,
                    correctOrder: ["retrieve", "compare", "locate", "retry"]
                )
            )
            instructions = localized("Arrange the source-grounded reconstruction cycle.", request: request)
            templateSlug = "reconstruction.ordered-cycle"
            promptLead = localized("Plan a derivation-style reconstruction for", request: request)
            tags = ["derivation-ordering", "source-reconstruction"]

        case 6:
            interaction = .shortText(
                NFShortTextResponseSchema(
                    expectedAnswer: fact.expectedAnswer,
                    scoringRule: .normalizedExact(acceptedAnswers: [fact.expectedAnswer] + fact.acceptedAlternatives),
                    maximumCharacters: 280
                )
            )
            instructions = localized("Reconstruct the missing right-hand side from the bounded source relationship.", request: request)
            templateSlug = "equation-reconstruction"
            promptLead = localized("Complete the source-backed relationship for", request: request)
            tags = ["equation-reconstruction", "source-reconstruction"]
            representations = [
                .equation(
                    latex: "E_{source} + C_{stated} \\rightarrow \\square",
                    spokenDescription: localized("Source evidence plus stated conditions leads to a missing supported relationship", request: request)
                )
            ]

        case 7:
            interaction = .shortText(
                NFShortTextResponseSchema(
                    expectedAnswer: fact.expectedAnswer,
                    scoringRule: .normalizedExact(acceptedAnswers: [fact.expectedAnswer] + fact.acceptedAlternatives),
                    maximumCharacters: 280
                )
            )
            instructions = localized("Interpret the compact source figure without reversing the relationship or adding scope.", request: request)
            templateSlug = "figure-interpretation"
            promptLead = localized("Interpret the source figure and state the supported answer for", request: request)
            tags = ["figure-interpretation", "data-figure", "source-reconstruction"]
            representations = [
                .table(
                    headers: [localized("Figure element", request: request), localized("Source-bounded content", request: request)],
                    rows: [
                        [localized("Observation", request: request), fact.statement],
                        [
                            localized("Interpretation rule", request: request),
                            localized("Preserve direction, conditions, and scope", request: request)
                        ]
                    ],
                    accessibilitySummary: localized("A two-row source figure with the observed statement and the rule for interpreting it", request: request)
                )
            ]

        default:
            var options = [
                NFChoiceOption(id: "correct", text: fact.expectedAnswer, accessibilityLabel: nil, distractorCode: nil),
                NFChoiceOption(id: "reverse", text: localized("Return the reversed relationship without checking its conditions.", request: request), accessibilityLabel: nil, distractorCode: "relationship_reversed"),
                NFChoiceOption(id: "none", text: localized("Return no supported relationship.", request: request), accessibilityLabel: nil, distractorCode: "relationship_omitted"),
                NFChoiceOption(id: "scope", text: localized("Return a universal claim beyond the source scope.", request: request), accessibilityLabel: nil, distractorCode: "scope_added")
            ]
            random.shuffle(&options)
            interaction = .singleChoice(NFSingleChoiceResponseSchema(options: options, correctOptionID: "correct"))
            instructions = localized("Trace the pseudocode, then choose the value supported by the cited source.", request: request)
            templateSlug = "code-tracing.source-filter"
            promptLead = localized("Trace the source-support filter for", request: request)
            tags = ["code-tracing", "pseudocode", "source-reconstruction"]
            representations = [
                .code(
                    language: "pseudocode",
                    source: """
                    candidates = [supported, reversed, scope_expanded]
                    for candidate in candidates:
                        if source_supports(candidate):
                            return candidate
                    return unsupported
                    """,
                    accessibilitySummary: localized("Pseudocode returns the first candidate whose direction, conditions, and scope are supported by the source", request: request)
                )
            ]
        }
        let materialPhrase = request.sourceContext.materialTitle.map { localized(" from “\($0)”", request: request) } ?? ""
        let prompt = localized("\(promptLead): \(fact.statement)\(materialPhrase)", request: request)
        return Draft(
            templateSlug: templateSlug,
            title: localized("Retrieval practice", request: request),
            prompt: prompt,
            contextText: suppliedFact == nil
                ? contextualLead(request) + localized(" This fallback uses a bundled, locally verified retrieval contract.", request: request)
                : localized("This prompt uses the bounded, cited fact supplied for your material.", request: request),
            instructions: instructions,
            interaction: interaction,
            difficulty: difficulty(base: 0.38, steps: 2, shift: 0.15),
            skillWeights: ["skill.retrieval": 1],
            strategies: [
                NFExerciseStrategy(
                    id: "strategy.retrieve-before-review",
                    title: localized("Retrieve before reviewing", request: request),
                    summary: localized("Produce the answer from memory, then compare against the supported reference.", request: request),
                    orderedSteps: [localized("Attempt recall", request: request), localized("Reveal the reference", request: request), localized("Name the missing or distorted element", request: request)],
                    whenToUse: localized("Durable learning from notes and source material", request: request)
                )
            ],
            representations: representations,
            citations: citations,
            rubric: exactRubric(localized("Typed response against the reviewed or cited reference", request: request)),
            correctExplanation: localized("The response preserves the central supported relationship.", request: request),
            retryExplanation: localized("Compare the response with the reference and retrieve the missing relationship once more.", request: request),
            decisiveStep: localized("Recall the relationship, not only isolated vocabulary.", request: request),
            hints: [localized("Name the key entities first.", request: request), localized("State how they relate.", request: request)],
            errorExplanations: [
                "text_answer": localized("The response does not match a reviewed accepted answer.", request: request),
                "self_check_partial": localized("Some essential elements were missing; a short immediate retry is useful.", request: request),
                "self_check_not_yet": localized("The reference was not yet retrievable; review it briefly and try again.", request: request)
            ],
            accessibility: standardAccessibility(label: prompt),
            expectedDurationSeconds: 80,
            tags: [
                "retrieval",
                citations.isEmpty ? "bundled" : "source-grounded",
                "knowledge-target.\(fact.id)"
            ] + tags
        )
    }

    /// General retrieval traverses the complete 1,000-question-contract bank. When the
    /// learner has chosen a field, most draws favor that field (and broadly
    /// useful General STEM), while a smaller exploration share keeps the full
    /// bank reachable and prevents a 125-contract preference slice from becoming
    /// a repeat ceiling in longer quizzes.
    private static func bundledRetrievalTarget(
        for preferredField: STEMField,
        random: inout NFFallbackRandom
    ) -> NFRetrievalKnowledgeTarget {
        guard preferredField != .general else {
            return NFBundledRetrievalCatalog.targets[
                random.int(upperBound: NFBundledRetrievalCatalog.targets.count)
            ]
        }

        let roll = random.int(upperBound: 100)
        let candidates: [NFRetrievalKnowledgeTarget]
        if roll < 60 {
            candidates = NFBundledRetrievalCatalog.targets(for: preferredField)
        } else if roll < 80 {
            candidates = NFBundledRetrievalCatalog.targets(for: .general)
        } else {
            candidates = NFBundledRetrievalCatalog.targets
        }
        return candidates[random.int(upperBound: candidates.count)]
    }

    private static func transferDraft(
        request: NFExerciseGenerationRequest,
        random: inout NFFallbackRandom
    ) -> Draft {
        if let brief = request.sourceContext.transferBrief {
            return structuredTransferDraft(request: request, brief: brief, random: &random)
        }
        let profile = fieldProfile(request.sourceContext.primaryField, request: request)
        let variant = selectedVariant(
            request: request,
            defaultUpperBound: variantCount(for: .transfer),
            compatibleVariants: [
                .numericEntry: [2, 5],
                .singleChoice: [3, 6],
                .orderedSteps: [0],
                .claimEvidence: [4]
            ],
            random: &random
        )
        let interaction: NFExerciseInteraction
        let instructions: String
        let templateSlug: String
        let prompt: String
        let representations: [NFExerciseRepresentation]
        let correctExplanation: String
        let decisiveStep: String
        let tags: [String]
        let errorExplanations: [String: String]
        let rubric: NFExerciseRubric
        let locale = NFAppLocalization.locale(identifier: request.localeIdentifier)
        let origin = request.sourceContext.transferOriginField?.localizedTitle(locale: locale)
            ?? localized("a familiar worked example", request: request)

        switch variant {
        case 0:
            var steps = [
                NFOrderedStep(id: "identify", text: localized("Identify the target quantity and available evidence.", request: request)),
                NFOrderedStep(id: "represent", text: localized("Translate the context into a diagram, equation, or state model.", request: request)),
                NFOrderedStep(id: "solve", text: localized("Apply the selected relationship or rule.", request: request)),
                NFOrderedStep(id: "check", text: localized("Check units, constraints, and whether the conclusion fits the evidence.", request: request))
            ]
            random.shuffle(&steps)
            interaction = .orderedSteps(
                NFOrderedStepsResponseSchema(
                    steps: steps,
                    correctOrder: ["identify", "represent", "solve", "check"]
                )
            )
            instructions = localized("Arrange the steps into a defensible problem-solving sequence.", request: request)
            templateSlug = "cross-context.sequence"
            prompt = localized("You are adapting \(origin) to a new \(profile.entity) problem. What is the defensible transfer process?", request: request)
            representations = [.prose]
            correctExplanation = localized("Valid transfer identifies the target, maps its structure, solves, and then rechecks assumptions and units.", request: request)
            decisiveStep = localized("Represent the target structure before applying the familiar method.", request: request)
            tags = ["surface-context", "problem-solving-sequence", "response-shift"]
            errorExplanations = ["ordered_steps_sequence": localized("Representation and solution should follow problem identification, with validation last.", request: request)]
            rubric = exactRubric(localized("Problem-solving sequence", request: request))

        case 1:
            var options = [
                NFChoiceOption(id: "a", text: localized("Preserve the underlying quantities while changing their labels.", request: request), accessibilityLabel: nil, distractorCode: nil),
                NFChoiceOption(id: "b", text: localized("Assume the new context uses the same units without checking.", request: request), accessibilityLabel: nil, distractorCode: "transfer_units"),
                NFChoiceOption(id: "c", text: localized("Verify that the original constraints still hold in the new field.", request: request), accessibilityLabel: nil, distractorCode: nil),
                NFChoiceOption(id: "d", text: localized("Copy the previous conclusion even if the evidence structure changes.", request: request), accessibilityLabel: nil, distractorCode: "transfer_structure")
            ]
            random.shuffle(&options)
            interaction = .multipleChoice(
                NFMultipleChoiceResponseSchema(
                    options: options,
                    correctOptionIDs: ["a", "c"],
                    minimumSelections: 1,
                    maximumSelections: 4
                )
            )
            instructions = localized("Select every action that preserves valid reasoning during transfer.", request: request)
            templateSlug = "cross-context.conditions"
            prompt = localized("You are adapting \(origin) to a new \(profile.entity) problem. Which actions preserve valid reasoning?", request: request)
            representations = [.prose]
            correctExplanation = localized("Valid transfer preserves the underlying structure and rechecks assumptions, units, and constraints in the target context.", request: request)
            decisiveStep = localized("Map relationships—not conclusions—and check that the target problem satisfies the same constraints.", request: request)
            tags = ["surface-context", "constraint-check", "multiple-response"]
            errorExplanations = ["multiple_choice_selection": localized("At least one selected action copies an unchecked assumption or misses a required validation.", request: request)]
            rubric = weightedRubric([
                ("mapping", localized("Preserve the underlying quantities", request: request), 0.5),
                ("validation", localized("Recheck constraints in the target context", request: request), 0.5)
            ])

        case 2:
            let rate = 2 + random.int(upperBound: 50)
            let duration = 5 + random.int(upperBound: 40)
            let answer = Double(rate * duration)
            templateSlug = "field-shift.rate-product"
            prompt = localized("A familiar rate × time relation is transferred into a \(profile.entity) context: \(rate) \(profile.countUnit) per minute for \(duration) minutes. What total follows?", request: request)
            instructions = localized("Enter the exact total with its unit.", request: request)
            interaction = numericInteraction(answer: answer, tolerance: .absolute(0), unit: profile.countUnit)
            representations = [
                .table(
                    headers: [localized("Quantity", request: request), localized("Target-context value", request: request)],
                    rows: [[localized("Rate", request: request), localized("\(rate) \(profile.countUnit)/min", request: request)], [localized("Duration", request: request), localized("\(duration) min", request: request)]],
                    accessibilitySummary: localized("The rate is \(rate) \(profile.countUnit) per minute for \(duration) minutes.", request: request)
                ),
                .equation(latex: "Q=r t", spokenDescription: localized("Total equals rate times duration", request: request))
            ]
            correctExplanation = localized("The surface nouns changed, but the constant-rate accumulation structure and unit cancellation remain the same.", request: request)
            decisiveStep = localized("Verify the target really has a constant rate, then multiply rate by duration.", request: request)
            tags = ["field-transfer", "surface-context", "table-to-equation", "numeric-response"]
            errorExplanations = [
                "numeric_value": localized("The transferred rate relationship was applied incorrectly.", request: request),
                "unit_missing": localized("The target total retains the counted-item unit.", request: request),
                "unit_mismatch": localized("Use the target context’s count unit.", request: request)
            ]
            rubric = exactRubric(localized("Transferred quantitative relation", request: request))

        case 3:
            let factor = 2 + random.int(upperBound: 4)
            var options = [
                NFChoiceOption(id: "correct", text: localized("y = \(factor)x", request: request), accessibilityLabel: nil, distractorCode: nil),
                NFChoiceOption(id: "inverse", text: localized("y = \(factor)/x", request: request), accessibilityLabel: nil, distractorCode: "representation_structure"),
                NFChoiceOption(id: "offset", text: localized("y = x + \(factor)", request: request), accessibilityLabel: nil, distractorCode: "representation_structure"),
                NFChoiceOption(id: "square", text: localized("y = \(factor)x²", request: request), accessibilityLabel: nil, distractorCode: "representation_structure")
            ]
            random.shuffle(&options)
            templateSlug = "representation.table-to-equation"
            prompt = localized("Which equation preserves the relationship in the table when the representation changes?", request: request)
            instructions = localized("Choose the equation that matches every row.", request: request)
            interaction = .singleChoice(NFSingleChoiceResponseSchema(options: options, correctOptionID: "correct"))
            representations = [.table(
                headers: ["x", "y"],
                rows: [["1", localized("\(factor)", request: request)], ["2", localized("\(2 * factor)", request: request)], ["4", localized("\(4 * factor)", request: request)]],
                accessibilitySummary: localized("As x takes values one, two, and four, y is always \(factor) times x.", request: request)
            )]
            correctExplanation = localized("The ratio y divided by x remains \(factor) in every row, so the invariant relationship is y equals \(factor) times x.", request: request)
            decisiveStep = localized("Test each candidate equation against more than one row.", request: request)
            tags = ["representation-shift", "table-to-equation", "scaling"]
            errorExplanations = ["representation_structure": localized("This equation matches neither the constant ratio nor every table row.", request: request)]
            rubric = exactRubric(localized("Representation-equivalent relationship", request: request))

        case 4:
            let claims = [
                NFClaimOption(id: "claim.feedback", text: localized("Both systems contain a feedback relation in which output changes later input.", request: request)),
                NFClaimOption(id: "claim.limit", text: localized("Matching labels alone is insufficient; edge direction and delay must also match.", request: request))
            ]
            let evidence = [
                NFEvidenceOption(id: "evidence.engineering", text: localized("Engineering model: sensor output adjusts the controller’s next input.", request: request), citationID: nil),
                NFEvidenceOption(id: "evidence.life", text: localized("Physiology model: measured output alters the next regulatory signal.", request: request), citationID: nil),
                NFEvidenceOption(id: "evidence.structure", text: localized("Both graphs have output → next-input edges with one-step delay.", request: request), citationID: nil),
                NFEvidenceOption(id: "evidence.labels", text: localized("The domain nouns differ and do not determine graph equivalence.", request: request), citationID: nil)
            ]
            templateSlug = "field-shift.causal-structure"
            prompt = localized("Map the common structure between a feedback controller and a regulatory system.", request: request)
            instructions = localized("Attach the evidence that supports each structural claim.", request: request)
            interaction = .claimEvidence(
                NFClaimEvidenceResponseSchema(
                    claims: claims,
                    evidence: evidence,
                    correctPairs: [
                        NFClaimEvidencePair(claimID: "claim.feedback", evidenceIDs: ["evidence.engineering", "evidence.life", "evidence.structure"]),
                        NFClaimEvidencePair(claimID: "claim.limit", evidenceIDs: ["evidence.structure", "evidence.labels"])
                    ]
                )
            )
            representations = [.prose]
            correctExplanation = localized("The common directed, delayed feedback structure supports transfer across fields; surface vocabulary alone does not.", request: request)
            decisiveStep = localized("Compare graph roles and edge direction rather than domain nouns.", request: request)
            tags = ["field-transfer", "causal-structure", "feedback", "claim-evidence"]
            errorExplanations = ["claim_evidence_support": localized("The evidence mapping must preserve graph structure and distinguish it from surface labels.", request: request)]
            rubric = weightedRubric([
                ("structure", localized("Map the shared feedback structure", request: request), 0.7),
                ("limit", localized("Preserve mapping limits", request: request), 0.3)
            ])

        case 5:
            let baseline = 3 + random.int(upperBound: 6)
            let answer = Double(baseline * 4)
            templateSlug = "interacting-variables.ratio"
            prompt = localized("A target quantity equals amount ÷ volume and initially equals \(baseline). If amount doubles while volume halves, what is the new value?", request: request)
            instructions = localized("Enter the transformed value in relative units.", request: request)
            interaction = numericInteraction(
                answer: answer,
                tolerance: .absolute(0),
                unit: localized("relative units", request: request),
                acceptedUnits: [localized("units", request: request)]
            )
            representations = [.equation(latex: "q=\\frac{A}{V}", spokenDescription: localized("Quantity equals amount divided by volume", request: request))]
            correctExplanation = localized("Doubling the numerator contributes a factor of two and halving the denominator contributes another factor of two, for a fourfold result.", request: request)
            decisiveStep = localized("Transform numerator and denominator independently before combining their factors.", request: request)
            tags = ["interacting-variables", "ratio", "multi-variable-transfer"]
            errorExplanations = [
                "numeric_value": localized("The two simultaneous changes combine multiplicatively, not additively.", request: request),
                "unit_missing": localized("Keep the target’s relative unit attached.", request: request),
                "unit_mismatch": localized("Use the relative unit stated in the target problem.", request: request)
            ]
            rubric = exactRubric(localized("Constrained multi-variable transformation", request: request))

        default:
            var options = [
                NFChoiceOption(id: "correct", text: localized("Test whether the target remains linear over the relevant range before using the source model.", request: request), accessibilityLabel: nil, distractorCode: nil),
                NFChoiceOption(id: "copy", text: localized("Copy the source conclusion because both contexts use the word ‘response.’", request: request), accessibilityLabel: nil, distractorCode: "surface_transfer"),
                NFChoiceOption(id: "ignore", text: localized("Ignore saturation because the source example had none.", request: request), accessibilityLabel: nil, distractorCode: "constraint_omitted"),
                NFChoiceOption(id: "units", text: localized("Keep the numeric coefficients even if the target units differ.", request: request), accessibilityLabel: nil, distractorCode: "transfer_units")
            ]
            random.shuffle(&options)
            templateSlug = "constraint-shift.linearity"
            prompt = localized("A linear source model is proposed for a target system that may saturate. What check is decisive before transfer?", request: request)
            instructions = localized("Choose the target-specific validation.", request: request)
            interaction = .singleChoice(NFSingleChoiceResponseSchema(options: options, correctOptionID: "correct"))
            representations = [.prose]
            correctExplanation = localized("A method that depends on linearity transfers only where the target relationship is sufficiently linear.", request: request)
            decisiveStep = localized("Revalidate the structural assumption that makes the source method valid.", request: request)
            tags = ["constraint-shift", "counterexample", "surface-context", "model-check"]
            errorExplanations = [
                "surface_transfer": localized("Shared vocabulary does not establish shared mathematical structure.", request: request),
                "constraint_omitted": localized("Potential saturation directly threatens the linear-model assumption.", request: request),
                "transfer_units": localized("Coefficients cannot be copied before target units are reconciled.", request: request)
            ]
            rubric = exactRubric(localized("Target-specific transfer check", request: request))
        }

        let activityTitle = switch request.purpose {
        case .appliedTransfer: localized("Applied transfer", request: request)
        case .nearTransfer: localized("Near transfer", request: request)
        default: localized("Transfer practice", request: request)
        }

        return Draft(
            templateSlug: templateSlug,
            title: activityTitle,
            prompt: prompt,
            contextText: contextualLead(request) + localized(" Surface structure may change; the relevant constraints must be checked again.", request: request),
            instructions: instructions,
            interaction: interaction,
            difficulty: difficulty(base: 0.58 + Double(variant % 4) * 0.045, steps: 3 + variant / 2, shift: 0.65 + Double(variant % 3) * 0.1),
            skillWeights: ["skill.transfer": 0.7, "skill.logicDebugging": 0.15, "skill.scientificReasoning": 0.15],
            strategies: [
                NFExerciseStrategy(
                    id: "strategy.transfer.structure",
                    title: localized("Transfer structure, then revalidate", request: request),
                    summary: localized("Map quantities and constraints rather than copying surface wording or conclusions.", request: request),
                    orderedSteps: [localized("Extract the source structure", request: request), localized("Map it to the target", request: request), localized("Solve", request: request), localized("Recheck target-specific constraints", request: request)],
                    whenToUse: localized("Applying a familiar method in a different field or representation", request: request)
                )
            ],
            representations: representations,
            citations: [],
            rubric: rubric,
            correctExplanation: correctExplanation,
            retryExplanation: localized("Identify what is structurally invariant and what must be revalidated after the context changes.", request: request),
            decisiveStep: decisiveStep,
            hints: [localized("Separate surface labels from underlying relations.", request: request), localized("Ask which assumptions could fail in the new context.", request: request)],
            errorExplanations: errorExplanations,
            accessibility: standardAccessibility(label: prompt),
            expectedDurationSeconds: 95 + variant * 5,
            tags: ["transfer", "problem-solving"] + tags
        )
    }

    /// Mission-authored fallback content. The scheduler's selected challenge,
    /// labs, skills, and changed dimensions all participate in both the visible
    /// task and the deterministic item identity through `sourceContext`.
    private static func structuredTransferDraft(
        request: NFExerciseGenerationRequest,
        brief: NFExerciseTransferBrief,
        random: inout NFFallbackRandom
    ) -> Draft {
        let selectedLabs = Array(brief.labs.prefix(2))
        let locale = NFAppLocalization.locale(identifier: request.localeIdentifier)
        let firstLab = selectedLabs.first?.localizedShortTitle(locale: locale)
            ?? localized("a familiar practice area", request: request)
        let secondLab = selectedLabs.dropFirst().first?.localizedShortTitle(locale: locale)
            ?? localized("another practice area", request: request)
        let dimensions = localizedDimensionSummary(brief.requiredDimensions, request: request)
        let missionTitle = brief.kind.localizedTitle(locale: locale)
        let missionLead = localized("Mission: \(missionTitle). Combine \(firstLab) with \(secondLab); deliberately change \(dimensions).", request: request)
        // A weekly mission is one coherent goal, but its questions must not be
        // number-swapped copies of one interaction. Lead with the selected
        // challenge, then rotate through the other reviewed transfer mechanics.
        let challengeSequence = [brief.kind] + NFTransferChallengeKind.allCases.filter { $0 != brief.kind }
        let challengeKind = challengeSequence[request.index % challengeSequence.count]
        let weights = structuredTransferSkillWeights(brief)
        let interaction: NFExerciseInteraction
        let instructions: String
        let templateSlug: String
        let prompt: String
        let representations: [NFExerciseRepresentation]
        let correctExplanation: String
        let decisiveStep: String
        let errorExplanations: [String: String]
        let rubric: NFExerciseRubric

        switch challengeKind {
        case .figureAndClaimAudit:
            let claims = [
                NFClaimOption(
                    id: "claim.pattern",
                    text: localized("The changed output is associated with the changed input in both representations.", request: request)
                ),
                NFClaimOption(
                    id: "claim.limit",
                    text: localized("The paired observations alone do not establish that the input caused the output change.", request: request)
                )
            ]
            let evidence = [
                NFEvidenceOption(id: "evidence.first", text: localized("\(firstLab) view: input 2 maps to output 6, while input 4 maps to output 12.", request: request), citationID: nil),
                NFEvidenceOption(id: "evidence.second", text: localized("\(secondLab) view: the plotted points are (2, 6) and (4, 12).", request: request), citationID: nil),
                NFEvidenceOption(id: "evidence.structure", text: localized("Both views preserve the same input-output pairs despite the representation change.", request: request), citationID: nil),
                NFEvidenceOption(id: "evidence.design", text: localized("No intervention or randomized comparison is described.", request: request), citationID: nil)
            ]
            interaction = .claimEvidence(
                NFClaimEvidenceResponseSchema(
                    claims: claims,
                    evidence: evidence,
                    correctPairs: [
                        NFClaimEvidencePair(claimID: "claim.pattern", evidenceIDs: ["evidence.first", "evidence.second", "evidence.structure"]),
                        NFClaimEvidencePair(claimID: "claim.limit", evidenceIDs: ["evidence.design"])
                    ]
                )
            )
            instructions = localized("Attach only the evidence that directly supports each claim.", request: request)
            templateSlug = "mission.figure-claim-audit"
            prompt = localized("Audit the transferred figure and claim across \(firstLab) and \(secondLab). Which evidence supports the pattern, and which evidence limits the causal claim?", request: request)
            representations = [.table(
                headers: [localized("Input", request: request), localized("\(firstLab) output", request: request), localized("\(secondLab) plotted y", request: request)],
                rows: [["2", "6", "6"], ["4", "12", "12"]],
                accessibilitySummary: localized("Both representations contain the pairs two to six and four to twelve.", request: request)
            )]
            correctExplanation = localized("The values support a shared association across representations, while the absent intervention limits causal inference.", request: request)
            decisiveStep = localized("Separate evidence for the observed pattern from evidence about whether causation was tested.", request: request)
            errorExplanations = ["claim_evidence_support": localized("Match each evidence statement to the exact scope of its claim; association and causation require different support.", request: request)]
            rubric = weightedRubric([
                ("pattern", localized("Map the shared figure structure", request: request), 0.6),
                ("limit", localized("Preserve the causal limitation", request: request), 0.4)
            ])

        case .numericalSimulationDebug:
            let initial = 3 + random.int(upperBound: 5)
            let multiplier = 2 + random.int(upperBound: 3)
            let increment = 1 + random.int(upperBound: 3)
            let expected = initial * multiplier + increment
            var options = [
                NFChoiceOption(id: "correct", text: localized("\(expected); multiply first, then apply the increment once.", request: request), accessibilityLabel: nil, distractorCode: nil),
                NFChoiceOption(id: "precedence", text: localized("\((initial + increment) * multiplier); the increment was applied before the transition.", request: request), accessibilityLabel: nil, distractorCode: "simulation_precedence"),
                NFChoiceOption(id: "omitted", text: localized("\(initial * multiplier); the increment was omitted.", request: request), accessibilityLabel: nil, distractorCode: "simulation_omission"),
                NFChoiceOption(id: "additive", text: localized("\(initial + multiplier + increment); the multiplicative transition was replaced by addition.", request: request), accessibilityLabel: nil, distractorCode: "simulation_operator")
            ]
            random.shuffle(&options)
            interaction = .singleChoice(NFSingleChoiceResponseSchema(options: options, correctOptionID: "correct"))
            instructions = localized("Choose the correct next state and the diagnosis that justifies it.", request: request)
            templateSlug = "mission.numerical-simulation-debug"
            prompt = localized("A \(firstLab) state model is implemented in a \(secondLab) simulation. Starting at \(initial), the specification says ‘multiply by \(multiplier), then add \(increment) once.’ Which trace is correct?", request: request)
            representations = [
                .equation(latex: "s_{t+1}=\(multiplier)s_t+\(increment)", spokenDescription: localized("Next state equals \(multiplier) times current state plus \(increment)", request: request)),
                .code(language: "pseudocode", source: "next = current * \(multiplier) + \(increment)", accessibilitySummary: localized("Multiply current by \(multiplier), then add \(increment).", request: request))
            ]
            correctExplanation = localized("The transition's multiplication is evaluated before its one-time increment, giving \(expected).", request: request)
            decisiveStep = localized("Translate the specification into one state-transition equation before tracing the implementation.", request: request)
            errorExplanations = [
                "simulation_precedence": localized("The increment belongs after the multiplicative transition.", request: request),
                "simulation_omission": localized("The specified increment must be applied exactly once.", request: request),
                "simulation_operator": localized("The transition scales the prior state; it is not wholly additive.", request: request)
            ]
            rubric = exactRubric(localized("Correct simulation state and diagnosis", request: request))

        case .causalStructureComparison:
            var options = [
                NFChoiceOption(id: "correct", text: localized("Map directed roles and delays, then test whether the target has the same intervention-response structure.", request: request), accessibilityLabel: nil, distractorCode: nil),
                NFChoiceOption(id: "labels", text: localized("Treat matching nouns in the two fields as evidence that their causal structures match.", request: request), accessibilityLabel: nil, distractorCode: "surface_transfer"),
                NFChoiceOption(id: "correlation", text: localized("Treat correlation in either field as sufficient proof of the same causal edge.", request: request), accessibilityLabel: nil, distractorCode: "causal_overreach"),
                NFChoiceOption(id: "direction", text: localized("Ignore edge direction as long as both systems contain the same number of variables.", request: request), accessibilityLabel: nil, distractorCode: "direction_omitted")
            ]
            random.shuffle(&options)
            interaction = .singleChoice(NFSingleChoiceResponseSchema(options: options, correctOptionID: "correct"))
            instructions = localized("Choose the comparison that preserves causal meaning across fields.", request: request)
            templateSlug = "mission.causal-structure-comparison"
            prompt = localized("A directed relation from input → state → delayed output is proposed as a bridge from \(firstLab) to \(secondLab). Which comparison makes that transfer defensible?", request: request)
            representations = [.logicState(NFLogicRepresentationMetadata(
                variables: [
                    "input": firstLab,
                    "state": localized("shared mediator", request: request),
                    "output": secondLab
                ],
                transitions: [
                    NFLogicTransition(
                        id: "input-state",
                        condition: localized("input changes", request: request),
                        mutation: localized("state updates", request: request)
                    ),
                    NFLogicTransition(
                        id: "state-output",
                        condition: localized("one step passes", request: request),
                        mutation: localized("output responds", request: request)
                    )
                ],
                invariants: [
                    "direction": localized("input precedes state; state precedes output", request: request)
                ],
                traceLanguage: localized("causal graph", request: request)
            ))]
            correctExplanation = localized("Causal transfer requires matching directed roles, timing, and intervention-response constraints—not vocabulary or correlation alone.", request: request)
            decisiveStep = localized("Compare the directed, delayed structure and the evidence that identifies each edge.", request: request)
            errorExplanations = [
                "surface_transfer": localized("Shared words do not establish shared causal roles.", request: request),
                "causal_overreach": localized("Correlation alone does not identify the proposed causal edge.", request: request),
                "direction_omitted": localized("Reversing an edge changes the causal claim.", request: request)
            ]
            rubric = exactRubric(localized("Causally valid structural comparison", request: request))

        case .abstractReconstruction:
            var steps = [
                NFOrderedStep(id: "extract", text: localized("Extract the invariant relationship from the \(firstLab) example.", request: request)),
                NFOrderedStep(id: "strip", text: localized("Remove labels and encode the relationship as an abstract rule.", request: request)),
                NFOrderedStep(id: "map", text: localized("Map each abstract role to the \(secondLab) target.", request: request)),
                NFOrderedStep(id: "test", text: localized("Test the mapped rule against a target-specific constraint or counterexample.", request: request))
            ]
            random.shuffle(&steps)
            interaction = .orderedSteps(NFOrderedStepsResponseSchema(
                steps: steps,
                correctOrder: ["extract", "strip", "map", "test"]
            ))
            instructions = localized("Arrange the reconstruction steps in a defensible order.", request: request)
            templateSlug = "mission.abstract-reconstruction"
            prompt = localized("Reconstruct a solution pattern from \(firstLab) for use in \(secondLab) after the original surface cues are removed. What sequence preserves valid transfer?", request: request)
            representations = [.prose]
            correctExplanation = localized("A reliable reconstruction extracts structure, abstracts it, maps roles, and only then tests target-specific validity.", request: request)
            decisiveStep = localized("Form the label-free rule before assigning target-domain roles.", request: request)
            errorExplanations = ["ordered_steps_sequence": localized("Abstraction must precede target mapping, and target validation must come after the mapping exists.", request: request)]
            rubric = exactRubric(localized("Abstract reconstruction sequence", request: request))

        case .multiRepresentationTransform:
            let factor = 2 + random.int(upperBound: 4)
            let intercept = 1 + random.int(upperBound: 4)
            var options = [
                NFChoiceOption(id: "correct", text: localized("y = \(factor)x + \(intercept)", request: request), accessibilityLabel: nil, distractorCode: nil),
                NFChoiceOption(id: "missing", text: localized("y = \(factor)x", request: request), accessibilityLabel: nil, distractorCode: "representation_intercept"),
                NFChoiceOption(id: "inverse", text: localized("y = x/\(factor) + \(intercept)", request: request), accessibilityLabel: nil, distractorCode: "representation_slope"),
                NFChoiceOption(id: "swapped", text: localized("y = \(intercept)x + \(factor)", request: request), accessibilityLabel: nil, distractorCode: "representation_roles")
            ]
            random.shuffle(&options)
            interaction = .singleChoice(NFSingleChoiceResponseSchema(options: options, correctOptionID: "correct"))
            instructions = localized("Choose the equation that preserves every row and the stated transformation.", request: request)
            templateSlug = "mission.multi-representation-transform"
            prompt = localized("Transform the \(firstLab) table into an equation that can be used in the \(secondLab) representation. Which equation preserves the relation?", request: request)
            representations = [.table(
                headers: ["x", "y"],
                rows: [
                    ["0", "\(intercept)"],
                    ["1", "\(factor + intercept)"],
                    ["3", "\(3 * factor + intercept)"]
                ],
                accessibilitySummary: localized("At x zero, y is \(intercept); each increase of one in x raises y by \(factor).", request: request)
            )]
            correctExplanation = localized("The table has intercept \(intercept) and constant change \(factor), so y equals \(factor)x plus \(intercept).", request: request)
            decisiveStep = localized("Identify the invariant rate and the x-equals-zero value separately.", request: request)
            errorExplanations = [
                "representation_intercept": localized("The nonzero value at x equals zero must be retained.", request: request),
                "representation_slope": localized("The table increases by \(factor) per unit x, not its reciprocal.", request: request),
                "representation_roles": localized("Slope and intercept play different roles and cannot be exchanged.", request: request)
            ]
            rubric = exactRubric(localized("Equivalent multi-representation relation", request: request))
        }

        let dimensionTags = brief.requiredDimensions.map { "transfer-dimension.\($0)" }
        let labTags = selectedLabs.map { "transfer-lab.\($0.rawValue)" }
        return Draft(
            templateSlug: templateSlug,
            title: missionTitle,
            prompt: prompt,
            contextText: missionLead,
            instructions: instructions,
            interaction: interaction,
            difficulty: difficulty(base: 0.72, steps: 4, shift: 0.9),
            skillWeights: weights,
            strategies: [
                NFExerciseStrategy(
                    id: "strategy.transfer.mission-structure",
                    title: localized("Map, transform, revalidate", request: request),
                    summary: localized("Preserve the selected skills' shared structure while deliberately changing the mission dimensions.", request: request),
                    orderedSteps: [localized("Extract the first skill's structure", request: request), localized("Map it to the second skill", request: request), localized("Apply the requested representation or context change", request: request), localized("Revalidate constraints", request: request)],
                    whenToUse: localized("Cross-skill transfer missions", request: request)
                )
            ],
            representations: representations,
            citations: [],
            rubric: rubric,
            correctExplanation: correctExplanation,
            retryExplanation: localized("Return to the relation shared by \(firstLab) and \(secondLab), then check the changed \(dimensions) explicitly.", request: request),
            decisiveStep: decisiveStep,
            hints: [localized("Name the invariant before changing its surface form.", request: request), localized("Check each requested transfer dimension against the target.", request: request)],
            errorExplanations: errorExplanations,
            accessibility: standardAccessibility(label: localized("\(missionLead) \(prompt)", request: request)),
            expectedDurationSeconds: 115,
            tags: [
                "transfer",
                "weekly-mission",
                "mission.\(brief.kind.rawValue)",
                "challenge.\(challengeKind.rawValue)"
            ] + labTags + dimensionTags
        )
    }

    private static func structuredTransferSkillWeights(
        _ brief: NFExerciseTransferBrief
    ) -> [String: Double] {
        let selectedSkills = Array(brief.skillIDs.prefix(2)).reduce(into: [String]()) { result, skill in
            guard !skill.isEmpty, !result.contains(skill) else { return }
            result.append(skill)
        }
        guard !selectedSkills.isEmpty else { return ["skill.transfer": 1] }
        var weights = ["skill.transfer": 0.4]
        let selectedShare = 0.6 / Double(selectedSkills.count)
        for skill in selectedSkills {
            weights[skill, default: 0] += selectedShare
        }
        return weights
    }

    // MARK: - Shared construction

    private static func localized(
        _ value: String.LocalizationValue,
        request: NFExerciseGenerationRequest
    ) -> String {
        NFAppLocalization.localized(
            value,
            locale: NFAppLocalization.locale(identifier: request.localeIdentifier)
        )
    }

    private static func localizedDimensionSummary(
        _ dimensions: [String],
        request: NFExerciseGenerationRequest
    ) -> String {
        guard !dimensions.isEmpty else { return localized("context", request: request) }
        return dimensions.map { dimension in
            switch dimension {
            case "representation": localized("representation", request: request)
            case "field": localized("field", request: request)
            case "response_type": localized("response type", request: request)
            case "delay": localized("delay", request: request)
            case "stimulus_category": localized("stimulus category", request: request)
            default: dimension.replacingOccurrences(of: "_", with: " ")
            }
        }.joined(separator: localized(", ", request: request))
    }

    private struct Draft {
        let templateSlug: String
        let title: String
        let prompt: String
        let contextText: String?
        let instructions: String
        let interaction: NFExerciseInteraction
        let difficulty: NFExerciseDifficulty
        let skillWeights: [String: Double]
        let strategies: [NFExerciseStrategy]
        let representations: [NFExerciseRepresentation]
        let citations: [NFExerciseCitation]
        let rubric: NFExerciseRubric
        let correctExplanation: String
        let retryExplanation: String
        let decisiveStep: String
        let hints: [String]
        let errorExplanations: [String: String]
        let accessibility: NFExerciseAccessibility
        let expectedDurationSeconds: Int
        let tags: [String]
    }

    private struct FieldProfile {
        let entity: String
        let countUnit: String
    }

    private static func fieldProfile(
        _ field: STEMField,
        request: NFExerciseGenerationRequest
    ) -> FieldProfile {
        switch field {
        case .general: FieldProfile(entity: localized("measurement", request: request), countUnit: localized("events", request: request))
        case .mathematics: FieldProfile(entity: localized("proof checking", request: request), countUnit: localized("cases", request: request))
        case .physics: FieldProfile(entity: localized("detector", request: request), countUnit: localized("events", request: request))
        case .computing: FieldProfile(entity: localized("data processing", request: request), countUnit: localized("records", request: request))
        case .engineering: FieldProfile(entity: localized("production", request: request), countUnit: localized("components", request: request))
        case .lifeSciences: FieldProfile(entity: localized("cell culture", request: request), countUnit: localized("observations", request: request))
        case .chemistry: FieldProfile(entity: localized("reaction monitoring", request: request), countUnit: localized("samples", request: request))
        case .dataScience: FieldProfile(entity: localized("model evaluation", request: request), countUnit: localized("records", request: request))
        }
    }

    private static func genericFact(
        for field: STEMField,
        request: NFExerciseGenerationRequest
    ) -> NFExerciseGroundingFact {
        switch field {
        case .mathematics:
            NFExerciseGroundingFact(
                id: "fact.math.contrapositive",
                statement: localized("What is the contrapositive of ‘if P, then Q’?", request: request),
                expectedAnswer: localized("If not Q, then not P", request: request),
                acceptedAlternatives: [localized("not Q implies not P", request: request)],
                citationIDs: []
            )
        case .physics:
            NFExerciseGroundingFact(
                id: "fact.physics.acceleration",
                statement: localized("How does net force relate to acceleration when mass is fixed?", request: request),
                expectedAnswer: localized("Acceleration is proportional to net force", request: request),
                acceptedAlternatives: [localized("greater net force produces proportionally greater acceleration", request: request)],
                citationIDs: []
            )
        case .computing:
            NFExerciseGroundingFact(
                id: "fact.computing.invariant",
                statement: localized("What must a loop invariant do?", request: request),
                expectedAnswer: localized("Remain true before and after every iteration", request: request),
                acceptedAlternatives: [localized("hold before and after each iteration", request: request)],
                citationIDs: []
            )
        case .engineering:
            NFExerciseGroundingFact(
                id: "fact.engineering.factor",
                statement: localized("What does a factor of safety compare?", request: request),
                expectedAnswer: localized("Failure capacity to expected operating load", request: request),
                acceptedAlternatives: [localized("strength to applied load", request: request)],
                citationIDs: []
            )
        case .lifeSciences:
            NFExerciseGroundingFact(
                id: "fact.bio.control",
                statement: localized("Why include a control group in an experiment?", request: request),
                expectedAnswer: localized("To provide a comparison for the treatment effect", request: request),
                acceptedAlternatives: [localized("provide a baseline comparison", request: request)],
                citationIDs: []
            )
        case .chemistry:
            NFExerciseGroundingFact(
                id: "fact.chemistry.catalyst",
                statement: localized("How does a catalyst affect activation energy?", request: request),
                expectedAnswer: localized("It lowers the activation energy", request: request),
                acceptedAlternatives: [localized("lowers activation energy", request: request)],
                citationIDs: []
            )
        case .dataScience:
            NFExerciseGroundingFact(
                id: "fact.data.holdout",
                statement: localized("Why keep a test set separate from model fitting?", request: request),
                expectedAnswer: localized("To estimate performance on unseen data", request: request),
                acceptedAlternatives: [localized("measure generalization to unseen data", request: request)],
                citationIDs: []
            )
        case .general:
            NFExerciseGroundingFact(
                id: "fact.general.proportion",
                statement: localized("What is a proportion?", request: request),
                expectedAnswer: localized("A part divided by the whole", request: request),
                acceptedAlternatives: [localized("the ratio of a part to the whole", request: request)],
                citationIDs: []
            )
        }
    }

    private static func citation(
        for fact: NFExerciseGroundingFact,
        context: NFExerciseSourceContext,
        request: NFExerciseGenerationRequest
    ) -> NFExerciseCitation? {
        guard let documentID = context.sourceDocumentIDs.first else { return nil }
        let declaredChunkID = fact.citationIDs.first(where: { context.sourceChunkIDs.contains($0) })
        let chunkID = declaredChunkID ?? context.sourceChunkIDs.first
        let locator: NFExerciseCitationLocator = chunkID.map(NFExerciseCitationLocator.chunk)
            ?? .section(localized("Referenced material", request: request))
        return NFExerciseCitation(
            id: "citation.\(fact.id)",
            documentID: documentID,
            sourceChunkID: chunkID,
            title: context.materialTitle ?? localized("Imported material", request: request),
            locator: locator,
            supportDescription: localized("Supports the reviewed expected answer for this retrieval item.", request: request),
            excerptDigest: nil
        )
    }

    private static func numericInteraction(
        answer: Double,
        tolerance: NFNumericTolerance,
        unit: String?,
        acceptedUnits: [String] = [],
        precision: Int = 2,
        authoritativeValue: NFExactNumber? = nil
    ) -> NFExerciseInteraction {
        .numeric(
            NFNumericResponseSchema(
                answer: NFNumericAnswer(
                    value: answer,
                    tolerance: tolerance,
                    canonicalUnit: unit,
                    acceptedUnits: acceptedUnits,
                    unitRequired: unit != nil,
                    displayPrecision: precision,
                    authoritativeValue: authoritativeValue
                ),
                placeholder: unit.map {
                    NFAppLocalization.localized("Value in \($0)",
                        locale: NFAppLocalization.preferredLocale,
                        comment: "Numeric exercise answer placeholder; the placeholder is the requested unit."
                    )
                } ?? NFAppLocalization.localized("Value",
                    locale: NFAppLocalization.preferredLocale,
                    comment: "Unitless numeric exercise answer placeholder."
                ),
                permitsScientificNotation: true,
                permitsThousandsSeparators: true
            )
        )
    }

    private static func difficulty(base: Double, steps: Int, shift: Double) -> NFExerciseDifficulty {
        NFExerciseDifficulty(
            overall: base,
            reasoningSteps: steps,
            abstraction: min(1, base + 0.08),
            representationShift: shift,
            priorKnowledge: min(1, max(0.1, base - 0.1)),
            timePressure: 0.2
        )
    }

    private static func adjustedDifficulty(
        _ difficulty: NFExerciseDifficulty,
        request: NFExerciseGenerationRequest
    ) -> NFExerciseDifficulty {
        let purposeAdjustment: Double
        switch request.purpose {
        case .practice: purposeAdjustment = -0.08
        case .documentPractice: purposeAdjustment = -0.04
        case .retention: purposeAdjustment = 0
        case .baseline: purposeAdjustment = 0.03
        case .nearTransfer: purposeAdjustment = 0.08
        case .assessmentHoldout: purposeAdjustment = 0.1
        case .appliedTransfer: purposeAdjustment = 0.14
        }
        let target = request.targetDifficulty ?? min(1, max(0, difficulty.overall + purposeAdjustment))
        return NFExerciseDifficulty(
            overall: target,
            reasoningSteps: difficulty.reasoningSteps,
            abstraction: min(1, max(0, difficulty.abstraction + purposeAdjustment / 2)),
            representationShift: min(1, max(0, difficulty.representationShift + purposeAdjustment)),
            priorKnowledge: difficulty.priorKnowledge,
            timePressure: difficulty.timePressure
        )
    }

    private static func exactRubric(_ description: String) -> NFExerciseRubric {
        NFExerciseRubric(
            criteria: [NFExerciseRubricCriterion(id: "correct", description: description, weight: 1)],
            fullCreditThreshold: 1,
            permitsPartialCredit: false
        )
    }

    private static func weightedRubric(_ criteria: [(String, String, Double)]) -> NFExerciseRubric {
        NFExerciseRubric(
            criteria: criteria.map { NFExerciseRubricCriterion(id: $0.0, description: $0.1, weight: $0.2) },
            fullCreditThreshold: 1,
            permitsPartialCredit: true
        )
    }

    private static func standardAccessibility(label: String) -> NFExerciseAccessibility {
        NFExerciseAccessibility(
            promptAccessibilityLabel: label,
            visualAlternative: nil,
            requiresVisualSpatialProcessing: false,
            supportsVoiceOver: true,
            supportsKeyboardOnly: true,
            usesMotion: false
        )
    }

    private static func contextualLead(_ request: NFExerciseGenerationRequest) -> String {
        let field = request.sourceContext.primaryField.localizedTitle(
            locale: NFAppLocalization.locale(identifier: request.localeIdentifier)
        )
        let topic = request.sourceContext.topic?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let isLearnerFacingTopic = topic.map {
            !$0.isEmpty
                && !$0.contains(".fallback-variant-")
                && NFUserFacingContentLinter.lint($0, field: "sourceContext.topic") == nil
        } ?? false
        if isLearnerFacingTopic, let topic {
            return localized("\(field) · \(topic).", request: request)
        }
        return localized("\(field).", request: request)
    }

    private static func templatePoolToken(for purpose: NFExercisePurpose) -> String {
        switch purpose {
        case .baseline: "baseline"
        case .practice: "practice"
        case .nearTransfer: "near"
        case .appliedTransfer: "applied"
        case .retention: "retention"
        case .assessmentHoldout: "holdout"
        case .documentPractice: "document"
        }
    }

    private static func selectedVariant(
        request: NFExerciseGenerationRequest,
        defaultUpperBound: Int,
        compatibleVariants: [NFAssessmentItemFormat: [Int]],
        random: inout NFFallbackRandom
    ) -> Int {
        if let mechanicID = request.preferredAssessmentMechanicID,
           let markerRange = mechanicID.range(of: ".fallback-variant-", options: .backwards),
           let declaredVariant = Int(mechanicID[markerRange.upperBound...]),
           declaredVariant >= 0,
           declaredVariant < defaultUpperBound,
           request.preferredAssessmentFormat.map({
               compatibleVariants[$0]?.contains(declaredVariant) == true
           }) ?? true {
            return declaredVariant
        }
        guard
            let preferredFormat = request.preferredAssessmentFormat,
            let variants = compatibleVariants[preferredFormat],
            !variants.isEmpty
        else {
            return random.int(upperBound: defaultUpperBound)
        }
        return variants[random.int(upperBound: variants.count)]
    }

    private static func mixedSeed(for request: NFExerciseGenerationRequest) -> UInt64 {
        let discriminator = [
            String(request.seed),
            String(request.index),
            request.lab.rawValue,
            request.purpose.rawValue,
            request.preferredAssessmentFormat?.rawValue ?? "automatic",
            request.preferredAssessmentMechanicID ?? "automatic-mechanic",
            request.sourceContext.transferBrief.map(canonicalEncoding) ?? "no-transfer-brief",
            String(generatorVersion)
        ].joined(separator: ":")
        return request.seed ^ stableHash(discriminator)
    }

    private static func stableDigest(_ value: String) -> String {
        String(stableHash(value), radix: 16)
    }

    private static func canonicalEncoding<T: Encodable>(_ value: T) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(value),
              let encoded = String(data: data, encoding: .utf8) else {
            return "encoding-failed"
        }
        return encoded
    }

    private static func stableHash(_ value: String) -> UInt64 {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in value.utf8 {
            hash ^= UInt64(byte)
            hash &*= 0x0000_0100_0000_01B3
        }
        return hash
    }

    private static func format(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...2)))
    }
}

private struct NFFallbackRandom: Sendable {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed == 0 ? 0x9E37_79B9_7F4A_7C15 : seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var value = state
        value = (value ^ (value >> 30)) &* 0xBF58_476D_1CE4_E5B9
        value = (value ^ (value >> 27)) &* 0x94D0_49BB_1331_11EB
        return value ^ (value >> 31)
    }

    mutating func int(upperBound: Int) -> Int {
        precondition(upperBound > 0)
        return Int(next() % UInt64(upperBound))
    }

    mutating func bool() -> Bool {
        next() & 1 == 0
    }

    mutating func shuffle<Element>(_ values: inout [Element]) {
        guard values.count > 1 else { return }
        for index in stride(from: values.count - 1, through: 1, by: -1) {
            let other = int(upperBound: index + 1)
            if index != other { values.swapAt(index, other) }
        }
    }
}

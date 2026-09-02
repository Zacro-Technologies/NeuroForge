import Foundation

struct SeededGenerator: RandomNumberGenerator, Sendable {
    private var state: UInt64

    init(seed: UInt64) {
        self.state = seed == 0 ? 0x9E37_79B9_7F4A_7C15 : seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var value = state
        value = (value ^ (value >> 30)) &* 0xBF58_476D_1CE4_E5B9
        value = (value ^ (value >> 27)) &* 0x94D0_49BB_1331_11EB
        return value ^ (value >> 31)
    }
}

enum AdaptiveEngine {
    static let policyVersion = 1
    static let reducerVersion = 2

    static func makeDailyPlan(
        profile: ProfileSnapshot,
        date: Date,
        readiness: Readiness,
        calendar: Calendar = .current
    ) -> DailyPlan {
        let dayKey = localDayKey(for: date, calendar: calendar)
        let seed = fnv1a64("\(profile.id.uuidString):\(dayKey):\(policyVersion)")
        let budget = profile.dailyDuration

        let blocks: [PlanBlock]
        switch budget {
        case ...5:
            blocks = [
                block(seed, 0, .mentalMath, "Numerical control", "Flexible calculation", 3, [.goalPriority, .estimateUncertain], .practice),
                block(seed, 1, .transfer, "Transfer check", "An unfamiliar representation", 2, [.transferGap, .calibration], .nearTransfer)
            ]
        case 6...10:
            blocks = [
                block(seed, 0, .retrieval, "Source recall warm-up", "Optional citation-grounded review", 2, [.variety], .documentPractice),
                block(seed, 1, .mentalMath, "Numerical control", "Flexible calculation", readiness == .low ? 4 : 5, [.goalPriority, .estimateUncertain], .practice),
                block(seed, 2, .transfer, "Transfer & reflect", "A new context, then calibration", readiness == .low ? 2 : 3, [.transferGap, .calibration], .appliedTransfer)
            ]
        case 11...15:
            blocks = [
                block(seed, 0, .retrieval, "Source recall warm-up", "Optional citation-grounded review", 3, [.variety], .documentPractice),
                block(seed, 1, .mentalMath, "Numerical control", "Scientific notation and estimation", 5, [.goalPriority, .skillGap], .practice),
                block(seed, 2, .scientificReasoning, "Figure forensics", "Match evidence to the claim", 3, [.representationCoverage, .variety], .practice),
                block(seed, 3, .transfer, "Transfer & reflect", "Apply the structure in a new field", 4, [.transferGap, .calibration], .appliedTransfer)
            ]
        default:
            blocks = [
                block(seed, 0, .retrieval, "Source recall warm-up", "Optional citation-grounded review", 4, [.variety], .documentPractice),
                block(seed, 1, .mentalMath, "Numerical control", "Estimation before exact calculation", 5, [.goalPriority, .skillGap], .practice),
                block(seed, 2, .logicDebugging, "Logic & state", "Find the first unsupported step", 5, [.errorPattern, .variety], .practice),
                block(seed, 3, .transfer, "Mission fragment", "Cross representation and field", 4, [.transferGap, .representationCoverage], .appliedTransfer),
                block(seed, 4, .quantitative, "Calibration", "Confidence against observed accuracy", 2, [.calibration], .nearTransfer)
            ]
        }

        let adjustedBlocks: [PlanBlock]
        if readiness == .low {
            adjustedBlocks = blocks.map { block in
                PlanBlock(
                    id: block.id,
                    lab: block.lab,
                    title: block.title,
                    detail: block.detail,
                    minutes: max(1, block.minutes - (block.minutes >= 4 ? 1 : 0)),
                    reasons: block.reasons,
                    evidenceClass: block.evidenceClass,
                    offlineReady: block.offlineReady
                )
            }
        } else {
            adjustedBlocks = blocks
        }

        return DailyPlan(
            id: "plan.\(dayKey).\(String(seed, radix: 16))",
            localDayKey: dayKey,
            seed: seed,
            policyVersion: policyVersion,
            minutes: adjustedBlocks.reduce(0) { $0 + $1.minutes },
            blocks: adjustedBlocks
        )
    }

    static func reduce(_ attempts: [AttemptDTO]) -> [SkillSummary] {
        TrainingLab.allCases.map { lab in
            let relevant = attempts
                .filter {
                    attributedWeight(of: $0, to: lab) > 0
                        && $0.evidenceClass != .documentPractice
                        && $0.evidenceWeight > 0
                }
                .sorted { lhs, rhs in
                    if lhs.submittedAt == rhs.submittedAt { return lhs.id.uuidString < rhs.id.uuidString }
                    return lhs.submittedAt < rhs.submittedAt
                }

            var theta = 0.0
            for (index, attempt) in relevant.enumerated() {
                let expected = 1.0 / (1.0 + exp(-theta))
                let k = max(0.08, 0.34 / sqrt(Double(index + 1)))
                let outcome = attempt.credit
                let weightedEvidence = attempt.evidenceWeight * attributedWeight(of: attempt, to: lab)
                theta = min(3, max(-3, theta + k * weightedEvidence * (outcome - expected)))
            }

            let count = relevant.count
            let totalWeight = relevant.reduce(0) {
                $0 + $1.evidenceWeight * attributedWeight(of: $1, to: lab)
            }
            let earnedCredit = relevant.reduce(0) {
                $0 + $1.credit * $1.evidenceWeight * attributedWeight(of: $1, to: lab)
            }
            let accuracy = totalWeight == 0 ? nil : earnedCredit / totalWeight
            let status: EstimateStatus
            switch count {
            case 0: status = .unassessed
            case 1...5: status = .emergingEvidence
            case 6...19: status = .developing
            default: status = .stable
            }

            let confidenceAttempts = relevant.compactMap { attempt -> (Double, Double)? in
                guard let confidence = attempt.confidence else { return nil }
                return (confidence.probability, attempt.credit)
            }
            let bias: Double? = confidenceAttempts.isEmpty ? nil : confidenceAttempts.reduce(0) { partial, pair in
                partial + pair.0 - pair.1
            } / Double(confidenceAttempts.count)

            return SkillSummary(
                id: lab.skillID,
                lab: lab,
                theta: theta,
                uncertainty: count == 0 ? 1 : max(0.12, 1 / sqrt(Double(count))),
                evidenceCount: count,
                accuracy: accuracy,
                status: status,
                calibrationBias: bias,
                lastTrained: relevant.last?.submittedAt
            )
        }
    }

    private static func attributedWeight(of attempt: AttemptDTO, to lab: TrainingLab) -> Double {
        if let direct = attempt.skillWeights[lab.skillID], direct > 0 { return direct }
        guard let dimension = attempt.assessmentDimension,
              dimension != .confidenceCalibration,
              dimension.lab == lab else {
            return 0
        }
        return attempt.skillWeights[dimension.skillID] ?? 1
    }

    private static func block(
        _ seed: UInt64,
        _ index: Int,
        _ lab: TrainingLab,
        _ title: String,
        _ detail: String,
        _ minutes: Int,
        _ reasons: [PrescriptionReason],
        _ evidenceClass: EvidenceClass
    ) -> PlanBlock {
        PlanBlock(
            id: "block.\(String(seed, radix: 16)).\(index)",
            lab: lab,
            title: title,
            detail: detail,
            minutes: minutes,
            reasons: reasons,
            evidenceClass: evidenceClass,
            offlineReady: true
        )
    }

    private static func localDayKey(for date: Date, calendar: Calendar) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", components.year ?? 0, components.month ?? 0, components.day ?? 0)
    }

    static func fnv1a64(_ string: String) -> UInt64 {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in string.utf8 {
            hash ^= UInt64(byte)
            hash &*= 0x0000_0100_0000_01B3
        }
        return hash
    }
}

enum MentalMathGenerator {
    static let scoringVersion = 1

    static func generate(
        seed: UInt64,
        index: Int,
        preferredKind: MentalMathKind? = nil,
        evidenceClass: EvidenceClass = .practice
    ) -> MentalMathItem {
        var random = SeededGenerator(seed: seed &+ UInt64(index) &* 0x9E37_79B9)
        let kindIndex: Int
        switch preferredKind {
        case .multiplication: kindIndex = 0
        case .percentage: kindIndex = 1
        case .scientificNotation: kindIndex = 2
        case .estimation: kindIndex = 3
        case nil: kindIndex = Int(random.next() % 4)
        }

        switch kindIndex {
        case 0:
            let left = Int(32 + random.next() % 36)
            let multiplierOptions = [9, 11, 19, 21]
            let right = multiplierOptions[Int(random.next() % UInt64(multiplierOptions.count))]
            let answer = Double(left * right)
            let nearby = right == 9 || right == 19 ? right + 1 : right - 1
            let operation = right < nearby ? "subtract \(left) once" : "add \(left) once"
            return MentalMathItem(
                id: "mm.multiply.v1.\(seed).\(index)",
                templateID: "mm.decompose.multiply.compensation.v1",
                seed: seed &+ UInt64(index),
                kind: .multiplication,
                prompt: "\(left) × \(right)",
                context: "Calculate mentally. Accuracy is scored separately from speed.",
                answer: answer,
                tolerance: 0,
                strategy: "Compensate from \(left) × \(nearby), then \(operation).",
                decisiveStep: "Use \(right) = \(nearby) \(right < nearby ? "−" : "+") 1.",
                difficulty: 0.34,
                evidenceClass: evidenceClass
            )
        case 1:
            let percentages = [12.5, 15, 20, 25, 40]
            let percent = percentages[Int(random.next() % UInt64(percentages.count))]
            let bases = [80, 120, 160, 240, 320]
            let base = bases[Int(random.next() % UInt64(bases.count))]
            let answer = Double(base) * percent / 100
            return MentalMathItem(
                id: "mm.percentage.v1.\(seed).\(index)",
                templateID: "mm.rational.percentage.v1",
                seed: seed &+ UInt64(index),
                kind: .percentage,
                prompt: "What is \(percent.formatted(.number.precision(.fractionLength(0...1))))% of \(base)?",
                context: "Convert the percentage into a useful fraction or decimal.",
                answer: answer,
                tolerance: 0.001,
                strategy: percent == 12.5 ? "12.5% is one eighth." : "Split the percentage into familiar parts.",
                decisiveStep: "Compute \(base) × \(percent / 100).",
                difficulty: 0.4,
                evidenceClass: evidenceClass
            )
        case 2:
            let coefficients = [1.8, 2.4, 3.2, 6.5, 7.2]
            let coefficient = coefficients[Int(random.next() % UInt64(coefficients.count))]
            let exponent = Int(2 + random.next() % 4)
            let answer = coefficient * pow(10, Double(exponent))
            return MentalMathItem(
                id: "mm.scientific.v1.\(seed).\(index)",
                templateID: "mm.scientific_notation.shift.v1",
                seed: seed &+ UInt64(index),
                kind: .scientificNotation,
                prompt: "Write \(coefficient.formatted()) × 10\(superscript(exponent)) as an ordinary number.",
                context: "Preserve the coefficient while shifting the place value.",
                answer: answer,
                tolerance: 0.001,
                strategy: "Move the decimal point \(exponent) places to the right.",
                decisiveStep: "A positive exponent multiplies by ten \(exponent) times.",
                difficulty: 0.3,
                evidenceClass: evidenceClass
            )
        default:
            let population = Int(120 + random.next() % 780)
            let rateOptions = [3, 4, 6, 8, 12]
            let rate = rateOptions[Int(random.next() % UInt64(rateOptions.count))]
            let answer = Double(population * rate)
            return MentalMathItem(
                id: "mm.estimate.v1.\(seed).\(index)",
                templateID: "mm.estimate.rate.v1",
                seed: seed &+ UInt64(index),
                kind: .estimation,
                prompt: "A sensor records about \(rate) events per minute. Roughly how many in \(population) minutes?",
                context: "Give the central estimate. A useful order of magnitude matters first.",
                answer: answer,
                tolerance: answer * 0.12,
                strategy: "Round one factor, multiply, then correct the approximation.",
                decisiveStep: "The estimate is rate × time: \(rate) × \(population).",
                difficulty: 0.38,
                evidenceClass: evidenceClass
            )
        }
    }

    static func score(response: String, item: MentalMathItem) -> DeterministicScore {
        let normalized = response
            .replacingOccurrences(of: ",", with: "")
            .replacingOccurrences(of: " ", with: "")
        guard let value = Double(normalized), value.isFinite else {
            return DeterministicScore(isCorrect: false, normalizedResponse: nil, errorCode: "input_error")
        }
        let correct = abs(value - item.answer) <= item.tolerance
        let error: String?
        if correct {
            error = nil
        } else if item.kind == .scientificNotation {
            error = "exponent"
        } else if item.kind == .percentage {
            error = "percentage_base"
        } else {
            error = "operation_selection"
        }
        return DeterministicScore(isCorrect: correct, normalizedResponse: value, errorCode: error)
    }

    static func feedback(score: DeterministicScore, item: MentalMathItem) -> DeterministicFeedback {
        if score.isCorrect {
            return DeterministicFeedback(
                title: "Correct",
                explanation: "The result is \(format(item.answer)).",
                strategy: item.strategy,
                errorCode: nil
            )
        }
        return DeterministicFeedback(
            title: "Revisit the decisive step",
            explanation: "\(item.decisiveStep) The supported result is \(format(item.answer)).",
            strategy: item.strategy,
            errorCode: score.errorCode
        )
    }

    private static func format(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...3)))
    }

    private static func superscript(_ number: Int) -> String {
        let map: [Character: Character] = ["0": "⁰", "1": "¹", "2": "²", "3": "³", "4": "⁴", "5": "⁵", "6": "⁶", "7": "⁷", "8": "⁸", "9": "⁹", "-": "⁻"]
        return String(String(number).map { map[$0] ?? $0 })
    }
}

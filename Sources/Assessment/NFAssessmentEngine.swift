import Foundation

// MARK: - Baseline structure

enum NFAssessmentBlockKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case numericalFluency
    case spatialRepresentation
    case scientificDataReasoning
    case logicMetacognition

    var id: String { rawValue }
}

/// The eight independent release-baseline dimensions. These identifiers are
/// persisted as attempt skill IDs so assessment evidence cannot be collapsed
/// into the broader training-lab buckets during replay or result reduction.
enum NFAssessmentDimension: String, Codable, CaseIterable, Identifiable, Sendable {
    case mentalArithmetic
    case quantitativeEstimation
    case probability
    case spatialTransformations
    case dataInterpretation
    case experimentalReasoning
    case logic
    case confidenceCalibration

    var id: String { rawValue }
    var skillID: String { "skill.assessment.\(rawValue)" }

    var title: String {
        switch self {
        case .mentalArithmetic:
            NFAppLocalization.localized("Mental math", locale: NFAppLocalization.preferredLocale, comment: "Independent baseline dimension for mental arithmetic.")
        case .quantitativeEstimation:
            NFAppLocalization.localized("Estimation", locale: NFAppLocalization.preferredLocale, comment: "Independent baseline dimension for quantitative estimation.")
        case .probability:
            NFAppLocalization.localized("Probability", locale: NFAppLocalization.preferredLocale, comment: "Independent baseline dimension for probability reasoning.")
        case .spatialTransformations:
            NFAppLocalization.localized("Spatial transformation", locale: NFAppLocalization.preferredLocale, comment: "Independent baseline dimension for spatial transformations.")
        case .dataInterpretation:
            NFAppLocalization.localized("Data interpretation", locale: NFAppLocalization.preferredLocale, comment: "Independent baseline dimension for data interpretation.")
        case .experimentalReasoning:
            NFAppLocalization.localized("Experimental design", locale: NFAppLocalization.preferredLocale, comment: "Independent baseline dimension for experimental reasoning.")
        case .logic:
            NFAppLocalization.localized("Logic", locale: NFAppLocalization.preferredLocale, comment: "Independent baseline dimension for formal logic and debugging.")
        case .confidenceCalibration:
            NFAppLocalization.localized("Confidence calibration", locale: NFAppLocalization.preferredLocale, comment: "Independent baseline dimension for confidence calibration.")
        }
    }

    var lab: TrainingLab {
        switch self {
        case .mentalArithmetic: .mentalMath
        case .quantitativeEstimation, .probability: .quantitative
        case .spatialTransformations: .spatial
        case .dataInterpretation, .experimentalReasoning: .scientificReasoning
        case .logic, .confidenceCalibration: .logicDebugging
        }
    }

    var block: NFAssessmentBlockKind {
        switch self {
        case .mentalArithmetic, .quantitativeEstimation, .probability: .numericalFluency
        case .spatialTransformations: .spatialRepresentation
        case .dataInterpretation, .experimentalReasoning: .scientificDataReasoning
        case .logic, .confidenceCalibration: .logicMetacognition
        }
    }

    static func from(skillID: String) -> NFAssessmentDimension? {
        allCases.first { $0.skillID == skillID }
    }
}

struct NFAssessmentBlockDefinition: Codable, Equatable, Sendable, Identifiable {
    let kind: NFAssessmentBlockKind
    let title: String
    let targetDurationSeconds: Int
    let maximumDurationSeconds: Int
    let minimumScorableItems: Int
    let itemCap: Int
    let targetInformation: Double
    let coveredLabs: [TrainingLab]

    var id: String { kind.rawValue }

    init(
        kind: NFAssessmentBlockKind,
        title: String,
        targetDurationSeconds: Int,
        maximumDurationSeconds: Int,
        minimumScorableItems: Int,
        itemCap: Int,
        targetInformation: Double,
        coveredLabs: [TrainingLab]
    ) {
        precondition(targetDurationSeconds > 0 && targetDurationSeconds <= 480)
        precondition(maximumDurationSeconds >= targetDurationSeconds && maximumDurationSeconds <= 480)
        precondition(minimumScorableItems > 0 && itemCap >= minimumScorableItems)
        self.kind = kind
        self.title = title
        self.targetDurationSeconds = targetDurationSeconds
        self.maximumDurationSeconds = maximumDurationSeconds
        self.minimumScorableItems = minimumScorableItems
        self.itemCap = itemCap
        self.targetInformation = targetInformation
        self.coveredLabs = coveredLabs
    }
}

enum NFAssessmentCatalog {
    static let minimumBaselineItemsPerDimension = 8
    static let minimumFormatsPerDimension = 2

    static let baselineBlocks: [NFAssessmentBlockDefinition] = [
        NFAssessmentBlockDefinition(
            kind: .numericalFluency,
            title: NFAppLocalization.localized("Numerical fluency", locale: NFAppLocalization.preferredLocale, comment: "Title of the numerical baseline-assessment block."),
            targetDurationSeconds: 420,
            maximumDurationSeconds: 480,
            minimumScorableItems: 24,
            itemCap: 28,
            targetInformation: 15.0,
            coveredLabs: [.mentalMath, .quantitative]
        ),
        NFAssessmentBlockDefinition(
            kind: .spatialRepresentation,
            title: NFAppLocalization.localized("Spatial and representation", locale: NFAppLocalization.preferredLocale, comment: "Title of the spatial baseline-assessment block."),
            targetDurationSeconds: 420,
            maximumDurationSeconds: 480,
            minimumScorableItems: 8,
            itemCap: 12,
            targetInformation: 5.0,
            coveredLabs: [.spatial]
        ),
        NFAssessmentBlockDefinition(
            kind: .scientificDataReasoning,
            title: NFAppLocalization.localized("Scientific and data reasoning", locale: NFAppLocalization.preferredLocale, comment: "Title of the scientific and data baseline-assessment block."),
            targetDurationSeconds: 420,
            maximumDurationSeconds: 480,
            minimumScorableItems: 16,
            itemCap: 20,
            targetInformation: 10.0,
            coveredLabs: [.scientificReasoning]
        ),
        NFAssessmentBlockDefinition(
            kind: .logicMetacognition,
            title: NFAppLocalization.localized("Logic and metacognition", locale: NFAppLocalization.preferredLocale, comment: "Title of the logic and confidence-calibration baseline-assessment block."),
            targetDurationSeconds: 360,
            maximumDurationSeconds: 420,
            minimumScorableItems: 16,
            itemCap: 20,
            targetInformation: 10.0,
            coveredLabs: [.logicDebugging]
        )
    ]

    static func definition(for kind: NFAssessmentBlockKind) -> NFAssessmentBlockDefinition {
        baselineBlocks.first { $0.kind == kind }!
    }

    static func dimensions(for block: NFAssessmentBlockKind) -> [NFAssessmentDimension] {
        NFAssessmentDimension.allCases.filter { $0.block == block }
    }

    static func minimumItemsPerDimension(
        for role: NFAssessmentContentRole,
        block: NFAssessmentBlockKind
    ) -> Int {
        switch role {
        case .practice: 0
        case .baseline: minimumBaselineItemsPerDimension
        case .reassessmentHoldout:
            // A 4–6 minute alternate form samples every dimension in its target
            // block. A spatial-only block retains eight observations; paired or
            // tripled blocks use four per dimension to stay within the limit.
            dimensions(for: block).count == 1 ? 8 : 4
        }
    }
}

// MARK: - Protected item identity

enum NFAssessmentContentRole: String, Codable, CaseIterable, Sendable {
    case practice
    case baseline
    case reassessmentHoldout

    var assessmentWeight: Double {
        switch self {
        case .practice: 0
        case .baseline, .reassessmentHoldout: 1
        }
    }

    var evidenceClass: EvidenceClass {
        switch self {
        case .practice: .practice
        case .baseline, .reassessmentHoldout: .assessmentHoldout
        }
    }

    var isProtectedAssessment: Bool { self != .practice }

    var namespaceComponent: String {
        switch self {
        case .practice: "practice"
        case .baseline: "baseline"
        case .reassessmentHoldout: "holdout"
        }
    }
}

enum NFAssessmentItemFormat: String, Codable, CaseIterable, Sendable {
    case numericEntry
    case singleChoice
    case orderedSteps
    case claimEvidence
    case stateTrace
    case diagramMatch
}

struct NFAssessmentItemDescriptor: Codable, Equatable, Hashable, Sendable, Identifiable {
    let id: String
    let templateFamily: String
    let seed: UInt64
    let block: NFAssessmentBlockKind
    let role: NFAssessmentContentRole
    let lab: TrainingLab
    let dimension: NFAssessmentDimension
    let subskillID: String
    let format: NFAssessmentItemFormat
    let mechanicID: String
    let difficulty: Double
    let expectedInformation: Double
    let estimatedDurationSeconds: Int

    var assessmentWeight: Double { role.assessmentWeight }
    var evidenceClass: EvidenceClass { role.evidenceClass }
    var isProtectedAssessment: Bool { role.isProtectedAssessment }
    var skillID: String { dimension.skillID }
}

struct NFAssessmentExposureKey: Codable, Equatable, Hashable, Sendable {
    let templateFamily: String
    let seed: UInt64
}

/// Records only items actually presented to the user. Reserving an item for a
/// form is not an exposure, so an interrupted form can resume without consuming
/// unseen content.
struct NFHoldoutExposureLedger: Codable, Equatable, Sendable {
    private(set) var protectedExposures: Set<NFAssessmentExposureKey>

    init(protectedExposures: Set<NFAssessmentExposureKey> = []) {
        self.protectedExposures = protectedExposures
    }

    func contains(_ item: NFAssessmentItemDescriptor) -> Bool {
        protectedExposures.contains(
            NFAssessmentExposureKey(templateFamily: item.templateFamily, seed: item.seed)
        )
    }

    func recordingPresentation(of item: NFAssessmentItemDescriptor) -> NFHoldoutExposureLedger {
        guard item.isProtectedAssessment else { return self }
        var copy = self
        copy.protectedExposures.insert(
            NFAssessmentExposureKey(templateFamily: item.templateFamily, seed: item.seed)
        )
        return copy
    }
}

// MARK: - Adaptive selection

struct NFAdaptiveAssessmentState: Codable, Equatable, Sendable {
    let theta: Double
    let uncertainty: Double
    let accumulatedInformation: Double
    let dimensionTheta: [NFAssessmentDimension: Double]
    let dimensionUncertainty: [NFAssessmentDimension: Double]
    let dimensionInformation: [NFAssessmentDimension: Double]
    let dimensionExposureCounts: [NFAssessmentDimension: Int]
    let dimensionCompletedCounts: [NFAssessmentDimension: Int]
    let dimensionFormatExposureCounts: [NFAssessmentDimension: [NFAssessmentItemFormat: Int]]
    let dimensionFormatCompletedCounts: [NFAssessmentDimension: [NFAssessmentItemFormat: Int]]
    let subskillExposureCounts: [String: Int]
    let formatExposureCounts: [NFAssessmentItemFormat: Int]
    let recentMechanicIDs: [String]
    let selectedItemIDs: Set<String>
    let completedItemIDs: Set<String>

    var completedScorableItems: Int { completedItemIDs.count }

    init(
        theta: Double = 0,
        uncertainty: Double = 1,
        accumulatedInformation: Double = 0,
        dimensionTheta: [NFAssessmentDimension: Double] = [:],
        dimensionUncertainty: [NFAssessmentDimension: Double] = [:],
        dimensionInformation: [NFAssessmentDimension: Double] = [:],
        dimensionExposureCounts: [NFAssessmentDimension: Int] = [:],
        dimensionCompletedCounts: [NFAssessmentDimension: Int] = [:],
        dimensionFormatExposureCounts: [NFAssessmentDimension: [NFAssessmentItemFormat: Int]] = [:],
        dimensionFormatCompletedCounts: [NFAssessmentDimension: [NFAssessmentItemFormat: Int]] = [:],
        subskillExposureCounts: [String: Int] = [:],
        formatExposureCounts: [NFAssessmentItemFormat: Int] = [:],
        recentMechanicIDs: [String] = [],
        selectedItemIDs: Set<String> = [],
        completedItemIDs: Set<String> = []
    ) {
        self.theta = theta
        self.uncertainty = uncertainty
        self.accumulatedInformation = max(0, accumulatedInformation)
        self.dimensionTheta = dimensionTheta
        self.dimensionUncertainty = dimensionUncertainty
        self.dimensionInformation = dimensionInformation.mapValues { max(0, $0) }
        self.dimensionExposureCounts = dimensionExposureCounts.mapValues { max(0, $0) }
        self.dimensionCompletedCounts = dimensionCompletedCounts.mapValues { max(0, $0) }
        self.dimensionFormatExposureCounts = dimensionFormatExposureCounts
        self.dimensionFormatCompletedCounts = dimensionFormatCompletedCounts
        self.subskillExposureCounts = subskillExposureCounts
        self.formatExposureCounts = formatExposureCounts
        self.recentMechanicIDs = recentMechanicIDs
        self.selectedItemIDs = selectedItemIDs
        self.completedItemIDs = completedItemIDs
    }

    func theta(for dimension: NFAssessmentDimension) -> Double {
        dimensionTheta[dimension] ?? theta
    }

    func uncertainty(for dimension: NFAssessmentDimension) -> Double {
        dimensionUncertainty[dimension] ?? uncertainty
    }

    func completedCount(for dimension: NFAssessmentDimension) -> Int {
        dimensionCompletedCounts[dimension, default: 0]
    }

    func completedFormats(for dimension: NFAssessmentDimension) -> Set<NFAssessmentItemFormat> {
        Set(dimensionFormatCompletedCounts[dimension, default: [:]].compactMap { format, count in
            count > 0 ? format : nil
        })
    }

    func hasRequiredEvidence(
        dimensions: [NFAssessmentDimension],
        minimumItemsPerDimension: Int,
        minimumFormatsPerDimension: Int
    ) -> Bool {
        !dimensions.isEmpty && dimensions.allSatisfy { dimension in
            completedCount(for: dimension) >= minimumItemsPerDimension
                && completedFormats(for: dimension).count >= minimumFormatsPerDimension
        }
    }

    func appending(_ item: NFAssessmentItemDescriptor) -> NFAdaptiveAssessmentState {
        guard !selectedItemIDs.contains(item.id) else { return self }
        var subskills = subskillExposureCounts
        subskills[item.subskillID, default: 0] += 1
        var formats = formatExposureCounts
        formats[item.format, default: 0] += 1
        var dimensionExposures = dimensionExposureCounts
        dimensionExposures[item.dimension, default: 0] += 1
        var dimensionFormats = dimensionFormatExposureCounts
        dimensionFormats[item.dimension, default: [:]][item.format, default: 0] += 1
        var mechanics = recentMechanicIDs
        mechanics.append(item.mechanicID)
        mechanics = Array(mechanics.suffix(3))
        var selected = selectedItemIDs
        selected.insert(item.id)
        return NFAdaptiveAssessmentState(
            theta: theta,
            uncertainty: uncertainty,
            accumulatedInformation: accumulatedInformation,
            dimensionTheta: dimensionTheta,
            dimensionUncertainty: dimensionUncertainty,
            dimensionInformation: dimensionInformation,
            dimensionExposureCounts: dimensionExposures,
            dimensionCompletedCounts: dimensionCompletedCounts,
            dimensionFormatExposureCounts: dimensionFormats,
            dimensionFormatCompletedCounts: dimensionFormatCompletedCounts,
            subskillExposureCounts: subskills,
            formatExposureCounts: formats,
            recentMechanicIDs: mechanics,
            selectedItemIDs: selected,
            completedItemIDs: completedItemIDs
        )
    }

    /// Applies a durable, deterministic assessment result. Calling this more than
    /// once for the same descriptor is intentionally idempotent so checkpoint
    /// replay cannot move the estimate twice.
    func recordingResponse(
        to item: NFAssessmentItemDescriptor,
        credit: Double
    ) -> NFAdaptiveAssessmentState {
        guard !completedItemIDs.contains(item.id) else { return self }

        let selectedState = selectedItemIDs.contains(item.id) ? self : appending(item)
        let boundedCredit = NFStableDeterminism.clampedUnit(credit)
        let currentTheta = selectedState.theta(for: item.dimension)
        let currentUncertainty = selectedState.uncertainty(for: item.dimension)
        let boundedDifficulty = min(0.999, max(0.001, item.difficulty))
        let difficultyLogit = log(boundedDifficulty / (1 - boundedDifficulty))
        let expected = 1 / (1 + exp(-(currentTheta - difficultyLogit)))
        let stepSize = min(0.65, max(0.12, 0.55 * currentUncertainty))
        let updatedDimensionTheta = min(4, max(-4, currentTheta + stepSize * (boundedCredit - expected)))

        // Information is greatest near the current estimate and remains positive
        // for off-target responses so every scorable item narrows uncertainty.
        let responseInformation = max(
            0.05,
            item.expectedInformation * 4 * expected * (1 - expected)
        )
        let updatedDimensionInformation = selectedState.dimensionInformation[item.dimension, default: 0]
            + responseInformation
        let updatedDimensionUncertainty = max(0.08, 1 / sqrt(1 + updatedDimensionInformation))
        var dimensionThetas = selectedState.dimensionTheta
        dimensionThetas[item.dimension] = updatedDimensionTheta
        var dimensionUncertainties = selectedState.dimensionUncertainty
        dimensionUncertainties[item.dimension] = updatedDimensionUncertainty
        var dimensionInformation = selectedState.dimensionInformation
        dimensionInformation[item.dimension] = updatedDimensionInformation
        var dimensionCompleted = selectedState.dimensionCompletedCounts
        dimensionCompleted[item.dimension, default: 0] += 1
        var completedFormats = selectedState.dimensionFormatCompletedCounts
        completedFormats[item.dimension, default: [:]][item.format, default: 0] += 1
        var completed = selectedState.completedItemIDs
        completed.insert(item.id)

        let observedDimensions = dimensionCompleted.filter { $0.value > 0 }.map(\.key)
        let totalObservedCount = max(1, observedDimensions.reduce(0) { $0 + dimensionCompleted[$1, default: 0] })
        let updatedTheta = observedDimensions.reduce(0) { partial, dimension in
            partial + dimensionThetas[dimension, default: 0]
                * Double(dimensionCompleted[dimension, default: 0])
        } / Double(totalObservedCount)
        let updatedInformation = dimensionInformation.values.reduce(0, +)
        let updatedUncertainty = observedDimensions.isEmpty
            ? selectedState.uncertainty
            : observedDimensions.reduce(0) {
                $0 + dimensionUncertainties[$1, default: 1]
            } / Double(observedDimensions.count)

        return NFAdaptiveAssessmentState(
            theta: updatedTheta,
            uncertainty: updatedUncertainty,
            accumulatedInformation: updatedInformation,
            dimensionTheta: dimensionThetas,
            dimensionUncertainty: dimensionUncertainties,
            dimensionInformation: dimensionInformation,
            dimensionExposureCounts: selectedState.dimensionExposureCounts,
            dimensionCompletedCounts: dimensionCompleted,
            dimensionFormatExposureCounts: selectedState.dimensionFormatExposureCounts,
            dimensionFormatCompletedCounts: completedFormats,
            subskillExposureCounts: selectedState.subskillExposureCounts,
            formatExposureCounts: selectedState.formatExposureCounts,
            recentMechanicIDs: selectedState.recentMechanicIDs,
            selectedItemIDs: selectedState.selectedItemIDs,
            completedItemIDs: completed
        )
    }

    func recordingResponse(
        to item: NFAssessmentItemDescriptor,
        isCorrect: Bool
    ) -> NFAdaptiveAssessmentState {
        recordingResponse(to: item, credit: isCorrect ? 1 : 0)
    }
}

struct NFAssessmentCandidateScore: Codable, Equatable, Sendable {
    let expectedInformation: Double
    let dimensionCoverageNeed: Double
    let coverageNeed: Double
    let formatDiversity: Double
    let recentMechanicSimilarity: Double
    let accessibilityPenalty: Double
    let exposurePenalty: Double
    let total: Double
}

enum NFAssessmentSelectionEngine {
    static let policyVersion = 1

    static func score(
        _ item: NFAssessmentItemDescriptor,
        state: NFAdaptiveAssessmentState,
        exposureLedger: NFHoldoutExposureLedger,
        excludedLabs: Set<TrainingLab> = []
    ) -> NFAssessmentCandidateScore {
        let targetDifficulty = 1 / (1 + exp(-state.theta(for: item.dimension)))
        let information = item.expectedInformation
            * max(0.15, state.uncertainty(for: item.dimension))
            * exp(-2.4 * abs(item.difficulty - targetDifficulty))
        let dimensionCoverage = 1 / Double(1 + state.dimensionExposureCounts[item.dimension, default: 0])
        let coverage = 1 / Double(1 + state.subskillExposureCounts[item.subskillID, default: 0])
        let formatDiversity = 1 / Double(
            1 + state.dimensionFormatExposureCounts[item.dimension, default: [:]][item.format, default: 0]
        )
        let similarity = state.recentMechanicIDs.contains(item.mechanicID) ? 1.0 : 0.0
        let accessibility = excludedLabs.contains(item.lab) ? 10.0 : 0.0
        let exposure = exposureLedger.contains(item) ? 10.0 : 0.0
        let total = information
            + 0.35 * dimensionCoverage
            + 0.20 * coverage
            + 0.10 * formatDiversity
            - 0.30 * similarity
            - accessibility
            - exposure
        return NFAssessmentCandidateScore(
            expectedInformation: information,
            dimensionCoverageNeed: dimensionCoverage,
            coverageNeed: coverage,
            formatDiversity: formatDiversity,
            recentMechanicSimilarity: similarity,
            accessibilityPenalty: accessibility,
            exposurePenalty: exposure,
            total: total
        )
    }

    static func selectNext(
        from candidates: [NFAssessmentItemDescriptor],
        block: NFAssessmentBlockKind,
        role: NFAssessmentContentRole,
        state: NFAdaptiveAssessmentState,
        exposureLedger: NFHoldoutExposureLedger,
        excludedLabs: Set<TrainingLab> = [],
        tieBreakSeed: UInt64
    ) -> NFAssessmentItemDescriptor? {
        let eligible = candidates
            .filter {
                $0.block == block
                    && $0.role == role
                    && !state.selectedItemIDs.contains($0.id)
                    && !excludedLabs.contains($0.lab)
                    && !exposureLedger.contains($0)
            }

        let coverageBalanced = coverageConstrainedCandidates(
            eligible,
            block: block,
            role: role,
            state: state
        )
        return coverageBalanced
            .map { item in
                (item, score(item, state: state, exposureLedger: exposureLedger, excludedLabs: excludedLabs))
            }
            .sorted { lhs, rhs in
                if abs(lhs.1.total - rhs.1.total) > 0.000_000_001 {
                    return lhs.1.total > rhs.1.total
                }
                let leftTie = NFStableDeterminism.hash64("\(tieBreakSeed)|\(lhs.0.id)")
                let rightTie = NFStableDeterminism.hash64("\(tieBreakSeed)|\(rhs.0.id)")
                if leftTie != rightTie { return leftTie < rightTie }
                return lhs.0.id < rhs.0.id
            }
            .first?.0
    }

    private static func coverageConstrainedCandidates(
        _ candidates: [NFAssessmentItemDescriptor],
        block: NFAssessmentBlockKind,
        role: NFAssessmentContentRole,
        state: NFAdaptiveAssessmentState
    ) -> [NFAssessmentItemDescriptor] {
        let minimum = NFAssessmentCatalog.minimumItemsPerDimension(for: role, block: block)
        let dimensions = NFAssessmentCatalog.dimensions(for: block)
        guard minimum > 0, !dimensions.isEmpty else { return candidates }

        let underTarget = dimensions.filter {
            state.dimensionExposureCounts[$0, default: 0] < minimum
        }
        guard !underTarget.isEmpty else { return candidates }
        let leastExposure = underTarget.map {
            state.dimensionExposureCounts[$0, default: 0]
        }.min() ?? 0
        let nextDimensions = Set(underTarget.filter {
            state.dimensionExposureCounts[$0, default: 0] == leastExposure
        })

        let constrained = nextDimensions.flatMap { dimension -> [NFAssessmentItemDescriptor] in
            let dimensionCandidates = candidates.filter { $0.dimension == dimension }
            let usedFormats = Set(
                state.dimensionFormatExposureCounts[dimension, default: [:]].compactMap { format, count in
                    count > 0 ? format : nil
                }
            )
            guard state.dimensionExposureCounts[dimension, default: 0] >= max(1, minimum / 2),
                  usedFormats.count < NFAssessmentCatalog.minimumFormatsPerDimension else {
                return dimensionCandidates
            }
            let unseenFormatCandidates = dimensionCandidates.filter { !usedFormats.contains($0.format) }
            return unseenFormatCandidates.isEmpty ? dimensionCandidates : unseenFormatCandidates
        }
        // Custom and partially quarantined pools may not contain the globally
        // least-exposed dimension. Keep selecting from available protected
        // candidates; the session evidence gate will leave the missing
        // dimension explicitly unassessed.
        return constrained.isEmpty ? candidates : constrained
    }
}

// MARK: - Forms and resumable blocks

enum NFAssessmentPhase: Codable, Equatable, Sendable {
    case initialBaseline
    case reassessment(cycle: Int)

    var role: NFAssessmentContentRole {
        switch self {
        case .initialBaseline: .baseline
        case .reassessment: .reassessmentHoldout
        }
    }

    var formOrdinal: Int {
        switch self {
        case .initialBaseline: 0
        case let .reassessment(cycle): max(1, cycle)
        }
    }
}

struct NFAssessmentBlockSession: Codable, Equatable, Sendable, Identifiable {
    let id: String
    let definition: NFAssessmentBlockDefinition
    let phase: NFAssessmentPhase
    let formOrdinal: Int
    let selectionSeed: UInt64
    let targetDurationSeconds: Int
    let maximumDurationSeconds: Int
    let minimumScorableItems: Int
    let itemCap: Int
    let targetInformation: Double
    let candidatePool: [NFAssessmentItemDescriptor]
    let items: [NFAssessmentItemDescriptor]

    var dimensions: [NFAssessmentDimension] {
        NFAssessmentCatalog.dimensions(for: definition.kind)
    }

    var minimumItemsPerDimension: Int {
        NFAssessmentCatalog.minimumItemsPerDimension(for: phase.role, block: definition.kind)
    }

    func hasSufficientEvidence(in state: NFAdaptiveAssessmentState) -> Bool {
        state.hasRequiredEvidence(
            dimensions: dimensions,
            minimumItemsPerDimension: minimumItemsPerDimension,
            minimumFormatsPerDimension: NFAssessmentCatalog.minimumFormatsPerDimension
        )
    }

    func nextUnanswered(using checkpoint: NFAssessmentCheckpoint) -> NFAssessmentItemDescriptor? {
        guard checkpoint.sessionID == id else { return nil }
        return items.first { !checkpoint.completedItemIDs.contains($0.id) }
    }
}

enum NFAssessmentStopReason: String, Codable, Equatable, Sendable {
    case targetInformationReached
    case maximumActiveDurationReached
    case itemCapReached
    case candidatePoolExhausted
}

struct NFAssessmentNextStep: Codable, Equatable, Sendable {
    let item: NFAssessmentItemDescriptor?
    let stopReason: NFAssessmentStopReason?

    var shouldStop: Bool { stopReason != nil }

    static func continueWith(_ item: NFAssessmentItemDescriptor) -> NFAssessmentNextStep {
        NFAssessmentNextStep(item: item, stopReason: nil)
    }

    static func stop(_ reason: NFAssessmentStopReason) -> NFAssessmentNextStep {
        NFAssessmentNextStep(item: nil, stopReason: reason)
    }
}

struct NFAssessmentCheckpoint: Codable, Equatable, Sendable {
    let sessionID: String
    let completedItemIDs: Set<String>
    let presentedItemIDs: Set<String>
    let activeElapsedSeconds: Int
    let interruptedSeconds: Int

    init(
        sessionID: String,
        completedItemIDs: Set<String> = [],
        presentedItemIDs: Set<String> = [],
        activeElapsedSeconds: Int = 0,
        interruptedSeconds: Int = 0
    ) {
        self.sessionID = sessionID
        self.completedItemIDs = completedItemIDs
        self.presentedItemIDs = presentedItemIDs
        self.activeElapsedSeconds = activeElapsedSeconds
        self.interruptedSeconds = interruptedSeconds
    }

    func recordingPresentation(itemID: String) -> NFAssessmentCheckpoint {
        var presented = presentedItemIDs
        presented.insert(itemID)
        return NFAssessmentCheckpoint(
            sessionID: sessionID,
            completedItemIDs: completedItemIDs,
            presentedItemIDs: presented,
            activeElapsedSeconds: activeElapsedSeconds,
            interruptedSeconds: interruptedSeconds
        )
    }

    func recordingCompletion(itemID: String, activeSeconds: Int) -> NFAssessmentCheckpoint {
        var completed = completedItemIDs
        completed.insert(itemID)
        var presented = presentedItemIDs
        presented.insert(itemID)
        return NFAssessmentCheckpoint(
            sessionID: sessionID,
            completedItemIDs: completed,
            presentedItemIDs: presented,
            activeElapsedSeconds: activeElapsedSeconds + max(0, activeSeconds),
            interruptedSeconds: interruptedSeconds
        )
    }

    func recordingInterruption(seconds: Int) -> NFAssessmentCheckpoint {
        NFAssessmentCheckpoint(
            sessionID: sessionID,
            completedItemIDs: completedItemIDs,
            presentedItemIDs: presentedItemIDs,
            activeElapsedSeconds: activeElapsedSeconds,
            interruptedSeconds: interruptedSeconds + max(0, seconds)
        )
    }
}

enum NFAssessmentEngine {
    static let generatorVersion = 2

    static func makeBlockSession(
        block: NFAssessmentBlockKind,
        phase: NFAssessmentPhase,
        profileSeed: UInt64,
        selfReportedDifficulty: Double = 0.5,
        exposureLedger: NFHoldoutExposureLedger = NFHoldoutExposureLedger(),
        excludedLabs: Set<TrainingLab> = [],
        excludedDescriptorIDs: Set<String> = []
    ) -> NFAssessmentBlockSession {
        let definition = NFAssessmentCatalog.definition(for: block)
        let formOrdinal = phase.formOrdinal
        let exclusionIdentity = excludedDescriptorIDs.sorted().joined(separator: ",")
        let selectionSeed = NFStableDeterminism.hash64(
            "assessment|\(generatorVersion)|\(profileSeed)|\(block.rawValue)|\(formOrdinal)|\(exclusionIdentity)"
        )
        let candidates = makeCandidates(
            block: block,
            role: phase.role,
            profileSeed: profileSeed,
            formOrdinal: formOrdinal
        ).filter { !excludedDescriptorIDs.contains($0.id) }
        let desiredCount: Int
        let targetDuration: Int
        let maximumDuration: Int
        let minimumScorableItems: Int
        let itemCap: Int
        let targetInformation: Double
        switch phase {
        case .initialBaseline:
            desiredCount = NFAssessmentCatalog.minimumItemsPerDimension(
                for: phase.role,
                block: block
            ) * NFAssessmentCatalog.dimensions(for: block).count
            targetDuration = definition.targetDurationSeconds
            maximumDuration = definition.maximumDurationSeconds
            minimumScorableItems = definition.minimumScorableItems
            itemCap = definition.itemCap
            targetInformation = definition.targetInformation
        case .reassessment:
            desiredCount = NFAssessmentCatalog.minimumItemsPerDimension(
                for: phase.role,
                block: block
            ) * NFAssessmentCatalog.dimensions(for: block).count
            targetDuration = 300
            maximumDuration = 360
            minimumScorableItems = desiredCount
            itemCap = min(definition.itemCap, desiredCount + 2)
            targetInformation = definition.targetInformation
                * Double(desiredCount) / Double(definition.minimumScorableItems)
        }

        var state = initialAdaptiveState(selfReportedDifficulty: selfReportedDifficulty)
        var items: [NFAssessmentItemDescriptor] = []
        while items.count < desiredCount,
              let next = NFAssessmentSelectionEngine.selectNext(
                from: candidates,
                block: block,
                role: phase.role,
                state: state,
                exposureLedger: exposureLedger,
                excludedLabs: excludedLabs,
                tieBreakSeed: selectionSeed &+ UInt64(items.count)
              ) {
            items.append(next)
            state = state.appending(next)
        }

        let sessionID = "nf.assessment.session.v\(generatorVersion).\(block.rawValue).\(formOrdinal).\(String(selectionSeed, radix: 16))"
        return NFAssessmentBlockSession(
            id: sessionID,
            definition: definition,
            phase: phase,
            formOrdinal: formOrdinal,
            selectionSeed: selectionSeed,
            targetDurationSeconds: targetDuration,
            maximumDurationSeconds: maximumDuration,
            minimumScorableItems: minimumScorableItems,
            itemCap: itemCap,
            targetInformation: targetInformation,
            candidatePool: candidates,
            items: items
        )
    }

    static func initialAdaptiveState(
        selfReportedDifficulty: Double = 0.5
    ) -> NFAdaptiveAssessmentState {
        let boundedDifficulty = min(0.999, max(0.001, selfReportedDifficulty))
        let initialTheta = log(boundedDifficulty / (1 - boundedDifficulty))
        return NFAdaptiveAssessmentState(
            theta: initialTheta,
            uncertainty: 1,
            dimensionTheta: Dictionary(
                uniqueKeysWithValues: NFAssessmentDimension.allCases.map { ($0, initialTheta) }
            ),
            dimensionUncertainty: Dictionary(
                uniqueKeysWithValues: NFAssessmentDimension.allCases.map { ($0, 1) }
            )
        )
    }

    /// Selects the next descriptor from the full protected candidate pool using
    /// the state produced by prior durable responses. Time is active time only;
    /// pauses and lifecycle interruptions must not be added by the caller.
    static func nextStep(
        in session: NFAssessmentBlockSession,
        state: NFAdaptiveAssessmentState,
        activeElapsedSeconds: Int,
        exposureLedger: NFHoldoutExposureLedger = NFHoldoutExposureLedger(),
        excludedLabs: Set<TrainingLab> = []
    ) -> NFAssessmentNextStep {
        let elapsed = max(0, activeElapsedSeconds)
        if elapsed >= session.maximumDurationSeconds {
            return .stop(.maximumActiveDurationReached)
        }
        if state.completedScorableItems >= session.itemCap {
            return .stop(.itemCapReached)
        }
        if state.completedScorableItems >= session.minimumScorableItems,
           session.hasSufficientEvidence(in: state),
           state.accumulatedInformation >= session.targetInformation {
            return .stop(.targetInformationReached)
        }

        let remainingSeconds = session.maximumDurationSeconds - elapsed
        let eligible = session.candidatePool.filter {
            $0.block == session.definition.kind
                && $0.role == session.phase.role
                && !state.selectedItemIDs.contains($0.id)
                && !excludedLabs.contains($0.lab)
                && !exposureLedger.contains($0)
        }
        guard !eligible.isEmpty else {
            return .stop(.candidatePoolExhausted)
        }
        let available = eligible.filter {
            $0.estimatedDurationSeconds <= remainingSeconds
        }
        guard !available.isEmpty else {
            return .stop(.maximumActiveDurationReached)
        }
        guard let next = NFAssessmentSelectionEngine.selectNext(
            from: available,
            block: session.definition.kind,
            role: session.phase.role,
            state: state,
            exposureLedger: exposureLedger,
            excludedLabs: excludedLabs,
            tieBreakSeed: session.selectionSeed &+ UInt64(state.completedScorableItems)
        ) else {
            return .stop(.candidatePoolExhausted)
        }
        return .continueWith(next)
    }

    /// Reconstructs the exact adaptive path from durable partial-credit outcomes.
    /// This is used for resume so unseen candidates remain unconsumed and
    /// selection stays reproducible across relaunches.
    static func replaying(
        credits: [Double],
        in session: NFAssessmentBlockSession,
        selfReportedDifficulty: Double = 0.5,
        activeElapsedSeconds: Int = 0,
        exposureLedger: NFHoldoutExposureLedger = NFHoldoutExposureLedger(),
        excludedLabs: Set<TrainingLab> = []
    ) -> NFAdaptiveAssessmentState {
        var state = initialAdaptiveState(selfReportedDifficulty: selfReportedDifficulty)
        for (index, credit) in credits.enumerated() {
            let elapsedBeforeItem = credits.isEmpty
                ? 0
                : max(0, activeElapsedSeconds) * index / credits.count
            let step = nextStep(
                in: session,
                state: state,
                activeElapsedSeconds: min(elapsedBeforeItem, session.maximumDurationSeconds - 1),
                exposureLedger: exposureLedger,
                excludedLabs: excludedLabs
            )
            guard let item = step.item else { break }
            state = state
                .appending(item)
                .recordingResponse(to: item, credit: credit)
        }
        return state
    }

    /// Replays the durable descriptor path directly when checkpoint metadata is
    /// available. This avoids inferring a prior selection from aggregate time and
    /// keeps template, format, mechanic, and seed identity exact after relaunch.
    static func replaying(
        credits: [Double],
        descriptorIDs: [String],
        in session: NFAssessmentBlockSession,
        selfReportedDifficulty: Double = 0.5
    ) -> NFAdaptiveAssessmentState {
        guard credits.count == descriptorIDs.count else {
            return replaying(
                credits: credits,
                in: session,
                selfReportedDifficulty: selfReportedDifficulty
            )
        }

        let candidatesByID = Dictionary(
            uniqueKeysWithValues: session.candidatePool.map { ($0.id, $0) }
        )
        var state = initialAdaptiveState(selfReportedDifficulty: selfReportedDifficulty)
        for (descriptorID, credit) in zip(descriptorIDs, credits) {
            guard let item = candidatesByID[descriptorID],
                  item.block == session.definition.kind,
                  item.role == session.phase.role else {
                return replaying(
                    credits: credits,
                    in: session,
                    selfReportedDifficulty: selfReportedDifficulty
                )
            }
            state = state
                .appending(item)
                .recordingResponse(to: item, credit: credit)
        }
        return state
    }

    /// Compatibility overload for callers with legacy binary checkpoints.
    static func replaying(
        outcomes: [Bool],
        in session: NFAssessmentBlockSession,
        selfReportedDifficulty: Double = 0.5,
        activeElapsedSeconds: Int = 0,
        exposureLedger: NFHoldoutExposureLedger = NFHoldoutExposureLedger(),
        excludedLabs: Set<TrainingLab> = []
    ) -> NFAdaptiveAssessmentState {
        replaying(
            credits: outcomes.map { $0 ? 1 : 0 },
            in: session,
            selfReportedDifficulty: selfReportedDifficulty,
            activeElapsedSeconds: activeElapsedSeconds,
            exposureLedger: exposureLedger,
            excludedLabs: excludedLabs
        )
    }

    static func makePracticeCandidates(
        block: NFAssessmentBlockKind,
        seed: UInt64
    ) -> [NFAssessmentItemDescriptor] {
        makeCandidates(block: block, role: .practice, profileSeed: seed, formOrdinal: 0)
    }

    private static func makeCandidates(
        block: NFAssessmentBlockKind,
        role: NFAssessmentContentRole,
        profileSeed: UInt64,
        formOrdinal: Int
    ) -> [NFAssessmentItemDescriptor] {
        let templates = templateSpecs(for: block)
        precondition(templates.allSatisfy { $0.dimension.block == block })
        var candidates: [NFAssessmentItemDescriptor] = []
        for template in templates {
            for variant in 0..<4 {
                var probe = 0
                var itemSeed: UInt64
                repeat {
                    itemSeed = NFStableDeterminism.hash64(
                        "item|\(generatorVersion)|\(profileSeed)|\(formOrdinal)|\(role.rawValue)|\(template.dimension.rawValue)|\(template.subskillID)|\(template.format.rawValue)|\(variant)|\(probe)"
                    )
                    probe += 1
                } while candidates.contains(where: { $0.seed == itemSeed })

                let templateFamily = "nf.assessment.\(role.namespaceComponent).\(block.rawValue).\(template.dimension.rawValue).\(template.subskillID).\(template.format.rawValue).v2"
                let jitter = NFStableDeterminism.unitInterval(itemSeed) * 0.18 - 0.09
                let difficulty = min(0.95, max(0.05, template.baseDifficulty + jitter + Double(variant - 1) * 0.06))
                let itemID = "\(templateFamily):\(String(itemSeed, radix: 16))"
                let expectedInformation = 0.72 + 0.22 * (1 - abs(0.5 - difficulty))
                let descriptor = NFAssessmentItemDescriptor(
                    id: itemID,
                    templateFamily: templateFamily,
                    seed: itemSeed,
                    block: block,
                    role: role,
                    lab: template.lab,
                    dimension: template.dimension,
                    subskillID: template.subskillID,
                    format: template.format,
                    mechanicID: template.mechanicID,
                    difficulty: difficulty,
                    expectedInformation: expectedInformation,
                    estimatedDurationSeconds: template.estimatedDurationSeconds
                )
                candidates.append(descriptor)
            }
        }
        return candidates
    }

    private struct TemplateSpec {
        let dimension: NFAssessmentDimension
        let lab: TrainingLab
        let subskillID: String
        let format: NFAssessmentItemFormat
        let mechanicID: String
        let baseDifficulty: Double
        let estimatedDurationSeconds: Int
    }

    private static func templateSpecs(for block: NFAssessmentBlockKind) -> [TemplateSpec] {
        switch block {
        case .numericalFluency:
            return [
                fallbackTemplate(.mentalArithmetic, .mentalMath, "fact_retrieval", .numericEntry, variant: 0, prefix: "numerical", difficulty: 0.34, seconds: 15),
                fallbackTemplate(.mentalArithmetic, .mentalMath, "decomposition", .numericEntry, variant: 1, prefix: "numerical", difficulty: 0.48, seconds: 18),
                fallbackTemplate(.mentalArithmetic, .mentalMath, "error_detection", .singleChoice, variant: 5, prefix: "numerical", difficulty: 0.52, seconds: 18),
                fallbackTemplate(.mentalArithmetic, .mentalMath, "strategy_selection", .singleChoice, variant: 9, prefix: "numerical", difficulty: 0.56, seconds: 18),

                fallbackTemplate(.quantitativeEstimation, .quantitative, "fermi_magnitude", .numericEntry, variant: 1, prefix: "quantitative", difficulty: 0.46, seconds: 20),
                fallbackTemplate(.quantitativeEstimation, .quantitative, "factor_estimation", .numericEntry, variant: 1, prefix: "quantitative", difficulty: 0.58, seconds: 20),
                fallbackTemplate(.quantitativeEstimation, .mentalMath, "magnitude_selection", .singleChoice, variant: 7, prefix: "numerical", difficulty: 0.44, seconds: 18),
                fallbackTemplate(.quantitativeEstimation, .mentalMath, "plausibility_check", .singleChoice, variant: 7, prefix: "numerical", difficulty: 0.56, seconds: 18),

                fallbackTemplate(.probability, .quantitative, "base_rate", .numericEntry, variant: 4, prefix: "quantitative", difficulty: 0.52, seconds: 22),
                fallbackTemplate(.probability, .quantitative, "expected_value", .numericEntry, variant: 5, prefix: "quantitative", difficulty: 0.58, seconds: 22),
                fallbackTemplate(.probability, .quantitative, "base_rate_representation", .singleChoice, variant: 4, prefix: "quantitative", difficulty: 0.54, seconds: 20),
                fallbackTemplate(.probability, .quantitative, "expected_value_representation", .singleChoice, variant: 5, prefix: "quantitative", difficulty: 0.60, seconds: 20)
            ]
        case .spatialRepresentation:
            return [
                fallbackTemplate(.spatialTransformations, .spatial, "rotation", .diagramMatch, variant: 0, prefix: "spatial", difficulty: 0.44, seconds: 34),
                fallbackTemplate(.spatialTransformations, .spatial, "projection", .diagramMatch, variant: 2, prefix: "spatial", difficulty: 0.56, seconds: 36),
                fallbackTemplate(.spatialTransformations, .spatial, "view_matching", .singleChoice, variant: 1, prefix: "spatial", difficulty: 0.58, seconds: 36),
                fallbackTemplate(.spatialTransformations, .spatial, "coordinate_transform", .singleChoice, variant: 3, prefix: "spatial", difficulty: 0.50, seconds: 34)
            ]
        case .scientificDataReasoning:
            return [
                fallbackTemplate(.dataInterpretation, .scientificReasoning, "claim_scope", .claimEvidence, variant: 0, prefix: "scientific", difficulty: 0.50, seconds: 26),
                fallbackTemplate(.dataInterpretation, .scientificReasoning, "evidence_matching", .claimEvidence, variant: 0, prefix: "scientific", difficulty: 0.58, seconds: 28),
                fallbackTemplate(.dataInterpretation, .scientificReasoning, "uncertainty_figure", .singleChoice, variant: 3, prefix: "scientific", difficulty: 0.52, seconds: 26),
                fallbackTemplate(.dataInterpretation, .scientificReasoning, "figure_claim", .singleChoice, variant: 3, prefix: "scientific", difficulty: 0.60, seconds: 28),

                fallbackTemplate(.experimentalReasoning, .scientificReasoning, "confound", .singleChoice, variant: 1, prefix: "scientific", difficulty: 0.50, seconds: 26),
                fallbackTemplate(.experimentalReasoning, .scientificReasoning, "next_experiment", .singleChoice, variant: 2, prefix: "scientific", difficulty: 0.58, seconds: 28),
                fallbackTemplate(.experimentalReasoning, .scientificReasoning, "study_structure", .orderedSteps, variant: 7, prefix: "scientific", difficulty: 0.54, seconds: 26),
                fallbackTemplate(.experimentalReasoning, .scientificReasoning, "method_sequence", .orderedSteps, variant: 7, prefix: "scientific", difficulty: 0.62, seconds: 28)
            ]
        case .logicMetacognition:
            return [
                fallbackTemplate(.logic, .logicDebugging, "state_trace", .stateTrace, variant: 0, prefix: "logic", difficulty: 0.50, seconds: 24),
                fallbackTemplate(.logic, .logicDebugging, "invariant_trace", .stateTrace, variant: 0, prefix: "logic", difficulty: 0.60, seconds: 26),
                fallbackTemplate(.logic, .logicDebugging, "proof_order", .orderedSteps, variant: 3, prefix: "logic", difficulty: 0.52, seconds: 24),
                fallbackTemplate(.logic, .logicDebugging, "proof_dependency", .orderedSteps, variant: 3, prefix: "logic", difficulty: 0.62, seconds: 26),

                fallbackTemplate(.confidenceCalibration, .logicDebugging, "evidence_update", .singleChoice, variant: 8, prefix: "logic", difficulty: 0.46, seconds: 22),
                fallbackTemplate(.confidenceCalibration, .logicDebugging, "confidence_scope", .singleChoice, variant: 8, prefix: "logic", difficulty: 0.56, seconds: 24),
                fallbackTemplate(.confidenceCalibration, .logicDebugging, "calibration_sequence", .orderedSteps, variant: 8, prefix: "logic", difficulty: 0.50, seconds: 22),
                fallbackTemplate(.confidenceCalibration, .logicDebugging, "uncertainty_sequence", .orderedSteps, variant: 8, prefix: "logic", difficulty: 0.60, seconds: 24)
            ]
        }
    }

    private static func fallbackTemplate(
        _ dimension: NFAssessmentDimension,
        _ lab: TrainingLab,
        _ subskill: String,
        _ format: NFAssessmentItemFormat,
        variant: Int,
        prefix: String,
        difficulty: Double,
        seconds: Int
    ) -> TemplateSpec {
        return TemplateSpec(
            dimension: dimension,
            lab: lab,
            subskillID: subskill,
            format: format,
            mechanicID: "\(prefix).\(subskill).\(format.rawValue).fallback-variant-\(variant)",
            baseDifficulty: difficulty,
            estimatedDurationSeconds: seconds
        )
    }
}

// MARK: - Independent dimension reduction

enum NFAssessmentDimensionReducer {
    static func reduce(_ attempts: [AttemptDTO]) -> [SkillSummary] {
        NFAssessmentDimension.allCases.map { dimension in
            let relevant = attempts
                .filter {
                    $0.assessmentDimension == dimension
                        && $0.evidenceClass == .assessmentHoldout
                        && $0.evidenceWeight > 0
                }
                .sorted { lhs, rhs in
                    if lhs.submittedAt == rhs.submittedAt {
                        return lhs.id.uuidString < rhs.id.uuidString
                    }
                    return lhs.submittedAt < rhs.submittedAt
                }
            let scored = relevant.compactMap { attempt -> (AttemptDTO, Double)? in
                if dimension == .confidenceCalibration {
                    guard let confidence = attempt.confidence else { return nil }
                    return (attempt, 1 - abs(confidence.probability - attempt.credit))
                }
                return (attempt, attempt.credit)
            }

            var theta = 0.0
            for (index, observation) in scored.enumerated() {
                let expected = 1 / (1 + exp(-theta))
                let step = max(0.08, 0.34 / sqrt(Double(index + 1)))
                theta = min(3, max(-3, theta + step * (observation.1 - expected)))
            }

            let formats = Set(scored.compactMap { $0.0.assessmentFormat })
            let hasRequiredCoverage = scored.count >= NFAssessmentCatalog.minimumBaselineItemsPerDimension
                && formats.count >= NFAssessmentCatalog.minimumFormatsPerDimension
            let status: EstimateStatus
            if !hasRequiredCoverage {
                status = .unassessed
            } else if scored.count < 20 {
                status = .developing
            } else {
                status = .stable
            }

            let totalWeight = scored.reduce(0) { $0 + $1.0.evidenceWeight }
            let accuracy = totalWeight == 0 ? nil : scored.reduce(0) {
                $0 + $1.0.credit * $1.0.evidenceWeight
            } / totalWeight
            let confidencePairs = relevant.compactMap { attempt -> (Double, Double)? in
                guard let confidence = attempt.confidence else { return nil }
                return (confidence.probability, attempt.credit)
            }
            let calibrationBias = confidencePairs.isEmpty ? nil : confidencePairs.reduce(0) {
                $0 + $1.0 - $1.1
            } / Double(confidencePairs.count)
            let baseUncertainty = scored.isEmpty ? 1 : max(0.12, 1 / sqrt(Double(scored.count)))
            let uncertainty = formats.count < NFAssessmentCatalog.minimumFormatsPerDimension
                ? max(0.72, baseUncertainty)
                : baseUncertainty

            return SkillSummary(
                id: dimension.skillID,
                lab: dimension.lab,
                theta: theta,
                uncertainty: uncertainty,
                evidenceCount: scored.count,
                accuracy: accuracy,
                status: status,
                calibrationBias: calibrationBias,
                lastTrained: scored.last?.0.submittedAt
            )
        }
    }
}

/// This is the only selector ordinary training code needs. Its role predicate is
/// intentionally non-configurable: a caller cannot accidentally request a
/// baseline or holdout family for practice.
enum NFPracticeItemSelector {
    static func select(
        from candidates: [NFAssessmentItemDescriptor],
        seed: UInt64,
        excluding itemIDs: Set<String> = []
    ) -> NFAssessmentItemDescriptor? {
        candidates
            .filter {
                $0.role == .practice
                    && !$0.isProtectedAssessment
                    && $0.assessmentWeight == 0
                    && $0.templateFamily.contains(".practice.")
                    && !itemIDs.contains($0.id)
            }
            .sorted { lhs, rhs in
                let left = NFStableDeterminism.hash64("practice|\(seed)|\(lhs.id)")
                let right = NFStableDeterminism.hash64("practice|\(seed)|\(rhs.id)")
                if left != right { return left < right }
                return lhs.id < rhs.id
            }
            .first
    }
}

// MARK: - Stable deterministic utilities

enum NFStableDeterminism {
    static func hash64(_ string: String) -> UInt64 {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in string.utf8 {
            hash ^= UInt64(byte)
            hash &*= 0x0000_0100_0000_01B3
        }
        return hash
    }

    static func unitInterval(_ value: UInt64) -> Double {
        Double(value >> 11) / Double(UInt64(1) << 53)
    }

    static func clampedUnit(_ value: Double) -> Double {
        min(1, max(0, value.isFinite ? value : 0))
    }
}

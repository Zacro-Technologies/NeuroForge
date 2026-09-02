import Foundation

// MARK: - Local personalization snapshot

/// A deliberately coarse description of how much eligible evidence is
/// available for one lab. Exact attempt counts never leave the builder.
enum NFAdaptiveEvidenceBand: String, Codable, Equatable, Sendable {
    case none
    case sparse
    case developing
    case established
}

/// A bounded interpretation of recent deterministic credit in one named lab.
/// This is not a cognitive trait or a replacement for the progress engine.
enum NFAdaptivePerformanceBand: String, Codable, Equatable, Sendable {
    case unknown
    case needsSupport
    case developing
    case secure
}

enum NFAdaptiveTrendBand: String, Codable, Equatable, Sendable {
    case unknown
    case declining
    case steady
    case improving
}

enum NFAdaptiveCalibrationBand: String, Codable, Equatable, Sendable {
    case unknown
    case underconfident
    case aligned
    case overconfident
}

enum NFAdaptiveReviewBand: String, Codable, Equatable, Sendable {
    case neverPracticed
    case current
    case revisitSoon
    case reviewDue
}

enum NFAdaptiveSessionLengthBand: String, Codable, Equatable, Sendable {
    case brief
    case standard
    case extended
}

struct NFAdaptiveLabAggregate: Codable, Equatable, Sendable {
    let lab: TrainingLab
    let evidence: NFAdaptiveEvidenceBand
    let performance: NFAdaptivePerformanceBand
    let trend: NFAdaptiveTrendBand
    let calibration: NFAdaptiveCalibrationBand
    let review: NFAdaptiveReviewBand
}

/// The only performance/profile representation intended for an adaptive
/// generation payload. It contains finite enums and coarse aggregates only:
/// never profile/attempt IDs, item text, answers, exact counts, or dates.
struct NFAdaptivePersonalizationSnapshot: Codable, Equatable, Sendable {
    static let schemaVersion = 1

    let schemaVersion: Int
    let stage: Stage
    let preferredFields: [STEMField]
    let goals: [TrainingGoal]
    let sessionLength: NFAdaptiveSessionLengthBand
    let timingPreference: TimingMode
    let labs: [NFAdaptiveLabAggregate]
}

/// Pure, in-memory reduction of persisted learner data. The builder reads only
/// fields needed for its coarse aggregates and retains no SwiftData records.
enum NFLocalPersonalizationSnapshotBuilder {
    static let maximumAttemptsConsideredPerLab = 24
    static let maximumPreferredFields = 4
    static let maximumGoals = 4

    static func makeSnapshot(
        profile: ProfileSnapshot,
        attempts: [AttemptRecord],
        referenceDate: Date = .now
    ) -> NFAdaptivePersonalizationSnapshot {
        let eligibleByLab = Dictionary(grouping: attempts.compactMap(eligibleSignal)) {
            $0.lab
        }

        let labAggregates = TrainingLab.allCases.map { lab in
            let recent = Array(
                (eligibleByLab[lab] ?? [])
                    .sorted(by: signalOrder)
                    .suffix(maximumAttemptsConsideredPerLab)
            )
            return NFAdaptiveLabAggregate(
                lab: lab,
                evidence: evidenceBand(for: recent.count),
                performance: performanceBand(for: recent),
                trend: trendBand(for: recent),
                calibration: calibrationBand(for: recent),
                review: reviewBand(for: recent, referenceDate: referenceDate)
            )
        }

        return NFAdaptivePersonalizationSnapshot(
            schemaVersion: NFAdaptivePersonalizationSnapshot.schemaVersion,
            stage: profile.stage,
            preferredFields: Array(
                STEMField.allCases
                    .filter(profile.fields.contains)
                    .prefix(maximumPreferredFields)
            ),
            goals: Array(
                TrainingGoal.allCases
                    .filter(profile.goals.contains)
                    .prefix(maximumGoals)
            ),
            sessionLength: sessionLengthBand(minutes: profile.dailyDuration),
            timingPreference: profile.timingMode,
            labs: labAggregates
        )
    }

    private struct EligibleSignal {
        let lab: TrainingLab
        let credit: Double
        let weight: Double
        let confidence: Double?
        let submittedAt: Date
    }

    private static func eligibleSignal(_ attempt: AttemptRecord) -> EligibleSignal? {
        guard !attempt.wasSkipped,
              let lab = TrainingLab(rawValue: attempt.gameID),
              let evidenceClass = EvidenceClass(rawValue: attempt.evidenceClassRaw),
              evidenceClass != .documentPractice,
              attempt.evidenceWeight.isFinite,
              attempt.evidenceWeight > 0,
              attempt.deterministicCredit.isFinite else {
            return nil
        }

        return EligibleSignal(
            lab: lab,
            credit: min(1, max(0, attempt.deterministicCredit)),
            weight: min(1, max(0, attempt.evidenceWeight)),
            confidence: attempt.confidenceRaw
                .flatMap(ConfidenceLevel.init(rawValue:))?
                .probability,
            submittedAt: attempt.submittedAt
        )
    }

    private static func signalOrder(_ lhs: EligibleSignal, _ rhs: EligibleSignal) -> Bool {
        if lhs.submittedAt != rhs.submittedAt { return lhs.submittedAt < rhs.submittedAt }
        if lhs.credit != rhs.credit { return lhs.credit < rhs.credit }
        if lhs.weight != rhs.weight { return lhs.weight < rhs.weight }
        return (lhs.confidence ?? -1) < (rhs.confidence ?? -1)
    }

    private static func evidenceBand(for count: Int) -> NFAdaptiveEvidenceBand {
        switch count {
        case 0: .none
        case 1..<4: .sparse
        case 4..<10: .developing
        default: .established
        }
    }

    private static func performanceBand(
        for signals: [EligibleSignal]
    ) -> NFAdaptivePerformanceBand {
        guard let credit = weightedCredit(signals) else { return .unknown }
        if credit < 0.50 { return .needsSupport }
        if credit < 0.78 { return .developing }
        return .secure
    }

    private static func trendBand(for signals: [EligibleSignal]) -> NFAdaptiveTrendBand {
        guard signals.count >= 6 else { return .unknown }
        let earlier = Array(signals.suffix(6).prefix(3))
        let later = Array(signals.suffix(3))
        guard let earlierCredit = weightedCredit(earlier),
              let laterCredit = weightedCredit(later) else {
            return .unknown
        }
        let change = laterCredit - earlierCredit
        if change >= 0.15 { return .improving }
        if change <= -0.15 { return .declining }
        return .steady
    }

    private static func calibrationBand(
        for signals: [EligibleSignal]
    ) -> NFAdaptiveCalibrationBand {
        let withConfidence = signals.compactMap { signal -> (Double, Double, Double)? in
            guard let confidence = signal.confidence else { return nil }
            return (signal.credit, confidence, signal.weight)
        }
        guard withConfidence.count >= 3 else { return .unknown }
        let weight = withConfidence.reduce(0) { $0 + $1.2 }
        guard weight > 0 else { return .unknown }
        let credit = withConfidence.reduce(0) { $0 + $1.0 * $1.2 } / weight
        let confidence = withConfidence.reduce(0) { $0 + $1.1 * $1.2 } / weight
        let difference = confidence - credit
        if difference >= 0.15 { return .overconfident }
        if difference <= -0.15 { return .underconfident }
        return .aligned
    }

    private static func reviewBand(
        for signals: [EligibleSignal],
        referenceDate: Date
    ) -> NFAdaptiveReviewBand {
        guard let latest = signals.last?.submittedAt else { return .neverPracticed }
        let age = max(0, referenceDate.timeIntervalSince(latest))
        if age < 2 * 86_400 { return .current }
        if age < 7 * 86_400 { return .revisitSoon }
        return .reviewDue
    }

    private static func sessionLengthBand(minutes: Int) -> NFAdaptiveSessionLengthBand {
        if minutes <= 5 { return .brief }
        if minutes <= 15 { return .standard }
        return .extended
    }

    private static func weightedCredit(_ signals: [EligibleSignal]) -> Double? {
        let weight = signals.reduce(0) { $0 + $1.weight }
        guard weight > 0 else { return nil }
        return signals.reduce(0) { $0 + $1.credit * $1.weight } / weight
    }
}

// MARK: - Bounded source context

struct NFExplicitSourceConsent: Equatable, Sendable {
    static let currentPolicyVersion = 1

    let policyVersion: Int

    private init(policyVersion: Int) {
        self.policyVersion = policyVersion
    }

    /// Produces a consent value only for an affirmative acknowledgement of the
    /// current policy. Callers must derive `explicitlyGranted` from durable UI
    /// state; AI-mode selection alone is not consent to share source text.
    static func make(
        explicitlyGranted: Bool,
        policyVersion: Int = currentPolicyVersion
    ) -> NFExplicitSourceConsent? {
        guard explicitlyGranted, policyVersion == currentPolicyVersion else { return nil }
        return NFExplicitSourceConsent(policyVersion: policyVersion)
    }
}

enum NFAdaptiveSourceMode: String, Codable, Equatable, Sendable {
    case sourceFree
    case explicitlyConsented
}

enum NFAdaptiveSourceContextError: Error, Equatable, Sendable {
    case noExcerpts
    case tooManyExcerpts
    case emptyExcerpt
    case excerptTooLong
    case totalContextTooLong
    case unsupportedControlCharacter
}

/// Source text is absent by default. The only source-bearing value requires an
/// explicit consent value and rejects, rather than silently truncates, content
/// outside the fixed context budget.
struct NFAdaptiveSourceContext: Codable, Equatable, Sendable {
    static let maximumExcerptCount = 4
    static let maximumCharactersPerExcerpt = 1_600
    static let maximumTotalCharacters = 4_800

    let mode: NFAdaptiveSourceMode
    let consentPolicyVersion: Int?
    let excerpts: [String]

    static let sourceFree = NFAdaptiveSourceContext(
        mode: .sourceFree,
        consentPolicyVersion: nil,
        excerpts: []
    )

    private init(
        mode: NFAdaptiveSourceMode,
        consentPolicyVersion: Int?,
        excerpts: [String]
    ) {
        self.mode = mode
        self.consentPolicyVersion = consentPolicyVersion
        self.excerpts = excerpts
    }

    static func explicitlyConsented(
        excerpts: [String],
        consent: NFExplicitSourceConsent
    ) throws -> NFAdaptiveSourceContext {
        guard !excerpts.isEmpty else { throw NFAdaptiveSourceContextError.noExcerpts }
        guard excerpts.count <= maximumExcerptCount else {
            throw NFAdaptiveSourceContextError.tooManyExcerpts
        }

        var bounded: [String] = []
        bounded.reserveCapacity(excerpts.count)
        for excerpt in excerpts {
            let trimmed = excerpt.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { throw NFAdaptiveSourceContextError.emptyExcerpt }
            guard trimmed.count <= maximumCharactersPerExcerpt else {
                throw NFAdaptiveSourceContextError.excerptTooLong
            }
            guard !containsUnsupportedControlCharacter(trimmed) else {
                throw NFAdaptiveSourceContextError.unsupportedControlCharacter
            }
            bounded.append(trimmed)
        }

        guard bounded.reduce(0, { $0 + $1.count }) <= maximumTotalCharacters else {
            throw NFAdaptiveSourceContextError.totalContextTooLong
        }
        return NFAdaptiveSourceContext(
            mode: .explicitlyConsented,
            consentPolicyVersion: consent.policyVersion,
            excerpts: bounded
        )
    }

    private static func containsUnsupportedControlCharacter(_ value: String) -> Bool {
        value.unicodeScalars.contains { scalar in
            guard CharacterSet.controlCharacters.contains(scalar) else { return false }
            return scalar != "\n" && scalar != "\r" && scalar != "\t"
        }
    }
}

// MARK: - Catalog floor and generation policy

struct NFBundledQuestionFloorDeficit: Equatable, Sendable {
    let lab: TrainingLab
    let availableUniqueQuestions: Int
    let requiredUniqueQuestions: Int
}

/// Local audit evidence for the bundled catalog. Only normalized fingerprints
/// are counted, so duplicate content cannot inflate the release floor.
struct NFBundledQuestionFloorEvidence: Equatable, Sendable {
    static let requiredUniqueQuestionsPerLab = 1_000
    static let maximumFingerprintLength = 256

    let catalogIntegrityVerified: Bool
    private let uniqueCounts: [TrainingLab: Int]

    static let unverified = NFBundledQuestionFloorEvidence(
        uniqueQuestionFingerprintsByLab: [:],
        catalogIntegrityVerified: false
    )

    init(
        uniqueQuestionFingerprintsByLab: [TrainingLab: [String]],
        catalogIntegrityVerified: Bool
    ) {
        self.catalogIntegrityVerified = catalogIntegrityVerified
        uniqueCounts = Dictionary(uniqueKeysWithValues: TrainingLab.allCases.map { lab in
            let normalized = uniqueQuestionFingerprintsByLab[lab, default: []]
                .compactMap(Self.normalizedFingerprint)
            return (lab, Set(normalized).count)
        })
    }

    func uniqueQuestionCount(for lab: TrainingLab) -> Int {
        uniqueCounts[lab, default: 0]
    }

    var deficits: [NFBundledQuestionFloorDeficit] {
        TrainingLab.allCases.compactMap { lab in
            let available = uniqueQuestionCount(for: lab)
            guard available < Self.requiredUniqueQuestionsPerLab else { return nil }
            return NFBundledQuestionFloorDeficit(
                lab: lab,
                availableUniqueQuestions: available,
                requiredUniqueQuestions: Self.requiredUniqueQuestionsPerLab
            )
        }
    }

    var satisfiesReleaseFloor: Bool {
        catalogIntegrityVerified && deficits.isEmpty
    }

    private static func normalizedFingerprint(_ value: String) -> String? {
        let normalized = value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard !normalized.isEmpty, normalized.count <= maximumFingerprintLength else {
            return nil
        }
        return normalized
    }
}

struct NFOffDevicePersonalizationConsent: Equatable, Sendable {
    static let currentPolicyVersion = 1

    let policyVersion: Int

    private init(policyVersion: Int) {
        self.policyVersion = policyVersion
    }

    static func make(
        explicitlyGranted: Bool,
        policyVersion: Int = currentPolicyVersion
    ) -> NFOffDevicePersonalizationConsent? {
        guard explicitlyGranted, policyVersion == currentPolicyVersion else { return nil }
        return NFOffDevicePersonalizationConsent(policyVersion: policyVersion)
    }
}

/// Platform-neutral destinations only. This policy intentionally has no
/// dependency on a model framework or on a future SDK-only provider type.
enum NFAdaptiveGenerationDestination: String, Equatable, Sendable {
    case onDevice
    case privateCloud
}

struct NFAdaptiveGenerationPayload: Codable, Equatable, Sendable {
    static let schemaVersion = 1

    let schemaVersion: Int
    let personalization: NFAdaptivePersonalizationSnapshot
    let sourceContext: NFAdaptiveSourceContext
}

enum NFAdaptiveQuestionPopulationBlocker: Equatable, Sendable {
    case catalogIntegrityUnverified
    case bundledQuestionFloorNotMet([NFBundledQuestionFloorDeficit])
    case aiDisabled
    case destinationDisallowedByPreference
    case offDevicePersonalizationConsentRequired
}

struct NFAdaptiveQuestionPopulationDecision: Equatable, Sendable {
    let blockers: [NFAdaptiveQuestionPopulationBlocker]
    let payload: NFAdaptiveGenerationPayload?

    var isEligible: Bool { blockers.isEmpty && payload != nil }
}

/// Fail-closed entry point for adaptive population. A safe payload is created
/// only after every bundled lab has a verified 1,000-question floor and the
/// learner's route/privacy preferences permit the requested destination.
enum NFAdaptiveQuestionPopulationPolicy {
    static func evaluate(
        destination: NFAdaptiveGenerationDestination,
        profile: ProfileSnapshot,
        attempts: [AttemptRecord],
        bundledFloor: NFBundledQuestionFloorEvidence,
        sourceContext: NFAdaptiveSourceContext = .sourceFree,
        offDeviceConsent: NFOffDevicePersonalizationConsent? = nil,
        referenceDate: Date = .now
    ) -> NFAdaptiveQuestionPopulationDecision {
        var blockers: [NFAdaptiveQuestionPopulationBlocker] = []
        if !bundledFloor.catalogIntegrityVerified {
            blockers.append(.catalogIntegrityUnverified)
        }
        let deficits = bundledFloor.deficits
        if !deficits.isEmpty {
            blockers.append(.bundledQuestionFloorNotMet(deficits))
        }
        if profile.aiMode == .disabled {
            blockers.append(.aiDisabled)
        } else if destination == .privateCloud, profile.aiMode != .automatic {
            blockers.append(.destinationDisallowedByPreference)
        }
        if destination == .privateCloud, offDeviceConsent == nil {
            blockers.append(.offDevicePersonalizationConsentRequired)
        }

        guard blockers.isEmpty else {
            return NFAdaptiveQuestionPopulationDecision(blockers: blockers, payload: nil)
        }

        let personalization = NFLocalPersonalizationSnapshotBuilder.makeSnapshot(
            profile: profile,
            attempts: attempts,
            referenceDate: referenceDate
        )
        return NFAdaptiveQuestionPopulationDecision(
            blockers: [],
            payload: NFAdaptiveGenerationPayload(
                schemaVersion: NFAdaptiveGenerationPayload.schemaVersion,
                personalization: personalization,
                sourceContext: sourceContext
            )
        )
    }
}

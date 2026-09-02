import Foundation

/// The learner-facing shape of a bundled activity. These labels describe the
/// interaction, not a cognitive trait: puzzle performance remains evidence for
/// the named mechanic and never becomes a general "brain score."
enum NFDefaultActivityKind: String, CaseIterable, Identifiable, Sendable {
    case practice
    case puzzle
    case investigation
    case reconstruction
    case transfer

    var id: String { rawValue }

    var title: String { localizedTitle(locale: NFAppLocalization.preferredLocale) }

    func localizedTitle(locale: Locale) -> String {
        let japanese = locale.identifier.lowercased().hasPrefix("ja")
        return switch self {
        case .practice: japanese ? "練習" : "Practice"
        case .puzzle: japanese ? "パズル" : "Puzzle"
        case .investigation: japanese ? "探究" : "Investigation"
        case .reconstruction: japanese ? "再構成" : "Reconstruction"
        case .transfer: japanese ? "転移課題" : "Transfer challenge"
        }
    }

    var symbol: String {
        switch self {
        case .practice: "scope"
        case .puzzle: "puzzlepiece.extension.fill"
        case .investigation: "magnifyingglass"
        case .reconstruction: "arrow.trianglehead.2.clockwise.rotate.90"
        case .transfer: "arrow.triangle.swap"
        }
    }
}

/// A reviewed source that supports one specific catalog design choice. The app
/// shows author/year labels and opens the primary record instead of exposing an
/// opaque internal identifier by itself.
enum NFDefaultContentReference: String, CaseIterable, Identifiable, Sendable {
    case uttal2013 = "SCI-03"
    case roedigerKarpicke2006 = "SCI-04"
    case cepeda2006 = "SCI-05"
    case alfieri2013 = "SCI-07"
    case mcdowellJacobs2017 = "SCI-08"

    var id: String { rawValue }

    var shortCitation: String {
        switch self {
        case .uttal2013: "Uttal et al. (2013)"
        case .roedigerKarpicke2006: "Roediger & Karpicke (2006)"
        case .cepeda2006: "Cepeda et al. (2006)"
        case .alfieri2013: "Alfieri et al. (2013)"
        case .mcdowellJacobs2017: "McDowell & Jacobs (2017)"
        }
    }

    var url: URL {
        switch self {
        case .uttal2013:
            URL(string: "https://pubmed.ncbi.nlm.nih.gov/22663761/")!
        case .roedigerKarpicke2006:
            URL(string: "https://doi.org/10.1111/j.1467-9280.2006.01693.x")!
        case .cepeda2006:
            URL(string: "https://pubmed.ncbi.nlm.nih.gov/16719566/")!
        case .alfieri2013:
            URL(string: "https://doi.org/10.1080/00461520.2013.775712")!
        case .mcdowellJacobs2017:
            URL(string: "https://pubmed.ncbi.nlm.nih.gov/29048176/")!
        }
    }
}

/// A conservative evidence note shown beside catalog activities. A reference
/// is attached only when it directly supports the named design choice. An empty
/// reference list means the copy is a product evidence boundary, not a research
/// efficacy claim.
enum NFDefaultContentResearchBasis: String, CaseIterable, Sendable {
    case scopeOnly
    case spatialPractice
    case retrievalAndSpacing
    case structureMapping
    case naturalFrequencyBayes

    var references: [NFDefaultContentReference] {
        switch self {
        case .scopeOnly: []
        case .spatialPractice: [.uttal2013]
        case .retrievalAndSpacing: [.roedigerKarpicke2006, .cepeda2006]
        case .structureMapping: [.alfieri2013]
        case .naturalFrequencyBayes: [.mcdowellJacobs2017]
        }
    }

    var referenceIDs: [String] { references.map(\.id) }

    var localizedTitle: String {
        localizedTitle(locale: NFAppLocalization.preferredLocale)
    }

    var localizedNote: String {
        localizedNote(locale: NFAppLocalization.preferredLocale)
    }

    func localizedTitle(locale: Locale) -> String {
        let japanese = locale.identifier.lowercased().hasPrefix("ja")
        return switch self {
        case .scopeOnly: japanese ? "証拠の範囲" : "Evidence limits"
        case .spatialPractice: japanese ? "空間課題の研究" : "Spatial-practice research"
        case .retrievalAndSpacing: japanese ? "想起練習と分散学習" : "Retrieval and spacing"
        case .structureMapping: japanese ? "構造比較の研究" : "Structural comparison"
        case .naturalFrequencyBayes: japanese ? "自然頻度による表現" : "Natural-frequency representation"
        }
    }

    func localizedNote(locale: Locale) -> String {
        let japanese = locale.identifier.lowercased().hasPrefix("ja")
        return switch self {
        case .scopeOnly:
            japanese
                ? "フィードバックは、この明示された課題だけを対象にします。成績の向上を、一般知能や遠い転移の証拠とはみなしません。"
                : "Feedback targets this named mechanic. Gains are not treated as evidence of general intelligence or far transfer."
        case .spatialPractice:
            japanese
                ? "空間スキルは平均的には訓練可能ですが、NeuroForge は未見の図形や表現への転移を別に確認します。"
                : "Spatial skills are trainable on average; NeuroForge still checks transfer to unfamiliar forms separately."
        case .retrievalAndSpacing:
            japanese
                ? "答えを見る前の想起と、時間をあけた再確認は保持を支えます。出典に基づく課題は標準化された進捗とは分けて扱います。"
                : "Retrieval before review and later rechecking support retention. Source-grounded work stays separate from standardized progress."
        case .structureMapping:
            japanese
                ? "構造が対応する事例の比較は学習を支えます。この課題は練習として記録し、未見形式での転移は別に測定します。"
                : "Comparing structurally analogous cases can support learning. This activity remains practice; transfer to unfamiliar forms is measured separately."
        case .naturalFrequencyBayes:
            japanese
                ? "自然頻度による表現はベイズ推論を助けることがあります。この課題の成績は、ここで練習した形式に限定して扱います。"
                : "Natural-frequency formats can support Bayesian reasoning. Performance remains evidence for this practiced format only."
        }
    }
}

/// A reviewed entry point into one concrete deterministic generator family.
/// The marker at the end of `mechanicID` is consumed by
/// `NFFallbackExerciseGenerator.selectedVariant`, so choosing an activity
/// actually selects that mechanic instead of merely changing its display name.
struct NFDefaultContentActivity: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let japaneseTitle: String
    let summary: String
    let lab: TrainingLab
    let kind: NFDefaultActivityKind
    let variant: Int
    let templateSlug: String
    let defaultDifficulty: Double
    let recommendedMinutes: Int
    let researchBasis: NFDefaultContentResearchBasis
    let keywords: [String]

    var mechanicID: String {
        "catalog.v\(NFDefaultContentCatalog.version).\(lab.rawValue).\(templateSlug).fallback-variant-\(variant)"
    }

    /// Choosing a catalog entry is always learner-directed practice. Protected
    /// retention and transfer evidence is issued by the scheduler with an
    /// explicit origin, exposure policy, and assessment purpose.
    var defaultEvidenceClass: EvidenceClass { .practice }

    var localizedTitle: String {
        localizedTitle(locale: NFAppLocalization.preferredLocale)
    }

    var localizedSummary: String {
        localizedSummary(locale: NFAppLocalization.preferredLocale)
    }

    func localizedTitle(locale: Locale) -> String {
        locale.identifier.lowercased().hasPrefix("ja") ? japaneseTitle : title
    }

    func localizedSummary(locale: Locale) -> String {
        NFAppLocalization.localizedCatalogValue(summary, locale: locale)
    }
}

/// A concrete, user-selectable catalog lane. Keeping the field beside the
/// activity prevents the UI from advertising contextual lanes that silently
/// collapse to the profile's first field at launch time.
struct NFDefaultContentSelection: Equatable, Sendable {
    let activity: NFDefaultContentActivity
    let field: STEMField
}

/// The complete user-selectable offline catalog. Its 58 entries expose every
/// deterministic fallback family across all seven labs. Each family is seeded,
/// can be launched with any supported field perspective, and is rendered/scored
/// through the same universal session contract used by
/// Today. Field selection changes framing everywhere and scenario content only
/// where the underlying generator has a reviewed domain profile.
enum NFDefaultContentCatalog {
    static let version = 1

    static let activities: [NFDefaultContentActivity] = [
        // Mental mathematics — 10/10 generator variants.
        activity("mental.rapid-recall", "Rapid Recall", "即時想起", "Recall the fact directly; if it is not ready, split one factor and recombine exactly.", .mentalMath, .practice, 0, "rapid-recall", 0.30, .scopeOnly, ["facts", "multiplication", "fluency", "reconstruct"]),
        activity("mental.compensation", "Compensation Lab", "補償計算ラボ", "Multiply by a nearby round factor, then add or subtract one group.", .mentalMath, .practice, 1, "decompose.compensation", 0.42, .scopeOnly, ["compensation", "decomposition", "multiplication", "flexibility"]),
        activity("mental.representation-relay", "Representation Relay", "表現変換リレー", "A fraction, decimal, and percentage name the same ratio at different scales.", .mentalMath, .puzzle, 2, "representation-relay", 0.45, .scopeOnly, ["fraction", "decimal", "percentage", "representation"]),
        activity("mental.scientific-notation", "Scientific Notation Repair", "科学的記数法の修復", "Every decimal shift in the coefficient requires the opposite power-of-ten adjustment.", .mentalMath, .puzzle, 3, "scientific-notation", 0.48, .scopeOnly, ["scientific notation", "exponent", "place value", "repair"]),
        activity("mental.missing-factor", "Missing Factor", "未知の因数", "Isolate the unknown by reversing the stated operation.", .mentalMath, .puzzle, 4, "missing-number", 0.40, .scopeOnly, ["inverse", "missing number", "factor", "verify"]),
        activity("mental.error-detective", "Percent Error Detective", "パーセント誤り探し", "Check the percentage base and scale before inspecting later arithmetic.", .mentalMath, .puzzle, 5, "error-detective", 0.48, .scopeOnly, ["percent", "error", "audit", "plausibility"]),
        activity("mental.calculation-chain", "Calculation Chain", "連続計算", "Retain one exact intermediate value after every transformation.", .mentalMath, .puzzle, 6, "calculation-chain", 0.52, .scopeOnly, ["chain", "state", "operation order", "checkpoint"]),
        activity("mental.estimate-first", "Estimate First", "先に概算", "Round each factor to one useful digit and preserve the operation.", .mentalMath, .investigation, 7, "estimate-first", 0.50, .scopeOnly, ["estimate", "magnitude", "bounds", "plausibility"]),
        activity("mental.tool-judgment", "Mental or Machine?", "暗算かツールか", "Choose based on precision, repeat count, consequence of error, and auditability.", .mentalMath, .investigation, 8, "mental-or-machine", 0.56, .scopeOnly, ["tool", "spreadsheet", "calculator", "judgment"]),
        activity("mental.strategy-duel", "Strategy Duel", "解法の比較", "Prefer a valid shortcut whose compensation cost is smallest for the visible structure.", .mentalMath, .puzzle, 9, "strategy-duel", 0.56, .scopeOnly, ["strategy", "flexibility", "shortcut", "exact"]),

        // Spatial reasoning — 6/6 generator variants.
        activity("spatial.coordinate-rotation", "Coordinate Rotation", "座標回転", "Rotate a 2D coordinate counterclockwise while preserving its distance from the origin.", .spatial, .puzzle, 0, "coordinate.rotate-ccw", 0.42, .spatialPractice, ["coordinate", "rotation", "2d", "orientation"]),
        activity("spatial.object-rotation", "3D Object Rotation", "3D物体の回転", "Track labeled faces through a quarter-turn about a stated three-dimensional axis.", .spatial, .puzzle, 1, "rotation.3d-z-axis", 0.50, .spatialPractice, ["3d", "object", "axis", "rotation"]),
        activity("spatial.cross-section", "Cross-Section Puzzle", "断面パズル", "Infer the planar shape produced when a named solid is sliced by a stated plane.", .spatial, .puzzle, 2, "cross-section", 0.56, .spatialPractice, ["cross section", "solid", "plane", "geometry"]),
        activity("spatial.top-view", "Top-View Decoder", "上面図の解読", "Translate occupied positions into a top-view footprint without counting hidden height.", .spatial, .puzzle, 3, "orthographic.top-view", 0.52, .spatialPractice, ["orthographic", "projection", "top view", "diagram"]),
        activity("spatial.cube-net", "Cube-Net Puzzle", "立方体の展開図パズル", "Fold a validated cube net mentally and identify which labeled faces become opposite.", .spatial, .puzzle, 4, "folding.cube-net", 0.60, .spatialPractice, ["cube", "net", "folding", "opposite faces"]),
        activity("spatial.vector-reflection", "Vector Reflection", "ベクトルの反射", "Reflect a vector across the y-axis by changing its horizontal component and preserving its vertical component.", .spatial, .puzzle, 5, "vector.reflect-y-axis", 0.54, .spatialPractice, ["vector", "reflection", "axis", "transformation"]),

        // Quantitative intuition — 8/8 generator variants.
        activity("quantitative.proportion", "Observed Proportion", "観測割合", "Divide the part by the whole, then compare with familiar fractions before converting to percent.", .quantitative, .practice, 0, "observed.proportion", 0.40, .scopeOnly, ["proportion", "part", "whole", "percent"]),
        activity("quantitative.fermi", "Fermi Estimate", "フェルミ推定", "Express the unknown total as a product of explicit, auditable assumptions.", .quantitative, .investigation, 1, "fermi.decomposition", 0.48, .scopeOnly, ["fermi", "estimate", "assumption", "magnitude"]),
        activity("quantitative.unit-bridge", "Unit Bridge", "単位変換", "Multiply by a conversion ratio equal to one and cancel the original unit.", .quantitative, .practice, 2, "units.metric-conversion", 0.46, .scopeOnly, ["unit", "conversion", "dimension", "metric"]),
        activity("quantitative.scaling", "Scaling Law", "スケーリング則", "Apply the input multiplier through the direct, inverse, or power-law relationship before changing the output.", .quantitative, .practice, 3, "scaling", 0.55, .scopeOnly, ["scaling", "direct", "inverse", "power law"]),
        activity("quantitative.bayes", "Base-Rate Bayes", "ベースレートとベイズ", "Convert rates to counts, then divide true positives by every positive result.", .quantitative, .investigation, 4, "probability.bayes-natural-frequency", 0.58, .naturalFrequencyBayes, ["bayes", "base rate", "natural frequency", "conditional"]),
        activity("quantitative.expected-value", "Expected Value", "期待値", "Multiply each signed outcome by its probability and add the contributions.", .quantitative, .puzzle, 5, "probability.expected-value", 0.56, .scopeOnly, ["expected value", "probability", "outcome", "weight"]),
        activity("quantitative.regression", "Regression Detective", "平均への回帰を見抜く", "Extreme observations tend to be followed by less extreme observations when measurement contains noise.", .quantitative, .investigation, 6, "sampling.regression-to-mean", 0.60, .scopeOnly, ["regression to mean", "noise", "selection", "repeat"]),
        activity("quantitative.interval", "Interval Inspector", "区間推定の検討", "Identify the estimated quantity and the repeated-sampling or modeled procedure before interpreting an interval.", .quantitative, .investigation, 7, "uncertainty.interval-interpretation", 0.62, .scopeOnly, ["interval", "uncertainty", "estimate", "scope"]),

        // Scientific reasoning — 9/9 generator variants.
        activity("science.claim-evidence", "Claim–Evidence Bounds", "主張と証拠の範囲", "Check whether the design and observation support descriptive, causal, or universal language.", .scientificReasoning, .investigation, 0, "claim.evidence.bounds", 0.52, .scopeOnly, ["claim", "evidence", "causal", "scope"]),
        activity("science.confound", "Confound Hunter", "交絡因子を見つける", "A confound predicts both exposure assignment and the outcome through paths outside the intended effect.", .scientificReasoning, .investigation, 1, "design.identify-confound", 0.54, .scopeOnly, ["confound", "common cause", "assignment", "outcome"]),
        activity("science.next-experiment", "Next Discriminating Experiment", "仮説を見分ける次の実験", "Choose a manipulation and measurement for which the hypotheses predict different observations.", .scientificReasoning, .investigation, 2, "design.next-discriminating-experiment", 0.60, .scopeOnly, ["experiment", "hypothesis", "prediction", "information"]),
        activity("science.figure-uncertainty", "Figure Uncertainty Audit", "図の不確かさを監査", "Match a figure's summary, uncertainty display, and raw-data access to the strength of its claim.", .scientificReasoning, .investigation, 3, "data-forensics.uncertainty", 0.58, .scopeOnly, ["figure", "uncertainty", "raw data", "claim"]),
        activity("science.bias-repair", "Bias Repair", "バイアスを減らす設計", "Use assignment, measurement, and replication safeguards for different validity threats.", .scientificReasoning, .investigation, 4, "design.repair-bias", 0.62, .scopeOnly, ["bias", "randomization", "blinding", "replication"]),
        activity("science.competing-predictions", "Competing Predictions", "競合する予測", "Prefer evidence that one hypothesis expects and the rival does not.", .scientificReasoning, .investigation, 5, "competing-hypotheses.prediction", 0.64, .scopeOnly, ["hypothesis", "prediction", "rival", "evidence"]),
        activity("science.reviewer", "Reviewer Mode", "査読者モード", "Audit assignment, measurement, analysis, presentation, and reproducibility as distinct dimensions.", .scientificReasoning, .investigation, 6, "reviewer-mode.method-figure", 0.68, .scopeOnly, ["review", "method", "figure", "reproducibility"]),
        activity("science.experiment-sequence", "Experiment Sequence", "実験手順の構成", "Order controls, manipulation, measurement, and comparison into a discriminating experiment.", .scientificReasoning, .puzzle, 7, "design.discriminating-sequence", 0.62, .scopeOnly, ["sequence", "experiment", "control", "prediction"]),
        activity("science.paper-sprint", "Paper Sprint", "論文スプリント", "Extract the question, method, result, and limitations before accepting the conclusion.", .scientificReasoning, .reconstruction, 8, "paper-sprint.structure", 0.64, .scopeOnly, ["paper", "question", "method", "limitations"]),

        // Logic and debugging — 9/9 generator variants.
        activity("logic.state-trace", "State Trace", "状態トレース", "Write the complete state after each mutation and recheck derived values and invariants.", .logicDebugging, .puzzle, 0, "trace.stale-derived-state", 0.52, .scopeOnly, ["state", "trace", "invariant", "mutation"]),
        activity("logic.conditions", "Necessary or Sufficient?", "必要条件か十分条件か", "Check the stated implication, then seek one counterexample to its converse.", .logicDebugging, .puzzle, 1, "conditions.divisibility", 0.50, .scopeOnly, ["necessary", "sufficient", "implication", "converse"]),
        activity("logic.counterexample", "Counterexample Quest", "反例を探す", "A valid counterexample must make the hypothesis true and the claimed consequence false.", .logicDebugging, .puzzle, 2, "counterexample.even-product", 0.56, .scopeOnly, ["counterexample", "premise", "conclusion", "universal"]),
        activity("logic.proof-builder", "Proof Builder", "証明を組み立てる", "Each proof line must use only definitions or results already established.", .logicDebugging, .puzzle, 3, "proof.order-odd-sum", 0.58, .scopeOnly, ["proof", "order", "dependency", "parity"]),
        activity("logic.invalid-step", "First Invalid Step", "最初の不正な手順", "At every transformation, check domain restrictions such as nonzero divisors.", .logicDebugging, .puzzle, 4, "proof.first-invalid-division", 0.60, .scopeOnly, ["proof", "invalid", "division by zero", "precondition"]),
        activity("logic.boundary-bug", "Boundary Bug Hunt", "境界バグを見つける", "Test empty, one-element, and just-over-boundary inputs before large examples.", .logicDebugging, .puzzle, 5, "debug.boundary-last-element", 0.56, .scopeOnly, ["boundary", "bug", "off by one", "minimal input"]),
        activity("logic.complexity", "Complexity Duel", "計算量の比較", "Write the dominant operation count as a function of input size.", .logicDebugging, .puzzle, 6, "debug.complexity-comparison", 0.62, .scopeOnly, ["complexity", "linear", "quadratic", "algorithm"]),
        activity("logic.loop-repair", "Loop Repair", "ループの修復", "A repair must satisfy the full iteration invariant for empty, singleton, and typical inputs.", .logicDebugging, .puzzle, 7, "debug.repair-loop-bound", 0.60, .scopeOnly, ["loop", "repair", "boundary", "patch"]),
        activity("logic.calibration", "Confidence Calibration", "確信度の調整", "Use the observed hit rate as an estimate while preserving uncertainty from a small sample.", .logicDebugging, .investigation, 8, "calibration.observed-frequency", 0.54, .scopeOnly, ["confidence", "calibration", "frequency", "uncertainty"]),

        // Retrieval — 9/9 generator variants.
        activity("retrieval.free-recall", "Free Recall", "自由再生", "Recall the central relationship without cues, then reveal the reference and rate the match.", .retrieval, .reconstruction, 0, "free-recall.self-check", 0.38, .retrievalAndSpacing, ["free recall", "self check", "reference", "memory"]),
        activity("retrieval.precision-recall", "Precision Recall", "正確な想起", "Enter a concise reviewed answer from memory before viewing the reference.", .retrieval, .reconstruction, 1, "short-answer", 0.42, .retrievalAndSpacing, ["short answer", "precision", "recall", "reference"]),
        activity("retrieval.cloze", "Relationship Cloze", "関係の穴埋め", "Reconstruct the missing part of a supported relationship before checking the answer.", .retrieval, .reconstruction, 2, "cloze.relationship", 0.44, .retrievalAndSpacing, ["cloze", "relationship", "missing", "recall"]),
        activity("retrieval.teach-back", "Teach It Back", "自分の言葉で説明", "Explain the central entities and relationship in your own words before review.", .retrieval, .reconstruction, 3, "explain-concept.self-check", 0.46, .retrievalAndSpacing, ["explain", "concept", "self check", "teach"]),
        activity("retrieval.recognition", "Recognition Audit", "再認の監査", "Choose the statement whose direction, conditions, and scope are supported by the bounded reference.", .retrieval, .investigation, 4, "source-supported.recognition", 0.42, .scopeOnly, ["recognition", "source", "scope", "supported"]),
        activity("retrieval.repair-cycle", "Retrieval Cycle Builder", "想起サイクルの構成", "Order an evidence-aware cycle of attempt, comparison, error location, and closed-reference retry.", .retrieval, .puzzle, 5, "reconstruction.ordered-cycle", 0.50, .scopeOnly, ["retrieve", "compare", "repair", "retry"]),
        activity("retrieval.equation", "Equation Reconstruction", "数式の再構成", "Rebuild the missing side of a source-backed equation before checking the reviewed answer.", .retrieval, .reconstruction, 6, "equation-reconstruction", 0.52, .retrievalAndSpacing, ["equation", "reconstruction", "relationship", "recall"]),
        activity("retrieval.figure", "Figure Interpretation", "図の解釈", "Interpret a compact source figure while preserving the supported direction, conditions, and scope.", .retrieval, .investigation, 7, "figure-interpretation", 0.54, .scopeOnly, ["figure", "interpretation", "scope", "source"]),
        activity("retrieval.source-filter", "Source-Filter Trace", "出典フィルターのトレース", "Trace a source-support filter and select the candidate justified by its direction, conditions, and scope.", .retrieval, .puzzle, 8, "code-tracing.source-filter", 0.56, .scopeOnly, ["source", "filter", "code trace", "support"]),

        // Transfer — 7/7 generator variants.
        activity("transfer.sequence", "Transfer Sequence", "転移手順", "Order representation, solution, and checking steps for a structurally related problem.", .transfer, .transfer, 0, "cross-context.sequence", 0.58, .scopeOnly, ["sequence", "represent", "solve", "check"]),
        activity("transfer.conditions", "Preserve Transfer Conditions", "転移条件を保つ", "Identify which conditions, constraints, and units must survive a context shift.", .transfer, .transfer, 1, "cross-context.conditions", 0.60, .scopeOnly, ["condition", "constraint", "unit", "mapping"]),
        activity("transfer.rate", "Rate in a New Field", "別分野でのレート", "Map a rate-times-duration relationship into a new field while preserving its units.", .transfer, .transfer, 2, "field-shift.rate-product", 0.60, .scopeOnly, ["rate", "time", "field", "unit"]),
        activity("transfer.representation", "Table-to-Equation", "表から式へ", "Recover a linear relationship from a table and express the same structure as an equation.", .transfer, .transfer, 3, "representation.table-to-equation", 0.62, .scopeOnly, ["table", "equation", "representation", "ratio"]),
        activity("transfer.causal-map", "Causal Structure Map", "因果構造の対応", "Map shared directed feedback and delay across controller and regulatory-system scenarios.", .transfer, .transfer, 4, "field-shift.causal-structure", 0.66, .structureMapping, ["causal", "feedback", "structure", "field"]),
        activity("transfer.interacting-variables", "Interacting-Variable Ratio", "相互作用する変数の比", "Map numerator and denominator roles to interacting variables, then compute the preserved ratio.", .transfer, .transfer, 5, "interacting-variables.ratio", 0.66, .scopeOnly, ["ratio", "variable", "numerator", "denominator"]),
        activity("transfer.saturation", "Saturation Check", "飽和の確認", "Identify where an assumed linear rule stops applying after a saturation constraint appears.", .transfer, .transfer, 6, "constraint-shift.linearity", 0.68, .scopeOnly, ["saturation", "linear", "constraint", "model"])
    ]

    static var selectableFieldPairingCount: Int {
        activities.count * STEMField.allCases.count
    }

    static func activity(id: String) -> NFDefaultContentActivity? {
        activities.first { $0.id == id }
    }

    static func activities(for lab: TrainingLab) -> [NFDefaultContentActivity] {
        activities.filter { $0.lab == lab }
    }

    static func search(
        _ query: String,
        lab: TrainingLab? = nil,
        kind: NFDefaultActivityKind? = nil,
        locale: Locale = NFAppLocalization.preferredLocale
    ) -> [NFDefaultContentActivity] {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let tokens = substantiveTokens(trimmedQuery)
        let candidates = activities.filter { activity in
            (lab == nil || activity.lab == lab)
                && (kind == nil || activity.kind == kind)
        }
        guard !trimmedQuery.isEmpty else { return candidates }

        let scored: [(activity: NFDefaultContentActivity, score: Int)] = candidates.compactMap { activity -> (activity: NFDefaultContentActivity, score: Int)? in
            let titleText = [
                activity.title,
                activity.japaneseTitle,
                activity.localizedTitle(locale: locale)
            ].joined(separator: " ")
            let searchableText = [
                titleText,
                activity.summary,
                activity.localizedSummary(locale: locale),
                activity.lab.localizedTitle(locale: locale),
                activity.kind.localizedTitle(locale: locale),
                activity.keywords.joined(separator: " ")
            ].joined(separator: " ")
            let haystack = substantiveTokens(searchableText)
            let overlap = tokens.intersection(haystack).count
            let phraseMatch = searchableText.localizedCaseInsensitiveContains(trimmedQuery)
            guard overlap > 0 || phraseMatch else { return nil }
            let titleMatch = titleText.localizedCaseInsensitiveContains(trimmedQuery)
            return (
                activity: activity,
                score: overlap * 10 + (phraseMatch ? 100 : 0) + (titleMatch ? 200 : 0)
            )
        }
        .sorted {
            if $0.score != $1.score { return $0.score > $1.score }
            return $0.activity.id < $1.activity.id
        }
        return scored.map(\.activity)
    }

    static func audit() -> [String] {
        var violations: [String] = []
        if activities.count != 58 { violations.append("activity-count") }
        if Set(activities.map(\.id)).count != activities.count { violations.append("duplicate-id") }
        if Set(activities.map(\.title)).count != activities.count { violations.append("duplicate-title") }
        if Set(activities.map(\.summary)).count != activities.count { violations.append("duplicate-summary") }
        if Set(activities.map(\.mechanicID)).count != activities.count { violations.append("duplicate-mechanic") }

        for lab in TrainingLab.allCases {
            let entries = activities(for: lab)
            let expectedCount = NFFallbackExerciseGenerator.variantCount(for: lab)
            if entries.count != expectedCount { violations.append("lab-count:\(lab.rawValue)") }
            if Set(entries.map(\.variant)) != Set(0..<expectedCount) {
                violations.append("variant-coverage:\(lab.rawValue)")
            }
        }

        for activity in activities {
            if activity.id.isEmpty || activity.title.isEmpty || activity.japaneseTitle.isEmpty
                || activity.summary.isEmpty || activity.templateSlug.isEmpty {
                violations.append("empty:\(activity.id)")
            }
            if !(0.15...0.90).contains(activity.defaultDifficulty) {
                violations.append("difficulty:\(activity.id)")
            }
            if ![5, 10, 15].contains(activity.recommendedMinutes) {
                violations.append("duration:\(activity.id)")
            }
            if activity.keywords.count < 4 || Set(activity.keywords.map { $0.lowercased() }).count != activity.keywords.count {
                violations.append("keywords:\(activity.id)")
            }
            if !activity.mechanicID.hasSuffix(".fallback-variant-\(activity.variant)") {
                violations.append("mechanic:\(activity.id)")
            }
            let prohibited = ["iq", "intelligence boost", "brain age", "cognitive score"]
            let claimsText = [activity.title, activity.summary, activity.researchBasis.localizedNote]
                .joined(separator: " ")
                .lowercased()
            if prohibited.contains(where: claimsText.contains) {
                violations.append("claim:\(activity.id)")
            }
        }
        return Array(Set(violations)).sorted()
    }

    private static func activity(
        _ id: String,
        _ title: String,
        _ japaneseTitle: String,
        _ summary: String,
        _ lab: TrainingLab,
        _ kind: NFDefaultActivityKind,
        _ variant: Int,
        _ templateSlug: String,
        _ difficulty: Double,
        _ researchBasis: NFDefaultContentResearchBasis,
        _ keywords: [String]
    ) -> NFDefaultContentActivity {
        NFDefaultContentActivity(
            id: "nf.default.\(id)",
            title: title,
            japaneseTitle: japaneseTitle,
            summary: summary,
            lab: lab,
            kind: kind,
            variant: variant,
            templateSlug: templateSlug,
            defaultDifficulty: difficulty,
            recommendedMinutes: 5,
            researchBasis: researchBasis,
            keywords: keywords
        )
    }

    private static func substantiveTokens(_ value: String) -> Set<String> {
        Set(value
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .lowercased()
            .split { !$0.isLetter && !$0.isNumber }
            .map(String.init)
            .filter { $0.count >= 2 })
    }
}

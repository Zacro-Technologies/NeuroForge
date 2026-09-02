import Foundation

/// A useful starting point for learners who know their field but do not yet
/// know how to phrase an authoring request. Starter sets are real authoring
/// inputs rather than canned screenshots: the selected topic, objective,
/// style, difficulty, and seed flow through the same authoring pipeline as a
/// custom set.
struct NFStarterQuestionSetDescriptor: Equatable, Identifiable, Sendable {
    let id: String
    let title: String
    let summary: String
    let field: STEMField
    let lab: TrainingLab
    let topic: String
    let learningObjective: String
    let supportedStyles: [NFQuestionStyle]
    let defaultStyle: NFQuestionStyle
    let defaultDifficulty: Double
    let defaultItemCount: Int
    let keywords: [String]

    var localizedTitle: String { localizedTitle(locale: NFAppLocalization.preferredLocale) }
    var localizedSummary: String { localizedSummary(locale: NFAppLocalization.preferredLocale) }
    var localizedLearningObjective: String {
        localizedLearningObjective(locale: NFAppLocalization.preferredLocale)
    }

    func localizedTitle(locale: Locale) -> String {
        NFAppLocalization.localizedCatalogValue(title, locale: locale)
    }

    func localizedSummary(locale: Locale) -> String {
        NFAppLocalization.localizedCatalogValue(summary, locale: locale)
    }

    func localizedLearningObjective(locale: Locale) -> String {
        NFAppLocalization.localizedCatalogValue(learningObjective, locale: locale)
    }

    func makeAuthoringRequest(
        seed: UInt64,
        style: NFQuestionStyle? = nil,
        difficulty: Double? = nil,
        count: Int? = nil,
        localeIdentifier: String = Locale.current.identifier,
        sourceChunks: [NFSourceChunk] = [],
        documentPolicies: [DocumentAIPolicy] = [],
        aiMode: AIMode = .automatic,
        allowsShortcutAuthoring: Bool = true
    ) -> NFAuthoringRequest {
        let requestedStyle = style.flatMap { supportedStyles.contains($0) ? $0 : nil }
            ?? defaultStyle
        return NFAuthoringRequest(
            capability: sourceChunks.isEmpty ? .contextualize : .sourceGroundedPractice,
            lab: lab,
            field: field,
            customTopic: topic,
            learningObjective: learningObjective,
            style: requestedStyle,
            difficulty: difficulty ?? defaultDifficulty,
            count: count ?? defaultItemCount,
            localeIdentifier: localeIdentifier,
            seed: NFStarterQuestionSetCatalog.derivedSeed(base: seed, setID: id),
            sourceChunks: sourceChunks,
            documentPolicies: documentPolicies,
            aiMode: aiMode,
            allowsShortcutAuthoring: allowsShortcutAuthoring
        )
    }
}

enum NFStarterQuestionSetCatalog {
    /// A broad reviewed library with at least five starting points for every
    /// available field. It remains compact on screen because callers request only the
    /// deterministic recommendations relevant to the learner's profile.
    static let sets: [NFStarterQuestionSetDescriptor] = [
        // General STEM
        set(
            "general.causal-claims", "Evidence, association, and causation",
            "Judge what an experiment or observational comparison actually supports.",
            .general, .scientificReasoning, "causal claims and study design",
            "distinguish association, prediction, and causation; identify the design change that would strengthen the claim",
            [.multipleChoice, .experimentalDesign, .dataInterpretation], .experimentalDesign, 0.56,
            ["causation", "evidence", "confound", "study design"]
        ),
        set(
            "general.estimation", "Estimation and sanity checks",
            "Break an unfamiliar quantity into factors, estimate it, and test the scale.",
            .general, .quantitative, "Fermi estimation and order of magnitude",
            "decompose an estimate, state assumptions, and detect an answer that is implausible by orders of magnitude",
            [.numerical, .multipleChoice, .shortAnswer], .shortAnswer, 0.48,
            ["estimate", "fermi", "magnitude", "assumption"]
        ),
        set(
            "general.logic", "Arguments, conditions, and counterexamples",
            "Test implications instead of relying on whether a conclusion sounds plausible.",
            .general, .logicDebugging, "logical implication and counterexamples",
            "separate necessary from sufficient conditions, identify invalid converses, and construct a decisive counterexample",
            [.multipleChoice, .shortAnswer, .proofOrDerivation], .multipleChoice, 0.55,
            ["logic", "implication", "counterexample", "deduction"]
        ),
        set(
            "general.data-literacy", "Read tables and charts without overclaiming",
            "Compute the visible contrast and keep it separate from the story around it.",
            .general, .quantitative, "tables, charts, and uncertainty",
            "extract a numerical comparison, preserve units and uncertainty, and state one conclusion the display cannot establish",
            [.dataInterpretation, .multipleChoice, .numerical], .dataInterpretation, 0.52,
            ["chart", "table", "uncertainty", "data"]
        ),
        set(
            "general.transfer", "Transfer a solution structure",
            "Recognize the same constraint or relation after the surface context changes.",
            .general, .transfer, "cross-domain problem solving",
            "identify the invariant structure, map each quantity or condition, and verify that the transferred solution still satisfies its assumptions",
            [.shortAnswer, .multipleChoice, .proofOrDerivation], .shortAnswer, 0.64,
            ["transfer", "analogy", "invariant", "problem solving"]
        ),
        set(
            "general.source-study", "Learn from my material",
            "Turn complete prose statements from an imported chapter, paper, or note into cited active recall.",
            .general, .retrieval, "prose statements and evidence from the selected material",
            "reconstruct distinct cited statements from memory, preserve their conditions and qualifiers, and distinguish a faithful paraphrase from a stronger, reversed, or universalized claim",
            [.shortAnswer], .shortAnswer, 0.55,
            ["source", "material", "prose", "citation", "retrieval", "recall"]
        ),
        set(
            "general.spatial-models", "Spatial models and transformations",
            "Rotate, project, fold, and translate between diagrams and coordinate descriptions.",
            .general, .spatial, "spatial transformations diagrams and coordinate models",
            "identify what a transformation changes and preserves, predict the resulting orientation or view, and verify the answer against coordinates or adjacency constraints",
            [.spatialTransformation, .multipleChoice, .shortAnswer], .spatialTransformation, 0.57,
            ["spatial", "rotation", "projection", "diagram"]
        ),

        // Mathematics
        set(
            "mathematics.calculus", "Calculus: rates, limits, and accumulation",
            "Connect symbolic rules to the quantities and limiting arguments behind them.",
            .mathematics, .logicDebugging, "calculus derivatives integrals and limits",
            "derive a result from a definition or theorem, check its assumptions, and interpret the result rather than only applying a formula",
            [.proofOrDerivation, .numerical, .multipleChoice], .proofOrDerivation, 0.68,
            ["calculus", "derivative", "integral", "limit"]
        ),
        set(
            "mathematics.linear-algebra", "Linear algebra and transformations",
            "Reason about vectors, matrices, rank, and invariants across representations.",
            .mathematics, .logicDebugging, "linear algebra matrices vector spaces eigenvalues",
            "use definitions and structural properties to justify a transformation, detect a dimension error, and connect algebraic and geometric views",
            [.proofOrDerivation, .numerical, .spatialTransformation], .proofOrDerivation, 0.69,
            ["matrix", "vector", "rank", "eigenvalue"]
        ),
        set(
            "mathematics.discrete-proof", "Discrete proofs and induction",
            "Practice proof construction, parity, induction, and counterexample choice.",
            .mathematics, .logicDebugging, "mathematical induction parity and discrete proof",
            "choose a proof method, make every quantifier and induction step explicit, and find the first unsupported inference",
            [.proofOrDerivation, .multipleChoice, .debugging], .proofOrDerivation, 0.66,
            ["proof", "induction", "parity", "discrete mathematics"]
        ),
        set(
            "mathematics.probability", "Probability and Bayesian reasoning",
            "Use the correct conditioning set and translate between probabilities and natural frequencies.",
            .mathematics, .quantitative, "probability conditional probability and Bayes theorem",
            "identify the relevant sample space, compute a conditional probability, and explain how the base rate changes the conclusion",
            [.numerical, .dataInterpretation, .multipleChoice], .numerical, 0.62,
            ["probability", "bayes", "conditional", "base rate"]
        ),
        set(
            "mathematics.modeling", "Build and audit mathematical models",
            "Translate a word problem into variables, constraints, and a checkable result.",
            .mathematics, .transfer, "mathematical modeling and optimization",
            "formulate a model from stated assumptions, solve or simplify it, then test units, boundary cases, and sensitivity to one assumption",
            [.numerical, .proofOrDerivation, .shortAnswer], .numerical, 0.65,
            ["model", "optimization", "constraints", "assumptions"]
        ),

        // Physics
        set(
            "physics.mechanics", "Mechanics, momentum, and energy",
            "Choose a system and derive motion or conservation results with signs and units intact.",
            .physics, .quantitative, "classical mechanics momentum energy and kinematics",
            "select an appropriate conservation law or equation of motion, derive the requested quantity, and check limiting cases and dimensions",
            [.numerical, .proofOrDerivation, .debugging], .numerical, 0.64,
            ["mechanics", "momentum", "energy", "kinematics"]
        ),
        set(
            "physics.electricity", "Electricity, fields, and circuits",
            "Reason from charge, potential, current, and circuit constraints instead of memorized shapes.",
            .physics, .quantitative, "electric fields potential and DC circuits",
            "apply sign conventions and conservation constraints, solve a circuit or field relation, and diagnose an inconsistent unit or boundary condition",
            [.numerical, .debugging, .proofOrDerivation], .numerical, 0.66,
            ["electricity", "circuit", "field", "potential"]
        ),
        set(
            "physics.waves", "Waves and oscillations",
            "Connect equations, graphs, phase, frequency, and energy for oscillatory systems.",
            .physics, .transfer, "waves oscillations frequency and phase",
            "translate between a wave equation and its graph, calculate a derived quantity, and explain which features remain invariant under a phase or viewpoint change",
            [.numerical, .dataInterpretation, .spatialTransformation], .dataInterpretation, 0.61,
            ["waves", "oscillation", "frequency", "phase"]
        ),
        set(
            "physics.thermodynamics", "Thermodynamics and statistical reasoning",
            "Track energy, state variables, and process assumptions across a thermodynamic change.",
            .physics, .quantitative, "thermodynamics heat work and state functions",
            "apply the first law with a declared sign convention, distinguish state functions from path quantities, and test the scale of the result",
            [.numerical, .multipleChoice, .proofOrDerivation], .numerical, 0.67,
            ["thermodynamics", "heat", "work", "entropy"]
        ),
        set(
            "physics.measurement", "Measurement, uncertainty, and dimensions",
            "Catch impossible formulas and report what precision the evidence really supports.",
            .physics, .scientificReasoning, "physical measurement uncertainty and dimensional analysis",
            "propagate a simple uncertainty, use dimensional consistency to reject an expression, and separate precision from accuracy",
            [.dataInterpretation, .numerical, .debugging], .dataInterpretation, 0.57,
            ["measurement", "uncertainty", "dimensions", "error"]
        ),

        // Computing
        set(
            "computing.algorithms", "Algorithms and complexity",
            "Trace an algorithm, prove the key invariant, and compare growth honestly.",
            .computing, .logicDebugging, "algorithms correctness and asymptotic complexity",
            "state a loop or data-structure invariant, find a boundary failure, and justify time and space complexity from counted operations",
            [.debugging, .proofOrDerivation, .multipleChoice], .debugging, 0.66,
            ["algorithm", "complexity", "invariant", "big o"]
        ),
        set(
            "computing.graphs", "Graph algorithms",
            "Reason through traversal, shortest paths, and the preconditions behind greedy choices.",
            .computing, .logicDebugging, "graph traversal Dijkstra and shortest paths",
            "trace frontier state, identify the correctness invariant, handle cycles and stale entries, and choose an algorithm compatible with edge weights",
            [.debugging, .proofOrDerivation, .shortAnswer], .debugging, 0.71,
            ["graph", "dijkstra", "bfs", "dfs"]
        ),
        set(
            "computing.boundaries", "State, loops, and boundary bugs",
            "Find the smallest failing input and repair the exact state transition that causes it.",
            .computing, .logicDebugging, "program state loops arrays and edge cases",
            "trace mutable state, test empty and one-element inputs, locate the first invalid access or transition, and propose the smallest correct repair",
            [.debugging, .multipleChoice, .shortAnswer], .debugging, 0.58,
            ["debugging", "loop", "array", "edge case"]
        ),
        set(
            "computing.concurrency", "Concurrency and distributed state",
            "Analyze interleavings, ownership, ordering, and failure recovery without assuming a lucky schedule.",
            .computing, .logicDebugging, "concurrency race conditions and distributed systems",
            "construct a failing interleaving, identify the missing synchronization or idempotency condition, and explain which guarantee the repair provides",
            [.debugging, .proofOrDerivation, .shortAnswer], .debugging, 0.77,
            ["concurrency", "race condition", "distributed", "idempotency"]
        ),
        set(
            "computing.data-structures", "Data structures in action",
            "Choose a representation by the operations and invariants the problem actually needs.",
            .computing, .transfer, "data structures trees heaps hash tables and queues",
            "compare operation costs, trace a structural update, and justify a data-structure choice under explicit workload constraints",
            [.multipleChoice, .debugging, .proofOrDerivation], .multipleChoice, 0.63,
            ["data structure", "tree", "heap", "hash table"]
        ),

        // Engineering
        set(
            "engineering.statics", "Statics, loads, and safety factors",
            "Draw the system boundary, balance loads, and audit whether a design margin is meaningful.",
            .engineering, .quantitative, "engineering statics loads and factors of safety",
            "construct a free-body model, solve an equilibrium relation, calculate a safety factor, and identify one assumption that controls the result",
            [.numerical, .debugging, .proofOrDerivation], .numerical, 0.63,
            ["statics", "load", "equilibrium", "safety factor"]
        ),
        set(
            "engineering.controls", "Feedback and control systems",
            "Trace feedback direction, stability evidence, and controller response across representations.",
            .engineering, .transfer, "feedback control stability and response",
            "map a block diagram to equations, distinguish negative from positive feedback, and interpret transient and steady-state behavior",
            [.dataInterpretation, .debugging, .proofOrDerivation], .dataInterpretation, 0.70,
            ["control", "feedback", "stability", "response"]
        ),
        set(
            "engineering.signals", "Signals, sampling, and filtering",
            "Connect time-domain observations to frequency, sampling, and noise tradeoffs.",
            .engineering, .quantitative, "signals sampling filtering and aliasing",
            "calculate a sampling constraint, diagnose aliasing or filter misuse, and interpret how a transformation changes signal and noise",
            [.numerical, .dataInterpretation, .debugging], .dataInterpretation, 0.68,
            ["signal", "sampling", "filter", "aliasing"]
        ),
        set(
            "engineering.materials", "Materials and failure reasoning",
            "Interpret stress–strain evidence and distinguish a measured failure mode from its proposed cause.",
            .engineering, .scientificReasoning, "materials stress strain fatigue and failure",
            "read a stress–strain or fatigue comparison, compute a relevant quantity, and design a test that discriminates competing failure mechanisms",
            [.dataInterpretation, .experimentalDesign, .numerical], .dataInterpretation, 0.66,
            ["materials", "stress", "strain", "fatigue"]
        ),
        set(
            "engineering.units", "Units, tolerances, and design checks",
            "Keep dimensions, tolerances, and worst-case bounds visible through a calculation.",
            .engineering, .mentalMath, "engineering units tolerances and plausibility checks",
            "convert units exactly, combine simple tolerances, estimate the expected range, and reject a dimensionally inconsistent result",
            [.numerical, .multipleChoice, .debugging], .numerical, 0.52,
            ["units", "tolerance", "dimension", "plausibility"]
        ),

        // Chemistry
        set(
            "chemistry.stoichiometry", "Stoichiometry and limiting reagents",
            "Turn a balanced equation into mole constraints and a checkable yield calculation.",
            .chemistry, .quantitative, "stoichiometry limiting reagents and reaction yield",
            "identify the limiting reagent from coefficient-adjusted amounts, compute theoretical yield, and diagnose a mole-ratio error",
            [.numerical, .debugging, .multipleChoice], .numerical, 0.59,
            ["stoichiometry", "limiting reagent", "mole", "yield"]
        ),
        set(
            "chemistry.kinetics", "Reaction kinetics",
            "Infer rate-law structure from controlled comparisons and distinguish fit from mechanism.",
            .chemistry, .scientificReasoning, "reaction kinetics rate laws and activation energy",
            "use initial-rate data to infer an order, compute a rate change, and state why the fitted rate law alone does not prove a molecular mechanism",
            [.dataInterpretation, .numerical, .experimentalDesign], .dataInterpretation, 0.67,
            ["kinetics", "rate law", "reaction order", "activation energy"]
        ),
        set(
            "chemistry.equilibrium", "Equilibrium and acid–base reasoning",
            "Track reaction direction, equilibrium expressions, and logarithmic concentration scales.",
            .chemistry, .quantitative, "chemical equilibrium acids bases and buffers",
            "write an equilibrium expression, compare Q with K, reason about a perturbation, and calculate a bounded acid–base quantity",
            [.numerical, .multipleChoice, .proofOrDerivation], .multipleChoice, 0.68,
            ["equilibrium", "acid", "base", "buffer"]
        ),
        set(
            "chemistry.thermochemistry", "Thermochemistry and spontaneity",
            "Keep heat, enthalpy, entropy, and spontaneity claims logically separate.",
            .chemistry, .logicDebugging, "thermochemistry enthalpy entropy and Gibbs energy",
            "apply a sign convention, compute an energy change, and identify an invalid inference from exothermicity to spontaneity",
            [.numerical, .debugging, .multipleChoice], .debugging, 0.64,
            ["enthalpy", "entropy", "gibbs", "spontaneity"]
        ),
        set(
            "chemistry.solutions", "Solutions, concentrations, and dilution",
            "Solve concentration changes while preserving solute amount and units.",
            .chemistry, .mentalMath, "solutions concentration and dilution",
            "choose the conserved quantity, calculate a dilution or mixture concentration, and catch an inverted volume ratio",
            [.numerical, .debugging, .multipleChoice], .numerical, 0.48,
            ["solution", "concentration", "dilution", "molarity"]
        ),

        // Life sciences
        set(
            "life-sciences.genetics", "Genetics and inheritance",
            "Connect genotype assumptions to probability, phenotype evidence, and experimental tests.",
            .lifeSciences, .quantitative, "genetics inheritance alleles and linkage",
            "calculate an inheritance probability, state the assumptions behind it, and choose evidence that distinguishes independent assortment from linkage",
            [.numerical, .experimentalDesign, .multipleChoice], .multipleChoice, 0.61,
            ["genetics", "inheritance", "allele", "linkage"]
        ),
        set(
            "life-sciences.experiments", "Biological experiments and controls",
            "Design comparisons that separate treatment effects from batches, handling, and measurement drift.",
            .lifeSciences, .scientificReasoning, "biological experimental design controls and confounding",
            "identify positive, negative, and procedural controls; block or randomize a nuisance variable; and match the conclusion to the design",
            [.experimentalDesign, .dataInterpretation, .multipleChoice], .experimentalDesign, 0.59,
            ["experiment", "control", "batch effect", "confound"]
        ),
        set(
            "life-sciences.cell-systems", "Cell signaling and regulatory systems",
            "Reason through pathways as causal state transitions rather than lists of names.",
            .lifeSciences, .logicDebugging, "cell signaling gene regulation and feedback",
            "trace activation and inhibition through a pathway, predict a perturbation, and identify feedback that changes the steady state",
            [.multipleChoice, .debugging, .proofOrDerivation], .debugging, 0.66,
            ["cell signaling", "regulation", "pathway", "feedback"]
        ),
        set(
            "life-sciences.epidemiology", "Epidemiology and diagnostic evidence",
            "Use base rates and study design to interpret risk and diagnostic results.",
            .lifeSciences, .quantitative, "epidemiology risk diagnostic tests and base rates",
            "translate sensitivity and specificity into natural frequencies, compare risks with a clear denominator, and avoid a causal claim from selection-biased data",
            [.numerical, .dataInterpretation, .multipleChoice], .dataInterpretation, 0.63,
            ["epidemiology", "risk", "diagnostic", "base rate"]
        ),
        set(
            "life-sciences.ecology", "Ecology, populations, and systems",
            "Interpret dynamic interactions, sampling choices, and competing explanations in population data.",
            .lifeSciences, .transfer, "ecology populations interactions and sampling",
            "reason from a simple population model, interpret a time series, and design a test that separates environmental forcing from species interaction",
            [.dataInterpretation, .experimentalDesign, .numerical], .dataInterpretation, 0.65,
            ["ecology", "population", "sampling", "interaction"]
        ),

        // Data science
        set(
            "data-science.classifiers", "Classifier metrics and thresholds",
            "Calculate metrics from a confusion matrix and explain the tradeoff a threshold creates.",
            .dataScience, .quantitative, "classifier evaluation precision recall and ROC tradeoffs",
            "compute precision, recall, and a base-rate-sensitive interpretation; then reason about how a threshold changes false positives and false negatives",
            [.numerical, .dataInterpretation, .multipleChoice], .dataInterpretation, 0.61,
            ["classifier", "precision", "recall", "threshold"]
        ),
        set(
            "data-science.inference", "Statistical inference and uncertainty",
            "Match intervals, tests, and effect estimates to the question and assumptions.",
            .dataScience, .quantitative, "statistical inference confidence intervals and hypothesis tests",
            "interpret an interval without reversing its probability statement, distinguish effect size from significance, and identify a violated assumption",
            [.dataInterpretation, .multipleChoice, .numerical], .dataInterpretation, 0.68,
            ["statistics", "confidence interval", "hypothesis test", "effect size"]
        ),
        set(
            "data-science.validation", "Validation, leakage, and generalization",
            "Build an evaluation pipeline whose held-out evidence remains genuinely unseen.",
            .dataScience, .logicDebugging, "model validation data leakage and generalization",
            "detect leakage in preprocessing or feature construction, choose an appropriate split, and explain what the test result does and does not generalize to",
            [.debugging, .experimentalDesign, .shortAnswer], .debugging, 0.65,
            ["validation", "data leakage", "test set", "generalization"]
        ),
        set(
            "data-science.regression", "Regression and model diagnostics",
            "Interpret coefficients and residuals while keeping prediction separate from causation.",
            .dataScience, .scientificReasoning, "regression residuals interactions and confounding",
            "interpret a coefficient with units and conditioning, diagnose a residual pattern, and state why an observational coefficient need not be causal",
            [.dataInterpretation, .debugging, .experimentalDesign], .dataInterpretation, 0.69,
            ["regression", "residual", "interaction", "confounding"]
        ),
        set(
            "data-science.algorithms", "Data pipelines and algorithmic reasoning",
            "Trace transformations, complexity, and failure modes from raw records to a reported metric.",
            .dataScience, .logicDebugging, "data pipelines algorithms and reproducibility",
            "trace row and feature transformations, detect a state or boundary bug, and specify the checks needed to reproduce the reported result",
            [.debugging, .proofOrDerivation, .multipleChoice], .debugging, 0.62,
            ["pipeline", "algorithm", "reproducibility", "transformation"]
        )
    ]

    static func descriptor(id: String) -> NFStarterQuestionSetDescriptor? {
        sets.first { $0.id == id }
    }

    static func sets(
        for field: STEMField,
        lab: TrainingLab? = nil
    ) -> [NFStarterQuestionSetDescriptor] {
        sets.filter { descriptor in
            descriptor.field == field && (lab == nil || descriptor.lab == lab)
        }
    }

    static func search(
        _ query: String,
        field: STEMField? = nil,
        locale: Locale = NFAppLocalization.preferredLocale,
        limit: Int = 12
    ) -> [NFStarterQuestionSetDescriptor] {
        let tokens = substantiveTokens(in: query)
        guard !tokens.isEmpty else {
            let candidates = field.map { sets(for: $0) } ?? sets
            return Array(candidates.prefix(max(0, limit)))
        }
        return sets
            .filter { field == nil || $0.field == field }
            .map { descriptor in
                let haystack = substantiveTokens(in: [
                    descriptor.title,
                    descriptor.summary,
                    descriptor.localizedTitle(locale: locale),
                    descriptor.localizedSummary(locale: locale),
                    descriptor.topic,
                    descriptor.learningObjective,
                    descriptor.keywords.joined(separator: " ")
                ].joined(separator: " "))
                let overlap = tokens.filter(haystack.contains).count
                let phraseBonus = descriptor.title.localizedCaseInsensitiveContains(query)
                    || descriptor.topic.localizedCaseInsensitiveContains(query) ? 4 : 0
                return (descriptor, overlap * 10 + phraseBonus)
            }
            .filter { $0.1 > 0 }
            .sorted {
                if $0.1 != $1.1 { return $0.1 > $1.1 }
                return $0.0.id < $1.0.id
            }
            .prefix(max(0, limit))
            .map(\.0)
    }

    /// Returns a small, balanced list for onboarding and empty-state screens.
    /// The same profile and seed always produce the same order, while a new
    /// seed rotates equally relevant choices without random or network state.
    static func recommendations(
        fields: Set<STEMField>,
        goals: Set<TrainingGoal>,
        seed: UInt64,
        excluding recentlyUsedIDs: Set<String> = [],
        limit: Int = 6
    ) -> [NFStarterQuestionSetDescriptor] {
        let eligibleSets = sets.filter { !recentlyUsedIDs.contains($0.id) }
        let boundedLimit = min(max(0, limit), eligibleSets.count)
        guard boundedLimit > 0 else { return [] }

        let specificFields = fields.subtracting([.general])
        let preferredFields = specificFields.isEmpty ? Set([STEMField.general]) : specificFields
        let preferredLabs = labs(for: goals)
        var selected: [NFStarterQuestionSetDescriptor] = []
        var selectedIDs = Set<String>()

        // Give each selected field one useful entry before filling by score.
        for field in preferredFields.sorted(by: { $0.rawValue < $1.rawValue }) {
            guard selected.count < boundedLimit,
                  let first = ranked(
                    candidates: eligibleSets.filter { $0.field == field },
                    fields: preferredFields,
                    labs: preferredLabs,
                    seed: seed
                  ).first else { continue }
            selected.append(first)
            selectedIDs.insert(first.id)
        }

        let remaining = ranked(
            candidates: eligibleSets.filter { descriptor in
                preferredFields.contains(descriptor.field) || descriptor.field == .general
            },
            fields: preferredFields,
            labs: preferredLabs,
            seed: seed
        )
        for descriptor in remaining where selected.count < boundedLimit {
            if selectedIDs.insert(descriptor.id).inserted {
                selected.append(descriptor)
            }
        }

        // A profile with an unusually narrow filter still receives a complete
        // shelf rather than an empty or partially populated screen.
        if selected.count < boundedLimit {
            for descriptor in ranked(
                candidates: eligibleSets,
                fields: preferredFields,
                labs: preferredLabs,
                seed: seed
            ) where selected.count < boundedLimit {
                if selectedIDs.insert(descriptor.id).inserted {
                    selected.append(descriptor)
                }
            }
        }
        return selected
    }

    static func audit() -> [String] {
        var violations: [String] = []
        if Set(sets.map(\.id)).count != sets.count { violations.append("duplicate-id") }
        if Set(sets.map { "\($0.field.rawValue)|\($0.title.lowercased())" }).count != sets.count {
            violations.append("duplicate-title")
        }

        for field in STEMField.allCases where sets(for: field).count < 5 {
            violations.append("field-coverage:\(field.rawValue)")
        }
        for lab in TrainingLab.allCases where !sets.contains(where: { $0.lab == lab }) {
            violations.append("lab-coverage:\(lab.rawValue)")
        }
        for style in NFQuestionStyle.allCases where !sets.contains(where: { $0.supportedStyles.contains(style) }) {
            violations.append("style-coverage:\(style.rawValue)")
        }

        for descriptor in sets {
            if descriptor.id.isEmpty || descriptor.title.isEmpty || descriptor.summary.isEmpty
                || descriptor.topic.isEmpty || descriptor.learningObjective.isEmpty {
                violations.append("empty:\(descriptor.id)")
            }
            if descriptor.supportedStyles.isEmpty
                || Set(descriptor.supportedStyles).count != descriptor.supportedStyles.count
                || !descriptor.supportedStyles.contains(descriptor.defaultStyle) {
                violations.append("styles:\(descriptor.id)")
            }
            if !(0...1).contains(descriptor.defaultDifficulty) {
                violations.append("difficulty:\(descriptor.id)")
            }
            if !(4...12).contains(descriptor.defaultItemCount) {
                violations.append("count:\(descriptor.id)")
            }
            if descriptor.keywords.count < 4 || Set(descriptor.keywords.map { $0.lowercased() }).count != descriptor.keywords.count {
                violations.append("keywords:\(descriptor.id)")
            }
            if descriptor.learningObjective.split(separator: " ").count < 10 {
                violations.append("objective-depth:\(descriptor.id)")
            }
        }
        return Array(Set(violations)).sorted()
    }

    fileprivate static func derivedSeed(base: UInt64, setID: String) -> UInt64 {
        stableHash(setID, seed: base ^ 0x9E37_79B9_7F4A_7C15)
    }

    private static func set(
        _ id: String,
        _ title: String,
        _ summary: String,
        _ field: STEMField,
        _ lab: TrainingLab,
        _ topic: String,
        _ objective: String,
        _ styles: [NFQuestionStyle],
        _ defaultStyle: NFQuestionStyle,
        _ difficulty: Double,
        _ keywords: [String]
    ) -> NFStarterQuestionSetDescriptor {
        NFStarterQuestionSetDescriptor(
            id: "nf.starter.\(id)",
            title: title,
            summary: summary,
            field: field,
            lab: lab,
            topic: topic,
            learningObjective: objective,
            supportedStyles: styles,
            defaultStyle: defaultStyle,
            defaultDifficulty: difficulty,
            defaultItemCount: 6,
            keywords: keywords
        )
    }

    private static func ranked(
        candidates: [NFStarterQuestionSetDescriptor],
        fields: Set<STEMField>,
        labs: Set<TrainingLab>,
        seed: UInt64
    ) -> [NFStarterQuestionSetDescriptor] {
        candidates.sorted { lhs, rhs in
            let left = relevance(lhs, fields: fields, labs: labs)
            let right = relevance(rhs, fields: fields, labs: labs)
            if left != right { return left > right }
            let leftTie = stableHash(lhs.id, seed: seed)
            let rightTie = stableHash(rhs.id, seed: seed)
            if leftTie != rightTie { return leftTie < rightTie }
            return lhs.id < rhs.id
        }
    }

    private static func relevance(
        _ descriptor: NFStarterQuestionSetDescriptor,
        fields: Set<STEMField>,
        labs: Set<TrainingLab>
    ) -> Int {
        let fieldScore = fields.contains(descriptor.field) ? 100 : (descriptor.field == .general ? 20 : 0)
        let labScore = labs.contains(descriptor.lab) ? 45 : 0
        return fieldScore + labScore
    }

    private static func labs(for goals: Set<TrainingGoal>) -> Set<TrainingLab> {
        var result = Set<TrainingLab>()
        for goal in goals {
            switch goal {
            case .mentalMath: result.formUnion([.mentalMath, .quantitative])
            case .problemSolving: result.formUnion([.logicDebugging, .quantitative, .transfer])
            case .researchReading: result.formUnion([.retrieval, .scientificReasoning])
            case .dataReasoning: result.formUnion([.quantitative, .scientificReasoning])
            case .experimentalDesign: result.insert(.scientificReasoning)
            case .programming: result.insert(.logicDebugging)
            case .spatialReasoning: result.formUnion([.spatial, .transfer])
            }
        }
        return result
    }

    private static func stableHash(_ value: String, seed: UInt64) -> UInt64 {
        var hash = seed == 0 ? 0xCBF2_9CE4_8422_2325 : seed
        for byte in value.utf8 {
            hash ^= UInt64(byte)
            hash &*= 0x100_0000_01B3
        }
        return hash
    }

    private static func substantiveTokens(in text: String) -> Set<String> {
        Set(text
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .lowercased()
            .split { !$0.isLetter && !$0.isNumber }
            .map(String.init)
            .filter { $0.count >= 3 })
    }
}

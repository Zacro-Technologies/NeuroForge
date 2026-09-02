import Foundation

enum NFReleaseContentCollectionID: String, Codable, CaseIterable, Sendable {
    case mentalMathMechanics = "mental-math.mechanics"
    case mentalMathPackTemplates = "mental-math.pack-templates"
    case spatialMechanics = "spatial.mechanics"
    case spatialStimulusCategories = "spatial.stimulus-categories"
    case spatialProtectedGrammars = "spatial.protected-grammars"
    case quantitativeFamilies = "quantitative.concept-families"
    case quantitativeRationales = "quantitative.rationale-variants"
    case experimentalScenarios = "experimental.scenario-skeletons"
    case dataChartTemplates = "data.chart-templates"
    case logicProofItems = "logic.proof-items"
    case logicASTFamilies = "logic.ast-families"
    case baselineAlternateForms = "baseline.alternate-forms"
    case weeklyMissionSkeletons = "weekly.mission-skeletons"
    case evidenceCards = "evidence.reviewed-cards"

    var releaseMinimum: Int {
        switch self {
        case .mentalMathMechanics: 10
        case .mentalMathPackTemplates: 240
        case .spatialMechanics: 6
        case .spatialStimulusCategories: 4
        case .spatialProtectedGrammars: 2
        case .quantitativeFamilies: 8
        case .quantitativeRationales: 200
        case .experimentalScenarios: 150
        case .dataChartTemplates: 100
        case .logicProofItems: 120
        case .logicASTFamilies: 12
        case .baselineAlternateForms: 120
        case .weeklyMissionSkeletons: 24
        case .evidenceCards: 10
        }
    }
}

/// A compact, auditable release-content descriptor. `content` is the authored
/// skeleton or review copy; `attributes` carries the typed grammar facets used
/// to instantiate or inspect it without making the signed manifest enormous.
struct NFReleaseContentDescriptor: Codable, Equatable, Sendable, Identifiable {
    let id: String
    let family: String
    let title: String
    let content: String
    let attributes: [String: String]
}

struct NFReleaseContentCollection: Codable, Equatable, Sendable, Identifiable {
    let id: NFReleaseContentCollectionID
    let descriptors: [NFReleaseContentDescriptor]
}

struct NFReleaseContentInventory: Codable, Equatable, Sendable {
    let contentVersion: String
    let collections: [NFReleaseContentCollection]

    func collection(_ id: NFReleaseContentCollectionID) -> NFReleaseContentCollection? {
        collections.first { $0.id == id }
    }

    /// Deterministic selection is available to generators and audit tooling.
    func descriptor(collection id: NFReleaseContentCollectionID, seed: UInt64) -> NFReleaseContentDescriptor? {
        guard let descriptors = collection(id)?.descriptors.sorted(by: { $0.id < $1.id }),
              !descriptors.isEmpty else { return nil }
        return descriptors[Int(seed % UInt64(descriptors.count))]
    }
}

enum NFReleaseContentCatalog {
    static let schemaVersion = 1
    static let contentVersion = "1.0.0-rc.1"

    static let inventory = NFReleaseContentInventory(
        contentVersion: contentVersion,
        collections: [
            collection(.mentalMathMechanics, mentalMathMechanics),
            collection(.mentalMathPackTemplates, mentalMathPackTemplates),
            collection(.spatialMechanics, spatialMechanics),
            collection(.spatialStimulusCategories, spatialStimulusCategories),
            collection(.spatialProtectedGrammars, spatialProtectedGrammars),
            collection(.quantitativeFamilies, quantitativeFamilies),
            collection(.quantitativeRationales, quantitativeRationales),
            collection(.experimentalScenarios, experimentalScenarios),
            collection(.dataChartTemplates, dataChartTemplates),
            collection(.logicProofItems, logicProofItems),
            collection(.logicASTFamilies, logicASTFamilies),
            collection(.baselineAlternateForms, baselineAlternateForms),
            collection(.weeklyMissionSkeletons, weeklyMissionSkeletons),
            collection(.evidenceCards, evidenceCards)
        ]
    )

    /// Structural release audit. This deliberately checks more than aggregate
    /// counts so duplicated filler cannot satisfy a release minimum.
    static func audit(_ inventory: NFReleaseContentInventory = inventory) -> [String] {
        var violations: [String] = []
        let expectedCollections = Set(NFReleaseContentCollectionID.allCases)
        let actualCollections = Set(inventory.collections.map(\.id))
        if actualCollections != expectedCollections {
            violations.append("collection-set")
        }
        if inventory.collections.count != actualCollections.count {
            violations.append("duplicate-collection")
        }

        var globalIDs = Set<String>()
        for collectionID in NFReleaseContentCollectionID.allCases {
            guard let descriptors = inventory.collection(collectionID)?.descriptors else {
                violations.append("missing:\(collectionID.rawValue)")
                continue
            }
            if descriptors.count < collectionID.releaseMinimum {
                violations.append("minimum:\(collectionID.rawValue)")
            }
            if Set(descriptors.map(\.id)).count != descriptors.count {
                violations.append("duplicate-id:\(collectionID.rawValue)")
            }
            for descriptor in descriptors {
                if descriptor.id.isEmpty || descriptor.family.isEmpty || descriptor.title.isEmpty || descriptor.content.isEmpty {
                    violations.append("empty-field:\(collectionID.rawValue)")
                }
                if !globalIDs.insert(descriptor.id).inserted {
                    violations.append("duplicate-global-id:\(descriptor.id)")
                }
                for lintViolation in NFUserFacingContentLinter.lint(descriptor) {
                    violations.append("content-lint:\(descriptor.id):\(lintViolation.description)")
                }
            }
        }

        auditMentalMath(inventory, violations: &violations)
        auditBaseline(inventory, violations: &violations)
        auditWeeklyMissions(inventory, violations: &violations)
        auditEvidenceCards(inventory, violations: &violations)
        return Array(Set(violations)).sorted()
    }

    private static func collection(
        _ id: NFReleaseContentCollectionID,
        _ descriptors: [NFReleaseContentDescriptor]
    ) -> NFReleaseContentCollection {
        NFReleaseContentCollection(id: id, descriptors: descriptors.sorted { $0.id < $1.id })
    }

    // MARK: Mental math

    private struct MentalMechanic {
        let id: String
        let title: String
        let authority: String
    }

    private static let mentalMechanicBlueprints = [
        MentalMechanic(id: "rapid-recall", title: "Rapid recall", authority: "exact integer or rational equality"),
        MentalMechanic(id: "compensation", title: "Compensation", authority: "exact arithmetic after an offset transform"),
        MentalMechanic(id: "fraction-relay", title: "Fraction relay", authority: "normalized exact rational equality"),
        MentalMechanic(id: "percentage-base", title: "Percentage base", authority: "exact base-rate calculation with units"),
        MentalMechanic(id: "scientific-notation", title: "Scientific notation", authority: "normalized coefficient and exponent"),
        MentalMechanic(id: "unit-conversion", title: "Unit conversion", authority: "dimension-preserving exact conversion"),
        MentalMechanic(id: "estimate-first", title: "Estimate, then exact", authority: "separate plausibility band and exact result"),
        MentalMechanic(id: "calculation-chain", title: "Calculation chain", authority: "replayable exact state transition chain"),
        MentalMechanic(id: "plausibility-audit", title: "Plausibility audit", authority: "authored magnitude bounds"),
        MentalMechanic(id: "mental-or-machine", title: "Mental or machine", authority: "authored tool-choice rubric")
    ]

    private static let mentalMathMechanics = mentalMechanicBlueprints.map { mechanic in
        descriptor(
            id: "nf.release.mm.mechanic.\(mechanic.id)",
            family: mechanic.id,
            title: mechanic.title,
            content: "Train \(mechanic.title.lowercased()) with feedback whose authority is \(mechanic.authority).",
            attributes: ["answerAuthority": mechanic.authority, "scoring": "deterministic"]
        )
    }

    private struct MentalPack {
        let id: String
        let title: String
        let entity: String
        let quantity: String
        let unit: String
    }

    private static let mentalPacks = [
        MentalPack(id: "mathematics-statistics", title: "Mathematics & Statistics", entity: "bootstrap samples", quantity: "observed cases", unit: "cases"),
        MentalPack(id: "physics-engineering", title: "Physics & Engineering", entity: "sensor cycles", quantity: "measured impulses", unit: "N·s"),
        MentalPack(id: "chemistry-biology", title: "Chemistry & Biology", entity: "assay wells", quantity: "sample aliquots", unit: "mL"),
        MentalPack(id: "computer-science-data", title: "Computer Science & Data", entity: "data batches", quantity: "processed records", unit: "records")
    ]

    private static let mentalMathPackTemplates = mentalPacks.flatMap { pack in
        mentalMechanicBlueprints.flatMap { mechanic in
            (1...6).map { level in
                let left = 6 + level * 3 + (mentalMechanicBlueprints.firstIndex { $0.id == mechanic.id } ?? 0)
                let right = 4 + level + ((mentalMechanicBlueprints.firstIndex { $0.id == mechanic.id } ?? 0) % 4)
                return descriptor(
                    id: "nf.mm.pack.\(pack.id).\(mechanic.id).l\(level)",
                    family: mechanic.id,
                    title: "\(pack.title) · \(mechanic.title) · level \(level)",
                    content: "Using \(pack.entity), reason about \(left) groups of \(right) \(pack.quantity) in \(pack.unit) with the \(mechanic.title.lowercased()) strategy.",
                    attributes: [
                        "pack": pack.id,
                        "mechanic": mechanic.id,
                        "difficultyLevel": String(level),
                        "entity": pack.entity,
                        "quantity": pack.quantity,
                        "unit": pack.unit,
                        "answerAuthority": mechanic.authority
                    ]
                )
            }
        }
    }

    // MARK: Spatial

    private static let spatialMechanics = [
        ("mental-rotation", "Mental rotation", "Track orientation under a named-axis rotation."),
        ("cube-net-folding", "Cube-net folding", "Determine which faces become adjacent or opposite after folding."),
        ("cross-section", "Cross-section prediction", "Predict the two-dimensional section made by a plane."),
        ("perspective-transform", "Perspective transform", "Map an object between orthographic viewpoints."),
        ("graph-layout", "Graph layout invariance", "Separate connectivity from a graph's drawn geometry."),
        ("reference-frame", "Reference-frame conversion", "Translate direction and coordinates between frames.")
    ].map { descriptor(id: "nf.release.spatial.mechanic.\($0.0)", family: $0.0, title: $0.1, content: $0.2) }

    private static let spatialStimulusCategories = [
        ("polyhedral", "Polyhedral solids", "Labeled cubes, prisms, and nets with unambiguous face identities."),
        ("molecular", "Molecular geometry", "Abstract bonded-node structures without chemistry-answer authority."),
        ("engineering", "Engineering views", "Orthographic components, sections, and coordinate frames."),
        ("data-structure", "Data structures", "Trees and graphs whose topology is invariant under layout.")
    ].map { descriptor(id: "nf.release.spatial.stimulus.\($0.0)", family: $0.0, title: $0.1, content: $0.2) }

    private static let spatialProtectedGrammars = [
        descriptor(
            id: "nf.release.spatial.holdout.axis-composition.v1",
            family: "axis-composition",
            title: "Protected axis-composition grammar",
            content: "Compose two non-commuting rotations over unseen labels, then select the final orientation.",
            attributes: ["pool": "assessment-holdout", "exposure": "ledger-protected", "answerAuthority": "rotation-state-machine"]
        ),
        descriptor(
            id: "nf.release.spatial.holdout.net-adjacency.v1",
            family: "net-adjacency",
            title: "Protected net-adjacency grammar",
            content: "Fold an unseen valid cube-net topology and identify an opposite-face relation.",
            attributes: ["pool": "assessment-holdout", "exposure": "ledger-protected", "answerAuthority": "cube-folding-engine"]
        )
    ]

    // MARK: Quantitative and probability

    private struct QuantitativeFamily {
        let id: String
        let title: String
        let decisiveRule: String
        let commonFailure: String
    }

    private static let quantitativeBlueprints = [
        QuantitativeFamily(id: "ratio-proportion", title: "Ratio and proportion", decisiveRule: "compare quantities on a common multiplicative scale", commonFailure: "adding where scaling is required"),
        QuantitativeFamily(id: "rates-units", title: "Rates and units", decisiveRule: "preserve dimensions through each rate conversion", commonFailure: "canceling incompatible units"),
        QuantitativeFamily(id: "percent-change", title: "Percent change", decisiveRule: "identify the reference base before dividing", commonFailure: "using the final value as the base"),
        QuantitativeFamily(id: "distribution-shape", title: "Distribution shape", decisiveRule: "match the summary to skew, spread, and outliers", commonFailure: "treating mean and median as interchangeable"),
        QuantitativeFamily(id: "conditional-probability", title: "Conditional probability", decisiveRule: "restrict the denominator to the stated condition", commonFailure: "using the full sample space"),
        QuantitativeFamily(id: "bayesian-update", title: "Bayesian update", decisiveRule: "combine prior odds with the likelihood ratio", commonFailure: "confusing inverse conditionals"),
        QuantitativeFamily(id: "expected-value-risk", title: "Expected value and risk", decisiveRule: "weight every outcome while keeping variability separate", commonFailure: "equating expectation with a guaranteed result"),
        QuantitativeFamily(id: "uncertainty-intervals", title: "Uncertainty and intervals", decisiveRule: "interpret the interval under its stated procedure", commonFailure: "assigning a posterior probability without a Bayesian model")
    ]

    private static let quantitativeFamilies = quantitativeBlueprints.map { family in
        descriptor(
            id: "nf.release.quant.family.\(family.id)",
            family: family.id,
            title: family.title,
            content: "Decisive rule: \(family.decisiveRule). Diagnostic contrast: \(family.commonFailure).",
            attributes: ["decisiveRule": family.decisiveRule, "commonFailure": family.commonFailure]
        )
    }

    private static let rationaleAngles = [
        ("identify", "First identify the quantities and the claim being tested"),
        ("represent", "Represent the givens with explicit symbols and units"),
        ("compute", "Carry out only the operation licensed by the representation"),
        ("contrast", "Contrast the supported step with the tempting invalid step"),
        ("audit", "Audit the result against bounds, dimensions, and base rates")
    ]

    private static let rationaleChecks = [
        ("units", "check that units and dimensions remain compatible"),
        ("denominator", "state why this denominator is the relevant comparison set"),
        ("bounds", "verify the result lies inside a defensible bound"),
        ("assumption", "name the assumption that makes the inference valid"),
        ("counterexample", "test the conclusion against a minimal counterexample")
    ]

    private static let quantitativeRationales = quantitativeBlueprints.flatMap { family in
        rationaleAngles.flatMap { angle in
            rationaleChecks.map { check in
                descriptor(
                    id: "nf.release.quant.rationale.\(family.id).\(angle.0).\(check.0)",
                    family: family.id,
                    title: "\(family.title): \(angle.0) / \(check.0)",
                    content: "\(angle.1). For \(family.title.lowercased()), \(family.decisiveRule); then \(check.1). This avoids \(family.commonFailure).",
                    attributes: ["angle": angle.0, "check": check.0, "errorContrast": family.commonFailure]
                )
            }
        }
    }

    // MARK: Experimental design and data

    private static let experimentDomains = [
        ("cell-culture", "cell-culture growth"),
        ("material-fatigue", "material-fatigue cycles"),
        ("ecological-survey", "ecological survey counts"),
        ("reaction-kinetics", "reaction-rate measurements"),
        ("sensor-calibration", "sensor calibration residuals"),
        ("algorithm-benchmark", "algorithm benchmark latency"),
        ("diagnostic-assay", "diagnostic-assay sensitivity"),
        ("energy-storage", "energy-storage degradation"),
        ("fluid-dynamics", "fluid-flow measurements"),
        ("astronomical-observation", "astronomical signal observations")
    ]

    private static let experimentDesigns = [
        ("randomized", "randomly assign experimental units to conditions"),
        ("blocked", "block on a measured nuisance variable before assignment"),
        ("factorial", "cross two interventions to estimate main effects and interaction"),
        ("repeated-measures", "measure each unit repeatedly with counterbalanced order"),
        ("observational", "pre-register an observational comparison and adjustment set")
    ]

    private static let experimentThreats = [
        ("confounding", "an uncontrolled common cause changes with the exposure"),
        ("measurement-drift", "the measurement process drifts across collection order"),
        ("selection-bias", "inclusion depends on both exposure and outcome-related factors")
    ]

    private static let experimentalScenarios = experimentDomains.flatMap { domain in
        experimentDesigns.flatMap { design in
            experimentThreats.map { threat in
                descriptor(
                    id: "nf.release.experiment.scenario.\(domain.0).\(design.0).\(threat.0)",
                    family: design.0,
                    title: "\(domain.1.capitalized): \(design.0), \(threat.0)",
                    content: "A team studying \(domain.1) plans to \(design.1). The audit reveals that \(threat.1). Identify the estimand, diagnose the threat, and propose one design repair without claiming causality beyond the repaired design.",
                    attributes: ["domain": domain.0, "design": design.0, "threat": threat.0, "answerAuthority": "causal-schema-rubric"]
                )
            }
        }
    }

    private static let chartPhenomena = [
        ("growth", "monotonic growth with saturation"),
        ("decay", "exponential decay with noise"),
        ("seasonality", "seasonality plus a weak trend"),
        ("threshold", "a threshold response"),
        ("interaction", "a two-factor interaction"),
        ("mixture", "a two-component mixture"),
        ("heteroskedasticity", "variance that grows with the mean"),
        ("outlier", "one influential outlier"),
        ("lag", "a lagged response"),
        ("null-effect", "no systematic group difference")
    ]

    private static let chartForms = [
        ("line", "line chart with uncertainty ribbon"),
        ("scatter", "scatterplot with an optional fitted trend"),
        ("distribution", "distribution plot with robust summaries"),
        ("small-multiple", "small multiples on common scales"),
        ("interval", "point-and-interval comparison")
    ]

    private static let chartTasks = [
        ("interpret", "identify the supported pattern and one unsupported extrapolation"),
        ("diagnose", "diagnose the encoding or statistical feature most likely to mislead")
    ]

    private static let dataChartTemplates = chartPhenomena.flatMap { phenomenon in
        chartForms.flatMap { form in
            chartTasks.map { task in
                descriptor(
                    id: "nf.release.data.chart.\(phenomenon.0).\(form.0).\(task.0)",
                    family: form.0,
                    title: "\(form.1.capitalized): \(phenomenon.0), \(task.0)",
                    content: "Seed a dataset showing \(phenomenon.1), render it as a \(form.1), and ask the learner to \(task.1).",
                    attributes: ["phenomenon": phenomenon.0, "chart": form.0, "task": task.0, "seeded": "true"]
                )
            }
        }
    }

    // MARK: Logic, proof, and debugging

    private static let logicFamilies = [
        ("modus-ponens", "apply a conditional only when its antecedent is established"),
        ("contrapositive", "distinguish a valid contrapositive from an invalid converse"),
        ("quantifier-negation", "move negation through universal and existential quantifiers"),
        ("set-inclusion", "track subset and element relations without reversing them"),
        ("loop-invariant", "show initialization, preservation, and termination"),
        ("induction", "connect the induction hypothesis to the next case"),
        ("contradiction", "identify the assumption whose consequence is impossible"),
        ("counterexample", "construct the smallest case that falsifies a universal claim"),
        ("dependency-order", "respect prerequisite edges in a partial order"),
        ("off-by-one", "trace inclusive and exclusive loop bounds"),
        ("recursion-trace", "track base cases and returned values through a call tree"),
        ("state-machine", "apply only transitions licensed by the current state")
    ]

    private static let logicContexts = [
        "integer parity", "set membership", "graph reachability", "array indexing", "string parsing",
        "resource scheduling", "experimental claims", "probability events", "geometric predicates", "program state"
    ]

    private static let logicProofItems = logicFamilies.flatMap { family in
        logicContexts.enumerated().map { index, context in
            descriptor(
                id: "nf.release.logic.item.\(family.0).c\(String(format: "%02d", index + 1))",
                family: family.0,
                title: "\(family.0) in \(context)",
                content: "In a \(context) argument, \(family.1). Select or construct the decisive step, then name the nearest invalid alternative.",
                attributes: ["context": context, "answerAuthority": "typed-logic-rubric", "authored": "true"]
            )
        }
    }

    private static let astBlueprints = [
        ("linear-scan", "scan a finite array once while tracking the best valid candidate"),
        ("binary-search", "halve an ordered search interval while preserving its invariant"),
        ("stable-filter", "retain matching elements without changing relative order"),
        ("reduce", "fold a sequence with an explicit accumulator state"),
        ("prefix-sum", "build cumulative totals with a defined zero boundary"),
        ("two-pointer", "move two bounded indices according to a comparison"),
        ("breadth-first-search", "explore a graph through a FIFO frontier"),
        ("depth-first-search", "explore a graph through a LIFO frontier"),
        ("stack-matcher", "match nested delimiters using a stack"),
        ("queue-simulation", "apply enqueue and dequeue operations to a FIFO state"),
        ("dynamic-recurrence", "fill a bounded table from declared predecessor states"),
        ("divide-conquer", "split, solve bounded subproblems, and combine results")
    ]

    private static let logicASTFamilies = astBlueprints.map { ast in
        descriptor(
            id: "nf.release.logic.ast.\(ast.0).v1",
            family: ast.0,
            title: ast.0.replacingOccurrences(of: "-", with: " ").capitalized,
            content: "Restricted pseudocode family: \(ast.1). Generation must remain inside interpreter limits and produce a unique terminal state.",
            attributes: ["interpreter": "nf-restricted-pseudocode.v1", "bounded": "true", "generatedVariants": "true"]
        )
    }

    // MARK: Baseline alternate forms

    private static let baselineDomains = [
        ("numerical-fluency", "mental-math", "numeric-entry"),
        ("spatial-representation", "spatial", "diagram-match"),
        ("scientific-data", "scientific-reasoning", "claim-evidence"),
        ("logic-metacognition", "logic-debugging", "state-trace")
    ]

    private static let baselineAlternateForms = baselineDomains.flatMap { domain in
        (1...15).flatMap { blueprint in
            ["a", "b"].map { form in
                let group = "nf.release.baseline.\(domain.0).g\(String(format: "%02d", blueprint))"
                return descriptor(
                    id: "\(group).form-\(form)",
                    family: domain.0,
                    title: "\(domain.0) blueprint \(blueprint), form \(form.uppercased())",
                    content: "Protected \(domain.0) descriptor using a \(domain.2) response. Form \(form.uppercased()) preserves construct and target difficulty while rotating parameters, labels, and surface representation.",
                    attributes: [
                        "alternateFormGroup": group,
                        "form": form,
                        "lab": domain.1,
                        "format": domain.2,
                        "pool": "assessment-holdout",
                        "calibration": "internal-release-target-v1"
                    ]
                )
            }
        }
    }

    // MARK: Weekly missions

    private static let missionPairs = [
        ("number-data", "mental-math", "scientific-reasoning", "scale and evidence"),
        ("space-logic", "spatial", "logic-debugging", "representation and invariants"),
        ("probability-experiment", "quantitative", "scientific-reasoning", "uncertainty and design"),
        ("retrieval-transfer", "retrieval", "transfer", "recall and application"),
        ("number-code", "mental-math", "logic-debugging", "exactness and state"),
        ("data-space", "quantitative", "spatial", "encoding and structure")
    ]

    private static let missionSurfaces = [
        ("lab-notebook", "audit a compact lab-notebook result"),
        ("field-brief", "resolve a field-research planning brief"),
        ("code-review", "review a data-processing decision and its trace"),
        ("figure-caption", "reconcile a figure, caption, and quantitative claim")
    ]

    private static let weeklyMissionSkeletons = missionPairs.flatMap { pair in
        missionSurfaces.map { surface in
            descriptor(
                id: "nf.release.weekly.\(pair.0).\(surface.0)",
                family: pair.0,
                title: "\(pair.0) · \(surface.0)",
                content: "Combine \(pair.1) with \(pair.2) to \(surface.1). Require transfer across \(pair.3), collect confidence before feedback, and end with a structure-comparison reflection.",
                attributes: ["primaryLab": pair.1, "secondaryLab": pair.2, "surface": surface.0, "repeatWindow": "24-active-weeks"]
            )
        }
    }

    // MARK: Reviewed evidence cards

    private static let evidenceCards = [
        evidenceCard("mental-math", "Mental math", "exactness, strategy use, and eligible response time", "Performance is specific to practiced arithmetic mechanics and does not estimate general intelligence."),
        evidenceCard("spatial", "Spatial reasoning", "accuracy across rotations, folds, views, and unseen grammars", "Evidence is task-specific and does not imply a general visualization trait."),
        evidenceCard("quantitative", "Quantitative reasoning", "ratio, probability, uncertainty, and rationale evidence", "Results separate practiced families from protected transfer items."),
        evidenceCard("scientific-reasoning", "Scientific reasoning", "claim-evidence links, design choices, and uncertainty handling", "The app does not certify research quality or professional competence."),
        evidenceCard("logic-debugging", "Logic and debugging", "typed logic steps, state traces, and bounded pseudocode outcomes", "Results cover the represented formal families, not programming ability as a whole."),
        evidenceCard("retrieval", "Retrieval", "delayed source-grounded recall with citation coverage", "Recall evidence is limited to material the learner imported or selected."),
        evidenceCard("transfer", "Transfer", "performance when surface context or representation changes", "Transfer is reported separately and never inferred from practice improvement alone."),
        evidenceCard("experimental-design", "Experimental design", "estimand, assignment, control, and validity-threat decisions", "Scenarios are educational and do not replace domain or ethics review."),
        evidenceCard("data-interpretation", "Data interpretation", "chart reading, distribution features, uncertainty, and unsupported extrapolation", "A correct chart judgment does not validate the underlying dataset or study."),
        evidenceCard("causal-inference", "Causal inference", "structured cause, confound, mediator, and selection reasoning", "Causal language is accepted only when licensed by the represented design assumptions.")
    ]

    private static func evidenceCard(_ id: String, _ title: String, _ evidence: String, _ limitation: String) -> NFReleaseContentDescriptor {
        descriptor(
            id: "nf.release.evidence.\(id).v1",
            family: id,
            title: title,
            content: "This card summarizes \(evidence). \(limitation)",
            attributes: [
                "reviewStatus": "reviewed-release-claims-checklist-v1",
                "reviewScope": "construct-and-claims-language",
                "claimScope": "in-app-evidence-only",
                "limitation": limitation
            ]
        )
    }

    // MARK: Audit facets

    private static func auditMentalMath(_ inventory: NFReleaseContentInventory, violations: inout [String]) {
        guard let templates = inventory.collection(.mentalMathPackTemplates)?.descriptors else { return }
        let packCounts = Dictionary(grouping: templates, by: { $0.attributes["pack"] ?? "" }).mapValues(\.count)
        for pack in mentalPacks where packCounts[pack.id] != 60 {
            violations.append("mental-pack-count:\(pack.id)")
        }
        let mechanics = Set(templates.compactMap { $0.attributes["mechanic"] })
        if mechanics != Set(mentalMechanicBlueprints.map(\.id)) {
            violations.append("mental-mechanic-coverage")
        }
    }

    private static func auditBaseline(_ inventory: NFReleaseContentInventory, violations: inout [String]) {
        guard let forms = inventory.collection(.baselineAlternateForms)?.descriptors else { return }
        let groups = Dictionary(grouping: forms, by: { $0.attributes["alternateFormGroup"] ?? "" })
        if groups.count != 60 {
            violations.append("baseline-group-count")
        }
        for (group, descriptors) in groups {
            let formIDs = Set(descriptors.compactMap { $0.attributes["form"] })
            if group.isEmpty || descriptors.count != 2 || formIDs != Set(["a", "b"]) {
                violations.append("baseline-alternate-pair:\(group)")
            }
        }
    }

    private static func auditWeeklyMissions(_ inventory: NFReleaseContentInventory, violations: inout [String]) {
        guard let missions = inventory.collection(.weeklyMissionSkeletons)?.descriptors else { return }
        if missions.count != 24 || Set(missions.map(\.family)).count != 6 {
            violations.append("weekly-six-month-rotation")
        }
    }

    private static func auditEvidenceCards(_ inventory: NFReleaseContentInventory, violations: inout [String]) {
        guard let cards = inventory.collection(.evidenceCards)?.descriptors else { return }
        let required = Set([
            "mental-math", "spatial", "quantitative", "scientific-reasoning", "logic-debugging",
            "retrieval", "transfer", "experimental-design", "data-interpretation", "causal-inference"
        ])
        if Set(cards.map(\.family)) != required {
            violations.append("evidence-card-coverage")
        }
        if cards.contains(where: { $0.attributes["reviewStatus"] != "reviewed-release-claims-checklist-v1" }) {
            violations.append("evidence-card-review-status")
        }
    }

    private static func descriptor(
        id: String,
        family: String,
        title: String,
        content: String,
        attributes: [String: String] = [:]
    ) -> NFReleaseContentDescriptor {
        NFReleaseContentDescriptor(id: id, family: family, title: title, content: content, attributes: attributes)
    }
}

import Foundation

enum NFMentalMathDomainPackID: String, Codable, CaseIterable, Sendable {
    case mathematicsStatistics = "mathematics-statistics"
    case physicsEngineering = "physics-engineering"
    case chemistryBiology = "chemistry-biology"
    case computerScienceData = "computer-science-data"
}

struct NFMentalMathDomainTemplateDescriptor: Codable, Equatable, Sendable, Identifiable {
    let id: String
    let packID: NFMentalMathDomainPackID
    let fields: [STEMField]
    let operationFamily: String
    let difficultyLevel: Int
    let contextFrame: String
    let examplePrompt: String
    let authoritativeAnswer: String
    let validatorKind: String
}

struct NFMentalMathDomainPack: Codable, Equatable, Sendable, Identifiable {
    let id: NFMentalMathDomainPackID
    let title: String
    let fields: [STEMField]
    let templates: [NFMentalMathDomainTemplateDescriptor]
}

enum NFMentalMathDomainPackCatalog {
    private struct PackBlueprint {
        let id: NFMentalMathDomainPackID
        let title: String
        let fields: [STEMField]
        let entity: String
        let quantity: String
        let unit: String
    }

    private static let operationFamilies = [
        "rapid-recall",
        "compensation",
        "fraction-relay",
        "percentage-base",
        "scientific-notation",
        "unit-conversion",
        "estimate-first",
        "calculation-chain",
        "plausibility-audit",
        "mental-or-machine"
    ]

    private static func blueprints(localeIdentifier: String) -> [PackBlueprint] { [
        PackBlueprint(
            id: .mathematicsStatistics,
            title: localized("Mathematics & Statistics", localeIdentifier: localeIdentifier),
            fields: [.mathematics, .dataScience],
            entity: localized("bootstrap samples", localeIdentifier: localeIdentifier),
            quantity: localized("observed cases", localeIdentifier: localeIdentifier),
            unit: localized("cases", localeIdentifier: localeIdentifier)
        ),
        PackBlueprint(
            id: .physicsEngineering,
            title: localized("Physics & Engineering", localeIdentifier: localeIdentifier),
            fields: [.physics, .engineering],
            entity: localized("sensor cycles", localeIdentifier: localeIdentifier),
            quantity: localized("measured impulses", localeIdentifier: localeIdentifier),
            unit: "N·s"
        ),
        PackBlueprint(
            id: .chemistryBiology,
            title: localized("Chemistry & Biology", localeIdentifier: localeIdentifier),
            fields: [.chemistry, .lifeSciences],
            entity: localized("assay wells", localeIdentifier: localeIdentifier),
            quantity: localized("sample aliquots", localeIdentifier: localeIdentifier),
            unit: "mL"
        ),
        PackBlueprint(
            id: .computerScienceData,
            title: localized("Computer Science & Data", localeIdentifier: localeIdentifier),
            fields: [.computing, .dataScience],
            entity: localized("data batches", localeIdentifier: localeIdentifier),
            quantity: localized("processed records", localeIdentifier: localeIdentifier),
            unit: localized("records", localeIdentifier: localeIdentifier)
        )
    ] }

    static var packs: [NFMentalMathDomainPack] {
        packs(localeIdentifier: NFAppLocalization.preferredLanguageCode)
    }

    static func packs(localeIdentifier: String) -> [NFMentalMathDomainPack] {
        blueprints(localeIdentifier: localeIdentifier).map { blueprint in
        let templates = operationFamilies.enumerated().flatMap { operationIndex, operation in
            (1...6).map { level in
                makeDescriptor(
                    blueprint: blueprint,
                    operation: operation,
                    operationIndex: operationIndex,
                    level: level,
                    localeIdentifier: localeIdentifier
                )
            }
        }
        return NFMentalMathDomainPack(
            id: blueprint.id,
            title: blueprint.title,
            fields: blueprint.fields,
            templates: templates
        )
        }
    }

    static func pack(
        matching field: STEMField,
        localeIdentifier: String = NFAppLocalization.preferredLanguageCode
    ) -> NFMentalMathDomainPack? {
        let packID: NFMentalMathDomainPackID? = switch field {
        case .mathematics: .mathematicsStatistics
        case .physics, .engineering: .physicsEngineering
        case .chemistry, .lifeSciences: .chemistryBiology
        case .computing, .dataScience: .computerScienceData
        case .general: nil
        }
        return packID.flatMap { selectedID in
            packs(localeIdentifier: localeIdentifier).first { $0.id == selectedID }
        }
    }

    static func deterministicTemplate(
        packID: NFMentalMathDomainPackID,
        seed: UInt64,
        localeIdentifier: String = NFAppLocalization.preferredLanguageCode
    ) -> NFMentalMathDomainTemplateDescriptor? {
        guard let templates = packs(localeIdentifier: localeIdentifier).first(where: { $0.id == packID })?.templates,
              !templates.isEmpty else { return nil }
        return templates[Int(seed % UInt64(templates.count))]
    }

    private static func makeDescriptor(
        blueprint: PackBlueprint,
        operation: String,
        operationIndex: Int,
        level: Int,
        localeIdentifier: String
    ) -> NFMentalMathDomainTemplateDescriptor {
        let left = 6 + level * 3 + operationIndex
        let right = 4 + level + operationIndex % 4
        let product = left * right
        let prompt: String
        let answer: String
        let validator: String
        switch operation {
        case "rapid-recall":
            prompt = localized("A \(blueprint.entity) check has \(left) groups of \(right). How many \(blueprint.quantity) are represented?", localeIdentifier: localeIdentifier)
            answer = String(product)
            validator = "exact-rational"
        case "compensation":
            prompt = localized("Compute \(left) × \(right * 10 - 1) for a \(blueprint.entity) audit using compensation.", localeIdentifier: localeIdentifier)
            answer = String(left * (right * 10 - 1))
            validator = "exact-rational"
        case "fraction-relay":
            prompt = localized("Express \(level)/\(level + right) of the \(blueprint.entity) as an exact ratio.", localeIdentifier: localeIdentifier)
            answer = (try? NFExactNumber(numerator: Int64(level), denominator: Int64(level + right)))?.canonicalString ?? "0"
            validator = "exact-rational"
        case "percentage-base":
            prompt = localized("What is \(level * 5)% of \(product * 20) \(blueprint.unit)?", localeIdentifier: localeIdentifier)
            answer = String(level * product)
            validator = "exact-rational-with-unit"
        case "scientific-notation":
            prompt = localized("Normalize \(left) × 10^\(level + 2) for the \(blueprint.quantity) report.", localeIdentifier: localeIdentifier)
            answer = "\(Double(left) / 10)×10^\(level + 3)"
            validator = "coefficient-exponent"
        case "unit-conversion":
            prompt = localized("Convert \(product * 1_000) milli-\(blueprint.unit) to \(blueprint.unit).", localeIdentifier: localeIdentifier)
            answer = String(product)
            validator = "exact-rational-with-unit"
        case "estimate-first":
            prompt = localized("Estimate \(left * 10 - 2) × \(right * 10 + 1) \(blueprint.quantity), judge plausibility, then calculate exactly.", localeIdentifier: localeIdentifier)
            answer = String((left * 10 - 2) * (right * 10 + 1))
            validator = NFEstimateExactContract.contractMarker
        case "calculation-chain":
            prompt = localized("For \(blueprint.entity), start at \(left), add \(right), double, then subtract \(level).", localeIdentifier: localeIdentifier)
            answer = String((left + right) * 2 - level)
            validator = "calculation-chain.v1"
        case "plausibility-audit":
            prompt = localized("A report claims \(left) groups of \(right) total \(product * 100) \(blueprint.unit). Is its magnitude plausible?", localeIdentifier: localeIdentifier)
            answer = localized("implausible", localeIdentifier: localeIdentifier)
            validator = "authored-plausibility"
        default:
            prompt = localized("Choose an auditable tool for repeating a \(blueprint.entity) conversion \(left * 1_000) times.", localeIdentifier: localeIdentifier)
            answer = localized("code or spreadsheet", localeIdentifier: localeIdentifier)
            validator = "authored-tool-rubric"
        }
        return NFMentalMathDomainTemplateDescriptor(
            id: "nf.mm.pack.\(blueprint.id.rawValue).\(operation).l\(level)",
            packID: blueprint.id,
            fields: blueprint.fields,
            operationFamily: operation,
            difficultyLevel: level,
            contextFrame: localized("\(blueprint.title): \(blueprint.entity), \(blueprint.quantity), and \(blueprint.unit)", localeIdentifier: localeIdentifier),
            examplePrompt: prompt,
            authoritativeAnswer: answer,
            validatorKind: validator
        )
    }

    private static func localized(
        _ value: String.LocalizationValue,
        localeIdentifier: String
    ) -> String {
        NFAppLocalization.localized(
            value,
            locale: NFAppLocalization.locale(identifier: localeIdentifier)
        )
    }
}

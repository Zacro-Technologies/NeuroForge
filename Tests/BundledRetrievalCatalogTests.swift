import XCTest

@testable import NeuroForge

final class BundledRetrievalCatalogTests: XCTestCase {
    func testCatalogHasExactlyOneHundredTwentyFiveQuestionContractsPerField() {
        XCTAssertEqual(NFBundledRetrievalCatalog.version, 2)
        XCTAssertEqual(NFBundledRetrievalCatalog.editorialTargetCount, 200)
        XCTAssertEqual(NFBundledRetrievalCatalog.computedFamilyCount, 80)
        XCTAssertEqual(NFBundledRetrievalCatalog.computedTargetCount, 800)
        XCTAssertEqual(NFBundledRetrievalCatalog.requiredCountPerField, 125)
        XCTAssertEqual(NFBundledRetrievalCatalog.requiredTotalCount, 1_000)
        XCTAssertEqual(
            NFBundledRetrievalCatalog.requiredTotalCount,
            NFOfflineQuestionBank.questionsPerLab
        )
        XCTAssertEqual(NFBundledRetrievalCatalog.targets.count, 1_000)
        XCTAssertEqual(NFBundledRetrievalCatalog.audit(), [])

        for field in STEMField.allCases {
            let targets = NFBundledRetrievalCatalog.targets(for: field)
            XCTAssertEqual(targets.count, 125, field.rawValue)
            XCTAssertGreaterThanOrEqual(Set(targets.map(\.category)).count, 5, field.rawValue)
        }
    }

    func testEveryTargetHasAUniqueStableSemanticContract() {
        let targets = NFBundledRetrievalCatalog.targets
        XCTAssertEqual(Set(targets.map(\.id)).count, targets.count)
        XCTAssertEqual(Set(targets.map(\.semanticIdentity)).count, targets.count)
        XCTAssertEqual(
            Set(targets.map { NFBundledRetrievalCatalog.normalized($0.prompt) }).count,
            targets.count
        )

        let contracts = targets.map { target in
            [
                target.semanticIdentity,
                NFBundledRetrievalCatalog.normalized(target.prompt),
                NFBundledRetrievalCatalog.normalized(target.answer),
                NFBundledRetrievalCatalog.normalized(target.explanation)
            ].joined(separator: "|")
        }
        XCTAssertEqual(Set(contracts).count, targets.count)
    }

    func testSemanticIdentityDoesNotDependOnStableRecordID() throws {
        let target = try XCTUnwrap(NFBundledRetrievalCatalog.targets.first)
        let sameContractWithDifferentID = NFRetrievalKnowledgeTarget(
            id: "nf.retrieval.v1.general.different-record-id",
            field: target.field,
            category: target.category,
            prompt: target.prompt,
            answer: target.answer,
            acceptedAnswers: target.acceptedAnswers,
            explanation: target.explanation
        )

        XCTAssertEqual(target.semanticIdentity, sameContractWithDifferentID.semanticIdentity)
    }

    func testReviewedFactualBoundariesRemainExplicit() throws {
        let median = try XCTUnwrap(
            NFBundledRetrievalCatalog.target(id: "nf.retrieval.v1.general.median-definition")
        )
        XCTAssertFalse(NFBundledRetrievalCatalog.accepts("the middle ordered value", for: median))

        let replication = try XCTUnwrap(
            NFBundledRetrievalCatalog.target(id: "nf.retrieval.v1.general.replication-purpose")
        )
        XCTAssertFalse(NFBundledRetrievalCatalog.accepts("test whether the result is reproducible", for: replication))

        let identity = try XCTUnwrap(
            NFBundledRetrievalCatalog.target(id: "nf.retrieval.v1.mathematics.identity-matrix")
        )
        XCTAssertTrue(identity.prompt.contains("every compatible vector"))
        XCTAssertFalse(NFBundledRetrievalCatalog.accepts("I", for: identity))

        let momentum = try XCTUnwrap(
            NFBundledRetrievalCatalog.target(id: "nf.retrieval.v1.physics.momentum-definition")
        )
        XCTAssertTrue(momentum.prompt.contains("classical nonrelativistic"))

        let pressure = try XCTUnwrap(
            NFBundledRetrievalCatalog.target(id: "nf.retrieval.v1.physics.pressure-definition")
        )
        XCTAssertTrue(pressure.prompt.contains("average pressure"))

        let safety = try XCTUnwrap(
            NFBundledRetrievalCatalog.target(id: "nf.retrieval.v1.engineering.factor-of-safety")
        )
        XCTAssertFalse(NFBundledRetrievalCatalog.accepts("strength divided by working load", for: safety))

        let ion = try XCTUnwrap(
            NFBundledRetrievalCatalog.target(id: "nf.retrieval.v1.chemistry.ion-definition")
        )
        XCTAssertEqual(ion.answer, "It has a net electric charge")

        let acid = try XCTUnwrap(
            NFBundledRetrievalCatalog.target(id: "nf.retrieval.v1.chemistry.bronsted-acid")
        )
        XCTAssertTrue(acid.prompt.contains("Brønsted-Lowry"))

        let leakage = try XCTUnwrap(
            NFBundledRetrievalCatalog.target(id: "nf.retrieval.v1.data-science.data-leakage")
        )
        XCTAssertTrue(leakage.answer.contains("preprocessing, fitting, selection, or evaluation"))

        XCTAssertNil(
            NFBundledRetrievalCatalog.target(id: "nf.retrieval.v1.mathematics.two-point-slope")
        )
        XCTAssertNotNil(
            NFBundledRetrievalCatalog.target(id: "nf.retrieval.v1.mathematics.two-point-midpoint")
        )
    }

    func testComputedFamilyBoundaryCasesRemainScientificallyAndScoringExplicit() throws {
        let alkalineActivity = try XCTUnwrap(
            NFBundledRetrievalCatalog.target(id: "nf.retrieval.v1.chemistry.hydrogen-activity-ph-10")
        )
        XCTAssertFalse(alkalineActivity.prompt.localizedCaseInsensitiveContains("strong acid"))

        let largestDilutionSample = try XCTUnwrap(
            NFBundledRetrievalCatalog.target(id: "nf.retrieval.v1.chemistry.dilution-50-100")
        )
        XCTAssertTrue(largestDilutionSample.prompt.contains("50-millilitre"))
        XCTAssertTrue(largestDilutionSample.prompt.contains("to 100 millilitres"))
        XCTAssertNil(
            NFBundledRetrievalCatalog.target(id: "nf.retrieval.v1.chemistry.dilution-100-100")
        )

        let dilution = try XCTUnwrap(
            NFBundledRetrievalCatalog.target(id: "nf.retrieval.v1.chemistry.dilution-10-100")
        )
        XCTAssertTrue(NFBundledRetrievalCatalog.accepts("0.10 M", for: dilution))
        XCTAssertTrue(NFBundledRetrievalCatalog.accepts("0.1 M", for: dilution))

        let strain = try XCTUnwrap(
            NFBundledRetrievalCatalog.target(id: "nf.retrieval.v1.engineering.engineering-strain-10-1000")
        )
        XCTAssertTrue(NFBundledRetrievalCatalog.accepts("0.010", for: strain))
        XCTAssertTrue(NFBundledRetrievalCatalog.accepts("0.01", for: strain))

        for id in [
            "nf.retrieval.v1.engineering.efficiency-500-1000",
            "nf.retrieval.v1.data-science.precision-50-50",
            "nf.retrieval.v1.data-science.recall-40-60",
            "nf.retrieval.v1.data-science.accuracy-60-40"
        ] {
            let target = try XCTUnwrap(NFBundledRetrievalCatalog.target(id: id), id)
            XCTAssertTrue(
                target.prompt.localizedCaseInsensitiveContains("percentage"),
                id
            )
        }
    }

    func testCanonicalAndDeclaredAlternativeAnswersScoreDeterministically() {
        for target in NFBundledRetrievalCatalog.targets {
            for accepted in target.allAcceptedAnswers {
                XCTAssertTrue(
                    NFBundledRetrievalCatalog.accepts(accepted, for: target),
                    "Rejected bundled answer for \(target.id): \(accepted)"
                )
                XCTAssertTrue(
                    NFBundledRetrievalCatalog.accepts("  \(accepted.uppercased())!  ", for: target),
                    "Normalization changed bundled answer meaning for \(target.id): \(accepted)"
                )
            }
            XCTAssertFalse(NFBundledRetrievalCatalog.accepts("", for: target), target.id)
            XCTAssertFalse(
                NFBundledRetrievalCatalog.accepts("unrelated response with no reviewed equivalence", for: target),
                target.id
            )
        }
    }

    func testNormalizationPreservesMeaningfulMathematicalSyntax() throws {
        XCTAssertNotEqual(
            NFBundledRetrievalCatalog.normalized("H+"),
            NFBundledRetrievalCatalog.normalized("H")
        )
        XCTAssertNotEqual(
            NFBundledRetrievalCatalog.normalized("-1"),
            NFBundledRetrievalCatalog.normalized("1")
        )
        XCTAssertNotEqual(
            NFBundledRetrievalCatalog.normalized("TP/(TP+FP)"),
            NFBundledRetrievalCatalog.normalized("TP/TP+FP")
        )
        XCTAssertNotEqual(
            NFBundledRetrievalCatalog.normalized("¬A or ¬B"),
            NFBundledRetrievalCatalog.normalized("A or B")
        )
        XCTAssertNotEqual(
            NFBundledRetrievalCatalog.normalized("2.0:1"),
            NFBundledRetrievalCatalog.normalized("2.0 1")
        )
        XCTAssertNotEqual(
            NFBundledRetrievalCatalog.normalized("(2, 3)"),
            NFBundledRetrievalCatalog.normalized("(2 3)")
        )
        XCTAssertNotEqual(
            NFBundledRetrievalCatalog.normalized("((x1+x2)/2, (y1+y2)/2)"),
            NFBundledRetrievalCatalog.normalized("((x1+x2)/2 (y1+y2)/2)")
        )
        XCTAssertEqual(
            NFBundledRetrievalCatalog.normalized("6.02 × 10^23"),
            NFBundledRetrievalCatalog.normalized("6.02 * 10^23")
        )
        XCTAssertEqual(
            NFBundledRetrievalCatalog.normalized("m²"),
            NFBundledRetrievalCatalog.normalized("m^2")
        )
        XCTAssertEqual(
            NFBundledRetrievalCatalog.normalized("µm³"),
            NFBundledRetrievalCatalog.normalized("µm^3")
        )

        let ph = try XCTUnwrap(
            NFBundledRetrievalCatalog.target(id: "nf.retrieval.v1.chemistry.ph-definition")
        )
        XCTAssertTrue(NFBundledRetrievalCatalog.accepts("pH = -log10(aH+)", for: ph))
        XCTAssertFalse(NFBundledRetrievalCatalog.accepts("pH = log10(aH+)", for: ph))
        XCTAssertFalse(NFBundledRetrievalCatalog.accepts("pH = -log10(aH)", for: ph))

        let deMorgan = try XCTUnwrap(
            NFBundledRetrievalCatalog.target(id: "nf.retrieval.v1.mathematics.de-morgan-conjunction")
        )
        XCTAssertTrue(NFBundledRetrievalCatalog.accepts("¬A or ¬B", for: deMorgan))
        XCTAssertFalse(NFBundledRetrievalCatalog.accepts("A or B", for: deMorgan))

        let gearRatio = try XCTUnwrap(
            NFBundledRetrievalCatalog.target(id: "nf.retrieval.v1.engineering.gear-ratio-20-40")
        )
        XCTAssertTrue(NFBundledRetrievalCatalog.accepts("2.0:1", for: gearRatio))
        XCTAssertTrue(NFBundledRetrievalCatalog.accepts("2:1", for: gearRatio))
        XCTAssertFalse(NFBundledRetrievalCatalog.accepts("2.0 1", for: gearRatio))

        let midpoint = try XCTUnwrap(
            NFBundledRetrievalCatalog.target(id: "nf.retrieval.v1.mathematics.midpoint-0-0-4-6")
        )
        XCTAssertTrue(NFBundledRetrievalCatalog.accepts("(2, 3)", for: midpoint))
        XCTAssertFalse(NFBundledRetrievalCatalog.accepts("(2 3)", for: midpoint))

        let symbolicMidpoint = try XCTUnwrap(
            NFBundledRetrievalCatalog.target(id: "nf.retrieval.v1.mathematics.two-point-midpoint")
        )
        XCTAssertTrue(
            NFBundledRetrievalCatalog.accepts("((x1+x2)/2, (y1+y2)/2)", for: symbolicMidpoint)
        )
        XCTAssertFalse(
            NFBundledRetrievalCatalog.accepts("((x1+x2)/2 (y1+y2)/2)", for: symbolicMidpoint)
        )

        let particles = try XCTUnwrap(
            NFBundledRetrievalCatalog.target(id: "nf.retrieval.v1.chemistry.particle-count-2")
        )
        XCTAssertTrue(
            NFBundledRetrievalCatalog.accepts("1.2 * 10^24 particles", for: particles)
        )
        XCTAssertTrue(
            NFBundledRetrievalCatalog.accepts("12 * 10^23 particles", for: particles)
        )

        let rectangle = try XCTUnwrap(
            NFBundledRetrievalCatalog.target(id: "nf.retrieval.v1.general.rectangle-area-3-2")
        )
        XCTAssertTrue(NFBundledRetrievalCatalog.accepts("6 m²", for: rectangle))

        let cellVolume = try XCTUnwrap(
            NFBundledRetrievalCatalog.target(id: "nf.retrieval.v1.life-sciences.cube-volume-1")
        )
        XCTAssertTrue(NFBundledRetrievalCatalog.accepts("1 µm³", for: cellVolume))
    }

    func testLookupAndFieldFilteringAreStable() throws {
        let firstID = "nf.retrieval.v1.general.independent-variable"
        let lastID = "nf.retrieval.v1.data-science.correlation-range"
        let first = try XCTUnwrap(NFBundledRetrievalCatalog.target(id: firstID))
        let last = try XCTUnwrap(NFBundledRetrievalCatalog.target(id: lastID))

        XCTAssertEqual(first.field, .general)
        XCTAssertEqual(first.category, "experimental-design")
        XCTAssertEqual(last.field, .dataScience)
        XCTAssertEqual(last.category, "statistics")
        XCTAssertNil(NFBundledRetrievalCatalog.target(id: "nf.retrieval.v1.missing"))

        for field in STEMField.allCases {
            XCTAssertTrue(
                NFBundledRetrievalCatalog.targets(for: field).allSatisfy { $0.field == field },
                field.rawValue
            )
        }
    }

    func testCatalogAvoidsTimeSensitiveAndHighStakesAdviceLanguage() {
        let prohibitedPhrases = [
            "as of today", "currently recommended", "latest version", "medical diagnosis",
            "treatment dosage", "legal advice", "investment advice", "guaranteed outcome"
        ]
        for target in NFBundledRetrievalCatalog.targets {
            let text = [target.prompt, target.answer, target.explanation]
                .joined(separator: " ")
                .lowercased()
            for phrase in prohibitedPhrases {
                XCTAssertFalse(text.contains(phrase), "\(target.id) contains \(phrase)")
            }
        }
    }
}

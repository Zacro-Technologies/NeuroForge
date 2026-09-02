import XCTest

@testable import NeuroForge

final class RetrievalRuntimeScoringTests: XCTestCase {
    func testEveryBundledRetrievalAnswerUsesTheProductionExactMatcher() {
        for target in NFBundledRetrievalCatalog.targets {
            for answer in target.allAcceptedAnswers {
                XCTAssertTrue(
                    NFExerciseScoringEngine.validateNormalizedExact(
                        "  \(answer.uppercased())!  ",
                        acceptedAnswers: target.allAcceptedAnswers
                    ),
                    "Production scoring rejected \(target.id): \(answer)"
                )
            }
        }
    }

    func testExactMatcherPreservesUnitsSignsOperatorsAndGrouping() throws {
        let percent = try XCTUnwrap(
            NFBundledRetrievalCatalog.target(id: "nf.retrieval.v1.general.quarter-as-percent")
        )
        XCTAssertFalse(
            NFExerciseScoringEngine.validateNormalizedExact(
                "25",
                acceptedAnswers: percent.allAcceptedAnswers
            )
        )

        let quadratic = try XCTUnwrap(
            NFBundledRetrievalCatalog.target(id: "nf.retrieval.v1.mathematics.quadratic-formula")
        )
        XCTAssertTrue(
            NFExerciseScoringEngine.validateNormalizedExact(
                "(-b±sqrt(b^2-4ac))/(2a)",
                acceptedAnswers: quadratic.allAcceptedAnswers
            )
        )
        XCTAssertFalse(
            NFExerciseScoringEngine.validateNormalizedExact(
                "(b±sqrt(b^2-4ac))/(2a)",
                acceptedAnswers: quadratic.allAcceptedAnswers
            )
        )

        let correlation = try XCTUnwrap(
            NFBundledRetrievalCatalog.target(id: "nf.retrieval.v1.data-science.correlation-range")
        )
        XCTAssertFalse(
            NFExerciseScoringEngine.validateNormalizedExact(
                "1 to 1",
                acceptedAnswers: correlation.allAcceptedAnswers
            )
        )

        let precision = try XCTUnwrap(
            NFBundledRetrievalCatalog.target(id: "nf.retrieval.v1.data-science.precision")
        )
        XCTAssertTrue(
            NFExerciseScoringEngine.validateNormalizedExact(
                "TP / ( TP + FP )",
                acceptedAnswers: precision.allAcceptedAnswers
            )
        )
        XCTAssertFalse(
            NFExerciseScoringEngine.validateNormalizedExact(
                "TP / TP + FP",
                acceptedAnswers: precision.allAcceptedAnswers
            )
        )

        let deMorgan = try XCTUnwrap(
            NFBundledRetrievalCatalog.target(id: "nf.retrieval.v1.mathematics.de-morgan-conjunction")
        )
        XCTAssertFalse(
            NFExerciseScoringEngine.validateNormalizedExact(
                "A or B",
                acceptedAnswers: deMorgan.allAcceptedAnswers
            )
        )

        let gearRatio = try XCTUnwrap(
            NFBundledRetrievalCatalog.target(id: "nf.retrieval.v1.engineering.gear-ratio-20-40")
        )
        XCTAssertFalse(
            NFExerciseScoringEngine.validateNormalizedExact(
                "2.0 1",
                acceptedAnswers: gearRatio.allAcceptedAnswers
            )
        )

        let midpoint = try XCTUnwrap(
            NFBundledRetrievalCatalog.target(id: "nf.retrieval.v1.mathematics.midpoint-0-0-4-6")
        )
        XCTAssertFalse(
            NFExerciseScoringEngine.validateNormalizedExact(
                "(2 3)",
                acceptedAnswers: midpoint.allAcceptedAnswers
            )
        )

        let symbolicMidpoint = try XCTUnwrap(
            NFBundledRetrievalCatalog.target(id: "nf.retrieval.v1.mathematics.two-point-midpoint")
        )
        XCTAssertFalse(
            NFExerciseScoringEngine.validateNormalizedExact(
                "((x1+x2)/2 (y1+y2)/2)",
                acceptedAnswers: symbolicMidpoint.allAcceptedAnswers
            )
        )
    }

    func testRetrievalGenerationBiasesTheSelectedFieldWithoutClosingTheCatalog() throws {
        var fieldCounts: [STEMField: Int] = [:]
        var observedTargetIDs: Set<String> = []

        for seed in 0..<400 {
            let exercise = try NFFallbackExerciseGenerator.generate(
                NFExerciseGenerationRequest(
                    seed: UInt64(seed),
                    index: 0,
                    lab: .retrieval,
                    purpose: .practice,
                    sourceContext: NFExerciseSourceContext(primaryField: .physics)
                )
            )
            let tag = try XCTUnwrap(
                exercise.tags.first { $0.hasPrefix("knowledge-target.") }
            )
            let targetID = String(tag.dropFirst("knowledge-target.".count))
            let target = try XCTUnwrap(NFBundledRetrievalCatalog.target(id: targetID))
            fieldCounts[target.field, default: 0] += 1
            observedTargetIDs.insert(target.id)
        }

        XCTAssertGreaterThan(fieldCounts[.physics, default: 0], 200)
        XCTAssertGreaterThan(
            fieldCounts[.physics, default: 0],
            fieldCounts[.general, default: 0]
        )
        XCTAssertTrue(
            fieldCounts.contains { field, count in
                field != .physics && field != .general && count > 0
            },
            "The exploration share should keep non-preferred catalog fields reachable"
        )
        XCTAssertGreaterThan(observedTargetIDs.count, NFBundledRetrievalCatalog.requiredCountPerField)
    }
}

import XCTest
@testable import NeuroForge

final class MathContentContractTests: XCTestCase {
    func testExactRationalDecimalPercentageAndUnitBoundaries() throws {
        let zero = try NFExactNumber(numerator: 0)
        let third = try NFExactNumber(numerator: 1, denominator: 3)
        let rationalSchema = numericSchema(
            value: third,
            tolerance: .absolute(zero),
            legacyTolerance: .absolute(0)
        )
        XCTAssertTrue(validate("2/6", schema: rationalSchema).isCorrect)
        XCTAssertFalse(validate("0.3333333333333333", schema: rationalSchema).isCorrect)

        let tenth = try NFExactNumber(numerator: 1, denominator: 10)
        let decimalSchema = numericSchema(
            value: tenth,
            tolerance: .absolute(zero),
            legacyTolerance: .absolute(0)
        )
        XCTAssertTrue(validate("0.10", schema: decimalSchema).isCorrect)
        XCTAssertTrue(validate("1e-1", schema: decimalSchema).isCorrect)
        XCTAssertFalse(validate("0.1000000000000001", schema: decimalSchema).isCorrect)

        let percentageSchema = numericSchema(
            value: try NFExactNumber(numerator: 25, denominator: 2),
            tolerance: .absolute(try NFExactNumber(numerator: 1, denominator: 20)),
            legacyTolerance: .absolute(0.05),
            unit: "%",
            acceptedUnits: ["percent"]
        )
        XCTAssertTrue(validate("12.55%", schema: percentageSchema).isCorrect)
        XCTAssertFalse(validate("12.5501%", schema: percentageSchema).isCorrect)
        XCTAssertTrue(validate("12.45", unit: "percent", schema: percentageSchema).isCorrect)
        XCTAssertEqual(validate("12.5", schema: percentageSchema).errorCode, "unit_missing")

        let unitSchema = numericSchema(
            value: try NFExactNumber(numerator: 5, denominator: 4),
            tolerance: .absolute(try NFExactNumber(numerator: 1, denominator: 100)),
            legacyTolerance: .absolute(0.01),
            unit: "m",
            acceptedUnits: ["meter", "meters"]
        )
        XCTAssertTrue(validate("1.26", unit: "meters", schema: unitSchema).isCorrect)
        XCTAssertFalse(validate("1.2601", unit: "m", schema: unitSchema).isCorrect)
        XCTAssertEqual(validate("1.25", unit: "cm", schema: unitSchema).errorCode, "unit_mismatch")

        let relativeSchema = numericSchema(
            value: try NFExactNumber(numerator: 100),
            tolerance: .relative(try NFExactNumber(numerator: 1, denominator: 10)),
            legacyTolerance: .relative(0.1)
        )
        XCTAssertTrue(validate("110", schema: relativeSchema).isCorrect)
        XCTAssertTrue(validate("90", schema: relativeSchema).isCorrect)
        XCTAssertFalse(validate("110.0001", schema: relativeSchema).isCorrect)
    }

    func testNumericAnswerLegacyDecodeDerivesExactAuthorityAndNewRoundTripPreservesIt() throws {
        let answer = NFNumericAnswer(
            value: 0.1,
            tolerance: .absolute(0.001),
            canonicalUnit: nil,
            acceptedUnits: [],
            unitRequired: false,
            displayPrecision: 3
        )
        let encoded = try JSONEncoder().encode(answer)
        XCTAssertEqual(try JSONDecoder().decode(NFNumericAnswer.self, from: encoded), answer)

        var legacyObject = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        legacyObject.removeValue(forKey: "authoritativeValue")
        legacyObject.removeValue(forKey: "authoritativeTolerance")
        let legacyData = try JSONSerialization.data(withJSONObject: legacyObject, options: [.sortedKeys])
        let decoded = try JSONDecoder().decode(NFNumericAnswer.self, from: legacyData)
        XCTAssertEqual(decoded.value, 0.1)
        XCTAssertEqual(decoded.authoritativeValue, try NFExactNumber(numerator: 1, denominator: 10))
        XCTAssertEqual(
            decoded.authoritativeTolerance,
            .absolute(try NFExactNumber(numerator: 1, denominator: 1_000))
        )
    }

    func testExactToleranceBoundaryPropertySweepAcrossSignsAndDenominators() throws {
        for denominator in 1...12 {
            for numerator in -20...20 {
                let expected = try NFExactNumber(
                    numerator: Int64(numerator),
                    denominator: Int64(denominator)
                )
                let tolerance = try NFExactNumber(
                    numerator: 1,
                    denominator: Int64(denominator * 10)
                )
                let schema = numericSchema(
                    value: expected,
                    tolerance: .absolute(tolerance),
                    legacyTolerance: .absolute(tolerance.doubleValue)
                )
                let upperBoundary = try NFExactNumber(
                    numerator: Int64(numerator * 10 + 1),
                    denominator: Int64(denominator * 10)
                )
                let lowerBoundary = try NFExactNumber(
                    numerator: Int64(numerator * 10 - 1),
                    denominator: Int64(denominator * 10)
                )
                let outside = try NFExactNumber(
                    numerator: Int64(numerator * 100 + 11),
                    denominator: Int64(denominator * 100)
                )

                XCTAssertTrue(validate(upperBoundary.canonicalString, schema: schema).isCorrect)
                XCTAssertTrue(validate(lowerBoundary.canonicalString, schema: schema).isCorrect)
                XCTAssertFalse(validate(outside.canonicalString, schema: schema).isCorrect)
            }
        }
    }

    func testEstimateThenExactContractsCaptureAndScoreEachFieldSeparately() throws {
        let mental = try NFFallbackExerciseGenerator.generate(NFExerciseGenerationRequest(
            seed: 100,
            index: 0,
            lab: .mentalMath,
            purpose: .practice,
            preferredAssessmentMechanicID: "mentalMath.fallback-variant-7"
        ))
        let quantitative = try NFFallbackExerciseGenerator.generate(NFExerciseGenerationRequest(
            seed: 101,
            index: 0,
            lab: .quantitative,
            purpose: .practice,
            preferredAssessmentMechanicID: "quantitative.fallback-variant-2"
        ))

        for exercise in [mental, quantitative] {
            guard case let .logicState(schema) = exercise.interaction else {
                return XCTFail("Expected estimate/exact composite for \(exercise.templateID)")
            }
            XCTAssertTrue(NFEstimateExactContract.isComposite(schema))
            XCTAssertEqual(
                NFEstimateExactContract.orderedResponseKeys(for: schema),
                [
                    NFEstimateExactContract.estimateKey,
                    NFEstimateExactContract.plausibilityKey,
                    NFEstimateExactContract.exactKey
                ]
            )
            let response = NFExerciseResponse.logicState(
                NFLogicStateSubmission(finalState: schema.expectedFinalState, violatedRuleID: nil)
            )
            let persisted = try JSONEncoder().encode(response)
            XCTAssertEqual(try JSONDecoder().decode(NFExerciseResponse.self, from: persisted), response)
            XCTAssertTrue(NFExerciseScoringEngine.score(response, for: exercise).isCorrect)

            var wrongExact = schema.expectedFinalState
            wrongExact[NFEstimateExactContract.exactKey] = "wrong"
            let wrong = NFExerciseScoringEngine.score(
                .logicState(NFLogicStateSubmission(finalState: wrongExact, violatedRuleID: nil)),
                for: exercise
            )
            XCTAssertFalse(wrong.isCorrect)
            XCTAssertLessThan(wrong.credit, 1)
        }
    }

    func testCalculationChainDiagnosticReplayCannotAlterOriginalScore() throws {
        let contract = NFCalculationChainContract(
            initialValue: try NFExactNumber(numerator: 20),
            operations: [
                .add(try NFExactNumber(numerator: 5)),
                .multiply(try NFExactNumber(numerator: 3)),
                .subtract(try NFExactNumber(numerator: 7))
            ]
        )
        let replay = try XCTUnwrap(NFCalculationChainEngine.replay(contract))
        XCTAssertEqual(replay.map(\.output.canonicalString), ["25", "75", "68"])

        let firstDiagnostic = NFCalculationChainEngine.diagnose(
            contract: contract,
            submittedFinalValue: "67",
            learnerCheckpoints: ["25", "74", "67"]
        )
        XCTAssertFalse(firstDiagnostic.originalScoreIsCorrect)
        XCTAssertEqual(firstDiagnostic.originalCredit, 0)
        XCTAssertEqual(firstDiagnostic.firstMismatchedCheckpoint, 1)

        let correctedReplay = NFCalculationChainEngine.diagnose(
            contract: contract,
            submittedFinalValue: "67",
            learnerCheckpoints: ["25", "75", "68"]
        )
        XCTAssertFalse(correctedReplay.originalScoreIsCorrect)
        XCTAssertEqual(correctedReplay.originalCredit, 0)
        XCTAssertNil(correctedReplay.firstMismatchedCheckpoint)

        let exercise = try NFFallbackExerciseGenerator.generate(NFExerciseGenerationRequest(
            seed: 77,
            index: 0,
            lab: .mentalMath,
            purpose: .practice,
            preferredAssessmentMechanicID: "mentalMath.fallback-variant-6"
        ))
        let chainMetadata: [NFLogicRepresentationMetadata] = exercise.representations.compactMap { representation in
            guard case let .logicState(metadata) = representation else { return nil }
            return metadata
        }
        let metadata = try XCTUnwrap(chainMetadata.first)
        XCTAssertNotNil(NFCalculationChainContract(representation: metadata))
    }

    func testCubeNetCheckerExhaustivelyFindsElevenFreeNetsAndGeneratorUsesOnlyValidLayouts() throws {
        let validFixture = NFCubeNetLayout(cells: [
            NFCubeNetCell(x: 0, y: 0, label: "A"),
            NFCubeNetCell(x: 0, y: -1, label: "B"),
            NFCubeNetCell(x: 0, y: 1, label: "C"),
            NFCubeNetCell(x: -1, y: 0, label: "D"),
            NFCubeNetCell(x: 1, y: 0, label: "E"),
            NFCubeNetCell(x: 0, y: 2, label: "F")
        ])
        let invalidRectangle = NFCubeNetLayout(cells: (0..<2).flatMap { y in
            (0..<3).map { x in NFCubeNetCell(x: x, y: y, label: "\(x)-\(y)") }
        })
        XCTAssertTrue(NFCubeNetEngine.isValid(validFixture))
        XCTAssertFalse(NFCubeNetEngine.isValid(invalidRectangle))
        XCTAssertEqual(NFCubeNetEngine.validCanonicalLayouts.count, 11)
        XCTAssertTrue(NFCubeNetEngine.validCanonicalLayouts.allSatisfy(NFCubeNetEngine.isValid))

        for seed in 0..<256 {
            let exercise = try NFFallbackExerciseGenerator.generate(NFExerciseGenerationRequest(
                seed: UInt64(seed),
                index: seed,
                lab: .spatial,
                purpose: .practice,
                preferredAssessmentMechanicID: "spatial.fallback-variant-4"
            ))
            let spatialMetadata: [NFSpatialRepresentationMetadata] = exercise.representations.compactMap { representation in
                guard case let .spatial(metadata) = representation else { return nil }
                return metadata
            }
            let metadata = try XCTUnwrap(spatialMetadata.first)
            let layout = try XCTUnwrap(NFCubeNetLayout(encodedDescription: metadata.objectDescription))
            XCTAssertTrue(NFCubeNetEngine.isValid(layout))
            XCTAssertNotNil(NFCubeNetEngine.oppositeFace(to: "A", in: layout))
            XCTAssertTrue(exercise.tags.contains("algorithmically-validated-net"))
        }
    }

    func testProgressionGatesAccuracyFlexibilityAutomaticityAndTransferInOrder() {
        let start = Date(timeIntervalSince1970: 10_000)
        func observations(
            count: Int,
            wrongIndices: Set<Int> = [],
            timedIndices: Set<Int> = [],
            repeatedError: Bool = false
        ) -> [NFMentalMathProgressionObservation] {
            (0..<count).map { index in
                let wrong = wrongIndices.contains(index)
                return NFMentalMathProgressionObservation(
                    submittedAt: start.addingTimeInterval(Double(index)),
                    isCorrect: !wrong,
                    errorCode: wrong ? (repeatedError ? "percentage_base" : "error.\(index)") : nil,
                    strategyID: index.isMultiple(of: 2) ? "decompose" : "compensate",
                    wasTimed: timedIndices.contains(index)
                )
            }
        }

        let firstExposure = NFMentalMathProgressionPolicy.status(for: [])
        XCTAssertEqual(firstExposure.stage, .accuracy)
        XCTAssertFalse(firstExposure.timingEligible)

        let flexibility = NFMentalMathProgressionPolicy.status(for: observations(count: 8))
        XCTAssertEqual(flexibility.stage, .flexibility)
        XCTAssertFalse(flexibility.timingEligible)

        let automaticity = NFMentalMathProgressionPolicy.status(for: observations(count: 20))
        XCTAssertEqual(automaticity.stage, .automaticity)
        XCTAssertTrue(automaticity.timingEligible)
        XCTAssertFalse(automaticity.transferEligible)

        let transfer = NFMentalMathProgressionPolicy.status(
            for: observations(count: 20, timedIndices: Set(12..<20))
        )
        XCTAssertEqual(transfer.stage, .transfer)
        XCTAssertTrue(transfer.transferEligible)

        let misconception = NFMentalMathProgressionPolicy.status(
            for: observations(count: 20, wrongIndices: [18, 19], repeatedError: true)
        )
        XCTAssertEqual(misconception.rollingAccuracy, 0.9)
        XCTAssertEqual(misconception.stage, .flexibility)
        XCTAssertEqual(misconception.repeatedMisconceptionCodes, ["percentage_base"])
    }

    func testMentalMathMetricReducerKeepsSevenMetricsIndependent() throws {
        let start = Date(timeIntervalSince1970: 20_000)
        let reference = try NFExactNumber(numerator: 100)
        var observations: [NFMentalMathMetricObservation] = []
        for index in 0..<5 {
            observations.append(NFMentalMathMetricObservation(
                submittedAt: start.addingTimeInterval(Double(index)),
                credit: 1,
                wasTimed: true,
                activeDurationSeconds: Double(index + 2),
                tags: ["rapid-recall"],
                strategyID: index.isMultiple(of: 2) ? "decompose" : "compensate",
                strategyWasValid: index != 4,
                estimate: try NFExactNumber(numerator: Int64(90 + index * 5)),
                exactReference: reference,
                unitRequired: index < 3,
                unitWasCorrect: index < 3 ? index != 2 : nil
            ))
        }
        for index in 0..<3 {
            observations.append(NFMentalMathMetricObservation(
                submittedAt: start.addingTimeInterval(Double(10 + index)),
                credit: index == 2 ? 0 : 1,
                evidenceClass: .retention
            ))
            observations.append(NFMentalMathMetricObservation(
                submittedAt: start.addingTimeInterval(Double(20 + index)),
                credit: 1,
                evidenceClass: index == 0 ? .nearTransfer : .appliedTransfer
            ))
        }
        observations.append(NFMentalMathMetricObservation(
            submittedAt: start,
            credit: 1,
            evidenceClass: .documentPractice,
            tags: ["rapid-recall"]
        ))

        let metrics = NFMentalMathMetricReducer.reduce(observations)
        XCTAssertEqual(Set(metrics.keys), Set(NFMentalMathMetricKind.allCases))
        XCTAssertTrue(metrics.values.allSatisfy(\.isAvailable))
        XCTAssertEqual(try XCTUnwrap(metrics[.retrievalFluency]?.value), 4, accuracy: 1e-12)
        XCTAssertEqual(try XCTUnwrap(metrics[.strategyFlexibility]?.value), 0.8, accuracy: 1e-12)
        XCTAssertEqual(try XCTUnwrap(metrics[.unitHandling]?.value), 2.0 / 3.0, accuracy: 1e-12)
        XCTAssertEqual(try XCTUnwrap(metrics[.retention]?.value), 2.0 / 3.0, accuracy: 1e-12)
        XCTAssertEqual(try XCTUnwrap(metrics[.transfer]?.value), 1, accuracy: 1e-12)
        XCTAssertNotEqual(metrics[.independentAccuracy]?.value, metrics[.transfer]?.value)
    }

    func testFourDomainPacksEachProvideSixtyUniqueDeterministicDescriptors() throws {
        XCTAssertEqual(NFMentalMathDomainPackCatalog.packs.count, 4)
        var allIDs = Set<String>()
        for pack in NFMentalMathDomainPackCatalog.packs {
            XCTAssertGreaterThanOrEqual(pack.templates.count, 60)
            XCTAssertEqual(Set(pack.templates.map(\.id)).count, pack.templates.count)
            XCTAssertEqual(Set(pack.templates.map(\.operationFamily)).count, 10)
            XCTAssertTrue(pack.templates.allSatisfy {
                !$0.contextFrame.isEmpty
                    && !$0.examplePrompt.isEmpty
                    && !$0.authoritativeAnswer.isEmpty
                    && Set($0.fields) == Set(pack.fields)
            })
            for descriptor in pack.templates {
                XCTAssertTrue(allIDs.insert(descriptor.id).inserted)
            }
            let first = NFMentalMathDomainPackCatalog.deterministicTemplate(packID: pack.id, seed: 44)
            let duplicate = NFMentalMathDomainPackCatalog.deterministicTemplate(packID: pack.id, seed: 44)
            XCTAssertEqual(first, duplicate)
        }

        let fieldCases: [(STEMField, NFMentalMathDomainPackID)] = [
            (.mathematics, .mathematicsStatistics),
            (.physics, .physicsEngineering),
            (.engineering, .physicsEngineering),
            (.chemistry, .chemistryBiology),
            (.lifeSciences, .chemistryBiology),
            (.computing, .computerScienceData),
            (.dataScience, .computerScienceData)
        ]
        for (offset, entry) in fieldCases.enumerated() {
            let exercise = try NFFallbackExerciseGenerator.generate(NFExerciseGenerationRequest(
                seed: UInt64(4_000 + offset),
                index: offset,
                lab: .mentalMath,
                purpose: .practice,
                sourceContext: NFExerciseSourceContext(primaryField: entry.0)
            ))
            XCTAssertTrue(exercise.contextText?.contains(entry.0.title) == true)
            XCTAssertTrue(exercise.tags.contains("domain-pack.\(entry.1.rawValue)"))
        }
    }

    func testMentalMathInventoryProducesExactUnitConversionEvidence() throws {
        var unitExercise: NFExercise?
        for seed in 0..<256 where unitExercise == nil {
            let exercise = try NFFallbackExerciseGenerator.generate(NFExerciseGenerationRequest(
                seed: UInt64(seed),
                index: seed,
                lab: .mentalMath,
                purpose: .practice
            ))
            if exercise.tags.contains("unit-conversion") { unitExercise = exercise }
        }
        let exercise = try XCTUnwrap(unitExercise)
        guard case let .numeric(schema) = exercise.interaction else {
            return XCTFail("Mental-math unit conversion must use deterministic numeric validation")
        }
        XCTAssertTrue(schema.answer.unitRequired)
        XCTAssertEqual(schema.answer.canonicalUnit, "g")
        XCTAssertTrue(exercise.tags.contains("unit-handling"))
        let exactResponse = NFNumericSubmission(
            value: schema.answer.authoritativeValue.canonicalString,
            unit: "grams"
        )
        XCTAssertTrue(NFExerciseScoringEngine.validateNumeric(exactResponse, schema: schema).isCorrect)
        XCTAssertEqual(
            NFExerciseScoringEngine.validateNumeric(
                NFNumericSubmission(value: exactResponse.value, unit: nil),
                schema: schema
            ).errorCode,
            "unit_missing"
        )
    }

    private func numericSchema(
        value: NFExactNumber,
        tolerance: NFExactNumericTolerance,
        legacyTolerance: NFNumericTolerance,
        unit: String? = nil,
        acceptedUnits: [String] = []
    ) -> NFNumericResponseSchema {
        NFNumericResponseSchema(
            answer: NFNumericAnswer(
                authoritativeValue: value,
                authoritativeTolerance: tolerance,
                legacyTolerance: legacyTolerance,
                canonicalUnit: unit,
                acceptedUnits: acceptedUnits,
                displayPrecision: 6
            ),
            placeholder: "Value",
            permitsScientificNotation: true,
            permitsThousandsSeparators: true
        )
    }

    private func validate(
        _ value: String,
        unit: String? = nil,
        schema: NFNumericResponseSchema
    ) -> NFExerciseScoringEngine.NumericAuthorityResult {
        NFExerciseScoringEngine.validateNumeric(
            NFNumericSubmission(value: value, unit: unit),
            schema: schema
        )
    }
}

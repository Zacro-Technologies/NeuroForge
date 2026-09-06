import Foundation
import SwiftData
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


/// Uses the actual runtime, local file repository and exact scorer. No reviewed
/// band or authoring admission is manufactured by these synthetic fixtures.
@MainActor
final class MentalMathWorkflowTests: XCTestCase {
    private func exercise(_ variant: Int, seed: UInt64 = 20260905, purpose: NFExercisePurpose = .practice) throws -> NFExercise {
        try NFFallbackExerciseGenerator.generate(.init(seed: seed, index: 0, lab: .mentalMath,
            purpose: purpose, localeIdentifier: "en", preferredAssessmentMechanicID: "fixture.fallback-variant-\(variant)"))
    }
    private func store(_ repository: NFLocalSessionRepository? = nil) throws -> (AppStore, ModelContainer) {
        let container = try ModelContainer(for: Schema(NFSchemaV1.models),
            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        var draft = OnboardingDraft(); draft.aiMode = .disabled
        container.mainContext.insert(UserProfileRecord(draft: draft)); try container.mainContext.save()
        return (AppStore(context: container.mainContext, localSessionRepository: repository ?? NFLocalSessionRepository(),
            allowsSharedWidgetPublishing: false), container)
    }
    private func runtime(_ exercise: NFExercise, store: AppStore, legacy: Bool = false, pinMechanic: Bool = true) throws -> NFUniversalSessionRuntime {
        var request = SessionRequest(lab: exercise.lab, source: .focused, seed: exercise.seed,
            localeIdentifier: "en", evidenceClass: exercise.evidenceClass, requestedItemCount: 1,
            isTimed: false, mechanicID: pinMechanic ? NFDefaultContentCatalog.activity(id: exercise.contractMetadata?.familyID ?? "")?.mechanicID : nil)
        var checkpoint = try NFLocalItemCheckpoint.initial(request: request, exercise: exercise,
            slotID: UUID(), attemptID: UUID(), at: Date().addingTimeInterval(-1))
        if legacy { checkpoint.mathWork = nil }
        request.localCheckpoint = checkpoint; request.freshlyAcceptedLaunch = true
        let runtime = NFUniversalSessionRuntime(request: request)
        XCTAssertTrue(runtime.checkpointDraft(store: store)); runtime.resume(); runtime.acknowledgePresented()
        XCTAssertNil(runtime.unavailableReason); XCTAssertTrue(runtime.canEditDraft)
        return runtime
    }
    private func resumed(_ run: NFLocalSessionEnvelope, store: AppStore) -> NFUniversalSessionRuntime {
        var request = run.request; request.localSessionID = run.id; request.localCheckpoint = run.checkpoint
        request.freshlyAcceptedLaunch = false
        let value = NFUniversalSessionRuntime(request: request)
        XCTAssertTrue(value.checkpointDraft(store: store)); value.resume(); value.acknowledgePresented()
        return value
    }
    private func blockFolder(_ folder: URL, perform: () throws -> Void) throws {
        let backup = folder.appendingPathExtension("preserved")
        try FileManager.default.moveItem(at: folder, to: backup)
        try Data("Synthetic failed directory write".utf8).write(to: folder)
        defer {
            try? FileManager.default.removeItem(at: folder)
            try? FileManager.default.moveItem(at: backup, to: folder)
        }
        try perform()
    }

    func testEstimateMustBeDurablySavedBeforeExactWorkAndCannotBeOverwritten() throws {
        let (store, container) = try self.store(); defer { _ = container }
        let exercise = try self.exercise(7)
        guard case let .logicState(schema) = exercise.interaction else { return XCTFail("Composite fixture changed") }
        let runtime = try self.runtime(exercise, store: store)
        XCTAssertTrue(runtime.awaitsEstimateLock)
        XCTAssertFalse(NFMathWorkPolicy.presentationContext(exercise: exercise, draft: runtime.mathWork)?.contains("in that order") ?? false)
        XCTAssertEqual(runtime.visibleLogicKeys(schema), [NFEstimateExactContract.estimateKey])
        let estimate = try XCTUnwrap(schema.expectedFinalState[NFEstimateExactContract.estimateKey])
        runtime.logicState[NFEstimateExactContract.estimateKey] = estimate
        runtime.submitResponse() // No entry point may bypass the durable stage lock.
        XCTAssertEqual(runtime.stage, .item); XCTAssertTrue(store.attempts.isEmpty)
        runtime.submitInline(store: store)
        XCTAssertFalse(runtime.awaitsEstimateLock); XCTAssertEqual(runtime.stage, .item)
        XCTAssertNil(runtime.lastResult); XCTAssertTrue(store.attempts.isEmpty)
        XCTAssertEqual(runtime.visibleLogicKeys(schema), [NFEstimateExactContract.exactKey, NFEstimateExactContract.plausibilityKey])
        XCTAssertEqual(store.localSessions.archive.sessions.first?.checkpoint.mathWork?.lockedEstimate, estimate)
        XCTAssertEqual(runtime.prepareToClose(store: store), .saved)
        runtime.resume(); runtime.acknowledgePresented()
        runtime.logicState = schema.expectedFinalState
        runtime.logicState[NFEstimateExactContract.estimateKey] = "A later edit must not replace the saved estimate."
        runtime.submitInline(store: store)
        XCTAssertEqual(runtime.stage, .feedback); XCTAssertEqual(runtime.lastResult?.credit, 1)
        let attempt = try XCTUnwrap(store.attempts.first)
        let saved = try JSONDecoder().decode(NFExerciseResponse.self, from: Data(attempt.response.utf8))
        guard case let .logicState(response) = saved else { return XCTFail("Typed response missing") }
        XCTAssertEqual(response.finalState[NFEstimateExactContract.estimateKey], estimate)
        XCTAssertEqual(response.finalState[NFEstimateExactContract.exactKey], schema.expectedFinalState[NFEstimateExactContract.exactKey])
        let work = try XCTUnwrap(store.localSessions.archive.snapshots.first { $0.attemptID == attempt.id }?.mathWork)
        XCTAssertEqual(work.lockedEstimate, estimate)
        XCTAssertEqual(try JSONDecoder().decode(NFMathWorkDraft.self, from: JSONEncoder().encode(work)), work)
        XCTAssertTrue(work.isCompatible(with: exercise, response: saved))
        runtime.releaseWriter()
    }

    func testEstimateWriteFailureRetainsFirstStageAndColdResumeUsesExactSavedLock() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "NFMathStage-\(UUID())")
        defer { try? FileManager.default.removeItem(at: folder) }
        let owner = UUID(), url = folder.appending(path: "local.json")
        let repository = NFLocalSessionRepository(url: url, ownerDeviceID: owner)
        let (store, container) = try self.store(repository); defer { _ = container }
        let exercise = try self.exercise(7), runtime = try self.runtime(exercise, store: store)
        runtime.logicState[NFEstimateExactContract.estimateKey] = "10,000"
        let prior = try Data(contentsOf: url)
        try blockFolder(folder) {
            XCTAssertFalse(runtime.lockEstimate(store: store))
            XCTAssertTrue(runtime.awaitsEstimateLock); XCTAssertNil(runtime.mathWork?.lockedEstimate)
            XCTAssertEqual(runtime.logicState[NFEstimateExactContract.estimateKey], "10,000")
            XCTAssertTrue(store.attempts.isEmpty); XCTAssertNotNil(runtime.saveError)
        }
        XCTAssertEqual(try Data(contentsOf: url), prior)
        XCTAssertTrue(runtime.lockEstimate(store: store)); XCTAssertNil(runtime.saveError)
        let run = try XCTUnwrap(repository.archive.sessions.first)
        runtime.releaseWriter()
        let reopened = NFLocalSessionRepository(url: url, ownerDeviceID: owner)
        let (coldStore, coldContainer) = try self.store(reopened); defer { _ = coldContainer }
        let cold = resumed(run, store: coldStore)
        XCTAssertFalse(cold.awaitsEstimateLock); XCTAssertEqual(cold.mathWork?.lockedEstimate, "10,000")
        XCTAssertEqual(cold.logicState[NFEstimateExactContract.estimateKey], "10,000")
        XCTAssertTrue(coldStore.attempts.isEmpty); XCTAssertNil(cold.lastResult)
        cold.releaseWriter()
    }

    func testEstimateAlreadySavedLocallyRemainsLockedWhenLegacySummaryWriteFails() throws {
        enum Fault: Error { case legacySummary }
        let folder = FileManager.default.temporaryDirectory.appending(path: "NFMathMirror-\(UUID())")
        defer { try? FileManager.default.removeItem(at: folder) }
        let owner = UUID(), url = folder.appending(path: "local.json")
        let repository = NFLocalSessionRepository(url: url, ownerDeviceID: owner)
        let (store, container) = try self.store(repository); defer { _ = container }
        let runtime = try self.runtime(self.exercise(7), store: store)
        runtime.logicState[NFEstimateExactContract.estimateKey] = "10,000"
        runtime.legacyCheckpointWriteFailure = { throw Fault.legacySummary }
        XCTAssertFalse(runtime.lockEstimate(store: store), "The failed legacy projection is still reported.")
        XCTAssertFalse(runtime.awaitsEstimateLock, "The already saved estimate must never become editable again.")
        XCTAssertEqual(runtime.mathWork?.lockedEstimate, "10,000")
        XCTAssertNotNil(runtime.saveError)
        let coldRepository = NFLocalSessionRepository(url: url, ownerDeviceID: owner)
        let run = try XCTUnwrap(coldRepository.archive.sessions.first)
        XCTAssertEqual(run.checkpoint.mathWork, runtime.mathWork)
        XCTAssertTrue(store.attempts.isEmpty)
        runtime.legacyCheckpointWriteFailure = nil
        XCTAssertTrue(runtime.checkpointDraft(store: store))
        XCTAssertNil(runtime.saveError)
        runtime.releaseWriter()
        let latestRepository = NFLocalSessionRepository(url: url, ownerDeviceID: owner)
        let latestRun = try XCTUnwrap(latestRepository.archive.sessions.first)
        let (coldStore, coldContainer) = try self.store(latestRepository); defer { _ = coldContainer }
        let cold = resumed(latestRun, store: coldStore)
        XCTAssertFalse(cold.awaitsEstimateLock)
        XCTAssertEqual(cold.mathWork?.lockedEstimate, "10,000")
        XCTAssertTrue(coldStore.attempts.isEmpty)
        cold.releaseWriter()
    }

    func testLegacyAndFutureMathWorkAreNotAssignedInventedStages() throws {
        let (store, container) = try self.store(); defer { _ = container }
        let exercise = try self.exercise(7)
        guard case let .logicState(schema) = exercise.interaction else { return XCTFail("Expected composite") }
        let legacy = try self.runtime(exercise, store: store, legacy: true)
        XCTAssertNil(legacy.mathWork); XCTAssertFalse(legacy.awaitsEstimateLock)
        XCTAssertEqual(legacy.visibleLogicKeys(schema), NFEstimateExactContract.orderedResponseKeys(for: schema))
        legacy.logicState = schema.expectedFinalState; legacy.submitInline(store: store)
        XCTAssertEqual(legacy.lastResult?.credit, 1)
        XCTAssertNil(store.localSessions.archive.snapshots.first?.mathWork)
        legacy.releaseWriter()
        var request = SessionRequest(lab: .mentalMath, source: .focused, seed: 20260905,
            localeIdentifier: "en", requestedItemCount: 1, isTimed: false)
        var checkpoint = try NFLocalItemCheckpoint.initial(request: request, exercise: exercise,
            slotID: UUID(), attemptID: UUID(), at: Date().addingTimeInterval(-1))
        checkpoint.mathWork?.schemaVersion = 999
        let original = try JSONEncoder().encode(checkpoint)
        XCTAssertFalse(checkpoint.hasSupportedMathWork)
        request.localCheckpoint = checkpoint
        let future = NFUniversalSessionRuntime(request: request)
        XCTAssertNotNil(future.unavailableReason)
        let count = store.attempts.count; future.submitInline(store: store)
        XCTAssertEqual(store.attempts.count, count)
        XCTAssertEqual(request.localCheckpoint, checkpoint)
        XCTAssertEqual(try JSONDecoder().decode(NFLocalItemCheckpoint.self, from: original).mathWork?.schemaVersion, 999)
        var mixed = checkpoint; mixed.mathWork = .initial(for: exercise)
        mixed.response = .logicState(.init(finalState: schema.expectedFinalState, violatedRuleID: nil))
        XCTAssertFalse(mixed.hasSupportedMathWork, "An unlocked imported draft may not carry already-entered exact work")
    }

    func testOptionalChainWorkSurvivesResumeAndDiagnosesOnlyEnteredValuesWithoutChangingCredit() throws {
        let (store, container) = try self.store(); defer { _ = container }
        let exercise = try self.exercise(6), runtime = try self.runtime(exercise, store: store)
        let contract = try XCTUnwrap(runtime.mathWorkingContract)
        let replay = try XCTUnwrap(NFCalculationChainEngine.replay(contract))
        XCTAssertGreaterThan(replay.count, 1)
        runtime.toggleMathWorking(store: store)
        XCTAssertEqual(runtime.hintCount, 0, "Chain operations are already essential givens")
        runtime.setMathWorkingValue(replay[0].output.canonicalString, at: 0)
        runtime.setMathWorkingValue("-999999", at: 1)
        XCTAssertTrue(runtime.recoveryText.contains("-999999"))
        XCTAssertTrue(runtime.checkpointDraft(store: store))
        let run = try XCTUnwrap(store.localSessions.archive.sessions.first); runtime.releaseWriter()
        let cold = resumed(run, store: store)
        XCTAssertTrue(cold.mathWork?.workingExpanded == true)
        XCTAssertEqual(cold.mathWork?.workingValues[1], "-999999")
        guard case .numeric(let schema) = exercise.interaction else { return XCTFail("Expected numeric final answer") }
        cold.numericValue = schema.answer.authoritativeValue.canonicalString
        cold.numericUnit = schema.answer.canonicalUnit ?? ""
        cold.submitInline(store: store)
        XCTAssertEqual(cold.stage, .feedback); XCTAssertEqual(cold.lastResult?.credit, 1)
        XCTAssertEqual(cold.calculationChainDiagnostic?.firstMismatchedCheckpoint, 1)
        XCTAssertEqual(cold.calculationChainDiagnostic?.originalCredit, 1)
        let attempt = try XCTUnwrap(store.attempts.first)
        XCTAssertEqual(attempt.deterministicCredit, 1)
        XCTAssertEqual(store.localSessions.archive.snapshots.first { $0.attemptID == attempt.id }?.mathWork?.workingValues[1], "-999999")
        let empty = NFCalculationChainEngine.diagnose(contract: contract,
            submittedFinalValue: schema.answer.authoritativeValue.canonicalString,
            learnerCheckpoints: Array(repeating: "  ", count: replay.count))
        XCTAssertNil(empty.firstMismatchedCheckpoint, "Missing optional work must not become a guessed error")
        cold.releaseWriter()
    }

    func testCompensationUsesVerifiedOperandsThreeProgressiveHintsAndDurableWorkingExposure() throws {
        var seen: Set<Int64> = []
        for seed in 0..<48 {
            let value = try self.exercise(1, seed: UInt64(seed))
            let equation = try XCTUnwrap(value.representations.compactMap { representation -> String? in
                if case .equation(let latex, _) = representation { return latex }; return nil
            }.first)
            let parts = equation.components(separatedBy: "\\times").map { $0.trimmingCharacters(in: .whitespaces) }
            let left = try XCTUnwrap(Int64(parts[0])), right = try XCTUnwrap(Int64(parts[1])); seen.insert(right)
            let contract = try XCTUnwrap(NFMathWorkPolicy.workingContract(for: value))
            let steps = try XCTUnwrap(NFCalculationChainEngine.replay(contract))
            XCTAssertEqual(steps.last?.output.canonicalString, String(left * right)) // Independent integer oracle.
            let nearby = right == 9 || right == 19 ? right + 1 : right - 1
            XCTAssertEqual(steps[0].output.canonicalString, String(left * nearby))
            let hints = NFMathWorkPolicy.hints(for: value)
            XCTAssertEqual(hints.count, 3); XCTAssertFalse(hints[0].contains(String(left * nearby)))
            XCTAssertFalse(hints[1].contains(String(left * nearby))); XCTAssertTrue(hints[2].contains(String(left * nearby)))
            XCTAssertFalse(hints.contains { $0.contains(String(left * right)) })
        }
        XCTAssertEqual(seen, [9, 11, 19, 21])
        let folder = FileManager.default.temporaryDirectory.appending(path: "NFMathSupport-\(UUID())")
        defer { try? FileManager.default.removeItem(at: folder) }
        let repository = NFLocalSessionRepository(url: folder.appending(path: "local.json"), ownerDeviceID: UUID())
        let (store, container) = try self.store(repository); defer { _ = container }
        let value = try self.exercise(1), runtime = try self.runtime(value, store: store)
        try blockFolder(folder) {
            runtime.toggleMathWorking(store: store)
            XCTAssertFalse(runtime.mathWork?.workingExpanded ?? true)
            XCTAssertEqual(runtime.hintCount, 0); XCTAssertTrue(runtime.visibleHints.isEmpty)
            XCTAssertTrue(runtime.assistanceEvents.isEmpty)
        }
        runtime.toggleMathWorking(store: store)
        XCTAssertTrue(runtime.mathWork?.workingExpanded == true)
        XCTAssertEqual(runtime.hintCount, 2); XCTAssertEqual(runtime.assistanceEvents.count, 2)
        XCTAssertEqual(repository.archive.sessions.first?.checkpoint.hintCount, 2)
        var unsupportedSupport = try XCTUnwrap(repository.archive.sessions.first?.checkpoint)
        unsupportedSupport.hintCount = 0
        XCTAssertFalse(unsupportedSupport.hasSupportedMathWork, "An imported open strategy worksheet cannot claim no support")
        runtime.requestHint(store: store); XCTAssertEqual(runtime.hintCount, 3)
        let presentation = NFHistoryContextProjection.make(exercise: value, hintCount: 3,
            isProtected: false, mathWork: runtime.mathWork)
        XCTAssertEqual(presentation.usedHints, runtime.activeHintLadder)
        XCTAssertTrue(NFHistoryContextProjection.make(exercise: value, hintCount: 3,
            isProtected: true, mathWork: runtime.mathWork).usedHints.isEmpty)
        runtime.releaseWriter()
    }

    func testMathWorkRefusesProtectedWrongKeyAndUnboundedInputs() throws {
        let value = try self.exercise(1)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(value)) as? [String: Any])
        object["assessmentProtected"] = true
        let protected = try JSONDecoder().decode(NFExercise.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertNil(NFMathWorkDraft.initial(for: protected))
        object["assessmentProtected"] = false
        let wrongInteraction = NFExerciseInteraction.numeric(.init(answer: NFNumericAnswer(value: -12345,
            tolerance: .absolute(0), canonicalUnit: nil, acceptedUnits: [], unitRequired: false, displayPrecision: 0),
            placeholder: "Answer", permitsScientificNotation: true, permitsThousandsSeparators: true))
        object["interaction"] = try JSONSerialization.jsonObject(with: JSONEncoder().encode(wrongInteraction))
        let wrongKey = try JSONDecoder().decode(NFExercise.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertNil(NFMathWorkPolicy.workingContract(for: wrongKey))
        var work = try XCTUnwrap(NFMathWorkDraft.initial(for: value)); work.workingValues[0] = String(repeating: "7", count: 501)
        XCTAssertFalse(work.isSupported)
        let estimate = try XCTUnwrap(NFMathWorkDraft.initial(for: exercise(7)))
        XCTAssertNil(estimate.lockingEstimate("NaN", activeSeconds: 0))
        XCTAssertNil(estimate.lockingEstimate("1", activeSeconds: .infinity))
        XCTAssertNil(estimate.lockingEstimate(String(repeating: "1", count: 501), activeSeconds: 1))
        XCTAssertNotNil(estimate.lockingEstimate("-5/2", activeSeconds: 1))
    }
    func testGeneratedEstimateAdapterSavesLockAndColdResumesWithoutReconstructingIt() throws {
        let exercise = try self.exercise(7, purpose: .documentPractice)
        guard case .logicState(let schema) = exercise.interaction else { return XCTFail("Expected composite") }
        let id = UUID()
        let request = NFAuthoringRequest(id: id, capability: .contextualize, lab: .mentalMath,
            field: .general, customTopic: "Estimate a product", learningObjective: "Estimate before exact work",
            style: .numerical, difficulty: 0.3, count: 1, localeIdentifier: "en", seed: 20260905, aiMode: .disabled)
        let correct = schema.expectedFinalState.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: ",")
        let question = NFAuthoredQuestion(id: exercise.id, lab: exercise.lab, style: .numerical,
            prompt: exercise.prompt, context: exercise.contextText ?? "", choices: [], correctAnswer: correct,
            acceptedAnswers: [], explanation: exercise.feedback.correctExplanation, hint: exercise.feedback.hintLadder.first ?? "Estimate first.",
            decisiveStep: exercise.feedback.decisiveStep, difficulty: 0.3, citationChunkIDs: [],
            evidenceClass: .documentPractice, authoritativeExercise: exercise)
        XCTAssertTrue(NFAuthoredExerciseAuthority.validatesBinding(question))
        let result = NFAuthoringResult(questions: [question], provenance: .init(requestID: id,
            generatedAt: Date().addingTimeInterval(-1), route: .deterministicFallback, routeReason: "Synthetic exact-contract fixture",
            promptVersion: 1, modelIdentifier: "synthetic.math", sourceChunkIDs: [], sourceDocumentIDs: [],
            validationVersion: 1, repairCount: 0, cacheKey: "synthetic.math", isFallback: true), routeCandidates: [],
            validationStatus: .init(level: .deterministicKey, sourceSupport: .notApplicable), validationNotes: [])
        let (store, container) = try self.store(); defer { _ = container }
        let runtime = AIGeneratedPracticeRuntime(result: result, request: request)
        XCTAssertTrue(runtime.checkpoint(store: store)); runtime.resume()
        let estimate = try XCTUnwrap(schema.expectedFinalState[NFEstimateExactContract.estimateKey])
        runtime.logicState[NFEstimateExactContract.estimateKey] = estimate
        runtime.submit(store: store)
        XCTAssertEqual(runtime.stage, 0); XCTAssertFalse(runtime.awaitsEstimateLock)
        XCTAssertNil(runtime.lastScore); XCTAssertTrue(store.attempts.isEmpty)
        let draft = try XCTUnwrap(store.generatedPracticeDraft(for: id))
        XCTAssertTrue(draft.valid); XCTAssertEqual(draft.mathWork?.lockedEstimate, estimate)
        runtime.releaseWriter()
        let cold = AIGeneratedPracticeRuntime(result: result, request: request, draft: draft)
        XCTAssertTrue(cold.restoreCheckpoint(store: store)); cold.resume()
        XCTAssertEqual(cold.mathWork?.lockedEstimate, estimate)
        cold.logicState = schema.expectedFinalState
        cold.logicState[NFEstimateExactContract.estimateKey] = "A later edit"
        cold.submit(store: store)
        XCTAssertEqual(cold.stage, 2); XCTAssertEqual(cold.lastScore?.credit, 1)
        XCTAssertEqual(store.attempts.count, 1)
        XCTAssertEqual(store.localSessions.archive.snapshots.first?.mathWork?.lockedEstimate, estimate)
        cold.releaseWriter()
    }

    func testSimilarRepairKeepsTheSavedMathFamilyAndChangesTheSemanticQuestion() throws {
        let (store, container) = try self.store(); defer { _ = container }
        let value = try self.exercise(1), runtime = try self.runtime(value, store: store, pinMechanic: false)
        guard case .numeric(let schema) = value.interaction else { return XCTFail("Expected compensation") }
        runtime.numericValue = schema.answer.authoritativeValue.canonicalString
        runtime.numericUnit = schema.answer.canonicalUnit ?? ""; runtime.submitInline(store: store)
        XCTAssertEqual(runtime.stage, .feedback)
        let originalID = try XCTUnwrap(store.attempts.first?.id)
        runtime.retrySimilar(store: store)
        let request = try XCTUnwrap(store.activeSessionRequest)
        XCTAssertEqual(request.repairOriginAttemptID, originalID)
        let originalFamily = try XCTUnwrap(value.contractMetadata?.familyID)
        let originalActivity = try XCTUnwrap(NFDefaultContentCatalog.activity(id: originalFamily))
        XCTAssertEqual(request.mechanicID, originalActivity.mechanicID)
        let repair = NFUniversalSessionRuntime(request: request)
        XCTAssertNil(repair.unavailableReason)
        XCTAssertTrue(repair.exercise.tags.contains("compensation"))
        XCTAssertNotEqual(NFQuestionFingerprint.fingerprint(for: repair.exercise), NFQuestionFingerprint.fingerprint(for: value))
        runtime.releaseWriter(); repair.releaseWriter()
    }

}

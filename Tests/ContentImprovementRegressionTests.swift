import XCTest
import SwiftData
import RealityKit
@testable import NeuroForge

final class ContentImprovementRegressionTests: XCTestCase {

    func testObservationChartAndTablePreserveTheSameOriginalCountsAndScale() throws {
        for locale in ["en_US", "ja_JP"] {
            let exercise = try observationInspectionFixture(locale: locale)
            let representation = try XCTUnwrap(exercise.independentRepresentations.first)
            guard case let .table(headers, rows, summary) = representation,
                  case let .numeric(schema) = exercise.interaction else { return XCTFail("Expected the actual observed-proportion contract") }
            let data = try XCTUnwrap(NFInspectableDataProjection.make(exercise: exercise, representation: representation))
            XCTAssertEqual(data.headers, headers)
            XCTAssertEqual(data.accessibilitySummary, summary)
            XCTAssertEqual(data.localeIdentifier, locale)
            XCTAssertEqual(data.points.map(\.label), rows.map { $0[0] })
            XCTAssertEqual(data.points.map(\.originalValue), rows.map { $0[1] })
            XCTAssertEqual(data.points.map(\.count), try rows.map { try XCTUnwrap(Int($0[1])) })
            XCTAssertEqual(data.verticalRange.lowerBound, 0)
            XCTAssertEqual(data.verticalRange.upperBound, Double(try XCTUnwrap(data.points.map(\.count).max())))
            let observedPercentage = 100 * Double(data.points[0].count) / Double(data.points.reduce(0) { $0 + $1.count })
            XCTAssertEqual(schema.answer.value, observedPercentage, accuracy: 0.000_001)
            XCTAssertEqual(schema.answer.canonicalUnit, "%", "Chart values are counts; the learner's independent response is a percentage")
            for point in data.points {
                XCTAssertEqual(data.inspect(id: point.id), data.inspect(label: point.label),
                    "Pointer category selection and the native picker must identify the same exact row")
            }
            XCTAssertNil(data.inspect(id: -1))
            XCTAssertNil(data.inspect(label: "Missing outcome"))
        }
    }

    func testObservationInspectionRejectsProtectedFutureAndNonGivenContracts() throws {
        let original = try observationInspectionFixture()
        let representation = try XCTUnwrap(original.representations.first)
        let changes: [[String: Any]] = [
            ["assessmentProtected": true], ["purpose": NFExercisePurpose.assessmentHoldout.rawValue],
            ["evidenceClass": EvidenceClass.assessmentHoldout.rawValue], ["evidenceClass": EvidenceClass.nearTransfer.rawValue],
            ["schemaVersion": 999], ["generatorVersion": 999], ["templateID": "another.table.contract"],
            ["availabilityReason": "The original contract is unavailable."]
        ]
        for change in changes {
            let altered = try alteredObservationInspectionFixture(original, values: change)
            XCTAssertNil(NFInspectableDataProjection.make(exercise: altered, representation: representation))
        }
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(original)) as? [String: Any])
        var metadata = try XCTUnwrap(object["contractMetadata"] as? [String: Any])
        metadata["representationRoles"] = Array(repeating: NFInstructionalRole.workedExample.rawValue,
            count: original.representations.count)
        object["contractMetadata"] = metadata
        let worked = try JSONDecoder().decode(NFExercise.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertNil(NFInspectableDataProjection.make(exercise: worked, representation: representation),
            "An explanatory representation cannot be promoted to independent inspection")
        let unrelated = NFExerciseRepresentation.table(headers: ["Time", "Distance"], rows: [["1", "4"], ["2", "8"]],
            accessibilitySummary: "The second observation has a greater distance.")
        XCTAssertNil(NFInspectableDataProjection.make(exercise: original, representation: unrelated))
    }

    func testObservationInspectionDoesNotGuessMalformedCountOrCategoryValues() throws {
        let original = try observationInspectionFixture()
        guard case let .table(headers, rows, summary) = original.representations.first else {
            return XCTFail("Expected the original count table")
        }
        let originalBytes = try NFImmutableAttemptRecordSnapshot.encoded(original)
        for invalid in ["", "-1", "0", "1.5", "1,000", "NaN", "1e300", String(repeating: "9", count: 100)] {
            let bad = NFExerciseRepresentation.table(headers: headers,
                rows: [[rows[0][0], invalid], rows[1]], accessibilitySummary: summary)
            var representations = original.representations
            representations[0] = bad
            let changed = try alteredObservationInspectionFixture(original,
                values: ["representations": try JSONSerialization.jsonObject(with: JSONEncoder().encode(representations))])
            XCTAssertNil(NFInspectableDataProjection.make(exercise: changed, representation: bad), invalid)
        }
        for bad in [
            NFExerciseRepresentation.table(headers: headers, rows: [[rows[0][0], "2"], [rows[0][0], "3"]], accessibilitySummary: summary),
            .table(headers: ["", headers[1]], rows: rows, accessibilitySummary: summary),
            .table(headers: headers, rows: [[rows[0][0], "2", "unexpected"], rows[1]], accessibilitySummary: summary)
        ] {
            var representations = original.representations
            representations[0] = bad
            let changed = try alteredObservationInspectionFixture(original,
                values: ["representations": try JSONSerialization.jsonObject(with: JSONEncoder().encode(representations))])
            XCTAssertNil(NFInspectableDataProjection.make(exercise: changed, representation: bad))
        }
        XCTAssertEqual(try NFImmutableAttemptRecordSnapshot.encoded(original), originalBytes)
    }

    private func observationInspectionFixture(locale: String = "en_US") throws -> NFExercise {
        try NFFallbackExerciseGenerator.generate(.init(seed: 721, index: 0, lab: .quantitative,
            purpose: .practice, localeIdentifier: locale, preferredAssessmentMechanicID: "fixture.fallback-variant-0"))
    }

    private func alteredObservationInspectionFixture(_ original: NFExercise, values: [String: Any]) throws -> NFExercise {
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(original)) as? [String: Any])
        object.merge(values) { _, value in value }
        return try JSONDecoder().decode(NFExercise.self, from: JSONSerialization.data(withJSONObject: object))
    }
    func testSpatialRenderingRejectsUnrepresentableAndOversizedOriginalGeometry() {
        func metadata(points: [NFSpatialPoint], complexity: Double = 0.5) -> NFSpatialRepresentationMetadata {
            .init(stimulusCategory: "coordinate", dimension: .threeDimensional,
                objectDescription: "Original points", viewpoint: "front", operations: [], points: points,
                axisLabels: ["x", "y", "z"], accessibilityDescription: "Original source description.",
                assetName: nil, protectedGrammarID: nil,
                difficultyParameters: .init(stimulusCategory: "coordinate", viewpoint: "front",
                    rotationMagnitudeDegrees: 0, objectComplexity: complexity, distractorSimilarity: 0.5,
                    responseMode: .coordinateEntry))
        }
        let point = NFSpatialPoint(label: "A", x: 2, y: -3, z: 4)
        XCTAssertTrue(NFSpatialRenderingSafety.permits(metadata(points: [point])))
        for invalid in [Double.greatestFiniteMagnitude, .infinity, .nan] {
            let original = metadata(points: [.init(label: "A", x: invalid, y: 0, z: nil)])
            XCTAssertFalse(NFSpatialRenderingSafety.permits(original))
            XCTAssertEqual(original.accessibilityDescription, "Original source description.")
            if invalid.isFinite { XCTAssertEqual(original.points[0].x, invalid) }
        }
        XCTAssertFalse(NFSpatialRenderingSafety.permits(metadata(points: [point], complexity: 1e300)))
        XCTAssertTrue(NFSpatialRenderingSafety.permits(metadata(points: Array(repeating: point, count: NFSpatialRenderingSafety.maximumPointCount))))
        XCTAssertFalse(NFSpatialRenderingSafety.permits(metadata(points: Array(repeating: point, count: NFSpatialRenderingSafety.maximumPointCount + 1))))
    }

    func testSpatialCoordinateLabelsDoNotConvertUnboundedDoublesToIntegers() {
        let locale = Locale(identifier: "en_US_POSIX")
        XCTAssertEqual(NFSpatialRenderingSafety.coordinateLabel(4, locale: locale), "4")
        XCTAssertEqual(NFSpatialRenderingSafety.coordinateLabel(-3.5, locale: locale), "-3.5")
        XCTAssertEqual(NFSpatialRenderingSafety.coordinateLabel(-3.5, locale: Locale(identifier: "de_DE")), "-3,5")
        XCTAssertFalse(NFSpatialRenderingSafety.coordinateLabel(1e300, locale: locale).isEmpty)
        XCTAssertLessThan(NFSpatialRenderingSafety.coordinateLabel(1e300, locale: locale).count, 40)
        XCTAssertEqual(NFSpatialRenderingSafety.coordinateLabel(.infinity, locale: locale), "—")
    }

    func testFrozenGermanEstimateExactAliasesAreInvalidItemsWithoutChangingSavedAnswers() throws {
        // These are the exact aliases previously emitted by regional integer
        // formatting: 198 × 48 = 9504, but "9.504" parses as 9504/1000.
        let contract = NFEstimateExactContract(estimate: "10000",
            acceptedEstimateAlternatives: [10_000.formatted(.number.locale(Locale(identifier: "de_DE")))],
            plausibility: "plausible", acceptedPlausibilityAlternatives: ["yes"], exact: "9504",
            acceptedExactAlternatives: [9_504.formatted(.number.locale(Locale(identifier: "de_DE")))])
        let schema = contract.responseSchema
        let item = try exercise(.logicState(schema))
        let wrong = NFExerciseResponse.logicState(.init(finalState: [NFEstimateExactContract.estimateKey: "10.000",
            NFEstimateExactContract.plausibilityKey: "yes", NFEstimateExactContract.exactKey: "9.504"], violatedRuleID: nil))
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let itemBytes = try encoder.encode(item)
        let responseBytes = try encoder.encode(wrong)
        XCTAssertTrue(schema.acceptedEquivalentStates.contains {
            $0[NFEstimateExactContract.exactKey] == "9.504" && $0[NFEstimateExactContract.estimateKey] == "10.000"
        })
        XCTAssertEqual(NFStateValueAuthority.exactNumber("9.504"), try NFExactNumber(numerator: 9504, denominator: 1000))
        XCTAssertTrue(NFExerciseSchemaValidator.hasContradictoryEstimateExactNumericAliases(schema))
        XCTAssertThrowsError(try NFExerciseSchemaValidator.validateInteraction(item.interaction))
        for response in [wrong, .logicState(.init(finalState: schema.expectedFinalState, violatedRuleID: nil))] {
            let result = NFExerciseScoringEngine.score(response, for: item)
            XCTAssertEqual(result.outcome, .invalidItem)
            XCTAssertNil(result.objectiveCorrectness)
            XCTAssertNil(result.expectedAnswerSummary)
            XCTAssertNil(result.normalizedResponse)
        }
        XCTAssertEqual(try encoder.encode(item), itemBytes)
        XCTAssertEqual(try encoder.encode(wrong), responseBytes)
    }

    func testExactAliasGuardPreservesCanonicalJudgmentEstimateAndUnrelatedLogicAlternatives() throws {
        let contract = NFEstimateExactContract(estimate: "10000", acceptedEstimateAlternatives: ["9000"],
            plausibility: "plausible", acceptedPlausibilityAlternatives: ["yes"], exact: "9504",
            acceptedExactAlternatives: ["9,504", "9504.0", "9504/1"])
        let schema = contract.responseSchema
        let item = try exercise(.logicState(schema))
        XCTAssertFalse(NFExerciseSchemaValidator.hasContradictoryEstimateExactNumericAliases(schema))
        XCTAssertNoThrow(try NFExerciseSchemaValidator.validateInteraction(item.interaction))
        for state in [schema.expectedFinalState] + schema.acceptedEquivalentStates {
            XCTAssertEqual(NFExerciseScoringEngine.score(.logicState(.init(finalState: state, violatedRuleID: nil)), for: item).outcome, .correct)
        }
        let alternative = [NFEstimateExactContract.estimateKey: "10", NFEstimateExactContract.plausibilityKey: "yes",
            NFEstimateExactContract.exactKey: "9.504"]
        let unrelated = NFLogicStateResponseSchema(initialState: ["contract": "different-valid-outputs.v1"],
            expectedFinalState: schema.expectedFinalState, acceptedEquivalentStates: [alternative],
            ruleOptions: [], expectedViolatedRuleID: nil, fieldDomains: schema.fieldDomains)
        XCTAssertFalse(NFExerciseSchemaValidator.hasContradictoryEstimateExactNumericAliases(unrelated))
        let unrelatedItem = try exercise(.logicState(unrelated))
        XCTAssertNoThrow(try NFExerciseSchemaValidator.validateInteraction(unrelatedItem.interaction))
        XCTAssertEqual(NFExerciseScoringEngine.score(.logicState(.init(finalState: alternative, violatedRuleID: nil)), for: unrelatedItem).outcome, .correct)
        let unitContract = NFEstimateExactContract(estimate: "about 10 m", acceptedEstimateAlternatives: ["10 m"],
            plausibility: "smaller", acceptedPlausibilityAlternatives: ["smaller numeric value"], exact: "9.504 m",
            acceptedExactAlternatives: ["1188/125 m"])
        XCTAssertNoThrow(try NFExerciseSchemaValidator.validateInteraction(.logicState(unitContract.responseSchema)))
    }

    func testEstimateKeysStayCanonicalAcrossRegionsAndRejectThousandfoldErrors() throws {
        // A regional display is not a numeric alias: this is ten under the
        // canonical decimal grammar, although it displays ten thousand in DE.
        let germanDisplay = 10_000.formatted(.number.locale(Locale(identifier: "de_DE")))
        XCTAssertEqual(germanDisplay, "10.000")
        XCTAssertNotEqual(NFStateValueAuthority.exactNumber(germanDisplay), try NFExactNumber(numerator: 10_000))
        var scientificChoices: [String] = []
        for region in ["en_US", "de_DE"] {
            let item = try NFFallbackExerciseGenerator.generate(.init(seed: 4391, index: 0, lab: .mentalMath,
                purpose: .practice, localeIdentifier: region, preferredAssessmentMechanicID: "fixture.fallback-variant-3"))
            guard case let .singleChoice(schema) = item.interaction else { return XCTFail("Expected scientific-notation choices") }
            scientificChoices.append(try XCTUnwrap(schema.options.first { $0.id == schema.correctOptionID }).text)
        }
        XCTAssertTrue(scientificChoices[0].contains("."))
        XCTAssertTrue(scientificChoices[1].contains(","))
        XCTAssertEqual(scientificChoices[0], scientificChoices[1].replacingOccurrences(of: ",", with: "."))
        for seed in 0..<32 {
            var reference: NFExerciseInteraction?
            for region in ["en_US", "de_DE", "fr_FR"] {
                let item = try NFFallbackExerciseGenerator.generate(.init(seed: UInt64(seed), index: 0,
                    lab: .mentalMath, purpose: .practice, localeIdentifier: region,
                    preferredAssessmentMechanicID: "fixture.fallback-variant-7"))
                guard case let .logicState(schema) = item.interaction else { return XCTFail("Expected estimate/exact contract") }
                if let reference { XCTAssertEqual(item.interaction, reference, "seed \(seed), region \(region)") }
                else { reference = item.interaction }
                for state in [schema.expectedFinalState] + schema.acceptedEquivalentStates {
                    for key in [NFEstimateExactContract.estimateKey, NFEstimateExactContract.exactKey] {
                        let text = try XCTUnwrap(state[key])
                        XCTAssertEqual(text, try XCTUnwrap(NFStateValueAuthority.exactNumber(text)).canonicalString)
                    }
                }
                XCTAssertEqual(NFExerciseScoringEngine.score(.logicState(.init(finalState: schema.expectedFinalState,
                    violatedRuleID: nil)), for: item).outcome, .correct)
                var wrong = schema.expectedFinalState
                for key in [NFEstimateExactContract.estimateKey, NFEstimateExactContract.exactKey] {
                    let integer = try XCTUnwrap(Int64(try XCTUnwrap(wrong[key])))
                    wrong[key] = try NFExactNumber(numerator: integer, denominator: 1_000).canonicalString
                }
                let score = NFExerciseScoringEngine.score(.logicState(.init(finalState: wrong, violatedRuleID: nil)), for: item)
                XCTAssertFalse(score.isCorrect, "seed \(seed), region \(region)")
                // The ratio remains plausible, but the fixed whole-answer
                // rubric cannot award credit to the two incorrect quantities.
                XCTAssertEqual(score.credit, 0)
            }
        }
    }

    @MainActor
    func testSavedRequestLocalePinsNumericAndCubeContentAcrossChromeLanguageChanges() throws {
        for (lab, variant) in [(TrainingLab.mentalMath, 0), (.spatial, 4)] {
            let request = NFExerciseGenerationRequest(seed: 4391, index: 0, lab: lab, purpose: .practice,
                localeIdentifier: "en", preferredAssessmentMechanicID: "fixture.fallback-variant-\(variant)")
            let original = try withChromeLanguage("en") { try NFFallbackExerciseGenerator.generate(request) }
            let replay = try withChromeLanguage("ja") {
                XCTAssertEqual(NFAppLocalization.preferredLanguageCode, "ja")
                return try NFFallbackExerciseGenerator.generate(request)
            }
            XCTAssertEqual(replay, original)
            XCTAssertEqual(try NFLocalItemCheckpoint.digest(replay), try NFLocalItemCheckpoint.digest(original))
        }
    }

    @MainActor
    func testColdProtectedNumericResumeUsesSavedEnglishLocaleUnderJapaneseChrome() throws {
        let container = try ModelContainer(for: Schema(NFSchemaV1.models), configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let repository = NFLocalSessionRepository()
        let store = AppStore(context: container.mainContext, localSessionRepository: repository, allowsSharedWidgetPublishing: false)
        let runtime = try withChromeLanguage("en") { () throws -> NFUniversalSessionRuntime in
            for seed in 0..<32 {
                let request = SessionRequest(lab: .mentalMath, source: .reassessment, seed: UInt64(seed), localeIdentifier: "en",
                    requestedMinutes: 5, evidenceClass: .assessmentHoldout, requestedItemCount: 5,
                    assessmentBlock: .numericalFluency, reassessmentCycle: 1)
                let candidate = NFUniversalSessionRuntime(request: request)
                if case .numeric = candidate.exercise.interaction {
                    XCTAssertTrue(candidate.exercise.assessmentProtected)
                    candidate.numericValue = "123.5"
                    candidate.scratchpad = "Retain my working"
                    XCTAssertTrue(candidate.checkpointDraft(store: store))
                    candidate.releaseWriter()
                    return candidate
                }
            }
            throw NFLocalSessionRepository.RepositoryError.unavailableLaunch
        }
        let original = runtime.exercise
        let archive = try JSONDecoder().decode(NFLocalSessionRepository.Archive.self, from: JSONEncoder().encode(repository.archive))
        let saved = try XCTUnwrap(archive.sessions.first)
        XCTAssertNil(saved.checkpoint.exercise, "A protected resume must regenerate its original undisclosed contract")
        var request = saved.request
        request.localSessionID = saved.id
        request.localCheckpoint = saved.checkpoint
        let replay = withChromeLanguage("ja") { NFUniversalSessionRuntime(request: request) }
        XCTAssertNil(replay.unavailableReason)
        XCTAssertEqual(replay.exercise, original)
        XCTAssertEqual(replay.numericValue, "123.5")
        XCTAssertEqual(replay.scratchpad, "Retain my working")
        XCTAssertTrue(replay.isPaused)
        XCTAssertEqual(replay.assessmentDescriptor, saved.checkpoint.descriptor)
    }

    /// Volatile argument overrides affect this process only and are restored
    /// synchronously. These fixtures never write the learner's saved preference.
    @MainActor
    private func withChromeLanguage<T>(_ code: String, _ operation: () throws -> T) rethrows -> T {
        let defaults = UserDefaults.standard
        let previous = defaults.volatileDomain(forName: UserDefaults.argumentDomain)
        var override = previous
        override[NFAppLocalization.preferredLanguageDefaultsKey] = code
        defaults.setVolatileDomain(override, forName: UserDefaults.argumentDomain)
        defer { defaults.setVolatileDomain(previous, forName: UserDefaults.argumentDomain) }
        return try operation()
    }

    func testS01EquivalentCoordinateOptionsInvalidateTheItemRatherThanPenalizeOneChoice() throws {
        let duplicate = NFSingleChoiceResponseSchema(options: [
            option("a", "(-10, 10)"), option("b", "(-10.0, 10.00)"), option("c", "(10, -10)")
        ], correctOptionID: "a")
        let item = try exercise(.singleChoice(duplicate))
        for id in ["a", "b", "c"] {
            let score = NFExerciseScoringEngine.score(.singleChoice(optionID: id), for: item)
            XCTAssertEqual(score.outcome, .invalidItem)
            XCTAssertNil(score.objectiveCorrectness)
        }
        for seed in 0..<300 {
            let item = try NFFallbackExerciseGenerator.generate(.init(seed: UInt64(seed), index: 0, lab: .spatial, purpose: .practice))
            guard case let .singleChoice(schema) = item.interaction else { return XCTFail("Spatial choice required") }
            XCTAssertTrue(NFAnswerSemanticIdentity.hasDistinctOptions(schema.options), "seed \(seed)")
            if item.templateID.contains("coordinate.rotate-ccw"),
               case let .spatial(stimulus)? = item.representations.first, let point = stimulus.points.first {
                let answer = schema.options.first { $0.id == schema.correctOptionID }?.text ?? ""
                // Independent active quarter-turn oracle (matrix [0,-1;1,0]).
                XCTAssertEqual(NFAnswerSemanticIdentity.canonical(answer),
                    NFAnswerSemanticIdentity.canonical("(\(-point.y), \(point.x))"))
            }
        }
    }

    func testS01StructuredTransferOptionsRemainDistinctAndAgreeWithIndependentTableOracle() throws {
        for seed in 0..<200 {
            let brief = NFExerciseTransferBrief(missionID: "duplicate-slope-regression", seed: UInt64(seed), kind: .multiRepresentationTransform,
                labs: [.quantitative, .logicDebugging], skillIDs: [TrainingLab.quantitative.skillID, TrainingLab.logicDebugging.skillID], requiredDimensions: ["representation"])
            let item = try NFFallbackExerciseGenerator.generate(.init(seed: UInt64(seed), index: 0, lab: .transfer, purpose: .appliedTransfer,
                sourceContext: .init(transferBrief: brief)))
            guard case let .singleChoice(schema) = item.interaction,
                  case let .table(_, rows, _)? = item.representations.first else { return XCTFail("Expected table-to-equation item") }
            XCTAssertTrue(NFAnswerSemanticIdentity.hasDistinctOptions(schema.options), "seed \(seed)")
            let intercept = try XCTUnwrap(Int(rows[0][1]))
            let slope = try XCTUnwrap(Int(rows[1][1])) - intercept
            XCTAssertEqual(schema.options.first { $0.id == schema.correctOptionID }?.text, "y = \(slope)x + \(intercept)")
            XCTAssertEqual(try XCTUnwrap(Int(rows[2][1])), 3 * slope + intercept)
        }
    }

    func testS02IntervalGeometryExhaustsTheAuthoredDomainWithoutUsingItAsAnInferenceTest() throws {
        XCTAssertThrowsError(try NFClosedInterval(lower: 2, upper: 1))
        for low in 15..<65 {
            for difference in 3..<23 {
                let high = low + difference
                let a = try NFClosedInterval(lower: Double(low - 3), upper: Double(low + 5))
                let b = try NFClosedInterval(lower: Double(high - 5), upper: Double(high + 3))
                let expected: NFClosedInterval.Relationship = difference < 10 ? .overlapping : (difference == 10 ? .touching : .disjoint)
                XCTAssertEqual(a.relationship(to: b), expected)
                XCTAssertEqual(b.relationship(to: a), expected)
            }
        }
        XCTAssertEqual(try NFClosedInterval(lower: 18, upper: 26).relationship(to: NFClosedInterval(lower: 27, upper: 35)), .disjoint)
        for seed in 0..<150 {
            let item = try NFFallbackExerciseGenerator.generate(.init(seed: UInt64(seed), index: 0, lab: .scientificReasoning, purpose: .practice,
                preferredAssessmentMechanicID: NFDefaultContentCatalog.activities.first { $0.id == "nf.default.science.figure-uncertainty" }?.mechanicID))
            XCTAssertTrue(item.templateID.contains("data-forensics.uncertainty"))
            XCTAssertFalse(item.prompt.contains("with overlapping"))
            XCTAssertTrue(item.contextText?.contains("not calculated from") == true)
            XCTAssertTrue(item.feedback.correctExplanation.contains("geometry alone"))
        }
    }

    func testS03AndS04SymbolicEquivalenceRetainsCaseFunctionRolesAndDomainBoundaries() throws {
        let derivative = NFShortTextResponseSchema(expectedAnswer: "4x", scoringRule: .normalizedExact(acceptedAnswers: ["4x"]), maximumCharacters: 280,
            authority: .symbolic(.init(acceptedExpressions: ["4*x"], variables: ["x"])))
        let item = try exercise(.shortText(derivative))
        for value in ["4x", "4*x", "4×x", "2x+2x", "4x^1", "((4*x))", "8x/2"] {
            let score = NFExerciseScoringEngine.score(.shortText(value), for: item)
            XCTAssertEqual(score.outcome, .correct, value)
            XCTAssertEqual(score.credit, 1, value)
        }
        XCTAssertEqual(NFExerciseScoringEngine.score(.shortText("2x"), for: item).outcome, .incorrect)
        for unsupported in ["4/x", "sin(x)", "x^99", String(repeating: "(", count: 33) + "x" + String(repeating: ")", count: 33), "((x^12)^12)^12", "0^0"] {
            XCTAssertEqual(NFExerciseScoringEngine.score(.shortText(unsupported), for: item).outcome, .needsClarification, unsupported)
        }
        let integral = try exercise(.shortText(.init(expectedAnswer: "F(b)-F(a)", scoringRule: .normalizedExact(acceptedAnswers: ["F(b)-F(a)"]), maximumCharacters: 280,
            authority: .symbolic(.init(acceptedExpressions: ["F(b)-F(a)"], variables: ["a", "b"], functions: ["F", "f"])))))
        XCTAssertEqual(NFExerciseScoringEngine.score(.shortText("(F(b))-((F(a)))"), for: integral).outcome, .correct)
        for wrong in ["f(b)-f(a)", "F(a)-F(b)", "F*b-F*a"] {
            XCTAssertNotEqual(NFExerciseScoringEngine.score(.shortText(wrong), for: integral).outcome, .correct)
        }
    }

    func testS03ProseAcceptsReviewedRelationsRejectsContradictionsAndClarifiesUnknownCoverage() throws {
        let target = try XCTUnwrap(NFBundledRetrievalCatalog.target(id: "nf.retrieval.v1.general.arithmetic-mean"))
        let fact = NFExerciseGroundingFact(id: target.id, statement: target.prompt, expectedAnswer: target.answer, acceptedAlternatives: target.acceptedAnswers, citationIDs: [])
        let item = try exercise(.shortText(.init(expectedAnswer: target.answer, scoringRule: .normalizedExact(acceptedAnswers: target.allAcceptedAnswers), maximumCharacters: 280,
            authority: NFRetrievalResponseAuthority.authority(for: fact))))
        for value in ["Sum all observations then divide by their count", "Sum observations / number of observations"] {
            XCTAssertEqual(NFExerciseScoringEngine.score(.shortText(value), for: item).outcome, .correct)
        }
        for value in ["Divide the count by the total", "Do not divide by the count", "Sum divided by count, but do not divide by the count"] {
            XCTAssertEqual(NFExerciseScoringEngine.score(.shortText(value), for: item).outcome, .incorrect)
        }
        let unknown = NFExerciseScoringEngine.score(.shortText("Use the collective centre procedure"), for: item)
        XCTAssertEqual(unknown.outcome, .needsClarification)
        XCTAssertNil(unknown.objectiveCorrectness)
    }

    func testS05EveryDeclaredEstimateAliasReceivesIdenticalFullCredit() throws {
        let contract = NFEstimateExactContract(estimate: "10000", acceptedEstimateAlternatives: ["10,000"], plausibility: "plausible", acceptedPlausibilityAlternatives: ["yes"], exact: "9504", acceptedExactAlternatives: ["9,504"])
        let item = try exercise(.logicState(contract.responseSchema))
        for state in [contract.responseSchema.expectedFinalState] + contract.responseSchema.acceptedEquivalentStates {
            let score = NFExerciseScoringEngine.score(.logicState(.init(finalState: state, violatedRuleID: nil)), for: item)
            XCTAssertEqual(score.outcome, .correct)
            XCTAssertEqual(score.credit, 1)
            XCTAssertEqual(score.components.map(\.awardedCredit).reduce(0, +), 1, accuracy: 0.000001)
        }
        var mismatched = contract.responseSchema.expectedFinalState
        mismatched[NFEstimateExactContract.estimateKey] = "100"
        let falsePlausibility = NFExerciseScoringEngine.score(.logicState(.init(finalState: mismatched, violatedRuleID: nil)), for: item)
        XCTAssertEqual(falsePlausibility.credit, 1.0 / 3.0, accuracy: 0.000001)
        mismatched[NFEstimateExactContract.plausibilityKey] = "no"
        let honestPlausibility = NFExerciseScoringEngine.score(.logicState(.init(finalState: mismatched, violatedRuleID: nil)), for: item)
        XCTAssertEqual(honestPlausibility.credit, 2.0 / 3.0, accuracy: 0.000001)
        XCTAssertFalse(honestPlausibility.isCorrect)
        let state = NFLogicStateResponseSchema(initialState: ["count": "10", "ready": "false"], expectedFinalState: ["count": "9", "ready": "true"], acceptedEquivalentStates: [], ruleOptions: [option("readyRule", "Readiness equals count <= 7"), option("positive", "Count stays nonnegative")], expectedViolatedRuleID: "readyRule", fieldDomains: ["count": .exactNumber, "ready": .boolean])
        let stateItem = try exercise(.logicState(state))
        XCTAssertEqual(NFExerciseScoringEngine.score(.logicState(.init(finalState: ["count": "9.0", "ready": "True"], violatedRuleID: "readyRule")), for: stateItem).credit, 1)
        XCTAssertEqual(NFExerciseScoringEngine.score(.logicState(.init(finalState: ["count": "9", "ready": "true"], violatedRuleID: "positive")), for: stateItem).credit, 0.8, accuracy: 0.000001)
        for state in [["count": "nine", "ready": "true"], ["count": "9", "ready": "maybe"]] {
            let unsupported = NFExerciseScoringEngine.score(.logicState(.init(finalState: state, violatedRuleID: "readyRule")), for: stateItem)
            XCTAssertEqual(unsupported.outcome, .needsClarification)
            XCTAssertNil(unsupported.objectiveCorrectness)
        }
    }

    func testS07NumericEquivalenceSeparatesSyntaxFromWrongUnits() throws {
        let schema = NFNumericResponseSchema(answer: .init(value: 1.25, tolerance: .absolute(0), canonicalUnit: "m", acceptedUnits: [], unitRequired: false, displayPrecision: 2), placeholder: "Answer in metres", permitsScientificNotation: true, permitsThousandsSeparators: true)
        let item = try exercise(.numeric(schema))
        for value in ["1.25", "1.250", "5/4", "1.25e0"] {
            XCTAssertEqual(NFExerciseScoringEngine.score(.numeric(.init(value: value, unit: nil)), for: item).outcome, .correct)
        }
        for value in ["1/0", "NaN", "1,25"] {
            XCTAssertEqual(NFExerciseScoringEngine.score(.numeric(.init(value: value, unit: nil)), for: item).outcome, .needsClarification)
        }
        XCTAssertEqual(NFExerciseScoringEngine.score(.numeric(.init(value: "1.25 cm", unit: nil)), for: item).outcome, .incorrect)
        XCTAssertEqual(NFExerciseScoringEngine.score(.numeric(.init(value: "1.25", unit: "M")), for: item).outcome, .incorrect)
    }

    func testS08SelectingEverythingCannotExploitPartialCreditOrSupportBundles() throws {
        let choices = [option("a", "Safeguard A"), option("b", "Harm B"), option("c", "Safeguard C"), option("d", "Harm D")]
        let item = try exercise(.multipleChoice(.init(options: choices, correctOptionIDs: ["a", "c"], minimumSelections: 1, maximumSelections: 4)))
        for (ids, credit) in [(["a", "c"], 1.0), (["a"], 0.5), (["a", "b", "c"], 0.5), (["a", "b", "c", "d"], 0.0)] {
            XCTAssertEqual(NFExerciseScoringEngine.score(.multipleChoice(optionIDs: ids), for: item).credit, credit)
        }
        let exactItem = try exercise(.multipleChoice(.init(options: choices, correctOptionIDs: ["a", "c"], minimumSelections: 1, maximumSelections: 4)), partial: false)
        XCTAssertEqual(NFExerciseScoringEngine.score(.multipleChoice(optionIDs: ["a"]), for: exactItem).credit, 0)
        let support = NFClaimEvidenceResponseSchema(claims: [.init(id: "claim", text: "The observed mean differs")], evidence: [.init(id: "a", text: "Raw data", citationID: nil), .init(id: "b", text: "Computed contrast", citationID: nil), .init(id: "c", text: "Unsupported assertion", citationID: nil)], correctPairs: [.init(claimID: "claim", evidenceIDs: ["a"])], supportContracts: [.init(claimID: "claim", sufficientBundles: [["a"], ["b"]])])
        let supportItem = try exercise(.claimEvidence(support))
        for id in ["a", "b"] { XCTAssertEqual(NFExerciseScoringEngine.score(.claimEvidence(.init(pairs: [.init(claimID: "claim", evidenceIDs: [id])])), for: supportItem).outcome, .correct) }
        XCTAssertEqual(NFExerciseScoringEngine.score(.claimEvidence(.init(pairs: [.init(claimID: "claim", evidenceIDs: ["a", "b", "c"])])), for: supportItem).credit, 0)
    }

    func testS09DAGAcceptsEveryCompleteTopologicalOrderAndBlocksCycles() throws {
        let steps = [NFOrderedStep(id: "a", text: "Prepare A"), .init(id: "b", text: "Prepare B"), .init(id: "c", text: "Combine")]
        let dependencies = [NFOrderingDependency(before: "a", after: "c"), .init(before: "b", after: "c")]
        let schema = NFOrderedStepsResponseSchema(steps: steps, correctOrder: ["a", "b", "c"], dependencies: dependencies)
        let item = try exercise(.orderedSteps(schema))
        for order in [["a", "b", "c"], ["b", "a", "c"]] {
            XCTAssertEqual(NFExerciseScoringEngine.score(.orderedSteps(stepIDs: order), for: item).outcome, .correct)
        }
        XCTAssertNotEqual(NFExerciseScoringEngine.score(.orderedSteps(stepIDs: ["c", "a", "b"]), for: item).outcome, .correct)
        let cycle = NFOrderedStepsResponseSchema(steps: steps, correctOrder: ["a", "b", "c"], dependencies: dependencies + [.init(before: "c", after: "a")])
        XCTAssertThrowsError(try NFExerciseSchemaValidator.validateInteraction(.orderedSteps(cycle)))
        let noEdges = try exercise(.orderedSteps(.init(steps: steps, correctOrder: ["a", "b", "c"], dependencies: [])))
        XCTAssertEqual(NFExerciseScoringEngine.score(.orderedSteps(stepIDs: ["c", "b", "a"]), for: noEdges).outcome, .correct)
    }

    func testS10SelfReportsNeverBecomeVerifiedCorrectnessAndRoundTrip() throws {
        let item = try exercise(.selfCheck(.init(referenceAnswer: "Reference", criteria: ["Criterion"], asksForReflection: false)))
        for rating in NFSelfCheckRating.allCases {
            let result = NFExerciseScoringEngine.score(.selfCheck(.init(rating: rating, reflection: nil)), for: item)
            XCTAssertEqual(result.outcome, .selfReported)
            XCTAssertNil(result.objectiveCorrectness)
            XCTAssertEqual(result.credit, 0)
            XCTAssertEqual(try JSONDecoder().decode(NFExerciseScoringResult.self, from: JSONEncoder().encode(result)), result)
        }
    }

    func testS06KnownSolutionScaffoldsAreAbsentFromIndependentRoles() throws {
        for id in ["logic.counterexample", "logic.invalid-step", "science.next-experiment", "mental.compensation"] {
            let activity = try XCTUnwrap(NFDefaultContentCatalog.activities.first { $0.id == "nf.default." + id })
            for purpose in [NFExercisePurpose.practice, .baseline, .assessmentHoldout] {
                let item = try NFFallbackExerciseGenerator.generate(.init(seed: 20260904, index: 0, lab: activity.lab, purpose: purpose, preferredAssessmentMechanicID: activity.mechanicID))
                let text = (item.independentContextText ?? "") + String(data: try JSONEncoder().encode(item.independentRepresentations), encoding: .utf8)!
                XCTAssertFalse(text.contains("2 \\times 3 = 6"))
                XCTAssertFalse(text.contains("the proposed divisor is zero"))
                XCTAssertFalse(text.contains("The useful experiment changes A independently"))
                XCTAssertEqual(item.contractMetadata?.representationRoles.count, item.representations.count)
                XCTAssertNil(item.contractMetadata?.editorialDemand)
            }
        }
    }

    func testB08AdmissionSolvesSharedTargetsAndReportsExactMissingAssets() {
        let candidates = [candidate("a", families: ["recall", "equation"]), candidate("b", families: ["recall"])]
        let policy = NFContentAdmissionPolicy(quotasByFamilyID: ["recall": 1, "equation": 1])
        let report = NFContentAdmission.assign(candidates, policy: policy)
        XCTAssertTrue(report.isFeasible)
        XCTAssertEqual(report.assignments.first { $0.semanticProblemID == "a" }?.familyID, "equation")
        XCTAssertEqual(Set(report.assignments.map(\.semanticProblemID)).count, 2)
        XCTAssertEqual(report, NFContentAdmission.assign(candidates.reversed(), policy: policy))
        let deficient = NFContentAdmission.assign([candidate("a", families: ["recall", "equation"], missing: true), candidates[1]], policy: policy)
        XCTAssertFalse(deficient.isFeasible)
        XCTAssertEqual(deficient.rejectedByReason["missingAsset"], 1)
        XCTAssertEqual(deficient.deficits.first { $0.identifier == "equation" }?.assigned, 0)
        XCTAssertEqual(deficient.deficits.first { $0.identifier == "equation" }?.required, 1)
        for lab in TrainingLab.allCases {
            let editionPolicy = NFContentAdmission.proposedEditionPolicy(for: lab)
            // CON-014's retrieval rendering row sums to900 while the field
            // quotas/floor require1000. Preserve and expose the contradiction.
            XCTAssertEqual(editionPolicy.quotasByFamilyID.values.reduce(0, +), lab == .retrieval ? 900 : 1000)
            if lab == .retrieval {
                XCTAssertEqual(editionPolicy.quotasByFieldID.values.reduce(0, +), 1000)
                XCTAssertEqual(NFContentAdmission.assign([], policy: editionPolicy).deficits.first?.dimension, "policy")
            }
        }
    }

    func testB08VarietyAssignmentMatchesAnIndependentExhaustiveOracle() {
        // Six candidates can independently be excluded, assigned to A, or B.
        // Enumerate all 729 assignments, without using the production graph.
        for fixture in 0..<64 {
            let candidates = (0..<6).map { index in
                NFContentAdmissionCandidate(semanticProblemID: "item.\(index)", semanticFingerprint: "fp.\(index)",
                    fieldID: index % 2 == 0 ? "x" : "y", structureID: ((fixture >> index) & 1) == 0 ? "s1" : "s2",
                    compatibleFamilyIDs: index < 2 ? ["a"] : (index > 3 ? ["b"] : ["a", "b"]),
                    availableAssetIDs: [], requiredAssetIDs: [], supportedLocaleIDs: ["en", "ja"], valid: true)
            }
            let policy = NFContentAdmissionPolicy(quotasByFamilyID: ["a": 2, "b": 2], quotasByFieldID: ["x": 2, "y": 2],
                maximumPerFamilyStructure: ["a": 1, "b": 1], minimumStructuresPerFamily: ["a": 2, "b": 2])
            let feasible = (0..<729).contains { encoding in
                var digits = encoding
                var byFamily: [String: [NFContentAdmissionCandidate]] = [:]
                for candidate in candidates {
                    let choice = digits % 3; digits /= 3
                    if choice == 0 { continue }
                    let family = choice == 1 ? "a" : "b"
                    if !candidate.compatibleFamilyIDs.contains(family) { return false }
                    byFamily[family, default: []].append(candidate)
                }
                let assigned = byFamily.values.flatMap { $0 }
                return ["a", "b"].allSatisfy { family in
                    let items = byFamily[family] ?? []
                    return items.count == 2 && Set(items.map(\.structureID)).count == 2
                } && ["x", "y"].allSatisfy { field in assigned.filter { $0.fieldID == field }.count == 2 }
            }
            let actual = NFContentAdmission.assign(candidates, policy: policy)
            XCTAssertEqual(actual.isFeasible, feasible, "fixture \(fixture)")
            XCTAssertEqual(actual, NFContentAdmission.assign(candidates.reversed(), policy: policy))
        }
        // Variety must affect assignment even when repeated structures fit the
        // numerical ceiling; a post-hoc check alone would miss this solution.
        let varied = (0..<5).map { index in
            NFContentAdmissionCandidate(semanticProblemID: "item.\(index)", semanticFingerprint: "fp.\(index)", fieldID: "x",
                structureID: index < 4 ? "s1" : "s2", compatibleFamilyIDs: ["a"], availableAssetIDs: [], requiredAssetIDs: [], supportedLocaleIDs: ["en", "ja"], valid: true)
        }
        XCTAssertTrue(NFContentAdmission.assign(varied, policy: .init(quotasByFamilyID: ["a": 4], minimumStructuresPerFamily: ["a": 2])).isFeasible)
    }

    func testHistoricalCorrectionsAreReproducibleFindingsAndNeverRewriteOriginals() throws {
        let contract = NFEstimateExactContract(estimate: "10000", acceptedEstimateAlternatives: [], plausibility: "plausible", acceptedPlausibilityAlternatives: ["yes"], exact: "9504", acceptedExactAlternatives: [])
        let item = try exercise(.logicState(contract.responseSchema))
        var state = contract.responseSchema.expectedFinalState
        state[NFEstimateExactContract.plausibilityKey] = "yes"
        let response = NFExerciseResponse.logicState(.init(finalState: state, violatedRuleID: nil))
        let current = NFExerciseScoringEngine.score(response, for: item)
        let legacy = NFExerciseScoringResult(exerciseID: item.id, scoringVersion: 7, isCorrect: true,
            credit: 2.0 / 3.0, normalizedResponse: current.normalizedResponse, errorCode: nil,
            expectedAnswerSummary: current.expectedAnswerSummary, feedback: current.feedback)
        let findings = NFContentCorrectionPolicy.findings(exercise: item, response: response, result: legacy)
        XCTAssertEqual(findings.map(\.reason), [.acceptedEquivalentReceivedPartialCredit])
        XCTAssertEqual(findings.first?.correctedCredit, 1)
        XCTAssertEqual(legacy.credit, 2.0 / 3.0)
        XCTAssertEqual(legacy.scoringVersion, 7)
        XCTAssertEqual(findings, NFContentCorrectionPolicy.findings(exercise: item, response: response, result: legacy))
        let invalidItem = try exercise(.singleChoice(.init(options: [option("a", "(-10, 10)"), option("b", "(-10.0, 10.0)")], correctOptionID: "a")))
        let exclusions = NFContentCorrectionPolicy.findings(exercise: invalidItem, response: .singleChoice(optionID: "b"), result: legacy)
        XCTAssertEqual(exclusions.map(\.reason), [.duplicateSemanticAnswer])
        XCTAssertTrue(exclusions.allSatisfy(\.excludesVerifiedEvidence))
    }

    private func candidate(_ id: String, families: [String], missing: Bool = false) -> NFContentAdmissionCandidate {
        .init(semanticProblemID: id, semanticFingerprint: id, fieldID: "general", structureID: "structure.\(id)", compatibleFamilyIDs: families, availableAssetIDs: [], requiredAssetIDs: missing ? ["equation"] : [], supportedLocaleIDs: ["en", "ja"], valid: true)
    }
    private func option(_ id: String, _ text: String) -> NFChoiceOption {
        .init(id: id, text: text, accessibilityLabel: nil, distractorCode: nil)
    }
    private func exercise(_ interaction: NFExerciseInteraction, partial: Bool = true) throws -> NFExercise {
        let base = try NFFallbackExerciseGenerator.generate(.init(seed: 91, index: 0, lab: .mentalMath, purpose: .practice))
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(base)) as? [String: Any])
        object["interaction"] = try JSONSerialization.jsonObject(with: JSONEncoder().encode(interaction))
        object["rubric"] = ["criteria": [["id": "response", "description": "Correct response", "weight": 1]], "fullCreditThreshold": 1, "permitsPartialCredit": partial]
        return try JSONDecoder().decode(NFExercise.self, from: JSONSerialization.data(withJSONObject: object))
    }
}


/// Real bounded-file recovery, independent of generator correctness fixtures.
@MainActor
final class GranularHistorySnapshotRecoveryTests: XCTestCase {
    private let goodID = UUID(uuidString: "10000000-0000-0000-0000-000000000001")!
    private let badID = UUID(uuidString: "10000000-0000-0000-0000-000000000002")!
    private let extraID = UUID(uuidString: "10000000-0000-0000-0000-000000000003")!
    private let canary = "OPAQUE_PROTECTED_ANSWER_RECOVERY_CANARY"

    private func fixture() throws -> (NFExercise, Data) {
        let exercise = try NFFallbackExerciseGenerator.generate(.init(seed: 20260904, index: 0, lab: .mentalMath, purpose: .practice))
        var archive = NFLocalSessionRepository.Archive()
        archive.snapshots = [.init(attemptID: goodID, exercise: exercise), .init(attemptID: badID, exercise: exercise)]
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(archive)) as? [String: Any])
        var snapshots = object["snapshots"] as! [[String: Any]]
        var corrupted = snapshots[1]["exercise"] as! [String: Any]
        corrupted["interaction"] = ["futureUnknownResponse": ["hiddenAnswerKey": canary]]
        snapshots[1]["exercise"] = corrupted
        object["snapshots"] = snapshots
        let data = Data(" \n".utf8) + (try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])) + Data("\n ".utf8)
        return (exercise, data)
    }

    private func location() throws -> (URL, URL) {
        let folder = FileManager.default.temporaryDirectory.appending(path: "NFHistoryRecovery-\(UUID())")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return (folder, folder.appending(path: "sessions.json"))
    }

    func testOneMalformedHistorySnapshotRetainsValidContextAndOriginalPrivateBytes() throws {
        let (exercise, bytes) = try fixture()
        let (folder, url) = try location(); defer { try? FileManager.default.removeItem(at: folder) }
        try bytes.write(to: url)
        let repository = NFLocalSessionRepository(url: url)
        XCTAssertNil(repository.loadError)
        XCTAssertEqual(repository.archive.snapshots.map(\.attemptID), [goodID])
        XCTAssertEqual(repository.archive.snapshots.first?.exercise, exercise)
        XCTAssertEqual(repository.archive.unavailableHistorySnapshots?.map(\.attemptID), [badID])
        XCTAssertEqual(repository.archive.unavailableHistorySnapshots?.first?.reason, .malformed)
        XCTAssertEqual(repository.archive.unavailableHistorySnapshots?.first?.digest.count, 64)
        XCTAssertEqual(try Data(contentsOf: url), bytes, "Loading must not rewrite the source archive")
        let recovery = try XCTUnwrap(repository.historyRecoveryDirectoryURL)
        let backups = try FileManager.default.contentsOfDirectory(at: recovery, includingPropertiesForKeys: nil)
        XCTAssertEqual(backups.count, 1)
        XCTAssertEqual(try Data(contentsOf: XCTUnwrap(backups.first)), bytes)
        let container = try ModelContainer(for: Schema(NFSchemaV1.models), configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let store = AppStore(context: container.mainContext, localSessionRepository: repository, allowsSharedWidgetPublishing: false)
        XCTAssertEqual(store.exerciseSnapshot(for: goodID), exercise)
        XCTAssertNil(store.exerciseSnapshot(for: badID))
        XCTAssertNotNil(store.historySnapshotUnavailableReason(for: badID))
        XCTAssertNil(store.historySnapshotUnavailableReason(for: goodID))
        try repository.retainSnapshot(attemptID: extraID, exercise: exercise)
        XCTAssertNotEqual(try Data(contentsOf: url), bytes)
        XCTAssertEqual(try Data(contentsOf: XCTUnwrap(backups.first)), bytes, "A successful later write keeps original recovery bytes")
        let reopened = NFLocalSessionRepository(url: url, ownerDeviceID: repository.ownerDeviceID)
        XCTAssertNil(reopened.loadError)
        XCTAssertEqual(Set(reopened.archive.snapshots.map(\.attemptID)), [goodID, extraID])
        XCTAssertEqual(reopened.archive.unavailableHistorySnapshots?.first?.attemptID, badID)
        let exported = String(decoding: try JSONEncoder().encode(reopened.exportArchive), as: UTF8.self)
        XCTAssertFalse(exported.contains(canary))
        XCTAssertFalse(exported.contains(bytes.base64EncodedString()))
        XCTAssertEqual(reopened.exportArchive.unavailableHistorySnapshots?.first?.attemptID, badID)
        XCTAssertThrowsError(try reopened.retainSnapshot(attemptID: badID, exercise: exercise), "An unknown original snapshot cannot be silently replaced")
    }

    func testProtectedMalformedMarkerOverridesInconsistentHistoryAndPortableResults() throws {
        let (_, bytes) = try fixture()
        let (folder, url) = try location(); defer { try? FileManager.default.removeItem(at: folder) }
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: bytes) as? [String: Any])
        var snapshots = object["snapshots"] as! [[String: Any]]
        var hidden = snapshots[1]["exercise"] as! [String: Any]
        hidden["assessmentProtected"] = true
        snapshots[1]["exercise"] = hidden
        object["snapshots"] = snapshots
        let original = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        try original.write(to: url)
        let repository = NFLocalSessionRepository(url: url)
        XCTAssertNil(repository.loadError)
        XCTAssertEqual(repository.archive.unavailableHistorySnapshots?.first?.reason, .protectedContent,
                       "Raw protection is recognized even when the interaction cannot decode")
        let container = try ModelContainer(for: Schema(NFSchemaV1.models), configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let store = AppStore(context: container.mainContext, localSessionRepository: repository, allowsSharedWidgetPublishing: false)
        let response = String(decoding: try JSONEncoder().encode(NFExerciseResponse.numeric(.init(value: "1", unit: nil))), as: UTF8.self)
        let attempt = AttemptRecord(sessionID: UUID(), lab: .mentalMath, itemID: "synthetic.inconsistent.protection",
            prompt: "Synthetic saved question", response: response, correctAnswer: canary, isCorrect: true,
            confidence: .certain, evidenceClass: .practice, responseFormat: "numeric")
        attempt.id = badID
        attempt.scoringVersion = 8
        container.mainContext.insert(attempt)
        try container.mainContext.save()
        store.reload()
        let presented = store.historyPresentation(for: NFReadOnlyAttemptSnapshot(attempt: attempt))
        XCTAssertEqual(presented.source, .protectedAssessment)
        XCTAssertEqual(presented.effectiveResult, .all)
        XCTAssertTrue(presented.correctAnswer.isEmpty)
        XCTAssertFalse(presented.reviewExplanation(exercise: nil).contains(canary))
        XCTAssertEqual(attempt.correctAnswerText, canary, "Original receipt is immutable")
        let urls = try NFDataExportService.makeExports(from: store)
        defer { if let directory = urls.first?.deletingLastPathComponent() { try? FileManager.default.removeItem(at: directory) } }
        for export in urls {
            XCTAssertFalse(try String(contentsOf: export, encoding: .utf8).contains(canary), export.lastPathComponent)
        }
        let fullURL = try XCTUnwrap(urls.first { $0.lastPathComponent == "NeuroForge-Full-Archive.json" })
        let exported = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: fullURL)) as? [String: Any])
        let row = try XCTUnwrap((exported["attempts"] as? [[String: Any]])?.first)
        XCTAssertNotNil(row["protectedReceipt"])
        XCTAssertNil(row["isCorrect"])
        XCTAssertNil(row["deterministicCredit"])
        XCTAssertEqual(try Data(contentsOf: XCTUnwrap(FileManager.default.contentsOfDirectory(
            at: XCTUnwrap(repository.historyRecoveryDirectoryURL), includingPropertiesForKeys: nil).first)), original)
        var markerOnly = repository.exportArchive
        markerOnly.unavailableHistorySnapshots = nil
        markerOnly.snapshots = []
        XCTAssertTrue(markerOnly.withheldProtectedConflictAttemptIDs?.contains(badID) == true)
        let importedRepository = NFLocalSessionRepository()
        try importedRepository.importArchive(markerOnly)
        let importedStore = AppStore(context: container.mainContext, localSessionRepository: importedRepository, allowsSharedWidgetPublishing: false)
        let markerPresentation = importedStore.historyPresentation(for: NFReadOnlyAttemptSnapshot(attempt: attempt))
        XCTAssertEqual(markerPresentation.source, .protectedAssessment)
        XCTAssertEqual(markerPresentation.effectiveResult, .all)
        XCTAssertTrue(markerPresentation.correctAnswer.isEmpty)
        let markerExports = try NFDataExportService.makeExports(from: importedStore)
        defer { if let directory = markerExports.first?.deletingLastPathComponent() { try? FileManager.default.removeItem(at: directory) } }
        for export in markerExports { XCTAssertFalse(try String(contentsOf: export, encoding: .utf8).contains(canary)) }
    }

    func testFutureGlobalVersionDuplicateIdentityAndMalformedSessionStayFailClosed() throws {
        let (_, bytes) = try fixture()
        for variant in 0..<3 {
            let (folder, url) = try location(); defer { try? FileManager.default.removeItem(at: folder) }
            var object = try XCTUnwrap(JSONSerialization.jsonObject(with: bytes) as? [String: Any])
            if variant == 0 { object["schemaVersion"] = 999 }
            else if variant == 1 {
                var snapshots = object["snapshots"] as! [[String: Any]]
                snapshots[1]["attemptID"] = goodID.uuidString
                object["snapshots"] = snapshots
            } else { object["sessions"] = [["id": UUID().uuidString, "malformedCheckpoint": true]] }
            let original = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
            try original.write(to: url)
            let repository = NFLocalSessionRepository(url: url)
            XCTAssertNotNil(repository.loadError)
            XCTAssertTrue(repository.archive.snapshots.isEmpty)
            XCTAssertTrue(repository.archive.unavailableHistorySnapshots?.isEmpty ?? true)
            XCTAssertEqual(try Data(contentsOf: url), original)
            XCTAssertFalse(FileManager.default.fileExists(atPath: try XCTUnwrap(repository.historyRecoveryDirectoryURL).path))
        }
    }

    func testFailedRecoveryBackupPreservesSourceAndRefusesAllMutation() throws {
        let (exercise, bytes) = try fixture()
        let (folder, url) = try location(); defer { try? FileManager.default.removeItem(at: folder) }
        try bytes.write(to: url)
        let obstruction = url.appendingPathExtension("history-recovery")
        try Data("blocked backup directory".utf8).write(to: obstruction)
        let repository = NFLocalSessionRepository(url: url)
        XCTAssertNotNil(repository.loadError)
        XCTAssertEqual(repository.archive.snapshots.first?.attemptID, goodID, "Readable valid history survives even when backup creation fails")
        XCTAssertThrowsError(try repository.retainSnapshot(attemptID: extraID, exercise: exercise))
        XCTAssertEqual(repository.archive.snapshots.map(\.attemptID), [goodID])
        XCTAssertEqual(try Data(contentsOf: url), bytes)
        XCTAssertEqual(try Data(contentsOf: obstruction), Data("blocked backup directory".utf8))
    }

    func testOversizedArchiveIsRejectedBeforeGranularDecodingOrBackup() throws {
        let (folder, url) = try location(); defer { try? FileManager.default.removeItem(at: folder) }
        XCTAssertTrue(FileManager.default.createFile(atPath: url.path, contents: Data()))
        let file = try FileHandle(forWritingTo: url)
        try file.truncate(atOffset: UInt64(NFLocalSessionRepository.maximumBytes + 1))
        try file.close()
        let repository = NFLocalSessionRepository(url: url)
        XCTAssertNotNil(repository.loadError)
        XCTAssertTrue(repository.archive.snapshots.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: try XCTUnwrap(repository.historyRecoveryDirectoryURL).path))
    }

    func testLinkedHistoryDeletionPurgesUnclassifiableRecoveryBackups() throws {
        let (_, bytes) = try fixture()
        let (folder, url) = try location(); defer { try? FileManager.default.removeItem(at: folder) }
        try bytes.write(to: url)
        let repository = NFLocalSessionRepository(url: url)
        let recovery = try XCTUnwrap(repository.historyRecoveryDirectoryURL)
        XCTAssertTrue(FileManager.default.fileExists(atPath: recovery.path))
        try repository.removeReferences(attemptIDs: [goodID])
        XCTAssertFalse(FileManager.default.fileExists(atPath: recovery.path))
        XCTAssertFalse(repository.archive.snapshots.contains { $0.attemptID == goodID })
        XCTAssertFalse(String(decoding: try JSONEncoder().encode(repository.exportArchive), as: UTF8.self).contains(canary))
    }
}


@MainActor
final class DataPredictionWorkflowTests: XCTestCase {
    private func exercise(seed: UInt64 = 721, purpose: NFExercisePurpose = .practice, locale: String = "en_US") throws -> NFExercise {
        try NFFallbackExerciseGenerator.generate(.init(seed: seed, index: 0, lab: .quantitative,
            purpose: purpose, localeIdentifier: locale, preferredAssessmentMechanicID: "fixture.fallback-variant-0"))
    }
    private func store(_ repository: NFLocalSessionRepository? = nil) throws -> (AppStore, ModelContainer) {
        let container = try ModelContainer(for: Schema(NFSchemaV1.models), configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        var draft = OnboardingDraft(); draft.aiMode = .disabled
        container.mainContext.insert(UserProfileRecord(draft: draft)); try container.mainContext.save()
        return (AppStore(context: container.mainContext, localSessionRepository: repository ?? NFLocalSessionRepository(),
            allowsSharedWidgetPublishing: false), container)
    }
    private func runtime(_ exercise: NFExercise, store: AppStore, legacy: Bool = false) throws -> NFUniversalSessionRuntime {
        var request = SessionRequest(lab: .quantitative, source: .focused, seed: exercise.seed,
            localeIdentifier: exercise.localeIdentifier, evidenceClass: exercise.evidenceClass,
            requestedItemCount: 1, isTimed: false, timingCondition: .init(.untimed),
            mechanicID: NFDefaultContentCatalog.activity(id: exercise.contractMetadata?.familyID ?? "")?.mechanicID)
        var checkpoint = try NFLocalItemCheckpoint.initial(request: request, exercise: exercise,
            slotID: UUID(), attemptID: UUID(), at: Date().addingTimeInterval(-1))
        if legacy { checkpoint.dataInspection = nil }
        request.localCheckpoint = checkpoint; request.freshlyAcceptedLaunch = true
        let value = NFUniversalSessionRuntime(request: request)
        XCTAssertTrue(value.checkpointDraft(store: store)); value.resume(); value.acknowledgePresented()
        XCTAssertNil(value.unavailableReason); return value
    }
    private func answer(_ runtime: NFUniversalSessionRuntime) throws {
        guard case .numeric(let schema) = runtime.exercise.interaction else { throw CocoaError(.coderInvalidValue) }
        runtime.numericValue = schema.answer.authoritativeValue.canonicalString
        runtime.numericUnit = "%"
    }
    private func blocked(_ folder: URL, _ action: () throws -> Void) throws {
        let backup = folder.appendingPathExtension("preserved")
        try FileManager.default.moveItem(at: folder, to: backup)
        try Data("Synthetic unavailable destination directory".utf8).write(to: folder)
        defer { try? FileManager.default.removeItem(at: folder); try? FileManager.default.moveItem(at: backup, to: folder) }
        try action()
    }
    private func mutated(_ exercise: NFExercise, _ values: [String: Any]) throws -> NFExercise {
        var raw = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(exercise)) as? [String: Any])
        raw.merge(values) { _, changed in changed }
        return try JSONDecoder().decode(NFExercise.self, from: JSONSerialization.data(withJSONObject: raw))
    }

    func testDenominatorExplanationUsesOnlyExactTypedCountsAndKeepsPercentAuthority() throws {
        for locale in ["en_US", "ja_JP"] {
            for seed in 0..<24 {
                let exercise = try self.exercise(seed: UInt64(seed), locale: locale)
                let original = try NFImmutableAttemptRecordSnapshot.encoded(exercise)
                let explanation = try XCTUnwrap(NFObservedProportionExplanation.make(exercise: exercise))
                let rows = explanation.data.points
                XCTAssertEqual(explanation.totalCount, rows[0].count + rows[1].count)
                guard case .numeric(let schema) = exercise.interaction else { return XCTFail("Expected percentage authority") }
                XCTAssertEqual(schema.answer.value, 100 * Double(rows[0].count) / Double(rows[0].count + rows[1].count), accuracy: 0.000_001)
                XCTAssertEqual(schema.answer.canonicalUnit, "%")
                XCTAssertEqual(explanation.data.verticalRange.lowerBound, 0)
                var pointer = try XCTUnwrap(NFDataInspectionDraft.initial(for: exercise))
                let keyboard = try XCTUnwrap(pointer.selecting(pointID: rows[1].id, exercise: exercise))
                pointer = try XCTUnwrap(pointer.selecting(pointID: try XCTUnwrap(explanation.data.inspect(label: rows[1].label)).id, exercise: exercise))
                XCTAssertEqual(try NFImmutableAttemptRecordSnapshot.encoded(pointer), try NFImmutableAttemptRecordSnapshot.encoded(keyboard))
                XCTAssertEqual(try NFImmutableAttemptRecordSnapshot.encoded(exercise), original)
            }
        }
        let original = try self.exercise()
        let wrong = NFExerciseInteraction.numeric(.init(answer: .init(value: 99, tolerance: .absolute(0),
            canonicalUnit: "%", acceptedUnits: [], unitRequired: true, displayPrecision: 1), placeholder: "Percentage",
            permitsScientificNotation: true, permitsThousandsSeparators: true))
        XCTAssertNil(NFObservedProportionExplanation.make(exercise: try mutated(original,
            ["interaction": JSONSerialization.jsonObject(with: JSONEncoder().encode(wrong))])))
        XCTAssertNil(NFObservedProportionExplanation.make(exercise: try mutated(original, ["assessmentProtected": true])))
        XCTAssertNil(NFObservedProportionExplanation.make(exercise: try mutated(original, ["generatorVersion": 999])))
    }

    func testFirstPredictionPrecedesAssistanceAndRemainsDistinctFromTheScoredFinalAnswer() throws {
        let (store, container) = try self.store(); defer { _ = container }
        let exercise = try self.exercise(), runtime = try self.runtime(exercise, store: store)
        XCTAssertFalse(runtime.revealDataExplanation(store: store))
        XCTAssertFalse(runtime.dataInspection?.overlayRevealed ?? true)
        runtime.setDataPrediction("150") // A wrong numerical prediction remains a valid learning observation.
        XCTAssertTrue(runtime.revealDataExplanation(store: store))
        XCTAssertEqual(runtime.stage, .item); XCTAssertTrue(store.attempts.isEmpty); XCTAssertNil(runtime.lastResult)
        XCTAssertEqual(runtime.dataInspection?.firstPrediction, .init(value: "150", unit: "%"))
        XCTAssertEqual(runtime.hintCount, 0); XCTAssertEqual(runtime.capturedSupportCount, 1)
        let saved = try XCTUnwrap(store.localSessions.archive.sessions.first?.checkpoint)
        XCTAssertEqual(saved.dataInspection?.firstPrediction?.value, "150")
        XCTAssertEqual(saved.hintCount, 0); XCTAssertEqual(saved.capturedSupportCount, 1)
        runtime.setDataPrediction("25")
        XCTAssertEqual(runtime.dataInspection?.predictionText, "150", "First prediction cannot be overwritten after explanation")
        runtime.toggleDataExplanation(store: store)
        XCTAssertFalse(runtime.dataInspection?.overlayExpanded ?? true)
        XCTAssertTrue(runtime.dataInspection?.overlayRevealed == true); XCTAssertEqual(runtime.capturedSupportCount, 1)
        runtime.requestHint(store: store)
        XCTAssertEqual(runtime.hintCount, 1); XCTAssertEqual(runtime.visibleHints.count, 1)
        XCTAssertEqual(runtime.capturedSupportCount, 2, "The overlay must not consume an actual hint-ladder rung")
        try answer(runtime); runtime.submitInline(store: store)
        XCTAssertEqual(runtime.stage, .feedback); XCTAssertEqual(runtime.lastResult?.credit, 1)
        let attempt = try XCTUnwrap(store.attempts.first)
        XCTAssertEqual(attempt.hintCount, 2); XCTAssertEqual(attempt.deterministicCredit, 1)
        let snapshot = try XCTUnwrap(store.localSessions.archive.snapshots.first { $0.attemptID == attempt.id })
        XCTAssertEqual(snapshot.dataInspection?.firstPrediction?.value, "150")
        XCTAssertEqual(snapshot.editorialCapture?.hintCount, 2, "New immutable condition capture must remain wired for supported practice")
        let history = try XCTUnwrap(NFDataInspectionHistoryProjection.make(exercise: snapshot.exercise,
            draft: snapshot.dataInspection, isProtected: false))
        XCTAssertEqual(history.draft.firstPrediction?.value, "150")
        XCTAssertEqual(NFHistoryContextProjection.make(exercise: snapshot.exercise,
            hintCount: attempt.hintCount - history.draft.supportCount, isProtected: false).usedHints, runtime.visibleHints)
        XCTAssertNil(NFDataInspectionHistoryProjection.make(exercise: snapshot.exercise, draft: snapshot.dataInspection, isProtected: true))
        XCTAssertEqual(runtime.prepareToClose(store: store), .saved)
        runtime.releaseWriter()

        // Skipping preserves the prediction/support receipt without creating objective credit.
        let skipped = try self.runtime(self.exercise(seed: 723), store: store)
        skipped.setDataPrediction("19"); XCTAssertTrue(skipped.revealDataExplanation(store: store))
        skipped.skip(store: store)
        let skippedAttempt = try XCTUnwrap(store.attempts.first { $0.wasSkipped })
        XCTAssertEqual(skipped.stage, .summary); XCTAssertEqual(skippedAttempt.deterministicCredit, 0)
        XCTAssertEqual(skippedAttempt.hintCount, 1)
        XCTAssertEqual(store.localSessions.archive.snapshots.first { $0.attemptID == skippedAttempt.id }?.dataInspection?.firstPrediction?.value, "19")
        XCTAssertEqual(store.attempts.count, 2)
        skipped.releaseWriter()
    }

    func testFailedRevealAndPointSelectionRetainPredecessorThenColdResumeRestoresOriginalPrediction() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "NFDataPrediction-\(UUID())")
        defer { try? FileManager.default.removeItem(at: folder) }
        let owner = UUID(), url = folder.appending(path: "local.json")
        let repository = NFLocalSessionRepository(url: url, ownerDeviceID: owner)
        let (store, container) = try self.store(repository); defer { _ = container }
        let runtime = try self.runtime(self.exercise(), store: store)
        runtime.setDataPrediction("41.2"); XCTAssertTrue(runtime.checkpointDraft(store: store))
        let bytes = try Data(contentsOf: url)
        try blocked(folder) {
            XCTAssertFalse(runtime.revealDataExplanation(store: store))
            XCTAssertNil(runtime.dataInspection?.firstPrediction)
            XCTAssertFalse(runtime.dataInspection?.overlayExpanded ?? true)
            XCTAssertEqual(runtime.capturedSupportCount, 0)
            runtime.selectDataPoint(1, store: store)
            XCTAssertEqual(runtime.dataInspection?.selectedPointID, 0)
            XCTAssertTrue(store.attempts.isEmpty)
        }
        XCTAssertEqual(try Data(contentsOf: url), bytes)
        XCTAssertTrue(runtime.revealDataExplanation(store: store))
        runtime.selectDataPoint(1, store: store); runtime.toggleDataExplanation(store: store)
        XCTAssertEqual(runtime.prepareToClose(store: store), .saved)
        let run = try XCTUnwrap(repository.archive.sessions.first); runtime.releaseWriter()
        let reopened = NFLocalSessionRepository(url: url, ownerDeviceID: owner)
        let (coldStore, coldContainer) = try self.store(reopened); defer { _ = coldContainer }
        var request = run.request; request.localCheckpoint = run.checkpoint; request.localSessionID = run.id; request.freshlyAcceptedLaunch = false
        let cold = NFUniversalSessionRuntime(request: request)
        XCTAssertTrue(cold.checkpointDraft(store: coldStore)); cold.resume(); cold.acknowledgePresented()
        XCTAssertEqual(cold.dataInspection?.firstPrediction?.value, "41.2")
        XCTAssertEqual(cold.dataInspection?.selectedPointID, 1)
        XCTAssertFalse(cold.dataInspection?.overlayExpanded ?? true); XCTAssertEqual(cold.capturedSupportCount, 1)
        XCTAssertTrue(cold.recoveryText.contains("41.2")); XCTAssertTrue(coldStore.attempts.isEmpty)
        cold.toggleDataExplanation(store: coldStore); XCTAssertTrue(cold.dataInspection?.overlayExpanded == true)
        XCTAssertEqual(cold.capturedSupportCount, 1, "Reopening one saved explanation is not another support event")
        cold.releaseWriter()
    }

    func testSavedDataPredictionAndHelpRemainRetainedAfterLegacySummaryFailure() throws {
        enum Fault: Error { case legacySummary }
        let folder = FileManager.default.temporaryDirectory.appending(path: "NFDataMirror-\(UUID())")
        defer { try? FileManager.default.removeItem(at: folder) }
        let owner = UUID(), url = folder.appending(path: "local.json")
        let repository = NFLocalSessionRepository(url: url, ownerDeviceID: owner)
        let (store, container) = try self.store(repository); defer { _ = container }
        let runtime = try self.runtime(self.exercise(), store: store)
        runtime.setDataPrediction("41.2")
        runtime.legacyCheckpointWriteFailure = { throw Fault.legacySummary }
        XCTAssertFalse(runtime.revealDataExplanation(store: store))
        XCTAssertEqual(runtime.dataInspection?.firstPrediction?.value, "41.2")
        XCTAssertTrue(runtime.dataInspection?.overlayRevealed == true)
        XCTAssertEqual(runtime.capturedSupportCount, 1)
        XCTAssertNotNil(runtime.saveError)
        let cold = NFLocalSessionRepository(url: url, ownerDeviceID: owner)
        XCTAssertEqual(cold.archive.sessions.first?.checkpoint.dataInspection, runtime.dataInspection)
        runtime.setDataPrediction("99")
        XCTAssertEqual(runtime.dataInspection?.firstPrediction?.value, "41.2")
        runtime.legacyCheckpointWriteFailure = nil
        XCTAssertTrue(runtime.checkpointDraft(store: store))
        XCTAssertNil(runtime.saveError)
        XCTAssertEqual(repository.archive.sessions.first?.checkpoint.dataInspection, cold.archive.sessions.first?.checkpoint.dataInspection)
        XCTAssertTrue(store.attempts.isEmpty)
        runtime.releaseWriter()
    }

    func testUnknownAndIncoherentDataDraftsStayUnavailableWithoutInventingLegacyPredictions() throws {
        let exercise = try self.exercise()
        let (store, container) = try self.store(); defer { _ = container }
        let legacy = try self.runtime(exercise, store: store, legacy: true)
        XCTAssertNil(legacy.dataInspection); XCTAssertFalse(legacy.revealDataExplanation(store: store))
        try answer(legacy); legacy.submitInline(store: store)
        XCTAssertEqual(legacy.lastResult?.credit, 1); XCTAssertNil(store.localSessions.archive.snapshots.first?.dataInspection)
        legacy.releaseWriter()
        var request = SessionRequest(lab: .quantitative, source: .focused, seed: 721,
            localeIdentifier: "en", requestedItemCount: 1, isTimed: false)
        var checkpoint = try NFLocalItemCheckpoint.initial(request: request, exercise: exercise,
            slotID: UUID(), attemptID: UUID(), at: Date().addingTimeInterval(-1))
        checkpoint.dataInspection?.schemaVersion = 999
        request.localCheckpoint = checkpoint
        let unknown = NFUniversalSessionRuntime(request: request)
        XCTAssertFalse(checkpoint.hasSupportedDataInspection); XCTAssertNotNil(unknown.unavailableReason)
        XCTAssertFalse(unknown.revealDataExplanation(store: store))
        XCTAssertEqual(request.localCheckpoint?.dataInspection?.schemaVersion, 999)
        var draft = try XCTUnwrap(NFDataInspectionDraft.initial(for: exercise))
        draft.overlayExpanded = true
        XCTAssertFalse(draft.isSupported, "Overlay cannot open before a saved prediction")
        draft = try XCTUnwrap(NFDataInspectionDraft.initial(for: exercise)); draft.predictionText = String(repeating: "1", count: 501)
        XCTAssertFalse(draft.isSupported)
        draft = try XCTUnwrap(NFDataInspectionDraft.initial(for: exercise)); draft.predictionText = "NaN"
        XCTAssertNil(draft.revealing(exercise: exercise, activeSeconds: 1))
        draft.predictionText = "-5/2"
        XCTAssertNotNil(draft.revealing(exercise: exercise, activeSeconds: 1))
        XCTAssertNil(draft.revealing(exercise: exercise, activeSeconds: .infinity))
        XCTAssertNil(draft.selecting(pointID: 44, exercise: exercise))
    }

    private func generated() throws -> (NFAuthoringRequest, NFAuthoringResult) {
        let id = UUID()
        let request = NFAuthoringRequest(id: id, capability: .contextualize, lab: .quantitative,
            field: .general, customTopic: "Observed proportions", learningObjective: "Distinguish part and whole",
            style: .numerical, difficulty: 0.3, count: 2, localeIdentifier: "en", seed: 721, aiMode: .disabled)
        let questions = try [721, 722].map { seed -> NFAuthoredQuestion in
            let exercise = try self.exercise(seed: UInt64(seed), purpose: .documentPractice)
            guard case let .numeric(schema) = exercise.interaction else { throw CocoaError(.coderInvalidValue) }
            let question = NFAuthoredQuestion(id: exercise.id, lab: exercise.lab, style: .numerical,
                prompt: exercise.prompt, context: exercise.contextText ?? "", choices: [],
                correctAnswer: schema.answer.authoritativeValue.canonicalString, acceptedAnswers: [],
                explanation: exercise.feedback.correctExplanation, hint: exercise.feedback.hintLadder.first ?? "Compare the counts.",
                decisiveStep: exercise.feedback.decisiveStep, difficulty: 0.3, citationChunkIDs: [],
                evidenceClass: .documentPractice, authoritativeExercise: exercise)
            XCTAssertTrue(NFAuthoredExerciseAuthority.validatesBinding(question))
            return question
        }
        let result = NFAuthoringResult(questions: questions, provenance: .init(requestID: id,
            generatedAt: Date().addingTimeInterval(-1), route: .deterministicFallback, routeReason: "Synthetic exact table fixture",
            promptVersion: 1, modelIdentifier: "synthetic.data", sourceChunkIDs: [], sourceDocumentIDs: [], validationVersion: 1,
            repairCount: 0, cacheKey: "synthetic.data", isFallback: true), routeCandidates: [],
            validationStatus: .init(level: .deterministicKey, sourceSupport: .notApplicable), validationNotes: [])
        return (request, result)
    }

    func testGeneratedDataAdapterPreservesFirstPredictionSupportAndFreshNextState() throws {
        let (store, container) = try self.store(); defer { _ = container }
        let (request, result) = try generated()
        let runtime = AIGeneratedPracticeRuntime(result: result, request: request)
        XCTAssertTrue(runtime.checkpoint(store: store)); runtime.resume()
        XCTAssertFalse(runtime.revealDataExplanation(store: store))
        runtime.setDataPrediction("31.5"); XCTAssertTrue(runtime.revealDataExplanation(store: store))
        runtime.selectDataPoint(1, store: store)
        let draft = try XCTUnwrap(store.generatedPracticeDraft(for: request.id)); XCTAssertTrue(draft.valid)
        XCTAssertEqual(draft.dataInspection?.firstPrediction?.value, "31.5")
        runtime.releaseWriter()
        let cold = AIGeneratedPracticeRuntime(result: result, request: request, draft: draft)
        XCTAssertTrue(cold.restoreCheckpoint(store: store)); cold.resume()
        XCTAssertEqual(cold.dataInspection?.selectedPointID, 1)
        guard case let .numeric(schema) = cold.exercise.interaction else { return XCTFail("Expected exact percentage") }
        cold.numericValue = schema.answer.authoritativeValue.canonicalString; cold.numericUnit = "%"
        cold.submit(store: store)
        XCTAssertEqual(cold.stage, 2); XCTAssertEqual(cold.lastScore?.credit, 1)
        let attempt = try XCTUnwrap(store.attempts.first)
        XCTAssertEqual(attempt.hintCount, 1)
        XCTAssertEqual(store.localSessions.archive.snapshots.first?.dataInspection?.firstPrediction?.value, "31.5")
        cold.next(store: store)
        XCTAssertEqual(cold.index, 1); XCTAssertEqual(cold.stage, 0)
        XCTAssertEqual(cold.dataInspection?.selectedPointID, 0)
        XCTAssertNil(cold.dataInspection?.firstPrediction); XCTAssertEqual(cold.capturedSupportCount, 0)
        XCTAssertEqual(store.localSessions.archive.snapshots.first?.dataInspection?.firstPrediction?.value, "31.5")
        cold.releaseWriter()
        var future = draft; future.dataInspection?.schemaVersion = 999
        XCTAssertFalse(future.valid)
    }

    func testProtectedPortableMarkerRemovesDataSidecarsWithoutChangingOriginalLearningRecord() throws {
        let (store, container) = try self.store(); defer { _ = container }
        let exercise = try self.exercise(), runtime = try self.runtime(exercise, store: store)
        let canary = "9876.54321"
        runtime.setDataPrediction(canary); XCTAssertTrue(runtime.revealDataExplanation(store: store))
        try answer(runtime); runtime.submitInline(store: store)
        let attempt = try XCTUnwrap(store.attempts.first)
        let original = try NFImmutableAttemptRecordSnapshot.encoded(store.localSessions.archive)
        let files = try NFDataExportService.makeExports(from: store)
        defer { try? FileManager.default.removeItem(at: files[0].deletingLastPathComponent()) }
        let bytes = try Data(contentsOf: files[0]); XCTAssertTrue(String(decoding: bytes, as: UTF8.self).contains(canary))
        var root = try XCTUnwrap(JSONSerialization.jsonObject(with: bytes) as? [String: Any])
        var local = try XCTUnwrap(root["localLearning"] as? [String: Any])
        local["withheldProtectedConflictAttemptIDs"] = [attempt.id.uuidString]
        root["localLearning"] = local
        let sanitized = try NFDataExportService.protectedPortableData(JSONSerialization.data(withJSONObject: root))
        XCTAssertFalse(String(decoding: sanitized, as: UTF8.self).contains(canary))
        XCTAssertFalse(String(decoding: sanitized, as: UTF8.self).contains("dataInspection"))
        XCTAssertEqual(try NFImmutableAttemptRecordSnapshot.encoded(store.localSessions.archive), original)
        XCTAssertEqual(store.localSessions.archive.snapshots.first?.dataInspection?.firstPrediction?.value, canary)
        runtime.releaseWriter()
    }
}


@MainActor
final class LinkedScienceStudyTests: XCTestCase {
    private func exercise(seed: UInt64 = 445, locale: String = "en", purpose: NFExercisePurpose = .practice,
                          policy: Int? = 1, excludedContext: String? = nil) throws -> NFExercise {
        try NFFallbackExerciseGenerator.generate(.init(seed: seed, index: 0, lab: .scientificReasoning,
            purpose: purpose, localeIdentifier: locale, preferredAssessmentMechanicID: "fixture.fallback-variant-0",
            scienceStudyPolicyVersion: policy, scienceStudyExcludedContextID: excludedContext))
    }
    private func store(_ repository: NFLocalSessionRepository? = nil) throws -> (AppStore, ModelContainer) {
        let container = try ModelContainer(for: Schema(NFSchemaV1.models), configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        var draft = OnboardingDraft(); draft.aiMode = .disabled
        container.mainContext.insert(UserProfileRecord(draft: draft)); try container.mainContext.save()
        return (AppStore(context: container.mainContext, localSessionRepository: repository ?? NFLocalSessionRepository(),
            allowsSharedWidgetPublishing: false), container)
    }
    private func runtime(_ exercise: NFExercise, store: AppStore) throws -> NFUniversalSessionRuntime {
        var request = SessionRequest(lab: .scientificReasoning, source: .focused, seed: exercise.seed,
            localeIdentifier: exercise.localeIdentifier, evidenceClass: exercise.evidenceClass,
            requestedItemCount: 1, isTimed: false, timingCondition: .init(.untimed),
            mechanicID: NFDefaultContentCatalog.activity(id: exercise.contractMetadata?.familyID ?? "")?.mechanicID)
        request.scienceStudyPolicyVersion = exercise.contractMetadata?.scienceStudy?.policyVersion
        request.localCheckpoint = try .initial(request: request, exercise: exercise, slotID: UUID(), attemptID: UUID(), at: Date().addingTimeInterval(-1))
        request.freshlyAcceptedLaunch = true
        let runtime = NFUniversalSessionRuntime(request: request)
        XCTAssertTrue(runtime.checkpointDraft(store: store)); runtime.resume(); runtime.acknowledgePresented()
        XCTAssertNil(runtime.unavailableReason); return runtime
    }
    private func firstAnswer(_ study: NFScienceStudyContract) -> [String: Set<String>] {
        [study.evidenceClaims[0].id: [study.observations[0].id],
         study.evidenceClaims[1].id: [study.observations[1].id, study.observations[2].id]]
    }
    private func fullAnswer(_ study: NFScienceStudyContract, experimentID: String? = nil) -> NFExerciseResponse {
        var selected = firstAnswer(study)
        selected[study.experimentClaim.id] = [experimentID ?? study.experiments.first { $0.randomizesWithinBaseline && $0.commonCalibratedMeasurement }!.id]
        return .claimEvidence(.init(pairs: selected.keys.sorted().map { .init(claimID: $0, evidenceIDs: selected[$0, default: []].sorted()) }))
    }
    private func obstruct(_ folder: URL, perform body: () throws -> Void) throws {
        let backup = folder.appendingPathExtension("preserved")
        try FileManager.default.moveItem(at: folder, to: backup)
        try Data("Synthetic unavailable destination directory".utf8).write(to: folder)
        defer { try? FileManager.default.removeItem(at: folder); try? FileManager.default.moveItem(at: backup, to: folder) }
        try body()
    }

    func testLinkedStudyKeepsExactDataScopeControlsAndLegacyProducerBytes() throws {
        var higher = false, lower = false, contexts: Set<String> = []
        for locale in ["en", "ja"] {
            for seed in 0..<20 {
                let value = try exercise(seed: UInt64(seed), locale: locale)
                let study = try XCTUnwrap(NFScienceStudyContract.make(exercise: value))
                contexts.insert(study.contextID)
                higher = higher || study.groups[0].mean > study.groups[1].mean
                lower = lower || study.groups[0].mean < study.groups[1].mean
                XCTAssertEqual(value.schemaVersion, 3); XCTAssertEqual(value.generatorVersion, 6)
                XCTAssertEqual(value.independentRepresentations, [study.table])
                XCTAssertFalse(value.provenance.isSourceGrounded); XCTAssertTrue(value.citations.isEmpty)
                XCTAssertNil(value.contractMetadata?.editorialDemand)
                XCTAssertEqual(study.experiments.filter { $0.randomizesWithinBaseline }.count, 2)
                XCTAssertEqual(study.experiments.filter { $0.commonCalibratedMeasurement }.count, 2)
                XCTAssertEqual(study.experiments.filter { $0.randomizesWithinBaseline && $0.commonCalibratedMeasurement }.count, 1)
                let response = fullAnswer(study)
                XCTAssertEqual(NFExerciseScoringEngine.score(response, for: value).credit, 1)
                for wrong in study.experiments.filter({ !$0.randomizesWithinBaseline || !$0.commonCalibratedMeasurement }) {
                    XCTAssertEqual(NFExerciseScoringEngine.score(fullAnswer(study, experimentID: wrong.id), for: value).credit, 2.0 / 3, accuracy: 0.000_001)
                }
                let legacy = try exercise(seed: UInt64(seed), locale: locale, policy: nil)
                let explicitLegacy = try NFFallbackExerciseGenerator.generate(.init(seed: UInt64(seed), index: 0, lab: .scientificReasoning,
                    purpose: .practice, localeIdentifier: locale, preferredAssessmentMechanicID: "fixture.fallback-variant-0"))
                XCTAssertEqual(try NFImmutableAttemptRecordSnapshot.encoded(legacy), try NFImmutableAttemptRecordSnapshot.encoded(explicitLegacy))
                XCTAssertEqual(legacy.schemaVersion, 2); XCTAssertEqual(legacy.generatorVersion, 4)
                XCTAssertNotEqual(value.id, legacy.id, "Different opted-in recipes must not share a question identity")
                XCTAssertEqual(value.templateID, legacy.templateID, "Catalog family routing stays stable")
                XCTAssertNil(legacy.contractMetadata?.scienceStudy)
                XCTAssertFalse(String(decoding: try JSONEncoder().encode(legacy), as: UTF8.self).contains("scienceStudy"))
            }
        }
        XCTAssertTrue(higher); XCTAssertTrue(lower); XCTAssertEqual(contexts.count, 3)
        XCTAssertThrowsError(try exercise(purpose: .baseline))
        XCTAssertThrowsError(try exercise(policy: 999))
        XCTAssertThrowsError(try exercise(excludedContext: "unknown context"))
    }

    func testScopedCompletenessRejectsMissingAndCrossStageEvidenceWithoutAKeyOracle() throws {
        let value = try exercise(), study = try XCTUnwrap(NFScienceStudyContract.make(exercise: value))
        let initial = NFExerciseResponse.initialDraft(for: value)
        XCTAssertFalse(NFExerciseResponseValidator.validate(initial, for: value.interaction).isValid)
        XCTAssertEqual(NFExerciseScoringEngine.score(initial, for: value).outcome, .needsClarification)
        guard case var .claimEvidence(schema) = value.interaction else { return XCTFail("Expected scoped claims") }
        var first = try XCTUnwrap(NFScienceStudyDraft.initial(for: value))
        let wrongButComplete = NFExerciseResponse.claimEvidence(.init(pairs: [
            .init(claimID: study.evidenceClaims[0].id, evidenceIDs: [study.observations[1].id]),
            .init(claimID: study.evidenceClaims[1].id, evidenceIDs: [study.observations[0].id])]))
        XCTAssertTrue(first.evidenceValidation(wrongButComplete, exercise: value).isValid)
        first = try XCTUnwrap(first.locking(response: wrongButComplete, exercise: value, activeSeconds: 2))
        XCTAssertEqual(first.firstEvidence?.pairs.count, 2, "Intermediate save checks structure, never correctness")
        let crossed = NFExerciseResponse.claimEvidence(.init(pairs: [
            .init(claimID: study.evidenceClaims[0].id, evidenceIDs: [study.experiments[0].id]),
            .init(claimID: study.evidenceClaims[1].id, evidenceIDs: [study.observations[0].id]),
            .init(claimID: study.experimentClaim.id, evidenceIDs: [study.experiments[1].id])]))
        XCTAssertFalse(NFExerciseResponseValidator.validate(crossed, for: value.interaction).isValid)
        schema.selectionScopes?[0].schemaVersion = 999
        XCTAssertThrowsError(try NFExerciseSchemaValidator.validateInteraction(.claimEvidence(schema)))
        XCTAssertFalse(NFExerciseResponseValidator.validate(fullAnswer(study), for: .claimEvidence(schema)).isValid)
    }

    func testActualRuntimeSavesFirstStageThenCommitsOneExactLinkedAnswerAndRejectsLateEdits() throws {
        let (store, container) = try self.store(); defer { _ = container }
        let value = try exercise(), study = try XCTUnwrap(NFScienceStudyContract.make(exercise: value))
        let runtime = try self.runtime(value, store: store)
        XCTAssertTrue(runtime.awaitsScienceEvidence); XCTAssertFalse(runtime.canSubmit)
        runtime.setScienceSelection(firstAnswer(study)); XCTAssertTrue(runtime.canSubmit)
        runtime.submitInline(store: store)
        XCTAssertEqual(runtime.stage, .item); XCTAssertFalse(runtime.awaitsScienceEvidence)
        XCTAssertNil(runtime.lastResult); XCTAssertTrue(store.attempts.isEmpty)
        XCTAssertEqual(runtime.index, 0); XCTAssertEqual(runtime.itemCount, 1)
        let locked = try XCTUnwrap(runtime.scienceStudy?.firstEvidence)
        let bytes = try NFImmutableAttemptRecordSnapshot.encoded(locked)
        runtime.setScienceSelection([study.evidenceClaims[0].id: [], study.evidenceClaims[1].id: []])
        XCTAssertEqual(try NFImmutableAttemptRecordSnapshot.encoded(runtime.scienceStudy?.firstEvidence), try NFImmutableAttemptRecordSnapshot.encoded(Optional(locked)))
        XCTAssertEqual(runtime.claimSelections[study.evidenceClaims[0].id], [study.observations[0].id])
        var full = firstAnswer(study)
        full[study.experimentClaim.id] = [study.experiments.first { $0.randomizesWithinBaseline && $0.commonCalibratedMeasurement }!.id]
        runtime.setScienceSelection(full); runtime.submitInline(store: store)
        XCTAssertEqual(runtime.stage, .feedback); XCTAssertEqual(runtime.lastResult?.credit, 1)
        XCTAssertEqual(store.attempts.count, 1); XCTAssertEqual(runtime.capturedSupportCount, 0)
        let attempt = try XCTUnwrap(store.attempts.first), snapshot = try XCTUnwrap(store.localSessions.archive.snapshots.first)
        XCTAssertEqual(snapshot.exercise, value)
        XCTAssertEqual(try NFImmutableAttemptRecordSnapshot.encoded(snapshot.scienceStudy?.firstEvidence), try NFImmutableAttemptRecordSnapshot.encoded(Optional(locked)))
        XCTAssertEqual(try NFImmutableAttemptRecordSnapshot.encoded(locked), bytes)
        let savedResponse = try JSONDecoder().decode(NFExerciseResponse.self, from: Data(attempt.response.utf8))
        XCTAssertEqual(savedResponse, fullAnswer(study))
        let historyText = NFResponsePresentation.text(savedResponse, exercise: snapshot.exercise)
        XCTAssertTrue(historyText.contains(study.evidenceClaims[0].text)); XCTAssertTrue(historyText.contains(study.experimentClaim.text))
        XCTAssertFalse(historyText.contains("claim.observed")); XCTAssertFalse(historyText.contains("experiment.random-common"))
        XCTAssertNotNil(NFScienceStudyHistoryProjection.make(exercise: value, draft: snapshot.scienceStudy, isProtected: false))
        XCTAssertNil(NFScienceStudyHistoryProjection.make(exercise: value, draft: snapshot.scienceStudy, isProtected: true))
        XCTAssertEqual(runtime.prepareToClose(store: store), .saved); runtime.releaseWriter()
    }

    func testFailedEvidenceSaveKeepsStageOneAndColdResumeRestoresSameStudyAndFrozenMapping() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "NFLinkedStudy-\(UUID())")
        defer { try? FileManager.default.removeItem(at: folder) }
        let owner = UUID(), url = folder.appending(path: "local.json")
        let repository = NFLocalSessionRepository(url: url, ownerDeviceID: owner)
        let (store, container) = try self.store(repository); defer { _ = container }
        let value = try exercise(), study = try XCTUnwrap(NFScienceStudyContract.make(exercise: value))
        let runtime = try self.runtime(value, store: store)
        runtime.setScienceSelection(firstAnswer(study)); XCTAssertTrue(runtime.checkpointDraft(store: store))
        let original = try Data(contentsOf: url)
        try obstruct(folder) {
            XCTAssertFalse(runtime.lockScienceEvidence(store: store))
            XCTAssertTrue(runtime.awaitsScienceEvidence); XCTAssertNil(runtime.scienceStudy?.firstEvidence)
            XCTAssertEqual(runtime.stage, .item); XCTAssertTrue(store.attempts.isEmpty)
        }
        XCTAssertEqual(try Data(contentsOf: url), original)
        XCTAssertTrue(runtime.lockScienceEvidence(store: store))
        XCTAssertEqual(runtime.prepareToClose(store: store), .saved)
        let savedRun = try XCTUnwrap(repository.archive.sessions.first); runtime.releaseWriter()
        let reopened = NFLocalSessionRepository(url: url, ownerDeviceID: owner)
        let (coldStore, coldContainer) = try self.store(reopened); defer { _ = coldContainer }
        var request = savedRun.request; request.localSessionID = savedRun.id; request.localCheckpoint = savedRun.checkpoint; request.freshlyAcceptedLaunch = false
        let cold = NFUniversalSessionRuntime(request: request)
        XCTAssertTrue(cold.checkpointDraft(store: coldStore)); cold.resume(); cold.acknowledgePresented()
        XCTAssertFalse(cold.awaitsScienceEvidence); XCTAssertEqual(cold.exercise, value)
        XCTAssertEqual(cold.scienceStudy?.firstEvidence, savedRun.checkpoint.scienceStudy?.firstEvidence)
        XCTAssertTrue(cold.recoveryText.contains(study.evidenceClaims[0].text))
        var response = firstAnswer(study); response[study.experimentClaim.id] = [study.experiments.first { $0.randomizesWithinBaseline && $0.commonCalibratedMeasurement }!.id]
        cold.setScienceSelection(response); cold.submitInline(store: coldStore)
        XCTAssertEqual(cold.stage, .feedback); XCTAssertEqual(coldStore.attempts.count, 1)
        cold.releaseWriter()
    }

    func testFutureStudyContractsAndMissingStageMetadataStayUnavailableWithoutChangingOriginals() throws {
        let value = try exercise()
        var missing = value; missing.contractMetadata?.scienceStudy = nil
        XCTAssertFalse(missing.hasSupportedScienceStudy)
        XCTAssertThrowsError(try NFExerciseSchemaValidator.validate(missing))
        XCTAssertEqual(NFExerciseScoringEngine.score(.initialDraft(for: missing), for: missing).outcome, .invalidItem)
        var future = value; future.contractMetadata?.scienceStudy?.schemaVersion = 999
        XCTAssertFalse(future.hasSupportedScienceStudy)
        XCTAssertNil(NFScienceStudyDraft.initial(for: future))
        XCTAssertThrowsError(try NFExerciseSchemaValidator.validate(future))
        let (store, container) = try self.store(); defer { _ = container }
        var request = SessionRequest(lab: .scientificReasoning, source: .focused, seed: 445, requestedItemCount: 1, isTimed: false)
        var checkpoint = try NFLocalItemCheckpoint.initial(request: request, exercise: value, slotID: UUID(), attemptID: UUID(), at: Date())
        checkpoint.scienceStudy?.schemaVersion = 999
        request.localCheckpoint = checkpoint
        let raw = try NFImmutableAttemptRecordSnapshot.encoded(checkpoint)
        let runtime = NFUniversalSessionRuntime(request: request)
        XCTAssertNotNil(runtime.unavailableReason); XCTAssertFalse(runtime.lockScienceEvidence(store: store))
        XCTAssertTrue(store.attempts.isEmpty)
        XCTAssertEqual(try NFImmutableAttemptRecordSnapshot.encoded(request.localCheckpoint), try NFImmutableAttemptRecordSnapshot.encoded(Optional(checkpoint)))
        XCTAssertEqual(raw, try NFImmutableAttemptRecordSnapshot.encoded(checkpoint))
        XCTAssertNil(NFScienceStudyHistoryProjection.make(exercise: value, draft: checkpoint.scienceStudy, isProtected: false))
        checkpoint.scienceStudy = nil; XCTAssertFalse(checkpoint.hasSupportedScienceStudy)
        request.scienceStudyPolicyVersion = 999; XCTAssertFalse(request.hasSupportedScienceStudyPolicy)
        XCTAssertNotNil(NFDeterministicSessionExerciseFactory.makeExercise(request: request, index: 0, assessmentDescriptor: nil).availabilityReason)
        runtime.releaseWriter()
    }

    func testRepairReservesNewContextInTheSameStudyFamilyAndDoesNotAmendTheOriginal() throws {
        let (store, container) = try self.store(); defer { _ = container }
        let value = try exercise(), study = try XCTUnwrap(NFScienceStudyContract.make(exercise: value))
        let runtime = try self.runtime(value, store: store)
        runtime.setScienceSelection(firstAnswer(study)); runtime.submitInline(store: store)
        var response = firstAnswer(study); response[study.experimentClaim.id] = [study.experiments.first { $0.randomizesWithinBaseline && $0.commonCalibratedMeasurement }!.id]
        runtime.setScienceSelection(response); runtime.submitInline(store: store)
        let attempt = try XCTUnwrap(store.attempts.first), original = try NFImmutableAttemptRecordSnapshot.encoded(store.localSessions.archive.snapshots.first)
        runtime.retrySimilar(store: store)
        let repair = try XCTUnwrap(store.activeSessionRequest)
        XCTAssertEqual(repair.repairOriginAttemptID, attempt.id)
        XCTAssertEqual(repair.scienceStudyPolicyVersion, 1)
        XCTAssertEqual(repair.scienceStudyExcludedContextID, study.contextID)
        let retained = try XCTUnwrap(repair.localCheckpoint?.exercise)
        let repairedStudy = try XCTUnwrap(NFScienceStudyContract.make(exercise: retained))
        XCTAssertNotEqual(repairedStudy.contextID, study.contextID)
        XCTAssertEqual(retained.contractMetadata?.familyID, value.contractMetadata?.familyID)
        XCTAssertEqual(NFAuthoredExerciseAuthority.responseFormat(for: retained.interaction), NFAuthoredExerciseAuthority.responseFormat(for: value.interaction))
        XCTAssertNotEqual(NFQuestionFingerprint.fingerprint(for: retained), NFQuestionFingerprint.fingerprint(for: value))
        XCTAssertEqual(store.attempts.count, 1)
        XCTAssertEqual(try NFImmutableAttemptRecordSnapshot.encoded(store.localSessions.archive.snapshots.first), original)
        XCTAssertEqual(repair.launchOnly().scienceStudyExcludedContextID, study.contextID)
        runtime.releaseWriter()
    }

    func testGeneratedRuntimePinsBothStudyStagesAndStartsTheNextStudyWithFreshState() throws {
        let (store, container) = try self.store(); defer { _ = container }
        let id = UUID()
        let request = NFAuthoringRequest(id: id, capability: .contextualize, lab: .scientificReasoning,
            field: .general, customTopic: "Synthetic study", learningObjective: "Separate observation and experimental control",
            style: .multipleChoice, difficulty: 0.4, count: 2, localeIdentifier: "en", seed: 445, aiMode: .disabled)
        let questions = try [445, 446].map { seed -> NFAuthoredQuestion in
            let value = try self.exercise(seed: UInt64(seed), purpose: .documentPractice)
            let question = NFAuthoredQuestion(id: value.id, lab: value.lab, style: .multipleChoice,
                prompt: value.prompt, context: value.contextText ?? "", choices: [], correctAnswer: NFScienceStudyContract.make(exercise: value)!.evidenceClaims[0].id,
                acceptedAnswers: [], explanation: value.feedback.correctExplanation,
                hint: value.feedback.hintLadder.first ?? "Inspect the study design.", decisiveStep: value.feedback.decisiveStep,
                difficulty: 0.4, citationChunkIDs: [], evidenceClass: .documentPractice, authoritativeExercise: value)
            XCTAssertTrue(NFAuthoredExerciseAuthority.validatesBinding(question)); return question
        }
        let result = NFAuthoringResult(questions: questions, provenance: .init(requestID: id,
            generatedAt: Date().addingTimeInterval(-1), route: .deterministicFallback, routeReason: "Synthetic exact study fixture",
            promptVersion: 1, modelIdentifier: "synthetic.science", sourceChunkIDs: [], sourceDocumentIDs: [], validationVersion: 1,
            repairCount: 0, cacheKey: "synthetic.science", isFallback: true), routeCandidates: [],
            validationStatus: .init(level: .deterministicKey, sourceSupport: .notApplicable), validationNotes: [])
        let runtime = AIGeneratedPracticeRuntime(result: result, request: request)
        XCTAssertTrue(runtime.checkpoint(store: store)); runtime.resume()
        let study = try XCTUnwrap(NFScienceStudyContract.make(exercise: runtime.exercise))
        runtime.setScienceSelection(firstAnswer(study)); runtime.submit(store: store)
        XCTAssertEqual(runtime.stage, 0); XCTAssertFalse(runtime.awaitsScienceEvidence); XCTAssertTrue(store.attempts.isEmpty)
        let draft = try XCTUnwrap(store.generatedPracticeDraft(for: id)); XCTAssertTrue(draft.valid)
        runtime.releaseWriter()
        let cold = AIGeneratedPracticeRuntime(result: result, request: request, draft: draft)
        XCTAssertTrue(cold.restoreCheckpoint(store: store)); cold.resume()
        XCTAssertFalse(cold.awaitsScienceEvidence); XCTAssertEqual(cold.scienceStudy?.firstEvidence, draft.scienceStudy?.firstEvidence)
        var response = firstAnswer(study); response[study.experimentClaim.id] = [study.experiments.first { $0.randomizesWithinBaseline && $0.commonCalibratedMeasurement }!.id]
        cold.setScienceSelection(response); cold.submit(store: store)
        XCTAssertEqual(cold.stage, 2); XCTAssertEqual(cold.lastScore?.credit, 1); XCTAssertEqual(store.attempts.count, 1)
        XCTAssertEqual(store.localSessions.archive.snapshots.first?.scienceStudy?.firstEvidence, draft.scienceStudy?.firstEvidence)
        cold.next(store: store)
        XCTAssertEqual(cold.index, 1); XCTAssertTrue(cold.awaitsScienceEvidence); XCTAssertNil(cold.scienceStudy?.firstEvidence)
        XCTAssertTrue(cold.claimSelections.values.allSatisfy(\.isEmpty))
        var future = draft; future.scienceStudy?.schemaVersion = 999; XCTAssertFalse(future.valid)
        cold.releaseWriter()
    }
    func testAlternativeSupportBundlesCannotCrossTheirDeclaredStageScope() throws {
        let value = try exercise(), study = try XCTUnwrap(NFScienceStudyContract.make(exercise: value))
        guard case var .claimEvidence(schema) = value.interaction else { return XCTFail("Expected scoped claims") }
        schema.supportContracts = schema.correctPairs.map { .init(claimID: $0.claimID, sufficientBundles: [$0.evidenceIDs]) }
        XCTAssertNoThrow(try NFExerciseSchemaValidator.validateInteraction(.claimEvidence(schema)))
        schema.supportContracts?[0] = .init(claimID: study.evidenceClaims[0].id,
            sufficientBundles: [[study.experiments[0].id]])
        XCTAssertThrowsError(try NFExerciseSchemaValidator.validateInteraction(.claimEvidence(schema)))
    }

    func testLocalFirstStageReceiptSurvivesALaterCompatibilityCheckpointFailure() throws {
        enum Failure: Error { case compatibilityWrite }
        let folder = FileManager.default.temporaryDirectory.appending(path: "NFLinkedStudyMirror-\(UUID())")
        defer { try? FileManager.default.removeItem(at: folder) }
        let owner = UUID(), url = folder.appending(path: "local.json")
        let repository = NFLocalSessionRepository(url: url, ownerDeviceID: owner)
        let (store, container) = try self.store(repository); defer { _ = container }
        let value = try exercise(), study = try XCTUnwrap(NFScienceStudyContract.make(exercise: value))
        let runtime = try self.runtime(value, store: store)
        runtime.setScienceSelection(firstAnswer(study))
        runtime.legacyCheckpointWriteFailure = { throw Failure.compatibilityWrite }
        XCTAssertFalse(runtime.lockScienceEvidence(store: store))
        XCTAssertFalse(runtime.awaitsScienceEvidence, "A locally frozen mapping cannot become editable after a later compatibility failure.")
        XCTAssertNotNil(runtime.saveError)
        let disk = NFLocalSessionRepository(url: url, ownerDeviceID: owner)
        let savedRun = try XCTUnwrap(disk.archive.sessions.first)
        let retained = try XCTUnwrap(savedRun.checkpoint.scienceStudy)
        XCTAssertEqual(runtime.scienceStudy, retained)
        XCTAssertTrue(store.attempts.isEmpty)
        runtime.setScienceSelection([study.evidenceClaims[0].id: [], study.evidenceClaims[1].id: []])
        XCTAssertEqual(runtime.scienceStudy, retained)
        runtime.releaseWriter()
        let (coldStore, coldContainer) = try self.store(disk); defer { _ = coldContainer }
        var request = savedRun.request
        request.localSessionID = savedRun.id; request.localCheckpoint = savedRun.checkpoint; request.freshlyAcceptedLaunch = false
        let cold = NFUniversalSessionRuntime(request: request)
        XCTAssertTrue(cold.checkpointDraft(store: coldStore)); cold.resume(); cold.acknowledgePresented()
        XCTAssertEqual(cold.scienceStudy, retained); XCTAssertFalse(cold.awaitsScienceEvidence)
        XCTAssertEqual(cold.exercise, value); XCTAssertTrue(coldStore.attempts.isEmpty)
        XCTAssertNil(cold.saveError)
        cold.releaseWriter()
    }

}

@MainActor
final class SpatialObjectControlTests: XCTestCase {
    func testCoordinateCopyUsesExactNamedOperationsAndResetPreservesOriginalScore() throws {
        for variant in [0, 1] {
            let exercise = try fixture(variant: variant)
            let metadata = try spatial(exercise)
            let original = try NFImmutableAttemptRecordSnapshot.encoded(exercise)
            let point = try XCTUnwrap(metadata.points.first)
            let policy = NFSpatialToolPolicy.resolve(exercise: exercise, metadata: metadata, phase: .committedFeedback)
            XCTAssertEqual(policy.kind, .coordinates)
            XCTAssertTrue(policy.allowsObjectChanges)
            guard case let .singleChoice(schema) = exercise.interaction else { return XCTFail("Expected the retained spatial answer schema") }
            let response = NFExerciseResponse.singleChoice(optionID: schema.correctOptionID)
            let score = NFExerciseScoringEngine.score(response, for: exercise)
            XCTAssertTrue(score.isCorrect)
            var copy = NFSpatialObjectCopy.authored
            if variant == 0 {
                XCTAssertFalse(copy.apply(.rotateX90, policy: policy, metadata: metadata))
                XCTAssertFalse(copy.apply(.rotateY90, policy: policy, metadata: metadata))
                XCTAssertFalse(copy.apply(.reflectZ, policy: policy, metadata: metadata))
                XCTAssertEqual(copy, .authored, "A planar copy cannot lose coordinates through a 3D operation")
            }
            XCTAssertTrue(copy.apply(.rotateZ90, policy: policy, metadata: metadata))
            let transformed = try XCTUnwrap(copy.points(from: metadata.points).first)
            XCTAssertEqual(transformed.x, -point.y)
            XCTAssertEqual(transformed.y, point.x)
            XCTAssertEqual(transformed.z, point.z)
            XCTAssertEqual(copy.metadata(from: metadata, policy: policy).accessibilityDescription, metadata.accessibilityDescription)
            for _ in 0..<3 { XCTAssertTrue(copy.apply(.rotateZ90, policy: policy, metadata: metadata)) }
            XCTAssertEqual(copy.points(from: metadata.points), metadata.points, "Four quarter-turns must return bit-exact source coordinates")
            XCTAssertTrue(copy.apply(.reflectX, policy: policy, metadata: metadata))
            XCTAssertEqual(copy.points(from: metadata.points).first?.x, -point.x)
            XCTAssertTrue(copy.apply(.reflectX, policy: policy, metadata: metadata))
            XCTAssertEqual(copy.points(from: metadata.points), metadata.points)
            XCTAssertTrue(copy.apply(.rotateZMinus90, policy: policy, metadata: metadata))
            copy.reset()
            XCTAssertEqual(copy, .authored)
            XCTAssertEqual(copy.metadata(from: metadata, policy: policy), metadata)
            XCTAssertEqual(NFExerciseScoringEngine.score(response, for: exercise), score)
            XCTAssertEqual(try NFImmutableAttemptRecordSnapshot.encoded(exercise), original,
                "Demonstration state must never mutate retained givens, response or evaluator authority")
        }
    }

    func testThreeDimensionalOperationOrderIsMeaningfulWhileCameraProjectionIsReadOnly() throws {
        let exercise = try fixture(variant: 1)
        let metadata = try spatial(exercise)
        let policy = NFSpatialToolPolicy.resolve(exercise: exercise, metadata: metadata, phase: .savedWorkedSolution)
        let point = try XCTUnwrap(metadata.points.first)
        var xy = NFSpatialObjectCopy.authored, yx = NFSpatialObjectCopy.authored
        XCTAssertTrue(xy.apply(.rotateX90, policy: policy, metadata: metadata))
        XCTAssertTrue(xy.apply(.rotateY90, policy: policy, metadata: metadata))
        XCTAssertTrue(yx.apply(.rotateY90, policy: policy, metadata: metadata))
        XCTAssertTrue(yx.apply(.rotateX90, policy: policy, metadata: metadata))
        XCTAssertNotEqual(xy.points(from: metadata.points), yx.points(from: metadata.points), "Object rotations cannot be modeled as an unordered camera setting")
        let expected = NFSpatialPoint(label: point.label, x: point.y, y: -point.z!, z: -point.x)
        XCTAssertEqual(xy.points(from: metadata.points), [expected])
        let frozen = xy
        let front = NFSpatialOrthographicProjection.components(point, camera: "Front")
        let side = NFSpatialOrthographicProjection.components(point, camera: "Side")
        let top = NFSpatialOrthographicProjection.components(point, camera: "Top")
        XCTAssertEqual(front.horizontal, point.x); XCTAssertEqual(front.vertical, point.y)
        XCTAssertEqual(side.horizontal, -point.z!); XCTAssertEqual(side.vertical, point.y)
        XCTAssertEqual(top.horizontal, point.x); XCTAssertEqual(top.vertical, -point.z!)
        XCTAssertEqual(NFSpatialOrthographicProjection.axisLabels(metadata: metadata, camera: "Side"), ["−z", "y"])
        XCTAssertEqual(NFSpatialOrthographicProjection.axisLabels(metadata: metadata, camera: "Top"), ["x", "−z"])
        XCTAssertEqual(xy, frozen, "Camera projections cannot mutate the object copy")
        let scene = NFSpatialRealitySceneFactory.makeScene(for: metadata)
        scene.orientation = simd_quatf(angle: 0.37, axis: [0, 1, 0])
        scene.position = [1, 2, 3]
        let retainedOrientation = scene.orientation.vector
        let retainedPosition = scene.position
        let originalMarker = try XCTUnwrap(scene.findEntity(named: "point.\(point.label)"))
        let originalPosition = originalMarker.position
        NFSpatialRealitySceneFactory.updateObject(in: scene, metadata: xy.metadata(from: metadata, policy: policy), foldedNet: false)
        XCTAssertTrue(scene.findEntity(named: "point.\(point.label)") === originalMarker, "Updating the object retains its scene and camera target")
        XCTAssertNotEqual(originalMarker.position, originalPosition)
        XCTAssertEqual(scene.orientation.vector, retainedOrientation)
        XCTAssertEqual(scene.position, retainedPosition)
        xy.reset()
        NFSpatialRealitySceneFactory.updateObject(in: scene, metadata: metadata, foldedNet: false)
        XCTAssertEqual(originalMarker.position, originalPosition)
        XCTAssertEqual(scene.orientation.vector, retainedOrientation)
        XCTAssertEqual(xy.points(from: metadata.points), metadata.points)
    }

    func testIndependentProtectedFutureAndUnboundMetadataCannotTransformOrDiscloseObjectState() throws {
        for variant in [0, 1, 4] {
            let exercise = try fixture(variant: variant)
            let metadata = try spatial(exercise)
            let independent = NFSpatialToolPolicy.resolve(exercise: exercise, metadata: metadata, phase: .independent)
            XCTAssertNotEqual(independent.kind, .unavailable, "Ordinary learners are told which tools open later")
            XCTAssertFalse(independent.allowsObjectChanges)
            var copy = NFSpatialObjectCopy.authored
            for operation in NFSpatialCopyOperation.allCases { XCTAssertFalse(copy.apply(operation, policy: independent, metadata: metadata)) }
            XCTAssertFalse(copy.setFolded(true, policy: independent))
            XCTAssertNil(copy.description(original: metadata, policy: independent, locale: .init(identifier: "en_US")))
            XCTAssertEqual(copy, .authored)
            for override in [
                ["assessmentProtected": true], ["purpose": NFExercisePurpose.baseline.rawValue],
                ["purpose": NFExercisePurpose.assessmentHoldout.rawValue], ["evidenceClass": EvidenceClass.assessmentHoldout.rawValue],
                ["purpose": NFExercisePurpose.nearTransfer.rawValue], ["schemaVersion": 999],
                ["availabilityReason": "The original question is unavailable."]
            ] as [[String: Any]] {
                let unavailable = try altered(exercise, values: override)
                for phase in [NFSpatialLearningPhase.savedWorkedSolution, .committedFeedback] {
                    let policy = NFSpatialToolPolicy.resolve(exercise: unavailable, metadata: metadata, phase: phase)
                    XCTAssertEqual(policy, .unavailable)
                    XCTAssertFalse(copy.setFolded(true, policy: policy))
                    XCTAssertFalse(copy.apply(.rotateZ90, policy: policy, metadata: metadata))
                    XCTAssertNil(copy.description(original: metadata, policy: policy, locale: .init(identifier: "en_US")))
                }
            }
            XCTAssertEqual(NFSpatialToolPolicy.resolve(exercise: nil, metadata: metadata, phase: .committedFeedback), .unavailable)
            let mismatched = metadataCopy(metadata, viewpoint: "An unrelated retained orientation")
            XCTAssertEqual(NFSpatialToolPolicy.resolve(exercise: exercise, metadata: mismatched, phase: .committedFeedback), .unavailable)
            let protectedMetadata = metadataCopy(metadata, protection: "spatial.protected.fixture")
            let protectedExercise = try altered(exercise, values: ["representations": try json([NFExerciseRepresentation.spatial(protectedMetadata)])])
            XCTAssertEqual(NFSpatialToolPolicy.resolve(exercise: protectedExercise, metadata: protectedMetadata, phase: .committedFeedback), .unavailable)
        }
    }

    func testEveryCanonicalNetHasSixOriginalLabelsAndConsistentFoldedRelationships() throws {
        let layouts = NFCubeNetEngine.validCanonicalLayouts
        XCTAssertEqual(layouts.count, 11)
        for layout in layouts {
            let original = try JSONEncoder().encode(layout)
            let faces = try XCTUnwrap(NFCubeNetEngine.displayFaces(encodedDescription: layout.encodedDescription))
            XCTAssertEqual(faces.count, 6)
            XCTAssertEqual(Set(faces.map(\.label)), Set(layout.cells.map(\.label)))
            XCTAssertEqual(Set(faces.map(\.normal)).count, 6)
            for face in faces {
                let cell = try XCTUnwrap(layout.cells.first { $0.label == face.label })
                XCTAssertEqual(face.column, cell.x); XCTAssertEqual(face.row, cell.y)
                XCTAssertEqual(dot(face.normal, face.normal), 1)
                XCTAssertEqual(dot(face.right, face.right), 1); XCTAssertEqual(dot(face.up, face.up), 1)
                XCTAssertEqual(dot(face.normal, face.right), 0); XCTAssertEqual(dot(face.normal, face.up), 0)
                XCTAssertEqual(dot(face.right, face.up), 0)
                XCTAssertEqual(cross(face.right, face.up), face.normal, "Every face frame must be a proper rotation, not a mirrored label")
                let opposite = try XCTUnwrap(faces.first { $0.normal == (SIMD3<Int32>.zero &- face.normal) })
                XCTAssertEqual(opposite.label, NFCubeNetEngine.oppositeFace(to: face.label, in: layout))
            }
            XCTAssertEqual(try JSONEncoder().encode(layout), original)
        }
    }

    func testNativeCubeSceneUsesActualRetainedFacesAndResetReturnsToExactUnfoldedNet() throws {
        let exercise = try fixture(variant: 4)
        let metadata = try spatial(exercise)
        let faces = try XCTUnwrap(NFCubeNetEngine.displayFaces(encodedDescription: metadata.objectDescription))
        let policy = NFSpatialToolPolicy.resolve(exercise: exercise, metadata: metadata, phase: .committedFeedback)
        XCTAssertEqual(policy.kind, .cubeNet)
        let sourceBytes = try NFImmutableAttemptRecordSnapshot.encoded(exercise)
        var copy = NFSpatialObjectCopy.authored
        XCTAssertTrue(copy.setFolded(true, policy: policy))
        let folded = NFSpatialRealitySceneFactory.makeScene(for: metadata, foldedNet: copy.isFolded)
        for face in faces {
            let entity = try XCTUnwrap(folded.findEntity(named: "face.\(face.label)"))
            XCTAssertEqual(entity.position, SIMD3(Float(face.normal.x), Float(face.normal.y), Float(face.normal.z)) * 0.5)
            XCTAssertNotNil(entity.findEntity(named: "face-label.\(face.label)"))
        }
        let foldedDescription = try XCTUnwrap(copy.description(original: metadata, policy: policy, locale: .init(identifier: "en_US")))
        for face in faces { XCTAssertTrue(foldedDescription.contains(face.label)) }
        copy.reset()
        XCTAssertEqual(copy, .authored)
        let reset = NFSpatialRealitySceneFactory.makeScene(for: metadata, foldedNet: copy.isFolded)
        let centerX = Float(try XCTUnwrap(faces.map(\.column).min()) + XCTUnwrap(faces.map(\.column).max())) / 2
        let centerY = Float(try XCTUnwrap(faces.map(\.row).min()) + XCTUnwrap(faces.map(\.row).max())) / 2
        let protectedMetadata = metadataCopy(metadata, protection: "spatial.protected.fixture")
        let protected = NFSpatialRealitySceneFactory.makeScene(for: protectedMetadata, foldedNet: true)
        for face in faces {
            let expected = SIMD3<Float>(Float(face.column) - centerX, centerY - Float(face.row), 0)
            XCTAssertEqual(try XCTUnwrap(reset.findEntity(named: "face.\(face.label)")).position, expected)
            XCTAssertEqual(try XCTUnwrap(protected.findEntity(named: "face.\(face.label)")).position, expected,
                "Even an explicit folded renderer request cannot fold protected grammar")
        }
        XCTAssertEqual(try NFImmutableAttemptRecordSnapshot.encoded(exercise), sourceBytes)
    }

    func testMalformedNetIsUnavailableRatherThanReplacedByAnUnrelatedCube() throws {
        let exercise = try fixture(variant: 4)
        let original = try spatial(exercise)
        let valid = try XCTUnwrap(NFCubeNetLayout(encodedDescription: original.objectDescription))
        var duplicateLabels = valid.cells
        duplicateLabels[1] = .init(x: duplicateLabels[1].x, y: duplicateLabels[1].y, label: duplicateLabels[0].label)
        let malformed = [
            "A valid cube net [A@0,0]", "An unknown object [A@0,0;B@1,0;C@2,0;D@0,1;E@0,2;F@0,3]",
            NFCubeNetLayout(cells: duplicateLabels).encodedDescription,
            "A valid cube net [A@\(Int.max),0;B@1,0;C@2,0;D@0,1;E@0,2;F@0,3]",
            "A valid cube net [A@\(Int.min),0;B@1,0;C@2,0;D@0,1;E@0,2;F@0,3]",
            "A valid cube net [" + String(repeating: "A", count: 2_049) + "]"
        ]
        for description in malformed {
            XCTAssertNil(NFCubeNetEngine.displayFaces(encodedDescription: description))
            let metadata = metadataCopy(original, description: description)
            let changed = try altered(exercise, values: ["representations": try json([NFExerciseRepresentation.spatial(metadata)])])
            XCTAssertEqual(NFSpatialToolPolicy.resolve(exercise: changed, metadata: metadata, phase: .committedFeedback), .unavailable)
            if description.hasPrefix("A valid cube net") {
                XCTAssertNil(NFSpatialRealitySceneFactory.makeScene(for: metadata).findEntity(named: "face.A"))
            }
            XCTAssertEqual(metadata.objectDescription, description)
        }
    }

    private func fixture(variant: Int) throws -> NFExercise {
        try NFFallbackExerciseGenerator.generate(.init(seed: 2_026_090_5, index: variant, lab: .spatial,
            purpose: .practice, localeIdentifier: "en_US", preferredAssessmentFormat: .singleChoice,
            preferredAssessmentMechanicID: "spatial.fallback-variant-\(variant)"))
    }
    private func spatial(_ exercise: NFExercise) throws -> NFSpatialRepresentationMetadata {
        try XCTUnwrap(exercise.independentRepresentations.compactMap {
            if case let .spatial(value) = $0 { return value }; return nil
        }.first)
    }
    private func json<T: Encodable>(_ value: T) throws -> Any { try JSONSerialization.jsonObject(with: JSONEncoder().encode(value)) }
    private func altered(_ exercise: NFExercise, values: [String: Any]) throws -> NFExercise {
        var object = try XCTUnwrap(try json(exercise) as? [String: Any])
        object.merge(values) { _, replacement in replacement }
        return try JSONDecoder().decode(NFExercise.self, from: JSONSerialization.data(withJSONObject: object))
    }
    private func metadataCopy(_ original: NFSpatialRepresentationMetadata, viewpoint: String? = nil,
                              protection: String? = nil, description: String? = nil) -> NFSpatialRepresentationMetadata {
        .init(stimulusCategory: original.stimulusCategory, dimension: original.dimension,
            objectDescription: description ?? original.objectDescription, viewpoint: viewpoint ?? original.viewpoint,
            operations: original.operations, points: original.points, axisLabels: original.axisLabels,
            accessibilityDescription: original.accessibilityDescription, assetName: original.assetName,
            protectedGrammarID: protection ?? original.protectedGrammarID, difficultyParameters: original.difficultyParameters)
    }
    private func dot(_ a: SIMD3<Int32>, _ b: SIMD3<Int32>) -> Int32 { a.x * b.x + a.y * b.y + a.z * b.z }
    private func cross(_ a: SIMD3<Int32>, _ b: SIMD3<Int32>) -> SIMD3<Int32> {
        .init(a.y * b.z - a.z * b.y, a.z * b.x - a.x * b.z, a.x * b.y - a.y * b.x)
    }
}


@MainActor
final class LinkedTransferWorkflowTests: XCTestCase {
    private func exercise(seed: UInt64 = 445, locale: String = "en", purpose: NFExercisePurpose = .practice,
                          policy: Int? = 1, excludedContext: String? = nil) throws -> NFExercise {
        try NFFallbackExerciseGenerator.generate(.init(seed: seed, index: 0, lab: .transfer,
            purpose: purpose, localeIdentifier: locale, preferredAssessmentMechanicID: "fixture.fallback-variant-2",
            transferPolicyVersion: policy, transferExcludedContextID: excludedContext))
    }
    private func store(_ repository: NFLocalSessionRepository? = nil) throws -> (AppStore, ModelContainer) {
        let container = try ModelContainer(for: Schema(NFSchemaV1.models), configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        var draft = OnboardingDraft(); draft.aiMode = .disabled
        container.mainContext.insert(UserProfileRecord(draft: draft)); try container.mainContext.save()
        return (AppStore(context: container.mainContext, localSessionRepository: repository ?? NFLocalSessionRepository(),
            allowsSharedWidgetPublishing: false), container)
    }
    private func runtime(_ value: NFExercise, store: AppStore) throws -> NFUniversalSessionRuntime {
        var request = SessionRequest(lab: .transfer, source: .focused, seed: value.seed,
            localeIdentifier: value.localeIdentifier, evidenceClass: value.evidenceClass,
            requestedItemCount: 1, isTimed: false, timingCondition: .init(.untimed),
            mechanicID: NFDefaultContentCatalog.activity(id: value.contractMetadata?.familyID ?? "")?.mechanicID)
        request.transferPolicyVersion = value.contractMetadata?.transferRelationship?.policyVersion
        request.localCheckpoint = try .initial(request: request, exercise: value, slotID: UUID(), attemptID: UUID(), at: Date().addingTimeInterval(-1))
        request.freshlyAcceptedLaunch = true
        let runtime = NFUniversalSessionRuntime(request: request)
        XCTAssertTrue(runtime.checkpointDraft(store: store)); runtime.resume(); runtime.acknowledgePresented()
        XCTAssertNil(runtime.unavailableReason); return runtime
    }
    private func answer(_ contract: NFTransferRelationshipContract, relationship: String = NFTransferRelationshipContract.productID, total: String? = nil) -> NFExerciseResponse {
        .logicState(.init(finalState: [NFTransferRelationshipContract.totalKey: total ?? String(contract.targetTotal)], violatedRuleID: relationship))
    }
    private func obstruct(_ folder: URL, perform body: () throws -> Void) throws {
        let backup = folder.appendingPathExtension("preserved")
        try FileManager.default.moveItem(at: folder, to: backup)
        try Data("Synthetic unavailable destination directory".utf8).write(to: folder)
        defer { try? FileManager.default.removeItem(at: folder); try? FileManager.default.moveItem(at: backup, to: folder) }
        try body()
    }

    func testTwoSkillContractBindsBothContextsUnitsAndDeclaredPartialScoringWithoutChangingLegacyRecipes() throws {
        var contexts: Set<String> = [], totals: Set<Int> = []
        for locale in ["en", "ja"] {
            for seed in 0..<20 {
                let value = try exercise(seed: UInt64(seed), locale: locale)
                let contract = try XCTUnwrap(NFTransferRelationshipContract.make(exercise: value))
                contexts.insert(contract.contextID); totals.insert(contract.targetTotal)
                XCTAssertEqual(value.schemaVersion, 5); XCTAssertEqual(value.generatorVersion, 8)
                XCTAssertEqual(contract.requiredSkills, ["skill.quantitative", "skill.mentalMath"])
                XCTAssertEqual(value.skillWeights, ["skill.transfer": 0.7, "skill.quantitative": 0.15, "skill.mentalMath": 0.15])
                XCTAssertEqual(contract.targetTotal * 60, contract.targetRate * contract.targetSeconds)
                XCTAssertEqual(contract.tableRows[0][3], "\(contract.sourceRate * contract.sourceMinutes) \(contract.sourceUnit)")
                XCTAssertEqual(contract.tableRows[1][3], contract.unknownTotalLabel)
                XCTAssertEqual(value.independentRepresentations, [contract.table]); XCTAssertTrue(value.citations.isEmpty)
                XCTAssertNil(value.contractMetadata?.editorialDemand)
                XCTAssertEqual(NFExerciseScoringEngine.score(answer(contract), for: value).credit, 1)
                XCTAssertEqual(NFExerciseScoringEngine.score(answer(contract, relationship: "relationship.divide"), for: value).credit, 0.8, accuracy: 0.000_001)
                XCTAssertEqual(NFExerciseScoringEngine.score(answer(contract, total: "0"), for: value).credit, 0.2, accuracy: 0.000_001)
                let legacy = try exercise(seed: UInt64(seed), locale: locale, policy: nil)
                let explicitLegacy = try NFFallbackExerciseGenerator.generate(.init(seed: UInt64(seed), index: 0, lab: .transfer,
                    purpose: .practice, localeIdentifier: locale, preferredAssessmentMechanicID: "fixture.fallback-variant-2"))
                XCTAssertEqual(try NFImmutableAttemptRecordSnapshot.encoded(legacy), try NFImmutableAttemptRecordSnapshot.encoded(explicitLegacy))
                XCTAssertEqual(legacy.schemaVersion, 2); XCTAssertEqual(legacy.generatorVersion, 4)
                XCTAssertNotEqual(value.id, legacy.id)
                XCTAssertNil(legacy.contractMetadata?.transferRelationship)
            }
        }
        XCTAssertEqual(contexts.count, 3); XCTAssertGreaterThan(totals.count, 5)
        XCTAssertThrowsError(try exercise(purpose: .baseline)); XCTAssertThrowsError(try exercise(purpose: .nearTransfer))
        XCTAssertThrowsError(try exercise(policy: 999)); XCTAssertThrowsError(try exercise(excludedContext: "unknown"))
    }

    func testRelationshipLockAcceptsWrongCompleteChoiceWithoutScoringAndBlocksPrematureTotalOrHelp() throws {
        let (store, container) = try self.store(); defer { _ = container }
        let value = try exercise(), runtime = try self.runtime(value, store: store)
        XCTAssertTrue(runtime.awaitsTransferRelationship); XCTAssertFalse(runtime.canSubmit)
        runtime.setTransferTotal("123"); XCTAssertEqual(runtime.logicState[NFTransferRelationshipContract.totalKey], "")
        runtime.requestHint(store: store); runtime.revealSolution(store: store)
        XCTAssertEqual(runtime.hintCount, 0); XCTAssertFalse(runtime.solutionRevealed)
        runtime.setTransferRelationship("relationship.divide"); XCTAssertTrue(runtime.canSubmit)
        runtime.submitInline(store: store)
        XCTAssertFalse(runtime.awaitsTransferRelationship); XCTAssertEqual(runtime.stage, .item)
        XCTAssertEqual(runtime.transferRelationship?.firstRelationshipID, "relationship.divide")
        XCTAssertTrue(store.attempts.isEmpty); XCTAssertNil(runtime.lastResult); XCTAssertNil(runtime.reflectionTrigger)
        runtime.setTransferRelationship(NFTransferRelationshipContract.productID)
        XCTAssertEqual(runtime.violatedRuleID, "relationship.divide", "The first model remains part of the submitted answer.")
        runtime.requestHint(store: store)
        XCTAssertEqual(runtime.hintCount, 1); XCTAssertEqual(store.localSessions.archive.sessions.first?.checkpoint.hintCount, 1)
        XCTAssertEqual(store.localSessions.archive.sessions.first?.checkpoint.transferRelationship?.firstRelationshipID, "relationship.divide")
        runtime.releaseWriter()
    }

    func testOrdinaryBothStagesCommitOneReadableOriginalWithExactHistoryAndNoMandatoryReflection() throws {
        let (store, container) = try self.store(); defer { _ = container }
        let value = try exercise(), contract = try XCTUnwrap(NFTransferRelationshipContract.make(exercise: value))
        let runtime = try self.runtime(value, store: store)
        runtime.setTransferRelationship(NFTransferRelationshipContract.productID); runtime.submitInline(store: store)
        XCTAssertEqual(runtime.stage, .item); XCTAssertFalse(runtime.canSubmit)
        runtime.setTransferTotal(String(contract.targetTotal)); runtime.submitInline(store: store)
        XCTAssertEqual(runtime.stage, .feedback); XCTAssertEqual(runtime.lastResult?.credit, 1)
        XCTAssertEqual(store.attempts.count, 1); XCTAssertEqual(runtime.capturedSupportCount, 0)
        let attempt = try XCTUnwrap(store.attempts.first), snapshot = try XCTUnwrap(store.localSessions.archive.snapshots.first)
        XCTAssertEqual(snapshot.exercise, value)
        XCTAssertEqual(snapshot.transferRelationship?.firstRelationshipID, NFTransferRelationshipContract.productID)
        let text = NFResponsePresentation.text(attempt.response, exercise: snapshot.exercise)
        XCTAssertTrue(text.contains(contract.relationships.first { $0.id == NFTransferRelationshipContract.productID }!.text))
        XCTAssertTrue(text.contains("\(contract.targetTotal) \(contract.targetUnit)"))
        XCTAssertFalse(text.contains(NFTransferRelationshipContract.productID)); XCTAssertFalse(text.contains("targetTotal"))
        XCTAssertNotNil(NFTransferRelationshipHistoryProjection.make(exercise: value, draft: snapshot.transferRelationship, isProtected: false))
        XCTAssertNil(NFTransferRelationshipHistoryProjection.make(exercise: value, draft: snapshot.transferRelationship, isProtected: true))
        runtime.setTransferTotal("999"); XCTAssertEqual(runtime.logicState[NFTransferRelationshipContract.totalKey], String(contract.targetTotal))
        XCTAssertEqual(runtime.prepareToClose(store: store), .saved); runtime.releaseWriter()
    }

    func testFailedFirstWriteRollsBackButColdResumeRetainsAcknowledgedRelationshipAndNumericDraft() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "NFTransfer-\(UUID())")
        defer { try? FileManager.default.removeItem(at: folder) }
        let owner = UUID(), url = folder.appending(path: "local.json"), repo = NFLocalSessionRepository(url: folder.appending(path: "local.json"), ownerDeviceID: owner)
        let (store, container) = try self.store(repo); defer { _ = container }
        let value = try exercise(), runtime = try self.runtime(value, store: store)
        runtime.setTransferRelationship(NFTransferRelationshipContract.productID); XCTAssertTrue(runtime.checkpointDraft(store: store))
        let bytes = try Data(contentsOf: url)
        try obstruct(folder) {
            XCTAssertFalse(runtime.lockTransferRelationship(store: store)); XCTAssertTrue(runtime.awaitsTransferRelationship)
            XCTAssertNil(runtime.transferRelationship?.firstRelationshipID); XCTAssertTrue(store.attempts.isEmpty)
        }
        XCTAssertEqual(try Data(contentsOf: url), bytes)
        XCTAssertTrue(runtime.lockTransferRelationship(store: store)); runtime.setTransferTotal("17")
        XCTAssertEqual(runtime.prepareToClose(store: store), .saved)
        let run = try XCTUnwrap(repo.archive.sessions.first); runtime.releaseWriter()
        let (coldStore, coldContainer) = try self.store(NFLocalSessionRepository(url: url, ownerDeviceID: owner)); defer { _ = coldContainer }
        var request = run.request; request.localSessionID = run.id; request.localCheckpoint = run.checkpoint; request.freshlyAcceptedLaunch = false
        let cold = NFUniversalSessionRuntime(request: request)
        XCTAssertTrue(cold.checkpointDraft(store: coldStore)); cold.resume(); cold.acknowledgePresented()
        XCTAssertEqual(cold.exercise, value); XCTAssertFalse(cold.awaitsTransferRelationship)
        XCTAssertEqual(cold.transferRelationship, run.checkpoint.transferRelationship)
        XCTAssertEqual(cold.logicState[NFTransferRelationshipContract.totalKey], "17")
        XCTAssertTrue(coldStore.attempts.isEmpty); cold.releaseWriter()
    }

    func testLocalRelationshipAcknowledgementSurvivesLegacyMirrorFailureAndColdReplay() throws {
        enum Failure: Error { case mirror }
        let folder = FileManager.default.temporaryDirectory.appending(path: "NFTransferMirror-\(UUID())")
        defer { try? FileManager.default.removeItem(at: folder) }
        let owner = UUID(), url = folder.appending(path: "local.json")
        let (store, container) = try self.store(NFLocalSessionRepository(url: url, ownerDeviceID: owner)); defer { _ = container }
        let value = try exercise(), runtime = try self.runtime(value, store: store)
        runtime.setTransferRelationship(NFTransferRelationshipContract.productID)
        runtime.legacyCheckpointWriteFailure = { throw Failure.mirror }
        XCTAssertFalse(runtime.lockTransferRelationship(store: store)); XCTAssertFalse(runtime.awaitsTransferRelationship)
        XCTAssertNotNil(runtime.saveError)
        let disk = NFLocalSessionRepository(url: url, ownerDeviceID: owner), run = try XCTUnwrap(disk.archive.sessions.first)
        XCTAssertEqual(runtime.transferRelationship, run.checkpoint.transferRelationship); runtime.releaseWriter()
        let (coldStore, coldContainer) = try self.store(disk); defer { _ = coldContainer }
        var request = run.request; request.localSessionID = run.id; request.localCheckpoint = run.checkpoint; request.freshlyAcceptedLaunch = false
        let cold = NFUniversalSessionRuntime(request: request)
        XCTAssertTrue(cold.checkpointDraft(store: coldStore)); cold.resume(); cold.acknowledgePresented()
        XCTAssertFalse(cold.awaitsTransferRelationship); XCTAssertEqual(cold.transferRelationship, run.checkpoint.transferRelationship)
        XCTAssertTrue(coldStore.attempts.isEmpty); cold.releaseWriter()
    }

    func testFutureMissingAndOversizedTransferStateRetainsOriginalsWithoutScoringOrClosing() throws {
        let value = try exercise()
        var missing = value; missing.contractMetadata?.transferRelationship = nil
        XCTAssertFalse(missing.hasSupportedTransferRelationship)
        XCTAssertThrowsError(try NFExerciseSchemaValidator.validate(missing))
        XCTAssertEqual(NFExerciseScoringEngine.score(.initialDraft(for: missing), for: missing).outcome, .invalidItem)
        var future = value; future.contractMetadata?.transferRelationship?.schemaVersion = 999
        XCTAssertFalse(future.hasSupportedTransferRelationship); XCTAssertNil(NFTransferRelationshipDraft.initial(for: future))
        let (store, container) = try self.store(); defer { _ = container }
        let runtime = try self.runtime(value, store: store)
        runtime.setTransferRelationship(NFTransferRelationshipContract.productID); runtime.submitInline(store: store)
        let long = String(repeating: "7", count: 501)
        runtime.setTransferTotal(long); XCTAssertFalse(runtime.canSubmit)
        XCTAssertFalse(runtime.checkpointDraft(store: store)); XCTAssertTrue(runtime.recoveryText.contains(long))
        XCTAssertEqual(runtime.logicState[NFTransferRelationshipContract.totalKey], long)
        XCTAssertTrue(store.attempts.isEmpty)
        XCTAssertEqual(runtime.prepareToClose(store: store), .unacknowledged)
        runtime.resume(); runtime.acknowledgePresented()
        runtime.setTransferTotal("17"); XCTAssertTrue(runtime.checkpointDraft(store: store)); runtime.releaseWriter()
        var checkpoint = try NFLocalItemCheckpoint.initial(request: .init(lab: .transfer, source: .focused, seed: 445), exercise: value, slotID: UUID(), attemptID: UUID(), at: Date())
        var mismatchedRequest = SessionRequest(lab: .transfer, source: .focused, seed: 445)
        mismatchedRequest.localCheckpoint = checkpoint
        XCTAssertFalse(mismatchedRequest.supportsTransferRecipe(in: checkpoint))
        let unavailable = NFUniversalSessionRuntime(request: mismatchedRequest)
        XCTAssertNotNil(unavailable.unavailableReason); unavailable.releaseWriter()
        checkpoint.transferRelationship = nil; XCTAssertFalse(checkpoint.hasSupportedTransferRelationship)
        let legacy = try exercise(policy: nil)
        let legacyBytes = try NFImmutableAttemptRecordSnapshot.encoded(legacy)
        let oldCheckpoint = try NFLocalItemCheckpoint.initial(request: mismatchedRequest, exercise: legacy, slotID: UUID(), attemptID: UUID(), at: Date())
        mismatchedRequest.transferPolicyVersion = 1; mismatchedRequest.localCheckpoint = oldCheckpoint
        XCTAssertFalse(mismatchedRequest.supportsTransferRecipe(in: oldCheckpoint))
        let incompatibleRecipe = NFUniversalSessionRuntime(request: mismatchedRequest)
        XCTAssertNotNil(incompatibleRecipe.unavailableReason)
        XCTAssertEqual(try NFImmutableAttemptRecordSnapshot.encoded(oldCheckpoint.exercise), try NFImmutableAttemptRecordSnapshot.encoded(Optional(legacy)))
        XCTAssertEqual(try NFImmutableAttemptRecordSnapshot.encoded(legacy), legacyBytes)
        XCTAssertTrue(store.attempts.isEmpty); incompatibleRecipe.releaseWriter()
    }

    func testRepairKeepsRelationshipFamilyAndChangesTargetContextWithoutAmendingOriginal() throws {
        let (store, container) = try self.store(); defer { _ = container }
        let value = try exercise(), contract = try XCTUnwrap(NFTransferRelationshipContract.make(exercise: value))
        let runtime = try self.runtime(value, store: store)
        runtime.setTransferRelationship(NFTransferRelationshipContract.productID); runtime.submitInline(store: store)
        runtime.setTransferTotal(String(contract.targetTotal)); runtime.submitInline(store: store)
        let original = try NFImmutableAttemptRecordSnapshot.encoded(store.localSessions.archive.snapshots.first)
        runtime.retrySimilar(store: store)
        let repair = try XCTUnwrap(store.activeSessionRequest), repaired = try XCTUnwrap(repair.localCheckpoint?.exercise)
        XCTAssertEqual(repair.transferPolicyVersion, 1); XCTAssertEqual(repair.transferExcludedContextID, contract.contextID)
        XCTAssertNotEqual(NFTransferRelationshipContract.make(exercise: repaired)?.contextID, contract.contextID)
        XCTAssertEqual(repaired.contractMetadata?.familyID, value.contractMetadata?.familyID)
        XCTAssertNotEqual(NFQuestionFingerprint.fingerprint(for: repaired), NFQuestionFingerprint.fingerprint(for: value))
        XCTAssertEqual(try NFImmutableAttemptRecordSnapshot.encoded(store.localSessions.archive.snapshots.first), original)
        XCTAssertEqual(repair.launchOnly().transferExcludedContextID, contract.contextID); runtime.releaseWriter()
    }

    func testGeneratedTypedAdapterFreezesSameRelationshipBeforeCoachingAndReplaysBothStages() throws {
        let (store, container) = try self.store(); defer { _ = container }
        let id = UUID()
        let request = NFAuthoringRequest(id: id, capability: .contextualize, lab: .transfer,
            field: .general, customTopic: "Rate in another context", learningObjective: "Map quantities and convert units",
            style: .multipleChoice, difficulty: 0.6, count: 2, localeIdentifier: "en", seed: 445, aiMode: .disabled)
        let questions = try [445, 446].map { seed -> NFAuthoredQuestion in
            let value = try self.exercise(seed: UInt64(seed), purpose: .documentPractice)
            let contract = try XCTUnwrap(NFTransferRelationshipContract.make(exercise: value))
            let question = NFAuthoredQuestion(id: value.id, lab: value.lab, style: .multipleChoice,
                prompt: value.prompt, context: value.contextText ?? "", choices: [],
                correctAnswer: "\(NFTransferRelationshipContract.totalKey)=\(contract.targetTotal)", acceptedAnswers: [],
                explanation: value.feedback.correctExplanation, hint: value.feedback.hintLadder[0], decisiveStep: value.feedback.decisiveStep,
                difficulty: 0.6, citationChunkIDs: [], evidenceClass: .documentPractice, authoritativeExercise: value)
            XCTAssertTrue(NFAuthoredExerciseAuthority.validatesBinding(question)); return question
        }
        let result = NFAuthoringResult(questions: questions, provenance: .init(requestID: id,
            generatedAt: Date().addingTimeInterval(-1), route: .deterministicFallback, routeReason: "Synthetic linked transfer fixture",
            promptVersion: 1, modelIdentifier: "synthetic.transfer", sourceChunkIDs: [], sourceDocumentIDs: [], validationVersion: 1,
            repairCount: 0, cacheKey: "synthetic.transfer", isFallback: true), routeCandidates: [],
            validationStatus: .init(level: .deterministicKey, sourceSupport: .notApplicable), validationNotes: [])
        let runtime = AIGeneratedPracticeRuntime(result: result, request: request)
        XCTAssertTrue(runtime.checkpoint(store: store)); runtime.resume()
        runtime.toggleCoaching(store: store); XCTAssertEqual(runtime.coachingHintCount, 0)
        runtime.setTransferRelationship(NFTransferRelationshipContract.productID); runtime.submit(store: store)
        XCTAssertEqual(runtime.stage, 0); XCTAssertFalse(runtime.awaitsTransferRelationship); XCTAssertTrue(store.attempts.isEmpty)
        runtime.setTransferTotal("17"); XCTAssertTrue(runtime.checkpoint(store: store))
        let saved = try XCTUnwrap(store.generatedPracticeDraft(for: id)); XCTAssertTrue(saved.valid); runtime.releaseWriter()
        let cold = AIGeneratedPracticeRuntime(result: result, request: request, draft: saved)
        XCTAssertTrue(cold.restoreCheckpoint(store: store)); cold.resume()
        XCTAssertEqual(cold.logicState[NFTransferRelationshipContract.totalKey], "17")
        XCTAssertEqual(cold.transferRelationship, saved.transferRelationship)
        let contract = try XCTUnwrap(NFTransferRelationshipContract.make(exercise: cold.exercise))
        cold.setTransferTotal(String(contract.targetTotal)); cold.submit(store: store)
        XCTAssertEqual(cold.stage, 2); XCTAssertEqual(cold.lastScore?.credit, 1); XCTAssertEqual(store.attempts.count, 1)
        XCTAssertEqual(store.localSessions.archive.snapshots.first?.transferRelationship, saved.transferRelationship)
        cold.next(store: store); XCTAssertEqual(cold.index, 1); XCTAssertTrue(cold.awaitsTransferRelationship)
        XCTAssertNil(cold.violatedRuleID); XCTAssertEqual(cold.logicState[NFTransferRelationshipContract.totalKey], "")
        var future = saved; future.transferRelationship?.schemaVersion = 999; XCTAssertFalse(future.valid)
        cold.releaseWriter()
    }
}

@MainActor
final class GraphConstructionWorkflowTests: XCTestCase {
    private func exercise(seed: UInt64 = 714, purpose: NFExercisePurpose = .practice, locale: String = "en_US", policy: Int? = 1) throws -> NFExercise {
        try NFFallbackExerciseGenerator.generate(.init(seed: seed, index: 0, lab: .quantitative,
            purpose: purpose, localeIdentifier: locale,
            preferredAssessmentMechanicID: NFGraphConstructionContract.mechanicID, graphConstructionPolicyVersion: policy))
    }
    private func store(_ repository: NFLocalSessionRepository? = nil) throws -> (AppStore, ModelContainer) {
        let container = try ModelContainer(for: Schema(NFSchemaV1.models), configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        var onboarding = OnboardingDraft(); onboarding.aiMode = .disabled
        container.mainContext.insert(UserProfileRecord(draft: onboarding)); try container.mainContext.save()
        let store = AppStore(context: container.mainContext, localSessionRepository: repository ?? NFLocalSessionRepository(), allowsSharedWidgetPublishing: false)
        XCTAssertFalse(store.allowsSharedWidgetPublishing)
        return (store, container)
    }
    private func runtime(_ exercise: NFExercise, store: AppStore) throws -> NFUniversalSessionRuntime {
        var request = SessionRequest(lab: .quantitative, source: .focused, seed: exercise.seed,
            localeIdentifier: exercise.localeIdentifier, requestedItemCount: 1, isTimed: false,
            timingCondition: .init(.untimed), mechanicID: NFGraphConstructionContract.mechanicID)
        request.graphConstructionPolicyVersion = 1
        request.localCheckpoint = try NFLocalItemCheckpoint.initial(request: request, exercise: exercise,
            slotID: UUID(), attemptID: UUID(), at: Date().addingTimeInterval(-1))
        request.freshlyAcceptedLaunch = true
        let runtime = NFUniversalSessionRuntime(request: request)
        XCTAssertTrue(runtime.checkpointDraft(store: store)); runtime.resume(); runtime.acknowledgePresented()
        XCTAssertNil(runtime.unavailableReason)
        return runtime
    }
    private func mutated(_ exercise: NFExercise, _ values: [String: Any]) throws -> NFExercise {
        var raw = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(exercise)) as? [String: Any])
        raw.merge(values) { _, replacement in replacement }
        return try JSONDecoder().decode(NFExercise.self, from: JSONSerialization.data(withJSONObject: raw))
    }
    private func blocked(_ folder: URL, _ action: () throws -> Void) throws {
        let preserved = folder.appendingPathExtension("preserved")
        try FileManager.default.moveItem(at: folder, to: preserved)
        try Data("Synthetic unavailable directory".utf8).write(to: folder)
        defer { try? FileManager.default.removeItem(at: folder); try? FileManager.default.moveItem(at: preserved, to: folder) }
        try action()
    }

    func testGeneratedGraphFiniteOracleUsesExactGridUnitsAndPreservesLegacyRecipes() throws {
        for locale in ["en_US", "ja_JP"] {
            for seed in 0..<8 {
                let value = try exercise(seed: UInt64(seed), locale: locale)
                let graph = try XCTUnwrap(NFGraphConstructionContract.make(exercise: value))
                XCTAssertEqual(value.schemaVersion, 4); XCTAssertEqual(value.generatorVersion, 7)
                XCTAssertTrue(value.id.contains(".r7.")); XCTAssertNil(value.contractMetadata?.editorialDemand)
                XCTAssertEqual(value.contractMetadata?.familyID, NFGraphConstructionContract.activityID)
                XCTAssertEqual(value.independentRepresentations, [graph.table])
                XCTAssertEqual(graph.responseSchema?.initialState, ["x": "1", "y": String(graph.baseline.y)])
                XCTAssertNil(graph.point(from: .initialDraft(for: value)), "The public given point must not prefill the learner's response.")
                guard case let .table(headers, rows, _) = graph.table else { return XCTFail("Expected the actual source table") }
                XCTAssertEqual(headers, [graph.xTitle, graph.yTitle]); XCTAssertEqual(rows, [["1", String(graph.baseline.y)]])
                XCTAssertTrue(headers[0].contains("s")); XCTAssertTrue(headers[1].contains("m"))
                var accepted: [NFGraphConstructionContract.Point] = []
                for x in 0...6 { for y in 0...50 {
                    let point = NFGraphConstructionContract.Point(x: x, y: y)
                    let result = NFExerciseScoringEngine.score(point.response, for: value)
                    let correct = x == graph.targetX && y == graph.baseline.y * graph.targetX
                    XCTAssertEqual(result.isCorrect, correct)
                    XCTAssertEqual(result.credit, correct ? 1 : 0, "Copying only the given time coordinate cannot earn partial correctness")
                    if result.isCorrect { accepted.append(point) }
                } }
                XCTAssertEqual(accepted, [.init(x: graph.targetX, y: graph.baseline.y * graph.targetX)])
                let alternate = NFExerciseResponse.logicState(.init(finalState: ["x": "\(graph.targetX * 2)/2", "y": "\(graph.baseline.y * graph.targetX).0"], violatedRuleID: nil))
                XCTAssertTrue(NFExerciseScoringEngine.score(alternate, for: value).isCorrect)
                XCTAssertEqual(graph.point(from: alternate), accepted.first)
                let legacy = try exercise(seed: UInt64(seed), locale: locale, policy: nil)
                let omitted = try NFFallbackExerciseGenerator.generate(.init(seed: UInt64(seed), index: 0, lab: .quantitative,
                    purpose: .practice, localeIdentifier: locale, preferredAssessmentMechanicID: NFGraphConstructionContract.mechanicID))
                XCTAssertEqual(try NFImmutableAttemptRecordSnapshot.encoded(legacy), try NFImmutableAttemptRecordSnapshot.encoded(omitted))
                XCTAssertEqual(legacy.schemaVersion, 2); XCTAssertEqual(legacy.generatorVersion, 4)
                XCTAssertNil(legacy.contractMetadata?.graphConstruction); XCTAssertFalse(legacy.id.contains(".r7."))
                XCTAssertNotEqual(legacy.id, value.id)
            }
        }
    }

    func testBoundedUndoPreservesExactTypedPredecessorAndCannotEditAfterCommit() throws {
        let (store, container) = try self.store(); defer { _ = container }
        let value = try exercise(), runtime = try self.runtime(value, store: store)
        let identity = try XCTUnwrap(runtime.graphInputIdentity)
        let graph = try XCTUnwrap(runtime.graphConstruction)
        let blank = runtime.graphResponse
        var history = NFGraphConstructionEditHistory()
        let origin = NFGraphConstructionContract.Point(x: 0, y: 0).response
        XCTAssertTrue(runtime.setGraphResponse(origin, expectedInputIdentity: identity))
        history.record(previous: blank, next: origin)
        let correct = try XCTUnwrap(graph.expectedPoint).response
        XCTAssertTrue(runtime.setGraphResponse(correct, expectedInputIdentity: identity))
        history.record(previous: origin, next: correct)
        XCTAssertEqual(history.edits.count, 2)
        let undo = try XCTUnwrap(history.undo(current: runtime.graphResponse))
        XCTAssertEqual(undo, origin)
        XCTAssertTrue(runtime.setGraphResponse(undo, expectedInputIdentity: identity))
        let undoBlank = try XCTUnwrap(history.undo(current: runtime.graphResponse))
        XCTAssertEqual(undoBlank, blank)
        XCTAssertTrue(runtime.setGraphResponse(undoBlank, expectedInputIdentity: identity))
        XCTAssertNil(graph.point(from: runtime.graphResponse))
        XCTAssertTrue(runtime.checkpointDraft(store: store))
        XCTAssertEqual(store.localSessions.archive.sessions.first?.checkpoint.response, blank)
        var prior = blank
        for index in 0..<60 {
            let next = NFGraphConstructionContract.Point(x: index % 7, y: index % 51).response
            history.record(previous: prior, next: next); prior = next
        }
        XCTAssertEqual(history.edits.count, 50)
        history.synchronize(current: blank); XCTAssertTrue(history.edits.isEmpty)
        XCTAssertTrue(runtime.setGraphResponse(correct, expectedInputIdentity: identity))
        runtime.submitInline(store: store)
        XCTAssertEqual(runtime.stage, .feedback)
        let attempt = try XCTUnwrap(store.attempts.first)
        let original = try NFImmutableAttemptRecordSnapshot.encoded(NFImmutableAttemptRecordSnapshot(attempt))
        XCTAssertFalse(runtime.setGraphResponse(blank, expectedInputIdentity: identity))
        XCTAssertEqual(try NFImmutableAttemptRecordSnapshot.encoded(NFImmutableAttemptRecordSnapshot(attempt)), original)
        XCTAssertEqual(runtime.graphResponse, correct)
        runtime.releaseWriter()
    }

    func testEveryPointerAndKeyboardGridAnswerSerializesIdenticallyAtDifferentDisplaySizes() throws {
        let graph = try XCTUnwrap(NFGraphConstructionContract.make(exercise: exercise()))
        for x in 0...6 { for y in 0...50 {
            let desired = NFGraphConstructionContract.Point(x: x, y: y)
            var keyboard: NFGraphConstructionContract.Point? = nil
            for _ in 0..<x { keyboard = graph.adjusted(keyboard, axis: .x, delta: 1) }
            for _ in 0..<y { keyboard = graph.adjusted(keyboard, axis: .y, delta: 1) }
            keyboard = keyboard ?? .init(x: 0, y: 0)
            XCTAssertEqual(keyboard, desired)
            for width in [180.0, 390.0, 1_400.0] {
                let height = width * 0.7
                let pointerX = Double(x) * width / 6, pointerY = Double(y) * height / 50
                let pointer = try XCTUnwrap(graph.snapped(normalizedX: pointerX / width, normalizedY: pointerY / height))
                XCTAssertEqual(pointer, desired)
                XCTAssertEqual(try NFImmutableAttemptRecordSnapshot.encoded(pointer.response), try NFImmutableAttemptRecordSnapshot.encoded(try XCTUnwrap(keyboard).response))
            }
        } }
        XCTAssertNil(graph.snapped(normalizedX: .nan, normalizedY: 0.5))
        XCTAssertNil(graph.snapped(normalizedX: 0.5, normalizedY: .infinity))
        XCTAssertNil(graph.adjusted(.init(x: Int.max, y: 0), axis: .x, delta: 1))
        XCTAssertNil(graph.adjusted(nil, axis: .x, delta: Int.max))
        XCTAssertEqual(graph.snapped(normalizedX: -1e300, normalizedY: 1e300), .init(x: 0, y: 50))
        XCTAssertEqual(graph.adjusted(.init(x: 6, y: 50), axis: .y, delta: 1), .init(x: 6, y: 50))
    }

    func testOrdinaryGraphDraftSurvivesColdRestoreAndFailedCommitWithoutChangingOriginalReceipt() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "NFGraphRecovery-\(UUID())")
        defer { try? FileManager.default.removeItem(at: folder) }
        let owner = UUID(), url = folder.appending(path: "local.json")
        let repository = NFLocalSessionRepository(url: url, ownerDeviceID: owner)
        let (store, container) = try self.store(repository); defer { _ = container }
        let value = try exercise(), runtime = try self.runtime(value, store: store)
        let graph = try XCTUnwrap(runtime.graphConstruction), digest = try XCTUnwrap(runtime.graphInputIdentity)
        let response = try XCTUnwrap(graph.expectedPoint)
        XCTAssertTrue(runtime.setGraphPoint(response, expectedInputIdentity: digest))
        XCTAssertTrue(runtime.checkpointDraft(store: store))
        let run = try XCTUnwrap(repository.archive.sessions.first)
        XCTAssertEqual(run.checkpoint.response, response.response)
        runtime.releaseWriter()
        let reopened = NFLocalSessionRepository(url: url, ownerDeviceID: owner)
        let (coldStore, coldContainer) = try self.store(reopened); defer { _ = coldContainer }
        var request = run.request; request.localSessionID = run.id; request.localCheckpoint = run.checkpoint; request.freshlyAcceptedLaunch = false
        let cold = NFUniversalSessionRuntime(request: request)
        XCTAssertTrue(cold.checkpointDraft(store: coldStore)); cold.resume(); cold.acknowledgePresented()
        XCTAssertEqual(cold.graphResponse, response.response)
        try blocked(folder) {
            cold.submitInline(store: coldStore)
            XCTAssertNotNil(cold.saveError); XCTAssertTrue(coldStore.attempts.isEmpty)
            XCTAssertEqual(cold.graphResponse, response.response)
        }
        cold.retrySaving(store: coldStore)
        XCTAssertEqual(cold.stage, .feedback); XCTAssertEqual(coldStore.attempts.count, 1)
        let attempt = try XCTUnwrap(coldStore.attempts.first)
        XCTAssertEqual(NFResponsePresentation.decode(attempt.response), response.response)
        XCTAssertEqual(attempt.deterministicCredit, 1); XCTAssertEqual(attempt.hintCount, 0)
        let original = try NFImmutableAttemptRecordSnapshot.encoded(NFImmutableAttemptRecordSnapshot(attempt))
        XCTAssertFalse(cold.setGraphPoint(.init(x: 0, y: 0), expectedInputIdentity: digest), "A late pointer update after submit cannot alter the frozen answer")
        cold.retrySaving(store: coldStore)
        XCTAssertEqual(coldStore.attempts.count, 1)
        XCTAssertEqual(try NFImmutableAttemptRecordSnapshot.encoded(NFImmutableAttemptRecordSnapshot(attempt)), original)
        let snapshot = try XCTUnwrap(reopened.archive.snapshots.first { $0.attemptID == attempt.id })
        XCTAssertEqual(snapshot.exercise.contractMetadata?.graphConstruction, graph)
        let history = try XCTUnwrap(NFGraphConstructionHistoryProjection.make(exercise: snapshot.exercise, response: NFResponsePresentation.decode(attempt.response), isProtected: false))
        XCTAssertEqual(history.savedPoint, response)
        XCTAssertTrue(NFResponsePresentation.text(attempt.response, exercise: snapshot.exercise).contains(graph.xTitle))
        cold.releaseWriter()
    }

    func testGraphRecipeAndNestedSchemaMustBothMatchOnRecoveryAndProtectedAdmission() throws {
        let value = try exercise()
        for purpose in [NFExercisePurpose.baseline, .assessmentHoldout, .nearTransfer, .retention] {
            XCTAssertThrowsError(try exercise(purpose: purpose))
        }
        XCTAssertThrowsError(try exercise(policy: 999))
        XCTAssertThrowsError(try NFFallbackExerciseGenerator.generate(.init(seed: 714, index: 0, lab: .quantitative,
            purpose: .practice, preferredAssessmentMechanicID: "fixture.fallback-variant-0", graphConstructionPolicyVersion: 1)))
        var invalid = value; invalid.contractMetadata?.graphConstruction?.schemaVersion = 999
        var missing = value; missing.contractMetadata?.graphConstruction = nil
        let inconsistent = try mutated(value, ["assessmentProtected": true])
        for unsupported in [invalid, missing, inconsistent] {
            XCTAssertFalse(unsupported.hasSupportedGraphConstruction)
            XCTAssertThrowsError(try NFExerciseSchemaValidator.validate(unsupported))
            XCTAssertEqual(NFExerciseScoringEngine.score(.initialDraft(for: unsupported), for: unsupported).outcome, .invalidItem)
            XCTAssertNil(NFGraphConstructionHistoryProjection.make(exercise: unsupported, response: .initialDraft(for: unsupported), isProtected: false))
        }
        let (store, container) = try self.store(); defer { _ = container }
        var request = SessionRequest(lab: .quantitative, source: .focused, seed: 714, requestedItemCount: 1,
            isTimed: false, mechanicID: NFGraphConstructionContract.mechanicID)
        let saved = try NFLocalItemCheckpoint.initial(request: request, exercise: value, slotID: UUID(), attemptID: UUID(), at: Date())
        request.localCheckpoint = saved
        XCTAssertFalse(request.permitsGraphConstruction(exercise: value), "A missing producer pin cannot be inferred from a newer item")
        XCTAssertNotNil(NFUniversalSessionRuntime(request: request).unavailableReason)
        request.graphConstructionPolicyVersion = 1
        XCTAssertTrue(request.permitsGraphConstruction(exercise: value))
        var future = saved; future.exercise = invalid; future.exerciseDigest = try NFLocalItemCheckpoint.digest(invalid)
        request.localCheckpoint = future
        XCTAssertFalse(future.hasSupportedGraphConstruction)
        let untouched = try NFImmutableAttemptRecordSnapshot.encoded(future)
        let runtime = NFUniversalSessionRuntime(request: request)
        XCTAssertNotNil(runtime.unavailableReason)
        XCTAssertFalse(runtime.setGraphPoint(.init(x: 0, y: 0), expectedInputIdentity: future.exerciseDigest))
        XCTAssertEqual(try NFImmutableAttemptRecordSnapshot.encoded(future), untouched)
        XCTAssertTrue(store.attempts.isEmpty)
        XCTAssertFalse(request.permitsGraphConstruction(exercise: try exercise(policy: nil)), "An opted-in graph request cannot silently restore an old numeric task")
    }

    func testGraphHistoryKeepsUnplottableOriginalTextAndRefusesProtectedOrMissingAuthority() throws {
        let value = try exercise(), graph = try XCTUnwrap(NFGraphConstructionContract.make(exercise: value))
        let outside = NFExerciseResponse.logicState(.init(finalState: ["x": "-123", "y": "1e300"], violatedRuleID: nil))
        let original = try NFImmutableAttemptRecordSnapshot.encoded(outside)
        let history = try XCTUnwrap(NFGraphConstructionHistoryProjection.make(exercise: value, response: outside, isProtected: false))
        XCTAssertNil(history.savedPoint); XCTAssertEqual(history.response, outside)
        let readable = NFResponsePresentation.text(outside, exercise: value)
        XCTAssertTrue(readable.contains("-123")); XCTAssertTrue(readable.contains("1e300"))
        XCTAssertTrue(readable.contains(graph.xTitle)); XCTAssertTrue(readable.contains(graph.yTitle))
        XCTAssertNil(NFGraphConstructionHistoryProjection.make(exercise: value, response: outside, isProtected: true))
        XCTAssertNil(NFGraphConstructionHistoryProjection.make(exercise: nil, response: outside, isProtected: false))
        XCTAssertNil(NFGraphConstructionHistoryProjection.make(exercise: value, response: nil, isProtected: false))
        XCTAssertEqual(try NFImmutableAttemptRecordSnapshot.encoded(outside), original)
        var raw = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(graph)) as? [String: Any])
        raw["baseline"] = ["x": 1, "y": Int.max]; raw["targetX"] = Int.max
        let malformed = try JSONDecoder().decode(NFGraphConstructionContract.self, from: JSONSerialization.data(withJSONObject: raw))
        XCTAssertFalse(malformed.isSupported); XCTAssertNil(malformed.expectedPoint)
        XCTAssertNil(malformed.snapped(normalizedX: 0.5, normalizedY: 0.5))
    }

    func testExplicitGraphLaunchPinsNewRecipeWhileNormalScalingKeepsItsVariety() throws {
        let activity = try XCTUnwrap(NFDefaultContentCatalog.activity(id: NFGraphConstructionContract.activityID))
        let (ordinaryStore, ordinaryContainer) = try store(); defer { _ = ordinaryContainer }
        XCTAssertTrue(ordinaryStore.beginDefaultCatalogSession(.init(activity: activity, field: .general), requestedItemCount: 1,
            isTimed: false, timingCondition: .init(.untimed)))
        let ordinary = try XCTUnwrap(ordinaryStore.activeSessionRequest)
        XCTAssertNil(ordinary.graphConstructionPolicyVersion)
        XCTAssertNil(ordinary.localCheckpoint?.exercise?.contractMetadata?.graphConstruction)
        let (invalidStore, invalidContainer) = try store(); defer { _ = invalidContainer }
        XCTAssertFalse(invalidStore.beginSession(lab: .mentalMath, source: .focused, requestedItemCount: 1,
            isTimed: false, graphConstructionPolicyVersion: 1))
        XCTAssertNil(invalidStore.activeSessionRequest)
        XCTAssertTrue(invalidStore.localSessions.archive.sessions.isEmpty)
        let (graphStore, graphContainer) = try store(); defer { _ = graphContainer }
        XCTAssertTrue(graphStore.beginDefaultCatalogSession(.init(activity: activity, field: .general), requestedItemCount: 1,
            isTimed: false, timingCondition: .init(.untimed), graphConstructionPolicyVersion: 1))
        let request = try XCTUnwrap(graphStore.activeSessionRequest)
        XCTAssertEqual(request.graphConstructionPolicyVersion, 1)
        XCTAssertEqual(request.launchOnly().graphConstructionPolicyVersion, 1)
        let retained = try XCTUnwrap(request.localCheckpoint?.exercise)
        XCTAssertNotNil(NFGraphConstructionContract.make(exercise: retained))
        XCTAssertEqual(retained.generatorVersion, 7); XCTAssertTrue(retained.id.contains(".r7."))
        XCTAssertNil(request.ordinaryDelivery, "A focused mechanic uses its fixed family reservation, not mixed-bank adaptive delivery.")
        XCTAssertNotNil(request.offlineRotationPlan)
        XCTAssertEqual(graphStore.localSessions.archive.fixedLaunchReceipts?.count, 1)
        XCTAssertEqual(graphStore.localSessions.archive.sessions.first?.checkpoint.exercise, retained)
        XCTAssertTrue(request.permitsGraphConstruction(exercise: retained))
        XCTAssertEqual(request.timingCondition?.mode, .untimed)
        let legacySlugs = try Set((0..<64).map { try exercise(seed: UInt64($0), policy: nil).templateID.split(separator: ".").suffix(2).joined(separator: ".") })
        XCTAssertEqual(legacySlugs, ["scaling.direct", "scaling.inverse", "scaling.power-law"])
    }

    func testGeneratedGraphAdapterColdRestoresExactPointAndRejectsLateInputAfterNext() throws {
        let (store, container) = try self.store(); defer { _ = container }
        let id = UUID()
        let request = NFAuthoringRequest(id: id, capability: .contextualize, lab: .quantitative, field: .general,
            customTopic: "Synthetic distance graph", learningObjective: "Place a direct-proportion point",
            style: .dataInterpretation, difficulty: 0.4, count: 2, localeIdentifier: "en", seed: 714, aiMode: .disabled)
        let questions = try [714, 715].map { seed -> NFAuthoredQuestion in
            let value = try exercise(seed: UInt64(seed), purpose: .documentPractice)
            guard case let .logicState(schema) = value.interaction else { throw CocoaError(.coderInvalidValue) }
            let question = NFAuthoredQuestion(id: value.id, lab: value.lab, style: .dataInterpretation,
                prompt: value.prompt, context: value.contextText ?? "", choices: [],
                correctAnswer: schema.expectedFinalState.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: ","),
                acceptedAnswers: [], explanation: value.feedback.correctExplanation, hint: value.feedback.hintLadder[0],
                decisiveStep: value.feedback.decisiveStep, difficulty: 0.4, citationChunkIDs: [], evidenceClass: .documentPractice,
                authoritativeExercise: value)
            XCTAssertTrue(NFAuthoredExerciseAuthority.validatesBinding(question)); return question
        }
        let result = NFAuthoringResult(questions: questions, provenance: .init(requestID: id, generatedAt: Date().addingTimeInterval(-1),
            route: .deterministicFallback, routeReason: "Synthetic graph fixture", promptVersion: 1, modelIdentifier: "synthetic.graph",
            sourceChunkIDs: [], sourceDocumentIDs: [], validationVersion: 1, repairCount: 0, cacheKey: "synthetic.graph", isFallback: true),
            routeCandidates: [], validationStatus: .init(level: .deterministicKey, sourceSupport: .notApplicable), validationNotes: [])
        let runtime = AIGeneratedPracticeRuntime(result: result, request: request)
        XCTAssertTrue(runtime.checkpoint(store: store)); runtime.resume()
        let firstIdentity = try XCTUnwrap(runtime.graphInputIdentity)
        let point = try XCTUnwrap(runtime.graphConstruction?.expectedPoint)
        XCTAssertTrue(runtime.setGraphPoint(point, expectedInputIdentity: firstIdentity)); XCTAssertTrue(runtime.checkpoint(store: store))
        let draft = try XCTUnwrap(store.generatedPracticeDraft(for: id)); XCTAssertTrue(draft.valid)
        XCTAssertEqual(draft.response, point.response); runtime.releaseWriter()
        let cold = AIGeneratedPracticeRuntime(result: result, request: request, draft: draft)
        XCTAssertTrue(cold.restoreCheckpoint(store: store)); cold.resume()
        XCTAssertEqual(cold.graphResponse, point.response)
        cold.submit(store: store)
        XCTAssertEqual(cold.stage, 2); XCTAssertEqual(cold.lastScore?.credit, 1); XCTAssertEqual(store.attempts.count, 1)
        let original = try NFImmutableAttemptRecordSnapshot.encoded(NFImmutableAttemptRecordSnapshot(try XCTUnwrap(store.attempts.first)))
        XCTAssertFalse(cold.setGraphPoint(.init(x: 0, y: 0), expectedInputIdentity: firstIdentity))
        cold.next(store: store)
        XCTAssertEqual(cold.index, 1); XCTAssertNotEqual(cold.graphInputIdentity, firstIdentity)
        XCTAssertNil(cold.graphConstruction?.point(from: cold.graphResponse))
        XCTAssertFalse(cold.setGraphPoint(point, expectedInputIdentity: firstIdentity), "An old graph gesture cannot attach to the next item")
        XCTAssertEqual(try NFImmutableAttemptRecordSnapshot.encoded(NFImmutableAttemptRecordSnapshot(try XCTUnwrap(store.attempts.first))), original)
        cold.releaseWriter()
    }
}


@MainActor
final class RetrievalAuthoritySuccessorTests: XCTestCase {
    private func store() throws -> (AppStore, ModelContainer) {
        let container = try ModelContainer(for: Schema(NFSchemaV1.models), configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        var draft = OnboardingDraft(); draft.aiMode = .disabled
        container.mainContext.insert(UserProfileRecord(draft: draft)); try container.mainContext.save()
        return (AppStore(context: container.mainContext, localSessionRepository: NFLocalSessionRepository(),
            allowsSharedWidgetPublishing: false), container)
    }
    private func selected(_ suffix: String) throws -> NFRetrievalKnowledgeTarget {
        try XCTUnwrap(NFBundledRetrievalCatalog.targets.first { $0.id.hasSuffix(suffix) })
    }
    // Match only the documented deterministic selection algorithm, then exercise
    // the real generator once. Correctness below uses explicit finite oracles.
    private func exercise(_ target: NFRetrievalKnowledgeTarget, policy: Int? = 1, variant: Int = 1, locale: String = "en_US") throws -> NFExercise {
        let ordinal = try XCTUnwrap(NFBundledRetrievalCatalog.targets.firstIndex { $0.id == target.id })
        let mechanic = "fixture.fallback-variant-\(variant)"
        func selection(_ seed: UInt64) -> Int {
            let text = "\(seed):0:\(TrainingLab.retrieval.rawValue):\(NFExercisePurpose.practice.rawValue):automatic:\(mechanic):no-transfer-brief:4"
            var hash: UInt64 = 0xcbf29ce484222325
            for byte in text.utf8 { hash = (hash ^ UInt64(byte)) &* 0x100000001b3 }
            var state = seed ^ hash
            if state == 0 { state = 0x9E3779B97F4A7C15 }
            state &+= 0x9E3779B97F4A7C15
            var value = (state ^ (state >> 30)) &* 0xBF58476D1CE4E5B9
            value = (value ^ (value >> 27)) &* 0x94D049BB133111EB
            return Int((value ^ (value >> 31)) % UInt64(NFBundledRetrievalCatalog.targets.count))
        }
        let seed = try XCTUnwrap((UInt64(0)..<100_000).first { selection($0) == ordinal })
        let value = try NFFallbackExerciseGenerator.generate(.init(seed: seed, index: 0, lab: .retrieval,
            purpose: .practice, localeIdentifier: locale, preferredAssessmentMechanicID: mechanic,
            retrievalAuthorityPolicyVersion: policy))
        if !value.tags.contains("learning-method-only") { XCTAssertTrue(value.tags.contains("knowledge-target." + target.id)) }
        return value
    }
    private func modified(_ exercise: NFExercise, _ values: [String: Any]) throws -> NFExercise {
        var raw = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(exercise)) as? [String: Any])
        raw.merge(values) { _, new in new }
        return try JSONDecoder().decode(NFExercise.self, from: JSONSerialization.data(withJSONObject: raw))
    }
    private func evidence(_ value: NFExercise, response: String, credit: Double) throws -> NFHistoricalContentCorrectionInput {
        var input = NFHistoricalContentCorrectionInput(attemptID: UUID().uuidString, itemID: value.id,
            templateID: value.templateID, originalScoringVersion: 8, prompt: value.prompt,
            rawResponse: String(decoding: try JSONEncoder().encode(NFExerciseResponse.shortText(response)), as: UTF8.self),
            originalExpectedAnswer: NFRetrievalResponseAuthority.target(in: value)?.answer ?? "",
            originalIsCorrect: credit == 1, originalCredit: credit)
        input.responseFormatRaw = "shortText"; input.generatorVersion = value.generatorVersion
        input.exactSnapshot = value; input.snapshotVerifiedAsOriginal = true
        return input
    }

    func testMatrixContractPreservesRolesOrderCaseAndScalarEquivalenceThroughActualScorer() throws {
        let target = try selected(".eigenvector-definition")
        for policy in [nil, 1] as [Int?] {
            let value = try exercise(target, policy: policy)
            XCTAssertEqual(value.schemaVersion, policy == nil ? 2 : 6)
            XCTAssertEqual(value.generatorVersion, policy == nil ? 4 : 9)
            XCTAssertEqual(value.id.contains(".r9."), policy != nil)
            let raw = try NFImmutableAttemptRecordSnapshot.encoded(value)
            for correct in ["Av equals lambda v", "A v = λ v", "A times v equals lambda times v", "(A*v)=(v*lambda)", "lambda*v=A*v"] {
                XCTAssertEqual(NFExerciseScoringEngine.score(.shortText(correct), for: value).outcome, .correct, correct)
            }
            for wrong in ["av equals lambda v", "AV=lambda*V", "v*A=lambda*v", "A*v=lambda*A"] {
                XCTAssertEqual(NFExerciseScoringEngine.score(.shortText(wrong), for: value).outcome, .incorrect, wrong)
            }
            for unknown in ["A*v=lambda*v provided that the vector is nonzero", "A/v=lambda", "A*v=λ*v; delete()"] {
                let result = NFExerciseScoringEngine.score(.shortText(unknown), for: value)
                XCTAssertEqual(result.outcome, .needsClarification); XCTAssertNil(result.objectiveCorrectness)
            }
            XCTAssertEqual(try NFImmutableAttemptRecordSnapshot.encoded(value), raw)
        }
    }

    func testBinaryDirectionsUseDifferentTypedAuthoritiesAndExactFiniteOracles() throws {
        let decimal = try selected(".binary-to-decimal-10010"), binary = try selected(".decimal-to-binary-33")
        XCTAssertEqual(decimal.answer, "18"); XCTAssertEqual(binary.answer, "100001")
        for policy in [nil, 1] as [Int?] {
            let numeric = try exercise(decimal, policy: policy), numeral = try exercise(binary, policy: policy)
            for text in ["18", "18.0", "36/2", "1.8e1"] { XCTAssertEqual(NFExerciseScoringEngine.score(.shortText(text), for: numeric).outcome, .correct) }
            for number in 0...40 { XCTAssertEqual(NFExerciseScoringEngine.score(.shortText(String(number)), for: numeric).isCorrect, number == 18) }
            for text in ["100001", "000100001"] { XCTAssertEqual(NFExerciseScoringEngine.score(.shortText(text), for: numeral).outcome, .correct) }
            for number in 0...40 {
                XCTAssertEqual(NFExerciseScoringEngine.score(.shortText(String(number, radix: 2)), for: numeral).isCorrect, number == 33)
            }
            for text in ["33", "100001.0", "1.00001e5", "100001/1", "0b100001"] {
                XCTAssertEqual(NFExerciseScoringEngine.score(.shortText(text), for: numeral).outcome, .needsClarification)
            }
        }
    }

    func testAuthoritiesRequireExactBundledIdentityAndUnknownNestedPoliciesFailClosed() throws {
        let target = try selected(".eigenvector-definition")
        let original = NFExerciseGroundingFact(id: target.id, statement: target.prompt, expectedAnswer: target.answer,
            acceptedAlternatives: target.acceptedAnswers, citationIDs: [])
        XCTAssertNotNil(NFRetrievalResponseAuthority.successorAuthority(for: original))
        for fact in [
            NFExerciseGroundingFact(id: "source.eigenvector-definition", statement: target.prompt, expectedAnswer: target.answer, acceptedAlternatives: target.acceptedAnswers, citationIDs: []),
            NFExerciseGroundingFact(id: target.id, statement: "Use lowercase a as the matrix symbol.", expectedAnswer: target.answer, acceptedAlternatives: target.acceptedAnswers, citationIDs: []),
            NFExerciseGroundingFact(id: target.id, statement: target.prompt, expectedAnswer: "av equals lambda v", acceptedAlternatives: target.acceptedAnswers, citationIDs: [])
        ] { XCTAssertNil(NFRetrievalResponseAuthority.successorAuthority(for: fact)) }
        var future = NFMatrixEigenvectorEquationAuthority.contract; future.policyVersion = 999
        XCTAssertEqual(NFRestrictedSymbolicAuthority.compare("A*v=lambda*v", contract: future), .unsupported)
        let item = try exercise(target)
        guard case let .shortText(schema) = item.interaction else { return XCTFail("Expected short text") }
        var changed = schema; changed.authority = .symbolic(future)
        XCTAssertThrowsError(try NFExerciseSchemaValidator.validateInteraction(.shortText(changed)))
        for values in [["schemaVersion": 999], ["generatorVersion": 4]] {
            XCTAssertEqual(NFExerciseScoringEngine.score(.shortText(target.answer), for: try modified(item, values)).outcome, .invalidItem)
        }
        var metadata = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(item.contractMetadata)) as? [String: Any])
        metadata.removeValue(forKey: "retrievalAuthorityPolicyVersion")
        XCTAssertEqual(NFExerciseScoringEngine.score(.shortText(target.answer), for: try modified(item, ["contractMetadata": metadata])).outcome, .invalidItem)
        let legacy = try exercise(target, policy: nil)
        let foreign = try modified(legacy, ["tags": ["knowledge-target.source.eigenvector-definition"]])
        XCTAssertNil(NFRetrievalResponseAuthority.legacySuccessorTarget(in: foreign), "Similar prose cannot confer the bundled compatibility rule")
    }

    func testUnrelatedCaseInsensitiveProseAndDeclaredScalarSymbolsAreNotReinterpreted() throws {
        let target = try selected(".si-time-unit")
        let old = try exercise(target, policy: nil)
        XCTAssertNil(NFRetrievalResponseAuthority.legacySuccessorTarget(in: old))
        XCTAssertEqual(NFExerciseScoringEngine.score(.shortText("SECOND"), for: old).outcome, .correct)
        let contract = NFSymbolicAnswerContract(acceptedExpressions: ["F(b)-F(a)"], variables: ["a", "b"], functions: ["F", "f"])
        XCTAssertEqual(NFRestrictedSymbolicAuthority.compare("F(b)-F(a)", contract: contract), .equivalent)
        XCTAssertEqual(NFRestrictedSymbolicAuthority.compare("f(b)-f(a)", contract: contract), .different)
        XCTAssertThrowsError(try NFFallbackExerciseGenerator.generate(.init(seed: 1, index: 0, lab: .retrieval,
            purpose: .practice, retrievalAuthorityPolicyVersion: 999)))
        XCTAssertThrowsError(try NFFallbackExerciseGenerator.generate(.init(seed: 1, index: 0, lab: .retrieval,
            purpose: .baseline, retrievalAuthorityPolicyVersion: 1)))
        let plain = try NFFallbackExerciseGenerator.generate(.init(seed: 2, index: 0, lab: .retrieval, purpose: .practice))
        let explicitLegacy = try NFFallbackExerciseGenerator.generate(.init(seed: 2, index: 0, lab: .retrieval,
            purpose: .practice, retrievalAuthorityPolicyVersion: nil))
        XCTAssertEqual(try NFImmutableAttemptRecordSnapshot.encoded(plain), try NFImmutableAttemptRecordSnapshot.encoded(explicitLegacy))
        XCTAssertNil(explicitLegacy.contractMetadata?.retrievalAuthorityPolicyVersion)
    }

    func testHistoricalCaseErrorAndNumericEquivalenceAmendOnlyExactOriginalEvidence() throws {
        let matrix = try exercise(selected(".eigenvector-definition"), policy: nil)
        let decimal = try exercise(selected(".binary-to-decimal-10010"), policy: nil)
        for (item, response, oldCredit, expected) in [(matrix, "av equals lambda v", 1.0, 0.0), (matrix, "lambda*v=A*v", 0.0, 1.0), (decimal, "36/2", 0.0, 1.0)] {
            let input = try evidence(item, response: response, credit: oldCredit)
            let raw = try NFImmutableAttemptRecordSnapshot.encoded(input.exactSnapshot)
            let audit = NFContentCorrectionPolicy.audit(input)
            XCTAssertEqual(audit.recommendations.compactMap(\.correctedCredit), [expected])
            XCTAssertEqual(audit, NFContentCorrectionPolicy.audit(input))
            XCTAssertEqual(try NFImmutableAttemptRecordSnapshot.encoded(input.exactSnapshot), raw)
            var absent = input; absent.exactSnapshot = nil
            XCTAssertFalse(NFContentCorrectionPolicy.audit(absent).recommendations.contains { $0.correctedCredit != nil })
            var unverified = input; unverified.snapshotVerifiedAsOriginal = false
            XCTAssertFalse(NFContentCorrectionPolicy.audit(unverified).recommendations.contains { $0.correctedCredit != nil })
        }
        let unknown = NFContentCorrectionPolicy.audit(try evidence(matrix, response: "A*v=lambda*v plus an unstated exception", credit: 1))
        XCTAssertTrue(unknown.recommendations.contains { $0.disposition == .withdrawnDisputedGrade && $0.excludedScopes.contains(.accuracy) })
    }

    func testCurrentScorerWorkflowIsMethodOnlyInActualStoreAndDoesNotScheduleSubjectReview() throws {
        let (store, container) = try store()
        let target = try selected(".eigenvector-definition")
        for policy in [nil, 1] as [Int?] {
            for locale in ["en_US", "ja_JP"] {
                let item = try exercise(target, policy: policy, variant: 5, locale: locale)
                XCTAssertTrue(NFContentCorrectionPolicy.knownWorkflowOnly(item))
                let response = NFExerciseResponse.orderedSteps(stepIDs: ["retrieve", "compare", "locate", "retry"])
                let score = NFExerciseScoringEngine.score(response, for: item)
                let id = UUID()
                try store.saveExerciseAttempt(attemptID: id, sessionID: UUID(), exercise: item, response: response,
                    result: score, confidence: nil, shownAt: Date().addingTimeInterval(-20), activeDuration: 10, source: .focused)
                let record = try XCTUnwrap(store.attempts.first { $0.id == id })
                let original = try NFImmutableAttemptRecordSnapshot.encoded(NFImmutableAttemptRecordSnapshot(record))
                try store.reconcileHistoricalAuthority()
                XCTAssertEqual(store.effectiveAttemptDTO(record).evidenceWeight, 0)
                XCTAssertTrue(store.localSessions.archive.contentCorrections?.contains { $0.originalAttemptID == id.uuidString && $0.disposition == .learningMethodOnly } == true)
                XCTAssertEqual(try NFImmutableAttemptRecordSnapshot.encoded(NFImmutableAttemptRecordSnapshot(record)), original)
                XCTAssertEqual(record.deterministicCredit, 1)
            }
        }
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        XCTAssertTrue(store.retentionReminderOrigins(at: Date().addingTimeInterval(172_800), calendar: calendar).isEmpty)
        XCTAssertEqual(try container.mainContext.fetchCount(FetchDescriptor<AttemptRecord>()), 4)
    }

    func testNewWorkflowSemanticIdentityDoesNotBorrowUnrelatedTargetsOrCitations() throws {
        let first = try selected(".eigenvector-definition"), second = try selected(".binary-to-decimal-10010")
        for variant in [5, 8] {
            let a = try exercise(first, variant: variant), b = try exercise(second, variant: variant, locale: "ja_JP")
            XCTAssertEqual(NFQuestionFingerprint.fingerprint(for: a), NFQuestionFingerprint.fingerprint(for: b))
            XCTAssertTrue(a.tags.contains("learning-method-only")); XCTAssertFalse(a.tags.contains { $0.hasPrefix("knowledge-target.") })
            XCTAssertFalse(a.prompt.contains(first.prompt)); XCTAssertTrue(a.citations.isEmpty)
            XCTAssertTrue(a.contractMetadata?.objectiveID.hasPrefix("learning-method.") == true)
            XCTAssertNil(a.contractMetadata?.editorialDemand)
        }
        let old = try exercise(first, policy: nil, variant: 5)
        guard case let .orderedSteps(schema) = old.interaction else { return XCTFail("Expected method steps") }
        let changedSchema = NFOrderedStepsResponseSchema(steps: schema.steps.map {
            NFOrderedStep(id: $0.id, text: $0.id == "retrieve" ? "Retrieve the sample from the refrigerated container." : $0.text)
        }, correctOrder: schema.correctOrder)
        let unrelated = try modified(old, ["interaction": JSONSerialization.jsonObject(with: JSONEncoder().encode(NFExerciseInteraction.orderedSteps(changedSchema)))])
        XCTAssertFalse(NFContentCorrectionPolicy.knownWorkflowOnly(unrelated))
        for seed in 0..<24 {
            let mixed = try NFFallbackExerciseGenerator.generate(.init(seed: UInt64(seed), index: 0, lab: .retrieval,
                purpose: .practice, retrievalAuthorityPolicyVersion: 1))
            XCTAssertFalse(NFContentCorrectionPolicy.knownWorkflowOnly(mixed))
            XCTAssertTrue(mixed.tags.contains { $0.hasPrefix("knowledge-target.") })
        }
    }

    func testLegacyRecordedWrongMatrixGradeGetsStoreAmendmentWithoutResponseOrXPRewrite() throws {
        let (store, container) = try store()
        let item = try exercise(selected(".eigenvector-definition"), policy: nil)
        let response = NFExerciseResponse.shortText("av equals lambda v")
        let record = AttemptRecord(sessionID: UUID(), lab: .retrieval, itemID: item.id, prompt: item.prompt,
            response: String(decoding: try JSONEncoder().encode(response), as: UTF8.self), correctAnswer: "Av equals lambda v",
            isCorrect: true, confidence: .certain, evidenceClass: .practice, source: .focused)
        record.templateID = item.templateID; record.responseFormatRaw = "shortText"; record.scoringVersion = 8; record.deterministicCredit = 1
        container.mainContext.insert(record); try container.mainContext.save()
        try store.localSessions.retainSnapshot(attemptID: record.id, exercise: item)
        let original = try NFImmutableAttemptRecordSnapshot.encoded(NFImmutableAttemptRecordSnapshot(record))
        store.reload(); try store.reconcileHistoricalAuthority()
        XCTAssertFalse(store.effectiveAttemptDTO(record).correct); XCTAssertEqual(store.effectiveAttemptDTO(record).credit, 0)
        XCTAssertTrue(record.isCorrect); XCTAssertEqual(record.deterministicCredit, 1)
        XCTAssertEqual(try NFImmutableAttemptRecordSnapshot.encoded(NFImmutableAttemptRecordSnapshot(record)), original)
        var request = SessionRequest(lab: .retrieval, source: .focused, seed: item.seed,
            localeIdentifier: item.localeIdentifier, requestedItemCount: 1, isTimed: false, timingCondition: .init(.untimed))
        request.id = record.sessionID; request.localSessionID = record.sessionID
        var checkpoint = try NFLocalItemCheckpoint.initial(request: request, exercise: item, slotID: UUID(), attemptID: record.id, at: record.submittedAt.addingTimeInterval(-1))
        checkpoint.phase = .feedback; checkpoint.response = response; checkpoint.committedAttemptID = record.id
        checkpoint.result = .init(exerciseID: item.id, scoringVersion: 8, isCorrect: true, credit: 1,
            normalizedResponse: "av equals lambda v", errorCode: nil, expectedAnswerSummary: "Av equals lambda v",
            feedback: .init(title: "Original saved result", explanation: "The original session marked this response correct.",
                decisiveStep: nil, strategy: nil, errorCode: nil, isDelayed: false), outcome: .correct)
        request.localCheckpoint = checkpoint
        let recovered = NFUniversalSessionRuntime(request: request)
        XCTAssertNil(recovered.unavailableReason); XCTAssertEqual(recovered.stage, .feedback)
        XCTAssertEqual(recovered.lastResult, checkpoint.result, "An acknowledged receipt is restored exactly; the separate historical amendment does not rescore or rewrite it")
        let firstIDs = store.localSessions.archive.contentCorrections?.map(\.id)
        try store.reconcileHistoricalAuthority(); XCTAssertEqual(store.localSessions.archive.contentCorrections?.map(\.id), firstIDs)
    }

    func testActualNewLaunchPinsRecipeAndColdDraftRestoresBeforeAuditedSubmit() throws {
        let (store, container) = try store()
        defer { withExtendedLifetime(container) {} }
        let activity = try XCTUnwrap(NFDefaultContentCatalog.activities.first { $0.lab == .retrieval && $0.templateSlug == "short-answer" })
        XCTAssertTrue(store.beginSession(lab: .retrieval, source: .focused, requestedItemCount: 5, isTimed: false, mechanicID: activity.mechanicID))
        let request = try XCTUnwrap(store.activeSessionRequest)
        XCTAssertEqual(request.retrievalAuthorityPolicyVersion, 1)
        let retained = try XCTUnwrap(request.localCheckpoint?.exercise)
        XCTAssertEqual(retained.schemaVersion, 6); XCTAssertEqual(retained.generatorVersion, 9)
        XCTAssertEqual(request.launchOnly().retrievalAuthorityPolicyVersion, 1)
        XCTAssertTrue(request.permitsRetrievalAuthority(exercise: retained))
        var old = request; old.retrievalAuthorityPolicyVersion = nil
        XCTAssertFalse(old.permitsRetrievalAuthority(exercise: retained))
        let legacy = try exercise(selected(".eigenvector-definition"), policy: nil)
        XCTAssertFalse(request.permitsRetrievalAuthority(exercise: legacy)); XCTAssertTrue(old.permitsRetrievalAuthority(exercise: legacy))
        var exact = SessionRequest(lab: .retrieval, source: .focused, seed: legacy.seed, localeIdentifier: legacy.localeIdentifier,
            requestedItemCount: 1, isTimed: false, timingCondition: .init(.untimed))
        exact.localCheckpoint = try NFLocalItemCheckpoint.initial(request: exact, exercise: legacy, slotID: UUID(), attemptID: UUID(), at: Date().addingTimeInterval(-1))
        let (coldStore, coldContainer) = try self.store()
        defer { withExtendedLifetime(coldContainer) {} }
        let runtime = NFUniversalSessionRuntime(request: exact)
        XCTAssertTrue(runtime.checkpointDraft(store: coldStore)); runtime.resume(); runtime.acknowledgePresented()
        runtime.shortText = "av equals lambda v"
        XCTAssertTrue(runtime.checkpointDraft(store: coldStore))
        let envelope = try XCTUnwrap(coldStore.localSessions.archive.sessions.first { $0.id == runtime.sessionID })
        runtime.releaseWriter()
        var resume = envelope.request; resume.localCheckpoint = envelope.checkpoint; resume.localSessionID = envelope.id
        let cold = NFUniversalSessionRuntime(request: resume)
        XCTAssertEqual(cold.shortText, "av equals lambda v"); XCTAssertNil(cold.unavailableReason)
        cold.resume(); cold.acknowledgePresented(); cold.submitInline(store: coldStore)
        XCTAssertEqual(cold.lastResult?.outcome, .incorrect)
        XCTAssertEqual(coldStore.attempts.filter { $0.sessionID == runtime.sessionID }.count, 1)
    }
}


@MainActor
final class RetrievalAssetContractTests: XCTestCase {
    private func store() throws -> (AppStore, ModelContainer) {
        let container = try ModelContainer(for: Schema(NFSchemaV1.models), configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        var draft = OnboardingDraft(); draft.aiMode = .disabled
        container.mainContext.insert(UserProfileRecord(draft: draft)); try container.mainContext.save()
        return (AppStore(context: container.mainContext, localSessionRepository: NFLocalSessionRepository(), allowsSharedWidgetPublishing: false), container)
    }
    private func generated(target: NFRetrievalKnowledgeTarget, form: NFRetrievalAssetContract.Form,
                           locale: String = "en_US", purpose: NFExercisePurpose = .practice) throws -> NFExercise {
        let candidates = NFRetrievalAssetCatalog.targets(form: form)
        let targetIndex = try XCTUnwrap(candidates.firstIndex { $0.id == target.id })
        let mechanic = "fixture.fallback-variant-\(form.variant)"
        func index(_ seed: UInt64) -> Int {
            let text = "\(seed):0:\(TrainingLab.retrieval.rawValue):\(purpose.rawValue):automatic:\(mechanic):no-transfer-brief:4"
            var hash: UInt64 = 0xcbf29ce484222325
            for byte in text.utf8 { hash = (hash ^ UInt64(byte)) &* 0x100000001b3 }
            var state = seed ^ hash
            if state == 0 { state = 0x9E3779B97F4A7C15 }
            state &+= 0x9E3779B97F4A7C15
            var value = (state ^ (state >> 30)) &* 0xBF58476D1CE4E5B9
            value = (value ^ (value >> 27)) &* 0x94D049BB133111EB
            return Int((value ^ (value >> 31)) % UInt64(candidates.count))
        }
        let seed = try XCTUnwrap((UInt64(0)..<10_000).first { index($0) == targetIndex })
        return try NFFallbackExerciseGenerator.generate(.init(seed: seed, index: 0, lab: .retrieval, purpose: purpose,
            localeIdentifier: locale, preferredAssessmentMechanicID: mechanic,
            retrievalAuthorityPolicyVersion: 1, retrievalAssetPolicyVersion: 1))
    }
    private func target(_ suffix: String) throws -> NFRetrievalKnowledgeTarget {
        try XCTUnwrap(NFBundledRetrievalCatalog.targets.first { $0.id.hasSuffix(suffix) })
    }
    private func altered(_ original: NFExercise, _ values: [String: Any]) throws -> NFExercise {
        var raw = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(original)) as? [String: Any])
        raw.merge(values) { _, new in new }
        return try JSONDecoder().decode(NFExercise.self, from: JSONSerialization.data(withJSONObject: raw))
    }
    private func numericAnswer(_ exercise: NFExercise) throws -> Int {
        let asset = try XCTUnwrap(NFRetrievalAssetContract.make(exercise: exercise))
        // The oracle reads the actual essential source data, independently of
        // the scorer's answer schema or generator's expectedAnswer field.
        if asset.targetID.contains("three-value-mean-") { return asset.parameters.reduce(0, +) / asset.parameters.count }
        if asset.targetID.contains("slope-") {
            return (asset.parameters[3] - asset.parameters[1]) / (asset.parameters[2] - asset.parameters[0])
        }
        if asset.targetID.contains("rectangle-area-") { return asset.parameters.reduce(1, *) }
        throw CocoaError(.coderInvalidValue)
    }

    func testAllFiniteAssetsMaterializeThroughActualGeneratorAndNumericScorer() throws {
        for form in NFRetrievalAssetContract.Form.allCases {
            for target in NFRetrievalAssetCatalog.targets(form: form) {
                let exercise = try generated(target: target, form: form)
                let asset = try XCTUnwrap(NFRetrievalAssetContract.make(exercise: exercise))
                XCTAssertEqual(asset.targetID, target.id); XCTAssertEqual(asset.sourcePrompt, target.prompt)
                XCTAssertEqual(asset.sourceAnswer, target.answer); XCTAssertEqual(asset.form, form)
                XCTAssertEqual(exercise.schemaVersion, 7); XCTAssertEqual(exercise.generatorVersion, 10)
                XCTAssertTrue(exercise.id.contains(".r10.")); XCTAssertNil(exercise.contractMetadata?.editorialDemand)
                XCTAssertEqual(exercise.independentRepresentations, asset.representations)
                if case .numeric = exercise.interaction {
                    let answer = try numericAnswer(exercise)
                    for candidate in [answer - 1, answer, answer + 1] {
                        let result = NFExerciseScoringEngine.score(.numeric(.init(value: String(candidate), unit: nil)), for: exercise)
                        XCTAssertEqual(result.isCorrect, candidate == answer)
                    }
                    XCTAssertEqual(NFExerciseScoringEngine.score(.numeric(.init(value: "\(answer).0", unit: nil)), for: exercise).outcome, .correct)
                }
            }
        }
    }

    func testCapacityCountsDistinctTargetsAndFormsWithoutInventingBandsOrCrossProducts() throws {
        XCTAssertEqual(NFRetrievalAssetCatalog.targets(form: .cloze).count, 38)
        XCTAssertEqual(NFRetrievalAssetCatalog.targets(form: .equation).count, 30)
        XCTAssertEqual(NFRetrievalAssetCatalog.targets(form: .figure).count, 30)
        let union = Set(NFRetrievalAssetContract.Form.allCases.flatMap { NFRetrievalAssetCatalog.targets(form: $0).map(\.id) })
        XCTAssertEqual(union.count, 38)
        XCTAssertEqual(NFRetrievalAssetCatalog.compatibleRenderings(targetID: try target(".enzyme-active-site").id), [.cloze])
        XCTAssertTrue(NFRetrievalAssetCatalog.compatibleRenderings(targetID: try target(".ohms-law").id).isEmpty)
        XCTAssertEqual(Set(NFRetrievalAssetCatalog.targets(form: .cloze).map(\.field)), Set(STEMField.allCases))
        XCTAssertTrue(NFRetrievalAssetCatalog.targets(form: .figure).allSatisfy { [.general, .mathematics].contains($0.field) })
        XCTAssertNil(NFRetrievalAssetCatalog.asset(targetID: try target(".ohms-law").id, form: .equation, locale: "en_US"))
        let shared = try target(".slope-0-1-4-9")
        let versions = try NFRetrievalAssetContract.Form.allCases.map { try generated(target: shared, form: $0) }
        XCTAssertEqual(Set(versions.map { NFQuestionFingerprint.fingerprint(for: $0) }).count, 1)
        XCTAssertEqual(Set(versions.map(\.id)).count, 3)
    }

    func testClozeAndEquationHaveRealOmissionsAndLanguageEquivalentAnswers() throws {
        let conceptAnswers = [
            (".si-time-unit", "second", "秒"), (".additive-identity", "0", "ゼロ"),
            (".force-si-unit", "newton", "ニュートン"), (".byte-size", "8", "八"),
            (".static-force-equilibrium", "zero", "ゼロベクトル"), (".enzyme-active-site", "active site", "活性部位"),
            (".cation-charge", "positive", "正"), (".feature-definition", "predictor variable", "予測に使う入力変数")
        ]
        for (suffix, english, japanese) in conceptAnswers {
            for locale in ["en_US", "ja_JP"] {
                let value = try generated(target: target(suffix), form: .cloze, locale: locale)
                XCTAssertEqual(NFExerciseScoringEngine.score(.shortText(english), for: value).outcome, .correct, suffix)
                XCTAssertEqual(NFExerciseScoringEngine.score(.shortText(japanese), for: value).outcome, .correct, suffix)
            }
        }
        for locale in ["en_US", "ja_JP"] {
            let cloze = try generated(target: target(".enzyme-active-site"), form: .cloze, locale: locale)
            let asset = try XCTUnwrap(NFRetrievalAssetContract.make(exercise: cloze))
            XCTAssertTrue(cloze.prompt.contains("____")); XCTAssertFalse(cloze.prompt.contains("活性部位"))
            XCTAssertFalse(cloze.prompt.contains("active site")); XCTAssertTrue(cloze.independentRepresentations.isEmpty)
            for answer in ["active site", "活性部位", "活性中心"] {
                XCTAssertEqual(NFExerciseScoringEngine.score(.shortText(answer), for: cloze).outcome, .correct)
            }
            XCTAssertEqual(NFExerciseScoringEngine.score(.shortText("This region has another name outside these examples"), for: cloze).outcome, .needsClarification)
            XCTAssertEqual(asset.localeIdentifier, locale)
            let equation = try generated(target: target(".rectangle-area-3-2"), form: .equation, locale: locale)
            guard case let .equation(latex, spoken) = equation.independentRepresentations.first else { return XCTFail("Missing target equation") }
            XCTAssertTrue(latex.contains("\\square")); XCTAssertTrue(latex.contains("3")); XCTAssertTrue(latex.contains("2"))
            XCTAssertFalse(latex.contains("E_{source}")); XCTAssertFalse(spoken.contains("6"))
            XCTAssertTrue(spoken.contains("3")); XCTAssertTrue(spoken.contains("2"))
            XCTAssertTrue(locale.hasPrefix("ja") ? spoken.contains("平方メートル") : spoken.contains("square metres"))
            for suffix in [".three-value-mean-4", ".slope-0-1-4-9"] {
                let value = try generated(target: target(suffix), form: .equation, locale: locale)
                let contract = try XCTUnwrap(NFRetrievalAssetContract.make(exercise: value))
                guard case let .equation(_, words) = value.representations.first else { return XCTFail("Missing spoken source equation") }
                for given in contract.parameters { XCTAssertTrue(words.contains(String(given))) }
                XCTAssertTrue(locale.hasPrefix("ja") ? words.contains("無次元") : words.contains("unitless"))
            }
            XCTAssertTrue(locale.hasPrefix("ja") ? equation.prompt.contains("空欄") : equation.prompt.contains("missing"))
        }
    }

    func testFiguresRetainActualGeometryOrObservationsAndTheSameAccessibleData() throws {
        for suffix in [".three-value-mean-4", ".slope-0-1-4-9", ".rectangle-area-3-2"] {
            let exercise = try generated(target: target(suffix), form: .figure, locale: "ja_JP")
            let asset = try XCTUnwrap(NFRetrievalAssetContract.make(exercise: exercise)), figure = try XCTUnwrap(asset.figure)
            XCTAssertEqual(exercise.representations, [figure.table])
            XCTAssertTrue(figure.yBounds.contains(0)); XCTAssertTrue(figure.points.allSatisfy { figure.yBounds.contains(Double($0.y)) })
            guard case let .table(headers, rows, summary) = figure.table else { return XCTFail("Expected an exact accessible table") }
            XCTAssertFalse(headers.contains("")); XCTAssertEqual(summary, figure.summary)
            XCTAssertEqual(rows.count, figure.points.count)
            for (row, point) in zip(rows, figure.points) {
                XCTAssertEqual(Array(row.suffix(2)), [String(point.x), String(point.y)])
            }
            if figure.kind == .rectangle { XCTAssertEqual(figure.points.map(\.x), [0, 3, 3, 0]); XCTAssertEqual(figure.points.map(\.y), [0, 0, 2, 2]) }
            if figure.kind == .line { XCTAssertEqual(figure.points.map(\.x), [0, 4]); XCTAssertEqual(figure.points.map(\.y), [1, 9]) }
            if figure.kind == .observations { XCTAssertEqual(figure.points.map(\.y), [4, 8, 12]) }
        }
    }

    func testFutureMissingAlteredAndProtectedAssetContractsFailClosedWithoutMutation() throws {
        let original = try generated(target: target(".slope-0-1-4-9"), form: .figure)
        let bytes = try NFImmutableAttemptRecordSnapshot.encoded(original)
        for mutation in [["schemaVersion": 999], ["generatorVersion": 9], ["assessmentProtected": true], ["lab": TrainingLab.quantitative.rawValue], ["evidenceClass": EvidenceClass.assessmentHoldout.rawValue]] {
            let changed = try altered(original, mutation)
            XCTAssertNil(NFRetrievalAssetContract.make(exercise: changed))
            XCTAssertEqual(NFExerciseScoringEngine.score(.numeric(.init(value: "2", unit: nil)), for: changed).outcome, .invalidItem)
        }
        var metadata = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(original.contractMetadata)) as? [String: Any])
        var asset = try XCTUnwrap(metadata["retrievalAsset"] as? [String: Any]); asset["policyVersion"] = 999
        metadata["retrievalAsset"] = asset
        XCTAssertNil(NFRetrievalAssetContract.make(exercise: try altered(original, ["contractMetadata": metadata])))
        metadata.removeValue(forKey: "retrievalAsset")
        XCTAssertEqual(NFExerciseScoringEngine.score(.numeric(.init(value: "2", unit: nil)), for: try altered(original, ["contractMetadata": metadata])).outcome, .invalidItem)
        let falseTable = NFExerciseRepresentation.table(headers: ["Point", "x", "y"], rows: [["P", "0", "999"], ["Q", "4", "9"]], accessibilitySummary: "Altered coordinates")
        let tampered = try altered(original, ["representations": JSONSerialization.jsonObject(with: JSONEncoder().encode([falseTable]))])
        XCTAssertNil(NFRetrievalAssetContract.make(exercise: tampered))
        XCTAssertTrue(NFHistoryContextProjection.make(exercise: original, hintCount: 0, isProtected: true).representations.isEmpty)
        XCTAssertEqual(try NFImmutableAttemptRecordSnapshot.encoded(original), bytes)
    }

    func testExplicitUnsupportedFieldAndUnknownPolicyDoNotPublishGenericAssetPlaceholders() throws {
        XCTAssertThrowsError(try NFFallbackExerciseGenerator.generate(.init(seed: 1, index: 0, lab: .retrieval, purpose: .practice,
            sourceContext: .init(primaryField: .physics), preferredAssessmentMechanicID: "fixture.fallback-variant-7",
            retrievalAuthorityPolicyVersion: 1, retrievalAssetPolicyVersion: 1)))
        XCTAssertThrowsError(try NFFallbackExerciseGenerator.generate(.init(seed: 1, index: 0, lab: .retrieval, purpose: .practice,
            retrievalAuthorityPolicyVersion: 1, retrievalAssetPolicyVersion: 999)))
        XCTAssertThrowsError(try NFFallbackExerciseGenerator.generate(.init(seed: 1, index: 0, lab: .retrieval, purpose: .practice,
            preferredAssessmentFormat: .numericEntry, preferredAssessmentMechanicID: "fixture.fallback-variant-7",
            retrievalAuthorityPolicyVersion: 1, retrievalAssetPolicyVersion: 1)))
        let (blockedStore, container) = try store(); defer { withExtendedLifetime(container) {} }
        let activity = try XCTUnwrap(NFDefaultContentCatalog.activity(id: "nf.default.retrieval.figure"))
        XCTAssertFalse(blockedStore.beginSession(lab: .retrieval, source: .focused, field: .physics,
            requestedItemCount: 5, isTimed: false, mechanicID: activity.mechanicID))
        XCTAssertNil(blockedStore.activeSessionRequest)
        XCTAssertTrue(blockedStore.localSessions.archive.sessions.isEmpty)
        XCTAssertTrue(blockedStore.localSessions.archive.fixedLaunchReceipts?.isEmpty ?? true)
        let old = try NFFallbackExerciseGenerator.generate(.init(seed: 1, index: 0, lab: .retrieval, purpose: .practice,
            preferredAssessmentMechanicID: "fixture.fallback-variant-6", retrievalAuthorityPolicyVersion: 1))
        XCTAssertEqual(old.generatorVersion, 9); XCTAssertEqual(old.schemaVersion, 6); XCTAssertNil(old.contractMetadata?.retrievalAsset)
        for seed in 0..<32 {
            let mixed = try NFFallbackExerciseGenerator.generate(.init(seed: UInt64(seed), index: 0, lab: .retrieval, purpose: .practice,
                retrievalAuthorityPolicyVersion: 1, retrievalAssetPolicyVersion: 1))
            if NFRetrievalAssetContract.Form.allCases.contains(where: { mixed.templateID.hasSuffix(".v4." + $0.templateSlug) }) {
                XCTAssertNotNil(NFRetrievalAssetContract.make(exercise: mixed))
            }
        }
    }

    func testActualFocusedFigureLaunchAndColdResponseKeepExactGraphHistory() throws {
        let (store, container) = try store(); defer { withExtendedLifetime(container) {} }
        let activity = try XCTUnwrap(NFDefaultContentCatalog.activity(id: "nf.default.retrieval.figure"))
        XCTAssertTrue(store.beginSession(lab: .retrieval, source: .focused, requestedItemCount: 5, isTimed: false, mechanicID: activity.mechanicID))
        let request = try XCTUnwrap(store.activeSessionRequest)
        XCTAssertEqual(request.retrievalAssetPolicyVersion, 1)
        let value = try XCTUnwrap(request.localCheckpoint?.exercise)
        XCTAssertEqual(value.schemaVersion, 7); XCTAssertTrue(request.permitsRetrievalAsset(exercise: value))
        var incompatible = request; incompatible.retrievalAssetPolicyVersion = nil
        XCTAssertFalse(incompatible.permitsRetrievalAsset(exercise: value))
        let runtime = NFUniversalSessionRuntime(request: request)
        XCTAssertTrue(runtime.checkpointDraft(store: store)); runtime.resume(); runtime.acknowledgePresented()
        let answer = try numericAnswer(value); runtime.numericValue = String(answer)
        XCTAssertTrue(runtime.checkpointDraft(store: store)); runtime.releaseWriter()
        let saved = try XCTUnwrap(store.localSessions.archive.sessions.first { $0.id == runtime.sessionID })
        var coldRequest = saved.request; coldRequest.localCheckpoint = saved.checkpoint; coldRequest.localSessionID = saved.id
        let cold = NFUniversalSessionRuntime(request: coldRequest)
        XCTAssertNil(cold.unavailableReason); XCTAssertEqual(cold.numericValue, String(answer))
        XCTAssertEqual(cold.exercise, value); cold.resume(); cold.acknowledgePresented(); cold.submitInline(store: store)
        XCTAssertEqual(cold.lastResult?.outcome, .correct); XCTAssertEqual(store.attempts.count, 1)
        let record = try XCTUnwrap(store.attempts.first), snapshot = try XCTUnwrap(store.exerciseSnapshot(for: record.id))
        XCTAssertEqual(snapshot, value)
        XCTAssertEqual(NFRetrievalAssetContract.make(exercise: snapshot)?.figure, NFRetrievalAssetContract.make(exercise: value)?.figure)
        cold.next(store: store); XCTAssertEqual(cold.index, 1); XCTAssertNotEqual(cold.exercise.id, value.id)
        XCTAssertNotEqual(NFQuestionFingerprint.fingerprint(for: cold.exercise), NFQuestionFingerprint.fingerprint(for: value))
    }
    func testGeneratedAdapterRestoresTheSameRetainedFigureAndTypedResponse() throws {
        let (store, container) = try self.store(); defer { withExtendedLifetime(container) {} }
        let id = UUID()
        let request = NFAuthoringRequest(id: id, capability: .contextualize, lab: .retrieval, field: .general,
            customTopic: "Synthetic reconstruction", learningObjective: "Read the original figure",
            style: .dataInterpretation, difficulty: 0.4, count: 1, localeIdentifier: "en_US", seed: 714, aiMode: .disabled)
        let exercise = try generated(target: target(".rectangle-area-3-2"), form: .figure, purpose: .documentPractice)
        let question = NFAuthoredQuestion(id: exercise.id, lab: exercise.lab, style: .dataInterpretation,
            prompt: exercise.prompt, context: exercise.contextText ?? "", choices: [], correctAnswer: "6",
            acceptedAnswers: [], explanation: exercise.feedback.correctExplanation, hint: exercise.feedback.hintLadder[0],
            decisiveStep: exercise.feedback.decisiveStep, difficulty: 0.4, citationChunkIDs: [], evidenceClass: .documentPractice,
            authoritativeExercise: exercise)
        XCTAssertTrue(NFAuthoredExerciseAuthority.validatesBinding(question))
        let result = NFAuthoringResult(questions: [question], provenance: .init(requestID: id, generatedAt: Date().addingTimeInterval(-1),
            route: .deterministicFallback, routeReason: "Synthetic retained figure", promptVersion: 1, modelIdentifier: "synthetic.figure",
            sourceChunkIDs: [], sourceDocumentIDs: [], validationVersion: 1, repairCount: 0, cacheKey: "synthetic.figure", isFallback: true),
            routeCandidates: [], validationStatus: .init(level: .deterministicKey, sourceSupport: .notApplicable), validationNotes: [])
        let runtime = AIGeneratedPracticeRuntime(result: result, request: request)
        XCTAssertTrue(runtime.checkpoint(store: store)); runtime.resume(); runtime.numericValue = "6.0"
        XCTAssertTrue(runtime.checkpoint(store: store))
        let draft = try XCTUnwrap(store.generatedPracticeDraft(for: id)); XCTAssertTrue(draft.valid)
        runtime.releaseWriter()
        let cold = AIGeneratedPracticeRuntime(result: result, request: request, draft: draft)
        XCTAssertTrue(cold.restoreCheckpoint(store: store)); cold.resume()
        XCTAssertEqual(cold.numericValue, "6.0"); XCTAssertEqual(cold.exercise, exercise)
        XCTAssertEqual(NFRetrievalAssetContract.make(exercise: cold.exercise)?.figure,
            NFRetrievalAssetContract.make(exercise: exercise)?.figure)
        cold.submit(store: store)
        XCTAssertEqual(cold.stage, 2); XCTAssertEqual(cold.lastScore?.outcome, .correct)
        let record = try XCTUnwrap(store.attempts.first)
        XCTAssertEqual(store.exerciseSnapshot(for: record.id), exercise)
        XCTAssertEqual(store.attempts.count, 1)
    }

}


@MainActor
final class SpatialStructureContractTests: XCTestCase {
    private typealias G = NFSpatialStructureGeometry
    private func store() throws -> (AppStore,ModelContainer) {
        let container=try ModelContainer(for:Schema(NFSchemaV1.models),configurations:ModelConfiguration(isStoredInMemoryOnly:true))
        var draft=OnboardingDraft();draft.aiMode = .disabled
        container.mainContext.insert(UserProfileRecord(draft:draft));try container.mainContext.save()
        return (AppStore(context:container.mainContext,localSessionRepository:NFLocalSessionRepository(),allowsSharedWidgetPublishing:false),container)
    }
    private func generated(_ structure:G.Structure,locale:String="en_US",purpose:NFExercisePurpose = .practice) throws -> NFExercise {
        let values=G.structures.filter { $0.variant == structure.variant }
        let target=try XCTUnwrap(values.firstIndex(of:structure)),mechanic="fixture.fallback-variant-\(structure.variant)"
        func selected(_ seed:UInt64) -> Int {
            let discriminator="\(seed):0:\(TrainingLab.spatial.rawValue):\(purpose.rawValue):automatic:\(mechanic):no-transfer-brief:4"
            var hash:UInt64=0xcbf29ce484222325
            for byte in discriminator.utf8 { hash=(hash ^ UInt64(byte)) &* 0x100000001b3 }
            var state=seed ^ hash;if state == 0 { state=0x9E3779B97F4A7C15 };state &+= 0x9E3779B97F4A7C15
            var v=(state ^ (state >> 30)) &* 0xBF58476D1CE4E5B9;v=(v ^ (v >> 27)) &* 0x94D049BB133111EB
            return Int((v ^ (v >> 31)) % UInt64(values.count))
        }
        let seed=try XCTUnwrap((UInt64(0)..<20_000).first { selected($0) == target })
        return try NFFallbackExerciseGenerator.generate(.init(seed:seed,index:0,lab:.spatial,purpose:purpose,
            localeIdentifier:locale,preferredAssessmentMechanicID:mechanic,spatialStructurePolicyVersion:1))
    }
    private func rotationMatrix(_ rotations:[G.Rotation]) -> [[Int]] {
        // Independent row-matrix composition, rather than the production
        // signed-coordinate swap implementation.
        func product(_ a:[[Int]],_ b:[[Int]]) -> [[Int]] {
            (0..<3).map { r in (0..<3).map { c in (0..<3).reduce(0) { $0+a[r][$1]*b[$1][c] } } }
        }
        var result=[[1,0,0],[0,1,0],[0,0,1]]
        for rotation in rotations {
            let turn:[[Int]]
            switch rotation.axis { case .x:turn=[[1,0,0],[0,0,-1],[0,1,0]];case .y:turn=[[0,0,1],[0,1,0],[-1,0,0]];case .z:turn=[[0,-1,0],[1,0,0],[0,0,1]] }
            for _ in 0..<rotation.quarterTurns { result=product(turn,result) }
        }
        return result
    }
    private func apply(_ matrix:[[Int]],_ vector:[Int]) -> [Int] { matrix.map { row in zip(row,vector).reduce(0) { $0+$1.0*$1.1 } } }
    private func determinant(_ m:[[Int]]) -> Int { m[0][0]*(m[1][1]*m[2][2]-m[1][2]*m[2][1])-m[0][1]*(m[1][0]*m[2][2]-m[1][2]*m[2][0])+m[0][2]*(m[1][0]*m[2][1]-m[1][1]*m[2][0]) }
    private func projections(_ cells:[G.Cell]) -> (front:Set<String>,side:Set<String>) {
        (Set(cells.map { "\($0.x),\($0.z)" }),Set(cells.map { "\($0.y),\($0.z)" }))
    }
    private func silhouette(_ heights:[Int]) -> Set<String> { Set(heights.enumerated().flatMap { x,height in (0..<height).map { "\(x),\($0)" } }) }
    private func changed(_ exercise:NFExercise,values:[String:Any]) throws -> NFExercise {
        var raw=try XCTUnwrap(JSONSerialization.jsonObject(with:JSONEncoder().encode(exercise)) as? [String:Any]);raw.merge(values) { _,next in next }
        return try JSONDecoder().decode(NFExercise.self,from:JSONSerialization.data(withJSONObject:raw))
    }

    func testEveryFaceContractHasOnePhysicalKeyAndAllTwentyFourProperOrientations() throws {
        var orientations:Set<String>=["1,0,0,0,1,0,0,0,1"],count=0
        for structure in G.structures {
            guard case let .faces(value)=structure else { continue };count += 1
            let matrix=rotationMatrix(value.rotations)
            XCTAssertEqual(determinant(matrix),1)
            orientations.insert(matrix.flatMap { $0 }.map(String.init).joined(separator:","))
            let destinations=G.Direction.allCases.map { apply(matrix,$0.vector) }
            XCTAssertEqual(Set(destinations.map { $0.map(String.init).joined(separator:",") }).count,6)
            let sourceIndex=try XCTUnwrap(destinations.firstIndex(of:value.query.vector)),expected=G.FaceRotation.labels[sourceIndex]
            XCTAssertEqual(value.correctFace,expected)
            let exercise=try generated(structure)
            XCTAssertEqual(exercise.schemaVersion,8);XCTAssertEqual(exercise.generatorVersion,11);XCTAssertTrue(exercise.id.contains(".r11."))
            XCTAssertEqual(exercise.contractMetadata?.familyID,"nf.default.spatial.object-rotation")
            XCTAssertEqual(exercise.contractMetadata?.semanticFingerprint,NFQuestionFingerprint.fingerprint(for:exercise))
            guard case let .singleChoice(schema)=exercise.interaction else { return XCTFail("Face identity requires a bounded choice") }
            XCTAssertEqual(Set(schema.options.map(\.text)).count,6)
            for label in G.FaceRotation.labels {
                XCTAssertEqual(NFExerciseScoringEngine.score(.singleChoice(optionID:label),for:exercise).isCorrect,label == expected)
            }
        }
        XCTAssertEqual(count,138);XCTAssertEqual(orientations.count,24)
        XCTAssertNotEqual(rotationMatrix([.init(axis:.x,quarterTurns:1),.init(axis:.y,quarterTurns:1)]),rotationMatrix([.init(axis:.y,quarterTurns:1),.init(axis:.x,quarterTurns:1)]))
    }

    func testWorkedEXC102UsesActualLabeledNativeFacesAndNeverReplaysBeforeCommit() throws {
        let structure=try XCTUnwrap(G.structures.first { if case let .faces(v)=$0 { return v.rotations == [.init(axis:.z,quarterTurns:1)] && v.query == .positiveY };return false })
        for locale in ["en_US","ja_JP"] {
            let exercise=try generated(structure,locale:locale),contract=try XCTUnwrap(NFSpatialStructureContract.make(exercise:exercise))
            XCTAssertEqual(NFExerciseScoringEngine.score(.singleChoice(optionID:"A"),for:exercise).outcome,.correct)
            XCTAssertTrue(exercise.prompt.contains("+z"));XCTAssertTrue(exercise.prompt.contains("+90°"));XCTAssertTrue(exercise.prompt.contains("+y"))
            XCTAssertFalse(contract.sourceDescription.contains("Face A ends"));XCTAssertNil(exercise.contractMetadata?.editorialDemand)
            let original=try NFImmutableAttemptRecordSnapshot.encoded(exercise)
            var state=NFSpatialStructureCopyState()
            XCTAssertFalse(state.advance(contract:contract,phase:.independent));XCTAssertTrue(state.rotations(contract:contract,phase:.independent).isEmpty)
            let scene=NFSpatialRealitySceneFactory.makeStructureScene(contract:contract)
            let object=try XCTUnwrap(scene.findEntity(named:"nf.spatial.structure.object"))
            for label in G.FaceRotation.labels { XCTAssertNotNil(scene.findEntity(named:"structure.face-label."+label)) }
            for axis in ["+x","+y","+z"] { XCTAssertNotNil(scene.findEntity(named:"structure.axis-label."+axis)) }
            let face=try XCTUnwrap(scene.findEntity(named:"structure.face.A"));XCTAssertEqual(face.position.x,0.5,accuracy:0.0001)
            scene.orientation=simd_quatf(angle:0.4,axis:[0,1,0]);let camera=scene.orientation.vector
            XCTAssertTrue(state.advance(contract:contract,phase:.committedFeedback))
            NFSpatialRealitySceneFactory.updateStructureScene(scene,contract:contract,rotations:state.rotations(contract:contract,phase:.committedFeedback))
            let final=object.orientation.act(face.position);XCTAssertEqual(final.x,0,accuracy:0.0001);XCTAssertEqual(final.y,0.5,accuracy:0.0001)
            XCTAssertEqual(scene.orientation.vector,camera)
            state.reset();XCTAssertEqual(state.completedRotations,0)
            NFSpatialRealitySceneFactory.updateStructureScene(scene,contract:contract,rotations:state.rotations(contract:contract,phase:.committedFeedback))
            XCTAssertEqual(object.orientation.act(face.position).x,0.5,accuracy:0.0001)
            XCTAssertEqual(try NFImmutableAttemptRecordSnapshot.encoded(exercise),original)
        }
    }

    func testAllOccupiedFootprintsMatchIndependentProjectionAndNativeCellPositions() throws {
        let top=G.structures.compactMap { if case let .top(v)=$0 { return v };return nil }
        XCTAssertEqual(top.count,17);XCTAssertEqual(G.footprints.filter { $0.count == 4 }.count,5);XCTAssertEqual(G.footprints.filter { $0.count == 5 }.count,12)
        XCTAssertEqual(Set(top.map(\.identity)).count,17)
        for value in top {
            XCTAssertTrue(G.permits(value.cells))
            let footprint=Set(value.cells.map { "\($0.x),\($0.y)" })
            let correct=value.choices.indices.filter { Set(value.choices[$0].map { "\($0.x),\($0.y)" }) == footprint }
            XCTAssertEqual(correct.count,1);XCTAssertEqual(correct,value.correctIndices)
            let exercise=try generated(.top(value)),contract=try XCTUnwrap(NFSpatialStructureContract.make(exercise:exercise))
            for index in value.choices.indices { XCTAssertEqual(NFExerciseScoringEngine.score(.singleChoice(optionID:NFSpatialStructureContract.choiceID(index)),for:exercise).isCorrect,correct.contains(index)) }
            let scene=NFSpatialRealitySceneFactory.makeStructureScene(contract:contract)
            for cell in value.cells {
                let cube=try XCTUnwrap(scene.findEntity(named:"structure.cell."+cell.token))
                XCTAssertEqual(cube.position.x,Float(cell.x)+0.5);XCTAssertEqual(cube.position.y,Float(cell.z)+0.5);XCTAssertEqual(cube.position.z,-Float(cell.y)-0.5)
            }
            let flattened=G.TopView(cells:value.cells.filter { $0.z == 0 },choices:value.choices)
            XCTAssertEqual(flattened.identity,value.identity,"Irrelevant height cannot invent a fresh top-footprint target")
        }
    }

    func testTwoViewQuestionsAcceptEveryValidProposalAndRejectEveryIncompleteOrExtraSet() throws {
        var counts:Set<Int>=[];var cases=0
        for structure in G.structures {
            guard case let .views(value)=structure else { continue };cases += 1
            let front=silhouette(value.frontHeights),side=silhouette(value.sideHeights)
            let correct=Set(value.candidates.indices.filter { let p=projections(value.candidates[$0]);return p.front == front && p.side == side })
            XCTAssertEqual(correct,Set(value.correctIndices));XCTAssertTrue(correct.count > 1);counts.insert(correct.count)
            let exercise=try generated(structure,locale:"ja_JP")
            guard case let .multipleChoice(schema)=exercise.interaction else { return XCTFail("Every valid assembly must be retained") }
            XCTAssertEqual(Set(schema.correctOptionIDs),Set(correct.map(NFSpatialStructureContract.choiceID)))
            for bits in 1..<16 {
                let indices=Set((0..<4).filter { bits & (1 << $0) != 0 })
                let result=NFExerciseScoringEngine.score(.multipleChoice(optionIDs:indices.map(NFSpatialStructureContract.choiceID).sorted()),for:exercise)
                XCTAssertEqual(result.isCorrect,indices == correct)
            }
            for candidate in value.candidates { XCTAssertTrue(G.permits(candidate)) }
        }
        XCTAssertEqual(cases,4);XCTAssertEqual(counts,[2,3])
    }

    func testMalformedUnsupportedAndProtectedGeometryFailsBeforeScoringOrRendering() throws {
        for bad in [[G.Cell(x:0,y:0,z:1)],[G.Cell(x:0,y:0,z:0),G.Cell(x:2,y:0,z:0)],
                    [G.Cell(x:0,y:0,z:0),G.Cell(x:0,y:0,z:0)],[G.Cell(x:Int.max,y:0,z:0)]] { XCTAssertFalse(G.permits(bad)) }
        XCTAssertTrue(G.transform([Int.min,0,0],by:[.init(axis:.x,quarterTurns:1)]).isEmpty)
        let structure=try XCTUnwrap(G.structures.first),exercise=try generated(structure)
        let original=try NFImmutableAttemptRecordSnapshot.encoded(exercise)
        for values:[String:Any] in [["schemaVersion":999],["generatorVersion":4],["assessmentProtected":true],["evidenceClass":EvidenceClass.assessmentHoldout.rawValue],["contextText":"Choose face A before trying the rotation."]] {
            let altered=try changed(exercise,values:values)
            XCTAssertNil(NFSpatialStructureContract.make(exercise:altered))
            XCTAssertEqual(NFExerciseScoringEngine.score(.singleChoice(optionID:"A"),for:altered).outcome,.invalidItem)
        }
        var feedback=try XCTUnwrap(JSONSerialization.jsonObject(with:JSONEncoder().encode(exercise.feedback)) as? [String:Any])
        feedback["correctExplanation"]="Every face ends in the same direction."
        XCTAssertNil(NFSpatialStructureContract.make(exercise:try changed(exercise,values:["feedback":feedback])))
        var metadata=try XCTUnwrap(JSONSerialization.jsonObject(with:JSONEncoder().encode(exercise.contractMetadata)) as? [String:Any])
        var contract=try XCTUnwrap(metadata["spatialStructure"] as? [String:Any]);contract["policyVersion"]=999;metadata["spatialStructure"]=contract
        XCTAssertNil(NFSpatialStructureContract.make(exercise:try changed(exercise,values:["contractMetadata":metadata])))
        metadata.removeValue(forKey:"spatialStructure")
        XCTAssertEqual(NFExerciseScoringEngine.score(.singleChoice(optionID:"A"),for:try changed(exercise,values:["contractMetadata":metadata])).outcome,.invalidItem)
        XCTAssertTrue(NFHistoryContextProjection.make(exercise:exercise,hintCount:0,isProtected:true).representations.isEmpty)
        XCTAssertEqual(try NFImmutableAttemptRecordSnapshot.encoded(exercise),original)
        XCTAssertThrowsError(try NFFallbackExerciseGenerator.generate(.init(seed:1,index:0,lab:.spatial,purpose:.assessmentHoldout,spatialStructurePolicyVersion:1)))
        XCTAssertThrowsError(try NFFallbackExerciseGenerator.generate(.init(seed:1,index:0,lab:.spatial,purpose:.practice,spatialStructurePolicyVersion:999)))
        let legacy=try NFFallbackExerciseGenerator.generate(.init(seed:1,index:0,lab:.spatial,purpose:.practice,preferredAssessmentMechanicID:"fixture.fallback-variant-1"))
        XCTAssertEqual(legacy.generatorVersion,4);XCTAssertEqual(legacy.schemaVersion,2);XCTAssertNil(legacy.contractMetadata?.spatialStructure)
    }

    func testActualLaunchColdChoiceQuarantineAndHistoryKeepTheExactNewStructure() throws {
        let (store,container)=try store();defer { withExtendedLifetime(container) {} }
        let activity=try XCTUnwrap(NFDefaultContentCatalog.activity(id:"nf.default.spatial.object-rotation"))
        XCTAssertTrue(store.beginSession(lab:.spatial,source:.focused,requestedItemCount:5,isTimed:false,mechanicID:activity.mechanicID))
        let request=try XCTUnwrap(store.activeSessionRequest),value=try XCTUnwrap(request.localCheckpoint?.exercise)
        let contract=try XCTUnwrap(NFSpatialStructureContract.make(exercise:value));XCTAssertEqual(request.spatialStructurePolicyVersion,1)
        guard case let .faces(geometry)=contract.structure else { return XCTFail("Actual focused family substituted an unrelated item") }
        let answerIndex=try XCTUnwrap(G.Direction.allCases.firstIndex { apply(rotationMatrix(geometry.rotations),$0.vector) == geometry.query.vector }),answer=G.FaceRotation.labels[answerIndex]
        let runtime=NFUniversalSessionRuntime(request:request);XCTAssertTrue(runtime.checkpointDraft(store:store));runtime.resume();runtime.acknowledgePresented();runtime.singleChoiceID=answer
        XCTAssertTrue(runtime.checkpointDraft(store:store));runtime.releaseWriter()
        let envelope=try XCTUnwrap(store.localSessions.archive.sessions.first { $0.id == runtime.sessionID })
        var coldRequest=envelope.request;coldRequest.localCheckpoint=envelope.checkpoint;coldRequest.localSessionID=envelope.id
        let cold=NFUniversalSessionRuntime(request:coldRequest);XCTAssertNil(cold.unavailableReason);XCTAssertEqual(cold.singleChoiceID,answer);XCTAssertEqual(cold.exercise,value)
        cold.resume();cold.acknowledgePresented();cold.submitInline(store:store);XCTAssertEqual(cold.lastResult?.outcome,.correct)
        let record=try XCTUnwrap(store.attempts.first),snapshot=try XCTUnwrap(store.exerciseSnapshot(for:record.id))
        XCTAssertEqual(snapshot,value);XCTAssertEqual(snapshot.contractMetadata?.spatialStructure,contract)
        var quarantineJSON=try XCTUnwrap(JSONSerialization.jsonObject(with:JSONEncoder().encode(request)) as? [String:Any])
        quarantineJSON["quarantinedItemIDs"]=[value.id]
        let quarantined=try JSONDecoder().decode(SessionRequest.self,from:JSONSerialization.data(withJSONObject:quarantineJSON))
        let replacement=NFDeterministicSessionExerciseFactory.makeExercise(request:quarantined,index:0,assessmentDescriptor:nil,excludingContentFingerprints:[NFQuestionFingerprint.fingerprint(for:value)])
        XCTAssertNil(replacement.availabilityReason);XCTAssertNotEqual(replacement.id,value.id);XCTAssertNotEqual(NFQuestionFingerprint.fingerprint(for:replacement),NFQuestionFingerprint.fingerprint(for:value))
        var missing=request;missing.spatialStructurePolicyVersion=nil;XCTAssertFalse(missing.permitsSpatialStructure(exercise:value))
        cold.next(store:store);XCTAssertEqual(cold.index,1);XCTAssertNotEqual(cold.exercise.id,value.id)
    }

    func testGeneratedRetainedAssemblyUsesSameTypedChoiceAndSavedHistory() throws {
        let (store,container)=try store();defer { withExtendedLifetime(container) {} }
        let structure=try XCTUnwrap(G.structures.first { if case .top=$0 { return true };return false }),exercise=try generated(structure,purpose:.documentPractice)
        guard case let .singleChoice(schema)=exercise.interaction else { return XCTFail("Expected a footprint choice") }
        let answer=try XCTUnwrap(schema.options.first { $0.id == schema.correctOptionID })
        let id=UUID(),request=NFAuthoringRequest(id:id,capability:.contextualize,lab:.spatial,field:.general,customTopic:"Synthetic occupied assembly",learningObjective:"Interpret the exact occupied cells",style:.spatialTransformation,difficulty:0.4,count:1,localeIdentifier:"en_US",seed:1,aiMode:.disabled)
        let question=NFAuthoredQuestion(id:exercise.id,lab:.spatial,style:.spatialTransformation,prompt:exercise.prompt,context:exercise.contextText ?? "",choices:schema.options.map(\.text),correctAnswer:answer.text,acceptedAnswers:[],explanation:exercise.feedback.correctExplanation,hint:exercise.feedback.hintLadder[0],decisiveStep:exercise.feedback.decisiveStep,difficulty:0.4,citationChunkIDs:[],evidenceClass:.documentPractice,authoritativeExercise:exercise)
        XCTAssertTrue(NFAuthoredExerciseAuthority.validatesBinding(question))
        let result=NFAuthoringResult(questions:[question],provenance:.init(requestID:id,generatedAt:Date().addingTimeInterval(-1),route:.deterministicFallback,routeReason:"Synthetic retained geometry",promptVersion:1,modelIdentifier:"synthetic.geometry",sourceChunkIDs:[],sourceDocumentIDs:[],validationVersion:1,repairCount:0,cacheKey:"synthetic.geometry",isFallback:true),routeCandidates:[],validationStatus:.init(level:.deterministicKey,sourceSupport:.notApplicable),validationNotes:[])
        let runtime=AIGeneratedPracticeRuntime(result:result,request:request);XCTAssertTrue(runtime.checkpoint(store:store));runtime.resume();runtime.singleChoiceID=schema.correctOptionID
        XCTAssertTrue(runtime.checkpoint(store:store));let draft=try XCTUnwrap(store.generatedPracticeDraft(for:id));runtime.releaseWriter()
        let cold=AIGeneratedPracticeRuntime(result:result,request:request,draft:draft);XCTAssertTrue(cold.restoreCheckpoint(store:store));cold.resume();XCTAssertEqual(cold.exercise,exercise);XCTAssertEqual(cold.singleChoiceID,schema.correctOptionID)
        cold.submit(store:store);XCTAssertEqual(cold.lastScore?.outcome,.correct)
        let record=try XCTUnwrap(store.attempts.first);XCTAssertEqual(store.exerciseSnapshot(for:record.id),exercise)
    }
    func testSemanticAliasesAndMissingPinnedPolicyCannotMintOrOverwriteAQuestion() throws {
        let left=G.FaceRotation(rotations:[.init(axis:.x,quarterTurns:2),.init(axis:.y,quarterTurns:2)],query:.positiveY)
        let equivalent=G.FaceRotation(rotations:[.init(axis:.z,quarterTurns:2)],query:.positiveY)
        XCTAssertEqual(left.identity,equivalent.identity)
        let shape=try XCTUnwrap(G.footprints.last)
        XCTAssertEqual(G.canonical(shape),G.canonical(shape.map { .init(x:-$0.y,y:$0.x) }))
        let (store,container)=try store();defer { withExtendedLifetime(container) {} }
        let activity=try XCTUnwrap(NFDefaultContentCatalog.activity(id:"nf.default.spatial.top-view"))
        XCTAssertTrue(store.beginSession(lab:.spatial,source:.focused,requestedItemCount:5,isTimed:false,mechanicID:activity.mechanicID))
        let request=try XCTUnwrap(store.activeSessionRequest)
        let original=try NFImmutableAttemptRecordSnapshot.encoded(store.localSessions.archive.sessions)
        var incompatible=request;incompatible.spatialStructurePolicyVersion=nil
        let invalid=NFUniversalSessionRuntime(request:incompatible)
        XCTAssertNotNil(invalid.unavailableReason);XCTAssertFalse(invalid.checkpointDraft(store:store));XCTAssertTrue(store.attempts.isEmpty)
        XCTAssertEqual(try NFImmutableAttemptRecordSnapshot.encoded(store.localSessions.archive.sessions),original)
        var future=request;future.spatialStructurePolicyVersion=999
        XCTAssertFalse(future.hasSupportedSpatialStructurePolicy)
        let unavailable=NFDeterministicSessionExerciseFactory.makeExercise(request:future,index:0,assessmentDescriptor:nil)
        XCTAssertNotNil(unavailable.availabilityReason)
    }

}


@MainActor
final class RetrievalWorkerStackTests: XCTestCase {
    func testActualDetachedPrelaunchValidatesEveryRetrievalAssetFormWithoutChangingAuthorityOrStore() async throws {
        for locale in ["en_US","ja_JP"] {
            for activityID in ["nf.default.retrieval.cloze","nf.default.retrieval.equation","nf.default.retrieval.figure"] {
                let root=FileManager.default.temporaryDirectory.appending(path:"NF-Retrieval-Worker-\(UUID().uuidString)")
                try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
                defer { try? FileManager.default.removeItem(at:root) }
                let rotation=NFOfflineQuestionRotation(store:NFMemoryOfflineQuestionRotationStateStore())
                let container=try ModelContainer(for:Schema(NFSchemaV1.models),configurations:ModelConfiguration(isStoredInMemoryOnly:true))
                var draft=OnboardingDraft();draft.aiMode = .disabled
                let profile=UserProfileRecord(draft:draft);profile.preferredLanguageCode=locale
                container.mainContext.insert(profile);try container.mainContext.save()
                let empty=AppStore(context:container.mainContext,
                    nextDayEnhancementCache:NFNextDayEnhancementCache(rootURL:root.appending(path:"empty-cache")),
                    documentStorageRootURL:root.appending(path:"empty-documents"),localSessionRepository:NFLocalSessionRepository(),
                    adaptivePlanHistoryRepository:NFAdaptivePlanHistoryRepository(fileURL:root.appending(path:"empty-history.json")),
                    offlineQuestionRotation:rotation,temporaryArtifactsRootURL:root.appending(path:"empty-temporary"),allowsSharedWidgetPublishing:false)
                let activity=try XCTUnwrap(NFDefaultContentCatalog.activity(id:activityID))
                let request=empty.reviewedPracticeRequest(lab:.retrieval,activity:activity,field:.general,
                    requestedItemCount:1,timingCondition:.init(.untimed),targetDifficulty:activity.defaultDifficulty)
                let scope=NFEditorialCatalogScope(catalogVersion:NFDefaultContentCatalog.version,activityID:activityID,field:.general)
                var original:NFExercise?,bankID:String?,ordinal:Int?
                for id in NFOfflineQuestionBank.rotationBank.questionIDs(for:.retrieval) {
                    guard let index=NFOfflineQuestionBank.ordinal(forQuestionID:id,lab:.retrieval) else { continue }
                    let value=NFDeterministicSessionExerciseFactory.makeExercise(request:request.launchOnly(offlineQuestionOrdinals:[index]),index:0,assessmentDescriptor:nil)
                    guard scope.matches(value),NFEditorialNativeProtocol.supports(value),NFRetrievalAssetContract.make(exercise:value) != nil,
                          case .numeric=value.interaction else { continue }
                    original=value;bankID=id;ordinal=index;break
                }
                let exercise=try XCTUnwrap(original),id=try XCTUnwrap(bankID),index=try XCTUnwrap(ordinal)
                let demand=NFEditorialDemandRecord(objectiveID:"QA.worker.retrieval",familyID:"QA.worker.family",
                    structureID:"QA.worker.structure",semanticFingerprint:try XCTUnwrap(exercise.contractMetadata?.semanticFingerprint),
                    editorialBand:.b1,demandVector:.init(reasoningSteps:1,quantityDomain:["basis":"Synthetic worker fixture"],
                        representationMappings:["numeric"],misconceptionClasses:[],abstraction:"concrete",relevantGivens:2,
                        irrelevantGivens:0,missingGivens:0,scaffoldConditionID:"essential-only",prerequisiteConceptIDs:[]),
                    bandContractVersion:"QA.worker.band.v1",calibrationStatus:.editorial,calibrationVersion:nil,
                    independentEligible:true,protectedEligible:false,assistancePolicyID:NFEditorialNativeProtocol.toolConditionID,
                    answerContractVersion:"QA.worker.answer.v1",expectedDurationRange:.init(minimumSeconds:10,maximumSeconds:40),
                    representationIDs:["numeric"],prerequisiteObjectiveIDs:[])
                let entry=NFEditorialAdmissionEntry(id:"QA.worker.entry",bankQuestionID:id,exerciseDigest:try NFLocalItemCheckpoint.digest(exercise),
                    scorerVersion:NFExerciseScoringEngine.scoringVersion,lab:.retrieval,contentLocale:locale,demand:demand)
                let repository=NFLocalSessionRepository(editorialAdmissions:.init(version:"QA.worker.preview.v1",entries:[entry]))
                let store=AppStore(context:container.mainContext,
                    nextDayEnhancementCache:NFNextDayEnhancementCache(rootURL:root.appending(path:"actual-cache")),
                    documentStorageRootURL:root.appending(path:"actual-documents"),localSessionRepository:repository,
                    adaptivePlanHistoryRepository:NFAdaptivePlanHistoryRepository(fileURL:root.appending(path:"actual-history.json")),
                    offlineQuestionRotation:rotation,temporaryArtifactsRootURL:root.appending(path:"actual-temporary"),allowsSharedWidgetPublishing:false)
                let archive=try NFImmutableAttemptRecordSnapshot.encoded(repository.archive)
                // This is the real app adapter and Task.detached preview path
                // that previously exhausted the cooperative worker's stack.
                let preview=try await store.reviewedStartingPreview(request:request,catalogScope:scope)
                XCTAssertEqual(preview.state,.feasible);XCTAssertTrue(preview.choices.contains { $0.availableUniqueCount == 1 && $0.band == .b1 })
                XCTAssertEqual(try NFImmutableAttemptRecordSnapshot.encoded(repository.archive),archive)
                XCTAssertTrue(store.attempts.isEmpty);XCTAssertNil(store.activeSessionRequest);XCTAssertFalse(store.allowsSharedWidgetPublishing)
                let expected=try NFImmutableAttemptRecordSnapshot.encoded(exercise)
                let restored=try await Task.detached {
                    let saved=NFDeterministicSessionExerciseFactory.makeExercise(request:request.launchOnly(offlineQuestionOrdinals:[index]),index:0,assessmentDescriptor:nil)
                    try NFExerciseSchemaValidator.validate(saved)
                    return try NFImmutableAttemptRecordSnapshot.encoded(saved)
                }.value
                XCTAssertEqual(restored,expected,"Worker construction/validation must preserve the exact pinned recipe bytes")
                withExtendedLifetime(container) {}
            }
        }
    }
    func testDetachedGenerationStillRejectsInvalidRequestsThroughMandatoryValidation() async throws {
        let results=await Task.detached {
            [-1,0].map { index -> NFExerciseGenerationError? in
                do {
                    _ = try NFFallbackExerciseGenerator.generate(.init(seed:1,index:index,lab:.retrieval,purpose:.practice,
                        preferredAssessmentMechanicID:"fixture.fallback-variant-6",retrievalAuthorityPolicyVersion:1,retrievalAssetPolicyVersion:index == 0 ? 999 : 1))
                    return nil
                } catch { return error as? NFExerciseGenerationError }
            }
        }.value
        XCTAssertEqual(results,[.invalidIndex,.unsupportedRetrievalAsset])
    }
}


@MainActor
final class CoordinateTransformContractTests: XCTestCase {
    private typealias G=NFCoordinateTransformGeometry
    private func store() throws -> (AppStore,ModelContainer) {
        let container=try ModelContainer(for:Schema(NFSchemaV1.models),configurations:ModelConfiguration(isStoredInMemoryOnly:true))
        var draft=OnboardingDraft();draft.aiMode = .disabled
        container.mainContext.insert(UserProfileRecord(draft:draft));try container.mainContext.save()
        let root=FileManager.default.temporaryDirectory.appending(path:"NF-Coordinate-Fixture-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
        addTeardownBlock { try? FileManager.default.removeItem(at:root) }
        return (AppStore(context:container.mainContext,
            nextDayEnhancementCache:NFNextDayEnhancementCache(rootURL:root.appending(path:"cache")),
            documentStorageRootURL:root.appending(path:"documents"),localSessionRepository:NFLocalSessionRepository(),
            adaptivePlanHistoryRepository:NFAdaptivePlanHistoryRepository(fileURL:root.appending(path:"history.json")),
            offlineQuestionRotation:NFOfflineQuestionRotation(store:NFMemoryOfflineQuestionRotationStateStore()),
            temporaryArtifactsRootURL:root.appending(path:"temporary"),allowsSharedWidgetPublishing:false),container)
    }
    private func generated(_ task:G.Task,locale:String="en_US",purpose:NFExercisePurpose = .practice) throws -> NFExercise {
        let values=G.tasks.filter { $0.kind.variant == task.kind.variant },target=try XCTUnwrap(G.tasks.filter { $0.kind.variant == task.kind.variant }.firstIndex(of:task))
        let mechanic="fixture.fallback-variant-\(task.kind.variant)"
        func selected(_ seed:UInt64) -> Int {
            let discriminator="\(seed):0:\(TrainingLab.spatial.rawValue):\(purpose.rawValue):automatic:\(mechanic):no-transfer-brief:4"
            var hash:UInt64=0xcbf29ce484222325
            for byte in discriminator.utf8 { hash=(hash ^ UInt64(byte)) &* 0x100000001b3 }
            var state=seed ^ hash;if state == 0 { state=0x9E3779B97F4A7C15 };state &+= 0x9E3779B97F4A7C15
            var v=(state ^ (state >> 30)) &* 0xBF58476D1CE4E5B9;v=(v ^ (v >> 27)) &* 0x94D049BB133111EB
            return Int((v ^ (v >> 31)) % UInt64(values.count))
        }
        let seed=try XCTUnwrap((UInt64(0)..<20_000).first { selected($0) == target })
        return try NFFallbackExerciseGenerator.generate(.init(seed:seed,index:0,lab:.spatial,purpose:purpose,
            localeIdentifier:locale,preferredAssessmentMechanicID:mechanic,spatialStructurePolicyVersion:1,coordinateTransformPolicyVersion:1))
    }
    /// Independent homogeneous row-matrix oracle: rotations use trigonometry;
    /// reflections use I−2nnᵀ/(nᵀn), including translated line offsets.
    private func oracle(_ point:G.Point,operations:[G.Operation]) -> G.Point {
        var p=[Double(point.x),Double(point.y),1]
        for operation in operations {
            let m:[[Double]]
            switch operation {
            case let .rotate(center,q):
                let c=cos(Double(q)*Double.pi/2).rounded(),s=sin(Double(q)*Double.pi/2).rounded()
                let x=Double(center.x),y=Double(center.y)
                m=[[c,-s,x-c*x+s*y],[s,c,y-s*x-c*y],[0,0,1]]
            case let .translate(v): m=[[1,0,Double(v.x)],[0,1,Double(v.y)],[0,0,1]]
            case let .reflect(line,offset):
                let n:[Double]
                switch line { case .vertical:n=[1,0];case .horizontal:n=[0,1];case .risingDiagonal:n=[1,-1];case .fallingDiagonal:n=[1,1] }
                let scale=2/(n[0]*n[0]+n[1]*n[1]),k=Double(offset)
                m=[[1-scale*n[0]*n[0],-scale*n[0]*n[1],scale*k*n[0]],[-scale*n[1]*n[0],1-scale*n[1]*n[1],scale*k*n[1]],[0,0,1]]
            }
            p=m.map { row in zip(row,p).reduce(0) { $0+$1.0*$1.1 } }
        }
        return .init(x:Int(p[0].rounded()),y:Int(p[1].rounded()))
    }
    private func response(_ p:G.Point) -> NFExerciseResponse { .logicState(.init(finalState:["x":String(p.x),"y":String(p.y)],violatedRuleID:nil)) }
    private func squaredDistance(_ a:G.Point,_ b:G.Point) -> Int { (a.x-b.x)*(a.x-b.x)+(a.y-b.y)*(a.y-b.y) }

    func testAllBoundedCoordinateContractsMatchIndependentAffineOracleAndTypedCredit() throws {
        XCTAssertEqual(G.tasks.count,336)
        for task in G.tasks {
            let expected=oracle(task.point,operations:task.operations),value=try generated(task)
            XCTAssertEqual(task.answer,expected);XCTAssertEqual(value.schemaVersion,9);XCTAssertEqual(value.generatorVersion,12)
            XCTAssertTrue(value.id.contains(".r12."));XCTAssertEqual(value.contractMetadata?.structureID,task.semanticIdentity)
            XCTAssertEqual(NFQuestionFingerprint.fingerprint(for:value),value.contractMetadata?.semanticFingerprint)
            let contract=try XCTUnwrap(NFCoordinateTransformContract.make(exercise:value));XCTAssertEqual(contract.task,task)
            let scope=NFEditorialCatalogScope(catalogVersion:NFDefaultContentCatalog.version,activityID:contract.familyID,field:value.sourceContext.primaryField)
            XCTAssertTrue(scope.matches(value))
            let other=NFEditorialCatalogScope(catalogVersion:NFDefaultContentCatalog.version,activityID:task.kind.variant == 0 ? "nf.default.spatial.vector-reflection" : "nf.default.spatial.coordinate-rotation",field:value.sourceContext.primaryField)
            XCTAssertFalse(other.matches(value))
            XCTAssertEqual(contract.representation.viewpoint,contract.representation.difficultyParameters.viewpoint)
            XCTAssertEqual(contract.representation.difficultyParameters.responseMode,.coordinateEntry)
            XCTAssertEqual(NFExerciseScoringEngine.score(response(expected),for:value).outcome,.correct)
            let equivalent=NFExerciseResponse.logicState(.init(finalState:["x":"\(expected.x*2)/2","y":"\(expected.y).0"],violatedRuleID:nil))
            XCTAssertEqual(NFExerciseScoringEngine.score(equivalent,for:value).outcome,.correct)
            let half=NFExerciseScoringEngine.score(response(.init(x:expected.x,y:expected.y+1)),for:value)
            XCTAssertFalse(half.isCorrect);XCTAssertEqual(half.credit,0.5)
            XCTAssertNil(value.contractMetadata?.editorialDemand)
        }
    }
    func testAllQuadrantsCentersLineFixedPointsDistancesAndOrderedCompositions() throws {
        let operations=G.tasks.flatMap(\.operations)
        for operation in operations {
            let f=try XCTUnwrap(operation.affine)
            XCTAssertEqual(abs(f.determinant),1)
            for x in -3...3 { for y in -3...3 {
                let p=G.Point(x:x,y:y),q=G.Point(x:x+1,y:y-2)
                XCTAssertEqual(f.applying(p),oracle(p,operations:[operation]))
                XCTAssertEqual(squaredDistance(p,q),squaredDistance(f.applying(p),f.applying(q)))
                switch operation {
                case let .rotate(center,_):
                    XCTAssertEqual(f.applying(center),center)
                    XCTAssertEqual(squaredDistance(p,center),squaredDistance(f.applying(p),center))
                case let .reflect(line,offset):
                    XCTAssertEqual(f.applying(f.applying(p)),p)
                    let before:Int,after:Int;let result=f.applying(p)
                    switch line { case .vertical:before=p.x-offset;after=result.x-offset;case .horizontal:before=p.y-offset;after=result.y-offset;case .risingDiagonal:before=p.x-p.y;after=result.x-result.y;case .fallingDiagonal:before=p.x+p.y;after=result.x+result.y }
                    XCTAssertEqual(before,-after)
                    if before == 0 { XCTAssertEqual(result,p) }
                case .translate: break
                }
            } }
        }
        let a=try XCTUnwrap(G.tasks.first { $0.kind == .translateThenRotate && $0.point == .init(x:3,y:2) })
        let b=try XCTUnwrap(G.tasks.first { $0.kind == .rotateThenTranslate && $0.point == a.point })
        XCTAssertNotEqual(a.answer,b.answer)
        let all=Set(G.tasks.map(\.point));XCTAssertTrue(all.contains(.init(x:0,y:0)));XCTAssertTrue(all.contains(.init(x:1,y:-1)))
        for sx in [-1,1] { for sy in [-1,1] { XCTAssertTrue(all.contains { $0.x*sx > 0 && $0.y*sy > 0 }) } }
    }
    func testSemanticIdentityCollapsesSignScaleAndFixedPointAliasesWithoutLosingTaskOrder() throws {
        let a=G.Task(kind:.rotateOrigin,point:.init(x:3,y:2),operations:[.rotate(center:.init(x:0,y:0),quarterTurns:1)])
        let reflected=G.Task(kind:.rotateOrigin,point:.init(x:-3,y:2),operations:[.rotate(center:.init(x:0,y:0),quarterTurns:-1)])
        let scaled=G.Task(kind:.rotateOrigin,point:.init(x:6,y:4),operations:a.operations)
        XCTAssertEqual(a.semanticIdentity,reflected.semanticIdentity);XCTAssertEqual(a.semanticIdentity,scaled.semanticIdentity)
        let first=G.Task(kind:.rotateOrigin,point:.init(x:0,y:0),operations:a.operations)
        let half=G.Task(kind:.rotateOrigin,point:.init(x:0,y:0),operations:[.rotate(center:.init(x:0,y:0),quarterTurns:2)])
        XCTAssertEqual(first.semanticIdentity,half.semanticIdentity)
        XCTAssertEqual(Set(G.tasks.map(\.semanticIdentity)).count,120)
        XCTAssertEqual(Set(G.tasks.map(\.kind)),Set(G.TaskKind.allCases))
    }
    func testOriginalDiagramAndCopyKeepIndependentPointAndBothRecordedLocales() throws {
        let task=try XCTUnwrap(G.tasks.first { $0.kind == .rotateThenReflect && $0.point == .init(x:3,y:2) })
        for locale in ["en_US","ja_JP"] {
            let exercise=try generated(task,locale:locale),value=try XCTUnwrap(NFCoordinateTransformContract.make(exercise:exercise))
            let original=try NFImmutableAttemptRecordSnapshot.encoded(exercise)
            XCTAssertTrue(value.sourceDescription.contains("(3, 2)"));XCTAssertTrue(value.representation.axisLabels.allSatisfy { $0.contains(locale == "en_US" ? "grid units" : "格子単位") })
            XCTAssertEqual(value.representation.points,[.init(label:"P",x:3,y:2,z:nil)])
            var copy=NFCoordinateTransformCopyState();XCTAssertFalse(copy.advance(contract:value,phase:.independent));XCTAssertEqual(copy.visibleStep(contract:value,phase:.independent),0)
            XCTAssertTrue(copy.advance(contract:value,phase:.committedFeedback));XCTAssertEqual(copy.visibleStep(contract:value,phase:.committedFeedback),1)
            XCTAssertEqual(copy.visibleStep(contract:value,phase:.independent),0)
            XCTAssertTrue(copy.advance(contract:value,phase:.committedFeedback));XCTAssertFalse(copy.advance(contract:value,phase:.committedFeedback))
            copy.reset();XCTAssertEqual(copy.visibleStep(contract:value,phase:.committedFeedback),0)
            XCTAssertEqual(try NFImmutableAttemptRecordSnapshot.encoded(exercise),original)
        }
    }
    func testFutureProtectedMalformedAndMissingRequestPolicyRefuseWithoutOverwritingOriginal() throws {
        XCTAssertFalse(G.Task(kind:.rotateOrigin,point:.init(x:Int.max,y:0),operations:[.rotate(center:.init(x:0,y:0),quarterTurns:1)]).isBounded)
        XCTAssertNil(G.Operation.rotate(center:.init(x:0,y:0),quarterTurns:Int.min).affine)
        XCTAssertNil(G.Operation.reflect(line:.risingDiagonal,offset:1).affine)
        let task=try XCTUnwrap(G.tasks.first),exercise=try generated(task)
        var raw=try XCTUnwrap(JSONSerialization.jsonObject(with:JSONEncoder().encode(exercise)) as? [String:Any])
        func decode() throws -> NFExercise { try JSONDecoder().decode(NFExercise.self,from:JSONSerialization.data(withJSONObject:raw)) }
        raw["assessmentProtected"]=true;let protected=try decode()
        XCTAssertNil(NFCoordinateTransformContract.make(exercise:protected));XCTAssertEqual(NFExerciseScoringEngine.score(response(task.answer!),for:protected).outcome,.invalidItem)
        raw["assessmentProtected"]=false;raw["schemaVersion"]=999
        XCTAssertFalse(try decode().hasSupportedCoordinateTransform)
        XCTAssertThrowsError(try NFFallbackExerciseGenerator.generate(.init(seed:1,index:0,lab:.spatial,purpose:.assessmentHoldout,coordinateTransformPolicyVersion:1)))
        XCTAssertThrowsError(try NFFallbackExerciseGenerator.generate(.init(seed:1,index:0,lab:.spatial,purpose:.practice,coordinateTransformPolicyVersion:999)))
        let (store,container)=try store();defer { withExtendedLifetime(container) {} }
        let activity=try XCTUnwrap(NFDefaultContentCatalog.activity(id:"nf.default.spatial.coordinate-rotation"))
        XCTAssertTrue(store.beginSession(lab:.spatial,source:.focused,requestedItemCount:5,isTimed:false,mechanicID:activity.mechanicID))
        var request=try XCTUnwrap(store.activeSessionRequest);XCTAssertEqual(request.coordinateTransformPolicyVersion,1)
        let bytes=try NFImmutableAttemptRecordSnapshot.encoded(store.localSessions.archive.sessions);request.coordinateTransformPolicyVersion=nil
        let runtime=NFUniversalSessionRuntime(request:request);XCTAssertNotNil(runtime.unavailableReason);XCTAssertFalse(runtime.checkpointDraft(store:store));XCTAssertTrue(store.attempts.isEmpty)
        XCTAssertEqual(try NFImmutableAttemptRecordSnapshot.encoded(store.localSessions.archive.sessions),bytes)
        let legacy=try NFFallbackExerciseGenerator.generate(.init(seed:11,index:0,lab:.spatial,purpose:.practice,preferredAssessmentMechanicID:activity.mechanicID))
        XCTAssertEqual(legacy.generatorVersion,4);XCTAssertEqual(legacy.schemaVersion,2)
        let object=try NFFallbackExerciseGenerator.generate(.init(seed:11,index:0,lab:.spatial,purpose:.practice,preferredAssessmentMechanicID:"fixture.fallback-variant-1",spatialStructurePolicyVersion:1,coordinateTransformPolicyVersion:1))
        XCTAssertEqual(object.generatorVersion,11);XCTAssertNotNil(NFSpatialStructureContract.make(exercise:object))
    }
    func testActualColdCoordinatesCommitHistoryAndNextPreserveExactTypedPoint() throws {
        let (store,container)=try store();defer { withExtendedLifetime(container) {} }
        let activity=try XCTUnwrap(NFDefaultContentCatalog.activity(id:"nf.default.spatial.vector-reflection"))
        XCTAssertTrue(store.beginSession(lab:.spatial,source:.focused,requestedItemCount:5,isTimed:false,mechanicID:activity.mechanicID))
        let request=try XCTUnwrap(store.activeSessionRequest),exercise=try XCTUnwrap(request.localCheckpoint?.exercise),contract=try XCTUnwrap(NFCoordinateTransformContract.make(exercise:exercise))
        let expected=oracle(contract.task.point,operations:contract.task.operations)
        let runtime=NFUniversalSessionRuntime(request:request);XCTAssertTrue(runtime.checkpointDraft(store:store));runtime.resume();runtime.acknowledgePresented()
        runtime.logicState=["x":"\(expected.x*2)/2","y":"\(expected.y).0"]
        XCTAssertTrue(runtime.checkpointDraft(store:store));runtime.releaseWriter()
        let envelope=try XCTUnwrap(store.localSessions.archive.sessions.first { $0.id == runtime.sessionID })
        var recovered=envelope.request;recovered.localCheckpoint=envelope.checkpoint;recovered.localSessionID=envelope.id
        let cold=NFUniversalSessionRuntime(request:recovered);XCTAssertEqual(cold.logicState,runtime.logicState);XCTAssertEqual(cold.exercise,exercise)
        cold.resume();cold.acknowledgePresented();cold.submitInline(store:store);XCTAssertEqual(cold.lastResult?.outcome,.correct)
        let record=try XCTUnwrap(store.attempts.first);XCTAssertEqual(store.exerciseSnapshot(for:record.id),exercise)
        let saved=try JSONDecoder().decode(NFExerciseResponse.self,from:Data(record.response.utf8))
        XCTAssertEqual(saved,.logicState(.init(finalState:runtime.logicState,violatedRuleID:nil)))
        cold.next(store:store);XCTAssertEqual(cold.index,1);XCTAssertNotEqual(NFQuestionFingerprint.fingerprint(for:cold.exercise),NFQuestionFingerprint.fingerprint(for:exercise))
        XCTAssertEqual(cold.exercise.contractMetadata?.coordinateTransform?.familyID,contract.familyID)
    }
    func testGeneratedSavedPointUsesExactContractAndSameNumericAuthority() throws {
        let (store,container)=try store();defer { withExtendedLifetime(container) {} }
        let task=try XCTUnwrap(G.tasks.first { $0.kind == .reflectDiagonal && $0.point == .init(x:-3,y:2) }),exercise=try generated(task,purpose:.documentPractice)
        let id=UUID(),request=NFAuthoringRequest(id:id,capability:.contextualize,lab:.spatial,field:.general,customTopic:"Synthetic coordinate geometry",learningObjective:"Apply exact ordered transformations",style:.spatialTransformation,difficulty:0.4,count:1,localeIdentifier:"en_US",seed:1,aiMode:.disabled)
        guard case let .logicState(schema)=exercise.interaction else { return XCTFail("Expected typed coordinates") }
        let expectedText=schema.expectedFinalState.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator:",")
        let question=NFAuthoredQuestion(id:exercise.id,lab:.spatial,style:.spatialTransformation,prompt:exercise.prompt,context:"",choices:[],correctAnswer:expectedText,acceptedAnswers:[],explanation:exercise.feedback.correctExplanation,hint:exercise.feedback.hintLadder[0],decisiveStep:exercise.feedback.decisiveStep,difficulty:0.4,citationChunkIDs:[],evidenceClass:.documentPractice,authoritativeExercise:exercise)
        XCTAssertTrue(NFAuthoredExerciseAuthority.validatesBinding(question))
        let result=NFAuthoringResult(questions:[question],provenance:.init(requestID:id,generatedAt:Date().addingTimeInterval(-1),route:.deterministicFallback,routeReason:"Synthetic retained geometry",promptVersion:1,modelIdentifier:"synthetic.geometry",sourceChunkIDs:[],sourceDocumentIDs:[],validationVersion:1,repairCount:0,cacheKey:"synthetic.geometry",isFallback:true),routeCandidates:[],validationStatus:.init(level:.deterministicKey,sourceSupport:.notApplicable),validationNotes:[])
        let runtime=AIGeneratedPracticeRuntime(result:result,request:request);XCTAssertTrue(runtime.checkpoint(store:store));runtime.resume()
        let point=oracle(task.point,operations:task.operations);runtime.logicState=["x":"\(point.x)","y":"\(point.y)"]
        XCTAssertTrue(runtime.checkpoint(store:store));let draft=try XCTUnwrap(store.generatedPracticeDraft(for:id));runtime.releaseWriter()
        let cold=AIGeneratedPracticeRuntime(result:result,request:request,draft:draft);XCTAssertTrue(cold.restoreCheckpoint(store:store));cold.resume();XCTAssertEqual(cold.logicState,runtime.logicState)
        cold.submit(store:store);XCTAssertEqual(cold.lastScore?.outcome,.correct)
        let record=try XCTUnwrap(store.attempts.first);XCTAssertEqual(store.exerciseSnapshot(for:record.id),exercise)
    }
    func testRecipeVersionsAreScopedToFallbackAndPreserveCurrentAndLegacyAuthoredAuthority() throws {
        let authored=NFAuthoredExerciseAuthority.make(id:"synthetic.numeric.authority",lab:.mentalMath,style:.numerical,
            prompt:"What is seven plus five?",context:"",choices:[],correctAnswer:"12",acceptedAnswers:[],
            explanation:"Seven plus five is twelve.",hint:"Add five to seven.",decisiveStep:"The sum is twelve.",
            difficulty:0.3,citationChunkIDs:[],evidenceClass:.documentPractice)
        XCTAssertEqual(authored.generatorVersion,12);XCTAssertNotEqual(authored.provenance.generatorID,"nf.exercise.fallback")
        XCTAssertTrue(authored.hasSupportedCoordinateTransform);XCTAssertTrue(authored.hasSupportedSpatialStructure)
        XCTAssertNoThrow(try NFExerciseSchemaValidator.validate(authored))
        XCTAssertEqual(NFExerciseScoringEngine.score(.numeric(.init(value:"12",unit:nil)),for:authored).outcome,.correct)
        var raw=try XCTUnwrap(JSONSerialization.jsonObject(with:JSONEncoder().encode(authored)) as? [String:Any])
        raw["generatorVersion"]=11
        var provenance=try XCTUnwrap(raw["provenance"] as? [String:Any]);provenance["generatorVersion"]=11;raw["provenance"]=provenance
        let older=try JSONDecoder().decode(NFExercise.self,from:JSONSerialization.data(withJSONObject:raw))
        XCTAssertTrue(older.hasSupportedSpatialStructure);XCTAssertNoThrow(try NFExerciseSchemaValidator.validate(older))
        XCTAssertEqual(NFExerciseScoringEngine.score(.numeric(.init(value:"12",unit:nil)),for:older).outcome,.correct)
    }

}


@MainActor
final class ReviewedCoordinateProtocolTests: XCTestCase {
    private struct Fixture {
        let root:URL
        let owner:UUID
        let container:ModelContainer
        let store:AppStore
        let request:SessionRequest
        let activity:NFDefaultContentActivity
        let scope:NFEditorialCatalogScope
        let admissions:NFEditorialAdmissionContext
        var family:NFEditorialFamilyScope { .init(objectiveID:activity.id,familyID:activity.id) }
    }
    private func newStore(container:ModelContainer,root:URL,repository:NFLocalSessionRepository,suffix:String) -> AppStore {
        AppStore(context:container.mainContext,nextDayEnhancementCache:NFNextDayEnhancementCache(rootURL:root.appending(path:suffix+"-cache")),
            documentStorageRootURL:root.appending(path:suffix+"-documents"),localSessionRepository:repository,
            adaptivePlanHistoryRepository:NFAdaptivePlanHistoryRepository(fileURL:root.appending(path:suffix+"-history.json")),
            offlineQuestionRotation:NFOfflineQuestionRotation(store:NFMemoryOfflineQuestionRotationStateStore()),
            temporaryArtifactsRootURL:root.appending(path:suffix+"-temporary"),allowsSharedWidgetPublishing:false)
    }
    private func fixture(released:Bool=false) throws -> Fixture {
        let root=FileManager.default.temporaryDirectory.appending(path:"NF-Reviewed-Coordinate-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
        addTeardownBlock { try? FileManager.default.removeItem(at:root) }
        let container=try ModelContainer(for:Schema(NFSchemaV1.models),configurations:ModelConfiguration(isStoredInMemoryOnly:true))
        var onboarding=OnboardingDraft();onboarding.aiMode = .disabled;onboarding.timingMode = .adaptive
        container.mainContext.insert(UserProfileRecord(draft:onboarding));try container.mainContext.save()
        let initial=newStore(container:container,root:root,repository:NFLocalSessionRepository(),suffix:"initial")
        let activity=try XCTUnwrap(NFDefaultContentCatalog.activity(id:"nf.default.spatial.coordinate-rotation"))
        let request=initial.reviewedPracticeRequest(lab:.spatial,activity:activity,field:.general,requestedItemCount:6,
            timingCondition:.init(.untimed),targetDifficulty:activity.defaultDifficulty)
        let scope=NFEditorialCatalogScope(catalogVersion:NFDefaultContentCatalog.version,activityID:activity.id,field:.general)
        var entries:[NFEditorialAdmissionEntry]=[],seen:Set<String>=[]
        for id in NFOfflineQuestionBank.rotationBank.questionIDs(for:.spatial) {
            guard let ordinal=NFOfflineQuestionBank.ordinal(forQuestionID:id,lab:.spatial) else { continue }
            let exercise=NFDeterministicSessionExerciseFactory.makeExercise(request:request.launchOnly(offlineQuestionOrdinals:[ordinal]),index:0,assessmentDescriptor:nil)
            guard let geometry=NFCoordinateTransformContract.make(exercise:exercise),scope.matches(exercise),
                  let metadata=exercise.contractMetadata,seen.insert(metadata.semanticFingerprint).inserted else { continue }
            XCTAssertTrue(NFEditorialNativeProtocol.supports(exercise))
            let band:NFEditorialBand=entries.count < 8 ? .b1 : .b2
            // Synthetic test admissions bind real exact contracts. They do not
            // grant review or measured levels to any shipped content.
            let demand=NFEditorialDemandRecord(objectiveID:activity.id,familyID:activity.id,structureID:geometry.task.semanticIdentity,
                semanticFingerprint:metadata.semanticFingerprint,editorialBand:band,
                demandVector:.init(reasoningSteps:geometry.task.operations.count,quantityDomain:["basis":"Synthetic coordinate admission"],
                    representationMappings:["coordinate-entry"],misconceptionClasses:[],abstraction:"concrete",relevantGivens:2,
                    irrelevantGivens:0,missingGivens:0,scaffoldConditionID:"essential-only",prerequisiteConceptIDs:[]),
                bandContractVersion:"QA.coordinate.band.v1",calibrationStatus:.editorial,calibrationVersion:nil,
                independentEligible:true,protectedEligible:false,assistancePolicyID:NFEditorialNativeProtocol.toolConditionID,
                answerContractVersion:"QA.coordinate.answer.v1",expectedDurationRange:.init(minimumSeconds:50,maximumSeconds:120),
                representationIDs:["coordinate-entry"],prerequisiteObjectiveIDs:[])
            entries.append(.init(id:"QA.coordinate.entry.\(entries.count)",bankQuestionID:id,exerciseDigest:try NFLocalItemCheckpoint.digest(exercise),
                scorerVersion:NFExerciseScoringEngine.scoringVersion,lab:.spatial,contentLocale:request.localeIdentifier,demand:demand))
            if entries.count == 16 { break }
        }
        XCTAssertEqual(entries.count,16)
        let admissions:NFEditorialAdmissionContext=released ? .released : .init(version:"QA.coordinate.admission.v1",entries:entries)
        let owner=UUID(),repository=NFLocalSessionRepository(url:root.appending(path:"sessions-v1.json"),ownerDeviceID:owner,editorialAdmissions:admissions)
        let store=newStore(container:container,root:root,repository:repository,suffix:"active")
        return .init(root:root,owner:owner,container:container,store:store,request:request,activity:activity,scope:scope,admissions:admissions)
    }
    private func launch(_ f:Fixture,count:Int=6) throws -> NFUniversalSessionRuntime {
        XCTAssertTrue(f.store.beginDefaultCatalogSession(.init(activity:f.activity,field:.general),requestedItemCount:count,
            timingCondition:.init(.untimed),editorialStartingBand:.b1,editorialStartingFamilyScope:f.family),f.store.lastErrorMessage ?? "")
        let runtime=NFUniversalSessionRuntime(request:try XCTUnwrap(f.store.activeSessionRequest))
        XCTAssertTrue(runtime.checkpointDraft(store:f.store));runtime.resume();runtime.acknowledgePresented()
        return runtime
    }
    private func answer(_ runtime:NFUniversalSessionRuntime,store:AppStore,half:Bool=false) throws -> AttemptRecord {
        runtime.acknowledgePresented()
        let task=try XCTUnwrap(NFCoordinateTransformContract.make(exercise:runtime.exercise)?.task),point=try XCTUnwrap(task.answer)
        runtime.logicState=["x":"\(point.x*2)/2","y":"\(point.y+(half ? 1 : 0)).0"]
        runtime.noteTextResponseInput();runtime.submitInline(store:store)
        XCTAssertEqual(runtime.stage,.feedback);XCTAssertNil(runtime.saveError)
        XCTAssertEqual(runtime.lastResult?.credit,half ? 0.5 : 1)
        return try XCTUnwrap(store.attempts.first { $0.sessionID == runtime.sessionID && $0.itemID == runtime.exercise.id })
    }
    private func receipt(_ runtime:NFUniversalSessionRuntime,store:AppStore) throws -> NFEditorialControllerDecision {
        let envelope=try XCTUnwrap(store.localSessions.archive.sessions.first { $0.id == runtime.sessionID })
        let id=try XCTUnwrap(envelope.checkpoint.ordinaryReservationDecisionID)
        return try XCTUnwrap(store.localSessions.archive.adaptiveItemReceipts?[id]?.editorialDecision)
    }

    func testOnlyCompleteOrdinaryCoordinateContractExtendsStructuredResponseProtocol() throws {
        let f=try fixture();defer { withExtendedLifetime(f.container) {} }
        let runtime=try launch(f,count:1);defer { runtime.releaseWriter() }
        let exact=runtime.exercise;XCTAssertTrue(NFEditorialNativeProtocol.supports(exact))
        var future=exact;future.contractMetadata?.coordinateTransform?.policyVersion=999
        XCTAssertFalse(NFEditorialNativeProtocol.supports(future))
        var missing=exact;missing.contractMetadata?.coordinateTransform=nil
        XCTAssertFalse(NFEditorialNativeProtocol.supports(missing))
        let generic=try NFFallbackExerciseGenerator.generate(.init(seed:11,index:0,lab:.logicDebugging,purpose:.practice,
            preferredAssessmentMechanicID:"fixture.fallback-variant-0"))
        guard case .logicState=generic.interaction else { return XCTFail("Must test a real unrelated structured response") }
        XCTAssertFalse(NFEditorialNativeProtocol.supports(generic))
        var raw=try XCTUnwrap(JSONSerialization.jsonObject(with:JSONEncoder().encode(exact)) as? [String:Any]);raw["assessmentProtected"]=true
        let protected=try JSONDecoder().decode(NFExercise.self,from:JSONSerialization.data(withJSONObject:raw))
        XCTAssertFalse(NFEditorialNativeProtocol.supports(protected))
        raw["assessmentProtected"]=false;raw["evidenceClass"]=EvidenceClass.documentPractice.rawValue
        let personal=try JSONDecoder().decode(NFExercise.self,from:JSONSerialization.data(withJSONObject:raw))
        XCTAssertFalse(NFEditorialNativeProtocol.supports(personal))
    }
    func testActualCoordinateCommitCapturesFamilyBandAndNextUsesEligibleTypedObservation() throws {
        let f=try fixture();defer { withExtendedLifetime(f.container) {} }
        let runtime=try launch(f);defer { runtime.releaseWriter() }
        let original=runtime.exercise,record=try answer(runtime,store:f.store)
        let capture=try XCTUnwrap(f.store.localSessions.editorialSnapshot(for:record.id)?.editorialCapture)
        XCTAssertEqual(capture.authorityAtCommit,"admitted");XCTAssertEqual(capture.profileID,f.store.profile?.id)
        XCTAssertEqual(capture.runtimeWitness?.admission.demand.familyID,f.activity.id)
        XCTAssertEqual(capture.runtimeWitness?.admission.demand.editorialBand,.b1)
        XCTAssertTrue(f.store.localSessions.hasEditorialAuthority(for:capture))
        let observation=try XCTUnwrap(f.store.effectiveAttemptDTO(record).editorialObservation)
        XCTAssertEqual(observation.item?.familyID,f.activity.id);XCTAssertEqual(observation.item?.editorialBand,.b1)
        XCTAssertEqual(observation.credit,1);XCTAssertTrue(observation.isFullCredit)
        XCTAssertEqual(try JSONDecoder().decode(NFExerciseResponse.self,from:Data(observation.originalResponse.utf8)),.logicState(.init(finalState:runtime.logicState,violatedRuleID:nil)))
        let evidence=EditorialBandEvidenceV1.reduce([observation],decisionDayOrdinal:capture.day.ordinal)
        XCTAssertEqual(evidence.independentObservationIDs,[record.id.uuidString]);XCTAssertNil(evidence.summaries.first?.lastDemonstratedAt)
        runtime.next(store:f.store);XCTAssertEqual(runtime.index,1)
        let next=try receipt(runtime,store:f.store)
        XCTAssertTrue(next.controlAfter.processedObservationIDs?.contains(record.id.uuidString) == true)
        XCTAssertEqual(next.admission.demand.familyID,f.activity.id);XCTAssertEqual(next.selection.deliveredBand,.b1)
        XCTAssertNotEqual(runtime.exercise.contractMetadata?.semanticFingerprint,original.contractMetadata?.semanticFingerprint)
        XCTAssertEqual(f.store.exerciseSnapshot(for:record.id),original)
    }
    func testHalfCreditIsNotFullSuccessAndHelpIsExcludedWithoutChangingOriginalPoint() throws {
        let f=try fixture();defer { withExtendedLifetime(f.container) {} }
        let runtime=try launch(f);defer { runtime.releaseWriter() }
        var records:[AttemptRecord]=[]
        for _ in 0..<4 {
            let record=try answer(runtime,store:f.store,half:true);records.append(record)
            runtime.next(store:f.store);XCTAssertEqual(try receipt(runtime,store:f.store).selection.deliveredBand,.b1)
        }
        let observations=try records.map { try XCTUnwrap(f.store.effectiveAttemptDTO($0).editorialObservation) }
        XCTAssertTrue(observations.allSatisfy { $0.credit == 0.5 && !$0.isFullCredit && !$0.isZeroCredit })
        let day=try XCTUnwrap(f.store.localSessions.editorialSnapshot(for:records[0].id)?.editorialCapture?.day.ordinal)
        let evidence=EditorialBandEvidenceV1.reduce(observations,decisionDayOrdinal:day)
        XCTAssertEqual(evidence.independentObservationIDs.count,4,"Partial credit remains genuine graded evidence")
        XCTAssertEqual(evidence.summaries.first?.fullCorrectCount,0);XCTAssertNil(evidence.summaries.first?.lastDemonstratedAt)
        XCTAssertTrue(evidence.cleanSpeedObservationIDs.isEmpty)
        XCTAssertEqual(try receipt(runtime,store:f.store).controlAfter.totalAutomaticChangesThisSession,0)
        runtime.acknowledgePresented();runtime.requestHint(store:f.store);XCTAssertEqual(runtime.hintCount,1)
        let assisted=try answer(runtime,store:f.store),savedResponse=assisted.response
        let hintObservation=try XCTUnwrap(f.store.effectiveAttemptDTO(assisted).editorialObservation)
        let filtered=EditorialBandEvidenceV1.reduce(observations+[hintObservation],decisionDayOrdinal:day)
        XCTAssertEqual(filtered.exclusions[assisted.id.uuidString],"assisted")
        XCTAssertFalse(filtered.independentObservationIDs.contains(assisted.id.uuidString))
        runtime.next(store:f.store);XCTAssertEqual(assisted.response,savedResponse)
        XCTAssertEqual(try receipt(runtime,store:f.store).controlAfter.totalAutomaticChangesThisSession,0)
    }
    func testHarderPreferenceAndColdFileResumeRetainActualBandWithoutInventingDemonstration() throws {
        let f=try fixture();defer { withExtendedLifetime(f.container) {} }
        let runtime=try launch(f,count:3)
        let first=try answer(runtime,store:f.store,half:true)
        runtime.chooseReviewedChallenge(.harder,store:f.store)
        XCTAssertTrue(runtime.applyReviewedChoice(.nextQuestion,store:f.store))
        runtime.next(store:f.store);XCTAssertEqual(runtime.index,1)
        XCTAssertEqual(try receipt(runtime,store:f.store).selection.deliveredBand,.b2)
        let value=runtime.exercise,task=try XCTUnwrap(value.contractMetadata?.coordinateTransform?.task),point=try XCTUnwrap(task.answer)
        runtime.logicState=["x":"\(point.x)","y":"\(point.y)"];runtime.noteTextResponseInput()
        XCTAssertTrue(runtime.checkpointDraft(store:f.store));runtime.releaseWriter()
        let repository=NFLocalSessionRepository(url:f.root.appending(path:"sessions-v1.json"),ownerDeviceID:f.owner,editorialAdmissions:f.admissions)
        XCTAssertNil(repository.loadError)
        let coldStore=newStore(container:f.container,root:f.root,repository:repository,suffix:"cold")
        let envelope=try XCTUnwrap(repository.archive.sessions.first { $0.id == runtime.sessionID })
        var request=envelope.request;request.localCheckpoint=envelope.checkpoint;request.localSessionID=envelope.id
        let cold=NFUniversalSessionRuntime(request:request);defer { cold.releaseWriter() }
        XCTAssertNil(cold.unavailableReason);XCTAssertEqual(cold.logicState,runtime.logicState);XCTAssertEqual(cold.exercise,value)
        XCTAssertFalse(cold.isDurablyPrepared)
        XCTAssertTrue(cold.checkpointDraft(store:coldStore))
        cold.resume();cold.acknowledgePresented()
        XCTAssertEqual(repository.archive.selectionLedger?.slots[cold.reviewedSlotID.uuidString]?.status,.presented)
        cold.submitInline(store:coldStore)
        XCTAssertEqual(cold.lastResult?.outcome,.correct)
        let record=try XCTUnwrap(coldStore.attempts.first { $0.itemID == value.id && $0.sessionID == runtime.sessionID })
        let capture=try XCTUnwrap(repository.editorialSnapshot(for:record.id)?.editorialCapture)
        XCTAssertEqual(capture.runtimeWitness?.admission.demand.editorialBand,.b2)
        XCTAssertEqual(capture.runtimeWitness?.admission.demand.familyID,f.activity.id)
        let observations=try [first,record].map { try XCTUnwrap(coldStore.effectiveAttemptDTO($0).editorialObservation) }
        let evidence=EditorialBandEvidenceV1.reduce(observations,decisionDayOrdinal:capture.day.ordinal)
        XCTAssertEqual(Set(observations.compactMap { $0.item?.editorialBand }),[.b1,.b2])
        XCTAssertTrue(evidence.summaries.allSatisfy { $0.lastDemonstratedAt == nil })
        cold.next(store:coldStore);XCTAssertEqual(cold.index,2)
        XCTAssertEqual(try receipt(cold,store:coldStore).selection.deliveredBand,.b2)
    }
    func testInvalidTypedInputAndCurrentExclusionCannotContributeEligibleCoordinateEvidence() throws {
        let f=try fixture();defer { withExtendedLifetime(f.container) {} }
        let runtime=try launch(f,count:2);defer { runtime.releaseWriter() }
        runtime.logicState=["x":"not a coordinate","y":"0"];runtime.submitInline(store:f.store)
        XCTAssertTrue(f.store.attempts.isEmpty);XCTAssertEqual(runtime.stage,.item)
        let record=try answer(runtime,store:f.store)
        let original=try NFImmutableAttemptRecordSnapshot.encoded(NFImmutableAttemptRecordSnapshot(record))
        let snapshot=try XCTUnwrap(f.store.localSessions.editorialSnapshot(for:record.id))
        let projected=NFEditorialCommitCapturePolicy.project(snapshot:snapshot,record:.init(record),effectiveCredit:record.deterministicCredit,
            excluded:true,admissions:f.admissions,localAuthorityVerified:true)
        XCTAssertNil(projected.observation);XCTAssertEqual(projected.exclusionReason,"effectiveEvidenceExcluded")
        XCTAssertEqual(try NFImmutableAttemptRecordSnapshot.encoded(NFImmutableAttemptRecordSnapshot(record)),original)
        let unverified=NFEditorialCommitCapturePolicy.project(snapshot:snapshot,record:.init(record),effectiveCredit:record.deterministicCredit,
            excluded:false,admissions:f.admissions,localAuthorityVerified:false)
        XCTAssertNil(unverified.observation)
        // Exercise the real current-validity caller as well as the pure adapter.
        // An append-only item report suppresses effective evidence, never the
        // immutable original response or its originally awarded credit.
        try f.store.saveItemReport(exercise:snapshot.exercise,reason:"QA.quarantine",note:"Synthetic coordinate validity change")
        XCTAssertNil(f.store.effectiveAttemptDTO(record).editorialObservation)
        runtime.next(store:f.store)
        let next=try receipt(runtime,store:f.store)
        XCTAssertEqual(next.evidence.exclusions[record.id.uuidString],"contentExcluded")
        XCTAssertEqual(next.selection.deliveredBand,.b1)
        XCTAssertEqual(try NFImmutableAttemptRecordSnapshot.encoded(NFImmutableAttemptRecordSnapshot(record)),original)
        XCTAssertEqual(record.deterministicCredit,1)
    }
    func testReleasedEmptyRegistryKeepsCoordinatePracticeAvailableWithoutReviewedAuthority() async throws {
        let f=try fixture(released:true);defer { withExtendedLifetime(f.container) {} }
        XCTAssertTrue(NFEditorialAdmissionContext.released.entries.isEmpty)
        let preview=try await f.store.reviewedStartingPreview(request:f.request,catalogScope:f.scope)
        XCTAssertEqual(preview.state,.registryUnavailable);XCTAssertTrue(preview.choices.isEmpty)
        XCTAssertTrue(f.store.beginDefaultCatalogSession(.init(activity:f.activity,field:.general),requestedItemCount:1,timingCondition:.init(.untimed)))
        let runtime=NFUniversalSessionRuntime(request:try XCTUnwrap(f.store.activeSessionRequest));defer { runtime.releaseWriter() }
        XCTAssertTrue(runtime.checkpointDraft(store:f.store));runtime.resume();runtime.acknowledgePresented()
        XCTAssertNotNil(NFCoordinateTransformContract.make(exercise:runtime.exercise))
        XCTAssertNil(runtime.request.ordinaryDelivery?.editorialPolicy)
        let record=try answer(runtime,store:f.store)
        XCTAssertNil(f.store.effectiveAttemptDTO(record).editorialObservation)
        XCTAssertNotEqual(f.store.localSessions.editorialSnapshot(for:record.id)?.editorialCapture?.authorityAtCommit,"admitted")
    }
}


extension CoordinateTransformContractTests {
    func testCoordinatePartialRubricOwnsBothFieldCreditsAndRejectsRetainedContradiction() throws {
        let task=try XCTUnwrap(G.tasks.first),exercise=try generated(task),answer=try XCTUnwrap(task.answer)
        let contract=try XCTUnwrap(NFCoordinateTransformContract.make(exercise:exercise))
        XCTAssertEqual(exercise.rubric,contract.rubric)
        XCTAssertTrue(exercise.rubric.permitsPartialCredit)
        XCTAssertEqual(exercise.rubric.criteria.map(\.weight),[0.5,0.5])
        for correctX in [true,false] {
            let response=NFExerciseResponse.logicState(.init(finalState:["x":String(answer.x+(correctX ? 0:1)),"y":String(answer.y+(correctX ? 1:0))],violatedRuleID:nil))
            let result=NFExerciseScoringEngine.score(response,for:exercise)
            XCTAssertEqual(result.outcome,.partial);XCTAssertFalse(result.isCorrect);XCTAssertEqual(result.credit,0.5)
            XCTAssertEqual(result.components.count,2)
            XCTAssertEqual(result.components.first{$0.id == "x"}?.awardedCredit,correctX ? 0.5:0)
            XCTAssertEqual(result.components.first{$0.id == "y"}?.awardedCredit,correctX ? 0:0.5)
            XCTAssertEqual(result.components.reduce(0){$0+$1.awardedCredit},result.credit)
        }
        var malformed=try XCTUnwrap(JSONSerialization.jsonObject(with:JSONEncoder().encode(exercise)) as? [String:Any])
        var rubric=try XCTUnwrap(malformed["rubric"] as? [String:Any]);rubric["permitsPartialCredit"]=false;malformed["rubric"]=rubric
        let frozen=try JSONDecoder().decode(NFExercise.self,from:JSONSerialization.data(withJSONObject:malformed)),bytes=try NFImmutableAttemptRecordSnapshot.encoded(frozen)
        XCTAssertNil(NFCoordinateTransformContract.make(exercise:frozen))
        XCTAssertEqual(NFExerciseScoringEngine.score(.logicState(.init(finalState:["x":String(answer.x),"y":String(answer.y+1)],violatedRuleID:nil)),for:frozen).outcome,.invalidItem)
        XCTAssertEqual(try NFImmutableAttemptRecordSnapshot.encoded(frozen),bytes)
        let legacy=try NFFallbackExerciseGenerator.generate(.init(seed:11,index:0,lab:.logicDebugging,purpose:.practice,preferredAssessmentMechanicID:"fixture.fallback-variant-0"))
        guard case let .logicState(schema)=legacy.interaction else { return XCTFail("Expected a real legacy structured exact contract") }
        XCTAssertTrue(legacy.rubric.permitsPartialCredit)
        var wrong=schema.expectedFinalState;let key="count";wrong[key]="999999"
        let result=NFExerciseScoringEngine.score(.logicState(.init(finalState:wrong,violatedRuleID:schema.expectedViolatedRuleID)),for:legacy)
        XCTAssertEqual(result.credit,0.6,accuracy:0.00000001);XCTAssertFalse(result.isCorrect)
    }
}

extension ReviewedCoordinateProtocolTests {
    func testActualDetachedCoordinatePreviewAndMaterializationStayWithinWorkerStackAndReadOnly() async throws {
        let f=try fixture();defer { withExtendedLifetime(f.container) {} }
        let original=try NFImmutableAttemptRecordSnapshot.encoded(f.store.localSessions.archive)
        let preview=try await f.store.reviewedStartingPreview(request:f.request,catalogScope:f.scope)
        XCTAssertEqual(preview.state,.feasible)
        XCTAssertTrue(preview.choices.contains{$0.scope == f.family && $0.band == .b1})
        let request=f.request,entry=try XCTUnwrap(f.admissions.entries.first)
        let ordinal=try XCTUnwrap(NFOfflineQuestionBank.ordinal(forQuestionID:entry.bankQuestionID,lab:.spatial))
        let exercise=await Task.detached(priority:.userInitiated) {
            NFDeterministicSessionExerciseFactory.makeExercise(request:request.launchOnly(offlineQuestionOrdinals:[ordinal]),index:0,assessmentDescriptor:nil)
        }.value
        XCTAssertNotNil(NFCoordinateTransformContract.make(exercise:exercise))
        XCTAssertEqual(try NFLocalItemCheckpoint.digest(exercise),entry.exerciseDigest)
        XCTAssertTrue(exercise.rubric.permitsPartialCredit)
        XCTAssertTrue(f.store.attempts.isEmpty);XCTAssertNil(f.store.activeSessionRequest)
        XCTAssertEqual(try NFImmutableAttemptRecordSnapshot.encoded(f.store.localSessions.archive),original)
    }
}

extension RetrievalWorkerStackTests {
    func testUnavailableWorkerMaterializationPreservesExactFallbackForInvalidAndExhaustedRequests() async throws {
        for locale in ["en_US", "ja_JP"] {
            for lab in TrainingLab.allCases {
                var invalid = SessionRequest(lab: lab, source: .focused, seed: 71,
                    localeIdentifier: locale, requestedItemCount: 1, isTimed: false)
                invalid.tracePolicyVersion = 999
                let expected = NFDeterministicSessionExerciseFactory.makeExercise(request: invalid, index: 0, assessmentDescriptor: nil)
                let request = invalid
                let actual = await Task.detached {
                    NFDeterministicSessionExerciseFactory.makeExercise(request: request, index: 0, assessmentDescriptor: nil)
                }.value
                XCTAssertNotNil(actual.availabilityReason)
                XCTAssertEqual(try NFImmutableAttemptRecordSnapshot.encoded(actual), try NFImmutableAttemptRecordSnapshot.encoded(expected))
                XCTAssertEqual(NFExerciseScoringEngine.score(.shortText("unavailable"), for: actual).outcome, .invalidItem)
            }
            let request = SessionRequest(lab: .mentalMath, source: .focused, seed: 71,
                localeIdentifier: locale, requestedItemCount: 1, offlineQuestionOrdinals: [0], isTimed: false)
            let original = NFDeterministicSessionExerciseFactory.makeExercise(request: request, index: 0, assessmentDescriptor: nil)
            XCTAssertNil(original.availabilityReason)
            let excluded: Set<String> = [NFQuestionFingerprint.fingerprint(for: original)]
            let captured = request
            let unavailable = await Task.detached {
                NFDeterministicSessionExerciseFactory.makeExercise(request: captured, index: 0,
                    assessmentDescriptor: nil, excludingContentFingerprints: excluded)
            }.value
            XCTAssertNotNil(unavailable.availabilityReason)
            XCTAssertEqual(NFExerciseScoringEngine.score(.shortText("unavailable"), for: unavailable).outcome, .invalidItem)
        }
    }
}


@MainActor
final class SolidSectionContractTests:XCTestCase {
    private typealias G=NFSolidSectionGeometry
    private func store() throws -> (AppStore,ModelContainer,URL) {
        let container=try ModelContainer(for:Schema(NFSchemaV1.models),configurations:ModelConfiguration(isStoredInMemoryOnly:true))
        var draft=OnboardingDraft();draft.aiMode = .disabled
        container.mainContext.insert(UserProfileRecord(draft:draft));try container.mainContext.save()
        let root=FileManager.default.temporaryDirectory.appending(path:"NF-Solid-Section-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
        addTeardownBlock { try? FileManager.default.removeItem(at:root) }
        let repository=NFLocalSessionRepository(url:root.appending(path:"sessions.json"),ownerDeviceID:UUID())
        return (AppStore(context:container.mainContext,nextDayEnhancementCache:NFNextDayEnhancementCache(rootURL:root.appending(path:"cache")),
            documentStorageRootURL:root.appending(path:"documents"),localSessionRepository:repository,
            adaptivePlanHistoryRepository:NFAdaptivePlanHistoryRepository(fileURL:root.appending(path:"history.json")),
            offlineQuestionRotation:NFOfflineQuestionRotation(store:NFMemoryOfflineQuestionRotationStateStore()),
            temporaryArtifactsRootURL:root.appending(path:"temporary"),allowsSharedWidgetPublishing:false),container,root)
    }
    private func generationRequest(_ task:G.Task,locale:String="en_US",purpose:NFExercisePurpose = .practice) throws -> NFExerciseGenerationRequest {
        let target=try XCTUnwrap(G.representatives.firstIndex(of:task)),mechanic="fixture.fallback-variant-2"
        func selected(_ seed:UInt64)->Int {
            let discriminator="\(seed):0:\(TrainingLab.spatial.rawValue):\(purpose.rawValue):automatic:\(mechanic):no-transfer-brief:4"
            var hash:UInt64=0xcbf29ce484222325
            for byte in discriminator.utf8 { hash=(hash ^ UInt64(byte)) &* 0x100000001b3 }
            var state=seed ^ hash;if state == 0 { state=0x9E3779B97F4A7C15 };state &+= 0x9E3779B97F4A7C15
            var v=(state ^ (state >> 30)) &* 0xBF58476D1CE4E5B9;v=(v ^ (v >> 27)) &* 0x94D049BB133111EB
            return Int((v ^ (v >> 31)) % UInt64(G.representatives.count))
        }
        let seed=try XCTUnwrap((UInt64(0)..<30_000).first{selected($0)==target})
        return .init(seed:seed,index:0,lab:.spatial,purpose:purpose,localeIdentifier:locale,
            preferredAssessmentMechanicID:mechanic,spatialStructurePolicyVersion:1,coordinateTransformPolicyVersion:1,solidSectionPolicyVersion:1)
    }
    private func generate(_ task:G.Task,locale:String="en_US",purpose:NFExercisePurpose = .practice) throws -> NFExercise {
        try NFFallbackExerciseGenerator.generate(generationRequest(task,locale:locale,purpose:purpose))
    }
    private func response(_ exercise:NFExercise)->NFExerciseResponse {
        switch exercise.interaction {
        case let .numeric(s):return .numeric(.init(value:s.answer.authoritativeValue.canonicalString,unit:nil))
        case let .singleChoice(s):return .singleChoice(optionID:s.correctOptionID)
        default:return .shortText("Unexpected response")
        }
    }
    private func enter(_ exercise:NFExercise,runtime:NFUniversalSessionRuntime) {
        switch response(exercise) {
        case let .numeric(s):runtime.numericValue=s.value
        case let .singleChoice(id):runtime.singleChoiceID=id
        default:break
        }
    }
    /// Independent three-plane linear-system oracle: pair each two cube face
    /// equations with the slice, solve by Cramer's rule, then apply six bounds.
    private func cubeOracle(_ p:G.Plane)->Set<G.Point> {
        func determinant(_ m:[[Double]])->Double {
            m[0][0]*(m[1][1]*m[2][2]-m[1][2]*m[2][1])-m[0][1]*(m[1][0]*m[2][2]-m[1][2]*m[2][0])+m[0][2]*(m[1][0]*m[2][1]-m[1][1]*m[2][0])
        }
        var result:Set<G.Point>=[]
        for i in 0..<3 { for j in (i+1)..<3 { for x in [-2.0,2.0] { for y in [-2.0,2.0] {
            let m=[p.normal.vector,(0..<3).map{$0==i ? 1.0:0},(0..<3).map{$0==j ? 1.0:0}],b=[p.offset,x,y],denominator=determinant(m)
            if denominator == 0 { continue }
            let v=(0..<3).map { column in determinant((0..<3).map { row in (0..<3).map { c in c == column ? b[row]:m[row][c] } })/denominator }
            if v.allSatisfy({abs($0)<=2}) { result.insert(.init(x:v[0],y:v[1],z:v[2])) }
        } } } }
        return result
    }
    func testEveryFiniteGeometryCaseMatchesIndependentOracleAndItsRenderedBoundary() throws {
        XCTAssertEqual(G.tasks.count,370)
        for task in G.tasks {
            XCTAssertTrue(task.isBounded);let shape=try XCTUnwrap(task.shape),p=task.plane
            switch task.solid {
            case .cube:XCTAssertEqual(Set(task.cubeVertices),cubeOracle(p))
            case .sphere:
                let numerator=36*p.normSquared-p.twiceOffset*p.twiceOffset
                XCTAssertEqual(task.radiusSquared,try NFExactNumber(numerator:Int64(numerator),denominator:Int64(4*p.normSquared)))
                XCTAssertEqual(shape,numerator<0 ? .empty:numerator==0 ? .point:.circle)
            case .cylinder:
                let support=2*hypot(Double(p.a),Double(p.b))+3*Double(abs(p.c)),d=abs(p.offset)
                let expected:G.Shape
                if d>support { expected = .empty }
                else if p.c==0 { expected=d==support ? .segment:.rectangle }
                else if p.a==0 && p.b==0 { expected = .circle }
                else if d==support { expected = .point }
                else { expected=d+2*hypot(Double(p.a),Double(p.b))<=3*Double(abs(p.c)) ? .ellipse:.clippedEllipse }
                XCTAssertEqual(shape,expected)
            }
            for v in task.boundary {
                XCTAssertEqual(p.normal.dot(v),p.offset,accuracy:1e-8)
                switch task.solid {
                case .cube:XCTAssertTrue(v.vector.allSatisfy{abs($0)<=2+1e-8})
                case .sphere:XCTAssertEqual(v.squaredLength,9,accuracy:1e-7)
                case .cylinder:XCTAssertLessThanOrEqual(v.x*v.x+v.y*v.y,4+1e-8);XCTAssertLessThanOrEqual(abs(v.z),3+1e-8)
                }
            }
            if case let .verify(proposed,q)=task.query { XCTAssertEqual(task.verifiesClaim,shape.dimension==2 && shape==proposed && p.normal.dot(q)==p.offset) }
        }
        XCTAssertTrue(G.tasks.contains{$0.shape == .pentagon});XCTAssertTrue(G.tasks.contains{$0.shape == .hexagon})
        XCTAssertTrue(G.tasks.contains{$0.verifiesClaim == true});XCTAssertTrue(G.tasks.contains{$0.verifiesClaim == false})
    }
    func testAllDeliveredContractsHaveExactKeysExclusiveChoicesAndBothLocalizedRepresentations() throws {
        for task in G.representatives { for locale in ["en_US","ja_JP"] {
            let value=try generate(task,locale:locale),contract=try XCTUnwrap(NFSolidSectionContract.make(exercise:value))
            XCTAssertEqual(contract.task,task);XCTAssertEqual(value.schemaVersion,10);XCTAssertEqual(value.generatorVersion,13)
            XCTAssertTrue(value.id.contains(".r13."));XCTAssertEqual(value.contractMetadata?.familyID,NFSolidSectionContract.familyID)
            XCTAssertEqual(value.representations,[.spatial(contract.representation)]);XCTAssertEqual(value.rubric,contract.rubric)
            XCTAssertEqual(value.independentRepresentations,value.representations);XCTAssertNil(value.contextText)
            XCTAssertEqual(contract.representation.viewpoint,contract.representation.difficultyParameters.viewpoint)
            XCTAssertEqual(NFExerciseScoringEngine.score(response(value),for:value).outcome,.correct)
            XCTAssertEqual(NFQuestionFingerprint.fingerprint(for:value),value.contractMetadata?.semanticFingerprint)
            XCTAssertNil(value.contractMetadata?.editorialDemand)
            switch value.interaction {
            case let .singleChoice(s):
                XCTAssertEqual(Set(s.options.map(\.text)).count,s.options.count)
                for option in s.options { XCTAssertEqual(NFExerciseScoringEngine.score(.singleChoice(optionID:option.id),for:value).credit,option.id==s.correctOptionID ? 1:0) }
            case let .numeric(s):
                let number=s.answer.authoritativeValue
                let equivalent="\(number.numerator*2)/\(number.denominator*2)"
                let exactResult=NFExerciseScoringEngine.score(.numeric(.init(value:equivalent,unit:nil)),for:value)
                XCTAssertEqual(exactResult.credit,1);XCTAssertEqual(exactResult.expectedAnswerSummary,contract.exactAnswerSummary)
                XCTAssertTrue(exactResult.expectedAnswerSummary?.hasPrefix(number.canonicalString) == true)
                XCTAssertEqual(NFExerciseScoringEngine.score(.numeric(.init(value:"999",unit:nil)),for:value).credit,0)
            default:XCTFail("Unsupported section answer form")
            }
        } }
    }
    func testSymmetryAndRepeatedShapeClassesDoNotInflateCapacity() throws {
        XCTAssertEqual(G.representatives.count,Set(G.tasks.map(\.identity)).count)
        XCTAssertLessThan(G.representatives.count,G.tasks.count)
        let x=G.Task(solid:.cube,plane:.init(a:1,b:0,c:0,twiceOffset:0),query:.classify)
        let z=G.Task(solid:.cube,plane:.init(a:0,b:0,c:-1,twiceOffset:2),query:.classify)
        XCTAssertEqual(x.identity,z.identity,"Parallel interior square slices retain one classification structure")
        let a=G.Task(solid:.sphere,plane:.init(a:0,b:0,c:1,twiceOffset:2),query:.classify)
        let b=G.Task(solid:.sphere,plane:.init(a:1,b:1,c:0,twiceOffset:2),query:.classify)
        XCTAssertEqual(a.identity,b.identity,"A different circle radius is not another shape-classification query")
        let radiusA=G.Task(solid:.sphere,plane:a.plane,query:.sphereRadiusSquared),radiusB=G.Task(solid:.sphere,plane:b.plane,query:.sphereRadiusSquared)
        XCTAssertNotEqual(radiusA.identity,radiusB.identity,"The requested squared-radius values actually differ")
        XCTAssertNil(G.Task(solid:.cylinder,plane:.init(a:2,b:1,c:1,twiceOffset:0),query:.classify).shape)
    }
    func testFutureMalformedProtectedAndMissingRecipeCannotUseOrdinarySectionAuthority() throws {
        let task=try XCTUnwrap(G.representatives.first),value=try generate(task)
        var future=value;future.contractMetadata?.solidSection?.policyVersion=999
        XCTAssertFalse(future.hasSupportedSolidSection);XCTAssertEqual(NFExerciseScoringEngine.score(response(value),for:future).outcome,.invalidItem)
        var missing=value;missing.contractMetadata?.solidSection=nil
        XCTAssertFalse(missing.hasSupportedSolidSection)
        var raw=try XCTUnwrap(JSONSerialization.jsonObject(with:JSONEncoder().encode(value)) as? [String:Any]);raw["assessmentProtected"]=true
        let protected=try JSONDecoder().decode(NFExercise.self,from:JSONSerialization.data(withJSONObject:raw))
        XCTAssertNil(NFSolidSectionContract.make(exercise:protected))
        XCTAssertThrowsError(try NFFallbackExerciseGenerator.generate(.init(seed:0,index:0,lab:.spatial,purpose:.baseline,solidSectionPolicyVersion:1)))
        let legacy=try NFFallbackExerciseGenerator.generate(.init(seed:0,index:0,lab:.spatial,purpose:.practice,preferredAssessmentMechanicID:"fixture.fallback-variant-2"))
        XCTAssertEqual(legacy.generatorVersion,4);XCTAssertEqual(legacy.schemaVersion,2);XCTAssertNil(legacy.contractMetadata?.solidSection)
        var request=SessionRequest(lab:.spatial,source:.focused,seed:0);request.solidSectionPolicyVersion=1
        XCTAssertFalse(request.permitsSolidSection(exercise:legacy));request.solidSectionPolicyVersion=nil
        XCTAssertTrue(request.permitsSolidSection(exercise:legacy));XCTAssertFalse(request.permitsSolidSection(exercise:value))
        request.solidSectionPolicyVersion=999;XCTAssertNotNil(NFDeterministicSessionExerciseFactory.makeExercise(request:request,index:0,assessmentDescriptor:nil).availabilityReason)
    }
    func testSectionReplayIsPostResponseOnlyAndResetPreservesOriginalGeometry() throws {
        let task=try XCTUnwrap(G.representatives.first{$0.shape == .hexagon}),exercise=try generate(task)
        let contract=try XCTUnwrap(NFSolidSectionContract.make(exercise:exercise)),bytes=try NFImmutableAttemptRecordSnapshot.encoded(exercise)
        var copy=NFSolidSectionInspectionState()
        XCTAssertFalse(copy.reveal(contract:contract,phase:.independent));XCTAssertFalse(copy.showsSection)
        let independent=NFSpatialRealitySceneFactory.makeSectionScene(contract:contract,showsSection:false)
        XCTAssertFalse(independent.children.contains{$0.name.hasPrefix("worked.")})
        XCTAssertTrue(independent.children.contains{$0.name.hasPrefix("given.plane")})
        XCTAssertTrue(copy.reveal(contract:contract,phase:.committedFeedback));XCTAssertTrue(copy.showsSection)
        let feedback=NFSpatialRealitySceneFactory.makeSectionScene(contract:contract,showsSection:true)
        XCTAssertTrue(feedback.children.contains{$0.name.hasPrefix("worked.section")})
        copy.reset();XCTAssertFalse(copy.showsSection)
        // Static projections agree with the actual native camera orientation,
        // including the mathematical z-up to RealityKit y-up basis change.
        for camera in ["Authored view","Front","Side","Top"] {
            let rotation:simd_quatf
            switch camera {
            case "Authored view":rotation=simd_quatf(angle:Float(atan(1/sqrt(2.0))),axis:[1,0,0])*simd_quatf(angle:-.pi/4,axis:[0,1,0])
            case "Side":rotation=simd_quatf(angle:-.pi/2,axis:[0,1,0])
            case "Top":rotation=simd_quatf(angle:.pi/2,axis:[1,0,0])
            default:rotation=simd_quatf(angle:0,axis:[0,1,0])
            }
            for p in G.Task.corners {
                let native=rotation.act(SIMD3<Float>(Float(p.x),Float(p.z),-Float(p.y)))
                let projected=NFSolidSectionDrawingGeometry.project(p,camera:camera)
                XCTAssertEqual(Double(projected.x),Double(native.x),accuracy:1e-6)
                XCTAssertEqual(Double(projected.y),-Double(native.y),accuracy:1e-6)
            }
        }
        XCTAssertEqual(try NFImmutableAttemptRecordSnapshot.encoded(exercise),bytes)
    }
    func testActualOrdinaryColdResponseCommitAndNextKeepSameFamilyExactHistoryAndRecipe() throws {
        let (store,container,_)=try store();defer{withExtendedLifetime(container){}}
        let activity=try XCTUnwrap(NFDefaultContentCatalog.activity(id:NFSolidSectionContract.familyID))
        XCTAssertTrue(store.beginDefaultCatalogSession(.init(activity:activity,field:.general),requestedItemCount:3,timingCondition:.init(.untimed)))
        let request=try XCTUnwrap(store.activeSessionRequest),runtime=NFUniversalSessionRuntime(request:request)
        XCTAssertTrue(runtime.checkpointDraft(store:store));runtime.resume();runtime.acknowledgePresented()
        let value=runtime.exercise;XCTAssertNotNil(NFSolidSectionContract.make(exercise:value));enter(value,runtime:runtime)
        XCTAssertTrue(runtime.checkpointDraft(store:store));runtime.releaseWriter()
        let envelope=try XCTUnwrap(store.localSessions.archive.sessions.first{$0.id==runtime.sessionID})
        var resume=envelope.request;resume.localSessionID=envelope.id;resume.localCheckpoint=envelope.checkpoint
        let cold=NFUniversalSessionRuntime(request:resume);defer{cold.releaseWriter()}
        XCTAssertTrue(cold.checkpointDraft(store:store));cold.resume();cold.acknowledgePresented()
        XCTAssertEqual(cold.exercise,value);XCTAssertEqual(cold.numericValue,runtime.numericValue);XCTAssertEqual(cold.singleChoiceID,runtime.singleChoiceID)
        cold.submitInline(store:store);XCTAssertEqual(cold.lastResult?.outcome,.correct);XCTAssertNil(cold.saveError)
        let record=try XCTUnwrap(store.attempts.first);XCTAssertEqual(store.exerciseSnapshot(for:record.id),value)
        XCTAssertEqual(try JSONDecoder().decode(NFExerciseResponse.self,from:Data(record.response.utf8)),response(value))
        cold.next(store:store);XCTAssertEqual(cold.index,1);XCTAssertNil(cold.nextUnavailableReason)
        XCTAssertEqual(cold.exercise.contractMetadata?.familyID,NFSolidSectionContract.familyID)
        XCTAssertNotEqual(cold.exercise.contractMetadata?.semanticFingerprint,value.contractMetadata?.semanticFingerprint)
    }
    func testGeneratedRadiusKeepsExactRationalDraftAndUsesSameAuthorityAfterColdRestore() throws {
        let (store,container,_)=try store();defer{withExtendedLifetime(container){}}
        let task=try XCTUnwrap(G.representatives.first { if case .sphereRadiusSquared=$0.query{return $0.radiusSquared?.denominator != 1};return false })
        let exercise=try generate(task,purpose:.documentPractice),id=UUID(),answer=try XCTUnwrap(task.radiusSquared)
        let request=NFAuthoringRequest(id:id,capability:.contextualize,lab:.spatial,field:.general,customTopic:"Synthetic solid section",learningObjective:"Find the squared radius of a plane section",style:.spatialTransformation,difficulty:0.5,count:1,localeIdentifier:"en_US",seed:1,aiMode:.disabled)
        let question=NFAuthoredQuestion(id:exercise.id,lab:.spatial,style:.spatialTransformation,prompt:exercise.prompt,context:"",choices:[],correctAnswer:answer.canonicalString,acceptedAnswers:[],explanation:exercise.feedback.correctExplanation,hint:exercise.feedback.hintLadder[0],decisiveStep:exercise.feedback.decisiveStep,difficulty:0.5,citationChunkIDs:[],evidenceClass:.documentPractice,authoritativeExercise:exercise)
        XCTAssertTrue(NFAuthoredExerciseAuthority.validatesBinding(question))
        let result=NFAuthoringResult(questions:[question],provenance:.init(requestID:id,generatedAt:Date().addingTimeInterval(-1),route:.deterministicFallback,routeReason:"Synthetic retained section",promptVersion:1,modelIdentifier:"synthetic.section",sourceChunkIDs:[],sourceDocumentIDs:[],validationVersion:1,repairCount:0,cacheKey:"synthetic.section",isFallback:true),routeCandidates:[],validationStatus:.init(level:.deterministicKey,sourceSupport:.notApplicable),validationNotes:[])
        let runtime=AIGeneratedPracticeRuntime(result:result,request:request);XCTAssertTrue(runtime.checkpoint(store:store));runtime.resume()
        runtime.numericValue="\(answer.numerator*2)/\(answer.denominator*2)";XCTAssertTrue(runtime.checkpoint(store:store))
        let draft=try XCTUnwrap(store.generatedPracticeDraft(for:id));runtime.releaseWriter()
        let cold=AIGeneratedPracticeRuntime(result:result,request:request,draft:draft);defer{cold.releaseWriter()}
        XCTAssertTrue(cold.restoreCheckpoint(store:store));cold.resume();XCTAssertEqual(cold.numericValue,runtime.numericValue)
        cold.submit(store:store);XCTAssertEqual(cold.lastScore?.outcome,.correct)
        let record=try XCTUnwrap(store.attempts.first);XCTAssertEqual(store.exerciseSnapshot(for:record.id),exercise)
    }
    func testDetachedProducerValidatesEveryNewSectionRepresentationWithoutChangingLegacyRecipe() async throws {
        let tasks=G.representatives
        for task in tasks.prefix(12) {
            let request=try generationRequest(task),exercise=try NFFallbackExerciseGenerator.generate(request)
            // Actual direct producer on a normal worker stack, including its
            // mandatory complete post-construction schema and taxonomy checks.
            let value=try await Task.detached(priority:.userInitiated) {
                try NFFallbackExerciseGenerator.generate(request)
            }.value
            XCTAssertNotNil(NFSolidSectionContract.make(exercise:value));XCTAssertEqual(value,exercise)
        }
    }
}

extension SolidSectionContractTests {
    func testActualFactoryReachabilitySeparatesFocusedQuestionsFromLegacyMixedBankDescriptors() async throws {
        let activity=try XCTUnwrap(NFDefaultContentCatalog.activity(id:NFSolidSectionContract.familyID))
        var focused=SessionRequest(lab:.spatial,source:.focused,seed:20260905,localeIdentifier:"en",field:.general,
            requestedItemCount:50,isTimed:false,timingCondition:.init(.untimed),mechanicID:activity.mechanicID)
        focused.solidSectionPolicyVersion=1
        var mixed=SessionRequest(lab:.spatial,source:.focused,seed:20260905,localeIdentifier:"en",field:.general,
            requestedItemCount:50,isTimed:false,timingCondition:.init(.untimed))
        mixed.solidSectionPolicyVersion=1
        let focusedRequest=focused,mixedRequest=mixed
        let census=await Task.detached(priority:.userInitiated) { () -> (Set<String>,Set<String>,Int) in
            var focusedIDs:Set<String>=[],mixedIDs:Set<String>=[],unavailable=0
            for index in 0..<50 {
                let value=NFDeterministicSessionExerciseFactory.makeExercise(request:focusedRequest,index:index,
                    assessmentDescriptor:nil,excludingContentFingerprints:focusedIDs)
                if let contract=NFSolidSectionContract.make(exercise:value) { focusedIDs.insert(NFQuestionFingerprint.solidSectionFingerprint(identity:contract.task.identity)) }
                else { unavailable+=1 }
            }
            for ordinal in 0..<NFOfflineQuestionBank.questionsPerLab {
                let value=NFDeterministicSessionExerciseFactory.makeExercise(request:mixedRequest.launchOnly(offlineQuestionOrdinals:[ordinal]),index:0,assessmentDescriptor:nil)
                if let contract=NFSolidSectionContract.make(exercise:value) { mixedIDs.insert(NFQuestionFingerprint.solidSectionFingerprint(identity:contract.task.identity)) }
            }
            return(focusedIDs,mixedIDs,unavailable)
        }.value
        XCTAssertEqual(census.0.count,50);XCTAssertEqual(census.2,0)
        XCTAssertGreaterThan(census.1.count,0);XCTAssertLessThanOrEqual(census.1.count,3)
        print("SOLID_SECTION_REACHABILITY focused50=\(census.0.count), unavailable=\(census.2), legacyMixedSemanticClasses=\(census.1.count), finiteAuthoredClasses=\(G.representatives.count)")
    }
}


@MainActor
final class CubeFoldingContractTests:XCTestCase {
    private typealias G=NFNetFoldingGeometry
    private func store() throws -> (AppStore,ModelContainer,URL) {
        let container=try ModelContainer(for:Schema(NFSchemaV1.models),configurations:ModelConfiguration(isStoredInMemoryOnly:true))
        var draft=OnboardingDraft();draft.aiMode = .disabled
        container.mainContext.insert(UserProfileRecord(draft:draft));try container.mainContext.save()
        let root=FileManager.default.temporaryDirectory.appending(path:"NF-Cube-Folding-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
        addTeardownBlock{try? FileManager.default.removeItem(at:root)}
        return(AppStore(context:container.mainContext,nextDayEnhancementCache:NFNextDayEnhancementCache(rootURL:root.appending(path:"cache")),documentStorageRootURL:root.appending(path:"documents"),
            localSessionRepository:NFLocalSessionRepository(url:root.appending(path:"sessions.json"),ownerDeviceID:UUID()),
            adaptivePlanHistoryRepository:NFAdaptivePlanHistoryRepository(fileURL:root.appending(path:"history.json")),offlineQuestionRotation:NFOfflineQuestionRotation(store:NFMemoryOfflineQuestionRotationStateStore()),
            temporaryArtifactsRootURL:root.appending(path:"temporary"),allowsSharedWidgetPublishing:false),container,root)
    }
    private func request(_ task:G.Task,locale:String="en_US",purpose:NFExercisePurpose = .practice) throws -> NFExerciseGenerationRequest {
        let target=try XCTUnwrap(G.tasks.firstIndex(of:task)),mechanic="fixture.fallback-variant-4"
        func selected(_ seed:UInt64)->Int {
            let input="\(seed):0:\(TrainingLab.spatial.rawValue):\(purpose.rawValue):automatic:\(mechanic):no-transfer-brief:4"
            var h:UInt64=0xcbf29ce484222325;for byte in input.utf8{h=(h ^ UInt64(byte)) &* 0x100000001b3}
            var state=seed ^ h;if state == 0{state=0x9E3779B97F4A7C15};state &+= 0x9E3779B97F4A7C15
            var value=(state ^ (state>>30)) &* 0xBF58476D1CE4E5B9;value=(value ^ (value>>27)) &* 0x94D049BB133111EB
            return Int((value ^ (value>>31)) % UInt64(G.tasks.count))
        }
        let seed=try XCTUnwrap((UInt64(0)..<40_000).first{selected($0)==target})
        return .init(seed:seed,index:0,lab:.spatial,purpose:purpose,localeIdentifier:locale,preferredAssessmentMechanicID:mechanic,netFoldingPolicyVersion:1)
    }
    private func generate(_ task:G.Task,locale:String="en_US",purpose:NFExercisePurpose = .practice) throws -> NFExercise {
        try NFFallbackExerciseGenerator.generate(request(task,locale:locale,purpose:purpose))
    }
    private func response(_ exercise:NFExercise)->NFExerciseResponse {
        switch exercise.interaction{case let .singleChoice(s):.singleChoice(optionID:s.correctOptionID);case let .multipleChoice(s):.multipleChoice(optionIDs:s.correctOptionIDs);default:.shortText("Unexpected interaction")}
    }
    private func enter(_ exercise:NFExercise,in runtime:NFUniversalSessionRuntime){switch response(exercise){case let .singleChoice(id):runtime.singleChoiceID=id;case let .multipleChoice(ids):runtime.multipleChoiceIDs=Set(ids);default:break}}

    /// Independent oracle enumerates all 24 oriented faces of an already
    /// closed cube. Shared directed cube-edge endpoints constrain which face
    /// frame can occupy each paper square; no folding update formula is used.
    private func cubeAssignment(_ layout:NFCubeNetLayout)->[String:G.Frame]? {
        func cross(_ a:G.Vector,_ b:G.Vector)->G.Vector{.init(x:a.y*b.z-a.z*b.y,y:a.z*b.x-a.x*b.z,z:a.x*b.y-a.y*b.x)}
        let axes=G.Direction.allCases.map(\.vector)
        let candidates=axes.flatMap{n in axes.filter{$0.dot(n)==0}.map{r in G.Frame(label:"",center2:n-G.Vector.zAxis,right:r,up:cross(n,r),normal:n)}}
        func edge(_ f:G.Frame,dx:Int,dy:Int)->[G.Vector]{if dx != 0{return [f.center2+f.right*dx-f.up,f.center2+f.right*dx+f.up]};return [f.center2+f.up*dy-f.right,f.center2+f.up*dy+f.right]}
        guard let first=layout.cells.first else{return nil}
        var mapped=[first.label:G.Frame(label:first.label,center2:.zero,right:.xAxis,up:.yAxis,normal:.zAxis)],queue=[first],cursor=0
        while cursor<queue.count{
            let a=queue[cursor];cursor+=1;guard let fa=mapped[a.label] else{return nil}
            for b in layout.cells where abs(a.x-b.x)+abs(a.y-b.y)==1{
                let dx=b.x-a.x,dy=b.y-a.y
                let allowed=candidates.filter{edge(fa,dx:dx,dy:dy)==edge($0,dx:-dx,dy:-dy)}
                guard allowed.count==1,let candidate=allowed.first else{return nil}
                let fb=G.Frame(label:b.label,center2:candidate.center2,right:candidate.right,up:candidate.up,normal:candidate.normal)
                if let prior=mapped[b.label]{guard prior==fb else{return nil}}else{mapped[b.label]=fb;queue.append(b)}
            }
        }
        return mapped.count==6 && Set(mapped.values.map(\.normal)).count==6 ? mapped:nil
    }
    func testAllThirtyFiveFreeProposalsHaveExactlyElevenValidCubeClosuresFromIndependentFaceAssignment() throws {
        XCTAssertEqual(NFCubeNetEngine.canonicalProposals.count,35)
        var valid=0
        for layout in NFCubeNetEngine.canonicalProposals {
            let oracle=cubeAssignment(layout),actual=NFCubeNetEngine.isValid(layout)
            XCTAssertEqual(actual,oracle != nil)
            if let oracle {
                valid+=1;let task=G.Task(layout:layout,query:.validity,givenFoldedLeaf:nil)
                let frames=try XCTUnwrap(task.completedFrames)
                for f in frames{XCTAssertEqual(f,oracle[f.label]);XCTAssertEqual(f.center2,f.normal-G.Vector.zAxis);XCTAssertEqual(Set(f.corners2).count,4)}
                let uniqueCorners=Set(frames.flatMap(\.corners2));XCTAssertEqual(uniqueCorners.count,8)
                for p in uniqueCorners{XCTAssertEqual(frames.filter{$0.corners2.contains(p)}.count,3)}
            }
        }
        XCTAssertEqual(valid,11)
    }
    func testEveryRetainedTaskUsesExactAllFaceAuthorityAndExclusiveLocalizedChoices() throws {
        for task in G.tasks {
            XCTAssertTrue(task.bounded);XCTAssertFalse(task.acceptedIDs.isEmpty)
            for locale in ["en_US","ja_JP"] {
                let exercise=try generate(task,locale:locale),contract=try XCTUnwrap(NFNetFoldingContract.make(exercise:exercise))
                XCTAssertEqual(contract.task,task);XCTAssertEqual(exercise.schemaVersion,11);XCTAssertEqual(exercise.generatorVersion,14);XCTAssertTrue(exercise.id.contains(".r14."))
                try NFExerciseSchemaValidator.validate(exercise)
                XCTAssertEqual(NFExerciseScoringEngine.score(response(exercise),for:exercise).credit,1)
                XCTAssertNil(exercise.contractMetadata?.editorialDemand)
                if case let .singleChoice(s)=exercise.interaction {
                    for option in s.options{XCTAssertEqual(NFExerciseScoringEngine.score(.singleChoice(optionID:option.id),for:exercise).isCorrect,task.acceptedIDs.contains(option.id))}
                } else if case let .multipleChoice(s)=exercise.interaction {
                    XCTAssertEqual(s.correctOptionIDs.count,4);XCTAssertEqual(Set(s.correctOptionIDs).count,4)
                    XCTAssertEqual(NFExerciseScoringEngine.score(.multipleChoice(optionIDs:Array(s.correctOptionIDs.dropLast())),for:exercise).credit,0)
                    XCTAssertEqual(NFExerciseScoringEngine.score(.multipleChoice(optionIDs:Array(s.correctOptionIDs.reversed())),for:exercise).credit,1)
                }
                XCTAssertEqual(Set(contract.options.map(\.text)).count,contract.options.count)
            }
        }
    }
    func testPartialGivenMovesOnlyItsLeafAndPreservesEveryHingeEdgeAndPrintedArrow() throws {
        for task in G.tasks where task.givenFoldedLeaf != nil {
            let leaf=try XCTUnwrap(task.givenFoldedLeaf),frames=try XCTUnwrap(task.originalFrames),flat=try XCTUnwrap(G.Task.frames(task.layout,folded:[]))
            for f in frames{if f.label != leaf{XCTAssertEqual(f,flat.first{$0.label==f.label})}}
            let cell=try XCTUnwrap(task.layout.cells.first{$0.label==leaf}),parent=try XCTUnwrap(task.layout.cells.first{abs($0.x-cell.x)+abs($0.y-cell.y)==1})
            let childFrame=try XCTUnwrap(frames.first{$0.label==leaf}),parentFrame=try XCTUnwrap(frames.first{$0.label==parent.label})
            XCTAssertEqual(Set(childFrame.corners2).intersection(parentFrame.corners2).count,2)
            XCTAssertEqual(childFrame.normal.dot(parentFrame.normal),0)
            XCTAssertEqual(childFrame.right.dot(childFrame.up),0);XCTAssertEqual(childFrame.up.dot(childFrame.normal),0)
        }
    }
    func testRoleSymmetryAndFaceRelabelingDoNotManufactureAnotherNetTarget() throws {
        let source=try XCTUnwrap(G.tasks.first{if case .opposite=$0.query{return true};return false})
        guard case let .opposite(label)=source.query else{return XCTFail("Expected opposite query")}
        let names=Dictionary(uniqueKeysWithValues:zip(["A","B","C","D","E","F"],["D","E","F","A","B","C"]))
        let renamed=NFCubeNetLayout(cells:source.layout.cells.map{.init(x:$0.x,y:$0.y,label:names[$0.label]!)})
        XCTAssertEqual(source.identity,G.Task(layout:renamed,query:.opposite(names[label]!),givenFoldedLeaf:nil).identity)
        let maxX=source.layout.cells.map(\.x).max()!
        let mirrored=NFCubeNetLayout(cells:source.layout.cells.map{.init(x:maxX-$0.x,y:$0.y,label:$0.label)})
        XCTAssertEqual(source.identity,G.Task(layout:mirrored,query:.opposite(label),givenFoldedLeaf:nil).identity)
        XCTAssertEqual(Set(G.tasks.map(\.deliveryIdentity)).count,G.tasks.count)
        XCTAssertEqual(source.identity,G.Task(layout:source.layout,query:.adjacent(label),givenFoldedLeaf:nil).identity)
        var combinations:Set<String>=[]
        for task in G.tasks{if case let .constraints(a,b)=task.query{combinations.insert("\(task.satisfies(a))-\(task.satisfies(b))")}}
        XCTAssertEqual(combinations,["true-true","true-false","false-true","false-false"])
        XCTAssertEqual(G.tasks.filter{if case .validity=$0.query{return true};return false}.count,35)
        print("CUBE_FOLDING_CENSUS deliveryForms=\(G.tasks.count), semanticTargets=\(Set(G.tasks.map(\.identity)).count), validTopologies=11, invalidProposals=24, reviewedAdmissions=0")
    }
    func testUnsupportedProtectedAndContradictoryRetainedContractsFailClosedWithoutChangingLegacy() throws {
        let task=try XCTUnwrap(G.tasks.first{if case .opposite=$0.query{return true};return false}),exercise=try generate(task)
        var changed=exercise;changed.contractMetadata?.netFolding?.policyVersion=99
        XCTAssertNil(NFNetFoldingContract.make(exercise:changed));XCTAssertEqual(NFExerciseScoringEngine.score(response(exercise),for:changed).outcome,.invalidItem)
        changed=exercise;changed.contractMetadata?.netFolding=nil;XCTAssertFalse(changed.hasSupportedNetFolding)
        var protectedRaw=try XCTUnwrap(JSONSerialization.jsonObject(with:JSONEncoder().encode(exercise)) as? [String:Any])
        protectedRaw["assessmentProtected"]=true
        changed=try JSONDecoder().decode(NFExercise.self,from:JSONSerialization.data(withJSONObject:protectedRaw))
        XCTAssertNil(NFNetFoldingContract.make(exercise:changed))
        var session=SessionRequest(lab:.spatial,source:.focused,seed:1,localeIdentifier:"en",requestedItemCount:2,isTimed:false)
        XCTAssertFalse(session.permitsNetFolding(exercise:exercise));session.netFoldingPolicyVersion=1;XCTAssertTrue(session.permitsNetFolding(exercise:exercise))
        let old=try NFFallbackExerciseGenerator.generate(.init(seed:1,index:0,lab:.spatial,purpose:.practice,preferredAssessmentMechanicID:"fixture.fallback-variant-4"))
        XCTAssertEqual(old.schemaVersion,2);XCTAssertEqual(old.generatorVersion,4);XCTAssertTrue(old.hasSupportedNetFolding);XCTAssertFalse(session.permitsNetFolding(exercise:old))
        XCTAssertThrowsError(try NFFallbackExerciseGenerator.generate(.init(seed:1,index:0,lab:.spatial,purpose:.baseline,netFoldingPolicyVersion:1)))
        XCTAssertThrowsError(try NFFallbackExerciseGenerator.generate(.init(seed:1,index:0,lab:.spatial,purpose:.practice,netFoldingPolicyVersion:99)))
    }
    func testFoldUnfoldResetAndNativeFacesRequireCommittedPhaseAndRetainExactOriginal() throws {
        let task=try XCTUnwrap(G.tasks.first{$0.givenFoldedLeaf != nil}),exercise=try generate(task),contract=try XCTUnwrap(NFNetFoldingContract.make(exercise:exercise))
        let original=try NFImmutableAttemptRecordSnapshot.encoded(exercise);var state=NFNetFoldingInspection()
        XCTAssertFalse(state.select(.completed,contract:contract,phase:.independent));XCTAssertEqual(state.frames(contract:contract,phase:.independent),task.originalFrames)
        XCTAssertTrue(state.select(.completed,contract:contract,phase:.committedFeedback));XCTAssertEqual(state.frames(contract:contract,phase:.committedFeedback),task.completedFrames)
        let scene=NFSpatialRealitySceneFactory.makeNetFoldingScene(frames:state.frames(contract:contract,phase:.committedFeedback));XCTAssertEqual(scene.children.filter{$0.name.hasPrefix("net.face.")}.count,6)
        for f in try XCTUnwrap(task.completedFrames){let entity=try XCTUnwrap(scene.children.first{$0.name=="net.face."+f.label});XCTAssertEqual(entity.position,SIMD3(Float(f.center2.x)/2,Float(f.center2.y)/2,Float(f.center2.z)/2));XCTAssertEqual(entity.children.first?.name,"net.arrow."+f.label)
            let arrow=entity.orientation.act(SIMD3<Float>(0,1,0)),normal=entity.orientation.act(SIMD3<Float>(0,0,1))
            for i in 0..<3{XCTAssertEqual(arrow[i],Float(f.up.values[i]),accuracy:1e-6);XCTAssertEqual(normal[i],Float(f.normal.values[i]),accuracy:1e-6)}}
        XCTAssertTrue(state.select(.flat,contract:contract,phase:.savedWorkedSolution));XCTAssertEqual(state.frames(contract:contract,phase:.savedWorkedSolution),G.Task.frames(task.layout,folded:[]))
        state.reset();XCTAssertEqual(state.frames(contract:contract,phase:.savedWorkedSolution),task.originalFrames)
        XCTAssertEqual(try NFImmutableAttemptRecordSnapshot.encoded(exercise),original)
        let invalid=NFNetFoldingContract(task:try XCTUnwrap(G.tasks.first{!$0.validNet}),localeIdentifier:"en_US")
        XCTAssertFalse(state.select(.completed,contract:invalid,phase:.committedFeedback));XCTAssertEqual(state.frames(contract:invalid,phase:.independent).count,6)
    }
    func testActualOrdinaryColdCommitAndNextRetainExactNetFamilyAndOriginalArrows() throws {
        let (store,container,_)=try store();defer{withExtendedLifetime(container){}}
        let activity=try XCTUnwrap(NFDefaultContentCatalog.activity(id:NFNetFoldingContract.familyID))
        XCTAssertTrue(store.beginDefaultCatalogSession(.init(activity:activity,field:.general),requestedItemCount:3,timingCondition:.init(.untimed)))
        let request=try XCTUnwrap(store.activeSessionRequest),runtime=NFUniversalSessionRuntime(request:request)
        XCTAssertTrue(runtime.checkpointDraft(store:store));runtime.resume();runtime.acknowledgePresented()
        let exercise=runtime.exercise;XCTAssertNotNil(NFNetFoldingContract.make(exercise:exercise));enter(exercise,in:runtime)
        XCTAssertTrue(runtime.checkpointDraft(store:store));runtime.releaseWriter()
        let envelope=try XCTUnwrap(store.localSessions.archive.sessions.first{$0.id==runtime.sessionID});var recovered=envelope.request;recovered.localSessionID=envelope.id;recovered.localCheckpoint=envelope.checkpoint
        let cold=NFUniversalSessionRuntime(request:recovered);defer{cold.releaseWriter()}
        XCTAssertTrue(cold.checkpointDraft(store:store));cold.resume();cold.acknowledgePresented()
        XCTAssertEqual(cold.exercise,exercise);XCTAssertEqual(cold.singleChoiceID,runtime.singleChoiceID);XCTAssertEqual(cold.multipleChoiceIDs,runtime.multipleChoiceIDs)
        cold.submitInline(store:store);XCTAssertEqual(cold.lastResult?.outcome,.correct);XCTAssertNil(cold.saveError)
        let record=try XCTUnwrap(store.attempts.first);XCTAssertEqual(store.exerciseSnapshot(for:record.id),exercise)
        XCTAssertEqual(try JSONDecoder().decode(NFExerciseResponse.self,from:Data(record.response.utf8)),response(exercise))
        cold.next(store:store);XCTAssertEqual(cold.index,1);XCTAssertNil(cold.nextUnavailableReason)
        XCTAssertEqual(cold.exercise.contractMetadata?.familyID,NFNetFoldingContract.familyID);XCTAssertNotEqual(cold.exercise.contractMetadata?.semanticFingerprint,exercise.contractMetadata?.semanticFingerprint)
    }
    func testGeneratedMultipleAdjacentFacesUseExactRetainedSetThroughColdCommit() throws {
        let (store,container,_)=try store();defer{withExtendedLifetime(container){}}
        let task=try XCTUnwrap(G.tasks.first{if case .adjacent=$0.query{return true};return false}),exercise=try generate(task,purpose:.documentPractice),id=UUID()
        let request=NFAuthoringRequest(id:id,capability:.contextualize,lab:.spatial,field:.general,customTopic:"Synthetic cube net",learningObjective:"Track every adjacent face",style:.spatialTransformation,difficulty:0.5,count:1,localeIdentifier:"en_US",seed:1,aiMode:.disabled)
        let question=NFAuthoredQuestion(id:exercise.id,lab:.spatial,style:.spatialTransformation,prompt:exercise.prompt,context:"",choices:[],correctAnswer:try XCTUnwrap(NFNetFoldingContract(task:task,localeIdentifier:"en_US").options.first{task.acceptedIDs.contains($0.id)}).text,acceptedAnswers:[],explanation:exercise.feedback.correctExplanation,hint:exercise.feedback.hintLadder[0],decisiveStep:exercise.feedback.decisiveStep,difficulty:0.5,citationChunkIDs:[],evidenceClass:.documentPractice,authoritativeExercise:exercise)
        XCTAssertTrue(NFAuthoredExerciseAuthority.validatesBinding(question))
        let result=NFAuthoringResult(questions:[question],provenance:.init(requestID:id,generatedAt:Date().addingTimeInterval(-1),route:.deterministicFallback,routeReason:"Synthetic net",promptVersion:NFAuthoringRequest.promptVersion,modelIdentifier:"synthetic.net",sourceChunkIDs:[],sourceDocumentIDs:[],validationVersion:NFAuthoringEngine.validationVersion,repairCount:0,cacheKey:"synthetic.net",isFallback:true),routeCandidates:[],validationStatus:.init(level:.deterministicKey,sourceSupport:.notApplicable),validationNotes:[])
        let runtime=AIGeneratedPracticeRuntime(result:result,request:request);XCTAssertTrue(runtime.checkpoint(store:store));runtime.resume();runtime.multipleChoiceIDs=task.acceptedIDs;XCTAssertTrue(runtime.checkpoint(store:store));let draft=try XCTUnwrap(store.generatedPracticeDraft(for:id));runtime.releaseWriter()
        let cold=AIGeneratedPracticeRuntime(result:result,request:request,draft:draft);defer{cold.releaseWriter()};XCTAssertTrue(cold.restoreCheckpoint(store:store));cold.resume();XCTAssertEqual(cold.multipleChoiceIDs,task.acceptedIDs)
        cold.submit(store:store);XCTAssertEqual(cold.lastScore?.outcome,.correct);let record=try XCTUnwrap(store.attempts.first);XCTAssertEqual(store.exerciseSnapshot(for:record.id),exercise)
    }
    func testDetachedFactoryReachabilityKeepsFiniteQueryCapacitySeparateFromElevenTopologies() async throws {
        let activity=try XCTUnwrap(NFDefaultContentCatalog.activity(id:NFNetFoldingContract.familyID))
        var request=SessionRequest(lab:.spatial,source:.focused,seed:20260905,localeIdentifier:"en",field:.general,requestedItemCount:50,isTimed:false,timingCondition:.init(.untimed),mechanicID:activity.mechanicID);request.netFoldingPolicyVersion=1
        let pinned=request
        var mixed=SessionRequest(lab:.spatial,source:.focused,seed:20260905,localeIdentifier:"en",field:.general,requestedItemCount:50,isTimed:false,timingCondition:.init(.untimed));mixed.netFoldingPolicyVersion=1
        let mixedRequest=mixed
        let result=await Task.detached(priority:.userInitiated){()->(Int,Int,Int) in
            var ids:Set<String>=[],unavailable=0,mixedIDs:Set<String>=[]
            for i in 0..<50{let value=NFDeterministicSessionExerciseFactory.makeExercise(request:pinned,index:i,assessmentDescriptor:nil,excludingContentFingerprints:ids)
                if let c=NFNetFoldingContract.make(exercise:value){ids.insert(NFQuestionFingerprint.netFoldingFingerprint(identity:c.task.identity))}else{unavailable+=1}}
            for ordinal in 0..<NFOfflineQuestionBank.questionsPerLab {
                let value=NFDeterministicSessionExerciseFactory.makeExercise(request:mixedRequest.launchOnly(offlineQuestionOrdinals:[ordinal]),index:0,assessmentDescriptor:nil)
                if let c=NFNetFoldingContract.make(exercise:value){mixedIDs.insert(NFQuestionFingerprint.netFoldingFingerprint(identity:c.task.identity))}
            }
            return(ids.count,unavailable,mixedIDs.count)
        }.value
        XCTAssertEqual(result.0,50);XCTAssertEqual(result.1,0);XCTAssertGreaterThan(result.2,0)
        XCTAssertLessThanOrEqual(result.2,Set(G.tasks.map(\.identity)).count)
        print("CUBE_FOLDING_REACHABILITY focused50=\(result.0), unavailable=\(result.1), legacyMixedSemanticTargets=\(result.2)")
    }
}


@MainActor
final class CoordinateReasoningContractTests:XCTestCase {
    private typealias G=NFCoordinateReasoningGeometry
    private typealias P=G.Point
    private func generated(_ task:G.Task,locale:String="en_US",purpose:NFExercisePurpose = .practice) throws -> NFExercise {
        let entries=G.tasks.filter{$0.familyVariant==task.familyVariant},target=try XCTUnwrap(entries.firstIndex(of:task))
        let mechanic="fixture.fallback-variant-\(task.familyVariant)"
        func selected(_ seed:UInt64)->Int {
            var hash:UInt64=0xcbf29ce484222325
            for byte in "\(seed):0:\(TrainingLab.spatial.rawValue):\(purpose.rawValue):automatic:\(mechanic):no-transfer-brief:4".utf8 {hash=(hash ^ UInt64(byte)) &* 0x100000001b3}
            var value=seed ^ hash;if value == 0 {value=0x9E3779B97F4A7C15};value &+= 0x9E3779B97F4A7C15
            value=(value ^ (value>>30)) &* 0xBF58476D1CE4E5B9;value=(value ^ (value>>27)) &* 0x94D049BB133111EB
            return Int((value ^ (value>>31)) % UInt64(entries.count))
        }
        let seed=try XCTUnwrap((UInt64(0)..<40_000).first{selected($0)==target})
        let value=try NFFallbackExerciseGenerator.generate(.init(seed:seed,index:0,lab:.spatial,purpose:purpose,localeIdentifier:locale,
            preferredAssessmentMechanicID:mechanic,coordinateReasoningPolicyVersion:1))
        XCTAssertEqual(value.contractMetadata?.coordinateReasoning?.task,task)
        return value
    }
    private func answer(_ exercise:NFExercise)throws->NFExerciseResponse {
        switch exercise.interaction {
        case let .logicState(s):return .logicState(.init(finalState:s.expectedFinalState,violatedRuleID:nil))
        case let .multipleChoice(s):return .multipleChoice(optionIDs:s.correctOptionIDs.sorted())
        default:throw NSError(domain:"CoordinateReasoningFixture",code:1)
        }
    }
    private func enter(_ response:NFExerciseResponse,in runtime:NFUniversalSessionRuntime) {
        switch response {case let .logicState(s):runtime.logicState=s.finalState;runtime.violatedRuleID=s.violatedRuleID
        case let .multipleChoice(ids):runtime.multipleChoiceIDs=Set(ids);default:XCTFail("Unexpected response")}
    }
    private func apply(_ p:P,_ operation:G.Operation)->P {
        switch operation {
        case let .rotate(c,q):
            var x=p.x-c.x,y=p.y-c.y
            for _ in 0..<((q%4+4)%4){let previous=x;x = -y;y=previous}
            return .init(x:x+c.x,y:y+c.y)
        case let .translate(v):return .init(x:p.x+v.x,y:p.y+v.y)
        case let .reflect(line,k):switch line {
            case .vertical:return .init(x:2*k-p.x,y:p.y);case .horizontal:return .init(x:p.x,y:2*k-p.y)
            case .risingDiagonal:return .init(x:p.y,y:p.x);case .fallingDiagonal:return .init(x:-p.y,y:-p.x)}
        }
    }
    private func inverse(_ operation:G.Operation)->G.Operation {
        switch operation {case let .rotate(c,q):.rotate(center:c,quarterTurns:-q)
        case let .translate(v):.translate(vector:.init(x:-v.x,y:-v.y));case .reflect:operation}
    }
    private func area(_ points:[P])->Int {
        let a=points[0],b=points[1],c=points[2]
        return a.x*b.y+b.x*c.y+c.x*a.y-a.y*b.x-b.y*c.x-c.y*a.x
    }
    private func fixture(root:URL?=nil,context:ModelContext?=nil,owner:UUID?=nil)throws->(AppStore,ModelContainer?,URL) {
        let folder=root ?? FileManager.default.temporaryDirectory.appending(path:"NF-Coordinate-Reasoning-\(UUID())")
        try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
        if root == nil {addTeardownBlock{try? FileManager.default.removeItem(at:folder)}}
        let container:ModelContainer?
        let model:ModelContext
        if let context {container=nil;model=context}
        else {
            let c=try ModelContainer(for:Schema(NFSchemaV1.models),configurations:ModelConfiguration(isStoredInMemoryOnly:true))
            var draft=OnboardingDraft();draft.aiMode = .disabled;c.mainContext.insert(UserProfileRecord(draft:draft));try c.mainContext.save()
            container=c;model=c.mainContext
        }
        let store=AppStore(context:model,nextDayEnhancementCache:NFNextDayEnhancementCache(rootURL:folder.appending(path:"cache")),documentStorageRootURL:folder.appending(path:"documents"),
            localSessionRepository:NFLocalSessionRepository(url:folder.appending(path:"sessions.json"),ownerDeviceID:owner ?? UUID()),
            adaptivePlanHistoryRepository:NFAdaptivePlanHistoryRepository(fileURL:folder.appending(path:"history.json")),
            offlineQuestionRotation:NFOfflineQuestionRotation(store:NFMemoryOfflineQuestionRotationStateStore()),
            temporaryArtifactsRootURL:folder.appending(path:"temporary"),allowsSharedWidgetPublishing:false)
        return(store,container,folder)
    }
    func testEveryFiniteInverseAndAffineKeyMatchesIndependentGeometricSubstitutionInBothLocales() throws {
        for task in G.tasks where task.query != .orientationFixed {
            let targets=task.originals.map{task.operations.reduce($0){apply($0,$1)}}
            XCTAssertEqual(targets,task.pairs.map(\.target))
            for (index,target) in targets.enumerated(){XCTAssertEqual(task.operations.reversed().reduce(target){apply($0,inverse($1))},task.originals[index])}
            for locale in ["en_US","ja_JP"] {
                let exercise=try generated(task,locale:locale),contract=try XCTUnwrap(NFCoordinateReasoningContract.make(exercise:exercise))
                try NFExerciseSchemaValidator.validate(exercise)
                XCTAssertEqual(exercise.schemaVersion,12);XCTAssertEqual(exercise.generatorVersion,15);XCTAssertTrue(exercise.id.contains(".r15."))
                XCTAssertNil(exercise.contractMetadata?.editorialDemand)
                let response=try answer(exercise);XCTAssertEqual(NFExerciseScoringEngine.score(response,for:exercise).credit,1)
                guard case let .logicState(s)=response else{return XCTFail("Expected numeric field envelope")}
                var wrong=s.finalState;let key=try XCTUnwrap(wrong.keys.sorted().first);wrong[key]=String(try XCTUnwrap(Int(wrong[key]!))+1)
                XCTAssertEqual(NFExerciseScoringEngine.score(.logicState(.init(finalState:wrong,violatedRuleID:nil)),for:exercise).credit,
                    Double(wrong.count-1)/Double(wrong.count),accuracy:1e-10)
                var equivalent=s.finalState;equivalent[key]=String(2 * (try XCTUnwrap(Int(s.finalState[key]!))))+"/2"
                XCTAssertEqual(NFExerciseScoringEngine.score(.logicState(.init(finalState:equivalent,violatedRuleID:nil)),for:exercise).outcome,.correct)
                XCTAssertEqual(contract.representation.points,contract.publicPoints)
                if task.query == .inferAffine {
                    XCTAssertNotEqual(area(task.originals),0)
                    let values=s.finalState
                    for pair in task.pairs {
                        XCTAssertEqual(Int(values["a"]!)!*pair.source.x+Int(values["b"]!)!*pair.source.y+Int(values["tx"]!)!,pair.target.x)
                        XCTAssertEqual(Int(values["c"]!)!*pair.source.x+Int(values["d"]!)!*pair.source.y+Int(values["ty"]!)!,pair.target.y)
                    }
                }
            }
        }
    }
    func testOrientationAndGlobalFixedLocusAreBothScoredUsingIndependentAreaAndHalfGridOracle() throws {
        var classes:Set<String>=[]
        for task in G.tasks where task.query == .orientationFixed {
            let output=task.originals.map{task.operations.reduce($0){apply($0,$1)}}
            let preserves=area(task.originals)*area(output)>0
            let doubled=task.operations.map{ op->G.Operation in switch op {
                case let .rotate(c,q):.rotate(center:.init(x:2*c.x,y:2*c.y),quarterTurns:q)
                case let .translate(v):.translate(vector:.init(x:2*v.x,y:2*v.y))
                case let .reflect(line,k):.reflect(line:line,offset:2*k)} }
            var fixed=0
            for x in -24...24 {for y in -24...24 {let point=P(x:x,y:y);if doubled.reduce(point,{apply($0,$1)})==point{fixed+=1}}}
            let locus=fixed==0 ? "none":fixed==1 ? "point":fixed==49*49 ? "plane":"line"
            classes.insert(locus);XCTAssertEqual(task.fixedLocus?.rawValue,locus)
            for locale in ["en_US","ja_JP"] {
                let exercise=try generated(task,locale:locale),contract=try XCTUnwrap(NFCoordinateReasoningContract.make(exercise:exercise))
                let expected=[preserves ? "orientation-preserved":"orientation-reversed","fixed-"+locus]
                XCTAssertEqual(Set(contract.acceptedOptionIDs),Set(expected))
                XCTAssertEqual(Set(contract.options.map(\.text)).count,6)
                XCTAssertEqual(NFExerciseScoringEngine.score(.multipleChoice(optionIDs:expected),for:exercise).outcome,.correct)
                let incorrect=[preserves ? "orientation-reversed":"orientation-preserved","fixed-"+locus]
                XCTAssertEqual(NFExerciseScoringEngine.score(.multipleChoice(optionIDs:incorrect),for:exercise).credit,0)
                XCTAssertEqual(NFExerciseScoringEngine.score(.multipleChoice(optionIDs:[expected[0],locus == "none" ? "fixed-plane":"fixed-none"]),for:exercise).credit,0)
            }
        }
        XCTAssertEqual(classes,["none","point","line","plane"])
        let classifications=G.tasks.filter{$0.query == .orientationFixed}
        XCTAssertTrue(classifications.contains{area($0.originals)<0})
        for task in classifications {
            let alternate=G.Task(query:task.query,familyVariant:task.familyVariant,
                originals:[.init(x:0,y:0),.init(x:0,y:3),.init(x:2,y:0)],operations:task.operations)
            XCTAssertEqual(task.identity,alternate.identity,"An illustrative triangle cannot manufacture another global orientation/fixed-locus target")
        }
    }
    func testUnderdeterminedContradictoryFutureAndProtectedContractsHaveNoAcceptedKey() throws {
        let zero=P(x:0,y:0),line=[zero,P(x:1,y:1),P(x:2,y:2)]
        let under=G.Task(query:.inferAffine,familyVariant:0,originals:line,operations:[.rotate(center:zero,quarterTurns:1)])
        XCTAssertFalse(under.isBounded);XCTAssertNil(G.solve(pairs:under.pairs));XCTAssertTrue(under.exactValues.isEmpty)
        let triangle=[zero,P(x:2,y:0),P(x:0,y:3)]
        let halfTurn=G.Task(query:.inferAffine,familyVariant:0,originals:triangle,operations:[.rotate(center:zero,quarterTurns:2)])
        let twoTurns=G.Task(query:.inferAffine,familyVariant:0,originals:triangle,operations:[.rotate(center:zero,quarterTurns:1),.rotate(center:zero,quarterTurns:1)])
        XCTAssertEqual(halfTurn.pairs,twoTurns.pairs)
        XCTAssertEqual(halfTurn.identity,twoTurns.identity,"An unseen recipe decomposition cannot inflate the identical correspondence task")
        let duplicated=G.Task(query:.inferAffine,familyVariant:0,originals:[zero,zero,.init(x:1,y:2)],operations:under.operations)
        XCTAssertFalse(duplicated.isBounded)
        let extreme=G.Task(query:.inverse,familyVariant:0,originals:[.init(x:Int.max,y:0)],operations:under.operations)
        XCTAssertFalse(extreme.isBounded);XCTAssertTrue(extreme.pairs.isEmpty)
        let original=try generated(try XCTUnwrap(G.tasks.first{$0.query == .inferAffine})),response=try answer(original)
        var invalid=original;invalid.contractMetadata?.coordinateReasoning = .init(task:under,localeIdentifier:original.localeIdentifier)
        XCTAssertEqual(NFExerciseScoringEngine.score(response,for:invalid).outcome,.invalidItem)
        invalid=original;invalid.contractMetadata?.coordinateReasoning?.policyVersion=999
        XCTAssertNil(NFCoordinateReasoningContract.make(exercise:invalid));XCTAssertNil(NFResponsePresentation.expectedAnswer(for:invalid))
        invalid=original;invalid.contractMetadata?.coordinateReasoning=nil
        XCTAssertFalse(invalid.hasSupportedCoordinateReasoning)
        var raw=try XCTUnwrap(JSONSerialization.jsonObject(with:JSONEncoder().encode(original)) as? [String:Any]);raw["assessmentProtected"]=true
        let protected=try JSONDecoder().decode(NFExercise.self,from:JSONSerialization.data(withJSONObject:raw))
        XCTAssertNil(NFCoordinateReasoningContract.make(exercise:protected));XCTAssertEqual(NFExerciseScoringEngine.score(response,for:protected).outcome,.invalidItem)
        XCTAssertThrowsError(try NFFallbackExerciseGenerator.generate(.init(seed:1,index:0,lab:.spatial,purpose:.baseline,coordinateReasoningPolicyVersion:1)))
        XCTAssertThrowsError(try NFFallbackExerciseGenerator.generate(.init(seed:1,index:0,lab:.spatial,purpose:.practice,coordinateReasoningPolicyVersion:999)))
    }
    func testOriginalOnlyRenderingAndResetDoNotLeakInverseOrUnknownMapBeforeCommit() throws {
        for query in G.Query.allCases {
            let task=try XCTUnwrap(G.tasks.first{$0.query==query}),value=try generated(task),contract=try XCTUnwrap(NFCoordinateReasoningContract.make(exercise:value))
            let original=try NFImmutableAttemptRecordSnapshot.encoded(value);var state=NFCoordinateReasoningInspection()
            XCTAssertFalse(state.reveal(contract:contract,phase:.independent))
            let before=state.drawingPlan(contract:contract,phase:.independent)
            XCTAssertEqual(before.originalPoints,contract.publicPoints);XCTAssertNil(before.workedPoints)
            XCTAssertTrue(state.reveal(contract:contract,phase:.committedFeedback))
            let worked=state.drawingPlan(contract:contract,phase:.committedFeedback)
            XCTAssertEqual(worked.originalPoints,before.originalPoints,"Showing a worked copy cannot move or rescale the separate original plot")
            XCTAssertEqual(state.drawingPlan(contract:contract,phase:.independent),before,"Reused feedback state cannot expose hidden values during independent work")
            let workedPoints=try XCTUnwrap(worked.workedPoints)
            if query == .inverse {XCTAssertEqual(contract.publicPoints.map(\.label),["Q"]);XCTAssertTrue(workedPoints.contains{$0.label=="P"})}
            if query == .inferAffine {XCTAssertFalse(contract.sourceDescription.contains(contract.operationList));XCTAssertEqual(contract.publicPoints.count,6)}
            if query == .orientationFixed {XCTAssertEqual(contract.publicPoints.map(\.label),["A","B","C"]);XCTAssertEqual(workedPoints.count,6)}
            state.reset();XCTAssertEqual(state.drawingPlan(contract:contract,phase:.savedWorkedSolution),before)
            XCTAssertEqual(try NFImmutableAttemptRecordSnapshot.encoded(value),original)
        }
    }
    func testNilPolicyPreservesForward12AndLegacy2WhileNewRecipeHasDistinctIdentityAndTypedProtocol() throws {
        for variant in [0,5] {
            let legacy=try NFFallbackExerciseGenerator.generate(.init(seed:21,index:0,lab:.spatial,purpose:.practice,preferredAssessmentMechanicID:"fixture.fallback-variant-\(variant)"))
            let forward=try NFFallbackExerciseGenerator.generate(.init(seed:21,index:0,lab:.spatial,purpose:.practice,preferredAssessmentMechanicID:"fixture.fallback-variant-\(variant)",coordinateTransformPolicyVersion:1))
            let advanced=try NFFallbackExerciseGenerator.generate(.init(seed:21,index:0,lab:.spatial,purpose:.practice,preferredAssessmentMechanicID:"fixture.fallback-variant-\(variant)",coordinateTransformPolicyVersion:1,coordinateReasoningPolicyVersion:1))
            XCTAssertEqual(legacy.schemaVersion,2);XCTAssertEqual(forward.schemaVersion,9);XCTAssertEqual(forward.generatorVersion,12)
            XCTAssertNil(forward.contractMetadata?.coordinateReasoning);XCTAssertEqual(advanced.schemaVersion,12)
            XCTAssertNotEqual(advanced.id,forward.id);XCTAssertNotEqual(advanced.id,legacy.id)
            var request=SessionRequest(lab:.spatial,source:.focused,seed:1,localeIdentifier:"en",requestedItemCount:2,isTimed:false)
            XCTAssertFalse(request.permitsCoordinateReasoning(exercise:advanced));XCTAssertTrue(request.permitsCoordinateReasoning(exercise:forward))
            request.coordinateReasoningPolicyVersion=1;XCTAssertTrue(request.permitsCoordinateReasoning(exercise:advanced));XCTAssertFalse(request.permitsCoordinateReasoning(exercise:forward));XCTAssertFalse(request.permitsCoordinateReasoning(exercise:legacy))
            XCTAssertEqual(request.launchOnly().coordinateReasoningPolicyVersion,1)
            XCTAssertTrue(NFEditorialNativeProtocol.supports(advanced));XCTAssertTrue(NFEditorialAdmissionContext.released.entries.isEmpty)
        }
    }
    func testActualSecondaryLaunchColdTypedCommitHistoryAndNextKeepChosenFamily() async throws {
        for family in ["nf.default.spatial.coordinate-rotation","nf.default.spatial.vector-reflection"] {
            let (store,container,root)=try fixture();defer{withExtendedLifetime(container){}}
            let activity=try XCTUnwrap(NFDefaultContentCatalog.activity(id:family))
            XCTAssertTrue(store.beginDefaultCatalogSession(.init(activity:activity,field:.general),requestedItemCount:3,timingCondition:.init(.untimed),coordinateReasoningPolicyVersion:1))
            let request=try XCTUnwrap(store.activeSessionRequest),runtime=NFUniversalSessionRuntime(request:request)
            XCTAssertEqual(request.coordinateReasoningPolicyVersion,1);XCTAssertTrue(runtime.checkpointDraft(store:store));runtime.resume();runtime.acknowledgePresented()
            let exercise=runtime.exercise,response=try answer(exercise);XCTAssertEqual(exercise.contractMetadata?.coordinateReasoning?.familyID,family)
            enter(response,in:runtime);runtime.scratchpad="Original transformation working."
            let didSave=await runtime.checkpointDraftAsync(store:store);XCTAssertTrue(didSave);runtime.releaseWriter()
            let envelope=try XCTUnwrap(store.localSessions.archive.sessions.first{$0.id==runtime.sessionID})
            let (coldStore,_,_)=try fixture(root:root,context:store.context,owner:store.localSessions.ownerDeviceID)
            XCTAssertNil(coldStore.localSessions.loadError)
            var coldRequest=envelope.request;coldRequest.localSessionID=envelope.id;coldRequest.localCheckpoint=envelope.checkpoint
            let cold=NFUniversalSessionRuntime(request:coldRequest);defer{cold.releaseWriter()}
            XCTAssertTrue(cold.checkpointDraft(store:coldStore));cold.resume();cold.acknowledgePresented()
            XCTAssertEqual(cold.exercise,exercise);XCTAssertEqual(cold.scratchpad,"Original transformation working.")
            await cold.submitInlineAsync(store:coldStore);XCTAssertEqual(cold.stage,.feedback);XCTAssertEqual(cold.lastResult?.outcome,.correct)
            let attempt=try XCTUnwrap(coldStore.attempts.first),saved=try XCTUnwrap(coldStore.exerciseSnapshot(for:attempt.id))
            XCTAssertEqual(saved,exercise);XCTAssertEqual(NFResponsePresentation.decode(attempt.response),response)
            let original=try NFImmutableAttemptRecordSnapshot.encoded(NFImmutableAttemptRecordSnapshot(attempt))
            XCTAssertEqual(saved.contractMetadata?.familyID,family);XCTAssertFalse(NFResponsePresentation.text(response,exercise:saved).isEmpty)
            cold.next(store:coldStore);XCTAssertEqual(cold.index,1);XCTAssertNil(cold.saveError);XCTAssertNil(cold.nextUnavailableReason)
            XCTAssertEqual(cold.exercise.contractMetadata?.coordinateReasoning?.familyID,family)
            XCTAssertNotEqual(cold.exercise.contractMetadata?.semanticFingerprint,exercise.contractMetadata?.semanticFingerprint)
            XCTAssertEqual(try NFImmutableAttemptRecordSnapshot.encoded(NFImmutableAttemptRecordSnapshot(attempt)),original)
        }
    }
    func testGeneratedAffineAndOrientationResponsesStayExactThroughColdCommitAndHistory() throws {
        for query in [G.Query.inferAffine,.orientationFixed] {
            let (store,container,_)=try fixture();defer{withExtendedLifetime(container){}}
            let task=try XCTUnwrap(G.tasks.first{$0.query==query}),exercise=try generated(task,purpose:.documentPractice),id=UUID()
            let expected:String
            switch exercise.interaction {
            case let .logicState(schema):expected=schema.expectedFinalState.sorted{$0.key<$1.key}.map{"\($0.key)=\($0.value)"}.joined(separator:",")
            case let .multipleChoice(schema):expected=try XCTUnwrap(schema.options.first{schema.correctOptionIDs.contains($0.id)}).text
            default:return XCTFail("Expected native exact authority")
            }
            let request=NFAuthoringRequest(id:id,capability:.contextualize,lab:.spatial,field:.general,customTopic:"Synthetic transformation reasoning",learningObjective:"Infer an exact planar map",style:.spatialTransformation,difficulty:0.6,count:1,localeIdentifier:"en_US",seed:1,aiMode:.disabled)
            let question=NFAuthoredQuestion(id:exercise.id,lab:.spatial,style:.spatialTransformation,prompt:exercise.prompt,context:"",choices:[],correctAnswer:expected,acceptedAnswers:[],explanation:exercise.feedback.correctExplanation,hint:exercise.feedback.hintLadder[0],decisiveStep:exercise.feedback.decisiveStep,difficulty:0.6,citationChunkIDs:[],evidenceClass:.documentPractice,authoritativeExercise:exercise)
            XCTAssertTrue(NFAuthoredExerciseAuthority.validatesBinding(question))
            let result=NFAuthoringResult(questions:[question],provenance:.init(requestID:id,generatedAt:Date().addingTimeInterval(-1),route:.deterministicFallback,routeReason:"Synthetic transformation",promptVersion:NFAuthoringRequest.promptVersion,modelIdentifier:"synthetic.coordinate",sourceChunkIDs:[],sourceDocumentIDs:[],validationVersion:NFAuthoringEngine.validationVersion,repairCount:0,cacheKey:"synthetic.coordinate",isFallback:true),routeCandidates:[],validationStatus:.init(level:.deterministicKey,sourceSupport:.notApplicable),validationNotes:[])
            let runtime=AIGeneratedPracticeRuntime(result:result,request:request);XCTAssertTrue(runtime.checkpoint(store:store));runtime.resume()
            let response=try answer(exercise)
            switch response {case let .logicState(value):runtime.logicState=value.finalState
            case let .multipleChoice(ids):runtime.multipleChoiceIDs=Set(ids);default:break}
            XCTAssertTrue(runtime.checkpoint(store:store));let draft=try XCTUnwrap(store.generatedPracticeDraft(for:id));runtime.releaseWriter()
            let cold=AIGeneratedPracticeRuntime(result:result,request:request,draft:draft);defer{cold.releaseWriter()}
            XCTAssertTrue(cold.restoreCheckpoint(store:store));cold.resume();XCTAssertEqual(cold.exercise,exercise)
            cold.submit(store:store);XCTAssertEqual(cold.stage,2);XCTAssertEqual(cold.lastScore?.outcome,.correct)
            let attempt=try XCTUnwrap(store.attempts.first)
            XCTAssertEqual(store.exerciseSnapshot(for:attempt.id),exercise);XCTAssertEqual(NFResponsePresentation.decode(attempt.response),response)
            XCTAssertEqual(draft.response,response);XCTAssertFalse(NFResponsePresentation.text(response,exercise:exercise).isEmpty)
            if query == .inferAffine {XCTAssertTrue(NFResponsePresentation.text(response,exercise:exercise).contains("unitless coefficient"))}
        }
    }
    func testActualFrozenNewContractCannotResumeUnderMissingPolicyAndKeepsOriginalBytes() throws {
        let (store,container,root)=try fixture();defer{withExtendedLifetime(container){}}
        let priorArchive=try NFEditorialCanonicalData.encode(store.localSessions.archive)
        let wrongActivity=try XCTUnwrap(NFDefaultContentCatalog.activity(id:"nf.default.spatial.cube-net"))
        XCTAssertFalse(store.beginDefaultCatalogSession(.init(activity:wrongActivity,field:.general),requestedItemCount:2,timingCondition:.init(.untimed),coordinateReasoningPolicyVersion:1))
        XCTAssertNil(store.activeSessionRequest)
        XCTAssertEqual(try NFEditorialCanonicalData.encode(store.localSessions.archive),priorArchive)
        let activity=try XCTUnwrap(NFDefaultContentCatalog.activity(id:"nf.default.spatial.coordinate-rotation"))
        XCTAssertTrue(store.beginDefaultCatalogSession(.init(activity:activity,field:.general),requestedItemCount:2,timingCondition:.init(.untimed),coordinateReasoningPolicyVersion:1))
        let runtime=NFUniversalSessionRuntime(request:try XCTUnwrap(store.activeSessionRequest))
        XCTAssertTrue(runtime.checkpointDraft(store:store));runtime.resume();runtime.acknowledgePresented();enter(try answer(runtime.exercise),in:runtime)
        XCTAssertTrue(runtime.checkpointDraft(store:store));runtime.releaseWriter()
        let original=try Data(contentsOf:root.appending(path:"sessions.json")),saved=try XCTUnwrap(store.localSessions.archive.sessions.first{$0.id==runtime.sessionID})
        var wrong=saved.request;wrong.localSessionID=saved.id;wrong.localCheckpoint=saved.checkpoint;wrong.coordinateReasoningPolicyVersion=nil
        let unavailable=NFUniversalSessionRuntime(request:wrong);defer{unavailable.releaseWriter()}
        XCTAssertNotNil(unavailable.unavailableReason);XCTAssertFalse(unavailable.checkpointDraft(store:store));XCTAssertTrue(store.attempts.isEmpty)
        XCTAssertEqual(try Data(contentsOf:root.appending(path:"sessions.json")),original)
    }
    func testDetachedBothAdvancedFamiliesUseOnlyValidUniqueFiniteContracts() async throws {
        let requests=try ["nf.default.spatial.coordinate-rotation","nf.default.spatial.vector-reflection"].map { id->SessionRequest in
            let activity=try XCTUnwrap(NFDefaultContentCatalog.activity(id:id))
            var request=SessionRequest(lab:.spatial,source:.focused,seed:20260905,localeIdentifier:"en",field:.general,requestedItemCount:20,isTimed:false,timingCondition:.init(.untimed),mechanicID:activity.mechanicID)
            request.coordinateTransformPolicyVersion=1;request.coordinateReasoningPolicyVersion=1;return request
        }
        let totals=await Task.detached(priority:.userInitiated){()->[Int] in requests.map { request in
            var seen:Set<String>=[]
            for index in 0..<20 {
                let exercise=NFDeterministicSessionExerciseFactory.makeExercise(request:request,index:index,assessmentDescriptor:nil,excludingContentFingerprints:seen)
                guard exercise.availabilityReason == nil,let contract=NFCoordinateReasoningContract.make(exercise:exercise) else{return -1}
                guard seen.insert(NFQuestionFingerprint.coordinateReasoningFingerprint(identity:contract.task.identity)).inserted else{return -2}
            }
            return seen.count
        }}.value
        XCTAssertEqual(totals,[20,20]);XCTAssertEqual(G.tasks.count,334)
        XCTAssertEqual(Set(G.tasks.map(\.identity)).count,180)
        XCTAssertTrue(G.tasks.contains{$0.query == .inverse && $0.originals==[.init(x:0,y:0)]})
        XCTAssertTrue(G.tasks.contains{$0.originals.contains{$0.x<0 && $0.y<0}})
        XCTAssertEqual(Set(G.tasks.filter{$0.familyVariant==0}.map(\.identity)).count,79)
        XCTAssertEqual(Set(G.tasks.filter{$0.familyVariant==5}.map(\.identity)).count,101)
    }
}

@MainActor
final class SpatialAssemblyContractTests:XCTestCase {
    private typealias G=NFSpatialAssemblyGeometry
    private typealias C=G.Cell
    private func generated(_ task:G.Task,locale:String="en_US",purpose:NFExercisePurpose = .practice) throws -> NFExercise {
        let entries=G.tasks.filter{$0.variant==task.variant},target=try XCTUnwrap(entries.firstIndex(of:task))
        let mechanic="fixture.fallback-variant-\(task.variant)"
        func selected(_ seed:UInt64)->Int {
            var hash:UInt64=0xcbf29ce484222325
            for byte in "\(seed):0:\(TrainingLab.spatial.rawValue):\(purpose.rawValue):automatic:\(mechanic):no-transfer-brief:4".utf8 {hash=(hash ^ UInt64(byte)) &* 0x100000001b3}
            var value=seed ^ hash;if value == 0 {value=0x9E3779B97F4A7C15};value &+= 0x9E3779B97F4A7C15
            value=(value ^ (value>>30)) &* 0xBF58476D1CE4E5B9;value=(value ^ (value>>27)) &* 0x94D049BB133111EB
            return Int((value ^ (value>>31)) % UInt64(entries.count))
        }
        let seed=try XCTUnwrap((UInt64(0)..<40_000).first{selected($0)==target})
        let value=try NFFallbackExerciseGenerator.generate(.init(seed:seed,index:0,lab:.spatial,purpose:purpose,localeIdentifier:locale,
            preferredAssessmentMechanicID:mechanic,spatialAssemblyPolicyVersion:1))
        XCTAssertEqual(value.contractMetadata?.spatialAssembly?.task,task)
        return value
    }
    private func answer(_ exercise:NFExercise)throws->NFExerciseResponse {
        switch exercise.interaction {
        case let .logicState(s):return .logicState(.init(finalState:s.expectedFinalState,violatedRuleID:nil))
        case let .multipleChoice(s):return .multipleChoice(optionIDs:s.correctOptionIDs.sorted())
        default:throw NSError(domain:"SpatialAssemblyFixture",code:1)
        }
    }
    private func enter(_ response:NFExerciseResponse,in runtime:NFUniversalSessionRuntime) {
        switch response {case let .logicState(s):runtime.logicState=s.finalState;runtime.violatedRuleID=s.violatedRuleID
        case let .multipleChoice(ids):runtime.multipleChoiceIDs=Set(ids);default:XCTFail("Unexpected response")}
    }
    private func fixture(root:URL?=nil,context:ModelContext?=nil,owner:UUID?=nil)throws->(AppStore,ModelContainer?,URL) {
        let folder=root ?? FileManager.default.temporaryDirectory.appending(path:"NF-Spatial-Assembly-\(UUID())")
        try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
        if root == nil {addTeardownBlock{try? FileManager.default.removeItem(at:folder)}}
        let container:ModelContainer?
        let model:ModelContext
        if let context {container=nil;model=context}
        else {
            let c=try ModelContainer(for:Schema(NFSchemaV1.models),configurations:ModelConfiguration(isStoredInMemoryOnly:true))
            var draft=OnboardingDraft();draft.aiMode = .disabled;c.mainContext.insert(UserProfileRecord(draft:draft));try c.mainContext.save()
            container=c;model=c.mainContext
        }
        let store=AppStore(context:model,nextDayEnhancementCache:NFNextDayEnhancementCache(rootURL:folder.appending(path:"cache")),documentStorageRootURL:folder.appending(path:"documents"),
            localSessionRepository:NFLocalSessionRepository(url:folder.appending(path:"sessions.json"),ownerDeviceID:owner ?? UUID()),
            adaptivePlanHistoryRepository:NFAdaptivePlanHistoryRepository(fileURL:folder.appending(path:"history.json")),
            offlineQuestionRotation:NFOfflineQuestionRotation(store:NFMemoryOfflineQuestionRotationStateStore()),
            temporaryArtifactsRootURL:folder.appending(path:"temporary"),allowsSharedWidgetPublishing:false)
        return(store,container,folder)
    }

    // Independent oracle: close the group by quarter turns about two physical
    // axes, rather than enumerating the producer's signed-permutation matrices.
    private func canonical(_ cells:[C])->[C] {
        let x=cells.map(\.x).min()!,y=cells.map(\.y).min()!,z=cells.map(\.z).min()!
        return cells.map{C(x:$0.x-x,y:$0.y-y,z:$0.z-z)}.sorted()
    }
    private func orientations(_ cells:[C])->Set<[C]> {
        var seen:Set<[C]>=[canonical(cells)],pending=[canonical(cells)]
        while let state=pending.popLast() {
            let turns=[state.map{C(x:$0.x,y:-$0.z,z:$0.y)},state.map{C(x:-$0.y,y:$0.x,z:$0.z)}]
            for turn in turns {let next=canonical(turn);if seen.insert(next).inserted{pending.append(next)}}
        }
        return seen
    }
    private func signature(_ cells:[C])->String {
        let front=Set(cells.map{"\($0.x):\($0.z)"}).sorted().joined(separator:";")
        let side=Set(cells.map{"\($0.y):\($0.z)"}).sorted().joined(separator:";")
        return front+"/"+side
    }
    private func physicallyConnected(_ h:[Int])->Bool {
        let occupied=Set(h.indices.filter{h[$0]>0});guard let start=occupied.first else{return false}
        var seen:Set<Int>=[start],pending=[start]
        while let i=pending.popLast(){for j in occupied where abs(i%2-j%2)+abs(i/2-j/2)==1 {
            if seen.insert(j).inserted{pending.append(j)}
        }}
        return seen==occupied
    }
    private func feasible(_ c:G.Constraints)->[[Int]] {
        var result:[[Int]]=[]
        for a in 0...3 {for b in 0...3 {for d in 0...3 {for e in 0...3 {
            let h=[a,b,d,e]
            if physicallyConnected(h),h.map({$0>0})==c.top,[max(a,d),max(b,e)]==c.front,
               [max(a,b),max(d,e)]==c.side,a+b+d+e==c.cubeCount {result.append(h)}
        }}}}
        return result
    }
    func testEveryAsymmetricOrientationUsesIndependentProperRotationAndVisibleSignatureOracle() throws {
        for task in G.tasks where task.variant==1 {
            guard case let .orientation(value)=task else{continue}
            let proper=orientations(value.source),views=Set(proper.map(signature))
            XCTAssertEqual(proper.count,24)
            XCTAssertFalse(proper.contains(canonical(value.source.map{C(x:-$0.x,y:$0.y,z:$0.z)})))
            let accepted=value.candidates.indices.filter{views.contains(signature(value.candidates[$0]))}
            XCTAssertEqual(task.acceptedIndices,accepted)
            XCTAssertTrue(value.shown.allSatisfy{$0.front.count<5 || $0.side.count<5})
            for locale in ["en_US","ja_JP"] {
                let exercise=try generated(task,locale:locale),contract=try XCTUnwrap(NFSpatialAssemblyContract.make(exercise:exercise))
                try NFExerciseSchemaValidator.validate(exercise)
                XCTAssertEqual(exercise.schemaVersion,13);XCTAssertEqual(exercise.generatorVersion,16)
                XCTAssertTrue(exercise.id.contains(".r16."));XCTAssertNil(exercise.contractMetadata?.editorialDemand)
                let response=NFExerciseResponse.multipleChoice(optionIDs:accepted.map(NFSpatialAssemblyContract.choiceID))
                XCTAssertEqual(NFExerciseScoringEngine.score(response,for:exercise).outcome,.correct)
                let wrong=try XCTUnwrap(value.candidates.indices.first{!accepted.contains($0)})
                XCTAssertEqual(NFExerciseScoringEngine.score(.multipleChoice(optionIDs:contract.acceptedOptionIDs+[NFSpatialAssemblyContract.choiceID(wrong)]),for:exercise).credit,0)
                XCTAssertEqual(exercise.representations,[.spatial(contract.representation)])
            }
        }
        XCTAssertEqual(G.tasks.filter{$0.variant==1}.count,67)
        XCTAssertEqual(Set(G.tasks.filter{$0.variant==1}.map(\.identity)).count,4,"A pose or shuffled options cannot manufacture another solid target")
    }
    func testEveryFeasibleReconstructionIncludingUnderdeterminedAndImpossibleSetsUsesIndependentEnumeration() throws {
        var counts:Set<Int>=[]
        for task in G.tasks where task.variant==3 {
            guard case let .reconstruction(value)=task else{continue}
            let expected=feasible(value.constraints);counts.insert(expected.count)
            XCTAssertEqual(Set(value.feasible),Set(expected));XCTAssertTrue(Set(expected).isSubset(of:Set(value.candidates)))
            let ids=expected.isEmpty ? ["none"]:value.candidates.indices.filter{expected.contains(value.candidates[$0])}.map(NFSpatialAssemblyContract.choiceID)
            for locale in ["en_US","ja_JP"] {
                let exercise=try generated(task,locale:locale),contract=try XCTUnwrap(NFSpatialAssemblyContract.make(exercise:exercise))
                XCTAssertEqual(Set(contract.acceptedOptionIDs),Set(ids))
                XCTAssertEqual(NFExerciseScoringEngine.score(.multipleChoice(optionIDs:ids),for:exercise).credit,1)
                if ids.count>1 {XCTAssertEqual(NFExerciseScoringEngine.score(.multipleChoice(optionIDs:[ids[0]]),for:exercise).credit,0,"All feasible arrangements are required")}
                if !expected.isEmpty {XCTAssertEqual(NFExerciseScoringEngine.score(.multipleChoice(optionIDs:["none"]),for:exercise).credit,0)}
                else {XCTAssertEqual(NFExerciseScoringEngine.score(.multipleChoice(optionIDs:["A"]),for:exercise).credit,0)}
            }
        }
        XCTAssertEqual(counts,[0,1,2,3,4,6]);XCTAssertEqual(G.heightMaps.count,237)
        XCTAssertEqual(G.tasks.filter{$0.variant==3}.count,78)
        XCTAssertEqual(Set(G.tasks.filter{$0.variant==3}.map(\.identity)).count,78)
    }
    func testVisibleAmbiguityAndIncompleteAlternativesCannotAcquireAFalseKey() throws {
        let original=try XCTUnwrap(G.tasks.compactMap{task->G.Orientation? in if case let .orientation(v)=task{return v};return nil}.first)
        let proper=orientations(original.source),visible=Set(proper.map(signature))
        let mirrors=orientations(canonical(original.source.map{C(x:-$0.x,y:$0.y,z:$0.z)}))
        let ambiguous=try XCTUnwrap(mirrors.first{visible.contains(signature($0))})
        var candidates=original.candidates;candidates[0]=ambiguous
        let malformed=G.Orientation(source:original.source,candidates:candidates)
        XCTAssertFalse(malformed.isBounded,"A hidden mirrored difference cannot reject the same supplied views as a proper orientation")
        let many=try XCTUnwrap(G.tasks.compactMap{task->G.Reconstruction? in if case let .reconstruction(v)=task,v.feasible.count==6{return v};return nil}.first)
        var incompleteCandidates=many.candidates
        let missing=try XCTUnwrap(incompleteCandidates.firstIndex(of:try XCTUnwrap(many.feasible.first)))
        incompleteCandidates[missing]=try XCTUnwrap(G.heightMaps.first{!many.candidates.contains($0) && !many.constraints.accepts($0)})
        let incomplete=G.Reconstruction(constraints:many.constraints,candidates:incompleteCandidates)
        XCTAssertEqual(Set(incompleteCandidates).count,8);XCTAssertFalse(incomplete.isBounded)
        XCTAssertFalse(G.permits([C(x:Int.max,y:0,z:0)]));XCTAssertTrue(G.normalized([C(x:Int.min,y:0,z:0)]).isEmpty)
        XCTAssertFalse(G.validHeights([0,1,1,0]),"Two diagonal unsupported components are not one face-connected assembly")
        XCTAssertFalse(G.validHeights([0,0,0,0]));XCTAssertFalse(G.validHeights([4,1,1,1]))
    }
    func testOriginalOnlyInspectionResetAndProtectedOrFutureContractsNeverExposeComputedReconstructions() throws {
        for task in [try XCTUnwrap(G.tasks.first{$0.variant==1}),try XCTUnwrap(G.tasks.first{$0.variant==3})] {
            let exercise=try generated(task),contract=try XCTUnwrap(NFSpatialAssemblyContract.make(exercise:exercise))
            let bytes=try NFImmutableAttemptRecordSnapshot.encoded(exercise);var state=NFSpatialAssemblyInspection()
            XCTAssertFalse(state.reveal(contract:contract,phase:.independent));XCTAssertNil(state.workedCells(contract:contract,index:0,phase:.independent))
            XCTAssertTrue(state.reveal(contract:contract,phase:.committedFeedback));XCTAssertNotNil(state.workedCells(contract:contract,index:0,phase:.committedFeedback))
            XCTAssertNil(state.workedCells(contract:contract,index:0,phase:.independent));state.reset()
            XCTAssertNil(state.workedCells(contract:contract,index:0,phase:.savedWorkedSolution));XCTAssertEqual(try NFImmutableAttemptRecordSnapshot.encoded(exercise),bytes)
            var future=exercise;future.contractMetadata?.spatialAssembly?.policyVersion=999
            XCTAssertNil(NFSpatialAssemblyContract.make(exercise:future));XCTAssertNil(NFResponsePresentation.expectedAnswer(for:future))
            XCTAssertEqual(NFExerciseScoringEngine.score(try answer(exercise),for:future).outcome,.invalidItem)
            var missing=exercise;missing.contractMetadata?.spatialAssembly=nil;XCTAssertFalse(missing.hasSupportedSpatialAssembly)
            var raw=try XCTUnwrap(JSONSerialization.jsonObject(with:JSONEncoder().encode(exercise)) as? [String:Any]);raw["assessmentProtected"]=true
            let protected=try JSONDecoder().decode(NFExercise.self,from:JSONSerialization.data(withJSONObject:raw))
            XCTAssertNil(NFSpatialAssemblyContract.make(exercise:protected));XCTAssertEqual(NFExerciseScoringEngine.score(try answer(exercise),for:protected).outcome,.invalidItem)
        }
        XCTAssertThrowsError(try NFFallbackExerciseGenerator.generate(.init(seed:1,index:0,lab:.spatial,purpose:.baseline,spatialAssemblyPolicyVersion:1)))
        XCTAssertThrowsError(try NFFallbackExerciseGenerator.generate(.init(seed:1,index:0,lab:.spatial,purpose:.practice,spatialAssemblyPolicyVersion:999)))
    }
    func testNilPolicyPreservesLegacyAndStructure11WhileNewRecipeCannotResumeUnderMissingPin() throws {
        for variant in [1,3] {
            let mechanic="fixture.fallback-variant-\(variant)"
            let legacy=try NFFallbackExerciseGenerator.generate(.init(seed:7,index:0,lab:.spatial,purpose:.practice,preferredAssessmentMechanicID:mechanic))
            let structure=try NFFallbackExerciseGenerator.generate(.init(seed:7,index:0,lab:.spatial,purpose:.practice,preferredAssessmentMechanicID:mechanic,spatialStructurePolicyVersion:1))
            let current=try NFFallbackExerciseGenerator.generate(.init(seed:7,index:0,lab:.spatial,purpose:.practice,preferredAssessmentMechanicID:mechanic,spatialStructurePolicyVersion:1,spatialAssemblyPolicyVersion:1))
            XCTAssertEqual(legacy.schemaVersion,2);XCTAssertEqual(structure.generatorVersion,11);XCTAssertEqual(structure.schemaVersion,8)
            XCTAssertEqual(current.generatorVersion,16);XCTAssertNotEqual(current.id,structure.id);XCTAssertNotEqual(current.id,legacy.id)
            var request=SessionRequest(lab:.spatial,source:.focused,seed:1,localeIdentifier:"en",requestedItemCount:2,isTimed:false)
            XCTAssertFalse(request.permitsSpatialAssembly(exercise:current));XCTAssertTrue(request.permitsSpatialAssembly(exercise:legacy))
            request.spatialAssemblyPolicyVersion=1;XCTAssertTrue(request.permitsSpatialAssembly(exercise:current))
            XCTAssertFalse(request.permitsSpatialAssembly(exercise:structure));XCTAssertFalse(request.permitsSpatialAssembly(exercise:legacy))
            XCTAssertEqual(request.launchOnly().spatialAssemblyPolicyVersion,1)
            XCTAssertTrue(NFEditorialNativeProtocol.supports(current));XCTAssertTrue(NFEditorialAdmissionContext.released.entries.isEmpty)
        }
    }
    func testActualSecondaryLaunchColdCommitHistoryAndNextKeepOriginalGivensAndFamily() async throws {
        for family in ["nf.default.spatial.object-rotation","nf.default.spatial.top-view"] {
            let (store,container,root)=try fixture();defer{withExtendedLifetime(container){}}
            let activity=try XCTUnwrap(NFDefaultContentCatalog.activity(id:family))
            XCTAssertTrue(store.beginDefaultCatalogSession(.init(activity:activity,field:.general),requestedItemCount:3,timingCondition:.init(.untimed),spatialAssemblyPolicyVersion:1))
            let runtime=NFUniversalSessionRuntime(request:try XCTUnwrap(store.activeSessionRequest))
            XCTAssertTrue(runtime.checkpointDraft(store:store));runtime.resume();runtime.acknowledgePresented()
            let exercise=runtime.exercise,response=try answer(exercise);enter(response,in:runtime)
            runtime.scratchpad="Original reconstruction reasoning."
            let saved=await runtime.checkpointDraftAsync(store:store);XCTAssertTrue(saved);runtime.releaseWriter()
            let envelope=try XCTUnwrap(store.localSessions.archive.sessions.first{$0.id==runtime.sessionID})
            let (coldStore,_,_)=try fixture(root:root,context:store.context,owner:store.localSessions.ownerDeviceID)
            XCTAssertNil(coldStore.localSessions.loadError)
            var request=envelope.request;request.localSessionID=envelope.id;request.localCheckpoint=envelope.checkpoint
            let cold=NFUniversalSessionRuntime(request:request);defer{cold.releaseWriter()}
            XCTAssertTrue(cold.checkpointDraft(store:coldStore));cold.resume();cold.acknowledgePresented()
            XCTAssertEqual(cold.exercise,exercise);XCTAssertEqual(cold.scratchpad,"Original reconstruction reasoning.")
            await cold.submitInlineAsync(store:coldStore);XCTAssertEqual(cold.stage,.feedback);XCTAssertEqual(cold.lastResult?.outcome,.correct)
            let attempt=try XCTUnwrap(coldStore.attempts.first),snapshot=try XCTUnwrap(coldStore.exerciseSnapshot(for:attempt.id))
            XCTAssertEqual(snapshot,exercise);XCTAssertEqual(NFResponsePresentation.decode(attempt.response),response)
            XCTAssertEqual(NFSpatialAssemblyContract.make(exercise:snapshot)?.familyID,family)
            XCTAssertFalse(NFResponsePresentation.text(response,exercise:snapshot).isEmpty)
            let original=try NFImmutableAttemptRecordSnapshot.encoded(NFImmutableAttemptRecordSnapshot(attempt))
            cold.next(store:coldStore);XCTAssertEqual(cold.index,1);XCTAssertNil(cold.saveError);XCTAssertNil(cold.nextUnavailableReason)
            XCTAssertEqual(NFSpatialAssemblyContract.make(exercise:cold.exercise)?.familyID,family)
            XCTAssertNotEqual(cold.exercise.contractMetadata?.semanticFingerprint,exercise.contractMetadata?.semanticFingerprint)
            XCTAssertEqual(try NFImmutableAttemptRecordSnapshot.encoded(NFImmutableAttemptRecordSnapshot(attempt)),original)
        }
    }
    func testGeneratedCompleteCandidateSetsStayExactThroughColdAsyncCommitAndHistory() async throws {
        for variant in [1,3] {
            let (store,container,_)=try fixture();defer{withExtendedLifetime(container){}}
            let task=try XCTUnwrap(G.tasks.first{$0.variant==variant && $0.acceptedIndices.count>1}),exercise=try generated(task,purpose:.documentPractice)
            let id=UUID(),contract=try XCTUnwrap(NFSpatialAssemblyContract.make(exercise:exercise))
            let request=NFAuthoringRequest(id:id,capability:.contextualize,lab:.spatial,field:.general,customTopic:"Synthetic physical reconstruction",learningObjective:"Identify all feasible occupied-cell arrangements",style:.spatialTransformation,difficulty:0.7,count:1,localeIdentifier:"en_US",seed:1,aiMode:.disabled)
            let expected=try XCTUnwrap(contract.options.first{contract.acceptedOptionIDs.contains($0.id)}).text
            let question=NFAuthoredQuestion(id:exercise.id,lab:.spatial,style:.spatialTransformation,prompt:exercise.prompt,context:"",choices:[],correctAnswer:expected,acceptedAnswers:[],explanation:exercise.feedback.correctExplanation,hint:exercise.feedback.hintLadder[0],decisiveStep:exercise.feedback.decisiveStep,difficulty:0.7,citationChunkIDs:[],evidenceClass:.documentPractice,authoritativeExercise:exercise)
            XCTAssertTrue(NFAuthoredExerciseAuthority.validatesBinding(question))
            let result=NFAuthoringResult(questions:[question],provenance:.init(requestID:id,generatedAt:Date().addingTimeInterval(-1),route:.deterministicFallback,routeReason:"Synthetic spatial assembly",promptVersion:NFAuthoringRequest.promptVersion,modelIdentifier:"synthetic.assembly",sourceChunkIDs:[],sourceDocumentIDs:[],validationVersion:NFAuthoringEngine.validationVersion,repairCount:0,cacheKey:"synthetic.assembly",isFallback:true),routeCandidates:[],validationStatus:.init(level:.deterministicKey,sourceSupport:.notApplicable),validationNotes:[])
            let runtime=AIGeneratedPracticeRuntime(result:result,request:request)
            XCTAssertTrue(runtime.checkpoint(store:store));runtime.resume();runtime.multipleChoiceIDs=Set(contract.acceptedOptionIDs)
            let didSave=await runtime.checkpointAsync(store:store);XCTAssertTrue(didSave)
            let draft=try XCTUnwrap(store.generatedPracticeDraft(for:id));runtime.releaseWriter()
            let cold=AIGeneratedPracticeRuntime(result:result,request:request,draft:draft);defer{cold.releaseWriter()}
            XCTAssertTrue(cold.restoreCheckpoint(store:store));cold.resume();XCTAssertEqual(cold.exercise,exercise)
            await cold.submitAsync(store:store);XCTAssertEqual(cold.stage,2);XCTAssertEqual(cold.lastScore?.outcome,.correct)
            let attempt=try XCTUnwrap(store.attempts.first),response=try answer(exercise)
            XCTAssertEqual(store.exerciseSnapshot(for:attempt.id),exercise);XCTAssertEqual(NFResponsePresentation.decode(attempt.response),response)
            XCTAssertEqual(draft.response,response)
        }
    }
    func testFrozenAssemblyCannotResumeUnderMissingPolicyOrWrongActivityAndPreservesOriginalBytes() throws {
        let (store,container,root)=try fixture();defer{withExtendedLifetime(container){}}
        let prior=try NFEditorialCanonicalData.encode(store.localSessions.archive)
        let wrongActivity=try XCTUnwrap(NFDefaultContentCatalog.activity(id:"nf.default.spatial.cube-net"))
        XCTAssertFalse(store.beginDefaultCatalogSession(.init(activity:wrongActivity,field:.general),requestedItemCount:2,timingCondition:.init(.untimed),spatialAssemblyPolicyVersion:1))
        XCTAssertEqual(try NFEditorialCanonicalData.encode(store.localSessions.archive),prior)
        let activity=try XCTUnwrap(NFDefaultContentCatalog.activity(id:"nf.default.spatial.top-view"))
        XCTAssertTrue(store.beginDefaultCatalogSession(.init(activity:activity,field:.general),requestedItemCount:2,timingCondition:.init(.untimed),spatialAssemblyPolicyVersion:1))
        let runtime=NFUniversalSessionRuntime(request:try XCTUnwrap(store.activeSessionRequest))
        XCTAssertTrue(runtime.checkpointDraft(store:store));runtime.resume();runtime.acknowledgePresented();enter(try answer(runtime.exercise),in:runtime)
        XCTAssertTrue(runtime.checkpointDraft(store:store));runtime.releaseWriter()
        let bytes=try Data(contentsOf:root.appending(path:"sessions.json")),saved=try XCTUnwrap(store.localSessions.archive.sessions.first{$0.id==runtime.sessionID})
        var wrong=saved.request;wrong.localSessionID=saved.id;wrong.localCheckpoint=saved.checkpoint;wrong.spatialAssemblyPolicyVersion=nil
        let unavailable=NFUniversalSessionRuntime(request:wrong);defer{unavailable.releaseWriter()}
        XCTAssertNotNil(unavailable.unavailableReason);XCTAssertFalse(unavailable.checkpointDraft(store:store));XCTAssertTrue(store.attempts.isEmpty)
        XCTAssertEqual(try Data(contentsOf:root.appending(path:"sessions.json")),bytes)
    }
    func testDetachedFiniteFactoryCollapsesCosmeticRotationsAndStopsAtActualTargets() async throws {
        let requests=try ["nf.default.spatial.object-rotation","nf.default.spatial.top-view"].map{id->SessionRequest in
            let activity=try XCTUnwrap(NFDefaultContentCatalog.activity(id:id))
            var request=SessionRequest(lab:.spatial,source:.focused,seed:20260905,localeIdentifier:"en",field:.general,requestedItemCount:8,isTimed:false,timingCondition:.init(.untimed),mechanicID:activity.mechanicID)
            request.spatialAssemblyPolicyVersion=1;return request
        }
        let totals=await Task.detached(priority:.userInitiated){()->[Int] in requests.map { request in
            var seen:Set<String>=[]
            for index in 0..<8 {
                let exercise=NFDeterministicSessionExerciseFactory.makeExercise(request:request,index:index,assessmentDescriptor:nil,excludingContentFingerprints:seen)
                guard exercise.availabilityReason == nil else{return seen.count}
                guard let contract=NFSpatialAssemblyContract.make(exercise:exercise),seen.insert(NFQuestionFingerprint.spatialAssemblyFingerprint(identity:contract.task.identity)).inserted else{return -1}
            }
            return seen.count
        }}.value
        XCTAssertEqual(totals,[4,8]);XCTAssertEqual(G.tasks.count,145);XCTAssertEqual(Set(G.tasks.map(\.identity)).count,82)
    }
}

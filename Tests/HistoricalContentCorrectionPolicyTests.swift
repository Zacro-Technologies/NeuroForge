import XCTest
import SwiftData
@testable import NeuroForge

final class HistoricalContentCorrectionPolicyTests: XCTestCase {
    func testFrozenNumericAliasCorrectionRequiresAuthenticContractAndPreservesOriginalResult() throws {
        let contract = frozenGermanEstimateContract()
        let item = try snapshot(.logicState(contract.responseSchema), family: "estimate-first",
            prompt: "Give the nearest power of ten to 198 × 48, then its exact product and a plausibility judgment.")
        let response = NFExerciseResponse.logicState(.init(finalState: [NFEstimateExactContract.estimateKey: "10.000",
            NFEstimateExactContract.plausibilityKey: "yes", NFEstimateExactContract.exactKey: "9.504"], violatedRuleID: nil))
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        for (scorer, credit) in [(7, 2.0 / 3.0), (8, 1.0)] {
            let original = try evidence(item, response: response, correct: true, credit: credit, scoringVersion: scorer)
            let bytes = try encoder.encode(original)
            let audit = NFContentCorrectionPolicy.audit(original)
            let correction = try XCTUnwrap(audit.recommendations.first { $0.ruleID == "contradictory-estimate-exact-alias" })
            XCTAssertEqual(correction.disposition, .excludedInvalidItem)
            XCTAssertTrue(correction.excludedScopes.contains(.accuracy))
            XCTAssertTrue(correction.excludedScopes.contains(.bandEvidence))
            XCTAssertNil(correction.correctedCredit)
            XCTAssertNil(correction.correctedScorerVersion)
            XCTAssertEqual(correction.originalContractDigest, try NFLocalItemCheckpoint.digest(item))
            XCTAssertFalse(audit.recommendations.contains { $0.ruleID == "accepted-state-equivalent" })
            XCTAssertEqual(audit, NFContentCorrectionPolicy.audit(original))
            XCTAssertEqual(try encoder.encode(original), bytes)
            for mode in 0..<3 {
                var unauthenticated = original
                if mode == 0 { unauthenticated.exactSnapshot = nil }
                if mode == 1 { unauthenticated.snapshotVerifiedAsOriginal = false }
                if mode == 2 { unauthenticated.generatorVersion = 999 }
                XCTAssertFalse(NFContentCorrectionPolicy.audit(unauthenticated).recommendations.contains {
                    $0.ruleID == "contradictory-estimate-exact-alias"
                })
            }
            var oldRecord = try XCTUnwrap(JSONSerialization.jsonObject(with: encoder.encode(correction)) as? [String: Any])
            oldRecord.removeValue(forKey: "originalContractDigest")
            let decoded = try JSONDecoder().decode(NFHistoricalContentCorrectionRecommendation.self,
                from: JSONSerialization.data(withJSONObject: oldRecord))
            XCTAssertNil(decoded.originalContractDigest, "Existing append-only recommendations remain readable")
        }
    }

    func testValidNumericExactAndJudgmentAliasesDoNotTriggerHistoricalInvalidation() throws {
        let contract = NFEstimateExactContract(estimate: "10000", acceptedEstimateAlternatives: ["9000"],
            plausibility: "plausible", acceptedPlausibilityAlternatives: ["yes"], exact: "9504",
            acceptedExactAlternatives: ["9,504", "9504.0"])
        let item = try snapshot(.logicState(contract.responseSchema), family: "estimate-first")
        var accepted = contract.responseSchema.expectedFinalState
        accepted[NFEstimateExactContract.estimateKey] = "9000"
        accepted[NFEstimateExactContract.exactKey] = "9,504"
        accepted[NFEstimateExactContract.plausibilityKey] = "yes"
        let audit = NFContentCorrectionPolicy.audit(try evidence(item,
            response: .logicState(.init(finalState: accepted, violatedRuleID: nil)), correct: true, credit: 2.0 / 3.0))
        XCTAssertFalse(audit.recommendations.contains { $0.disposition == .excludedInvalidItem })
        XCTAssertEqual(audit.recommendations.first { $0.ruleID == "accepted-state-equivalent" }?.correctedCredit, 1)
    }

    @MainActor
    func testAppStoreAuditsOnlyAffectedScorerEightSnapshotsAndReplaysExclusionIdempotently() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("NF-Frozen-Alias-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("local.json")
        let repository = NFLocalSessionRepository(url: url)
        let container = try ModelContainer(for: Schema(NFSchemaV1.models), configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let bad = try snapshot(.logicState(frozenGermanEstimateContract().responseSchema), family: "estimate-first")
        let wrong = NFExerciseResponse.logicState(.init(finalState: [NFEstimateExactContract.estimateKey: "10.000",
            NFEstimateExactContract.plausibilityKey: "yes", NFEstimateExactContract.exactKey: "9.504"], violatedRuleID: nil))
        let affected = try historyRecord(bad, response: wrong, credit: 1)
        affected.scoringVersion = 8
        let originalResponse = affected.response
        let originalKey = affected.correctAnswerText
        let good = try snapshot(.logicState(NFEstimateExactContract(estimate: "10000", acceptedEstimateAlternatives: [],
            plausibility: "plausible", acceptedPlausibilityAlternatives: ["yes"], exact: "9504",
            acceptedExactAlternatives: ["9,504"]).responseSchema), family: "valid-estimate-first")
        let unaffected = try historyRecord(good, response: .logicState(.init(finalState: [NFEstimateExactContract.estimateKey: "10000",
            NFEstimateExactContract.plausibilityKey: "yes", NFEstimateExactContract.exactKey: "9,504"], violatedRuleID: nil)), credit: 1)
        unaffected.scoringVersion = 8
        container.mainContext.insert(affected)
        container.mainContext.insert(unaffected)
        try container.mainContext.save()
        try repository.retainSnapshot(attemptID: affected.id, exercise: bad)
        try repository.retainSnapshot(attemptID: unaffected.id, exercise: good)
        let store = AppStore(context: container.mainContext, localSessionRepository: repository, allowsSharedWidgetPublishing: false)
        store.reload()
        try store.reconcileHistoricalAuthority()
        let disposition = try XCTUnwrap(store.evidenceDispositions.first { $0.attemptID == affected.id.uuidString })
        XCTAssertEqual(disposition.disposition, .excludedContentCorrection)
        XCTAssertNil(disposition.correctedDerivedCredit)
        XCTAssertFalse(store.evidenceDispositions.contains { $0.attemptID == unaffected.id.uuidString })
        XCTAssertNil(repository.archive.activeContentCorrectionIDs?[unaffected.id.uuidString])
        let corrections = try XCTUnwrap(repository.archive.contentCorrections)
        XCTAssertEqual(corrections.count, 1)
        XCTAssertEqual(corrections[0].originalContractDigest, try NFLocalItemCheckpoint.digest(bad))
        let replayRepository = NFLocalSessionRepository(url: url, ownerDeviceID: repository.ownerDeviceID)
        XCTAssertNil(replayRepository.loadError)
        let replay = AppStore(context: container.mainContext, localSessionRepository: replayRepository, allowsSharedWidgetPublishing: false)
        replay.reload()
        try replay.reconcileHistoricalAuthority()
        XCTAssertEqual(replay.evidenceDispositions, store.evidenceDispositions)
        XCTAssertEqual(replayRepository.archive.contentCorrections, corrections)
        XCTAssertEqual(replayRepository.archive.activeContentCorrectionIDs, repository.archive.activeContentCorrectionIDs)
        XCTAssertEqual(replay.exerciseSnapshot(for: affected.id), bad)
        XCTAssertEqual(affected.response, originalResponse)
        XCTAssertEqual(affected.correctAnswerText, originalKey)
        XCTAssertEqual(affected.scoringVersion, 8)
        XCTAssertEqual(affected.deterministicCredit, 1)
        XCTAssertTrue(affected.isCorrect)
        let summary = try XCTUnwrap(NFHistoricalPracticeProjection.reduce(attempts: replay.attempts.map(\.dto),
            dispositions: replay.evidenceDispositions).first)
        XCTAssertEqual(summary.legacyCount, 1)
        XCTAssertEqual(summary.excludedAttemptIDs, [affected.id.uuidString])
        XCTAssertEqual(summary.legacyMeanCredit, 1)
    }

    private func frozenGermanEstimateContract() -> NFEstimateExactContract {
        .init(estimate: "10000", acceptedEstimateAlternatives: [10_000.formatted(.number.locale(Locale(identifier: "de_DE")))],
            plausibility: "plausible", acceptedPlausibilityAlternatives: ["yes"], exact: "9504",
            acceptedExactAlternatives: [9_504.formatted(.number.locale(Locale(identifier: "de_DE")))])
    }

    func testDuplicateEquivalentCoordinatesReceiveFullDerivedCreditWithoutChangingOriginal() throws {
        let choices = NFSingleChoiceResponseSchema(options: [option("key", "(-10, 10)"), option("alias", "(-10.0, 10.00)"), option("wrong", "(10, -10)")], correctOptionID: "key")
        let item = try snapshot(.singleChoice(choices), family: "coordinate.rotate-ccw")
        let input = try evidence(item, response: .singleChoice(optionID: "alias"), correct: false, credit: 0)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let bytes = try encoder.encode(input)
        let audit = NFContentCorrectionPolicy.audit(input)
        let correction = try XCTUnwrap(audit.recommendations.first { $0.ruleID == "duplicate-equivalent-choice" })
        XCTAssertEqual(correction.correctedCredit, 1)
        XCTAssertFalse(correction.excludedScopes.contains(.accuracy))
        XCTAssertTrue(correction.excludedScopes.contains(.cleanSpeed))
        XCTAssertEqual(try encoder.encode(input), bytes)
        XCTAssertEqual(audit, NFContentCorrectionPolicy.audit(input))
        XCTAssertEqual(correction.originalResultDigest.count, 64)
        XCTAssertEqual(correction.correctedScorerVersion, 8)
    }

    func testDuplicateWrongChoiceIsExcludedAndMissingSnapshotNeverReconstructed() throws {
        let item = try snapshot(.singleChoice(.init(options: [option("a", "1/2"), option("b", "0.5"), option("c", "1")], correctOptionID: "a")), family: "coordinate.rotate-ccw")
        let bad = NFContentCorrectionPolicy.audit(try evidence(item, response: .singleChoice(optionID: "c"), correct: false, credit: 0))
        XCTAssertTrue(bad.recommendations.contains { $0.disposition == .excludedInvalidItem && $0.excludedScopes.contains(.accuracy) })
        XCTAssertFalse(bad.recommendations.contains { $0.correctedCredit != nil })
        var unavailable = try evidence(item, response: .singleChoice(optionID: "b"), correct: false, credit: 0)
        unavailable.exactSnapshot = nil
        let unresolved = NFContentCorrectionPolicy.audit(unavailable)
        XCTAssertTrue(unresolved.unresolved.contains(.missingOriginalSnapshot))
        XCTAssertFalse(unresolved.recommendations.contains { $0.correctedCredit != nil })
        XCTAssertTrue(unresolved.recommendations.contains { $0.disposition == .excludedUnverifiableContract })
    }

    func testSymbolCaseIsNotAnEquivalentDuplicateChoice() throws {
        let item = try snapshot(.singleChoice(.init(options: [option("a", "F(b)-F(a)"), option("b", "f(b)-f(a)")], correctOptionID: "a")))
        let result = NFContentCorrectionPolicy.audit(try evidence(item, response: .singleChoice(optionID: "a"), correct: true, credit: 1))
        XCTAssertFalse(result.recommendations.contains { $0.ruleID.contains("duplicate") })
    }

    func testCoordinateOracleRejectsAnEquivalentButInvalidHistoricalKey() throws {
        let point = NFSpatialRepresentationMetadata(stimulusCategory: "coordinate-geometry", dimension: .twoDimensional,
            objectDescription: "Point P", viewpoint: "Front", operations: [.coordinateTransform],
            points: [.init(label: "P", x: 10, y: 10, z: nil)], axisLabels: ["x", "y"],
            accessibilityDescription: "Rotate point P counterclockwise by 90 degrees", assetName: nil, protectedGrammarID: nil,
            difficultyParameters: .legacy(viewpoint: "Front"))
        for (answer, fullCredit) in [("(-10, 10)", true), ("(10, -10)", false)] {
            let item = try snapshot(.singleChoice(.init(options: [option("a", answer), option("b", answer), option("c", "(10, 10)")], correctOptionID: "a")),
                family: "coordinate.rotate-ccw", representations: [.spatial(point)])
            let audit = NFContentCorrectionPolicy.audit(try evidence(item, response: .singleChoice(optionID: "b"), correct: false, credit: 0))
            XCTAssertEqual(audit.recommendations.contains { $0.correctedCredit == 1 }, fullCredit)
            XCTAssertEqual(audit.recommendations.contains { $0.disposition == .excludedInvalidItem }, !fullCredit)
        }
    }

    func testContradictoryIntervalExcludesOnlyProvenBadGeometry() throws {
        for (second, contradictory) in [("27–35", true), ("26–35", true), ("25–35", false)] {
            let item = try snapshot(.singleChoice(.init(options: [option("a", "A claim"), option("b", "B claim")], correctOptionID: "a")),
                family: "data-forensics.uncertainty", prompt: "A report shows overlapping intervals. Which conclusion is supported?",
                representations: [.table(headers: ["Group", "Mean", "Interval"], rows: [["A", "22", "18–26"], ["B", "31", second]], accessibilitySummary: "Original intervals")])
            let audit = NFContentCorrectionPolicy.audit(try evidence(item, response: .singleChoice(optionID: "a"), correct: true, credit: 1))
            XCTAssertEqual(audit.recommendations.contains { $0.ruleID == "contradictory-interval" }, contradictory)
            XCTAssertFalse(audit.recommendations.contains { $0.correctedCredit != nil })
        }
    }

    func testOriginalStateAliasRestoresFullCreditButUnlistedAliasDoesNot() throws {
        let schema = NFLogicStateResponseSchema(initialState: [:], expectedFinalState: ["estimate": "10000", "plausible": "plausible", "exact": "9504"],
            acceptedEquivalentStates: [["estimate": "10000", "plausible": "yes", "exact": "9504"]], ruleOptions: [], expectedViolatedRuleID: nil)
        let item = try snapshot(.logicState(schema), family: "estimate-first")
        let original = try evidence(item, response: .logicState(.init(finalState: schema.acceptedEquivalentStates[0], violatedRuleID: nil)), correct: true, credit: 2.0 / 3.0)
        XCTAssertEqual(NFContentCorrectionPolicy.audit(original).recommendations.first { $0.ruleID == "accepted-state-equivalent" }?.correctedCredit, 1)
        let unlisted = try evidence(item, response: .logicState(.init(finalState: ["estimate": "10000", "plausible": "sure", "exact": "9504"], violatedRuleID: nil)), correct: false, credit: 2.0 / 3.0)
        XCTAssertFalse(NFContentCorrectionPolicy.audit(unlisted).recommendations.contains { $0.correctedCredit != nil })
        var absent = original
        absent.exactSnapshot = nil
        XCTAssertTrue(NFContentCorrectionPolicy.audit(absent).recommendations.contains { $0.ruleID == "unverifiable-state-equivalence" })
    }

    func testExactOriginalFFRolesCorrectFalseAcceptanceAndPreserveCase() throws {
        for (response, expectedCredit) in [("f(b)-f(a)", 0.0), ("F(a)-F(b)", 0.0), ("(F(b))-((F(a)))", 1.0)] {
            let input = rawText(response, prompt: integralPrompt, answer: "F(b) minus F(a)", correct: expectedCredit == 0, credit: 1 - expectedCredit)
            let result = NFContentCorrectionPolicy.audit(input)
            XCTAssertEqual(result.recommendations.first { $0.ruleID == "integral-function-role" }?.correctedCredit, expectedCredit)
        }
        let unsupported = NFContentCorrectionPolicy.audit(rawText("integral(f,a,b)", prompt: integralPrompt, answer: "F(b) minus F(a)", correct: true, credit: 1))
        XCTAssertTrue(unsupported.unresolved.contains(.unsupportedSymbolicResponse))
        XCTAssertTrue(unsupported.recommendations.contains { $0.disposition == .withdrawnDisputedGrade && $0.correctedCredit == nil })
        let reversedRoles = NFContentCorrectionPolicy.audit(rawText("f(b)-f(a)", prompt: "If f prime equals F, integrate F from a to b.", answer: "f(b)-f(a)", correct: true, credit: 1))
        XCTAssertFalse(reversedRoles.recommendations.contains { $0.correctedCredit != nil })
    }

    func testReviewedProseAliasCanCorrectWithoutModelAndUnknownDoesNotInventCredit() throws {
        let prompt = "How is the arithmetic mean of a finite set of numbers calculated?"
        let answer = "Add the values and divide by the number of values"
        let reviewed = NFContentCorrectionPolicy.audit(rawText("Sum all observations then divide by their count", prompt: prompt, answer: answer, correct: false, credit: 0))
        XCTAssertEqual(reviewed.recommendations.first { $0.correctedCredit != nil }?.correctedCredit, 1)
        let unknown = NFContentCorrectionPolicy.audit(rawText("Find the common centre", prompt: prompt, answer: answer, correct: false, credit: 0))
        XCTAssertTrue(unknown.unresolved.contains(.unreviewedProseEquivalence))
        XCTAssertFalse(unknown.recommendations.contains { $0.correctedCredit != nil })
        XCTAssertTrue(unknown.recommendations.contains { $0.disposition == .withdrawnDisputedGrade })
    }

    func testSelfCheckRatingPreservedAndFormatProvenancePreventsObjectiveAuthority() throws {
        let item = try snapshot(.selfCheck(.init(referenceAnswer: "Personal comparison", criteria: ["Compare"], asksForReflection: true)))
        for rating in NFSelfCheckRating.allCases {
            let input = try evidence(item, response: .selfCheck(.init(rating: rating, reflection: "My exact reflection")), correct: true, credit: 1)
            let audit = NFContentCorrectionPolicy.audit(input)
            XCTAssertEqual(audit.recommendations.count, 1)
            XCTAssertEqual(audit.recommendations.first?.disposition, .selfReported)
            XCTAssertTrue(audit.recommendations.first?.excludedScopes.contains(.accuracy) == true)
            XCTAssertNil(audit.recommendations.first?.correctedCredit)
            XCTAssertEqual(try JSONDecoder().decode(NFExerciseResponse.self, from: Data(input.rawResponse.utf8)), .selfCheck(.init(rating: rating, reflection: "My exact reflection")))
        }
    }

    func testWorkflowAndVisibleSolutionOnlyExcludeRelevantClaims() throws {
        let workflow = try snapshot(.orderedSteps(.init(steps: [
            .init(id: "retrieve", text: "Attempt the answer before consulting the reference."),
            .init(id: "compare", text: "Compare the recalled relationship with the cited answer."),
            .init(id: "locate", text: "Locate the exact missing, reversed, or unsupported element."),
            .init(id: "retry", text: "Close the reference and retrieve the corrected relationship once more.")
        ], correctOrder: ["retrieve", "compare", "locate", "retry"])), family: "reconstruction.ordered-cycle")
        let result = NFContentCorrectionPolicy.audit(try evidence(workflow, response: .orderedSteps(stepIDs: ["retrieve", "compare", "locate", "retry"]), correct: true, credit: 1))
        let method = try XCTUnwrap(result.recommendations.first { $0.ruleID == "workflow-objective-only" })
        XCTAssertFalse(method.excludedScopes.contains(.accuracy))
        XCTAssertTrue(method.excludedScopes.contains(.retention))
        let leaked = try snapshot(.singleChoice(.init(options: [option("a", "2 and 3"), option("b", "2 and 4")], correctOptionID: "a")), family: "counterexample.even-product", representations: [.equation(latex: "2 \\times 3 = 6", spokenDescription: "Two times three equals six")])
        let assisted = NFContentCorrectionPolicy.audit(try evidence(leaked, response: .singleChoice(optionID: "a"), correct: true, credit: 1))
        let correction = try XCTUnwrap(assisted.recommendations.first { $0.ruleID == "visible-solution-scaffold" })
        XCTAssertFalse(correction.excludedScopes.contains(.accuracy))
        XCTAssertTrue(correction.excludedScopes.contains(.independentEvidence))
        XCTAssertNil(correction.correctedCredit)
    }

    func testTimingReportAndLegacyMetadataNeverGuessOrRetroactivelyInvalidate() throws {
        var input = rawText("saved", prompt: "An ordinary historical question", answer: "saved", correct: true, credit: 1)
        var audit = NFContentCorrectionPolicy.audit(input)
        XCTAssertEqual(audit.recommendations.map(\.disposition), [.legacyUncalibrated])
        XCTAssertFalse(audit.recommendations[0].excludedScopes.contains(.accuracy))
        input.confirmedTimingWasLostOnResume = true
        input.hasUnresolvedContentReport = true
        audit = NFContentCorrectionPolicy.audit(input)
        XCTAssertEqual(audit.recommendations.first { $0.ruleID == "lost-resume-provenance" }?.excludedScopes, [.cleanSpeed])
        XCTAssertEqual(audit.recommendations.first { $0.ruleID == "unresolved-content-report" }?.excludedScopes, [])
        XCTAssertFalse(audit.recommendations.contains { $0.excludedScopes.contains(.accuracy) })
        input.confirmedAssistanceHistoryWasLostOnResume = true
        XCTAssertTrue(NFContentCorrectionPolicy.audit(input).recommendations.first { $0.ruleID == "lost-resume-provenance" }?.excludedScopes.contains(.independentEvidence) == true)
    }

    func testUntrustedOrMismatchingSnapshotCannotSupplyCorrectionAuthority() throws {
        let item = try snapshot(.singleChoice(.init(options: [option("a", "0.5"), option("b", "1/2")], correctOptionID: "a")), family: "coordinate.rotate-ccw")
        var input = try evidence(item, response: .singleChoice(optionID: "b"), correct: false, credit: 0)
        input.snapshotVerifiedAsOriginal = false
        var audit = NFContentCorrectionPolicy.audit(input)
        XCTAssertTrue(audit.unresolved.contains(.unverifiedSnapshot))
        XCTAssertFalse(audit.recommendations.contains { $0.correctedCredit != nil })
        input.snapshotVerifiedAsOriginal = true
        input.exactSnapshot = try snapshot(item.interaction, family: "coordinate.rotate-ccw", prompt: "Different historical prompt")
        audit = NFContentCorrectionPolicy.audit(input)
        XCTAssertTrue(audit.unresolved.contains(.snapshotIdentityMismatch))
        XCTAssertFalse(audit.recommendations.contains { $0.correctedCredit != nil })
    }

    func testCorrectionKeysRemainStableAcrossReplayAndChangeWithOriginalEvidence() throws {
        let original = rawText("f(b)-f(a)", prompt: integralPrompt, answer: "F(b) minus F(a)", correct: true, credit: 1)
        let first = NFContentCorrectionPolicy.audit(original)
        var withReport = original
        withReport.hasUnresolvedContentReport = true
        let replay = NFContentCorrectionPolicy.audit(withReport)
        XCTAssertEqual(first.recommendations.first { $0.ruleID == "integral-function-role" }?.idempotencyKey,
                       replay.recommendations.first { $0.ruleID == "integral-function-role" }?.idempotencyKey)
        var changed = original
        changed.originalResultPayload = Data("authentic additional old result bytes".utf8)
        XCTAssertNotEqual(first.recommendations.first?.originalResultDigest, NFContentCorrectionPolicy.audit(changed).recommendations.first?.originalResultDigest)
        let roundTrip = try JSONDecoder().decode(NFHistoricalContentCorrectionAudit.self, from: JSONEncoder().encode(first))
        XCTAssertEqual(first, roundTrip)
    }

    func testShippedTemplateEditionBoundsMissingGeneratorWithoutGuessingCustomLineage() {
        let old = NFHistoricalContentCorrectionInput(attemptID: "original", itemID: "item",
            templateID: "nf.fallback.scientificReasoning.practice.v3.data-forensics.uncertainty", originalScoringVersion: 7,
            prompt: "Original interval prompt", rawResponse: "correct", originalExpectedAnswer: "Saved answer", originalIsCorrect: true, originalCredit: 1)
        XCTAssertTrue(NFContentCorrectionPolicy.audit(old).recommendations.contains { $0.ruleID == "unverifiable-interval" })
        let custom = NFHistoricalContentCorrectionInput(attemptID: "original", itemID: "item",
            templateID: "custom.data-forensics.uncertainty", originalScoringVersion: 7,
            prompt: "Original interval prompt", rawResponse: "correct", originalExpectedAnswer: "Saved answer", originalIsCorrect: true, originalCredit: 1)
        XCTAssertFalse(NFContentCorrectionPolicy.audit(custom).recommendations.contains { $0.ruleID == "unverifiable-interval" })
    }

    @MainActor
    func testHistoryPresentsAliasCorrectionAlongsideOriginalPartialCredit() throws {
        let state = NFLogicStateResponseSchema(initialState: [:], expectedFinalState: ["plausible": "plausible"],
            acceptedEquivalentStates: [["plausible": "yes"]], ruleOptions: [], expectedViolatedRuleID: nil)
        let item = try snapshot(.logicState(state), family: "estimate-first")
        let record = try historyRecord(item, response: .logicState(.init(finalState: ["plausible": "yes"], violatedRuleID: nil)), credit: 2.0 / 3.0)
        let originalBytes = record.response
        let raw = NFReadOnlyAttemptSnapshot(attempt: record)
        let correction = try XCTUnwrap(historyAudit(record, item: item).first { $0.ruleID == "accepted-state-equivalent" })
        let disposition = historyDisposition(record, correction: correction, excluded: false)
        let presented = raw.applyingHistoricalCorrections(dispositions: [disposition], corrections: [correction], activeIDs: [correction.id])
        XCTAssertEqual(presented.effectiveCredit, 1)
        XCTAssertEqual(presented.effectiveResult, .correct)
        XCTAssertTrue(presented.hasObjectiveResult)
        XCTAssertEqual(presented.deterministicCredit, 2.0 / 3.0)
        XCTAssertEqual(presented.originalResultTitle, raw.originalResultTitle)
        XCTAssertEqual(presented.reviewExplanation(exercise: item), item.feedback.correctExplanation)
        XCTAssertEqual(presented.correction?.reasons, [correction.rationale])
        XCTAssertEqual(presented.rawResponse, originalBytes)
        XCTAssertEqual(record.response, originalBytes)
        XCTAssertEqual(record.deterministicCredit, 2.0 / 3.0)
    }

    @MainActor
    func testHistoryInvalidIntervalIsExcludedAndOriginalKeyIsDisputedWithProtectionFirst() throws {
        let item = try snapshot(.singleChoice(.init(options: [option("a", "Original keyed claim canary"), option("b", "Alternative claim")], correctOptionID: "a")),
            family: "data-forensics.uncertainty", prompt: "The figure shows overlapping intervals.",
            representations: [.table(headers: ["Group", "Mean", "Interval"], rows: [["A", "22", "18–26"], ["B", "31", "27–35"]], accessibilitySummary: "Original intervals")])
        let record = try historyRecord(item, response: .singleChoice(optionID: "a"), credit: 1)
        let raw = NFReadOnlyAttemptSnapshot(attempt: record)
        let correction = try XCTUnwrap(historyAudit(record, item: item).first { $0.ruleID == "contradictory-interval" })
        let disposition = historyDisposition(record, correction: correction, excluded: true)
        let presented = raw.applyingHistoricalCorrections(dispositions: [disposition], corrections: [correction], activeIDs: [correction.id])
        XCTAssertEqual(presented.effectiveResult, .all)
        XCTAssertFalse(presented.hasObjectiveResult)
        XCTAssertTrue(presented.hasDisputedKey)
        XCTAssertEqual(presented.result, .correct)
        XCTAssertEqual(presented.deterministicCredit, 1)
        XCTAssertEqual(presented.correctAnswer, "Original saved key canary")
        XCTAssertEqual(presented.reviewExplanation(exercise: item), item.feedback.correctExplanation)
        XCTAssertTrue(presented.correction?.reasons.contains(correction.rationale) == true)

        // Even a mismarked imported record is restricted before its exact
        // protected snapshot could become labels, key, feedback, or AX text.
        let protected = raw.applyingHistoricalCorrections(dispositions: [disposition], corrections: [correction],
            activeIDs: [correction.id], protectedSnapshot: true)
        XCTAssertEqual(protected.source, .protectedAssessment)
        XCTAssertNil(protected.correction)
        XCTAssertEqual(protected.effectiveResult, .all)
        XCTAssertFalse(protected.hasObjectiveResult)
        XCTAssertEqual(protected.correctAnswer, "")
        XCTAssertFalse(protected.readableResponse(exercise: item).contains("Original keyed claim canary"))
        XCTAssertFalse(protected.reviewExplanation(exercise: item).contains(item.feedback.correctExplanation))
        XCTAssertEqual(record.correctAnswerText, "Original saved key canary")
        XCTAssertTrue(record.isCorrect)
    }

    @MainActor
    func testHistoryAssistedCorrectionRetainsAccuracyWithoutIndependentOrTimedEvidence() throws {
        let item = try snapshot(.singleChoice(.init(options: [option("a", "2 and 3"), option("b", "2 and 4")], correctOptionID: "a")),
            family: "counterexample.even-product", representations: [.equation(latex: "2 \\times 3 = 6", spokenDescription: "Two times three equals six")])
        let record = try historyRecord(item, response: .singleChoice(optionID: "a"), credit: 1)
        record.wasTimed = true
        record.activeDurationSeconds = 12
        let raw = NFReadOnlyAttemptSnapshot(attempt: record)
        let correction = try XCTUnwrap(historyAudit(record, item: item).first { $0.ruleID == "visible-solution-scaffold" })
        let presented = raw.applyingHistoricalCorrections(dispositions: [], corrections: [correction], activeIDs: [correction.id])
        XCTAssertEqual(presented.effectiveCredit, 1)
        XCTAssertEqual(presented.effectiveResult, .correct)
        XCTAssertTrue(presented.hasObjectiveResult)
        XCTAssertTrue(presented.usedSupport)
        XCTAssertFalse(presented.effectiveWasTimed)
        XCTAssertEqual(presented.supportTitle, NFAppLocalization.localizedCatalogValue("Assisted practice", locale: NFAppLocalization.preferredLocale))
        XCTAssertEqual(presented.timingTitle, NFAppLocalization.localizedCatalogValue("Timing evidence unavailable", locale: NFAppLocalization.preferredLocale))
        XCTAssertEqual(presented.hintCount, 0)
        XCTAssertEqual(record.hintCount, 0)
        XCTAssertTrue(record.wasTimed)
        XCTAssertEqual(record.activeDurationSeconds, 12)
        XCTAssertEqual(record.deterministicCredit, 1)
    }

    @MainActor
    func testHistoryAmendmentSurvivesDismissalAndIgnoresInactiveOrForeignPolicyRules() throws {
        let item = try snapshot(.singleChoice(.init(options: [option("a", "1/2"), option("b", "0.5")], correctOptionID: "a")), family: "duplicate")
        let record = try historyRecord(item, response: .singleChoice(optionID: "b"), credit: 0)
        let correction = try XCTUnwrap(historyAudit(record, item: item).first { $0.ruleID == "duplicate-equivalent-choice" })
        let disposition = historyDisposition(record, correction: correction, excluded: false)
        let repository = NFLocalSessionRepository()
        try repository.appendDispositions([disposition], contentCorrections: [correction], activeContentCorrectionIDs: [record.id.uuidString: [correction.id]])
        let raw = NFReadOnlyAttemptSnapshot(attempt: record)
        func presentation() -> NFReadOnlyAttemptSnapshot {
            raw.applyingHistoricalCorrections(dispositions: repository.archive.evidenceDispositions ?? [],
                corrections: repository.archive.contentCorrections ?? [], activeIDs: repository.archive.activeContentCorrectionIDs?[record.id.uuidString])
        }
        let before = presentation()
        try repository.dismissCorrections([disposition.id])
        let after = presentation()
        XCTAssertEqual(after.correction, before.correction)
        XCTAssertEqual(after.effectiveCredit, 1)
        XCTAssertTrue(repository.archive.dismissedCorrectionIDs?.contains(disposition.id) == true)
        XCTAssertNil(raw.applyingHistoricalCorrections(dispositions: [], corrections: [correction], activeIDs: []).correction)
        let foreign = NFHistoricalPracticeDispositionRecord(id: "foreign", attemptID: record.id.uuidString, revision: 99,
            policyVersion: "UnsupportedFuturePolicy", occurredAt: record.submittedAt, disposition: .excludedContentCorrection,
            reason: "This foreign policy cannot change the display", correctedDerivedCredit: nil, supersedesDispositionID: nil)
        XCTAssertNil(raw.applyingHistoricalCorrections(dispositions: [foreign], corrections: [], activeIDs: []).correction)
        XCTAssertEqual(record.deterministicCredit, 0)
    }

    @MainActor
    private func historyRecord(_ item: NFExercise, response: NFExerciseResponse, credit: Double) throws -> AttemptRecord {
        let record = AttemptRecord(sessionID: UUID(), lab: item.lab, itemID: item.id, prompt: item.prompt,
            response: String(decoding: try JSONEncoder().encode(response), as: UTF8.self), correctAnswer: "Original saved key canary",
            isCorrect: credit > 0, confidence: .certain, evidenceClass: .practice, source: .focused)
        record.templateID = item.templateID
        record.responseFormatRaw = response.responseFormatRaw
        record.scoringVersion = 7
        record.deterministicCredit = credit
        return record
    }

    @MainActor
    private func historyAudit(_ record: AttemptRecord, item: NFExercise) -> [NFHistoricalContentCorrectionRecommendation] {
        var input = NFHistoricalContentCorrectionInput(attemptID: record.id.uuidString, itemID: record.itemID, templateID: record.templateID,
            originalScoringVersion: record.scoringVersion, prompt: record.prompt, rawResponse: record.response,
            originalExpectedAnswer: record.correctAnswerText, originalIsCorrect: record.isCorrect, originalCredit: record.deterministicCredit)
        input.responseFormatRaw = record.responseFormatRaw
        input.generatorVersion = item.generatorVersion
        input.exactSnapshot = item
        input.snapshotVerifiedAsOriginal = true
        return NFContentCorrectionPolicy.audit(input).recommendations
    }

    @MainActor
    private func historyDisposition(_ record: AttemptRecord, correction: NFHistoricalContentCorrectionRecommendation, excluded: Bool) -> NFHistoricalPracticeDispositionRecord {
        .init(id: correction.id, attemptID: record.id.uuidString, revision: 1, policyVersion: NFHistoricalPracticeProjection.policyVersion,
            occurredAt: record.submittedAt, disposition: excluded ? .excludedContentCorrection : .legacyPracticeHistory,
            reason: correction.rationale, correctedDerivedCredit: correction.correctedCredit, supersedesDispositionID: nil)
    }

    private let integralPrompt = "If F prime equals f, what is the definite integral of f from a to b?"
    private func option(_ id: String, _ text: String) -> NFChoiceOption { .init(id: id, text: text, accessibilityLabel: nil, distractorCode: nil) }
    private func rawText(_ response: String, prompt: String, answer: String, correct: Bool, credit: Double) -> NFHistoricalContentCorrectionInput {
        var input = NFHistoricalContentCorrectionInput(attemptID: "original-attempt", itemID: "old-item", templateID: "nf.fallback.retrieval.practice.v3.short-answer", originalScoringVersion: 7,
            prompt: prompt, rawResponse: response, originalExpectedAnswer: answer, originalIsCorrect: correct, originalCredit: credit)
        input.responseFormatRaw = "shortText"
        input.generatorVersion = 3
        return input
    }
    private func evidence(_ item: NFExercise, response: NFExerciseResponse, correct: Bool, credit: Double, scoringVersion: Int = 7) throws -> NFHistoricalContentCorrectionInput {
        var input = NFHistoricalContentCorrectionInput(attemptID: "original-attempt", itemID: item.id, templateID: item.templateID, originalScoringVersion: scoringVersion,
            prompt: item.prompt, rawResponse: String(decoding: try JSONEncoder().encode(response), as: UTF8.self), originalExpectedAnswer: "Original retained key", originalIsCorrect: correct, originalCredit: credit)
        input.generatorVersion = 3
        input.responseFormatRaw = response.responseFormatRaw
        input.exactSnapshot = item
        input.snapshotVerifiedAsOriginal = true
        return input
    }
    private func snapshot(_ interaction: NFExerciseInteraction, family: String = "fixture", prompt: String = "Original question", representations: [NFExerciseRepresentation] = []) throws -> NFExercise {
        // Generator supplies only unrelated structural boilerplate; the audited
        // prompt, response contract, version and stimulus are explicit fixtures.
        let base = try NFFallbackExerciseGenerator.generate(.init(seed: 91, index: 0, lab: .mentalMath, purpose: .practice))
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(base)) as? [String: Any])
        object["id"] = "old-item"
        object["templateID"] = "nf.fallback.fixture.v3." + family
        object["generatorVersion"] = 3
        object["prompt"] = prompt
        object["contractMetadata"] = nil
        object["interaction"] = try JSONSerialization.jsonObject(with: JSONEncoder().encode(interaction))
        object["representations"] = try JSONSerialization.jsonObject(with: JSONEncoder().encode(representations))
        return try JSONDecoder().decode(NFExercise.self, from: JSONSerialization.data(withJSONObject: object))
    }
}
